# Hesh

Hesh is a lightweight Linux desktop environment for developing and testing web
devices, with a future path to real Android virtual devices. It is a native
Qt 6 application: QML owns presentation, modern C++ owns application state, the
device lifecycle, and persistence.

Every web device is a real embedded Chromium profile with its own cookies, local
storage, IndexedDB, and disk cache, previewed at a logical viewport size and
device pixel ratio. Devices can be previewed in the main workspace or opened as
independent windows the compositor can tile and move.

Current version: **0.1.6** (pre-release)

## Status

Working today:

- Frameless Qt Quick desktop window with a custom dark developer-tool theme
- Web devices with built-in viewport profiles: Pixel 7, Pixel 8, iPhone 14,
  Galaxy S24, iPad, Desktop, and a Custom profile
- Embedded Qt WebEngine preview with explicit states: animated loading with
  progress, classified connection errors with retry, and a stopped state
- Per-device isolated browser storage, persistent across restarts
- Hardware-accelerated rendering at native physical resolution on fractional
  HiDPI scales
- Standalone device windows that Hyprland can tile, float, resize, and move
  between workspaces
- Embedded Chromium DevTools with a persistent dark appearance
- Device lifecycle: start/stop per device, with run state persisted per device
- Per-device accent (six presets or "Follow App Accent") and per-device web
  content theme (System or Dark)
- Confirmed per-device **Clear Data** and **Remove Device** actions
- Drag-to-reorder devices in the sidebar, persisted with the device records
- Settings dialog (Devices, Preview, Appearance, Storage, Advanced) that applies
  immediately and persists through `QSettings`
- Core model coverage in `tests/device_tests.cpp`, run through CTest

Not implemented yet:

- Android devices: no QEMU, KVM, ADB, APK installation, images, or snapshots
- Back and forward controls in the embedded workspace toolbar (standalone
  windows have them in their right-click menu), and advanced DevTools hosting
  controls
- Project-local configuration or remote device management

## Requirements

- Linux
- CMake 3.24 or newer
- A C++20 compiler
- Qt 6.5 or newer with these modules:
  - Core
  - Gui
  - Quick
  - QuickControls2
  - WebEngineQuick (and `WebEngineCore`, pulled in by it)
  - Test

## Build and run

```bash
cmake -B build -S .
cmake --build build -j
./build/hesh
```

The `./hesh` script in the repository root does the same thing: it configures
`build/` on first use, builds, and launches the binary with any arguments you
pass it.

Run the core tests with:

```bash
ctest --test-dir build --output-on-failure
```

`--maximized` starts the main window maximized. `cmake --install build` installs
the `hesh` binary to `bin/` under the chosen prefix.

## Using Hesh

### Creating a device

**New Device** in the titlebar opens the create dialog with a name, a device
profile, and a starting URL; the sidebar's **+ Add Device** and the empty state's
**+ Create Device** open the same dialog. The profile supplies the viewport size,
device pixel ratio, and user agent. The name, URL, and profile the dialog opens
with are configurable in Settings → Devices.

### The device preview

The workspace shows the selected device inside a device frame with a toolbar
under it. The URL field and **Go** point the device at a new address, and the
toolbar reloads the page, toggles DevTools, and opens or focuses the standalone
window. On narrow windows those buttons collapse into an `⋯` overflow menu.

The toolbar also reports viewport metrics when Settings → Preview enables them:
logical viewport size, device pixel ratio, fit mode, and zoom level. Previews
scale down to fit the available space but never upscale unless Settings →
Preview allows it; upscaling softens text and can band colours.

The preview never renders a blank black surface: a stopped, loading, or failed
device shows that state inside the frame. Loading keeps a progress indicator
running until the page finishes, connection failures are classified with a
retry action, and a stopped device can be started again from there.

### Controlling devices

Click a sidebar card to select that device, or right-click it for the
per-device actions:

- **Accent** — six presets, or "Follow App Accent" to inherit the application
  accent
- **Theme** — System follows the desktop colour scheme; Dark applies Chromium's
  per-view force-dark rendering to that device only. There is no per-device
  Light: Qt WebEngine exposes no per-view light override
- **Start Device** / **Stop Device** — stopping keeps the device stopped across
  restarts; Hesh only starts devices that were running when state was last
  written
- **Open in Window** / **Focus Window** — detaches the device into its own
  frameless window
- **Clear Data** — wipes that device's cookies, local storage, IndexedDB, and
  cached files, then reloads it with a fresh session (confirmed)
- **Remove Device** — deletes the device record (confirmed)

Dragging a sidebar card reorders the list; the drop line marks where the card
will land, and the order is persisted with the device records.

### Standalone windows

**Open in Window** detaches a device into its own frameless window, sized to the
logical viewport and scaled down only if it would not fit the work area. The
embedded preview is released at the same time, so a device never holds two live
browser surfaces. Closing the window returns the device to the workspace; while
it is detached, the workspace shows a placeholder with a **Focus Window**
button.

Right-click inside a standalone window for its own menu: **Reload**, **Back**,
**Forward**, **Open in Browser**, **Main Window**, and **Close Window**.

Window placement and open state are session-only: reopening Hesh does not
restore standalone windows. Whether a device is *running*, however, does persist.

### Keyboard and window shortcuts

| Shortcut | Action |
| --- | --- |
| `Ctrl+R` | Reload the device page |
| `Ctrl+Shift+R` | Hard reload, bypassing the profile's disk cache |
| Double-click the titlebar | Maximize or restore the window |

These work in the main window and in standalone device windows.

### Settings

- **Devices** — name, URL, and profile the Create Device dialog starts from
- **Preview** — show DevTools on open, open new devices in a standalone window,
  allow upscaling, show viewport metrics
- **Appearance** — six accent presets that retint the interface live
- **Storage** — the device data and cache directories, Open Data Folder, and a
  confirmed Clear All Device Data action
- **Advanced** — extra Chromium flags with an explicit restart-required state
  and a relaunch action, plus read-only diagnostics (Hesh, Qt, and Chromium
  versions, HiDPI rounding policy, the flags this process runs with)

Everything applies immediately and persists. **Restore Defaults** clears the
preference group only, so devices and their browser data survive.

## Where Hesh stores data

Paths follow Qt's standard locations, so `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and
`XDG_CACHE_HOME` are honoured:

| What | Path |
| --- | --- |
| Preferences and device records | `~/.config/Hesh/Hesh.conf` |
| Device browser data | `~/.local/share/Hesh/Hesh/web-devices/<device-id>` |
| Device cache | `~/.cache/Hesh/Hesh/web-devices/<device-id>` |

Device records live in one JSON value in the settings file, next to the
`preferences` group. Browser state is isolated by device id and is never written
into the source tree. **Clear Data** removes the browser data but keeps the
device; **Clear All Device Data** does the same for every device.

**Remove Device** deletes the device record only; the browser data directories
above stay on disk, and once the device is gone there is no UI left to clear
them. Use **Clear Data** first if you want the browsing state erased, or delete
the directory by hand.

## Hyprland integration

The standalone-window rule is kept in
[config/hypr/hesh.lua](config/hypr/hesh.lua) so it can be versioned with Hesh.
Install it into Omarchy/Hyprland with:

```bash
mkdir -p ~/.config/hypr
cp config/hypr/hesh.lua ~/.config/hypr/hesh.lua
```

Then add `require("hypr.hesh")` once to `~/.config/hypr/hyprland.lua` and reload
the compositor with `hyprctl reload`. The rule floats and centers standalone
device windows, keeps them opaque, and leaves compositor borders and shadows
available.

On Wayland the application uses a frameless Qt Quick window and calls the
compositor's system move operation for titlebar dragging. XWayland keeps working
through Qt's normal platform handling.

## Architecture

```text
QML UI
   ↓
Application
   ├── Settings
   ├── Preferences
   └── DeviceManager
          ↓
       Device
        ├── WebDevice
        └── AndroidDevice [future]
```

`Hesh::Application` owns one `Settings`, one `Preferences`, and one
`DeviceManager`; the manager owns the `Device` objects and exposes them as a
`QAbstractListModel`. QML reads that model and never owns the canonical device
collection. `src/android/` is documentation only for now.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — ownership, persistence,
  logical viewport scaling, presentation hosts, and the planned Android runtime
  boundary
- [docs/QUALITY.md](docs/QUALITY.md) — how previews stay sharp and colour
  accurate across profiles and HiDPI scales, plus the checklist for adding a
  viewport profile

## Roadmap

### Phase 2 — Web Device runtime and host controls

The standalone host is in place without changes to `DeviceManager`. Remaining
work is proving the browser runtime boundary further and adding navigation and
advanced host controls.

### Phase 3 — QEMU/KVM Android runtime prototype

Once the device and presentation abstractions are proven, add a small Android
runtime prototype around QEMU/KVM. That phase establishes process lifecycle and
image contracts before ADB, APK, and snapshot features expand the scope.
