# Builds the deep dome's hydrothermal vent field and writes assets/models/dome_vent.glb.
#
#     blender --background --python tools/blender/dome_vent.py
#
# A black smoker: a mound of sulphide rubble eight metres across, and on it a cluster of
# chimneys, the tallest seven metres, lumpy and ledged where the mineral has built out in
# flanges, each open at the top where the hot water comes out (a rim of dull glow in its throat).
# Round their feet, thickets of tube worms: white tubes, each with its red plume.
#
# Blender Z up (Godot +Y), the origin on the sea floor at the mound's middle.
#
# Objects:
#   Vent        the mound and the chimneys. Materials "rock" (the sulphide, near black), "glow"
#               (the throat of each chimney).
#   Worms       the tube worms. Materials "worm" (the tubes), "plume" (their red tips).
#   Smoke.*     empties at each chimney's mouth, where DomeVenue lets the smoke out.

import math
import os
import random

import bpy
import bmesh
from mathutils import Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(5)
NAMES = ["rock", "glow", "worm", "plume"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}


def finish(bm, name, names, angle=50):
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for n in names:
        mesh.materials.append(mats[n])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
    print("%s: %d faces" % (name, len(mesh.polygons)))
    return obj


bm = bmesh.new()

# The mound: a flattened lumpy dome of rubble, its foot below the sand.
mound = bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0)
for v in mound["verts"]:
    d = v.co.normalized()
    bump = noise.fractal(d * 2.2 + Vector((3, 1, 7)), 0.6, 2.0, 5) * 0.28
    v.co = Vector((d.x * 4.2, d.y * 3.6, d.z * 1.5)) * (1.0 + bump)
    v.co.z -= 0.35

# The chimneys: lathed up a wandering axis, the radius pushed about by noise and stepped out in
# flanges every so often.
CHIMNEYS = [  # base (x, y), height, base radius
    ((0.2, 0.0), 7.0, 0.85),
    ((-1.6, 0.9), 5.0, 0.6),
    ((1.5, -1.0), 4.2, 0.55),
    ((-0.6, -1.5), 3.1, 0.45),
    ((2.4, 1.0), 2.4, 0.4),
    ((-2.6, -0.4), 1.8, 0.35),
]
mouths = []
SIDES = 18
for ci, ((bx, by), height, r0) in enumerate(CHIMNEYS):
    base_z = 0.4
    rings = []
    steps = int(height / 0.1)
    lean = Vector((random.uniform(-0.25, 0.25), random.uniform(-0.25, 0.25), 0))
    # Flanges: (how far up, how far out, which way round they face, how far round they reach).
    flanges = [(random.uniform(0.2, 0.9), random.uniform(0.25, 0.6), random.uniform(0, 2 * math.pi),
                random.uniform(0.6, 1.6)) for _ in range(3)]
    for i in range(steps + 1):
        h = i / steps
        centre = Vector((bx, by, base_z + h * height)) + lean * h * h * height * 0.2
        centre += Vector((noise.noise(Vector((h * 3, ci, 0))), noise.noise(Vector((ci, h * 3, 1))), 0)) * 0.15
        r = r0 * (1.0 - 0.55 * h)
        ring = []
        for s in range(SIDES):
            a = 2 * math.pi * s / SIDES
            d = Vector((math.cos(a), math.sin(a), 0))
            # Knobbly: big lumps up the length and small ones round it, and flanges only part of
            # the way round, the way the mineral builds out.
            k = 1.0 + 0.3 * noise.noise(d * 1.5 + Vector((ci * 5.0, 0, h * height * 0.8))) \
                + 0.1 * noise.noise(d * 5.0 + Vector((0, ci * 3.0, h * height * 3.0)))
            for fl, out, face, reach in flanges:
                round_ = max(0.0, math.cos(a - face)) ** (1.0 / reach)
                k += out * round_ * math.exp(-((h - fl) * height / 0.12) ** 2) * (1.0 - h * 0.5)
            k = max(0.55, k)
            ring.append(bm.verts.new(centre + d * r * k))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(SIDES):
            bm.faces.new((rings[i][s], rings[i][(s + 1) % SIDES], rings[i + 1][(s + 1) % SIDES], rings[i + 1][s]))
    # The mouth: the rim rolled in and down into a throat that glows.
    top = rings[-1]
    centre = sum((v.co for v in top), Vector()) / SIDES
    inner = [bm.verts.new(centre + (v.co - centre) * 0.55) for v in top]
    for s in range(SIDES):
        bm.faces.new((top[s], top[(s + 1) % SIDES], inner[(s + 1) % SIDES], inner[s]))
    throat = [bm.verts.new(v.co - Vector((0, 0, 0.4))) for v in inner]
    glow = []
    for s in range(SIDES):
        glow.append(bm.faces.new((inner[s], inner[(s + 1) % SIDES], throat[(s + 1) % SIDES], throat[s])))
    glow.append(bm.faces.new(list(reversed(throat))))
    for f in glow:
        f.material_index = 1
    mouths.append(centre.copy())

finish(bm, "Vent", ["rock", "glow"], 40)

# The worms: clumps round the chimneys' feet, on the mound's flanks.
bm = bmesh.new()
for clump in range(14):
    a = random.uniform(0, 2 * math.pi)
    d = random.uniform(1.6, 3.4)
    cx, cy = math.cos(a) * d * 1.05, math.sin(a) * d * 0.9
    # On the mound's surface, roughly.
    cz = max(0.0, 1.15 * (1.0 - (d / 4.0) ** 2)) - 0.15
    for w in range(random.randint(10, 22)):
        ox, oy = random.gauss(0, 0.22), random.gauss(0, 0.22)
        foot = Vector((cx + ox, cy + oy, cz - 0.1))
        length = random.uniform(0.35, 1.1)
        tip_dir = Vector((ox * 0.8 + random.uniform(-0.15, 0.15), oy * 0.8 + random.uniform(-0.15, 0.15), 1.0)).normalized()
        r = random.uniform(0.018, 0.032)
        sides = 6
        side = tip_dir.cross(Vector((1, 0, 0))).normalized()
        up = side.cross(tip_dir)
        prev = None
        segs = 4
        for k in range(segs + 1):
            t = k / segs
            # A gentle curve: they lean out more toward the tip.
            p = foot + Vector((0, 0, 1)) * length * t * (1 - t) * 0.4 + tip_dir * length * t
            ring = [bm.verts.new(p + (side * math.cos(2 * math.pi * s / sides) + up * math.sin(2 * math.pi * s / sides)) * r)
                    for s in range(sides)]
            if prev:
                for s in range(sides):
                    bm.faces.new((prev[s], prev[(s + 1) % sides], ring[(s + 1) % sides], ring[s]))
            prev = ring
        tip = foot + tip_dir * length + Vector((0, 0, 0))
        # The plume: a feathery red bulb on the end.
        plume = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=r * 2.3)
        for v in plume["verts"]:
            v.co = Vector((v.co.x, v.co.y, v.co.z * 1.8)) + tip + tip_dir * r * 2.5
        for f in {f for v in plume["verts"] for f in v.link_faces}:
            f.material_index = 1
finish(bm, "Worms", ["worm", "plume"], 60)

for i, m in enumerate(mouths):
    e = bpy.data.objects.new("Smoke.%d" % i, None)
    e.location = m
    bpy.context.scene.collection.objects.link(e)

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/dome_vent.glb"), export_format="GLB",
                          export_apply=True)
print("wrote dome_vent.glb")
