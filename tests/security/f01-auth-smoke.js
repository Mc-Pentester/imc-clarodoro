/* F-01 smoke test: the real auth.js must load without stubbing it. */
const fs = require("fs");
const vm = require("vm");
const auth = fs.readFileSync("auth.js", "utf8");

const context = {
  console,
  fetch: async () => ({ ok: false, json: async () => ({ success: false }) }),
  sessionStorage: { removeItem() {} },
  location: { href: "" },
  IMCSecureStorage: { lock() {} }
};
context.window = context;

vm.createContext(context);
vm.runInContext(auth, context, { filename: "auth.js" });

if (!context.window.IMCAuth) throw new Error("F-01 FAIL: window.IMCAuth was not created");
const required = ["login","logout","isAuthenticated","currentUser","requireAuth","verifySession","requireRole","hasRole","hasPermission","requirePermission"];
for (const name of required) {
  if (typeof context.window.IMCAuth[name] !== "function") {
    throw new Error("F-01 FAIL: IMCAuth." + name + " is not callable");
  }
}
if (context.window.IMCAuth.getSession !== undefined) {
  throw new Error("F-01 FAIL: obsolete getSession export remains");
}
console.log("F-01 REAL AUTH.JS LOAD: PASS");
console.log("window.IMCAuth created: PASS");
console.log("No undefined getSession reference: PASS");
