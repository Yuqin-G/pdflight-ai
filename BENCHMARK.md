# PDFlight vs. Skim memory benchmark

Measured on 2026-08-06 using macOS physical footprint, the metric that most closely matches Activity Monitor's Memory column. RSS is deliberately not used.

## Summary

| Open PDFs | PDFlight mean | Skim mean | PDFlight reduction | Skim / PDFlight |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 165.2 MiB | 934.6 MiB | 82.3% | 5.66x |
| 30 | 338.2 MiB | 2595.6 MiB | 87.0% | 7.67x |

Each mean is the average of two independently launched process trials. Every trial reached the requested document-window count and passed the stability gate described below.

## Raw trial results

| PDFs | Application | Round | Stable after | Mean | Min | Max |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 10 | PDFlight | 1 | 14 s | 232.4 MiB | 232.4 MiB | 232.6 MiB |
| 10 | PDFlight | 2 | 30 s | 97.9 MiB | 97.8 MiB | 97.9 MiB |
| 10 | Skim | 1 | 15 s | 947.9 MiB | 945.1 MiB | 949.6 MiB |
| 10 | Skim | 2 | 15 s | 921.4 MiB | 920.7 MiB | 921.9 MiB |
| 30 | PDFlight | 1 | 14 s | 447.6 MiB | 447.6 MiB | 447.6 MiB |
| 30 | PDFlight | 2 | 18 s | 228.9 MiB | 228.8 MiB | 228.9 MiB |
| 30 | Skim | 1 | 14 s | 2604.2 MiB | 2569.9 MiB | 2640.2 MiB |
| 30 | Skim | 2 | 14 s | 2587.0 MiB | 2563.6 MiB | 2617.0 MiB |

Machine-readable results are stored in [`Benchmarks/2026-08-06-10-pdfs.csv`](Benchmarks/2026-08-06-10-pdfs.csv) and [`Benchmarks/2026-08-06-30-pdfs.csv`](Benchmarks/2026-08-06-30-pdfs.csv).

## Method

- Corpus: the first 10 or 30 PDF files from a bytewise-sorted local Zotero storage listing; both applications receive the identical paths in each trial.
- Trial order: PDFlight 1, Skim 1, Skim 2, PDFlight 2. This reduces a simple first-run filesystem-cache bias.
- Isolation: each trial uses `NSWorkspace.OpenConfiguration.createsNewApplicationInstance` and records the returned PID. Existing app processes are not included.
- Readiness: a Core Graphics helper must observe exactly 10 or 30 qualifying document windows for four consecutive checks.
- Settling: measurement starts no earlier than 10 seconds after readiness.
- Stability: physical footprint is sampled once per second. A trial is accepted only when the most recent five samples span no more than 5% of their mean.
- Metric: `proc_pid_rusage(..., RUSAGE_INFO_V4, ...)` and `ri_phys_footprint`, reported in MiB.
- Each benchmark-owned process is terminated after its samples are recorded.

Run the benchmark with:

```sh
./Scripts/benchmark-10-pdfs.sh
./Scripts/benchmark-30-pdfs.sh
```

## Environment

- Mac: Mac17,9, Apple M5 Pro, 48 GiB RAM, arm64
- macOS: 26.4 (25E246)
- PDFlight: 0.1.0, 31 MiB application bundle
- Skim: 1.7.15, 21 MiB application bundle
- MuPDF: 1.28.2, PDF-only release build

## Interpretation

This is a settled, many-document idle-state benchmark, not a scrolling or all-pages-rendered stress test. PDFlight intentionally releases rendered images, extracted text, render-cache entries, and the MuPDF store after a window has remained inactive for five seconds. That design explains both its low settled footprint and the larger difference between its two independent rounds. Interactive latency and memory while rapidly switching among all documents should be measured separately.
