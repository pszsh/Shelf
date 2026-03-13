# Shelf

A clipboard manager for macOS. Sits in your menu bar, watches what you copy, shows it
all in a floating shelf at the bottom of your screen. Hit `Cmd+Shift+V` or click the
tray icon.

You know Paste? It's that, but yours. No subscription, no account, no telemetry.
Rust backend, Swift frontend, zero dependencies beyond what ships with your Mac.

## What it does

- Monitors your clipboard — text, URLs, images
- Cards show a preview, a title (file path with the filename bolded), and a timestamp
- Re-copying something moves it to the front instead of duplicating it
- Tracks where items were displaced from, so you can peek at old neighbors
- Space bar opens native Quick Look on the selected card
- Arrow keys to navigate, Return to paste, Delete to remove
- Starts on login automatically
- Lives in the menu bar, stays out of your way

## Building

Needs Rust and Xcode command line tools.

```
bash build.sh
```

App lands in `build/Shelf.app`.

## Installing

```
bash install.sh
```

Builds, kills any running instance, drops it into `/Applications`, opens it.

## Debug build

```
bash debug.sh
```

## Structure

```
core/       Rust — clipboard monitoring, SQLite storage, FFI exports
bridge/     C header bridging Rust to Swift
src/        Swift — UI, panel, app lifecycle
resources/  Icon SVG, Info.plist
```

## Author

[pszsh](https://else-if.org)
