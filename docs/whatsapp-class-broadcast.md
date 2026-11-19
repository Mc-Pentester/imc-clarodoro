# WhatsApp — diffusion aux parents d'une classe

## Fonctionnement commun

1. L'utilisateur choisit une année scolaire active, une classe active et une finalité de consentement.
2. Clarodaro récupère les inscriptions actives de cette classe pour cette année.
3. Les parents sont retrouvés exclusivement via les relations existantes `student_parents`.
4. Un parent lié à plusieurs élèves de la même classe n'est présenté qu'une seule fois.
5. Seuls les parents avec un consentement `OPTED_IN` pour la finalité choisie sont proposés. Les autres sont exclus et comptabilisés.
6. Chaque destinataire est revalidé par le serveur juste avant sa préparation ou son envoi.

La sélection de classe ne crée aucune association parent-élève et ne modifie aucune inscription.

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
