# FastScreenerMac

A lightweight macOS screen capture and annotation tool — a native Mac port of [FastScreener2](https://github.com/Ivanou-Dzmitry/FastScreener2) (Windows). Define a capture area, annotate it with arrows, frames, and numbers, then save and/or copy it to the clipboard, all without leaving your workflow.

**Built with:** Swift 6 · AppKit · ScreenCaptureKit · macOS 14+

---

## Features

### Capture
- Borderless, always-on-top capture-frame window whose interior *is* the exact area that gets captured
- Global hotkey **F4** captures and copies to clipboard (and saves to file, if enabled) from anywhere, without needing to focus the app
- **4 preset capture sizes** (`⌥1`–`⌥4`), a resolution-cycle toolbar button, **Fullscreen** (`⌥5`), and **Max Size** toggle (`⌃⇧M`)
- The capture window snaps to screen edges — the actual capture area's edges snap flush, not just the window's outer chrome
- Captures via **ScreenCaptureKit**, Apple's native capture API, with correct handling of Retina/mixed-DPI multi-monitor setups

### Annotation Tools
All tools are placed with the **Middle Mouse Button (MMB)**; pick the active tool from the left toolbar, the hamburger menu, or keys `1`/`2`/`3`/`0`.

| Tool | Description |
|------|-------------|
| **Arrow** | Click to anchor the arrowhead, drag to set direction — snaps to the 4 diagonals. |
| **Frame** | Click for a fixed-size box (from Settings); drag past a threshold for a free-size box. |
| **Number** | Places sequential numbers with a drop shadow. Counter decrements correctly on Undo. |
| Text, Watermark | Present in the menu/Settings for parity with the Windows app, not yet implemented. |

- **Undo** last annotation with `⌘Z`, **Clear all** with `⌘⇧Z`
- **Bars**: a dual-thumb vertical slider on the right-side panel masks off the top and/or bottom of the capture area with a solid color — drag either thumb to resize a mask, double-click the slider to reset both to 0. The mask is baked into the saved/copied image, unlike Guides.

### Guide Lines
Non-destructive dashed overlay lines to help with composition — never included in the saved screenshot.
- **Thirds** / **Quarters** — grid overlays
- **Custom Margins** — independent pixel offsets from each edge

### Settings & Profiles
All visual parameters (colors, sizes, arrow style, font, bar color, etc.) live in the **Settings** window, organized into the same categories as the Windows app: Appearance, Arrow, Bar, File, Frame, Guides, Numbers, Sizes, Watermark.

**Profiles** save and load named setting presets — useful when different projects need different annotation styles.
- Stored as JSON snapshots in macOS's standard app preferences (`UserDefaults`), not as separate files
- The Settings window remembers which profile you last saved or loaded and reselects it the next time it opens

### File Output
- **Format:** PNG or JPG
- **PNG Depth:** 32bpp (with alpha, default) / 24bpp (no alpha) / 8bpp — macOS has no simple indexed-palette PNG encoder, so 8bpp falls back to plain 24bpp RGB rather than a true 256-color palette
- **JPEG Compression:** quality 1–100 (default 75)
- **Save Folder:** configurable in Settings; defaults to `~/Desktop/FastScreener Screens`
- **File naming:** an optional fixed name, or an auto-generated timestamped name

### DPI Scale
When on (default), the saved/copied image's pixel dimensions always exactly match the capture size shown — the app downsamples native Retina pixels so a 650×366 capture is always a 650×366px file, regardless of the display's scale factor. When off, it keeps the display's native pixel density.

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode with Swift 6 toolchain, to build from source
- **Screen Recording** permission (macOS will prompt on first capture; required by ScreenCaptureKit)

---

## Getting Started

```bash
swift run FastScreenerMac
```

1. Position and size the capture window over the area you want to capture (presets, drag, or edge-snap)
2. Use MMB to add annotations with the currently selected tool
3. Press `F4`, or click the capture button, to save/copy the screenshot

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `F4` | Capture (global, works even when unfocused) |
| `1` / `2` / `3` / `0` | Select Arrow / Frame / Number / no tool |
| `⌘Z` | Undo last annotation |
| `⌘⇧Z` | Clear all annotations |
| `⌥1`–`⌥4` | Apply capture size preset 1–4 |
| `⌥5` | Fullscreen capture size |
| `⌃⇧M` | Toggle Max Size |
| `⌃→` | Cycle to the next preset size |

---

## Author

Dzmitry Ivanou · [id.cgtalk@gmail.com](mailto:id.cgtalk@gmail.com)
