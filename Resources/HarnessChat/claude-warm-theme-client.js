window.__ModuleLoader__.load({
  id: '@local/claude-warm-theme',
  factory() {
    const t = (light, dark) => ({ light, dark });

    // Warm paper gray ramp replacing the cool "neutral-bluish" static palette.
    const GRAY = {
      '00': '#ffffff',
      50: '#fbfaf6',
      60: '#f8f6f1',
      75: '#f3f1ea',
      100: '#ece9e1',
      150: '#e7e3d9',
      200: '#ded9cd',
      300: '#cfc9bb',
      400: '#b4aea1',
      500: '#999387',
      600: '#7e786d',
      700: '#645f56',
      750: '#4f4b44',
      800: '#3b3832',
      850: '#2e2b27',
      875: '#25231f',
      900: '#1c1a17',
      950: '#141311',
      1000: '#0d0c0b',
    };
    const NEUTRAL = {
      '00': '#ffffff',
      50: '#faf8f3',
      100: '#f3f0e9',
      150: '#ebe7df',
      200: '#e2ddd3',
      250: '#d7d2c6',
      300: '#ccc6b8',
      400: '#a7a196',
      500: '#8a8479',
      550: '#716c62',
      600: '#5c584f',
      700: '#433f39',
      800: '#2c2a26',
      850: '#242220',
      900: '#141311',
      1000: '#000000',
    };
    // Clay ramp replacing the blue accent ramp.
    const CLAY = {
      50: '#fdf5f1',
      100: '#fae8df',
      200: '#f5d3c3',
      300: '#eeb79e',
      400: '#e2906f',
      450: '#d97757',
      500: '#c4603f',
      600: '#a34e33',
      800: '#673423',
      900: '#47241a',
    };

    const tokens = {
      // ------------------------------------------------------------------
      // Static ramps
      // ------------------------------------------------------------------
      ...Object.fromEntries(Object.entries(GRAY).map(([step, value]) => [`--dsw-static-neutral-bluish-${step}`, t(value, value)])),
      ...Object.fromEntries(Object.entries(NEUTRAL).map(([step, value]) => [`--dsw-static-neutral-${step}`, t(value, value)])),
      ...Object.fromEntries(Object.entries(CLAY).map(([step, value]) => [`--dsw-static-deepseek-${step}`, t(value, value)])),

      // ------------------------------------------------------------------
      // Surfaces
      // ------------------------------------------------------------------
      '--dsw-alias-bg-base': t('#f7f5ef', '#121110'),
      '--dsw-alias-bg-layer-1': t('#fbfaf6', '#191816'),
      '--dsw-alias-bg-layer-2': t('#fdfcf9', '#1f1e1b'),
      '--dsw-alias-bg-layer-3': t('#ffffff', '#272520'),
      '--dsw-alias-bg-overlay': t('#ffffff', '#292722'),
      '--dsw-alias-bg-skeleton': t('#1f1d190f', '#ffffff14'),
      '--dsw-alias-bg-document-preview': t('#fbfaf6', '#161513'),
      '--dsw-alias-bg-document-selection': t('color-mix(in srgb, #d97757 28%, transparent)', 'color-mix(in srgb, #d97757 32%, transparent)'),
      '--dsw-alias-label-document-preview': t('#66615a', '#b9b3a7'),
      '--dsw-alias-bg-module-platform': t('#f1eee6', '#292722'),
      '--dsw-alias-bg-multi-select': t('#f1eee6', '#292722'),

      // ------------------------------------------------------------------
      // Hairline borders
      // ------------------------------------------------------------------
      '--dsw-alias-border-inverted': t('#1f1d1900', '#f5efe600'),
      '--dsw-alias-border-inverted2': t('#1f1d1900', '#f5efe600'),
      '--dsw-alias-border-l1': t('#1f1d190f', '#f5efe60f'),
      '--dsw-alias-border-l2': t('#1f1d191a', '#f5efe61f'),
      '--dsw-alias-border-l2-darkmode-thin': t('#1f1d1912', '#f5efe612'),
      '--dsw-alias-border-l3': t('#1f1d1924', '#f5efe629'),
      '--dsw-alias-border-l4': t('#1f1d1933', '#f5efe63d'),

      // ------------------------------------------------------------------
      // Brand and primary actions: clay instead of ink / blue
      // ------------------------------------------------------------------
      '--dsw-alias-brand-primary': t('#c4603f', '#d97757'),
      '--dsw-alias-brand-primary-invert': t('#1f1d19', '#f5f1e8'),
      '--dsw-alias-brand-primary-new-colorprimary-new-color': t('#c4603f', '#e2906f'),
      '--dsw-alias-brand-text': t('#1f1d19', '#f5f1e8'),
      '--dsw-alias-button-primary-fill': t('#c4603f', '#d97757'),
      '--dsw-alias-button-primary-hover': t('#a34e33', '#e2906f'),
      '--dsw-alias-button-primary-dimmed': t('#f0d8cc', '#4a2e24'),
      '--dsw-alias-button-contrast-fill': t('#2e2b27', '#f0eadf'),
      '--dsw-alias-button-elevated-fill': t('#ffffff', '#2a2823'),
      '--dsw-alias-button-floating-fill': t('#ffffff', '#2b2924'),
      '--dsw-alias-button-floating-hover': t('#f7f5ef', '#34312b'),
      '--dsw-alias-button-ghost-active-border': t('#cfc9bb', '#5c574e'),
      '--dsw-alias-button-ghost-active-fill': t('#f2efe8', '#34312b'),
      '--dsw-alias-button-ghost-active-hover': t('#ece9e1', '#3c3832'),
      '--dsw-alias-button-info-fill': t('#c4603f', '#d97757'),
      '--dsw-alias-button-info-hover': t('#a34e33', '#e2906f'),
      '--dsw-alias-button-tool-bar-fill': t('#54504a80', '#54504a80'),
      '--dsw-alias-button-tool-bar-fill-invisible': t('#1f1c185c', '#1f1c185c'),
      '--dsw-alias-button-tool-bar-hover': t('#54504a99', '#54504a99'),

      // ------------------------------------------------------------------
      // Text
      // ------------------------------------------------------------------
      '--dsw-alias-label-primary': t('#1f1d19', '#f4f0e7'),
      '--dsw-alias-label-primary-bluish': t('#1f1d19', '#f4f0e7'),
      '--dsw-alias-label-primary-dimmed': t('#3b372f', '#e7e1d5'),
      '--dsw-alias-label-primary-inverted': t('#ffffff', '#1a1815'),
      '--dsw-alias-label-secondary': t('#6b665c', '#b9b3a7'),
      '--dsw-alias-label-tertiary': t('#6f695f', '#9a9488'),
      '--dsw-alias-label-caption': t('#746e63', '#8a8478'),
      '--dsw-alias-label-dimmed': t('#d7d2c6', '#4f4b44'),
      '--dsw-alias-label-shimmer': t('rgba(31,29,25,0.3)', 'rgba(255,248,238,0.45)'),
      '--dsw-alias-label-deep-diving': t('color-mix(in srgb, #c4603f 72%, #2a2722)', 'color-mix(in srgb, #d97757 55%, #b4aea1)'),
      '--dsw-alias-label-deep-diving-shimmer': t('color-mix(in srgb, #c4603f 30%, #2a2722)', 'color-mix(in srgb, #e2906f 70%, #b4aea1)'),
      '--dsw-alias-link': t('#a34e33', '#e2906f'),
      '--dsw-alias-menu-icon': t('#4f4b44', '#d8d2c6'),

      // ------------------------------------------------------------------
      // Markdown and code
      // ------------------------------------------------------------------
      '--dsw-alias-markdown-citation': t('#ece9e1', '#2e2b26'),
      '--dsw-alias-markdown-code-block': t('#f3f0e8', '#1d1c19'),
      '--dsw-alias-markdown-code-block-banner': t('#efebe2', '#23211d'),
      '--dsw-alias-markdown-code-segment-selected': t('#ffffff', '#2e2b26'),
      '--dsw-alias-markdown-code-segment-unselected': t('#f7f5ef', '#262420'),
      '--dsw-alias-markdown-inline-code': t('#f1ede4', '#2a2722'),
      '--dsw-alias-markdown-placeholder': t('#e7e2d7', '#2b2823'),
      '--dsw-alias-markdown-tag': t('#ece8de', '#2b2823'),
      '--dsw-alias-turn-trigger-bg': t('#f3f0e8', '#23211d'),
      '--dsw-alias-turn-trigger-bg-hover': t('#ece9e1', '#2b2823'),

      // ------------------------------------------------------------------
      // Menus, popovers, settings, feedback
      // ------------------------------------------------------------------
      '--dsw-menu-surface-fill': t('#fbfaf6', '#2b2924'),
      '--dsw-alias-menu-group-header-fill': t('#fbfaf6', '#2b2924'),
      '--dsw-alias-settings-card-fill': t('#ffffff', '#1f1e1b'),
      '--dsw-alias-settings-card-stroke': t('#1f1d1933', '#f5efe63d'),
      '--dsw-alias-toast-bg': t('#2b2823', '#f0eadf'),
      '--dsw-alias-toast-label': t('#fbf7ef', '#1f1d19'),
      '--dsw-alias-tooltip-bg': t('#35322c', '#2c2924'),
      '--dsw-alias-tooltip-key-bg': t('#4a463f', '#3f3b34'),
      '--dsw-alias-switch-thumb': t('#ffffff', '#f0eadf'),
      '--dsw-alias-onboarding-accent': t('#c4603f', '#d97757'),
      '--dsw-alias-onboarding-card-fill': t('#ffffff', '#1f1e1b'),
      '--dsw-alias-onboarding-checkbox-border': t('#1f1d1933', '#f5efe633'),
      '--dsw-alias-onboarding-secondary-fill': t('#2e2b27', '#f0eadf'),

      // ------------------------------------------------------------------
      // Scrollbars
      // ------------------------------------------------------------------
      '--dsw-alias-scrollbar-bg-l1': t('#d8d2c5', '#3d3a33'),
      '--dsw-alias-scrollbar-bg-l2': t('#d8d2c5', '#3d3a33'),
      '--dsw-alias-scrollbar-hover-l1': t('#c3bcad', '#4a463f'),
      '--dsw-alias-scrollbar-hover-l2': t('#c3bcad', '#4a463f'),

      // ------------------------------------------------------------------
      // Interactive states
      // ------------------------------------------------------------------
      '--dsw-alias-interactive-bg-hover': t('#1f1d190d', '#ffffff12'),
      '--dsw-alias-interactive-bg-active': t('#1f1d1917', '#ffffff24'),
      '--dsw-alias-interactive-bg-hover-accent': t('#c4603f1f', '#d977572b'),
      '--dsw-alias-interactive-bg-hover-danger': t('#b23a2c0d', '#e8847426'),
      '--dsw-alias-interactive-bg-hover-solid': t('#f3f1ea', '#2e2b27'),

      // ------------------------------------------------------------------
      // Semantic states (kept semantic, warmed to sit on paper)
      // ------------------------------------------------------------------
      '--dsw-alias-state-business-primary': t('#c4603f', '#e2906f'),
      '--dsw-alias-state-business-tertiary': t('#f7e5db', '#4a2f25'),
      '--dsw-alias-state-error-primary': t('#b23a2c', '#e88474'),
      '--dsw-alias-state-error-secondary': t('#d4695a', '#f0a093'),
      '--dsw-alias-state-idle-primary': t('#ccc6b8', '#5c574e'),
      '--dsw-alias-state-success-primary': t('#3f7d58', '#6fbf8c'),
      '--dsw-alias-state-success-secondary': t('#5e9c76', '#8ed3a5'),
      '--dsw-alias-state-success-tertiary': t('#e4f0e7', '#1f3a2a'),
      '--dsw-alias-state-warn-label': t('#8a6410', '#d9b062'),
      '--dsw-alias-state-warn-primary': t('#a8761f', '#e0b15e'),
      '--dsw-alias-state-warn-secondary': t('#c99a3f', '#ecc484'),
      '--dsw-alias-state-warn-tertiary': t('#f7edd8', '#3d2f18'),

      // ------------------------------------------------------------------
      // DSH-specific surfaces
      // ------------------------------------------------------------------
      '--dsw-specific-sidebar-fill': t('#f1eee6', '#0d0c0b'),
      '--dsw-specific-bubble': t('#f0f4f8', 'rgba(255,255,255,.10)'),
      '--dsw-specific-bubble-highlight': t('#e6edf5', 'rgba(255,255,255,.16)'),
      '--dsw-specific-input-major': t('#ffffff', '#1f1e1b'),
      '--dsw-specific-login-input': t('#faf8f3', '#1f1d1a'),
      '--dsw-specific-menu': t('#fbfaf6', '#2b2924'),
      '--dsw-specific-selector': t('#f3f1ea', '#2e2b26'),
      '--dsw-specific-sidebar-nav-item-active': t('#e9e4d8', '#2a2722'),
      '--dsw-specific-sidebar-nav-item-active-accent': t('#f7e3d8', '#3d2b22'),
      '--dsw-specific-sidebar-nav-item-hover': t('#ebe7dd', '#211f1c'),
      '--dsw-specific-tip': t('#f2efe8', '#2a2823'),

      // ------------------------------------------------------------------
      // Corner radii: Claude 2.0 flat scale (4 / 6 / 8 / 12 / 14 / 14)
      // ------------------------------------------------------------------
      '--dsw-radius-xs': t('4px', '4px'),
      '--dsw-radius-sm': t('6px', '6px'),
      '--dsw-radius-md': t('8px', '8px'),
      '--dsw-radius-lg': t('12px', '12px'),
      '--dsw-radius-xl': t('18px', '18px'),
      '--dsw-radius-panel': t('14px', '14px'),

      // ------------------------------------------------------------------
      // Editorial serif headings; body stays in the system sans stack
      // ------------------------------------------------------------------
      '--dsw-font-markdown-h1': t('600 calc(21px + var(--dsh-content-font-delta)) / calc(30px + var(--dsh-content-font-delta)) "Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif', '600 calc(21px + var(--dsh-content-font-delta)) / calc(30px + var(--dsh-content-font-delta)) "Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif'),
      '--dsw-font-markdown-h2': t('600 calc(19px + var(--dsh-content-font-delta)) / calc(28px + var(--dsh-content-font-delta)) "Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif', '600 calc(19px + var(--dsh-content-font-delta)) / calc(28px + var(--dsh-content-font-delta)) "Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif'),
      '--dsw-font-markdown-h3': t('600 calc(18px + var(--dsh-content-font-delta)) / calc(26px + var(--dsh-content-font-delta)) "Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif', '600 calc(18px + var(--dsh-content-font-delta)) / calc(26px + var(--dsh-content-font-delta)) "Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif'),
      '--dsw-font-markdown-h1-font-family': t('"Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif', '"Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif'),
      '--dsw-font-markdown-h2-font-family': t('"Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif', '"Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif'),
      '--dsw-font-markdown-h3-font-family': t('"Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif', '"Iowan Old Style", "Charter", "Palatino Linotype", "Songti SC", Georgia, serif'),
      '--dsw-font-markdown-h1-font-weight': t('600', '600'),
      '--dsw-font-markdown-h2-font-weight': t('600', '600'),
      '--dsw-font-markdown-h3-font-weight': t('600', '600'),


      // ------------------------------------------------------------------
      // Motion physics: tactile 70ms, geometric 120ms, panel 300ms
      // ------------------------------------------------------------------
      '--ds-ease-in-out': t('cubic-bezier(.22, 1, .36, 1)', 'cubic-bezier(.22, 1, .36, 1)'),
      '--ds-transition-duration-fast': t('.07s', '.07s'),
      '--ds-transition-duration': t('.12s', '.12s'),
      '--ds-transition-duration-slow': t('.3s', '.3s'),

      // ------------------------------------------------------------------
      // Floating layers: opaque fills, dual-ring hairline + diffuse shadow.
      // No backdrop blur: translucent panels let page content bleed through.
      // ------------------------------------------------------------------
      '--dsw-mask-blur': t('none', 'none'),
      '--dsw-menu-backdrop-filter': t('none', 'none'),
      '--dsw-elevation-soft': t(
        'var(--dsw-elevation-stroke), 0 1px 2px 0 rgba(42,33,24,.05), 0 10px 28px -14px rgba(42,33,24,.16)',
        'var(--dsw-elevation-stroke), 0 1px 2px 0 rgba(0,0,0,.30), 0 10px 30px -14px rgba(0,0,0,.50)',
      ),
      '--dsw-elevation-panel': t(
        'var(--dsw-elevation-stroke), 0 2px 6px 0 rgba(42,33,24,.06), 0 20px 50px -18px rgba(42,33,24,.24)',
        'var(--dsw-elevation-stroke), 0 2px 8px 0 rgba(0,0,0,.35), 0 22px 56px -18px rgba(0,0,0,.58)',
      ),
      '--dsw-elevation-prominent': t(
        'var(--dsw-elevation-stroke), 0 4px 12px 0 rgba(42,33,24,.08), 0 36px 90px -28px rgba(42,33,24,.30)',
        'var(--dsw-elevation-stroke), 0 4px 14px 0 rgba(0,0,0,.45), 0 40px 100px -30px rgba(0,0,0,.65)',
      ),

      // Clay focus ring
      '--dsw-focus-ring-color': t('#c4603f', '#e2906f'),
    };


    // Structural layer: boundaries, floating-layer physics, press feedback.
    // Selectors lean on stable class suffixes and ARIA roles, never hashed ids.
    const CSS = `
      /* --- Boundary system ------------------------------------------- */
      /* macOS ships a blue-tinted translucent sidebar with no edge.
         Flatten it to one warm plane and keep exactly one hairline. */
      [data-platform="darwin"] [class*="sidebarCol"] {
        background: var(--dsw-specific-sidebar-fill) !important;
      }
      [data-platform="darwin"] [class*="centerCol"] {
        border-left: .5px solid var(--dsw-alias-border-l3) !important;
      }
      /* Right dock is the same page surface; one seam is the only closed
         border on this sightline (1-Border Rule). */
      [class*="rightbarCol"] {
        border-left: .5px solid var(--dsw-alias-border-l3);
      }

      /* --- Floating layers: opaque, never see-through ---------------- */
      /* Token overrides cover the shared menu material; this also catches
         popovers that set their own backdrop filter. */
      [role="menu"], [role="listbox"], [role="tooltip"], [role="dialog"] {
        backdrop-filter: none !important;
      }

      /* --- Floating layers: spring entrance, never touching transform - */
      @media (prefers-reduced-motion: no-preference) {
        [role="dialog"][aria-modal="true"] {
          animation: cds-dialog-in 280ms cubic-bezier(.2, 1.25, .3, 1) both;
        }
        [role="menu"], [role="listbox"] {
          animation: cds-pop-in 160ms cubic-bezier(.2, 1.2, .3, 1) both;
        }
        [role="tooltip"] {
          animation: cds-fade-in 120ms cubic-bezier(.22, 1, .36, 1) both;
        }
        button:not(:disabled):active,
        [role="button"]:not([aria-disabled="true"]):active {
          scale: .98;
        }
      }
      @keyframes cds-dialog-in {
        from { opacity: 0; scale: .97; translate: 0 10px; }
      }
      @keyframes cds-pop-in {
        from { opacity: 0; scale: .98; translate: 0 -3px; }
      }
      @keyframes cds-fade-in {
        from { opacity: 0; }
      }


      /* --- Status motion --------------------------------------------- */
      /* DSH's running indicator is a spinner arc, not a breathing dot:
         keep its geometry, brand it clay, and let it breathe at 2.4s. */
      @media (prefers-reduced-motion: no-preference) {
        svg[class*="_spinner_"] {
          color: var(--dsw-alias-state-business-primary);
          filter: drop-shadow(0 0 2px color-mix(in srgb, var(--dsw-alias-state-business-primary) 40%, transparent));
          animation: cds-breathe 2.4s ease-in-out infinite;
        }
        /* The trailing ellipsis becomes Claude's three-dot wave. */
        [class*="_secondDot"], [class*="_thirdDot"] {
          display: inline-block;
          animation: cds-dot-wave 1.2s cubic-bezier(.45, 0, .55, 1) infinite;
        }
        [class*="_secondDot"] { animation-delay: .15s; }
        [class*="_thirdDot"] { animation-delay: .3s; }
      }
      @keyframes cds-breathe {
        0%, 100% { opacity: .72; }
        50% { opacity: 1; }
      }
      @keyframes cds-dot-wave {
        0%, 60%, 100% { transform: translateY(0); opacity: .5; }
        30% { transform: translateY(-2px); opacity: 1; }
      }


      /* --- Scroll edge: 7-stop perceptual fade ----------------------- */
      /* --cds-fade-top is written by the scroll sensor: 0 at the top,
         40px after scrolling into history. The stop ladder mirrors the
         y ≈ x^1.5 curve so the cut has no visible banding. */
      [data-conversation-scroll] {
        --cds-fade-top: 0px;
        mask-image: linear-gradient(to bottom,
          transparent 0,
          rgba(0, 0, 0, .051) calc(var(--cds-fade-top) * .15),
          rgba(0, 0, 0, .149) calc(var(--cds-fade-top) * .3),
          rgba(0, 0, 0, .302) calc(var(--cds-fade-top) * .45),
          rgba(0, 0, 0, .502) calc(var(--cds-fade-top) * .6),
          rgba(0, 0, 0, .702) calc(var(--cds-fade-top) * .75),
          rgba(0, 0, 0, .851) calc(var(--cds-fade-top) * .87),
          #000 var(--cds-fade-top),
          #000 100%);
      }

      /* --- Selection: clay wash instead of the system blue ----------- */
      ::selection {
        background: color-mix(in srgb, var(--dsw-alias-state-business-primary) 22%, transparent);
      }
    `;


    /**
     * Drive the conversation's top fade from its real scroll position.
     * Masking at rest would dim the first message, so the CSS ladder is
     * collapsed to 0 until the scroller actually leaves the top.
     */
    function installScrollFade() {
      const FADE = 40;
      const bindings = new Map();
      const update = (el) => {
        const top = Math.max(0, Math.min(FADE, el.scrollTop));
        el.style.setProperty('--cds-fade-top', `${top}px`);
      };
      const bind = (el) => {
        if (bindings.has(el)) return;
        /* Direct write: rAF is paused in occluded windows, and a stale
           0 would leave the fade off after a programmatic scroll restore. */
        const schedule = () => update(el);
        el.addEventListener('scroll', schedule, { passive: true });
        const ro = new ResizeObserver(schedule);
        ro.observe(el);
        const settle = setTimeout(schedule, 250);
        update(el);
        bindings.set(el, () => {
          clearTimeout(settle);
          el.removeEventListener('scroll', schedule);
          ro.disconnect();
          el.style.removeProperty('--cds-fade-top');
        });
      };
      const scan = () => {
        for (const [el, dispose] of bindings) {
          if (!el.isConnected) { dispose(); bindings.delete(el); }
        }
        for (const el of document.querySelectorAll('[data-conversation-scroll]')) bind(el);
      };
      const observer = new MutationObserver(scan);
      observer.observe(document.body, { childList: true, subtree: true });
      scan();
      return () => {
        observer.disconnect();
        for (const dispose of bindings.values()) dispose();
        bindings.clear();
      };
    }

    return {
      inject: ['theme'],
      apply(ctx) {
        ctx.effect(
          () => ctx.theme.overrideTokens('@local/claude-warm-theme', tokens),
          'claude-theme: token overrides',
        );
        ctx.effect(() => {
          const style = document.createElement('style');
          style.dataset.claudeTheme = 'shell';
          style.textContent = CSS;
          document.head.append(style);
          return () => style.remove();
        }, 'claude-theme: shell styles');
        ctx.effect(() => installScrollFade(), 'claude-theme: scroll fade');
      },
    };
  },
});
