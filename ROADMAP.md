# Roadmap

## Project Status

**Current version:** 1.4.0 (2026-07-28)
**Stability:** Production — Python CLI and macOS app both feature-complete for core use cases.

## Completed

- [x] **v1.0.0** — Python CLI: SAE→Metric hex head conversion, transform + vertex scaling
- [x] **v1.1.0** — Swift app: Z scaling, self-closing tag preservation, XML comment round-trip
- [x] **v1.3.0** — Swift CLI parity with Python: all 4 conversion directions, 5 fastener types, 8020 profiles, JSON config
- [x] **v1.4.0** — Externalized extrusion profiles to JSON, app icon, ad-hoc signed .app bundle, GitHub Release workflow

## Near Term

- [ ] **Test coverage** — Swift unit tests for ConversionTable lookups, Converter scaling, XML round-trip integrity
- [ ] **Python test coverage** — pytest suite for scale_3mf.py (conversion table, CLI args, 3MF round-trip)
- [ ] **CI** — GitHub Actions: build Swift package, run tests on macOS 14 runner
- [ ] **Batch mode** — Process a directory of .3mf files with a single scale factor or fastener size
- [ ] **Inverse scale** — SAE→Metric direction in the GUI (currently CLI-only for advanced directions)

## Medium Term

- [ ] **Preview** — Quick 3D preview of scaled model in the macOS app before saving
- [ ] **Multi-object 3MF** — Per-object scale factors for 3MF files with mixed fastener sizes
- [ ] **Thread profile scaling** — Scale internal/external thread profiles (not just head AF)
- [ ] **Bambu Studio plate integration** — Write scale metadata into Bambu Studio project 3MF extensions
- [ ] **Localization** — GUI strings in metric-first locales (EN-EU, DE, JA)

## Long Term / Experimental

- [ ] **Cloud API** — Headless scaling endpoint for integration with maker pipelines
- [ ] **Plugin SDK** — Custom scaling presets as user-authored Swift/Python modules
- [ ] **Direct OpenSCAD integration** — Re-parametrize OpenSCAD source when available instead of scaling mesh
- [ ] **Filament volume recalculation** — Adjust Bambu Studio filament estimates after scaling