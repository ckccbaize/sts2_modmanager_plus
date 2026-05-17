/**
 * STS2App - Main application controller
 *
 * Orchestrates initialization of all subsystems (store, i18n, router, notifications),
 * provides a page module registration system, a global event bus, and DPI scaling.
 */
class STS2App {
    constructor() {
        // Core subsystems (set during init)
        this.store = null;
        this.i18n = null;
        this.router = null;
        this.notifications = null;
        this.api = null;

        // Page modules registry: { moduleName: moduleInstance }
        this._pageModules = {};

        // Event bus listeners: { eventName: [callback, ...] }
        this._eventBus = {};

        // Launch bar state
        this._launchBarExpanded = false;

        // Backend connectivity
        this._backendConnected = false;
    }

    // ── Initialization ─────────────────────────────────────────

    /**
     * Full application bootstrap. Call once on DOMContentLoaded.
     */
    async init() {
        console.log('[STS2App] Initializing...');

        // 1. Initialize store
        this.store = new STS2Store();
        this.store.initDefaults();
        window.STS2Store_instance = this.store; // expose for i18n persistence

        // 1.5 Initialize API client and test backend connection
        await this._initApi();

        // 1.6 Get version from backend and update UI
        await this._initVersion();

        // 2. Initialize i18n with saved language
        const savedLang = this.store.get('language', 'zh_CN');
        this.i18n = new STS2I18n({ defaultLang: savedLang });

        // 3. Apply translations to DOM
        this.i18n.applyTranslations();
        this.i18n.applyPlaceholders();

        // Re-apply when language changes
        document.addEventListener('language-changed', () => {
            this._updateDynamicTexts();
        });

        // 4. Initialize router
        this.router = new STS2Router({
            tabs: ['mods', 'bundles', 'saves', 'nexus', 'downloads', 'settings'],
            defaultTab: 'mods',
            store: this.store,
        });
        this.router.init();

        // Notify page modules on navigation
        this.router.onNavigate((newTab, oldTab) => {
            this._onPageEnter(newTab, oldTab);
        });

        // 4. Initialize store with version control
        this._checkStorageVersion();

        // 5. Initialize notifications
        this.notifications = new STS2Notifications();

        // 6. Load mock data if store is empty
        this._loadMockDataIfEmpty();

        // 7. Initialize each registered page module
        this._initPageModules();

        // 8. Initialize launch bar
        this._initLaunchBar();

        // 8.5. Initialize global drag-and-drop file install
        this._initGlobalDragDrop();

        // 9. Check first run
        if (this.store.get('first_run', true)) {
            this._showFirstRunTutorial();
        }

        // 10. Apply saved DPI scale
        this.applyDpiScale(this.store.get('dpi_scale', 1.0));

        // Fire app-ready event
        this.emit('app-ready');
        console.log('[STS2App] Ready.');
    }

    // ── Page module registration ───────────────────────────────

    /**
     * Register a page module.
     * A module should implement at minimum an `init()` method and optionally `onEnter()` / `onLeave()`.
     *
     * @param {string} name - module identifier (e.g. 'mods', 'saves')
     * @param {object} module - module instance with init(), onEnter(), onLeave()
     */
    registerPage(name, module) {
        this._pageModules[name] = module;
    }

    /**
     * Get a registered page module by name.
     * @param {string} name
     * @returns {object|null}
     */
    getPage(name) {
        return this._pageModules[name] || null;
    }

    /**
     * Initialize all registered page modules.
     * @private
     */
    _initPageModules() {
        for (const [name, module] of Object.entries(this._pageModules)) {
            try {
                if (typeof module.init === 'function') {
                    module.init(this);
                }
                console.log(`[STS2App] Page module "${name}" initialized.`);
            } catch (e) {
                console.error(`[STS2App] Failed to init page module "${name}":`, e);
            }
        }
    }

    /**
     * Called by the router when a page becomes active.
     * @private
     */
    _onPageEnter(newTab, oldTab) {
        // Notify the leaving module
        if (oldTab && this._pageModules[oldTab]) {
            const mod = this._pageModules[oldTab];
            if (typeof mod.onLeave === 'function') {
                try { mod.onLeave(); } catch (e) { console.error(e); }
            }
        }

        // Notify the entering module
        if (this._pageModules[newTab]) {
            const mod = this._pageModules[newTab];
            if (typeof mod.onEnter === 'function') {
                try { mod.onEnter(); } catch (e) { console.error(e); }
            }
        }

        this.emit('page-changed', { from: oldTab, to: newTab });
    }

    // ── Global event bus ───────────────────────────────────────

    /**
     * Subscribe to a global event.
     * @param {string} event
     * @param {function} callback
     * @returns {function} unsubscribe function
     */
    on(event, callback) {
        if (!this._eventBus[event]) this._eventBus[event] = [];
        this._eventBus[event].push(callback);
        return () => {
            this._eventBus[event] = this._eventBus[event].filter(cb => cb !== callback);
        };
    }

    /**
     * Emit a global event with optional data.
     * @param {string} event
     * @param {*} data
     */
    emit(event, data = null) {
        const listeners = this._eventBus[event];
        if (!listeners) return;
        listeners.forEach(cb => {
            try {
                cb(data);
            } catch (e) {
                console.error(`[STS2App] Event "${event}" listener error:`, e);
            }
        });
    }

    /**
     * Remove all listeners for an event (or all events if no name given).
     * @param {string} [event]
     */
    offAll(event) {
        if (event) {
            delete this._eventBus[event];
        } else {
            this._eventBus = {};
        }
    }

    // ── DPI scaling ────────────────────────────────────────────

    /**
     * Apply a DPI scale factor to the document root.
     * @param {number} scale - e.g. 1.0, 1.25, 1.5
     */
    applyDpiScale(scale) {
        document.documentElement.style.setProperty('--dpi-scale', scale);
        document.documentElement.style.fontSize = `${scale * 16}px`;
        this.store.set('dpi_scale', scale);
        this.emit('dpi-changed', scale);
    }

    // ── API connectivity ─────────────────────────────────────

    /**
     * Initialize API client and test backend connection.
     * @private
     */
    async _initApi() {
        if (window.STS2API) {
            this.api = new STS2API();
            try {
                await this.api.health();
                this._backendConnected = true;
                console.log('[STS2App] Backend connected');
                this.emit('backend-connected');
            } catch (e) {
                this._backendConnected = false;
                console.warn('[STS2App] Backend not available, using offline mode');
                this.emit('backend-offline');
                this._showOfflineBanner();
            }
        }
    }

    /**
     * Get version from backend and update UI.
     * @private
     */
    async _initVersion() {
        if (this.api && this._backendConnected) {
            try {
                const version = await this.api.getVersion();
                // 更新页脚版本号
                const versionLabel = document.querySelector('.version-label');
                if (versionLabel) {
                    versionLabel.textContent = version;
                }
                // 保存到 store，供设置页面使用
                this.store.set('app_version', version);
                console.log('[STS2App] Version:', version);
            } catch (e) {
                console.warn('[STS2App] Failed to get version:', e);
            }
        }
    }

    /**
     * Whether the backend is available.
     * @returns {boolean}
     */
    isBackendConnected() {
        return this._backendConnected;
    }

    /**
     * Show a persistent banner indicating offline mode.
     * @private
     */
    _showOfflineBanner() {
        const banner = document.createElement('div');
        banner.id = 'offline-banner';
        banner.style.cssText = `
            background: rgba(234, 179, 8, 0.15); border-bottom: 1px solid rgba(234, 179, 8, 0.3);
            color: #eab308; text-align: center; padding: 4px 12px; font-size: 12px; z-index: 9999;
        `;
        banner.textContent = this.i18n ? (this.i18n.translate('offline_mode') !== 'offline_mode' ? this.i18n.translate('offline_mode') : '离线模式 - 后端未连接，使用本地数据') : '离线模式 - 后端未连接，使用本地数据';
        const appContainer = document.querySelector('.app-container');
        if (appContainer) {
            appContainer.prepend(banner);
        }
    }

    /**
     * Get the current DPI scale.
     * @returns {number}
     */
    getDpiScale() {
        return this.store.get('dpi_scale', 1.0);
    }

    // ── Launch bar ─────────────────────────────────────────────

    /**
     * Set up the launch button and its orbital sub-buttons.
     * @private
     */
    _initLaunchBar() {
        const launchBtn = document.getElementById('launch-btn');
        const subButtons = document.getElementById('launch-sub-buttons');
        if (!launchBtn || !subButtons) return;

        // Toggle orbital expansion
        launchBtn.addEventListener('click', () => {
            this._launchBarExpanded = !this._launchBarExpanded;
            subButtons.classList.toggle('expanded', this._launchBarExpanded);
            launchBtn.classList.toggle('active', this._launchBarExpanded);
        });

        // Sub-button handlers
        subButtons.querySelectorAll('.launch-sub-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const mode = btn.getAttribute('data-launch-mode');
                if (mode) {
                    this.emit('launch-mode-pressed', mode);
                    this._launchBarExpanded = false;
                    subButtons.classList.remove('expanded');
                    launchBtn.classList.remove('active');
                }
            });
        });

        // Close on outside click
        document.addEventListener('click', (e) => {
            if (this._launchBarExpanded && !launchBtn.contains(e.target) && !subButtons.contains(e.target)) {
                this._launchBarExpanded = false;
                subButtons.classList.remove('expanded');
                launchBtn.classList.remove('active');
            }
        });

        // Listen for launch events
        this.on('launch-mode-pressed', (mode) => {
            this._handleLaunch(mode);
        });
    }

    // ── Global drag-and-drop file install ──────────────────────

    /**
     * Set up global drag-and-drop for file installation across all pages.
     * Shows an overlay when files are dragged over the window and routes
     * dropped files to the appropriate page module handler.
     * @private
     */
    _initGlobalDragDrop() {
        let dragCounter = 0;
        let overlay = null;

        const getOverlay = () => {
            if (overlay) return overlay;
            overlay = document.createElement('div');
            overlay.id = 'global-drop-overlay';
            overlay.style.cssText = `
                position: fixed; inset: 0; z-index: 9999;
                background: rgba(10, 15, 22, 0.85);
                backdrop-filter: blur(6px);
                display: none; align-items: center; justify-content: center;
                flex-direction: column; gap: 12px;
                pointer-events: none;
                opacity: 0; transition: opacity 0.2s ease;
            `;
            const icon = document.createElement('div');
            icon.style.cssText = 'font-size: 48px; opacity: 0.7;';
            icon.textContent = '\ud83d\udcc1';
            const text = document.createElement('div');
            text.style.cssText = 'font-size: 16px; color: var(--text-primary); font-weight: 500;';
            text.id = 'global-drop-text';
            text.textContent = '\u62d6\u653e\u6587\u4ef6\u5230\u6b64\u5904';
            const hint = document.createElement('div');
            hint.style.cssText = 'font-size: 12px; color: var(--text-secondary);';
            hint.id = 'global-drop-hint';
            overlay.appendChild(icon);
            overlay.appendChild(text);
            overlay.appendChild(hint);
            document.body.appendChild(overlay);
            return overlay;
        };

        const showOverlay = () => {
            const ov = getOverlay();
            const currentTab = this.router ? this.router.getCurrentTab() : 'mods';
            const textEl = document.getElementById('global-drop-text');
            const hintEl = document.getElementById('global-drop-hint');
            const labels = {
                mods:       { text: '\u62d6\u653e .zip \u5b89\u88c5\u6a21\u7ec4', hint: '\u652f\u6301\u5355\u4e2a\u6216\u591a\u4e2a .zip \u6587\u4ef6' },
                bundles:    { text: '\u62d6\u653e .zip \u5bfc\u5165\u6574\u5408\u5305', hint: '\u652f\u6301 .zip \u6574\u5408\u5305\u6587\u4ef6' },
                saves:      { text: '\u62d6\u653e .zip \u5bfc\u5165\u5b58\u6863', hint: '\u652f\u6301 .zip \u5b58\u6863\u6587\u4ef6' },
            };
            const info = labels[currentTab] || labels.mods;
            if (textEl) textEl.textContent = info.text;
            if (hintEl) hintEl.textContent = info.hint;
            ov.style.display = 'flex';
            requestAnimationFrame(() => { ov.style.opacity = '1'; });
        };

        const hideOverlay = () => {
            if (!overlay) return;
            overlay.style.opacity = '0';
            setTimeout(() => { if (overlay) overlay.style.display = 'none'; }, 200);
        };

        document.addEventListener('dragenter', (e) => {
            e.preventDefault();
            if (!e.dataTransfer || !e.dataTransfer.types.includes('Files')) return;
            dragCounter++;
            if (dragCounter === 1) showOverlay();
        });

        document.addEventListener('dragleave', (e) => {
            e.preventDefault();
            dragCounter--;
            if (dragCounter <= 0) {
                dragCounter = 0;
                hideOverlay();
            }
        });

        document.addEventListener('dragover', (e) => {
            e.preventDefault();
            if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
        });

        document.addEventListener('drop', (e) => {
            e.preventDefault();
            dragCounter = 0;
            hideOverlay();
            if (!e.dataTransfer || !e.dataTransfer.files.length) return;

            const files = Array.from(e.dataTransfer.files);
            const currentTab = this.router ? this.router.getCurrentTab() : 'mods';

            // Route files to the appropriate handler
            switch (currentTab) {
                case 'mods': {
                    const modModule = this.getPage('mods');
                    if (modModule && typeof modModule._handleFileDrop === 'function') {
                        modModule._handleFileDrop({ dataTransfer: e.dataTransfer });
                    } else if (modModule && typeof modModule.installMod === 'function') {
                        const zips = files.filter(f => f.name.toLowerCase().endsWith('.zip'));
                        zips.forEach(f => modModule.installMod(f));
                    }
                    break;
                }
                case 'saves': {
                    const saveModule = this.getPage('saves');
                    if (saveModule && typeof saveModule.importSaveFromFiles === 'function') {
                        saveModule.importSaveFromFiles(files);
                    } else if (saveModule && typeof saveModule.importSave === 'function') {
                        const zips = files.filter(f => f.name.toLowerCase().endsWith('.zip'));
                        if (zips.length) saveModule.importSave(zips[0]);
                    }
                    break;
                }
                case 'bundles': {
                    console.log('[STS2App] Drop on bundles tab, calling importBundleFromFiles');
                    const bundleModule = this.getPage('bundles');
                    console.log('[STS2App] bundleModule:', bundleModule);
                    if (bundleModule && typeof bundleModule.importBundleFromFiles === 'function') {
                        console.log('[STS2App] Calling bundleModule.importBundleFromFiles with', files.length, 'files');
                        bundleModule.importBundleFromFiles(files);
                    } else if (bundleModule && typeof bundleModule.importBundle === 'function') {
                        const zips = files.filter(f => f.name.toLowerCase().endsWith('.zip'));
                        if (zips.length) bundleModule.importBundle(zips[0]);
                    } else {
                        console.warn('[STS2App] bundles module not found or missing methods');
                    }
                    break;
                }
                default:
                    // On other pages, try to install as mod if it's a zip
                    const modFallback = this.getPage('mods');
                    if (modFallback && typeof modFallback.installMod === 'function') {
                        const zips = files.filter(f => f.name.toLowerCase().endsWith('.zip'));
                        if (zips.length) {
                            zips.forEach(f => modFallback.installMod(f));
                        }
                    }
                    break;
            }
        });
    }

    /**
     * Handle a game launch request.
     * @private
     * @param {string} mode - 'vanilla', 'modded', or 'multiplayer'
     */
    _handleLaunch(mode) {
        const appIds = {
            vanilla: '2868840',
            modded: '2868840',
            multiplayer: '2868840',
        };
        const appId = appIds[mode] || '2868840';
        this.notifications.show(
            `Launching Slay the Spire 2 (${mode})...`,
            'info',
            2000
        );
        // In a real environment this would call: window.open(`steam://launch/${appId}/dialog`)
        console.log(`[STS2App] Launch: steam://launch/${appId}/dialog`);
    }

    // ── First-run tutorial ─────────────────────────────────────

    /**
     * Show a first-run welcome message / tutorial.
     * @private
     */
    _showFirstRunTutorial() {
        // Delay slightly so the UI has time to render
        setTimeout(() => {
            this.notifications.show(
                this.i18n.translate('welcome_message') !== 'welcome_message'
                    ? this.i18n.translate('welcome_message')
                    : 'Welcome to STS2 Mod Manager!',
                'info',
                5000
            );
            this.store.set('first_run', false);
        }, 800);
    }

    // ── Mock data ──────────────────────────────────────────────

    /**
     * Check storage version and clear old data if version mismatch.
     * This prevents stale localStorage data from causing issues after structural changes.
     * @private
     */
    _checkStorageVersion() {
        const STORAGE_VERSION = 1;
        const currentVersion = this.store.get('storage_version', 0);
        if (currentVersion !== STORAGE_VERSION) {
            console.log(`[STS2App] Storage version mismatch (${currentVersion} -> ${STORAGE_VERSION}), clearing old data...`);
            this.store.clear();
            this.store.set('storage_version', STORAGE_VERSION);
        }
    }

    /**
     * Load mock/demo data into the store if it appears to be empty.
     * @private
     */
    _loadMockDataIfEmpty() {
        // Load mods from MOCK_MODS data file
        if (!this.store.has('mods_data') || this.store.get('mods_data').length === 0) {
            if (window.MOCK_MODS && window.MOCK_MODS.length > 0) {
                this.store.set('mods_data', window.MOCK_MODS);
                // Enable first 3 mods by default
                const defaultEnabled = window.MOCK_MODS.slice(0, 3).map(m => m.id);
                this.store.set('enabled_mods', defaultEnabled);
            }
        }

        // Load bundles from MOCK_BUNDLES data file
        if (!this.store.has('bundles_data') || this.store.get('bundles_data').length === 0) {
            if (window.MOCK_BUNDLES && window.MOCK_BUNDLES.length > 0) {
                this.store.set('bundles_data', window.MOCK_BUNDLES);
            }
        }

        // Load saves from MOCK_SAVES data file
        if (!this.store.has('saves_data') || this.store.get('saves_data').length === 0) {
            if (window.MOCK_SAVES && window.MOCK_SAVES.length > 0) {
                this.store.set('saves_data', window.MOCK_SAVES);
            }
        }

        // Initialize empty collections
        if (!this.store.has('downloads_data')) this.store.set('downloads_data', []);
        if (!this.store.has('download_history')) this.store.set('download_history', []);
        if (!this.store.has('tag_data')) this.store.set('tag_data', {});
        if (!this.store.has('mod_boxes')) this.store.set('mod_boxes', []);
        if (!this.store.has('mod_notes')) this.store.set('mod_notes', {});

        console.log('[STS2App] Mock data loaded.');
    }

    // ── Dynamic text updates ───────────────────────────────────

    /**
     * Re-translate any dynamic text that is not covered by data-i18n attributes.
     * @private
     */
    _updateDynamicTexts() {
        this.emit('language-applied');
        // Page modules can listen for 'language-applied' to re-render their dynamic content
    }

    // ── Cleanup ────────────────────────────────────────────────

    /**
     * Tear down all modules and event listeners.
     */
    destroy() {
        for (const [name, module] of Object.entries(this._pageModules)) {
            if (typeof module.destroy === 'function') {
                try { module.destroy(); } catch (e) { console.error(e); }
            }
        }
        this._pageModules = {};
        this.offAll();
        console.log('[STS2App] Destroyed.');
    }
}

// ── Export ─────────────────────────────────────────────────────
window.STS2App = STS2App;

// ── Bootstrap ────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', async () => {
    const app = new STS2App();

    // Register all page modules (order doesn't matter, just needs to happen before init)
    if (window.STS2Mods) app.registerPage('mods', window.STS2Mods);
    if (window.STS2Bundles) app.registerPage('bundles', window.STS2Bundles);
    if (window.STS2Saves) app.registerPage('saves', window.STS2Saves);
    if (window.STS2Nexus) app.registerPage('nexus', window.STS2Nexus);
    if (window.STS2Downloads) app.registerPage('downloads', window.STS2Downloads);
    if (window.STS2Settings) app.registerPage('settings', window.STS2Settings);

    // Initialize the app (registers modules, loads data, sets up router)
    await app.init();

    // Initialize Tesla launch bar
    if (window.STS2Launch) {
        window.STS2Launch.init(app);
    }

    // Initialize tutorial system
    if (window.STS2Tutorial) {
        window.STS2Tutorial.init(app);
    }

    // Initialize animations
    if (window.STS2Animations) {
        window.STS2Animations.init(app);
    }

    // Expose app globally for debugging
    window.app = app;
});
