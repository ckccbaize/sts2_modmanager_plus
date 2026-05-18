/**
 * Aria2 WebUI Bridge
 *
 * Provides simple interface for WebUI to interact with Aria2 via BrowserHost.
 * Methods are exposed as global functions that call BrowserHost Host Objects.
 */

window.Aria2 = {
    _initialized: false,
    _callbacks: {},

    /**
     * Initialize Aria2 connection and setup callbacks
     */
    async init() {
        console.log('[Aria2] Initializing...');

        try {
            // Check if BrowserHost is available
            if (!window.chrome?.webview?.hostObjects?.browserHost) {
                console.log('[Aria2] BrowserHost not available');
                return false;
            }

            // Initialize Aria2 via BrowserHost
            const result = await this._call('Aria2Init');
            if (result?.success) {
                this._initialized = true;
                console.log('[Aria2] Connected, version:', result.version);
                return true;
            }
        } catch (e) {
            console.error('[Aria2] Init failed:', e);
        }

        this._initialized = false;
        return false;
    },

    /**
     * Add a download task
     * @param {string} url - Download URL
     * @param {string} savePath - Save path
     * @param {object} options - Aria2 options (connections, split, etc.)
     * @returns {Promise<string>} GID or null
     */
    async addDownload(url, savePath, options = {}) {
        if (!this._initialized) {
            console.warn('[Aria2] Not initialized');
            return null;
        }

        try {
            const result = await this._call('Aria2AddDownload', {
                url: url,
                savePath: savePath,
                options: options
            });

            if (result?.gid) {
                console.log('[Aria2] Download added:', result.gid);
                return result.gid;
            }
        } catch (e) {
            console.error('[Aria2] Add download failed:', e);
        }

        return null;
    },

    /**
     * Pause a download
     * @param {string} gid
     */
    async pause(gid) {
        return await this._call('Aria2Pause', gid);
    },

    /**
     * Resume a paused download
     * @param {string} gid
     */
    async resume(gid) {
        return await this._call('Aria2Resume', gid);
    },

    /**
     * Remove/cancel a download
     * @param {string} gid
     */
    async remove(gid) {
        return await this._call('Aria2Remove', gid);
    },

    /**
     * Get download status
     * @param {string} gid
     * @returns {Promise<object>} Status object
     */
    async getStatus(gid) {
        return await this._call('Aria2GetStatus', gid);
    },

    /**
     * Get all active downloads
     * @returns {Promise<Array>}
     */
    async getAllActive() {
        return await this._call('Aria2GetAllActive') || [];
    },

    /**
     * Get download history
     * @returns {Promise<Array>}
     */
    async getHistory() {
        return await this._call('Aria2GetHistory') || [];
    },

    /**
     * Set global options (connections, speed limits, etc.)
     * @param {object} options
     */
    async setOptions(options) {
        return await this._call('Aria2SetOptions', options);
    },

    /**
     * Get global options
     * @returns {Promise<object>}
     */
    async getOptions() {
        return await this._call('Aria2GetOptions') || {};
    },

    /**
     * Set global option by key
     * @param {string} key - Option key (e.g., "max-connection-per-server")
     * @param {string} value - Option value
     */
    async setOption(key, value) {
        return await this.setOptions({ [key]: value });
    },

    /**
     * Register callback for download events
     * @param {string} event - Event name: 'progress', 'complete', 'error'
     * @param {function} callback
     */
    on(event, callback) {
        if (!this._callbacks[event]) {
            this._callbacks[event] = [];
        }
        this._callbacks[event].push(callback);
    },

    /**
     * Emit event to registered callbacks
     * @private
     */
    _emit(event, data) {
        const callbacks = this._callbacks[event] || [];
        callbacks.forEach(cb => {
            try {
                cb(data);
            } catch (e) {
                console.error('[Aria2] Callback error:', e);
            }
        });
    },

    /**
     * Internal: Call BrowserHost method
     * @private
     */
    async _call(method, data = null) {
        if (!window.chrome?.webview?.hostObjects?.browserHost) {
            throw new Error('BrowserHost not available');
        }

        try {
            const paramStr = data ? JSON.stringify(data) : '{}';
            const result = window.chrome.webview.hostObjects.browserHost[method](paramStr);

            if (typeof result === 'string') {
                return JSON.parse(result);
            }
            return result;
        } catch (e) {
            console.error('[Aria2] Call failed:', method, e);
            return null;
        }
    },

    /**
     * Get connection status
     */
    isConnected() {
        return this._initialized;
    }
};

// Download settings panel functions
window.showDownloadSettings = function() {
    const panel = document.getElementById('download-settings-panel');
    if (panel) {
        panel.style.display = 'flex';
        window.loadDownloadSettings();
    }
};

window.hideDownloadSettings = function() {
    const panel = document.getElementById('download-settings-panel');
    if (panel) {
        panel.style.display = 'none';
    }
};

window.loadDownloadSettings = async function() {
    // Load current settings from Backend
    try {
        const options = await Aria2.getOptions();
        if (options) {
            document.getElementById('max-connections').value = options['max-connection-per-server'] || 16;
            document.getElementById('max-concurrent').value = options['max-concurrent-downloads'] || 8;
            document.getElementById('split-count').value = options['split'] || 16;
            document.getElementById('max-download-speed').value = parseInt(options['max-download-limit'] || '0') / 1024;
            document.getElementById('max-retry').value = options['max-tries'] || 5;
            document.getElementById('retry-delay').value = options['retry-wait'] || 3;
            document.getElementById('auto-resume').checked = options['auto-resume'] === 'true';
        }
    } catch (e) {
        console.log('[DownloadSettings] Failed to load settings:', e);
    }
};

window.saveDownloadSettings = async function() {
    const settings = {
        'max-connection-per-server': document.getElementById('max-connections').value,
        'max-concurrent-downloads': document.getElementById('max-concurrent').value,
        'split': document.getElementById('split-count').value,
        'max-download-limit': (document.getElementById('max-download-speed').value * 1024) + 'K',
        'max-tries': document.getElementById('max-retry').value,
        'retry-wait': document.getElementById('retry-delay').value,
        'auto-resume': document.getElementById('auto-resume').checked ? 'true' : 'false'
    };

    try {
        await Aria2.setOptions(settings);
        window.hideDownloadSettings();

        // Show success notification
        if (window.app?.notifications) {
            window.app.notifications.show('下载器设置已保存', 'success');
        }
    } catch (e) {
        console.error('[DownloadSettings] Failed to save:', e);
    }
};

window.resetDownloadSettings = function() {
    document.getElementById('max-connections').value = 16;
    document.getElementById('max-concurrent').value = 8;
    document.getElementById('split-count').value = 16;
    document.getElementById('max-download-speed').value = 0;
    document.getElementById('max-retry').value = 5;
    document.getElementById('retry-delay').value = 3;
    document.getElementById('auto-resume').checked = true;
};

console.log('[Aria2] WebUI Bridge loaded');