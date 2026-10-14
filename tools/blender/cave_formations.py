# Builds the crystal cave's rock formations and writes assets/models/cave_formations.glb.
#
#     blender --background --python tools/blender/cave_formations.py
#
# One file, several objects, each placed by CaveVenue by name (most of them many times over, as
# one MultiMesh a kind):
#   Stalactite0..2  hanging from the roof: a flared root, a long taper ringed where each season's
#                   drip stopped, a thin wet tip, each a little bent. About 1 m long, origin at
#                   the root, hanging down Blender -Z (Godot -Y); the root reaches 0.15 m up into
#                   the rock above so a rough roof never shows a gap round it.
#   Stalagmite0..2  standing on the floor: blunt, rounded tops, wide skirts of flowstone. About
#                   1 m tall, origin on the floor; the skirt runs 0.15 m down into it.
#   Column          a stalactite and a stalagmite that met: 1 m floor to roof, waisted where they
#                   joined, flared at both ends (scaled to the height it spans).
#   Basalt0..1      cooled basalt: a cluster of hexagonal columns, crisp-faceted, their tops
#                   broken at different heights (0) or worn down into a stepped pavement (1).
#   Boulder0..2     fallen rock, lumpy, flat underneath, about a metre across.
# Every origin is where it meets the rock. Materials "rock" (limestone flowstone) and "basalt".

import math
import os
import random

import bpy
import bmesh
from mathutils import Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(11)
NAMES = ["rock", "basalt"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}


def finish(bm, name, mat_name, x_offset, smooth_angle=50):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mats[mat_name])
    for p in mesh.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth_angle))
    obj.location.x = x_offset
    bb = [Vector(c) for c in obj.bound_box]
    print("%s: %d faces, z %.2f..%.2f" % (name, len(mesh.polygons), min(p.z for p in bb), max(p.z for p in bb)))


def lathe(bm, rings, sides, seed, lumps):
    """A closed surface of revolution: `rings` is [(z, radius, (cx, cy))] from one end to the
    other. Each ring is pushed about by noise so nothing is turned on a lathe, and both ends are
    closed on a point."""
    verts = []
    for z, r, c in rings:
        ring = []
        for s in range(sides):
            a = 2 * math.pi * s / sides
            d = Vector((math.cos(a), math.sin(a), 0.0))
            bump = noise.noise(d * 1.3 + Vector((seed, seed * 0.7, z * 2.2))) * lumps
            rr = max(r * (1.0 + bump), 0.0015)
            ring.append(bm.verts.new((c[0] + d.x * rr, c[1] + d.y * rr, z)))
        verts.append(ring)
    for i in range(len(verts) - 1):
        for s in range(sides):
            bm.faces.new((verts[i][s], verts[i][(s + 1) % sides], verts[i + 1][(s + 1) % sides], verts[i + 1][s]))
    first, last = rings[0], rings[-1]
    cap_a = bm.verts.new((first[2][0], first[2][1], first[0]))
    cap_b = bm.verts.new((last[2][0], last[2][1], last[0] + (0.004 if last[0] > first[0] else -0.004)))
    for s in range(sides):
        bm.faces.new((verts[0][(s + 1) % sides], verts[0][s], cap_a))
        bm.faces.new((verts[-1][s], verts[-1][(s + 1) % sides], cap_b))


# --- stalactites -------------------------------------------------------------------------------
# A taper from a flared root to a fine tip, with the rings a drip leaves where it paused, and a
# bend: the roof is never level, and the drip runs down the lean.
for i in range(3):
    bm = bmesh.new()
    seed = i * 4.1 + 1.0
    root = [0.2, 0.15, 0.24][i]
    bend = Vector((random.uniform(-0.12, 0.12), random.uniform(-0.12, 0.12)))
    rings = [(0.15, root * 1.9, (0, 0)), (0.0, root * 1.55, (0, 0))]
    steps = 30
    for k in range(1, steps + 1):
        t = k / steps
        r = root * (1.0 - t) ** 1.5 + 0.004
        # The rings: a swell every few centimetres, fading toward the tip.
        r *= 1.0 + (0.05 * math.sin(t * 46.0 + seed) + 0.03 * math.sin(t * 97.0)) * (1.0 - t)
        if k == 1:
            r = root * 1.15
        c = bend * t * t
        rings.append((-t, r, (c.x, c.y)))
    lathe(bm, rings, 12, seed, 0.22)
    finish(bm, "Stalactite%d" % i, "rock", i * 1.0)

# --- stalagmites -------------------------------------------------------------------------------
# Blunt where a stalactite is sharp: the drop lands and spreads. A wide skirt of flowstone at the
# foot, a body that narrows slowly, a rounded head.
for i in range(3):
    bm = bmesh.new()
    seed = i * 3.3 + 20.0
    body = [0.2, 0.15, 0.26][i]
    lean = Vector((random.uniform(-0.06, 0.06), random.uniform(-0.06, 0.06)))
    rings = [(-0.15, body * 2.3, (0, 0)), (0.0, body * 2.1, (0, 0)), (0.05, body * 1.45, (0, 0))]
    steps = 22
    for k in range(1, steps + 1):
        t = k / steps
        z = 0.05 + t * 0.95
        r = body * (1.0 - t ** 2.4) ** 0.55 * (1.15 - 0.35 * t)
        r *= 1.0 + 0.035 * math.sin(t * 23.0 + seed) + 0.025 * math.sin(t * 61.0 + seed * 2.0)
        c = lean * t
        rings.append((z, max(r, 0.01) if k < steps else 0.01, (c.x, c.y)))
    lathe(bm, rings, 14, seed, 0.2)
    finish(bm, "Stalagmite%d" % i, "rock", 4.0 + i * 1.0)

# --- a column ----------------------------------------------------------------------------------
# Floor to roof in 1 m: flared at both ends, thinnest a little above the middle where the two
# met, ridged with flowstone curtains.
bm = bmesh.new()
rings = [(-0.12, 0.42, (0, 0))]
steps = 34
for k in range(steps + 1):
    t = k / steps
    waist = abs(t - 0.58) / 0.58
    r = 0.07 + 0.2 * waist ** 1.6 + 0.12 * math.exp(-t * 14.0) + 0.1 * math.exp(-(1.0 - t) * 12.0)
    r *= 1.0 + 0.06 * math.sin(t * 40.0)
    rings.append((t, r, (0, 0)))
rings.append((1.12, 0.36, (0, 0)))
lathe(bm, rings, 16, 7.7, 0.25)
finish(bm, "Column", "rock", 8.0)

# --- basalt ------------------------------------------------------------------------------------
# Columns of cooled lava: hexagons packed edge to edge, each a separate prism with its own
# slightly uneven sides, broken off at its own height. Basalt0 is a tall broken stand of them;
# Basalt1 is worn down into a stepped pavement.


def hex_column(bm, cx, cy, r, top, tilt, seed):
    corners = []
    for s in range(6):
        a = math.pi / 3 * s + math.pi / 6
        rr = r * (1.0 + random.uniform(-0.08, 0.06))
        corners.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    bottom = [bm.verts.new((x, y, -0.3)) for x, y in corners]
    tops = []
    for x, y in corners:
        # The break is a plane at a small tilt, and a few millimetres of chatter.
        z = top + (x - cx) * tilt.x + (y - cy) * tilt.y + random.uniform(-0.01, 0.01)
        tops.append(bm.verts.new((x, y, z)))
    for s in range(6):
        bm.faces.new((bottom[s], bottom[(s + 1) % 6], tops[(s + 1) % 6], tops[s]))
    bm.faces.new(tops)
    bm.faces.new(list(reversed(bottom)))


for i, (count, heights) in enumerate([(19, (0.5, 2.0)), (24, (0.08, 0.5))]):
    bm = bmesh.new()
    r = 0.17
    pitch = r * math.sqrt(3) * 1.02
    placed = 0
    ring = 0
    cells = []
    for q in range(-4, 5):
        for s in range(-4, 5):
            x = pitch * (q + s * 0.5)
            y = pitch * s * math.sqrt(3) / 2
            cells.append((math.hypot(x, y), x, y))
    cells.sort()
    for d, x, y in cells[:count]:
        # Tallest in the middle of the stand, and broken lower toward its edge.
        fall = d / (pitch * 3.0)
        top = heights[0] + (heights[1] - heights[0]) * max(0.0, 1.0 - fall) * random.uniform(0.55, 1.0)
        tilt = Vector((random.uniform(-0.25, 0.25), random.uniform(-0.25, 0.25)))
        hex_column(bm, x, y, r * 0.985, top, tilt, i)
    finish(bm, "Basalt%d" % i, "basalt", 12.0 + i * 2.0, smooth_angle=20)

# --- boulders ----------------------------------------------------------------------------------
for i in range(3):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=0.5)
    seed = Vector((i * 5.3 + 2.0, i * 1.7, i * 9.1))
    stretch = Vector((1.0 + random.random() * 0.5, 0.75 + random.random() * 0.4, 0.5 + random.random() * 0.3))
    for v in bm.verts:
        d = v.co.normalized()
        bump = noise.fractal(d * 1.8 + seed, 0.6, 2.0, 4) * 0.2
        # Faceted: a few flat fractures, as fallen rock breaks.
        facet = max(0.0, d.dot(Vector((0.6, 0.3, 0.74)).normalized()) - 0.75) * 0.6
        v.co = Vector((v.co.x * stretch.x, v.co.y * stretch.y, v.co.z * stretch.z)) * (1.0 + bump - facet)
        if v.co.z < -0.08:
            v.co.z = -0.08 - (v.co.z + 0.08) * 0.15
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector((0, 0, 0.06)))
    finish(bm, "Boulder%d" % i, "rock", 17.0 + i * 1.5, smooth_angle=40)

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/cave_formations.glb"), export_format="GLB")
print("wrote cave_formations.glb")
