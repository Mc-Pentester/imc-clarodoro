<?php
declare(strict_types=1);
require_once __DIR__ . '/../config/page_auth.php';
require_once __DIR__ . '/../config/auth.php';
$pdo = getDatabaseConnection();
imcRequirePageAccess('whatsapp.message.send', null, $pdo);
$csrfToken = htmlspecialchars(generateCsrfToken(), ENT_QUOTES, 'UTF-8');
?>
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="csrf-token" content="<?= $csrfToken ?>">
<title>WhatsApp | Clarodaro</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f3f6f8;color:#17212b;font:16px Arial,sans-serif}header{background:#075e54;color:#fff;padding:22px max(18px,calc((100% - 900px)/2))}header h1{margin:0 0 6px;font-size:26px}header p{margin:0}main{max-width:900px;margin:24px auto;padding:0 16px}.card{background:#fff;border:1px solid #dce4e8;border-radius:12px;padding:22px;margin-bottom:18px}h2{margin:0 0 16px;color:#075e54;font-size:20px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}label{display:block;font-weight:700;font-size:14px;margin-bottom:6px}input,select,textarea{width:100%;padding:11px;border:1px solid #b8c5cc;border-radius:7px;font:inherit}textarea{min-height:110px;resize:vertical}.wide{grid-column:1/-1}button{border:0;border-radius:7px;padding:12px 18px;background:#087f5b;color:#fff;font-weight:700;cursor:pointer}button:disabled{opacity:.55;cursor:not-allowed}.hint{color:#52616b;font-size:13px;line-height:1.5}.notice{padding:12px;border-radius:8px;background:#eaf4ff;color:#17436a;margin-bottom:16px;line-height:1.5}.result{padding:12px;border-radius:8px;background:#edf7f1;margin-top:14px;white-space:pre-wrap;overflow-wrap:anywhere}.error{background:#fff0f0;color:#8a1717}.actions{display:flex;gap:10px;flex-wrap:wrap}.mode{font-size:13px;font-weight:700;color:#52616b;text-transform:uppercase;letter-spacing:.04em;margin-bottom:8px}@media(max-width:650px){.grid{grid-template-columns:1fr}.wide{grid-column:auto}.card{padding:16px}}
</style>
</head>
<body>
<header><h1>WhatsApp — Clarodaro</h1><p>Choisissez l’envoi manuel ou l’envoi réel via Meta</p></header>
<main>
<div class="notice"><strong>Deux modes disponibles :</strong> l’envoi manuel ouvre WhatsApp avec le numéro et le texte préremplis ; vous vérifiez puis appuyez vous-même sur Envoyer. L’envoi Meta transmet un modèle approuvé depuis le serveur Clarodaro. Les deux modes vérifient le consentement actif et sont journalisés. Une préparation manuelle n’est pas une preuve d’envoi.</div>
<section class="card">
<h2>Destinataire et autorisation</h2>
<div class="grid">
<div class="wide"><label for="parentSearch">Rechercher un parent par nom, téléphone ou nom de son élève</label><input id="parentSearch" type="search" autocomplete="off" placeholder="Nom du parent, téléphone ou nom de l’élève…" aria-describedby="parentSearchHint"><p id="parentSearchHint" class="hint">Saisissez au moins 2 caractères du nom du parent, de son téléphone ou du nom de son élève. Seuls les parents liés à cet élève et ayant un consentement actif pour la finalité choisie apparaissent.</p><div id="parentResults" class="result" hidden role="listbox" aria-label="Résultats de recherche des parents"></div><div id="selectedParent" class="result" hidden aria-live="polite"></div><input id="parent_id" type="hidden" required></div>
<div><label for="purpose">Finalité / consentement</label><select id="purpose"><option value="ATTENDANCE">Présence / absence</option><option value="RESULTS_AVAILABLE">Résultats disponibles</option><option value="PAYMENT_REMINDER">Rappel de paiement</option><option value="GENERAL">Message général</option></select></div>
</div>
<p class="hint">Les deux modes sont actuellement destinés aux parents disposant d’un consentement actif pour la finalité choisie.</p>
</section>
<section class="card">
<div class="mode">Diffusion à une classe</div>
<h2>Envoyer un message aux parents d’une classe</h2>
<p class="hint">Clarodaro récupère les élèves inscrits dans la classe et l’année scolaire sélectionnées, puis déduplique les parents. Seuls les parents ayant un consentement actif pour la finalité choisie sont proposés. Les autres sont exclus.</p>
<div class="grid">
<div><label for="broadcastSchoolYear">Année scolaire active</label><select id="broadcastSchoolYear"><option value="">Chargement…</option></select></div>
<div><label for="broadcastClass">Classe active</label><select id="broadcastClass"><option value="">Choisir une classe</option></select></div>
<div class="wide actions"><button type="button" id="loadClassParents">Charger les parents autorisés</button><label style="display:flex;align-items:center;gap:8px;font-weight:normal"><input id="selectAllClassParents" type="checkbox" checked style="width:auto"> Sélectionner tous les parents autorisés</label></div>
</div>
<div id="classRecipientsSummary" class="result" hidden aria-live="polite"></div>
<div id="classParentList" class="result" hidden></div>
<div class="actions" style="margin-top:12px">
<button type="button" id="manualBatchButton" disabled>Préparer les liens WhatsApp pour la classe</button>
<button type="button" id="metaBatchButton" disabled>Envoyer la classe via Meta</button>
</div>
<div id="classBatchResult" class="result" hidden aria-live="polite"></div>
<p class="hint">Mode manuel : Clarodaro prépare un lien par parent; vous ouvrez chaque conversation et appuyez vous-même sur Envoyer. Mode Meta : Clarodaro transmet les modèles approuvés un par un, sans ouvrir les conversations. L’acceptation par Meta n’est pas une preuve de livraison.</p>
</section>
<section class="card">
<div class="mode">Mode 1 · WhatsApp sur le poste</div>
<h2>Envoyer manuellement</h2>
<div class="grid">
<div class="wide"><label for="manual_message">Message à préparer</label><textarea id="manual_message" maxlength="4000" placeholder="Rédigez le message à envoyer au parent…" required></textarea></div>
<div class="wide actions"><button type="button" id="manualButton">Ouvrir WhatsApp pour vérifier et envoyer</button></div>
</div>
<div id="manualResult" class="result" hidden aria-live="polite"></div>
<p class="hint">Clarodaro vérifie à nouveau le consentement et journalise la préparation avant d’ouvrir WhatsApp. Le message prérempli figure dans l’URL WhatsApp : évitez les informations scolaires, médicales, disciplinaires ou financières sensibles.</p>
</section>
<section class="card">
<div class="mode">Mode 2 · Envoi serveur Meta</div>
<h2>Envoyer automatiquement via Meta</h2>
<div id="configStatus" class="result" aria-live="polite">Vérification de la configuration sécurisée du serveur…</div>
<p class="hint">Le jeton d’accès reste exclusivement dans le fichier protégé <code>C:\ProgramData\IMC-Clarodaro\config\.env</code>. Il n’est jamais transmis au navigateur.</p>
<div class="grid">
<div><label for="template_name">Modèle approuvé Meta</label><select id="template_name" required disabled><option value="">Chargement des modèles…</option></select></div>
<div><label for="language">Langue du modèle</label><input id="language" value="fr" maxlength="10" placeholder="fr ou fr_FR" required></div>
<div class="wide"><label for="parameters">Paramètres du corps (un paramètre par ligne, dans l’ordre du modèle)</label><textarea id="parameters" maxlength="12000" placeholder="Jean&#10;Lundi 16 novembre"></textarea><p class="hint">Laissez vide si le modèle n’a aucune variable. Les valeurs sont transmises à Meta comme paramètres texte du modèle approuvé.</p></div>
<div class="wide actions"><button type="button" id="sendButton" disabled>Envoyer réellement via Meta</button></div>
</div>
<div id="sendResult" class="result" hidden aria-live="polite"></div>
<p class="hint">L’acceptation par Meta ne confirme pas la livraison. Vérifiez la réception sur le téléphone destinataire et les statuts WhatsApp Business.</p>
</section>
</main>
<script>
const csrf=document.querySelector('meta[name="csrf-token"]').content,$=id=>document.getElementById(id);
let configReady=false;
function show(node,text,error=false){node.hidden=false;node.textContent=text;node.classList.toggle('error',error)}
function validParent(){const value=$('parent_id').value.trim();if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))throw Error('Recherchez puis sélectionnez un parent dans la liste.');return value}
let parentSearchTimer=null,parentSearchController=null;
function clearSelectedParent(){ $('parent_id').value=''; $('selectedParent').hidden=true; $('selectedParent').textContent=''; }
async function searchParents(){
  const q=$('parentSearch').value.trim(),results=$('parentResults');
  clearSelectedParent();
  if(q.length<2){results.hidden=true;results.textContent='';return}
  if(parentSearchController)parentSearchController.abort();
  parentSearchController=new AbortController();
  show(results,'Recherche des parents…');
  try{
    const url='/api/whatsapp/parents-search.php?purpose='+encodeURIComponent($('purpose').value)+'&q='+encodeURIComponent(q);
    const response=await fetch(url,{credentials:'same-origin',cache:'no-store',headers:{'Accept':'application/json'},signal:parentSearchController.signal});
    const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
    if(!response.ok||data.success!==true)throw Error(data.error||('Erreur HTTP '+response.status));
    results.replaceChildren();
    if(!Array.isArray(data.parents)||data.parents.length===0){show(results,'Aucun parent avec consentement actif trouvé pour cette recherche et cette finalité.');return}
    for(const parent of data.parents){
      const option=document.createElement('button');option.type='button';option.style.cssText='display:block;width:100%;text-align:left;margin:5px 0;background:#f0f7f4;color:#173b32;border:1px solid #c9ded5';
      const fullName=[parent.first_name,parent.last_name].filter(Boolean).join(' ');
      const studentNames=parent.student_names?' · Élève(s) : '+parent.student_names:'';
      option.textContent=fullName+' — '+parent.phone_e164+studentNames;
      option.setAttribute('role','option');
      option.addEventListener('click',()=>{
        $('parent_id').value=parent.id;
        $('selectedParent').textContent='Destinataire sélectionné : '+fullName+' · '+parent.phone_e164;
        $('selectedParent').hidden=false;results.hidden=true;results.replaceChildren();
      });
      results.appendChild(option);
    }
    results.hidden=false;
  }catch(error){if(error.name!=='AbortError')show(results,'Recherche impossible : '+error.message,true)}
}
$('parentSearch').addEventListener('input',()=>{clearTimeout(parentSearchTimer);parentSearchTimer=setTimeout(searchParents,250)});
$('purpose').addEventListener('change',()=>{if($('parentSearch').value.trim().length>=2)searchParents();else clearSelectedParent()});
async function loadConfig(){
  const status=$('configStatus');
  try{
    const response=await fetch('/api/whatsapp/send.php',{credentials:'same-origin',cache:'no-store',headers:{'Accept':'application/json'}});
    const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
    if(!response.ok||data.success!==true)throw Error(data.error||('Erreur HTTP '+response.status));
    const select=$('template_name');select.replaceChildren();
    for(const name of (data.templates||[])){const option=document.createElement('option');option.value=name;option.textContent=name;select.appendChild(option)}
    select.disabled=!data.configured;
    if(!data.configured||!data.templates?.length){
      show(status,'ENVOI META NON CONFIGURÉ. Le mode manuel reste disponible. Aucun faux envoi ne sera annoncé.',true);
      configReady=false;
    }else{
      show(status,'Configuration Meta prête. '+data.templates.length+' modèle(s) autorisé(s).');
      configReady=true;
    }
  }catch(error){show(status,'Impossible de vérifier la configuration Meta : '+error.message+'. Le mode manuel reste disponible.',true);configReady=false}
  $('sendButton').disabled=!configReady;
}
$('manualButton').addEventListener('click',async()=>{
  const out=$('manualResult');out.hidden=true;
  let popup=null;
  try{
    const parentId=validParent(),message=$('manual_message').value.trim();
    if(!message||message.length>4000)throw Error('Rédigez un message de 1 à 4000 caractères.');
    // Open synchronously to avoid popup blockers; navigate only after server-side revalidation.
    popup=window.open('about:blank','_blank');
    if(!popup)throw Error('Le navigateur a bloqué la fenêtre. Autorisez les fenêtres contextuelles puis réessayez.');
    popup.opener=null;$('manualButton').disabled=true;show(out,'Vérification du consentement et journalisation de la préparation…');
    const response=await fetch('/api/whatsapp/manual-preparations.php',{
      method:'POST',credentials:'same-origin',cache:'no-store',
      headers:{'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':csrf},
      body:JSON.stringify({parent_id:parentId,purpose:$('purpose').value,message})
    });
    const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
    if(!response.ok||data.success!==true||!/^\+[1-9][0-9]{7,14}$/.test(data.phone_e164||''))throw Error(data.error||'La vérification finale du consentement a échoué.');
    const digits=data.phone_e164.replace(/\D/g,'');
    popup.location.href='https://wa.me/'+digits+'?text='+encodeURIComponent(message);
    show(out,'Préparation journalisée (référence '+data.preparation_id+'). WhatsApp est ouvert. Vérifiez le destinataire et le texte, puis appuyez vous-même sur Envoyer. Clarodaro ne confirme pas l’envoi.');
  }catch(error){if(popup&&!popup.closed)popup.close();show(out,error.message||'Impossible de préparer le message.',true)}
  finally{$('manualButton').disabled=false}
});
function makeIdempotencyKey(){
  const bytes=new Uint8Array(16);crypto.getRandomValues(bytes);
  return 'clarodaro-'+Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
}
$('sendButton').addEventListener('click',async()=>{
  const out=$('sendResult');out.hidden=true;
  if(!configReady){show(out,'La configuration Meta n’est pas prête. Aucun envoi effectué.',true);return}
  let parentId;
  try{parentId=validParent()}catch(error){show(out,error.message,true);return}
  const templateName=$('template_name').value,language=$('language').value.trim();
  if(!templateName){show(out,'Choisissez un modèle approuvé.',true);return}
  if(!/^[a-z]{2,3}(?:_[A-Z]{2})?$/.test(language)){show(out,'Code de langue invalide.',true);return}
  const parameters=$('parameters').value.split(/\r?\n/).map(value=>value.trim()).filter(Boolean);
  $('sendButton').disabled=true;show(out,'Envoi de la demande à Meta…');
  try{
    const response=await fetch('/api/whatsapp/send.php',{
      method:'POST',credentials:'same-origin',cache:'no-store',
      headers:{'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':csrf},
      body:JSON.stringify({parent_id:parentId,purpose:$('purpose').value,template_name:templateName,language,parameters,idempotency_key:makeIdempotencyKey()})
    });
    const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
    if(!response.ok||data.success!==true)throw Error(data.error||('Erreur HTTP '+response.status)+(data.provider_error_code?' · Code Meta '+data.provider_error_code:''));
    show(out,'DEMANDE ACCEPTÉE PAR META.\nRéférence Clarodaro : '+data.message_log_id+'\nIdentifiant WhatsApp : '+data.provider_message_id+'\n'+data.message+'\nLa livraison doit être vérifiée dans le suivi WhatsApp Business.');
  }catch(error){show(out,'ÉCHEC DE L’ENVOI : '+error.message,true)}
  finally{$('sendButton').disabled=!configReady}
});
let classParents=[];
let classExcludedCount=0;
function selectedClassParents(){
  return classParents.filter(parent=>{
    const checkbox=document.querySelector('[data-class-parent="'+parent.parent_id+'"]');
    return checkbox&&checkbox.checked;
  });
}
function updateClassBatchButtons(){
  const count=selectedClassParents().length;
  $('manualBatchButton').disabled=count===0;
  $('metaBatchButton').disabled=count===0||!configReady;
}
async function loadClassOptions(){
  const yearSelect=$('broadcastSchoolYear'),classSelect=$('broadcastClass');
  try{
    const response=await fetch('/api/whatsapp/class-recipients.php',{credentials:'same-origin',cache:'no-store',headers:{'Accept':'application/json'}});
    const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
    if(!response.ok||data.success!==true)throw Error(data.error||('Erreur HTTP '+response.status));
    yearSelect.replaceChildren(new Option('Choisir une année scolaire',''));
    (data.school_years||[]).forEach(year=>yearSelect.add(new Option(year.label,year.id)));
    classSelect.replaceChildren(new Option('Choisir une classe',''));
    (data.classes||[]).forEach(item=>classSelect.add(new Option(item.name+' ('+item.code+')',item.id)));
    if((data.school_years||[]).length===1)yearSelect.value=data.school_years[0].id;
    if(!(data.school_years||[]).length||!(data.classes||[]).length){
      show($('classRecipientsSummary'),'Aucune année scolaire active ou aucune classe active disponible.',true);
    }
  }catch(error){show($('classRecipientsSummary'),'Chargement des classes impossible : '+error.message,true)}
}
async function loadClassParents(){
  const classId=$('broadcastClass').value,schoolYearId=$('broadcastSchoolYear').value;
  if(!classId||!schoolYearId){show($('classRecipientsSummary'),'Choisissez une année scolaire et une classe.',true);return}
  $('loadClassParents').disabled=true;
  show($('classRecipientsSummary'),'Recherche des parents ayant un consentement actif…');
  $('classParentList').hidden=true;
  classParents=[];
  updateClassBatchButtons();
  try{
    const url='/api/whatsapp/class-recipients.php?class_id='+encodeURIComponent(classId)+'&school_year_id='+encodeURIComponent(schoolYearId)+'&purpose='+encodeURIComponent($('purpose').value);
    const response=await fetch(url,{credentials:'same-origin',cache:'no-store',headers:{'Accept':'application/json'}});
    const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
    if(!response.ok||data.success!==true)throw Error(data.error||('Erreur HTTP '+response.status));
    classParents=Array.isArray(data.parents)?data.parents:[];
    const list=$('classParentList');list.replaceChildren();
    if(!classParents.length){
      show($('classRecipientsSummary'),'Aucun parent avec consentement actif pour cette classe, cette année et cette finalité.');
      list.hidden=true;return;
    }
    classParents.forEach(parent=>{
      const label=document.createElement('label');
      label.style.cssText='display:flex;align-items:flex-start;gap:10px;padding:9px;border-bottom:1px solid #dce4e8;font-weight:normal';
      const checkbox=document.createElement('input');checkbox.type='checkbox';checkbox.checked=true;checkbox.style.width='auto';checkbox.dataset.classParent=parent.parent_id;
      checkbox.addEventListener('change',updateClassBatchButtons);
      const text=document.createElement('span');
      text.textContent=[parent.first_name,parent.last_name].filter(Boolean).join(' ')+' — '+parent.phone_e164+' · Élève(s) : '+parent.student_names;
      label.append(checkbox,text);list.appendChild(label);
    });
    list.hidden=false;
    $('selectAllClassParents').checked=true;
    show($('classRecipientsSummary'),classParents.length+' parent(s) autorisé(s) et sélectionné(s) sur '+(data.total_linked_parents||classParents.length)+' parent(s) lié(s) à la classe. '+(data.excluded_without_active_consent||0)+' parent(s) exclu(s) faute de consentement actif. Un parent lié à plusieurs élèves de cette classe ne sera compté qu’une seule fois.');
    updateClassBatchButtons();
  }catch(error){show($('classRecipientsSummary'),'Chargement des parents impossible : '+error.message,true)}
  finally{$('loadClassParents').disabled=false}
}
$('loadClassParents').addEventListener('click',loadClassParents);
$('purpose').addEventListener('change',()=>{if($('broadcastClass').value&&$('broadcastSchoolYear').value)loadClassParents()});
$('selectAllClassParents').addEventListener('change',()=>{
  document.querySelectorAll('[data-class-parent]').forEach(node=>node.checked=$('selectAllClassParents').checked);
  updateClassBatchButtons();
});
$('manualBatchButton').addEventListener('click',async()=>{
  const recipients=selectedClassParents(),message=$('manual_message').value.trim(),out=$('classBatchResult');
  if(!recipients.length){show(out,'Sélectionnez au moins un parent.',true);return}
  if(!message||message.length>4000){show(out,'Rédigez un message de 1 à 4000 caractères dans le champ du mode manuel.',true);return}
  $('manualBatchButton').disabled=true;show(out,'Vérification individuelle des consentements et préparation des liens…');
  const prepared=[],failed=[];
  for(const parent of recipients){
    try{
      const response=await fetch('/api/whatsapp/manual-preparations.php',{
        method:'POST',credentials:'same-origin',cache:'no-store',
        headers:{'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':csrf},
        body:JSON.stringify({parent_id:parent.parent_id,purpose:$('purpose').value,message})
      });
      const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
      if(!response.ok||data.success!==true||!/^\+[1-9][0-9]{7,14}$/.test(data.phone_e164||''))throw Error(data.error||('HTTP '+response.status));
      prepared.push({parent,data});
    }catch(error){failed.push([parent.first_name+' '+parent.last_name,error.message])}
  }
  out.replaceChildren();
  const summary=document.createElement('p');summary.textContent=prepared.length+' lien(s) préparé(s), '+failed.length+' échec(s). Aucun message n’a été envoyé automatiquement.';out.appendChild(summary);
  prepared.forEach(({parent,data})=>{
    const link=document.createElement('a');link.href='https://wa.me/'+data.phone_e164.replace(/\D/g,'')+'?text='+encodeURIComponent(message);
    link.target='_blank';link.rel='noopener noreferrer';link.textContent='Ouvrir WhatsApp — '+parent.first_name+' '+parent.last_name+' ('+parent.student_names+')';
    link.style.cssText='display:block;padding:8px 0;color:#075e54;font-weight:bold';out.appendChild(link);
  });
  failed.forEach(([name,error])=>{const line=document.createElement('p');line.textContent='Échec pour '+name+' : '+error;out.appendChild(line)});
  out.hidden=false;$('manualBatchButton').disabled=false;
});
$('metaBatchButton').addEventListener('click',async()=>{
  const recipients=selectedClassParents(),out=$('classBatchResult');
  if(!configReady){show(out,'La configuration Meta n’est pas prête. Aucun envoi effectué.',true);return}
  if(!recipients.length){show(out,'Sélectionnez au moins un parent.',true);return}
  const templateName=$('template_name').value,language=$('language').value.trim();
  if(!templateName||!/^[a-z]{2,3}(?:_[A-Z]{2})?$/.test(language)){show(out,'Choisissez un modèle approuvé et une langue valide.',true);return}
  const parameters=$('parameters').value.split(/\r?\n/).map(value=>value.trim()).filter(Boolean);
  if(!confirm('Confirmer l’envoi Meta à '+recipients.length+' parent(s) sélectionné(s) ? Chaque destinataire sera vérifié et journalisé individuellement.'))return;
  $('metaBatchButton').disabled=true;
  const accepted=[],failed=[];
  for(let index=0;index<recipients.length;index++){
    const parent=recipients[index];
    show(out,'Envoi Meta : '+(index+1)+' / '+recipients.length+' — '+parent.first_name+' '+parent.last_name);
    try{
      const response=await fetch('/api/whatsapp/send.php',{
        method:'POST',credentials:'same-origin',cache:'no-store',
        headers:{'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':csrf},
        body:JSON.stringify({parent_id:parent.parent_id,purpose:$('purpose').value,template_name:templateName,language,parameters,idempotency_key:makeIdempotencyKey()})
      });
      const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
      if(!response.ok||data.success!==true)throw Error(data.error||('HTTP '+response.status)+(data.provider_error_code?' · Code Meta '+data.provider_error_code:''));
      accepted.push(parent.first_name+' '+parent.last_name+' — '+data.provider_message_id);
    }catch(error){failed.push(parent.first_name+' '+parent.last_name+' — '+error.message)}
  }
  out.replaceChildren();
  const summary=document.createElement('p');summary.textContent='Bilan Meta : '+accepted.length+' demande(s) acceptée(s) par Meta, '+failed.length+' échec(s). L’acceptation ne confirme pas la livraison.';out.appendChild(summary);
  accepted.forEach(item=>{const line=document.createElement('p');line.textContent='Accepté : '+item;out.appendChild(line)});
  failed.forEach(item=>{const line=document.createElement('p');line.textContent='Échec : '+item;out.appendChild(line)});
  out.hidden=false;$('metaBatchButton').disabled=!configReady;
});
loadClassOptions();
loadConfig();
</script>
</body>
</html>