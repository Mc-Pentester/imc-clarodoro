<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

function payrollError(int $status, string $message): never
{
    apiError($status, $message);
}

function payrollLabel(mixed $value): string
{
    if (!is_string($value)) {
        payrollError(422, 'school_year_label requis');
    }
    $label = preg_replace('/\s+/', '', trim($value));
    if (!is_string($label) || !preg_match('/^\d{4}-\d{4}$/', $label)) {
        payrollError(422, 'Année scolaire invalide');
    }
    return $label;
}

function payrollUuid(mixed $value, string $field): string
{
    if (!is_string($value) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $value)) {
        payrollError(422, $field . ' invalide');
    }
    return $value;
}

function payrollAmount(mixed $value, string $field): float
{
    if ((!is_int($value) && !is_float($value) && !is_string($value)) || !is_numeric($value)) {
        payrollError(422, $field . ' doit être un montant numérique');
    }
    $amount = round((float) $value, 2);
    if (!is_finite($amount) || $amount < 0 || $amount > 9999999999.99) {
        payrollError(422, $field . ' hors limites');
    }
    return $amount;
}

function payrollStatus(mixed $value): string
{
    return match ($value) {
        'Non payé', 'UNPAID' => 'UNPAID',
        'Partiel', 'PARTIAL' => 'PARTIAL',
        'Payé', 'PAID' => 'PAID',
        default => (payrollError(422, 'Statut de paie invalide')),
    };
}

function payrollSelectSql(): string
{
    return "SELECT pe.id, pe.staff_id, pe.school_year_id, sy.label AS school_year_label,
                   pe.payroll_month, pe.base_amount, pe.bonus_amount, pe.deduction_amount,
                   pe.net_amount, pe.status, pe.recorded_at, pe.created_at, pe.updated_at,
                   s.first_name, s.last_name, s.function_name, s.class_name
            FROM payroll_entries pe
            INNER JOIN staff s ON s.id = pe.staff_id
            INNER JOIN school_years sy ON sy.id = pe.school_year_id";
}

$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    requirePermission($pdo, 'paies.read');

    $where = [];
    $params = [];
    if (isset($_GET['school_year_label']) && $_GET['school_year_label'] !== '') {
        $label = payrollLabel($_GET['school_year_label']);
        $where[] = "REPLACE(sy.label, ' ', '') = :school_year_label";
        $params[':school_year_label'] = $label;
    }
    if (isset($_GET['staff_id']) && $_GET['staff_id'] !== '') {
        $where[] = 'pe.staff_id = :staff_id';
        $params[':staff_id'] = payrollUuid($_GET['staff_id'], 'staff_id');
    }
    $sql = payrollSelectSql();
    if ($where !== []) {
        $sql .= ' WHERE ' . implode(' AND ', $where);
    }
    $sql .= ' ORDER BY sy.label DESC, pe.payroll_month DESC, s.last_name, s.first_name';
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $entries = $stmt->fetchAll();
    foreach ($entries as &$entry) {
        foreach (['base_amount', 'bonus_amount', 'deduction_amount', 'net_amount'] as $field) {
            $entry[$field] = (float) $entry[$field];
        }
        $entry['payroll_month'] = (int) $entry['payroll_month'];
    }
    unset($entry);
    echo json_encode(['success' => true, 'payroll' => $entries], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($method !== 'POST') {
    header('Allow: GET, POST');
    payrollError(405, 'Méthode non autorisée');
}

requireAuthenticatedUser($pdo);
requireCsrfToken();
$data = readJsonBody();

$staffId = payrollUuid($data['staff_id'] ?? null, 'staff_id');
$schoolYearLabel = payrollLabel($data['school_year_label'] ?? null);
$monthValue = $data['month'] ?? null;
if (!is_int($monthValue) && !(is_string($monthValue) && ctype_digit($monthValue))) {
    payrollError(422, 'month invalide');
}
$month = (int) $monthValue;
if ($month < 1 || $month > 12) {
    payrollError(422, 'month doit être compris entre 1 et 12');
}
$base = payrollAmount($data['base'] ?? null, 'base');
$bonus = payrollAmount($data['bonuses'] ?? null, 'bonuses');
$deductions = payrollAmount($data['deductions'] ?? null, 'deductions');
$status = payrollStatus($data['status'] ?? null);

$yearStmt = $pdo->prepare("SELECT id FROM school_years WHERE REPLACE(label, ' ', '') = :label LIMIT 1");
$yearStmt->execute([':label' => $schoolYearLabel]);
$schoolYearId = $yearStmt->fetchColumn();
if ($schoolYearId === false) {
    payrollError(422, 'Année scolaire introuvable');
}

$staffStmt = $pdo->prepare("SELECT id FROM staff WHERE id = :id AND status <> 'ARCHIVED' LIMIT 1");
$staffStmt->execute([':id' => $staffId]);
if ($staffStmt->fetchColumn() === false) {
    payrollError(404, 'Membre du personnel introuvable ou archivé');
}

$existingStmt = $pdo->prepare(
    'SELECT id FROM payroll_entries
     WHERE staff_id = :staff_id AND school_year_id = :school_year_id AND payroll_month = :month'
);
$existingStmt->execute([
    ':staff_id' => $staffId,
    ':school_year_id' => $schoolYearId,
    ':month' => $month,
]);
$existingId = $existingStmt->fetchColumn();
requirePermission($pdo, $existingId === false ? 'paies.create' : 'paies.update');

try {
    if ($existingId === false) {
        $stmt = $pdo->prepare(
            'INSERT INTO payroll_entries
                (staff_id, school_year_id, payroll_month, base_amount, bonus_amount, deduction_amount, status, recorded_at)
             VALUES
                (:staff_id, :school_year_id, :month, :base, :bonus, :deductions, :status, NOW())
             RETURNING id'
        );
    } else {
        $stmt = $pdo->prepare(
            'UPDATE payroll_entries
             SET base_amount = :base, bonus_amount = :bonus, deduction_amount = :deductions,
                 status = :status, recorded_at = NOW(), updated_at = NOW()
             WHERE id = :id
             RETURNING id'
        );
    }

    $params = [
        ':staff_id' => $staffId,
        ':school_year_id' => $schoolYearId,
        ':month' => $month,
        ':base' => $base,
        ':bonus' => $bonus,
        ':deductions' => $deductions,
        ':status' => $status,
    ];
    if ($existingId !== false) {
        $params = [
            ':id' => $existingId,
            ':base' => $base,
            ':bonus' => $bonus,
            ':deductions' => $deductions,
            ':status' => $status,
        ];
    }
    $stmt->execute($params);
    $id = $stmt->fetchColumn();

    $resultStmt = $pdo->prepare(payrollSelectSql() . ' WHERE pe.id = :id');
    $resultStmt->execute([':id' => $id]);
    $entry = $resultStmt->fetch();
    foreach (['base_amount', 'bonus_amount', 'deduction_amount', 'net_amount'] as $field) {
        $entry[$field] = (float) $entry[$field];
    }
    $entry['payroll_month'] = (int) $entry['payroll_month'];

    http_response_code($existingId === false ? 201 : 200);
    echo json_encode(['success' => true, 'payroll' => $entry], JSON_UNESCAPED_UNICODE);
} catch (PDOException $error) {
    if ($error->getCode() === '23505') {
        payrollError(409, 'Une paie existe déjà pour ce membre, cette année et ce mois');
    }
    payrollError(500, 'Erreur interne du serveur');
}
