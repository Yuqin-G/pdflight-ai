# Chat heavy-view cache checks

The cache retains at most the last selected chat and one recent chat. It holds weak owners, so a closed document is not retained. Hidden roots keep their slots until the next selection: hiding B must not evict A immediately before an A → B → A return.

Production hooks are `NativePaperChatSidebar.viewDidHide`, `viewDidUnhide`, and `viewDidMoveToWindow`; they handle workspace roots that stay in the same native window. The document controller's existing activation call remains valid. Heavy-view eviction releases WebKit and native Markdown/formula rows, not the sidebar, draft, transcript, request task, or history-save task. Hidden/cold message updates only mutate lightweight transcript state. Native transcript rows are built only for the native renderer or an actual renderer failure, then released when WebKit succeeds.

`preview.js` now supplies Harness's real `chatScroll` store rather than a no-op store. Each mounted revision has its own store, and stale revisions cannot overwrite its replacement. WebKit restores through Harness's saved-offset fallback because scaled anchor geometry and scroll offsets have different units. The native bridge ignores the initial empty page's scroll reports and reports from discarded renderers. Unchanged warm renderers are not remounted on activation.

## Small standalone check

From the repository root:

```sh
bash Tools/ChatCacheCheck/run.sh
```

Requires only the installed Swift compiler and Foundation. Compiles the production cache into a temporary executable and checks A/B reuse, third-owner eviction, closing, weak ownership, and 1,000 selections. The temporary directory is removed on exit.

## Native lifecycle and real WebKit check

Pass an executable built in an isolated scratch directory:

```sh
bash Tools/ChatCacheCheck/run.sh --renderer /tmp/pdflight-chat-cache-build/debug/PDFlight
```

The script copies that executable and renderer resources into a temporary bundle with a dedicated bundle identifier. It supplies isolated `HOME`, `CFFIXED_USER_HOME`, and `TMPDIR`, and runs only `--self-check-chat-renderer` with the opt-in `PDFLIGHT_CHAT_CACHE_WEB_CHECK=1` flag. It never launches the normal application lifecycle or creates an AppDelegate, reader session, history store, real document, model request, or final distribution.

The integrated checks exercise ancestor hide/unhide in a synthetic window, lazy native/WebKit allocation, actual row release, recent renderer identity, third-paper eviction, background message/reasoning updates, draft/zoom preservation, native scroll state and real DOM reading-position restoration after renderer recreation. Background message completion is synthetic; this check makes no model/network request and does not test disk history writes. Those continue to belong to the unchanged ReaderWindowController/history store lifecycle.

## Change ownership

This lane changes only:

- `Sources/PDFlightApp/NativePaperChatSidebar.swift`
- `Sources/PDFlightApp/HarnessChatPreview.swift`
- `Sources/PDFlightApp/ChatHeavyViewCache.swift` (new)
- `Resources/HarnessChat/preview.js`
- `Tools/ChatCacheCheck/` (new)

The existing workspace self-check extensions in both chat files are preserved. AppDelegate, ReaderWindowController, PDFlightMain, ReaderWorkspacePresentation, session restoration, build configuration and final packaging belong to the parallel/main lanes.
