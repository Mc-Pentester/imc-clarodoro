function calculerMontantEleve() {
    if (!eleveSelectionne) return;

    const tarif = Number(document.getElementById("tarifNormal").value || 0);
    const reduction = Number(document.getElementById("reduction").value || 0);

    const vetement1 = Number(document.getElementById("vetement1").value || 0);
    const vetement2 = Number(document.getElementById("vetement2").value || 0);
    const vetement3 = Number(document.getElementById("vetement3").value || 0);

    const totalVetements = vetement1 + vetement2 + vetement3;

    document.getElementById("totalVetements").value =
        totalVetements.toFixed(2);

    const montantAPayer =
        Math.max(0, tarif - reduction) + totalVetements;

    document.getElementById("montantAPayer").value =
        montantAPayer.toFixed(2);

    const finance = obtenirFinanceEleve(eleveSelectionne);

    const totalVerse = finance.versements.reduce(
        (total, versement) =>
            total + Number(versement.montant || 0),
        0
    );

    document.getElementById("totalVerse").value =
        totalVerse.toFixed(2);

    document.getElementById("reste").value =
        Math.max(0, montantAPayer - totalVerse).toFixed(2);
}
function calculerPlaces(eleves, controle) {

    const classement = eleves
        .map(eleve => {

            const notes = eleve.resultats?.[controle] || [];

            const calcul = calculerControle(notes);

            return {
                eleve: eleve,
                moyenne: calcul.moyenne,
                aDesNotes: notes.some(note =>
                    note !== "" &&
                    note !== null &&
                    note !== undefined
                )
            };
        })
        .filter(item => item.aDesNotes)
        .sort((a, b) => b.moyenne - a.moyenne);

    const places = {};

    classement.slice(0, 3).forEach((item, index) => {

        const place = index + 1;

        const sexe = String(item.eleve.sexe || "")
            .toLowerCase();

        if (place === 1) {
            places[item.eleve.id] =
                sexe === "f" || sexe === "fille"
                    ? "1ère"
                    : "1er";
        } else {
            places[item.eleve.id] =
                place + "ème";
        }
    });

    return places;
}
function afficherElevesClasse() {

    const classe = document.getElementById('filtreClasse').value;
    const liste = document.getElementById('listeElevesClasse');

    const eleves = JSON.parse(
        localStorage.getItem('imc_students') || '[]'
    );

    const elevesFiltres = classe === ''
        ? eleves
        : eleves.filter(function(eleve) {
            return String(eleve.classe || '').trim() === classe;
        });

    liste.innerHTML = '';

    if (elevesFiltres.length === 0) {
        liste.innerHTML = '<p>Aucun élève dans cette classe.</p>';
        return;
    }

    const titre = document.createElement('h3');

    titre.textContent = classe === ''
        ? 'Tous les élèves'
        : 'Élèves de ' + classe;

    liste.appendChild(titre);

    elevesFiltres.forEach(function(eleve) {

        const bouton = document.createElement('button');

        bouton.type = 'button';
        bouton.className = 'bouton-eleve';

        bouton.textContent =
            (eleve.nom || '') + ' ' + (eleve.prenom || '');

        bouton.onclick = function() {

            // Afficher le carnet
            const carnet = document.getElementById('carnetEleve');

            if (carnet) {
                carnet.style.display = 'block';
            }

            // Sélectionner l'élève avec la fonction
            // déjà utilisée par ton carnet
            if (typeof selectionnerEleve === 'function') {
                selectionnerEleve(eleve.id);
            }

            // Aller directement au carnet
            if (carnet) {
                carnet.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        };

        liste.appendChild(bouton);
    });
}

document.addEventListener('DOMContentLoaded', function() {
    afficherElevesClasse();
});

