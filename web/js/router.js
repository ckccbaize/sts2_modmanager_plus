/**
 * STS2Router - SPA router for tab/page switching
 *
 * Manages visibility of .page sections and active state of .tab-btn buttons.
 * Persists the current tab to localStorage and restores it on init.
 */
class STS2Router {
    /**
     * @param {object} options
     * @param {string[]} options.tabs         - list of valid tab names
     * @param {string}   options.defaultTab   - tab to show if none saved
     * @param {STS2Store} options.store       - store instance for persistence
     */
    constructor(options = {}) {
        this._tabs = options.tabs || ['mods', 'bundles', 'saves', 'nexus', 'downloads', 'settings'];
        this._defaultTab = options.defaultTab || 'mods';
        this._store = options.store || null;
        this._currentTab = null;
        this._listeners = [];
    }

    // ── Initialization ─────────────────────────────────────────

    /**
     * Initialize the router: restore last tab from store, set up click handlers.
     * Also checks URL for hash (#tab=) or query (?tab=) parameter to force a specific tab on load.
     */
    init() {
        // Wire up tab button click listeners
        document.querySelectorAll('.tab-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.preventDefault();
                const tabName = btn.getAttribute('data-tab') || btn.getAttribute('data-page');
                if (tabName) this.navigateTo(tabName);
            });
        });

        // Check URL for hash (#mods) or query (?tab=mods) parameter to force a specific tab
        // Hash takes priority (browser's native navigation won't change hash)
        const hashTab = window.location.hash.replace('#', '');
        const urlParams = new URLSearchParams(window.location.search);
        const queryTab = urlParams.get('tab');

        // Priority: hash > query > localStorage
        let target;
        if (hashTab && this._tabs.includes(hashTab)) {
            target = hashTab;
            console.log('[STS2Router] Using tab from hash:', target);
        } else if (queryTab && this._tabs.includes(queryTab)) {
            target = queryTab;
            console.log('[STS2Router] Using tab from query:', target);
        } else {
            const saved = this._store ? this._store.get('current_tab', this._defaultTab) : this._defaultTab;
            target = this._tabs.includes(saved) ? saved : this._defaultTab;
        }
        this.navigateTo(target, false); // false = no animation on first load
    }

    // ── Navigation ─────────────────────────────────────────────

    /**
     * Navigate to a specific tab/page.
     * @param {string} tabName - target tab identifier
     * @param {boolean} animate - whether to trigger the page-enter animation (default true)
     */
    navigateTo(tabName, animate = true) {
        if (!this._tabs.includes(tabName)) {
            console.warn('[STS2Router] Unknown tab:', tabName);
            return;
        }

        // Don't re-navigate to the same tab
        if (this._currentTab === tabName) return;

        // Check if bundle is active and trying to switch to mods page
        if (tabName === 'mods' && this._store) {
            const activeBundle = this._store.get('active_bundle', null);
            if (activeBundle) {
                // Bundle is active, show alert and prevent navigation
                const t = window.STS2I18n_instance ? window.STS2I18n_instance.translate.bind(window.STS2I18n_instance) : (k) => k;
                alert(t('close_bundle_first') || '请关闭整合包后尝试');
                return;
            }
        }

        const previousTab = this._currentTab;
        this._currentTab = tabName;

        // Hide all pages
        document.querySelectorAll('.page').forEach(page => {
            page.classList.remove('active');
            page.style.display = 'none';
        });

        // Show target page
        const targetPage = document.getElementById('page-' + tabName) ||
                           document.querySelector(`.page[data-page="${tabName}"]`);
        if (targetPage) {
            targetPage.style.display = '';
            targetPage.classList.add('active');

            // Page-enter animation
            if (animate) {
                targetPage.classList.remove('page-enter');
                // Force reflow to restart animation
                void targetPage.offsetWidth;
                targetPage.classList.add('page-enter');
                targetPage.addEventListener('animationend', () => {
                    targetPage.classList.remove('page-enter');
                }, { once: true });
            }
        }

        // Update tab button active states
        document.querySelectorAll('.tab-btn').forEach(btn => {
            const btnTab = btn.getAttribute('data-tab') || btn.getAttribute('data-page');
            btn.classList.toggle('active', btnTab === tabName);
        });

        // Persist to store
        if (this._store) {
            this._store.set('current_tab', tabName);
        }

        // Notify listeners
        this._notifyListeners(tabName, previousTab);
    }

    /**
     * Get the currently active tab name.
     * @returns {string|null}
     */
    getCurrentTab() {
        return this._currentTab;
    }

    // ── Callback system ────────────────────────────────────────

    /**
     * Register a callback that fires on every navigation.
     * @param {function(string, string): void} callback - (newTab, oldTab)
     * @returns {function} unsubscribe function
     */
    onNavigate(callback) {
        this._listeners.push(callback);
        return () => {
            this._listeners = this._listeners.filter(cb => cb !== callback);
        };
    }

    /**
     * Notify all registered listeners of a navigation change.
     * @param {string} newTab
     * @param {string|null} oldTab
     * @private
     */
    _notifyListeners(newTab, oldTab) {
        this._listeners.forEach(cb => {
            try {
                cb(newTab, oldTab);
            } catch (e) {
                console.error('[STS2Router] Listener error:', e);
            }
        });
    }

    // ── Tab list management ────────────────────────────────────

    /**
     * Get the list of registered tab names.
     * @returns {string[]}
     */
    getTabs() {
        return [...this._tabs];
    }

    /**
     * Register a new tab at runtime.
     * @param {string} tabName
     */
    addTab(tabName) {
        if (!this._tabs.includes(tabName)) {
            this._tabs.push(tabName);
        }
    }

    /**
     * Remove a tab from the registry.
     * @param {string} tabName
     */
    removeTab(tabName) {
        this._tabs = this._tabs.filter(t => t !== tabName);
    }
}

// ── Export ─────────────────────────────────────────────────────
window.STS2Router = STS2Router;
