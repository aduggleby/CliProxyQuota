#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_FLAGS=(-c release)
if [[ "${1:-}" == "--universal" ]]; then BUILD_FLAGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_FLAGS[@]}"
BIN_DIR=$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)
APP="build/CliProxy Quota.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CliProxyQuota" "$APP/Contents/MacOS/CliProxyQuota"
for RESOURCE_BUNDLE in "$BIN_DIR"/*.bundle; do
    [[ -d "$RESOURCE_BUNDLE" ]] || continue
    ditto "$RESOURCE_BUNDLE" "$APP/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"
done
swiftc Sources/CliProxyQuota/QuotaBotIcon.swift scripts/make-icon.swift -o build/make-icon
build/make-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CliProxyQuota</string>
<key>CFBundleIdentifier</key><string>io.github.aduggleby.CliProxyQuota</string>
<key>CFBundleName</key><string>CliProxy Quota</string>
<key>CFBundleDisplayName</key><string>CliProxy Quota</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.7</string>
<key>CFBundleVersion</key><string>19</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
# Local builds are ad-hoc signed. A Developer ID is needed for notarized distribution.
codesign --force --sign - --identifier io.github.aduggleby.CliProxyQuota "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
