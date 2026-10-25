# Activation de l'envoi WhatsApp réel

L'application contient déjà l'interface `/whatsapp-send.html` et l'API serveur sécurisée. Le code n'envoie réellement que lorsque `WHATSAPP_SEND_ENABLED=true` et que les paramètres serveur sont valides.

## Variables serveur

Configurer **sur le serveur PHP uniquement** :

- `WHATSAPP_SEND_ENABLED=true`
- `WHATSAPP_ACCESS_TOKEN=<jeton Meta WhatsApp Business>`
- `WHATSAPP_PHONE_NUMBER_ID=<Phone Number ID Meta>`
- `WHATSAPP_API_VERSION=vX.Y`
- `WHATSAPP_ALLOWED_TEMPLATES=<modele1,modele2>`

Ne jamais mettre le jeton dans Git, JavaScript, HTML ou dans le navigateur.

## Conditions avant activation

1. Le compte Meta WhatsApp Business et le numéro d'envoi doivent être configurés.
2. Les modèles utilisés doivent être approuvés par Meta et présents dans `WHATSAPP_ALLOWED_TEMPLATES`.
3. Chaque parent destinataire doit avoir un consentement `OPTED_IN` pour la finalité correspondante.
4. L'utilisateur doit posséder `whatsapp.message.send`.
5. Tester d'abord avec un numéro autorisé et surveiller le journal `whatsapp_message_log`.

L'activation est volontairement **impossible par l'interface** : elle se fait uniquement par configuration serveur afin qu'un utilisateur disposant d'un compte applicatif ne puisse pas transformer accidentellement une installation en émetteur réel.

## Limite actuelle

Le module ne peut pas être activé réellement depuis GitHub seul : GitHub ne contient pas et ne doit pas contenir les secrets Meta de l'installation. Une fois ces variables présentes dans l'environnement PHP de production, l'API existante bascule automatiquement du mode simulation au mode live.
