extends RefCounted

## The host's edits of the room (docs/layouts.md section 11 step 9), called from the `_test_*` wrappers in
## tests/run_tests.gd: `ask_layout` with each op accepted and refused, a guest told "host only", an added
## hoop built and a removed piece un-stood, a reset, the edit surviving a reload in a fresh studio, and a
## guest seeing it through the `layout` row. Files go to the folder of the room-delta tests.

var t: Node
var base


func _init(runner: Node) -> void:
	t = runner
	base = t.RoomDeltaTests.new(runner)


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _at(tr: Trolley) -> Vector2:
	return Vector2(tr.position.x, tr.position.z)


## Every op, done and refused; a refusal changes nothing.
func ops_are_done_or_refused() -> void:
	base._off()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var hoop: Trolley = s.live_pieces[&"hoop"]
	var rev := s.room_deltas.delta.rev
	check("move: the host puts the hoop 0.5 m on, and it stands there", s.rack_host.ask_layout("move", ["hoop", hoop.position.x + 0.5, hoop.position.z, hoop.rotation.y]) == ""
			and s.room_deltas.delta.moved.has("hoop") and absf(hoop.position.x - (s.room_deltas.delta.moved["hoop"][0])) < 0.01)
	var at := _at(hoop)
	check("rotate: and turns it, where it stands", s.rack_host.ask_layout("rotate", ["hoop", 1.0]) == "" and absf(hoop.rotation.y - 1.0) < 0.01 and _at(hoop).distance_to(at) < 0.01)
	rev = s.room_deltas.delta.rev
	var why := s.rack_host.ask_layout("move", ["hoop", 50.0, 50.0])
	check("a move off the floor is refused, with a reason (%s)" % why, why != "" and s.room_deltas.delta.rev == rev and _at(hoop).distance_to(at) < 0.01)
	why = s.rack_host.ask_layout("move", ["hoop", 0.0, 0.0, 0.0, 1.0])
	check("a move with the wrong arguments is refused (%s)" % why, why != "" and s.room_deltas.delta.rev == rev)
	check("a move with a number that is not one is refused", s.rack_host.ask_layout("move", ["hoop", NAN, 0.0]) != "" and s.rack_host.ask_layout("move", ["hoop", "x", 0.0]) != "")
	check("a piece the room does not have is refused", s.rack_host.ask_layout("move", ["unicorn", 0.0, 0.0]) != "" and s.rack_host.ask_layout("remove", ["unicorn"]) != "")
	why = s.rack_host.ask_layout("remove", ["tour_case"])
	check("a piece that is part of the room stays (%s)" % why, why.contains("part of the room") and s.room_deltas.delta.removed.is_empty())
	check("an op nobody knows is refused", s.rack_host.ask_layout("fly", []) != "")
	check("add: something that is not addable is refused", s.rack_host.ask_layout("add", ["tour_case", 0.0, 0.0, 0.0]) != "")
	base._off()
	t._drop_floor_studio(rig)


## A guest is told host only, except for pushing a piece on wheels by hand.
func a_guest_is_told_host_only() -> void:
	base._off()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var rev := s.room_deltas.delta.rev
	for op: Array in [["remove", ["sampler"]], ["add", ["hoop", 0.0, 0.0, 0.0]], ["reset", ["all"]], ["rotate", ["hoop", 1.0]]]:
		check("%s from a guest is host only" % op[0], s.layout_edit.answer(op[0], op[1], 7) == LayoutEdit.HOST_ONLY)
	check("a guest's move of something with no wheels is host only", s.layout_edit.answer("move", ["sampler_nowhere", 0.0, 0.0], 7) == LayoutEdit.HOST_ONLY)
	var hoop: Trolley = s.live_pieces[&"hoop"]
	var to := _at(hoop) + Vector2(0.3, 0.0)
	check("but a guest's push of the hoop is placed", s.layout_edit.answer("move", ["hoop", to.x, to.y, hoop.rotation.y], 7) == "" and _at(hoop).distance_to(to) < 0.02)
	check("and nothing else of the room changes", s.sampler != null and s.room_deltas.delta.removed.is_empty() and s.room_deltas.delta.added.is_empty())
	var kept := Session.role
	Session.role = Session.Role.GUEST
	check("on a guest, the studio's own ask says so", s.rack_host.ask_layout("remove", ["sampler"]) == LayoutEdit.HOST_ONLY and s.sampler != null)
	check("and a guest's own push is not refused", s.rack_host.ask_layout("move", ["hoop", to.x, to.y + 0.1, hoop.rotation.y]) == "")
	Session.role = kept
	check("the room verb is known and typed", Session.ROOM_VERBS.has(&"layout"))
	base._off()
	t._drop_floor_studio(rig)


## An added hoop is built and a removed piece is not stood; remove and add put one back; reset.
func add_remove_and_reset() -> void:
	base._off()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var home := _at(s.live_pieces[&"hoop"])
	check("the studio starts with a sampler and a cassette rack", s.sampler != null and s.cassette_rack != null)
	check("remove: the sampler goes", s.rack_host.ask_layout("remove", ["sampler"]) == "" and s.sampler == null and not s.live_pieces[&"sampler"].visible
			and s.room_deltas.delta.removed.has("sampler"))
	check("remove: so does the cassette rack", s.rack_host.ask_layout("remove", ["cassette_rack"]) == "" and s.cassette_rack == null)
	check("and a removed piece cannot be moved", s.rack_host.ask_layout("move", ["sampler", 0.0, 0.0]) != "")
	check("it cannot be taken out twice", s.rack_host.ask_layout("remove", ["sampler"]) != "")
	var spot := home + Vector2(1.2, 0.0)
	var why := s.rack_host.ask_layout("add", ["hoop", spot.x, spot.y, 0.0])
	check("add: another hoop is built (%s)" % why, why == "" and s.room_deltas.delta.added.size() == 1)
	var copy_id := StringName(s.room_deltas.delta.added[0]["id"])
	var copy: Trolley = s.live_pieces.get(copy_id)
	check("on a trolley of its own, where it was asked", copy != null and copy.visible and _at(copy).distance_to(spot) < 0.3
			and s.floor_plan.pieces.has(copy))
	check("and the hoop itself stands in the venue", s.venue.get_node_or_null(RoomSync.node_name(copy_id)) is Hoop)
	check("its basket is among the venue's", RoomSync.hoops(s).size() >= 2)
	check("reset: the sampler is put back", s.rack_host.ask_layout("reset", ["sampler"]) == "")
	check("and is stood again", s.sampler != null and s.live_pieces[&"sampler"].visible)
	var moved := _at(copy) + Vector2(0.2, 0.3)
	check("a copy moves with the same verb", s.rack_host.ask_layout("move", [String(copy_id), moved.x, moved.y]) == "" and _at(copy).distance_to(moved) < 0.02
			and s.room_deltas.delta.added[0]["at"]["pos"][0] != spot.x)
	var last := ""
	for n in 6:
		last = s.rack_host.ask_layout("add", ["hoop", spot.x - 0.5 * n, spot.y + 1.0, 0.0])
		if last != "" and s.room_deltas.delta.added.size() >= PieceCatalogue.limit(&"hoop") - 1:
			break
	check("the copies stop at the limit (%s, %d)" % [last, s.room_deltas.delta.added.size()], s.room_deltas.delta.added.size() == PieceCatalogue.limit(&"hoop") - 1 and last.contains("most"))
	s.set_venue(&"rooftop", false, 0)
	check("another room has none of this room's copies", s.venue.get_node_or_null(RoomSync.node_name(copy_id)) == null and s.sampler != null)
	s.set_venue(&"studio", false, 0)
	check("and the studio has them again when it is back", s.venue.get_node_or_null(RoomSync.node_name(copy_id)) is Hoop and s.sampler != null)
	check("reset: one copy is taken down", s.rack_host.ask_layout("reset", [String(copy_id)]) == "" and (s.live_pieces.get(copy_id) == null or not s.live_pieces[copy_id].visible))
	check("and its hoop is gone from the venue", s.venue.get_node_or_null(RoomSync.node_name(copy_id)) == null)
	check("reset: the whole room goes back to the default", s.rack_host.ask_layout("reset", ["all"]) == "" and s.room_deltas.delta.is_empty()
			and s.sampler != null and s.cassette_rack != null and s.room_deltas.delta.added.is_empty()
			and _at(s.live_pieces[&"hoop"]).distance_to(home) < 0.02)
	check("a reset of a room that is the default has nothing to do", s.rack_host.ask_layout("reset", ["all"]) != "")
	base._off()
	t._drop_floor_studio(rig)


## The edit is written, and a fresh studio finds the room as it was left.
func an_edit_survives_a_reload() -> void:
	base._live()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	s.room_deltas.delay = 0.05
	var home := _at(s.live_pieces[&"hoop"])
	var spot := home + Vector2(1.2, 0.0)
	var said := [s.rack_host.ask_layout("add", ["hoop", spot.x, spot.y, 0.0]), s.rack_host.ask_layout("remove", ["sampler"]),
			s.rack_host.ask_layout("move", ["hoop", home.x - 0.3, home.y, 0.0])]
	check("an add, a remove and a move are all accepted (%s)" % [said], said == ["", "", ""])
	var id := StringName(s.room_deltas.delta.added[0]["id"])
	await t.get_tree().create_timer(0.3).timeout
	s.room_deltas.flush()
	s.room_deltas.wait()
	check("they are written", FileAccess.file_exists(RoomDeltaFile.path_of("studio.0")) and s.room_deltas.writes >= 1)
	t._drop_floor_studio(rig)

	var rig2: Dictionary = t._floor_studio()
	var fresh: Studio = rig2["studio"]
	check("a fresh studio stands the added hoop", fresh.live_pieces.get(id) != null and fresh.live_pieces[id].visible
			and fresh.venue.get_node_or_null(RoomSync.node_name(id)) is Hoop and fresh.floor_plan.pieces.has(fresh.live_pieces[id]))
	check("without the sampler", fresh.sampler == null and not fresh.live_pieces[&"sampler"].visible)
	check("and with the hoop where it was left", _at(fresh.live_pieces[&"hoop"]).distance_to(home + Vector2(-0.3, 0.0)) < 0.02)
	check("and the cassette rack still there", fresh.cassette_rack != null)
	check("a reset in it is written too", fresh.rack_host.ask_layout("reset", ["all"]) == "" and fresh.sampler != null)
	t._drop_floor_studio(rig2)
	base._off()


## A guest applies the host's row: the copy is built and the removed piece is not stood; a reset undoes it.
func a_guest_sees_the_edit() -> void:
	base._off()
	var rig: Dictionary = t._floor_studio()
	var host: Studio = rig["studio"]
	var home := _at(host.live_pieces[&"hoop"])
	host.rack_host.ask_layout("add", ["hoop", home.x + 1.2, home.y, 0.0])
	host.rack_host.ask_layout("remove", ["sampler"])
	var id := StringName(host.room_deltas.delta.added[0]["id"])
	var state := host.room_rows.room_state()
	var row: Dictionary = state["layout"]
	check("the host's row carries the added hoop and the removed sampler", row["added"].size() == 1 and row["removed"] == ["sampler"] and RoomDelta.problem(row) == "")
	t._drop_floor_studio(rig)

	var rig2: Dictionary = t._floor_studio()
	var guest: Studio = rig2["studio"]
	var kept := Session.role
	Session.role = Session.Role.GUEST
	guest.room_rows.apply_room(state, false)
	check("the guest stands the hoop", guest.live_pieces.get(id) != null and guest.live_pieces[id].visible
			and guest.venue.get_node_or_null(RoomSync.node_name(id)) is Hoop)
	check("and does not stand the sampler", guest.sampler == null)
	var back := state.duplicate(true)
	back["layout"] = RoomDelta.empty(&"studio", 0).to_dict()
	back["layout"]["rev"] = row["rev"] + 1
	guest.room_rows.apply_room(back, false)
	check("a reset on the host puts both back on the guest", guest.sampler != null and guest.venue.get_node_or_null(RoomSync.node_name(id)) == null)
	Session.role = kept
	t._drop_floor_studio(rig2)
	base._off()


## The F3 panel: opens for the host, lists the pieces, shows the validator's words, and stays shut for a guest.
func the_panel_shows_what_the_validator_said() -> void:
	base._off()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var ed := LayoutEditor.new()
	ed.studio = s
	t.add_child(ed)
	ed.toggle()
	check("F3 opens it for the host, with buttons for the room's pieces", ed.is_open() and ed._rows.get_child_count() >= 3 and ed._picked != &"")
	ed._ask("move", ["hoop", 50.0, 50.0])
	check("a refused move says why in the panel", ed._status.text != "" and not ed._status.text.begins_with("Done"))
	ed._pick(&"hoop")
	ed._nudge(0.1, 0.0)
	check("a nudge is asked of the studio and says it is done", ed._status.text.begins_with("Done") and s.room_deltas.delta.moved.has("hoop"))
	ed._ask("remove", ["sampler"])
	ed._add(&"hoop")
	check("remove and add go through the same verb", s.sampler == null and ed._status.text != "")
	ed._ask("reset", ["all"])
	check("reset room undoes them", s.room_deltas.delta.is_empty() and s.sampler != null)
	ed.toggle()
	check("and F3 again closes it", not ed.is_open())
	var kept := Session.role
	Session.role = Session.Role.GUEST
	ed.toggle()
	check("a guest cannot open it", not ed.is_open())
	Session.role = kept
	t.remove_child(ed)
	ed.free()
	base._off()
	t._drop_floor_studio(rig)
