/* IMC-Clarodaro — accès WhatsApp manuel depuis les pages métier.
 * Le serveur reste l'autorité finale: ce bouton ne contourne jamais RBAC.
 */
(function () {
  "use strict";

  function ajouterAccesWhatsApp() {
    if (!window.IMCAuth || !window.IMCAuth.isAuthenticated || !window.IMCAuth.isAuthenticated()) return;
    if (!window.IMCAuth.hasPermission("whatsapp.message.send")) return;

    document.querySelectorAll(".menu-principal").forEach(function (menu) {
      if (menu.querySelector('[data-imc-whatsapp-send="true"]')) return;
      var button = document.createElement("button");
      button.type = "button";
      button.dataset.imcWhatsappSend = "true";
      button.textContent = "WhatsApp";
      button.setAttribute("aria-label", "Ouvrir l'interface d'envoi WhatsApp");
      button.addEventListener("click", function () {
        window.location.href = "/whatsapp-send.html";
      });
      menu.appendChild(button);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ajouterAccesWhatsApp);
  } else {
    ajouterAccesWhatsApp();
  }
})();
