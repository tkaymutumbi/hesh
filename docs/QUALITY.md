# Hesh Rendering Quality Guide (0.1.3–0.1.4)

This document explains why device previews were blurry *and* why colors were off, how `0.1.3`/`0.1.4` fixes both for **all profiles**, and how to keep quality crisp when adding future profiles or presentation modes.

## 1. TL;DR — The Rule

* **DO:** Size `WebEngineView` directly to its *visual* DIPs and set `zoomFactor = presentationScale`. CSS stays correct because `CSS = visual / zoom = viewport`.
* **DO NOT:** Wrap `WebEngineView` in an `Item { scale: presentationScale; smooth:true }` — it rasterizes at `viewport * Screen.devicePixelRatio` then bilinear-filters to `visual`, causing blur on every downscale.
* **DO:** Set `QGuiApplication::setHighDpiScaleFactorRoundingPolicy(PassThrough)` *before* `QGuiApplication` + `QtWebEngineQuick::initialize()` so fractional Wayland scales (1.25/1.5) use native backing stores.
* **DO:** Keep `minimumPresentationScale >= 0.25` / `maximum <= 5.0` — WebEngine clamps `zoomFactor` to `[0.25, 5.0]`; outside that CSS breaks.

If you follow the rule, Pixel 7 (412×915 @2.625), Pixel 8 (412×915 @2.75), iPhone 14 (390×844 @3.0), Galaxy S24 (360×780 @3.0), iPad (820×1180 @2.0) and Desktop (1440×900 @1.0) all render crisp from the same code path.

## 2. What Was Blurry (0.1.2)

`qml/components/DeviceFrame.qml:151-159` (pre-0.1.3):
```qml
Rectangle { id: frame
  width: viewportWidth + bezel*2   // 436 DIPs for Pixel 7
  height: viewportHeight + bezel*2 // 939 DIPs
  scale: presentationScale         // ~0.56 to fit 620×560 workspace
  smooth: true
  WebEngineView { anchors.fill: parent; zoomFactor: 1.0 }
}
```
* `WebEngineView` backing = `436 * Screen.devicePixelRatio` (e.g. `1.5` → `654` physical px) then QML `scale` bilinear-filters to `244` DIPs. Text hinting is lost, images are filtered.
* `zoomFactor:1.0` ignored `DeviceProfile.devicePixelRatio` (`src/devices/DeviceProfile.cpp:28-42`), so high-DPR profiles fetched 1× assets but displayed as if 3×.
* On Hyprland fractional scale, Qt rounded DPR (`1.5 → 2`), compositor then downscaled again — double blur. No `PassThrough` policy in `src/main.cpp`.

Result: the “Sign In” screenshot looks soft / pixelated at any profile, worse on fractional scales.

## 3. How 0.1.3 Fixes It For All Profiles

### 3.1 Direct geometry, no Item.scale
`qml/components/DeviceFrame.qml:189-223`:
```qml
property real effectiveBezel: bezel * presentationScale
property real effectiveRadius: screenRadius * presentationScale
Rectangle { id: frame
  width: (viewportWidth + bezel*2) * presentationScale // visual DIPs
  height: (viewportHeight + bezel*2) * presentationScale
  // no `scale`, no `smooth`
  radius: effectiveRadius
  Rectangle { id: contentSurface
    anchors.margins: effectiveBezel
    WebEngineView {
      anchors.fill: parent
      // visual = (viewport*presentationScale)
      // zoom = presentationScale
      // → CSS = visual/zoom = viewport (logical size preserved)
      zoomFactor: Math.max(0.25, Math.min(5.0, presentationScale))
    }
  }
}
```
Backing = `visual * Screen.devicePixelRatio` (native, never filtered). Chromium rasterizes *at* display size with correct hinting.

### 3.2 HiDPI PassThrough
`src/main.cpp:34-38`:
```cpp
QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
    Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
QtWebEngineQuick::initialize();
```
Keeps `1.25/1.5` reports as `1.25/1.5`, not rounded to `1` or `2`. Required before `QGuiApplication` construction.

### 3.3 Profile DPR emulation (JS)
`qml/components/DeviceFrame.qml:44-68` `syncDevicePixelRatio()`:
* After `onLoadingChanged: LoadSucceeded` and `onLoadProgressChanged:100%`, runs `window.devicePixelRatio = profileDpr` + injects `meta[name=viewport] width=<viewportWidth>` if missing.
* Lets `srcset`, `image-set()`, `matchMedia('(resolution: 2.625dppx)')` pick high-res assets even though native backing is `Screen.devicePixelRatio`-based.
* `onDeviceChanged` updates `deviceProfile.instance().httpUserAgent` and re-syncs DPR when switching devices.

### 3.4 Clamping
`qml/components/DeviceFrame.qml:18-20`:
```qml
property real minimumPresentationScale: 0.25 // was 0.1
property real maximumPresentationScale: 5.0  // was 8.0, WebEngine max
```
Prevents invisible `zoomFactor <0.25` clamping which would make `CSS = visual/0.25 ≠ viewport`.

### 3.5 Standalone windows
`qml/components/StandaloneDeviceWindow.qml:42` → width `Math.round(viewport*initialPresentationScale)` already uses work area. With new `DeviceFrame`, standalone uses `presentationScale≈1.0` → `zoomFactor≈1.0` → 1:1 crisp. No change needed beyond inheriting the fix.

## 4. Adding a New Profile — Checklist

1. Add to `src/devices/DeviceProfile.cpp:catalog()`:
   ```cpp
   {QStringLiteral("My Device"), <width>, <height>, <dpr>, QStringLiteral("<userAgent>")},
   ```
2. No QML change needed. Verify in `qml/pages/DeviceWorkspace.qml:173` DPR badge shows `<dpr>`.
3. Manual QA at workspace sizes `620×560` (embedded) and `Screen.desktopAvailableWidth/Height` (standalone):
   ```
   cmake -B build -S . && cmake --build build -j && ./build/hesh
   # Test fractional scales
   QT_SCALE_FACTOR=1.25 ./build/hesh
   QT_SCALE_FACTOR=1.5 ./build/hesh
   ```
   * Check `window.devicePixelRatio` in DevTools console equals profile DPR after `syncDevicePixelRatio`.
   * No texture blur at `presentationScale 0.25–1.0` (resize window).
4. If profile needs true network-level DPR (to fetch 3× images before JS runs), future work is CDP: `Emulation.setDeviceMetricsOverride` via private WebEngine DevTools protocol. For now JS + `zoomFactor` is sufficient for good quality.

## 5. Future Presentation Modes — Do/Don’t

* **Embedded Fit (0.1.3)** — `maximumPresentationScale:1.0`, downscale only. Crisp because `zoom <1`.
* **Standalone** — same, never upscale (`allowUpscale:false`). Prevents `zoom>1` upscaling blur on portrait → landscape.
* **If you add “Zoom / Fill” (`allowUpscale:true`)** — keep `maximum 5.0`, but warn: `zoom>1` upscales raster → slight softness is expected. Prefer increasing `availableWidth/Height` over `zoom>1` for desktop profiles.
* **Do not** reintroduce `Item.scale` on any ancestor of `WebEngineView`. If chrome needs scaling, scale only the chrome `Rectangle` borders/labels via `effectiveBezel/effectiveRadius`, as 0.1.3 does.
* **Do not** set `smooth:true` on `frame` or `contentSurface` — it forces linear sampling. `antialiasing:true` on shape borders is fine.

## 6. Color Distortion (0.1.4)

**What happened:** `src/main.cpp:22` injected `--force-dark-mode` + `--enable-features=WebUIDarkMode` into `QTWEBENGINE_CHROMIUM_FLAGS` for every start. Chromium then recolors every page (Bink’s “autodark”): light pages are inverted, *already-dark* pages (Sekiwa Cloud: `bg:#000`, lime `S` `#A3FF12` / `rgb(163,255,18)`) are desaturated to muted olive, contrast is crushed per profile. Compare Image 1 (bug: Sekiwa lime muted, blacks washed) vs Image 2 (expected: pure lime/black).

**Fix `0.1.4`:** `src/main.cpp:18-32` no longer injects `--force-dark-mode`. User-supplied `QTWEBENGINE_CHROMIUM_FLAGS` are preserved verbatim; DevTools dark appearance is still handled by `qml/components/DeviceFrame.qml:71` `applyDevToolsDarkTheme()` (`Common.settings uiTheme='dark'`). If you need WebUI dark chrome only, add `--enable-features=WebUIDarkMode` externally — do not use `--force-dark-mode` for content.

**Future rule:**
* **DO:** Let the page’s own `prefers-color-scheme` win. Set `WebEngineView.backgroundColor: "transparent"` or page `bg` if you need a placeholder.
* **DO NOT:** Add `--force-dark-mode`, `--enable-force-dark` or `blink-settings=forceDarkModeEnabled` unless you are writing an explicit “force dark” toggle — it globally recolors and breaks `color-scheme`, `lab()`/`oklch()` and image fidelity on every profile (`qml/theme/Theme.qml` is dark, but web content is not).
* **If you must darken:** Use `QWebEngineSettings::ForceDarkMode` per-profile or inject a page-level `filter: invert()` in a `WebEngineScript` with `injectionPoint: DocumentCreation` + `worldId: MainWorld`, not a process flag. That explicit toggle now exists as the per-device content theme (see [ARCHITECTURE.md](ARCHITECTURE.md#device-content-theme)): it sets the attribute on the device's own `WebEngineView` and still adds no process-wide flag, so the rest of this section keeps holding.

Check:
```bash
# should be empty / only user flags, not force-dark-mode
echo $QTWEBENGINE_CHROMIUM_FLAGS
QTWEBENGINE_CHROMIUM_FLAGS="" ./build/hesh  # lime S must be #A3FF12, not #8DBF3A
# verify in DevTools: getComputedStyle(document.querySelector('.logo')).backgroundColor
```

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Blurry at `1.5` scale but crisp at `1.0` | Missing `PassThrough` or Hyprland rounding | Ensure `src/main.cpp` policy before `QGuiApplication`; `hyprctl monitors` should show `scale:1.5` |
| Text crisp but images low-res on 3.0 profiles | `window.devicePixelRatio` still `1`/`1.5` | Check `syncDevicePixelRatio()` ran (load succeeded); console `window.devicePixelRatio` should be `3` |
| Lime/green desaturated, blacks washed (Sekiwa) | `--force-dark-mode` in `src/main.cpp` | Remove flag as in 0.1.4; verify `QTWEBENGINE_CHROMIUM_FLAGS` empty; reload `about:blank` then URL |
| `zoomFactor` warning `value 0.1 out of range` | `minimumPresentationScale` <0.25 | Bump to `0.25` as in `qml/components/DeviceFrame.qml:18` |
| Desktop profile (1440) looks tiny at 0.4 zoom | Expected: `visual = 1440*0.4 = 576` DIPs; increase `availableWidth` or `presentationPadding` | Adjust `qml/pages/DeviceWorkspace.qml:89` or run standalone window for full size |
| `httpUserAgent` not changing when switching device | `deviceProfile.instance().httpUserAgent` stale | `qml/components/DeviceFrame.qml:150` `onDeviceChanged` updates it |

## 8. References

* `qml/components/DeviceFrame.qml:18-485` — presentation scale, effective metrics, zoom logic, DPR sync
* `qml/components/StandaloneDeviceWindow.qml:20-31` — work-area initial scale (never upscale)
* `src/main.cpp:18-38` — HiDPI PassThrough + no force-dark-mode (0.1.4)
* `src/devices/DeviceProfile.hpp:21-27` + `src/devices/DeviceProfile.cpp:25-43` — profile catalog
* `docs/ARCHITECTURE.md:51-63` — logical viewport vs visual scale invariant

When in doubt, keep `visual / zoom == viewportWidth/Height` and never scale the `WebEngineView` ancestor; never force dark on the renderer.
