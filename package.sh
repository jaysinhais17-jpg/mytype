#!/bin/bash
# Build a shareable MyType.dmg (Apple Silicon). Users add their own API keys inside the app.
set -euo pipefail
cd "$(dirname "$0")"
./bundle.sh
STAGE=build/dmg; rm -rf "$STAGE" build/MyType.dmg; mkdir -p "$STAGE"
cp -R build/MyType.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
MyType: hold Fn, talk, let go, and your words are typed wherever your cursor is.
Free, Mac only (Apple Silicon). You use your own accounts, so nothing goes through anyone else.

1. INSTALL
   - Drag MyType onto the Applications folder.
   - Open it from Applications. macOS will say it can't verify the app (it isn't from the App Store).
     Open System Settings > Privacy & Security, scroll down, click "Open Anyway" next to MyType.
     (Terminal alternative:  xattr -dr com.apple.quarantine /Applications/MyType.app )

2. FOLLOW THE SETUP GUIDE
   MyType opens a guide the first time. It takes about three minutes and walks you through:
   - Speech key: make a free account at console.deepgram.com (new accounts get $200 credit, months of
     normal use). Go to API Keys > Create a New API Key, then paste it in.
   - Cleanup key (optional): a free key from console.groq.com > API Keys. It tidies punctuation and
     filler words. Without it you still get the raw transcript.
   - Permissions: Microphone, Accessibility and Input Monitoring. Click Grant, then switch MyType on.
     If a switch is already on but the guide shows red, turn it off and on again.
   - Fn key: System Settings > Keyboard > "Press (globe) key to" > Do Nothing.
   Reopen the guide any time from MyType > Settings > "Open setup guide".

3. USE IT
   - Hold Fn, speak, release: the text is pasted at your cursor.
   - Double-tap Fn for hands-free mode; tap Fn again to finish.
   - Say "scratch that" to remove what was just typed.
   - Add names and jargon under Dictionary, and shortcuts under Snippets.

PRIVACY
   Audio goes to Deepgram and text to Groq, using your own keys. MyType keeps no copy of your voice
   and has no server. Keys are stored only on your Mac. If you work with patient information, don't
   dictate anything identifiable unless your own agreement with those vendors allows it.

Optional on-device mode (no internet, slower): brew install whisper-cpp
TXT
hdiutil create -volname MyType -srcfolder "$STAGE" -ov -format UDZO build/MyType.dmg >/dev/null
echo "Built build/MyType.dmg"
