#!/usr/bin/env bash
set -euo pipefail

: "${WHATSAPP_APP_SECRET:?Missing webhook app secret}"
: "${WHATSAPP_WEBHOOK_VERIFY_TOKEN:?Missing webhook verification token}"

php -S 127.0.0.1:8111 -t . > /tmp/whatsapp-webhook-server.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

for attempt in $(seq 1 30); do
  if curl --silent --output /dev/null http://127.0.0.1:8111/api/whatsapp/webhook.php; then
    break
  fi
  sleep 1
done

challenge="$(curl --silent --show-error --fail "http://127.0.0.1:8111/api/whatsapp/webhook.php?hub.mode=subscribe&hub.verify_token=${WHATSAPP_WEBHOOK_VERIFY_TOKEN}&hub.challenge=clarodaro-webhook-ci")"
test "$challenge" = "clarodaro-webhook-ci"

bad_verify_status="$(curl --silent --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:8111/api/whatsapp/webhook.php?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=bad")"
test "$bad_verify_status" = "403"

delivered='{"entry":[{"changes":[{"value":{"statuses":[{"id":"wamid.whatsapp-ci-test","status":"delivered","timestamp":"1800000000"}]}}]}]}'
bad_signature_status="$(curl --silent --output /dev/null --write-out '%{http_code}' -X POST \
  -H 'Content-Type: application/json' -H 'X-Hub-Signature-256: sha256=invalid' \
  --data "$delivered" http://127.0.0.1:8111/api/whatsapp/webhook.php)"
test "$bad_signature_status" = "403"

sign_and_post() {
  local body="$1"
  local digest signature response
  digest="$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$WHATSAPP_APP_SECRET" -binary | xxd -p -c 256)"
  signature="sha256=$digest"
  response="$(curl --silent --show-error --fail -X POST \
    -H 'Content-Type: application/json' -H "X-Hub-Signature-256: $signature" \
    --data "$body" http://127.0.0.1:8111/api/whatsapp/webhook.php)"
  printf '%s' "$response"
}

delivered_response="$(sign_and_post "$delivered")"
php -r '$d=json_decode($argv[1],true); if (($d["success"]??false)!==true || ($d["processed"]??0)!==1) exit(1);' "$delivered_response"

read_event='{"entry":[{"changes":[{"value":{"statuses":[{"id":"wamid.whatsapp-ci-test","status":"read","timestamp":"1800000001"}]}}]}]}'
read_response="$(sign_and_post "$read_event")"
php -r '$d=json_decode($argv[1],true); if (($d["success"]??false)!==true || ($d["processed"]??0)!==1) exit(1);' "$read_response"

duplicate_response="$(sign_and_post "$read_event")"
php -r '$d=json_decode($argv[1],true); if (($d["success"]??false)!==true || ($d["processed"]??-1)!==0) exit(1);' "$duplicate_response"

final_status="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT status FROM whatsapp_recipient_message_log WHERE provider_message_id='wamid.whatsapp-ci-test'")"
event_count="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_webhook_events WHERE provider_message_id='wamid.whatsapp-ci-test'")"
test "$final_status" = "READ"
test "$event_count" = "2"

psql -X -v ON_ERROR_STOP=1 <<'SQL'
DO $webhook_audit$
BEGIN
  BEGIN
    UPDATE whatsapp_webhook_events SET provider_status='SENT'
    WHERE provider_message_id='wamid.whatsapp-ci-test';
    RAISE EXCEPTION 'Webhook event UPDATE unexpectedly succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'Webhook event UPDATE unexpectedly succeeded' THEN RAISE; END IF;
  END;
END
$webhook_audit$;
SQL

echo "PASS Meta webhook verification, HMAC signature, deduplication, DELIVERED -> READ lifecycle and append-only audit"
