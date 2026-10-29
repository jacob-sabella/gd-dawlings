# Builds a chord brick and the ledge on the bricks table that holds a progression of them, and
# writes assets/models/chord_brick.glb and assets/models/chord_ledge.glb.
#
#     blender --background --python tools/blender/chord_brick.py
#
# WHAT THEY ARE FOR
#
# Chord bricks (docs/spatial_loop.md part two, slice 31, idea #16): a chord as a block you hold,
# made from the fifths wheel's strip, stood in a row on the ledge along the bricks table's near
# edge, where the row is a progression. Pressed into a track it writes the row's chords; pressed
# into a section block it writes that section's harmony. So it reads as a toy wooden brick first: a
# chunky painted block with softened edges, its two long faces left plain for ChordBrick to letter
# with the chord and its numeral. The studs on its top (one a bar it lasts: 1, 2 or 4) are
# ChordBrick's own, since a nudge changes them.
#
# The ledge is a long rail with sixteen shallow felt slots, numbered by ChordLedge, a low lip along
# its front so a brick stands against it, a tray behind where a brick with nowhere else to be lies,
# and at its right end an open box, the BIN. ChordLedge repeats every number below (the slots, the
# rail's top, the tray, the bin), so the two agree.
#
# ORIENTATION (see _parts.py)
#
# Godot +Y is Blender +Z and Godot -Z is Blender +Y. The brick's origin is the middle of its
# bottom. The ledge's origin is the middle of its band on the table top; its front, where you
# stand, is Godot +Z: Blender -Y; it runs along Godot +X.

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    bevel_all, box, clear_scene, export, join, material, report, smooth,
)

# --- The brick, in metres (Godot x along its long face, y up, z through it). -----------------

BRICK = (0.060, 0.035, 0.045)

# --- The ledge, in metres, in Godot's terms (y up, z toward you), as ChordLedge has them. ------

SLOTS = 16
STEP = 0.070
RAIL_HALF = 0.565
RAIL_BACK = 0.005
RAIL_FRONT = 0.095
RAIL_TOP = 0.018
SLOT_Z = 0.048
SLOT = (0.064, 0.052)
LIP = (0.095, 0.106, 0.024)            # z from, z to, its top
TRAY = (-0.13, -0.02, 0.008)           # z from, z to, its top
BIN = (0.585, 0.665, 0.0, 0.1, 0.05)   # x from, x to, z from, z to, its top
WALL = 0.005


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


def brick():
    clear_scene()
    MATS[:] = [material("brick", (0.86, 0.80, 0.66, 1.0), 0.6)]
    hx, hy, hz = BRICK[0] * 0.5, BRICK[1], BRICK[2] * 0.5
    obj = slot(gbox("ChordBrick", (-hx, 0.0, -hz), (hx, hy, hz)), 0)
    bevel_all(obj, 0.0035, 3)
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/chord_brick.glb")


def ledge():
    clear_scene()
    MATS[:] = [material("wood", (0.36, 0.23, 0.13, 1.0), 0.55),
            material("felt", (0.09, 0.10, 0.12, 1.0), 0.95),
            material("metal", (0.62, 0.60, 0.56, 1.0), 0.3),
            material("bin", (0.16, 0.16, 0.17, 1.0), 0.6)]
    parts = []
    parts.append(slot(gbox("Rail", (-RAIL_HALF, 0.0, RAIL_BACK), (RAIL_HALF, RAIL_TOP, RAIL_FRONT)), 0))
    for n in range(SLOTS):
        x = (n - (SLOTS - 1) * 0.5) * STEP
        parts.append(slot(gbox("Slot", (x - SLOT[0] * 0.5, RAIL_TOP - 0.0015, SLOT_Z - SLOT[1] * 0.5),
                (x + SLOT[0] * 0.5, RAIL_TOP + 0.0006, SLOT_Z + SLOT[1] * 0.5)), 1))
    parts.append(slot(gbox("Lip", (-RAIL_HALF, 0.0, LIP[0]), (RAIL_HALF, LIP[2], LIP[1])), 2))
    for x in (-RAIL_HALF, RAIL_HALF - 0.006):
        parts.append(slot(gbox("End", (x, 0.0, RAIL_BACK - 0.004), (x + 0.006, RAIL_TOP + 0.01, LIP[1])), 2))
    parts.append(slot(gbox("Tray", (-RAIL_HALF, 0.0, TRAY[0]), (RAIL_HALF, TRAY[2], TRAY[1])), 0))
    parts.append(slot(gbox("TrayLip", (-RAIL_HALF, 0.0, TRAY[0] - 0.008), (RAIL_HALF, TRAY[2] + 0.012, TRAY[0])), 0))
    # The bin: an open box at the right end, its floor on the table.
    x0, x1, z0, z1, top = BIN
    parts.append(slot(gbox("BinFloor", (x0, 0.0, z0), (x1, WALL, z1)), 3))
    parts.append(slot(gbox("BinFront", (x0, 0.0, z1 - WALL), (x1, top, z1)), 3))
    parts.append(slot(gbox("BinBack", (x0, 0.0, z0), (x1, top, z0 + WALL)), 3))
    for x in (x0, x1 - WALL):
        parts.append(slot(gbox("BinSide", (x, 0.0, z0), (x + WALL, top, z1)), 3))
    parts.append(slot(gbox("BinRim", (x0, top - 0.004, z1 - WALL - 0.003), (x1, top, z1 + 0.002)), 2))
    first = parts.pop(0)
    obj = join(first, parts)
    obj.name = "ChordLedge"
    bevel_all(obj, 0.0012, 1)
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/chord_ledge.glb")


os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
brick()
ledge()
