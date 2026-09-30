#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Build the macOS app on a Mac with Xcode 16 or newer."
  exit 1
fi
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
xcrun swift build -c release --arch arm64 --arch x86_64
binary_dir="$(xcrun swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
bundle_dir="$project_dir/dist/QuotaBar.app"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"
cp "$binary_dir/QuotaBar" "$bundle_dir/Contents/MacOS/QuotaBar"
lipo -verify_arch arm64 x86_64 "$bundle_dir/Contents/MacOS/QuotaBar"
cat > "$bundle_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>QuotaBar</string>
  <key>CFBundleDisplayName</key><string>QuotaBar</string>
  <key>CFBundleIdentifier</key><string>com.quotabar.app</string>
  <key>CFBundleExecutable</key><string>QuotaBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
# Ad-hoc signing for local development. Set SIGNING_IDENTITY for Developer ID distribution.
codesign --force --options runtime --sign "${SIGNING_IDENTITY:--}" "$bundle_dir"
codesign --verify --strict "$bundle_dir"
ditto -c -k --sequesterRsrc --keepParent "$bundle_dir" "$project_dir/dist/QuotaBar-macOS.zip"
dmg_stage="$(mktemp -d)"
trap 'rm -rf "$dmg_stage"' EXIT
ditto "$bundle_dir" "$dmg_stage/QuotaBar.app"
ln -s /Applications "$dmg_stage/Applications"
hdiutil create -volname QuotaBar -srcfolder "$dmg_stage" -ov -format UDZO "$project_dir/dist/QuotaBar-macOS.dmg"
hdiutil verify "$project_dir/dist/QuotaBar-macOS.dmg"
echo "Built $bundle_dir"
echo "Run: open '$bundle_dir'"
