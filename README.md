# Scale3MF

> Scale metric 3MF models to SAE fastener sizes — with both a Python CLI and a native macOS droplet app.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Python 3.6+](https://img.shields.io/badge/python-3.6+-blue.svg)](https://www.python.org/downloads/)
[![macOS 14+](https://img.shields.io/badge/macOS-14+-black?logo=apple)](https://developer.apple.com/macos/)

MakerWorld’s parametric models (like the [Parametric Nut Caps & Knobs System](https://makerworld.com/en/models/2760568)) are metric-only, and the Customizer does not expose the OpenSCAD source. **Scale3MF** lets you download the closest metric size, scale the X/Y dimensions to the SAE fastener you actually have, and open the result in Bambu Studio.

Z is left untouched by default so socket depths stay correct; optional Z scaling is available for special cases.

## Features

- **Python CLI** — cross-platform, stdlib-only, scriptable.
- **Native macOS app** — drag & drop droplet GUI plus full CLI mode.
- **Five fastener types** — hex head bolts, hex nuts, nylock nuts, socket head cap screws, button head cap screws.
- **Four conversion directions** — Metric→SAE, Metric→Metric, SAE→Metric, SAE→SAE.
- **8020 extrusion profile scaling** — metric↔imperial T-slot presets.
- **Transform-aware** — scales existing 3MF `<item>` matrices when present.
- **Vertex fallback** — scales raw `<vertex>` coordinates for plain MakerWorld exports.
- **Round-trip safe** — preserves namespaces, comments, metadata, and self-closing tags.

## Supported Fastener Types

| Type | Dimension Used | Key |
|------|---------------|-----|
| Hex Head Bolt | Across Flats (AF) | `hex_head` |
| Hex Nut | Across Flats (AF) | `hex_nut` |
| Nylock Nut | Across Flats (AF) | `nylock_nut` |
| Socket Head Cap Screw | Head Diameter | `socket_head_cap` |
| Button Head Cap Screw | Head Diameter | `button_head_cap` |

Dimensions are loaded from `fastener-dimensions.json` (compiled from ASME B18.2.1, B18.2.2, B18.3, B18.16.6, ISO 4014, ISO 4762, ISO 7380, DIN 931/934/985/982). A hardcoded fallback covers the core hex head table if the JSON is missing.

8020 extrusion profile presets are loaded from `extrusion-profiles.json`. Edit that file or supply your own to add custom profile mappings without recompiling the app.

## Installation

### Python CLI

No install step is required. Just clone the repo and run `scale_3mf.py`.

```bash
git clone https://github.com/pixel-placebo-lab/scale-3mf.git
cd scale-3mf
python3 scale_3mf.py --help
```

Requires Python 3.6 or later. No third-party packages are used.

### macOS App

A pre-built, ad-hoc signed `.app` bundle is attached to each [GitHub Release](https://github.com/pixel-placebo-lab/scale-3mf/releases). Download `Scale3MF.app.zip`, unzip it, and drag `Scale3MF.app` to `/Applications`.

> **macOS Gatekeeper:** Because the app is ad-hoc signed (no Apple Developer ID), opening it the first time may show “Apple could not verify...”. Right-click the app and choose **Open**, then click **Open** in the dialog. After that, double-clicking works normally.

Build from source with Swift Package Manager:

```bash
git clone https://github.com/pixel-placebo-lab/scale-3mf.git
cd scale-3mf
swift build
```

The executable is produced at `.build/debug/Scale3MF`.

To produce the `.app` bundle and ad-hoc sign it:

```bash
swift build
rm -rf Scale3MF.app/Contents/MacOS/Scale3MF
cp .build/debug/Scale3MF Scale3MF.app/Contents/MacOS/Scale3MF
codesign --force --deep --sign - Scale3MF.app
```

Requires macOS 14 (Sonoma) or later and Swift 5.10 or later.

## Usage — Python CLI

```bash
# Print the conversion table (hex head by default)
python3 scale_3mf.py --table

# Print table for nylock nuts
python3 scale_3mf.py --table --fastener-type nylock_nut

# Scale a metric M8 model to the closest SAE 5/16"
python3 scale_3mf.py model.3mf --sae 5/16

# Explicitly choose the metric source size
python3 scale_3mf.py model.3mf --sae 5/16 --metric M8

# Scale a nylock nut model
python3 scale_3mf.py model.3mf --sae 5/16 --fastener-type nylock_nut

# Manual scale factor
python3 scale_3mf.py model.3mf --factor 0.977

# Scale Z too (rarely needed)
python3 scale_3mf.py model.3mf --sae 5/16 --z 0.95

# Specify output path
python3 scale_3mf.py model.3mf --sae 5/16 -o my_t_handle.3mf

# Dry run
python3 scale_3mf.py model.3mf --sae 5/16 --dry-run

# Metric-to-metric resize
python3 scale_3mf.py model.3mf --metric M8 --target-metric M10

# 8020 profile scaling
python3 scale_3mf.py model.3mf --profile-scale 2020_to_1515
```

## Usage — macOS App

### GUI Mode

Drag one or more `.3mf` files onto the app window. Choose the source and target fastener sizes, enable Z scaling if needed, and click **Scale**. Output files are written next to the inputs with a `_s{factor}` suffix (and `_z{factor}` when Z scaling is used).

### CLI Mode

```bash
# Print conversion table
.build/debug/Scale3MF --table

# Scale a file
.build/debug/Scale3MF model.3mf --sae 5/16

# Scale with Z
.build/debug/Scale3MF model.3mf --sae 5/16 --z 0.95

# Manual factor
.build/debug/Scale3MF model.3mf --factor 0.977 -o output.3mf
```

## How It Works

3MF files are ZIP archives containing XML (`3D/3dmodel.model`) with mesh data. Scale3MF:

1. **Unzips** the 3MF.
2. **Looks for transform matrices** in `<item>` elements and scales the X/Y (and optionally Z) components.
   - 3MF transform layout (row-major): `r00 r01 r02 r10 r11 r12 r20 r21 r22 tx ty tz`
   - X/Y scale: `r00`, `r01`, `r10`, `r11` + `tx`, `ty`
   - Z scale (optional): `r22` + `tz`
   - Untouched: `r02`, `r12`, `r20`, `r21` (and `r22`, `tz` when Z scale = 1.0)
3. **Falls back to vertex scaling** when no transforms are present — common for MakerWorld Customizer exports.
4. **Re-zips** into a new 3MF, preserving XML structure, namespaces, comments, and self-closing tags.

## Bambu Studio Compatibility

Tested with 3MF files exported by:

- MakerWorld Customizer (plain 3MF, vertex-based)
- Bambu Studio project exports (with BambuStudio XML namespaces)

Output 3MFs open correctly in Bambu Studio.

## Requirements

- **Python CLI:** Python 3.6+, no external dependencies (stdlib only)
- **macOS app:** macOS 14+, Swift 5.10+, [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) package
- **Config files:** `fastener-dimensions.json`, `fastener-heights.json`, and `extrusion-profiles.json` must be present in the app bundle (or the working directory for CLI use).

## Contributing

Issues and pull requests are welcome. If you find a model that does not round-trip cleanly, please attach the smallest 3MF that reproduces the issue.

## License

[MIT](./LICENSE) © Pixel Placebo Lab
