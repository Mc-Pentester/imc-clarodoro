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
<title>WhatsApp — message manuel | IMC-Clarodoro</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f3f6f8;color:#17212b;font:16px Arial,sans-serif}header{background:#075e54;color:#fff;padding:22px max(18px,calc((100% - 900px)/2))}header h1{margin:0 0 6px;font-size:26px}header p{margin:0}main{max-width:900px;margin:24px auto;padding:0 16px}.card{background:#fff;border:1px solid #dce4e8;border-radius:12px;padding:22px;margin-bottom:18px}h2{margin:0 0 16px;color:#075e54;font-size:20px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}label{display:block;font-weight:700;font-size:14px;margin-bottom:6px}input,select,textarea{width:100%;padding:11px;border:1px solid #b8c5cc;border-radius:7px;font:inherit}textarea{min-height:160px;resize:vertical}.wide{grid-column:1/-1}button{border:0;border-radius:7px;padding:12px 18px;background:#087f5b;color:#fff;font-weight:700;cursor:pointer}button:disabled{opacity:.55;cursor:not-allowed}.hint{color:#52616b;font-size:13px;line-height:1.5}.notice{padding:12px;border-radius:8px;background:#fff6df;color:#664c00;margin-bottom:16px;line-height:1.5}.result{padding:12px;border-radius:8px;background:#edf7f1;margin-top:14px;white-space:pre-wrap;overflow-wrap:anywhere}.error{background:#fff0f0;color:#8a1717}.actions{display:flex;gap:10px;flex-wrap:wrap}.secondary{background:#52616b}.status{font-weight:700}@media(max-width:650px){.grid{grid-template-columns:1fr}.wide{grid-column:auto}.card{padding:16px}}
</style>
</head>
<body>
<header><h1>WhatsApp — message manuel</h1><p>IMC-Clarodoro · vous vérifiez et envoyez vous-même le message dans WhatsApp</p></header>
<main>
<div class="notice"><strong>Mode manuel :</strong> aucun message n’est envoyé automatiquement par IMC-Clarodoro. Après vérification du consentement, le bouton ouvre WhatsApp avec le numéro et le texte préremplis. Vous devez vérifier le contenu puis appuyer sur <strong>Envoyer</strong> dans WhatsApp. Aucune configuration Meta Cloud API n’est nécessaire. <strong>Confidentialité :</strong> n’incluez pas de résultats détaillés, de données médicales, disciplinaires ou financières dans le texte. Le message prérempli est placé dans l’URL WhatsApp et peut apparaître dans l’historique du navigateur.</div>
<section class="card">
<h2>1. Vérifier le consentement du parent</h2>
<div class="grid">
<div class="wide"><label for="parent_id">Identifiant UUID du parent</label><input id="parent_id" autocomplete="off" placeholder="UUID du parent dans PostgreSQL" required></div>
<div><label for="purpose">Motif du message</label><select id="purpose"><option value="ATTENDANCE">Présence / absence</option><option value="RESULTS_AVAILABLE">Résultats disponibles</option><option value="PAYMENT_REMINDER">Rappel de paiement</option><option value="GENERAL">Message général</option></select></div>
<div style="align-self:end"><button type="button" id="checkConsent">Vérifier le consentement</button></div>
</div>
<div id="consentResult" class="result" hidden aria-live="polite"></div>
<p class="hint">Le numéro est récupéré depuis le consentement enregistré. L’ouverture de WhatsApp est autorisée uniquement si le consentement est OPTED_IN pour le motif choisi.</p>
</section>
<section class="card">
<h2>2. Rédiger et ouvrir WhatsApp</h2>
<div class="grid">
<div class="wide"><label for="message">Message</label><textarea id="message" maxlength="4000" placeholder="Rédigez ici le message à envoyer au parent…" required></textarea></div>
<div class="wide actions"><button type="button" id="openWhatsApp" disabled>Ouvrir WhatsApp avec ce message</button><button type="button" id="clearMessage" class="secondary">Effacer le texte</button></div>
</div>
<div id="sendResult" class="result" hidden aria-live="polite"></div>
<p class="hint">Le message reste modifiable dans WhatsApp. Cette page ne confirme pas l’envoi ni la livraison : vérifiez le message et son destinataire dans WhatsApp avant d’appuyer sur Envoyer.</p>
</section>
</main>
<script>
const csrf=document.querySelector('meta[name="csrf-token"]').content,$=id=>document.getElementById(id);
let verifiedConsent=null;
function show(node,text,error=false){node.hidden=false;node.textContent=text;node.classList.toggle('error',error)}
function invalidateConsent(){verifiedConsent=null;$('openWhatsApp').disabled=true}
$('parent_id').addEventListener('input',invalidateConsent);
$('purpose').addEventListener('change',invalidateConsent);
$('checkConsent').addEventListener('click',async()=>{
  const out=$('consentResult');out.hidden=true;invalidateConsent();
  const parentId=$('parent_id').value.trim();
  if(!parentId){show(out,'Saisissez l’identifiant UUID du parent.',true);return}
  try{
    const response=await fetch('/api/whatsapp/consents.php?parent_id='+encodeURIComponent(parentId),{credentials:'same-origin',cache:'no-store',headers:{'Accept':'application/json'}});
    const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
    if(!response.ok||data.success===false)throw Error(data.error||('Erreur HTTP '+response.status));
    const consent=(data.consents||[]).find(item=>item.purpose===$('purpose').value);
    if(!consent){show(out,'Aucun consentement enregistré pour ce motif. WhatsApp ne sera pas ouvert.');return}
    if(consent.status!=='OPTED_IN'){show(out,'Consentement non actif ('+consent.status+'). Aucun message ne peut être préparé via cette page.');return}
    if(!/^\+[1-9][0-9]{7,14}$/.test(consent.phone_e164||'')){show(out,'Le numéro enregistré est invalide. Corrigez le consentement dans le dossier du parent.',true);return}
    verifiedConsent={parentId,purpose:$('purpose').value,phone:consent.phone_e164};
    show(out,'Consentement actif pour ce motif.\nNuméro : '+consent.phone_e164+'\nVous pouvez rédiger le message puis ouvrir WhatsApp.');
    $('openWhatsApp').disabled=false;
  }catch(error){show(out,error.message||'Erreur lors de la vérification.',true)}
});
$('openWhatsApp').addEventListener('click',async()=>{
  const out=$('sendResult');out.hidden=true;
  if(!verifiedConsent||verifiedConsent.parentId!==$('parent_id').value.trim()||verifiedConsent.purpose!==$('purpose').value){show(out,'Vérifiez à nouveau le consentement avant de continuer.',true);invalidateConsent();return}
  const message=$('message').value.trim();
  if(!message){show(out,'Rédigez le message avant d’ouvrir WhatsApp.',true);return}
  // Open synchronously to avoid popup blockers, then navigate only after server revalidation.
  const popup=window.open('about:blank','_blank');
  if(!popup){show(out,'Le navigateur a bloqué la fenêtre. Autorisez les fenêtres contextuelles puis réessayez.',true);return}
  popup.opener=null;
  $('openWhatsApp').disabled=true;
  try{
    const response=await fetch('/api/whatsapp/manual-preparations.php',{
      method:'POST',credentials:'same-origin',cache:'no-store',
      headers:{'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':csrf},
      body:JSON.stringify({parent_id:verifiedConsent.parentId,purpose:verifiedConsent.purpose,message})
    });
    const data=await response.json().catch(()=>({success:false,error:'Réponse serveur invalide'}));
    if(!response.ok||data.success!==true||!/^\\+[1-9][0-9]{7,14}$/.test(data.phone_e164||''))throw Error(data.error||'La vérification finale a échoué.');
    const digits=data.phone_e164.replace(/\\D/g,'');
    popup.location.href='https://wa.me/'+digits+'?text='+encodeURIComponent(message);
    $('message').value='';
    invalidateConsent();
    show(out,'Préparation journalisée (référence '+data.preparation_id+'). Consentement revérifié. Vérifiez le destinataire et le texte dans WhatsApp puis appuyez vous-même sur Envoyer. L’application ne peut pas confirmer l’envoi.');
  }catch(error){
    popup.close();
    show(out,error.message||'Impossible de vérifier le consentement et journaliser la préparation.',true);
  }finally{
    $('openWhatsApp').disabled=!verifiedConsent;
  }
});
$('clearMessage').addEventListener('click',()=>{$('message').value='';$('sendResult').hidden=true});
</script>
</body>
</html>
