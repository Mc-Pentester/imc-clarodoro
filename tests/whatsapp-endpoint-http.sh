#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8099}"
for endpoint in consents.php send.php; do
  if [ "$endpoint" = "consents.php" ]; then
    url="$BASE_URL/api/whatsapp/$endpoint?parent_id=00000000-0000-4000-8000-000000000001"
    method=GET
    body=''
  else
    url="$BASE_URL/api/whatsapp/$endpoint"
    method=POST
    body='{"parent_id":"00000000-0000-4000-8000-000000000001"}'
  fi
  status="$(curl --silent --output /tmp/whatsapp-http.json --write-out '%{http_code}' -X "$method" -H 'Content-Type: application/json' --data "$body" "$url")"
  test "$status" = 401 || { echo "$endpoint expected 401, got $status"; cat /tmp/whatsapp-http.json; exit 1; }
  echo "PASS $endpoint unauthenticated request rejected"
done
