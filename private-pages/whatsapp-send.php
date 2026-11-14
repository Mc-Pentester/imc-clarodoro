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
<title>Envoi WhatsApp réel | Clarodaro</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f3f6f8;color:#17212b;font:16px Arial,sans-serif}header{background:#075e54;color:#fff;padding:22px max(18px,calc((100% - 900px)/2))}header h1{margin:0 0 6px;font-size:26px}header p{margin:0}main{max-width:900px;margin:24px auto;padding:0 16px}.card{background:#fff;border:1px solid #dce4e8;border-radius:12px;padding:22px;margin-bottom:18px}h2{margin:0 0 16px;color:#075e54;font-size:20px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}label{display:block;font-weight:700;font-size:14px;margin-bottom:6px}input,select,textarea{width:100%;padding:11px;border:1px solid #b8c5cc;border-radius:7px;font:inherit}textarea{min-height:110px;resize:vertical}.wide{grid-column:1/-1}button{border:0;border-radius:7px;padding:12px 18px;background:#087f5b;color:#fff;font-weight:700;cursor:pointer}button:disabled{opacity:.55;cursor:not-allowed}.hint{color:#52616b;font-size:13px;line-height:1.5}.notice{padding:12px;border-radius:8px;background:#eaf4ff;color:#17436a;margin-bottom:16px;line-height:1.5}.result{padding:12px;border-radius:8px;background:#edf7f1;margin-top:14px;white-space:pre-wrap;overflow-wrap:anywhere}.error{background:#fff0f0;color:#8a1717}.actions{display:flex;gap:10px;flex-wrap:wrap}@media(max-width:650px){.grid{grid-template-columns:1fr}.wide{grid-column:auto}.card{padding:16px}}
</style>
</head>
<body>
<header><h1>Envoi WhatsApp réel</h1><p>Clarodaro · Meta WhatsApp Business Cloud API</p></header>
<main>
<div class="notice"><strong>Envoi réel :</strong> cette page transmet les demandes à l’API officielle Meta depuis le serveur Clarodaro. Elle n’ouvre pas WhatsApp sur le poste et ne simule aucun envoi. Seuls les modèles approuvés par Meta et configurés sur le serveur peuvent être envoyés. L’acceptation par Meta n’est pas une confirmation de livraison.</div>
<section class="card">
<h2>1. État de la configuration</h2>
<div id="configStatus" class="result" aria-live="polite">Vérification de la configuration sécurisée du serveur…</div>
<p class="hint">Le jeton d’accès reste exclusivement dans le fichier protégé <code>C:\ProgramData\IMC-Clarodaro\config\.env</code>. Il n’est jamais transmis au navigateur.</p>
</section>
<section class="card">
<h2>2. Envoyer un modèle WhatsApp</h2>
<div class="grid">
<div class="wide"><label for="parent_id">Identifiant UUID du parent</label><input id="parent_id" autocomplete="off" placeholder="UUID du parent dans Clarodaro" required></div>
<div><label for="purpose">Finalité / consentement</label><select id="purpose"><option value="ATTENDANCE">Présence / absence</option><option value="RESULTS_AVAILABLE">Résultats disponibles</option><option value="PAYMENT_REMINDER">Rappel de paiement</option><option value="GENERAL">Message général</option></select></div>
<div><label for="template_name">Modèle approuvé Meta</label><select id="template_name" required disabled><option value="">Chargement des modèles…</option></select></div>
<div><label for="language">Langue du modèle</label><input id="language" value="fr" maxlength="10" placeholder="fr ou fr_FR" required></div>
<div class="wide"><label for="parameters">Paramètres du corps (un paramètre par ligne, dans l’ordre du modèle)</label><textarea id="parameters" maxlength="12000" placeholder="Jean&#10;Lundi 16 novembre"></textarea><p class="hint">Laissez vide si le modèle n’a aucune variable. Les valeurs sont transmises à Meta comme paramètres texte du modèle approuvé.</p></div>
<div class="wide actions"><button type="button" id="sendButton" disabled>Envoyer réellement via WhatsApp</button></div>
</div>
<div id="sendResult" class="result" hidden aria-live="polite"></div>
</section>
</main>
<script>
const csrf=document.querySelector('meta[name="csrf-token"]').content,$=id=>document.getElementById(id);
let configReady=false;
function show(node,text,error=false){node.hidden=false;node.textContent=text;node.classList.toggle('error',error)}
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
      show(status,'ENVOI RÉEL NON CONFIGURÉ. Aucun message ne sera simulé ni envoyé. Configurez les variables Meta dans le fichier protégé du serveur puis rechargez cette page.',true);
      configReady=false;
    }else{
      show(status,'Configuration prête. '+data.templates.length+' modèle(s) autorisé(s). Envoi réel activable.');
      configReady=true;
    }
  }catch(error){show(status,'Impossible de vérifier la configuration : '+error.message,true);configReady=false}
  $('sendButton').disabled=!configReady;
}
function makeIdempotencyKey(){
  const bytes=new Uint8Array(16);crypto.getRandomValues(bytes);
  return 'clarodaro-'+Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
}
$('sendButton').addEventListener('click',async()=>{
  const out=$('sendResult');out.hidden=true;
  if(!configReady){show(out,'La configuration réelle n’est pas prête. Aucun envoi effectué.',true);return}
  const parentId=$('parent_id').value.trim(),templateName=$('template_name').value,language=$('language').value.trim();
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(parentId)){show(out,'Identifiant UUID du parent invalide.',true);return}
  if(!templateName){show(out,'Choisissez un modèle approuvé.',true);return}
  if(!/^[a-z]{2,3}(?:_[A-Z]{2})?$/.test(language)){show(out,'Code de langue invalide.',true);return}
  const parameters=$('parameters').value.split(/\r?\n/).map(value=>value.trim()).filter(Boolean);
  $('sendButton').disabled=true;
  show(out,'Envoi de la demande à Meta…');
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
loadConfig();
</script>
</body>
</html>
