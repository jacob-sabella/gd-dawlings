# Builds the personal-mix tablet and its wireless send plug, and writes
# assets/models/tablet.glb and assets/models/wireless_plug.glb.
#
#     blender --background --python tools/blender/tablet.py
#
# The tablet (docs/items_loop.md) is a rugged studio slate: a dark body with a rubber bumper, a
# screen over most of its face, and above the screen a moulded tray in which its wireless send
# plugs lie in a row. Lying face up, as it lies on a shelf, origin on the ground under its middle,
# the tray's edge toward +Y (which is -Z, an item's forward, once exported). Nodes the item finds
# by name:
#   "Screen"  the glass, origin at its middle, on its surface.
#   "Tray"    the plugs' tray, origin at its middle, on its floor.
# Materials "case", "bumper", "screen", "tray", which the item swaps by name.
#
# The plug is a quarter-inch jack with a transmitter for a body, stackable (a socket in its back
# end takes the next one's tip), the kind of thing one person's cue pack sends from. Built with
# its body along -Y and its tip along +Y, so once exported the tip points down -Z, into a
# socket whose face looks along +Z; origin at its shoulder, where it seats against the panel.
# Materials "body", "metal", "led", "socket".

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
WIDTH = 0.26
HEIGHT = 0.19
THICK = 0.013
# The glass: most of the face, below the tray.
SCREEN = (0.238, 0.142)
SCREEN_Y = -0.016
# The tray across the top, where the plugs lie.
TRAY = (0.236, 0.024)
TRAY_Y = 0.069
TRAY_DEPTH = 0.0045
# The plug: shoulder to back end, and the shaft that goes into a socket.
PLUG_BODY = 0.036
PLUG_RADIUS = 0.0075
SHAFT = 0.03


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
	return bpy.data.materials.get(name) or bpy.data.materials.new(name)


def smooth(ob):
	for p in ob.data.polygons:
		p.use_smooth = True


def part(ob, mat, into, flat=False):
	ob.data.materials.append(material(mat))
	if not flat:
		smooth(ob)
	into.append(ob)
	return ob


def rounded_box(size, centre, radius, mat, into, segments=4):
	bpy.ops.mesh.primitive_cube_add(size=1, location=centre)
	ob = bpy.context.active_object
	ob.scale = size
	bpy.ops.object.transform_apply(scale=True)
	bev = ob.modifiers.new("round", "BEVEL")
	bev.width = radius
	bev.segments = segments
	bev.limit_method = "NONE"
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.modifier_apply(modifier="round")
	return part(ob, mat, into)


def join(objs, name, origin):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	if len(objs) > 1:
		bpy.ops.object.join()
	ob = bpy.context.active_object
	ob.name = name
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	from mathutils import Matrix
	ob.data.transform(Matrix.Translation(-Vector(origin)))
	ob.location = origin
	return ob


def plane(name, size, centre, mat):
	bm = bmesh.new()
	hx, hy = size[0] * 0.5, size[1] * 0.5
	vs = [bm.verts.new((centre[0] + x, centre[1] + y, centre[2])) for x, y in ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy))]
	face = bm.faces.new(vs)
	# UVs across the whole face, so a texture laid on the glass fills it.
	uv = bm.loops.layers.uv.new()
	for loop in face.loops:
		co = loop.vert.co
		loop[uv].uv = ((co.x - centre[0]) / size[0] + 0.5, (co.y - centre[1]) / size[1] + 0.5)
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	ob = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(ob)
	ob.data.materials.append(material(mat))
	bpy.context.view_layer.objects.active = ob
	return ob


def report_and_write(path):
	for ob in bpy.data.objects:
		if ob.data is None:
			print(ob.name, "at", tuple(round(c, 4) for c in ob.location))
			continue
		lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
		print(ob.name, "at", tuple(round(c, 4) for c in ob.location), "bounds",
				tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
				tuple(round(max(v[i] for v in lo), 4) for i in range(3)), len(ob.data.polygons), "faces")
	bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, path), export_format="GLB")
	print("wrote", path)


# --- the tablet --------------------------------------------------------------------------------
reset()
body = []
# The slate, its edges rounded off.
rounded_box((WIDTH - 0.012, HEIGHT - 0.012, THICK - 0.002), (0, 0, THICK * 0.5), 0.004, "case", body)
# The bumper: a rubber rim round the edge, a little proud of the face and the back, fat at the
# corners where a tablet is dropped on.
rounded_box((WIDTH, HEIGHT, THICK), (0, 0, THICK * 0.5), 0.006, "bumper", body, 6)
bump = body[-1]
# Hollow it out: a box through the middle leaves the rim.
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, THICK * 0.5))
cutter = bpy.context.active_object
cutter.scale = (WIDTH - 0.016, HEIGHT - 0.016, THICK * 2.0)
boolean = bump.modifiers.new("hollow", "BOOLEAN")
boolean.object = cutter
boolean.operation = "DIFFERENCE"
bpy.context.view_layer.objects.active = bump
bpy.ops.object.modifier_apply(modifier="hollow")
bpy.data.objects.remove(cutter)
# The tray: a shallow recess across the top of the face, its floor darker.
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, TRAY_Y, THICK - TRAY_DEPTH * 0.5 + 0.0002))
tray_cut = bpy.context.active_object
tray_cut.scale = (TRAY[0], TRAY[1], TRAY_DEPTH)
case = body[0]
boolean = case.modifiers.new("tray", "BOOLEAN")
boolean.object = tray_cut
boolean.operation = "DIFFERENCE"
bpy.context.view_layer.objects.active = case
bpy.ops.object.modifier_apply(modifier="tray")
bpy.data.objects.remove(tray_cut)
tray_floor = plane("tray_floor", TRAY, (0, TRAY_Y, THICK - TRAY_DEPTH + 0.0003), "tray")
body.append(tray_floor)
# Little saddles in the tray the plugs lie in, so they read as put away rather than dropped.
for i in range(4):
	x = (i - 1.5) * TRAY[0] / 4.0
	for side in (-1, 1):
		rounded_box((0.004, TRAY[1] * 0.7, 0.003), (x + side * 0.018, TRAY_Y, THICK - TRAY_DEPTH + 0.0015),
				0.0012, "bumper", body, 2)
tablet = join(body, "Tablet", (0, 0, 0))
# The glass, flush with the face, a node of its own for the item to draw on.
screen = plane("Screen", SCREEN, (0, SCREEN_Y, THICK + 0.0002), "screen")
join([screen], "Screen", (0, SCREEN_Y, THICK + 0.0002))
tray = bpy.data.objects.new("Tray", None)
bpy.context.collection.objects.link(tray)
tray.location = (0, TRAY_Y, THICK - TRAY_DEPTH + 0.0004)
report_and_write("assets/models/tablet.glb")


# --- the plug ----------------------------------------------------------------------------------
reset()
plug = []
# The transmitter: a rounded can, from the shoulder back.
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=PLUG_RADIUS, depth=PLUG_BODY,
		location=(0, -PLUG_BODY * 0.5, 0), rotation=(math.pi * 0.5, 0, 0))
can = part(bpy.context.active_object, "body", plug)
bev = can.modifiers.new("round", "BEVEL")
bev.width = 0.0018
bev.segments = 3
bpy.context.view_layer.objects.active = can
bpy.ops.object.modifier_apply(modifier="round")
# A ring of light round it, near the shoulder: the colour of whoever it sends to.
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=PLUG_RADIUS + 0.0004, depth=0.003,
		location=(0, -0.008, 0), rotation=(math.pi * 0.5, 0, 0))
part(bpy.context.active_object, "led", plug)
# Grip ridges down the back half.
for k in range(3):
	bpy.ops.mesh.primitive_torus_add(major_radius=PLUG_RADIUS, minor_radius=0.0007, major_segments=32,
			minor_segments=6, location=(0, -0.02 - k * 0.0045, 0), rotation=(math.pi * 0.5, 0, 0))
	part(bpy.context.active_object, "body", plug)
# The back end: a socket the next plug's tip goes into, so they stack.
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.0042, depth=0.001,
		location=(0, -PLUG_BODY - 0.0002, 0), rotation=(math.pi * 0.5, 0, 0))
part(bpy.context.active_object, "metal", plug)
bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.0024, depth=0.0012,
		location=(0, -PLUG_BODY - 0.0004, 0), rotation=(math.pi * 0.5, 0, 0))
part(bpy.context.active_object, "socket", plug)
# The shaft, the insulating ring and the tip, forward of the shoulder.
bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.0032, depth=SHAFT - 0.004,
		location=(0, (SHAFT - 0.004) * 0.5, 0), rotation=(math.pi * 0.5, 0, 0))
part(bpy.context.active_object, "metal", plug)
bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.0033, depth=0.0015,
		location=(0, SHAFT - 0.008, 0), rotation=(math.pi * 0.5, 0, 0))
part(bpy.context.active_object, "socket", plug)
bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.0033, location=(0, SHAFT - 0.003, 0))
part(bpy.context.active_object, "metal", plug)
join(plug, "Plug", (0, 0, 0))
report_and_write("assets/models/wireless_plug.glb")
