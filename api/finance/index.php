<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'];

function financeUuid(string $value, string $field): string
{
    if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value)) {
        apiError(422, $field . ' UUID invalide');
    }
    return $value;
}

function financeMoney(mixed $value, string $field, bool $allowZero = true): float
{
    if (!is_numeric($value) || !is_finite((float) $value)) {
        apiError(422, $field . ' doit être numérique');
    }
    $amount = round((float) $value, 2);
    if ($allowZero ? $amount < 0 : $amount <= 0) {
        apiError(422, $field . ' invalide');
    }
    return $amount;
}

if ($method === 'GET') {
    $user = requirePermission($pdo, 'finances.read');

    $yearId = isset($_GET['school_year_id'])
        ? financeUuid((string) $_GET['school_year_id'], 'school_year_id')
        : null;
    $studentId = isset($_GET['student_id'])
        ? financeUuid((string) $_GET['student_id'], 'student_id')
        : null;

    $where = [];
    $params = [];

    if ($yearId !== null) {
        $where[] = 'e.school_year_id = :school_year_id';
        $params[':school_year_id'] = $yearId;
    }
    if ($studentId !== null) {
        $where[] = 'i.student_id = :student_id';
        $params[':student_id'] = $studentId;
    }

    $sql = 'SELECT
                i.id,
                i.student_id,
                i.enrollment_id,
                i.amount,
                i.base_amount,
                i.discount_amount,
                i.discount_reason,
                i.status,
                i.invoice_date,
                i.description,
                i.created_at,
                i.updated_at,
                s.matricule,
                s.last_name,
                s.first_name,
                e.class_id,
                c.name AS class_name,
                e.school_year_id,
                sy.label AS school_year_label,
                COALESCE(SUM(CASE WHEN p.id IS NOT NULL THEN p.amount ELSE 0 END), 0) AS paid_amount
            FROM invoices i
            INNER JOIN students s ON s.id = i.student_id
            LEFT JOIN enrollments e ON e.id = i.enrollment_id
            LEFT JOIN classes c ON c.id = e.class_id
            LEFT JOIN school_years sy ON sy.id = e.school_year_id
            LEFT JOIN payments p ON p.invoice_id = i.id';

    if ($where) {
        $sql .= ' WHERE ' . implode(' AND ', $where);
    }

    $sql .= ' GROUP BY i.id, s.id, e.id, c.id, sy.id
              ORDER BY i.invoice_date DESC, s.last_name, s.first_name, i.id';

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $invoices = $stmt->fetchAll();

    foreach ($invoices as &$invoice) {
        $invoice['balance'] = max(
            0,
            (float) $invoice['amount'] - (float) $invoice['paid_amount']
        );
    }
    unset($invoice);

    $paymentsSql = 'SELECT
                        p.id, p.invoice_id, p.amount, p.payment_date,
                        p.method, p.reference, p.created_at, p.updated_at
                    FROM payments p
                    INNER JOIN invoices i ON i.id = p.invoice_id';
    $paymentWhere = [];
    $paymentParams = [];

    if ($yearId !== null) {
        $paymentWhere[] = 'EXISTS (
            SELECT 1 FROM enrollments pe
            WHERE pe.id = i.enrollment_id
              AND pe.school_year_id = :payment_school_year_id
        )';
        $paymentParams[':payment_school_year_id'] = $yearId;
    }
    if ($studentId !== null) {
        $paymentWhere[] = 'i.student_id = :payment_student_id';
        $paymentParams[':payment_student_id'] = $studentId;
    }

    if ($paymentWhere) {
        $paymentsSql .= ' WHERE ' . implode(' AND ', $paymentWhere);
    }
    $paymentsSql .= ' ORDER BY p.payment_date DESC, p.created_at DESC, p.id';

    $paymentStmt = $pdo->prepare($paymentsSql);
    $paymentStmt->execute($paymentParams);

    $scheduleSql = 'SELECT
                        fs.id, fs.school_year_id, fs.class_id,
                        fs.total_amount,
                        fs.installment_1_amount, fs.installment_1_label,
                        fs.installment_2_amount, fs.installment_2_label,
                        fs.installment_3_amount, fs.installment_3_label,
                        fs.status, fs.created_at, fs.updated_at,
                        c.name AS class_name, sy.label AS school_year_label
                    FROM fee_schedules fs
                    INNER JOIN classes c ON c.id = fs.class_id
                    INNER JOIN school_years sy ON sy.id = fs.school_year_id
                    WHERE fs.status = \'ACTIVE\'';

    $scheduleParams = [];
    if ($yearId !== null) {
        $scheduleSql .= ' AND fs.school_year_id = :schedule_year_id';
        $scheduleParams[':schedule_year_id'] = $yearId;
    }
    $scheduleSql .= ' ORDER BY sy.start_date DESC, c.name, fs.id';

    $scheduleStmt = $pdo->prepare($scheduleSql);
    $scheduleStmt->execute($scheduleParams);

    $enrollmentSql = "SELECT
                          e.id AS enrollment_id,
                          e.student_id,
                          e.class_id,
                          c.name AS class_name,
                          e.school_year_id,
                          sy.label AS school_year_label,
                          s.matricule,
                          s.last_name,
                          s.first_name
                      FROM enrollments e
                      INNER JOIN students s ON s.id = e.student_id
                      INNER JOIN classes c ON c.id = e.class_id
                      INNER JOIN school_years sy ON sy.id = e.school_year_id
                      WHERE e.status = 'ACTIVE'";
    $enrollmentParams = [];
    if ($yearId !== null) {
        $enrollmentSql .= ' AND e.school_year_id = :enrollment_year_id';
        $enrollmentParams[':enrollment_year_id'] = $yearId;
    }
    if ($studentId !== null) {
        $enrollmentSql .= ' AND e.student_id = :enrollment_student_id';
        $enrollmentParams[':enrollment_student_id'] = $studentId;
    }
    $enrollmentSql .= ' ORDER BY s.last_name, s.first_name, e.id';
    $enrollmentStmt = $pdo->prepare($enrollmentSql);
    $enrollmentStmt->execute($enrollmentParams);

    $schoolYearStmt = $pdo->query(
        "SELECT id, label, start_date, end_date, status
         FROM school_years
         WHERE status IN ('PLANNED','ACTIVE','CLOSED')
         ORDER BY start_date DESC, id DESC"
    );

    echo json_encode([
        'success' => true,
        'invoices' => $invoices,
        'payments' => $paymentStmt->fetchAll(),
        'schedules' => $scheduleStmt->fetchAll(),
        'enrollments' => $enrollmentStmt->fetchAll(),
        'school_years' => $schoolYearStmt->fetchAll(),
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($method !== 'POST') {
    header('Allow: GET, POST');
    apiError(405, 'Méthode HTTP non autorisée');
}

$user = requirePermission($pdo, 'finances.create');
requireCsrfToken();
$data = readJsonBody();
$type = $data['type'] ?? '';

if (!is_string($type) || !in_array($type, ['invoice', 'payment', 'schedule'], true)) {
    apiError(422, 'type financier invalide');
}

try {
    if ($type === 'invoice') {
        foreach (array_keys($data) as $field) {
            if (!in_array($field, [
                'type', 'enrollment_id', 'base_amount', 'discount_amount',
                'discount_reason', 'invoice_date', 'description'
            ], true)) {
                apiError(422, 'Champ inconnu: ' . $field);
            }
        }

        $enrollmentId = financeUuid((string) ($data['enrollment_id'] ?? ''), 'enrollment_id');
        $base = financeMoney($data['base_amount'] ?? null, 'base_amount');
        $discount = financeMoney($data['discount_amount'] ?? 0, 'discount_amount');

        if ($discount > $base) {
            apiError(422, 'La réduction ne peut pas dépasser le montant de base');
        }

        $date = $data['invoice_date'] ?? date('Y-m-d');
        if (!is_string($date) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
            apiError(422, 'invoice_date invalide');
        }

        $check = $pdo->prepare(
            'SELECT e.student_id
             FROM enrollments e
             WHERE e.id = :id AND e.status = \'ACTIVE\''
        );
        $check->execute([':id' => $enrollmentId]);
        $enrollment = $check->fetch();

        if (!$enrollment) {
            apiError(404, 'Inscription active introuvable');
        }

        $amount = round($base - $discount, 2);

        if ($amount <= 0) {
            apiError(422, 'Le montant final de la facture doit être supérieur à zéro');
        }

        $stmt = $pdo->prepare(
            'INSERT INTO invoices (
                student_id, enrollment_id, amount, base_amount,
                discount_amount, discount_reason, status,
                invoice_date, description
             )
             VALUES (
                :student_id, :enrollment_id, :amount, :base_amount,
                :discount_amount, :discount_reason, \'OPEN\',
                :invoice_date, :description
             )
             RETURNING id, student_id, enrollment_id, amount, base_amount,
                       discount_amount, discount_reason, status,
                       invoice_date, description, created_at, updated_at'
        );

        $stmt->execute([
            ':student_id' => $enrollment['student_id'],
            ':enrollment_id' => $enrollmentId,
            ':amount' => $amount,
            ':base_amount' => $base,
            ':discount_amount' => $discount,
            ':discount_reason' => isset($data['discount_reason']) ? (string) $data['discount_reason'] : null,
            ':invoice_date' => $date,
            ':description' => isset($data['description']) ? (string) $data['description'] : null,
        ]);

        http_response_code(201);
        echo json_encode(['success' => true, 'invoice' => $stmt->fetch()], JSON_UNESCAPED_UNICODE);
        exit;
    }

    if ($type === 'schedule') {
        foreach (array_keys($data) as $field) {
            if (!in_array($field, [
                'type', 'school_year_id', 'class_id', 'total_amount',
                'installment_1_amount', 'installment_1_label',
                'installment_2_amount', 'installment_2_label',
                'installment_3_amount', 'installment_3_label'
            ], true)) {
                apiError(422, 'Champ inconnu: ' . $field);
            }
        }

        $yearId = financeUuid((string) ($data['school_year_id'] ?? ''), 'school_year_id');
        $classId = financeUuid((string) ($data['class_id'] ?? ''), 'class_id');
        $total = financeMoney($data['total_amount'] ?? null, 'total_amount', false);
        $i1 = financeMoney($data['installment_1_amount'] ?? 0, 'installment_1_amount');
        $i2 = financeMoney($data['installment_2_amount'] ?? 0, 'installment_2_amount');
        $i3 = financeMoney($data['installment_3_amount'] ?? 0, 'installment_3_amount');

        if (round($i1 + $i2 + $i3, 2) !== $total) {
            apiError(422, 'La somme des versements doit être égale au total');
        }

        $pdo->beginTransaction();
        $pdo->prepare(
            'UPDATE fee_schedules SET status = \'INACTIVE\', updated_at = NOW()
             WHERE school_year_id = :year AND class_id = :class AND status = \'ACTIVE\''
        )->execute([':year' => $yearId, ':class' => $classId]);

        $stmt = $pdo->prepare(
            'INSERT INTO fee_schedules (
                school_year_id, class_id, total_amount,
                installment_1_amount, installment_1_label,
                installment_2_amount, installment_2_label,
                installment_3_amount, installment_3_label
             ) VALUES (
                :year, :class, :total,
                :i1, :l1, :i2, :l2, :i3, :l3
             )
             RETURNING *'
        );
        $stmt->execute([
            ':year' => $yearId,
            ':class' => $classId,
            ':total' => $total,
            ':i1' => $i1,
            ':l1' => isset($data['installment_1_label']) ? (string) $data['installment_1_label'] : null,
            ':i2' => $i2,
            ':l2' => isset($data['installment_2_label']) ? (string) $data['installment_2_label'] : null,
            ':i3' => $i3,
            ':l3' => isset($data['installment_3_label']) ? (string) $data['installment_3_label'] : null,
        ]);
        $schedule = $stmt->fetch();
        $pdo->commit();

        http_response_code(201);
        echo json_encode(['success' => true, 'schedule' => $schedule], JSON_UNESCAPED_UNICODE);
        exit;
    }

    foreach (array_keys($data) as $field) {
        if (!in_array($field, ['type', 'invoice_id', 'amount', 'payment_date', 'method', 'reference'], true)) {
            apiError(422, 'Champ inconnu: ' . $field);
        }
    }

    $invoiceId = financeUuid((string) ($data['invoice_id'] ?? ''), 'invoice_id');
    $amount = financeMoney($data['amount'] ?? null, 'amount', false);
    $date = $data['payment_date'] ?? date('Y-m-d');

    if (!is_string($date) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)) {
        apiError(422, 'payment_date invalide');
    }

    $methodName = trim((string) ($data['method'] ?? ''));
    if ($methodName === '') {
        apiError(422, 'method est requis');
    }

    $pdo->beginTransaction();

    $invoiceStmt = $pdo->prepare(
        'SELECT id, amount, status
         FROM invoices
         WHERE id = :id
         FOR UPDATE'
    );
    $invoiceStmt->execute([':id' => $invoiceId]);
    $invoice = $invoiceStmt->fetch();

    if (!$invoice || $invoice['status'] === 'CANCELLED') {
        $pdo->rollBack();
        apiError(404, 'Facture introuvable ou annulée');
    }

    $paidStmt = $pdo->prepare(
        'SELECT COALESCE(SUM(amount), 0) AS paid
         FROM payments
         WHERE invoice_id = :invoice_id'
    );
    $paidStmt->execute([':invoice_id' => $invoiceId]);
    $paid = (float) $paidStmt->fetch()['paid'];
    $balance = round((float) $invoice['amount'] - $paid, 2);

    if ($amount > $balance) {
        $pdo->rollBack();
        apiError(409, 'Le versement dépasse le solde disponible');
    }

    $paymentStmt = $pdo->prepare(
        'INSERT INTO payments (invoice_id, amount, payment_date, method, reference)
         VALUES (:invoice, :amount, :date, :method, :reference)
         RETURNING id, invoice_id, amount, payment_date, method, reference, created_at, updated_at'
    );
    $paymentStmt->execute([
        ':invoice' => $invoiceId,
        ':amount' => $amount,
        ':date' => $date,
        ':method' => $methodName,
        ':reference' => isset($data['reference']) ? (string) $data['reference'] : null,
    ]);
    $payment = $paymentStmt->fetch();

    $newPaid = round($paid + $amount, 2);
    $newStatus = $newPaid >= (float) $invoice['amount']
        ? 'PAID'
        : 'PARTIALLY_PAID';

    $pdo->prepare(
        'UPDATE invoices SET status = :status, updated_at = NOW() WHERE id = :id'
    )->execute([':status' => $newStatus, ':id' => $invoiceId]);

    $pdo->commit();

    http_response_code(201);
    echo json_encode([
        'success' => true,
        'payment' => $payment,
        'invoice_status' => $newStatus,
        'balance' => round((float) $invoice['amount'] - $newPaid, 2),
    ], JSON_UNESCAPED_UNICODE);
} catch (Throwable) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    apiError(500, 'Erreur interne du serveur');
}
