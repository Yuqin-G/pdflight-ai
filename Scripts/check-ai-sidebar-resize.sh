#!/bin/zsh
set -euo pipefail

if (( $# != 5 )); then
    echo "usage: $0 <pid> <from-x> <from-y> <to-x> <to-y>" >&2
    exit 2
fi

app_selector="pid:$1"
from_x="$2"
from_y="$3"
to_x="$4"
to_y="$5"
window_id=$(orca computer list-windows --app "$app_selector" --json \
    | jq -r '.result.windows[0].id')

read_ai_splitter_value() {
    local snapshot value
    for _ in 1 2 3; do
        snapshot=$(orca computer get-app-state \
            --app "$app_selector" \
            --window-id "$window_id" \
            --restore-window \
            --json 2>/dev/null) || continue
        value=$(print -r -- "$snapshot" \
            | jq -r '.result.snapshot.treeText' \
            | rg -o 'splitter, Value: [0-9.]+' \
            | tail -1 \
            | rg -o '[0-9.]+$') || continue
        print -r -- "$value"
        return 0
    done
    return 1
}

before=$(read_ai_splitter_value)
orca computer drag \
    --app "$app_selector" \
    --window-id "$window_id" \
    --from-x "$from_x" \
    --from-y "$from_y" \
    --to-x "$to_x" \
    --to-y "$to_y" \
    --json >/dev/null
after=$(read_ai_splitter_value)

if [[ "$before" == "$after" ]]; then
    echo "FAIL: Ask PDF splitter remained at $after after drag" >&2
    exit 1
fi

echo "PASS: Ask PDF splitter moved from $before to $after"
