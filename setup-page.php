<?php
declare(strict_types=1);

require_once __DIR__ . '/config/database.php';
require_once __DIR__ . '/config/auth.php';

header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store, private, max-age=0');
header('X-Content-Type-Options: nosniff');

try {
    $pdo = getDatabaseConnection();
    $existing = $pdo->query(
        "SELECT 1 FROM users u LEFT JOIN roles r ON r.id = u.role_id
         WHERE LOWER(u.username) = 'pdg' OR r.name = 'PDG' LIMIT 1"
    )->fetchColumn();
} catch (Throwable $error) {
    error_log('Clarodaro first-run status unavailable: ' . $error->getMessage());
    http_response_code(503);
    exit('Service temporairement indisponible.');
}

if ($existing !== false) {
    http_response_code(409);
    echo '<!doctype html><html lang="fr"><meta charset="utf-8"><title>Configuration terminée</title><body><main><h1>Clarodaro est déjà configuré</h1><p>Le compte PDG existe déjà. La configuration initiale ne peut être effectuée qu’une seule fois.</p><a href="/pdg.html">Accéder à la connexion</a></main></body></html>';
    exit;
}

$csrf = htmlspecialchars(generateCsrfToken(), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
?>
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="csrf-token" content="<?= $csrf ?>">
<title>Première configuration — Clarodaro</title>
<style>
body{font:16px system-ui,sans-serif;background:#f1f5f9;color:#172033;margin:0;min-height:100vh;display:grid;place-items:center}
main{background:#fff;width:min(460px,calc(100% - 40px));padding:28px;border-radius:14px;box-shadow:0 8px 32px #0f172a18;box-sizing:border-box}
label{display:block;margin:16px 0 6px}input,button{box-sizing:border-box;width:100%;padding:12px;border:1px solid #cbd5e1;border-radius:8px;font:inherit}
button{margin-top:20px;background:#12355b;color:white;border:0;cursor:pointer}button:disabled{opacity:.6;cursor:wait}
small{color:#64748b}#message{white-space:pre-wrap;margin-top:14px}
</style>
</head>
<body>
<main>
<h1>Bienvenue sur Clarodaro</h1>
<p>La base de données est prête. Créez maintenant le compte administrateur principal (PDG). Cette étape se fait après l’installation et ne peut être effectuée qu’une seule fois.</p>
<form id="setup">
<label for="username">Identifiant</label>
<input id="username" value="pdg" readonly autocomplete="username">
<label for="password">Mot de passe (12 caractères minimum)</label>
<input id="password" type="password" required autocomplete="new-password">
<label for="confirmation">Confirmer le mot de passe</label>
<input id="confirmation" type="password" required autocomplete="new-password">
<button id="submit" type="submit">Créer mon compte PDG</button>
<p id="message" role="status" aria-live="polite"></p>
</form>
</main>
<script>
const form=document.getElementById('setup');
form.addEventListener('submit',async event=>{
 event.preventDefault();
 const password=document.getElementById('password').value;
 const confirmation=document.getElementById('confirmation').value;
 const message=document.getElementById('message');
 const button=document.getElementById('submit');
 message.textContent='';
 if(Array.from(password).length<12){message.textContent='Le mot de passe doit contenir au moins 12 caractères.';return;}
 if(password!==confirmation){message.textContent='Les deux mots de passe ne correspondent pas.';return;}
 button.disabled=true;
 try{
  const response=await fetch('/api/auth/initial-setup.php',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name="csrf-token"]').content},body:JSON.stringify({password,confirmation})});
  const result=await response.json();
  if(!response.ok||!result.success)throw new Error(result.error||'Création du compte impossible.');
  form.innerHTML='<h2>Compte PDG créé</h2><p>Votre compte administrateur est prêt. Vous pouvez maintenant vous connecter.</p><a href="/pdg.html">Ouvrir la connexion</a>';
 }catch(error){message.textContent=error.message||'Une erreur est survenue.';button.disabled=false;}
});
</script>
</body>
</html>
