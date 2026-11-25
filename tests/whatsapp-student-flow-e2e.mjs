import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import { chromium } from 'playwright';

const studentId = '00000000-0000-4000-8000-000000009111';
const parents = [
  { parent_id: '00000000-0000-4000-8000-000000009101', first_name: 'Marie', last_name: 'Test', phone_e164: '+50937000101', eligible: true, relationship_type: 'MOTHER', is_primary: true },
  { parent_id: '00000000-0000-4000-8000-000000009102', first_name: 'Jean', last_name: 'Test', phone_e164: '+50937000102', eligible: true, relationship_type: 'GUARDIAN', is_primary: false }
];

const studentListSource = fs.readFileSync('private-pages/index.php', 'utf8');
assert.ok(studentListSource.includes('/whatsapp-send.html?student_id='), 'The real student list must generate a student-specific WhatsApp link.');
assert.ok(studentListSource.includes('data-whatsapp-send='), 'Student WhatsApp links must remain permission-gated.');
assert.ok(studentListSource.includes('document.body.dataset.whatsappSend === "true"'), 'The real student list must hide the WhatsApp link without permission.');

let pageHtml = fs.readFileSync('private-pages/whatsapp-send.php', 'utf8');
pageHtml = pageHtml.replace(/<\?php[\s\S]*?\?>/g, '');
pageHtml = pageHtml.replace('<?= $csrfToken ?>', 'ci-csrf-token');
assert.ok(!pageHtml.includes('<?php') && !pageHtml.includes('<?=') , 'The browser fixture must not contain unrendered PHP.');

const listHtml = `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><title>Élèves — Clarodaro</title></head>
<body data-whatsapp-send="true">
  <h1>Liste des élèves</h1>
  <table><tbody><tr><td><a href="/whatsapp-send.html?student_id=${studentId}" aria-label="Contacter les parents ou responsables de Alex Student">Student</a></td></tr></tbody></table>
</body></html>`;

const server = http.createServer((req, res) => {
  if (req.url?.startsWith('/eleves.html')) {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(listHtml);
    return;
  }
  if (req.url?.startsWith('/whatsapp-send.html')) {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(pageHtml);
    return;
  }
  res.writeHead(404);
  res.end('Not found');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const address = server.address();
const baseUrl = `http://127.0.0.1:${address.port}`;
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  const requests = [];
  await page.route('**/api/whatsapp/**', async route => {
    const request = route.request();
    const url = new URL(request.url());
    const method = request.method();
    if (url.pathname === '/api/whatsapp/class-recipients.php' && method === 'GET') {
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ success: true, school_years: [], classes: [] }) });
      return;
    }
    if (url.pathname === '/api/whatsapp/send.php' && method === 'GET') {
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ success: true, configured: false, templates: [] }) });
      return;
    }
    if (url.pathname === '/api/whatsapp/student-recipients.php' && method === 'GET') {
      assert.equal(url.searchParams.get('student_id'), studentId, 'The selected student ID must reach the server lookup.');
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          student: { first_name: 'Alex', last_name: 'Student', matricule: 'CI-STUDENT-01' },
          parents,
          total_linked_parents: 2,
          eligible_parent_count: 2,
          excluded_without_active_consent: 0
        })
      });
      return;
    }
    if (url.pathname === '/api/whatsapp/manual-preparations.php' && method === 'POST') {
      const body = request.postDataJSON();
      requests.push(body);
      assert.equal(body.purpose, 'ATTENDANCE');
      assert.equal(body.message, 'Réunion des parents vendredi.');
      assert.ok(parents.some(parent => parent.parent_id === body.parent_id), 'Only a linked parent may be prepared.');
      const parent = parents.find(item => item.parent_id === body.parent_id);
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ success: true, phone_e164: parent.phone_e164, preparation_id: 'ci-preparation-' + requests.length })
      });
      return;
    }
    if (url.pathname === '/api/whatsapp/send.php' && method === 'POST') {
      throw new Error('The browser flow must never call the real Meta send endpoint.');
    }
    throw new Error('Unexpected WhatsApp API request: ' + method + ' ' + url.pathname);
  });

  await page.goto(baseUrl + '/eleves.html');
  await page.getByRole('link', { name: /Contacter les parents ou responsables de Alex Student/ }).click();
  await page.waitForURL(url => url.pathname === '/whatsapp-send.html' && url.searchParams.get('student_id') === studentId);

  await page.getByText('Élève sélectionné : Alex Student · Matricule CI-STUDENT-01.').waitFor();
  const recipientCheckboxes = page.locator('[data-class-parent]');
  await recipientCheckboxes.first().waitFor();
  assert.equal(await recipientCheckboxes.count(), 2, 'Both linked responsible adults must be listed.');
  assert.equal(await page.locator('[data-class-parent]:checked').count(), 2, 'Both eligible responsible adults must be selected initially.');

  await page.locator('#manual_message').fill('Réunion des parents vendredi.');
  const prepareButton = page.locator('#manualBatchButton');
  await assert.doesNotReject(() => prepareButton.click());
  await page.getByText('2 lien(s) préparé(s), 0 échec(s). Aucun message n’a été envoyé automatiquement.').waitFor();
  assert.equal(requests.length, 2, 'A separate audited preparation must be requested for each selected responsible adult.');
  assert.deepEqual(new Set(requests.map(item => item.parent_id)), new Set(parents.map(item => item.parent_id)));
  assert.equal(await page.locator('#manualLinks a[href^="https://wa.me/"]').count(), 2, 'The message preparation section must expose two manual WhatsApp links.');
  assert.equal(await page.locator('#manualLinks').isVisible(), true, 'Prepared WhatsApp links must be visible below the message field.');
  assert.equal(requests.some(item => Object.hasOwn(item, 'template_name')), false, 'No Meta template request may be made.');
  console.log('PASS browser E2E: student list link → selected student → multiple linked responsible adults → audited manual preparations');
  console.log('PASS safety: Meta send endpoint was not called; no WhatsApp message was sent by the test.');
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
