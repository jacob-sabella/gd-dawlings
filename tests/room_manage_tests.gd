extends RefCounted

## Deleting and renaming made rooms (docs/layouts.md section 8, called from the `_test_*` wrappers in
## tests/run_tests.gd): the F4 panel's two-step delete, the host and a guest both led out, the files gone, and a
## rename that changes the title and nothing else. Files are real, in folders of the test's own.

const HOST_DIR := "user://test_manage_host/"
const DELTA_DIR := "user://test_manage_deltas/"

var t: Node
var share
var maker


func _init(runner: Node) -> void:
	t = runner
	share = t.LayoutShareTests.new(runner)
	maker = t.RoomMakerTests.new(runner)


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


## A room made and the host in it with one piece moved, its delta on disk.
func _made_with_a_delta(s: Studio, title: String) -> StringName:
	var made := MadeRooms.make(maker._spec(&"standard", ["drums"], true, title))
	check("the room is made (%s)" % [made["errors"]], made["ok"])
	var id := StringName(made["id"])
	s.venue_switch.choose_venue(id)
	var candidate := s.room_deltas.delta.copy()
	candidate.move(&"hoop", 0.4, 0.4, 0.0)
	s.room_deltas.commit(candidate)
	s.room_deltas.flush()
	return id


func rename_keeps_the_id_and_the_delta() -> void:
	_live()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var id := _made_with_a_delta(s, "Old Name")
	var path := RoomDeltaFile.path_of("%s.0" % id)
	check("the delta is on disk", FileAccess.file_exists(path))
	var panel := RoomMaker.new()
	panel.studio = s
	t.add_child(panel)
	var bad := panel.rename_room(id, "   ")
	check("an empty name is refused and the title stays", bad != "" and Venue.make_title(id) == "Old Name")
	check("a name over the limit is refused", panel.rename_room(id, "x".repeat(MadeRoom.MAX_TITLE + 1)) != "")
	check("renamed", panel.rename_room(id, "  New Name ") == "")
	check("the title is the new one, the id the same", Venue.make_title(id) == "New Name" and MadeRooms.has(id) and MadeRooms.own_ids() == [id])
	check("the delta is still there and the piece still moved", FileAccess.file_exists(path) and s.room_deltas.delta.transform_of(&"hoop") != null)
	check("the venue is the same room", s.venue.venue_id() == id)
	check("a room that is not the player's cannot be renamed", not MadeRooms.rename(&"studio", "Nope")["ok"])

	# A restart reads the new title from the file.
	LiveRoom.reset()
	check("after a restart the file has the new title", Venue.make_title(id) == "New Name")

	# A guest is sent the new title with the room.
	var guest_rig: Dictionary = t._floor_studio()
	var guest: Studio = guest_rig["studio"]
	var state: Dictionary = share._as(Session.Role.HOST, func() -> Variant: return s.room_rows.room_state())
	check("the host's row carries the new title", str(state["made_room"].get("title")) == "New Name")
	share._as(Session.Role.GUEST, func() -> Variant:
		panel.rename_room(id, "Guest Try")
		return null)
	check("a guest cannot rename", Venue.make_title(id) == "New Name")
	MadeRooms.drop_adopted()
	panel.free()
	t._drop_floor_studio(guest_rig)
	t._drop_floor_studio(rig)
	_off()


func delete_asks_twice_and_leads_everyone_out() -> void:
	_live()
	var pair: Dictionary = share._pair()
	var host: Studio = pair["host"]
	var guest: Studio = pair["guest"]
	var id := _made_with_a_delta(host, "Doomed")
	var other: Dictionary = MadeRooms.make(maker._spec(&"standard", ["drums"], true, "Spared"))
	var spared := StringName(other["id"])
	var path := RoomDeltaFile.path_of("%s.0" % id)
	var panel := RoomMaker.new()
	panel.studio = host
	t.add_child(panel)
	panel.toggle()
	check("the panel lists both rooms with a delete button each", panel.find_child("Room_%s" % id, true, false) != null
			and panel.find_child("Room_%s" % spared, true, false) != null)
	share._send(pair)
	check("the guest is in the room", guest.venue.venue_id() == id and MadeRooms.has(id))

	panel.ask_delete(id, true)
	var row := panel.find_child("Room_%s" % id, true, false)
	var labels: Array = row.get_children().filter(func(n: Node) -> bool: return n is Button).map(func(b: Button) -> String: return b.text)
	check("the first press only asks (no OS dialog, nothing deleted)", "REALLY DELETE?" in labels and "KEEP IT" in labels
			and MadeRooms.has(id) and host.venue.venue_id() == id)
	panel.ask_delete(id, false)
	check("changing your mind puts the button back", panel.find_child("Room_%s" % id, true, false).get_children().any(
			func(n: Node) -> bool: return n is Button and n.text == "DELETE"))

	var said: String = share._as(Session.Role.GUEST, func() -> Variant: return panel.delete_room(id))
	check("a guest cannot delete", said != "" and MadeRooms.has(id) and FileAccess.file_exists(path))

	panel.ask_delete(id, true)
	check("the second press deletes", panel.delete_room(id) == "")
	check("the file and the delta are gone, the other room is not", not MadeRooms.has(id) and not FileAccess.file_exists(path)
			and not FileAccess.file_exists("%s%s%s" % [HOST_DIR, id, LayoutSet.SUFFIX]) and MadeRooms.has(spared))
	check("the host is in a shipped room", host.venue.venue_id() == Venue.IDS[0])
	share._send(pair)
	check("the guest is led out with the host and forgets the room", guest.venue.venue_id() == Venue.IDS[0] and guest.venue is Venue)
	check("the panel no longer lists it", panel.find_child("Room_%s" % id, true, false) == null)
	check("the host's profile no longer names it", Session.layout.venue != id)

	# The same name again gets the same id and finds no stale delta.
	var again: Dictionary = MadeRooms.make(maker._spec(&"standard", ["drums"], true, "Doomed"))
	check("a room of the same name has the same id", StringName(again["id"]) == id)
	host.venue_switch.choose_venue(id)
	check("and starts without the old delta", host.room_deltas.delta.is_empty() and host.room_deltas.delta.transform_of(&"hoop") == null)

	# A restart finds the deleted room gone.
	host.venue_switch.choose_venue(Venue.IDS[0])
	MadeRooms.remove(id)
	LiveRoom.reset()
	check("after a restart it is not there", not MadeRooms.has(id) and not Venue.is_known(id) and MadeRooms.has(spared))
	panel.free()
	share._drop(pair)
	_off()
