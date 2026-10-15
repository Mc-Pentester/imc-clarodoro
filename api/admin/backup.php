<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

if (strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    header('Allow: POST');
    apiError(405, 'Méthode non autorisée');
}

$pdo = getDatabaseConnection();
$actor = requireAuthenticatedUser($pdo);
if (mb_strtoupper((string) ($actor['role_name'] ?? ''), 'UTF-8') !== 'PDG') {
    apiError(403, 'Seul le PDG peut lancer une sauvegarde manuelle.');
}
requireCsrfToken();

if (PHP_OS_FAMILY !== 'Windows' || !function_exists('proc_open')) {
    apiError(503, 'La sauvegarde manuelle via l’interface nécessite le service local Windows configuré.');
}

$projectRoot = dirname(__DIR__, 2);
$runner = $projectRoot . DIRECTORY_SEPARATOR . 'Scripts' . DIRECTORY_SEPARATOR . 'RUN-DB-BACKUP.ps1';
$backupDirectory = $projectRoot . DIRECTORY_SEPARATOR . 'backups';
if (!is_file($runner)) {
    apiError(503, 'Le lanceur de sauvegarde n’est pas installé. Réexécutez le script d’installation de la tâche de sauvegarde.');
}

$startedAt = time();
$command = 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File '
    . escapeshellarg($runner);
$descriptors = [
    0 => ['pipe', 'r'],
    1 => ['pipe', 'w'],
    2 => ['pipe', 'w'],
];
$process = proc_open($command, $descriptors, $pipes, $projectRoot);
if (!is_resource($process)) {
    error_log('IMC backup API: proc_open failed for manual backup.');
    apiError(500, 'Impossible de démarrer la sauvegarde.');
}
fclose($pipes[0]);
$stdout = stream_get_contents($pipes[1]);
$stderr = stream_get_contents($pipes[2]);
fclose($pipes[1]);
fclose($pipes[2]);
$exitCode = proc_close($process);

if ($exitCode !== 0) {
    error_log('IMC backup API: manual backup failed (exit ' . $exitCode . '): ' . trim((string) $stderr));
    apiError(500, 'La sauvegarde a échoué. Vérifiez les journaux de sauvegarde et la configuration PostgreSQL.');
}

$files = glob($backupDirectory . DIRECTORY_SEPARATOR . '*.backup') ?: [];
usort($files, static fn (string $a, string $b): int => filemtime($b) <=> filemtime($a));
$created = null;
foreach ($files as $candidate) {
    if (filemtime($candidate) >= $startedAt - 2) {
        $created = $candidate;
        break;
    }
}
if ($created === null) {
    error_log('IMC backup API: runner returned success but no fresh backup was found. ' . trim((string) $stdout));
    apiError(500, 'Le script a terminé sans produire de nouveau fichier de sauvegarde vérifiable.');
}

$manifestPath = $created . '.manifest.json';
if (!is_file($manifestPath)) {
    apiError(500, 'La sauvegarde a été créée, mais son manifeste est absent.');
}
try {
    $manifest = json_decode((string) file_get_contents($manifestPath), true, 512, JSON_THROW_ON_ERROR);
} catch (JsonException) {
    apiError(500, 'Le manifeste de sauvegarde est illisible.');
}
$actualHash = hash_file('sha256', $created);
$actualSize = filesize($created);
if (
    !is_array($manifest) ||
    !isset($manifest['sha256'], $manifest['sizeBytes']) ||
    !hash_equals((string) $manifest['sha256'], (string) $actualHash) ||
    (int) $manifest['sizeBytes'] !== (int) $actualSize
) {
    apiError(500, 'La sauvegarde a été créée, mais le contrôle d’intégrité a échoué.');
}

echo json_encode([
    'success' => true,
    'message' => 'Sauvegarde créée et intégrité SHA-256 vérifiée.',
    'file' => basename($created),
    'sizeBytes' => $actualSize,
    'sha256' => $actualHash,
    'externalCopy' => 'La copie sur le support portant l’étiquette IMC_BACKUPS sera effectuée par la tâche périodique.',
], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
