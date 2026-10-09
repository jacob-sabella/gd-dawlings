# Builds the handheld mic and writes assets/models/mic.glb.
#
#     blender --background --python tools/blender/mic.py
#
# The mic you sing into (docs/items_loop.md): a stage dynamic mic, the shape everyone knows -- a
# ball of wire mesh on a body that tapers to the cable end. The mesh is a real wire net (a
# wireframe over a sphere) round a dark foam ball, so it reads as a grille from across the room
# and close up. Lying on its side, as it lies on a shelf: the grille and the cable end both
# touch the ground, the axis tipped to match. Grille toward +Y here, which is -Z (an item's
# forward) once exported. Origin on the ground under it. Materials "body", "grille", "foam",
# "band", which the item swaps by name.

import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GRILLE = 0.026
BODY_TOP = 0.021
BODY_END = 0.0145
BODY_LENGTH = 0.15

bpy.ops.wm.read_factory_settings(use_empty=True)
mats = {n: bpy.data.materials.new(n) for n in ("body", "grille", "foam", "band")}
parts = []


def solid(name, ob, mat):
	ob.name = name
	ob.data.materials.append(mats[mat])
	for p in ob.data.polygons:
		p.use_smooth = True
	parts.append(ob)
	return ob


# Body: a tapered cylinder along +Y, from the cable end (y=0) to the grille.
bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=BODY_END, radius2=BODY_TOP, depth=BODY_LENGTH,
		location=(0, BODY_LENGTH * 0.5, 0), rotation=(-math.pi * 0.5, 0, 0))
solid("body", bpy.context.active_object, "body")
# The ring where the grille screws on.
bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=BODY_TOP + 0.0015, depth=0.012,
		location=(0, BODY_LENGTH + 0.004, 0), rotation=(-math.pi * 0.5, 0, 0))
solid("band", bpy.context.active_object, "band")
# The cable end: a dark socket.
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=BODY_END * 0.8, depth=0.006,
		location=(0, -0.002, 0), rotation=(-math.pi * 0.5, 0, 0))
solid("socket", bpy.context.active_object, "foam")
# The ball: foam inside, a wire net over it.
centre = (0, BODY_LENGTH + 0.01 + GRILLE * 0.75, 0)
bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=GRILLE * 0.94, location=centre)
solid("foam", bpy.context.active_object, "foam")
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=GRILLE, location=centre)
net = bpy.context.active_object
wire = net.modifiers.new("wire", "WIREFRAME")
wire.thickness = 0.0011
wire.use_replace = True
bpy.ops.object.modifier_apply(modifier="wire")
solid("grille", net, "grille")

bpy.ops.object.select_all(action="DESELECT")
for p in parts:
	p.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
mic = bpy.context.active_object
mic.name = "mic"
# The join kept the body's own placement; bake it in, so what follows is in the mic's frame.
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# On its side: tip the axis so the cable end and the grille both rest on the ground, then put
# the ground at the origin.
grille_tip = Vector(centre)
tilt = math.atan2(GRILLE - BODY_END, grille_tip.y)
mic.data.transform(Matrix.Rotation(tilt, 4, "X"))
low = min((v.co.z for v in mic.data.vertices))
mic.data.transform(Matrix.Translation((0, 0, -low)))
# Its middle, end to end (not the vertices' average, which the grille's net drags forward).
ys = [v.co.y for v in mic.data.vertices]
mid_y = (min(ys) + max(ys)) * 0.5
mic.data.transform(Matrix.Translation((0, -mid_y, 0)))

print("mic", len(mic.data.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/mic.glb"), export_format="GLB")
print("wrote mic.glb")
