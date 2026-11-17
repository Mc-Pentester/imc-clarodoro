# Gestion des consentements WhatsApp des parents

## Parcours pris en charge

Clarodaro conserve un consentement par parent, numéro et finalité : présences/absences, résultats disponibles, rappels de paiement et communications générales. Le numéro de téléphone enregistré dans le dossier parent ne constitue jamais un accord.

### Consentement numérique par e-mail
1. Un membre autorisé de l'établissement ouvre « Gérer les consentements WhatsApp » et sélectionne le parent.
2. Clarodaro envoie une invitation à l'adresse e-mail déjà enregistrée dans le dossier du parent.
3. Le parent ouvre le lien temporaire, saisit le code à six chiffres reçu par e-mail, indique le numéro WhatsApp et choisit explicitement les finalités. Aucune case n'est précochée.
4. Le lien expire après 30 minutes et le code est limité à cinq tentatives. La confirmation est enregistrée comme DIGITAL_EMAIL, avec l'adresse vérifiée, l'heure, la version du texte et la référence de preuve.
5. Une invitation numérique n'active aucun consentement avant la confirmation du parent.

L'accès au lien et le code confirment l'accès à la boîte e-mail enregistrée. Ils ne remplacent pas une vérification d'identité indépendante.

### Consentement papier
Après réception d'un formulaire signé, un membre autorisé coche les finalités autorisées, saisit le numéro E.164 et indique une référence d'archive. Clarodaro refuse l'activation papier sans référence de preuve. La date et l'utilisateur qui a enregistré l'accord sont conservés.

### Retrait
L'établissement peut retirer une finalité depuis l'écran de gestion. Les API d'envoi vérifient toujours l'état courant du consentement; un retrait bloque les prochains envois pour cette finalité. L'historique d'audit est append-only.

## Configuration SMTP

Ajouter ces variables au fichier .env protégé de l'installation (ne jamais les committer) :

- APP_BASE_URL=https://adresse-de-l-etablissement
- SMTP_HOST=...
- SMTP_PORT=587
- SMTP_SECURITY=tls (tls, ssl ou none; TLS recommandé)
- SMTP_USERNAME=...
- SMTP_PASSWORD=...
- SMTP_FROM_EMAIL=...
- SMTP_FROM_NAME=Clarodaro

Le serveur doit pouvoir joindre le relais SMTP. Les identifiants restent côté serveur. En l'absence de configuration valide, l'invitation échoue explicitement et aucun consentement n'est créé.

## Migration

La migration 20261117100000_whatsapp_parent_consent_workflow.sql est additive. Elle n'est pas exécutée automatiquement. Vérifier la sauvegarde et l'état des migrations avant toute application en production. Aucun effacement ni réinitialisation de données n'est requis.
