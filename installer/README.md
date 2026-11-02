# Installateur Windows — IMC-Clarodaro

## Portée de cette première version

Ce paquet Inno Setup déploie les fichiers applicatifs et crée les raccourcis Windows. Il est volontairement conservateur : il ne touche jamais à PostgreSQL et ne lance aucune opération SQL.

### Protections prévues

- Réinstallation/mise à jour dans le même dossier sans désinstallation préalable.
- Le fichier `.env`, les sauvegardes, journaux et répertoires temporaires sont exclus du remplacement.
- La désinstallation ne contient aucune suppression de données persistantes.
- Aucun appel à `bootstrap-auth.php`, aucun changement de mot de passe PDG.
- Aucun arrêt/redémarrage de service PostgreSQL, Apache ou PHP.
- Aucun `database/schema.sql`, migration, restauration ou création de base n'est exécuté.

## Limitation importante — paquet initial

Cette version n'est pas encore un installateur autonome prêt pour un poste vierge. Elle suppose que l'environnement PHP/Apache déjà validé est installé et que le site est accessible sur `http://localhost:8080/`. Elle ne configure pas automatiquement Apache, PHP, PostgreSQL ni le service applicatif. Le compte PDG initial reste soumis au processus sécurisé séparé ; l'assistant graphique de première création n'est pas encore inclus.

Ces limites sont explicites afin de ne pas risquer de modifier une base existante ou d'arrêter un service non géré.

## Construction

Le workflow GitHub Actions **Windows installer package** compile le fichier `installer/IMC-Clarodoro.iss` avec Inno Setup et publie l'exécutable comme artefact de 14 jours.

Le paquet ne doit pas être distribué comme version autonome avant les étapes suivantes : détection et configuration du runtime, gestion contrôlée du serveur web, emplacement persistant documenté, assistant de première initialisation PDG et tests de réinstallation sur Windows.
