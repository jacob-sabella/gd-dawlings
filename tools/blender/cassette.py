# Builds a compact cassette and the rack that holds a band's cassettes, and writes
# assets/models/cassette.glb and assets/models/cassette_rack.glb.
#
#     blender --background --python tools/blender/cassette.py
#
# WHAT THEY ARE FOR
#
# A clip pulled out of the timeline is a cassette in your hand (docs/spatial_loop.md part two,
# slice 23, idea #4): carried, thrown, handed over, and shelved in the rack beside the prop shelf,
# a clipboard you can see. The cassette is the real size, 100 x 64 x 12 mm, so it reads as one in
# a hand at once: the shell, a paper label across both faces with the window through it, the two
# hubs and the tape wound on them, five screws, and the head opening along the bottom edge. Its
# label is left blank: CassetteItem letters it with the clip's name, its track and its length.
#
# The rack is a display stand, face out, like a shop's: twelve ledges in three columns of four,
# a tray under them where a cassette with nowhere else to be lies, and the BIN under that, an open
# box a cassette is dropped in to retire it. A cabinet front under the bin carries the plaque.
# CassetteRack repeats every number below (slot poses, the tray, the bin), so the two agree.
#
# ORIENTATION (see _parts.py)
#
# Godot +Y is Blender +Z and Godot -Z is Blender +Y. Each part's origin is the middle of its
# bottom. The cassette stands on its long edge, its A side toward Godot -Z (an item's front) and
# its B side toward +Z, both labelled. The rack's front, where you stand, is Godot +Z: Blender -Y.

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    bevel_all, box, clear_scene, cylinder, export, join, material, report, smooth,
)

# --- The cassette, in metres. ----------------------------------------------------------------

WIDTH = 0.100
HEIGHT = 0.064
THICK = 0.012
LABEL = (0.086, 0.036)
LABEL_Z = 0.040
WINDOW = (0.046, 0.014)
WINDOW_Z = 0.037
HUB_X = 0.0205
TAPE_RADIUS = 0.0066
HUB_RADIUS = 0.0040
HEAD = (0.060, 0.009)
SCREWS = [(-0.044, 0.006), (0.044, 0.006), (-0.044, 0.058), (0.044, 0.058), (0.0, 0.054)]

# --- The rack, in metres, in Godot's terms (y up, z toward you), as CassetteRack has them. ----

RACK_HALF = 0.21
RACK_DEPTH = 0.20
RACK_TOP = 1.50
SIDE = 0.02
COLS = [-0.125, 0.0, 0.125]
ROWS = [1.335, 1.235, 1.135, 1.035]
LEDGE = 0.012
LEDGE_BACK = -0.085
LEDGE_FRONT = -0.040
TRAY_Y = 0.90
BIN = (0.45, 0.72)
BIN_HALF = 0.18
BIN_BACK = -0.085
BIN_FRONT = 0.090
WALL = 0.010
CABINET = (0.04, 0.44)


def gbox(name, lo, hi):
    """A box from Godot-space corners: x, y up, z toward you."""
    size = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    centre = ((lo[0] + hi[0]) * 0.5, -(lo[2] + hi[2]) * 0.5, (lo[1] + hi[1]) * 0.5)
    return box(name, size, centre)


# The materials of whatever is being built: every part carries all of them, in this order, so
# the join keeps each part's faces on its own (a face's index past its object's slots is lost).
MATS = []


def slot(obj, index):
    obj.data.materials.clear()
    for m in MATS:
        obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = index
    return obj


def cassette():
    clear_scene()
    MATS[:] = [material("shell", (0.06, 0.06, 0.07, 1.0), 0.35),
            material("label", (0.92, 0.88, 0.76, 1.0), 0.8),
            material("window", (0.10, 0.09, 0.08, 1.0), 0.15),
            material("tape", (0.24, 0.13, 0.06, 1.0), 0.5),
            material("hub", (0.95, 0.95, 0.93, 1.0), 0.4),
            material("screw", (0.6, 0.6, 0.62, 1.0), 0.3)]
    shell = box("Cassette", (WIDTH, THICK, HEIGHT), (0.0, 0.0, HEIGHT * 0.5))
    bevel_all(shell, 0.0016, 2)
    slot(shell, 0)
    parts = []
    for side in (-1.0, 1.0):
        face = side * THICK * 0.5
        parts.append(slot(box("Label", (LABEL[0], 0.0006, LABEL[1]),
                (0.0, face + side * 0.0003, LABEL_Z)), 1))
        parts.append(slot(box("Window", (WINDOW[0], 0.0006, WINDOW[1]),
                (0.0, face + side * 0.0005, WINDOW_Z)), 2))
        for x in (-HUB_X, HUB_X):
            parts.append(slot(cylinder("Tape", TAPE_RADIUS, 0.0004, (x, face + side * 0.0008, WINDOW_Z),
                    "Y", 28), 3))
            parts.append(slot(cylinder("Hub", HUB_RADIUS, 0.0004, (x, face + side * 0.0011, WINDOW_Z),
                    "Y", 6), 4))
        for x, z in SCREWS:
            parts.append(slot(cylinder("Screw", 0.0017, 0.0004, (x, face + side * 0.0002, z), "Y", 10), 5))
    # The head opening: a raised lip along the bottom edge, where the tape crosses.
    parts.append(slot(box("Head", (HEAD[0], THICK + 0.0012, HEAD[1]), (0.0, 0.0, HEAD[1] * 0.5)), 0))
    obj = join(shell, parts)
    obj.name = "Cassette"
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/cassette.glb")


def rack():
    clear_scene()
    MATS[:] = [material("wood", (0.33, 0.21, 0.12, 1.0), 0.55),
            material("felt", (0.10, 0.12, 0.10, 1.0), 0.95),
            material("metal", (0.62, 0.60, 0.56, 1.0), 0.3),
            material("bin", (0.16, 0.16, 0.17, 1.0), 0.6)]
    parts = []
    for x in (-RACK_HALF + SIDE * 0.5, RACK_HALF - SIDE * 0.5):
        parts.append(slot(gbox("Side", (x - SIDE * 0.5, 0.0, -RACK_DEPTH * 0.5),
                (x + SIDE * 0.5, RACK_TOP, RACK_DEPTH * 0.5)), 0))
    inner = RACK_HALF - SIDE
    parts.append(slot(gbox("Top", (-RACK_HALF, RACK_TOP - 0.02, -RACK_DEPTH * 0.5),
            (RACK_HALF, RACK_TOP, RACK_DEPTH * 0.5)), 0))
    parts.append(slot(gbox("Back", (-inner, 0.04, -RACK_DEPTH * 0.5),
            (inner, RACK_TOP - 0.02, LEDGE_BACK)), 1))
    for y in ROWS + [TRAY_Y]:
        parts.append(slot(gbox("Ledge", (-inner, y - LEDGE, LEDGE_BACK), (inner, y, LEDGE_FRONT)), 0))
        parts.append(slot(gbox("Lip", (-inner, y - LEDGE, LEDGE_FRONT), (inner, y + 0.012, LEDGE_FRONT + 0.004)), 2))
    # The bin: an open box, its floor a little above the cabinet.
    parts.append(slot(gbox("BinFloor", (-BIN_HALF, BIN[0], BIN_BACK), (BIN_HALF, BIN[0] + WALL, BIN_FRONT)), 3))
    parts.append(slot(gbox("BinFront", (-BIN_HALF, BIN[0], BIN_FRONT - WALL), (BIN_HALF, BIN[1], BIN_FRONT)), 3))
    for x in (-BIN_HALF, BIN_HALF - WALL):
        parts.append(slot(gbox("BinSide", (x, BIN[0], BIN_BACK), (x + WALL, BIN[1], BIN_FRONT)), 3))
    parts.append(slot(gbox("BinRim", (-BIN_HALF, BIN[1] - 0.006, BIN_FRONT - WALL - 0.004),
            (BIN_HALF, BIN[1], BIN_FRONT + 0.002)), 2))
    # The cabinet under the bin, whose front carries the plaque, and the plinth it stands on.
    parts.append(slot(gbox("Cabinet", (-inner, CABINET[0], RACK_DEPTH * 0.5 - 0.012),
            (inner, CABINET[1], RACK_DEPTH * 0.5)), 0))
    parts.append(slot(gbox("Plinth", (-RACK_HALF, 0.0, -RACK_DEPTH * 0.5), (RACK_HALF, CABINET[0], RACK_DEPTH * 0.5)), 3))
    first = parts.pop(0)
    obj = join(first, parts)
    obj.name = "CassetteRack"
    bevel_all(obj, 0.0015, 1)
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/cassette_rack.glb")


os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
cassette()
rack()
