#!/bin/bash
# Build a shareable MyType.dmg (Apple Silicon). Users add their own API keys inside the app.
set -euo pipefail
cd "$(dirname "$0")"
./bundle.sh
STAGE=build/dmg; rm -rf "$STAGE" build/MyType.dmg; mkdir -p "$STAGE"
cp -R build/MyType.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
MyType: hold Fn and talk, release, and your words are typed where your cursor is.

INSTALL
1. Drag MyType into Applications.
2. First launch: this app isn't from the App Store, so macOS will block it.
   Open System Settings > Privacy & Security, scroll down and click "Open Anyway" next to MyType.
   (Or in Terminal:  xattr -dr com.apple.quarantine /Applications/MyType.app )
3. Allow Microphone, Input Monitoring and Accessibility when asked (Settings > Privacy & Security).

ADD YOUR KEYS (in MyType > Settings)
- Speech: a Deepgram API key (console.deepgram.com, new accounts get free credit).
- Cleanup (optional): a Groq API key (console.groq.com), free tier available.
Keys are stored only on your Mac and sent only to those providers.

PRIVACY: dictation audio goes to Deepgram and text to Groq using your keys. Don't dictate patient-identifiable
information unless your own agreement with those vendors allows it. Optional on-device mode: brew install whisper-cpp.
TXT
hdiutil create -volname MyType -srcfolder "$STAGE" -ov -format UDZO build/MyType.dmg >/dev/null
echo "Built build/MyType.dmg"
