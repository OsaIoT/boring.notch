# Boring Notch+

**Your MacBook's notch, turned into a practice companion.**

Boring Notch+ is a fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch) that adds a **Focus** tab: a stopwatch that lives in the notch, and one-click recording of your webcam, your screen, or both. Film yourself solving a problem out loud, then watch it back to see where you got stuck and how you got out.

It was built for LeetCode-style practice and mock interviews, but it works for any focused session. Everything boring.notch already does (music controls, the file shelf, calendar, volume and brightness HUD, mirror) is still there.

- [Features](#features)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Install](#install)
- [First launch and permissions](#first-launch-and-permissions)
- [Using it](#using-it)
- [Privacy](#privacy)
- [Differences from boring.notch](#differences-from-boringnotch)
- [Updating](#updating)
- [Troubleshooting](#troubleshooting)
- [Credits and license](#credits-and-license)

## Features

### A stopwatch in the notch

- Start it and the elapsed time stays visible in the closed notch: an icon on the left of the camera, the time on the right.
- Set a **target time**. The three presets (**E 20**, **M 35**, **H 50** minutes, for Easy, Medium and Hard) can be changed to anything from 1 to 300 minutes. The time turns orange at 80% of the target and red once you go over it. It keeps counting, and can play a sound when you reach the target.
- Pause, reset, and drop **markers** to note key moments, each with its split time.
- It survives quitting and relaunching the app.
- It gets along with music: swipe sideways on the closed notch to switch between the stopwatch and what's playing.

### Recording

Pick **Webcam**, **Screen** or **Both** in the Focus tab and press record.

| Mode | What you get |
|---|---|
| **Webcam** | Camera and microphone, 1080p HEVC (about 2 GB per hour). Can be paused. |
| **Screen** | The screen under your pointer (or one you choose), with your voice. Mouse clicks are highlighted. Needs macOS 15. |
| **Both** | The screen recording plus a round **webcam bubble** that floats on screen and ends up in the same video. Drag it anywhere: it remembers the spot. |

- While you record, a pulsing red dot and the recording time show in the closed notch, even if you turned the stopwatch display off.
- Videos go to `~/Movies/Boring Notch` (you can pick another folder), named by date and mode, e.g. `2026-11-23 21.30 Webcam.mov`.
- Markers added while recording are saved next to the video in a `.md` file with their timestamps.
- Quitting the app during a recording finishes the file properly first.

### A smarter notch

Opening the notch lands on what you're doing: the **Focus** tab while the stopwatch or a recording runs, **Home** otherwise. The shelf only opens when you drag a file onto the notch.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌃⌥⌘T` | Start or pause the stopwatch |
| `⌃⌥⌘M` | Add a marker |
| `⌃⌥⌘R` | Start or stop recording (in the mode selected in the Focus tab) |
| none | Reset the stopwatch |

Change them in **Settings → Shortcuts** or **Settings → Focus**.

## Install

**Requirements:** macOS 14 Sonoma or later, Apple Silicon or Intel. Screen recording needs macOS 15 Sequoia or later. A Mac with a notch looks best, but any Mac works.

### Option 1: download (no Xcode needed)

1. Download [**Boring-Notch-Plus.zip**](https://github.com/OsaIoT/boring.notch/releases/latest/download/Boring-Notch-Plus.zip) from the [latest release](https://github.com/OsaIoT/boring.notch/releases/latest).
2. Unzip it and drag **Boring Notch+** into your **Applications** folder.
3. The app isn't notarized by Apple, so macOS blocks it the first time. Run this once in Terminal:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Boring Notch+.app"
   ```

   Or try to open the app, dismiss the warning, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
4. Open **Boring Notch+** from Applications.

### Option 2: build from source

Building needs **macOS 15.6** or later and **Xcode 26** or later.

1. Install Xcode from the App Store and open it once, so it installs its components.
2. Recommended: create a free signing certificate. In Xcode, go to **Settings → Apple Accounts**, add your Apple ID, select your *(Personal Team)*, then **Manage Certificates… → + → Apple Development**. With a certificate, macOS keeps the camera, microphone and screen permissions when you update the app. Without one the app still works, but asks again after every rebuild.
3. Clone and install:

   ```bash
   git clone https://github.com/OsaIoT/boring.notch.git
   cd boring.notch
   ./scripts/install.sh
   ```

   The script builds a Release version, installs it as `/Applications/Boring Notch+.app` and opens it. It picks your certificate automatically; set `TEAM_ID=...` to choose a specific team.

Prefer Xcode? Open `boringNotch.xcodeproj`, select the **boringNotch** target, choose your team under **Signing & Capabilities**, and press Run.

## First launch and permissions

- The boring.notch onboarding walks you through its own permissions (music, calendar and so on).
- Your first recording asks for **camera** and **microphone** access.
- Your first screen recording asks for **Screen & System Audio Recording** access. Enable **Boring Notch+** in **System Settings → Privacy & Security**, then restart the app. The Focus tab offers buttons for both steps.
- Don't run Boring Notch+ and the original Boring Notch at the same time, or you'll get two notches. They can stay installed side by side: they're separate apps with separate settings.

## Using it

Hover over the notch (or click it) and open the **Focus** tab.

- **Left half, stopwatch:** play/pause, reset, marker, and the target buttons (∞ for no target).
- **Right half, recording:** the record button, the microphone switch, the **Webcam | Screen | Both** picker, a live preview of the webcam while recording, and links to open the last video or show it in Finder.

Everything else is in **Settings → Focus**:

| Section | Options |
|---|---|
| General | Show the Focus tab; show the stopwatch in the closed notch |
| Target times | The three presets; sound when the target is reached |
| Recording | Camera, microphone, 1080p or 720p |
| Screen | Which screen to record, highlight clicks, hide the notch from recordings, bubble size, show the bubble in webcam-only recordings too |
| Saving | Folder, add finished videos to the shelf, open the video when the recording ends |

## Privacy

Everything stays on your Mac. Recordings are ordinary video files in the folder you chose, and nothing is uploaded anywhere. The webcam bubble is a normal window: it only ends up in a video when you record the screen.

## Differences from boring.notch

- It's a separate app (bundle ID `com.osaiot.boringnotch`, named "Boring Notch+"), so it doesn't share settings or permissions with the original.
- Automatic updates are off. To update, see [Updating](#updating).
- It's based on boring.notch's `dev` branch (2.8 beta).
- It fixes a bug where the selected tab's highlight could land on the wrong tab once there are three tabs.

## Updating

If you downloaded the app, download the latest release and replace the old copy.

If you built it, pull and run the script again:

```bash
git pull
./scripts/install.sh
```

To bring in the latest changes from the original project too:

```bash
git remote add upstream https://github.com/TheBoredTeam/boring.notch.git   # only once
git fetch upstream
git merge upstream/dev
./scripts/install.sh
```

If `README.md` conflicts during the merge, keep this one (`git checkout --ours README.md`).

## Troubleshooting

| Problem | What to do |
|---|---|
| macOS says the app can't be opened | Run the `xattr` command from [Install](#install), or use **Open Anyway** in Privacy & Security. |
| The build fails with a signing or team error | Use `./scripts/install.sh`, which picks your team, or choose your team in Xcode under **Signing & Capabilities**. |
| Screen recording still says access is off after you allowed it | Restart the app (the **Restart** button in the Focus tab). |
| Two notches on screen | Quit the original Boring Notch and remove it from **System Settings → General → Login Items**. |
| A recording stopped by itself | Open Console.app and filter by subsystem `com.osaiot.boringnotch`: the error code is logged there. |

## Credits and license

Boring Notch+ is built on [boring.notch](https://github.com/TheBoredTeam/boring.notch) by [TheBoredTeam](https://github.com/TheBoredTeam) and its contributors. Everything except the Focus features is their work.

Like the original, it's released under the [GNU General Public License v3.0](LICENSE). Third-party components are listed in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).
