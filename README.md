# PDFlight AI

<p align="center">
  <img src="Resources/PDFlightIcon.png" width="160" alt="PDFlight icon">
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

PDFlight AI is an extremely light, native macOS paper reader with an integrated **Ask PDF** workspace. It combines an AppKit interface and PDF-only MuPDF engine with per-paper AI conversations, editable prompt modes, and native Markdown/LaTeX rendering—without a web view, embeddings, or RAG.

**Extremely Light**

| Open PDFs | PDFlight | Skim |
| ---: | ---: | ---: |
| 10 | 165.2 MiB | 934.6 MiB |
| 30 | 338.2 MiB | 2,595.6 MiB |

Current features:

- continuous vertical scrolling with visible-page rendering;
- an always-available native library sidebar with one width synchronized across every open paper, unlimited nested collections, display aliases, search, drag-to-file papers, and one-click paper switching;
- a hierarchical document outline with page-number navigation, available beside the library;
- a 12 MiB MuPDF store limit and a byte-bounded 12 MiB rendered-page cache per document;
- inactive windows release text, rendered pages, and MuPDF caches after five seconds;
- selectable/copyable PDF text;
- selection-first highlighting from the toolbar or Command-E, without switching tools;
- full-document search with result navigation and page highlights;
- password-protected PDF opening;
- internal PDF links with exact pre-link viewport restoration via Command-Left Arrow;
- external links through the default browser;
- reopening a PDF restores its last page, precise viewport position, and zoom;
- Retina rendering, fit-width, keyboard/pinch zoom, and nonblank progressive redraw while zooming;
- different PDFs grouped as tabs in one window by default;
- text-aligned highlights written back as standard PDF annotations;
- embedded PDF text-note annotations;
- Command-Z undo for the most recent highlight or text note;
- a native **Ask PDF** sidebar with buffered streaming, a workspace-wide remembered width and visibility, horizontal per-paper conversation tabs, adjustable and selectable reply text, editable prompt-mode buttons, native block Markdown/LaTeX rendering, and per-message copy/delete actions;
- direct save with a close-time unsaved-changes warning.

## Ask PDF

The AI sidebar opens by default and can be resized by dragging its divider. Its width and visibility are shared by every open paper and restored on the next launch, together with the reader window frame. Optional reply-list gesture zoom is disabled by default; enable it in AI Settings to pinch or Command-scroll over replies without resizing the composer or controls. The same panel can open the portable chat-history folder directly in Finder. A **+** button immediately after the conversation tabs creates another conversation for the current paper. Use **Shift-Command-A** to hide or show the sidebar, then use the gear button to enter an OpenAI-compatible Base URL, model, and optional API key. OpenAI, OpenRouter, DeepSeek, Ollama, and LM Studio-style chat-completions endpoints are supported.

PDFlight receives streaming responses in the background while showing live activity state, then inserts and renders the complete Markdown/LaTeX answer once generation finishes. This avoids repeatedly laying out unfinished tables and formulas. If generation is stopped or the connection fails, any answer text already received is retained as a partial reply.

Every new conversation starts with **No prompt**. Prompt modes appear as buttons below the composer: click **Reading** to enable its saved Chinese deep-reading prompt. Use the adjacent menu to edit No prompt or Reading, or add another mode. Templates are portable JSON and support `{{title}}` for the current PDF title. No mode automatically appends PDF pages.

Conversations for the current PDF appear as stable horizontal tabs. The smaller/larger text controls adjust and remember reply text size without changing the composer. Replies use the same macOS system-font stack as Argus—SF Pro with the native Chinese fallback and SF Mono for code. Sending with Return keeps the active tab and newest message visible.

Each PDF tab owns its own chat area and can contain multiple conversations. The history button groups conversations by paper and can reveal the files in Finder. History uses pretty-printed, versioned UTF-8 JSON—one file per paper—under `~/Library/Application Support/dev.pdflight.reader/ai-chats`, so it can be backed up or migrated without a database. Assistant replies render native headings, lists, quotes, tables, fenced code, bold/italic Markdown, and LaTeX math, including Unicode labels inside `\text{…}`. Emphasis can span inline equations, inline equations stay embedded in their surrounding paragraph, and wide display equations scroll horizontally instead of being clipped. Reply text is selectable. Every user/assistant card has copy at both the top and bottom, plus a confirmed delete action that updates local history.

The AI feature stays deliberately small: it does not build embeddings, run RAG, expose MCP tools, automatically capture or upload PDF pages, or use a web view. Images are sent only when the user explicitly pastes, drops, or attaches them. API keys are stored in macOS Keychain.

## Paper library

The left sidebar opens to **Library** by default and can switch to the current PDF's **Outline**. Its width and visibility use the same workspace layout as every other paper: changing either sidebar updates all existing windows, future papers, and the next launch. **Recent** lists PDFs in true last-opened order; the File menu also provides **Open Recent** and **Clear Menu**. Create collections and subcollections to any depth, add PDFs, search by display name, file name, or path, press Return/double-click to open papers, and Command/Shift-select several papers before dragging or moving them to another collection. Names matching `Author - 2026 - Paper title` automatically display as `Paper title`. Use **Edit display name…** in a paper's context menu to set a custom alias without renaming the PDF; clear it to restore the automatic name. Opened PDFs are indexed automatically under Unfiled. Enable **Restore Last Session at Launch** in the application menu to reopen the PDFs that were still open when PDFlight quit. The library and last session are stored as portable, pretty-printed JSON under `~/Library/Application Support/dev.pdflight.reader/`; removing a library entry never deletes the PDF itself.

## Download

Download the latest Apple Silicon build from [GitHub Releases](https://github.com/Yuqin-G/pdflight-ai/releases/latest). PDFlight requires macOS 14 or later. The current open-source build is ad-hoc signed; on first launch, use **Control-click → Open** if macOS asks you to confirm the unidentified developer.

## Build

Requirements: macOS 14 or later, Apple Command Line Tools, Git, and an internet connection for the first MuPDF checkout.

```sh
./Scripts/build-app.sh
open ./dist/PDFlight.app
```

The build script checks out MuPDF 1.28.2 and compiles only the native libraries needed by PDFlight. EPUB/HTML, XPS, SVG, JavaScript, OCR, and barcode support are not included. The `tofu` build keeps Base 14 and CJK fallback fonts while omitting unrelated fallback fonts.

To install the local build:

```sh
ditto ./dist/PDFlight.app /Applications/PDFlight.app
```

To make it the default PDF reader with [`duti`](https://github.com/moretension/duti):

```sh
duti -s dev.pdflight.reader com.adobe.pdf viewer
duti -s dev.pdflight.reader com.adobe.pdf editor
duti -s dev.pdflight.reader com.adobe.pdf shell
```

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Open | Command-O |
| Save | Command-S |
| Undo last annotation | Command-Z |
| Copy selected text | Command-C |
| Search | Command-F |
| Next/previous result while in search field | Return / Shift-Return |
| Next/previous search result | Command-G / Shift-Command-G |
| Move caret while editing search or chat text | Left/Right Arrow |
| Previous/next page | Left/Right Arrow |
| Back after following a link | Command-Left Arrow |
| Zoom | Command-Plus/Minus |
| Fit width | Command-0 |
| Highlight selected text | Command-E |
| Find the current paper and its citing-paper entry on Google Scholar | Toolbar graduation-cap button |
| Show/hide Ask PDF | Shift-Command-A |
| AI settings | Command-Comma |
| Text-note mode | N |

## Architecture

`DocumentEngine` is the document seam: page inspection, document outlines, text extraction, search, rendering, links, annotations, passwords, memory release, and save. `MuPDFDocument` is the first adapter. `RenderScheduler` owns in-flight request coalescing and a byte-bounded LRU cache. `DocumentCanvasView` virtualizes page bitmaps by retaining rendered content only near the viewport. `ReadingPositionStore` and `PaperLibraryStore` atomically persist local JSON. `PDFlightAI` contains explicit request construction, OpenAI-compatible streaming, Keychain configuration, and per-PDF chat persistence. AppKit only talks to those interfaces.


## License

PDFlight is released under AGPL-3.0-or-later because it links MuPDF. See `LICENSE` and MuPDF's notices under `Vendor/mupdf`.
