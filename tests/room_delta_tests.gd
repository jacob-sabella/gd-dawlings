extends RefCounted

## The per-room delta (docs/layouts.md section 11 step 8), called from the `_test_*` wrappers in
## tests/run_tests.gd: the delta as data and over the defaults, its file, the studio keeping it per room
## and reloading it, a bad or oversized file, a guest adopting the host's `layout` row, and the one
## import of the saved `floor/*` spots. Files go to a folder of the test's own, never the player's.

const DIR := "user://test_rooms/"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _clean() -> void:
	var da := DirAccess.open(DIR)
	if da != null:
		for f in da.get_files():
			da.remove(f)
	else:
		DirAccess.make_dir_recursive_absolute(DIR)


## Real files in a folder of the test's own for as long as a test runs.
func _live() -> void:
	_clean()
	RoomDeltas.disabled = false
	RoomDeltaFile.dir_override = DIR


func _off() -> void:
	RoomDeltas.disabled = true
	RoomDeltaFile.dir_override = ""
	_clean()


func _body() -> Dictionary:
	return LiveRoom.layout(&"studio", 0).body


## A delta of 64 added pieces, each with a long note: past 16 kB.
func _padded() -> RoomDelta:
	var pad := RoomDelta.empty(&"studio", 0)
	for n in 60:
		pad.added.append({"id": "extra_%d" % n, "piece": "hoop", "at": {"pos": [0.5, 0.5], "yaw": 0.0}, "note": "x".repeat(300)})
	return pad


func _put(name: String, text: String) -> String:
	var path := DIR + name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


## Round trip, over the defaults, the limits and the flags.
func data() -> void:
	var body := _body()
	var empty := RoomDelta.empty(&"studio", 0)
	var applied := empty.apply(body)
	check("an empty delta applied over the defaults is the defaults", applied["ok"] and applied["pieces"] == body["pieces"]
			and applied["groups"] == body["groups"] and applied["wiring"] == body["wiring"] and applied["flagged"].is_empty())
	check("it is empty, and its room is studio.0", empty.is_empty() and empty.room == "studio.0")

	var d := RoomDelta.empty(&"studio", 0)
	d.move(&"hoop", 1.23456, -2.5, 0.75)
	d.removed.append("cassette_rack")
	d.added.append({"id": "extra_hoop", "piece": "hoop", "at": {"pos": [0.5, 0.5], "yaw": 0.0}})
	d.added.append({"id": "from_a_mod", "piece": "mod.gong", "at": {"pos": [1.0, 1.0], "yaw": 0.0}, "footprint": [0.3, 0.3]})
	d.move(&"lamp_2", 1.0, 1.0, 0.0)
	d.move(&"ghost_piece", 3.0, 3.0, 0.0)
	d.removed.append("ghost_two")
	var parsed: Variant = JSON.parse_string(d.text())
	check("a delta is a file that parses back as the same delta", RoomDelta.problem(parsed) == "" and RoomDelta.from_dict(parsed).to_dict() == d.to_dict())
	check("the same delta is always the same text", d.text() == RoomDelta.from_dict(parsed).text())
	check("a moved spot is kept to a tenth of a millimetre", d.moved["hoop"] == [1.2346, -2.5, 0.75])
	check("a row has no format, a file has", not d.to_dict(false).has("format") and d.to_dict()["format"] == RoomDelta.FORMAT)

	var out := d.apply(body)
	var at := {}
	for p: Dictionary in out["pieces"]:
		at[p["id"]] = p
	check("a moved piece stands at its spot, whatever it was placed against", at["hoop"]["at"]["pos"] == [1.2346, -2.5]
			and at["hoop"]["at"]["yaw"] == 0.75 and not at["hoop"]["at"].has("anchor") and not at["hoop"]["at"].has("frame"))
	check("a removed piece is gone", not at.has("cassette_rack"))
	check("with the group members and wires that named it", out["groups"].all(func(g: Dictionary) -> bool: return "cassette_rack" not in g["members"])
			and out["wiring"].all(func(w: Dictionary) -> bool: return w["from"] != "cassette_rack" and w["to"] != "cassette_rack"))
	check("an added piece is appended", at.has("extra_hoop") and not at["extra_hoop"].has("unavailable"))
	check("one nobody has a definition for is kept and marked unavailable", at.has("from_a_mod") and at["from_a_mod"]["unavailable"] == true
			and at["from_a_mod"]["footprint"] == [0.3, 0.3])
	var codes: Array = out["flagged"].map(func(f: Dictionary) -> String: return "%s:%s" % [f["code"], f["id"]])
	check("what the room cannot make sense of is flagged, not dropped (%s)" % [codes],
			codes.size() == 3 and "unavailable_piece:from_a_mod" in codes and "unknown_piece:ghost_piece" in codes and "unknown_piece:ghost_two" in codes)
	check("and stays in the delta", d.moved.has("ghost_piece") and "ghost_two" in d.removed and RoomDelta.from_dict(parsed).moved.has("ghost_piece"))
	check("a lamp, which the code places, is no stranger", not codes.any(func(c: String) -> bool: return "lamp_2" in c))
	check("the defaults are left alone", body["pieces"] == _body()["pieces"] and body["pieces"].any(func(p: Dictionary) -> bool: return p["id"] == "cassette_rack"))

	var twice := RoomDelta.empty(&"studio", 0)
	twice.added.append({"id": "hoop", "piece": "hoop", "at": {"pos": [0.0, 0.0], "yaw": 0.0}})
	check("an added piece with the id of one the room has is flagged and the room's own wins",
			twice.apply(body)["flagged"][0]["code"] == &"duplicate_piece" and twice.apply(body)["pieces"].size() == body["pieces"].size())
	var crowd := RoomDelta.empty(&"studio", 0)
	for n in 70:
		crowd.added.append({"id": "extra_%d" % n, "piece": "hoop", "at": {"pos": [0.0, 0.0], "yaw": 0.0}})
	var over := crowd.apply(body)
	check("more than the room's limit of pieces is refused and the room stays at its defaults", not over["ok"]
			and over["pieces"] == body["pieces"] and over["flagged"].any(func(f: Dictionary) -> bool: return f["code"] == &"over_limit"))
	check("and a file with more than 64 added is not a delta", RoomDelta.problem(crowd.to_dict()) != "")

	var mended := RoomDelta.from_dict({"format": RoomDelta.FORMAT, "version": 1, "base": "studio", "variant": "x",
			"moved": {"rack": [1, 2, 3], "bad": "no", "short": [1, 2], "Bad Id": [0, 0, 0], "inf": [INF, 0, 0]},
			"added": [5, {"id": "a"}, {"id": "ok", "piece": "hoop", "at": {"pos": [1, 2]}}], "removed": ["tv", 7, "tv"]})
	check("wrong shapes are mended and the readable entries kept", mended.moved.keys() == ["rack"] and mended.added.size() == 1
			and mended.removed == ["tv"] and mended.variant == 0)
	check("a delta from a newer game or another format is refused", RoomDelta.problem({"version": 99}) != ""
			and RoomDelta.problem({"format": "dawlings.layout"}) != "" and RoomDelta.problem([1]) != "" and RoomDelta.problem(null) != "")
	var pad := _padded()
	check("a delta over 16 kB does not fit", not pad.fits() and RoomDelta.empty(&"studio", 0).fits())


## The file: atomic write with a .bak, a bad main file rescued by it, nothing thrown at a bad one.
func files() -> void:
	_clean()
	var path := DIR + "studio.0.delta.json"
	var d := RoomDelta.empty(&"studio", 0)
	d.move(&"rack", -1.0, 0.5, 0.25)
	check("a delta writes", RoomDeltaFile.write(path, d) == OK and FileAccess.file_exists(path))
	var got := RoomDeltaFile.read(path)
	check("and reads back", got["ok"] and got["delta"].to_dict() == d.to_dict())
	d.move(&"rack", -2.0, 0.5, 0.25)
	RoomDeltaFile.write(path, d)
	check("the file it replaces is kept as .bak", FileAccess.file_exists(path + ".bak") and RoomDeltaFile.read(path + ".bak")["delta"].moved["rack"][0] == -1.0)
	_put("studio.0.delta.json", "{broken")
	var rescued := RoomDeltaFile.read(path)
	check("a main file that does not read falls back to the .bak", rescued["ok"])
	check("no file is no problem, only missing", RoomDeltaFile.read(DIR + "none.delta.json")["missing"])
	var junk := RoomDeltaFile.read(_put("junk.delta.json", "{{{"))
	check("junk is not JSON", not junk["ok"] and not junk["missing"] and junk["error"] == "not JSON")
	var big := _put("big.delta.json", JSON.stringify({"format": RoomDelta.FORMAT, "version": 1, "pad": "x".repeat(20000)}))
	check("a file over 16 kB is not read", RoomDeltaFile.read(big)["error"] == "file too large")
	check("another format is not read", not RoomDeltaFile.read(_put("o.delta.json", '{"format": "dawlings.layout"}'))["ok"])
	var pad := _padded()
	check("an over-size delta is not written", RoomDeltaFile.write(DIR + "pad.delta.json", pad) != OK and not FileAccess.file_exists(DIR + "pad.delta.json"))
	check("a delta file is never taken for a layout file", not (DIR + "studio.0.delta.json").ends_with(LayoutSet.SUFFIX))
	_clean()


## Pushed in the studio, written a moment later, reloaded by a fresh studio, and kept per room.
func persistence() -> void:
	_live()
	var rig: Dictionary = t._floor_studio()
	var studio: Studio = rig["studio"]
	studio.room_deltas.delay = 0.05
	var rack := studio.rack_trolley
	var home := Vector2(rack.position.x, rack.position.z)
	rack.place(home + Vector2(-0.3, 0.2), 0.4)
	studio._on_trolley_settled(rack)
	var hoop: Trolley = studio.live_pieces[&"hoop"]
	var hoop_home := Vector2(hoop.position.x, hoop.position.z)
	hoop.place(hoop_home + Vector2(0.4, 0.4), 1.0)
	studio._on_trolley_settled(hoop)
	check("a settled piece is the room's moved piece", studio.room_deltas.delta.moved.has("rack") and studio.room_deltas.delta.moved.has("hoop"))
	var rack_at := Vector2(rack.position.x, rack.position.z)
	var path := RoomDeltaFile.path_of("studio.0")
	check("nothing is written at once", not FileAccess.file_exists(path))
	await t.get_tree().create_timer(0.3).timeout
	studio.room_deltas.wait()
	check("the pause then writes the file for studio.0 (%s)" % path, FileAccess.file_exists(path) and studio.room_deltas.writes == 1)
	var first := FileAccess.get_file_as_string(path)
	studio.room_deltas.settle(&"rack", rack.transform, false, null)
	studio.room_deltas.flush()
	check("a piece left where it is does not write again", studio.room_deltas.writes == 1 and FileAccess.get_file_as_string(path) == first)

	studio.set_venue(&"rooftop", false, 0)
	check("another room has its own delta, empty", studio.room_deltas.delta.room == "rooftop.0" and studio.room_deltas.delta.moved.is_empty()
			and not FileAccess.file_exists(RoomDeltaFile.path_of("rooftop.0")))
	var hoop_roof := Vector2(hoop.position.x, hoop.position.z)
	check("and the hoop is not where the studio left it", hoop_roof.distance_to(hoop_home + Vector2(0.4, 0.4)) > 0.1)
	studio.set_venue(&"studio", false, 0)
	check("back in the studio the hoop is where it was left", studio.room_deltas.delta.moved.has("hoop"))
	t._drop_floor_studio(rig)

	var rig2: Dictionary = t._floor_studio()
	var fresh: Studio = rig2["studio"]
	check("a fresh studio finds the room as it was left", fresh.room_deltas.delta.moved.has("rack")
			and Vector2(fresh.rack_trolley.position.x, fresh.rack_trolley.position.z).distance_to(rack_at) < 0.01)
	check("the hoop too", fresh.room_deltas.delta.moved.has("hoop"))
	var back := fresh.rack_trolley
	fresh.room_deltas.settle(&"rack", back.transform, true, null)
	fresh.room_deltas.flush()
	check("a piece put back where the room stands it is forgotten, and the file says so",
			not RoomDeltaFile.read(path)["delta"].moved.has("rack") and RoomDeltaFile.read(path)["delta"].moved.has("hoop"))
	t._drop_floor_studio(rig2)
	_off()


## A file nobody can use leaves the room as it is made, is set aside, and the studio builds.
func a_bad_file_degrades() -> void:
	for kind in ["junk", "big", "newer"]:
		_live()
		var text := "{{{"
		if kind == "big":
			text = JSON.stringify({"format": RoomDelta.FORMAT, "version": 1, "room": "studio.0", "pad": "x".repeat(20000)})
		elif kind == "newer":
			text = JSON.stringify({"format": RoomDelta.FORMAT, "version": 7, "moved": {"rack": [0, 0, 0]}})
		_put("studio.0.delta.json", text)
		var rig: Dictionary = t._floor_studio()
		var studio: Studio = rig["studio"]
		check("%s: the studio builds with the room at its defaults" % kind, studio.rack_trolley != null and studio.room_deltas.delta.is_empty()
				and studio.room_deltas.applied["pieces"] == _body()["pieces"])
		check("%s: and says why, and sets the file aside" % kind, studio.room_deltas.last_problem != ""
				and FileAccess.file_exists(DIR + "studio.0.delta.json.bad") and not FileAccess.file_exists(DIR + "studio.0.delta.json"))
		t._drop_floor_studio(rig)
	_off()


## A guest follows the host's `layout` row and writes nothing of its own.
func a_guest_adopts_the_hosts_row() -> void:
	_live()
	var rig: Dictionary = t._floor_studio()
	var host: Studio = rig["studio"]
	host.room_deltas.delay = 0.05
	var rack := host.rack_trolley
	var rack_home := Vector2(rack.position.x, rack.position.z)
	rack.place(rack_home + Vector2(-0.4, 0.3), 0.5)
	host._on_trolley_settled(rack)
	var row: Dictionary = host.room_state()["layout"]
	check("the host's row is its delta with the pushed rack in it", row["moved"].has("rack") and row["room"] == "studio.0" and row["rev"] > 0
			and RoomDelta.problem(row) == "")
	var at := Vector2(rack.position.x, rack.position.z)
	var state := host.room_state()
	host.room_deltas.flush()
	var file := FileAccess.get_file_as_string(RoomDeltaFile.path_of("studio.0"))
	t._drop_floor_studio(rig)

	_clean()
	var rig2: Dictionary = t._floor_studio()
	var guest: Studio = rig2["studio"]
	var kept_role := Session.role
	Session.role = Session.Role.GUEST
	guest.apply_room(state, false)
	check("the guest's rack is where the host's is", Vector2(guest.rack_trolley.position.x, guest.rack_trolley.position.z).distance_to(at) < 0.01)
	check("it is following the host's room, which it did not read from a file", guest.room_deltas.following and guest.room_deltas.delta.moved.has("rack"))
	guest.room_deltas.settle(&"rack", guest.rack_trolley.transform, false, null)
	guest.room_deltas.flush()
	guest.room_deltas.wait()
	check("a guest never writes a room file", guest.room_deltas.writes == 0 and not FileAccess.file_exists(RoomDeltaFile.path_of("studio.0")))
	var back := state.duplicate(true)
	back["layout"]["moved"].erase("rack")
	back["layout"]["rev"] += 1
	guest.apply_room(back, false)
	check("a piece the host put back goes back to where the room stands it",
			Vector2(guest.rack_trolley.position.x, guest.rack_trolley.position.z).distance_to(Vector2(RoomFloor.default_of(guest, &"rack").origin.x, RoomFloor.default_of(guest, &"rack").origin.z)) < 0.01)
	guest.apply_room({"venue": &"studio", "variant": 0, "layout": "junk"}, false)
	check("a row that is not a delta changes nothing", guest.room_deltas.following and guest.room_deltas.delta.rev == back["layout"]["rev"])
	Session.role = kept_role
	check("the host's file is as the host wrote it", file != "" and file.contains('"rack"'))
	t._drop_floor_studio(rig2)
	_off()


## The saved `floor/*` spots become the studio room's moved pieces, once.
func the_floor_import_moves_into_the_room() -> void:
	_off()
	var at := func(x: float, z: float, deg: float) -> Transform3D:
		return Transform3D(Basis(Vector3.UP, deg_to_rad(deg)), Vector3(x, 0, z))
	var path := "user://test_floor_moved.cfg"
	var profile := LayoutProfile.new()
	profile.save_path = path
	profile.set_transform(&"floor/deck_trolley", Presentation.Mode.STUDIO, at.call(1.7, 0.9, 10.0))
	profile.set_transform(&"floor/hoop", Presentation.Mode.STUDIO, at.call(2.0, -1.0, 100.0))
	profile.set_transform(&"floor/tablet_1", Presentation.Mode.STUDIO, at.call(0.5, 0.5, 0.0))
	profile.set_transform(&"floor/levels", Presentation.Mode.STUDIO, at.call(-3.0, -2.0, 40.0))
	profile.set_transform(&"floor/rack", Presentation.Mode.ROOM, at.call(1.0, 1.0, 0.0))
	var deltas := RoomDeltas.new()
	deltas.enter(&"studio", 0)
	deltas.delta.move(&"hoop", 9.0, 9.0, 0.0)
	check("a profile has not been moved into a room", profile.floor_moved == 0)
	check("one spot moves into the room's delta (the hoop's was already there)", FloorImport.into_room(profile, deltas) == 1)
	check("the pushed deck is the room's, turned as it was", deltas.delta.moved.has("deck_trolley")
			and absf(float(deltas.delta.moved["deck_trolley"][2]) - deg_to_rad(10.0)) < 1e-4 and deltas.delta.moved["deck_trolley"][0] == 1.7)
	check("one the room already had is not overwritten", deltas.delta.moved["hoop"][0] == 9.0)
	check("the player's own stand stays in the profile, another mode's too",
			profile.has_transform(&"floor/tablet_1", Presentation.Mode.STUDIO) and profile.has_transform(&"floor/rack", Presentation.Mode.ROOM))
	check("and the rest are forgotten, the wall's niche among them", not profile.has_transform(&"floor/deck_trolley", Presentation.Mode.STUDIO)
			and not profile.has_transform(&"floor/hoop", Presentation.Mode.STUDIO) and not profile.has_transform(&"floor/levels", Presentation.Mode.STUDIO)
			and not deltas.delta.moved.has("levels"))
	check("the profile is marked, in its file too", profile.floor_moved == 1)
	profile.set_transform(&"floor/deck_trolley", Presentation.Mode.STUDIO, at.call(0.0, 0.0, 0.0))
	check("it does not run twice", FloorImport.into_room(profile, deltas) == 0 and profile.has_transform(&"floor/deck_trolley", Presentation.Mode.STUDIO))
	var again := LayoutProfile.new()
	again.save_path = path
	again.load_saved()
	check("the mark is kept in the file", again.floor_moved == 1)
	var guest := LayoutProfile.new()
	guest.set_transform(&"floor/deck_trolley", Presentation.Mode.STUDIO, at.call(1.7, 0.9, 10.0))
	var kept_role := Session.role
	Session.role = Session.Role.GUEST
	check("a guest imports nothing, and is not marked", FloorImport.into_room(guest, deltas) == 0 and guest.floor_moved == 0)
	Session.role = kept_role
	deltas.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
