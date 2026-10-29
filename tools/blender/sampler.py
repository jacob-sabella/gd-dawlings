# Builds the sampler station beside the cassette rack, and writes assets/models/sampler.glb.
#
#     blender --background --python tools/blender/sampler.py
#
# WHAT IT IS FOR
#
# Anything can be a sample (docs/spatial_loop.md part two, slice 26, idea #12): press REC, then
# squeeze the duck or hit the tambourine near the mic, and the sound it made is a WAV in the
# project's media and a sample cassette on the rack beside it. So it looks like what it does: a
# small pad bank on a cabinet the height of a table, eight rubber pads and a round REC key on its
# deck, a little screen along the back that says what it is listening for, and a microphone on a
# gooseneck bent forward over the pads, toward whoever stands at it. The REC key's cap and the
# screen's lettering are Sampler's own (they light and change); this is everything that does not.
#
# Sampler repeats every number below that it places things by (the deck, the screen, the REC
# key's seat, the mic's head), so the two agree.
#
# ORIENTATION (see _parts.py)
#
# Godot +Y is Blender +Z and Godot -Z is Blender +Y. Its origin is the middle of its foot; its
# front, where you stand, is Godot +Z: Blender -Y.

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    _flatten, bevel_all, box, clear_scene, export, join, material, report, smooth,
)

# --- In metres, in Godot's terms (y up, z toward you), as Sampler has them. -------------------

PLINTH = (0.19, 0.04, 0.15)        # half x, height, half z
CABINET = (0.17, 0.86, 0.13)       # half x, top, half z
DECK = (0.20, 0.92, 0.15)          # half x, top, half z
PAD = 0.055
PAD_TALL = 0.012
PAD_COLS = [-0.1475, -0.0825, -0.0175, 0.0475]
PAD_ROWS = [-0.02, 0.045]
SCREEN = (0.18, 1.0, -0.15, -0.13)  # half x, top, back z, front z
REC_SEAT = (0.13, 0.04, 0.036)      # x, z, radius
NECK_BASE = (-0.16, 1.0, -0.14)     # x, y, z: on the screen's top, at its left end
NECK_RISE = 1.18
NECK_ARC = 0.14
NECK_END_DEGREES = 50.0
NECK_RADIUS = 0.006
MIC_RADIUS = 0.02
MIC_LONG = 0.06


def g(p):
    """A point in Godot's terms as Blender has it."""
    return Vector((p[0], -p[2], p[1]))


def gbox(name, lo, hi):
    """A box from Godot-space corners: x, y up, z toward you, its edges eased. Only the boxes: a
    bevel over the round parts' every edge would make the file ten times the size for nothing."""
    size = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    centre = ((lo[0] + hi[0]) * 0.5, -(lo[2] + hi[2]) * 0.5, (lo[1] + hi[1]) * 0.5)
    return bevel_all(box(name, size, centre), 0.0012, 1)


def rod(name, a, b, radius, vertices=12):
    """A cylinder from Godot point `a` to `b`."""
    a = g(a)
    b = g(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=d.length,
            location=(a + b) * 0.5, rotation=d.to_track_quat("Z", "Y").to_euler())
    obj = bpy.context.active_object
    obj.name = name
    return _flatten(obj)


def ball(name, at, radius):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=radius, location=g(at))
    obj = bpy.context.active_object
    obj.name = name
    return _flatten(obj)


MATS = []


def slot(obj, index):
    obj.data.materials.clear()
    for m in MATS:
        obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = index
    return obj


def neck_points():
    """The gooseneck as Godot points: straight up from its base, then bent forward over the pads."""
    x, y, z = NECK_BASE
    points = [(x, y, z), (x, NECK_RISE, z)]
    centre = (z + NECK_ARC, NECK_RISE)
    steps = 12
    for k in range(1, steps + 1):
        theta = math.radians(180.0 - (180.0 - NECK_END_DEGREES) * k / steps)
        points.append((x, centre[1] + NECK_ARC * math.sin(theta), centre[0] + NECK_ARC * math.cos(theta)))
    return points


def sampler():
    clear_scene()
    MATS[:] = [material("wood", (0.30, 0.19, 0.11, 1.0), 0.55),
            material("panel", (0.09, 0.09, 0.10, 1.0), 0.45),
            material("pad", (0.55, 0.55, 0.52, 1.0), 0.9),
            material("metal", (0.66, 0.64, 0.60, 1.0), 0.3),
            material("glass", (0.03, 0.04, 0.04, 1.0), 0.12),
            material("grille", (0.18, 0.18, 0.19, 1.0), 0.5)]
    parts = []
    parts.append(slot(gbox("Plinth", (-PLINTH[0], 0.0, -PLINTH[2]), (PLINTH[0], PLINTH[1], PLINTH[2])), 1))
    parts.append(slot(gbox("Cabinet", (-CABINET[0], PLINTH[1], -CABINET[2]),
            (CABINET[0], CABINET[1], CABINET[2])), 0))
    parts.append(slot(gbox("Deck", (-DECK[0], CABINET[1], -DECK[2]), (DECK[0], DECK[1], DECK[2])), 1))
    for x in PAD_COLS:
        for z in PAD_ROWS:
            parts.append(slot(gbox("Pad", (x - PAD * 0.5, DECK[1], z - PAD * 0.5),
                    (x + PAD * 0.5, DECK[1] + PAD_TALL, z + PAD * 0.5)), 2))
    parts.append(slot(gbox("Screen", (-SCREEN[0], DECK[1], SCREEN[2]), (SCREEN[0], SCREEN[1], SCREEN[3])), 4))
    parts.append(slot(gbox("ScreenRim", (-SCREEN[0] - 0.006, SCREEN[1] - 0.004, SCREEN[2] - 0.003),
            (SCREEN[0] + 0.006, SCREEN[1] + 0.004, SCREEN[3] + 0.002)), 1))
    # The REC key's seat: a metal ring proud of the deck, the cap (Sampler's) sits in it.
    parts.append(slot(rod("RecSeat", (REC_SEAT[0], DECK[1], REC_SEAT[1]), (REC_SEAT[0], DECK[1] + 0.004, REC_SEAT[1]),
            REC_SEAT[2], 32), 3))
    # The gooseneck: a collar on the screen's top, then the neck, its joints rounded.
    x, y, z = NECK_BASE
    parts.append(slot(rod("Collar", (x, y, z), (x, y + 0.02, z), NECK_RADIUS * 2.2, 16), 3))
    points = neck_points()
    for a, b in zip(points, points[1:]):
        parts.append(slot(rod("Neck", a, b, NECK_RADIUS), 3))
        parts.append(slot(ball("Joint", b, NECK_RADIUS), 3))
    # The mic: a body along the neck's last stretch, its grille a ball at its head.
    end = Vector(points[-1])
    way = (end - Vector(points[-2])).normalized()
    head = end + way * MIC_LONG
    parts.append(slot(rod("MicBody", tuple(end), tuple(head), MIC_RADIUS * 0.8, 20), 3))
    parts.append(slot(ball("Grille", tuple(head), MIC_RADIUS), 5))
    print("mic head at x %.4f y %.4f z %.4f" % (head.x, head.y, head.z))
    first = parts.pop(0)
    obj = join(first, parts)
    obj.name = "Sampler"
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/sampler.glb")


os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
sampler()
