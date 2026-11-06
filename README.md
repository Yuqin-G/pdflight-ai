# PDFlight AI

[简体中文](README.zh-CN.md)

A lightweight macOS PDF reader with a paper library and an Ask PDF sidebar.
Requires macOS 14+ and Apple Silicon.

- PDF search, outlines, highlights, notes, and saved reading positions.
- Nested library collections and tabbed papers. Every launch restores all groups' open PDFs, tab order, and selected papers, starting in Default; PDFs opened from Finder or the command line are merged into that restored workspace.
- Harness-style chat typography, tables, math, and independent reading zoom.
- Fixed-size message composer, PDF/image attachments, and per-paper conversations.
- OpenAI-compatible API and supported web chat providers; credentials stay local.

## Download

Get the app from [GitHub Releases](https://github.com/Yuqin-G/pdflight-ai/releases/latest).
Extract the ZIP and move **PDFlight.app** to Applications. The build is ad-hoc signed;
use **Control-click → Open** on first launch if macOS requires it.

## Build

Install Apple Command Line Tools, then:

```sh
git clone --recurse-submodules https://github.com/Yuqin-G/pdflight-ai.git
cd pdflight-ai
./Scripts/build-app.sh
open dist/PDFlight.app
```

The first build downloads and compiles MuPDF. Chat rendering is bundled;
DeepSeek Harness is not required to display conversations. Configure your model
or web provider in the app before sending messages.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Open / Save | ⌘O / ⌘S |
| Search | ⌘F |
| Highlight / Undo | ⌘E / ⌘Z |
| Fit width | ⌘0 |
| Show/hide Ask PDF | ⇧⌘A |

[License](LICENSE) · [Architecture](CONTEXT.md) · [Benchmarks](BENCHMARK.md)
