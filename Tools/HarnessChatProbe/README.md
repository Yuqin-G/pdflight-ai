# Harness chat port feasibility probe

This is an **isolated, unfinished experiment**, not the PDFlight sidebar. It
loads the installed Harness build's actual chat, input and model-selection
components into a local WebKit page without starting Harness. The host services
in this probe are stubs: do not use it to send messages or edit conversations.

To reproduce with a local migration-stage chat JSON, pass its path explicitly:

```sh
python3 Tools/HarnessChatProbe/prepare.py \
  --history '/path/to/local/chat.json' --output /tmp/pdflight-harness-probe
swiftc -parse-as-library Tools/HarnessChatProbe/WebKitProbe.swift \
  -o /tmp/pdflight-harness-probe-runner
/tmp/pdflight-harness-probe-runner /tmp/pdflight-harness-probe
/tmp/pdflight-harness-probe-runner /tmp/pdflight-harness-probe composer
```

The output contains a private copy of the selected conversation. Keep it out of
the repository, and delete it when no longer needed. The probe reports counts,
layout timing and boundary measurements, not conversation text. It uses
synthetic gesture events; results do not substitute for real trackpad testing.
The composer probe sends a synthetic string only to an in-memory stub, and
checks exact preservation of newlines and leading/trailing whitespace. It
does not exercise attachments, references, provider requests or persistence.

`prepare.py` requires an installed Harness build and its corresponding source
checkout only while preparing the experiment. This is not a design for a
runtime dependency: a finished app must bundle its own verified assets, license
notices and local data bridge, and must remain usable when Harness is absent.
No production application is modified by these commands.

`full-probe.html` combines the actual Harness conversation container, message
view, composer, and model menu; its model and session callbacks are stubs.
The probe's synthetic gesture test resets the zoom before measuring. Text
boundary checks exclude tables (tested separately for horizontal scrolling),
math/code and the composer's intentionally ellipsized placeholder.

The WebView transfer logic can be checked independently with:

```sh
swiftc -parse-as-library Sources/PDFlightApp/HarnessChatWebViewPool.swift \
  Tools/HarnessChatProbe/PoolCheck.swift -o /tmp/pdflight-harness-pool-check
/tmp/pdflight-harness-pool-check
```

The transfer test checks object reuse and save ordering with simulated hosts;
it does not measure WebKit processes, exercise real editor persistence, or
prove the production app has adopted the pool.

Check the bundled production preview's resolved typography, content gutters,
and horizontal table scrolling with synthetic data in isolated WebKit storage:

```sh
swiftc -parse-as-library Tools/HarnessChatProbe/TableCheck.swift -o /tmp/pdflight-table-check
/tmp/pdflight-table-check "$PWD/Resources/HarnessChat"
```

This checks widths of 420/1100 pixels at 80/100/160/240% zoom, confirms both
table ends remain reachable and the page does not overflow horizontally, and
exits nonzero on assertion failure or timeout. It reads no conversation files.
It permits the original wide-table breakout beyond the centered message
column and focuses each table before checking both scroll endpoints.
Repeated React updates also verify exact DOM text and copied selections for
leading/trailing spaces, repeated spaces, newlines, indentation and tabs.

For exact layout comparison, prepare an independent reference from the installed
Harness archive and the original PDF-reading and warm-theme plugins:

```sh
python3 Tools/HarnessChatProbe/prepare-parity.py \
  --output /tmp/pdflight-harness-reference
python3 Tools/HarnessChatProbe/ChromeParityCheck.py \
  Resources/HarnessChat /tmp/pdflight-harness-reference /tmp/pdflight-chrome-parity \
  --device-scale-factor 2
swiftc -parse-as-library Tools/HarnessChatProbe/ParityCheck.swift -o /tmp/pdflight-parity-check
/tmp/pdflight-parity-check "$PWD/Resources/HarnessChat" /tmp/pdflight-harness-reference \
  /tmp/pdflight-webkit-parity /tmp/pdflight-chrome-parity
```

Use a new reference output directory and match Chrome's device scale factor to
the Mac display. The reference imports no migrated preview or compatibility
code. It uses the original ConversationContent and DefaultConversationViews
components with the original embedded-reading variant and active phase; its
composer slot is empty and no provider is contacted. Both checks share only
synthetic messages and measurement scripts (`parity-fixture.js` and
`parity-metrics.js`). Each saves 420/680/1100px × 80/100/160/240% screenshots and
JSON metrics for typography, margins, element bounds and table scroll ranges.
Paragraph, heading, list and user-bubble line counts must match exactly.
Font size and line height must agree within .02 CSS pixels and weight must
match; column geometry permits 1 point of engine rounding, block heights
2 points, accumulated positions and total height 3 points. Table endpoints
permit one unscaled CSS pixel because CSSOM scroll extents are integer-valued.
Bounds are compared on the display's physical pixel grid; the saved JSON keeps
the original unrounded measurements.

The optional final ParityCheck argument selects the original Chromium metrics
as the pass/fail reference. Omitting it compares two WebKit pages, which is
useful for diagnosis but also reproduces WebKit's original CSS-zoom/container
query bugs and therefore does not establish parity with the Harness desktop app.


The integrated preview keeps a renderer per open paper window so activation does
not blank the previous window or transfer its scroll and zoom state. Closing a
preview detaches and releases its renderer. This uses more WebKit memory than the
single-renderer transfer experiment. The independent window regression uses the
real preview wrapper and two WebViews (no conversation data or provider calls):

```sh
swift build --product PDFlight
swiftc -parse-as-library \
  -I .build/arm64-apple-macosx/debug/Modules \
  -I .build/checkouts/Yams/Sources/CYaml/include \
  Sources/PDFlightApp/HarnessChatWebViewPool.swift \
  Sources/PDFlightApp/HarnessChatPreview.swift \
  Tools/HarnessChatProbe/PreviewWindowCheck.swift \
  .build/arm64-apple-macosx/debug/PDFlightAI.build/*.o \
  .build/arm64-apple-macosx/debug/PDFlightCore.build/*.o \
  .build/arm64-apple-macosx/debug/Yams.build/*.o \
  .build/arm64-apple-macosx/debug/CYaml.build/src/*.o \
  -o /tmp/pdflight-preview-window-check
/tmp/pdflight-preview-window-check
```


To also check the bundled renderer, native/WebKit zoom bridge, and retained
scroll positions, put the runner in a temporary app layout and reference the
checked-in resources. All messages are synthetic:

```sh
mkdir -p /tmp/PDFlightPreviewCheck.app/Contents/{MacOS,Resources}
cp /tmp/pdflight-preview-window-check /tmp/PDFlightPreviewCheck.app/Contents/MacOS/PDFlightPreviewCheck
ln -sfn "$PWD/Resources/HarnessChat" /tmp/PDFlightPreviewCheck.app/Contents/Resources/HarnessChat
/tmp/PDFlightPreviewCheck.app/Contents/MacOS/PDFlightPreviewCheck --rendered --snapshot
```

The optional screenshot is `/tmp/pdflight-window-check.png`.

The production renderer's viewport and gesture behavior can be checked with
synthetic messages (no Harness installation or conversation history needed):

```sh
swiftc -parse-as-library Tools/HarnessChatProbe/ZoomCheck.swift \
  -o /tmp/pdflight-harness-zoom-check
/tmp/pdflight-harness-zoom-check "$PWD/Resources/HarnessChat"
```

This checks 340/680/980 px wide WebKit windows at 80/100/140/240%, full-height
layout without page overflow, 14/24 px body typography, increasing glyph size,
wheel/pinch sensitivity, zoom limits, and invalid-value handling. Gestures are
synthetic; real trackpad feel still needs a manual check.

Theme resources are exported from the installed Harness archive, rather than
from the adjacent source checkout. The installed app is `0.2.1-rc.5`; the local
`dsh-src` package manifests currently say `0.2.1-rc.2`, so that checkout alone
cannot establish which CSS the running app uses. Export or verify the eight
original theme sheets in their `STYLES` order with:

```sh
python3 Tools/HarnessChatProbe/extract-installed-theme.py \
  --output Resources/HarnessChat
python3 Tools/HarnessChatProbe/extract-installed-theme.py \
  --output Resources/HarnessChat --check
```

The default archive is `/Applications/DeepSeek Harness.app/Contents/Resources/app.asar`;
`--archive` selects another archive explicitly. `theme-provenance.json` records
the archive hash, module hash, version, ordered filenames and exact CSS hashes.
The check parses bundled string literals and never starts Harness. Runtime
rendering comparisons must preserve the original order: `base`, `corner-shape`,
`design-platform`, `focus`, `onboarding`, `scrollbar`, `gradient-shadow-text`,
then `shiki`.

The active desktop profile also links `@local/claude-warm-theme` version `1.6.1`.
Its original plugin owns heading font family and weight, colors, radii, shadows,
shell CSS and the scroll sensor. Copy or verify its complete original file with:

```sh
node Tools/HarnessChatProbe/extract-theme.mjs \
  /path/to/deepseek-harness/default-workspace/claude-warm-theme/client.js \
  Resources/HarnessChat/claude-warm-theme-client.js
node Tools/HarnessChatProbe/extract-theme.mjs \
  /path/to/deepseek-harness/default-workspace/claude-warm-theme/client.js \
  Resources/HarnessChat/claude-warm-theme-client.js --check
```

The source and bundled plugin are byte-identical (SHA-256
`9d331daa22b5868ccb68d7dd88e476a93f28060d3f58f3d135615a72be5ebd78`).
Load it through the existing module loader and invoke its original `apply` with
the host's effect/theme adapter. As in the original presenter, the adapter writes
token overrides onto `body.style` and uses `body[data-ds-dark-theme]` for dark
mode. The original plugin installs its shell CSS and scroll sensor itself.
Profile typography settings are 14px text and 12px code, with no custom font
family configured. The helper never executes the source; `--check` validates
byte equality, which does not by itself prove matching DOM ancestry or pixels.

Cross-engine reading parity needs the WebKit compatibility adapter as well as
the byte-identical Harness assets. WebKit CSS `zoom` changes the system font's
optical selection and rounds line heights; an original 14px Latin sample at
240% measured 392.30px in WebKit versus 431.05px in Chromium. The WebKit zoom
hook now lays out at inverse viewport dimensions and paints with `transform:
scale(...)`; that sample then measures 431.06px with matching line counts.
Chromium retains Harness's original CSS zoom path. `data-chat-zoom` is the
shared effective ratio; WebKit intentionally leaves `style.zoom` unset.

`harness-webkit-compat.js` also selects local PingFang faces for the Chinese
Unicode ranges so WebKit preserves Chromium's full-width CJK advances. The
Medium face uses its full name `PingFang SC Medium`: WebKit's PostScript-name
lookup widens these glyph advances. At 13px/500, the original Chromium mixed
sample `Safety 防御成功率` is 108.203125px wide; the full-name face preserves that
width and the actual Medium strokes. Substituting Regular would match advances
but visibly lighten strokes, so it is not used. `ZoomCheck.swift` locks down
both this sample and four 14px Chinese glyphs throughout its zoom/window matrix.
The adapter also reconciles WebKit's stable scrollbar gutter and the original
Markdown rule widths with Chromium's actual painted geometry. None of these
compatibility rules modify the original theme sheets or plugin bytes.
