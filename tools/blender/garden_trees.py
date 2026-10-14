# Builds the temple garden's trees and writes assets/models/garden_trees.glb.
#
#     blender --background --python tools/blender/garden_trees.py
#
# Grown, not drawn: each tree's limbs are tapered tubes branching recursively from its trunk,
# and its crown is lumpy clumps at the ends of the finest twigs, so the same tree can be in
# blossom, in autumn leaf, or bare (the venue leaves the crown's surface out in winter). Real
# size, in metres, origin at the foot of the trunk; the venue scales a little for variety and
# draws each kind as a MultiMesh. Materials, swapped by the venue by name: "bark" and
# "crown" (or "needles" for the conifers).
#
#   CherryA, CherryB   Yoshino cherries: a short trunk splitting into a few heavy limbs that
#                      spread wide into a flat-topped umbrella, about 6 m tall and 9 m across.
#   MapleA, MapleB     Japanese maples: several stems, fine twigs in layered tiers, 5 m tall.
#   Pine               a clipped black pine (niwaki): an S-curved leaning trunk, its branches
#                      held out level and each ending in a flat cloud of needles, 4.5 m.
#   Sugi               a cryptomeria for the hills: a straight trunk and a narrow jagged cone,
#                      1 unit tall (the venue scales it 14-26 m).
#   Round              a far broadleaf tree for the hills, three lumps on a stub, 1 unit tall.

import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
mats = {}
for n, c in {"bark": (0.2, 0.15, 0.12), "crown": (1.0, 0.75, 0.82), "needles": (0.08, 0.18, 0.08)}.items():
    m = bpy.data.materials.new(n)
    m.diffuse_color = (*c, 1)
    mats[n] = m
x_cursor = [0.0]


def finish(bm, name, names, smooth=50):
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for n in names:
        me.materials.append(mats[n])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth))
    ob.location.x = x_cursor[0]
    x_cursor[0] += 12.0
    print("%s: %d faces" % (name, len(me.polygons)))
    return ob


def tube(bm, pts, radii, sides, index):
    """A tapered tube through `pts`, radius `radii[i]` at each, capped at its tip."""
    rings = []
    prev_side = None
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        tan = (b - a).normalized()
        ref = Vector((0, 0, 1)) if abs(tan.z) < 0.95 else Vector((1, 0, 0))
        side = prev_side if prev_side is not None else tan.cross(ref).normalized()
        # Keep the ring from twisting: project the last side onto this ring's plane.
        side = (side - tan * side.dot(tan)).normalized()
        prev_side = side
        up = tan.cross(side).normalized()
        rings.append([bm.verts.new(p + (side * math.cos(math.tau * k / sides) + up * math.sin(math.tau * k / sides))
                                   * radii[i]) for k in range(sides)])
    for i in range(len(rings) - 1):
        for k in range(sides):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
            f.material_index = index
    f = bm.faces.new(rings[-1])
    f.material_index = index


def clump(bm, at, size, index, seed, subdiv=2, jag=0.28):
    """A lump of crown: an icosphere pushed about by noise, `size` = (rx, ry, rz)."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    off = Vector((seed * 1.7, seed * 2.9, seed * 0.7))
    for v in res["verts"]:
        n = v.co.normalized()
        d = 1.0 + jag * noise.noise(n * 2.2 + off) + jag * 0.5 * noise.noise(n * 5.0 + off)
        v.co = Vector((at[0] + n.x * size[0] * d, at[1] + n.y * size[1] * d, at[2] + n.z * size[2] * d))
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = index


def grow(bm, rnd, base, direction, length, radius, depth, spec, ends):
    """One limb and, recursively, what branches off its end. Tips collect in `ends`."""
    segs = max(2, int(length / 0.45))
    pts = [Vector(base)]
    d = direction.normalized()
    for i in range(segs):
        # A little wander, and the droop or lift the species carries.
        d = (d + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.5, 0.5))) * spec["wander"]
             + Vector((0, 0, spec["lift"] * (1.0 - depth / spec["depth"])))).normalized()
        pts.append(pts[-1] + d * (length / segs))
    radii = [radius * (1.0 - 0.45 * i / segs) for i in range(segs + 1)]
    tube(bm, pts, radii, spec["sides"] if depth < 2 else 4, 0)
    tip = pts[-1]
    if depth >= spec["depth"]:
        ends.append((tip, d))
        return
    kids = rnd.randint(*spec["kids"])
    for k in range(kids):
        yaw = math.tau * (k + rnd.uniform(-0.3, 0.3)) / kids
        # Out from the parent's line by the species' angle, round it by `yaw`.
        perp = d.cross(Vector((0, 0, 1)))
        if perp.length < 1e-4:
            perp = Vector((1, 0, 0))
        perp.normalize()
        perp = Matrix.Rotation(yaw, 3, d) @ perp
        ang = math.radians(rnd.uniform(*spec["angle"]))
        nd = (d * math.cos(ang) + perp * math.sin(ang)).normalized()
        nd.z = nd.z * spec["flatten"] + spec["level"]
        grow(bm, rnd, tip - d * 0.05, nd, length * rnd.uniform(*spec["shrink"]), radii[-1] * spec["thin"],
             depth + 1, spec, ends)


def broadleaf(name, seed, spec, clumps):
    rnd = random.Random(seed)
    bm = bmesh.new()
    ends = []
    for trunk in spec["trunks"]:
        lean = Vector(trunk[0]).normalized()
        grow(bm, rnd, Vector((trunk[2][0], trunk[2][1], 0.0)), lean, trunk[1], spec["radius"] * trunk[3], 0, spec,
             ends)
    for i, (tip, d) in enumerate(ends):
        s = rnd.uniform(*clumps["size"])
        clump(bm, tip + Vector((0, 0, clumps["rise"] * s)), (s, s, s * clumps["flat"]), 1, seed * 31 + i,
              subdiv=clumps["subdiv"])
        if clumps.get("extra") and rnd.random() < clumps["extra"]:
            # A second lump beside the first, so the crown is not a string of beads.
            off = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.3, 0.2))) * s
            clump(bm, tip + off, (s * 0.8, s * 0.8, s * 0.8 * clumps["flat"]), 1, seed * 37 + i,
                  subdiv=clumps["subdiv"])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    return finish(bm, name, ["bark", "crown"])


CHERRY = {"wander": 0.12, "lift": 0.05, "depth": 3, "kids": (2, 3), "angle": (28, 46), "flatten": 0.6,
          "level": 0.08, "shrink": (0.62, 0.8), "thin": 0.62, "sides": 8, "radius": 0.24}
MAPLE = {"wander": 0.16, "lift": 0.02, "depth": 4, "kids": (2, 3), "angle": (30, 55), "flatten": 0.45,
         "level": 0.05, "shrink": (0.6, 0.78), "thin": 0.62, "sides": 6, "radius": 0.13}

broadleaf("CherryA", 3, dict(CHERRY, trunks=[((0.5, 0.1, 1.0), 2.4, (0, 0), 1.0), ((-0.6, 0.3, 1.0), 2.1, (0.05, 0), 0.85),
                                             ((0.0, -0.7, 1.0), 2.2, (0, 0.05), 0.8)]),
          {"size": (0.75, 1.15), "rise": 0.25, "flat": 0.62, "subdiv": 2, "extra": 0.45})
broadleaf("CherryB", 8, dict(CHERRY, trunks=[((0.3, 0.4, 1.0), 2.6, (0, 0), 1.0), ((-0.5, -0.3, 1.0), 2.3, (0.05, 0), 0.9)]),
          {"size": (0.75, 1.15), "rise": 0.25, "flat": 0.62, "subdiv": 2, "extra": 0.45})
broadleaf("MapleA", 5, dict(MAPLE, trunks=[((0.2, 0.1, 1.0), 2.0, (0, 0), 1.0), ((-0.35, 0.2, 1.0), 1.8, (0.08, 0.02), 0.75),
                                           ((0.1, -0.4, 1.0), 1.9, (-0.04, 0.06), 0.7)]),
          {"size": (0.45, 0.7), "rise": 0.1, "flat": 0.45, "subdiv": 1, "extra": 0.3})
broadleaf("MapleB", 12, dict(MAPLE, trunks=[((0.4, -0.2, 1.0), 2.2, (0, 0), 1.0), ((-0.3, -0.1, 1.0), 1.7, (0.06, 0.04), 0.8)]),
          {"size": (0.45, 0.7), "rise": 0.1, "flat": 0.45, "subdiv": 1, "extra": 0.3})

# --- the clipped pine ------------------------------------------------------------------------
rnd = random.Random(21)
bm = bmesh.new()
trunk = []
for i in range(12):
    t = i / 11
    trunk.append(Vector((0.9 * math.sin(t * 2.6) * (1 - t * 0.3), 0.35 * math.sin(t * 4.0), 4.0 * t)))
tube(bm, trunk, [0.2 * (1 - 0.6 * i / 11) for i in range(12)], 8, 0)
pads = []
for k, t in enumerate([0.32, 0.45, 0.56, 0.66, 0.76, 0.86]):
    at = trunk[int(t * 11)]
    yaw = k * 2.4 + rnd.uniform(-0.3, 0.3)
    reach = rnd.uniform(1.0, 1.7) * (1.15 - t * 0.6)
    out = Vector((math.cos(yaw), math.sin(yaw), 0))
    pts = [at, at + out * reach * 0.5 + Vector((0, 0, 0.12)), at + out * reach + Vector((0, 0, 0.05))]
    tube(bm, pts, [0.08 * (1.1 - t), 0.06 * (1.1 - t), 0.04], 6, 0)
    pads.append((pts[-1] + Vector((0, 0, 0.12)), rnd.uniform(0.7, 1.05) * (1.2 - t * 0.5)))
pads.append((trunk[-1] + Vector((0, 0, 0.1)), 0.8))
for i, (at, s) in enumerate(pads):
    # A cloud of needles: broad and flat, its top lumpy, its underside nearly level -- a ring of
    # small clumps round a bigger one, all squashed.
    clump(bm, at, (s * 0.7, s * 0.62, s * 0.3), 1, 70 + i, subdiv=2, jag=0.22)
    for k in range(6):
        a = math.tau * k / 6 + i
        off = Vector((math.cos(a) * s * 0.55, math.sin(a) * s * 0.48, -s * 0.04 + rnd.uniform(-0.04, 0.06)))
        r = s * rnd.uniform(0.38, 0.5)
        clump(bm, at + off, (r, r, r * 0.5), 1, 90 + i * 7 + k, subdiv=1, jag=0.3)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
finish(bm, "Pine", ["bark", "needles"], smooth=60)

# --- the cryptomeria for the hills ------------------------------------------------------------
bm = bmesh.new()
tube(bm, [Vector((0, 0, 0)), Vector((0, 0, 0.3))], [0.03, 0.025], 6, 0)
apex = 1.0
for tier in range(6):
    k = tier / 5
    y = 0.15 + 0.7 * k
    r = 0.2 * (1 - k * 0.8)
    h = 0.32 * (1 - k * 0.4)
    top = bm.verts.new((0, 0, min(y + h, apex)))
    rim = []
    for i in range(14):
        a = math.tau * i / 14 + tier
        rr = r * (1.0 if i % 2 == 0 else 0.7)
        rim.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, y - (0.03 if i % 2 == 0 else 0))))
    for i in range(14):
        f = bm.faces.new((top, rim[i], rim[(i + 1) % 14]))
        f.material_index = 1
    under = bm.verts.new((0, 0, y + h * 0.2))
    for i in range(14):
        f = bm.faces.new((under, rim[(i + 1) % 14], rim[i]))
        f.material_index = 1
finish(bm, "Sugi", ["bark", "needles"], smooth=30)

# --- the far broadleaf -----------------------------------------------------------------------
bm = bmesh.new()
tube(bm, [Vector((0, 0, 0)), Vector((0, 0, 0.35))], [0.04, 0.03], 6, 0)
for i, (at, s) in enumerate([((0, 0, 0.55), 0.32), ((0.2, 0.08, 0.45), 0.24), ((-0.17, -0.1, 0.48), 0.25),
                             ((0.02, 0.0, 0.78), 0.2)]):
    clump(bm, at, (s, s, s * 0.85), 1, 50 + i, subdiv=1, jag=0.18)
finish(bm, "Round", ["bark", "crown"], smooth=60)

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/garden_trees.glb"), export_format="GLB")
print("wrote garden_trees.glb")
