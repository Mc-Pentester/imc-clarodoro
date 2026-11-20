#!/usr/bin/env bash
set -euo pipefail

CONSENT_ID="$(psql -X -At -v ON_ERROR_STOP=1 -c "
  SELECT id FROM whatsapp_recipient_consents
  WHERE recipient_type='STUDENT'
    AND student_id='00000000-0000-4000-8000-000000009111'
    AND purpose='GENERAL' AND status='OPTED_IN'
  LIMIT 1
")"
ACTOR_ID="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT id FROM users WHERE username='whatsapp-ci-user' LIMIT 1")"
test -n "$CONSENT_ID" && test -n "$ACTOR_ID"

# Claim and commit before the provider call, matching send-multi.php.
psql -X -v ON_ERROR_STOP=1 -v consent="$CONSENT_ID" -v actor="$ACTOR_ID" <<'SQL'
BEGIN;
SELECT id FROM whatsapp_recipient_consents WHERE id=:'consent' AND status='OPTED_IN' FOR UPDATE;
INSERT INTO whatsapp_recipient_message_log
  (consent_id,idempotency_key,purpose,status,template_name,payload_sha256,initiated_by)
VALUES
  (:'consent','whatsapp-send-claim-lock-test-000001','GENERAL','PROCESSING',
   'ci_template',repeat('f',64),:'actor')
ON CONFLICT (idempotency_key) DO NOTHING;
COMMIT;
SQL

# Simulate the provider wait while a second connection revokes consent.
sleep 3 &
NETWORK_SIM_PID=$!
trap 'kill "$NETWORK_SIM_PID" 2>/dev/null || true; wait "$NETWORK_SIM_PID" 2>/dev/null || true' EXIT
START_NS="$(date +%s%N)"
psql -X -v ON_ERROR_STOP=1 -c "
  UPDATE whatsapp_recipient_consents
  SET status='OPTED_OUT', revoked_at=NOW(), updated_at=NOW()
  WHERE id='$CONSENT_ID' AND status='OPTED_IN'
" >/tmp/whatsapp-recipient-revoke.log
END_NS="$(date +%s%N)"
ELAPSED_MS="$(( (END_NS - START_NS) / 1000000 ))"
if [ "$ELAPSED_MS" -gt 1500 ]; then
  echo "FAIL revocation waited $ELAPSED_MS ms while provider request was simulated"
  cat /tmp/whatsapp-recipient-revoke.log
  exit 1
fi
wait "$NETWORK_SIM_PID"
trap - EXIT
echo "PASS revocation is not blocked by simulated provider wait ($ELAPSED_MS ms)"

# Replaying the same idempotency key must not create a second message record.
psql -X -v ON_ERROR_STOP=1 -c "
  INSERT INTO whatsapp_recipient_message_log
    (consent_id,idempotency_key,purpose,status,template_name,payload_sha256,initiated_by)
  VALUES ('$CONSENT_ID','whatsapp-send-claim-lock-test-000001','GENERAL','PROCESSING',
          'ci_template',repeat('0',64),'$ACTOR_ID')
  ON CONFLICT (idempotency_key) DO NOTHING
" >/dev/null
LOG_COUNT="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_recipient_message_log WHERE idempotency_key='whatsapp-send-claim-lock-test-000001'")"
test "$LOG_COUNT" = "1"
echo "PASS duplicate request cannot create a second message claim"

# Static guard: commit the PROCESSING claim before curl_init.
php <<'PHP'
<?php
$source = file_get_contents('api/whatsapp/send-multi.php');
$claim = strpos($source, 'ON CONFLICT (idempotency_key) DO NOTHING RETURNING id');
$curl = strpos($source, '$ch = curl_init($url);');
$commit = $claim === false ? false : strpos($source, '$pdo->commit();', $claim);
if ($claim === false || $commit === false || $curl === false || $commit > $curl) {
    fwrite(STDERR, "FAIL Meta HTTP call is not preceded by a committed idempotency claim\n");
    exit(1);
}
echo "PASS send-multi commits the idempotency claim before network I/O\n";
PHP
