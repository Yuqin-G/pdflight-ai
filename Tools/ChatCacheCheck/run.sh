#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
check_root="$(mktemp -d /tmp/pdflight-chat-check.XXXXXX)"
trap 'rm -rf "$check_root"' EXIT
swiftc -parse-as-library "$project_root/Sources/PDFlightApp/ChatHeavyViewCache.swift" \
    "$project_root/Tools/ChatCacheCheck/main.swift" -o "$check_root/cache-check"
"$check_root/cache-check"
if [[ $# -eq 0 ]]; then exit 0; fi
if [[ $# -ne 2 || "$1" != "--renderer" || ! -x "$2" ]]; then
    echo 'Usage: run.sh [--renderer /absolute/path/to/isolated-build/PDFlight]' >&2
    exit 64
fi
# Execute a dedicated synthetic fixture directly, always with a known self-check
# argument. Never launch the app normally or reuse its bundle ID/data directories.
fixture="$check_root/ChatCacheFixture.app/Contents"
mkdir -p "$fixture/MacOS" "$fixture/Resources" "$check_root/home" "$check_root/tmp"
cp "$2" "$fixture/MacOS/PDFlight"
cp -R "$project_root/Resources/HarnessChat" "$fixture/Resources/HarnessChat"
cat > "$fixture/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.pdflight.synthetic-chat-cache-check</string>
<key>CFBundleExecutable</key><string>PDFlight</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
CFFIXED_USER_HOME="$check_root/home" TMPDIR="$check_root/tmp/" \
    PDFLIGHT_CHAT_CACHE_WEB_CHECK=1 "$fixture/MacOS/PDFlight" --self-check-chat-renderer
