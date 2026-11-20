<?php
declare(strict_types=1);
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private');
$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$token = $_GET['token'] ?? '';
$data = [];
if ($method === 'POST') { $data = readJsonBody(); $token = $data['token'] ?? ''; }
if (!is_string($token) || !preg_match('/^[a-f0-9]{64}$/', $token)) apiError(400, 'Lien de confirmation invalide.');

if ($method === 'GET') {
    $stmt = $pdo->prepare(
        'SELECT c.id, c.email, c.expires_at, c.attempts, p.first_name
         FROM whatsapp_consent_email_challenges c JOIN parents p ON p.id = c.parent_id
         WHERE c.invitation_token_hash = :token_hash AND c.used_at IS NULL
           AND c.expires_at > NOW() AND c.attempts < 5'
    );
    $stmt->execute([':token_hash' => hash('sha256', $token)]);
    $challenge = $stmt->fetch();
    if (!$challenge) apiError(410, 'Ce lien a expiré ou a déjà été utilisé.');
    $email = (string) $challenge['email'];
    $at = strpos($email, '@');
    $masked = $at === false ? 'adresse masquée' : substr($email, 0, 1) . '•••' . substr($email, $at);
    echo json_encode(['success'=>true, 'first_name'=>$challenge['first_name'], 'email_masked'=>$masked], JSON_UNESCAPED_UNICODE);
    exit;
}
if ($method !== 'POST') { header('Allow: GET, POST'); apiError(405, 'Méthode HTTP non autorisée'); }
$code = $data['code'] ?? '';
$phone = $data['phone_e164'] ?? '';
$purposes = $data['purposes'] ?? [];
$allowed = ['ATTENDANCE','RESULTS_AVAILABLE','PAYMENT_REMINDER','GENERAL'];
if (!is_string($code) || !preg_match('/^[0-9]{6}$/', $code)) apiError(422, 'Saisissez le code à 6 chiffres reçu par e-mail.');
if (!is_string($phone) || !preg_match('/^\+[1-9][0-9]{7,14}$/', $phone)) apiError(422, 'Le téléphone doit être au format international E.164.');
if (!is_array($purposes) || $purposes === [] || count($purposes) > 4 || array_diff($purposes, $allowed) || count(array_unique($purposes)) !== count($purposes)) apiError(422, 'Choisissez au moins une catégorie de communication.');

$pdo->beginTransaction();
try {
    $stmt = $pdo->prepare(
        'SELECT c.*, p.first_name FROM whatsapp_consent_email_challenges c
         JOIN parents p ON p.id = c.parent_id WHERE c.invitation_token_hash = :token_hash FOR UPDATE'
    );
    $stmt->execute([':token_hash'=>hash('sha256',$token)]);
    $challenge = $stmt->fetch();
    if (!$challenge || $challenge['used_at'] !== null || strtotime((string)$challenge['expires_at']) <= time() || (int)$challenge['attempts'] >= 5) {
        $pdo->rollBack(); apiError(410, 'Ce lien a expiré ou a déjà été utilisé.');
    }
    if (!hash_equals((string)$challenge['verification_code_hash'], hash('sha256',$code))) {
        $bad = $pdo->prepare('UPDATE whatsapp_consent_email_challenges SET attempts = attempts + 1 WHERE id = :id');
        $bad->execute([':id'=>$challenge['id']]);
        $pdo->commit(); apiError(403, 'Code incorrect. Vérifiez le courriel reçu.');
    }
    $version = '2026-11-v1';
    foreach ($purposes as $purpose) {
        $advisory = $pdo->prepare('SELECT pg_advisory_xact_lock(hashtextextended(:lock_key, 0))');
        $advisory->execute([':lock_key' => $challenge['parent_id'] . ':' . $purpose]);
        $previousStmt = $pdo->prepare('SELECT status FROM whatsapp_consents WHERE parent_id = :parent AND purpose = :purpose FOR UPDATE');
        $previousStmt->execute([':parent'=>$challenge['parent_id'], ':purpose'=>$purpose]);
        $previous = $previousStmt->fetchColumn();
        $upsert = $pdo->prepare(
            "INSERT INTO whatsapp_consents
              (parent_id, purpose, phone_e164, status, consent_source, evidence_reference,
               consented_at, revoked_at, consent_method, consent_email, email_verified_at,
               consent_text_version, created_by, updated_by)
             VALUES (:parent, :purpose, :phone, 'OPTED_IN', 'DIGITAL_EMAIL',
               :evidence, NOW(), NULL, 'DIGITAL_EMAIL', :email, NOW(), :version, NULL, NULL)
             ON CONFLICT (parent_id, purpose) DO UPDATE SET
               phone_e164=EXCLUDED.phone_e164, status='OPTED_IN', consent_source='DIGITAL_EMAIL',
               evidence_reference=EXCLUDED.evidence_reference, consented_at=NOW(), revoked_at=NULL,
               consent_method='DIGITAL_EMAIL', consent_email=EXCLUDED.consent_email,
               email_verified_at=NOW(), consent_text_version=EXCLUDED.consent_text_version,
               created_by=NULL, updated_by=NULL, updated_at=NOW()
             RETURNING id, consent_method, consent_email, email_verified_at,
                       consent_text_version, evidence_reference, consent_source, phone_e164"
        );
        $upsert->execute([':parent'=>$challenge['parent_id'], ':purpose'=>$purpose, ':phone'=>$phone,
            ':evidence'=>'email_challenge:'.$challenge['id'], ':email'=>$challenge['email'], ':version'=>$version]);
        $savedConsent = $upsert->fetch(PDO::FETCH_ASSOC);
        $consentId = $savedConsent['id'];
        $audit = $pdo->prepare(
            "INSERT INTO whatsapp_consent_audit
             (consent_id,parent_id,purpose,previous_status,new_status,actor_user_id,
              consent_method,evidence_reference,consent_email,consent_text_version,actor_type)
             VALUES (:consent,:parent,:purpose,:previous,'OPTED_IN',NULL,
              'DIGITAL_EMAIL',:evidence,:email,:version,'PARENT_EMAIL')"
        );
        $audit->execute([':consent'=>$consentId, ':parent'=>$challenge['parent_id'], ':purpose'=>$purpose,
            ':previous'=>$previous ?: null, ':evidence'=>'email_challenge:'.$challenge['id'],
            ':email'=>$challenge['email'], ':version'=>$version]);

        $genericPreviousStmt = $pdo->prepare(
            "SELECT status FROM whatsapp_recipient_consents
             WHERE recipient_type = 'PARENT' AND parent_id = :parent_id AND purpose = :purpose
             FOR UPDATE"
        );
        $genericPreviousStmt->execute([':parent_id' => $challenge['parent_id'], ':purpose' => $purpose]);
        $genericPrevious = $genericPreviousStmt->fetchColumn();

        $genericUpsert = $pdo->prepare(
            "INSERT INTO whatsapp_recipient_consents
                (recipient_type, parent_id, purpose, phone_e164, status, consent_source,
                 consent_method, consent_email, email_verified_at, consent_text_version,
                 evidence_reference, consented_at, revoked_at, created_by, updated_by)
             VALUES ('PARENT', :parent_id, :purpose, :phone, 'OPTED_IN', 'DIGITAL_EMAIL',
                 'DIGITAL_EMAIL', :email, NOW(), :text_version, :evidence,
                 NOW(), NULL, NULL, NULL)
             ON CONFLICT (parent_id, purpose) WHERE recipient_type = 'PARENT'
             DO UPDATE SET phone_e164 = EXCLUDED.phone_e164, status = 'OPTED_IN',
                 consent_source = 'DIGITAL_EMAIL', consent_method = 'DIGITAL_EMAIL',
                 consent_email = EXCLUDED.consent_email, email_verified_at = NOW(),
                 consent_text_version = EXCLUDED.consent_text_version,
                 evidence_reference = EXCLUDED.evidence_reference,
                 consented_at = NOW(), revoked_at = NULL, updated_by = NULL, updated_at = NOW()
             RETURNING id, consent_method, consent_email, consent_text_version, evidence_reference"
        );
        $genericUpsert->execute([
            ':parent_id' => $challenge['parent_id'], ':purpose' => $purpose, ':phone' => $phone,
            ':email' => $challenge['email'], ':text_version' => $version,
            ':evidence' => 'email_challenge:' . $challenge['id'],
        ]);
        $genericConsent = $genericUpsert->fetch(PDO::FETCH_ASSOC);

        $genericAudit = $pdo->prepare(
            "INSERT INTO whatsapp_recipient_consent_audit
                (consent_id, recipient_type, previous_status, new_status, actor_user_id,
                 consent_method, evidence_reference, consent_email, consent_text_version, actor_type)
             VALUES (:consent_id, 'PARENT', :previous, 'OPTED_IN', NULL,
                 'DIGITAL_EMAIL', :evidence, :email, :text_version, 'PARENT_EMAIL')"
        );
        $genericAudit->execute([
            ':consent_id' => $genericConsent['id'], ':previous' => $genericPrevious ?: null,
            ':evidence' => $genericConsent['evidence_reference'], ':email' => $genericConsent['consent_email'],
            ':text_version' => $genericConsent['consent_text_version'],
        ]);
    }
    $used=$pdo->prepare('UPDATE whatsapp_consent_email_challenges SET used_at=NOW() WHERE id=:id');
    $used->execute([':id'=>$challenge['id']]);
    $pdo->commit();
    echo json_encode(['success'=>true,'message'=>'Vos préférences ont été enregistrées. Vous pouvez retirer votre accord à tout moment en contactant l’établissement.'], JSON_UNESCAPED_UNICODE);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    error_log('Public WhatsApp consent submission failed: '.$e->getMessage());
    apiError(503, 'Impossible d’enregistrer vos préférences pour le moment.');
}
