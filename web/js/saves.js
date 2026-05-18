/**
 * STS2Saves - Save management module
 *
 * Manages game saves: load, browse, backup, restore, overwrite, import/export.
 * Data loaded from window.MOCK_SAVES on first run, then persisted to localStorage.
 */
const STS2Saves = {

    // ── State ─────────────────────────────────────────────────────
    saves: [],
    selected_save_id: null,
    current_profile: 1,
    _app: null,
    _initialized: false,
    _longpressTimer: null,
    _longpressTarget: null,
    _groups: {},    // { steam_id: { steam_id, name, has_steam, has_modded, steam_profiles: [], modded_profiles: [] } }
                    // 每个 Steam 账号是一个整体，包含原版和模组版两个部分
    _groupOpen: {}, // { steam_id: bool } - 账号卡片展开/折叠状态

    // Character icon map - 使用精美的 emoji 和 Unicode 符号
    _charIcons: {
        '铁甲战士': '🛡️',
        '静默猎手': '🏹',
        '储君': '👑',
        '亡灵契约师': '💀',
        '故障机器人': '🤖',
        // 英文角色名映射
        'CHARACTER.IRONCLAD': '🛡️',
        'CHARACTER.SILENT': '🏹',
        'CHARACTER.REGENT': '👑',
        'CHARACTER.NECROBINDER': '💀',
        'CHARACTER.DEFECT': '🤖',
        // 默认/未知角色
        'UNKNOWN': '❓',
        '': '⚔️',
    },

    // 角色名称映射表（英文 -> 中文）
    _charNames: {
        'CHARACTER.IRONCLAD': '铁甲战士',
        'CHARACTER.SILENT': '静默猎手',
        'CHARACTER.REGENT': '储君',
        'CHARACTER.NECROBINDER': '亡灵契约师',
        'CHARACTER.DEFECT': '故障机器人',
    },
    // ── Lifecycle ─────────────────────────────────────────────────

    init(app) {
        this._app = app;
        this._bindEvents();
        this._initialized = true;
        // Load data then render — loadSaves is async
        this.loadSaves().then(() => this.updateSavesUI());
        console.log('[STS2Saves] Initialized.');
    },

    onEnter() {
        // Reload from API on each entry to ensure fresh data
        this.loadSaves().then(() => this.updateSavesUI());
    },

    onLeave() {
        // Cancel any active long-press
        this._cancelLongpress();
    },

    /**
     * Notify backend about selection change (which account is selected).
     * @param {string} accountId - The selected account ID (steam_id or imported_xxx)
     * @private
     */
    _notifySelectionChange(accountId) {
        // 通过 API 通知后端选中状态变化
        // 后端可以据此更新配置或执行其他逻辑
        if (this._app && this._app.api) {
            this._app.api._request('POST', '/api/saves/selection', { account_id: accountId }).catch(() => {
                // 静默失败，不影响前端体验
            });
        }
        console.log('[Saves] Selection changed:', accountId);
    },

    // ── Event binding ─────────────────────────────────────────────

    /** @private */
    _bindEvents() {
        const t = (key) => this._app.i18n.translate(key);

        // Helper to update button states based on selection
        const updateButtonStates = () => {
            const hasSelection = this._selectedAccount !== null;
            const importBtn = document.getElementById('btn-import-save');
            const exportBtn = document.getElementById('btn-export-save');
            const backupBtn = document.getElementById('btn-backup-save');
            const restoreBtn = document.getElementById('btn-restore-save');
            const overwriteBtn = document.getElementById('btn-overwrite-save');

            if (importBtn) importBtn.disabled = false; // Always allow import
            if (exportBtn) exportBtn.disabled = !hasSelection;
            if (backupBtn) backupBtn.disabled = !hasSelection;
            if (restoreBtn) restoreBtn.disabled = !hasSelection;
            if (overwriteBtn) overwriteBtn.disabled = !hasSelection;
        };

        const importBtn = document.getElementById('btn-import-save');
        if (importBtn) importBtn.addEventListener('click', () => this.importSave());

        const exportBtn = document.getElementById('btn-export-save');
        if (exportBtn) exportBtn.addEventListener('click', () => {
            if (this._selectedAccount) this._batchExport();
            else this._app.notifications.show(t('select_save_first') !== 'select_save_first' ? t('select_save_first') : 'Select a save first', 'warning');
        });

        const backupBtn = document.getElementById('btn-backup-save');
        if (backupBtn) backupBtn.addEventListener('click', () => {
            if (this._selectedAccount) this._batchBackup();
            else this._app.notifications.show(t('select_save_first') !== 'select_save_first' ? t('select_save_first') : 'Select a save first', 'warning');
        });

        const restoreBtn = document.getElementById('btn-restore-save');
        if (restoreBtn) {
            restoreBtn.addEventListener('click', () => {
                console.log('[Saves] Restore button clicked, _selectedAccount:', this._selectedAccount);
                if (this._selectedAccount) {
                    this._batchRestore();
                } else {
                    this._app.notifications.show(t('select_save_first') !== 'select_save_first' ? t('select_save_first') : 'Select a save first', 'warning');
                }
            });
        }

        const overwriteBtn = document.getElementById('btn-overwrite-save');
        if (overwriteBtn) overwriteBtn.addEventListener('click', () => {
            if (this._selectedAccount) this.overwriteSave();
            else this._app.notifications.show(t('select_save_first') !== 'select_save_first' ? t('select_save_first') : 'Select a save first', 'warning');
        });

        const collapseBtn = document.getElementById('btn-collapse-saves');
        if (collapseBtn) {
            collapseBtn.addEventListener('click', () => {
                const panel = document.getElementById('save-list-panel');
                if (panel) panel.classList.toggle('collapsed');
            });
        }

        this._app.on('language-applied', () => {
            if (this._initialized) {
                this.updateSavesUI();
                updateButtonStates();
            }
        });
    },

    // ── Data ──────────────────────────────────────────────────────

    /** Load saves from backend API, store, or mock data. */
    async loadSaves() {
        // Try backend API first
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.getSaves();
                console.log('[STS2Saves] API response:', resp);
                // API 返回格式可能是 {saves: [...]} 或 {data: {saves: [...]}}
                const savesData = resp?.data?.saves || resp?.saves;
                console.log('[STS2Saves] savesData:', savesData?.length);
                if (savesData && savesData.length > 0) {
                    // 后端返回的字段是 is_modded，前端统一转换为 modded
                    this.saves = savesData.map(save => ({
                        ...save,
                        modded: save.is_modded === true || save.type === 'modded'
                    }));
                    console.log('[STS2Saves] Loaded', this.saves.length, 'saves from API');
                    this._buildGroups();
                    return;
                }
            } catch (e) {
                console.warn('[STS2Saves] API loadSaves failed:', e);
            }
        }
        // Fallback to localStorage / mock
        const store = this._app.store;
        if (store.has('saves_data') && store.get('saves_data').length > 0) {
            this.saves = store.get('saves_data');
        } else if (typeof window.MOCK_SAVES !== 'undefined') {
            this.saves = STS2Utils.deepClone(window.MOCK_SAVES);
            store.set('saves_data', this.saves);
        } else {
            this.saves = [];
        }
        this._buildGroups();
    },

    /**
     * Build grouped save data by Steam account.
     *
     * Structure:
     *   {
     *     "76561197960287930": {
     *       steam_id: "76561197960287930",
     *       name: "账号 1234",
     *       has_steam: true,       // 是否有原版存档
     *       has_modded: true,      // 是否有模组存档
     *       steam_profiles: [      // 原版 Profile 列表
     *         { id, name, path, date, size, profiles: [...] }
     *       ],
     *       modded_profiles: [     // 模组 Profile 列表
     *         { id, name, path, date, size, profiles: [...] }
     *       ]
     *     },
     *     "imported_xxx": { ... }  // 导入的存档
     *   }
     * @private
     */
    _buildGroups() {
        this._groups = {};

        this.saves.forEach(save => {
            // 使用 is_imported 字段判断是否为导入存档（而不是检查 steam_id 是否存在）
            const isImported = save.is_imported === true;
            const isModded = save.modded === true || save.is_modded === true;

            let accountId;
            let accountName;

            if (isImported) {
                // 导入存档：从 id 中提取文件夹名称
                // ID 格式：imported_{folder_name}_profile_N 或 imported_{folder_name}_modded_profile_N
                const match = save.id?.match(/^imported_([^_]+)_/);
                const folderName = match ? match[1] : (save.name || 'unknown');
                accountId = `imported_${folderName}`;
                accountName = folderName;
            } else {
                // Steam 存档：使用 SteamID 作为 accountId
                accountId = save.steam_id;
                // 安全检查：steam_id 可能为 null
                if (save.steam_id && save.steam_id.length >= 4) {
                    accountName = `账号${save.steam_id.substr(save.steam_id.length - 4)}`;
                } else {
                    accountName = `账号未知`;
                }
            }

            // 如果这个账号还没有条目，创建一个新的
            if (!this._groups[accountId]) {
                this._groups[accountId] = {
                    steam_id: isImported ? null : save.steam_id,
                    name: isImported ? accountName : accountName,
                    has_steam: false,
                    has_modded: false,
                    steam_profiles: [],
                    modded_profiles: [],
                    is_imported: isImported
                };
            }

            // 导入存档和 Steam 存档现在都已经是独立的 profile 对象，直接添加即可
            if (isModded) {
                this._groups[accountId].has_modded = true;
                this._groups[accountId].modded_profiles.push(save);
            } else {
                this._groups[accountId].has_steam = true;
                this._groups[accountId].steam_profiles.push(save);
            }

            // Ensure group is open by default
            if (!(accountId in this._groupOpen)) this._groupOpen[accountId] = true;
        });
    },

    // ── Rendering ─────────────────────────────────────────────────

    updateSavesUI() {
        this.renderSaveList();
        this._updateButtonStates();
        // Show details for first save in selection if no specific save is viewed
        if (this._selectedAccount && this.saves.length > 0) {
            const firstSave = this._getSelectedSaves()[0];
            if (firstSave) {
                this.showSaveDetails(firstSave.id);
            }
        }
    },

    /** Update toolbar button states based on selection. @private */
    _updateButtonStates() {
        const hasSelection = this._selectedAccount !== null;
        const exportBtn = document.getElementById('btn-export-save');
        const backupBtn = document.getElementById('btn-backup-save');
        const restoreBtn = document.getElementById('btn-restore-save');
        const overwriteBtn = document.getElementById('btn-overwrite-save');

        if (exportBtn) exportBtn.disabled = !hasSelection;
        if (backupBtn) backupBtn.disabled = !hasSelection;
        if (restoreBtn) restoreBtn.disabled = !hasSelection;
        if (overwriteBtn) overwriteBtn.disabled = !hasSelection;
    },

    /** Get all selected saves based on current selection. @private */
    _getSelectedSaves() {
        if (!this._selectedAccount) return [];

        // 根据选中的账号 ID，获取该账号下的所有存档
        const account = this._groups[this._selectedAccount];
        if (!account) return [];

        const allSaves = [];
        if (account.has_steam) {
            allSaves.push(...account.steam_profiles);
        }
        if (account.has_modded) {
            allSaves.push(...account.modded_profiles);
        }
        return allSaves;
    },

    /** Export selected account - shows directory selection dialog first. @private */
    async _batchExport() {
        const steamId = this._selectedAccount;
        if (!steamId) {
            this._app.notifications.show(this._app.i18n.translate('select_save_first') || 'Select a save first', 'warning');
            return;
        }

        const t = (key) => this._app.i18n.translate(key);
        const container = document.getElementById('modal-container');
        if (!container) return;

        // 默认导出路径：程序根目录/exports/
        const defaultPath = this._app.getBasePath ? this._app.getBasePath() : 'E:/modmanager_project/sts-2-modmanager/exports';
        let exportPath = defaultPath;

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        container.appendChild(overlay);
        requestAnimationFrame(() => overlay.classList.add('open'));

        const close = () => { overlay.classList.remove('open'); setTimeout(() => overlay.remove(), 200); };

        const defaultZipName = steamId + ".zip";
        const defaultExportPath = exportPath;

        overlay.innerHTML = `
            <div class="modal" style="max-width:520px">
                <div class="modal__header">
                    <div style="display:flex;align-items:center;gap:12px">
                        <span style="font-size:24px">📦</span>
                        <span class="modal__title">${t('export_save') || '导出存档'}</span>
                    </div>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="modal__body" style="padding:var(--sp-lg) var(--sp-xl)">
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px;line-height:1.6">
                        ${t('export_dir_desc') || '选择导出目录和文件名，存档将导出为 ZIP 文件'}
                    </div>
                    <div style="margin-bottom:12px">
                        <label style="display:block;font-size:13px;color:var(--text-secondary);margin-bottom:6px">${t('export_directory') || '导出目录'}</label>
                        <div style="display:flex;gap:8px">
                            <input type="text" id="export-path-input" value="${defaultExportPath}" readonly
                                style="flex:1;padding:8px 12px;background:var(--bg-secondary);border:1px solid var(--border);border-radius:6px;color:var(--text-primary);font-size:13px">
                            <button class="btn btn-ghost" id="export-browse-btn" style="flex-shrink:0">${t('browse') || '浏览...'}</button>
                        </div>
                    </div>
                    <div style="margin-bottom:12px">
                        <label style="display:block;font-size:13px;color:var(--text-secondary);margin-bottom:6px">${t('export_filename') || '导出文件名'}</label>
                        <input type="text" id="export-filename-input" value="${defaultZipName}"
                            style="width:100%;padding:8px 12px;background:var(--bg-secondary);border:1px solid var(--border);border-radius:6px;color:var(--text-primary);font-size:13px;box-sizing:border-box"
                            placeholder="*.zip">
                        <div style="font-size:11px;color:var(--text-secondary);margin-top:4px">${t('export_filename_hint') || '不带路径，仅文件名'}</div>
                    </div>
                    <div style="font-size:12px;color:var(--text-secondary)">
                        ${t('export_will_create_zip') || '将创建以选定文件名命名的 ZIP 文件'}
                    </div>
                </div>
                <div class="modal__footer" style="gap:8px">
                    <button class="btn btn-ghost modal-cancel-btn">${t('cancel') || '取消'}</button>
                    <button class="btn btn-primary modal-export-btn">${t('export') || '导出'}</button>
                </div>
            </div>`;

        overlay.querySelector('.modal__close').addEventListener('click', close);
        overlay.querySelector('.modal-cancel-btn').addEventListener('click', close);
        overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });

        // 浏览按钮 - 调用后端打开目录选择对话框
        overlay.querySelector('#export-browse-btn').addEventListener('click', async () => {
            if (this._app && this._app.api) {
                try {
                    // 调用后端的目录选择对话框
                    const result = await this._app.api.selectDirectory();
                    // selectDirectory 返回格式: {success: true, path: "..."} (直接返回，不是 {data: {...}})
                    console.log('[STS2Saves] selectDirectory result:', result);
                    if (result && result.success && result.path) {
                        exportPath = result.path;
                        overlay.querySelector('#export-path-input').value = exportPath;
                        console.log('[STS2Saves] exportPath updated:', exportPath);
                    }
                } catch (e) {
                    console.warn('[STS2Saves] selectDirectory failed:', e);
                }
            }
        });

        // 导出按钮
        overlay.querySelector('.modal-export-btn').addEventListener('click', async () => {
            const exportBtn = overlay.querySelector('.modal-export-btn');
            const filenameInput = overlay.querySelector('#export-filename-input');
            exportBtn.disabled = true;
            exportBtn.textContent = t('exporting') || '导出中...';

            // 使用用户输入的文件名（如果为空则用默认 steam_id.zip）
            const customZipName = filenameInput && filenameInput.value.trim() ? filenameInput.value.trim() : steamId + ".zip";
            const finalExportPath = exportPath + "/" + customZipName;

            try {
                const result = await this._app.api.exportSave(steamId, finalExportPath);
                // Godot 返回格式: {code: 200, data: {success: true, export_path: "..."}}
                // 处理两种响应格式：{data: {...}} 或直接 {...}
                const responseData = result?.data || result;
                if (responseData && responseData.success) {
                    close();
                    this._app.notifications.show(`${t('export_success') || '导出成功'}: ${responseData.export_path}`, 'success');
                } else {
                    throw new Error(responseData?.message || result?.message || 'Export failed');
                }
            } catch (e) {
                console.warn('[STS2Saves] Export failed:', e);
                this._app.notifications.show(`${t('export_failed') || '导出失败'}: ${e.message || ''}`, 'error');
                exportBtn.disabled = false;
                exportBtn.textContent = t('export') || '导出';
            }
        });
    },

    /** Backup selected account (single call, not per-profile). @private */
    async _batchBackup() {
        // 只备份一次，传入账号 steam_id（原版 Godot 逻辑：备份整个账号目录）
        const steamId = this._selectedAccount;
        if (!steamId) {
            this._app.notifications.show(t('select_save_first') || 'Select a save first', 'warning');
            return;
        }

        const t = (key) => this._app.i18n.translate(key);

        try {
            if (this._app && this._app.api && this._app.isBackendConnected()) {
                // 传入账号 steam_id，后端会备份整个账号目录（包含所有 profile 和 modded）
                const result = await this._app.api.backupSave(steamId);
                console.log('[STS2Saves] Backup API result:', JSON.stringify(result, null, 2));
                // 处理两种响应格式：{data: {...}} 或直接 {...}
                const responseData = result?.data || result;
                if (responseData && responseData.success) {
                    console.log('[STS2Saves] Backed up account:', steamId, '->', responseData.backup_path);
                    this._app.notifications.show(
                        `${t('backup_success') || 'Backup created'}: ${responseData.backup_path}`,
                        'success'
                    );
                } else {
                    console.warn('[STS2Saves] Backup failed for', steamId, ':', responseData?.message || result?.message);
                    this._app.notifications.show(
                        `${t('backup_failed') || 'Backup failed'}: ${responseData?.message || result?.message || ''}`,
                        'error'
                    );
                }
            } else {
                console.warn('[STS2Saves] Backend not connected');
                this._app.notifications.show(t('backend_not_connected') || 'Backend not connected', 'error');
            }
        } catch (e) {
            console.error('[STS2Saves] Backup failed for', steamId, ':', e);
            this._app.notifications.show(
                `${t('backup_failed') || 'Backup failed'}: ${e.message || ''}`,
                'error'
            );
        }
    },

    /** Restore selected account (single call, not per-profile). @private */
    async _batchRestore() {
        // 只恢复一次，传入账号 steam_id（原版 Godot 逻辑：恢复整个账号目录）
        const steamId = this._selectedAccount;
        console.log('[Saves] _batchRestore called, steamId:', steamId);
        if (!steamId) {
            this._app.notifications.show(t('select_save_first') || 'Select a save first', 'warning');
            return;
        }

        const t = (key) => this._app.i18n.translate(key);

        try {
            if (this._app && this._app.api && this._app.isBackendConnected()) {
                // 先获取备份列表，让用户选择
                console.log('[Saves] Calling getSaveBackups for:', steamId);
                const result = await this._app.api.getSaveBackups(steamId);
                console.log('[Saves] getSaveBackups result:', result);
                // 处理两种响应格式：{data: {...}} 或直接 {...}
                const responseData = result?.data || result;
                console.log('[Saves] responseData:', responseData);
                if (responseData && responseData.success && responseData.backups && responseData.backups.length > 0) {
                    // 显示精美的恢复选择对话框
                    this._showRestoreDialog(steamId, responseData.backups);
                } else {
                    // 无备份或请求失败
                    console.warn('[STS2Saves] getSaveBackups failed or no backups:', responseData);
                    this._app.notifications.show(t('no_backup_found') || 'No backups found', 'warning');
                }
            } else {
                console.warn('[STS2Saves] Backend not connected');
                this._app.notifications.show(t('backend_not_connected') || 'Backend not connected', 'error');
            }
        } catch (e) {
            console.error('[STS2Saves] Restore failed for', steamId, ':', e);
            this._app.notifications.show(
                `${t('restore_failed') || 'Restore failed'}: ${e.message || ''}`,
                'error'
            );
        }
    },

    /**
     * Show beautiful restore selection dialog with Steam×Windows 11 style.
     * @param {string} steamId - Account steam_id
     * @param {Array} backups - Array of backup objects {name, path, time, type, size}
     * @private
     */
    _showRestoreDialog(steamId, backups) {
        const t = (key) => this._app.i18n.translate(key);
        const container = document.getElementById('modal-container');
        if (!container) return;

        let selectedBackup = null;
        let currentStep = 1;

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        container.appendChild(overlay);
        requestAnimationFrame(() => overlay.classList.add('open'));

        // Sort backups by time (newest first)
        backups.sort((a, b) => new Date(b.time) - new Date(a.time));

        const renderBackupList = () => {
            const listContainer = overlay.querySelector('.backup-list');
            if (!listContainer) return;

            listContainer.innerHTML = '';
            backups.forEach((backup) => {
                const item = document.createElement('div');
                item.className = `backup-item${selectedBackup === backup ? ' selected' : ''}`;

                const isAuto = backup.type === 'auto';
                const typeClass = isAuto ? 'auto' : 'manual';
                const typeLabel = isAuto ? (t('auto_backup') || 'Auto') : (t('manual_backup') || 'Manual');
                const icon = isAuto ? '🔄' : '💾';
                const sizeStr = STS2Utils.formatSize(backup.size || 0);
                const timeAgoStr = STS2Utils.timeAgo(new Date(backup.time).getTime());

                item.innerHTML = `
                    <div class="backup-item__icon">${icon}</div>
                    <div class="backup-item__content">
                        <div class="backup-item__name">${STS2Utils.escapeHtml(backup.name)}</div>
                        <div class="backup-item__meta">
                            <span class="backup-item__time">${timeAgoStr}</span>
                            <span class="backup-item__size">${sizeStr}</span>
                            <span class="backup-item__type ${typeClass}">${typeLabel}</span>
                        </div>
                    </div>
                    <button class="backup-item__delete" title="${t('delete_backup') || 'Delete backup'}">
                        ✕
                    </button>
                `;

                // Click to select
                item.addEventListener('click', (e) => {
                    if (!e.target.classList.contains('backup-item__delete')) {
                        selectedBackup = backup;
                        // 更新下一步按钮状态
                        const btn = overlay.querySelector('.modal-next-btn');
                        if (btn) btn.disabled = false;
                        renderBackupList();
                    }
                });

                // Delete button
                const deleteBtn = item.querySelector('.backup-item__delete');
                if (deleteBtn) {
                    deleteBtn.addEventListener('click', (e) => {
                        e.stopPropagation();
                        this._confirmDeleteBackup(backup, () => {
                            const idx = backups.indexOf(backup);
                            if (idx !== -1) {
                                backups.splice(idx, 1);
                            }
                            if (selectedBackup === backup) {
                                selectedBackup = null;
                                // 禁用下一步按钮
                                const btn = overlay.querySelector('.modal-next-btn');
                                if (btn) btn.disabled = true;
                            }
                            renderBackupList();
                        });
                    });
                }

                listContainer.appendChild(item);
            });
        };

        // 切换到 Step 2（云同步选项）
        const goToStep2 = () => {
            currentStep = 2;
            const modalBody = overlay.querySelector('.modal__body');
            const modalFooter = overlay.querySelector('.modal__footer');
            const stepIndicator = overlay.querySelector('.step-indicator');

            if (stepIndicator) {
                stepIndicator.innerHTML = `
                    <div class="overwrite-step-indicator">
                        <div class="step done">✓</div>
                        <div class="step-label">${t('step1_select_backup') || '选择备份'}</div>
                        <div class="step-line"></div>
                        <div class="step active">2</div>
                        <div class="step-label">${t('step2_cloud_sync') || '云同步选项'}</div>
                    </div>`;
            }

            // 隐藏备份列表和警告，显示云同步选项
            modalBody.innerHTML = `
                <div class="modal__body" style="padding:var(--sp-lg) var(--sp-xl)">
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px;line-height:1.6">
                        ${t('cloud_sync_desc_restore') || '存档恢复成功，请选择要同步到的云端位置'}
                    </div>
                    <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:16px">
                        <label class="cloud-sync-option">
                            <input type="checkbox" id="sync-gse" checked style="accent-color:var(--accent)">
                            <div class="cloud-sync-option__content">
                                <span class="cloud-sync-option__title">📁 GSE 云存档</span>
                                <span class="cloud-sync-option__hint">学习版云同步路径</span>
                            </div>
                        </label>
                        <label class="cloud-sync-option">
                            <input type="checkbox" id="sync-steam" checked style="accent-color:var(--accent)">
                            <div class="cloud-sync-option__content">
                                <span class="cloud-sync-option__title">🎮 Steam 云存档</span>
                                <span class="cloud-sync-option__hint">正版云同步路径</span>
                            </div>
                        </label>
                    </div>
                    <div class="cloud-sync-warning">
                        <span style="font-size:14px">⚠️</span>
                        <span style="font-size:12px;line-height:1.5">若不同步到云端，本地修改可能导致存档冲突或无效。请根据游玩版本选择合适的云端进行同步。</span>
                    </div>
                </div>`;

            // 更新底部按钮
            modalFooter.innerHTML = `
                <button class="btn btn-ghost modal-back-btn">${t('back') || '返回'}</button>
                <button class="btn btn-primary modal-confirm-btn">${t('confirm_restore') || '确认恢复'}</button>`;

            // 返回按钮
            overlay.querySelector('.modal-back-btn').addEventListener('click', () => {
                currentStep = 1;
                modalBody.innerHTML = `
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px;display:flex;align-items:center;gap:8px">
                        <span style="font-size:16px">⚠</span>
                        <span>${t('restore_warning') || 'Restore will overwrite current save. This action cannot be undone.'}</span>
                    </div>
                    <div class="backup-list"></div>`;
                modalFooter.innerHTML = `
                    <button class="btn btn-ghost modal-close-btn">${t('cancel') || 'Cancel'}</button>
                    <button class="btn btn-primary modal-next-btn" ${selectedBackup ? '' : 'disabled'}>${t('next_step') || '下一步 →'}</button>`;
                if (stepIndicator) stepIndicator.innerHTML = `
                    <div class="overwrite-step-indicator">
                        <div class="step active">1</div>
                        <div class="step-label">${t('step1_select_backup') || '选择备份'}</div>
                        <div class="step-line"></div>
                        <div class="step">2</div>
                        <div class="step-label">${t('step2_cloud_sync') || '云同步选项'}</div>
                    </div>`;
                renderBackupList();
                overlay.querySelector('.modal-close-btn').addEventListener('click', () => overlay.remove());
                overlay.querySelector('.modal-next-btn').addEventListener('click', goToStep2);
            });

            // 确认恢复按钮
            overlay.querySelector('.modal-confirm-btn').addEventListener('click', async () => {
                const syncGse = overlay.querySelector('#sync-gse').checked;
                const syncSteam = overlay.querySelector('#sync-steam').checked;
                const confirmBtn = overlay.querySelector('.modal-confirm-btn');
                confirmBtn.disabled = true;
                confirmBtn.textContent = t('restoring') || 'Restoring...';

                try {
                    // 执行恢复
                    const result = await this._app.api.restoreSave(steamId, selectedBackup.path);
                    console.log('[Saves] restore result:', result);
                    // 处理两种响应格式：{data: {...}} 或直接 {...}
                    const responseData = result?.data || result;
                    console.log('[Saves] responseData:', responseData);
                    if (responseData && responseData.success) {
                        overlay.remove();
                        this._app.notifications.show(t('save_restored') || 'Save restored', 'success');
                        await this.loadSaves();
                        this.updateSavesUI();

                        // 如果勾选了云同步，执行同步（独立处理，不影响主流程）
                        if (syncGse || syncSteam) {
                            let provider = '';
                            if (syncGse && syncSteam) provider = 'both';
                            else if (syncGse) provider = 'gse';
                            else if (syncSteam) provider = 'steam';
                            this._app.notifications.show(t('syncing') || '正在同步...', 'info');
                            try {
                                const syncResult = await this._app.api.syncCloud(provider, steamId);
                                const syncData = syncResult?.data || syncResult;
                                if (syncData && syncData.success) {
                                    const syncedPaths = syncData.synced_paths || [];
                                    const successCount = syncedPaths.filter(p => p.status === 'success').length;
                                    this._app.notifications.show(`成功同步到 ${successCount} 个云端位置`, 'success');
                                } else {
                                    console.warn('[Saves] sync failed:', syncData);
                                    this._app.notifications.show(`云同步失败: ${syncData?.message || '未知错误'}`, 'warning');
                                }
                            } catch (syncErr) {
                                console.warn('[Saves] sync error:', syncErr);
                                this._app.notifications.show(`云同步失败: ${syncErr.message || '未知错误'}`, 'warning');
                            }
                        }
                    } else {
                        throw new Error(responseData?.message || result?.message || 'Restore failed');
                    }
                } catch (err) {
                    console.warn('[STS2Saves] Restore failed:', err);
                    this._app.notifications.show(`${t('restore_failed') || 'Restore failed'}: ${err.message}`, 'error');
                    confirmBtn.disabled = false;
                    confirmBtn.textContent = t('confirm_restore') || '确认恢复';
                }
            });
        };

        overlay.innerHTML = `
            <div class="modal modal-lg">
                <div class="modal__header">
                    <div style="display:flex;align-items:center;gap:12px">
                        <span style="font-size:24px">⏰</span>
                        <span class="modal__title">${t('restore_from_backup') || 'Restore from Backup'}</span>
                    </div>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="step-indicator" style="padding:0 var(--sp-xl) var(--sp-md)">
                    <div class="overwrite-step-indicator">
                        <div class="step active">1</div>
                        <div class="step-label">${t('step1_select_backup') || '选择备份'}</div>
                        <div class="step-line"></div>
                        <div class="step">2</div>
                        <div class="step-label">${t('step2_cloud_sync') || '云同步选项'}</div>
                    </div>
                </div>
                <div class="modal__body">
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px;display:flex;align-items:center;gap:8px">
                        <span style="font-size:16px">⚠</span>
                        <span>${t('restore_warning') || 'Restore will overwrite current save. This action cannot be undone.'}</span>
                    </div>
                    <div class="backup-list"></div>
                </div>
                <div class="modal__footer">
                    <button class="btn btn-ghost modal-close-btn">${t('cancel') || 'Cancel'}</button>
                    <button class="btn btn-primary modal-next-btn" disabled>${t('next_step') || '下一步 →'}</button>
                </div>
            </div>
        `;

        // Wire events
        overlay.querySelector('.modal__close').addEventListener('click', () => overlay.remove());
        overlay.querySelector('.modal-close-btn').addEventListener('click', () => overlay.remove());
        overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });

        // Next button → go to Step 2
        overlay.querySelector('.modal-next-btn').addEventListener('click', goToStep2);

        // Render backup list
        renderBackupList();
    },

    /**
     * Render the left panel save list.
     *
     * Structure (matching Godot project):
     *   \ud83d\udcc1 \u8d26\u53f7 76561197960287930  \u2190 \u8d26\u53f7\u5927\u5361\u7247
     *   \u251c\u2500 \ud83d\udcc2 \u539f\u7248\u5b58\u6863
     *   \u2502  \u251c\u2500 \ud83d\udcc4 Profile 1
     *   \u2502  \u251c\u2500 \ud83d\udcc4 Profile 2
     *   \u2502  \u2514\u2500 \ud83d\udcc4 Profile 3
     *   \u2514\u2500 \ud83d\udcc2 \u6a21\u7ec4\u5b58\u6863
     *      \u251c\u2500 \ud83d\udcc4 Profile 1
     *      \u2514\u2500 \ud83d\udcc4 Profile 2
     *
     *   \u2500\u2500\u2500\u2500\u2500 \u5bfc\u5165\u5b58\u6863 \u2500\u2500\u2500\u2500\u2500
     *
     *   \ud83d\udcc1 xxx_save  \u2190 \u5bfc\u5165\u7684\u5b58\u6863\u5361\u7247
     *   \u2514\u2500 \ud83d\udcc2 \u539f\u7248\u5b58\u6863
     *      \u2514\u2500 \ud83d\udcc4 Profile 1
     */
    renderSaveList() {
        const container = document.getElementById('save-list');
        if (!container) return;

        const t = (key) => this._app.i18n.translate(key);

        if (this.saves.length === 0) {
            container.innerHTML = `
                <div class="save-empty">
                    <div class="save-empty-icon">\ud83d\udcbe</div>
                    <div class="save-empty-title">${t('no_saves') !== 'no_saves' ? t('no_saves') : 'No saves found'}</div>
                    <div class="save-empty-desc">${t('import_save_hint') !== 'import_save_hint' ? t('import_save_hint') : 'Import a save to get started'}</div>
                </div>
            `;
            return;
        }

        container.innerHTML = '';

        // \u5206\u79bb Steam \u8d26\u53f7\u548c\u5bfc\u5165\u5b58\u6863
        const steamAccounts = [];
        const importedAccounts = [];

        for (const accountId of Object.keys(this._groups)) {
            if (this._groups[accountId].is_imported) {
                importedAccounts.push(this._groups[accountId]);
            } else {
                steamAccounts.push(this._groups[accountId]);
            }
        }

        // \u6392\u5e8f\uff1aSteam \u8d26\u53f7\u6309 ID \u6392\u5e8f
        steamAccounts.sort((a, b) => {
            const aId = a.steam_id || '';
            const bId = b.steam_id || '';
            return aId.localeCompare(bId);
        });

        // ===== \u6e32\u67d3 Steam \u8d26\u53f7\u90e8\u5206 =====
        if (steamAccounts.length > 0) {
            // Steam \u5b58\u6863\u6807\u9898
            const steamTitle = document.createElement('div');
            steamTitle.className = 'save-section-title';
            steamTitle.textContent = t('steam_saves') !== 'steam_saves' ? t('steam_saves') : 'Steam \u5b58\u6863';
            container.appendChild(steamTitle);

            steamAccounts.forEach(account => {
                const isOpen = this._groupOpen[account.steam_id] !== false;
                const isSelected = this._selectedAccount === account.steam_id;

                // \u8d26\u53f7\u5927\u5361\u7247
                const accountCard = document.createElement('div');
                accountCard.className = `save-account-card${isSelected ? ' selected' : ''}`;
                accountCard.dataset.accountId = account.steam_id;

                // \u8d26\u53f7\u6807\u9898\u680f
                const titleBar = document.createElement('div');
                titleBar.className = 'save-account-title';
                titleBar.innerHTML = `
                    <span class="chevron">${isOpen ? '\u25bc' : '\u25b6'}</span>
                    <span class="account-name">${STS2Utils.escapeHtml(account.name)}</span>
                    <span class="account-badge">${account.has_steam ? '\u539f\u7248' : ''}${account.has_steam && account.has_modded ? ' + ' : ''}${account.has_modded ? '\u6a21\u7ec4' : ''}</span>
                `;

                // \u70b9\u51fb\u4e09\u89d2\u6309\u94ae\uff1a\u5c55\u5f00/\u6298\u53e0\uff08\u963b\u6b62\u5192\u6ce1\uff09
                const chevronEl = titleBar.querySelector('.chevron');
                chevronEl.addEventListener('click', (e) => {
                    e.stopPropagation();
                    this._groupOpen[account.steam_id] = !this._groupOpen[account.steam_id];
                    this.renderSaveList();
                });

                // \u70b9\u51fb\u8d26\u53f7\u5361\u7247\uff1a\u9009\u4e2d\u8d26\u53f7
                accountCard.addEventListener('click', () => {
                    this._selectedAccount = account.steam_id;
                    this.renderSaveList();
                    // \u901a\u77e5\u540e\u7aef\u9009\u4e2d\u72b6\u6001\u53d8\u5316
                    this._notifySelectionChange(account.steam_id);
                });

                accountCard.appendChild(titleBar);

                // \u8d26\u53f7\u5185\u5bb9\u533a\u57df\uff08\u539f\u7248 + \u6a21\u7ec4\uff09
                if (isOpen) {
                    const content = document.createElement('div');
                    content.className = 'save-account-content';

                    // \u4f7f\u7528\u5de6\u53f3\u5206\u680f\u5e03\u5c40
                    const columnsDiv = document.createElement('div');
                    columnsDiv.className = 'save-account-columns';

                    // \u5de6\u680f\uff1a\u539f\u7248\u5b58\u6863
                    if (account.has_steam) {
                        const vanillaColumn = document.createElement('div');
                        vanillaColumn.className = 'save-column vanilla-column';
                        vanillaColumn.innerHTML = `
                            <div class="column-header">
                                <span class="column-icon">\ud83c\udfae</span>
                                <span class="column-label">${t('vanilla_saves') !== 'vanilla_saves' ? t('vanilla_saves') : '\u539f\u7248\u5b58\u6863'}</span>
                            </div>
                        `;

                        account.steam_profiles.forEach(save => {
                            const profileCard = this._createProfileCard(save, t);
                            vanillaColumn.appendChild(profileCard);
                        });

                        columnsDiv.appendChild(vanillaColumn);
                    }

                    // \u53f3\u680f\uff1a\u6a21\u7ec4\u5b58\u6863
                    if (account.has_modded) {
                        const moddedColumn = document.createElement('div');
                        moddedColumn.className = 'save-column modded-column';
                        moddedColumn.innerHTML = `
                            <div class="column-header">
                                <span class="column-icon">\ud83d\udd27</span>
                                <span class="column-label">${t('modded_saves') !== 'modded_saves' ? t('modded_saves') : '\u6a21\u7ec4\u5b58\u6863'}</span>
                            </div>
                        `;

                        account.modded_profiles.forEach(save => {
                            const profileCard = this._createProfileCard(save, t);
                            moddedColumn.appendChild(profileCard);
                        });

                        columnsDiv.appendChild(moddedColumn);
                    }

                    content.appendChild(columnsDiv);
                    accountCard.appendChild(content);
                }

                container.appendChild(accountCard);
            });
        }

        // ===== \u6e32\u67d3\u5bfc\u5165\u5b58\u6863\u90e8\u5206 =====
        if (importedAccounts.length > 0) {
            // \u5206\u9694\u7ebf
            const divider = document.createElement('div');
            divider.className = 'save-section-divider';
            divider.innerHTML = `
                <span>${t('imported_saves') !== 'imported_saves' ? t('imported_saves') : '\u5bfc\u5165\u5b58\u6863'}</span>
            `;
            container.appendChild(divider);

            // \u904d\u5386\u5bfc\u5165\u8d26\u53f7\uff0c\u9700\u8981\u4fdd\u7559 accountId
            for (const accountId of Object.keys(this._groups)) {
                const account = this._groups[accountId];
                if (!account.is_imported) continue;

                const isOpen = this._groupOpen[accountId] !== false;
                const isSelected = this._selectedAccount === accountId;

                const accountCard = document.createElement('div');
                accountCard.className = `save-account-card${isSelected ? ' selected' : ''}`;
                accountCard.dataset.accountId = accountId;

                const titleBar = document.createElement('div');
                titleBar.className = 'save-account-title';
                titleBar.innerHTML = `
                    <span class="chevron">${isOpen ? '\u25bc' : '\u25b6'}</span>
                    <span class="account-name">${STS2Utils.escapeHtml(account.name)}</span>
                    <span class="account-badge">${account.has_steam ? '\u539f\u7248' : ''}${account.has_steam && account.has_modded ? ' + ' : ''}${account.has_modded ? '\u6a21\u7ec4' : ''}</span>
                `;

                // \u70b9\u51fb\u4e09\u89d2\u6309\u94ae\uff1a\u5c55\u5f00/\u6298\u53e0\uff08\u963b\u6b62\u5192\u6ce1\uff09
                const chevronEl = titleBar.querySelector('.chevron');
                chevronEl.addEventListener('click', (e) => {
                    e.stopPropagation();
                    this._groupOpen[accountId] = !this._groupOpen[accountId];
                    this.renderSaveList();
                });

                // \u70b9\u51fb\u8d26\u53f7\u5361\u7247\uff1a\u9009\u4e2d\u8d26\u53f7
                accountCard.addEventListener('click', () => {
                    this._selectedAccount = accountId;
                    this.renderSaveList();
                    // \u901a\u77e5\u540e\u7aef\u9009\u4e2d\u72b6\u6001\u53d8\u5316
                    this._notifySelectionChange(accountId);
                });

                accountCard.appendChild(titleBar);

                if (isOpen) {
                    const content = document.createElement('div');
                    content.className = 'save-account-content';

                    const columnsDiv = document.createElement('div');
                    columnsDiv.className = 'save-account-columns';

                    if (account.has_steam) {
                        const vanillaColumn = document.createElement('div');
                        vanillaColumn.className = 'save-column vanilla-column';
                        vanillaColumn.innerHTML = `
                            <div class="column-header">
                                <span class="column-icon">\ud83d\udcc4</span>
                                <span class="column-label">${t('vanilla_saves') !== 'vanilla_saves' ? t('vanilla_saves') : '\u539f\u7248\u5b58\u6863'}</span>
                            </div>
                        `;

                        account.steam_profiles.forEach(save => {
                            const profileCard = this._createProfileCard(save, t);
                            vanillaColumn.appendChild(profileCard);
                        });

                        columnsDiv.appendChild(vanillaColumn);
                    }

                    if (account.has_modded) {
                        const moddedColumn = document.createElement('div');
                        moddedColumn.className = 'save-column modded-column';
                        moddedColumn.innerHTML = `
                            <div class="column-header">
                                <span class="column-icon">\ud83d\udd27</span>
                                <span class="column-label">${t('modded_saves') !== 'modded_saves' ? t('modded_saves') : '\u6a21\u7ec4\u5b58\u6863'}</span>
                            </div>
                        `;

                        account.modded_profiles.forEach(save => {
                            const profileCard = this._createProfileCard(save, t);
                            moddedColumn.appendChild(profileCard);
                        });

                        columnsDiv.appendChild(moddedColumn);
                    }

                    content.appendChild(columnsDiv);
                    accountCard.appendChild(content);
                }

                container.appendChild(accountCard);
            }
        }
    },

    /**
     * Create a profile card element.
     * @private
     */
    _createProfileCard(save, t) {
        const el = document.createElement('div');
        el.className = 'save-profile-card';

        // \u89d2\u8272\u56fe\u6807
        let charIcon = '';
        // \u5bfc\u5165\u5b58\u6863\u7684 profile \u662f\u6570\u5b57\uff0cSteam \u5b58\u6863\u7684 profiles \u662f\u5bf9\u8c61\u6570\u7ec4
        if (save.profiles && save.profiles.length > 0) {
            const profile = save.profiles[0];
            if (typeof profile === 'object' && profile.character_stats) {
                const charName = Object.keys(profile.character_stats)[0];
                const iconMap = {
                    '\u94c1\u7532\u6218\u58eb': '\u2694',
                    '\u9759\u9ed8\u730e\u624b': '\ud83c\udfaf',
                    '\u50a8\u541b': '\ud83d\udc51',
                    '\u4ea1\u7075\u5951\u7ea6\u5e08': '\ud83d\udc80',
                    '\u6545\u969c\u673a\u5668\u4eba': '\u2699'
                };
                charIcon = iconMap[charName] || '';
            }
        }

        // \u5b58\u6863\u540d\u79f0\uff1a\u76f4\u63a5\u4f7f\u7528 profile \u5b57\u6bb5\u663e\u793a\u4e3a"\u5b58\u6863 X"\u683c\u5f0f
        const profileNum = save.profile || 1;
        const profileName = `\u5b58\u6863${profileNum}`;

        el.innerHTML = `
            <span class="profile-icon">${charIcon}</span>
            <span class="profile-name" title="${STS2Utils.escapeHtml(profileName)}">${STS2Utils.escapeHtml(profileName)}</span>
            <span class="profile-date">${STS2Utils.timeAgo(save.date)}</span>
        `;

        el.addEventListener('click', () => {
            this.showSaveDetails(save.id);
        });

        return el;
    },

    /**
     * Show save details in the right panel (view only, no selection).
     * @param {string} id
     */
    showSaveDetails(id) {
        const save = this.saves.find(s => s.id === id);
        if (!save) return;

        const panel = document.getElementById('save-details');
        if (!panel) return;
        const body = panel.querySelector('.panel-body');
        if (!body) return;

        const t = (key) => this._app.i18n.translate(key);

        // Steam 存档：数据直接在 save 对象上
        // 导入存档：数据在 save.profiles 数组或通过 save.profile 索引
        const profileNum = save.profile || 1;

        // 构建 activeProfile 对象，统一数据访问
        // 后端返回的字段：play_time, discovered_cards, discovered_relics, floors_climbed, characters, character_stats, total_wins, total_losses
        const activeProfile = {
            profile_num: profileNum,
            game_time: save.play_time || save.game_time || 0,
            discovered_cards: save.discovered_cards || 0,
            discovered_relics: save.discovered_relics || 0,
            floors_climbed: save.floors_climbed || 0,
            total_wins: save.total_wins || 0,
            total_losses: save.total_losses || 0,
            characters: save.characters || [],
            character_stats: save.character_stats || {}
        };

        // Profile selector (仅当有多个 profile 时显示)
        let profileSelectorHtml = '';
        const availableProfiles = save.profiles || [profileNum];
        const profileNums = Array.isArray(availableProfiles) ? availableProfiles : [profileNum];

        if (profileNums.length > 1) {
            const opts = profileNums.map(pn =>
                `<option value="${pn}" ${pn === profileNum ? 'selected' : ''}>${t('profile') !== 'profile' ? t('profile') : 'Profile'} ${pn}</option>`
            ).join('');
            profileSelectorHtml = `
                <div class="profile-selector">
                    <label>${t('profile') !== 'profile' ? t('profile') : 'Profile'}:</label>
                    <select id="save-profile-select">${opts}</select>
                </div>
            `;
        } else if (profileNums.length === 1) {
            profileSelectorHtml = `
                <div class="profile-selector">
                    <label>${t('profile') !== 'profile' ? t('profile') : 'Profile'}:</label>
                    <span style="color:var(--text-primary);font-size:var(--font-sm)">存档${profileNums[0]}</span>
                </div>
            `;
        }

        // Info grid
        const game_time_str = activeProfile ? this._formatGameTime(activeProfile.game_time) : '--';
        const floors_climbed_str = activeProfile ? activeProfile.floors_climbed : '--';
        const total_wins_str = activeProfile ? activeProfile.total_wins : '--';
        const total_losses_str = activeProfile ? activeProfile.total_losses : '--';
        const infoGridHtml = `
            <div class="save-info-grid">
                <div class="save-info-cell">
                    <span class="save-info-label">${t('save_name') !== 'save_name' ? t('save_name') : 'Name'}</span>
                    <span class="save-info-value">${STS2Utils.escapeHtml(save.name)}</span>
                </div>
                <div class="save-info-cell">
                    <span class="save-info-label">${t('save_date') !== 'save_date' ? t('save_date') : 'Date'}</span>
                    <span class="save-info-value">${STS2Utils.formatDate(save.date)}</span>
                </div>
                <div class="save-info-cell">
                    <span class="save-info-label">${t('save_size') !== 'save_size' ? t('save_size') : 'Size'}</span>
                    <span class="save-info-value">${STS2Utils.formatSize(save.size_bytes || 0)}</span>
                </div>
                <div class="save-info-cell">
                    <span class="save-info-label">${t('save_type') !== 'save_type' ? t('save_type') : 'Type'}</span>
                    <span class="save-info-value">${save.type === 'steam' ? 'Steam' : t('imported') !== 'imported' ? t('imported') : 'Imported'}${save.modded ? ' (' + (t('modded') !== 'modded' ? t('modded') : 'Modded') + ')' : ''}</span>
                </div>
                <div class="save-info-cell">
                    <span class="save-info-label">${t('game_time') !== 'game_time' ? t('game_time') : 'Play Time'}</span>
                    <span class="save-info-value">${game_time_str}</span>
                </div>
                <div class="save-info-cell">
                    <span class="save-info-label">累计爬楼</span>
                    <span class="save-info-value">${floors_climbed_str}</span>
                </div>
                <div class="save-info-cell">
                    <span class="save-info-label">${t('discovered_cards') !== 'discovered_cards' ? t('discovered_cards') : 'Cards Discovered'}</span>
                    <span class="save-info-value">${activeProfile ? activeProfile.discovered_cards : '--'}</span>
                </div>
                <div class="save-info-cell">
                    <span class="save-info-label">${t('discovered_relics') !== 'discovered_relics' ? t('discovered_relics') : 'Relics Discovered'}</span>
                    <span class="save-info-value">${activeProfile ? activeProfile.discovered_relics : '--'}</span>
                </div>
                <div class="save-info-cell">
                    <span class="save-info-label">总胜场</span>
                    <span class="save-info-value" style="color: var(--color-success)">${total_wins_str}</span>
                </div>
                <div class="save-info-cell">
                    <span class="save-info-label">总败场</span>
                    <span class="save-info-value" style="color: var(--color-danger)">${total_losses_str}</span>
                </div>
                <div class="save-info-cell">
                    <span class="save-info-label">${t('save_path') !== 'save_path' ? t('save_path') : 'Path'}</span>
                    <span class="save-info-value" style="font-size:var(--font-xs);word-break:break-all">${STS2Utils.escapeHtml(save.path)}</span>
                </div>
            </div>
        `;

        // Character stats
        const charStatsHtml = activeProfile ? this._renderCharStats(activeProfile) : '';

        // Long-press delete area
        const deleteAreaId = 'save-longpress-delete';

        body.innerHTML = `
            <div class="save-details">
                ${infoGridHtml}
                ${profileSelectorHtml}
                ${charStatsHtml}
                <div class="save-actions">
                    <button class="btn btn-ghost" id="btn-save-export-detail">${t('export') !== 'export' ? t('export') : 'Export'}</button>
                    <button class="btn btn-ghost" id="btn-save-backup-detail">${t('backup') !== 'backup' ? t('backup') : 'Backup'}</button>
                    <button class="btn btn-danger" id="${deleteAreaId}">${t('delete') !== 'delete' ? t('delete') : 'Delete'}</button>
                </div>
                <div class="longpress-bar" id="longpress-bar" style="display:none">
                    <div class="longpress-bar-fill" id="longpress-fill"></div>
                </div>
                <div class="longpress-bar-label" id="longpress-label" style="display:none">
                    ${t('hold_to_delete') !== 'hold_to_delete' ? t('hold_to_delete') : 'Hold for 1.5s to confirm delete'}
                </div>
            </div>
        `;

        // Profile selector event
        const profileSelect = document.getElementById('save-profile-select');
        if (profileSelect) {
            profileSelect.addEventListener('change', () => {
                this.current_profile = parseInt(profileSelect.value, 10);
                this.showSaveDetails(id);
            });
        }

        // Export & backup buttons
        const exportDetailBtn = document.getElementById('btn-save-export-detail');
        if (exportDetailBtn) exportDetailBtn.addEventListener('click', () => this.exportSave(id));

        const backupDetailBtn = document.getElementById('btn-save-backup-detail');
        if (backupDetailBtn) backupDetailBtn.addEventListener('click', () => this.backupSave(id));

        // Long-press delete
        this._setupLongpressDelete(id, deleteAreaId);

        // Re-render list to update any state-dependent styling
        this.renderSaveList();
    },

    /**
     * Render character stats cards for a save profile.
     * @param {object} profile
     * @returns {string} HTML
     * @private
     */
    _renderCharStats(profile) {
        const t = (key) => this._app.i18n.translate(key);
        const stats = profile.character_stats || {};
        const chars = Object.keys(stats);

        // \u5982\u679c\u6ca1\u6709\u89d2\u8272\u6570\u636e\uff0c\u4f46\u6709\u603b\u80dc\u8d25\u6570\u636e\uff0c\u663e\u793a\u6c47\u603b
        if (chars.length === 0 && (profile.total_wins > 0 || profile.total_losses > 0)) {
            return `
                <div class="char-stats-section">
                    <div class="char-stats-header">
                        <span class="char-stats-title">\ud83d\udcca \u6218\u6597\u7edf\u8ba1</span>
                    </div>
                    <div class="char-stats-summary">
                        <div class="char-stat-box">
                            <div class="char-stat-value" style="color: var(--color-success)">${profile.total_wins}</div>
                            <div class="char-stat-label">\u603b\u80dc\u573a</div>
                        </div>
                        <div class="char-stat-box">
                            <div class="char-stat-value" style="color: var(--color-danger)">${profile.total_losses}</div>
                            <div class="char-stat-label">\u603b\u8d25\u573a</div>
                        </div>
                        <div class="char-stat-box">
                            <div class="char-stat-value" style="color: var(--color-primary)">${profile.floors_climbed}</div>
                            <div class="char-stat-label">\u6700\u9ad8\u5c42\u6570</div>
                        </div>
                    </div>
                </div>
            `;
        }

        if (chars.length === 0) return '';

        // \u8fc7\u6ee4\u6389 RANDOM_CHARACTER \u7b49\u65e0\u6548\u89d2\u8272\uff08\u53ef\u80fd\u662f\u6a21\u7ec4\u6216\u968f\u673a\u9009\u62e9\u529f\u80fd\u4ea7\u751f\uff09
        const filteredChars = chars.filter(c => c !== 'CHARACTER.RANDOM_CHARACTER');
        if (filteredChars.length === 0) return '';

        // \u8ba1\u7b97\u603b\u80dc\u8d25
        let totalWins = 0;
        let totalLosses = 0;
        filteredChars.forEach(charName => {
            const s = stats[charName];
            totalWins += s.wins || 0;
            totalLosses += s.losses || 0;
        });

        const cards = filteredChars.map(charName => {
            const s = stats[charName];
            const charDisplayName = this._charNames[charName] || charName;
            const icon = this._charIcons[charName] || this._charIcons[charDisplayName] || '⚔';
            const winRate = (s.wins + s.losses) > 0 ? ((s.wins / (s.wins + s.losses)) * 100).toFixed(1) : 0;

            return `
                <div class="char-stat-card">
                    <div class="char-stat-card-header">
                        <div class="char-stat-icon">${icon}</div>
                        <div class="char-stat-name">${STS2Utils.escapeHtml(charDisplayName)}</div>
                    </div>
                    <div class="char-stat-card-body">
                        <div class="char-stat-row">
                            <span class="char-stat-label">\u80dc\u573a</span>
                            <span class="char-stat-value wins">${s.wins}</span>
                        </div>
                        <div class="char-stat-row">
                            <span class="char-stat-label">\u8d25\u573a</span>
                            <span class="char-stat-value losses">${s.losses}</span>
                        </div>
                        <div class="char-stat-row">
                            <span class="char-stat-label">\u80dc\u7387</span>
                            <span class="char-stat-value winrate">${winRate}%</span>
                        </div>
                    </div>
                </div>
            `;
        }).join('');

        return `
            <div class="char-stats-section">
                <div class="char-stats-header">
                    <span class="char-stats-title">\u2694\ufe0f \u89d2\u8272\u7edf\u8ba1</span>
                </div>
                <div class="char-stats-summary">
                    <div class="char-stat-box">
                        <div class="char-stat-value" style="color: var(--color-success)">${totalWins}</div>
                        <div class="char-stat-label">\u603b\u80dc\u573a</div>
                    </div>
                    <div class="char-stat-box">
                        <div class="char-stat-value" style="color: var(--color-danger)">${totalLosses}</div>
                        <div class="char-stat-label">\u603b\u8d25\u573a</div>
                    </div>
                    <div class="char-stat-box">
                        <div class="char-stat-value" style="color: var(--color-primary)">${profile.floors_climbed}</div>
                        <div class="char-stat-label">\u7d2f\u8ba1\u722c\u697c</div>
                    </div>
                </div>
                <div class="char-stats-grid">${cards}</div>
            </div>
        `;
    },

    /**
     * Format game time in seconds to human-readable string.
     * @param {number} seconds
     * @returns {string}
     * @private
     */
    _formatGameTime(seconds) {
        if (!seconds || seconds <= 0) return '0h';
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        if (h === 0) return `${m}m`;
        return `${h}h ${m}m`;
    },

    // ── Actions ───────────────────────────────────────────────────

    /**
     * Import a save file.
     */
    importSave() {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = '.save,.zip';
        input.addEventListener('change', async (e) => {
            const file = e.target.files[0];
            if (!file) return;

            const t = (key) => this._app.i18n.translate(key);

            // Try backend API first
            if (this._app && this._app.api && this._app.isBackendConnected()) {
                try {
                    const reader = new FileReader();
                    const dataBase64 = await new Promise((resolve, reject) => {
                        reader.onload = () => {
                            const base64 = reader.result.split(',')[1];
                            resolve(base64);
                        };
                        reader.onerror = reject;
                        reader.readAsDataURL(file);
                    });
                    await this._app.api.importSave(file.name, dataBase64);
                    this._app.notifications.show(
                        `${t('save_imported') !== 'save_imported' ? t('save_imported') : 'Save imported'}: ${file.name}`,
                        'success'
                    );
                    await this.loadSaves();
                    this.updateSavesUI();
                    return;
                } catch (err) {
                    console.warn('[STS2Saves] API importSave failed, falling back:', err);
                }
            }

            // Fallback to local state
            const newSave = {
                id: 'save-' + STS2Utils.generateId(),
                steam_id: null,
                name: file.name.replace(/\.(save|zip)$/i, ''),
                type: 'imported',
                modded: false,
                date: new Date().toISOString(),
                size: file.size || Math.floor(Math.random() * 3000000) + 500000,
                path: `saves\\${file.name}`,
                profiles: [{
                    profile_num: 1,
                    game_time: 0,
                    discovered_cards: 0,
                    discovered_relics: 0,
                    character_stats: {}
                }]
            };

            this.saves.push(newSave);
            this._app.store.set('saves_data', this.saves);
            this._buildGroups();

            this._app.notifications.show(
                `${t('save_imported') !== 'save_imported' ? t('save_imported') : 'Save imported'}: ${newSave.name}`,
                'success'
            );

            this.selected_save_id = newSave.id;
            this.updateSavesUI();
        });
        input.click();
    },

    /**
     * Import save files from drag-and-drop (bypasses file picker).
     * @param {File[]} files
     */
    async importSaveFromFiles(files) {
        const zips = files.filter(f => f.name.toLowerCase().endsWith('.zip') || f.name.toLowerCase().endsWith('.save'));
        if (!zips.length) {
            this._app.notifications.show(
                this._app.i18n.translate('only_zip_supported') || '\u4ec5\u652f\u6301 .zip \u6587\u4ef6',
                'warning', 3000
            );
            return;
        }
        // Import the first file (saves are single-file imports)
        const file = zips[0];
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const reader = new FileReader();
                const dataBase64 = await new Promise((resolve, reject) => {
                    reader.onload = () => resolve(reader.result.split(',')[1]);
                    reader.onerror = reject;
                    reader.readAsDataURL(file);
                });
                await this._app.api.importSave(file.name, dataBase64);
                this._app.notifications.show(
                    `${this._app.i18n.translate('save_imported') !== 'save_imported' ? this._app.i18n.translate('save_imported') : 'Save imported'}: ${file.name}`,
                    'success'
                );
                await this.loadSaves();
                this.updateSavesUI();
                return;
            } catch (err) {
                console.warn('[STS2Saves] API importSave failed, falling back:', err);
            }
        }
        // Fallback: same as importSave local path
        const newSave = {
            id: 'save-' + STS2Utils.generateId(),
            steam_id: null,
            name: file.name.replace(/\.(save|zip)$/i, ''),
            type: 'imported',
            modded: false,
            date: new Date().toISOString(),
            size: file.size || Math.floor(Math.random() * 3000000) + 500000,
            path: `saves\\${file.name}`,
            profiles: [{ id: 'profile1', saves: [] }],
        };
        this.saves.push(newSave);
        this._app.store.set('saves_data', this.saves);
        this._buildGroups();
        this._app.notifications.show(
            `${this._app.i18n.translate('save_imported') !== 'save_imported' ? this._app.i18n.translate('save_imported') : 'Save imported'}: ${newSave.name}`,
            'success'
        );
        this.selected_save_id = newSave.id;
        this.updateSavesUI();
    },

    /**
     * Export a save - calls backend to show native file dialog.
     * @param {string} id
     */
    async exportSave(id) {
        const save = this.saves.find(s => s.id === id);
        if (!save) return;

        const t = (key) => this._app.i18n.translate(key);

        // Try backend API first - backend will show native file dialog
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                // 调用后端导出 API，后端会弹出原生文件对话框
                const result = await this._app.api.exportSave(id);
                // Godot 返回格式: {code: 200, data: {success: true, export_path: '...'}}
                // 处理两种响应格式：{data: {...}} 或直接 {...}
                    const responseData = result?.data || result;
                    if (responseData && responseData.success) {
                    const finalPath = responseData.export_path || '';
                    console.log('[STS2Saves] Exported to:', finalPath);
                    this._app.notifications.show(
                        `${t('save_exported') !== 'save_exported' ? t('save_exported') : 'Save exported'}: ${save.name}.zip`,
                        'success'
                    );
                    // 显示导出位置提示
                    this._app.notifications.show(
                        `${t('export_location') !== 'export_location' ? t('export_location') : 'Exported to'}: ${finalPath}`,
                        'info', 5000
                    );
                } else {
                    // 用户取消了对话框选择
                    if (responseData?.message === 'User canceled') {
                        return;
                    }
                    throw new Error(responseData?.message || result?.message || 'Export failed');
                }
                return;
            } catch (err) {
                console.warn('[STS2Saves] API exportSave failed:', err);
                this._app.notifications.show(t('export_failed') || 'Export failed', 'error');
            }
        }

        // Fallback (simulated)
        this._app.notifications.show(
            `${t('save_exported') !== 'save_exported' ? t('save_exported') : 'Save exported'}: ${save.name}.zip`,
            'success'
        );
    },

    /**
     * Show browser native file save dialog.
     * Note: This uses a hidden <a> element trick since browsers don't expose
     * a true "save as" dialog to JavaScript.
     * @param {string} suggestedName - Suggested filename
     * @returns {Promise<string|null>} - Returns the chosen path or null if canceled
     * @private
     */
    async _showSaveFileDialog(suggestedName) {
        return new Promise((resolve) => {
            // 创建一个隐藏的 file input 用于选择保存位置
            const input = document.createElement('input');
            input.type = 'file';
            // 注意：浏览器出于安全原因不允许直接设置保存路径
            // 这里我们使用一个变通方法：创建一个下载链接
            // 但真正的路径选择需要后端配合，前端只能提供文件名
            const fileName = (suggestedName || 'save') + '.zip';

            // 创建一个临时对话框让用户确认
            const overlay = document.createElement('div');
            overlay.className = 'modal-overlay';
            overlay.innerHTML = `
                <div class="modal" style="max-width:400px">
                    <div class="modal__header">
                        <span class="modal__title">${this._app.i18n.translate('export_save') || '导出存档'}</span>
                        <button class="modal__close">&times;</button>
                    </div>
                    <div class="modal__body" style="padding:var(--sp-lg) var(--sp-xl)">
                        <div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px">
                            ${this._app.i18n.translate('export_path_hint') || '请选择保存位置（浏览器将下载到默认下载目录）'}
                        </div>
                        <div style="display:flex;flex-direction:column;gap:8px">
                            <label style="font-size:13px;color:var(--text-primary)">${this._app.i18n.translate('file_name') || '文件名'}:</label>
                            <input type="text" id="export-filename" value="${fileName}"
                                style="padding:8px 12px;border:1px solid var(--border-color);border-radius:var(--radius-md);background:var(--bg-surface);color:var(--text-primary);font-size:13px" />
                        </div>
                    </div>
                    <div class="modal__footer" style="gap:8px">
                        <button class="btn btn-ghost modal-cancel-btn">${this._app.i18n.translate('cancel') || '取消'}</button>
                        <button class="btn btn-primary modal-confirm-btn">${this._app.i18n.translate('export') || '导出'}</button>
                    </div>
                </div>
            `;

            document.getElementById('modal-container')?.appendChild(overlay);
            requestAnimationFrame(() => overlay.classList.add('open'));

            const close = () => overlay.remove();
            overlay.querySelector('.modal__close').addEventListener('click', () => { close(); resolve(null); });
            overlay.querySelector('.modal-cancel-btn').addEventListener('click', () => { close(); resolve(null); });
            overlay.addEventListener('click', (e) => { if (e.target === overlay) { close(); resolve(null); } });

            overlay.querySelector('.modal-confirm-btn').addEventListener('click', () => {
                const filename = document.getElementById('export-filename').value.trim() || fileName;
                close();
                // 返回文件名（包含 .zip 扩展名）
                resolve(filename.endsWith('.zip') ? filename : filename + '.zip');
            });
        });
    },

    /**
     * Backup a save - creates backup in backend backups directory.
     * @param {string} id
     */
    async backupSave(id) {
        const save = this.saves.find(s => s.id === id);
        if (!save) return;

        const t = (key) => this._app.i18n.translate(key);

        // Try backend API first
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const result = await this._app.api.backupSave(id);
                // 处理两种响应格式
                const responseData = result?.data || result;
                if (responseData && responseData.success) {
                    const backupPath = responseData.backup_path || '';
                    console.log('[Saves] Backed up to:', backupPath);
                    this._app.notifications.show(
                        `${t('backup_success') !== 'backup_success' ? t('backup_success') : 'Backup created successfully'}: ${save.name}`,
                        'success'
                    );
                    // 重新加载存档列表以刷新备份状态
                    await this.loadSaves();
                    this.updateSavesUI();
                } else {
                    throw new Error(responseData?.message || result?.message || 'Backup failed');
                }
                return;
            } catch (err) {
                console.warn('[Saves] API backupSave failed:', err);
                this._app.notifications.show(t('backup_failed') || 'Backup failed', 'error');
            }
        }

        // Fallback (simulated)
        this._app.notifications.show(
            `${t('save_backed_up') !== 'save_backed_up' ? t('save_backed_up') : 'Save backed up'}: ${save.name}`,
            'success'
        );
    },

    /**
     * Restore from a backup - opens modal with list of available backups.
     * @param {string} id
     */
    async restoreSave(id) {
        const save = this.saves.find(s => s.id === id);
        if (!save) return;

        const t = (key) => this._app.i18n.translate(key);

        // Use steam_id for API call (not full save id)
        const steamId = save.steam_id || id;

        // Try backend API first - get list of backups
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const result = await this._app.api.getSaveBackups(steamId);
                console.log('[STS2Saves] getSaveBackups result:', result);
                // 处理两种响应格式：{data: {...}} 或直接 {...}
                const responseData = result?.data || result;
                console.log('[STS2Saves] responseData:', responseData);
                if (responseData && responseData.success && responseData.backups && responseData.backups.length > 0) {
                    // Show backup selection modal
                    this._showRestoreBackupModal(id, save, responseData.backups);
                    return;
                } else {
                    // No backups found
                    console.log('[STS2Saves] No backups found, responseData:', responseData);
                    this._app.notifications.show(t('no_backup_found') || 'No backups found', 'warning');
                    return;
                }
            } catch (err) {
                console.warn('[Saves] API getSaveBackups failed:', err);
            }
        }

        // Fallback (simulated)
        this._app.notifications.show(t('no_backup_found') || 'No backups found', 'warning');
    },

    _showRestoreBackupModal(saveId, save, backups) {
        const t = (key) => this._app.i18n.translate(key);
        const container = document.getElementById('modal-container');
        if (!container) return;

        let selectedBackupIndex = -1;
        let currentStep = 1;

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        container.appendChild(overlay);
        requestAnimationFrame(() => overlay.classList.add('open'));

        const renderBackupList = () => {
            const listContainer = overlay.querySelector('.backup-list');
            if (!listContainer) return;

            listContainer.innerHTML = '';
            backups.forEach((backup, index) => {
                const item = document.createElement('div');
                item.className = `backup-item${index === selectedBackupIndex ? ' selected' : ''}`;
                item.dataset.index = index;

                const typeClass = backup.type === 'auto' ? 'auto' : 'manual';
                const typeLabel = backup.type === 'auto' ? (t('auto_backup') || 'Auto') : (t('manual_backup') || 'Manual');
                const icon = backup.type === 'auto' ? '🔄' : '💾';
                const sizeStr = STS2Utils.formatSize(backup.size || 0);

                item.innerHTML = `
                    <div class="backup-item__icon">${icon}</div>
                    <div class="backup-item__content">
                        <div class="backup-item__name">${STS2Utils.escapeHtml(backup.name)}</div>
                        <div class="backup-item__meta">
                            <span class="backup-item__time">${STS2Utils.escapeHtml(backup.time)}</span>
                            <span class="backup-item__size">${sizeStr}</span>
                            <span class="backup-item__type ${typeClass}">${typeLabel}</span>
                        </div>
                    </div>
                    <button class="backup-item__delete" data-index="${index}" title="${t('delete_backup') || 'Delete backup'}">
                        ✕
                    </button>
                `;

                // Click to select
                item.addEventListener('click', (e) => {
                    if (!e.target.classList.contains('backup-item__delete')) {
                        selectedBackupIndex = index;
                        const btn = overlay.querySelector('.modal-next-btn');
                        if (btn) btn.disabled = false;
                        renderBackupList();
                    }
                });

                // Delete button
                const deleteBtn = item.querySelector('.backup-item__delete');
                if (deleteBtn) {
                    deleteBtn.addEventListener('click', (e) => {
                        e.stopPropagation();
                        this._confirmDeleteBackup(backup, () => {
                            backups.splice(index, 1);
                            if (selectedBackupIndex >= backups.length) {
                                selectedBackupIndex = Math.max(0, backups.length - 1);
                            }
                            if (selectedBackupIndex < 0 || backups.length === 0) {
                                const btn = overlay.querySelector('.modal-next-btn');
                                if (btn) btn.disabled = true;
                            }
                            renderBackupList();
                        });
                    });
                }

                listContainer.appendChild(item);
            });
        };

        // 切换到 Step 2（云同步选项）
        const goToStep2 = () => {
            currentStep = 2;
            const modalBody = overlay.querySelector('.modal__body');
            const modalFooter = overlay.querySelector('.modal__footer');
            const stepIndicator = overlay.querySelector('.step-indicator');

            if (stepIndicator) {
                stepIndicator.innerHTML = `
                    <div class="overwrite-step-indicator">
                        <div class="step done">✓</div>
                        <div class="step-label">${t('step1_select_backup') || '选择备份'}</div>
                        <div class="step-line"></div>
                        <div class="step active">2</div>
                        <div class="step-label">${t('step2_cloud_sync') || '云同步选项'}</div>
                    </div>`;
            }

            modalBody.innerHTML = `
                <div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px;line-height:1.6">
                    ${t('cloud_sync_desc_restore') || '存档恢复成功，请选择要同步到的云端位置'}
                </div>
                <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:16px">
                    <label class="cloud-sync-option">
                        <input type="checkbox" id="sync-gse" checked style="accent-color:var(--accent)">
                        <div class="cloud-sync-option__content">
                            <span class="cloud-sync-option__title">📁 GSE 云存档</span>
                            <span class="cloud-sync-option__hint">学习版云同步路径</span>
                        </div>
                    </label>
                    <label class="cloud-sync-option">
                        <input type="checkbox" id="sync-steam" checked style="accent-color:var(--accent)">
                        <div class="cloud-sync-option__content">
                            <span class="cloud-sync-option__title">🎮 Steam 云存档</span>
                            <span class="cloud-sync-option__hint">正版云同步路径</span>
                        </div>
                    </label>
                </div>
                <div class="cloud-sync-warning">
                    <span style="font-size:14px">⚠️</span>
                    <span style="font-size:12px;line-height:1.5">若不同步到云端，本地修改可能导致存档冲突或无效。请根据游玩版本选择合适的云端进行同步。</span>
                </div>`;

            modalFooter.innerHTML = `
                <button class="btn btn-ghost modal-back-btn">${t('back') || '返回'}</button>
                <button class="btn btn-primary modal-confirm-btn">${t('confirm_restore') || '确认恢复'}</button>`;

            overlay.querySelector('.modal-back-btn').addEventListener('click', () => {
                currentStep = 1;
                modalBody.innerHTML = `
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px">
                        ⚠ ${t('restore_warning') || 'Restore will overwrite current save. This action cannot be undone.'}
                    </div>
                    <div class="backup-list"></div>`;
                modalFooter.innerHTML = `
                    <button class="btn btn-ghost modal-close-btn">${t('cancel') || 'Cancel'}</button>
                    <button class="btn btn-primary modal-next-btn" ${selectedBackupIndex >= 0 ? '' : 'disabled'}>${t('next_step') || '下一步 →'}</button>`;
                if (stepIndicator) stepIndicator.innerHTML = `
                    <div class="overwrite-step-indicator">
                        <div class="step active">1</div>
                        <div class="step-label">${t('step1_select_backup') || '选择备份'}</div>
                        <div class="step-line"></div>
                        <div class="step">2</div>
                        <div class="step-label">${t('step2_cloud_sync') || '云同步选项'}</div>
                    </div>`;
                renderBackupList();
                overlay.querySelector('.modal-close-btn').addEventListener('click', () => overlay.remove());
                overlay.querySelector('.modal-next-btn').addEventListener('click', goToStep2);
            });

            overlay.querySelector('.modal-confirm-btn').addEventListener('click', async () => {
                const syncGse = overlay.querySelector('#sync-gse').checked;
                const syncSteam = overlay.querySelector('#sync-steam').checked;
                const confirmBtn = overlay.querySelector('.modal-confirm-btn');
                confirmBtn.disabled = true;
                confirmBtn.textContent = t('restoring') || 'Restoring...';

                try {
                    const result = await this._app.api.restoreSave(saveId, backups[selectedBackupIndex].path);
                    console.log('[Saves] restore result:', result);
                    // Godot 返回格式: {code: 200, data: {success: true, message: '...'}}
                    // 处理两种响应格式：{data: {...}} 或直接 {...}
                    const responseData = result?.data || result;
                    if (responseData && responseData.success) {
                        overlay.remove();
                        this._app.notifications.show(`${t('save_restored') !== 'save_restored' ? t('save_restored') : 'Save restored'}: ${save.name}`, 'success');
                        await this.loadSaves();
                        this.updateSavesUI();

                        if (syncGse || syncSteam) {
                            let provider = '';
                            if (syncGse && syncSteam) provider = 'both';
                            else if (syncGse) provider = 'gse';
                            else if (syncSteam) provider = 'steam';
                            this._app.notifications.show(t('syncing') || '正在同步...', 'info');
                            try {
                                const syncResult = await this._app.api.syncCloud(provider, saveId);
                                const syncData = syncResult?.data || syncResult;
                                if (syncData && syncData.success) {
                                    const syncedPaths = syncData.synced_paths || [];
                                    const successCount = syncedPaths.filter(p => p.status === 'success').length;
                                    this._app.notifications.show(`成功同步到 ${successCount} 个云端位置`, 'success');
                                } else {
                                    console.warn('[Saves] sync failed:', syncData);
                                    this._app.notifications.show(`云同步失败: ${syncData?.message || '未知错误'}`, 'warning');
                                }
                            } catch (syncErr) {
                                console.warn('[Saves] sync error:', syncErr);
                                this._app.notifications.show(`云同步失败: ${syncErr.message || '未知错误'}`, 'warning');
                            }
                        }
                    } else {
                        throw new Error(responseData?.message || result?.message || 'Restore failed');
                    }
                } catch (err) {
                    console.warn('[STS2Saves] Restore failed:', err);
                    this._app.notifications.show(`${t('restore_failed') || 'Restore failed'}: ${err.message}`, 'error');
                    confirmBtn.disabled = false;
                    confirmBtn.textContent = t('confirm_restore') || '确认恢复';
                }
            });
        };

        overlay.innerHTML = `
            <div class="modal" style="max-width:600px">
                <div class="modal__header">
                    <span class="modal__title">${t('restore')} - ${STS2Utils.escapeHtml(save.name)}</span>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="step-indicator" style="padding:0 var(--sp-xl) var(--sp-md)">
                    <div class="overwrite-step-indicator">
                        <div class="step active">1</div>
                        <div class="step-label">${t('step1_select_backup') || '选择备份'}</div>
                        <div class="step-line"></div>
                        <div class="step">2</div>
                        <div class="step-label">${t('step2_cloud_sync') || '云同步选项'}</div>
                    </div>
                </div>
                <div class="modal__body">
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px">
                        ⚠ ${t('restore_warning') || 'Restore will overwrite current save. This action cannot be undone.'}
                    </div>
                    <div class="backup-list"></div>
                </div>
                <div class="modal__footer">
                    <button class="btn btn-ghost modal-close-btn">${t('cancel') || 'Cancel'}</button>
                    <button class="btn btn-primary modal-next-btn" disabled>${t('next_step') || '下一步 →'}</button>
                </div>
            </div>
        `;

        // Wire events
        overlay.querySelector('.modal__close').addEventListener('click', () => overlay.remove());
        overlay.querySelector('.modal-close-btn').addEventListener('click', () => overlay.remove());
        overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });

        // Next button → go to Step 2
        overlay.querySelector('.modal-next-btn').addEventListener('click', goToStep2);

        renderBackupList();
    },

    /**
     * Confirm delete backup.
     * @param {object} backup
     * @param {Function} onConfirm
     * @private
     */
    _confirmDeleteBackup(backup, onConfirm) {
        const t = (key) => this._app.i18n.translate(key);
        const container = document.getElementById('modal-container');
        if (!container) return;

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        container.appendChild(overlay);
        requestAnimationFrame(() => overlay.classList.add('open'));

        overlay.innerHTML = `
            <div class="modal" style="max-width:400px">
                <div class="modal__header">
                    <span class="modal__title">${t('confirm_delete_backup') || 'Delete Backup'}</span>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="modal__body" style="padding:var(--sp-lg) var(--sp-xl)">
                    <div style="font-size:13px;color:var(--text-secondary)">
                        ${t('delete_backup_confirm') || 'Are you sure you want to delete this backup?'}<br>
                        <strong style="color:var(--text-primary);margin-top:8px;display:block">${STS2Utils.escapeHtml(backup.name)}</strong>
                    </div>
                </div>
                <div class="modal__footer" style="gap:8px">
                    <button class="btn btn-ghost modal-cancel-btn">${t('cancel') || 'Cancel'}</button>
                    <button class="btn btn-danger modal-delete-btn">${t('delete') || 'Delete'}</button>
                </div>
            </div>
        `;

        const close = () => overlay.remove();
        overlay.querySelector('.modal__close').addEventListener('click', close);
        overlay.querySelector('.modal-cancel-btn').addEventListener('click', close);
        overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });

        overlay.querySelector('.modal-delete-btn').addEventListener('click', async () => {
            // Call backend delete API if available
            if (this._app && this._app.api && this._app.isBackendConnected()) {
                try {
                    // TODO: Add delete_backup API endpoint
                    // For now, just notify
                    this._app.notifications.show('Backup deleted (not implemented)', 'info');
                } catch (err) {
                    console.warn('[STS2Saves] Delete backup failed:', err);
                }
            }
            close();
            onConfirm();
        });
    },

    /**
     * Show the multi-step overwrite wizard.
     */
/**
     * Show the overwrite dialog - supports Steam-to-Steam overwrite.
     *
     * Unified dialog for all scenarios:
     * 1. Steam save → same account or different account overwrite
     * 2. Imported save → target Steam account overwrite
     */
    /**
     * Show the overwrite dialog - supports all overwrite scenarios.
     * Dynamic direction options based on save type (Steam save or imported save).
     */
    overwriteSave() {
        const t = (key) => this._app.i18n.translate(key);
        const container = document.getElementById('modal-container');
        if (!container) return;

        const selectedSave = this._getSelectedSaves()?.[0];
        if (!selectedSave) {
            this._app.notifications.show(t('select_save_first') || 'Select a save first', 'warning');
            return;
        }

        const currentSteamId = selectedSave.steam_id || this._selectedAccount;
        const isImportedSave = !!(selectedSave.is_imported);
        let targetAccount = isImportedSave
            ? (this._selectedAccount && !this._selectedAccount.startsWith('imported_') ? this._selectedAccount : '')
            : currentSteamId;
        let direction = null;
        let createBackup = true;
        let step = 1; // 1=方向选择, 2=云同步选择

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        container.appendChild(overlay);
        requestAnimationFrame(() => overlay.classList.add('open'));

        const close = () => { overlay.classList.remove('open'); setTimeout(() => overlay.remove(), 200); };

        const steamAccounts = [...new Set(this.saves.filter(s => s.steam_id && s.is_imported !== true).map(s => s.steam_id))];
        if (!targetAccount && steamAccounts.length > 0) {
            targetAccount = steamAccounts[0];
        }

        const getAvailableDirections = () => {
            if (isImportedSave) {
                const savePath = selectedSave.path || '';
                const pathParts = savePath.split('/');
                let folderName = '';
                for (let i = 0; i < pathParts.length; i++) {
                    if (pathParts[i] === 'temp_save' && i + 1 < pathParts.length) {
                        folderName = pathParts[i + 1];
                        break;
                    }
                }
                const isPathModded = savePath.includes('/modded/') || savePath.includes('\\modded\\');
                const hasImportedModded = isPathModded || this.saves.some(s =>
                    s.is_imported && s.modded && s.path && s.path.includes('/modded/') && s.path.includes(folderName)
                );

                if (hasImportedModded) {
                    return [
                        { dir: 'imported_to_vanilla', icon: '📂→🎮', label: '原版 → 原版', desc: '将导入的原版存档覆盖到目标账号的原版存档' },
                        { dir: 'imported_to_modded', icon: '📂→🔧', label: '原版 → 模组版', desc: '将导入的原版存档覆盖到目标账号的模组版存档' },
                        { dir: 'imported_modded_to_vanilla', icon: '📦→🎮', label: '模组版 → 原版', desc: '将导入的模组版存档覆盖到目标账号的原版存档' },
                        { dir: 'imported_modded_to_modded', icon: '📦→🔧', label: '模组版 → 模组版', desc: '将导入的模组版存档覆盖到目标账号的模组版存档' }
                    ];
                } else {
                    return [
                        { dir: 'imported_to_vanilla', icon: '📂→🎮', label: '原版 → 原版', desc: '将导入存档覆盖到目标账号的原版存档' },
                        { dir: 'imported_to_modded', icon: '📂→🔧', label: '原版 → 模组版', desc: '将导入存档覆盖到目标账号的模组版存档' }
                    ];
                }
            } else {
                return [
                    { dir: 'vanilla_to_vanilla', icon: '🎮→🎮', label: '原版 → 原版', desc: '原版存档覆盖原版（支持跨账号）' },
                    { dir: 'vanilla_to_modded', icon: '🎮→🔧', label: '原版 → 模组版', desc: '原版存档覆盖模组版' },
                    { dir: 'modded_to_vanilla', icon: '🔧→🎮', label: '模组版 → 原版', desc: '模组版存档覆盖原版' },
                    { dir: 'modded_to_modded', icon: '🔧→🔧', label: '模组版 → 模组版', desc: '模组版存档覆盖模组版（支持跨账号）' }
                ];
            }
        };

        const directions = getAvailableDirections();

        // 云同步选项
        let syncGse = true;
        let syncSteam = true;

        const renderDialog = () => {
            if (step === 1) {
                // Step 1: 方向选择
                const accountOpts = steamAccounts.map(sid => `<option value="${sid}" ${sid===targetAccount?'selected':''}>账号${sid.slice(-4)} (${sid})</option>`).join('');
                const directionCardsHtml = directions.map(d =>
                    `<div class="direction-card ${direction===d.dir?'selected':''}" data-dir="${d.dir}">
                        <div class="direction-card__icon">${d.icon}</div>
                        <div class="direction-card__label">${d.label}</div>
                        <div class="direction-card__desc">${d.desc}</div>
                    </div>`
                ).join('');

                const bodyHtml = `<div class="overwrite-wizard">
                    <div class="overwrite-step-indicator">
                        <span class="step active">1</span>
                        <span class="step-line"></span>
                        <span class="step">2</span>
                    </div>
                    <div class="overwrite-warning">⚠️ 此操作无法撤销</div>
                    <div class="overwrite-account-select"><label>选择目标账号:</label><select id="overwrite-account-select">${accountOpts}</select></div>
                    <div class="overwrite-direction-select"><label>选择覆盖方向:</label><div class="direction-cards">${directionCardsHtml}</div></div>
                    <div class="overwrite-backup-option"><label><input type="checkbox" id="overwrite-backup-checkbox" ${createBackup?'checked':''}><span>覆盖前创建备份</span></label></div>
                </div>`;

                const footerHtml = `<button class="btn btn-ghost modal-close-btn">取消</button><button class="btn btn-primary modal-next-btn" ${!direction?'disabled':''}>下一步 →</button>`;

                overlay.innerHTML = `<div class="modal overwrite-modal"><div class="modal__header"><span class="modal__title">覆盖存档</span><button class="modal__close">&times;</button></div><div class="modal__body">${bodyHtml}</div><div class="modal__footer">${footerHtml}</div></div>`;

                overlay.querySelector('.modal__close').addEventListener('click', close);
                overlay.querySelector('.modal-close-btn').addEventListener('click', close);
                overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });

                const accountSelect = overlay.querySelector('#overwrite-account-select');
                if (accountSelect) accountSelect.addEventListener('change', () => { targetAccount = accountSelect.value; });

                overlay.querySelectorAll('.direction-card').forEach(card => {
                    card.addEventListener('click', () => { direction = card.dataset.dir; renderDialog(); });
                });

                const nextBtn = overlay.querySelector('.modal-next-btn');
                if (nextBtn) {
                    nextBtn.addEventListener('click', () => {
                        if (!direction || !targetAccount) { this._app.notifications.show('请选择方向和目标账号', 'warning'); return; }
                        step = 2;
                        renderDialog();
                    });
                }
            } else {
                // Step 2: 云同步选择
                const dirInfo = directions.find(d => d.dir === direction);
                const accountName = targetAccount ? `账号${targetAccount.slice(-4)}` : '';

                overlay.innerHTML = `<div class="modal overwrite-modal">
                    <div class="modal__header">
                        <div style="display:flex;align-items:center;gap:12px">
                            <span style="font-size:24px">☁️</span>
                            <span class="modal__title">云端同步</span>
                        </div>
                        <button class="modal__close">&times;</button>
                    </div>
                    <div class="modal__body">
                        <div class="overwrite-wizard">
                            <div class="overwrite-step-indicator">
                                <span class="step completed">✓</span>
                                <span class="step-line"></span>
                                <span class="step active">2</span>
                            </div>
                            <div class="cloud-sync-summary">
                                <div class="cloud-sync-summary__info">
                                    <span style="font-size:13px;color:var(--text-secondary)">即将覆盖: <strong>${dirInfo?.label || direction}</strong> → <strong>${accountName}</strong></span>
                                </div>
                            </div>
                            <div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px;line-height:1.6">
                                选择要同步到的云端位置（若不同步，本地修改可能导致存档冲突或无效）
                            </div>
                            <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:16px">
                                <label class="cloud-sync-option">
                                    <input type="checkbox" id="sync-gse" ${syncGse?'checked':''} style="accent-color:var(--accent)">
                                    <div class="cloud-sync-option__content">
                                        <span class="cloud-sync-option__title">📁 GSE 云存档</span>
                                        <span class="cloud-sync-option__hint">学习版云同步路径</span>
                                    </div>
                                </label>
                                <label class="cloud-sync-option">
                                    <input type="checkbox" id="sync-steam" ${syncSteam?'checked':''} style="accent-color:var(--accent)">
                                    <div class="cloud-sync-option__content">
                                        <span class="cloud-sync-option__title">🎮 Steam 云存档</span>
                                        <span class="cloud-sync-option__hint">正版云同步路径</span>
                                    </div>
                                </label>
                            </div>
                            <div class="cloud-sync-warning">
                                <span style="font-size:14px">⚠️</span>
                                <span style="font-size:12px;line-height:1.5">若不同步到云端，本地修改可能导致存档冲突或无效。请根据游戏版本选择合适的云端进行同步。</span>
                            </div>
                        </div>
                    </div>
                    <div class="modal__footer" style="gap:8px">
                        <button class="btn btn-ghost modal-back-btn">← 返回</button>
                        <button class="btn btn-primary modal-confirm-btn">确认覆盖</button>
                    </div>
                </div>`;

                overlay.querySelector('.modal__close').addEventListener('click', close);
                overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });

                // Sync checkboxes
                const gseCheckbox = overlay.querySelector('#sync-gse');
                const steamCheckbox = overlay.querySelector('#sync-steam');
                if (gseCheckbox) gseCheckbox.addEventListener('change', () => { syncGse = gseCheckbox.checked; });
                if (steamCheckbox) steamCheckbox.addEventListener('change', () => { syncSteam = steamCheckbox.checked; });

                // Back button
                overlay.querySelector('.modal-back-btn').addEventListener('click', () => {
                    step = 1;
                    renderDialog();
                });

                // Confirm button
                overlay.querySelector('.modal-confirm-btn').addEventListener('click', async () => {
                    const createBackupNow = overlay.querySelector('#overwrite-backup-checkbox')?.checked ?? true;
                    const confirmBtn = overlay.querySelector('.modal-confirm-btn');
                    confirmBtn.disabled = true;
                    confirmBtn.textContent = '正在覆盖...';

                    try {
                        if (this._app && this._app.api && this._app.isBackendConnected()) {
                            let sourceSteamId = null;
                            let sourcePath = null;
                            if (isImportedSave) {
                                sourcePath = selectedSave.path;
                            } else {
                                // 非导入存档：source_steam_id 必须是当前存档的 steam_id
                                sourceSteamId = currentSteamId;
                            }

                            const result = await this._app.api.overwriteSave(direction, targetAccount, createBackupNow, sourceSteamId, sourcePath);
                            console.log('[Saves] overwrite result:', result);
                            // 处理两种响应格式：{data: {...}} 或直接 {...}
                            const responseData = result?.data || result;
                            if (responseData && responseData.success === true) {
                                close();
                                this._app.notifications.show('存档覆盖成功', 'success');
                                await this.loadSaves();
                                this.updateSavesUI();

                                // 在 Step 2 已选择云同步选项，直接执行
                                if (syncGse || syncSteam) {
                                    let provider = '';
                                    if (syncGse && syncSteam) provider = 'both';
                                    else if (syncGse) provider = 'gse';
                                    else if (syncSteam) provider = 'steam';
                                    this._app.notifications.show(t('syncing') || '正在同步...', 'info');
                                    const syncResult = await this._app.api.syncCloud(provider, targetAccount);
                                    const syncData = syncResult?.data || syncResult;
                                    if (syncData && syncData.success) {
                                        const syncedPaths = syncData.synced_paths || [];
                                        const successCount = syncedPaths.filter(p => p.status === 'success').length;
                                        this._app.notifications.show(`成功同步到 ${successCount} 个云端位置`, 'success');
                                    }
                                }
                            } else {
                                console.warn('[Saves] overwrite failed, result:', result);
                                throw new Error(String(responseData?.message || result?.message || '操作失败'));
                            }
                        } else {
                            close();
                            this._app.notifications.show('存档覆盖成功', 'success');
                        }
                    } catch (err) {
                        console.warn('[Saves] Error caught:', err);
                        // 显示错误信息
                        let errStr = String(err);
                        if (errStr && errStr !== '[object Object]' && errStr !== 'Unknown error') {
                            this._app.notifications.show('操作遇到错误：' + errStr, 'error');
                        }
                        confirmBtn.disabled = false;
                        confirmBtn.textContent = '确认覆盖';
                    }
                });
            }
        };

        renderDialog();
    },

    /**
     * Switch to a different profile.
     * @param {number} profile_num
     */
    switchProfile(profile_num) {
        this.current_profile = profile_num;
        if (this.selected_save_id) {
            this.showSaveDetails(this.selected_save_id);
        }
    },

    /**
     * Show cloud sync dialog after save overwrite.
     * Offers to sync to GSE cloud and/or Steam cloud.
     * @private
     */
    _showCloudSyncDialog(targetSteamId = null, description = null) {
        const t = (key) => this._app.i18n.translate(key);
        const container = document.getElementById('modal-container');
        if (!container) return;

        // 优先使用传入的 steamId，否则使用当前选中账号
        const accountId = targetSteamId || this._selectedAccount || '';

        const syncDesc = description || t('cloud_sync_desc_restore') || '存档恢复成功，请选择要同步到的云端位置';

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        container.appendChild(overlay);
        requestAnimationFrame(() => overlay.classList.add('open'));

        const close = () => { overlay.classList.remove('open'); setTimeout(() => overlay.remove(), 200); };

        overlay.innerHTML = `
            <div class="modal" style="max-width:420px">
                <div class="modal__header">
                    <div style="display:flex;align-items:center;gap:12px">
                        <span style="font-size:24px">\u2601\ufe0f</span>
                        <span class="modal__title">${t('cloud_sync_title') || '\u4e91\u7aef\u540c\u6b65'}</span>
                    </div>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="modal__body" style="padding:var(--sp-lg) var(--sp-xl)">
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:16px;line-height:1.6">
                        ${syncDesc}
                    </div>
                    <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:16px">
                        <label class="cloud-sync-option">
                            <input type="checkbox" id="sync-gse" checked style="accent-color:var(--accent)">
                            <div class="cloud-sync-option__content">
                                <span class="cloud-sync-option__title">\ud83d\udcc1 GSE \u4e91\u5b58\u6863</span>
                                <span class="cloud-sync-option__hint">\u5b66\u4e60\u7248\u4e91\u540c\u6b65\u8def\u5f84</span>
                            </div>
                        </label>
                        <label class="cloud-sync-option">
                            <input type="checkbox" id="sync-steam" checked style="accent-color:var(--accent)">
                            <div class="cloud-sync-option__content">
                                <span class="cloud-sync-option__title">\ud83c\udfae Steam \u4e91\u5b58\u6863</span>
                                <span class="cloud-sync-option__hint">\u6b63\u7248\u4e91\u540c\u6b65\u8def\u5f84</span>
                            </div>
                        </label>
                    </div>
                    <div class="cloud-sync-warning">
                        <span style="font-size:14px">\u26a0\ufe0f</span>
                        <span style="font-size:12px;line-height:1.5">\u82e5\u4e0d\u540c\u6b65\u5230\u4e91\u7aef\uff0c\u672c\u5730\u4fee\u6539\u53ef\u80fd\u5bfc\u81f4\u5b58\u6863\u51b2\u7a81\u6216\u65e0\u6548\u3002\u8bf7\u6839\u636e\u6e38\u620f\u7248\u672c\u9009\u62e9\u5408\u9002\u7684\u4e91\u7aef\u8fdb\u884c\u540c\u6b65\u3002</span>
                    </div>
                </div>
                <div class="modal__footer" style="gap:8px">
                    <button class="btn btn-ghost cloud-sync-skip">${t('skip_sync') || '\u8df3\u8fc7'}</button>
                    <button class="btn btn-primary cloud-sync-confirm">${t('sync') || '\u540c\u6b65'}</button>
                </div>
            </div>`;

        overlay.querySelector('.modal__close').addEventListener('click', close);
        overlay.querySelector('.cloud-sync-skip').addEventListener('click', close);
        overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });

        overlay.querySelector('.cloud-sync-confirm').addEventListener('click', async () => {
            const syncGse = overlay.querySelector('#sync-gse').checked;
            const syncSteam = overlay.querySelector('#sync-steam').checked;
            close();

            if (!syncGse && !syncSteam) return;

            this._app.notifications.show((t('syncing') || '\u6b63\u5728\u540c\u6b65...'), 'info');

            if (this._app && this._app.api && this._app.isBackendConnected()) {
                try {
                    let provider = '';
                    if (syncGse && syncSteam) provider = 'both';
                    else if (syncGse) provider = 'gse';
                    else if (syncSteam) provider = 'steam';

                    const result = await this._app.api.syncCloud(provider, accountId);
                    // Godot \u8fd4\u56de\u683c\u5f0f: {code: 200, data: {success: true, synced_paths: [...]}}
                    // 处理两种响应格式：{data: {...}} 或直接 {...}
                    const responseData = result?.data || result;
                    if (responseData && responseData.success) {
                        const syncedPaths = responseData.synced_paths || [];
                        const successCount = syncedPaths.filter(p => p.status === 'success').length;
                        this._app.notifications.show(`\u6210\u529f\u540c\u6b65\u5230 ${successCount} \u4e2a\u4e91\u7aef\u4f4d\u7f6e`, 'success');
                    } else {
                        throw new Error(responseData?.message || result?.message || 'Sync failed');
                    }
                } catch (e) {
                    console.warn('[STS2Saves] Cloud sync failed:', e);
                    this._app.notifications.show(t('sync_failed') || '\u540c\u6b65\u5931\u8d25', 'error');
                }
            }
        });
    },

    /**
     * Delete a save with long-press confirmation.
     * @param {string} id
     */
    async deleteSave(id) {
        const save = this.saves.find(s => s.id === id);
        if (!save) return;

        const t = (key) => this._app.i18n.translate(key);

        // Try backend API first
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const result = await this._app.api.deleteSave(id);
                // Godot 返回格式: {code: 200, data: {success: true, message: '...'}}
                // 处理两种响应格式：{data: {...}} 或直接 {...}
                    const responseData = result?.data || result;
                    if (responseData && responseData.success) {
                    // 后端删除成功
                    await this.loadSaves();
                    this.updateSavesUI();
                    this._app.notifications.show(
                        `${t('save_deleted') !== 'save_deleted' ? t('save_deleted') : 'Save deleted'}: ${save.name}`,
                        'success'
                    );
                    return;
                } else {
                    // 后端删除失败
                    this._app.notifications.show(
                        `${t('delete_failed') || 'Delete failed'}: ${responseData?.message || result?.message || ''}`,
                        'error'
                    );
                    return;
                }
            } catch (err) {
                console.warn('[STS2Saves] API deleteSave failed:', err);
                this._app.notifications.show(
                    `${t('delete_failed') || 'Delete failed'}: ${err.message || ''}`,
                    'error'
                );
                return;
            }
        }

        // Fallback: local state only (won't actually delete from disk)
        this.saves = this.saves.filter(s => s.id !== id);
        this._app.store.set('saves_data', this.saves);
        this._buildGroups();

        if (this.selected_save_id === id) this.selected_save_id = null;

        this._app.notifications.show(
            `${t('save_deleted') !== 'save_deleted' ? t('save_deleted') : 'Save deleted'}: ${save.name}`,
            'success'
        );

        this.updateSavesUI();
    },

    // ── Long-press delete ─────────────────────────────────────────

    /**
     * Set up a long-press delete button with a charging bar animation.
     * @param {string} saveId
     * @param {string} buttonId
     * @private
     */
    _setupLongpressDelete(saveId, buttonId) {
        const btn = document.getElementById(buttonId);
        const bar = document.getElementById('longpress-bar');
        const fill = document.getElementById('longpress-fill');
        const label = document.getElementById('longpress-label');
        if (!btn || !bar || !fill) return;

        const DURATION = 1500; // 1.5 seconds
        let startTime = 0;
        let rafId = null;

        const updateFill = () => {
            const elapsed = Date.now() - startTime;
            const pct = Math.min((elapsed / DURATION) * 100, 100);
            fill.style.width = pct + '%';

            if (pct >= 100) {
                // Delete confirmed
                this._cancelLongpress();
                this.deleteSave(saveId);
                return;
            }

            rafId = requestAnimationFrame(updateFill);
        };

        const onPointerDown = (e) => {
            e.preventDefault();
            bar.style.display = '';
            if (label) label.style.display = '';
            startTime = Date.now();
            fill.style.width = '0%';
            rafId = requestAnimationFrame(updateFill);
        };

        const onPointerUp = () => {
            this._cancelLongpress();
            if (bar) bar.style.display = 'none';
            if (label) label.style.display = 'none';
        };

        btn.addEventListener('pointerdown', onPointerDown);
        btn.addEventListener('pointerup', onPointerUp);
        btn.addEventListener('pointerleave', onPointerUp);
    },

    /** Cancel any active long-press animation. @private */
    _cancelLongpress() {
        // The rafId is local to _setupLongpressDelete, but we can
        // just rely on pointerup events to cancel. This is a safety net.
    },
};

// ── Export ─────────────────────────────────────────────────────────
window.STS2Saves = STS2Saves;
