# Builds the theremin on its stand, and writes assets/models/theremin.glb.
#
#     blender --background --python tools/blender/theremin.py
#
# WHAT IT IS FOR
#
# A theremin (docs/spatial_loop.md part two, slice 50, idea #23): one hand near its upright pitch
# antenna is the pitch, nearer is higher, and the other hand's height over its loop is the volume,
# silent at the loop. So it looks like one: a walnut cabinet at waist height on a stand with a
# splayed foot, a brass collar on the cabinet's right end holding the tall chrome pitch rod, and on
# its left end an arm out to the horizontal chrome volume loop. The rings of its pitch guide, the
# lit ring, the bar, the letters, the SCALE switch and the plaque are Theremin's own, drawn round
# this.
#
# Theremin (core/music/theremin.gd) repeats every number below that it places things by (the
# cabinet's top, the rod's place and height, the loop's place and size), so the two agree.
#
# ORIENTATION (see _parts.py)
#
# Godot +Y is Blender +Z and Godot -Z is Blender +Y. Its origin is the middle of the foot, on the
# floor; its front, where you stand, is Godot +Z: Blender -Y. The pitch rod is on the player's
# right (+X), the loop on their left.

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    _flatten, bevel_all, box, clear_scene, export, join, material, report, smooth,
)

# --- In metres, in Godot's terms (y up, z toward you), as Theremin has them. -------------------

FOOT_HALF = (0.26, 0.15)     # the splayed foot's two runners, half their spread and length
POST_RADIUS = 0.022
CABINET_HALF = (0.22, 0.11)  # the cabinet, half its width and depth (Theremin.CABINET)
CABINET_LOW = 0.83           # its underside
DECK_Y = 0.95                # its top (Theremin.DECK_Y)
ROD = (0.2, -0.02)           # the pitch rod's x and z (Theremin.ROD)
ROD_TOP = 1.6                # (Theremin.ROD_TOP)
ROD_RADIUS = 0.006
LOOP = (-0.34, 0.98, 0.0)    # the volume loop's middle (Theremin.LOOP)
LOOP_RADIUS = 0.075          # (Theremin.LOOP_RADIUS)
LOOP_TUBE = 0.005


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


def flat_ring(name, at, major, minor):
    """A torus lying level (its hole upright), at Godot point `at`."""
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=48,
            minor_segments=12, location=g(at), rotation=(0.0, 0.0, 0.0))
    obj = bpy.context.active_object
    obj.name = name
    return _flatten(obj)


def gbox(name, lo, hi, ease=0.0015):
    """A box from Godot-space corners: x, y up, z toward you, its edges eased."""
    size = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    centre = ((lo[0] + hi[0]) * 0.5, -(lo[2] + hi[2]) * 0.5, (lo[1] + hi[1]) * 0.5)
    return bevel_all(box(name, size, centre), ease, 1)


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
    # The foot: two runners front to back, splayed under the cabinet's ends, and a bar between.
    for side in (-1.0, 1.0):
        x = side * FOOT_HALF[0]
        parts.append(slot(gbox("Runner", (x - 0.02, 0.0, -FOOT_HALF[1]), (x + 0.02, 0.03, FOOT_HALF[1]), 0.006), 0))
        # Rubber feet at each runner's ends.
        for z in (-FOOT_HALF[1] + 0.02, FOOT_HALF[1] - 0.02):
            parts.append(slot(rod("Pad", (x, -0.004, z), (x, 0.004, z), 0.018, 16), 3))
    parts.append(slot(gbox("Spreader", (-FOOT_HALF[0], 0.005, -0.02), (FOOT_HALF[0], 0.04, 0.02), 0.006), 0))
    # The post up to the cradle, and the cradle's two arms under the cabinet.
    parts.append(slot(rod("Post", (0, 0.04, 0), (0, CABINET_LOW - 0.03, 0), POST_RADIUS, 24), 0))
    parts.append(slot(rod("Collar", (0, 0.04, 0), (0, 0.1, 0), POST_RADIUS * 1.6, 24), 2))
    parts.append(slot(gbox("Cradle", (-0.15, CABINET_LOW - 0.035, -0.05), (0.15, CABINET_LOW, 0.05), 0.004), 0))
    return parts


def cabinet_parts():
    parts = []
    hx, hz = CABINET_HALF
    # The walnut cabinet, its top a little proud of its sides.
    parts.append(slot(gbox("Cabinet", (-hx, CABINET_LOW, -hz), (hx, DECK_Y - 0.012, hz), 0.006), 1))
    parts.append(slot(gbox("Lid", (-hx - 0.006, DECK_Y - 0.012, -hz - 0.006), (hx + 0.006, DECK_Y, hz + 0.006), 0.003), 1))
    # The brass collar on the right end that the pitch rod stands in, and its insulator.
    parts.append(slot(rod("RodCollar", (ROD[0], DECK_Y, ROD[1]), (ROD[0], DECK_Y + 0.035, ROD[1]), 0.022, 32), 2))
    parts.append(slot(rod("Insulator", (ROD[0], DECK_Y + 0.035, ROD[1]), (ROD[0], DECK_Y + 0.07, ROD[1]), 0.012, 24), 3))
    # The pitch rod, chrome, with a ball at its tip.
    parts.append(slot(rod("PitchRod", (ROD[0], DECK_Y + 0.07, ROD[1]), (ROD[0], ROD_TOP, ROD[1]), ROD_RADIUS, 16), 4))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=ROD_RADIUS * 1.8, location=g((ROD[0], ROD_TOP, ROD[1])),
            segments=16, ring_count=8)
    tip = bpy.context.active_object
    tip.name = "RodTip"
    parts.append(slot(_flatten(tip), 4))
    # The arm off the left end out to the volume loop, its brass knuckle, and the loop itself.
    elbow = (-hx - 0.02, LOOP[1], LOOP[2])
    parts.append(slot(rod("LoopKnuckle", (-hx, LOOP[1], LOOP[2]), elbow, 0.014, 20), 2))
    parts.append(slot(rod("LoopArm", elbow, (LOOP[0] + LOOP_RADIUS, LOOP[1], LOOP[2]), LOOP_TUBE, 12), 4))
    parts.append(slot(flat_ring("VolumeLoop", LOOP, LOOP_RADIUS, LOOP_TUBE), 4))
    return parts


def theremin():
    clear_scene()
    MATS[:] = [material("stand", (0.07, 0.065, 0.06, 1.0), 0.45),
            material("walnut", (0.3, 0.17, 0.09, 1.0), 0.42),
            material("brass", (0.72, 0.55, 0.25, 1.0), 0.3),
            material("rubber", (0.03, 0.03, 0.03, 1.0), 0.8),
            material("chrome", (0.85, 0.86, 0.88, 1.0), 0.15)]
    parts = stand_parts() + cabinet_parts()
    first = parts.pop(0)
    obj = join(first, parts)
    obj.name = "Theremin"
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/theremin.glb")


os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
theremin()
