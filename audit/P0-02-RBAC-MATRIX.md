# IMC-Clarodoro — P0-02 RBAC Permission Matrix

## Rôles identifiés

| Role | Source | Description |
|---|---|---|
| PDG | personnel.html (option) | Direction générale, accès complet |
| Directeur | personnel.html (option) | Direction académique |
| Enseignant | personnel.html (option) | Enseignement, gestion classes |
| Secrétaire | personnel.html (option) | Administration |
| Surveillant | personnel.html (option) | Surveillance |
| Autre | personnel.html (option) | Autre fonction |

## Permissions

| Permission | Resource | Action | Source |
|---|---|---|---|
| personnel.read | personnel | read | personnel.html |
| personnel.create | personnel | create | personnel.html |
| personnel.update | personnel | update | personnel.html |
| personnel.delete | personnel | delete | personnel.html |
| eleves.read | eleves | read | index.html |
| eleves.create | eleves | create | index.html |
| eleves.update | eleves | update | index.html |
| eleves.delete | eleves | delete | index.html |
| annees.read | annees | read | annees-scolaires.html |
| annees.create | annees | create | annees-scolaires.html |
| annees.update | annees | update | annees-scolaires.html |
| annees.delete | annees | delete | annees-scolaires.html |
| matieres.read | matieres | read | matieres.html |
| matieres.create | matieres | create | matieres.html |
| matieres.update | matieres | update | matieres.html |
| matieres.delete | matieres | delete | matieres.html |
| resultats.read | resultats | read | resultats.html |
| resultats.create | resultats | create | resultats.html |
| resultats.update | resultats | update | resultats.html |
| finances.read | finances | read | finances.html |
| finances.create | finances | create | finances.html |
| finances.update | finances | update | finances.html |
| finances.delete | finances | delete | finances.html |
| vacances.read | vacances | read | Vacances.html |
| vacances.create | vacances | create | Vacances.html |
| vacances.update | vacances | update | Vacances.html |
| vacances.delete | vacances | delete | Vacances.html |
| badge.read | badge | read | badge.html |
| badge.create | badge | create | badge.html |
| badge.print | badge | print | badge.html |
| paies.read | paies | read | PDG.html |
| paies.create | paies | create | PDG.html |
| paies.update | paies | update | PDG.html |
| depenses.read | depenses | read | PDG.html |
| depenses.create | depenses | create | PDG.html |
| depenses.delete | depenses | delete | PDG.html |
| vault.update | vault | update | secure-storage.js (P0-04-B) |

## Matrice RBAC

Basée sur l'analyse du code existant et la logique métier dérivée :

| Role | Permission | Allow/Deny | Justification |
|---|---|---|---|
| PDG | personnel.read | ALLOW | Gestion complète du personnel |
| PDG | personnel.create | ALLOW | Création comptes personnel |
| PDG | personnel.update | ALLOW | Modification comptes personnel |
| PDG | personnel.delete | ALLOW | Suppression comptes personnel |
| PDG | eleves.read | ALLOW | Accès complet élèves |
| PDG | eleves.create | ALLOW | Création dossiers élèves |
| PDG | eleves.update | ALLOW | Modification dossiers élèves |
| PDG | eleves.delete | ALLOW | Suppression dossiers élèves |
| PDG | annees.read | ALLOW | Gestion années scolaires |
| PDG | annees.create | ALLOW | Création années |
| PDG | annees.update | ALLOW | Modification années |
| PDG | annees.delete | ALLOW | Suppression années |
| PDG | matieres.read | ALLOW | Gestion matières |
| PDG | matieres.create | ALLOW | Création matières |
| PDG | matieres.update | ALLOW | Modification matières |
| PDG | matieres.delete | ALLOW | Suppression matières |
| PDG | resultats.read | ALLOW | Accès résultats |
| PDG | resultats.create | ALLOW | Saisie résultats |
| PDG | resultats.update | ALLOW | Modification résultats |
| PDG | finances.read | ALLOW | Accès finances complet |
| PDG | finances.create | ALLOW | Création données financières |
| PDG | finances.update | ALLOW | Modification données financières |
| PDG | finances.delete | ALLOW | Suppression données financières |
| PDG | vacances.read | ALLOW | Gestion vacances |
| PDG | vacances.create | ALLOW | Création événements |
| PDG | vacances.update | ALLOW | Modification événements |
| PDG | vacances.delete | ALLOW | Suppression événements |
| PDG | badge.read | ALLOW | Gestion badges |
| PDG | badge.create | ALLOW | Création badges |
| PDG | badge.print | ALLOW | Impression badges |
| PDG | paies.read | ALLOW | Gestion paies |
| PDG | paies.create | ALLOW | Création paies |
| PDG | paies.update | ALLOW | Modification paies |
| PDG | depenses.read | ALLOW | Gestion dépenses |
| PDG | depenses.create | ALLOW | Création dépenses |
| PDG | depenses.delete | ALLOW | Suppression dépenses |
| PDG | vault.update | ALLOW | Modification code vault (P0-04-B) |
| Directeur | personnel.read | ALLOW | Lecture personnel |
| Directeur | personnel.create | DENY | Réservé PDG |
| Directeur | personnel.update | DENY | Réservé PDG |
| Directeur | personnel.delete | DENY | Réservé PDG |
| Directeur | eleves.read | ALLOW | Lecture élèves |
| Directeur | eleves.create | ALLOW | Création dossiers |
| Directeur | eleves.update | ALLOW | Modification dossiers |
| Directeur | eleves.delete | DENY | Réservé PDG |
| Directeur | annees.read | ALLOW | Lecture années |
| Directeur | annees.create | DENY | Réservé PDG |
| Directeur | annees.update | DENY | Réservé PDG |
| Directeur | annees.delete | DENY | Réservé PDG |
| Directeur | matieres.read | ALLOW | Lecture matières |
| Directeur | matieres.create | DENY | Réservé PDG |
| Directeur | matieres.update | DENY | Réservé PDG |
| Directeur | matieres.delete | DENY | Réservé PDG |
| Directeur | resultats.read | ALLOW | Lecture résultats |
| Directeur | resultats.create | ALLOW | Saisie résultats |
| Directeur | resultats.update | ALLOW | Modification résultats |
| Directeur | finances.read | ALLOW | Lecture finances |
| Directeur | finances.create | DENY | Réservé PDG |
| Directeur | finances.update | DENY | Réservé PDG |
| Directeur | finances.delete | DENY | Réservé PDG |
| Directeur | vacances.read | ALLOW | Lecture vacances |
| Directeur | vacances.create | DENY | Réservé PDG |
| Directeur | vacances.update | DENY | Réservé PDG |
| Directeur | vacances.delete | DENY | Réservé PDG |
| Directeur | badge.read | ALLOW | Lecture badges |
| Directeur | badge.create | DENY | Réservé PDG |
| Directeur | badge.print | ALLOW | Impression badges |
| Directeur | paies.read | DENY | Réservé PDG |
| Directeur | paies.create | DENY | Réservé PDG |
| Directeur | paies.update | DENY | Réservé PDG |
| Directeur | depenses.read | DENY | Réservé PDG |
| Directeur | depenses.create | DENY | Réservé PDG |
| Directeur | depenses.delete | DENY | Réservé PDG |
| Directeur | vault.update | DENY | Réservé PDG (P0-04-B) |
| Enseignant | personnel.read | DENY | Réservé direction |
| Enseignant | personnel.create | DENY | Réservé PDG |
| Enseignant | personnel.update | DENY | Réservé PDG |
| Enseignant | personnel.delete | DENY | Réservé PDG |
| Enseignant | eleves.read | ALLOW | Lecture élèves sa classe |
| Enseignant | eleves.create | DENY | Réservé direction |
| Enseignant | eleves.update | DENY | Réservé direction |
| Enseignant | eleves.delete | DENY | Réservé PDG |
| Enseignant | annees.read | ALLOW | Lecture années |
| Enseignant | annees.create | DENY | Réservé PDG |
| Enseignant | annees.update | DENY | Réservé PDG |
| Enseignant | annees.delete | DENY | Réservé PDG |
| Enseignant | matieres.read | ALLOW | Lecture matières |
| Enseignant | matieres.create | DENY | Réservé PDG |
| Enseignant | matieres.update | DENY | Réservé PDG |
| Enseignant | matieres.delete | DENY | Réservé PDG |
| Enseignant | resultats.read | ALLOW | Lecture résultats |
| Enseignant | resultats.create | ALLOW | Saisie résultats sa classe |
| Enseignant | resultats.update | ALLOW | Modification résultats sa classe |
| Enseignant | finances.read | DENY | Réservé PDG |
| Enseignant | finances.create | DENY | Réservé PDG |
| Enseignant | finances.update | DENY | Réservé PDG |
| Enseignant | finances.delete | DENY | Réservé PDG |
| Enseignant | vacances.read | ALLOW | Lecture vacances |
| Enseignant | vacances.create | DENY | Réservé PDG |
| Enseignant | vacances.update | DENY | Réservé PDG |
| Enseignant | vacances.delete | DENY | Réservé PDG |
| Enseignant | badge.read | DENY | Réservé direction |
| Enseignant | badge.create | DENY | Réservé PDG |
| Enseignant | badge.print | DENY | Réservé direction |
| Enseignant | paies.read | DENY | Réservé PDG |
| Enseignant | paies.create | DENY | Réservé PDG |
| Enseignant | paies.update | DENY | Réservé PDG |
| Enseignant | depenses.read | DENY | Réservé PDG |
| Enseignant | depenses.create | DENY | Réservé PDG |
| Enseignant | depenses.delete | DENY | Réservé PDG |
| Enseignant | vault.update | DENY | Réservé PDG (P0-04-B) |
| Secrétaire | personnel.read | ALLOW | Lecture personnel |
| Secrétaire | personnel.create | DENY | Réservé PDG |
| Secrétaire | personnel.update | DENY | Réservé PDG |
| Secrétaire | personnel.delete | DENY | Réservé PDG |
| Secrétaire | eleves.read | ALLOW | Lecture élèves |
| Secrétaire | eleves.create | ALLOW | Création dossiers |
| Secrétaire | eleves.update | ALLOW | Modification dossiers |
| Secrétaire | eleves.delete | DENY | Réservé PDG |
| Secrétaire | annees.read | ALLOW | Lecture années |
| Secrétaire | annees.create | DENY | Réservé PDG |
| Secrétaire | annees.update | DENY | Réservé PDG |
| Secrétaire | annees.delete | DENY | Réservé PDG |
| Secrétaire | matieres.read | ALLOW | Lecture matières |
| Secrétaire | matieres.create | DENY | Réservé PDG |
| Secrétaire | matieres.update | DENY | Réservé PDG |
| Secrétaire | matieres.delete | DENY | Réservé PDG |
| Secrétaire | resultats.read | DENY | Réservé enseignement |
| Secrétaire | resultats.create | DENY | Réservé enseignement |
| Secrétaire | resultats.update | DENY | Réservé enseignement |
| Secrétaire | finances.read | ALLOW | Lecture finances |
| Secrétaire | finances.create | DENY | Réservé PDG |
| Secrétaire | finances.update | DENY | Réservé PDG |
| Secrétaire | finances.delete | DENY | Réservé PDG |
| Secrétaire | vacances.read | ALLOW | Lecture vacances |
| Secrétaire | vacances.create | DENY | Réservé PDG |
| Secrétaire | vacances.update | DENY | Réservé PDG |
| Secrétaire | vacances.delete | DENY | Réservé PDG |
| Secrétaire | badge.read | ALLOW | Lecture badges |
| Secrétaire | badge.create | DENY | Réservé PDG |
| Secrétaire | badge.print | ALLOW | Impression badges |
| Secrétaire | paies.read | DENY | Réservé PDG |
| Secrétaire | paies.create | DENY | Réservé PDG |
| Secrétaire | paies.update | DENY | Réservé PDG |
| Secrétaire | depenses.read | DENY | Réservé PDG |
| Secrétaire | depenses.create | DENY | Réservé PDG |
| Secrétaire | depenses.delete | DENY | Réservé PDG |
| Secrétaire | vault.update | DENY | Réservé PDG (P0-04-B) |
| Surveillant | personnel.read | DENY | Réservé direction |
| Surveillant | personnel.create | DENY | Réservé PDG |
| Surveillant | personnel.update | DENY | Réservé PDG |
| Surveillant | personnel.delete | DENY | Réservé PDG |
| Surveillant | eleves.read | ALLOW | Lecture élèves |
| Surveillant | eleves.create | DENY | Réservé direction |
| Surveillant | eleves.update | DENY | Réservé direction |
| Surveillant | eleves.delete | DENY | Réservé PDG |
| Surveillant | annees.read | ALLOW | Lecture années |
| Surveillant | annees.create | DENY | Réservé PDG |
| Surveillant | annees.update | DENY | Réservé PDG |
| Surveillant | annees.delete | DENY | Réservé PDG |
| Surveillant | matieres.read | ALLOW | Lecture matières |
| Surveillant | matieres.create | DENY | Réservé PDG |
| Surveillant | matieres.update | DENY | Réservé PDG |
| Surveillant | matieres.delete | DENY | Réservé PDG |
| Surveillant | resultats.read | DENY | Réservé enseignement |
| Surveillant | resultats.create | DENY | Réservé enseignement |
| Surveillant | resultats.update | DENY | Réservé enseignement |
| Surveillant | finances.read | DENY | Réservé PDG |
| Surveillant | finances.create | DENY | Réservé PDG |
| Surveillant | finances.update | DENY | Réservé PDG |
| Surveillant | finances.delete | DENY | Réservé PDG |
| Surveillant | vacances.read | ALLOW | Lecture vacances |
| Surveillant | vacances.create | DENY | Réservé PDG |
| Surveillant | vacances.update | DENY | Réservé PDG |
| Surveillant | vacances.delete | DENY | Réservé PDG |
| Surveillant | badge.read | DENY | Réservé direction |
| Surveillant | badge.create | DENY | Réservé PDG |
| Surveillant | badge.print | DENY | Réservé direction |
| Surveillant | paies.read | DENY | Réservé PDG |
| Surveillant | paies.create | DENY | Réservé PDG |
| Surveillant | paies.update | DENY | Réservé PDG |
| Surveillant | depenses.read | DENY | Réservé PDG |
| Surveillant | depenses.create | DENY | Réservé PDG |
| Surveillant | depenses.delete | DENY | Réservé PDG |
| Surveillant | vault.update | DENY | Réservé PDG (P0-04-B) |
| Autre | personnel.read | DENY | Accès limité |
| Autre | personnel.create | DENY | Réservé PDG |
| Autre | personnel.update | DENY | Réservé PDG |
| Autre | personnel.delete | DENY | Réservé PDG |
| Autre | eleves.read | DENY | Accès limité |
| Autre | eleves.create | DENY | Réservé direction |
| Autre | eleves.update | DENY | Réservé direction |
| Autre | eleves.delete | DENY | Réservé PDG |
| Autre | annees.read | ALLOW | Lecture années |
| Autre | annees.create | DENY | Réservé PDG |
| Autre | annees.update | DENY | Réservé PDG |
| Autre | annees.delete | DENY | Réservé PDG |
| Autre | matieres.read | ALLOW | Lecture matières |
| Autre | matieres.create | DENY | Réservé PDG |
| Autre | matieres.update | DENY | Réservé PDG |
| Autre | matieres.delete | DENY | Réservé PDG |
| Autre | resultats.read | DENY | Réservé enseignement |
| Autre | resultats.create | DENY | Réservé enseignement |
| Autre | resultats.update | DENY | Réservé enseignement |
| Autre | finances.read | DENY | Réservé PDG |
| Autre | finances.create | DENY | Réservé PDG |
| Autre | finances.update | DENY | Réservé PDG |
| Autre | finances.delete | DENY | Réservé PDG |
| Autre | vacances.read | ALLOW | Lecture vacances |
| Autre | vacances.create | DENY | Réservé PDG |
| Autre | vacances.update | DENY | Réservé PDG |
| Autre | vacances.delete | DENY | Réservé PDG |
| Autre | badge.read | DENY | Réservé direction |
| Autre | badge.create | DENY | Réservé PDG |
| Autre | badge.print | DENY | Réservé direction |
| Autre | paies.read | DENY | Réservé PDG |
| Autre | paies.create | DENY | Réservé PDG |
| Autre | paies.update | DENY | Réservé PDG |
| Autre | depenses.read | DENY | Réservé PDG |
| Autre | depenses.create | DENY | Réservé PDG |
| Autre | depenses.delete | DENY | Réservé PDG |
| Autre | vault.update | DENY | Réservé PDG (P0-04-B) |

## Actions critiques

| Action | Permission requise | Protection |
|---|---|---|
| supprimerPersonnel | personnel.delete | P0 - Destruction |
| supprimerEleve | eleves.delete | P0 - Destruction |
| supprimerAnnee | annees.delete | P0 - Destruction |
| supprimerMatiere | matieres.delete | P0 - Destruction |
| supprimerDepense | depenses.delete | P0 - Destruction financière |
| supprimerVersement | finances.delete | P0 - Destruction financière |
| supprimerEvenement | vacances.delete | P1 - Destruction |
| enregistrerPaie | paies.create | P0 - Action financière |
| enregistrerVersement | finances.create | P0 - Action financière |
| ajouterDepense | depenses.create | P0 - Action financière |
| ajouterPersonnel | personnel.create | P0 - Gestion comptes |
| imprimerBadge | badge.print | P1 - Impression |
| imprimerFiche | finances.print | P1 - Impression financière |
| imprimerDossier | eleves.print | P1 - Impression |
| exporterWord | eleves.export | P1 - Export |

## Limites client-side

Cette matrice RBAC est une protection logique côté client.

**Limites fondamentales :**
- Le rôle est stocké dans sessionStorage
- sessionStorage peut être modifié par le propriétaire du navigateur
- Un utilisateur malveillant peut tenter de modifier sa session
- JavaScript peut être modifié via DevTools
- Aucune validation serveur n'existe

**Recommandations :**
- Considérer cette RBAC comme une couche de protection UI/logique
- Ne pas s'y fier pour une véritable sécurité des données
- Pour une véritable sécurité, une implémentation serveur est nécessaire
- Les données sensibles doivent rester dans le coffre chiffré

**Note :** Cette intervention P0-02 améliore l'architecture d'autorisation mais ne résout pas la limitation fondamentale d'une architecture purement client-side.