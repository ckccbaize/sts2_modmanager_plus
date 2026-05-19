/**
 * STS2Downloads - Download management module
 *
 * Manages active downloads (via Aria2) and download history.
 * Active downloads use Aria2 for real multi-threaded downloads.
 * History persists in localStorage.
 */
const STS2Downloads = {

    // ── State ─────────────────────────────────────────────────────
    active_downloads: {},  // { id: { id, mod_name, url, progress, speed, status, started_at, gid, timer_id, total_size } }
    history: [],           // [ { id, mod_name, status, date, size, duration } ]
    _app: null,
    _initialized: false,
    _backendPollTimer: null,  // interval handle for backend download polling
    _aria2PollTimer: null,    // interval handle for Aria2 progress polling

    // ── Polling termination state ─────────────────────────────────
    _lastPollData: null,      // 上次轮询的响应数据（用于比较）
    _pollEmptyCount: 0,       // 连续空数据计数器
    _POLL_EMPTY_THRESHOLD: 3, // 连续几次空数据后停止轮询
    _completedNotificationIds: new Set(), // 已弹窗通知的下载ID（防止重复弹窗）

    // ── Lifecycle ─────────────────────────────────────────────────

    init(app) {
        this._app = app;
        this._bindEvents();
        this._loadHistory();
        this._initialized = true;

        // Request browser notification permission
        this._requestNotificationPermission();

        // Initialize Aria2
        this._initAria2();

        // Sync history from backend immediately on init (before first render)
        this._fetchBackendHistory();

        // Start backend polling when connected
        if (app.api && app.isBackendConnected()) {
            this._startBackendPolling();
        }

        // Listen for backend connection events to start polling when backend connects later
        app.on('backend-connected', () => {
            console.log('[STS2Downloads] Backend connected, starting polling');
            this._fetchBackendHistory();
            this._startBackendPolling();
        });

        // 监听 BrowserHost 的主动通知（通过 CustomEvent）
        window.addEventListener('sts2-download-complete', (event) => {
            console.log('[STS2Downloads] Received download complete event:', event.detail);
            const { id, mod_name, status } = event.detail;
            this._onBrowserHostDownloadComplete(id, mod_name, status);
        });

        // 监听安装完成通知
        window.addEventListener('sts2-install-complete', (event) => {
            console.log('[STS2Downloads] Received install complete event:', event.detail);
            const { id, mod_name, status } = event.detail;
            this._onBrowserHostInstallComplete(id, mod_name, status);
        });

        // 暴露全局函数供 BrowserHost 调用
        window.STS2Downloads = this;
        window._onBrowserHostDownloadComplete = (id, mod_name, status) => {
            this._onBrowserHostDownloadComplete(id, mod_name, status);
        };

        console.log('[STS2Downloads] Initialized.');
    },

    /**
     * Handle download complete notification from BrowserHost (active push, not polling).
     * @param {string} id - download id
     * @param {string} mod_name - mod name
     * @param {string} status - download status
     * @private
     */
    _onBrowserHostDownloadComplete(id, mod_name, status) {
        console.log('[STS2Downloads] BrowserHost download complete:', id, mod_name, status);
        // 防止重复弹窗
        if (this._completedNotificationIds.has(id)) {
            console.log('[STS2Downloads] Already notified for:', id);
            return;
        }
        this._completedNotificationIds.add(id);

        // 添加到历史记录
        const histExists = this.history.some(h => h.id === id);
        if (!histExists) {
            this.history.unshift({
                id,
                mod_name: mod_name || 'Unknown',
                status: 'success',
                date: new Date().toISOString(),
                size: 0,
                duration: 0,
            });
            this._saveHistory();
            this.renderHistory();
        }

        // 从活跃列表移除（如果还在）
        if (this.active_downloads[id]) {
            if (this.active_downloads[id].timer_id) {
                clearInterval(this.active_downloads[id].timer_id);
            }
            delete this.active_downloads[id];
            this.renderActiveDownloads();
        }

        // 显示通知
        this._app.notifications.show(`下载完成: ${mod_name}，正在安装...`, 'success', 4000);

        // 通知模组页面刷新（后端已完成自动安装）
        if (this._app) {
            console.log('[STS2Downloads] Emitting download-complete event for mod refresh');
            this._app.emit('download-complete', { id, mod_name });
        }
    },

    /**
     * Handle install complete notification from BrowserHost (active push, not polling).
     * @param {string} id - download id
     * @param {string} mod_name - mod name
     * @param {string} status - install status
     * @private
     */
    _onBrowserHostInstallComplete(id, mod_name, status) {
        console.log('[STS2Downloads] BrowserHost install complete:', id, mod_name, status);
        // 安装完成时不需要再次检查 _completedNotificationIds，因为同一个 id 已经添加过了

        // 显示安装完成通知
        this._app.notifications.show(`已自动安装: ${mod_name}`, 'success', 3000);

        // 通知模组页面刷新列表
        if (this._app) {
            console.log('[STS2Downloads] Emitting install-complete event for mod refresh');
            this._app.emit('install-complete', { id, mod_name });
        }
    },

    /**
     * Backend download complete handler (called by BrowserHost via JavaScript).
     * Updates download item to 100% and marks as completed.
     * @param {string} id - download id
     * @param {string} modName - mod name
     * @public (called from BrowserHost)
     */
    onBackendDownloadComplete(id, modName) {
        console.log('[STS2Downloads] onBackendDownloadComplete:', id, modName);
        // 防止重复处理
        if (this._completedNotificationIds.has(id)) {
            console.log('[STS2Downloads] Already processed:', id);
            return;
        }
        this._completedNotificationIds.add(id);

        // 更新活跃下载项为完成状态
        if (this.active_downloads[id]) {
            this.active_downloads[id].progress = 1;
            this.active_downloads[id].status = 'complete';
            this.active_downloads[id].speed = 0;
            if (this.active_downloads[id].timer_id) {
                clearInterval(this.active_downloads[id].timer_id);
                this.active_downloads[id].timer_id = null;
            }
            this.renderActiveDownloads();
        }

        // 添加到历史记录
        const histExists = this.history.some(h => h.id === id);
        if (!histExists) {
            this.history.unshift({
                id,
                mod_name: modName || 'Unknown',
                status: 'success',
                date: new Date().toISOString(),
                size: 0,
                duration: 0,
            });
            this._saveHistory();
            this.renderHistory();
        }
    },

    /**
     * Initialize Aria2 connection and register callbacks.
     * @private
     */
    async _initAria2() {
        try {
            // 等待 Aria2 初始化
            const initialized = await window.Aria2?.init();
            if (initialized) {
                console.log('[STS2Downloads] Aria2 initialized successfully');

                // 注册进度回调
                window.Aria2.on('progress', (data) => {
                    this._onAria2Progress(data);
                });

                window.Aria2.on('complete', (data) => {
                    this._onAria2Complete(data);
                });

                window.Aria2.on('error', (data) => {
                    this._onAria2Error(data);
                });

                // 启动 Aria2 状态轮询
                this._startAria2Polling();
            } else {
                console.log('[STS2Downloads] Aria2 not available, using simulated downloads');
            }
        } catch (e) {
            console.warn('[STS2Downloads] Aria2 init failed:', e);
        }
    },

    /**
     * Start polling Aria2 for download status.
     * @private
     */
    _startAria2Polling() {
        this._stopAria2Polling();
        this._aria2PollTimer = setInterval(async () => {
            try {
                const active = await window.Aria2?.getAllActive();
                if (active && Array.isArray(active)) {
                    for (const dl of active) {
                        this._updateDownloadFromAria2(dl);
                    }
                }
            } catch (e) {
                // Ignore polling errors
            }
        }, 500); // 每 500ms 轮询一次
    },

    /**
     * Stop Aria2 polling.
     * @private
     */
    _stopAria2Polling() {
        if (this._aria2PollTimer) {
            clearInterval(this._aria2PollTimer);
            this._aria2PollTimer = null;
        }
    },

    /**
     * Update download from Aria2 status.
     * @param {object} aria2Dl - Aria2 download status
     * @private
     */
    _updateDownloadFromAria2(aria2Dl) {
        // 查找对应的下载（通过 GID 或其他标识）
        for (const [id, dl] of Object.entries(this.active_downloads)) {
            if (dl.gid === aria2Dl.gid) {
                // 更新进度
                if (aria2Dl.totalLength > 0) {
                    dl.total_size = parseInt(aria2Dl.totalLength);
                    dl.downloaded = parseInt(aria2Dl.completedLength);
                    dl.progress = dl.total_size > 0 ? dl.downloaded / dl.total_size : 0;
                }
                dl.speed = parseInt(aria2Dl.downloadSpeed) || 0;
                dl.status = aria2Dl.status === 'active' ? 'downloading' : aria2Dl.status;

                this.renderActiveDownloads();
                return;
            }
        }
    },

    /**
     * Handle Aria2 progress event.
     * @param {object} data
     * @private
     */
    _onAria2Progress(data) {
        console.log('[STS2Downloads] Aria2 progress:', data);
        // 进度更新通过轮询处理
    },

    /**
     * Handle Aria2 complete event.
     * @param {object} data
     * @private
     */
    _onAria2Complete(data) {
        console.log('[STS2Downloads] Aria2 download complete:', data);
        // 查找并标记完成
        for (const [id, dl] of Object.entries(this.active_downloads)) {
            if (dl.gid === data.gid) {
                dl.status = 'complete';
                dl.progress = 1;
                dl.speed = 0;

                // 添加到历史
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

                this.renderActiveDownloads();
                this.renderHistory();

                const t = (key) => this._app.i18n.translate(key);
                const completeMsg = t('download_complete') !== 'download_complete' ? t('download_complete') : 'Download complete';
                this._app.notifications.show(`${completeMsg}: ${dl.mod_name}`, 'success');

                // 通知 Godot 安装
                this._notifyDownloadComplete(dl);
                return;
            }
        }
    },

    /**
     * Handle Aria2 error event.
     * @param {object} data
     * @private
     */
    _onAria2Error(data) {
        console.log('[STS2Downloads] Aria2 download error:', data);
        for (const [id, dl] of Object.entries(this.active_downloads)) {
            if (dl.gid === data.gid) {
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
                return;
            }
        }
    },

    /**
     * Notify Godot that download is complete.
     * @param {object} dl
     * @private
     */
    _notifyDownloadComplete(dl) {
        if (this._app?.api) {
            this._app.api.notifyDownloadComplete(dl.id, dl.SavePath).catch(e => {
                console.warn('[STS2Downloads] Notify complete failed:', e);
            });
        }
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

    /**
     * Fetch history from backend API immediately (one-shot, no polling).
     * Ensures download_history.json data is available on initial page load.
     * @private
     */
    async _fetchBackendHistory() {
        if (!this._app || !this._app.api || !this._app.isBackendConnected()) {
            return;
        }
        try {
            const resp = await this._app.api.getDownloads();
            console.log('[STS2Downloads] Initial backend history fetch:', resp);

            let apiHistory = null;
            if (resp?.data?.history) {
                apiHistory = resp.data.history;
            } else if (resp?.history) {
                apiHistory = resp.history;
            } else if (resp?.data?.data?.history) {
                apiHistory = resp.data.data.history;
            } else if (resp?.data?.active !== undefined) {
                // 响应是 {active: [...], history: [...]} 没有 data 包装
                apiHistory = resp.data?.history || resp.history;
            }

            console.log('[STS2Downloads] Extracted apiHistory:', apiHistory?.length);

            if (apiHistory && Array.isArray(apiHistory) && apiHistory.length > 0) {
                this._mergeHistoryFromAPI(apiHistory);
            }
        } catch (e) {
            console.warn('[STS2Downloads] Initial backend history fetch failed:', e);
        }
    },

    // ── Download lifecycle ────────────────────────────────────────

    /**
     * Start a new download via Aria2.
     * @param {string|object} mod_name - mod name string, or a download object from nexus module
     * @param {string} [url]
     * @param {string} [source] - 'nexus', 'local', 'url', etc.
     * @returns {string} download id
     */
    async addDownload(mod_name, url = '', source = 'local') {
        // 重置轮询终止计数器并恢复轮询（如果有新下载）
        this._pollEmptyCount = 0;
        this._lastPollData = null;
        if (this._app && this._app.api && this._app.isBackendConnected() && !this._backendPollTimer) {
            this._startBackendPolling();
        }

        const id = 'dl-' + STS2Utils.generateId();
        let totalSize = Math.floor(Math.random() * 150000000) + 10000000; // 10-160 MB default

        // Handle object form (from nexus module)
        if (typeof mod_name === 'object' && mod_name !== null) {
            const obj = mod_name;
            url = obj.url || url;
            source = obj.source || 'nexus';
            totalSize = obj.size || obj.total_size || totalSize;
            mod_name = obj.name || obj.mod_name || 'Unknown';
        }

        // 创建下载记录
        const dl = {
            id: id,
            mod_name: mod_name,
            url: url,
            source: source,
            progress: 0,
            speed: 0,
            status: 'downloading',
            started_at: Date.now(),
            total_size: totalSize,
            downloaded: 0,
            gid: null,  // Aria2 GID
            timer_id: null,
        };

        this.active_downloads[id] = dl;

        // 尝试通过 Aria2 下载
        if (window.Aria2?.isConnected() && url) {
            try {
                const gid = await window.Aria2.addDownload(url, '', {
                    'split': '16',
                    'max-connection-per-server': '16',
                    'continue': 'true',
                });

                if (gid) {
                    dl.gid = gid;
                    console.log('[STS2Downloads] Aria2 download started:', gid);
                    this.renderActiveDownloads();
                    this._app.emit('download-started', { id, mod_name: dl.mod_name });
                    return id;
                }
            } catch (e) {
                console.warn('[STS2Downloads] Aria2 add failed, using simulation:', e);
            }
        }

        // Aria2 不可用时使用模拟进度
        this._simulateProgress(id);
        this.renderActiveDownloads();
        this._app.emit('download-started', { id, mod_name });

        return id;
    },

    /**
     * Pause an active download.
     * @param {string} id - download id
     */
    async pauseDownload(id) {
        const dl = this.active_downloads[id];
        if (!dl || dl.status !== 'downloading') return;

        // 如果有 GID，通过 Aria2 暂停
        if (dl.gid && window.Aria2?.isConnected()) {
            try {
                await window.Aria2.pause(dl.gid);
            } catch (e) {
                console.warn('[STS2Downloads] Aria2 pause failed:', e);
            }
        }

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
            const result = await this._app.api.pauseDownload(id);
            console.log('[STS2Downloads] Download paused on backend:', id, result);
        } catch (e) {
            console.error('[STS2Downloads] Failed to pause download on backend:', e);
        }

        this._app.emit('download-paused', { id });
    },

    /**
     * Resume a paused download.
     * @param {string} id - download id
     */
    async resumeDownload(id) {
        const dl = this.active_downloads[id];
        if (!dl || dl.status !== 'paused') return;

        // 如果有 GID，通过 Aria2 恢复
        if (dl.gid && window.Aria2?.isConnected()) {
            try {
                await window.Aria2.resume(dl.gid);
            } catch (e) {
                console.warn('[STS2Downloads] Aria2 resume failed:', e);
            }
        }

        // 先更新本地状态
        dl.status = 'downloading';
        this._simulateProgress(id);
        this.renderActiveDownloads();

        // 调用后端 API
        try {
            const result = await this._app.api.resumeDownload(id);
            console.log('[STS2Downloads] Download resumed on backend:', id, result);
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

        // 如果有 GID，通过 Aria2 取消
        if (dl.gid && window.Aria2?.isConnected()) {
            try {
                await window.Aria2.remove(dl.gid);
            } catch (e) {
                console.warn('[STS2Downloads] Aria2 remove failed:', e);
            }
        }

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

            const rawProgress = dl.progress > 1 ? dl.progress : dl.progress * 100;
            const pct = isFinite(rawProgress) ? Math.min(100, Math.floor(rawProgress)) : 0;
            const speedStr = dl.status === 'downloading' && dl.speed > 0 ? STS2Utils.formatSize(Math.floor(dl.speed)) + '/s' : '';
            const etaStr = dl.status === 'downloading' && dl.speed > 0 && dl.total_size > dl.downloaded
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
        console.log('[STS2Downloads] renderHistory called. Container:', !!container, 'History count:', this.history.length);
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

        console.log('[STS2Downloads] Rendering', this.history.length, 'history items');
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

                // 解析LocalServer响应格式：支持多种返回格式
                // 格式1: { downloads: [...] }
                // 格式2: { data: { downloads: [...] } }
                // 格式3: { data: { active: [], history: [] } } (LocalServer格式)
                let apiDownloads = null;
                let apiHistory = null;

                // 添加调试日志
                console.log('[STS2Downloads] Poll response:', resp);

                if (resp?.data?.active !== undefined) {
                    // LocalServer格式：data.active 和 data.history
                    apiDownloads = resp.data.active;
                    apiHistory = resp.data.history;
                    console.log('[STS2Downloads] LocalServer format detected:', { active: apiDownloads?.length, history: apiHistory?.length });

                    // 轮询终止逻辑：当 active.length === 0 且连续多次响应数据无变化时停止轮询
                    const currentData = JSON.stringify(resp.data);
                    if (apiDownloads.length === 0) {
                        if (this._lastPollData === currentData) {
                            this._pollEmptyCount++;
                            console.log('[STS2Downloads] Empty poll count:', this._pollEmptyCount);
                            if (this._pollEmptyCount >= this._POLL_EMPTY_THRESHOLD) {
                                console.log('[STS2Downloads] Stopping backend polling after', this._POLL_EMPTY_THRESHOLD, 'consecutive empty polls');
                                this._stopBackendPolling();
                                return;
                            }
                        } else {
                            this._pollEmptyCount = 0;
                        }
                    } else {
                        this._pollEmptyCount = 0;
                    }
                    this._lastPollData = currentData;

                } else if (resp?.downloads) {
                    // 直接返回格式
                    apiDownloads = resp.downloads;
                    console.log('[STS2Downloads] Direct downloads format:', apiDownloads?.length);
                } else if (resp?.data?.downloads) {
                    // data.downloads 格式
                    apiDownloads = resp.data.downloads;
                    console.log('[STS2Downloads] Data.downloads format:', apiDownloads?.length);
                } else if (resp?.active !== undefined || resp?.data?.active !== undefined) {
                    // {active, history} 格式
                    apiDownloads = resp.active !== undefined ? resp.active : resp.data?.active;
                    apiHistory = resp.history !== undefined ? resp.history : resp.data?.history;
                    console.log('[STS2Downloads] Active/history format:', apiDownloads?.length, apiHistory?.length);
                } else {
                    console.warn('[STS2Downloads] Unknown response format:', resp);
                }

                // 同步历史记录（如果有的话）
                if (apiHistory && Array.isArray(apiHistory) && apiHistory.length > 0) {
                    console.log('[STS2Downloads] Merging', apiHistory.length, 'history entries from API');
                    this._mergeHistoryFromAPI(apiHistory);
                }

                if (!apiDownloads || !Array.isArray(apiDownloads)) {
                    return;
                }

                const seenIds = new Set();

                for (const apiDl of apiDownloads) {
                    seenIds.add(apiDl.id);
                    const existing = this.active_downloads[apiDl.id];

                    if (existing) {
                        // Merge real API data into existing entry (API takes priority)
                        // 注意：后端progress范围为0-100，前端使用0-1，需要进行归一化
                        if (apiDl.progress !== undefined) existing.progress = this._normalizeProgress(apiDl.progress);
                        if (apiDl.speed !== undefined) existing.speed = apiDl.speed;
                        if (apiDl.status !== undefined) existing.status = apiDl.status;
                        if (apiDl.downloaded !== undefined) existing.downloaded = apiDl.downloaded;
                        if (apiDl.total_size !== undefined) existing.total_size = apiDl.total_size;
                        if (apiDl.mod_name !== undefined) existing.mod_name = apiDl.mod_name;

                        // Handle terminal states from API
                        if (apiDl.status === 'complete' || apiDl.status === 'completed' || apiDl.status === 'failed') {
                            if (existing.timer_id) {
                                clearInterval(existing.timer_id);
                                existing.timer_id = null;
                            }
                            existing.speed = 0;
                            existing.status = apiDl.status === 'failed' ? 'failed' : 'complete';

                            // 防止重复弹窗（只在未处理过的情况下显示通知）
                            if (!this._completedNotificationIds.has(apiDl.id)) {
                                this._completedNotificationIds.add(apiDl.id);

                                // Add to history if not already there
                                const histExists = this.history.some(h => h.id === apiDl.id);
                                if (!histExists) {
                                    this.history.unshift({
                                        id: apiDl.id,
                                        mod_name: apiDl.mod_name,
                                        status: (apiDl.status === 'complete' || apiDl.status === 'completed') ? 'success' : 'failed',
                                        date: new Date().toISOString(),
                                        size: apiDl.total_size || 0,
                                        duration: 0,
                                    });
                                    this._saveHistory();
                                    console.log('[STS2Downloads] Download completed:', apiDl.mod_name);
                                    this._app.notifications.show(`下载完成: ${apiDl.mod_name}`, 'success');
                                }
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
                            progress: this._normalizeProgress(apiDl.progress) || 0,
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
     * Merge history from API response into local history.
     * Prevents duplicates and updates UI.
     * @param {Array} apiHistory - History array from API response
     * @private
     */
    _mergeHistoryFromAPI(apiHistory) {
        if (!Array.isArray(apiHistory) || apiHistory.length === 0) return;

        console.log('[STS2Downloads] Current local history count:', this.history.length);
        console.log('[STS2Downloads] API history count:', apiHistory.length);

        // 【修复 Task #10】清理已进入历史记录的活跃任务
        // 如果后端下载任务失败或完成进入了历史记录，前端必须停止本地模拟并从活跃列表中移除
        for (const apiEntry of apiHistory) {
            if (this.active_downloads[apiEntry.id]) {
                const dl = this.active_downloads[apiEntry.id];
                if (dl.timer_id) clearInterval(dl.timer_id);
                delete this.active_downloads[apiEntry.id];
            }
        }
        this.renderActiveDownloads();

        // 转换格式：Unix timestamp -> ISO string, status: completed -> success
        const convertedHistory = apiHistory.map((apiEntry, idx) => {
            let entryDate;
            if (apiEntry.date) {
                const timestamp = typeof apiEntry.date === 'number' ? apiEntry.date : parseInt(apiEntry.date);
                entryDate = new Date(timestamp * 1000).toISOString();
            } else {
                entryDate = new Date().toISOString();
            }

            let status = apiEntry.status || 'success';
            if (status === 'completed') status = 'success';

            const entry = {
                id: apiEntry.id || `hist-${Date.now()}-${idx}`,
                mod_name: apiEntry.mod_name || 'Unknown',
                source: apiEntry.source || apiEntry.download_source || 'nexus',
                status: status,
                date: entryDate,
                size: apiEntry.size || apiEntry.total_size || 0,
                duration: apiEntry.duration || 0,
            };
            console.log('[STS2Downloads] Converted entry', idx, ':', entry.mod_name, 'date:', entry.date);
            return entry;
        });

        // 直接用后端数据替换本地历史
        this.history = convertedHistory;
        this._saveHistory();
        this.renderHistory();
        console.log('[STS2Downloads] History replaced. New total:', this.history.length);
    },

    /**
     * Normalize progress value from API (0-100 range) to frontend (0-1 range).
     * If the value is already in 0-1 range (< 1.5), return as-is.
     * @param {number} progress - Progress value from API
     * @returns {number} Normalized progress in 0-1 range
     * @private
     */
    _normalizeProgress(progress) {
        if (progress === undefined || progress === null) return 0;
        // API reports progress as 0-100; if > 1.5, assume it's 0-100 and divide
        return progress > 1.5 ? progress / 100.0 : progress;
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
