/* IMC-Clarodaro — accès WhatsApp manuel depuis les pages métier.
 * Le serveur reste l'autorité finale: ce bouton ne contourne jamais RBAC.
 */
(function () {
  "use strict";

  async function ajouterAccesWhatsApp() {
    if (!window.IMCAuth || typeof window.IMCAuth.verifySession !== "function") return;

    // La session serveur est chargée de façon asynchrone. Ne pas tester
    // isAuthenticated() avant que /api/auth/me.php ait répondu.
    try {
      await window.IMCAuth.verifySession();
    } catch (error) {
      console.error("Vérification de session WhatsApp impossible:", error);
      return;
    }

    if (!window.IMCAuth.isAuthenticated()) return;
    if (!window.IMCAuth.hasPermission("whatsapp.message.send")) return;

    document.querySelectorAll(".menu-principal").forEach(function (menu) {
      if (menu.querySelector('[data-imc-whatsapp-send="true"]')) return;
      var button = document.createElement("button");
      button.type = "button";
      button.dataset.imcWhatsappSend = "true";
      button.className = "pdg";
      button.textContent = "Envoyer un message WhatsApp";
      button.setAttribute("aria-label", "Ouvrir l'interface d'envoi WhatsApp");
      button.addEventListener("click", function () {
        window.location.href = "/whatsapp-send.html";
      });
      menu.appendChild(button);
    });
  }

  function initialiserAccesWhatsApp() {
    ajouterAccesWhatsApp().catch(function (error) {
      console.error("Initialisation de l'accès WhatsApp impossible:", error);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialiserAccesWhatsApp, { once: true });
  } else {
    initialiserAccesWhatsApp();
  }
})();
