import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const pagePath = 'private-pages/whatsapp-send.php';
const page = fs.readFileSync(pagePath, 'utf8');
const scripts = [...page.matchAll(/<script>([\\s\\S]*?)<\\/script>/gi)];
assert.equal(scripts.length, 1, 'Expected exactly one inline script');
const script = scripts[0][1];
new vm.Script(script, { filename: pagePath });

const ids = [...page.matchAll(/\\bid="([^"]+)"/g)].map(match => match[1]);
assert.equal(new Set(ids).size, ids.length, 'Duplicate DOM IDs detected');
for (const match of script.matchAll(/\\$\\('([^']+)'\\)/g)) {
  assert.ok(ids.includes(match[1]), `Missing DOM element referenced by script: ${match[1]}`);
}
assert.ok(page.includes('Meta WhatsApp Business Cloud API'), 'Official Meta Cloud API branding missing');
assert.ok(script.includes("fetch('/api/whatsapp/send.php'"), 'Configuration status endpoint missing');
assert.ok(script.includes("method:'POST'"), 'Real POST send request missing');
assert.ok(script.includes("'X-CSRF-Token':csrf"), 'CSRF header missing on send request');
assert.ok(script.includes('idempotency_key:makeIdempotencyKey()'), 'Idempotency key missing');
assert.ok(script.includes('DEMANDE ACCEPTÉE PAR META'), 'Provider acceptance must be distinguished from delivery');
assert.ok(!/wa\\.me|manual-preparations|window\\.open/.test(script), 'Manual click-to-chat flow must not be used by the real send page');
assert.ok(!/localStorage|sessionStorage/.test(script), 'Message parameters must not be persisted in browser storage');
assert.ok(page.includes('Le jeton d’accès reste exclusivement dans le fichier protégé'), 'Server-only token warning missing');

const api = fs.readFileSync('api/whatsapp/send.php', 'utf8');
assert.ok(api.includes("if (!$configured || !in_array($templateName, $allowedTemplates, true))"), 'Unconfigured or unapproved templates must fail closed');
assert.ok(!api.includes("'mode' => 'simulation'"), 'The real-send endpoint must never report a simulated success');
assert.ok(api.includes("'mode' => 'live'"), 'The endpoint must report live mode');
console.log('PASS WhatsApp real-send smoke: JS syntax, DOM references, Meta Cloud API, CSRF, idempotency, fail-closed configuration, no wa.me simulation');
