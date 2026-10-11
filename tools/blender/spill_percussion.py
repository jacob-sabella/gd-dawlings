# Builds the instruments that spill out of the Tour case, and writes assets/models/cowbell.glb,
# woodblock.glb, pad.glb, triangle.glb, claves.glb, hihat.glb and bongos.glb.
#
#     blender --background --python tools/blender/spill_percussion.py
#
# The cowbell is a tapered, flattened box with a small handle loop at its narrow (top) end, mouth
# down. The woodblock is a solid block with a shallow slot across one face, where a real one's
# resonating cut is. The drum pad is a low disc on a wider base, a stage monitor's practice pad,
# with a status LED on the rim. The triangle is three bent steel rods closed at two corners and
# left a small gap at the third, the way a real one is left open so it rings rather than being
# damped by its own suspension point. The claves are a pair of short tapered wooden sticks, laid
# side by side at a slight angle and offset along their length, with a visible gap between them so
# they read as two distinct sticks rather than one long rod. The hi-hat is a pair of thin bevelled
# discs stacked a small gap apart, a closed pair carried as one item rather than the stand they'd
# sit on. The bongos are a joined pair of drum shells, a smaller one and a larger one side by
# side, bridged by a short wood block where a real pair's rims are bolted together. All seven
# built origin at the bottom, facing -Z once exported (Blender's Z-up becomes Godot's Y-up on
# export, so "bottom" here is "bottom" there too) -- the triangle's, claves', hi-hat's and bongos'
# own "bottom" is their vertical middle, the same convention the others use.
# Materials: cowbell "bell"/"handle", woodblock "wood"/"slot", pad "pad"/"rim"/"led", triangle
# "rod", claves "wood", hi-hat "cymbal", bongos "shell".

import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


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


def boolean_cut(ob, cutter):
	b = ob.modifiers.new("cut", "BOOLEAN")
	b.object = cutter
	b.operation = "DIFFERENCE"
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.modifier_apply(modifier="cut")
	bpy.data.objects.remove(cutter)


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


# --- the cowbell --------------------------------------------------------------------------------
reset()
cowbell = []
BELL_HEIGHT = 0.14
bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.078, radius2=0.048, depth=BELL_HEIGHT,
		location=(0, 0, BELL_HEIGHT * 0.5), rotation=(0, 0, math.radians(45)))
bell = bpy.context.active_object
bell.scale.y = 0.62
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
part(bell, "bell", cowbell)
bevel(bell, 0.004)
# The handle loop, at the narrow (top) end, where a real one's mounting strap goes.
bpy.ops.mesh.primitive_torus_add(major_radius=0.012, minor_radius=0.003, location=(0, 0, BELL_HEIGHT + 0.003))
part(bpy.context.active_object, "handle", cowbell)
join(cowbell, "Cowbell")
report_and_write("assets/models/cowbell.glb")


# --- the woodblock -------------------------------------------------------------------------------
reset()
woodblock = []
BLOCK = (0.16, 0.055, 0.045)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, BLOCK[2] * 0.5))
block = bpy.context.active_object
block.scale = BLOCK
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
part(block, "wood", woodblock)
bevel(block, 0.003)
# The slot: a shallow cut into the +Y face, where a real block's resonating gap is.
slot_size = (0.14, 0.012, 0.03)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, BLOCK[1] * 0.5, BLOCK[2] * 0.5))
slot = bpy.context.active_object
slot.scale = slot_size
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
part(slot, "slot", [])
boolean_cut(block, slot)
# The cut leaves a bare wood wall where it went in -- a thin tinted insert at the bottom of the
# groove, so "slot" is a surface the item's material swap can actually find, not just a shape.
fill_y = BLOCK[1] * 0.5 - slot_size[1] * 0.5 + 0.0005
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, fill_y, BLOCK[2] * 0.5))
fill = bpy.context.active_object
fill.scale = (slot_size[0] - 0.01, 0.001, slot_size[2] - 0.004)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
part(fill, "slot", woodblock)
join(woodblock, "Woodblock")
report_and_write("assets/models/woodblock.glb")


# --- the drum pad --------------------------------------------------------------------------------
reset()
pad = []
RIM_RADIUS = 0.118
RIM_DEPTH = 0.012
PAD_RADIUS = 0.11
PAD_DEPTH = 0.03
bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=RIM_RADIUS, depth=RIM_DEPTH, location=(0, 0, 0.006))
part(bpy.context.active_object, "rim", pad)
bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=PAD_RADIUS, depth=PAD_DEPTH, location=(0, 0, 0.021))
part(bpy.context.active_object, "pad", pad, smooth=False)
# The status LED, on the rim's front edge.
led_size = (0.02, 0.006, 0.004)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -(RIM_RADIUS - 0.012), RIM_DEPTH + led_size[2] * 0.5))
led = bpy.context.active_object
led.scale = led_size
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
part(led, "led", pad)
join(pad, "Pad")
report_and_write("assets/models/pad.glb")


# --- the triangle --------------------------------------------------------------------------------
reset()


def rod(p1, p2, radius, into):
	p1, p2 = Vector(p1), Vector(p2)
	d = p2 - p1
	bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=d.length,
			location=tuple((p1 + p2) * 0.5))
	ob = bpy.context.active_object
	ob.rotation_mode = "QUATERNION"
	ob.rotation_quaternion = d.to_track_quat("Z", "Y")
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	return part(ob, "rod", into)


def corner(p, radius, into):
	bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=radius, location=tuple(p))
	ob = bpy.context.active_object
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	return part(ob, "rod", into)


triangle = []
ROD_RADIUS = 0.0035
WIDTH = 0.13
HEIGHT = 0.16
HALF = HEIGHT * 0.5
GAP = 0.014
LEFT = Vector((-WIDTH * 0.5, 0, -HALF))
RIGHT = Vector((WIDTH * 0.5, 0, -HALF))
APEX = Vector((0, 0, HALF))
# The base and its two closed corners.
rod(LEFT, RIGHT, ROD_RADIUS, triangle)
corner(LEFT, ROD_RADIUS, triangle)
corner(RIGHT, ROD_RADIUS, triangle)
# The two sides, each stopping short of the apex -- the gap a real triangle is left open at, so
# it rings rather than being damped by its own suspension point.
left_end = LEFT + (APEX - LEFT).normalized() * ((APEX - LEFT).length - GAP * 0.5)
right_end = RIGHT + (APEX - RIGHT).normalized() * ((APEX - RIGHT).length - GAP * 0.5)
rod(LEFT, left_end, ROD_RADIUS, triangle)
rod(RIGHT, right_end, ROD_RADIUS, triangle)
corner(left_end, ROD_RADIUS, triangle)
corner(right_end, ROD_RADIUS, triangle)
join(triangle, "Triangle")
report_and_write("assets/models/triangle.glb")


# --- the claves ----------------------------------------------------------------------------------
reset()


def stick(p1, p2, r1, r2, into):
	p1, p2 = Vector(p1), Vector(p2)
	d = p2 - p1
	bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=r1, radius2=r2, depth=d.length,
			location=tuple((p1 + p2) * 0.5))
	ob = bpy.context.active_object
	ob.rotation_mode = "QUATERNION"
	ob.rotation_quaternion = d.to_track_quat("Z", "Y")
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	return part(ob, "wood", into)


claves = []
STICK_LEN = 0.22
R1 = 0.0145
R2 = 0.0115
LATERAL = 0.023
LEN_OFFSET = 0.045
ANGLE = math.radians(6)
HALF = STICK_LEN * 0.5
DIR = Vector((math.cos(ANGLE), math.sin(ANGLE), 0))
# Two sticks laid parallel (same direction, so their centrelines never cross) but offset sideways
# and along their own length -- the "resting together, not touching end-to-end" pose, with a clear
# gap between them.
A = Vector((0, -LATERAL, 0))
stick(A - DIR * HALF, A + DIR * HALF, R1, R2, claves)
B = Vector((LEN_OFFSET, LATERAL, 0))
stick(B - DIR * HALF, B + DIR * HALF, R1, R2, claves)
for ob in claves:
	bevel(ob, 0.004, segments=3)
join(claves, "Claves")
report_and_write("assets/models/claves.glb")


# --- the hi-hat ----------------------------------------------------------------------------------
reset()

hihat = []
RADIUS = 0.1
DISC_DEPTH = 0.006
HAT_GAP = 0.014
top_z = HAT_GAP * 0.5 + DISC_DEPTH * 0.5
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=RADIUS, depth=DISC_DEPTH, location=(0, 0, top_z))
top_disc = part(bpy.context.active_object, "cymbal", hihat)
bevel(top_disc, 0.003)
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=RADIUS, depth=DISC_DEPTH, location=(0, 0, -top_z))
bottom_disc = part(bpy.context.active_object, "cymbal", hihat)
bevel(bottom_disc, 0.003)
join(hihat, "Hihat")
report_and_write("assets/models/hihat.glb")


# --- the bongos ----------------------------------------------------------------------------------
reset()

bongos = []
HI_RADIUS = 0.05
HI_DEPTH = 0.085
LO_RADIUS = 0.065
LO_DEPTH = 0.095
BONGO_GAP = 0.006
hi_x = -(BONGO_GAP * 0.5 + HI_RADIUS)
lo_x = BONGO_GAP * 0.5 + LO_RADIUS
bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=HI_RADIUS, depth=HI_DEPTH, location=(hi_x, 0, 0))
hi_shell = part(bpy.context.active_object, "shell", bongos)
bevel(hi_shell, 0.004)
bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=LO_RADIUS, depth=LO_DEPTH, location=(lo_x, 0, 0))
lo_shell = part(bpy.context.active_object, "shell", bongos)
bevel(lo_shell, 0.004)
# The wood bridge joining the shells, where a real pair's rims are bolted together.
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
bridge = bpy.context.active_object
bridge.scale = (BONGO_GAP + 0.02, 0.025, 0.02)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
part(bridge, "shell", bongos)
join(bongos, "Bongos")
report_and_write("assets/models/bongos.glb")
