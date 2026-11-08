extends RefCounted

## The new-room maker (docs/layouts.md section 11 step 11, called from the `_test_*` wrappers in
## tests/run_tests.gd): a made room is layout data that validates and loads, pieces are of two classes,
## the limits hold, and the brief's proof: make a new room, restart with a fresh Studio and it is there,
## and a guest sees it. In-process the host and the guest share the static registry, so the guest's
## machine is a registry that has none of the host's files before the row is applied.

const HOST_DIR := "user://test_made_host/"
const GUEST_DIR := "user://test_made_guest/"

var t: Node
var share


func _init(runner: Node) -> void:
	t = runner
	share = t.LayoutShareTests.new(runner)


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## Real files in a folder of the test's own.
func _live(dir: String) -> void:
	_clean(dir)
	MadeRooms.disabled = false
	MadeRooms.dir_override = dir
	LiveRoom.reset()


func _off() -> void:
	MadeRooms.drop_adopted()
	MadeRooms.disabled = true
	MadeRooms.dir_override = ""
	_clean(HOST_DIR)
	_clean(GUEST_DIR)
	LiveRoom.reset()


func _clean(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da != null:
		for f in da.get_files():
			da.remove(f)
	else:
		DirAccess.make_dir_recursive_absolute(dir)


## Every subset of `ids`.
func _subsets(ids: Array[StringName]) -> Array:
	var out: Array = []
	for mask in 1 << ids.size():
		var one: Array = []
		for i in ids.size():
			if mask & (1 << i):
				one.append(String(ids[i]))
		out.append(one)
	return out


## A spec keeping `zones`, every single that has its zone, and the annex or not.
func _spec(size: StringName, zones: Array, annex := true, title := "Test room") -> Dictionary:
	var pieces: Array = []
	for kind in PieceCatalogue.maker_kinds():
		if not MadeRoom.NEEDS.has(kind) or String(MadeRoom.NEEDS[kind]) in zones:
			pieces.append(String(kind))
	return {"title": title, "size": String(size), "style": "warm", "zones": zones, "pieces": pieces, "annex": annex}


func validates_and_loads() -> void:
	_live(HOST_DIR)
	# Every size with every subset of the zones that fit it makes a room that validates with no error.
	var rooms := 0
	var failed: Array = []
	for size in MadeRoom.SIZES:
		for zones: Array in _subsets(MadeRoom.zones_fitting(size)):
			for annex in [true, false]:
				if not annex and zones.size() > 1:
					continue
				var made := MadeRoom.build(_spec(size, zones, annex), "probe")
				rooms += 1
				if not made["ok"]:
					failed.append("%s %s annex=%s: %s" % [size, zones, annex, made["errors"]])
	check("%d sizes x zone subsets all validate (%s)" % [rooms, failed.slice(0, 3)], rooms > 60 and failed.is_empty())
	check("the small room fits only some zones, the standard all five", MadeRoom.zones_fitting(&"small").size() < 5
			and MadeRoom.zones_fitting(&"standard").size() == 5 and MadeRoom.zones_fitting(&"large").size() == 5)
	check("a zone that does not fit the size is refused", not MadeRoom.problems(_spec(&"small", ["vocals"])).is_empty())
	check("a piece without its zone is refused", not MadeRoom.problems({"title": "x", "size": "standard", "style": "warm",
			"zones": ["drums"], "pieces": ["wheel"], "annex": false}).is_empty())
	check("a room with no name, or an unknown size or look, is refused", not MadeRoom.problems(_spec(&"standard", ["drums"], true, "")).is_empty()
			and not MadeRoom.problems(_spec(&"huge", [])).is_empty()
			and not MadeRoom.problems({"title": "x", "size": "standard", "style": "plaid", "zones": [], "pieces": [], "annex": false}).is_empty())

	# It is stored as layout data, found by the catalogue, and built as a BoxVenue of the file's size.
	var spec := _spec(&"large", ["drums", "bricks", "synth"], true, "Big Room!")
	var made := MadeRooms.make(spec)
	var id := StringName(made["id"])
	check("the maker answers the id and writes the file (%s)" % [made["errors"]], made["ok"] and id == &"big-room" and FileAccess.file_exists(HOST_DIR + "big-room.layout.json"))
	check("a second room of the same name is told apart", MadeRooms.make(spec)["id"] == "big-room-2")
	LiveRoom.reset()
	check("after a restart of the scan the room is there, a BoxVenue, with its title", MadeRooms.has(id) and VenueCatalogue.builder_of(id) == "BoxVenue"
			and VenueCatalogue.title_of(id) == "Big Room!" and Venue.is_known(id))
	check("it is not one of the cycled venues", id not in VenueCatalogue.ids())
	var venue := Venue.make(id, 0)
	check("Venue.make builds it: its size, look and zones", venue is BoxVenue and (venue as BoxVenue).room_size == &"large"
			and (venue as BoxVenue).zone_ids.size() == 3 and &"synth" in (venue as BoxVenue).zone_ids)
	check("a large room is wider than a standard one, a small one narrower", (venue as BoxVenue).live_room_half() > Venue.LIVE_ROOM_HALF
			and (Venue.make(&"studio") as Venue).live_room_half() == Venue.LIVE_ROOM_HALF)
	check("only the zones kept are the room's", venue.zones().keys().size() == 3 and not venue.zones().has(&"vocals") and not venue.zones().has(&"matrix"))
	check("it has the modular room", venue.has_annex() and venue.modular_spot() != null)
	venue.free()
	var bare := MadeRooms.make(_spec(&"small", ["drums"], false, "Closet"))
	var closet := Venue.make(StringName(bare["id"]), 0)
	check("a room made without the modular room has none", bare["ok"] and not closet.has_annex() and closet.modular_spot() == null
			and not closet.walk_rooms().any(func(r: Rect2) -> bool: return r.position.x > closet.live_room_half()))
	closet.free()
	var resolved := LiveRoom.layout(id, 0)
	check("its resolved layout has the live room's pieces, the unticked ones switched off and the annex in", resolved.status == LayoutData.STATUS_OK
			and not resolved.piece(&"drums").is_empty() and not resolved.piece(&"wheel").is_empty() and not resolved.piece(&"sampler").is_empty()
			and resolved.piece(&"lyrics").is_empty() and not resolved.piece(&"modular_annex").is_empty())
	check("every code of the validator still has its seeded case", LayoutIssue.CODES.size() == 17)

	# Pieces are of two classes, and the class is the piece's.
	check("a single item is a single, the modular annex room-scale", PieceDef.class_of(&"hoop") == "single" and PieceDef.class_of(&"modular_annex") == "room_scale"
			and PieceDef.room_scale(&"modular_annex") and not PieceDef.room_scale(&"wheel"))
	check("the annex is the only room-scale piece, it has a builder, and a limit of one", PieceDef.ids().all(func(p: StringName) -> bool: return not PieceDef.room_scale(p))
			and PieceBuilders.can_build(&"modular_annex") and PieceFeet.limit(&"modular_annex") == 1 and PieceFeet.limit(&"hoop") == 0)
	check("the annex's claims come from its def; a single claims no site", PieceFeet.claims(&"modular_annex", 8.8).has("site") and PieceFeet.claims(&"hoop", 8.8).is_empty())
	check("every single the maker offers is of class single", PieceCatalogue.kinds().all(func(k: StringName) -> bool: return PieceDef.class_of(k) == "single"))
	check("the annex is refused among the single pieces", not MadeRoom.problems({"title": "x", "size": "standard", "style": "warm", "zones": [],
			"pieces": ["modular_annex"], "annex": false}).is_empty())
	var dict := MadeRoom.layout_dict(_spec(&"standard", ["drums"]), "probe")
	dict["pieces"][0]["class"] = "single"
	check("a layout that states a class of its own is refused", not LayoutData.parse(dict).errors().is_empty())
	dict = MadeRoom.layout_dict(_spec(&"standard", ["drums"]), "probe")
	var wheeled: Dictionary = (dict["pieces"] as Array).back()
	wheeled["mobility"] = "wheeled"
	check("a room-scale piece given wheels is refused", not LayoutData.parse(dict).errors().is_empty())

	# The limits: 64 pieces, 16 kB.
	dict = MadeRoom.layout_dict(_spec(&"standard", ["drums"]), "probe")
	for i in 70:
		(dict["pieces"] as Array).append({"id": "hoop_%d" % (i + 2), "piece": "hoop", "at": {"pos": [0.0, 6.0], "yaw": 0.0}})
	check("more than 64 pieces is refused", not MadeRoom.validate(dict).is_empty())
	dict = MadeRoom.layout_dict(_spec(&"standard", ["drums"]), "probe")
	dict["note"] = "x".repeat(MadeRoom.MAX_BYTES)
	check("a row over 16 kB is not taken", not MadeRooms.adopt(dict))
	check("a row naming a shipped room's id is not taken", not MadeRooms.adopt(MadeRoom.layout_dict(_spec(&"standard", ["drums"]), "studio")))
	_off()


## The brief's proof: make a new room, restart with a fresh Studio and it is where the band left it,
## and a guest sees it.
func persists_and_a_guest_sees_it() -> void:
	_live(HOST_DIR)
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var spec := _spec(&"standard", ["drums", "matrix", "bricks"], true, "Proof Room")
	spec["pieces"].erase("hoop")
	spec["pieces"].erase("cassette_rack")
	var made := MadeRooms.make(spec)
	check("the maker makes the room (%s)" % [made["errors"]], made["ok"])
	var id := StringName(made["id"])
	check("the host takes the band into it", s.venue_switch.choose_venue(id) and s.venue is BoxVenue and s.venue.venue_id() == id)
	check("the room has its zones, the wheel in the table's zone, no sampler (no keyboard zone), no rack", s.venue.zones().size() == 3 and s.wheel != null
			and s.sampler == null and s.cassette_rack == null and s.venue.get_node_or_null("ModularAnnex") != null)
	check("and no basket: the hoop was unticked", not s.live_pieces.has(&"hoop") or not s.live_pieces[&"hoop"].visible)
	check("the session remembers the room", Session.layout.venue == id)

	# A restart: the scan is read from disk again, and a fresh Studio opens on the layout profile.
	LiveRoom.reset()
	(rig["hand"] as Node).free()
	t.remove_child(s)
	s.free()
	var again := Studio.new()
	again.medium = Presentation.Medium.SCREEN
	t.add_child(again)
	check("restarted: the fresh studio is in the made room, from its file", again.venue is BoxVenue and again.venue.venue_id() == id
			and again.venue.zones().size() == 3 and again.wheel != null and again.sampler == null)

	# A guest, on a machine that has none of the host's files.
	var guest_rig: Dictionary = t._floor_studio()
	var guest: Studio = guest_rig["studio"]
	var state: Dictionary = share._as(Session.Role.HOST, func() -> Variant: return again.room_rows.room_state())
	check("the host's row carries the room, within 16 kB", state["made_room"].get("id") == String(id)
			and JSON.stringify(state["made_room"]).to_utf8_buffer().size() <= MadeRoom.MAX_BYTES)
	_live(GUEST_DIR)
	check("the guest's machine has no such room", not MadeRooms.has(id) and not Venue.is_known(id))
	share._as(Session.Role.GUEST, func() -> Variant:
		guest.room_rows.apply_room(state, false)
		return null)
	check("the guest stands in the host's made room", guest.venue is BoxVenue and guest.venue.venue_id() == id and guest.venue.zones().size() == 3
			and guest.wheel != null and guest.sampler == null)
	check("the guest wrote no file of its own", DirAccess.get_files_at(GUEST_DIR).is_empty())
	check("the guest does not keep it in its own list", MadeRooms.own_ids().is_empty())
	MadeRooms.drop_adopted()
	check("it goes with the host's room", not MadeRooms.has(id))

	var keep: LayoutProfile = guest_rig["saved_layout"]
	t._drop_floor_studio(guest_rig)
	t.remove_child(again)
	again.free()
	Session.layout = rig["saved_layout"]
	if keep != null and FileAccess.file_exists(keep.save_path) and keep.save_path.begins_with("user://test_"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(keep.save_path))
	_off()
