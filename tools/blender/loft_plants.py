# Builds three potted house plants and writes assets/models/loft_plants.glb.
#
#     blender --background --python tools/blender/loft_plants.py
#
# For the loft's sills on a Sunday morning (LoftVenue, arrangement 1): plants someone keeps in
# the sun of the big windows. Each is its own object, origin at the bottom of its pot, so the
# venue can stand each one alone:
#
#   plant_monstera  a cheese plant: a dozen broad split leaves on arching stalks, in a terracotta
#                   pot 0.2 m across; about 0.55 m tall.
#   plant_snake     a snake plant: stiff sword leaves, banded, standing up out of a glazed pot
#                   0.16 m across; about 0.6 m tall.
#   plant_fern      a Boston fern: thirty narrow fronds arching over and down round a pot 0.18 m
#                   across; about 0.4 m tall and wider than its pot.
#
# Materials, which the venue swaps by name: "pot" (terracotta), "glaze" (the snake plant's
# pot), "soil", "leaf" (the deep green), "leaf_pale" (the fern's and the snake plant's lighter
# green). Leaves are single-sided strips; the venue draws them with culling off.

import math
import os
import random

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

bpy.ops.wm.read_factory_settings(use_empty=True)
MATS = {}
for name, colour in (("pot", (0.6, 0.3, 0.18)), ("glaze", (0.15, 0.25, 0.3)), ("soil", (0.1, 0.07, 0.05)),
                     ("leaf", (0.05, 0.2, 0.06)), ("leaf_pale", (0.2, 0.4, 0.12))):
    m = bpy.data.materials.new(name)
    m.diffuse_color = colour + (1.0,)
    MATS[name] = m
ORDER = ["pot", "glaze", "soil", "leaf", "leaf_pale"]
SEG = 16


def lathe(bm, profile, slot, segments=SEG):
    """Turn a (radius, height) profile round Z; a radius of 0 closes the end."""
    rings = []
    for r, z in profile:
        if r == 0.0:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z))
                      for a in (math.tau * i / segments for i in range(segments))])
    for lower, upper in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            if len(lower) == 1:
                f = bm.faces.new((lower[0], upper[j], upper[i]))
            elif len(upper) == 1:
                f = bm.faces.new((lower[i], lower[j], upper[0]))
            else:
                f = bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
            f.material_index = slot


def pot(bm, radius, tall, slot):
    """A flowerpot: a tapered body, a thick rolled rim, the soil a little down inside it."""
    foot = radius * 0.74
    lathe(bm, [(0.0, 0.0), (foot, 0.0), (radius * 0.92, tall * 0.82), (radius * 0.94, tall * 0.82),
               (radius, tall * 0.84), (radius, tall), (radius * 0.9, tall), (radius * 0.86, tall * 0.9)], slot)
    lathe(bm, [(radius * 0.86, tall * 0.9), (0.0, tall * 0.9 + 0.004)], ORDER.index("soil"))


def strip(bm, points, widths, normals, slot):
    """A leaf as a ribbon: one quad row along `points`, `widths` either side, across `normals`."""
    left, right = [], []
    for p, w, n in zip(points, widths, normals):
        left.append(bm.verts.new(p + n * w))
        right.append(bm.verts.new(p - n * w))
    for i in range(len(points) - 1):
        f = bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))
        f.material_index = slot


def arch(base, heading, rise, reach, droop, steps):
    """Points along an arching stalk: out along `heading`, up by `rise`, falling by `droop` at the tip."""
    out = []
    for k in range(steps + 1):
        t = k / steps
        out.append(base + heading * reach * t + Vector((0, 0, rise * math.sin(t * math.pi * 0.5) - droop * t * t)))
    return out


def monstera(seed):
    rnd = random.Random(seed)
    me = bpy.data.meshes.new("plant_monstera")
    bm = bmesh.new()
    pot(bm, 0.1, 0.17, ORDER.index("pot"))
    top = 0.17 * 0.9
    for i in range(11):
        a = i * 2.4 + rnd.uniform(-0.3, 0.3)
        heading = Vector((math.cos(a), math.sin(a), 0))
        tall = rnd.uniform(0.18, 0.36)
        # The stalk: thin, rising out of the soil and arching over.
        stalk = arch(Vector((0, 0, top)), heading, tall, rnd.uniform(0.04, 0.12), 0.0, 5)
        side = heading.cross(Vector((0, 0, 1)))
        strip(bm, stalk, [0.006] * len(stalk), [side] * len(stalk), ORDER.index("leaf"))
        # The leaf: heart-shaped, broad, tilted out and down from the stalk's end, with the
        # splits a monstera has -- drawn as gaps where the ribbon narrows to nothing.
        tip = stalk[-1]
        size = rnd.uniform(0.13, 0.2)
        tilt = rnd.uniform(0.35, 0.8)
        along = (heading * math.cos(tilt) - Vector((0, 0, math.sin(tilt) * 0.6))).normalized()
        steps = 9
        pts = [tip + along * size * k / steps - Vector((0, 0, 0.25 * size * (k / steps) ** 2)) for k in range(steps + 1)]
        widths = []
        for k in range(steps + 1):
            t = k / steps
            w = size * 0.55 * math.sin(math.pi * min(1.0, t * 1.05 + 0.08)) ** 0.8
            widths.append(max(w, 0.003))
        # Cut the splits: every other segment on the outer half, a narrow waist.
        for k in range(steps):
            t0 = k / steps
            t1 = (k + 1) / steps
            for sign in (1.0, -1.0):
                a0 = pts[k]
                a1 = pts[k + 1]
                n = side * sign
                inner = 0.004
                if k % 2 == 1 and 0.15 < t0 < 0.85:
                    # A split: the outer part of the leaf is missing here; only near the midrib.
                    reach0 = widths[k] * 0.35
                    reach1 = widths[k + 1] * 0.35
                else:
                    reach0 = widths[k]
                    reach1 = widths[k + 1]
                v0 = bm.verts.new(a0 + n * inner)
                v1 = bm.verts.new(a0 + n * reach0 - Vector((0, 0, reach0 * 0.15)))
                v2 = bm.verts.new(a1 + n * reach1 - Vector((0, 0, reach1 * 0.15)))
                v3 = bm.verts.new(a1 + n * inner)
                f = bm.faces.new((v0, v1, v2, v3) if sign > 0 else (v3, v2, v1, v0))
                f.material_index = ORDER.index("leaf")
    return finish(me, bm)


def snake(seed):
    rnd = random.Random(seed)
    me = bpy.data.meshes.new("plant_snake")
    bm = bmesh.new()
    pot(bm, 0.08, 0.15, ORDER.index("glaze"))
    top = 0.15 * 0.9
    for i in range(9):
        a = rnd.uniform(0, math.tau)
        at = Vector((math.cos(a), math.sin(a), 0)) * rnd.uniform(0.0, 0.045)
        lean = Vector((math.cos(a), math.sin(a), 0)) * rnd.uniform(0.02, 0.09)
        tall = rnd.uniform(0.32, 0.55)
        face = Vector((-math.sin(a + rnd.uniform(-1, 1)), math.cos(a + rnd.uniform(-1, 1)), 0)).normalized()
        steps = 7
        pts = [Vector((at.x, at.y, top)) + lean * (k / steps) ** 2 + Vector((0, 0, tall * k / steps)) for k in range(steps + 1)]
        widths = [0.026 * math.sin(math.pi * (0.15 + 0.85 * (1 - k / steps)) * 0.5 + 0.2) * (1 - (k / steps) ** 3) + 0.001
                  for k in range(steps + 1)]
        # A slight twist up the blade.
        normals = [(Matrix.Rotation(0.5 * k / steps, 3, "Z") @ face) for k in range(steps + 1)]
        strip(bm, pts, widths, normals, ORDER.index("leaf") if i % 3 else ORDER.index("leaf_pale"))
    return finish(me, bm)


def fern(seed):
    rnd = random.Random(seed)
    me = bpy.data.meshes.new("plant_fern")
    bm = bmesh.new()
    pot(bm, 0.09, 0.15, ORDER.index("pot"))
    top = 0.15 * 0.9
    for i in range(30):
        a = i * 2.39996 + rnd.uniform(-0.2, 0.2)
        heading = Vector((math.cos(a), math.sin(a), 0))
        side = heading.cross(Vector((0, 0, 1)))
        up = rnd.uniform(0.12, 0.28)
        pts = arch(Vector((0, 0, top)) + heading * 0.02, heading, up, rnd.uniform(0.2, 0.32), up * 1.5, 8)
        # Frond: wide at the middle, a fringe made by zig-zagging the width.
        widths = [0.03 * math.sin(math.pi * k / 8) * (0.7 if k % 2 else 1.0) + 0.001 for k in range(9)]
        strip(bm, pts, widths, [side] * 9, ORDER.index("leaf_pale"))
    return finish(me, bm)


def finish(me, bm):
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for name in ORDER:
        me.materials.append(MATS[name])
    ob = bpy.data.objects.new(me.name, me)
    bpy.context.collection.objects.link(ob)
    print(me.name, len(me.polygons), "faces")
    return ob


monstera(5).location.x = 0.0
snake(9).location.x = 0.5
fern(13).location.x = 1.0
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/loft_plants.glb"), export_format="GLB")
print("wrote loft_plants.glb")
