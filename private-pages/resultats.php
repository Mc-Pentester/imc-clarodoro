<?php
require_once __DIR__ . '/../config/page_auth.php';
imcRequirePageAccess('resultats.read', null, $pdo ?? null);
?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<title>Résultats - IMC Clarodaro</title>

<style>

* {
    box-sizing: border-box;
}

html,
body {
    margin: 0;
    padding: 0;
}

body {
    font-family: "Times New Roman", Times, serif;
    font-size: 12pt;
    background: #f4f6f8;
    color: #111;
}

/* =========================================================
   MENU
========================================================= */

.menu-principal {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    padding: 12px;
    background: #ffffff;
    border-bottom: 1px solid #ccc;
}

.menu-principal button {
    font-family: "Times New Roman", Times, serif;
    font-size: 12pt;
    font-weight: bold;
    border: 1px solid #999;
    border-radius: 7px;
    padding: 8px 14px;
    cursor: pointer;
    background: #eee;
}

.menu-principal button:hover {
    opacity: 0.85;
}

.menu-principal button.active {
    color: white;
    background: #1976d2;
}

/* =========================================================
   ZONE DE CONTROLE
========================================================= */

.commandes {
    width: 98%;
    max-width: 1500px;
    margin: 15px auto;
    background: white;
    border: 1px solid #ccc;
    border-radius: 8px;
    padding: 12px;
}

.commandes-ligne {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 10px;
}

.commandes label {
    font-weight: bold;
}

.commandes select,
.commandes input {
    font-family: "Times New Roman", Times, serif;
    font-size: 12pt;
    padding: 6px;
    border: 1px solid #999;
    border-radius: 5px;
}

#recherche {
    min-width: 220px;
}
.saisie-notes { width:98%; max-width:1500px; margin:16px auto; padding:18px; background:#fff; border:1px solid #d7dee8; border-radius:12px; box-shadow:0 3px 12px rgba(20,40,70,.05); }
.saisie-notes h2 { margin:0 0 6px; color:#17365d; }
.saisie-aide { margin:0 0 16px; color:#526174; }
.saisie-filtres { display:grid; grid-template-columns:repeat(3,minmax(160px,1fr)); gap:12px; margin-bottom:16px; }
.saisie-filtres label { display:grid; gap:6px; font-weight:bold; }
.saisie-filtres select,.saisie-filtres input { width:100%; min-height:42px; padding:8px 10px; border:1px solid #b8c4d3; border-radius:7px; background:#fff; font:inherit; }
.saisie-filtres input[readonly] { background:#f6f8fb; }
.saisie-table-wrap { overflow-x:auto; border:1px solid #e0e6ee; border-radius:8px; }
#tableSaisie { width:100%; border-collapse:collapse; min-width:460px; }
#tableSaisie th,#tableSaisie td { padding:10px 12px; border-bottom:1px solid #e7ecf2; text-align:left; }
#tableSaisie th { background:#f2f6fb; color:#26384d; }
#tableSaisie tbody tr:last-child td { border-bottom:0; }
.note-saisie-input { width:110px; max-width:100%; min-height:40px; padding:7px 9px; border:1px solid #aebdce; border-radius:7px; font:inherit; text-align:center; }
.note-saisie-input:focus { outline:2px solid #9bc5f4; border-color:#2876c7; }
.saisie-actions { display:flex; flex-wrap:wrap; align-items:center; gap:12px; margin-top:14px; }
.btn-saisie { min-height:42px; padding:9px 18px; border:0; border-radius:8px; background:#167447; color:#fff; font:inherit; font-weight:bold; cursor:pointer; }
.btn-saisie:disabled { opacity:.55; cursor:not-allowed; }
#saisieProgression { color:#526174; }
.saisie-vide { padding:20px!important; text-align:center!important; color:#66758a; }
@media(max-width:700px) { .saisie-filtres { grid-template-columns:1fr; } .saisie-notes { padding:13px; } #tableSaisie th,#tableSaisie td { padding:8px; } .note-saisie-input { width:88px; } }

/* =========================================================
   LISTE DES ÉLÈVES
========================================================= */

.liste-eleves {
    width: 98%;
    max-width: 1500px;
    margin: 10px auto;
    background: white;
    border: 1px solid #ccc;
    border-radius: 8px;
    padding: 10px;
}

.liste-eleves h3 {
    margin-top: 0;
}

.eleves-container {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
}

.eleve-bouton {
    font-family: "Times New Roman", Times, serif;
    font-size: 12pt;
    background: #e8f1ff;
    border: 1px solid #4682b4;
    border-radius: 6px;
    padding: 7px 12px;
    cursor: pointer;
}

.eleve-bouton:hover {
    background: #d0e5ff;
}

.eleve-bouton.selectionne {
    background: #1976d2;
    color: white;
}

/* =========================================================
   CARNET
========================================================= */

#zoneCarnet {
    display: none;
    width: 98%;
    max-width: 1500px;
    margin: 15px auto 30px;
    background: white;
    padding: 12px;
}

.informations-eleve {
    display: grid;
    grid-template-columns: 1.5fr 1fr 1fr;
    gap: 15px;
    margin-bottom: 8px;
    font-weight: bold;
}

.info-ligne {
    border-bottom: 1px solid #555;
    min-height: 24px;
    padding: 3px;
}

/* =========================================================
   TABLEAU PRINCIPAL
========================================================= */

.table-carnet {
    width: 100%;
    border-collapse: collapse;
    table-layout: fixed;
}

.table-carnet th,
.table-carnet td {
    border: 1px solid #222;
    padding: 2px;
    text-align: center;
    vertical-align: middle;
    font-family: "Times New Roman", Times, serif;
    font-size: 12pt;
}

.table-carnet th {
    font-weight: bold;
}

/* Première colonne */

.colonne-ligne {
    width: 105px;
    text-align: left !important;
    padding-left: 5px !important;
}

/* Colonnes matières */

.colonne-matiere {
    width: 43px;
}

/* Total / moyenne / place */

.colonne-resultat {
    width: 50px;
}

/* Signature */

.colonne-signature {
    width: 125px;
}

/* =========================================================
   EN-TÊTE VERTICAL
========================================================= */

.entete-vertical {
    height: 245px;
    padding: 3px !important;
    vertical-align: bottom !important;
}

.mots-verticaux {
    display: flex;
    flex-direction: row;
    justify-content: center;
    align-items: flex-end;
    gap: 3px;
    height: 100%;
}

.mot-vertical {
    writing-mode: vertical-rl;
    transform: rotate(180deg);
    white-space: nowrap;
    display: inline-flex;
    align-items: center;
    justify-content: flex-start;
    height: 225px;
    font-weight: bold;
}

/* Matières / Total / Moyenne / Place */

.entete-simple-vertical {
    height: 245px;
    writing-mode: vertical-rl;
    transform: rotate(180deg);
    white-space: nowrap;
    vertical-align: bottom !important;
    text-align: center !important;
}

/* Signatures restent horizontales */

.entete-signature {
    height: 245px;
    white-space: normal;
    writing-mode: horizontal-tb;
    transform: none;
    text-align: center;
    vertical-align: middle !important;
}

/* =========================================================
   CELLULES DE NOTES
========================================================= */

.note-input {
    width: 100%;
    min-width: 0;
    border: 0;
    outline: none;
    background: transparent;
    text-align: center;
    font-family: "Times New Roman", Times, serif;
    font-size: 12pt;
    padding: 3px 0;
}

.note-input:focus {
    background: #fff7c7;
}

.note-erreur {
    background: #ffcccc !important;
}

.cellule-calcul {
    font-weight: bold;
}

/* =========================================================
   SIGNATURES
========================================================= */

.signature {
    height: 34px;
    text-align: center;
    vertical-align: bottom !important;
    font-size: 12pt;
}

.trait-signature {
    display: block;
    margin: 18px auto 2px;
    width: 90%;
    border-bottom: 1px solid #111;
    height: 1px;
}

/* Pas de trait sur les autres lignes */

.signature-vide {
    height: 34px;
}

/* =========================================================
   MESSAGE
========================================================= */

.message {
    margin: 10px 0;
    padding: 8px;
    border-radius: 5px;
    font-weight: bold;
    display: none;
}

.message.erreur {
    display: block;
    background: #ffd8d8;
    color: #9b0000;
}

.message.succes {
    display: block;
    background: #d8f5d8;
    color: #087208;
}

/* =========================================================
   BOUTONS
========================================================= */

.actions-carnet {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 12px;
}

.actions-carnet button {
    font-family: "Times New Roman", Times, serif;
    font-size: 12pt;
    font-weight: bold;
    padding: 8px 14px;
    border: 1px solid #555;
    border-radius: 6px;
    cursor: pointer;
}

.btn-enregistrer {
    background: #198754;
    color: white;
}

.btn-imprimer {
    background: #0d6efd;
    color: white;
}

.btn-fermer {
    background: #6c757d;
    color: white;
}

/* =========================================================
   DEUXIÈME PARTIE DU CARNET
========================================================= */

.deuxieme-partie {
    display: grid;
    grid-template-columns: 1.15fr 1fr 1fr;
    gap: 12px;
    margin-top: 18px;
}

.bloc-carnet {
    border: 1px solid #222;
}

.bloc-titre {
    text-align: center;
    font-weight: bold;
    border-bottom: 1px solid #222;
    padding: 4px;
}

.table-hygiene {
    width: 100%;
    border-collapse: collapse;
    table-layout: fixed;
}

.table-hygiene td,
.table-hygiene th {
    border: 1px solid #222;
    height: 28px;
    padding: 2px;
    font-family: "Times New Roman", Times, serif;
    font-size: 12pt;
}

.table-hygiene .libelle {
    width: 120px;
}

.table-hygiene input,
.observation-input {
    width: 100%;
    border: 0;
    outline: none;
    font-family: "Times New Roman", Times, serif;
    font-size: 12pt;
    background: transparent;
}

/* Décision */

.decision {
    min-height: 165px;
    padding: 12px;
}

.decision-ligne {
    margin: 16px 0;
    line-height: 1.4;
}

.ligne-remplissage {
    display: inline-block;
    min-width: 120px;
    border-bottom: 1px solid #111;
    height: 18px;
    vertical-align: bottom;
}

/* Observation */

.observation {
    min-height: 165px;
    padding: 10px;
}

.observation-ligne {
    margin: 13px 0;
    display: flex;
    align-items: flex-end;
    gap: 5px;
}

.observation-ligne span {
    white-space: nowrap;
}

.observation-input {
    border-bottom: 1px solid #111;
    padding: 2px;
}

/* =========================================================
   IMPRESSION
========================================================= */

@media print {

    @page {
        size: A4 landscape;
        margin: 7mm;
    }

    body {
        background: white;
        font-family: "Times New Roman", Times, serif;
        font-size: 12pt;
    }

    .no-print,
    .commandes,
    .liste-eleves,
    .actions-carnet,
    .message {
        display: none !important;
    }

    #zoneCarnet {
        display: block !important;
        width: 100%;
        margin: 0;
        padding: 0;
    }

    .table-carnet {
        width: 100%;
    }

    .deuxieme-partie {
        display: grid;
        page-break-inside: avoid;
    }

    .table-carnet th,
    .table-carnet td,
    .table-hygiene td,
    .table-hygiene th {
        font-size: 12pt;
    }

    .note-input {
        font-size: 12pt;
    }

    input {
        color: black;
    }
}

/* =========================================================
   PETITS ÉCRANS
========================================================= */

@media screen and (max-width: 900px) {

    .informations-eleve {
        grid-template-columns: 1fr;
    }

    .deuxieme-partie {
        grid-template-columns: 1fr;
    }

    .table-carnet {
        font-size: 10pt;
    }

    .table-carnet th,
    .table-carnet td {
        font-size: 10pt;
    }
}

</style>
</head>

<body>

<!-- =======================================================
     MENU
======================================================= -->

<nav class="menu-principal no-print">

    <button type="button"
            onclick="ouvrirPage('index.html')">
        Élèves
    </button>

    <button type="button"
            onclick="ouvrirPage('matieres.html')">
        Matières
    </button>

    <button type="button"
            class="active"
            onclick="ouvrirPage('resultats.html')">
        Résultats
    </button>

    <button type="button"
            onclick="ouvrirPage('finances.html')">
        Finances
    </button>

    <button type="button"
            onclick="ouvrirPage('personnel.html')">
        Personnel
    </button>

    <button type="button"
            onclick="ouvrirPage('annees-scolaires.html')">
        Année scolaire
    </button>

    <button type="button"
            onclick="ouvrirPage('vacances.html')">
        Vacances
    </button>

    <button type="button"
            onclick="ouvrirPage('pdg.html')">
        PDG
    </button>

</nav>


<!-- =======================================================
     COMMANDES
======================================================= -->

<section class="commandes no-print">

    <div class="commandes-ligne">

        <label for="annee">
            Année :
        </label>

        <select id="annee"></select>


        <label for="classe">
            Classe :
        </label>

        <select id="classe">
            <option value="">Toutes les classes</option>
        </select>


        <label for="recherche">
            Rechercher :
        </label>

        <input
            type="text"
            id="recherche"
            placeholder="Nom ou prénom..."
        >

    </div>

</section>

<section class="saisie-notes no-print" aria-labelledby="titreSaisieNotes">
    <h2 id="titreSaisieNotes">Saisir les notes des élèves</h2>
    <p class="saisie-aide">Choisissez une classe, une matière et un contrôle. La liste des élèves et les notes déjà enregistrées s'affichent automatiquement.</p>
    <div class="saisie-filtres">
        <label for="saisieMatiere">Matière
            <select id="saisieMatiere"><option value="">Choisir une matière</option></select>
        </label>
        <label for="saisieControle">Évaluation
            <select id="saisieControle"><option value="1">1er contrôle</option><option value="2">2e contrôle</option><option value="3">3e contrôle</option></select>
        </label>
        <label for="saisieBareme">Barème de la matière
            <input id="saisieBareme" type="text" readonly value="Sélectionnez une matière">
        </label>
    </div>
    <div class="saisie-table-wrap">
        <table id="tableSaisie">
            <thead><tr><th style="width:52px">N°</th><th>Élève</th><th style="width:180px">Note obtenue</th><th style="width:150px">État</th></tr></thead>
            <tbody id="corpsSaisie"><tr><td colspan="4" class="saisie-vide">Choisissez d'abord une classe et une matière.</td></tr></tbody>
        </table>
    </div>
    <div class="saisie-actions">
        <button type="button" id="btnEnregistrerSaisie" class="btn-saisie" onclick="enregistrerSaisieClasse()" disabled>Enregistrer les notes</button>
        <span id="saisieProgression" aria-live="polite">Sélectionnez une classe et une matière pour commencer.</span>
    </div>
</section>

<!-- =======================================================
     LISTE DES ÉLÈVES / CARNET INDIVIDUEL
======================================================= -->

<section class="liste-eleves no-print">

    <h3>
        Élèves
    </h3>

    <div
        id="listeEleves"
        class="eleves-container">
    </div>

</section>


<!-- =======================================================
     MESSAGE
======================================================= -->

<div
    id="message"
    class="message">
</div>


<!-- =======================================================
     CARNET
======================================================= -->

<section id="zoneCarnet">

    <!-- IDENTITÉ -->

    <div class="informations-eleve">

        <div class="info-ligne">
            Nom et Prénom :
            <span id="nomPrenom"></span>
        </div>

        <div class="info-ligne">
            Classe :
            <span id="classeEleve"></span>
        </div>

        <div class="info-ligne">
            Année :
            <span id="anneeEleve"></span>
        </div>

    </div>


    <!-- ===================================================
         TABLEAU PRINCIPAL
    =================================================== -->

    <table
        id="tableCarnet"
        class="table-carnet">

        <thead>

            <tr>

                <!-- Matières -->

                <th class="colonne-ligne entete-simple-vertical">
                    Matières
                </th>

                <!-- Les matières seront ajoutées ici -->

                <!-- Total -->

                <th class="colonne-resultat entete-simple-vertical">
                    TOTAL
                </th>

                <!-- Moyenne -->

                <th class="colonne-resultat entete-simple-vertical">
                    MOYENNE
                </th>

                <!-- Place -->

                <th class="colonne-resultat entete-simple-vertical">
                    PLACE
                </th>

                <!-- Signature Directeur -->

                <th class="colonne-signature entete-signature">
                    Signature du Directeur
                </th>

                <!-- Signature parents -->

                <th class="colonne-signature entete-signature">
                    Signature des parents
                </th>

            </tr>

        </thead>


        <tbody id="corpsCarnet">

            <!-- Généré par JavaScript -->

        </tbody>

    </table>


    <!-- ===================================================
         DEUXIÈME PARTIE
    =================================================== -->

    <div class="deuxieme-partie">

        <!-- ===============================================
             HYGIÈNE + RÉGULARITÉ
        ================================================ -->

        <div class="bloc-carnet">

            <div class="bloc-titre">
                Hygiène
            </div>

            <table class="table-hygiene">

                <tr>

                    <td class="libelle">
                        Propreté
                    </td>

                    <td colspan="5">
                        <input
                            type="text"
                            id="proprete">
                    </td>

                </tr>


                <tr>

                    <td class="libelle">
                        Conduite
                    </td>

                    <td colspan="5">
                        <input
                            type="text"
                            id="conduite">
                    </td>

                </tr>


                <tr>

                    <td class="libelle">
                        Tenue de<br>
                        matériels
                    </td>

                    <td colspan="5">
                        <input
                            type="text"
                            id="tenueMateriels">
                    </td>

                </tr>

            </table>


            <div class="bloc-titre">
                Régularité
            </div>

            <table class="table-hygiene">

                <tr>

                    <td class="libelle">
                        Retard
                    </td>

                    <td colspan="5">
                        <input
                            type="text"
                            id="retard">
                    </td>

                </tr>


                <tr>

                    <td class="libelle">
                        Absence
                    </td>

                    <td colspan="5">
                        <input
                            type="text"
                            id="absence">
                    </td>

                </tr>

            </table>

        </div>


        <!-- ===============================================
             DÉCISION DE FIN D'ANNÉE
        ================================================ -->

        <div class="bloc-carnet">

            <div class="bloc-titre">
                Décision de fin d’année
            </div>

            <div class="decision">

                <div class="decision-ligne">

                    L’élève est promu(e) en classe de

                    <span
                        id="classePromotion"
                        class="ligne-remplissage">
                    </span>

                </div>


                <div class="decision-ligne">

                    L’élève refait la classe de

                    <span
                        id="classeRefait"
                        class="ligne-remplissage">
                    </span>

                </div>


                <div class="decision-ligne">

                    L’élève est remis(e)

                    <span
                        id="eleveRemis"
                        class="ligne-remplissage">
                    </span>

                </div>

            </div>

        </div>


        <!-- ===============================================
             OBSERVATION
        ================================================ -->

        <div class="bloc-carnet">

            <div class="bloc-titre">
                Observation :
            </div>

            <div class="observation">

                <div class="observation-ligne">

                    <span>
                        1er Contrôle :
                    </span>

                    <input
                        class="observation-input"
                        type="text"
                        id="observation1">

                </div>


                <div class="observation-ligne">

                    <span>
                        2ème Contrôle :
                    </span>

                    <input
                        class="observation-input"
                        type="text"
                        id="observation2">

                </div>


                <div class="observation-ligne">

                    <span>
                        3ème Contrôle :
                    </span>

                    <input
                        class="observation-input"
                        type="text"
                        id="observation3">

                </div>

            </div>

        </div>

    </div>


    <!-- ACTIONS -->

    <div class="actions-carnet no-print">

        <button
            type="button"
            class="btn-enregistrer"
            onclick="enregistrerResultats()">

            Enregistrer

        </button>


        <button
            type="button"
            class="btn-imprimer"
            onclick="window.print()">

            Imprimer

        </button>


        <button
            type="button"
            class="btn-fermer"
            onclick="fermerCarnet()">

            Fermer le carnet

        </button>

    </div>

</section>


<script src="auth.js"></script>
<script>

/* =========================================================
   STOCKAGE
========================================================= */

let eleves = [];
let matieres = [];
let resultats = {};
let gradeMeta = {};
let carnetMeta = {};
let anneesServeur = [];
let anneeServeurId = "";
let eleveSelectionne = null;


/* =========================================================
   MOIS
========================================================= */

const lignes = [

    {
        type: "mois",
        nom: "Septembre"
    },

    {
        type: "mois",
        nom: "Octobre"
    },

    {
        type: "mois",
        nom: "Novembre"
    },

    {
        type: "controle",
        numero: 1,
        nom: "1er Contrôle"
    },

    {
        type: "mois",
        nom: "Janvier"
    },

    {
        type: "mois",
        nom: "Février"
    },

    {
        type: "controle",
        numero: 2,
        nom: "2ème Contrôle"
    },

    {
        type: "mois",
        nom: "Avril"
    },

    {
        type: "mois",
        nom: "Mai"
    },

    {
        type: "controle",
        numero: 3,
        nom: "3ème Contrôle"
    }

];


/* =========================================================
   CHARGEMENT
========================================================= */

async function chargerClasses() {
    const select = document.getElementById("classe");
    if (!select) return;
    const response = await fetch("/api/student-enrollment-options/index.php", {
        method: "GET",
        credentials: "same-origin",
        headers: { "Accept": "application/json" },
        cache: "no-store"
    });
    const payload = await response.json();
    if (!response.ok || !payload.success || !Array.isArray(payload.classes)) {
        throw new Error(payload.error || "Impossible de charger les classes depuis PostgreSQL.");
    }
    select.replaceChildren(new Option("Toutes les classes", ""));
    payload.classes.forEach(function (item) {
        if (!item || !item.id || !item.name) return;
        const option = new Option(String(item.name), String(item.id));
        option.dataset.classId = String(item.id);
        select.appendChild(option);
    });
}

async function chargerDonnees() {

    if (!anneeServeurId) {
        eleves = [];
        matieres = [];
        resultats = {};
        gradeMeta = {};
        carnetMeta = {};
        return;
    }

    const response = await fetch(
        "/api/grades/index.php?school_year_id=" +
        encodeURIComponent(anneeServeurId),
        { method: "GET", credentials: "same-origin", headers: { "Accept": "application/json" } }
    );

    const payload = await response.json();

    if (!response.ok || !payload.success) {
        throw new Error(payload.error || "Impossible de charger les résultats.");
    }

    if (!Array.isArray(payload.subjects) || payload.subjects.some(subject => !Number.isFinite(Number(subject.max_points)) || Number(subject.max_points) <= 0)) {
        throw new Error("Barème max_points absent ou invalide dans PostgreSQL. Aucun barème de remplacement ne sera appliqué.");
    }

    matieres = (payload.subjects || []).map(function(subject) {
        return {
            id: subject.id,
            nom: subject.name,
            code: subject.code,
            pointsMax: Number(subject.max_points),
            coefficient: subject.coefficient
        };
    });

    eleves = (payload.enrollments || []).map(function(enrollment) {
        return {
            id: enrollment.student_id,
            enrollmentId: enrollment.enrollment_id,
            classId: String(enrollment.class_id || ""),
            nom: enrollment.last_name,
            prenom: enrollment.first_name,
            classe: enrollment.class_name,
            sexe: "",
            schoolYearId: enrollment.school_year_id
        };
    });

    resultats = {};
    gradeMeta = {};

    (payload.grades || []).forEach(function(grade) {
        const studentId = String(grade.student_id);
        const yearLabel = String(
            (anneesServeur.find(function(y) {
                return String(y.id) === String(grade.school_year_id);
            }) || {}).label || document.getElementById("annee").value
        );
        const control = Number(grade.assessment_number || 1);

        if (!resultats[studentId]) resultats[studentId] = {};
        if (!resultats[studentId][yearLabel]) resultats[studentId][yearLabel] = {};
        if (!resultats[studentId][yearLabel]["controle" + control]) {
            resultats[studentId][yearLabel]["controle" + control] = {};
        }

        resultats[studentId][yearLabel]["controle" + control][String(grade.subject_id)] =
            Number(grade.grade);

        gradeMeta[
            studentId + "|" + String(grade.school_year_id) + "|" +
            control + "|" + String(grade.subject_id)
        ] = {
            id: String(grade.id),
            enrollmentId: String(grade.enrollment_id)
        };
    });

    remplirSelecteurMatieres();
    afficherSaisieClasse();
}


/* =========================================================
   ANNÉES SCOLAIRES
========================================================= */

async function chargerAnnees() {

    const select = document.getElementById("annee");
    select.innerHTML = "";

    const response = await fetch(
        "/api/school-years/index.php",
        { method: "GET", credentials: "same-origin", headers: { "Accept": "application/json" } }
    );
    const payload = await response.json();

    if (!response.ok || !payload.success) {
        throw new Error(payload.error || "Impossible de charger les années scolaires.");
    }

    anneesServeur = Array.isArray(payload.schoolYears) ? payload.schoolYears : [];

    anneesServeur.forEach(function(annee) {
        const option = document.createElement("option");
        option.value = annee.label;
        option.textContent = annee.label;
        option.dataset.yearId = annee.id;
        select.appendChild(option);
    });

    const active = anneesServeur.find(function(annee) {
        return annee.status === "ACTIVE";
    }) || anneesServeur[0];

    if (active) {
        select.value = active.label;
        anneeServeurId = String(active.id);
    }
}


/* =========================================================
   SAUVEGARDER ANNÉE
========================================================= */

document
    .getElementById("annee")
    .addEventListener("change", async function () {
        const option = this.options[this.selectedIndex];
        anneeServeurId = option ? String(option.dataset.yearId || "") : "";
        try {
            await chargerDonnees();
            afficherEleves();
            if (eleveSelectionne) afficherCarnet(eleveSelectionne);
        } catch (error) {
            afficherMessage(error.message, "erreur");
        }
    });


/* =========================================================
   CLASSE
========================================================= */

document.getElementById("classe").addEventListener("change", function () {
    afficherEleves();
    afficherSaisieClasse();
});
document.getElementById("saisieMatiere").addEventListener("change", afficherSaisieClasse);
document.getElementById("saisieControle").addEventListener("change", afficherSaisieClasse);


/* =========================================================
   RECHERCHE
========================================================= */

document
    .getElementById("recherche")
    .addEventListener(
        "input",
        afficherEleves
    );


/* =========================================================
   AFFICHER LES ÉLÈVES
========================================================= */

function afficherEleves() {

    const container =
        document.getElementById(
            "listeEleves"
        );

    container.innerHTML = "";

    const classeChoisie =
        document.getElementById(
            "classe"
        ).value;


    const recherche =
        document.getElementById(
            "recherche"
        ).value
        .trim()
        .toLowerCase();


    let liste =
        eleves.filter(function (eleve) {

            const classeOK =
                !classeChoisie ||
                String(eleve.classId) === String(classeChoisie);


            const texte =
                (
                    (eleve.nom || "") +
                    " " +
                    (eleve.prenom || "")
                ).toLowerCase();


            const rechercheOK =
                !recherche ||
                texte.includes(recherche);


            return classeOK && rechercheOK;

        });


    liste.sort(function (a, b) {

        const nomA =
            (
                (a.nom || "") +
                " " +
                (a.prenom || "")
            ).toLowerCase();

        const nomB =
            (
                (b.nom || "") +
                " " +
                (b.prenom || "")
            ).toLowerCase();

        return nomA.localeCompare(
            nomB,
            "fr"
        );

    });


    if (liste.length === 0) {

        container.innerHTML =
            "<p>Aucun élève trouvé.</p>";

        return;

    }


    liste.forEach(function (eleve) {

        const bouton =
            document.createElement("button");

        bouton.type = "button";

        bouton.className =
            "eleve-bouton";


        if (
            eleveSelectionne &&
            String(eleveSelectionne.id) ===
            String(eleve.id)
        ) {

            bouton.classList.add(
                "selectionne"
            );

        }


        bouton.textContent =
            `${eleve.nom || ""} ${eleve.prenom || ""}`;


        bouton.onclick = function () {

            eleveSelectionne = eleve;

            afficherEleves();

            afficherCarnet(eleve);

        };


        container.appendChild(bouton);

    });

}


/* =========================================================
   SAISIE RAPIDE DES NOTES PAR CLASSE
========================================================= */

function remplirSelecteurMatieres() {
    const select = document.getElementById("saisieMatiere");
    if (!select) return;
    const previous = select.value;
    select.replaceChildren(new Option("Choisir une matière", ""));
    matieres.forEach(function(matiere) {
        select.appendChild(new Option(matiere.nom + " — /" + formatNombre(matiere.pointsMax), String(matiere.id)));
    });
    if (matieres.some(m => String(m.id) === previous)) select.value = previous;
}

function afficherSaisieClasse() {
    const body = document.getElementById("corpsSaisie");
    const button = document.getElementById("btnEnregistrerSaisie");
    const progress = document.getElementById("saisieProgression");
    const classId = document.getElementById("classe").value;
    const subjectId = document.getElementById("saisieMatiere").value;
    const control = Number(document.getElementById("saisieControle").value || 1);
    const subject = matieres.find(m => String(m.id) === String(subjectId));
    document.getElementById("saisieBareme").value = subject ? "Note maximale : " + formatNombre(subject.pointsMax) + " points" : "Sélectionnez une matière";
    body.replaceChildren();

    if (!anneeServeurId) {
        body.innerHTML = '<tr><td colspan="4" class="saisie-vide">Aucune année scolaire sélectionnée.</td></tr>';
        button.disabled = true; progress.textContent = "Choisissez une année scolaire."; return;
    }
    if (!classId || !subject) {
        body.innerHTML = '<tr><td colspan="4" class="saisie-vide">Choisissez une classe et une matière pour afficher les élèves.</td></tr>';
        button.disabled = true; progress.textContent = "Sélectionnez une classe et une matière pour commencer."; return;
    }

    const uniqueEnrollments = new Map();
    eleves.filter(e => String(e.classId) === String(classId)).forEach(e => {
        uniqueEnrollments.set(String(e.enrollmentId), e);
    });
    const list = Array.from(uniqueEnrollments.values()).sort((a,b) =>
        ((a.nom || "") + " " + (a.prenom || "")).localeCompare((b.nom || "") + " " + (b.prenom || ""), "fr")
    );
    if (!list.length) {
        body.innerHTML = '<tr><td colspan="4" class="saisie-vide">Aucun élève inscrit dans cette classe pour cette année scolaire.</td></tr>';
        button.disabled = true; progress.textContent = "Aucun élève à noter."; return;
    }

    const yearLabel = document.getElementById("annee").value;
    list.forEach(function(eleve, index) {
        const key = String(eleve.id) + "|" + anneeServeurId + "|" + control + "|" + String(subject.id);
        const existing = gradeMeta[key];
        const saved = resultats[String(eleve.id)] && resultats[String(eleve.id)][yearLabel] &&
            resultats[String(eleve.id)][yearLabel]["controle" + control]
            ? resultats[String(eleve.id)][yearLabel]["controle" + control][String(subject.id)] : "";
        const tr = document.createElement("tr");
        const number = document.createElement("td"); number.textContent = String(index + 1);
        const name = document.createElement("td"); name.textContent = ((eleve.nom || "") + " " + (eleve.prenom || "")).trim();
        const gradeCell = document.createElement("td");
        const input = document.createElement("input");
        input.type = "number"; input.min = "0"; input.max = String(subject.pointsMax); input.step = "0.01";
        input.className = "note-saisie-input"; input.inputMode = "decimal";
        input.setAttribute("aria-label", "Note de " + name.textContent + " sur " + subject.pointsMax);
        input.value = saved === null || saved === undefined ? "" : String(saved);
        input.dataset.studentId = String(eleve.id); input.dataset.enrollmentId = String(eleve.enrollmentId);
        input.dataset.subjectId = String(subject.id); input.dataset.control = String(control);
        input.dataset.gradeId = existing ? existing.id : ""; input.dataset.initialValue = input.value;
        const state = document.createElement("td"); state.className = "etat-saisie";
        state.textContent = existing ? "Enregistrée" : "À saisir";
        input.addEventListener("input", function() {
            const value = input.value.trim();
            const valid = value === "" || (Number.isFinite(Number(value)) && Number(value) >= 0 && Number(value) <= Number(subject.pointsMax));
            input.setCustomValidity(valid ? "" : "La note doit être comprise entre 0 et " + subject.pointsMax + ".");
            input.classList.toggle("note-erreur", !valid);
            state.textContent = value === input.dataset.initialValue ? (existing ? "Enregistrée" : "À saisir") : (value === "" ? "Non modifiée" : "À enregistrer");
        });
        gradeCell.appendChild(input); tr.append(number, name, gradeCell, state); body.appendChild(tr);
    });
    button.disabled = false;
    progress.textContent = list.length + " élève(s) • " + subject.nom + " • " + document.getElementById("saisieControle").selectedOptions[0].textContent;
}

async function enregistrerSaisieClasse() {
    const inputs = Array.from(document.querySelectorAll("#corpsSaisie .note-saisie-input"));
    if (!inputs.length) return;
    const button = document.getElementById("btnEnregistrerSaisie");
    const progress = document.getElementById("saisieProgression");
    const subject = matieres.find(m => String(m.id) === String(document.getElementById("saisieMatiere").value));
    if (!subject) { afficherMessage("Sélectionnez une matière.", "erreur"); return; }

    const changes = [];
    for (const input of inputs) {
        if (!input.checkValidity()) { input.reportValidity(); input.focus(); return; }
        const value = input.value.trim();
        if (value === "" || value === input.dataset.initialValue) continue;
        const grade = Number(value);
        if (!Number.isFinite(grade) || grade < 0 || grade > Number(subject.pointsMax)) {
            input.focus(); afficherMessage("La note doit être comprise entre 0 et " + subject.pointsMax + ".", "erreur"); return;
        }
        changes.push({input, grade});
    }
    if (!changes.length) {
        afficherMessage("Aucune nouvelle note à enregistrer. Les champs vides ne modifient pas les notes existantes.", "succes");
        return;
    }

    button.disabled = true;
    let savedCount = 0;
    try {
        for (const change of changes) {
            const input = change.input;
            const existingId = input.dataset.gradeId;
            const method = existingId ? "PUT" : "POST";
            const permission = existingId ? "resultats.update" : "resultats.create";
            if (!IMCAuth.requirePermission(permission)) throw new Error("Permission refusée pour " + (existingId ? "modifier" : "créer") + " les notes.");
            const url = "/api/grades/index.php" + (existingId ? "?id=" + encodeURIComponent(existingId) : "");
            const response = await fetch(url, {
                method, credentials: "same-origin",
                headers: {"Content-Type":"application/json","Accept":"application/json"},
                body: JSON.stringify({
                    enrollment_id: input.dataset.enrollmentId,
                    subject_id: input.dataset.subjectId,
                    assessment_number: Number(input.dataset.control),
                    grade: change.grade,
                    grade_date: new Date().toISOString().slice(0,10)
                })
            });
            const payload = await response.json();
            if (!response.ok || !payload.success) throw new Error(payload.error || "Échec d'enregistrement de " + input.getAttribute("aria-label") + ".");
            savedCount++;
        }
        await chargerDonnees();
        afficherSaisieClasse();
        progress.textContent = savedCount + " note(s) enregistrée(s) dans PostgreSQL.";
        afficherMessage(savedCount + " note(s) enregistrée(s) avec succès.", "succes");
    } catch (error) {
        progress.textContent = savedCount + " note(s) enregistrée(s) avant l'erreur.";
        afficherMessage(error.message || "Erreur pendant l'enregistrement.", "erreur");
        await chargerDonnees();
        afficherSaisieClasse();
    } finally {
        button.disabled = false;
    }
}


/* =========================================================
   CRÉER L'EN-TÊTE D'UNE MATIÈRE
========================================================= */

function creerEnteteMatiere(matiere) {

    const th =
        document.createElement("th");

    th.className =
        "colonne-matiere entete-vertical";


    const zone =
        document.createElement("div");

    zone.className =
        "mots-verticaux";


    const nom =
        String(
            matiere.nom || ""
        ).trim();


    const mots =
        nom.split(/\s+/);


    mots.forEach(function (mot) {

        const span =
            document.createElement("span");

        span.className =
            "mot-vertical";

        span.textContent =
            mot;

        zone.appendChild(span);

    });


    th.appendChild(zone);

    return th;

}


/* =========================================================
   CONSTRUIRE L'EN-TÊTE
========================================================= */

function construireEntete() {

    const ligne =
        document.querySelector(
            "#tableCarnet thead tr"
        );


    /*
     * On conserve la première cellule
     * "Matières".
     */

    while (ligne.children.length > 1) {

        ligne.removeChild(
            ligne.lastElementChild
        );

    }


    matieres.forEach(function (matiere) {

        ligne.appendChild(
            creerEnteteMatiere(matiere)
        );

    });


    const total =
        document.createElement("th");

    total.className =
        "colonne-resultat entete-simple-vertical";

    total.textContent =
        "TOTAL";

    ligne.appendChild(total);


    const moyenne =
        document.createElement("th");

    moyenne.className =
        "colonne-resultat entete-simple-vertical";

    moyenne.textContent =
        "MOYENNE";

    ligne.appendChild(moyenne);


    const place =
        document.createElement("th");

    place.className =
        "colonne-resultat entete-simple-vertical";

    place.textContent =
        "PLACE";

    ligne.appendChild(place);


    const directeur =
        document.createElement("th");

    directeur.className =
        "colonne-signature entete-signature";

    directeur.textContent =
        "Signature du Directeur";

    ligne.appendChild(directeur);


    const parents =
        document.createElement("th");

    parents.className =
        "colonne-signature entete-signature";

    parents.textContent =
        "Signature des parents";

    ligne.appendChild(parents);

}


/* =========================================================
   TOTAL DES POINTS MAX
========================================================= */

function totalPointsMax() {

    return matieres.reduce(
        function (total, matiere) {

            return total +
                Number(
                    matiere.pointsMax || 0
                );

        },
        0
    );

}


/* =========================================================
   CRÉER CELLULE NOTE
========================================================= */

function creerCelluleNote(
    matiere,
    numeroControle,
    valeur
) {

    const td =
        document.createElement("td");


    const input =
        document.createElement("input");


    input.type = "number";

    input.className =
        "note-input";


    input.min = "0";

    input.max =
        Number(
            matiere.pointsMax || 0
        );


    input.step = "0.01";


    input.dataset.subjectId =
        matiere.id;


    input.dataset.controle =
        numeroControle;


    input.value =
        valeur !== undefined &&
        valeur !== null &&
        valeur !== ""
            ? valeur
            : "";


    input.addEventListener(
        "input",
        function () {

            verifierNote(
                input,
                matiere
            );


            actualiserCalculsControle(
                numeroControle
            );

        }
    );


    input.addEventListener(
        "change",
        function () {

            verifierNote(
                input,
                matiere
            );


            actualiserCalculsControle(
                numeroControle
            );

        }
    );


    td.appendChild(input);

    return td;

}


/* =========================================================
   VÉRIFIER LE BARÈME
========================================================= */

function verifierNote(
    input,
    matiere
) {

    if (
        input.value === "" ||
        input.value === null
    ) {

        input.classList.remove(
            "note-erreur"
        );

        return;

    }


    let valeur =
        Number(input.value);


    const max =
        Number(
            matiere.pointsMax || 0
        );


    if (Number.isNaN(valeur)) {

        input.value = "";

        return;

    }


    if (valeur < 0) {

        valeur = 0;

        input.value = 0;

    }


    if (valeur > max) {

        valeur = max;

        input.value = max;

        afficherMessage(
            `La matière "${matiere.nom}" est sur ${max} points. La note a été limitée à ${max}.`,
            "erreur"
        );

    }


    input.classList.remove(
        "note-erreur"
    );

}


/* =========================================================
   RÉCUPÉRER LES NOTES DU CONTRÔLE
========================================================= */

function recupererNotesControle(
    numeroControle
) {

    const notes = {};

    const inputs =
        document.querySelectorAll(
            `.note-input[data-controle="${numeroControle}"]`
        );


    inputs.forEach(function (input) {

        if (
            input.value !== ""
        ) {

            notes[
                String(
                    input.dataset.subjectId
                )
            ] =
                Number(input.value);

        }

    });


    return notes;

}


/* =========================================================
   CALCUL TOTAL
========================================================= */

function calculerTotalControle(
    numeroControle
) {

    let total = 0;


    const inputs =
        document.querySelectorAll(
            `.note-input[data-controle="${numeroControle}"]`
        );


    inputs.forEach(function (input) {

        if (
            input.value !== ""
        ) {

            const valeur =
                Number(input.value);


            if (!Number.isNaN(valeur)) {

                total += valeur;

            }

        }

    });


    return total;

}


/* =========================================================
   MOYENNE /10
========================================================= */

function calculerMoyenneControle(
    numeroControle
) {

    const totalMax =
        totalPointsMax();


    const total =
        calculerTotalControle(
            numeroControle
        );


    const notes =
        recupererNotesControle(
            numeroControle
        );


    if (
        Object.keys(notes).length === 0 ||
        totalMax <= 0
    ) {

        return "";

    }


    return (
        total /
        totalMax *
        10
    );

}


/* =========================================================
   ACTUALISER TOTAL / MOYENNE / PLACE
========================================================= */

function actualiserCalculsControle(
    numeroControle
) {

    const total =
        calculerTotalControle(
            numeroControle
        );


    const moyenne =
        calculerMoyenneControle(
            numeroControle
        );


    const totalCell =
        document.getElementById(
            `total-${numeroControle}`
        );


    const moyenneCell =
        document.getElementById(
            `moyenne-${numeroControle}`
        );


    const placeCell =
        document.getElementById(
            `place-${numeroControle}`
        );


    const nombreNotes =
        Object.keys(
            recupererNotesControle(
                numeroControle
            )
        ).length;


    if (nombreNotes === 0) {

        totalCell.textContent = "";

        moyenneCell.textContent = "";

        placeCell.textContent = "";

        return;

    }


    totalCell.textContent =
        formatNombre(total);


    moyenneCell.textContent =
        formatNombre(moyenne);


    /*
     * Le classement est recalculé
     * après chaque modification.
     */

    calculerPlaces();

}


/* =========================================================
   FORMAT NOMBRE
========================================================= */

function formatNombre(
    valeur
) {

    if (
        valeur === "" ||
        valeur === null ||
        valeur === undefined
    ) {

        return "";

    }


    return Number(valeur)
        .toFixed(2)
        .replace(
            /\.00$/,
            ""
        )
        .replace(
            /(\.\d)0$/,
            "$1"
        )
        .replace(
            ".",
            ","
        );

}


/* =========================================================
   NORMALISER POUR LE CLASSEMENT
========================================================= */

function moyenneEtNotesEleve(
    eleve,
    numeroControle
) {

    /*
     * Si c'est l'élève actuellement affiché,
     * on utilise directement les notes
     * visibles dans le carnet.
     */

    if (
        eleveSelectionne &&
        String(eleve.id) ===
        String(eleveSelectionne.id)
    ) {

        const notes =
            recupererNotesControle(
                numeroControle
            );


        if (
            Object.keys(notes).length === 0
        ) {

            return null;

        }


        let total = 0;


        Object.keys(notes).forEach(
            function (subjectId) {

                total +=
                    Number(
                        notes[subjectId]
                    );

            }
        );


        const max =
            totalPointsMax();


        if (max <= 0) {

            return null;

        }


        return {
            total: total,
            moyenne:
                total / max * 10
        };

    }


    /*
     * Pour les autres élèves,
     * on lit les notes sauvegardées.
     */

    const id =
        String(eleve.id);


    const annee =
        document.getElementById(
            "annee"
        ).value;


    const sauvegarde =
        resultats[id] &&
        resultats[id][annee]
            ? resultats[id][annee]
            : null;


    if (!sauvegarde) {

        return null;

    }


    const notes =
        sauvegarde[
            `controle${numeroControle}`
        ];


    if (
        !notes ||
        Object.keys(notes).length === 0
    ) {

        return null;

    }


    let total = 0;


    Object.keys(notes).forEach(
        function (subjectId) {

            total +=
                Number(
                    notes[subjectId]
                );

        }
    );


    const max =
        totalPointsMax();


    if (max <= 0) {

        return null;

    }


    return {

        total: total,

        moyenne:
            total / max * 10

    };

}


/* =========================================================
   CLASSER LES 3 PREMIERS
========================================================= */

function calculerPlaces() {

    if (!eleveSelectionne) {

        return;

    }


    const classe =
        eleveSelectionne.classe;


    const annee =
        document.getElementById(
            "annee"
        ).value;


    for (
        let controle = 1;
        controle <= 3;
        controle++
    ) {

        const classement = [];


        eleves
            .filter(function (eleve) {

                return eleve.classe === classe;

            })
            .forEach(function (eleve) {

                const resultat =
                    moyenneEtNotesEleve(
                        eleve,
                        controle
                    );


                /*
                 * Un élève sans aucune note
                 * ne participe pas au classement.
                 */

                if (!resultat) {

                    return;

                }


                classement.push({

                    id:
                        String(eleve.id),

                    moyenne:
                        resultat.moyenne,

                    total:
                        resultat.total

                });

            });


        classement.sort(
            function (a, b) {

                if (
                    b.moyenne !==
                    a.moyenne
                ) {

                    return (
                        b.moyenne -
                        a.moyenne
                    );

                }


                return (
                    b.total -
                    a.total
                );

            }
        );


        /*
         * Seuls les trois premiers
         * obtiennent une place.
         */

        const top3 =
            classement.slice(0, 3);


        const element =
            document.getElementById(
                `place-${controle}`
            );


        if (!element) {

            continue;

        }


        const position =
            top3.findIndex(
                function (item) {

                    return (
                        item.id ===
                        String(
                            eleveSelectionne.id
                        )
                    );

                }
            );


        if (position === -1) {

            element.textContent = "";

            continue;

        }


        if (position === 0) {

            element.textContent =
                eleveEstFille(
                    eleveSelectionne
                )
                    ? "1ère"
                    : "1er";

        }

        else if (position === 1) {

            element.textContent =
                "2ème";

        }

        else if (position === 2) {

            element.textContent =
                "3ème";

        }

    }

}


/* =========================================================
   SEXE
========================================================= */

function eleveEstFille(
    eleve
) {

    const sexe =
        String(
            eleve.sexe || ""
        )
        .trim()
        .toLowerCase();


    return (
        sexe === "f" ||
        sexe === "fille" ||
        sexe === "féminin" ||
        sexe === "feminin"
    );

}


/* =========================================================
   AFFICHER LE CARNET
========================================================= */

function afficherCarnet(
    eleve
) {

    if (!eleve) {

        return;

    }


    document.getElementById(
        "zoneCarnet"
    ).style.display = "block";


    document.getElementById(
        "nomPrenom"
    ).textContent =
        `${eleve.nom || ""} ${eleve.prenom || ""}`;


    document.getElementById(
        "classeEleve"
    ).textContent =
        eleve.classe || "";


    const annee =
        document.getElementById(
            "annee"
        ).value;


    document.getElementById(
        "anneeEleve"
    ).textContent =
        annee;


    construireEntete();


    const tbody =
        document.getElementById(
            "corpsCarnet"
        );


    tbody.innerHTML = "";


    /*
     * Récupération des résultats sauvegardés.
     */

    const id =
        String(eleve.id);


    const sauvegarde =
        resultats[id] &&
        resultats[id][annee]
            ? resultats[id][annee]
            : {};


    /* =====================================================
       LIGNE COEFFICIENT
    ===================================================== */

    const ligneCoefficient =
        document.createElement("tr");


    const libelleCoefficient =
        document.createElement("td");

    libelleCoefficient.className =
        "colonne-ligne";


    libelleCoefficient.textContent =
        "Coefficient";


    ligneCoefficient.appendChild(
        libelleCoefficient
    );


    matieres.forEach(
        function (matiere) {

            const td =
                document.createElement("td");

            td.textContent =
                Number(
                    matiere.pointsMax || 0
                );

            ligneCoefficient.appendChild(
                td
            );

        }
    );


    /*
     * Total des coefficients / points max
     */

    const tdTotalMax =
        document.createElement("td");

    tdTotalMax.className =
        "cellule-calcul";


    tdTotalMax.textContent =
        formatNombre(
            totalPointsMax()
        );


    ligneCoefficient.appendChild(
        tdTotalMax
    );


    ligneCoefficient.appendChild(
        document.createElement("td")
    );


    ligneCoefficient.appendChild(
        document.createElement("td")
    );


    ligneCoefficient.appendChild(
        document.createElement("td")
    );


    ligneCoefficient.appendChild(
        document.createElement("td")
    );


    tbody.appendChild(
        ligneCoefficient
    );


    /* =====================================================
       LIGNES MOIS / CONTRÔLES
    ===================================================== */

    lignes.forEach(
        function (ligne) {

            const tr =
                document.createElement("tr");


            const tdNom =
                document.createElement("td");


            tdNom.className =
                "colonne-ligne";


            tdNom.textContent =
                ligne.nom;


            tr.appendChild(tdNom);


            if (
                ligne.type === "mois"
            ) {

                /*
                 * Les mois restent vides,
                 * comme dans le carnet.
                 */

                matieres.forEach(
                    function () {

                        tr.appendChild(
                            document.createElement(
                                "td"
                            )
                        );

                    }
                );


                /*
                 * TOTAL
                 */

                tr.appendChild(
                    document.createElement("td")
                );


                /*
                 * MOYENNE
                 */

                tr.appendChild(
                    document.createElement("td")
                );


                /*
                 * PLACE
                 */

                tr.appendChild(
                    document.createElement("td")
                );


                /*
                 * Signatures :
                 * aucun trait sur les mois.
                 */

                tr.appendChild(
                    document.createElement("td")
                );

                tr.appendChild(
                    document.createElement("td")
                );

            }

            else {

                const numero =
                    ligne.numero;


                const anciennesNotes =
                    sauvegarde[
                        `controle${numero}`
                    ] || {};


                matieres.forEach(
                    function (matiere) {

                        const valeur =
                            anciennesNotes[
                                String(
                                    matiere.id
                                )
                            ];


                        tr.appendChild(
                            creerCelluleNote(
                                matiere,
                                numero,
                                valeur
                            )
                        );

                    }
                );


                /*
                 * TOTAL
                 */

                const tdTotal =
                    document.createElement("td");

                tdTotal.className =
                    "cellule-calcul";

                tdTotal.id =
                    `total-${numero}`;


                /*
                 * MOYENNE
                 */

                const tdMoyenne =
                    document.createElement("td");

                tdMoyenne.className =
                    "cellule-calcul";

                tdMoyenne.id =
                    `moyenne-${numero}`;


                /*
                 * PLACE
                 */

                const tdPlace =
                    document.createElement("td");

                tdPlace.className =
                    "cellule-calcul";

                tdPlace.id =
                    `place-${numero}`;


                /*
                 * Signature Directeur
                 *
                 * TRAIT UNIQUEMENT
                 * POUR LES 3 CONTRÔLES.
                 */

                const tdDirecteur =
                    document.createElement("td");

                tdDirecteur.className =
                    "signature";


                const traitDirecteur =
                    document.createElement("span");

                traitDirecteur.className =
                    "trait-signature";


                tdDirecteur.appendChild(
                    traitDirecteur
                );


                /*
                 * Signature Parents
                 */

                const tdParents =
                    document.createElement("td");

                tdParents.className =
                    "signature";


                const traitParents =
                    document.createElement("span");

                traitParents.className =
                    "trait-signature";


                tdParents.appendChild(
                    traitParents
                );


                tr.appendChild(tdTotal);

                tr.appendChild(tdMoyenne);

                tr.appendChild(tdPlace);

                tr.appendChild(tdDirecteur);

                tr.appendChild(tdParents);

            }


            tbody.appendChild(tr);

        }
    );


    /*
     * Calculs initiaux
     */

    for (
        let controle = 1;
        controle <= 3;
        controle++
    ) {

        actualiserCalculsControle(
            controle
        );

    }


    /*
     * Recalcul du classement
     */

    calculerPlaces();

}


/* =========================================================
   ENREGISTRER
========================================================= */

async function enregistrerResultats() {

    if (!IMCAuth.requirePermission("resultats.update")) {
        afficherMessage("Permission refusée.", "erreur");
        return;
    }

    if (!eleveSelectionne) {
        afficherMessage("Veuillez sélectionner un élève.", "erreur");
        return;
    }

    const yearLabel = document.getElementById("annee").value;
    const enrollmentId = String(eleveSelectionne.enrollmentId || "");

    if (!enrollmentId || !anneeServeurId) {
        afficherMessage("Inscription ou année scolaire introuvable.", "erreur");
        return;
    }

    try {
        for (let controle = 1; controle <= 3; controle++) {
            const notes = recupererNotesControle(controle);

            for (const subjectId of Object.keys(notes)) {
                const matiere = matieres.find(function(m) {
                    return String(m.id) === String(subjectId);
                });
                if (!matiere) continue;

                const note = Number(notes[subjectId]);
                const max = Number(matiere.pointsMax);
                if (!Number.isFinite(note) || note < 0 || note > max) {
                    throw new Error("La note de " + matiere.nom + " doit être comprise entre 0 et " + max + ".");
                }

                const key = String(eleveSelectionne.id) + "|" + anneeServeurId + "|" +
                    controle + "|" + String(subjectId);
                const meta = gradeMeta[key];
                const body = {
                    enrollment_id: enrollmentId,
                    subject_id: String(subjectId),
                    assessment_number: controle,
                    grade: note,
                    grade_date: new Date().toISOString().slice(0, 10)
                };

                let response;
                if (meta) {
                    response = await fetch(
                        "/api/grades/index.php?id=" + encodeURIComponent(meta.id),
                        {
                            method: "PUT",
                            credentials: "same-origin",
                            headers: { "Content-Type": "application/json", "Accept": "application/json" },
                            body: JSON.stringify(body)
                        }
                    );
                } else {
                    response = await fetch(
                        "/api/grades/index.php",
                        {
                            method: "POST",
                            credentials: "same-origin",
                            headers: { "Content-Type": "application/json", "Accept": "application/json" },
                            body: JSON.stringify(body)
                        }
                    );
                }

                const payload = await response.json();
                if (!response.ok || !payload.success) throw new Error(payload.error || "Échec d'enregistrement d'une note.");

                const saved = payload.grade;
                gradeMeta[key] = { id: String(saved.id), enrollmentId: enrollmentId };
            }

            const existing = Object.keys(gradeMeta).filter(function(key) {
                return key.indexOf(String(eleveSelectionne.id) + "|" + anneeServeurId + "|" + controle + "|") === 0;
            });

            for (const key of existing) {
                const subjectId = key.split("|")[3];
                if (!Object.prototype.hasOwnProperty.call(notes, subjectId)) {
                    const meta = gradeMeta[key];
                    const response = await fetch(
                        "/api/grades/index.php?id=" + encodeURIComponent(meta.id),
                        { method: "DELETE", credentials: "same-origin", headers: { "Accept": "application/json" } }
                    );
                    const payload = await response.json();
                    if (!response.ok || !payload.success) throw new Error(payload.error || "Échec de suppression d'une note.");
                    delete gradeMeta[key];
                }
            }
        }

        const carnetBody = {
            enrollment_id: enrollmentId,
            proprete: document.getElementById("proprete").value,
            conduite: document.getElementById("conduite").value,
            tenue_materiels: document.getElementById("tenueMateriels").value,
            retard: document.getElementById("retard").value,
            absence: document.getElementById("absence").value,
            classe_promotion: document.getElementById("classePromotion").textContent,
            classe_refait: document.getElementById("classeRefait").textContent,
            eleve_remis: document.getElementById("eleveRemis").textContent,
            observation1: document.getElementById("observation1").value,
            observation2: document.getElementById("observation2").value,
            observation3: document.getElementById("observation3").value
        };

        const carnetResponse = await fetch(
            "/api/results/index.php",
            {
                method: "PUT",
                credentials: "same-origin",
                headers: { "Content-Type": "application/json", "Accept": "application/json" },
                body: JSON.stringify(carnetBody)
            }
        );
        const carnetPayload = await carnetResponse.json();
        if (!carnetResponse.ok || !carnetPayload.success) {
            throw new Error(carnetPayload.error || "Échec d'enregistrement du carnet.");
        }

        carnetMeta = carnetPayload.carnet || null;
        await chargerDonnees();
        await chargerDeuxiemePartie();
        afficherCarnet(eleveSelectionne);

        afficherMessage("Les résultats ont été enregistrés avec succès.", "succes");
    } catch (error) {
        afficherMessage(error.message || "Erreur d'enregistrement.", "erreur");
    }
}


/* =========================================================
   CHARGER LES INFORMATIONS DE LA DEUXIÈME PARTIE
========================================================= */

async function chargerDeuxiemePartie() {

    if (!eleveSelectionne || !eleveSelectionne.enrollmentId) return;

    const response = await fetch(
        "/api/results/index.php?enrollment_id=" +
        encodeURIComponent(eleveSelectionne.enrollmentId),
        { method: "GET", credentials: "same-origin", headers: { "Accept": "application/json" } }
    );
    const payload = await response.json();

    if (!response.ok || !payload.success) {
        throw new Error(payload.error || "Impossible de charger le carnet.");
    }

    const carnet = payload.carnet || {};

    document.getElementById("proprete").value = carnet.proprete || "";
    document.getElementById("conduite").value = carnet.conduite || "";
    document.getElementById("tenueMateriels").value = carnet.tenue_materiels || "";
    document.getElementById("retard").value = carnet.retard || "";
    document.getElementById("absence").value = carnet.absence || "";
    document.getElementById("classePromotion").textContent = carnet.classe_promotion || "";
    document.getElementById("classeRefait").textContent = carnet.classe_refait || "";
    document.getElementById("eleveRemis").textContent = carnet.eleve_remis || "";
    document.getElementById("observation1").value = carnet.observation1 || "";
    document.getElementById("observation2").value = carnet.observation2 || "";
    document.getElementById("observation3").value = carnet.observation3 || "";
    carnetMeta = carnet || null;
}


/* =========================================================
   FERMER
========================================================= */

function fermerCarnet() {

    document.getElementById(
        "zoneCarnet"
    ).style.display = "none";


    eleveSelectionne = null;

    afficherEleves();

}


/* =========================================================
   MESSAGE
========================================================= */

function afficherMessage(
    texte,
    type
) {

    const message =
        document.getElementById(
            "message"
        );


    message.textContent =
        texte;


    message.className =
        "message " +
        (
            type === "succes"
                ? "succes"
                : "erreur"
        );


    setTimeout(
        function () {

            message.className =
                "message";

        },
        3500
    );

}


/* =========================================================
   NAVIGATION
========================================================= */

function ouvrirPage(
    page
) {

    window.location.href =
        page;

}


/* =========================================================
   INITIALISATION
========================================================= */

document.addEventListener("DOMContentLoaded", async function () {
    try {
        const authenticated = await IMCAuth.verifySession();
        if (!authenticated) {
            window.location.href = "index.html";
            return;
        }
        if (!IMCAuth.requirePermission("resultats.read")) {
            afficherMessage("Permission refusée.", "erreur");
            return;
        }

        await chargerAnnees();
        await chargerClasses();
        await chargerDonnees();
        afficherEleves();
        afficherSaisieClasse();

        const ancienneAfficherCarnet = afficherCarnet;
        window.afficherCarnet = async function (eleve) {
            ancienneAfficherCarnet(eleve);
            try {
                await chargerDeuxiemePartie();
            } catch (error) {
                afficherMessage(error.message, "erreur");
            }
        };
    } catch (error) {
        afficherMessage(error.message || "Impossible de charger les résultats.", "erreur");
    }
});


</script>

</body>
</html>
