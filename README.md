# MacsPane

Drag a window to the notch, hold it there, and drop it into a layout.

MacsPane is a menu-bar window manager for macOS. When you drag a window by its title bar to the top of
the screen and rest it on the notch, the notch opens into a row of layouts: halves, thirds, quarters
and any you save yourself. Let go on a box and the window fills it. Everything else (applying a saved
arrangement of apps, saving the windows you have open, Undo and settings) lives in the menu-bar
dropdown.

## Using it

- **Snap a window.** Drag it by its title bar onto the notch and pause. Aim at a box in one of the
  layouts and let go. Letting go anywhere else leaves the window where you dropped it. When other
  apps are open, the picker also offers to tile the window beside the apps you used last.
- **Presets.** Arrange your windows, then choose *Save windows as a preset* in the menu. Clicking the
  preset there puts each app back in its place, opening any that are closed.
- **Layouts.** *Save windows as a layout* turns the windows on screen into an empty layout for the
  picker. Settings chooses which layouts the picker offers, as many as you like.

On its first run MacsPane opens a short setup window that asks for Accessibility (the one permission
it needs, to move other apps' windows) and lets you practise the drag on sample windows.

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

## How it's put together

| Target | What it holds |
|---|---|
| `MacsPaneCore` | Pure logic with no AppKit: layouts, presets, snap zones, the picker's geometry, and the config file. Unit-tested. |
| `MacsPaneKit` | The app: the drag tracker (global mouse monitors, never consuming events), the notch panel and picker, Accessibility window moves, the menu-bar dropdown, Settings and setup. |
| `macspane` | The executable that boots `MacsPaneKit`. |

Settings are saved to `~/Library/Application Support/MacsPane/config.json`. Every field decodes with a
default, so a file from an older version never resets your presets.

`macspane --snapshot-macspane <dir>` renders each surface (the dropdown, the notch states, Settings,
setup and the permission card) to PNGs without touching your windows.
