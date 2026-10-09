#!/bin/bash
# Builds Clevane.app from the Swift package and signs it ad hoc (no Apple account needed).
# Usage: scripts/build-app.sh [debug|release]   (default: release). Output: Clevane/build/<configuration>/Clevane.app
# Touch ID goes through the Secure Enclave, which works with an ad hoc signature.
set -euo pipefail
configuration="${1:-release}"
root="$(cd "$(dirname "$0")/.." && pwd)"
package="$root/Clevane"

swift build --package-path "$package" -c "$configuration"
binary="$(swift build --package-path "$package" -c "$configuration" --show-bin-path)/Clevane"

app="$package/build/$configuration/Clevane.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Clevane"
if [ -f "$package/Resources/AppIcon.icns" ]; then cp "$package/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"; fi
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>app.clevane.Clevane</string>
  <key>CFBundleName</key><string>Clevane</string>
  <key>CFBundleDisplayName</key><string>Clevane</string>
  <key>CFBundleExecutable</key><string>Clevane</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Yannick Kibale. Apache License 2.0.</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>app.clevane.backup</string>
      <key>UTTypeDescription</key><string>Clevane Backup</string>
      <key>UTTypeConformsTo</key><array><string>com.apple.package</string><string>public.data</string></array>
      <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>cvbackup</string></array></dict>
    </dict>
  </array>
</dict>
</plist>
PLIST
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict "$app"
echo "$app"
