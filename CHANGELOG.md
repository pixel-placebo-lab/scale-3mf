# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **AXorcist accessibility** — Added `accessibilityIdentifier`, `accessibilityLabel`, and `accessibilityValue` modifiers to scale controls, fastener type popup, mode selectors, action buttons, and file info. Enables remote UI reading via `axorc find --app Scale3MF --identifier <id>`.
### Added
- **ROADMAP.md** — Project roadmap with completed milestones (v1.0–v1.4), near-term goals (tests, CI, batch mode), and long-term experimental features.
- **Swift test target** — 41 unit tests covering ConversionTable (fallback data, scale factors, fastener types, metric/SAE dimension lookups, formatted tables, extrusion profiles) and Converter (transform scaling, vertex scaling, Z scaling, XML comment/self-closing tag preservation, error handling, result metadata, plus Sep 2026 review-fix regressions: world-space S·M matrix scaling for rotated transforms, full Z-column scaling, mixed transform/vertex files, reordered vertex attributes, scientific notation).

### Changed
- **Package.swift** — Added `Scale3MFTests` test target with JSON resource copies.
- **scale_3mf.py extract/repackage routed through the shared 3mf-tooling library** (card ff043e2c) — `extract_3mf`/`repackage_3mf` now come from `~/Projects/3mf-tooling/3mf_lib.py` (gateway-absolute path), replacing the local zipfile blocks.
- **Python regression tests** — new `test_scale_3mf.py` (7 unittest cases, also pytest-compatible) covering the same matrix/parity regressions as the Swift suite.

### Fixed
- **X/Y and Z scaling of rotated transforms sheared tilted objects** (Swift + Python) — scaling now applies a proper world-space scale to the whole transform matrix instead of patching individual elements. Per the 3MF core spec (§3.3), the transform is a row-major 4×3 matrix (`m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32`; rows are basis-vector images, the last row is the translation, points are row-vectors), so world-space scaling scales each **column** by its axis factor (positions j, j+3, j+6, j+9). Previously the X/Y pass left m20/m21 unscaled and the Z pass left m02/m12 unscaled — any object rotated about a horizontal axis sheared/distorted (Sep 7 review findings 1–2; layout verified against the spec and real Bambu Studio exports).
- **Mixed transform/vertex files silently scaled only part** (Sep 7 review finding 3) — vertex scaling is now decided per object: objects whose `<item>`/`<component>` reference carries a transform scale through the matrix (vertices protected from double-scaling); every other object scales via its vertices directly. Previously ANY transform in a file suppressed vertex scaling file-wide, so a second object placed without a transform stayed at its original size.
- **Vertex attributes now parsed by name, not position** (Sep 7 review finding 4) — `<vertex>` x/y/z scale regardless of attribute order, extra attributes (e.g. `p1`) are preserved, and non-numeric values are left untouched (Swift + Python).
- **Scientific notation parity** (Sep 7 review finding 5) — transform and vertex values like `1e0`/`2.5E-3` now scale in both CLIs. Python previously rejected scientific notation in transforms (silent no-op); Swift previously rejected it in vertices (a gap beyond the original finding — Swift transforms already accepted it).

## [1.4.0] - 2026-07-28

### Added
- **Externalized 8020 extrusion profile config** — `extrusionProfiles` moved from hardcoded Swift arrays to `extrusion-profiles.json`. Add or edit profile presets without recompiling.
- **App icon** — `app_icon.icns` embedded in the `.app` bundle and referenced in `Info.plist` (`CFBundleIconFile`).
- **Ad-hoc signed `.app` bundle** — Release `.app` is now built, deep-signed with `codesign --force --deep --sign -`, and attached to GitHub Releases.
- **GitHub Release workflow** — Tagged release `v1.4.0` with `Scale3MF.app.zip` asset and signed `.app` bundle.

### Changed
- **README** — Added pre-built download instructions, Gatekeeper note, ad-hoc signing caveat, config-file note, and updated build-from-source steps.
- **Package.swift** — Added `extrusion-profiles.json` as a copied resource for the Swift executable target.

## [1.3.0] - 2026-07-11

### Added
- **CLI: Full feature parity with Python CLI** — `--version`, `--help`, `--table` (with `--fastener-type`), `--list-metrics`, `--dry-run`, `--profile-table`, `--profile-scale` flags
- **CLI: All 4 conversion directions** — Metric→SAE (`--sae`), Metric→Metric (`--metric` + `--target-metric`), SAE→Metric (`--sae` + `--target-metric`), SAE→SAE (`--sae` + `--target-sae`)
- **CLI: 8020 extrusion profile scaling** — `--profile-scale` with 8 presets (metric→imperial and imperial→metric)
- **App: FastenerType enum** — 5 fastener types: hex_head, hex_nut, nylock_nut, socket_head_cap, button_head_cap
- **App: JSON-based dimension loading** — Loads `fastener-dimensions.json` and `fastener-heights.json` from bundle/CWD with hardcoded fallback
- **App: Advanced mode GUI** — 3 modes (Simple, Advanced, 8020 Profile) with source/target type selection
- **App: 8020 extrusion profile presets** — 8 presets with T-slot mismatch analysis
- **App: Metric dimension lookups** — `metricDimension()` and `saeDimension()` with fallbacks for all fastener types
- **App: Z-scale toggle + slider in GUI** — Optional Z axis scaling with visual feedback

### Fixed
- **Regex: Vertex pattern crash** — Fixed invalid character class `[ -\d.]+` (space-dash interpreted as range) → `[-\d. ]+` (dash first)
- **ConversionTable: Lazy JSON loading** — `saeDimension()` and `metricDimension()` now ensure JSON is loaded before lookup
- **ConversionTable: SAE dimension fallback** — Added hardcoded fallback for hex_head/hex_nut SAE dimensions when JSON unavailable

## [1.1.0] - 2026-07-06

### Added
- **Swift app: Z scaling support** — `zFactor` parameter through Converter → ModelXMLScaler pipeline, `--z` CLI flag, and toggle + slider in the GUI. Scales r22 and tz in transform matrices, and vertex Z coordinates when zFactor ≠ 1.0.

### Fixed
- **Swift app: Self-closing tag preservation** — `<vertex .../>` no longer expands to `<vertex ...></vertex>`. XML emission uses a pending-tag pattern: if no character content is found between start and end, the element is emitted as self-closing.
- **Swift app: XML comment preservation** — Added `parser(_:foundComment:)` delegate method. `<!-- -->` comments survive the round-trip.

## [1.0.1] - 2026-07-06

### Fixed
- **Swift app: X/Y transform scaling bug** — `scaleTransform` used wrong matrix indices `[0,1,4,5,8,9]` (scaled r00,r01,r11,r12,r20,r21) instead of correct `[0,1,3,4,9,10]` (r00,r01,r10,r11,tx,ty). This left X at 100% while Y and Z were incorrectly adjusted. Python CLI was correct all along.
- **JSON data: 3/8" mapped to M8** — Should be M10 in `hex_head` and `nylock_nut` (both had `closest_metric: M8`). Now correctly maps to M10, matching the hardcoded fallback and `fastener-heights.json`.
- **JSON data: Missing 7/8" and 1" entries** — Added SAE + metric entries for 7/8" (→M22) and 1" (→M24) in `hex_head` and `nylock_nut`.
- **SAE filter excluded 1"** — Both Python and Swift filtered SAE sizes by checking for `/` in the thread string, which excluded `"1"` (1 inch). Now includes it.
- **Swift: `formattedTable` format specifiers** — Used `%@` (object specifier) which doesn't pad strings. Replaced with manual padding helper.
- **Swift: Table entries unsorted** — JSON dictionary iteration is unordered. Now sorts by SAE size (1/4, 5/16, 3/8, ... 1).
- **Python: Table entries sorted alphabetically** — Was `sorted(cat.keys())` (alphabetical: 1, 1/2, 1/4...). Now sorts by proper SAE fractional order.

## [1.0.0] - 2026-07-05

### Added
- Initial release
- SAE→Metric conversion table for hex head bolts (1/4" through 1")
- Automatic scale factor calculation from SAE size (auto-picks closest metric)
- Manual scale factor option (`--factor`)
- Z scaling option (`--z`, defaults to 1.0)
- Dry run mode (`--dry-run`)
- Conversion table display (`--table`)
- Custom output path (`-o`/`--output`)

### How It Works
- **Transform-based 3MF**: Modifies the 4×3 transform matrix on `<item>` elements (scales r00, r01, r10, r11 for X/Y; r22 for Z if requested)
- **Vertex-based 3MF**: Scales vertex X/Y coordinates directly (fallback when no transforms are present — common for MakerWorld Customizer exports)
- Preserves all XML namespaces, metadata, and file structure
- Tested with Bambu Studio-compatible 3MF files

### SAE→Metric Mappings
| SAE | Metric | Scale | Δ |
|-----|--------|-------|---|
| 1/4 | M6 | 1.1110 | +11.10% |
| 5/16 | M8 | 0.9769 | -2.31% |
| 3/8 | M10 | 0.8931 | -10.69% |
| 7/16 | M10 | 0.9925 | -0.75% |
| 1/2 | M12 | 1.0583 | +5.83% |
| 9/16 | M14 | 1.0586 | +5.86% |
| 5/8 | M16 | 0.9921 | -0.79% |
| 3/4 | M20 | 0.9527 | -4.73% |
| 7/8 | M22 | 1.0274 | +2.74% |
| 1 | M24 | 1.1467 | +14.67% |