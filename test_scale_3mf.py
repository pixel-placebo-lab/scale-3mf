#!/usr/bin/env python3
"""Regression tests for scale_3mf.py (review findings from the Sep 7 deepseek
code review — see CHANGELOG 'Unreleased/Fixed').

Self-contained: builds minimal 3MF fixtures in a temp dir, runs
scale_3mf.scale_3mf(), and inspects the output model XML. Works with
`python3 test_scale_3mf.py`, `python3 -m unittest test_scale_3mf`, or pytest.

Covers:
- S·M (world-space) transform scaling: rotated objects scale without shear
- Z-only scaling scales the full Z column (m02/m12/m22/m32)
- Mixed files: transform-covered AND vertex-scaled objects both end up scaled
- Reordered/extra vertex attributes still scale (parsed by name, not position)
- Scientific notation in transforms and vertices
- Output re-zip round-trip stays a valid ZIP with all members
"""

import contextlib
import importlib.util
import io
import os
import re
import sys
import tempfile
import unittest
import zipfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'scale_3mf_mod', os.path.join(_HERE, 'scale_3mf.py'))
scale_3mf_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(scale_3mf_mod)

MODEL_HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n'
              '<model unit="millimeter" '
              'xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">\n')


class Scale3MFTests(unittest.TestCase):

    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.workdir = self.tmpdir.name

    def tearDown(self):
        self.tmpdir.cleanup()

    # ── helpers ────────────────────────────────────────────────────────

    def make_3mf(self, name, model_xml):
        path = os.path.join(self.workdir, name)
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zf:
            zf.writestr('[Content_Types].xml',
                        '<?xml version="1.0" encoding="UTF-8"?>'
                        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                        '<Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>'
                        '</Types>')
            zf.writestr('_rels/.rels',
                        '<?xml version="1.0" encoding="UTF-8"?>'
                        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                        '<Relationship Target="/3D/3dmodel.model" Id="rel0" '
                        'Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>'
                        '</Relationships>')
            zf.writestr('3D/3dmodel.model', model_xml)
        return path

    def run_scale(self, input_path, scale_xy=1.0, scale_z=1.0):
        out_path = os.path.join(self.workdir, 'out.3mf')
        with contextlib.redirect_stdout(io.StringIO()):
            scale_3mf_mod.scale_3mf(input_path, scale_xy=scale_xy,
                                     scale_z=scale_z, output_path=out_path)
        return out_path

    def read_model(self, out_path):
        with zipfile.ZipFile(out_path) as zf:
            return zf.read('3D/3dmodel.model').decode('utf-8')

    def transform_values(self, xml):
        m = re.search(r'transform="([^"]+)"', xml)
        self.assertIsNotNone(m, 'no transform attribute in output XML')
        return [float(v) for v in m.group(1).split()]

    def assert_matrix(self, actual, expected, places=4):
        self.assertEqual(len(actual), 12)
        for i, (a, e) in enumerate(zip(actual, expected)):
            self.assertAlmostEqual(a, e, places=places,
                                    msg=f'element {i}: {a} != {e}')

    # ── Finding 1: X/Y scaling shears tilted objects ──────────────────

    def test_rotated_transform_xy_scale_is_matrix_multiply(self):
        """45° Y-rotation + X/Y×2 must scale the whole matrix (S·M), leaving
        m20 scaled (the old code left it unscaled → shear)."""
        c = 0.7071
        xml = MODEL_HEAD + f'''<resources>
<object id="1" type="model"><mesh><vertices>
<vertex x="0" y="0" z="0"/>
</vertices><triangles><triangle v1="0" v2="0" v3="0"/></triangles></mesh></object>
</resources>
<build>
<item objectid="1" transform="{c} 0 {c} 0 1 0 -{c} 0 {c} 10 20 30"/>
</build>
</model>
'''
        out = self.run_scale(self.make_3mf('in.3mf', xml), scale_xy=2.0)
        vals = self.transform_values(self.read_model(out))
        # Column scaling: col0 (idx 0,3,6,9) ×2, col1 (1,4,7,10) ×2, col2 ×1
        self.assert_matrix(vals,
                           [2 * c, 0, c,
                            0, 2, 0,
                            -2 * c, 0, c,
                            20, 40, 30])

    # ── Finding 2: Z scaling left m02/m12 unscaled ─────────────────────

    def test_z_scale_scales_full_z_column(self):
        """45° X-rotation + Z×2 must scale m02/m12/m22/m32 (the old code
        scaled only m22 and m32 → shear)."""
        c = 0.7071
        xml = MODEL_HEAD + f'''<resources>
<object id="1" type="model"><mesh><vertices>
<vertex x="0" y="0" z="0"/>
</vertices><triangles><triangle v1="0" v2="0" v3="0"/></triangles></mesh></object>
</resources>
<build>
<item objectid="1" transform="1 0 0 0 {c} -{c} 0 {c} {c} 10 20 30"/>
</build>
</model>
'''
        out = self.run_scale(self.make_3mf('in.3mf', xml), scale_xy=1.0, scale_z=2.0)
        vals = self.transform_values(self.read_model(out))
        self.assert_matrix(vals,
                           [1, 0, 0,
                            0, c, -2 * c,
                            0, c, 2 * c,
                            10, 20, 60])

    # ── Finding 3: mixed transformed/untransformed objects ────────────

    def test_mixed_objects_both_scaled(self):
        """One item WITH transform + one WITHOUT: the transform must scale,
        the uncovered object's vertices must scale, and the covered object's
        vertices must NOT (no double scaling)."""
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
</model>
'''
        out = self.run_scale(self.make_3mf('in.3mf', xml), scale_xy=2.0)
        result = self.read_model(out)

        # Object 1: scaled through its transform matrix
        self.assert_matrix(self.transform_values(result),
                           [2, 0, 0, 0, 2, 0, 0, 0, 1, 10, 10, 5])
        obj1 = re.search(r'<object id="1".*?</object>', result, re.DOTALL).group(0)
        self.assertIn('x="10"', obj1, 'transform-covered object vertices must not double-scale')
        # Object 2: scaled via vertices directly
        obj2 = re.search(r'<object id="2".*?</object>', result, re.DOTALL).group(0)
        self.assertIn('x="20.000000"', obj2)
        self.assertIn('y="20.000000"', obj2)
        self.assertIn('z="10.000000"', obj2)

    # ── Finding 4: vertex attribute order ─────────────────────────────

    def test_reordered_vertex_attributes_still_scale(self):
        """z-before-x attribute order and extra attributes must not hide a
        vertex from scaling; order and extra attrs are preserved."""
        xml = MODEL_HEAD + '''<resources>
<object id="1" type="model"><mesh><vertices>
<vertex z="3" y="2" x="1" p1="0.5"/>
<vertex y="5" x="4" z="6"/>
</vertices><triangles><triangle v1="0" v2="1" v3="0"/></triangles></mesh></object>
</resources>
<build>
<item objectid="1"/>
</build>
</model>
'''
        out = self.run_scale(self.make_3mf('in.3mf', xml), scale_xy=2.0)
        result = self.read_model(out)
        self.assertIn('<vertex z="3.000000" y="4.000000" x="2.000000" p1="0.5"/>', result,
                      'reordered attrs must scale in place, preserving order + extras')
        self.assertIn('<vertex y="10.000000" x="8.000000" z="6.000000"/>', result)

    # ── Finding 5: scientific notation parity ─────────────────────────

    def test_scientific_notation_transform_scales(self):
        xml = MODEL_HEAD + '''<resources>
<object id="1" type="model"><mesh><vertices>
<vertex x="0" y="0" z="0"/>
</vertices><triangles><triangle v1="0" v2="0" v3="0"/></triangles></mesh></object>
</resources>
<build>
<item objectid="1" transform="1e0 0 0 0 1e0 0 0 0 1e0 1e1 2e1 3e1"/>
</build>
</model>
'''
        out = self.run_scale(self.make_3mf('in.3mf', xml), scale_xy=2.0)
        vals = self.transform_values(self.read_model(out))
        self.assert_matrix(vals, [2, 0, 0, 0, 2, 0, 0, 0, 1, 20, 40, 30])

    def test_scientific_notation_vertices_scale(self):
        xml = MODEL_HEAD + '''<resources>
<object id="1" type="model"><mesh><vertices>
<vertex x="1e0" y="2e0" z="3e0"/>
<vertex x="1.5E1" y="-2.5" z="+.5e1"/>
</vertices><triangles><triangle v1="0" v2="1" v3="0"/></triangles></mesh></object>
</resources>
<build>
<item objectid="1"/>
</build>
</model>
'''
        out = self.run_scale(self.make_3mf('in.3mf', xml), scale_xy=2.0)
        result = self.read_model(out)
        self.assertIn('<vertex x="2.000000" y="4.000000" z="3.000000"/>', result)
        self.assertIn('<vertex x="30.000000" y="-5.000000" z="5.000000"/>', result)

    # ── Output validity ──────────────────────────────────────────────

    def test_output_zip_roundtrip_valid(self):
        """Scaled output is a valid ZIP with every original member preserved."""
        xml = MODEL_HEAD + '''<resources>
<object id="1" type="model"><mesh><vertices>
<vertex x="1" y="2" z="3"/>
</vertices><triangles><triangle v1="0" v2="0" v3="0"/></triangles></mesh></object>
</resources>
<build>
<item objectid="1"/>
</build>
</model>
'''
        out = self.run_scale(self.make_3mf('in.3mf', xml), scale_xy=2.0)
        with zipfile.ZipFile(out) as zf:
            self.assertIsNone(zf.testzip())
            for member in ('[Content_Types].xml', '_rels/.rels', '3D/3dmodel.model'):
                self.assertIn(member, zf.namelist())

    # ── Batch mode ────────────────────────────────────────────────────

    def make_batch_dir(self, names):
        d = os.path.join(self.workdir, 'batch_in')
        os.makedirs(d, exist_ok=True)
        for i, n in enumerate(names):
            xml = MODEL_HEAD + (
                '<resources>'
                '<object id="1" type="model"><mesh><vertices>'
                f'<vertex x="{i+1}" y="2" z="3"/>'
                '</vertices><triangles><triangle v1="0" v2="0" v3="0"/></triangles></mesh></object>'
                '</resources><build><item objectid="1"/></build>'
                '</model>')
            self.make_3mf(os.path.join('batch_in', n), xml)
        return d

    def test_batch_dry_run_creates_no_output(self):
        d = self.make_batch_dir(['a.3mf', 'b.3mf', 'c.3mf'])
        before = sorted(os.listdir(d))
        with contextlib.redirect_stdout(io.StringIO()):
            processed, failed = scale_3mf_mod.process_batch(
                d, scale_xy=2.0, dry_run=True)
        self.assertEqual(processed, 0)
        self.assertEqual(failed, 0)
        self.assertEqual(sorted(os.listdir(d)), before)

    def test_batch_processes_all_3mf_files(self):
        d = self.make_batch_dir(['a.3mf', 'b.3mf', 'c.3mf'])
        with contextlib.redirect_stdout(io.StringIO()):
            processed, failed = scale_3mf_mod.process_batch(d, scale_xy=2.0)
        self.assertEqual(processed, 3)
        self.assertEqual(failed, 0)
        # Each scaled output doubles BOTH x and y (vertex-based file).
        expect = {'a_s2.000.3mf': 'x="2.000000" y="4.000000"',
                  'b_s2.000.3mf': 'x="4.000000" y="4.000000"',
                  'c_s2.000.3mf': 'x="6.000000" y="4.000000"'}
        for name, marker in expect.items():
            xml = self.read_model(os.path.join(d, name))
            self.assertIn(marker, xml)

    def test_batch_respects_output_dir(self):
        d = self.make_batch_dir(['a.3mf', 'b.3mf'])
        outdir = os.path.join(self.workdir, 'batch_out')
        with contextlib.redirect_stdout(io.StringIO()):
            processed, _ = scale_3mf_mod.process_batch(
                d, scale_xy=2.0, output_dir=outdir)
        self.assertEqual(processed, 2)
        self.assertEqual(sorted(os.listdir(d)), ['a.3mf', 'b.3mf'])
        self.assertEqual(len(os.listdir(outdir)), 2)
        self.assertTrue(all(f.endswith('.3mf') for f in os.listdir(outdir)))

    def test_batch_fails_on_non_directory(self):
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stdout(io.StringIO()):
                scale_3mf_mod.process_batch(
                    os.path.join(self.workdir, 'missing'), scale_xy=2.0)

    def test_batch_no_3mf_raises(self):
        d = os.path.join(self.workdir, 'empty_dir')
        os.makedirs(d, exist_ok=True)
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stdout(io.StringIO()):
                scale_3mf_mod.process_batch(d, scale_xy=2.0)


if __name__ == '__main__':
    unittest.main(verbosity=2)