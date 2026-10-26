import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const path = 'private-pages/whatsapp-send.php';
const page = fs.readFileSync(path, 'utf8');
const scripts = [...page.matchAll(/<script>([\s\S]*?)<\/script>/gi)];
assert.equal(scripts.length, 1, 'Expected exactly one inline script');
const script = scripts[0][1];
new vm.Script(script, { filename: path });

const ids = [...page.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
assert.equal(new Set(ids).size, ids.length, 'Duplicate DOM IDs detected');
for (const match of script.matchAll(/\$\('([^']+)'\)/g)) {
  assert.ok(ids.includes(match[1]), `Missing DOM element referenced by script: ${match[1]}`);
}
assert.ok(script.includes('/api/whatsapp/manual-preparations.php'), 'Final server-side consent/audit endpoint missing');
assert.ok(script.includes("'X-CSRF-Token':csrf"), 'CSRF header missing on preparation request');
assert.ok(script.includes('popup.location.href=\'https://wa.me/'), 'WhatsApp click-to-chat navigation missing');
assert.ok(!/localStorage|sessionStorage/.test(script), 'Message must not be persisted in browser storage');
assert.ok(page.includes('Le message prérempli est placé dans l’URL WhatsApp'), 'Sensitive URL warning missing');
console.log('PASS WhatsApp manual page smoke: JS syntax, DOM references, CSRF, server revalidation, wa.me flow, no browser storage');
