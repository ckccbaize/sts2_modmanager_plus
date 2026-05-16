/**
 * STS2Animations - Advanced animation effects for the mod manager
 *
 * Provides particle effects, background animations, and enhanced UI interactions.
 * All effects are GPU-accelerated where possible and respect prefers-reduced-motion.
 */
window.STS2Animations = {
    _particles: [],
    _animFrame: null,
    _reducedMotion: false,

    init(app) {
        this.app = app;
        this._reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (this._reducedMotion) return;

        this._initBackgroundGrid();
        this._initButtonRipple();
        this._initScrollReveal();
        this._initParallax();

        // Re-init on page change
        if (app && app.on) {
            app.on('page-changed', () => {
                requestAnimationFrame(() => this._initScrollReveal());
            });
        }
    },

    // ── Background subtle grid effect ──
    _initBackgroundGrid() {
        const canvas = document.createElement('canvas');
        canvas.id = 'bg-canvas';
        canvas.style.cssText = `
            position: fixed; top: 0; left: 0; width: 100%; height: 100%;
            pointer-events: none; z-index: 0; opacity: 0.03;
        `;
        document.body.prepend(canvas);

        const ctx = canvas.getContext('2d');
        const resize = () => {
            canvas.width = window.innerWidth;
            canvas.height = window.innerHeight;
        };
        resize();
        window.addEventListener('resize', resize);

        const draw = () => {
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            ctx.strokeStyle = '#66c0f9';
            ctx.lineWidth = 0.5;
            const gridSize = 40;
            for (let x = 0; x < canvas.width; x += gridSize) {
                ctx.beginPath();
                ctx.moveTo(x, 0);
                ctx.lineTo(x, canvas.height);
                ctx.stroke();
            }
            for (let y = 0; y < canvas.height; y += gridSize) {
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(canvas.width, y);
                ctx.stroke();
            }
        };
        draw();
        window.addEventListener('resize', draw);
    },

    // ── Button ripple effect ──
    _initButtonRipple() {
        document.addEventListener('click', (e) => {
            const btn = e.target.closest('.btn, .tab-btn, .mode-btn, .tag');
            if (!btn || btn.classList.contains('no-ripple')) return;

            const ripple = document.createElement('span');
            ripple.className = 'ripple-effect';
            const rect = btn.getBoundingClientRect();
            const size = Math.max(rect.width, rect.height);
            const x = e.clientX - rect.left - size / 2;
            const y = e.clientY - rect.top - size / 2;

            ripple.style.cssText = `
                position: absolute; width: ${size}px; height: ${size}px;
                left: ${x}px; top: ${y}px;
                background: rgba(102, 192, 249, 0.3);
                border-radius: 50%; transform: scale(0);
                animation: rippleExpand 0.6s ease-out forwards;
                pointer-events: none; z-index: 1;
            `;

            btn.style.position = btn.style.position || 'relative';
            btn.style.overflow = 'hidden';
            btn.appendChild(ripple);

            setTimeout(() => ripple.remove(), 600);
        });

        // Add ripple keyframes if not exists
        if (!document.getElementById('ripple-styles')) {
            const style = document.createElement('style');
            style.id = 'ripple-styles';
            style.textContent = `
                @keyframes rippleExpand {
                    to { transform: scale(4); opacity: 0; }
                }
            `;
            document.head.appendChild(style);
        }
    },

    // ── Scroll reveal for list items ──
    _initScrollReveal() {
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('revealed');
                    observer.unobserve(entry.target);
                }
            });
        }, { threshold: 0.1, rootMargin: '0px 0px -20px 0px' });

        document.querySelectorAll('.mod-item, .bundle-item, .save-item, .download-item, .nexus-card').forEach(el => {
            if (!el.classList.contains('revealed')) {
                el.style.opacity = '0';
                el.style.transform = 'translateY(12px)';
                el.style.transition = 'opacity 0.3s ease-out, transform 0.3s ease-out';
                observer.observe(el);
            }
        });

        // Add reveal styles
        if (!document.getElementById('reveal-styles')) {
            const style = document.createElement('style');
            style.id = 'reveal-styles';
            style.textContent = `
                .revealed { opacity: 1 !important; transform: translateY(0) !important; }
            `;
            document.head.appendChild(style);
        }
    },

    // ── Subtle parallax on title bar ──
    _initParallax() {
        const titleBar = document.querySelector('.title-bar');
        if (!titleBar) return;

        let ticking = false;
        document.querySelector('.content-area')?.addEventListener('scroll', () => {
            if (ticking) return;
            ticking = true;
            requestAnimationFrame(() => {
                const scroll = document.querySelector('.content-area').scrollTop;
                const opacity = Math.max(0.95, 1 - scroll * 0.001);
                titleBar.style.opacity = opacity;
                ticking = false;
            });
        });
    },

    // ── Loading shimmer for skeleton screens ──
    createSkeleton(count, container) {
        if (!container) return;
        container.innerHTML = '';
        for (let i = 0; i < count; i++) {
            const skel = document.createElement('div');
            skel.className = 'skeleton';
            skel.style.height = '64px';
            skel.style.marginBottom = '6px';
            skel.style.animationDelay = `${i * 0.1}s`;
            container.appendChild(skel);
        }
    },

    // ── Number counter animation ──
    animateNumber(element, from, to, duration = 800) {
        if (!element || this._reducedMotion) {
            if (element) element.textContent = to;
            return;
        }
        const start = performance.now();
        const update = (now) => {
            const elapsed = now - start;
            const progress = Math.min(elapsed / duration, 1);
            const eased = 1 - Math.pow(1 - progress, 3); // ease-out cubic
            const current = Math.round(from + (to - from) * eased);
            element.textContent = current;
            if (progress < 1) requestAnimationFrame(update);
        };
        requestAnimationFrame(update);
    },

    // ── Success/error flash effect ──
    flashElement(element, color = 'success') {
        if (!element || this._reducedMotion) return;
        const colors = {
            success: 'rgba(74, 222, 128, 0.15)',
            error: 'rgba(239, 68, 68, 0.15)',
            info: 'rgba(102, 192, 249, 0.15)',
        };
        element.style.transition = 'box-shadow 0.3s ease-out';
        element.style.boxShadow = `inset 0 0 0 2px ${colors[color] || colors.info}`;
        setTimeout(() => {
            element.style.boxShadow = 'none';
        }, 600);
    },

    // ── Stagger children animation ──
    staggerIn(container, selector = '*', delay = 40) {
        if (!container || this._reducedMotion) return;
        const children = container.querySelectorAll(selector);
        children.forEach((child, i) => {
            child.style.opacity = '0';
            child.style.transform = 'translateY(8px)';
            child.style.transition = `opacity 0.25s ease-out ${i * delay}ms, transform 0.25s ease-out ${i * delay}ms`;
            requestAnimationFrame(() => {
                child.style.opacity = '1';
                child.style.transform = 'translateY(0)';
            });
        });
    },

    // ── Glow pulse for important elements ──
    pulseGlow(element, color = 'var(--accent)') {
        if (!element || this._reducedMotion) return;
        element.style.animation = 'none';
        element.offsetHeight; // force reflow
        element.style.animation = `pulseGlow 1s ease-out`;
        setTimeout(() => { element.style.animation = ''; }, 1000);
    },

    // ── Cleanup ──
    destroy() {
        const canvas = document.getElementById('bg-canvas');
        if (canvas) canvas.remove();
        if (this._animFrame) cancelAnimationFrame(this._animFrame);
    }
};
