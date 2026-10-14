# Builds the chalk zone's classroom furniture and writes five models:
#
#     blender --background --python tools/blender/chalk_classroom.py
#
#   assets/models/chalk_desk.glb          a pupil's desk: a wooden lid on a steel tube frame with
#                                         a book box under it, open to the pupil's side
#   assets/models/chalk_chair.glb         the chair that goes with it: bent-ply seat and back on
#                                         steel tubes
#   assets/models/chalk_teacher_desk.glb  the teacher's pedestal desk: two banks of drawers with
#                                         brass knobs, a leather-topped lid, a panelled front
#   assets/models/chalk_globe.glb         a desk globe on a turned wooden foot, tilted in a brass
#                                         half meridian
#   assets/models/chalk_radiator.glb      a cast-iron column radiator, as under every schoolroom
#                                         window, on its feet with a valve and its pipe
#
# Materials by name, swapped by ChalkVenue: "wood", "steel", "top", "brass", "globe", "iron".
# Every origin is on the floor under the middle. Blender +Y is Godot -Z (see _parts.py): the
# desk and the chair face Blender +Y, the way the class faces the front board; the teacher's
# drawers are on Blender +Y, the board's side, and its panelled front on -Y, toward the class.

import math
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
parts = []
mats = {}


def fresh():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts.clear()
    mats.clear()


def mat(name):
    if name not in mats:
        mats[name] = bpy.data.materials.new(name)
    return mats[name]


def box(size, loc, m, rx=0.0, rz=0.0, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=(rx, 0, rz))
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        mod = o.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mat(m))
    parts.append(o)
    return o


def tube(a, b, r, m, verts=10):
    """A round bar from point a to point b."""
    ax, ay, az = a
    bx, by, bz = b
    dx, dy, dz = bx - ax, by - ay, bz - az
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=length, vertices=verts,
                                        location=((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2))
    o = bpy.context.object
    # Point the cylinder's Z along a->b.
    o.rotation_mode = "QUATERNION"
    from mathutils import Vector
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(Vector((dx, dy, dz)).normalized())
    o.data.materials.append(mat(m))
    parts.append(o)
    return o


def cyl(r, depth, loc, m, verts=24, r2=None, rot=(0, 0, 0)):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, vertices=verts, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, location=loc, vertices=verts,
                                        rotation=rot)
    o = bpy.context.object
    o.data.materials.append(mat(m))
    parts.append(o)
    return o


def write(name, smooth=False):
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    # Everything into the vertices, the origin left on the floor under the middle: a MultiMesh
    # takes the mesh alone and would drop an object offset.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if smooth:
        bpy.ops.object.shade_smooth()
        if hasattr(bpy.ops.object, "shade_auto_smooth"):
            bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    else:
        bpy.ops.object.shade_flat()
    print(name, "faces", len(o.data.polygons), [m.name for m in o.data.materials],
          [round(d, 3) for d in o.dimensions])
    out = os.path.join(ROOT, "assets/models/%s.glb" % name)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True)
    print("wrote", out)


# --- The pupil's desk ---------------------------------------------------------------------------
# 62 x 45 cm lid, 74 cm up: the old two-tone kind, a varnished lid on a grey steel frame.
fresh()
TOP = 0.74
W, D = 0.62, 0.45
box((W, D, 0.024), (0, 0, TOP - 0.012), "wood", bevel=0.004)
# The pen groove along the far edge, a strip of wood standing proud, and the ink-well hole as a
# little dark disc set into it.
box((W - 0.04, 0.03, 0.006), (0, D / 2 - 0.035, TOP + 0.003), "wood")
cyl(0.018, 0.004, (W / 2 - 0.07, D / 2 - 0.035, TOP + 0.0065), "steel", verts=16)
# The book box: a steel tray under the lid, open toward the pupil (-Y).
box((W - 0.07, D - 0.08, 0.008), (0, 0.02, TOP - 0.15), "steel")
box((W - 0.07, 0.008, 0.13), (0, D / 2 - 0.024, TOP - 0.088), "steel")
for sx in (-1, 1):
    box((0.008, D - 0.08, 0.13), (sx * (W / 2 - 0.039), 0.02, TOP - 0.088), "steel")
# The frame: four tube legs, a stretcher along each side low down, and a foot rail under the
# pupil's side.
for sx in (-1, 1):
    x = sx * (W / 2 - 0.035)
    for sy in (-1, 1):
        y = sy * (D / 2 - 0.035)
        tube((x, y, 0.012), (x, y, TOP - 0.024), 0.013, "steel")
        cyl(0.016, 0.012, (x, y, 0.006), "steel", verts=12)
    tube((x, -(D / 2 - 0.035), 0.16), (x, D / 2 - 0.035, 0.16), 0.01, "steel")
tube((-(W / 2 - 0.035), -(D / 2 - 0.035), 0.09), (W / 2 - 0.035, -(D / 2 - 0.035), 0.09), 0.01, "steel")
write("chalk_desk")

# --- The pupil's chair --------------------------------------------------------------------------
# Seat 44 cm up; bent ply seat and back on a steel frame; it faces +Y, its back on -Y.
fresh()
SEAT = 0.44
box((0.38, 0.36, 0.018), (0, 0.0, SEAT - 0.009), "wood", bevel=0.005)
# The back: a curved ply rail, made of three slats turned round the sitter.
for i, a in enumerate((-0.32, 0.0, 0.32)):
    x = math.sin(a) * 0.15
    y = -0.19 - (1 - math.cos(a)) * 0.15 + 0.15 * (1 - math.cos(a))
    box((0.135, 0.016, 0.15), (x, -0.19 + (1.0 - math.cos(a)) * 0.06, 0.74), "wood", rz=-a * 0.9, bevel=0.003)
for sx in (-1, 1):
    x = sx * 0.165
    # Front leg, straight.
    tube((x, 0.15, 0.0), (x, 0.15, SEAT - 0.018), 0.011, "steel")
    # Back leg, up through the seat's back corner and on up to carry the back.
    tube((x, -0.16, 0.0), (x, -0.17, SEAT - 0.018), 0.011, "steel")
    tube((x, -0.17, SEAT - 0.018), (x * 0.85, -0.185, 0.80), 0.011, "steel")
    # The seat's side rail.
    tube((x, 0.15, SEAT - 0.03), (x, -0.17, SEAT - 0.03), 0.009, "steel")
    cyl(0.013, 0.01, (x, 0.15, 0.005), "steel", verts=10)
    cyl(0.013, 0.01, (x, -0.16, 0.005), "steel", verts=10)
write("chalk_chair")

# --- The teacher's desk -------------------------------------------------------------------------
fresh()
TW, TD, TT = 1.4, 0.72, 0.76
box((TW, TD, 0.035), (0, 0, TT - 0.0175), "wood", bevel=0.006)
# A green leather inset in the lid, a hair proud.
box((TW - 0.16, TD - 0.16, 0.002), (0, 0, TT + 0.001), "top")
PED = 0.42
for sx in (-1, 1):
    cx = sx * (TW / 2 - PED / 2 - 0.03)
    # The pedestal's carcass, on a plinth.
    box((PED, TD - 0.06, TT - 0.035 - 0.08), (cx, 0, 0.08 + (TT - 0.035 - 0.08) / 2), "wood")
    box((PED - 0.02, TD - 0.08, 0.08), (cx, 0, 0.04), "wood")
    # Three drawers on the teacher's side (+Y): fronts standing proud, a brass knob in each.
    for k in range(3):
        h = (TT - 0.035 - 0.1) / 3
        z = 0.1 + h * (k + 0.5)
        box((PED - 0.05, 0.016, h - 0.025), (cx, (TD - 0.06) / 2 + 0.008, z), "wood", bevel=0.003)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.016, segments=12, ring_count=6,
                                             location=(cx, (TD - 0.06) / 2 + 0.03, z))
        bpy.context.object.data.materials.append(mat("brass"))
        parts.append(bpy.context.object)
    # Panels on the class's side (-Y): two raised fields per pedestal.
    for k in range(2):
        z = 0.12 + (TT - 0.2) * (k + 0.5) / 2
        box((PED - 0.08, 0.012, (TT - 0.2) / 2 - 0.06), (cx, -(TD - 0.06) / 2 - 0.006, z), "wood", bevel=0.004)
# The modesty panel between the pedestals, on the class's side, and a drawer over the knees.
box((TW - 2 * PED - 0.06, 0.02, 0.42), (0, -(TD - 0.06) / 2 + 0.03, TT - 0.035 - 0.21), "wood")
box((TW - 2 * PED - 0.08, 0.016, 0.1), (0, (TD - 0.06) / 2 + 0.008, TT - 0.035 - 0.06), "wood", bevel=0.003)
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.014, segments=12, ring_count=6,
                                     location=(0, (TD - 0.06) / 2 + 0.03, TT - 0.035 - 0.06))
bpy.context.object.data.materials.append(mat("brass"))
parts.append(bpy.context.object)
write("chalk_teacher_desk")

# --- The globe ----------------------------------------------------------------------------------
# 30 cm across on a turned foot, its axis tilted 23.4 degrees in a brass half meridian.
fresh()
R = 0.15
C = 0.37
TILT = math.radians(23.4)
cyl(0.095, 0.025, (0, 0, 0.0125), "wood", verts=32)
cyl(0.08, 0.04, (0, 0, 0.045), "wood", verts=32, r2=0.03)
cyl(0.022, 0.12, (0, 0, 0.125), "wood", verts=16, r2=0.016)
cyl(0.03, 0.02, (0, 0, 0.19), "wood", verts=16)
# The meridian: a brass ring round the globe from pole to pole, tilted with it, on a stem from
# the foot to the ring's lowest point.
bpy.ops.mesh.primitive_torus_add(major_radius=R + 0.012, minor_radius=0.005, major_segments=48,
                                 minor_segments=6, location=(0, 0, C), rotation=(math.pi / 2, TILT, 0))
bpy.context.object.data.materials.append(mat("brass"))
parts.append(bpy.context.object)
low = (-(R + 0.012) * math.sin(TILT), 0, C - (R + 0.012) * math.cos(TILT))
tube((0, 0, 0.195), low, 0.007, "brass")
# The globe itself, its UVs running east-west and pole to pole, tilted with the meridian.
bpy.ops.mesh.primitive_uv_sphere_add(radius=R, segments=48, ring_count=24, location=(0, 0, C),
                                     rotation=(0, TILT, 0))
bpy.context.object.data.materials.append(mat("globe"))
parts.append(bpy.context.object)
# The axle's two brass caps at the poles.
for s in (-1, 1):
    cyl(0.008, 0.02, (s * math.sin(TILT) * (R + 0.01), 0, C + s * math.cos(TILT) * (R + 0.01)), "brass",
        verts=10, rot=(0, TILT, 0))
write("chalk_globe", smooth=True)

# --- The radiator -------------------------------------------------------------------------------
# Fourteen cast-iron columns, 1.0 m along, 0.68 tall, 0.16 deep, on two feet, with a valve.
fresh()
N = 14
L = 1.0
for i in range(N):
    x = -L / 2 + L * (i + 0.5) / N
    # Each section: two round columns joined top and bottom.
    for y in (-0.045, 0.045):
        cyl(0.022, 0.56, (x, y, 0.1 + 0.32), "iron", verts=10)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.022, segments=10, ring_count=5, location=(x, y, 0.7))
        bpy.context.object.data.materials.append(mat("iron"))
        parts.append(bpy.context.object)
    box((0.05, 0.13, 0.05), (x, 0, 0.13), "iron", bevel=0.008)
    box((0.05, 0.13, 0.05), (x, 0, 0.665), "iron", bevel=0.008)
for sx in (-1, 1):
    box((0.06, 0.16, 0.1), (sx * (L / 2 - 0.08), 0, 0.05), "iron", bevel=0.01)
# The valve at one end and the pipe down into the floor.
tube((L / 2, 0, 0.13), (L / 2 + 0.09, 0, 0.13), 0.016, "iron")
tube((L / 2 + 0.09, 0, 0.13), (L / 2 + 0.09, 0, 0.0), 0.016, "iron")
cyl(0.03, 0.02, (L / 2 + 0.05, 0, 0.17), "brass", verts=12)
write("chalk_radiator")
