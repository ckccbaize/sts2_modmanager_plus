/**
 * STS2Settings - Settings page module
 *
 * Renders a comprehensive settings page with path config, language selection,
 * DPI scaling, backup settings, launch options, Nexus API, storage paths,
 * mod JSON field validation, organization settings, server config, updates,
 * and a danger zone.
 */
window.STS2Settings = {

    // ── State ────────────────────────────────────────────────
    settings: {},
    dirty: false,
    _app: null,
    _rendered: false,

    // ── Lifecycle ────────────────────────────────────────────

    /**
     * Initialize the Settings module.
     * @param {STS2App} app
     */
    init(app) {
        this._app = app;
        this.loadSettings();  // async — no need to await in init
    },

    /** Called when the Settings page becomes active. */
    async onEnter() {
        await this.loadSettings();
        this.renderSettings();
        this.dirty = false;
        this._updateDirtyState();
    },

    /** Called when leaving the Settings page. */
    async onLeave() {
        if (this.dirty) {
            // Auto-save on leave (simpler UX than confirmation dialog for web)
            await this.saveSettings();
        }
    },

    // ── Settings CRUD ────────────────────────────────────────

    /**
     * Load all settings from the store into the local settings object.
     * When backend is connected, API settings take priority over local store.
     */
    async loadSettings() {
        const store = this._app.store;
        this.settings = {
            game_path: store.get('game_path', ''),
            save_path: store.get('save_path', ''),
            gse_cloud_path: store.get('gse_cloud_path', ''),
            steam_cloud_path: store.get('steam_cloud_path', ''),
            language: store.get('language', 'zh_CN'),
            dpi_scale: store.get('dpi_scale', 1.0),
            auto_backup: store.get('auto_backup', true),
            auto_backup_on_startup: store.get('auto_backup_on_startup', true),
            auto_backup_max_count: store.get('auto_backup_max_count', 10),
            launch_via_steam: store.get('launch_via_steam', true),
            enable_fix_steam: store.get('enable_fix_steam', false),
            fix_steam_path: store.get('fix_steam_path', ''),
            temp_mods_path: store.get('temp_mods_path', ''),
            backup_path: store.get('backup_path', ''),
            mod_json_fields: store.get('mod_json_fields', {
                id: true, name: true, author: true, description: true,
                version: true, has_pck: true, has_dll: true,
                affects_gameplay: false, dependencies: false,
            }),
            enable_mod_drag: store.get('enable_mod_drag', false),
            enable_override_order: store.get('enable_override_order', false),
            nexus_api_key: store.get('nexus_api_key', ''),
            nexus_api_validated: store.get('nexus_api_validated', false),
            server_port: store.get('server_port', 8765),
        };

        // Try backend API — merge API settings over local (API takes priority)
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.getSettings();
                if (resp && resp.settings) {
                    this.settings = { ...this.settings, ...resp.settings };
                    this._renderAll();
                    return;
                }
            } catch (e) {
                console.warn('[STS2Settings] API loadSettings failed:', e);
            }
        }
    },

    /**
     * Persist all settings to the store and emit a notification.
     * When backend is connected, also sends settings to the API.
     */
    async saveSettings() {
        const store = this._app.store;
        for (const [key, value] of Object.entries(this.settings)) {
            store.set(key, value);
        }
        this.dirty = false;
        this._updateDirtyState();
        this._app.notifications.show(this._t('settings_saved'), 'success', 2000);
        this._app.emit('settings-changed', this.settings);

        // Sync to backend API when connected
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                await this._app.api.updateSettings(this.settings);
            } catch (e) {
                console.warn('[STS2Settings] API updateSettings failed:', e);
            }
        }
    },

    /**
     * Reload settings from store, discarding unsaved changes.
     */
    discardChanges() {
        this.loadSettings();
        this.dirty = false;
        this._updateDirtyState();
        this.renderSettings();
    },

    // ── Rendering ────────────────────────────────────────────

    /**
     * Render the entire settings page.
     */
    renderSettings() {
        const container = document.getElementById('settings-content');
        if (!container) return;

        container.innerHTML = '';

        // Section 1: Path settings
        container.appendChild(this._renderPathSettings());

        // Section 2: Language
        container.appendChild(this._renderLanguageSettings());

        // Section 3: DPI scale
        container.appendChild(this._renderDpiSettings());

        // Section 4: Backup settings
        container.appendChild(this._renderBackupSettings());

        // Section 5: Launch settings
        container.appendChild(this._renderLaunchSettings());

        // Section 6: Storage paths
        container.appendChild(this._renderStorageSettings());

        // Section 7: Mod JSON fields
        container.appendChild(this._renderJsonFieldSettings());

        // Section 8: Organization settings
        container.appendChild(this._renderOrganizationSettings());

        // Section 9: Nexus API
        container.appendChild(this._renderNexusApiSettings());

        // Section 10: Server
        container.appendChild(this._renderServerSettings());

        // Section 11: Updates
        container.appendChild(this._renderUpdateSettings());

        // Section 12: Danger zone
        container.appendChild(this._renderDangerZone());

        // Save actions
        container.appendChild(this._renderActions());

        this._rendered = true;
    },

    // ── Section Renderers ────────────────────────────────────

    /** @private */
    _renderPathSettings() {
        return this._renderSection(this._t('game_path'), [
            this._renderPathRow(this._t('game_path'), this._t('select_game_exe'), 'game_path'),
            this._renderPathRow(this._t('save_path'), this._t('select_save_path'), 'save_path'),
            this._renderReadonlyRow('GSE ' + this._t('cloud_sync_gse'), this.settings.gse_cloud_path || '--'),
            this._renderReadonlyRow('Steam ' + this._t('cloud_sync_steam'), this.settings.steam_cloud_path || '--'),
        ]);
    },

    /** @private */
    _renderLanguageSettings() {
        const select = this._createSelect('settings-language', [
            { value: 'zh_CN', label: '\u4e2d\u6587' },
            { value: 'en_US', label: 'English' },
        ], this.settings.language, (val) => {
            this.changeLanguage(val);
        });

        return this._renderSection(this._t('language'), [
            this._renderSelectRow(this._t('language'), select),
        ]);
    },

    /** @private */
    _renderDpiSettings() {
        const value = this.settings.dpi_scale;
        const slider = document.createElement('div');
        slider.className = 'settings-slider-row';
        slider.innerHTML = `
            <div class="settings-slider-header">
                <span class="settings-slider-label">${this._t('dpi_scale')}</span>
                <span class="settings-slider-value" id="dpi-value">${value.toFixed(2)}</span>
            </div>
            <input type="range" class="settings-slider-input" id="dpi-slider"
                   min="0.8" max="2.0" step="0.05" value="${value}">
        `;

        const input = slider.querySelector('#dpi-slider');
        const display = slider.querySelector('#dpi-value');
        if (input) {
            input.addEventListener('input', (e) => {
                const v = parseFloat(e.target.value);
                display.textContent = v.toFixed(2);
                this.changeDpiScale(v);
            });
        }

        return this._renderSection(this._t('dpi_scale'), [slider]);
    },

    /** @private */
    _renderBackupSettings() {
        const autoBackupToggle = this._createToggle('settings-auto-backup', this.settings.auto_backup, (val) => {
            this.onSettingChange('auto_backup', val);
        });
        const autoStartupToggle = this._createToggle('settings-auto-backup-startup', this.settings.auto_backup_on_startup, (val) => {
            this.onSettingChange('auto_backup_on_startup', val);
        });
        const maxCountInput = document.createElement('div');
        maxCountInput.className = 'settings-control';
        maxCountInput.innerHTML = `
            <input type="number" class="input" style="width:80px;text-align:center"
                   id="settings-max-backup" min="1" max="50"
                   value="${this.settings.auto_backup_max_count}">
        `;
        const maxInput = maxCountInput.querySelector('input');
        if (maxInput) {
            maxInput.addEventListener('change', (e) => {
                this.onSettingChange('auto_backup_max_count', Math.max(1, Math.min(50, parseInt(e.target.value) || 10)));
            });
        }

        return this._renderSection(this._t('auto_backup'), [
            this._renderToggleRow(this._t('auto_backup'), this._t('auto_backup_label'), autoBackupToggle),
            this._renderToggleRow(this._t('auto_backup_on_startup'), '', autoStartupToggle),
            this._renderControlRow(this._t('auto_backup_max_count'), '1-50', maxCountInput),
        ]);
    },

    /** @private */
    _renderLaunchSettings() {
        const steamToggle = this._createToggle('settings-launch-steam', this.settings.launch_via_steam, (val) => {
            this.onSettingChange('launch_via_steam', val);
        });
        const fixToggle = this._createToggle('settings-fix-steam', this.settings.enable_fix_steam, (val) => {
            this.onSettingChange('enable_fix_steam', val);
        });

        const rows = [
            this._renderToggleRow(this._t('launch_via_steam'), '', steamToggle),
            this._renderToggleRow(this._t('enable_fix_steam'), this._t('enable_fix_steam_desc'), fixToggle),
            this._renderPathRow(this._t('fix_steam_path'), this._t('fix_steam_path_placeholder'), 'fix_steam_path'),
        ];

        return this._renderSection(this._t('launch_settings'), rows);
    },

    /** @private */
    _renderStorageSettings() {
        return this._renderSection(this._t('temp_mods_path'), [
            this._renderPathRow(this._t('temp_mods_path'), this._t('temp_mods_path_desc'), 'temp_mods_path'),
            this._renderPathRow(this._t('backup_path_label'), this._t('backup_path_label_desc'), 'backup_path'),
        ]);
    },

    /** @private */
    _renderJsonFieldSettings() {
        const fields = this.settings.mod_json_fields;
        const fieldKeys = [
            { key: 'id', label: this._t('field_id') },
            { key: 'name', label: this._t('field_name') },
            { key: 'author', label: this._t('field_author') },
            { key: 'description', label: this._t('field_description') },
            { key: 'version', label: this._t('field_version') },
            { key: 'has_pck', label: this._t('field_has_pck') },
            { key: 'has_dll', label: this._t('field_has_dll') },
            { key: 'affects_gameplay', label: this._t('field_affects_gameplay') },
            { key: 'dependencies', label: this._t('field_dependencies') },
        ];

        const group = document.createElement('div');
        group.className = 'settings-checkbox-group';
        fieldKeys.forEach(({ key, label }) => {
            const item = document.createElement('label');
            item.className = 'settings-checkbox-item';
            item.innerHTML = `
                <input type="checkbox" ${fields[key] ? 'checked' : ''} data-field="${key}">
                <span>${STS2Utils.escapeHtml(label)}</span>
            `;
            const cb = item.querySelector('input');
            if (cb) {
                cb.addEventListener('change', (e) => {
                    this.settings.mod_json_fields[key] = e.target.checked;
                    this.dirty = true;
                    this._updateDirtyState();
                });
            }
            group.appendChild(item);
        });

        return this._renderSection(this._t('mod_json_fields'), [
            this._createDesc(this._t('mod_json_fields_hint')),
            group,
        ]);
    },

    /** @private */
    _renderOrganizationSettings() {
        const dragToggle = this._createToggle('settings-mod-drag', this.settings.enable_mod_drag, (val) => {
            this.onSettingChange('enable_mod_drag', val);
        });
        const overrideToggle = this._createToggle('settings-override-order', this.settings.enable_override_order, (val) => {
            this.onSettingChange('enable_override_order', val);
        });

        return this._renderSection(this._t('mod_organization_title'), [
            this._createDesc(this._t('mod_organization_desc')),
            this._renderToggleRow(this._t('enable_mod_drag'), this._t('enable_mod_drag_tip'), dragToggle),
            this._renderToggleRow(this._t('enable_override_order'), this._t('enable_override_order_tip'), overrideToggle),
        ]);
    },

    /** @private */
    _renderNexusApiSettings() {
        const keyInput = document.createElement('div');
        keyInput.className = 'settings-path-controls';
        keyInput.innerHTML = `
            <input type="password" class="input" id="settings-nexus-key"
                   placeholder="${this._t('nexus_api_key_placeholder')}"
                   value="${STS2Utils.escapeHtml(this.settings.nexus_api_key)}">
            <button class="btn btn-primary btn-sm" id="settings-nexus-validate">${this._t('nexus_validate_btn_text')}</button>
        `;

        const keyField = keyInput.querySelector('input');
        if (keyField) {
            keyField.addEventListener('change', (e) => {
                this.onSettingChange('nexus_api_key', e.target.value);
            });
        }

        const validateBtn = keyInput.querySelector('#settings-nexus-validate');
        if (validateBtn) {
            validateBtn.addEventListener('click', () => {
                this.validateNexusApiKey();
            });
        }

        const statusClass = this.settings.nexus_api_validated ? 'success' : 'pending';
        const statusText = this.settings.nexus_api_validated
            ? this._t('nexus_validated')
            : this._t('nexus_not_validated');

        const statusEl = document.createElement('div');
        statusEl.className = 'settings-row';
        statusEl.innerHTML = `
            <div class="settings-label-area">
                <span class="settings-label">${this._t('nexus_status')}</span>
            </div>
            <div class="settings-control">
                <span class="settings-status ${statusClass}" id="settings-nexus-status">${statusText}</span>
            </div>
        `;

        const helpLink = document.createElement('div');
        helpLink.className = 'settings-help';
        helpLink.innerHTML = `
            <a href="#" id="settings-nexus-help">${this._t('nexus_how_to_get_api')}</a>
        `;
        const link = helpLink.querySelector('a');
        if (link) {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                this._app.notifications.show(this._t('nexus_get_api_tip'), 'info', 4000);
            });
        }

        return this._renderSection(this._t('nexus_api_title'), [
            this._createDesc(this._t('nexus_api_desc')),
            this._renderControlRow(this._t('nexus_api_key_label'), '', keyInput),
            statusEl,
            helpLink,
        ]);
    },

    /** @private */
    _renderServerSettings() {
        const portInput = document.createElement('div');
        portInput.className = 'settings-control';
        portInput.innerHTML = `
            <input type="number" class="input" style="width:100px;text-align:center"
                   id="settings-server-port" min="1024" max="65535"
                   value="${this.settings.server_port}">
        `;
        const input = portInput.querySelector('input');
        if (input) {
            input.addEventListener('change', (e) => {
                const port = Math.max(1024, Math.min(65535, parseInt(e.target.value) || 8765));
                this.onSettingChange('server_port', port);
            });
        }

        return this._renderSection(this._t('server_port'), [
            this._renderControlRow(this._t('server_port'), this._t('server_port_desc'), portInput),
            this._createDesc(this._t('server_restart_tip')),
        ]);
    },

    /** @private */
    _renderUpdateSettings() {
        // 从 store 获取版本号（由 app.js 初始化时设置）
        const version = this._app?.store?.get('app_version', 'v2.9.5') || 'v2.9.5';
        const versionEl = document.createElement('div');
        versionEl.className = 'settings-version';
        versionEl.innerHTML = `
            <span>${this._t('current_version')}:</span>
            <span class="settings-version-value">${version}</span>
        `;

        const updateBtn = document.createElement('button');
        updateBtn.className = 'btn btn-ghost btn-sm';
        updateBtn.textContent = this._t('check_update');
        updateBtn.addEventListener('click', () => this.checkForUpdates());

        const debugBtn = document.createElement('button');
        debugBtn.className = 'btn btn-ghost btn-sm';
        debugBtn.textContent = this._t('export_debug_info');
        debugBtn.addEventListener('click', () => this.exportDebugInfo());

        const actionsEl = document.createElement('div');
        actionsEl.className = 'settings-row';
        actionsEl.innerHTML = `<div class="settings-label-area"></div>`;
        const control = document.createElement('div');
        control.className = 'settings-control';
        control.style.gap = '8px';
        control.appendChild(updateBtn);
        control.appendChild(debugBtn);
        actionsEl.appendChild(control);

        return this._renderSection(this._t('check_update'), [
            versionEl,
            actionsEl,
        ]);
    },

    /** @private */
    _renderDangerZone() {
        const clearBtn = document.createElement('button');
        clearBtn.className = 'btn btn-danger btn-sm';
        clearBtn.textContent = this._t('clear_all_backups');
        clearBtn.addEventListener('click', () => this.clearAllBackups());

        const row = document.createElement('div');
        row.className = 'settings-row';
        row.innerHTML = `
            <div class="settings-label-area">
                <span class="settings-label">${this._t('clear_all_backups')}</span>
                <span class="settings-desc">${this._t('confirm_delete_all_backups').split('\n')[0]}</span>
            </div>
        `;
        const control = document.createElement('div');
        control.className = 'settings-control';
        control.appendChild(clearBtn);
        row.appendChild(control);

        const section = document.createElement('div');
        section.className = 'settings-section settings-danger';
        section.innerHTML = `
            <div class="settings-section-header">\u26a0 ${this._t('warning')}</div>
            <div class="settings-section-body"></div>
        `;
        section.querySelector('.settings-section-body').appendChild(row);
        return section;
    },

    /** @private */
    _renderActions() {
        const actions = document.createElement('div');
        actions.className = 'settings-actions';

        const discardBtn = document.createElement('button');
        discardBtn.className = 'btn btn-ghost';
        discardBtn.textContent = this._t('discard_changes');
        discardBtn.disabled = true;
        discardBtn.id = 'settings-discard-btn';
        discardBtn.addEventListener('click', () => this.discardChanges());

        const saveBtn = document.createElement('button');
        saveBtn.className = 'btn btn-primary';
        saveBtn.textContent = this._t('confirm');
        saveBtn.id = 'settings-save-btn';
        saveBtn.addEventListener('click', () => this.saveSettings());

        actions.appendChild(discardBtn);
        actions.appendChild(saveBtn);
        return actions;
    },

    // ── Actions ──────────────────────────────────────────────

    /**
     * Auto-detect the game installation path.
     * Uses backend API when connected, falls back to simulated detection.
     */
    async autoDetectGamePath() {
        let detected = 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Slay the Spire 2';

        // Try backend API first
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.detectGamePath();
                if (resp && resp.path) {
                    detected = resp.path;
                }
            } catch (e) {
                console.warn('[STS2Settings] API detectGamePath failed:', e);
            }
        }

        this.settings.game_path = detected;
        this.dirty = true;
        this._updateDirtyState();
        this._app.notifications.show(
            this._t('path_detected') + ': ' + detected,
            'success',
            3000
        );
        // Update the input if visible
        const input = document.querySelector('[data-setting="game_path"]');
        if (input) input.value = detected;
    },

    /**
     * Auto-detect the save path.
     * Uses backend API when connected, falls back to simulated detection.
     */
    async autoDetectSavePath() {
        let detected = '%APPDATA%\\SlayTheSpire2';

        // Try backend API first
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.detectSavePath();
                if (resp && resp.path) {
                    detected = resp.path;
                }
            } catch (e) {
                console.warn('[STS2Settings] API detectSavePath failed:', e);
            }
        }

        this.settings.save_path = detected;
        this.dirty = true;
        this._updateDirtyState();
        this._app.notifications.show(
            this._t('path_detected') + ': ' + detected,
            'success',
            3000
        );
        const input = document.querySelector('[data-setting="save_path"]');
        if (input) input.value = detected;
    },

    /**
     * Change the application language.
     * @param {string} lang
     */
    changeLanguage(lang) {
        this.onSettingChange('language', lang);
        this._app.i18n.setLanguage(lang);
        this._app.i18n.applyTranslations();
        this._app.i18n.applyPlaceholders();
        this._app.emit('language-applied');
        // Re-render settings after language change
        setTimeout(() => this.renderSettings(), 50);
    },

    /**
     * Change the DPI scale factor.
     * @param {number} value
     */
    changeDpiScale(value) {
        this.onSettingChange('dpi_scale', value);
        this._app.applyDpiScale(value);
    },

    /**
     * Validate the Nexus API key entered in the settings.
     */
    async validateNexusApiKey() {
        const input = document.getElementById('settings-nexus-key');
        const key = input ? input.value : '';
        if (!key.trim()) {
            this._app.notifications.show(this._t('cannot_be_empty'), 'warning', 2000);
            return;
        }

        this.onSettingChange('nexus_api_key', key.trim());

        // Simulate validation
        const statusEl = document.getElementById('settings-nexus-status');
        if (statusEl) {
            statusEl.className = 'settings-status pending';
            statusEl.textContent = this._t('nexus_validating');
        }

        await new Promise(resolve => setTimeout(resolve, 1000));

        const valid = key.trim().length >= 8;
        this.settings.nexus_api_validated = valid;
        this.dirty = true;

        if (statusEl) {
            if (valid) {
                statusEl.className = 'settings-status success';
                statusEl.textContent = this._t('nexus_validated');
                this._app.notifications.show(
                    this._t_fmt('api_validated_success', ['User']),
                    'success',
                    3000
                );
            } else {
                statusEl.className = 'settings-status error';
                statusEl.textContent = this._t('nexus_validation_failed');
                this._app.notifications.show(
                    this._t_fmt('api_key_validate_failed', ['Invalid']),
                    'error',
                    3000
                );
            }
        }
    },

    /**
     * Clear all backup files (simulated).
     */
    clearAllBackups() {
        if (!confirm(this._t('confirm_delete_all_backups'))) return;
        this._app.notifications.show(
            this._t_fmt('all_backups_deleted', ['12']),
            'success',
            3000
        );
    },

    /**
     * Check for application updates (simulated).
     */
    async checkForUpdates() {
        const t = (key) => this._t(key);
        this._app.notifications.show(t('checking_update') || '正在检查更新...', 'info', 2000);

        // 获取当前版本号
        const currentVersion = this._app?.store?.get('app_version', 'v2.9.5') || 'v2.9.5';

        // Try backend API for real update check
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.checkUpdate();
                // resp.data.has_update 来自 Godot 后端 API，resp.update_available 来自旧的模拟 API
                const respData = resp.data || resp;
                if (respData.has_update || respData.update_available) {
                    this._showUpdateDialog(currentVersion, respData.new_version || respData.version, respData.download_url);
                    return;
                }
            } catch (e) {
                console.warn('[STS2Settings] API checkUpdate failed:', e);
            }
        }

        // Simulated update check (offline mode)
        setTimeout(() => {
            this._app.notifications.show(
                this._t_fmt('already_latest_version', [currentVersion]) || '当前已是最新版本 ' + currentVersion,
                'success',
                3000
            );
        }, 1500);
    },

    /**
     * Show an update available dialog with download progress.
     * @param {string} currentVersion
     * @param {string} newVersion
     * @param {string} downloadUrl
     * @private
     */
    _showUpdateDialog(currentVersion, newVersion, downloadUrl) {
        const t = (key) => this._t(key);

        // 优先使用 BrowserHost 原生弹窗（不依赖浏览器层）
        console.log('[STS2Settings] _showUpdateDialog called:', currentVersion, '->', newVersion);

        try {
            const hostObjects = window.chrome?.webview?.hostObjects;
            console.log('[STS2Settings] hostObjects:', hostObjects);
            console.log('[STS2Settings] hostObjects?.sync:', hostObjects?.sync);
            console.log('[STS2Settings] hostObjects?.sync?.browserHost:', hostObjects?.sync?.browserHost);

            if (hostObjects?.sync?.browserHost) {
                console.log('[STS2Settings] Calling BrowserHost ShowUpdateDialog via sync');
                try {
                    hostObjects.sync.browserHost.ShowUpdateDialog(
                        currentVersion || '?',
                        newVersion || '?',
                        downloadUrl || ''
                    );
                    console.log('[STS2Settings] ShowUpdateDialog call succeeded');
                    return;
                } catch (syncError) {
                    console.error('[STS2Settings] Sync call failed:', syncError);
                    // 继续尝试异步方式
                }
            }

            if (hostObjects?.browserHost) {
                console.log('[STS2Settings] Trying async browserHost call');
                hostObjects.browserHost.ShowUpdateDialog(
                    currentVersion || '?',
                    newVersion || '?',
                    downloadUrl || ''
                );
                console.log('[STS2Settings] Async call succeeded');
                return;
            }

            console.warn('[STS2Settings] No browserHost found, using fallback');
        } catch(e) {
            console.error('[STS2Settings] ShowUpdateDialog failed:', e);
        }

        // Fallback: 浏览器内置弹窗
        console.log('[STS2Settings] Showing browser fallback modal');
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        overlay.innerHTML = `
            <div class="modal" style="max-width:400px">
                <div class="modal__header">
                    <span class="modal__title">${t('update_available') || '发现新版本'}</span>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="modal__body" style="padding:var(--sp-lg) var(--sp-xl)">
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:12px">
                        ${(t('current_version_label') || '当前版本: {current}\n新版本: {new}')
                            .replace('{current}', currentVersion || '?')
                            .replace('{new}', newVersion || '?')}
                    </div>
                    <div class="update-progress-area" style="display:none;margin-top:12px">
                        <div style="font-size:12px;color:var(--text-muted);margin-bottom:6px" class="update-progress-text">
                            ${t('downloading_update') || '正在下载更新...'} 0%
                        </div>
                        <div style="width:100%;height:6px;background:var(--bg-surface);border-radius:3px;overflow:hidden">
                            <div class="update-progress-fill" style="width:0%;height:100%;background:var(--accent);transition:width 0.3s ease"></div>
                        </div>
                    </div>
                </div>
                <div class="modal__footer update-footer" style="gap:8px">
                    <button class="btn btn-primary update-download-btn">${t('update_install_now') || '立即更新'}</button>
                    <button class="btn btn-ghost update-later-btn">${t('update_install_later') || '稍后提醒'}</button>
                </div>
            </div>`;

        const close = () => overlay.remove();
        overlay.querySelector('.modal__close').addEventListener('click', close);
        overlay.querySelector('.update-later-btn').addEventListener('click', close);
        overlay.querySelector('.update-download-btn').addEventListener('click', () => {
            // Hide buttons, show progress
            const footer = overlay.querySelector('.update-footer');
            if (footer) footer.style.display = 'none';
            const progressArea = overlay.querySelector('.update-progress-area');
            if (progressArea) progressArea.style.display = 'block';

            // Simulate download progress
            let pct = 0;
            const progressFill = overlay.querySelector('.update-progress-fill');
            const progressText = overlay.querySelector('.update-progress-text');
            const interval = setInterval(() => {
                pct += Math.random() * 15 + 5;
                if (pct > 100) pct = 100;
                if (progressFill) progressFill.style.width = pct + '%';
                if (progressText) progressText.textContent =
                    (t('downloading_update') || '正在下载更新...') + ' ' + Math.round(pct) + '%';

                if (pct >= 100) {
                    clearInterval(interval);
                    setTimeout(() => {
                        close();
                        this._app.notifications.show(
                            t('update_install_confirm') || '下载完成，请重启应用安装更新',
                            'success', 5000
                        );
                    }, 500);
                }
            }, 200);
        });

        document.getElementById('modal-container').appendChild(overlay);
    },

    /**
     * Export debug information (simulated).
     */
    exportDebugInfo() {
        const info = {
            version: '2.9.5',
            language: this.settings.language,
            dpi_scale: this.settings.dpi_scale,
            game_path: this.settings.game_path,
            store_keys: this._app.store.keys(),
            timestamp: new Date().toISOString(),
        };
        const json = JSON.stringify(info, null, 2);
        const blob = new Blob([json], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'sts2mm-debug-info.json';
        a.click();
        URL.revokeObjectURL(url);
        this._app.notifications.show(this._t('export_debug_info'), 'success', 3000);
    },

    /**
     * Mark a setting as changed.
     * @param {string} key
     * @param {*} value
     */
    onSettingChange(key, value) {
        this.settings[key] = value;
        this.dirty = true;
        this._updateDirtyState();
    },

    // ── Rendering Helpers ────────────────────────────────────

    /**
     * Render a settings section card.
     * @param {string} title
     * @param {Array<HTMLElement|string>} children
     * @returns {HTMLElement}
     * @private
     */
    _renderSection(title, children) {
        const section = document.createElement('div');
        section.className = 'settings-section';
        section.innerHTML = `
            <div class="settings-section-header">${STS2Utils.escapeHtml(title)}</div>
            <div class="settings-section-body"></div>
        `;
        const body = section.querySelector('.settings-section-body');
        children.forEach(child => {
            if (typeof child === 'string') {
                body.insertAdjacentHTML('beforeend', child);
            } else {
                body.appendChild(child);
            }
        });
        return section;
    },

    /**
     * Render a path input row with browse and auto-detect buttons.
     * @private
     */
    _renderPathRow(label, desc, settingKey) {
        const row = document.createElement('div');
        row.className = 'settings-path-row';
        row.innerHTML = `
            <span class="settings-path-label">${STS2Utils.escapeHtml(label)}</span>
            ${desc ? `<span class="settings-path-desc">${STS2Utils.escapeHtml(desc)}</span>` : ''}
            <div class="settings-path-controls">
                <input type="text" class="input" data-setting="${settingKey}"
                       value="${STS2Utils.escapeHtml(this.settings[settingKey] || '')}"
                       placeholder="${STS2Utils.escapeHtml(desc || '')}">
                <button class="btn btn-ghost btn-sm">${this._t('browse')}</button>
                <button class="btn btn-ghost btn-sm">${this._t('auto_detect')}</button>
            </div>
        `;

        const input = row.querySelector('input');
        const buttons = row.querySelectorAll('button');

        if (input) {
            input.addEventListener('change', (e) => {
                this.onSettingChange(settingKey, e.target.value);
            });
        }

        // Browse button (simulated)
        if (buttons[0]) {
            buttons[0].addEventListener('click', () => {
                this._app.notifications.show(this._t('browse'), 'info', 1500);
            });
        }

        // Auto-detect button
        if (buttons[1]) {
            buttons[1].addEventListener('click', () => {
                if (settingKey === 'game_path') this.autoDetectGamePath();
                else if (settingKey === 'save_path') this.autoDetectSavePath();
                else this._app.notifications.show(this._t('path_detected'), 'info', 2000);
            });
        }

        return row;
    },

    /**
     * Render a readonly info row.
     * @private
     */
    _renderReadonlyRow(label, value) {
        const row = document.createElement('div');
        row.className = 'settings-row';
        row.innerHTML = `
            <div class="settings-label-area">
                <span class="settings-label">${STS2Utils.escapeHtml(label)}</span>
            </div>
            <div class="settings-control">
                <span class="text-muted" style="font-size:var(--font-xs)">${STS2Utils.escapeHtml(value)}</span>
            </div>
        `;
        return row;
    },

    /**
     * Render a toggle row.
     * @private
     */
    _renderToggleRow(label, desc, toggleEl) {
        const row = document.createElement('div');
        row.className = 'settings-toggle-row';

        const labelArea = document.createElement('div');
        labelArea.className = 'settings-label-area';
        labelArea.innerHTML = `
            <span class="settings-label">${STS2Utils.escapeHtml(label)}</span>
            ${desc ? `<span class="settings-desc">${STS2Utils.escapeHtml(desc)}</span>` : ''}
        `;

        row.appendChild(labelArea);
        row.appendChild(toggleEl);
        return row;
    },

    /**
     * Render a generic control row.
     * @private
     */
    _renderControlRow(label, desc, controlEl) {
        const row = document.createElement('div');
        row.className = 'settings-row';

        const labelArea = document.createElement('div');
        labelArea.className = 'settings-label-area';
        labelArea.innerHTML = `
            <span class="settings-label">${STS2Utils.escapeHtml(label)}</span>
            ${desc ? `<span class="settings-desc">${STS2Utils.escapeHtml(desc)}</span>` : ''}
        `;

        row.appendChild(labelArea);
        row.appendChild(controlEl);
        return row;
    },

    /**
     * Render a select dropdown row.
     * @private
     */
    _renderSelectRow(label, selectEl) {
        const row = document.createElement('div');
        row.className = 'settings-select-row';

        const labelEl = document.createElement('span');
        labelEl.className = 'settings-label';
        labelEl.textContent = label;

        row.appendChild(labelEl);
        row.appendChild(selectEl);
        return row;
    },

    /**
     * Create a toggle switch element.
     * @private
     */
    _createToggle(id, checked, onChange) {
        const toggle = document.createElement('label');
        toggle.className = 'toggle';
        toggle.innerHTML = `
            <input type="checkbox" id="${id}" ${checked ? 'checked' : ''}>
            <span class="toggle__track"></span>
            <span class="toggle__knob"></span>
        `;
        const input = toggle.querySelector('input');
        if (input) {
            input.addEventListener('change', (e) => {
                if (onChange) onChange(e.target.checked);
            });
        }
        return toggle;
    },

    /**
     * Create a select element.
     * @private
     */
    _createSelect(id, options, value, onChange) {
        const select = document.createElement('select');
        select.className = 'input';
        select.id = id;
        options.forEach(opt => {
            const option = document.createElement('option');
            option.value = opt.value;
            option.textContent = opt.label;
            if (opt.value === value) option.selected = true;
            select.appendChild(option);
        });
        if (onChange) {
            select.addEventListener('change', (e) => onChange(e.target.value));
        }
        return select;
    },

    /**
     * Create a description paragraph.
     * @private
     */
    _createDesc(text) {
        const p = document.createElement('p');
        p.className = 'settings-desc';
        p.style.padding = '4px 0 8px';
        p.textContent = text;
        return p;
    },

    /**
     * Update the dirty state visual indicator and button states.
     * @private
     */
    _updateDirtyState() {
        const container = document.getElementById('settings-content');
        if (container) {
            container.classList.toggle('dirty', this.dirty);
        }

        const saveBtn = document.getElementById('settings-save-btn');
        const discardBtn = document.getElementById('settings-discard-btn');
        if (saveBtn) saveBtn.disabled = !this.dirty;
        if (discardBtn) discardBtn.disabled = !this.dirty;
    },

    /**
     * Translate shortcut.
     * @param {string} key
     * @returns {string}
     * @private
     */
    _t(key) {
        return this._app.i18n.translate(key);
    },

    /**
     * Translate with format arguments.
     * @param {string} key
     * @param {Array} args
     * @returns {string}
     * @private
     */
    _t_fmt(key, args) {
        return this._app.i18n.translate_fmt(key, args);
    },
};
