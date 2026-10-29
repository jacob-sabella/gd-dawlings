# Builds the music box on its plinth, and writes assets/models/music_box.glb.
#
#     blender --background --python tools/blender/music_box.py
#
# WHAT IT IS FOR
#
# A music-box sequencer (docs/spatial_loop.md part two, slice 47, idea #15): a brass cylinder of
# sixteen steps round by eight rows across, turning past a steel comb, its pegs a pattern that plays a
# track as ordinary MIDI. So it looks like a music box's works set out on a wooden case: a plinth to
# stand at, a base board on it, two brass cheeks holding the cylinder's axle, the comb's steel block
# behind the cylinder with its plate reaching forward over the top, a back wall and the lid hinged
# open behind, its felt facing whoever stands in front. The cylinder, its pegs, the comb's teeth (they
# flick), the row names and the keys are MusicBox's own (they turn, change and are pressed); this is
# everything that does not.
#
# MusicBox (core/music/music_box.gd) repeats every number below that it places things by (the deck's
# height, the axis, the cylinder's radius and length, the comb's root, the lid's hinge), so the two
# agree.
#
# ORIENTATION (see _parts.py)
#
# Godot +Y is Blender +Z and Godot -Z is Blender +Y. Its origin is the middle of the plinth's foot,
# on the floor; its front, where you stand, is Godot +Z: Blender -Y.

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    _flatten, bevel_all, box, clear_scene, export, join, material, report, smooth,
)

# --- In metres, in Godot's terms (y up, z toward you), as MusicBox has them. ------------------

FOOT = (0.3, 0.22)       # half the footprint: x, z
FOOT_Z = -0.02           # the footprint's middle along z
SKIRT = 0.05             # the dark kick at the floor
DECK_Y = 0.88            # the base board's top
BASE = 0.04              # the base board's thickness
AXIS = (0.0, 1.0, -0.03)  # the cylinder's axle, across x
RADIUS = 0.095           # the cylinder's
HALF = 0.18              # half the cylinder's length
CHEEK = (0.006, 0.03)    # a cheek's gap from the cylinder's end, and its thickness
COMB_BLOCK = (-0.19, 0.15, -0.205, -0.135, 1.09)   # x0, x1, z0, z1, top
COMB_ROOT_Z = -0.11      # where the plate ends and the teeth begin
PLATE = 0.008            # the comb plate's thickness
BACK_TALL = 1.12         # the back wall's top: the lid's hinge
LID = (0.44, 0.02, 0.06)  # its length, thickness, and lean back from straight up (radians)


def g(p):
    """A point in Godot's terms as Blender has it."""
    return Vector((p[0], -p[2], p[1]))


def gbox(name, lo, hi, ease=0.0015):
    """A box from Godot-space corners: x, y up, z toward you, its edges eased."""
    size = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    centre = ((lo[0] + hi[0]) * 0.5, -(lo[2] + hi[2]) * 0.5, (lo[1] + hi[1]) * 0.5)
    return bevel_all(box(name, size, centre), ease, 1)


def rod(name, a, b, radius, vertices=20):
    """A cylinder from Godot point `a` to `b`."""
    a = g(a)
    b = g(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=d.length,
            location=(a + b) * 0.5, rotation=d.to_track_quat("Z", "Y").to_euler())
    obj = bpy.context.active_object
    obj.name = name
    return _flatten(obj)


MATS = []


def metal(name, colour, roughness, metallic):
    """A material that is metal: _parts.material sets only the colour and the roughness, so without
    Metallic the brass cheeks look like pale wood and the comb's steel like white plastic. MusicBox's
    own brass and comb steel are metallic too, so the case's metal matches what it holds."""
    mat = material(name, colour, roughness)
    principled = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    if "Metallic" in principled.inputs:
        principled.inputs["Metallic"].default_value = metallic
    return mat


def slot(obj, index):
    obj.data.materials.clear()
    for m in MATS:
        obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = index
    return obj


def case_parts():
    fx, fz = FOOT
    z0 = FOOT_Z - fz
    z1 = FOOT_Z + fz
    parts = []
    # The plinth, a little in from the footprint, on a dark kick.
    parts.append(slot(gbox("Skirt", (-fx, 0.0, z0), (fx, SKIRT, z1), 0.003), 2))
    parts.append(slot(gbox("Plinth", (-fx + 0.02, SKIRT, z0 + 0.02), (fx - 0.02, DECK_Y - BASE, z1 - 0.02), 0.004), 0))
    parts.append(slot(gbox("Base", (-fx, DECK_Y - BASE, z0), (fx, DECK_Y, z1), 0.004), 0))
    # The back wall the lid hinges on.
    parts.append(slot(gbox("BackWall", (-fx, DECK_Y, z0), (fx, BACK_TALL, z0 + 0.02), 0.003), 0))
    return parts


def works_parts():
    parts = []
    ax, ay, az = AXIS
    gap, thick = CHEEK
    # The two cheeks holding the axle, brass, standing on the base board either end of the cylinder.
    for side in (-1.0, 1.0):
        inner = side * (HALF + gap)
        outer = side * (HALF + gap + thick)
        lo_x, hi_x = min(inner, outer), max(inner, outer)
        parts.append(slot(gbox("Cheek", (lo_x, DECK_Y, az - 0.05), (hi_x, ay + 0.03, az + 0.05), 0.004), 1))
        parts.append(slot(rod("Boss", (outer, ay, az), (outer + side * 0.008, ay, az), 0.018), 1))
    parts.append(slot(rod("Axle", (-(HALF + gap + thick), ay, az), (HALF + gap + thick, ay, az), 0.006), 3))
    # The comb's block behind the cylinder, steel, and its plate reaching forward over the top, where
    # the teeth (MusicBox's) begin.
    x0, x1, cz0, cz1, top = COMB_BLOCK
    parts.append(slot(gbox("CombBlock", (x0, DECK_Y, cz0), (x1, top, cz1), 0.003), 3))
    parts.append(slot(gbox("CombPlate", (x0, top, cz0), (x1, top + PLATE, COMB_ROOT_Z), 0.002), 3))
    # Two screws on the plate.
    for x in (x0 + 0.03, x1 - 0.03):
        parts.append(slot(rod("Screw", (x, top + PLATE, (cz0 + COMB_ROOT_Z) * 0.5),
                (x, top + PLATE + 0.003, (cz0 + COMB_ROOT_Z) * 0.5), 0.006, 12), 1))
    return parts


def lid_parts():
    fx, fz = FOOT
    z0 = FOOT_Z - fz
    length, thick, lean = LID
    # Made upright at the hinge, then leant back about it.
    parts = []
    lid = gbox("Lid", (-fx, 0.0, -thick), (fx, length, 0.0), 0.003)
    felt = gbox("Felt", (-fx + 0.025, 0.025, 0.0), (fx - 0.025, length - 0.025, 0.003), 0.001)
    for obj, index in ((lid, 0), (felt, 4)):
        slot(obj, index)
        # Godot's lean back about x (top toward -z) is Blender's rotation about x toward +y.
        obj.rotation_euler = (-lean, 0.0, 0.0)
        obj.location = g((0.0, BACK_TALL, z0 + thick))
        _flatten(obj)
        parts.append(obj)
    return parts


def music_box():
    clear_scene()
    MATS[:] = [material("walnut", (0.2, 0.11, 0.06, 1.0), 0.45),
            metal("brass", (0.78, 0.58, 0.26, 1.0), 0.4, 0.85),
            material("kick", (0.05, 0.04, 0.035, 1.0), 0.7),
            metal("steel", (0.62, 0.63, 0.66, 1.0), 0.3, 0.9),
            material("felt", (0.16, 0.05, 0.06, 1.0), 0.95)]
    parts = case_parts() + works_parts() + lid_parts()
    first = parts.pop(0)
    obj = join(first, parts)
    obj.name = "MusicBox"
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/music_box.glb")


os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
music_box()
