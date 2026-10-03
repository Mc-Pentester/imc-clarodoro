#requires -Version 5.1
<#
ENV-10 — FORENSIC DATA MODEL V1 FINALIZATION

Projet :
C:\IMC-Clarodoro-securise-client\IMC-Clarodoro

OBJECTIF
--------
Transformer les resultats ENV-07 / ENV-08 / ENV-09 en un
MODELE DE DONNEES V1 FINAL documente.

IMPORTANT
---------
ENV-10 ne cree PAS encore schema.sql.
ENV-10 ne cree PAS PostgreSQL.
ENV-10 ne modifie PAS le code.

MODE STRICTEMENT READ-ONLY
==========================
INTERDIT :
- CREATE DATABASE
- CREATE TABLE
- ALTER
- DROP
- INSERT
- UPDATE
- DELETE
- TRUNCATE
- migration
- modification du code
- modification de schema.sql
- demarrage/arrêt PostgreSQL
- demarrage/arrêt Apache
- installation de dependances
- commit/push Git
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# 1. CONFIGURATION
# ============================================================

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$AuditDir    = Join-Path $ProjectRoot "audit"

$ReportPath = Join-Path $AuditDir "ENV-10-FORENSIC-DATA-MODEL-V1-FINALIZATION-REPORT.md"
$FinalPath  = Join-Path $AuditDir "ENV-10-FORENSIC-DATA-MODEL-V1-FINALIZATION-REPORT-FINAL.md"
$ModelPath  = Join-Path $AuditDir "ENV-10-DATA-MODEL-V1-FINAL.md"

$Env08Final = Join-Path $AuditDir "ENV-08-FORENSIC-DATA-MODEL-RECONSTRUCTION-REPORT-FINAL.md"
$Env09Final = Join-Path $AuditDir "ENV-09-FORENSIC-DATA-MODEL-VALIDATION-REPORT-FINAL.md"

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Projet introuvable : $ProjectRoot"
}

if (-not (Test-Path -LiteralPath $AuditDir -PathType Container)) {
    New-Item -ItemType Directory -Path $AuditDir -Force | Out-Null
}

# ============================================================
# 2. UTILITAIRES
# ============================================================

$StartTime = Get-Date

$Warnings = New-Object System.Collections.Generic.List[string]
$Issues   = New-Object System.Collections.Generic.List[string]

function Add-Warning {
    param([string]$Message)
    $Warnings.Add($Message)
}

function Add-Issue {
    param([string]$Message)
    $Issues.Add($Message)
}

function Read-TextSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ""
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    }
    catch {
        Add-Warning "Lecture impossible : $Path"
        return ""
    }
}

function Escape-Md {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return $Value.Replace("|","\|")
}

function Add-Line {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Text = ""
    )

    $List.Add($Text)
}

# ============================================================
# 3. VERIFICATION DES RAPPORTS PRECEDENTS
# ============================================================

$Env08Text = Read-TextSafe $Env08Final
$Env09Text = Read-TextSafe $Env09Final

if ([string]::IsNullOrWhiteSpace($Env08Text)) {
    Add-Issue "Rapport final ENV-08 introuvable ou vide."
}

if ([string]::IsNullOrWhiteSpace($Env09Text)) {
    Add-Issue "Rapport final ENV-09 introuvable ou vide."
}

# ============================================================
# 4. INVENTAIRE DU CODE
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
    "audit",
    ".git"
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

$Sources = New-Object System.Collections.Generic.List[object]

foreach ($file in $Files) {

    try {

        $content = Get-Content `
            -LiteralPath $file.FullName `
            -Raw `
            -ErrorAction Stop

        $Sources.Add([PSCustomObject]@{
            FullName = $file.FullName
            Relative = $file.FullName.Substring($ProjectRoot.Length).TrimStart("\")
            Extension = $file.Extension.ToLowerInvariant()
            Content = $content
        })
    }
    catch {
        Add-Warning "Impossible de lire : $($file.FullName)"
    }
}

# ============================================================
# 5. ENTITES V1 ISSUES DE ENV-08 / ENV-09
# ============================================================

$Entities = @(
    [PSCustomObject]@{
        Name = "users"
        Status = "CONFIRMED"
        Purpose = "Utilisateurs authentifies de l'application"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "students"
        Status = "CONFIRMED"
        Purpose = "Eleves"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "parents"
        Status = "CONFIRMED"
        Purpose = "Parents / responsables"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "teachers"
        Status = "CONFIRMED"
        Purpose = "Enseignants"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "classes"
        Status = "CONFIRMED"
        Purpose = "Classes scolaires"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "subjects"
        Status = "CONFIRMED"
        Purpose = "Matieres"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "school_years"
        Status = "CONFIRMED"
        Purpose = "Annees scolaires"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "enrollments"
        Status = "CONFIRMED"
        Purpose = "Inscriptions des eleves"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "grades"
        Status = "CONFIRMED"
        Purpose = "Notes / resultats"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "roles"
        Status = "CONFIRMED"
        Purpose = "Roles applicatifs"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "staff"
        Status = "PROBABLE"
        Purpose = "Personnel administratif"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "levels"
        Status = "PROBABLE"
        Purpose = "Niveaux scolaires"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "attendance"
        Status = "PROBABLE"
        Purpose = "Presences"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "absences"
        Status = "PROBABLE"
        Purpose = "Absences"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "invoices"
        Status = "PROBABLE"
        Purpose = "Facturation"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "payments"
        Status = "PROBABLE"
        Purpose = "Paiements"
        Source = "ENV-08/ENV-09"
    },

    [PSCustomObject]@{
        Name = "permissions"
        Status = "PROBABLE"
        Purpose = "Permissions RBAC"
        Source = "ENV-08/ENV-09"
    }
)

# ============================================================
# 6. ENTITES HYPOTHETIQUES
# ============================================================

$HypotheticalEntities = @(
    [PSCustomObject]@{
        Name = "sections"
        Reason = "Detectee mais non suffisamment confirmee par ENV-09."
    },

    [PSCustomObject]@{
        Name = "holidays"
        Reason = "Detectee mais non suffisamment confirmee par ENV-09."
    }
)

# ============================================================
# 7. TABLES D'ASSOCIATION POTENTIELLES
# ============================================================

$AssociationCandidates = @(
    [PSCustomObject]@{
        Name = "student_parents"
        Purpose = "Relation potentiellement N:M entre eleves et parents/responsables"
        Status = "DECISION-REQUIRED"
        Reason = "La relation students -> parents est seulement PROBABLE."
    },

    [PSCustomObject]@{
        Name = "role_permissions"
        Purpose = "Association roles <-> permissions"
        Status = "DECISION-REQUIRED"
        Reason = "La relation roles -> permissions est PROBABLE."
    },

    [PSCustomObject]@{
        Name = "teacher_class_subjects"
        Purpose = "Affectation enseignant / classe / matiere"
        Status = "DECISION-REQUIRED"
        Reason = "Le code suggere ces concepts mais la cardinalite exacte doit etre validee."
    }
)

# ============================================================
# 8. CATALOGUE DES COLONNES V1
# ============================================================

$TableDefinitions = @{

    users = @(
        @("id","IDENTIFIER","NON","PK"),
        @("username","TEXT","NON",""),
        @("email","TEXT","NON",""),
        @("password","TEXT","NON","SENSITIVE"),
        @("role_id","IDENTIFIER","OUI","FK roles.id - a confirmer"),
        @("status","TEXT","NON",""),
        @("created_at","DATETIME","NON",""),
        @("updated_at","DATETIME","NON","")
    )

    students = @(
        @("id","IDENTIFIER","NON","PK"),
        @("matricule","TEXT","NON","UNIQUE a valider"),
        @("nom","TEXT","NON",""),
        @("prenom","TEXT","NON",""),
        @("date_naissance","DATE","OUI",""),
        @("sexe","TEXT","OUI",""),
        @("adresse","TEXT","OUI",""),
        @("telephone","TEXT","OUI",""),
        @("status","TEXT","NON",""),
        @("created_at","DATETIME","OUI",""),
        @("updated_at","DATETIME","OUI","")
    )

    parents = @(
        @("id","IDENTIFIER","NON","PK"),
        @("nom","TEXT","NON",""),
        @("prenom","TEXT","NON",""),
        @("telephone","TEXT","OUI",""),
        @("email","TEXT","OUI",""),
        @("adresse","TEXT","OUI",""),
        @("created_at","DATETIME","OUI",""),
        @("updated_at","DATETIME","OUI","")
    )

    teachers = @(
        @("id","IDENTIFIER","NON","PK"),
        @("nom","TEXT","NON",""),
        @("prenom","TEXT","NON",""),
        @("email","TEXT","OUI",""),
        @("telephone","TEXT","OUI",""),
        @("status","TEXT","NON",""),
        @("created_at","DATETIME","OUI",""),
        @("updated_at","DATETIME","OUI","")
    )

    staff = @(
        @("id","IDENTIFIER","NON","PK"),
        @("nom","TEXT","NON",""),
        @("prenom","TEXT","NON",""),
        @("fonction","TEXT","OUI",""),
        @("telephone","TEXT","OUI",""),
        @("email","TEXT","OUI",""),
        @("status","TEXT","NON",""),
        @("created_at","DATETIME","OUI",""),
        @("updated_at","DATETIME","OUI","")
    )

    levels = @(
        @("id","IDENTIFIER","NON","PK"),
        @("code","TEXT","NON",""),
        @("nom","TEXT","NON",""),
        @("description","TEXT","OUI","")
    )

    classes = @(
        @("id","IDENTIFIER","NON","PK"),
        @("code","TEXT","NON",""),
        @("nom","TEXT","NON",""),
        @("level_id","IDENTIFIER","OUI","FK levels.id - a confirmer"),
        @("section_id","IDENTIFIER","OUI","FK sections.id - decision"),
        @("teacher_id","IDENTIFIER","OUI","FK teachers.id - decision"),
        @("status","TEXT","NON","")
    )

    subjects = @(
        @("id","IDENTIFIER","NON","PK"),
        @("code","TEXT","NON",""),
        @("nom","TEXT","NON",""),
        @("description","TEXT","OUI",""),
        @("coefficient","NUMERIC","OUI","Regle a valider")
    )

    school_years = @(
        @("id","IDENTIFIER","NON","PK"),
        @("label","TEXT","NON",""),
        @("start_date","DATE","NON",""),
        @("end_date","DATE","NON",""),
        @("status","TEXT","NON","")
    )

    enrollments = @(
        @("id","IDENTIFIER","NON","PK"),
        @("student_id","IDENTIFIER","NON","FK students.id"),
        @("class_id","IDENTIFIER","NON","FK classes.id"),
        @("school_year_id","IDENTIFIER","NON","FK school_years.id"),
        @("status","TEXT","NON",""),
        @("date","DATE","NON","")
    )

    grades = @(
        @("id","IDENTIFIER","NON","PK"),
        @("student_id","IDENTIFIER","NON","FK students.id"),
        @("subject_id","IDENTIFIER","NON","FK subjects.id"),
        @("enrollment_id","IDENTIFIER","OUI","FK enrollments.id"),
        @("note","NUMERIC","NON",""),
        @("coefficient","NUMERIC","OUI",""),
        @("date","DATE","OUI","")
    )

    attendance = @(
        @("id","IDENTIFIER","NON","PK"),
        @("student_id","IDENTIFIER","NON","FK students.id"),
        @("class_id","IDENTIFIER","OUI","FK classes.id"),
        @("date","DATE","NON",""),
        @("status","TEXT","NON",""),
        @("comment","TEXT","OUI","")
    )

    absences = @(
        @("id","IDENTIFIER","NON","PK"),
        @("student_id","IDENTIFIER","NON","FK students.id"),
        @("date","DATE","NON",""),
        @("justification","TEXT","OUI",""),
        @("comment","TEXT","OUI","")
    )

    invoices = @(
        @("id","IDENTIFIER","NON","PK"),
        @("student_id","IDENTIFIER","NON","FK students.id"),
        @("amount","NUMERIC","NON",""),
        @("balance","NUMERIC","OUI","Calcul/persistance a decider"),
        @("status","TEXT","NON",""),
        @("date","DATE","NON","")
    )

    payments = @(
        @("id","IDENTIFIER","NON","PK"),
        @("invoice_id","IDENTIFIER","NON","FK invoices.id"),
        @("amount","NUMERIC","NON",""),
        @("date","DATE","NON",""),
        @("method","TEXT","NON",""),
        @("reference","TEXT","OUI","")
    )

    roles = @(
        @("id","IDENTIFIER","NON","PK"),
        @("name","TEXT","NON",""),
        @("description","TEXT","OUI","")
    )

    permissions = @(
        @("id","IDENTIFIER","NON","PK"),
        @("name","TEXT","NON",""),
        @("description","TEXT","OUI","")
    )
}

# ============================================================
# 9. RELATIONS V1
# ============================================================

$Relations = @(
    [PSCustomObject]@{
        From = "students"
        To = "enrollments"
        Cardinality = "1:N"
        Status = "CONFIRMED"
        Constraint = "student_id"
    },

    [PSCustomObject]@{
        From = "students"
        To = "grades"
        Cardinality = "1:N"
        Status = "CONFIRMED"
        Constraint = "student_id"
    },

    [PSCustomObject]@{
        From = "enrollments"
        To = "classes"
        Cardinality = "N:1"
        Status = "CONFIRMED"
        Constraint = "class_id"
    },

    [PSCustomObject]@{
        From = "enrollments"
        To = "school_years"
        Cardinality = "N:1"
        Status = "CONFIRMED"
        Constraint = "school_year_id"
    },

    [PSCustomObject]@{
        From = "grades"
        To = "subjects"
        Cardinality = "N:1"
        Status = "CONFIRMED"
        Constraint = "subject_id"
    },

    [PSCustomObject]@{
        From = "grades"
        To = "enrollments"
        Cardinality = "N:1"
        Status = "CONFIRMED"
        Constraint = "enrollment_id"
    },

    [PSCustomObject]@{
        From = "users"
        To = "roles"
        Cardinality = "N:1"
        Status = "CONFIRMED"
        Constraint = "role_id"
    },

    [PSCustomObject]@{
        From = "students"
        To = "parents"
        Cardinality = "UNKNOWN"
        Status = "PROBABLE"
        Constraint = "student_parent a decider"
    },

    [PSCustomObject]@{
        From = "students"
        To = "attendance"
        Cardinality = "1:N"
        Status = "PROBABLE"
        Constraint = "student_id"
    },

    [PSCustomObject]@{
        From = "students"
        To = "absences"
        Cardinality = "1:N"
        Status = "PROBABLE"
        Constraint = "student_id"
    },

    [PSCustomObject]@{
        From = "classes"
        To = "levels"
        Cardinality = "N:1"
        Status = "PROBABLE"
        Constraint = "level_id"
    },

    [PSCustomObject]@{
        From = "classes"
        To = "teachers"
        Cardinality = "UNKNOWN"
        Status = "PROBABLE"
        Constraint = "teacher_id - affectation a decider"
    },

    [PSCustomObject]@{
        From = "attendance"
        To = "classes"
        Cardinality = "N:1"
        Status = "PROBABLE"
        Constraint = "class_id"
    },

    [PSCustomObject]@{
        From = "payments"
        To = "invoices"
        Cardinality = "N:1"
        Status = "PROBABLE"
        Constraint = "invoice_id"
    },

    [PSCustomObject]@{
        From = "invoices"
        To = "students"
        Cardinality = "N:1"
        Status = "PROBABLE"
        Constraint = "student_id"
    },

    [PSCustomObject]@{
        From = "roles"
        To = "permissions"
        Cardinality = "N:M"
        Status = "PROBABLE"
        Constraint = "role_permissions a confirmer"
    }
)

# ============================================================
# 10. REGLES METIER V1
# ============================================================

$BusinessRules = @(
    [PSCustomObject]@{
        Area = "Authentication"
        Rule = "Les utilisateurs doivent etre authentifies avant acces aux fonctionnalites protegees."
        Status = "CONFIRMED-BY-APPLICATION"
    },

    [PSCustomObject]@{
        Area = "Students"
        Rule = "Le matricule etudiant doit etre traite comme identifiant metier."
        Status = "STRONGLY-SUPPORTED"
    },

    [PSCustomObject]@{
        Area = "Enrollment"
        Rule = "Une inscription associe un eleve a une classe et une annee scolaire."
        Status = "CONFIRMED"
    },

    [PSCustomObject]@{
        Area = "Grades"
        Rule = "Une note est associee a un eleve et une matiere."
        Status = "CONFIRMED"
    },

    [PSCustomObject]@{
        Area = "Grades"
        Rule = "Le coefficient existe dans le modele detecte mais sa regle de calcul reste a definir."
        Status = "DECISION-REQUIRED"
    },

    [PSCustomObject]@{
        Area = "Attendance"
        Rule = "Les presences/absences doivent etre rattachees a un eleve et a une date."
        Status = "SUPPORTED"
    },

    [PSCustomObject]@{
        Area = "Finance"
        Rule = "Une facture appartient a un eleve et peut recevoir plusieurs paiements."
        Status = "PROBABLE"
    },

    [PSCustomObject]@{
        Area = "Finance"
        Rule = "Le paiement partiel doit etre supporte si confirme par les regles fonctionnelles."
        Status = "DECISION-REQUIRED"
    },

    [PSCustomObject]@{
        Area = "RBAC"
        Rule = "Les utilisateurs sont associes a des roles."
        Status = "CONFIRMED"
    },

    [PSCustomObject]@{
        Area = "RBAC"
        Rule = "Les roles peuvent etre associes a des permissions."
        Status = "PROBABLE"
    }
)

# ============================================================
# 11. DECISIONS BLOQUANTES AVANT ENV-11
# ============================================================

$BlockingDecisions = @(
    "Type exact des cles primaires",
    "Noms definitifs des tables et colonnes",
    "Relation eleves <-> parents",
    "Affectation enseignants <-> classes <-> matieres",
    "Creation ou non de sections",
    "Creation ou non de holidays",
    "Creation de role_permissions",
    "Structure de teacher_class_subjects si necessaire",
    "Type des statuts",
    "Regles de suppression",
    "Soft delete ou suppression physique",
    "Unicite des matricules",
    "Unicite d'une inscription par eleve/annee scolaire",
    "Structure des notes et coefficients",
    "Regles de calcul des moyennes",
    "Structure definitive de la presence/absence",
    "Regles financieres",
    "Paiements partiels",
    "Calcul ou persistance du solde",
    "Methodes de paiement",
    "Roles et permissions definitifs"
)

# ============================================================
# 12. DECISIONS POUVANT ETRE DEFERREES A ENV-11
# ============================================================

$DeferredToSchema = @(
    "Index secondaires",
    "Index composites",
    "Check constraints detaillees",
    "Defaults PostgreSQL",
    "Triggers eventuels",
    "Generated columns eventuelles",
    "Strategie exacte de timestamp",
    "Commentaires SQL",
    "Ordre definitif des CREATE TABLE"
)

# ============================================================
# 13. COHERENCE INTERNE
# ============================================================

$ConsistencyIssues = New-Object System.Collections.Generic.List[string]

# Verification FK -> table connue
foreach ($tableName in $TableDefinitions.Keys) {

    foreach ($column in $TableDefinitions[$tableName]) {

        $note = [string]$column[3]

        if ($note -match "FK\s+([a-zA-Z_]+)\.([a-zA-Z_]+)") {

            $targetTable = $Matches[1]

            $exists = $TableDefinitions.ContainsKey($targetTable)

            if (-not $exists) {

                if ($targetTable -notin @("sections")) {
                    $ConsistencyIssues.Add(
                        "FK cible non definie : $tableName.$($column[0]) -> $targetTable"
                    )
                }
            }
        }
    }
}

# Verification des PK
foreach ($tableName in $TableDefinitions.Keys) {

    $pkCount = @(
        $TableDefinitions[$tableName] |
        Where-Object {
            ([string]$_.Count -ge 4) -and
            ([string]$_.Item(3) -eq "PK")
        }
    ).Count

    if ($pkCount -ne 1) {
        $ConsistencyIssues.Add(
            "Table $tableName : cle primaire non determinee exactement."
        )
    }
}

# ============================================================
# 14. SCORE DE MATURITE
# ============================================================

$ConfirmedEntityCount = @(
    $Entities | Where-Object Status -eq "CONFIRMED"
).Count

$ProbableEntityCount = @(
    $Entities | Where-Object Status -eq "PROBABLE"
).Count

$HypotheticalEntityCount = $HypotheticalEntities.Count

$ConfirmedRelationCount = @(
    $Relations | Where-Object Status -eq "CONFIRMED"
).Count

$ProbableRelationCount = @(
    $Relations | Where-Object Status -eq "PROBABLE"
).Count

# ============================================================
# 15. VERDICT ENV-10
# ============================================================

$Verdict = "MODEL-V1-DRAFT-COMPLETE"

if ($Issues.Count -gt 0) {
    $Verdict = "MODEL-V1-INCOMPLETE"
}

if ($ConsistencyIssues.Count -gt 0) {
    $Verdict = "MODEL-V1-REQUIRES-CORRECTION"
}

$SchemaReady = $false

# ============================================================
# 16. RAPPORT PRINCIPAL
# ============================================================

$Lines = New-Object System.Collections.Generic.List[string]

Add-Line $Lines "# ENV-10 — FORENSIC DATA MODEL V1 FINALIZATION"
Add-Line $Lines ""
Add-Line $Lines "## 1. Resultat"
Add-Line $Lines ""
Add-Line $Lines "**$Verdict**"
Add-Line $Lines ""
Add-Line $Lines "ENV-10 consolide ENV-08 et ENV-09 en modele logique V1."
Add-Line $Lines ""
Add-Line $Lines "**Creation PostgreSQL : NON EFFECTUEE**"
Add-Line $Lines ""
Add-Line $Lines "**schema.sql : NON GENERE**"
Add-Line $Lines ""
Add-Line $Lines "---"
Add-Line $Lines ""

Add-Line $Lines "## 2. Sources"
Add-Line $Lines ""
Add-Line $Lines "- Code applicatif reel"
Add-Line $Lines "- ENV-08 - reconstruction forensic"
Add-Line $Lines "- ENV-09 - validation forensic"
Add-Line $Lines ""

Add-Line $Lines "## 3. Entites V1"
Add-Line $Lines ""
Add-Line $Lines "Entite - Statut - Objet"
Add-Line $Lines "--- - --- - ---"

foreach ($entity in $Entities) {

    Add-Line $Lines (
        "$(Escape-Md $entity.Name) - $($entity.Status) - $(Escape-Md $entity.Purpose)"
    )
}

Add-Line $Lines ""

Add-Line $Lines "### Entites hypothetiques"
Add-Line $Lines ""

foreach ($entity in $HypotheticalEntities) {

    Add-Line $Lines (
        "- **$($entity.Name)** - $($entity.Reason)"
    )
}

Add-Line $Lines ""

Add-Line $Lines "## 4. Tables d'association"
Add-Line $Lines ""
Add-Line $Lines "Table candidate - Objet - Statut"
Add-Line $Lines "--- - --- - ---"

foreach ($item in $AssociationCandidates) {

    Add-Line $Lines (
        "$($item.Name) - $(Escape-Md $item.Purpose) - $($item.Status)"
    )
}

Add-Line $Lines ""

Add-Line $Lines "## 5. Catalogue des tables et colonnes"
Add-Line $Lines ""

foreach ($tableName in $TableDefinitions.Keys | Sort-Object) {

    Add-Line $Lines "### $tableName"
    Add-Line $Lines ""
    Add-Line $Lines "Colonne - Type logique - Null - Role / contrainte"
    Add-Line $Lines "--- - --- - --- - ---"

    foreach ($column in $TableDefinitions[$tableName]) {

        Add-Line $Lines (
            "$($column[0]) - $($column[1]) - $($column[2]) - $(Escape-Md ([string]$column[3]))"
        )
    }

    Add-Line $Lines ""
}

Add-Line $Lines "## 6. Relations"
Add-Line $Lines ""
Add-Line $Lines "Source - Cible - Cardinalite - Statut - Contrainte"
Add-Line $Lines "--- - --- - --- - --- - ---"

foreach ($relation in $Relations) {

    Add-Line $Lines (
        "$($relation.From) - $($relation.To) - $($relation.Cardinality) - $($relation.Status) - $(Escape-Md $relation.Constraint)"
    )
}

Add-Line $Lines ""

Add-Line $Lines "## 7. Regles metier"
Add-Line $Lines ""
Add-Line $Lines "Domaine - Regle - Statut"
Add-Line $Lines "--- - --- - ---"

foreach ($rule in $BusinessRules) {

    Add-Line $Lines (
        "$(Escape-Md $rule.Area) - $(Escape-Md $rule.Rule) - $($rule.Status)"
    )
}

Add-Line $Lines ""

Add-Line $Lines "## 8. Decisions bloquantes avant ENV-11"
Add-Line $Lines ""

foreach ($decision in $BlockingDecisions) {

    Add-Line $Lines "- [ ] $decision"
}

Add-Line $Lines ""

Add-Line $Lines "## 9. Decisions pouvant etre traitees pendant ENV-11"
Add-Line $Lines ""

foreach ($decision in $DeferredToSchema) {

    Add-Line $Lines "- $decision"
}

Add-Line $Lines ""

Add-Line $Lines "## 10. Coherence interne"
Add-Line $Lines ""

if ($ConsistencyIssues.Count -eq 0) {

    Add-Line $Lines "**Aucune incoherence structurelle detectee dans le modele logique produit par ENV-10.**"

}
else {

    foreach ($issue in $ConsistencyIssues) {

        Add-Line $Lines "- $issue"
    }
}

Add-Line $Lines ""

Add-Line $Lines "## 11. Synthese"
Add-Line $Lines ""
Add-Line $Lines "Element - Nombre"
Add-Line $Lines "--- - ---:"
Add-Line $Lines "Entites confirmees - $ConfirmedEntityCount"
Add-Line $Lines "Entites probables - $ProbableEntityCount"
Add-Line $Lines "Entites hypothetiques - $HypotheticalEntityCount"
Add-Line $Lines "Relations confirmees - $ConfirmedRelationCount"
Add-Line $Lines "Relations probables - $ProbableRelationCount"
Add-Line $Lines "Tables d'association candidates - $($AssociationCandidates.Count)"
Add-Line $Lines "Decisions bloquantes - $($BlockingDecisions.Count)"
Add-Line $Lines ""

Add-Line $Lines "## 12. Etat de preparation du schema"
Add-Line $Lines ""
Add-Line $Lines "**schema.sql pret a etre genere : NON**"
Add-Line $Lines ""
Add-Line $Lines "La generation SQL doit rester bloquee tant que les decisions metier listees en section 8 ne sont pas explicitement validees."
Add-Line $Lines ""

Add-Line $Lines "## 13. Garanties forensic"
Add-Line $Lines ""
Add-Line $Lines "- Aucun CREATE DATABASE execute."
Add-Line $Lines "- Aucun CREATE TABLE execute."
Add-Line $Lines "- Aucun ALTER execute."
Add-Line $Lines "- Aucun DROP execute."
Add-Line $Lines "- Aucun INSERT execute."
Add-Line $Lines "- Aucun UPDATE execute."
Add-Line $Lines "- Aucun DELETE execute."
Add-Line $Lines "- Aucun TRUNCATE execute."
Add-Line $Lines "- Aucune migration executee."
Add-Line $Lines "- Aucun code applicatif modifie."
Add-Line $Lines "- Aucun service PostgreSQL modifie."
Add-Line $Lines "- Aucun service Apache modifie."
Add-Line $Lines ""

Add-Line $Lines "## 14. Prochaine etape"
Add-Line $Lines ""
Add-Line $Lines "**Validation humaine des decisions bloquantes, puis ENV-11 - PRODUCTION DU SCHEMA POSTGRESQL V1.**"
Add-Line $Lines ""

$EndTime = Get-Date

Add-Line $Lines "## 15. Execution"
Add-Line $Lines ""
Add-Line $Lines "- Debut : $($StartTime.ToString("yyyy-MM-dd HH:mm:ss"))"
Add-Line $Lines "- Fin : $($EndTime.ToString("yyyy-MM-dd HH:mm:ss"))"
Add-Line $Lines "- Fichiers analyses : $($Files.Count)"
Add-Line $Lines ""

$ReportText = $Lines -join "`r`n"

Set-Content `
    -LiteralPath $ReportPath `
    -Value $ReportText `
    -Encoding UTF8

Set-Content `
    -LiteralPath $FinalPath `
    -Value $ReportText `
    -Encoding UTF8

Set-Content `
    -LiteralPath $ModelPath `
    -Value $ReportText `
    -Encoding UTF8

# ============================================================
# 17. SORTIE CONSOLE
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host " ENV-10 — DATA MODEL V1 FINALIZATION"
Write-Host "============================================================"
Write-Host ""
Write-Host "VERDICT : $Verdict"
Write-Host ""
Write-Host "Entites confirmees       : $ConfirmedEntityCount"
Write-Host "Entites probables        : $ProbableEntityCount"
Write-Host "Entites hypothetiques    : $HypotheticalEntityCount"
Write-Host "Relations confirmees     : $ConfirmedRelationCount"
Write-Host "Relations probables      : $ProbableRelationCount"
Write-Host "Associations candidates  : $($AssociationCandidates.Count)"
Write-Host "Decisions bloquantes     : $($BlockingDecisions.Count)"
Write-Host "Incoherences             : $($ConsistencyIssues.Count)"
Write-Host ""
Write-Host "SCHEMA SQL PRET          : NON"
Write-Host ""
Write-Host "Rapport :"
Write-Host $ReportPath
Write-Host ""
Write-Host "Rapport final :"
Write-Host $FinalPath
Write-Host ""
Write-Host "Modele V1 :"
Write-Host $ModelPath
Write-Host ""
Write-Host "============================================================"
Write-Host " FIN ENV-10"
Write-Host "============================================================"
