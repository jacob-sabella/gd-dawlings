# Builds the rowing boat moored at the glowworm lake's landing and writes assets/models/cave_boat.glb.
#
#     blender --background --python tools/blender/cave_boat.py
#
# A small clinker-ish rowing boat, 3 m long: a lofted hull with a square transom at the stern and
# a fine bow, its sheer rising toward the bow, planked inside, two thwarts across it and a pair of
# oars shipped along them. Blender +X is the bow (Godot +X); +Z up. The origin is on the water
# line at the boat's middle: it floats with its origin on the lake's surface.
# Materials "hull" (paint outside), "wood" (bare boards inside, the thwarts, the oars) and
# "iron" (the bow's mooring ring).

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
mats = {n: bpy.data.materials.new(n) for n in ["hull", "wood", "iron"]}

LENGTH = 3.0
BEAM = 0.58
# The water line on the hull, measured up from the keel.
DRAUGHT = 0.16
STATIONS = 28
AROUND = 12


def station(t):
    """Half beam, keel height and sheer height at t along the hull, stern (0) to bow (1)."""
    half = BEAM * math.sin(math.pi * (0.22 + 0.78 * t)) ** 0.55
    if t > 0.97:
        half *= (1.0 - t) / 0.03
    keel = 0.2 * max(0.0, t - 0.7) ** 2 * 11.0
    sheer = 0.5 + 0.16 * t ** 3 + 0.04 * (1.0 - t) ** 3
    return half, keel, sheer


bm = bmesh.new()
rows = []
for i in range(STATIONS + 1):
    t = i / STATIONS
    half, keel, sheer = station(t)
    x = (t - 0.5) * LENGTH
    row = []
    for k in range(AROUND + 1):
        # From the keel up to the starboard gunwale, then mirrored for port.
        s = k / AROUND
        y = half * math.sin(s * math.pi / 2) ** 0.6
        z = keel + (sheer - keel) * (1.0 - math.cos(s * math.pi / 2)) ** 0.9
        # The planks: a small step at each strake, the clinker's lap.
        y += 0.006 * ((k % 3) == 0)
        row.append((x, y, z - DRAUGHT))
    rows.append(row)
grid = []
for row in rows:
    port = [bm.verts.new((x, -y, z)) for x, y, z in reversed(row[1:])]
    keel = bm.verts.new(row[0])
    star = [bm.verts.new(p) for p in row[1:]]
    grid.append(port + [keel] + star)
for i in range(STATIONS):
    for k in range(len(grid[i]) - 1):
        bm.faces.new((grid[i][k], grid[i + 1][k], grid[i + 1][k + 1], grid[i][k + 1]))
# The transom: a flat board across the stern.
bm.faces.new(list(reversed(grid[0])))
mesh = bpy.data.meshes.new("Hull")
bm.normal_update()
bm.to_mesh(mesh)
bm.free()
mesh.materials.append(mats["hull"])
mesh.materials.append(mats["wood"])
hull = bpy.data.objects.new("Hull", mesh)
bpy.context.scene.collection.objects.link(hull)
bpy.context.view_layer.objects.active = hull
solid = hull.modifiers.new("Planks", "SOLIDIFY")
solid.thickness = 0.022
solid.offset = -1.0
solid.material_offset = 1
solid.material_offset_rim = 1
for o in bpy.context.scene.objects:
    o.select_set(o == hull)
bpy.ops.object.modifier_apply(modifier=solid.name)
for p in hull.data.polygons:
    p.use_smooth = True
bpy.ops.object.shade_auto_smooth(angle=math.radians(35))


def board(name, size, at, material, rot=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.data.materials.append(mats[material])
    return o


parts = []
# Two thwarts across, at seat height, a little short of the planking either side.
for x in (-0.55, 0.35):
    half, keel, sheer = station(x / LENGTH + 0.5)
    parts.append(board("Thwart", (0.22, half * 1.8, 0.03), (x, 0.0, sheer - 0.14 - DRAUGHT), "wood"))
# Floorboards over the keel.
parts.append(board("Floor", (1.9, 0.5, 0.02), (-0.1, 0.0, 0.07 - DRAUGHT), "wood"))
# A gunwale rubbing strip each side, along the sheer.
for side in (-1, 1):
    pts = []
    for i in range(3, STATIONS - 2):
        t = i / STATIONS
        half, keel, sheer = station(t)
        pts.append(Vector(((t - 0.5) * LENGTH, side * (half + 0.012), sheer - 0.02 - DRAUGHT)))
    curve = bpy.data.curves.new("Rub", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.018
    curve.bevel_resolution = 1
    spline = curve.splines.new("POLY")
    spline.points.add(len(pts) - 1)
    for p, c in zip(spline.points, pts):
        p.co = (c.x, c.y, c.z, 1.0)
    rub = bpy.data.objects.new("Rub", curve)
    bpy.context.scene.collection.objects.link(rub)
    curve.materials.append(mats["wood"])
    for o in bpy.context.scene.objects:
        o.select_set(o == rub)
    bpy.context.view_layer.objects.active = rub
    bpy.ops.object.convert(target="MESH")
    parts.append(bpy.context.active_object)
# The oars, shipped: lying along the thwarts, blades toward the bow.
for side in (-1, 1):
    y = side * 0.2
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.02, depth=2.1, location=(0.05, y, 0.39 - DRAUGHT + 0.03),
                                        rotation=(0.0, math.pi / 2, 0.0))
    shaft = bpy.context.active_object
    shaft.data.materials.append(mats["wood"])
    parts.append(shaft)
    parts.append(board("Blade", (0.48, 0.13, 0.012), (1.1, y, 0.39 - DRAUGHT + 0.03), "wood"))
# The mooring ring on the stem head.
bpy.ops.mesh.primitive_torus_add(major_radius=0.035, minor_radius=0.007, location=(LENGTH * 0.5 - 0.06, 0.0,
                                 station(0.98)[2] - 0.06 - DRAUGHT), rotation=(math.pi / 2, 0.0, 0.0))
ring = bpy.context.active_object
ring.data.materials.append(mats["iron"])
parts.append(ring)

for o in bpy.context.scene.objects:
    o.select_set(o in parts or o == hull)
bpy.context.view_layer.objects.active = hull
bpy.ops.object.join()
boat = bpy.context.active_object
boat.name = "Boat"
bb = [Vector(c) for c in boat.bound_box]
print("Boat: %d faces, x %.2f..%.2f z %.2f..%.2f" % (len(boat.data.polygons), min(p.x for p in bb), max(p.x for p in bb),
                                                    min(p.z for p in bb), max(p.z for p in bb)))
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/cave_boat.glb"), export_format="GLB")
print("wrote cave_boat.glb")
