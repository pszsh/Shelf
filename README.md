# Shelf

A clipboard manager for macOS. Hit `Cmd+Shift+V` or click the
tray icon.

I just didn't feel like this was a thing that should cost money.
Now it doesn't anymore.


## Preview

<img width="1934" height="386" alt="B39A5D5D-60D0-4B77-AA18-BACEC7DA2C42" src="https://github.com/user-attachments/assets/5031fe8d-3b71-4577-8714-4fde2e16fc59" />

## What it does

- Monitors your clipboard — text, URLs, images
- Cards show a preview, a title (file path with the filename bolded), and a timestamp
- Re-copying something moves it to the front instead of duplicating it
- Tracks where items were displaced from, so you can peek at old neighbors (click twice - not exactly double click, just... twice.)
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

[pszsh](https://else-if.org) - My Half-Assed blog.
Email: [jess@else-if.org](mailto:jess@else-if.org)

