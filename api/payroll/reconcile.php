<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

function payrollReconcileError(int $status, string $message): never
{
    apiError($status, $message);
}

function payrollReconcileLabel(mixed $value): string
{
    if (!is_string($value)) {
        payrollReconcileError(422, 'Année scolaire requise');
    }
    $label = preg_replace('/\\s+/', '', trim($value));
    if (!is_string($label) || !preg_match('/^\\d{4}-\\d{4}$/', $label)) {
        payrollReconcileError(422, 'Année scolaire invalide');
    }
    return $label;
}

function payrollReconcileAmount(mixed $value, string $field): float
{
    if ((!is_int($value) && !is_float($value) && !is_string($value)) || !is_numeric($value)) {
        payrollReconcileError(422, $field . ' doit être numérique');
    }
    $amount = round((float) $value, 2);
    if (!is_finite($amount) || $amount < 0 || $amount > 9999999999.99) {
        payrollReconcileError(422, $field . ' hors limites');
    }
    return $amount;
}

function payrollReconcileStatus(mixed $value): string
{
    return match ($value) {
        'Non payé', 'UNPAID' => 'UNPAID',
        'Partiel', 'PARTIAL' => 'PARTIAL',
        'Payé', 'PAID' => 'PAID',
        default => (payrollReconcileError(422, 'Statut de paie invalide')),
    };
}

$pdo = getDatabaseConnection();
$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

if ($method === 'GET') {
    requirePermission($pdo, 'paies.reconcile');
    $stmt = $pdo->query(
        'SELECT source_key_hash, target_staff_id, payroll_entry_id, created_at
         FROM payroll_reconciliation_audit
         ORDER BY created_at DESC'
    );
    echo json_encode([
        'success' => true,
        'reconciliations' => $stmt->fetchAll(),
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($method !== 'POST') {
    header('Allow: GET, POST');
    payrollReconcileError(405, 'Méthode non autorisée');
}

$actor = requirePermission($pdo, 'paies.reconcile');
requireCsrfToken();
$data = readJsonBody();

$sourceKey = $data['source_key'] ?? null;
if (!is_string($sourceKey) || $sourceKey === '' || strlen($sourceKey) > 512) {
    payrollReconcileError(422, 'Clé source invalide');
}
$sourceParts = explode('|', $sourceKey);
if (count($sourceParts) !== 3) {
    payrollReconcileError(422, 'Clé source historique invalide');
}

$schoolYearLabel = payrollReconcileLabel($data['school_year_label'] ?? null);
$monthValue = $data['month'] ?? null;
if (!is_int($monthValue) && !(is_string($monthValue) && ctype_digit($monthValue))) {
    payrollReconcileError(422, 'Mois invalide');
}
$month = (int) $monthValue;
if ($month < 1 || $month > 12) {
    payrollReconcileError(422, 'Mois hors limites');
}
if (
    preg_replace('/\\s+/', '', $sourceParts[0]) !== $schoolYearLabel ||
    !preg_match('/^\\d{1,2}$/', $sourceParts[2]) ||
    (int) $sourceParts[2] !== $month
) {
    payrollReconcileError(422, 'La clé source ne correspond pas à l’année et au mois déclarés');
}

$sourceStaffId = $data['source_staff_id'] ?? $sourceParts[1];
if (!is_string($sourceStaffId) && !is_int($sourceStaffId)) {
    payrollReconcileError(422, 'Identifiant historique invalide');
}
$sourceStaffId = trim((string) $sourceStaffId);
if ($sourceStaffId === '' || strlen($sourceStaffId) > 200) {
    payrollReconcileError(422, 'Identifiant historique invalide');
}

$targetStaffId = $data['target_staff_id'] ?? null;
if (!is_string($targetStaffId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $targetStaffId)) {
    payrollReconcileError(422, 'Membre du personnel cible invalide');
}
$base = payrollReconcileAmount($data['base'] ?? null, 'Salaire de base');
$bonus = payrollReconcileAmount($data['bonuses'] ?? 0, 'Primes');
$deductions = payrollReconcileAmount($data['deductions'] ?? 0, 'Déductions');
$status = payrollReconcileStatus($data['status'] ?? 'UNPAID');
$sourceHash = hash('sha256', $sourceKey);

$pdo->beginTransaction();
try {
    $existingSource = $pdo->prepare(
        'SELECT payroll_entry_id, target_staff_id, created_at
         FROM payroll_reconciliation_audit
         WHERE source_key_hash = :source_hash
         FOR UPDATE'
    );
    $existingSource->execute([':source_hash' => $sourceHash]);
    $alreadyImported = $existingSource->fetch();
    if ($alreadyImported) {
        $pdo->commit();
        http_response_code(200);
        echo json_encode([
            'success' => true,
            'created' => false,
            'already_imported' => true,
            'payroll_id' => $alreadyImported['payroll_entry_id'],
            'target_staff_id' => $alreadyImported['target_staff_id'],
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $yearStmt = $pdo->prepare(
        "SELECT id FROM school_years WHERE REPLACE(label, ' ', '') = :label LIMIT 1 FOR SHARE"
    );
    $yearStmt->execute([':label' => $schoolYearLabel]);
    $schoolYearId = $yearStmt->fetchColumn();
    if ($schoolYearId === false) {
        $pdo->rollBack();
        payrollReconcileError(422, 'Année scolaire introuvable');
    }

    $staffStmt = $pdo->prepare(
        "SELECT id FROM staff WHERE id = :id AND status <> 'ARCHIVED' FOR SHARE"
    );
    $staffStmt->execute([':id' => $targetStaffId]);
    if ($staffStmt->fetchColumn() === false) {
        $pdo->rollBack();
        payrollReconcileError(404, 'Membre du personnel cible introuvable ou archivé');
    }

    $duplicateStmt = $pdo->prepare(
        'SELECT id FROM payroll_entries
         WHERE staff_id = :staff_id AND school_year_id = :school_year_id AND payroll_month = :month
         FOR UPDATE'
    );
    $duplicateStmt->execute([
        ':staff_id' => $targetStaffId,
        ':school_year_id' => $schoolYearId,
        ':month' => $month,
    ]);
    if ($duplicateStmt->fetchColumn() !== false) {
        $pdo->rollBack();
        payrollReconcileError(409, 'Une paie existe déjà pour cette personne, cette année et ce mois. Aucune donnée n’a été modifiée.');
    }

    $insert = $pdo->prepare(
        'INSERT INTO payroll_entries
            (staff_id, school_year_id, payroll_month, base_amount, bonus_amount,
             deduction_amount, status, recorded_at, legacy_source_key)
         VALUES
            (:staff_id, :school_year_id, :month, :base, :bonus, :deductions, :status, NOW(), :source_hash)
         RETURNING id'
    );
    $insert->execute([
        ':staff_id' => $targetStaffId,
        ':school_year_id' => $schoolYearId,
        ':month' => $month,
        ':base' => $base,
        ':bonus' => $bonus,
        ':deductions' => $deductions,
        ':status' => $status,
        ':source_hash' => $sourceHash,
    ]);
    $payrollId = $insert->fetchColumn();

    $audit = $pdo->prepare(
        "INSERT INTO payroll_reconciliation_audit
            (source_key_hash, source_staff_id, target_staff_id, school_year_id,
             payroll_month, payroll_entry_id, actor_user_id, action)
         VALUES
            (:source_hash, :source_staff_id, :target_staff_id, :school_year_id,
             :month, :payroll_id, :actor_id, 'IMPORTED')"
    );
    $audit->execute([
        ':source_hash' => $sourceHash,
        ':source_staff_id' => $sourceStaffId,
        ':target_staff_id' => $targetStaffId,
        ':school_year_id' => $schoolYearId,
        ':month' => $month,
        ':payroll_id' => $payrollId,
        ':actor_id' => $actor['id'],
    ]);

    $pdo->commit();
    http_response_code(201);
    echo json_encode([
        'success' => true,
        'created' => true,
        'already_imported' => false,
        'payroll_id' => $payrollId,
        'target_staff_id' => $targetStaffId,
    ], JSON_UNESCAPED_UNICODE);
} catch (PDOException $error) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    if ($error->getCode() === '23505') {
        payrollReconcileError(409, 'Cette paie historique a déjà été importée ou entre en conflit. Aucune donnée locale n’a été supprimée.');
    }
    payrollReconcileError(500, 'Erreur interne pendant le rapprochement');
}
