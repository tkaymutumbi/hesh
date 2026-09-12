# Hesh architecture

This document describes Hesh **0.1.5**.

Hesh keeps the QML presentation layer separate from the C++ application and
device infrastructure.

```text
QML UI
   ↓ QML singleton, context properties and QObject properties
Application
   ├── Settings
   ├── Preferences
   └── DeviceManager
          ↓ QAbstractListModel + selectedDevice
       Device
        ├── WebDevice
        └── AndroidDevice [future]
```

## Application ownership

`Hesh::Application` owns one `Settings` instance, one `Preferences` instance,
and one `DeviceManager`. `DeviceManager` owns the dynamically created `Device`
objects through Qt parent ownership. QML receives the manager and reads its
model; it does not own or maintain the canonical device collection.

`Settings` is a small replaceable boundary over `QSettings`. It serializes the
device list as compact JSON in one settings value, plus the selected device id.
This keeps persistence out of QML and leaves room for a database or project
file later.

## Preferences

`Preferences` is the QML-facing boundary over everything in `Settings` that is
not a device record. It owns the preference keys, their defaults, their
validation, and the change notifications QML binds to, so no QML file parses or
writes a settings key. It is registered as the `Preferences` QML singleton in
`main.cpp`: preferences are read from unrelated corners of the tree — the
palette, the preview frame, the toolbars, the create-device dialog — and
threading one object through all of them would add plumbing without adding
clarity. Device-scoped objects keep their existing explicit `manager`
injection.

Preferences live under a `preferences` group in the same settings file as the
device records. `Settings::resetPreferences()` removes that group and nothing
else, so "Restore Defaults" can never delete a device or its browser data. Two
preferences are the exception to the object boundary: the extra Chromium flags
are read through `Hesh::storedExtraChromiumFlags()` and merged into
`QTWEBENGINE_CHROMIUM_FLAGS` before `QtWebEngineQuick::initialize()`, because
Chromium reads its command line before any `Application` exists. Both readers
resolve the key through `Settings::preferenceSettingsKey()`.

Flag precedence is deliberate: stored preferences first, then the environment,
then the rendering guards. Chromium keeps the last value for a repeated switch,
so a flag exported for one launch outranks the stored preference, and the
guards that keep covered Wayland surfaces producing frames always apply. A
stored-flag edit cannot take effect in the running process, so `Preferences`
reports `restartRequired` against the flags this process actually started with
and the settings dialog offers a relaunch instead of pretending the change
applied.

The accent is six presets rather than a free colour. The base accent has three
derived shades — `accentStrong`, `accentSoft`, and `accentBorder`, the last of
which used to be hardcoded at the selected-device card and the empty-state
badge — and a preset table is the only thing that keeps them coherent for
values nobody has tested. `Theme` stays a plain palette: `Main.qml` binds the
stored accent into it, and every consumer already binds to `Theme.accent`, so a
change repaints the whole UI, including standalone windows, without any
component re-reading a preference.

A device can carry an accent of its own. `DeviceRecord.accent` holds a preset
name, and an empty name means the device follows the application accent, which
is what every record written before the feature existed has. The fallback is
resolved in QML by the two surfaces that show a device — `DeviceListItem` and
`DeviceFrame` — rather than in the model: a device never reads application
preferences, so the dependency stays one-way. `Device::setAccentName()` rejects
a name the catalog does not contain back to "follow the app accent" instead of
storing a colour this build cannot draw. The picker lives in the device context
menu, which keeps the app-level choice in Settings and the device-level choice
on the device visibly separate, and `AccentPicker` renders both from the single
C++ catalog, so the two pickers cannot disagree about what a preset looks like.

Settings that drive rendering are read where the value is consumed:
`DeviceWorkspace` takes the metrics and DevTools preferences, and passes the
upscale preference to `DeviceFrame.allowUpscale`. The workspace also receives a
`dialogOpen` flag, because its `Ctrl+R` and `Ctrl+Shift+R` shortcuts are
application-level and would otherwise fire into a page the settings dialog is
covering.

The settings dialog is a modal `Popup`, like `Create Device` and `Clear Data`.
A popup leaves the device workspace and its live `WebEngineView` mounted
underneath, which keeps the browser-surface lifecycle out of the settings path
entirely. `ClearDeviceDataDialog` serves both the per-device menu action and the
settings dialog's Clear All action, so the confirmation wording and the wipe
protocol have one implementation.

The settings dialog is reachable from the titlebar in every window size. Below
`compactWindow` the labelled button would not fit, so the titlebar hosts a
`SettingsGlyph` overlay on an `IconButton` instead of a text character: a font
gear can be substituted by a colour emoji, and an icon font or raster asset
would be a heavier contract than three drawn tracks. `SettingsGlyph` follows the
empty-state device glyph, which is drawn from primitives for the same reason.
Icons in this UI are drawn or bundled, never emoji characters.

Browser persistence is separate from device metadata. Each web device receives
an isolated `WebEngineProfile` keyed by its stable device id. Cookies, local
storage, IndexedDB, and other browser data use the platform application-data
directory, while disposable HTTP and rendering caches use the platform cache
directory. QML converts `StandardPaths` URLs to native filesystem paths before
passing them to WebEngine; passing a `file://` URL to those string properties
would incorrectly create a relative `file:` directory.

Clearing a device's browser data is driven by `Device::clearData()`. Because
Chromium keeps the storage directories busy while a profile is alive, the
sequence is: emit `dataClearing()` so the presentation host releases its
`WebEngineProfile`; remove the storage directories on the next event-loop turn;
emit `dataCleared()` so the host rebuilds a fresh surface and page session.
`DeviceStorage` is the single source of the on-disk layout: `WebDevice` exposes
both directories and `DeviceFrame` binds its profile to them, so the profile
that writes the data and the operation that wipes it can never disagree.

## Device model

`Device` contains identity, type, lifecycle status, display profile data, and an
optional accent. `WebDevice` adds its URL and owns the web-device lifecycle
boundary. The model
uses roles backed by actual `Device` objects, rather than two hardcoded device
slots or a large collection of QVariant maps.

Run state is part of a persisted record. `DeviceRecord.running` is written
whenever a device starts or stops — not on exit — so a stopped device is already
stopped in storage if the process is killed. Loading starts only the devices
whose record says they were running; Hesh never starts the whole collection
because it launched, and a record written before the flag existed has no
`running` key and therefore loads stopped. A restored stopped device renders the
frame's stopped state, which is what makes that state visible at startup instead
of a preview that silently starts.

List order is the record order, so a reorder is a data change rather than a view
concern. Dragging a device in the sidebar calls `DeviceManager::moveDevice()`,
which clamps the drop position, resolves it against the dragged row, moves the
row through `beginMoveRows`/`endMoveRows` — so the view moves delegates instead of
rebuilding them — and persists the whole list in its new order. Drop positions
are insertion boundaries, not row indexes: dragging a row onto its own boundary,
or the one just after it, is a no-op rather than a shuffle, which is what makes a
drag that ends where it started harmless. `DeviceListModel::moveDevice()` takes
indexes in the resulting order and converts to the destination row
`beginMoveRows` expects.

The interaction is deliberately a translated card plus a drop line rather than a
list that reflows during the drag. Live reflow would move the dragged delegate
under the pointer as the model reorders, and keeping it pinned under the cursor
then means compensating for the model's own movement on every step; the sidebar
is short enough that an explicit insertion line communicates the drop better, and
the card's anchors stay intact because only a `Translate` transform is applied.

Phase 1 supports the Web type. Android records are deliberately not created or
emulated yet; the future type can be added without changing the manager's
collection, selection, or model APIs.

## Device content theme

A device persists a web content theme: `system` (follow the desktop colour
scheme) or `dark`. Qt WebEngine exposes Chromium's force-dark rendering as a
per-view attribute — `QWebEngineSettings::ForceDarkMode`, surfaced in QML as
`WebEngineView.settings.forceDarkMode` — so `dark` turns darkening on for that
device's view and nothing else. `DeviceFrame` binds it to the device's stored
value and reloads a running device once when the value changes, because a
renderer setting only takes effect at the next paint of a loaded document.

Two measured facts shape this:

- **The desktop scheme reaches web content.** With the application colour scheme
  forced light, `matchMedia('(prefers-color-scheme: dark)')` reports `false`; on a
  `prefer-dark` desktop it reports `true`. `system` therefore is not "always
  light" — a page that supports dark mode already renders dark here, and `dark`
  adds Chromium's darkening for pages that ignore the scheme.
- **Force dark is a paint-stage filter.** Computed styles keep reporting the
  page's own colours (`rgb(255, 255, 255)`) while the rendered pixels are dark
  (`#121212`), so nothing in the page can detect it. It needs no Chromium
  command-line feature flag; the attribute alone is effective on Qt 6.11.

There is deliberately no third "light" state. Qt WebEngine has no per-view
override for the preferred colour scheme — the only lever is the application-wide
`QStyleHints::setColorScheme()`, which would flip every device and the window's
own rendering at once — and a stylesheet's `@media (prefers-color-scheme: …)`
rules are evaluated by Blink, so a script cannot re-evaluate them for one view.
A per-device "light" would be a control that lies about what it does.

## Profiles

`DeviceProfile` is a value type for logical viewport width and height, device
pixel ratio, and user agent. The built-in catalog includes Pixel 7, Pixel 8,
iPhone 14, Galaxy S24, iPad, Desktop, and Custom.

The web content's logical viewport is kept separate from its visual scale.
`DeviceFrame` sizes `WebEngineView` directly to its visual size and sets
`zoomFactor` to `presentationScale`, so `CSS viewport = visual / zoom` stays
at the profile's logical size. The view is not scaled with an `Item.scale`
transform, which avoids bilinear-filter blur and respects the window's
`devicePixelRatio` (with `PassThrough` rounding on fractional Wayland scales)
for crisp native raster.

The preview runs with WebEngine's normal hardware-accelerated backend. Loading
state is driven by both navigation status and load progress so a rendered page
is revealed promptly, including development servers whose final navigation
notification can arrive late.

## Preview states

`DeviceFrame` shows exactly one of four preview states, derived from the device
status and the WebEngine load state:

```text
stopped   ── start ──▶ loading ── rendered ──▶ ready
                          │                      │
                          └── load failed ──▶ error ── retry ──▶ loading
```

The state overlay is opaque and covers the `WebEngineView` in every state but
`ready`, so a stopped, failed, or still-loading device can never show a black
surface. Its text renders at unscaled pixel sizes while its content width
follows the device screen, so a scaled-down preview shrinks the state instead
of clipping the progress bar.

- `loading` animates a spinner, names the target URL, and reveals a determinate
  progress bar once Chromium reports progress. A load that reports no progress
  for four seconds says it is still waiting, which covers a connection that
  black-holes instead of refusing. When the load succeeds the overlay holds the
  completed bar for a beat before revealing the page, so progress is never seen
  stopping short of the end.
- `error` classifies the raw Chromium code (`net::ERR_…`) into a plain-language
  title and explanation — offline, DNS, refused, timeout, certificate, HTTP
  status — keeps the raw code as secondary detail, and offers Retry.
- `stopped` explains that the device is not running and offers Start Device
  through `DeviceManager`, so a stopped preview cannot be mistaken for a slow
  one. Reloading a stopped device is a no-op: the frame never enters `loading`
  without a navigation, because the device URL binding is pinned to
  `about:blank` whenever the device is not running.
- Only a render process crash retries on its own.

## Developer tools

`DeviceFrame` hosts Chromium DevTools in a second `WebEngineView` whose
`inspectedView` is the device preview. DevTools has its own preference store,
so Hesh selects its native `uiTheme` setting after the frontend initializes
rather than applying a content color inversion filter.

## Presentation boundary

The presentation layer can route a device to either an embedded workspace or
an independent top-level window. The device model does not depend on either
host:

```text
Device
   ↓
Presentation
   ├── Embedded
   └── Standalone
```

`StandaloneDeviceWindow.qml` binds to the same `Device` object as the embedded
host. Main-window presentation state owns one window per device, removes the
embedded `WebEngineView` before creating a standalone host, and destroys that
surface before restoring the embedded preview. Both hosts create a
device-id-keyed `WebEngineProfile`, so cookies, local storage, IndexedDB, and
disk cache persist while transient page state can reset when a host changes.
Standalone windows are frameless, have no transient parent, and scale a fixed
logical viewport inside the compositor-sized window. Their initial size is
calculated from Qt's available screen work area so reserved panels are left
visible, and the standalone presentation never upscales the browser surface.
Their placement and open state are session-only and are not restored from
`Settings`.

## Future Android runtime

The intended future boundary is:

```text
AndroidDevice
      ↓
AndroidRuntime
      ↓
QEMU
      ↓
KVM
```

`AndroidRuntime` will eventually own QEMU process lifecycle, KVM detection,
image selection, CPU/RAM/storage configuration, ADB connectivity, APK
installation, and snapshots. None of those capabilities are present in Phase
1, and `src/android/README.md` is documentation only.
