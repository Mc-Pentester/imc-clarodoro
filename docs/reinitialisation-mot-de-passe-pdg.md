# Réinitialisation du mot de passe PDG — procédure administrateur

## Décision de sécurité

La réinitialisation par navigateur est désactivée. `api/auth/reset-pdg-password.php` renvoie HTTP `410 Gone` sans lire de secret, ouvrir PostgreSQL ni modifier de compte. Cette règle s'applique également aux appels HTTP directs à l'endpoint : connaître un ancien token ne permet donc plus de réinitialiser le mot de passe via l'API.

La page `/reinitialiser-mot-de-passe.html` explique la procédure, mais ne contient aucun formulaire de réinitialisation. Le coffre-fort navigateur reste une protection des données locales et de l'interface ; il n'est pas considéré comme une preuve d'autorisation côté serveur.

## Procédure depuis PowerShell (Windows)

À exécuter sur l'ordinateur autorisé qui héberge la base, depuis la racine du projet, avec PHP CLI et la configuration PostgreSQL habituelle disponibles.

1. Ouvrir PowerShell avec le compte système autorisé à administrer IMC-Clarodoro.
2. Saisir les commandes suivantes. Le mot de passe est demandé sous forme masquée ; le script ne l'affiche pas.

```powershell
$securePassword = Read-Host "Nouveau mot de passe PDG (12 caractères minimum)" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    $env:IMC_PDG_NEW_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    php .\Scripts\RESET-PDG-PASSWORD.php
    if ($LASTEXITCODE -ne 0) {
        throw "La réinitialisation a échoué. Consultez le message du script."
    }
}
finally {
    Remove-Item Env:IMC_PDG_NEW_PASSWORD -ErrorAction SilentlyContinue
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $securePassword.Dispose()
}
```

Le script vérifie que le mot de passe comporte au moins 12 caractères, calcule son hash avec `password_hash()`, puis efface la variable d'environnement dans le processus PHP. La commande PowerShell retire également la variable de son environnement à la fin. Éviter d'exécuter cette procédure sur un ordinateur partagé ou depuis une session non fiable.

## Ce que le script modifie

- Il se limite au compte existant dont l'identifiant est `pdg` et dont le rôle est `PDG`.
- Il remplace uniquement `users.password_hash` et actualise `updated_at`.
- La mise à jour se fait dans une transaction PostgreSQL.
- Si le compte attendu est absent ou si la mise à jour ne concerne pas exactement un compte, la transaction est annulée.
- Il ne crée aucun compte et ne modifie ni le schéma, ni les rôles, ni les permissions, ni les données métier.

## Après la réinitialisation

1. Vérifier que le script affiche `PASS`.
2. Se connecter à IMC-Clarodoro avec l'identifiant PDG et le nouveau mot de passe.
3. Ne pas transmettre le nouveau mot de passe par messagerie et ne pas l'enregistrer dans le dépôt Git.

## Vérification de la neutralisation HTTP

Une requête POST vers `/api/auth/reset-pdg-password.php`, même avec un JSON qui contient `recoveryToken` et `newPassword`, doit retourner HTTP `410 Gone` avec `success: false`. Cette requête ne doit pas modifier PostgreSQL. Vérifier ce comportement dans l'environnement de test avant déploiement.

## Prérequis et limites

- PHP CLI doit être installé et accessible avec `php`.
- La configuration de base de données doit permettre au compte système autorisé de se connecter à PostgreSQL.
- Cette procédure nécessite un accès administrateur local/serveur ; elle n'est pas destinée à une récupération autonome à distance.
- Ne pas réactiver l'endpoint HTTP sans un mécanisme d'autorisation serveur robuste, testé et indépendant du JavaScript du navigateur.
