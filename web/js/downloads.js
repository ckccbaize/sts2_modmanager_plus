/**
 * STS2Downloads - Download management module
 *
 * Manages active downloads (simulated) and download history.
 * Active downloads use setInterval-based progress simulation.
 * History persists in localStorage.
 */
const STS2Downloads = {

    // ── State ─────────────────────────────────────────────────────
    active_downloads: {},  // { id: { id, mod_name, url, progress, speed, status, started_at, timer_id, total_size } }
    history: [],           // [ { id, mod_name, status, date, size, duration } ]
    _app: null,
    _initialized: false,
    _backendPollTimer: null,  // interval handle for backend download polling

    // ── Lifecycle ─────────────────────────────────────────────────

    init(app) {
        this._app = app;
        this._bindEvents();
        this._loadHistory();
        this._initialized = true;

        // Request browser notification permission
        this._requestNotificationPermission();

        // Start backend polling when connected
        if (app.api && app.isBackendConnected()) {
            this._startBackendPolling();
        }

        console.log('[STS2Downloads] Initialized.');
    },

    _requestNotificationPermission() {
        if ('Notification' in window && Notification.permission === 'default') {
            Notification.requestPermission();
        }
    },

    _showBrowserNotification(title, body) {
        if ('Notification' in window && Notification.permission === 'granted') {
            try {
                new Notification(title, {
                    body,
                    icon: '../icon.svg',
                    tag: 'sts2-download-complete',
                });
            } catch (_) {
                // Notifications may be blocked in some environments
            }
        }
    },

    onEnter() {
        this.renderActiveDownloads();
        this.renderHistory();
    },

    onLeave() {
        // no-op; downloads continue in background
    },

    // ── Event binding ─────────────────────────────────────────────

    /** @private */
    _bindEvents() {
        const clearBtn = document.getElementById('btn-clear-history');
        if (clearBtn) {
            clearBtn.addEventListener('click', () => this.clearHistory());
        }

        const openFolderBtn = document.getElementById('btn-open-download-folder');
        if (openFolderBtn) {
            openFolderBtn.addEventListener('click', () => {
                const t = (key) => this._app.i18n.translate(key);
                this._app.notifications.show(
                    t('download_folder_opened') !== 'download_folder_opened' ? t('download_folder_opened') : 'Download folder opened',
                    'info'
                );
            });
        }

        this._app.on('language-applied', () => {
            if (this._initialized) {
                this.renderActiveDownloads();
                this.renderHistory();
            }
        });
    },

    // ── Data persistence ──────────────────────────────────────────

    /** @private */
    _loadHistory() {
        const store = this._app.store;
        if (store.has('download_history')) {
            this.history = store.get('download_history', []);
        }
    },

    /** @private */
    _saveHistory() {
        this._app.store.set('download_history', this.history);
    },

    // ── Download lifecycle ────────────────────────────────────────

    /**
     * Start a new simulated download.
     * @param {string|object} mod_name - mod name string, or a download object from nexus module
     * @param {string} [url]
     * @param {string} [source] - 'nexus', 'local', 'url', etc.
     * @returns {string} download id
     */
    addDownload(mod_name, url = '', source = 'local') {
        // Handle object form (from nexus module)
        if (typeof mod_name === 'object' && mod_name !== null) {
            const obj = mod_name;
            const id = obj.id || 'dl-' + STS2Utils.generateId();
            const dl = {
                id: id,
                mod_name: obj.name || obj.mod_name || 'Unknown',
                url: obj.url || '',
                source: obj.source || 'nexus',
                progress: obj.progress || 0,
                speed: obj.speed || 0,
                status: obj.status || 'downloading',
                started_at: obj.started_at || Date.now(),
                total_size: obj.size || obj.total_size || Math.floor(Math.random() * 50 + 5) * 1024 * 1024,
                downloaded: obj.downloaded || 0,
                timer_id: null,
            };
            this.active_downloads[id] = dl;
            this._simulateProgress(id);
            this.renderActiveDownloads();
            this._app.emit('download-started', { id, mod_name: dl.mod_name });
            return id;
        }

        const id = 'dl-' + STS2Utils.generateId();
        const totalSize = Math.floor(Math.random() * 150000000) + 10000000; // 10-160 MB

        const dl = {
            id: id,
            mod_name: mod_name,
            url: url,
            source: source,
            progress: 0,
            speed: 0,
            status: 'downloading',  // downloading | paused | complete | failed
            started_at: Date.now(),
            total_size: totalSize,
            downloaded: 0,
            timer_id: null,
        };

        this.active_downloads[id] = dl;
        this._simulateProgress(id);
        this.renderActiveDownloads();

        // Emit event
        this._app.emit('download-started', { id, mod_name });

        return id;
    },

    /**
     * Pause an active download.
     * @param {string} id
     */
    async pauseDownload(id) {
        const dl = this.active_downloads[id];
        if (!dl || dl.status !== 'downloading') return;

        // 先更新本地状态
        dl.status = 'paused';
        if (dl.timer_id) {
            clearInterval(dl.timer_id);
            dl.timer_id = null;
        }
        dl.speed = 0;
        this.renderActiveDownloads();

        // 调用后端 API
        try {
            await this._app.api.pauseDownload(id);
            console.log('[STS2Downloads] Download paused on backend:', id);
        } catch (e) {
            console.error('[STS2Downloads] Failed to pause download on backend:', e);
        }

        this._app.emit('download-paused', { id });
    },

    /**
     * Resume a paused download.
     * @param {string} id
     */
    async resumeDownload(id) {
        const dl = this.active_downloads[id];
        if (!dl || dl.status !== 'paused') return;

        // 先更新本地状态
        dl.status = 'downloading';
        this._simulateProgress(id);
        this.renderActiveDownloads();

        // 调用后端 API
        try {
            await this._app.api.resumeDownload(id);
            console.log('[STS2Downloads] Download resumed on backend:', id);
        } catch (e) {
            console.error('[STS2Downloads] Failed to resume download on backend:', e);
        }

        this._app.emit('download-resumed', { id });
    },

    /**
     * Cancel a download.
     * @param {string} id
     */
    async cancelDownload(id) {
        const dl = this.active_downloads[id];
        if (!dl) return;

        if (dl.timer_id) {
            clearInterval(dl.timer_id);
            dl.timer_id = null;
        }

        // 调用后端 API
        try {
            await this._app.api.cancelDownload(id);
            console.log('[STS2Downloads] Download cancelled on backend:', id);
        } catch (e) {
            console.error('[STS2Downloads] Failed to cancel download on backend:', e);
        }

        // Add to history as cancelled
        this.history.unshift({
            id: dl.id,
            mod_name: dl.mod_name,
            status: 'cancelled',
            date: new Date().toISOString(),
            size: dl.downloaded,
            duration: Date.now() - dl.started_at,
        });
        this._saveHistory();

        delete this.active_downloads[id];

        this.renderActiveDownloads();
        this.renderHistory();
        this._app.emit('download-cancelled', { id });
    },

    /**
     * Clear download history.
     */
    clearHistory() {
        this.history = [];
        this._saveHistory();
        this.renderHistory();

        const t = (key) => this._app.i18n.translate(key);
        this._app.notifications.show(
            t('history_cleared') !== 'history_cleared' ? t('history_cleared') : 'Download history cleared',
            'info'
        );
    },

    // ── Progress simulation ───────────────────────────────────────

    /**
     * Simulate download progress with setInterval.
     * @param {string} id
     * @private
     */
    _simulateProgress(id) {
        const dl = this.active_downloads[id];
        if (!dl) return;

        const TOTAL_DURATION = (Math.random() * 10 + 5) * 1000; // 5-15 seconds
        const INTERVAL = 200; // Update every 200ms
        const totalIncrements = TOTAL_DURATION / INTERVAL;
        let increment = 0;

        // Random failure chance (5%)
        const willFail = Math.random() < 0.05;
        const failAt = willFail ? Math.floor(totalIncrements * (0.3 + Math.random() * 0.5)) : -1;

        dl.timer_id = setInterval(() => {
            if (dl.status !== 'downloading') return;

            increment++;

            // Check for failure
            if (increment === failAt) {
                clearInterval(dl.timer_id);
                dl.timer_id = null;
                dl.status = 'failed';
                dl.speed = 0;

                this.history.unshift({
                    id: dl.id,
                    mod_name: dl.mod_name,
                    status: 'failed',
                    date: new Date().toISOString(),
                    size: dl.downloaded,
                    duration: Date.now() - dl.started_at,
                });
                this._saveHistory();

                this.renderActiveDownloads();
                this.renderHistory();
                this._app.emit('download-failed', { id });
                return;
            }

            // Calculate progress with some randomness
            const baseProgress = increment / totalIncrements;
            const jitter = (Math.random() - 0.5) * 0.02;
            dl.progress = Math.min(baseProgress + jitter, 1);
            dl.downloaded = Math.floor(dl.total_size * dl.progress);

            // Simulated speed: random 1-10 MB/s with variation
            dl.speed = (1 + Math.random() * 9) * 1024 * 1024; // bytes/s

            // Check completion
            if (dl.progress >= 1) {
                clearInterval(dl.timer_id);
                dl.timer_id = null;
                dl.progress = 1;
                dl.downloaded = dl.total_size;
                dl.status = 'complete';
                dl.speed = 0;

                this.history.unshift({
                    id: dl.id,
                    mod_name: dl.mod_name,
                    source: dl.source || 'local',
                    status: 'success',
                    date: new Date().toISOString(),
                    size: dl.total_size,
                    duration: Date.now() - dl.started_at,
                });
                this._saveHistory();

                const t = (key) => this._app.i18n.translate(key);
                const completeMsg = t('download_complete') !== 'download_complete' ? t('download_complete') : 'Download complete';
                this._app.notifications.show(`${completeMsg}: ${dl.mod_name}`, 'success');
                this._showBrowserNotification(`${completeMsg}: ${dl.mod_name}`, dl.url || '');

                this.renderActiveDownloads();
                this.renderHistory();
                this._app.emit('download-complete', { id, mod_name: dl.mod_name });
                return;
            }

            this.renderActiveDownloads();
        }, INTERVAL);
    },

    // ── Rendering ─────────────────────────────────────────────────

    /** Render active downloads in the #active-downloads container. */
    renderActiveDownloads() {
        const container = document.getElementById('active-downloads');
        if (!container) return;

        const t = (key) => this._app.i18n.translate(key);
        const activeIds = Object.keys(this.active_downloads);

        if (activeIds.length === 0) {
            container.innerHTML = `
                <div class="download-empty">
                    <div class="download-empty-icon">\ud83d\udce5</div>
                    <div class="download-empty-text">${t('no_download_task') !== 'no_download_task' ? t('no_download_task') : 'No active downloads'}</div>
                </div>
            `;
            return;
        }

        container.innerHTML = '';
        activeIds.forEach(id => {
            const dl = this.active_downloads[id];
            const el = document.createElement('div');
            el.className = `download-item ${dl.status}`;
            el.dataset.downloadId = id;

            const pct = Math.floor(dl.progress * 100);
            const speedStr = dl.status === 'downloading' ? STS2Utils.formatSize(Math.floor(dl.speed)) + '/s' : '';
            const etaStr = dl.status === 'downloading' && dl.speed > 0
                ? this._formatETA((dl.total_size - dl.downloaded) / dl.speed)
                : '';

            const statusLabels = {
                downloading: t('downloading') !== 'downloading' ? t('downloading') : 'Downloading',
                paused: t('paused') !== 'paused' ? t('paused') : 'Paused',
                complete: t('complete') !== 'complete' ? t('complete') : 'Complete',
                failed: t('failed') !== 'failed' ? t('failed') : 'Failed',
            };
            const statusIcons = {
                downloading: '\u25bc',
                paused: '\u23f8',
                complete: '\u2714',
                failed: '\u2718',
            };

            const statusClass = `status-${dl.status}`;

            el.innerHTML = `
                <div class="download-item-row">
                    <span class="download-item-name">${STS2Utils.escapeHtml(dl.mod_name)}</span>
                    <span class="download-item-speed">${speedStr}</span>
                    <span class="download-item-eta">${etaStr}</span>
                    <span class="download-item-status ${statusClass}">
                        ${statusIcons[dl.status] || ''} ${statusLabels[dl.status] || dl.status}
                    </span>
                </div>
                <div class="download-progress">
                    <div class="download-progress-bar">
                        <div class="download-progress-fill" style="width:${pct}%"></div>
                    </div>
                    <span class="download-progress-pct">${pct}%</span>
                </div>
                <div class="download-actions">
                    ${dl.status === 'downloading' ? `<button class="btn btn-sm btn-ghost dl-pause-btn">${t('pause') !== 'pause' ? t('pause') : 'Pause'}</button>` : ''}
                    ${dl.status === 'paused' ? `<button class="btn btn-sm btn-ghost dl-resume-btn">${t('resume') !== 'resume' ? t('resume') : 'Resume'}</button>` : ''}
                    ${dl.status === 'downloading' || dl.status === 'paused' ? `<button class="btn btn-sm btn-danger dl-cancel-btn">${t('cancel') !== 'cancel' ? t('cancel') : 'Cancel'}</button>` : ''}
                    ${dl.status === 'complete' || dl.status === 'failed' ? `<button class="btn btn-sm btn-ghost dl-remove-btn">${t('remove') !== 'remove' ? t('remove') : 'Remove'}</button>` : ''}
                </div>
            `;

            // Wire action buttons
            const pauseBtn = el.querySelector('.dl-pause-btn');
            if (pauseBtn) pauseBtn.addEventListener('click', () => this.pauseDownload(id));

            const resumeBtn = el.querySelector('.dl-resume-btn');
            if (resumeBtn) resumeBtn.addEventListener('click', () => this.resumeDownload(id));

            const cancelBtn = el.querySelector('.dl-cancel-btn');
            if (cancelBtn) cancelBtn.addEventListener('click', () => this.cancelDownload(id));

            const removeBtn = el.querySelector('.dl-remove-btn');
            if (removeBtn) removeBtn.addEventListener('click', () => {
                delete this.active_downloads[id];
                this.renderActiveDownloads();
            });

            container.appendChild(el);
        });
    },

    /** Render download history in the #download-history container. */
    renderHistory() {
        const container = document.getElementById('download-history');
        if (!container) return;

        const t = (key) => this._app.i18n.translate(key);

        if (this.history.length === 0) {
            container.innerHTML = `
                <div class="download-empty">
                    <div class="download-empty-text">${t('no_history') !== 'no_history' ? t('no_history') : 'No download history'}</div>
                </div>
            `;
            return;
        }

        container.innerHTML = '';
        const sourceLabels = {
            nexus: 'Nexus',
            local: t('local_source') !== 'local_source' ? t('local_source') : 'Local',
            url: 'URL',
        };
        this.history.forEach(entry => {
            const el = document.createElement('div');
            el.className = 'download-history-item';

            const iconMap = {
                success: { icon: '\u2714', cls: 'success' },
                failed: { icon: '\u2718', cls: 'failed' },
                cancelled: { icon: '\u2716', cls: 'cancelled' },
            };
            const iconInfo = iconMap[entry.status] || iconMap.cancelled;
            const srcLabel = sourceLabels[entry.source] || entry.source || '';

            el.innerHTML = `
                <span class="download-history-icon ${iconInfo.cls}">${iconInfo.icon}</span>
                <span class="download-history-name">${STS2Utils.escapeHtml(entry.mod_name)}</span>
                ${srcLabel ? `<span class="download-history-source">${srcLabel}</span>` : ''}
                <span class="download-history-date">${STS2Utils.timeAgo(entry.date)}</span>
                <span class="download-history-size">${STS2Utils.formatSize(entry.size)}</span>
            `;

            container.appendChild(el);
        });
    },

    // ── Backend polling ───────────────────────────────────────────

    /**
     * Start polling the backend API for real download status every 3 seconds.
     * Merges API data into active_downloads, replacing simulated progress when available.
     * @private
     */
    _startBackendPolling() {
        this._stopBackendPolling();
        this._backendPollTimer = setInterval(async () => {
            if (!this._app || !this._app.api || !this._app.isBackendConnected()) {
                this._stopBackendPolling();
                return;
            }
            try {
                const resp = await this._app.api.getDownloads();
                // 支持两种返回格式：resp.downloads 和 resp.data.downloads
                const apiDownloads = resp?.downloads || resp?.data?.downloads;
                if (!apiDownloads || !Array.isArray(apiDownloads)) return;
                const seenIds = new Set();

                for (const apiDl of apiDownloads) {
                    seenIds.add(apiDl.id);
                    const existing = this.active_downloads[apiDl.id];

                    if (existing) {
                        // Merge real API data into existing entry (API takes priority)
                        if (apiDl.progress !== undefined) existing.progress = apiDl.progress;
                        if (apiDl.speed !== undefined) existing.speed = apiDl.speed;
                        if (apiDl.status !== undefined) existing.status = apiDl.status;
                        if (apiDl.downloaded !== undefined) existing.downloaded = apiDl.downloaded;
                        if (apiDl.total_size !== undefined) existing.total_size = apiDl.total_size;
                        if (apiDl.mod_name !== undefined) existing.mod_name = apiDl.mod_name;

                        // Handle terminal states from API
                        if (apiDl.status === 'complete' || apiDl.status === 'failed') {
                            if (existing.timer_id) {
                                clearInterval(existing.timer_id);
                                existing.timer_id = null;
                            }
                            existing.speed = 0;

                            // Add to history if not already there
                            const histExists = this.history.some(h => h.id === apiDl.id);
                            if (!histExists) {
                                this.history.unshift({
                                    id: apiDl.id,
                                    mod_name: apiDl.mod_name,
                                    status: apiDl.status === 'complete' ? 'success' : 'failed',
                                    date: new Date().toISOString(),
                                    size: apiDl.total_size || 0,
                                    duration: 0,
                                });
                                this._saveHistory();
                            }
                        }
                    } else {
                        // 本地文件优先：检查该mod是否已存在本地
                        if (this._checkModExistsLocally(apiDl.mod_name, apiDl.url)) {
                            console.log('[STS2Downloads] Mod already exists locally, skipping download:', apiDl.mod_name);
                            continue;  // 跳过创建下载项
                        }

                        // New download from API that we don't track yet
                        this.active_downloads[apiDl.id] = {
                            id: apiDl.id,
                            mod_name: apiDl.mod_name || 'Unknown',
                            url: apiDl.url || '',
                            progress: apiDl.progress || 0,
                            speed: apiDl.speed || 0,
                            status: apiDl.status || 'downloading',
                            started_at: apiDl.started_at || Date.now(),
                            total_size: apiDl.total_size || 0,
                            downloaded: apiDl.downloaded || 0,
                            timer_id: null,
                        };
                    }
                }

                this.renderActiveDownloads();
            } catch (e) {
                console.warn('[STS2Downloads] Backend polling failed:', e);
            }
        }, 3000);
    },

    /**
     * Stop backend polling.
     * @private
     */
    _stopBackendPolling() {
        if (this._backendPollTimer) {
            clearInterval(this._backendPollTimer);
            this._backendPollTimer = null;
        }
    },

    // ── Helpers ───────────────────────────────────────────────────

    /**
     * Check if a mod already exists locally by name or URL.
     * @param {string} modName - The name of the mod
     * @param {string} url - The URL of the mod
     * @returns {boolean} - True if mod exists locally
     * @private
     */
    _checkModExistsLocally(modName, url) {
        if (!modName) return false;

        const normalizedName = modName.toLowerCase().trim();

        // 1. Check download history for successful downloads with same mod name
        const inHistory = this.history.some(h => 
            h.mod_name && h.mod_name.toLowerCase().trim() === normalizedName && h.status === 'success'
        );
        if (inHistory) return true;

        // 2. Check installed mods via app.mods.mods
        if (this._app && this._app.mods && this._app.mods.mods) {
            const installedMods = this._app.mods.mods;
            const modExists = installedMods.some(mod => {
                const modNameLower = (mod.name || mod.mod_name || '').toLowerCase().trim();
                return modNameLower === normalizedName;
            });
            if (modExists) return true;
        }

        // 3. Check active downloads for same mod (avoid duplicate active downloads)
        const activeExists = Object.values(this.active_downloads).some(dl =>
            dl.mod_name && dl.mod_name.toLowerCase().trim() === normalizedName
        );
        if (activeExists) return true;

        // 4. Check by URL if provided
        if (url) {
            const urlInHistory = this.history.some(h => 
                h.url === url && h.status === 'success'
            );
            if (urlInHistory) return true;

            const urlInActive = Object.values(this.active_downloads).some(dl => dl.url === url);
            if (urlInActive) return true;
        }

        // 5. Check by filename extracted from URL
        if (url) {
            try {
                const urlObj = new URL(url);
                const pathname = urlObj.pathname;
                const filename = pathname.split('/').pop();
                if (filename) {
                    const filenameInHistory = this.history.some(h => {
                        if (!h.url) return false;
                        try {
                            const hUrl = new URL(h.url);
                            const hFilename = hUrl.pathname.split('/').pop();
                            return hFilename === filename && h.status === 'success';
                        } catch (e) {
                            return false;
                        }
                    });
                    if (filenameInHistory) return true;
                }
            } catch (e) {
                // URL parsing failed, skip filename check
            }
        }

        return false;
    },

    /**
     * Format ETA in seconds to a readable string.
     * @param {number} seconds
     * @returns {string}
     * @private
     */
    _formatETA(seconds) {
        if (!seconds || seconds <= 0 || !isFinite(seconds)) return '';
        const s = Math.ceil(seconds);
        if (s < 60) return `${s}s`;
        const m = Math.floor(s / 60);
        const rem = s % 60;
        return `${m}m ${rem}s`;
    },
};

// ── Export ─────────────────────────────────────────────────────────
window.STS2Downloads = STS2Downloads;
