class_name RoomRows
extends RefCounted

## The room's shared state on the wire: `room_state` (what the host publishes), `apply_room` (what a guest adopts), and the
## verbs a player asks of the room (`_on_room_asked`), with the prediction and motion that go with them. Moved out of
## `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the calls other code makes.

var _motion_sent_msec := 0

## The pads' row (PadShare): what the host's sampling station holds, for the room.
var pads_row := {}

var _pads_rev := -1

var _pads_file := ""

const MOTION_MSEC := 50

## The stands someone else is pushing, by id: what their push sent, played back.
var _pushed_trails := {}

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


# --- the shared room -----------------------------------------------------------------------
#
# The venue and the plugins out on stands are facts about the room, like where the desk is, so
# in a session they are the host's: one room, everyone in it. A guest asks and is shown; its own
# venue and tablets wait in its profile for when it is on its own again.

## The room as it stands here, in the shape Session.room carries.
func room_state() -> Dictionary:
	var out := {}
	for id in studio.tablets:
		var stand: Trolley = studio.tablets[id][0]
		var t: PluginTablet = studio.tablets[id][1]
		out[id] = [t.track_index, t.fx_index, t.fx_name, stand.position.x, stand.position.z,
				stand.rotation.y]
	var pulled := {}
	for id in studio.track_racks:
		var stand: Trolley = studio.track_racks[id][0]
		pulled[id] = [(studio.track_racks[id][1] as RackSurface).track_index, stand.position.x, stand.position.z,
				stand.rotation.y]
	var placed := {}
	if studio.mount != null:
		for surface_id in studio.mount.mounted_ids():
			if not studio.mount.seats.has(surface_id):
				placed[surface_id] = studio.mount.studio_home(surface_id)
	return {"venue": studio.venue.venue_id() if studio.venue != null else Venue.IDS[0],
			"variant": studio.venue.variant if studio.venue != null else 0, "tablets": out,
			"layout": RoomFloor.row(studio), "made_room": MadeRooms.row_of(studio.venue.venue_id()) if studio.venue != null else {},
			"placed": placed, "items": studio.items.state() if studio.items != null else {},
			"made": studio.items.made_ids() if studio.items != null else [],
			"patches": studio.patches.duplicate(true), "on_air": studio.on_air.duplicate(), "board": studio.board_source,
			"track_racks": pulled, "jacks": studio.jacks.state() if studio.jacks != null else {},
			"ropes": studio.stage.ropes.duplicate() if studio.stage != null else {},
			"sampler": studio.sampler.armed_by if studio.sampler != null and is_instance_valid(studio.sampler) else 0,
			"weather": studio.weather_listening, "looper": studio.looper_row.duplicate(),
			RackPatch.ROW: RackGaps.published(studio.rack_row),
			"tv": studio.tv.row() if studio.tv != null and is_instance_valid(studio.tv) else {}, "pads": pads_row.duplicate(true)}


## The host's TV changed what it plays: the room is told.
func _on_tv_changed() -> void:
	if Session.role == Session.Role.HOST:
		_publish_room()


## The host's pads changed: the sample written once (and offered to guests), the row remade.
func _on_pads_changed() -> void:
	if Session.role != Session.Role.HOST or studio.tv == null or not is_instance_valid(studio.tv):
		return
	var bank := studio.tv.bank
	if bank.revision != _pads_rev:
		_pads_rev = bank.revision
		_pads_file = PadShare.write(bank)
	var made := PadShare.row(bank, _pads_file)
	if made != pads_row:
		pads_row = made
		_publish_room()


## A guest asked the host's TV for something (its FIND, PLAY, a skip): the host does it.
func _answer_tv(video: String, playing: bool, at: float) -> void:
	if studio.tv != null and is_instance_valid(studio.tv):
		studio.tv.apply(video, playing, at)


## A guest: the room's TV and pads, as the host has them.
func _follow_tv(state: Dictionary) -> void:
	if studio.tv == null or not is_instance_valid(studio.tv):
		return
	studio.tv.guest = Session.role == Session.Role.GUEST
	if not studio.tv.guest:
		return
	if state.has("tv"):
		studio.tv.follow(state["tv"])
	if state.has("pads") and state["pads"] != studio._pads_followed:
		studio._pads_followed = (state["pads"] as Dictionary).duplicate(true)
		if not studio.tv.own_pads:
			_follow_pads_row(studio._pads_followed)


func _follow_pads_row(row: Dictionary) -> void:
	var file := str(row.get("file", ""))
	if file == "" or file == studio._pads_loaded or studio.tv.deck == null:
		PadShare.set_settings(studio.tv.bank, row)
		if studio.tv.deck != null:
			studio.tv.deck.refresh()
		return
	var have := Session.files.fetched_path(file) if Session.files != null else ""
	if have == "":
		if Session.files != null:
			Session.files.fetch(file)
			if not Session.files.fetched.is_connected(_on_pads_fetched):
				Session.files.fetched.connect(_on_pads_fetched)
		return
	_pads_fetched_into(file, have, row)


func _on_pads_fetched(file: String, path: String) -> void:
	if not is_instance_valid(studio):
		return
	if file == str(studio._pads_followed.get("file", "")):
		_pads_fetched_into(file, path, studio._pads_followed)


func _pads_fetched_into(file: String, path: String, row: Dictionary) -> void:
	if studio.tv == null or not is_instance_valid(studio.tv) or studio.tv.deck == null:
		return
	var stream := AudioStreamWAV.load_from_file(path)
	if stream == null:
		return
	studio._pads_loaded = file
	PadShare.apply(studio.tv.bank, row, stream)
	studio.tv.deck.refresh()


func _publish_room() -> void:
	if Session.role == Session.Role.HOST and not studio._applying_room:
		Session.publish_room(room_state())


func _on_room_changed() -> void:
	if not is_instance_valid(studio):
		return
	if not Session.is_authority():
		apply_room(Session.room, true)


## Make this room the one `state` describes -- its venue, the same stands in the same places, the
## desk where it stands -- and then put this guest's own unanswered moves back on top.
##
## That last part is the prediction. A guest does what it asked for at once, on its own screen,
## and keeps a note of it until the host's room says the ask was answered: until then the note
## wins over the room, so a stand does not flick back to where it was because a room published a
## moment before the ask arrived crossed it on the wire. Once answered, the room is the truth --
## and if the host would not do it, the stand goes back. That is the rollback.
##
## `glide` rolls things to where the room has them, as if pushed, instead of putting them there.
func apply_room(state: Dictionary, glide := false) -> void:
	studio._applying_room = true
	studio._showing_hosts_room = true
	var answered := int((state.get("acks", {}) as Dictionary).get(Session.local_peer_id, 0))
	studio._predictions = studio._predictions.filter(func(p: Dictionary) -> bool: return int(p["seq"]) > answered)
	var pending_open := {}
	var pending_close := {}
	var pending_move := {}
	var pending_place := {}
	var pending_items := {}
	for p in studio._predictions:
		match p["verb"]:
			&"put_item", &"home_item", &"throw_item", &"wear_item", &"pocket_item", &"slot_item", &"give":
				pending_items[p["args"][0]] = true
			&"patch", &"on_air", &"plug", &"rope", &"make", &"paste", &"sampler", &"weather", \
					&"looper", &"looper_layer", \
					&"rack", &"tv": pass
			&"open_tablet", &"open_track_rack": pending_open[p["id"]] = true
			&"close_tablet", &"close_track_rack": pending_close[p["args"][0]] = true
			&"move_tablet", &"move_piece": pending_move[p["args"][0]] = true
			&"place_surface": pending_place[p["args"][0]] = p["args"][1]

	# A room the host made is a layout this guest has not got: held in memory, before the venue is asked for.
	MadeRooms.adopt(state.get("made_room"))
	studio.room_deltas.adopt(state.get("layout"))
	var id_wanted := StringName(state.get("venue", &""))
	var variant_wanted := Venue.known_variant(id_wanted, int(state.get("variant", 0)))
	if studio.venue != null and Venue.is_known(id_wanted) \
			and (studio.venue.venue_id() != id_wanted or studio.venue.variant != variant_wanted):
		studio.venue_switch.set_venue(id_wanted, false, variant_wanted)

	var wanted: Dictionary = state.get("tablets", {})
	for id in studio.tablets.keys():
		var t: PluginTablet = studio.tablets[id][1]
		var entry: Variant = wanted.get(id)
		if entry != null and int(entry[0]) == t.track_index and int(entry[1]) == t.fx_index:
			continue
		if pending_open.has(id):
			continue
		# The host's answer to this guest's pull: the same stand, under the name the host gave
		# it, rather than this one taken away and that one put up in its place.
		var named := _hosts_name_for(wanted, t.track_index, t.fx_index)
		if named != StringName() and not studio.tablets.has(named):
			_rename_tablet(id, named)
			continue
		studio.tablet_host._take_down_tablet(id)

	if studio.floor_plan != null:
		for id in wanted:
			if pending_close.has(id):
				continue
			var entry: Array = wanted[id]
			if not studio.tablets.has(id):
				studio.tablet_host._build_tablet(id, int(entry[0]), int(entry[1]), str(entry[2]))
				(studio.tablets[id][0] as Trolley).place(Vector2(float(entry[3]), float(entry[4])), float(entry[5]))
			elif not pending_move.has(id):
				_follow_room(studio.tablets[id][0], float(entry[3]), float(entry[4]), float(entry[5]), glide)
		RoomFloor.follow(studio, pending_move, glide)

	if studio.floor_plan != null and state.has("track_racks"):
		var racks_wanted: Dictionary = state["track_racks"]
		for id in studio.track_racks.keys():
			var entry: Variant = racks_wanted.get(id)
			var mine: RackSurface = studio.track_racks[id][1]
			if (entry != null and int(entry[0]) == mine.track_index) or pending_open.has(id):
				continue
			studio.tablet_host._take_down_track_rack(id)
		for id in racks_wanted:
			if pending_close.has(id):
				continue
			var entry: Array = racks_wanted[id]
			if not studio.track_racks.has(id):
				# The host's answer to this guest's own pull: its predicted one goes, the host's
				# takes its place.
				for mine_id in studio.track_racks.keys():
					if (studio.track_racks[mine_id][1] as RackSurface).track_index == int(entry[0]) \
							and not racks_wanted.has(mine_id):
						studio.tablet_host._take_down_track_rack(mine_id)
				studio.tablet_host._build_track_rack(id, int(entry[0]))
				(studio.track_racks[id][0] as Trolley).place(Vector2(float(entry[1]), float(entry[2])), float(entry[3]))
			elif not pending_move.has(id):
				_follow_room(studio.track_racks[id][0], float(entry[1]), float(entry[2]), float(entry[3]), glide)

	if studio.mount != null:
		var placed: Dictionary = (state.get("placed", {}) as Dictionary).duplicate()
		placed.merge(pending_place, true)
		studio.mount.share_studio(placed, Studio.GLIDE_SECONDS if glide else 0.0)
	if studio.items != null and state.has("made"):
		# The made items the room names, real here from the rows the host sent first.
		studio.items.apply_made(state["made"])
	if studio.items != null and state.has("items"):
		studio.items.apply(state["items"], pending_items)
	studio.item_host._settle_makes(answered)
	if state.has("on_air"):
		studio.on_air = (state["on_air"] as Array).duplicate()
		for p in studio._predictions:
			if p["verb"] == &"on_air":
				studio.patch_host._set_on_air(Session.local_peer_id, p["args"][0], false)
	if state.has("patches"):
		studio.patches = (state["patches"] as Dictionary).duplicate(true)
		# This guest's plugs it has moved and not heard back about, on top.
		for p in studio._predictions:
			if p["verb"] == &"patch":
				studio.patch_host._set_patch(Session.local_peer_id, p["args"][0], p["args"][1], false)
		studio.patch_host._show_patches()
	if studio.jacks != null and state.has("jacks"):
		var rows: Dictionary = (state["jacks"] as Dictionary).duplicate()
		# The host's word alone first: a chord hand it now says goes into a bandmate sends again.
		studio.jacks.answered(rows)
		# This guest's plugs it has not heard back about, on top: an empty sink, unplugged.
		for p in studio._predictions:
			if p["verb"] == &"plug":
				rows[String(p["args"][0])] = String(p["args"][1])
		studio.jacks.set_patch(rows)
	if studio.stage != null and state.has("ropes"):
		# The stage table keeps its own unanswered ties and cuts on top.
		studio.stage.apply_ropes(state["ropes"], answered)
	_follow_tv(state)
	if studio.sampler != null and is_instance_valid(studio.sampler) and state.has("sampler") \
			and not studio._predictions.any(func(p): return p["verb"] == Sampler.VERB):
		# Once its press is answered, the host's word: on for whoever the room says, or off.
		studio.sampler.armed_by = int(state["sampler"])
	if state.has("weather") and not studio._predictions.any(func(p): return p["verb"] == Weather.VERB):
		# Once its press is answered, the host's word: LISTEN or OFF.
		studio.item_host._show_weather(bool(state["weather"]))
	if state.has("looper") and not studio._predictions.any(func(p): return p["verb"] == Looper.VERB or p["verb"] == Looper.LAYER_VERB):
		# Once its slaps and layers are answered, the host's word: who is looping, from which bar.
		studio.item_host._show_looper(state["looper"])
	if state.has(RackPatch.ROW):
		# The host's rack, with this guest's own edits it has not heard back about on top.
		var row: Dictionary = (state[RackPatch.ROW] as Dictionary).duplicate(true)
		row["patch"] = RackPatch.sanitize(row.get("patch", {}))
		for p in studio._predictions:
			if p["verb"] == &"rack":
				studio.rack_host._rack_apply(row, String(p["args"][0]), p["args"][1])
		studio.rack_host._show_rack(row)
	if state.has("board") and not studio._predictions.any(func(p): return p["verb"] == &"board_source"):
		studio.roll_room._show_board(StringName(state["board"]))
	studio._applying_room = false
	studio._looms_dirty = true


## A piece to where the room has it -- unless a hand here has hold of it, which wins.
func _follow_room(t: Trolley, x: float, z: float, heading: float, glide: bool) -> void:
	if t.held_by != null:
		return
	var at := Vector2(x, z)
	if at.is_equal_approx(Vector2(t.position.x, t.position.z)) and is_equal_approx(t.rotation.y, heading):
		return
	if glide:
		t.roll_to(at, heading)
	else:
		t.steered = true
		t.place(at, heading)


func _hosts_name_for(wanted: Dictionary, track: int, fx: int) -> StringName:
	for id in wanted:
		if int(wanted[id][0]) == track and int(wanted[id][1]) == fx:
			return id
	return StringName()


## The same stand, known by another name: the one the host gave the stand this guest put out.
func _rename_tablet(from: StringName, to: StringName) -> void:
	var stand: Trolley = studio.tablets[from][0]
	var tablet: PluginTablet = studio.tablets[from][1]
	studio.tablets.erase(from)
	studio.tablets[to] = [stand, tablet]
	stand.piece_id = to
	tablet.surface_id = to
	studio._authored_floor[to] = studio._authored_floor.get(from, stand.transform)
	studio._authored_floor.erase(from)
	if studio.focus != null and studio.focus.focused_id == from:
		studio.focus.focused_id = to
	for p in studio._predictions:
		if p["verb"] != &"open_tablet" and p["args"].size() > 0 and p["args"][0] == from:
			p["args"][0] = to


## A guest's ask, sent, and done here at once. See apply_room.
func _predict(verb: StringName, args: Array, id := StringName()) -> int:
	var seq := Session.ask_room(verb, args)
	if seq > 0:
		studio._predictions.append({"seq": seq, "verb": verb, "args": args, "id": id})
	return seq


## A stand being pushed by a hand here, told to everyone else a few dozen times a second so
## theirs rolls after it. The settled place is sent as an ask when it comes to rest.
func _on_trolley_moved(piece: Trolley) -> void:
	studio._looms_dirty = true
	if piece.held_by == null or not Session.is_networked():
		return
	var now := Time.get_ticks_msec()
	if now - _motion_sent_msec < MOTION_MSEC:
		return
	_motion_sent_msec = now
	Session.send_motion(piece.piece_id, piece.position.x, piece.position.z, piece.rotation.y)


## Someone else's hand on a stand: roll ours after it. Not one this guest is pushing, nor one it
## has let go of and not yet heard the host answer for.
func _on_room_motion(id: StringName, x: float, z: float, heading: float, _from: int) -> void:
	if not is_instance_valid(studio):
		return
	var t := _floor_piece(id)
	if t == null or t.held_by != null:
		return
	for p in studio._predictions:
		if (p["verb"] == &"move_piece" or p["verb"] == &"move_tablet") and p["args"][0] == id:
			return
	# Kept and played back a moment behind (_drive_pushed), rather than sprung after.
	var trail: PoseTrail = _pushed_trails.get(id)
	if trail == null:
		trail = PoseTrail.new()
		_pushed_trails[id] = trail
	trail.push(PoseTrail.now(), Transform3D(Basis(Vector3.UP, heading), Vector3(x, 0, z)))


func _drive_pushed() -> void:
	var now := PoseTrail.now()
	for id in _pushed_trails.keys():
		var trail: PoseTrail = _pushed_trails[id]
		var t := _floor_piece(id)
		if t == null or t.held_by != null:
			_pushed_trails.erase(id)
			continue
		var pose := trail.sample(now)
		var heading := pose.basis.get_euler().y
		if trail.settled(now):
			# Let go over there: the spring brings it the last of the way and it settles.
			_pushed_trails.erase(id)
			t.roll_to(Vector2(trail.latest().origin.x, trail.latest().origin.z), trail.latest().basis.get_euler().y)
			continue
		t.drive_to(Vector2(pose.origin.x, pose.origin.z), heading)


## The host, answering someone's ask. The same calls the host's own hands make, so the room is
## then published the way any change to it is.
func _on_room_asked(verb: StringName, args: Array, from: int) -> void:
	if not is_instance_valid(studio):
		return
	match verb:
		&"look_solo":
			studio.signal_views._on_look_solo_asked(args[0], args[1], from)
		&"patch":
			# A monitor only while its performer is on air: off air, there is no socket to plug into.
			var into := PersonalMix.monitor_of(args[1])
			if PersonalMix.valid_socket(args[1]) and (into == 0 or into in studio.on_air):
				studio.patch_host._set_patch(from, args[0], args[1])
				studio.player_host._publish_room_soon()
		&"on_air":
			studio.patch_host._set_on_air(from, args[0])
			studio.player_host._publish_room_soon()
		&"plug":
			# The hand that holds it, or anyone while it is home; into a track there is or a
			# bandmate in the room; and whoever a jack goes into may take it out.
			if studio.jacks != null and studio.patch_host._plug_refusal(args[0], args[1], from) == "":
				var was := studio.jacks.sink_of(args[0])
				studio.jacks.plug(args[0], args[1])
				studio.patch_host._tell_plugged(args[0], was, args[1], from)
				studio.player_host._publish_room_soon()
		&"open_tablet":
			if studio.floor_plan != null and DAW.state.fx(args[0], args[1], false) != null:
				studio.tablet_host.open_tablet(args[0], args[1], args[2], Vector2(args[3], args[4]))
		&"close_tablet":
			studio.tablet_host.close_tablet(args[0])
		&"move_tablet", &"move_piece":
			var piece := _floor_piece(args[0])
			if piece != null:
				piece.place(Vector2(args[1], args[2]), args[3])
		&"place_surface":
			if studio.mount != null and studio.mount.mounted_ids().has(args[0]) and not studio.mount.seats.has(args[0]):
				_place_in_studio(args[0], args[1])
		&"put_item", &"home_item", &"throw_item", &"wear_item", &"pocket_item":
			var item: Item = studio.items.items.get(args[0]) if studio.items != null else null
			if item == null or not _may_put(item, from):
				return
			match verb:
				&"wear_item":
					# Only something in their hand goes on their head.
					if item.state == Item.State.HELD:
						item.set_worn(args[1])
				&"pocket_item":
					# Only something they have goes in their pocket, and only one of theirs.
					if item.state == Item.State.HELD and args[1] >= -1 and args[1] < Pockets.COUNT:
						item.set_pocket(args[1])
				&"put_item": studio.items.lay(item, Vector2(args[1], args[2]), args[3])
				&"home_item": studio.items.retire(item)
				&"throw_item": studio.items.fly(item, args[1], args[2], args[3], from)
		&"take_personal":
			if studio.items != null:
				studio.items.take_personal(args[0], from)
		&"make":
			# A guest's pull: the host packs the clip from its own song, mints it, and it is in
			# their hand -- or it is refused, and they are told why.
			var made := studio.item_host._mint_for(args[0], args[1], from)
			if made != null:
				studio.item_host._hand_made(made, from)
		&"slot_item":
			var item: Item = studio.items.items.get(args[0]) if studio.items != null else null
			if item != null and _may_put(item, from) and not studio.items.slot(item, args[1], args[2]):
				Session.tell(from, studio.items.slot_refusal(item, args[1], args[2]))
		&"give":
			var item: Item = studio.items.items.get(args[0]) if studio.items != null else null
			if item != null and Session.holder_of(item.network_key()) == from and args[1] != from \
					and Session.participants.has(args[1]):
				studio.item_host._give(item, args[1], from)
		&"paste":
			# A guest's paste: the cassette in its hand, by id; the clip is the host's own row.
			var cassette := studio.items.items.get(args[0]) as CassetteItem if studio.items != null else null
			if cassette == null or Session.holder_of(cassette.network_key()) != from:
				Session.tell(from, "That cassette is not in your hand here yet: pick it up again and paste.")
			else:
				studio.item_host.paste_cassette(cassette, args[1], args[2], from)
		&"open_track_rack":
			if studio.floor_plan != null and DAW.state.tracks.has(args[0]):
				studio.tablet_host.open_track_rack(args[0], Vector2(args[1], args[2]))
		&"close_track_rack":
			studio.tablet_host.close_track_rack(args[0])
		&"harmony":
			# A guest's SET on the fifths wheel: written at the bar they chose, if it reads.
			FifthsWheel.answer(args[0], args[1])
		&"rope":
			# A guest's rope tied or cut on its stage table: the row says what the rope added.
			if studio.stage != null:
				studio.stage.answer_rope(args[0], args[1], args[2])
		&"tv":
			# A guest's wish for the TV: the video, whether it plays, where. The host does it.
			_answer_tv(args[0], args[1], args[2])
		&"sampler":
			# A guest's REC: on for their next sound, or off.
			studio.sampler_host._arm_sampler(args[0], from)
		&"weather":
			# A guest's press on the weather's switch: LISTEN or OFF, for everyone.
			studio.item_host._set_weather(args[0])
		&"looper":
			# A guest's slap on the looper's pad: armed for them, or refused while somebody else loops.
			studio.item_host._answer_looper(args[0], args[1], from)
		&"looper_layer":
			# A guest's finished layer: onto a track of theirs in the LOOPER folder.
			studio.item_host._write_looper_layer(args[0], args[1], args[2], from)
		&"rack":
			# A guest's edit of the rack, or its track: the room's row, or told why not.
			studio.rack_host._answer_rack(String(args[0]), args[1], from)
		&"layout":
			studio.layout_edit.answer(String(args[0]), args[1], from)
		&"scratch":
			# A guest's scratch on the platter, for the sampler: of what is in its slot here, and
			# a path that fits (Varispeed.fits: bounded in steps and in time). Rendered only when
			# REC would catch it (_sample_scratch), so an ask with REC off costs the host nothing.
			var path: PackedFloat32Array = args[1]
			var there: Item = studio.items.in_slot(Platter.HOLDER, 0) if studio.items != null else null
			if there != null and there.id == args[0] and there is CassetteItem and Varispeed.fits(path):
				studio.sampler_host._sample_scratch(there as CassetteItem, path, from)
		&"board_source":
			if studio.roll_room.board_sources().has(args[0]):
				studio.roll_room._show_board(args[0])
				_publish_room()


## Only whoever has an item may put it down: the hand the host's table says has it, or anyone
## when nobody does. Not the guest whose pick-up lost a race, still putting down what it thought
## it had.
func _may_put(item: Item, from: int) -> bool:
	var holder := Session.holder_of(item.network_key())
	return holder == 0 or holder == from


func _floor_piece(id: StringName) -> Trolley:
	if studio.floor_plan == null:
		return null
	for piece in studio.floor_plan.pieces:
		var t := piece as Trolley
		if t != null and is_instance_valid(t) and t.piece_id == id:
			return t
	return null


## Gear that stands on nothing, put somewhere in the studio for the room: remembered as the
## host's own placement, stood there if it is standing in the studio now, and the room told.
func _place_in_studio(surface_id: StringName, where: Transform3D) -> void:
	Session.layout.set_transform(surface_id, Presentation.Mode.STUDIO, where)
	Session.layout.save()
	studio.mount.share_studio({})
	if surface_id == &"console":
		studio.venue_switch._fit_room_to_session()
	_publish_room()


## The mount's question when the desk is put down in the studio: a guest sends it to the host
## and keeps nothing; the host saves it as ever and tells the room once it has.
func _on_studio_placed(surface_id: StringName, where: Transform3D) -> bool:
	if Session.is_authority():
		_publish_room.call_deferred()
		return false
	if _predict(&"place_surface", [surface_id, where]) > 0:
		var placed := studio.mount.shared_studio.duplicate()
		placed[surface_id] = where
		studio.mount.shared_studio = placed
	return true
