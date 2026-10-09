# Builds the jazz club's furniture and writes assets/models/club.glb.
#
#     blender --background --python tools/blender/club.py
#
# One file, several objects, each placed by ClubVenue by name:
#   Table      a bistro table: a round marble top on a cast-iron column and foot, 0.74 m high
#   Chair      a bentwood cafe chair: round seat, four splayed legs, a hoop back and a leg ring
#   Stool      a bar stool: a padded round seat, brass legs and a foot ring, 0.76 m to the seat
#   Banquette  one bench of a booth: a channel-tufted high back and a padded seat on a wood
#              plinth, 1.3 m long, its seat facing Blender -Y (Godot +Z)
#   Bottle0..3 bottles for the back bar: wine, a tall spirit, a squat one, a long neck
#   Piano      an upright piano, 1.5 m wide, 1.25 m high, its keys facing Blender -Y (Godot +Z)
#   Bass       a double bass lying on its side on the floor, scroll toward +X, its belly toward
#              Blender -Y (Godot +Z); resting on the edge of its body and its scroll
#   Glass0..2  glasses left on the tables: a rocks glass with a finger of whisky, a wine glass
#              with a little red, an empty coupe
#   Coat       a coat thrown over a Banquette's back and hanging down onto its seat, in the
#              bench's own frame (cloth simulated over the bench), and Hat, a fedora on the seat
# Every origin is on the floor (a bottle's on its base). Materials "marble", "iron", "wood",
# "leather", "brass", "glass_green", "glass_amber", "glass_clear", "label", "lacquer", "ivory",
# "ebony", "varnish", "string", "whisky", "wine", "wool", "felt", "ribbon".

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
NAMES = ["marble", "iron", "wood", "leather", "brass", "glass_green", "glass_amber", "glass_clear", "label",
         "lacquer", "ivory", "ebony", "varnish", "string", "whisky", "wine", "wool", "felt", "ribbon"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}


class Part:
    """One object being built: a bmesh and the materials it uses."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.used = []

    def index(self, mat):
        if mat not in self.used:
            self.used.append(mat)
        return self.used.index(mat)

    def lathe(self, profile, mat, at=(0, 0, 0), sides=24):
        """Spins (r, z) pairs round the vertical axis, capped where r is 0."""
        rings = []
        for r, z in profile:
            ring = []
            for s in range(sides):
                a = 2 * math.pi * s / sides
                ring.append(self.bm.verts.new((at[0] + r * math.cos(a), at[1] + r * math.sin(a), at[2] + z)))
            rings.append(ring)
        k = self.index(mat)
        for i in range(len(rings) - 1):
            for s in range(sides):
                f = self.bm.faces.new((rings[i][s], rings[i][(s + 1) % sides],
                                       rings[i + 1][(s + 1) % sides], rings[i + 1][s]))
                f.material_index = k

    def tube(self, points, radius, mat, sides=8, closed=False):
        """A round rod along `points`."""
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
            ring = []
            for s in range(sides):
                a = 2 * math.pi * s / sides
                ring.append(self.bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * radius))
            rings.append(ring)
        k = self.index(mat)
        count = n if closed else n - 1
        for i in range(count):
            a, b = rings[i], rings[(i + 1) % n]
            for s in range(sides):
                f = self.bm.faces.new((a[s], a[(s + 1) % sides], b[(s + 1) % sides], b[s]))
                f.material_index = k

    def box(self, size, at, mat, bevel=0.0):
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
        # Laid out in a row in the file so they can be looked at; each is placed in Godot.
        obj.location.x = x_offset
        print("%s: %d faces" % (self.name, len(mesh.polygons)))


# The table.
t = Part("Table")
t.lathe([(0.0, 0.0), (0.24, 0.0), (0.24, 0.02), (0.1, 0.05), (0.045, 0.09), (0.03, 0.2), (0.025, 0.66),
         (0.06, 0.69), (0.08, 0.705), (0.0, 0.705)], "iron")
t.lathe([(0.0, 0.705), (0.33, 0.705), (0.335, 0.72), (0.33, 0.74), (0.0, 0.74)], "marble", sides=40)
t.finish(0.0)

# The chair: a seat, four legs splayed out, a ring between them, and a hoop back in one bend.
c = Part("Chair")
c.lathe([(0.0, 0.44), (0.2, 0.44), (0.215, 0.455), (0.21, 0.475), (0.0, 0.48)], "wood", sides=28)
legs = []
for i in range(4):
    a = math.radians(45 + 90 * i)
    top = Vector((0.15 * math.cos(a), 0.15 * math.sin(a), 0.44))
    foot = Vector((0.23 * math.cos(a), 0.23 * math.sin(a), 0.0))
    legs.append((top, foot))
    c.tube([foot, foot.lerp(top, 0.5), top], 0.014, "wood")
ring = []
for s in range(24):
    a = 2 * math.pi * s / 24
    ring.append((0.19 * math.cos(a), 0.19 * math.sin(a), 0.17))
c.tube(ring, 0.009, "wood", closed=True)
# The back: from the seat's back corners, up and round in a hoop, leaning back a little.
hoop = []
for s in range(19):
    a = math.pi * s / 18
    x = 0.17 * math.cos(a)
    z = 0.48 + 0.18 + 0.2 * math.sin(a)
    hoop.append((x, 0.17 + 0.06 * (z - 0.48), z))
back = [(0.17, 0.16, 0.48), (0.17, 0.17, 0.66)] + hoop[1:-1] + [(-0.17, 0.17, 0.66), (-0.17, 0.16, 0.48)]
c.tube(back, 0.012, "wood")
c.tube([(0.0, 0.18, 0.48), (0.0, 0.19, 0.6), (0.0, 0.2, 0.86)], 0.009, "wood")
c.finish(1.0)

# The stool.
s = Part("Stool")
s.lathe([(0.0, 0.7), (0.17, 0.7), (0.19, 0.72), (0.19, 0.76), (0.17, 0.785), (0.0, 0.79)], "leather", sides=28)
s.lathe([(0.0, 0.68), (0.16, 0.68), (0.16, 0.7), (0.0, 0.7)], "brass", sides=28)
for i in range(4):
    a = math.radians(45 + 90 * i)
    top = (0.12 * math.cos(a), 0.12 * math.sin(a), 0.68)
    foot = (0.21 * math.cos(a), 0.21 * math.sin(a), 0.0)
    s.tube([foot, top], 0.013, "brass")
ring = []
for k in range(24):
    a = 2 * math.pi * k / 24
    ring.append((0.18 * math.cos(a), 0.18 * math.sin(a), 0.28))
s.tube(ring, 0.011, "brass", closed=True)
s.finish(2.0)

# The banquette: a wood plinth, a padded seat, and a high back in vertical channels.
b = Part("Banquette")
LENGTH = 1.3
b.box((LENGTH, 0.5, 0.2), (0, 0.0, 0.1), "wood")
b.box((LENGTH - 0.02, 0.52, 0.14), (0, -0.01, 0.27), "leather", bevel=0.03)
b.box((LENGTH, 0.14, 1.12), (0, 0.27, 0.56), "wood")
channels = 7
w = (LENGTH - 0.04) / channels
for i in range(channels):
    x = -LENGTH / 2 + 0.02 + w * (i + 0.5)
    b.box((w - 0.008, 0.09, 0.62), (x, 0.17, 0.72), "leather", bevel=0.035)
b.box((LENGTH + 0.02, 0.18, 0.05), (0, 0.27, 1.145), "wood", bevel=0.01)
b.finish(3.5)

# The bottles: (profile, glass, label band (z0, z1) or None).
BOTTLES = [
    ([(0.0, 0.0), (0.037, 0.0), (0.038, 0.01), (0.038, 0.2), (0.03, 0.24), (0.014, 0.27), (0.013, 0.31),
      (0.015, 0.315), (0.014, 0.33), (0.0, 0.33)], "glass_green", (0.07, 0.15)),
    ([(0.0, 0.0), (0.04, 0.0), (0.041, 0.01), (0.041, 0.2), (0.036, 0.22), (0.016, 0.25), (0.015, 0.3),
      (0.017, 0.305), (0.016, 0.32), (0.0, 0.32)], "glass_amber", (0.06, 0.14)),
    ([(0.0, 0.0), (0.05, 0.0), (0.052, 0.01), (0.052, 0.13), (0.045, 0.15), (0.02, 0.17), (0.019, 0.21),
      (0.021, 0.215), (0.02, 0.23), (0.0, 0.23)], "glass_clear", (0.04, 0.1)),
    ([(0.0, 0.0), (0.032, 0.0), (0.033, 0.01), (0.033, 0.17), (0.026, 0.2), (0.011, 0.22), (0.01, 0.34),
      (0.012, 0.345), (0.011, 0.36), (0.0, 0.36)], "glass_green", None),
]
for i, (profile, glass, label) in enumerate(BOTTLES):
    p = Part("Bottle%d" % i)
    p.lathe(profile, glass, sides=16)
    if label:
        r = profile[2][0] + 0.002
        p.lathe([(r, label[0]), (r, label[1])], "label", sides=16)
    p.finish(5.0 + i * 0.2)

# The piano: the case, the keybed sticking out at the front, keys, a fallboard folded back, the
# music desk, toe blocks on castors and three brass pedals.
p = Part("Piano")
W, D, H = 1.5, 0.6, 1.25
p.box((W, D, H - 0.06), (0, 0.0, 0.06 + (H - 0.06) / 2), "lacquer", bevel=0.008)
p.box((W + 0.02, D + 0.04, 0.03), (0, 0.0, H - 0.015), "lacquer", bevel=0.008)
p.box((W - 0.04, D - 0.04, 0.06), (0, 0.0, 0.03), "ebony")
# The cheeks either side of the keys, and the keybed under them.
for sx in (-1, 1):
    p.box((0.06, 0.3, 0.2), (sx * (W / 2 - 0.03), -D / 2 - 0.15, 0.72), "lacquer", bevel=0.01)
    p.box((0.06, 0.06, 0.6), (sx * (W / 2 - 0.03), -D / 2 - 0.27, 0.32), "lacquer", bevel=0.01)
    p.box((0.08, 0.36, 0.06), (sx * (W / 2 - 0.03), -D / 2 - 0.18, 0.03), "lacquer", bevel=0.01)
p.box((W - 0.12, 0.3, 0.08), (0, -D / 2 - 0.15, 0.66), "lacquer")
KEYS = 52
kw = (W - 0.14) / KEYS
for i in range(KEYS):
    x = -(W - 0.14) / 2 + kw * (i + 0.5)
    p.box((kw - 0.002, 0.15, 0.022), (x, -D / 2 - 0.2, 0.711), "ivory")
for i in range(KEYS - 1):
    if (i % 7) in (2, 6):
        continue
    x = -(W - 0.14) / 2 + kw * (i + 1)
    p.box((kw * 0.55, 0.09, 0.03), (x, -D / 2 - 0.17, 0.73), "ebony")
# The fallboard, folded back against the case, and a music desk on it.
p.box((W - 0.12, 0.04, 0.16), (0, -D / 2 - 0.02, 0.86), "lacquer", bevel=0.006)
p.box((0.7, 0.03, 0.26), (0, -D / 2 - 0.035, 1.02), "lacquer", bevel=0.006)
p.box((0.72, 0.06, 0.02), (0, -D / 2 - 0.05, 0.9), "lacquer", bevel=0.004)
for sx in (-0.12, 0.0, 0.12):
    p.box((0.03, 0.12, 0.012), (sx, -D / 2 - 0.08, 0.06), "brass", bevel=0.004)
p.box((W - 0.12, 0.02, 0.5), (0, -D / 2 - 0.01, 0.32), "lacquer")
p.finish(7.0)


# The double bass: built standing (long axis Z, belly toward -Y), then laid down.
def bass_halfwidth(t):
    pts = [(0.0, 0.0), (0.025, 0.2), (0.08, 0.3), (0.2, 0.355), (0.32, 0.34), (0.42, 0.27), (0.5, 0.215),
           (0.58, 0.225), (0.7, 0.265), (0.8, 0.26), (0.9, 0.21), (0.96, 0.13), (1.0, 0.0)]
    for (t0, w0), (t1, w1) in zip(pts, pts[1:]):
        if t <= t1:
            u = (t - t0) / (t1 - t0)
            u = u * u * (3 - 2 * u)
            return w0 + (w1 - w0) * u
    return 0.0


b = Part("Bass")
bm = b.bm
BODY = 1.12
RIB = 0.1
STEPS = 40
SIDES = 28
rings = []
for i in range(1, STEPS):
    t = i / STEPS
    hw = bass_halfwidth(t)
    ring = []
    for k in range(SIDES):
        a = 2 * math.pi * k / SIDES
        c, sn = math.cos(a), math.sin(a)
        x = hw * math.copysign(abs(c) ** 0.55, c)
        # Ribs straight, top and back arched a little more in the middle.
        y = (RIB + 0.035 * (1 - (x / max(hw, 1e-3)) ** 2)) * math.copysign(abs(sn) ** 0.45, sn)
        ring.append(bm.verts.new((x, y, t * BODY)))
    rings.append(ring)
k = b.index("varnish")
for i in range(len(rings) - 1):
    for s in range(SIDES):
        f = bm.faces.new((rings[i][s], rings[i][(s + 1) % SIDES], rings[i + 1][(s + 1) % SIDES], rings[i + 1][s]))
        f.material_index = k
for ring, z, flip in ((rings[0], 0.0, True), (rings[-1], BODY, False)):
    tip = bm.verts.new((0, 0, z))
    for s in range(SIDES):
        f = bm.faces.new((ring[(s + 1) % SIDES], ring[s], tip) if flip else (ring[s], ring[(s + 1) % SIDES], tip))
        f.material_index = k
body_verts = set(bm.verts)
TOP = -(RIB + 0.035)
# The neck and its fingerboard, which runs on down over the belly; the pegbox and scroll.
b.box((0.07, 0.06, 0.62), (0, TOP + 0.05, BODY + 0.29), "varnish", bevel=0.01)
b.box((0.075, 0.02, 0.95), (0, TOP - 0.02, BODY + 0.1), "ebony", bevel=0.004)
b.box((0.06, 0.07, 0.22), (0, TOP + 0.04, BODY + 0.71), "varnish", bevel=0.01)
scroll = []
for s in range(13):
    a = 2.2 * math.pi * s / 12
    r = 0.06 * (1 - 0.06 * s)
    scroll.append((0, TOP + 0.04 + r * math.sin(a), BODY + 0.86 + r * (1 - math.cos(a)) * 0.9))
b.tube(scroll, 0.026, "varnish", sides=10)
for i, z in enumerate((0.65, 0.72, 0.79)):
    for sx in (-1, 1):
        if i == 2 and sx > 0:
            continue
        b.tube([(sx * 0.03, TOP + 0.04, BODY + z), (sx * 0.1, TOP + 0.04, BODY + z)], 0.007, "brass", sides=6)
        b.box((0.012, 0.04, 0.03), (sx * 0.105, TOP + 0.04, BODY + z), "brass")
# The bridge, the tailpiece and the end pin.
b.box((0.2, 0.012, 0.15), (0, TOP - 0.075, 0.44), "ivory", bevel=0.004)
b.box((0.09, 0.016, 0.3), (0, TOP - 0.05, 0.19), "ebony", bevel=0.006)
b.tube([(0, 0, 0.0), (0, 0, -0.08)], 0.012, "iron", sides=8)
# Four strings, from the tailpiece over the bridge to the nut.
for i in range(4):
    x = -0.045 + i * 0.03
    b.tube([(x * 0.8, TOP - 0.06, 0.3), (x, TOP - 0.152, 0.44), (x * 0.55, TOP - 0.036, BODY + 0.58)], 0.0022 + 0.0006 * (3 - i),
           "string", sides=5)
# The f-holes: thin dark slots in an S, either side of the bridge.
for sx in (-1, 1):
    pts = []
    for s in range(9):
        u = s / 8
        pts.append((sx * (0.12 + 0.025 * math.sin(u * math.pi * 2)), TOP + 0.002, 0.35 + u * 0.24))
    b.tube(pts, 0.006, "ebony", sides=5)

# Laid down: on its side, then tipped about its length until it rests on its body and its scroll.
neck_verts = [v for v in bm.verts if v not in body_verts]
for v in bm.verts:
    v.co = Vector((v.co.z, v.co.y, v.co.x))
best = None
for i in range(-400, 400):
    ang = i * 0.001
    rot = [Vector((v.co.x * math.cos(ang) - v.co.z * math.sin(ang), v.co.y, v.co.x * math.sin(ang) + v.co.z * math.cos(ang)))
           for v in bm.verts]
    lo_body = min(rot[j].z for j, v in enumerate(bm.verts) if v in body_verts)
    lo_head = min(rot[j].z for j, v in enumerate(bm.verts) if v not in body_verts and v.co.x > BODY + 0.5)
    if best is None or abs(lo_body - lo_head) < best[0]:
        best = (abs(lo_body - lo_head), ang)
ang = best[1]
for v in bm.verts:
    v.co = Vector((v.co.x * math.cos(ang) - v.co.z * math.sin(ang), v.co.y, v.co.x * math.sin(ang) + v.co.z * math.cos(ang)))
low = min(v.co.z for v in bm.verts)
for v in bm.verts:
    v.co.z -= low
print("bass tipped %.3f rad" % ang)
b.finish(9.0)

# The glasses: (profile of the glass, profile of what is left in it or None).
GLASSES = [
    ([(0.0, 0.0), (0.04, 0.0), (0.042, 0.004), (0.042, 0.085), (0.038, 0.085), (0.037, 0.016), (0.0, 0.016)],
     [(0.0, 0.016), (0.036, 0.016), (0.036, 0.04), (0.0, 0.04)], "whisky"),
    ([(0.0, 0.0), (0.035, 0.0), (0.036, 0.004), (0.004, 0.01), (0.004, 0.09), (0.03, 0.11), (0.042, 0.15),
      (0.036, 0.205), (0.033, 0.205), (0.038, 0.15), (0.0, 0.098)],
     [(0.0, 0.1), (0.026, 0.115), (0.036, 0.135), (0.0, 0.135)], "wine"),
    ([(0.0, 0.0), (0.035, 0.0), (0.036, 0.004), (0.004, 0.01), (0.004, 0.1), (0.04, 0.12), (0.052, 0.15),
      (0.049, 0.15), (0.0, 0.11)], None, None),
]
for i, (glass, drink, kind) in enumerate(GLASSES):
    g = Part("Glass%d" % i)
    g.lathe(glass, "glass_clear", sides=20)
    if drink:
        g.lathe(drink, kind, sides=20)
    g.finish(10.0 + i * 0.2)

# The hat: a fedora, its crown pinched, a ribbon round it.
h = Part("Hat")
h.lathe([(0.0, 0.0), (0.17, 0.0), (0.175, 0.008), (0.1, 0.012), (0.095, 0.1), (0.07, 0.125), (0.0, 0.11)], "felt", sides=32)
h.lathe([(0.097, 0.012), (0.096, 0.042)], "ribbon", sides=32)
h.bm.verts.ensure_lookup_table()
for v in h.bm.verts:
    if v.co.z > 0.05:
        v.co.y *= 0.82
h.finish(11.0)

# The coat: cloth dropped over a bench's back and seat (the Banquette's own shapes, as a collider).
collider = bpy.data.objects.new("BenchCollider", bpy.data.meshes.new("BenchCollider"))
bpy.context.scene.collection.objects.link(collider)
cb = bmesh.new()
for size, at in (((LENGTH, 0.5, 0.34), (0, 0.0, 0.17)), ((LENGTH, 0.24, 1.17), (0, 0.22, 0.585)),
                 ((4.0, 4.0, 0.1), (0, 0, -0.05))):
    geom = bmesh.ops.create_cube(cb, size=1.0)
    for v in geom["verts"]:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(at)
cb.to_mesh(collider.data)
cb.free()
bpy.context.view_layer.objects.active = collider
bpy.ops.object.modifier_add(type="COLLISION")
collider.collision.thickness_outer = 0.012
collider.collision.cloth_friction = 80.0
collider.collision.damping = 0.9
bpy.ops.mesh.primitive_grid_add(x_subdivisions=28, y_subdivisions=48, size=1.0)
coat = bpy.context.active_object
coat.name = "Coat"
coat.data.name = "Coat"
coat.scale = (0.75, 1.75, 1.0)
coat.rotation_euler = (0.0, 0.0, 0.12)
coat.location = (0.2, 0.12, 1.24)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
cloth = coat.modifiers.new("Cloth", "CLOTH")
cloth.settings.quality = 8
cloth.settings.mass = 0.6
cloth.settings.tension_stiffness = 20
cloth.settings.compression_stiffness = 20
cloth.settings.bending_stiffness = 6.0
cloth.collision_settings.use_self_collision = True
cloth.collision_settings.distance_min = 0.006
scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = 90
cloth.point_cache.frame_end = 90
for f in range(1, 91):
    scene.frame_set(f)
bpy.context.view_layer.objects.active = coat
for o in scene.objects:
    o.select_set(o == coat)
bpy.ops.object.modifier_apply(modifier="Cloth")
# The sim leaves a fine crumple all over; wool hangs in fewer, softer folds.
smooth = coat.modifiers.new("Soften", "SMOOTH")
smooth.factor = 0.6
smooth.iterations = 6
bpy.ops.object.modifier_apply(modifier="Soften")
sol = coat.modifiers.new("Thick", "SOLIDIFY")
sol.thickness = 0.012
bpy.ops.object.modifier_apply(modifier="Thick")
coat.data.materials.append(mats["wool"])
for poly in coat.data.polygons:
    poly.use_smooth = True
bpy.ops.object.shade_auto_smooth(angle=math.radians(60))
bpy.data.objects.remove(collider)
print("Coat: %d faces, lowest %.3f" % (len(coat.data.polygons), min(v.co.z for v in coat.data.vertices)))
coat.location.x = 12.0

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/club.glb"), export_format="GLB")
print("wrote club.glb")
