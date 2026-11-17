<?php
declare(strict_types=1);
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') { header('Allow: GET'); apiError(405, 'Méthode non autorisée'); }
$pdo = getDatabaseConnection();
requirePermission($pdo, 'whatsapp.consent.read');
$q = trim((string) ($_GET['q'] ?? ''));
if (strlen($q) < 2 || strlen($q) > 100) apiError(422, 'Saisissez au moins 2 caractères.');
$like = '%' . $q . '%';
$stmt = $pdo->prepare(
    "SELECT id, first_name, last_name, email, phone FROM parents
     WHERE first_name ILIKE :q1 OR last_name ILIKE :q2
        OR (first_name || ' ' || last_name) ILIKE :q3 OR email ILIKE :q4
        OR regexp_replace(COALESCE(phone,''), '[^0-9]', '', 'g') LIKE regexp_replace(:digits, '[^0-9]', '', 'g')
     ORDER BY last_name, first_name LIMIT 25"
);
$stmt->execute([':q1'=>$like, ':q2'=>$like, ':q3'=>$like, ':q4'=>$like, ':digits'=>$like]);
echo json_encode(['success'=>true, 'parents'=>$stmt->fetchAll()], JSON_UNESCAPED_UNICODE);
