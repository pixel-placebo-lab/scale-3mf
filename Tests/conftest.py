"""Shared pytest fixtures for the scale-3mf Python test suite.

Makes the repo root (one directory up) importable so tests can `import
scale_3mf` directly, builds minimal valid 3MF fixtures in-memory, and runs
the CLI through its argparse `main()` with captured stdout.
"""

import contextlib
import io
import os
import sys
import zipfile

import pytest

# Make the repo root importable (scale_3mf.py lives one directory up).
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

import scale_3mf  # noqa: E402  (needs the sys.path insert above)

# ── Minimal valid 3MF model skeleton (spec-compliant package). ─────────
CONTENT_TYPES = ('<?xml version="1.0" encoding="UTF-8"?>'
                 '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                 '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                 '<Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>'
                 '</Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Target="/3D/3dmodel.model" Id="rel0" '
        'Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>'
        '</Relationships>')
MODEL_HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n'
              '<model unit="millimeter" '
              'xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">\n')
MODEL_TAIL = '</model>\n'


def make_3mf_zip(model_xml, obj_name='3D/3dmodel.model'):
    """Return an in-memory 3MF package (bytes) for the given model XML."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('[Content_Types].xml', CONTENT_TYPES)
        zf.writestr('_rels/.rels', RELS)
        zf.writestr(obj_name, model_xml)
    return buf.getvalue()


@pytest.fixture
def model_cube():
    """A 10×10×10 cube as a single untransformed object (vertex-based)."""
    return MODEL_HEAD + '''<resources>
<object id="1" type="model"><mesh><vertices>
<vertex x="0" y="0" z="0"/>
<vertex x="10" y="0" z="0"/>
<vertex x="10" y="10" z="0"/>
<vertex x="0" y="10" z="0"/>
<vertex x="0" y="0" z="10"/>
<vertex x="10" y="0" z="10"/>
<vertex x="10" y="10" z="10"/>
<vertex x="0" y="10" z="10"/>
</vertices><triangles>
<triangle v1="0" v2="1" v3="2"/><triangle v1="0" v2="2" v3="3"/>
<triangle v1="4" v2="5" v3="6"/><triangle v1="4" v2="6" v3="7"/>
<triangle v1="1" v2="5" v3="6"/><triangle v1="1" v2="6" v3="2"/>
<triangle v1="3" v2="7" v3="6"/><triangle v1="3" v2="6" v3="2"/>
<triangle v1="0" v2="4" v3="5"/><triangle v1="0" v2="5" v3="1"/>
<triangle v1="2" v2="6" v3="7"/><triangle v1="2" v2="7" v3="3"/>
</triangles></mesh></object>
</resources>
<build>
<item objectid="1"/>
</build>
''' + MODEL_TAIL


@pytest.fixture
def model_transformed_cube():
    """Cube placed with a 45° Y-rotation transform; 4×3 row-major matrix
    (m00 m01 m02 m10 m11 m20 m21 m22 m30 m31 m32 = identity + translation).
    """
    return MODEL_HEAD + '''<resources>
<object id="1" type="model"><mesh><vertices>
<vertex x="0" y="0" z="0"/><vertex x="10" y="0" z="0"/>
<vertex x="10" y="10" z="0"/><vertex x="0" y="10" z="0"/>
</vertices><triangles>
<triangle v1="0" v2="1" v3="2"/><triangle v1="0" v2="2" v3="3"/>
</triangles></mesh></object>
</resources>
<build>
<item objectid="1" transform="1 0 0 0 1 0 0 0 1 5 6 7"/>
</build>
''' + MODEL_TAIL


@pytest.fixture
def write_model(tmp_path, model_cube):
    """Write model XML to a temp .3mf, return its path."""
    def _write(xml, name='in.3mf'):
        p = tmp_path / name
        p.write_bytes(make_3mf_zip(xml))
        return str(p)
    return _write


@pytest.fixture
def run_cli(monkeypatch, capsys):
    """Invoke scale_3mf.main() with argv; return (exit_code, stdout, stderr).

    argparse errors / sys.exit are captured rather than propagated.
    """
    def _run(*argv):
        argv = [str(a) for a in argv]  # normalize pathlib.Path args for argparse
        monkeypatch.setattr(sys, 'argv', ['scale_3mf.py'] + list(argv))
        code = 0
        code_note = ''
        try:
            scale_3mf.main()
        except SystemExit as e:
            # sys.exit(msg) sets e.code to a message string, not an int.
            # Normalize any non-int/None exit to a nonzero code and surface
            # the message so tests can assert on it.
            if e.code is None:
                code = 0
            elif isinstance(e.code, int):
                code = e.code
            else:
                code = 1
                code_note = str(e.code)
        out, err = capsys.readouterr()
        return code, out, err + code_note
    return _run
