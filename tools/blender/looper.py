# Builds the looper on its stand at the drum riser's front corner, and writes assets/models/looper.glb.
#
#     blender --background --python tools/blender/looper.py
#
# WHAT IT IS FOR
#
# A looper, by hand (docs/spatial_loop.md part two, slice 45, idea #21): slap its pad to record a loop
# of everything you play, slap again to stack a layer. So it looks like a drummer's sample pad on a
# snare stand: three splayed steel legs on rubber feet, a pole, a tilt clamp, and on it a dark case
# tipped toward whoever stands in front, a big rubber pad set into its deck inside a raised rim, and
# behind the pad a panel hinged up off the deck and leant back: the screen on its left and the LENGTH
# key on its right. The pad's rubber, the screen's glass and lettering and the key are Looper's own
# (they are struck, change and are pressed); this is everything that does not.
#
# Looper (core/music/looper.gd) repeats every number below that it places things by (the deck's
# height and tilt, the case, the pad's place, the panel's hinge and lean, the screen's and the key's
# sizes and places), so the two agree.
#
# ORIENTATION (see _parts.py)
#
# Godot +Y is Blender +Z and Godot -Z is Blender +Y. Its origin is the middle of the stand's feet,
# on the riser's top; its front, where you stand, is Godot +Z: Blender -Y.

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    _flatten, bevel_all, box, clear_scene, export, join, material, report, smooth,
)

# --- In metres, in Godot's terms (y up, z toward you), as Looper has them. --------------------

STAND_FOOT = 0.2         # the feet's radius
HUB = 0.2                # where the legs meet the pole
PAD_Y = 0.72             # the deck's top, over the feet
TILT = 0.4               # the deck tipped toward the front (radians)
CASE = (0.21, 0.05, 0.16)    # half x, thickness, half z, in the deck's frame
PAD_HALF = (0.15, 0.08)
PAD_Z = 0.05
RIM = 0.007              # the raised rim round the pad: its width
RIM_TALL = 0.005
HINGE_Z = -0.07          # the panel hinges up off the deck here
SCREEN_LEAN = 0.6        # leant back from straight up off the deck (radians)
PANEL = (-0.198, 0.193, 0.095)   # the panel's left and right x, and its height up its face
PANEL_THICK = 0.012
LEG_RADIUS = 0.009
POLE_RADIUS = 0.013


def g(p):
    """A point in Godot's terms as Blender has it."""
    return Vector((p[0], -p[2], p[1]))


def gbox(name, lo, hi, ease=0.0012):
    """A box from Godot-space corners: x, y up, z toward you, its edges eased."""
    size = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    centre = ((lo[0] + hi[0]) * 0.5, -(lo[2] + hi[2]) * 0.5, (lo[1] + hi[1]) * 0.5)
    return bevel_all(box(name, size, centre), ease, 1)


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


def ball(name, at, radius):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=radius, location=g(at))
    obj = bpy.context.active_object
    obj.name = name
    return _flatten(obj)


def prism(name, section, x0, x1):
    """A prism along Godot X from `x0` to `x1`, its section [(y, z), ...] in Godot's terms."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    left = [bm.verts.new(g((x0, y, z))) for y, z in section]
    right = [bm.verts.new(g((x1, y, z))) for y, z in section]
    bm.faces.new(list(reversed(left)))
    bm.faces.new(right)
    n = len(section)
    for k in range(n):
        bm.faces.new([left[k], left[(k + 1) % n], right[(k + 1) % n], right[k]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


MATS = []


def slot(obj, index):
    obj.data.materials.clear()
    for m in MATS:
        obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = index
    return obj


def to_deck(obj):
    """A part made in the deck's frame put where the deck is: tipped by TILT, PAD_Y up."""
    obj.rotation_euler = (TILT, 0.0, 0.0)
    obj.location = g((0.0, PAD_Y, 0.0))
    return _flatten(obj)


def deck_parts():
    cx, ct, cz = CASE
    parts = []
    parts.append(slot(gbox("Case", (-cx, -ct, -cz), (cx, 0.0, cz), 0.004), 0))
    # The rim round the pad: four strips, proud of the deck.
    px, pz = PAD_HALF
    z0 = PAD_Z - pz
    z1 = PAD_Z + pz
    parts.append(slot(gbox("RimFront", (-px - RIM, 0.0, z1), (px + RIM, RIM_TALL, z1 + RIM)), 1))
    parts.append(slot(gbox("RimBack", (-px - RIM, 0.0, z0 - RIM), (px + RIM, RIM_TALL, z0)), 1))
    parts.append(slot(gbox("RimLeft", (-px - RIM, 0.0, z0), (-px, RIM_TALL, z1)), 1))
    parts.append(slot(gbox("RimRight", (px, 0.0, z0), (px + RIM, RIM_TALL, z1)), 1))
    # The panel behind it: a slab leant back off the hinge, and a wedge filling under it to the deck.
    up = (math.sin(SCREEN_LEAN), -math.cos(SCREEN_LEAN))      # (y, z) along the panel's face
    out = (math.cos(SCREEN_LEAN), math.sin(SCREEN_LEAN))      # (y, z) out of it
    top = (up[0] * PANEL[2], HINGE_Z + up[1] * PANEL[2])
    back_top = (top[0] - out[0] * PANEL_THICK, top[1] - out[1] * PANEL_THICK)
    parts.append(slot(prism("Panel", [(0.0, HINGE_Z), top, back_top, (0.0, back_top[1])],
            PANEL[0], PANEL[1]), 2))
    # A thin bezel along the panel's top edge, the lip a screen's glass sits under.
    lip_a = (top[0], top[1])
    lip_b = (top[0] + out[0] * 0.004, top[1] + out[1] * 0.004)
    lip_c = (lip_b[0] - up[0] * 0.006, lip_b[1] - up[1] * 0.006)
    lip_d = (top[0] - up[0] * 0.006, top[1] - up[1] * 0.006)
    parts.append(slot(prism("PanelLip", [lip_a, lip_b, lip_c, lip_d], PANEL[0], PANEL[1]), 1))
    first = parts.pop(0)
    obj = join(first, parts)
    obj.name = "Deck"
    return to_deck(obj)


def stand_parts():
    parts = []
    # Three legs splayed from the hub to the feet: one straight back, two toward the front corners, so
    # nothing is under the pad where a player's knees are.
    for degrees in (90.0, 210.0, 330.0):
        a = math.radians(degrees)
        foot = (STAND_FOOT * math.cos(a), 0.012, -STAND_FOOT * math.sin(a))
        parts.append(slot(rod("Leg", (0.0, HUB, 0.0), foot, LEG_RADIUS), 3))
        parts.append(slot(ball("Foot", foot, 0.016), 4))
    parts.append(slot(rod("Collar", (0.0, HUB - 0.03, 0.0), (0.0, HUB + 0.03, 0.0), POLE_RADIUS * 1.8, 20), 3))
    # The pole, up to the tilt clamp under the case's middle.
    clamp_y = PAD_Y - CASE[1] - 0.035
    parts.append(slot(rod("Pole", (0.0, HUB, 0.0), (0.0, clamp_y, 0.0), POLE_RADIUS), 3))
    parts.append(slot(rod("Clamp", (-0.03, clamp_y, 0.0), (0.03, clamp_y, 0.0), 0.02, 20), 5))
    parts.append(slot(rod("Wing", (0.03, clamp_y, 0.0), (0.05, clamp_y, 0.0), 0.007, 12), 5))
    parts.append(slot(gbox("WingNut", (0.05, clamp_y - 0.016, -0.004), (0.056, clamp_y + 0.016, 0.004)), 5))
    # A bracket from the clamp up to the case's underside, square to the deck.
    under = Vector((0.0, PAD_Y, 0.0))
    tilt_down = Vector((0.0, -math.cos(TILT), -math.sin(TILT)))
    under = under + tilt_down * CASE[1]
    parts.append(slot(rod("Bracket", (0.0, clamp_y, 0.0), (under.x, under.y + 0.004, under.z), 0.011, 16), 3))
    return parts


def looper():
    clear_scene()
    MATS[:] = [material("case", (0.11, 0.11, 0.12, 1.0), 0.5),
            material("rim", (0.05, 0.05, 0.055, 1.0), 0.4),
            material("panel", (0.08, 0.08, 0.085, 1.0), 0.45),
            material("stand", (0.06, 0.06, 0.065, 1.0), 0.35),
            material("rubber", (0.03, 0.03, 0.03, 1.0), 0.9),
            material("chrome", (0.7, 0.7, 0.72, 1.0), 0.2)]
    parts = [deck_parts()] + stand_parts()
    first = parts.pop(0)
    obj = join(first, parts)
    obj.name = "Looper"
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/looper.glb")


os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
looper()
