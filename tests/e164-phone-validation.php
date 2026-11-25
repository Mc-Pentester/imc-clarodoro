<?php
declare(strict_types=1);

require_once __DIR__ . '/../config/phone.php';

$cases = [
    ['+50937000000', '+50937000000'],
    ['+1 (202) 555-0123', '+12025550123'],
    ['+33 6 12 34 56 78', '+33612345678'],
    ['+44-20-7946-0958', '+442079460958'],
    ['50937000000', null],
    ['037000000', null],
    ['+509123', null],
    ['+0123456789', null],
    ['+5093700000000000', null],
    ['+509ABC00000', null],
];

foreach ($cases as [$input, $expected]) {
    $actual = normalizeE164Phone($input);
    if ($actual !== $expected) {
        fwrite(STDERR, sprintf("FAIL %s: expected %s, got %s\\n", $input, var_export($expected, true), var_export($actual, true)));
        exit(1);
    }
}

if (normalizeE164Phone('   ') !== null) {
    fwrite(STDERR, "FAIL empty phone should remain null\\n");
    exit(1);
}

echo "PASS E.164 normalization: Haitian and international numbers, separators, missing country code, invalid lengths and characters\\n";
