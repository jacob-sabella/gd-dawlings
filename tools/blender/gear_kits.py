# Builds each venue's gear kit and writes assets/models/gear_kit_<venue>.glb.
#
#     blender --background --python tools/blender/gear_kits.py
#
# The furniture the gear stands in -- the console's body, the rack's plinth, the patch cabinet --
# is a set of boxes whose sizes follow the session (a console grows a strip per track, the patch
# cabinet a row per send). So a venue's SHAPE cannot be a model of a whole desk: it is a kit of
# fittings that GearShape (hardware/gear_shape.gd) puts onto any box at whatever size it is:
#
#   corner      one at each of the box's eight corners, modelled for the +X +Y +Z one and
#               mirrored onto the rest. The box is on the -X -Y -Z side of the origin.
#   corner_top  the same, at the four top corners only.
#   edge        each upright edge, modelled one metre tall centred on the origin and stretched
#               to the box's height; the +X +Z edge, mirrored.
#   handle      the middle of each side (X) face, modelled on the +X face, facing out.
#   latch       near the top of the front and back (Z) faces, modelled on the +Z face.
#   face        the middle of the front and back faces, modelled 0.2 m across on the +Z face
#               and scaled to the face.
#   finial      standing on each top corner, the right way up, never mirrored.
#
# Each part is an object of that name. Its materials are named for the shared finish GearShape
# gives them -- "furniture", "brushed", "trim", "end_cheek", "chassis" -- so a kit wears the
# venue's GearStyle like everything else, and "glass" and "rope" for the two it does not have.
#
# Written in Godot's axes (y up, z out of the box's front) and turned into Blender's as it is
# built: Godot (x, y, z) is Blender (x, -z, y). See _parts.py's ORIENTATION note.
#
# Nothing a fitting adds may lie in a box face's plane, or the two fight over every pixel: every
# outer surface stands a few millimetres proud, and every inner one is buried in the box.

import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _parts  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def g(x, y, z):
    """A Godot-space point in Blender's axes."""
    return Vector((x, -z, y))


def mat(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    return m


def give(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(mat(material))
    return obj


def block(name, size, centre, material):
    """A box, Godot-space size and centre."""
    sx, sy, sz = size
    return give(_parts.box(name, (sx, sz, sy), g(*centre)), material)


def rod(name, radius, length, centre, axis, material, vertices=16):
    """A cylinder along a Godot axis."""
    blender_axis = {"x": "X", "y": "Z", "z": "Y"}[axis]
    return give(_parts.cylinder(name, radius, length, g(*centre), blender_axis, vertices), material)


def ball(name, radius, centre, material, segments=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=segments // 2, radius=radius,
            location=g(*centre))
    obj = bpy.context.active_object
    obj.name = name
    return give(_parts._flatten(obj), material)


def ring(name, major, minor, centre, axis, material):
    """A torus whose hole runs along a Godot axis."""
    rot = {"x": (0.0, math.pi / 2, 0.0), "y": (0.0, 0.0, 0.0), "z": (math.pi / 2, 0.0, 0.0)}[axis]
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=24,
            minor_segments=8, location=g(*centre), rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    return give(_parts._flatten(obj), material)


def pyramid(name, radius, height, base, material):
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=radius, radius2=0.0, depth=height,
            location=g(base[0], base[1] + height * 0.5, base[2]), rotation=(0.0, 0.0, math.pi / 4))
    obj = bpy.context.active_object
    obj.name = name
    return give(_parts._flatten(obj), material)


def combine(name, parts):
    """One object of `parts`, keeping each one's material."""
    first = parts[0]
    if len(parts) > 1:
        first = _parts.join(first, parts[1:])
    first.name = name
    first.data.name = name
    return first


def roughen(obj, amount, seed):
    """Nudge every vertex sideways a little: hewn, not turned."""
    rng = random.Random(seed)
    for v in obj.data.vertices:
        v.co.x += rng.uniform(-amount, amount)
        v.co.y += rng.uniform(-amount, amount)
    return obj


def export_kit(venue, objects):
    out = os.path.join(ROOT, "assets", "models", "gear_kit_%s.glb" % venue)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
        _parts.report(o)
    bpy.context.view_layer.objects.active = objects[0]
    kwargs = {"filepath": out, "export_format": "GLB", "use_selection": True, "export_apply": True,
            "export_yup": True}
    allowed = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    bpy.ops.export_scene.gltf(**{k: v for k, v in kwargs.items() if k in allowed})
    print("wrote %s (%d bytes)" % (out, os.path.getsize(out)))


# --- the kits -----------------------------------------------------------------------------------

# How far a fitting's outer face stands off the box face it covers.
PROUD = 0.010


def road_case_corner(name, material, with_ball):
    """Three stamped plates folded round a corner, the way a flight case's corners are."""
    c = 0.085
    t = 0.005
    parts = [
        block(name + "_x", (t, c, c), (PROUD - t * 0.5, -c * 0.5 + PROUD, -c * 0.5 + PROUD), material),
        block(name + "_y", (c, t, c), (-c * 0.5 + PROUD, PROUD - t * 0.5, -c * 0.5 + PROUD), material),
        block(name + "_z", (c, c, t), (-c * 0.5 + PROUD, -c * 0.5 + PROUD, PROUD - t * 0.5), material),
    ]
    if with_ball:
        parts.append(ball(name + "_ball", 0.026, (0.008, 0.008, 0.008), material))
    else:
        # Rivets instead of the pressed dome: an older, flatter corner.
        for at in [(PROUD, -0.05, -0.018), (PROUD, -0.018, -0.05), (-0.05, -0.018, PROUD),
                (-0.018, -0.05, PROUD), (-0.05, PROUD, -0.018), (-0.018, PROUD, -0.05)]:
            parts.append(ball(name + "_rivet", 0.006, at, material, 8))
    return combine(name, parts)


def club():
    """Road cases: ball corners, recessed spring handles, butterfly latches."""
    corner = road_case_corner("corner", "brushed", True)
    dish = block("dish", (0.006, 0.08, 0.17), (PROUD - 0.003, 0.0, 0.0), "brushed")
    bar = rod("bar", 0.0075, 0.13, (0.026, 0.0, 0.0), "z", "brushed")
    posts = [rod("post", 0.005, 0.022, (0.016, 0.0, s * 0.06), "x", "brushed") for s in (-1, 1)]
    handle = combine("handle", [dish, bar] + posts)
    plate = block("plate", (0.07, 0.05, 0.005), (0.0, -0.01, PROUD - 0.0025), "brushed")
    wing = block("wing", (0.05, 0.014, 0.008), (0.0, -0.012, PROUD + 0.004), "brushed")
    hasp = rod("hasp", 0.006, 0.02, (0.0, 0.016, PROUD + 0.002), "x", "brushed")
    latch = combine("latch", [plate, wing, hasp])
    export_kit("club", [corner, handle, latch])


def rooftop():
    """Weathered flight cases: flat riveted corners and rope loop handles through iron eyes."""
    corner = road_case_corner("corner", "brushed", False)
    loop = ring("loop", 0.05, 0.009, (0.018, -0.03, 0.0), "z", "rope")
    eyes = [block("eye", (0.006, 0.03, 0.026), (PROUD - 0.003, 0.0, s * 0.05), "brushed") for s in (-1, 1)]
    handle = combine("handle", [loop] + eyes)
    export_kit("rooftop", [corner, handle])


def cabin():
    """Hewn log uprights at every edge and a forged iron strap round the top corners."""
    log = rod("edge", 0.034, 1.0, (0.0, 0.0, 0.0), "y", "end_cheek", 10)
    roughen(log, 0.005, 7)
    log = combine("edge", [log])
    t = 0.004
    strap_x = block("sx", (t, 0.03, 0.13), (PROUD + 0.03 - t * 0.5, -0.04, -0.065), "trim")
    strap_z = block("sz", (0.13, 0.03, t), (-0.065, -0.04, PROUD + 0.03 - t * 0.5), "trim")
    nails = [ball("nail", 0.006, (PROUD + 0.031, -0.04, -z), "trim", 8) for z in (0.06, 0.11)] + \
            [ball("nail", 0.006, (-x, -0.04, PROUD + 0.031), "trim", 8) for x in (0.06, 0.11)]
    strap = combine("corner_top", [strap_x, strap_z] + nails)
    export_kit("cabin", [log, strap])


def dome():
    """Brass corner plates with rivets and a porthole set into each face."""
    corner = road_case_corner("corner_top", "brushed", False)
    frame = ring("frame", 0.07, 0.012, (0.0, 0.0, PROUD + 0.004), "z", "brushed")
    glass = rod("glass", 0.066, 0.004, (0.0, 0.0, PROUD - 0.002), "z", "glass", 32)
    bolts = [ball("bolt", 0.005, (math.cos(a) * 0.07, math.sin(a) * 0.07, PROUD + 0.016), "brushed", 8)
            for a in [i * math.pi / 4 for i in range(8)]]
    face = combine("face", [frame, glass] + bolts)
    export_kit("dome", [corner, face])


def grid():
    """A lit pyramid on every top corner and a neon chevron on each face."""
    finial = pyramid("finial", 0.035, 0.07, (0.0, 0.006, 0.0), "trim")
    finial = combine("finial", [finial])
    arm_a = block("a", (0.14, 0.014, 0.006), (-0.04, 0.035, PROUD), "end_cheek")
    arm_b = block("b", (0.14, 0.014, 0.006), (-0.04, -0.035, PROUD), "end_cheek")
    arm_a.rotation_euler = (0.0, 0.0, 0.0)
    for arm, angle in ((arm_a, 0.5), (arm_b, -0.5)):
        pivot = g(0.03, 0.0, PROUD)
        arm.data.transform(Matrix.Translation(pivot) @ Matrix.Rotation(angle, 4, "Y") @ Matrix.Translation(-pivot))
    face = combine("face", [arm_a, arm_b])
    export_kit("grid", [finial, face])


def loft():
    """Black iron pipe at every upright edge, on a bolted floor flange at each end."""
    pipe = rod("edge", 0.028, 1.0, (0.0, 0.0, 0.0), "y", "brushed", 16)
    pipe = combine("edge", [pipe])
    flange = rod("flange", 0.052, 0.012, (0.0, -0.005 + 0.002, 0.0), "y", "brushed", 20)
    bolts = [rod("bolt", 0.004, 0.008, (math.cos(a) * 0.04, 0.003, math.sin(a) * 0.04), "y", "brushed", 6)
            for a in [math.pi / 4 + i * math.pi / 2 for i in range(4)]]
    corner = combine("corner", [flange] + bolts)
    export_kit("loft", [pipe, corner])


def station():
    """Rounded impact bumpers on every corner and a vent grille in each face."""
    bump = _parts.box("corner", (0.06, 0.06, 0.06), g(0.0, 0.0, 0.0))
    _parts.bevel_all(bump, 0.018, 3)
    give(bump, "chassis")
    bump = combine("corner", [bump])
    frame = block("frame", (0.2, 0.09, 0.006), (0.0, 0.0, PROUD - 0.003), "chassis")
    slats = [block("slat", (0.17, 0.008, 0.006), (0.0, y, PROUD + 0.003), "trim")
            for y in (-0.03, -0.015, 0.0, 0.015, 0.03)]
    face = combine("face", [frame] + slats)
    export_kit("station", [bump, face])


def hex_crystal(name, radius, length, base, tilt_x, tilt_z, material):
    """A quartz point: a six-sided prism with a pyramid tip, standing from `base` up Godot y, leant
    by `tilt_x` and `tilt_z` radians."""
    prism = rod(name + "_prism", radius, length, (0.0, length * 0.5, 0.0), "y", material, 6)
    tip = pyramid(name + "_tip", radius * 1.05, radius * 2.2, (0.0, length, 0.0), material)
    piece = combine(name, [prism, tip])
    piece.data.transform(Matrix.Rotation(tilt_z, 4, "X") @ Matrix.Rotation(-tilt_x, 4, "Y"))
    piece.data.transform(Matrix.Translation(g(*base)))
    return piece


def cave():
    """A cluster of quartz points on every top corner, and a geode's cut face in each front."""
    points = [hex_crystal("c%d" % i, r, h, (x, -0.02, z), tx, tz, "glass")
            for i, (r, h, x, z, tx, tz) in enumerate([(0.012, 0.07, 0.0, 0.0, 0.0, 0.0),
                    (0.009, 0.05, 0.012, -0.006, 0.45, 0.1), (0.008, 0.045, -0.008, 0.012, -0.2, -0.45),
                    (0.006, 0.03, 0.014, 0.012, 0.5, -0.5)])]
    finial = combine("finial", points)
    rim = ring("rim", 0.075, 0.012, (0.0, 0.0, PROUD + 0.002), "z", "brushed")
    rim.scale = (1.0, 0.72, 1.0)
    bpy.context.view_layer.objects.active = rim
    rim.select_set(True)
    bpy.ops.object.transform_apply(scale=True)
    inside = rod("inside", 0.066, 0.006, (0.0, 0.0, PROUD - 0.002), "z", "glass", 24)
    inside.scale = (1.0, 0.72, 1.0)
    bpy.context.view_layer.objects.active = inside
    bpy.ops.object.transform_apply(scale=True)
    face = combine("face", [rim, inside])
    export_kit("cave", [finial, face])


def greenhouse():
    """A fluted cast-iron column at every upright edge, and an acorn finial on each top corner."""
    shaft = rod("shaft", 0.022, 1.0, (0.0, 0.0, 0.0), "y", "trim", 16)
    flutes = [rod("flute", 0.005, 1.0, (math.cos(a) * 0.022, 0.0, math.sin(a) * 0.022), "y", "trim", 6)
            for a in [i * math.tau / 8 for i in range(8)]]
    edge = combine("edge", [shaft] + flutes)
    neck = rod("neck", 0.008, 0.03, (0.0, 0.012, 0.0), "y", "trim", 12)
    collar = rod("collar", 0.016, 0.006, (0.0, 0.03, 0.0), "y", "trim", 16)
    acorn = ball("acorn", 0.017, (0.0, 0.05, 0.0), "trim", 16)
    tip = pyramid("tip", 0.008, 0.02, (0.0, 0.064, 0.0), "trim")
    finial = combine("finial", [neck, collar, acorn, tip])
    export_kit("greenhouse", [edge, finial])


def stage():
    """Triangular aluminium truss up every upright edge, a black truss block on each top corner."""
    chords = [(PROUD + 0.014, -0.035), (-0.035, PROUD + 0.014), (PROUD + 0.03, PROUD + 0.03)]
    parts = [rod("chord", 0.008, 1.0, (x, 0.0, z), "y", "brushed", 10) for x, z in chords]
    steps = 10
    for i in range(steps):
        a = chords[i % 3]
        b = chords[(i + 1) % 3]
        y0 = -0.5 + i / steps
        y1 = y0 + 1.0 / steps
        p = Vector((a[0], y0, a[1]))
        q = Vector((b[0], y1, b[1]))
        mid = (p + q) * 0.5
        lace = rod("lace", 0.004, (q - p).length, (mid.x, mid.y, mid.z), "y", "brushed", 6)
        d = (q - p).normalized()
        # Turn the lacing from straight up onto its diagonal, about its own middle.
        up = Vector((0.0, 1.0, 0.0))
        axis = up.cross(d)
        if axis.length > 1e-6:
            angle = math.acos(max(-1.0, min(1.0, up.dot(d))))
            gm = g(mid.x, mid.y, mid.z)
            ga = g(axis.x, axis.y, axis.z).normalized()
            lace.data.transform(Matrix.Translation(gm) @ Matrix.Rotation(angle, 4, ga) @ Matrix.Translation(-gm))
        parts.append(lace)
    edge = combine("edge", parts)
    cube = block("cube", (0.07, 0.07, 0.07), (PROUD - 0.022, PROUD - 0.022, PROUD - 0.022), "chassis")
    bolts = [ball("bolt", 0.006, at, "brushed", 8) for at in
            [(PROUD + 0.014, -0.012, -0.012), (-0.012, PROUD + 0.014, -0.012), (-0.012, -0.012, PROUD + 0.014)]]
    corner = combine("corner_top", [cube] + bolts)
    export_kit("stage", [edge, corner])


def garden():
    """Bronze corner fittings with round studs on the top corners, as on a temple's beams, and a
    crest in a ring on each face."""
    t = 0.004
    c = 0.11
    plate_x = block("px", (t, 0.05, c), (PROUD - t * 0.5, -0.025 + PROUD, -c * 0.5 + PROUD), "trim")
    plate_z = block("pz", (c, 0.05, t), (-c * 0.5 + PROUD, -0.025 + PROUD, PROUD - t * 0.5), "trim")
    plate_y = block("py", (c, t, c), (-c * 0.5 + PROUD, PROUD - t * 0.5, -c * 0.5 + PROUD), "trim")
    studs = [ball("stud", 0.008, (PROUD, -0.025, -z), "trim", 10) for z in (0.035, 0.08)] + \
            [ball("stud", 0.008, (-x, -0.025, PROUD), "trim", 10) for x in (0.035, 0.08)]
    corner = combine("corner_top", [plate_x, plate_z, plate_y] + studs)
    outer = ring("outer", 0.07, 0.008, (0.0, 0.0, PROUD + 0.002), "z", "trim")
    boss = ball("boss", 0.016, (0.0, 0.0, PROUD - 0.004), "trim", 14)
    petals = [ball("petal", 0.014, (math.cos(a) * 0.038, math.sin(a) * 0.038, PROUD - 0.006), "trim", 12)
            for a in [math.pi / 2 + i * math.tau / 3 for i in range(3)]]
    face = combine("face", [outer, boss] + petals)
    export_kit("garden", [corner, face])


def desert():
    """Hammered brass corner plates with a domed stud in each, and a leather strap and buckle down
    the front and back like a camel trunk's."""
    c = 0.09
    t = 0.004
    plates = [
        block("dx", (t, c, c), (PROUD - t * 0.5, -c * 0.5 + PROUD, -c * 0.5 + PROUD), "trim"),
        block("dy", (c, t, c), (-c * 0.5 + PROUD, PROUD - t * 0.5, -c * 0.5 + PROUD), "trim"),
        block("dz", (c, c, t), (-c * 0.5 + PROUD, -c * 0.5 + PROUD, PROUD - t * 0.5), "trim"),
    ]
    domes = [ball("dome", 0.011, at, "trim", 12) for at in
            [(PROUD, -0.04, -0.04), (-0.04, PROUD, -0.04), (-0.04, -0.04, PROUD)]]
    corner = combine("corner", plates + domes)
    strap = block("strap", (0.04, 0.12, 0.005), (0.0, -0.03, PROUD - 0.0025), "end_cheek")
    frame = [block("bf", (0.05, 0.006, 0.006), (0.0, y, PROUD + 0.003), "trim") for y in (-0.02, 0.012)] + \
            [block("bs", (0.006, 0.032, 0.006), (x, -0.004, PROUD + 0.003), "trim") for x in (-0.022, 0.022)]
    tongue = block("tongue", (0.004, 0.03, 0.004), (0.0, -0.004, PROUD + 0.006), "trim")
    latch = combine("latch", [strap] + frame + [tongue])
    export_kit("desert", [corner, latch])


for build in (club, rooftop, cabin, dome, grid, loft, station, cave, greenhouse, stage, garden, desert):
    _parts.clear_scene()
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    build()
