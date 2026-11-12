<?php
declare(strict_types=1);
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';
header('Content-Type: application/json; charset=utf-8');

function expenseReconcileError(int $status, string $message): never { apiError($status, $message); }

$pdo = getDatabaseConnection();
$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
if ($method === 'GET') {
    requirePermission($pdo, 'depenses.reconcile');
    $stmt = $pdo->query(
        'SELECT a.source_key_hash, a.source_year_label, a.source_legacy_id,
                a.target_school_year_id, sy.label AS target_school_year_label,
                a.expense_id, a.payload_hash, a.actor_user_id, a.created_at
         FROM expense_reconciliation_audit a
         INNER JOIN school_years sy ON sy.id = a.target_school_year_id
         ORDER BY a.created_at DESC'
    );
    echo json_encode(['success'=>true,'reconciliations'=>$stmt->fetchAll()], JSON_UNESCAPED_UNICODE);
    exit;
}
if ($method !== 'POST') { header('Allow: GET, POST'); expenseReconcileError(405, 'Méthode non autorisée'); }
$actor = requirePermission($pdo, 'depenses.reconcile');
requireCsrfToken();
$data = readJsonBody();

$sourceYear = $data['source_year_label'] ?? null;
if (!is_string($sourceYear) || trim($sourceYear)==='' || strlen(trim($sourceYear))>50) expenseReconcileError(422,'Année historique invalide');
$sourceYear = trim($sourceYear);
$legacyValue = $data['legacy_id'] ?? null;
if (!is_string($legacyValue) && !is_int($legacyValue)) expenseReconcileError(422,'Identifiant historique invalide');
$legacyId = trim((string)$legacyValue);
if ($legacyId==='' || strlen($legacyId)>100) expenseReconcileError(422,'Identifiant historique invalide');
$description = $data['description'] ?? null;
if (!is_string($description)) expenseReconcileError(422,'Description invalide');
$description = trim($description);
if ($description==='' || strlen($description)>500) expenseReconcileError(422,'Description invalide');
$rawAmount = $data['amount'] ?? null;
if ((!is_int($rawAmount)&&!is_float($rawAmount)&&!is_string($rawAmount)) || !is_numeric($rawAmount)) expenseReconcileError(422,'Montant invalide');
$amount = number_format(round((float)$rawAmount,2),2,'.','');
if (!is_finite((float)$amount) || (float)$amount<=0 || (float)$amount>9999999999.99) expenseReconcileError(422,'Montant hors limites');
$date = $data['expense_date'] ?? null;
if (!is_string($date) || !preg_match('/^\\d{4}-\\d{2}-\\d{2}$/',$date)) expenseReconcileError(422,'Date invalide');
[$yy,$mm,$dd] = array_map('intval',explode('-',$date));
if (!checkdate($mm,$dd,$yy)) expenseReconcileError(422,'Date invalide');
$targetYearId = $data['target_school_year_id'] ?? null;
if (!is_string($targetYearId) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i',$targetYearId)) expenseReconcileError(422,'Année cible invalide');

$sourceHash = hash('sha256',$sourceYear.'|'.$legacyId);
$payloadHash = hash('sha256',json_encode([
    'source_year_label'=>$sourceYear,'legacy_id'=>$legacyId,
    'description'=>$description,'amount'=>$amount,'expense_date'=>$date
],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));

try {
    $pdo->beginTransaction();
    $lock=$pdo->prepare('SELECT pg_advisory_xact_lock(hashtext(:source_hash))');
    $lock->execute([':source_hash'=>$sourceHash]);
    $existing=$pdo->prepare('SELECT expense_id,payload_hash,target_school_year_id FROM expense_reconciliation_audit WHERE source_key_hash=:hash FOR UPDATE');
    $existing->execute([':hash'=>$sourceHash]);
    $already=$existing->fetch();
    if ($already) {
        if (!hash_equals((string)$already['payload_hash'],$payloadHash) || (string)$already['target_school_year_id']!==$targetYearId) {
            $pdo->rollBack(); expenseReconcileError(409,'Cette source a déjà été rapprochée avec des valeurs différentes. Aucun changement effectué.');
        }
        $pdo->commit();
        echo json_encode(['success'=>true,'created'=>false,'already_imported'=>true,'expense_id'=>$already['expense_id']],JSON_UNESCAPED_UNICODE); exit;
    }
    $year=$pdo->prepare("SELECT id FROM school_years WHERE id=:id AND status <> 'ARCHIVED' FOR SHARE");
    $year->execute([':id'=>$targetYearId]);
    if ($year->fetchColumn()===false) { $pdo->rollBack(); expenseReconcileError(422,'Année scolaire cible introuvable ou archivée'); }

    // Older versions may already have inserted a raw legacy ID without an audit row.
    $old=$pdo->prepare('SELECT id,school_year_id,description,amount::text AS amount,expense_date::text AS expense_date FROM expenses WHERE legacy_id=:legacy ORDER BY created_at,id FOR UPDATE');
    $old->execute([':legacy'=>$legacyId]);
    $oldRows=$old->fetchAll();
    if (count($oldRows)>1) {
        $pdo->rollBack();
        expenseReconcileError(409,'Plusieurs dépenses portent cet identifiant historique. Rapprochement manuel requis.');
    }
    $oldRow=$oldRows[0]??null;
    if ($oldRow) {
        if ((string)$oldRow['school_year_id']!==$targetYearId) {
            $pdo->rollBack();
            expenseReconcileError(409,'Cette dépense existe déjà dans une autre année scolaire. Aucun doublon ne sera créé; vérifiez son affectation.');
        }
        $same=(string)$oldRow['description']===$description
            && number_format((float)$oldRow['amount'],2,'.','')===$amount
            && (string)$oldRow['expense_date']===$date;
        if (!$same) { $pdo->rollBack(); expenseReconcileError(409,'Une dépense avec cet identifiant existe mais ses valeurs diffèrent. Vérification manuelle requise.'); }
        $expenseId=(string)$oldRow['id']; $created=false;
    } else {
        $insert=$pdo->prepare('INSERT INTO expenses(school_year_id,description,amount,expense_date,created_by,legacy_id) VALUES(:year,:description,:amount,:date,:actor,:legacy) RETURNING id');
        $insert->execute([':year'=>$targetYearId,':description'=>$description,':amount'=>$amount,':date'=>$date,':actor'=>$actor['id'],':legacy'=>$sourceHash]);
        $expenseId=(string)$insert->fetchColumn(); $created=true;
    }
    $sourceAlreadyLinked = $pdo->prepare(
        'SELECT source_key_hash FROM expense_reconciliation_audit
         WHERE expense_id = :expense_id AND source_key_hash <> :source_hash LIMIT 1'
    );
    $sourceAlreadyLinked->execute([':expense_id'=>$expenseId, ':source_hash'=>$sourceHash]);
    if ($sourceAlreadyLinked->fetchColumn() !== false) {
        $pdo->rollBack();
        expenseReconcileError(409, 'Cette dépense PostgreSQL est déjà liée à une autre source historique. Vérification manuelle requise.');
    }
    $audit=$pdo->prepare("INSERT INTO expense_reconciliation_audit(source_key_hash,source_year_label,source_legacy_id,target_school_year_id,expense_id,payload_hash,actor_user_id,action) VALUES(:hash,:source_year,:legacy,:target_year,:expense,:payload,:actor,'IMPORTED')");
    $audit->execute([':hash'=>$sourceHash,':source_year'=>$sourceYear,':legacy'=>$legacyId,':target_year'=>$targetYearId,':expense'=>$expenseId,':payload'=>$payloadHash,':actor'=>$actor['id']]);
    $pdo->commit();
    http_response_code($created?201:200);
    echo json_encode(['success'=>true,'created'=>$created,'already_imported'=>false,'expense_id'=>$expenseId],JSON_UNESCAPED_UNICODE);
} catch (PDOException $error) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    if ($error->getCode()==='23505') expenseReconcileError(409,'Cette dépense a déjà été importée ou entre en conflit. Rechargez les rapprochements.');
    error_log('Expense reconciliation failed: '.$error->getMessage());
    expenseReconcileError(500,'Erreur interne pendant le rapprochement des dépenses');
}
