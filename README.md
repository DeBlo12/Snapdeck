# Snapdeck

A small, native window manager for macOS that works like window management on Windows:
snap windows with the keyboard or by dragging them to a screen edge, define your own
layouts, and save and restore whole window setups.

Written in Swift using only Apple system frameworks. No third-party dependencies.

## Features

- **Keyboard snapping** with Windows-style behaviour: halves, quarters, maximise, restore.
  Pressing left or right again moves the window to the next display.
- **Drag to edge**: drag a window to the left, right or top edge (or a top/side corner)
  and drop it on the preview.
- **Layouts**: named combinations of zones, such as "Main + Stack". Send the focused
  window to a zone, or arrange the front-most windows into the layout in one step.
- **Setups**: save where all your windows are and restore that arrangement later.
  Apps that are not running are launched first.
- **Hover previews**: hovering over an item in the menu bar menu shows on screen
  where the window (or windows) would go.
- **Settings** (`⌘,` while the menu is open): launch at login, gap between windows,
  modifier keys for the shortcuts, active layout, saved setups.

## Shortcuts

The default modifier keys are Control + Option; they can be changed in the settings.

| Shortcut | Action |
| --- | --- |
| `⌃⌥←` / `⌃⌥→` | Left / right half; from a quarter, move sideways; again, next display |
| `⌃⌥↑` | Half → top quarter, otherwise maximise |
| `⌃⌥↓` | Top quarter → half → bottom quarter, otherwise restore the original size |
| `⌃⌥↩` | Maximise |
| `⌃⌥C` | Centre |
| `⌃⌥1` … `⌃⌥9` | Move the window to that zone of the active layout |
| `⌃⌥A` | Arrange the front-most windows into the active layout |

## Build and run

Requires macOS 13 or later and the Swift toolchain (Xcode or the Command Line Tools).

```bash
./scripts/bundle.sh
```

```bash
open build/Snapdeck.app
```

On first launch macOS asks for **Accessibility** access (System Settings → Privacy &
Security → Accessibility). This is the only supported way for an app to move other
apps' windows. Snapdeck appears in the menu bar and has no Dock icon.

Run the unit tests with:

```bash
swift test
```

## Configuration

Config lives in `~/Library/Application Support/Snapdeck` (Settings → Layouts → *Edit layouts.json*).

`layouts.json` holds the layouts and is meant to be edited by hand. Each zone is a
fraction of the usable screen area, measured from the top-left corner:

```json
[
  {
    "name": "Main + Stack",
    "zones": [
      { "x": 0,   "y": 0,   "width": 0.6, "height": 1 },
      { "x": 0.6, "y": 0,   "width": 0.4, "height": 0.5 },
      { "x": 0.6, "y": 0.5, "width": 0.4, "height": 0.5 }
    ]
  }
]
```

Press *Reload* in the settings after editing. `setups.json` is written by
*Save Current Setup…*.

## Known limitations

- macOS has its own edge tiling (System Settings → Desktop & Dock → "Drag windows to
  screen edges to tile"). Turn it off if both previews appear.
- Setups match windows by app and window title, then by order. Apps with many
  similar windows may be restored in a different order.
- There is no public API for moving windows between Spaces, so setups apply to the
  current Space.
- The app is ad-hoc signed by default. After rebuilding, macOS may ask you to grant
  Accessibility access again. To avoid that, sign with a certificate of your own:
  `CODESIGN_IDENTITY="<name or hash>" ./scripts/bundle.sh`.
- If Snapdeck is switched on in the Accessibility list but still reports that access
  is missing, the entry belongs to an older build. Quit Snapdeck, run
  `tccutil reset Accessibility dev.snapdeck.Snapdeck`, start it again and grant access.
- Only the modifier keys of the shortcuts can be changed, not the individual keys,
  and there is no visual layout editor.

## Project structure

- `Sources/SnapdeckCore`: pure geometry and models, covered by unit tests.
- `Sources/Snapdeck`: the menu bar app (Accessibility, hotkeys, drag snapping, menu).
- `scripts/bundle.sh`: builds `build/Snapdeck.app`.

## Licence

MIT. See [LICENSE](LICENSE).
