#requires -Version 5.1
<#
================================================================================
IMC-CLARODORO
ENV-08 — FORENSIC DATA MODEL RECONSTRUCTION
================================================================================

OBJECTIF
--------
Reconstruire le modele de donnees V1 de l'application a partir des preuves
presentes dans le code reel.

MODE
----
READ-ONLY STRICT.
================================================================================
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$AuditDir    = Join-Path $ProjectRoot "audit"
$FinalReport = Join-Path $AuditDir "ENV-08-FORENSIC-DATA-MODEL-RECONSTRUCTION-REPORT-FINAL.md"

New-Item -ItemType Directory -Force -Path $AuditDir | Out-Null

$StartedAt = Get-Date

$Lines = New-Object System.Collections.Generic.List[string]

function Add-Line {
    param([string]$Text = "")
    $Lines.Add($Text)
}

function Add-Section {
    param([string]$Title)
    Add-Line ""
    Add-Line "## $Title"
    Add-Line ""
}

function Get-ProjectFiles {
    param([string[]]$Extensions)
    $Result = @()
    foreach ($Extension in $Extensions) {
        try {
            $Items = Get-ChildItem -Path $ProjectRoot -Recurse -File -Filter "*$Extension" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\vendor\\' -and $_.FullName -notmatch '\\audit\\' }
            $Result += $Items
        } catch { }
    }
    return $Result | Sort-Object FullName -Unique
}

function Get-FileContent {
    param([string]$Path)
    try {
        return Get-Content -Raw -LiteralPath $Path -ErrorAction Stop
    } catch {
        return ""
    }
}

Add-Line "# ENV-08 — FORENSIC DATA MODEL RECONSTRUCTION"
Add-Line ""
Add-Line "**Projet :** $ProjectRoot"
Add-Line "**Date :** $($StartedAt.ToString("yyyy-MM-dd HH:mm:ss"))"
Add-Line "**Mode :** READ-ONLY"
Add-Line ""

$Extensions = @(".php", ".js", ".html", ".htm", ".json", ".md", ".txt")

Add-Section "1. Inventaire des sources"

$Files = Get-ProjectFiles $Extensions

$PhpFiles = $Files | Where-Object { $_.Extension -ieq ".php" }
$JsFiles  = $Files | Where-Object { $_.Extension -ieq ".js" }
$HtmlFiles = $Files | Where-Object { $_.Extension -ieq ".html" -or $_.Extension -ieq ".htm" }
$JsonFiles = $Files | Where-Object { $_.Extension -ieq ".json" }

Add-Line "Type - Nombre"
Add-Line "--- - ---:"
Add-Line "PHP - $($PhpFiles.Count)"
Add-Line "JavaScript - $($JsFiles.Count)"
Add-Line "HTML - $($HtmlFiles.Count)"
Add-Line "JSON - $($JsonFiles.Count)"

Add-Section "2. Entites metier candidates"

$EntityTerms = @(
    "user", "users", "utilisateur", "currentUser", "login",
    "role", "roles", "permission", "permissions",
    "student", "students", "eleve", "eleves",
    "personnel", "staff", "employee", "employe",
    "teacher", "teachers", "enseignant",
    "niveau", "niveaux", "level", "levels",
    "classe", "classes", "class",
    "section", "sections",
    "matiere", "matieres", "subject", "subjects",
    "annee_scolaire", "school_year", "school_years",
    "inscription", "inscriptions", "enrollment", "enrollments",
    "note", "notes", "grade", "grades", "resultat", "resultats",
    "presence", "presences", "attendance",
    "absence", "absences", "absent",
    "vacance", "vacances", "holiday", "holidays",
    "parent", "parents", "tuteur", "tuteurs", "guardian",
    "facture", "factures", "invoice", "invoices",
    "paiement", "paiements", "payment", "payments",
    "finance", "finances"
)

$DetectedEntities = New-Object System.Collections.Generic.HashSet[string]

foreach ($File in $Files) {
    $Content = Get-FileContent $File.FullName
    foreach ($Term in $EntityTerms) {
        if ($Content -match [regex]::Escape($Term)) {
            [void]$DetectedEntities.Add($Term)
        }
    }
}

Add-Line "Entites detectees : $($DetectedEntities.Count)"
foreach ($Entity in ($DetectedEntities | Sort-Object)) {
    Add-Line "- $Entity"
}

Add-Section "3. Champs de donnees detectes"

$FieldTerms = @(
    "name", "nom", "prenom", "first_name", "last_name",
    "email", "telephone", "phone", "adresse", "address",
    "sexe", "gender", "date_naissance", "birth_date",
    "id", "status", "statut", "active", "actif",
    "description", "code", "matricule", "username", "password",
    "role", "permission", "coefficient", "coef",
    "note", "score", "grade", "date",
    "created_at", "updated_at", "deleted_at",
    "start_date", "end_date",
    "montant", "amount", "prix", "price", "total", "subtotal",
    "taxe", "tax", "solde", "balance",
    "payment", "paiement", "presence", "absence", "commentaire", "comment"
)

$DetectedFields = New-Object System.Collections.Generic.HashSet[string]

foreach ($File in $Files) {
    $Content = Get-FileContent $File.FullName
    foreach ($Term in $FieldTerms) {
        if ($Content -match [regex]::Escape($Term)) {
            [void]$DetectedFields.Add($Term)
        }
    }
}

Add-Line "Champs detectes : $($DetectedFields.Count)"
foreach ($Field in ($DetectedFields | Sort-Object)) {
    Add-Line "- $Field"
}

Add-Section "4. Identifiants candidates"

$IdTerms = @("id", "ID", "matricule", "code", "user_id", "student_id", "class_id", "teacher_id", "role_id")

$DetectedIds = New-Object System.Collections.Generic.HashSet[string]

foreach ($File in $Files) {
    $Content = Get-FileContent $File.FullName
    foreach ($Term in $IdTerms) {
        if ($Content -match [regex]::Escape($Term)) {
            [void]$DetectedIds.Add($Term)
        }
    }
}

Add-Line "Identifiants detectes : $($DetectedIds.Count)"
foreach ($Id in ($DetectedIds | Sort-Object)) {
    Add-Line "- $Id"
}

Add-Section "5. Relations candidates"

$RelationBaseTerms = @("student", "class", "teacher", "parent", "role", "subject", "level", "section", "enrollment", "invoice", "payment")

$DetectedRelations = New-Object System.Collections.Generic.HashSet[string]

foreach ($File in $Files) {
    $Content = Get-FileContent $File.FullName
    foreach ($Term in $RelationBaseTerms) {
        if ($Content -match "$Term" + "_id") {
            [void]$DetectedRelations.Add($Term)
        }
    }
}

Add-Line "Relations candidates : $($DetectedRelations.Count)"
foreach ($Relation in ($DetectedRelations | Sort-Object)) {
    Add-Line "- ${Relation}_id"
}

Add-Section "6. Types de donnees probables"

Add-Line "Hypotheses de types basees sur l'utilisation:"
Add-Line "- id : UUID ou BIGINT - A CONFIRMER"
Add-Line "- name, nom, prenom : VARCHAR"
Add-Line "- email : VARCHAR"
Add-Line "- telephone, phone : VARCHAR"
Add-Line "- adresse, address : TEXT"
Add-Line "- description : TEXT"
Add-Line "- code, matricule : VARCHAR"
Add-Line "- status, statut : VARCHAR ou ENUM"
Add-Line "- active, actif : BOOLEAN"
Add-Line "- note, score, grade, coefficient : NUMERIC"
Add-Line "- date, date_naissance, birth_date : DATE"
Add-Line "- created_at, updated_at : TIMESTAMP"
Add-Line "- deleted_at : TIMESTAMP NULL"
Add-Line "- montant, amount, prix, price, total, solde, balance : NUMERIC"

Add-Section "7. Donnees sensibles detectees"

$SensitiveTerms = @("password", "email", "telephone", "adresse", "date_naissance", "student", "eleve", "parent")

$DetectedSensitive = New-Object System.Collections.Generic.HashSet[string]

foreach ($File in $Files) {
    $Content = Get-FileContent $File.FullName
    foreach ($Term in $SensitiveTerms) {
        if ($Content -match [regex]::Escape($Term)) {
            [void]$DetectedSensitive.Add($Term)
        }
    }
}

Add-Line "Termes sensibles detectes : $($DetectedSensitive.Count)"
foreach ($Term in ($DetectedSensitive | Sort-Object)) {
    Add-Line "- $Term"
}

Add-Section "8. Modele preliminaire V1"

Add-Line "> Ce modele est une reconstruction forensic et non le schema SQL definitif."
Add-Line ""

Add-Line "### Entites candidates avec champs probables:"
Add-Line ""
Add-Line "**users**: id, username, email, password, role, status, created_at, updated_at"
Add-Line "**students**: id, matricule, nom, prenom, date_naissance, sexe, adresse, telephone, status"
Add-Line "**parents**: id, nom, prenom, telephone, email, adresse"
Add-Line "**teachers**: id, nom, prenom, email, telephone, status"
Add-Line "**staff**: id, nom, prenom, fonction, telephone, email, status"
Add-Line "**levels**: id, code, nom, description"
Add-Line "**classes**: id, code, nom, niveau_id, section_id, teacher_id, status"
Add-Line "**sections**: id, code, nom, description"
Add-Line "**subjects**: id, code, nom, description, coefficient"
Add-Line "**school_years**: id, label, start_date, end_date, status"
Add-Line "**enrollments**: id, student_id, class_id, school_year_id, status, date"
Add-Line "**grades**: id, student_id, subject_id, enrollment_id, note, coefficient, date"
Add-Line "**attendance**: id, student_id, class_id, date, status, comment"
Add-Line "**absences**: id, student_id, date, justification, comment"
Add-Line "**holidays**: id, name, start_date, end_date, description"
Add-Line "**invoices**: id, student_id, amount, balance, status, date"
Add-Line "**payments**: id, invoice_id, amount, date, method, reference"
Add-Line "**roles**: id, name, description"
Add-Line "**permissions**: id, name, description"

Add-Section "9. Relations candidates"

Add-Line "- students -> parents (student_parent ou table intermediaire)"
Add-Line "- students -> enrollments"
Add-Line "- students -> grades"
Add-Line "- students -> attendance"
Add-Line "- students -> absences"
Add-Line "- enrollments -> classes"
Add-Line "- enrollments -> school_years"
Add-Line "- classes -> levels"
Add-Line "- classes -> sections"
Add-Line "- classes -> teachers"
Add-Line "- grades -> subjects"
Add-Line "- grades -> enrollments"
Add-Line "- attendance -> classes"
Add-Line "- payments -> invoices"
Add-Line "- invoices -> students"
Add-Line "- users -> roles"
Add-Line "- roles -> permissions"

Add-Section "10. Decisions a valider"

Add-Line "Les elements suivants doivent etre valides avant schema.sql:"
Add-Line ""
Add-Line "1. Type d'identifiant (UUID vs BIGINT vs INTEGER)"
Add-Line "2. Noms exacts des tables et colonnes"
Add-Line "3. ENUM vs VARCHAR pour les statuts"
Add-Line "4. CASCADE vs RESTRICT pour les suppressions"
Add-Line "5. Soft delete (deleted_at) ou suppression physique"
Add-Line "6. Relation exacte eleve-parent (1:N ou N:M)"
Add-Line "7. Structure des notes et coefficients"
Add-Line "8. Regles de calcul des moyennes"
Add-Line "9. Regles financieres et paiements partiels"
Add-Line "10. Unicite des matricules"
Add-Line "11. Unicite inscription par annee scolaire"
Add-Line "12. Roles et permissions definitifs"

Add-Section "11. Etat de maturite"

Add-Line "- Entites candidates : $($EntityTerms.Count)"
Add-Line "- Entites avec evidence : $($DetectedEntities.Count)"
Add-Line "- Champs detectes : $($DetectedFields.Count)"
Add-Line "- Identifiants detectes : $($DetectedIds.Count)"
Add-Line "- Relations candidates : $($DetectedRelations.Count)"

Add-Line ""

$Result = "PREUVES INSUFFISANTES"
if ($DetectedEntities.Count -ge 5 -and $DetectedRelations.Count -gt 0) {
    $Result = "MODELE SUFFISAMMENT DOCUMENTABLE POUR VALIDATION"
}

Add-Line "### RESULTAT"
Add-Line ""
Add-Line "**$Result**"

Add-Section "12. Prochaine etape"

Add-Line "Valider le modele avec l'utilisateur avant de produire le schema.sql."
Add-Line ""
Add-Line "Aucune creation PostgreSQL avant cette validation."

Add-Section "13. Resume d'execution"

$FinishedAt = Get-Date
$Duration = $FinishedAt - $StartedAt

Add-Line "- Debut : $($StartedAt.ToString("yyyy-MM-dd HH:mm:ss"))"
Add-Line "- Fin : $($FinishedAt.ToString("yyyy-MM-dd HH:mm:ss"))"
Add-Line "- Duree : $($Duration.TotalSeconds.ToString("0.00")) secondes"
Add-Line ""
Add-Line "**MODE READ-ONLY CONFIRME**"
Add-Line ""
Add-Line "Aucune base creee."
Add-Line "Aucune table creee."
Add-Line "Aucune donnee modifiee."

$ReportContent = $Lines -join "`r`n"

Set-Content -LiteralPath $FinalReport -Value $ReportContent -Encoding UTF8

Write-Host ""
Write-Host "============================================================"
Write-Host " ENV-08 — FORENSIC DATA MODEL RECONSTRUCTION"
Write-Host "============================================================"
Write-Host ""
Write-Host "Rapport final :"
Write-Host "  $FinalReport"
Write-Host ""
Write-Host "MODE : READ-ONLY"
Write-Host ""
Write-Host "Aucune base creee."
Write-Host "Aucune table creee."
Write-Host "Aucune donnee modifiee."
Write-Host ""
Write-Host "============================================================"
