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
async function afficherElevesClasse() {

    const classe = document.getElementById('filtreClasse').value;
    const liste = document.getElementById('listeElevesClasse');
    liste.replaceChildren();

    try {
        const response = await fetch('api/students/index.php', {
            method: 'GET',
            credentials: 'same-origin',
            headers: { 'Accept': 'application/json' }
        });
        const payload = await response.json();

        if (!response.ok || !payload.success || !Array.isArray(payload.students)) {
            throw new Error(payload.message || 'Impossible de charger les élèves depuis le serveur.');
        }

        const eleves = payload.students.map(function(student) {
            const profile = student && student.profile_data && typeof student.profile_data === 'object'
                ? student.profile_data
                : {};

            return {
                ...student,
                id: student.id,
                nom: student.last_name || '',
                prenom: student.first_name || '',
                classe: profile.classe || student.class_name || '',
                sexe: student.sex || ''
            };
        });

        const elevesFiltres = classe === ''
            ? eleves
            : eleves.filter(function(eleve) {
                return String(eleve.classe || '').trim() === classe;
            });

        if (elevesFiltres.length === 0) {
            const message = document.createElement('p');
            message.textContent = classe === ''
                ? 'Aucun élève disponible.'
                : 'Aucun élève dans cette classe.';
            liste.appendChild(message);
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
            bouton.textContent = (eleve.nom || '') + ' ' + (eleve.prenom || '');

            bouton.onclick = function() {
                const carnet = document.getElementById('carnetEleve');

                if (carnet) {
                    carnet.style.display = 'block';
                }

                if (typeof selectionnerEleve === 'function') {
                    selectionnerEleve(eleve.id);
                }

                if (carnet) {
                    carnet.scrollIntoView({ behavior: 'smooth', block: 'start' });
                }
            };

            liste.appendChild(bouton);
        });
    } catch (error) {
        console.error('Erreur de chargement des élèves depuis l’API :', error);
        const message = document.createElement('p');
        message.textContent = error.message || 'Impossible de charger les élèves depuis le serveur.';
        liste.appendChild(message);
    }
}

document.addEventListener('DOMContentLoaded', function() {
    afficherElevesClasse();
});

