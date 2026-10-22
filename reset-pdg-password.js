document.addEventListener('DOMContentLoaded', async function () {
  const form = document.getElementById('reset-form');
  if (!form) return;
  const status = document.getElementById('status');
  const vaultStatus = document.getElementById('vault-status');
  const fields = document.getElementById('reset-fields');
  const button = document.getElementById('submit-button');

  // Le formulaire reste désactivé tant que le coffre local existant n'est pas déverrouillé.
  try {
    const vault = window.IMCSecureStorage;
    if (!vault || !vault.ready) throw new Error('Le coffre-fort n’est pas disponible.');
    const ready = await vault.ready;
    if (!ready || !vault.isUnlocked()) throw new Error('Le coffre-fort n’a pas été déverrouillé.');
    fields.disabled = false;
    vaultStatus.textContent = 'Coffre-fort déverrouillé. Vous pouvez continuer.';
    vaultStatus.className = 'success';
  } catch (error) {
    vaultStatus.textContent = error.message || 'Accès refusé : déverrouillez le coffre-fort existant.';
    vaultStatus.className = 'error';
    return;
  }

  form.addEventListener('submit', async function (event) {
    event.preventDefault();
    status.textContent = '';
    status.className = '';
    const recoveryToken = document.getElementById('recovery-token').value;
    const newPassword = document.getElementById('new-password').value;
    const confirmation = document.getElementById('confirm-password').value;

    if (!window.IMCSecureStorage || !window.IMCSecureStorage.isUnlocked()) {
      status.textContent = 'Le coffre-fort est verrouillé. Rechargez la page et déverrouillez-le.';
      status.className = 'error';
      fields.disabled = true;
      return;
    }
    if (recoveryToken.length < 32) {
      status.textContent = 'Code de récupération invalide.';
      status.className = 'error';
      return;
    }
    if (newPassword.length < 12 || newPassword.length > 200) {
      status.textContent = 'Le mot de passe doit contenir entre 12 et 200 caractères.';
      status.className = 'error';
      return;
    }
    if (newPassword !== confirmation) {
      status.textContent = 'Les deux mots de passe ne correspondent pas.';
      status.className = 'error';
      return;
    }

    button.disabled = true;
    try {
      const response = await fetch('/api/auth/reset-pdg-password.php', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: JSON.stringify({recoveryToken: recoveryToken, newPassword: newPassword})
      });
      const result = await response.json();
      if (!response.ok || !result.success) {
        throw new Error(result.error || 'Réinitialisation impossible.');
      }
      form.reset();
      status.textContent = 'Mot de passe réinitialisé. Retirez ou renouvelez maintenant le code de récupération sur le serveur.';
      status.className = 'success';
      button.textContent = 'Mot de passe réinitialisé';
    } catch (error) {
      status.textContent = error.message || 'Erreur réseau. Réessayez.';
      status.className = 'error';
    } finally {
      document.getElementById('recovery-token').value = '';
      document.getElementById('new-password').value = '';
      document.getElementById('confirm-password').value = '';
      if (status.className !== 'success') button.disabled = false;
    }
  });
});
