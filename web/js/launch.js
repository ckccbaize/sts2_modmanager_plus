/**
 * STS2Launch - Tesla-style horizontal gear selector for the footer
 *
 * Layout: R (Vanilla) - N (Neutral/Start) - D (Modded) - P (Multiplayer)
 * N starts at center (index 1, 88px from track left edge)
 */
window.STS2Launch = {

    // ── Constants ────────────────────────────────────────────────
    NEUTRAL_COLOR:    '#16232e',
    NEUTRAL_BORDER:    'rgba(102, 192, 249, 0.3)',
    NEUTRAL_SHADOW:    'rgba(102, 192, 249, 0.15)',
    TRACK_WIDTH:       216,   // 248 - 2*16 padding
    TRACK_PADDING:     16,    // left/right padding
    KNOB_W:            30,   // knob width
    N_SNAP_THRESHOLD:  40,    // px: snap back to N if released within this range

    // Gear pixel centers from trackContainer left edge
    // Order: R(0), N(1), D(2), P(3)
    GEAR_POSITIONS: { R: 16, N: 88, D: 160, P: 232 },

    // Gear detection threshold - only detect when cursor is within this range of gear center
    GEAR_DETECT_THRESHOLD: 20,  // px: must be within 20px of gear center to detect

    // ── State ────────────────────────────────────────────────────
    current_gear: 'N',
    isDragging: false,
    _app: null,
    _trackFillEl: null,
    _knobEl: null,
    _statusEl: null,
    _launching: false,
    _dragSnapTimer: null,
    _snapTimeoutActive: false,
    _lastVisualGear: null,

    gears: [
        { id: 'R', label: 'R', color: '#f472b6', mode: 'vanilla',     desc_zh: '\u539f\u7248\u6a21\u5f0f', desc_en: 'Vanilla' },
        { id: 'N', label: 'N', color: '#10b981', mode: 'idle',        desc_zh: '\u7a7a\u6863',              desc_en: 'Neutral' },
        { id: 'D', label: 'D', color: '#66c0f9', mode: 'modded',      desc_zh: '\u6a21\u7ec4\u6a21\u5f0f', desc_en: 'Modded' },
        { id: 'P', label: 'P', color: '#fbbf24', mode: 'multiplayer', desc_zh: '\u8054\u673a\u6a21\u5f0f', desc_en: 'Multiplayer' },
    ],

    // ── Lifecycle ────────────────────────────────────────────────

    init(app) {
        this._app = app;
        this.render();
    },

    render() {
        const area = document.getElementById('launch-area');
        if (!area) return;

        area.innerHTML = '';
        area.style.cssText = 'display:flex;align-items:center;justify-content:center;position:relative;gap:10px;';

        // ── Track container: fixed 248px wide ──────────────────
        const track = document.createElement('div');
        track.id = 'launch-track-container';
        track.style.cssText = 'position:relative;width:248px;height:32px;display:flex;align-items:center;flex-shrink:0;';
        this._trackEl = track;

        // Background line
        const bg = document.createElement('div');
        bg.style.cssText = 'position:absolute;left:16px;right:16px;height:2px;background:rgba(86,131,172,0.2);border-radius:99px;top:50%;transform:translateY(-50%);pointer-events:none;';
        track.appendChild(bg);

        // Active fill
        const fill = document.createElement('div');
        fill.style.cssText = 'position:absolute;left:16px;height:2px;top:50%;transform:translateY(-50%);background:linear-gradient(90deg,var(--accent-dark),var(--accent));border-radius:99px;pointer-events:none;transition:width 0.25s cubic-bezier(0.34,1.56,0.64,1);';
        this._trackFillEl = fill;
        track.appendChild(fill);

        // ── Gear labels ─────────────────────────────────────────
        this.gears.forEach((gear) => {
            const pos = this.GEAR_POSITIONS[gear.id];  // center of gear
            const label = document.createElement('div');
            label.className = 'launch-gear-label';
            label.dataset.gear = gear.id;
            const isN = gear.id === 'N';

            // left = gear center - half label width
            label.style.cssText = `position:absolute;left:${pos-14}px;width:28px;height:28px;top:50%;transform:translateY(-50%);display:flex;align-items:center;justify-content:center;font-size:var(--font-sm);font-weight:var(--weight-bold);color:${isN?gear.color:'rgba(255,255,255,0.25)'};background:${isN?gear.color+'18':'transparent'};border-radius:50%;cursor:pointer;user-select:none;transition:color 0.15s,background 0.15s,transform 0.15s;z-index:1;`;
            label.textContent = gear.label;

            label.addEventListener('click', (e) => {
                e.stopPropagation();
                if (!this._launching) this.snapToGear(gear.id, true);
            });
            label.addEventListener('mouseenter', () => {
                if (gear.id !== this.current_gear) {
                    label.style.color = gear.color;
                    label.style.background = gear.color + '15';
                    label.style.transform = 'translateY(-50%) scale(1.12)';
                }
            });
            label.addEventListener('mouseleave', () => {
                const isActive = gear.id === this.current_gear;
                label.style.color = isActive ? gear.color : 'rgba(255,255,255,0.25)';
                label.style.background = isActive ? gear.color + '18' : 'transparent';
                label.style.transform = 'translateY(-50%) scale(1)';
            });

            track.appendChild(label);
        });

        // ── Knob: starts at N (88px from track left) ────────────
        const knob = document.createElement('div');
        knob.className = 'launch-knob';
        this._knobEl = knob;

        // Use KNOB_W constant for centering: knob left = gearCenter - KNOB_W/2
        const nCenter = this.GEAR_POSITIONS['N'];  // 88
        const knobLeft = nCenter - this.KNOB_W / 2; // 88 - 15 = 73

        this._applyKnobStyle('N', false);
        // Set both left (fallback) and a data attribute for verification
        knob.style.cssText = `position:absolute;left:${knobLeft}px;top:50%;transform:translateY(-50%);width:30px;height:28px;border-radius:6px;background-color:${this.NEUTRAL_COLOR};border:1px solid ${this.NEUTRAL_BORDER};box-shadow:0 0 6px ${this.NEUTRAL_SHADOW};cursor:grab;user-select:none;z-index:2;`;
        knob.dataset.gearCenter = nCenter;

        track.appendChild(knob);
        area.appendChild(track);

        // ── Status text ──────────────────────────────────────────
        const status = document.createElement('div');
        status.className = 'launch-status';
        status.style.cssText = 'font-size:10px;line-height:1;white-space:nowrap;pointer-events:none;flex-shrink:0;min-width:100px;color:rgba(255,255,255,0.35);transition:color 0.2s;';
        this._statusEl = status;
        this._applyStatusText('N');
        area.appendChild(status);

        // Bind drag events
        this._bindDragEvents(knob, track);

        // Initial state
        this._lastVisualGear = 'N';
        this._applyGearVisuals('N');
        this._updateTrackFill('N');
    },

    // ── Drag Events ───────────────────────────────────────────────

    _bindDragEvents(knob, track) {
        this._onMoveBound = (e) => this._onMove(e);
        this._onUpBound = (e) => this._onUp(e);
        knob.addEventListener('mousedown',  (e) => this._onDown(e));
        knob.addEventListener('touchstart', (e) => this._onDown(e), { passive: false });
        document.addEventListener('mousemove', this._onMoveBound);
        document.addEventListener('mouseup', this._onUpBound);
        document.addEventListener('touchmove', this._onMoveBound, { passive: false });
        document.addEventListener('touchend', this._onUpBound);
    },

    _onDown(e) {
        if (this._launching) return;
        e.preventDefault();
        this.isDragging = true;
        this._knobEl.style.transition = 'none';
        this._knobEl.style.cursor = 'grabbing';
        this._cancelSnap();
    },

    _onMove(e) {
        if (!this.isDragging) return;
        e.preventDefault();

        const track = this._knobEl.parentElement;
        if (!track) return;

        const rect = track.getBoundingClientRect();
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const x = clientX - rect.left;

        // Clamp within track
        const left = 16;
        const right = 248 - 16;
        const cx = Math.max(left, Math.min(right, x));

        // Move knob: knob left = cx - KNOB_W/2 (center on cursor)
        const knobLeft = cx - this.KNOB_W / 2;
        this._knobEl.style.left = knobLeft + 'px';

        // Detect gear by cursor position
        const nearest = this._detectGear(cx);

        if (nearest !== this._lastVisualGear) {
            this._lastVisualGear = nearest;
            this._applyGearVisuals(nearest);
            this._applyKnobStyle(nearest, false);
            this._applyStatusText(nearest);
        }
    },

    _onUp(e) {
        if (!this.isDragging) return;
        this.isDragging = false;
        this._knobEl.style.cursor = 'grab';
        this._knobEl.style.transition = '';

        const knobLeft = parseFloat(this._knobEl.style.left) || 0;
        const knobCenter = knobLeft + this.KNOB_W / 2;
        const gearId = this._resolveSnap(knobCenter);
        this.snapToGear(gearId, true);
    },

    // ── Gear Detection ────────────────────────────────────────────

    _detectGear(trackX) {
        // Only detect gear when cursor is within threshold of a gear center
        // Otherwise return current gear to avoid flickering between distant gears
        let nearest = this.current_gear || 'N';
        let minDist = Infinity;
        for (const [id, pos] of Object.entries(this.GEAR_POSITIONS)) {
            const d = Math.abs(trackX - pos);
            if (d < minDist) { minDist = d; nearest = id; }
        }
        // Only return nearest if within threshold, otherwise stay at current
        if (minDist <= this.GEAR_DETECT_THRESHOLD) {
            return nearest;
        }
        return this._lastVisualGear || this.current_gear || 'N';
    },

    _resolveSnap(trackX) {
        // If close to N, snap back
        const nDist = Math.abs(trackX - this.GEAR_POSITIONS['N']);
        if (nDist <= this.N_SNAP_THRESHOLD) return 'N';
        return this._detectGear(trackX);
    },

    // ── Snap & Launch ─────────────────────────────────────────────

    snapToGear(gearId, autoLaunch = false) {
        const gear = this.gears.find(g => g.id === gearId);
        if (!gear) return;

        this._cancelSnap();
        this.current_gear = gearId;
        this._lastVisualGear = gearId;

        const center = this.GEAR_POSITIONS[gearId];
        const knobLeft = center - this.KNOB_W / 2;

        // Animate to target
        this._knobEl.style.transition = 'left 0.35s cubic-bezier(0.34,1.56,0.64,1),background-color 0.25s,box-shadow 0.25s,border-color 0.25s';
        this._knobEl.style.left = knobLeft + 'px';
        this._knobEl.dataset.gearCenter = center;

        this._applyKnobStyle(gearId, true);
        this._applyGearVisuals(gearId);
        this._applyStatusText(gearId);
        this._updateTrackFill(gearId);

        if (autoLaunch && gear.mode !== 'idle' && !this._launching) {
            this._snapTimeoutActive = true;
            this._dragSnapTimer = setTimeout(() => {
                this._snapTimeoutActive = false;
                if (this.current_gear === gearId && !this.isDragging && !this._launching) {
                    this.launchGame(gear.mode);
                }
            }, 500);
        }
    },

    // ── Launch ────────────────────────────────────────────────────

    async launchGame(mode) {
        if (this._launching) return;
        this._launching = true;

        const labels = {
            vanilla:     { zh: '\u539f\u7248\u6a21\u5f0f', en: 'Vanilla' },
            modded:      { zh: '\u6a21\u7ec4\u6a21\u5f0f', en: 'Modded' },
            multiplayer: { zh: '\u8054\u673a\u6a21\u5f0f', en: 'Multiplayer' },
        };

        const lang = (this._app && this._app.i18n) ? this._app.i18n.getCurrentLanguage() : 'zh_CN';
        const isZh = lang !== 'en_US';
        const t = (k) => this._app && this._app.i18n ? this._app.i18n.translate(k) : k;

        const lbl = labels[mode];
        const desc = lbl ? (isZh ? lbl.zh : lbl.en) : '';

        this._statusEl.textContent = (t('launching') || '\u6b63\u5728\u542f\u52a8') + ' ' + desc;
        this._statusEl.style.color = '#66c0f9';

        if (this._app && this._app.notifications) {
            this._app.notifications.show(t('launching_game') || '\u6b63\u5728\u542f\u52a8\u6e38\u6232...', 'info', 3000);
        }

        this._app && this._app.emit('launch-mode-pressed', mode);

        if (this._app && this._app.api && this._app.isBackendConnected()) {
            try { await this._app.api.launchGame(mode); }
            catch (e) { console.warn('[STS2Launch] API launchGame failed:', e); }
        }

        setTimeout(() => {
            this._launching = false;
            this.snapToGear('N', false);
        }, 3000);
    },

    // ── Visual Helpers ────────────────────────────────────────────

    _applyKnobStyle(gearId, animate) {
        const gear = this.gears.find(g => g.id === gearId);
        const isN = gearId === 'N';

        if (!isN && gear) {
            this._knobEl.style.backgroundColor = gear.color;
            this._knobEl.style.borderColor = gear.color + '88';
            this._knobEl.style.boxShadow = '0 0 16px ' + gear.color + '66';
        } else {
            this._knobEl.style.backgroundColor = this.NEUTRAL_COLOR;
            this._knobEl.style.borderColor = this.NEUTRAL_BORDER;
            this._knobEl.style.boxShadow = '0 0 6px ' + this.NEUTRAL_SHADOW;
        }
    },

    _applyGearVisuals(gearId) {
        document.querySelectorAll('.launch-gear-label').forEach(label => {
            const gear = this.gears.find(g => g.id === label.dataset.gear);
            if (!gear) return;
            const is = gear.id === gearId;
            label.style.color = is ? gear.color : 'rgba(255,255,255,0.25)';
            label.style.background = is ? gear.color + '22' : 'transparent';
            label.style.transform = is ? 'translateY(-50%) scale(1.12)' : 'translateY(-50%) scale(1)';
        });
    },

    _applyStatusText(gearId) {
        if (!this._statusEl) return;
        const gear = this.gears.find(g => g.id === gearId);
        if (!gear) return;

        const isN = gearId === 'N';
        const lang = (this._app && this._app.i18n) ? this._app.i18n.getCurrentLanguage() : 'zh_CN';
        const isZh = lang !== 'en_US';
        const t = (k) => this._app && this._app.i18n ? this._app.i18n.translate(k) : k;

        if (isN) {
            this._statusEl.innerHTML = '<span style="opacity:0.4">\u2190</span> ' + (t('drag_to_launch') || '\u62d6\u62fd\u542f\u52a8');
            this._statusEl.style.color = 'rgba(255,255,255,0.35)';
        } else {
            const desc = isZh ? gear.desc_zh : gear.desc_en;
            this._statusEl.textContent = gear.label + ' \u2014 ' + desc;
            this._statusEl.style.color = gear.color;
        }
    },

    _updateTrackFill(gearId) {
        if (!this._trackFillEl) return;
        const pos = this.GEAR_POSITIONS[gearId];
        if (pos === undefined) return;
        this._trackFillEl.style.width = (pos - this.TRACK_PADDING) + 'px';
    },

    _cancelSnap() {
        if (this._dragSnapTimer) {
            clearTimeout(this._dragSnapTimer);
            this._dragSnapTimer = null;
        }
        this._snapTimeoutActive = false;
    },
};