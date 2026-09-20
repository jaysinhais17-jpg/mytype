#!/bin/bash
# Build a shareable MyType.dmg (Apple Silicon). Users add their own API keys inside the app.
set -euo pipefail
cd "$(dirname "$0")"
[ -n "${SKIP_BUILD:-}" ] || ./bundle.sh
STAGE=build/dmg; RW=build/MyType-rw.dmg; OUT=build/MyType.dmg
rm -rf "$STAGE" "$RW" "$OUT"; mkdir -p "$STAGE"
cp -R build/MyType.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil detach "/Volumes/MyType" >/dev/null 2>&1 || true
hdiutil create -volname MyType -srcfolder "$STAGE" -ov -format UDRW "$RW" >/dev/null
hdiutil attach "$RW" -mountpoint /Volumes/MyType -nobrowse >/dev/null
# Lay the window out: MyType on the left, Applications on the right. No background image on
# purpose: Finder then uses the viewer's own light/dark theme.
osascript >/dev/null 2>&1 <<'AS' || echo "note: couldn't style the DMG window (Finder automation not allowed); it still works."
tell application "Finder"
  tell disk "MyType"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 460}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set position of item "MyType.app" of container window to {150, 160}
    set position of item "Applications" of container window to {390, 160}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
AS
sync
hdiutil detach /Volumes/MyType >/dev/null
hdiutil convert "$RW" -format UDZO -o "$OUT" >/dev/null
rm -f "$RW"
echo "Built $OUT"
