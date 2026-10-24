#!/usr/bin/env bash
set -euo pipefail

CONSENT_ID="$(psql -X -At -v ON_ERROR_STOP=1 -c "
  SELECT id FROM whatsapp_consents
  WHERE parent_id = (SELECT id FROM parents WHERE first_name='Fixture' AND last_name='Runtime' ORDER BY created_at LIMIT 1)
    AND purpose = 'GENERAL'
  LIMIT 1
")"
test -n "$CONSENT_ID"

# Connection A holds the same row lock used by send.php and consents.php.
psql -X -v ON_ERROR_STOP=1 -c "BEGIN; SELECT id FROM whatsapp_consents WHERE id = '$CONSENT_ID' FOR UPDATE; SELECT pg_sleep(3); COMMIT;" >/tmp/whatsapp-lock-holder.log 2>&1 &
HOLDER_PID=$!
cleanup() { kill "$HOLDER_PID" 2>/dev/null || true; wait "$HOLDER_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 0.5

# Connection B must wait for A to release the consent row.
START_NS="$(date +%s%N)"
psql -X -At -v ON_ERROR_STOP=1 -c "SELECT status FROM whatsapp_consents WHERE id = '$CONSENT_ID' FOR UPDATE" >/tmp/whatsapp-lock-contender.log
END_NS="$(date +%s%N)"
ELAPSED_MS="$(( (END_NS - START_NS) / 1000000 ))"
wait "$HOLDER_PID"
if [ "$ELAPSED_MS" -lt 1500 ]; then
  echo "FAIL consent row lock did not serialize concurrent access (${ELAPSED_MS}ms)"
  cat /tmp/whatsapp-lock-holder.log /tmp/whatsapp-lock-contender.log
  exit 1
fi
echo "PASS consent row lock serializes concurrent access (${ELAPSED_MS}ms wait)"
