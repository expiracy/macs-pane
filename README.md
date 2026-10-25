# MacsPane

Drag a window to the notch, hold it there, and drop it into a layout.

MacsPane is a menu-bar window manager for macOS. When you drag a window by its title bar to the top of
the screen and rest it on the notch, the notch opens into a row of layouts: halves, thirds, quarters
and any you draw yourself. Let go on a box and the window fills it. Everything else (drawing and
applying presets, drawing layouts and settings) starts from the menu-bar icon.

## Installing the beta

Requires macOS 14 or later, on Apple silicon or Intel.

1. Open `MacsPane-1.0.0-beta.2.dmg` and drag MacsPane into Applications.
2. Open MacsPane from Applications. It has no Dock icon: it lives in the menu bar, and setup opens the
   first time.
3. In setup, click **Grant Access** and switch MacsPane on in System Settings › Privacy & Security ›
   Accessibility. It needs this to move and resize other apps' windows, and nothing else.

Beta builds are test builds, not signed by Apple, so macOS blocks the first open: click **Done**, then
open System Settings › Privacy & Security and click **Open Anyway** under the message about MacsPane.
You do this once. Later test builds keep the Accessibility permission. The disk image has these steps
in *How to open MacsPane.txt*.

To remove MacsPane, quit it from its menu, then delete it from Applications and
`~/Library/Application Support/MacsPane`.

## Using it

- **Snap a window.** Drag it by its title bar onto the notch and pause. Aim at a box in one of the
  layouts and let go. Letting go anywhere else leaves the window where you dropped it. An island on
  the left offers to tile the window beside the apps you used last, and one on the right holds your
  presets.
- **Presets.** *New preset* in the menu offers two ways. *From the current desktop* saves the windows
  on your screen as a preset straight away and lets you name it in the list. *Draw one…* opens the
  editor instead: the screen
  dims, drag to draw a box, drag a box to move it, pull its edges to resize it, and click *Choose an
  app* in each box to say what opens there. Clicking a preset in the menu (or dropping a window on it
  in the notch) puts each app back in its place, opening any that are closed, and an Undo grows out
  of the notch for a few seconds; its pencil opens it in the editor again.
- **Layouts.** *New layout* offers the same two: *Draw one…* opens the same editor with empty boxes,
  for the picker, and *From the current desktop* saves one with a box where each window is. Every
  layout, built-in or your own, is listed in the menu with a pencil to change it, a switch for whether
  the notch offers it and a bin to delete it. Deleted built-ins come back as they first were with
  *Restore built-in layouts*. Drag either list by a row's grip to reorder it; the notch offers its
  layouts in the same order as the menu. There is no separate Settings window: it is all in the menu.
- **Shortcuts.** In the editor every layout box has *Add shortcut*: click it and press the keys (with
  ⌘, ⌃ or ⌥, or a function key alone). Pressing them in any app sends the window you're in to that
  box, on the screen it is on. A preset's shortcut sits in its editor's toolbar and applies it, as
  clicking it in the menu does. A combination does one thing: giving it to something new takes it
  from whatever had it. esc keeps the shortcut a box had; ⌫ removes it. The menu's *Shortcuts* list
  shows every one with its keys: switch one off to let its keys through to your apps for a while,
  click its pencil to change it or its bin to remove it.

On its first run MacsPane opens a short setup window. You practise the drag on sample windows, grant
Accessibility (the one permission it needs, to move other apps' windows) and try the drag on a real
one, pick the layouts the notch offers, and switch on any suggested shortcuts (⌃⌥← and ⌃⌥→ for the
halves, ⌃⌥↩ to fill, ⌃⌥C to centre), trying them on the samples first. The menu's Setup button opens
it again.

## Building

Requires macOS 14 or later. The package builds with the Command Line Tools; the signed `.app` uses
Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
swift build              # build everything
swift test               # run the Core tests
scripts/run.sh           # build a MacsPane.app bundle and open it
```

`swift run macspane` also works, but Accessibility is granted per signed app, so a bundle signed with
a stable identity (`MACSPANE_SIGN_IDENTITY=…  scripts/run.sh`) keeps the grant across rebuilds.

For the Xcode project: `xcodegen generate`, then build the `MacsPane` scheme.

### Releasing

`scripts/release.sh beta.2` runs the tests, builds for Apple silicon and Intel, signs the app and packs
it in `dist/MacsPane-<version>-beta.2.dmg` with its SHA-256. The version is in `VERSION`; the build number is
the commit count, so every release is newer than the last.

To give it to other people, sign it with a Developer ID (from the Apple Developer Program) and have
Apple notarize it:

```sh
xcrun notarytool store-credentials macspane --apple-id <email> --team-id <TEAMID>   # once
MACSPANE_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" \
MACSPANE_NOTARY_PROFILE=macspane scripts/release.sh
```

Every release signed with the same Developer ID keeps the Accessibility permission people already
gave. Without an identity the script makes an ad-hoc test build, with *How to open MacsPane.txt* in the
disk image. Its signature asks only for MacsPane's bundle identifier, so testers keep Accessibility
across test builds; any other ad-hoc app claiming that identifier would get it too, so use a Developer
ID before a wide release.

## How it's put together

| Target | What it holds |
|---|---|
| `MacsPaneCore` | Pure logic with no AppKit: layouts, presets, snap zones, the picker's geometry, and the config file. Unit-tested. |
| `MacsPaneKit` | The app: the drag tracker (global mouse monitors, never consuming events), the notch panel and picker, Accessibility window moves, the menu-bar dropdown, the box editor and setup. |
| `macspane` | The executable that boots `MacsPaneKit`. |

Your choices are saved to `~/Library/Application Support/MacsPane/config.json`. Every field decodes with a
default, so a file from an older version never resets your presets.

`macspane --snapshot-macspane <dir>` renders each surface (the dropdown, the notch states, the box editor,
setup and the permission card) to PNGs without touching your windows.

## License

Copyright (C) 2026 James Gray

MacsPane is free software: you can redistribute it and/or modify it under the terms of the GNU Affero
General Public License as published by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version. Anything built from it, including a modified version you only offer
to others over a network, must be released under the same license with its source. See
[LICENSE](LICENSE) for the full text.
