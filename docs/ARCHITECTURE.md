# Hesh architecture

This document describes Hesh **0.1.4**.

Hesh keeps the QML presentation layer separate from the C++ application and
device infrastructure.

```text
QML UI
   ↓ context properties and QObject properties
Application
   ├── Settings
   └── DeviceManager
          ↓ QAbstractListModel + selectedDevice
       Device
        ├── WebDevice
        └── AndroidDevice [future]
```

## Application ownership

`Hesh::Application` owns one `Settings` instance and one `DeviceManager`.
`DeviceManager` owns the dynamically created `Device` objects through Qt
parent ownership. QML receives the manager and reads its model; it does not own
or maintain the canonical device collection.

`Settings` is a small replaceable boundary over `QSettings`. It serializes the
device list as compact JSON in one settings value, plus the selected device id.
This keeps persistence out of QML and leaves room for a database or project
file later.

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

`Device` contains identity, type, lifecycle status, and display profile data.
`WebDevice` adds its URL and owns the web-device lifecycle boundary. The model
uses roles backed by actual `Device` objects, rather than two hardcoded device
slots or a large collection of QVariant maps.

Phase 1 supports the Web type. Android records are deliberately not created or
emulated yet; the future type can be added without changing the manager's
collection, selection, or model APIs.

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
