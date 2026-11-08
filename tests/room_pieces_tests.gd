extends RefCounted

## The drum circle, the venue's instrument and the weather switch as removable pieces (docs/layouts.md section 7, called
## from the `_test_*` wrappers in tests/run_tests.gd): each comes out and goes back, what hangs on it goes with it (the
## hand drums, the bars, the walker solid), a shell without one refuses, a restart keeps it and a guest sees it.

const DELTA_DIR := "user://test_pieces_deltas/"

var t: Node
var share


func _init(runner: Node) -> void:
	t = runner
	share = t.LayoutShareTests.new(runner)


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## The first venue whose shell supplies shell piece `id` and is solid about it (so the solid can be checked), or "".
func _venue_with(s: Studio, id: StringName) -> StringName:
	for v in Venue.IDS:
		s.venue_switch.choose_venue(v)
		var solids: Array = s.venue.instrument_solids() if id == &"venue" else s.venue.weather_solids()
		if PieceHost.shell_has(s.venue, id) and not solids.is_empty():
			return v
	return &""


func the_drum_circle_comes_out_and_the_drums_are_put_away() -> void:
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var drum := HandDrum.KINDS[0]
	check("the circle stands and the hand drums have homes", s.drum_circle != null and s.item_host._item_homes().has(drum))
	check("it is taken out", s.rack_host.ask_layout("remove", ["drums"]) == "" and s.drum_circle == null and s.room_deltas.delta.is_removed(&"drums"))
	check("the hand drums are put away: no home on the riser", not s.item_host._item_homes().has(drum))
	check("it cannot be taken out twice or moved", s.rack_host.ask_layout("remove", ["drums"]) != "" and s.rack_host.ask_layout("move", ["drums", 0.0, 0.0]) != "")
	check("the looper, on the same riser, is not touched", s.looper != null)
	var why: String = s.rack_host.ask_layout("add", ["drums"])
	check("it is put back with add (%s)" % why, why == "" and s.drum_circle != null and s.item_host._item_homes().has(drum))
	check("the F3 list offers it while out", s.rack_host.ask_layout("remove", ["drums"]) == "" and "drums" in s.layout_edit.missing().map(func(k: StringName) -> String: return String(k)))
	check("reset puts it back", s.rack_host.ask_layout("reset", ["all"]) == "" and s.drum_circle != null and s.item_host._item_homes().has(drum))
	t._drop_floor_studio(rig)


func a_shell_piece_comes_out_with_its_solid() -> void:
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	for pair: Array in [[&"venue", "instrument", "venue_instrument"], [&"weather", "weather", "weather"]]:
		var id: StringName = pair[0]
		var v := _venue_with(s, id)
		check("some venue has a %s with a solid post" % id, v != &"")
		if v == &"":
			continue
		var solids := func() -> Array: return s.venue.instrument_solids() if id == &"venue" else s.venue.weather_solids()
		check("%s stands and is solid" % id, s.get(pair[2]) != null and not solids.call().is_empty())
		check("%s is taken out" % id, s.rack_host.ask_layout("remove", [String(id)]) == "" and s.get(pair[2]) == null)
		check("its solid is gone from the venue and from the walker", solids.call().is_empty() and (s.walker.fixed as Array).size() == s.venue.solids().size())
		check("it cannot be taken out twice", s.rack_host.ask_layout("remove", [String(id)]) != "")
		var why: String = s.rack_host.ask_layout("add", [String(id)])
		check("%s is put back (%s)" % [id, why], why == "" and s.get(pair[2]) != null and not solids.call().is_empty())
		check("the walker has its solid again", (s.walker.fixed as Array).size() == s.venue.solids().size())
	# Out, then the room is left and entered again: the delta still has it out.
	var v := _venue_with(s, &"venue")
	s.venue_switch.choose_venue(v)
	s.rack_host.ask_layout("remove", ["venue"])
	var other := Venue.IDS[(Venue.IDS.find(v) + 1) % Venue.IDS.size()]
	s.venue_switch.choose_venue(other)
	s.venue_switch.choose_venue(v)
	check("coming back into the room finds the instrument still out, and no solid", s.venue_instrument == null and s.venue.instrument_solids().is_empty())
	t._drop_floor_studio(rig)


func a_shell_without_the_piece_refuses() -> void:
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	s.venue_switch.choose_venue(Venue.ROULETTE_ID)
	for id in ["venue", "weather", "drums"]:
		check("the roulette room has no %s to take out" % id, s.rack_host.ask_layout("remove", [id]) != "")
	check("and no place to put one", s.rack_host.ask_layout("add", ["weather"]) != "")
	check("the maker does not offer the shell's two", PieceCatalogue.maker_kinds().size() == PieceCatalogue.kinds().size() - 2
			and &"drums" in PieceCatalogue.maker_kinds() and &"weather" not in PieceCatalogue.maker_kinds())
	t._drop_floor_studio(rig)


func a_restart_keeps_them_out() -> void:
	RoomDeltas.disabled = false
	RoomDeltaFile.dir_override = DELTA_DIR
	DirAccess.make_dir_recursive_absolute(DELTA_DIR)
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var v := _venue_with(s, &"weather")
	s.venue_switch.choose_venue(v)
	check("two pieces out", s.rack_host.ask_layout("remove", ["drums"]) == "" and s.rack_host.ask_layout("remove", ["weather"]) == "")
	s.room_deltas.flush()
	var path := RoomDeltaFile.path_of(s.room_deltas.delta.room)
	var got := RoomDeltaFile.read(path)
	check("the file holds them out", got["ok"] and got["delta"].is_removed(&"drums") and got["delta"].is_removed(&"weather"))
	t._drop_floor_studio(rig)
	var again: Dictionary = t._floor_studio()
	var s2: Studio = again["studio"]
	s2.venue_switch.choose_venue(v)
	check("a new studio (a restart) stands the room without them", s2.drum_circle == null and s2.weather == null and not s2.item_host._item_homes().has(HandDrum.KINDS[0]))
	t._drop_floor_studio(again)
	RoomDeltas.disabled = true
	RoomDeltaFile.dir_override = ""
	for f in DirAccess.get_files_at(DELTA_DIR):
		DirAccess.remove_absolute(DELTA_DIR + f)


func a_guest_sees_the_pieces_out_and_back() -> void:
	var pair: Dictionary = share._pair()
	var host: Studio = pair["host"]
	var guest: Studio = pair["guest"]
	var v := _venue_with(host, &"weather")
	host.venue_switch.choose_venue(v)
	share._send(pair)
	check("the guest has them all", guest.drum_circle != null and guest.weather != null)
	share._as(Session.Role.HOST, func() -> Variant:
		host.rack_host.ask_layout("remove", ["drums"])
		host.rack_host.ask_layout("remove", ["weather"])
		return null)
	share._send(pair)
	check("the guest's room is without the circle and the weather", guest.drum_circle == null and guest.weather == null)
	check("and the guest's hand drums are put away", not guest.item_host._item_homes().has(HandDrum.KINDS[0]))
	check("and its weather solid is gone", guest.venue.weather_solids().is_empty())
	share._as(Session.Role.HOST, func() -> Variant:
		host.rack_host.ask_layout("reset", ["all"])
		return null)
	share._send(pair)
	check("put back, the guest has them again", guest.drum_circle != null and guest.weather != null and not guest.venue.weather_solids().is_empty())
	share._drop(pair)
