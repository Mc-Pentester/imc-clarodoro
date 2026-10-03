/**
 * IMC-Clarodoro - API Client
 * ARCH-01-PHP - Foundation
 * 
 * Client API minimal pour les futures communications avec le serveur PHP.
 * Pour ARCH-01-PHP, ce fichier est défini mais non utilisé pour remplacer
 * les mécanismes actuels (auth.js, secure-storage.js).
 * 
 * Ce client sera intégré progressivement lors des phases de migration.
 */

/**
 * Effectue une requête API vers le serveur PHP
 * 
 * @param {string} url - URL de l'endpoint API
 * @param {Object} options - Options de la requête fetch
 * @returns {Promise<Object>} - Promise avec la réponse JSON
 * @throws {Error} - Erreur HTTP ou de parsing JSON
 */
async function apiRequest(url, options = {}) {
    // Options par défaut
    const defaultOptions = {
        method: 'GET',
        headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        },
        credentials: 'same-origin' // Inclure les cookies de session
    };

    // Fusionner avec les options fournies
    const finalOptions = {
        ...defaultOptions,
        ...options,
        headers: {
            ...defaultOptions.headers,
            ...options.headers
        }
    };

    // Convertir le body en JSON si nécessaire
    if (options.body && typeof options.body === 'object') {
        finalOptions.body = JSON.stringify(options.body);
    }

    try {
        const response = await fetch(url, finalOptions);

        // Vérifier si la réponse est OK
        if (!response.ok) {
            throw new Error(`HTTP Error: ${response.status} ${response.statusText}`);
        }

        // Vérifier le Content-Type
        const contentType = response.headers.get('content-type');
        if (!contentType || !contentType.includes('application/json')) {
            throw new Error('Response is not JSON');
        }

        // Parser le JSON
        const data = await response.json();
        return data;

    } catch (error) {
        // Propager l'erreur proprement
        console.error('API Request Error:', error);
        throw error;
    }
}

/**
 * Requête GET
 * 
 * @param {string} url - URL de l'endpoint
 * @returns {Promise<Object>}
 */
function apiGet(url) {
    return apiRequest(url, { method: 'GET' });
}

/**
 * Requête POST
 * 
 * @param {string} url - URL de l'endpoint
 * @param {Object} data - Données à envoyer
 * @returns {Promise<Object>}
 */
function apiPost(url, data) {
    return apiRequest(url, { method: 'POST', body: data });
}

/**
 * Requête PUT
 * 
 * @param {string} url - URL de l'endpoint
 * @param {Object} data - Données à envoyer
 * @returns {Promise<Object>}
 */
function apiPut(url, data) {
    return apiRequest(url, { method: 'PUT', body: data });
}

/**
 * Requête PATCH
 * 
 * @param {string} url - URL de l'endpoint
 * @param {Object} data - Données à envoyer
 * @returns {Promise<Object>}
 */
function apiPatch(url, data) {
    return apiRequest(url, { method: 'PATCH', body: data });
}

/**
 * Requête DELETE
 * 
 * @param {string} url - URL de l'endpoint
 * @returns {Promise<Object>}
 */
function apiDelete(url) {
    return apiRequest(url, { method: 'DELETE' });
}

// Exposer les fonctions globalement
window.IMCApi = {
    request: apiRequest,
    get: apiGet,
    post: apiPost,
    put: apiPut,
    patch: apiPatch,
    delete: apiDelete
};
