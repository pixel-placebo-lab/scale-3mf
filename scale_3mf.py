#!/usr/bin/env python3
"""
scale_3mf.py — Scale X/Y of a 3MF file for metric→SAE hex head conversion

Supports: hex_head, hex_nut, nylock_nut, socket_head_cap, button_head_cap
Handles both transform-based and vertex-based 3MF files.
Preserves all XML namespaces, metadata, and Bambu Studio extensions.
"""

import argparse
import json
import os
import re
import sys
import tempfile
import zipfile

# ─── Data ─────────────────────────────────────────────────────────────
# Loaded from fastener-dimensions.json if available, falls back to hardcoded

SAE_AF = {
    "1/4":  11.11, "5/16": 12.70, "3/8":  14.29, "7/16": 15.88,
    "1/2":  19.05, "9/16": 22.23, "5/8":  23.81, "3/4":  28.58,
    "7/8":  34.93, "1":    41.28,
}

METRIC_AF = {
    "M4": 7.0, "M5": 8.0, "M6": 10.0, "M8": 13.0, "M10": 16.0,
    "M12": 18.0, "M14": 21.0, "M16": 24.0, "M18": 27.0, "M20": 30.0,
    "M22": 34.0, "M24": 36.0,
}

SAE_TO_METRIC = {
    "1/4": "M6", "5/16": "M8", "3/8": "M10", "7/16": "M10",
    "1/2": "M12", "9/16": "M14", "5/8": "M16", "3/4": "M20",
    "7/8": "M22", "1": "M24",
}

FASTENER_TYPES = ["hex_head", "hex_nut", "nylock_nut", "socket_head_cap", "button_head_cap"]


def load_dimensions():
    """Load fastener dimensions from JSON file."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    json_path = os.path.join(script_dir, "fastener-dimensions.json")
    if os.path.exists(json_path):
        with open(json_path) as f:
            return json.load(f)
    return None


def compute_scale(sae_size, metric_size=None, fastener_type="hex_head", dim_data=None):
    """Compute X/Y scale factor from SAE and metric sizes."""
    if dim_data and fastener_type in dim_data:
        cat = dim_data[fastener_type]
        # Find the SAE entry (keys prefixed with 'sa')
        key = f"sa{sae_size.replace('/', '')}"
        # Try different key formats
        for k in cat:
            entry = cat[k]
            if entry.get("thread") == sae_size:
                if metric_size is None:
                    metric_size = entry.get("closest_metric", "")
                # Find the metric entry
                metric_key = f"m{metric_size.lower()}"
                metric_entry = cat.get(metric_key, {})
                
                if fastener_type in ("hex_head", "hex_nut", "nylock_nut"):
                    sae_dim = entry.get("across_flats_mm", 0)
                    metric_dim = metric_entry.get("across_flats_mm", entry.get("metric_af_mm", 0))
                else:
                    sae_dim = entry.get("head_dia_mm", 0)
                    metric_dim = metric_entry.get("head_dia_mm", entry.get("metric_head_dia_mm", 0))
                
                if metric_dim == 0:
                    metric_dim = entry.get("metric_af_mm", entry.get("metric_head_dia_mm", 0))
                
                if sae_dim and metric_dim:
                    print(f"  {fastener_type}: {sae_size} ({sae_dim:.2f}mm) → {metric_size} ({metric_dim:.2f}mm)")
                    return sae_dim / metric_dim
    
    # Fallback to hardcoded hex_head table
    if fastener_type in ("hex_head", "hex_nut"):
        sae_af = SAE_AF.get(sae_size)
        if metric_size is None:
            metric_size = SAE_TO_METRIC.get(sae_size)
        metric_af = METRIC_AF.get(metric_size, 0) if metric_size else 0
        if sae_af and metric_af:
            print(f"  {fastener_type}: {sae_size} ({sae_af:.2f}mm) → {metric_size} ({metric_af:.2f}mm) [fallback]")
            return sae_af / metric_af
    
    print(f"  ⚠️  Could not find dimensions for {sae_size} in {fastener_type}")
    return None


def scale_3mf(input_path, scale_xy=1.0, scale_z=1.0, output_path=None):
    """Scale X/Y (and optionally Z) of a 3MF file."""
    if output_path is None:
        base, ext = os.path.splitext(input_path)
        suffix = f"_s{scale_xy:.3f}"
        if scale_z != 1.0:
            suffix += f"_z{scale_z:.3f}"
        output_path = f"{base}{suffix}{ext}"

    with tempfile.TemporaryDirectory() as tmpdir:
        with zipfile.ZipFile(input_path, 'r') as zin:
            zin.extractall(tmpdir)

        model_dir = os.path.join(tmpdir, '3D')
        if not os.path.isdir(model_dir):
            sys.exit(f"Error: No 3D/ directory found in {input_path}")

        # Find ALL .model files recursively (3D/3dmodel.xml + 3D/Objects/*.model)
        model_files = []
        for root, dirs, files in os.walk(model_dir):
            for f in files:
                if f.endswith('.model'):
                    model_files.append(os.path.join(root, f))
        if not model_files:
            sys.exit(f"Error: No .model file found in 3D/ directory")

        total_transforms = 0
        total_vertices = 0

        for model_path in model_files:
            with open(model_path, 'r', encoding='utf-8') as f:
                xml_content = f.read()

            transform_pattern = re.compile(
                r'(transform=")([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+'
                r'([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+'
                r'([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+'
                r'([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)(")'
            )

            file_transforms = 0

            def replace_transform(m):
                nonlocal total_transforms, file_transforms
                total_transforms += 1
                file_transforms += 1
                r00 = float(m.group(2)) * scale_xy
                r01 = float(m.group(3)) * scale_xy
                r02 = float(m.group(4))
                r10 = float(m.group(5)) * scale_xy
                r11 = float(m.group(6)) * scale_xy
                r12 = float(m.group(7))
                r20 = float(m.group(8))
                r21 = float(m.group(9))
                r22 = float(m.group(10))
                if scale_z != 1.0:
                    r22 *= scale_z
                tx = float(m.group(11)) * scale_xy
                ty = float(m.group(12)) * scale_xy
                tz = float(m.group(13))
                if scale_z != 1.0:
                    tz *= scale_z
                return (
                    f'{m.group(1)}'
                    f'{r00:.6f} {r01:.6f} {r02:.6f} '
                    f'{r10:.6f} {r11:.6f} {r12:.6f} '
                    f'{r20:.6f} {r21:.6f} {r22:.6f} '
                    f'{tx:.6f} {ty:.6f} {tz:.6f}'
                    f'{m.group(14)}'
                )

            new_xml = transform_pattern.sub(replace_transform, xml_content)

            if file_transforms == 0:
                vertex_pattern = re.compile(
                    r'(<vertex\s+x=")([-\d.]+)("\s+y=")([-\d.]+)("\s+z=")([-\d.]+)("\s*/>)'
                )
                def replace_vertex(m):
                    nonlocal total_vertices
                    total_vertices += 1
                    x = float(m.group(2)) * scale_xy
                    y = float(m.group(4)) * scale_xy
                    z = float(m.group(6))
                    if scale_z != 1.0:
                        z *= scale_z
                    return f'{m.group(1)}{x:.6f}{m.group(3)}{y:.6f}{m.group(5)}{z:.6f}{m.group(7)}'
                new_xml = vertex_pattern.sub(replace_vertex, new_xml)

            with open(model_path, 'w', encoding='utf-8') as f:
                f.write(new_xml)

        if total_transforms > 0:
            print(f"  ✓ Modified {total_transforms} transform matrix(es)")
        if total_vertices > 0:
            print(f"  ✓ Scaled {total_vertices} vertex coordinates directly")
        if total_transforms == 0 and total_vertices == 0:
            print(f"  ⚠️  No transforms or vertices found to scale!")

        with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as zout:
            for root, dirs, files in os.walk(tmpdir):
                for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, tmpdir)
                    zout.write(file_path, arcname)

    print(f"  ✓ Output: {output_path}")
    return output_path


def print_conversion_table(dim_data=None, fastener_type="hex_head"):
    """Print the SAE→Metric conversion table for a fastener type."""
    type_names = {
        "hex_head": "Hex Head Bolt",
        "hex_nut": "Hex Nut",
        "nylock_nut": "Nylock Nut",
        "socket_head_cap": "Socket Head Cap Screw",
        "button_head_cap": "Button Head Cap Screw",
    }
    
    print(f"\n{type_names.get(fastener_type, fastener_type)} — Metric → SAE Conversion")
    print("=" * 70)
    
    if dim_data and fastener_type in dim_data:
        cat = dim_data[fastener_type]
        dim_key = "across_flats_mm" if fastener_type in ("hex_head", "hex_nut", "nylock_nut") else "head_dia_mm"
        metric_dim_key = "metric_af_mm" if fastener_type in ("hex_head", "hex_nut", "nylock_nut") else "metric_head_dia_mm"
        
        print(f"{'SAE':<8} {'SAE mm':>8}  {'Metric':<8} {'Met mm':>8}  {'Scale':>8}  {'Δ':>7}")
        print("-" * 70)
        
        SAE_ORDER = ["1/4", "5/16", "3/8", "7/16", "1/2", "9/16", "5/8", "3/4", "7/8", "1"]
        sae_entries = []
        for k in cat.keys():
            entry = cat[k]
            thread = entry.get("thread", "")
            if not ('/' in thread or thread in ('1',)):  # SAE sizes only (includes '1' which has no slash)
                continue
            sae_entries.append(entry)
        sae_entries.sort(key=lambda e: SAE_ORDER.index(e.get('thread', '')) if e.get('thread', '') in SAE_ORDER else 99)
        
        for entry in sae_entries:
            thread = entry.get("thread", "")
            sae_dim = entry.get(dim_key, 0)
            metric = entry.get("closest_metric", "")
            metric_dim = entry.get(metric_dim_key, 0)
            if sae_dim and metric_dim:
                scale = sae_dim / metric_dim
                delta = (scale - 1) * 100
                marker = " ◀" if abs(delta) < 3 else ""
                print(f"{thread:<8} {sae_dim:>7.2f}  {metric:<8} {metric_dim:>7.2f}  {scale:>7.4f}  {delta:>+6.2f}%{marker}")
    else:
        # Fallback hardcoded
        print(f"{'SAE':<8} {'SAE AF':>8}  {'Metric':<8} {'Met AF':>8}  {'Scale':>8}  {'Δ':>7}")
        print("-" * 70)
        for sae, metric in SAE_TO_METRIC.items():
            sae_af = SAE_AF[sae]
            metric_af = METRIC_AF[metric]
            scale = sae_af / metric_af
            delta = (scale - 1) * 100
            print(f"{sae:<8} {sae_af:>7.2f}  {metric:<8} {metric_af:>7.2f}  {scale:>7.4f}  {delta:>+6.2f}%")
    print()


def main():
    dim_data = load_dimensions()
    
    parser = argparse.ArgumentParser(
        description="Scale a 3MF file's X/Y for metric→SAE conversion",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --table
  %(prog)s --table --fastener-type hex_nut
  %(prog)s model.3mf --sae 5/16
  %(prog)s model.3mf --sae 5/16 --fastener-type nylock_nut
  %(prog)s model.3mf --factor 0.977
  %(prog)s model.3mf --sae 5/16 -o my_handle.3mf
""")
    parser.add_argument('input', nargs='?', help='Input 3MF file')
    parser.add_argument('--sae', help='SAE bolt size (e.g. 5/16, 3/8, 1/2)')
    parser.add_argument('--metric', help='Metric bolt size (e.g. M8, M10)')
    parser.add_argument('--fastener-type', default='hex_head', choices=FASTENER_TYPES, help='Fastener type (default: hex_head)')
    parser.add_argument('--factor', type=float, help='Manual scale factor for X/Y')
    parser.add_argument('--z', type=float, default=1.0, help='Z scale factor (default: 1.0)')
    parser.add_argument('--output', '-o', help='Output 3MF file path')
    parser.add_argument('--table', action='store_true', help='Print conversion table and exit')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without writing')

    args = parser.parse_args()

    if args.table:
        print_conversion_table(dim_data, args.fastener_type)
        return

    if not args.input:
        parser.print_help()
        sys.exit(1)

    if not os.path.exists(args.input):
        sys.exit(f"Error: File not found: {args.input}")

    if args.factor is not None:
        scale_xy = args.factor
        print(f"Manual scale factor: {scale_xy:.4f}")
    elif args.sae:
        print("Computing scale factor:")
        scale_xy = compute_scale(args.sae, args.metric, args.fastener_type, dim_data)
        if scale_xy is None:
            sys.exit("Error: Could not determine scale factor")
    else:
        sys.exit("Error: Specify --sae, --metric, or --factor to set the scale")

    print(f"\nScaling: X/Y = {scale_xy:.4f}, Z = {args.z:.4f}")
    print(f"Input: {args.input}")

    if args.dry_run:
        print("(dry run — no output written)")
        return

    scale_3mf(args.input, scale_xy=scale_xy, scale_z=args.z, output_path=args.output)


if __name__ == '__main__':
    main()