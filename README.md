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

Keep the lid open for at least three seconds. Close it, allow about one second for the display configuration to settle, then check the appearance. Reopen it to return control to normal True Tone.

The installer builds the program locally and registers `local.truetone-hold` as a per-user LaunchAgent. Existing unknown installations must be stopped first to prevent two helpers from competing.

## How it works

Every half second, the helper reads the lid state through IOKit. While open, it captures the external display's baseline gamma and the `ColorRampTarget` matrix through the private `BrightnessSystemClient` interface. The row sums describe the matrix's effect on neutral white; the helper approximates corresponding encoded RGB gains with an exponent of 1/2.2.

While closed, it reapplies the saved gamma with those gains. It always starts from the saved baseline, so successive applications do not accumulate. When reopened or gracefully stopped, it restores the baseline.

## Limitations

- This is a white-balance approximation, not colorimetrically exact True Tone. It is unsuitable for color-critical work.
- The private CoreBrightness read interface may change after a macOS update.
- A brief return to the default tint can occur during lid closure before the correction is applied.
- The process must observe the lid open before it has a reading to hold. Captures are kept in memory, not persisted across restarts.
- Other gamma-adjustment applications, HDR behavior, display reconnections, and display-ID changes may affect the result. Multiple-display behavior has not been verified.
- SIGTERM and SIGINT restore gamma; a force kill or crash cannot run cleanup. macOS may reset gamma during a display reconfiguration, but this is not guaranteed.
- The helper does not keep a sleeping Mac awake.

## Validation and diagnostics

A brief live gamma write/readback/restore test is available while the lid is open:

```sh
"$HOME/Library/Application Support/TrueToneHold/truetone-hold" --self-test
```

This changes display gamma briefly and restores it. The initial development test passed capture, gamma write/readback, and baseline restoration. A physical lid-close appearance test has not yet been confirmed by the user.

Transition logs are local at `~/Library/Logs/TrueToneHold/agent.log`. The helper makes no network requests and sends no telemetry. Logs include display identifiers and correction gains; review them before sharing.

## Disable

```sh
./uninstall.sh
```

This stops the login helper and removes its LaunchAgent. Program files and logs remain under `~/Library/Application Support/TrueToneHold/` and `~/Library/Logs/TrueToneHold/` for inspection or manual removal.
