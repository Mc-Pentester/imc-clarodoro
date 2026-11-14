import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const pagePath = 'private-pages/whatsapp-send.php';
const page = fs.readFileSync(pagePath, 'utf8');
const scripts = [...page.matchAll(/<script>([\s\S]*?)<\/script>/gi)];
assert.equal(scripts.length, 1, 'Expected exactly one inline script');
const script = scripts[0][1];
new vm.Script(script, { filename: pagePath });

const ids = [...page.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
assert.equal(new Set(ids).size, ids.length, 'Duplicate DOM IDs detected');
for (const match of script.matchAll(/\$\('([^']+)'\)/g)) {
  assert.ok(ids.includes(match[1]), 'Missing DOM element referenced by script: ' + match[1]);
}
assert.ok(page.includes('Envoyer manuellement'), 'Manual WhatsApp mode missing');
assert.ok(page.includes('Envoyer automatiquement via Meta'), 'Meta Cloud API mode missing');
assert.ok(script.includes("fetch('/api/whatsapp/manual-preparations.php'"), 'Manual server-side consent/audit endpoint missing');
assert.ok(script.includes("fetch('/api/whatsapp/send.php'"), 'Meta configuration/send endpoint missing');
assert.ok(script.includes("'X-CSRF-Token':csrf"), 'CSRF header missing');
assert.ok(script.includes('idempotency_key:makeIdempotencyKey()'), 'Meta idempotency key missing');
assert.ok(script.includes('https://wa.me/'), 'Manual click-to-chat navigation missing');
assert.ok(script.includes('Préparation journalisée'), 'Manual preparation must be clearly distinguished from actual send');
assert.ok(script.includes('DEMANDE ACCEPTÉE PAR META'), 'Provider acceptance must be distinguished from delivery');
assert.ok(!/localStorage|sessionStorage/.test(script), 'Message parameters must not be persisted in browser storage');
assert.ok(page.includes('Le jeton d’accès reste exclusivement dans le fichier protégé'), 'Server-only token warning missing');

const manualApi = fs.readFileSync('api/whatsapp/manual-preparations.php', 'utf8');
assert.ok(manualApi.includes('whatsapp_manual_preparations'), 'Manual preparation audit persistence missing');
assert.ok(manualApi.includes("$consent['status'] !== 'OPTED_IN'"), 'Manual mode must reject inactive consent');
const api = fs.readFileSync('api/whatsapp/send.php', 'utf8');
assert.ok(api.includes("if (!$configured || !in_array($templateName, $allowedTemplates, true))"), 'Unconfigured or unapproved templates must fail closed');
assert.ok(!api.includes("'mode' => 'simulation'"), 'The real-send endpoint must never report a simulated success');
assert.ok(api.includes("'mode' => 'live'"), 'The endpoint must report live mode');
console.log('PASS WhatsApp dual-mode smoke: JS syntax, DOM references, manual wa.me preparation/audit, Meta Cloud API, CSRF, idempotency, fail-closed configuration');
