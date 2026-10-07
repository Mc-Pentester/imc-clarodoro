/* F-02-D: server-authoritative finance page adapter.
 * The browser may render/cache data, but all financial state comes from PostgreSQL.
 */
(function () {
    "use strict";

    const endpoint = "/api/finance/index.php";
    let state = {
        invoices: [],
        payments: [],
        schedules: [],
        enrollments: [],
        school_years: []
    };

    function money(value) {
        return Number(value || 0);
    }

    function selectedYearLabel() {
        return document.getElementById("annee")?.value || "";
    }

    function selectedEnrollment() {
        if (!window.eleveSelectionne) return null;
        const year = selectedYearLabel();
        return state.enrollments.find(function (e) {
            return e.student_id === window.eleveSelectionne.id &&
                e.school_year_label === year &&
                e.status !== "CANCELLED";
        }) || null;
    }

    function rebuildLocalView() {
        const year = selectedYearLabel();

        window.etudiants = state.enrollments
            .filter(function (e) {
                return e.school_year_label === year;
            })
            .map(function (e) {
                return {
                    id: e.student_id,
                    nom: e.last_name,
                    prenom: e.first_name,
                    classe: e.class_name,
                    matricule: e.matricule,
                    enrollmentId: e.enrollment_id
                };
            });

        const unique = new Map();
        window.etudiants.forEach(function (student) {
            unique.set(student.id, student);
        });
        window.etudiants = Array.from(unique.values());

        window.finances = {};
        state.enrollments
            .filter(function (e) {
                return e.school_year_label === year;
            })
            .forEach(function (e) {
                const invoice = state.invoices.find(function (i) {
                    return i.enrollment_id === e.enrollment_id &&
                        i.status !== "CANCELLED";
                });

                const payments = invoice
                    ? state.payments.filter(function (p) {
                        return p.invoice_id === invoice.id;
                    })
                    : [];

                const schedule = state.schedules.find(function (s) {
                    return s.school_year_id === e.school_year_id &&
                        s.class_id === e.class_id &&
                        s.status === "ACTIVE";
                });

                window.finances[year + "|" + e.student_id] = {
                    studentId: e.student_id,
                    enrollmentId: e.enrollment_id,
                    annee: year,
                    tarifNormal: invoice
                        ? money(invoice.base_amount)
                        : money(schedule?.total_amount),
                    reduction: invoice
                        ? money(invoice.discount_amount)
                        : 0,
                    motifReduction: invoice?.discount_reason || "",
                    invoiceId: invoice?.id || null,
                    versements: payments.map(function (p, index) {
                        return {
                            id: p.id,
                            numero: index + 1,
                            date: p.payment_date,
                            heure: p.created_at
                                ? new Date(p.created_at).toLocaleTimeString("fr-FR", {
                                    hour: "2-digit",
                                    minute: "2-digit"
                                })
                                : "",
                            montant: money(p.amount),
                            mode: p.method,
                            observation: p.reference || ""
                        };
                    })
                };
            });

        window.tarifs = {};
        state.schedules.forEach(function (s) {
            window.tarifs[s.school_year_label + "|" + s.class_name] = {
                classe: s.class_name,
                date1: s.installment_1_label || "",
                montant1: money(s.installment_1_amount),
                date2: s.installment_2_label || "",
                montant2: money(s.installment_2_amount),
                date3: s.installment_3_label || "",
                montant3: money(s.installment_3_amount),
                montantTotal: money(s.total_amount)
            };
        });
    }

    async function loadServerState() {
        const response = await fetch(endpoint, {
            method: "GET",
            credentials: "same-origin",
            cache: "no-store",
            headers: { "Accept": "application/json" }
        });

        const payload = await response.json();
        if (!response.ok || !payload.success) {
            throw new Error(payload.error || "Impossible de charger les données financières");
        }

        state = {
            invoices: Array.isArray(payload.invoices) ? payload.invoices : [],
            payments: Array.isArray(payload.payments) ? payload.payments : [],
            schedules: Array.isArray(payload.schedules) ? payload.schedules : [],
            enrollments: Array.isArray(payload.enrollments) ? payload.enrollments : [],
            school_years: Array.isArray(payload.school_years) ? payload.school_years : []
        };

        rebuildLocalView();
    }

    window.genererAnnees = function () {
        const select = document.getElementById("annee");
        if (!select) return;

        const current = select.value;
        select.innerHTML = "";

        state.school_years.forEach(function (year) {
            const option = document.createElement("option");
            option.value = year.label;
            option.textContent = year.label;
            select.appendChild(option);
        });

        if (current && state.school_years.some(function (y) { return y.label === current; })) {
            select.value = current;
        } else if (state.school_years.length) {
            select.value = state.school_years[0].label;
        }
    };

    window.actualiser = async function () {
        try {
            await loadServerState();

            window.genererAnnees();

            const year = selectedYearLabel();
            document.getElementById("anneeAffichee").textContent =
                "Année académique : " + year;

            window.eleveSelectionne = null;
            document.getElementById("ficheEleve").classList.add("hidden");

            window.afficherClasses();
            window.afficherTarifs();
            window.afficherEleves();
            window.afficherSituations();
            window.afficherResume();

            console.info("[F-02-D] finances loaded from PostgreSQL");
        } catch (error) {
            console.error("[F-02-D]", error);
            if (typeof window.afficherMessage === "function") {
                window.afficherMessage(
                    "Impossible de charger les données financières du serveur.",
                    "error"
                );
            }
        }
    };

    window.enregistrerSituation = async function () {
        if (!window.eleveSelectionne) return;

        const enrollment = selectedEnrollment();
        if (!enrollment) {
            return window.afficherMessage("Inscription serveur introuvable.", "error");
        }

        const base = money(document.getElementById("tarifNormal").value);
        const discount = Math.min(
            money(document.getElementById("reduction").value),
            base
        );
        const reason = document.getElementById("motifReduction").value.trim();

        const existing = state.invoices.find(function (i) {
            return i.enrollment_id === enrollment.enrollment_id &&
                i.status !== "CANCELLED";
        });

        if (existing) {
            return window.afficherMessage(
                "Cette situation possède déjà une facture serveur. Une modification comptable dédiée sera utilisée dans l'étape suivante.",
                "error"
            );
        }

        const response = await fetch(endpoint, {
            method: "POST",
            credentials: "same-origin",
            headers: {
                "Content-Type": "application/json",
                "Accept": "application/json"
            },
            body: JSON.stringify({
                type: "invoice",
                enrollment_id: enrollment.enrollment_id,
                base_amount: base,
                discount_amount: discount,
                discount_reason: reason,
                invoice_date: new Date().toISOString().slice(0, 10)
            })
        });

        const payload = await response.json();
        if (!response.ok || !payload.success) {
            return window.afficherMessage(payload.error || "Enregistrement financier refusé.", "error");
        }

        await window.actualiser();
        window.afficherMessage("Situation financière enregistrée côté serveur.");
    };

    async function createPayment(amount, date, method, reference) {
        const enrollment = selectedEnrollment();
        if (!enrollment) {
            return window.afficherMessage("Inscription serveur introuvable.", "error");
        }

        const invoice = state.invoices.find(function (i) {
            return i.enrollment_id === enrollment.enrollment_id &&
                i.status !== "CANCELLED";
        });

        if (!invoice) {
            return window.afficherMessage(
                "Créez d'abord la situation financière de l'élève.",
                "error"
            );
        }

        const response = await fetch(endpoint, {
            method: "POST",
            credentials: "same-origin",
            headers: {
                "Content-Type": "application/json",
                "Accept": "application/json"
            },
            body: JSON.stringify({
                type: "payment",
                invoice_id: invoice.id,
                amount: amount,
                payment_date: date,
                method: method,
                reference: reference || null
            })
        });

        const payload = await response.json();
        if (!response.ok || !payload.success) {
            return window.afficherMessage(
                payload.error || "Versement refusé par le serveur.",
                "error"
            );
        }

        await window.actualiser();
        window.chargerFicheEleve();
        window.afficherSituations();
        window.afficherResume();
        window.afficherMessage("Versement enregistré côté serveur.");
    }

    window.enregistrerVersement = async function () {
        if (!window.eleveSelectionne) return;

        const amount = money(document.getElementById("versementMontant").value);
        if (amount <= 0) {
            return window.afficherMessage("Veuillez saisir un montant supérieur à 0.", "error");
        }

        await createPayment(
            amount,
            document.getElementById("versementDate").value,
            document.getElementById("versementMode").value,
            document.getElementById("versementObservation").value.trim()
        );

        window.fermerModals();
    };

    window.enregistrerVersementDirect = async function (numero, valeur) {
        const amount = money(valeur);
        if (amount <= 0) return;
        await createPayment(amount, new Date().toISOString().slice(0, 10), "Espèces", "Versement " + numero);
    };

    window.supprimerVersement = function () {
        window.afficherMessage(
            "La suppression directe d'un versement comptable est désactivée pour préserver l'intégrité PostgreSQL.",
            "error"
        );
    };

    window.enregistrerTarif = async function () {
        const year = state.school_years.find(function (y) {
            return y.label === selectedYearLabel();
        });
        const className = document.getElementById("tarifClasseOriginal").value;

        const schedule = state.schedules.find(function (s) {
            return s.school_year_id === year?.id &&
                s.class_name === className;
        });

        if (!year || !schedule) {
            return window.afficherMessage(
                "Année ou classe non référencée côté serveur.",
                "error"
            );
        }

        const total = money(document.getElementById("montantTotal").value);
        const m1 = money(document.getElementById("montant1").value);
        const m2 = money(document.getElementById("montant2").value);
        const m3 = money(document.getElementById("montant3").value);

        if (Math.round((m1 + m2 + m3) * 100) !== Math.round(total * 100)) {
            return window.afficherMessage(
                "La somme des versements doit être égale au total.",
                "error"
            );
        }

        const response = await fetch(endpoint, {
            method: "POST",
            credentials: "same-origin",
            headers: {
                "Content-Type": "application/json",
                "Accept": "application/json"
            },
            body: JSON.stringify({
                type: "schedule",
                school_year_id: year.id,
                class_id: schedule.class_id,
                total_amount: total,
                installment_1_amount: m1,
                installment_1_label: document.getElementById("date1").value.trim(),
                installment_2_amount: m2,
                installment_2_label: document.getElementById("date2").value.trim(),
                installment_3_amount: m3,
                installment_3_label: document.getElementById("date3").value.trim()
            })
        });

        const payload = await response.json();
        if (!response.ok || !payload.success) {
            return window.afficherMessage(payload.error || "Tarif refusé par le serveur.", "error");
        }

        window.fermerModals();
        await window.actualiser();
        window.afficherMessage("Tarif enregistré côté serveur.");
    };

    window.chargerFicheEleve = function () {
        if (!window.eleveSelectionne) return;

        const f = window.obtenirFinanceEleve(window.eleveSelectionne);
        const ap = Math.max(0, money(f.tarifNormal) - money(f.reduction));
        const tv = f.versements.reduce(function (sum, p) { return sum + money(p.montant); }, 0);

        document.getElementById("tarifNormal").value = money(f.tarifNormal);
        document.getElementById("reduction").value = money(f.reduction);
        document.getElementById("montantAPayer").value = ap.toFixed(2);
        document.getElementById("totalVerse").value = tv.toFixed(2);
        document.getElementById("reste").value = Math.max(0, ap - tv).toFixed(2);
        document.getElementById("motifReduction").value = f.motifReduction || "";

        if (typeof window.afficherTableauResumeEleve === "function") {
            window.afficherTableauResumeEleve(window.eleveSelectionne, f);
        }

        const tb = document.getElementById("tableVersements");
        tb.innerHTML = "";

        f.versements.forEach(function (p, index) {
            const tr = document.createElement("tr");
            tr.innerHTML =
                "<td>" + (index + 1) + "</td>" +
                "<td>📅 " + window.escapeHtml(p.date || "") +
                "<br><span class='small'>🕐 " + window.escapeHtml(p.heure || "—") + "</span></td>" +
                "<td>" + (index + 1) + "e</td>" +
                "<td class='money'>" + window.formatMontant(p.montant) + "</td>" +
                "<td>" + window.escapeHtml(p.mode || "") + "</td>" +
                "<td>" + window.escapeHtml(p.observation || "") + "</td>" +
                "<td class='no-print'><span class='small'>Lecture seule</span></td>";
            tb.appendChild(tr);
        });

        if (!f.versements.length) {
            tb.innerHTML = "<tr><td colspan='7'>Aucun versement enregistré.</td></tr>";
        }

        document.getElementById("ficheEleve").classList.remove("hidden");
    };
})();
