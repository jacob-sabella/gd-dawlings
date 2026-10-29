# Builds what the jazz club sets out for the show ("Showtime") and writes
# assets/models/club_showtime.glb.
#
#     blender --background --python tools/blender/club_showtime.py
#
# One file, several objects, each placed by ClubVenue by name:
#   PianoOpen  the upright again (as club.glb's Piano: 1.5 m wide, 1.25 m high, keys toward
#              Blender -Y / Godot +Z), its top lid propped open on a stick and the gilt frame
#              showing inside, a score open on the music desk
#   PianoBench a lacquered bench with a buttoned leather top, long side toward the keys
#   BassUpright the double bass standing in its stand, belly toward Blender -Y (Godot +Z),
#              leaning back a little onto the stand's yoke
#   Marquee    "LIVE tonight": red neon over blue on a lacquered board in a brass frame, ringed
#              with bulbs in two alternating sets ("bulb_a", "bulb_b") so the club can chase
#              them. The board's back on Blender y = 0, its face toward -Y; origin at its middle.
#   CoatStand  a bentwood coat stand by the door with a fedora, a cloche and a scarf on it
#   Bucket     a champagne bucket on a three-legged stand, a bottle in the ice
#   Footlight  one stage footlight: a brass hood over a bulb, open toward Blender -Y
# Every origin is on the floor except the Marquee's. Materials "lacquer", "ivory", "ebony",
# "brass", "gold", "paper", "ink", "varnish", "string", "iron", "wood", "felt", "felt_red",
# "scarf", "leather", "panel", "tube_red", "tube_blue", "bulb_a", "bulb_b", "silver",
# "glass_green", "ice", "foil", "lens".

import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
NAMES = ["lacquer", "ivory", "ebony", "brass", "gold", "paper", "ink", "varnish", "string", "iron", "wood", "felt",
         "felt_red", "scarf", "leather", "panel", "tube_red", "tube_blue", "bulb_a", "bulb_b", "silver",
         "glass_green", "ice", "foil", "lens"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}


class Part:
    """One object being built: a bmesh and the materials it uses (as tools/blender/club.py)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.used = []

    def index(self, mat):
        if mat not in self.used:
            self.used.append(mat)
        return self.used.index(mat)

    def lathe(self, profile, mat, at=(0, 0, 0), sides=24):
        """Spins (r, z) pairs round the vertical axis. Returns the new verts."""
        rings = []
        made = []
        for r, z in profile:
            ring = []
            for s in range(sides):
                a = 2 * math.pi * s / sides
                v = self.bm.verts.new((at[0] + r * math.cos(a), at[1] + r * math.sin(a), at[2] + z))
                ring.append(v)
                made.append(v)
            rings.append(ring)
        k = self.index(mat)
        for i in range(len(rings) - 1):
            for s in range(sides):
                f = self.bm.faces.new((rings[i][s], rings[i][(s + 1) % sides],
                                       rings[i + 1][(s + 1) % sides], rings[i + 1][s]))
                f.material_index = k
        return made

    def tube(self, points, radius, mat, sides=8, closed=False, radii=None):
        """A round rod along `points` (each point its own radius when `radii` is given)."""
        pts = [Vector(p) for p in points]
        n = len(pts)
        rings = []
        for i, p in enumerate(pts):
            if closed:
                d = (pts[(i + 1) % n] - pts[(i - 1) % n]).normalized()
            else:
                d = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            side = d.cross(Vector((0, 0, 1)))
            if side.length < 0.1:
                side = d.cross(Vector((1, 0, 0)))
            side.normalize()
            up = side.cross(d).normalized()
            r = radii[i] if radii else radius
            ring = []
            for s in range(sides):
                a = 2 * math.pi * s / sides
                ring.append(self.bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * r))
            rings.append(ring)
        k = self.index(mat)
        count = n if closed else n - 1
        for i in range(count):
            a, b = rings[i], rings[(i + 1) % n]
            for s in range(sides):
                f = self.bm.faces.new((a[s], a[(s + 1) % sides], b[(s + 1) % sides], b[s]))
                f.material_index = k

    def box(self, size, at, mat, bevel=0.0):
        """A box; returns its verts (bevelled ones included) so it can be turned afterwards."""
        before = set(self.bm.verts)
        geom = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = geom["verts"]
        for v in verts:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(at)
        faces = {f for v in verts for f in v.link_faces}
        k = self.index(mat)
        for f in faces:
            f.material_index = k
        if bevel > 0.0:
            edges = list({e for v in verts for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=3, affect="EDGES", profile=0.5)
        return [v for v in self.bm.verts if v not in before]

    def sphere(self, radius, at, mat, sides=10):
        prof = [(radius * math.sin(math.pi * i / 6), -radius * math.cos(math.pi * i / 6)) for i in range(7)]
        prof[0] = (0.0, -radius)
        prof[-1] = (0.0, radius)
        return self.lathe(prof, mat, at=at, sides=sides)

    def turn(self, verts, matrix):
        for v in verts:
            v.co = matrix @ v.co

    def finish(self, x_offset):
        mesh = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.used:
            mesh.materials.append(mats[m])
        for p in mesh.polygons:
            p.use_smooth = True
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        for o in bpy.context.scene.objects:
            o.select_set(o == obj)
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
        obj.location.x = x_offset
        print("%s: %d faces" % (self.name, len(mesh.polygons)))
        return obj


def about(axis_point, axis, angle):
    """A matrix turning `angle` about a line through `axis_point`."""
    p = Vector(axis_point)
    return Matrix.Translation(p) @ Matrix.Rotation(angle, 4, axis) @ Matrix.Translation(-p)


# --- the piano, open ------------------------------------------------------------------------
# club.py's upright, the same case, keys and pedals (so it reads as the same piano), but the top
# lid is up: a fixed strip at the back, the lid hinged off it and propped on a stick, and the gilt
# iron frame showing in the case. A score on the desk, two pages of staves.
p = Part("PianoOpen")
W, D, H = 1.5, 0.6, 1.25
p.box((W, D, H - 0.06), (0, 0.0, 0.06 + (H - 0.06) / 2), "lacquer", bevel=0.008)
p.box((W - 0.04, D - 0.04, 0.06), (0, 0.0, 0.03), "ebony")
for sx in (-1, 1):
    p.box((0.06, 0.3, 0.2), (sx * (W / 2 - 0.03), -D / 2 - 0.15, 0.72), "lacquer", bevel=0.01)
    p.box((0.06, 0.06, 0.6), (sx * (W / 2 - 0.03), -D / 2 - 0.27, 0.32), "lacquer", bevel=0.01)
    p.box((0.08, 0.36, 0.06), (sx * (W / 2 - 0.03), -D / 2 - 0.18, 0.03), "lacquer", bevel=0.01)
p.box((W - 0.12, 0.3, 0.08), (0, -D / 2 - 0.15, 0.66), "lacquer")
KEYS = 52
kw = (W - 0.14) / KEYS
# As club.py's: the octave the club's instrument is, left out for the set's own keys.
GAP = range(26, 34)
for i in range(KEYS):
    if i in GAP:
        continue
    x = -(W - 0.14) / 2 + kw * (i + 0.5)
    p.box((kw - 0.002, 0.15, 0.022), (x, -D / 2 - 0.2, 0.711), "ivory")
for i in range(KEYS - 1):
    if (i % 7) in (2, 6) or GAP[0] - 1 <= i <= GAP[-1]:
        continue
    x = -(W - 0.14) / 2 + kw * (i + 1)
    p.box((kw * 0.55, 0.09, 0.03), (x, -D / 2 - 0.17, 0.73), "ebony")
p.box((W - 0.12, 0.04, 0.16), (0, -D / 2 - 0.02, 0.86), "lacquer", bevel=0.006)
p.box((0.7, 0.03, 0.26), (0, -D / 2 - 0.035, 1.02), "lacquer", bevel=0.006)
p.box((0.72, 0.06, 0.02), (0, -D / 2 - 0.05, 0.9), "lacquer", bevel=0.004)
for sx in (-0.12, 0.0, 0.12):
    p.box((0.03, 0.12, 0.012), (sx, -D / 2 - 0.08, 0.06), "brass", bevel=0.004)
p.box((W - 0.12, 0.02, 0.5), (0, -D / 2 - 0.01, 0.32), "lacquer")
# The gilt frame seen through the open top: a plate a little under the rim, and the tuning pins.
p.box((W - 0.1, D - 0.16, 0.02), (0, 0.02, H - 0.02), "gold")
for i in range(40):
    x = -(W - 0.2) / 2 + (W - 0.2) * i / 39
    p.box((0.008, 0.008, 0.03), (x, 0.17 if i % 2 else 0.2, H - 0.002), "iron")
# The lid: a fixed strip at the back, the rest hinged at its back edge and lifted 32 degrees.
p.box((W + 0.02, 0.14, 0.03), (0, D / 2 + 0.02 - 0.07, H + 0.015), "lacquer", bevel=0.006)
hinge_y = D / 2 + 0.02 - 0.14
lid_depth = D + 0.04 - 0.14
lid = p.box((W + 0.02, lid_depth, 0.03), (0, hinge_y - lid_depth / 2, H + 0.015), "lacquer", bevel=0.006)
LIFT = math.radians(32)
p.turn(lid, about((0, hinge_y, H), "X", -LIFT))
for sx in (-W / 2 + 0.06, W / 2 - 0.06):
    p.box((0.04, 0.02, 0.02), (sx, hinge_y, H + 0.03), "brass")
# The stick from the case's front rim up to the lid's underside.
tip_y = hinge_y - (lid_depth - 0.05) * math.cos(LIFT)
tip_z = H + (lid_depth - 0.05) * math.sin(LIFT)
p.tube([(W / 2 - 0.25, -D / 2 + 0.05, H), (W / 2 - 0.25, tip_y, tip_z - 0.005)], 0.008, "lacquer", sides=6)
# The score: two pages open on the desk, staves ruled across them, a few notes.
for page in (-1, 1):
    cx = page * 0.115
    p.box((0.22, 0.003, 0.29), (cx, -D / 2 - 0.0535, 1.055), "paper")
    for staff in range(6):
        top = 1.17 - staff * 0.04
        for line in range(5):
            p.box((0.18, 0.0008, 0.0011), (cx, -D / 2 - 0.0554, top - line * 0.0045), "ink")
        for n in range(7):
            nx = cx - 0.075 + n * 0.024 + (staff * 0.007) % 0.01
            nz = top - 0.009 - ((n * 7 + staff * 3) % 5) * 0.0022
            p.box((0.004, 0.001, 0.003), (nx, -D / 2 - 0.0556, nz), "ink")
            p.box((0.0008, 0.001, 0.012), (nx + 0.002, -D / 2 - 0.0556, nz + 0.007), "ink")
p.finish(0.0)

# The bench: lacquered, a buttoned leather top, long side toward the keys (along X).
b = Part("PianoBench")
b.box((0.86, 0.36, 0.04), (0, 0, 0.47), "lacquer", bevel=0.006)
b.box((0.82, 0.32, 0.05), (0, 0, 0.51), "leather", bevel=0.018)
for sx in (-1, 1):
    for sy in (-1, 1):
        b.tube([(sx * 0.38, sy * 0.14, 0.0), (sx * 0.36, sy * 0.13, 0.45)], 0.022, "lacquer", sides=10)
b.box((0.72, 0.02, 0.06), (0, -0.15, 0.4), "lacquer")
b.box((0.72, 0.02, 0.06), (0, 0.15, 0.4), "lacquer")
b.finish(2.0)


# --- the bass, stood up ---------------------------------------------------------------------
def bass_halfwidth(t):
    pts = [(0.0, 0.0), (0.025, 0.2), (0.08, 0.3), (0.2, 0.355), (0.32, 0.34), (0.42, 0.27), (0.5, 0.215),
           (0.58, 0.225), (0.7, 0.265), (0.8, 0.26), (0.9, 0.21), (0.96, 0.13), (1.0, 0.0)]
    for (t0, w0), (t1, w1) in zip(pts, pts[1:]):
        if t <= t1:
            u = (t - t0) / (t1 - t0)
            u = u * u * (3 - 2 * u)
            return w0 + (w1 - w0) * u
    return 0.0


bb = Part("BassUpright")
bm = bb.bm
BODY = 1.12
RIB = 0.1
STEPS = 40
SIDES = 28
LIFTED = 0.1
rings = []
for i in range(1, STEPS):
    t = i / STEPS
    hw = bass_halfwidth(t)
    ring = []
    for k in range(SIDES):
        a = 2 * math.pi * k / SIDES
        c, sn = math.cos(a), math.sin(a)
        x = hw * math.copysign(abs(c) ** 0.55, c)
        y = (RIB + 0.035 * (1 - (x / max(hw, 1e-3)) ** 2)) * math.copysign(abs(sn) ** 0.45, sn)
        ring.append(bm.verts.new((x, y, LIFTED + t * BODY)))
    rings.append(ring)
k = bb.index("varnish")
for i in range(len(rings) - 1):
    for s in range(SIDES):
        f = bm.faces.new((rings[i][s], rings[i][(s + 1) % SIDES], rings[i + 1][(s + 1) % SIDES], rings[i + 1][s]))
        f.material_index = k
for ring, z, flip in ((rings[0], LIFTED, True), (rings[-1], LIFTED + BODY, False)):
    tip = bm.verts.new((0, 0, z))
    for s in range(SIDES):
        f = bm.faces.new((ring[(s + 1) % SIDES], ring[s], tip) if flip else (ring[s], ring[(s + 1) % SIDES], tip))
        f.material_index = k
TOP = -(RIB + 0.035)
Z0 = LIFTED
bb.box((0.07, 0.06, 0.62), (0, TOP + 0.05, Z0 + BODY + 0.29), "varnish", bevel=0.01)
bb.box((0.075, 0.02, 0.95), (0, TOP - 0.02, Z0 + BODY + 0.1), "ebony", bevel=0.004)
bb.box((0.06, 0.07, 0.22), (0, TOP + 0.04, Z0 + BODY + 0.71), "varnish", bevel=0.01)
scroll = []
for s in range(13):
    a = 2.2 * math.pi * s / 12
    r = 0.06 * (1 - 0.06 * s)
    scroll.append((0, TOP + 0.04 + r * math.sin(a), Z0 + BODY + 0.86 + r * (1 - math.cos(a)) * 0.9))
bb.tube(scroll, 0.026, "varnish", sides=10)
for i, z in enumerate((0.65, 0.72, 0.79)):
    for sx in (-1, 1):
        if i == 2 and sx > 0:
            continue
        bb.tube([(sx * 0.03, TOP + 0.04, Z0 + BODY + z), (sx * 0.1, TOP + 0.04, Z0 + BODY + z)], 0.007, "brass", sides=6)
        bb.box((0.012, 0.04, 0.03), (sx * 0.105, TOP + 0.04, Z0 + BODY + z), "brass")
bb.box((0.2, 0.012, 0.15), (0, TOP - 0.075, Z0 + 0.44), "ivory", bevel=0.004)
bb.box((0.09, 0.016, 0.3), (0, TOP - 0.05, Z0 + 0.19), "ebony", bevel=0.006)
bb.tube([(0, 0, Z0 + 0.01), (0, 0, 0.0)], 0.012, "iron", sides=8)
for i in range(4):
    x = -0.045 + i * 0.03
    bb.tube([(x * 0.8, TOP - 0.06, Z0 + 0.3), (x, TOP - 0.152, Z0 + 0.44), (x * 0.55, TOP - 0.036, Z0 + BODY + 0.58)],
            0.0022 + 0.0006 * (3 - i), "string", sides=5)
for sx in (-1, 1):
    pts = []
    for s in range(9):
        u = s / 8
        pts.append((sx * (0.12 + 0.025 * math.sin(u * math.pi * 2)), TOP + 0.002, Z0 + 0.35 + u * 0.24))
    bb.tube(pts, 0.006, "ebony", sides=5)
# Leaning back 8 degrees about its end pin, onto the stand behind it.
LEAN = math.radians(8)
bb.turn(list(bm.verts), about((0, 0, 0), "X", -LEAN))
# The stand: three feet, a post up its back, a padded cradle under the lower bout and a yoke
# round the neck.
POST_Y = 0.32
for i in range(3):
    a = math.radians(90 + 120 * i)
    bb.tube([(0, POST_Y, 0.03), (0.32 * math.cos(a), POST_Y + 0.32 * math.sin(a), 0.012)], 0.012, "iron", sides=8)
bb.tube([(0, POST_Y, 0.0), (0, POST_Y, 1.42)], 0.015, "iron", sides=10)
neck = Matrix.Rotation(-LEAN, 4, "X") @ Vector((0, TOP + 0.05, Z0 + BODY + 0.25))
bb.tube([(0, POST_Y, 1.42), (0, neck.y + 0.06, neck.z)], 0.012, "iron", sides=8)
yoke = [(0.07 * math.cos(math.pi * s / 8), neck.y + 0.06 - 0.07 * math.sin(math.pi * s / 8), neck.z) for s in range(9)]
bb.tube(yoke, 0.01, "felt", sides=6)
low = Matrix.Rotation(-LEAN, 4, "X") @ Vector((0, RIB + 0.03, Z0 + 0.22))
bb.tube([(0, POST_Y, 0.35), (0, low.y + 0.02, low.z)], 0.012, "iron", sides=8)
bb.tube([(-0.2, low.y + 0.02, low.z), (0.2, low.y + 0.02, low.z)], 0.02, "felt", sides=8)
bb.finish(4.0)


# --- the marquee ----------------------------------------------------------------------------
def neon_words(body, size, z, mat, y):
    bpy.ops.object.text_add()
    text = bpy.context.object
    text.data.body = body
    text.data.size = size
    text.data.align_x = "CENTER"
    text.data.fill_mode = "NONE"
    text.data.bevel_depth = 0.009
    text.data.bevel_resolution = 2
    text.data.resolution_u = 6
    text.rotation_euler = (math.pi / 2, 0, 0)
    text.location = (0, y, z)
    text.data.materials.append(mats[mat])
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    xs = [v.co.x for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    print("%s: %.2f m wide, %.2f..%.2f" % (body, max(xs) - min(xs), min(zs), max(zs)))
    return obj


BW, BH = 2.7, 1.6
m = Part("MarqueeBoard")
m.box((BW, 0.08, BH), (0, -0.04, 0), "panel", bevel=0.01)
# A brass frame proud of the board, the bulbs in a channel inside it.
for spec in (((BW + 0.08, 0.05, 0.06), (0, -0.075, BH / 2 + 0.01)), ((BW + 0.08, 0.05, 0.06), (0, -0.075, -BH / 2 - 0.01)),
             ((0.06, 0.05, BH + 0.02), (BW / 2 + 0.01, -0.075, 0)), ((0.06, 0.05, BH + 0.02), (-BW / 2 - 0.01, -0.075, 0))):
    m.box(spec[0], spec[1], "brass", bevel=0.006)
ring = []
STEP = 0.135
nx = int((BW - 0.16) / STEP)
nz = int((BH - 0.16) / STEP)
x0, z0 = -(nx * STEP) / 2, -(nz * STEP) / 2
for i in range(nx):
    ring.append((x0 + i * STEP, z0 + nz * STEP))
for i in range(nz):
    ring.append((x0 + nx * STEP, z0 + nz * STEP - i * STEP))
for i in range(nx):
    ring.append((x0 + nx * STEP - i * STEP, z0))
for i in range(nz):
    ring.append((x0, z0 + i * STEP))
for i, (x, z) in enumerate(ring):
    m.lathe([(0.0, -0.1), (0.016, -0.1), (0.016, -0.09), (0.0, -0.09)], "brass", at=(x, 0, z), sides=10)
    bulb = m.sphere(0.02, (0, 0, 0), "bulb_a" if i % 2 == 0 else "bulb_b", sides=10)
    # Lathed round Z; turned so it stands out of the board along -Y.
    m.turn(bulb, Matrix.Translation((x, -0.115, z)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
print("marquee bulbs: %d" % len(ring))
board = m.finish(0.0)
live = neon_words("LIVE", 0.75, 0.05, "tube_red", -0.13)
tonight = neon_words("tonight", 0.42, -0.33, "tube_blue", -0.13)
bpy.ops.object.select_all(action="DESELECT")
for o in (live, tonight, board):
    o.select_set(True)
bpy.context.view_layer.objects.active = board
bpy.ops.object.join()
joined = bpy.context.active_object
joined.name = "Marquee"
joined.data.name = "Marquee"
joined.location.x = 6.0
print("Marquee: %d faces" % len(joined.data.polygons))

# --- the coat stand -------------------------------------------------------------------------
c = Part("CoatStand")
c.tube([(0, 0, 0.0), (0, 0, 1.78)], 0.022, "wood", sides=12)
c.lathe([(0.0, 1.78), (0.03, 1.78), (0.032, 1.8), (0.0, 1.83)], "wood", sides=12)
for i in range(4):
    a = math.radians(45 + 90 * i)
    d = Vector((math.cos(a), math.sin(a), 0))
    pts = [Vector((0, 0, 0.32)) + d * 0.01]
    for s in range(1, 9):
        u = s / 8
        pts.append(d * (0.32 * u) + Vector((0, 0, 0.32 * (1 - u) ** 1.6 + 0.012)))
    c.tube(pts, 0.014, "wood", sides=8)
for i in range(6):
    a = math.radians(30 + 60 * i)
    d = Vector((math.cos(a), math.sin(a), 0))
    z = 1.62 if i % 2 else 1.5
    pts = []
    for s in range(7):
        u = s / 6
        pts.append(d * (0.2 * math.sin(u * math.pi * 0.6)) + Vector((0, 0, z - 0.12 + 0.12 * u + 0.08 * math.sin(u * math.pi))))
    c.tube(pts, 0.011, "wood", sides=6)
# A fedora on one hook, a cloche on another; a scarf hung over a low hook, its two ends down.
fed = c.lathe([(0.0, 0.0), (0.16, 0.0), (0.165, 0.008), (0.095, 0.012), (0.09, 0.1), (0.065, 0.122), (0.0, 0.108)],
              "felt", sides=24)
c.turn(fed, Matrix.Translation((0.17, 0.1, 1.66)) @ Matrix.Rotation(math.radians(-24), 4, "Y"))
clo = c.lathe([(0.0, 0.0), (0.12, 0.0), (0.125, 0.012), (0.1, 0.04), (0.095, 0.11), (0.06, 0.15), (0.0, 0.155)],
              "felt_red", sides=24)
c.turn(clo, Matrix.Translation((-0.17, -0.1, 1.72)) @ Matrix.Rotation(math.radians(20), 4, "Y"))
a = math.radians(270)
hook = Vector((0.16 * math.cos(a), 0.16 * math.sin(a), 1.52))
c.tube([hook + Vector((-0.08, 0.02, -0.75)), hook + Vector((-0.06, 0.0, -0.3)), hook + Vector((-0.02, 0.0, 0.02)),
        hook + Vector((0.03, 0.0, 0.03)), hook + Vector((0.07, 0.0, -0.3)), hook + Vector((0.08, 0.03, -0.6))],
       0.03, "scarf", sides=8)
c.finish(8.0)

# --- the champagne bucket -------------------------------------------------------------------
k2 = Part("Bucket")
for i in range(3):
    a = math.radians(90 + 120 * i)
    k2.tube([(0.2 * math.cos(a), 0.2 * math.sin(a), 0.0), (0.13 * math.cos(a), 0.13 * math.sin(a), 0.6)], 0.009, "silver", sides=8)
ring = [(0.13 * math.cos(2 * math.pi * s / 24), 0.13 * math.sin(2 * math.pi * s / 24), 0.6) for s in range(24)]
k2.tube(ring, 0.008, "silver", closed=True)
ring = [(0.16 * math.cos(2 * math.pi * s / 24), 0.16 * math.sin(2 * math.pi * s / 24), 0.22) for s in range(24)]
k2.tube(ring, 0.006, "silver", closed=True)
k2.lathe([(0.0, 0.56), (0.08, 0.56), (0.11, 0.6), (0.125, 0.8), (0.133, 0.81), (0.12, 0.81), (0.11, 0.62), (0.0, 0.58)],
         "silver", sides=28)
k2.lathe([(0.0, 0.76), (0.115, 0.76), (0.0, 0.78)], "ice", sides=12)
neck_bottle = k2.lathe([(0.0, 0.0), (0.045, 0.0), (0.046, 0.2), (0.032, 0.25), (0.016, 0.28), (0.015, 0.33), (0.0, 0.33)],
                       "glass_green", sides=16)
foil = k2.lathe([(0.0165, 0.27), (0.0165, 0.335), (0.0, 0.34)], "foil", sides=12)
k2.turn(neck_bottle + foil, Matrix.Translation((0.02, 0.0, 0.6)) @ Matrix.Rotation(math.radians(-14), 4, "Y"))
k2.finish(9.0)

# --- a footlight ----------------------------------------------------------------------------
f = Part("Footlight")
f.box((0.2, 0.08, 0.012), (0, 0.0, 0.006), "brass", bevel=0.003)
# The hood: a half-round shell over the bulb, open toward the stage (-Y), closed at the back.
arc = []
for s in range(13):
    a = math.pi * s / 12
    arc.append((0.09 * math.cos(a), 0.012 + 0.065 * math.sin(a)))
front = [f.bm.verts.new((x, -0.04, z)) for x, z in arc]
back = [f.bm.verts.new((x, 0.04, z)) for x, z in arc]
kh = f.index("brass")
for i in range(len(arc) - 1):
    face = f.bm.faces.new((front[i], front[i + 1], back[i + 1], back[i]))
    face.material_index = kh
cap = f.bm.faces.new(list(reversed(back)))
cap.material_index = kh
f.sphere(0.022, (0, -0.005, 0.03), "lens", sides=10)
f.finish(10.0)

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/club_showtime.glb"), export_format="GLB")
print("wrote club_showtime.glb")
