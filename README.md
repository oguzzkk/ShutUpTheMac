# Shut Up The Mac

Per-app mute and volume control for macOS, built on Core Audio process taps — **without a virtual audio device**.

Your default output device never changes, no driver is installed, and no audio is resampled through a kernel extension. The app opens a tap on the processes you want to silence, reads it, and emits silence (or a scaled copy) instead.

![menu bar icon](docs/menubar.png)

## Why

Existing tools (Background Music and friends) route the entire system output through a virtual device they install. That changes your default output, adds latency, breaks when you plug in headphones, and leaves a driver behind. macOS 14.2 introduced a public process-tap API that makes all of that unnecessary.

## What it does

- **Mute or set the volume of individual apps** from a menu bar panel.
- **Groups helper processes under the app they belong to.** Chrome, Electron apps and Safari play audio from helper processes (`com.apple.WebKit.GPU`, `Google Chrome Helper`, …). Muting "Safari" mutes everything Safari plays, including helpers that spawn later.
- **Survives process restarts.** Taps are attached by bundle ID, so a process that dies and respawns — like `systemsoundserverd`, which plays every alert and screenshot sound — stays muted.
- **Mute apps that are not running.** Once the app has seen where an app plays audio from, it can keep it silenced across launches.
- **"Mute everything" is reversible.** It snapshots the current state; pressing it again restores exactly what you had, including partial volumes.
- **Frequently toggled apps rise to the top** of the list.
- **CLI for automation** (Shortcuts, scripts).

## Requirements

- macOS 14.2+ for process taps; **macOS 26+** for bundle-ID taps and process restore (the features that make muting survive process respawns).
- Permission to record system audio. Muting requires it: a tap only silences a process while the tap is being read, so the app has to open an audio path. It never writes audio anywhere.
- No Xcode. Swift toolchain from the Command Line Tools is enough.

## Build

```bash
./make-app.sh --install     # builds, bundles, signs, installs to /Applications and launches
./make-app.sh               # build only, into ./build
```

The script hand-assembles the `.app` bundle (SwiftPM has no app-bundle product) and signs it. If a code signing identity named `Shut Up The Mac Dev` exists in your keychain it is used; otherwise the bundle is ad-hoc signed.

> Ad-hoc signatures change on every build, and macOS ties privacy permissions to the signature — so with ad-hoc signing you have to grant audio permission again after every rebuild. Creating a stable self-signed identity avoids that.

## CLI

```bash
shutup list                  # apps and their levels, loudest first
shutup mute <app>            # <app> matches a bundle ID or a name fragment
shutup unmute <app>
shutup volume <app> 0-100
shutup muteall               # mute everything; run again to restore the previous state
shutup status                # what the app is doing right now, as JSON
```

The binary lives inside the bundle at `Contents/Resources/shutup`.

## How it works

Each controlled app gets its own independent audio path:

1. A `CATapDescription` tap on the app's processes, with `muteBehavior = .mutedWhenTapped` — while we read the tap, the app's audio does not reach the hardware.
2. A **private aggregate device** containing that tap and the current output device.
3. An `IOProc` that multiplies the tap's samples by the app's gain and writes them to the output. Gain `0` is a mute.

Per-app paths matter: with one shared path, unmuting a single app tore down and rebuilt everything, leaking a moment of audio from every other muted app.

### Things that cost me a day

- **`CATapMuted` does not mute on its own.** The header says the audio "is captured by the tap but not sent to the audio hardware" — the capture part is load-bearing. A tap nobody reads changes nothing.
- **A tap-only aggregate device never runs IO.** The output device is what drives the IO cycle; remove it and the `IOProc` is never called, so muting silently stops working.
- **HAL setup calls must not run on the main thread.** Creating an aggregate device makes Core Audio call back into the process; on the main queue the whole app deadlocks — menu included.
- **`ProcessInfo.beginActivity(.latencyCritical)` freezes the main run loop.** Timers and notifications stop firing entirely.
- **Private taps are only visible to the process that created them**, so you cannot inspect the app's taps from a CLI — hence `shutup status`.
- **Safari's audio comes from a process whose parent is `launchd`**, not Safari. Walking the parent chain is not enough; macOS's own responsible-process mapping is what connects them.

## License

MIT — see [LICENSE](LICENSE).

## Notes

Source comments and the user interface are in Turkish.
