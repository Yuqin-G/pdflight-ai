window.__ModuleLoader__.load({
  id: '@local/pdflight-harness-chat',
  factory() {
    return {
      inject: ['layout'],
      apply(ctx) {
        // The real Desktop and embedded views keep separate browser stores.
        // Share the original PDF reader's zoom preference through the Host.
        const zoomKey = 'pdf-reading-chat-zoom';
        let lastZoom;
        const syncZoom = () => {
          let value;
          try { value = Number(window.localStorage.getItem(zoomKey)); } catch { return; }
          if (!Number.isFinite(value) || value < 0.8 || value > 2.4 || value === lastZoom) return;
          lastZoom = value;
          fetch('/pdflight-bridge/zoom', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ zoom: value }) })
            .then(response => { if (!response.ok) lastZoom = undefined; })
            .catch(() => { lastZoom = undefined; });
        };
        syncZoom();
        ctx.effect(() => {
          const timer = setInterval(syncZoom, 1000);
          return () => clearInterval(timer);
        });
        // The Desktop window never sets this flag; only PDFlight's WebKit view does.
        if (!window.__PDFLIGHT_EMBED__) return;
        const style = document.createElement('style');
        style.textContent = `
          html,body,#root {width:100%;height:100%;margin:0;overflow:hidden}
          div:has(> [data-shell-bottom]) {grid-template-columns:0 minmax(0,1fr) 0!important}
          [class*="sidebarCol"],[class*="rightbarCol"] {visibility:hidden;overflow:hidden;pointer-events:none}
          [data-shell-leading],[data-shell-bottom] {display:none!important}
          .pr-workspace {display:grid!important;grid-template-columns:0 0 minmax(0,1fr)!important;width:100%;height:100%}
          .pr-reader,.pr-divider {visibility:hidden;pointer-events:none;overflow:hidden}
          .pr-chat {width:100%;height:100%}
        `;
        document.head.appendChild(style);
        let attempts = 0;
        const select = () => {
          ctx.layout.selectPanel('pdf-reading');
          if (!document.querySelector('.pr-chat') && ++attempts < 40) setTimeout(select, 100);
        };
        setTimeout(select, 250);
        ctx.effect(() => () => style.remove());
      }
    };
  }
});
