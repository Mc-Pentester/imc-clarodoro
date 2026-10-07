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
  let serverUser = null;
  let serverSessionReady = false;

  function getCachedUser() {
    return serverUser ? { ...serverUser } : null;
  }

  async function login(credentials) {
    if (!credentials || typeof credentials !== "object") throw new Error("Identifiants invalides");
    const response = await fetch("/api/auth/login.php", {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        username: String(credentials.username || credentials.identifiant || ""),
        password: String(credentials.password || credentials.motDePasse || "")
      })
    });
    let payload = null;
    try { payload = await response.json(); } catch (error) {}
    if (!response.ok || !payload || !payload.success || !payload.user) {
      serverUser = null; serverSessionReady = true;
      throw new Error((payload && payload.message) || "Identifiant ou mot de passe incorrect.");
    }
    serverUser = { userId: String(payload.user.id), username: String(payload.user.username), role: String(payload.user.role) };
    serverSessionReady = true;
    sessionStorage.removeItem(SESSION_KEY);
    return getCachedUser();
  }

  async function verifySession() {
    try {
      const response = await fetch("/api/auth/me.php", { method: "GET", credentials: "same-origin", cache: "no-store", headers: { "Accept": "application/json" } });
      const payload = await response.json();
      if (!response.ok || !payload || !payload.success || !payload.user) { serverUser = null; serverSessionReady = true; return null; }
      serverUser = { userId: String(payload.user.id), username: String(payload.user.username), role: String(payload.user.role) };
      serverSessionReady = true;
      sessionStorage.removeItem(SESSION_KEY);
      return getCachedUser();
    } catch (error) { serverUser = null; serverSessionReady = true; return null; }
  }

  async function logout() {
    try { await fetch("/api/auth/logout.php", { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: "{}" }); }
    catch (error) { console.error("Erreur lors de la déconnexion serveur:", error); }
    serverUser = null; serverSessionReady = true;
    sessionStorage.removeItem(SESSION_KEY);
    if (window.IMCSecureStorage && typeof window.IMCSecureStorage.lock === "function") {
      try { window.IMCSecureStorage.lock(); } catch (error) { console.error("Erreur lors du verrouillage du coffre:", error); }
    }
  }

  function isAuthenticated() { return serverSessionReady && serverUser !== null; }
  function currentUser() { return getCachedUser(); }

  function requireAuth(loginPageUrl) {
    if (isAuthenticated()) return true;
    window.location.href = loginPageUrl || "index.html";
    return false;
  }

  function requireRole(requiredRole) {
    const user = currentUser();
    return !!user && String(user.role).toUpperCase() === String(requiredRole).toUpperCase();
  }

  function hasRole(requiredRole) { return requireRole(requiredRole); }

  // Matrice RBAC basée sur l'analyse forensic
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
      paies: ["read", "create", "update"],
      depenses: ["read", "create", "delete"],
      presences: ["read", "create", "update"],
      vault: ["update"]
    },
    Directeur: {
      personnel: ["read"],
      eleves: ["read", "create", "update"],
      annees: ["read"],
      matieres: ["read"],
      resultats: ["read", "create", "update"],
      finances: ["read"],
      vacances: ["read"],
      badge: ["read", "print"],
      paies: [],
      depenses: [],
      presences: ["read", "create", "update"],
      vault: []
    },
    Enseignant: {
      personnel: [],
      eleves: ["read"],
      annees: ["read"],
      matieres: ["read"],
      resultats: ["read", "create", "update"],
      finances: [],
      vacances: ["read"],
      badge: [],
      paies: [],
      depenses: [],
      presences: ["read", "create", "update"],
      vault: []
    },
    Secrétaire: {
      personnel: ["read"],
      eleves: ["read", "create", "update"],
      annees: ["read"],
      matieres: ["read"],
      resultats: [],
      finances: ["read"],
      vacances: ["read"],
      badge: ["read", "print"],
      paies: [],
      depenses: [],
      presences: ["read", "create", "update"],
      vault: []
    },
    Surveillant: {
      personnel: [],
      eleves: ["read"],
      annees: ["read"],
      matieres: ["read"],
      resultats: [],
      finances: [],
      vacances: ["read"],
      badge: [],
      paies: [],
      depenses: [],
      presences: ["read", "create", "update"],
      vault: []
    },
    Autre: {
      personnel: [],
      eleves: [],
      annees: ["read"],
      matieres: ["read"],
      resultats: [],
      finances: [],
      vacances: ["read"],
      badge: [],
      paies: [],
      depenses: [],
      presences: [],
      vault: []
    }
  };

  function hasPermission(permission) {
    const user = currentUser();
    if (!user) {
      return false;
    }

    // Format attendu: "resource.action"
    const parts = permission.split(".");
    if (parts.length !== 2) {
      console.warn("Format de permission invalide:", permission);
      return false;
    }

    const resource = parts[0];
    const action = parts[1];
    const role = user.role;

    // Récupérer les permissions pour ce rôle
    const rolePermissions = PERMISSION_MATRIX[role];
    if (!rolePermissions) {
      console.warn("Rôle non reconnu:", role);
      return false;
    }

    // Récupérer les permissions pour cette ressource
    const resourcePermissions = rolePermissions[resource];
    if (!resourcePermissions) {
      return false;
    }

    // Vérifier si l'action est autorisée
    return resourcePermissions.includes(action);
  }

  function requirePermission(permission) {
    if (!isAuthenticated()) {
      console.warn("Permission refusée: utilisateur non authentifié");
      return false;
    }

    if (!hasPermission(permission)) {
      console.warn("Permission refusée:", permission);
      return false;
    }

    return true;
  }

  // API publique
  window.IMCAuth = Object.freeze({
    login: login,
    logout: logout,
    isAuthenticated: isAuthenticated,
    currentUser: currentUser,
    requireAuth: requireAuth,
    verifySession: verifySession,
    refresh: function () { return false; },
    isSessionExpired: function () { return !isAuthenticated(); },
    requireRole: requireRole,
    hasRole: hasRole,
    hasPermission: hasPermission,
    requirePermission: requirePermission
  });

})();
