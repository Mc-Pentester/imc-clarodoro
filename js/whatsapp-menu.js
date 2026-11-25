/* IMC-Clarodaro — point d'entrée unique du module de communication WhatsApp.
 * Le serveur reste l'autorité finale: ce bouton ne contourne jamais RBAC.
 * L'ancien libellé « Envoyer un message WhatsApp » est remplacé par l'entrée unique ci-dessous.
 */
(function () {
  "use strict";

  async function ajouterAccesWhatsApp() {
    if (!window.IMCAuth || typeof window.IMCAuth.verifySession !== "function") return;

    try {
      await window.IMCAuth.verifySession();
    } catch (error) {
      console.error("Vérification de session WhatsApp impossible:", error);
      return;
    }

    if (!window.IMCAuth.isAuthenticated()) return;
    var canSend = window.IMCAuth.hasPermission("whatsapp.message.send");
    var canReadConsent = window.IMCAuth.hasPermission("whatsapp.consent.read");
    if (!canSend && !canReadConsent) return;

    // Un seul bouton au total, même si la page possède plusieurs variantes de navigation.
    var menu = document.querySelector(".menu-principal");
    if (menu && !document.querySelector('[data-imc-whatsapp-module="true"]')) {
      var button = document.createElement("button");
      button.type = "button";
      button.dataset.imcWhatsappModule = "true";
      button.className = "pdg";
      button.textContent = "Communication WhatsApp";
      button.setAttribute("aria-label", "Ouvrir le module de communication WhatsApp");
      button.addEventListener("click", function () {
        if (canSend) {
          window.location.href = "/whatsapp-send.html";
        } else {
          window.location.href = "/whatsapp-consent-management.html";
        }
      });
      menu.appendChild(button);
    }

    // Les fonctions complémentaires restent accessibles depuis la page
    // principale du module, jamais comme entrées supplémentaires du menu.
    if (window.location.pathname === "/whatsapp-send.html" || window.location.pathname === "/whatsapp-send.html/") {
      var main = document.querySelector("main");
      if (main && !document.querySelector("[data-imc-whatsapp-tools]")) {
        var tools = document.createElement("nav");
        tools.dataset.imcWhatsappTools = "true";
        tools.setAttribute("aria-label", "Outils du module de communication WhatsApp");
        tools.style.cssText = "display:flex;gap:10px;flex-wrap:wrap;margin:0 0 18px";
        var multi = document.createElement("a");
        multi.href = "/whatsapp-multi-send.html";
        multi.textContent = "Communication multi-destinataires";
        multi.style.cssText = "display:inline-block;padding:10px 14px;border-radius:7px;background:#e5f3ed;color:#075e54;font-weight:700;text-decoration:none";
        tools.appendChild(multi);

        if (canReadConsent) {
          var consent = document.createElement("a");
          consent.href = "/whatsapp-consent-management.html";
          consent.textContent = "Gestion des consentements";
          consent.style.cssText = multi.style.cssText;
          tools.appendChild(consent);
        }
        main.insertBefore(tools, main.firstChild);
      }
    }
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
