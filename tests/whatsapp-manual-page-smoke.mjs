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
assert.ok(page.includes('Rechercher un parent par nom, téléphone ou nom de son élève'), 'Parent search by student name missing');
assert.ok(script.includes('parent.student_names'), 'Matching student names must be shown with parent results');
assert.ok(script.includes("fetch(url,{credentials:'same-origin'"), 'Authorized parent search request missing');
assert.ok(script.includes("/api/whatsapp/parents-search.php?purpose="), 'Purpose-scoped parent search endpoint missing');
assert.ok(script.includes("$('parent_id').value=parent.id"), 'Selecting a search result must set the internal parent UUID');
assert.ok(page.includes('Envoyer un message aux parents d’une ou plusieurs classes'), 'Multi-class parent broadcast UI missing');
assert.ok(page.includes('id="broadcastClassOptions"'), 'Multi-class checkbox selector missing');
assert.ok(page.includes('id="studentContextNotice"'), 'Student-linked recipient context missing');
assert.ok(page.includes('Préparer les liens WhatsApp pour la classe'), 'Manual class broadcast action missing');
assert.ok(page.includes('Envoyer la classe via Meta'), 'Meta class broadcast action missing');
assert.ok(page.includes('Contacter les parents et responsables de l’élève'), 'Student-linked communication heading missing');
assert.ok(script.includes("/api/whatsapp/class-recipients.php?class_ids="), 'Consent-filtered multi-class recipient lookup missing');
assert.ok(script.includes("$('broadcastSchoolYear').addEventListener('change'"), 'Changing the school year must invalidate previously loaded recipients');
assert.ok(script.includes('Sélection de classes modifiée'), 'Changing selected classes must invalidate previously loaded recipients');
assert.ok(script.includes("/api/whatsapp/student-recipients.php?student_id="), 'Student-linked responsible lookup missing');
assert.ok(script.includes('parent.eligible!==false'), 'Only individually consented parents may be selected');
assert.ok(script.includes('selectedStudentName'), 'Student context must be displayed after opening from a student record');
assert.ok(script.includes("fetch('/api/whatsapp/manual-preparations.php'"), 'Manual batch must reuse the per-parent audited preparation endpoint');
assert.ok(script.includes("fetch('/api/whatsapp/send.php'"), 'Meta batch must reuse the per-parent protected send endpoint');
assert.ok(script.includes('makeIdempotencyKey()'), 'Each Meta recipient must receive an idempotency key');
assert.ok(script.includes('excluded_without_active_consent'), 'UI must report parents excluded for missing active consent');
assert.ok(script.includes('parent.student_names'), 'Class results must identify linked students');
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

const studentList = fs.readFileSync('private-pages/index.php', 'utf8');
assert.ok(studentList.includes('/whatsapp-send.html?student_id='), 'Student names must open WhatsApp with the selected student ID');
assert.ok(studentList.includes('data-whatsapp-send='), 'WhatsApp student links must be gated by the server-side permission');
assert.ok(studentList.includes('document.body.dataset.whatsappSend === "true"'), 'Users without WhatsApp send permission must not see clickable student names');
assert.ok(studentList.includes('id="filterClass"'), 'Student list class filter missing');
assert.ok(studentList.includes('student.classId !== classFilter'), 'Student list must filter by persisted class ID');

const studentRecipientsApi = fs.readFileSync('api/whatsapp/student-recipients.php', 'utf8');
assert.ok(studentRecipientsApi.includes("requirePermission($pdo, 'whatsapp.message.send')"), 'Student responsible lookup must require WhatsApp permission');
assert.ok(studentRecipientsApi.includes('student_parents'), 'Student responsible lookup must use the persisted student-parent relationship');
assert.ok(studentRecipientsApi.includes("c.status = 'OPTED_IN'"), 'Student responsible lookup must require active consent');

const classRecipientsApi = fs.readFileSync('api/whatsapp/class-recipients.php', 'utf8');
assert.ok(classRecipientsApi.includes('ANY(CAST(:class_ids AS uuid[]))'), 'Multi-class lookup must query all selected class IDs');
assert.ok(classRecipientsApi.includes('count(DISTINCT sp.parent_id)'), 'Multi-class parent count must deduplicate shared parents');
assert.ok(script.includes('length>20'), 'The UI must enforce the API maximum of twenty selected classes');

const parentSearchApi = fs.readFileSync('api/whatsapp/parents-search.php', 'utf8');
assert.ok(parentSearchApi.includes("requirePermission($pdo, 'whatsapp.message.send')"), 'Parent search must require WhatsApp send permission');
assert.ok(parentSearchApi.includes("c.status = 'OPTED_IN'"), 'Parent search must only return active-consent recipients');
assert.ok(parentSearchApi.includes('LEFT JOIN student_parents sp ON sp.parent_id = p.id'), 'Parent search must resolve the existing student-parent relationship');
assert.ok(parentSearchApi.includes('LEFT JOIN students s ON s.id = sp.student_id'), 'Parent search must match the student record');
assert.ok(parentSearchApi.includes('student_full_name_search'), 'Parent search must match a student full name');
assert.ok(parentSearchApi.includes('AS student_names'), 'Search results must identify the matching family students');
assert.ok(parentSearchApi.includes('regexp_replace'), 'Phone search must ignore formatting characters');
assert.ok(parentSearchApi.includes('LIMIT 20'), 'Parent search must cap result count');
const manualApi = fs.readFileSync('api/whatsapp/manual-preparations.php', 'utf8');
assert.ok(manualApi.includes('whatsapp_manual_preparations'), 'Manual preparation audit persistence missing');
assert.ok(manualApi.includes("$consent['status'] !== 'OPTED_IN'"), 'Manual mode must reject inactive consent');
const api = fs.readFileSync('api/whatsapp/send.php', 'utf8');
assert.ok(api.includes("if (!$configured || !in_array($templateName, $allowedTemplates, true))"), 'Unconfigured or unapproved templates must fail closed');
assert.ok(!api.includes("'mode' => 'simulation'"), 'The real-send endpoint must never report a simulated success');
assert.ok(api.includes("'mode' => 'live'"), 'The endpoint must report live mode');
console.log('PASS WhatsApp dual-mode smoke: JS syntax, DOM references, manual wa.me preparation/audit, Meta Cloud API, CSRF, idempotency, fail-closed configuration');
