# Builds a preserving jar and writes assets/models/jar.glb.
#
#     blender --background --python tools/blender/jar.py
#
# A mason jar, turned from a profile: a round-shouldered body, a short neck, and a screw band
# lid. For the cabin's shelf, drawn as MultiMeshes and scaled, so it is light -- 16 segments
# round. Two materials, "glass" (the jar) and "lid", which CabinVenue swaps by name. 0.1 m
# across, 0.16 m tall, origin on the bottom.

import math
import os

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

bpy.ops.wm.read_factory_settings(use_empty=True)
glass = bpy.data.materials.new("glass")
lid = bpy.data.materials.new("lid")

SEGMENTS = 16
# (radius, height) up the jar's outline; the lid is its own ring of the profile.
BODY = [(0.0, 0.0), (0.046, 0.0), (0.05, 0.006), (0.05, 0.11), (0.046, 0.124), (0.036, 0.132),
        (0.034, 0.138)]
LID = [(0.037, 0.137), (0.038, 0.139), (0.038, 0.156), (0.034, 0.16), (0.0, 0.16)]


def lathe(bm, profile, slot):
    rings = []
    for r, z in profile:
        if r == 0.0:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z))
                      for a in (math.tau * i / SEGMENTS for i in range(SEGMENTS))])
    for lower, upper in zip(rings, rings[1:]):
        for i in range(SEGMENTS):
            j = (i + 1) % SEGMENTS
            if len(lower) == 1:
                f = bm.faces.new((lower[0], upper[j], upper[i]))
            elif len(upper) == 1:
                f = bm.faces.new((lower[i], lower[j], upper[0]))
            else:
                f = bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
            f.material_index = slot


me = bpy.data.meshes.new("jar")
ob = bpy.data.objects.new("jar", me)
bpy.context.collection.objects.link(ob)
me.materials.append(glass)
me.materials.append(lid)
bm = bmesh.new()
lathe(bm, BODY, 0)
lathe(bm, LID, 1)
bm.normal_update()
bm.to_mesh(me)
bm.free()
for p in me.polygons:
    p.use_smooth = True
print("jar", len(me.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/jar.glb"), export_format="GLB")
print("wrote jar.glb")
