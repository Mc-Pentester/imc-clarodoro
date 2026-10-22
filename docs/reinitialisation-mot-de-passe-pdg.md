# Réinitialisation du mot de passe PDG

La page publique `/reinitialiser-mot-de-passe.html` permet de réinitialiser uniquement le compte dont l’identifiant est `pdg` et dont le rôle est `PDG`. Elle ne crée pas de compte et ne modifie ni rôles, ni permissions, ni données métier.

## Préparation requise par un administrateur

1. Accéder au serveur ou à l’ordinateur qui héberge IMC-Clarodoro.
2. Générer un secret aléatoire avec PHP :

   ```powershell
   php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"
   ```

3. Ajouter le résultat au fichier local `.env` (jamais dans Git) :

   ```dotenv
   IMC_PDG_RESET_TOKEN=COLLER_ICI_LE_SECRET_ALEATOIRE
   ```

4. Redémarrer le serveur PHP/Web afin que l’environnement soit rechargé, si nécessaire.
5. Ouvrir `/reinitialiser-mot-de-passe.html`, saisir le secret, puis le nouveau mot de passe (12 caractères minimum) deux fois.

Sans `IMC_PDG_RESET_TOKEN` configuré avec au moins 32 caractères, l’API refuse la réinitialisation. Aucun secret par défaut n’est fourni.

## Après usage

Retirer immédiatement `IMC_PDG_RESET_TOKEN` du `.env` ou le remplacer par un nouveau secret aléatoire, puis redémarrer/recharger le serveur si nécessaire. Ne pas partager le secret, ne pas le mettre dans une capture d’écran et ne pas le committer.

## Portée et précautions

- La modification se fait dans PostgreSQL via une transaction et une mise à jour ciblée du compte PDG existant.
- Si le compte PDG est absent ou ambigu, la transaction est annulée.
- L’API n’accepte que les requêtes POST JSON et compare le secret sans comparaison naïve.
- Utiliser la page uniquement sur un serveur de confiance et via HTTPS si elle est accessible sur un réseau. Le secret de récupération est une preuve d’autorisation : toute personne qui le possède peut réinitialiser le mot de passe PDG.
