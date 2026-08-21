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
mkdir -p "$STAGING_APP/Contents/Resources/ThirdParty"
cp "$PROJECT_ROOT/.build/checkouts/iosMath/LICENSE" \
    "$STAGING_APP/Contents/Resources/ThirdParty/iosMath-LICENSE.txt"
cp "$PROJECT_ROOT/.build/checkouts/iosMath/iosMath/fonts/GUST-FONT-LICENSE.txt" \
    "$STAGING_APP/Contents/Resources/ThirdParty/GUST-FONT-LICENSE.txt"
codesign --force --deep --sign - "$STAGING_APP" >/dev/null

rm -rf "$APP_ROOT"
mv "$STAGING_APP" "$APP_ROOT"

echo "$APP_ROOT"
