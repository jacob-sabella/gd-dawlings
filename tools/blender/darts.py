# Builds a dartboard and a dart, and writes assets/models/dartboard.glb and assets/models/dart.glb.
#
#     blender --background --python tools/blender/darts.py
#
# The board (docs/items_loop.md) is a regulation bristle board, 451 mm across: twenty segments
# with the 20 at the top, the treble and double rings, the bulls, a wire spider over the face and
# a ring of numbers round it. Built facing -Y in Blender (+Z once exported, toward whoever throws),
# origin at the middle of its face, the 20 up. Materials "black", "cream", "red", "green", "wire",
# "numbers", "rim".
#
# The dart is a steel-tip dart, 150 mm: a point, a knurled barrel, a shaft and four flights. Built
# with its point at the origin and its tail toward -Y in Blender (+Z exported): it flies toward
# -Z, the way an item faces. Materials "point", "barrel", "ring", "shaft", "flight".

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
# The board's rings, from its middle (m), as a regulation board has them.
BULL = 0.00635
OUTER_BULL = 0.0159
TREBLE_IN = 0.099
TREBLE_OUT = 0.107
DOUBLE_IN = 0.162
DOUBLE_OUT = 0.170
EDGE = 0.2255
DEPTH = 0.038
ORDER = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
MATERIALS = ["black", "cream", "red", "green", "wire", "numbers", "rim"]


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
		print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
				tuple(round(max(v[i] for v in lo), 4) for i in range(3)), len(ob.data.polygons), "faces")
	bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, path), export_format="GLB")
	print("wrote", path)


def at(r, a, z=0.0):
	# A point `r` out from the middle, `a` clockwise from straight up.
	return (r * math.sin(a), r * math.cos(a), z)


# --- the board ---------------------------------------------------------------------------------
reset()
mesh = bpy.data.meshes.new("Face")
bm = bmesh.new()


def sector(r0, r1, a0, a1, mat, steps=6):
	ring_in = [bm.verts.new(at(r0, a0 + (a1 - a0) * s / steps)) for s in range(steps + 1)] if r0 > 0 else []
	ring_out = [bm.verts.new(at(r1, a0 + (a1 - a0) * s / steps)) for s in range(steps + 1)]
	if r0 > 0:
		f = bm.faces.new(ring_in + list(reversed(ring_out)))
	else:
		centre = bm.verts.new((0, 0, 0))
		f = bm.faces.new([centre] + list(reversed(ring_out)))
	f.material_index = MATERIALS.index(mat)


seg = math.radians(18)
for i in range(20):
	a0 = i * seg - seg * 0.5
	a1 = a0 + seg
	single = "black" if i % 2 == 0 else "cream"
	ring = "red" if i % 2 == 0 else "green"
	sector(OUTER_BULL, TREBLE_IN, a0, a1, single)
	sector(TREBLE_IN, TREBLE_OUT, a0, a1, ring)
	sector(TREBLE_OUT, DOUBLE_IN, a0, a1, single)
	sector(DOUBLE_IN, DOUBLE_OUT, a0, a1, ring)
	sector(DOUBLE_OUT, EDGE, a0, a1, "black")
	sector(BULL, OUTER_BULL, a0, a1, "green", 2)
	sector(0.0, BULL, a0, a1, "red", 2)
bm.normal_update()
for f in bm.faces:
	if f.normal.z < 0:
		f.normal_flip()
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00001)
bm.to_mesh(mesh)
bm.free()
face = bpy.data.objects.new("Face", mesh)
bpy.context.collection.objects.link(face)
for m in MATERIALS:
	face.data.materials.append(material(m))
parts = [face]
# The body under the face: a thick disc, its edge the rim.
bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=EDGE, depth=DEPTH, location=(0, 0, -DEPTH * 0.5 - 0.0003))
body = tag(bpy.context.active_object, "rim")
for p in body.data.polygons:
	p.use_smooth = abs(p.normal.z) < 0.5
parts.append(body)
# The spider: wire rings, and a wire between each pair of segments from the outer bull out.
for r in (BULL, OUTER_BULL, TREBLE_IN, TREBLE_OUT, DOUBLE_IN, DOUBLE_OUT):
	bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.0006, major_segments=96 if r > 0.05 else 32,
			minor_segments=6, location=(0, 0, 0.0003))
	parts.append(tag(bpy.context.active_object, "wire"))
for i in range(20):
	a = i * seg - seg * 0.5
	mid = (OUTER_BULL + DOUBLE_OUT) * 0.5
	bpy.ops.mesh.primitive_cube_add(size=1, location=at(mid, a, 0.0003), rotation=(0, 0, -a))
	w = bpy.context.active_object
	w.scale = (0.0011, DOUBLE_OUT - OUTER_BULL, 0.0011)
	parts.append(tag(w, "wire"))
# The numbers, round the outside, each over its segment, top outward.
for i, n in enumerate(ORDER):
	a = i * seg
	bpy.ops.object.text_add(location=at(0.1975, a, 0.0002), rotation=(0, 0, -a))
	t = bpy.context.active_object
	t.data.body = str(n)
	t.data.size = 0.03
	t.data.extrude = 0.0006
	t.data.align_x = "CENTER"
	t.data.align_y = "CENTER"
	bpy.ops.object.convert(target="MESH")
	parts.append(tag(bpy.context.active_object, "numbers"))
board = join(parts, "Dartboard")
# Face toward -Y, the 20 up.
board.rotation_euler = (math.pi * 0.5, 0, 0)
bpy.ops.object.transform_apply(rotation=True)
write("assets/models/dartboard.glb")


# --- the dart ----------------------------------------------------------------------------------
reset()
parts = []


def along(z0, z1, r0, r1, mat, verts=20):
	# A turned part along the dart, from z0 to z1 behind the point (m), radius r0 to r1.
	bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=z1 - z0,
			location=(0, 0, (z0 + z1) * 0.5))
	ob = tag(bpy.context.active_object, mat)
	for p in ob.data.polygons:
		p.use_smooth = True
	parts.append(ob)
	return ob


# Built along +Z from the point, then laid along -Y.
along(0.0, 0.03, 0.0002, 0.0011, "point", 12)
along(0.03, 0.034, 0.0016, 0.0034, "barrel")
along(0.034, 0.076, 0.0034, 0.0034, "barrel")
for k in range(6):
	z = 0.042 + k * 0.0045
	bpy.ops.mesh.primitive_torus_add(major_radius=0.0034, minor_radius=0.0006, major_segments=20, minor_segments=6,
			location=(0, 0, z))
	parts.append(tag(bpy.context.active_object, "ring"))
along(0.076, 0.08, 0.0034, 0.0022, "barrel")
along(0.08, 0.117, 0.0021, 0.0019, "shaft", 12)
# Four flights, each a thin kite from the shaft's end back.
for k in range(4):
	m = bpy.data.meshes.new("Flight")
	b = bmesh.new()
	outline = [(0.0012, 0.104), (0.009, 0.118), (0.0155, 0.142), (0.0155, 0.15), (0.0012, 0.15)]
	low = [b.verts.new((x, -0.0002, z)) for x, z in outline]
	high = [b.verts.new((x, 0.0002, z)) for x, z in outline]
	b.faces.new(low)
	b.faces.new(list(reversed(high)))
	n = len(outline)
	for i in range(n):
		j = (i + 1) % n
		b.faces.new([low[j], low[i], high[i], high[j]])
	b.to_mesh(m)
	b.free()
	f = bpy.data.objects.new("Flight", m)
	bpy.context.collection.objects.link(f)
	f.rotation_euler = (0, 0, k * math.pi * 0.5 + math.pi * 0.25)
	parts.append(tag(f, "flight"))
dart = join(parts, "Dart")
# Point toward +Y in Blender, -Z once exported; tail behind it.
dart.rotation_euler = (math.pi * 0.5, 0, 0)
bpy.ops.object.transform_apply(rotation=True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode="OBJECT")
write("assets/models/dart.glb")
