/**
 * STS2Store - State management with localStorage
 *
 * All keys are namespaced with 'sts2mm_' to avoid collisions.
 * Values are JSON-serialized/deserialized automatically.
 */
class STS2Store {
    constructor(namespace = 'sts2mm_') {
        this._namespace = namespace;
    }

    // ── Core CRUD ──────────────────────────────────────────────

    /**
     * Get a value from the store.
     * @param {string} key
     * @param {*} defaultValue - returned when the key does not exist
     * @returns {*}
     */
    get(key, defaultValue = null) {
        try {
            const raw = localStorage.getItem(this._namespace + key);
            if (raw === null) return defaultValue;
            return JSON.parse(raw);
        } catch {
            return defaultValue;
        }
    }

    /**
     * Set a value in the store.
     * @param {string} key
     * @param {*} value - will be JSON-serialized
     */
    set(key, value) {
        try {
            localStorage.setItem(this._namespace + key, JSON.stringify(value));
        } catch (e) {
            console.error('[STS2Store] Failed to set key:', key, e);
        }
    }

    /**
     * Remove a single key from the store.
     * @param {string} key
     */
    remove(key) {
        localStorage.removeItem(this._namespace + key);
    }

    /**
     * Remove ALL namespaced keys from localStorage.
     */
    clear() {
        const prefix = this._namespace;
        const keysToRemove = [];
        for (let i = 0; i < localStorage.length; i++) {
            const k = localStorage.key(i);
            if (k && k.startsWith(prefix)) {
                keysToRemove.push(k);
            }
        }
        keysToRemove.forEach(k => localStorage.removeItem(k));
    }

    // ── Convenience helpers ────────────────────────────────────

    /**
     * Check whether a key exists in the store.
     * @param {string} key
     * @returns {boolean}
     */
    has(key) {
        return localStorage.getItem(this._namespace + key) !== null;
    }

    /**
     * Return all namespaced keys as an array.
     * @returns {string[]}
     */
    keys() {
        const prefix = this._namespace;
        const result = [];
        for (let i = 0; i < localStorage.length; i++) {
            const k = localStorage.key(i);
            if (k && k.startsWith(prefix)) {
                result.push(k.slice(prefix.length));
            }
        }
        return result;
    }

    // ── Default config ─────────────────────────────────────────

    /**
     * Initialize default configuration values.
     * Only writes a key if it does not already exist in the store.
     */
    initDefaults() {
        const defaults = {
            // Paths
            game_path: '',
            save_path: '',
            temp_mods_path: '',

            // Settings
            language: 'zh_CN',
            minimize_to_tray: true,
            auto_backup: true,
            dpi_scale: 1.0,
            theme: 'steam_win11',

            // Window state
            window_width: 1280,
            window_height: 800,
            window_maximized: false,

            // Router
            current_tab: 'mods',

            // Mod filter state
            mod_filter: 'all',
            mod_sort: 'name',
            mod_search: '',

            // First run flag
            first_run: true,

            // Download settings
            max_concurrent_downloads: 3,
            download_path: '',
        };

        for (const [key, value] of Object.entries(defaults)) {
            if (!this.has(key)) {
                this.set(key, value);
            }
        }
    }

    /**
     * Get the total number of namespaced keys stored.
     * @returns {number}
     */
    size() {
        return this.keys().length;
    }
}

// ── Export ─────────────────────────────────────────────────────
window.STS2Store = STS2Store;
