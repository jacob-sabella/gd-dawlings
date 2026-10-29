#!/usr/bin/env python3
"""Top-down maps of tools/layout_dump.gd's JSON, and the clearances in them.

    godot --headless --path . tools/layout_dump.tscn
    python3 tools/layout_map.py [shots/tmp/layout]

For each <venue>.json: <venue>.svg and <venue>.png (rsvg-convert, else magick), a 1 m grid,
the walkable floor, the walls (Walker.outline), the zones, every footprint labelled, the seat
and its view wedge; then all.jpg (magick montage) and summary.json: per venue the room's size,
floor area, counts, every pair of footprints closer than 0.6 m, and which stations' seats a
person can walk to from the desk (body radius 0.25 m) and with a 0.9 m walkway (0.45 m).
Standard library only.
"""
import json
import math
import os
import re
import shutil
import subprocess
import sys
from collections import deque

OUT = sys.argv[1] if len(sys.argv) > 1 else "shots/tmp/layout"
PX = 56  # pixels per metre
STEP = 0.32  # Walker.STEP_HEIGHT: anything lower is stepped onto
CLEAR = 0.6
GRID = 0.05

COL = {
    "trolley": "#2f6fd0",
    "fixed": "#d07a1f",
    "console": "#222222",
    "station": "#c0247a",
    "item": "#2a9a3a",
    "wall_mounted": "#7a3fc0",
    "visual": "#888888",
}


# --- geometry -----------------------------------------------------------------------------

def corners_of(c, h, a_deg):
    a = math.radians(a_deg)
    ax = (math.cos(a), -math.sin(a))
    az = (math.sin(a), math.cos(a))
    out = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        out.append((c[0] + ax[0] * h[0] * sx + az[0] * h[1] * sz,
                    c[1] + ax[1] * h[0] * sx + az[1] * h[1] * sz))
    return out


def local_box_corners(origin, heading_deg, local):
    """A node's own-frame AABB [x, z, w, d] at its origin and heading, on the floor."""
    a = math.radians(heading_deg)
    x0, z0, w, d = local
    pts = [(x0, z0), (x0 + w, z0), (x0 + w, z0 + d), (x0, z0 + d)]
    out = []
    for x, z in pts:
        # Basis(UP, a): local +X -> (cos a, -sin a), local +Z -> (sin a, cos a)
        out.append((origin[0] + x * math.cos(a) + z * math.sin(a),
                    origin[1] - x * math.sin(a) + z * math.cos(a)))
    return out


def _axes(poly):
    out = []
    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        ex, ez = q[0] - p[0], q[1] - p[1]
        n = math.hypot(ex, ez)
        if n > 1e-9:
            out.append((-ez / n, ex / n))
    return out


def penetration(a, b):
    """Least overlap along the separating axes (>0 overlapping), or 0 apart."""
    best = math.inf
    for ax in _axes(a) + _axes(b):
        pa = [p[0] * ax[0] + p[1] * ax[1] for p in a]
        pb = [p[0] * ax[0] + p[1] * ax[1] for p in b]
        o = min(max(pa), max(pb)) - max(min(pa), min(pb))
        if o <= 0:
            return 0.0
        best = min(best, o)
    return best


def seg_dist(p, a, b):
    ex, ez = b[0] - a[0], b[1] - a[1]
    L = ex * ex + ez * ez
    t = 0 if L == 0 else max(0, min(1, ((p[0] - a[0]) * ex + (p[1] - a[1]) * ez) / L))
    return math.hypot(p[0] - a[0] - t * ex, p[1] - a[1] - t * ez)


def gap(a, b):
    """Distance between two convex polygons; negative is how deep they overlap."""
    pen = penetration(a, b)
    if pen > 0:
        return -pen
    d = math.inf
    for P, Q in ((a, b), (b, a)):
        for p in P:
            for i in range(len(Q)):
                d = min(d, seg_dist(p, Q[i], Q[(i + 1) % len(Q)]))
    return d


def point_poly_dist(p, poly):
    inside = penetration([p, (p[0] + 1e-6, p[1]), (p[0], p[1] + 1e-6)], poly) > 0
    d = min(seg_dist(p, poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))
    return -d if inside else d


def in_rects(p, rects, eps=1e-3):
    # eps: the rects meet along shared lines only to float precision (the control room's back is
    # 2.7999997, the live room's front 2.79999995), and a probe between them is on no floor.
    return any(r[0] - eps <= p[0] <= r[0] + r[2] + eps and r[1] - eps <= p[1] <= r[1] + r[3] + eps for r in rects)


# --- analysis -----------------------------------------------------------------------------

def obstacles(d, walk_only=True):
    out = []
    for t in d["things"]:
        if t.get("visible") is False:
            continue
        if walk_only and t.get("walk_through"):
            continue
        top = t.get("top", 1.25)
        if t["kind"] == "fixed" and 0 <= top <= STEP and walk_only:
            continue
        out.append(t)
    return out


def walk_grid(d, obs, radius):
    rects = d["walkable"]
    xs = [r[0] for r in rects] + [r[0] + r[2] for r in rects]
    zs = [r[1] for r in rects] + [r[1] + r[3] for r in rects]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    nx, nz = int((x1 - x0) / GRID) + 1, int((z1 - z0) / GRID) + 1
    polys = [t["corners"] for t in obs]
    boxes = []
    for poly in polys:
        px = [p[0] for p in poly]
        pz = [p[1] for p in poly]
        boxes.append((min(px) - radius, max(px) + radius, min(pz) - radius, max(pz) + radius, poly))
    free = [[False] * nz for _ in range(nx)]
    for i in range(nx):
        x = x0 + i * GRID
        for j in range(nz):
            z = z0 + j * GRID
            # The whole body on the floor (Walker.fits probes the ring at RADIUS + 0.03).
            if not all(in_rects((x + radius * math.cos(k * math.pi / 4), z + radius * math.sin(k * math.pi / 4)), rects)
                       for k in range(8)) or not in_rects((x, z), rects):
                continue
            ok = True
            for bx0, bx1, bz0, bz1, poly in boxes:
                if bx0 <= x <= bx1 and bz0 <= z <= bz1 and point_poly_dist((x, z), poly) < radius:
                    ok = False
                    break
            free[i][j] = ok
    return free, x0, z0, nx, nz


def reach_from(grid, start):
    free, x0, z0, nx, nz = grid
    seen = [[False] * nz for _ in range(nx)]
    si, sj = round((start[0] - x0) / GRID), round((start[1] - z0) / GRID)
    # Nearest free cell to the start.
    best = None
    for r in range(0, 20):
        for i in range(si - r, si + r + 1):
            for j in range(sj - r, sj + r + 1):
                if 0 <= i < nx and 0 <= j < nz and free[i][j]:
                    best = (i, j)
                    break
            if best:
                break
        if best:
            break
    if not best:
        return seen
    q = deque([best])
    seen[best[0]][best[1]] = True
    while q:
        i, j = q.popleft()
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            a, b = i + di, j + dj
            if 0 <= a < nx and 0 <= b < nz and free[a][b] and not seen[a][b]:
                seen[a][b] = True
                q.append((a, b))
    return seen


def reached(grid, seen, p, slack=0.15):
    free, x0, z0, nx, nz = grid
    si, sj = round((p[0] - x0) / GRID), round((p[1] - z0) / GRID)
    r = int(slack / GRID)
    for i in range(si - r, si + r + 1):
        for j in range(sj - r, sj + r + 1):
            if 0 <= i < nx and 0 <= j < nz and seen[i][j]:
                return True
    return False


def gameplay_dressing(x):
    if x["kind"] == "scenery":
        return False
    cls = x.get("class") or ""
    name = x["name"]
    if name in ("PropShelf", "BellStand", "DrumCircle", "Mirror", "PatchWall", "RouletteDoor", "VenueInstrument"):
        return True
    if name.startswith("Zone_"):
        return True
    return bool(cls) and not cls.endswith("3D") and not name.startswith("@")


def name_things(d):
    """Lamps by their piece id; a venue solid outside every zone by the smallest piece of the
    venue's dressing standing over its middle (a pillar, the bar, a planter)."""
    for t in d["things"]:
        if t["kind"] == "trolley" and t["name"].startswith("@"):
            t["name"] = t["id"]
        if t["kind"] == "fixed" and t["name"] in ("zone", "venue", "instrument", "weather"):
            best, area = None, math.inf
            for x in d["dressing"]:
                if x["kind"] == "scenery" or not x["mesh"] or x["name"].startswith("Zone_"):
                    continue
                w = x["mesh"]["world"]
                if w[0] - 0.05 <= t["c"][0] <= w[0] + w[2] + 0.05 and w[1] - 0.05 <= t["c"][1] <= w[1] + w[3] + 0.05 \
                        and w[2] * w[3] < area and w[2] * w[3] < 40:
                    best, area = x["name"], w[2] * w[3]
            tag = {"zone": "solid", "venue": "solid"}.get(t["name"], t["name"])
            t["name"] = "%s:%s" % (tag, best) if best and not best.startswith("@") else tag


def analyse(d):
    name_things(d)
    obs_all = obstacles(d, walk_only=False)
    pairs = []
    for i in range(len(obs_all)):
        for j in range(i + 1, len(obs_all)):
            a, b = obs_all[i], obs_all[j]
            if a["in"] == b["in"] and a["in"].startswith("zone:"):
                continue  # one activity's own furniture
            ta, tb = a.get("top", 1.25), b.get("top", 1.25)
            if (a["kind"] == "fixed" and 0 <= ta <= STEP) or (b["kind"] == "fixed" and 0 <= tb <= STEP):
                continue  # a riser or a step, stood on
            g = gap(a["corners"], b["corners"])
            if g < CLEAR:
                pairs.append({"a": a["name"], "b": b["name"], "gap": round(g, 3), "a_in": a["in"], "b_in": b["in"]})
    pairs.sort(key=lambda p: p["gap"])
    # Footprints off the walkable floor (part or all of them).
    off = []
    for t in obs_all:
        outside = [c for c in t["corners"] if not in_rects(c, d["walkable"])]
        if outside:
            off.append({"name": t["name"], "corners_off_floor": len(outside), "in": t["in"]})
    # Visual (mesh) boxes of the gameplay pieces: overlaps of what is drawn, past the footprints.
    vis = []
    for s in d["surfaces"]:
        if s["visible"] and s["mesh"]:
            vis.append((s["id"], local_box_corners(s["origin"], s["heading_deg"], s["mesh"]["local"]),
                        "control_room" if in_rects(s["origin"], [d["control_room"]]) else "x"))
    for x in d["dressing"]:
        if gameplay_dressing(x) and not x["name"].startswith("Zone_") and x["mesh"]:
            vis.append((x["name"], local_box_corners(x["origin"], x["heading_deg"], x["mesh"]["local"]), x["in"]))
    vis_pairs = []
    for i in range(len(vis)):
        for j in range(i + 1, len(vis)):
            g = gap(vis[i][1], vis[j][1])
            if g < 0 and not (vis[i][2] == vis[j][2] and vis[i][2].startswith("zone:")):
                vis_pairs.append({"a": vis[i][0], "b": vis[j][0], "overlap": round(-g, 3)})
    vis_pairs.sort(key=lambda p: -p["overlap"])
    # Walking.
    obs = obstacles(d)
    seat = d["seat"]["at"]
    walk = {}
    for label, radius, slack in (("body_0.25", 0.25, 0.15), ("walkway_0.9", 0.45, 0.5)):
        grid = walk_grid(d, obs, radius)
        seen = reach_from(grid, seat)
        free_cells = sum(sum(1 for v in col if v) for col in grid[0])
        seen_cells = sum(sum(1 for v in col if v) for col in seen)
        unreach = [s["id"] for s in d["stations"] if s.get("seat") and not reached(grid, seen, s["seat"], slack)]
        walk[label] = {"free_m2": round(free_cells * GRID * GRID, 2),
                       "reachable_m2": round(seen_cells * GRID * GRID, 2),
                       "stations_unreachable": unreach}
        if label == "body_0.25":
            body_grid, body_seen = grid, seen
    occupied = sum(abs(t["h"][0] * t["h"][1] * 4) for t in obs_all if not (t["kind"] == "fixed" and 0 <= t.get("top", 1) <= STEP))
    cr = d["control_room"]
    in_cr = [t for t in obs_all if t["in"] == "control_room"]
    occ_cr = sum(abs(t["h"][0] * t["h"][1] * 4) for t in in_cr)
    return {
        "venue": d["venue"], "title": d["title"],
        "control_room_m": [round(cr[2], 2), round(cr[3], 2)], "control_room_m2": round(cr[2] * cr[3], 1),
        "walkable_rects": len(d["walkable"]), "walkable_m2": round(d["walkable_area_union"], 1),
        "extent_m": extent(d),
        "footprints": len(obs_all), "in_control_room": len(in_cr),
        "occupied_m2": round(occupied, 2), "control_room_occupied_m2": round(occ_cr, 2),
        "stations": len(d["stations"]), "items": len(d["items"]),
        "close_pairs": pairs, "off_floor": off, "visual_overlaps": vis_pairs[:40], "walk": walk,
        "station_seat_distances": {s["id"]: round(s["seat_dist_from_desk_seat"], 2) for s in d["stations"]
                                   if s.get("seat_dist_from_desk_seat") is not None},
    }, (body_grid, body_seen)


def extent(d):
    rects = d["walkable"]
    xs = [r[0] for r in rects] + [r[0] + r[2] for r in rects]
    zs = [r[1] for r in rects] + [r[1] + r[3] for r in rects]
    return [round(min(xs), 2), round(min(zs), 2), round(max(xs) - min(xs), 2), round(max(zs) - min(zs), 2)]


# --- drawing ------------------------------------------------------------------------------

def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def short(name):
    return re.sub(r"(Trolley|Stand)$", "", name) or name


def svg_for(d, summary, walkgrid):
    pts = []
    for r in d["walkable"]:
        pts += [(r[0], r[1]), (r[0] + r[2], r[1] + r[3])]
    for z in d["zones"].values():
        r = z["rect"]
        pts += [(r[0], r[1]), (r[0] + r[2], r[1] + r[3])]
    for t in d["things"]:
        pts += [tuple(c) for c in t["corners"]]
    x0 = math.floor(min(p[0] for p in pts) - 0.6)
    x1 = math.ceil(max(p[0] for p in pts) + 0.6)
    z0 = math.floor(min(p[1] for p in pts) - 0.6)
    z1 = math.ceil(max(p[1] for p in pts) + 0.6)
    W, H = (x1 - x0) * PX, (z1 - z0) * PX + 70
    X = lambda x: (x - x0) * PX
    Z = lambda z: (z - z0) * PX + 50
    poly = lambda cs: " ".join("%.1f,%.1f" % (X(c[0]), Z(c[1])) for c in cs)
    o = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" font-family="Adwaita Sans, DejaVu Sans, sans-serif">' % (W, H),
         '<rect width="100%" height="100%" fill="#fbfaf7"/>']
    # Walkable floor.
    for r in d["walkable"]:
        o.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#e9efe4" stroke="none"/>'
                 % (X(r[0]), Z(r[1]), r[2] * PX, r[3] * PX))
    # Where the body cannot reach from the seat (radius 0.25), on the floor: hatched.
    free, gx0, gz0, nx, nz = walkgrid[0]
    seen = walkgrid[1]
    for i in range(0, nx, 2):
        for j in range(0, nz, 2):
            x, z = gx0 + i * GRID, gz0 + j * GRID
            if in_rects((x, z), d["walkable"]) and not seen[i][j]:
                o.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#f3d6d6"/>'
                         % (X(x - GRID), Z(z - GRID), 2 * GRID * PX, 2 * GRID * PX))
    # Grid, 1 m.
    for x in range(x0, x1 + 1):
        o.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="%s"/>'
                 % (X(x), Z(z0), X(x), Z(z1), "#9a9a9a" if x == 0 else "#d8d8d8", 1.2 if x == 0 else 0.6))
        o.append('<text x="%.1f" y="%.1f" font-size="10" fill="#777" text-anchor="middle">%d</text>' % (X(x), Z(z0) - 4, x))
    for z in range(z0, z1 + 1):
        o.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="%s"/>'
                 % (X(x0), Z(z), X(x1), Z(z), "#9a9a9a" if z == 0 else "#d8d8d8", 1.2 if z == 0 else 0.6))
        o.append('<text x="%.1f" y="%.1f" font-size="10" fill="#777">%d</text>' % (X(x0) + 2, Z(z) - 2, z))
    # Zones.
    for zid, z in d["zones"].items():
        r = z["rect"]
        o.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="#3a8f8f" stroke-dasharray="6,4" stroke-width="1.2"/>'
                 % (X(r[0]), Z(r[1]), r[2] * PX, r[3] * PX))
        o.append('<text x="%.1f" y="%.1f" font-size="11" fill="#2a7070" font-style="italic">zone %s</text>' % (X(r[0]) + 3, Z(r[1] + r[3]) - 4, esc(zid)))
    # Control room outline.
    cr = d["control_room"]
    o.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="#5a7a50" stroke-dasharray="2,3" stroke-width="1"/>'
             % (X(cr[0]), Z(cr[1]), cr[2] * PX, cr[3] * PX))
    # Walls.
    for a, b, _n in d["walls"]:
        o.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#333" stroke-width="3.5" stroke-linecap="square"/>'
                 % (X(a[0]), Z(a[1]), X(b[0]), Z(b[1])))
    # Visual extents of the gameplay pieces.
    for s in d["surfaces"]:
        if s["visible"] and s["mesh"]:
            o.append('<polygon points="%s" fill="none" stroke="%s" stroke-width="0.8" stroke-dasharray="3,2"/>'
                     % (poly(local_box_corners(s["origin"], s["heading_deg"], s["mesh"]["local"])), COL["visual"]))
    for x in d["dressing"]:
        if gameplay_dressing(x) and not x["name"].startswith("Zone_") and x["mesh"]:
            wm = x.get("near_wall", 9) < 0.35
            o.append('<polygon points="%s" fill="%s" fill-opacity="0.12" stroke="%s" stroke-width="%s" stroke-dasharray="3,2"/>'
                     % (poly(local_box_corners(x["origin"], x["heading_deg"], x["mesh"]["local"])),
                        COL["wall_mounted"] if wm else "#aaaaaa", COL["wall_mounted"] if wm else COL["visual"], 1.4 if wm else 0.8))
    # Footprints.
    labels = []
    for t in d["things"]:
        if t.get("visible") is False:
            continue
        kind = "console" if t["id"] == "console" else t["kind"]
        low = t["kind"] == "fixed" and 0 <= t.get("top", 1) <= STEP
        o.append('<polygon points="%s" fill="%s" fill-opacity="%s" stroke="%s" stroke-width="1.2"/>'
                 % (poly(t["corners"]), COL[kind], 0.10 if low else (0.15 if t.get("walk_through") else 0.35), COL[kind]))
        if t["kind"] == "trolley":
            labels.append((t["c"], short(t["name"]), COL[kind]))
        elif t["id"] == "console":
            labels.append((t["c"], "CONSOLE", COL[kind]))
        elif not t["name"].startswith("zone:"):
            labels.append((t["c"], t["name"], COL[kind]))
    # Items.
    for it in d["items"]:
        if it.get("visible", True):
            o.append('<circle cx="%.1f" cy="%.1f" r="2.2" fill="%s"/>' % (X(it["at"][0]), Z(it["at"][1]), COL["item"]))
    # Stations: spot, seat, and a line between.
    for s in d["stations"]:
        a, st = s["at"], s.get("seat")
        if st:
            o.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="0.8" stroke-dasharray="2,2"/>'
                     % (X(a[0]), Z(a[1]), X(st[0]), Z(st[1]), COL["station"]))
            o.append('<circle cx="%.1f" cy="%.1f" r="3" fill="none" stroke="%s" stroke-width="1"/>' % (X(st[0]), Z(st[1]), COL["station"]))
        o.append('<circle cx="%.1f" cy="%.1f" r="3.2" fill="%s"/>' % (X(a[0]), Z(a[1]), COL["station"]))
        labels.append((a, s["title"].lower(), COL["station"]))
    # The seat and its view: the desk is toward -Z (up the page).
    sx, sz = d["seat"]["at"]
    vfov = math.radians(d["seat"]["fov"])
    hfov = 2 * math.atan(math.tan(vfov / 2) * 16 / 9)
    R = 3.5
    pa = (sx - R * math.sin(hfov / 2), sz - R * math.cos(hfov / 2))
    pb = (sx + R * math.sin(hfov / 2), sz - R * math.cos(hfov / 2))
    o.append('<path d="M%.1f,%.1f L%.1f,%.1f A%.1f,%.1f 0 0,1 %.1f,%.1f Z" fill="#ffd34d" fill-opacity="0.18" stroke="#c9a000" stroke-width="0.8"/>'
             % (X(sx), Z(sz), X(pa[0]), Z(pa[1]), R * PX, R * PX, X(pb[0]), Z(pb[1])))
    o.append('<circle cx="%.1f" cy="%.1f" r="6" fill="#ffcc00" stroke="#000" stroke-width="1.2"/>' % (X(sx), Z(sz)))
    labels.append(((sx + 0.12, sz + 0.12), "SEAT", "#000"))
    # Labels, nudged down where they would sit on one already placed.
    placed = []
    for (c, text, colour) in labels:
        x, y = X(c[0]) + 4, Z(c[1]) - 3
        for _ in range(8):
            if any(abs(y - py) < 10 and abs(x - px) < max(40, len(text) * 5.5) for px, py in placed):
                y += 10
            else:
                break
        placed.append((x, y))
        o.append('<text x="%.1f" y="%.1f" font-size="9.5" fill="%s" stroke="#fbfaf7" stroke-width="2.4" paint-order="stroke">%s</text>'
                 % (x, y, colour, esc(text)))
    # Title and legend.
    cr_w, cr_d = summary["control_room_m"]
    head = "%s  ·  control room %.1f x %.1f m  ·  walkable %.0f m²  ·  %d footprints, %d stations, %d items  ·  pairs < 0.6 m: %d" % (
        d["title"], cr_w, cr_d, summary["walkable_m2"], summary["footprints"], summary["stations"], summary["items"],
        len(summary["close_pairs"]))
    o.append('<text x="8" y="18" font-size="14" font-weight="bold" fill="#111">%s</text>' % esc(head))
    legend = [("trolley", "trolley (FloorPlan piece)"), ("fixed", "venue solid"), ("console", "desk"),
              ("station", "station spot · seat"), ("item", "item home"), ("wall_mounted", "near a wall (<0.35 m)"),
              ("visual", "mesh extent")]
    x = 8
    for k, txt in legend:
        o.append('<rect x="%d" y="26" width="10" height="10" fill="%s" fill-opacity="0.6"/>' % (x, COL[k]))
        o.append('<text x="%d" y="35" font-size="10" fill="#333">%s</text>' % (x + 13, esc(txt)))
        x += 16 + len(txt) * 5.6
    o.append('<rect x="%d" y="26" width="10" height="10" fill="#f3d6d6"/><text x="%d" y="35" font-size="10" fill="#333">floor a body cannot reach from the seat</text>' % (x, x + 13))
    o.append('<text x="8" y="%d" font-size="10" fill="#555">x right, z down the page (+z = behind the seat, toward the live room); the desk faces up (-z). 1 m grid. Wedge: the seat\'s %.0f° x %.0f° view.</text>'
             % (H - 8, math.degrees(hfov), d["seat"]["fov"]))
    o.append("</svg>")
    return "\n".join(o)


def to_png(svg_path, png_path):
    if shutil.which("rsvg-convert"):
        subprocess.run(["rsvg-convert", "-o", png_path, svg_path], check=True)
    else:
        subprocess.run(["magick", svg_path, png_path], check=True)


def main():
    venues = json.load(open(os.path.join(OUT, "index.json")))
    summaries = []
    pngs = []
    for v in venues:
        d = json.load(open(os.path.join(OUT, v + ".json")))
        s, walkgrid = analyse(d)
        summaries.append(s)
        svg = svg_for(d, s, walkgrid)
        sp = os.path.join(OUT, v + ".svg")
        pp = os.path.join(OUT, v + ".png")
        open(sp, "w").write(svg)
        to_png(sp, pp)
        pngs.append(pp)
        print("%-11s cr %4.1fx%4.1f  walk %5.1f m2  feet %2d  st %2d  <0.6m %2d  overlap %2d  unreach(body) %s  unreach(0.9m) %s" % (
            v, s["control_room_m"][0], s["control_room_m"][1], s["walkable_m2"], s["footprints"], s["stations"],
            len(s["close_pairs"]), sum(1 for p in s["close_pairs"] if p["gap"] < 0),
            s["walk"]["body_0.25"]["stations_unreachable"], s["walk"]["walkway_0.9"]["stations_unreachable"]))
    json.dump(summaries, open(os.path.join(OUT, "summary.json"), "w"), indent=1)
    subprocess.run(["magick", "montage", *pngs, "-tile", "4x", "-geometry", "900x900>+6+6",
                    "-background", "#dddddd", "-quality", "85", os.path.join(OUT, "all.jpg")], check=True)


if __name__ == "__main__":
    main()
