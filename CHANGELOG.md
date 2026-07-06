# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-06

### Added
- SwiftUI drag-and-drop macOS app (macOS 12 Monterey compatible)
- CLI mode with `--table`, `--version`, `--sae`, `--factor`, and `--fastener-type` flags
- Five fastener types supported:
  - Hex Head Bolt (`hex_head`)
  - Hex Nut (`hex_nut`)
  - Nylock Nut (`nylock_nut`)
  - Socket Head Cap Screw (`socket_head_cap`)
  - Button Head Cap Screw (`button_head_cap`)
- Metric → SAE scaling of 3MF vertex X/Y coordinates; Z never scaled by default
- Fastener dimension and height JSONs bundled as app resources
- Automatic closest-metric lookup per fastener type and SAE size
- Conversion table printer for every supported fastener type
- Placeholder app icon (Lumo icon TODO)
