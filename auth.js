/*
 * IMC-Clarodoro - Module d'authentification central
 *
 * Authentification client pour l'application IMC-Clarodoro.
 *
 * La source de vérité est l'API PHP /api/auth/login.php et la session PHP HttpOnly.
 * Le navigateur ne choisit jamais l'identité ou le rôle.
 * sessionStorage ne contient plus de session d'autorité.
 */
(function () {
  "use strict";

  const SESSION_KEY = "imc_auth_session";
  const pageName = (window.location.pathname.split("/").pop() || "").toLowerCase();
  const VAULT_REQUIRED = pageName === "finances.html";
  let vaultReadyPromise = Promise.resolve(true);
  let vaultFailure = null;
  let serverUser = null;
  let serverSessionReady = false;
  let csrfToken = null;
  const nativeFetch = window.fetch.bind(window);

  function chargerCoffreFinance() {
    if (!VAULT_REQUIRED || window.IMCSecureStorage) return;

    window.IMC_VAULT_REQUIRED = true;
    document.documentElement.dataset.imcVault = "locked";

    const style = document.createElement("style");
    style.id = "imc-vault-page-lock";
    style.textContent = 'html[data-imc-vault="locked"] body > * { visibility: hidden !important; }';
    document.documentElement.appendChild(style);

    vaultReadyPromise = new Promise(function (resolve, reject) {
      const script = document.createElement("script");
      script.src = "secure-storage.js";
      script.async = false;
      script.onload = function () {
        if (!window.IMCSecureStorage || !window.IMCSecureStorage.ready) {
          reject(new Error("Le coffre-fort n'est pas disponible."));
          return;
        }
        window.IMCSecureStorage.ready.then(function () {
          document.documentElement.removeAttribute("data-imc-vault");
          const lockStyle = document.getElementById("imc-vault-page-lock");
          if (lockStyle) lockStyle.remove();
          resolve(true);
        }).catch(reject);
      };
      script.onerror = function () {
        reject(new Error("Impossible de charger le coffre-fort."));
      };
      document.documentElement.appendChild(script);
    }).catch(function (error) {
      vaultFailure = error;
      console.error("Coffre-fort:", error);
      return false;
    });
  }

  chargerCoffreFinance();

  function getCachedUser() { return serverUser ? { ...serverUser } : null; }

  async function login(credentials) {
    if (!credentials || typeof credentials !== "object") throw new Error("Identifiants invalides");
    const response = await fetch("/api/auth/login.php", { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ username: String(credentials.username || credentials.identifiant || ""), password: String(credentials.password || credentials.motDePasse || "") }) });
    let payload = null;
    try { payload = await response.json(); } catch (error) {}
    if (!response.ok || !payload || !payload.success || !payload.user) {
      serverUser = null; csrfToken = null; serverSessionReady = true;
      throw new Error((payload && payload.message) || "Identifiant ou mot de passe incorrect.");
    }
    csrfToken = payload.csrfToken ? String(payload.csrfToken) : null;
    serverUser = { userId: String(payload.user.id), username: String(payload.user.username), role: String(payload.user.role) };
    serverSessionReady = true;
    sessionStorage.removeItem(SESSION_KEY);
    return getCachedUser();
  }

  async function verifySession() {
    if (VAULT_REQUIRED) {
      const vaultReady = await vaultReadyPromise;
      if (!vaultReady || vaultFailure) {
        serverUser = null;
        csrfToken = null;
        serverSessionReady = true;
        return null;
      }
    }

    try {
      const response = await fetch("/api/auth/me.php", { method: "GET", credentials: "same-origin", cache: "no-store", headers: { "Accept": "application/json" } });
      const payload = await response.json();
      if (!response.ok || !payload || !payload.success || !payload.user) { serverUser = null; csrfToken = null; serverSessionReady = true; return null; }
      serverUser = { userId: String(payload.user.id), username: String(payload.user.username), role: String(payload.user.role) };
      csrfToken = payload.csrfToken ? String(payload.csrfToken) : null;
      serverSessionReady = true;
      sessionStorage.removeItem(SESSION_KEY);
      return getCachedUser();
    } catch (error) { serverUser = null; csrfToken = null; serverSessionReady = true; return null; }
  }

  async function logout() {
    try { await fetch("/api/auth/logout.php", { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: "{}" }); }
    catch (error) { console.error("Erreur lors de la déconnexion serveur:", error); }
    serverUser = null; csrfToken = null; serverSessionReady = true;
    sessionStorage.removeItem(SESSION_KEY);
    if (window.IMCSecureStorage && typeof window.IMCSecureStorage.lock === "function") { try { window.IMCSecureStorage.lock(); } catch (error) { console.error("Erreur lors du verrouillage du coffre:", error); } }
  }

  window.fetch = function (input, init) {
    const request = new Request(input, init || {});
    const method = request.method.toUpperCase();
    const sameOrigin = request.url.startsWith(window.location.origin);
    const mutation = !['GET', 'HEAD', 'OPTIONS'].includes(method);
    if (sameOrigin && mutation && csrfToken) {
      const headers = new Headers(request.headers);
      headers.set('X-CSRF-Token', csrfToken);
      return nativeFetch(new Request(request, { headers }));
    }
    return nativeFetch(request);
  };

  function isAuthenticated() { return serverSessionReady && serverUser !== null; }
  function currentUser() { return getCachedUser(); }
  function requireAuth(loginPageUrl) { if (isAuthenticated()) return true; window.location.href = loginPageUrl || "index.html"; return false; }
  function requireRole(requiredRole) { const user = currentUser(); return !!user && String(user.role).toUpperCase() === String(requiredRole).toUpperCase(); }
  function hasRole(requiredRole) { return requireRole(requiredRole); }

  const PERMISSION_MATRIX = {
    PDG: {
      personnel: ["read", "create", "update", "delete"],
      eleves: ["read", "create", "update", "delete"],
      annees: ["read", "create", "update", "delete"],
      matieres: ["read", "create", "update", "delete"],
      resultats: ["read", "create", "update"],
      finances: ["read", "create", "update", "delete"],
      vacances: ["read", "create", "update", "delete"],
      badge: ["read", "create", "print"],
      paies: ["read", "create", "update", "reconcile"],
      depenses: ["read", "create", "delete"],
      presences: ["read", "create", "update"],
      vault: ["update"]
    },
    Directeur: {
      personnel: ["read"], eleves: ["read", "create", "update"], annees: ["read"], matieres: ["read"], resultats: ["read", "create", "update"], finances: ["read"], vacances: ["read"], badge: ["read", "print"], paies: [], depenses: [], presences: ["read", "create", "update"], vault: []
    },
    Enseignant: {
      personnel: [], eleves: ["read"], annees: ["read"], matieres: ["read"], resultats: ["read", "create", "update"], finances: [], vacances: ["read"], badge: [], paies: [], depenses: [], presences: ["read", "create", "update"], vault: []
    },
    Secrétaire: {
      personnel: ["read"], eleves: ["read", "create", "update"], annees: ["read"], matieres: ["read"], resultats: [], finances: ["read"], vacances: ["read"], badge: ["read", "print"], paies: [], depenses: [], presences: ["read", "create", "update"], vault: []
    },
    Surveillant: {
      personnel: [], eleves: ["read"], annees: ["read"], matieres: ["read"], resultats: [], finances: [], vacances: ["read"], badge: [], paies: [], depenses: [], presences: ["read", "create", "update"], vault: []
    },
    Autre: {
      personnel: [], eleves: [], annees: ["read"], matieres: ["read"], resultats: [], finances: [], vacances: ["read"], badge: [], paies: [], depenses: [], presences: [], vault: []
    }
  };

  function hasPermission(permission) {
    const user = currentUser();
    if (!user) return false;
    const parts = permission.split(".");
    if (parts.length !== 2) { console.warn("Format de permission invalide:", permission); return false; }
    const rolePermissions = PERMISSION_MATRIX[user.role];
    if (!rolePermissions) { console.warn("Rôle non reconnu:", user.role); return false; }
    const resourcePermissions = rolePermissions[parts[0]];
    if (!resourcePermissions) return false;
    return resourcePermissions.includes(parts[1]);
  }

  function requirePermission(permission) {
    if (!isAuthenticated()) { console.warn("Permission refusée: utilisateur non authentifié"); return false; }
    if (!hasPermission(permission)) { console.warn("Permission refusée:", permission); return false; }
    return true;
  }

  window.IMCAuth = Object.freeze({ login, logout, isAuthenticated, currentUser, requireAuth, verifySession, refresh: function () { return false; }, isSessionExpired: function () { return !isAuthenticated(); }, requireRole, hasRole, hasPermission, requirePermission });
})();