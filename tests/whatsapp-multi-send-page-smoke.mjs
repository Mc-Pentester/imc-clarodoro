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
const menuButtonCreation = menu.split("menu.appendChild(button)").length - 1;
assert.equal(menuButtonCreation, 1, 'The navigation menu must expose exactly one WhatsApp communication entry.');
assert.ok(menu.includes('button.textContent = "Communication WhatsApp"'), 'The single menu entry must be named Communication WhatsApp.');
assert.ok(menu.includes('window.location.href = "/whatsapp-send.html"'), 'The communication menu entry must open the main module.');
assert.ok(menu.includes('imcWhatsappTools'), 'The main communication module must expose its internal tools navigation.');
assert.ok(menu.includes('/whatsapp-multi-send.html'), 'Multi-recipient communication must remain accessible inside the module.');
assert.ok(menu.includes('/whatsapp-consent-management.html'), 'Consent management must remain accessible inside the module.');
assert.ok(!menu.includes('menu.appendChild(multiButton)') && !menu.includes('menu.appendChild(consentButton)'), 'Secondary WhatsApp features must not create additional navigation menu buttons.');
assert.ok(page.includes('crypto.randomUUID()'), 'send must use a fresh idempotency key');
assert.ok(page.includes('Une révocation après réservation'), 'in-flight revocation behavior must be disclosed');
console.log('PASS WhatsApp multi-recipient page, secure route, menu and API wiring');
