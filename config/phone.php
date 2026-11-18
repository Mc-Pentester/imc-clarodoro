<?php
declare(strict_types=1);

/**
 * Normalize a human-entered international phone number to E.164.
 * Only common visual separators are removed; national numbers without a
 * country calling code are deliberately rejected (no guessed country code).
 */
function normalizeE164Phone(string $phone): ?string
{
    $phone = trim($phone);
    if ($phone === '') {
        return null;
    }

    $normalized = preg_replace('/[\s().-]+/u', '', $phone);
    if (!is_string($normalized) || !preg_match('/^\+[1-9][0-9]{7,14}$/', $normalized)) {
        return null;
    }

    return $normalized;
}
