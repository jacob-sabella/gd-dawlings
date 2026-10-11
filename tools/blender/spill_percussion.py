# Builds the instruments that spill out of the Tour case, and writes assets/models/cowbell.glb,
# woodblock.glb and pad.glb.
#
#     blender --background --python tools/blender/spill_percussion.py
#
# The cowbell is a tapered, flattened box with a small handle loop at its narrow (top) end, mouth
# down. The woodblock is a solid block with a shallow slot across one face, where a real one's
# resonating cut is. The drum pad is a low disc on a wider base, a stage monitor's practice pad,
# with a status LED on the rim. All three built origin at the bottom, facing -Z once exported
# (Blender's Z-up becomes Godot's Y-up on export, so "bottom" here is "bottom" there too).
# Materials: cowbell "bell"/"handle", woodblock "wood"/"slot", pad "pad"/"rim"/"led".

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
