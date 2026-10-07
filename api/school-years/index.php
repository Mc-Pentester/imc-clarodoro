<?php
declare(strict_types=1);
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';
header('Content-Type: application/json; charset=utf-8');

$pdo = getDatabaseConnection();
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    requirePermission($pdo, 'annees.read');
    $stmt = $pdo->query("SELECT id,label,start_date,end_date,status,created_at,updated_at FROM school_years WHERE status <> 'ARCHIVED' ORDER BY start_date DESC,id DESC");
    echo json_encode(['success'=>true,'schoolYears'=>$stmt->fetchAll(),'count'=>$stmt->rowCount()], JSON_UNESCAPED_UNICODE);
    exit;
}

$user = requirePermission($pdo, $method === 'POST' ? 'annees.create' : 'annees.update');
requireCsrfToken();
$data = readJsonBody();

if ($method === 'POST') {
    $label=isset($data['label'])&&is_string($data['label'])?trim($data['label']):'';
    $start=$data['start_date']??null; $end=$data['end_date']??null;
    if ($label===''||!is_string($start)||!is_string($end)) apiError(422,'label, start_date et end_date sont requis');
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/',$start)||!preg_match('/^\d{4}-\d{2}-\d{2}$/',$end)) apiError(422,'Dates invalides');
    $status=isset($data['status'])&&is_string($data['status'])?$data['status']:'PLANNED';
    if (!in_array($status,['PLANNED','ACTIVE','CLOSED','ARCHIVED'],true)) apiError(422,'status invalide');
    try {
        $stmt=$pdo->prepare('INSERT INTO school_years(label,start_date,end_date,status) VALUES(:label,:start,:end,:status) RETURNING id,label,start_date,end_date,status,created_at,updated_at');
        $stmt->execute([':label'=>$label,':start'=>$start,':end'=>$end,':status'=>$status]);
        http_response_code(201); echo json_encode(['success'=>true,'schoolYear'=>$stmt->fetch()],JSON_UNESCAPED_UNICODE);
    } catch(PDOException $e){ apiError(str_contains($e->getMessage(),'school_years_one_active')?409:500,str_contains($e->getMessage(),'school_years_label_unique')?'Année déjà existante':'Erreur interne du serveur'); }
    exit;
}
$id=$_GET['id']??'';
if(!preg_match('/^[0-9a-f-]{36}$/i',$id)) apiError(400,'UUID invalide');
$allowed=['label','start_date','end_date','status']; $set=[];$params=[':id'=>$id];
foreach($allowed as $f){if(array_key_exists($f,$data)){if(!is_string($data[$f]))apiError(422,"$f invalide");$set[]="$f=:$f";$params[":$f"]=trim($data[$f]);}}
if(!$set) apiError(422,'Aucun champ à modifier');
if(isset($params[':status'])&&!in_array($params[':status'],['PLANNED','ACTIVE','CLOSED','ARCHIVED'],true))apiError(422,'status invalide');
$set[]='updated_at=NOW()';
try {
    $pdo->beginTransaction();
    if (isset($params[':status']) && $params[':status'] === 'ACTIVE') {
        $pdo->exec("UPDATE school_years SET status='CLOSED', updated_at=NOW() WHERE status='ACTIVE' AND id<>".$pdo->quote($id));
    }
    $stmt=$pdo->prepare("UPDATE school_years SET ".implode(',',$set)." WHERE id=:id RETURNING id,label,start_date,end_date,status,created_at,updated_at");
    $stmt->execute($params);
    $row=$stmt->fetch();
    if(!$row){$pdo->rollBack();apiError(404,'Année scolaire introuvable');}
    $pdo->commit();
    echo json_encode(['success'=>true,'schoolYear'=>$row],JSON_UNESCAPED_UNICODE);
} catch(PDOException $e) {
    if($pdo->inTransaction())$pdo->rollBack();
    apiError(str_contains($e->getMessage(),'school_years_one_active')?409:500,'Erreur interne du serveur');
}
