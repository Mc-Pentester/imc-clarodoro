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

STUDENT_ID="$(psql -X -q -At -v ON_ERROR_STOP=1 -c "INSERT INTO students (matricule, last_name, first_name) VALUES ('WHATSAPP-SEARCH-STUDENT-001', 'Search', 'Student') RETURNING id")"
psql -X -v ON_ERROR_STOP=1 -v parent="$PARENT_ID" -v student="$STUDENT_ID" <<'SQL'
INSERT INTO student_parents (student_id, parent_id, relationship_type, is_primary)
VALUES (:'student', :'parent', 'MOTHER', TRUE);
SQL

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

CONSENT="{\"parent_id\":\"$PARENT_ID\",\"purpose\":\"GENERAL\",\"phone_e164\":\"+50937000000\",\"status\":\"OPTED_IN\",\"consent_source\":\"PAPER\",\"consent_method\":\"PAPER\",\"evidence_reference\":\"CI signed consent fixture\"}"
SEND="{\"parent_id\":\"$PARENT_ID\",\"purpose\":\"GENERAL\",\"template_name\":\"ci_template\",\"language\":\"fr\",\"idempotency_key\":\"whatsapp-http-key-000001\",\"parameters\":[\"CI\"]}"

call_api no_permission 403 "$DENIED_SID" POST /api/whatsapp/consents.php "$CONSENT" whatsapp-ci-csrf-token
call_api no_csrf 403 "$ALLOWED_SID" POST /api/whatsapp/consents.php "$CONSENT" ''
NO_EVIDENCE="{\"parent_id\":\"$PARENT_ID\",\"purpose\":\"GENERAL\",\"phone_e164\":\"+50937000000\",\"status\":\"OPTED_IN\",\"consent_source\":\"PAPER\",\"consent_method\":\"PAPER\"}"
call_api paper_without_evidence 422 "$ALLOWED_SID" POST /api/whatsapp/consents.php "$NO_EVIDENCE" whatsapp-ci-csrf-token
call_api opt_in 200 "$ALLOWED_SID" POST /api/whatsapp/consents.php "$CONSENT" whatsapp-ci-csrf-token
SEARCH_STATUS="$(curl --silent --show-error --output /tmp/whatsapp-parent-search.json --write-out '%{http_code}' \
  -H "Cookie: IMC_SESSION=$ALLOWED_SID" \
  "http://127.0.0.1:8100/api/whatsapp/parents-search.php?purpose=GENERAL&q=Student%20Search")"
test "$SEARCH_STATUS" = "200"
php -r '
  $d = json_decode(file_get_contents($argv[1]), true);
  $expectedParent = $argv[2];
  if (($d["success"] ?? false) !== true || !is_array($d["parents"] ?? null)) exit(1);
  $matches = array_values(array_filter($d["parents"], static fn($p) => ($p["id"] ?? "") === $expectedParent));
  if (count($matches) !== 1 || !str_contains((string)($matches[0]["student_names"] ?? ""), "Student Search")) exit(1);
' /tmp/whatsapp-parent-search.json "$PARENT_ID"
echo "PASS parent search by linked student full name HTTP 200"
DENIED_SEARCH_STATUS="$(curl --silent --show-error --output /tmp/whatsapp-parent-search-denied.json --write-out '%{http_code}' \
  -H "Cookie: IMC_SESSION=$DENIED_SID" \
  "http://127.0.0.1:8100/api/whatsapp/parents-search.php?purpose=GENERAL&q=Student%20Search")"
test "$DENIED_SEARCH_STATUS" = "403"
echo "PASS parent search permission enforcement HTTP 403"

# Seed one class with two siblings for the same opted-in parent and one
# additional linked parent without consent. The class endpoint must deduplicate
# the first parent and exclude the second one.
LEVEL_ID="$(psql -X -q -At -v ON_ERROR_STOP=1 -c "INSERT INTO levels (code,name) VALUES ('WHATSAPP-CLASS-LVL','WhatsApp class level') RETURNING id")"
CLASS_ID="$(psql -X -q -At -v ON_ERROR_STOP=1 -c "INSERT INTO classes (code,name,level_id,status) VALUES ('WHATSAPP-CLASS-A','WhatsApp test class','$LEVEL_ID','ACTIVE') RETURNING id")"
SCHOOL_YEAR_ID="$(psql -X -q -At -v ON_ERROR_STOP=1 -c "INSERT INTO school_years (label,start_date,end_date,status) VALUES ('WhatsApp CI 2026-2027','2026-09-01','2027-06-30','ACTIVE') RETURNING id")"
SIBLING_ID="$(psql -X -q -At -v ON_ERROR_STOP=1 -c "INSERT INTO students (matricule,last_name,first_name) VALUES ('WHATSAPP-SIBLING-001','Search','Sibling') RETURNING id")"
EXCLUDED_PARENT_ID="$(psql -X -q -At -v ON_ERROR_STOP=1 -c "INSERT INTO parents (last_name,first_name) VALUES ('NoConsent','Parent') RETURNING id")"
EXCLUDED_STUDENT_ID="$(psql -X -q -At -v ON_ERROR_STOP=1 -c "INSERT INTO students (matricule,last_name,first_name) VALUES ('WHATSAPP-NOCONSENT-001','NoConsent','Student') RETURNING id")"
psql -X -v ON_ERROR_STOP=1 -v parent="$PARENT_ID" -v sibling="$SIBLING_ID" -v excluded_parent="$EXCLUDED_PARENT_ID" -v excluded_student="$EXCLUDED_STUDENT_ID" -v class="$CLASS_ID" -v year="$SCHOOL_YEAR_ID" <<'SQL'
INSERT INTO student_parents (student_id,parent_id,relationship_type,is_primary)
VALUES (:'sibling',:'parent','MOTHER',FALSE), (:'excluded_student',:'excluded_parent','FATHER',TRUE);
INSERT INTO enrollments (student_id,class_id,school_year_id,status)
SELECT id, :'class'::uuid, :'year'::uuid, 'ACTIVE'
FROM students
WHERE id IN (:'sibling', :'excluded_student')
UNION ALL
SELECT id, :'class'::uuid, :'year'::uuid, 'ACTIVE'
FROM students
WHERE id = (SELECT id FROM students WHERE matricule='WHATSAPP-SEARCH-STUDENT-001');
SQL
CLASS_STATUS="$(curl --silent --show-error --output /tmp/whatsapp-class-recipients.json --write-out '%{http_code}' \
  -H "Cookie: IMC_SESSION=$ALLOWED_SID" \
  "http://127.0.0.1:8100/api/whatsapp/class-recipients.php?class_id=$CLASS_ID&school_year_id=$SCHOOL_YEAR_ID&purpose=GENERAL")"
test "$CLASS_STATUS" = "200"
php -r '
  $d=json_decode(file_get_contents($argv[1]),true);
  $expectedParent=$argv[2];
  if (($d["success"]??false)!==true || ($d["count"]??-1)!==1 || ($d["total_linked_parents"]??-1)!==2 || ($d["excluded_without_active_consent"]??-1)!==1) exit(1);
  $p=$d["parents"][0]??[];
  if (($p["parent_id"]??"")!==$expectedParent || ($p["student_count"]??-1)!==2) exit(1);
  if (!str_contains((string)($p["student_names"]??""),"Student Search") || !str_contains((string)($p["student_names"]??""),"Sibling Search")) exit(1);
' /tmp/whatsapp-class-recipients.json "$PARENT_ID"
echo "PASS class parent lookup: deduplicates siblings and excludes parents without active consent"
DENIED_CLASS_STATUS="$(curl --silent --show-error --output /tmp/whatsapp-class-recipients-denied.json --write-out '%{http_code}' \
  -H "Cookie: IMC_SESSION=$DENIED_SID" \
  "http://127.0.0.1:8100/api/whatsapp/class-recipients.php?class_id=$CLASS_ID&school_year_id=$SCHOOL_YEAR_ID&purpose=GENERAL")"
test "$DENIED_CLASS_STATUS" = "403"
echo "PASS class recipient permission enforcement HTTP 403"
printf -v CLASS_MANUAL_BODY '{"parent_id":"%s","purpose":"GENERAL","message":"Class broadcast CI preparation"}' "$PARENT_ID"
call_api class_manual_preparation 200 "$ALLOWED_SID" POST /api/whatsapp/manual-preparations.php "$CLASS_MANUAL_BODY" whatsapp-ci-csrf-token
CLASS_MANUAL_AUDIT="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_manual_preparations WHERE parent_id='$PARENT_ID' AND purpose='GENERAL'")"
test "$CLASS_MANUAL_AUDIT" = "1"
echo "PASS class manual preparation is audited without sending a WhatsApp message"

BATCH_CONSENT="{\"parent_id\":\"$PARENT_ID\",\"purposes\":[\"ATTENDANCE\",\"RESULTS_AVAILABLE\"],\"phone_e164\":\"+50937000000\",\"status\":\"OPTED_IN\",\"consent_source\":\"PAPER\",\"consent_method\":\"PAPER\",\"evidence_reference\":\"CI batch signed consent\"}"
call_api paper_batch 200 "$ALLOWED_SID" POST /api/whatsapp/consents.php "$BATCH_CONSENT" whatsapp-ci-csrf-token
BATCH_COUNT="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_consents WHERE parent_id='$PARENT_ID' AND purpose IN ('ATTENDANCE','RESULTS_AVAILABLE') AND status='OPTED_IN'")"
test "$BATCH_COUNT" = "2"
BATCH_AUDIT_COUNT="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_consent_audit WHERE parent_id='$PARENT_ID' AND purpose IN ('ATTENDANCE','RESULTS_AVAILABLE') AND new_status='OPTED_IN'")"
test "$BATCH_AUDIT_COUNT" = "2"
INVALID_BATCH="{\"parent_id\":\"$PARENT_ID\",\"purposes\":[\"GENERAL\",\"NOT_A_PURPOSE\"],\"phone_e164\":\"+50937000000\",\"status\":\"OPTED_IN\",\"consent_source\":\"PAPER\",\"consent_method\":\"PAPER\",\"evidence_reference\":\"CI invalid batch\"}"
call_api invalid_paper_batch 422 "$ALLOWED_SID" POST /api/whatsapp/consents.php "$INVALID_BATCH" whatsapp-ci-csrf-token
INVALID_BATCH_COUNT="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_consents WHERE parent_id='$PARENT_ID' AND purpose='GENERAL' AND status='OPTED_IN'")"
test "$INVALID_BATCH_COUNT" = "1"
call_api send_disabled 503 "$ALLOWED_SID" POST /api/whatsapp/send.php "$SEND" whatsapp-ci-csrf-token
php -r '$d=json_decode(file_get_contents($argv[1]),true); if (($d["success"]??true)!==false || !str_contains((string)($d["error"]??""), "Envoi réel")) exit(1);' /tmp/whatsapp-send_disabled.json
COUNT="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_message_log WHERE idempotency_key='whatsapp-http-key-000001'")"
test "$COUNT" = "0"
REVOKE="{\"parent_id\":\"$PARENT_ID\",\"purpose\":\"GENERAL\",\"phone_e164\":\"+50937000000\",\"status\":\"OPTED_OUT\",\"consent_source\":\"HTTP CI revocation\"}"
CONSENTED_AT_BEFORE="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT consented_at FROM whatsapp_consents WHERE parent_id='$PARENT_ID' AND purpose='GENERAL' AND status='OPTED_IN'")"
test -n "$CONSENTED_AT_BEFORE"
call_api opt_out 200 "$ALLOWED_SID" POST /api/whatsapp/consents.php "$REVOKE" whatsapp-ci-csrf-token
REVOKED_STATE="$(psql -X -At -F '|' -v ON_ERROR_STOP=1 -c "SELECT status, consented_at IS NOT NULL, revoked_at IS NOT NULL, consent_method, consent_source, evidence_reference FROM whatsapp_consents WHERE parent_id='$PARENT_ID' AND purpose='GENERAL'")"
test "$REVOKED_STATE" = "OPTED_OUT|t|t|PAPER|PAPER|CI signed consent fixture"
REVOCATION_AUDIT="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_consent_audit WHERE parent_id='$PARENT_ID' AND purpose='GENERAL' AND previous_status='OPTED_IN' AND new_status='OPTED_OUT' AND consent_method='PAPER' AND evidence_reference='CI signed consent fixture'")"
test "$REVOCATION_AUDIT" = "1"
# Exercise the complete parent email confirmation endpoint with a seeded one-time challenge.
psql -X -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO parents (last_name, first_name, email)
VALUES ('DigitalRuntime', 'Fixture', 'digital-runtime@example.test');
SQL
DIGITAL_PARENT_ID="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT id FROM parents WHERE last_name='DigitalRuntime' AND first_name='Fixture' ORDER BY created_at DESC LIMIT 1")"
DIGITAL_TOKEN="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
DIGITAL_CODE="123456"
DIGITAL_TOKEN_HASH="$(php -r 'echo hash("sha256", $argv[1]);' "$DIGITAL_TOKEN")"
DIGITAL_CODE_HASH="$(php -r 'echo hash("sha256", $argv[1]);' "$DIGITAL_CODE")"
psql -X -v ON_ERROR_STOP=1 -v parent="$DIGITAL_PARENT_ID" -v token_hash="$DIGITAL_TOKEN_HASH" -v code_hash="$DIGITAL_CODE_HASH" -v actor="$USER_ID" <<'SQL'
INSERT INTO whatsapp_consent_email_challenges
(parent_id, email, invitation_token_hash, verification_code_hash, expires_at, initiated_by)
VALUES (:'parent', 'digital-runtime@example.test', :'token_hash', :'code_hash', NOW() + INTERVAL '30 minutes', :'actor');
SQL
DIGITAL_BODY="{\"token\":\"$DIGITAL_TOKEN\",\"code\":\"$DIGITAL_CODE\",\"phone_e164\":\"+50937000001\",\"purposes\":[\"GENERAL\"]}"
call_api digital_parent_confirmation 200 "$ALLOWED_SID" POST /api/whatsapp/consent-public.php "$DIGITAL_BODY" ""
DIGITAL_CONSENT_COUNT="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_consents WHERE parent_id='$DIGITAL_PARENT_ID' AND purpose='GENERAL' AND status='OPTED_IN' AND consent_method='DIGITAL_EMAIL' AND consent_email='digital-runtime@example.test' AND email_verified_at IS NOT NULL")"
test "$DIGITAL_CONSENT_COUNT" = "1"
DIGITAL_AUDIT_COUNT="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_consent_audit WHERE parent_id='$DIGITAL_PARENT_ID' AND purpose='GENERAL' AND actor_type='PARENT_EMAIL' AND new_status='OPTED_IN'")"
test "$DIGITAL_AUDIT_COUNT" = "1"

# A wrong code consumes one attempt; after five attempts the token is no longer usable.
LOCK_TOKEN="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
LOCK_TOKEN_HASH="$(php -r 'echo hash("sha256", $argv[1]);' "$LOCK_TOKEN")"
LOCK_CODE_HASH="$(php -r 'echo hash("sha256", "654321");')"
psql -X -v ON_ERROR_STOP=1 -v parent="$DIGITAL_PARENT_ID" -v token_hash="$LOCK_TOKEN_HASH" -v code_hash="$LOCK_CODE_HASH" -v actor="$USER_ID" <<'SQL'
INSERT INTO whatsapp_consent_email_challenges
(parent_id, email, invitation_token_hash, verification_code_hash, expires_at, initiated_by)
VALUES (:'parent', 'digital-runtime@example.test', :'token_hash', :'code_hash', NOW() + INTERVAL '30 minutes', :'actor');
SQL
BAD_CODE_BODY="{\"token\":\"$LOCK_TOKEN\",\"code\":\"000000\",\"phone_e164\":\"+50937000001\",\"purposes\":[\"PAYMENT_REMINDER\"]}"
for attempt in 1 2 3 4 5; do
  call_api "wrong_email_code_$attempt" 403 "$ALLOWED_SID" POST /api/whatsapp/consent-public.php "$BAD_CODE_BODY" ""
done
call_api exhausted_email_challenge 410 "$ALLOWED_SID" GET "/api/whatsapp/consent-public.php?token=$LOCK_TOKEN" "" ""

EXPIRED_TOKEN="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
EXPIRED_TOKEN_HASH="$(php -r 'echo hash("sha256", $argv[1]);' "$EXPIRED_TOKEN")"
EXPIRED_CODE_HASH="$(php -r 'echo hash("sha256", "111111");')"
psql -X -v ON_ERROR_STOP=1 -v parent="$DIGITAL_PARENT_ID" -v token_hash="$EXPIRED_TOKEN_HASH" -v code_hash="$EXPIRED_CODE_HASH" -v actor="$USER_ID" <<'SQL'
INSERT INTO whatsapp_consent_email_challenges
(parent_id, email, invitation_token_hash, verification_code_hash, expires_at, initiated_by)
VALUES (:'parent', 'digital-runtime@example.test', :'token_hash', :'code_hash', NOW() - INTERVAL '1 minute', :'actor');
SQL
call_api expired_email_challenge 410 "$ALLOWED_SID" GET "/api/whatsapp/consent-public.php?token=$EXPIRED_TOKEN" "" ""

SEND_AGAIN="{\"parent_id\":\"$PARENT_ID\",\"purpose\":\"GENERAL\",\"template_name\":\"ci_template\",\"language\":\"fr\",\"idempotency_key\":\"whatsapp-http-key-000002\",\"parameters\":[\"blocked\"]}"
call_api send_after_opt_out 403 "$ALLOWED_SID" POST /api/whatsapp/send.php "$SEND_AGAIN" whatsapp-ci-csrf-token

# Legacy -> generic and generic -> legacy consent compatibility.
call_api generic_parent_consent_read 200 "$ALLOWED_SID" GET "/api/whatsapp/recipient-consents.php?recipient_type=PARENT&recipient_id=$PARENT_ID" '' ''
php -r '$d=json_decode(file_get_contents("/tmp/whatsapp-generic_parent_consent_read.json"),true); $matches=array_values(array_filter($d["consents"]??[], static fn($x)=>(($x["purpose"]??"")==="GENERAL"))); $c=$matches[0]??[]; if (($d["success"]??false)!==true || ($c["status"]??"")!=="OPTED_OUT" || ($c["consent_method"]??"")!=="PAPER" || ($c["evidence_reference"]??"")!=="CI signed consent fixture" || empty($c["consented_at"]) || empty($c["revoked_at"])) exit(1);'
echo "PASS legacy revocation is mirrored without losing consent evidence or original consent timestamp"

PARENT_NEW_CONSENT="{\"recipient_type\":\"PARENT\",\"recipient_id\":\"$PARENT_ID\",\"purpose\":\"ATTENDANCE\",\"phone_e164\":\"+50937000000\",\"status\":\"OPTED_IN\",\"consent_source\":\"PAPER\",\"consent_method\":\"PAPER\",\"evidence_reference\":\"CI generic signed parent consent\"}"
call_api parent_generic_opt_in 200 "$ALLOWED_SID" POST /api/whatsapp/recipient-consents.php "$PARENT_NEW_CONSENT" whatsapp-ci-csrf-token
call_api parent_legacy_read_after_generic 200 "$ALLOWED_SID" GET "/api/whatsapp/consents.php?parent_id=$PARENT_ID" '' ''
php -r '$d=json_decode(file_get_contents("/tmp/whatsapp-parent_legacy_read_after_generic.json"),true); $found=false; foreach (($d["consents"]??[]) as $c) { if (($c["purpose"]??"")==="ATTENDANCE" && ($c["status"]??"")==="OPTED_IN" && ($c["consent_method"]??"")==="PAPER" && ($c["evidence_reference"]??"") === "CI generic signed parent consent") $found=true; } if (!$found) exit(1);'
echo "PASS generic parent opt-in is mirrored to the legacy consent API with evidence"

PARENT_GENERIC_REVOKE="{\"recipient_type\":\"PARENT\",\"recipient_id\":\"$PARENT_ID\",\"purpose\":\"ATTENDANCE\",\"phone_e164\":\"+50937000000\",\"status\":\"OPTED_OUT\",\"consent_source\":null,\"evidence_reference\":null}"
call_api parent_generic_opt_out 200 "$ALLOWED_SID" POST /api/whatsapp/recipient-consents.php "$PARENT_GENERIC_REVOKE" whatsapp-ci-csrf-token
GENERIC_REVOKED="$(psql -X -At -F '|' -v ON_ERROR_STOP=1 -c "SELECT status, consented_at IS NOT NULL, revoked_at IS NOT NULL, consent_method, evidence_reference FROM whatsapp_recipient_consents WHERE recipient_type='PARENT' AND parent_id='$PARENT_ID' AND purpose='ATTENDANCE'")"
test "$GENERIC_REVOKED" = "OPTED_OUT|t|t|PAPER|CI generic signed parent consent"
LEGACY_REVOKED="$(psql -X -At -F '|' -v ON_ERROR_STOP=1 -c "SELECT status, consented_at IS NOT NULL, revoked_at IS NOT NULL, consent_method, evidence_reference FROM whatsapp_consents WHERE parent_id='$PARENT_ID' AND purpose='ATTENDANCE'")"
test "$LEGACY_REVOKED" = "$GENERIC_REVOKED"
echo "PASS generic revocation preserves paper proof and original consent timestamp in both models"

DIGITAL_GENERIC="$(psql -X -At -F '|' -v ON_ERROR_STOP=1 -c "SELECT status, consent_method, consent_email, email_verified_at IS NOT NULL, consent_text_version FROM whatsapp_recipient_consents WHERE recipient_type='PARENT' AND parent_id='$DIGITAL_PARENT_ID' AND purpose='GENERAL'")"
test "$DIGITAL_GENERIC" = "OPTED_IN|DIGITAL_EMAIL|digital-runtime@example.test|t|2026-11-v1"
DIGITAL_GENERIC_AUDIT="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_recipient_consent_audit WHERE recipient_type='PARENT' AND actor_type='PARENT_EMAIL' AND consent_email='digital-runtime@example.test' AND consent_text_version='2026-11-v1'")"
test "$DIGITAL_GENERIC_AUDIT" = "1"
echo "PASS verified parent email consent and its audit evidence are mirrored to generic recipients"

DIGITAL_REVOKE="{\"parent_id\":\"$DIGITAL_PARENT_ID\",\"purpose\":\"GENERAL\",\"phone_e164\":\"+50937000001\",\"status\":\"OPTED_OUT\",\"consent_source\":null,\"evidence_reference\":null}"
call_api digital_parent_opt_out 200 "$ALLOWED_SID" POST /api/whatsapp/consents.php "$DIGITAL_REVOKE" whatsapp-ci-csrf-token
DIGITAL_REVOKED="$(psql -X -At -F '|' -v ON_ERROR_STOP=1 -c "SELECT status, consent_method, consent_email, email_verified_at IS NOT NULL, consent_text_version, evidence_reference IS NOT NULL, consented_at IS NOT NULL, revoked_at IS NOT NULL FROM whatsapp_recipient_consents WHERE recipient_type='PARENT' AND parent_id='$DIGITAL_PARENT_ID' AND purpose='GENERAL'")"
test "$DIGITAL_REVOKED" = "OPTED_OUT|DIGITAL_EMAIL|digital-runtime@example.test|t|2026-11-v1|t|t|t"
DIGITAL_REVOKE_AUDIT="$(psql -X -At -F '|' -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_recipient_consent_audit WHERE recipient_type='PARENT' AND actor_type='SCHOOL_USER' AND new_status='OPTED_OUT' AND consent_method='DIGITAL_EMAIL' AND consent_email='digital-runtime@example.test' AND consent_text_version='2026-11-v1'")"
test "$DIGITAL_REVOKE_AUDIT" = "1"
LEGACY_DIGITAL_REVOKE_AUDIT="$(psql -X -At -F '|' -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM whatsapp_consent_audit WHERE parent_id='$DIGITAL_PARENT_ID' AND actor_type='SCHOOL_USER' AND new_status='OPTED_OUT' AND consent_method='DIGITAL_EMAIL' AND consent_email='digital-runtime@example.test' AND consent_text_version='2026-11-v1'")"
test "$LEGACY_DIGITAL_REVOKE_AUDIT" = "1"
echo "PASS digital-email proof and verification metadata survive revocation in both consent models and audits"

STUDENT_ID='00000000-0000-4000-8000-000000009111'
STUDENT_CONSENT="{\"recipient_type\":\"STUDENT\",\"recipient_id\":\"$STUDENT_ID\",\"purpose\":\"GENERAL\",\"phone_e164\":\"+50937000111\",\"status\":\"OPTED_IN\",\"consent_source\":\"Signed student form\",\"evidence_reference\":\"CI student consent evidence\"}"
call_api student_opt_in 200 "$ALLOWED_SID" POST /api/whatsapp/recipient-consents.php "$STUDENT_CONSENT" whatsapp-ci-csrf-token
call_api student_consent_read 200 "$ALLOWED_SID" GET "/api/whatsapp/recipient-consents.php?recipient_type=STUDENT&recipient_id=$STUDENT_ID" '' ''
php -r '$d=json_decode(file_get_contents("/tmp/whatsapp-student_consent_read.json"),true); $c=$d["consents"][0]??[]; if (($d["success"]??false)!==true || ($c["status"]??"")!=="OPTED_IN" || ($c["evidence_reference"]??"")!=="CI student consent evidence") exit(1);'
call_api recipient_search 200 "$ALLOWED_SID" GET "/api/whatsapp/recipient-search.php?recipient_type=STUDENT&q=Adult" '' ''
php -r '$d=json_decode(file_get_contents("/tmp/whatsapp-recipient_search.json"),true); if (($d["success"]??false)!==true || count($d["recipients"]??[])<1) exit(1);'
call_api message_history 200 "$ALLOWED_SID" GET /api/whatsapp/recipient-message-history.php '' ''
php -r '$d=json_decode(file_get_contents("/tmp/whatsapp-message_history.json"),true); if (($d["success"]??false)!==true || count($d["messages"]??[])<1) exit(1);'
MULTI_SEND="{\"recipient_type\":\"STUDENT\",\"recipient_id\":\"$STUDENT_ID\",\"scope\":\"STUDENT_ONLY\",\"purpose\":\"GENERAL\",\"template_name\":\"ci_template\",\"language\":\"fr\",\"idempotency_key\":\"whatsapp-multi-http-key-000001\",\"parameters\":[\"CI\"]}"
call_api multi_send_disabled 503 "$ALLOWED_SID" POST /api/whatsapp/send-multi.php "$MULTI_SEND" whatsapp-ci-csrf-token
echo "PASS generic recipient API, search, history and disabled-send safety"
