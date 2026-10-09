# Builds three snowy firs and writes assets/models/firs.glb.
#
#     blender --background --python tools/blender/firs.py
#
# Low-poly, for a whole forest drawn as MultiMeshes (CabinVenue): each tree a short tapered trunk
# and four to six jagged tiers, each tier a cone with a sawtooth rim whose tips droop, with a
# smaller, flatter cap of snow lying on it. 250-400 faces a tree. One unit tall, origin at the
# foot of the trunk; the venue scales them. Three materials -- "needles", "snow", "bark" --
# which the venue swaps by name.

import os
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import bpy, bmesh, math, random
from mathutils import Vector
bpy.ops.wm.read_factory_settings(use_empty=True)
needles = bpy.data.materials.new("needles"); needles.diffuse_color=(0.03,0.07,0.05,1)
snow = bpy.data.materials.new("snow"); snow.diffuse_color=(0.85,0.9,1.0,1)
bark = bpy.data.materials.new("bark"); bark.diffuse_color=(0.12,0.08,0.05,1)

def skirt(bm, y, r, h, points, droop, rnd, mat_index, cap=None):
    """A jagged cone: apex at y+h, a sawtooth rim of `points` teeth at y, tips drooping."""
    apex = bm.verts.new((0, 0, y + h))
    rim = []
    off = rnd.random() * math.tau
    for i in range(points * 2):
        a = off + math.tau * i / (points * 2)
        tip = i % 2 == 0
        rr = r * (rnd.uniform(0.9, 1.08) if tip else 0.68)
        z = y - (droop if tip else 0.0) + rnd.uniform(-0.02, 0.02) * r
        rim.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)))
    for i in range(len(rim)):
        f = bm.faces.new((apex, rim[i], rim[(i + 1) % len(rim)]))
        f.material_index = mat_index
    # Underside, so it is closed from below as you look up at it.
    under = bm.verts.new((0, 0, y + h * 0.25))
    for i in range(len(rim)):
        f = bm.faces.new((under, rim[(i + 1) % len(rim)], rim[i]))
        f.material_index = 0

def tree(name, height, tiers, seed, x):
    rnd = random.Random(seed)
    me = bpy.data.meshes.new(name); ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for m in (needles, snow, bark): me.materials.append(m)
    bm = bmesh.new()
    # The trunk: a short tapered hexagon to the first tier.
    ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.05*height, radius2=0.03*height, depth=0.3*height)
    for v in ret["verts"]: v.co.z += 0.15*height
    for f in bm.faces: f.material_index = 2
    base = 0.18 * height
    span = height - base
    for t in range(tiers):
        k = t / (tiers - 1)
        y = base + span * (k ** 0.9) * 0.82
        r = height * 0.28 * (1.0 - k * 0.85)
        h = span * 0.34 * (1.0 - k * 0.35)
        skirt(bm, y, r, h, 7 + (tiers - t), r * 0.22, rnd, 0)
        # Snow lying on the tier: a smaller, flatter cap just proud of it.
        skirt(bm, y + h * 0.28, r * 0.72, h * 0.62, 6, r * 0.08, rnd, 1)
    bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = False
    ob.location.x = x
    print("fir", name, len(me.polygons), "faces")

tree("fir_tall", 1.0, 6, 3, 0)
tree("fir_mid", 1.0, 5, 11, 1.2)
tree("fir_wide", 1.0, 4, 29, 2.4)
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/firs.glb"), export_format='GLB')
