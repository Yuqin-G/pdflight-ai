#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ( "$1" != "10" && "$1" != "30" ) ]]; then
    echo "usage: benchmark-memory.sh <10|30>" >&2
    exit 2
fi

project_root="$(cd "$(dirname "$0")/.." && pwd)"
pdflight_app="$project_root/dist/PDFlight.app"
skim_app="/Applications/Skim.app"
pdf_count="$1"
settle_seconds=10
sample_count=5
sample_delay=1
max_stability_samples=60
stability_tolerance_percent=5
window_counter="$(mktemp -t pdflight-window-count)"
footprint_reader="$(mktemp -t pdflight-footprint)"
application_launcher="$(mktemp -t pdflight-app-launcher)"
temporary_files=("$window_counter" "$footprint_reader" "$application_launcher")
launched_process_ids=()

cleanup() {
    for process_id in "${launched_process_ids[@]}"; do
        kill -TERM "$process_id" 2>/dev/null || true
    done
    for temporary_file in "${temporary_files[@]}"; do
        [[ -f "$temporary_file" ]] && rm -f "$temporary_file"
    done
}
trap cleanup EXIT INT TERM

if [[ ! -x "$pdflight_app/Contents/MacOS/PDFlight" ]]; then
    echo "PDFlight release app is missing. Run Scripts/build-app.sh first." >&2
    exit 1
fi
if [[ ! -d "$skim_app" ]]; then
    echo "Skim is not installed in /Applications." >&2
    exit 1
fi

pdfs=()
while IFS= read -r pdf_file; do
    pdfs+=("$pdf_file")
    [[ ${#pdfs[@]} -eq $pdf_count ]] && break
done < <(rg --files /Users/yq/Zotero/storage -g '*.pdf' | LC_ALL=C sort)

if [[ ${#pdfs[@]} -ne $pdf_count ]]; then
    echo "Expected $pdf_count Zotero PDFs, found ${#pdfs[@]}." >&2
    exit 1
fi

/usr/bin/xcrun swiftc -framework CoreGraphics \
    "$project_root/Scripts/window-count.swift" \
    -o "$window_counter"
/usr/bin/xcrun swiftc \
    "$project_root/Scripts/memory-footprint.swift" \
    -o "$footprint_reader"
/usr/bin/xcrun swiftc -parse-as-library \
    "$project_root/Scripts/launch-isolated-app.swift" \
    -o "$application_launcher"

launch_application() {
    local application="$1"
    local application_path
    if [[ "$application" == "PDFlight" ]]; then
        application_path="$pdflight_app"
    else
        application_path="$skim_app"
    fi

    launched_process_id="$("$application_launcher" "$application_path" "${pdfs[@]}")"
    launched_process_ids+=("$launched_process_id")
}

wait_for_documents() {
    local application="$1"
    local process_id="$2"
    local stable_checks=0
    local attempt=0
    local window_count=0
    while [[ $attempt -lt 240 ]]; do
        window_count="$($window_counter "$process_id")"
        if [[ "$window_count" -eq "$pdf_count" ]]; then
            stable_checks=$((stable_checks + 1))
        else
            stable_checks=0
        fi
        if [[ $stable_checks -ge 4 ]]; then
            echo "$application ready: $window_count windows" >&2
            echo "$window_count"
            return 0
        fi
        sleep 0.25
        attempt=$((attempt + 1))
    done
    echo "$application opened only $window_count qualifying windows." >&2
    return 1
}

sample_process() {
    local application="$1"
    local round="$2"
    local process_id="$3"
    local window_count="$4"
    local sample_file
    sample_file="$(mktemp -t pdflight-memory-samples)"
    temporary_files+=("$sample_file")

    echo "$application round $round: minimum ${settle_seconds}s settling period" >&2
    sleep "$settle_seconds"

    local index=0
    local stable="no"
    while [[ $index -lt $max_stability_samples ]]; do
        "$footprint_reader" "$process_id" >> "$sample_file"
        index=$((index + 1))
        if [[ $index -ge $sample_count ]]; then
            if tail -n "$sample_count" "$sample_file" | /usr/bin/awk \
                -v tolerance="$stability_tolerance_percent" '
                BEGIN { min = -1; max = 0 }
                {
                    total += $1
                    if (min < 0 || $1 < min) min = $1
                    if ($1 > max) max = $1
                }
                END {
                    mean = total / NR
                    exit !((max - min) / mean * 100 <= tolerance)
                }
            '; then
                stable="yes"
                break
            fi
        fi
        sleep "$sample_delay"
    done

    local stabilized_after_seconds=$((settle_seconds + index - 1))
    echo "$application round $round: stable=$stable after ${stabilized_after_seconds}s" >&2

    tail -n "$sample_count" "$sample_file" | /usr/bin/awk -v label="$application" \
        -v round="$round" \
        -v pid="$process_id" \
        -v windows="$window_count" \
        -v settle="$settle_seconds" \
        -v stabilized_after="$stabilized_after_seconds" \
        -v stable="$stable" \
        -v samples="$sample_count" '
        BEGIN { min = -1; max = 0 }
        {
            total += $1
            if (min < 0 || $1 < min) min = $1
            if ($1 > max) max = $1
        }
        END {
            mib = 1048576
            printf "%s,%s,%s,%s,%s,%s,%s,%s,%.1f,%.1f,%.1f\n", \
                label, round, pid, windows, settle, stabilized_after, stable, samples, \
                total / NR / mib, min / mib, max / mib
        }
    '
}

stop_process() {
    local process_id="$1"
    kill -TERM "$process_id" 2>/dev/null || true
    local attempt=0
    while kill -0 "$process_id" 2>/dev/null && [[ $attempt -lt 40 ]]; do
        sleep 0.25
        attempt=$((attempt + 1))
    done
    sleep 1
}

run_trial() {
    local application="$1"
    local round="$2"
    launch_application "$application"
    local process_id="$launched_process_id"
    local window_count
    window_count="$(wait_for_documents "$application round $round" "$process_id")"
    sample_process "$application" "$round" "$process_id" "$window_count"
    stop_process "$process_id"
}

echo "results"
echo "application,round,pid,windows,minimum_settle_seconds,stabilized_after_seconds,stable,samples,mean_phys_mib,min_phys_mib,max_phys_mib"
run_trial PDFlight 1
run_trial Skim 1
run_trial Skim 2
run_trial PDFlight 2

echo "corpus"
for pdf_file in "${pdfs[@]}"; do
    printf '%s\n' "$pdf_file"
done
