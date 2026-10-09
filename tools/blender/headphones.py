# Builds the studio headphones and writes assets/models/headphones.glb.
#
#     blender --background --python tools/blender/headphones.py
#
# The headphones you patch yourself into things with (docs/items_loop.md): closed-back studio
# cans, the shape every control room has hanging off a hook -- a sprung band with a padded
# underside, sliders, and two round cups on yokes that swivel flat.
#
# Built as worn: X from ear to ear, Z up, the wearer facing +Y (which is -Z, an item's forward,
# once exported). No cable: what plays in them is the game's to say. The parts the item moves on
# its own, each its own node:
#   "Band"         the headband, sliders and pad; origin at the middle of the head, between the
#                  ears.
#   "CupL", "CupR" a cup and its yoke, origin at the swivel on top of the yoke, so turning one a
#                  quarter about its own up lays it flat (as they lie on a shelf) or back.
# Materials "shell", "pad", "metal", "accent", which the item swaps by name.

import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
# Half a head's breadth at the ears (an adult's is about 15.5cm), and where the pads sit.
HALF_HEAD = 0.078
CUP_RADIUS = 0.046
CUP_DEPTH = 0.03
PAD_MINOR = 0.012
# The cups' middles, out from the pads.
CUP_X = HALF_HEAD + PAD_MINOR * 1.6 + CUP_DEPTH * 0.5
# Where each yoke swivels: over its cup, at the bottom of the slider.
PIVOT_Z = CUP_RADIUS + 0.018
# The band: an arc over the head, from just above each pivot.
BAND_RADIUS = CUP_X + 0.004
BAND_CENTRE_Z = PIVOT_Z + 0.03
BAND_WIDTH = 0.032
BAND_THICK = 0.006

bpy.ops.wm.read_factory_settings(use_empty=True)
mats = {n: bpy.data.materials.new(n) for n in ("shell", "pad", "metal", "accent")}


def smooth(ob):
	for p in ob.data.polygons:
		p.use_smooth = True


def part(ob, mat, into):
	ob.data.materials.append(mats[mat])
	smooth(ob)
	into.append(ob)
	return ob


def join(objs, name, origin):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.join()
	ob = bpy.context.active_object
	ob.name = name
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	# The origin moved to `origin`: the mesh shifted under it.
	ob.data.transform(Matrix.Translation(-Vector(origin)))
	ob.location = origin
	return ob


def swept(name, points, width, thick, mat, into):
	# A flat strip along `points` (in the XZ plane), `width` along Y, `thick` across the arc.
	bm = bmesh.new()
	rings = []
	for i, p in enumerate(points):
		a = points[max(i - 1, 0)]
		b = points[min(i + 1, len(points) - 1)]
		along = (b - a).normalized()
		out = Vector((along.z, 0, -along.x))
		ring = []
		for (u, v) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
			ring.append(bm.verts.new(p + out * (u * thick * 0.5) + Vector((0, v * width * 0.5, 0))))
		rings.append(ring)
	for r0, r1 in zip(rings, rings[1:]):
		for k in range(4):
			bm.faces.new((r0[k], r0[(k + 1) % 4], r1[(k + 1) % 4], r1[k]))
	bm.faces.new(list(reversed(rings[0])))
	bm.faces.new(rings[-1])
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	ob = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(ob)
	bev = ob.modifiers.new("round", "BEVEL")
	bev.width = thick * 0.45
	bev.segments = 3
	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.modifier_apply(modifier="round")
	return part(ob, mat, into)


def arc(radius, centre_z, a0, a1, n):
	# From angle a0 to a1 (0 = straight out to +X, pi/2 = overhead), in the XZ plane.
	return [Vector((math.cos(a0 + (a1 - a0) * i / n) * radius, 0, centre_z
			+ math.sin(a0 + (a1 - a0) * i / n) * radius)) for i in range(n + 1)]


# --- the band ----------------------------------------------------------------------------------
band = []
# Down to a little above each slider, round over the top.
low = math.asin(0.012 / BAND_RADIUS)
swept("band", arc(BAND_RADIUS, BAND_CENTRE_Z, low, math.pi - low, 48), BAND_WIDTH, BAND_THICK, "shell", band)
# The pad under the top: softer and wider, over the middle of the arc.
swept("cushion", arc(BAND_RADIUS - BAND_THICK * 0.5 - 0.007, BAND_CENTRE_Z, math.radians(48),
		math.radians(132), 28), BAND_WIDTH * 1.15, 0.013, "pad", band)
for side in (-1, 1):
	# The sliders: bright rods from the band's ends down to the swivels.
	top = Vector((side * BAND_RADIUS * math.cos(low), 0, BAND_CENTRE_Z + BAND_RADIUS * math.sin(low)))
	bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.0035, depth=top.z - PIVOT_Z + 0.004,
			location=(side * CUP_X, 0, (top.z + PIVOT_Z) * 0.5))
	part(bpy.context.active_object, "metal", band)
	# The band's end cap, where the slider goes in.
	bpy.ops.mesh.primitive_cube_add(size=1, location=(side * (BAND_RADIUS * math.cos(low)), 0, top.z - 0.004))
	cap = bpy.context.active_object
	cap.scale = (0.012, BAND_WIDTH * 0.8, 0.016)
	part(cap, "shell", band)
band_ob = join(band, "Band", (0, 0, 0))


# --- the cups ----------------------------------------------------------------------------------
def cup(side, name):
	objs = []
	cx = side * CUP_X
	# The shell: a short round can, its open face toward the head.
	bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=CUP_RADIUS, depth=CUP_DEPTH,
			location=(cx, 0, 0), rotation=(0, math.pi * 0.5, 0))
	shell = part(bpy.context.active_object, "shell", objs)
	bev = shell.modifiers.new("round", "BEVEL")
	bev.width = 0.006
	bev.segments = 4
	bpy.context.view_layer.objects.active = shell
	bpy.ops.object.modifier_apply(modifier="round")
	# The cap on the outside, with a coloured ring round it.
	bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=CUP_RADIUS * 0.62, depth=0.004,
			location=(cx + side * (CUP_DEPTH * 0.5 + 0.0015), 0, 0), rotation=(0, math.pi * 0.5, 0))
	part(bpy.context.active_object, "metal", objs)
	bpy.ops.mesh.primitive_torus_add(major_radius=CUP_RADIUS * 0.66, minor_radius=0.0028,
			major_segments=48, minor_segments=8, location=(cx + side * (CUP_DEPTH * 0.5 + 0.0015), 0, 0),
			rotation=(0, math.pi * 0.5, 0))
	part(bpy.context.active_object, "accent", objs)
	# The ear pad: a fat ring on the inside face.
	bpy.ops.mesh.primitive_torus_add(major_radius=CUP_RADIUS - PAD_MINOR * 0.9, minor_radius=PAD_MINOR,
			major_segments=48, minor_segments=16,
			location=(cx - side * (CUP_DEPTH * 0.5 + PAD_MINOR * 0.55), 0, 0), rotation=(0, math.pi * 0.5, 0))
	pad = part(bpy.context.active_object, "pad", objs)
	pad.scale = (1.0, 1.0, 0.8)
	# The yoke: a half hoop over the top of the cup, holding it at front and back, from the swivel.
	points = []
	for i in range(25):
		a = math.pi * i / 24
		points.append(Vector((0, math.cos(a) * (CUP_RADIUS + 0.006), math.sin(a) * (CUP_RADIUS + 0.006))))
	bm = bmesh.new()
	prev = None
	for p in points:
		ring = [bm.verts.new(Vector((cx + side * CUP_DEPTH * 0.1, 0, 0)) + p + Vector((dx, 0, 0)) + d)
				for dx, d in ((-0.003, Vector((0, 0, 0))), (0.003, Vector((0, 0, 0))),
						(0.003, p.normalized() * 0.005), (-0.003, p.normalized() * 0.005))]
		if prev:
			for k in range(4):
				bm.faces.new((prev[k], prev[(k + 1) % 4], ring[(k + 1) % 4], ring[k]))
		prev = ring
	mesh = bpy.data.meshes.new("yoke")
	bm.to_mesh(mesh)
	bm.free()
	yoke = bpy.data.objects.new("yoke", mesh)
	bpy.context.collection.objects.link(yoke)
	part(yoke, "shell", objs)
	# The swivel: a small hub where the slider meets the yoke.
	bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.0065, depth=0.012, location=(cx, 0, PIVOT_Z - 0.004))
	part(bpy.context.active_object, "metal", objs)
	return join(objs, name, (cx, 0, PIVOT_Z))


cup(-1, "CupL")
cup(1, "CupR")


for ob in bpy.data.objects:
	lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
	print(ob.name, "at", tuple(round(c, 3) for c in ob.location), "bounds",
			tuple(round(min(v[i] for v in lo), 3) for i in range(3)),
			tuple(round(max(v[i] for v in lo), 3) for i in range(3)), len(ob.data.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/headphones.glb"), export_format="GLB")
print("wrote headphones.glb")
