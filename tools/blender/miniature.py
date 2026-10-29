# Builds the tray the session in miniature lies on, and writes assets/models/miniature.glb.
#
#     blender --background --python tools/blender/miniature.py
#
# WHAT IT IS FOR
#
# The session in miniature (docs/spatial_loop.md part two, slice 34, idea #6): a 40 cm model of the
# whole session to hold, its tracks strips with their items as blocks on them, the regions bands,
# the markers flags, the loop a bracket and the playhead moving, and the room's stations pins round
# its edge. All of that is MiniatureItem's own, drawn from the song as it changes. This is only
# what it lies on: a shallow wooden tray, its felt bed sunk a few millimetres inside a raised lip,
# so it reads as a thing to pick up by its edge, as a tray is, and the lip is where the pins stand.
# Four small feet keep it off the desk's wing.
#
# MiniatureItem repeats every number below (SIZE, BAND, BED_TOP, LIP_TOP), so the two agree.
#
# ORIENTATION (see _parts.py)
#
# Godot +Y is Blender +Z and Godot -Z is Blender +Y. The origin is the middle of its bottom. Its
# reader stands at Godot +Z (Blender -Y), the song's time runs along Godot +X.

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    bevel_all, box, clear_scene, export, join, material, report, smooth,
)

# --- In metres, in Godot's terms (x along the song, y up, z toward the reader). ---------------

SIZE = (0.40, 0.30)       # the tray's footprint
FOOT = 0.003              # the feet's height
SLAB_TOP = 0.016          # the slab's top, under the felt
BED_TOP = 0.020           # the felt bed's top: where the strips lie
LIP_TOP = 0.024           # the lip's top: where the pins stand
BAND = 0.03               # how wide the lip is, all round


def gbox(name, lo, hi):
    """A box from Godot-space corners: x, y up, z toward you."""
    size = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    centre = ((lo[0] + hi[0]) * 0.5, -(lo[2] + hi[2]) * 0.5, (lo[1] + hi[1]) * 0.5)
    return box(name, size, centre)


MATS = []


def slot(obj, index):
    obj.data.materials.clear()
    for m in MATS:
        obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = index
    return obj


def tray():
    clear_scene()
    MATS[:] = [material("wood", (0.40, 0.26, 0.15, 1.0), 0.5),
            material("felt", (0.05, 0.06, 0.075, 1.0), 0.95),
            material("foot", (0.03, 0.03, 0.03, 1.0), 0.8)]
    hx, hz = SIZE[0] * 0.5, SIZE[1] * 0.5
    ix, iz = hx - BAND, hz - BAND
    parts = []
    slab = slot(gbox("Slab", (-hx, FOOT, -hz), (hx, SLAB_TOP, hz)), 0)
    bevel_all(slab, 0.003, 2)
    # The lip, four bars round the bed, their outer edges the slab's.
    lips = [
        gbox("LipFar", (-hx, SLAB_TOP - 0.001, -hz), (hx, LIP_TOP, -iz)),
        gbox("LipNear", (-hx, SLAB_TOP - 0.001, iz), (hx, LIP_TOP, hz)),
        gbox("LipLeft", (-hx, SLAB_TOP - 0.001, -iz), (-ix, LIP_TOP, iz)),
        gbox("LipRight", (ix, SLAB_TOP - 0.001, -iz), (hx, LIP_TOP, iz)),
    ]
    for lip in lips:
        bevel_all(lip, 0.0015, 1)
        parts.append(slot(lip, 0))
    parts.append(slot(gbox("Bed", (-ix, SLAB_TOP - 0.001, -iz), (ix, BED_TOP, iz)), 1))
    for x in (-hx + 0.03, hx - 0.03):
        for z in (-hz + 0.03, hz - 0.03):
            parts.append(slot(gbox("Foot", (x - 0.012, 0.0, z - 0.012), (x + 0.012, FOOT + 0.0005, z + 0.012)), 2))
    obj = join(slab, parts)
    obj.name = "Miniature"
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/miniature.glb")


os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
tray()
