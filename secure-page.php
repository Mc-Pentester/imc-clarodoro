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
    'eleves.html' => ['public' => 'eleves.html', 'file' => 'index.php', 'permission' => 'eleves.read', 'role' => null],
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
$pdo = null;
$access = null;
try {
    require_once __DIR__ . '/config/database.php';
    $pdo = getDatabaseConnection();
    $access = imcPageAccess($pdo, $page['permission'], $page['role']);
} catch (Throwable $error) {
    error_log('IMC protected page access check failed: ' . $error->getMessage());
    http_response_code(503);
    header('Content-Type: text/plain; charset=utf-8');
    header('Cache-Control: no-store, private');
    exit('Service temporairement indisponible.');
}

if (!$access['allowed']) {
    http_response_code((int) $access['status']);
    header('Content-Type: text/plain; charset=utf-8');
    header('Cache-Control: no-store, private');
    exit($access['status'] === 401 ? 'Authentification requise.' : 'Permission insuffisante.');
}

$privateFile = __DIR__ . '/private-pages/' . $page['file'];
if (!is_file($privateFile)) {
    http_response_code(500);
    exit('Page protégée indisponible.');
}

ob_start();
require $privateFile;
$html = ob_get_clean();

// N'injecter qu'avant la vraie fermeture du document, jamais dans une chaîne
// JavaScript contenant par exemple "</body>" pour générer un document Word.
if (is_string($html)) {
    $updated = preg_replace(
        '/<\/body>(\s*<\/html>\s*)$/i',
        '<script src="/js/whatsapp-menu.js" defer></script></body>$1',
        $html,
        1,
        $count
    );
    if (is_string($updated) && $count === 1) {
        $html = $updated;
    } else {
        error_log('WhatsApp menu injection skipped: final body/html closing tags not found.');
    }
}

header('Content-Type: text/html; charset=utf-8');
echo $html;
