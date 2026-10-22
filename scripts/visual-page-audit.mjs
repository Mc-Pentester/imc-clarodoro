import fs from "node:fs";
import path from "node:path";
import { chromium } from "playwright";

const baseUrl = process.env.IMC_BASE_URL || "http://127.0.0.1:8090";
const username = process.env.IMC_VISUAL_USERNAME || "reconcile-runtime";
const password = process.env.IMC_VISUAL_PASSWORD || "Reconcile-Test-2026!";
const outputDir = process.env.IMC_VISUAL_OUTPUT || "artifacts/visual-audit";
const routes = ["index.html", "PDG.html", "finances.html", "personnel.html", "badge.html", "payroll-recovery.html", "resultats.html"];
const visibleCodePatterns = [
  /function\s+chargerPersonnelTableau\s*\(/i,
  /function\s+basculerMotDePasse\s*\(/i,
  /function\s+echapperHTML\s*\(/i,
  /const\s+CLE_ELEVES\b/i,
  /async\s+function\s+[A-Za-z_$][\w$]*\s*\(/i,
  /(?:^|\n)\s*```(?:javascript|js|html|markdown)?\s*(?:\n|$)/i,
];
fs.mkdirSync(outputDir, { recursive: true });
const browser = await chromium.launch({ headless: true });
const results = [];
const failures = [];
try {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 1 });
  const loginResponse = await context.request.post(new URL("/api/auth/login.php", baseUrl).toString(), {
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    data: { username, password },
  });
  let loginBody = {};
  try { loginBody = await loginResponse.json(); } catch {}
  if (!loginResponse.ok() || !loginBody.success || !loginBody.user) {
    throw new Error("Visual audit login failed: HTTP " + loginResponse.status() + " " + JSON.stringify(loginBody));
  }
  for (const route of routes) {
    for (const viewport of [{ name: "desktop", width: 1440, height: 1000 }, { name: "mobile", width: 390, height: 844 }]) {
      const page = await context.newPage();
      await page.setViewportSize({ width: viewport.width, height: viewport.height });
      const pageErrors = [];
      const consoleErrors = [];
      page.on("pageerror", error => pageErrors.push(error.message));
      page.on("console", message => { if (message.type() === "error") consoleErrors.push(message.text()); });
      const screenshotName = path.basename(route, ".html") + "-" + viewport.name + ".png";
      const screenshotPath = path.join(outputDir, screenshotName);
      let responseStatus = null;
      let view = { title: "", text: "", width: 0, height: 0, visibleContent: false, horizontalOverflow: null, url: "" };
      try {
        const response = await page.goto(new URL(route, baseUrl).toString(), { waitUntil: "domcontentloaded", timeout: 30000 });
        responseStatus = response ? response.status() : null;
        await page.waitForTimeout(900);
        view = await page.evaluate(() => {
          const body = document.body;
          const rect = body ? body.getBoundingClientRect() : null;
          const visibleContent = Boolean(body && [...body.querySelectorAll("h1,h2,form,main,section,button,a,p,table")].some(el => {
            const style = getComputedStyle(el);
            const r = el.getBoundingClientRect();
            return style.display !== "none" && style.visibility !== "hidden" && Number(style.opacity) > 0 && r.width > 0 && r.height > 0;
          }));
          return { title: document.title || "", text: body && body.innerText ? body.innerText.trim() : "", width: rect ? rect.width : 0, height: rect ? rect.height : 0, visibleContent, horizontalOverflow: document.documentElement.scrollWidth > document.documentElement.clientWidth + 2, url: location.href };
        });
        await page.screenshot({ path: screenshotPath, fullPage: true, animations: "disabled" });
        const prefix = route + " [" + viewport.name + "]";
        if (!response) failures.push(prefix + ": no HTTP response");
        else if (response.status() >= 500) failures.push(prefix + ": HTTP " + response.status());
        const finalUrl = new URL(view.url);
        const expectedRoute = route.toLowerCase();
        const isExpectedPage = finalUrl.pathname.toLowerCase().endsWith("/" + expectedRoute)
          || (finalUrl.pathname.toLowerCase().endsWith("/secure-page.php") && (finalUrl.searchParams.get("page") || "").toLowerCase() === expectedRoute);
        if (!isExpectedPage) failures.push(prefix + ": unexpected redirect; expected " + route + " or secure-page.php?page=" + route + ", got " + view.url);
        if (view.width <= 0 || view.height <= 0 || view.text.length < 8 || !view.visibleContent) failures.push(prefix + ": blank page or no visible content (title=" + view.title + ", url=" + view.url + ")");
        const leaked = visibleCodePatterns.find(pattern => pattern.test(view.text));
        if (leaked) failures.push(prefix + ": source code appears in visible text (" + leaked + ")");
        if (pageErrors.length) failures.push(prefix + ": uncaught browser errors: " + pageErrors.join(" | "));
        results.push({ route, viewport: viewport.name, width: viewport.width, height: viewport.height, httpStatus: responseStatus, title: view.title, finalUrl: view.url, visibleTextLength: view.text.length, visibleContent: view.visibleContent, horizontalOverflow: view.horizontalOverflow, pageErrors, consoleErrors, screenshot: screenshotName });
        console.log("VISUAL AUDIT: " + (failures.some(f => f.startsWith(prefix + ":")) ? "FAIL " : "PASS ") + prefix + " -> " + view.url);
      } catch (error) {
        failures.push(route + " [" + viewport.name + "]: " + error.message);
        results.push({ route, viewport: viewport.name, error: error.message, pageErrors, consoleErrors, screenshot: screenshotName });
        try { await page.screenshot({ path: screenshotPath, fullPage: true }); } catch {}
      } finally { await page.close(); }
    }
  }
  await context.close();
} finally { await browser.close(); }
fs.writeFileSync(path.join(outputDir, "report.json"), JSON.stringify({ generatedAt: new Date().toISOString(), baseUrl, pagesChecked: routes.length, viewportRuns: results.length, passed: failures.length === 0, results, failures }, null, 2) + "\n");
if (failures.length) { console.error("\nVISUAL AUDIT FAILURES:"); for (const failure of failures) console.error("- " + failure); process.exit(1); }
console.log("AUTHENTICATED VISUAL AUDIT: PASS (" + results.length + " screenshots, desktop + mobile)");
