# Builds the paper plane and writes assets/models/plane.glb.
#
#     blender --background --python tools/blender/plane.py
#
# The gliding toy (docs/items_loop.md): a dart folded from one sheet, the kind everyone makes
# first. Paper has no thickness worth modelling, so it is single faces, drawn from both sides by
# the item. Two wings with a little dihedral on a narrow keel you hold it by, and a red line
# down each wing where the last fold was inked over -- which, seen from below in flight, shows
# which way it is banking. Two materials, "paper" and "ink", which the item swaps by name.
# Nose toward +Y here, which is -Z (an item's forward) once exported. Origin on its keel's
# bottom.

import os

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
LENGTH = 0.24
SPAN = 0.15
# How high the wings sit above the bottom of the keel, and how far their tips lift above that.
KEEL = 0.032
DIHEDRAL = 0.012
# Where the inked fold runs along each wing, as a fraction of the half-span at the tail.
INK_FROM, INK_TO = 0.62, 0.7

bpy.ops.wm.read_factory_settings(use_empty=True)
paper = bpy.data.materials.new("paper")
ink = bpy.data.materials.new("ink")

mesh = bpy.data.meshes.new("plane")
ob = bpy.data.objects.new("plane", mesh)
bpy.context.scene.collection.objects.link(ob)
mesh.materials.append(paper)
mesh.materials.append(ink)

bm = bmesh.new()
nose_y, tail_y = LENGTH * 0.5, -LENGTH * 0.5
half = SPAN * 0.5


def v(x, y, z):
	return bm.verts.new((x, y, z))


nose = v(0.0, nose_y, KEEL)
tail = v(0.0, tail_y, KEEL)
for side in (-1.0, 1.0):
	# Along the trailing edge from the spine out to the tip, rising with the dihedral.
	def edge(f):
		return v(side * half * f, tail_y, KEEL + DIHEDRAL * f)
	a, b, tip = edge(INK_FROM), edge(INK_TO), edge(1.0)
	for face, inked in (((nose, tail, a), False), ((nose, a, b), True), ((nose, b, tip), False)):
		f = bm.faces.new(face if side > 0 else tuple(reversed(face)))
		f.material_index = 1 if inked else 0
	# The keel: the sheet folded down under the spine, a narrow V from just behind the nose to
	# the tail, the part a hand pinches.
	under = v(side * 0.004, tail_y, 0.0)
	front = v(side * 0.002, nose_y - LENGTH * 0.3, KEEL * 0.7)
	keel = (nose, front, under, tail)
	bm.faces.new(keel if side > 0 else tuple(reversed(keel)))

bm.normal_update()
bm.to_mesh(mesh)
bm.free()

print("plane", len(mesh.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/plane.glb"), export_format="GLB")
print("wrote plane.glb")
