import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const page = readFileSync('private-pages/whatsapp-multi-send.php', 'utf8');
const router = readFileSync('router.php', 'utf8');
const securePage = readFileSync('secure-page.php', 'utf8');
const menu = readFileSync('js/whatsapp-menu.js', 'utf8');

for (const id of [
  'recipientType', 'recipientSearch', 'recipientResults', 'recipientId',
  'purpose', 'scope', 'consentPhone', 'consentStatus', 'consentEvidence',
  'templateName', 'sendButton', 'refreshHistory'
]) {
  assert.match(page, new RegExp('id="' + id + '"'), 'missing page control: ' + id);
}
for (const endpoint of [
  '/api/whatsapp/recipient-search.php',
  '/api/whatsapp/recipient-consents.php',
  '/api/whatsapp/send-multi.php',
  '/api/whatsapp/recipient-message-history.php'
]) {
  assert.ok(page.includes(endpoint), 'page does not call ' + endpoint);
}
assert.ok(router.includes("'/whatsapp-multi-send.html' => 'whatsapp-multi-send.html'"), 'HTTP router route missing');
assert.ok(securePage.includes("'whatsapp-multi-send.html' => ['public' => 'whatsapp-multi-send.html', 'file' => 'whatsapp-multi-send.php'"), 'secure page mapping missing');
assert.ok(menu.includes('/whatsapp-multi-send.html'), 'menu link missing');
assert.ok(page.includes('crypto.randomUUID()'), 'send must use a fresh idempotency key');
assert.ok(page.includes('Une révocation après réservation'), 'in-flight revocation behavior must be disclosed');
console.log('PASS WhatsApp multi-recipient page, secure route, menu and API wiring');
