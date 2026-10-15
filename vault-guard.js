/*
 * IMC-Clarodoro - garde centralisé du coffre-fort
 *
 * Cette couche ne remplace jamais l'Auth/RBAC ni les contrôles serveur.
 * Elle fournit un point unique pour protéger les actions sensibles côté UI.
 * secure-storage.js doit être chargé avant ce module sur les pages concernées.
 */
(function () {
  "use strict";

  function getVault() {
    if (!window.IMCSecureStorage) {
      throw new Error("Le module du coffre-fort n'est pas chargé.");
    }
    return window.IMCSecureStorage;
  }

  async function ready() {
    const vault = getVault();
    if (vault.ready && typeof vault.ready.then === "function") {
      const result = await vault.ready;
      if (result === false || !vault.isUnlocked()) {
        throw new Error("Le coffre-fort est verrouillé.");
      }
      return true;
    }

    if (!vault.isUnlocked()) {
      throw new Error("Le coffre-fort est verrouillé.");
    }
    return true;
  }

  async function requireVault(options) {
    const config = options || {};
    await ready();

    if (config.permission && window.IMCAuth && typeof window.IMCAuth.requirePermission === "function") {
      if (!window.IMCAuth.requirePermission(config.permission)) {
        throw new Error("Permission refusée.");
      }
    }

    if (config.role && window.IMCAuth && typeof window.IMCAuth.requireRole === "function") {
      if (!window.IMCAuth.requireRole(config.role)) {
        throw new Error("Rôle insuffisant.");
      }
    }

    return true;
  }

  function isUnlocked() {
    return Boolean(
      window.IMCSecureStorage &&
      typeof window.IMCSecureStorage.isUnlocked === "function" &&
      window.IMCSecureStorage.isUnlocked()
    );
  }

  function guardAction(action, options) {
    return async function guardedAction() {
      await requireVault(options);
      return action.apply(this, arguments);
    };
  }

  window.IMCVaultGuard = Object.freeze({
    ready,
    requireVault,
    isUnlocked,
    guardAction
  });
})();
