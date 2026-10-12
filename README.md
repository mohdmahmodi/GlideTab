<div align="center">

<img src="docs/images/icon.png" width="112" height="112" alt="GlideTab app icon">

# GlideTab

**Hold Option. Press Tab.** Every open window on your Mac, with a live preview.

[![Latest release](https://img.shields.io/github/v/release/mohdmahmodi/glidetab?label=release&color=333333)](https://github.com/mohdmahmodi/glidetab/releases/latest) [![Total downloads](https://img.shields.io/github/downloads/mohdmahmodi/glidetab/total?label=downloads&color=333333)](https://github.com/mohdmahmodi/glidetab/releases) [![macOS 14 or later](https://img.shields.io/badge/macOS-14%2B-333333?logo=apple&logoColor=white)](#install) [![MIT License](https://img.shields.io/badge/license-MIT-333333)](LICENSE)

### [Download](https://github.com/mohdmahmodi/glidetab/releases/latest/download/GlideTab.zip) &nbsp;·&nbsp; [Website](https://glidetab.com) &nbsp;·&nbsp; [Compare](https://glidetab.com/compare)

<br>

<picture>
  <source media="(prefers-color-scheme: light)" srcset="docs/images/switcher-light.jpg">
  <img src="docs/images/switcher.jpg" width="860" alt="The GlideTab switcher showing six windows with live previews">
</picture>

<br><br>

<table>
  <tr>
    <td align="center" width="33%"><b>Every window</b><br><sub>Spaces, displays, minimized</sub></td>
    <td align="center" width="33%"><b>Type to search</b><br><sub>Windows and browser tabs</sub></td>
    <td align="center" width="33%"><b>Three looks</b><br><sub>Thumbnails, icons or a list</sub></td>
  </tr>
  <tr>
    <td align="center"><b>Your shortcuts</b><br><sub>Up to nine, a swipe, or ⌘Tab</sub></td>
    <td align="center"><b>Quick actions</b><br><sub>Close or minimize in place</sub></td>
    <td align="center"><b>Private</b><br><sub>No account, no tracking</sub></td>
  </tr>
</table>

<table>
  <tr>
    <td width="33%"><img src="docs/images/search.jpg" alt="Typing to search for a window"></td>
    <td width="33%"><img src="docs/images/style-list.jpg" alt="The list style"></td>
    <td width="33%"><img src="docs/images/style-icons.jpg" alt="The app icons style"></td>
  </tr>
  <tr>
    <td align="center"><sub>Search</sub></td>
    <td align="center"><sub>List</sub></td>
    <td align="center"><sub>App icons</sub></td>
  </tr>
</table>

</div>

## Install

1. [Download GlideTab.zip](https://github.com/mohdmahmodi/glidetab/releases/latest/download/GlideTab.zip) and unzip it.
2. Move GlideTab to Applications and open it.
3. Follow the setup. It explains each permission before macOS asks.

<p align="center">
<picture>
  <source media="(prefers-color-scheme: light)" srcset="docs/images/setup-light.png">
  <img src="docs/images/setup.png" width="480" alt="The setup window explaining why GlideTab needs Accessibility">
</picture>
</p>

<sub>macOS 14 or later, Apple silicon and Intel. Notarized by Apple. Updates itself.</sub>

## Keys

| Press | To |
| --- | --- |
| <kbd>⌥</kbd> + <kbd>Tab</kbd> | Open, then next window |
| <kbd>⇧</kbd> + <kbd>Tab</kbd> or arrows | Go back or move around |
| Let go of <kbd>⌥</kbd> | Switch |
| Type | Search |
| <kbd>Esc</kbd> | Clear, then close |

Everything else is in Settings, from the menu bar icon.

## Questions

<details>
<summary><b>Is it free?</b></summary>
<br>
Yes. No paid version, no trial, no account.
</details>

<details>
<summary><b>Why Accessibility and Screen Recording?</b></summary>
<br>
Accessibility lets it see the shortcut and bring windows forward. Screen Recording is only for thumbnails. The App Icons and List styles work without it.
</details>

<details>
<summary><b>Can it replace ⌘Tab?</b></summary>
<br>
Yes. Set a shortcut to <kbd>⌘</kbd> + <kbd>Tab</kbd> in Settings. The built-in switcher comes back when you quit GlideTab.
</details>

<details>
<summary><b>Why do some tabs and minimized windows show an icon?</b></summary>
<br>
macOS doesn't draw background tabs or minimized windows, so there's nothing to capture. GlideTab shows the last picture it has, or the app icon.
</details>

<details>
<summary><b>Why isn't it on the Mac App Store?</b></summary>
<br>
App Store apps can't switch to a window on another Space, which is the main thing GlideTab does.
</details>

<details>
<summary><b>Where does my data go?</b></summary>
<br>
Nowhere. Window titles and previews stay in memory. The only network request is the daily update check to GitHub, which you can turn off.
</details>

<details>
<summary><b>How do I uninstall it?</b></summary>
<br>
Quit it from the menu bar and move it to the Trash.
</details>

## For developers

<details>
<summary><b>Build it yourself</b></summary>
<br>

Needs macOS 14 and the Xcode Command Line Tools. No Xcode project.

```bash
xcode-select --install
git clone https://github.com/mohdmahmodi/glidetab.git
cd glidetab
./build.sh install
```

| Command | Does |
| --- | --- |
| `./build.sh` | Builds `build/GlideTab.app` |
| `./build.sh install` | Builds, installs and opens it |
| `./build.sh test` | Runs the tests |
| `./build.sh release` | Signs, notarizes and zips |

Copies you build can't install updates from this page.

</details>

<details>
<summary><b>Command line</b></summary>
<br>

Turn it on in Settings → General.

```text
glidetab list [--json]   List windows
glidetab focus <id>      Switch to a window
glidetab close <id>      Close a window
glidetab minimize <id>   Minimize a window
glidetab show            Open the switcher
glidetab settings        Open Settings
```

</details>

<details>
<summary><b>How it's built</b></summary>
<br>

Swift, AppKit and SwiftUI. About 5 MB, no third-party code.

| File | Does |
| --- | --- |
| `KeyStateMachine.swift` | Every keyboard decision, fully tested |
| `EventTap.swift` | Keyboard and trackpad input |
| `Switcher.swift` | One switching session |
| `WindowManager.swift` | Finds and focuses windows |
| `Browsers.swift` | Browser tabs |
| `Panel.swift` | The switcher window |
| `Settings/` | Settings and setup |
| `site/` | [glidetab.com](https://glidetab.com) |

</details>

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md), and report security issues as described in [SECURITY.md](SECURITY.md).

<br>

<div align="center">
<sub>Made by <a href="https://mohdmahmodi.com">Mohd Mahmodi</a> · <a href="https://x.com/mohdmahmodi">X</a> · <a href="https://github.com/mohdmahmodi">GitHub</a> · <a href="LICENSE">MIT License</a></sub>
</div>
