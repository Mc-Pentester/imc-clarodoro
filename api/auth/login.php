<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    apiError(405, 'Méthode non autorisée');
}

configureAuthSession();

$data = readJsonBody();

$username = isset($data['username']) && is_string($data['username'])
    ? trim($data['username'])
    : '';

$password = isset($data['password']) && is_string($data['password'])
    ? $data['password']
    : '';

if ($username === '' || $password === '') {
    apiError(400, 'Identifiant et mot de passe requis');
}


function getClientIp(): string
{
    $ip = $_SERVER['REMOTE_ADDR'] ?? '';
    return filter_var($ip, FILTER_VALIDATE_IP) ? $ip : 'unknown';
}

function rateLimitKey(string $scope, string $value): string
{
    return hash('sha256', $scope . ':' . $value);
}

function checkLoginRateLimit(PDO $pdo, string $username, string $ip): void
{
    $keys = [
        rateLimitKey('username-ip', strtolower($username) . '|' . $ip),
        rateLimitKey('ip', $ip),
    ];

    $stmt = $pdo->prepare(
        'SELECT blocked_until
         FROM auth_login_attempts
         WHERE key_hash = :key_hash
         LIMIT 1'
    );

    foreach ($keys as $key) {
        $stmt->execute([':key_hash' => $key]);
        $row = $stmt->fetch();

        if ($row && $row['blocked_until'] !== null && strtotime($row['blocked_until']) > time()) {
            $retryAfter = max(1, strtotime($row['blocked_until']) - time());
            header('Retry-After: ' . $retryAfter);
            apiError(429, 'Trop de tentatives de connexion. Réessayez plus tard.');
        }
    }
}

function recordLoginFailure(PDO $pdo, string $username, string $ip): void
{
    $maxAttempts = max(1, (int) (getenv('AUTH_RATE_LIMIT_MAX_ATTEMPTS') ?: 5));
    $windowSeconds = max(1, (int) (getenv('AUTH_RATE_LIMIT_WINDOW_SECONDS') ?: 900));
    $keys = [
        rateLimitKey('username-ip', strtolower($username) . '|' . $ip),
        rateLimitKey('ip', $ip),
    ];

    $pdo->beginTransaction();

    try {
        foreach ($keys as $key) {
            $stmt = $pdo->prepare(
                'SELECT failed_attempts, first_failed_at
                 FROM auth_login_attempts
                 WHERE key_hash = :key_hash
                 FOR UPDATE'
            );
            $stmt->execute([':key_hash' => $key]);
            $row = $stmt->fetch();

            $now = time();
            if (!$row || ($now - strtotime($row['first_failed_at'])) >= $windowSeconds) {
                $failedAttempts = 1;
                $firstFailedAt = gmdate('Y-m-d H:i:sP');
            } else {
                $failedAttempts = ((int) $row['failed_attempts']) + 1;
                $firstFailedAt = $row['first_failed_at'];
            }

            $blockedUntil = $failedAttempts >= $maxAttempts
                ? gmdate('Y-m-d H:i:sP', $now + $windowSeconds)
                : null;

            $upsert = $pdo->prepare(
                'INSERT INTO auth_login_attempts
                    (key_hash, failed_attempts, first_failed_at, blocked_until, updated_at)
                 VALUES
                    (:key_hash, :failed_attempts, :first_failed_at, :blocked_until, NOW())
                 ON CONFLICT (key_hash) DO UPDATE SET
                    failed_attempts = EXCLUDED.failed_attempts,
                    first_failed_at = EXCLUDED.first_failed_at,
                    blocked_until = EXCLUDED.blocked_until,
                    updated_at = NOW()'
            );

            $upsert->execute([
                ':key_hash' => $key,
                ':failed_attempts' => $failedAttempts,
                ':first_failed_at' => $firstFailedAt,
                ':blocked_until' => $blockedUntil,
            ]);
        }

        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }
}

function clearLoginRateLimit(PDO $pdo, string $username, string $ip): void
{
    $keys = [
        rateLimitKey('username-ip', strtolower($username) . '|' . $ip),
        rateLimitKey('ip', $ip),
    ];

    $stmt = $pdo->prepare(
        'DELETE FROM auth_login_attempts
         WHERE key_hash = :key_hash'
    );

    foreach ($keys as $key) {
        $stmt->execute([':key_hash' => $key]);
    }
}

$pdo = getDatabaseConnection();
$clientIp = getClientIp();
checkLoginRateLimit($pdo, $username, $clientIp);

$stmt = $pdo->prepare(
    'SELECT
        u.id,
        u.username,
        u.password_hash,
        u.role_id,
        u.status,
        r.name AS role_name
     FROM users u
     INNER JOIN roles r
        ON r.id = u.role_id
     WHERE u.username = :username
     LIMIT 1'
);

$stmt->execute([
    ':username' => $username,
]);

$user = $stmt->fetch();

if (!$user || !password_verify($password, $user['password_hash'])) {
    recordLoginFailure($pdo, $username, $clientIp);
    apiError(401, 'Identifiant ou mot de passe incorrect');
}

if ($user['status'] !== 'ACTIVE') {
    recordLoginFailure($pdo, $username, $clientIp);
    apiError(403, 'Compte non actif');
}

clearLoginRateLimit($pdo, $username, $clientIp);

session_regenerate_id(true);

$_SESSION['user_id'] = $user['id'];
$_SESSION['username'] = $user['username'];
$_SESSION['role_id'] = $user['role_id'];
$_SESSION['role_name'] = $user['role_name'];
$_SESSION['authenticated_at'] = time();

echo json_encode([
    'success' => true,
    'user' => [
        'id' => $user['id'],
        'username' => $user['username'],
        'role' => $user['role_name'],
    ],
], JSON_UNESCAPED_UNICODE);