# Builds the supply ship docked at the station and writes assets/models/station_ship.glb.
#
#     blender --background --python tools/blender/station_ship.py
#
# An uncrewed cargo freighter, fifteen metres long: a pressurised cargo module (white, ribbed
# with stringers, its berthing port on its flank), a cockpit section forward with a band of small
# lit windows, and a service module aft wrapped in gold foil with four thruster quads, a main
# engine bell and its radiators. Two solar wings, each three panels on a yoke, stand out from the
# service module. Running lights: red to port, green to starboard, white at the tail.
#
# Blender X along the ship, nose at +X (Godot +X); the berthing port faces Blender -Y (Godot
# +Z, toward the station); the origin is the middle of the port's face, where the station's
# tunnel meets it.
#
# Materials "hull" (white paint), "foil" (gold insulation), "dark" (engine, fittings), "cell"
# (solar cells), "frame" (the panels' frames and yokes), "window", "red", "green", "white".

import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
NAMES = ["hull", "foil", "dark", "cell", "frame", "window", "red", "green", "white"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}

R = 1.6           # the cargo module's radius
PORT_OUT = 0.5    # how far the berthing port stands proud of the hull
SIDES = 40

bm = bmesh.new()


def tag(faces, name):
    for f in faces:
        f.material_index = NAMES.index(name)


def lathe(profile, name, sides=SIDES, place=lambda v: v):
    """(x, r) pairs spun round the X axis, then moved by `place`; capped at both ends."""
    rings = []
    for x, r in profile:
        rings.append([bm.verts.new(place(Vector((x, r * math.cos(2 * math.pi * s / sides),
                                                     r * math.sin(2 * math.pi * s / sides))))) for s in range(sides)])
    faces = []
    for i in range(len(rings) - 1):
        for s in range(sides):
            t = (s + 1) % sides
            faces.append(bm.faces.new((rings[i][s], rings[i][t], rings[i + 1][t], rings[i + 1][s])))
    if profile[0][1] > 0:
        faces.append(bm.faces.new(list(reversed(rings[0]))))
    if profile[-1][1] > 0:
        faces.append(bm.faces.new(rings[-1]))
    tag(faces, name)
    return faces


def box(size, at, name, rot=Matrix.Identity(3)):
    geom = bmesh.ops.create_cube(bm, size=1.0)
    for v in geom["verts"]:
        v.co = rot @ Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(at)
    tag({f for v in geom["verts"] for f in v.link_faces}, name)


def cone(at, d):
    """A thruster's nozzle at `at`, opening along `d`."""
    d = d.normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 0.1:
        side = d.cross(Vector((0, 1, 0)))
    side.normalize()
    up = d.cross(side)
    rings = [[bm.verts.new(at + d * x + (side * math.cos(2 * math.pi * k / 10) + up * math.sin(2 * math.pi * k / 10)) * r)
              for k in range(10)] for x, r in [(0.0, 0.05), (0.12, 0.08)]]
    faces = [bm.faces.new((rings[0][k], rings[0][(k + 1) % 10], rings[1][(k + 1) % 10], rings[1][k])) for k in range(10)]
    faces.append(bm.faces.new(list(reversed(rings[0]))))
    faces.append(bm.faces.new(rings[1]))
    tag(faces, "dark")


# Everything is built round the hull's axis at y = R + PORT_OUT (so the port's face is at y = 0),
# then the whole is moved so -Y faces the station.
AXIS = Vector((0, R + PORT_OUT, 0))


def on_axis(v):
    return v + AXIS


# The cargo module, with raised stringer bands; the cockpit forward, tapering to a docking cone.
lathe([(-4.0, R), (4.0, R)], "hull", place=on_axis)
for x in [-3.0, -1.0, 1.0, 3.0]:
    lathe([(x - 0.06, 0), (x - 0.06, R + 0.03), (x + 0.06, R + 0.03), (x + 0.06, 0)], "hull", place=on_axis)
lathe([(4.0, R), (4.6, R * 0.97), (5.6, R * 0.8), (6.4, R * 0.5), (6.7, 0.42), (6.9, 0.42), (6.9, 0.0)], "hull",
      place=on_axis)
# The band of cockpit windows round the cone, lit from inside.
for k in range(10):
    a = math.pi * 0.25 + k * math.pi * 1.5 / 9
    centre = Vector((5.05, math.cos(a) * R * 0.905, math.sin(a) * R * 0.905))
    normal = Vector((0.35, math.cos(a), math.sin(a))).normalized()
    rot = normal.to_track_quat("Y", "Z").to_matrix()
    box((0.42, 0.04, 0.26), centre + normal * 0.02 + AXIS, "window", rot)

# The service module aft: gold foil, a slightly fatter drum, then the engine.
lathe([(-4.0, 0), (-4.0, R + 0.08), (-7.0, R + 0.08), (-7.0, 0)], "foil", place=on_axis)
lathe([(-7.0, R * 0.7), (-7.4, R * 0.6), (-7.4, 0.0)], "dark", place=on_axis)
lathe([(-7.4, 0.25), (-7.6, 0.3), (-8.5, 0.7), (-8.55, 0.72), (-8.55, 0.62), (-7.7, 0.22)], "dark", sides=28,
      place=on_axis)
# Four thruster quads round the service module.
for k in range(4):
    a = math.pi * 0.25 + k * math.pi * 0.5
    d = Vector((0, math.cos(a), math.sin(a)))
    at = Vector((-6.2, 0, 0)) + d * (R + 0.25) + AXIS
    box((0.5, 0.36, 0.36), at, "dark", d.to_track_quat("Y", "X").to_matrix())
    tangent = d.cross(Vector((1, 0, 0)))
    for out in (Vector((1, 0, 0)), Vector((-1, 0, 0)), tangent, -tangent):
        cone(at + out * 0.2, out)

# The berthing port: a stubby drum out of the hull's flank toward the station, a darker ring
# round its face.
lathe([(0.0, 0.0), (0.0, 0.95), (R + PORT_OUT - 0.02, 0.95), (R + PORT_OUT - 0.02, 0.0)], "hull", sides=32,
      place=lambda v: Vector((v.y, R + PORT_OUT - v.x, v.z)))
lathe([(0.0, 0.0), (0.0, 1.08), (0.12, 1.08), (0.12, 0.0)], "dark", sides=32,
      place=lambda v: Vector((v.y, 0.12 - v.x + 0.0, v.z)))

# Two solar wings from the service module's sides (Blender +Z and -Z: up and down the ship's
# sides as it lies), each a yoke and three panels.
for side in (1, -1):
    root = Vector((-5.5, 0, side * (R + 0.08))) + AXIS
    box((0.12, 0.12, 1.1), root + Vector((0, 0, side * 0.55)), "frame")
    for p in range(3):
        c = root + Vector((0, 0, side * (1.1 + 1.0 + p * 2.1)))
        box((3.4, 0.05, 2.0), c, "frame")
        box((3.3, 0.06, 1.9), c, "cell")
# Radiators: two white fins on the service module's back, edge on.
for side in (1, -1):
    box((2.4, 1.6, 0.05), Vector((-5.5, R + 0.8, side * 0.5)) + AXIS, "hull")
# Antennas: a boom with a dish on the cockpit's top, and a whip.
box((0.06, 1.2, 0.06), AXIS + Vector((3.0, R + 0.6, 0)), "frame")
lathe([(0.0, 0.0), (0.05, 0.3), (0.16, 0.5), (0.18, 0.5), (0.07, 0.3), (0.0, 0.05)], "hull", sides=20,
      place=lambda v: Vector((3.0 + v.y, v.x, v.z)) + AXIS + Vector((0, R + 1.15, 0)))

# Running lights: red to port (Blender +Z, the ship's left with its nose at +X and the station
# below), green to starboard, white on the engine.
box((0.12, 0.12, 0.12), Vector((4.2, 0, R + 0.06)) + AXIS, "red")
box((0.12, 0.12, 0.12), Vector((4.2, 0, -R - 0.06)) + AXIS, "green")
box((0.12, 0.12, 0.12), Vector((-7.2, R * 0.65, 0)) + AXIS, "white")

# The Blender build put the port's face at y = 0 facing -Y: as glTF hands it to Godot, -Y is +Z.
mesh = bpy.data.meshes.new("Ship")
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.normal_update()
bm.to_mesh(mesh)
bm.free()
for m in NAMES:
    mesh.materials.append(mats[m])
obj = bpy.data.objects.new("Ship", mesh)
bpy.context.scene.collection.objects.link(obj)
for o in bpy.context.scene.objects:
    o.select_set(o == obj)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
print("Ship: %d faces" % len(mesh.polygons))
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/station_ship.glb"), export_format="GLB",
                          export_apply=True)
print("wrote station_ship.glb")
