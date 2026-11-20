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
      if (window.IMCAuth.hasPermission("whatsapp.message.send") && !menu.querySelector('[data-imc-whatsapp-send="true"]')) {
        var button = document.createElement("button");
        button.type = "button";
        button.dataset.imcWhatsappSend = "true";
        button.className = "pdg";
        button.textContent = "Envoyer un message WhatsApp";
        button.setAttribute("aria-label", "Ouvrir l'interface d'envoi WhatsApp");
        button.addEventListener("click", function () { window.location.href = "/whatsapp-send.html"; });
        menu.appendChild(button);
      }
      if (window.IMCAuth.hasPermission("whatsapp.message.send") && !menu.querySelector('[data-imc-whatsapp-multi-send="true"]')) {
        var multiButton = document.createElement("button");
        multiButton.type = "button";
        multiButton.dataset.imcWhatsappMultiSend = "true";
        multiButton.className = "pdg";
        multiButton.textContent = "WhatsApp — destinataires multiples";
        multiButton.setAttribute("aria-label", "Ouvrir l'envoi WhatsApp multi-destinataires");
        multiButton.addEventListener("click", function () { window.location.href = "/whatsapp-multi-send.html"; });
        menu.appendChild(multiButton);
      }
      if (window.IMCAuth.hasPermission("whatsapp.consent.read") && !menu.querySelector('[data-imc-whatsapp-consent="true"]')) {
        var consentButton = document.createElement("button");
        consentButton.type = "button";
        consentButton.dataset.imcWhatsappConsent = "true";
        consentButton.className = "pdg";
        consentButton.textContent = "Gérer les consentements WhatsApp";
        consentButton.setAttribute("aria-label", "Gérer les consentements WhatsApp des parents");
        consentButton.addEventListener("click", function () { window.location.href = "/whatsapp-consent-management.html"; });
        menu.appendChild(consentButton);
      }
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
