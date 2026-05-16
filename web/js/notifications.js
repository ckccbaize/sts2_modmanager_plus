/**
 * STS2Notifications - Toast notification system
 *
 * Displays slide-in toasts from the right edge.
 * Max 5 visible at once; overflow is queued and shown as slots free up.
 */
class STS2Notifications {
    /**
     * @param {object} options
     * @param {number} options.maxVisible - max toasts on screen (default 5)
     */
    constructor(options = {}) {
        this._maxVisible = options.maxVisible || 5;
        this._queue = [];
        this._activeToasts = [];

        // Create the toast container (fixed, right-aligned)
        this._container = document.createElement('div');
        this._container.id = 'toast-container';
        Object.assign(this._container.style, {
            position: 'fixed',
            top: '16px',
            right: '16px',
            zIndex: '10000',
            display: 'flex',
            flexDirection: 'column',
            gap: '8px',
            pointerEvents: 'none',
            maxWidth: '380px',
        });
        document.body.appendChild(this._container);

        // Inject animation keyframes once
        if (!document.getElementById('sts2-toast-styles')) {
            const style = document.createElement('style');
            style.id = 'sts2-toast-styles';
            style.textContent = `
                @keyframes sts2-toast-slide-in {
                    from { transform: translateX(110%); opacity: 0; }
                    to   { transform: translateX(0);    opacity: 1; }
                }
                @keyframes sts2-toast-slide-out {
                    from { transform: translateX(0);    opacity: 1; }
                    to   { transform: translateX(110%); opacity: 0; }
                }
                .sts2-toast {
                    display: flex;
                    align-items: center;
                    gap: 10px;
                    padding: 12px 16px;
                    border-radius: 8px;
                    color: #fff;
                    font-size: 14px;
                    font-family: 'Segoe UI', system-ui, sans-serif;
                    box-shadow: 0 4px 16px rgba(0,0,0,0.35);
                    pointer-events: auto;
                    cursor: default;
                    animation: sts2-toast-slide-in 0.35s ease forwards;
                    will-change: transform, opacity;
                    max-width: 360px;
                    word-break: break-word;
                }
                .sts2-toast.toast-exit {
                    animation: sts2-toast-slide-out 0.3s ease forwards;
                }
                .sts2-toast .toast-icon { font-size: 18px; flex-shrink: 0; }
                .sts2-toast .toast-msg  { flex: 1; line-height: 1.4; }
                .sts2-toast .toast-close {
                    flex-shrink: 0;
                    background: none;
                    border: none;
                    color: rgba(255,255,255,0.7);
                    font-size: 16px;
                    cursor: pointer;
                    padding: 0 2px;
                    line-height: 1;
                }
                .sts2-toast .toast-close:hover { color: #fff; }
                .sts2-toast.toast-success { background: linear-gradient(135deg, #2d7d46, #1e5c32); }
                .sts2-toast.toast-error   { background: linear-gradient(135deg, #b33030, #8a2020); }
                .sts2-toast.toast-info    { background: linear-gradient(135deg, #2a6cb8, #1a4e8a); }
                .sts2-toast.toast-warning { background: linear-gradient(135deg, #c07a10, #8a5a0a); }
            `;
            document.head.appendChild(style);
        }
    }

    // ── Public API ─────────────────────────────────────────────

    /**
     * Show a toast notification.
     *
     * @param {string} message       - text to display
     * @param {string} type          - 'success' | 'error' | 'info' | 'warning'
     * @param {number} duration      - ms before auto-dismiss (0 = sticky)
     * @param {function|null} onClick - callback when the toast is clicked
     * @returns {HTMLElement} the toast element
     */
    show(message, type = 'success', duration = 3000, onClick = null) {
        const toast = this._createToastElement(message, type, onClick);

        // If at max capacity, queue it
        if (this._activeToasts.length >= this._maxVisible) {
            this._queue.push({ message, type, duration, onClick });
            return toast;
        }

        this._mountToast(toast, duration);
        return toast;
    }

    // ── Internal ───────────────────────────────────────────────

    /**
     * Build the DOM element for a single toast.
     * @private
     */
    _createToastElement(message, type, onClick) {
        const toast = document.createElement('div');
        toast.className = `sts2-toast toast-${type}`;

        // Icon
        const icon = document.createElement('span');
        icon.className = 'toast-icon';
        icon.textContent = this._iconForType(type);
        toast.appendChild(icon);

        // Message
        const msg = document.createElement('span');
        msg.className = 'toast-msg';
        msg.textContent = message;
        toast.appendChild(msg);

        // Close button
        const closeBtn = document.createElement('button');
        closeBtn.className = 'toast-close';
        closeBtn.textContent = '\u00d7';
        closeBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            this._dismissToast(toast);
        });
        toast.appendChild(closeBtn);

        // Click handler
        if (onClick) {
            toast.style.cursor = 'pointer';
            toast.addEventListener('click', () => onClick());
        }

        return toast;
    }

    /**
     * Mount a toast into the DOM and start its auto-dismiss timer.
     * @private
     */
    _mountToast(toast, duration) {
        this._container.appendChild(toast);
        this._activeToasts.push(toast);

        if (duration > 0) {
            const timerId = setTimeout(() => this._dismissToast(toast), duration);
            toast._timerId = timerId;
        }
    }

    /**
     * Dismiss a toast with slide-out animation, then remove it from the DOM.
     * Processes the queue if there are waiting toasts.
     * @private
     */
    _dismissToast(toast) {
        if (toast._dismissed) return;
        toast._dismissed = true;

        // Clear auto-dismiss timer
        if (toast._timerId) clearTimeout(toast._timerId);

        toast.classList.add('toast-exit');
        toast.addEventListener('animationend', () => {
            toast.remove();
            this._activeToasts = this._activeToasts.filter(t => t !== toast);
            this._processQueue();
        }, { once: true });
    }

    /**
     * Show the next queued toast if there is one and a slot is free.
     * @private
     */
    _processQueue() {
        if (this._queue.length === 0) return;
        if (this._activeToasts.length >= this._maxVisible) return;

        const next = this._queue.shift();
        const toast = this._createToastElement(next.message, next.type, next.onClick);
        this._mountToast(toast, next.duration);
    }

    /**
     * Return an icon character for a notification type.
     * @private
     */
    _iconForType(type) {
        const icons = {
            success: '\u2714',
            error:   '\u2718',
            info:    '\u2139',
            warning: '\u26a0',
        };
        return icons[type] || icons.info;
    }

    /**
     * Dismiss all currently visible toasts immediately.
     */
    clearAll() {
        [...this._activeToasts].forEach(t => this._dismissToast(t));
        this._queue = [];
    }
}

// ── Export ─────────────────────────────────────────────────────
window.STS2Notifications = STS2Notifications;
