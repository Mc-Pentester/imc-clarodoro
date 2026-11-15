<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private');

if (($_SERVER['REQUEST_METHOD'] ?? 'POST') !== 'POST') {
    header('Allow: POST');
    apiError(405, 'Méthode HTTP non autorisée');
}
$pdo = getDatabaseConnection();
$user = requirePermission($pdo, 'whatsapp.message.send');
requireCsrfToken();
$data = readJsonBody();

$purpose = $data['purpose'] ?? '';
$templateName = $data['template_name'] ?? '';
$language = $data['language'] ?? 'fr';
$rootKey = $data['idempotency_key'] ?? '';
$parameters = $data['parameters'] ?? [];
$recipientType = strtoupper((string) ($data['recipient_type'] ?? 'STUDENT'));
$recipientId = $data['recipient_id'] ?? '';
$scope = strtoupper((string) ($data['scope'] ?? 'STUDENT_ONLY'));
$uuid = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i';
$purposes = ['ATTENDANCE', 'RESULTS_AVAILABLE', 'PAYMENT_REMINDER', 'GENERAL'];

if (!is_string($purpose) || !in_array($purpose, $purposes, true)) apiError(422, 'Finalité WhatsApp invalide');
if (!is_string($templateName) || !preg_match('/^[a-z0-9_]{1,128}$/', $templateName)) apiError(422, 'Modèle Meta invalide');
if (!is_string($language) || !preg_match('/^[a-z]{2,3}(?:_[A-Z]{2})?$/', $language)) apiError(422, 'Langue du modèle invalide');
if (!is_string($rootKey) || !preg_match('/^[A-Za-z0-9._:-]{16,80}$/', $rootKey)) apiError(422, 'Clé idempotente invalide');
if (!is_array($parameters) || count($parameters) > 20) apiError(422, 'Paramètres du modèle invalides');
$bodyParameters = [];
foreach ($parameters as $parameter) {
    if (!is_string($parameter) || trim($parameter) === '' || strlen($parameter) > 1024) apiError(422, 'Paramètre de modèle invalide');
    $bodyParameters[] = ['type' => 'text', 'text' => $parameter];
}

$enabled = getenv('WHATSAPP_SEND_ENABLED') === 'true';
$token = getenv('WHATSAPP_ACCESS_TOKEN');
$phoneNumberId = getenv('WHATSAPP_PHONE_NUMBER_ID');
$apiVersion = getenv('WHATSAPP_API_VERSION');
$templatesRaw = getenv('WHATSAPP_ALLOWED_TEMPLATES');
$allowedTemplates = is_string($templatesRaw) ? array_values(array_filter(array_map('trim', explode(',', $templatesRaw)))) : [];
$configured = $enabled && is_string($token) && $token !== ''
    && is_string($phoneNumberId) && preg_match('/^[0-9]+$/', $phoneNumberId)
    && is_string($apiVersion) && preg_match('/^v[0-9]+\\.[0-9]+$/', $apiVersion)
    && function_exists('curl_init') && in_array($templateName, $allowedTemplates, true);
if (!$configured) apiError(503, 'Envoi Meta non configuré ou modèle non autorisé; aucun message envoyé.');

$consentTargets = [];
$targetType = null;
$targetId = null;
if ($recipientType === 'STUDENT') {
    if (!is_string($recipientId) || !preg_match($uuid, $recipientId)) apiError(422, 'Élève invalide');
    if (!in_array($scope, ['STUDENT_ONLY', 'STUDENT_AND_PARENTS'], true)) apiError(422, 'Portée du message invalide');

    $studentStmt = $pdo->prepare("SELECT id, CASE WHEN date_of_birth IS NOT NULL AND date_of_birth <= (CURRENT_DATE - INTERVAL '18 years') THEN 1 ELSE 0 END AS is_adult FROM students WHERE id = :id AND status = 'ACTIVE' LIMIT 1");
    $studentStmt->execute([':id' => $recipientId]);
    $student = $studentStmt->fetch(PDO::FETCH_ASSOC);
    if (!$student) apiError(404, 'Élève actif introuvable');

    // En Haïti, la majorité est fixée à 18 ans. Une date de naissance absente
    // est traitée par prudence comme un élève mineur pour le routage.
    $isAdult = (int) $student['is_adult'] === 1;

    if ($isAdult && $scope === 'STUDENT_ONLY') {
        $targetType = 'STUDENT';
        $targetId = $recipientId;
        $stmt = $pdo->prepare(
            "SELECT id, recipient_type, phone_e164 FROM whatsapp_recipient_consents
             WHERE recipient_type = 'STUDENT' AND student_id = :id
               AND purpose = :purpose AND status = 'OPTED_IN'"
        );
        $stmt->execute([':id' => $recipientId, ':purpose' => $purpose]);
        $consentTargets = $stmt->fetchAll(PDO::FETCH_ASSOC);
    } else {
        // Mineurs: parents/responsables seulement, quel que soit le scope envoyé.
        // Majeurs en mode relation familiale: élève + tous les responsables actifs.
        if ($isAdult && $scope === 'STUDENT_AND_PARENTS') {
            $stmt = $pdo->prepare(
                "SELECT id, recipient_type, phone_e164 FROM whatsapp_recipient_consents
                 WHERE recipient_type = 'STUDENT' AND student_id = :id
                   AND purpose = :purpose AND status = 'OPTED_IN'"
            );
            $stmt->execute([':id' => $recipientId, ':purpose' => $purpose]);
            $consentTargets = array_merge($consentTargets, $stmt->fetchAll(PDO::FETCH_ASSOC));
        }
        $parentsStmt = $pdo->prepare(
            "SELECT c.id, c.recipient_type, c.phone_e164
             FROM student_parents sp
             INNER JOIN whatsapp_recipient_consents c
               ON c.parent_id = sp.parent_id
              AND c.recipient_type = 'PARENT'
              AND c.purpose = :purpose
              AND c.status = 'OPTED_IN'
             WHERE sp.student_id = :student_id
             ORDER BY sp.parent_id"
        );
        $parentsStmt->execute([':purpose' => $purpose, ':student_id' => $recipientId]);
        $consentTargets = array_merge($consentTargets, $parentsStmt->fetchAll(PDO::FETCH_ASSOC));
    }
} elseif (in_array($recipientType, ['STAFF', 'TEACHER', 'PARENT'], true)) {
    if (!is_string($recipientId) || !preg_match($uuid, $recipientId)) apiError(422, 'Destinataire invalide');
    $idColumn = ['STAFF' => 'staff_id', 'TEACHER' => 'teacher_id', 'PARENT' => 'parent_id'][$recipientType];
    $stmt = $pdo->prepare(
        "SELECT id, recipient_type, phone_e164 FROM whatsapp_recipient_consents
         WHERE recipient_type = :type AND {$idColumn} = :id
           AND purpose = :purpose AND status = 'OPTED_IN'"
    );
    $stmt->execute([':type' => $recipientType, ':id' => $recipientId, ':purpose' => $purpose]);
    $consentTargets = $stmt->fetchAll(PDO::FETCH_ASSOC);
} else {
    apiError(422, 'Type de destinataire non pris en charge');
}

if (!$consentTargets) apiError(403, 'Aucun destinataire ne possède un consentement WhatsApp actif pour cette finalité.');

$url = 'https://graph.facebook.com/' . $apiVersion . '/' . $phoneNumberId . '/messages';
$results = [];
$accepted = 0;
foreach ($consentTargets as $target) {
    $phone = (string) $target['phone_e164'];
    if (!preg_match('/^\\+[1-9][0-9]{7,14}$/', $phone)) {
        $results[] = ['consent_id' => $target['id'], 'status' => 'SKIPPED', 'reason' => 'INVALID_PHONE'];
        continue;
    }
    $key = $rootKey . ':' . (string) $target['id'];
    $payload = [
        'messaging_product' => 'whatsapp',
        'recipient_type' => 'individual',
        'to' => ltrim($phone, '+'),
        'type' => 'template',
        'template' => ['name' => $templateName, 'language' => ['code' => $language]],
    ];
    if ($bodyParameters) $payload['template']['components'] = [['type' => 'body', 'parameters' => $bodyParameters]];
    $payloadJson = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);

    try {
        $pdo->beginTransaction();
        $lock = $pdo->prepare('SELECT id, status, phone_e164 FROM whatsapp_recipient_consents WHERE id = :id FOR UPDATE');
        $lock->execute([':id' => $target['id']]);
        $current = $lock->fetch(PDO::FETCH_ASSOC);
        if (!$current || $current['status'] !== 'OPTED_IN' || $current['phone_e164'] !== $phone) {
            $pdo->rollBack();
            $results[] = ['consent_id' => $target['id'], 'status' => 'SKIPPED', 'reason' => 'CONSENT_NOT_ACTIVE'];
            continue;
        }
        $insert = $pdo->prepare(
            "INSERT INTO whatsapp_recipient_message_log
                (consent_id, idempotency_key, purpose, status, template_name, payload_sha256, initiated_by)
             VALUES (:consent, :key, :purpose, 'PROCESSING', :template, :hash, :actor)
             ON CONFLICT (idempotency_key) DO NOTHING RETURNING id"
        );
        $insert->execute([
            ':consent' => $target['id'], ':key' => $key, ':purpose' => $purpose,
            ':template' => $templateName, ':hash' => hash('sha256', $payloadJson), ':actor' => $user['id'],
        ]);
        $logId = $insert->fetchColumn();
        if (!$logId) {
            $pdo->rollBack();
            $results[] = ['consent_id' => $target['id'], 'status' => 'DUPLICATE'];
            continue;
        }

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 5, CURLOPT_TIMEOUT => 20,
            CURLOPT_HTTPHEADER => ['Authorization: Bearer ' . $token, 'Content-Type: application/json'],
            CURLOPT_POSTFIELDS => $payloadJson,
        ]);
        $body = curl_exec($ch);
        $http = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_errno($ch);
        curl_close($ch);
        $provider = is_string($body) ? json_decode($body, true) : null;
        $messageId = is_array($provider) ? ($provider['messages'][0]['id'] ?? null) : null;

        if ($curlError === 0 && $http >= 200 && $http < 300 && is_string($messageId)) {
            $update = $pdo->prepare("UPDATE whatsapp_recipient_message_log SET status='SENT', provider_message_id=:message, updated_at=NOW() WHERE id=:id");
            $update->execute([':message' => $messageId, ':id' => $logId]);
            $pdo->commit();
            $accepted++;
            $results[] = ['consent_id' => $target['id'], 'status' => 'ACCEPTED', 'message_log_id' => $logId, 'provider_message_id' => $messageId];
        } else {
            $errorCode = is_array($provider) ? (string) ($provider['error']['code'] ?? 'PROVIDER_ERROR') : ($curlError ? 'NETWORK_UNCERTAIN' : 'PROVIDER_ERROR');
            $update = $pdo->prepare("UPDATE whatsapp_recipient_message_log SET status='FAILED', provider_error_code=:code, updated_at=NOW() WHERE id=:id");
            $update->execute([':code' => substr($errorCode, 0, 80), ':id' => $logId]);
            $pdo->commit();
            $results[] = ['consent_id' => $target['id'], 'status' => 'FAILED', 'message_log_id' => $logId, 'provider_error_code' => substr($errorCode, 0, 80)];
        }
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        error_log('WhatsApp multi-recipient send failed: ' . $error->getMessage());
        $results[] = ['consent_id' => $target['id'], 'status' => 'ERROR'];
    }
}

echo json_encode([
    'success' => $accepted > 0,
    'accepted_by_meta' => $accepted,
    'total_eligible' => count($consentTargets),
    'results' => $results,
    'message' => 'Les résultats sont indiqués individuellement. Une acceptation par Meta ne confirme pas la livraison.',
], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
