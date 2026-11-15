<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private');

$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$types = ['PARENT' => 'parent_id', 'STUDENT' => 'student_id', 'STAFF' => 'staff_id', 'TEACHER' => 'teacher_id'];
$purposes = ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'];
$uuid = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i';

if ($method === 'GET') {
    requirePermission($pdo, 'whatsapp.recipient.read');
    $type = strtoupper((string) ($_GET['recipient_type'] ?? ''));
    $id = $_GET['recipient_id'] ?? '';
    if (!isset($types[$type]) || !is_string($id) || !preg_match($uuid, $id)) {
        apiError(422, 'Type ou identifiant du destinataire invalide');
    }
    $column = $types[$type];
    $stmt = $pdo->prepare(
        "SELECT id, recipient_type, purpose, phone_e164, status, consent_source,
                evidence_reference, consented_at, revoked_at, created_at, updated_at
         FROM whatsapp_recipient_consents
         WHERE recipient_type = :type AND {$column} = :recipient_id
         ORDER BY purpose"
    );
    $stmt->execute([':type' => $type, ':recipient_id' => $id]);
    echo json_encode(['success' => true, 'consents' => $stmt->fetchAll()], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($method !== 'POST') {
    header('Allow: GET, POST');
    apiError(405, 'Méthode HTTP non autorisée');
}

$user = requirePermission($pdo, 'whatsapp.recipient.manage');
requireCsrfToken();
$data = readJsonBody();
$type = strtoupper((string) ($data['recipient_type'] ?? ''));
$id = $data['recipient_id'] ?? '';
$purpose = $data['purpose'] ?? '';
$phone = $data['phone_e164'] ?? '';
$status = $data['status'] ?? '';
$source = $data['consent_source'] ?? null;
$evidence = $data['evidence_reference'] ?? null;

if (!isset($types[$type]) || !is_string($id) || !preg_match($uuid, $id)) {
    apiError(422, 'Type ou identifiant du destinataire invalide');
}
if (!is_string($purpose) || !in_array($purpose, $purposes, true)) {
    apiError(422, 'Finalité WhatsApp invalide');
}
if (!is_string($phone) || !preg_match('/^\+[1-9][0-9]{7,14}$/', $phone)) {
    apiError(422, 'Le téléphone doit être au format international E.164');
}
if (!is_string($status) || !in_array($status, ['PENDING', 'OPTED_IN', 'OPTED_OUT'], true)) {
    apiError(422, 'Statut de consentement invalide');
}
foreach (['consent_source' => $source, 'evidence_reference' => $evidence] as $field => $value) {
    if ($value !== null && (!is_string($value) || strlen($value) > 255)) {
        apiError(422, $field . ' invalide');
    }
}
if ($status === 'OPTED_IN' && (!is_string($source) || trim($source) === '')) {
    apiError(422, 'La preuve/source du consentement est obligatoire pour OPTED_IN');
}

$column = $types[$type];
$exists = $pdo->prepare("SELECT 1 FROM " . strtolower($type === 'PARENT' ? 'parents' : ($type === 'STUDENT' ? 'students' : ($type === 'STAFF' ? 'staff' : 'teachers'))) . " WHERE id = :id LIMIT 1");
$exists->execute([':id' => $id]);
if (!$exists->fetchColumn()) {
    apiError(404, 'Destinataire introuvable');
}

$pdo->beginTransaction();
try {
    $lock = $pdo->prepare('SELECT pg_advisory_xact_lock(hashtextextended(:lock_key, 0))');
    $lock->execute([':lock_key' => ($type === 'PARENT' ? $id : $type . ':' . $id) . ':' . $purpose]);
    $previousStmt = $pdo->prepare(
        "SELECT id, status FROM whatsapp_recipient_consents
         WHERE recipient_type = :type AND {$column} = :recipient_id AND purpose = :purpose
         FOR UPDATE"
    );
    $previousStmt->execute([':type' => $type, ':recipient_id' => $id, ':purpose' => $purpose]);
    $previous = $previousStmt->fetch();

    $upsert = $pdo->prepare(
        "INSERT INTO whatsapp_recipient_consents
            (recipient_type, {$column}, purpose, phone_e164, status, consent_source,
             evidence_reference, consented_at, revoked_at, created_by, updated_by)
         VALUES
            (:type, :recipient_id, :purpose, :phone, :status, :source,
             :evidence, CASE WHEN :status_in = 'OPTED_IN' THEN NOW() ELSE NULL END,
             CASE WHEN :status_out = 'OPTED_OUT' THEN NOW() ELSE NULL END, :actor_created, :actor_updated)
         ON CONFLICT ({$column}, purpose) WHERE recipient_type = '{$type}'
         DO UPDATE SET phone_e164 = EXCLUDED.phone_e164,
             status = EXCLUDED.status, consent_source = EXCLUDED.consent_source,
             evidence_reference = EXCLUDED.evidence_reference,
             consented_at = CASE WHEN EXCLUDED.status = 'OPTED_IN' THEN NOW() ELSE NULL END,
             revoked_at = CASE WHEN EXCLUDED.status = 'OPTED_OUT' THEN NOW() ELSE NULL END,
             updated_by = EXCLUDED.updated_by, updated_at = NOW()
         RETURNING id, recipient_type, purpose, phone_e164, status, consented_at, revoked_at, updated_at"
    );
    $upsert->execute([
        ':type' => $type, ':recipient_id' => $id, ':purpose' => $purpose,
        ':phone' => $phone, ':status' => $status, ':status_in' => $status, ':status_out' => $status, ':source' => $source,
        ':evidence' => $evidence, ':actor_created' => $user['id'], ':actor_updated' => $user['id'],
    ]);
    $consent = $upsert->fetch();

    // Keep the legacy parent-consent table synchronized so the existing
    // manual WhatsApp preparation and older integrations remain compatible.
    if ($type === 'PARENT') {
        $legacy = $pdo->prepare(
            "INSERT INTO whatsapp_consents
                (parent_id, purpose, phone_e164, status, consent_source, evidence_reference,
                 consented_at, revoked_at, created_by, updated_by)
             VALUES (:parent_id, :purpose, :phone, :status, :source, :evidence,
                 CASE WHEN :legacy_status_in = 'OPTED_IN' THEN NOW() ELSE NULL END,
                 CASE WHEN :legacy_status_out = 'OPTED_OUT' THEN NOW() ELSE NULL END, :legacy_actor_created, :legacy_actor_updated)
             ON CONFLICT (parent_id, purpose) DO UPDATE SET
                 phone_e164 = EXCLUDED.phone_e164, status = EXCLUDED.status,
                 consent_source = EXCLUDED.consent_source, evidence_reference = EXCLUDED.evidence_reference,
                 consented_at = CASE WHEN EXCLUDED.status = 'OPTED_IN' THEN NOW() ELSE NULL END,
                 revoked_at = CASE WHEN EXCLUDED.status = 'OPTED_OUT' THEN NOW() ELSE NULL END,
                 updated_by = EXCLUDED.updated_by, updated_at = NOW()
             RETURNING id"
        );
        $legacy->execute([
            ':parent_id' => $id, ':purpose' => $purpose, ':phone' => $phone,
            ':status' => $status, ':legacy_status_in' => $status, ':legacy_status_out' => $status,
            ':source' => $source, ':evidence' => $evidence,
            ':legacy_actor_created' => $user['id'], ':legacy_actor_updated' => $user['id'],
        ]);
        $legacyConsentId = $legacy->fetchColumn();
        $legacyAudit = $pdo->prepare(
            'INSERT INTO whatsapp_consent_audit
                (consent_id, parent_id, purpose, previous_status, new_status, actor_user_id)
             VALUES (:consent, :parent, :purpose, :previous, :new, :actor)'
        );
        $legacyAudit->execute([
            ':consent' => $legacyConsentId, ':parent' => $id, ':purpose' => $purpose,
            ':previous' => $previous['status'] ?? null, ':new' => $status, ':actor' => $user['id'],
        ]);
    }

    $audit = $pdo->prepare(
        'INSERT INTO whatsapp_recipient_consent_audit
            (consent_id, recipient_type, previous_status, new_status, actor_user_id)
         VALUES (:consent_id, :type, :previous, :new, :actor)'
    );
    $audit->execute([
        ':consent_id' => $consent['id'], ':type' => $type,
        ':previous' => $previous['status'] ?? null, ':new' => $status, ':actor' => $user['id'],
    ]);
    $pdo->commit();
    echo json_encode(['success' => true, 'consent' => $consent], JSON_UNESCAPED_UNICODE);
} catch (Throwable $error) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    error_log('WhatsApp recipient consent update failed: ' . $error->getMessage());
    apiError(503, 'Impossible de mettre à jour le consentement WhatsApp');
}
