"""Comprehensive pytest suite for scale_3mf.py.

Mirrors the coverage of the 36 Swift unit tests in
Tests/Scale3MFTests/ (ConversionTableTests.swift + ConverterTests.swift).

Areas covered:
  1. Conversion table lookups — SAE bolt sizes, metric sizes, 8020 profiles
  2. CLI arg parsing         — --sae, --metric, --fastener-type, --factor,
                               --z, --output, --table, --dry-run, --profile-table
  3. 3MF round-trip integrity — scale a generated 3MF, reload, verify dims
  4. Vertex-fallback paths
  5. Error paths             — bad input file, missing args, unknown sizes

Run with:  python3 -m pytest tests/ -q
"""

import os
import zipfile

import pytest

import scale_3mf
from conftest import make_3mf_zip, MODEL_HEAD, MODEL_TAIL


# ──────────────────────────────────────────────────────────────────────
# 1. Conversion table lookups
# ──────────────────────────────────────────────────────────────────────

class TestConversionTables:
    def test_sae_across_flats_table(self):
        """Hardcoded SAE hex AF table has expected values for common sizes."""
        assert scale_3mf.SAE_AF["1/4"] == pytest.approx(11.11)
        assert scale_3mf.SAE_AF["5/16"] == pytest.approx(12.70)
        assert scale_3mf.SAE_AF["1/2"] == pytest.approx(19.05)
        assert scale_3mf.SAE_AF["1"] == pytest.approx(41.28)

    def test_metric_across_flats_table(self):
        """Hardcoded metric hex AF table has expected values."""
        assert scale_3mf.METRIC_AF["M8"] == pytest.approx(13.0)
        assert scale_3mf.METRIC_AF["M10"] == pytest.approx(16.0)
        assert scale_3mf.METRIC_AF["M24"] == pytest.approx(36.0)

    def test_sae_to_metric_map(self):
        """SAE→closest-metric correspondence for core sizes."""
        assert scale_3mf.SAE_TO_METRIC["1/4"] == "M6"
        assert scale_3mf.SAE_TO_METRIC["5/16"] == "M8"
        assert scale_3mf.SAE_TO_METRIC["1/2"] == "M12"
        assert scale_3mf.SAE_TO_METRIC["3/4"] == "M20"

    def test_compute_scale_quarter_inch(self):
        """5/16 hex_head → M8 should be ~0.977 (12.70 / 13.00)."""
        factor = scale_3mf.compute_scale("5/16", None, "hex_head")
        assert factor is not None
        assert factor == pytest.approx(0.9769, abs=1e-3)

    def test_compute_scale_quarter_inch_from_json(self):
        """JSON-backed lookup for 1/4 hex_head → M6 = 11.11/10.0 ≈ 1.111."""
        dim = scale_3mf.load_dimensions()
        factor = scale_3mf.compute_scale("1/4", None, "hex_head", dim)
        assert factor is not None
        assert factor == pytest.approx(1.111, abs=1e-3)

    def test_compute_scale_explicit_metric(self):
        """Explicit --metric overrides the closest metric mapping."""
        dim = scale_3mf.load_dimensions()
        # 5/16 hex_head → M6 = 12.70 / 10.0 = 1.27
        factor = scale_3mf.compute_scale("5/16", "M6", "hex_head", dim)
        assert factor is not None
        assert factor == pytest.approx(1.27, abs=1e-3)

    def test_compute_scale_socket_head_cap(self):
        """Socket head cap uses head diameter, not across-flats."""
        dim = scale_3mf.load_dimensions()
        factor = scale_3mf.compute_scale("3/8", None, "socket_head_cap", dim)
        # 3/8 head_dia 14.3 / M10 head_dia 16.0 ≈ 0.894
        assert factor is not None
        assert factor == pytest.approx(14.3 / 16.0, abs=1e-3)

    def test_extrusion_profiles_loaded(self):
        """8020 profile presets exist with correct body-scale factors."""
        assert "2020-to-1010" in scale_3mf.EXTRUSION_PROFILES
        assert "1010-to-2020" in scale_3mf.EXTRUSION_PROFILES
        p = scale_3mf.EXTRUSION_PROFILES["2020-to-1010"]
        assert p["scale"] == pytest.approx(25.4 / 20)
        # Imperial→metric reverses the factor
        assert scale_3mf.EXTRUSION_PROFILES["1010-to-2020"]["scale"] == pytest.approx(20 / 25.4)

    def test_profile_slot_math(self):
        """T-slot after scaling = source slot × body scale."""
        p = scale_3mf.EXTRUSION_PROFILES["2020-to-1010"]
        assert p["source_slot_mm"] == pytest.approx(8.0)
        assert p["target_slot_mm"] == pytest.approx(6.35)
        assert p["source_slot_mm"] * p["scale"] == pytest.approx(
            scale_3mf.EXTRUSION_PROFILES["2020-to-1010"]["scale"] * 8.0)


# ──────────────────────────────────────────────────────────────────────
# 2. CLI arg parsing
# ──────────────────────────────────────────────────────────────────────

class TestCLI:
    def test_table_flag_prints_and_exits(self, run_cli):
        code, out, _ = run_cli("--table")
        assert code == 0
        assert "Conversion" in out
        assert "5/16" in out

    def test_table_flag_with_fastener_type(self, run_cli):
        code, out, _ = run_cli("--table", "--fastener-type", "hex_nut")
        assert code == 0
        assert "Hex Nut" in out

    def test_profile_table_flag(self, run_cli):
        code, out, _ = run_cli("--profile-table")
        assert code == 0
        assert "8020" in out
        assert "2020-to-1010" in out

    def test_invalid_fastener_type(self, run_cli):
        code, out, err = run_cli("--table", "--fastener-type", "bogus")
        assert code == 2  # argparse usage error
        assert "invalid choice" in (out + err)

    def test_dry_run_no_output(self, run_cli, model_cube, tmp_path):
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(model_cube))
        out_path = tmp_path / "out.3mf"
        code, out, _ = run_cli(
            "--sae", "5/16", "--dry-run", src, "--output", str(out_path))
        assert code == 0
        assert "dry run" in out
        # Z = default 1.0; no output file written
        assert not out_path.exists()

    def test_factor_flag_sets_scale(self, run_cli, model_cube, tmp_path):
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(model_cube))
        out_path = tmp_path / "out.3mf"
        code, out, _ = run_cli("--factor", "0.977", "--output", str(out_path), src)
        assert code == 0
        assert "0.9770" in out
        assert out_path.exists()

    def test_metric_sae_and_z_flags(self, run_cli, model_cube, tmp_path):
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(model_cube))
        out_path = tmp_path / "out.3mf"
        code, out, _ = run_cli(
            "--sae", "5/16", "--metric", "M8", "--z", "2.0",
            "--output", str(out_path), src)
        assert code == 0
        assert out_path.exists()

    def test_default_output_naming_contains_factor(self, run_cli, model_cube, tmp_path):
        # Output defaults to <base>_s<scale>.3mf when --output omitted
        src = tmp_path / "bolt.3mf"
        src.write_bytes(make_3mf_zip(model_cube))
        code, out, _ = run_cli("--factor", "0.5", src)
        assert code == 0
        expected = tmp_path / "bolt_s0.500.3mf"
        assert expected.exists()

    def test_profile_scale_flag(self, run_cli, model_cube, tmp_path):
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(model_cube))
        out_path = tmp_path / "out.3mf"
        code, out, _ = run_cli(
            "--profile-scale", "2020-to-1010", "--output", str(out_path), src)
        assert code == 0
        assert "Profile scaling" in out
        assert out_path.exists()


# ──────────────────────────────────────────────────────────────────────
# 3. 3MF round-trip integrity
# ──────────────────────────────────────────────────────────────────────

class TestRoundTrip:
    def read_model(self, path):
        with zipfile.ZipFile(path) as zf:
            return zf.read('3D/3dmodel.model').decode('utf-8')

    def test_vertex_cube_xy_scale_dimensions(self, model_cube, tmp_path):
        """10×10 cube scaled X/Y×2 → vertices land at 20; Z unchanged."""
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(model_cube))
        out_path = tmp_path / "out.3mf"
        scale_3mf.scale_3mf(str(src), scale_xy=2.0, output_path=str(out_path))
        xml = self.read_model(out_path)
        assert 'x="20.000000"' in xml
        assert 'y="20.000000"' in xml
        # Z preserved at 10
        assert 'z="10.000000"' in xml
        # Original 0-coords stay 0 (vertex scale multiplies 0)
        assert 'x="0.000000"' in xml

    def test_vertex_cube_z_scale(self, model_cube, tmp_path):
        """Z×3 on a vertex-based cube → z coords ×3, x/y untouched."""
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(model_cube))
        out_path = tmp_path / "out.3mf"
        scale_3mf.scale_3mf(str(src), scale_xy=1.0, scale_z=3.0, output_path=str(out_path))
        xml = self.read_model(out_path)
        assert 'z="30.000000"' in xml
        assert 'x="10.000000"' in xml

    def test_transform_translation_scaled(self, model_transformed_cube, tmp_path):
        """Transform-based object: translation row (m30 m31 m32) scales X/Y,
        matrix basis columns scale by axis factor."""
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(model_transformed_cube))
        out_path = tmp_path / "out.3mf"
        scale_3mf.scale_3mf(str(src), scale_xy=2.0, output_path=str(out_path))
        xml = self.read_model(out_path)
        # translation 5 6 7 → 10 12 7 (X/Y scaled, Z not); formatted 6-dp
        assert ('transform="2.000000 0.000000 0.000000 0.000000 '
                '2.000000 0.000000 0.000000 0.000000 1.000000 '
                '10.000000 12.000000 7.000000"') in xml

    def test_roundtrip_is_valid_zip(self, model_cube, tmp_path):
        """Scaled output stays a valid ZIP with every member preserved."""
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(model_cube))
        out_path = tmp_path / "out.3mf"
        scale_3mf.scale_3mf(str(src), scale_xy=0.5, output_path=str(out_path))
        with zipfile.ZipFile(out_path) as zf:
            assert zf.testzip() is None
            assert set(('[Content_Types].xml', '_rels/.rels', '3D/3dmodel.model')) <= set(zf.namelist())


# ──────────────────────────────────────────────────────────────────────
# 4. Vertex-fallback paths
# ──────────────────────────────────────────────────────────────────────

class TestVertexFallback:
    def read_model(self, path):
        with zipfile.ZipFile(path) as zf:
            return zf.read('3D/3dmodel.model').decode('utf-8')

    def test_object_without_transform_vertex_scaled(
            self, model_cube, tmp_path):
        """Untransformed object falls back to direct vertex scaling."""
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(model_cube))
        out_path = tmp_path / "out.3mf"
        scale_3mf.scale_3mf(str(src), scale_xy=2.0, output_path=str(out_path))
        xml = self.read_model(out_path)
        assert 'x="20.000000"' in xml

    def test_mixed_transform_and_vertex(self, tmp_path):
        """One item with transform + one without: transform scales, the
        uncovered object's vertices scale, the covered one's do NOT."""
        xml = MODEL_HEAD + '''<resources>
<object id="1" type="model"><mesh><vertices>
<vertex x="10" y="10" z="10"/>
</vertices><triangles><triangle v1="0" v2="0" v3="0"/></triangles></mesh></object>
<object id="2" type="model"><mesh><vertices>
<vertex x="10" y="10" z="10"/>
</vertices><triangles><triangle v1="0" v2="0" v3="0"/></triangles></mesh></object>
</resources>
<build>
<item objectid="1" transform="1 0 0 0 1 0 0 0 1 5 5 5"/>
<item objectid="2"/>
</build>
''' + MODEL_TAIL
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(xml))
        out_path = tmp_path / "out.3mf"
        scale_3mf.scale_3mf(str(src), scale_xy=2.0, output_path=str(out_path))
        result = self.read_model(out_path)
        # Obj 1 transform translation 5 5 5 → 10 10 5 (formatted 6-dp)
        assert ('transform="2.000000 0.000000 0.000000 0.000000 '
                '2.000000 0.000000 0.000000 0.000000 1.000000 '
                '10.000000 10.000000 5.000000"') in result
        # Obj 2 vertex 10 → 20
        assert 'x="20.000000"' in result

    def test_reordered_vertex_attributes(self, tmp_path):
        """z-before-x order and extra attributes still scale (parsed by name)."""
        xml = MODEL_HEAD + '''<resources>
<object id="1" type="model"><mesh><vertices>
<vertex z="3" y="2" x="1" p1="0.5"/>
</vertices><triangles><triangle v1="0" v2="0" v3="0"/></triangles></mesh></object>
</resources>
<build>
<item objectid="1"/>
</build>
''' + MODEL_TAIL
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(xml))
        out_path = tmp_path / "out.3mf"
        scale_3mf.scale_3mf(str(src), scale_xy=2.0, output_path=str(out_path))
        result = self.read_model(out_path)
        assert 'z="3.000000"' in result  # Z not scaled, unchanged
        assert 'y="4.000000"' in result  # y 2×2
        assert 'x="2.000000"' in result  # x 1×2
        assert 'p1="0.5"' in result     # extra attr preserved


# ──────────────────────────────────────────────────────────────────────
# 5. Error paths
# ──────────────────────────────────────────────────────────────────────

class TestErrorPaths:
    def test_missing_input_arg(self, run_cli):
        """No input + no scale flag → usage/help and nonzero exit."""
        code, out, err = run_cli()
        assert code == 1
        assert "usage" in (out + err).lower()

    def test_nonexistent_input_file(self, run_cli, tmp_path):
        code, out, err = run_cli(
            "--sae", "5/16", str(tmp_path / "missing.3mf"))
        assert code == 1
        assert "File not found" in (out + err)

    def test_unknown_sae_returns_error(self, run_cli, tmp_path):
        """A size with no conversion → exits with error, no scaling."""
        src = tmp_path / "in.3mf"
        src.write_bytes(make_3mf_zip(MODEL_HEAD + "<resources/>"
                                     "<build/>" + MODEL_TAIL))
        code, out, err = run_cli("--sae", "99/99", src)
        assert code == 1
        assert "Could not determine scale factor" in (out + err)

    def test_bad_3mf_missing_3d_dir(self, tmp_path):
        """A zip without a 3D/ directory → SystemExit with clear error."""
        import sys
        bad = tmp_path / "bad.3mf"
        with zipfile.ZipFile(bad, 'w') as zf:
            zf.writestr('random.txt', 'not a 3mf')
        with pytest.raises(SystemExit) as exc:
            scale_3mf.scale_3mf(str(bad), scale_xy=2.0, output_path=str(tmp_path / "o.3mf"))
        assert "No 3D/ directory" in str(exc.value)

    def test_no_model_file_in_3d(self, tmp_path):
        """A zip with 3D/ but no .model → SystemExit."""
        bad = tmp_path / "bad.3mf"
        with zipfile.ZipFile(bad, 'w') as zf:
            zf.writestr('3D/readme.txt', 'no model here')
        with pytest.raises(SystemExit) as exc:
            scale_3mf.scale_3mf(str(bad), scale_xy=2.0, output_path=str(tmp_path / "o.3mf"))
        assert "No .model file" in str(exc.value)

    def test_unknown_profile_preset(self, run_cli):
        code, out, err = run_cli("--profile-scale", "bogus-profile")
        assert code == 1
        assert "Unknown profile preset" in (out + err)
