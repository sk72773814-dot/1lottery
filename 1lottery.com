<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Mini Lottery Demo (A to Z)</title>
  <style>
    body { background: #f3faff; font-family: Arial,sans-serif; padding: 2em; max-width: 520px; margin:auto;}
    h2 { color: #234F6D; }
    input[type=text], input[type=password], input[type=number] {
      padding:6px; margin:5px; border:1px solid #aed2f6; border-radius:4px;width:120px;}
    .panel { border:1px solid #aed2f6; border-radius:7px; padding:1em; margin:1em 0; background:#fff;}
    .hidden { display: none; }
    #betForm input[type=number] {width:36px;}
    button {padding:7px 16px; margin:6px 2px; background:#2376aa; color:#fff; border:none; border-radius:4px;cursor:pointer;}
    #adminPanel {font-size:0.95em;}
    .small {font-size:0.93em;color:#666;}
    .table { width:100%; border-collapse:collapse; }
    .table td, .table th {border:1px solid #eef; padding:4px;}
  </style>
</head>
<body>

  <h2>MINI LOTTERY Game ⚡</h2>
  <div id="authPanel" class="panel">
    <b>User Login/Register</b><br>
    Username: <input type="text" id="username"> 
    Password: <input type="password" id="password">
    <button onclick="registerUser()">Register</button>
    <button onclick="loginUser()">Login</button>
    <div id="authMsg" class="small"></div>
  </div>
  
  <div id="gamePanel" class="panel hidden">
    <b>Welcome, <span id="userNameShow"></span>!</b>&nbsp;&nbsp;
    <button onclick="logoutUser()" style="float:right">Logout</button><br>
    <span>Balance: <b id="walletShow">0</b> Coins&nbsp;&nbsp;
    <button onclick="addFunds()">+Add Coins</button>
    </span>
    <hr>
    <div>
      <b>Place Bet (10 coins):</b>
      <form id="betForm">
        <span>Select 6 numbers (1-60):</span><br>
        <input type="number" min="1" max="60" required>
        <input type="number" min="1" max="60" required>
        <input type="number" min="1" max="60" required>
        <input type="number" min="1" max="60" required>
        <input type="number" min="1" max="60" required>
        <input type="number" min="1" max="60" required>
        <button type="submit">Bet Now</button>
      </form>
      <div class="small" id="betMsg"></div>
    </div>
    <div id="drawResult" class="panel" style="background:#eaf7ed; margin-top:12px"></div>
    <div>
      <hr>
      <details>
        <summary><b>🔍Bet History</b></summary>
        <div id="betHistory"></div>
      </details>
    </div>
    <span class="small">Lottery draw happens on every bet for demo. Multiple users can register in same browser.<br>
    <a href="#" onclick="showAdminPanel();return false;">(Admin Panel)</a></span>
  </div>
  
  <!-- Admin (Demo) -->
  <div id="adminPanel" class="panel hidden">
    <b>Admin Panel</b> (<a href="#" onclick="closeAdminPanel();return false;">Close</a>)<br>
    <i>Total registered users: <span id="adminUserCount"></span></i><br>
    <i>Total bets placed: <span id="adminBets"></span></i><br>
    <b>Last winning number draw:</b>
    <div id="lastDraw"></div>
    <table class="table"><thead><tr><th>User</th><th>Bet</th><th>Matches</th><th>+/-</th></tr></thead>
      <tbody id="adminBetsList"></tbody>
    </table>
  </div>

<script>
let users = JSON.parse(localStorage.getItem("lotteryUsers")||"{}");
let bets = JSON.parse(localStorage.getItem("lotteryBets")||"[]");
let current = JSON.parse(localStorage.getItem("lotteryCurrent")||"null");

function saveDB() {
  localStorage.setItem("lotteryUsers",JSON.stringify(users));
  localStorage.setItem("lotteryBets",JSON.stringify(bets));
  localStorage.setItem("lotteryCurrent",JSON.stringify(current));
}

// Registration
function registerUser(){
  let uname = document.getElementById('username').value.trim();
  let pass = document.getElementById('password').value;
  if(!(uname && pass)) { authMsg("Enter both fields."); return;}
  if(users[uname]) {authMsg("Username already taken!");return;}
  users[uname] = {password:pass, wallet:50};
  saveDB();
  authMsg("Registered! Login to play.");
}
function authMsg(txt){document.getElementById('authMsg').textContent=txt;}
function loginUser(){
  let uname = document.getElementById('username').value.trim();
  let pass = document.getElementById('password').value;
  if(!users[uname] || users[uname].password!==pass){authMsg("Wrong username or password!");return;}
  current = uname; saveDB();
  showGame();
}
function logoutUser(){ current=null; saveDB(); location.reload();}

// Topup
function addFunds(){
  users[current].wallet += 100;
  saveDB();
  showGame();
}

// Game
function showGame(){
  document.getElementById('authPanel').classList.add("hidden");
  document.getElementById('gamePanel').classList.remove("hidden");
  document.getElementById('userNameShow').textContent=current;
  document.getElementById('walletShow').textContent=users[current].wallet;
  drawHistory();
  document.getElementById('drawResult').textContent="";
}
function drawHistory(){
  const userBets = bets.filter(b=>b.user===current);
  if(!userBets.length) document.getElementById('betHistory').innerHTML = "No bets yet.";
  else
    document.getElementById('betHistory').innerHTML = 
      `<table class="table"><tr><th>Numbers</th><th>Win</th><th>+/-</th></tr>` +
      userBets.map(b=>`<tr><td>${b.nums.join(",")}</td>
      <td>${b.result} (${b.matched})</td>
      <td>${b.prize}</td></tr>`).join("")+"</table>";
  document.getElementById('adminUserCount').textContent = Object.keys(users).length;
  document.getElementById('adminBets').textContent = bets.length;
}

// Bet Process
document.getElementById('betForm').onsubmit = function(e){
  e.preventDefault();
  let ins = this.querySelectorAll('input');
  let nums = Array.from(ins).map(i=>+i.value);
  if(new Set(nums).size!==6 || nums.some(n=>n<1||n>60)){
    document.getElementById('betMsg').textContent="Pick 6 UNIQUE numbers (1-60)!";
    return;
  }
  if(users[current].wallet<10){
    document.getElementById('betMsg').textContent="Not enough coins!";
    return;
  }
  users[current].wallet -= 10;
  let win = getLuckyDraw();
  let matched = nums.filter(n=>win.includes(n));
  let prize = 0, result = "Lose";
  if(matched.length===6){prize=500; result="JACKPOT";}
  else if(matched.length>=3){prize=50; result="Small";}
  users[current].wallet += prize;
  bets.push({user:current, nums:nums, win:win, matched:matched.length, prize:prize-10, result:result, time:Date.now()});
  saveDB();
  showGame();
  document.getElementById('drawResult').innerHTML = 
    `<b>Draw:</b> ${win.join(", ")}<br>`+
    `<b>Matched:</b> ${matched.join(", ")}<br>`+
    `<b>Result:</b> <span style="color:${result=="JACKPOT"?"green":result=="Small"?"blue":"gray"}">${result}</span>`+
    ` &nbsp; <b>Prize:</b> ${prize-10}`;
  document.getElementById('betMsg').textContent="";
  document.getElementById('betForm').reset();
}

// Random 6 numbers 1-60
function getLuckyDraw(){
  let arr=[];
  while(arr.length<6){let r=1+Math.floor(Math.random()*60);if(!arr.includes(r))arr.push(r);}
  return arr.sort((a,b)=>a-b);
}

// Admin
function showAdminPanel(){
  document.getElementById('adminPanel').classList.remove('hidden');
  document.getElementById('adminUserCount').textContent = Object.keys(users).length;
  document.getElementById('adminBets').textContent = bets.length;
  let last = bets.length? bets[bets.length-1].win.join(", ") : "-";
  document.getElementById('lastDraw').textContent = last;
  document.getElementById('adminBetsList').innerHTML = bets.slice(-10).reverse().map(b=>
    `<tr><td>${b.user}</td><td>${b.nums.join(",")}</td><td>${b.matched}</td><td>${b.prize}</td></tr>`
  ).join("");
}
function closeAdminPanel(){
  document.getElementById('adminPanel').classList.add('hidden');
}
</script>
</body>
</html>