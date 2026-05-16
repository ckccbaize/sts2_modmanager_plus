/**
 * STS2Utils - Utility functions
 *
 * A collection of pure helper functions used across the application.
 * All functions are static; the object serves as a namespace.
 */
const STS2Utils = {

    // ── Date / Time ───────────────────────────────────────────

    /**
     * Format a date string (or Date object) to "YYYY-MM-DD HH:mm".
     * @param {string|Date} dateStr
     * @returns {string}
     */
    formatDate(dateStr) {
        if (!dateStr) return '';
        const d = dateStr instanceof Date ? dateStr : new Date(dateStr);
        if (isNaN(d.getTime())) return String(dateStr);

        const pad = (n) => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
    },

    /**
     * Format a timestamp (ms) to a relative "time ago" string.
     * @param {string|Date} dateStr
     * @returns {string}
     */
    timeAgo(dateStr) {
        if (!dateStr) return '';
        const d = dateStr instanceof Date ? dateStr : new Date(dateStr);
        const now = Date.now();
        const diff = now - d.getTime();

        const seconds = Math.floor(diff / 1000);
        if (seconds < 60)  return `${seconds}s ago`;
        const minutes = Math.floor(seconds / 60);
        if (minutes < 60)  return `${minutes}m ago`;
        const hours = Math.floor(minutes / 60);
        if (hours < 24)    return `${hours}h ago`;
        const days = Math.floor(hours / 24);
        if (days < 30)     return `${days}d ago`;
        const months = Math.floor(days / 30);
        if (months < 12)   return `${months}mo ago`;
        return `${Math.floor(months / 12)}y ago`;
    },

    // ── File size ──────────────────────────────────────────────

    /**
     * Format bytes into a human-readable string.
     * @param {number} bytes
     * @returns {string} e.g. "1.23 MB"
     */
    formatSize(bytes) {
        if (bytes === 0) return '0 B';
        if (bytes == null || bytes < 0) return '--';

        const units = ['B', 'KB', 'MB', 'GB', 'TB'];
        const k = 1024;
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        const idx = Math.min(i, units.length - 1);
        const value = bytes / Math.pow(k, idx);

        // Use no decimals for bytes/KB, 2 decimals otherwise
        if (idx <= 1) return `${Math.round(value)} ${units[idx]}`;
        return `${value.toFixed(2)} ${units[idx]}`;
    },

    // ── Function helpers ───────────────────────────────────────

    /**
     * Create a debounced version of a function.
     * @param {function} fn
     * @param {number} delay - milliseconds
     * @returns {function}
     */
    debounce(fn, delay) {
        let timer = null;
        return function (...args) {
            if (timer) clearTimeout(timer);
            timer = setTimeout(() => {
                fn.apply(this, args);
                timer = null;
            }, delay);
        };
    },

    /**
     * Create a throttled version of a function.
     * @param {function} fn
     * @param {number} limit - milliseconds
     * @returns {function}
     */
    throttle(fn, limit) {
        let inThrottle = false;
        return function (...args) {
            if (!inThrottle) {
                fn.apply(this, args);
                inThrottle = true;
                setTimeout(() => { inThrottle = false; }, limit);
            }
        };
    },

    // ── ID generation ──────────────────────────────────────────

    /**
     * Generate a short random ID (8 hex characters).
     * @returns {string}
     */
    generateId() {
        return Math.random().toString(36).slice(2, 10);
    },

    /**
     * Generate a longer UUID-like ID.
     * @returns {string}
     */
    uuid() {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
            const r = (Math.random() * 16) | 0;
            const v = c === 'x' ? r : (r & 0x3) | 0x8;
            return v.toString(16);
        });
    },

    // ── String helpers ─────────────────────────────────────────

    /**
     * Escape HTML special characters to prevent XSS.
     * @param {string} str
     * @returns {string}
     */
    escapeHtml(str) {
        if (!str) return '';
        const map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' };
        return String(str).replace(/[&<>"']/g, c => map[c]);
    },

    /**
     * Truncate a string to a maximum length, appending "..." if truncated.
     * @param {string} str
     * @param {number} maxLen
     * @returns {string}
     */
    truncate(str, maxLen = 100) {
        if (!str || str.length <= maxLen) return str || '';
        return str.slice(0, maxLen - 3) + '...';
    },

    // ── Object / Array helpers ─────────────────────────────────

    /**
     * Deep clone an object using structured clone (or JSON fallback).
     * @param {*} obj
     * @returns {*}
     */
    deepClone(obj) {
        if (obj === null || typeof obj !== 'object') return obj;
        try {
            return structuredClone(obj);
        } catch {
            // Fallback for environments without structuredClone
            return JSON.parse(JSON.stringify(obj));
        }
    },

    /**
     * Compare two values for shallow equality (works for primitives and plain objects).
     * @param {*} a
     * @param {*} b
     * @returns {boolean}
     */
    shallowEqual(a, b) {
        if (a === b) return true;
        if (a == null || b == null) return false;
        if (typeof a !== 'object' || typeof b !== 'object') return false;
        const keysA = Object.keys(a);
        const keysB = Object.keys(b);
        if (keysA.length !== keysB.length) return false;
        return keysA.every(k => a[k] === b[k]);
    },

    // ── DOM helpers ────────────────────────────────────────────

    /**
     * Create a DOM element with optional class, attributes, and children.
     *
     * @param {string} tag
     * @param {string|string[]} [className]
     * @param {object} [attrs] - attribute map; special keys: 'text', 'html', 'children', 'style', 'events'
     * @returns {HTMLElement}
     */
    createElement(tag, className, attrs = {}) {
        const el = document.createElement(tag);

        // Class name(s)
        if (className) {
            if (Array.isArray(className)) {
                el.className = className.join(' ');
            } else {
                el.className = className;
            }
        }

        // Attributes and special properties
        for (const [key, value] of Object.entries(attrs)) {
            if (key === 'text') {
                el.textContent = value;
            } else if (key === 'html') {
                el.innerHTML = value;
            } else if (key === 'children' && Array.isArray(value)) {
                value.forEach(child => {
                    if (child instanceof Node) el.appendChild(child);
                    else if (typeof child === 'string') el.appendChild(document.createTextNode(child));
                });
            } else if (key === 'style' && typeof value === 'object') {
                Object.assign(el.style, value);
            } else if (key === 'events' && typeof value === 'object') {
                for (const [evt, handler] of Object.entries(value)) {
                    el.addEventListener(evt, handler);
                }
            } else if (key === 'dataset' && typeof value === 'object') {
                for (const [ds, dsVal] of Object.entries(value)) {
                    el.dataset[ds] = dsVal;
                }
            } else {
                el.setAttribute(key, value);
            }
        }

        return el;
    },

    /**
     * Query a single element; returns null instead of throwing.
     * @param {string} selector
     * @param {Element} [root=document]
     * @returns {Element|null}
     */
    $(selector, root = document) {
        return root.querySelector(selector);
    },

    /**
     * Query all matching elements as an array.
     * @param {string} selector
     * @param {Element} [root=document]
     * @returns {Element[]}
     */
    $$(selector, root = document) {
        return Array.from(root.querySelectorAll(selector));
    },

    // ── Color helpers ──────────────────────────────────────────

    /**
     * Convert a hex color string to rgba with the given alpha.
     * @param {string} hex - e.g. "#ff0000" or "#f00"
     * @param {number} alpha - 0..1
     * @returns {string} rgba(...) string
     */
    hexToRgba(hex, alpha = 1) {
        const clean = hex.replace('#', '');
        const full = clean.length === 3
            ? clean.split('').map(c => c + c).join('')
            : clean;
        const r = parseInt(full.slice(0, 2), 16);
        const g = parseInt(full.slice(2, 4), 16);
        const b = parseInt(full.slice(4, 6), 16);
        return `rgba(${r}, ${g}, ${b}, ${alpha})`;
    },
};

// ── Export ─────────────────────────────────────────────────────
window.STS2Utils = STS2Utils;
