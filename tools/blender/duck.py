# Builds the rubber duck and writes assets/models/duck.glb.
#
#     blender --background --python tools/blender/duck.py
#
# The first item (docs/items_loop.md): a bath duck, a hand's width long. The body and the head
# are one fused skin (see below), so the neck flows into the back the way a moulded toy's does,
# thinned to something light enough to carry in a glove. The beak and the eyes are their own
# pieces. Three materials, "duck", "beak" and "eye", which the item swaps by name. Beak toward
# Blender -Y, which is Godot +Z (the item turns it round to face -Z, the way a glove points);
# origin on its bottom, 0.1 m nose to tail.

import math
import os

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

bpy.ops.wm.read_factory_settings(use_empty=True)
duck = bpy.data.materials.new("duck")
beak = bpy.data.materials.new("beak")
eye = bpy.data.materials.new("eye")

# The skin: a body, a tail, a neck and a head, each a stretched ball, overlapped and then fused
# into one surface by a voxel remesh, so the neck flows into the back the way a moulded toy's
# does. Metaballs would have done it in one, but their mesher gives nothing at a hand's size.
def ball(name, at, size, material, segments=24, rings=16):
	bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1.0, location=at)
	ob = bpy.context.active_object
	ob.name = name
	ob.scale = size
	# Location too: a vertex has to read where it is, or the cut for the flat bottom below
	# lands somewhere else (tools/blender/_parts.py, THE RULE).
	bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
	ob.data.materials.append(material)
	return ob


PARTS = [
	# (centre, radii)
	((0.0, 0.004, 0.026), (0.03, 0.043, 0.026)),     # the body, long nose to tail
	((0.0, 0.036, 0.04), (0.015, 0.016, 0.019)),     # the tail, up at the back
	((0.0, -0.016, 0.048), (0.017, 0.016, 0.016)),   # the neck, so the head grows from the chest
	((0.0, -0.02, 0.068), (0.021, 0.02, 0.02)),      # the head, forward and up
]
pieces = [ball("skin%d" % i, at, size, duck) for i, (at, size) in enumerate(PARTS)]
for ob in pieces:
	ob.select_set(True)
bpy.context.view_layer.objects.active = pieces[0]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "duck"
fuse = body.modifiers.new("fuse", "REMESH")
fuse.mode = "VOXEL"
fuse.voxel_size = 0.0018
bpy.ops.object.modifier_apply(modifier="fuse")
soften = body.modifiers.new("soften", "SMOOTH")
soften.factor = 0.8
soften.iterations = 6
bpy.ops.object.modifier_apply(modifier="soften")
print("skin", len(body.data.vertices), "verts")

# A flat bottom, so it sits on a shelf rather than rocking on a point.
bm = bmesh.new()
bm.from_mesh(body.data)
geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, 0.004), plane_no=(0, 0, 1), clear_inner=True)
edges = [e for e in bm.edges if e.is_boundary]
if edges:
	bmesh.ops.holes_fill(bm, edges=edges)
for v in bm.verts:
	v.co.z -= 0.004
bm.to_mesh(body.data)
bm.free()
mod = body.modifiers.new("thin", "DECIMATE")
mod.ratio = 0.08
bpy.ops.object.modifier_apply(modifier="thin")



# The beak: a flattened lozenge pushed out of the face, its lower half a little shorter.
bill = ball("beak", (0.0, -0.041, 0.064), (0.012, 0.014, 0.0055), beak, 16, 10)
for side in (-1.0, 1.0):
	e = ball("eye", (side * 0.0125, -0.034, 0.078), (0.0042, 0.0042, 0.0048), eye, 10, 6)

for ob in bpy.context.scene.objects:
	for p in ob.data.polygons:
		p.use_smooth = True
	ob.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
n = len(body.data.polygons)
xs = [v.co for v in body.data.vertices]
print("duck", n, "faces; bounds", [round(min(c[i] for c in xs), 3) for i in range(3)],
	[round(max(c[i] for c in xs), 3) for i in range(3)])
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/duck.glb"), export_format="GLB")
print("wrote duck.glb")
