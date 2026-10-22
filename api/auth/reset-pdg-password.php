<?php
declare(strict_types=1);

/**
 * La récupération du mot de passe PDG est réservée au script CLI
 * Scripts/RESET-PDG-PASSWORD.php. Cet endpoint HTTP est volontairement
 * neutralisé afin qu'aucun token envoyé par le navigateur ne puisse
 * modifier le mot de passe, même par appel direct à l'API.
 */
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private, max-age=0');
header('Pragma: no-cache');
header('X-Content-Type-Options: nosniff');
header('X-Robots-Tag: noindex, nofollow');
http_response_code(410);
echo json_encode([
    'success' => false,
    'error' => 'La récupération HTTP est désactivée. Contactez l’administrateur système pour une réinitialisation locale via CLI.'
], JSON_UNESCAPED_UNICODE);
exit;
