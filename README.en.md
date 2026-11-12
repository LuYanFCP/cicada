<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Cicada icon">
</p>

<h1 align="center">Cicada · 知了</h1>

<p align="center">
  Every call. Every stream. No language barrier.<br>
  Understand, speak back, and remember everything. Live meeting notes, bilingual transcripts, subtitles and interpreting on Mac, Windows, Linux and Android.
</p>

<p align="center">
  <a href="https://cicada.indaloop.app"><img src="https://img.shields.io/badge/Website-cicada.indaloop.app-E8552B?style=for-the-badge" alt="Website: cicada.indaloop.app" height="36"></a>
  &nbsp;
  <a href="https://cicada.indaloop.app/en/download/"><img src="https://img.shields.io/badge/Download-Mac%20·%20Windows%20·%20Linux%20·%20Android-15171C?style=for-the-badge" alt="Download for Mac, Windows, Linux and Android" height="36"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.4%2B-black" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Windows-10%202004%2B-black" alt="Windows 10 2004+">
  <img src="https://img.shields.io/badge/Ubuntu-22.04%2B-black" alt="Ubuntu 22.04+">
  <img src="https://img.shields.io/badge/Android-10%2B-black" alt="Android 10+">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0">
</p>

<p align="center"><a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a></p>

Whether you're on Zoom, Teams, Feishu, or Tencent Meeting, or listening to X Spaces or a YouTube livestream, Cicada gives you live bilingual subtitles and writes structured meeting notes as it listens. When it's your turn to speak, hold the talk key (right `⌥` on Mac, right `Ctrl` on Windows) and the other side hears your translated voice right in the call. Cicada reads system audio directly without sending bots into the meeting, so no one else notices a thing. On Apple silicon Macs, all speech recognition runs on device, so audio never leaves your computer.

**Where it works**: Anything that plays sound on your computer. Tencent Meeting, Feishu, DingTalk, WeCom, Zoom, Teams, Google Meet, Webex, Discord, and Telegram voice chats, plus X Spaces, YouTube, Twitch, Bilibili Live, podcasts, and browser-based meetings. On Android, the system blocks recording audio from meeting and call apps—put the call on speaker and use In person instead.

<p align="center">
  <img src="docs/demo.gif" width="800" alt="A Bloomberg English livestream on YouTube with Cicada's live Chinese notes, topics, and fishbone diagram on the right and bilingual subtitles at the bottom">
</p>

## Platforms

| Platform | Requirements | Notes |
|---|---|---|
| Mac | macOS 14.4+, Apple silicon / Intel | Full feature set. On-device recognition on Apple silicon (works without a key); Intel needs a cloud audio-understanding service (Ming by default, or a compatible API) |
| Windows | Windows 10 2004+, x64 / ARM64 | Needs an AI service key (Ling, OpenRouter, ZenMux, etc.); see [windows/](windows/README.md) |
| Linux | Ubuntu 22.04 / 24.04 desktop | Needs an AI service key; the notes window is visible in screen sharing; see [linux/](linux/README.md) |
| Android | Android 10+ | Needs an AI service key; subtitles for videos and streams, face-to-face interpreting; see [android/](android/README.md) |

Installers are available on [the download page](https://cicada.indaloop.app/en/download/) and [Releases](https://github.com/wquguru/cicada/releases). All four platforms share the same version number and meeting record format. The sections below use the Mac app to walk through the features.

## Features

### Live notes and bilingual transcript

As the meeting runs, the notes window organizes a summary, topics and key points, conclusions, to-dos, a fishbone diagram, and a glossary of names and terms. Click any conclusion or to-do to jump straight back to the original lines. Pressing `⌘F` searches both the canonical spelling and misrecognized variants.

With an AI service connected, misheard names and terms are fixed on the spot: sound-alike typos are corrected right away, while unfamiliar names are asked about once and fixed automatically once you confirm. You can paste your usual spellings into **Word list** in Settings. After the meeting, select **Edit line…** to batch-fix the same misheard word across the whole session, with full undo support.

### Live subtitles and language detection

Cicada detects the spoken language within seconds and translates it into your system language; press `⌃⌥S` to switch display modes. The subtitle bar only appears when someone speaks and turns see-through under your pointer so it never blocks buttons. On macOS 26 with Apple silicon, Cicada also re-listens on device to refine each line 15 to 30 seconds later, fixing typos and words lost at line breaks.

### In-person and hybrid meetings

In a meeting room, click **Turn on mic** to listen to people around the table. Hybrid meetings use the exact same button: computer audio is marked **Online** and microphone audio is marked **In room**, combined in a single record (on macOS 14 and 15, turning on the mic listens only to the table). When speaker audio bleeds into the microphone, Cicada automatically ducks and deduplicates it so nothing is recorded twice; with headphones on, both sides can talk at once and both are kept. Windows and Linux follow the same rules.

### Simultaneous interpreting

Hold the right `⌥` key and speak so the other side hears your translated voice in the meeting app. Turning on interpreting automatically switches the system microphone to BlackHole 2ch, a virtual driver you can download and install with one click. With a Ling API key you can use natural voices or clone your own voice from an 8 to 30 second sample; without a key, it uses built-in macOS voices.

<p align="center">
  <img src="docs/interpreting.png" width="640" alt="Interpreting settings showing the right Option talk key, target language, Ming voice previews, and macOS voices">
</p>

### Meeting records

Bilingual transcripts, notes, and raw audio recordings are saved on your computer. Click any line to play the recording from that point. The bundled on-device voiceprint model automatically separates different speakers (and fills in their names when a Ling key is set), and you can rename or merge them anytime if it gets someone wrong. After a meeting, you can generate notes retroactively or export to Markdown, Word, or SRT subtitles. **Share…** turns the notes (and, if you like, the bilingual transcript) into a link with an expiry and an optional password, copied together with one click; before anything is uploaded it is checked for keys, unpublished company information and other sensitive content, and held back if any is found. You can also turn local audio or video files into bilingual records via **File › Import Recording or Video…**. Right now "you" in the record only covers what you say while holding the talk key; capturing what you say directly in the meeting is on the [roadmap](#roadmap).

<p align="center">
  <img src="docs/records.png" width="640" alt="Meeting records window showing identified speakers and a line-by-line English and Chinese transcript">
</p>

## Privacy & Permissions

**Apple silicon Macs**: Audio capture, language detection, speech recognition, and meeting recordings all stay on your computer. The only data that leaves your Mac is the recognized text (sent for translation and meeting notes) and the short voice clips you speak while holding the talk key with cloud audio understanding configured (if a speech model downloads slowly and you click **Use Ling for Now**, or if you switch speech recognition to a self-hosted service on another machine in **Settings › AI Service › Per-feature services**, meeting audio is also sent to that service; a service on this Mac keeps it here). Without an API key, live subtitles, translation, meeting records, and interpreting all work for free. Live notes and one-step voice translation need an AI service configured for them, and voice cloning requires your own Ling (Ant Group's LLM service) API key; an hour of meetings costs roughly ¥0.15 to ¥1 RMB, and Ling provides ¥10 of free credit every month, enough for 10 to 50 hours.

**Intel Macs, Windows, Linux, Android**: Speech recognition runs in the cloud. Spoken audio is sent in segments to Ling's Ming or your chosen service (OpenRouter, ZenMux, etc.; an Intel Mac can also use a compatible audio-understanding API of its own), so an AI service key is required. Recordings and meeting records still stay only on your device.

The Mac app only asks for a permission when you use the corresponding feature, and everything else works normally if you decline:

| Permission | What it's for | Without it |
|---|---|---|
| System audio recording (Screen & System Audio Recording) | Hears system audio for subtitles; never records the screen | Subtitles and notes won't work |
| Microphone | Hold-to-talk interpreting; **Turn on mic** for meeting rooms | Can't speak to translate or listen to the room |
| Input Monitoring | Detects whether right `⌥` is pressed (doesn't block or log other keys) | Switch to a `⌃`/`⌘` shortcut in Settings to skip this permission |
| Administrator password | Installs the BlackHole 2ch virtual microphone (asked once) | The other side can't hear interpreting; everything else works |

- **Transparent networking**: Cicada only connects to the internet for translation (`translate.googleapis.com`), your configured AI service (such as `api.ant-ling.com`), downloading the Apple-notarized BlackHole driver (verified against SHA-256), and checking GitHub once a day for updates. There is no analytics, no tracking, and no server of our own.
- **Local storage**: Records and recordings live in `~/Library/Application Support/LiveSubs`. Your key and voice sample are readable only by your current system account and excluded from Time Machine and logs.
- **Hidden from screen capture**: On Mac, screen sharing, screen recordings, and screenshots cannot capture the notes window; you can manually turn on **Show in screen sharing** when recording a demo.

## Models

The table below shows the setup on Apple silicon Macs. When using a self-hosted service (**Other (OpenAI-compatible)**), you can turn on **Send audio and text only to your service** in **Settings › AI Service** to bypass Google completely.

| Feature | With a Ling key | Without a key / fallback |
|---|---|---|
| Speech recognition and language detection | Apple `SpeechAnalyzer` / `SpeechTranscriber` (on device); macOS 14.4–15 uses `SFSpeechRecognizer` (on device, needs Dictation); or Qwen3-ASR running on this Mac (see below) | Same |
| Translating finished sentences | Ling `Ling-3.1-flash` (can be changed to `Ling-3.0-flash` in Settings › AI Service) | Google Translate → Apple `Translation` (on device, macOS 26 only) |
| Translating the sentence still being spoken | Google Translate | Shows original text until replaced by the full-sentence translation |
| Live notes and post-meeting full version | Ling `Ling-3.1-flash` | Not available |
| Checking if the key works | Ling `Ling-3.0-tiny` (1 token) | — |
| Interpreting: hearing and translating | Ming `Ming-3.0-audio-flash` (one step) | Apple on-device recognition + translation chain above |
| Interpreting: voice output and voice cloning | Ming `Ming-3.0-tts-0.5B` | Built-in Mac voices (`AVSpeechSynthesizer`), no cloning |
| Speaker identification | WeSpeaker ResNet34-LM (bundled, runs on device via Core ML) | Same |

On Mac, **Translation and notes** and **Audio understanding** can each use an OpenAI-compatible API of their own instead of the main service. At the bottom of **Settings › AI Service**, under **Per-feature services**, switch the row from **Same** to **Compatible API**, enter the address (such as `https://api.openai.com/v1`), model and key, then click **Save and check**. Type the model name, or enter the address and key first and click **Read models** next to it to pick from the list. Once the check passes the row folds into one line: the address, the model and how long a sentence takes; when something breaks it opens again and says what. **Translation and notes** takes over completed sentences in meeting subtitles and imported recordings, live and final notes, and speaker-name guesses. The check verifies translation and JSON support; an API without JSON support can still translate but cannot write notes. Partial sentences still use Google → Apple; completed sentences use the same fallback if the API fails. Speech recognition and Ming's audio understanding, interpreting voices and voice cloning stay on the main service. With **Other (OpenAI-compatible)** as the main service, translation and notes are already set up above, so that row isn't repeated. When the notes window or the menu bar reports a problem with this API, **Configure AI service** opens the page at these rows.

**Audio understanding** is **Same** by default (`Ming-3.0-audio-flash` with Ling). On its own API it also needs the format your service accepts: OpenAI (`input_audio`) or Ming-compatible (`audio_url`); Ling's `api.ant-ling.com` picks Ming-compatible by itself. If translation and notes already use a compatible API, **Use the address and key from Translation and notes** brings over the same address and key and reads the model list, so you only pick an audio model. **Save and check** verifies it with one second of real audio. This handles push-to-talk audio understanding and cloud recognition on Intel Macs or when selected manually; Apple silicon Macs still recognize speech on device by default. Each row keeps its own key on the Mac with 0600 permissions, a key brought over is saved as a separate copy and never shown, and speech synthesis and voice cloning keep the existing Ming TTS configuration.

**Speech recognition** stays on device by default on Apple silicon Macs. For more accurate Chinese, dialects and mixed-language speech, switch it to **Your service**: we recommend running Qwen3-ASR on this Mac with [mlx-audio](https://github.com/Blaizzy/mlx-audio), so the meeting's audio still stays on this Mac, whatever the main service is. Install it once in Terminal and start it:

```bash
uv tool install --upgrade "mlx-audio[stt,server]"   # without uv: pip3 install -U "mlx-audio[stt,server]" (Python 3.10+)
mlx_audio.server --port 8000
```

Then under **Per-feature services › Speech recognition**, choose **Your service**: the address `http://localhost:8000/v1` and the model `mlx-community/Qwen3-ASR-1.7B-8bit` are already filled in, so click **Save and check**. The first check downloads about 2.5 GB of model and takes a few minutes. To save memory, use `mlx-community/Qwen3-ASR-0.6B-8bit` (about 1 GB). Measured on an M4 Pro, a 9-second stretch takes about 0.5 s once the model is loaded. With the server on this Mac or the local network, a line shows as a draft while it is still being said, updated about once a second, and the final text replaces it when the sentence ends. It recognizes meetings from the next one on, and when the server is off or unreachable Cicada goes back to on-device recognition by itself. If the first check says the model can't be found, the download most likely failed: see the errors in the Terminal window running the server; if large downloads fail through a proxy, start it with `HF_HUB_DISABLE_XET=1`. Any server with `/audio/transcriptions` works (Qwen3-ASR on vLLM, Whisper…), and addresses on your local network can use http. MLX runs only on Apple silicon: an Intel Mac can use another Apple silicon Mac on the local network (start it there with `--host 0.0.0.0`). Recognition set up earlier under **Other (OpenAI-compatible)** moves here by itself; the steps are also on the website's [setup page](https://cicada.indaloop.app/en/start/#local-asr).

## Setting up a Ling API key

1. Sign up and log in on the [Ling open platform](https://chat.ant-ling.com/platform/api), create a token, and copy the key starting with `sk-`.
2. Open **Settings › AI Service** in Cicada (or the banner at the top of the notes window), paste the key, and save.

**Can't sign up for Ling?** At the top right of **Settings › AI Service** (or by clicking **Can't use Ling?** during onboarding), you can switch to OpenRouter, ZenMux, OpenAI, or any OpenAI-compatible service (including local or LAN services like Ollama, vLLM, and SGLang; in onboarding, **Compatible API** takes an address, model and key, and a service on this Mac or your local network needs no key). Live notes and full-sentence translation work with all of them, and OpenRouter and ZenMux can also use natural Gemini voices for interpreting; voice cloning is supported only by Ling, and on Mac one-step voice translation can also use a compatible audio-understanding API of its own. On Mac, translation and notes, speech recognition and audio understanding can each use a service of their own under **Per-feature services**, whatever the main service is. When Windows, Linux, or Android switches to another service, listening to the other side also goes through that service, so subtitles run 1–2 seconds behind Ling. If a connection fails, Settings tells you directly whether it's a key, model, or proxy issue (see the [setup page](https://cicada.indaloop.app/en/start/#proxy) for proxy details).

## Requirements & Installation

Installers are on the [Releases page](https://github.com/wquguru/cicada/releases/latest) and [the website](https://cicada.indaloop.app), and you can verify SHA-256 checksums against `checksums.txt` in Releases. If you run into questions, reach out to the author [@wquguru](https://x.com/wquguru) on X.

### Mac

Requires macOS 14.4+ (Apple silicon and Intel). On Apple silicon with macOS 14.4–15, first go to **System Settings › Keyboard** to turn on **Dictation** and add the languages you want heard; macOS 26 uses the new on-device model directly without needing Dictation; Intel Macs recognize speech through a cloud audio-understanding service (Ming by default, which needs a Ling key, or a compatible API).

Download `Cicada-<version>-macOS-AppleSilicon.dmg` or `Cicada-<version>-macOS-Intel.dmg` and drag Cicada into Applications (verify with `shasum -a 256 Cicada-*.dmg`). The app is not notarized by Apple yet, so if the first launch is blocked, go to **System Settings › Privacy & Security** and click **Open Anyway**. Follow the onboarding guide to grant permissions and try the sample meeting.

<p align="center">
  <img src="docs/onboarding.png" width="640" alt="Onboarding step 2 playing a two-person sample meeting with live bilingual subtitles">
</p>

### Windows

Requires Windows 10 2004+ (x64 or Snapdragon ARM64). Download the installer and double-click to install without admin rights. If SmartScreen blocks it, click **More info › Run anyway**. When you use interpreting, the guide walks you through installing the free VB-Cable virtual microphone.

### Linux

Requires Ubuntu 22.04 or 24.04 desktop (x86_64 or arm64). Download `Cicada-<version>-Linux.tar.gz` and run `tar xzf Cicada-<version>-Linux.tar.gz && cicada-linux/install.sh` in a terminal. Interpreting automatically creates a "Cicada Microphone" with no driver to install. Linux windows cannot hide from screen sharing, so the notes window indicates that it is visible when sharing your screen. To enable **Settings › General › Save meeting audio**, first install system third-party media formats (such as `ubuntu-restricted-extras`) to provide an AAC encoder. Turning on **Settings › Word list › Fix misheard words live** sends one extra text request per sentence.

### Android

Requires Android 10+. Download and install `Cicada-<version>-Android.apk`; on Android 15 and later, allow restricted settings in App info the first time you turn on floating subtitles. It also includes on-device voiceprints to separate speakers and fixes misheard words live while listening. Call and meeting apps block internal audio capture on Android—just put the call on speaker and switch to **In person**.

## Roadmap

In rough order of priority; feel free to open an Issue for what you'd like to see. See [docs/ROADMAP.md](docs/ROADMAP.md) for details.

- **Record my own speech**: Continuously listen to the microphone with echo cancellation during meetings so what you say directly is also included in records and notes.
- **Code signing and notarization**: Official signing and notarization for Mac and Windows installers to eliminate security prompts and move AI keys back to the system keychain.
- **Speaker recognition**: Remember frequent coworkers' voices on device and recognize them automatically in future meetings.
- **Notes without a key**: Generate meeting notes on supported Macs using Apple's on-device models.
- **Android on app stores**: No more manual APK installs.
- **iPhone and iPad**: Starting with listening to meeting rooms, face-to-face interpreting, and meeting records.

## Uninstall

Quit Cicada and drag it from the Applications folder to the Trash. Meeting records and recordings are in `~/Library/Application Support/LiveSubs` and can be deleted manually if no longer needed. To clear settings, run:

```bash
defaults delete com.wquguru.cicada
```

## Development

The Mac app only requires Xcode Command Line Tools (`xcode-select --install`) and has no third-party dependencies. On macOS 27, if `SwiftUIMacros` is reported missing, install full Xcode and run `sudo xcode-select -s /Applications/Xcode.app`. For building on other platforms, see [windows/README.md](windows/README.md), [linux/README.md](linux/README.md), and [android/README.md](android/README.md).

```bash
scripts/build.sh            # dev build → build/Cicada.app ("Cicada Dev", runs alongside the release app)
open build/Cicada.app
scripts/package.sh          # package release DMG, zip, and SHA-256 checksums
```

See [AGENTS.md](AGENTS.md) for code architecture. The website source is in `site/` (generated by `scripts/site.py`), and release history is in [CHANGELOG.md](CHANGELOG.md) or on the [website changelog](https://cicada.indaloop.app/changelog/).

## License

This project is licensed under [Apache-2.0](LICENSE). The BlackHole 2ch virtual microphone driver is licensed under the GPL; it is not bundled in the installer and is downloaded from its official URL when you click install. The bundled voiceprint model is [WeSpeaker](https://github.com/wenet-e2e/wespeaker)'s ResNet34-LM trained on VoxCeleb (CC BY 4.0), converted to Core ML by `scripts/convert-voiceprint.py`.
