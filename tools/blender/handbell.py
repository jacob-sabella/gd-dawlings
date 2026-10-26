# Builds a handbell and the stand the four of them rest on, and writes assets/models/handbell.glb
# and assets/models/bell_stand.glb.
#
#     blender --background --python tools/blender/handbell.py
#
# The handbell (HandbellItem, core/items/handbell_item.gd): an English handbell, a cast bronze
# bell turned on a lathe (a flared lip, a waist and a rounded crown), hollow so it shows its mouth
# when it is tipped, with its clapper inside. On the crown a short shank, a leather hand guard and
# a leather loop to hold it by, and at the loop's foot a flat leather tab facing the player, where
# the game letters the bell's number and the note it rings now (none of that text is baked in).
# One bell for all four: what tells them apart is the lettering. Materials "bronze", "clapper",
# "leather", "tab".
#
# The stand (Venue.bell_spot): a small table beside the chord harp with a padded top and four
# pegs along it, one under each bell's mouth, so each bell stands mouth down on its pad with its
# handle up, ready to be lifted. Materials "wood", "pad", "peg".
#
# Sizes in Godot's terms (y up, z toward the player): the bell's origin is the middle of its
# mouth, the stand's the middle of its feet. HandbellItem repeats the ones it needs: MOUTH,
# HEIGHT, TAB_Y, STAND_TOP, STAND, PEG_SPACING.

import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# The bell: its outside, (radius, height) from the lip to the crown.
PROFILE = [(0.050, 0.000), (0.0495, 0.005), (0.046, 0.013), (0.040, 0.026), (0.0355, 0.041),
		(0.032, 0.056), (0.029, 0.069), (0.024, 0.080), (0.015, 0.0875), (0.006, 0.0900), (0.0, 0.0905)]
WALL = 0.0035
MOUTH = PROFILE[0][0]
SHANK = (0.007, 0.0895, 0.112)
GUARD = (0.024, 0.006, 0.112)
# The loop: its middle, its half-width and half-height, and the strap's thickness.
LOOP = (0.165, 0.026, 0.045, 0.0065)
# The tab at the loop's foot, facing the player: its middle and size.
TAB_Y = 0.13
TAB = (0.046, 0.034, 0.004)
HEIGHT = LOOP[0] + LOOP[2] + LOOP[3]

# The stand: its top's size, the pad's top (where the bells' mouths rest), the legs, the pegs.
STAND = (0.54, 0.24)
STAND_TOP = 0.80
TOP_THICK = 0.03
PAD_THICK = 0.012
PEG_SPACING = 0.125
# Low felt-topped seats rather than tall pegs: a bell stands over one, its clapper clear of it.
PEG = (0.03, 0.008)


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
	return bpy.data.materials.get(name) or bpy.data.materials.new(name)


def tag(ob, mat, smooth=True):
	ob.data.materials.clear()
	ob.data.materials.append(material(mat))
	if smooth:
		for p in ob.data.polygons:
			p.use_smooth = True
	return ob


def g(x, y, z):
	# Godot's (x, y up, z toward the player) as Blender's (x, -z, y).
	return (x, -z, y)


def lathe(name, profile, segments=40):
	"""A surface of revolution about the y axis through `profile` [(r, y)], open where r > 0 at
	its first point and closed where it reaches r == 0."""
	verts = []
	faces = []
	rings = []
	for r, y in profile:
		if r <= 0.0:
			verts.append(g(0.0, y, 0.0))
			rings.append([len(verts) - 1])
			continue
		ring = []
		for k in range(segments):
			a = math.tau * k / segments
			verts.append(g(r * math.cos(a), y, r * math.sin(a)))
			ring.append(len(verts) - 1)
		rings.append(ring)
	for lo, hi in zip(rings, rings[1:]):
		if len(hi) == 1:
			for k in range(segments):
				faces.append((lo[k], lo[(k + 1) % segments], hi[0]))
		else:
			for k in range(segments):
				faces.append((lo[k], lo[(k + 1) % segments], hi[(k + 1) % segments], hi[k]))
	mesh = bpy.data.meshes.new(name)
	mesh.from_pydata(verts, [], faces)
	mesh.update()
	ob = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(ob)
	return ob


def solidify(ob, thickness):
	mod = ob.modifiers.new("wall", "SOLIDIFY")
	mod.thickness = thickness
	mod.offset = 0.0
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.modifier_apply(modifier=mod.name)
	return ob


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
	return tag(ob, mat, False)


def post(radius, bottom, top, x, z, mat, vertices=16):
	bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=top - bottom,
			location=g(x, (bottom + top) * 0.5, z))
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


def report_and_write(path):
	bpy.context.view_layer.update()
	for ob in bpy.data.objects:
		lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
		print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
				tuple(round(max(v[i] for v in lo), 4) for i in range(3)), len(ob.data.polygons), "faces")
	bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, path), export_format="GLB")
	print("wrote", path)


# --- the bell -----------------------------------------------------------------------------------
reset()
parts = []
bell = tag(lathe("Bell", PROFILE), "bronze")
solidify(bell, WALL)
parts.append(bell)
# A rolled lip, the thick ring the clapper strikes.
bpy.ops.mesh.primitive_torus_add(major_radius=MOUTH - WALL * 0.3, minor_radius=WALL * 0.9,
		major_segments=40, minor_segments=8, location=g(0, WALL * 0.6, 0), rotation=(0, 0, 0))
parts.append(tag(bpy.context.active_object, "bronze"))
# The clapper: a ball on a short arm, hung from inside the crown.
parts.append(post(0.0025, 0.03, 0.086, 0.0, 0.0, "clapper", 8))
bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.009, location=g(0, 0.028, 0))
parts.append(tag(bpy.context.active_object, "clapper"))
# The shank through the crown, the hand guard on it, and the loop.
parts.append(post(SHANK[0], SHANK[1], SHANK[2], 0.0, 0.0, "bronze", 12))
parts.append(post(GUARD[0], GUARD[2] - GUARD[1] * 0.5, GUARD[2] + GUARD[1] * 0.5, 0.0, 0.0, "leather", 24))
bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=LOOP[3] / LOOP[1], major_segments=32,
		minor_segments=8, location=g(0, LOOP[0], 0), rotation=(math.radians(90), 0, 0))
loop = bpy.context.active_object
loop.scale = (LOOP[1], LOOP[2], LOOP[1])
bpy.ops.object.transform_apply(scale=True)
parts.append(tag(loop, "leather"))
# The tab: a flat leather plate at the loop's foot, toward the player.
parts.append(box(TAB, (0, TAB_Y, LOOP[3] + TAB[2] * 0.5 + 0.0005), "tab", 0.0015))
join(parts, "Bell")
report_and_write("assets/models/handbell.glb")

# --- the stand ----------------------------------------------------------------------------------
reset()
parts = []
top_y = STAND_TOP - PAD_THICK - TOP_THICK * 0.5
parts.append(box((STAND[0], TOP_THICK, STAND[1]), (0, top_y, 0), "wood", 0.006))
# The pad: a felt-covered top the bells stand on without ringing.
parts.append(box((STAND[0] - 0.02, PAD_THICK, STAND[1] - 0.02), (0, STAND_TOP - PAD_THICK * 0.5, 0), "pad", 0.004))
# An apron under the top, all round.
apron_y = top_y - TOP_THICK * 0.5 - 0.035
for z in (STAND[1] * 0.5 - 0.035, -STAND[1] * 0.5 + 0.035):
	parts.append(box((STAND[0] - 0.08, 0.07, 0.016), (0, apron_y, z), "wood", 0.003))
for x in (STAND[0] * 0.5 - 0.035, -STAND[0] * 0.5 + 0.035):
	parts.append(box((0.016, 0.07, STAND[1] - 0.08), (x, apron_y, 0), "wood", 0.003))
# Four legs, a little in from the corners, and a stretcher low between each pair.
leg_top = top_y - TOP_THICK * 0.5
for x in (STAND[0] * 0.5 - 0.04, -STAND[0] * 0.5 + 0.04):
	for z in (STAND[1] * 0.5 - 0.04, -STAND[1] * 0.5 + 0.04):
		parts.append(box((0.03, leg_top, 0.03), (x, leg_top * 0.5, z), "wood", 0.004))
	parts.append(box((0.02, 0.025, STAND[1] - 0.08), (x, 0.14, 0), "wood", 0.003))
parts.append(box((STAND[0] - 0.08, 0.025, 0.02), (0, 0.14, 0), "wood", 0.003))
# A seat under each bell's mouth, so a bell put back sits where it was.
for i in range(4):
	x = (i - 1.5) * PEG_SPACING
	parts.append(post(PEG[0], STAND_TOP - 0.001, STAND_TOP + PEG[1], x, 0.0, "peg", 24))
join(parts, "Stand")
report_and_write("assets/models/bell_stand.glb")
