# PDFlight

<p align="center">
  <img src="Resources/PDFlightIcon.png" width="160" alt="PDFlight icon">
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

PDFlight is a small, native macOS PDF reader built for papers. It uses an AppKit shell and a PDF-only MuPDF build instead of PDFKit's `PDFView` or a web view.

**Extremely Light**

| Open PDFs | PDFlight | Skim |
| ---: | ---: | ---: |
| 10 | 165.2 MiB | 934.6 MiB |
| 30 | 338.2 MiB | 2,595.6 MiB |

Current features:

- continuous vertical scrolling with visible-page rendering;
- a native hierarchical outline sidebar with page-number navigation;
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
- direct save with a close-time unsaved-changes warning.

## Download

Download the latest Apple Silicon build from [GitHub Releases](https://github.com/Yuqin-G/pdflight/releases/latest). PDFlight requires macOS 14 or later. The current open-source build is ad-hoc signed; on first launch, use **Control-click → Open** if macOS asks you to confirm the unidentified developer.

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
| Previous/next page | Left/Right Arrow |
| Back after following a link | Command-Left Arrow |
| Zoom | Command-Plus/Minus |
| Fit width | Command-0 |
| Highlight selected text | Command-E |
| Text-note mode | N |

## Architecture

`DocumentEngine` is the document seam: page inspection, document outlines, text extraction, search, rendering, links, annotations, passwords, memory release, and save. `MuPDFDocument` is the first adapter. `RenderScheduler` owns in-flight request coalescing and a byte-bounded LRU cache. `DocumentCanvasView` virtualizes page bitmaps by retaining rendered content only near the viewport. `ReadingPositionStore` atomically persists recent document positions to local JSON. AppKit only talks to those interfaces.


## License

PDFlight is released under AGPL-3.0-or-later because it links MuPDF. See `LICENSE` and MuPDF's notices under `Vendor/mupdf`.
