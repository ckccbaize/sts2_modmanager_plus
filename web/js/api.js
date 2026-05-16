/**
 * STS2API - HTTP API client for Godot backend communication
 *
 * Provides async methods for all backend operations.
 * Falls back gracefully when backend is unavailable.
 */
class STS2API {
    constructor() {
        this._baseUrl = '';
        this._timeout = 15000;
        this._connected = false;
        this._detectBaseUrl();
    }

    _detectBaseUrl() {
        // Running on localhost:PORT — use same origin
        const loc = window.location;
        if (loc.hostname === 'localhost' || loc.hostname === '127.0.0.1') {
            this._baseUrl = `${loc.protocol}//${loc.host}`;
        } else {
            // Opened from file:// or other — default to port 8765
            this._baseUrl = 'http://127.0.0.1:8765';
        }
        console.log('[API] _baseUrl detected:', this._baseUrl, 'location:', loc.href);
    }

    isConnected() {
        return this._connected;
    }

    async _request(method, path, body = null) {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), this._timeout);

        const opts = {
            method,
            headers: { 'Content-Type': 'application/json' },
            signal: controller.signal,
        };
        if (body !== null) {
            opts.body = JSON.stringify(body);
        }

        try {
            const resp = await fetch(this._baseUrl + path, opts);
            clearTimeout(timer);
            console.log('[API] Response status:', resp.status, 'for', path);
            if (!resp.ok) {
                throw new Error(`HTTP ${resp.status}`);
            }
            const text = await resp.text();
            console.log('[API] Response text length:', text.length, 'for', path);
            if (!text || text.trim() === '') {
                console.warn('[API] Empty response for', path);
                return { data: {} };
            }
            try {
                const parsed = JSON.parse(text);
                console.log('[API] Parsed JSON for', path, ':', parsed);
                return parsed;
            } catch (e) {
                console.warn('[API] Response is not valid JSON:', text.substring(0, 200));
                return { data: {}, raw: text };
            }
        } catch (e) {
            clearTimeout(timer);
            console.error('[API] Request failed for', path, ':', e.message);
            throw e;
        }
    }

    // ── Health ──────────────────────────────────────────────────

    async health() {
        const result = await this._request('GET', '/api/health');
        this._connected = true;
        return result;
    }

    async getVersion() {
        const result = await this._request('GET', '/api/health');
        return result.data?.version || result.version || 'v0.0.0';
    }

    // ── Mods ────────────────────────────────────────────────────

    async getMods() {
        return this._request('GET', '/api/mods');
    }

    async getMod(id) {
        return this._request('GET', `/api/mods/${encodeURIComponent(id)}`);
    }

    async enableMod(id) {
        return this._request('POST', `/api/mods/${encodeURIComponent(id)}/enable`);
    }

    async disableMod(id) {
        return this._request('POST', `/api/mods/${encodeURIComponent(id)}/disable`);
    }

    async uninstallMod(id) {
        return this._request('DELETE', `/api/mods/${encodeURIComponent(id)}`);
    }

    async installMod(filename, dataBase64) {
        return this._request('POST', '/api/mods/install', {
            filename,
            data_base64: dataBase64
        });
    }

    async resolveConflicts(conflictPendingDir) {
        return this._request('POST', '/api/mods/resolve-conflicts', {
            conflict_pending_dir: conflictPendingDir
        });
    }

    async batchEnable(ids) {
        return this._request('POST', '/api/mods/batch-enable', { mod_ids: ids });
    }

    async batchDisable(ids) {
        return this._request('POST', '/api/mods/batch-disable', { mod_ids: ids });
    }

    async getModNotes() {
        return this._request('GET', '/api/mods/notes');
    }

    async saveModNotes(modId, note) {
        return this._request('POST', '/api/mods/notes', { mod_id: modId, note });
    }

    async saveTagData(tagData, currentTag) {
        return this._request('POST', '/api/mods/save-tag-data', { tag_data: tagData, current_tag: currentTag });
    }

    // ── Saves ───────────────────────────────────────────────────

    async getSaves() {
        return this._request('GET', '/api/saves');
    }

    async importSave(filename, dataBase64) {
        return this._request('POST', '/api/saves/import', {
            filename,
            data_base64: dataBase64
        });
    }

    async exportSave(id, exportPath = null) {
        if (exportPath != null && exportPath !== '') {
            return this._request('POST', `/api/saves/${encodeURIComponent(id)}/export`, { export_path: exportPath });
        }
        return this._request('POST', `/api/saves/${encodeURIComponent(id)}/export`);
    }

    async backupSave(id) {
        return this._request('POST', `/api/saves/${encodeURIComponent(id)}/backup`);
    }

    async restoreSave(id, backupPath = null) {
        const body = backupPath !== null ? { backup_path: backupPath } : null;
        return this._request('POST', `/api/saves/${encodeURIComponent(id)}/restore`, body);
    }

    async getSaveBackups(id) {
        return this._request('GET', `/api/saves/${encodeURIComponent(id)}/backups`);
    }

    async deleteSave(id) {
        return this._request('DELETE', `/api/saves/${encodeURIComponent(id)}`);
    }

    async overwriteSave(direction, steamId, createBackup = true, sourceSteamId = null, sourcePath = null) {
        const payload = {
            direction,
            steam_id: steamId,
            create_backup: createBackup
        };
        // 只在有值时才添加可选参数，避免传递 null
        if (sourceSteamId) {
            payload.source_steam_id = sourceSteamId;
        }
        if (sourcePath) {
            payload.source_path = sourcePath;
        }
        return this._request('POST', '/api/saves/overwrite', payload);
    }

    async syncCloud(provider, steamId) {
        return this._request('POST', '/api/saves/sync', {
            provider,
            steam_id: steamId
        });
    }

    // ── Bundles ─────────────────────────────────────────────────

    async getBundles() {
        return this._request('GET', '/api/bundles');
    }

    async enableBundle(id, presetName = null) {
        const body = presetName !== null ? { preset_name: presetName } : null;
        return this._request('POST', `/api/bundles/${encodeURIComponent(id)}/enable`, body);
    }

    async disableBundle(id) {
        return this._request('POST', `/api/bundles/${encodeURIComponent(id)}/disable`);
    }

    async deleteBundle(id) {
        return this._request('DELETE', `/api/bundles/${encodeURIComponent(id)}`);
    }

    async saveBundle(id, bundleData) {
        return this._request('PUT', `/api/bundles/${encodeURIComponent(id)}`, bundleData);
    }

    async updateBundlePresets(id, presets) {
        return this._request('PUT', `/api/bundles/${encodeURIComponent(id)}/presets`, { presets });
    }

    async applyBundlePreset(id, presetName) {
        return this._request('POST', `/api/bundles/${encodeURIComponent(id)}/apply-preset`, { preset_name: presetName });
    }

    async exportBundle(id) {
        return this._request('POST', `/api/bundles/${encodeURIComponent(id)}/export`);
    }

    async exportCurrentBundle(data) {
        return this._request('POST', '/api/bundles/export-current', data);
    }

    async importBundle(filename, dataBase64) {
        return this._request('POST', '/api/bundles/import', {
            filename,
            data_base64: dataBase64
        });
    }

    async importBundleFromUrl(url) {
        return this._request('POST', '/api/bundles/import-from-url', { url });
    }

    // ── Settings ────────────────────────────────────────────────

    async getSettings() {
        return this._request('GET', '/api/settings');
    }

    async updateSettings(settings) {
        return this._request('PUT', '/api/settings', settings);
    }

    async detectGamePath() {
        return this._request('POST', '/api/settings/detect-game-path');
    }

    async detectSavePath() {
        return this._request('POST', '/api/settings/detect-save-path');
    }

    // ── Downloads ───────────────────────────────────────────────

    async getDownloads() {
        return this._request('GET', '/api/downloads');
    }

    async pauseDownload(id) {
        return this._request('POST', `/api/downloads/${encodeURIComponent(id)}/pause`);
    }

    async resumeDownload(id) {
        return this._request('POST', `/api/downloads/${encodeURIComponent(id)}/resume`);
    }

    async cancelDownload(id) {
        return this._request('DELETE', `/api/downloads/${encodeURIComponent(id)}`);
    }

    // ── Launch ──────────────────────────────────────────────────

    async launchGame(mode) {
        return this._request('POST', '/api/launch', { mode });
    }

    // ── Nexus ───────────────────────────────────────────────────

    async nexusDownload(data) {
        return this._request('POST', '/api/download', data);
    }

    // ── Upload Helper ───────────────────────────────────────────

    /**
     * Read a File object and return {filename, data_base64} for API upload.
     * @param {File} file
     * @returns {Promise<{filename: string, data_base64: string}>}
     */
    uploadFile(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const base64 = reader.result.split(',')[1];
                resolve({ filename: file.name, data_base64: base64 });
            };
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }

    // ── Update ──────────────────────────────────────────────────

    async checkUpdate() {
        return this._request('GET', '/api/update/check');
    }

    async downloadUpdate(downloadUrl) {
        return this._request('POST', '/api/update/download', {
            download_url: downloadUrl
        });
    }

    // ── Cloud Sync ──────────────────────────────────────────────

    async syncCloud(provider, steamId) {
        const body = { provider };
        if (steamId) body.steam_id = steamId;
        return this._request('POST', '/api/saves/sync', body);
    }

    // ── Dependency Check ─────────────────────────────────────────

    async checkDependencies(modId) {
        return this._request('GET', `/api/mods/${encodeURIComponent(modId)}/dependencies`);
    }

    async saveModOrganization(boxes, itemOrder, enableModDrag = false, enableOverrideOrder = false) {
        return this._request('POST', '/api/mods/save-mod-organization', {
            boxes,
            item_order: itemOrder,
            enable_mod_drag: enableModDrag,
            enable_override_order: enableOverrideOrder
        });
    }

    async getModOrganization() {
        return this._request('GET', '/api/mods/organization');
    }

    // ── Directory Selection ─────────────────────────────────────

    /**
     * Open native folder picker via BrowserHost C# Host Object.
     * Shows proper Windows folder dialog via AddHostObjectToScript.
     * @returns {Promise<{success: boolean, path?: string, message?: string}>}
     */
    async selectDirectory() {
        console.log('[API] selectDirectory called');
        console.log('[API] window.chrome:', window.chrome);
        console.log('[API] window.chrome.webview:', window.chrome?.webview);
        console.log('[API] window.chrome.webview.hostObjects:', window.chrome?.webview?.hostObjects);
        try {
            // Use BrowserHost's native Host Object to call FolderBrowserDialog
            if (window.chrome?.webview?.hostObjects) {
                console.log('[API] Using chrome.webview.hostObjects.browserHost');
                const result = await window.chrome.webview.hostObjects.browserHost.SelectFolder();
                console.log('[API] SelectFolder result:', result);
                if (result && typeof result === 'string' && result.length > 0) {
                    return { success: true, path: result };
                } else {
                    return { success: false, message: 'User canceled or empty path' };
                }
            } else {
                console.warn('[API] chrome.webview.hostObjects not available, fallback to webkitdirectory');
            }
        } catch (e) {
            console.warn('[API] Host object call failed:', e);
        }

        // Fallback: webkitdirectory input
        return new Promise((resolve) => {
            const input = document.createElement('input');
            input.type = 'file';
            input.webkitdirectory = true;
            input.style.cssText = 'position:fixed;top:0;left:0;width:0;height:0;opacity:0;z-index:-9999;pointer-events:none;display:none;';
            document.body.appendChild(input);

            const cleanup = () => {
                if (document.body.contains(input)) {
                    document.body.removeChild(input);
                }
            };

            input.addEventListener('change', () => {
                cleanup();
                const files = input.files;
                if (!files || files.length === 0) {
                    resolve({ success: false, message: 'User canceled' });
                    return;
                }
                const dirPath = files[0].path;
                if (dirPath && (dirPath.includes('/') || dirPath.includes('\\'))) {
                    console.log('[API] Selected path (fallback):', dirPath);
                    resolve({ success: true, path: dirPath });
                } else {
                    resolve({ success: false, message: 'Invalid path: ' + dirPath });
                }
            });

            input.addEventListener('cancel', () => {
                cleanup();
                resolve({ success: false, message: 'User canceled' });
            });

            const timeout = setTimeout(() => {
                cleanup();
                resolve({ success: false, message: 'Timeout' });
            }, 30000);

            input.click();
        });
    }
}

window.STS2API = STS2API;
