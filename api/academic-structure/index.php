<?php
declare(strict_types=1);
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';
header('Content-Type: application/json; charset=utf-8');
$pdo=getDatabaseConnection(); $method=$_SERVER['REQUEST_METHOD']; $resource=$_GET['resource']??'';
function academicUuid(string $v):bool{return (bool)preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i',$v);}
function academicText(array $d,string $f,int $max):string{$v=$d[$f]??null;if(!is_string($v))apiError(422,$f.' est requis.');$v=trim($v);preg_match_all('/./us',$v,$m);if($v===''||count($m[0])>$max)apiError(422,$f.' est vide ou trop long.');return $v;}
if($method==='GET'){
 $user=requireAuthenticatedUser($pdo);$q=$pdo->prepare('SELECT 1 FROM role_permissions rp INNER JOIN permissions p ON p.id=rp.permission_id WHERE rp.role_id=:r AND p.name=:p LIMIT 1');$q->execute([':r'=>$user['role_id'],':p'=>'classes.manage']);$manager=(bool)$q->fetchColumn();
 if(!$manager)requirePermission($pdo,'resultats.read');
 if($manager||in_array($user['role_name'],['PDG','Directeur'],true)){$classes=$pdo->query('SELECT c.id,c.code,c.name,c.level_id,l.code AS level_code,l.name AS level_name,c.status FROM classes c LEFT JOIN levels l ON l.id=c.level_id ORDER BY l.name NULLS LAST,c.name,c.code,c.id')->fetchAll();}
 else{$s=$pdo->prepare("SELECT DISTINCT c.id,c.code,c.name,c.level_id,l.code AS level_code,l.name AS level_name,c.status FROM classes c LEFT JOIN levels l ON l.id=c.level_id INNER JOIN teacher_class_subjects tcs ON tcs.class_id=c.id AND tcs.status='ACTIVE' INNER JOIN user_teachers ut ON ut.teacher_id=tcs.teacher_id AND ut.user_id=:uid ORDER BY l.name NULLS LAST,c.name,c.code,c.id");$s->execute([':uid'=>$user['id']]);$classes=$s->fetchAll();}
 $levels=$manager?$pdo->query('SELECT id,code,name,description FROM levels ORDER BY name,code,id')->fetchAll():[];
 echo json_encode(['success'=>true,'classes'=>$classes,'levels'=>$levels,'managed'=>$manager],JSON_UNESCAPED_UNICODE);exit;
}
if(!in_array($method,['POST','PATCH'],true)){header('Allow: GET, POST, PATCH');apiError(405,'Méthode HTTP non autorisée.');}
requirePermission($pdo,'classes.manage');requireCsrfToken();$data=readJsonBody();
foreach(array_keys($data) as $f)if(!in_array($f,['resource','code','name','description','level_id','status'],true))apiError(422,'Champ inconnu : '.$f);
if(($data['resource']??'')!==$resource||!in_array($resource,['levels','classes'],true))apiError(422,'Ressource invalide.');
try{
 if($method==='POST'){
  $code=academicText($data,'code',50);$name=academicText($data,'name',150);
  if($resource==='levels'){$desc=isset($data['description'])&&is_string($data['description'])?trim($data['description']):null;$s=$pdo->prepare('INSERT INTO levels(code,name,description) VALUES(:c,:n,:d) RETURNING id,code,name,description');$s->execute([':c'=>$code,':n'=>$name,':d'=>$desc]);http_response_code(201);echo json_encode(['success'=>true,'level'=>$s->fetch()],JSON_UNESCAPED_UNICODE);exit;}
  $level=$data['level_id']??'';if(!is_string($level)||!academicUuid($level))apiError(422,'Un niveau scolaire valide est requis.');$status=$data['status']??'ACTIVE';if(!is_string($status)||!in_array($status,['ACTIVE','INACTIVE','ARCHIVED'],true))apiError(422,'Statut invalide.');
  $s=$pdo->prepare('INSERT INTO classes(code,name,level_id,status) VALUES(:c,:n,:l,:s) RETURNING id,code,name,level_id,status');$s->execute([':c'=>$code,':n'=>$name,':l'=>$level,':s'=>$status]);http_response_code(201);echo json_encode(['success'=>true,'class'=>$s->fetch()],JSON_UNESCAPED_UNICODE);exit;
 }
 $id=$_GET['id']??'';if(!is_string($id)||!academicUuid($id))apiError(400,'UUID invalide.');
 $sets=[];$params=[':id'=>$id];
 if($resource==='levels'){
  foreach(['code'=>50,'name'=>150] as $f=>$max)if(array_key_exists($f,$data)){$sets[]="$f=:$f";$params[":$f"]=academicText($data,$f,$max);}
  if(array_key_exists('description',$data)){if(!is_string($data['description']))apiError(422,'description invalide.');$sets[]='description=:description';$params[':description']=trim($data['description']);}
  if(!$sets)apiError(422,'Aucune modification fournie.');$sets[]='updated_at=NOW();';$s=$pdo->prepare('UPDATE levels SET '.implode(',',$sets).' WHERE id=:id RETURNING id,code,name,description');$s->execute($params);$row=$s->fetch();if(!$row)apiError(404,'Niveau introuvable.');echo json_encode(['success'=>true,'level'=>$row],JSON_UNESCAPED_UNICODE);exit;
 }
 foreach(['code'=>50,'name'=>150] as $f=>$max)if(array_key_exists($f,$data)){$sets[]="$f=:$f";$params[":$f"]=academicText($data,$f,$max);}
 if(array_key_exists('level_id',$data)){if(!is_string($data['level_id'])||!academicUuid($data['level_id']))apiError(422,'level_id invalide.');$sets[]='level_id=:level_id';$params[':level_id']=$data['level_id'];}
 if(array_key_exists('status',$data)){if(!is_string($data['status'])||!in_array($data['status'],['ACTIVE','INACTIVE','ARCHIVED'],true))apiError(422,'Statut invalide.');$sets[]='status=:status';$params[':status']=$data['status'];}
 if(!$sets)apiError(422,'Aucune modification fournie.');$sets[]='updated_at=NOW()';$s=$pdo->prepare('UPDATE classes SET '.implode(',',$sets).' WHERE id=:id RETURNING id,code,name,level_id,status');$s->execute($params);$row=$s->fetch();if(!$row)apiError(404,'Classe introuvable.');echo json_encode(['success'=>true,'class'=>$row],JSON_UNESCAPED_UNICODE);
}catch(PDOException $e){error_log('Academic structure write failed: '.$e->getMessage());if($e->getCode()==='23505')apiError(409,'Ce code existe déjà.');if($e->getCode()==='23503')apiError(409,'Le niveau est invalide ou référencé ; aucune donnée liée n’a été supprimée.');apiError(500,'Erreur interne lors de l’enregistrement.');}
