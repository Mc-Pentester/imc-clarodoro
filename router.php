<?php
declare(strict_types=1);

/**
 * Routeur pour le serveur PHP intégré : php -S 127.0.0.1:8090 router.php
 */
$path = rawurldecode((string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH));
$protected = [
    '/index.html' => 'index.html',
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

if (isset($protected[$path]) || isset($protected[strtolower($path)])) {
    $_GET['page'] = $protected[$path] ?? $protected[strtolower($path)];
    require __DIR__ . '/secure-page.php';
    exit;
}

if (str_starts_with($path, '/private-pages/')) {
    http_response_code(404);
    exit('Not found');
}

if ($path !== '/router.php' && is_file(__DIR__ . $path)) {
    return false;
}

return false;
