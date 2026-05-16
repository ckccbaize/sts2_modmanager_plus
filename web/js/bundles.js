/**
 * STS2Bundles - Bundle (Mod Pack) management module
 *
 * Manages mod bundles: load, display, enable/disable, import/export, and updates.
 * Data persisted to localStorage under sts2mm_bundles_data.
 * Falls back to window.MOCK_BUNDLES on first run.
 */
const STS2Bundles = {

    // ── State ─────────────────────────────────────────────────────
    bundles: [],
    selected_bundle_id: null,
    active_bundle: null,
    _app: null,
    _initialized: false,

    // ── Lifecycle ─────────────────────────────────────────────────

    /**
     * Called by STS2App during page module initialization.
     * @param {STS2App} app
     */
    init(app) {
        this._app = app;
        this._bindEvents();
        this._initialized = true;

        // Restore last selected bundle and preset from localStorage
        this._restoreState();

        // Load data then render — loadBundles is async
        this.loadBundles().then(() => this.updateBundlesUI()).catch(e => {
            console.warn('[STS2Bundles] init loadBundles failed:', e);
            this.updateBundlesUI();
        });
        console.log('[STS2Bundles] Initialized.');
    },

    /**
     * Restore last selected bundle and preset from localStorage.
     * @private
     */
    _restoreState() {
        const store = this._app.store;
        if (!store) return;

        // Restore selected bundle
        const lastSelectedBundle = store.get('last_selected_bundle', null);
        if (lastSelectedBundle) {
            this.selected_bundle_id = lastSelectedBundle;
        }

        // Restore active bundle (already handled in loadBundles)
        const activeBundle = store.get('active_bundle', null);
        if (activeBundle) {
            this.active_bundle = activeBundle;
        }
    },

    /**
     * Save current selected bundle to localStorage.
     * @private
     */
    _saveSelectedBundle(id) {
        const store = this._app.store;
        if (!store) return;
        store.set('last_selected_bundle', id);
    },

    /**
     * Save current selected preset to localStorage.
     * @private
     */
    _saveSelectedPreset(bundleId, presetName) {
        const store = this._app.store;
        if (!store) return;
        store.set(`bundle_${bundleId}_selected_preset`, presetName);
    },

    /** Called when the bundles tab becomes active. */
    onEnter() {
        // Reload from API on each entry to ensure fresh data
        this.loadBundles().then(() => this.updateBundlesUI()).catch(e => {
            console.warn('[STS2Bundles] onEnter loadBundles failed:', e);
            this.updateBundlesUI();
        });
    },

    /** Called when leaving the bundles tab. */
    onLeave() {
        // no-op
    },

    // ── Event binding ─────────────────────────────────────────────

    /** @private */
    _bindEvents() {
        // Import bundle button
        const importBtn = document.getElementById('btn-import-bundle');
        if (importBtn) {
            importBtn.addEventListener('click', () => this.importBundle());
        }

        // Import by URL button
        const urlBtn = document.getElementById('btn-bundle-url');
        if (urlBtn) {
            urlBtn.addEventListener('click', () => this.importBundleByUrl());
        }

        // Export bundle button
        const exportBtn = document.getElementById('btn-export-bundle');
        if (exportBtn) {
            exportBtn.addEventListener('click', () => {
                // Export current enabled mods as new bundle
                this.exportBundle();
            });
        }

        // Re-render on language change
        this._app.on('language-applied', () => {
            if (this._initialized) this.updateBundlesUI();
        });
    },

    // ── Data ──────────────────────────────────────────────────────

    /** Load bundles from store, falling back to MOCK_BUNDLES. When backend is connected, API data takes priority. */
    async loadBundles() {
        // Try backend API first
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.getBundles();
                if (resp && resp.bundles) {
                    this.bundles = resp.bundles;
                    // Save active_bundle from API response
                    if (resp.active_bundle) {
                        this.active_bundle = resp.active_bundle;
                        this._app.store.set('active_bundle', resp.active_bundle);
                        console.log('[STS2Bundles] Active bundle:', resp.active_bundle);
                    }
                    this._saveBundles();
                    return;
                }
            } catch (e) {
                console.warn('[STS2Bundles] API loadBundles failed:', e);
            }
        }

        // Fallback to local store / mock data
        const store = this._app.store;
        if (store.has('bundles_data') && store.get('bundles_data').length > 0) {
            this.bundles = store.get('bundles_data');
            console.log('[STS2Bundles] Loaded from store:', this.bundles.length, 'bundles');
            console.log('[STS2Bundles] First bundle mod_names:', this.bundles[0]?.mod_names);
            // If stored data has no mod_names, fall back to mock data
            const firstBundle = this.bundles[0];
            if (firstBundle && (!firstBundle.mod_names || firstBundle.mod_names.length === 0)) {
                console.log('[STS2Bundles] Store data missing mod_names, using mock data');
                if (typeof window.MOCK_BUNDLES !== 'undefined') {
                    this.bundles = STS2Utils.deepClone(window.MOCK_BUNDLES);
                    store.set('bundles_data', this.bundles);
                }
            }
        } else if (typeof window.MOCK_BUNDLES !== 'undefined') {
            this.bundles = STS2Utils.deepClone(window.MOCK_BUNDLES);
            store.set('bundles_data', this.bundles);
            console.log('[STS2Bundles] Loaded mock data:', this.bundles.length, 'bundles');
        } else {
            this.bundles = [];
        }
    },

    /** Persist current bundles to store. */
    _saveBundles() {
        // Try backend first if connected
        if (this._app && this._app.isBackendConnected && this._app.isBackendConnected()) {
            for (const bundle of this.bundles) {
                this._app.api.saveBundle(bundle.id, bundle).catch(e => {
                    console.warn('[STS2Bundles] Backend save failed:', e);
                });
            }
        }
        // Always save to localStorage as cache
        this._app.store.set('bundles_data', this.bundles);
    },

    // ── Rendering ─────────────────────────────────────────────────

    /** Full UI refresh: both list and details. */
    updateBundlesUI() {
        this.renderBundleList();
        if (this.selected_bundle_id) {
            this.showBundleDetails(this.selected_bundle_id);
        }
    },

    /** Render the left bundle list panel. */
    renderBundleList() {
        const container = document.getElementById('bundle-list');
        if (!container) return;

        const t = (key) => this._app.i18n.translate(key);

        // Clear existing items to prevent duplication
        container.innerHTML = '';

        if (this.bundles.length === 0) {
            container.innerHTML = `
                <div class="bundle-empty">
                    <div class="bundle-empty-icon">📦</div>
                    <div class="bundle-empty-title">${t('no_bundles')}</div>
                    <div class="bundle-empty-desc">${t('import_bundle_hint')}</div>
                </div>
            `;
            return;
        }

        this.bundles.forEach(bundle => {
            const el = document.createElement('div');
            el.className = 'bundle-item';
            if (bundle.id === this.selected_bundle_id) el.classList.add('selected');
            if (bundle.id === this.active_bundle) el.classList.add('active');

            const modCount = (bundle.mods || bundle.mod_names || []).length;

            el.innerHTML = `
                <div class="bundle-item-info">
                    <div class="bundle-item-name">${STS2Utils.escapeHtml(bundle.name)}</div>
                    <div class="bundle-item-version">${STS2Utils.escapeHtml(bundle.version)}</div>
                </div>
                <span class="bundle-item-mod-count">${modCount} ${t('mods')}</span>
            `;

            el.addEventListener('click', () => this.showBundleDetails(bundle.id));
            container.appendChild(el);
        });
    },

    /**
     * Show bundle details in the right panel.
     * @param {string} id
     */
    showBundleDetails(id) {
        this.selected_bundle_id = id;
        this._saveSelectedBundle(id);

        const bundle = this.bundles.find(b => b.id === id);
        if (!bundle) return;

        console.log('[STS2Bundles] showBundleDetails bundle:', bundle);
        console.log('[STS2Bundles] showBundleDetails mod_names:', bundle.mod_names);

        const panel = document.getElementById('bundle-details');
        if (!panel) return;

        const t = (key) => this._app.i18n.translate(key);
        const body = panel.querySelector('.panel-body');
        if (!body) return;

        // Support both formats: mod_names (string[]) and mods (object[])
        const rawMods = bundle.mod_names || bundle.mods || [];
        const modNames = rawMods.map(m => typeof m === 'string' ? m : m.id);
        const presets = bundle.presets || {};
        const presetKeys = Object.keys(presets);

        // 计算所有预设的并集（所有可能启用的模组）
        const allEnabledMods = new Set();
        presetKeys.forEach(key => {
            const presetMods = presets[key] || [];
            presetMods.forEach(mod => {
                const modName = typeof mod === 'string' ? mod : (mod.id || mod.name || String(mod));
                allEnabledMods.add(modName);
            });
        });
        const totalEnabledMods = allEnabledMods.size;

        const isActive = this.active_bundle === id;

        // 优化：使用 DocumentFragment 渲染大量模组，避免一次性innerHTML导致页面卡顿
        // 同时限制最大显示数量，超过则显示"更多"提示
        const MAX_VISIBLE_MODS = 50;
        const visibleModCount = Math.min(modNames.length, MAX_VISIBLE_MODS);
        const hasMoreMods = modNames.length > MAX_VISIBLE_MODS;

        // Build mods list using DocumentFragment for better performance
        const modsFragment = document.createDocumentFragment();
        for (let i = 0; i < visibleModCount; i++) {
            const name = modNames[i];
            const div = document.createElement('div');
            div.className = 'bundle-mod-item';
            div.innerHTML = `
                <span class="bundle-mod-check">✓</span>
                <span>${STS2Utils.escapeHtml(name)}</span>
            `;
            modsFragment.appendChild(div);
        }

        // Build presets HTML with optimization for many presets/mods
        let presetsHtml = '';
        let tabsFragment = null;
        let badgesContainer = null;
        if (presetKeys.length > 0) {
            // Get saved selected preset (from store or default to first)
            const savedSelectedPreset = this._app.store.get(`bundle_${id}_selected_preset`, null);
            const defaultSelectedPreset = savedSelectedPreset || presetKeys[0];

            // Build Steam-style preset tabs with horizontal scroll for many presets
            tabsFragment = document.createDocumentFragment();
            presetKeys.forEach(key => {
                const btn = document.createElement('button');
                btn.className = `bundle-preset-tab ${key === defaultSelectedPreset ? 'active' : ''}`;
                btn.dataset.presetName = STS2Utils.escapeHtml(key);
                btn.textContent = STS2Utils.escapeHtml(key);
                tabsFragment.appendChild(btn);
            });

            const selectedPresetMods = presets[defaultSelectedPreset] || [];
            const MAX_VISIBLE_PRESET_MODS = 30;
            const visiblePresetModCount = Math.min(selectedPresetMods.length, MAX_VISIBLE_PRESET_MODS);
            const hasMorePresetMods = selectedPresetMods.length > MAX_VISIBLE_PRESET_MODS;

            // Build preset mods badges using DocumentFragment
            badgesContainer = document.createElement('div');
            badgesContainer.className = 'bundle-preset-mods';
            badgesContainer.id = 'bundle-preset-mods';

            if (selectedPresetMods.length === 0) {
                badgesContainer.innerHTML = `<span class="bundle-preset-empty">${t('no_enabled_mods')}</span>`;
            } else {
                for (let i = 0; i < visiblePresetModCount; i++) {
                    const name = selectedPresetMods[i];
                    const badge = document.createElement('span');
                    badge.className = 'badge badge-preset';
                    badge.style.animationDelay = `${i * 20}ms`;
                    badge.textContent = STS2Utils.escapeHtml(name);
                    badgesContainer.appendChild(badge);
                }
                if (hasMorePresetMods) {
                    const moreBadge = document.createElement('span');
                    moreBadge.className = 'badge badge-preset';
                    moreBadge.textContent = `+${selectedPresetMods.length - MAX_VISIBLE_PRESET_MODS} more`;
                    moreBadge.style.backgroundColor = 'rgba(102, 192, 249, 0.05)';
                    moreBadge.style.borderStyle = 'dashed';
                    badgesContainer.appendChild(moreBadge);
                }
            }

            presetsHtml = `
                <div class="bundle-presets">
                    <div class="bundle-presets-header" id="bundle-presets-toggle">
                        <span class="bundle-presets-title">${t('presets')}</span>
                        <span class="bundle-presets-arrow" id="bundle-presets-arrow">▼</span>
                        <button class="btn btn-sm btn-ghost bundle-presets-edit-btn" id="btn-edit-preset">
                            <span class="btn-icon-text">${t('edit')}</span>
                        </button>
                    </div>
                    <div class="bundle-presets-content" id="bundle-presets-content">
                        <div class="bundle-presets-tabs" id="bundle-presets-tabs"></div>
                        <div class="bundle-preset-mods-wrapper">
                        </div>
                    </div>
                </div>
            `;
        }

        const createdDate = bundle.created_date ? STS2Utils.formatDate(bundle.created_date) : '--';

        // Build the main HTML structure (without mods list content)
        body.innerHTML = `
            <div class="bundle-details">
                <div class="bundle-info-header">
                    <div class="bundle-name">${STS2Utils.escapeHtml(bundle.name)}</div>
                    <div class="bundle-version">${STS2Utils.escapeHtml(bundle.version)}</div>
                </div>

                <div class="bundle-info-row">
                    <span class="info-item">${this._app.i18n.translate_fmt('author', [bundle.author])}</span>
                    <span class="info-item"><span class="info-label">${t('created_date')}</span> <span class="info-value">${createdDate}</span></span>
                    <span class="info-item"><span class="info-label">${t('mod_count')}</span> <span class="info-value">${modNames.length}</span></span>
                    <span class="info-item"><span class="info-label">${t('presets')}</span> <span class="info-value">${presetKeys.length}</span></span>
                    <span class="info-item"><span class="info-label">${t('enabled_mods') || '启用模组'}</span> <span class="info-value">${totalEnabledMods}</span></span>
                </div>

                <div class="bundle-description">${STS2Utils.escapeHtml(bundle.description)}</div>

                <div class="bundle-mods-list">
                    <div class="bundle-mods-list-title" id="bundle-mods-toggle">
                        <span>${t('included_mods')}</span>
                        <span class="bundle-mods-count">(${modNames.length})</span>
                        <span class="bundle-mods-arrow" id="bundle-mods-arrow">▼</span>
                    </div>
                    <div class="bundle-mods-content" id="bundle-mods-content"></div>
                </div>

                ${presetsHtml}

                <div class="bundle-actions">
                    ${isActive
                        ? `<button class="btn btn-ghost" id="btn-bundle-disable">${t('disable_bundle')}</button>`
                        : `<button class="btn btn-primary" id="btn-bundle-enable">${t('enable_bundle')}</button>`
                    }
                    <button class="btn btn-ghost" id="btn-bundle-check-update">${t('check_update')}</button>
                    <button class="btn btn-danger" id="btn-bundle-delete">${t('delete')}</button>
                </div>
            </div>
        `;

        // Now populate the mods content using DocumentFragment for better performance
        const modsContent = document.getElementById('bundle-mods-content');
        if (modsContent) {
            if (modNames.length === 0) {
                modsContent.innerHTML = `<div class="bundle-mods-empty">${t('no_mods_installed')}</div>`;
            } else {
                modsContent.appendChild(modsFragment);
                if (hasMoreMods) {
                    const moreEl = document.createElement('div');
                    moreEl.className = 'bundle-mod-item';
                    moreEl.style.backgroundColor = 'rgba(42, 71, 94, 0.1)';
                    moreEl.style.borderStyle = 'dashed';
                    moreEl.innerHTML = `<span style="color: var(--text-muted); font-style: italic;">... ${modNames.length - MAX_VISIBLE_MODS} more mods (use edit to view all)</span>`;
                    modsContent.appendChild(moreEl);
                }
            }
        }

        // Populate preset tabs container if presets exist
        if (presetKeys.length > 0) {
            const tabsContainer = document.getElementById('bundle-presets-tabs');
            if (tabsContainer) {
                tabsContainer.appendChild(tabsFragment);
            }
            // Add the badges container
            const modsWrapper = document.querySelector('.bundle-preset-mods-wrapper');
            if (modsWrapper && badgesContainer) {
                modsWrapper.appendChild(badgesContainer);
            }
        }

        // Wire up collapse toggle for included mods with smooth animation
        const modsToggle = document.getElementById('bundle-mods-toggle');
        const modsContentEl = document.getElementById('bundle-mods-content');
        const modsArrow = document.getElementById('bundle-mods-arrow');
        if (modsToggle && modsContentEl) {
            modsToggle.addEventListener('click', () => {
                const isCollapsed = modsContentEl.classList.toggle('collapsed');
                if (modsArrow) modsArrow.classList.toggle('collapsed', isCollapsed);
            });
        }

        // Wire up action buttons
        const enableBtn = document.getElementById('btn-bundle-enable');
        if (enableBtn) enableBtn.addEventListener('click', () => this.enableBundle(id));

        const disableBtn = document.getElementById('btn-bundle-disable');
        if (disableBtn) disableBtn.addEventListener('click', () => this.disableBundle(id));

        const checkBtn = document.getElementById('btn-bundle-check-update');
        if (checkBtn) checkBtn.addEventListener('click', () => this.checkUpdate(id));

        const deleteBtn = document.getElementById('btn-bundle-delete');
        if (deleteBtn) deleteBtn.addEventListener('click', () => this.deleteBundle(id));

        // Wire up collapse toggle for presets
        const presetsToggle = document.getElementById('bundle-presets-toggle');
        const presetsContent = document.getElementById('bundle-presets-content');
        const presetsArrow = document.getElementById('bundle-presets-arrow');
        if (presetsToggle && presetsContent) {
            presetsToggle.addEventListener('click', (e) => {
                // Don't toggle if clicking the edit button
                if (e.target.closest('#btn-edit-preset')) return;
                const isCollapsed = presetsContent.classList.toggle('collapsed');
                if (presetsArrow) presetsArrow.classList.toggle('collapsed', isCollapsed);
            });
        }

        // Wire up preset tab clicks with smooth animation
        const presetTabs = document.querySelectorAll('.bundle-preset-tab');
        const presetModsContent = document.getElementById('bundle-preset-mods');
        const currentBundleId = id; // Capture for closure
        if (presetTabs.length > 0 && presetModsContent) {
            presetTabs.forEach(tab => {
                tab.addEventListener('click', async () => {
                    // Update active tab
                    presetTabs.forEach(t => t.classList.remove('active'));
                    tab.classList.add('active');

                    // Get selected preset name from data attribute
                    const selectedPresetName = tab.dataset.presetName;
                    const selectedPresetMods = presets[selectedPresetName] || [];

                    // Save selected preset to store (for enable bundle later and persistence)
                    this._saveSelectedPreset(currentBundleId, selectedPresetName);

                    // Fade out effect
                    presetModsContent.classList.add('loading');

                    // 如果有活跃的整合包且后端已连接，调用后端 API 应用预设
                    const activeBundle = this._app.store.get('active_bundle', null);
                    if (activeBundle === currentBundleId && this._app.isBackendConnected && this._app.isBackendConnected()) {
                        try {
                            const result = await this._app.api.applyBundlePreset(currentBundleId, selectedPresetName);
                            // 后端返回格式：{ success: true, message: "...", ... }（不是 { data: {...} }）
                            if (result && result.success) {
                                this._app.notifications.show(this._app.i18n.translate_fmt('preset_applied', [selectedPresetName]), 'success');
                            } else {
                                const msg = result?.message || 'Unknown error';
                                this._app.notifications.show(this._app.i18n.translate_fmt('preset_apply_failed', [msg]), 'warning');
                            }
                        } catch (e) {
                            console.warn('[STS2Bundles] Failed to apply preset:', e);
                            this._app.notifications.show(this._app.i18n.translate_fmt('preset_apply_failed', [e.message]), 'error');
                        }
                    }

                    // Use DocumentFragment for better performance with many mods
                    setTimeout(() => {
                        // Clear existing content
                        presetModsContent.innerHTML = '';

                        const MAX_VISIBLE_PRESET_MODS = 30;
                        const visibleCount = Math.min(selectedPresetMods.length, MAX_VISIBLE_PRESET_MODS);
                        const hasMore = selectedPresetMods.length > MAX_VISIBLE_PRESET_MODS;

                        if (selectedPresetMods.length === 0) {
                            presetModsContent.innerHTML = `<span class="bundle-preset-empty">${t('no_enabled_mods')}</span>`;
                        } else {
                            // Create badges using DocumentFragment
                            const fragment = document.createDocumentFragment();
                            for (let i = 0; i < visibleCount; i++) {
                                const name = selectedPresetMods[i];
                                const badge = document.createElement('span');
                                badge.className = 'badge badge-preset';
                                badge.style.animationDelay = `${i * 20}ms`;
                                badge.textContent = STS2Utils.escapeHtml(name);
                                fragment.appendChild(badge);
                            }
                            if (hasMore) {
                                const moreBadge = document.createElement('span');
                                moreBadge.className = 'badge badge-preset';
                                moreBadge.textContent = `+${selectedPresetMods.length - MAX_VISIBLE_PRESET_MODS} more`;
                                moreBadge.style.backgroundColor = 'rgba(102, 192, 249, 0.05)';
                                moreBadge.style.borderStyle = 'dashed';
                                fragment.appendChild(moreBadge);
                            }
                            presetModsContent.appendChild(fragment);
                        }

                        // Fade in effect
                        presetModsContent.classList.remove('loading');
                    }, 150);
                });
            });
        }

        // Wire up edit preset button
        const editPresetBtn = document.getElementById('btn-edit-preset');
        if (editPresetBtn) {
            editPresetBtn.addEventListener('click', () => this._showEditPresetsModal(id));
        }

        // Update list selection highlight
        this.renderBundleList();
    },

    // ── Actions ───────────────────────────────────────────────────

    /**
     * Enable a bundle: sets it as active and applies its mod config.
     * Shows a confirmation dialog if another bundle is already active.
     * @param {string} id
     */
    async enableBundle(id) {
        const bundle = this.bundles.find(b => b.id === id);
        if (!bundle) return;

        const t = (key) => this._app.i18n.translate(key);

        // If this bundle is already active, do nothing
        if (this.active_bundle === id) {
            this._app.notifications.show(
                t('bundle_already_active') || '整合包已处于激活状态',
                'info'
            );
            return;
        }

        // If another bundle is already active, show alert and block
        if (this.active_bundle && this.active_bundle !== id) {
            const currentBundle = this.bundles.find(b => b.id === this.active_bundle);
            const curName = currentBundle ? currentBundle.name : '?';
            alert((t('close_bundle_first') || '请先关闭当前整合包「{name}」后再尝试启用其他整合包').replace('{name}', curName));
            return;
        }

        await this._doEnableBundle(id);
    },

    /**
     * Show a dialog when enabling a bundle while another is active.
     * @param {object} currentBundle
     * @param {object} newBundle
     * @private
     */
    _showSelectBundleDialog(currentBundle, newBundle) {
        const t = (key) => this._app.i18n.translate(key);
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        const curName = currentBundle ? STS2Utils.escapeHtml(currentBundle.name) : '?';
        const curVer = currentBundle ? (currentBundle.version || '') : '';
        const newName = STS2Utils.escapeHtml(newBundle.name);
        const newVer = newBundle.version || '?';
        overlay.innerHTML = `
            <div class="modal" style="max-width:420px">
                <div class="modal__header">
                    <span class="modal__title">${t('select_active_bundle') || '选择激活整合包'}</span>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="modal__body" style="padding:var(--sp-lg) var(--sp-xl)">
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:12px">
                        ${(t('select_bundle_desc') || '当前已有整合包「{name}」处于激活状态，是否替换？').replace('{name}', curName)}
                    </div>
                    <div style="display:flex;gap:8px;font-size:12px;margin-bottom:8px">
                        <div style="flex:1;padding:8px;background:var(--bg-surface);border-radius:var(--radius-md)">
                            <div style="color:var(--text-muted);margin-bottom:4px">当前激活</div>
                            <div style="color:var(--text-primary)">${curName}</div>
                            <div style="color:var(--accent)">${curVer}</div>
                        </div>
                        <div style="flex:1;padding:8px;background:var(--bg-surface);border-radius:var(--radius-md)">
                            <div style="color:var(--text-muted);margin-bottom:4px">新整合包</div>
                            <div style="color:var(--text-primary)">${newName}</div>
                            <div style="color:var(--success)">${newVer}</div>
                        </div>
                    </div>
                </div>
                <div class="modal__footer" style="gap:8px">
                    <button class="btn btn-primary sb-replace">${t('replace_bundle') || '替换当前整合包'}</button>
                    <button class="btn btn-ghost sb-cancel">${t('cancel') || '取消'}</button>
                </div>
            </div>`;

        const close = () => overlay.remove();
        overlay.querySelector('.modal__close').addEventListener('click', close);
        overlay.querySelector('.sb-cancel').addEventListener('click', close);
        overlay.querySelector('.sb-replace').addEventListener('click', async () => {
            close();
            if (this.active_bundle) {
                await this.disableBundle(this.active_bundle);
            }
            await this._doEnableBundle(newBundle.id);
        });

        document.getElementById('modal-container').appendChild(overlay);
    },

    /**
     * Actually enable a bundle (internal, no conflict check).
     * @param {string} id
     * @private
     */
    async _doEnableBundle(id) {
        const bundle = this.bundles.find(b => b.id === id);
        if (!bundle) return;

        // Get the currently selected preset (from store or default to first)
        const selectedPreset = this._app.store.get(`bundle_${id}_selected_preset`, null);
        const t = (key) => this._app.i18n.translate(key);

        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                await this._app.api.enableBundle(id, selectedPreset);
                // API 调用成功，显示成功通知
                this._app.notifications.show(
                    `${t('bundle_enabled') !== 'bundle_enabled' ? t('bundle_enabled') : 'Bundle enabled'}: ${bundle.name}`,
                    'success'
                );
            } catch (e) {
                console.warn('[STS2Bundles] API enableBundle failed:', e);
                // API 调用失败，显示错误通知
                this._app.notifications.show(
                    `${t('bundle_enable_failed') || '启用整合包失败'}: ${e.message}`,
                    'error'
                );
                return; // 不继续执行后续 UI 更新
            }
        } else {
            // 后端未连接，显示提示
            this._app.notifications.show(
                t('backend_not_connected') || '后端未连接',
                'warning'
            );
        }

        this.active_bundle = id;
        this._app.store.set('active_bundle', id);
        this._app.emit('bundle-enabled', bundle);

        this.updateBundlesUI();
    },

    /**
     * Disable the currently active bundle.
     * @param {string} id
     */
    async disableBundle(id) {
        const t = (key) => this._app.i18n.translate(key);

        // Notify backend API when connected
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                await this._app.api.disableBundle(id);
            } catch (e) {
                console.warn('[STS2Bundles] API disableBundle failed:', e);
                this._app.notifications.show(
                    `${t('bundle_disable_failed') || '禁用整合包失败'}: ${e.message}`,
                    'error'
                );
                return;
            }
        }

        this.active_bundle = null;
        this._app.store.set('active_bundle', null);
        this._app.emit('bundle-disabled', { id });

        const bundle = this.bundles.find(b => b.id === id);
        this._app.notifications.show(
            `${t('bundle_disabled') !== 'bundle_disabled' ? t('bundle_disabled') : 'Bundle disabled'}${bundle ? ': ' + bundle.name : ''}`,
            'info'
        );

        this.updateBundlesUI();
    },

    /**
     * Delete a bundle with confirmation modal.
     * @param {string} id
     */
    deleteBundle(id) {
        const bundle = this.bundles.find(b => b.id === id);
        if (!bundle) return;

        const t = (key) => this._app.i18n.translate(key);
        this._showConfirmModal(
            t('confirm_delete_bundle') !== 'confirm_delete_bundle' ? t('confirm_delete_bundle') : 'Delete Bundle',
            `${t('confirm_delete_bundle_msg') !== 'confirm_delete_bundle_msg' ? t('confirm_delete_bundle_msg') : 'Are you sure you want to delete this bundle?'} <span class="bundle-confirm-name">${STS2Utils.escapeHtml(bundle.name)}</span>`,
            t('delete') !== 'delete' ? t('delete') : 'Delete',
            async () => {
                // Notify backend API when connected
                if (this._app && this._app.api && this._app.isBackendConnected()) {
                    try {
                        await this._app.api.deleteBundle(id);
                    } catch (e) {
                        console.warn('[STS2Bundles] API deleteBundle failed:', e);
                    }
                }

                this.bundles = this.bundles.filter(b => b.id !== id);
                this._saveBundles();

                if (this.active_bundle === id) {
                    this.active_bundle = null;
                    this._app.store.set('active_bundle', null);
                }

                if (this.selected_bundle_id === id) {
                    this.selected_bundle_id = null;
                }

                this._app.notifications.show(
                    `${t('bundle_deleted') !== 'bundle_deleted' ? t('bundle_deleted') : 'Bundle deleted'}: ${bundle.name}`,
                    'success'
                );

                this.updateBundlesUI();
            }
        );
    },

    /**
     * Import a bundle from a .zip file (simulated).
     */
    importBundle() {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = '.zip';
        input.addEventListener('change', (e) => {
            const file = e.target.files[0];
            if (!file) return;

            const t = (key) => this._app.i18n.translate(key);

            // Simulate import: create a new bundle from file name
            const newBundle = {
                id: 'bundle-' + STS2Utils.generateId(),
                name: file.name.replace(/\.zip$/i, ''),
                version: 'v1.0.0',
                author: 'Imported',
                description: `${t('imported_from') !== 'imported_from' ? t('imported_from') : 'Imported from'}: ${file.name}`,
                mod_names: ['STS2中文汉化补丁', '敌人血量显示'],
                presets: { '默认': ['STS2中文汉化补丁', '敌人血量显示'] },
                update_url: null,
                created_date: new Date().toISOString()
            };

            this.bundles.push(newBundle);
            this._saveBundles();

            this._app.notifications.show(
                `${t('bundle_imported') !== 'bundle_imported' ? t('bundle_imported') : 'Bundle imported'}: ${newBundle.name}`,
                'success'
            );

            this.selected_bundle_id = newBundle.id;
            this.updateBundlesUI();
        });
        input.click();
    },

    /**
     * Import bundle files from drag-and-drop (bypasses file picker).
     * @param {File[]} files
     */
    importBundleFromFiles(files) {
        const zips = files.filter(f => f.name.toLowerCase().endsWith('.zip'));
        if (!zips.length) {
            this._app.notifications.show(
                this._app.i18n.translate('only_zip_supported') || '\u4ec5\u652f\u6301 .zip \u6587\u4ef6',
                'warning', 3000
            );
            return;
        }
        const t = (key) => this._app.i18n.translate(key);
        zips.forEach(file => {
            console.log('[STS2Bundles] Starting import for file:', file.name);
            // \u5fc5\u987b\u4f7f\u7528\u540e\u7aef API \u68c0\u6d4b bundle.json
            if (this._app && this._app.api && this._app.isBackendConnected()) {
                const reader = new FileReader();
                reader.onload = async () => {
                    console.log('[STS2Bundles] File loaded, size:', reader.result.length);
                    try {
                        const dataBase64 = reader.result.split(',')[1];
                        console.log('[STS2Bundles] Calling importBundle API...');
                        const result = await this._app.api.importBundle(file.name, dataBase64);

                        // \u8c03\u8bd5\uff1a\u6253\u5370\u8fd4\u56de\u7ed3\u679c
                        console.log('[STS2Bundles] importBundle result:', result);

                        // \u68c0\u67e5\u540e\u7aef\u8fd4\u56de\u7684\u7ed3\u679c
                        // \u6ce8\u610f\uff1a\u540e\u7aef\u53d1\u9001\u7684\u54cd\u5e94\u662f {success: true, ...}\uff0c\u4e0d\u662f {code: 200, data: {...}}
                        if (result && result.success) {
                            this._app.notifications.show(
                                `${t('bundle_imported') || '\u6574\u5408\u5305\u5df2\u5bfc\u5165'}: ${result.bundle_name || file.name}`,
                                'success'
                            );
                            await this.loadBundles();
                            this.updateBundlesUI();
                        } else if (result && result.error_type === 'missing_bundle_json') {
                            // \u540e\u7aef\u68c0\u6d4b\u5230\u4e0d\u662f\u6709\u6548\u7684\u6574\u5408\u5305
                            this._app.notifications.show(
                                `${t('bundle_import_failed') || '\u5bfc\u5165\u5931\u8d25'}: ${file.name} ${t('not_valid_bundle') || '\u4e0d\u662f\u6709\u6548\u7684\u6574\u5408\u5305\uff08\u7f3a\u5c11 bundle.json\uff09'}`,
                                'error', 5000
                            );
                        } else {
                            this._app.notifications.show(
                                `${t('bundle_import_failed') || '\u5bfc\u5165\u5931\u8d25'}: ${file.name}`,
                                'error', 5000
                            );
                        }
                    } catch (e) {
                        console.warn('[STS2Bundles] API importBundle failed:', e);
                        this._app.notifications.show(
                            `${t('bundle_import_failed') || '\u5bfc\u5165\u5931\u8d25'}: ${e.message || '\u672a\u77e5\u9519\u8bef'}`,
                            'error', 5000
                        );
                    }
                };
                reader.readAsDataURL(file);
            } else {
                // \u540e\u7aef\u672a\u8fde\u63a5\uff0c\u663e\u793a\u9519\u8bef\u63d0\u793a
                this._app.notifications.show(
                    t('backend_not_connected_bundle_import') || '\u540e\u7aef\u672a\u8fde\u63a5\uff0c\u65e0\u6cd5\u5bfc\u5165\u6574\u5408\u5305',
                    'warning', 5000
                );
            }
        });
    },

    /**
     * Import a bundle from a URL (show URL input dialog).
     */
    importBundleByUrl() {
        const t = (key) => this._app.i18n.translate(key);

        // Check if backend is connected
        if (!this._app || !this._app.isBackendConnected || !this._app.isBackendConnected()) {
            this._app.notifications.show(
                t('backend_not_connected_url_import') || '后端未连接，无法通过 URL 下载整合包',
                'warning'
            );
            return;
        }

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        overlay.innerHTML = `
            <div class="modal modal-md">
                <div class="modal__header">
                    <span class="modal__title">${t('bundle_url_import') || '通过 URL 导入整合包'}</span>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="modal__body">
                    <div class="url-import-form">
                        <div class="form-group">
                            <label class="form-label">${t('bundle_url_label') || '下载链接'}</label>
                            <input type="url"
                                class="input bundle-url-input"
                                placeholder="${t('bundle_url_placeholder') || 'https://example.com/bundle.zip'}"
                                autofocus>
                            <p class="form-hint">${t('bundle_url_hint') || '支持 Nexus Mods、GitHub Releases 等直接下载链接'}</p>
                        </div>
                    </div>
                </div>
                <div class="modal__footer">
                    <button class="btn btn-ghost modal-cancel-btn">${t('cancel') || '取消'}</button>
                    <button class="btn btn-primary modal-download-btn">
                        <span class="btn-icon">📥</span>
                        <span>${t('download') || '下载'}</span>
                    </button>
                </div>
            </div>
        `;

        const close = () => {
            overlay.classList.remove('open');
            setTimeout(() => overlay.remove(), 200);
        };

        overlay.querySelector('.modal__close').addEventListener('click', close);
        overlay.querySelector('.modal-cancel-btn').addEventListener('click', close);
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) close();
        });

        const downloadBtn = overlay.querySelector('.modal-download-btn');
        const urlInput = overlay.querySelector('.bundle-url-input');

        downloadBtn.addEventListener('click', async () => {
            const url = urlInput.value.trim();

            if (!url) {
                this._app.notifications.show(
                    t('url_required') || '请输入下载链接',
                    'warning'
                );
                urlInput.focus();
                return;
            }

            // Validate URL format
            try {
                new URL(url);
            } catch (e) {
                this._app.notifications.show(
                    t('url_invalid') || '请输入有效的 URL 地址',
                    'error'
                );
                urlInput.focus();
                return;
            }

            // Start download
            downloadBtn.disabled = true;
            downloadBtn.innerHTML = `<span class="spinner spinner-sm"></span> ${t('downloading') || '正在下载...'}`;

            try {
                // Use backend API to download and import bundle
                const result = await this._app.api.importBundleFromUrl(url);

                if (result && result.success) {
                    close();
                    this._app.notifications.show(
                        `${t('bundle_imported') || '整合包已导入'}: ${result.bundle_name || url.split('/').pop()}`,
                        'success'
                    );
                    // Reload bundles list
                    await this.loadBundles();
                    this.updateBundlesUI();
                } else {
                    throw new Error(result?.message || '下载失败');
                }
            } catch (e) {
                console.warn('[STS2Bundles] URL import failed:', e);
                this._app.notifications.show(
                    `${t('bundle_import_failed') || '导入失败'}: ${e.message}`,
                    'error'
                );
                downloadBtn.disabled = false;
                downloadBtn.innerHTML = `<span class="btn-icon">📥</span><span>${t('download') || '下载'}</span>`;
            }
        });

        document.getElementById('modal-container').appendChild(overlay);
        requestAnimationFrame(() => {
            overlay.classList.add('open');
            urlInput.focus();
        });
    },

    /**
     * Check for bundle update from its update_url.
     * @param {string} id
     */
    async checkBundleUpdate(id) {
        const bundle = this.bundles.find(b => b.id === id);
        if (!bundle) return;

        const t = (key) => this._app.i18n.translate(key);

        if (!bundle.update_url) {
            this._app.notifications.show(
                t('no_update_url') !== 'no_update_url' ? t('no_update_url') : '\u672a\u914d\u7f6e\u66f4\u65b0\u68c0\u67e5URL',
                'info'
            );
            return;
        }

        this._app.notifications.show(
            t('checking_update') || '\u6b63\u5728\u68c0\u67e5\u66f4\u65b0...',
            'info'
        );

        // In a real implementation, this would fetch the remote bundle.json
        // For now, simulate "already latest"
        setTimeout(() => {
            this._app.notifications.show(
                (t('already_latest') || '\u5df2\u662f\u6700\u65b0\u7248\u672c') + `: ${bundle.name}`,
                'success'
            );
        }, 1500);
    },

    /**
     * Show bundle conflict dialog when importing a bundle that already exists.
     * @param {object} existingBundle
     * @param {object} newBundle
     * @private
     */
    _showBundleConflictDialog(existingBundle, newBundle) {
        const t = (key) => this._app.i18n.translate(key);
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        overlay.innerHTML = `
            <div class="modal" style="max-width:420px">
                <div class="modal__header">
                    <span class="modal__title">${t('bundle_conflict_title') !== 'bundle_conflict_title' ? t('bundle_conflict_title') : '\u6574\u5408\u5305\u51b2\u7a81'}</span>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="modal__body" style="padding:var(--sp-lg) var(--sp-xl)">
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:12px">
                        ${(t('bundle_conflict_desc') || '\u5df2\u5b58\u5728\u540c\u540d\u6574\u5408\u5305\u300c{name}\u300d\uff0c\u5982\u4f55\u5904\u7406\uff1f').replace('{name}', STS2Utils.escapeHtml(existingBundle.name))}
                    </div>
                    <div style="display:flex;gap:8px;font-size:12px;margin-bottom:8px">
                        <div style="flex:1;padding:8px;background:var(--bg-surface);border-radius:var(--radius-md)">
                            <div style="color:var(--text-muted);margin-bottom:4px">\u5f53\u524d\u7248\u672c</div>
                            <div style="color:var(--text-primary)">${STS2Utils.escapeHtml(existingBundle.name)}</div>
                            <div style="color:var(--accent)">${existingBundle.version || '?'}</div>
                        </div>
                        <div style="flex:1;padding:8px;background:var(--bg-surface);border-radius:var(--radius-md)">
                            <div style="color:var(--text-muted);margin-bottom:4px">\u65b0\u7248\u672c</div>
                            <div style="color:var(--text-primary)">${STS2Utils.escapeHtml(newBundle.name)}</div>
                            <div style="color:var(--success)">${newBundle.version || '?'}</div>
                        </div>
                    </div>
                </div>
                <div class="modal__footer" style="gap:8px">
                    <button class="btn btn-primary bc-replace">${t('bundle_conflict_replace') !== 'bundle_conflict_replace' ? t('bundle_conflict_replace') : '\u66ff\u6362'}</button>
                    <button class="btn btn-ghost bc-skip">${t('bundle_conflict_skip') !== 'bundle_conflict_skip' ? t('bundle_conflict_skip') : '\u8df3\u8fc7'}</button>
                </div>
            </div>`;

        const close = () => overlay.remove();
        overlay.querySelector('.modal__close').addEventListener('click', close);
        overlay.querySelector('.bc-skip').addEventListener('click', close);
        overlay.querySelector('.bc-replace').addEventListener('click', () => {
            close();
            this.bundles = this.bundles.filter(b => b.id !== existingBundle.id);
            this.bundles.push(newBundle);
            this._saveBundles();
            this.selected_bundle_id = newBundle.id;
            this.updateBundlesUI();
            this._app.notifications.show(
                `${this._app.i18n.translate('bundle_imported') || '\u6574\u5408\u5305\u5df2\u5bfc\u5165'}: ${newBundle.name}`,
                'success'
            );
        });

        document.getElementById('modal-container').appendChild(overlay);
    },

    /**
     * Export a bundle to .zip (simulated -- shows notification).
     * @param {string} id
     */
    /**
     * Export current enabled mods as a new bundle.
     * Shows a dialog to input bundle details.
     */
    async exportBundle() {
        const t = (key) => this._app.i18n.translate(key);

        // 获取启用的模组数量 - 所有预设中涉及的模组合集（与原版 Godot 逻辑一致）
        let enabledCount = 0;
        let presetCount = 0;
        const presetModIds = new Set(); // 用于收集所有预设中的唯一模组ID

        // 优先从后端 API 获取 tag_data（与原版 Godot 逻辑一致）
        let tagData = {};
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.getMods();
                if (resp && resp.tag_data) {
                    tagData = resp.tag_data;
                    console.log('[exportBundle] Loaded tag_data from API:', tagData);
                }
            } catch (e) {
                console.warn('[exportBundle] Failed to get tag_data from API:', e);
            }
        }

        // 如果 API 获取失败，回退到 store
        if (Object.keys(tagData).length === 0 && this._app.store && this._app.store.has('mod_tags')) {
            tagData = this._app.store.get('mod_tags', {});
            console.log('[exportBundle] Fallback to store tag_data:', tagData);
        }

        // 计算预设数量和涉及的模组数量（与原版 Godot _export_bundle_to_zip 逻辑一致）
        // 注意：只统计实际存在于 mods 列表中的模组，过滤掉幽灵模组
        const validModIds = new Set((this._app.mods?.mods || []).map(m => m.id));
        presetCount = Object.keys(tagData).length;

        // 如果没有获取到有效模组列表，回退到使用所有预设中的模组（不过滤）
        if (validModIds.size === 0) {
            console.warn('[exportBundle] No valid mod list available, using all preset mods without filtering');
            for (const presetName in tagData) {
                const modIds = tagData[presetName] || [];
                for (const modId of modIds) {
                    presetModIds.add(modId);
                }
            }
        } else {
            // 有过滤：只添加实际存在的模组ID，过滤幽灵模组
            for (const presetName in tagData) {
                const modIds = tagData[presetName] || [];
                for (const modId of modIds) {
                    if (validModIds.has(modId)) {
                        presetModIds.add(modId);
                    } else {
                        console.log('[exportBundle] Skipping ghost mod:', modId);
                    }
                }
            }
        }
        enabledCount = presetModIds.size;

        console.log('[exportBundle] final enabledCount:', enabledCount, 'presetCount:', presetCount, 'unique mod ids:', presetModIds.size, 'valid mods:', validModIds.size);

        if (enabledCount === 0) {
            this._app.notifications.show(t('no_enabled_mods') || '没有启用的模组', 'warning');
            return;
        }

        // Create export modal with input fields (模仿存档导出对话框)
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';

        // 默认导出路径
        let exportPath = this._app.store.get('last_bundle_export_path', '');
        if (!exportPath) {
            // 使用下载目录作为默认路径
            exportPath = (navigator.userAgent.indexOf('Win') !== -1)
                ? `${window.process?.env?.USERPROFILE || 'C:\\Users\\User'}\\Downloads`
                : `${window.process?.env?.HOME || '/home/user'}/Downloads`;
        }
        const defaultZipName = name.replace(/\s+/g, '_').replace(/[\/\\]/g, '_') + '.zip';

        overlay.innerHTML = `
            <div class="modal modal-lg">
                <div class="modal__header">
                    <span class="modal__title">${t('export_bundle')}</span>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="modal__body">
                    <div class="bundle-export-form">
                        <div class="export-form-group">
                            <label class="export-form-label">${t('bundle_name')} *</label>
                            <input type="text" class="export-form-input" id="export-name"
                                placeholder="${t('bundle_name_placeholder') || '输入整合包名称'}"
                                value="${t('my_bundle') || '我的整合包'}">
                        </div>
                        <div class="export-form-row">
                            <div class="export-form-group">
                                <label class="export-form-label">${t('author_label') || '作者'}</label>
                                <input type="text" class="export-form-input" id="export-author"
                                    placeholder="${t('author_placeholder') || '作者名称'}">
                            </div>
                            <div class="export-form-group">
                                <label class="export-form-label">${t('version_label') || '版本'}</label>
                                <input type="text" class="export-form-input" id="export-version"
                                    value="v1.0.0">
                            </div>
                        </div>
                        <div class="export-form-group">
                            <label class="export-form-label">${t('description')}</label>
                            <textarea class="export-form-textarea" id="export-desc" rows="3"
                                placeholder="${t('bundle_desc_placeholder') || '描述这个整合包...'}"></textarea>
                        </div>
                        <!-- 导出路径选择（模仿存档导出） -->
                        <div class="export-form-group" style="margin-top:16px">
                            <label class="export-form-label">${t('export_directory') || '导出目录'}</label>
                            <div style="display:flex;gap:8px">
                                <input type="text" class="export-form-input" id="export-path" readonly
                                    value="${exportPath}"
                                    style="flex:1;background:var(--bg-secondary);border:1px solid var(--border)">
                                <button class="btn btn-ghost" id="export-browse-btn" style="flex-shrink:0">
                                    ${t('browse') || '浏览...'}
                                </button>
                            </div>
                        </div>
                        <div class="export-form-group">
                            <label class="export-form-label">${t('export_filename') || '导出文件名'}</label>
                            <input type="text" class="export-form-input" id="export-filename"
                                value="${defaultZipName}"
                                placeholder="*.zip">
                            <div style="font-size:11px;color:var(--text-secondary);margin-top:4px">
                                ${t('export_filename_hint') || '不带路径，仅文件名'}
                            </div>
                        </div>
                        <div class="export-mod-summary">
                            <div class="export-stat">
                                <span class="export-stat-value">${enabledCount}</span>
                                <span class="export-stat-label">${t('enabled_mods') || '已启用模组'}</span>
                            </div>
                            <div class="export-stat">
                                <span class="export-stat-value">${presetCount}</span>
                                <span class="export-stat-label">${t('presets')}</span>
                            </div>
                        </div>
                    </div>
                    <div class="export-progress" style="display:none">
                        <div class="export-progress-bar">
                            <div class="export-progress-fill"></div>
                        </div>
                        <span class="export-progress-text">${t('exporting_bundle') || '正在导出...'}</span>
                    </div>
                </div>
                <div class="modal__footer">
                    <button class="btn btn-ghost modal-cancel-btn">${t('cancel')}</button>
                    <button class="btn btn-primary modal-export-btn">
                        <span class="btn-icon">📥</span>
                        <span>${t('export')}</span>
                    </button>
                </div>
            </div>
        `;

        const close = () => {
            overlay.classList.remove('open');
            setTimeout(() => overlay.remove(), 200);
        };

        overlay.querySelector('.modal__close').addEventListener('click', close);
        overlay.querySelector('.modal-cancel-btn').addEventListener('click', close);

        // 浏览按钮 - 调用后端打开目录选择对话框（模仿存档导出）
        overlay.querySelector('#export-browse-btn').addEventListener('click', async () => {
            if (this._app && this._app.api) {
                try {
                    const result = await this._app.api.selectDirectory();
                    if (result && result.success && result.path) {
                        exportPath = result.path;
                        overlay.querySelector('#export-path').value = exportPath;
                        // 保存最后使用的路径
                        this._app.store.set('last_bundle_export_path', exportPath);
                    }
                } catch (e) {
                    console.warn('[STS2Bundles] selectDirectory failed:', e);
                }
            }
        });

        const exportBtn = overlay.querySelector('.modal-export-btn');
        const progressSection = overlay.querySelector('.export-progress');
        const progressFill = overlay.querySelector('.export-progress-fill');

        exportBtn.addEventListener('click', async () => {
            const name = overlay.querySelector('#export-name').value.trim();
            const author = overlay.querySelector('#export-author').value.trim();
            const version = overlay.querySelector('#export-version').value.trim();
            const description = overlay.querySelector('#export-desc').value.trim();
            const exportDir = overlay.querySelector('#export-path').value.trim();
            const fileName = overlay.querySelector('#export-filename').value.trim();

            if (!name) {
                this._app.notifications.show(t('name_required') || '名称不能为空', 'error');
                return;
            }

            // 构建完整的导出路径
            const finalExportPath = exportDir + '/' + (fileName || defaultZipName);

            exportBtn.disabled = true;
            exportBtn.innerHTML = `<span class="spinner"></span> ${t('exporting')}`;
            progressSection.style.display = 'block';

            // Animate progress
            progressFill.style.width = '30%';
            await new Promise(r => setTimeout(r, 300));
            progressFill.style.width = '60%';

            try {
                const result = await this._app.api.exportCurrentBundle({
                    name,
                    author,
                    version,
                    description,
                    export_path: finalExportPath
                });
                progressFill.style.width = '100%';

                // 处理 API 响应格式：后端返回 {code: 200, data: {success: true, ...}}
                // 或直接的 {success: true, ...} 格式
                const isSuccess = (result && result.data && result.data.success) ||
                                   (result && result.success);
                const fileName = result?.data?.file_name || result?.file_name || name + '.zip';
                const message = result?.data?.message || result?.message || 'Export failed';
                const finalPath = result?.data?.export_path || result?.export_path || finalExportPath;

                if (isSuccess) {
                    close();
                    this._app.notifications.show(
                        `${t('bundle_exported')}: ${fileName}`,
                        'success'
                    );
                    // 显示导出位置提示
                    this._app.notifications.show(
                        `${t('export_location') || '导出位置'}: ${finalPath}`,
                        'info',
                        5000
                    );
                    // 刷新整合包列表
                    await this.loadBundles();
                    this.updateBundlesUI();
                } else {
                    throw new Error(message);
                }
            } catch (e) {
                progressSection.style.display = 'none';
                exportBtn.disabled = false;
                exportBtn.innerHTML = `<span class="btn-icon">📥</span><span>${t('export')}</span>`;
                this._app.notifications.show(
                    `${t('bundle_export_failed')}: ${e.message}`,
                    'error'
                );
            }
        });

        document.getElementById('modal-container').appendChild(overlay);
        requestAnimationFrame(() => overlay.classList.add('open'));

        // Focus name input
        setTimeout(() => {
            const nameInput = overlay.querySelector('#export-name');
            if (nameInput) {
                nameInput.select();
                nameInput.focus();
            }
        }, 100);
    },

    /**
     * Get count of enabled mods.
     * @private
     */
    _getEnabledModsCount() {
        // Try to get from app store
        if (this._app.store && this._app.store.has('enabled_mods')) {
            const enabled = this._app.store.get('enabled_mods');
            return Object.values(enabled).filter(v => v).length;
        }
        // Fallback to API
        return this._app.mods?.filter(m => m.enabled).length || 0;
    },

    /**
     * Check for updates on a bundle (simulated).
     * @param {string} id
     */
    checkUpdate(id) {
        const bundle = this.bundles.find(b => b.id === id);
        if (!bundle) return;

        const t = (key) => this._app.i18n.translate(key);

        // Simulate a check: 60% chance of update available
        const hasUpdate = Math.random() > 0.4;

        if (hasUpdate) {
            const oldVersion = bundle.version;
            // Bump patch version
            const parts = oldVersion.replace(/^v/, '').split('.');
            const newVersion = `v${parts[0]}.${parts[1]}.${parseInt(parts[2] || '0', 10) + 1}`;

            this._showConfirmModal(
                t('update_available') !== 'update_available' ? t('update_available') : 'Update Available',
                `${t('new_version') !== 'new_version' ? t('new_version') : 'New version available'}: <strong>${STS2Utils.escapeHtml(bundle.name)}</strong> ${STS2Utils.escapeHtml(oldVersion)} → ${STS2Utils.escapeHtml(newVersion)}`,
                t('update') !== 'update' ? t('update') : 'Update',
                () => {
                    bundle.version = newVersion;
                    this._saveBundles();
                    this._app.notifications.show(
                        `${t('bundle_updated') !== 'bundle_updated' ? t('bundle_updated') : 'Bundle updated'}: ${bundle.name} → ${newVersion}`,
                        'success'
                    );
                    this.updateBundlesUI();
                }
            );
        } else {
            this._app.notifications.show(
                `${t('no_update') !== 'no_update' ? t('no_update') : 'No update available'}: ${bundle.name}`,
                'info'
            );
        }
    },

    // ── Modal helpers ─────────────────────────────────────────────

    /**
     * Show edit presets modal with mod selection.
     * @param {string} id
     * @private
     */
    _showEditPresetsModal(id) {
        const bundle = this.bundles.find(b => b.id === id);
        if (!bundle) return;

        const t = (key) => this._app.i18n.translate(key);
        const presets = bundle.presets || {};
        const presetKeys = Object.keys(presets);

        // Handle both string[] and {id:string, enabled:bool, tags:[]}[] formats
        const rawMods = bundle.mod_names || bundle.mods || [];
        const allMods = rawMods.map(m => typeof m === 'string' ? m : (m.id || m.name || String(m)));

        // Normalize current preset mods to strings
        const normalizeMods = (mods) => (mods || []).map(m => typeof m === 'string' ? m : (m.id || m.name || String(m)));

        if (presetKeys.length === 0) {
            this._app.notifications.show(t('no_preset_to_edit') || '没有可编辑的预设', 'warning');
            return;
        }

        let currentPreset = presetKeys[0];
        let currentMods = normalizeMods(presets[currentPreset]);

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';

        const renderModal = () => {
            // Filter out mods already in current preset
            const availableMods = allMods.filter(m => !currentMods.includes(m));

            overlay.innerHTML = `
                <div class="modal modal-lg">
                    <div class="modal__header">
                        <span class="modal__title">${t('edit_bundle_presets')}</span>
                        <button class="modal__close">&times;</button>
                    </div>
                    <div class="modal__body">
                        <div class="preset-editor">
                            <div class="preset-selector-row">
                                <select class="preset-select steam-select" id="preset-select">
                                    ${presetKeys.map(k => `<option value="${STS2Utils.escapeHtml(k)}" ${k === currentPreset ? 'selected' : ''}>${STS2Utils.escapeHtml(k)}</option>`).join('')}
                                </select>
                                <button class="btn btn-sm btn-ghost preset-rename-btn">${t('rename') || '重命名'}</button>
                                <button class="btn btn-sm btn-danger preset-delete-btn">${t('delete') || '删除'}</button>
                            </div>
                            <div class="preset-mod-manager">
                                <div class="available-mods-panel">
                                    <h4>${t('available_mods') || '可用模组'}</h4>
                                    <div class="mod-list" id="available-mods">
                                        ${availableMods.length > 0 ? availableMods.map(m => `
                                            <div class="mod-item" data-mod="${STS2Utils.escapeHtml(m)}">
                                                <span>${STS2Utils.escapeHtml(m)}</span>
                                                <button class="btn btn-xs btn-primary add-mod-btn" data-mod="${STS2Utils.escapeHtml(m)}">+</button>
                                            </div>
                                        `).join('') : `<div class="empty-msg">${t('no_more_mods') || '没有更多模组'}</div>`}
                                    </div>
                                </div>
                                <div class="transfer-panel">
                                    <button class="btn btn-sm btn-ghost add-all-btn" title="${t('add_all') || '添加全部'}">≫</button>
                                    <button class="btn btn-sm btn-ghost remove-all-btn" title="${t('remove_all') || '移除全部'}">≪</button>
                                </div>
                                <div class="selected-mods-panel">
                                    <h4>${t('selected_mods') || '已选模组'} (${currentMods.length})</h4>
                                    <div class="mod-list" id="selected-mods">
                                        ${currentMods.length > 0 ? currentMods.map(m => `
                                            <div class="mod-item selected" data-mod="${STS2Utils.escapeHtml(m)}">
                                                <span>${STS2Utils.escapeHtml(m)}</span>
                                                <button class="btn btn-xs btn-danger remove-mod-btn" data-mod="${STS2Utils.escapeHtml(m)}">×</button>
                                            </div>
                                        `).join('') : `<div class="empty-msg">${t('no_mods_selected') || '未选择模组'}</div>`}
                                    </div>
                                </div>
                            </div>
                            <div class="preset-add-new">
                                <button class="btn btn-ghost btn-sm" id="btn-add-preset">
                                    <span>+ ${t('new_preset') || '新建预设'}</span>
                                </button>
                            </div>
                        </div>
                    </div>
                    <div class="modal__footer">
                        <button class="btn btn-ghost modal-cancel-btn">${t('cancel')}</button>
                        <button class="btn btn-primary modal-confirm-btn">${t('save')}</button>
                    </div>
                </div>
            `;
        };

        renderModal();

        const close = () => overlay.remove();

        const attachListeners = () => {
            overlay.querySelector('.modal__close')?.addEventListener('click', close);
            overlay.querySelector('.modal-cancel-btn')?.addEventListener('click', close);

            overlay.querySelector('.modal-confirm-btn')?.addEventListener('click', () => {
                // Save current preset changes
                presets[currentPreset] = currentMods;
                bundle.presets = presets;
                this._saveBundles();
                close();
                this._app.notifications.show(t('bundle_preset_saved'), 'success');
                this.updateBundlesUI();
            });

            // Preset selector change
            overlay.querySelector('#preset-select')?.addEventListener('change', (e) => {
                // Save current preset before switching
                presets[currentPreset] = currentMods;
                currentPreset = e.target.value;
                currentMods = [...(presets[currentPreset] || [])];
                renderModal();
                attachListeners();
            });

            // Add mod buttons
            overlay.querySelectorAll('.add-mod-btn').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    const mod = e.target.dataset.mod;
                    if (mod && !currentMods.includes(mod)) {
                        currentMods.push(mod);
                        renderModal();
                        attachListeners();
                    }
                });
            });

            // Remove mod buttons
            overlay.querySelectorAll('.remove-mod-btn').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    const mod = e.target.dataset.mod;
                    currentMods = currentMods.filter(m => m !== mod);
                    renderModal();
                    attachListeners();
                });
            });

            // Add all
            overlay.querySelector('.add-all-btn')?.addEventListener('click', () => {
                const available = allMods.filter(m => !currentMods.includes(m));
                currentMods = [...currentMods, ...available];
                renderModal();
                attachListeners();
            });

            // Remove all
            overlay.querySelector('.remove-all-btn')?.addEventListener('click', () => {
                currentMods = [];
                renderModal();
                attachListeners();
            });

            // Rename preset
            overlay.querySelector('.preset-rename-btn')?.addEventListener('click', () => {
                const newName = prompt(t('rename_preset_prompt') || '重命名预设:', currentPreset);
                if (newName && newName !== currentPreset) {
                    presets[newName] = presets[currentPreset];
                    delete presets[currentPreset];
                    currentPreset = newName;
                    bundle.presets = presets;
                    renderModal();
                    attachListeners();
                }
            });

            // Delete preset
            overlay.querySelector('.preset-delete-btn')?.addEventListener('click', () => {
                this._showConfirmModal(
                    t('delete_preset') || '删除预设',
                    `<p>${t('confirm_delete_preset') || '确定要删除预设'} "${STS2Utils.escapeHtml(currentPreset)}"?</p>`,
                    t('delete') || '删除',
                    () => {
                        delete presets[currentPreset];
                        const keys = Object.keys(presets);
                        if (keys.length === 0) {
                            close();
                            this._app.notifications.show(t('no_preset_remaining') || '没有剩余预设', 'warning');
                            return;
                        }
                        currentPreset = keys[0];
                        currentMods = [...(presets[currentPreset] || [])];
                        bundle.presets = presets;
                        renderModal();
                        attachListeners();
                    }
                );
            });

            // Add new preset
            overlay.querySelector('#btn-add-preset')?.addEventListener('click', () => {
                const newName = t('new_preset') + ' ' + (presetKeys.length + 1);
                presets[newName] = [];
                bundle.presets = presets;
                currentPreset = newName;
                currentMods = [];
                renderModal();
                attachListeners();
            });
        };

        attachListeners();
        document.getElementById('modal-container').appendChild(overlay);
        requestAnimationFrame(() => overlay.classList.add('open'));
    },

    /**
     * Save bundle presets.
     * @param {string} id
     * @param {object} presets
     * @private
     */
    _saveBundlePresets(id, presets) {
        const bundle = this.bundles.find(b => b.id === id);
        if (!bundle) return;
        bundle.presets = presets;
        this._saveBundles();
    },

    /**
     * Show a confirmation modal.
     * @param {string} title
     * @param {string} messageHtml
     * @param {string} confirmLabel
     * @param {function} onConfirm
     * @private
     */
    _showConfirmModal(title, messageHtml, confirmLabel, onConfirm) {
        const container = document.getElementById('modal-container');
        if (!container) return;

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        overlay.innerHTML = `
            <div class="modal">
                <div class="modal__header">
                    <span class="modal__title">${STS2Utils.escapeHtml(title)}</span>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="modal__body">
                    <div class="bundle-confirm-body">${messageHtml}</div>
                </div>
                <div class="modal__footer">
                    <button class="btn btn-ghost modal-cancel-btn">${this._app.i18n.translate('cancel') !== 'cancel' ? this._app.i18n.translate('cancel') : 'Cancel'}</button>
                    <button class="btn btn-danger modal-confirm-btn">${STS2Utils.escapeHtml(confirmLabel)}</button>
                </div>
            </div>
        `;

        container.appendChild(overlay);
        // Trigger open animation
        requestAnimationFrame(() => overlay.classList.add('open'));

        const close = () => {
            overlay.classList.remove('open');
            setTimeout(() => overlay.remove(), 200);
        };

        overlay.querySelector('.modal__close').addEventListener('click', close);
        overlay.querySelector('.modal-cancel-btn').addEventListener('click', close);
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) close();
        });

        overlay.querySelector('.modal-confirm-btn').addEventListener('click', () => {
            close();
            if (typeof onConfirm === 'function') onConfirm();
        });
    },
};

// ── Export ─────────────────────────────────────────────────────────
window.STS2Bundles = STS2Bundles;
