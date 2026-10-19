#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
source "$root/scripts/identity.sh"
source "$root/version.env"
VERSION="${RELEASE_VERSION:-$VERSION}"
BUILD="${RELEASE_BUILD:-$BUILD}"
out="$root/build"
app="$out/$APP_NAME.app"
sparkle="$root/vendor/Sparkle"
target="arm64-apple-macos26.0"

"$root/scripts/fetch-sparkle.sh"
mkdir -p "$out"

swiftc -O -parse-as-library -target "$target" -F "$sparkle" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "$root/Tidy.swift" "$root/Identity.swift" "$root/HUD.swift" "$root/Hotkey.swift" "$root/Updates.swift" \
  "$root"/vendor/ThinkingOrbsKit/*.swift -o "$out/app-binary"
swiftc -O -parse-as-library -target "$target" "$root/Signal.swift" -o "$out/fixer-signal" 2>/dev/null \
  || swiftc -O -target "$target" "$root/Signal.swift" -o "$out/fixer-signal"
swiftc -O -parse-as-library -target "$target" "$root/LocalFix.swift" -o "$out/fixer-local"
swiftc -O "$root/make-icon.swift" -o "$out/make-icon"

ictool="$HOME/Applications/Icon Composer.app/Contents/Executables/ictool"
[[ -x "$ictool" ]] || ictool="/Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ -x "$ictool" ]]; then
  python3 -I "$root/icon/make-icon-doc.py" "$out/AppIcon.icon" "${APP_ICON:-feather}" "${APP_THEME:-graphite}" >/dev/null
  "$ictool" "$out/AppIcon.icon" --export-image --output-file "$out/icon-glass.png" \
    --platform macOS --rendition Default --width 824 --height 824 --scale 1 >/dev/null
  "$out/make-icon" --compose "$out/icon-glass.png" "$out/icon-1024.png" >/dev/null
else
  "$out/make-icon" "$out/icon-1024.png" >/dev/null
fi
iconset="$out/AppIcon.iconset"
rm -rf "$iconset"; mkdir -p "$iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$out/icon-1024.png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$out/icon-1024.png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$out/AppIcon.icns"

rm -rf "$out"/*.app(N)
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$out/app-binary" "$app/Contents/MacOS/$EXECUTABLE"
cp "$out/fixer-local" "$out/fixer-signal" "$app/Contents/MacOS/"
cp "$root/fixer" "$app/Contents/Resources/fixer"
cp "$out/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
chmod 755 "$app/Contents/MacOS/"* "$app/Contents/Resources/fixer"
ditto "$sparkle/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
rm -rf "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
  "$app/Contents/Frameworks/Sparkle.framework/XPCServices"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© $PUBLISHER · MIT License</string>
  <key>AppConfigDirName</key><string>$CONFIG_DIR_NAME</string>
  <key>AppRepoURL</key><string>$REPO_URL</string>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAllowsAutomaticUpdates</key><true/>
  <key>SUAutomaticallyUpdate</key><true/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$app/Contents/Info.plist" >/dev/null

sign_id="$SIGN_IDENTITY"
if ! security find-certificate -c "$sign_id" >/dev/null 2>&1; then
  [[ "${IDENTITY_RELEASE:-0}" == 1 ]] && { print -u2 "Signing certificate '$sign_id' not found. Run scripts/make-cert.sh."; exit 1; }
  sign_id="-"
fi
sign() { codesign --force --timestamp=none --options runtime --sign "$sign_id" "$@"; }
fw="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$fw/Autoupdate"
sign "$fw/Updater.app"
sign "$app/Contents/Frameworks/Sparkle.framework"
sign "$app/Contents/MacOS/fixer-local"
sign "$app/Contents/MacOS/fixer-signal"
sign --entitlements "$root/Tidy.entitlements" "$app"
codesign --verify --deep --strict "$app"
print -r -- "$app"
