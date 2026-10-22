<?php
declare(strict_types=1);
require_once __DIR__ . '/../../config/auth.php';
header('Cache-Control: no-store, private, max-age=0');
header('Pragma: no-cache');
header('X-Robots-Tag: noindex, nofollow');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    apiError(405, 'Méthode non autorisée');
}
$type = strtolower(trim(explode(';', $_SERVER['CONTENT_TYPE'] ?? '')[0]));
if ($type !== 'application/json') {
    apiError(415, 'Content-Type application/json requis');
}
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
$host = strtolower((string)($_SERVER['HTTP_HOST'] ?? ''));
if ($origin !== '') {
    $originHost = strtolower((string)parse_url($origin, PHP_URL_HOST));
    $requestHost = strtolower((string)parse_url('http://' . $host, PHP_URL_HOST));
    if ($originHost === '' || $requestHost === '' || $originHost !== $requestHost) {
        apiError(403, 'Origine non autorisée');
    }
}
$raw = file_get_contents('php://input');
if (!is_string($raw) || strlen($raw) > 16384) {
    apiError(413, 'Requête trop volumineuse');
}
try {
    $data = json_decode($raw, true, 32, JSON_THROW_ON_ERROR);
} catch (JsonException) {
    apiError(400, 'JSON invalide');
}
if (!is_array($data)) {
    apiError(400, 'Corps JSON invalide');
}

$expectedToken = getenv('IMC_PDG_RESET_TOKEN');
$providedToken = $data['recoveryToken'] ?? null;
$newPassword = $data['newPassword'] ?? null;
if (!is_string($expectedToken) || strlen($expectedToken) < 32 ||
    !is_string($providedToken) || !hash_equals($expectedToken, $providedToken)) {
    apiError(403, 'Code de récupération invalide ou non configuré.');
}
if (!is_string($newPassword) || strlen($newPassword) < 12 || strlen($newPassword) > 200) {
    apiError(400, 'Le mot de passe doit contenir entre 12 et 200 caractères.');
}
$hash = password_hash($newPassword, PASSWORD_DEFAULT);
if (!is_string($hash) || $hash === '') {
    apiError(500, 'Impossible de préparer le nouveau mot de passe.');
}

try {
    $pdo = getDatabaseConnection();
    $pdo->beginTransaction();
    $stmt = $pdo->prepare(
        "UPDATE users
         SET password_hash = :password_hash, updated_at = NOW()
         WHERE LOWER(username) = 'pdg'
           AND role_id = (SELECT id FROM roles WHERE UPPER(name) = 'PDG')"
    );
    $stmt->execute([':password_hash' => $hash]);
    if ($stmt->rowCount() !== 1) {
        throw new RuntimeException('Le compte PDG attendu est absent ou ambigu.');
    }
    $pdo->commit();
    echo json_encode(['success' => true], JSON_UNESCAPED_UNICODE);
} catch (Throwable $error) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('PDG password recovery failed: ' . $error->getMessage());
    apiError(500, 'Réinitialisation impossible. Contactez l’administrateur système.');
}
