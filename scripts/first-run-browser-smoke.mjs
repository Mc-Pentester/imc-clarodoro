import { chromium } from "playwright";

const baseUrl = (process.env.IMC_BASE_URL || "http://127.0.0.1:18080").replace(/\\/$/, "");
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

  console.log("BROWSER FIRST-RUN FORM: PASS");
  console.log("CLIENT-SIDE 12-CHARACTER MINIMUM: PASS");
  console.log("UNICODE PDG PASSWORD CREATION: PASS");
  console.log("SECOND SETUP REFUSED (HTTP 409): PASS");
} finally {
  await browser.close();
}
