<?php
declare(strict_types=1);
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';
header('Content-Type: application/json; charset=utf-8');
$pdo=getDatabaseConnection();$method=$_SERVER['REQUEST_METHOD'];
if($method==='GET'){requirePermission($pdo,'matieres.read');$s=$pdo->query("SELECT id,code,name,description,coefficient,status,created_at,updated_at FROM subjects WHERE status <> 'ARCHIVED' ORDER BY name ASC,id ASC");echo json_encode(['success'=>true,'subjects'=>$s->fetchAll()],JSON_UNESCAPED_UNICODE);exit;}
requirePermission($pdo,$method==='POST'?'matieres.create':'matieres.update');requireCsrfToken();$d=readJsonBody();
if($method==='POST'){
 $name=isset($d['name'])&&is_string($d['name'])?trim($d['name']):'';$code=isset($d['code'])&&is_string($d['code'])?trim($d['code']):'';$coef=$d['coefficient']??null;
 if($name==='')apiError(422,'name est requis');if($code==='')$code='MAT-'.strtoupper(substr(hash('sha256',$name.microtime(true)),0,12));
 if(!is_string($code)||strlen($code)>50)apiError(422,'code invalide');if(!is_numeric($coef)||$coef<=0)apiError(422,'coefficient doit être supérieur à zéro');
 try{$s=$pdo->prepare('INSERT INTO subjects(code,name,description,coefficient) VALUES(:code,:name,:description,:coefficient) RETURNING id,code,name,description,coefficient,status,created_at,updated_at');$s->execute([':code'=>$code,':name'=>$name,':description'=>isset($d['description'])&&is_string($d['description'])?trim($d['description']):null,':coefficient'=>$coef]);http_response_code(201);echo json_encode(['success'=>true,'subject'=>$s->fetch()],JSON_UNESCAPED_UNICODE);}catch(PDOException $e){apiError(str_contains($e->getMessage(),'subjects_code_unique')?409:500,'Erreur interne du serveur');}exit;
}
$id=$_GET['id']??'';if(!preg_match('/^[0-9a-f-]{36}$/i',$id))apiError(400,'UUID invalide');$set=[];$p=[':id'=>$id];
foreach(['code','name','description','coefficient','status'] as $f)if(array_key_exists($f,$d)){$set[]="$f=:$f";$p[":$f"]=$d[$f];}
if(!$set)apiError(422,'Aucun champ à modifier');if(isset($d['status'])&&!in_array($d['status'],['ACTIVE','INACTIVE','ARCHIVED'],true))apiError(422,'status invalide');$set[]='updated_at=NOW()';
try{$s=$pdo->prepare("UPDATE subjects SET ".implode(',',$set)." WHERE id=:id RETURNING id,code,name,description,coefficient,status,created_at,updated_at");$s->execute($p);$row=$s->fetch();if(!$row)apiError(404,'Matière introuvable');echo json_encode(['success'=>true,'subject'=>$row],JSON_UNESCAPED_UNICODE);}catch(PDOException $e){apiError(500,'Erreur interne du serveur');}
