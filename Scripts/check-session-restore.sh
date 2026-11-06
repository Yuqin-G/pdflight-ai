#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
swift build --product PDFlight
CHECK_ROOT="$(mktemp -d /private/tmp/pdflight-session-check.XXXXXX)"
trap 'rm -rf "$CHECK_ROOT"' EXIT
CHECK_APP="$CHECK_ROOT/SessionCheck.app"
mkdir -p "$CHECK_APP/Contents/MacOS" "$CHECK_APP/Contents/Resources" "$CHECK_ROOT/home/Library" "$CHECK_ROOT/tmp"
cp .build/debug/PDFlight "$CHECK_APP/Contents/MacOS/SessionCheck"
# A distinct bundle domain plus a fixed CF HOME keeps AppKit/defaults out of the real app state.
cat > "$CHECK_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.pdflight.session-check.$(uuidgen)</string>
<key>CFBundleExecutable</key><string>SessionCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
cp -R Resources/HarnessChat "$CHECK_APP/Contents/Resources/HarnessChat"
if [ -d .build/debug/iosMath_iosMath.bundle ]; then
    cp -R .build/debug/iosMath_iosMath.bundle "$CHECK_APP/Contents/Resources/"
fi
# Restrict real-user state and network as an additional guard. Nothing launches through LaunchServices.
cat > "$CHECK_ROOT/isolation.sb" <<PROFILE
(version 1)
(allow default)
(deny network-outbound)
(deny file-read* file-write* (subpath "$HOME/Library/Application Support/dev.pdflight.reader"))
(deny file-read* file-write* (subpath "$HOME/.dsh"))
(deny file-read* file-write* (subpath "$HOME/Library/Keychains"))
(deny file-read* file-write* (regex #"^$HOME/Library/Preferences/(dev[.]pdflight[.]reader|PDFlight)([.]|/)"))
PROFILE
CFFIXED_USER_HOME="$CHECK_ROOT/home" TMPDIR="$CHECK_ROOT/tmp/" \
PDFLIGHT_SELF_CHECK_HOME="$CHECK_ROOT/home" PDFLIGHT_SKIP_HARNESS_MODEL_IMPORT=1 \
PDFLIGHT_HARNESS_DRAFT_DIRECTORY="$CHECK_ROOT/no-harness-drafts" \
/usr/bin/sandbox-exec -f "$CHECK_ROOT/isolation.sb" "$CHECK_APP/Contents/MacOS/SessionCheck" --self-check-group-tabs
