# Gaxo

A native macOS receiver for iPhone and iPad **screen mirroring** (AirPlay).
Mirroring opens in a **normal, movable, resizable window** — like AirServer or
LonelyScreen on Windows — and never goes full screen unless you ask.

Personal project, GPL-3.0. Built on the [UxPlay](https://github.com/FDH2/UxPlay)
engine; everything you see (window, video, sound, menus) is native Swift.

## Status — 2026-10-17

Tested with an iPhone 17 (iPhone18,2) on iOS 26.6.1, Mac on macOS 26.5:

| Works | Notes |
|---|---|
| Shows up in Screen Mirroring next to the Mac's own AirPlay Receiver | Gaxo uses its own ports and device ID |
| Screen mirroring video in a resizable window that keeps the phone's shape | H.264, hardware decoded |
| Rotating the phone reshapes the window around its centre | portrait 498×1080 ↔ landscape 1920×884 |
| Sound on the Mac | AAC-ELD; keeps playing when you switch output (e.g. a headset) |
| Closing the window disconnects the iPhone; stopping on the iPhone returns Gaxo to Ready | |
| Menu bar icon + status window; Dock icon only while a Gaxo window is open | |
| Settings: name, resolution, frame rate, keep on top, close when mirroring stops, sound | renaming restarts the receiver under the new name |

Not verified yet: the 4-digit code, Open at login and Take Screenshot with a
phone, and the installed, signed app's first-launch prompts.

Not supported (by design, for now): casting videos from apps (YouTube/HLS),
photos, a music-only AirPlay player, H.265/4K, recording, several phones at once.

## Requirements

- macOS 26 on Apple Silicon, Xcode 26 (Swift 6.3)
- Homebrew `openssl@3` and `libplist` — **build time only**; both are linked
  statically, so Gaxo.app does not need Homebrew

```bash
brew install libplist
```

## Build, test, run

```bash
swift build
```

```bash
swift test
```

```bash
swift run Gaxo
```

The windowless engine test (mirror to "Gaxo Probe"; prints what arrives):

```bash
swift run gaxo-probe --debug --sound
```

## Install

```bash
scripts/build-app.sh
```

```bash
scripts/install.sh
```

```bash
open ~/Applications/Gaxo.app
```

`build-app.sh` makes `build/Gaxo.app`, signed with the first Apple Development
identity in your keychain (set `GAXO_SIGN_ID` to choose another, or `-` for
ad-hoc signing, e.g. for a build you share). `install.sh` copies it to
`~/Applications`. Both refuse to replace anything they did not create.

First launch, macOS asks:

1. *"Do you want the application Gaxo to accept incoming network connections?"* — **Allow** (firewall).
2. Local Network access — **Allow**.

The first signing may ask for keychain access: enter your login password and
click **Always Allow**.

## Using it

On the iPhone: **Control Center → Screen Mirroring → Gaxo**.

View menu: Float on Top (⌥⌘T), Actual Size (⌘0), Fit to Screen (⌥⌘0),
Take Screenshot (⇧⌘S, saved to the Desktop, never overwriting a file),
Enter Full Screen (⌃⌘F).

## How it works

| Path | What |
|---|---|
| `Sources/UxPlayLib/uxplay` | UxPlay v1.73.7 `lib/` plus one documented patch (PIN pairing with iOS 26; see `Patches/README.md` and `Sources/UxPlayLib/UPSTREAM.md`) |
| `Sources/UxPlayEngine` | C shim doing what `uxplay.cpp` does around the library: Bonjour, feature bits, server lifecycle, callbacks |
| `Sources/GaxoCore` | Swift: engine wrapper, session rules (one phone at a time, 15 s silence watchdog), H.264 → VideoToolbox, audio → AudioToolbox, settings |
| `Sources/Gaxo` | The app: menu bar item, status window, mirror window, Settings |
| `Sources/gaxo-probe` | Windowless engine test |

- Ports: TCP/UDP **7100–7102** (RTSP on 7101, like `uxplay -p 7100`). The
  Mac's own receiver keeps 7000/5000.
- Device ID: a random, locally administered MAC address, kept in preferences.
- Identity key: `~/Library/Application Support/Gaxo/identity.pem`, so the
  iPhone recognises Gaxo across launches.

## Troubleshooting

- Log: `~/Library/Logs/Gaxo/gaxo.log` (includes UxPlay's engine messages).
- Is Gaxo advertised? `dns-sd -B _airplay._tcp local.`
- The iPhone lists Gaxo but never connects: usually the firewall. System
  Settings → Network → Firewall → Options → allow Gaxo.
- In zsh, `log` is a shell built-in; use `/usr/bin/log show …` for the system log.

## Updating the UxPlay engine

Replace `Sources/UxPlayLib/uxplay` with a newer UxPlay `lib/`, update
`UPSTREAM.md`, run `swift test`, and compare the feature bits in UxPlay's
`uxplay.cpp` (`start_dnssd`) with `Sources/UxPlayEngine/gaxo_engine.c`.

## License and credits

GPL-3.0 — see `LICENSE`.

- [UxPlay](https://github.com/FDH2/UxPlay) (GPL-3.0), by F. Duncanh and contributors
- RPiPlay and shairplay (LGPL-2.1), by Juho Vähä-Herttua and contributors
- playfair (FairPlay), see `Sources/UxPlayLib/uxplay/playfair/LICENSE.md`
- llhttp (MIT)

AirPlay is a trademark of Apple Inc. Gaxo is not affiliated with Apple.
