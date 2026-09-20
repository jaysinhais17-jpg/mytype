# MyType

Free dictation for Mac. Hold **fn**, say what you want to write, let go, and your words are typed wherever your cursor is, in any app. Punctuation and "um"s are cleaned up for you.

Created by Jay Sinha.

## Download

Grab **MyType.dmg** from the [latest release](../../releases/latest).

Requires a Mac with **Apple Silicon** (M1 or newer) and **macOS 13 or later**.

## Install

1. Open `MyType.dmg` and drag **MyType** into **Applications**.
2. **First launch only:** macOS will say it can't verify MyType, because the app is not notarized (that needs a paid Apple developer account). It is safe to open:
   - Try to open MyType once and dismiss the warning.
   - Go to **System Settings > Privacy & Security**, scroll down, and click **Open Anyway** next to MyType, then confirm.
   - On macOS 14 or earlier you can instead right-click MyType and choose **Open**.
   - Still stuck? Run `xattr -dr com.apple.quarantine /Applications/MyType.app` in Terminal, then open it again.
3. Follow the in-app setup guide (about 3 minutes).

## How it works

MyType is bring-your-own-keys, so it costs nothing to run beyond the free tiers:

- **Speech to text:** [Deepgram](https://console.deepgram.com) (new accounts get $200 of free credit).
- **Cleanup:** [Groq](https://console.groq.com) (free tier).

Your keys are stored on your Mac only. Audio goes to Deepgram and text to Groq using your own accounts. Nothing passes through anyone else, and MyType keeps no copy of your voice.

## Shortcuts

- **Hold fn:** talk, release to paste. Double-tap fn for hands-free, tap once to stop.
- **Right Option** also works: hold to talk, tap once for hands-free.

Both can be changed in Settings.

## Build from source

```bash
./install.sh                 # build and install to ~/Applications
VERSION=1.0 ./package.sh     # build build/MyType.dmg
```

Needs Xcode command line tools (`swiftc`).

Publishing a new build (maintainers): `./release.sh "what changed"` commits, pushes, rebuilds the DMG and replaces it on the GitHub release. Add a version (`./release.sh "what changed" 1.1`) to cut a new release.

## License

See [LICENSE](LICENSE).
