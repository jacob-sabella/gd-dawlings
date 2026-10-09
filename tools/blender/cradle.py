# Builds a Newton's cradle, and writes assets/models/cradle.glb.
#
#     blender --background --python tools/blender/cradle.py
#
# A desk toy (docs/items_loop.md): five steel balls hung in a row, each on a V of two threads
# from the frame's two top rails, over a black plinth. Two objects. "Frame": the plinth and the
# chrome frame, origin on the plinth's underside in the middle. "Ball": one ball and its threads,
# origin at its pivot -- the middle of the line between the rails above it -- so a ball swings by
# turning its node about Z. CradleItem hangs five of them along X. Materials "base", "chrome",
# "ball", "thread".
#
# Sizes in Godot's terms (y up), which CradleItem repeats.

import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BALL = 0.0095
STRING = 0.095
PIVOT_Y = 0.15
RAIL_Z = 0.042
FRAME_X = 0.085
ROD = 0.0022
BASE = (0.21, 0.018, 0.12)


def material(name):
	return bpy.data.materials.get(name) or bpy.data.materials.new(name)


def tag(ob, mat):
	ob.data.materials.append(material(mat))
	return ob


def g(x, y, z):
	# Godot's (x, y up, z toward you) as Blender's (x, -z, y).
	return Vector((x, -z, y))


def rod(a, b, radius, mat, verts=10):
	gap = b - a
	bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=gap.length, location=(a + b) * 0.5)
	ob = bpy.context.active_object
	ob.rotation_mode = "QUATERNION"
	ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(gap.normalized())
	for p in ob.data.polygons:
		p.use_smooth = True
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


bpy.ops.wm.read_factory_settings(use_empty=True)
parts = []
# The plinth, its top edges bevelled.
bpy.ops.mesh.primitive_cube_add(size=1, location=g(0, BASE[1] * 0.5, 0))
plinth = bpy.context.active_object
plinth.scale = (BASE[0], BASE[2], BASE[1])
bpy.ops.object.transform_apply(scale=True)
bev = plinth.modifiers.new("Bevel", "BEVEL")
bev.width = 0.003
bev.segments = 2
bpy.ops.object.modifier_apply(modifier="Bevel")
parts.append(tag(plinth, "base"))
# The frame: at each end an arch of rod, two legs up from the plinth meeting the two rails.
for sx in (-1, 1):
	for sz in (-1, 1):
		parts.append(rod(g(sx * FRAME_X, BASE[1], sz * RAIL_Z), g(sx * FRAME_X, PIVOT_Y, sz * RAIL_Z), ROD, "chrome"))
		# A foot where it stands in the plinth.
		bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=ROD * 2.2, depth=0.003,
				location=g(sx * FRAME_X, BASE[1] + 0.0015, sz * RAIL_Z))
		parts.append(tag(bpy.context.active_object, "chrome"))
for sz in (-1, 1):
	parts.append(rod(g(-FRAME_X - ROD, PIVOT_Y, sz * RAIL_Z), g(FRAME_X + ROD, PIVOT_Y, sz * RAIL_Z), ROD, "chrome"))
for sx in (-1, 1):
	# Rounded corners where a leg meets its rail.
	for sz in (-1, 1):
		bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=ROD * 1.05,
				location=g(sx * FRAME_X, PIVOT_Y, sz * RAIL_Z))
		parts.append(tag(bpy.context.active_object, "chrome"))
join(parts, "Frame")

# One ball, hung from its pivot: the ball, a little eye on top, and its two threads up to the rails.
parts = []
bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=BALL, location=g(0, -STRING, 0))
ball = tag(bpy.context.active_object, "ball")
for p in ball.data.polygons:
	p.use_smooth = True
parts.append(ball)
top = g(0, -STRING + BALL + 0.0012, 0)
bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.0016, depth=0.0024, location=top)
parts.append(tag(bpy.context.active_object, "chrome"))
for sz in (-1, 1):
	parts.append(rod(top, g(0, 0, sz * RAIL_Z), 0.00035, "thread", 4))
join(parts, "Ball")

for ob in bpy.data.objects:
	lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
	print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
			tuple(round(max(v[i] for v in lo), 4) for i in range(3)), len(ob.data.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/cradle.glb"), export_format="GLB")
print("wrote assets/models/cradle.glb")
