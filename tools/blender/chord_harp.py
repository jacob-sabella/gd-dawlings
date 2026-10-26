# Builds the chord harp's body and writes assets/models/chord_harp.glb.
#
#     blender --background --python tools/blender/chord_harp.py
#
# A floor harp of eight strings that stands against the live room's back wall (ChordHarp,
# core/music/chord_harp.gd; Venue.harp_spot). Lyre-shaped, so its strings are in one upright
# plane facing whoever plays it: a plinth on the floor, a pedestal under a soundbox whose top is
# the soundboard, a tall pillar on the left (the low strings' side) and a short one on the right,
# and a neck curving down from one to the other that carries the tuning pins. Over the middle of
# the neck, on a short post, is the crown: a board the game letters with the chord and the
# octave shift and puts its two octave buttons on (none of that text is baked in).
#
# The strings are not here. The game draws them, so they can shake while they sound and be
# tuned as the chord changes; this is everything that stays still. One object, "Body".
# Materials "wood", "board", "dark", "brass", "crown".
#
# Sizes in Godot's terms (y up, z out of the string plane toward the player), origin on the
# floor in the string plane under the middle string. ChordHarp repeats the ones it needs:
# BOARD_Y, NECK_LEFT, NECK_RIGHT, FRAME_X, CROWN_Y, FOOT.

import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# The soundboard's top, where every string starts.
BOARD_Y = 0.64
# The neck's underside at the two pillars: the low strings are long, the high ones short.
NECK_LEFT = 1.58
NECK_RIGHT = 1.30
# The pillars' centres either side of the strings.
FRAME_X = 0.31
NECK_THICK = 0.05
PILLAR_R = 0.028
# The plinth: its half-size on the floor, and how far behind the string plane its centre is.
FOOT = (0.35, 0.2)
FOOT_Z = -0.06
PLINTH_H = 0.05
# The soundbox: from the pedestal's top up to the soundboard, deeper behind the strings.
BOX_H = 0.13
BOX_FRONT = 0.07
BOX_BACK = -0.16
# The crown's board: its middle, and its size.
CROWN_Y = 1.665
CROWN = (0.34, 0.12, 0.03)
STRINGS = 8
SPACING = 0.062


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
	return bpy.data.materials.get(name) or bpy.data.materials.new(name)


def tag(ob, mat):
	ob.data.materials.clear()
	ob.data.materials.append(material(mat))
	return ob


def g(x, y, z):
	# Godot's (x, y up, z toward the player) as Blender's (x, -z, y).
	return (x, -z, y)


def box(size, at, mat, bevel=0.0):
	bpy.ops.mesh.primitive_cube_add(size=1, location=g(*at))
	ob = bpy.context.active_object
	ob.scale = (size[0], size[2], size[1])
	bpy.ops.object.transform_apply(scale=True)
	if bevel > 0.0:
		mod = ob.modifiers.new("bevel", "BEVEL")
		mod.width = bevel
		mod.segments = 2
		bpy.ops.object.modifier_apply(modifier=mod.name)
	return tag(ob, mat)


def post(radius, bottom, top, x, z, mat, taper=1.0, vertices=16):
	"""An upright round post from `bottom` to `top` (Godot y), its top `taper` times as wide."""
	bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius * taper,
			depth=top - bottom, location=g(x, (bottom + top) * 0.5, z))
	return tag(bpy.context.active_object, mat)


def neck_y(x):
	"""The neck's underside at `x`: down from the tall pillar to the short one, in a shallow S."""
	f = (x + FRAME_X) / (FRAME_X * 2.0)
	return NECK_LEFT + (NECK_RIGHT - NECK_LEFT) * f + 0.025 * math.sin(f * math.pi * 2.0)


def neck(mat):
	"""The neck: a rounded bar swept along its curve, from one pillar's top to the other's."""
	data = bpy.data.curves.new("NeckCurve", "CURVE")
	data.dimensions = "3D"
	data.bevel_depth = NECK_THICK * 0.5
	data.bevel_resolution = 3
	spline = data.splines.new("POLY")
	steps = 24
	spline.points.add(steps)
	for k in range(steps + 1):
		x = -FRAME_X - 0.02 + (FRAME_X * 2.0 + 0.04) * k / steps
		y = neck_y(max(-FRAME_X, min(FRAME_X, x))) + NECK_THICK * 0.5
		bx, by, bz = g(x, y, 0.0)
		spline.points[k].co = (bx, by, bz, 1.0)
	ob = bpy.data.objects.new("Neck", data)
	bpy.context.collection.objects.link(ob)
	bpy.ops.object.select_all(action="DESELECT")
	ob.select_set(True)
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.convert(target="MESH")
	return tag(bpy.context.active_object, mat)


def join(objs, name):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	if len(objs) > 1:
		bpy.ops.object.join()
	ob = bpy.context.active_object
	ob.name = name
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	return ob


reset()
parts = []

# --- on the floor: the plinth, and the pedestal up to the soundbox ---------------------------
parts.append(box((FOOT[0] * 2.0, PLINTH_H, FOOT[1] * 2.0), (0, PLINTH_H * 0.5, FOOT_Z), "dark", 0.012))
pedestal_top = BOARD_Y - BOX_H
parts.append(box((0.14, pedestal_top - PLINTH_H, 0.12), (0, (PLINTH_H + pedestal_top) * 0.5, FOOT_Z),
		"wood", 0.01))

# --- the soundbox, its top the soundboard the strings rise from -------------------------------
box_z = (BOX_FRONT + BOX_BACK) * 0.5
parts.append(box((FRAME_X * 2.0 + 0.06, BOX_H - 0.012, BOX_FRONT - BOX_BACK),
		(0, pedestal_top + (BOX_H - 0.012) * 0.5, box_z), "wood", 0.015))
# The soundboard: a lighter top, a hair proud of the box so the two do not share a face.
parts.append(box((FRAME_X * 2.0 + 0.03, 0.012, BOX_FRONT - BOX_BACK - 0.03),
		(0, BOARD_Y - 0.006, box_z), "board"))
# A sound hole in the box's front, under the strings: a dark disc, proud of the front.
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.035, depth=0.004,
		location=g(0, pedestal_top + BOX_H * 0.45, BOX_FRONT + 0.001), rotation=(math.radians(90), 0, 0))
parts.append(tag(bpy.context.active_object, "dark"))

# --- the pillars and the neck between them ------------------------------------------------------
parts.append(post(PILLAR_R, pedestal_top + 0.02, neck_y(-FRAME_X) + NECK_THICK, -FRAME_X, 0.0, "wood", 0.8))
parts.append(post(PILLAR_R * 0.9, pedestal_top + 0.02, neck_y(FRAME_X) + NECK_THICK, FRAME_X, 0.0, "wood", 0.8))
# Turned finials on both pillars' tops.
for x, top in ((-FRAME_X, neck_y(-FRAME_X) + NECK_THICK), (FRAME_X, neck_y(FRAME_X) + NECK_THICK)):
	bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=PILLAR_R * 1.15, location=g(x, top + 0.02, 0.0))
	parts.append(tag(bpy.context.active_object, "brass"))
parts.append(neck("wood"))

# --- one tuning pin in the neck and one bridge pin on the soundboard per string -----------------
for i in range(STRINGS):
	x = (i - (STRINGS - 1) * 0.5) * SPACING
	top = neck_y(x)
	bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.005, depth=0.07,
			location=g(x, top + NECK_THICK * 0.5, 0.0), rotation=(math.radians(90), 0, 0))
	parts.append(tag(bpy.context.active_object, "brass"))
	bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.006, depth=0.014,
			location=g(x, BOARD_Y + 0.007, 0.0))
	parts.append(tag(bpy.context.active_object, "brass"))

# --- the crown: a post up from the neck's middle, and the board on it ---------------------------
crown_bottom = CROWN_Y - CROWN[1] * 0.5
parts.append(post(0.012, neck_y(0.0) + NECK_THICK * 0.5, crown_bottom + 0.01, 0.0, 0.0, "brass"))
parts.append(box((CROWN[0], CROWN[1], CROWN[2]), (0, CROWN_Y, -CROWN[2] * 0.5 - 0.004), "wood", 0.008))
# Its face, where the lettering and the buttons go: a dark panel set a hair proud of the board.
parts.append(box((CROWN[0] - 0.02, CROWN[1] - 0.02, 0.004), (0, CROWN_Y, -0.002), "crown"))

body = join(parts, "Body")

bpy.context.view_layer.update()
for ob in bpy.data.objects:
	lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
	print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
			tuple(round(max(v[i] for v in lo), 4) for i in range(3)), len(ob.data.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/chord_harp.glb"), export_format="GLB")
print("wrote assets/models/chord_harp.glb")
