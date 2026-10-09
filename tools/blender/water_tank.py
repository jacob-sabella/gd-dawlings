# Builds a rooftop water tank and writes assets/models/water_tank.glb.
#
#     blender --background --python tools/blender/water_tank.py
#
# The wooden tank a city roof carries: a barrel of upright cedar staves bound with steel hoops,
# a shallow conical cap with a hatch and a finial, standing on a steel frame of six legs braced
# by a ring beam, with a caged ladder up one side. Three materials, "staves", "steel" and "cap",
# which RooftopVenue swaps by name. The ladder is on Blender -Y (Godot +Z); the origin is on the
# roof under the middle. 3.2 m across, about 6.4 m to the finial.

import math
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
staves = bpy.data.materials.new("staves")
steel = bpy.data.materials.new("steel")
cap = bpy.data.materials.new("cap")

R = 1.6        # the barrel's radius
STAND = 2.4    # the frame, roof to the tank's floor
TALL = 3.0     # the barrel
parts = []


def cyl(name, r, depth, loc, mat, rot=(0, 0, 0), verts=24, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, location=loc, rotation=rot,
                                        vertices=verts)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat)
    parts.append(o)
    return o


def box(name, size, loc, mat, rz=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=(0, 0, rz))
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    parts.append(o)
    return o


# The barrel: 28 sides, so the staves read as boards when the planks texture runs up them.
cyl("barrel", R, TALL, (0, 0, STAND + TALL / 2), staves, verts=28)
# The hoops, a little proud of the staves, closer together low down where the pressure is.
for z in (0.18, 0.5, 0.86, 1.3, 1.85, 2.5):
    cyl("hoop", R + 0.025, 0.05, (0, 0, STAND + z), steel, verts=28)
# The cap: a shallow cone overhanging the barrel, a hatch on it, and a finial.
cyl("cap", R + 0.12, 0.9, (0, 0, STAND + TALL + 0.45), cap, verts=28, r2=0.12)
box("hatch", (0.5, 0.5, 0.1), (0, -0.75, STAND + TALL + 0.32), cap)
cyl("finial", 0.06, 0.4, (0, 0, STAND + TALL + 1.0), steel, verts=8)
# The frame: six legs to a ring beam under the tank's floor, and a cross-brace halfway down.
legs = 6
for i in range(legs):
    a = math.tau * (i + 0.5) / legs
    x, y = math.cos(a) * (R - 0.25), math.sin(a) * (R - 0.25)
    box("leg", (0.14, 0.14, STAND), (x, y, STAND / 2), steel)
    b = math.tau * (i + 1.5) / legs
    nx, ny = math.cos(b) * (R - 0.25), math.sin(b) * (R - 0.25)
    span = math.hypot(nx - x, ny - y)
    rz = math.atan2(ny - y, nx - x)
    box("ring", (span, 0.12, 0.2), ((x + nx) / 2, (y + ny) / 2, STAND - 0.1), steel, rz)
    box("brace", (span, 0.06, 0.08), ((x + nx) / 2, (y + ny) / 2, STAND * 0.45), steel, rz)
box("floor", (2 * R - 0.1, 0.16, 0.12), (0, 0, STAND - 0.06), steel)
box("floor", (0.16, 2 * R - 0.1, 0.12), (0, 0, STAND - 0.06), steel)
# The ladder, from the roof up the barrel to the cap, on -Y, with a hoop cage over its top half.
ly = -(R + 0.22)
for x in (-0.22, 0.22):
    box("rail", (0.05, 0.05, STAND + TALL + 0.2), (x, ly, (STAND + TALL + 0.2) / 2), steel)
rungs = int((STAND + TALL) / 0.32)
for i in range(rungs):
    box("rung", (0.44, 0.03, 0.03), (0, ly, 0.3 + i * 0.32), steel)
for z in (STAND + 0.6, STAND + 1.4, STAND + 2.2):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.38, minor_radius=0.02, major_segments=12, minor_segments=4,
                                     location=(0, ly - 0.12, z))
    bpy.context.object.data.materials.append(steel)
    parts.append(bpy.context.object)

for p in parts:
    p.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
o = bpy.context.object
o.name = "water_tank"
bpy.ops.object.shade_flat()
print("water_tank faces", len(o.data.polygons), [m.name for m in o.data.materials], [round(d, 2) for d in o.dimensions])
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/water_tank.glb"), export_format='GLB')
print("wrote water_tank.glb")
