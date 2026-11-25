<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

/**
 * Journalise les erreurs SQL de création sans exposer les données personnelles
 * éventuellement incluses dans le DETAIL PostgreSQL (NINU, téléphone, etc.).
 */
function logStudentCreationDatabaseFailure(PDOException $exception): void
{
    $sqlState = 'unknown';
    if (isset($exception->errorInfo) && is_array($exception->errorInfo) && isset($exception->errorInfo[0])) {
        $sqlState = (string) $exception->errorInfo[0];
    } elseif ($exception->getCode() !== '') {
        $sqlState = (string) $exception->getCode();
    }

    $message = $exception->getMessage();
    $message = preg_replace(
        '/(DETAIL:\\s*Key\\s*\\([^)]*\\)\\s*=\\s*)\\([^)]*\\)/i',
        '$1([redacted])',
        $message
    ) ?? 'Database error';
    $message = preg_replace(
        "/(invalid input syntax for type [^:]+:\\s*)'[^']*'/i",
        '$1[redacted]',
        $message
    ) ?? 'Database error';

    error_log('Student creation failed [SQLSTATE ' . $sqlState . ']: ' . substr($message, 0, 1500));
}

function normalizeStudentParents($raw): array
{
    if (!is_array($raw) || !array_is_list($raw) || count($raw) > 100) apiError(422, 'parents doit contenir au maximum 100 responsables');
    $result = []; $primary = 0; $relations = ['FATHER','MOTHER','GUARDIAN','OTHER'];
    foreach ($raw as $item) {
        if (!is_array($item)) apiError(422, 'Chaque responsable doit être un objet');
        $p = [];
        foreach (['parent_id','first_name','last_name','phone','email','address','ninu','relationship_type'] as $f) {
            if (isset($item[$f]) && !is_string($item[$f])) apiError(422, "Champ parent invalide: $f");
            $p[$f] = trim((string)($item[$f] ?? ''));
        }
        $p['is_primary'] = filter_var($item['is_primary'] ?? false, FILTER_VALIDATE_BOOLEAN);
        $hasData = $p['parent_id'] !== '';
        foreach (['first_name','last_name','phone','email','address','ninu'] as $f) if ($p[$f] !== '') $hasData = true;
        if ($p['parent_id'] !== '' && !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $p['parent_id'])) apiError(422, 'Identifiant de fiche parent invalide');
        if (!$hasData) continue;
        if ($p['first_name'] === '' || $p['last_name'] === '') apiError(422, 'Le nom et le prénom sont requis pour chaque responsable renseigné');
        if (strlen($p['first_name']) > 150 || strlen($p['last_name']) > 150 || strlen($p['phone']) > 50 || strlen($p['email']) > 255 || strlen($p['address']) > 2000) apiError(422, 'Coordonnées du responsable trop longues');
        if ($p['email'] !== '' && !filter_var($p['email'], FILTER_VALIDATE_EMAIL)) apiError(422, 'Adresse courriel du responsable invalide');
        if ($p['ninu'] !== '' && !preg_match('/^\d{10}$/', $p['ninu'])) apiError(422, 'Le NINU du responsable doit contenir exactement 10 chiffres');
        if (!in_array($p['relationship_type'], $relations, true)) apiError(422, 'Lien de parenté invalide');
        if ($p['is_primary']) $primary++;
        $result[] = $p;
    }
    if ($primary > 1) apiError(422, 'Un seul responsable principal peut être sélectionné');
    return $result;
}

function saveStudentParents(PDO $pdo, string $studentId, array $parents): void
{
    $pdo->prepare('DELETE FROM student_parents WHERE student_id = :id')->execute([':id' => $studentId]);
    foreach ($parents as $p) {
        $parentId = null;
        if ($p['parent_id'] !== '') {
            $find = $pdo->prepare('SELECT id FROM parents WHERE id = :id FOR UPDATE');
            $find->execute([':id' => $p['parent_id']]);
            $parentId = $find->fetchColumn() ?: null;
            if (!$parentId) apiError(422, 'La fiche parent sélectionnée est introuvable');
        }
        if ($parentId === null && $p['ninu'] !== '') {
            $find = $pdo->prepare('SELECT id FROM parents WHERE ninu = :ninu FOR UPDATE');
            $find->execute([':ninu' => $p['ninu']]);
            $parentId = $find->fetchColumn() ?: null;
        }
        if ($parentId) {
            $stmt = $pdo->prepare('UPDATE parents SET first_name=:first_name,last_name=:last_name,phone=:phone,email=:email,address=:address,updated_at=NOW() WHERE id=:id');
            $stmt->execute([':first_name'=>$p['first_name'],':last_name'=>$p['last_name'],':phone'=>$p['phone'] ?: null,':email'=>$p['email'] ?: null,':address'=>$p['address'] ?: null,':id'=>$parentId]);
        } else {
            $stmt = $pdo->prepare('INSERT INTO parents(last_name,first_name,phone,email,address,ninu) VALUES(:last_name,:first_name,:phone,:email,:address,:ninu) RETURNING id');
            $stmt->execute([':last_name'=>$p['last_name'],':first_name'=>$p['first_name'],':phone'=>$p['phone'] ?: null,':email'=>$p['email'] ?: null,':address'=>$p['address'] ?: null,':ninu'=>$p['ninu'] ?: null]);
            $parentId = $stmt->fetchColumn();
        }
        $link = $pdo->prepare('INSERT INTO student_parents(student_id,parent_id,relationship_type,is_primary) VALUES(:student_id,:parent_id,:relationship_type,:is_primary)');
        $link->bindValue(':student_id', $studentId, PDO::PARAM_STR);
        $link->bindValue(':parent_id', $parentId, PDO::PARAM_STR);
        $link->bindValue(':relationship_type', $p['relationship_type'], PDO::PARAM_STR);
        // PDO_PGSQL may serialize PHP false as an empty string when execute(array)
        // is used. Bind explicitly as BOOLEAN so PostgreSQL receives FALSE, not ''.
        $link->bindValue(':is_primary', $p['is_primary'], PDO::PARAM_BOOL);
        $link->execute();
    }
}

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $pdo = getDatabaseConnection();
    $user = requirePermission($pdo, 'eleves.read');

    // Les rôles qui disposent d'un droit de création ou de modification
    // des dossiers peuvent consulter la liste complète. Les comptes en
    // lecture seule restent strictement limités aux classes qui leur sont
    // affectées côté serveur.
    $manageScope = $pdo->prepare(
        "SELECT COUNT(*)
         FROM role_permissions rp
         INNER JOIN permissions p ON p.id = rp.permission_id
         WHERE rp.role_id = :role_id
           AND p.name IN ('eleves.create', 'eleves.update')"
    );
    $manageScope->execute([':role_id' => $user['role_id']]);
    $canManageStudentRecords = $user['role_name'] === 'PDG'
        || (int) $manageScope->fetchColumn() > 0;

    if ($canManageStudentRecords) {
        $stmt = $pdo->prepare(
            'SELECT
                s.id,
                s.matricule,
                s.last_name,
                s.first_name,
                s.date_of_birth,
                s.sex,
                s.address,
                s.phone,
                s.profile_data,
                s.status,
                s.created_at,
                s.updated_at,
                active_enrollment.class_id,
                active_enrollment.school_year_id,
                active_enrollment.class_name,
                active_enrollment.school_year_label
             FROM students s
             LEFT JOIN LATERAL (
                SELECT e.class_id, e.school_year_id, c.name AS class_name, sy.label AS school_year_label
                FROM enrollments e
                INNER JOIN classes c ON c.id = e.class_id
                INNER JOIN school_years sy ON sy.id = e.school_year_id
                WHERE e.student_id = s.id AND e.status = \'ACTIVE\'
                ORDER BY sy.start_date DESC, e.created_at DESC, e.id DESC
                LIMIT 1
             ) active_enrollment ON TRUE
             ORDER BY s.created_at DESC, s.id DESC'
        );
    } else {
        // F-03: le périmètre est déterminé exclusivement par la relation
        // serveur users -> teachers -> teacher_class_subjects -> classes
        // -> enrollments -> students. Aucun identifiant de classe fourni
        // par le client n'intervient dans l'autorisation.
        $stmt = $pdo->prepare(
            "SELECT DISTINCT
                s.id,
                s.matricule,
                s.last_name,
                s.first_name,
                s.date_of_birth,
                s.sex,
                s.address,
                s.phone,
                s.profile_data,
                s.profile_data->>'photo' AS photo,
                e.class_id,
                e.school_year_id,
                c.name AS class_name,
                sy.label AS school_year_label,
                s.status,
                s.created_at,
                s.updated_at
             FROM students s
             INNER JOIN enrollments e
                ON e.student_id = s.id
               AND e.status = :enrollment_status
             INNER JOIN classes c ON c.id = e.class_id
             INNER JOIN school_years sy ON sy.id = e.school_year_id
             INNER JOIN teacher_class_subjects tcs
                ON tcs.class_id = e.class_id
               AND tcs.status = :assignment_status
             INNER JOIN user_teachers ut
                ON ut.teacher_id = tcs.teacher_id
               AND ut.user_id = :user_id
             ORDER BY s.created_at DESC, s.id DESC"
        );
        $stmt->bindValue(':enrollment_status', 'ACTIVE');
        $stmt->bindValue(':assignment_status', 'ACTIVE');
        $stmt->bindValue(':user_id', $user['id']);
    }

    $stmt->execute();
    $students = $stmt->fetchAll();
    $parentStmt = $pdo->prepare('SELECT p.id,p.first_name,p.last_name,p.ninu,p.phone,p.email,p.address,sp.relationship_type,sp.is_primary FROM student_parents sp INNER JOIN parents p ON p.id=sp.parent_id WHERE sp.student_id=:student_id ORDER BY sp.is_primary DESC,p.last_name,p.first_name');
    foreach ($students as &$student) {
        if (isset($student['profile_data']) && is_string($student['profile_data'])) {
            $decoded = json_decode($student['profile_data'], true);
            $student['profile_data'] = is_array($decoded) ? $decoded : [];
        }
        $parentStmt->execute([':student_id'=>$student['id']]);
        $student['parents'] = $parentStmt->fetchAll();
    }
    unset($student);

    echo json_encode([
        'success' => true,
        'students' => $students,
        'count' => count($students),
    ], JSON_UNESCAPED_UNICODE);
}
elseif ($method === 'POST') {
    $pdo = getDatabaseConnection();
    $user = requirePermission($pdo, 'eleves.create');
    requireCsrfToken();

    $data = readJsonBody();

    // Validation des champs obligatoires
    $matricule = isset($data['matricule']) && is_string($data['matricule'])
        ? trim($data['matricule'])
        : '';

    $lastName = isset($data['last_name']) && is_string($data['last_name'])
        ? trim($data['last_name'])
        : '';

    $firstName = isset($data['first_name']) && is_string($data['first_name'])
        ? trim($data['first_name'])
        : '';

    if ($matricule === '') {
        apiError(422, 'matricule est requis');
    }

    if ($lastName === '') {
        apiError(422, 'last_name est requis');
    }

    if ($firstName === '') {
        apiError(422, 'first_name est requis');
    }

    // Validation des longueurs
    if (strlen($matricule) > 100) {
        apiError(422, 'matricule trop long (max 100 caractères)');
    }

    if (strlen($lastName) > 150) {
        apiError(422, 'last_name trop long (max 150 caractères)');
    }

    if (strlen($firstName) > 150) {
        apiError(422, 'first_name trop long (max 150 caractères)');
    }

    // Validation des champs facultatifs
    $dateOfBirth = null;
    if (isset($data['date_of_birth']) && $data['date_of_birth'] !== '') {
        if (!is_string($data['date_of_birth'])) {
            apiError(422, 'date_of_birth invalide');
        }
        $date = DateTime::createFromFormat('Y-m-d', $data['date_of_birth']);
        if (!$date || $date->format('Y-m-d') !== $data['date_of_birth']) {
            apiError(422, 'date_of_birth invalide (format YYYY-MM-DD requis)');
        }
        $dateOfBirth = $data['date_of_birth'];
    }

    $sex = null;
    if (isset($data['sex']) && $data['sex'] !== '') {
        if (!is_string($data['sex'])) {
            apiError(422, 'sex invalide');
        }
        $validSex = ['M', 'F', 'OTHER', 'UNSPECIFIED'];
        if (!in_array($data['sex'], $validSex, true)) {
            apiError(422, 'sex invalide (valeurs acceptées: M, F, OTHER, UNSPECIFIED)');
        }
        $sex = $data['sex'];
    }

    $address = null;
    if (isset($data['address']) && is_string($data['address'])) {
        $address = trim($data['address']);
    }

    $phone = null;
    if (isset($data['phone']) && is_string($data['phone'])) {
        $phone = trim($data['phone']);
        if (strlen($phone) > 50) {
            apiError(422, 'phone trop long (max 50 caractères)');
        }
    }

    $status = 'ACTIVE';
    if (isset($data['status']) && $data['status'] !== '') {
        if (!is_string($data['status'])) {
            apiError(422, 'status invalide');
        }
        $validStatus = ['ACTIVE', 'INACTIVE', 'SUSPENDED'];
        if (!in_array($data['status'], $validStatus, true)) {
            apiError(422, 'status invalide (valeurs acceptées: ACTIVE, INACTIVE, SUSPENDED)');
        }
        $status = $data['status'];
    }

    $profileData = (object) [];
    if (array_key_exists('profile_data', $data)) {
        if (!is_array($data['profile_data'])) {
            apiError(422, 'profile_data doit être un objet JSON');
        }
        // JSON objects arrive as associative PHP arrays. Reject non-empty JSON arrays,
        // while normalizing an empty object/array representation to an object so the
        // PostgreSQL jsonb object constraint remains satisfied.
        if (array_is_list($data['profile_data']) && $data['profile_data'] !== []) {
            apiError(422, 'profile_data doit être un objet JSON');
        }
        if ($data['profile_data'] === []) {
            $profileData = (object) [];
        }
        $encodedProfileData = json_encode($data['profile_data'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($encodedProfileData === false || strlen($encodedProfileData) > 65536) {
            apiError(422, 'profile_data invalide ou trop volumineux');
        }
        $profileData = $data['profile_data'];
    }

    $parents = array_key_exists('parents', $data) ? normalizeStudentParents($data['parents']) : [];
    $classId = isset($data['class_id']) && is_string($data['class_id']) ? trim($data['class_id']) : '';
    $schoolYearId = isset($data['school_year_id']) && is_string($data['school_year_id']) ? trim($data['school_year_id']) : '';
    if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $classId)) {
        apiError(422, 'Une classe valide est requise');
    }
    if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $schoolYearId)) {
        apiError(422, 'Une année scolaire valide est requise');
    }

    // Refuser les champs générés par le serveur
    $forbiddenFields = ['id', 'created_at', 'updated_at'];
    foreach ($forbiddenFields as $field) {
        if (array_key_exists($field, $data)) {
            apiError(422, "Le champ $field ne peut pas être fourni par le client");
        }
    }

    // Refuser les champs inconnus
    $allowedFields = ['matricule', 'last_name', 'first_name', 'date_of_birth', 'sex', 'address', 'phone', 'status', 'profile_data', 'class_id', 'school_year_id', 'parents'];
    foreach (array_keys($data) as $field) {
        if (!in_array($field, $allowedFields, true)) {
            apiError(422, "Champ inconnu: $field");
        }
    }

    // Student and academic enrollment are committed atomically.
    try {
        $pdo->beginTransaction();
        $referenceStmt = $pdo->prepare(
            "SELECT c.id AS class_id, c.name AS class_name, sy.id AS school_year_id, sy.label AS school_year_label
             FROM classes c CROSS JOIN school_years sy
             WHERE c.id = :class_id AND c.status = 'ACTIVE'
               AND sy.id = :school_year_id AND sy.status = 'ACTIVE'
             LIMIT 1"
        );
        $referenceStmt->execute([':class_id' => $classId, ':school_year_id' => $schoolYearId]);
        $references = $referenceStmt->fetch();
        if (!$references) {
            $pdo->rollBack();
            apiError(422, 'La classe ou l’année scolaire sélectionnée est indisponible ou inactive');
        }

        $stmt = $pdo->prepare(
            'INSERT INTO students (
                matricule,
                last_name,
                first_name,
                date_of_birth,
                sex,
                address,
                phone,
                profile_data,
                status
            ) VALUES (
                :matricule,
                :last_name,
                :first_name,
                :date_of_birth,
                :sex,
                :address,
                :phone,
                CAST(:profile_data AS jsonb),
                :status
            ) RETURNING
                id,
                matricule,
                last_name,
                first_name,
                date_of_birth,
                sex,
                address,
                phone,
                profile_data,
                status,
                created_at,
                updated_at'
        );

        $stmt->execute([
            ':matricule' => $matricule,
            ':last_name' => $lastName,
            ':first_name' => $firstName,
            ':date_of_birth' => $dateOfBirth,
            ':sex' => $sex,
            ':address' => $address,
            ':phone' => $phone,
            ':profile_data' => json_encode($profileData, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            ':status' => $status,
        ]);

        $student = $stmt->fetch();
        saveStudentParents($pdo, $student['id'], $parents);
        $enrollmentStmt = $pdo->prepare(
            "INSERT INTO enrollments (student_id, class_id, school_year_id, status)
             VALUES (:student_id, :class_id, :school_year_id, 'ACTIVE')"
        );
        $enrollmentStmt->execute([
            ':student_id' => $student['id'],
            ':class_id' => $classId,
            ':school_year_id' => $schoolYearId,
        ]);
        $student['class_id'] = $references['class_id'];
        $student['school_year_id'] = $references['school_year_id'];
        $student['class_name'] = $references['class_name'];
        $student['school_year_label'] = $references['school_year_label'];
        $pdo->commit();
        if (isset($student['profile_data']) && is_string($student['profile_data'])) {
            $decoded = json_decode($student['profile_data'], true);
            $student['profile_data'] = is_array($decoded) ? $decoded : [];
        }

        http_response_code(201);

        echo json_encode([
            'success' => true,
            'student' => $student,
        ], JSON_UNESCAPED_UNICODE);
    } catch (PDOException $e) {
        // Journaliser avant le rollback : une erreur pendant celui-ci ne doit
        // jamais empêcher la trace de l'échec initial de création.
        logStudentCreationDatabaseFailure($e);
        if ($pdo->inTransaction()) {
            try {
                $pdo->rollBack();
            } catch (Throwable $rollbackError) {
                error_log('Student creation rollback failed: ' . substr($rollbackError->getMessage(), 0, 500));
            }
        }
        if (str_contains($e->getMessage(), 'students_matricule_unique')) {
            apiError(409, 'Matricule déjà utilisé');
        }
        if (str_contains($e->getMessage(), 'enrollments_one_active_per_student_year')) {
            apiError(409, 'Cet élève possède déjà une inscription active pour cette année scolaire');
        }
        apiError(500, 'Erreur interne du serveur');
    }
}
elseif ($method === 'PUT' || $method === 'PATCH') {
    $pdo = getDatabaseConnection();
    $user = requirePermission($pdo, 'eleves.update');
    requireCsrfToken();

    // Validate UUID parameter
    $id = $_GET['id'] ?? '';
    if ($id === '') {
        apiError(400, 'Paramètre id requis');
    }

    // Validate UUID format (basic check for 8-4-4-4-12 hex pattern)
    if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $id)) {
        apiError(400, 'UUID invalide');
    }

    $data = readJsonBody();

    $profileData = (object) [];
    if (array_key_exists('profile_data', $data)) {
        if (!is_array($data['profile_data'])) {
            apiError(422, 'profile_data doit être un objet JSON');
        }
        // JSON objects arrive as associative PHP arrays. Reject non-empty JSON arrays,
        // while normalizing an empty object/array representation to an object so the
        // PostgreSQL jsonb object constraint remains satisfied.
        if (array_is_list($data['profile_data']) && $data['profile_data'] !== []) {
            apiError(422, 'profile_data doit être un objet JSON');
        }
        if ($data['profile_data'] === []) {
            $profileData = (object) [];
        }
        $encodedProfileData = json_encode($data['profile_data'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($encodedProfileData === false || strlen($encodedProfileData) > 65536) {
            apiError(422, 'profile_data invalide ou trop volumineux');
        }
        $profileData = $data['profile_data'];
    }

    $parents = array_key_exists('parents', $data) ? normalizeStudentParents($data['parents']) : null;

    // Refuser les champs générés par le serveur
    $forbiddenFields = ['id', 'created_at', 'updated_at'];
    foreach ($forbiddenFields as $field) {
        if (array_key_exists($field, $data)) {
            apiError(422, "Le champ $field ne peut pas être fourni par le client");
        }
    }

    // Refuser les champs inconnus
    $allowedFields = ['matricule', 'last_name', 'first_name', 'date_of_birth', 'sex', 'address', 'phone', 'status', 'profile_data', 'class_id', 'parents'];
    foreach (array_keys($data) as $field) {
        if (!in_array($field, $allowedFields, true)) {
            apiError(422, "Champ inconnu: $field");
        }
    }

    // PUT requires all required fields
    if ($method === 'PUT') {
        $matricule = isset($data['matricule']) && is_string($data['matricule'])
            ? trim($data['matricule'])
            : '';

        $lastName = isset($data['last_name']) && is_string($data['last_name'])
            ? trim($data['last_name'])
            : '';

        $firstName = isset($data['first_name']) && is_string($data['first_name'])
            ? trim($data['first_name'])
            : '';

        if ($matricule === '') {
            apiError(422, 'matricule est requis pour PUT');
        }

        if ($lastName === '') {
            apiError(422, 'last_name est requis pour PUT');
        }

        if ($firstName === '') {
            apiError(422, 'first_name est requis pour PUT');
        }
    }

    // La classe est modifiée sur l'inscription active, jamais directement sur students.
    $newClassId = null;
    if (array_key_exists('class_id', $data)) {
        if (!is_string($data['class_id']) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', trim($data['class_id']))) {
            apiError(422, 'Une classe valide est requise');
        }
        $newClassId = trim($data['class_id']);
    }

    // Validate provided fields
    $updateFields = [];
    $params = [':id' => $id];

    if (isset($data['matricule']) && is_string($data['matricule'])) {
        $matricule = trim($data['matricule']);
        if ($matricule === '') {
            apiError(422, 'matricule ne peut pas être vide');
        }
        if (strlen($matricule) > 100) {
            apiError(422, 'matricule trop long (max 100 caractères)');
        }
        $updateFields[] = 'matricule = :matricule';
        $params[':matricule'] = $matricule;
    }

    if (isset($data['last_name']) && is_string($data['last_name'])) {
        $lastName = trim($data['last_name']);
        if ($lastName === '') {
            apiError(422, 'last_name ne peut pas être vide');
        }
        if (strlen($lastName) > 150) {
            apiError(422, 'last_name trop long (max 150 caractères)');
        }
        $updateFields[] = 'last_name = :last_name';
        $params[':last_name'] = $lastName;
    }

    if (isset($data['first_name']) && is_string($data['first_name'])) {
        $firstName = trim($data['first_name']);
        if ($firstName === '') {
            apiError(422, 'first_name ne peut pas être vide');
        }
        if (strlen($firstName) > 150) {
            apiError(422, 'first_name trop long (max 150 caractères)');
        }
        $updateFields[] = 'first_name = :first_name';
        $params[':first_name'] = $firstName;
    }

    if (isset($data['date_of_birth']) && $data['date_of_birth'] !== '') {
        if (!is_string($data['date_of_birth'])) {
            apiError(422, 'date_of_birth invalide');
        }
        $date = DateTime::createFromFormat('Y-m-d', $data['date_of_birth']);
        if (!$date || $date->format('Y-m-d') !== $data['date_of_birth']) {
            apiError(422, 'date_of_birth invalide (format YYYY-MM-DD requis)');
        }
        $updateFields[] = 'date_of_birth = :date_of_birth';
        $params[':date_of_birth'] = $data['date_of_birth'];
    }

    if (isset($data['sex']) && $data['sex'] !== '') {
        if (!is_string($data['sex'])) {
            apiError(422, 'sex invalide');
        }
        $validSex = ['M', 'F', 'OTHER', 'UNSPECIFIED'];
        if (!in_array($data['sex'], $validSex, true)) {
            apiError(422, 'sex invalide (valeurs acceptées: M, F, OTHER, UNSPECIFIED)');
        }
        $updateFields[] = 'sex = :sex';
        $params[':sex'] = $data['sex'];
    }

    if (isset($data['address']) && is_string($data['address'])) {
        $updateFields[] = 'address = :address';
        $params[':address'] = trim($data['address']);
    }

    if (isset($data['phone']) && is_string($data['phone'])) {
        $phone = trim($data['phone']);
        if (strlen($phone) > 50) {
            apiError(422, 'phone trop long (max 50 caractères)');
        }
        $updateFields[] = 'phone = :phone';
        $params[':phone'] = $phone;
    }

    if (isset($data['status']) && $data['status'] !== '') {
        if (!is_string($data['status'])) {
            apiError(422, 'status invalide');
        }
        $validStatus = ['ACTIVE', 'INACTIVE', 'SUSPENDED'];
        if (!in_array($data['status'], $validStatus, true)) {
            apiError(422, 'status invalide (valeurs acceptées: ACTIVE, INACTIVE, SUSPENDED)');
        }
        $updateFields[] = 'status = :status';
        $params[':status'] = $data['status'];
    }

    if (array_key_exists('profile_data', $data)) {
        $updateFields[] = 'profile_data = CAST(:profile_data AS jsonb)';
        $params[':profile_data'] = json_encode($profileData, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }

    // PATCH requires at least one field to update
    if ($method === 'PATCH' && count($updateFields) === 0 && $newClassId === null && $parents === null) {
        apiError(422, 'Aucun champ à modifier pour PATCH');
    }

    // F-03: le contrôle d'existence est également borné au périmètre
    // serveur afin d'éviter qu'un utilisateur puisse modifier un élève
    // appartenant à une autre classe.
    if ($user['role_name'] === 'PDG') {
        $checkStmt = $pdo->prepare(
            'SELECT id
             FROM students
             WHERE id = :id
             LIMIT 1'
        );
        $checkStmt->execute([':id' => $id]);
    } else {
        $checkStmt = $pdo->prepare(
            'SELECT DISTINCT s.id
             FROM students s
             INNER JOIN enrollments e
                ON e.student_id = s.id
               AND e.status = :enrollment_status
             INNER JOIN teacher_class_subjects tcs
                ON tcs.class_id = e.class_id
               AND tcs.status = :assignment_status
             INNER JOIN user_teachers ut
                ON ut.teacher_id = tcs.teacher_id
               AND ut.user_id = :user_id
             WHERE s.id = :id
             LIMIT 1'
        );
        $checkStmt->execute([
            ':enrollment_status' => 'ACTIVE',
            ':assignment_status' => 'ACTIVE',
            ':user_id' => $user['id'],
            ':id' => $id,
        ]);
    }

    if (!$checkStmt->fetch()) {
        apiError(404, 'Étudiant non trouvé');
    }

    // Check matricule uniqueness if matricule is being updated
    if (isset($params[':matricule'])) {
        $matriculeCheck = $pdo->prepare(
            'SELECT id FROM students WHERE matricule = :matricule AND id != :id LIMIT 1'
        );
        $matriculeCheck->execute([
            ':matricule' => $params[':matricule'],
            ':id' => $id,
        ]);
        if ($matriculeCheck->fetch()) {
            apiError(409, 'Matricule déjà utilisé');
        }
    }

    // Les changements de dossier et d'inscription sont atomiques.
    try {
        $pdo->beginTransaction();

        if ($parents !== null) saveStudentParents($pdo, $id, $parents);

        if ($newClassId !== null) {
            $classStmt = $pdo->prepare("SELECT id FROM classes WHERE id = :class_id AND status = 'ACTIVE' LIMIT 1");
            $classStmt->execute([':class_id' => $newClassId]);
            if (!$classStmt->fetch()) {
                $pdo->rollBack();
                apiError(422, 'La classe sélectionnée est indisponible ou inactive');
            }

            if ($user['role_name'] !== 'PDG') {
                $assignmentStmt = $pdo->prepare(
                    "SELECT 1 FROM teacher_class_subjects tcs
                     INNER JOIN user_teachers ut ON ut.teacher_id = tcs.teacher_id
                     WHERE tcs.class_id = :class_id AND tcs.status = 'ACTIVE' AND ut.user_id = :user_id
                     LIMIT 1"
                );
                $assignmentStmt->execute([':class_id' => $newClassId, ':user_id' => $user['id']]);
                if (!$assignmentStmt->fetch()) {
                    $pdo->rollBack();
                    apiError(403, 'Vous ne pouvez pas inscrire cet élève dans cette classe');
                }
            }

            $enrollmentStmt = $pdo->prepare(
                "SELECT id, class_id, school_year_id FROM enrollments
                 WHERE student_id = :student_id AND status = 'ACTIVE'
                 ORDER BY created_at DESC, id DESC LIMIT 1 FOR UPDATE"
            );
            $enrollmentStmt->execute([':student_id' => $id]);
            $activeEnrollment = $enrollmentStmt->fetch();
            if (!$activeEnrollment) {
                $pdo->rollBack();
                apiError(409, 'Aucune inscription active à corriger pour cet élève');
            }

            if ($activeEnrollment['class_id'] !== $newClassId) {
                // L'ancienne inscription est conservée : notes et présences restent liées
                // à son enrollment_id historique et ne sont jamais déplacées.
                $cancelStmt = $pdo->prepare("UPDATE enrollments SET status = 'CANCELLED', updated_at = NOW() WHERE id = :id");
                $cancelStmt->execute([':id' => $activeEnrollment['id']]);
                $insertEnrollment = $pdo->prepare(
                    "INSERT INTO enrollments (student_id, class_id, school_year_id, status)
                     VALUES (:student_id, :class_id, :school_year_id, 'ACTIVE')"
                );
                $insertEnrollment->execute([
                    ':student_id' => $id,
                    ':class_id' => $newClassId,
                    ':school_year_id' => $activeEnrollment['school_year_id'],
                ]);
            }
        }

        if ($updateFields !== []) {
            $updateFields[] = 'updated_at = NOW()';
            $setClause = implode(', ', $updateFields);
            $stmt = $pdo->prepare(
                "UPDATE students SET $setClause WHERE id = :id
                 RETURNING id, matricule, last_name, first_name, date_of_birth, sex,
                           address, phone, profile_data, status, created_at, updated_at"
            );
            $stmt->execute($params);
            $student = $stmt->fetch();
        } else {
            $studentStmt = $pdo->prepare(
                'SELECT id, matricule, last_name, first_name, date_of_birth, sex,
                        address, phone, profile_data, status, created_at, updated_at
                 FROM students WHERE id = :id'
            );
            $studentStmt->execute([':id' => $id]);
            $student = $studentStmt->fetch();
        }

        $pdo->commit();

        $enrollmentInfo = $pdo->prepare(
            "SELECT e.class_id, e.school_year_id, c.name AS class_name, sy.label AS school_year_label
             FROM enrollments e
             INNER JOIN classes c ON c.id = e.class_id
             INNER JOIN school_years sy ON sy.id = e.school_year_id
             WHERE e.student_id = :student_id AND e.status = 'ACTIVE'
             ORDER BY sy.start_date DESC, e.created_at DESC, e.id DESC LIMIT 1"
        );
        $enrollmentInfo->execute([':student_id' => $id]);
        $activeInfo = $enrollmentInfo->fetch();
        if ($activeInfo) $student = array_merge($student, $activeInfo);

        if (isset($student['profile_data']) && is_string($student['profile_data'])) {
            $decoded = json_decode($student['profile_data'], true);
            $student['profile_data'] = is_array($decoded) ? $decoded : [];
        }
        $responseParents = $pdo->prepare('SELECT p.id,p.first_name,p.last_name,p.ninu,p.phone,p.email,p.address,sp.relationship_type,sp.is_primary FROM student_parents sp INNER JOIN parents p ON p.id=sp.parent_id WHERE sp.student_id=:student_id ORDER BY sp.is_primary DESC,p.last_name,p.first_name');
        $responseParents->execute([':student_id'=>$id]);
        $student['parents'] = $responseParents->fetchAll();

        http_response_code(200);
        echo json_encode(['success' => true, 'student' => $student], JSON_UNESCAPED_UNICODE);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        if (str_contains($e->getMessage(), 'enrollments_one_active_per_student_year')) {
            apiError(409, 'Une inscription active existe déjà pour cet élève et cette année scolaire');
        }
        error_log('Student update failed: ' . $e->getMessage());
        apiError(500, 'Erreur interne du serveur');
    }
}
elseif ($method === 'DELETE') {
    $pdo = getDatabaseConnection();
    requirePermission($pdo, 'eleves.delete');
    requireCsrfToken();

    $id = $_GET['id'] ?? '';
    if (!is_string($id) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $id)) {
        apiError(400, 'Identifiant élève invalide');
    }

    // Ne jamais supprimer implicitement les inscriptions, notes ou historiques.
    $enrollments = $pdo->prepare('SELECT 1 FROM enrollments WHERE student_id = :id LIMIT 1');
    $enrollments->execute([':id' => $id]);
    if ($enrollments->fetchColumn()) {
        apiError(409, 'Suppression impossible : cet élève possède une ou plusieurs inscriptions. Archivez-le ou traitez ses données liées séparément.');
    }

    try {
        $stmt = $pdo->prepare('DELETE FROM students WHERE id = :id RETURNING id');
        $stmt->execute([':id' => $id]);
        if (!$stmt->fetch()) {
            apiError(404, 'Élève introuvable');
        }

        echo json_encode(['success' => true, 'deleted' => true, 'id' => $id], JSON_UNESCAPED_UNICODE);
    } catch (PDOException $e) {
        if ((string) $e->getCode() === '23503') {
            apiError(409, 'Suppression impossible : des données liées existent pour cet élève.');
        }
        error_log('Student delete failed: ' . $e->getMessage());
        apiError(500, 'Erreur interne lors de la suppression de l’élève');
    }
}
else {
    header('Allow: GET, POST, PUT, PATCH, DELETE');
    apiError(405, 'Méthode HTTP non autorisée');
}
