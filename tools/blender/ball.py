# Builds the bouncy ball and writes assets/models/ball.glb.
#
#     blender --background --python tools/blender/ball.py
#
# The throwing toy (docs/items_loop.md): a rubber ball the size of a fist, bigger than a real
# superball so it can be seen across the room. One sphere with a stripe wound round it like a
# seam, so its tumble can be seen in flight -- a plain ball spinning looks like a ball standing
# still. Two materials, "ball" and "stripe", which the item swaps by name. Origin on its bottom.

import math
import os

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RADIUS = 0.045

bpy.ops.wm.read_factory_settings(use_empty=True)
base = bpy.data.materials.new("ball")
stripe = bpy.data.materials.new("stripe")

bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=RADIUS, location=(0.0, 0.0, RADIUS))
ob = bpy.context.active_object
ob.name = "ball"
bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
ob.data.materials.append(base)
ob.data.materials.append(stripe)

# A band that winds once round the ball and tips up and down twice as it goes: a tennis ball's
# seam, near enough, which shows which way it is turning from any side.
bm = bmesh.new()
bm.from_mesh(ob.data)
for f in bm.faces:
	c = f.calc_center_median()
	x, y, z = c.x / RADIUS, c.y / RADIUS, (c.z - RADIUS) / RADIUS
	around = math.atan2(y, x)
	seam = 0.55 * math.sin(2.0 * around)
	if abs(z - seam) < 0.22:
		f.material_index = 1
	f.smooth = True
bm.to_mesh(ob.data)
bm.free()

print("ball", len(ob.data.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/ball.glb"), export_format="GLB")
print("wrote ball.glb")
