<?php
declare(strict_types=1);
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private');
$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    requirePermission($pdo, 'whatsapp.consent.read');
    $parentId = $_GET['parent_id'] ?? '';
    if (!is_string($parentId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $parentId)) {
        apiError(400, 'parent_id UUID invalide');
    }
    $stmt = $pdo->prepare(
        'SELECT id, parent_id, purpose, phone_e164, status, consent_source, consent_method,
                consent_email, email_verified_at, consent_text_version, evidence_reference,
                consented_at, revoked_at, created_at, updated_at
         FROM whatsapp_consents WHERE parent_id = :parent_id ORDER BY purpose'
    );
    $stmt->execute([':parent_id' => $parentId]);
    echo json_encode(['success' => true, 'consents' => $stmt->fetchAll()], JSON_UNESCAPED_UNICODE);
    exit;
}
if ($method !== 'POST') {
    header('Allow: GET, POST');
    apiError(405, 'Méthode HTTP non autorisée');
}
$user = requirePermission($pdo, 'whatsapp.consent.manage');
requireCsrfToken();
$data = readJsonBody();
$parentId = $data['parent_id'] ?? '';
$purposes = $data['purposes'] ?? (isset($data['purpose']) ? [$data['purpose']] : []);
$phone = $data['phone_e164'] ?? '';
$status = $data['status'] ?? '';
$source = $data['consent_source'] ?? null;
$evidence = $data['evidence_reference'] ?? null;
$consentMethod = $data['consent_method'] ?? null;
$allowedPurposes = ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'];

if (!is_string($parentId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $parentId)) apiError(422, 'parent_id UUID invalide');
if (!is_array($purposes) || $purposes === [] || count($purposes) > 4 || array_diff($purposes, $allowedPurposes) || count(array_unique($purposes)) !== count($purposes)) apiError(422, 'Choisissez une ou plusieurs finalités WhatsApp valides.');
if (!is_string($phone) || !preg_match('/^\\+[1-9][0-9]{7,14}$/', $phone)) apiError(422, 'Le téléphone doit être au format international E.164');
if (!in_array($status, ['PENDING', 'OPTED_IN', 'OPTED_OUT'], true)) apiError(422, 'Statut de consentement invalide');
foreach (['consent_source' => $source, 'evidence_reference' => $evidence] as $field => $value) {
    if ($value !== null && (!is_string($value) || strlen($value) > 255)) apiError(422, $field . ' invalide');
}
if ($status === 'OPTED_IN' && ($consentMethod !== 'PAPER' || !is_string($evidence) || trim($evidence) === '' || !is_string($source) || trim($source) !== 'PAPER')) {
    apiError(422, 'Un accord saisi par le personnel doit être de type PAPER et comporter une référence de preuve. Le parcours numérique est réservé à la confirmation e-mail du parent.');
}
if ($consentMethod !== null && !in_array($consentMethod, ['PAPER', 'DIGITAL_EMAIL'], true)) apiError(422, 'Méthode de consentement invalide');
if ($status === 'OPTED_OUT' && count($purposes) !== 1) apiError(422, 'Retirez une finalité à la fois.');

$parent = $pdo->prepare('SELECT id FROM parents WHERE id = :id LIMIT 1');
$parent->execute([':id' => $parentId]);
if (!$parent->fetchColumn()) apiError(404, 'Parent introuvable');

sort($purposes);
$consentedAt = $status === 'OPTED_IN' ? (new DateTimeImmutable())->format(DateTimeInterface::ATOM) : null;
$revokedAt = $status === 'OPTED_OUT' ? (new DateTimeImmutable())->format(DateTimeInterface::ATOM) : null;
$pdo->beginTransaction();
try {
    foreach ($purposes as $purpose) {
        $lock = $pdo->prepare('SELECT pg_advisory_xact_lock(hashtextextended(:lock_key, 0))');
        $lock->execute([':lock_key' => $parentId . ':' . $purpose]);
    }

    $upsert = $pdo->prepare(
        'INSERT INTO whatsapp_consents
          (parent_id, purpose, phone_e164, status, consent_source, evidence_reference,
           consented_at, revoked_at, consent_method, created_by, updated_by)
         VALUES (:parent_id, :purpose, :phone, :status, :source, :evidence,
           :consented_at, :revoked_at, :consent_method, :actor, :actor)
         ON CONFLICT (parent_id, purpose) DO UPDATE SET
           phone_e164 = EXCLUDED.phone_e164,
           status = EXCLUDED.status,
           consent_source = CASE WHEN EXCLUDED.status = \'OPTED_OUT\' THEN whatsapp_consents.consent_source ELSE EXCLUDED.consent_source END,
           evidence_reference = CASE WHEN EXCLUDED.status = \'OPTED_OUT\' THEN whatsapp_consents.evidence_reference ELSE EXCLUDED.evidence_reference END,
           consent_method = CASE WHEN EXCLUDED.status = \'OPTED_IN\' THEN EXCLUDED.consent_method ELSE whatsapp_consents.consent_method END,
           consented_at = CASE WHEN EXCLUDED.status = \'OPTED_IN\' THEN NOW() ELSE whatsapp_consents.consented_at END,
           revoked_at = CASE WHEN EXCLUDED.status = \'OPTED_OUT\' THEN NOW() ELSE NULL END,
           updated_by = EXCLUDED.updated_by, updated_at = NOW()
         RETURNING id, parent_id, purpose, phone_e164, status, consent_source, consent_method,
                   evidence_reference, consented_at, revoked_at, updated_at'
    );
    $previousStmt = $pdo->prepare('SELECT status FROM whatsapp_consents WHERE parent_id = :parent_id AND purpose = :purpose FOR UPDATE');
    $audit = $pdo->prepare(
        'INSERT INTO whatsapp_consent_audit
          (consent_id, parent_id, purpose, previous_status, new_status, actor_user_id,
           consent_method, evidence_reference, consent_email, consent_text_version, actor_type)
         VALUES (:consent_id, :parent_id, :purpose, :previous_status, :new_status, :actor,
           :consent_method, :evidence, NULL, NULL, \'SCHOOL_USER\')'
    );
    $saved = [];
    foreach ($purposes as $purpose) {
        $previousStmt->execute([':parent_id' => $parentId, ':purpose' => $purpose]);
        $previous = $previousStmt->fetchColumn();
        $upsert->execute([
            ':parent_id' => $parentId, ':purpose' => $purpose, ':phone' => $phone,
            ':status' => $status, ':source' => $source, ':evidence' => $evidence,
            ':consented_at' => $consentedAt, ':revoked_at' => $revokedAt,
            ':consent_method' => $consentMethod, ':actor' => $user['id'],
        ]);
        $consent = $upsert->fetch();
        $audit->execute([
            ':consent_id' => $consent['id'], ':parent_id' => $parentId, ':purpose' => $purpose,
            ':previous_status' => $previous ?: null, ':new_status' => $status,
            ':actor' => $user['id'], ':consent_method' => $consent['consent_method'],
            ':evidence' => $consent['evidence_reference'],
        ]);
        $saved[] = $consent;
    }
    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    throw $e;
}
echo json_encode(['success' => true, 'consents' => $saved], JSON_UNESCAPED_UNICODE);
