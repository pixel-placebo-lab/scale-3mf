# Scale3MF

> Metric → SAE 3MF scaling droplet

Scale3MF is a tiny macOS app (and command-line tool) that takes a metric 3MF model and scales its X/Y dimensions to the closest matching SAE fastener size. Z is never scaled by default, so socket depths and standoff heights stay correct.

## Why

MakerWorld's parametric models (like the [Parametric Nut Caps & Knobs System](https://makerworld.com/en/models/2760568)) are usually metric-only. The Customizer doesn't expose the OpenSCAD source, so you can't type in SAE dimensions directly. Scale3MF lets you:

1. Download the closest metric size from the Customizer
2. Drop the 3MF onto Scale3MF (or run the CLI)
3. Open the scaled result in Bambu Studio and slice

## Supported Fastener Types

- **Hex Head Bolt** (`hex_head`)
- **Hex Nut** (`hex_nut`)
- **Nylock Nut** (`nylock_nut`)
- **Socket Head Cap Screw** (`socket_head_cap`)
- **Button Head Cap Screw** (`button_head_cap`)

The CLI defaults to `hex_head`; the GUI defaults to Hex Head but lets you pick any type.

## GUI Usage

Drag a `.3mf` file onto the Scale3MF window, choose the SAE size and fastener type, and click **Scale**. The output is saved next to the original with a `_scaled.3mf` suffix.

## CLI Usage

```bash
# Print the conversion table
./Scale3MF --table

# Table for a specific fastener type
./Scale3MF --table --fastener-type socket_head_cap

# Scale for 5/16" SAE hex head (auto-picks metric source)
./Scale3MF model.3mf --sae 5/16

# Scale for 5/16" SAE nylock nut
./Scale3MF model.3mf --sae 5/16 --fastener-type nylock_nut

# Manual scale factor
./Scale3MF model.3mf --factor 0.977

# Specify output path
./Scale3MF model.3mf --sae 5/16 -o my_t_handle.3mf
```

## Version

**1.0.0**

## Requirements

- macOS 12 Monterey or later
- Swift 5.7+

## License

MIT
