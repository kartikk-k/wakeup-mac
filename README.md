# Wakeup

A simple, free, and open-source macOS menu bar app that prevents your Mac from sleeping — inspired by Lungo.

![Wakeup preview](preview.png)

## Features

- Keep your Mac awake for a chosen duration or indefinitely
- Live countdown in the menu bar and in the popover
- Two modes:
  - Prevent display sleep (screen stays on)
  - Allow display sleep (system stays awake)
- Quick 30-minute start + presets + custom duration
- Native SwiftUI + Apple design guidelines
- No Dock icon (pure menu bar app)
- Uses the built-in `caffeinate` tool under the hood

## Requirements

- macOS 13 Ventura or later (MenuBarExtra + modern SwiftUI)
- Built with Xcode 16+

## Build & Run

1. Open `Wakeup.xcodeproj` in Xcode
2. Select the `Wakeup` scheme
3. Build & Run (⌘R)
4. The coffee mug icon ☕ will appear in your menu bar (right side)

## Usage

- Click the coffee mug icon to open the panel
- Tap **"Keep awake for 30 minutes"** for quick use, or choose any other duration
- Or enter a custom number of minutes
- Toggle **"Allow display to sleep"** if you want the screen to turn off while keeping the system awake
- Click **Turn Off** anytime to restore normal sleep behavior
- The remaining time is shown directly in the menu bar while active

## How it works

Wakeup launches the system `caffeinate` command with the appropriate flags:
- `-d` — prevent the display from sleeping
- `-i` — prevent system idle sleep (allows display sleep)
- `-t <seconds>` — for timed sessions

When the time expires or you turn it off, the assertion is released and your Mac behaves normally.

## Design

- Follows official Apple Human Interface Guidelines
- Uses SF Symbols (coffee mug "mug.fill"), native controls, proper spacing and typography
- Clean minimal popover (no unnecessary chrome)

## Custom Menu Bar Icon

The app uses the built-in SF Symbol `mug` / `mug.fill` as the coffee icon.

To use a custom coffee icon (recommended for a polished app):

1. In Xcode, open `Assets.xcassets`
2. Replace the `MenuBarIcon` imageset with a vector PDF (black on transparent)
3. In the asset inspector, set **Render As** → **Template Image**
4. Rebuild

A good source is to export the "mug" symbol from the official SF Symbols app and edit it, or design a simple coffee mug in 16–22 pt height.

## License

MIT — free and open source.

## Credits

Inspired by Lungo (by Sindre Sorhus / Setapp). This is an independent clone created for learning and personal use.
