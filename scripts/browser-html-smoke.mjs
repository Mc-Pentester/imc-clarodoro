import { chromium } from "playwright";

const baseUrl = process.env.IMC_BASE_URL || "http://127.0.0.1:8090";
const routes = [
  "index.html",
  "matieres.html",
  "resultats.html",
  "finances.html",
  "personnel.html",
  "annees-scolaires.html",
  "Vacances.html",
  "badge.html",
  "PDG.html",
  "payroll-recovery.html",
];

const visibleCodePatterns = [
  /function\s+chargerPersonnelTableau\s*\(/i,
  /function\s+basculerMotDePasse\s*\(/i,
  /function\s+echapperHTML\s*\(/i,
  /const\s+CLE_ELEVES\b/i,
  /async\s+function\s+[A-Za-z_$][\w$]*\s*\(/i,
];

const visibleMarkdownPatterns = [
  /^#{1,6}\\s+\\S/m,
  /^>\\s+\\S/m,
  /^\\s*```/m,
  /\\*\\*[^*\\n]+\\*\\*/,
  /__[^_\\n]+__/,
  /`[^\\n`]+`/,
  /\\[[^\\]\\n]+\\]\\(https?:\\/\\/[^)]+\\)/i,
];

const browser = await chromium.launch({ headless: true });
const failures = [];

try {
  for (const route of routes) {
    const page = await browser.newPage({ viewport: { width: 1365, height: 900 } });
    const pageErrors = [];
    page.on("pageerror", error => pageErrors.push(error.message));

    try {
      const response = await page.goto(new URL(route, baseUrl).toString(), {
        waitUntil: "domcontentloaded",
        timeout: 30000,
      });
      await page.waitForTimeout(700);

      const view = await page.evaluate(() => {
        const body = document.body;
        const rect = body?.getBoundingClientRect();
        return {
          title: document.title || "",
          text: body?.innerText?.trim() || "",
          width: rect?.width || 0,
          height: rect?.height || 0,
          visibleContent: Boolean(body && [...body.querySelectorAll("h1,h2,form,main,section,button,a,p")].some(el => {
            const style = getComputedStyle(el);
            const r = el.getBoundingClientRect();
            return style.display !== "none" && style.visibility !== "hidden" && r.width > 0 && r.height > 0;
          })),
          url: location.href,
        };
      });

      if (!response) failures.push(`${route}: navigation produced no HTTP response`);
      else if (response.status() >= 500) failures.push(`${route}: HTTP ${response.status()} at ${page.url()}`);
      if (view.width <= 0 || view.height <= 0 || view.text.length < 8 || !view.visibleContent) {
        failures.push(`${route}: page appears blank or has no visible content (title="${view.title}", url=${view.url})`);
      }
      const leaked = visibleCodePatterns.find(pattern => pattern.test(view.text));
      if (leaked) failures.push(`${route}: JavaScript source is visible as page text (${leaked})`);
      const markdownLeak = visibleMarkdownPatterns.find(pattern => pattern.test(view.text));
      if (markdownLeak) failures.push(`${route}: Markdown syntax is visible as page text (${markdownLeak})`);
      if (await page.locator("body pre code").count()) {
        failures.push(`${route}: visible pre/code block detected; inspect for leaked source or Markdown`);
      }
      if (pageErrors.length) failures.push(`${route}: uncaught browser error(s): ${pageErrors.join(" | ")}`);

      if (failures.length === 0 || !failures.some(message => message.startsWith(route + ":"))) {
        console.log(`CHROMIUM RENDER: PASS ${route} -> ${view.url} [${view.title}]`);
      }
    } catch (error) {
      failures.push(`${route}: browser navigation/check failed: ${error.message}`);
    } finally {
      await page.close();
    }
  }
} finally {
  await browser.close();
}

if (failures.length) {
  console.error("\nCHROMIUM RENDER FAILURES:");
  for (const failure of failures) console.error("- " + failure);
  process.exit(1);
}
console.log(`CHROMIUM RENDERING SMOKE TEST: PASS (${routes.length} pages)`);
