# MyType

Free dictation for Mac. Hold **fn**, say what you want to write, let go, and your words are typed wherever your cursor is, in any app. Punctuation and "um"s are cleaned up for you.

Created by Jay Sinha.

## Download

Grab **MyType.dmg** from the [latest release](../../releases/latest).

Requires a Mac with **Apple Silicon** (M1 or newer) and **macOS 13 or later**.

## Install

1. Open `MyType.dmg` and drag **MyType** into **Applications**.
2. **First launch only:** right-click MyType, choose **Open**, then click **Open** again. macOS shows a warning because the app is not notarized (that needs a paid Apple developer account). If Open is not offered, go to System Settings > Privacy & Security and click **Open Anyway**.
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

## License

See [LICENSE](LICENSE).
