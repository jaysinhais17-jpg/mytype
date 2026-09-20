#!/bin/bash
# Build release binary and wrap it in a signed .app so macOS permissions stick.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
# Workaround: CLT ships a stale usr/include/swift/module.modulemap that duplicates bridging.modulemap.
# Blank it via a VFS overlay instead of touching system files.
: > build/empty.modulemap
cat > build/vfs.json <<VFS
{"version":0,"roots":[{"name":"/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap","type":"file","external-contents":"$PWD/build/empty.modulemap"}]}
VFS
swiftc -O -Xcc -ivfsoverlay -Xcc "$PWD/build/vfs.json" -vfsoverlay "$PWD/build/vfs.json" \
  -module-cache-path build/mc2 -o build/MyType-bin Sources/MyType/*.swift
APP=build/MyType.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp build/MyType-bin "$APP/Contents/MacOS/MyType"
mkdir -p "$APP/Contents/Resources"; cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MyType</string>
<key>CFBundleIdentifier</key><string>com.jay.mytype</string>
<key>CFBundleExecutable</key><string>MyType</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>${VERSION:-$(cat .version 2>/dev/null || echo 1.0)}</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Jay Sinha. MIT License.</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDisplayName</key><string>MyType</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSMicrophoneUsageDescription</key><string>MyType records your voice locally to transcribe it.</string>
</dict></plist>
PL
# Fixed designated requirement (bundle id only) so macOS keeps privacy permissions across rebuilds.
codesign --force --sign - -r='designated => identifier "com.jay.mytype"' "$APP"
echo "Built $APP"
