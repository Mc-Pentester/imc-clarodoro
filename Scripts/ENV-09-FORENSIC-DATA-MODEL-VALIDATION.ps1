#requires -Version 5.1
<#
ENV-09 — FORENSIC DATA MODEL VALIDATION & CONSISTENCY AUDIT

Projet :
C:\IMC-Clarodoro-securise-client\IMC-Clarodoro

OBJECTIF
--------
Valider forensicement le modele de donnees reconstruit par ENV-08
contre le code reellement present dans l'application.

MODE READ-ONLY STRICT
---------------------
Ce script NE DOIT PAS :
- creer une base PostgreSQL
- creer une table
- modifier PostgreSQL
- creer/modifier/supprimer des donnees
- modifier le code applicatif
- modifier database/schema.sql
- executer une migration
- installer une dependance
- demarrer/arrêter PostgreSQL
- demarrer/arrêter Apache
- effectuer de commit/push Git

SORTIES
-------
audit\ENV-09-FORENSIC-DATA-MODEL-VALIDATION-REPORT.md
audit\ENV-09-FORENSIC-DATA-MODEL-VALIDATION-REPORT-FINAL.md
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# 1. CONFIGURATION
# ============================================================

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$AuditDir    = Join-Path $ProjectRoot "audit"

$ReportPath       = Join-Path $AuditDir "ENV-09-FORENSIC-DATA-MODEL-VALIDATION-REPORT.md"
$FinalReportPath  = Join-Path $AuditDir "ENV-09-FORENSIC-DATA-MODEL-VALIDATION-REPORT-FINAL.md"

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Projet introuvable : $ProjectRoot"
}

if (-not (Test-Path -LiteralPath $AuditDir -PathType Container)) {
    New-Item -ItemType Directory -Path $AuditDir -Force | Out-Null
}

# ============================================================
# 2. ETAT FORENSIC
# ============================================================

$StartTime = Get-Date

$Results = New-Object System.Collections.Generic.List[object]
$Warnings = New-Object System.Collections.Generic.List[string]
$Issues   = New-Object System.Collections.Generic.List[string]

function Add-Result {
    param(
        [string]$Category,
        [string]$Item,
        [string]$Status,
        [string]$Evidence,
        [string]$Details = ""
    )

    $Results.Add([PSCustomObject]@{
        Category = $Category
        Item     = $Item
        Status   = $Status
        Evidence = $Evidence
        Details  = $Details
    })
}

function Add-Warning {
    param([string]$Message)

    $Warnings.Add($Message)
}

function Add-Issue {
    param([string]$Message)

    $Issues.Add($Message)
}

function Normalize-Text {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return $Text.ToLowerInvariant()
}

function Get-LineNumber {
    param(
        [string]$Content,
        [int]$Index
    )

    if ($Index -le 0) {
        return 1
    }

    return (($Content.Substring(0, [Math]::Min($Index, $Content.Length)) -split "`n").Count)
}

function Get-Snippet {
    param(
        [string]$Content,
        [int]$Index,
        [int]$Radius = 180
    )

    if ($null -eq $Content) {
        return ""
    }

    $start = [Math]::Max(0, $Index - $Radius)
    $length = [Math]::Min(
        $Radius * 2,
        $Content.Length - $start
    )

    if ($length -le 0) {
        return ""
    }

    $snippet = $Content.Substring($start, $length)
    $snippet = $snippet -replace "`r", " " -replace "`n", " "
    $snippet = $snippet -replace "\s+", " "

    return $snippet.Trim()
}

function Escape-Markdown {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return $Text.Replace("|","\|")
}

# ============================================================
# 3. INVENTAIRE DES SOURCES
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
        -File `
        -Recurse `
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

$FileInventory = foreach ($file in $Files) {
    [PSCustomObject]@{
        FullName  = $file.FullName
        Relative  = $file.FullName.Substring($ProjectRoot.Length).TrimStart("\")
        Extension = $file.Extension.ToLowerInvariant()
        Size      = $file.Length
    }
}

$PhpCount  = @($Files | Where-Object Extension -eq ".php").Count
$JsCount   = @($Files | Where-Object Extension -eq ".js").Count
$HtmlCount = @($Files | Where-Object { $_.Extension -in @(".html",".htm") }).Count
$JsonCount = @($Files | Where-Object Extension -eq ".json").Count
$MdCount   = @($Files | Where-Object Extension -eq ".md").Count
$TxtCount  = @($Files | Where-Object Extension -eq ".txt").Count

Add-Result `
    -Category "INVENTORY" `
    -Item "Application source inventory" `
    -Status "PASS" `
    -Evidence "$($Files.Count) fichiers analysables" `
    -Details "PHP=$PhpCount; JS=$JsCount; HTML=$HtmlCount; JSON=$JsonCount; MD=$MdCount; TXT=$TxtCount"

# ============================================================
# 4. LECTURE READ-ONLY DU CODE
# ============================================================

$SourceRecords = New-Object System.Collections.Generic.List[object]

foreach ($file in $Files) {

    try {
        $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop

        $SourceRecords.Add([PSCustomObject]@{
            FullName = $file.FullName
            Relative = $file.FullName.Substring($ProjectRoot.Length).TrimStart("\")
            Extension = $file.Extension.ToLowerInvariant()
            Content = $content
        })
    }
    catch {
        Add-Warning "Lecture impossible : $($file.FullName)"
    }
}

# ============================================================
# 5. DEFINITIONS DU MODELE ENV-08
# ============================================================

$ModelEntities = @{

    users = @(
        "id",
        "username",
        "email",
        "password",
        "role",
        "status",
        "created_at",
        "updated_at"
    )

    students = @(
        "id",
        "matricule",
        "nom",
        "prenom",
        "date_naissance",
        "sexe",
        "adresse",
        "telephone",
        "status"
    )

    parents = @(
        "id",
        "nom",
        "prenom",
        "telephone",
        "email",
        "adresse"
    )

    teachers = @(
        "id",
        "nom",
        "prenom",
        "email",
        "telephone",
        "status"
    )

    staff = @(
        "id",
        "nom",
        "prenom",
        "fonction",
        "telephone",
        "email",
        "status"
    )

    levels = @(
        "id",
        "code",
        "nom",
        "description"
    )

    classes = @(
        "id",
        "code",
        "nom",
        "niveau_id",
        "section_id",
        "teacher_id",
        "status"
    )

    sections = @(
        "id",
        "code",
        "nom",
        "description"
    )

    subjects = @(
        "id",
        "code",
        "nom",
        "description",
        "coefficient"
    )

    school_years = @(
        "id",
        "label",
        "start_date",
        "end_date",
        "status"
    )

    enrollments = @(
        "id",
        "student_id",
        "class_id",
        "school_year_id",
        "status",
        "date"
    )

    grades = @(
        "id",
        "student_id",
        "subject_id",
        "enrollment_id",
        "note",
        "coefficient",
        "date"
    )

    attendance = @(
        "id",
        "student_id",
        "class_id",
        "date",
        "status",
        "comment"
    )

    absences = @(
        "id",
        "student_id",
        "date",
        "justification",
        "comment"
    )

    holidays = @(
        "id",
        "name",
        "start_date",
        "end_date",
        "description"
    )

    invoices = @(
        "id",
        "student_id",
        "amount",
        "balance",
        "status",
        "date"
    )

    payments = @(
        "id",
        "invoice_id",
        "amount",
        "date",
        "method",
        "reference"
    )

    roles = @(
        "id",
        "name",
        "description"
    )

    permissions = @(
        "id",
        "name",
        "description"
    )
}

# ============================================================
# 6. ALIAS / VARIANTS
# ============================================================

$EntityAliases = @{

    users = @(
        "user",
        "users",
        "utilisateur",
        "utilisateurs",
        "currentUser",
        "current_user"
    )

    students = @(
        "student",
        "students",
        "eleve",
        "eleves",
        "eleve",
        "eleves"
    )

    parents = @(
        "parent",
        "parents",
        "parent_id",
        "parentId"
    )

    teachers = @(
        "teacher",
        "teachers",
        "enseignant",
        "enseignants"
    )

    staff = @(
        "staff",
        "personnel",
        "employee",
        "employees"
    )

    levels = @(
        "level",
        "levels",
        "niveau",
        "niveaux"
    )

    classes = @(
        "class",
        "classes",
        "classe",
        "class_id",
        "classId"
    )

    sections = @(
        "section",
        "sections"
    )

    subjects = @(
        "subject",
        "subjects",
        "matiere",
        "matieres",
        "matiere",
        "matieres"
    )

    school_years = @(
        "school_year",
        "school_years",
        "schoolYear",
        "schoolYears",
        "annee_scolaire",
        "annees_scolaires",
        "annee_scolaire",
        "annees_scolaires"
    )

    enrollments = @(
        "enrollment",
        "enrollments",
        "inscription",
        "inscriptions"
    )

    grades = @(
        "grade",
        "grades",
        "note",
        "notes",
        "result",
        "results",
        "resultat",
        "resultats",
        "resultat",
        "resultats"
    )

    attendance = @(
        "attendance",
        "presence",
        "presences",
        "presence",
        "presences"
    )

    absences = @(
        "absence",
        "absences"
    )

    holidays = @(
        "holiday",
        "holidays",
        "vacance",
        "vacances"
    )

    invoices = @(
        "invoice",
        "invoices",
        "facture",
        "factures"
    )

    payments = @(
        "payment",
        "payments",
        "paiement",
        "paiements"
    )

    roles = @(
        "role",
        "roles",
        "role",
        "roles"
    )

    permissions = @(
        "permission",
        "permissions"
    )
}

# ============================================================
# 7. DETECTION D'UTILISATION DES ENTITES
# ============================================================

$EntityEvidence = @{}

foreach ($entity in $ModelEntities.Keys) {

    $aliases = @($EntityAliases[$entity])

    $matches = New-Object System.Collections.Generic.List[object]

    foreach ($source in $SourceRecords) {

        foreach ($alias in $aliases) {

            if ([string]::IsNullOrWhiteSpace($alias)) {
                continue
            }

            $pattern = [regex]::Escape($alias)

            $regex = New-Object System.Text.RegularExpressions.Regex(
                $pattern,
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )

            foreach ($match in $regex.Matches($source.Content)) {

                $line = Get-LineNumber `
                    -Content $source.Content `
                    -Index $match.Index

                $snippet = Get-Snippet `
                    -Content $source.Content `
                    -Index $match.Index

                $matches.Add([PSCustomObject]@{
                    Entity  = $entity
                    Alias   = $alias
                    File    = $source.Relative
                    Line    = $line
                    Snippet = $snippet
                })

                if ($matches.Count -ge 40) {
                    break
                }
            }

            if ($matches.Count -ge 40) {
                break
            }
        }
    }

    $EntityEvidence[$entity] = @($matches)
}

# ============================================================
# 8. CLASSIFICATION DES ENTITES
# ============================================================

$EntityValidation = New-Object System.Collections.Generic.List[object]

foreach ($entity in $ModelEntities.Keys) {

    $evidence = @($EntityEvidence[$entity])

    $uniqueFiles = @(
        $evidence |
        Select-Object -ExpandProperty File -Unique
    )

    $count = $evidence.Count

    if ($count -eq 0) {
        $status = "NON-DETERMINABLE"
    }
    elseif ($count -ge 8 -or $uniqueFiles.Count -ge 4) {
        $status = "CONFIRME"
    }
    elseif ($count -ge 3 -or $uniqueFiles.Count -ge 2) {
        $status = "FORTEMENT-PROBABLE"
    }
    else {
        $status = "HYPOTHESE"
    }

    $sample = ""
    if ($evidence.Count -gt 0) {
        $sample = (($evidence | Select-Object -First 3 | ForEach-Object {
            "$($_.File):$($_.Line)"
        }) -join "; ")
    }

    $EntityValidation.Add([PSCustomObject]@{
        Entity       = $entity
        EvidenceHits = $count
        Files        = $uniqueFiles.Count
        Status       = $status
        Evidence     = $sample
    })
}

# ============================================================
# 9. VALIDATION DES CHAMPS
# ============================================================

$FieldCandidates = @{

    id             = @("id","\bid\b")
    username       = @("username","user_name","login")
    email          = @("email","e-mail")
    password       = @("password","mot_de_passe","motdepasse")
    role           = @("role","role_id","roleId")
    status         = @("status","statut","active","actif")
    matricule      = @("matricule")
    nom            = @("nom","last_name","lastname")
    prenom         = @("prenom","first_name","firstname","prenom")
    date_naissance = @("date_naissance","birth_date","dateOfBirth","date_naissance")
    sexe           = @("sexe","gender")
    adresse        = @("adresse","address")
    telephone      = @("telephone","phone","tel")
    fonction       = @("fonction","position","job")
    code           = @("code")
    description    = @("description")
    coefficient    = @("coefficient","coef")
    note           = @("note","score","grade")
    created_at     = @("created_at","createdAt")
    updated_at     = @("updated_at","updatedAt")
    deleted_at     = @("deleted_at","deletedAt")
    date           = @("date")
    start_date     = @("start_date","startDate","date_debut")
    end_date       = @("end_date","endDate","date_fin")
    montant        = @("montant","amount")
    prix           = @("prix","price")
    total          = @("total")
    subtotal       = @("subtotal","sous_total")
    taxe           = @("tax","taxe")
    solde          = @("solde","balance")
    payment        = @("payment","paiement")
    method         = @("method","payment_method","methode")
    reference      = @("reference","reference")
    justification  = @("justification")
    comment        = @("comment","commentaire")
}

$FieldEvidence = @{}

foreach ($field in $FieldCandidates.Keys) {

    $matches = New-Object System.Collections.Generic.List[object]

    foreach ($source in $SourceRecords) {

        foreach ($alias in $FieldCandidates[$field]) {

            $pattern = $alias

            try {
                $regex = New-Object System.Text.RegularExpressions.Regex(
                    $pattern,
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
                )
            }
            catch {
                continue
            }

            foreach ($match in $regex.Matches($source.Content)) {

                $line = Get-LineNumber `
                    -Content $source.Content `
                    -Index $match.Index

                $snippet = Get-Snippet `
                    -Content $source.Content `
                    -Index $match.Index

                $matches.Add([PSCustomObject]@{
                    Field   = $field
                    Alias   = $alias
                    File    = $source.Relative
                    Line    = $line
                    Snippet = $snippet
                })

                if ($matches.Count -ge 30) {
                    break
                }
            }

            if ($matches.Count -ge 30) {
                break
            }
        }
    }

    $FieldEvidence[$field] = @($matches)
}

# ============================================================
# 10. VALIDATION DES RELATIONS
# ============================================================

$RelationCandidates = @(
    [PSCustomObject]@{
        Name = "students -> parents"
        Patterns = @(
            "parent_id",
            "parentId",
            "student_parent",
            "studentParent",
            "parent.*student",
            "student.*parent"
        )
    },
    [PSCustomObject]@{
        Name = "students -> enrollments"
        Patterns = @(
            "student_id",
            "studentId",
            "enrollment.*student",
            "student.*enrollment",
            "inscription.*eleve",
            "eleve.*inscription"
        )
    },
    [PSCustomObject]@{
        Name = "students -> grades"
        Patterns = @(
            "student_id.*note",
            "studentId.*grade",
            "grade.*student",
            "note.*student",
            "result.*student"
        )
    },
    [PSCustomObject]@{
        Name = "students -> attendance"
        Patterns = @(
            "student_id.*attendance",
            "attendance.*student",
            "presence.*student",
            "student.*presence"
        )
    },
    [PSCustomObject]@{
        Name = "students -> absences"
        Patterns = @(
            "student_id.*absence",
            "absence.*student",
            "student.*absence"
        )
    },
    [PSCustomObject]@{
        Name = "enrollments -> classes"
        Patterns = @(
            "class_id",
            "classId",
            "enrollment.*class",
            "inscription.*classe"
        )
    },
    [PSCustomObject]@{
        Name = "enrollments -> school_years"
        Patterns = @(
            "school_year_id",
            "schoolYearId",
            "enrollment.*school.*year",
            "inscription.*annee",
            "inscription.*annee"
        )
    },
    [PSCustomObject]@{
        Name = "classes -> levels"
        Patterns = @(
            "level_id",
            "levelId",
            "niveau_id",
            "classe.*niveau"
        )
    },
    [PSCustomObject]@{
        Name = "classes -> sections"
        Patterns = @(
            "section_id",
            "sectionId",
            "classe.*section"
        )
    },
    [PSCustomObject]@{
        Name = "classes -> teachers"
        Patterns = @(
            "teacher_id",
            "teacherId",
            "classe.*enseignant",
            "class.*teacher"
        )
    },
    [PSCustomObject]@{
        Name = "grades -> subjects"
        Patterns = @(
            "subject_id",
            "subjectId",
            "matiere_id",
            "matiere_id",
            "grade.*subject",
            "note.*matiere",
            "note.*matiere"
        )
    },
    [PSCustomObject]@{
        Name = "grades -> enrollments"
        Patterns = @(
            "enrollment_id",
            "enrollmentId",
            "grade.*enrollment",
            "note.*inscription"
        )
    },
    [PSCustomObject]@{
        Name = "attendance -> classes"
        Patterns = @(
            "attendance.*class",
            "presence.*classe",
            "class_id.*attendance"
        )
    },
    [PSCustomObject]@{
        Name = "payments -> invoices"
        Patterns = @(
            "invoice_id",
            "invoiceId",
            "payment.*invoice",
            "paiement.*facture"
        )
    },
    [PSCustomObject]@{
        Name = "invoices -> students"
        Patterns = @(
            "invoice.*student",
            "facture.*eleve",
            "facture.*eleve",
            "student_id.*invoice"
        )
    },
    [PSCustomObject]@{
        Name = "users -> roles"
        Patterns = @(
            "role_id",
            "roleId",
            "user.*role",
            "utilisateur.*role",
            "utilisateur.*role"
        )
    },
    [PSCustomObject]@{
        Name = "roles -> permissions"
        Patterns = @(
            "permission_id",
            "permissionId",
            "role.*permission",
            "role.*permission"
        )
    }
)

$RelationValidation = New-Object System.Collections.Generic.List[object]

foreach ($relation in $RelationCandidates) {

    $matches = New-Object System.Collections.Generic.List[object]

    foreach ($source in $SourceRecords) {

        foreach ($pattern in $relation.Patterns) {

            try {
                $regex = New-Object System.Text.RegularExpressions.Regex(
                    $pattern,
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
                )
            }
            catch {
                continue
            }

            foreach ($match in $regex.Matches($source.Content)) {

                $line = Get-LineNumber `
                    -Content $source.Content `
                    -Index $match.Index

                $snippet = Get-Snippet `
                    -Content $source.Content `
                    -Index $match.Index

                $matches.Add([PSCustomObject]@{
                    Relation = $relation.Name
                    Pattern  = $pattern
                    File     = $source.Relative
                    Line     = $line
                    Snippet  = $snippet
                })

                if ($matches.Count -ge 20) {
                    break
                }
            }

            if ($matches.Count -ge 20) {
                break
            }
        }

        if ($matches.Count -ge 20) {
            break
        }
    }

    $uniqueFiles = @(
        $matches |
        Select-Object -ExpandProperty File -Unique
    )

    if ($matches.Count -eq 0) {
        $status = "NON-DETERMINEE"
    }
    elseif ($matches.Count -ge 5 -or $uniqueFiles.Count -ge 3) {
        $status = "CONFIRMEE"
    }
    elseif ($matches.Count -ge 2 -or $uniqueFiles.Count -ge 2) {
        $status = "PROBABLE"
    }
    else {
        $status = "HYPOTHESE"
    }

    $sample = ""
    if ($matches.Count -gt 0) {
        $sample = (($matches | Select-Object -First 3 | ForEach-Object {
            "$($_.File):$($_.Line)"
        }) -join "; ")
    }

    $RelationValidation.Add([PSCustomObject]@{
        Relation    = $relation.Name
        EvidenceHits = $matches.Count
        Files       = $uniqueFiles.Count
        Status      = $status
        Evidence    = $sample
    })
}

# ============================================================
# 11. DETECTION DES FK EXPLICITES
# ============================================================

$ForeignKeyMatches = New-Object System.Collections.Generic.List[object]

foreach ($source in $SourceRecords) {

    $patterns = @(
        '\b[a-zA-Z][a-zA-Z0-9]*_id\b',
        '\b[a-zA-Z][a-zA-Z0-9]*Id\b'
    )

    foreach ($pattern in $patterns) {

        $regex = New-Object System.Text.RegularExpressions.Regex(
            $pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        foreach ($match in $regex.Matches($source.Content)) {

            $value = $match.Value

            $line = Get-LineNumber `
                -Content $source.Content `
                -Index $match.Index

            $snippet = Get-Snippet `
                -Content $source.Content `
                -Index $match.Index

            $ForeignKeyMatches.Add([PSCustomObject]@{
                Field   = $value
                File    = $source.Relative
                Line    = $line
                Snippet = $snippet
            })

            if ($ForeignKeyMatches.Count -ge 500) {
                break
            }
        }

        if ($ForeignKeyMatches.Count -ge 500) {
            break
        }
    }

    if ($ForeignKeyMatches.Count -ge 500) {
        break
    }
}

$UniqueForeignKeys = @(
    $ForeignKeyMatches |
    Select-Object -ExpandProperty Field -Unique |
    Sort-Object
)

# ============================================================
# 12. STATUTS / ENUMERATIONS OBSERVES
# ============================================================

$StatusPatterns = @(
    "status",
    "statut",
    "active",
    "actif",
    "etat",
    "etat"
)

$StatusValues = New-Object System.Collections.Generic.List[object]

foreach ($source in $SourceRecords) {

    foreach ($pattern in $StatusPatterns) {

        $regex = New-Object System.Text.RegularExpressions.Regex(
            "(?i)(?:$pattern)\s*[:=]\s*['""]([^'""]+)['""]"
        )

        foreach ($match in $regex.Matches($source.Content)) {

            $value = $match.Groups[1].Value

            if (-not [string]::IsNullOrWhiteSpace($value)) {

                $StatusValues.Add([PSCustomObject]@{
                    Value = $value
                    File  = $source.Relative
                    Line  = Get-LineNumber `
                        -Content $source.Content `
                        -Index $match.Index
                })
            }
        }
    }
}

$UniqueStatusValues = @(
    $StatusValues |
    Select-Object -ExpandProperty Value -Unique |
    Sort-Object
)

# ============================================================
# 13. LOCALSTORAGE / CLIENT STATE
# ============================================================

$LocalStorageKeys = New-Object System.Collections.Generic.List[object]

foreach ($source in $SourceRecords) {

    if ($source.Extension -ne ".js" -and
        $source.Extension -ne ".html" -and
        $source.Extension -ne ".htm") {
        continue
    }

    $regex = New-Object System.Text.RegularExpressions.Regex(
        '(?:localStorage|sessionStorage)\.(?:getItem|setItem|removeItem)\s*\(\s*[''"]([^''"]+)[''"]',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    foreach ($match in $regex.Matches($source.Content)) {

        $LocalStorageKeys.Add([PSCustomObject]@{
            Key  = $match.Groups[1].Value
            File = $source.Relative
            Line = Get-LineNumber `
                -Content $source.Content `
                -Index $match.Index
        })
    }
}

$UniqueLocalStorageKeys = @(
    $LocalStorageKeys |
    Select-Object -ExpandProperty Key -Unique |
    Sort-Object
)

# ============================================================
# 14. REGLES METIER DETECTEES
# ============================================================

$BusinessRulePatterns = @{

    "authentication" = @(
        "login",
        "logout",
        "isAuthenticated",
        "currentUser",
        "requireRole",
        "requirePermission",
        "auth"
    )

    "enrollment" = @(
        "inscription",
        "enrollment",
        "school.year",
        "annee.scolaire",
        "annee.scolaire"
    )

    "grading" = @(
        "note",
        "score",
        "grade",
        "coefficient",
        "moyenne",
        "average"
    )

    "attendance" = @(
        "presence",
        "presence",
        "absence",
        "attendance"
    )

    "finance" = @(
        "facture",
        "invoice",
        "paiement",
        "payment",
        "montant",
        "amount",
        "solde",
        "balance",
        "prix",
        "price"
    )

    "permissions" = @(
        "permission",
        "role",
        "role",
        "access",
        "autorisation"
    )

    "soft_delete" = @(
        "deleted_at",
        "deletedAt",
        "soft.delete",
        "archive",
        "archived"
    )
}

$BusinessRuleEvidence = @{}

foreach ($rule in $BusinessRulePatterns.Keys) {

    $hits = New-Object System.Collections.Generic.List[object]

    foreach ($source in $SourceRecords) {

        foreach ($pattern in $BusinessRulePatterns[$rule]) {

            $regex = New-Object System.Text.RegularExpressions.Regex(
                [regex]::Escape($pattern),
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )

            foreach ($match in $regex.Matches($source.Content)) {

                $hits.Add([PSCustomObject]@{
                    Rule    = $rule
                    Pattern = $pattern
                    File    = $source.Relative
                    Line    = Get-LineNumber `
                        -Content $source.Content `
                        -Index $match.Index
                })

                if ($hits.Count -ge 50) {
                    break
                }
            }

            if ($hits.Count -ge 50) {
                break
            }
        }

        if ($hits.Count -ge 50) {
            break
        }
    }

    $BusinessRuleEvidence[$rule] = @($hits)
}

# ============================================================
# 15. CONTRAINTES / UNICITE
# ============================================================

$ConstraintPatterns = @(
    "unique",
    "unicite",
    "unicite",
    "duplicate",
    "duplicat",
    "already exists",
    "existe deja",
    "existe deja",
    "required",
    "obligatoire",
    "maxlength",
    "minlength",
    "pattern",
    "validate",
    "validation"
)

$ConstraintEvidence = New-Object System.Collections.Generic.List[object]

foreach ($source in $SourceRecords) {

    foreach ($pattern in $ConstraintPatterns) {

        $regex = New-Object System.Text.RegularExpressions.Regex(
            [regex]::Escape($pattern),
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        foreach ($match in $regex.Matches($source.Content)) {

            $ConstraintEvidence.Add([PSCustomObject]@{
                Pattern = $pattern
                File    = $source.Relative
                Line    = Get-LineNumber `
                    -Content $source.Content `
                    -Index $match.Index
                Snippet = Get-Snippet `
                    -Content $source.Content `
                    -Index $match.Index
            })

            if ($ConstraintEvidence.Count -ge 200) {
                break
            }
        }

        if ($ConstraintEvidence.Count -ge 200) {
            break
        }
    }

    if ($ConstraintEvidence.Count -ge 200) {
        break
    }
}

# ============================================================
# 16. DETECTION DES INCOHERENCES DE NOMMAGE
# ============================================================

$NamingFamilies = @{
    "student" = @(
        "student",
        "students",
        "eleve",
        "eleves",
        "eleve",
        "eleves"
    )

    "subject" = @(
        "subject",
        "subjects",
        "matiere",
        "matieres",
        "matiere",
        "matieres"
    )

    "school_year" = @(
        "school_year",
        "schoolYear",
        "schoolYears",
        "annee_scolaire",
        "annees_scolaires",
        "annee_scolaire",
        "annees_scolaires"
    )

    "class" = @(
        "class",
        "classes",
        "classe"
    )

    "teacher" = @(
        "teacher",
        "teachers",
        "enseignant",
        "enseignants"
    )

    "parent" = @(
        "parent",
        "parents"
    )

    "invoice" = @(
        "invoice",
        "invoices",
        "facture",
        "factures"
    )

    "payment" = @(
        "payment",
        "payments",
        "paiement",
        "paiements"
    )
}

$NamingFindings = New-Object System.Collections.Generic.List[object]

foreach ($family in $NamingFamilies.Keys) {

    $variantsFound = New-Object System.Collections.Generic.List[string]

    foreach ($source in $SourceRecords) {

        foreach ($variant in $NamingFamilies[$family]) {

            if ($source.Content -match [regex]::Escape($variant)) {
                if (-not $variantsFound.Contains($variant)) {
                    $variantsFound.Add($variant)
                }
            }
        }
    }

    if ($variantsFound.Count -gt 1) {

        $NamingFindings.Add([PSCustomObject]@{
            Family   = $family
            Variants = ($variantsFound -join ", ")
            Status   = "INCONSISTENCE-POTENTIELLE"
        })
    }
}

# ============================================================
# 17. DETECTION DES DONNEES SENSIBLES
# ============================================================

$SensitivePatterns = @(
    "password",
    "mot_de_passe",
    "token",
    "secret",
    "email",
    "telephone",
    "phone",
    "adresse",
    "address",
    "date_naissance",
    "birth_date",
    "student",
    "eleve",
    "eleve",
    "parent"
)

$SensitiveEvidence = New-Object System.Collections.Generic.List[object]

foreach ($source in $SourceRecords) {

    foreach ($pattern in $SensitivePatterns) {

        $regex = New-Object System.Text.RegularExpressions.Regex(
            [regex]::Escape($pattern),
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        foreach ($match in $regex.Matches($source.Content)) {

            $SensitiveEvidence.Add([PSCustomObject]@{
                Pattern = $pattern
                File    = $source.Relative
                Line    = Get-LineNumber `
                    -Content $source.Content `
                    -Index $match.Index
            })

            if ($SensitiveEvidence.Count -ge 200) {
                break
            }
        }

        if ($SensitiveEvidence.Count -ge 200) {
            break
        }
    }

    if ($SensitiveEvidence.Count -ge 200) {
        break
    }
}

# ============================================================
# 18. MATRICE DE DECISION
# ============================================================

$ConfirmedEntities = @(
    $EntityValidation |
    Where-Object Status -eq "CONFIRME"
)

$ProbableEntities = @(
    $EntityValidation |
    Where-Object Status -eq "FORTEMENT-PROBABLE"
)

$HypothesisEntities = @(
    $EntityValidation |
    Where-Object Status -eq "HYPOTHESE"
)

$UndeterminedEntities = @(
    $EntityValidation |
    Where-Object Status -eq "NON-DETERMINABLE"
)

$ConfirmedRelations = @(
    $RelationValidation |
    Where-Object Status -eq "CONFIRMEE"
)

$ProbableRelations = @(
    $RelationValidation |
    Where-Object Status -eq "PROBABLE"
)

$HypothesisRelations = @(
    $RelationValidation |
    Where-Object Status -eq "HYPOTHESE"
)

$UndeterminedRelations = @(
    $RelationValidation |
    Where-Object Status -eq "NON-DETERMINEE"
)

# ============================================================
# 19. DECISIONS NON AUTOMATISABLES
# ============================================================

$OpenDecisions = @(
    "UUID vs BIGINT vs INTEGER",
    "Noms definitifs des tables",
    "Noms definitifs des colonnes",
    "ENUM vs VARCHAR",
    "CASCADE vs RESTRICT",
    "Soft delete vs suppression physique",
    "Relation eleve-parent 1:N vs N:M",
    "Affectation enseignant-classe-matiere",
    "Structure definitive des notes",
    "Structure des coefficients",
    "Calcul des moyennes",
    "Gestion des annees scolaires",
    "Regles d'inscription",
    "Unicite du matricule",
    "Unicite d'une inscription par annee scolaire",
    "Regles de presence",
    "Regles d'absence et justification",
    "Facturation",
    "Paiements partiels",
    "Solde des factures",
    "Methodes de paiement",
    "Roles definitifs",
    "Permissions definitives",
    "Historisation des donnees sensibles"
)

# ============================================================
# 20. EVALUATION GLOBALE
# ============================================================

$GlobalStatus = "GO-VALIDATION-CONTINUE"

if ($ConfirmedEntities.Count -lt 10) {
    $GlobalStatus = "MODELE-INCOMPLET"
    Add-Issue "Moins de 10 entites sont fortement confirmees par le code."
}

if ($UndeterminedEntities.Count -gt 0) {
    Add-Warning "$($UndeterminedEntities.Count) entites ENV-08 ne sont pas suffisamment demontrees."
}

if ($UndeterminedRelations.Count -gt 0) {
    Add-Warning "$($UndeterminedRelations.Count) relations ENV-08 ne sont pas demontrees."
}

if ($NamingFindings.Count -gt 0) {
    Add-Warning "$($NamingFindings.Count) familles presentent plusieurs variantes de nommage."
}

if ($LocalStorageKeys.Count -gt 0) {
    Add-Warning "$($UniqueLocalStorageKeys.Count) cles localStorage/sessionStorage ont ete detectees."
}

if ($ConstraintEvidence.Count -eq 0) {
    Add-Warning "Aucune contrainte explicite suffisamment identifiable n'a ete detectee par les motifs generiques."
}

if ($EntityValidation.Count -gt 0) {
    Add-Result `
        -Category "MODEL" `
        -Item "Entity validation" `
        -Status "PASS" `
        -Evidence "$($ConfirmedEntities.Count) confirmees; $($ProbableEntities.Count) fortement probables; $($HypothesisEntities.Count) hypotheses; $($UndeterminedEntities.Count) non determinables"
}

Add-Result `
    -Category "MODEL" `
    -Item "Relation validation" `
    -Status "PASS" `
    -Evidence "$($ConfirmedRelations.Count) confirmees; $($ProbableRelations.Count) probables; $($HypothesisRelations.Count) hypotheses; $($UndeterminedRelations.Count) non determinees"

Add-Result `
    -Category "STATE" `
    -Item "Client-side storage" `
    -Status $(if ($LocalStorageKeys.Count -eq 0) { "PASS" } else { "WARNING" }) `
    -Evidence "$($UniqueLocalStorageKeys.Count) cles distinctes detectees"

Add-Result `
    -Category "NAMING" `
    -Item "Naming consistency" `
    -Status $(if ($NamingFindings.Count -eq 0) { "PASS" } else { "WARNING" }) `
    -Evidence "$($NamingFindings.Count) familles potentiellement incoherentes"

# ============================================================
# 21. RAPPORT
# ============================================================

$EndTime = Get-Date
$Duration = $EndTime - $StartTime

$Lines = New-Object System.Collections.Generic.List[string]

$Lines.Add("# ENV-09 — FORENSIC DATA MODEL VALIDATION & CONSISTENCY AUDIT")
$Lines.Add("")
$Lines.Add("## 1. Resultat")
$Lines.Add("")
$Lines.Add("**$GlobalStatus**")
$Lines.Add("")
$Lines.Add("Date : $($StartTime.ToString("yyyy-MM-dd HH:mm:ss"))")
$Lines.Add("Projet : `$ProjectRoot`")
$Lines.Add("")
$Lines.Add("Cette intervention est strictement READ-ONLY.")
$Lines.Add("")
$Lines.Add("---")
$Lines.Add("")

$Lines.Add("## 2. Perimetre")
$Lines.Add("")
$Lines.Add("ENV-09 verifie le modele ENV-08 contre les sources applicatives reellement presentes.")
$Lines.Add("")
$Lines.Add("Aucune creation ou modification PostgreSQL n'a ete effectuee.")
$Lines.Add("Aucune modification du code applicatif n'a ete effectuee.")
$Lines.Add("")

$Lines.Add("## 3. Inventaire")
$Lines.Add("")
$Lines.Add("Type - Nombre")
$Lines.Add("--- - ---:")
$Lines.Add("PHP - $PhpCount")
$Lines.Add("JavaScript - $JsCount")
$Lines.Add("HTML/HTM - $HtmlCount")
$Lines.Add("JSON - $JsonCount")
$Lines.Add("Markdown - $MdCount")
$Lines.Add("TXT - $TxtCount")
$Lines.Add("Total - $($Files.Count)")
$Lines.Add("")

$Lines.Add("## 4. Classification du modele")
$Lines.Add("")
$Lines.Add("Entite - Preuves - Fichiers - Classification")
$Lines.Add("--- - ---: - ---: - ---")

foreach ($item in $EntityValidation | Sort-Object Entity) {

    $Lines.Add(
        "$(Escape-Markdown $item.Entity) - $($item.EvidenceHits) - $($item.Files) - $($item.Status)"
    )
}

$Lines.Add("")

$Lines.Add("### Interpretation")
$Lines.Add("")
$Lines.Add("- **CONFIRME** : usage repete et identifiable dans le code.")
$Lines.Add("- **FORTEMENT-PROBABLE** : plusieurs indices coherents.")
$Lines.Add("- **HYPOTHESE** : indice insuffisant pour considerer l'entite comme demontree.")
$Lines.Add("- **NON-DETERMINABLE** : aucune preuve exploitable trouvee.")
$Lines.Add("")

$Lines.Add("## 5. Relations")
$Lines.Add("")
$Lines.Add("Relation - Preuves - Fichiers - Classification")
$Lines.Add("--- - ---: - ---: - ---")

foreach ($item in $RelationValidation | Sort-Object Relation) {

    $Lines.Add(
        "$(Escape-Markdown $item.Relation) - $($item.EvidenceHits) - $($item.Files) - $($item.Status)"
    )
}

$Lines.Add("")

$Lines.Add("## 6. Foreign keys candidates detectees")
$Lines.Add("")

if ($UniqueForeignKeys.Count -eq 0) {

    $Lines.Add("Aucune reference de type `*_id` ou `*Id` detectee.")

}
else {

    foreach ($fk in $UniqueForeignKeys | Select-Object -First 100) {
        $Lines.Add("- $fk")
    }
}

$Lines.Add("")

$Lines.Add("## 7. Statuts / valeurs candidates")
$Lines.Add("")

if ($UniqueStatusValues.Count -eq 0) {

    $Lines.Add("Aucune valeur de statut explicitement identifiable.")

}
else {

    foreach ($value in $UniqueStatusValues | Select-Object -First 100) {
        $Lines.Add("- $value")
    }
}

$Lines.Add("")

$Lines.Add("## 8. Stockage client")
$Lines.Add("")

if ($UniqueLocalStorageKeys.Count -eq 0) {

    $Lines.Add("Aucune cle localStorage/sessionStorage detectee.")

}
else {

    $Lines.Add("Cles distinctes detectees :")
    $Lines.Add("")

    foreach ($key in $UniqueLocalStorageKeys) {
        $Lines.Add("- $key")
    }
}

$Lines.Add("")

$Lines.Add("## 9. Regles metier detectees")
$Lines.Add("")

foreach ($rule in $BusinessRuleEvidence.Keys | Sort-Object) {

    $hits = @($BusinessRuleEvidence[$rule])

    $Lines.Add(
        "- **$rule** : $($hits.Count) occurrence(s)"
    )
}

$Lines.Add("")

$Lines.Add("## 10. Contraintes detectees")
$Lines.Add("")

$Lines.Add("Occurrences de validation/contrainte detectees : $($ConstraintEvidence.Count)")
$Lines.Add("")

foreach ($item in $ConstraintEvidence | Select-Object -First 30) {

    $Lines.Add(
        "- $($item.Pattern) — $($item.File):$($item.Line)"
    )
}

$Lines.Add("")

$Lines.Add("## 11. Incoherences potentielles de nommage")
$Lines.Add("")

if ($NamingFindings.Count -eq 0) {

    $Lines.Add("Aucune incoherence de famille de nommage detectee.")

}
else {

    foreach ($item in $NamingFindings) {

        $Lines.Add(
            "- **$($item.Family)** : $($item.Variants)"
        )
    }
}

$Lines.Add("")

$Lines.Add("## 12. Donnees sensibles")
$Lines.Add("")
$Lines.Add("Des champs correspondant a des donnees personnelles ou d'authentification sont presents dans le code.")
$Lines.Add("")
$Lines.Add("Occurrences analysees : $($SensitiveEvidence.Count)")
$Lines.Add("")
$Lines.Add("Cela ne constitue pas a lui seul une vulnerabilite ; ces champs devront cependant etre integres aux decisions de securite du schema final.")
$Lines.Add("")

$Lines.Add("## 13. Decisions encore ouvertes")
$Lines.Add("")

foreach ($decision in $OpenDecisions) {

    $Lines.Add("- [ ] $decision")
}

$Lines.Add("")

$Lines.Add("## 14. Conclusion forensic")
$Lines.Add("")
$Lines.Add("ENV-09 ne transforme pas automatiquement les hypotheses en decisions de conception.")
$Lines.Add("")
$Lines.Add("Les elements non demontres par le code restent explicitement ouverts.")
$Lines.Add("")
$Lines.Add("Le passage a ENV-10 devra produire le modele de donnees V1 final, avec pour chaque entite :")
$Lines.Add("")
$Lines.Add("1. nom definitif ;")
$Lines.Add("2. description ;")
$Lines.Add("3. champs ;")
$Lines.Add("4. type logique ;")
$Lines.Add("5. obligatoire/facultatif ;")
$Lines.Add("6. cle primaire ;")
$Lines.Add("7. cles etrangeres ;")
$Lines.Add("8. cardinalite ;")
$Lines.Add("9. unicite ;")
$Lines.Add("10. regles metier ;")
$Lines.Add("11. regles de suppression ;")
$Lines.Add("12. niveau de confiance forensic.")
$Lines.Add("")

$Lines.Add("## 15. Interdiction de creation prematuree")
$Lines.Add("")
$Lines.Add("**Aucune creation de `imc_clarodoro` ne doit etre effectuee sur la seule base de ENV-09.**")
$Lines.Add("")
$Lines.Add("Le premier schema PostgreSQL doit etre produit uniquement apres ENV-10.")
$Lines.Add("")

$Lines.Add("## 16. Prochaine etape")
$Lines.Add("")
$Lines.Add("**ENV-10 — MODELE DE DONNEES V1 FINAL ET VALIDE**")
$Lines.Add("")
$Lines.Add("ENV-10 consolidera les resultats ENV-07/08/09 en modele V1 definitif avant generation de `database/schema.sql`.")
$Lines.Add("")

$Lines.Add("## 17. Execution")
$Lines.Add("")
$Lines.Add("- Debut : $($StartTime.ToString("yyyy-MM-dd HH:mm:ss"))")
$Lines.Add("- Fin : $($EndTime.ToString("yyyy-MM-dd HH:mm:ss"))")
$Lines.Add("- Duree : $($Duration.ToString())")
$Lines.Add("- Fichiers analyses : $($Files.Count)")
$Lines.Add("- Entites : $($ModelEntities.Count)")
$Lines.Add("- Relations : $($RelationCandidates.Count)")
$Lines.Add("")

# ============================================================
# 22. ECRITURE DU RAPPORT
# ============================================================

$ReportText = $Lines -join "`r`n"

Set-Content `
    -LiteralPath $ReportPath `
    -Value $ReportText `
    -Encoding UTF8

Set-Content `
    -LiteralPath $FinalReportPath `
    -Value $ReportText `
    -Encoding UTF8

# ============================================================
# 23. SORTIE CONSOLE
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host " ENV-09 — FORENSIC DATA MODEL VALIDATION"
Write-Host "============================================================"
Write-Host ""
Write-Host "RESULTAT : $GlobalStatus"
Write-Host ""
Write-Host "Fichiers analyses      : $($Files.Count)"
Write-Host "Entites confirmees     : $($ConfirmedEntities.Count)"
Write-Host "Entites probables      : $($ProbableEntities.Count)"
Write-Host "Entites hypotheses     : $($HypothesisEntities.Count)"
Write-Host "Entites non determinees: $($UndeterminedEntities.Count)"
Write-Host ""
Write-Host "Relations confirmees   : $($ConfirmedRelations.Count)"
Write-Host "Relations probables    : $($ProbableRelations.Count)"
Write-Host "Relations hypotheses   : $($HypothesisRelations.Count)"
Write-Host "Relations non determinees : $($UndeterminedRelations.Count)"
Write-Host ""
Write-Host "Cles storage detectees : $($UniqueLocalStorageKeys.Count)"
Write-Host "Variantes nommage      : $($NamingFindings.Count)"
Write-Host ""
Write-Host "Rapport :"
Write-Host $ReportPath
Write-Host ""
Write-Host "Rapport final :"
Write-Host $FinalReportPath
Write-Host ""
Write-Host "============================================================"
Write-Host " FIN ENV-09"
Write-Host "============================================================"
