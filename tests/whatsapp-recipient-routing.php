<?php
declare(strict_types=1);

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../config/auth.php';
require_once __DIR__ . '/../api/whatsapp/recipient-resolver.php';

$pdo = getDatabaseConnection();
$purpose = 'GENERAL';
$adultId = '00000000-0000-4000-8000-000000009111';
$minorId = '00000000-0000-4000-8000-000000009112';
$unknownDobId = '00000000-0000-4000-8000-000000009113';
$parentIds = [
    '00000000-0000-4000-8000-000000009101',
    '00000000-0000-4000-8000-000000009102',
];

function expectTargets(array $targets, int $expected, string $label): void
{
    if (count($targets) !== $expected) {
        fwrite(STDERR, $label . ': expected ' . $expected . ', got ' . count($targets) . PHP_EOL);
        exit(1);
    }
}

$adultPersonal = resolveWhatsAppConsentTargets($pdo, 'STUDENT', $adultId, 'STUDENT_ONLY', $purpose);
expectTargets($adultPersonal, 1, 'Adult personal message');
if ($adultPersonal[0]['recipient_type'] !== 'STUDENT') {
    throw new RuntimeException('Adult personal message must target the student only');
}

$adultFamily = resolveWhatsAppConsentTargets($pdo, 'STUDENT', $adultId, 'STUDENT_AND_PARENTS', $purpose);
expectTargets($adultFamily, 3, 'Adult family message');
$adultFamilyTypes = array_count_values(array_column($adultFamily, 'recipient_type'));
if (($adultFamilyTypes['STUDENT'] ?? 0) !== 1 || ($adultFamilyTypes['PARENT'] ?? 0) !== 2) {
    throw new RuntimeException('Adult family message must include the student and both consented parents');
}

$minor = resolveWhatsAppConsentTargets($pdo, 'STUDENT', $minorId, 'STUDENT_ONLY', $purpose);
expectTargets($minor, 2, 'Minor message');
if (count(array_filter($minor, static fn(array $row): bool => $row['recipient_type'] !== 'PARENT')) !== 0) {
    throw new RuntimeException('Minor message must never target the student directly');
}

$unknownDob = resolveWhatsAppConsentTargets($pdo, 'STUDENT', $unknownDobId, 'STUDENT_ONLY', $purpose);
expectTargets($unknownDob, 2, 'Unknown birth date');
if (count(array_filter($unknownDob, static fn(array $row): bool => $row['recipient_type'] !== 'PARENT')) !== 0) {
    throw new RuntimeException('Unknown birth date must be treated as minor');
}

$parent = resolveWhatsAppConsentTargets($pdo, 'PARENT', $parentIds[0], 'STUDENT_ONLY', $purpose);
expectTargets($parent, 1, 'Direct parent message');
$staff = resolveWhatsAppConsentTargets($pdo, 'STAFF', '00000000-0000-4000-8000-000000009121', 'STUDENT_ONLY', $purpose);
expectTargets($staff, 1, 'Staff message');
$teacher = resolveWhatsAppConsentTargets($pdo, 'TEACHER', '00000000-0000-4000-8000-000000009122', 'STUDENT_ONLY', $purpose);
expectTargets($teacher, 1, 'Teacher message');

echo "PASS WhatsApp recipient routing: adult personal, adult + all consented parents, minor parent-only, missing DOB parent-only, parent/staff/teacher direct.\n";
