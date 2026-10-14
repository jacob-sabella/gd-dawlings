# Builds the temple garden's props and writes assets/models/garden_props.glb.
#
#     blender --background --python tools/blender/garden_props.py
#
# Each object stands on its own origin (its foot, on the ground), in metres, the way GardenVenue
# places it. Godot -Z is Blender +Y. Objects, and the materials the venue swaps by name:
#
#   Toro       a Kasuga stone lantern, 2.3 m: hexagonal base, round pillar, platform, a fire box
#              with its windows lit ("stone", "light").
#   Yukimi     a snow-viewing lantern, 1.25 m, on three curved legs under a wide round cap
#              ("stone", "light").
#   Chochin    a paper lantern, 0.5 m, ribbed, black lacquer caps and a cord; origin at the top of
#              the cord ("paper", "lacquer").
#   Tsuri      a hanging bronze lantern, 0.62 m, hexagonal, its fretwork lit; origin at the top
#              of its ring ("bronze", "light").
#   Bridge     a vermilion drum bridge (taikobashi), 7.2 m along X, 1.9 m wide, its crown 1.45 m
#              over the banks: lacquered girders, posts and rails with bronze caps (giboshi), a
#              plank deck, round piers down into the water, stone abutments ("lacquer", "deck",
#              "bronze", "stone").
#   Torii      a shrine gate, 7.6 m, pillars 5.4 m apart, its top beam sweeping up at the ends
#              ("lacquer", "black").
#   Gate       a temple gate's frame: two posts and their tie beams, under the venue's own roof
#              ("timber").
#   Rock0..3   garden stones: a tall standing one, a broad reclining one, a low flat one, and a
#              stepping stone ("stone").
#   Shrub      a clipped azalea mound, about 1 m across ("shrub").
#   Koi        a carp, 1 m long nose to tail along +X, for the koi shader ("koi").
#   Petal      a cherry petal, 1 unit across, cupped ("petal").
#   Leaf       a maple leaf, 1 unit across, seven-lobed ("leaf").

import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(7)

COLOURS = {
    "stone": (0.5, 0.5, 0.47), "light": (1.0, 0.8, 0.5), "paper": (0.95, 0.88, 0.75),
    "lacquer": (0.75, 0.15, 0.08), "bronze": (0.35, 0.3, 0.2), "deck": (0.5, 0.38, 0.26),
    "black": (0.05, 0.05, 0.05), "timber": (0.35, 0.25, 0.17), "shrub": (0.12, 0.25, 0.1),
    "koi": (1, 0.5, 0.2), "petal": (1, 0.8, 0.85), "leaf": (0.8, 0.2, 0.1),
}
mats = {}
for n, c in COLOURS.items():
    m = bpy.data.materials.new(n)
    m.diffuse_color = (*c, 1)
    mats[n] = m

x_cursor = [0.0]


def finish(bm, name, names, smooth=40, flat=False):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for n in names:
        me.materials.append(mats[n])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = not flat
    if not flat:
        bpy.context.view_layer.objects.active = ob
        for o in bpy.context.scene.objects:
            o.select_set(o == ob)
        bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth))
    # Laid out in a row in the file, so they are easy to look at; the venue uses each mesh at
    # its own origin.
    ob.location.x = x_cursor[0]
    x_cursor[0] += 8.0
    print("%s: %d faces" % (name, len(me.polygons)))
    return ob


def tag(faces, index):
    for f in faces:
        f.material_index = index


def faces_of(res):
    return {f for v in res["verts"] for f in v.link_faces}


def prism(bm, sides, r1, r2, z0, z1, index, rot=0.0, centre=(0, 0)):
    """A tapered prism or cylinder from z0 to z1."""
    m = Matrix.Translation((centre[0], centre[1], (z0 + z1) / 2)) @ Matrix.Rotation(rot, 4, "Z")
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=r1, radius2=r2, depth=z1 - z0,
                                matrix=m)
    tag(faces_of(res), index)
    return res


def lathe(bm, profile, sides, index, rot=0.0, radial=None):
    """Revolve (r, z) points round Z; `radial(a, r, z)` may bend each radius."""
    rings = []
    for r, z in profile:
        ring = []
        for s in range(sides):
            a = rot + math.tau * s / sides
            rr = radial(a, r, z) if radial else r
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), z)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(sides):
            f = bm.faces.new((rings[i][s], rings[i][(s + 1) % sides], rings[i + 1][(s + 1) % sides],
                              rings[i + 1][s]))
            f.material_index = index
    for ring, top in ((rings[0], False), (rings[-1], True)):
        if profile[0 if not top else -1][0] > 1e-5:
            f = bm.faces.new(ring if top else list(reversed(ring)))
            f.material_index = index
    return rings


def box(bm, size, at, index, rot=None):
    m = Matrix.Translation(at)
    if rot is not None:
        m = m @ rot
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=m @ Matrix.Diagonal((*size, 1.0)))
    tag(faces_of(res), index)
    return res


def sweep(bm, path, section, index, up=(0, 0, 1), caps=True):
    pts = [Vector(p) for p in path]
    upv = Vector(up)
    rings = []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        tan = (b - a).normalized()
        side = tan.cross(upv)
        if side.length < 1e-6:
            side = Vector((1, 0, 0))
        side.normalize()
        vert = side.cross(tan).normalized()
        rings.append([bm.verts.new(p + side * s + vert * u) for s, u in section])
    n = len(section)
    for i in range(len(rings) - 1):
        for k in range(n):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % n], rings[i + 1][(k + 1) % n], rings[i + 1][k]))
            f.material_index = index
    if caps:
        f = bm.faces.new(list(reversed(rings[0])))
        f.material_index = index
        f = bm.faces.new(rings[-1])
        f.material_index = index
    return rings


def circle(r, n=8):
    return [(r * math.cos(math.tau * k / n), r * math.sin(math.tau * k / n)) for k in range(n)]


def rect(w, h):
    return [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]


def hex_roof(bm, r, z, h, curl, index, sides=6, thick=0.05):
    """A lantern's cap: a hexagonal (or round) shallow pyramid whose corners curl up."""
    rings = []
    for k, (rr, zz) in enumerate([(r, z), (r * 0.82, z + h * 0.22), (r * 0.5, z + h * 0.62), (r * 0.16, z + h)]):
        ring = []
        for s in range(sides * 2):
            a = math.tau * s / (sides * 2)
            corner = s % 2 == 0
            lift = curl if corner and k == 0 else (curl * 0.35 if corner and k == 1 else 0.0)
            reach = rr * (1.0 if corner or sides > 8 else math.cos(math.pi / sides))
            ring.append(bm.verts.new((reach * math.cos(a), reach * math.sin(a), zz + lift)))
        rings.append(ring)
    under = [bm.verts.new((v.co.x * 0.92, v.co.y * 0.92, v.co.z - thick)) for v in rings[0]]
    n = sides * 2
    all_rings = [under] + rings
    for i in range(len(all_rings) - 1):
        for s in range(n):
            f = bm.faces.new((all_rings[i][s], all_rings[i][(s + 1) % n], all_rings[i + 1][(s + 1) % n],
                              all_rings[i + 1][s]))
            f.material_index = index
    f = bm.faces.new(list(reversed(under)))
    f.material_index = index
    f = bm.faces.new(rings[-1])
    f.material_index = index


def hoju(bm, z, r, index):
    """The jewel on top: a lotus collar and an onion-pointed knob."""
    lathe(bm, [(r * 0.6, z), (r * 1.0, z + r * 0.35), (r * 0.7, z + r * 0.6), (r * 0.9, z + r * 1.1),
               (r * 0.95, z + r * 1.5), (r * 0.6, z + r * 2.0), (r * 0.15, z + r * 2.45), (0.0, z + r * 2.6)],
          12, index)


# --- Toro: the Kasuga lantern --------------------------------------------------------------
bm = bmesh.new()
S, L = 0, 1
prism(bm, 6, 0.36, 0.33, 0.0, 0.12, S)                       # foot
lathe(bm, [(0.3, 0.12), (0.26, 0.2), (0.17, 0.26), (0.13, 0.3)], 6, S)  # lotus base
prism(bm, 16, 0.12, 0.11, 0.3, 1.05, S)                       # pillar
prism(bm, 16, 0.14, 0.14, 0.62, 0.66, S)                      # its band
lathe(bm, [(0.13, 1.05), (0.2, 1.1), (0.28, 1.16), (0.3, 1.24), (0.29, 1.28)], 6, S)  # platform
# The fire box: six posts with openings between, the front and back lit (paper in a stone frame).
for k in range(6):
    a = math.tau * k / 6
    box(bm, (0.07, 0.07, 0.4), (0.21 * math.cos(a), 0.21 * math.sin(a), 1.48), S,
        rot=Matrix.Rotation(a, 4, "Z"))
prism(bm, 6, 0.19, 0.19, 1.3, 1.66, L)                        # the lit core, set back
box(bm, (0.48, 0.48, 0.05), (0, 0, 1.31), S, rot=Matrix.Rotation(0.0, 4, "Z"))
box(bm, (0.46, 0.46, 0.05), (0, 0, 1.68), S)
hex_roof(bm, 0.5, 1.7, 0.32, 0.09, S)
hoju(bm, 2.02, 0.08, S)
finish(bm, "Toro", ["stone", "light"])

# --- Yukimi: the snow-viewing lantern ------------------------------------------------------
bm = bmesh.new()
for k in range(3):
    a = math.tau * k / 3 + 0.5
    path = []
    for q in range(7):
        t = q / 6
        r = 0.55 - 0.32 * t + 0.08 * math.sin(t * math.pi)
        path.append((r * math.cos(a), r * math.sin(a), 0.62 * t))
    sweep(bm, path, circle(0.05, 8), S, up=(math.cos(a + 1.57), math.sin(a + 1.57), 0))
lathe(bm, [(0.3, 0.6), (0.34, 0.64), (0.34, 0.7), (0.26, 0.74)], 12, S)  # the leg ring / platform
for k in range(4):
    a = math.tau * k / 4 + math.pi / 4
    box(bm, (0.07, 0.07, 0.28), (0.2 * math.cos(a), 0.2 * math.sin(a), 0.88), S,
        rot=Matrix.Rotation(a, 4, "Z"))
prism(bm, 4, 0.2, 0.2, 0.74, 1.02, L, rot=math.pi / 4)
hex_roof(bm, 0.66, 1.02, 0.24, 0.05, S, sides=12, thick=0.08)
hoju(bm, 1.25, 0.06, S)
finish(bm, "Yukimi", ["stone", "light"])

# --- Chochin: the paper lantern ------------------------------------------------------------
bm = bmesh.new()
P, LQ = 0, 1
prof = []
for q in range(15):
    t = q / 14
    z = -0.12 - 0.42 * t
    r = 0.07 + 0.11 * math.sin(math.pi * t) ** 0.7
    prof.append((r, z))
# The paper bulges between the ribs: a scallop round, a fine ridge down.
lathe(bm, prof, 48, P, radial=lambda a, r, z: r * (1.0 + 0.025 * abs(math.sin(a * 12))))
prism(bm, 24, 0.085, 0.085, -0.15, -0.1, LQ)
prism(bm, 24, 0.085, 0.085, -0.56, -0.51, LQ)
prism(bm, 6, 0.006, 0.006, -0.1, 0.0, LQ)        # the cord
finish(bm, "Chochin", ["paper", "lacquer"])

# --- Tsuri: the hanging bronze lantern -----------------------------------------------------
bm = bmesh.new()
B, L2 = 0, 1
lathe(bm, [(0.02, -0.02), (0.035, -0.0), (0.035, -0.06), (0.02, -0.08)], 8, B)   # ring
prism(bm, 6, 0.012, 0.012, -0.14, -0.06, B)
hex_roof(bm, 0.26, -0.3, 0.16, 0.05, B, thick=0.03)
for k in range(6):
    a = math.tau * k / 6
    box(bm, (0.03, 0.03, 0.3), (0.17 * math.cos(a), 0.17 * math.sin(a), -0.47), B,
        rot=Matrix.Rotation(a, 4, "Z"))
prism(bm, 6, 0.155, 0.155, -0.6, -0.33, L2)
prism(bm, 6, 0.2, 0.17, -0.66, -0.6, B)
lathe(bm, [(0.12, -0.66), (0.08, -0.71), (0.0, -0.72)], 12, B)
finish(bm, "Tsuri", ["bronze", "light"])

# --- Bridge ---------------------------------------------------------------------------------
bm = bmesh.new()
LAC, DECK, BRZ, STN = 0, 1, 2, 3
SPAN = 7.2
CROWN = 1.45
HALFW = 0.95


def arch(x):
    u = x / (SPAN / 2)
    return CROWN * (1.0 - u * u) ** 0.85 if abs(u) < 1 else 0.0


xs = [-SPAN / 2 + SPAN * k / 40 for k in range(41)]
# The deck: a curved slab of planks.
deck_path = [(x, 0, arch(x) + 0.02) for x in xs]
sweep(bm, deck_path, [(-HALFW, -0.1), (HALFW, -0.1), (HALFW, 0.0), (-HALFW, 0.0)], DECK, up=(0, 0, 1))
# The girders either side, under the deck's edge.
for sy in (-1, 1):
    sweep(bm, [(x, sy * (HALFW - 0.06), arch(x) - 0.06) for x in xs], rect(0.14, 0.34), LAC)
# The railings: posts every 0.9 m, a top rail, a middle and a low one, giboshi on the end posts.
for sy in (-1, 1):
    y = sy * (HALFW - 0.04)
    posts = [-SPAN / 2 + 0.15 + (SPAN - 0.3) * k / 8 for k in range(9)]
    for i, x in enumerate(posts):
        base = arch(x)
        tall = 1.05 if i in (0, 8) else 0.82
        box(bm, (0.11, 0.11, tall), (x, y, base + tall / 2), LAC)
        if i in (0, 8):
            # The giboshi: a bronze onion on the end posts.
            top = base + tall
            prof = [(0.075, top), (0.1, top + 0.04), (0.1, top + 0.08), (0.065, top + 0.1), (0.1, top + 0.16),
                    (0.08, top + 0.24), (0.02, top + 0.33), (0.0, top + 0.36)]
            for ring in lathe(bm, prof, 12, BRZ):
                for v in ring:
                    v.co.x += x
                    v.co.y += y
        else:
            box(bm, (0.13, 0.13, 0.04), (x, y, base + tall + 0.02), BRZ)
    for h, sec in ((0.78, rect(0.07, 0.08)), (0.46, rect(0.05, 0.05)), (0.16, rect(0.05, 0.05))):
        sweep(bm, [(x, y, arch(x) + h) for x in xs[1:-1]], sec, LAC)
# The piers: pairs of round posts down into the water, with a cross-beam.
for x in (-1.6, 1.6):
    for sy in (-1, 1):
        prism(bm, 12, 0.12, 0.12, -1.1, arch(x) - 0.2, LAC, centre=(x, sy * (HALFW - 0.2)))
    box(bm, (0.16, HALFW * 2 - 0.1, 0.18), (x, 0, arch(x) - 0.3), LAC)
# Stone abutments at both banks.
for sx in (-1, 1):
    box(bm, (0.8, HALFW * 2 + 0.5, 0.9), (sx * (SPAN / 2 + 0.05), 0, -0.4), STN)
finish(bm, "Bridge", ["lacquer", "deck", "bronze", "stone"], smooth=30)

# --- Torii ---------------------------------------------------------------------------------
bm = bmesh.new()
LAC, BLK = 0, 1
GAP = 2.7
TALL = 6.6
for sx in (-1, 1):
    # Leaning in a little, as a myojin torii's pillars do.
    lean = 0.035
    base = Vector((sx * (GAP + 0.18), 0, 0))
    top = Vector((sx * GAP, 0, TALL))
    sweep(bm, [base, top], circle(0.3, 20), LAC, up=(0, 1, 0))
    prism(bm, 20, 0.36, 0.34, 0.0, 0.7, BLK, centre=(base.x, 0))          # the black base sleeve
    prism(bm, 20, 0.33, 0.33, 0.7, 0.78, BLK, centre=(base.x - sx * 0.006, 0))
# The tie beam through the pillars, out past them; and the strut and plaque between.
box(bm, (GAP * 2 + 1.8, 0.3, 0.42), (0, 0, 5.2), LAC)
box(bm, (0.36, 0.26, 0.9), (0, 0, 5.85), LAC)
box(bm, (0.7, 0.12, 0.95), (0, -0.16, 5.85), BLK)
# The two top beams: shimaki, straight, vermilion; kasagi above it, black, sweeping up at its
# ends.
box(bm, (GAP * 2 + 2.6, 0.44, 0.34), (0, 0, TALL + 0.05), LAC)
pts = []
for k in range(25):
    x = -(GAP + 2.1) + (GAP + 2.1) * 2 * k / 24
    u = abs(x) / (GAP + 2.1)
    pts.append((x, 0, TALL + 0.42 + 0.55 * u ** 3.2))
sweep(bm, pts, [(-0.32, -0.2), (0.32, -0.2), (0.36, 0.08), (0.24, 0.24), (-0.24, 0.24), (-0.36, 0.08)], BLK)
finish(bm, "Torii", ["lacquer", "black"], smooth=35)

# --- Gate: a temple gate's timber frame under the venue's roof ------------------------------
bm = bmesh.new()
for sx in (-1, 1):
    prism(bm, 16, 0.22, 0.2, 0.0, 4.2, 0, centre=(sx * 1.9, 0))
    for sy in (-1, 1):
        prism(bm, 12, 0.13, 0.12, 0.0, 3.0, 0, centre=(sx * 1.9, sy * 1.3))
        box(bm, (0.1, 1.3, 0.16), (sx * 1.9, sy * 0.65, 2.9), 0)
box(bm, (4.6, 0.26, 0.34), (0, 0, 3.6), 0)
box(bm, (4.4, 0.32, 0.3), (0, 0, 4.25), 0)
box(bm, (4.2, 2.9, 0.12), (0, 0, 4.45), 0)
finish(bm, "Gate", ["timber"], smooth=30)

# --- Rocks ---------------------------------------------------------------------------------


def rock(name, stretch, seed, flat_top=False):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=0.5)
    off = Vector((seed * 7.3, seed * 3.1, seed * 5.7))
    for v in bm.verts:
        n = v.co.normalized()
        d = 1.0 + 0.22 * noise.noise(n * 1.6 + off) + 0.08 * noise.noise(n * 4.5 + off)
        v.co = Vector((n.x * stretch[0], n.y * stretch[1], n.z * stretch[2])) * d
        # Faceted, the way weathered stone breaks: a little quantised.
    bottom = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z -= bottom + 0.18 * stretch[2]
        if v.co.z < 0.0:
            v.co.z = 0.0
        if flat_top and v.co.z > stretch[2] * 0.62:
            v.co.z = stretch[2] * 0.62 + (v.co.z - stretch[2] * 0.62) * 0.15
    finish(bm, name, ["stone"], smooth=55)


rock("Rock0", (0.55, 0.45, 1.6), 1)
rock("Rock1", (1.3, 0.8, 0.75), 2)
rock("Rock2", (1.0, 0.85, 0.45), 3)
rock("Rock3", (0.6, 0.5, 0.32), 4, flat_top=True)

# --- Shrub ---------------------------------------------------------------------------------
bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=3, radius=0.5)
for v in bm.verts:
    n = v.co.normalized()
    d = 1.0 + 0.07 * noise.noise(n * 5.0) + 0.04 * noise.noise(n * 11.0)
    v.co = Vector((n.x * 1.1, n.y, n.z * 0.62)) * d * 0.5
    if v.co.z < -0.05:
        v.co.z = -0.05
for v in bm.verts:
    v.co.z += 0.05
finish(bm, "Shrub", ["shrub"], smooth=70)

# --- Koi -----------------------------------------------------------------------------------
bm = bmesh.new()
profile = [(0.5, 0.0), (0.47, 0.035), (0.4, 0.07), (0.25, 0.1), (0.05, 0.095), (-0.15, 0.07), (-0.3, 0.04),
           (-0.38, 0.022)]
sides = 12
rings = []
for x, r in profile:
    rings.append([bm.verts.new((x, r * math.cos(math.tau * s / sides) * 0.75, r * math.sin(math.tau * s / sides)
                                * (1.0 if math.sin(math.tau * s / sides) > 0 else 0.85)))
                  for s in range(sides)])
for i in range(len(rings) - 1):
    for s in range(sides):
        bm.faces.new((rings[i][s], rings[i][(s + 1) % sides], rings[i + 1][(s + 1) % sides], rings[i + 1][s]))
nose = bm.verts.new((0.51, 0, 0))
for s in range(sides):
    bm.faces.new((rings[0][(s + 1) % sides], rings[0][s], nose))
tailend = bm.verts.new((-0.39, 0, 0))
for s in range(sides):
    bm.faces.new((rings[-1][s], rings[-1][(s + 1) % sides], tailend))
# The tail: a broad fan, forked.
tail = [bm.verts.new(p) for p in [(-0.37, 0, 0.012), (-0.52, 0, 0.13), (-0.47, 0, 0.0), (-0.52, 0, -0.13),
                                   (-0.37, 0, -0.012)]]
bm.faces.new(tail)
# Dorsal fin along the back, and the pectoral fins, swept back.
bm.faces.new([bm.verts.new(p) for p in [(0.18, 0, 0.09), (0.02, 0, 0.16), (-0.2, 0, 0.1), (-0.12, 0, 0.06)]])
for sy in (-1, 1):
    bm.faces.new([bm.verts.new(p) for p in [(0.3, sy * 0.06, -0.04), (0.18, sy * 0.2, -0.07),
                                            (0.12, sy * 0.07, -0.05)]])
finish(bm, "Koi", ["koi"], smooth=60)

# --- Petal ---------------------------------------------------------------------------------
bm = bmesh.new()
centre = bm.verts.new((0, 0, 0.08))
rim = []
for k in range(10):
    a = math.tau * k / 10
    # A notch at the tip, the cherry's own.
    r = 0.5 * (0.55 + 0.45 * math.sin(a / 2) ** 0.6) * (0.85 if k == 5 else 1.0)
    x = math.cos(a) * r * 0.75 + 0.1
    y = math.sin(a) * r
    rim.append(bm.verts.new((x, y, 0.06 * (x / 0.5) ** 2)))
for k in range(10):
    bm.faces.new((centre, rim[k], rim[(k + 1) % 10]))
finish(bm, "Petal", ["petal"], flat=False, smooth=80)

# --- Leaf ----------------------------------------------------------------------------------
bm = bmesh.new()
centre = bm.verts.new((0, 0, 0.02))
rim = []
lobes = 7
# Seven lobes fanned round the top, each a point with toothed shoulders, deep notches between.
spread = math.tau * 0.8
for k in range(lobes):
    mid = math.pi * 0.5 - spread / 2 + spread * (k + 0.5) / lobes
    size = 0.5 * (0.55 if k in (0, lobes - 1) else (0.82 if k in (1, lobes - 2) else 1.0))
    step = spread / lobes
    for da, r, z in ((-0.5, 0.38, 0.0), (-0.3, 0.62, 0.02), (-0.13, 0.78, 0.03), (0.0, 1.0, 0.05), (0.13, 0.78, 0.03), (0.3, 0.62, 0.02)):
        a = mid + da * step
        rr = size * r if r < 0.9 else size
        rim.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)))
rim.append(bm.verts.new((math.cos(math.pi * 0.5 + spread / 2) * 0.08, math.sin(math.pi * 0.5 + spread / 2) * 0.08, 0)))
stem = bm.verts.new((0, -0.3, -0.02))
ring = rim + [stem]
for k in range(len(ring)):
    bm.faces.new((centre, ring[k], ring[(k + 1) % len(ring)]))
finish(bm, "Leaf", ["leaf"], smooth=80)

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/garden_props.glb"), export_format="GLB")
print("wrote garden_props.glb")

if os.environ.get("PREVIEW"):
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    focus = float(os.environ.get("FOCUS", "0"))
    cam.location = (focus + 6, -9, 4.5)
    cam.rotation_euler = (math.radians(70), 0, math.radians(34))
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600
    scene.render.filepath = os.environ["PREVIEW"]
    bpy.ops.render.render(write_still=True)
