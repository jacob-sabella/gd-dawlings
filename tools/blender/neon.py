# Builds the jazz club's neon sign and writes assets/models/neon.glb.
#
#     blender --background --python tools/blender/neon.py
#
# The words "after hours" in glass tube: Blender's own font, its letters' outlines (not filled)
# given a round bevel so each stroke is a tube, the way a sign bender bends one. A backing rail
# of dark steel behind them. Materials "tube" and "rail". Blender X along the words, Z up, the
# tube facing Blender -Y (Godot +Z); the origin under the middle of the words.

import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
tube = bpy.data.materials.new("tube")
rail = bpy.data.materials.new("rail")

bpy.ops.object.text_add()
text = bpy.context.object
text.data.body = "after hours"
text.data.size = 0.42
text.data.align_x = "CENTER"
text.data.fill_mode = "NONE"
text.data.bevel_depth = 0.008
text.data.bevel_resolution = 2
text.data.resolution_u = 6
text.rotation_euler = (1.5707963, 0, 0)
text.data.materials.append(tube)
bpy.ops.object.convert(target="MESH")
words = bpy.context.object
words.name = "Words"
xs = [v.co.x for v in words.data.vertices]
zs = [v.co.y for v in words.data.vertices]
print("words: %.2f m wide, %d faces" % (max(xs) - min(xs), len(words.data.polygons)))

# The rail the tubes are clipped to, behind them.
bpy.ops.mesh.primitive_cube_add(size=1.0)
bar = bpy.context.object
bar.name = "Rail"
bar.scale = ((max(xs) - min(xs)) + 0.1, 0.02, 0.03)
bar.location = (0, 0.04, 0.12)
bar.data.materials.append(rail)

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/neon.glb"), export_format="GLB")
print("wrote neon.glb")
