# Builds the glasshouse's tropical planting and writes assets/models/greenhouse_plants.glb.
#
#     blender --background --python tools/blender/greenhouse_plants.py
#
# One file, several objects, each placed by GreenhouseVenue by name (most of them as MultiMeshes):
#   Palm       a kentia palm: a ringed grey trunk 4.2 m tall, a green crown shaft, and ten arching
#              feather fronds of drooping leaflets, the crown about 4 m across
#   FanPalm    a Chusan fan palm: a short trunk shaggy with old fibre and a dozen pleated fans on
#              long stalks, 3.2 m tall
#   TreeFern   a Dicksonia: a thick fibrous trunk 2 m tall, a crown of fronds arching out and down
#              and three fiddleheads unrolling in the middle
#   Banana     three pseudostems and their paddle leaves, torn into slats at the edges, 3 m tall
#   Monstera   a clump of split-leaf philodendron: nine heart-shaped leaves slit to the rib, on
#              stalks from the ground, 1.2 m tall
#   Fern       a Boston fern: thirty narrow pinnate fronds arching out of the crown and over,
#              for the hanging baskets and the bed's edge, 0.9 m across
#   Aspidistra a clump of upright strap leaves, the ground cover, 0.6 m tall
#   Bloom      one night-blooming flower (Epiphyllum, queen of the night): a cup of white petals
#              in a star of narrow pale sepals, 0.2 m across, opening toward +Y (Godot -Z)
# Every origin is on the ground at the plant's foot (the flower's at its stalk). Blender Z is up
# (Godot +Y). Materials, which the venue swaps by name: "trunk", "fibre", "stem", "frond",
# "leaf", "leaf_pale", "petal", "heart".

import math
import os
import random

import bpy
import bmesh
from mathutils import Matrix, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(19)
NAMES = ["trunk", "fibre", "stem", "frond", "leaf", "leaf_pale", "petal", "heart"]
COLOURS = {"trunk": (0.32, 0.3, 0.27, 1), "fibre": (0.16, 0.1, 0.06, 1), "stem": (0.22, 0.32, 0.14, 1),
           "frond": (0.14, 0.3, 0.1, 1), "leaf": (0.08, 0.24, 0.08, 1), "leaf_pale": (0.3, 0.45, 0.14, 1),
           "petal": (0.95, 0.93, 0.86, 1), "heart": (0.9, 0.82, 0.4, 1)}
mats = {}
for n in NAMES:
    m = bpy.data.materials.new(n)
    m.diffuse_color = COLOURS[n]
    m.use_backface_culling = False
    mats[n] = m

UP = Vector((0, 0, 1))


class Builder:
    """One object's bmesh, with its material slots named up front."""

    def __init__(self, name, slots):
        self.name = name
        self.slots = slots
        self.bm = bmesh.new()

    def face(self, verts, slot):
        f = self.bm.faces.new([self.bm.verts.new(v) if not isinstance(v, bmesh.types.BMVert) else v for v in verts])
        f.material_index = self.slots.index(slot)
        return f

    def ring(self, centre, radius, sides, axis=UP, phase=0.0, squash=1.0):
        axis = Vector(axis).normalized()
        side = axis.cross(Vector((0.31, 0.95, 0.0)) if abs(axis.z) > 0.9 else UP).normalized()
        up = side.cross(axis).normalized()
        out = []
        for s in range(sides):
            a = phase + 2 * math.pi * s / sides
            out.append(self.bm.verts.new(Vector(centre) + (side * math.cos(a) + up * math.sin(a) * squash) * radius))
        return out

    def bridge(self, a, b, slot):
        n = len(a)
        for s in range(n):
            self.face([a[s], a[(s + 1) % n], b[(s + 1) % n], b[s]], slot)

    def cap(self, ring_verts, slot, point=None):
        if point is None:
            self.face(list(reversed(ring_verts)), slot)
        else:
            tip = self.bm.verts.new(point)
            n = len(ring_verts)
            for s in range(n):
                self.face([ring_verts[s], ring_verts[(s + 1) % n], tip], slot)

    def tube(self, points, radii, sides, slot, cap_end=True):
        """A tube along a polyline, its radius per point."""
        rings = []
        for i, p in enumerate(points):
            d = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
            rings.append(self.ring(p, radii[i], sides, d))
        for i in range(len(rings) - 1):
            self.bridge(rings[i], rings[i + 1], slot)
        if cap_end:
            self.cap(rings[-1], slot, points[-1] + (points[-1] - points[-2]).normalized() * radii[-1])
        return rings

    def finish(self, x_offset, smooth=True):
        mesh = bpy.data.meshes.new(self.name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-6)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for s in self.slots:
            mesh.materials.append(mats[s])
        for p in mesh.polygons:
            p.use_smooth = smooth
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.location.x = x_offset
        print("%s: %d faces" % (self.name, len(mesh.polygons)))
        return obj


def horizontal(azimuth):
    return Vector((math.cos(azimuth), math.sin(azimuth), 0.0))


def arch(base, azimuth, length, rise, droop, steps):
    """Points along an arching stalk: out along `azimuth`, starting up at `rise` radians and
    bending down by `droop` radians over its length."""
    pts = [Vector(base)]
    p = Vector(base)
    h = horizontal(azimuth)
    for i in range(1, steps + 1):
        t = i / steps
        ang = rise - droop * t ** 1.4
        p = p + (h * math.cos(ang) + UP * math.sin(ang)) * (length / steps)
        pts.append(p.copy())
    return pts


def leaflet(b, root, along, out, length, width, drop, slot, tip_drop=None):
    """A narrow leaf from `root`, reaching `out`, falling `drop` over its length: a kite of five
    points, bent at its middle so it hangs."""
    out = out.normalized()
    along = along.normalized()
    tip_drop = drop if tip_drop is None else tip_drop
    mid = root + out * length * 0.5 - UP * drop * 0.35
    tip = root + out * length - UP * tip_drop
    w = along * width * 0.5
    b.face([root - w * 0.6, root + w * 0.6, mid + w, mid - w], slot)
    b.face([mid - w, mid + w, tip], slot)


# --- the kentia palm --------------------------------------------------------------------------

def palm():
    b = Builder("Palm", ["trunk", "stem", "frond"])
    height = 4.2
    lean = horizontal(0.7) * 0.25
    pts, radii = [], []
    rings = 34
    for i in range(rings + 1):
        t = i / rings
        p = Vector((0, 0, t * height)) + lean * t * t
        pts.append(p)
        # Ringed where each old leaf fell: every other ring a little proud. Flared at the foot.
        r = 0.11 - 0.025 * t + (0.06 * (1 - t / 0.08) if t < 0.08 else 0.0)
        radii.append(r * (1.06 if i % 2 else 1.0))
    trunk_rings = b.tube(pts, radii, 9, "trunk", cap_end=False)
    # The crown shaft: smooth and green, a little fatter than the trunk under it.
    top = pts[-1]
    shaft = [top, top + Vector((0, 0, 0.3)), top + Vector((0, 0, 0.6)), top + Vector((0, 0, 0.75))]
    b.tube(shaft, [0.1, 0.12, 0.1, 0.05], 9, "stem")
    crown = top + Vector((0, 0, 0.62))
    fronds = 10
    for f in range(fronds):
        az = f * 2.39996 + random.uniform(-0.2, 0.2)
        # The young ones stand up; the old ones arch right over and hang.
        age = f / (fronds - 1)
        rise = math.radians(70 - 55 * age + random.uniform(-6, 6))
        droop = math.radians(55 + 50 * age)
        length = random.uniform(2.1, 2.6)
        steps = 14
        rach = arch(crown, az, length, rise, droop, steps)
        b.tube(rach, [0.025 * (1 - i / steps * 0.8) for i in range(steps + 1)], 4, "stem")
        side = horizontal(az + math.pi * 0.5)
        pairs = 26
        for k in range(pairs):
            s = 0.12 + 0.86 * k / (pairs - 1)
            idx = s * steps
            i0 = int(idx)
            i1 = min(i0 + 1, steps)
            root = rach[i0].lerp(rach[i1], idx - i0)
            along = (rach[i1] - rach[i0]).normalized()
            ln = 0.62 * math.sin(math.pi * min(s * 1.05, 1.0)) ** 0.55 + 0.06
            for sgn in (-1, 1):
                # Out to the side, a little forward, and down: the leaflets hang in a V.
                out = side * sgn + along * 0.35 - UP * 0.25
                leaflet(b, root, along, out, ln, 0.045, ln * 0.35, "frond")
    return b.finish(0.0)


# --- the fan palm -----------------------------------------------------------------------------

def fan_palm():
    b = Builder("FanPalm", ["fibre", "stem", "frond"])
    height = 2.0
    pts = [Vector((0, 0, height * i / 10)) for i in range(11)]
    radii = []
    for i in range(11):
        t = i / 10
        radii.append(0.15 + 0.03 * noise.noise(Vector((0, 0, t * 9.0))) + (0.05 if i == 0 else 0.0))
    b.tube(pts, radii, 10, "fibre", cap_end=False)
    # Shaggy: old leaf bases as rough flaps round the top of the trunk.
    for k in range(18):
        az = k * 2.39996
        z = height * random.uniform(0.55, 0.98)
        root = Vector((0, 0, z)) + horizontal(az) * 0.14
        out = horizontal(az) * 0.6 - UP * 0.8
        leaflet(b, root, horizontal(az + 1.57), out, 0.32, 0.1, 0.05, "fibre")
    crown = Vector((0, 0, height))
    for f in range(13):
        az = f * 2.39996 + random.uniform(-0.15, 0.15)
        age = f / 12
        rise = math.radians(75 - 50 * age)
        stalk = arch(crown, az, random.uniform(0.75, 1.0), rise, math.radians(15 + 25 * age), 4)
        b.tube(stalk, [0.022, 0.02, 0.018, 0.016, 0.014], 4, "stem", cap_end=False)
        hub = stalk[-1]
        forward = (stalk[-1] - stalk[-2]).normalized()
        across = forward.cross(UP).normalized()
        if across.length < 0.1:
            across = horizontal(az + 1.57)
        # The fan faces up and out, square to the stalk: a near-circle of pleated segments.
        normal = across.cross(forward).normalized()
        if normal.z < 0:
            normal = -normal
        segs = 30
        radius = random.uniform(0.55, 0.7)
        span = math.radians(250)
        prev = None
        for k in range(segs + 1):
            a = -span * 0.5 + span * k / segs
            ray = (forward * math.cos(a) + across * math.sin(a)).normalized()
            pleat = (0.035 if k % 2 else -0.035)
            col = []
            for j, rr in enumerate((0.05, 0.4, 0.75, 1.0)):
                r = radius * rr
                # The outer third of each segment hangs free and droops.
                sag = 0.45 * max(0.0, rr - 0.45) ** 1.6
                col.append(hub + ray * r + normal * (pleat * rr - sag) - UP * sag * 0.6)
            if prev is not None:
                for j in range(3):
                    # Split from the edge in to just past halfway: the fan's fingers.
                    if j == 2 and k % 2 == 0:
                        continue
                    b.face([prev[j], col[j], col[j + 1], prev[j + 1]], "frond")
            prev = col
    return b.finish(2.0)


# --- the tree fern ----------------------------------------------------------------------------

def tree_fern():
    b = Builder("TreeFern", ["fibre", "stem", "frond"])
    height = 2.0
    pts, radii = [], []
    for i in range(13):
        t = i / 12
        pts.append(Vector((0.06 * math.sin(t * 2.5), 0.04 * math.sin(t * 1.7), t * height)))
        radii.append(0.2 - 0.04 * t + 0.025 * noise.noise(Vector((t * 7.0, 0.3, 0.0))) + (0.06 if i == 0 else 0))
    b.tube(pts, radii, 11, "fibre", cap_end=False)
    crown = pts[-1] + Vector((0, 0, 0.04))
    b.cap(b.ring(pts[-1], radii[-1], 11), "fibre", crown)
    for f in range(13):
        az = f * 2.39996 + random.uniform(-0.2, 0.2)
        age = f / 12
        length = random.uniform(1.5, 1.9)
        steps = 12
        rach = arch(crown, az, length, math.radians(55 - 30 * age), math.radians(70 + 30 * age), steps)
        b.tube(rach, [0.02 * (1 - i / steps * 0.7) for i in range(steps + 1)], 4, "stem", cap_end=False)
        side = horizontal(az + math.pi * 0.5)
        for k in range(16):
            s = 0.1 + 0.88 * k / 15
            idx = s * steps
            i0 = int(idx)
            i1 = min(i0 + 1, steps)
            root = rach[i0].lerp(rach[i1], idx - i0)
            along = (rach[i1] - rach[i0]).normalized()
            ln = 0.42 * math.sin(math.pi * min(s * 1.1, 1.0)) ** 0.7 + 0.04
            for sgn in (-1, 1):
                out = (side * sgn + along * 0.5).normalized()
                # A pinna: a strip with lobed edges, flat-ish, curling down at its tip.
                stations = 6
                left, right = [], []
                for j in range(stations + 1):
                    u = j / stations
                    p = root + out * ln * u - UP * 0.12 * ln * u * u
                    w = (0.05 * (1 - u) + 0.006) * (1.25 if j % 2 else 0.8)
                    left.append(p + along * w)
                    right.append(p - along * w)
                for j in range(stations):
                    b.face([left[j], right[j], right[j + 1], left[j + 1]], "frond")
    # Fiddleheads: young fronds still unrolling in the crown.
    for k in range(3):
        az = k * 2.1 + 0.4
        h = horizontal(az)
        spiral = []
        for i in range(16):
            t = i / 15
            ang = t * math.pi * 2.2
            r = 0.16 * (1 - t * 0.85)
            spiral.append(crown + h * (0.04 + r * math.sin(ang)) + UP * (0.05 + 0.25 * t + r * (1 - math.cos(ang)) * 0.5))
        b.tube(spiral, [0.018 * (1 - i / 20) for i in range(16)], 5, "stem")
    return b.finish(4.0)


# --- the banana -------------------------------------------------------------------------------

def banana_leaf(b, base, az, length, width, rise, droop):
    steps = 12
    rib = arch(base, az, length, rise, droop, steps)
    b.tube(rib, [0.02 * (1 - i / steps * 0.8) for i in range(steps + 1)], 4, "stem", cap_end=False)
    side = horizontal(az + math.pi * 0.5)
    cols = 3
    for sgn in (-1, 1):
        prev = None
        for i in range(steps + 1):
            u = i / steps
            # Paddle-shaped: blunt at the tip, narrowing to the stalk.
            w = width * (math.sin(math.pi * min(0.15 + u * 0.95, 1.0)) ** 0.5) * (0.2 if u < 0.12 else 1.0)
            fold = 0.16
            col = [rib[i]]
            for c in range(1, cols + 1):
                f = c / cols
                # Folded down from the midrib, the edge drooping a little more.
                col.append(rib[i] + side * sgn * w * f - UP * w * (fold * f + 0.12 * f * f))
            if prev is not None and u > 0.12:
                for c in range(cols):
                    # Torn: here and there the outer part splits between two ribs.
                    if c >= 1 and random.random() < 0.28:
                        continue
                    b.face([prev[c], col[c], col[c + 1], prev[c + 1]], "leaf_pale")
            prev = col


def banana():
    b = Builder("Banana", ["stem", "leaf_pale"])
    for s, (at, h) in enumerate([((0, 0), 1.8), ((0.35, 0.18), 1.35), ((-0.2, 0.32), 1.0)]):
        base = Vector((at[0], at[1], 0))
        pts = [base + Vector((0, 0, h * i / 6)) for i in range(7)]
        b.tube(pts, [0.13 - 0.04 * i / 6 for i in range(7)], 8, "stem", cap_end=False)
        top = pts[-1]
        for k in range(6 if s == 0 else 4):
            az = k * 2.39996 + s
            age = k / 5
            banana_leaf(b, top - Vector((0, 0, 0.05 * k)), az, random.uniform(1.4, 1.9) * (0.85 if s else 1.0),
                        random.uniform(0.28, 0.34), math.radians(78 - 50 * age), math.radians(55 + 50 * age))
    return b.finish(6.0)


# --- the monstera -----------------------------------------------------------------------------

def monstera_leaf(b, tip_of_stalk, az, size, tilt):
    """A heart-shaped blade, the stalk joining at its notch, cut into lobes by slits from the
    edge to near the rib, with a hole or two along the rib."""
    forward = (horizontal(az) * math.cos(tilt) - UP * math.sin(tilt)).normalized()
    side = horizontal(az + math.pi * 0.5)
    normal = side.cross(forward).normalized()
    if normal.z < 0:
        normal = -normal
    lobes = 7
    rib = [tip_of_stalk + forward * size * (i / lobes) - normal * 0.08 * size * (i / lobes) ** 2
           for i in range(lobes + 1)]
    for sgn in (-1, 1):
        for k in range(lobes):
            u0, u1 = k / lobes, (k + 1) / lobes
            # The outline: widest a third of the way along, round at the base (the heart's lobes
            # reach back past the notch), pointed at the tip.
            def width(u):
                return size * (0.62 * math.sin(math.pi * min(u * 0.85 + 0.12, 1.0)) ** 0.8)

            def edge(u, back):
                w = width(u)
                # The lobes sweep back toward the stalk.
                return rib[0].lerp(rib[-1], u) + side * sgn * w + forward * (-0.12 * size * back) \
                       - normal * 0.1 * w

            a0, a1 = rib[k], rib[k + 1]
            m0 = a0.lerp(edge(u0, 0.5), 0.3)
            m1 = a1.lerp(edge(u1, 0.5), 0.3)
            gap = 0.22
            e0 = edge(u0 + (u1 - u0) * gap, 1.0)
            e1 = edge(u1, 1.0)
            b.face([a0, a1, m1, m0] if sgn > 0 else [a1, a0, m0, m1], "leaf")
            if not (k == 3 and sgn > 0):
                b.face([m0, m1, e1, e0] if sgn > 0 else [m1, m0, e0, e1], "leaf")


def monstera():
    b = Builder("Monstera", ["stem", "leaf"])
    for k in range(9):
        az = k * 2.39996
        age = k / 8
        stalk = arch(Vector((0, 0, 0)) + horizontal(az) * 0.05, az, random.uniform(0.6, 1.0),
                     math.radians(80 - 25 * age), math.radians(30 + 20 * age), 5)
        b.tube(stalk, [0.016] * 6, 4, "stem", cap_end=False)
        monstera_leaf(b, stalk[-1], az, random.uniform(0.38, 0.5), math.radians(15 + 25 * age))
    return b.finish(8.0)


# --- the Boston fern --------------------------------------------------------------------------

def fern():
    b = Builder("Fern", ["frond"])
    for k in range(30):
        az = k * 2.39996 + random.uniform(-0.1, 0.1)
        length = random.uniform(0.45, 0.62)
        steps = 10
        rach = arch(Vector((0, 0, 0.05)), az, length, math.radians(random.uniform(35, 70)),
                    math.radians(random.uniform(90, 150)), steps)
        side = horizontal(az + math.pi * 0.5)
        left, right = [], []
        for i in range(steps + 1):
            u = i / steps
            w = (0.045 * math.sin(math.pi * min(0.1 + u, 1.0)) ** 0.4 + 0.004) * (1.3 if i % 2 else 0.7)
            left.append(rach[i] + side * w)
            right.append(rach[i] - side * w)
        for i in range(steps):
            b.face([left[i], right[i], right[i + 1], left[i + 1]], "frond")
    return b.finish(10.0)


# --- the aspidistra ---------------------------------------------------------------------------

def aspidistra():
    b = Builder("Aspidistra", ["leaf"])
    for k in range(16):
        az = k * 2.39996
        length = random.uniform(0.45, 0.65)
        steps = 6
        rib = arch(horizontal(az) * 0.04, az, length, math.radians(random.uniform(62, 82)),
                   math.radians(random.uniform(25, 55)), steps)
        side = horizontal(az + math.pi * 0.5)
        left, right = [], []
        for i in range(steps + 1):
            u = i / steps
            w = 0.055 * math.sin(math.pi * min(0.08 + u * 0.95, 1.0)) ** 0.7 + 0.004
            left.append(rib[i] + side * w - UP * w * 0.2)
            right.append(rib[i] - side * w - UP * w * 0.2)
        for i in range(steps):
            b.face([left[i], right[i], right[i + 1], left[i + 1]], "leaf")
    return b.finish(12.0)


# --- the night flower ---------------------------------------------------------------------------

def bloom():
    b = Builder("Bloom", ["petal", "heart", "stem"])
    # Facing +Y (Godot -Z): the venue turns each one to face out of its plant.
    axis = Vector((0, 1, 0))
    up = UP
    side = Vector((1, 0, 0))
    b.tube([Vector((0, -0.06, -0.02)), Vector((0, -0.02, 0)), Vector((0, 0.0, 0))], [0.008, 0.012, 0.02], 5, "stem",
           cap_end=False)

    def petal(n, i, length, width, cup, slot, phase):
        a = phase + 2 * math.pi * i / n
        ray = side * math.cos(a) + up * math.sin(a)
        across = axis.cross(ray).normalized()
        root = Vector((0, 0.01, 0))
        mid = root + ray * length * 0.5 + axis * cup
        tip = root + ray * length + axis * cup * 0.6
        b.face([root - across * width * 0.2, root + across * width * 0.2, mid + across * width * 0.5,
                mid - across * width * 0.5], slot)
        b.face([mid - across * width * 0.5, mid + across * width * 0.5, tip], slot)

    for i in range(10):
        petal(10, i, 0.1, 0.022, 0.02, "petal", 0.0)
    for i in range(9):
        petal(9, i, 0.075, 0.04, 0.045, "petal", 0.3)
    # The stamens: a pale tuft in the throat.
    b.cap(b.ring(Vector((0, 0.03, 0)), 0.012, 6, axis), "heart", Vector((0, 0.07, 0)))
    return b.finish(14.0, smooth=False)


palm()
fan_palm()
tree_fern()
banana()
monstera()
fern()
aspidistra()
bloom()

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/greenhouse_plants.glb"), export_format="GLB")
print("wrote greenhouse_plants.glb")
