/**
 * STS2Mods - Mods management page module
 * Full-featured mod manager page: search, sort, category filter,
 * tag presets, collapsible boxes, drag-drop, batch ops, details panel,
 * install/uninstall with progress.
 *
 * Requires: STS2Utils, STS2Store, STS2I18n, STS2Notifications (via app)
 */
const STS2Mods = {
    // ── State ─────────────────────────────────────────────────
    mods: [],
    displayed_mods: [],
    enabled_mods: {},
    selected_mod_id: null,
    batch_mode: false,
    batch_selected: {},

    // App reference (set on init)
    _app: null,

    // DOM cache
    _dom: {},

    // Debounced search
    _debouncedSearch: null,

    // Tag presets
    current_tag: null,
    tag_data: {},
    tag_buttons: {},

    // Boxes
    mod_boxes: [],

    // Unified item order (boxes + unboxed mods interleaved)
    item_order: [],

    // Drag-reorder state (mouse-event-based)
    _dragSourceModId: null,
    _dragSourceBoxId: null,
    _dragGhost: null,
    _dropIndicator: null,
    _dragMoved: false,
    _dragStartX: 0,
    _dragStartY: 0,
    _dragHoverBoxId: null,       // box ID the cursor is currently over
    _dragInBoxContent: false,    // true when cursor is in the box content area

    // Mod notes (user annotations)
    _modNotes: {},

    // Long press state
    _longPressTimer: null,
    _longPressTarget: null,

    // Sort / filter state
    _currentSort: 'name',
    _currentCategory: 'all',
    _searchQuery: '',

    // File input ref
    _fileInput: null,

    // Default tag presets
    _defaultTags: ['单人模组', '联机模组'],

    // Box colors cycle
    _boxColors: ['blue', 'green', 'orange', 'red', 'purple', 'yellow', 'gray', 'cyan'],

    // ── Helpers ─────────────────────────────────────────────────

    /**
     * Parse installed_time from various formats to Date.
     * Handles: Unix timestamp (seconds), Unix timestamp (ms), Date string.
     * @param {*} val
     * @returns {Date|null}
     */
    _parseTimestamp(val) {
        if (!val) return null;
        if (val instanceof Date) return val;
        const n = Number(val);
        if (!isNaN(n)) {
            // If it's a small number (< 1e12), treat as seconds; otherwise as ms
            return new Date(n < 1e12 ? n * 1000 : n);
        }
        const d = new Date(val);
        return isNaN(d.getTime()) ? null : d;
    },

    // ── Initialization ─────────────────────────────────────────

    init(app) {
        this._app = app;
        this._debouncedSearch = STS2Utils.debounce((q) => this.searchMods(q), 200);

        this._cacheDom();
        console.log('[STS2Mods] DOM cached:', !!this._dom.modList, !!this._dom.btnInstall, !!this._dom.btnBatchToggle);

        this._bindEvents();
        this._initFileInput();
        this._initDropIndicator();

        // Load persisted data
        this._loadTagData();
        this._loadBoxData();
        this._loadItemOrder();
        this._loadModNotes();
        this._loadModOrganization();
        this.loadMods();

        // Listen for language changes
        document.addEventListener('language-changed', () => {
            this.refreshUI();
        });

        // Listen for app events
        if (this._app) {
            this._app.on('language-applied', () => this.refreshUI());
            // Reload mods when bundle is enabled/disabled to sync enabled state
            this._app.on('bundle-enabled', () => {
                console.log('[STS2Mods] Bundle enabled, reloading mods...');
                this.loadMods();
            });
            this._app.on('bundle-disabled', () => {
                console.log('[STS2Mods] Bundle disabled, reloading mods...');
                this.loadMods();
            });
            // 监听下载完成事件，自动刷新模组列表
            this._app.on('download-complete', (data) => {
                console.log('[STS2Mods] Download complete, reloading mods:', data.mod_name);
                this.loadMods();
            });
            // 监听安装完成事件，自动刷新模组列表
            this._app.on('install-complete', (data) => {
                console.log('[STS2Mods] Install complete, reloading mods:', data.mod_name);
                this.loadMods();
            });
        }

        // 【关键修复】页面关闭前保存当前标签的配置（模仿Godot的_exit_tree）
        window.addEventListener('beforeunload', () => {
            this._saveCurrentTagModsSync();
        });

        console.log('[STS2Mods] Initialized. Mods:', this.mods.length, 'Displayed:', this.displayed_mods.length);
    },

    onEnter() {
        // Reload from API on each entry to ensure fresh data
        this.loadMods();
    },

    onLeave() {
        // Clean up long press if active
        this._cancelLongPress();
    },

    // ── DOM Cache ──────────────────────────────────────────────

    _cacheDom() {
        this._dom = {
            modList:        document.getElementById('mod-list'),
            searchInput:    document.getElementById('mod-search'),
            sortTrigger:    document.getElementById('sort-trigger'),
            sortMenu:       document.getElementById('sort-menu'),
            categoryTags:   document.getElementById('category-tags'),
            tagPresets:     document.getElementById('tag-presets'),
            detailsContent: document.getElementById('mod-details-content'),
            detailsPanel:   document.getElementById('mod-details'),
            dropZone:       document.getElementById('mod-drop-zone'),
            btnInstall:     document.getElementById('btn-install-mod'),
            btnUninstall:   document.getElementById('btn-uninstall'),
            btnBatchEnable: document.getElementById('btn-batch-enable'),
            btnBatchDisable:document.getElementById('btn-batch-disable'),
            btnBatchToggle: document.getElementById('btn-batch-toggle'),
            btnSelectAll:   document.getElementById('btn-select-all'),
            btnRefresh:     document.getElementById('btn-refresh-mods'),
            statusLabel:    document.getElementById('status-label'),
            loadingOverlay: document.getElementById('loading-overlay'),
            loadingText:    document.getElementById('loading-text'),
            loadingProgress:document.getElementById('loading-progress'),
        };
    },

    // ── Event Binding ──────────────────────────────────────────

    _bindEvents() {
        const { searchInput, sortTrigger, sortMenu, categoryTags,
                btnInstall, btnUninstall, btnBatchEnable, btnBatchDisable,
                btnSelectAll, btnRefresh, modList, dropZone, btnBatchToggle } = this._dom;

        if (btnInstall) {
            btnInstall.addEventListener('click', () => this._triggerInstall());
        } else {
            console.warn('[STS2Mods] btnInstall not found in DOM');
        }
        if (btnBatchToggle) {
            btnBatchToggle.addEventListener('click', () => this.toggleBatchMode());
        } else {
            console.warn('[STS2Mods] btnBatchToggle not found in DOM');
        }

        // Search
        if (searchInput) {
            searchInput.addEventListener('input', (e) => {
                this._searchQuery = e.target.value.trim();
                this._debouncedSearch(this._searchQuery);
            });
        }

        // Sort dropdown
        if (sortTrigger) {
            sortTrigger.addEventListener('click', (e) => {
                e.stopPropagation();
                const dd = sortTrigger.closest('.dropdown');
                dd.classList.toggle('open');
            });
        }
        if (sortMenu) {
            sortMenu.addEventListener('click', (e) => {
                const item = e.target.closest('.dropdown-item');
                if (!item) return;
                const sortBy = item.dataset.sort;
                if (sortBy) {
                    this.sortMods(sortBy);
                    // Update active state
                    sortMenu.querySelectorAll('.dropdown-item').forEach(d => d.classList.remove('active'));
                    item.classList.add('active');
                    // Update trigger label
                    if (sortTrigger) {
                        const label = item.textContent.trim().replace(/\s*▾\s*/, '');
                        sortTrigger.querySelector('[data-i18n]') ?
                            (sortTrigger.querySelector('[data-i18n]').textContent = label) :
                            (sortTrigger.innerHTML = label + ' ▾');
                    }
                    const dd = sortTrigger.closest('.dropdown');
                    dd.classList.remove('open');
                }
            });
        }

        // Close dropdown on outside click
        document.addEventListener('click', () => {
            document.querySelectorAll('.dropdown.open').forEach(dd => dd.classList.remove('open'));
        });

        // Category tags
        if (categoryTags) {
            categoryTags.addEventListener('click', (e) => {
                const tag = e.target.closest('.tag');
                if (!tag) return;
                const cat = tag.dataset.category;
                if (cat) {
                    this.filterCategory(cat);
                    categoryTags.querySelectorAll('.tag').forEach(t => t.classList.remove('active'));
                    tag.classList.add('active');
                }
            });
        }

        // Action buttons
        if (btnUninstall) {
            btnUninstall.addEventListener('click', () => {
                if (this.selected_mod_id) {
                    this.uninstallMod(this.selected_mod_id);
                }
            });
        }
        if (btnBatchEnable) {
            btnBatchEnable.addEventListener('click', () => this.batchEnable());
        }
        if (btnBatchDisable) {
            btnBatchDisable.addEventListener('click', () => this.batchDisable());
        }
        if (btnSelectAll) {
            btnSelectAll.addEventListener('click', () => this.selectAll());
        }

        // File drag-drop on mod list container (ZIP files only — internal reorder uses mouse events)
        if (modList) {
            modList.addEventListener('dragover', (e) => {
                // Only handle external file drags
                if (!this._dragSourceModId && !this._dragSourceBoxId && e.dataTransfer.types.includes('Files')) {
                    e.preventDefault();
                    e.dataTransfer.dropEffect = 'copy';
                    modList.classList.add('drop-active');
                }
            });
            modList.addEventListener('dragleave', (e) => {
                if (!modList.contains(e.relatedTarget)) {
                    modList.classList.remove('drop-active');
                }
            });
            modList.addEventListener('drop', (e) => {
                e.preventDefault();
                modList.classList.remove('drop-active');
                if (!this._dragSourceModId && !this._dragSourceBoxId) {
                    this._handleFileDrop(e);
                }
            });
        }

        // Drag-drop on drop zone
        if (dropZone) {
            dropZone.addEventListener('dragover', (e) => {
                e.preventDefault();
                dropZone.classList.add('drag-over');
            });
            dropZone.addEventListener('dragleave', () => {
                dropZone.classList.remove('drag-over');
            });
            dropZone.addEventListener('drop', (e) => {
                e.preventDefault();
                dropZone.classList.remove('drag-over');
                this._handleFileDrop(e);
            });
        }

        // Refresh button
        if (btnRefresh) {
            btnRefresh.addEventListener('click', () => {
                btnRefresh.classList.add('spinning');
                this.loadMods().then(() => {
                    setTimeout(() => btnRefresh.classList.remove('spinning'), 600);
                });
            });
        }

        // Keyboard shortcuts
        document.addEventListener('keydown', (e) => {
            // Only handle Ctrl+A in the mods page when not in a text input
            if ((e.ctrlKey || e.metaKey) && e.key === 'a') {
                const activePage = document.querySelector('.page.active');
                const tag = document.activeElement.tagName;
                const isTextInput = tag === 'INPUT' || tag === 'TEXTAREA' || document.activeElement.isContentEditable;
                if (activePage && activePage.id === 'page-mods' && !isTextInput) {
                    e.preventDefault();
                    if (!this.batch_mode) { this._enterBatchMode(); }
                    this.displayed_mods.forEach(m => { this.batch_selected[m.id] = true; });
                    this.renderModList();
                }
            }
            // Escape: exit batch mode
            if (e.key === 'Escape' && this.batch_mode) {
                this._exitBatchMode();
                this.renderModList();
            }
        });
    },

    // ── File Input ─────────────────────────────────────────────

    _initFileInput() {
        this._fileInput = document.createElement('input');
        this._fileInput.type = 'file';
        this._fileInput.accept = '.zip';
        this._fileInput.multiple = true;
        this._fileInput.style.display = 'none';
        document.body.appendChild(this._fileInput);

        this._fileInput.addEventListener('change', (e) => {
            const files = Array.from(e.target.files);
            files.forEach(f => this.installMod(f));
            this._fileInput.value = '';
        });
    },

    _triggerInstall() {
        console.log('[STS2Mods] Install triggered');
        if (this._fileInput) {
            this._fileInput.click();
        } else {
            console.warn('[STS2Mods] _fileInput not initialized');
        }
    },

    _handleFileDrop(e) {
        const files = Array.from(e.dataTransfer.files).filter(f => f.name.endsWith('.zip'));
        if (files.length === 0) {
            if (this._app && this._app.notifications) {
                this._app.notifications.show(
                    this._t('only_zip_supported') || '仅支持 .zip 文件',
                    'warning', 3000
                );
            }
            return;
        }
        files.forEach(f => this.installMod(f));
    },

    // ── Translation helper ─────────────────────────────────────

    _t(key) {
        if (this._app && this._app.i18n) return this._app.i18n.translate(key);
        return key;
    },

    _t_fmt(key, args) {
        if (this._app && this._app.i18n) return this._app.i18n.translate_fmt(key, args);
        // Fallback: replace %s placeholders
        let text = this._t(key);
        if (Array.isArray(args)) {
            args.forEach(a => { text = text.replace('%s', a); });
        }
        return text;
    },

    // ── Data Loading ───────────────────────────────────────────

    async loadMods() {
        // Try loading from backend API first
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.getMods();
                // API 返回格式: {current_tag, enabled, mods, tag_data} 或 {data: {mods, ...}}
                const modsData = resp?.data?.mods || resp?.mods;
                const enabledData = resp?.data?.enabled || resp?.enabled;
                const tagData = resp?.data?.tag_data || resp?.tag_data;
                const currentTag = resp?.data?.current_tag || resp?.current_tag;

                if (modsData) {
                    this.mods = modsData;
                    this.enabled_mods = {};
                    (enabledData || []).forEach(id => { this.enabled_mods[id] = true; });

                    // 从后端加载 tag_data 和 current_tag（优先级高于本地缓存）
                    if (tagData) {
                        this.tag_data = tagData;
                        // 【关键修复】确保默认标签存在，防止后端数据缺少默认标签
                        const defaultTags = ['单人模组', '联机模组'];
                        for (const tag of defaultTags) {
                            if (!this.tag_data.hasOwnProperty(tag)) {
                                this.tag_data[tag] = [];
                            }
                        }
                        this._app.store.set('mod_tags', this.tag_data);
                        console.log('[STS2Mods] Loaded tag_data from API:', this.tag_data);
                    }
                    if (currentTag) {
                        const oldTag = this.current_tag;
                        this.current_tag = currentTag;
                        // 确保 current_tag 有效
                        if (!this.tag_data.hasOwnProperty(this.current_tag)) {
                            this.current_tag = this._defaultTags[0];
                        }
                        this._app.store.set('current_tag', this.current_tag);
                        console.log('[STS2Mods] Loaded current_tag from API:', this.current_tag);

                        // 【核心修复】如果加载到的标签与之前不同，或者是首次加载，
                        // 确保 enabled_mods 状态与该标签的预设完全一致。
                        // 这里我们直接同步 enabled_mods 为该标签定义的列表。
                        const tagEnabled = this.tag_data[this.current_tag] || [];
                        this.enabled_mods = {};
                        tagEnabled.forEach(id => { this.enabled_mods[id] = true; });
                    }

                    this.applyFiltersAndSort();
                    this.renderModList();
                    this.renderTagPresets();
                    this.updateStatusBar();

                    // Also load active_bundle from API if not already set
                    if (!this._app.store.get('active_bundle', null)) {
                        try {
                            const bundlesResp = await this._app.api.getBundles();
                            if (bundlesResp && bundlesResp.data && bundlesResp.data.active_bundle) {
                                this._app.store.set('active_bundle', bundlesResp.data.active_bundle);
                                console.log('[STS2Mods] Loaded active_bundle:', bundlesResp.active_bundle);
                            }
                        } catch (e) {
                            console.warn('[STS2Mods] Failed to load active_bundle:', e);
                        }
                    }
                    return;
                }
            } catch (e) {
                console.warn('[STS2Mods] API loadMods failed, falling back to local:', e);
            }
        }

        // Fallback: load from store, then mock data
        let stored = null;
        if (this._app && this._app.store) {
            stored = this._app.store.get('mods_data');
        }

        if (stored && stored.length > 0) {
            this.mods = stored;
        } else if (window.MOCK_MODS && window.MOCK_MODS.length > 0) {
            this.mods = STS2Utils.deepClone(window.MOCK_MODS);
            // Persist mock data
            if (this._app && this._app.store) {
                this._app.store.set('mods_data', this.mods);
            }
        } else {
            this.mods = [];
        }

        // Load enabled mods
        if (this._app && this._app.store) {
            const enabledArr = this._app.store.get('enabled_mods', []);
            this.enabled_mods = {};
            enabledArr.forEach(id => { this.enabled_mods[id] = true; });
        }

        this.applyFiltersAndSort();
        this.renderModList();
        this.renderTagPresets();
        this.updateStatusBar();
    },

    saveMods() {
        if (this._app && this._app.store) {
            this._app.store.set('mods_data', this.mods);
            const enabledArr = Object.keys(this.enabled_mods).filter(id => this.enabled_mods[id]);
            this._app.store.set('enabled_mods', enabledArr);
        }
    },

    // ── Filter & Sort ──────────────────────────────────────────

    applyFiltersAndSort() {
        let filtered = this.mods.slice();

        // Category filter
        if (this._currentCategory === 'gameplay') {
            filtered = filtered.filter(m => m.affects_gameplay === true);
        } else if (this._currentCategory === 'cosmetic') {
            filtered = filtered.filter(m => m.affects_gameplay === false);
        }

        // Search filter
        if (this._searchQuery) {
            const q = this._searchQuery.toLowerCase();
            filtered = filtered.filter(m =>
                m.name.toLowerCase().includes(q) ||
                (m.author && m.author.toLowerCase().includes(q)) ||
                (m.description && m.description.toLowerCase().includes(q))
            );
        }

        // Sort
        const savedOrder = this._app && this._app.store ? this._app.store.get('mod_order', null) : null;

        if (this._currentSort === 'custom' && savedOrder && savedOrder.length > 0) {
            // Custom drag-reorder: use saved order
            const orderMap = {};
            savedOrder.forEach((id, i) => { orderMap[id] = i; });
            filtered.sort((a, b) => {
                const ai = orderMap[a.id] ?? 9999;
                const bi = orderMap[b.id] ?? 9999;
                return ai - bi;
            });
        } else {
            filtered.sort((a, b) => {
                switch (this._currentSort) {
                    case 'name':
                        return a.name.localeCompare(b.name, 'zh-CN');
                    case 'install_time': {
                        const ta = this._parseTimestamp(a.installed_time);
                        const tb = this._parseTimestamp(b.installed_time);
                        return (tb ? tb.getTime() : 0) - (ta ? ta.getTime() : 0);
                    }
                    case 'version':
                        return (b.version || '').localeCompare(a.version || '');
                    case 'author':
                        return (a.author || '').localeCompare(b.author || '', 'zh-CN');
                    default:
                        return 0;
                }
            });
        }

        this.displayed_mods = filtered;
    },

    // ── Rendering ──────────────────────────────────────────────

    renderModList() {
        const container = this._dom.modList;
        if (!container) { console.warn('[STS2Mods] modList container not found'); return; }

        container.innerHTML = '';

        const unified = this._buildUnifiedItems();

        if (unified.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'mod-empty-state';
            empty.innerHTML = `
                <div class="empty-icon">📦</div>
                <div class="empty-title">${STS2Utils.escapeHtml(this._t('no_mods_found') || '没有找到模组')}</div>
                <div class="empty-desc">${STS2Utils.escapeHtml(this._t('try_different_search') || '请尝试不同的搜索条件或安装新的模组')}</div>
            `;
            container.appendChild(empty);
            return;
        }

        const staggerDelay = 30;
        unified.forEach((entry, index) => {
            if (entry.type === 'box') {
                const boxEl = this._renderBoxInList(entry.data);
                boxEl.style.animationDelay = `${index * staggerDelay}ms`;
                boxEl.classList.add('stagger-enter');
                container.appendChild(boxEl);
            } else {
                const mod = entry.data;
                const enabled = !!this.enabled_mods[mod.id];
                const item = this.renderModItem(mod, enabled);
                item.style.animationDelay = `${index * staggerDelay}ms`;
                item.classList.add('stagger-enter');
                container.appendChild(item);
            }
        });
    },

    renderModItem(mod, enabled) {
        const item = document.createElement('div');
        item.className = 'mod-item';
        item.dataset.modId = mod.id;
        // Drag is handled by mouse events (not HTML5 drag API)

        // Batch selector (shown when batch_mode is active)
        const selector = document.createElement('div');
        selector.className = 'batch-selector';
        if (this.batch_mode && this.batch_selected[mod.id]) {
            selector.classList.add('checked');
        }
        selector.addEventListener('click', (e) => {
            e.stopPropagation();
            if (!this.batch_mode) {
                this.batch_mode = true;
                this._updateBatchModeUI(true);
            }
            this._toggleBatchSelect(mod.id, item);
        });
        item.appendChild(selector);

        // Drag handle (hidden inside box content via CSS)
        const dragHandle = document.createElement('span');
        dragHandle.className = 'mod-item-drag-handle';
        dragHandle.innerHTML = '<svg width="8" height="12" viewBox="0 0 8 12"><circle cx="2" cy="2" r="1.1"/><circle cx="6" cy="2" r="1.1"/><circle cx="2" cy="6" r="1.1"/><circle cx="6" cy="6" r="1.1"/><circle cx="2" cy="10" r="1.1"/><circle cx="6" cy="10" r="1.1"/></svg>';
        item.appendChild(dragHandle);

        if (this.selected_mod_id === mod.id) {
            item.classList.add('selected');
        }
        if (this.batch_mode && this.batch_selected[mod.id]) {
            item.classList.add('batch-selected');
        }

        // Icon class based on category
        let iconClass = 'icon-default';
        if (mod.affects_gameplay === true) iconClass = 'icon-gameplay';
        else if (mod.affects_gameplay === false) iconClass = 'icon-cosmetic';

        // Check missing dependencies
        const hasMissingDeps = this._hasMissingDeps(mod);
        if (hasMissingDeps) item.classList.add('missing-dep');

        // Icon
        const iconDiv = document.createElement('div');
        iconDiv.className = `mod-item-icon ${iconClass}`;
        iconDiv.textContent = mod.icon || '📦';
        item.appendChild(iconDiv);

        // Info
        const infoDiv = document.createElement('div');
        infoDiv.className = 'mod-item-info';

        const nameSpan = document.createElement('div');
        nameSpan.className = 'mod-item-name';
        nameSpan.textContent = mod.name;
        infoDiv.appendChild(nameSpan);

        const metaSpan = document.createElement('div');
        metaSpan.className = 'mod-item-meta';
        metaSpan.innerHTML = `<span class="author">${STS2Utils.escapeHtml(mod.author || '')}</span><span class="version">${STS2Utils.escapeHtml(mod.version || '')}</span>`;
        infoDiv.appendChild(metaSpan);

        item.appendChild(infoDiv);

        // Dependency warning
        if (hasMissingDeps) {
            const warn = document.createElement('span');
            warn.className = 'mod-item-dep-warn';
            warn.textContent = '⚠';
            warn.title = this._t('missing_dependency') || '缺少依赖';
            item.appendChild(warn);
        }

        // Toggle
        const toggleLabel = document.createElement('label');
        toggleLabel.className = 'mod-item-toggle';
        toggleLabel.addEventListener('click', (e) => e.stopPropagation());

        const toggleInput = document.createElement('input');
        toggleInput.type = 'checkbox';
        toggleInput.checked = enabled;
        toggleInput.addEventListener('change', () => {
            this.toggleMod(mod.id);
        });
        toggleLabel.appendChild(toggleInput);

        const track = document.createElement('span');
        track.className = 'toggle-track';
        toggleLabel.appendChild(track);

        const knob = document.createElement('span');
        knob.className = 'toggle-knob';
        toggleLabel.appendChild(knob);

        item.appendChild(toggleLabel);

        // Click handler for selection / details / batch
        item.addEventListener('click', (e) => {
            this._onModItemClick(e, mod, item);
        });

        // Drag initiation via mouse events
        item.addEventListener('mousedown', (e) => {
            // Don't interfere with toggle, buttons, or right-click
            if (e.target.closest('.mod-item-toggle') || e.target.closest('button') || e.button !== 0) return;
            this._startDrag(e, mod.id, null, item);
        });

        return item;
    },

    // ── Tag Presets ────────────────────────────────────────────

    renderTagPresets() {
        const container = this._dom.tagPresets;
        if (!container) return;

        container.innerHTML = '';

        // Get all tag names
        const allTags = this._getAllTagNames();

        allTags.forEach(tagName => {
            const btn = document.createElement('button');
            btn.className = 'tag-preset';
            if (this.current_tag === tagName) btn.classList.add('active');
            btn.textContent = tagName;
            btn.dataset.tag = tagName;

            // Check if custom (non-default)
            const isCustom = !this._defaultTags.includes(tagName);

            // Click to switch
            btn.addEventListener('click', (e) => {
                if (btn.classList.contains('deleting')) return;
                this.switchTag(tagName);
                container.querySelectorAll('.tag-preset').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
            });

            // Long press to delete custom tags
            if (isCustom) {
                this._setupLongPress(btn, tagName);
            }

            container.appendChild(btn);
            this.tag_buttons[tagName] = btn;
        });

        // Add button
        const addBtn = document.createElement('button');
        addBtn.className = 'tag-add-btn';
        addBtn.textContent = '+';
        addBtn.title = this._t('add_tag') || '添加标签';
        addBtn.addEventListener('click', () => this.addTag());
        container.appendChild(addBtn);

        // Separator
        const sep = document.createElement('span');
        sep.className = 'tag-separator';
        sep.textContent = '|';
        container.appendChild(sep);

        // New box button
        const boxBtn = document.createElement('button');
        boxBtn.className = 'tag-preset tag-box-btn';
        boxBtn.textContent = '📦 ' + (this._t('new_mod_box') || '新盒子');
        boxBtn.title = this._t('new_mod_box_tip') || '新建收纳盒子';
        boxBtn.addEventListener('click', () => this.createBox());
        container.appendChild(boxBtn);

        // Mouse wheel horizontal scroll for tag cycling
        if (!this._tagWheelBound) {
            container.addEventListener('wheel', (e) => {
                if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
                    e.preventDefault();
                    container.scrollLeft += e.deltaY;
                }
            }, { passive: false });
            this._tagWheelBound = true;
        }
    },

    _setupLongPress(btn, tagName) {
        let timer = null;

        const startPress = (e) => {
            e.preventDefault();
            timer = setTimeout(() => {
                this.deleteTag(tagName);
            }, 1000);
            btn.classList.add('deleting');
            this._longPressTimer = timer;
            this._longPressTarget = btn;
        };

        const cancelPress = () => {
            if (timer) {
                clearTimeout(timer);
                timer = null;
            }
            btn.classList.remove('deleting');
            this._longPressTimer = null;
            this._longPressTarget = null;
        };

        btn.addEventListener('mousedown', startPress);
        btn.addEventListener('mouseup', cancelPress);
        btn.addEventListener('mouseleave', cancelPress);
        btn.addEventListener('touchstart', startPress, { passive: false });
        btn.addEventListener('touchend', cancelPress);
        btn.addEventListener('touchcancel', cancelPress);
    },

    _cancelLongPress() {
        if (this._longPressTimer) {
            clearTimeout(this._longPressTimer);
            this._longPressTimer = null;
        }
        if (this._longPressTarget) {
            this._longPressTarget.classList.remove('deleting');
            this._longPressTarget = null;
        }
    },

    _getAllTagNames() {
        const names = new Set(this._defaultTags);
        Object.keys(this.tag_data).forEach(k => names.add(k));
        if (this.current_tag) names.add(this.current_tag);
        return Array.from(names);
    },

    async switchTag(tagName) {
        console.log('[STS2Mods] switchTag called with:', tagName);
        console.log('[STS2Mods] active_bundle:', this._app.store.get('active_bundle', null));

        const activeBundle = this._app.store.get('active_bundle', null);

        // 如果有活跃的整合包，禁止切换标签（与 Godot 原生 UI 保持一致）
        if (activeBundle) {
            console.log('[STS2Mods] Bundle is active, tag switch locked');
            this._app.notifications.show(this._t_fmt('bundle_active_tag_locked') || '整合包激活时无法切换标签', 'warning');
            return;
        }

        // 【关键修复】确保 current_tag 有效，防止 null 值覆盖正确预设
        if (!this.current_tag || !this.tag_data.hasOwnProperty(this.current_tag)) {
            this.current_tag = this._defaultTags[0];
        }

        // 保存当前标签的启用模组到 tag_data（与原版 Godot 保持一致）
        const savedTag = this.current_tag;
        const currentEnabledMods = Object.keys(this.enabled_mods).filter(id => this.enabled_mods[id]);
        this.tag_data[savedTag] = currentEnabledMods;
        console.log('[STS2Mods] Saved current tag mods:', savedTag, currentEnabledMods);

        // 保存到后端（持久化）
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                await this._app.api.saveTagData(this.tag_data, tagName);  // 传新标签，让后端更新 current_tag
                console.log('[STS2Mods] Tag data saved to backend');
            } catch (e) {
                console.warn('[STS2Mods] Failed to save tag data:', e);
            }
        }

        this.current_tag = tagName;

        // 【关键修复】切换标签后重新渲染标签按钮，确保高亮状态正确更新
        this.renderTagPresets();

        // 获取新标签需要启用的模组列表
        const tagEnabled = this.tag_data[tagName] || [];
        console.log('[STS2Mods] Tag enabled mods:', tagEnabled);

        // 计算需要禁用和启用的模组
        const currentEnabled = Object.keys(this.enabled_mods).filter(id => this.enabled_mods[id]);
        const toDisable = currentEnabled.filter(id => !tagEnabled.includes(id));
        const toEnable = tagEnabled.filter(id => !currentEnabled.includes(id));

        console.log('[STS2Mods] To disable:', toDisable);
        console.log('[STS2Mods] To enable:', toEnable);

        // 调用后端 API 执行实际的启用/禁用操作
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                this._app.notifications.show(this._t_fmt('applying_preset', [tagName]), 'info');

                // 禁用不需要的模组
                for (const modId of toDisable) {
                    try {
                        await this._app.api.disableMod(modId);
                        console.log('[STS2Mods] Disabled mod:', modId);
                    } catch (e) {
                        console.warn('[STS2Mods] Failed to disable mod:', modId, e);
                    }
                }

                // 启用需要的模组
                for (const modId of toEnable) {
                    try {
                        await this._app.api.enableMod(modId);
                        console.log('[STS2Mods] Enabled mod:', modId);
                    } catch (e) {
                        console.warn('[STS2Mods] Failed to enable mod:', modId, e);
                    }
                }

                this._app.notifications.show(this._t_fmt('preset_applied', [tagName]), 'success');
            } catch (e) {
                console.warn('[STS2Mods] Failed to apply tag preset:', e);
                this._app.notifications.show(this._t_fmt('preset_apply_failed', [e.message]), 'error');
            }
        }

        // 更新本地 enabled_mods 状态
        this.enabled_mods = {};
        tagEnabled.forEach(id => { this.enabled_mods[id] = true; });

        this.saveMods();
        this.applyFiltersAndSort();
        this.renderModList();
        this.updateStatusBar();

        if (this.selected_mod_id) {
            this.showModDetails(this.selected_mod_id);
        }
    },

    addTag() {
        const name = prompt(this._t('enter_tag_name') || '请输入标签名称:', '');
        if (!name || !name.trim()) return;
        const trimmed = name.trim();

        if (this._getAllTagNames().includes(trimmed)) {
            if (this._app && this._app.notifications) {
                this._app.notifications.show(
                    this._t('tag_already_exists') || '标签已存在',
                    'warning', 2000
                );
            }
            return;
        }

        // Initialize tag with current enabled mods
        this.tag_data[trimmed] = Object.keys(this.enabled_mods).filter(id => this.enabled_mods[id]);
        this._saveTagData();
        this.current_tag = trimmed;
        this.renderTagPresets();
    },

    deleteTag(tagName) {
        if (this._defaultTags.includes(tagName)) return;

        delete this.tag_data[tagName];
        this._saveTagData();

        // If deleted tag was active, switch to first default
        if (this.current_tag === tagName) {
            this.current_tag = this._defaultTags[0];
            const tagEnabled = this.tag_data[this.current_tag] || [];
            this.enabled_mods = {};
            tagEnabled.forEach(id => { this.enabled_mods[id] = true; });
            this.saveMods();
        }

        this.renderTagPresets();
        this.renderModList();

        if (this._app && this._app.notifications) {
            this._app.notifications.show(
                (this._t('tag_deleted') || '标签已删除') + ': ' + tagName,
                'info', 2000
            );
        }
    },

    _loadTagData() {
        if (this._app && this._app.store) {
            this.tag_data = this._app.store.get('mod_tags', {});
            this.current_tag = this._app.store.get('current_tag', this._defaultTags[0]);
        } else {
            this.tag_data = {};
            this.current_tag = this._defaultTags[0];
        }
        // 【关键修复】确保默认标签存在，防止 current_tag 为 null 时覆盖正确预设
        const defaultTags = ['单人模组', '联机模组'];
        for (const tag of defaultTags) {
            if (!this.tag_data.hasOwnProperty(tag)) {
                this.tag_data[tag] = [];
            }
        }
        // 确保 current_tag 不为 null 且有效
        if (!this.current_tag || !this.tag_data.hasOwnProperty(this.current_tag)) {
            this.current_tag = this._defaultTags[0];
        }
    },

    _saveTagData() {
        if (this._app && this._app.store) {
            this._app.store.set('mod_tags', this.tag_data);
            this._app.store.set('current_tag', this.current_tag);
        }
    },

    /**
     * 【关键】同步保存当前标签的启用模组到 tag_data（用于页面关闭前）
     */
    _saveCurrentTagModsSync() {
        if (this.current_tag && this.tag_data) {
            const currentEnabledMods = Object.keys(this.enabled_mods).filter(id => this.enabled_mods[id]);
            this.tag_data[this.current_tag] = currentEnabledMods;
            this._saveTagData();
            console.log('[STS2Mods] Saved current tag mods before unload:', this.current_tag, currentEnabledMods);
        }
    },

    // ── Boxes (Collapsible Groups) ─────────────────────────────

    /** Build unified items array: interleaved boxes + unboxed mods respecting saved item_order. */
    _buildUnifiedItems() {
        const inBox = this._getModIdsInBoxes();
        const allBoxes = this.mod_boxes;
        const unboxed = this.displayed_mods.filter(m => !inBox.has(m.id));

        if (!this.item_order || this.item_order.length === 0) {
            const items = [];
            allBoxes.forEach(box => items.push({ type: 'box', id: box.id, data: box }));
            unboxed.forEach(mod => items.push({ type: 'mod', id: mod.id, data: mod }));
            return items;
        }

        const boxMap = {};
        allBoxes.forEach(b => { boxMap[b.id] = b; });
        const modMap = {};
        unboxed.forEach(m => { modMap[m.id] = m; });

        const items = [];
        const placed = new Set();
        this.item_order.forEach(id => {
            if (boxMap[id] && !placed.has(id)) {
                items.push({ type: 'box', id, data: boxMap[id] });
                placed.add(id);
            } else if (modMap[id] && !placed.has(id)) {
                items.push({ type: 'mod', id, data: modMap[id] });
                placed.add(id);
            }
        });
        allBoxes.forEach(box => {
            if (!placed.has(box.id)) items.push({ type: 'box', id: box.id, data: box });
        });
        unboxed.forEach(mod => {
            if (!placed.has(mod.id)) items.push({ type: 'mod', id: mod.id, data: mod });
        });
        return items;
    },

    /** Set of mod IDs that belong to any box. */
    _getModIdsInBoxes() {
        const ids = new Set();
        this.mod_boxes.forEach(box => {
            (box.mod_ids || []).forEach(id => ids.add(id));
        });
        return ids;
    },

    /** Unboxed mods from the displayed list. */
    _getUnboxedMods() {
        const inBox = this._getModIdsInBoxes();
        return this.displayed_mods.filter(m => !inBox.has(m.id));
    },

    /** Persist the unified item_order array. */
    _saveItemOrder() {
        if (this._app && this._app.store) {
            this._app.store.set('item_order', this.item_order);
        }
        // 同步到后端（持久化）
        this._syncModOrganization();
    },

    /** Load saved item_order. */
    _loadItemOrder() {
        if (this._app && this._app.store) {
            this.item_order = this._app.store.get('item_order', []);
        } else {
            this.item_order = [];
        }
    },

    /**
     * Render a box inline in the mod list (unified drag-and-drop layout).
     * Redesigned with SVG chevron, drag handle, smooth animations.
     */
    _renderBoxInList(box) {
        const boxEl = document.createElement('div');
        boxEl.className = 'mod-box' + (box.collapsed ? ' collapsed' : '');
        boxEl.dataset.boxId = box.id;
        boxEl.dataset.color = box.color || 'blue';

        // ── Header ──
        const header = document.createElement('div');
        header.className = 'mod-box-header';

        // Drag grip (6-dot SVG) — mouse-event drag for box reorder
        const handle = document.createElement('span');
        handle.className = 'mod-box-drag-handle';
        handle.innerHTML = '<svg width="10" height="14" viewBox="0 0 10 14"><circle cx="2" cy="2" r="1.2"/><circle cx="8" cy="2" r="1.2"/><circle cx="2" cy="7" r="1.2"/><circle cx="8" cy="7" r="1.2"/><circle cx="2" cy="12" r="1.2"/><circle cx="8" cy="12" r="1.2"/></svg>';
        header.appendChild(handle);

        // Color dot (cycles colors on click)
        const dot = document.createElement('span');
        dot.className = 'mod-box-color-dot';
        dot.style.backgroundColor = this._getBoxColorHex(box.color);
        dot.addEventListener('click', (e) => {
            e.stopPropagation();
            this._cycleBoxColor(box.id);
        });
        header.appendChild(dot);

        // Name (double-click to rename)
        const nameEl = document.createElement('span');
        nameEl.className = 'mod-box-name';
        nameEl.textContent = box.name;
        nameEl.addEventListener('dblclick', (e) => {
            e.stopPropagation();
            this._startRenameBox(box.id, nameEl);
        });
        header.appendChild(nameEl);

        // Mod count
        const countEl = document.createElement('span');
        countEl.className = 'mod-box-count';
        countEl.textContent = `${(box.mod_ids || []).length}`;
        header.appendChild(countEl);

        // Collapse chevron (SVG)
        const collapseIcon = document.createElement('span');
        collapseIcon.className = 'mod-box-collapse-icon';
        collapseIcon.innerHTML = '<svg width="14" height="14" viewBox="0 0 14 14"><path d="M5.5 3L10 7L5.5 11" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg>';
        header.appendChild(collapseIcon);

        // Delete button
        const actions = document.createElement('div');
        actions.className = 'mod-box-actions';
        const deleteBtn = document.createElement('button');
        deleteBtn.className = 'box-action-btn delete-btn';
        deleteBtn.innerHTML = '<svg width="12" height="12" viewBox="0 0 12 12"><path d="M3 3L9 9M9 3L3 9" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>';
        deleteBtn.title = this._t('delete') || '删除';
        deleteBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            this.deleteBox(box.id);
        });
        actions.appendChild(deleteBtn);
        header.appendChild(actions);

        // Toggle collapse on header click
        header.addEventListener('click', () => this.toggleBoxCollapse(box.id));
        boxEl.appendChild(header);

        // ── Content (wrapped for grid-based collapse animation) ──
        const wrapper = document.createElement('div');
        wrapper.className = 'mod-box-content-wrapper';
        const content = document.createElement('div');
        content.className = 'mod-box-content';

        (box.mod_ids || []).forEach(modId => {
            const mod = this.mods.find(m => m.id === modId);
            if (mod) {
                const enabled = !!this.enabled_mods[mod.id];
                const item = this.renderModItem(mod, enabled);
                // Add drag handle at the start so users can drag mods out of boxes
                const handle = document.createElement('span');
                handle.className = 'mod-item-drag-handle';
                handle.innerHTML = '<svg width="8" height="12" viewBox="0 0 8 12"><circle cx="2" cy="2" r="1.1"/><circle cx="6" cy="2" r="1.1"/><circle cx="2" cy="6" r="1.1"/><circle cx="6" cy="6" r="1.1"/><circle cx="2" cy="10" r="1.1"/><circle cx="6" cy="10" r="1.1"/></svg>';
                item.insertBefore(handle, item.firstChild);
                content.appendChild(item);
            }
        });

        wrapper.appendChild(content);
        boxEl.appendChild(wrapper);

        // ── Box drag via mouse events (handle initiates box reorder) ──
        handle.addEventListener('mousedown', (e) => {
            if (e.button !== 0) return;
            e.stopPropagation();
            this._startDrag(e, null, box.id, boxEl);
        });

        // ── Drag hover tracking (mouse-event based) ──
        boxEl.addEventListener('mouseenter', (e) => {
            if (this._dragSourceModId) {
                this._dragHoverBoxId = box.id;
                this._dragInBoxContent = false;
                boxEl.classList.add('drop-target');
            }
        });
        boxEl.addEventListener('mouseleave', (e) => {
            if (this._dragSourceModId) {
                this._dragHoverBoxId = null;
                this._dragInBoxContent = false;
                boxEl.classList.remove('drop-target');
            }
        });

        // Intercept false mouseleave events caused by pointer-events:none on
        // the dragging element.  mouseleave doesn't bubble, but capture-phase
        // listeners still fire for it — use that to swallow the event before
        // the bubble-phase handlers above see it.
        boxEl.addEventListener('mouseleave', (e) => {
            if (this._dragSourceModId && e.target.classList.contains('dragging')) {
                e.stopPropagation();
            }
        }, true);  // capture phase

        // Track cursor entering the content area specifically
        content.addEventListener('mouseenter', (e) => {
            if (this._dragSourceModId && this._dragHoverBoxId === box.id) {
                this._dragInBoxContent = true;
            }
        });
        content.addEventListener('mouseleave', (e) => {
            if (this._dragSourceModId) {
                this._dragInBoxContent = false;
            }
        });
        // Same capture-phase interception for content
        content.addEventListener('mouseleave', (e) => {
            if (this._dragSourceModId && e.target.classList.contains('dragging')) {
                e.stopPropagation();
            }
        }, true);  // capture phase

        // Update drop indicator position inside the box when cursor is in content
        // Use capture phase so this runs before _moveDrag on the document
        content.addEventListener('mousemove', (e) => {
            if (!this._dragSourceModId || this._dragHoverBoxId !== box.id) return;
            this._dragInBoxContent = true;
            // Move ghost (since _moveDrag is also running, this is redundant but safe)
            if (this._dragGhost) {
                this._dragGhost.style.left = (e.clientX - 20) + 'px';
                this._dragGhost.style.top = (e.clientY - 16) + 'px';
            }
            this._updateBoxContentDropIndicator(box.id, e.clientY);
        }, true);

        return boxEl;
    },

    _getBoxColorHex(color) {
        const map = {
            blue: '#66c0f9',
            green: '#10b981',
            orange: '#f59e0b',
            red: '#ef4444',
            purple: '#a78bfa',
            yellow: '#facc15',
            gray: '#8b98a0',
            cyan: '#22d3ee'
        };
        return map[color] || map.blue;
    },

    _cycleBoxColor(boxId) {
        const box = this.mod_boxes.find(b => b.id === boxId);
        if (!box) return;
        const idx = this._boxColors.indexOf(box.color);
        box.color = this._boxColors[(idx + 1) % this._boxColors.length];
        this._saveBoxData();
        this.renderModList();
    },

    _startRenameBox(boxId, nameEl) {
        nameEl.contentEditable = 'true';
        nameEl.focus();

        // Select all text
        const range = document.createRange();
        range.selectNodeContents(nameEl);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);

        const finish = () => {
            nameEl.contentEditable = 'false';
            const newName = nameEl.textContent.trim();
            if (newName) {
                this.renameBox(boxId, newName);
            }
        };

        nameEl.addEventListener('blur', finish, { once: true });
        nameEl.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                nameEl.blur();
            }
            if (e.key === 'Escape') {
                nameEl.textContent = this.mod_boxes.find(b => b.id === boxId)?.name || '';
                nameEl.blur();
            }
        });
    },

    createBox() {
        const name = prompt(this._t('enter_box_name') || '请输入分组名称:', this._t('new_box') || '新分组');
        if (!name || !name.trim()) return;

        const box = {
            id: 'box_' + STS2Utils.generateId(),
            name: name.trim(),
            color: this._boxColors[this.mod_boxes.length % this._boxColors.length],
            mod_ids: [],
            collapsed: false
        };

        this.mod_boxes.push(box);
        // Add to item_order at the beginning (before unboxed mods)
        this.item_order.unshift(box.id);
        this._saveBoxData();
        this._saveItemOrder();
        this.renderModList();
    },

    deleteBox(id) {
        const box = this.mod_boxes.find(b => b.id === id);
        const boxModIds = box ? (box.mod_ids || []) : [];

        // Find the box's current position in the unified list
        const items = this._buildUnifiedItems();
        const boxIdx = items.findIndex(e => e.type === 'box' && e.id === id);

        // Remove the box from data
        this.mod_boxes = this.mod_boxes.filter(b => b.id !== id);

        // Splice box mods into item_order at the box's former position
        const order = this.item_order.filter(i => i !== id);
        const insertAt = boxIdx >= 0 ? boxIdx : order.length;
        order.splice(insertAt, 0, ...boxModIds);
        this.item_order = order;

        this._saveBoxData();
        this._saveItemOrder();
        this.renderModList();
    },

    renameBox(id, name) {
        const box = this.mod_boxes.find(b => b.id === id);
        if (box) {
            box.name = name;
            this._saveBoxData();
        }
    },

    toggleBoxCollapse(id) {
        const box = this.mod_boxes.find(b => b.id === id);
        if (box) {
            box.collapsed = !box.collapsed;
            this._saveBoxData();
            const el = document.querySelector(`.mod-box[data-box-id="${id}"]`);
            if (el) el.classList.toggle('collapsed', box.collapsed);
        }
    },

    _addModToBox(boxId, modId) {
        const box = this.mod_boxes.find(b => b.id === boxId);
        if (!box) return;

        // Remove from any other box first
        this.mod_boxes.forEach(b => {
            b.mod_ids = (b.mod_ids || []).filter(id => id !== modId);
        });

        // Also remove from item_order if it was a top-level item
        this.item_order = this.item_order.filter(id => id !== modId);

        // Add to target box
        if (!box.mod_ids.includes(modId)) {
            box.mod_ids.push(modId);
        }

        this._saveBoxData();
        this._saveItemOrder();
        this.renderModList();
    },

    _loadBoxData() {
        if (this._app && this._app.store) {
            this.mod_boxes = this._app.store.get('mod_boxes', []);
        } else {
            this.mod_boxes = [];
        }
    },

    _saveBoxData() {
        if (this._app && this._app.store) {
            this._app.store.set('mod_boxes', this.mod_boxes);
        }
        // 同步到后端（持久化）
        this._syncModOrganization();
    },

    _syncModOrganization() {
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            this._app.api.saveModOrganization(this.mod_boxes, this.item_order, false, false).catch(e => {
                console.warn('[STS2Mods] saveModOrganization failed:', e);
            });
        }
    },

    /** Load mod notes from backend API or localStorage. */
    async _loadModNotes() {
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.getModNotes();
                if (resp && resp.notes) {
                    this._modNotes = resp.notes;
                    return;
                }
            } catch (e) {
                console.warn('[STS2Mods] API getModNotes failed:', e);
            }
        }
        // Fallback to localStorage
        if (this._app && this._app.store) {
            this._modNotes = this._app.store.get('mod_notes', {});
        }
    },

    /** Load mod organization (boxes & item_order) from backend API or localStorage. */
    async _loadModOrganization() {
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.getModOrganization();
                if (resp && resp.data) {
                    if (resp.data.boxes && resp.data.boxes.length > 0) {
                        this.mod_boxes = resp.data.boxes;
                        this._app.store.set('mod_boxes', this.mod_boxes);
                    }
                    if (resp.data.item_order && resp.data.item_order.length > 0) {
                        this.item_order = resp.data.item_order;
                        this._app.store.set('item_order', this.item_order);
                    }
                    console.log('[STS2Mods] Loaded mod organization from API');
                    return;
                }
            } catch (e) {
                console.warn('[STS2Mods] API getModOrganization failed:', e);
            }
        }
        // Fallback to localStorage (already done in _loadBoxData and _loadItemOrder)
    },

    /** Save a single mod note. */
    async _saveModNote(modId, note) {
        this._modNotes[modId] = note;
        // Persist locally
        if (this._app && this._app.store) {
            this._app.store.set('mod_notes', this._modNotes);
        }
        // Persist to backend
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                await this._app.api.saveModNotes(modId, note);
            } catch (e) {
                console.warn('[STS2Mods] API saveModNotes failed:', e);
            }
        }
    },

    /** Show the mod note edit modal dialog. */
    _showNoteEditDialog(modId) {
        const currentNote = this._modNotes[modId] || '';
        const t = (key) => this._t(key) || key;

        // Create modal overlay
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        overlay.style.cssText = 'opacity:1;visibility:visible;';
        overlay.innerHTML = `
            <div class="modal note-modal" style="width:520px;max-width:90vw">
                <div class="modal__header">
                    <span class="modal__title">${t('mod_note_edit')}</span>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="modal__body" style="padding:var(--sp-lg) var(--sp-xl)">
                    <textarea class="note-textarea" maxlength="500" rows="8"
                        placeholder="${t('mod_note_placeholder')}">${STS2Utils.escapeHtml(currentNote)}</textarea>
                    <div class="note-char-count">${currentNote.length}/500</div>
                </div>
                <div class="modal__footer">
                    <button class="btn btn-ghost note-cancel">${this._t('cancel')}</button>
                    <button class="btn btn-primary note-confirm">${this._t('confirm') || '确定'}</button>
                </div>
            </div>
        `;

        document.body.appendChild(overlay);

        const textarea = overlay.querySelector('.note-textarea');
        const charCount = overlay.querySelector('.note-char-count');
        textarea.addEventListener('input', () => {
            charCount.textContent = textarea.value.length + '/500';
        });

        const close = () => overlay.remove();
        overlay.querySelector('.modal__close').addEventListener('click', close);
        overlay.querySelector('.note-cancel').addEventListener('click', close);
        overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });

        overlay.querySelector('.note-confirm').addEventListener('click', async () => {
            const note = textarea.value.trim().substr(0, 500);
            await this._saveModNote(modId, note);
            close();
            // Refresh the details panel
            if (this.selected_mod_id === modId) {
                this.showModDetails(modId);
            }
        });

        textarea.focus();
    },

    // ── Drag-to-Reorder (Mouse-Event Based) ────────────────────

    /** Create the drop indicator line and ghost elements. @private */
    _initDropIndicator() {
        const indicator = document.createElement('div');
        indicator.className = 'mod-drop-indicator';
        indicator.style.display = 'none';
        document.body.appendChild(indicator);
        this._dropIndicator = indicator;
    },

    /**
     * Start a drag operation. Called from mousedown on a mod item or box handle.
     * @param {MouseEvent} e
     * @param {string|null} modId - if dragging a mod
     * @param {string|null} boxId - if dragging a box
     * @param {HTMLElement} sourceEl - the element being dragged
     * @private
     */
    _startDrag(e, modId, boxId, sourceEl) {
        this._dragSourceModId = modId;
        this._dragSourceBoxId = boxId;
        this._dragMoved = false;
        this._dragStartX = e.clientX;
        this._dragStartY = e.clientY;

        // If the source element is inside a box content area, pre-set hover state
        // so that in-box reorder works immediately (mouseenter won't fire again)
        const parentBoxContent = sourceEl.closest('.mod-box-content');
        if (parentBoxContent) {
            const parentBox = parentBoxContent.closest('.mod-box');
            if (parentBox) {
                this._dragHoverBoxId = parentBox.dataset.boxId;
                this._dragInBoxContent = true;
            }
        }

        // Create ghost (follows cursor)
        const ghost = sourceEl.cloneNode(true);
        ghost.className = sourceEl.className + ' drag-ghost';
        ghost.style.cssText = `position:fixed;pointer-events:none;z-index:10000;
            width:${sourceEl.offsetWidth}px;opacity:0.85;
            box-shadow:0 8px 24px rgba(0,0,0,0.4);border-radius:6px;
            transition:none;`;
        document.body.appendChild(ghost);
        this._dragGhost = ghost;

        // Bind move/up on document
        this._onDragMove = (ev) => this._moveDrag(ev);
        this._onDragEnd = (ev) => this._endDrag(ev);
        document.addEventListener('mousemove', this._onDragMove);
        document.addEventListener('mouseup', this._onDragEnd);
    },

    /**
     * Move the ghost and update the drop indicator. @private
     */
    _moveDrag(e) {
        const dx = e.clientX - this._dragStartX;
        const dy = e.clientY - this._dragStartY;

        // Require 5px movement before starting drag
        if (!this._dragMoved && Math.abs(dx) + Math.abs(dy) < 5) return;

        if (!this._dragMoved) {
            this._dragMoved = true;
            // Add dragging class to the source element
            if (this._dragSourceModId) {
                const el = this._dom.modList?.querySelector(`.mod-item[data-mod-id="${this._dragSourceModId}"]`);
                if (el) el.classList.add('dragging');
            } else if (this._dragSourceBoxId) {
                const el = this._dom.modList?.querySelector(`.mod-box[data-box-id="${this._dragSourceBoxId}"]`);
                if (el) el.classList.add('dragging');
            }
        }

        // Move ghost
        if (this._dragGhost) {
            this._dragGhost.style.left = (e.clientX - 20) + 'px';
            this._dragGhost.style.top = (e.clientY - 16) + 'px';
        }

        // Update drop indicator — skip when cursor is inside a box content area
        // (the content's own mousemove handler positions the indicator instead)
        if (!this._dragInBoxContent) {
            this._updateDropIndicator(e.clientX, e.clientY);
        }

        // Prevent text selection
        e.preventDefault();
    },

    /**
     * End the drag — perform the reorder. @private
     */
    _endDrag(e) {
        // Clean up document listeners
        document.removeEventListener('mousemove', this._onDragMove);
        document.removeEventListener('mouseup', this._onDragEnd);

        // Remove ghost
        if (this._dragGhost) {
            this._dragGhost.remove();
            this._dragGhost = null;
        }

        // Remove dragging classes
        document.querySelectorAll('.mod-item.dragging, .mod-box.dragging').forEach(el => el.classList.remove('dragging'));
        document.querySelectorAll('.mod-box.drop-target').forEach(el => el.classList.remove('drop-target'));
        this._hideDropIndicator();

        // Only reorder if the user actually dragged
        if (!this._dragMoved) {
            this._dragSourceModId = null;
            this._dragSourceBoxId = null;
            this._dragHoverBoxId = null;
            this._dragInBoxContent = false;
            return;
        }

        const draggedId = this._dragSourceModId || this._dragSourceBoxId;
        const hit = this._hitTest(e.clientX, e.clientY, draggedId);
        const items = this._buildUnifiedItems();

        // Filter out the dragged item; hit.index is relative to this filtered list
        const filtered = items.filter(e => e.id !== draggedId);

        if (this._dragSourceModId) {
            // ── MOD drag ──
            const dropBoxId = this._dragHoverBoxId;

            if (dropBoxId && this._dragInBoxContent) {
                // ── Drop inside a box content area → insert at position ──
                const targetBox = this.mod_boxes.find(b => b.id === dropBoxId);
                if (targetBox) {
                    // Remove dragged mod from ALL boxes and from item_order
                    this.mod_boxes.forEach(b => {
                        b.mod_ids = (b.mod_ids || []).filter(id => id !== draggedId);
                    });
                    this.item_order = this.item_order.filter(id => id !== draggedId);

                    // insertIdx is relative to non-dragging items (= items after removal)
                    const insertIdx = this._calcBoxContentInsertIndex(dropBoxId, e.clientY, draggedId);
                    const adj = Math.min(insertIdx, (targetBox.mod_ids || []).length);
                    targetBox.mod_ids.splice(adj, 0, draggedId);

                    this._saveBoxData();
                    this._saveItemOrder();
                    this._dragSourceModId = null;
                    this._dragSourceBoxId = null;
                    this._dragHoverBoxId = null;
                    this._dragInBoxContent = false;
                    this.renderModList();
                    return;
                }
            }

            if (dropBoxId) {
                // ── Drop on box header → add mod to box ──
                this._dragSourceModId = null;
                this._dragSourceBoxId = null;
                this._dragHoverBoxId = null;
                this._dragInBoxContent = false;
                this._addModToBox(dropBoxId, draggedId);
                return;
            }

            // ── Drop on list → standard reorder ──
            // If mod was inside a box, remove it from the box first
            let fromBoxId = null;
            this.mod_boxes.forEach(box => {
                if ((box.mod_ids || []).includes(draggedId)) fromBoxId = box.id;
            });
            if (fromBoxId) {
                const srcBox = this.mod_boxes.find(b => b.id === fromBoxId);
                if (srcBox) {
                    srcBox.mod_ids = srcBox.mod_ids.filter(id => id !== draggedId);
                    this._saveBoxData();
                }
            }

            // Compute insertion index from hit result
            let adj = filtered.length; // default: append
            if (hit) {
                const refIdx = Math.min(hit.index, filtered.length - 1);
                adj = hit.position === 'after' ? refIdx + 1 : refIdx;
            }

            filtered.splice(adj, 0, { type: 'mod', id: draggedId, data: null });
            this.item_order = filtered.map(e => e.id);
            this._saveItemOrder();
            this._currentSort = 'custom';
            if (this._app && this._app.store) this._app.store.set('mod_sort', 'custom');
        }

        if (this._dragSourceBoxId) {
            // ── BOX drag ──
            let adj = filtered.length;
            if (hit) {
                const refIdx = Math.min(hit.index, filtered.length - 1);
                adj = hit.position === 'after' ? refIdx + 1 : refIdx;
            }

            filtered.splice(adj, 0, { type: 'box', id: draggedId, data: null });
            this.item_order = filtered.map(e => e.id);
            this._saveItemOrder();
        }

        this._dragSourceModId = null;
        this._dragSourceBoxId = null;
        this._dragHoverBoxId = null;
        this._dragInBoxContent = false;
        this.renderModList();
    },

    /**
     * Hit-test: find which top-level item is at the given coordinates.
     * Returns {index, position ('before'|'after'), type, el} — always returns a valid result.
     * The index is relative to the visible (non-dragging) items, matching `_endDrag`'s
     * filtered item list so that splice indices stay consistent.
     * @param {number} clientX
     * @param {number} clientY
     * @param {string} [excludeId] - ID of the item being dragged (skipped in hit detection)
     * @private
     */
    _hitTest(clientX, clientY, excludeId) {
        const modList = this._dom.modList;
        if (!modList) return null;

        const allItems = Array.from(modList.querySelectorAll(':scope > .mod-box, :scope > .mod-item'));
        if (allItems.length === 0) return null;

        // Filter to visible items (exclude dragging + excludeId)
        const visibleItems = allItems.filter(el => {
            if (el.classList.contains('dragging')) return false;
            if (excludeId && (el.dataset.modId === excludeId || el.dataset.boxId === excludeId)) return false;
            return true;
        });

        if (visibleItems.length === 0) return null;

        // First pass: try to find a visible item under the cursor
        for (let i = 0; i < visibleItems.length; i++) {
            const el = visibleItems[i];
            const rect = el.getBoundingClientRect();
            if (clientY >= rect.top && clientY <= rect.bottom) {
                const midY = rect.top + rect.height / 2;
                return {
                    index: i,
                    position: clientY < midY ? 'before' : 'after',
                    type: el.classList.contains('mod-box') ? 'box' : 'mod',
                    el: el
                };
            }
        }

        // Second pass: find the nearest visible item by distance
        let bestIdx = 0, bestDist = Infinity;
        for (let i = 0; i < visibleItems.length; i++) {
            const el = visibleItems[i];
            const rect = el.getBoundingClientRect();
            const midY = rect.top + rect.height / 2;
            const dist = Math.abs(clientY - midY);
            if (dist < bestDist) {
                bestDist = dist;
                bestIdx = i;
            }
        }

        const el = visibleItems[bestIdx];
        const rect = el.getBoundingClientRect();
        const midY = rect.top + rect.height / 2;
        return {
            index: bestIdx,
            position: clientY < midY ? 'before' : 'after',
            type: el.classList.contains('mod-box') ? 'box' : 'mod',
            el: el
        };
    },

    /**
     * Position the drop indicator inside a box's content area at clientY.
     * Returns true if positioned, false if the cursor is outside the content area.
     * @private
     */
    _updateBoxContentDropIndicator(boxId, clientY) {
        const boxEl = this._dom.modList?.querySelector(`.mod-box[data-box-id="${boxId}"]`);
        if (!boxEl) return false;
        const content = boxEl.querySelector('.mod-box-content');
        if (!content) return false;

        const contentRect = content.getBoundingClientRect();
        if (clientY < contentRect.top || clientY > contentRect.bottom) return false;

        // Exclude the dragging element from visible items
        const boxItems = Array.from(content.querySelectorAll(':scope > .mod-item'))
            .filter(el => !el.classList.contains('dragging'));
        if (boxItems.length === 0) {
            // Empty or all items are dragging — show indicator at top of content area
            if (!this._dropIndicator) return false;
            this._dropIndicator.style.top = (contentRect.top + 2) + 'px';
            this._dropIndicator.style.left = contentRect.left + 'px';
            this._dropIndicator.style.width = contentRect.width + 'px';
            this._dropIndicator.style.display = 'block';
            return true;
        }

        let insertY = null, insertLeft = contentRect.left, insertWidth = contentRect.width;
        for (let i = 0; i < boxItems.length; i++) {
            const rect = boxItems[i].getBoundingClientRect();
            const midY = rect.top + rect.height / 2;
            if (clientY < midY) {
                insertY = rect.top;
                insertLeft = rect.left;
                insertWidth = rect.width;
                break;
            }
        }
        if (insertY === null) {
            const last = boxItems[boxItems.length - 1];
            const rect = last.getBoundingClientRect();
            insertY = rect.bottom;
            insertLeft = rect.left;
            insertWidth = rect.width;
        }

        if (!this._dropIndicator) return false;
        this._dropIndicator.style.top = (insertY - 1) + 'px';
        this._dropIndicator.style.left = insertLeft + 'px';
        this._dropIndicator.style.width = insertWidth + 'px';
        this._dropIndicator.style.display = 'block';
        return true;
    },

    /**
     * Calculate the insertion index inside a box's content area at clientY.
     * Returns the index (0..visible_count) relative to non-dragging items,
     * matching the array that results after removing the dragged item.
     * @private
     */
    _calcBoxContentInsertIndex(boxId, clientY, draggedId) {
        const boxEl = this._dom.modList?.querySelector(`.mod-box[data-box-id="${boxId}"]`);
        if (!boxEl) return 0;
        const content = boxEl.querySelector('.mod-box-content');
        if (!content) return 0;

        // Exclude the dragging element
        const boxItems = Array.from(content.querySelectorAll(':scope > .mod-item'))
            .filter(el => !el.classList.contains('dragging'));
        if (boxItems.length === 0) return 0;

        for (let i = 0; i < boxItems.length; i++) {
            const rect = boxItems[i].getBoundingClientRect();
            const midY = rect.top + rect.height / 2;
            if (clientY < midY) return i;
        }
        return boxItems.length;
    },

    /**
     * Update the drop indicator line position. @private
     */
    _updateDropIndicator(clientX, clientY) {
        const modList = this._dom.modList;
        if (!modList || !this._dropIndicator) return;

        const allItems = Array.from(modList.querySelectorAll(':scope > .mod-box, :scope > .mod-item'));
        const visibleItems = allItems.filter(el => !el.classList.contains('dragging'));

        if (visibleItems.length === 0) {
            this._hideDropIndicator();
            return;
        }

        let insertY, insertLeft, insertWidth;

        // Check if we're in the list area at all
        const listRect = modList.getBoundingClientRect();
        if (clientY < listRect.top || clientY > listRect.bottom) {
            this._hideDropIndicator();
            return;
        }

        for (let i = 0; i < visibleItems.length; i++) {
            const rect = visibleItems[i].getBoundingClientRect();
            const midY = rect.top + rect.height / 2;

            if (clientY < midY) {
                insertY = rect.top;
                insertLeft = rect.left;
                insertWidth = rect.width;
                break;
            }
        }

        if (insertY === undefined) {
            // After the last item
            const last = visibleItems[visibleItems.length - 1];
            const rect = last.getBoundingClientRect();
            insertY = rect.bottom;
            insertLeft = rect.left;
            insertWidth = rect.width;
        }

        const indicator = this._dropIndicator;
        indicator.style.top = (insertY - 1) + 'px';
        indicator.style.left = insertLeft + 'px';
        indicator.style.width = insertWidth + 'px';
        indicator.style.display = 'block';
    },

    /** Hide the drop indicator. @private */
    _hideDropIndicator() {
        if (this._dropIndicator) {
            this._dropIndicator.style.display = 'none';
        }
    },

    // ── Mod Details ────────────────────────────────────────────

    showModDetails(mod_id) {
        const container = this._dom.detailsContent;
        if (!container) return;

        const mod = this.mods.find(m => m.id === mod_id);
        if (!mod) {
            this.selected_mod_id = null;
            this._renderDetailsEmpty();
            return;
        }

        this.selected_mod_id = mod_id;
        const enabled = !!this.enabled_mods[mod_id];

        container.innerHTML = '';

        // Header
        const header = document.createElement('div');
        header.className = 'detail-header';

        const name = document.createElement('div');
        name.className = 'detail-name';
        name.textContent = mod.name;
        header.appendChild(name);

        const version = document.createElement('span');
        version.className = 'detail-version';
        version.textContent = mod.version || 'v?';
        header.appendChild(version);

        container.appendChild(header);

        // Badges
        const badges = document.createElement('div');
        badges.className = 'detail-badges';

        // Category badge
        const catBadge = document.createElement('span');
        if (mod.affects_gameplay) {
            catBadge.className = 'badge badge-gameplay';
            catBadge.textContent = '🎮 ' + (this._t('affects_gameplay') || '游戏性');
        } else {
            catBadge.className = 'badge badge-cosmetic';
            catBadge.textContent = '🎨 ' + (this._t('cosmetic') || '美化');
        }
        badges.appendChild(catBadge);

        // PCK badge
        if (mod.has_pck) {
            const pck = document.createElement('span');
            pck.className = 'badge badge-pck';
            pck.textContent = '.pck';
            badges.appendChild(pck);
        }

        // DLL badge
        if (mod.has_dll) {
            const dll = document.createElement('span');
            dll.className = 'badge badge-dll';
            dll.textContent = '.dll ⚠';
            badges.appendChild(dll);
        }

        // Source badge
        if (mod.download_source) {
            const src = document.createElement('span');
            src.className = 'badge badge-source';
            src.textContent = mod.download_source;
            badges.appendChild(src);
        }

        container.appendChild(badges);

        // Info section
        const info = document.createElement('div');
        info.className = 'detail-info';

        // 翻译 download_source 为中文显示
        const sourceMap = {
            'nexus': 'N网下载',
            'steam_workshop': 'Steam工坊',
            'local': '本地',
            'manual': '手动',
            'github': 'GitHub',
            'url': '网址',
        };
        const sourceValue = mod.download_source || '--';
        const sourceDisplay = sourceMap[sourceValue] || (sourceValue === 'nexus' ? 'N网下载' : sourceValue);

        const infoRows = [
            { label: this._t('author_label') || '作者', value: mod.author || '--' },
            { label: this._t('installed_time') || '安装时间', value: mod.installed_time ? STS2Utils.formatDate(this._parseTimestamp(mod.installed_time)) : '--' },
            { label: this._t('source_label') || '来源', value: sourceDisplay },
            { label: 'ID', value: mod.id || '--' },
        ];

        infoRows.forEach(row => {
            const div = document.createElement('div');
            div.className = 'detail-info-row';

            const label = document.createElement('span');
            label.className = 'info-label';
            label.textContent = row.label;
            div.appendChild(label);

            const value = document.createElement('span');
            value.className = 'info-value';
            value.textContent = row.value;
            div.appendChild(value);

            info.appendChild(div);
        });

        container.appendChild(info);

        // Description
        if (mod.description) {
            const desc = document.createElement('div');
            desc.className = 'detail-description';
            desc.textContent = mod.description;
            container.appendChild(desc);
        }

        // Dependencies
        if (mod.dependencies && mod.dependencies.length > 0) {
            const deps = document.createElement('div');
            deps.className = 'detail-dependencies';

            const depTitle = document.createElement('div');
            depTitle.className = 'dep-title';
            depTitle.textContent = this._t('dependencies') || '依赖';
            deps.appendChild(depTitle);

            const depList = document.createElement('div');
            depList.className = 'dep-list';

            mod.dependencies.forEach(dep => {
                const depItem = document.createElement('div');
                depItem.className = 'dep-item';
                // 支持字符串和对象格式的依赖
                const depId = typeof dep === 'string' ? dep : (dep.id || dep.mid || dep.mod_id || null);
                const depName = typeof dep === 'string' ? dep : (dep.id || dep.mid || dep.mod_id || (typeof dep === 'object' ? JSON.stringify(dep) : String(dep)));
                const depMod = depId ? this.mods.find(m => m.id === depId || m.name === depId) : null;
                if (!depMod) {
                    depItem.classList.add('missing');
                    depItem.textContent = '⚠ ' + depName + ' (' + (this._t('not_installed') || '未安装') + ')';
                } else {
                    depItem.textContent = '✓ ' + depName;
                }

                depList.appendChild(depItem);
            });

            deps.appendChild(depList);
            container.appendChild(deps);
        }

        // Notes section (user-editable)
        const notes = document.createElement('div');
        notes.className = 'detail-notes';

        const notesHeader = document.createElement('div');
        notesHeader.className = 'notes-header';

        const notesTitle = document.createElement('span');
        notesTitle.className = 'notes-title';
        notesTitle.textContent = '📝 ' + (this._t('mod_note') || '备注');
        notesHeader.appendChild(notesTitle);

        const notesEditBtn = document.createElement('button');
        notesEditBtn.className = 'btn btn-sm btn-ghost';
        notesEditBtn.textContent = this._t('mod_note_edit') || '编辑备注';
        notesEditBtn.addEventListener('click', () => this._showNoteEditDialog(mod_id));
        notesHeader.appendChild(notesEditBtn);

        notes.appendChild(notesHeader);

        const noteText = this._modNotes[mod_id] || '';
        const notesContent = document.createElement('div');
        notesContent.className = 'notes-text' + (noteText ? '' : ' notes-empty');
        notesContent.textContent = noteText || (this._t('mod_note_placeholder') || '点击添加备注...');
        if (!noteText) {
            notesContent.addEventListener('click', () => this._showNoteEditDialog(mod_id));
        }
        notes.appendChild(notesContent);

        // System info (DLL/gameplay warnings)
        if (mod.has_dll) {
            const sysNote = document.createElement('div');
            sysNote.className = 'notes-system';
            sysNote.textContent = '⚠ ' + (this._t('dll_warning') || '该模组包含 DLL 文件，请确保来源可信。');
            notes.appendChild(sysNote);
        } else if (mod.affects_gameplay) {
            const sysNote = document.createElement('div');
            sysNote.className = 'notes-system';
            sysNote.textContent = '⚠ ' + (this._t('gameplay_note') || '该模组会影响游戏玩法，可能与其他模组产生兼容问题。');
            notes.appendChild(sysNote);
        }

        container.appendChild(notes);

        // Action buttons
        const actions = document.createElement('div');
        actions.className = 'detail-actions';

        const enableBtn = document.createElement('button');
        enableBtn.className = 'btn btn-enable' + (enabled ? ' is-enabled' : '');
        enableBtn.textContent = enabled
            ? (this._t('disable') || '停用')
            : (this._t('enable') || '启用');
        enableBtn.addEventListener('click', () => {
            this.toggleMod(mod_id);
            this.showModDetails(mod_id);
        });
        actions.appendChild(enableBtn);

        const uninstallBtn = document.createElement('button');
        uninstallBtn.className = 'btn btn-uninstall';
        uninstallBtn.textContent = this._t('uninstall_mod') || '卸载';
        uninstallBtn.addEventListener('click', () => {
            this.uninstallMod(mod_id);
        });
        actions.appendChild(uninstallBtn);

        container.appendChild(actions);

        // Emit event
        if (this._app) {
            this._app.emit('mod-selected', mod);
        }
    },

    _renderDetailsEmpty() {
        const container = this._dom.detailsContent;
        if (!container) return;

        container.innerHTML = `
            <div class="empty-state">
                <div class="empty-icon">📋</div>
                <p>${STS2Utils.escapeHtml(this._t('click_mod_for_details') || '点击左侧列表中的模组查看详情')}</p>
            </div>
        `;
    },

    // ── Toggle / Enable / Disable ──────────────────────────────

    async toggleMod(mod_id) {
        const wasEnabled = !!this.enabled_mods[mod_id];
        const willEnable = !wasEnabled;

        // Check dependencies before enabling
        if (willEnable) {
            const depResult = this._checkDepsForMod(mod_id);
            if (depResult.hasMissing || depResult.hasDisabled) {
                return this._showDependencyDialog(mod_id, depResult);
            }
        }

        // 后端 API 调用 - 后端会自动保存到 config
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = willEnable
                    ? await this._app.api.enableMod(mod_id)
                    : await this._app.api.disableMod(mod_id);
                if (!resp.success && resp.success !== undefined) {
                    this._app.notifications.show(resp.message || 'Toggle failed', 'error');
                    return;
                }
                // API 调用成功，后端已保存配置
                // 更新本地状态以反映后端状态
                if (wasEnabled) {
                    delete this.enabled_mods[mod_id];
                } else {
                    this.enabled_mods[mod_id] = true;
                }
                // Sync to current tag data
                if (this.current_tag && this.tag_data) {
                    this.tag_data[this.current_tag] = Object.keys(this.enabled_mods).filter(id => this.enabled_mods[id]);
                }
            } catch (e) {
                console.warn('[STS2Mods] API toggleMod failed:', e);
                this._app.notifications.show('操作失败: ' + e.message, 'error');
                return;
            }
        } else {
            // 后端未连接时，仅更新本地状态（临时）
            if (wasEnabled) {
                delete this.enabled_mods[mod_id];
            } else {
                this.enabled_mods[mod_id] = true;
            }
        }

        this._updateToggleInList(mod_id);
        this.updateStatusBar();

        const mod = this.mods.find(m => m.id === mod_id);
        const isNow = !!this.enabled_mods[mod_id];

        if (this._app && this._app.notifications) {
            this._app.notifications.show(
                `${mod ? mod.name : mod_id}: ${isNow ? (this._t('enabled') || '已启用') : (this._t('disabled') || '已停用')}`,
                isNow ? 'success' : 'info',
                2000
            );
        }

        // Emit event
        if (this._app) {
            this._app.emit('mod-toggled', { id: mod_id, enabled: isNow });
        }
    },

    _updateToggleInList(mod_id) {
        const item = this._dom.modList?.querySelector(`.mod-item[data-mod-id="${mod_id}"]`);
        if (!item) return;
        const input = item.querySelector('.mod-item-toggle input');
        if (input) {
            input.checked = !!this.enabled_mods[mod_id];
        }
    },

    // ── Dependency Checking ────────────────────────────────────

    /**
     * Resolve a dependency string (name or ID) to a mod object.
     * @param {string} dep - dependency name or ID
     * @returns {object|null}
     * @private
     */
    _resolveDep(dep) {
        // 支持字符串格式和对象格式的依赖
        const depId = typeof dep === 'string' ? dep : (dep.id || dep.mid || dep.mod_id || null);
        if (!depId) return null;
        return this.mods.find(m => m.id === depId || m.name === depId) || null;
    },

    /**
     * Check a mod's dependencies and categorize them.
     * @param {string} mod_id
     * @returns {{ hasMissing: boolean, hasDisabled: boolean, missing: object[], disabled: object[] }}
     * @private
     */
    _checkDepsForMod(mod_id) {
        const mod = this.mods.find(m => m.id === mod_id);
        if (!mod || !mod.dependencies || mod.dependencies.length === 0) {
            return { hasMissing: false, hasDisabled: false, missing: [], disabled: [] };
        }

        const missing = [];
        const disabled = [];

        for (const dep of mod.dependencies) {
            const depMod = this._resolveDep(dep);
            // 从 dep 中提取 ID（支持字符串或对象格式）
            const depId = typeof dep === 'string' ? dep : (dep.id || dep.mid || dep.mod_id || String(dep));
            if (!depMod) {
                // 依赖未安装，但仍然允许强制启用
                missing.push({ name: depId, id: depId });
            } else if (!this.enabled_mods[depMod.id]) {
                disabled.push(depMod);
            }
        }

        return {
            hasMissing: missing.length > 0,
            hasDisabled: disabled.length > 0,
            missing,
            disabled,
        };
    },

    /**
     * Show a dependency warning dialog when enabling a mod with unresolved deps.
     * @param {string} mod_id
     * @param {{ hasMissing: boolean, hasDisabled: boolean, missing: object[], disabled: object[] }} depResult
     * @private
     */
    _showDependencyDialog(mod_id, depResult) {
        const mod = this.mods.find(m => m.id === mod_id);
        if (!mod) return;

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';

        let bodyHTML = '';

        // Disabled deps section (can be auto-enabled)
        if (depResult.hasDisabled) {
            const list = depResult.disabled.map(d =>
                `<div style="padding:4px 0;display:flex;align-items:center;gap:8px">
                    <span style="color:var(--warning);font-size:14px">⚠</span>
                    <span style="color:var(--text-primary)">${STS2Utils.escapeHtml(d.name)}</span>
                    <span style="color:var(--text-muted);font-size:11px">(${STS2Utils.escapeHtml(d.id)})</span>
                </div>`
            ).join('');
            bodyHTML += `
                <div style="margin-bottom:12px">
                    <div style="font-size:12px;color:var(--text-secondary);margin-bottom:6px">
                        ${this._t('deps_disabled') || '以下依赖未启用：'}
                    </div>
                    ${list}
                </div>`;
        }

        // Missing deps section (not installed)
        if (depResult.hasMissing) {
            const list = depResult.missing.map(d =>
                `<div style="padding:4px 0;display:flex;align-items:center;gap:8px">
                    <span style="color:var(--danger);font-size:14px">✖</span>
                    <span style="color:var(--text-primary)">${STS2Utils.escapeHtml(d.name)}</span>
                    <span style="color:var(--danger);font-size:11px">(${this._t('not_installed') || '未安装'})</span>
                </div>`
            ).join('');
            bodyHTML += `
                <div style="margin-bottom:8px">
                    <div style="font-size:12px;color:var(--text-secondary);margin-bottom:6px">
                        ${this._t('deps_not_installed') || '以下依赖未安装：'}
                    </div>
                    ${list}
                </div>`;
        }

        // Action buttons
        let footerHTML = '';
        // 无论是否有未安装的依赖，都可以强制启用（但会显示警告）
        if (depResult.hasDisabled) {
            footerHTML += `<button class="btn btn-primary dep-enable-all">${this._t('enable_deps_and_continue')}</button>`;
        }
        if (depResult.hasMissing) {
            footerHTML += `<button class="btn btn-ghost dep-force-enable" style="color:var(--warning)">${this._t('force_enable_anyway') || '强制启用'}</button>`;
        }
        footerHTML += `<button class="btn btn-ghost dep-cancel">${this._t('cancel')}</button>`;

        overlay.innerHTML = `
            <div class="modal" style="max-width:440px">
                <div class="modal__header">
                    <span class="modal__title">${this._t('dependency_enable_title') || '模组依赖检查'}</span>
                    <button class="modal__close">&times;</button>
                </div>
                <div class="modal__body" style="padding:var(--sp-lg) var(--sp-xl)">
                    <div style="font-size:13px;color:var(--text-secondary);margin-bottom:12px">
                        <strong style="color:var(--text-primary)">${STS2Utils.escapeHtml(mod.name)}</strong>
                        ${this._t('has_unresolved_deps') || '存在未解决的依赖关系：'}
                    </div>
                    ${bodyHTML}
                    ${depResult.hasMissing ? `<div style="font-size:11px;color:var(--danger);margin-top:8px">${this._t('missing_dep_warning') || '未安装的依赖可能导致模组工作异常'}</div>` : ''}
                </div>
                <div class="modal__footer" style="gap:8px">
                    ${footerHTML}
                </div>
            </div>`;

        const close = () => overlay.remove();
        overlay.querySelector('.modal__close').addEventListener('click', close);
        overlay.querySelector('.dep-cancel').addEventListener('click', close);

        // "Enable deps and continue" button
        const enableBtn = overlay.querySelector('.dep-enable-all');
        if (enableBtn) {
            enableBtn.addEventListener('click', async () => {
                close();
                // Enable all disabled deps first
                for (const dep of depResult.disabled) {
                    if (!this.enabled_mods[dep.id]) {
                        try { await this.toggleMod(dep.id); } catch (e) { /* skip circular */ }
                    }
                }
                // Then enable the original mod (skip dep check since we just enabled them)
                await this._doToggleMod(mod_id);
            });
        }

        // "Continue anyway" button (skip dep check)
        const skipBtn = overlay.querySelector('.dep-skip');
        if (skipBtn) {
            skipBtn.addEventListener('click', async () => {
                close();
                await this._doToggleMod(mod_id);
            });
        }

        // "Force enable anyway" button (for missing deps)
        const forceBtn = overlay.querySelector('.dep-force-enable');
        if (forceBtn) {
            forceBtn.addEventListener('click', async () => {
                close();
                await this._doToggleMod(mod_id);
            });
        }

        document.getElementById('modal-container').appendChild(overlay);
    },

    /**
     * Perform the actual mod toggle (bypassing dependency check).
     * @param {string} mod_id
     * @private
     */
    async _doToggleMod(mod_id) {
        const wasEnabled = !!this.enabled_mods[mod_id];
        const willEnable = !wasEnabled;

        // 后端 API 调用 - 后端会自动保存到 config
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = willEnable
                    ? await this._app.api.enableMod(mod_id)
                    : await this._app.api.disableMod(mod_id);
                if (!resp.success && resp.success !== undefined) {
                    this._app.notifications.show(resp.message || 'Toggle failed', 'error');
                    return;
                }
                // API 调用成功，后端已保存配置
                if (wasEnabled) {
                    delete this.enabled_mods[mod_id];
                } else {
                    this.enabled_mods[mod_id] = true;
                }
                // Sync to current tag data
                if (this.current_tag && this.tag_data) {
                    this.tag_data[this.current_tag] = Object.keys(this.enabled_mods).filter(id => this.enabled_mods[id]);
                }
            } catch (e) {
                console.warn('[STS2Mods] API toggleMod failed:', e);
                this._app.notifications.show('操作失败: ' + e.message, 'error');
                return;
            }
        } else {
            // 后端未连接时，仅更新本地状态
            if (wasEnabled) {
                delete this.enabled_mods[mod_id];
            } else {
                this.enabled_mods[mod_id] = true;
            }
        }

        this._updateToggleInList(mod_id);
        this.updateStatusBar();

        const mod = this.mods.find(m => m.id === mod_id);
        const isNow = !!this.enabled_mods[mod_id];

        if (this._app && this._app.notifications) {
            this._app.notifications.show(
                `${mod ? mod.name : mod_id}: ${isNow ? (this._t('enabled') || '已启用') : (this._t('disabled') || '已停用')}`,
                isNow ? 'success' : 'info',
                2000
            );
        }

        if (this._app) {
            this._app.emit('mod-toggled', { id: mod_id, enabled: isNow });
        }
    },

    // ── Batch Operations ───────────────────────────────────────

    toggleBatchMode() {
        console.log('[STS2Mods] toggleBatchMode called, current:', this.batch_mode);
        if (this.batch_mode) {
            this._exitBatchMode();
            this.renderModList();
        } else {
            this._enterBatchMode();
        }
    },

    async batchEnable() {
        if (!this.batch_mode) { this._enterBatchMode(); return; }
        const ids = Object.keys(this.batch_selected).filter(id => this.batch_selected[id]);
        if (ids.length === 0) {
            if (this._app && this._app.notifications) {
                this._app.notifications.show(
                    this._t('no_mods_selected') || '未选择任何模组',
                    'warning', 2000
                );
            }
            return;
        }
        // 后端 API 调用 - 后端会自动保存到 config
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.batchEnable(ids);
                if (resp && (resp.success || resp.data?.success)) {
                    // API 调用成功，后端已保存配置
                    ids.forEach(id => { this.enabled_mods[id] = true; });
          // Sync to current tag data
          if (this.current_tag && this.tag_data) {
              this.tag_data[this.current_tag] = Object.keys(this.enabled_mods).filter(id => this.enabled_mods[id]);
          }
                } else {
                    throw new Error(resp?.message || resp?.data?.message || '批量启用失败');
                }
            } catch (e) {
                console.warn('[STS2Mods] API batchEnable failed:', e);
                this._app.notifications.show('批量启用失败: ' + e.message, 'error');
                return;
            }
        } else {
            // 后端未连接时，仅更新本地状态
            ids.forEach(id => { this.enabled_mods[id] = true; });
          // Sync to current tag data
          if (this.current_tag && this.tag_data) {
              this.tag_data[this.current_tag] = Object.keys(this.enabled_mods).filter(id => this.enabled_mods[id]);
          }
        }
        this.updateStatusBar();
        this._exitBatchMode();
        this.renderModList();
        if (this._app && this._app.notifications) {
            this._app.notifications.show(
                (this._t('batch_enabled') || '批量启用') + `: ${ids.length}`,
                'success', 2000
            );
        }
    },

    async batchDisable() {
        if (!this.batch_mode) { this._enterBatchMode(); return; }
        const ids = Object.keys(this.batch_selected).filter(id => this.batch_selected[id]);
        if (ids.length === 0) {
            if (this._app && this._app.notifications) {
                this._app.notifications.show(
                    this._t('no_mods_selected') || '未选择任何模组',
                    'warning', 2000
                );
            }
            return;
        }
        // 后端 API 调用 - 后端会自动保存到 config
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                const resp = await this._app.api.batchDisable(ids);
                if (resp && (resp.success || resp.data?.success)) {
                    // API 调用成功，后端已保存配置
                    ids.forEach(id => { delete this.enabled_mods[id]; });
          // Sync to current tag data
          if (this.current_tag && this.tag_data) {
              this.tag_data[this.current_tag] = Object.keys(this.enabled_mods).filter(id => this.enabled_mods[id]);
          }
                } else {
                    throw new Error(resp?.message || resp?.data?.message || '批量停用失败');
                }
            } catch (e) {
                console.warn('[STS2Mods] API batchDisable failed:', e);
                this._app.notifications.show('批量停用失败: ' + e.message, 'error');
                return;
            }
        } else {
            // 后端未连接时，仅更新本地状态
            ids.forEach(id => { delete this.enabled_mods[id]; });
          // Sync to current tag data
          if (this.current_tag && this.tag_data) {
              this.tag_data[this.current_tag] = Object.keys(this.enabled_mods).filter(id => this.enabled_mods[id]);
          }
        }
        this.updateStatusBar();
        this._exitBatchMode();
        this.renderModList();
        if (this._app && this._app.notifications) {
            this._app.notifications.show(
                (this._t('batch_disabled') || '批量停用') + `: ${ids.length}`,
                'info', 2000
            );
        }
    },

    selectAll() {
        if (!this.batch_mode) { this._enterBatchMode(); }
        const allSelected = this.displayed_mods.every(m => this.batch_selected[m.id]);
        this.batch_selected = {};
        if (!allSelected) {
            this.displayed_mods.forEach(m => { this.batch_selected[m.id] = true; });
        }
        this.renderModList();
    },

    _enterBatchMode() {
        this.batch_mode = true;
        this.batch_selected = {};
        this.renderModList();
        this._updateBatchModeUI(true);
        this._updateBatchCountHint();
        if (this._app && this._app.notifications) {
            this._app.notifications.show(
                this._t('batch_mode_entered') || '已进入批量模式，点击模组选择 | Ctrl+A全选 | Esc退出',
                'info', 3000
            );
        }
    },

    _exitBatchMode() {
        this.batch_mode = false;
        this.batch_selected = {};
        this._updateBatchModeUI(false);
    },

    _updateBatchModeUI(active) {
        // Toggle class on toolbar
        const toolbar = document.querySelector('.mod-toolbar');
        if (toolbar) toolbar.classList.toggle('batch-mode-active', active);
        // Toggle class on mod-list container so CSS selectors work
        const modList = this._dom.modList;
        if (modList) modList.classList.toggle('batch-mode-active', active);
        // Toggle batch selectors visibility directly
        modList && modList.querySelectorAll('.batch-selector').forEach(el => {
            el.style.display = active ? 'flex' : '';
        });
        // Toggle hint visibility
        const hint = document.querySelector('.batch-mode-hint');
        if (hint) hint.style.display = active ? 'inline-flex' : 'none';
        const toggleBtn = this._dom.btnBatchToggle;
        if (toggleBtn) {
            toggleBtn.classList.toggle('btn-primary', active);
            toggleBtn.classList.toggle('btn-ghost', !active);
            toggleBtn.textContent = active ? (this._t('exit_batch_mode') || '退出批量模式') : (this._t('batch_mode') || '批量选择');
        }
    },

    _toggleBatchSelect(mod_id, itemEl) {
        if (this.batch_selected[mod_id]) {
            delete this.batch_selected[mod_id];
            itemEl.classList.remove('batch-selected');
            itemEl.querySelector('.batch-selector')?.classList.remove('checked');
        } else {
            this.batch_selected[mod_id] = true;
            itemEl.classList.add('batch-selected');
            itemEl.querySelector('.batch-selector')?.classList.add('checked');
        }
        this._updateBatchCountHint();
    },

    _updateBatchCountHint() {
        const hint = document.querySelector('.batch-mode-hint [data-i18n]');
        if (hint) {
            const count = Object.keys(this.batch_selected).length;
            hint.textContent = (this._t('batch_mode_hint') || '已选中') + ' ' + count;
        }
    },

    _onModItemClick(e, mod, item) {
        if (e.target.closest('.mod-item-toggle')) return;

        if (e.ctrlKey || e.metaKey) {
            // Ctrl+click: toggle multi-select without entering batch mode
            if (!this.batch_mode) {
                this.batch_mode = true;
                this._updateBatchModeUI(true);
            }
            this._toggleBatchSelect(mod.id, item);
            return;
        }

        if (this.batch_mode) {
            this._toggleBatchSelect(mod.id, item);
        } else {
            this.showModDetails(mod.id);
            this._dom.modList.querySelectorAll('.mod-item').forEach(el => el.classList.remove('selected'));
            item.classList.add('selected');
        }
    },

    // ── Search ─────────────────────────────────────────────────

    searchMods(query) {
        this._searchQuery = query;
        this.applyFiltersAndSort();
        this.renderModList();
    },

    // ── Sort ───────────────────────────────────────────────────

    sortMods(by) {
        this._currentSort = by;
        if (this._app && this._app.store) {
            this._app.store.set('mod_sort', by);
        }
        this.applyFiltersAndSort();
        this.renderModList();
    },

    // ── Category Filter ────────────────────────────────────────

    filterCategory(cat) {
        this._currentCategory = cat;
        if (this._app && this._app.store) {
            this._app.store.set('mod_filter', cat);
        }
        this.applyFiltersAndSort();
        this.renderModList();
    },

    // ── Install / Uninstall ────────────────────────────────────

    async installMod(file) {
        const modal = document.getElementById('install-progress-modal');
        const body = document.getElementById('ipm-body');
        const footer = document.getElementById('ipm-footer');
        const btnClose = document.getElementById('ipm-btn-close');
        const btnCancel = document.getElementById('ipm-btn-cancel');

        const t = (key) => this._t(key);

        // Helper to format file size
        const fmtSize = (bytes) => {
            if (bytes < 1024) return bytes + ' B';
            if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
            return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
        };

        // Steps definition
        const STEPS = [
            { label: t('step_upload') || '上传文件' },
            { label: t('step_install') || '安装模组' },
            { label: t('step_finish') || '完成' },
        ];

        // Render progress UI
        const renderProgress = (step, percent, status) => {
            let stepCircles = '';
            for (let i = 0; i < STEPS.length; i++) {
                const cls = i < step ? 'done' : i === step ? 'active' : '';
                const mark = i < step ? '✓' : i + 1;
                const line = i < STEPS.length - 1
                    ? `<div class="ipm-step-line${i < step ? ' done' : ''}"></div>`
                    : '';
                stepCircles += `<div class="ipm-step ${cls}">${line}<div class="ipm-step-circle">${mark}</div><span class="ipm-step-label">${STEPS[i].label}</span></div>`;
            }
            body.innerHTML = `
                <div class="ipm-file-info">
                    <span class="ipm-file-icon">📦</span>
                    <div class="ipm-file-details">
                        <p class="ipm-file-name">${file.name}</p>
                        <p class="ipm-file-size">${fmtSize(file.size)}</p>
                    </div>
                </div>
                <div class="ipm-progress-section">
                    <div class="ipm-steps">${stepCircles}</div>
                    <div class="ipm-progress-bar-wrap">
                        <div class="ipm-progress-bar-fill" id="ipm-bar-fill" style="width:${percent}%"></div>
                    </div>
                    <div class="ipm-progress-percent" id="ipm-percent">${percent}%</div>
                    <div class="ipm-progress-status" id="ipm-status">${status}</div>
                </div>`;
        };

        // Render success UI
        const renderSuccess = (msg) => {
            body.innerHTML = `
                <div style="text-align:center;padding:8px 0 24px">
                    <div class="ipm-success-icon">✓</div>
                    <p class="ipm-complete-title">${t('install_success') || '安装成功'}</p>
                    <p class="ipm-complete-subtitle">${msg || ''}</p>
                </div>`;
            btnClose.style.display = '';
            btnCancel.style.display = 'none';
            footer.style.display = 'flex';
        };

        // Render error UI
        const renderError = (msg) => {
            body.innerHTML = `
                <div style="text-align:center;padding:8px 0 24px">
                    <div class="ipm-error-icon">✕</div>
                    <p class="ipm-error-title">${t('install_failed_title') || '安装失败'}</p>
                    <p class="ipm-error-subtitle">${msg || ''}</p>
                </div>`;
            btnClose.style.display = '';
            btnCancel.style.display = 'none';
            footer.style.display = 'flex';
        };

        // Render conflict UI (versions differ, user must choose)
        const renderConflict = (conflicts, conflictPendingDir) => {
            let html = '';
            for (const c of conflicts) {
                html += `
                <div style="display:flex;gap:8px;font-size:12px;margin-bottom:8px">
                    <div style="flex:1;padding:8px;background:var(--bg-surface);border-radius:var(--radius-md)">
                        <div style="color:var(--text-muted);margin-bottom:4px">当前版本</div>
                        <div style="color:var(--text-primary)">${STS2Utils.escapeHtml(c.name)}</div>
                        <div style="color:var(--accent)">${c.existing_version || '?'}</div>
                    </div>
                    <div style="flex:1;padding:8px;background:var(--bg-surface);border-radius:var(--radius-md)">
                        <div style="color:var(--text-muted);margin-bottom:4px">新版本</div>
                        <div style="color:var(--text-primary)">${STS2Utils.escapeHtml(c.name)}</div>
                        <div style="color:var(--success)">${c.new_version || '?'}</div>
                    </div>
                </div>`;
            }
            const conflictText = t('version_conflict_different_version') || '已安装「{name}」(v{old})，是否替换为新版本 (v{new})？';
            const firstConflict = conflicts[0] || {};
            const descriptionText = conflictText
                .replace('{name}', STS2Utils.escapeHtml(firstConflict.name || ''))
                .replace('{old}', firstConflict.existing_version || '?')
                .replace('{new}', firstConflict.new_version || '?');
            body.innerHTML = `
                <div style="margin-bottom:12px;font-size:13px;color:var(--text-secondary)">
                    ${descriptionText}
                </div>
                ${html}
                <div style="font-size:12px;color:var(--text-muted);margin-top:8px">${conflicts.length} 个模组存在版本冲突</div>`;
            btnCancel.style.display = 'none';

            // Ensure footer is visible for buttons
            footer.style.display = 'flex';

            // Add buttons
            const btnGroup = document.createElement('div');
            btnGroup.style.cssText = 'display:flex;gap:8px;margin-top:16px';
            btnGroup.innerHTML = `
                <button class="btn btn-primary" id="ipm-btn-conflict-replace">${t('version_conflict_replace') || '替换（自动备份）'}</button>
                <button class="btn btn-ghost" id="ipm-btn-conflict-skip">${t('version_conflict_skip') || '跳过'}</button>`;
            body.appendChild(btnGroup);

            // Replace: apply the pending mods (overwrite)
            document.getElementById('ipm-btn-conflict-replace').addEventListener('click', async () => {
                try {
                    const resp = await this._app.api.resolveConflicts(conflictPendingDir);
                    const data = resp.data || resp;
                    if (data.success) {
                        document.getElementById('ipm-title').textContent = t('install_complete') || '安装完成';
                        renderSuccess('');
                        await this.loadMods();
                    } else {
                        renderError(data.message || '冲突解决失败');
                    }
                } catch (e) {
                    renderError(e.message || '冲突解决失败');
                }
            });

            // Skip: cancel and keep existing
            document.getElementById('ipm-btn-conflict-skip').addEventListener('click', () => {
                modal.classList.remove('active');
            });
        };

        // Reset UI
        document.getElementById('ipm-title').textContent = t('installing_mod') || '正在安装模组...';
        document.getElementById('ipm-subtitle').textContent = '';
        btnClose.style.display = 'none';
        btnCancel.style.display = '';
        footer.style.display = 'flex';
        btnCancel.onclick = () => { modal.classList.remove('active'); };
        btnClose.onclick = () => { modal.classList.remove('active'); };
        renderProgress(0, 0, t('step_upload') || '准备上传...');

        // Show modal
        modal.classList.add('active');

        // Try backend API install
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                renderProgress(0, 10, t('reading_file') || '读取文件中...');
                const { filename, data_base64 } = await this._app.api.uploadFile(file);

                renderProgress(0, 40, t('uploading') || '上传中...');
                document.getElementById('ipm-percent').textContent = '';
                document.getElementById('ipm-status').textContent = t('uploading_mod') || '正在上传模组...';
                document.getElementById('ipm-status').classList.add('ipm-status-animating');

                const resp = await this._app.api.installMod(filename, data_base64);

                const ipmStatus = document.getElementById('ipm-status');
                if (ipmStatus) ipmStatus.classList.remove('ipm-status-animating');
                renderProgress(1, 70, t('installing_mod') || '正在安装模组...');
                document.getElementById('ipm-percent').textContent = '70%';

                const data = resp.data || resp;
                const success = data.success;
                const hasConflicts = data.has_conflicts;
                const message = data.message;
                const modInfo = data.mod_info;

                if (success) {
                    renderProgress(2, 100, '');
                    document.getElementById('ipm-percent').textContent = '100%';
                    document.getElementById('ipm-title').textContent = t('install_complete') || '安装完成';
                    renderSuccess(modInfo?.name || filename);
                    await this.loadMods();
                } else if (hasConflicts) {
                    document.getElementById('ipm-title').textContent = t('version_conflict_title') || '版本冲突';
                    renderConflict(data.conflicts, data.conflict_pending_dir);
                } else if (data.error_type === 'is_bundle_not_mod') {
                    document.getElementById('ipm-title').textContent = t('bundle_not_mod') || '整合包文件';
                    renderError(message || '请到「整合包」页面导入此文件');
                } else {
                    renderError(message || t('install_failed') || '安装失败');
                }
            } catch (e) {
                const ipmStatus = document.getElementById('ipm-status');
                if (ipmStatus) ipmStatus.classList.remove('ipm-status-animating');
                document.getElementById('ipm-title').textContent = t('install_failed') || '安装失败';
                renderError(e.message || t('install_failed_no_args') || '安装失败');
            }
        } else {
            renderError(t('backend_not_connected') || '后端未连接，无法安装');
        }
    },

    async uninstallMod(mod_id) {
        const mod = this.mods.find(m => m.id === mod_id);
        if (!mod) return;

        // Confirm
        const confirmed = confirm(
            (this._t('confirm_uninstall') || '确认卸载') + '\n' + mod.name + '?'
        );
        if (!confirmed) return;

        // Try backend API uninstall
        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try {
                await this._app.api.uninstallMod(mod_id);
            } catch (e) {
                console.warn('[STS2Mods] API uninstallMod failed:', e);
            }
        }

        // Remove from mods array
        this.mods = this.mods.filter(m => m.id !== mod_id);

        // Remove from enabled
        delete this.enabled_mods[mod_id];

        // Remove from boxes
        this.mod_boxes.forEach(box => {
            box.mod_ids = (box.mod_ids || []).filter(id => id !== mod_id);
        });

        // Clear selection if this was selected
        if (this.selected_mod_id === mod_id) {
            this.selected_mod_id = null;
            this._renderDetailsEmpty();
        }

        this.saveMods();
        this._saveBoxData();
        this.applyFiltersAndSort();
        this.renderModList();
        this.updateStatusBar();

        if (this._app && this._app.notifications) {
            this._app.notifications.show(
                (this._t('mod_uninstalled') || '模组已卸载') + ': ' + mod.name,
                'info', 3000
            );
        }

        if (this._app) {
            this._app.emit('mod-uninstalled', { id: mod_id });
        }
    },

    // ── Status Bar ─────────────────────────────────────────────

    updateStatusBar() {
        const label = this._dom.statusLabel;
        if (!label) return;

        // 只统计实际存在于 mods 数组中的已启用模组
        const validModIds = new Set(this.mods.map(m => m.id));
        const enabledCount = Object.keys(this.enabled_mods).filter(id => {
            return this.enabled_mods[id] && validModIds.has(id);
        }).length;
        const totalCount = this.mods.length;

        label.innerHTML = `${enabledCount} <span data-i18n="enable">${this._t('enabled') || '已启用'}</span> / ${totalCount} <span data-i18n="mod_count">${this._t('total') || '总数'}</span>`;
    },

    // ── Full Refresh ───────────────────────────────────────────

    refreshUI() {
        // Restore persisted sort/filter state
        if (this._app && this._app.store) {
            this._currentSort = this._app.store.get('mod_sort', 'name');
            this._currentCategory = this._app.store.get('mod_filter', 'all');
        }

        this._cacheDom();
        this.applyFiltersAndSort();
        this.renderModList();
        this.renderTagPresets();
        this.updateStatusBar();

        // Restore details if a mod is selected
        if (this.selected_mod_id) {
            this.showModDetails(this.selected_mod_id);
        }

        // Update category tags active state
        const catTags = this._dom.categoryTags;
        if (catTags) {
            catTags.querySelectorAll('.tag').forEach(t => {
                t.classList.toggle('active', t.dataset.category === this._currentCategory);
            });
        }
    },

    // ── Helpers ────────────────────────────────────────────────

    _hasMissingDeps(mod) {
        if (!mod.dependencies || mod.dependencies.length === 0) return false;
        return mod.dependencies.some(dep => {
            const depId = typeof dep === 'string' ? dep : (dep.id || dep.mid || dep.mod_id || null);
            if (!depId) return false;
            return !this.mods.some(m => m.id === depId || m.name === depId);
        });
    },
};

// ── Export ─────────────────────────────────────────────────────
window.STS2Mods = STS2Mods;
