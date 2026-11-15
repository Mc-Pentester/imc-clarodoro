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
<div><label for="recipientType">Type de destinataire</label><select id="recipientType"><option value="STUDENT">Élève</option><option value="PARENT">Parent / responsable</option><option value="STAFF">Personnel</option><option value="TEACHER">Enseignant</option></select></div>
<div><label for="purpose">Finalité / consentement</label><select id="purpose"><option value="ATTENDANCE">Présence / absence</option><option value="RESULTS_AVAILABLE">Résultats disponibles</option><option value="PAYMENT_REMINDER">Rappel de paiement</option><option value="GENERAL">Message général</option></select></div>
<div class="wide"><label for="recipientSearch">Rechercher un destinataire</label><input id="recipientSearch" type="search" autocomplete="off" placeholder="Nom, prénom ou matricule…" aria-describedby="recipientSearchHint"><p id="recipientSearchHint" class="hint">Saisissez au moins 2 caractères. La sélection d’un élève applique automatiquement les règles mineur/majeur sur le serveur.</p><div id="recipientResults" class="result" hidden role="listbox" aria-label="Résultats des destinataires"></div><div id="selectedRecipient" class="result" hidden aria-live="polite"></div><input id="recipient_id" type="hidden" required><input id="parent_id" type="hidden"></div>
<div class="wide" id="studentScopeWrap"><label for="studentScope">Portée du message pour un élève majeur</label><select id="studentScope"><option value="STUDENT_ONLY">Message personnel : élève uniquement</option><option value="STUDENT_AND_PARENTS">Message concernant aussi les parents : élève et responsables consentants</option></select><p class="hint">Pour un mineur, seuls les responsables liés ayant un consentement actif seront ciblés, quel que soit ce choix. Pour un majeur, le serveur applique la portée sélectionnée.</p></div>
</div>
<p class="hint">Les consentements sont vérifiés individuellement par finalité et par numéro. Les responsables sont sélectionnés à partir de la relation élève-responsable en base de données.</p>
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
let recipientSearchTimer=null,recipientSearchController=null;
function clearSelectedRecipient(){
  $('recipient_id').value='';$('parent_id').value='';
  $('selectedRecipient').hidden=true;$('selectedRecipient').textContent='';
}
async function searchRecipients(){
  const q=$('recipientSearch').value.trim(),results=$('recipientResults'),type=$('recipientType').value;
  clearSelectedRecipient();
  if(q.length<2){results.hidden=true;results.textContent='';return}
  if(recipientSearchController)recipientSearchController.abort();
  recipientSearchController=new AbortController();show(results,'Recherche…');
  try{
    const url='/api/whatsapp/recipient-search.php?recipient_type='+encodeURIComponent(type)+'&q='+encodeURIComponent(q);
    const response=await fetch(url,{credentials:'same-origin',cache:'no-store',headers:{'Accept':'application/json'},signal:recipientSearchController.signal});
    const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
    if(!response.ok||data.success!==true)throw Error(data.error||('Erreur HTTP '+response.status));
    results.replaceChildren();
    if(!Array.isArray(data.recipients)||data.recipients.length===0){show(results,'Aucun résultat trouvé. Vérifiez aussi que le consentement est enregistré pour la bonne finalité.');return}
    for(const recipient of data.recipients){
      const option=document.createElement('button');option.type='button';
      option.style.cssText='display:block;width:100%;text-align:left;margin:5px 0;background:#f0f7f4;color:#173b32;border:1px solid #c9ded5';
      const fullName=[recipient.first_name,recipient.last_name].filter(Boolean).join(' ');
      option.textContent=fullName+(recipient.phone?' — téléphone dossier : '+recipient.phone:'');
      option.setAttribute('role','option');
      option.addEventListener('click',()=>{
        $('recipient_id').value=recipient.id;
        $('parent_id').value=type==='PARENT'?recipient.id:'';
        $('selectedRecipient').textContent='Destinataire sélectionné : '+fullName+' · '+type;
        $('selectedRecipient').hidden=false;results.hidden=true;results.replaceChildren();
        $('manualButton').disabled=type!=='PARENT';
      });
      results.appendChild(option);
    }
    results.hidden=false;
  }catch(error){if(error.name!=='AbortError')show(results,'Recherche impossible : '+error.message,true)}
}
$('recipientSearch').addEventListener('input',()=>{clearTimeout(recipientSearchTimer);recipientSearchTimer=setTimeout(searchRecipients,250)});
$('recipientType').addEventListener('change',()=>{
  $('recipientSearch').value='';clearSelectedRecipient();$('recipientResults').hidden=true;
  $('studentScopeWrap').hidden=$('recipientType').value!=='STUDENT';
  $('manualButton').disabled=$('recipientType').value!=='PARENT';
});
$('purpose').addEventListener('change',()=>{if($('recipientSearch').value.trim().length>=2)searchRecipients();else clearSelectedRecipient()});
$('studentScopeWrap').hidden=false;
function validParent(){const value=$('parent_id').value.trim();if($('recipientType').value!=='PARENT'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))throw Error('Le mode manuel est disponible uniquement pour un parent sélectionné.');return value}
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
    const response=await fetch('/api/whatsapp/send-multi.php',{
      method:'POST',credentials:'same-origin',cache:'no-store',
      headers:{'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':csrf},
      body:JSON.stringify({recipient_type:$('recipientType').value,recipient_id:$('recipient_id').value,scope:$('studentScope').value,purpose:$('purpose').value,template_name:templateName,language,parameters,idempotency_key:makeIdempotencyKey()})
    });
    const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
    if(!response.ok||data.success!==true)throw Error(data.error||('Erreur HTTP '+response.status)+(data.provider_error_code?' · Code Meta '+data.provider_error_code:''));
    show(out,'Résultat : '+data.accepted_by_meta+' demande(s) acceptée(s) par Meta sur '+data.total_eligible+' destinataire(s) éligible(s).\n'+(data.results||[]).map(r=>r.status+' — '+r.consent_id+(r.provider_message_id?' — '+r.provider_message_id:'')+(r.reason?' — '+r.reason:'')).join('\n')+'\n'+data.message);
  }catch(error){show(out,'ÉCHEC DE L’ENVOI : '+error.message,true)}
  finally{$('sendButton').disabled=!configReady}
});
loadConfig();
</script>
</body>
</html>