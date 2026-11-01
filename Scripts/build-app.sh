#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
APP_ROOT="$PROJECT_ROOT/dist/PDFlight.app"
STAGING_ROOT=$(mktemp -d -t pdflight-app-build)
STAGING_APP="$STAGING_ROOT/PDFlight.app"

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

"$SCRIPT_DIR/bootstrap-mupdf.sh"
swift build --package-path "$PROJECT_ROOT" -c release --product PDFlight
BIN_DIR=$(swift build --package-path "$PROJECT_ROOT" -c release --show-bin-path)

mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources" "$PROJECT_ROOT/dist"
cp "$BIN_DIR/PDFlight" "$STAGING_APP/Contents/MacOS/PDFlight"
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGING_APP/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/PDFlight.icns" "$STAGING_APP/Contents/Resources/PDFlight.icns"
for resource_bundle in "$BIN_DIR"/*.bundle(N); do
    cp -R "$resource_bundle" "$STAGING_APP/Contents/Resources/"
done
UWA_HOME="$PROJECT_ROOT/Services/uwa-lite"
if [[ -d "$UWA_HOME" && -d "$UWA_HOME/.venv" ]]; then
    RSYNC_EXCLUDES=(
        --exclude '.env' --exclude 'logs/' --exclude '__pycache__/'
        --exclude '*.pyc' --exclude '*.sqlite3' --exclude '*.sqlite3-*'
        --exclude 'bin/' --exclude 'pyvenv.cfg'
    )
    mkdir -p "$STAGING_APP/Contents/Resources/uwa-lite"
    rsync -a "${RSYNC_EXCLUDES[@]}" \
        "$UWA_HOME/main.py" "$UWA_HOME/browser_ensure.py" \
        "$UWA_HOME/requirements.txt" "$UWA_HOME/app" "$UWA_HOME/config" \
        "$UWA_HOME/.venv" \
        "$STAGING_APP/Contents/Resources/uwa-lite/"
    find "$STAGING_APP/Contents/Resources/uwa-lite" \
        -type d -name '__pycache__' -prune -exec rm -rf {} +
    UWA_RUNTIME=$(sed -n 's/^executable = //p' "$UWA_HOME/.venv/pyvenv.cfg" \
        | xargs dirname 2>/dev/null | xargs dirname 2>/dev/null || true)
    if [[ -n "${UWA_RUNTIME:-}" && -x "$UWA_RUNTIME/bin/python3" ]]; then
        rsync -a --delete "$UWA_RUNTIME/" \
            "$STAGING_APP/Contents/Resources/uwa-lite/runtime/"
    fi
fi
mkdir -p "$STAGING_APP/Contents/Resources/ThirdParty"
cp "$PROJECT_ROOT/.build/checkouts/iosMath/LICENSE" \
    "$STAGING_APP/Contents/Resources/ThirdParty/iosMath-LICENSE.txt"
cp "$PROJECT_ROOT/.build/checkouts/iosMath/iosMath/fonts/GUST-FONT-LICENSE.txt" \
    "$STAGING_APP/Contents/Resources/ThirdParty/GUST-FONT-LICENSE.txt"
cp "$PROJECT_ROOT/.build/checkouts/Yams/LICENSE" \
    "$STAGING_APP/Contents/Resources/ThirdParty/Yams-LICENSE.txt"
codesign --force --deep --sign - "$STAGING_APP" >/dev/null

rm -rf "$APP_ROOT"
mv "$STAGING_APP" "$APP_ROOT"

echo "$APP_ROOT"
