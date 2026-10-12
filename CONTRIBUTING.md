# Contributing

GlideTab is meant to stay small, fast and native. These notes cover building, testing, and what a good pull request looks like.

## Building

You need macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). There is no Xcode project.

```bash
./build.sh                             # build build/GlideTab.app
./build.sh test                        # unit tests and fuzzing
./build.sh install                     # build, install to /Applications, and open
GLIDETAB_DEBUG=1 ./build.sh install   # also compile in the developer commands below
```

Sign with an Apple Development certificate if you have one. `build.sh` finds it automatically, and macOS then keeps the Accessibility and Screen Recording permissions between builds. Ad hoc builds lose them every time.

## Developer commands

Debug builds (`GLIDETAB_DEBUG=1`) accept a few extra arguments. Run them against the installed app so they use its permissions:

```bash
open -W --stdout out.txt /Applications/GlideTab.app --args --dump     # print the window and tab list
open -W --stdout out.txt /Applications/GlideTab.app --args --stress   # stress the switcher without focusing anything
open -W --stdout out.txt /Applications/GlideTab.app --args --e2e      # switch between real windows, then restore
open -W /Applications/GlideTab.app --args --snapshot panel.png        # save a screenshot of the switcher
```

`Sources/Debug.swift` lists every option. None of this is compiled into release builds.

## Pull requests

- `./build.sh test` must pass with no compiler warnings.
- If you changed the switcher, run the stress test as well.
- Keyboard logic belongs in `KeyStateMachine.swift`, which has no UI or system calls so it can be tested. Add a test for new behavior there.
- Follow the existing code: no third-party dependencies, no polling timers, native AppKit and SwiftUI controls.
- Keep comments short and about why, not what.

## Translations

User-facing text goes through `String(localized:)` or a SwiftUI string literal, and each key is listed in `Resources/strings-keys.json`. English is enough for a pull request. To fix or add a translation, edit `Resources/<language>.lproj/Localizable.strings`.

## Reporting bugs

Use the bug report template and include your macOS version, your Mac, the switcher style, and steps to reproduce. For missing or extra windows, the output of `glidetab list` helps.
