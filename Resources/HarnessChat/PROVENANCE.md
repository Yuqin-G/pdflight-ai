# Harness chat assets

These assets were extracted from DeepSeek Harness `0.2.1-rc.5`; the source
application archive had SHA-256
`8dad52f295bdbe9fa71948fdf38ac2ce3c910213d3b89c37174b2af77db9fb31`.
Harness is distributed under the included MIT license; bundled dependency
notices are in `THIRD_PARTY_NOTICES.md`.

`assets/pdflight-static.js` exposes the installed build's existing module
runtime without starting the desktop client. The three `dsh-client-*.js`
files expose the existing components for the local host adapter; the input
bundle also preserves leading and trailing whitespace on submission. The eight
ordered theme stylesheets are copied verbatim from the installed ui-theme module;
their identities and hashes are in `theme-provenance.json`. The reading stylesheet
includes both original `css` and `refinedCss` blocks. The actual enabled local
`claude-warm-theme` plugin is bundled verbatim and owns the warm palette, serif
headings, token overrides, and scroll fade. Its tokens are applied to `body.style`
through the same theme-host boundary as Harness.

The preview uses the original embedded `ConversationContent` and
`DefaultConversationViews` around `ChatView`. These components own the shared
content width, responsive margins, paragraph spacing, and wide-table breakout.
No per-message padding or table-size overrides are added. The current Harness
profile's 14px text and 12px code settings are applied unchanged.
WebKit uses an isolated compatibility layer: inverse layout dimensions plus a
paint transform preserve Chromium's system-font optical size, line heights,
and container-query table widths while zooming. Explicit local PingFang faces
preserve the same CJK glyph advances. The original theme and component source
are not rewritten to work around these engine differences.
The original PDF-reading plugin is in `pdf-reading-client.js`, with its existing tab
component exported for the local host. Its original chat zoom behavior is
adapted into `harness-chat-zoom.js`.

The packaging script includes these files as the default message renderer.
The composer and model controls remain native. `PDFLIGHT_HARNESS_PREVIEW=0`
selects the fallback native renderer. These files contain no chat data or model
credentials.

Local reading preferences: the native composer stays at 100% when transcript
zoom changes; `preview.html` reduces Markdown divider margins and the heading
gap immediately after a divider to 16px. Original theme assets remain intact.
