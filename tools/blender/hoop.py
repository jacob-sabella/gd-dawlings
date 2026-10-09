# Builds a mini basketball hoop on a weighted stand, and writes assets/models/hoop.glb.
#
#     blender --background --python tools/blender/hoop.py
#
# The kind of hoop that goes over a door or stands in a corner (docs/items_loop.md), sized for the
# room's ball (BallItem, 9 cm across): a 23 cm rim, a 60 x 42 cm backboard with its lines, a cord
# net, on a pole from a weighted base. Built facing -Y in Blender (+Z once exported, into the
# room), origin on the floor under the pole. Two objects: "Stand", everything that does not move,
# and "Net", its origin at the middle of the rim, so it can be stretched from the top when a
# ball goes through. Materials "base", "pole", "board", "lines", "rim", "net".
#
# Sizes in Godot's terms (y up, z out of the board), which Hoop and Venue.hoops() repeat.

import math
import os


import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RIM_RADIUS = 0.115
RIM_TUBE = 0.007
RIM_Y = 1.97
# The board's front face, and the rim's middle out from it.
BOARD_FRONT = 0.002
RIM_Z = BOARD_FRONT + 0.03 + RIM_RADIUS
BOARD_W = 0.6
BOARD_H = 0.42
BOARD_Y = 2.12
BOARD_THICK = 0.012
POLE_Z = -0.1
POLE_TOP = BOARD_Y + 0.12
NET_DROP = 0.2
NET_BOTTOM = 0.075


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
	return bpy.data.materials.get(name) or bpy.data.materials.new(name)


def tag(ob, mat):
	ob.data.materials.append(material(mat))
	return ob


def g(x, y, z):
	# Godot's (x, y up, z toward the room) as Blender's (x, -z, y).
	return (x, -z, y)


def box(size, at, mat):
	bpy.ops.mesh.primitive_cube_add(size=1, location=g(*at))
	ob = bpy.context.active_object
	ob.scale = (size[0], size[2], size[1])
	bpy.ops.object.transform_apply(scale=True)
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


reset()
parts = []
# The base: a weighted slab, its front edges bevelled.
base = box((0.46, 0.07, 0.42), (0, 0.035, POLE_Z + 0.06), "base")
bev = base.modifiers.new("Bevel", "BEVEL")
bev.width = 0.012
bev.segments = 2
bpy.context.view_layer.objects.active = base
bpy.ops.object.modifier_apply(modifier="Bevel")
parts.append(base)
# The pole, and its collar at the base.
bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.022, depth=POLE_TOP - 0.07,
		location=g(0, 0.07 + (POLE_TOP - 0.07) * 0.5, POLE_Z))
pole = tag(bpy.context.active_object, "pole")
for p in pole.data.polygons:
	p.use_smooth = abs(p.normal.z) < 0.5
parts.append(pole)
bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.036, depth=0.05, location=g(0, 0.095, POLE_Z))
parts.append(tag(bpy.context.active_object, "pole"))
# Two arms from the pole to the back of the board.
for y in (BOARD_Y - 0.12, BOARD_Y + 0.1):
	parts.append(box((0.03, 0.03, -POLE_Z - BOARD_THICK), (0, y, (POLE_Z - BOARD_THICK) * 0.5), "pole"))
# The board.
board = box((BOARD_W, BOARD_H, BOARD_THICK), (0, BOARD_Y, BOARD_FRONT - BOARD_THICK * 0.5), "board")
bev = board.modifiers.new("Bevel", "BEVEL")
bev.width = 0.004
bev.segments = 2
bpy.context.view_layer.objects.active = board
bpy.ops.object.modifier_apply(modifier="Bevel")
parts.append(board)
# Its lines: a border just in from the edge, and the shooter's square over the rim.
LINE = 0.012
PROUD = BOARD_FRONT + 0.0008
for (w, h, cy) in ((BOARD_W - 0.04, BOARD_H - 0.04, BOARD_Y), (0.24, 0.17, RIM_Y + 0.02 + 0.085)):
	parts.append(box((w, LINE, 0.0016), (0, cy + h * 0.5 - LINE * 0.5, PROUD), "lines"))
	parts.append(box((w, LINE, 0.0016), (0, cy - h * 0.5 + LINE * 0.5, PROUD), "lines"))
	parts.append(box((LINE, h, 0.0016), (-w * 0.5 + LINE * 0.5, cy, PROUD), "lines"))
	parts.append(box((LINE, h, 0.0016), (w * 0.5 - LINE * 0.5, cy, PROUD), "lines"))
# The rim, and the bracket that holds it out from the board.
bpy.ops.mesh.primitive_torus_add(major_radius=RIM_RADIUS, minor_radius=RIM_TUBE, major_segments=48,
		minor_segments=10, location=g(0, RIM_Y, RIM_Z))
rim = tag(bpy.context.active_object, "rim")
for p in rim.data.polygons:
	p.use_smooth = True
parts.append(rim)
parts.append(box((0.1, 0.008, 0.03 + RIM_TUBE), (0, RIM_Y - 0.002, BOARD_FRONT + (0.03 + RIM_TUBE) * 0.5), "rim"))
parts.append(box((0.07, 0.05, 0.006), (0, RIM_Y + 0.02, BOARD_FRONT + 0.003), "rim"))
# Hooks for the net, round under the rim.
for k in range(12):
	a = k * math.tau / 12
	parts.append(box((0.006, 0.012, 0.006), (math.sin(a) * RIM_RADIUS, RIM_Y - 0.008,
			RIM_Z + math.cos(a) * RIM_RADIUS), "rim"))
stand = join(parts, "Stand")

# The net: a cone of cord in diamonds, from the rim down, narrower at the bottom. Built round its
# own origin at the rim's middle, each cord a thin four-sided tube.
ROWS = 4
COLS = 12
rings = []
for r in range(ROWS + 1):
	f = r / ROWS
	radius = RIM_RADIUS + (NET_BOTTOM - RIM_RADIUS) * f
	y = -NET_DROP * f
	# Each row turned half a cell from the last: the cords cross in diamonds.
	turn = (r % 2) * math.pi / COLS
	rings.append([Vector(g(math.sin(k * math.tau / COLS + turn) * radius, y,
			math.cos(k * math.tau / COLS + turn) * radius)) for k in range(COLS)])
cords = []
for r in range(ROWS):
	for k in range(COLS):
		# Down to the two below it, either side: half a cell back and half on.
		for j in ((k - 1) % COLS, k) if r % 2 == 0 else (k, (k + 1) % COLS):
			cords.append((rings[r][k], rings[r + 1][j]))
# And a cord round the bottom.
for k in range(COLS):
	cords.append((rings[ROWS][k], rings[ROWS][(k + 1) % COLS]))
pieces = []
for a, b in cords:
	gap = b - a
	bpy.ops.mesh.primitive_cylinder_add(vertices=4, radius=0.0018, depth=gap.length, end_fill_type="NOTHING",
			location=(a + b) * 0.5)
	c = bpy.context.active_object
	c.rotation_mode = "QUATERNION"
	c.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(gap.normalized())
	pieces.append(c)
net = join(pieces, "Net")
tag(net, "net")
# Built round the origin; moved up to the rim, its origin with it.
net.location = g(0, RIM_Y, RIM_Z)

bpy.context.view_layer.update()
for ob in bpy.data.objects:
	lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
	print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
			tuple(round(max(v[i] for v in lo), 4) for i in range(3)), len(ob.data.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/hoop.glb"), export_format="GLB")
print("wrote assets/models/hoop.glb")
