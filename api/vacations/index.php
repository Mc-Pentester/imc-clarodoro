<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

function vacationDateIsValid(mixed $value): bool
{
    if (!is_string($value) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $value)) {
        return false;
    }

    $date = DateTimeImmutable::createFromFormat('!Y-m-d', $value);
    return $date !== false && $date->format('Y-m-d') === $value;
}

function validateVacationName(mixed $value): string
{
    if (!is_string($value)) {
        apiError(422, 'name doit être une chaîne de caractères');
    }

    $name = trim($value);
    if ($name === '' || preg_match_all('/./us', $name) > 150) {
        apiError(422, 'name est requis et limité à 150 caractères');
    }

    return $name;
}

$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    requirePermission($pdo, 'vacances.read');
    $stmt = $pdo->query(
        "SELECT id, name, start_date, end_date, status, created_at, updated_at
         FROM vacations
         WHERE status <> 'ARCHIVED'
         ORDER BY start_date DESC, id DESC"
    );
    echo json_encode(['success' => true, 'vacations' => $stmt->fetchAll()], JSON_UNESCAPED_UNICODE);
    exit;
}

if (!in_array($method, ['POST', 'PATCH'], true)) {
    header('Allow: GET, POST, PATCH');
    apiError(405, 'Méthode non autorisée');
}

if ($method === 'POST') {
    requirePermission($pdo, 'vacances.create');
    requireCsrfToken();
    $data = readJsonBody();

    $name = validateVacationName($data['name'] ?? null);
    $start = $data['start_date'] ?? null;
    $end = $data['end_date'] ?? null;

    if (!vacationDateIsValid($start) || !vacationDateIsValid($end)) {
        apiError(422, 'start_date et end_date doivent être des dates valides au format AAAA-MM-JJ');
    }
    if ($end < $start) {
        apiError(422, 'end_date doit être supérieure ou égale à start_date');
    }

    try {
        $stmt = $pdo->prepare(
            'INSERT INTO vacations (name, start_date, end_date, status)
             VALUES (:name, :start_date, :end_date, \'ACTIVE\')
             RETURNING id, name, start_date, end_date, status, created_at, updated_at'
        );
        $stmt->execute([':name' => $name, ':start_date' => $start, ':end_date' => $end]);
        http_response_code(201);
        echo json_encode(['success' => true, 'vacation' => $stmt->fetch()], JSON_UNESCAPED_UNICODE);
    } catch (PDOException $error) {
        if ($error->getCode() === '23505') {
            apiError(409, 'Une période de vacances portant ce nom existe déjà');
        }
        apiError(500, 'Erreur interne du serveur');
    }
    exit;
}

// PATCH: distinguish archiving from ordinary edits so the API enforces the
// same separate permissions as the UI (vacances.delete vs vacances.update).
requireAuthenticatedUser($pdo);
requireCsrfToken();
$data = readJsonBody();
$isArchive = ($data['status'] ?? null) === 'ARCHIVED';

if ($isArchive && array_keys($data) !== ['status']) {
    apiError(422, 'L’archivage ne peut modifier que le statut');
}

requirePermission($pdo, $isArchive ? 'vacances.delete' : 'vacances.update');

$id = $_GET['id'] ?? '';
if (!is_string($id) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $id)) {
    apiError(400, 'UUID invalide');
}

$allowedFields = ['name', 'start_date', 'end_date', 'status'];
$set = [];
$params = [':id' => $id];

foreach ($data as $field => $value) {
    if (!in_array($field, $allowedFields, true)) {
        apiError(422, 'Champ non autorisé');
    }

    if ($field === 'name') {
        $value = validateVacationName($value);
    } elseif (in_array($field, ['start_date', 'end_date'], true)) {
        if (!vacationDateIsValid($value)) {
            apiError(422, $field . ' doit être une date valide au format AAAA-MM-JJ');
        }
    } elseif ($field === 'status' && !in_array($value, ['ACTIVE', 'INACTIVE', 'ARCHIVED'], true)) {
        apiError(422, 'Statut invalide');
    }

    $set[] = $field . ' = :' . $field;
    $params[':' . $field] = $value;
}

if ($set === []) {
    apiError(422, 'Aucun champ à modifier');
}

$existing = $pdo->prepare('SELECT start_date, end_date FROM vacations WHERE id = :id');
$existing->execute([':id' => $id]);
$current = $existing->fetch();
if (!$current) {
    apiError(404, 'Période de vacances introuvable');
}

$start = $params[':start_date'] ?? (string) $current['start_date'];
$end = $params[':end_date'] ?? (string) $current['end_date'];
if ($end < $start) {
    apiError(422, 'end_date doit être supérieure ou égale à start_date');
}

$set[] = 'updated_at = NOW()';

try {
    $stmt = $pdo->prepare(
        'UPDATE vacations SET ' . implode(', ', $set) .
        ' WHERE id = :id RETURNING id, name, start_date, end_date, status, created_at, updated_at'
    );
    $stmt->execute($params);
    echo json_encode(['success' => true, 'vacation' => $stmt->fetch()], JSON_UNESCAPED_UNICODE);
} catch (PDOException $error) {
    if ($error->getCode() === '23505') {
        apiError(409, 'Une période de vacances portant ce nom existe déjà');
    }
    apiError(500, 'Erreur interne du serveur');
}
