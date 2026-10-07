<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/auth.php';

header('Content-Type: application/json; charset=utf-8');

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $pdo = getDatabaseConnection();
    $user = requirePermission($pdo, 'eleves.read');

    // F-03: le schéma V1 ne relie pas encore users aux enseignants/classes.
    // Tant que ce périmètre serveur n'existe pas, une lecture globale par un
    // utilisateur non-PDG serait une fuite inter-classe. On échoue fermement
    // plutôt que de retourner tous les élèves.
    if ($user['role_name'] === 'PDG') {
        $stmt = $pdo->prepare(
            'SELECT
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
                updated_at
             FROM students
             ORDER BY created_at DESC, id DESC'
        );
    } else {
        // F-03: le périmètre est déterminé exclusivement par la relation
        // serveur users -> teachers -> teacher_class_subjects -> classes
        // -> enrollments -> students. Aucun identifiant de classe fourni
        // par le client n'intervient dans l'autorisation.
        $stmt = $pdo->prepare(
            'SELECT DISTINCT
                s.id,
                s.matricule,
                s.last_name,
                s.first_name,
                s.date_of_birth,
                s.sex,
                s.address,
                s.phone,
                s.status,
                s.created_at,
                s.updated_at
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
             ORDER BY s.created_at DESC, s.id DESC'
        );
        $stmt->bindValue(':enrollment_status', 'ACTIVE');
        $stmt->bindValue(':assignment_status', 'ACTIVE');
        $stmt->bindValue(':user_id', $user['id']);
    }

    $stmt->execute();
    $students = $stmt->fetchAll();
    foreach ($students as &$student) {
        if (isset($student['profile_data']) && is_string($student['profile_data'])) {
            $decoded = json_decode($student['profile_data'], true);
            $student['profile_data'] = is_array($decoded) ? $decoded : [];
        }
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

    // Refuser les champs générés par le serveur
    $forbiddenFields = ['id', 'created_at', 'updated_at'];
    foreach ($forbiddenFields as $field) {
        if (array_key_exists($field, $data)) {
            apiError(422, "Le champ $field ne peut pas être fourni par le client");
        }
    }

    // Refuser les champs inconnus
    $allowedFields = ['matricule', 'last_name', 'first_name', 'date_of_birth', 'sex', 'address', 'phone', 'status', 'profile_data'];
    foreach (array_keys($data) as $field) {
        if (!in_array($field, $allowedFields, true)) {
            apiError(422, "Champ inconnu: $field");
        }
    }

    // Insertion
    try {
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
        if (str_contains($e->getMessage(), 'students_matricule_unique')) {
            apiError(409, 'Matricule déjà utilisé');
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

    // Refuser les champs générés par le serveur
    $forbiddenFields = ['id', 'created_at', 'updated_at'];
    foreach ($forbiddenFields as $field) {
        if (array_key_exists($field, $data)) {
            apiError(422, "Le champ $field ne peut pas être fourni par le client");
        }
    }

    // Refuser les champs inconnus
    $allowedFields = ['matricule', 'last_name', 'first_name', 'date_of_birth', 'sex', 'address', 'phone', 'status', 'profile_data'];
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
    if ($method === 'PATCH' && count($updateFields) === 0) {
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

    // Build UPDATE query
    $updateFields[] = 'updated_at = NOW()';
    $setClause = implode(', ', $updateFields);

    try {
        $stmt = $pdo->prepare(
            "UPDATE students
             SET $setClause
             WHERE id = :id
             RETURNING
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
                updated_at"
        );

        $stmt->execute($params);
        $student = $stmt->fetch();
        if (isset($student['profile_data']) && is_string($student['profile_data'])) {
            $decoded = json_decode($student['profile_data'], true);
            $student['profile_data'] = is_array($decoded) ? $decoded : [];
        }

        http_response_code(200);

        echo json_encode([
            'success' => true,
            'student' => $student,
        ], JSON_UNESCAPED_UNICODE);
    } catch (PDOException $e) {
        apiError(500, 'Erreur interne du serveur');
    }
}
elseif ($method === 'DELETE') {
    header('Allow: GET, POST, PUT, PATCH');
    apiError(405, 'Méthode HTTP non autorisée');
}
else {
    header('Allow: GET, POST, PUT, PATCH');
    apiError(405, 'Méthode HTTP non autorisée');
}
