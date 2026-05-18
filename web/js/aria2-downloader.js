/**
 * Aria2 Downloader Integration
 *
 * This module handles communication with Aria2 via BrowserHost
 * for multi-threaded downloading with resume support.
 */

class Aria2Downloader {
    constructor(app) {
        this._app = app;
        this._isConnected = false;
        this._activeTasks = new Map(); // gid -> download info
        this._pollInterval = null;
        this._pollMs = 500; // 500ms poll interval as recommended
    }

    /**
     * Initialize Aria2 connection
     */
    async init() {
        console.log('[Aria2Downloader] Initializing...');

        try {
            // Check if Aria2 is available via BrowserHost
            if (window.chrome?.webview?.hostObjects?.browserHost) {
                // Try to get Aria2 status
                const status = await this._callHostMethod('GetAria2Status');
                if (status) {
                    this._isConnected = true;
                    console.log('[Aria2Downloader] Connected to Aria2');
                    this._startPolling();
                    return true;
                }
            }
        } catch (e) {
            console.log('[Aria2Downloader] Not connected:', e.message);
        }

        this._isConnected = false;
        return false;
    }

    /**
     * Add a new download task
     * @param {string} url - Download URL
     * @param {string} modName - Mod name for display
     * @param {object} options - Download options
     * @returns {Promise<string>} Download ID (gid)
     */
    async addDownload(url, modName, options = {}) {
        console.log('[Aria2Downloader] Adding download:', url, modName);

        try {
            const result = await this._callHostMethod('Aria2AddDownload', {
                url: url,
                savePath: this._getDownloadsDir() + '/' + this._sanitizeFileName(modName) + '.zip',
                options: options
            });

            if (result && result.gid) {
                this._activeTasks.set(result.gid, {
                    url: url,
                    mod_name: modName,
                    status: 'downloading',
                    progress: 0,
                    speed: 0,
                    total_length: 0,
                    completed_length: 0
                });

                console.log('[Aria2Downloader] Download added, gid:', result.gid);
                return result.gid;
            }
        } catch (e) {
            console.error('[Aria2Downloader] Failed to add download:', e);
        }

        return null;
    }

    /**
     * Pause a download
     * @param {string} gid - Download ID
     */
    async pause(gid) {
        console.log('[Aria2Downloader] Pausing:', gid);
        try {
            await this._callHostMethod('Aria2Pause', gid);
            if (this._activeTasks.has(gid)) {
                this._activeTasks.get(gid).status = 'paused';
            }
        } catch (e) {
            console.error('[Aria2Downloader] Failed to pause:', e);
        }
    }

    /**
     * Resume a paused download
     * @param {string} gid - Download ID
     */
    async resume(gid) {
        console.log('[Aria2Downloader] Resuming:', gid);
        try {
            await this._callHostMethod('Aria2Resume', gid);
            if (this._activeTasks.has(gid)) {
                this._activeTasks.get(gid).status = 'downloading';
            }
        } catch (e) {
            console.error('[Aria2Downloader] Failed to resume:', e);
        }
    }

    /**
     * Remove/cancel a download
     * @param {string} gid - Download ID
     */
    async remove(gid) {
        console.log('[Aria2Downloader] Removing:', gid);
        try {
            await this._callHostMethod('Aria2Remove', gid);
            this._activeTasks.delete(gid);
        } catch (e) {
            console.error('[Aria2Downloader] Failed to remove:', e);
        }
    }

    /**
     * Get download status
     * @param {string} gid - Download ID
     * @returns {Promise<object>} Download info
     */
    async getStatus(gid) {
        try {
            const status = await this._callHostMethod('Aria2GetStatus', gid);
            return status;
        } catch (e) {
            console.error('[Aria2Downloader] Failed to get status:', e);
            return null;
        }
    }

    /**
     * Get all active downloads
     * @returns {Promise<Array>} List of active downloads
     */
    async getAllActive() {
        try {
            const downloads = await this._callHostMethod('Aria2GetAllActive');
            return downloads || [];
        } catch (e) {
            console.error('[Aria2Downloader] Failed to get all active:', e);
            return [];
        }
    }

    /**
     * Update global options (connection count, speed limits, etc.)
     * @param {object} options - Aria2 options
     */
    async setOptions(options) {
        console.log('[Aria2Downloader] Setting options:', options);
        try {
            await this._callHostMethod('Aria2SetOptions', options);
        } catch (e) {
            console.error('[Aria2Downloader] Failed to set options:', e);
        }
    }

    /**
     * Start polling for status updates
     */
    _startPolling() {
        if (this._pollInterval) return;

        this._pollInterval = setInterval(async () => {
            if (!this._isConnected) {
                this._stopPolling();
                return;
            }

            try {
                const activeDownloads = await this.getAllActive();

                for (const dl of activeDownloads) {
                    this._updateTask(dl.gid, dl);

                    // Check for completion
                    if (dl.status === 'complete') {
                        this._onDownloadComplete(dl);
                    } else if (dl.status === 'error') {
                        this._onDownloadError(dl);
                    }
                }

                // Emit progress update
                this._emitProgress();
            } catch (e) {
                console.error('[Aria2Downloader] Poll error:', e);
            }
        }, this._pollMs);
    }

    /**
     * Stop polling
     */
    _stopPolling() {
        if (this._pollInterval) {
            clearInterval(this._pollInterval);
            this._pollInterval = null;
        }
    }

    /**
     * Update task info
     */
    _updateTask(gid, info) {
        if (this._activeTasks.has(gid)) {
            Object.assign(this._activeTasks.get(gid), info);
        } else {
            this._activeTasks.set(gid, info);
        }
    }

    /**
     * Handle download completion
     */
    _onDownloadComplete(dl) {
        console.log('[Aria2Downloader] Download complete:', dl.gid, dl.mod_name);

        // Notify app
        this._app.emit('aria2-download-complete', {
            gid: dl.gid,
            mod_name: dl.mod_name,
            save_path: dl.save_path
        });

        // Remove from active
        this._activeTasks.delete(dl.gid);
    }

    /**
     * Handle download error
     */
    _onDownloadError(dl) {
        console.error('[Aria2Downloader] Download error:', dl.gid, dl.mod_name);

        // Notify app
        this._app.emit('aria2-download-error', {
            gid: dl.gid,
            mod_name: dl.mod_name,
            error: dl.error || 'Unknown error'
        });

        // Remove from active
        this._activeTasks.delete(dl.gid);
    }

    /**
     * Emit progress update
     */
    _emitProgress() {
        const activeList = Array.from(this._activeTasks.values());
        this._app.emit('aria2-progress', activeList);
    }

    /**
     * Call BrowserHost method
     */
    async _callHostMethod(method, ...args) {
        if (!window.chrome?.webview?.hostObjects?.browserHost) {
            throw new Error('BrowserHost not available');
        }

        const argStr = args.length > 0 ? JSON.stringify(args) : '{}';
        const result = window.chrome.webview.hostObjects.browserHost[method](argStr);

        if (typeof result === 'string') {
            return JSON.parse(result);
        }
        return result;
    }

    /**
     * Get downloads directory
     */
    _getDownloadsDir() {
        return this._app?.store?.get('downloads_dir') || './downloads';
    }

    /**
     * Sanitize file name
     */
    _sanitizeFileName(name) {
        return name.replace(/[<>:"/\\|?*]/g, '_').substring(0, 100);
    }

    /**
     * Destroy downloader
     */
    destroy() {
        this._stopPolling();
        this._activeTasks.clear();
        this._isConnected = false;
    }
}

// Export for use in downloads.js
window.Aria2Downloader = Aria2Downloader;