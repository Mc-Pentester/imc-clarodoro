# Audit statique des flux métier pour WhatsApp

## Statut et périmètre

Audit de lecture du code versionné sur `main`, sans connexion à PostgreSQL, sans exécution de code, sans migration et sans appel à Meta.

Fichiers examinés :
- `config/auth.php`
- `api/attendance/index.php`
- `api/grades/index.php`
- `api/results/index.php`
- `api/finance/index.php`
- `database/schema.sql`

Ce document décrit les chemins observés dans ces fichiers. Il ne prouve pas que le schéma déployé ou les données locales sont identiques.

## Résumé exécutif

**Conclusion : aucun déclencheur automatique WhatsApp fiable n'est démontré par les flux examinés.** Les routes observées servent à lire ou modifier les données métier et renvoient une réponse HTTP. Elles ne montrent pas de mécanisme de publication/validation qui autoriserait à lui seul l'envoi d'un message à un parent.

L'authentification serveur, les permissions RBAC et la vérification CSRF sont disponibles dans `config/auth.php` et utilisées sur les mutations examinées. Elles constituent une base utile, mais elles ne remplacent ni le consentement du destinataire ni la vérification du lien parent-élève pour chaque message.

## Constats par catégorie

### 1. Absences et retards

Dans `api/attendance/index.php` :
- lecture protégée par `presences.read` ;
- création par `presences.create` et modification/suppression par `presences.update` ;
- jeton CSRF exigé sur les mutations ;
- l'enregistrement est rattaché à `enrollment_id`, puis à l'élève via `enrollments` ;
- les statuts acceptés sont `PRESENT`, `ABSENT`, `LATE`, `EXCUSED`.

**Limite WhatsApp :** une absence peut être créée, modifiée ou supprimée. Le code examiné ne distingue pas une absence définitivement validée d'une saisie provisoire et ne montre pas d'événement d'envoi durable avec anti-doublon. Un envoi immédiat lors d'une création pourrait notifier une absence saisie par erreur, puis envoyer des informations contradictoires après correction.

**À définir avant automatisation :** règle de confirmation, délai éventuel, traitement des corrections/suppressions et clé d'idempotence fondée sur l'inscription, la date et le type d'événement.

### 2. Notes et bulletins

Dans `api/grades/index.php` :
- les notes sont lues et modifiées via une API protégée par `resultats.read`, `resultats.create` et `resultats.update` ;
- les écritures exigent un jeton CSRF ;
- les notes sont rattachées à une inscription et une matière ;
- les notes peuvent être modifiées ou supprimées.

Dans `api/results/index.php` :
- `result_carnets` est lu par inscription ;
- les champs du carnet sont créés ou remplacés par `PUT/PATCH` ;
- le modèle observé contient les commentaires du carnet, mais aucun état de publication explicite.

**Limite WhatsApp :** ni l'ajout d'une note ni la sauvegarde du carnet ne prouvent que le bulletin est final, contrôlé et publiable. Une notification automatique déclenchée par une simple écriture serait prématurée et pourrait être répétée.

**À définir avant automatisation :** qui publie, comment la publication est enregistrée, si elle peut être annulée, et comment une version déjà envoyée est corrigée. Le premier périmètre doit notifier qu'un bulletin est disponible plutôt que transmettre des notes détaillées, jusqu'à validation des règles de confidentialité et d'autorisation.

### 3. Factures et paiements

Dans `api/finance/index.php` :
- la lecture et les mutations sont protégées par les permissions `finances.*` ;
- la création de paiement verrouille la facture dans une transaction, vérifie le solde, insère le paiement puis actualise le statut de la facture ;
- un paiement peut également être supprimé, avec recalcul du statut de la facture ;
- les factures ont des statuts tels que `OPEN`, `PARTIALLY_PAID`, `PAID`, `CANCELLED`, `ARCHIVED`.

**Limite WhatsApp :** le solde est calculé à partir des factures et paiements courants. Une facture peut changer de statut et un paiement peut être supprimé. Il faut donc recalculer le solde au moment de préparer le message et ne pas utiliser un ancien contenu de rappel. Les routes examinées ne montrent pas de file d'envoi transactionnelle ni de journal d'événement de notification.

**À définir avant automatisation :** règle de rappel (échéance, délai de grâce, fréquence, plafond), exclusion des factures annulées/archivées, recalcul du solde juste avant envoi, et annulation des rappels devenus obsolètes.

### 4. Relation parent-élève et numéro

Le schéma versionné définit `students`, `parents` et `student_parents`, avec une relation plusieurs-à-plusieurs. Le téléphone de `parents` peut être nul ; `students.phone` ne prouve pas qu'il s'agit du téléphone du responsable.

**Conséquence :** le destinataire doit être résolu côté serveur à partir d'une relation parent-élève autorisée. Le numéro envoyé par le navigateur ne doit pas faire autorité. Ne pas utiliser automatiquement le téléphone de l'élève comme repli.

Le code examiné ne démontre pas encore de parcours complet d'administration du consentement WhatsApp ou de désinscription.

### 5. Sécurité et permissions

`config/auth.php` :
- démarre une session avec cookie HttpOnly et SameSite=Lax ;
- applique des délais d'inactivité et absolu ;
- vérifie l'utilisateur actif et la permission nommée ;
- fournit une vérification CSRF par en-tête `X-CSRF-Token`.

Les routes examinées utilisent ces contrôles sur les opérations de mutation. Pour le futur module WhatsApp, il faudra ajouter les permissions dédiées, les vérifier côté serveur et conserver CSRF sur chaque mutation. L'accès aux journaux d'envoi doit être distinct de l'autorisation d'envoyer.

## Modèle fonctionnel recommandé avant tout code d'envoi

1. **Consentement** : enregistrer le destinataire, la portée du consentement, la date, la source, l'acteur ayant enregistré l'information et le retrait éventuel. Bloquer si l'état est absent, ambigu ou retiré.
2. **Événement métier** : créer une notion explicite de validation/publication ou de rappel éligible, au lieu d'envoyer à chaque mutation CRUD.
3. **Outbox/journal** : enregistrer la demande de notification dans la même transaction que l'événement métier quand c'est possible ; utiliser une clé unique d'idempotence.
4. **Vérification juste avant l'envoi** : relation parent-élève, consentement actif, numéro valide, statut métier toujours éligible, absence de désinscription et permission de l'initiateur.
5. **Confidentialité** : limiter le contenu ; ne pas inclure notes, commentaires sensibles ou montants détaillés tant que la politique de communication et l'identité du destinataire ne sont pas validées.
6. **Désactivation par défaut** : simulation sans appel réseau, tests de sécurité et validation humaine avant tout envoi réel.

## Priorités de suite

- **P0 — contrat métier :** définir les règles de publication du bulletin, de confirmation d'absence et de rappel de paiement.
- **P0 — consentement :** décider si le consentement est par numéro, par parent, par élève-parent et/ou par catégorie de notification.
- **P1 — conception de données :** préparer une migration additive séparée pour consentements et journal/outbox, après confirmation du schéma réel.
- **P1 — tests :** tests unitaires et d'intégration pour RBAC, CSRF, périmètre parent-élève, retrait de consentement, anti-doublon, correction d'événement et recalcul de solde.
- **P2 — intégration Meta :** seulement après validation des étapes précédentes et de la configuration hors dépôt.

## Limites explicites

- Aucun accès à la base PostgreSQL réelle.
- Aucune validation de la qualité des numéros ou des relations enregistrées.
- Aucun envoi WhatsApp.
- Aucune migration écrite ou exécutée dans cette étape.
- Les politiques Meta doivent être revalidées au moment de l'activation. La politique WhatsApp Business exige notamment le consentement préalable et le respect des demandes de désinscription ; les conversations initiées par l'entreprise nécessitent les modèles approuvés applicables.
