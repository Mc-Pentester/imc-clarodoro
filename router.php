<?php
declare(strict_types=1);

/**
 * Routeur pour le serveur PHP intégré.
 * Les fichiers applicatifs internes, runtimes, secrets et données ne sont jamais servis directement.
 */
$path = rawurldecode((string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH));
$path = str_replace('\\', '/', $path);
$path = preg_replace('#/+#', '/', $path) ?? '/';
$lowerPath = strtolower($path);

if (preg_match('#(?:^|/)\\.\\.(?:/|$)#', $path) === 1 || preg_match('#(?:^|/)\\.[^/]*#', $path) === 1) {
    http_response_code(404);
    exit('Not found');
}

$protected = [
    '/index.html' => 'index.html',
    '/eleves.html' => 'index.html',
    '/pdg.html' => 'PDG.html',
    '/finances.html' => 'finances.html',
    '/personnel.html' => 'personnel.html',
    '/badge.html' => 'badge.html',
    '/payroll-recovery.html' => 'payroll-recovery.html',
    '/resultats.html' => 'resultats.html',
    '/vacations.html' => 'vacations.html',
];

if ($path === '/') {
    $_GET['page'] = 'index.html';
    require __DIR__ . '/secure-page.php';
    exit;
}

if (isset($protected[$path]) || isset($protected[$lowerPath])) {
    $_GET['page'] = $protected[$path] ?? $protected[$lowerPath];
    require __DIR__ . '/secure-page.php';
    exit;
}

if ($path === '/whatsapp-send.html') {
    require __DIR__ . '/private-pages/whatsapp-send.php';
    exit;
}

$blockedDirectories = [
    '/runtime', '/installer', '/database', '/scripts', '/config',
    '/logs', '/backups', '/uploads', '/storage', '/tmp', '/cache',
    '/exports', '/private-pages', '/audit', '/docs', '/.git', '/.github',
];
foreach ($blockedDirectories as $directory) {
    if ($lowerPath === $directory || str_starts_with($lowerPath, $directory . '/')) {
        http_response_code(404);
        exit('Not found');
    }
}

if (in_array($lowerPath, ['/router.php', '/secure-page.php', '/bootstrap-auth.php'], true)
    || preg_match('/\\.(sql|ps1|ini|exe|dll|bat|cmd|log|bak|zip)$/i', $path) === 1) {
    http_response_code(404);
    exit('Not found');
}

$documentRoot = realpath(__DIR__);
$requestedFile = realpath(__DIR__ . $path);
if (
    $documentRoot !== false
    && $requestedFile !== false
    && is_file($requestedFile)
    && strncasecmp($requestedFile, $documentRoot . DIRECTORY_SEPARATOR, strlen($documentRoot . DIRECTORY_SEPARATOR)) === 0
) {
    return false;
}

http_response_code(404);
exit('Not found');
