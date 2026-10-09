# Builds a poker chip and a playing card, and writes assets/models/chip.glb and
# assets/models/card.glb.
#
#     blender --background --python tools/blender/table_games.py
#
# The chip (docs/items_loop.md) is a 39 mm clay chip: a disc with six rectangular inserts round
# its edge that show as stripes on both faces, and a paper inlay in the middle of each face. Built
# flat, origin at the middle of its bottom face. Materials "clay" (the chip's colour, set by the
# item), "insert", "inlay".
#
# The card is a poker-size card, 63.5 by 88.9 mm, with rounded corners, a hair thick. Built flat,
# long side along Y in Blender (-Z once exported), origin at the middle of its bottom face. Its
# top is the back ("back"), its bottom the face ("face"), its edge "edge": a card lies face down.

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CHIP_RADIUS = 0.0195
CHIP_THICK = 0.0033
INSERTS = 6
CARD_W = 0.0635
CARD_L = 0.0889
CARD_THICK = 0.0003
CORNER = 0.0032


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
	return bpy.data.materials.get(name) or bpy.data.materials.new(name)


def tag(ob, mat):
	ob.data.materials.append(material(mat))
	return ob


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


def write(path):
	for ob in bpy.data.objects:
		lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
		print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 5) for i in range(3)),
				tuple(round(max(v[i] for v in lo), 5) for i in range(3)), len(ob.data.polygons), "faces")
	bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, path), export_format="GLB")
	print("wrote", path)


# --- the chip -----------------------------------------------------------------------------------
reset()
parts = []
bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=CHIP_RADIUS, depth=CHIP_THICK,
		location=(0, 0, CHIP_THICK * 0.5))
body = tag(bpy.context.active_object, "clay")
mod = body.modifiers.new("round", "BEVEL")
mod.width = 0.0005
mod.segments = 2
bpy.context.view_layer.objects.active = body
bpy.ops.object.modifier_apply(modifier="round")
for f in body.data.polygons:
	f.use_smooth = abs(f.normal.z) < 0.5
parts.append(body)
# The inserts: blocks through the rim, a hair proud of edge and faces, so each shows as a stripe
# on the edge and a short bar on both faces.
for k in range(INSERTS):
	a = k * math.tau / INSERTS
	r = CHIP_RADIUS - 0.0026
	bpy.ops.mesh.primitive_cube_add(size=1, location=(math.cos(a) * r, math.sin(a) * r, CHIP_THICK * 0.5),
			rotation=(0, 0, a))
	ins = bpy.context.active_object
	ins.scale = (0.0056, 0.0062, CHIP_THICK + 0.0003)
	parts.append(tag(ins, "insert"))
# The inlays: a thin paper disc on each face.
for z, sign in ((CHIP_THICK + 0.00008, 1), (-0.00008, -1)):
	bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.0122, depth=0.00016, location=(0, 0, z))
	parts.append(tag(bpy.context.active_object, "inlay"))
join(parts, "Chip")
write("assets/models/chip.glb")


# --- the card -----------------------------------------------------------------------------------
reset()


def outline():
	# The card's rounded rectangle, anticlockwise from the bottom right.
	pts = []
	hx, hy = CARD_W * 0.5 - CORNER, CARD_L * 0.5 - CORNER
	for cx, cy, a0 in ((hx, -hy, -90), (hx, hy, 0), (-hx, hy, 90), (-hx, -hy, 180)):
		for s in range(7):
			a = math.radians(a0 + s * 15)
			pts.append((cx + math.cos(a) * CORNER, cy + math.sin(a) * CORNER))
	return pts


mesh = bpy.data.meshes.new("Card")
bm = bmesh.new()
ring = outline()
low = [bm.verts.new((x, y, 0.0)) for x, y in ring]
high = [bm.verts.new((x, y, CARD_THICK)) for x, y in ring]
face = bm.faces.new(list(reversed(low)))
face.material_index = 1
back = bm.faces.new(high)
back.material_index = 0
n = len(ring)
for i in range(n):
	j = (i + 1) % n
	side = bm.faces.new([low[i], low[j], high[j], high[i]])
	side.material_index = 2
# UVs: the face and the back each take the whole texture, the right way up from their side.
uv = bm.loops.layers.uv.new()
for f in bm.faces:
	for loop in f.loops:
		x, y = loop.vert.co.x, loop.vert.co.y
		u = x / CARD_W + 0.5
		v = y / CARD_L + 0.5
		if f.material_index == 1:
			u = 1.0 - u
		loop[uv].uv = (u, v)
bm.to_mesh(mesh)
bm.free()
card = bpy.data.objects.new("Card", mesh)
bpy.context.collection.objects.link(card)
for name in ("back", "face", "edge"):
	card.data.materials.append(material(name))
write("assets/models/card.glb")
