import { chromium } from "playwright";

const baseUrl = (process.env.IMC_BASE_URL || "http://127.0.0.1:18080").replace(/\/$/, "");
const password = process.env.CLARODARO_TEST_PDG_PASSWORD;
if (!password) throw new Error("CLARODARO_TEST_PDG_PASSWORD is required.");

const browser = await chromium.launch({ headless: true });
try {
  const context = await browser.newContext();
  const page = await context.newPage();
  const pageErrors = [];
  page.on("pageerror", error => pageErrors.push(error.message));

  const firstResponse = await page.goto(baseUrl + "/setup", { waitUntil: "domcontentloaded", timeout: 30000 });
  if (!firstResponse || firstResponse.status() !== 200) {
    throw new Error("First-run page must return HTTP 200; got " + (firstResponse?.status() ?? "no response"));
  }
  if (!(await page.getByRole("heading", { name: /Bienvenue sur Clarodaro/i }).isVisible())) {
    throw new Error("First-run welcome heading is not visible.");
  }
  const username = page.locator("#username");
  if (await username.inputValue() !== "pdg" || await username.getAttribute("readonly") === null) {
    throw new Error("The initial account must be the fixed, read-only pdg username.");
  }

  await page.locator("#password").fill("court");
  await page.locator("#confirmation").fill("court");
  await page.getByRole("button", { name: "Créer mon compte PDG" }).click();
  if (!(await page.locator("#message").innerText()).includes("12 caractères")) {
    throw new Error("The browser must reject passwords shorter than 12 Unicode characters.");
  }

  await page.locator("#password").fill(password);
  await page.locator("#confirmation").fill(password);
  await page.getByRole("button", { name: "Créer mon compte PDG" }).click();
  await page.getByRole("heading", { name: "Compte PDG créé" }).waitFor({ state: "visible", timeout: 30000 });
  if (!(await page.getByRole("link", { name: /Ouvrir la connexion/i }).isVisible())) {
    throw new Error("Successful setup must provide the login link.");
  }
  if (pageErrors.length) throw new Error("Browser error(s): " + pageErrors.join(" | "));

  const repeatPage = await context.newPage();
  const repeatResponse = await repeatPage.goto(baseUrl + "/setup", { waitUntil: "domcontentloaded", timeout: 30000 });
  if (!repeatResponse || repeatResponse.status() !== 409) {
    throw new Error("A second setup attempt must return HTTP 409; got " + (repeatResponse?.status() ?? "no response"));
  }
  if (!(await repeatPage.getByRole("heading", { name: "Clarodaro est déjà configuré" }).isVisible())) {
    throw new Error("The repeat-setup refusal message is not visible.");
  }

  // Verify the real student-registration workflow after first-run setup.
  const studentsPage = await context.newPage();
  studentsPage.on("pageerror", error => pageErrors.push(error.message));
  await studentsPage.goto(baseUrl + "/eleves.html", { waitUntil: "domcontentloaded", timeout: 30000 });
  await studentsPage.locator("#login").waitFor({ state: "visible", timeout: 15000 });
  // The protected-page login intentionally leaves the username blank
  // (only the dedicated PDG page pre-fills it). Enter the bootstrap account.
  await studentsPage.locator("#username").fill("pdg");
  await studentsPage.locator("#password").fill(password);
  await studentsPage.locator("#login button[type='submit']").click();
  await studentsPage.locator("#studentForm").waitFor({ state: "visible", timeout: 30000 });

  const studentMarker = "BrowserSmoke-" + Date.now();
  await studentsPage.locator("#nom").fill(studentMarker);
  await studentsPage.locator("#prenom").fill("Inscription");
  await studentsPage.locator("#sexe").selectOption("M");
  await studentsPage.locator("#dateNaissance").fill("2015-01-15");
  await studentsPage.locator("#classe").selectOption({ label: "1ère Kind" });
  await studentsPage.locator("#studentForm button[type='submit']").click();

  await studentsPage.locator("#message").getByText(/enregistrées avec succès/i).waitFor({ state: "visible", timeout: 30000 });
  await studentsPage.locator("#studentsTableBody").getByText(studentMarker).waitFor({ state: "visible", timeout: 15000 });

  // Reload proves that the row comes back from PostgreSQL, not only from browser memory.
  await studentsPage.reload({ waitUntil: "domcontentloaded", timeout: 30000 });
  await studentsPage.locator("#studentsTableBody").getByText(studentMarker).waitFor({ state: "visible", timeout: 30000 });

  const row = studentsPage.locator("#studentsTableBody tr").filter({ hasText: studentMarker }).first();
  const cells = await row.locator("td").allTextContents();
  if (cells.length !== 10 || cells[0].trim() !== "1" || !cells[1].includes("—") || !cells[2].includes(studentMarker)) {
    throw new Error("The student list columns are not aligned with the table headings: " + JSON.stringify(cells));
  }

  if (pageErrors.length) throw new Error("Browser error(s): " + pageErrors.join(" | "));

  console.log("BROWSER FIRST-RUN FORM: PASS");
  console.log("CLIENT-SIDE 12-CHARACTER MINIMUM: PASS");
  console.log("UNICODE PDG PASSWORD CREATION: PASS");
  console.log("SECOND SETUP REFUSED (HTTP 409): PASS");
  console.log("STUDENT FORM SAVE: PASS");
  console.log("STUDENT LIST AFTER PAGE RELOAD: PASS");
  console.log("STUDENT TABLE COLUMN ALIGNMENT: PASS");
} finally {
  await browser.close();
}
