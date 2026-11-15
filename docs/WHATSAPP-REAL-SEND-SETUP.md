# WhatsApp réel — Meta WhatsApp Business Cloud API

Clarodaro propose deux modes complémentaires sur la page `/whatsapp-send.html` :

- **Envoi manuel** : Clarodaro revérifie le consentement et journalise la préparation, puis ouvre `wa.me` avec le numéro et le texte préremplis. L’utilisateur vérifie le destinataire et appuie lui-même sur Envoyer dans WhatsApp. La préparation journalisée ne prouve pas que le message a été envoyé.
- **Envoi réel via Meta** : le serveur Clarodaro transmet un modèle approuvé à l’API officielle Meta WhatsApp Business Cloud API. Ce mode ne dépend pas de l’application WhatsApp installée sur le poste et ne simule jamais un succès.

Les deux modes sont présentés séparément dans la même page et exigent un consentement actif pour la finalité sélectionnée. Le mode manuel prépare un message pour un parent choisi individuellement; les messages concernant un élève doivent passer par l'envoi Meta multi-destinataires afin d'appliquer automatiquement la règle mineur/majeur et de joindre tous les responsables consentants.

## 1. Prérequis Meta

Avant de configurer Clarodaro, l’établissement doit disposer de :

- un portefeuille Meta Business et une application Meta ;
- un compte WhatsApp Business (WABA) associé à l’application ;
- un numéro professionnel enregistré et activé pour WhatsApp Business Platform ;
- le **Phone Number ID** du numéro d’envoi (ce n’est pas le numéro de téléphone visible) ;
- un jeton d’accès permanent ou de longue durée avec les autorisations WhatsApp Business requises, notamment `whatsapp_business_messaging` ;
- au moins un modèle de message approuvé par Meta, avec sa langue exacte ;
- le consentement WhatsApp explicite de chaque personne destinataire (parent/responsable, élève majeur, membre du personnel ou enseignant) pour la finalité concernée.

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
WHATSAPP_APP_SECRET=SECRET_APPLICATION_META
WHATSAPP_WEBHOOK_VERIFY_TOKEN=JETON_VERIFICATION_WEBHOOK
```

Remplacer `vXX.X` par une version Graph API actuellement prise en charge par Meta, et les noms d’exemple par les noms exacts des modèles approuvés. Ne pas ajouter de guillemets autour des valeurs sauf nécessité particulière.

Après modification du fichier, redémarrer le serveur PHP / la tâche planifiée Clarodaro afin que les nouvelles variables soient chargées. Conserver le fichier dans ProgramData lors des mises à jour de l’application.

## 3. Utilisation dans Clarodaro

1. Ouvrir **WhatsApp — envoi réel** avec un compte autorisé.
2. Vérifier que l’état de configuration affiche « Configuration prête ».
3. Choisir le type de destinataire et rechercher la personne dans Clarodaro.
4. Pour un élève, choisir le message personnel ou celui qui concerne aussi les parents. Le serveur impose les règles d'âge : mineur = responsables uniquement; majeur personnel = élève uniquement; majeur familial = élève et responsables consentants. Une date de naissance absente est traitée comme mineur.
5. Choisir la finalité correspondant au consentement actif.
6. Choisir un modèle approuvé et sa langue exacte.
7. Saisir les paramètres du corps dans l’ordre défini par le modèle, un par ligne.
8. Cliquer sur **Envoyer réellement via WhatsApp**.

La section **Gérer les consentements WhatsApp** permet d'enregistrer ou de retirer le consentement et le numéro E.164 pour les parents, élèves, personnel et enseignants. La source du consentement est obligatoire pour activer un consentement. Le téléphone présent dans un dossier scolaire n'est pas, à lui seul, une preuve de consentement.

Pour le mode Meta, le serveur vérifie la permission, le consentement actif et la finalité, applique une clé d’idempotence, journalise la demande, puis appelle l’endpoint Meta `/{PHONE_NUMBER_ID}/messages`. Aucun envoi n’est déclenché si la configuration est absente, si le modèle n’est pas autorisé ou si le consentement n’est pas actif.

## 4. Fenêtre de conversation et modèles

Pour les messages initiés par l’établissement en dehors de la fenêtre de service client autorisée par Meta, il faut utiliser un modèle approuvé. Clarodaro n’envoie pas de texte libre arbitraire à la place d’un modèle. Les paramètres fournis doivent correspondre exactement aux variables déclarées dans le modèle Meta.

Les finalités de consentement prises en charge actuellement sont : `ATTENDANCE`, `RESULTS_AVAILABLE`, `PAYMENT_REMINDER` et `GENERAL`. Le consentement est vérifié côté serveur à chaque envoi.

## 5. Résultat et limites de confirmation

- **Demande acceptée par Meta** : Meta a accepté la requête et renvoyé un identifiant de message.
- **Livraison** : elle n’est pas garantie par la réponse d’acceptation. Elle doit être confirmée par les statuts du compte WhatsApp Business / Meta.
- **Échec** : Clarodaro journalise l’échec et affiche le code d’erreur fournisseur disponible.
- **Configuration absente** : la page bloque l’envoi et l’API retourne une erreur. Aucun mode simulation n’est utilisé.

Le journal `whatsapp_recipient_message_log` conserve un statut par destinataire (`PROCESSING`, `SENT`, `DELIVERED`, `READ`, `FAILED`), l'identifiant fournisseur, la finalité, le modèle, l'empreinte du contenu et l'utilisateur initiateur. Le jeton Meta et le texte complet ne sont pas enregistrés. La page affiche l'historique si le compte possède `whatsapp.message.audit`.

Le webhook `/api/whatsapp/webhook.php` doit être déclaré dans l'application Meta. Il utilise `WHATSAPP_WEBHOOK_VERIFY_TOKEN` pour la vérification initiale et `WHATSAPP_APP_SECRET` pour valider `X-Hub-Signature-256`. Il déduplique les statuts reçus et fait évoluer les journaux jusqu'à `DELIVERED` ou `READ`. Le corps brut du webhook n'est pas conservé.

## 6. Test initial obligatoire

Commencer par un numéro de test autorisé et un modèle simple approuvé. Vérifier :

- l’acceptation par Meta et la présence du `wamid` ;
- la réception sur le téléphone destinataire ;
- les erreurs de modèle, de langue, de numéro et de jeton ;
- le refus lorsque le consentement est absent ou révoqué ;
- le routage d'un élève mineur vers tous les responsables consentants ;
- le routage d'un élève majeur en message personnel et en message familial ;
- la réception des statuts Meta `delivered` et `read` dans l'historique ;
- l’absence de nouvel envoi lorsqu’une même clé d’idempotence est rejouée.

L’intégration ne doit être considérée comme validée en production qu’après un test réel de réception sur un téléphone. Les contrôles CI ne peuvent pas remplacer ce test, car ils ne disposent pas des identifiants Meta de l’établissement.
