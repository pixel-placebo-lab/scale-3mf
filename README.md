# scale-3mf

> Scale 3MF files for metric→SAE fastener conversion

Two tools, one job:
- **Python CLI** (`scale_3mf.py`) — supports 5 fastener types, Z scaling, dry-run
- **Swift droplet app** (macOS) — drag & drop GUI, hex head focus, auto-builds on Mac Pro

## What It Does

Takes a metric 3MF model (e.g. M8 nut cap from MakerWorld Customizer) and scales the X/Y dimensions to match the closest SAE fastener size. Z is never scaled by default — the socket depth stays the same.

## Why

MakerWorld's parametric models (like the [Parametric Nut Caps & Knobs System](https://makerworld.com/en/models/2760568)) are metric-only. The Customizer doesn't expose the OpenSCAD source code, so you can't just type in SAE dimensions. This script lets you:

1. Download the closest metric size from the Customizer
2. Run the script to scale it to your SAE bolt size
3. Open the result in Bambu Studio and slice

## Usage

```bash
# Print the conversion table
python3 scale_3mf.py --table

# Scale for 5/16" SAE (auto-picks M8, scale=0.9769)
python3 scale_3mf.py model.3mf --sae 5/16

# Scale for 5/16" SAE with explicit metric source
python3 scale_3mf.py model.3mf --sae 5/16 --metric M8

# Manual scale factor
python3 scale_3mf.py model.3mf --factor 0.977

# Scale Z too (rarely needed)
python3 scale_3mf.py model.3mf --sae 5/16 --z 0.95

# Specify output path
python3 scale_3mf.py model.3mf --sae 5/16 -o my_t_handle.3mf

# Dry run (show what would be done)
python3 scale_3mf.py model.3mf --sae 5/16 --dry-run
```

## Conversion Table

```
SAE        SAE AF  Metric     Met AF     Scale        Δ
1/4        11.11mm  M6         10.00mm   1.1110  +11.10%
5/16       12.70mm  M8         13.00mm   0.9769   -2.31% ◀
3/8        14.29mm  M10        16.00mm   0.8931  -10.69%
7/16       15.88mm  M10        16.00mm   0.9925   -0.75% ◀
1/2        19.05mm  M12        18.00mm   1.0583   +5.83%
9/16       22.23mm  M14        21.00mm   1.0586   +5.86%
5/8        23.81mm  M16        24.00mm   0.9921   -0.79% ◀
3/4        28.58mm  M20        30.00mm   0.9527   -4.73%
7/8        34.93mm  M22        34.00mm   1.0274   +2.74% ◀
1          41.28mm  M24        36.00mm   1.1467  +14.67%
```

The `◀` marker indicates sizes with less than 3% difference — these are the best candidates for scaling (minimal distortion).

## How It Works

3MF files are ZIP archives containing XML (`3D/3dmodel.model`) with mesh data. The script:

1. **Unzips** the 3MF
2. **Checks for transform matrices** in `<item>` elements — if present, scales the X/Y components of the transform matrix
   - 3MF transform layout (row-major): `r00 r01 r02 r10 r11 r12 r20 r21 r22 tx ty tz`
   - Scales r00, r01, r10, r11 (rotation X/Y columns) and tx, ty (translation X/Y)
   - Leaves r02, r12, r20, r21, r22, tz untouched
3. **Falls back to vertex scaling** — if no transforms are found (common for MakerWorld Customizer exports), scales all `<vertex>` X/Y coordinates directly
4. **Re-zips** into a new 3MF, preserving all XML structure, namespaces, and metadata

### Why No Z Scaling?

Hex head bolt heights are roughly equivalent between SAE and metric. The socket depth just needs to be tall enough to cover the bolt head — shrinking Z would make it too shallow.

## Bambu Studio Compatibility

Tested with 3MF files exported by:
- MakerWorld Customizer (plain 3MF, vertex-based)
- Bambu Studio project exports (with BambuStudio XML namespaces)

The script preserves all XML namespaces, metadata, and file structure. Output 3MFs open correctly in Bambu Studio.

## Swift Droplet App (macOS)

A drag & drop GUI version is on Mac Pro at `~/Projects/scale-3mf/`. Build with `swift build`.

- Drag .3MF files onto the window
- Pick SAE size from the picker
- Output appears next to input with `_s{factor}` suffix
- Loads `fastener-dimensions.json` + `fastener-heights.json` for all 5 fastener types
- CLI mode also works: `.build/debug/Scale3MF --table` or `.build/debug/Scale3MF model.3mf --sae 5/16`

## Requirements

- Python CLI: Python 3.6+, no external dependencies
- Swift app: macOS 12+, Swift 5.7+, [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) package

## Known Limitations

- Swift app does not support Z scaling (Python CLI does via `--z`)
- Swift app XML parser converts self-closing tags (`<vertex .../>` → `<vertex ...></vertex>`) — output may be slightly larger
- Swift app uses `XMLParser` (event-based) which may not preserve XML comments or processing instructions

## License

MIT