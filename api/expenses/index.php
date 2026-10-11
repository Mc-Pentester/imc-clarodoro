<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

function expenseUuid(string $value): string {
    if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value)) {
        apiError(400, 'expense_id invalide');
    }
    return $value;
}

function expenseSchoolYearId(PDO $pdo, string $label): string {
    if ($label === '' || strlen($label) > 50) {
        apiError(422, 'Année scolaire invalide');
    }
    $stmt = $pdo->prepare('SELECT id FROM school_years WHERE label = :label LIMIT 1');
    $stmt->execute([':label' => $label]);
    $id = $stmt->fetchColumn();
    if (!$id) {
        apiError(422, 'Année scolaire introuvable côté serveur');
    }
    return (string)$id;
}

$method = $_SERVER['REQUEST_METHOD'];
$pdo = getDatabaseConnection();

if ($method === 'GET') {
    requirePermission($pdo, 'depenses.read');
    $label = isset($_GET['school_year_label']) && is_string($_GET['school_year_label'])
        ? trim($_GET['school_year_label'])
        : '';
    $sql = 'SELECT e.id, sy.label AS school_year_label, e.description,
                   e.amount, e.expense_date, e.created_at, e.updated_at
            FROM expenses e
            INNER JOIN school_years sy ON sy.id = e.school_year_id';
    $params = [];
    if ($label !== '') {
        $sql .= ' WHERE sy.label = :label';
        $params[':label'] = $label;
    }
    $sql .= ' ORDER BY e.expense_date DESC, e.created_at DESC, e.id';
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $expenses = $stmt->fetchAll();
    foreach ($expenses as &$expense) {
        $expense['amount'] = (float)$expense['amount'];
    }
    unset($expense);
    echo json_encode(['success' => true, 'expenses' => $expenses], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($method === 'POST') {
    $user = requirePermission($pdo, 'depenses.create');
    requireCsrfToken();
    $data = readJsonBody();
    $description = isset($data['description']) && is_string($data['description'])
        ? trim($data['description'])
        : '';
    $amount = $data['amount'] ?? null;
    $date = isset($data['expense_date']) && is_string($data['expense_date'])
        ? $data['expense_date']
        : '';
    $label = isset($data['school_year_label']) && is_string($data['school_year_label'])
        ? trim($data['school_year_label'])
        : '';

    if ($description === '' || strlen($description) > 2000) {
        apiError(422, 'Description invalide');
    }
    if (!is_numeric($amount) || !is_finite((float)$amount) || (float)$amount <= 0) {
        apiError(422, 'Montant invalide');
    }
    $dateParts = explode('-', $date);
    if (count($dateParts) !== 3 || !checkdate((int)$dateParts[1], (int)$dateParts[2], (int)$dateParts[0])) {
        apiError(422, 'Date invalide');
    }
    $schoolYearId = expenseSchoolYearId($pdo, $label);
    $stmt = $pdo->prepare(
        'INSERT INTO expenses (school_year_id, description, amount, expense_date, created_by)
         VALUES (:school_year_id, :description, :amount, :expense_date, :created_by)
         RETURNING id, description, amount, expense_date'
    );
    $stmt->execute([
        ':school_year_id' => $schoolYearId,
        ':description' => $description,
        ':amount' => number_format((float)$amount, 2, '.', ''),
        ':expense_date' => $date,
        ':created_by' => $user['id'],
    ]);
    $expense = $stmt->fetch();
    $expense['amount'] = (float)$expense['amount'];
    http_response_code(201);
    echo json_encode(['success' => true, 'expense' => $expense], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($method === 'DELETE') {
    requirePermission($pdo, 'depenses.delete');
    requireCsrfToken();
    $id = expenseUuid(isset($_GET['expense_id']) ? (string)$_GET['expense_id'] : '');
    $stmt = $pdo->prepare('DELETE FROM expenses WHERE id = :id RETURNING id');
    $stmt->execute([':id' => $id]);
    $deleted = $stmt->fetchColumn();
    if (!$deleted) {
        apiError(404, 'Dépense introuvable');
    }
    echo json_encode(['success' => true, 'deleted' => true, 'id' => $deleted], JSON_UNESCAPED_UNICODE);
    exit;
}

header('Allow: GET, POST, DELETE');
apiError(405, 'Méthode HTTP non autorisée');
