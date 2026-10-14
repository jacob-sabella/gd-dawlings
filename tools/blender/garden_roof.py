# Builds the temple garden's roofs and writes assets/models/garden_roof.glb.
#
#     blender --background --python tools/blender/garden_roof.py
#
# A Japanese hip-and-gable roof (irimoya): four tiled slopes, each a concave curve (steep at the
# ridge, flattening toward the eave), the eave line sweeping up into the four corners (sori), and
# above the hips a vertical gable at each end under a bargeboard. A main ridge with an ogre tile
# (onigawara) at each end, ridges down the gables and along the hips, the round tile ends along
# the eaves, a fascia, a boarded soffit and parallel rafters under it with a heavier corner
# rafter at each hip. Two objects:
#
#   Roof        the pavilion's: 18.7 x 15.0 m over its eave tips, 4.3 m from eave to ridge.
#   RoofSquare  a pure hip roof on a square plan (a pagoda's tiers, a lantern house), 2 x 2 m.
#
# The origin is the middle of the plan at the height of the eave tips midway along a side; the
# venue scales the pavilion's along X as the room widens. Materials, swapped by the venue by
# name: "tiles" (UV: U along the eave, V up the slope, both in metres, for the tile shader),
# "ridge", "fascia", "soffit", "rafters", "gable".
#
# Blender +Y is Godot -Z; the roof is symmetric front to back, so it does not matter which.

import math
import os

import bmesh
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
MAT_NAMES = ["tiles", "ridge", "fascia", "soffit", "rafters", "gable"]
mats = {n: bpy.data.materials.new(n) for n in MAT_NAMES}
mats["tiles"].diffuse_color = (0.22, 0.24, 0.27, 1)
mats["ridge"].diffuse_color = (0.18, 0.19, 0.21, 1)
mats["fascia"].diffuse_color = (0.42, 0.28, 0.18, 1)
mats["soffit"].diffuse_color = (0.5, 0.36, 0.24, 1)
mats["rafters"].diffuse_color = (0.46, 0.32, 0.2, 1)
mats["gable"].diffuse_color = (0.3, 0.2, 0.14, 1)
TILES, RIDGE, FASCIA, SOFFIT, RAFTERS, GABLE = range(6)

# The pitch of the round tiles, along the eave: the tile shader draws its ribs at this spacing,
# and the round tile ends along the eave sit on them.
PITCH = 0.3


class Roof:
    """One roof's numbers. `w` and `d` are half the plan to the eave tips along X and Y, `hip_run`
    how far in from the end eaves the gables stand (all of `d` for a pure hip), `rise` the eave
    to the ridge, `thick` the depth of the roof at its edge, and `sori` how far the corners lift."""

    def __init__(self, w, d, hip_run, rise, thick, sori, soffit_run, rafter_pitch):
        self.w, self.d, self.hip_run, self.rise = w, d, hip_run, rise
        self.thick, self.sori, self.soffit_run, self.rafter_pitch = thick, sori, soffit_run, rafter_pitch
        self.xg = w - hip_run

    def f(self, run):
        # Concave: shallow at the eave, steepening to the ridge, as a Japanese roof is.
        return self.rise * (max(run, 0.0) / self.d) ** 1.55

    def lift(self, e, run):
        # `e` is how far along the eave from the nearest corner; on a hip line it equals the run,
        # so the slope either side of it agrees. The corners sweep up, the whole eave a little.
        corner = self.sori * math.exp(-e / 1.3 * (2.0 / max(self.d, 2.0)) ** 0.5)
        line = self.sori * 0.35 * math.exp(-e / 4.5)
        return (corner + line) * math.exp(-run / 2.2)

    def height(self, e, run):
        return self.f(run) + self.lift(e, run)

    def xmax(self, t):
        return max(self.w - t, self.xg)


def runs(r, upto):
    """Rows up a slope: close together near the eave, where the curve and the lift change fastest,
    and with one exactly at the hip run, where the slope's edge turns from the hip to the gable."""
    out = [0.0, 0.08, 0.2, 0.36, 0.56, 0.8, 1.08, 1.4, 1.76, 2.16, 2.6]
    out = [t for t in out if t < upto - 0.05]
    t = out[-1]
    while t < upto - 0.05:
        t += 0.42
        out.append(min(t, upto))
    if r.hip_run < upto and all(abs(r.hip_run - x) > 1e-4 for x in out):
        out.append(r.hip_run)
    out.append(upto)
    return sorted(set(round(x, 5) for x in out))


def grid(bm, uv, rows, cols, point, uvf, mat, flip=False):
    """Faces between rows of points: point(i, j) and uvf(i, j) for row i, column j."""
    verts = [[bm.verts.new(point(i, j)) for j in range(cols)] for i in range(rows)]
    for i in range(rows - 1):
        for j in range(cols - 1):
            q = [verts[i][j], verts[i][j + 1], verts[i + 1][j + 1], verts[i + 1][j]]
            ids = [(i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)]
            if flip:
                q.reverse()
                ids.reverse()
            if len({v.index for v in q}) < 4 and False:
                continue
            try:
                face = bm.faces.new(q)
            except ValueError:
                continue
            face.material_index = mat
            for loop, (a, b) in zip(face.loops, ids):
                loop[uv].uv = uvf(a, b)
    return verts


def sweep(bm, path, section, mat, up=(0, 0, 1), caps=True):
    """A section (list of (side, up) points, closed) swept along `path`, kept upright."""
    from mathutils import Vector
    pts = [Vector(p) for p in path]
    upv = Vector(up)
    rings = []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        tan = (b - a).normalized()
        side = tan.cross(upv)
        if side.length < 1e-6:
            side = Vector((1, 0, 0))
        side.normalize()
        vert = side.cross(tan).normalized()
        rings.append([bm.verts.new(p + side * s + vert * u) for s, u in section])
    n = len(section)
    for i in range(len(rings) - 1):
        for k in range(n):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % n], rings[i + 1][(k + 1) % n], rings[i + 1][k]))
            f.material_index = mat
    if caps:
        for ring, rev in ((rings[0], True), (rings[-1], False)):
            f = bm.faces.new(list(reversed(ring)) if rev else ring)
            f.material_index = mat
    return rings


def rounded(w, h, segs=5, below=0.06):
    """A ridge's section: upright sides and a round top, `w` wide and `h` tall, reaching `below`
    under its path so it beds into the slope."""
    pts = [(-w / 2, -below), (w / 2, -below), (w / 2, h - w / 2)]
    for k in range(1, segs):
        a = math.pi * k / segs
        pts.append((w / 2 * math.cos(a), h - w / 2 + w / 2 * math.sin(a)))
    pts.append((-w / 2, h - w / 2))
    return pts


def box_section(w, h):
    return [(-w / 2, -h), (w / 2, -h), (w / 2, 0.0), (-w / 2, 0.0)]


def onigawara(bm, at, facing_x, size, mat):
    """The ogre tile at a ridge's end: a tall slab, flared at its top corners, facing out."""
    from mathutils import Vector
    w, h, t = size
    # Outline in (side, up): a broad foot, waisted, flaring out into two horns at the top.
    outline = [(-w * 0.5, 0.0), (w * 0.5, 0.0), (w * 0.42, h * 0.45), (w * 0.62, h * 0.92),
               (w * 0.45, h), (w * 0.18, h * 0.8), (0.0, h * 0.86), (-w * 0.18, h * 0.8),
               (-w * 0.45, h), (-w * 0.62, h * 0.92), (-w * 0.42, h * 0.45)]
    ax = Vector(facing_x).normalized()
    side = Vector((-ax.y, ax.x, 0.0))
    base = Vector(at)
    front = [bm.verts.new(base + ax * (t * 0.5) + side * s + Vector((0, 0, u))) for s, u in outline]
    back = [bm.verts.new(base - ax * (t * 0.5) + side * s + Vector((0, 0, u))) for s, u in outline]
    f = bm.faces.new(front)
    f.material_index = mat
    f = bm.faces.new(list(reversed(back)))
    f.material_index = mat
    n = len(outline)
    for k in range(n):
        f = bm.faces.new((front[(k + 1) % n], front[k], back[k], back[(k + 1) % n]))
        f.material_index = mat


def build(name, r, with_gable_ridges=True):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    w, d = r.w, r.d
    # --- the front and back slopes ----------------------------------------------------------
    trows = runs(r, d)
    cols = max(int(2 * w / 0.25), 8)
    for sy in (-1.0, 1.0):
        def p(i, j, sy=sy, top=True):
            t = trows[i]
            x = (-1 + 2 * j / (cols - 1)) * r.xmax(t)
            e = w - abs(x)
            z = r.height(e, t) - (0 if top else r.thick)
            return (x, sy * (d - t), z)

        arc = [0.0]
        for i in range(1, len(trows)):
            dt = trows[i] - trows[i - 1]
            dh = r.f(trows[i]) - r.f(trows[i - 1])
            arc.append(arc[-1] + math.hypot(dt, dh))

        def u(i, j, sy=sy):
            return ((-1 + 2 * j / (cols - 1)) * r.xmax(trows[i]), arc[i])

        grid(bm, uv, len(trows), cols, lambda i, j: p(i, j), u, TILES, flip=sy > 0)
        # The soffit: the same surface a roof's depth under, facing down, out to where the
        # pavilion's ceiling takes over.
        srows = [t for t in trows if t <= r.soffit_run + 1e-4]
        if srows[-1] < r.soffit_run:
            srows.append(r.soffit_run)

        def ps(i, j, sy=sy):
            t = srows[i]
            x = (-1 + 2 * j / (cols - 1)) * r.xmax(t)
            return (x, sy * (d - t), r.height(w - abs(x), t) - r.thick)

        grid(bm, uv, len(srows), cols, ps, lambda i, j: (0, 0), SOFFIT, flip=sy < 0)
        # The fascia: down the roof's depth at the eave.
        fas = [[bm.verts.new(p2) for p2 in (p(0, j, sy, True), p(0, j, sy, False))] for j in range(cols)]
        for j in range(cols - 1):
            q = [fas[j][0], fas[j + 1][0], fas[j + 1][1], fas[j][1]]
            if sy < 0:
                q.reverse()
            f = bm.faces.new(q)
            f.material_index = FASCIA

    # --- the hip ends -------------------------------------------------------------------------
    srun = [t for t in runs(r, r.hip_run)]
    hcols = max(int(2 * d / 0.25), 8)
    for sx in (-1.0, 1.0):
        def ph(i, j, sx=sx, top=True, rows=srun):
            s = rows[i]
            y = (-1 + 2 * j / (hcols - 1)) * (d - s)
            e = d - abs(y)
            return (sx * (w - s), y, r.height(e, s) - (0 if top else r.thick))

        arc = [0.0]
        for i in range(1, len(srun)):
            arc.append(arc[-1] + math.hypot(srun[i] - srun[i - 1], r.f(srun[i]) - r.f(srun[i - 1])))
        grid(bm, uv, len(srun), hcols, lambda i, j: ph(i, j),
             lambda i, j: ((-1 + 2 * j / (hcols - 1)) * (d - srun[i]), arc[i]), TILES, flip=sx < 0)
        srows = [t for t in srun if t <= r.soffit_run + 1e-4]
        grid(bm, uv, len(srows), hcols, lambda i, j: ph(i, j, top=False, rows=srows),
             lambda i, j: (0, 0), SOFFIT, flip=sx > 0)
        fas = [[bm.verts.new(p2) for p2 in (ph(0, j), ph(0, j, top=False))] for j in range(hcols)]
        for j in range(hcols - 1):
            q = [fas[j][0], fas[j + 1][0], fas[j + 1][1], fas[j][1]]
            if sx > 0:
                q.reverse()
            f = bm.faces.new(q)
            f.material_index = FASCIA

        if r.xg > 0.05:
            # The gable: a vertical face over the hip's top, up to the slopes' edge.
            n = 24
            span = d - r.hip_run
            bottom, top = [], []
            for k in range(n + 1):
                y = -span + 2 * span * k / n
                bottom.append(bm.verts.new((sx * r.xg, y, r.height(d - abs(y), r.hip_run))))
                top.append(bm.verts.new((sx * r.xg, y, r.height(r.hip_run, d - abs(y)))))
            for k in range(n):
                q = [bottom[k], bottom[k + 1], top[k + 1], top[k]]
                if sx < 0:
                    q.reverse()
                f = bm.faces.new(q)
                f.material_index = GABLE
                for loop in f.loops:
                    loop[uv].uv = (loop.vert.co.y, loop.vert.co.z)
            # The bargeboard, just proud of the gable, hanging from the slopes' edge.
            path = []
            for k in range(n + 1):
                y = -span + 2 * span * k / n
                path.append((sx * (r.xg + 0.07), y, r.height(r.hip_run, d - abs(y)) + 0.06))
            sweep(bm, path, [(-0.035, -0.42), (0.035, -0.42), (0.035, 0.0), (-0.035, 0.0)], FASCIA,
                  up=(0, 0, 1))
            # The hanging ornament under the gable's apex (gegyo).
            top_z = r.height(r.hip_run, d)
            sweep(bm, [(sx * (r.xg + 0.07), 0, top_z - 0.3), (sx * (r.xg + 0.07), 0, top_z - 0.85)],
                  [(-0.04, -0.22), (0.04, -0.22), (0.04, 0.22), (-0.04, 0.22)], FASCIA, up=(1, 0, 0))

    # --- the ridges ---------------------------------------------------------------------------
    top_z = r.height(r.hip_run if r.xg > 0 else 0.0, d)
    if r.xg > 0.05:
        ridge_len = r.xg + 0.12
        path = [(x, 0.0, r.height(w - abs(x), d) + 0.02) for x in
                [-ridge_len + 2 * ridge_len * k / 16 for k in range(17)]]
        sweep(bm, path, rounded(0.42, 0.62), RIDGE, up=(0, 0, 1))
        for sx in (-1.0, 1.0):
            onigawara(bm, (sx * (ridge_len + 0.02), 0.0, path[0][2] - 0.05), (sx, 0, 0), (0.62, 0.95, 0.22), RIDGE)
        if with_gable_ridges:
            for sx in (-1.0, 1.0):
                for sy in (-1.0, 1.0):
                    # Down the gable's edge, a little in from the bargeboard.
                    pts = []
                    for k in range(13):
                        t = d - (d - r.hip_run) * k / 12
                        pts.append((sx * (r.xg - 0.12), sy * (d - t), r.height(r.hip_run, t) + 0.02))
                    sweep(bm, pts, rounded(0.26, 0.3), RIDGE)
    # Down each hip to its corner, ending in a small upturned ogre tile.
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            pts = []
            hr = r.hip_run if r.xg > 0.05 else d
            for k in range(15):
                t = hr * (1.0 - k / 14) + 0.25 * (k / 14)
                pts.append((sx * (w - t), sy * (d - t), r.height(t, t) + 0.02))
            sweep(bm, pts, rounded(0.26 if r.d > 3 else 0.12, 0.3 if r.d > 3 else 0.12), RIDGE)
            end = pts[-1]
            dirn = (sx * 0.7071, sy * 0.7071, 0)
            scale = 1.0 if r.d > 3 else 0.4
            onigawara(bm, (end[0] + dirn[0] * 0.06, end[1] + dirn[1] * 0.06, end[2] - 0.04), dirn,
                      (0.34 * scale, 0.5 * scale, 0.14 * scale), RIDGE)
    if r.xg <= 0.05:
        # A pure hip's top: a capping block and a finial socket.
        from mathutils import Matrix as _M
        res = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.16 * r.d, radius2=0.1 * r.d,
                                    depth=0.2 * r.d, matrix=_M.Translation((0, 0, r.rise + 0.06 * r.d)))
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = RIDGE

    # --- round tile ends along the eave ------------------------------------------------------
    from mathutils import Matrix, Vector
    rad = 0.075 if r.d > 3 else 0.035
    pitch = PITCH if r.d > 3 else 0.15
    for sy in (-1.0, 1.0):
        k0 = int(w / pitch)
        for k in range(-k0, k0 + 1):
            x = k * pitch
            if abs(x) > w - 0.2:
                continue
            z = r.height(w - abs(x), 0.0) - rad * 0.6
            m = Matrix.Translation((x, sy * (d + 0.01), z)) @ Matrix.Rotation(math.pi / 2, 4, "X")
            res = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=rad, radius2=rad, depth=0.06,
                                        matrix=m)
            for f in {f for v in res["verts"] for f in v.link_faces}:
                f.material_index = RIDGE
    for sx in (-1.0, 1.0):
        k0 = int(d / pitch)
        for k in range(-k0, k0 + 1):
            y = k * pitch
            if abs(y) > d - 0.2:
                continue
            z = r.height(d - abs(y), 0.0) - rad * 0.6
            m = Matrix.Translation((sx * (w + 0.01), y, z)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
            res = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=rad, radius2=rad, depth=0.06,
                                        matrix=m)
            for f in {f for v in res["verts"] for f in v.link_faces}:
                f.material_index = RIDGE

    # --- rafters under the soffit --------------------------------------------------------------
    rw, rh = (0.075, 0.09) if r.d > 3 else (0.03, 0.035)
    for sy in (-1.0, 1.0):
        k0 = int(w / r.rafter_pitch)
        for k in range(-k0, k0 + 1):
            x = (k + 0.5) * r.rafter_pitch
            reach = min(r.soffit_run, w - abs(x) - 0.06)
            if reach < 0.15:
                continue
            pts = [(x, sy * (d - t - 0.02), r.height(w - abs(x), t) - r.thick)
                   for t in [reach * q / 4 for q in range(5)]]
            sweep(bm, pts, box_section(rw, rh), RAFTERS)
    for sx in (-1.0, 1.0):
        k0 = int(d / r.rafter_pitch)
        for k in range(-k0, k0 + 1):
            y = (k + 0.5) * r.rafter_pitch
            reach = min(r.soffit_run, d - abs(y) - 0.06, r.hip_run if r.xg > 0.05 else d)
            if reach < 0.15:
                continue
            pts = [(sx * (w - t - 0.02), y, r.height(d - abs(y), t) - r.thick)
                   for t in [reach * q / 4 for q in range(5)]]
            sweep(bm, pts, box_section(rw, rh), RAFTERS)
    # The corner rafters, heavier, out along each hip under the soffit.
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            reach = min(r.soffit_run * 1.2, r.hip_run if r.xg > 0.05 else d)
            pts = [(sx * (w - t), sy * (d - t), r.height(t, t) - r.thick)
                   for t in [-0.12 + (reach + 0.12) * q / 6 for q in range(7)]]
            sweep(bm, pts, box_section(rw * 2.2, rh * 2.4), RAFTERS)

    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in MAT_NAMES:
        me.materials.append(mats[m])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    print("%s: %d faces" % (name, len(me.polygons)))
    return ob


# The pavilion's: its eaves 1.9 m past the columns all round (see GardenVenue), the gables
# 2.6 m in from the end eaves.
build("Roof", Roof(w=9.35, d=7.5, hip_run=2.6, rise=4.3, thick=0.3, sori=0.5, soffit_run=1.95,
                   rafter_pitch=0.32))
sq = build("RoofSquare", Roof(w=1.0, d=1.0, hip_run=1.0, rise=0.62, thick=0.06, sori=0.14, soffit_run=0.6,
                              rafter_pitch=0.12))
sq.location.x = 14.0

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/garden_roof.glb"), export_format="GLB",
                          export_yup=True)
print("wrote garden_roof.glb")

if os.environ.get("PREVIEW"):
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = (22, -26, 12)
    cam.rotation_euler = (math.radians(68), 0, math.radians(40))
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    scene.collection.objects.link(sun)
    sun.rotation_euler = (0.7, 0.3, 0.5)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 650
    scene.render.filepath = os.environ["PREVIEW"]
    bpy.ops.render.render(write_still=True)
