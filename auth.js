/*
 * IMC-Clarodoro - Module d'authentification central
 *
 * Ce module fournit une authentification locale côté navigateur.
 * Il ne constitue pas une autorisation serveur.
 *
 * Session storage pour éviter une persistance illimitée.
 * Aucun mot de passe ou clé AES n'est stocké dans la session.
 */
(function () {
  "use strict";

  const SESSION_KEY = "imc_auth_session";
  const SESSION_DURATION = 8 * 60 * 60 * 1000; // 8 heures

  function generateSessionId() {
    if (typeof crypto !== "undefined" && crypto.randomUUID) {
      return crypto.randomUUID();
    }
    // Fallback cryptographiquement approprié si crypto.randomUUID n'est pas disponible
    const array = new Uint8Array(16);
    if (typeof crypto !== "undefined" && crypto.getRandomValues) {
      crypto.getRandomValues(array);
    } else {
      // Dernier recours - utiliser Math.random() seulement si crypto n'est pas disponible
      for (let i = 0; i < array.length; i++) {
        array[i] = Math.floor(Math.random() * 256);
      }
    }
    return Array.from(array)
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");
  }

  function validateSession(session) {
    if (!session || typeof session !== "object") {
      return false;
    }
    if (!session.sessionId || typeof session.sessionId !== "string") {
      return false;
    }
    if (!session.userId || typeof session.userId !== "string") {
      return false;
    }
    if (!session.username || typeof session.username !== "string") {
      return false;
    }
    if (!session.role || typeof session.role !== "string") {
      return false;
    }
    if (!session.loginAt || typeof session.loginAt !== "number") {
      return false;
    }
    if (!session.expiresAt || typeof session.expiresAt !== "number") {
      return false;
    }
    if (session.expiresAt <= Date.now()) {
      return false;
    }
    return true;
  }

  function getSession() {
    try {
      const sessionJson = sessionStorage.getItem(SESSION_KEY);
      if (!sessionJson) {
        return null;
      }
      const session = JSON.parse(sessionJson);
      if (!validateSession(session)) {
        sessionStorage.removeItem(SESSION_KEY);
        return null;
      }
      return session;
    } catch (error) {
      console.error("Erreur lors de la lecture de la session:", error);
      sessionStorage.removeItem(SESSION_KEY);
      return null;
    }
  }

  function saveSession(session) {
    try {
      sessionStorage.setItem(SESSION_KEY, JSON.stringify(session));
    } catch (error) {
      console.error("Erreur lors de la sauvegarde de la session:", error);
      throw new Error("Impossible de sauvegarder la session");
    }
  }

  function isSessionExpired() {
    const session = getSession();
    if (!session) {
      return true;
    }
    return session.expiresAt <= Date.now();
  }

  function isAuthenticated() {
    return !isSessionExpired();
  }

  function currentUser() {
    const session = getSession();
    if (!session) {
      return null;
    }
    // Ne jamais retourner de mot de passe ou de clé
    return {
      userId: session.userId,
      username: session.username,
      role: session.role,
      loginAt: session.loginAt,
      expiresAt: session.expiresAt
    };
  }

  function login(credentials) {
    const userId = credentials.userId || credentials.id || String(Date.now());
    const username = credentials.username || credentials.nom || "Utilisateur";
    const role = credentials.role || "USER";

    const session = {
      sessionId: generateSessionId(),
      userId: String(userId),
      username: String(username),
      role: String(role),
      loginAt: Date.now(),
      expiresAt: Date.now() + SESSION_DURATION
    };

    saveSession(session);
    return session;
  }

  function logout() {
    sessionStorage.removeItem(SESSION_KEY);
    
    // Tenter de verrouiller le coffre si le mécanisme existe
    if (window.IMCSecureStorage && typeof window.IMCSecureStorage.lock === "function") {
      try {
        window.IMCSecureStorage.lock();
      } catch (error) {
        console.error("Erreur lors du verrouillage du coffre:", error);
      }
    }
  }

  function refresh() {
    const session = getSession();
    if (!session) {
      return false;
    }
    session.expiresAt = Date.now() + SESSION_DURATION;
    saveSession(session);
    return true;
  }

  function requireAuth(loginPageUrl) {
    if (isAuthenticated()) {
      return true;
    }
    
    // Session invalide ou absente - rediriger vers login
    if (loginPageUrl) {
      window.location.href = loginPageUrl;
    } else {
      // Par défaut, rediriger vers index.html
      window.location.href = "index.html";
    }
    return false;
  }

  function requireRole(requiredRole) {
    const user = currentUser();
    if (!user) {
      return false;
    }
    return String(user.role).toUpperCase() === String(requiredRole).toUpperCase();
  }

  function hasRole(requiredRole) {
    return requireRole(requiredRole);
  }

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
    getSession: getSession,
    refresh: refresh,
    isSessionExpired: isSessionExpired,
    requireRole: requireRole,
    hasRole: hasRole,
    hasPermission: hasPermission,
    requirePermission: requirePermission
  });

})();
