# Builds the DJ platter on the tape deck's cart, and writes assets/models/platter.glb (what stands
# still) and assets/models/platter_disc.glb (what turns).
#
#     blender --background --python tools/blender/platter.py
#
# WHAT IT IS FOR
#
# A DJ platter (docs/spatial_loop.md part two, slice 27, idea #17): a turntable whose label turns
# with the song, a turn a bar. Bare it is the playhead: turn it to scrub, hold it to stop, flick it
# back to spin back. A cassette stood in the slot beside it is scratched instead, in its player's
# ears alone. So it looks like a turntable first: a low plinth on rubber feet with a brushed top, a
# heavy platter with strobe dots round its rim, a rubber mat and a paper label with a stripe across
# it, so the turning is seen from across the room; a tonearm parked over the record at the back,
# and at the front right a slot housing a cassette stands up in. The lettering along the plinth's
# front and the cassette are Platter's own; this is everything that does not change.
#
# Platter repeats every number below that it places things by (the axis, the disc's top, the slot,
# the front), so the two agree.
#
# ORIENTATION (see _parts.py)
#
# Godot +Y is Blender +Z and Godot -Z is Blender +Y. The body's origin is the middle of its foot
# on the cart's leaf; its front, where you stand, is Godot +Z: Blender -Y. The disc's origin is the
# platter's axis at its underside.

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    _flatten, bevel_all, box, clear_scene, export, join, material, report, smooth,
)

# --- In metres, in Godot's terms (y up, z toward you), as Platter has them. -------------------

PLINTH = (0.17, 0.008, 0.05, 0.16)     # half x, bottom, top, half z
FEET = (0.14, 0.13, 0.016)             # x, z, radius
PLATE = 0.053                          # the brushed top's top
AXIS = (-0.04, 0.0)                    # x, z of the platter's axis
BEARING = (0.125, 0.056)               # radius, top: what the disc sits on
TONEARM = (0.13, -0.115)               # x, z of its pivot
ARM_Y = 0.08
ARM_REST = (0.04, -0.035)              # where the headshell is parked, over the record's edge
SLOT = (0.06, 0.17, 0.086, 0.114, 0.075)  # x from, x to, z from, z to, its top

RIM = (0.12, 0.010)                    # the platter's radius and height, in the disc's frame
MAT = (0.108, 0.013)
LABEL = (0.045, 0.0135)
DOTS = 16


def g(p):
    """A point in Godot's terms as Blender has it."""
    return Vector((p[0], -p[2], p[1]))


def gbox(name, lo, hi, bevel=0.0012):
    """A box from Godot-space corners: x, y up, z toward you, its edges eased."""
    size = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    centre = ((lo[0] + hi[0]) * 0.5, -(lo[2] + hi[2]) * 0.5, (lo[1] + hi[1]) * 0.5)
    return bevel_all(box(name, size, centre), bevel, 1)


def rod(name, a, b, radius, vertices=16):
    """A cylinder from Godot point `a` to `b`."""
    a = g(a)
    b = g(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=d.length,
            location=(a + b) * 0.5, rotation=d.to_track_quat("Z", "Y").to_euler())
    obj = bpy.context.active_object
    obj.name = name
    return _flatten(obj)


def disc(name, x, z, radius, y0, y1, vertices=64):
    """An upright cylinder at Godot (x, z), from height y0 to y1."""
    return rod(name, (x, y0, z), (x, y1, z), radius, vertices)


MATS = []


def slot(obj, index):
    obj.data.materials.clear()
    for m in MATS:
        obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = index
    return obj


def body():
    clear_scene()
    MATS[:] = [material("plinth", (0.035, 0.032, 0.03, 1.0), 0.45),
            material("plate", (0.40, 0.40, 0.39, 1.0), 0.38),
            material("rubber", (0.03, 0.03, 0.03, 1.0), 0.9),
            material("metal", (0.75, 0.74, 0.70, 1.0), 0.22),
            material("slot", (0.01, 0.01, 0.012, 1.0), 0.8)]
    parts = []
    hx, bottom, top, hz = PLINTH
    parts.append(slot(gbox("Plinth", (-hx, bottom, -hz), (hx, top, hz), 0.004), 0))
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            parts.append(slot(disc("Foot", sx * FEET[0], sz * FEET[1], FEET[2], 0.0, bottom, 24), 2))
    parts.append(slot(gbox("Plate", (-hx + 0.005, top, -hz + 0.005), (hx - 0.005, PLATE, hz - 0.005), 0.001), 1))
    parts.append(slot(disc("Bearing", AXIS[0], AXIS[1], BEARING[0], PLATE, BEARING[1]), 2))
    # The tonearm, parked: its base, its post, the arm out over the record's edge and a headshell,
    # a counterweight behind the pivot.
    px, pz = TONEARM
    parts.append(slot(disc("ArmBase", px, pz, 0.018, PLATE, PLATE + 0.012, 32), 3))
    parts.append(slot(disc("ArmPost", px, pz, 0.005, PLATE + 0.012, ARM_Y + 0.004, 16), 3))
    parts.append(slot(rod("Arm", (px, ARM_Y, pz), (ARM_REST[0], ARM_Y, ARM_REST[1]), 0.003), 3))
    way = (Vector((ARM_REST[0], ARM_REST[1])) - Vector((px, pz))).normalized()
    back = Vector((px, pz)) - way * 0.03
    parts.append(slot(rod("Weight", (back.x, ARM_Y, back.y), (px - way.x * 0.012, ARM_Y, pz - way.y * 0.012), 0.009, 24), 3))
    hx0, hz0 = ARM_REST
    parts.append(slot(gbox("Headshell", (hx0 - 0.008, ARM_Y - 0.006, hz0 - 0.012), (hx0 + 0.008, ARM_Y + 0.002, hz0 + 0.004), 0.001), 2))
    # The cassette's slot: a housing at the front right, its opening black.
    x0, x1, z0, z1, slot_top = SLOT
    parts.append(slot(gbox("SlotHousing", (x0, PLATE, z0), (x1, slot_top, z1), 0.002), 0))
    parts.append(slot(gbox("SlotOpening", (x0 + 0.004, slot_top, z0 + 0.007), (x1 - 0.004, slot_top + 0.0006, z1 - 0.007), 0.0002), 4))
    first = parts.pop(0)
    obj = join(first, parts)
    obj.name = "Platter"
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/platter.glb")


def turning():
    clear_scene()
    MATS[:] = [material("rim", (0.70, 0.70, 0.68, 1.0), 0.25),
            material("mat", (0.025, 0.025, 0.028, 1.0), 0.85),
            material("label", (0.88, 0.80, 0.62, 1.0), 0.7),
            material("stripe", (0.55, 0.08, 0.06, 1.0), 0.6),
            material("dot", (0.96, 0.96, 0.94, 1.0), 0.4)]
    parts = []
    parts.append(slot(disc("Rim", 0.0, 0.0, RIM[0], 0.0, RIM[1], 96), 0))
    parts.append(slot(disc("Mat", 0.0, 0.0, MAT[0], RIM[1], MAT[1], 96), 1))
    parts.append(slot(disc("Label", 0.0, 0.0, LABEL[0], MAT[1], LABEL[1], 64), 2))
    # The stripe across the label, from the spindle to its edge at the back (the angle the platter
    # counts from): what says how far it has turned.
    parts.append(slot(gbox("Stripe", (-0.003, LABEL[1], -LABEL[0] + 0.002), (0.003, LABEL[1] + 0.0004, -0.007), 0.0001), 3))
    parts.append(slot(disc("Spindle", 0.0, 0.0, 0.0035, LABEL[1], LABEL[1] + 0.009, 16), 0))
    # Strobe dots round the rim, outside the mat: the turning seen from across the room.
    for k in range(DOTS):
        a = 2.0 * math.pi * k / DOTS
        r = (MAT[0] + RIM[0]) * 0.5
        parts.append(slot(disc("Dot", r * math.sin(a), -r * math.cos(a), 0.003, RIM[1], RIM[1] + 0.0006, 10), 4))
    first = parts.pop(0)
    obj = join(first, parts)
    obj.name = "PlatterDisc"
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/platter_disc.glb")


os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
body()
turning()
