<p align="center">
  <img src="docs/readme-icon.png" alt="SoundLock speaker and padlock icon" width="160" />
</p>

# SoundLock

**Your audio. Your rules. Always.**

SoundLock is a lightweight macOS menu bar app that stops the system from hijacking your audio devices. Define a priority order for your headphones, speakers, and microphones — and SoundLock silently enforces it, every time, in the background.

Its icon pairs a speaker with a small padlock badge — a single glance says "your audio, held in place." The menu bar icon is state-aware: the padlock is shut while SoundLock is enforcing your order, and its shackle springs open (dimmed) when enforcement is paused.

<p align="center">
  <img src="docs/screenshot-popover.png" alt="SoundLock menu bar popover" width="320" />
</p>

---

## The problem with macOS audio

macOS decides which audio device to use, and it changes its mind constantly.

Connect a pair of Bluetooth headphones and macOS switches your output to them — even if you were mid-call on your AirPods. Plug in a USB hub with an audio chip and suddenly your mic is gone. Open a video call and the system reassigns your input without asking. Every time a new device appears, macOS picks a winner based on its own rules, not yours.

The System Settings audio panel lets you change the default device after the fact, but it won't remember your preference the next time things connect or disconnect. There's no concept of priority. There's no lock. There's no protection.

So you fix it manually. And then you fix it again. And again.

---

## What SoundLock does differently

SoundLock puts you in charge of a ranked priority list — one for output devices, one for input — and keeps the system honest.

**It's always watching.** Three CoreAudio listeners run silently in the background, watching for default-device changes, new connections, and disconnections. The moment macOS switches to the wrong device, SoundLock switches it back.

**It uses your priority list, not macOS's.** You drag your preferred headphones to the top. If they're connected, they stay active. If they disconnect, SoundLock promotes the next device on your list automatically. When the top-priority device reconnects, it takes over again.

**It remembers devices even when they're offline.** Your AirPods in the priority list but not currently connected? They stay in the list, labelled Offline, ready to take priority the moment they pair.

**It recovers from Bluetooth delays.** macOS often auto-switches audio after a Bluetooth device finishes pairing — a delayed second event that happens 1–3 seconds after connection. SoundLock schedules multiple recovery checks to catch this, and cancels stale ones if a newer event arrives.

**It respects when you want to opt out.** The guard toggle in the menu lets you temporarily disable priority enforcement — useful when you deliberately want to try a different device. Toggle it back on and SoundLock immediately reasserts your priority.

---

## Features

- **Priority output and input lists** — drag to reorder, add/remove any connected physical device
- **Offline device persistence** — priority devices stay in the list even when disconnected
- **Volume control** — slider and percentage display for both output and input priority devices
- **Mute toggles** — one-tap mute for both directions, directly from the menu
- **Guard toggle** — enable or disable priority enforcement instantly from the menu bar
- **Launch at login** — runs silently in the background from the moment you log in
- **Zero Dock presence** — lives entirely in the menu bar, takes no space in your app switcher
- **System Settings shortcuts** — one-click access to Sound and Bluetooth panels from the footer
- **Tiny footprint** — event-driven CoreAudio listeners with 0% idle CPU and minimal RAM usage

---

## How it compares to macOS defaults

| | macOS | SoundLock |
|---|---|---|
| Remembers preferred device | ✗ | ✓ |
| Priority order across devices | ✗ | ✓ |
| Auto-restores on reconnect | ✗ | ✓ |
| Recovers from BT pairing delay | ✗ | ✓ |
| Volume control in menu bar | ✓ (system menu only) | ✓ |
| Runs silently in background | — | ✓ |
| No Dock icon | — | ✓ |

---

## Privacy

SoundLock knows nothing about you. There is no account, no telemetry, no analytics, no network code of any kind. The app never leaves your Mac.

**It never listens to your audio.** SoundLock does not record, sample, or process any audio data. It uses CoreAudio's Hardware Abstraction Layer (HAL) exclusively — the same low-level API that macOS itself uses to route audio. It sets device metadata (which device is the default, its volume level, its mute state). It reads zero bytes of audio content.

**It does not need microphone permission.** macOS requires microphone access when an app reads audio stream data. SoundLock never opens an audio stream, so the permission prompt never appears and the entitlement is never requested. You can verify this: open System Settings → Privacy & Security → Microphone — SoundLock will not appear in the list.

**No accessibility, location, or any other sensitive permission is used.** The only system feature SoundLock opts into is Launch at Login, which is handled through a standard macOS API (`SMAppService`) and clearly indicated by a toggle in the UI. No background entitlements, no kernel extensions, no privileged helpers.

**All preferences stay on your device.** Your priority device lists are stored in `~/Library/Preferences/` via standard `UserDefaults`, the same place macOS stores every app's settings. Nothing is synced, shared, or uploaded.

---

## Performance

SoundLock is built around a single principle: do nothing unless the system tells you something changed.

**0% CPU at idle.** There is no polling loop, no timer, no background thread spinning. The app registers three `AudioObjectPropertyListener` callbacks with CoreAudio and then goes completely dormant. The CPU wakes up only when macOS fires one of those events — a device connects, disconnects, or the default changes. On a typical day with a stable audio setup, that might be a handful of events total.

**Minimal RAM.** The entire app — Swift runtime, SwiftUI view tree, CoreAudio state, and persisted priority lists — runs comfortably under 20 MB. There are no image caches, no web views, no large frameworks loaded.

**No redundant work.** Device enumeration is a single kernel round-trip that builds both the output and input device lists in one pass. Priority list saves are debounced (300 ms), so a drag-reorder that fires multiple `didSet` callbacks results in exactly one `UserDefaults` write. Bluetooth reconnect retries use cancellable `DispatchWorkItem` objects, so a rapid connect/disconnect cycle doesn't pile up stale closures on the main queue.

**Event-driven cleanup.** Listeners are registered in `startMonitoring()` and explicitly removed in `applicationWillTerminate` — so CoreAudio is never left holding a dangling callback. Retry timers are cancelled on every new device-list event, preventing any timer accumulation over time.

---

## Download

Grab the prebuilt app from the [latest release](https://github.com/lucasmancan/SoundLock/releases/latest).

Unzip, drag `SoundLock.app` to `/Applications`, launch. macOS Gatekeeper may block first run since the build is unsigned — right-click the app → **Open** → **Open** to bypass, or run `xattr -dr com.apple.quarantine /Applications/SoundLock.app`.

---

## Building

Requires macOS 13 or later and Xcode Command Line Tools.

```bash
git clone <repo>
cd SoundLock
bash build.sh
open SoundLock.app
```

To install permanently:

```bash
cp -r SoundLock.app /Applications/
```

Then open SoundLock, enable **Launch at login**, and forget about it.

---

## How it works

SoundLock registers three `AudioObjectPropertyListener` callbacks with CoreAudio — one for default output changes, one for default input changes, and one for device list changes (connect/disconnect events). All three dispatch to the main thread and check whether the current system default matches the top-priority connected device. If it doesn't, a single `AudioObjectSetPropertyData` call corrects it.

No polling. No background threads. No timers in steady state. The app sits completely idle until the system tells it something changed.

---

## Support

If SoundLock saved your sanity, consider buying me a coffee.

<p align="center">
  <a href="https://www.buymeacoffee.com/lucasmancan">
    <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee" />
  </a>
</p>

---

## License

MIT
