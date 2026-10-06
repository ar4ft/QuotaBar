#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Build the macOS app on a Mac with Xcode 26.2 or newer."
  exit 1
fi
build_mode="${1:---unsigned}"
if [[ $# -gt 1 || ( "$build_mode" != "--unsigned" && "$build_mode" != "--signed" ) ]]; then
  echo "Usage: $0 [--unsigned | --signed]" >&2
  exit 1
fi
if [[ "$build_mode" == "--signed" ]]; then
  if [[ "${GITHUB_ACTIONS:-}" == "true" && "${GITHUB_EVENT_NAME:-}" != "workflow_dispatch" ]]; then
    echo "Signed CI builds are allowed only for a manually dispatched action." >&2
    exit 1
  fi
  if [[ "${SIGNING_IDENTITY:-}" != "Developer ID Application:"* ]]; then
    echo "--signed requires a Developer ID Application SIGNING_IDENTITY." >&2
    exit 1
  fi
fi
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
xcrun swift build -c release --arch arm64 --arch x86_64
binary_dir="$(xcrun swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
bundle_dir="$project_dir/dist/QuotaBar.app"
rm -rf "$bundle_dir"
mkdir -p "$bundle_dir/Contents/Frameworks" "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"
cp "$binary_dir/QuotaBar" "$bundle_dir/Contents/MacOS/QuotaBar"
lipo "$bundle_dir/Contents/MacOS/QuotaBar" -verify_arch arm64 x86_64
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
  <key>CFBundleShortVersionString</key><string>0.10.0</string>
  <key>CFBundleVersion</key><string>11</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleIconFile</key><string>QuotaBar</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
xcrun swift "$project_dir/scripts/render-icon.swift" "$project_dir/dist"
iconutil -c icns "$project_dir/dist/QuotaBar.iconset" -o "$bundle_dir/Contents/Resources/QuotaBar.icns"
# Embed the pinned Sparkle framework and its license, preserving symlinks.
sparkle_framework="$(find "$project_dir/.build/artifacts" -type d -path '*/macos-arm64_x86_64/Sparkle.framework' -print -quit)"
test -n "$sparkle_framework"
ditto "$sparkle_framework" "$bundle_dir/Contents/Frameworks/Sparkle.framework"
sparkle_root="${sparkle_framework%/Sparkle.xcframework/*}"
cp "$sparkle_root/LICENSE" "$bundle_dir/Contents/Resources/Sparkle-LICENSE.txt"
if [[ "$build_mode" == "--signed" && -n "${UPDATE_PUBLIC_KEY:-}" ]]; then
  if [[ "${SIGNING_IDENTITY:--}" == "-" ]]; then
    echo "Update-enabled builds require a Developer ID signing identity." >&2
    exit 1
  fi
  export QUOTABAR_BUNDLE_DIR="$bundle_dir"
  python3 - <<'PYKEY'
import base64, os, plistlib
from pathlib import Path
key = os.environ['UPDATE_PUBLIC_KEY'].strip()
if len(base64.b64decode(key, validate=True)) != 32:
    raise SystemExit('UPDATE_PUBLIC_KEY must be a 32-byte Ed25519 public key.')
p = Path(os.environ['QUOTABAR_BUNDLE_DIR']) / 'Contents/Info.plist'
info = plistlib.loads(p.read_bytes())
info.update(SUPublicEDKey=key, SUFeedURL='https://github.com/ar4ft/QuotaBar/releases/latest/download/appcast.xml',
            SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
            SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUEnableSystemProfiling=False)
p.write_bytes(plistlib.dumps(info))
PYKEY
fi
if [[ "$build_mode" == "--signed" ]]; then
  identity="$SIGNING_IDENTITY"
  signing_flags=(--force --sign "$identity" --options runtime --timestamp)
  framework="$bundle_dir/Contents/Frameworks/Sparkle.framework"
  for helper in "$framework/Versions/B/XPCServices/Downloader.xpc" \
                "$framework/Versions/B/XPCServices/Installer.xpc" \
                "$framework/Versions/B/Updater.app" \
                "$framework/Versions/B/Autoupdate"; do
    codesign "${signing_flags[@]}" --preserve-metadata=entitlements "$helper"
  done
  codesign "${signing_flags[@]}" "$framework"
  codesign "${signing_flags[@]}" "$bundle_dir"
  codesign --verify --deep --strict "$bundle_dir"
  if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    test "$identity" != "-"
    notary_flags=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
    if [[ -n "${NOTARY_KEYCHAIN_PATH:-}" ]]; then notary_flags+=(--keychain "$NOTARY_KEYCHAIN_PATH"); fi
    submission="$project_dir/dist/QuotaBar-notary.zip"
    ditto -c -k --sequesterRsrc --keepParent "$bundle_dir" "$submission"
    xcrun notarytool submit "$submission" "${notary_flags[@]}" --wait
    rm -f "$submission"
    xcrun stapler staple "$bundle_dir"
    xcrun stapler validate "$bundle_dir"
    spctl --assess --type execute --verbose "$bundle_dir"
  fi
else
  # Keep only the compiler's platform-required ad-hoc executable signature.
  # Do not sign the app bundle, re-sign Sparkle, enable updates, or notarize.
  echo "Development build: no Developer ID signing or notarization."
fi
ditto -c -k --sequesterRsrc --keepParent "$bundle_dir" "$project_dir/dist/QuotaBar-macOS.zip"
dmg_stage="$(mktemp -d)"
trap 'rm -rf "$dmg_stage"' EXIT
ditto "$bundle_dir" "$dmg_stage/QuotaBar.app"
ln -s /Applications "$dmg_stage/Applications"
hdiutil create -volname QuotaBar -srcfolder "$dmg_stage" -ov -format UDZO "$project_dir/dist/QuotaBar-macOS.dmg"
if [[ "$build_mode" == "--signed" ]]; then
  codesign "${signing_flags[@]}" "$project_dir/dist/QuotaBar-macOS.dmg"
  if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    xcrun notarytool submit "$project_dir/dist/QuotaBar-macOS.dmg" "${notary_flags[@]}" --wait
    xcrun stapler staple "$project_dir/dist/QuotaBar-macOS.dmg"
    xcrun stapler validate "$project_dir/dist/QuotaBar-macOS.dmg"
  fi
fi
hdiutil verify "$project_dir/dist/QuotaBar-macOS.dmg"
echo "Built $bundle_dir"
echo "Run: open '$bundle_dir'"
