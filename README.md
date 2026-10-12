<div align="center">

<img src="docs/images/icon.png" width="112" height="112" alt="GlideTab app icon">

# GlideTab

**Hold Option. Press Tab.**<br>
Every open window on your Mac, with a live preview.

[![Latest release](https://img.shields.io/github/v/release/mohdmahmodi/glidetab?label=release&color=333333)](https://github.com/mohdmahmodi/glidetab/releases/latest)
[![macOS 14 or later](https://img.shields.io/badge/macOS-14%2B-333333?logo=apple&logoColor=white)](#install)
[![Apple silicon and Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-333333)](#install)
[![MIT License](https://img.shields.io/badge/license-MIT-333333)](LICENSE)

### [Download](https://github.com/mohdmahmodi/glidetab/releases/latest/download/GlideTab.zip) &nbsp;·&nbsp; [Website](https://glidetab.com) &nbsp;·&nbsp; [Features](https://glidetab.com/features) &nbsp;·&nbsp; [Compare](https://glidetab.com/compare)

<br>

<picture>
  <source media="(prefers-color-scheme: light)" srcset="docs/images/switcher-light.jpg">
  <img src="docs/images/switcher.jpg" width="860" alt="The GlideTab switcher showing six windows with live previews">
</picture>

</div>

<br>

## What it does

<table>
  <tr><td width="160"><b>Every window</b></td><td>Each window gets its own spot, including other Spaces, other displays, minimized windows and hidden apps.</td></tr>
  <tr><td width="160"><b>Search</b></td><td>Start typing to filter windows and browser tabs. Works with Safari, Chrome, Brave, Edge, Vivaldi, Firefox and Zen.</td></tr>
  <tr><td width="160"><b>Your look</b></td><td>Thumbnails, app icons or a list, in four sizes, in light or dark.</td></tr>
  <tr><td width="160"><b>Your keys</b></td><td>Up to nine shortcuts with their own filters, a trackpad swipe, or take over ⌘Tab.</td></tr>
  <tr><td width="160"><b>Quick actions</b></td><td>Close, minimize or full screen a window right from the switcher.</td></tr>
  <tr><td width="160"><b>Private</b></td><td>No account, no analytics. Free and open source, with no paid version.</td></tr>
</table>

<table>
  <tr>
    <td width="50%"><img src="docs/images/search.jpg" alt="Typing to search for a window"></td>
    <td width="50%"><img src="docs/images/style-list.jpg" alt="The list style"></td>
  </tr>
  <tr>
    <td align="center"><sub>Type to search</sub></td>
    <td align="center"><sub>List style</sub></td>
  </tr>
  <tr>
    <td colspan="2"><img src="docs/images/style-icons.jpg" alt="The app icons style"></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><sub>App icons style</sub></td>
  </tr>
</table>

## Install

1. **[Download GlideTab.zip](https://github.com/mohdmahmodi/glidetab/releases/latest/download/GlideTab.zip)** and unzip it.
2. Move **GlideTab** to your Applications folder and open it.
3. Allow **Accessibility** when asked. Allow **Screen Recording** too if you want thumbnails.

That's it. Hold <kbd>⌥ Option</kbd>, press <kbd>Tab</kbd>, and let go to switch.

<sub>Works on macOS 14 Sonoma or later, on Apple silicon and Intel. Signed and notarized by Apple. GlideTab updates itself from this page.</sub>

## Keys

| Press | To |
| --- | --- |
| <kbd>⌥</kbd> + <kbd>Tab</kbd> | Open the switcher and move to the next window |
| <kbd>⇧</kbd> + <kbd>Tab</kbd> or arrow keys | Move back, or around the grid |
| Let go of <kbd>⌥</kbd> | Switch to the selected window |
| Type anything | Search windows and tabs |
| <kbd>Esc</kbd> | Clear the search, then close |

Everything else is in **Settings**, from the menu bar icon. It has a Help tab too.

## More

<details>
<summary><b>Questions</b></summary>

<br>

**Is it really free?**<br>
Yes. No paid version, no trial and no account.

**Why does it need Accessibility and Screen Recording?**<br>
Accessibility lets GlideTab read the shortcut and bring windows forward. Screen Recording is only for thumbnails and the full-size preview. The App Icons and List styles work without it.

**Can it replace ⌘Tab?**<br>
Yes. Set a shortcut to <kbd>⌘</kbd> + <kbd>Tab</kbd> in Settings. The built-in switcher comes back when you quit GlideTab.

**Why isn't it on the Mac App Store?**<br>
App Store apps can't switch to a specific window on another Space, which is the main thing GlideTab does.

**How do I uninstall it?**<br>
Quit it from the menu bar and move it to the Trash. If it's still in System Settings → General → Login Items, remove it there.

**Where does my data go?**<br>
Nowhere. Window titles and previews stay in memory. The only network request is the daily update check to GitHub, which you can turn off.

</details>

<details>
<summary><b>Command line</b></summary>

<br>

Turn it on in **Settings → General**, then:

```text
glidetab list [--json]   List windows (id, app, title, state)
glidetab focus <id>      Switch to a window
glidetab close <id>      Close a window
glidetab minimize <id>   Minimize a window
glidetab show            Open the switcher
glidetab settings        Open Settings
```

</details>

<details>
<summary><b>Build it yourself</b></summary>

<br>

You need macOS 14 or later and the Xcode Command Line Tools. There's no Xcode project.

```bash
xcode-select --install
git clone https://github.com/mohdmahmodi/glidetab.git
cd glidetab
./build.sh install
```

| Command | Does |
| --- | --- |
| `./build.sh` | Builds `build/GlideTab.app` |
| `./build.sh install` | Builds, installs to `/Applications` and opens it |
| `./build.sh test` | Runs the unit tests |
| `./build.sh release` | Signs with Developer ID, notarizes and zips |

macOS ties permissions to the app's signature. With an Apple Development certificate, `build.sh` uses it and permissions survive rebuilds. Without one, macOS asks again after each build. Copies you build can't install updates from this page, so turn off automatic updates in Settings.

</details>

<details>
<summary><b>How it's built</b></summary>

<br>

Swift with AppKit and SwiftUI, about 5 MB, no third-party code.

| File | Does |
| --- | --- |
| `KeyStateMachine.swift` | Every keyboard decision, as pure logic with exhaustive tests |
| `EventTap.swift` | Keyboard and trackpad input on their own threads |
| `Switcher.swift` | One switching session: items, search, selection, actions |
| `WindowManager.swift` | Finds windows and focuses them |
| `Browsers.swift` | Reads and switches browser tabs |
| `Panel.swift` | The switcher window |
| `Settings/` | The Settings window |
| `site/` | The website at [glidetab.com](https://glidetab.com) |

</details>

## Contributing

Bug reports and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to build, test and add translations. Report security issues privately, as described in [SECURITY.md](SECURITY.md).

<br>

<div align="center">
<sub>Made by <a href="https://mohdmahmodi.com">Mohd Mahmodi</a> · <a href="https://x.com/mohdmahmodi">X</a> · <a href="https://github.com/mohdmahmodi">GitHub</a> · <a href="LICENSE">MIT License</a></sub>
</div>
