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
     * Initialize Aria2 connection - 检查是否已连接
     */
    async init() {
        console.log('[Aria2] Initializing...');

        try {
            // 检查 BrowserHost.aria2Manager 是否可用
            const browserHost = window.chrome?.webview?.hostObjects?.browserHost;
            const aria2Manager = browserHost?.aria2Manager;
            if (!aria2Manager) {
                console.log('[Aria2] Aria2Manager not available');
                return false;
            }

            // 检查 Aria2 是否已经在运行（通过 GetAllDownloadsAsync 测试 RPC 连接）
            try {
                const downloads = await aria2Manager.GetAllDownloadsAsync();
                console.log('[Aria2] Connected (Aria2 already running)');
                this._initialized = true;
                return true;
            } catch (e) {
                console.log('[Aria2] RPC check failed:', e.message || e);
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

            // 转换 options 为 Dictionary<string, string>（如果是 null 则传空对象）
            const ariaOptions = {};
            if (options) {
                for (const [key, value] of Object.entries(options)) {
                    ariaOptions[key] = String(value);
                }
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
        console.log('[Aria2] pause called with gid:', gid);
        try {
            const host = window.chrome.webview.hostObjects.browserHost.aria2Manager;
            console.log('[Aria2] host.aria2Manager:', host);
            const result = await host.PauseAsync(gid);
            console.log('[Aria2] PauseAsync returned:', result);
            return result === "true";
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
        console.log('[Aria2] resume called with gid:', gid);
        try {
            const host = window.chrome.webview.hostObjects.browserHost.aria2Manager;
            const result = await host.UnpauseAsync(gid);
            console.log('[Aria2] UnpauseAsync returned:', result);
            return result === "true";
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
        console.log('[Aria2] remove called with gid:', gid);
        try {
            const host = window.chrome.webview.hostObjects.browserHost.aria2Manager;
            const result = await host.RemoveAsync(gid);
            console.log('[Aria2] RemoveAsync returned:', result);
            return result;
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
            const result = await host.GetAllDownloadsAsync();
            if (!result) return [];
            // 如果返回的是 JSON 字符串（C# 新版），解析它
            if (typeof result === 'string') {
                try {
                    return JSON.parse(result) || [];
                } catch {
                    return [];
                }
            }
            // WebView2 may serialize List<T> as an object with numeric keys, not array
            if (Array.isArray(result)) {
                return result;
            }
            // Handle object with numeric keys (WebView2 serialization quirk)
            if (typeof result === 'object') {
                const keys = Object.keys(result).filter(k => !isNaN(parseInt(k)));
                if (keys.length > 0) {
                    return keys.map(k => result[k]);
                }
            }
            return [];
        } catch (e) {
            console.error('[Aria2] GetAllActive failed:', e);
            return [];
        }
    },

    async getAll() {
        return await this.getAllActive();
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
        try {
            const host = window.chrome.webview.hostObjects.browserHost.aria2Manager;
            const options = await host.GetGlobalOptionsAsync();
            return options || {};
        } catch (e) {
            console.error('[Aria2] GetOptions failed:', e);
            return {};
        }
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
    // 优先从 localStorage 加载（持久化）
    const stored = localStorage.getItem('aria2-settings');
    if (stored) {
        try {
            const options = JSON.parse(stored);
            document.getElementById('max-connections').value = options['max-connection-per-server'] || 16;
            document.getElementById('max-concurrent').value = options['max-concurrent-downloads'] || 8;
            document.getElementById('split-count').value = options['split'] || 16;
            const speedLimit = parseInt(options['max-download-limit'] || '0') / 1024;
            document.getElementById('max-download-speed').value = speedLimit || 0;
            document.getElementById('max-retry').value = options['max-tries'] || 5;
            document.getElementById('retry-delay').value = options['retry-wait'] || 3;
            document.getElementById('auto-resume').checked = options['auto-resume'] === 'true';
            console.log('[DownloadSettings] Loaded from localStorage');
            return;
        } catch (e) {
            console.warn('[DownloadSettings] Failed to parse stored settings:', e);
        }
    }

    // 尝试从 Aria2 加载
    try {
        const options = await Aria2.getOptions();
        if (options && Object.keys(options).length > 0) {
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
        console.log('[DownloadSettings] Failed to load from Aria2:', e);
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

    // 保存到 localStorage（持久化）
    localStorage.setItem('aria2-settings', JSON.stringify(settings));
    console.log('[DownloadSettings] Saved to localStorage:', settings);

    try {
        // 同时保存到 Aria2
        await Aria2.setOptions(settings);
    } catch (e) {
        console.warn('[DownloadSettings] Failed to save to Aria2:', e);
    }

    window.hideDownloadSettings();

    // 显示成功通知
    if (window.app?.notifications) {
        window.app.notifications.show('下载器设置已保存', 'success');
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