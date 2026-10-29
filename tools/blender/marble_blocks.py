# Builds the marble run's blocks and its tray, and writes assets/models/marble_blocks.glb.
#
#     blender --background --python tools/blender/marble_blocks.py
#
# WHAT IT IS FOR
#
# A marble run (docs/spatial_loop.md part two, slice 49, idea #35): blocks put in the lattice's cells,
# a marble rolling through them a cell each sixteenth, each bell block ringing its note. Every block is
# a maple slab at the bottom of its 0.25 m cell, a little smaller than the cell so a run reads as
# blocks and not a wall, and what it does is its shape, never only its colour:
#
#   Ramp       a groove along the slab, its floor falling toward the out end, two chevrons on the
#              rails pointing that way: the marble rolls on into the next cell.
#   Drop       a funnel through the slab, a brass ring round its mouth: the marble falls into the cell
#              under it.
#   Splitter   a level groove through, chevrons both ways, and a brass vane on a pin at its middle
#              (SplitterVane, its own object so MarbleRun can tip it to the side the next marble
#              goes): every other marble goes the other way.
#   Bell       a groove like the ramp's, and a brass arch over its middle (BellArch) with a small bell
#              hanging from it (BellBell, its own object so MarbleRun can swing it when it rings).
#   Tray       the station's stand at the lattice's face toward the desk: a weighted foot, a post, and
#              a board tipped toward whoever stands at it, with five wells along it for the blocks to
#              take and the BALL key's marble.
#
# Every block's out end is Godot -Z (MarbleRun.FACINGS' AWAY): MarbleRun turns it about Y to face
# where it rolls. Its origin is its cell's middle. The tray's origin is on the floor at the middle of
# the lattice's face, its front (+Z) toward the desk.
#
# MarbleRun (core/music/marble_run.gd) repeats every number below that it places things by (the slab's
# top, the groove, the bell's pin, the tray's board and its wells), so the two agree.
#
# ORIENTATION (see _parts.py)
#
# Godot +Y is Blender +Z and Godot -Z is Blender +Y.

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    _flatten, bevel_all, box, clear_scene, cut, join, material, report, smooth,
)

# --- In metres, in Godot's terms (y up, z toward you), as MarbleRun has them. -----------------

CELL = 0.25
HALF = 0.11              # half the slab's side (MarbleRun.BLOCK)
BOTTOM = -0.115          # the slab's underside, a centimetre off the cell's floor
TOP = -0.03              # the slab's top (MarbleRun.SLAB_TOP)
GROOVE = 0.032           # half the groove's width
GROOVE_IN = -0.055       # the groove's floor at the in end (+Z)
GROOVE_OUT = -0.07       # and at the out end (-Z), a ramp's falling toward it
FUNNEL = (0.075, 0.035)  # the drop's funnel: its mouth's radius and its throat's
BELL_PIN = (0.0, 0.075, 0.0)   # where the bell hangs from its arch (MarbleRun.BELL_PIN)
VANE_PIN = (0.0, -0.06, 0.0)   # the splitter's vane's pin (MarbleRun.VANE_PIN)

TRAY_FOOT = (0.18, 0.1)  # half the foot: x, z (MarbleRun.TRAY_FOOT)
TRAY_Z = 0.12            # the post's and the foot's middle, in front of the face (MarbleRun.TRAY_Z)
BOARD_Y = 1.1            # the board's middle (MarbleRun.BOARD_Y)
BOARD = (0.36, 0.0125, 0.09)   # half its size: x, y, z (MarbleRun.BOARD)
TILT = 0.35              # tipped toward you, radians (MarbleRun.BOARD_TILT)
WELLS = [-0.26, -0.13, 0.0, 0.13, 0.26]   # the wells' middles along it (MarbleRun.WELLS)
WELL = 0.05              # half a well's side


def g(p):
    """A point in Godot's terms as Blender has it."""
    return Vector((p[0], -p[2], p[1]))


def gbox(name, lo, hi, ease=0.0015):
    """A box from Godot-space corners: x, y up, z toward you, its edges eased."""
    size = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    centre = ((lo[0] + hi[0]) * 0.5, -(lo[2] + hi[2]) * 0.5, (lo[1] + hi[1]) * 0.5)
    return bevel_all(box(name, size, centre), ease, 1) if ease > 0.0 else box(name, size, centre)


def rod(name, a, b, radius, vertices=20):
    """A cylinder from Godot point `a` to `b`."""
    a = g(a)
    b = g(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=d.length,
            location=(a + b) * 0.5, rotation=d.to_track_quat("Z", "Y").to_euler())
    obj = bpy.context.active_object
    obj.name = name
    return _flatten(obj)


MATS = []


def slot(obj, index):
    obj.data.materials.clear()
    for m in MATS:
        obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = index
    return obj


def prism(name, points, y0, y1, index):
    """A prism standing up from y0 to y1 over a polygon of Godot (x, z) points."""
    mesh = bpy.data.meshes.new(name)
    verts = [g((x, y0, z)) for x, z in points] + [g((x, y1, z)) for x, z in points]
    n = len(points)
    faces = [list(range(n))[::-1], list(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    # Faces wound either way, made consistent and outward.
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return slot(obj, index)


def chevron(name, x, z, toward, index):
    """A raised arrowhead on a rail's top at (x, z), pointing along `toward` (-1 for -Z, the out end)."""
    w = 0.022
    tip = z + toward * 0.022
    back = z - toward * 0.012
    pts = [(x, tip), (x + w * 0.5, back), (x, back + toward * 0.01), (x - w * 0.5, back)]
    if toward > 0:
        pts = pts[::-1]
    return prism(name, pts, TOP - 0.001, TOP + 0.005, index)


def channel(name, sloped):
    """A slab with a groove along Z: two rails and a floor between, falling toward -Z if `sloped`."""
    parts = []
    for side in (-1.0, 1.0):
        x0 = side * GROOVE
        x1 = side * HALF
        parts.append(slot(gbox("Rail", (min(x0, x1), BOTTOM, -HALF), (max(x0, x1), TOP, HALF), 0.004), 0))
    out = GROOVE_OUT if sloped else GROOVE_IN
    # The groove's floor: a wedge from the slab's underside up to the floor, higher at the in end.
    pts_y = [(-GROOVE, HALF, GROOVE_IN), (GROOVE, HALF, GROOVE_IN), (GROOVE, -HALF, out), (-GROOVE, -HALF, out)]
    mesh = bpy.data.meshes.new("Floor")
    verts = [g((x, y, z)) for x, z, y in [(p[0], p[1], p[2]) for p in pts_y]] \
        + [g((x, BOTTOM, z)) for x, z, _ in pts_y]
    faces = [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()
    floor = bpy.data.objects.new("Floor", mesh)
    bpy.context.collection.objects.link(floor)
    bpy.ops.object.select_all(action="DESELECT")
    floor.select_set(True)
    bpy.context.view_layer.objects.active = floor
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    parts.append(slot(floor, 1))
    return parts


def finish(name, parts):
    first = parts.pop(0)
    obj = join(first, parts) if parts else first
    obj.name = name
    smooth(obj, 30.0)
    report(obj)
    return obj


def ramp():
    parts = channel("Ramp", True)
    for side in (-1.0, 1.0):
        parts.append(chevron("Chevron", side * (GROOVE + HALF) * 0.5, -0.06, -1.0, 2))
        parts.append(chevron("Chevron", side * (GROOVE + HALF) * 0.5, 0.0, -1.0, 2))
    return finish("Ramp", parts)


def drop():
    slab = slot(gbox("Slab", (-HALF, BOTTOM, -HALF), (HALF, TOP, HALF), 0.004), 0)
    bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=FUNNEL[1], radius2=FUNNEL[0],
            depth=TOP - BOTTOM + 0.004, location=g((0, (TOP + BOTTOM) * 0.5, 0)))
    funnel = _flatten(bpy.context.active_object)
    cut(slab, funnel)
    slot(slab, 0)
    # The funnel's inside, darker, so its mouth reads from above.
    for p in slab.data.polygons:
        c = p.center
        if math.hypot(c.x, c.y) < FUNNEL[0] - 0.002 and c.z > BOTTOM + 0.002 and c.z < TOP - 0.001:
            p.material_index = 1
    bpy.ops.mesh.primitive_torus_add(major_radius=FUNNEL[0] + 0.004, minor_radius=0.004, major_segments=40,
            minor_segments=8, location=g((0, TOP + 0.001, 0)))
    rim = slot(_flatten(bpy.context.active_object), 2)
    return finish("Drop", [slab, rim])


def splitter():
    parts = channel("Splitter", False)
    for side in (-1.0, 1.0):
        x = side * (GROOVE + HALF) * 0.5
        parts.append(chevron("Chevron", x, -0.065, -1.0, 2))
        parts.append(chevron("Chevron", x, 0.065, 1.0, 2))
    # The vane's pin, standing up out of the groove's floor; the vane is its own object.
    parts.append(slot(rod("Pin", (0, GROOVE_IN, 0), (0, VANE_PIN[1] + 0.03, 0), 0.004, 12), 2))
    return finish("Splitter", parts)


def splitter_vane():
    # A thin brass plate across the groove on its pin, its long side along Z: tipped by MarbleRun
    # toward the side the next marble goes.
    plate = slot(gbox("Vane", (-0.003, -0.012, -0.055), (0.003, 0.016, 0.055), 0.001), 2)
    tip = slot(rod("Cap", (0, 0.016, 0), (0, 0.022, 0), 0.007, 16), 2)
    obj = finish("SplitterVane", [plate, tip])
    return obj


def bell():
    parts = channel("Bell", True)
    for side in (-1.0, 1.0):
        parts.append(chevron("Chevron", side * (GROOVE + HALF) * 0.5, -0.075, -1.0, 2))
    return finish("Bell", parts)


def bell_arch():
    # Two brass posts off the rails and a crossbar over the groove's middle, the bell's pin under it.
    parts = []
    for side in (-1.0, 1.0):
        x = side * (GROOVE + 0.018)
        parts.append(slot(rod("Post", (x, TOP, 0), (x, BELL_PIN[1] + 0.012, 0), 0.0045, 12), 2))
    parts.append(slot(rod("Bar", (-GROOVE - 0.024, BELL_PIN[1] + 0.012, 0), (GROOVE + 0.024, BELL_PIN[1] + 0.012, 0),
            0.005, 12), 2))
    return finish("BellArch", parts)


def bell_bell():
    # A small bell turned on a lathe, its mouth down, hanging from its loop at the origin (the pin).
    profile = [(0.0, -0.006), (0.004, -0.006), (0.006, -0.012), (0.011, -0.022), (0.016, -0.034),
            (0.021, -0.044), (0.023, -0.05), (0.019, -0.05), (0.016, -0.045), (0.012, -0.036),
            (0.007, -0.024), (0.0, -0.022)]
    mesh = bpy.data.meshes.new("BellBell")
    segments = 32
    verts = []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        for r, y in profile:
            verts.append(tuple(g((r * math.cos(a), y, r * math.sin(a)))))
    n = len(profile)
    faces = []
    for i in range(segments):
        j = (i + 1) % segments
        for k in range(n - 1):
            faces.append([i * n + k, j * n + k, j * n + k + 1, i * n + k + 1])
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("BellBell", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0002)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    slot(obj, 2)
    loop = slot(rod("Loop", (0, 0.0, 0), (0, -0.007, 0), 0.003, 10), 2)
    return finish("BellBell", [obj, loop])


def tray():
    parts = []
    fx, fz = TRAY_FOOT
    parts.append(slot(gbox("Foot", (-fx, 0.0, TRAY_Z - fz), (fx, 0.03, TRAY_Z + fz), 0.008), 3))
    parts.append(slot(rod("Post", (0, 0.03, TRAY_Z), (0, BOARD_Y - 0.03, TRAY_Z), 0.018, 24), 3))
    # The board, made flat and then tipped about its long axis toward the front.
    bx, by, bz = BOARD
    board = slot(gbox("Board", (-bx, -by, -bz), (bx, by, bz), 0.004), 0)
    for x in WELLS:
        cutter = gbox("Well", (x - WELL, by - 0.008, -WELL), (x + WELL, by + 0.01, WELL), 0.0)
        cut(board, cutter)
    slot(board, 0)
    for p in board.data.polygons:
        c = p.center
        # Godot y is Blender z: the wells' floors and walls are under the board's top.
        if c.z < by - 0.0005 and c.z > by - 0.0085 + 0.0001 and any(abs(c.x - x) < WELL + 0.0005 for x in WELLS) \
                and abs(c.y) < WELL + 0.0005:
            p.material_index = 4
    board.rotation_euler = (TILT, 0.0, 0.0)
    board.location = g((0, BOARD_Y, TRAY_Z))
    _flatten(board)
    parts.append(board)
    # A bracket under the board where it meets the post.
    parts.append(slot(gbox("Bracket", (-0.06, BOARD_Y - 0.06, TRAY_Z - 0.03), (0.06, BOARD_Y - 0.02, TRAY_Z + 0.03), 0.004), 3))
    return finish("Tray", parts)


def blocks():
    clear_scene()
    MATS[:] = [material("maple", (0.78, 0.62, 0.42, 1.0), 0.5),
            material("groove", (0.36, 0.22, 0.12, 1.0), 0.55),
            material("brass", (0.78, 0.6, 0.3, 1.0), 0.3),
            material("iron", (0.09, 0.09, 0.1, 1.0), 0.45),
            material("felt", (0.12, 0.2, 0.16, 1.0), 0.9)]
    made = [ramp(), drop(), splitter(), splitter_vane(), bell(), bell_arch(), bell_bell(), tray()]
    # Each its own object, apart in the file so none is merged, at its own origin in Godot.
    out = os.path.join(os.getcwd(), "assets", "models", "marble_blocks.glb")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in made:
        obj.select_set(True)
    kwargs = {"filepath": out, "export_format": "GLB", "use_selection": True, "export_apply": True,
            "export_yup": True}
    allowed = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    bpy.ops.export_scene.gltf(**{k: v for k, v in kwargs.items() if k in allowed})
    print("wrote %s (%d bytes)" % (out, os.path.getsize(out)))


os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
blocks()
