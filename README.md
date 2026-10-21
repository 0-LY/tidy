<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Tidy icon">
</p>

<h1 align="center">Tidy</h1>

<p align="center">
  Select text anywhere on your Mac, press a hotkey, and it comes back fixed.
</p>

<p align="center">
  <a href="https://github.com/0-LY/tidy/releases/latest/download/Tidy.dmg"><b>Download Tidy for macOS</b></a>
  ·
  <a href="https://github.com/0-LY/tidy/releases">All releases</a>
</p>

<p align="center">
  <img src="docs/screenshots/in-use.png" width="560" alt="The Tidy bubble while it fixes your text">
</p>

## What it does

Select text in any app — mail, chat, notes, a browser, a terminal — and press **⌃⌥F** (you can change it).
Tidy fixes the spelling, grammar and punctuation and puts the result back in place of your selection.
A small glass bubble with an animated orb shows above the text while it works.

| Style | What it does |
|---|---|
| Natural | Casual and short, like texting. For chat. |
| Official | Polite full sentences, no slang. For email. |
| Typos only | Fixes spelling, grammar and punctuation; changes nothing else. |

| Model | Notes |
|---|---|
| Haiku 5.5 | Claude Haiku through your own [Claude Code](https://claude.com/claude-code) login, about 3 seconds. No API key. |
| Local | Apple's on-device model (Apple Intelligence). Offline, free, under a second. Shows which of your keyboard languages it doesn't officially support. |

If Claude is unavailable, Tidy can fall back to the local model.

- **Vocabulary** — words Tidy must keep exactly as written, such as product names.
- **Extra** — your own instruction added to every fix, such as "Use British spelling".
- **Services menu** — right-click selected text → Services → **Fix text**.

<p align="center">
  <img src="docs/screenshots/settings-general.png" width="360" alt="General settings">
  <img src="docs/screenshots/settings-writing.png" width="360" alt="Writing settings">
  <img src="docs/screenshots/settings-animation.png" width="360" alt="Animation settings">
  <img src="docs/screenshots/settings-try-it.png" width="360" alt="Try It">
</p>

## Install

> [!IMPORTANT]
> **First launch only.** Tidy isn't notarized by Apple, so macOS blocks it the first time you open it.
> Click **Done**, open **System Settings → Privacy & Security**, scroll down, click **Open Anyway**
> next to "Tidy", then open it again. You do this once; updates install and open normally.

1. [Download Tidy.dmg](https://github.com/0-LY/tidy/releases/latest/download/Tidy.dmg) and open it.
2. Drag **Tidy** onto the **Applications** folder in the window that opens.
3. Open Tidy from Applications and use **Open Anyway** as above.
4. **First launch:** a short setup walks you through allowing **Accessibility** (the button opens that page in
   System Settings; Tidy needs it to copy your selection and paste the fixed text), choosing Local or Haiku,
   your style and hotkey, and a quick try — with a little confetti at the end.
   Run it again any time from the menu: **Set Up Tidy…**

<p align="center">
  <img src="docs/screenshots/setup-welcome.png" width="200" alt="Setup: welcome">
  <img src="docs/screenshots/setup-access.png" width="200" alt="Setup: allow Accessibility">
  <img src="docs/screenshots/setup-model.png" width="200" alt="Setup: choose the model">
  <img src="docs/screenshots/setup-try.png" width="200" alt="Setup: try it">
</p>

Requirements: macOS 26 or later on Apple silicon. For Haiku, install Claude Code and sign in once (`claude`).
For Local, turn on Apple Intelligence.

## Privacy

- Tidy has no account, no analytics and no tracking.
- Your selected text is sent **only** to the model you choose:
  - **Haiku** — sent to Anthropic through your own Claude Code login and processed under your account's privacy settings.
    Tidy runs Claude with no tools, no files and no saved session.
  - **Local** — never leaves your Mac.
- Nothing you fix is logged or saved. Each fix runs in a private temporary folder that is deleted right away.
- Text Tidy puts on the clipboard is marked as temporary, so clipboard-history apps skip it, and your previous clipboard is restored.
- Settings are stored in `~/.config/tidy/config.json`, readable only by you.
- Update checks fetch `https://github.com/0-LY/tidy/releases/latest/download/appcast.xml`. No system profile is sent.

## Updates

Tidy updates itself. Every update is signed, and Tidy refuses any download whose signature doesn't match the key built into the app.

In **Settings → General** you can turn off automatic checks or automatic installs, check now, or switch on
**Get beta updates** to try new features early.

## Build from source

```sh
git clone https://github.com/0-LY/tidy.git
cd tidy
./build.sh
```

`build.sh` builds `Tidy.app`, installs it into `~/Applications`, adds the **Fix text** service and starts it.
You need the Xcode Command Line Tools (`xcode-select --install`). The first build downloads Sparkle
(pinned version, checked against its SHA-256).

Run a fix from the command line:

```sh
echo "helo wrld" | ./Resources/fixer --style minimal --model local
```

| File | Purpose |
|---|---|
| `Sources/Tidy.swift` | App, menu bar, settings window |
| `Sources/Hotkey.swift` | Global hotkey, copy → fix → paste |
| `Sources/HUD.swift` | Glass bubble and its placement |
| `Sources/Updates.swift` | Automatic updates (Sparkle) |
| `Sources/LocalFix.swift` | Apple on-device model and shared clean-up |
| `Sources/Signal.swift` | Clipboard and bubble helper for the Services action |
| `Resources/fixer` | Prompt rules, model calls, fallback |
| `Sources/Identity.swift` | Name, bundle ID and settings folder, read from the built app |
| `app.env` | Name, publisher, GitHub owner and repo, version |
| `Resources/` | Entitlements, the `fixer` script and the Fix text service |
| `scripts/` | Build and Sparkle download scripts; `scripts/icon/` makes the app icon |

## Credits

Orb animation: [Thinking orbs](https://libraries.dev/orbs) by Jakub Antalik (MIT, see `Sources/ThinkingOrbsKit/LICENSE`).
Updates: [Sparkle](https://sparkle-project.org) (MIT).

## License

[MIT](LICENSE) © 0-LY
