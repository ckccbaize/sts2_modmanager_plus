/**
 * STS2Nexus - Nexus Mods page controller
 *
 * Handles navigation between Web UI and Nexus Mods website
 * via BrowserHost Host Object methods.
 * Version: 4.2 - Debug COM interop issues
 */
window.STS2Nexus = {

    // ── State ────────────────────────────────────────────────
    _app: null,
    _rendered: false,

    // ── Lifecycle ────────────────────────────────────────────

    /**
     * Initialize the Nexus module. Called once at startup.
     * @param {STS2App} app
     */
    init(app) {
        this._app = app;
        console.log('[STS2Nexus] Initialized');
        this._debugHostObjects();
    },

    /** Debug Host Object availability */
    _debugHostObjects() {
        console.log('[STS2Nexus] Checking Host Objects...');
        const chrome = window.chrome;
        console.log('[STS2Nexus] window.chrome:', !!chrome);
        if (chrome) {
            console.log('[STS2Nexus] window.chrome.webview:', !!chrome.webview);
            if (chrome.webview) {
                console.log('[STS2Nexus] window.chrome.webview.hostObjects:', !!chrome.webview.hostObjects);
                const ho = chrome.webview.hostObjects;
                if (ho) {
                    console.log('[STS2Nexus] hostObjects keys:', Object.keys(ho));
                    console.log('[STS2Nexus] hostObjects.browserHost:', !!ho.browserHost);
                    console.log('[STS2Nexus] hostObjects.sync:', !!ho.sync);
                    if (ho.sync) {
                        console.log('[STS2Nexus] hostObjects.sync keys:', Object.keys(ho.sync));
                        console.log('[STS2Nexus] hostObjects.sync.browserHost:', !!ho.sync.browserHost);
                    }
                }
            }
        }
    },

    /** Called when the Nexus page becomes active. */
    onEnter() {
        if (!this._rendered) {
            this._rendered = true;
        }

        // 【关键修复】进入 N 网页面时，将标签重置为默认标签
        // 这样即使在 N 网页面关闭管理器，重启后也会进入模组页
        if (this._app?.mods) {
            const defaultTag = this._app.mods._defaultTags?.[0] || '单人模组';
            if (this._app.mods.current_tag !== defaultTag) {
                console.log('[STS2Nexus] Resetting current_tag to:', defaultTag);
                this._app.mods.current_tag = defaultTag;
                this._app.mods.renderTagPresets();
            }
        }

        // Navigate to Nexus Mods via BrowserHost
        this._navigateToNexus();
    },

    /** Called when leaving the Nexus page. */
    onLeave() {
        // 【关键修复】离开 N 网页面时，将标签重置为默认标签并保存
        // 确保"返回首页"总是回到模组页，且状态已持久化
        if (this._app?.mods) {
            const defaultTag = this._app.mods._defaultTags?.[0] || '单人模组';
            if (this._app.mods.current_tag !== defaultTag) {
                console.log('[STS2Nexus] onLeave: Resetting current_tag to:', defaultTag);
                this._app.mods.current_tag = defaultTag;
                this._app.mods.renderTagPresets();

                // 【关键】立即保存到后端，确保重启后也是正确的
                if (this._app.api && this._app.isBackendConnected()) {
                    try {
                        // 保存当前标签的启用模组
                        const currentEnabledMods = Object.keys(this._app.mods.enabled_mods).filter(id => this._app.mods.enabled_mods[id]);
                        this._app.mods.tag_data[defaultTag] = currentEnabledMods;
                        // 保存到后端
                        this._app.api.saveTagData(this._app.mods.tag_data, defaultTag);
                        console.log('[STS2Nexus] Saved default tag to backend:', defaultTag);
                    } catch (e) {
                        console.warn('[STS2Nexus] Failed to save tag data:', e);
                    }
                }
            }
        }

        // Navigate back to local Web UI via BrowserHost
        this._navigateToLocalhost();
    },

    // ── Navigation ───────────────────────────────────────────

    /**
     * Get the BrowserHost object from WebView2
     * Uses sync proxy for COM interop compatibility
     * @private
     */
    _getBrowserHost() {
        // Try sync proxy first (required for synchronous COM methods)
        const ho = window.chrome?.webview?.hostObjects;
        if (ho?.sync?.browserHost) {
            console.log('[STS2Nexus] Using hostObjects.sync.browserHost');
            return ho.sync.browserHost;
        }
        if (ho?.browserHost) {
            console.log('[STS2Nexus] Using hostObjects.browserHost (async)');
            return ho.browserHost;
        }
        console.log('[STS2Nexus] BrowserHost not found');
        return null;
    },

    /**
     * Navigate to Nexus Mods website via BrowserHost
     * @private
     */
    _navigateToNexus() {
        console.log('[STS2Nexus] Requesting navigation to Nexus Mods');

        const browserHost = this._getBrowserHost();
        if (browserHost) {
            try {
                // Try to inspect the object
                console.log('[STS2Nexus] browserHost type:', typeof browserHost);
                console.log('[STS2Nexus] browserHost methods:', Object.getOwnPropertyNames(browserHost));

                // Call synchronous method - don't use await since it's sync
                const result = browserHost.NavigateToNexus();
                console.log('[STS2Nexus] NavigateToNexus returned:', result);
                console.log('[STS2Nexus] Navigation request sent to BrowserHost');
            } catch (e) {
                console.error('[STS2Nexus] Failed to navigate:', e);
                console.error('[STS2Nexus] Error details:', e.message, e.stack);
                this._showNavigationError();
            }
        } else {
            console.warn('[STS2Nexus] BrowserHost not available');
            this._showNavigationError();
        }
    },

    /**
     * Navigate back to local Web UI via BrowserHost
     * @private
     */
    _navigateToLocalhost() {
        console.log('[STS2Nexus] Requesting navigation back to Web UI');

        const browserHost = this._getBrowserHost();
        if (browserHost) {
            try {
                browserHost.NavigateToLocalhost();
                console.log('[STS2Nexus] Navigation request sent to BrowserHost');
            } catch (e) {
                console.error('[STS2Nexus] Failed to navigate back:', e);
            }
        }
    },

    /**
     * Show error when navigation fails
     * @private
     */
    _showNavigationError() {
        const container = document.getElementById('page-nexus');
        if (container) {
            container.innerHTML = `
                <div class="empty-state" style="padding:60px 40px;text-align:center;">
                    <div class="empty-icon" style="font-size:48px;margin-bottom:16px;">⚠️</div>
                    <h3 style="margin-bottom:12px;">无法加载 Nexus Mods</h3>
                    <p style="color:var(--text-secondary);margin-bottom:20px;">
                        BrowserHost 连接失败，请确保使用内嵌浏览器打开此页面。
                    </p>
                    <button class="btn btn-primary" onclick="window.STS2Nexus._navigateToNexus()">
                        重试
                    </button>
                </div>
            `;
        }
    },

    // ── Public API ───────────────────────────────────────────

    /**
     * Refresh/reload the Nexus page
     */
    refreshUI() {
        this._navigateToNexus();
    },

    /**
     * Show a notification when download starts
     * Called by the extension via BrowserHost
     * @param {string} modName
     * @param {string} status
     */
    onDownloadStatus(modName, status) {
        const message = status === 'success'
            ? this._app.i18n.translate_fmt('nexus_download_started', [modName])
            : this._app.i18n.translate('download_failed');

        this._app.notifications.show(
            message,
            status === 'success' ? 'success' : 'error',
            3000
        );
    }
};
