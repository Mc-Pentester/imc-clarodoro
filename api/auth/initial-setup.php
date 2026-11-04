<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    apiError(405, 'Méthode non autorisée');
}

configureAuthSession();
requireCsrfToken();
$data = readJsonBody();
$password = isset($data['password']) && is_string($data['password']) ? $data['password'] : '';
$confirmation = isset($data['confirmation']) && is_string($data['confirmation']) ? $data['confirmation'] : '';

if (strlen($password) < 12 || preg_match('/^[\x20-\x7E]+$/D', $password) !== 1) {
    apiError(400, 'Le mot de passe doit contenir au moins 12 caractères ASCII imprimables.');
}
if (!hash_equals($password, $confirmation)) {
    apiError(400, 'Les deux mots de passe ne correspondent pas.');
}

$pdo = getDatabaseConnection();
$existing = $pdo->query(
    "SELECT 1 FROM users u LEFT JOIN roles r ON r.id = u.role_id
     WHERE LOWER(u.username) = 'pdg' OR r.name = 'PDG' LIMIT 1"
)->fetchColumn();
if ($existing !== false) {
    apiError(409, 'La configuration initiale est déjà terminée.');
}

$bootstrap = dirname(__DIR__, 2) . DIRECTORY_SEPARATOR . 'bootstrap-auth.php';
if (!is_file($bootstrap) || !function_exists('proc_open')) {
    error_log('Clarodaro first-run bootstrap unavailable: missing CLI script or proc_open.');
    apiError(503, 'La création initiale du compte est momentanément indisponible.');
}

$environment = getenv();
if (!is_array($environment)) {
    $environment = [];
}
$environment['IMC_BOOTSTRAP_PASSWORD'] = $password;
$descriptors = [
    0 => ['pipe', 'r'],
    1 => ['pipe', 'w'],
    2 => ['pipe', 'w'],
];

$process = proc_open(
    [PHP_BINARY, $bootstrap],
    $descriptors,
    $pipes,
    dirname(__DIR__, 2),
    $environment,
    ['bypass_shell' => true]
);
if (!is_resource($process)) {
    apiError(503, 'Impossible de démarrer la configuration initiale.');
}
fclose($pipes[0]);
$stdout = stream_get_contents($pipes[1]);
fclose($pipes[1]);
$stderr = stream_get_contents($pipes[2]);
fclose($pipes[2]);
$exitCode = proc_close($process);
unset($environment['IMC_BOOTSTRAP_PASSWORD'], $password, $confirmation, $data);

if ($exitCode !== 0) {
    error_log('Clarodaro first-run bootstrap failed: ' . trim((string) $stderr . ' ' . (string) $stdout));
    apiError(409, 'La création du compte PDG a échoué. Vérifiez que la configuration initiale n’a pas déjà été effectuée.');
}

$verify = $pdo->query(
    "SELECT COUNT(*) FROM users u INNER JOIN roles r ON r.id = u.role_id
     WHERE LOWER(u.username) = 'pdg' AND r.name = 'PDG' AND u.status = 'ACTIVE'"
)->fetchColumn();
if ((int) $verify !== 1) {
    error_log('Clarodaro first-run bootstrap exited successfully but PDG verification failed.');
    apiError(500, 'Le compte PDG n’a pas pu être vérifié après sa création.');
}

$_SESSION = [];
session_destroy();

echo json_encode(['success' => true], JSON_UNESCAPED_UNICODE);
