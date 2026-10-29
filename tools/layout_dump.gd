extends Node

## Headless floor-plan dump, one JSON per venue: what stands where, on what floor.
##
##   godot --headless --path . tools/layout_dump.tscn
##   LAYOUT_OUT=shots/tmp/layout  LAYOUT_VENUES=studio,club  LAYOUT_VARIANT=0
##   python3 tools/layout_map.py shots/tmp/layout     (the PNG maps and the contact sheet)
##
## Builds the studio the way the suite does (a SCREEN studio on the offline backend, a throwaway
## layout so nobody's saved room is read or written), then for each venue: the walkable floor
## (Studio._walkable, the walker's rects), its walls (Walker.outline of them), the zones, the desk
## and the seat, every floor-plan piece (trolleys: the gear's, the lamps', the live pieces'), the
## venue's own solids (labelled by where they come from), every station (Stations.ids) with its
## spot, seat and solid, the room's items at their homes, and the venue's own top-level dressing
## with its measured footprint. All XZ in studio space (the venue's frame, which is the set's
## on a screen).

var _out_dir := "res://shots/tmp/layout"


func _ready() -> void:
	OfflineBackend.autosave_every = 0.0
	PluginCatalogue.use_only([])
	var dir := OS.get_environment("LAYOUT_OUT")
	if dir != "":
		_out_dir = dir if dir.begins_with("res://") or dir.begins_with("/") else "res://" + dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://layout_dump_profile.cfg"
	var backend := OfflineBackend.new()
	if OS.get_environment("LAYOUT_TRACKS") != "":
		backend.track_count = int(OS.get_environment("LAYOUT_TRACKS"))
	DAW.use(backend)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().process_frame
	await get_tree().process_frame
	var ids: Array = Venue.IDS.duplicate()
	var only := OS.get_environment("LAYOUT_VENUES")
	if only != "":
		ids = Array(only.split(",", false)).map(func(s: String) -> StringName: return StringName(s.strip_edges()))
	var variant := int(OS.get_environment("LAYOUT_VARIANT")) if OS.get_environment("LAYOUT_VARIANT") != "" else 0
	var index := []
	for id: StringName in ids:
		studio.set_venue(id, false, variant)
		await get_tree().process_frame
		await get_tree().physics_frame
		var data := _dump(studio, variant)
		var path := "%s/%s.json" % [_out_dir, id]
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(data, "  "))
		f.close()
		index.append(String(id))
		print("layout_dump: %s -> %s (%d things)" % [id, ProjectSettings.globalize_path(path), data["things"].size()])
	var f := FileAccess.open("%s/index.json" % _out_dir, FileAccess.WRITE)
	f.store_string(JSON.stringify(index))
	f.close()
	studio.queue_free()
	await get_tree().process_frame
	Session.layout = saved_layout
	get_tree().quit()


func _dump(studio: Studio, variant: int) -> Dictionary:
	var venue := studio.venue
	var walk := studio._walkable()
	var out := {
		"venue": String(venue.venue_id()),
		"title": venue.title(),
		"variant": variant,
		"variants": Array(Venue.variant_titles(venue.venue_id())),
		"room_width": studio.room_width,
		"room_depth": Studio.ROOM_DEPTH,
		"room_front": Studio.ROOM_FRONT,
		"room_back": Studio.ROOM_BACK,
		"wall_height": Studio.WALL_HEIGHT,
		"live_room_back": Venue.LIVE_ROOM_BACK,
		"live_room_half": venue.live_room_half(),
		"control_room": _rect(studio._room_bounds()),
		"floor_plan_bounds": _rect(studio.floor_plan.bounds),
		"floor_plan_rooms": studio.floor_plan.rooms.map(_rect),
		"walkable": walk.map(_rect),
		"walls": Walker.outline(walk).map(func(e: Array) -> Array:
			return [_v2(e[0]), _v2(e[1]), _v2(e[2])]),
		"zones": {},
		"venue_transform_is_identity": venue.transform.is_equal_approx(Transform3D.IDENTITY),
		"set_transform_is_identity": studio.studio_set.transform.is_equal_approx(Transform3D.IDENTITY),
	}
	var area := 0.0
	for r: Rect2 in walk:
		area += r.get_area()
	out["walkable_area_sum"] = area
	out["walkable_area_union"] = _union_area(walk)
	for z: StringName in venue.zones():
		var b: AABB = venue.zones()[z]
		out["zones"][String(z)] = {"rect": [b.position.x, b.position.z, b.size.x, b.size.z], "height": b.size.y}

	# The seat and the desk.
	var desk := studio._desk_footprint()
	out["seat"] = {"at": [0.0, Studio.MIX_POSITION_Z], "eye": studio.ergonomics.eye_height,
			"walker_at": _v3xz(studio.walker.global_position), "fov": Studio.ROOM_FOV,
			"seated_fov": Studio.SEATED_FOV}
	var things: Array = []
	if not desk.is_empty():
		things.append(_thing("console", "Console (desk)", "fixed", desk[0], &"", 1.0, studio))

	# The floor plan's pieces: every trolley, the gear's and the live room's.
	for piece in studio.floor_plan.pieces:
		if not is_instance_valid(piece) or not piece.is_inside_tree():
			continue
		var t := piece as Trolley
		var at := Vector2(t.position.x, t.position.z)
		var fp: Dictionary = t.footprint_at(at, t.rotation.y)
		var thing := _thing(String(t.piece_id), String(t.name), "trolley", fp, &"", -1.0, studio)
		thing["visible"] = t.visible
		thing["walk_through"] = t.walk_through
		thing["origin"] = _v2(at)
		thing["heading_deg"] = rad_to_deg(t.rotation.y)
		thing["mesh"] = _measure(t)
		things.append(thing)

	# The venue's own solids, by where each comes from.
	var labelled := []
	var sources := {
		"zone": venue.zone_solids(),
		"instrument": venue.instrument_solids(),
		"weather": venue.weather_solids(),
		"door": [venue.door_solid()],
		"wheeled": venue.wheeled_solids(),
	}
	var used := {}
	var all_solids: Array = venue.solids()
	for i in all_solids.size():
		var s: Dictionary = all_solids[i]
		var from := "venue"
		for key in sources:
			if (sources[key] as Array).has(s):
				from = key
				break
		var label := String(s.get("station", ""))
		if label == "":
			label = from
			if from == "zone":
				for z: StringName in venue.zones():
					var b: AABB = venue.zones()[z]
					if Rect2(b.position.x - 0.05, b.position.z - 0.05, b.size.x + 0.1, b.size.z + 0.1).has_point(s["c"]):
						label = "zone:%s" % z
						break
		var thing := _thing("solid_%d" % i, label, "fixed", s, &"", float(s.get("top", Walker.SOLID_HEIGHT)), studio)
		thing["source"] = from
		things.append(thing)

	# Stations: spot, seat, footprint, and how each is stood.
	var stations := []
	for sid: StringName in Stations.ids(venue):
		var r := Stations.row(sid)
		var spot: Transform3D = Stations.spot(venue, sid)
		var seat: Variant = Stations.seat(venue, sid, studio.walker.fits)
		var kind := "fixed"
		if Venue.WHEELED.has(sid) or r.has("surface") and not Stations.zoned(sid):
			kind = "trolley"
		elif r.has("cart"):
			kind = "on-cart"
		elif Stations.zoned(sid):
			kind = "zone-mounted"
		elif sid == VenueInstrument.STATION or sid == Weather.STATION:
			kind = "venue-mounted"
		var entry := {
			"id": String(sid), "title": String(Stations.row_in(venue, sid).get("title", r.get("title", ""))),
			"area": String(r.get("area", "")), "zone": String(r.get("zone", "")), "kind": kind,
			"at": _v3xz(spot.origin), "y": spot.origin.y, "heading_deg": rad_to_deg(spot.basis.get_euler().y),
			"seat": _v3xz((seat as Transform3D).origin) if seat != null else null,
			"seat_dist_from_desk_seat": Vector2((seat as Transform3D).origin.x, (seat as Transform3D).origin.z).distance_to(Vector2(0, Studio.MIX_POSITION_Z)) if seat != null else null,
			"air": r.get("air", 0.0),
		}
		var solid := Stations.solid(venue, sid)
		if not solid.is_empty():
			entry["footprint"] = _fp(solid)
		entry["in"] = _where(studio, Vector2(spot.origin.x, spot.origin.z))
		stations.append(entry)
	out["stations"] = stations

	# The room's items at home.
	var items := []
	if studio.items != null:
		for iid in studio.items.items:
			var it := studio.items.items[iid] as Node3D
			if it == null or not is_instance_valid(it):
				continue
			var home: Transform3D = it.get(&"home") if it.get(&"home") != null else it.global_transform
			var p := Vector2(home.origin.x, home.origin.z)
			items.append({"id": String(iid), "kind": "item", "at": _v2(p), "y": home.origin.y,
					"visible": it.visible, "in": _where(studio, p)})
	out["items"] = items

	# The surfaces on the set (the console, rack, deck, patchbay, timeline, stage table, EQ wall,
	# the modular wall), with what their meshes measure.
	var surfaces := []
	for child in studio.studio_set.get_children():
		if child is Surface:
			var s := child as Surface
			surfaces.append({"id": String(s.surface_id), "name": String(s.name), "visible": s.visible,
					"origin": _v3xz(s.global_position), "y": s.global_position.y,
					"heading_deg": rad_to_deg(s.global_rotation.y), "mesh": _measure(s)})
	out["surfaces"] = surfaces
	# The rest of the set that is neither a surface nor a trolley: the roll board, the Rig Roulette
	# station, the tour case, the items' room, tablets.
	var set_other := []
	for child in studio.studio_set.get_children():
		if child is Surface or child is Trolley or not child is Node3D:
			continue
		var n := child as Node3D
		var m := _measure(n)
		if m.is_empty():
			continue
		set_other.append({"name": String(n.name), "origin": _v3xz(n.global_position),
				"heading_deg": rad_to_deg(n.global_rotation.y), "mesh": m,
				"in": _where(studio, Vector2(n.global_position.x, n.global_position.z)),
				"near_wall": _near_wall(walk, Vector2(n.global_position.x, n.global_position.z))})
	out["set_other"] = set_other

	# The venue's own top-level dressing: what it is, where, and how big on the floor.
	var dressing := []
	for child in venue.get_children():
		if not child is Node3D:
			continue
		var n := child as Node3D
		var m := _measure(n)
		if m.is_empty():
			continue
		var kind := "dressing"
		var w: float = m["world"][2]
		var d: float = m["world"][3]
		if w > 14.0 or d > 14.0:
			kind = "scenery"
		dressing.append({"name": String(n.name), "kind": kind, "class": n.get_class() if n.get_script() == null else String(n.get_script().get_global_name()),
				"origin": _v3xz(n.global_position), "heading_deg": rad_to_deg(n.global_rotation.y), "mesh": m,
				"in": _where(studio, Vector2(n.global_position.x, n.global_position.z)),
				"near_wall": _near_wall(walk, Vector2(n.global_position.x, n.global_position.z))})
	out["dressing"] = dressing
	out["things"] = things
	for t: Dictionary in things:
		t["in"] = _where(studio, Vector2(t["c"][0], t["c"][1]))
	return out


func _thing(id: String, label: String, kind: String, fp: Dictionary, _zone: StringName, top: float, _studio: Studio) -> Dictionary:
	var d := _fp(fp)
	d["id"] = id
	d["name"] = label
	d["kind"] = kind
	if top >= 0.0:
		d["top"] = top
	return d


func _fp(fp: Dictionary) -> Dictionary:
	var c: Vector2 = fp["c"]
	var h: Vector2 = fp["h"]
	var a: float = fp["a"]
	# Corners as FloorPlan has them: local +X -> (cos a, -sin a), local +Z -> (sin a, cos a).
	var ax := Vector2(cos(a), -sin(a))
	var az := Vector2(sin(a), cos(a))
	var corners := []
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(_v2(c + ax * h.x * s.x + az * h.y * s.y))
	return {"c": _v2(c), "h": _v2(h), "heading_deg": rad_to_deg(a), "corners": corners,
			"top": fp.get("top", -1.0)}


## A node's visible meshes, measured: the world AABB on the floor [x, z, w, d] and its top, and the
## box in its own frame (an oriented footprint at its heading).
func _measure(n: Node3D) -> Dictionary:
	var world := AABB()
	var local := AABB()
	var any := false
	var inv := n.global_transform.affine_inverse()
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is Node3D and not (c as Node3D).visible:
			continue
		stack.append_array(c.get_children())
		if c is VisualInstance3D and not c is Light3D and not c is GPUParticles3D and not c is ReflectionProbe:
			var vi := c as VisualInstance3D
			var box := vi.get_aabb()
			if box.size == Vector3.ZERO:
				continue
			var g := vi.global_transform * box
			var l := (inv * vi.global_transform) * box
			if not any:
				world = g
				local = l
				any = true
			else:
				world = world.merge(g)
				local = local.merge(l)
	if not any:
		return {}
	return {"world": [world.position.x, world.position.z, world.size.x, world.size.z], "top": world.end.y,
			"bottom": world.position.y,
			"local": [local.position.x, local.position.z, local.size.x, local.size.z]}


func _where(studio: Studio, p: Vector2) -> String:
	var venue := studio.venue
	for z: StringName in venue.zones():
		var b: AABB = venue.zones()[z]
		if Rect2(b.position.x, b.position.z, b.size.x, b.size.z).has_point(p):
			return "zone:%s" % z
	if studio._room_bounds().has_point(p):
		return "control_room"
	var rooms := venue.rooms()
	for i in rooms.size():
		if rooms[i].has_point(p):
			return "back_of_house" if rooms[i] == venue.back_of_house() else "room_%d" % i
	return "off_floor"


func _near_wall(walk: Array[Rect2], p: Vector2) -> float:
	var best := INF
	for e in Walker.outline(walk):
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p))
	return best


func _union_area(rects: Array[Rect2]) -> float:
	var xs: Array[float] = []
	var zs: Array[float] = []
	for r in rects:
		xs.append_array([r.position.x, r.end.x])
		zs.append_array([r.position.y, r.end.y])
	xs.sort()
	zs.sort()
	var area := 0.0
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var mid := Vector2((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5)
			if rects.any(func(r: Rect2) -> bool: return r.has_point(mid)):
				area += (xs[i + 1] - xs[i]) * (zs[j + 1] - zs[j])
	return area


func _rect(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


func _v2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]


func _v3xz(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.z, 0.001)]
