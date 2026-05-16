/**
 * STS2Tutorial - First-run tutorial system
 *
 * Displays a full-screen overlay with step-by-step guidance for new users.
 * Highlights target elements with a dark overlay + transparent cutout.
 * Tracks completion state in the store to avoid re-showing.
 */
window.STS2Tutorial = {

    // ── State ────────────────────────────────────────────────
    isActive: false,
    currentStep: 0,
    _app: null,
    _overlay: null,
    _dialog: null,

    /**
     * Tutorial steps definition.
     * highlight: CSS selector of the element to spotlight (null for no highlight).
     */
    steps: [
        {
            id: 'welcome',
            title_key: 'tutorial_welcome_title',
            content_key: 'tutorial_welcome_content',
            highlight: null,
        },
        {
            id: 'game_path',
            title_key: 'tutorial_game_path_title',
            content_key: 'tutorial_game_path_content',
            highlight: null, // Settings path section - may not be visible
        },
        {
            id: 'mods',
            title_key: 'tutorial_mods_title',
            content_key: 'tutorial_mods_content',
            highlight: '#page-mods',
        },
        {
            id: 'saves',
            title_key: 'tutorial_saves_title',
            content_key: 'tutorial_saves_content',
            highlight: '#page-saves',
        },
        {
            id: 'nexus',
            title_key: 'tutorial_nexus_title',
            content_key: 'tutorial_nexus_content',
            highlight: '#page-nexus',
        },
        {
            id: 'finish',
            title_key: 'tutorial_completed',
            content_key: 'tutorial_welcome_content',
            highlight: null,
        },
    ],

    // ── Lifecycle ────────────────────────────────────────────

    /**
     * Initialize the tutorial system. Checks store for completion flag.
     * @param {STS2App} app
     */
    init(app) {
        this._app = app;

        // Auto-start on first visit
        const completed = app.store.get('tutorial_completed', false);
        if (!completed) {
            // Delay to let the UI render first
            setTimeout(() => this.show(), 1000);
        }
    },

    /**
     * Show the tutorial overlay starting from the first step (or current step).
     */
    show() {
        if (this.isActive) return;

        this.isActive = true;
        this.currentStep = 0;

        this._createOverlay();
        this._createDialog();
        this.renderStep(this.steps[this.currentStep]);

        // Animate in
        requestAnimationFrame(() => {
            if (this._overlay) this._overlay.classList.add('open');
            if (this._dialog) this._dialog.classList.add('open');
        });
    },

    /**
     * Hide and destroy the tutorial overlay.
     */
    hide() {
        if (!this.isActive) return;

        this.isActive = false;

        // Mark as completed
        if (this._app) {
            this._app.store.set('tutorial_completed', true);
            this._app.notifications.show(
                this._t('tutorial_completed'),
                'success',
                3000
            );
        }

        // Animate out
        if (this._overlay) this._overlay.classList.remove('open');
        if (this._dialog) this._dialog.classList.remove('open');

        setTimeout(() => {
            if (this._overlay) {
                this._overlay.remove();
                this._overlay = null;
            }
            if (this._dialog) {
                this._dialog.remove();
                this._dialog = null;
            }
        }, 300);
    },

    /**
     * Advance to the next step.
     */
    next() {
        if (this.currentStep >= this.steps.length - 1) {
            this.hide();
            return;
        }
        this.currentStep++;
        this.renderStep(this.steps[this.currentStep]);
    },

    /**
     * Go back to the previous step.
     */
    prev() {
        if (this.currentStep <= 0) return;
        this.currentStep--;
        this.renderStep(this.steps[this.currentStep]);
    },

    /**
     * Jump to a specific step index.
     * @param {number} n
     */
    goToStep(n) {
        if (n < 0 || n >= this.steps.length) return;
        this.currentStep = n;
        this.renderStep(this.steps[this.currentStep]);
    },

    // ── Rendering ────────────────────────────────────────────

    /**
     * Render a single tutorial step: update dialog content and highlight.
     * @param {object} step
     */
    renderStep(step) {
        if (!step || !this._dialog) return;

        const t = (key) => this._app.i18n.translate(key);
        const title = t(step.title_key);
        const content = t(step.content_key);

        // Update title
        const titleEl = this._dialog.querySelector('.tutorial-title');
        if (titleEl) titleEl.textContent = title;

        // Update content (preserve line breaks)
        const contentEl = this._dialog.querySelector('.tutorial-content');
        if (contentEl) {
            contentEl.innerHTML = STS2Utils.escapeHtml(content).replace(/\n/g, '<br>');
        }

        // Update step counter
        const stepEl = this._dialog.querySelector('.tutorial-step-counter');
        if (stepEl) {
            stepEl.textContent = this._t_fmt('tutorial_step', [this.currentStep + 1]);
        }

        // Update progress dots
        this._updateProgressDots();

        // Update button states
        this._updateButtons();

        // Update highlight
        this.renderOverlay(step.highlight);
    },

    /**
     * Render the highlight overlay around the target element.
     * @param {string|null} selector - CSS selector of element to highlight
     */
    renderOverlay(selector) {
        if (!this._overlay) return;

        const highlightEl = this._overlay.querySelector('.tutorial-highlight');
        if (!highlightEl) return;

        if (!selector) {
            // No highlight - just dark overlay
            highlightEl.style.display = 'none';
            return;
        }

        const target = document.querySelector(selector);
        if (!target) {
            highlightEl.style.display = 'none';
            return;
        }

        // Ensure the target page is visible
        const page = target.closest('.page');
        if (page && !page.classList.contains('active')) {
            // Navigate to this page
            const tabName = page.id.replace('page-', '');
            if (this._app.router) {
                this._app.router.navigateTo(tabName, false);
            }
        }

        const rect = target.getBoundingClientRect();
        const padding = 8;

        highlightEl.style.display = 'block';
        highlightEl.style.top = (rect.top - padding) + 'px';
        highlightEl.style.left = (rect.left - padding) + 'px';
        highlightEl.style.width = (rect.width + padding * 2) + 'px';
        highlightEl.style.height = (rect.height + padding * 2) + 'px';
    },

    // ── DOM Creation ─────────────────────────────────────────

    /**
     * Create the full-screen overlay with dark background.
     * @private
     */
    _createOverlay() {
        const overlay = document.createElement('div');
        overlay.className = 'tutorial-overlay';
        overlay.style.cssText = `
            position: fixed;
            inset: 0;
            background-color: rgba(0, 0, 0, 0.65);
            z-index: 9000;
            opacity: 0;
            transition: opacity 0.3s ease;
        `;

        // Highlight cutout (box-shadow creates the "hole" effect)
        const highlight = document.createElement('div');
        highlight.className = 'tutorial-highlight';
        highlight.style.cssText = `
            position: fixed;
            border-radius: var(--radius-lg);
            box-shadow: 0 0 0 9999px rgba(0, 0, 0, 0.65);
            z-index: 9001;
            pointer-events: none;
            transition: all 0.35s cubic-bezier(0.34, 1.56, 0.64, 1);
            display: none;
        `;

        overlay.appendChild(highlight);
        document.body.appendChild(overlay);
        this._overlay = overlay;

        // Add open class handling
        overlay.classList.add('open');
    },

    /**
     * Create the tutorial dialog with step content and navigation.
     * @private
     */
    _createDialog() {
        const dialog = document.createElement('div');
        dialog.className = 'tutorial-dialog';
        dialog.style.cssText = `
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%) scale(0.92);
            background-color: var(--bg-light);
            border: 1px solid var(--border);
            border-radius: var(--radius-xl);
            box-shadow: var(--shadow-xl);
            max-width: 480px;
            width: calc(100% - 40px);
            z-index: 9002;
            opacity: 0;
            transition: opacity 0.3s ease, transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
            overflow: hidden;
            display: flex;
            flex-direction: column;
        `;

        dialog.innerHTML = `
            <!-- Header -->
            <div style="
                display: flex;
                align-items: center;
                justify-content: space-between;
                padding: 16px 20px;
                border-bottom: 1px solid var(--border);
            ">
                <div style="display:flex;align-items:center;gap:8px">
                    <span class="tutorial-step-counter"
                          style="font-size:var(--font-xs);color:var(--accent);font-weight:600"></span>
                    <h3 class="tutorial-title"
                        style="font-size:var(--font-lg);font-weight:700;color:var(--text-primary);margin:0"></h3>
                </div>
                <button class="tutorial-skip" style="
                    background: none;
                    border: 1px solid var(--border);
                    border-radius: var(--radius-md);
                    padding: 4px 12px;
                    font-size: var(--font-xs);
                    color: var(--text-secondary);
                    cursor: pointer;
                    transition: background-color 0.12s ease, color 0.12s ease;
                ">${this._t('tutorial_skip')}</button>
            </div>

            <!-- Body -->
            <div style="
                padding: 20px;
                flex: 1;
                min-height: 120px;
            ">
                <div class="tutorial-content"
                     style="font-size:var(--font-sm);color:var(--text-primary);line-height:1.7"></div>
            </div>

            <!-- Progress dots -->
            <div class="tutorial-dots" style="
                display: flex;
                justify-content: center;
                gap: 6px;
                padding: 0 20px 12px;
            "></div>

            <!-- Footer with navigation -->
            <div style="
                display: flex;
                align-items: center;
                justify-content: space-between;
                padding: 12px 20px;
                border-top: 1px solid var(--border);
            ">
                <button class="tutorial-prev" style="
                    background: none;
                    border: 1px solid var(--border);
                    border-radius: var(--radius-md);
                    padding: 6px 16px;
                    font-size: var(--font-sm);
                    color: var(--text-secondary);
                    cursor: pointer;
                    transition: background-color 0.12s ease, border-color 0.12s ease;
                    opacity: 0.4;
                ">${this._t('tutorial_prev')}</button>
                <button class="tutorial-next" style="
                    background-color: var(--accent);
                    border: none;
                    border-radius: var(--radius-md);
                    padding: 6px 20px;
                    font-size: var(--font-sm);
                    font-weight: 600;
                    color: #fff;
                    cursor: pointer;
                    transition: background-color 0.12s ease, box-shadow 0.12s ease;
                    box-shadow: 0 0 8px var(--accent-glow);
                ">${this._t('tutorial_next')}</button>
            </div>
        `;

        document.body.appendChild(dialog);
        this._dialog = dialog;

        // Bind events
        const skipBtn = dialog.querySelector('.tutorial-skip');
        const prevBtn = dialog.querySelector('.tutorial-prev');
        const nextBtn = dialog.querySelector('.tutorial-next');

        if (skipBtn) {
            skipBtn.addEventListener('click', () => this.hide());
            // Hover effects
            skipBtn.addEventListener('mouseenter', () => {
                skipBtn.style.backgroundColor = 'var(--bg-surface)';
                skipBtn.style.color = 'var(--text-primary)';
            });
            skipBtn.addEventListener('mouseleave', () => {
                skipBtn.style.backgroundColor = 'transparent';
                skipBtn.style.color = 'var(--text-secondary)';
            });
        }

        if (prevBtn) {
            prevBtn.addEventListener('click', () => this.prev());
            prevBtn.addEventListener('mouseenter', () => {
                prevBtn.style.backgroundColor = 'var(--bg-surface)';
                prevBtn.style.borderColor = 'var(--border-hover)';
            });
            prevBtn.addEventListener('mouseleave', () => {
                prevBtn.style.backgroundColor = 'transparent';
                prevBtn.style.borderColor = 'var(--border)';
            });
        }

        if (nextBtn) {
            nextBtn.addEventListener('click', () => this.next());
            nextBtn.addEventListener('mouseenter', () => {
                nextBtn.style.backgroundColor = '#7ecbf7';
                nextBtn.style.boxShadow = '0 0 16px var(--accent-glow)';
            });
            nextBtn.addEventListener('mouseleave', () => {
                nextBtn.style.backgroundColor = 'var(--accent)';
                nextBtn.style.boxShadow = '0 0 8px var(--accent-glow)';
            });
        }

        // ESC to close
        this._escHandler = (e) => {
            if (e.key === 'Escape') this.hide();
        };
        document.addEventListener('keydown', this._escHandler);

        // Animate open
        requestAnimationFrame(() => {
            dialog.style.opacity = '1';
            dialog.style.transform = 'translate(-50%, -50%) scale(1)';
        });

        // Build progress dots
        this._buildProgressDots();
    },

    // ── Progress Dots ────────────────────────────────────────

    /**
     * Build the progress dot indicators.
     * @private
     */
    _buildProgressDots() {
        const dotsContainer = this._dialog.querySelector('.tutorial-dots');
        if (!dotsContainer) return;

        dotsContainer.innerHTML = '';
        this.steps.forEach((_, i) => {
            const dot = document.createElement('div');
            dot.className = 'tutorial-dot';
            dot.style.cssText = `
                width: 8px;
                height: 8px;
                border-radius: var(--radius-circle);
                background-color: ${i === this.currentStep ? 'var(--accent)' : 'var(--border)'};
                transition: background-color 0.2s ease, transform 0.2s ease;
                cursor: pointer;
                ${i === this.currentStep ? 'transform: scale(1.2);' : ''}
            `;
            dot.addEventListener('click', () => this.goToStep(i));
            dotsContainer.appendChild(dot);
        });
    },

    /**
     * Update progress dots to reflect current step.
     * @private
     */
    _updateProgressDots() {
        const dots = this._dialog.querySelectorAll('.tutorial-dot');
        dots.forEach((dot, i) => {
            dot.style.backgroundColor = i === this.currentStep
                ? 'var(--accent)'
                : 'var(--border)';
            dot.style.transform = i === this.currentStep
                ? 'scale(1.2)'
                : 'scale(1)';
        });
    },

    // ── Button State ─────────────────────────────────────────

    /**
     * Update prev/next button states based on current step.
     * @private
     */
    _updateButtons() {
        if (!this._dialog) return;

        const prevBtn = this._dialog.querySelector('.tutorial-prev');
        const nextBtn = this._dialog.querySelector('.tutorial-next');

        // Previous button: disabled on first step
        if (prevBtn) {
            const isFirst = this.currentStep === 0;
            prevBtn.style.opacity = isFirst ? '0.4' : '1';
            prevBtn.style.pointerEvents = isFirst ? 'none' : 'auto';
        }

        // Next button: "Finish" on last step
        if (nextBtn) {
            const isLast = this.currentStep === this.steps.length - 1;
            nextBtn.textContent = isLast
                ? this._t('tutorial_finish')
                : this._t('tutorial_next');
        }
    },

    // ── Cleanup ──────────────────────────────────────────────

    /**
     * Destroy the tutorial system and clean up event listeners.
     */
    destroy() {
        if (this._escHandler) {
            document.removeEventListener('keydown', this._escHandler);
            this._escHandler = null;
        }
        if (this._overlay) {
            this._overlay.remove();
            this._overlay = null;
        }
        if (this._dialog) {
            this._dialog.remove();
            this._dialog = null;
        }
        this.isActive = false;
    },

    // ── Helpers ──────────────────────────────────────────────

    /**
     * Translate shortcut.
     * @param {string} key
     * @returns {string}
     * @private
     */
    _t(key) {
        return this._app.i18n.translate(key);
    },

    /**
     * Translate with format arguments.
     * @param {string} key
     * @param {Array} args
     * @returns {string}
     * @private
     */
    _t_fmt(key, args) {
        return this._app.i18n.translate_fmt(key, args);
    },
};
