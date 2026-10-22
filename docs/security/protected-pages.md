# Protection serveur des pages sensibles

Les pages suivantes ne contiennent plus leur interface complète dans les fichiers publics :
- `index.html` — permission `eleves.read`
- `PDG.html` — rôle `PDG` et permission `paies.read`
- `finances.html` — permission `finances.read`
- `personnel.html` — permission `personnel.read`
- `badge.html` — permission `badge.read`
- `payroll-recovery.html` — permission `paies.reconcile`
- `resultats.html` — permission `resultats.read`

Le contenu complet est conservé sous `private-pages/*.php`. Chaque source privée vérifie elle-même la session, le statut actif du compte et la permission PostgreSQL requise. Le contrôleur `secure-page.php` effectue le même contrôle avant de charger le contenu. Le répertoire privé est interdit en HTTP par `.htaccess` et par `router.php`.

## Démarrage local recommandé

Depuis la racine du dépôt, avec la configuration PostgreSQL locale déjà installée :

```powershell
php -S 127.0.0.1:8090 router.php
```

Ouvrir ensuite `http://127.0.0.1:8090/`. Ne pas utiliser un serveur statique pour valider l’authentification ou les permissions.

Pour Apache, conserver `mod_rewrite` activé et autoriser les règles du fichier `.htaccess`. Les fichiers publics ne sont que des pages de transition sans le contenu de l’interface protégée.

## Vérifications runtime

Le workflow `.github/workflows/payroll-reconciliation-runtime.yml` démarre un vrai serveur PHP avec PostgreSQL de test et vérifie :
- refus de toutes les pages protégées sans session ;
- absence du titre/contenu de page protégé dans les réponses anonymes ;
- refus de l'accès HTTP direct à `private-pages/` ;
- accès des sept pages avec une session PDG active et les permissions requises ;
- refus HTTP 403 pour un compte non-PDG sur `PDG.html` ;
- refus HTTP 401 pour une session expirée et un compte désactivé.

Les API conservent leurs contrôles d’authentification, de permissions et de CSRF. Aucun changement de schéma ou de données applicatives n’est nécessaire.
