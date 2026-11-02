// Compatibility for WebKit's system-font fallback and CSS zoom behavior.
// Chromium keeps Harness's original font selection and zoom path unchanged.
export const isHarnessWebKit = /AppleWebKit/.test(navigator.userAgent)
  && !/Chrom(?:e|ium)|Edg\//.test(navigator.userAgent);

export function installHarnessWebKitCompatibility() {
  if (!isHarnessWebKit) return () => {};
  const identifier = 'pdflight-harness-webkit-compat';
  if (document.getElementById(identifier)) return () => {};
  const style = document.createElement('style');
  style.id = identifier;
  // WebKit's system-ui cascade shrinks its implicit PingFang fallback (a 14px
  // CJK glyph advances 13.89px). An explicit, local face keeps the original
  // 14px advance used by Chromium. The Unicode range leaves Latin system-font
  // glyphs and the theme's explicit serif heading families unchanged.
  const ranges = 'U+2E80-2FFF,U+3000-303F,U+3400-4DBF,U+4E00-9FFF,U+F900-FAFF,U+FE30-FE4F,U+FF01-FF60,U+FFE0-FFE6,U+20000-323AF';
  // WebKit's PostScript-name lookup for PingFangSC-Medium widens glyph
  // advances; its actual full name selects the same Medium face without
  // that expansion. Both advances and rendered strokes were compared with
  // Chromium; substituting the Regular face would lighten the strokes.
  const faces = [
    ['400', 'PingFangSC-Regular'],
    ['500', 'PingFang SC Medium'],
    ['600 900', 'PingFangSC-Semibold'],
  ];
  style.textContent = faces.map(([weight, source]) => `
    @font-face {
      font-family: 'Harness WebKit CJK';
      src: local('${source}');
      font-weight: ${weight};
      font-style: normal;
      unicode-range: ${ranges};
    }
  `).join('') + `
    /* WebKit reserves a 17px native gutter for stable+auto overflow until a
       scrollbar is painted. A persistent scroll track uses Harness's actual
       5px styled width even when short content has no thumb. */
    [data-conversation-scroll] { overflow-y: scroll; }
    /* Chromium snaps the original 0.5px Markdown rules to one physical CSS
       pixel across chat zoom. The host publishes the inverse zoom length. */
    #chat-body [class*="_markdown_"] th,
    #chat-body [class*="_markdown_"] td {
      border-bottom-width: var(--pdflight-chromium-hairline, .5px);
    }
    /* WebKit snaps border lengths again before the transform, including the
       half-border in a collapsed header row. Preserve Chromium's row heights
       by giving back only the measured missing border contribution. */
    #chat-body [class*="_markdown_"] th {
      padding-bottom: calc(10px + var(--pdflight-chromium-head-border-extra, 0px));
    }
    #chat-body [class*="_markdown_"] td {
      padding-bottom: calc(10px + var(--pdflight-chromium-cell-border-extra, 0px));
    }
    #chat-body [class*="_markdown_"] :not(pre) > code {
      border-width: var(--pdflight-chromium-hairline, .5px);
    }
    #chat-body [class*="_markdown_"] blockquote {
      border-left-width: var(--pdflight-chromium-blockquote-border, 2px);
      padding-left: calc(14px + var(--pdflight-chromium-quote-border-extra, 0px));
    }
    body {
      --dsw-font-family: 'Harness WebKit CJK',
        var(--dsh-font-family-text, var(--dsh-font-family-text-default)),
        var(--dsh-font-family-text-default);
    }
  `;
  document.head.appendChild(style);
  return () => style.remove();
}
