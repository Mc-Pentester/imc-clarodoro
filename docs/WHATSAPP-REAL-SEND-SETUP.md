# WhatsApp : parcours manuel et API Meta Cloud

IMC-Clarodoro dispose de deux parcours distincts. Ils ne doivent pas être confondus.

## A. Préparation manuelle via WhatsApp (interface actuelle)

La page `/whatsapp-send.html` :
- exige la permission `whatsapp.message.send` ;
- vérifie le consentement `OPTED_IN` pour la finalité choisie ;
- revérifie le consentement côté serveur au clic final ;
- journalise la préparation dans `whatsapp_manual_preparations` avec l’utilisateur, le parent, le consentement, la finalité et des empreintes SHA-256 du numéro et du texte ;
- n’enregistre pas le texte complet ni le numéro en clair dans cette table ;
- ouvre `wa.me` avec le numéro et le message préremplis.

L’utilisateur doit vérifier le destinataire et appuyer lui-même sur **Envoyer** dans WhatsApp. La journalisation prouve qu’une préparation a été autorisée, pas que WhatsApp a été ouvert, ni que le message a été envoyé ou livré.

Le texte prérempli fait partie de l’URL `wa.me`. Ne pas y inclure de résultats détaillés, de données médicales, disciplinaires ou financières, ni d’autres informations scolaires sensibles. L’application efface le champ après la préparation; elle ne conserve pas le texte dans `localStorage`.

Migrations requises pour ce parcours :
- `20261023100000_whatsapp_consent_foundation.sql`
- `20261025100000_assign_whatsapp_manual_permissions.sql`
- `20261023103000_whatsapp_consent_audit.sql`
- `20261023110000_whatsapp_message_log.sql`
- `20261025120000_whatsapp_manual_preparations.sql`

Appliquer les migrations selon l’ordre chronologique et vérifier leur statut dans l’environnement de l’établissement.

## B. API Meta Cloud API (endpoint séparé)

L’endpoint `POST /api/whatsapp/send.php` est un parcours serveur distinct. **La variable `WHATSAPP_SEND_ENABLED=true` n’active pas l’envoi depuis la page manuelle `/whatsapp-send.html`**. Elle concerne uniquement cet endpoint API direct.

Pour utiliser l’API Meta, configurer sur le serveur PHP uniquement :
- `WHATSAPP_SEND_ENABLED=true`
- `WHATSAPP_ACCESS_TOKEN=<jeton Meta WhatsApp Business>`
- `WHATSAPP_PHONE_NUMBER_ID=<Phone Number ID Meta>`
- `WHATSAPP_API_VERSION=vX.Y`
- `WHATSAPP_ALLOWED_TEMPLATES=<modele1,modele2>`

Ne jamais placer le jeton dans Git, JavaScript, HTML ou le navigateur.

Avant activation, vérifier le compte Meta Business et le numéro d’envoi, l’approbation des modèles, le consentement actif du parent pour la finalité, la permission `whatsapp.message.send`, ainsi que le journal `whatsapp_message_log`. Tester d’abord avec un numéro autorisé.

L’activation se fait exclusivement par configuration serveur. GitHub ne contient pas et ne doit pas contenir les secrets Meta. L’acceptation par Meta ne garantit pas à elle seule la livraison du message.
