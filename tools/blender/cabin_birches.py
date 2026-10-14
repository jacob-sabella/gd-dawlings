# Builds three summer birches and writes assets/models/cabin_birches.glb.
#
#     blender --background --python tools/blender/cabin_birches.py
#
# For the cabin's clearing on a summer evening (CabinVenue, arrangement 1), standing among the
# firs: drawn as MultiMeshes, so low-poly -- a slender trunk with a lean and a kink, a few
# branches up and out of it, and a light, broken crown of leaf clumps hung off the branch ends,
# not one ball. White bark with black lenticel bands. One unit tall, origin at the foot of the
# trunk; the venue scales them.
#
# Materials, swapped by name: "bark" (the white), "mark" (the black bands), "leaves".

import math
import os
import random

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
ORDER = ["bark", "mark", "leaves"]
MATS = [bpy.data.materials.new(n) for n in ORDER]


def limb(bm, points, r0, r1, rnd, sides=6, marks=True):
    """A tapering trunk or branch along `points`; some of its rings painted black."""
    rings = []
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        t = (b - a).normalized()
        n = t.cross(Vector((0, 0, 1)) if abs(t.z) < 0.95 else Vector((1, 0, 0))).normalized()
        m = t.cross(n)
        r = r0 + (r1 - r0) * i / (len(points) - 1)
        rings.append([bm.verts.new(p + (n * math.cos(k * math.tau / sides) + m * math.sin(k * math.tau / sides)) * r)
                      for k in range(sides)])
    for i, (lo, hi) in enumerate(zip(rings, rings[1:])):
        for k in range(sides):
            f = bm.faces.new((lo[k], lo[(k + 1) % sides], hi[(k + 1) % sides], hi[k]))
            # Birch bark: mostly white, with dark horizontal bands and patches.
            f.material_index = 1 if marks and rnd.random() < (0.28 if i < 2 else 0.14) else 0
    # Cap the top.
    top = bm.verts.new(points[-1] + (points[-1] - points[-2]).normalized() * r1)
    for k in range(sides):
        f = bm.faces.new((rings[-1][k], rings[-1][(k + 1) % sides], top))
        f.material_index = 0


def clump(bm, centre, size, rnd):
    """A clump of leaves: a rough, squashed icosphere, its verts jittered so no two read alike."""
    ret = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in ret["verts"]:
        j = rnd.uniform(0.75, 1.2)
        v.co = centre + Vector((v.co.x * size * j, v.co.y * size * j, v.co.z * size * 0.7 * j))
    for f in {f for v in ret["verts"] for f in v.link_faces}:
        f.material_index = 2


def tree(name, seed, x):
    rnd = random.Random(seed)
    bm = bmesh.new()
    lean = Vector((rnd.uniform(-0.06, 0.06), rnd.uniform(-0.06, 0.06), 0))
    steps = 8
    trunk = []
    for k in range(steps + 1):
        t = k / steps
        kink = Vector((math.sin(t * 7.0 + seed) * 0.008, math.cos(t * 5.0 + seed) * 0.008, 0))
        trunk.append(lean * t * t + kink + Vector((0, 0, t * 0.92)))
    limb(bm, trunk, 0.016, 0.004, rnd)
    # Branches from the upper two thirds, rising, each with leaf clumps along and at its end.
    for b in range(rnd.randint(10, 14)):
        t = rnd.uniform(0.3, 0.88)
        at = trunk[0].lerp(trunk[-1], t)
        a = rnd.uniform(0, math.tau)
        out = Vector((math.cos(a), math.sin(a), 0))
        reach = (1.0 - t) * rnd.uniform(0.22, 0.35) + 0.05
        pts = [at + out * reach * s + Vector((0, 0, reach * (0.7 * s - 0.25 * s * s))) for s in (0.0, 0.5, 1.0)]
        limb(bm, pts, 0.006 * (1.0 - t) + 0.002, 0.0015, rnd, 4, False)
        for s in (0.4, 0.75, 1.0):
            p = pts[0].lerp(pts[-1], s) - Vector((0, 0, 0.03))
            clump(bm, p, rnd.uniform(0.07, 0.11) * (1.15 - t * 0.5), rnd)
    # And the leader's crown.
    for k in range(3):
        clump(bm, trunk[-1] + Vector((rnd.uniform(-0.04, 0.04), rnd.uniform(-0.04, 0.04), -0.04 * k)),
              rnd.uniform(0.05, 0.08), rnd)
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in MATS:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = me.materials[p.material_index].name == "leaves"
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.location.x = x
    print("birch", name, len(me.polygons), "faces")


tree("birch_tall", 3, 0.0)
tree("birch_lean", 8, 0.8)
tree("birch_twin", 21, 1.6)
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/cabin_birches.glb"), export_format="GLB")
print("wrote cabin_birches.glb")
