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
<title>WhatsApp multi-destinataires | Clarodaro</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f3f6f8;color:#17212b;font:16px Arial,sans-serif}
header{background:#075e54;color:#fff;padding:20px max(18px,calc((100% - 900px)/2))}
main{max-width:900px;margin:22px auto;padding:0 16px}.card{background:#fff;border:1px solid #dce4e8;border-radius:12px;padding:20px;margin-bottom:16px}
h1{margin:0 0 6px;font-size:25px}h2{margin:0 0 14px;color:#075e54;font-size:19px}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}.wide{grid-column:1/-1}
label{display:block;font-weight:700;font-size:14px;margin-bottom:6px}input,select,textarea{width:100%;padding:11px;border:1px solid #b8c5cc;border-radius:7px;font:inherit}
textarea{min-height:90px;resize:vertical}button{border:0;border-radius:7px;padding:11px 16px;background:#087f5b;color:#fff;font-weight:700;cursor:pointer}
button:disabled{opacity:.55;cursor:not-allowed}.hint{font-size:13px;line-height:1.5;color:#52616b}.result{padding:12px;border-radius:8px;background:#edf7f1;margin-top:12px;white-space:pre-wrap;overflow-wrap:anywhere}.error{background:#fff0f0;color:#8a1717}
.item{display:block;width:100%;text-align:left;margin:6px 0;background:#f0f7f4;color:#173b32;border:1px solid #c9ded5}
.actions{display:flex;gap:10px;flex-wrap:wrap}@media(max-width:650px){.grid{grid-template-columns:1fr}.wide{grid-column:auto}.card{padding:15px}}
</style>
</head>
<body>
<header><h1>WhatsApp — destinataires multiples</h1><p>Envoi Meta avec consentement individuel, routage par âge et journalisation</p></header>
<main>
<section class="card">
<h2>1. Sélectionner la personne de référence</h2>
<div class="grid">
<div><label for="recipientType">Type de personne</label><select id="recipientType"><option value="STUDENT">Élève</option><option value="PARENT">Parent / responsable</option><option value="STAFF">Personnel</option><option value="TEACHER">Enseignant</option></select></div>
<div><label for="purpose">Finalité du consentement</label><select id="purpose"><option value="ATTENDANCE">Présence / absence</option><option value="RESULTS_AVAILABLE">Résultats disponibles</option><option value="PAYMENT_REMINDER">Rappel de paiement</option><option value="GENERAL">Message général</option></select></div>
<div class="wide"><label for="recipientSearch">Rechercher</label><input id="recipientSearch" type="search" autocomplete="off" placeholder="Nom, prénom ou matricule"><div id="recipientResults" class="result" hidden></div><div id="selectedRecipient" class="result" hidden></div><input id="recipientId" type="hidden"></div>
<div class="wide" id="scopeWrap"><label for="scope">Portée pour un élève majeur</label><select id="scope"><option value="STUDENT_ONLY">Message personnel : élève uniquement</option><option value="STUDENT_AND_PARENTS">Message familial : élève et responsables consentants</option></select><p class="hint">Mineur ou date de naissance inconnue : seuls les responsables liés et consentants sont ciblés. Majeur : la portée choisie est appliquée côté serveur.</p></div>
</div>
</section>
<section class="card">
<h2>2. Enregistrer ou retirer un consentement</h2>
<p class="hint">Sélectionnez d’abord une personne. Pour un parent, l’activation exige une preuve papier identifiée. Le numéro du dossier scolaire ne vaut pas consentement.</p>
<div class="grid">
<div><label for="consentPhone">Numéro WhatsApp E.164</label><input id="consentPhone" placeholder="+509XXXXXXXX" autocomplete="tel"></div>
<div><label for="consentStatus">Statut</label><select id="consentStatus"><option value="OPTED_IN">Actif</option><option value="PENDING">En attente</option><option value="OPTED_OUT">Retiré</option></select></div>
<div><label for="consentSource">Source</label><input id="consentSource" maxlength="255" placeholder="PAPER pour un parent"></div>
<div><label for="consentEvidence">Référence de preuve</label><input id="consentEvidence" maxlength="255" placeholder="Référence du document signé"></div>
<div class="wide"><button type="button" id="saveConsent">Enregistrer le consentement</button><div id="consentResult" class="result" hidden></div></div>
</div>
</section>
<section class="card">
<h2>3. Envoyer via Meta</h2>
<div class="grid">
<div><label for="templateName">Modèle Meta approuvé</label><input id="templateName" maxlength="128" pattern="[a-z0-9_]+" placeholder="nom_modele"></div>
<div><label for="language">Langue</label><input id="language" value="fr" maxlength="8"></div>
<div class="wide"><label for="parameters">Paramètres du modèle (un par ligne)</label><textarea id="parameters" placeholder="Jean&#10;Absence du 20 novembre"></textarea></div>
<div class="wide actions"><button type="button" id="sendButton" disabled>Envoyer aux destinataires autorisés</button><button type="button" id="refreshHistory">Actualiser l’historique</button></div>
<div class="wide"><div id="sendResult" class="result" hidden aria-live="polite"></div></div>
</div>
<p class="hint">Chaque destinataire est revérifié et journalisé individuellement. Une requête déjà réservée ne sera pas relancée automatiquement après une issue réseau incertaine. Une révocation après réservation n’annule pas un envoi déjà en cours.</p>
</section>
<section class="card">
<h2>Historique des envois</h2><div id="history" class="result" hidden aria-live="polite"></div>
</section>
</main>
<script>
'use strict';
const csrf=document.querySelector('meta[name="csrf-token"]').content;
const $=id=>document.getElementById(id);
let searchTimer=null,searchController=null;
function show(id,message,error=false){const el=$(id);el.hidden=false;el.textContent=message;el.classList.toggle('error',error)}
function selectedId(){return $('recipientId').value.trim()}
function clearSelection(){ $('recipientId').value='';$('selectedRecipient').hidden=true;$('selectedRecipient').textContent='';$('sendButton').disabled=true;$('consentPhone').value=''; }
async function searchRecipients(){
 const q=$('recipientSearch').value.trim(),type=$('recipientType').value,box=$('recipientResults');
 clearSelection();
 if(q.length<2){box.hidden=true;box.replaceChildren();return}
 if(searchController)searchController.abort();searchController=new AbortController();show('recipientResults','Recherche…');
 try{
  const response=await fetch('/api/whatsapp/recipient-search.php?recipient_type='+encodeURIComponent(type)+'&q='+encodeURIComponent(q),{credentials:'same-origin',cache:'no-store',signal:searchController.signal});
  const data=await response.json();if(!response.ok||data.success!==true)throw Error(data.error||('HTTP '+response.status));
  box.replaceChildren();
  if(!Array.isArray(data.recipients)||!data.recipients.length){show('recipientResults','Aucun résultat.');return}
  data.recipients.forEach(person=>{
   const b=document.createElement('button');b.type='button';b.className='item';
   const name=[person.first_name,person.last_name].filter(Boolean).join(' ');
   b.textContent=name+(person.phone?' — '+person.phone:'');
   b.addEventListener('click',()=>{
    $('recipientId').value=person.id;$('selectedRecipient').textContent='Sélection : '+name+' · '+type;
    $('selectedRecipient').hidden=false;box.hidden=true;box.replaceChildren();
    $('consentPhone').value=person.phone&&/^\+[1-9][0-9]{7,14}$/.test(person.phone)?person.phone:'';
    $('sendButton').disabled=false;
   });box.appendChild(b);
  });box.hidden=false;
 }catch(error){if(error.name!=='AbortError')show('recipientResults','Recherche impossible : '+error.message,true)}
}
$('recipientSearch').addEventListener('input',()=>{clearTimeout(searchTimer);searchTimer=setTimeout(searchRecipients,250)});
$('recipientType').addEventListener('change',()=>{$('recipientSearch').value='';clearSelection();$('recipientResults').hidden=true;$('scopeWrap').hidden=$('recipientType').value!=='STUDENT'});
$('scopeWrap').hidden=false;
$('saveConsent').addEventListener('click',async()=>{
 const id=selectedId(),type=$('recipientType').value,phone=$('consentPhone').value.trim(),status=$('consentStatus').value;
 if(!id){show('consentResult','Sélectionnez une personne.',true);return}
 if(!/^\+[1-9][0-9]{7,14}$/.test(phone)){show('consentResult','Numéro E.164 invalide.',true);return}
 const source=$('consentSource').value.trim(),evidence=$('consentEvidence').value.trim();
 if(status==='OPTED_IN'&&!source){show('consentResult','La source du consentement est obligatoire.',true);return}
 const body={recipient_type:type,recipient_id:id,purpose:$('purpose').value,phone_e164:phone,status,consent_source:source||null,evidence_reference:evidence||null};
 if(type==='PARENT'&&status==='OPTED_IN'){body.consent_source='PAPER';body.consent_method='PAPER';if(!evidence){show('consentResult','Une référence de preuve papier est obligatoire pour un parent.',true);return}}
 $('saveConsent').disabled=true;
 try{
  const response=await fetch('/api/whatsapp/recipient-consents.php',{method:'POST',credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf,'Accept':'application/json'},body:JSON.stringify(body)});
  const data=await response.json();if(!response.ok||data.success!==true)throw Error(data.error||('HTTP '+response.status));
  show('consentResult','Consentement enregistré : '+data.consent.status+' · '+data.consent.purpose);
 }catch(error){show('consentResult','Enregistrement impossible : '+error.message,true)}
 finally{$('saveConsent').disabled=false}
});
$('sendButton').addEventListener('click',async()=>{
 const id=selectedId(),type=$('recipientType').value,template=$('templateName').value.trim(),language=$('language').value.trim(),out=$('sendResult');
 if(!id){show('sendResult','Sélectionnez une personne.',true);return}
 if(!/^[a-z0-9_]{1,128}$/.test(template)){show('sendResult','Nom de modèle Meta invalide.',true);return}
 if(!/^[a-z]{2,3}(?:_[A-Z]{2})?$/.test(language)){show('sendResult','Langue invalide.',true);return}
 const parameters=$('parameters').value.split(/\r?\n/).map(v=>v.trim()).filter(Boolean);
 if(!confirm('Confirmer l’envoi Meta? Clarodaro vérifiera les consentements et les destinataires finaux.'))return;
 $('sendButton').disabled=true;show('sendResult','Réservation des destinataires et envoi Meta…');
 try{
  const response=await fetch('/api/whatsapp/send-multi.php',{method:'POST',credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf,'Accept':'application/json'},body:JSON.stringify({recipient_type:type,recipient_id:id,scope:$('scope').value,purpose:$('purpose').value,template_name:template,language,parameters,idempotency_key:crypto.randomUUID()})});
  const data=await response.json();if(!response.ok||data.success!==true){show('sendResult',JSON.stringify(data,null,2),true);return}
  show('sendResult',JSON.stringify(data,null,2));loadHistory();
 }catch(error){show('sendResult','Résultat incertain : '+error.message+'. Ne relancez pas avec une nouvelle clé avant de vérifier l’historique.',true)}
 finally{$('sendButton').disabled=false}
});
async function loadHistory(){
 try{
  const response=await fetch('/api/whatsapp/recipient-message-history.php',{credentials:'same-origin',cache:'no-store',headers:{'Accept':'application/json'}});
  const data=await response.json();if(!response.ok||data.success!==true)throw Error(data.error||('HTTP '+response.status));
  const lines=(data.messages||[]).map(m=>[m.created_at,m.recipient_type,m.recipient_name,m.purpose,m.status,m.provider_message_id||m.provider_error_code||''].join(' · '));
  show('history',lines.length?lines.join('\n'):'Aucun envoi journalisé.');
 }catch(error){show('history','Historique indisponible ou permission d’audit absente : '+error.message,true)}
}
$('refreshHistory').addEventListener('click',loadHistory);
</script>
</body>
</html>
