#requires -Version 5.1
<#
============================================================
ENV-10-D
FORENSIC DATA MODEL V1 DECISION VALIDATION
============================================================

Projet :
C:\IMC-Clarodoro-securise-client\IMC-Clarodoro

OBJECTIF
--------
Transformer les 21 decisions bloquantes ENV-10 en un
registre architectural V1 explicite.

IMPORTANT
---------
Cette intervention est STRICTEMENT READ-ONLY.

Elle :
- relit ENV-10 ;
- inspecte le code existant ;
- identifie les preuves disponibles ;
- separe les faits des decisions metier ;
- produit un registre de decisions ;
- prepare ENV-11.

Elle ne :
- cree aucune base ;
- ne cree aucune table ;
- ne modifie aucun SQL ;
- ne modifie aucun PHP/JS/HTML ;
- n'execute aucune migration ;
- n'installe aucune dependance ;
- ne demarre/arrete aucun service ;
- ne modifie aucun fichier applicatif.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# 1. CONFIGURATION
# ============================================================

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$AuditDir    = Join-Path $ProjectRoot "audit"

$Env10Final = Join-Path $AuditDir `
    "ENV-10-FORENSIC-DATA-MODEL-V1-FINALIZATION-REPORT-FINAL.md"

$Env10DReport = Join-Path $AuditDir `
    "ENV-10-D-FORENSIC-DATA-MODEL-V1-DECISION-VALIDATION-REPORT.md"

$Env10DFinal = Join-Path $AuditDir `
    "ENV-10-D-FORENSIC-DATA-MODEL-V1-DECISION-VALIDATION-REPORT-FINAL.md"

$DecisionRegister = Join-Path $AuditDir `
    "ENV-10-D-V1-DECISION-REGISTER.md"

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Projet introuvable : $ProjectRoot"
}

if (-not (Test-Path -LiteralPath $AuditDir -PathType Container)) {
    New-Item -ItemType Directory -Path $AuditDir -Force | Out-Null
}

# ============================================================
# 2. OUTILS
# ============================================================

$Warnings = New-Object System.Collections.Generic.List[string]
$Issues   = New-Object System.Collections.Generic.List[string]

function Read-Safe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ""
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    }
    catch {
        $Warnings.Add("Lecture impossible : $Path")
        return ""
    }
}

function Add-Line {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Text = ""
    )

    $List.Add($Text)
}

function Escape-Md {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return $Value.Replace("|","\|")
}

# ============================================================
# 3. RAPPORT ENV-10
# ============================================================

$Env10Text = Read-Safe $Env10Final

if ([string]::IsNullOrWhiteSpace($Env10Text)) {
    $Issues.Add(
        "Le rapport ENV-10 final est absent ou vide."
    )
}

# ============================================================
# 4. INVENTAIRE FORENSIC DU CODE
# ============================================================

$Extensions = @(
    ".php",
    ".js",
    ".html",
    ".htm",
    ".json",
    ".md",
    ".txt"
)

$ExcludedDirs = @(
    "node_modules",
    "vendor",
    ".git",
    "audit"
)

$Files = @(
    Get-ChildItem `
        -LiteralPath $ProjectRoot `
        -Recurse `
        -File `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $Extensions -contains $_.Extension.ToLowerInvariant()
    } |
    Where-Object {

        $relative = $_.FullName.Substring($ProjectRoot.Length).TrimStart("\")
        $parts = $relative -split "[\\/]"

        -not ($parts | Where-Object {
            $ExcludedDirs -contains $_
        })
    }
)

$SourceObjects = New-Object System.Collections.Generic.List[object]

foreach ($file in $Files) {

    try {

        $content = Get-Content `
            -LiteralPath $file.FullName `
            -Raw `
            -ErrorAction Stop

        $SourceObjects.Add([PSCustomObject]@{
            Path = $file.FullName.Substring($ProjectRoot.Length).TrimStart("\")
            Content = $content
        })
    }
    catch {
        $Warnings.Add(
            "Lecture impossible : $($file.FullName)"
        )
    }
}

# ============================================================
# 5. DETECTION DE MOTIFS
# ============================================================

function Find-Evidence {
    param(
        [string[]]$Patterns
    )

    $matchesFound = New-Object System.Collections.Generic.List[string]

    foreach ($source in $SourceObjects) {

        foreach ($pattern in $Patterns) {

            if ($source.Content -match $pattern) {

                $matchesFound.Add($source.Path)
                break
            }
        }
    }

    return @($matchesFound | Sort-Object -Unique)
}

# ============================================================
# 6. REGISTRE DES 21 DECISIONS
# ============================================================

$Decisions = @(

    [PSCustomObject]@{
        ID = "D01"
        Domaine = "IDENTIFIANTS"
        Decision = "Type exact des cles primaires"
        Options = "UUID / BIGINT / INTEGER"
        Evidence = "Le code detecte des identifiants mais ne demontre pas un type PostgreSQL definitif."
        Recommendation = "UUID si l'application doit rester facilement distribuable/importable; sinon BIGINT."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D02"
        Domaine = "NAMING"
        Decision = "Noms definitifs des tables et colonnes"
        Options = "snake_case / noms historiques"
        Evidence = "Le modele forensic utilise deja principalement des noms snake_case."
        Recommendation = "Conserver snake_case pour PostgreSQL."
        Status = "PROPOSED"
    },

    [PSCustomObject]@{
        ID = "D03"
        Domaine = "STUDENTS-PARENTS"
        Decision = "Relation eleves <-> parents"
        Options = "1:N / N:M"
        Evidence = "students et parents sont confirmes; cardinalite non demontree."
        Recommendation = "N:M avec student_parents si plusieurs responsables par eleve sont autorises."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D04"
        Domaine = "PEDAGOGIE"
        Decision = "Affectation enseignants/classes/matières"
        Options = "teacher_id dans classes / table d'affectation"
        Evidence = "classes, teachers et subjects sont detectes."
        Recommendation = "Table d'affectation si un enseignant peut gerer plusieurs classes/matieres."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D05"
        Domaine = "STRUCTURE"
        Decision = "Creation de sections"
        Options = "Creer / ne pas creer"
        Evidence = "sections seulement hypothetique."
        Recommendation = "Ne pas creer sans preuve fonctionnelle."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D06"
        Domaine = "CALENDRIER"
        Decision = "Creation de holidays"
        Options = "Creer / ne pas creer"
        Evidence = "holidays seulement hypothetique."
        Recommendation = "Ne pas creer sans preuve fonctionnelle."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D07"
        Domaine = "RBAC"
        Decision = "Association roles <-> permissions"
        Options = "N:M / autre"
        Evidence = "roles et permissions sont detectes."
        Recommendation = "role_permissions en N:M."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D08"
        Domaine = "PEDAGOGIE"
        Decision = "Structure teacher_class_subjects"
        Options = "Creer / ne pas creer"
        Evidence = "La combinaison enseignant/classe/matiere est suggeree mais non completement demontree."
        Recommendation = "Creer uniquement si les affectations multiples sont reellement supportees."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D09"
        Domaine = "STATUTS"
        Decision = "Type des statuts"
        Options = "ENUM / VARCHAR + CHECK"
        Evidence = "Plusieurs valeurs de statut sont detectees."
        Recommendation = "VARCHAR + CHECK ou tables de reference si les valeurs doivent evoluer."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D10"
        Domaine = "INTEGRITE"
        Decision = "Regles de suppression"
        Options = "CASCADE / RESTRICT / SET NULL"
        Evidence = "Les dependances existent mais aucune strategie globale n'est demontree."
        Recommendation = "RESTRICT par defaut sur donnees metier/historiques."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D11"
        Domaine = "HISTORIQUE"
        Decision = "Soft delete"
        Options = "Oui / Non"
        Evidence = "Le modele contient plusieurs donnees historiques."
        Recommendation = "Privilegier l'archivage/statut pour donnees metier plutot que DELETE physique."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D12"
        Domaine = "STUDENTS"
        Decision = "Unicite des matricules"
        Options = "UNIQUE global / UNIQUE contextualise"
        Evidence = "matricule detecte comme identifiant metier."
        Recommendation = "UNIQUE, sous reserve de confirmer s'il est global ou lie a l'etablissement."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D13"
        Domaine = "ENROLLMENTS"
        Decision = "Unicite d'inscription eleve/annee"
        Options = "Unique / plusieurs inscriptions"
        Evidence = "enrollment associe student, class et school_year."
        Recommendation = "Une inscription active par eleve et annee scolaire."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D14"
        Domaine = "GRADES"
        Decision = "Structure notes/coefficient"
        Options = "coefficient matiere / coefficient evaluation / les deux"
        Evidence = "note et coefficient detectes."
        Recommendation = "Ne pas figer avant clarification du systeme de notation."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D15"
        Domaine = "GRADES"
        Decision = "Calcul des moyennes"
        Options = "calcul dynamique / valeur persistee"
        Evidence = "Les resultats sont presents mais aucune regle SQL definitive n'est demontree."
        Recommendation = "Calculer depuis les notes sources plutot que persister une valeur derivee."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D16"
        Domaine = "ATTENDANCE"
        Decision = "Presence / absence"
        Options = "attendance unique / attendance + absences"
        Evidence = "Deux concepts sont detectes."
        Recommendation = "Eviter la duplication; privilegier une source unique si les statuts couvrent les cas necessaires."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D17"
        Domaine = "FINANCE"
        Decision = "Structure financiere"
        Options = "invoice/payment / autre"
        Evidence = "invoices et payments sont fortement supportes."
        Recommendation = "Conserver invoice -> payments."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D18"
        Domaine = "FINANCE"
        Decision = "Paiements partiels"
        Options = "Oui / Non"
        Evidence = "payments multiples potentiels detectes."
        Recommendation = "Autoriser plusieurs paiements par facture si le besoin metier est confirme."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D19"
        Domaine = "FINANCE"
        Decision = "Calcul/persistance du solde"
        Options = "calcule / stocke"
        Evidence = "balance apparait dans le modele."
        Recommendation = "Eviter une duplication du solde si celui-ci peut etre calcule de facon fiable."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D20"
        Domaine = "FINANCE"
        Decision = "Methodes de paiement"
        Options = "VARCHAR / ENUM / table"
        Evidence = "method et reference sont detectes."
        Recommendation = "VARCHAR + validation controlee pour permettre l'evolution."
        Status = "HUMAN-DECISION"
    },

    [PSCustomObject]@{
        ID = "D21"
        Domaine = "RBAC"
        Decision = "Roles et permissions definitifs"
        Options = "roles/permissions actuels du code"
        Evidence = "roles et permissions detectes par ENV-08/09."
        Recommendation = "Definir explicitement les roles et permissions avant creation des contraintes SQL."
        Status = "HUMAN-DECISION"
    }
)

# ============================================================
# 7. PREUVES CODE POUR CHAQUE DOMAINE
# ============================================================

$EvidenceMap = @{

    "IDENTIFIANTS" = @(
        "id",
        "uuid",
        "matricule",
        "student_id",
        "teacher_id",
        "class_id"
    )

    "STUDENTS-PARENTS" = @(
        "student",
        "parent",
        "responsable",
        "parents"
    )

    "PEDAGOGIE" = @(
        "teacher",
        "enseignant",
        "subject",
        "matiere",
        "class"
    )

    "STRUCTURE" = @(
        "section"
    )

    "CALENDRIER" = @(
        "holiday",
        "vacance",
        "vacances"
    )

    "RBAC" = @(
        "role",
        "permission",
        "requireRole",
        "requirePermission"
    )

    "STATUTS" = @(
        "status",
        "active",
        "inactive",
        "pending",
        "paid"
    )

    "HISTORIQUE" = @(
        "deleted",
        "archived",
        "inactive",
        "soft"
    )

    "GRADES" = @(
        "grade",
        "note",
        "coefficient",
        "moyenne",
        "result"
    )

    "ATTENDANCE" = @(
        "attendance",
        "absence",
        "present",
        "absent"
    )

    "FINANCE" = @(
        "invoice",
        "facture",
        "payment",
        "paiement",
        "balance",
        "solde"
    )
}

$EvidenceResults = @{}

foreach ($domain in $EvidenceMap.Keys) {

    $patterns = @()

    foreach ($term in $EvidenceMap[$domain]) {
        $patterns += [regex]::Escape($term)
    }

    $EvidenceResults[$domain] = Find-Evidence $patterns
}

# ============================================================
# 8. DETECTION DE L'ETAT DE LA BASE
# ============================================================

$SchemaPath = Join-Path $ProjectRoot "database\schema.sql"

$SchemaText = Read-Safe $SchemaPath

$CreateTableCount = 0

if (-not [string]::IsNullOrWhiteSpace($SchemaText)) {
    $CreateTableCount = (
        [regex]::Matches(
            $SchemaText,
            "(?im)\bCREATE\s+TABLE\b"
        )
    ).Count
}

# ============================================================
# 9. DETECTION DES MODIFICATIONS INTERDITES
# ============================================================

$ForbiddenDbPatterns = @(
    "(?im)\bCREATE\s+DATABASE\b",
    "(?im)\bCREATE\s+TABLE\b",
    "(?im)\bALTER\s+TABLE\b",
    "(?im)\bDROP\s+TABLE\b",
    "(?im)\bDROP\s+DATABASE\b",
    "(?im)\bTRUNCATE\b",
    "(?im)\bINSERT\s+INTO\b",
    "(?im)\bUPDATE\s+\w+\s+SET\b",
    "(?im)\bDELETE\s+FROM\b"
)

# Le script ne les execute jamais.
# Verification informative uniquement sur ENV-10-D lui-même.

# ============================================================
# 10. RAPPORT
# ============================================================

$Lines = New-Object System.Collections.Generic.List[string]

Add-Line $Lines "# ENV-10-D — FORENSIC DATA MODEL V1 DECISION VALIDATION"
Add-Line $Lines ""
Add-Line $Lines "## 1. Verdict"
Add-Line $Lines ""
Add-Line $Lines "**DECISION-REGISTER-CREATED**"
Add-Line $Lines ""
Add-Line $Lines "ENV-10-D transforme les decisions bloquantes ENV-10 en registre architectural V1."
Add-Line $Lines ""
Add-Line $Lines "**Aucune decision metier n'est automatiquement consideree comme validee.**"
Add-Line $Lines ""
Add-Line $Lines "---"
Add-Line $Lines ""

Add-Line $Lines "## 2. Securite de l'intervention"
Add-Line $Lines ""
Add-Line $Lines "- Mode : READ-ONLY"
Add-Line $Lines "- Base PostgreSQL creee : NON"
Add-Line $Lines "- Tables PostgreSQL creees : NON"
Add-Line $Lines "- Migration executee : NON"
Add-Line $Lines "- Code applicatif modifie : NON"
Add-Line $Lines "- Services systeme modifies : NON"
Add-Line $Lines ""

Add-Line $Lines "## 3. Etat du schema.sql actuel"
Add-Line $Lines ""
Add-Line $Lines "- Fichier : `database/schema.sql`"
Add-Line $Lines "- CREATE TABLE detectes : $CreateTableCount"
Add-Line $Lines ""

if ($CreateTableCount -eq 0) {
    Add-Line $Lines "**Le schema.sql reste un placeholder.**"
}
else {
    Add-Line $Lines "**Attention : des CREATE TABLE existent deja dans schema.sql.**"
}

Add-Line $Lines ""

Add-Line $Lines "## 4. Registre des decisions"
Add-Line $Lines ""

Add-Line $Lines "ID - Domaine - Decision - Statut"
Add-Line $Lines "--- - --- - --- - ---"

foreach ($decision in $Decisions) {

    Add-Line $Lines (
        "$($decision.ID) - $(Escape-Md $decision.Domaine) - $(Escape-Md $decision.Decision) - $($decision.Status)"
    )
}

Add-Line $Lines ""

foreach ($decision in $Decisions) {

    Add-Line $Lines "### $($decision.ID) — $($decision.Decision)"
    Add-Line $Lines ""
    Add-Line $Lines "**Domaine :** $($decision.Domaine)"
    Add-Line $Lines ""
    Add-Line $Lines "**Options :** $($decision.Options)"
    Add-Line $Lines ""
    Add-Line $Lines "**Preuve disponible :** $($decision.Evidence)"
    Add-Line $Lines ""
    Add-Line $Lines "**Proposition technique :** $($decision.Recommendation)"
    Add-Line $Lines ""
    Add-Line $Lines "**Statut :** `$($decision.Status)`"
    Add-Line $Lines ""
}

Add-Line $Lines "## 5. Preuves detectees dans le code"
Add-Line $Lines ""

foreach ($domain in ($EvidenceResults.Keys | Sort-Object)) {

    Add-Line $Lines "### $domain"
    Add-Line $Lines ""

    $items = @($EvidenceResults[$domain])

    if ($items.Count -eq 0) {
        Add-Line $Lines "- Aucune occurrence pertinente detectee."
    }
    else {

        Add-Line $Lines "- Fichiers concernes : $($items.Count)"

        foreach ($item in ($items | Select-Object -First 15)) {
            Add-Line $Lines "  - $item"
        }

        if ($items.Count -gt 15) {
            Add-Line $Lines "  - ... $($items.Count - 15) fichier(s) supplementaire(s)"
        }
    }

    Add-Line $Lines ""
}

Add-Line $Lines "## 6. Architecture V1 proposee"
Add-Line $Lines ""

Add-Line $Lines "### Noyau academique"
Add-Line $Lines ""
Add-Line $Lines "students"
Add-Line $Lines "    |"
Add-Line $Lines "    |"
Add-Line $Lines "    - enrollments - classes - levels"
Add-Line $Lines "              |"
Add-Line $Lines "              - school_years"
Add-Line $Lines ""
Add-Line $Lines "students - grades - subjects"
Add-Line $Lines ""

Add-Line $Lines "### Noyau financier"
Add-Line $Lines ""
Add-Line $Lines "students"
Add-Line $Lines "    |"
Add-Line $Lines "    - invoices"
Add-Line $Lines "           |"
Add-Line $Lines "           - payments"
Add-Line $Lines ""

Add-Line $Lines "### Noyau securite"
Add-Line $Lines ""
Add-Line $Lines "users"
Add-Line $Lines "   |"
Add-Line $Lines "   - roles"
Add-Line $Lines "          |"
Add-Line $Lines "          - role_permissions - permissions"
Add-Line $Lines ""

Add-Line $Lines "### Relations potentiellement N:M"
Add-Line $Lines ""
Add-Line $Lines "- students <-> parents"
Add-Line $Lines "- roles <-> permissions"
Add-Line $Lines "- teachers <-> classes <-> subjects"
Add-Line $Lines ""

Add-Line $Lines "## 7. Points volontairement non figes"
Add-Line $Lines ""
Add-Line $Lines "- sections"
Add-Line $Lines "- holidays"
Add-Line $Lines "- structure exacte des affectations enseignants"
Add-Line $Lines "- cardinalite eleves/parents"
Add-Line $Lines "- modele exact des notes"
Add-Line $Lines "- strategie attendance/absences"
Add-Line $Lines "- strategie de suppression"
Add-Line $Lines "- type des statuts"
Add-Line $Lines ""

Add-Line $Lines "## 8. Preparation ENV-11"
Add-Line $Lines ""
Add-Line $Lines "ENV-11 pourra generer le schema.sql uniquement apres validation humaine du registre D01-D21."
Add-Line $Lines ""
Add-Line $Lines "La validation humaine doit conserver les identifiants D01 a D21 afin que chaque choix soit tracable jusqu'au SQL."
Add-Line $Lines ""

Add-Line $Lines "## 9. Anomalies"
Add-Line $Lines ""

if ($Issues.Count -eq 0) {
    Add-Line $Lines "Aucune anomalie bloquante detectee."
}
else {
    foreach ($issue in $Issues) {
        Add-Line $Lines "- $issue"
    }
}

Add-Line $Lines ""

Add-Line $Lines "## 10. Warnings"

if ($Warnings.Count -eq 0) {
    Add-Line $Lines ""
    Add-Line $Lines "Aucun warning."
}
else {
    Add-Line $Lines ""

    foreach ($warning in $Warnings) {
        Add-Line $Lines "- $warning"
    }
}

Add-Line $Lines ""

Add-Line $Lines "## 11. Conclusion"
Add-Line $Lines ""
Add-Line $Lines "**ENV-10-D COMPLETE — DECISION REGISTER READY FOR HUMAN VALIDATION**"
Add-Line $Lines ""
Add-Line $Lines "Le modele logique peut maintenant etre valide decision par decision avant toute production SQL."
Add-Line $Lines ""

$ReportText = $Lines -join "`r`n"

Set-Content `
    -LiteralPath $Env10DReport `
    -Value $ReportText `
    -Encoding UTF8

Set-Content `
    -LiteralPath $Env10DFinal `
    -Value $ReportText `
    -Encoding UTF8

Set-Content `
    -LiteralPath $DecisionRegister `
    -Value $ReportText `
    -Encoding UTF8

# ============================================================
# 11. SORTIE CONSOLE
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host " ENV-10-D — V1 DECISION VALIDATION"
Write-Host "============================================================"
Write-Host ""
Write-Host "VERDICT : DECISION-REGISTER-CREATED"
Write-Host ""
Write-Host "Decisions D01-D21 : 21"
Write-Host "Fichiers analyses  : $($Files.Count)"
Write-Host "CREATE TABLE dans schema.sql : $CreateTableCount"
Write-Host ""
Write-Host "Base creee        : NON"
Write-Host "Tables creees     : NON"
Write-Host "Migration         : NON"
Write-Host "Code modifie      : NON"
Write-Host ""
Write-Host "Rapport :"
Write-Host $Env10DReport
Write-Host ""
Write-Host "Rapport final :"
Write-Host $Env10DFinal
Write-Host ""
Write-Host "Registre decisions :"
Write-Host $DecisionRegister
Write-Host ""
Write-Host "============================================================"
Write-Host " FIN ENV-10-D"
Write-Host "============================================================"
