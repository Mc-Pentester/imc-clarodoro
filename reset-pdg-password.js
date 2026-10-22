document.addEventListener('DOMContentLoaded', function () {
  const form = document.getElementById('reset-form');
  if (!form) return;
  const status = document.getElementById('status');
  const button = document.getElementById('submit-button');
  form.addEventListener('submit', async function (event) {
    event.preventDefault();
    status.textContent = '';
    status.className = '';
    const recoveryToken = document.getElementById('recovery-token').value;
    const newPassword = document.getElementById('new-password').value;
    const confirmation = document.getElementById('confirm-password').value;
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
