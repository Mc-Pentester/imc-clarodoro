#!/usr/bin/env bash
set -euo pipefail

SESSIONS=/tmp/whatsapp-http-sessions
mkdir -p "$SESSIONS"
chmod 700 "$SESSIONS"

psql -X -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO roles (name, description)
VALUES ('WhatsApp HTTP Denied', 'HTTP test role without WhatsApp permissions')
ON CONFLICT (name) DO NOTHING;

INSERT INTO users (username, password_hash, role_id)
SELECT 'whatsapp-http-denied', 'not-a-real-login', id
FROM roles WHERE name = 'WhatsApp HTTP Denied'
ON CONFLICT (username) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.name = 'WhatsApp CI'
  AND p.name IN ('whatsapp.consent.read', 'whatsapp.consent.manage', 'whatsapp.message.send', 'whatsapp.recipient.read', 'whatsapp.recipient.manage', 'whatsapp.message.audit')
ON CONFLICT DO NOTHING;
SQL

USER_ID="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT id FROM users WHERE username='whatsapp-ci-user'")"
DENIED_ID="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT id FROM users WHERE username='whatsapp-http-denied'")"
PARENT_ID="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT id FROM parents WHERE last_name='Runtime' AND first_name='Fixture' ORDER BY created_at LIMIT 1")"
test -n "$USER_ID" && test -n "$DENIED_ID" && test -n "$PARENT_ID"

make_session() {
  php -d session.save_path="$SESSIONS" -r '
    session_name("IMC_SESSION");
    session_id($argv[1]);
    session_start();
    $_SESSION["user_id"] = $argv[2];
    $_SESSION["authenticated_at"] = time();
    $_SESSION["last_activity_at"] = time();
    $_SESSION["csrf_token"] = "whatsapp-ci-csrf-token";
    session_write_close();
  ' "$1" "$2"
}

ALLOWED_SID=aa11223344556677889900aabbccddee
DENIED_SID=bb11223344556677889900aabbccddee
make_session "$ALLOWED_SID" "$USER_ID"
make_session "$DENIED_SID" "$DENIED_ID"

php -d session.save_path="$SESSIONS" -S 127.0.0.1:8100 -t . >/tmp/whatsapp-http-auth.log 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
for i in $(seq 1 30); do
  curl --silent http://127.0.0.1:8100/api/auth/me.php >/dev/null && break
  sleep 1
done

call_api() {
  local name="$1" expected="$2" sid="$3" method="$4" path="$5" body="$6" csrf="$7"
  local headers=()
  if [ -n "$csrf" ]; then headers+=( -H "X-CSRF-Token: $csrf" ); fi
  local status
  status="$(curl --silent --show-error --output "/tmp/whatsapp-$name.json" --write-out '%{http_code}' \
    -X "$method" -H 'Content-Type: application/json' -H "Cookie: IMC_SESSION=$sid" \
    "${headers[@]}" --data "$body" "http://127.0.0.1:8100$path")"
  if [ "$status" != "$expected" ]; then
    echo "FAIL $name: expected $expected got $status"
    cat "/tmp/whatsapp-$name.json"
    cat /tmp/whatsapp-http-auth.log
    exit 1
  fi
  echo "PASS $name HTTP $status"
}

CONSENT="{\"parent_id\":\"$PARENT_ID\",\"purpose\":\"GENERAL\",\"phone_e164\":\"+50937000000\",\"status\":\"OPTED_IN\",\"consent_source\":\"HTTP CI\"}"
SEND="{\"parent_id\":\"$PARENT_ID\",\"purpose\":\"GENERAL\",\"template_name\":\"ci_template\",\"language\":\"fr\",\"idempotency_key\":\"whatsapp-http-key-000001\",\"parameters\":[\"CI\"]}"

call_api no_permission 403 "$DENIED_SID" POST /api/whatsapp/consents.php "$CONSENT" whatsapp-ci-csrf-token
call_api no_csrf 403 "$ALLOWED_SID" POST /api/whatsapp/consents.php "$CONSENT" ''
call_api opt_in 200 "$ALLOWED_SID" POST /api/whatsapp/consents.php "$CONSENT" whatsapp-ci-csrf-token
call_api send_disabled 503 "$ALLOWED_SID" POST /api/whatsapp/send.php "$SEND" whatsapp-ci-csrf-token
php -r '$d=json_decode(file_get_contents($argv[1]),true); if (($d["success"]??true)!==false || !str_contains((string)($d["error"]??""), "Envoi réel")) exit(1);' /tmp/whatsapp-send_disabled.json
COUNT="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_message_log WHERE idempotency_key='whatsapp-http-key-000001'")"
test "$COUNT" = "0"
REVOKE="{\"parent_id\":\"$PARENT_ID\",\"purpose\":\"GENERAL\",\"phone_e164\":\"+50937000000\",\"status\":\"OPTED_OUT\",\"consent_source\":\"HTTP CI revocation\"}"
call_api opt_out 200 "$ALLOWED_SID" POST /api/whatsapp/consents.php "$REVOKE" whatsapp-ci-csrf-token
SEND_AGAIN="{\"parent_id\":\"$PARENT_ID\",\"purpose\":\"GENERAL\",\"template_name\":\"ci_template\",\"language\":\"fr\",\"idempotency_key\":\"whatsapp-http-key-000002\",\"parameters\":[\"blocked\"]}"
call_api send_after_opt_out 403 "$ALLOWED_SID" POST /api/whatsapp/send.php "$SEND_AGAIN" whatsapp-ci-csrf-token

# Legacy parent consent changes must be mirrored into the generic recipient model.
call_api generic_parent_consent_read 200 "$ALLOWED_SID" GET "/api/whatsapp/recipient-consents.php?recipient_type=PARENT&recipient_id=$PARENT_ID" '' ''
php -r '$d=json_decode(file_get_contents("/tmp/whatsapp-generic_parent_consent_read.json"),true); if (($d["success"]??false)!==true || count($d["consents"]??[])!==1 || ($d["consents"][0]["status"]??"")!=="OPTED_OUT") exit(1);'

PARENT_NEW_CONSENT="{\\"recipient_type\\":\\"PARENT\\",\\"recipient_id\\":\\"$PARENT_ID\\",\\"purpose\\":\\"ATTENDANCE\\",\\"phone_e164\\":\\"+50937000000\\",\\"status\\":\\"OPTED_IN\\",\\"consent_source\\":\\"New generic consent API CI\\"}"
call_api parent_generic_opt_in 200 "$ALLOWED_SID" POST /api/whatsapp/recipient-consents.php "$PARENT_NEW_CONSENT" whatsapp-ci-csrf-token
call_api parent_legacy_read_after_generic 200 "$ALLOWED_SID" GET "/api/whatsapp/consents.php?parent_id=$PARENT_ID" '' ''
php -r '$d=json_decode(file_get_contents("/tmp/whatsapp-parent_legacy_read_after_generic.json"),true); $found=false; foreach (($d["consents"]??[]) as $x) { if (($x["purpose"]??"")==="ATTENDANCE" && ($x["status"]??"")==="OPTED_IN") $found=true; } if (!$found) exit(1);'

STUDENT_ID='00000000-0000-4000-8000-000000009111'
STUDENT_CONSENT="{\"recipient_type\":\"STUDENT\",\"recipient_id\":\"$STUDENT_ID\",\"purpose\":\"GENERAL\",\"phone_e164\":\"+50937000111\",\"status\":\"OPTED_IN\",\"consent_source\":\"HTTP CI student consent\"}"
call_api student_opt_in 200 "$ALLOWED_SID" POST /api/whatsapp/recipient-consents.php "$STUDENT_CONSENT" whatsapp-ci-csrf-token
call_api student_consent_read 200 "$ALLOWED_SID" GET "/api/whatsapp/recipient-consents.php?recipient_type=STUDENT&recipient_id=$STUDENT_ID" '' ''
php -r '$d=json_decode(file_get_contents("/tmp/whatsapp-student_consent_read.json"),true); if (($d["success"]??false)!==true || count($d["consents"]??[])!==1 || ($d["consents"][0]["status"]??"")!=="OPTED_IN") exit(1);'

call_api recipient_search 200 "$ALLOWED_SID" GET "/api/whatsapp/recipient-search.php?recipient_type=STUDENT&q=Adult" '' ''
php -r '$d=json_decode(file_get_contents("/tmp/whatsapp-recipient_search.json"),true); if (($d["success"]??false)!==true || count($d["recipients"]??[])<1) exit(1);'

call_api message_history 200 "$ALLOWED_SID" GET /api/whatsapp/recipient-message-history.php '' ''
php -r '$d=json_decode(file_get_contents("/tmp/whatsapp-message_history.json"),true); if (($d["success"]??false)!==true || count($d["messages"]??[])<1) exit(1);'

MULTI_SEND="{\"recipient_type\":\"STUDENT\",\"recipient_id\":\"$STUDENT_ID\",\"scope\":\"STUDENT_ONLY\",\"purpose\":\"GENERAL\",\"template_name\":\"ci_template\",\"language\":\"fr\",\"idempotency_key\":\"whatsapp-multi-http-key-000001\",\"parameters\":[\"CI\"]}"
call_api multi_send_disabled 503 "$ALLOWED_SID" POST /api/whatsapp/send-multi.php "$MULTI_SEND" whatsapp-ci-csrf-token
echo 'WHATSAPP MULTI-RECIPIENT AUTHENTICATED HTTP LIFECYCLE: PASS'
