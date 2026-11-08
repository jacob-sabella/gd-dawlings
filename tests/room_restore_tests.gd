extends RefCounted

## Putting back what a room lacks (docs/layouts.md section 8, called from the `_test_*` wrappers in
## tests/run_tests.gd): a piece a made room left out, or a delta took out of a venue, is listed and added
## back with `ask_layout("add", [piece])` at the layout's own spot or `[piece, x, z, yaw]` at a stated one,
## always through the validator; a guest sees it, and a restart finds it.

const HOST_DIR := "user://test_restore_host/"
const DELTA_DIR := "user://test_restore_deltas/"

var t: Node
var share
var maker
var manage


func _init(runner: Node) -> void:
	t = runner
	share = t.LayoutShareTests.new(runner)
	maker = t.RoomMakerTests.new(runner)
	manage = t.RoomManageTests.new(runner)


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _live() -> void:
	maker._live(HOST_DIR)
	maker._clean(DELTA_DIR)
	RoomDeltas.disabled = false
	RoomDeltaFile.dir_override = DELTA_DIR


func _off() -> void:
	RoomDeltas.disabled = true
	RoomDeltaFile.dir_override = ""
	maker._clean(DELTA_DIR)
	maker._off()


func _at(tr: Trolley) -> Vector2:
	return Vector2(tr.position.x, tr.position.z)


## A made room with the zones, none of the four pieces that can be left out.
func _bare_room(title: String) -> StringName:
	var spec: Dictionary = maker._spec(&"standard", ["drums", "synth", "bricks"], true, title)
	for kind in ["cassette_rack", "sampler", "hoop", "wheel"]:
		spec["pieces"].erase(kind)
	var made := MadeRooms.make(spec)
	check("the bare room is made (%s)" % [made["errors"]], made["ok"])
	return StringName(made["id"])


func a_taken_out_piece_goes_back_by_default_or_where_asked() -> void:
	manage._off()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var home := _at(s.live_pieces[&"sampler"])
	var heading: float = (s.live_pieces[&"sampler"] as Trolley).rotation.y
	check("a room that lacks nothing lists nothing to put back", s.layout_edit.missing().is_empty())
	check("the sampler goes", s.rack_host.ask_layout("remove", ["sampler"]) == "" and s.sampler == null)
	check("it is listed to put back", s.layout_edit.missing() == [&"sampler"])
	check("add with only its name puts it where the room stands it", s.rack_host.ask_layout("add", ["sampler"]) == ""
			and s.sampler != null and _at(s.live_pieces[&"sampler"]).distance_to(home) < 0.05 and s.room_deltas.delta.is_empty())
	check("and it is no longer listed", s.layout_edit.missing().is_empty())
	check("it goes again", s.rack_host.ask_layout("remove", ["sampler"]) == "")
	var why := ""
	for offset in [Vector2(0.3, 0.0), Vector2(-0.3, 0.0), Vector2(0.0, -0.3), Vector2(0.0, 0.3), Vector2(0.5, 0.5)]:
		var spot: Vector2 = home + offset
		why = s.rack_host.ask_layout("add", ["sampler", spot.x, spot.y, heading])
		if why == "":
			break
	check("add with a spot puts it there, or the nearest clear one (%s)" % why, why == "" and s.sampler != null
			and s.room_deltas.delta.moved.has("sampler") and s.layout_edit.refusal(s.room_deltas.delta) == "")
	check("a spot that is a wall is refused and changes nothing", s.rack_host.ask_layout("remove", ["sampler"]) == ""
			and s.rack_host.ask_layout("add", ["sampler", 40.0, 40.0, 0.0]) != "" and s.sampler == null)
	check("a wrong number of arguments is refused", s.rack_host.ask_layout("add", ["hoop", 1.0]) != "" and s.rack_host.ask_layout("add", []) != "")
	t._drop_floor_studio(rig)
	manage._off()


func a_left_out_piece_of_a_made_room_comes_back() -> void:
	manage._live()
	_live()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var id := _bare_room("Bare Room")
	s.venue_switch.choose_venue(id)
	check("in the bare room: no rack, no sampler, no wheel, no hoop", s.cassette_rack == null and s.sampler == null and s.wheel == null
			and not s.live_pieces[&"hoop"].visible)
	var missing: Array = s.layout_edit.missing()
	check("each is listed to put back", &"cassette_rack" in missing and &"sampler" in missing and &"wheel" in missing and &"hoop" in missing)
	check("the looper's zone is not in the room, so the looper is not offered", &"looper" not in missing or false)

	check("the rack comes back at the layout's spot", s.rack_host.ask_layout("add", ["cassette_rack"]) == "" and s.cassette_rack != null
			and s.live_pieces[&"cassette_rack"].visible and s.room_deltas.delta.is_restored(&"cassette_rack"))
	check("the venue has a spot for it now", s.venue.default_spot(&"cassette_rack") != null)
	check("it stands where its trolley is", s.cassette_rack.transform.origin.distance_to(s.live_pieces[&"cassette_rack"].position) < 1.5)
	var spot := _at(s.live_pieces[&"sampler"]) if s.live_pieces.has(&"sampler") else Vector2.ZERO
	var why: String = s.rack_host.ask_layout("add", ["sampler"])
	check("the sampler comes back (%s)" % why, why == "" and s.sampler != null)
	check("the wheel, which a zone holds, comes back", s.rack_host.ask_layout("add", ["wheel"]) == "" and s.wheel != null)
	why = s.rack_host.ask_layout("add", ["hoop"])
	check("so does the hoop (%s)" % why, why == "" and s.live_pieces[&"hoop"].visible)
	check("and the room is still valid", s.layout_edit.refusal(s.room_deltas.delta) == "")
	check("nothing is left to put back of those", s.layout_edit.missing().filter(func(k: StringName) -> bool: return k in [&"cassette_rack", &"sampler", &"wheel", &"hoop"]).is_empty())
	check("one more is refused: the room has it", s.rack_host.ask_layout("add", ["cassette_rack"]) != "")

	# Where the host says, through the validator.
	var default_at := _at(s.live_pieces[&"cassette_rack"])
	check("remove takes a restored piece out again", s.rack_host.ask_layout("remove", ["cassette_rack"]) == "" and s.cassette_rack == null
			and not s.room_deltas.delta.is_restored(&"cassette_rack"))
	var stated := default_at + Vector2(0.4, 0.0)
	why = s.rack_host.ask_layout("add", ["cassette_rack", stated.x, stated.y, 0.0])
	check("add with a spot (%s)" % why, why == "" and s.cassette_rack != null and s.room_deltas.delta.is_restored(&"cassette_rack")
			and s.layout_edit.refusal(s.room_deltas.delta) == "")
	var rack_at := _at(s.live_pieces[&"cassette_rack"])

	# Persists.
	s.room_deltas.flush()
	check("the delta file says what is restored", FileAccess.get_file_as_string(RoomDeltaFile.path_of("%s.0" % id)).contains("restored"))
	LiveRoom.reset()
	(rig["hand"] as Node).free()
	t.remove_child(s)
	s.free()
	var again := Studio.new()
	again.medium = Presentation.Medium.SCREEN
	t.add_child(again)
	check("restarted: the room has the restored pieces", again.venue.venue_id() == id and again.cassette_rack != null and again.sampler != null
			and again.wheel != null and again.room_deltas.delta.is_restored(&"cassette_rack"))
	check("and the rack is where it was put", _at(again.live_pieces[&"cassette_rack"]).distance_to(rack_at) < 0.1)
	var reset_said: String = again.rack_host.ask_layout("reset", ["all"])
	check("reset room leaves them out again (%s %s %s %s)" % [reset_said, again.cassette_rack, again.sampler, again.wheel], reset_said == ""
			and again.cassette_rack == null and again.sampler == null and again.wheel == null)
	t.remove_child(again)
	again.free()
	_off()
	manage._off()


func a_guest_sees_the_piece_put_back() -> void:
	manage._live()
	_live()
	var pair: Dictionary = share._pair()
	var host: Studio = pair["host"]
	var guest: Studio = pair["guest"]
	var id := _bare_room("Bare Guest")
	host.venue_switch.choose_venue(id)
	share._send(pair)
	check("the guest is in the bare room, without the rack", guest.venue.venue_id() == id and guest.cassette_rack == null)
	check("the host puts the rack back", host.rack_host.ask_layout("add", ["cassette_rack"]) == "" and host.cassette_rack != null)
	var state: Dictionary = share._send(pair)
	check("the row says what is restored", "cassette_rack" in state["layout"].get("restored", []))
	check("the guest has the rack, and the same restored list", guest.cassette_rack != null and guest.room_deltas.delta.is_restored(&"cassette_rack")
			and guest.live_pieces[&"cassette_rack"].visible)
	check("a guest cannot put one back", share._as(Session.Role.GUEST, func() -> Variant: return guest.layout_edit.answer("add", ["sampler"], 7)) == LayoutEdit.HOST_ONLY
			and guest.sampler == null)
	var back: Dictionary = share._as(Session.Role.HOST, func() -> Variant: return RoomDelta.from_dict(host.room_rows.room_state()["layout"]).to_dict(false))
	check("the row round-trips through the delta", back["restored"] == ["cassette_rack"])
	host.venue_switch.choose_venue(Venue.IDS[0])
	MadeRooms.remove(id)
	share._send(pair)
	share._drop(pair)
	_off()
	manage._off()


func the_panel_lists_what_can_be_put_back() -> void:
	manage._live()
	_live()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var id := _bare_room("Bare Panel")
	s.venue_switch.choose_venue(id)
	var panel := LayoutEditor.new()
	panel.studio = s
	t.add_child(panel)
	panel.toggle()
	var row := panel.find_child("PutBack", true, false)
	check("the panel has a put back row", row != null)
	var labels: Array = row.get_children().filter(func(n: Node) -> bool: return n is Button).map(func(b: Button) -> String: return b.text)
	check("it names the rack and the wheel (%s)" % [labels], "+ CASSETTE RACK" in labels and "+ FIFTHS WHEEL" in labels)
	(row.get_children().filter(func(n: Node) -> bool: return n is Button and n.text == "+ CASSETTE RACK")[0] as Button).pressed.emit()
	check("pressing one puts it back", s.cassette_rack != null)
	check("and the row no longer names it", not panel.find_child("PutBack", true, false).get_children().any(func(n: Node) -> bool: return n is Button and n.text == "+ CASSETTE RACK"))
	panel.free()
	s.venue_switch.choose_venue(Venue.IDS[0])
	MadeRooms.remove(id)
	t._drop_floor_studio(rig)
	_off()
	manage._off()


func the_delta_carries_what_is_restored() -> void:
	var d := RoomDelta.empty(&"studio", 0)
	check("a room that restored nothing writes no key for it", not d.to_dict().has("restored") and d.is_empty())
	check("restore is a change once", d.restore(&"sampler") and not d.restore(&"sampler") and not d.is_empty())
	var back := RoomDelta.from_dict(JSON.parse_string(d.text()))
	check("it round-trips through the file text", back.restored == ["sampler"] and back.text() == d.text())
	check("a bad entry is mended, not kept", RoomDelta.from_dict({"restored": ["ok_id", 7, "Not An Id", "ok_id"]}).restored == ["ok_id"])
	var body := LiveRoom.layout(&"studio", 0).body
	var applied := d.apply(body, {})
	check("a layout that left nothing out flags a restored id", applied["flagged"].any(func(f: Dictionary) -> bool: return f["code"] == &"unknown_piece"))
	var left := {"pieces": [{"id": "ghost", "piece": "hoop"}], "wiring": [{"kind": "feeds", "from": "ghost", "to": "tour_case"}], "members": {"tape": ["ghost"]}}
	d.restored.clear()
	d.restore(&"ghost")
	var got := d.apply(body, left)
	check("a restored piece, its wire and its group place come back", got["pieces"].any(func(p: Dictionary) -> bool: return p["id"] == "ghost")
			and got["wiring"].any(func(w: Dictionary) -> bool: return w["from"] == "ghost")
			and got["groups"].any(func(g: Dictionary) -> bool: return g["id"] == "tape" and "ghost" in g["members"]))
	check("and the body it was laid over is untouched", not body["pieces"].any(func(p: Dictionary) -> bool: return p["id"] == "ghost"))
	check("clear forgets it", d.clear() and d.restored.is_empty())
	var over := RoomDelta.problem({"restored": range(LayoutData.MAX_PIECES + 1)})
	check("too many is refused (%s)" % over, over != "")
