# True Tone Hold

A small macOS login helper that preserves **approximately the last True Tone warmth** on an external monitor when a MacBook's lid closes, then restores the original gamma when the lid opens.

Apple's native True Tone correction stops on ordinary external monitors when the laptop lid closes. This helper reads the live color-adaptation matrix while the lid is open and approximates its neutral-white correction using RGB gamma gains while closed. It does **not** reproduce the full True Tone matrix or make native True Tone work in clamshell mode.

## Requirements

- macOS with True Tone enabled and an external display.
- Xcode Command Line Tools (`xcode-select --install`) to compile.
- Tested on one Apple Silicon Mac running macOS 26.6.2; other releases and hardware are unverified.

No administrator access, reboot, network connection, or third-party runtime is required. The helper does not change VPN, sleep, or power settings.

## Install

```sh
./install.sh
```

Keep the lid open for at least three seconds. Close it and check the appearance; the cached correction is applied as soon as the lid notification is handled. Reopen it to return control to normal True Tone.

The installer builds the program locally and registers `local.truetone-hold` as a per-user LaunchAgent. Existing unknown installations must be stopped first to prevent two helpers from competing.

## How it works

The helper is **dormant between events**, with a bounded guard during lid closure:

- **No external monitor:** only the macOS display-reconfiguration callback remains registered. The color client and lid listener are released.
- **External monitor, lid open:** it listens for True Tone `ColorRamp` changes through the private `BrightnessSystemClient` interface and caches the delivered matrix. There is no scheduled sampling.
- **Lid closes:** an IOKit clamshell notification stops color subscriptions and applies the cached correction immediately, without an intentional delay. A transition guard checks for a macOS gamma reset approximately once per 16.7 ms for at most 1.25 seconds, writing only when necessary. It then stops. Completed closed-lid display-configuration events restart this short guard.
- **Lid opens:** it restores the saved gamma and resumes True Tone notifications.
- **Display configuration changes:** it reconciles connected monitors and restores or reapplies correction as needed.

A coalesced **one-shot** timer handles open-lid settling. During closure only, a short repeating timer covers asynchronous gamma resets. There is no continuous monitoring timer: opening the lid, disconnecting all external displays, or reaching the 1.25-second deadline cancels the guard. Between events the helper sleeps. A small resident process is needed to receive connection notifications; dormant does not mean unloaded from memory.

The color matrix's row sums describe its effect on neutral white. The helper approximates corresponding encoded RGB gains with an exponent of 1/2.2. It always applies them to the saved baseline, so corrections do not accumulate.

## Limitations

- This is a white-balance approximation, not colorimetrically exact True Tone. It is unsuitable for color-critical work.
- The private CoreBrightness read interface may change after a macOS update.
- macOS can overwrite an immediate correction during display reconfiguration. The transition guard attempts to repair such resets on its next tick, approximately 16.7 ms later. Scheduling delays are still possible; this is not a real-time guarantee. This implementation cannot guarantee an instantaneous, flicker-free transition.
- The process must observe the lid open before it has a reading to hold. Captures are kept in memory, not persisted across restarts.
- Other gamma-adjustment applications, HDR behavior, display reconnections, and display-ID changes may affect the result. There is no ongoing periodic correction to override changes made by another application. Multiple-display behavior has not been verified.
- SIGTERM and SIGINT restore gamma; a force kill or crash cannot run cleanup. macOS may reset gamma during a display reconfiguration, but this is not guaranteed.
- The helper does not keep a sleeping Mac awake.

## Validation and diagnostics

A brief live gamma write/readback/restore test is available while the lid is open:

```sh
"$HOME/Library/Application Support/TrueToneHold/truetone-hold" --self-test
```

This changes display gamma briefly and restores it. Live tests passed gamma write/readback/restoration and delivery of True Tone change notifications. `make check` builds with warnings treated as errors, checks shell syntax, and verifies dormant-state cleanup and detection of reset/invalid gamma tables. A physical lid-close appearance test has not yet been confirmed by the user.

Send `SIGUSR1` to the helper for a one-time diagnostic status line (subscription, cache, held-display, notification counts, pending-transition state, and whether the transition guard is active). This adds no periodic wakeups.

Transition logs are local at `~/Library/Logs/TrueToneHold/agent.log`. The helper makes no network requests and sends no telemetry. Logs include display identifiers and correction gains; review them before sharing.

## Disable

```sh
./uninstall.sh
```

This stops the login helper and removes its LaunchAgent. Program files and logs remain under `~/Library/Application Support/TrueToneHold/` and `~/Library/Logs/TrueToneHold/` for inspection or manual removal.
