# scale-3mf

> Scale 3MF files for metric→SAE fastener conversion

Two tools, one job:
- **Python CLI** (`scale_3mf.py`) — 5 fastener types, Z scaling, dry-run, conversion tables
- **Swift droplet app** (macOS) — drag & drop GUI, all 5 fastener types, Z scale slider, CLI mode

## What It Does

Takes a metric 3MF model (e.g. M8 nut cap from MakerWorld Customizer) and scales the X/Y dimensions to match the closest SAE fastener size. Z is never scaled by default (scale factor 1.0) — the socket depth stays the same. Z scaling is available when needed via `--z` (CLI) or the Z scale slider (GUI).

## Why

MakerWorld's parametric models (like the [Parametric Nut Caps & Knobs System](https://makerworld.com/en/models/2760568)) are metric-only. The Customizer doesn't expose the OpenSCAD source code, so you can't just type in SAE dimensions. This tool lets you:

1. Download the closest metric size from the Customizer
2. Scale it to your SAE fastener size
3. Open the result in Bambu Studio and slice

## Supported Fastener Types

| Type | Dimension Used | Key |
|------|---------------|-----|
| Hex Head Bolt | Across Flats (AF) | `hex_head` |
| Hex Nut | Across Flats (AF) | `hex_nut` |
| Nylock Nut | Across Flats (AF) | `nylock_nut` |
| Socket Head Cap Screw | Head Diameter | `socket_head_cap` |
| Button Head Cap Screw | Head Diameter | `button_head_cap` |

Dimensions are loaded from `fastener-dimensions.json` (compiled from ASME B18.2.1, B18.2.2, B18.3, B18.16.6, ISO 4014, ISO 4762, ISO 7380, DIN 931/934/985/982). Falls back to hardcoded hex head table if JSON is missing.

## Usage — Python CLI

```bash
# Print the conversion table (hex head by default)
python3 scale_3mf.py --table

# Print table for nylock nuts
python3 scale_3mf.py --table --fastener-type nylock_nut

# Scale for 5/16" SAE (auto-picks M8, scale=0.9769)
python3 scale_3mf.py model.3mf --sae 5/16

# Scale for 5/16" SAE with explicit metric source
python3 scale_3mf.py model.3mf --sae 5/16 --metric M8

# Scale for nylock nut
python3 scale_3mf.py model.3mf --sae 5/16 --fastener-type nylock_nut

# Manual scale factor
python3 scale_3mf.py model.3mf --factor 0.977

# Scale Z too (rarely needed)
python3 scale_3mf.py model.3mf --sae 5/16 --z 0.95

# Specify output path
python3 scale_3mf.py model.3mf --sae 5/16 -o my_t_handle.3mf

# Dry run (show what would be done)
python3 scale_3mf.py model.3mf --sae 5/16 --dry-run
```

## Usage — Swift Droplet App

**Location:** Mac Pro at `~/Projects/scale-3mf/`

### GUI Mode

Drag .3MF files onto the window. Pick SAE size from the picker. Toggle Z scale and adjust the slider if needed. Output appears next to input with `_s{factor}` suffix (and `_z{factor}` if Z-scaled).

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

## Conversion Table (Hex Head)

```
SAE      SAE(mm)    Metric   Metric(mm)   Scale
1/4           11.11  M6              10.00      1.1110
5/16          12.70  M8              13.00      0.9769
3/8           14.29  M10             16.00      0.8931
7/16          15.88  M10             16.00      0.9925
1/2           19.05  M12             18.00      1.0583
9/16          22.23  M14             21.00      1.0586
5/8           23.81  M16             24.00      0.9921
3/4           28.58  M20             30.00      0.9527
7/8           34.93  M22             34.00      1.0274
1             41.28  M24             36.00      1.1467
```

The `◀` marker (in CLI output) indicates sizes with less than 3% difference — best candidates for scaling.

## How It Works

3MF files are ZIP archives containing XML (`3D/3dmodel.model`) with mesh data. The tool:

1. **Unzips** the 3MF
2. **Checks for transform matrices** in `<item>` elements — if present, scales the X/Y (and optionally Z) components
   - 3MF transform layout (row-major): `r00 r01 r02 r10 r11 r12 r20 r21 r22 tx ty tz`
   - X/Y scale: r00, r01, r10, r11 (rotation columns 0-1) + tx, ty (translation X/Y)
   - Z scale (optional): r22 (rotation Z) + tz (translation Z)
   - Untouched: r02, r12, r20, r21 (and r22, tz when Z scale = 1.0)
3. **Falls back to vertex scaling** — if no transforms are found (common for MakerWorld Customizer exports), scales all `<vertex>` X/Y (and optionally Z) coordinates directly
4. **Re-zips** into a new 3MF, preserving all XML structure, namespaces, comments, and metadata

**Self-closing tags** are preserved (`<vertex .../>` stays as-is, not expanded to `<vertex ...></vertex>`).

**XML comments** are preserved through the round-trip.

## Bambu Studio Compatibility

Tested with 3MF files exported by:
- MakerWorld Customizer (plain 3MF, vertex-based)
- Bambu Studio project exports (with BambuStudio XML namespaces)

Output 3MFs open correctly in Bambu Studio.

## Requirements

- **Python CLI:** Python 3.6+, no external dependencies (stdlib only)
- **Swift app:** macOS 12+, Swift 5.7+, [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) package

## License

MIT