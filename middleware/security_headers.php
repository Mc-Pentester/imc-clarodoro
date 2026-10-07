<?php
declare(strict_types=1);

/**
 * Baseline security headers for browser-consumed API responses.
 */
function sendApiSecurityHeaders(): void
{
    header("X-Content-Type-Options: nosniff");
    header("Content-Security-Policy: frame-ancestors 'none'");
    header("X-Frame-Options: DENY");
    header("Referrer-Policy: no-referrer");
    header("Cache-Control: no-store");
    header("Permissions-Policy: camera=(), microphone=(), geolocation=()");
}
