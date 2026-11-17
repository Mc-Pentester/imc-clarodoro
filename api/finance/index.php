<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

function financeUuid(string $value, string $name): string {
    if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value)) {
        apiError(400, "$name invalide");
    }
    return $value;
}

function financeScopeSql(array $user, string $studentColumn = 'i.student_id'): array {
    if (in_array($user['role_name'], ['PDG', 'Directeur', 'Secrétaire'], true)) {
        return ['', []];
    }
    return [
        " AND EXISTS (
            SELECT 1
            FROM enrollments se
            INNER JOIN teacher_class_subjects stcs
                ON stcs.class_id = se.class_id AND stcs.status = 'ACTIVE'
            INNER JOIN user_teachers sut
                ON sut.teacher_id = stcs.teacher_id
               AND sut.user_id = :scope_user_id
            WHERE se.student_id = $studentColumn
              AND se.status = 'ACTIVE'
        )",
        [':scope_user_id' => $user['id']]
    ];
}

function financeInvoice(PDO $pdo, string $invoiceId, array $user, bool $forUpdate = false): array {
    $scope = financeScopeSql($user, 'i.student_id');
    $lock = $forUpdate ? ' FOR UPDATE' : '';
    $stmt = $pdo->prepare(
        'SELECT i.*, s.matricule, s.last_name, s.first_name
         FROM invoices i
         INNER JOIN students s ON s.id = i.student_id
         WHERE i.id = :id' . $scope[0] . $lock
    );
    $stmt->execute([':id' => $invoiceId] + $scope[1]);
    $row = $stmt->fetch();
    if (!$row) apiError(404, 'Facture introuvable');
    $paidStmt = $pdo->prepare('SELECT COALESCE(SUM(amount), 0) FROM payments WHERE invoice_id = :invoice_id');
    $paidStmt->execute([':invoice_id' => $invoiceId]);
    $paid = (float)$paidStmt->fetchColumn();
    $row['paid_amount'] = $paid;
    $row['balance'] = max(0, (float)$row['amount'] - (float)$row['reduction'] - $paid);
    $installments = $pdo->prepare(
        'SELECT ii.id, ii.installment_number, ii.label, ii.due_amount, ii.reduction_amount,
                COALESCE(SUM(p.amount), 0) AS paid_amount,
                GREATEST(0, ii.due_amount - ii.reduction_amount - COALESCE(SUM(p.amount), 0)) AS balance
         FROM invoice_installments ii LEFT JOIN payments p ON p.installment_id = ii.id
         WHERE ii.invoice_id = :invoice_id GROUP BY ii.id ORDER BY ii.installment_number'
    );
    $installments->execute([':invoice_id' => $invoiceId]);
    $row['installments'] = $installments->fetchAll();
    foreach ($row['installments'] as &$part) {
        foreach (['due_amount','reduction_amount','paid_amount','balance'] as $field) $part[$field] = (float)$part[$field];
    }
    unset($part);
    return $row;
}

$method = $_SERVER['REQUEST_METHOD'];
$pdo = getDatabaseConnection();

if ($method === 'GET') {
    $user = requirePermission($pdo, 'finances.read');

    $studentId = isset($_GET['student_id']) && $_GET['student_id'] !== ''
        ? financeUuid($_GET['student_id'], 'student_id')
        : null;
    $schoolYearId = isset($_GET['school_year_id']) && $_GET['school_year_id'] !== ''
        ? financeUuid($_GET['school_year_id'], 'school_year_id')
        : null;

    $scope = financeScopeSql($user, 'i.student_id');
    $where = 'WHERE 1=1' . $scope[0];
    $params = $scope[1];

    if ($studentId !== null) {
        $where .= ' AND i.student_id = :student_id';
        $params[':student_id'] = $studentId;
    }
    if ($schoolYearId !== null) {
        $where .= ' AND i.school_year_id = :school_year_id';
        $params[':school_year_id'] = $schoolYearId;
    }

    $stmt = $pdo->prepare(
        'SELECT i.id, i.student_id, i.school_year_id, i.amount, i.reduction,
                i.reduction_type, i.reduction_percent, i.reduction_reason, i.status, i.invoice_date, i.description,
                i.created_at, i.updated_at,
                s.matricule, s.last_name, s.first_name,
                COALESCE(SUM(p.amount), 0) AS paid_amount,
                GREATEST(0, i.amount - i.reduction - COALESCE(SUM(p.amount), 0)) AS balance
         FROM invoices i
         INNER JOIN students s ON s.id = i.student_id
         LEFT JOIN payments p ON p.invoice_id = i.id
         ' . $where . '
         GROUP BY i.id, s.id
         ORDER BY i.invoice_date DESC, i.created_at DESC'
    );
    $stmt->execute($params);
    $invoices = $stmt->fetchAll();

    $tariffWhere = 'WHERE 1=1';
    $tariffParams = [];
    if ($schoolYearId !== null) {
        $tariffWhere .= ' AND ft.school_year_id = :school_year_id';
        $tariffParams[':school_year_id'] = $schoolYearId;
    }
    $tariffsStmt = $pdo->prepare(
        'SELECT ft.*, c.code AS class_code, c.name AS class_name
         FROM finance_tariffs ft
         INNER JOIN classes c ON c.id = ft.class_id
         ' . $tariffWhere . '
         ORDER BY c.name'
    );
    $tariffsStmt->execute($tariffParams);

    foreach ($invoices as &$invoice) {
        $invoice['paid_amount'] = (float)$invoice['paid_amount'];
        $invoice['balance'] = (float)$invoice['balance'];
        $paymentStmt = $pdo->prepare(
            'SELECT id, invoice_id, installment_id, amount, payment_date, method, reference
             FROM payments
             WHERE invoice_id = :invoice_id
             ORDER BY payment_date ASC, id ASC'
        );
        $paymentStmt->execute([':invoice_id' => $invoice['id']]);
        $invoice['payments'] = $paymentStmt->fetchAll();
        $installmentStmt = $pdo->prepare(
            'SELECT ii.id, ii.installment_number, ii.label, ii.due_amount, ii.reduction_amount,
                    COALESCE(SUM(p.amount), 0) AS paid_amount,
                    GREATEST(0, ii.due_amount - ii.reduction_amount - COALESCE(SUM(p.amount), 0)) AS balance
             FROM invoice_installments ii LEFT JOIN payments p ON p.installment_id = ii.id
             WHERE ii.invoice_id = :invoice_id GROUP BY ii.id ORDER BY ii.installment_number'
        );
        $installmentStmt->execute([':invoice_id' => $invoice['id']]);
        $invoice['installments'] = $installmentStmt->fetchAll();
        foreach ($invoice['installments'] as &$part) {
            foreach (['due_amount','reduction_amount','paid_amount','balance'] as $field) $part[$field] = (float)$part[$field];
        }
        unset($part);
        $reductionAuditStmt = $pdo->prepare(
            'SELECT a.id, a.old_reduction, a.new_reduction, a.old_reduction_type, a.new_reduction_type,
                    a.old_reduction_percent, a.new_reduction_percent, a.old_reason, a.new_reason,
                    a.created_at, u.username AS actor_username
             FROM invoice_reduction_audit a
             INNER JOIN users u ON u.id = a.actor_user_id
             WHERE a.invoice_id = :invoice_id
             ORDER BY a.created_at ASC, a.id ASC'
        );
        $reductionAuditStmt->execute([':invoice_id' => $invoice['id']]);
        $invoice['reduction_history'] = $reductionAuditStmt->fetchAll();
        foreach ($invoice['payments'] as &$payment) {
            $payment['amount'] = (float)$payment['amount'];
        }
        unset($payment);
    }
    unset($invoice);

    $studentWhere = '';
    $studentParams = [];
    if ($schoolYearId !== null) {
        $studentWhere = ' AND e.school_year_id = :students_school_year_id';
        $studentParams[':students_school_year_id'] = $schoolYearId;
    }

    $studentsScope = financeScopeSql($user, 's.id');
    $studentsStmt = $pdo->prepare(
        'SELECT DISTINCT
            s.id,
            s.matricule,
            s.last_name,
            s.first_name,
            e.class_id,
            c.code AS class_code,
            c.name AS class_name,
            e.school_year_id
         FROM students s
         INNER JOIN enrollments e
            ON e.student_id = s.id
           AND e.status = \'ACTIVE\'' . $studentWhere . '
         INNER JOIN classes c ON c.id = e.class_id
         WHERE 1=1' . $studentsScope[0] . '
         ORDER BY s.last_name, s.first_name, s.id'
    );
    $studentsStmt->execute($studentParams + $studentsScope[1]);
    $students = $studentsStmt->fetchAll();

    echo json_encode([
        'success' => true,
        'invoices' => $invoices,
        'tariffs' => $tariffsStmt->fetchAll(),
        'students' => $students,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($method === 'POST') {
    $data = readJsonBody();
    $resource = isset($data['resource']) && is_string($data['resource']) ? $data['resource'] : '';
    if ($resource === 'tariff') {
        $user = requirePermission($pdo, 'finances.update');
        requireCsrfToken();
        $schoolYearId = financeUuid((string)($data['school_year_id'] ?? ''), 'school_year_id');
        $classId = financeUuid((string)($data['class_id'] ?? ''), 'class_id');
        $amount = $data['amount'] ?? null;
        if (!is_numeric($amount) || (float)$amount < 0) apiError(422, 'amount invalide');
        foreach (['installment1_amount','installment2_amount','installment3_amount'] as $field) {
            if (isset($data[$field]) && (!is_numeric($data[$field]) || (float)$data[$field] < 0)) {
                apiError(422, "$field invalide");
            }
        }
        $installmentTotal = round((float)($data['installment1_amount'] ?? 0) + (float)($data['installment2_amount'] ?? 0) + (float)($data['installment3_amount'] ?? 0), 2);
        if ($installmentTotal > 0 && abs($installmentTotal - (float)$amount) > 0.01) {
            apiError(422, 'La somme des trois versements doit être égale au tarif total.');
        }
        $stmt = $pdo->prepare(
            'INSERT INTO finance_tariffs
                (school_year_id, class_id, amount,
                 installment1_amount, installment1_label,
                 installment2_amount, installment2_label,
                 installment3_amount, installment3_label)
             VALUES
                (:school_year_id, :class_id, :amount,
                 :i1, :l1, :i2, :l2, :i3, :l3)
             ON CONFLICT (school_year_id, class_id)
             DO UPDATE SET
                 amount = EXCLUDED.amount,
                 installment1_amount = EXCLUDED.installment1_amount,
                 installment1_label = EXCLUDED.installment1_label,
                 installment2_amount = EXCLUDED.installment2_amount,
                 installment2_label = EXCLUDED.installment2_label,
                 installment3_amount = EXCLUDED.installment3_amount,
                 installment3_label = EXCLUDED.installment3_label,
                 updated_at = NOW()
             RETURNING *'
        );
        $stmt->execute([
            ':school_year_id' => $schoolYearId,
            ':class_id' => $classId,
            ':amount' => number_format((float)$amount, 2, '.', ''),
            ':i1' => number_format((float)($data['installment1_amount'] ?? 0), 2, '.', ''),
            ':l1' => isset($data['installment1_label']) && is_string($data['installment1_label']) ? trim($data['installment1_label']) : null,
            ':i2' => number_format((float)($data['installment2_amount'] ?? 0), 2, '.', ''),
            ':l2' => isset($data['installment2_label']) && is_string($data['installment2_label']) ? trim($data['installment2_label']) : null,
            ':i3' => number_format((float)($data['installment3_amount'] ?? 0), 2, '.', ''),
            ':l3' => isset($data['installment3_label']) && is_string($data['installment3_label']) ? trim($data['installment3_label']) : null,
        ]);
        http_response_code(201);
        echo json_encode(['success' => true, 'tariff' => $stmt->fetch()], JSON_UNESCAPED_UNICODE);
        exit;
    }

    if ($resource === 'invoice') {
        $user = requirePermission($pdo, 'finances.create');
        requireCsrfToken();

        $studentId = financeUuid((string)($data['student_id'] ?? ''), 'student_id');
        $reduction = $data['reduction'] ?? 0;
        $reductionType = strtoupper((string)($data['reduction_type'] ?? 'FIXED'));
        $reductionPercent = $data['reduction_percent'] ?? 0;
        $schoolYearId = isset($data['school_year_id']) ? financeUuid((string)$data['school_year_id'], 'school_year_id') : null;

        if (!in_array($reductionType, ['FIXED', 'PERCENT'], true)) apiError(422, 'reduction_type invalide');
        if (!is_numeric($reductionPercent) || (float)$reductionPercent < 0 || (float)$reductionPercent > 100) apiError(422, 'reduction_percent invalide');
        if ($schoolYearId === null) apiError(422, 'Année scolaire requise');
        $scope = financeScopeSql($user, 's.id');
        $check = $pdo->prepare(
            "SELECT s.id, e.class_id FROM students s
             INNER JOIN enrollments e ON e.student_id=s.id AND e.status='ACTIVE'
             WHERE s.id=:student_id AND e.school_year_id=:school_year_id" . $scope[0] . " LIMIT 1"
        );
        $check->execute([':student_id'=>$studentId, ':school_year_id'=>$schoolYearId] + $scope[1]);
        $enrollment = $check->fetch();
        if (!$enrollment) apiError(404, 'Inscription active introuvable pour cet élève et cette année.');
        $tariffStmt = $pdo->prepare(
            'SELECT amount, installment1_amount, installment1_label, installment2_amount, installment2_label,
                    installment3_amount, installment3_label
             FROM finance_tariffs WHERE school_year_id=:year AND class_id=:class LIMIT 1'
        );
        $tariffStmt->execute([':year'=>$schoolYearId, ':class'=>$enrollment['class_id']]);
        $tariff = $tariffStmt->fetch();
        if (!$tariff || (float)$tariff['amount'] <= 0) apiError(422, 'Aucun tarif configuré pour la classe de cet élève.');
        $amount = round((float)$tariff['amount'], 2);
        $parts = [];
        foreach ([1,2,3] as $n) {
            $v = round((float)$tariff['installment'.$n.'_amount'], 2);
            if ($v > 0) $parts[] = ['number'=>$n, 'label'=>$tariff['installment'.$n.'_label'], 'amount'=>$v];
        }
        if (!$parts) $parts[] = ['number'=>1, 'label'=>'Versement unique', 'amount'=>$amount];
        if (abs(round(array_sum(array_column($parts,'amount')),2)-$amount)>0.01) {
            apiError(422, 'La somme des versements configurés doit être égale au tarif total de la classe.');
        }
        if ($reductionType === 'PERCENT') {
            $reduction = round($amount * (float)$reductionPercent / 100, 2);
        } else {
            $reductionPercent = 0;
        }
        if (!is_numeric($reduction) || (float)$reduction < 0 || (float)$reduction > $amount) {
            apiError(422, 'reduction invalide');
        }

        $stmt = $pdo->prepare(
            'INSERT INTO invoices
                (student_id, school_year_id, amount, reduction, reduction_type, reduction_percent, reduction_reason, status, invoice_date, description)
             VALUES
                (:student_id, :school_year_id, :amount, :reduction, :reduction_type, :reduction_percent, :reduction_reason, :status, :invoice_date, :description)
             RETURNING id'
        );
        $stmt->execute([
            ':student_id' => $studentId,
            ':school_year_id' => $schoolYearId,
            ':amount' => number_format((float)$amount, 2, '.', ''),
            ':reduction' => number_format((float)$reduction, 2, '.', ''),
            ':reduction_type' => $reductionType,
            ':reduction_percent' => number_format((float)$reductionPercent, 2, '.', ''),
            ':reduction_reason' => isset($data['reduction_reason']) && is_string($data['reduction_reason']) ? trim($data['reduction_reason']) : null,
            ':status' => 'OPEN',
            ':invoice_date' => isset($data['invoice_date']) && is_string($data['invoice_date']) ? $data['invoice_date'] : date('Y-m-d'),
            ':description' => isset($data['description']) && is_string($data['description']) ? trim($data['description']) : null,
        ]);
        $createdInvoiceId = (string)$stmt->fetchColumn();
        $allocatedReduction = 0.0;
        foreach ($parts as $index => $part) {
            $share = $index === count($parts)-1
                ? round((float)$reduction - $allocatedReduction, 2)
                : round((float)$reduction * $part['amount'] / $amount, 2);
            $allocatedReduction = round($allocatedReduction + $share, 2);
            $insertPart = $pdo->prepare(
                'INSERT INTO invoice_installments(invoice_id, installment_number, label, due_amount, reduction_amount)
                 VALUES(:invoice_id, :number, :label, :due, :reduction)'
            );
            $insertPart->execute([
                ':invoice_id'=>$createdInvoiceId, ':number'=>$part['number'], ':label'=>$part['label'],
                ':due'=>number_format($part['amount'],2,'.',''), ':reduction'=>number_format($share,2,'.','')
            ]);
        }
        if ((float)$reduction > 0) {
            $audit = $pdo->prepare(
                'INSERT INTO invoice_reduction_audit
                    (invoice_id, actor_user_id, old_reduction, new_reduction, old_reduction_type, new_reduction_type,
                     old_reduction_percent, new_reduction_percent, old_reason, new_reason)
                 VALUES (:invoice_id, :actor, 0, :new_reduction, \'FIXED\', :new_type, 0, :new_percent, NULL, :new_reason)'
            );
            $audit->execute([
                ':invoice_id' => $createdInvoiceId,
                ':actor' => $user['id'],
                ':new_reduction' => number_format((float)$reduction, 2, '.', ''),
                ':new_type' => $reductionType,
                ':new_percent' => number_format((float)$reductionPercent, 2, '.', ''),
                ':new_reason' => isset($data['reduction_reason']) && is_string($data['reduction_reason']) ? trim($data['reduction_reason']) : null,
            ]);
        }
        $invoice = financeInvoice($pdo, $createdInvoiceId, $user);
        http_response_code(201);
        echo json_encode(['success' => true, 'invoice' => $invoice], JSON_UNESCAPED_UNICODE);
        exit;
    }

    if ($resource === 'payment') {
        $user = requirePermission($pdo, 'finances.create');
        requireCsrfToken();

        $invoiceId = financeUuid((string)($data['invoice_id'] ?? ''), 'invoice_id');
        $installmentId = financeUuid((string)($data['installment_id'] ?? ''), 'installment_id');
        $amount = $data['amount'] ?? null;
        if (!is_numeric($amount) || (float)$amount <= 0) apiError(422, 'amount doit être supérieur à 0');

        $pdo->beginTransaction();
        try {
            $invoice = financeInvoice($pdo, $invoiceId, $user, true);
            $partStmt = $pdo->prepare(
                'SELECT ii.id, ii.due_amount, ii.reduction_amount, COALESCE(SUM(p.amount),0) AS paid_amount
                 FROM invoice_installments ii LEFT JOIN payments p ON p.installment_id=ii.id
                 WHERE ii.id=:part AND ii.invoice_id=:invoice GROUP BY ii.id'
            );
            $partStmt->execute([':part'=>$installmentId, ':invoice'=>$invoiceId]);
            $part = $partStmt->fetch();
            if (!$part) { $pdo->rollBack(); apiError(404, 'Versement scolaire introuvable.'); }
            $balance = max(0, (float)$part['due_amount']-(float)$part['reduction_amount']-(float)$part['paid_amount']);
            $paymentAmount = (float)$amount;
            if ($paymentAmount > $balance + 0.00001) {
                $pdo->rollBack();
                apiError(409, 'Le versement dépasse le solde restant');
            }

            $stmt = $pdo->prepare(
                'INSERT INTO payments
                    (invoice_id, installment_id, amount, payment_date, method, reference)
                 VALUES
                    (:invoice_id, :installment_id, :amount, :payment_date, :method, :reference)
                 RETURNING id'
            );
            $stmt->execute([
                ':invoice_id' => $invoiceId,
                ':installment_id' => $installmentId,
                ':amount' => number_format($paymentAmount, 2, '.', ''),
                ':payment_date' => isset($data['payment_date']) && is_string($data['payment_date']) ? $data['payment_date'] : date('Y-m-d'),
                ':method' => isset($data['method']) && is_string($data['method']) ? trim($data['method']) : '',
                ':reference' => isset($data['reference']) && is_string($data['reference']) ? trim($data['reference']) : null,
            ]);

            $newBalance = $balance - $paymentAmount;
            $newStatus = $newBalance <= 0.00001 ? 'PAID' : 'PARTIALLY_PAID';
            $update = $pdo->prepare('UPDATE invoices SET status = :status, updated_at = NOW() WHERE id = :id');
            $update->execute([':status' => $newStatus, ':id' => $invoiceId]);

            $pdo->commit();
            $fresh = financeInvoice($pdo, $invoiceId, $user);
            http_response_code(201);
            echo json_encode(['success' => true, 'payment_id' => $stmt->fetchColumn(), 'invoice' => $fresh], JSON_UNESCAPED_UNICODE);
            exit;
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            if ($e instanceof PDOException && str_contains($e->getMessage(), 'payments_method_check')) {
                apiError(422, 'method est requis');
            }
            apiError(500, 'Erreur interne du serveur');
        }
    }

    apiError(422, 'resource invalide');
}

if ($method === 'PUT' || $method === 'PATCH') {
    $user = requirePermission($pdo, 'finances.update');
    requireCsrfToken();
    $invoiceId = financeUuid((string)($_GET['invoice_id'] ?? ''), 'invoice_id');
    $data = readJsonBody();

    $allowed = ['reduction', 'reduction_type', 'reduction_percent', 'reduction_reason', 'description', 'status'];
    foreach (array_keys($data) as $key) {
        if (!in_array($key, $allowed, true)) apiError(422, "Champ inconnu: $key");
    }
    if (!$data) apiError(422, 'Aucun champ à modifier');

    $pdo->beginTransaction();
    try {
        $current = financeInvoice($pdo, $invoiceId, $user, true);
        $discountFields = ['reduction', 'reduction_type', 'reduction_percent', 'reduction_reason'];
        $discountChanged = count(array_intersect(array_keys($data), $discountFields)) > 0;
        $fields = [];
        $params = [':id' => $invoiceId];

        if ($discountChanged) {
            $oldReduction = (float)$current['reduction'];
            $oldType = (string)($current['reduction_type'] ?? 'FIXED');
            $oldPercent = (float)($current['reduction_percent'] ?? 0);
            $oldReason = $current['reduction_reason'] ?? null;
            $newType = strtoupper((string)($data['reduction_type'] ?? (
                array_key_exists('reduction', $data) && !array_key_exists('reduction_percent', $data)
                    ? 'FIXED'
                    : $oldType
            )));
            if (!in_array($newType, ['FIXED', 'PERCENT'], true)) {
                $pdo->rollBack();
                apiError(422, 'reduction_type invalide');
            }
            $newPercent = $newType === 'PERCENT'
                ? ($data['reduction_percent'] ?? ($oldType === 'PERCENT' ? $oldPercent : 0))
                : 0;
            if (!is_numeric($newPercent) || (float)$newPercent < 0 || (float)$newPercent > 100) {
                $pdo->rollBack();
                apiError(422, 'reduction_percent invalide');
            }
            $newReduction = $newType === 'PERCENT'
                ? round((float)$current['amount'] * (float)$newPercent / 100, 2)
                : ($data['reduction'] ?? ($oldType === 'FIXED' ? $oldReduction : 0));
            if (!is_numeric($newReduction) || (float)$newReduction < 0) {
                $pdo->rollBack();
                apiError(422, 'reduction invalide');
            }
            $newReduction = round((float)$newReduction, 2);
            if ($newReduction + (float)$current['paid_amount'] > (float)$current['amount'] + 0.00001) {
                $pdo->rollBack();
                apiError(422, 'La réduction ne peut pas annuler un montant déjà encaissé');
            }
            $partsStmt = $pdo->prepare(
                'SELECT ii.id, ii.due_amount, COALESCE(SUM(p.amount),0) AS paid_amount
                 FROM invoice_installments ii LEFT JOIN payments p ON p.installment_id=ii.id
                 WHERE ii.invoice_id=:invoice_id GROUP BY ii.id ORDER BY ii.installment_number'
            );
            $partsStmt->execute([':invoice_id'=>$invoiceId]);
            $partsToUpdate = $partsStmt->fetchAll();
            $allocated = 0.0;
            foreach ($partsToUpdate as $index=>$part) {
                $share = $index===count($partsToUpdate)-1
                    ? round($newReduction-$allocated,2)
                    : round($newReduction*(float)$part['due_amount']/(float)$current['amount'],2);
                $allocated = round($allocated+$share,2);
                if ((float)$part['paid_amount'] > (float)$part['due_amount']-$share+0.00001) {
                    $pdo->rollBack();
                    apiError(422, 'La réduction ne peut pas diminuer un versement sous les sommes déjà encaissées.');
                }
                $updPart=$pdo->prepare('UPDATE invoice_installments SET reduction_amount=:reduction WHERE id=:id');
                $updPart->execute([':reduction'=>number_format($share,2,'.',''), ':id'=>$part['id']]);
            }
            $newReason = array_key_exists('reduction_reason', $data)
                ? (is_string($data['reduction_reason']) ? trim($data['reduction_reason']) : null)
                : $oldReason;

            $fields[] = 'reduction = :reduction';
            $fields[] = 'reduction_type = :reduction_type';
            $fields[] = 'reduction_percent = :reduction_percent';
            $fields[] = 'reduction_reason = :reduction_reason';
            if (!in_array((string)$current['status'], ['CANCELLED', 'ARCHIVED'], true)) {
                $newBalance = max(0, (float)$current['amount'] - $newReduction - (float)$current['paid_amount']);
                $fields[] = 'status = :discount_status';
                $params[':discount_status'] = $newBalance <= 0.00001
                    ? 'PAID'
                    : ((float)$current['paid_amount'] > 0.00001 ? 'PARTIALLY_PAID' : 'OPEN');
            }
            $params[':reduction'] = number_format($newReduction, 2, '.', '');
            $params[':reduction_type'] = $newType;
            $params[':reduction_percent'] = number_format((float)$newPercent, 2, '.', '');
            $params[':reduction_reason'] = $newReason;

            if (
                abs($newReduction - $oldReduction) > 0.00001 ||
                $newType !== $oldType ||
                abs((float)$newPercent - $oldPercent) > 0.00001 ||
                $newReason !== $oldReason
            ) {
                $audit = $pdo->prepare(
                    'INSERT INTO invoice_reduction_audit
                        (invoice_id, actor_user_id, old_reduction, new_reduction, old_reduction_type, new_reduction_type,
                         old_reduction_percent, new_reduction_percent, old_reason, new_reason)
                     VALUES (:invoice_id, :actor, :old_reduction, :new_reduction, :old_type, :new_type,
                             :old_percent, :new_percent, :old_reason, :new_reason)'
                );
                $audit->execute([
                    ':invoice_id' => $invoiceId,
                    ':actor' => $user['id'],
                    ':old_reduction' => number_format($oldReduction, 2, '.', ''),
                    ':new_reduction' => number_format($newReduction, 2, '.', ''),
                    ':old_type' => $oldType,
                    ':new_type' => $newType,
                    ':old_percent' => number_format($oldPercent, 2, '.', ''),
                    ':new_percent' => number_format((float)$newPercent, 2, '.', ''),
                    ':old_reason' => $oldReason,
                    ':new_reason' => $newReason,
                ]);
            }
        }

        if (array_key_exists('description', $data)) {
            $fields[] = 'description = :description';
            $params[':description'] = is_string($data['description']) ? trim($data['description']) : null;
        }
        if (array_key_exists('status', $data)) {
            if (!in_array($data['status'], ['OPEN','PARTIALLY_PAID','PAID','CANCELLED','ARCHIVED'], true)) {
                $pdo->rollBack();
                apiError(422, 'status invalide');
            }
            $fields[] = 'status = :status';
            $params[':status'] = $data['status'];
        }
        if (!$fields) {
            $pdo->rollBack();
            apiError(422, 'Aucun champ à modifier');
        }

        $stmt = $pdo->prepare('UPDATE invoices SET ' . implode(', ', $fields) . ', updated_at = NOW() WHERE id = :id');
        $stmt->execute($params);
        $pdo->commit();
        echo json_encode(['success' => true, 'invoice' => financeInvoice($pdo, $invoiceId, $user)], JSON_UNESCAPED_UNICODE);
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        apiError(500, 'Erreur interne du serveur');
    }
    exit;
}

if ($method === 'DELETE') {
    $user = requirePermission($pdo, 'finances.delete');
    requireCsrfToken();
    $paymentId = financeUuid((string)($_GET['payment_id'] ?? ''), 'payment_id');

    $pdo->beginTransaction();
    try {
        $stmt = $pdo->prepare(
            'SELECT p.id, p.invoice_id
             FROM payments p
             INNER JOIN invoices i ON i.id = p.invoice_id
             WHERE p.id = :id
             LIMIT 1
             FOR UPDATE'
        );
        $stmt->execute([':id' => $paymentId]);
        $payment = $stmt->fetch();
        if (!$payment) {
            $pdo->rollBack();
            apiError(404, 'Versement introuvable');
        }
        financeInvoice($pdo, (string)$payment['invoice_id'], $user, true);
        $delete = $pdo->prepare('DELETE FROM payments WHERE id = :id RETURNING id');
        $delete->execute([':id' => $paymentId]);
        $deletedId = $delete->fetchColumn();
        $remaining = financeInvoice($pdo, (string)$payment['invoice_id'], $user, true);
        $newStatus = (float)$remaining['paid_amount'] <= 0.00001 ? 'OPEN' :
            ((float)$remaining['balance'] <= 0.00001 ? 'PAID' : 'PARTIALLY_PAID');
        $update = $pdo->prepare('UPDATE invoices SET status = :status, updated_at = NOW() WHERE id = :id');
        $update->execute([':status' => $newStatus, ':id' => $payment['invoice_id']]);
        $pdo->commit();
        echo json_encode(['success' => true, 'deleted' => true, 'id' => $deletedId], JSON_UNESCAPED_UNICODE);
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        apiError(500, 'Erreur interne du serveur');
    }
    exit;
}

header('Allow: GET, POST, PUT, PATCH, DELETE');
apiError(405, 'Méthode HTTP non autorisée');
