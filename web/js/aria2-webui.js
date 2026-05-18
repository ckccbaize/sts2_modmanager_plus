/**
 * Aria2 WebUI Bridge
 *
 * Provides simple interface for WebUI to interact with Aria2 via BrowserHost.
 * Methods are exposed as global functions that call BrowserHost Host Objects.
 *
 * 架构: WebUI ←→ BrowserHost.aria2Manager ←→ aria2c.exe (RPC 6800)
 */

window.Aria2 = {
    _initialized: false,
    _callbacks: {},

    /**
     * Initialize Aria2 connection - 启动 Aria2 进程
     */
    async init() {
        console.log('[Aria2] Initializing...');

        try {
            // 检查 BrowserHost.aria2Manager 是否可用
            const host = window.chrome?.webview?.hostObjects?.browserHost?.aria2Manager;
            if (!host) {
                console.log('[Aria2] Aria2Manager not available');
                return false;
            }

            // 查找 aria2c.exe（与 BrowserHost.exe 同目录，或 PATH 中）
            const aria2Paths = [
                '.\\aria2c.exe',  // 同目录（相对路径）
                'E:\\modmanager_project\\sts-2-modmanager\\browser_host\\publish\\aria2c.exe',
                'C:\\aria2\\aria2c.exe',
                'C:\\Program Files\\aria2\\aria2c.exe',
                'aria2c.exe'  // PATH 中
            ];

            let started = false;
            for (const path of aria2Paths) {
                try {
                    const result = await host.Start(path);
                    if (result) {
                        console.log('[Aria2] Aria2 started from:', path);
                        started = true;
                        this._initialized = true;
                        return true;
                    }
                } catch (e) {
                    console.log('[Aria2] Path not found:', path);
                }
            }

            // 尝试使用 PATH 中的 aria2c
            if (!started) {
                try {
                    const result = await host.Start('aria2c.exe');
                    if (result) {
                        console.log('[Aria2] Aria2 started from PATH');
                        this._initialized = true;
                        return true;
                    }
                } catch (e) {
                    console.log('[Aria2] PATH check failed:', e);
                }
            }
        } catch (e) {
            console.error('[Aria2] Init failed:', e);
        }

        this._initialized = false;
        return false;
    },

    /**
     * 添加下载任务
     * @param {string} url - 下载 URL
     * @param {string} savePath - 保存路径
     * @param {object} options - Aria2 选项
     * @returns {Promise<string>} GID 或 null
     */
    async addDownload(url, savePath, options = {}) {
        if (!this._initialized) {
            console.warn('[Aria2] Not initialized');
            return null;
        }

        try {
            const host = window.chrome.webview.hostObjects.browserHost.aria2Manager;

            // 转换 options 为 Dictionary<string, string>
            const ariaOptions = {};
            for (const [key, value] of Object.entries(options)) {
                ariaOptions[key] = String(value);
            }

            const gid = await host.AddDownloadAsync(url, savePath, ariaOptions);
            if (gid) {
                console.log('[Aria2] Download added:', gid);
                return gid;
            }
        } catch (e) {
            console.error('[Aria2] Add download failed:', e);
        }

        return null;
    },

    /**
     * 暂停下载
     * @param {string} gid
     */
    async pause(gid) {
        try {
            const host = window.chrome.webview.hostObjects.browserHost.aria2Manager;
            return await host.PauseAsync(gid);
        } catch (e) {
            console.error('[Aria2] Pause failed:', e);
            return false;
        }
    },

    /**
     * 恢复下载
     * @param {string} gid
     */
    async resume(gid) {
        try {
            const host = window.chrome.webview.hostObjects.browserHost.aria2Manager;
            return await host.UnpauseAsync(gid);
        } catch (e) {
            console.error('[Aria2] Resume failed:', e);
            return false;
        }
    },

    /**
     * 取消下载
     * @param {string} gid
     */
    async remove(gid) {
        try {
            const host = window.chrome.webview.hostObjects.browserHost.aria2Manager;
            return await host.RemoveAsync(gid);
        } catch (e) {
            console.error('[Aria2] Remove failed:', e);
            return false;
        }
    },

    /**
     * 获取下载状态
     * @param {string} gid
     * @returns {Promise<object>} 状态对象
     */
    async getStatus(gid) {
        try {
            const host = window.chrome.webview.hostObjects.browserHost.aria2Manager;
            const status = await host.GetStatusAsync(gid);
            return status;
        } catch (e) {
            console.error('[Aria2] GetStatus failed:', e);
            return null;
        }
    },

    /**
     * 获取所有活跃下载
     * @returns {Promise<Array>}
     */
    async getAllActive() {
        try {
            const host = window.chrome.webview.hostObjects.browserHost.aria2Manager;
            const downloads = await host.GetAllDownloadsAsync();
            return downloads || [];
        } catch (e) {
            console.error('[Aria2] GetAllActive failed:', e);
            return [];
        }
    },

    /**
     * 获取下载历史（暂无实现，保留接口）
     * @returns {Promise<Array>}
     */
    async getHistory() {
        // TODO: 需要 Aria2Manager 实现历史记录存储
        return [];
    },

    /**
     * 设置全局选项（连接数、速度限制等）
     * @param {object} options
     */
    async setOptions(options) {
        try {
            const host = window.chrome.webview.hostObjects.browserHost.aria2Manager;

            // 转换选项
            const ariaOptions = {};
            for (const [key, value] of Object.entries(options)) {
                ariaOptions[key] = String(value);
            }

            await host.SetGlobalOptionsAsync(ariaOptions);
            console.log('[Aria2] Options set:', options);
        } catch (e) {
            console.error('[Aria2] SetOptions failed:', e);
        }
    },

    /**
     * 获取全局选项
     * @returns {Promise<object>}
     */
    async getOptions() {
        // TODO: 需要 Aria2Manager 实现 GetGlobalOptions
        return {};
    },

    /**
     * 设置单个选项
     * @param {string} key - 选项键
     * @param {string} value - 选项值
     */
    async setOption(key, value) {
        return await this.setOptions({ [key]: value });
    },

    /**
     * 注册下载事件回调
     * @param {string} event - 事件名: 'progress', 'complete', 'error'
     * @param {function} callback
     */
    on(event, callback) {
        if (!this._callbacks[event]) {
            this._callbacks[event] = [];
        }
        this._callbacks[event].push(callback);
    },

    /**
     * 触发事件到已注册的回调
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
     * 获取连接状态
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
    // 加载当前设置
    try {
        const options = await Aria2.getOptions();
        if (options) {
            document.getElementById('max-connections').value = options['max-connection-per-server'] || 16;
            document.getElementById('max-concurrent').value = options['max-concurrent-downloads'] || 8;
            document.getElementById('split-count').value = options['split'] || 16;
            const speedLimit = parseInt(options['max-download-limit'] || '0') / 1024;
            document.getElementById('max-download-speed').value = speedLimit || 0;
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
        'max-download-limit': (parseInt(document.getElementById('max-download-speed').value) * 1024) + 'K',
        'max-tries': document.getElementById('max-retry').value,
        'retry-wait': document.getElementById('retry-delay').value,
        'auto-resume': document.getElementById('auto-resume').checked ? 'true' : 'false'
    };

    try {
        await Aria2.setOptions(settings);
        window.hideDownloadSettings();

        // 显示成功通知
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