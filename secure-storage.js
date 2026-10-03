/*
 * IMC-Clarodoro - coffre client-side minimal
 *
 * Les préférences générales restent dans localStorage.
 * Les données sensibles sont regroupées dans un coffre IndexedDB chiffré.
 * La clé de session n'est jamais persistée.
 */
(function () {
  "use strict";

  const DB_NAME = "imc_clarodoro_secure_v1";
  const STORE_NAME = "vault";
  const RECORD_ID = "main";
  const ITERATIONS = 600000;
  const IDLE_TIMEOUT = 15 * 60 * 1000;

  const SENSITIVE_KEYS = new Set([
    "imc_students",
    "imc_finances",
    "imc_tarifs",
    "imc_personnel",
    "imc_presences",
    "imc_resultats",
    "imc_depenses",
    "imc_paies_personnel",
    "imc_pdg_password_hash"
  ]);

  const nativeGetItem = Storage.prototype.getItem;
  const nativeSetItem = Storage.prototype.setItem;
  const nativeRemoveItem = Storage.prototype.removeItem;

  let sessionKey = null;
  let vaultData = Object.create(null);
  let vaultReady = false;
  let saveChain = Promise.resolve();
  let idleTimer = null;

  function bytesToBase64(bytes) {
    let binary = "";
    bytes.forEach(function (byte) {
      binary += String.fromCharCode(byte);
    });
    return btoa(binary);
  }

  function base64ToBytes(value) {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  }

  function ouvrirBase() {
    return new Promise(function (resolve, reject) {
      const request = indexedDB.open(DB_NAME, 1);

      request.onupgradeneeded = function () {
        if (!request.result.objectStoreNames.contains(STORE_NAME)) {
          request.result.createObjectStore(STORE_NAME, { keyPath: "id" });
        }
      };

      request.onsuccess = function () {
        resolve(request.result);
      };

      request.onerror = function () {
        reject(request.error || new Error("Impossible d'ouvrir IndexedDB."));
      };
    });
  }

  function lireEnregistrement(db) {
    return new Promise(function (resolve, reject) {
      const transaction = db.transaction(STORE_NAME, "readonly");
      const request = transaction.objectStore(STORE_NAME).get(RECORD_ID);

      request.onsuccess = function () {
        resolve(request.result || null);
      };

      request.onerror = function () {
        reject(request.error || new Error("Lecture du coffre impossible."));
      };
    });
  }

  function ecrireEnregistrement(db, record) {
    return new Promise(function (resolve, reject) {
      const transaction = db.transaction(STORE_NAME, "readwrite");
      const request = transaction.objectStore(STORE_NAME).put(record);

      request.onsuccess = function () {
        resolve();
      };

      request.onerror = function () {
        reject(request.error || new Error("Écriture du coffre impossible."));
      };
    });
  }

  async function deriveKey(password, salt) {
    const material = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(password),
      "PBKDF2",
      false,
      ["deriveKey"]
    );

    return crypto.subtle.deriveKey(
      {
        name: "PBKDF2",
        salt,
        iterations: ITERATIONS,
        hash: "SHA-256"
      },
      material,
      {
        name: "AES-GCM",
        length: 256
      },
      false,
      ["encrypt", "decrypt"]
    );
  }

  async function chiffrer(data, key) {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const plaintext = new TextEncoder().encode(JSON.stringify(data));
    const ciphertext = await crypto.subtle.encrypt(
      { name: "AES-GCM", iv },
      key,
      plaintext
    );

    return {
      iv: bytesToBase64(iv),
      ciphertext: bytesToBase64(new Uint8Array(ciphertext))
    };
  }

  async function dechiffrer(record, key) {
    const plaintext = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: base64ToBytes(record.iv)
      },
      key,
      base64ToBytes(record.ciphertext)
    );

    return JSON.parse(new TextDecoder().decode(plaintext));
  }

  function demanderMotDePasse(initialisation) {
    const message = initialisation
      ? "Créez le mot de passe maître du coffre IMC-Clarodoro (12 caractères minimum) :"
      : "Mot de passe maître du coffre IMC-Clarodoro :";

    const password = window.prompt(message);

    if (password === null) {
      throw new Error("Déverrouillage annulé.");
    }

    if (password.length < 12) {
      throw new Error("Le mot de passe maître doit contenir au moins 12 caractères.");
    }

    return password;
  }

  async function initialiserCoffre() {
    const db = await ouvrirBase();
    let record = await lireEnregistrement(db);

    if (!record) {
      const password = demanderMotDePasse(true);
      const confirmation = window.prompt("Confirmez le mot de passe maître :");

      if (password !== confirmation) {
        throw new Error("Les mots de passe maîtres ne correspondent pas.");
      }

      const salt = crypto.getRandomValues(new Uint8Array(16));
      sessionKey = await deriveKey(password, salt);
      vaultData = Object.create(null);

      SENSITIVE_KEYS.forEach(function (key) {
        const legacyValue = nativeGetItem.call(window.localStorage, key);
        if (legacyValue !== null) {
          vaultData[key] = legacyValue;
          nativeRemoveItem.call(window.localStorage, key);
        }
      });

      const encrypted = await chiffrer(vaultData, sessionKey);
      record = {
        id: RECORD_ID,
        version: 1,
        iterations: ITERATIONS,
        salt: bytesToBase64(salt),
        iv: encrypted.iv,
        ciphertext: encrypted.ciphertext
      };
      await ecrireEnregistrement(db, record);
    } else {
      let unlocked = false;

      for (let attempt = 1; attempt <= 3 && !unlocked; attempt += 1) {
        const password = demanderMotDePasse(false);
        const salt = base64ToBytes(record.salt);

        try {
          sessionKey = await deriveKey(password, salt);
          vaultData = await dechiffrer(record, sessionKey);
          unlocked = true;
        } catch (error) {
          sessionKey = null;
          vaultData = Object.create(null);
          if (attempt < 3) {
            window.alert("Mot de passe maître incorrect.");
          }
        }
      }

      if (!unlocked) {
        throw new Error("Le coffre n'a pas pu être déverrouillé.");
      }
    }

    vaultReady = true;
    window.dispatchEvent(new CustomEvent("imc-vault-unlocked"));
  }

  async function sauvegarderCoffre() {
    if (!vaultReady || !sessionKey) {
      throw new Error("Le coffre est verrouillé.");
    }

    const db = await ouvrirBase();
    const current = await lireEnregistrement(db);
    const encrypted = await chiffrer(vaultData, sessionKey);

    await ecrireEnregistrement(db, {
      id: RECORD_ID,
      version: 1,
      iterations: current ? current.iterations : ITERATIONS,
      salt: current ? current.salt : "",
      iv: encrypted.iv,
      ciphertext: encrypted.ciphertext
    });
  }

  function planifierSauvegarde() {
    saveChain = saveChain
      .then(sauvegarderCoffre)
      .catch(function (error) {
        console.error("Sauvegarde du coffre impossible :", error);
      });
  }

  function verrouiller() {
    if (!vaultReady) {
      return;
    }
    sessionKey = null;
    vaultData = Object.create(null);
    vaultReady = false;
    window.location.reload();
  }

  async function changerMotDePasse(ancienCode, nouveauCode, confirmation) {
    // Vérification des préconditions
    if (!vaultReady || !sessionKey) {
      throw new Error("Le coffre doit être déverrouillé pour changer le mot de passe.");
    }

    // Vérification RBAC
    if (window.IMCAuth && typeof window.IMCAuth.requirePermission === "function") {
      if (!window.IMCAuth.requirePermission("vault.update")) {
        throw new Error("Permission refusée.");
      }
    }

    // Validation de l'ancien code
    if (!ancienCode || typeof ancienCode !== "string" || ancienCode.length < 12) {
      throw new Error("Ancien code invalide.");
    }

    // Validation du nouveau code
    if (!nouveauCode || typeof nouveauCode !== "string" || nouveauCode.length < 12) {
      throw new Error("Le nouveau code doit contenir au moins 12 caractères.");
    }

    // Validation de la confirmation
    if (nouveauCode !== confirmation) {
      throw new Error("Les deux nouveaux codes ne correspondent pas.");
    }

    // Ne pas modifier si le nouveau code est identique à l'ancien
    if (ancienCode === nouveauCode) {
      throw new Error("Le nouveau code doit être différent de l'ancien.");
    }

    const db = await ouvrirBase();
    const currentRecord = await lireEnregistrement(db);

    if (!currentRecord) {
      throw new Error("Aucun coffre trouvé.");
    }

    // Sauvegarde de l'ancien payload pour restauration en cas d'échec
    const oldPayload = currentRecord;

    try {
      // Vérification de l'ancien code
      const oldSalt = base64ToBytes(currentRecord.salt);
      const oldKey = await deriveKey(ancienCode, oldSalt);
      
      let vaultDataTest;
      try {
        vaultDataTest = await dechiffrer(currentRecord, oldKey);
      } catch (error) {
        throw new Error("Ancien code incorrect.");
      }

      // Validation de la cohérence des données
      if (!vaultDataTest || typeof vaultDataTest !== "object") {
        throw new Error("Données du coffre invalides.");
      }

      // Génération du nouveau salt
      const newSalt = crypto.getRandomValues(new Uint8Array(16));

      // Dérivation de la nouvelle clé
      const newKey = await deriveKey(nouveauCode, newSalt);

      // Re-chiffrement avec la nouvelle clé
      const encrypted = await chiffrer(vaultDataTest, newKey);

      // Validation du nouveau payload avant écriture
      let verificationData;
      try {
        verificationData = await dechiffrer(
          { iv: encrypted.iv, ciphertext: encrypted.ciphertext },
          newKey
        );
      } catch (error) {
        throw new Error("Échec de validation du nouveau chiffrement.");
      }

      // Vérification de l'intégrité des données après re-chiffrement
      if (JSON.stringify(vaultDataTest) !== JSON.stringify(verificationData)) {
        throw new Error("Incohérence des données après re-chiffrement.");
      }

      // Construction du nouveau payload
      const newPayload = {
        id: RECORD_ID,
        version: 1,
        iterations: ITERATIONS,
        salt: bytesToBase64(newSalt),
        iv: encrypted.iv,
        ciphertext: encrypted.ciphertext
      };

      // Écriture atomique du nouveau payload
      await ecrireEnregistrement(db, newPayload);

      // Validation après écriture
      const writtenRecord = await lireEnregistrement(db);
      let finalVerification;
      try {
        finalVerification = await dechiffrer(writtenRecord, newKey);
      } catch (error) {
        // En cas d'échec, tentative de restauration
        await ecrireEnregistrement(db, oldPayload);
        throw new Error("Échec de validation après écriture. Restauration effectuée.");
      }

      if (JSON.stringify(vaultDataTest) !== JSON.stringify(finalVerification)) {
        await ecrireEnregistrement(db, oldPayload);
        throw new Error("Incohérence des données après écriture. Restauration effectuée.");
      }

      // Nettoyage sécurisé
      sessionKey = null;
      vaultData = Object.create(null);
      vaultReady = false;

      return true;

    } catch (error) {
      // En cas d'erreur, tenter de restaurer l'ancien payload
      try {
        await ecrireEnregistrement(db, oldPayload);
      } catch (restoreError) {
        console.error("Erreur critique lors de la restauration du coffre:", restoreError);
        throw new Error("Erreur critique : impossible de restaurer le coffre.");
      }
      throw error;
    }
  }

  function reinitialiserVerrouillageAutomatique() {
    if (!vaultReady) {
      return;
    }

    window.clearTimeout(idleTimer);
    idleTimer = window.setTimeout(verrouiller, IDLE_TIMEOUT);
  }

  function afficherEtatVerrouillage() {
    const overlay = document.createElement("div");
    overlay.id = "imcVaultOverlay";
    overlay.setAttribute("role", "dialog");
    overlay.setAttribute("aria-live", "polite");
    overlay.innerHTML = "<div class=\"imc-vault-box\"><strong>Coffre sécurisé IMC-Clarodoro</strong><p id=\"imcVaultStatus\">Déverrouillage en cours…</p></div>";
    document.documentElement.appendChild(overlay);

    const style = document.createElement("style");
    style.textContent = "#imcVaultOverlay{position:fixed;inset:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;background:#102a43f2;font-family:Arial,sans-serif;color:#fff}#imcVaultOverlay .imc-vault-box{width:min(430px,90vw);padding:26px;border-radius:12px;background:#1f4e78;box-shadow:0 10px 35px #0008;text-align:center}#imcVaultOverlay p{line-height:1.5}.imc-vault-error{background:#7f1d1d!important}";
    document.head.appendChild(style);

    return overlay;
  }

  function retirerEtatVerrouillage(overlay) {
    if (overlay && overlay.parentNode) {
      overlay.parentNode.removeChild(overlay);
    }
  }

  function valeurSensible(key) {
    return Object.prototype.hasOwnProperty.call(vaultData, key)
      ? vaultData[key]
      : null;
  }

  function ecrireSensible(key, value) {
    vaultData[key] = String(value);
    planifierSauvegarde();
  }

  Storage.prototype.getItem = function (key) {
    if (SENSITIVE_KEYS.has(String(key))) {
      return vaultReady ? valeurSensible(String(key)) : null;
    }
    return nativeGetItem.call(this, key);
  };

  Storage.prototype.setItem = function (key, value) {
    if (SENSITIVE_KEYS.has(String(key))) {
      if (!vaultReady) {
        throw new Error("Le coffre est verrouillé.");
      }
      ecrireSensible(String(key), value);
      return;
    }
    return nativeSetItem.call(this, key, value);
  };

  Storage.prototype.removeItem = function (key) {
    if (SENSITIVE_KEYS.has(String(key))) {
      if (vaultReady) {
        delete vaultData[String(key)];
        planifierSauvegarde();
      }
      return;
    }
    return nativeRemoveItem.call(this, key);
  };

  const overlay = afficherEtatVerrouillage();
  const status = overlay.querySelector("#imcVaultStatus");

  const ready = initialiserCoffre()
    .then(function () {
      retirerEtatVerrouillage(overlay);
      ["click", "keydown", "pointermove", "touchstart"].forEach(function (eventName) {
        window.addEventListener(eventName, reinitialiserVerrouillageAutomatique, { passive: true });
      });
      reinitialiserVerrouillageAutomatique();
      return true;
    })
    .catch(function (error) {
      console.error(error);
      status.textContent = "Le coffre est verrouillé. Rechargez la page pour réessayer.";
      overlay.classList.add("imc-vault-error");
      return false;
    });

  window.IMCSecureStorage = Object.freeze({
    ready,
    isUnlocked: function () {
      return vaultReady;
    },
    lock: verrouiller,
    changePassword: changerMotDePasse
  });
})();
