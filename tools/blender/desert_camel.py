# Builds a caravan's camels and writes assets/models/desert_camel.glb.
#
#     blender --background --python tools/blender/desert_camel.py
#
# Seen only far off, against the dawn, so what matters is the silhouette: the long legs, the
# hump, the neck that dips forward and comes up to the head. Two, walking toward Godot -X
# (Blender -X), origin on the ground under the middle, about 2.3 m to the top of the hump:
#   camel_rider   a camel with a rider wrapped in a cloak, sitting behind the hump.
#   camel_pack    a camel loaded with bundles slung either side and a rolled tent on top.
# The legs are set mid-stride, the near pair and the far pair apart, so a line of them reads as
# walking. Materials, which DesertVenue swaps by name: "hide", "cloth", "load".

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
MATS = {n: bpy.data.materials.new(n) for n in ("hide", "cloth", "load")}


def blob(bm, centre, size, mat, subdiv=2):
    ret = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in ret["verts"]:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(centre)
    for f in {f for v in ret["verts"] for f in v.link_faces}:
        f.material_index = mat


def limb(bm, points, radii, mat, segments=7):
    """A tapered tube through `points`."""
    rings = []
    for k, p in enumerate(points):
        p = Vector(p)
        d = (Vector(points[min(k + 1, len(points) - 1)]) - Vector(points[max(k - 1, 0)])).normalized()
        side = d.cross(Vector((0, 1, 0)))
        if side.length < 1e-4:
            side = d.cross(Vector((1, 0, 0)))
        side.normalize()
        up = side.cross(d)
        rings.append([bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * radii[k])
                      for a in (math.tau * s / segments for s in range(segments))])
    for a, b in zip(rings, rings[1:]):
        for s in range(segments):
            bm.faces.new((a[s], a[(s + 1) % segments], b[(s + 1) % segments], b[s])).material_index = mat
    for ring, flip in ((rings[0], True), (rings[-1], False)):
        f = bm.faces.new(list(reversed(ring)) if flip else ring)
        f.material_index = mat


def camel(name, rider):
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for m in ("hide", "cloth", "load"):
        me.materials.append(MATS[m])
    bm = bmesh.new()
    # The body, the hump on it, the chest.
    blob(bm, (0.0, 0.0, 1.55), (0.78, 0.36, 0.36), 0)
    blob(bm, (0.05, 0.0, 1.85), (0.36, 0.26, 0.38), 0)
    blob(bm, (-0.55, 0.0, 1.45), (0.32, 0.3, 0.38), 0)
    # The neck: down and forward from the chest, then up to the head.
    limb(bm, [(-0.7, 0, 1.6), (-1.05, 0, 1.45), (-1.3, 0, 1.55), (-1.45, 0, 1.9), (-1.5, 0, 2.1)],
         [0.2, 0.15, 0.13, 0.11, 0.1], 0)
    # The head: long, nose down a little, ears.
    limb(bm, [(-1.42, 0, 2.12), (-1.62, 0, 2.1), (-1.82, 0, 2.02)], [0.11, 0.09, 0.07], 0)
    for s in (-1, 1):
        limb(bm, [(-1.45, s * 0.06, 2.18), (-1.42, s * 0.09, 2.27)], [0.025, 0.01], 0, 4)
    # The legs, mid-stride: knees, and big flat feet.
    stride = {(-1, -1): 0.25, (-1, 1): -0.2, (1, -1): -0.2, (1, 1): 0.25}
    for fore in (-1, 1):
        x0 = -0.5 if fore < 0 else 0.5
        for s in (-1, 1):
            sw = stride[(fore, s)]
            y = s * 0.2
            hip = (x0, y, 1.4)
            knee = (x0 + sw * 0.5 + (0.05 if fore > 0 else -0.02), y, 0.75)
            foot = (x0 + sw, y, 0.08)
            limb(bm, [hip, knee, foot], [0.13, 0.07, 0.055], 0)
            blob(bm, (foot[0], y, 0.05), (0.1, 0.08, 0.05), 0, 1)
    # The tail.
    limb(bm, [(0.76, 0, 1.6), (0.82, 0, 1.25)], [0.04, 0.02], 0, 4)
    if rider:
        # A saddle blanket, then the rider: a cloaked body, a wrapped head, legs down the side.
        blob(bm, (0.38, 0.0, 1.88), (0.32, 0.4, 0.1), 1)
        limb(bm, [(0.4, 0, 1.9), (0.42, 0, 2.3), (0.38, 0, 2.62)], [0.26, 0.2, 0.13], 1, 9)
        blob(bm, (0.36, 0.0, 2.76), (0.11, 0.11, 0.13), 1)
        for s in (-1, 1):
            limb(bm, [(0.38, s * 0.3, 1.95), (0.3, s * 0.38, 1.6), (0.36, s * 0.36, 1.3)], [0.08, 0.06, 0.05], 1, 6)
        # A camel stick, held up at an angle.
        limb(bm, [(0.2, 0.2, 2.3), (-0.4, 0.3, 2.9)], [0.012, 0.01], 2, 4)
    else:
        # Bundles slung either side, a rolled tent across the top.
        for s in (-1, 1):
            blob(bm, (0.1, s * 0.45, 1.6), (0.36, 0.18, 0.3), 2)
        limb(bm, [(0.1, -0.55, 2.2), (0.1, 0.55, 2.2)], [0.16, 0.16], 1, 10)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    print("%s: %d faces, %s, dims %s" % (name, len(me.polygons), [m.name for m in me.materials],
                                       [round(d, 2) for d in ob.dimensions]))
    return ob


camel("camel_rider", True)
camel("camel_pack", False).location.y = 2.0

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/desert_camel.glb"), export_format="GLB",
                          use_selection=True)
print("wrote desert_camel.glb")
