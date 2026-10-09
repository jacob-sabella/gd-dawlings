# Builds the hand percussion, and writes assets/models/shaker.glb and assets/models/tambourine.glb.
#
#     blender --background --python tools/blender/percussion.py
#
# The shaker (docs/items_loop.md) is a tube shaker: a lacquered wooden tube with turned end caps
# and a painted band round its middle, the kind that lives in a studio's percussion drawer. Built
# along X, origin at its middle. Materials "wood", "cap", "band".
#
# The tambourine is a wooden hoop with a skin head and five pairs of jingles set in slots round
# it, and a gap with no jingles where the hand holds it. Built lying flat, head up (+Z in Blender,
# +Y once exported), origin at its middle; the hand's gap toward -Y (+Z exported, toward the
# holder). Nodes the item finds by name: "Jingles", one node with all of them, so they can be
# shaken as one. Materials "hoop", "head", "jingle".

import math
import os

import bpy
from mathutils import Vector, Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
# The shaker.
TUBE_LENGTH = 0.19
TUBE_RADIUS = 0.017
CAP = 0.012
# The tambourine.
HOOP_RADIUS = 0.125
HOOP_DEPTH = 0.048
HOOP_WALL = 0.009
PAIRS = 5
JINGLE_RADIUS = 0.017


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
	return bpy.data.materials.get(name) or bpy.data.materials.new(name)


def part(ob, mat, into, smooth=True):
	ob.data.materials.append(material(mat))
	if smooth:
		for p in ob.data.polygons:
			p.use_smooth = True
	into.append(ob)
	return ob


def bevel(ob, width, segments=2):
	mod = ob.modifiers.new("round", "BEVEL")
	mod.width = width
	mod.segments = segments
	mod.limit_method = "ANGLE"
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.modifier_apply(modifier="round")
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


def report_and_write(path):
	for ob in bpy.data.objects:
		if ob.data is None:
			continue
		lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
		print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
				tuple(round(max(v[i] for v in lo), 4) for i in range(3)), len(ob.data.polygons), "faces")
	bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, path), export_format="GLB")
	print("wrote", path)


# --- the shaker --------------------------------------------------------------------------------
reset()
shaker = []
along = (0, math.pi * 0.5, 0)
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=TUBE_RADIUS, depth=TUBE_LENGTH - CAP, rotation=along)
part(bpy.context.active_object, "wood", shaker)
# A painted band round the middle, a hair proud of the wood.
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=TUBE_RADIUS + 0.0006, depth=0.05, rotation=along)
part(bpy.context.active_object, "band", shaker)
# Two thin rings either side of it.
for x in (-0.031, 0.031):
	bpy.ops.mesh.primitive_torus_add(major_radius=TUBE_RADIUS + 0.0004, minor_radius=0.0012, major_segments=32,
			minor_segments=6, location=(x, 0, 0), rotation=along)
	part(bpy.context.active_object, "cap", shaker)
# Turned end caps: a collar, then a domed end.
for side in (-1, 1):
	x = side * (TUBE_LENGTH - CAP) * 0.5
	bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=TUBE_RADIUS + 0.0018, depth=CAP,
			location=(x + side * CAP * 0.5, 0, 0), rotation=along)
	bevel(part(bpy.context.active_object, "cap", shaker), 0.0025, 3)
join(shaker, "Shaker")
report_and_write("assets/models/shaker.glb")


# --- the tambourine ----------------------------------------------------------------------------
reset()
hoop = []
# The hoop: a ring, the outside of a cylinder less its inside.
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=HOOP_RADIUS, depth=HOOP_DEPTH)
ring = part(bpy.context.active_object, "hoop", hoop)
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=HOOP_RADIUS - HOOP_WALL, depth=HOOP_DEPTH * 2)
cut = bpy.context.active_object
b = ring.modifiers.new("hollow", "BOOLEAN")
b.object = cut
b.operation = "DIFFERENCE"
bpy.context.view_layer.objects.active = ring
bpy.ops.object.modifier_apply(modifier="hollow")
bpy.data.objects.remove(cut)
# The slots the jingles sit in: through the hoop, a pair each.
slots = []
for k in range(PAIRS):
	# Round the hoop, leaving the quarter toward -Y bare for the hand.
	a = math.radians(-90) + math.radians(55) + k * math.radians(250.0 / (PAIRS - 1))
	slots.append(a)
	bpy.ops.mesh.primitive_cube_add(size=1, location=(math.cos(a) * HOOP_RADIUS, math.sin(a) * HOOP_RADIUS, 0),
			rotation=(0, 0, a))
	c = bpy.context.active_object
	c.scale = (HOOP_WALL * 3.0, 0.05, HOOP_DEPTH * 0.78)
	b = ring.modifiers.new("slot", "BOOLEAN")
	b.object = c
	b.operation = "DIFFERENCE"
	bpy.context.view_layer.objects.active = ring
	bpy.ops.object.modifier_apply(modifier="slot")
	bpy.data.objects.remove(c)
bevel(ring, 0.0015, 2)
# The skin, stretched over the top edge.
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=HOOP_RADIUS + 0.0008, depth=0.0016,
		location=(0, 0, HOOP_DEPTH * 0.5 + 0.0008))
part(bpy.context.active_object, "head", hoop, smooth=False)
join(hoop, "Hoop")
# The jingles: in each slot two thin discs on a pin across it, face to face, standing in the
# slot so that from above they cross the rim, poking in and out of it.
jingles = []
for a in slots:
	centre = Vector((math.cos(a) * HOOP_RADIUS, math.sin(a) * HOOP_RADIUS, 0))
	tangent = Vector((-math.sin(a), math.cos(a), 0))
	for side in (-1, 1):
		bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=JINGLE_RADIUS, depth=0.0016,
				location=centre + tangent * side * 0.0024)
		disc = bpy.context.active_object
		# Face along the tangent: the disc's axis turned from Z onto it.
		disc.rotation_euler = (math.pi * 0.5, 0, a)
		part(disc, "jingle", jingles)
	# The pin through them, across the slot.
	bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.0011, depth=0.014, location=centre)
	pin = bpy.context.active_object
	pin.rotation_euler = (math.pi * 0.5, 0, a)
	part(pin, "jingle", jingles)
join(jingles, "Jingles")
report_and_write("assets/models/tambourine.glb")
