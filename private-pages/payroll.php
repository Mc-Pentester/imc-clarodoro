<?php
require_once __DIR__ . '/../config/page_auth.php';
imcRequirePageAccess('paies.read', 'PDG', $pdo ?? null);
?>
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Gestion des paies — Clarodaro</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f3f6fa;color:#172033;font:16px system-ui,Arial,sans-serif}header{background:#12355b;color:white;padding:20px;text-align:center}header h1{margin:0 0 5px}nav{display:flex;justify-content:center;gap:8px;flex-wrap:wrap;background:white;padding:12px}nav a{padding:9px 13px;border-radius:7px;background:#e8eef6;color:#12355b;text-decoration:none;font-weight:650}.wrap{max-width:1250px;margin:24px auto;padding:0 14px}.card{background:white;border:1px solid #dce4ee;border-radius:12px;padding:18px;margin:16px 0;box-shadow:0 2px 8px #12355b0b}.controls{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:14px;align-items:end}label{display:grid;gap:6px;font-weight:650}input,select{width:100%;min-height:40px;padding:8px;border:1px solid #b8c5d4;border-radius:7px;font:inherit}button{border:0;border-radius:7px;padding:9px 13px;background:#176b45;color:white;font:inherit;font-weight:650;cursor:pointer}button:disabled{opacity:.5;cursor:wait}.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse;min-width:850px;margin-top:12px}th,td{padding:9px;border:1px solid #dbe2ea;text-align:left}th{background:#12355b;color:white}.amount{max-width:125px}.muted{color:#64748b;font-size:14px}.message{display:none;padding:12px;border-radius:8px;margin:12px 0}.message.success,.message.error{display:block}.message.success{background:#dcfce7;color:#166534}.message.error{background:#fee2e2;color:#991b1b}.summary{display:flex;gap:16px;flex-wrap:wrap}.summary strong{color:#12355b}.empty{text-align:center;color:#64748b;padding:20px}@media(max-width:650px){.card{padding:13px}.controls{grid-template-columns:1fr}}
</style>
</head>
<body>
<header><h1>Gestion des paies du personnel</h1><div>Institution Mixte Clarodaro</div></header>
<nav><a href="PDG.html">Tableau de bord PDG</a><a href="personnel.html">Personnel</a><a href="payroll-recovery.html">Reprise des paies historiques</a></nav>
<main class="wrap">
<div id="message" class="message" role="status" aria-live="polite"></div>
<section class="card">
<h2>Créer les paies du mois</h2>
<p class="muted">Sélectionnez l'année scolaire et le mois, saisissez les montants pour chaque membre du personnel, puis enregistrez chaque paie. Les enregistrements sont conservés dans PostgreSQL. Une paie existante pour la même personne, la même année et le même mois sera mise à jour, pas dupliquée.</p>
<div class="controls">
<label>Année scolaire<select id="year"><option value="">Chargement…</option></select></label>
<label>Mois<select id="month"><option value="1">Janvier</option><option value="2">Février</option><option value="3">Mars</option><option value="4">Avril</option><option value="5">Mai</option><option value="6">Juin</option><option value="7">Juillet</option><option value="8">Août</option><option value="9">Septembre</option><option value="10">Octobre</option><option value="11">Novembre</option><option value="12">Décembre</option></select></label>
</div>
<div class="summary"><span>Personnel actif : <strong id="staffCount">—</strong></span><span>Paies enregistrées pour le mois : <strong id="savedCount">—</strong></span><span>Total net enregistré : <strong id="totalNet">—</strong></span></div>
<div class="table-wrap"><table><thead><tr><th>#</th><th>Nom et prénom</th><th>Fonction</th><th>Salaire de base</th><th>Primes</th><th>Déductions</th><th>Net</th><th>Statut</th><th>Action</th></tr></thead><tbody id="payrollRows"><tr><td colspan="9" class="empty">Chargement…</td></tr></tbody></table></div>
</section>
<section class="card">
<h2>Historique des paies enregistrées</h2>
<div class="table-wrap"><table><thead><tr><th>Personnel</th><th>Année</th><th>Mois</th><th>Base</th><th>Primes</th><th>Déductions</th><th>Net</th><th>Statut</th><th>Enregistrée le</th></tr></thead><tbody id="historyRows"><tr><td colspan="9" class="empty">Chargement…</td></tr></tbody></table></div>
</section>
</main>
<script src="/auth.js"></script>
<script>
"use strict";
const months=["","Janvier","Février","Mars","Avril","Mai","Juin","Juillet","Août","Septembre","Octobre","Novembre","Décembre"];
let staff=[], entries=[];
const el=id=>document.getElementById(id);
const money=n=>Number(n||0).toLocaleString("fr-HT",{minimumFractionDigits:2,maximumFractionDigits:2})+" HTG";
function showMessage(message,type){el("message").textContent=message;el("message").className="message "+type;}
async function request(url,options={}){const response=await fetch(url,{credentials:"same-origin",cache:"no-store",headers:{Accept:"application/json","Content-Type":"application/json",...(options.headers||{})},...options});let data={};try{data=await response.json();}catch(_){}if(!response.ok||!data.success)throw new Error(data.error||data.message||"La requête a échoué.");return data;}
function statusLabel(value){return ({PAID:"Payée",PARTIAL:"Partielle",UNPAID:"Non payée"})[value]||value;}
function render(){
 const month=Number(el("month").value),year=el("year").value;
 const current=entries.filter(x=>Number(x.payroll_month)===month);
 const byStaff=new Map(current.map(x=>[String(x.staff_id),x]));
 const tbody=el("payrollRows");tbody.replaceChildren();
 if(!staff.length){tbody.innerHTML='<tr><td colspan="9" class="empty">Aucun membre du personnel actif. Ajoutez d’abord le personnel.</td></tr>';}
 staff.forEach((person,index)=>{
  const old=byStaff.get(String(person.id));const tr=document.createElement("tr");
  const name=[person.first_name,person.last_name].filter(Boolean).join(" ");
  const cells=[String(index+1),name,person.function_name||"—"];
  cells.forEach(value=>{const td=document.createElement("td");td.textContent=value;tr.appendChild(td);});
  const values=[old?old.base_amount:0,old?old.bonus_amount:0,old?old.deduction_amount:0];
  ["base","bonus","deduction"].forEach((field,i)=>{const td=document.createElement("td"),input=document.createElement("input");input.type="number";input.min="0";input.step="0.01";input.className="amount";input.id=field+"-"+person.id;input.value=String(values[i]);input.setAttribute("aria-label",field+" "+name);td.appendChild(input);tr.appendChild(td);});
  const net=document.createElement("td");net.id="net-"+person.id;net.textContent=money(Math.max(0,values[0]+values[1]-values[2]));tr.appendChild(net);
  const statusCell=document.createElement("td"),select=document.createElement("select");select.id="status-"+person.id;[["UNPAID","Non payé"],["PARTIAL","Partiel"],["PAID","Payé"]].forEach(([v,t])=>select.add(new Option(t,v)));select.value=old?old.status:"UNPAID";statusCell.appendChild(select);tr.appendChild(statusCell);
  const action=document.createElement("td"),button=document.createElement("button");button.textContent=old?"Mettre à jour":"Enregistrer";button.addEventListener("click",()=>save(person,button));action.appendChild(button);tr.appendChild(action);
  ["base","bonus","deduction"].forEach(field=>el(field+"-"+person.id).addEventListener("input",()=>{const a=Number(el("base-"+person.id).value||0),b=Number(el("bonus-"+person.id).value||0),d=Number(el("deduction-"+person.id).value||0);el("net-"+person.id).textContent=money(Math.max(0,a+b-d));}));
  tbody.appendChild(tr);
 });
 const total=current.reduce((sum,x)=>sum+Number(x.net_amount||0),0);
 el("staffCount").textContent=String(staff.length);el("savedCount").textContent=String(current.length);el("totalNet").textContent=money(total);
 const history=el("historyRows");history.replaceChildren();
 if(!entries.length){history.innerHTML='<tr><td colspan="9" class="empty">Aucune paie enregistrée pour cette année scolaire.</td></tr>';return;}
 entries.slice().sort((a,b)=>Number(b.payroll_month)-Number(a.payroll_month)||String(a.last_name).localeCompare(String(b.last_name))).forEach(x=>{const tr=document.createElement("tr");const values=[[x.first_name,x.last_name].filter(Boolean).join(" "),x.school_year_label,months[Number(x.payroll_month)]||x.payroll_month,money(x.base_amount),money(x.bonus_amount),money(x.deduction_amount),money(x.net_amount),statusLabel(x.status),x.recorded_at?new Date(x.recorded_at).toLocaleString("fr-FR"):"—"];values.forEach(v=>{const td=document.createElement("td");td.textContent=String(v);tr.appendChild(td);});history.appendChild(tr);});
}
async function save(person,button){
 const year=el("year").value,month=Number(el("month").value);if(!year){showMessage("Sélectionnez une année scolaire.","error");return;}
 const value=id=>Number(el(id+"-"+person.id).value);
 const base=value("base"),bonuses=value("bonus"),deductions=value("deduction");
 if([base,bonuses,deductions].some(x=>!Number.isFinite(x)||x<0)){showMessage("Les montants doivent être des nombres positifs ou nuls.","error");return;}
 button.disabled=true;
 try{await request("/api/payroll/index.php",{method:"POST",body:JSON.stringify({staff_id:String(person.id),school_year_label:year,month,base,bonuses,deductions,status:el("status-"+person.id).value})});await loadEntries();showMessage("Paie de "+[person.first_name,person.last_name].filter(Boolean).join(" ")+" enregistrée dans PostgreSQL.","success");}
 catch(error){showMessage(error.message,"error");}finally{button.disabled=false;}
}
async function loadEntries(){const year=el("year").value;if(!year)return;const data=await request("/api/payroll/index.php?school_year_label="+encodeURIComponent(year));entries=Array.isArray(data.payroll)?data.payroll:[];render();}
async function init(){
 const user=await IMCAuth.verifySession();
 if(!user||user.role!=="PDG"||!IMCAuth.hasPermission("paies.read")){location.replace("PDG.html");return;}
 const [years,people]=await Promise.all([request("/api/school-years/index.php"),request("/api/personnel/index.php")]);
 const active=(years.schoolYears||[]).filter(x=>x&&x.status!=="ARCHIVED");
 el("year").replaceChildren();active.forEach(x=>el("year").add(new Option(x.label,x.label)));
 if(!active.length)throw new Error("Aucune année scolaire n'est configurée. Créez d'abord une année scolaire.");
 const selected=active.find(x=>x.status==="ACTIVE")||active[0];el("year").value=selected.label;
 staff=Array.isArray(people.personnel)?people.personnel:[];
 el("month").value=String(new Date().getMonth()+1);
 await loadEntries();
}
el("year").addEventListener("change",()=>loadEntries().catch(e=>showMessage(e.message,"error")));
el("month").addEventListener("change",render);
document.addEventListener("DOMContentLoaded",()=>init().catch(e=>showMessage(e.message,"error")));
</script>
</body></html>
