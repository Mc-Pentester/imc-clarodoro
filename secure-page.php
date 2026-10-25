<?php
declare(strict_types=1);

require_once __DIR__ . '/config/page_auth.php';

header('Cache-Control: no-store, private, max-age=0');
header('Pragma: no-cache');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: same-origin');
// Autoriser les fonctions caméra de même origine si une page les utilise.
header('Permissions-Policy: camera=(self), microphone=(), geolocation=()');

$pages = [
    'index.html' => ['public' => 'index.html', 'file' => 'index.php', 'permission' => 'eleves.read', 'role' => null],
    'pdg.html' => ['public' => 'PDG.html', 'file' => 'PDG.php', 'permission' => 'paies.read', 'role' => 'PDG'],
    'finances.html' => ['public' => 'finances.html', 'file' => 'finances.php', 'permission' => 'finances.read', 'role' => null],
    'personnel.html' => ['public' => 'personnel.html', 'file' => 'personnel.php', 'permission' => 'personnel.read', 'role' => null],
    'badge.html' => ['public' => 'badge.html', 'file' => 'badge.php', 'permission' => 'badge.read', 'role' => null],
    'payroll-recovery.html' => ['public' => 'payroll-recovery.html', 'file' => 'payroll-recovery.php', 'permission' => 'paies.reconcile', 'role' => null],
    'resultats.html' => ['public' => 'resultats.html', 'file' => 'resultats.php', 'permission' => 'resultats.read', 'role' => null],
    'vacations.html' => ['public' => 'vacations.html', 'file' => 'vacations.php', 'permission' => 'vacances.read', 'role' => null],
];

$requestedPage = isset($_GET['page']) && is_string($_GET['page']) ? strtolower(basename($_GET['page'])) : '';
if (!isset($pages[$requestedPage])) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    exit('Page introuvable.');
}
$page = $pages[$requestedPage];

try {
    $pdo = getDatabaseConnection();
    $access = imcPageAccess($pdo, $page['permission'], $page['role']);
} catch (Throwable $error) {
    error_log('IMC page authorization unavailable: ' . $error->getMessage());
    http_response_code(503);
    header('Content-Type: text/plain; charset=utf-8');
    exit('Service temporairement indisponible.');
}

if (!$access['allowed']) {
    http_response_code((int) $access['status']);
    if ($access['status'] === 401) {
        header('Content-Type: text/html; charset=utf-8');
        $next = htmlspecialchars($page['public'], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $pdgLogin = strtolower($page['public']) === 'pdg.html';
        $username = $pdgLogin ? 'pdg' : '';
        $readonly = $pdgLogin ? 'readonly' : '';
        echo '<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Connexion — IMC-Clarodaro</title><style>body{font:16px system-ui,sans-serif;background:#f1f5f9;margin:0;display:grid;min-height:100vh;place-items:center}.box{background:white;padding:2rem;border-radius:12px;box-shadow:0 4px 20px #0001;width:min(420px,calc(100% - 3rem))}label,input,button{display:block;width:100%;box-sizing:border-box;margin:.65rem 0}input,button{padding:.8rem;border:1px solid #cbd5e1;border-radius:7px;font:inherit}button{background:#12355b;color:white;cursor:pointer}#error{color:#b91c1c;white-space:pre-wrap}</style></head><body><main class="box"><h1>IMC-Clarodaro</h1><h2>Connexion requise</h2><form id="login"><label for="username">Identifiant</label><input id="username" autocomplete="username" required value="' . $username . '" ' . $readonly . '><label for="password">Mot de passe</label><input id="password" type="password" autocomplete="current-password" required><button type="submit">Se connecter</button><p id="error" role="alert"></p></form>' . ($pdgLogin ? '<p><a href="/reinitialiser-mot-de-passe.html">Mot de passe oublié ?</a></p>' : '') . '</main><script>const next=' . json_encode($page['public'], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) . ';document.getElementById("login").addEventListener("submit",async e=>{e.preventDefault();const error=document.getElementById("error");error.textContent="";try{const r=await fetch("/api/auth/login.php",{method:"POST",credentials:"same-origin",headers:{"Content-Type":"application/json","Accept":"application/json"},body:JSON.stringify({username:document.getElementById("username").value.trim(),password:document.getElementById("password").value})});const d=await r.json();if(!r.ok||!d.success||!d.user)throw new Error(d.message||d.error||"Connexion refusée.");location.replace("/"+next);}catch(err){error.textContent=err.message||"Connexion impossible.";}});</script></body></html>';
        exit;
    }

    header('Content-Type: text/html; charset=utf-8');
    exit('<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Accès refusé — IMC-Clarodaro</title></head><body><main><h1>Accès refusé</h1><p>Votre compte ne dispose pas de la permission nécessaire pour ouvrir cette page.</p></main></body></html>');
}

$privateFile = __DIR__ . '/private-pages/' . $page['file'];
if (!is_file($privateFile)) {
    http_response_code(500);
    exit('Page protégée indisponible.');
}

ob_start();
require $privateFile;
$html = ob_get_clean();

// Ajoute l'accès WhatsApp après le rendu de toute page protégée sans modifier
// les pages métier. Le script décide lui-même de l'afficher uniquement si
// l'utilisateur possède la permission RBAC dédiée.
if (is_string($html) && stripos($html, '</body>') !== false) {
    $html = preg_replace(
        '/<\/body>/i',
        '<script src="/js/whatsapp-menu.js" defer></script></body>',
        $html,
        1
    );
}

echo $html;
