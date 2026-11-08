class_name RackHost
extends RefCounted

## The rack and the modular room: building the rack, standing the modular and the annex, the world sockets, `ask_rack` and its
## answer, recording from the rack, the modular's keys and play, and the pads and modular follow. Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the calls other code makes.

var _modular_held := {}

var _modular_last := -1

## Whether the rack's take under way began with the song's recording (and so ends with it).
var _rack_auto_take := false
## Whether guests were last sent a running rack, and how many sends there have been (every other one has the scopes).
var _live_sent := false
var _live_ticks := 0

# --- the modular room's rack (docs/architecture.md, "The modular room") ----------------------
#
# The patch is the room's row `rack` {patch: {modules, cables}, track} (RackPatch): every change to it
# is the one ask `rack` [op, args] (RackPatch.answer: add, remove, move, cable, pull, pull_one, knob,
# preset; and `track`, the track the rack sounds through), shown at once here and rolled back if the
# host refuses it, as the patchbay's `patch` is. The engine (native/rack, RackVoice) runs on the host
# alone, and what it plays goes through a track of the song (InputMonitor.feeds), so every guest hears
# it in the mix; a guest's keys at the rack reach it as notes the host plays (Presence.modular_heard).
# A knob turning is the ask too, at most Session.KNOBS_PER_SECOND, so the room hears a sweep as it is
# made. The rack is caught as audio on its track while the song records, or with its REC key.

## Where a player stands to play the rack, in its frame (m): in front of the stand, out to the seat and a step
## past it (3.0), and no wider than the case. Its jacks and knobs take the pointer
## only from here (and only where no other station's seat is nearer, `at_modular`), or while it is
## visited or brought.
const MODULAR_NEAR := 0.3

const MODULAR_FAR := 4.4

const MODULAR_SIDE := 3.6

## How often the stations' seats are worked out again for `at_modular` (s): a trolley pushed
## moves its seat, but not every frame's worth.
const MODULAR_SEATS_EVERY := 0.5

## Every station's seat here on the floor (global x, z), by id, for `at_modular`, and when they were
## worked out (ms) and for which venue.
var _modular_seats := {}

var _modular_seats_at := -1

var _modular_seats_venue := 0

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## A piece of furniture that can be pushed around the floor, standing where the layout puts it
## -- or where this participant last left it.
func _trolley(of_name: String, id: StringName, at: Vector3, heading_degrees: float) -> Trolley:
	var piece := Trolley.new()
	piece.name = of_name
	piece.piece_id = id
	piece.floor_plan = studio.floor_plan
	piece.position = at
	piece.rotation_degrees = Vector3(0, heading_degrees, 0)
	studio._authored_floor[id] = piece.transform
	var saved: Variant = studio.room_deltas.saved(id, Session.layout)
	if saved != null and not (id == &"levels" or id == &"tv"):
		piece.transform = saved
	piece.settled.connect(_on_trolley_settled.bind(piece))
	piece.moved.connect(studio.room_rows._on_trolley_moved.bind(piece))
	studio.studio_set.add_child(piece)
	studio.floor_plan.add_piece(piece)
	return piece


## A piece of furniture the control-room fragment places (`ControlRoom`), standing where it says
## in this room's width: `_trolley` with its authored spot and turn.
func _authored(of_name: String, id: StringName) -> Trolley:
	var args := ControlRoom.trolley_args(id, studio.room_width)
	return _trolley(of_name, id, args[0], args[1])


func _on_trolley_settled(piece: Trolley) -> void:
	var steered := piece.steered
	piece.steered = false
	var told := not studio._fitting and not studio._applying_room and not (steered and not Session.is_authority())
	if told and not Session.is_authority():
		# Wheeled here: it stays here, and the host is told; see apply_room.
		var verb := &"move_tablet" if studio.tablets.has(piece.piece_id) else &"move_piece"
		studio.room_rows._predict(verb, [piece.piece_id, piece.position.x, piece.position.z, piece.rotation.y])
	else:
		# Where the host's room has things is not where this guest keeps its own. A spot that is where the
		# room stands the piece is not a place anyone chose: in the next venue, or a wider room, it goes there.
		if not (studio._fitting or studio._showing_hosts_room or piece.built_in):
			studio.room_deltas.settle(piece.piece_id, piece.transform, RoomFloor.at_default(studio, piece), Session.layout)
		if told:
			studio.room_rows._publish_room()
	studio._looms_dirty = true


## The rack, its voice and its computer keys, made once with the surfaces; hung at the venue's spot
## (`_stand_the_modular`). None in AR.
func _build_rack() -> void:
	studio.add_child(studio.rack_files)
	studio.rack_files.restore(studio.rack_row)
	studio.rack_wall = RackWall.new()
	studio.rack_wall.name = "RackWall"
	studio.rack_wall.parks = false
	studio.rack_wall.pillars = false
	studio.rack_wall.within_reach = false
	studio.rack_wall.patch = studio.rack_row["patch"].duplicate(true)
	studio.studio_set.add_child(studio.rack_wall)
	studio.mount.register(studio.rack_wall)
	studio.rack_wall.edit_asked.connect(ask_rack)
	studio.rack_wall.knob_streamed.connect(func(id: String, k: String, v: float) -> void: ask_rack("knob", [id, k, v]))
	studio.rack_wall.knob_set.connect(func(id: String, k: String, v: float) -> void: ask_rack("knob", [id, k, v]))
	studio.rack_wall.told.connect(func(text: String) -> void: Session.notice.emit(text))
	studio.rack_wall.touched.connect(_on_rack_touched)
	studio.rack_wall.keys_asked.connect(func() -> void: _modular_play(not studio.modular_keys.is_active()))
	studio.rack_wall.track_asked.connect(func() -> void: ask_rack("track", [0]))
	studio.rack_wall.record_asked.connect(_rack_toggle_record)
	studio.rack_voice = RackVoice.new()
	studio.rack_voice.name = "RackVoice"
	studio.add_child(studio.rack_voice)
	studio.rack_voice.set_patch(studio.rack_row["patch"])
	# The world plays into the rack's WORLD module, worked out from the song clock and the rows as it
	# always was, the same on every machine; only the host's engine sounds it.
	studio.modular_world = ModularWorld.new()
	studio.modular_world.weather = func() -> Variant: return studio.weather
	studio.modular_world.has_venue = func() -> bool: return studio.venue_instrument != null and is_instance_valid(studio.venue_instrument)
	studio.add_child(studio.modular_world)
	studio.modular_world.fired.connect(func(events: Array) -> void: studio.rack_voice.play_world(events))
	studio.modular_keys = KeyCatcher.new()
	studio.modular_keys.name = "RackKeys"
	studio.modular_keys.base = 48
	studio.add_child(studio.modular_keys)
	studio.modular_keys.note_on.connect(func(pitch: int, velocity: int) -> void: _on_rack_touched(pitch, true, velocity))
	studio.modular_keys.note_off.connect(func(pitch: int) -> void: _on_rack_touched(pitch, false))
	studio.modular_keys.active_changed.connect(func(on: bool) -> void: studio.rack_wall.show_playing(on))
	if studio.presence != null:
		studio.presence.modular_heard = _on_rack_heard
	if Session.guest_midi != null:
		Session.guest_midi.key.connect(_on_modular_key)
	_show_rack(studio.rack_row)
	# A mod installed or removed (the MODS screen's reload, a mod a host shared): plates become modules and back.
	var reg := ModRegistry.ensure_current()
	var reshow := func() -> void:
		if is_instance_valid(studio) and studio.rack_wall != null and is_instance_valid(studio.rack_wall):
			_show_rack(studio.rack_row)
	reg.changed.connect(reshow)
	studio.tree_exiting.connect(func() -> void:
		if reg.changed.is_connected(reshow):
			reg.changed.disconnect(reshow), CONNECT_ONE_SHOT)


## The rack, hung at this venue's spot over the stand (Venue.modular_spot), the venue's rack giving way
## to it, in the venue's mood; put away, and out of F's round, where the venue has none.
func _stand_the_modular() -> void:
	if studio.rack_wall == null or not is_instance_valid(studio.rack_wall) or studio.venue == null:
		return
	var spot: Variant = Stations.spot(studio.venue, Modular.STATION)
	studio.rack_wall.visible = spot != null
	studio.rack_wall.set_mood(RackMood.palette(studio.venue.venue_id()))
	if spot == null:
		if studio.focus != null:
			if studio.focus.focused_id == studio.rack_wall.surface_id:
				studio.focus.release()
			studio.focus.surfaces.erase(studio.rack_wall)
		return
	_stand_the_annex()
	var at := studio.venue_switch._venue_to_set(spot as Transform3D)
	studio.mount.seat(studio.rack_wall.surface_id, func() -> Transform3D: return at)
	if studio.focus != null and not studio.focus.surfaces.has(studio.rack_wall):
		studio.focus.surfaces.append(studio.rack_wall)


## The modular room built onto this venue's live room: its walls, its doorway cut through the live
## room's wall, its lights in the venue's mood.
func _stand_the_annex() -> void:
	if studio.venue == null or studio.venue.get_node_or_null("ModularAnnex") != null:
		return
	AnnexSite.cut_the_wall(studio.venue)
	AnnexSite.clear_the_site(studio.venue)
	studio.modular_annex = ModularAnnex.build(studio.venue)
	studio.rack_wall.extra_controls.clear()
	for kn in studio.modular_annex.bench:
		studio.rack_wall.extra_controls.append(kn)
	studio.modular_annex.bench_turned.connect(func(k: int, v: float) -> void:
		if studio.rack_voice != null:
			studio.rack_voice.set_hand(k, v))
	studio.rack_wall._apply_reach()


## A world socket's press (WorldSocket.step_asked): its cable out of the input it is in and into the
## next free one `way` on, the rack's WORLD module put in the case first if it has none.
func _on_world_step(socket: StringName, way: int) -> void:
	var patch: Dictionary = studio.rack_row["patch"]
	if not RackPatch.has_type(patch, RackPatch.WORLD_MODULE):
		ask_rack("add", ["world", -1, 0])
		patch = studio.rack_row["patch"]
		if not RackPatch.has_type(patch, RackPatch.WORLD_MODULE):
			return
	var now := RackPatch.world_sink(patch, socket)
	var next := RackPatch.step_world(patch, socket, way)
	if now != "":
		var out := ""
		for c in patch["cables"]:
			if c[1] == now and RackPatch.type_of(patch, String(c[0]).get_slice(".", 0)) == RackPatch.WORLD_MODULE:
				out = c[0]
		if out != "":
			ask_rack("pull_one", [out, now])
	if next != "":
		ask_rack("cable", [RackPatch.world_out(patch, socket, next), next])
		Session.notice.emit("%s goes into %s on the rack. Press it again for the next free input."
				% [Modular.world_title(socket).capitalize(), next.replace(".", " ").to_upper()])


## Where a plug in the rack's input `path` sits, for a world socket's cable.
func _rack_jack(path: StringName) -> Variant:
	if studio.rack_wall == null or not is_instance_valid(studio.rack_wall) or not studio.rack_wall.is_visible_in_tree():
		return null
	var jack: RackJack = studio.rack_wall.jacks.get(String(path))
	return jack.plug_transform() if jack != null and jack.is_inside_tree() else null


## Each frame: every world socket in the room wired to its press and to the rack, and showing where
## the rack has its cable.
func _follow_world_sockets() -> void:
	var patch: Dictionary = studio.rack_row["patch"]
	for node in studio.get_tree().get_nodes_in_group(WorldSocket.SOCKETS):
		var socket := node as WorldSocket
		if socket == null:
			continue
		if not socket.has_meta(&"wired"):
			socket.set_meta(&"wired", true)
			socket.step_asked.connect(_on_world_step)
			socket.wall_jack = _rack_jack
		var into := StringName(RackPatch.world_sink(patch, socket.socket))
		if socket.into != into:
			socket.show_into(into)


## An edit of the rack, `op` and `args` as RackPatch.answer takes them (or `track` [step]): done on the
## host, asked by a guest and shown at once, or refused here in words where the host would refuse it.
func ask_rack(op: String, args: Array) -> void:
	if op == "knob" and args.size() == 3 and _turn_knob(String(args[0]), String(args[1]), float(args[2])):
		return
	if Session.is_authority():
		_answer_rack(op, args, Session.local_peer_id)
		return
	var row := studio.rack_row.duplicate(true)
	var refusal := _rack_apply(row, op, args)
	if refusal != "":
		Session.notice.emit(refusal)
		return
	if op == "knob":
		# A sweep is many asks and one room: the turn is shown here, and the host's room catches up.
		Session.ask_room(&"rack", [StringName(op), args])
		_show_rack(row)
		return
	if studio.room_rows._predict(&"rack", [StringName(op), args]) > 0:
		_show_rack(row)


## An edit of the room's layout, `op` and `args` as `LayoutEdit` takes them: done on the host, refused in
## words where the host would refuse it (and for a guest, which may only push). The refusal, or "".
func ask_layout(op: String, args: Array) -> String:
	return studio.layout_edit.ask(op, args)


## One knob turned: only that value is set, on the wall, in the voice and in the row. The patch is not
## copied, sanitized, diffed or laid out again (that cost ~60 ms a turn). False if the knob is not there,
## and the whole ask goes the long way to be refused in words.
func _turn_knob(id: String, k: String, v: float) -> bool:
	var patch: Dictionary = studio.rack_row.get("patch", {})
	if not RackPatch.set_knob(patch, id, k, v):
		return false
	v = RackPatch.knob_of(patch, id, k)
	studio.rack_files.note(studio.rack_row)
	if studio.rack_wall != null and is_instance_valid(studio.rack_wall):
		studio.rack_wall.show_knob(id, k, v)
	if Session.is_authority():
		if studio.rack_voice != null and is_instance_valid(studio.rack_voice):
			if not studio.rack_voice.running() and _rack_engaged():
				_rack_wake()
			studio.rack_voice.knob(id, k, v)
		studio.player_host._publish_room_soon()
	else:
		Session.ask_room(&"rack", [&"knob", [id, k, v]])
	return true


## `op` done to the row `row`; the refusal in words, or "".
func _rack_apply(row: Dictionary, op: String, args: Array) -> String:
	if op == "track":
		var tracks: Array = DAW.state.track_indices() if DAW.state != null else []
		tracks.sort()
		var at := tracks.find(int(row["track"]))
		var step := int(args[0]) if args.size() > 0 else 0
		if step == 0:
			# Round the tracks, and to none after the last.
			row["track"] = tracks[at + 1] if at + 1 < tracks.size() and at >= -1 else 0
			if at == -1 and not tracks.is_empty():
				row["track"] = tracks[0]
		elif tracks.has(step) or step < 0:
			row["track"] = maxi(step, 0)
		return ""
	return RackPatch.answer(row["patch"], op, args)


func _answer_rack(op: String, args: Array, from: int) -> void:
	var row := studio.rack_row.duplicate(true)
	var refusal := _rack_apply(row, op, args)
	if refusal != "":
		Session.tell(from, refusal)
		return
	_show_rack(row)
	studio.player_host._publish_room_soon()


## The room's rack as `row` has it, here: on the wall and in the voice, with a knob a hand here is still
## turning kept where the hand has it. On the host it wakes the engine for any edit.
func _show_rack(row: Dictionary) -> void:
	studio.rack_row = {"patch": RackPatch.sanitize(row.get("patch", {})), "track": int(row.get("track", 0))}
	studio.rack_files.note(studio.rack_row)
	var turning := studio.rack_wall.turning() if studio.rack_wall != null and is_instance_valid(studio.rack_wall) else {}
	var patch: Dictionary = studio.rack_row["patch"]
	for key: String in turning:
		RackPatch.set_knob(patch, key.get_slice(".", 0), key.get_slice(".", 1), float(turning[key]))
	if studio.rack_wall != null and is_instance_valid(studio.rack_wall):
		studio.rack_wall.show_patch(patch)
		studio.rack_wall.set_track(int(studio.rack_row["track"]), _rack_track_name(int(studio.rack_row["track"])))
	if studio.rack_voice != null and is_instance_valid(studio.rack_voice) and Session.is_authority():
		if studio.rack_voice.running() or _rack_engaged():
			_rack_wake()
		studio.rack_voice.set_patch(patch)
		studio.rack_voice.set_track(int(studio.rack_row["track"]))
	elif studio.rack_voice != null and is_instance_valid(studio.rack_voice):
		studio.rack_voice.patch = patch
	_offer_the_mods_in_use(patch)


## Host: the mods the patch uses are offered to guests who lack them (`ModSend`, docs/mods.md section 13).
func _offer_the_mods_in_use(patch: Dictionary) -> void:
	if Session.role != Session.Role.HOST or Session.mod_share == null or Session.participants.size() < 2:
		return
	var used: Array = []
	for use: Dictionary in (RackPatch.to_dict(patch)["uses"] as Dictionary).values():
		used.append(str(use.get("mod", "")))
	Session.mod_share.offer_used(used)


func _rack_track_name(index: int) -> String:
	if index <= 0 or DAW.state == null:
		return ""
	var t: MixState.TrackState = DAW.state.track(index, false)
	return t.name if t != null else ""


## Start the engine if it is not going (host only), the track chosen for it if none is: the first one.
func _rack_wake() -> void:
	if studio.rack_voice == null or not Session.is_authority() or studio.rack_voice.running():
		return
	if not RackEngine.available():
		return
	if studio.rack_voice.start():
		if int(studio.rack_row["track"]) <= 0 and DAW.state != null:
			var tracks: Array = DAW.state.track_indices()
			if tracks.is_empty():
				# A song with no track has nothing for the rack to sound through: it gets one.
				DAW.add_track(1, "Modular")
				tracks = DAW.state.track_indices()
			tracks.sort()
			if not tracks.is_empty():
				studio.rack_row["track"] = tracks[0]
		studio.rack_voice.set_patch(studio.rack_row["patch"])
		studio.rack_voice.set_track(int(studio.rack_row["track"]))
		_show_rack(studio.rack_row)


func _rack_engaged() -> bool:
	return at_modular() or (studio.modular_keys != null and studio.modular_keys.is_active())


## REC on the rack: a take of what it plays, on its track at the song position it began.
func _rack_toggle_record() -> void:
	if not Session.is_authority():
		Session.notice.emit("The host records the rack: its sound is in the mix on its track.")
		return
	_rack_wake()
	if studio.rack_voice.recording():
		var made := studio.rack_voice.record_stop()
		Session.notice.emit("Rack take: %s" % ("kept on track %d" % int(studio.rack_row["track"]) if str(made.get("error", "")) == ""
				else str(made["error"])))
	elif not studio.rack_voice.record_start(DAW.state.position_seconds if DAW.state != null else 0.0):
		Session.notice.emit("Pick a track for the rack to sound through first: TRACK.")
	if studio.rack_wall != null:
		studio.rack_wall.set_recording(studio.rack_voice.recording())


## A touch key, or the computer keys under PLAY: a note on this player's keys, to the rack.
func _on_rack_touched(pitch: int, down: bool, velocity := 100) -> void:
	if Session.guest_midi == null:
		return
	if down:
		Session.guest_midi.note_on(pitch, velocity, 0, 0.0, false, Modular.SOURCE)
	else:
		Session.guest_midi.note_off(pitch, 0, 0.0, false, Modular.SOURCE)


## A bandmate's note through the rack (Presence.modular_heard): the host plays it.
func _on_rack_heard(_peer: int, kind: int, pitch: int, velocity: int) -> void:
	if not is_instance_valid(studio):
		return
	if not Session.is_authority() or studio.rack_voice == null:
		return
	_rack_wake()
	if kind == Session.Note.ON:
		studio.rack_voice.note_on(pitch, velocity)
	elif kind == Session.Note.OFF:
		studio.rack_voice.note_off(pitch)


## A key played on this player's keys, from anywhere: KEYS' lamp.
func _on_modular_key(pitch: int, down: bool) -> void:
	if not is_instance_valid(studio):
		return
	if down:
		_modular_held[pitch] = true
		_modular_last = pitch
	else:
		_modular_held.erase(pitch)
	if studio.rack_wall != null and is_instance_valid(studio.rack_wall):
		studio.rack_wall.show_keys(_modular_last, not _modular_held.is_empty())


## The computer keys as the rack's, on or off, and said so the first time.
func _modular_play(on: bool) -> void:
	if studio.modular_keys == null or on == studio.modular_keys.is_active():
		return
	studio.modular_keys.set_active(on)
	if on:
		Session.notice.emit("Rack: A to ' play from %s, Z and X move the octave. Esc gives the keys back; PLAY takes them again."
				% studio.modular_keys.octave_name())


## Whether this player is at the rack: with it visited or brought, or standing in front of the
## stand (MODULAR_NEAR to MODULAR_FAR out, MODULAR_SIDE either side) where the rack's own seat is
## the nearest station's, so standing at a station beside it plays it
## and not the patch.
func at_modular() -> bool:
	if studio.rack_wall == null or not is_instance_valid(studio.rack_wall) or not studio.rack_wall.visible \
			or not studio.rack_wall.is_inside_tree():
		return false
	if studio.focus != null and studio.focus.focused_id == studio.rack_wall.surface_id:
		return true
	var me := studio.venue_switch._standing_at()
	var local := studio.rack_wall.global_transform.affine_inverse() * me
	if local.z <= MODULAR_NEAR or local.z >= MODULAR_FAR or absf(local.x) >= MODULAR_SIDE:
		return false
	var seats := _station_seats()
	if not seats.has(Modular.STATION):
		return true
	var floor := Vector2(me.x, me.z)
	var own := floor.distance_to(seats[Modular.STATION])
	for id: StringName in seats:
		if id != Modular.STATION and floor.distance_to(seats[id]) < own:
			return false
	return true


## Every station's seat here (Stations.seat, a headset's where this is one), on the floor in global
## space, by id: worked out again every MODULAR_SEATS_EVERY, or for another venue.
func _station_seats() -> Dictionary:
	var now := Time.get_ticks_msec()
	var here := studio.venue.get_instance_id() if studio.venue != null else 0
	if _modular_seats_venue == here and _modular_seats_at >= 0 \
			and now - _modular_seats_at < MODULAR_SEATS_EVERY * 1000.0:
		return _modular_seats
	_modular_seats_venue = here
	_modular_seats_at = now
	_modular_seats = {}
	if studio.venue == null:
		return _modular_seats
	var frame_of := studio.venue.global_transform if studio.venue.is_inside_tree() else studio.venue.transform
	var fits := studio.walker.fits if studio.walker != null else studio.station_host._station_fits()
	var hands := studio.medium != Presentation.Medium.SCREEN
	for id in studio.station_host.station_ids():
		var seat: Variant = Stations.seat(studio.venue, id, fits, hands)
		if seat != null:
			var p: Vector3 = frame_of * (seat as Transform3D).origin
			_modular_seats[id] = Vector2(p.x, p.z)
	return _modular_seats


## Whether this player stands at the sampling station (or has it focused): its pads then answer the
## computer keys and a MIDI keyboard's notes 36-51.
func at_tv() -> bool:
	if studio.tv == null or not is_instance_valid(studio.tv) or not studio.tv.is_inside_tree() or studio.tv.deck == null:
		return false
	if studio.focus != null and studio.focus.focused_id == studio.tv.surface_id:
		return true
	var local := studio.tv.global_transform.affine_inverse() * studio.venue_switch._standing_at()
	return local.z > 0.2 and local.z < 3.2 and absf(local.x) < 1.8


func _follow_pads() -> void:
	var here := at_tv()
	if studio.tv != null and is_instance_valid(studio.tv) and studio.tv.deck != null:
		if studio.tv.deck.engaged and not here:
			studio.tv.deck.stop_all()
		studio.tv.deck.engaged = here
	if Session.guest_midi != null:
		var sink := Callable(studio.tv.deck, "midi") if here else Callable()
		if Session.guest_midi.pad_sink != sink:
			Session.guest_midi.pad_sink = sink


func _follow_modular() -> void:
	if studio.rack_wall == null or not is_instance_valid(studio.rack_wall):
		return
	var here := at_modular()
	var engaged := here or (studio.modular_keys != null and studio.modular_keys.is_active())
	studio.rack_wall.within_reach = here
	if Session.guest_midi != null:
		Session.guest_midi.reach(Modular.SOURCE, engaged)
		Session.guest_midi.synth.redirect = studio.rack_voice if engaged and Session.is_authority() else null
	if not here and studio.modular_keys != null and studio.modular_keys.is_active() and not studio.rack_wall.visible:
		_modular_play(false)
	_follow_world_sockets()
	if studio.rack_voice == null or not is_instance_valid(studio.rack_voice):
		return
	if Session.role == Session.Role.GUEST:
		# The engine is the host's: a guest's wall shows what the host sends of it (RackLive).
		_show_live_rack()
		return
	if engaged and Session.is_authority():
		_rack_wake()
	if studio.rack_voice.running():
		studio.rack_wall.show_meters(studio.rack_voice.meters)
		studio.rack_wall.show_scopes(studio.rack_voice.scopes)
		studio.rack_wall.show_steps(studio.rack_voice.steps)
		studio.rack_wall.glow_with(studio.rack_voice.level, studio.rack_voice.hit)
		if studio.modular_annex != null and is_instance_valid(studio.modular_annex):
			studio.modular_annex.glow_with(studio.rack_voice.level, studio.rack_voice.hit)
			studio.modular_annex.show_levels(studio.rack_wall.module_levels(studio.rack_voice.meters))
			studio.modular_annex.show_scope(studio.rack_voice.scopes)
		studio.rack_wall.set_recording(studio.rack_voice.recording())
		_publish_live_rack(true)
		# The song recording catches the rack: begun at the take's start, kept where it ends.
		if DAW.state != null and int(studio.rack_row["track"]) > 0:
			if DAW.state.recording and not studio.rack_voice.recording() and DAW.state.playing:
				_rack_auto_take = studio.rack_voice.record_start(DAW.state.position_seconds)
			elif not DAW.state.recording and studio.rack_voice.recording() and _rack_auto_take:
				studio.rack_voice.record_stop()
				_rack_auto_take = false
	else:
		_publish_live_rack(false)
		studio.rack_wall.glow_with(0.0, 0.0)
		if studio.modular_annex != null and is_instance_valid(studio.modular_annex):
			studio.modular_annex.glow_with(0.0, 0.0)


## The host's rack to the guests, as the volatile entry `/rack/live` (`RackLive`): every follow while it runs, once
## when it stops. Nothing is built when nobody is here to be sent it.
func _publish_live_rack(running: bool) -> void:
	if not Session.is_authority() or Session.participants.size() <= 1 or DAW.backend == null:
		return
	if not running:
		if _live_sent:
			_live_sent = false
			DAW.backend.record_for_replication(RackLive.ADDRESS, [false])
		return
	_live_sent = true
	_live_ticks += 1
	var voice := studio.rack_voice
	DAW.backend.record_for_replication(RackLive.ADDRESS, RackLive.pack(voice.level, voice.hit, voice.meters,
			voice.steps, voice.scopes, _live_ticks % 2 == 0))


## A guest's wall, its annex and its lights from what the host sent of the rack: the meters, the sequencer's step,
## the scopes and the glow.
func _show_live_rack() -> void:
	var live := live_rack()
	if studio.rack_wall == null or not is_instance_valid(studio.rack_wall):
		return
	studio.rack_wall.show_meters(live.get("meters", {}))
	studio.rack_wall.show_scopes(live.get("scopes", {}))
	studio.rack_wall.show_steps(live.get("steps", {}))
	studio.rack_wall.glow_with(float(live.get("level", 0.0)), float(live.get("hit", 0.0)))
	if studio.modular_annex != null and is_instance_valid(studio.modular_annex):
		studio.modular_annex.glow_with(float(live.get("level", 0.0)), float(live.get("hit", 0.0)))
		studio.modular_annex.show_levels(studio.rack_wall.module_levels(live.get("meters", {})))
		studio.modular_annex.show_scope(live.get("scopes", {}))


## What the host's rack is doing as a guest has it (`RackLive`), `{}` for none: nothing heard lately, or the rack
## is not running.
func live_rack() -> Dictionary:
	return RackLive.fresh(DAW.state.rack_live) if DAW.state != null else {}


## How loud the modular room is now, 0..1: the engine's own level on the host, the host's as sent on a guest.
## The room's lights follow it as well as the mix, for a rack that sounds where the mix does not hear it.
func rack_level() -> float:
	if Session.role == Session.Role.GUEST:
		return float(live_rack().get("level", 0.0))
	var voice := studio.rack_voice
	if voice == null or not is_instance_valid(voice) or not voice.running():
		return 0.0
	return voice.level

