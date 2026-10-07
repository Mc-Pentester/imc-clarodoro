/* F-02-E — Personnel server adapter
 * PostgreSQL/API is the source of truth for personnel records.
 * localStorage is not used for personnel CRUD.
 */
(function () {
  "use strict";

  async function fetchPersonnel() {
    const response = await fetch("/api/personnel/index.php", {
      method: "GET",
      credentials: "same-origin",
      cache: "no-store",
      headers: { "Accept": "application/json" }
    });
    const payload = await response.json().catch(function () { return null; });
    if (!response.ok || !payload || !payload.success) {
      throw new Error((payload && payload.error) || "Impossible de charger le personnel.");
    }
    return Array.isArray(payload.staff) ? payload.staff : [];
  }

  function toLegacy(row) {
    return {
      id: row.id,
      nom: [row.first_name, row.last_name].filter(Boolean).join(" ").trim(),
      fonction: row.role_name || row.function_name || "Autre",
      classe: row.class_name || "",
      identifiant: row.username || "",
      userId: row.user_id || null,
      status: row.status,
      _server: true
    };
  }

  async function chargerPersonnelServeur(showError) {
    try {
      personnel = (await fetchPersonnel()).map(toLegacy);
      if (typeof chargerPersonnelTableau === "function") {
        chargerPersonnelTableau();
      }
      return true;
    } catch (error) {
      if (showError !== false && typeof afficherMessage === "function") {
        afficherMessage("messagePersonnel", error.message, "erreur");
      }
      return false;
    }
  }

  async function connecterPersonnelServeur() {
    const identifiant = document.getElementById("identifiantConnexion").value.trim();
    const motDePasse = document.getElementById("motDePasseConnexion").value;

    if (!identifiant || !motDePasse) {
      afficherMessage("messageConnexion", "Veuillez saisir votre identifiant et votre mot de passe.", "erreur");
      return;
    }

    try {
      const utilisateur = await IMCAuth.login({
        username: identifiant,
        password: motDePasse
      });

      personnelConnecte = {
        id: utilisateur.userId,
        nom: utilisateur.username,
        fonction: utilisateur.role,
        identifiant: utilisateur.username
      };

      document.getElementById("sectionConnexion").classList.add("hidden");
      document.getElementById("interfacePersonnel").classList.remove("hidden");

      await chargerPersonnelServeur(true);

      if (typeof afficherInformationsEnseignant === "function") {
        afficherInformationsEnseignant();
      }
    } catch (error) {
      afficherMessage(
        "messageConnexion",
        error && error.message ? error.message : "Identifiant ou mot de passe incorrect.",
        "erreur"
      );
    }
  }

  async function ajouterPersonnelServeur() {
    if (!IMCAuth.requirePermission("personnel.create")) {
      afficherMessage("messagePersonnel", "Permission refusée.", "erreur");
      return;
    }

    const body = {
      action: "create",
      name: document.getElementById("personnelNom").value.trim(),
      role: document.getElementById("personnelFonction").value,
      class_name: document.getElementById("personnelClasse").value.trim(),
      username: document.getElementById("personnelIdentifiant").value.trim(),
      password: document.getElementById("personnelMotDePasse").value
    };

    try {
      const response = await fetch("/api/personnel/index.php", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
      });
      const payload = await response.json().catch(function () { return null; });
      if (!response.ok || !payload || !payload.success) {
        throw new Error((payload && payload.error) || "Création impossible.");
      }
      viderFormulairePersonnel();
      await chargerPersonnelServeur(false);
      afficherMessage("messagePersonnel", "Personnel ajouté avec succès.", "ok");
    } catch (error) {
      afficherMessage("messagePersonnel", error.message, "erreur");
    }
  }

  async function enregistrerModificationPersonnelServeur() {
    if (!IMCAuth.requirePermission("personnel.update")) {
      afficherMessage("messagePersonnel", "Permission refusée.", "erreur");
      return;
    }
    if (!personnelEnModification) return;

    const body = {
      action: "update",
      staff_id: personnelEnModification.id,
      name: document.getElementById("modNom").value.trim(),
      role: document.getElementById("modFonction").value,
      class_name: document.getElementById("modClasse").value.trim(),
      username: document.getElementById("modIdentifiant").value.trim(),
      password: document.getElementById("modMotDePasse").value
    };

    try {
      const response = await fetch("/api/personnel/index.php", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
      });
      const payload = await response.json().catch(function () { return null; });
      if (!response.ok || !payload || !payload.success) {
        throw new Error((payload && payload.error) || "Modification impossible.");
      }
      annulerModificationPersonnel();
      await chargerPersonnelServeur(false);
      afficherMessage("messagePersonnel", "Modification enregistrée.", "ok");
    } catch (error) {
      afficherMessage("messagePersonnel", error.message, "erreur");
    }
  }

  async function supprimerPersonnelServeur(id) {
    if (!IMCAuth.requirePermission("personnel.delete")) {
      afficherMessage("messagePersonnel", "Permission refusée.", "erreur");
      return;
    }
    if (!confirm("Voulez-vous archiver ce personnel ?")) return;

    try {
      const response = await fetch("/api/personnel/index.php", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "delete", staff_id: id })
      });
      const payload = await response.json().catch(function () { return null; });
      if (!response.ok || !payload || !payload.success) {
        throw new Error((payload && payload.error) || "Archivage impossible.");
      }
      await chargerPersonnelServeur(false);
      afficherMessage("messagePersonnel", "Personnel archivé.", "ok");
    } catch (error) {
      afficherMessage("messagePersonnel", error.message, "erreur");
    }
  }

  async function chargerDonneesPersonnelServeur() {
    // Keep F-02-C attendance/student compatibility local for now.
    try {
      eleves = JSON.parse(localStorage.getItem(CLE_ELEVES)) || [];
    } catch (error) {
      eleves = [];
    }
    try {
      presences = JSON.parse(localStorage.getItem(CLE_PRESENCES)) || {};
    } catch (error) {
      presences = {};
    }
    await chargerPersonnelServeur(false);
    if (typeof afficherElevesPersonnel === "function") {
      afficherElevesPersonnel();
    }
  }

  window.connecterPersonnel = connecterPersonnelServeur;
  window.connecterPersonnelWrapper = connecterPersonnelServeur;
  window.ajouterPersonnel = ajouterPersonnelServeur;
  window.enregistrerModificationPersonnel = enregistrerModificationPersonnelServeur;
  window.supprimerPersonnel = supprimerPersonnelServeur;
  window.sauvegarderPersonnel = function () {
    return chargerPersonnelServeur(false);
  };
  window.chargerDonnees = chargerDonneesPersonnelServeur;
})();
