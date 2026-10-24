# WhatsApp — envoi manuel contrôlé

## État
L'endpoint `POST /api/whatsapp/send.php` utilise le mode simulation par défaut. Aucun appel réseau n'est effectué tant que `WHATSAPP_SEND_ENABLED` n'est pas exactement `true`. La migration de journal est additive et doit être revue avant application; elle n'est pas exécutée par le code.

## Contrat de requête
JSON : `parent_id` (UUID), `purpose` (`ATTENDANCE`, `RESULTS_AVAILABLE`, `PAYMENT_REMINDER`, `GENERAL`), `template_name`, `language`, `parameters` (tableau de chaînes), `idempotency_key` (16–120 caractères). Requiert une session authentifiée, la permission serveur `whatsapp.message.send` et l'en-tête `X-CSRF-Token`.

Le numéro est obtenu exclusivement du consentement actif en base; le navigateur ne fournit pas le destinataire. Le modèle est envoyé comme modèle WhatsApp, et les envois réels exigent que son nom figure dans `WHATSAPP_ALLOWED_TEMPLATES`.

## Variables serveur
- `WHATSAPP_SEND_ENABLED=false` (par défaut, simulation)
- `WHATSAPP_ACCESS_TOKEN` (secret serveur uniquement)
- `WHATSAPP_PHONE_NUMBER_ID`
- `WHATSAPP_API_VERSION` (format `vX.Y`)
- `WHATSAPP_ALLOWED_TEMPLATES` (noms séparés par virgules)

Ne jamais placer ces secrets dans le dépôt, le navigateur ou les logs.

## Avant activation réelle
1. Vérifier le schéma réel et appliquer les migrations via le processus approuvé.
2. Attribuer explicitement `whatsapp.message.send` à des rôles précis; ne pas ouvrir l'accès à tous les rôles.
3. Configurer les actifs Meta et tester avec un destinataire autorisé.
4. Confirmer les modèles approuvés et la preuve de consentement.
5. Vérifier CSRF, accès RBAC, répétition de la même clé (409), consentement absent/retiré (403), mode simulation (aucun appel réseau) et erreurs fournisseur.
6. Garder l'envoi automatique désactivé jusqu'à la définition de déclencheurs métier fiables pour absences confirmées, résultats publiés et rappels de paiement.

Le statut `SENT` signifie que Meta a accepté la requête, pas que le message a été livré. Les accusés de livraison nécessiteront un webhook de statut signé et validé, à implémenter séparément.
