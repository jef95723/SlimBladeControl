# SlimBlade Control 0.6.1

A native macOS utility for the older **wired Kensington SlimBlade**, USB **047d:2041**. Rust handles button combinations, report decoding, and motion scaling. Objective-C provides Cocoa settings, IOKit device access, and Core Graphics output. MIT licensed; no external Rust crates, networking, telemetry, privileged helper, or kernel extension.

**Author: [Jeffrey Liu](https://github.com/jef95723)** · [MIT License](LICENSE)

[Download the latest Apple Silicon app](https://github.com/jef95723/SlimBladeControl/releases/latest) · [Release notes](docs/releases/v0.6.1.md)

## Start using it

1. Put **SlimBlade Control.app** in `/Applications` and open it. It automatically starts your saved mappings when both permissions are available.
2. In **App → Grant permissions**, enable **Accessibility** and **Input Monitoring** in System Settings → Privacy & Security. If the app is missing, use **+** and choose `/Applications/SlimBlade Control.app`. Relaunch if requested. No Full Disk Access or Screen Recording is needed.
3. Kensington's trackball driver must release the device: on this Mac it is **System Settings → General → Login Items & Extensions → .KensingtonKonnect-TB → Show Detail**. Turn off that driver switch, then unplug and reconnect the SlimBlade USB cable once so macOS attaches its native mouse event service. Quitting Kensington Konnect alone does not release the device. Leave Karabiner's keyboard driver enabled; disable **Modify events** for the SlimBlade only if Karabiner is capturing it.
4. Release all trackball buttons and move the ball after launch. Movement and scrolling are forwarded immediately after connection; the first neutral report arms clicks without firing already-held buttons. No Start click with a second mouse is needed once permissions are granted. Keep another pointer available during initial permission setup.
5. **Buttons** contains individual and combination mappings, **Motion** contains speed, direction, and timing, **App** contains startup, Dock, menu bar, and identification options, and **About** shows the author and version. Choose **Apply changes** to save and activate button/motion changes.

**Closing the settings window keeps mappings running.** Open the app from Applications, Spotlight, or the menu bar to return. **Quit** exits the process and stops mappings. **Pause** releases capture. With the native mouse service attached, quitting provides basic pointer movement, bottom-left/right clicks, and twist scrolling without this app running. The upper buttons use vendor reports and their custom mappings require the app. If basic input stops after changing Kensington's driver state, quit this app and reconnect USB once.

The menu bar shows a monochrome trackball, with a red center while connected. Turn off **App → Show icon in the menu bar** to hide it; this does not stop mappings. It stays out of the Dock by default. Enable **App → Show app in the Dock** if desired. You can always return through Applications or Spotlight, even with both icons hidden. Dock, menu bar, and startup options save immediately. Automatic startup is enabled by default and can be disabled in App. This starts mappings when the app opens; it does not add a login item. Running without a Dock icon uses the same app process and input permissions; it does not require a background helper or updater permission. Choose **App → Quit SlimBlade Control** to exit even when both icons are hidden.

Sleep, session deactivation, and unplugging still pause the controller; click Start after returning. Saved settings remain local.

This local build is ad-hoc signed, **not notarized**. Rebuilding changes its signature; macOS may require removing and re-adding its privacy entries. Never run it as root or disable SIP.

## Changes in 0.6.1

- Added an About page and an About menu command, with author credit to **Jeffrey Liu**, the current version, and MIT licensing.
- The app stays out of the Dock by default, with an optional **Show app in the Dock** setting. Closing the window keeps mappings running. Applications, Spotlight, and the optional menu icon can reopen settings. App settings include a Quit button for use when both icons are hidden.
- Prepared the first public GitHub release, including source, build instructions, and an Apple Silicon app archive.

## Changes in 0.6.0

- Every button and pair can use **Keyboard shortcut…**. Record a physical key combination, or select Control, Option, Shift, Command, and a key explicitly. For Option–Space, choose Option and Space; this also works when a global hotkey intercepts recording. The recorder listens only inside its own sheet while recording. Escape stops recording, Cancel keeps the previous mapping, and Use shortcut updates the card. Apply changes saves it.
- **Open application…** shows a native application picker. Choose ChatGPT or another installed `.app`. A press opens or focuses that app once; holding or releasing the buttons does not launch it again. Click the app name on its card to choose another. If the app is moved or removed, choose it again.
- Individual buttons are arranged in their physical two-by-two layout. A separate **Button combinations** grid shows all six pairs: bottom 1+2, top 3+4, left 1+3, right 2+4, and diagonals 1+4 and 2+3. Existing eight mappings retain their positions and values; the two new diagonal mappings start disabled. Motion and app preferences are preserved.
- Two additional generated transparent illustrations identify the diagonals. All ten assets are in `assets/buttons/`; `diagonal-prompts.json` records the complete new prompts and built-in image-generation provenance.

## Changes in 0.5.0

- Pointer speed, twist scrolling, and combination timing have editable numeric fields. Typing a valid value updates the associated slider; Apply saves it. Invalid, non-finite, partial, and out-of-range inputs are rejected before interrupting a working connection. Timing accepts whole milliseconds. Fields retain the existing underlying numeric precision.
- Twist scrolling now ranges from 0.1 to 20× in both the UI and Rust engine. Pointer speed remains 0.1–5×; combination timing remains 20–150 ms. Existing saved values are preserved.
- Eight generated transparent trackball illustrations show the selected individual button or adjacent pair in blue, with spatial labels and accessible descriptions. Assets live in `assets/buttons/`; `prompts.json` records the complete prompt set and built-in image-generation tool provenance.
- Diagnosed the no-input-after-Quit issue on this Mac: the raw HID device existed but its native mouse event service was missing after Kensington's extension was disabled. The app had already released its capture. A USB reconnect restored `AppleUserHIDEventService`; it remained attached after another app launch/capture/Quit cycle. The user confirmed pointer movement, bottom-button clicks, and twist scrolling still worked without reconnecting again. No background helper, USB-reset workaround, or driver/security setting change was added.

## Changes in 0.4.0

- Saved mappings start automatically after the UI, event source, and settings are initialized. Permission checks still precede device capture, and reopening a closed window does not restart capture.
- Native settings use three tabs, grouped cards, readable action menus, and custom fields shown only when needed. Existing mappings and speed preferences are retained.
- A template trackball icon adapts to the menu bar's foreground color. A separate red ball indicates an actual device connection, and hiding the icon leaves the controller running.
- Window-close behavior is explicit: remain running until Quit.

## Shortcut fix in 0.3.1

Preserves the arrow/function/keypad flags created by Core Graphics and includes the device-specific bits for generated left-side modifiers. The previous build replaced those flags with only generic Ctrl/Cmd/Shift/Option flags; Mission Control and Space presets did not work on this Mac even though physical keyboard shortcuts did. Native regression tests now verify the complete Control-arrow press/release sequence for all four arrow keys. The author reports that the current version works well; detailed hardware acceptance items are listed below.

Permission failures now identify Accessibility and Input Monitoring separately, including guidance for stale entries after rebuilding. The installed copy on this Mac is now `/Applications/SlimBlade Control.app`.

## Controls

- **Linear tracking:** 0.1–5×. One raw count moves one desktop coordinate unit at 1×, with fractional carry. This does not reproduce Apple's pointer acceleration or Kensington's numerical scale.
- **Scroll multiplier:** 0.1–20×, with optional reversal. Base rate: 24 pixel-scroll units per wheel count. No inertia or smoothing.
- **Combo window:** 20–150 ms, default 60 ms. Only buttons belonging to an enabled pair wait for this window.
- **Four buttons:** lower-left 1, lower-right 2, upper-left 3, upper-right 4.
- **Six combinations:** bottom 1+2, top 3+4, left 1+3, right 2+4, diagonal 1+4, diagonal 2+3.

The connected device's ID, descriptor, and upper-button orientation have been verified on this Mac. To check a different unit: enable **App → Identify buttons**, Apply, release buttons and move the ball, then press each button. The last pressed number remains visible after release. Identification suppresses clicks and shortcuts while preserving movement/scroll, so use another pointer to Pause. If the upper numbers are reversed, enable **Swap top-left and top-right inputs** and Apply. Uncheck Identify and Apply to use mappings normally.

## Mappings

Choose a mouse action or preset, **Keyboard shortcut…**, or **Open application…**. Click the shortcut or app name beneath the action menu to edit it. Choose **Apply changes** to save and activate your choices.

The following syntax is used internally in saved preferences; you do not need to type it:

| Syntax | Action |
| --- | --- |
| `none` | Disabled; a disabled combination adds no waiting window |
| `mouse:1` / `mouse:2` / `mouse:3` | Left / right / middle click |
| `mouse:4` / `mouse:5` | Additional mouse buttons; app support varies |
| `key:8:cmd` / `key:9:cmd` | Copy / Paste on a US layout |
| `key:126:ctrl` | Control-Up (Mission Control if enabled in macOS) |
| `key:123:ctrl` / `key:124:ctrl` | Previous / next Space |
| `key:33:cmd` / `key:30:cmd` | Browser Back / Forward on a US layout |
| `key:36` | Return |
| `key:49:alt` | Option–Space |
| `app:file:///Applications/ChatGPT.app` | Open or focus ChatGPT |

Keyboard syntax is `key:<decimal macOS virtual keycode>:<modifiers>`, using `cmd`, `ctrl`, `shift`, `alt` joined with `+`. Keycodes describe physical keys, so labels depend on keyboard layout. Codes 54–63 are rejected because modifier-only mappings are unsupported. Media keys, macros, and key repeat are not implemented.

Default individual actions: left, right, middle, Control-Up. Combinations default to disabled. A first combination to try is `1+2 → mouse:3`.

Identical mapped actions share ownership: releasing one holder does not release another. Mappings using the **same key with different modifiers are rejected** to avoid conflicting key-up events. Modifiers are held for a shortcut's lifetime and can affect other simultaneous actions; physical keyboard modifiers are preserved. Interactions with physical presses of the same mapped key still require hardware testing.

## Combination behavior

- A successful pair emits only its assigned action. Mouse and keyboard actions remain down until either member is released; the other member's later release emits no individual click. Application actions fire once when the pair activates.
- Quick taps deliver down/up on release. A late second press cannot cancel an already-delivered individual action.
- Ball motion commits pending clicks immediately for dragging; incidental movement between presses can prevent a combination.
- Complete USB reports provide one atomic button snapshot. Releases are processed before new presses, preventing false combinations when one button is replaced by another in the same report. Movement follows that button snapshot.
- First completed overlapping pair wins. Disjoint pairs can coexist. No triple/quad combinations.
- A one-shot timer handles the next pending deadline. There is no permanent 200 Hz combo timer. A tolerant 2-second timer checks permission revocation while started.

## Build

Requires Xcode Command Line Tools and a native Rust toolchain. macOS 12+ is the deployment target; only Apple Silicon on macOS 26.6.2 has been built and launched here.

```sh
bash build.sh
```

This runs Rust, C/Rust integration, and native event-generation tests; builds the Cocoa app with warnings treated as errors; creates the icon; and ad-hoc signs `build/SlimBlade Control.app`. Builds are offline after installing the toolchains. In the original workspace, the script also detects the isolated Rust install at `../.toolchain`. That toolchain is not included in the source ZIP. For a fresh checkout, install Rust from [rustup](https://rustup.rs).

Tests alone:

```sh
bash tests/run.sh
```

## Verified status — October 9, 2026

- Version 0.6.1 builds and passes the existing Rust, C/Rust, and native regression suites. The installed About page shows Jeffrey Liu and version 0.6.1. The live Dock preference switches macOS activation policy between regular and accessory; accessory mode remains active after closing the settings window, and settings reopen successfully. Saved actions and effective motion/startup/menu preferences are preserved. No helper, login item, updater, or network access was added. After refreshing Accessibility and Input Monitoring, the final installed v0.6.1 binary reached Active, confirmed in the UI and by the author.

- Rust 1.99.0, Xcode 26.2, arm64 macOS 26.6.2.
- Seven Rust tests pass, covering every pair in both orders, quick taps, drag commitment, reset, signed report decoding, upper-button swapping, fractional motion/scroll, the extended 20× scroll range and its clamp, simultaneous snapshots, duplicate reports, and one-shot deadlines.
- C integration against the actual Rust library passes, including 640,000 randomized transitions across all 64 enabled-pair configurations; C ABI struct size, report output, returned motion structs, and deadline calls are exercised.
- The 0.5.0 C/Rust integration suite also passed with Clang UndefinedBehaviorSanitizer. AddressSanitizer did not complete on this host; no ASan result is claimed. Rust code itself was not sanitizer-instrumented.
- Native tests intercept every event post and application launch and pass for action validation, eight-to-ten mapping migration, Option–Space generation/release, application URL validation, once-per-press diagonal application actions, shared click/key ownership, modifier release, all four Control-arrow sequences including Fn/keypad identity and left-Control bits, cleanup, startup arming, duplicate reports, automatic launch, window-close policy, numeric input validation/precision and slider synchronization, and the connection indicator. These tests inject no input into other apps.
- Read-only IOKit discovery succeeds, finds one `047d:2041` device, and confirms its exact 75-byte HID descriptor and five-byte report format.
- Version 0.6.0 compilation and ad-hoc signature verification pass. UI checks cover the physical button grid, all six combination cards, manual Option–Space entry, recording Control–Shift–K and Command–W, Escape stopping recording, Cancel restoring the previous shortcut, and choosing ChatGPT in the native application picker. Test mappings were discarded without saving. Saved original mappings and motion values were preserved, with the two disabled diagonal slots appended. The author subsequently reported that the app is working well. Detailed physical combination and shortcut coverage has not been separately confirmed.
- Previously verified in version 0.5.0: compilation, launch, generated mapping illustrations, numeric entry for all three motion controls, 7.5× scroll entry, out-of-range rejection, corrected-input feedback, preserved mappings/speeds, and missing-permission handling have been checked. Ad-hoc signature verification passes. All eight bundled PNGs retain alpha. Accessibility and Input Monitoring were refreshed for the final binary, automatic capture reached Active, and a final Quit left the native Apple mouse service attached with no SlimBlade Control capture open. The app was reopened and left running on Motion. The feel of higher scroll speeds still needs the user’s preference testing.
- Accessibility and Input Monitoring approval for the installed app have been verified. The first live capture attempt returned `0xe00002c5` (exclusive access conflict) while other remappers held the device. After Kensington's trackball driver was disabled and Karabiner's SlimBlade Modify events switch was off, **exclusive capture succeeded**. Quitting Kensington's settings app alone did not resolve the conflict.
- **User-confirmed on the actual trackball:** pointer movement, twist scrolling, lower-left/right clicks, and upper-left/right identification as buttons 3/4. The app reached Active and Start successfully recaptured it. After the native mouse service was restored by reconnecting USB, a full open/capture/Quit cycle left ordinary pointer movement, bottom-button clicks, and twist scrolling working, confirmed by the user. **Physical combination timing, double-click/drag details, unplug/sleep/session recovery, and multi-display behavior still need acceptance testing.** Passing automated tests does not establish these results.

## Hardware acceptance checklist

1. Start at 1× with combinations disabled. Confirm four movement directions and both scroll directions, without duplicated native events.
2. Identify all four physical buttons, adjust upper swap if needed, then test left/right/middle and Control-Up.
3. Test click, double click, drag/select, right drag, Command-click, and Shift-click.
4. Compare tracking/scroll at 0.5× and 2×. Confirm the trackpad/second mouse remains native; check display edges and transitions.
5. Test all six combinations in both press orders, quick tap, long hold, late second press, overlapping pairs, and release/repress. A successful combination must emit no individual click.
6. Assign Option–Space (or another configured shortcut), then test it from a button. Assign an application to a pair; confirm a press opens/focuses it once and a held pair does not repeatedly launch it.
7. Test Pause, Quit, unplug/replug, sleep/wake, and session switching while idle and while an action is held. Confirm native input returns and no key/button stays held.
8. Check scroll direction/units in the apps you use. Games, raw-HID consumers, login screens, Secure Input, and remote sessions are not verified.

## Internals and limits

The independent IOHIDManager discovers only `047d:2041`. The app validates the exact known report descriptor before opening one device with `kIOHIDOptionsTypeSeizeDevice`. Unknown layouts are left in native mode. The five-byte report contains lower buttons, signed X/Y/wheel, and vendor upper buttons. It cannot silently fall back to guessing an arbitrary device layout.

The report callback, Rust engine, timers, and Cocoa state run on the main thread. Rust's event path allocates no heap memory. The C FFI still requires valid aligned pointers, matching layouts, and non-reentrant callbacks. The Objective-C shell is not made memory-safe by using Rust.

Mapped output is posted at the session event tap; physical modifiers are queried from HID system state without a keyboard listener. The app releases held outputs before closing the device on Pause, configuration changes, input error, disconnect, sleep, session deactivation, and normal exit. Revocation is detected periodically, but macOS may already prevent final output delivery once permission is withdrawn. A force-kill/crash cannot run cleanup; use another pointer/key release if the OS retains synthetic state.

Only one wired SlimBlade is supported. Conflicting drivers may prevent exclusive capture or interfere with suppression. Multi-display behavior and interactions with simultaneous physical input need validation. No measured performance or latency advantage is claimed.

Preferences: `org.local.SlimBladeControl`. No event logs, telemetry, firmware changes, or network traffic.

## References

- [Apple IOHIDDeviceOpen](https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen)
- [Apple IOHIDManager options](https://developer.apple.com/documentation/iokit/iohidmanageroptions)
- [Rust static library linkage](https://doc.rust-lang.org/reference/linkage.html)

`tests/reference_chords.c` preserves the earlier four-pair C reference; it is not linked into the app or the current Rust integration tests. The source and icon artwork are MIT licensed.
