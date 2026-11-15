<?php
declare(strict_types=1);

/**
 * Resolve WhatsApp recipients from server-owned student/parent/staff records.
 * The browser supplies one record ID and a message scope, never phone numbers.
 */
function resolveWhatsAppConsentTargets(
    PDO $pdo,
    string $recipientType,
    string $recipientId,
    string $scope,
    string $purpose
): array {
    if ($recipientType === 'STUDENT') {
        if (!in_array($scope, ['STUDENT_ONLY', 'STUDENT_AND_PARENTS'], true)) {
            apiError(422, 'Portée du message invalide');
        }
        $studentStmt = $pdo->prepare(
            "SELECT id,
                    CASE WHEN date_of_birth IS NOT NULL
                               AND date_of_birth <= (CURRENT_DATE - INTERVAL '18 years')
                         THEN 1 ELSE 0 END AS is_adult
             FROM students
             WHERE id = :id AND status = 'ACTIVE'
             LIMIT 1"
        );
        $studentStmt->execute([':id' => $recipientId]);
        $student = $studentStmt->fetch(PDO::FETCH_ASSOC);
        if (!$student) apiError(404, 'Élève actif introuvable');

        // PostgreSQL integer avoids driver-dependent boolean string conversion.
        $isAdult = (int) $student['is_adult'] === 1;
        $targets = [];

        if ($isAdult && $scope === 'STUDENT_ONLY') {
            $stmt = $pdo->prepare(
                "SELECT id, recipient_type, phone_e164
                 FROM whatsapp_recipient_consents
                 WHERE recipient_type = 'STUDENT' AND student_id = :id
                   AND purpose = :purpose AND status = 'OPTED_IN'"
            );
            $stmt->execute([':id' => $recipientId, ':purpose' => $purpose]);
            return $stmt->fetchAll(PDO::FETCH_ASSOC);
        }

        // Minors always route to responsible adults only. Unknown birth dates
        // are treated conservatively as minors.
        if ($isAdult && $scope === 'STUDENT_AND_PARENTS') {
            $stmt = $pdo->prepare(
                "SELECT id, recipient_type, phone_e164
                 FROM whatsapp_recipient_consents
                 WHERE recipient_type = 'STUDENT' AND student_id = :id
                   AND purpose = :purpose AND status = 'OPTED_IN'"
            );
            $stmt->execute([':id' => $recipientId, ':purpose' => $purpose]);
            $targets = array_merge($targets, $stmt->fetchAll(PDO::FETCH_ASSOC));
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
        return array_merge($targets, $parentsStmt->fetchAll(PDO::FETCH_ASSOC));
    }

    $columns = [
        'PARENT' => 'parent_id',
        'STAFF' => 'staff_id',
        'TEACHER' => 'teacher_id',
    ];
    if (!isset($columns[$recipientType])) {
        apiError(422, 'Type de destinataire non pris en charge');
    }
    $column = $columns[$recipientType];
    $stmt = $pdo->prepare(
        "SELECT id, recipient_type, phone_e164
         FROM whatsapp_recipient_consents
         WHERE recipient_type = :type AND {$column} = :id
           AND purpose = :purpose AND status = 'OPTED_IN'"
    );
    $stmt->execute([
        ':type' => $recipientType,
        ':id' => $recipientId,
        ':purpose' => $purpose,
    ]);
    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}
