/**
 * STS2I18n - Internationalization system
 *
 * Loads locale data (expects a global `STS2_LOCALES` object keyed by language code),
 * provides translation lookup, sprintf-like formatting, and DOM auto-translation.
 */
class STS2I18n {
    /**
     * @param {object} options
     * @param {object} options.locales  - locale data map { zh_CN: {...}, en_US: {...} }
     * @param {string} options.fallback - fallback language code (default 'en_US')
     */
    constructor(options = {}) {
        this._locales = options.locales || (typeof STS2_LOCALES !== 'undefined' ? STS2_LOCALES : {});
        this._fallback = options.fallback || 'en_US';
        this._current = options.defaultLang || 'zh_CN';
    }

    // ── Translation lookup ─────────────────────────────────────

    /**
     * Get a translated string by key.
     * Falls back to the fallback language, then returns the key itself.
     * @param {string} key
     * @returns {string}
     */
    translate(key) {
        const dict = this._locales[this._current];
        if (dict && key in dict) return dict[key];

        const fb = this._locales[this._fallback];
        if (fb && key in fb) return fb[key];

        return key;
    }

    /**
     * Translate a key and substitute positional arguments (%s, %d, etc.).
     * Usage: translate_fmt('author', ['Alice'])  → "Author: Alice"
     *
     * Supports %s, %d, %f, %i patterns and {0}, {1} positional placeholders.
     *
     * @param {string} key
     * @param {Array} args
     * @returns {string}
     */
    translate_fmt(key, args = []) {
        let text = this.translate(key);

        // Replace {0}, {1}, … style placeholders first
        args.forEach((val, idx) => {
            text = text.split('{' + idx + '}').join(String(val));
        });

        // Replace classic printf-style placeholders (%s, %d, %f, %i, %.)
        let argIndex = 0;
        text = text.replace(/%(\.\d+)?[sdfi]/g, (match) => {
            if (argIndex >= args.length) return match;
            const val = args[argIndex++];
            // Handle precision for floats
            if (match.includes('.')) {
                const precision = parseInt(match.slice(2), 10);
                return Number(val).toFixed(precision);
            }
            return String(val);
        });

        return text;
    }

    // ── DOM auto-translation ───────────────────────────────────

    /**
     * Scan the DOM for elements with [data-i18n] and set their textContent.
     * Also supports [data-i18n-args] (JSON array) for formatted translations.
     */
    applyTranslations() {
        document.querySelectorAll('[data-i18n]').forEach(el => {
            const key = el.getAttribute('data-i18n');
            const argsAttr = el.getAttribute('data-i18n-args');
            if (argsAttr) {
                try {
                    const args = JSON.parse(argsAttr);
                    el.textContent = this.translate_fmt(key, args);
                } catch {
                    el.textContent = this.translate(key);
                }
            } else {
                el.textContent = this.translate(key);
            }
        });
    }

    /**
     * Scan the DOM for elements with [data-i18n-placeholder]
     * and set their placeholder attribute.
     */
    applyPlaceholders() {
        document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
            const key = el.getAttribute('data-i18n-placeholder');
            el.setAttribute('placeholder', this.translate(key));
        });

        // Also handle title attributes
        document.querySelectorAll('[data-i18n-title]').forEach(el => {
            const key = el.getAttribute('data-i18n-title');
            el.setAttribute('title', this.translate(key));
        });
    }

    // ── Language switching ─────────────────────────────────────

    /**
     * Switch the active language, persist the preference, and re-apply translations.
     * @param {string} lang - language code, e.g. 'zh_CN', 'en_US'
     */
    setLanguage(lang) {
        if (!this._locales[lang]) {
            console.warn('[STS2I18n] Unknown language:', lang);
            return;
        }
        this._current = lang;

        // Persist via store if available
        if (window.STS2Store_instance) {
            window.STS2Store_instance.set('language', lang);
        }

        // Re-apply all DOM translations
        this.applyTranslations();
        this.applyPlaceholders();

        // Fire a custom event so other modules can react
        document.dispatchEvent(new CustomEvent('language-changed', { detail: { lang } }));
    }

    /**
     * Get the currently active language code.
     * @returns {string}
     */
    getCurrentLanguage() {
        return this._current;
    }

    /**
     * Return all available language codes.
     * @returns {string[]}
     */
    getAvailableLanguages() {
        return Object.keys(this._locales);
    }

    /**
     * Check whether a language code has locale data loaded.
     * @param {string} lang
     * @returns {boolean}
     */
    hasLanguage(lang) {
        return lang in this._locales;
    }
}

// ── Export ─────────────────────────────────────────────────────
window.STS2I18n = STS2I18n;
