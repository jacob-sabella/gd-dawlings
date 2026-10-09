# Builds a yo-yo, and writes assets/models/yoyo.glb.
#
#     blender --background --python tools/blender/yoyo.py
#
# A classic yo-yo (docs/items_loop.md): two rounded halves, a gap between them where the string
# winds, a hub cap in the face of each. One object, "Yoyo", its origin in the middle of the axle
# and the axle along X, so it spins by turning about X. Materials "shell", "cap", "axle".
#
# Sizes in Godot's terms, which YoyoItem repeats.

import math
import os

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RADIUS = 0.028
HALF_WIDTH = 0.0165
GAP = 0.0018
STEPS = 48
MATERIALS = ["shell", "cap", "axle"]

bpy.ops.wm.read_factory_settings(use_empty=True)


def lathe(bm, profile, mat):
	# Turn a profile of (x along the axle, r out from it) points round the axle (Blender's X).
	rings = []
	for x, r in profile:
		rings.append([bm.verts.new((x, r * math.cos(a), r * math.sin(a)))
				for a in (k * math.tau / STEPS for k in range(STEPS))])
	for i in range(len(rings) - 1):
		for k in range(STEPS):
			j = (k + 1) % STEPS
			f = bm.faces.new((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]))
			f.material_index = MATERIALS.index(mat)
			f.smooth = True
	return rings


def cap_disc(bm, ring, centre_x, mat, flip):
	c = bm.verts.new((centre_x, 0, 0))
	for k in range(STEPS):
		j = (k + 1) % STEPS
		f = bm.faces.new((c, ring[j], ring[k]) if flip else (c, ring[k], ring[j]))
		f.material_index = MATERIALS.index(mat)


mesh = bpy.data.meshes.new("Yoyo")
bm = bmesh.new()
for side in (-1, 1):
	# From the gap out to the face: the inner wall, the rounded rim, the face, the cap's edge.
	g = GAP * 0.5
	w = HALF_WIDTH
	shell = [(g, 0.004), (g, 0.012), (g + 0.002, RADIUS * 0.7), (g + 0.004, RADIUS * 0.92),
			(w * 0.45, RADIUS), (w * 0.8, RADIUS * 0.97), (w, RADIUS * 0.85), (w, RADIUS * 0.6)]
	if side < 0:
		shell = [(-x, r) for x, r in reversed(shell)]
	rings = lathe(bm, shell, "shell")
	face_ring = rings[0] if side < 0 else rings[-1]
	# The hub cap: a shallow dome in the face.
	cap = [(w, RADIUS * 0.6), (w + 0.0008, RADIUS * 0.5), (w + 0.0012, RADIUS * 0.25)]
	if side < 0:
		cap = [(-x, r) for x, r in reversed(cap)]
	cap_rings = lathe(bm, cap, "cap")
	cap_disc(bm, cap_rings[0] if side < 0 else cap_rings[-1], side * (w + 0.0013), "cap", side < 0)
	# The inner wall closed round the axle.
	inner = rings[-1] if side < 0 else rings[0]
	cap_disc(bm, inner, side * g, "shell", side > 0)
# The axle across the gap, where the string loops.
lathe(bm, [(-GAP * 0.5, 0.0035), (GAP * 0.5, 0.0035)], "axle")
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.000001)
bm.normal_update()
bm.to_mesh(mesh)
bm.free()
ob = bpy.data.objects.new("Yoyo", mesh)
bpy.context.collection.objects.link(ob)
for m in MATERIALS:
	ob.data.materials.append(bpy.data.materials.get(m) or bpy.data.materials.new(m))
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode="OBJECT")
lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
		tuple(round(max(v[i] for v in lo), 4) for i in range(3)), len(ob.data.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/yoyo.glb"), export_format="GLB")
print("wrote assets/models/yoyo.glb")
