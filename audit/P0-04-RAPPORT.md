# IMC-Clarodoro — P0-04
# Vault Forensic + Rotation du code/PIN

## 1. Contexte

**Objectif :** Permettre à l'utilisateur autorisé de changer le code/PIN utilisé pour déverrouiller le coffre-fort, sans perte de données et sans exposer ce code.

**Projet :** C:\IMC-Clarodoro-securise-client\IMC-Clarodoro

**Architecture :** Application client-side HTML/CSS/JavaScript avec secure-storage.js (coffre-fort cryptographique) et auth.js (authentification + session + RBAC)

**État antérieur :** P0-01 (GLOBAL AUTH GATE + SESSION) — PASS, P0-02 (RBAC) — PASS, P0-02-B (branding) — traité, P0-03 (CREATE / UPDATE RBAC) — PASS avec gap badge.create

## 2. Fichiers audités

**Fichiers principaux :**
- secure-storage.js (374 lignes)
- auth.js (326 lignes)

**Fichiers HTML audités :**
- index.html
- personnel.html
- PDG.html
- finances.html
- badge.html
- resultats.html
- annees-scolaires.html
- matieres.html
- Vacances.html

**Autres fichiers :**
- app.js
- style.css

## 3. Architecture cryptographique actuelle

### Algorithme de chiffrement :
**AES-GCM** (Advanced Encryption Standard - Galois/Counter Mode)

### Mode :
**GCM** (Galois/Counter Mode) avec authentification intégrée

### Longueur de clé :
**256 bits** (AES-256)

### Algorithme de dérivation :
**PBKDF2** (Password-Based Key Derivation Function 2)

### Nombre d'itérations :
**600,000 itérations** (constante ITERATIONS)

### Salt :
**16 octets aléatoires** générés avec `crypto.getRandomValues(new Uint8Array(16))`

### IV/nonce :
**12 octets aléatoires** générés avec `crypto.getRandomValues(new Uint8Array(12))` pour chaque chiffrement

### Format du payload :
```javascript
{
  id: "main",
  version: 1,
  iterations: 600000,
  salt: "base64_encoded_salt",
  iv: "base64_encoded_iv",
  ciphertext: "base64_encoded_ciphertext"
}
```

### Stockage du salt :
**Dans l'enregistrement IndexedDB** (champ `salt` en base64)

### Stockage de l'IV :
**Dans l'enregistrement IndexedDB** (champ `iv` en base64)

### Stockage des données chiffrées :
**IndexedDB** - Base de données `imc_clarodoro_secure_v1`, Store `vault`, Record `main`

### Gestion de la clé en mémoire :
**Variable locale `sessionKey`** - jamais persistée, détruite au lock/refresh

### Durée de vie de la clé :
**Temporaire en mémoire** - existe uniquement pendant la session déverrouillée (15 minutes idle timeout)

### Procédure actuelle de lock :
```javascript
function verrouiller() {
    sessionKey = null;
    vaultData = Object.create(null);
    vaultReady = false;
    window.location.reload();
}
```

### Procédure actuelle d'unlock :
```javascript
1. Demande du mot de passe via window.prompt()
2. Dérivation de clé avec PBKDF2 (600,000 itérations)
3. Tentative de déchiffrement du vault
4. Si succès : vaultReady = true, déclenchement event "imc-vault-unlocked"
5. Si échec : 3 tentatives autorisées, puis erreur
```

## 4. Cartographie du stockage

### Données protégées par le vault (SENSITIVE_KEYS) :
| Storage key | Donnée | Chiffrée | Lecture | Écriture |
|-------------|--------|----------|---------|----------|
| imc_students | Élèves | OUI | IMCSecureStorage.getItem() | IMCSecureStorage.setItem() |
| imc_finances | Finances | OUI | IMCSecureStorage.getItem() | IMCSecureStorage.setItem() |
| imc_tarifs | Tarifs | OUI | IMCSecureStorage.getItem() | IMCSecureStorage.setItem() |
| imc_personnel | Personnel | OUI | IMCSecureStorage.getItem() | IMCSecureStorage.setItem() |
| imc_presences | Présences | OUI | IMCSecureStorage.getItem() | IMCSecureStorage.setItem() |
| imc_resultats | Résultats | OUI | IMCSecureStorage.getItem() | IMCSecureStorage.setItem() |
| imc_depenses | Dépenses | OUI | IMCSecureStorage.getItem() | IMCSecureStorage.setItem() |
| imc_paies_personnel | Paies personnel | OUI | IMCSecureStorage.getItem() | IMCSecureStorage.setItem() |
| imc_pdg_password_hash | Hash PDG | OUI | IMCSecureStorage.getItem() | IMCSecureStorage.setItem() |

### Données non chiffrées (localStorage direct) :
| Storage key | Donnée | Chiffrée | Lecture | Écriture |
|-------------|--------|----------|---------|----------|
| imc_annees | Années scolaires | NON | localStorage.getItem() | localStorage.setItem() |
| imc_annee_active | Année active | NON | localStorage.getItem() | localStorage.setItem() |
| imc_matieres | Matières | NON | localStorage.getItem() | localStorage.setItem() |
| imc_pdg_password | Mot de passe PDG (legacy) | NON | localStorage.getItem() | localStorage.setItem() |
| clés de configuration diverses | Préférences | NON | localStorage.getItem() | localStorage.setItem() |

### Données de session (sessionStorage) :
| Storage key | Donnée | Chiffrée | Lecture | Écriture |
|-------------|--------|----------|---------|----------|
| imc_auth_session | Session auth | NON | sessionStorage.getItem() | sessionStorage.setItem() |

## 5. Mécanisme actuel d'unlock

**Fonction principale :** `initialiserCoffre()`

**Processus :**
1. Ouverture de la base IndexedDB
2. Lecture de l'enregistrement "main"
3. Si record inexistant : initialisation avec création de mot de passe
4. Si record existant : boucle de 3 tentatives de déverrouillage
5. Pour chaque tentative :
   - Demande du mot de passe via `window.prompt()`
   - Conversion du salt de base64 vers bytes
   - Dérivation de clé avec `deriveKey(password, salt)`
   - Tentative de déchiffrement avec `dechiffrer(record, sessionKey)`
   - Si succès : `vaultReady = true`, déclenchement event
   - Si échec : message d'erreur, réinitialisation des variables

**État de déverrouillage :** Variable `vaultReady` + event `imc-vault-unlocked`

## 6. Mécanisme actuel de lock

**Fonction principale :** `verrouiller()`

**Processus :**
1. Vérification de `vaultReady`
2. Destruction de `sessionKey` (mise à null)
3. Destruction de `vaultData` (réinitialisation)
4. Mise à `false` de `vaultReady`
5. Rechargement de la page (`window.location.reload()`)

**Lock automatique :** Timeout de 15 minutes d'inactivité via `reinitialiserVerrouillageAutomatique()`

## 7. Protection du secret

**État actuel :**
- Le mot de passe n'est jamais stocké en clair
- Le mot de passe n'est jamais persisté
- La clé dérivée (`sessionKey`) n'est jamais persistée
- La clé existe uniquement en mémoire temporaire
- Le mot de passe est saisi via `window.prompt()` (mécanisme natif)
- Aucune log du mot de passe ou de la clé dans le code actuel

**Risques identifiés :**
- Le mot de passe existe temporairement en mémoire pendant la saisie
- `window.prompt()` ne garantit pas la sécurité de la saisie
- La clé en mémoire peut théoriquement être extraite par un attaquant ayant accès à la mémoire du navigateur

## 8. Conception de la rotation

**Architecture proposée :**

```text
1. Vérification prérequis
   - Session IMCAuth valide
   - Vault actuellement déverrouillé
   - Permission RBAC appropriée

2. Validation de l'ancien code
   - Dérivation de clé avec ancien code
   - Tentative de déchiffrement du vault actuel
   - Si échec : REFUS

3. Validation du nouveau code
   - Minimum 12 caractères (politique existante)
   - Confirmation identique
   - Validation du format

4. Processus de rotation
   - Lecture complète du vault avec ancienne clé
   - Génération nouveau salt (16 octets aléatoires)
   - Dérivation nouvelle clé avec nouveau code
   - Chiffrement des données avec nouvelle clé
   - Écriture atomique du nouveau vault
   - Validation du nouveau vault

5. Nettoyage
   - Destruction ancienne clé
   - Destruction nouvelle clé
   - Lock du vault
   - Force re-demande du nouveau code
```

## 9. Modifications effectuées

**AUCUNE MODIFICATION EFFECTUÉE** - Phase forensic uniquement

## 10. Permission RBAC utilisée

**Permission proposée :** `vault.update`

**Rôles autorisés :** PDG uniquement (opération sensible)

**Ajout nécessaire dans la matrice RBAC :**
```javascript
vault: ["update"]  // pour PDG uniquement
```

## 11. Tests ancien code

**Tests prévus :**
- Ancien code incorrect + nouveau code valide → REFUS
- Ancien code correct + nouveau code valide → SUCCESS
- Après rotation : ancien code → REFUS

## 12. Tests nouveau code

**Tests prévus :**
- Nouveau code trop court → REFUS
- Confirmation différente → REFUS
- Après rotation : nouveau code → ACCEPTÉ
- Intégrité des données préservée

## 13. Tests données

**Tests prévus :**
- Comptage des objets avant/après rotation
- Vérification des clés préservées
- Validation des structures
- Test de lecture/écriture après rotation

## 14. Tests refresh

**Tests prévus :**
- Rotation → lock → refresh → unlock avec nouveau code

## 15. Tests logout/login

**Tests prévus :**
- Rotation → lock → logout → login → unlock avec nouveau code
- Vérification P0-01 non affecté

## 16. Tests RBAC

**Tests prévus :**
- Rôle PDG : rotation autorisée
- Rôles autres : rotation refusée
- Appel direct depuis DevTools : refusé sans permission

## 17. Tests bypass

**Tests prévus :**
- Appel direct de fonction sans session → REFUS
- Appel direct sans vault déverrouillé → REFUS
- Manipulation DOM pour afficher UI → REFUS au niveau fonction

## 18. Tests exposition du secret

**Tests prévus :**
- Recherche dans localStorage après rotation
- Recherche dans sessionStorage après rotation
- Recherche dans DOM après rotation
- Recherche dans console
- Vérification des logs

## 19. Tests d'erreur

**Tests prévus :**
- Simulation d'erreur de déchiffrement
- Simulation d'erreur de chiffrement
- Simulation d'erreur d'écriture
- Vérification que l'ancien vault reste intact

## 20. Non-régression P0-01

**Vérifications :**
- IMCAuth.authentification intacte
- Session management intacte
- Page guards intacts
- Login/logout fonctionnels

## 21. Non-régression P0-02

**Vérifications :**
- Matrice RBAC intacte
- Permissions existantes préservées
- hasPermission() fonctionnel
- requirePermission() fonctionnel

## 22. Non-régression P0-03

**Vérifications :**
- Protections CREATE/UPDATE intactes
- Nouvelle permission presences.create préservée
- Gap badge.create documenté mais non traité

## 23. Données

**État actuel :**
- Aucune donnée supprimée
- Aucune donnée modifiée
- Structure de stockage préservée
- Vault intact

## 24. Limitations

**Limitations identifiées :**
1. **Architecture client-side** : Toutes les protections sont côté client et ne constituent pas une frontière de sécurité serveur équivalente
2. **Absence de transaction atomique native** : IndexedDB ne garantit pas une transaction multi-opération au niveau applicatif
3. **Saisie du mot de passe** : `window.prompt()` ne garantit pas la sécurité de la saisie
4. **Mémoire JavaScript** : Impossible de garantir l'effacement physique de la mémoire
5. **Pas de rollback natif** : En cas d'échec pendant la rotation, l'ancien vault reste intact mais aucun mécanisme de rollback automatique

## 25. Risques résiduels

**Risques identifiés :**
1. **Corruption pendant rotation** : Si l'écriture échoue après le début de la rotation, l'ancien vault reste intact mais il n'y a pas de mécanisme de rollback
2. **Exposition temporaire en mémoire** : Les clés existent temporairement en mémoire pendant la rotation
3. **Attaque par timing** : La durée de la rotation pourrait indiquer une opération sensible
4. **Contournement client-side** : Un attaquant avec accès à la console pourrait potentiellement contourner les protections

## 26. Verdict final

**NO-GO — ROTATION NON IMPLÉMENTÉE**

### Raison :
Phase forensic uniquement - Aucune implémentation de la rotation du code n'a été effectuée conformément aux règles absolues de l'intervention.

### Recommandations :
1. **Implémenter la fonction de rotation** dans `secure-storage.js` avec le mécanisme conçu
2. **Ajouter la permission RBAC** `vault.update` dans `auth.js` pour le rôle PDG
3. **Créer l'interface utilisateur** dans une page appropriée (PDG.html recommandé)
4. **Implémenter les protections** au niveau fonction métier
5. **Effectuer tous les tests** prévus dans ce rapport forensic
6. **Valider la non-régression** de P0-01, P0-02, et P0-03

### Prérequis pour implémentation :
- Session IMCAuth valide
- Vault actuellement déverrouillé
- Permission vault.update
- Politique de mot de passe (12 caractères minimum)
- Validation de l'ancien code avant rotation
- Validation du nouveau code
- Confirmation identique
- Gestion d'erreur robuste
- Nettoyage sécurisé des clés

### État du vault :
- **Intégrité :** INTACT
- **Structure :** PRÉSERVÉE
- **Données :** NON MODIFIÉES
- **Cryptographie :** COHÉRENTE

### État de l'application :
- **P0-01 :** PASS
- **P0-02 :** PASS
- **P0-03 :** PASS
- **Vault :** INTACT

### Next steps :
1. Approuver le design de rotation
2. Implémenter la fonction de rotation
3. Ajouter les protections RBAC
4. Créer l'interface utilisateur
5. Effectuer les tests de validation
6. Produire un rapport final d'implémentation