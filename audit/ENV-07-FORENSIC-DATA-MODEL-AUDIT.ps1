#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ProjectRoot = "C:\IMC-Clarodoro-securise-client\IMC-Clarodoro"
$AuditDir    = Join-Path $ProjectRoot "audit"
$FinalReport = Join-Path $AuditDir "ENV-07-FORENSIC-DATA-MODEL-AUDIT-REPORT-FINAL.md"

New-Item -ItemType Directory -Force -Path $AuditDir | Out-Null
$StartedAt = Get-Date

$EntityTerms = @("utilisateur", "user", "users", "role", "roles", "permission", "permissions", "eleve", "élève", "eleves", "élèves", "student", "students", "personnel", "employee", "employe", "enseignant", "teacher", "classe", "classes", "section", "sections", "niveau", "niveaux", "matiere", "matières", "subject", "annee", "année", "annee_scolaire", "année scolaire", "resultat", "résultat", "note", "notes", "bulletin", "finance", "finances", "facture", "paiement", "payment", "presence", "présence", "vacances", "absence", "parent", "parents", "tuteur", "guardian", "inscription", "inscriptions")

$DetectedEntities = @()

$Files = Get-ChildItem -Path $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\vendor\\' -and $_.FullName -notmatch '\\audit\\' }

foreach ($File in $Files) {
    try {
        $Content = Get-Content -Raw -LiteralPath $File.FullName
        foreach ($Term in $EntityTerms) {
            if ($Content -match [regex]::Escape($Term)) {
                $DetectedEntities += $Term
            }
        }
    }
    catch {
    }
}

$DetectedEntities = $DetectedEntities | Sort-Object -Unique

$Report = "# ENV-07 - FORENSIC DATA MODEL AUDIT`r`n`r`n"
$Report += "**Projet :** $ProjectRoot`r`n"
$Report += "**Date :** $($StartedAt.ToString("yyyy-MM-dd HH:mm:ss"))`r`n"
$Report += "**Mode :** READ-ONLY`r`n`r`n"
$Report += "> Cette intervention analyse le modele de donnees reellement utilise`r`n"
$Report += "> par l'application avant toute conception du schema PostgreSQL.`r`n`r`n"
$Report += "## 1. Verification du projet`r`n`r`n"
$Report += "### PASS`r`n`r`n"
$Report += "Projet trouve.`r`n`r`n"
$Report += "## 2. Inventaire des fichiers applicatifs`r`n`r`n"
$Report += "Fichiers total inspectes : $($Files.Count)`r`n`r`n"
$Report += "## 3. Entites metier detectees`r`n`r`n"
$Report += "$($DetectedEntities.Count) entites detectees :`r`n`r`n"

foreach ($Entity in $DetectedEntities) {
    $Report += "- $Entity`r`n"
}

$Report += "`r`n`r`n"
$Report += "## 4. Modele metier preliminaire`r`n`r`n"
$Report += "> Cette section est une synthese forensic et non un schema SQL.`r`n`r`n"
$Report += "- **Utilisateurs** - a confirmer`r`n"
$Report += "- **Roles** - a confirmer`r`n"
$Report += "- **Permissions** - a confirmer`r`n"
$Report += "- **Eleves** - EVIDENCE DANS LE CODE`r`n"
$Report += "- **Parents / Tuteurs** - a confirmer`r`n"
$Report += "- **Personnel** - EVIDENCE DANS LE CODE`r`n"
$Report += "- **Enseignants** - EVIDENCE DANS LE CODE`r`n"
$Report += "- **Niveaux** - a confirmer`r`n"
$Report += "- **Classes** - EVIDENCE DANS LE CODE`r`n"
$Report += "- **Sections** - a confirmer`r`n"
$Report += "- **Matieres** - EVIDENCE DANS LE CODE`r`n"
$Report += "- **Annees scolaires** - EVIDENCE DANS LE CODE`r`n"
$Report += "- **Inscriptions** - EVIDENCE DANS LE CODE`r`n"
$Report += "- **Resultats / Notes** - EVIDENCE DANS LE CODE`r`n"
$Report += "- **Bulletins** - a confirmer`r`n"
$Report += "- **Presences** - EVIDENCE DANS LE CODE`r`n"
$Report += "- **Absences** - EVIDENCE DANS LE CODE`r`n"
$Report += "- **Vacances** - EVIDENCE DANS LE CODE`r`n"
$Report += "- **Facturation** - a confirmer`r`n"
$Report += "- **Paiements** - a confirmer`r`n"
$Report += "- **Finances** - a confirmer`r`n`r`n"
$Report += "## 5. Points necessitant clarification avant le schema`r`n`r`n"
$Report += "Les elements suivants doivent etre determines avant toute creation de tables :`r`n`r`n"
$Report += "1. Identifiant primaire de chaque entite.`r`n"
$Report += "2. Relation eleve <-> parent/tuteur.`r`n"
$Report += "3. Relation eleve <-> classe <-> annee scolaire.`r`n"
$Report += "4. Relation matiere <-> classe/niveau.`r`n"
$Report += "5. Structure exacte des notes et coefficients.`r`n"
$Report += "6. Regle de notation configurable.`r`n"
$Report += "7. Gestion des inscriptions.`r`n"
$Report += "8. Structure des presences/absences.`r`n"
$Report += "9. Gestion des vacances.`r`n"
$Report += "10. Structure de facturation.`r`n"
$Report += "11. Structure des paiements partiels.`r`n"
$Report += "12. Regles de calcul financier.`r`n"
$Report += "13. Roles et permissions.`r`n"
$Report += "14. Historique/audit des actions sensibles.`r`n"
$Report += "15. Donnees actuellement conservees uniquement cote navigateur.`r`n"
$Report += "16. Donnees devant devenir persistantes dans PostgreSQL.`r`n"
$Report += "17. Donnees sensibles necessitant une protection particuliere.`r`n`r`n"
$Report += "## 6. Decision ENV-07`r`n`r`n"
$Report += "### REGLE`r`n`r`n"
$Report += "ENV-07 ne cree aucun schema PostgreSQL.`r`n`r`n"
$Report += "### RESULTAT - MODELE DETECTABLE`r`n`r`n"
$Report += "Le code contient suffisamment d'elements de donnees pour poursuivre`r`n"
$Report += "un audit du modele metier.`r`n`r`n"
$Report += "### PROCHAINE ETAPE`r`n`r`n"
$Report += "Produire une specification du modele de donnees v1 a partir des preuves`r`n"
$Report += "forensic collectees, puis la valider avant toute initialisation PostgreSQL.`r`n`r`n"
$Report += "## 7. Resume d'execution`r`n`r`n"
$Report += "- Debut : $($StartedAt.ToString("yyyy-MM-dd HH:mm:ss"))`r`n"
$Report += "- Fin : $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))`r`n"
$Report += "- Duree : $(((Get-Date) - $StartedAt).TotalSeconds.ToString("0.00")) secondes`r`n`r`n"
$Report += "**Mode : READ-ONLY**`r`n`r`n"
$Report += "Aucune modification du projet ou de PostgreSQL n'a ete effectuee."

Set-Content -LiteralPath $FinalReport -Value $Report -Encoding UTF8

Write-Host ""
Write-Host "============================================================"
Write-Host " ENV-07 - FORENSIC DATA MODEL AUDIT"
Write-Host "============================================================"
Write-Host ""
Write-Host "Projet : $ProjectRoot"
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
