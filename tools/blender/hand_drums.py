# Builds the circle of hand drums, and writes assets/models/djembe.glb, assets/models/conga.glb and
# assets/models/cajon.glb.
#
#     blender --background --python tools/blender/hand_drums.py
#
# WHAT THEY ARE FOR
#
# A circle of hand drums on the drum riser (HandDrum, core/items/hand_drum_item.gd; docs/spatial_loop.md
# part two, slice 40, idea #30): a djembe, a high and a low conga and a cajon, struck by hand where
# they stand. Where the head is struck picks the sound (bass in the middle, slap at the rim), so each
# head is drawn plain and pale against a dark shell, its rim clear, and nothing is lettered on it.
#
# The djembe: a goblet carved from one log, a wide bowl over a narrow waist and a flared foot, a goat
# skin over the bowl held by two rope rings and the rope's long zigzag between them. Materials
# "shell", "skin", "rope".
#
# The conga: a barrel of glued staves, widest a third of the way up, a skin under a chrome hoop held
# down by six tuning lugs. One model for both: HandDrum widens it for the low one (the tumba). Materials
# "stave", "skin", "hoop".
#
# The cajon: a plywood box with a thinner, paler face (the tapa) screwed on at its top corners, which
# is where a slap is played, and a sound hole in its back, on a stand so it is played standing.
# Materials "wood", "tapa", "screw", "hole", "stand".
#
# Each is played standing, on the drum riser where the player stands too: the djembe and the conga sit
# in a three-legged stand of black steel (STAND tall, a riser's height, ZoneKit.RISER_HEIGHT), and the
# cajon's own stand is that much taller, so a head is as high above the feet of whoever plays it as it
# would be above the floor beside the riser. Material "stand".
#
# Sizes in Godot's terms (y up, z toward the player, who stands at a drum's -Z): every drum's origin is
# the middle of its stand's feet. HandDrum repeats what it strikes by: each head's height and radius
# (SPECS), the cajon's face and its stand's height.

import math
import os

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# The djembe: its outside, (radius, height) from the foot up to the head's rim.
DJEMBE = [(0.112, 0.0), (0.118, 0.012), (0.112, 0.03), (0.098, 0.09), (0.082, 0.18), (0.076, 0.26),
		(0.08, 0.33), (0.1, 0.4), (0.13, 0.47), (0.155, 0.53), (0.166, 0.575), (0.168, 0.605), (0.166, 0.612)]
DJEMBE_HEAD = (0.166, 0.62)
DJEMBE_RINGS = [(0.172, 0.585), (0.112, 0.405)]

# The conga: its staves' outside, foot to rim; the head, its hoop and lugs.
CONGA = [(0.118, 0.0), (0.124, 0.02), (0.142, 0.12), (0.158, 0.25), (0.165, 0.36), (0.162, 0.47),
		(0.153, 0.58), (0.144, 0.68), (0.14, 0.735), (0.14, 0.748)]
CONGA_HEAD = (0.14, 0.76)
HOOP = (0.146, 0.745, 0.007)
LUGS = 6

# The stand a round drum sits in: how high its cradle holds the drum's foot (a riser's height,
# ZoneKit.RISER_HEIGHT), and how far out its three feet are (inside Venue.DRUM_FOOT, the low conga's
# widened by HandDrum).
STAND = 0.3
STAND_FEET = 0.15

# The cajon: its box, its face's thickness, its stand.
CAJON = (0.3, 0.48, 0.3)    # width, height, depth
LIFT = 0.26 + STAND         # the stand's top: the box stands on it
TAPA = 0.006
HOLE = (0.055, 0.29)        # the sound hole in the back: radius, height off the box's foot


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, colour, roughness):
	m = bpy.data.materials.get(name)
	if m is None:
		m = bpy.data.materials.new(name)
		m.use_nodes = True
		principled = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
		principled.inputs["Base Color"].default_value = colour
		if "Roughness" in principled.inputs:
			principled.inputs["Roughness"].default_value = roughness
	return m


LOOKS = {
	"shell": ((0.2, 0.09, 0.035, 1.0), 0.55), "skin": ((0.76, 0.66, 0.47, 1.0), 0.85),
	"rope": ((0.62, 0.52, 0.33, 1.0), 0.9), "stave": ((0.3, 0.06, 0.02, 1.0), 0.35),
	"hoop": ((0.6, 0.6, 0.62, 1.0), 0.3), "wood": ((0.45, 0.26, 0.11, 1.0), 0.6),
	"tapa": ((0.66, 0.45, 0.22, 1.0), 0.5), "screw": ((0.03, 0.03, 0.03, 1.0), 0.4),
	"hole": ((0.01, 0.008, 0.006, 1.0), 0.9), "stand": ((0.02, 0.02, 0.02, 1.0), 0.6),
}


def tag(ob, mat, smooth=True):
	ob.data.materials.clear()
	colour, rough = LOOKS[mat]
	ob.data.materials.append(material(mat, colour, rough))
	# A lathe's foot (its faces from `flat_from` on) stays flat.
	flat_from = ob.get("flat_from", len(ob.data.polygons))
	for p in ob.data.polygons:
		p.use_smooth = smooth and p.index < flat_from
	return ob


def g(x, y, z):
	# Godot's (x, y up, z toward the player) as Blender's (x, -z, y).
	return (x, -z, y)


def lathe(name, profile, segments=48, cap=True):
	"""A surface of revolution about the y axis through `profile` [(r, y)], closed at its foot when
	`cap`, open at its top (a head goes there)."""
	verts = []
	faces = []
	rings = []
	for r, y in profile:
		ring = []
		for k in range(segments):
			a = math.tau * k / segments
			verts.append(g(r * math.cos(a), y, r * math.sin(a)))
			ring.append(len(verts) - 1)
		rings.append(ring)
	for lo, hi in zip(rings, rings[1:]):
		for k in range(segments):
			faces.append((lo[k], lo[(k + 1) % segments], hi[(k + 1) % segments], hi[k]))
	sides = len(faces)
	if cap:
		# Its own ring of vertices, so the foot's flat face is not smoothed into the side.
		base = len(verts)
		r, y = profile[0]
		for k in range(segments):
			a = math.tau * k / segments
			verts.append(g(r * math.cos(a), y, r * math.sin(a)))
		faces.append(tuple(range(base, base + segments)))
	mesh = bpy.data.meshes.new(name)
	mesh.from_pydata(verts, [], faces)
	# Every face outward, whichever way round the profile ran: a lathe drawn inside out shows its far
	# wall's inside through its near one.
	bm = bmesh.new()
	bm.from_mesh(mesh)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(mesh)
	bm.free()
	mesh.update()
	ob = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(ob)
	ob["flat_from"] = sides
	return ob


def disc(radius, y, thick, mat, segments=48):
	bpy.ops.mesh.primitive_cylinder_add(vertices=segments, radius=radius, depth=thick, location=g(0, y - thick * 0.5, 0))
	return tag(bpy.context.active_object, mat)


def ring(radius, y, thick, mat):
	bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=thick, major_segments=48,
			minor_segments=8, location=g(0, y, 0))
	return tag(bpy.context.active_object, mat)


def rod(a, b, radius, mat, vertices=6):
	"""A thin cylinder from `a` to `b`, both in Godot's terms."""
	pa = Vector(g(*a))
	pb = Vector(g(*b))
	mid = (pa + pb) * 0.5
	d = pb - pa
	bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=d.length, location=mid)
	ob = bpy.context.active_object
	ob.rotation_mode = "QUATERNION"
	ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
	return tag(ob, mat)


def box(size, at, mat, bevel=0.0):
	bpy.ops.mesh.primitive_cube_add(size=1, location=g(*at))
	ob = bpy.context.active_object
	ob.scale = (size[0], size[2], size[1])
	bpy.ops.object.transform_apply(scale=True)
	if bevel > 0.0:
		mod = ob.modifiers.new("bevel", "BEVEL")
		mod.width = bevel
		mod.segments = 2
		bpy.context.view_layer.objects.active = ob
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


def raised(ob, by):
	"""`ob` lifted `by` up (Godot's y), its transform applied."""
	ob.location = Vector(g(0, by, 0))
	bpy.ops.object.select_all(action="DESELECT")
	ob.select_set(True)
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
	return ob


def stand(foot, cup):
	"""A round drum's stand: a ring at STAND round the drum's foot (radius `foot`) and a second
	higher round its shell (`cup`: radius, height above the foot), three uprights between them, and
	three legs splayed from the low ring to rubber feet on the floor STAND_FEET out, braced by a ring
	part way down."""
	parts = [ring(foot + 0.008, STAND, 0.007, "stand"), ring(cup[0] + 0.008, STAND + cup[1], 0.006, "stand")]
	brace = 0.09
	for k in range(3):
		a = math.tau * k / 3 + math.pi / 6
		c, s = math.cos(a), math.sin(a)
		parts.append(rod(((foot + 0.008) * c, STAND, (foot + 0.008) * s),
				((cup[0] + 0.008) * c, STAND + cup[1], (cup[0] + 0.008) * s), 0.006, "stand", 8))
		parts.append(rod(((foot + 0.008) * c, STAND, (foot + 0.008) * s), (STAND_FEET * c, 0.012, STAND_FEET * s),
				0.009, "stand", 8))
		bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.016, depth=0.012, location=g(STAND_FEET * c, 0.006, STAND_FEET * s))
		parts.append(tag(bpy.context.active_object, "stand"))
	t = brace / STAND
	parts.append(ring(STAND_FEET + (foot + 0.008 - STAND_FEET) * t, brace, 0.005, "stand"))
	return parts


def report_and_write(path):
	bpy.context.view_layer.update()
	for ob in bpy.data.objects:
		lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
		print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
				tuple(round(max(v[i] for v in lo), 4) for i in range(3)), len(ob.data.polygons), "faces")
	bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, path), export_format="GLB")
	print("wrote", path)


# --- the djembe ---------------------------------------------------------------------------------
reset()
parts = [tag(lathe("Shell", DJEMBE), "shell")]
parts.append(disc(DJEMBE_HEAD[0], DJEMBE_HEAD[1], 0.012, "skin"))
# The skin's edge tucked over the bowl's lip, a little proud of it.
parts.append(ring(DJEMBE_HEAD[0] + 0.002, DJEMBE_HEAD[1] - 0.012, 0.006, "skin"))
for radius, y in DJEMBE_RINGS:
	parts.append(ring(radius, y, 0.007, "rope"))
# The rope's zigzag from the top ring down to the one under the bowl, the verticals that tune it.
strands = 24
top_r, top_y = DJEMBE_RINGS[0]
low_r, low_y = DJEMBE_RINGS[1]
for k in range(strands):
	a = math.tau * k / strands
	b = math.tau * (k + 0.5) / strands
	parts.append(rod((top_r * math.cos(a), top_y, top_r * math.sin(a)),
			(low_r * math.cos(b), low_y, low_r * math.sin(b)), 0.0035, "rope"))
	c = math.tau * (k + 1) / strands
	parts.append(rod((low_r * math.cos(b), low_y, low_r * math.sin(b)),
			(top_r * math.cos(c), top_y, top_r * math.sin(c)), 0.0035, "rope"))
drum = raised(join(parts, "Djembe"), STAND)
# In its stand: cradled at its foot and round its waist.
join([drum] + stand(DJEMBE[0][0], (0.098, 0.09)), "Djembe")
report_and_write("assets/models/djembe.glb")

# --- the conga ----------------------------------------------------------------------------------
reset()
parts = [tag(lathe("Staves", CONGA), "stave")]
parts.append(disc(CONGA_HEAD[0], CONGA_HEAD[1], 0.012, "skin"))
parts.append(ring(HOOP[0], HOOP[1], HOOP[2], "hoop"))
# A band round the foot, and the six lugs: a rod from the hoop down to a bracket on the staves.
parts.append(ring(0.122, 0.03, 0.006, "hoop"))
for k in range(LUGS):
	a = math.tau * (k + 0.5) / LUGS
	top = (0.152 * math.cos(a), HOOP[1], 0.152 * math.sin(a))
	low = (0.161 * math.cos(a), 0.6, 0.161 * math.sin(a))
	parts.append(rod(top, low, 0.004, "hoop", 8))
	bpy.ops.mesh.primitive_cube_add(size=1, location=g(0.158 * math.cos(a), 0.585, 0.158 * math.sin(a)))
	bracket = bpy.context.active_object
	bracket.scale = (0.02, 0.014, 0.03)
	bracket.rotation_euler = (0, 0, -a)
	bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
	parts.append(tag(bracket, "hoop", False))
drum = raised(join(parts, "Conga"), STAND)
# In its stand: cradled at its foot and a hand's width up its staves.
join([drum] + stand(CONGA[0][0], (0.142, 0.12)), "Conga")
report_and_write("assets/models/conga.glb")

# --- the cajon ----------------------------------------------------------------------------------
reset()
w, h, d = CAJON
parts = []
# The stand: a frame of black steel the box sits on, four legs, a top rail and two lower ones.
for x in (w * 0.5 - 0.02, -w * 0.5 + 0.02):
	for z in (d * 0.5 - 0.02, -d * 0.5 + 0.02):
		parts.append(box((0.022, LIFT, 0.022), (x, LIFT * 0.5, z), "stand", 0.003))
	parts.append(box((0.022, 0.022, d - 0.02), (x, LIFT - 0.011, 0), "stand", 0.003))
	parts.append(box((0.02, 0.02, d - 0.04), (x, 0.06, 0), "stand", 0.003))
	parts.append(box((0.02, 0.02, d - 0.04), (x, LIFT * 0.55, 0), "stand", 0.003))
for z in (d * 0.5 - 0.02, -d * 0.5 + 0.02):
	parts.append(box((w - 0.02, 0.022, 0.022), (0, LIFT - 0.011, z), "stand", 0.003))
# The box: its back, sides and top in plywood, the face (the tapa) on its front (-Z).
parts.append(box((w, h, d - TAPA), (0, LIFT + h * 0.5, TAPA * 0.5), "wood", 0.006))
parts.append(box((w - 0.004, h - 0.004, TAPA), (0, LIFT + h * 0.5, -d * 0.5 + TAPA * 0.5), "tapa", 0.002))
# Its screws at the top corners, where it is slapped, and two more down each side.
for x in (w * 0.5 - 0.02, -w * 0.5 + 0.02):
	for y in (LIFT + h - 0.02, LIFT + h * 0.55, LIFT + 0.04):
		bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.0045, depth=0.003,
				location=g(x, y, -d * 0.5 - 0.0005), rotation=(math.pi * 0.5, 0, 0))
		parts.append(tag(bpy.context.active_object, "screw"))
# The sound hole in its back.
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=HOLE[0], depth=0.003,
		location=g(0, LIFT + HOLE[1], d * 0.5 + 0.0005), rotation=(math.pi * 0.5, 0, 0))
parts.append(tag(bpy.context.active_object, "hole"))
join(parts, "Cajon")
report_and_write("assets/models/cajon.glb")
