# WhatsApp — communication individuelle, par classe et multi-classes

## Fonctionnement commun

1. L'utilisateur choisit une année scolaire active, une ou plusieurs classes actives (maximum 20) et une finalité de consentement.
2. Clarodaro récupère les inscriptions actives de cette classe pour cette année.
3. Les parents sont retrouvés exclusivement via les relations existantes `student_parents`.
4. Un parent lié à plusieurs élèves de la même classe n'est présenté qu'une seule fois.
5. Seuls les parents avec un consentement `OPTED_IN` pour la finalité choisie sont proposés. Les autres sont exclus et comptabilisés.
6. Chaque destinataire est revalidé par le serveur juste avant sa préparation ou son envoi.

La sélection de classe ne crée aucune association parent-élève et ne modifie aucune inscription. Lorsqu'un parent a plusieurs enfants répartis dans plusieurs classes sélectionnées, il apparaît une seule fois.


## Mode 0 — depuis le nom d'un élève

- Les cellules Nom et Prénom de la liste des élèves ouvrent `/whatsapp-send.html?student_id=<uuid>`.
- L'API authentifiée recharge l'élève et les responsables depuis `student_parents`; le navigateur ne fournit jamais les numéros ni les associations comme source de vérité.
- La page présente chaque responsable lié, sa relation et son statut de consentement pour la finalité sélectionnée.
- Seuls les responsables avec un consentement actif et un numéro E.164 valide sont sélectionnables.
- L'utilisateur peut sélectionner un responsable ou plusieurs, puis préparer des liens WhatsApp ou lancer l'envoi Meta après confirmation.
- Un responsable sans consentement actif reste visible comme non admissible; il n'est jamais sélectionné automatiquement ni contacté.

## Mode 3 — diffusion à plusieurs classes

- Le sélecteur permet de cocher une à vingt classes pour une même année scolaire active.
- Le serveur vérifie que toutes les classes sélectionnées sont actives.
- Les parents sont dédupliqués sur l'ensemble des classes sélectionnées, pas seulement à l'intérieur d'une classe.
- Le récapitulatif indique le nombre de parents admissibles et le nombre de parents exclus faute de consentement actif.
- Modifier la sélection des classes invalide la liste des destinataires précédemment chargée; il faut recharger les destinataires avant un envoi.
- Le filtre de classe de la liste des élèves est alimenté par les classes actives de PostgreSQL et s'applique également à l'export Word.

## Mode 1 — préparation manuelle WhatsApp

- L'utilisateur rédige un message libre (jusqu'à 4 000 caractères).
- Clarodaro appelle `POST /api/whatsapp/manual-preparations.php` séparément pour chaque parent sélectionné.
- L'API revalide le consentement et enregistre une préparation d'audit par parent.
- L'interface affiche un lien WhatsApp individuel avec le numéro et le message prérempli.
- L'utilisateur ouvre chaque conversation, vérifie le destinataire et le texte, puis appuie lui-même sur Envoyer.

Une préparation journalisée ne signifie jamais que le message a été envoyé ou livré. Le texte apparaît dans l'URL WhatsApp; ne pas inclure d'informations médicales, disciplinaires ou financières sensibles.

## Mode 2 — envoi automatique via WhatsApp Business Platform

- L'utilisateur choisit un modèle approuvé Meta, sa langue et les paramètres communs du modèle.
- L'interface demande une confirmation explicite avec le nombre de destinataires.
- Clarodaro transmet les demandes une par une à `POST /api/whatsapp/send.php`, avec une clé d'idempotence distincte par parent.
- Le serveur revalide le consentement, vérifie que le modèle figure dans `WHATSAPP_ALLOWED_TEMPLATES`, conserve le jeton Meta côté serveur et journalise chaque tentative.
- Le bilan distingue les demandes acceptées par Meta des échecs. L'acceptation Meta ne prouve pas la livraison.

Le mode automatique reste indisponible si `WHATSAPP_SEND_ENABLED` n'est pas exactement `true`, si les secrets serveur sont incomplets ou si aucun modèle approuvé n'est autorisé. Aucun succès simulé n'est annoncé.

## Limites et précautions

- Les paramètres du modèle sont identiques pour tous les parents de la diffusion. La personnalisation par élève ou par parent est hors de ce périmètre.
- Les appels Meta sont séquentiels depuis la page ouverte; garder la page ouverte jusqu'au bilan final.
- En cas d'échec partiel, vérifier les journaux et les statuts WhatsApp Business avant toute nouvelle tentative.
- Les statuts `SENT`/acceptés par Meta ne signifient pas `DELIVERED`.
- Les tests CI n'envoient aucun message réel et utilisent une base PostgreSQL isolée.
- Aucune migration de base n'est nécessaire pour cette fonctionnalité; les tables de consentement et de préparation existantes sont réutilisées.
