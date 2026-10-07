<?php
declare(strict_types=1);
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';
header('Content-Type: application/json; charset=utf-8');
// F-02-B: reference data is server-authoritative.
$pdo=getDatabaseConnection();$method=$_SERVER['REQUEST_METHOD'];
if($method==='GET'){requirePermission($pdo,'vacances.read');$s=$pdo->query("SELECT id,name,start_date,end_date,status,created_at,updated_at FROM vacations WHERE status <> 'ARCHIVED' ORDER BY start_date DESC,id DESC");echo json_encode(['success'=>true,'vacations'=>$s->fetchAll()],JSON_UNESCAPED_UNICODE);exit;}
requirePermission($pdo,$method==='POST'?'vacances.create':'vacances.update');requireCsrfToken();$d=readJsonBody();
if($method==='POST'){
$name=isset($d['name'])&&is_string($d['name'])?trim($d['name']):'';$start=$d['start_date']??'';$end=$d['end_date']??'';if($name===''||!is_string($start)||!is_string($end))apiError(422,'name, start_date et end_date sont requis');if($end<$start)apiError(422,'end_date doit être >= start_date');
try{$s=$pdo->prepare('INSERT INTO vacations(name,start_date,end_date,status) VALUES(:name,:start,:end,:status) RETURNING id,name,start_date,end_date,status,created_at,updated_at');$s->execute([':name'=>$name,':start'=>$start,':end'=>$end,':status'=>'ACTIVE']);http_response_code(201);echo json_encode(['success'=>true,'vacation'=>$s->fetch()],JSON_UNESCAPED_UNICODE);}catch(PDOException $e){apiError(500,'Erreur interne du serveur');}exit;}
$id=$_GET['id']??'';if(!preg_match('/^[0-9a-f-]{36}$/i',$id))apiError(400,'UUID invalide');$set=[];$p=[':id'=>$id];foreach(['name','start_date','end_date','status'] as $f)if(array_key_exists($f,$d)){$set[]="$f=:$f";$p[":$f"]=$d[$f];}if(!$set)apiError(422,'Aucun champ à modifier');$set[]='updated_at=NOW()';
try{$s=$pdo->prepare("UPDATE vacations SET ".implode(',',$set)." WHERE id=:id RETURNING id,name,start_date,end_date,status,created_at,updated_at");$s->execute($p);$row=$s->fetch();if(!$row)apiError(404,'Vacances introuvables');echo json_encode(['success'=>true,'vacation'=>$row],JSON_UNESCAPED_UNICODE);}catch(PDOException $e){apiError(500,'Erreur interne du serveur');}
