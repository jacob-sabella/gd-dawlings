# Builds the string spool on its stand, and writes assets/models/string_spool.glb.
#
#     blender --background --python tools/blender/string_spool.py
#
# WHAT IT IS FOR
#
# A string across the room (docs/spatial_loop.md part two, slice 48, idea #34): take an end off the
# spool, tie it anywhere, carry it to anywhere else and tie it there, and its length is its note. So
# it looks like a bobbin of string on a spinning-wheel's stand: a round weighted foot, a turned post,
# a yoke at hand height holding an axle, and on it a wooden bobbin between two flanges, wound full of
# string, with a brass eyelet in front of the bobbin that the loose end hangs out of. The wound string
# is its own material (`wound`), so RoomString can light it; the bobbin, its axle, the eyelet and the
# plaque's arm are what RoomString.Spool does not change.
#
# RoomString (core/music/room_string.gd) repeats every number below that it places things by (the
# axle's height, the bobbin's size, the eyelet's place, the plaque's arm), so the two agree.
#
# ORIENTATION (see _parts.py)
#
# Godot +Y is Blender +Z and Godot -Z is Blender +Y. Its origin is the middle of the foot, on the
# floor; its front, where you stand, is Godot +Z: Blender -Y.

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    _flatten, bevel_all, box, clear_scene, export, join, material, report, smooth,
)

# --- In metres, in Godot's terms (y up, z toward you), as RoomString has them. ----------------

FOOT_RADIUS = 0.16       # the weighted foot's radius
FOOT_TALL = 0.035
POST_RADIUS = 0.017
AXLE_Y = 1.0             # the bobbin's axle (RoomString.SPOOL_AXLE)
YOKE_X = 0.085           # the yoke's two arms either side of the bobbin
BOBBIN_RADIUS = 0.085    # the flanges (RoomString.SPOOL_RADIUS)
BOBBIN_HALF = 0.07       # half its length along the axle, flange to flange
FLANGE = 0.012
DRUM_RADIUS = 0.032      # the bobbin's core, under the wound string
WOUND_RADIUS = 0.066     # how full it is wound
EYELET = (0.0, 0.93, 0.105)  # the brass eyelet the end hangs from (RoomString.SPOOL_EYELET)
ARM_Y = 0.62             # the plaque's arm off the post's front (RoomString.SPOOL_PLAQUE)


def g(p):
    """A point in Godot's terms as Blender has it."""
    return Vector((p[0], -p[2], p[1]))


def rod(name, a, b, radius, vertices=24):
    """A cylinder from Godot point `a` to `b`."""
    a = g(a)
    b = g(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=d.length,
            location=(a + b) * 0.5, rotation=d.to_track_quat("Z", "Y").to_euler())
    obj = bpy.context.active_object
    obj.name = name
    return _flatten(obj)


def ring(name, at, major, minor):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=24,
            minor_segments=10, location=g(at), rotation=(0.0, 0.0, 0.0))
    obj = bpy.context.active_object
    obj.name = name
    # Its hole facing the player: turned up off the floor's plane into the front's.
    obj.rotation_euler = (math.pi / 2, 0.0, 0.0)
    return _flatten(obj)


MATS = []


def slot(obj, index):
    obj.data.materials.clear()
    for m in MATS:
        obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = index
    return obj


def stand_parts():
    parts = []
    # The foot: a turned disc with a rounded edge, and a collar where the post goes in.
    parts.append(slot(bevel_all(rod("Foot", (0, 0, 0), (0, FOOT_TALL, 0), FOOT_RADIUS, 48), 0.008, 2), 0))
    parts.append(slot(rod("Collar", (0, FOOT_TALL, 0), (0, FOOT_TALL + 0.04, 0), POST_RADIUS * 2.0, 32), 0))
    # The post, up to the yoke's crossbar under the bobbin.
    cross_y = AXLE_Y - BOBBIN_RADIUS - 0.03
    parts.append(slot(rod("Post", (0, FOOT_TALL, 0), (0, cross_y, 0), POST_RADIUS, 24), 0))
    # The yoke: a crossbar and two arms up either side of the bobbin to the axle.
    parts.append(slot(gbox("Crossbar", (-YOKE_X - 0.012, cross_y - 0.014, -0.014),
            (YOKE_X + 0.012, cross_y + 0.014, 0.014)), 0))
    for side in (-1.0, 1.0):
        x = side * YOKE_X
        parts.append(slot(gbox("Arm", (x - 0.008, cross_y, -0.014), (x + 0.008, AXLE_Y + 0.02, 0.014)), 0))
    # The axle through them, brass, proud of each arm.
    parts.append(slot(rod("Axle", (-YOKE_X - 0.02, AXLE_Y, 0), (YOKE_X + 0.02, AXLE_Y, 0), 0.006, 16), 2))
    # The eyelet's stalk off the crossbar's front, and the brass ring the end hangs through.
    parts.append(slot(rod("Stalk", (0, cross_y, 0.014), (EYELET[0], EYELET[1] - 0.012, EYELET[2]), 0.004, 12), 2))
    parts.append(slot(ring("Eyelet", EYELET, 0.011, 0.0025), 2))
    # The plaque's arm off the post's front, the plate's back stood on it.
    parts.append(slot(rod("PlaqueArm", (0, ARM_Y, 0), (0, ARM_Y, 0.04), 0.008, 12), 2))
    return parts


def gbox(name, lo, hi, ease=0.0015):
    """A box from Godot-space corners: x, y up, z toward you, its edges eased."""
    size = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    centre = ((lo[0] + hi[0]) * 0.5, -(lo[2] + hi[2]) * 0.5, (lo[1] + hi[1]) * 0.5)
    return bevel_all(box(name, size, centre), ease, 1)


def bobbin_parts():
    parts = []
    for side in (-1.0, 1.0):
        x0 = side * (BOBBIN_HALF - FLANGE)
        x1 = side * BOBBIN_HALF
        parts.append(slot(bevel_all(rod("Flange", (x0, AXLE_Y, 0), (x1, AXLE_Y, 0), BOBBIN_RADIUS, 40), 0.003, 1), 1))
    parts.append(slot(rod("Drum", (-BOBBIN_HALF + FLANGE, AXLE_Y, 0), (BOBBIN_HALF - FLANGE, AXLE_Y, 0),
            DRUM_RADIUS, 32), 1))
    # The string wound on it, a little short of the flanges' rims.
    parts.append(slot(rod("Wound", (-BOBBIN_HALF + FLANGE + 0.001, AXLE_Y, 0),
            (BOBBIN_HALF - FLANGE - 0.001, AXLE_Y, 0), WOUND_RADIUS, 40), 3))
    return parts


def spool():
    clear_scene()
    MATS[:] = [material("stand", (0.18, 0.11, 0.06, 1.0), 0.5),
            material("bobbin", (0.55, 0.37, 0.2, 1.0), 0.45),
            material("brass", (0.72, 0.55, 0.25, 1.0), 0.3),
            material("wound", (0.86, 0.8, 0.66, 1.0), 0.7)]
    parts = stand_parts() + bobbin_parts()
    first = parts.pop(0)
    obj = join(first, parts)
    obj.name = "StringSpool"
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/string_spool.glb")


os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
spool()
