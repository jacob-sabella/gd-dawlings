# Builds the desert camp's tent and writes assets/models/desert_tent.glb.
#
#     blender --background --python tools/blender/desert_tent.py
#
# A Bedouin canopy: one sheet of woven cloth pulled taut over the studio and its back of house on
# a ring of poles, never a pole inside it (the gear stands under the middle, the zones under the
# back). The cloth is a tension membrane: its height is solved as a stretched sheet between the
# pole heads (a Poisson relaxation -- a sheet under tension with a little weight in it), every hem
# between two poles swings in toward the middle and sags, the way a cloth edge pulled from both
# ends does. The front is lifted high on two tall poles as an awning, so the view out is under it.
#
# Pieces, by material, which DesertVenue swaps by name:
#   "cloth"   the roof, both faces (UVs are its plan in metres: the venue's shader weaves stripes)
#   "valance" a woven band hanging from the front and side hems
#   "tassel"  the tassels along the valance
#   "wall"    the closed back wall, hung from the back hem to the sand in folds
# and empties "hook_<n>" under the cloth where lanterns hang from it.
#
# Modelled in the venue's own frame at the base width (Godot x, y up, z toward the back):
# Blender (x, -z, y). The venue scales it in x as the room widens; its pole heads are POLES below
# and in DesertVenue.TENT_POLES -- the two lists are one fact and must agree.

import math
import os

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)

# Pole heads in Godot space (x, height, z), round the edge in order.
POLES = [
    (-6.55, 3.75, -3.55), (-2.3, 4.85, -3.55), (2.3, 4.85, -3.55), (6.55, 3.75, -3.55),
    (6.55, 4.35, 2.1), (6.55, 3.7, 7.75), (2.3, 4.25, 7.75), (-2.3, 4.25, 7.75),
    (-6.55, 3.7, 7.75), (-6.55, 4.35, 2.1),
]
X0, X1, Z0, Z1 = -6.55, 6.55, -3.55, 7.75
NX, NZ = 54, 46
# How far a hem swings in, and sags, per metre of span between its poles.
SWING = {"front": 0.07, "side": 0.06, "back": 0.04}
SAG = 0.06
# The weight in the sheet: how far the middle hangs below a weightless one.
BELLY = 0.22
# Where lanterns hang (Godot x, z), in DesertVenue's order: over the two lounges, the walk to the
# zones either side and down the middle, the back corners, over the desk's front corners, over
# the kit and the bricks table, and over the middle of the lattice (a fitting, not a lantern).
HOOKS = [(-4.9, 0.4), (4.9, 0.4), (-2.6, 2.95), (2.6, 2.95), (0.0, 2.6), (-4.9, 4.3), (5.0, 4.2),
         (-2.3, -1.9), (2.3, -1.9), (-2.2, 5.8), (4.15, 4.85), (1.2, 5.4)]


def g2b(x, y, z):
    return (x, -z, y)


def edge_of(i, j):
    """Which hem a boundary grid point is on, its two poles and its parameter between them."""
    if j == 0:
        side, along = "front", (X0 + (X1 - X0) * i / (NX - 1))
        poles = [p for p in POLES if abs(p[2] - Z0) < 1e-6]
        key = 0
    elif j == NZ - 1:
        side, along = "back", (X0 + (X1 - X0) * i / (NX - 1))
        poles = [p for p in POLES if abs(p[2] - Z1) < 1e-6]
        key = 0
    elif i == 0:
        side, along = "side", (Z0 + (Z1 - Z0) * j / (NZ - 1))
        poles = [p for p in POLES if abs(p[0] - X0) < 1e-6]
        key = 2
    else:
        side, along = "side", (Z0 + (Z1 - Z0) * j / (NZ - 1))
        poles = [p for p in POLES if abs(p[0] - X1) < 1e-6]
        key = 2
    poles = sorted(poles, key=lambda p: p[key])
    for a, b in zip(poles, poles[1:]):
        if a[key] - 1e-6 <= along <= b[key] + 1e-6:
            t = (along - a[key]) / (b[key] - a[key])
            return side, a, b, t, b[key] - a[key]
    raise RuntimeError("no span for %s at %.3f" % (side, along))


# Boundary: height, and the plan swing inward.
H = [[0.0] * NZ for _ in range(NX)]
DX = [[0.0] * NZ for _ in range(NX)]
DZ = [[0.0] * NZ for _ in range(NX)]
FIXED = [[False] * NZ for _ in range(NX)]
for i in range(NX):
    for j in range(NZ):
        if 0 < i < NX - 1 and 0 < j < NZ - 1:
            continue
        side, a, b, t, span = edge_of(i, j)
        bell = 4.0 * t * (1.0 - t)
        H[i][j] = a[1] + (b[1] - a[1]) * t - SAG * span * bell
        swing = SWING[side] * span * bell
        if j == 0:
            DZ[i][j] = swing
        elif j == NZ - 1:
            DZ[i][j] = -swing
        elif i == 0:
            DX[i][j] = swing
        else:
            DX[i][j] = -swing
        FIXED[i][j] = True
# The corners belong to both of their hems: no swing at a pole.
for i, j in ((0, 0), (NX - 1, 0), (0, NZ - 1), (NX - 1, NZ - 1)):
    DX[i][j] = DZ[i][j] = 0.0

hx = (X1 - X0) / (NX - 1)
hz = (Z1 - Z0) / (NZ - 1)
# A sheet under tension, with a little weight: the Laplacian of its height is a small constant.
# Scaled so the middle of a weightless sheet would drop by about BELLY.
source = -8.0 * BELLY / ((X1 - X0) ** 2 + (Z1 - Z0) ** 2) * 2.0
w = 1.0 / (2.0 / hx ** 2 + 2.0 / hz ** 2)
for field, src in ((H, source), (DX, 0.0), (DZ, 0.0)):
    for _ in range(1600):
        for i in range(1, NX - 1):
            row, left, right = field[i], field[i - 1], field[i + 1]
            for j in range(1, NZ - 1):
                row[j] = w * ((left[j] + right[j]) / hx ** 2 + (row[j - 1] + row[j + 1]) / hz ** 2 + src)


def at(i, j):
    x = X0 + hx * i + DX[i][j]
    z = Z0 + hz * j + DZ[i][j]
    return x, H[i][j], z


cloth = bpy.data.materials.new("cloth")
valance = bpy.data.materials.new("valance")
tassel = bpy.data.materials.new("tassel")
wall = bpy.data.materials.new("wall")

# --- the roof: a double-faced sheet, the underside a hair under the top -----------------------
me = bpy.data.meshes.new("tent")
ob = bpy.data.objects.new("tent", me)
bpy.context.collection.objects.link(ob)
for m in (cloth, valance, tassel, wall):
    me.materials.append(m)
bm = bmesh.new()
uv = bm.loops.layers.uv.new("UVMap")
grid = [[bm.verts.new(g2b(*at(i, j))) for j in range(NZ)] for i in range(NX)]
under = [[bm.verts.new(g2b(at(i, j)[0], at(i, j)[1] - 0.012, at(i, j)[2])) for j in range(NZ)] for i in range(NX)]
for i in range(NX - 1):
    for j in range(NZ - 1):
        for verts, flip in ((grid, False), (under, True)):
            quad = [verts[i][j], verts[i + 1][j], verts[i + 1][j + 1], verts[i][j + 1]]
            f = bm.faces.new(quad)
            f.material_index = 0
            # Top faces up (Blender +Z), the underside down.
            f.normal_update()
            if (f.normal.z > 0) == flip:
                f.normal_flip()
            for loop in f.loops:
                # Godot x and z in metres: the weave runs across x.
                loop[uv].uv = (loop.vert.co.x, -loop.vert.co.y)


def hem(points_fn, count):
    return [points_fn(k) for k in range(count)]


# The hem lines as Godot points, front (left to right), the two sides (front to back), back.
front = hem(lambda i: at(i, 0), NX)
back = hem(lambda i: at(i, NZ - 1), NX)
left = hem(lambda j: at(0, j), NZ)
right = hem(lambda j: at(NX - 1, j), NZ)

# --- the valance: a woven band down from the front and side hems, with tassels ----------------
BAND = 0.34


def band(points, drop, outward):
    """A band hanging `drop` below a hem, a centimetre outside it."""
    tops, bots, length = [], [], 0.0
    for k, p in enumerate(points):
        if k:
            q = points[k - 1]
            length += math.dist((p[0], p[2]), (q[0], q[2]))
        ox, oz = outward(p)
        top = (p[0] + ox * 0.012, p[1] - 0.006, p[2] + oz * 0.012)
        tops.append((bm.verts.new(g2b(*top)), length))
        bots.append(bm.verts.new(g2b(top[0], top[1] - drop, top[2])))
    # One face: the venue draws the band from both sides.
    for k in range(len(points) - 1):
        f = bm.faces.new([tops[k][0], tops[k + 1][0], bots[k + 1], bots[k]])
        f.material_index = 1
        for loop in f.loops:
            idx = k if loop.vert in (tops[k][0], bots[k]) else k + 1
            s = tops[idx][1]
            v = 0.0 if loop.vert in (tops[k][0], tops[k + 1][0]) else 1.0
            loop[uv].uv = (s, v)
    return tops, bots


def tassels(points, drop, outward, every):
    walked = 0.0
    next_at = every * 0.5
    for k in range(1, len(points)):
        p, q = points[k], points[k - 1]
        step = math.dist((p[0], p[2]), (q[0], q[2]))
        while walked + step >= next_at:
            t = (next_at - walked) / step
            x = q[0] + (p[0] - q[0]) * t
            y = q[1] + (p[1] - q[1]) * t - drop - 0.006
            z = q[2] + (p[2] - q[2]) * t
            ox, oz = outward(p)
            x += ox * 0.012
            z += oz * 0.012
            ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.028, radius2=0.006, depth=0.13)
            for v in ret["verts"]:
                v.co.x += x
                v.co.y += -z
                v.co.z += y - 0.065
            for f in {f for v in ret["verts"] for f in v.link_faces}:
                f.material_index = 2
            next_at += every
        walked += step


band(front, BAND, lambda p: (0.0, -1.0))
band(left, BAND, lambda p: (-1.0, 0.0))
band(right, BAND, lambda p: (1.0, 0.0))
tassels(front, BAND, lambda p: (0.0, -1.0), 0.42)
tassels(left, BAND, lambda p: (-1.0, 0.0), 0.42)
tassels(right, BAND, lambda p: (1.0, 0.0), 0.42)

# --- the back wall: woven panels from the back hem down into the sand, in soft folds ----------
FOLD = 0.06
tops, bots = [], []
for k, p in enumerate(back):
    wobble = FOLD * math.sin(k * 0.9)
    tops.append(bm.verts.new(g2b(p[0], p[1] - 0.01, p[2] + 0.015 + wobble)))
    bots.append(bm.verts.new(g2b(p[0], -0.05, p[2] + 0.04 + wobble * 1.4)))
for k in range(len(back) - 1):
    # One face, drawn from both sides.
    f = bm.faces.new([tops[k], tops[k + 1], bots[k + 1], bots[k]])
    f.material_index = 3
    for loop in f.loops:
        loop[uv].uv = (loop.vert.co.x, loop.vert.co.z)

bm.normal_update()
bm.to_mesh(me)
bm.free()
for p in me.polygons:
    p.use_smooth = p.material_index in (0, 3)

# --- the hooks: lantern chains hang from these, a hair under the cloth ------------------------


def height_at(x, z):
    i = min(NX - 2, max(0, int((x - X0) / hx)))
    j = min(NZ - 2, max(0, int((z - Z0) / hz)))
    ti = (x - X0) / hx - i
    tj = (z - Z0) / hz - j
    a = H[i][j] * (1 - ti) + H[i + 1][j] * ti
    b = H[i][j + 1] * (1 - ti) + H[i + 1][j + 1] * ti
    return a * (1 - tj) + b * tj


for n, (x, z) in enumerate(HOOKS):
    e = bpy.data.objects.new("hook_%d" % n, None)
    e.location = g2b(x, height_at(x, z) - 0.03, z)
    e.parent = ob
    bpy.context.collection.objects.link(e)

print("tent faces", len(me.polygons), [m.name for m in me.materials], [round(d, 2) for d in ob.dimensions])
print("lowest roof", round(min(min(r) for r in H), 3), "middle", round(H[NX // 2][NZ // 2], 3))
for n, (x, z) in enumerate(HOOKS):
    print("hook", n, x, round(height_at(x, z), 3), z)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/desert_tent.glb"), export_format="GLB",
                          use_selection=True)
print("wrote desert_tent.glb")
