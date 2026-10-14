# Builds the desert's plants and writes assets/models/desert_flora.glb.
#
#     blender --background --python tools/blender/desert_flora.py
#
# Low-poly, for drawing many of each as MultiMeshes (DesertVenue). Each at its real size, origin
# at its foot:
#   date_palm     a date palm, 8.5 m: a leaning trunk, ringed with the stubs of old fronds, a
#                 crown of eighteen arching fronds each a folded ribbon toothed with leaflets,
#                 and hanging bunches of dates under them.
#   saguaro       a saguaro cactus, 5 m: a ribbed column, round-topped, with three arms that
#                 bend up.
#   prickly_pear  a prickly pear, 1.2 m: flat oval pads growing out of each other's rims.
#   agave         a spiky rosette, 0.9 m across.
#   reeds         a clump of reeds and bulrushes, 2.2 m: narrow blades and brown heads.
#   scrub         a low dry bush, 0.8 m, a tangle of twigs read as a lumpy ball.
# Materials, which the venue swaps by name: "trunk", "frond", "dates", "cactus", "reed",
# "bulrush", "scrub".

import math
import os
import random

import bpy
import bmesh
from mathutils import Euler, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
MATS = {n: bpy.data.materials.new(n) for n in ("trunk", "frond", "dates", "cactus", "reed", "bulrush", "scrub")}


def new_object(name, mats):
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for m in mats:
        me.materials.append(MATS[m])
    return ob, bmesh.new()


def finish(ob, bm, x, smooth=True):
    bm.normal_update()
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = smooth
    ob.location.x = x
    print("%s: %d faces, %s, dims %s" % (ob.name, len(ob.data.polygons), [m.name for m in ob.data.materials],
                                       [round(d, 2) for d in ob.dimensions]))


def sweep(bm, spine, radius, segments, mat, cap=True, ribs=0, rib_depth=0.0):
    """A tube along `spine` (points), radius(t, angle) at each, closed at the top if `cap`."""
    rings = []
    for k, p in enumerate(spine):
        t = k / (len(spine) - 1)
        if k == 0:
            d = spine[1] - spine[0]
        elif k == len(spine) - 1:
            d = spine[-1] - spine[-2]
        else:
            d = spine[k + 1] - spine[k - 1]
        d.normalize()
        side = d.cross(Vector((0, 1, 0)))
        if side.length < 1e-4:
            side = d.cross(Vector((1, 0, 0)))
        side.normalize()
        up = side.cross(d).normalized()
        ring = []
        for s in range(segments):
            a = math.tau * s / segments
            r = radius(t, a)
            if ribs:
                r *= 1.0 - rib_depth * (0.5 - 0.5 * math.cos(a * ribs))
            ring.append(bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * r))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for s in range(segments):
            f = bm.faces.new((a[s], a[(s + 1) % segments], b[(s + 1) % segments], b[s]))
            f.material_index = mat
    if cap:
        tip = bm.verts.new(spine[-1] + (spine[-1] - spine[-2]).normalized() * radius(1.0, 0.0) * 0.6)
        for s in range(segments):
            f = bm.faces.new((rings[-1][s], rings[-1][(s + 1) % segments], tip))
            f.material_index = mat
    return rings


def blob(bm, centre, size, mat, seed, subdiv=1, rough=0.2):
    ret = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in ret["verts"]:
        n = noise.noise(v.co * 1.7 + Vector((seed * 3.1, seed * 1.3, 0)))
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) * (1.0 + rough * n) + Vector(centre)
    for f in {f for v in ret["verts"] for f in v.link_faces}:
        f.material_index = mat


def frond(bm, base, yaw, rise, length, droop, width, mat, rnd):
    """A pinnate frond: a ribbon along an arching rachis, folded in a shallow V, its two edges
    toothed so it reads as leaflets against the sky."""
    n = 14
    pts = []
    for k in range(n + 1):
        t = k / n
        # Out and up, then over and down: a parabola in the frond's own plane.
        out = length * t
        up = length * (rise * t - droop * t * t)
        pts.append(Vector((math.cos(yaw) * out, math.sin(yaw) * out, up)) + base)
    side = Vector((-math.sin(yaw), math.cos(yaw), 0.0))
    prev = None
    for k, p in enumerate(pts):
        t = k / n
        w = width * math.sin(math.pi * min(1.0, t * 1.15)) ** 0.6 * (1.0 if t > 0.08 else t / 0.08)
        tooth = 1.0 + (0.35 if k % 2 else -0.25)
        fold = Vector((0, 0, -0.18 * w))
        row = (bm.verts.new(p + side * w * tooth + fold), bm.verts.new(p + Vector((0, 0, 0.01))),
               bm.verts.new(p - side * w * tooth + fold))
        if prev:
            for a, b in ((0, 1), (1, 2)):
                f = bm.faces.new((prev[a], prev[b], row[b], row[a]))
                f.material_index = mat
        prev = row


# --- date palm ----------------------------------------------------------------------------------
rnd = random.Random(3)
ob, bm = new_object("date_palm", ["trunk", "frond", "dates"])
TALL = 8.5
spine = [Vector((0.35 * (k / 12) ** 1.8, 0.0, TALL * k / 12)) for k in range(13)]
sweep(bm, spine, lambda t, a: 0.24 - 0.06 * t + 0.03 * (t < 0.04), 10, 0, cap=False)
# The old frond bases: a lattice of stubs up the trunk, as little scales sticking out.
for k in range(1, 40):
    t = k / 40
    z = TALL * t * 0.97
    c = Vector((0.35 * t ** 1.8, 0.0, z))
    for s in range(5):
        a = s * math.tau / 5 + k * 0.62
        out = Vector((math.cos(a), math.sin(a), 0.0))
        r = 0.24 - 0.06 * t
        v0 = bm.verts.new(c + out * r * 0.92 + Vector((0, 0, -0.06)))
        v1 = bm.verts.new(c + out * r * 0.92 + Vector((0, 0, 0.12)) + Vector((-out.y, out.x, 0)) * 0.07)
        v2 = bm.verts.new(c + out * (r + 0.08) + Vector((0, 0, 0.1)))
        bm.faces.new((v0, v1, v2)).material_index = 0
crown = spine[-1] + Vector((0, 0, 0.1))
# The crown: three tiers of fronds, the young ones upright, the old ones drooping.
for k in range(18):
    tier = k % 3
    yaw = k * 2.4 + rnd.uniform(-0.15, 0.15)
    rise = [1.25, 0.8, 0.45][tier]
    droop = [0.85, 1.05, 1.15][tier]
    frond(bm, crown, yaw, rise, rnd.uniform(3.2, 3.9), droop, 0.32, 1, rnd)
# Bunches of dates hanging under the crown.
for k in range(4):
    a = k * math.tau / 4 + 0.5
    c = crown + Vector((math.cos(a) * 0.45, math.sin(a) * 0.45, -0.75))
    blob(bm, c, (0.22, 0.22, 0.42), 2, k, 1, 0.3)
finish(ob, bm, 0.0)

# --- saguaro ------------------------------------------------------------------------------------
ob, bm = new_object("saguaro", ["cactus"])
TALL = 5.0
spine = [Vector((0, 0, TALL * k / 10)) for k in range(11)]
sweep(bm, spine, lambda t, a: 0.3 * (1.0 - 0.15 * t), 24, 0, ribs=12, rib_depth=0.12)
for side, at, reach, up in ((1, 1.7, 0.75, 1.6), (-1, 2.3, 0.6, 1.4), (1, 2.9, 0.5, 1.0)):
    yaw = 0.0 if side > 0 else math.pi
    yaw += 0.6 * (at - 2.3)
    d = Vector((math.cos(yaw), math.sin(yaw), 0.0))
    pts = []
    for k in range(9):
        t = k / 8
        # Out level, round a knee, and straight up.
        if t < 0.4:
            q = d * reach * (t / 0.4) * 0.8
            z = at + 0.15 * t
        else:
            u = (t - 0.4) / 0.6
            q = d * (reach * 0.8 + reach * 0.2 * math.sin(u * math.pi * 0.5))
            z = at + 0.06 + up * u
        pts.append(q + Vector((0, 0, z)))
    sweep(bm, pts, lambda t, a: 0.18 * (1.0 - 0.1 * t), 16, 0, ribs=10, rib_depth=0.12)
finish(ob, bm, 3.0)

# --- prickly pear -------------------------------------------------------------------------------
ob, bm = new_object("prickly_pear", ["cactus"])
rnd = random.Random(9)


def pad(c, yaw, tilt, size, depth=0):
    ret = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    rot = Euler((tilt, 0.0, yaw))
    for v in ret["verts"]:
        co = Vector((v.co.x * size * 0.75, v.co.y * size * 0.12, v.co.z * size))
        co.rotate(rot)
        v.co = co + c
    for f in {f for v in ret["verts"] for f in v.link_faces}:
        f.material_index = 0
    if depth < 3:
        top = c + Vector((0, 0, size * 0.85))
        top.rotate(Euler((0, 0, 0)))
        for k in range(rnd.choice((1, 2, 2))):
            off = Vector((math.cos(yaw) * rnd.uniform(-0.6, 0.6) * size, math.sin(yaw) * rnd.uniform(-0.6, 0.6) * size,
                          0.0))
            pad(top + off + Vector((0, 0, size * 0.55)), yaw + rnd.uniform(-1.0, 1.0), rnd.uniform(-0.4, 0.4),
                size * 0.85, depth + 1)


pad(Vector((0, 0, 0.22)), 0.0, 0.0, 0.24)
pad(Vector((0.2, 0.1, 0.2)), 1.3, 0.3, 0.22, 1)
finish(ob, bm, 5.0)

# --- agave --------------------------------------------------------------------------------------
ob, bm = new_object("agave", ["cactus"])
for k in range(22):
    a = k * 2.399
    ring = k / 22
    tilt = 0.25 + 0.9 * ring
    length = 0.5 - 0.15 * (1 - ring)
    d = Vector((math.cos(a) * math.sin(tilt), math.sin(a) * math.sin(tilt), math.cos(tilt)))
    side = Vector((-math.sin(a), math.cos(a), 0.0))
    base = Vector((0, 0, 0.05))
    v0 = bm.verts.new(base + side * 0.06)
    v1 = bm.verts.new(base - side * 0.06)
    v2 = bm.verts.new(base + d * length * 0.5 + side * 0.045)
    v3 = bm.verts.new(base + d * length * 0.5 - side * 0.045)
    v4 = bm.verts.new(base + d * length)
    for f in ((v0, v1, v3, v2), (v2, v3, v4)):
        bm.faces.new(f).material_index = 0
finish(ob, bm, 6.0, smooth=False)

# --- reeds --------------------------------------------------------------------------------------
ob, bm = new_object("reeds", ["reed", "bulrush"])
rnd = random.Random(21)
for k in range(46):
    r = math.sqrt(rnd.random()) * 0.45
    a = rnd.random() * math.tau
    base = Vector((math.cos(a) * r, math.sin(a) * r, 0.0))
    tall = rnd.uniform(1.1, 2.2)
    lean = Vector((math.cos(a) * rnd.uniform(0.05, 0.3), math.sin(a) * rnd.uniform(0.05, 0.3), 0.0))
    yaw = rnd.random() * math.tau
    side = Vector((math.cos(yaw), math.sin(yaw), 0.0)) * 0.012
    prev = None
    for s in range(5):
        t = s / 4
        p = base + lean * t * t + Vector((0, 0, tall * t))
        w = 1.0 - t
        row = (bm.verts.new(p + side * w), bm.verts.new(p - side * w))
        if prev:
            bm.faces.new((prev[0], prev[1], row[1], row[0])).material_index = 0
        prev = row
    if k % 4 == 0:
        # A bulrush head on a stem: a brown cylinder near the top.
        top = base + lean * 0.8 + Vector((0, 0, tall * 0.88))
        ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.022, radius2=0.022, depth=0.16)
        for v in ret["verts"]:
            v.co += top
        for f in {f for v in ret["verts"] for f in v.link_faces}:
            f.material_index = 1
finish(ob, bm, 7.0, smooth=False)

# --- scrub --------------------------------------------------------------------------------------
ob, bm = new_object("scrub", ["scrub"])
for k in range(5):
    a = k * 1.3
    blob(bm, (math.cos(a) * 0.18, math.sin(a) * 0.18, 0.22 + 0.06 * (k % 2)), (0.24, 0.24, 0.2), 0, k + 10, 1, 0.45)
finish(ob, bm, 8.0, smooth=False)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/desert_flora.glb"), export_format="GLB",
                          use_selection=True)
print("wrote desert_flora.glb")
