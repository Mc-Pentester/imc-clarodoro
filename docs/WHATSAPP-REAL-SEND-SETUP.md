# WhatsApp réel — Meta WhatsApp Business Cloud API

Clarodaro envoie désormais les messages via l’API officielle Meta WhatsApp Business Cloud API. La page `/whatsapp-send.html` appelle le serveur Clarodaro, qui transmet la demande à Meta. Elle ne lance pas `wa.me`, n’ouvre pas l’application WhatsApp du poste et ne renvoie jamais un succès simulé.

## 1. Prérequis Meta

Avant de configurer Clarodaro, l’établissement doit disposer de :

- un portefeuille Meta Business et une application Meta ;
- un compte WhatsApp Business (WABA) associé à l’application ;
- un numéro professionnel enregistré et activé pour WhatsApp Business Platform ;
- le **Phone Number ID** du numéro d’envoi (ce n’est pas le numéro de téléphone visible) ;
- un jeton d’accès permanent ou de longue durée avec les autorisations WhatsApp Business requises, notamment `whatsapp_business_messaging` ;
- au moins un modèle de message approuvé par Meta, avec sa langue exacte ;
- le consentement WhatsApp explicite du parent pour la finalité concernée.

La configuration doit être réalisée dans Meta for Developers / WhatsApp > API Setup et dans WhatsApp Manager. Les noms et statuts des modèles doivent correspondre exactement à ceux approuvés par Meta.

## 2. Configuration sécurisée sous Windows

Sur une installation Windows Clarodaro, le serveur charge la configuration depuis :

`C:\ProgramData\IMC-Clarodaro\config\.env`

Ce fichier est situé dans ProgramData, en dehors du dépôt et du répertoire d’installation. Il est protégé par les ACL installateur. Ne placez jamais le jeton dans Git, dans un fichier JavaScript, dans une page HTML ou dans un formulaire du navigateur.

Ajouter ou mettre à jour les variables suivantes dans ce fichier :

```dotenv
WHATSAPP_SEND_ENABLED=true
WHATSAPP_ACCESS_TOKEN=COLLER_ICI_LE_JETON_META
WHATSAPP_PHONE_NUMBER_ID=IDENTIFIANT_NUMERIQUE_META
WHATSAPP_API_VERSION=vXX.X
WHATSAPP_ALLOWED_TEMPLATES=nom_modele_presence,nom_modele_information
```

Remplacer `vXX.X` par une version Graph API actuellement prise en charge par Meta, et les noms d’exemple par les noms exacts des modèles approuvés. Ne pas ajouter de guillemets autour des valeurs sauf nécessité particulière.

Après modification du fichier, redémarrer le serveur PHP / la tâche planifiée Clarodaro afin que les nouvelles variables soient chargées. Conserver le fichier dans ProgramData lors des mises à jour de l’application.

## 3. Utilisation dans Clarodaro

1. Ouvrir **WhatsApp — envoi réel** avec un compte autorisé.
2. Vérifier que l’état de configuration affiche « Configuration prête ».
3. Saisir l’UUID du parent enregistré dans Clarodaro.
4. Choisir la finalité correspondant au consentement actif du parent.
5. Choisir un modèle approuvé et sa langue exacte.
6. Saisir les paramètres du corps dans l’ordre défini par le modèle, un par ligne.
7. Cliquer sur **Envoyer réellement via WhatsApp**.

Le serveur vérifie la permission, le consentement actif et la finalité, applique une clé d’idempotence, journalise la demande, puis appelle l’endpoint Meta `/{PHONE_NUMBER_ID}/messages`. Aucun envoi n’est déclenché si la configuration est absente, si le modèle n’est pas autorisé ou si le consentement n’est pas actif.

## 4. Fenêtre de conversation et modèles

Pour les messages initiés par l’établissement en dehors de la fenêtre de service client autorisée par Meta, il faut utiliser un modèle approuvé. Clarodaro n’envoie pas de texte libre arbitraire à la place d’un modèle. Les paramètres fournis doivent correspondre exactement aux variables déclarées dans le modèle Meta.

Les finalités de consentement prises en charge actuellement sont : `ATTENDANCE`, `RESULTS_AVAILABLE`, `PAYMENT_REMINDER` et `GENERAL`. Le consentement est vérifié côté serveur à chaque envoi.

## 5. Résultat et limites de confirmation

- **Demande acceptée par Meta** : Meta a accepté la requête et renvoyé un identifiant de message.
- **Livraison** : elle n’est pas garantie par la réponse d’acceptation. Elle doit être confirmée par les statuts du compte WhatsApp Business / Meta.
- **Échec** : Clarodaro journalise l’échec et affiche le code d’erreur fournisseur disponible.
- **Configuration absente** : la page bloque l’envoi et l’API retourne une erreur. Aucun mode simulation n’est utilisé.

Le journal `whatsapp_message_log` conserve l’identifiant de message fournisseur, le statut d’acceptation/échec, la finalité, le modèle, l’empreinte du contenu et l’utilisateur initiateur. Le jeton Meta et le texte complet ne sont pas enregistrés dans ce journal.

## 6. Test initial obligatoire

Commencer par un numéro de test autorisé et un modèle simple approuvé. Vérifier :

- l’acceptation par Meta et la présence du `wamid` ;
- la réception sur le téléphone destinataire ;
- les erreurs de modèle, de langue, de numéro et de jeton ;
- le refus lorsque le consentement est absent ou révoqué ;
- l’absence de nouvel envoi lorsqu’une même clé d’idempotence est rejouée.

L’intégration ne doit être considérée comme validée en production qu’après un test réel de réception sur un téléphone. Les contrôles CI ne peuvent pas remplacer ce test, car ils ne disposent pas des identifiants Meta de l’établissement.
