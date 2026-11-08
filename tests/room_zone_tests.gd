extends RefCounted

## Moving the zones of a made room (docs/layouts.md section 8, called from the `_test_*` wrappers in
## tests/run_tests.gd): a move is snapped to the grid and checked whole; one that leaves the room, lands on another
## zone or shuts a zone off is refused and changes nothing; a good one is kept across a restart, built into the room
## the host stands in, and sent to a guest, who builds it too.

const HOST_DIR := "user://test_zones_host/"

var t: Node
var share
var maker


func _init(runner: Node) -> void:
	t = runner
	share = t.LayoutShareTests.new(runner)
	maker = t.RoomMakerTests.new(runner)


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _made(title: String, size := &"standard", zones := ["drums", "synth", "bricks"]) -> StringName:
	var made := MadeRooms.make(maker._spec(size, zones, true, title))
	check("the room is made (%s)" % [made["errors"]], made["ok"])
	return StringName(made["id"])


func a_zone_moves_on_the_grid_and_is_checked() -> void:
	maker._live(HOST_DIR)
	var id := _made("Zone Room")
	var home: Rect2 = MadeRooms.zone_places(id)[&"drums"]
	check("the zones start at the standard places", home.position.is_equal_approx(Vector2(Venue.ZONES[&"drums"].position.x, Venue.ZONES[&"drums"].position.z)))

	var done := MadeRooms.move_zone(id, &"drums", home.position.x + 0.52, home.position.y + 0.03)
	var now: Rect2 = MadeRooms.zone_places(id)[&"drums"]
	check("a good move is made (%s)" % [done["errors"]], done["ok"])
	check("it lands on the grid", is_equal_approx(now.position.x, MadeRoom.snap(home.position.x + 0.52))
			and is_equal_approx(now.position.y, MadeRoom.snap(home.position.y + 0.03)) and now.position != home.position)
	check("the room still validates", MadeRoom.validate((LiveRoom.layouts().layouts[String(id)] as LayoutData).to_dict()).is_empty())

	var before := JSON.stringify((LiveRoom.layouts().layouts[String(id)] as LayoutData).to_dict())
	var out := MadeRooms.move_zone(id, &"drums", -20.0, 5.0)
	check("a zone cannot be put outside the room", not out["ok"] and out["errors"].size() == 1)
	var synth: Rect2 = MadeRooms.zone_places(id)[&"synth"]
	var over := MadeRooms.move_zone(id, &"drums", synth.position.x, synth.position.y)
	check("a zone cannot be put on another", not over["ok"])
	var behind := MadeRooms.move_zone(id, &"drums", 0.0, Studio.ROOM_BACK - 3.0)
	check("a zone cannot be put in front of the live room", not behind["ok"])
	check("a refused move changes nothing", JSON.stringify((LiveRoom.layouts().layouts[String(id)] as LayoutData).to_dict()) == before)
	check("a zone the room does not have cannot be moved", not MadeRooms.move_zone(id, &"vocals", 0.0, 5.0)["ok"])
	check("a room that is not yours cannot be moved", not MadeRooms.move_zone(&"studio", &"drums", 0.0, 5.0)["ok"])

	# A zone that would wall another in is refused: a box wider than the gap leaves nothing to walk through.
	var spec: Dictionary = maker._spec(&"standard", ["drums", "synth", "bricks"])
	spec["zone_at"] = {"drums": [-3.4, 4.8]}
	check("a spec with a zone placed builds", MadeRoom.build(spec, "x")["ok"])
	spec["zone_at"] = {"drums": [40.0, 4.8]}
	check("a spec with a zone outside is refused", not MadeRoom.build(spec, "x")["ok"])
	spec["zone_at"] = {"vocals": [0.0, 5.0]}
	check("a spec placing a zone it does not keep is refused", not MadeRoom.build(spec, "x")["ok"])
	LiveRoom.reset()
	maker._off()


func the_panel_nudges_and_a_restart_keeps_it() -> void:
	maker._live(HOST_DIR)
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var id := _made("Nudge Room")
	s.venue_switch.choose_venue(id)
	var panel := RoomMaker.new()
	panel.studio = s
	t.add_child(panel)
	panel.toggle()
	var home: Rect2 = MadeRooms.zone_places(id)[&"drums"]
	var drums_was: AABB = s.venue.zones()[&"drums"]
	var said := panel.move_room_zone(id, &"drums", MadeRoom.ZONE_STEP, 0.0)
	check("the nudge is made (%s)" % said, said == "")
	var now: Rect2 = MadeRooms.zone_places(id)[&"drums"]
	check("the zone moved a step to the side", is_equal_approx(now.position.x, home.position.x + MadeRoom.ZONE_STEP))
	check("the room the host stands in was built again with it", is_equal_approx(s.venue.zones()[&"drums"].position.x, drums_was.position.x + MadeRoom.ZONE_STEP))
	check("the nudge past the wall says why", panel.move_room_zone(id, &"drums", 40.0, 0.0) != "")
	check("the reset puts it back", panel.reset_room_zone(id, &"drums") == "" and MadeRooms.zone_places(id)[&"drums"] == home)
	panel.move_room_zone(id, &"drums", 0.0, MadeRoom.ZONE_STEP)

	# The new-room form: a zone is nudged in the spec, refused when it would not do, and forgotten when unticked.
	panel.rebuild()
	check("a zone of the form moves", panel.move_spec_zone(&"drums", 0.5, 0.0) == "")
	check("and is in the spec", panel.spec["zone_at"].has("drums"))
	check("a zone of the form is not moved off the room", panel.move_spec_zone(&"drums", 60.0, 0.0) != "")
	panel.set_zone(&"drums", false)
	check("a zone unticked loses its place", not panel.spec["zone_at"].has("drums"))

	LiveRoom.reset()
	check("after a restart the file still has the moved zone", MadeRooms.zone_places(id)[&"drums"].position.y == home.position.y + MadeRoom.ZONE_STEP)
	panel.free()
	t._drop_floor_studio(rig)
	maker._off()


func a_guest_builds_the_moved_zone() -> void:
	maker._live(HOST_DIR)
	var pair: Dictionary = share._pair()
	var host: Studio = pair["host"]
	var guest: Studio = pair["guest"]
	var id := _made("Shared Zones")
	host.venue_switch.choose_venue(id)
	share._send(pair)
	var was: AABB = guest.venue.zones()[&"drums"]
	check("the guest is in the room", guest.venue.venue_id() == id)
	var panel := RoomMaker.new()
	panel.studio = host
	t.add_child(panel)
	var said: String = share._as(Session.Role.HOST, func() -> Variant: return panel.move_room_zone(id, &"drums", 0.0, MadeRoom.ZONE_STEP))
	check("the host moves it (%s)" % said, said == "")
	var by_guest: String = share._as(Session.Role.GUEST, func() -> Variant: return panel.move_room_zone(id, &"drums", 0.5, 0.0))
	check("a guest cannot move a zone", by_guest != "")
	share._send(pair)
	check("the guest has built the room again with the zone where the host put it",
			is_equal_approx(guest.venue.zones()[&"drums"].position.z, was.position.z + MadeRoom.ZONE_STEP))
	MadeRooms.drop_adopted()
	panel.free()
	share._drop(pair)
	LiveRoom.reset()
	maker._off()


## The limits stay: a room of zones and the largest piece list is still under the file and piece caps.
func the_limits_still_hold() -> void:
	maker._live(HOST_DIR)
	var id := _made("Limits", &"large", ["drums", "synth", "bricks", "matrix", "vocals"])
	for z in MadeRooms.zone_places(id):
		MadeRooms.move_zone(id, z, MadeRooms.zone_places(id)[z].position.x, MadeRooms.zone_places(id)[z].position.y)
	var text := FileAccess.get_file_as_string("%s%s%s" % [HOST_DIR, id, LayoutSet.SUFFIX])
	check("the file is under the limit", text.to_utf8_buffer().size() <= MadeRoom.MAX_BYTES)
	check("the pieces are under the limit", (LiveRoom.layouts().layouts[String(id)] as LayoutData).pieces().size() <= LayoutData.MAX_PIECES)
	LiveRoom.reset()
	maker._off()
