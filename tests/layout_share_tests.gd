extends RefCounted

## Sharing the layout (docs/layouts.md section 11 step 10), called from the `_test_*` wrappers in
## tests/run_tests.gd. A HOST studio and a GUEST studio stand in the tree together (the pattern of the rack's
## guest test: `Session.role` is flipped around each call, and the row goes from `room_state()` to
## `apply_room()` as the session sends it): the guest sees what the host arranged, is told host only when it
## tries to arrange, and goes back to the default when the host resets. A piece this build cannot make is a
## named plate in its place. The zone-held pieces come out of a room and go back; and the brief's proof as
## far as it goes without the room-maker: delete in one venue, add in another, restart, and a guest sees both.

var t: Node
var base


func _init(runner: Node) -> void:
	t = runner
	base = t.RoomDeltaTests.new(runner)


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _at(tr: Trolley) -> Vector2:
	return Vector2(tr.position.x, tr.position.z)


## Run `what` as the host (a solo player is the authority too) or as a guest, then put the role back.
func _as(role: int, what: Callable) -> Variant:
	var kept := Session.role
	Session.role = role
	var out: Variant = what.call()
	Session.role = kept
	return out


## The host's studio and a guest's, both in the tree; the guest has adopted the host's room.
func _pair() -> Dictionary:
	var host_rig: Dictionary = t._floor_studio()
	var guest_rig: Dictionary = t._floor_studio()
	return {"host_rig": host_rig, "guest_rig": guest_rig, "host": host_rig["studio"], "guest": guest_rig["studio"]}


func _drop(pair: Dictionary) -> void:
	# In the order they were made: the second rig's saved profile is the first rig's.
	t._drop_floor_studio(pair["guest_rig"])
	t._drop_floor_studio(pair["host_rig"])


## The host publishes; the guest applies, as the session would deliver it.
func _send(pair: Dictionary) -> Dictionary:
	var state: Dictionary = _as(Session.Role.HOST, func() -> Variant: return (pair["host"] as Studio).room_state())
	_as(Session.Role.GUEST, func() -> Variant:
		(pair["guest"] as Studio).apply_room(state, false)
		return null)
	return state


## An entry the host has and this build cannot make: a mod's piece.
func _gong(id := "gong_2") -> Dictionary:
	return {"id": id, "piece": "dawlings.gong", "at": {"pos": [0.8, 0.8], "yaw": 0.0}, "footprint": [0.3, 0.3],
			"uses": {"mod": "dawlings.gong", "version": "1.2.0", "title": "Gong"}}


## The host adds the stranger the way an install that has the mod would, bypassing the catalogue.
func _host_has_a_gong(host: Studio, id := "gong_2") -> void:
	var candidate := host.room_deltas.delta.copy()
	candidate.add_piece(_gong(id))
	host.room_deltas.commit(candidate)
	RoomFloor.follow(host, {}, false)


func guest_sees_the_host_and_cannot_edit() -> void:
	base._off()
	var pair := _pair()
	var host: Studio = pair["host"]
	var guest: Studio = pair["guest"]
	var home := _at(host.live_pieces[&"hoop"])
	check("both start with the whole studio", host.wheel != null and guest.wheel != null and host.sampler != null and guest.sampler != null)
	var said := [host.ask_layout("add", ["hoop", home.x + 1.2, home.y, 0.0]), host.ask_layout("remove", ["sampler"]),
			host.ask_layout("remove", ["wheel"]), host.ask_layout("move", ["hoop", home.x - 0.3, home.y, 0.0])]
	check("the host arranges the room (%s)" % [said], said == ["", "", "", ""])
	_host_has_a_gong(host)
	var state := _send(pair)
	var row: Dictionary = state["layout"]
	var id := StringName(host.room_deltas.delta.added[0]["id"])
	check("the row names every edit, and is a delta the guest can read", row["added"].size() == 2 and row["removed"].size() == 2 and row["moved"].has("hoop")
			and RoomDelta.problem(row) == "")
	check("the guest holds the host's delta, at the host's revision", guest.room_deltas.following and guest.room_deltas.delta.rev == int(row["rev"]))
	check("the guest stands the added hoop", guest.live_pieces.get(id) != null and guest.live_pieces[id].visible
			and guest.venue.get_node_or_null(RoomSync.node_name(id)) is Hoop)
	check("and not the sampler or the wheel", guest.sampler == null and guest.wheel == null)
	check("the hoop is where the host left it", _at(guest.live_pieces[&"hoop"]).distance_to(_at(host.live_pieces[&"hoop"])) < 0.02)
	check("the sections, the looper and the lyric board are still there", guest.sections != null and guest.looper != null and guest.lyric_board != null)
	var gap := guest.venue.get_node_or_null(RoomSync.node_name(&"gong_2")) as PieceGap
	check("the piece this build cannot make is a named plate in its place", gap != null and gap.words.begins_with("GONG not installed")
			and gap.words.contains("dawlings.gong 1.2.0") and gap.kind == &"dawlings.gong")
	check("at the host's spot", gap != null and absf((guest.venue.global_transform.affine_inverse() * gap.global_position).x - 0.0) < 100.0
			and gap.get_node("Words") is Label3D and (gap.get_node("Words") as Label3D).text == gap.words)
	check("the host shows the same plate, because it lacks the mod too", host.venue.get_node_or_null(RoomSync.node_name(&"gong_2")) is PieceGap)
	check("the plate is no trolley: nothing to push or walk into", guest.live_pieces.get(&"gong_2") == null)
	var kept: Array = [guest.room_deltas.delta.rev, guest.sampler, guest.wheel]
	var refusals := []
	for op: Array in [["remove", ["hoop"]], ["add", ["sampler", 0.0, 0.0, 0.0]], ["add", ["hoop", 0.0, 0.0, 0.0]], ["rotate", ["hoop", 1.0]],
			["reset", ["all"]], ["remove", ["gong_2"]], ["move", ["gong_2", 1.0, 1.0]]]:
		refusals.append(_as(Session.Role.GUEST, func() -> Variant: return guest.ask_layout(op[0], op[1])))
	check("every arranging op from the guest is host only (%s)" % [refusals], refusals.all(func(w: String) -> bool: return w == LayoutEdit.HOST_ONLY))
	check("and nothing of the guest's room changed", guest.room_deltas.delta.rev == kept[0] and guest.sampler == kept[1] and guest.wheel == kept[2]
			and guest.room_deltas.delta.added.size() == 2 and guest.room_deltas.writes == 0)
	var pushed: Vector2 = _at(guest.live_pieces[&"hoop"]) + Vector2(0.25, 0.0)
	var answer: Variant = _as(Session.Role.GUEST, func() -> Variant:
		return guest.layout_edit.answer("move", ["hoop", pushed.x, pushed.y, guest.live_pieces[&"hoop"].rotation.y], Session.local_peer_id))
	check("a guest may still push a piece with wheels", answer == HOST_OK and _at(guest.live_pieces[&"hoop"]).distance_to(pushed) < 0.02)
	check("the host can take the stranger out; the guest then has no plate", host.ask_layout("remove", ["gong_2"]) == ""
			and _send(pair).size() > 0 and guest.venue.get_node_or_null(RoomSync.node_name(&"gong_2")) == null
			and host.venue.get_node_or_null(RoomSync.node_name(&"gong_2")) == null)
	_drop(pair)
	base._off()


const HOST_OK := ""


func reset_returns_the_default() -> void:
	base._off()
	var pair := _pair()
	var host: Studio = pair["host"]
	var guest: Studio = pair["guest"]
	var home_hoop := _at(guest.live_pieces[&"hoop"])
	var home_sampler := _at(guest.live_pieces[&"sampler"])
	var at := _at(host.live_pieces[&"hoop"])
	host.ask_layout("add", ["hoop", at.x + 1.2, at.y, 0.0])
	host.ask_layout("move", ["hoop", at.x - 0.4, at.y, 0.0])
	host.ask_layout("remove", ["cassette_rack"])
	host.ask_layout("remove", ["looper"])
	host.ask_layout("remove", ["lyrics"])
	_host_has_a_gong(host)
	_send(pair)
	check("the guest follows the host: moved, taken out, added", _at(guest.live_pieces[&"hoop"]).distance_to(home_hoop) > 0.3 and guest.cassette_rack == null
			and guest.looper == null and guest.lyric_board == null and guest.room_deltas.delta.added.size() == 2)
	check("a reset from the guest is host only, and changes nothing", _as(Session.Role.GUEST, func() -> Variant: return guest.ask_layout("reset", ["all"])) == LayoutEdit.HOST_ONLY
			and guest.cassette_rack == null)
	check("one reset on the host", host.ask_layout("reset", ["all"]) == "" and host.room_deltas.delta.is_empty())
	_send(pair)
	check("takes the guest back to the default: every piece in the room again", guest.cassette_rack != null and guest.looper != null and guest.lyric_board != null
			and guest.sampler != null and guest.room_deltas.delta.added.is_empty() and guest.room_deltas.delta.removed.is_empty()
			and not guest.room_deltas.delta.moved.has("hoop"))
	check("at its own spots", _at(guest.live_pieces[&"hoop"]).distance_to(home_hoop) < 0.02 and _at(guest.live_pieces[&"sampler"]).distance_to(home_sampler) < 0.02)
	check("with no copy and no plate left", guest.venue.get_children().all(func(c: Node) -> bool: return not (c is PieceGap) and not String(c.name).begins_with("Copy_")))
	check("and the host's row is the default's", host.room_state()["layout"]["added"].is_empty() and host.room_state()["layout"]["removed"].is_empty())
	_drop(pair)
	base._off()


## The zone-held pieces come out and go back; a room with no zone for one refuses it; every kind in the catalogue round trips.
func zone_pieces_come_out_and_go_back() -> void:
	base._off()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var stood := {&"wheel": "wheel", &"sections": "sections", &"looper": "looper", &"lyrics": "lyric_board"}
	check("the catalogue lists the seven removable kinds, each titled", PieceCatalogue.kinds().size() == 7 and PieceCatalogue.kinds().all(func(k: StringName) -> bool: return PieceCatalogue.title(k) != ""))
	for kind: StringName in stood:
		check("%s stands in the studio" % kind, s.get(stood[kind]) != null)
		check("%s is taken out" % kind, s.ask_layout("remove", [String(kind)]) == "" and s.get(stood[kind]) == null and s.room_deltas.delta.is_removed(kind))
		check("%s cannot be taken out twice or moved" % kind, s.ask_layout("remove", [String(kind)]) != "" and s.ask_layout("move", [String(kind), 0.0, 0.0]) != "")
	var why: String = s.ask_layout("add", ["wheel", 0.0, 0.0, 0.0])
	check("put back with add: it asks for no spot, the zone is the place (%s)" % why, why == "" and s.wheel != null and not s.room_deltas.delta.moved.has("wheel"))
	check("reset puts back another", s.ask_layout("reset", ["sections"]) == "" and s.sections != null)
	check("and a piece that is there is not added again", s.ask_layout("add", ["looper", 0.0, 0.0, 0.0]) == "" and s.looper != null
			and s.ask_layout("add", ["wheel", 0.0, 0.0, 0.0]) != "")
	check("reset all puts back the rest", s.ask_layout("reset", ["all"]) == "" and s.looper != null and s.lyric_board != null and s.wheel != null and s.sections != null)
	# The rack, the sampler and the hoop still do what they did.
	for kind: StringName in [&"cassette_rack", &"sampler", &"hoop"]:
		check("%s comes out and goes back" % kind, s.ask_layout("remove", [String(kind)]) == "" and s.ask_layout("reset", [String(kind)]) == "")
	# A venue with no bricks table has no wheel to take out or put back.
	var bare := _venue_without(s, &"wheel")
	if bare != &"":
		s.set_venue(bare, false, 0)
		check("%s has no wheel: there is none to take out" % bare, s.wheel == null and s.ask_layout("remove", ["wheel"]).contains("no wheel"))
		check("and the layout does not carry one", s.room_deltas.delta.removed.is_empty())
	else:
		check("every venue has a place for the wheel (nothing to refuse)", true)
	s.set_venue(&"studio", false, 0)
	base._off()
	t._drop_floor_studio(rig)


## The first venue (arrangement 0) where `kind` of the live room has no spot, or &"".
func _venue_without(s: Studio, kind: StringName) -> StringName:
	for id: StringName in Venue.IDS:
		var v := Venue.make(id, 0)
		var spot: Variant = Stations.spot(v, kind)
		v.free()
		if spot == null:
			return id
	return &""


## A plate for what this build cannot make: never a crash, whatever the entry says.
func a_piece_this_build_cannot_make_is_a_plate() -> void:
	base._off()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	var odd := [_gong("gong_2"),
			{"id": "no_words", "piece": "lost.thing", "at": {"pos": [-0.5, 0.5], "yaw": 1.0}},
			{"id": "bad_foot", "piece": "x.y.z", "at": {"pos": [0.5, -0.5], "yaw": 0.0}, "footprint": ["a", NAN, 4]},
			{"id": "huge", "piece": "big.thing", "at": {"pos": [1.5, 0.5], "yaw": 0.0}, "footprint": [900.0, -900.0], "uses": 7}]
	var candidate := s.room_deltas.delta.copy()
	for entry: Dictionary in odd:
		candidate.add_piece(entry)
	s.room_deltas.commit(candidate)
	RoomFloor.follow(s, {}, false)
	var plates := s.venue.get_children().filter(func(c: Node) -> bool: return c is PieceGap)
	check("each odd entry is a plate, none crashes (%d)" % plates.size(), plates.size() == 4)
	check("named from the entry's title, else from the kind's last word", (s.venue.get_node("Copy_gong_2") as PieceGap).words.begins_with("GONG not installed")
			and (s.venue.get_node("Copy_no_words") as PieceGap).words == "THING not installed" and (s.venue.get_node("Copy_bad_foot") as PieceGap).words == "Z not installed")
	check("a footprint that is wrong or absurd is mended to something small", ((s.venue.get_node("Copy_huge/Pad") as MeshInstance3D).mesh as BoxMesh).size.x <= 6.01
			and ((s.venue.get_node("Copy_bad_foot/Pad") as MeshInstance3D).mesh as BoxMesh).size.x == PieceGap.DEFAULT_HALF.x * 2.0)
	check("syncing again changes nothing", (func() -> bool:
		RoomSync.sync(s)
		return s.venue.get_children().filter(func(c: Node) -> bool: return c is PieceGap).size() == 4).call())
	check("the plate is in the room's delta untouched, so nothing is lost", s.room_deltas.delta.added.size() == 4 and s.room_deltas.delta.added[0]["piece"] == "dawlings.gong")
	check("a plate cannot be moved, and says why", s.ask_layout("move", ["gong_2", 1.0, 1.0]).contains("not installed"))
	check("taking one out is one verb", s.ask_layout("remove", ["no_words"]) == "" and s.venue.get_node_or_null("Copy_no_words") == null and s.venue.get_node_or_null("Copy_gong_2") != null)
	s.set_venue(&"rooftop", false, 0)
	check("another room has none of this room's plates", s.venue.get_children().all(func(c: Node) -> bool: return not (c is PieceGap)))
	s.set_venue(&"studio", false, 0)
	check("and the studio has them again when it is back", s.venue.get_children().filter(func(c: Node) -> bool: return c is PieceGap).size() == 3)
	s.ask_layout("reset", ["all"])
	check("reset takes them all down", s.venue.get_children().all(func(c: Node) -> bool: return not (c is PieceGap)))
	base._off()
	t._drop_floor_studio(rig)


## The brief's proof without the room-maker: delete a piece in one venue, add one in another, restart; both are
## still there, and a guest sees them.
func deleting_and_adding_survives_a_restart() -> void:
	base._live()
	var rig: Dictionary = t._floor_studio()
	var s: Studio = rig["studio"]
	s.room_deltas.delay = 0.05
	check("the first venue has a wheel and a rack", s.venue.venue_id() == &"studio" and s.wheel != null and s.cassette_rack != null)
	check("delete in the first: the wheel and the cassette rack go", s.ask_layout("remove", ["wheel"]) == "" and s.ask_layout("remove", ["cassette_rack"]) == "")
	s.set_venue(&"rooftop", false, 0)
	check("the second venue still has them", s.wheel != null and s.cassette_rack != null and s.room_deltas.delta.is_empty())
	var home := _at(s.live_pieces[&"hoop"])
	var said: String = s.ask_layout("add", ["hoop", home.x + 1.2, home.y, 0.0])
	check("add in the second: another hoop (%s)" % said, said == "" and s.room_deltas.delta.added.size() == 1)
	var copy := StringName(s.room_deltas.delta.added[0]["id"])
	await t.get_tree().create_timer(0.3).timeout
	s.room_deltas.flush()
	s.room_deltas.wait()
	check("each room has its own file", FileAccess.file_exists(RoomDeltaFile.path_of("studio.0")) and FileAccess.file_exists(RoomDeltaFile.path_of("rooftop.0")))
	t._drop_floor_studio(rig)

	# A restart: a fresh studio, and a guest beside it.
	var pair := _pair()
	var host: Studio = pair["host"]
	var guest: Studio = pair["guest"]
	check("restarted in the first venue: no wheel, no rack, the rest of the room there", host.venue.venue_id() == &"studio" and host.wheel == null
			and host.cassette_rack == null and host.sampler != null and host.sections != null)
	check("the first venue has no copy of the hoop", host.venue.get_children().all(func(c: Node) -> bool: return not String(c.name).begins_with("Copy_")))
	_send(pair)
	check("a guest sees the deletion", guest.wheel == null and guest.cassette_rack == null and guest.sampler != null)
	host.set_venue(&"rooftop", false, 0)
	check("in the second venue the wheel and rack are there, and the added hoop", host.wheel != null and host.cassette_rack != null
			and host.venue.get_node_or_null(RoomSync.node_name(copy)) is Hoop and host.live_pieces[copy].visible)
	_send(pair)
	check("a guest sees the addition and the deletion's absence", guest.venue.venue_id() == &"rooftop" and guest.wheel != null and guest.cassette_rack != null
			and guest.venue.get_node_or_null(RoomSync.node_name(copy)) is Hoop and guest.live_pieces[copy].visible)
	check("the guest wrote no file of its own", guest.room_deltas.writes == 0)
	host.set_venue(&"studio", false, 0)
	_send(pair)
	check("and back in the first, both follow it", guest.wheel == null and guest.cassette_rack == null and guest.venue.get_node_or_null(RoomSync.node_name(copy)) == null)
	host.ask_layout("reset", ["all"])
	host.set_venue(&"rooftop", false, 0)
	host.ask_layout("reset", ["all"])
	await t.get_tree().create_timer(0.3).timeout
	host.room_deltas.flush()
	host.room_deltas.wait()
	_drop(pair)
	base._off()
