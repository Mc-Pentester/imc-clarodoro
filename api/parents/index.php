<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');
$pdo = getDatabaseConnection();
$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

function parentUuid(string $value, string $field): string
{
    if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value)) {
        apiError(422, $field . ' invalide');
    }
    return $value;
}

function parentText(array $data, string $field, int $max, bool $required = false): ?string
{
    $value = $data[$field] ?? '';
    if (!is_string($value)) apiError(422, $field . ' invalide');
    $value = trim($value);
    if ($required && $value === '') apiError(422, $field . ' est requis');
    if (mb_strlen($value, 'UTF-8') > $max) apiError(422, $field . ' est trop long');
    return $value === '' ? null : $value;
}

function parentPayload(array $data): array
{
    $first = parentText($data, 'first_name', 150, true);
    $last = parentText($data, 'last_name', 150, true);
    $phone = parentText($data, 'phone', 50);
    $email = parentText($data, 'email', 255);
    $address = parentText($data, 'address', 2000);
    $ninu = parentText($data, 'ninu', 10);
    if ($email !== null && !filter_var($email, FILTER_VALIDATE_EMAIL)) apiError(422, 'Adresse courriel invalide');
    if ($ninu !== null && !preg_match('/^\d{10}$/', $ninu)) apiError(422, 'Le NINU doit contenir exactement 10 chiffres');
    return ['first_name'=>$first, 'last_name'=>$last, 'phone'=>$phone, 'email'=>$email, 'address'=>$address, 'ninu'=>$ninu];
}

function parentRelationship(array $data): array
{
    $relationship = $data['relationship_type'] ?? 'OTHER';
    if (!is_string($relationship) || !in_array($relationship, ['FATHER','MOTHER','GUARDIAN','OTHER'], true)) {
        apiError(422, 'Lien de parenté invalide');
    }
    return [$relationship, filter_var($data['is_primary'] ?? false, FILTER_VALIDATE_BOOLEAN)];
}

if ($method === 'GET') {
    requirePermission($pdo, 'parents.read');
    $query = trim((string)($_GET['q'] ?? ''));
    $params = [];
    $where = '';
    if ($query !== '') {
        $where = "WHERE (p.first_name ILIKE :q OR p.last_name ILIKE :q OR COALESCE(p.phone,'') ILIKE :q OR COALESCE(p.ninu,'') ILIKE :q OR COALESCE(p.email,'') ILIKE :q)";
        $params[':q'] = '%' . $query . '%';
    }
    $stmt = $pdo->prepare(
        "SELECT p.id,p.first_name,p.last_name,p.ninu,p.phone,p.email,p.address,p.created_at,p.updated_at,
                COALESCE((
                    SELECT json_agg(json_build_object(
                        'student_id',s.id,'matricule',s.matricule,
                        'first_name',s.first_name,'last_name',s.last_name,
                        'relationship_type',sp.relationship_type,'is_primary',sp.is_primary
                    ) ORDER BY s.last_name,s.first_name)
                    FROM student_parents sp
                    INNER JOIN students s ON s.id=sp.student_id
                    WHERE sp.parent_id=p.id
                ), '[]'::json) AS children
         FROM parents p $where
         ORDER BY p.last_name,p.first_name,p.id"
    );
    $stmt->execute($params);
    $parents = $stmt->fetchAll();
    foreach ($parents as &$parent) {
        if (is_string($parent['children'])) $parent['children'] = json_decode($parent['children'], true) ?: [];
    }
    unset($parent);
    $students = $pdo->query("SELECT s.id,s.matricule,s.first_name,s.last_name FROM students s ORDER BY s.last_name,s.first_name,s.id")->fetchAll();
    echo json_encode(['success'=>true,'parents'=>$parents,'students'=>$students], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($method === 'POST') {
    requireCsrfToken();
    $data = readJsonBody();
    $action = $data['action'] ?? 'create';
    if ($action === 'link') {
        requirePermission($pdo, 'parents.link');
        $parentId = parentUuid((string)($data['parent_id'] ?? ''), 'parent_id');
        $studentId = parentUuid((string)($data['student_id'] ?? ''), 'student_id');
        [$relationship, $primary] = parentRelationship($data);
        $pdo->beginTransaction();
        try {
            $exists = $pdo->prepare('SELECT id FROM parents WHERE id=:id FOR UPDATE');
            $exists->execute([':id'=>$parentId]);
            if (!$exists->fetchColumn()) { $pdo->rollBack(); apiError(404, 'Parent introuvable'); }
            $student = $pdo->prepare('SELECT id FROM students WHERE id=:id');
            $student->execute([':id'=>$studentId]);
            if (!$student->fetchColumn()) { $pdo->rollBack(); apiError(404, 'Élève introuvable'); }
            if ($primary) $pdo->prepare('UPDATE student_parents SET is_primary=FALSE WHERE student_id=:id')->execute([':id'=>$studentId]);
            $link = $pdo->prepare(
                'INSERT INTO student_parents(student_id,parent_id,relationship_type,is_primary)
                 VALUES(:student_id,:parent_id,:relationship_type,:is_primary)
                 ON CONFLICT(student_id,parent_id) DO UPDATE SET relationship_type=EXCLUDED.relationship_type,is_primary=EXCLUDED.is_primary'
            );
            $link->execute([':student_id'=>$studentId,':parent_id'=>$parentId,':relationship_type'=>$relationship,':is_primary'=>$primary]);
            $pdo->commit();
            echo json_encode(['success'=>true,'linked'=>true], JSON_UNESCAPED_UNICODE);
            exit;
        } catch (Throwable $error) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            throw $error;
        }
    }
    if ($action !== 'create') apiError(422, 'Action invalide');
    requirePermission($pdo, 'parents.create');
    $parent = parentPayload($data);
    [$relationship, $primary] = parentRelationship($data);
    $studentId = isset($data['student_id']) && $data['student_id'] !== '' ? parentUuid((string)$data['student_id'], 'student_id') : null;
    $pdo->beginTransaction();
    try {
        $parentId = null;
        $reused = false;
        if ($parent['ninu'] !== null) {
            $find = $pdo->prepare('SELECT id FROM parents WHERE ninu=:ninu FOR UPDATE');
            $find->execute([':ninu'=>$parent['ninu']]);
            $parentId = $find->fetchColumn() ?: null;
            $reused = $parentId !== null;
        }
        $parentParams = [];
        foreach ($parent as $field => $value) $parentParams[':' . $field] = $value;
        if ($parentId !== null) {
            $update = $pdo->prepare('UPDATE parents SET first_name=:first_name,last_name=:last_name,phone=:phone,email=:email,address=:address,updated_at=NOW() WHERE id=:id');
            unset($parentParams[':ninu']);
            $update->execute($parentParams + [':id'=>$parentId]);
        } else {
            $insert = $pdo->prepare('INSERT INTO parents(first_name,last_name,phone,email,address,ninu) VALUES(:first_name,:last_name,:phone,:email,:address,:ninu) RETURNING id');
            $insert->execute($parentParams);
            $parentId = $insert->fetchColumn();
        }
        if ($studentId !== null) {
            $student = $pdo->prepare('SELECT id FROM students WHERE id=:id');
            $student->execute([':id'=>$studentId]);
            if (!$student->fetchColumn()) { $pdo->rollBack(); apiError(404, 'Élève introuvable'); }
            if ($primary) $pdo->prepare('UPDATE student_parents SET is_primary=FALSE WHERE student_id=:id')->execute([':id'=>$studentId]);
            $link = $pdo->prepare(
                'INSERT INTO student_parents(student_id,parent_id,relationship_type,is_primary)
                 VALUES(:student_id,:parent_id,:relationship_type,:is_primary)
                 ON CONFLICT(student_id,parent_id) DO UPDATE SET relationship_type=EXCLUDED.relationship_type,is_primary=EXCLUDED.is_primary'
            );
            $link->execute([':student_id'=>$studentId,':parent_id'=>$parentId,':relationship_type'=>$relationship,':is_primary'=>$primary]);
        }
        $pdo->commit();
        http_response_code(201);
        echo json_encode(['success'=>true,'parent_id'=>$parentId,'reused'=>$reused], JSON_UNESCAPED_UNICODE);
        exit;
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        if ($error instanceof PDOException && $error->getCode() === '23505') apiError(409, 'Ce NINU est déjà associé à une autre fiche parent');
        throw $error;
    }
}

if ($method === 'PATCH') {
    requirePermission($pdo, 'parents.update');
    requireCsrfToken();
    $id = parentUuid((string)($_GET['id'] ?? ''), 'id');
    $data = readJsonBody();
    $parent = parentPayload($data);
    $stmt = $pdo->prepare('UPDATE parents SET first_name=:first_name,last_name=:last_name,phone=:phone,email=:email,address=:address,ninu=:ninu,updated_at=NOW() WHERE id=:id RETURNING id');
    $parentParams = [];
    foreach ($parent as $field => $value) $parentParams[':' . $field] = $value;
    try {
        $stmt->execute($parentParams + [':id'=>$id]);
    } catch (PDOException $error) {
        if ($error->getCode() === '23505') apiError(409, 'Ce NINU est déjà utilisé par une autre fiche parent');
        throw $error;
    }
    if (!$stmt->fetchColumn()) apiError(404, 'Parent introuvable');
    echo json_encode(['success'=>true,'updated'=>true], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($method === 'DELETE') {
    requirePermission($pdo, 'parents.link');
    requireCsrfToken();
    $parentId = parentUuid((string)($_GET['parent_id'] ?? ''), 'parent_id');
    $studentId = parentUuid((string)($_GET['student_id'] ?? ''), 'student_id');
    $stmt = $pdo->prepare('DELETE FROM student_parents WHERE parent_id=:parent_id AND student_id=:student_id RETURNING parent_id');
    $stmt->execute([':parent_id'=>$parentId,':student_id'=>$studentId]);
    if (!$stmt->fetchColumn()) apiError(404, 'Association parent-élève introuvable');
    echo json_encode(['success'=>true,'unlinked'=>true,'parent_preserved'=>true], JSON_UNESCAPED_UNICODE);
    exit;
}

header('Allow: GET, POST, PATCH, DELETE');
apiError(405, 'Méthode HTTP non autorisée');
