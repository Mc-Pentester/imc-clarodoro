<?php
require_once __DIR__ . '/../config/page_auth.php';
imcRequirePageAccess('parents.read', null, $pdo ?? null);
?>
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Parents et responsables — Clarodaro</title>
<style>
*{box-sizing:border-box}body{margin:0;padding:18px;background:#f4f6f8;color:#1f2937;font:15px Arial,sans-serif}
header,.card{max-width:1180px;margin:0 auto 16px;background:#fff;border-radius:12px;padding:18px;box-shadow:0 2px 9px #0000000d}
header{text-align:center}h1,h2{color:#1f4e78;margin-top:0}.menu{max-width:1180px;margin:0 auto 16px;display:flex;gap:8px;flex-wrap:wrap}.menu a,.btn{display:inline-block;border:0;border-radius:7px;padding:10px 13px;background:#1f4e78;color:white;text-decoration:none;cursor:pointer;font-weight:600}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:12px}label{display:block;font-weight:600;margin:8px 0 4px}input,select{width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:7px;font:inherit}
.toolbar{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-bottom:12px}.toolbar input{flex:1;min-width:190px}.muted{color:#64748b}.message{padding:10px;border-radius:7px;margin:10px 0;display:none}.error{background:#fee2e2;color:#991b1b}.success{background:#dcfce7;color:#166534}
table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:10px;border-bottom:1px solid #e2e8f0;vertical-align:top}th{background:#f8fafc}.actions{display:flex;gap:6px;flex-wrap:wrap}.btn.secondary{background:#475569}.btn.danger{background:#b91c1c}.child{padding:5px 0}.empty{padding:18px;text-align:center;color:#64748b}
@media(max-width:640px){body{padding:10px}.card,header{padding:13px;overflow-x:auto}table{min-width:650px}.menu a{flex:1;text-align:center}}
</style>
</head>
<body>
<header><img src="/logo-clarodaro.png" alt="Clarodaro" style="width:58px;height:58px;object-fit:contain"><h1>Parents et responsables</h1><p class="muted">Fiches parentales indépendantes et associations avec plusieurs élèves</p></header>
<nav class="menu">
<a href="/secure-page.php?page=index.html">Élèves</a><a href="/secure-page.php?page=parents.html">Parents et responsables</a><a href="/secure-page.php?page=finances.html">Finances</a><a href="/secure-page.php?page=personnel.html">Personnel</a><a href="/secure-page.php?page=pdg.html">PDG</a>
</nav>
<main>
<section class="card">
<h2 id="formTitle">Créer une fiche parent</h2>
<div id="message" class="message" role="status"></div>
<form id="parentForm">
<input type="hidden" id="parentId">
<div class="grid">
<div><label for="firstName">Prénom *</label><input id="firstName" maxlength="150" required></div>
<div><label for="lastName">Nom *</label><input id="lastName" maxlength="150" required></div>
<div><label for="ninu">NINU (10 chiffres)</label><input id="ninu" maxlength="10" inputmode="numeric" pattern="[0-9]{10}"></div>
<div><label for="phone">Téléphone</label><input id="phone" type="tel" maxlength="50"></div>
<div><label for="email">Courriel</label><input id="email" type="email" maxlength="255"></div>
<div><label for="address">Adresse</label><input id="address" maxlength="2000"></div>
</div>
<p class="muted">Si le NINU existe déjà, la fiche correspondante est réutilisée. Sans NINU, vérifiez les fiches existantes avant de créer un doublon.</p>
<div class="actions"><button class="btn" type="submit">Enregistrer la fiche</button><button class="btn secondary" type="button" id="resetForm">Nouvelle fiche</button></div>
</form>
</section>
<section class="card">
<h2>Associer un parent à un élève</h2>
<p class="muted">Une même fiche parent peut être liée à plusieurs élèves. Retirer une association ne supprime jamais la fiche parent.</p>
<form id="linkForm">
<div class="grid">
<div><label for="linkParent">Parent *</label><select id="linkParent" required><option value="">Choisir un parent</option></select></div>
<div><label for="linkStudent">Élève *</label><select id="linkStudent" required><option value="">Choisir un élève</option></select></div>
<div><label for="relationship">Lien de parenté</label><select id="relationship"><option value="FATHER">Père</option><option value="MOTHER">Mère</option><option value="GUARDIAN">Tuteur / tutrice</option><option value="OTHER">Autre responsable</option></select></div>
<div><label for="primary">Responsable principal</label><select id="primary"><option value="false">Non</option><option value="true">Oui</option></select></div>
</div>
<p><button class="btn" type="submit">Associer à l'élève</button></p>
</form>
</section>
<section class="card">
<h2>Répertoire des parents</h2>
<div class="toolbar"><input id="search" type="search" placeholder="Rechercher par nom, téléphone, NINU ou courriel"><button class="btn secondary" id="refresh" type="button">Actualiser</button></div>
<div style="overflow-x:auto"><table><thead><tr><th>Parent</th><th>Coordonnées</th><th>Enfants associés</th><th>Actions</th></tr></thead><tbody id="parentsRows"><tr><td colspan="4" class="empty">Chargement…</td></tr></tbody></table></div>
</section>
</main>
<script src="/auth.js"></script>
<script>
(function(){
'use strict';
const $=id=>document.getElementById(id);
let parents=[],students=[];
function csrf(){return window.IMCAuth&&typeof IMCAuth.getCsrfToken==='function'?IMCAuth.getCsrfToken():'';}
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function message(text,isError){const el=$('message');el.textContent=text;el.className='message '+(isError?'error':'success');el.style.display='block';}
async function request(url,options){const response=await fetch(url,Object.assign({credentials:'same-origin',headers:{'Accept':'application/json'}},options||{}));const data=await response.json();if(!response.ok||!data.success)throw new Error(data.error||data.message||'Opération impossible');return data;}
function reset(){ $('parentForm').reset();$('parentId').value='';$('formTitle').textContent='Créer une fiche parent';}
function relationshipLabel(type){
 switch(type){case 'FATHER':return 'Père';case 'MOTHER':return 'Mère';case 'GUARDIAN':return 'Tuteur';case 'OTHER':return 'Autre';default:return 'Responsable';}
}
function render(){
 const term=$('search').value.trim().toLocaleLowerCase('fr');
 const rows=parents.filter(p=>[p.first_name,p.last_name,p.phone,p.email,p.ninu].join(' ').toLocaleLowerCase('fr').includes(term));
 $('parentsRows').innerHTML=rows.length?rows.map(p=>{
 const children=(p.children||[]).length
  ? (p.children||[]).map(c=>'<div class="child">'+esc(c.first_name+' '+c.last_name)+' <span class="muted">('+esc(relationshipLabel(c.relationship_type))+(c.is_primary?', principal':'')+')</span><button class="btn danger" type="button" data-unlink="'+esc(p.id)+'" data-student="'+esc(c.student_id)+'">Dissocier</button></div>').join('')
  : '<span class="muted">Aucun élève associé</span>';
 return '<tr><td><strong>'+esc(p.first_name+' '+p.last_name)+'</strong><br><span class="muted">NINU : '+esc(p.ninu||'—')+'</span></td><td>'+esc(p.phone||'—')+'<br>'+esc(p.email||'—')+'<br>'+esc(p.address||'')+'</td><td>'+children+'</td><td><div class="actions"><button class="btn secondary" type="button" data-edit="'+esc(p.id)+'">Modifier</button></div></td></tr>';
 }).join(''):'<tr><td colspan="4" class="empty">Aucune fiche parent trouvée.</td></tr>';
 $('linkParent').innerHTML='<option value="">Choisir un parent</option>'+parents.map(p=>'<option value="'+esc(p.id)+'">'+esc(p.last_name+' '+p.first_name+(p.ninu?' — '+p.ninu:''))+'</option>').join('');
 $('linkStudent').innerHTML='<option value="">Choisir un élève</option>'+students.map(s=>'<option value="'+esc(s.id)+'">'+esc(s.last_name+' '+s.first_name+' — '+s.matricule)+'</option>').join('');
}
async function load(){try{const data=await request('/api/parents/index.php');parents=data.parents||[];students=data.students||[];render();}catch(e){$('parentsRows').innerHTML='<tr><td colspan="4" class="empty">'+esc(e.message)+'</td></tr>';}}
$('parentForm').addEventListener('submit',async e=>{e.preventDefault();const id=$('parentId').value;const payload={first_name:$('firstName').value.trim(),last_name:$('lastName').value.trim(),ninu:$('ninu').value.trim(),phone:$('phone').value.trim(),email:$('email').value.trim(),address:$('address').value.trim()};try{await request(id?'/api/parents/index.php?id='+encodeURIComponent(id):'/api/parents/index.php',{method:id?'PATCH':'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf()},body:JSON.stringify(payload)});message(id?'Fiche parent mise à jour.':'Fiche parent enregistrée.');reset();await load();}catch(err){message(err.message,true);}});
$('linkForm').addEventListener('submit',async e=>{e.preventDefault();try{await request('/api/parents/index.php',{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf()},body:JSON.stringify({action:'link',parent_id:$('linkParent').value,student_id:$('linkStudent').value,relationship_type:$('relationship').value,is_primary:$('primary').value==='true'})});message('Parent associé à l’élève.');await load();}catch(err){message(err.message,true);}});
$('parentsRows').addEventListener('click',async e=>{const edit=e.target.closest('[data-edit]');const unlink=e.target.closest('[data-unlink]');if(edit){const p=parents.find(x=>x.id===edit.dataset.edit);if(!p)return;$('parentId').value=p.id;$('firstName').value=p.first_name||'';$('lastName').value=p.last_name||'';$('ninu').value=p.ninu||'';$('phone').value=p.phone||'';$('email').value=p.email||'';$('address').value=p.address||'';$('formTitle').textContent='Modifier la fiche parent';window.scrollTo({top:0,behavior:'smooth'});}if(unlink){if(!confirm('Dissocier ce parent de cet élève ? La fiche parent sera conservée.'))return;try{await request('/api/parents/index.php?parent_id='+encodeURIComponent(unlink.dataset.unlink)+'&student_id='+encodeURIComponent(unlink.dataset.student),{method:'DELETE',headers:{'X-CSRF-Token':csrf()}});message('Association retirée. La fiche parent est conservée.');await load();}catch(err){message(err.message,true);}}});
$('search').addEventListener('input',render);$('refresh').addEventListener('click',load);$('resetForm').addEventListener('click',reset);
document.addEventListener('DOMContentLoaded',async()=>{if(window.IMCAuth&&!(await IMCAuth.verifySession())){location.replace('/');return;}load();});
})();
</script>
</body>
</html>
