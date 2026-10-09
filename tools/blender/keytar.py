# Builds the keytar, and writes assets/models/keytar.glb.
#
#     blender --background --python tools/blender/keytar.py
#
# A two-octave keytar (docs/items_loop.md): a glossy body round a keybed of 25 keys, C to C, and a
# neck off its left-hand end, past the low C, with a rubber grip and two buttons on it, the way the shoulder synths
# of the eighties were. Built lying on its back, keys up (+Z in Blender, +Y once exported), along
# X, the keys' front edge toward -Y (+Z exported: toward whoever holds it), origin on its back face
# under the low end of the keys.
#
# Each key is an object of its own, "Key00" to "Key24" by semitone from the low C, with its
# origin on the hinge at its back top edge, so the item turns one about X to press it. Materials
# "body", "trim", "white", "black", "grip", "metal", "led".

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = "assets/models/keytar.glb"

KEYS = 25
WHITE_W = 0.0225
WHITE_L = 0.088
WHITE_H = 0.013
BLACK_W = 0.012
BLACK_L = 0.054
BLACK_H = 0.011
GAP = 0.0012
# The keybed's low end, along X, and where the keys' fronts are.
KEYS_FROM = -0.385
FRONT = -0.092
# The body: under the keys and a panel behind them, then narrowing into the neck.
BODY_FROM = -0.415
BODY_TO = 0.06
BODY_BACK = 0.072
THICK = 0.045
KEYBED = 0.03
NECK_TO = 0.4
NECK_RISE = math.radians(9)
# White keys' semitones in an octave, and black keys' (with where each sits, in whites).
WHITES = [0, 2, 4, 5, 7, 9, 11]
BLACKS = {1: 1, 3: 2, 6: 4, 8: 5, 10: 6}


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
	return bpy.data.materials.get(name) or bpy.data.materials.new(name)


def tag(ob, mat):
	ob.data.materials.append(material(mat))
	return ob


def bevel(ob, width, segments=2):
	mod = ob.modifiers.new("round", "BEVEL")
	mod.width = width
	mod.segments = segments
	mod.limit_method = "ANGLE"
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.modifier_apply(modifier="round")
	return ob


def box(size, at, mat, name):
	bpy.ops.mesh.primitive_cube_add(size=1, location=at)
	ob = bpy.context.active_object
	ob.scale = size
	bpy.ops.object.transform_apply(scale=True)
	ob.name = name
	return tag(ob, mat)


def slab(outline, z0, z1, mat, name):
	# A flat outline in XY, extruded from z0 to z1.
	mesh = bpy.data.meshes.new(name)
	bm = bmesh.new()
	low = [bm.verts.new((x, y, z0)) for x, y in outline]
	high = [bm.verts.new((x, y, z1)) for x, y in outline]
	bm.faces.new(list(reversed(low)))
	bm.faces.new(high)
	n = len(outline)
	for i in range(n):
		j = (i + 1) % n
		bm.faces.new([low[i], low[j], high[j], high[i]])
	bm.to_mesh(mesh)
	bm.free()
	ob = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(ob)
	return tag(ob, mat)


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


def rounded(points, radius, steps=5):
	# A polygon with its corners rounded off.
	out = []
	n = len(points)
	for i in range(n):
		p = Vector(points[i])
		a = (Vector(points[i - 1]) - p).normalized()
		b = (Vector(points[(i + 1) % n]) - p).normalized()
		r = radius
		start = p + a * r
		end = p + b * r
		for s in range(steps + 1):
			t = s / steps
			q = start * (1 - t) ** 2 + p * 2 * (1 - t) * t + end * t * t
			out.append((q.x, q.y))
	return out


reset()
parts = []
# The body: a long slab under the keys with a raked end at the low side and a waist where the neck
# leaves it, the far edge swept up toward the neck.
outline = rounded([
	(BODY_FROM, FRONT - 0.012), (BODY_TO + 0.02, FRONT - 0.012), (BODY_TO + 0.09, -0.035),
	(BODY_TO + 0.09, 0.02), (BODY_TO + 0.02, BODY_BACK), (BODY_FROM + 0.05, BODY_BACK),
	(BODY_FROM - 0.02, 0.02)], 0.022)
body = slab(outline, 0.0, THICK, "body", "Body")
bevel(body, 0.006, 3)
parts.append(body)
# The keybed: a dark well the keys sit in.
white_count = sum(1 for k in range(KEYS) if k % 12 in WHITES)
bed_w = white_count * WHITE_W + 0.01
parts.append(box((bed_w, WHITE_L + 0.006, 0.006), (KEYS_FROM + bed_w * 0.5 - 0.005, FRONT + (WHITE_L + 0.006) * 0.5,
		THICK + 0.001), "trim", "Bed"))
# The panel behind the keys: a black strip with three knobs and a lit display.
panel_y = FRONT + WHITE_L + 0.008
panel = box((bed_w, BODY_BACK - panel_y - 0.012, 0.004), (KEYS_FROM + bed_w * 0.5 - 0.005,
		(panel_y + BODY_BACK - 0.012) * 0.5, THICK + 0.001), "trim", "Panel")
parts.append(panel)
for i in range(3):
	bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.0075, depth=0.012,
			location=(KEYS_FROM + 0.03 + i * 0.03, (panel_y + BODY_BACK) * 0.5 - 0.006, THICK + 0.008))
	parts.append(tag(bevel(bpy.context.active_object, 0.0015, 2), "metal"))
parts.append(box((0.07, 0.022, 0.003), (KEYS_FROM + 0.17, (panel_y + BODY_BACK) * 0.5 - 0.006, THICK + 0.0035),
		"led", "Display"))
# The neck: off the high end, rising a little, along the far edge.
neck_len = NECK_TO - BODY_TO
neck = slab(rounded([(0, -0.028), (neck_len, -0.022), (neck_len, 0.022), (0, 0.028)], 0.008),
		0.004, THICK - 0.004, "body", "Neck")
bevel(neck, 0.005, 2)
neck.rotation_euler = (0, -NECK_RISE, 0)
neck.location = (BODY_TO + 0.06, 0.012, 0.0)
bpy.context.view_layer.objects.active = neck
bpy.ops.object.transform_apply(location=True, rotation=True)
parts.append(neck)
# The grip: a rubber sleeve round the neck's far half, with two buttons on top.
grip_len = neck_len * 0.55
mid = BODY_TO + 0.06 + neck_len * 0.7
# Its axis along the neck; squashed across, rounder than the neck but not a broom handle.
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.031, depth=grip_len,
		location=(mid, 0.012, math.tan(NECK_RISE) * (mid - BODY_TO - 0.06) + THICK * 0.5),
		rotation=(0, math.pi * 0.5 - NECK_RISE, 0))
grip = bpy.context.active_object
grip.scale = (0.9, 1.1, 1.0)
parts.append(tag(grip, "grip"))
for i in range(2):
	x = mid - 0.04 + i * 0.03
	bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.0055, depth=0.008,
			location=(x, 0.012, math.tan(NECK_RISE) * (x - BODY_TO - 0.06) + THICK * 0.5 + 0.029))
	parts.append(tag(bpy.context.active_object, "led" if i == 0 else "metal"))
# Three stripes across the plain end of the body, raked toward the neck: the eighties' way of
# saying it moves.
for i in range(3):
	x = BODY_TO - 0.035 + i * 0.03
	stripe = box((0.012, 0.115, 0.002), (x, -0.006, THICK + 0.0008), "trim", "Stripe")
	stripe.rotation_euler = (0, 0, math.radians(-28))
	parts.append(stripe)
# Strap pins at each end.
for x, z in ((BODY_FROM - 0.016, THICK * 0.5), (NECK_TO + 0.03, math.tan(NECK_RISE) * (NECK_TO - BODY_TO) + THICK * 0.5)):
	bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.006, depth=0.014, location=(x, 0.0, z),
			rotation=(0, math.pi * 0.5, 0))
	parts.append(tag(bpy.context.active_object, "metal"))
for p in parts:
	for f in p.data.polygons:
		f.use_smooth = p.data.materials[0].name in ("metal", "grip")
keytar = join(parts, "Keytar")
# Built with the neck off the high end, as it is easiest to lay out; a keytar's neck is beside the
# low keys, where the left hand holds it. Mirrored, so the keys go on that way round.
keytar.scale = (-1, 1, 1)
bpy.ops.object.transform_apply(scale=True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode="OBJECT")
KEYS_FROM = -KEYS_FROM - white_count * WHITE_W

# The keys, each on its own hinge.
white = 0
for k in range(KEYS):
	octave, step = divmod(k, 12)
	if step in WHITES:
		x0 = KEYS_FROM + (octave * 7 + WHITES.index(step)) * WHITE_W
		w, l, h, top = WHITE_W - GAP, WHITE_L, WHITE_H, THICK + 0.004 + WHITE_H
		cx = x0 + WHITE_W * 0.5
		mat = "white"
	else:
		x0 = KEYS_FROM + (octave * 7 + BLACKS[step]) * WHITE_W - BLACK_W * 0.5
		w, l, h, top = BLACK_W, BLACK_L, BLACK_H, THICK + 0.004 + WHITE_H + BLACK_H * 0.75
		cx = x0 + BLACK_W * 0.5
		mat = "black"
	back = FRONT + WHITE_L
	key = box((w, l, h), (cx, back - l * 0.5, top - h * 0.5), mat, "Key%02d" % k)
	bevel(key, 0.0012 if mat == "white" else 0.0018, 2)
	# Its origin on the hinge: the back edge, at its top.
	bpy.context.scene.cursor.location = (cx, back, top)
	bpy.ops.object.select_all(action="DESELECT")
	key.select_set(True)
	bpy.context.view_layer.objects.active = key
	bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

for ob in bpy.data.objects:
	lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
	if ob.name in ("Keytar", "Key00", "Key24"):
		print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
				tuple(round(max(v[i] for v in lo), 4) for i in range(3)), "origin", tuple(round(c, 4) for c in ob.location))
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, OUT), export_format="GLB")
print("wrote", OUT)
