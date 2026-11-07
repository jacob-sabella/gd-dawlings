class_name SignalViews
extends RefCounted

## The signal view, the look-solo and the trace: what a player looks at lights up, soloing by looking, tracing a signal
## back to its source. Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the studio, which
## delegates the calls other code makes.

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## Whether this player sees the signal: the glasses on this player's own head, or X.
func signal_view_on() -> bool:
	if studio.signal_key_on:
		return true
	for hand in studio.get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor != null and is_instance_valid(interactor.worn) and interactor.worn is SignalGlassesItem:
			return true
	return false


## X at a desk: the view on or off, glasses or none. Said, with what it shows and the next key.
func toggle_signal_view() -> void:
	studio.signal_key_on = not studio.signal_key_on
	if signal_view_on():
		Session.notice.emit("Seeing the signal: pipes as thick as the sound, amber near 0 dB, red over, a sign where it stops. Y over anything: why can't I hear it? Hold U over a track: hear it alone. X again: off.")
	else:
		Session.notice.emit("The signal view is off.")


## The room's sound sources, as SignalGraph.build takes them: every instrument item and the venue's
## set (onto its jack's track, armed or not, else the armed track), the
## modular (the armed track), the mic (its voice track), and the sampler and the
## platter, heard in one player's ears only.
func signal_sources() -> Array:
	var out: Array = []
	var seen := {}
	var armed := HitRecorder.armed_track()
	var row := func(id: StringName, title: String, node: Node3D, kind: StringName, track: int, jacked := false) -> void:
		if seen.has(id) or node == null or not is_instance_valid(node):
			return
		seen[id] = true
		var r := {"id": String(id), "title": title, "track": track, "kind": kind, "jacked": jacked, "node": node}
		if studio.jacks != null and studio.jacks.level_of(id) > 0.0:
			r["level_db"] = linear_to_db(studio.jacks.level_of(id))
		out.append(r)
	var onto := func(source: StringName, item: Item) -> Array:
		var sink: StringName = studio.jacks.goes_to(source, item) if studio.jacks != null else &""
		var track := Jack.track_of(sink)
		return [track, true] if track > 0 else [armed, false]
	if studio.items != null:
		for item: Item in studio.items.items.values():
			if not item.visible:
				continue
			if item is MicItem:
				row.call(&"mic", "MIC", item, SignalGraph.VOICE, studio.mic_arm.track if studio.mic_arm.track > 0 else MicArm.track_for(DAW.state.tracks))
			elif item is InstrumentItem:
				var source := (item as InstrumentItem).jack_source()
				var to: Array = onto.call(source, item)
				row.call(source, (item as InstrumentItem).item_title(), item, SignalGraph.NOTES, to[0], to[1])
	if studio.rack_wall != null:
		row.call(Modular.SOURCE, "MODULAR", studio.rack_wall, SignalGraph.NOTES, armed)
	for local in [[&"sampler", "SAMPLER", studio.sampler], [&"platter", "PLATTER", studio.platter]]:
		if local[2] != null:
			row.call(local[0], local[1], local[2], SignalGraph.LOCAL_SOURCE, 0)
	return out


## Where a stage stands in this room, or null: a source where it is; a track's stages at its voice on
## the stage table, else its channel strip; the master at the console's master section, OUT over it.
func signal_place(id: String) -> Variant:
	if id.begins_with("src:"):
		for r in studio._signal_rows:
			if r["id"] == id.trim_prefix("src:"):
				return (r["node"] as Node3D).global_position + Vector3.UP * 0.12 if is_instance_valid(r["node"]) else null
		return null
	if id == "master" or id == "out":
		if studio.console == null or studio.console.master == null or not studio.console.master.is_inside_tree():
			return null
		return studio.console.master.global_position + Vector3.UP * (0.3 if id == "master" else Studio.OUT_RISE)
	if id.begins_with("t"):
		var track := int(id.substr(1, id.find(":") - 1))
		return track_place(track)
	return null


## A track's place in the room: its voice on the stage table where it is shown, else its strip.
func track_place(track: int) -> Variant:
	if studio.stage != null and is_instance_valid(studio.stage) and studio.stage.voices.has(track):
		var voice := studio.stage.voices[track] as Node3D
		if voice != null and voice.is_inside_tree() and voice.is_visible_in_tree():
			return voice.global_position + Vector3.UP * 0.08
	if studio.console != null:
		for strip in studio.console.strips:
			if strip.track_index == track and strip.is_inside_tree() and strip.is_visible_in_tree():
				return strip.global_position + Vector3.UP * 0.25
	return null


## Every frame: the view on or off; while on, the graph rebuilt, the meters kept wanted, the
## pipes drawn, the headset's held trigger watched, and a trace run again after its fix.
func _follow_signal(delta: float) -> void:
	var on := signal_view_on()
	_follow_skyline(on)
	if not on:
		if studio.signal_view != null and studio.signal_view.visible:
			studio.signal_view.visible = false
			studio.signal_view.clear_trace()
			if studio.signal_view.card != null:
				studio.signal_view.card.visible = false
		return
	if studio.signal_view == null:
		studio.signal_view = SignalView.new()
		studio.signal_view.name = "SignalView"
		studio.signal_view.screen_card = studio.medium == Presentation.Medium.SCREEN
		studio.signal_view.place = signal_place
		studio.signal_view.fix_asked.connect(_do_signal_fix)
		studio.add_child(studio.signal_view)
	studio.signal_view.visible = true
	studio.signal_view.motion = studio.ergonomics.motion_scale
	DAW.backend.want_signal_meters()
	studio._signal_clock += delta
	if studio.signal_graph == null or studio._signal_clock >= 1.0 / Studio.SIGNAL_GRAPH_HZ:
		studio._signal_clock = 0.0
		studio._signal_rows = signal_sources()
		studio.signal_graph = SignalGraph.build(DAW.state, studio._signal_rows)
	studio.signal_view.quiet = [SignalGraph.SOLOED_OUT] if look_solo_held() else []
	studio.signal_view.update(studio.signal_graph, delta)
	if studio._retrace_in >= 0.0:
		studio._retrace_in -= delta
		if studio._retrace_in < 0.0 and studio._traced_from != "":
			studio.signal_graph = SignalGraph.build(DAW.state, signal_sources())
			studio.signal_view.trace(studio.signal_graph.trace(studio._traced_from), studio._traced_title)
	_follow_trace_holds(delta)


## The routing bay and the audio devices' wall stand up as skylines while the view is on
## (PinMatrix.skyline, docs/spatial_loop.md part three, E): this player's alone, as the view is.
func _follow_skyline(on: bool) -> void:
	if studio.patchbay != null and studio.patchbay.matrix != null:
		studio.patchbay.matrix.skyline = on
	var wall := studio.venue.get_node_or_null("PatchWall") as PatchWallSurface if studio.venue != null else null
	if wall != null and wall.matrix != null:
		wall.matrix.skyline = on


## The track looked at now: in a headset what the head's gaze meets, at a desk what the cursor is
## over; through what the signal view would trace from it (an instrument, its track). 0 for none.
func looked_track() -> int:
	var under: Node = null
	var point := Vector3.ZERO
	if studio.rig != null and studio.rig.head != null and studio.rig.head.is_inside_tree():
		var from := studio.rig.head.global_position
		var query := PhysicsRayQueryParameters3D.create(from, from - studio.rig.head.global_basis.z * Interactor.RAY_LENGTH)
		query.collision_mask = 1 << (Interactor.CONTROL_LAYER - 1)
		var hit := studio.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			under = hit["collider"]
			point = hit["position"]
	else:
		var hand := studio.get_node_or_null("MouseHand") as Interactor
		if hand != null:
			under = hand.held if hand.held != null else hand.hovered
			point = hand.hover_point
	var target := signal_target_of(under, point)
	if target.is_empty():
		return 0
	var id: String = target[0]
	if id.begins_with("src:"):
		for r in studio._signal_rows if not studio._signal_rows.is_empty() else signal_sources():
			if SignalGraph.source_id(r["id"]) == id:
				return int(r["track"])
		return 0
	return int(id.substr(1, id.find(":") - 1)) if id.begins_with("t") else 0


## Look to solo pressed, by `by` (&"key" or &"ear"): with the signal view on, the track looked at
## alone; on a guest asked of the host. Said either way.
func look_solo_press(by: StringName) -> void:
	if studio._look_by != &"":
		return
	if not signal_view_on():
		if by == &"key":
			Session.notice.emit("Look to solo needs the signal view on: X, or the signal glasses. Then hold U over a track to hear it alone.")
		return
	studio._look_by = by
	var on := looked_track()
	if Session.is_authority():
		var other := _look_solo_holder(Session.local_peer_id)
		if other != "":
			studio._look_by = &""
			Session.notice.emit("Look to solo is %s's just now: one at a time, as the room hears it." % other)
			return
		studio.look_solo.peer = 0
		var words := studio.look_solo.press(on)
		if words != "":
			Session.notice.emit(words)
		return
	studio._look_asked = on
	studio._look_resting = [on, 0.0]
	Session.ask_room(&"look_solo", [on, true])
	Session.notice.emit("Look to solo asks the host: the whole room hears %s alone while you hold, as a guest hears only the host's mix." % (LookSolo._title(on) if on > 0 else "what you look at"))


## Look to solo let go by `by`, or by anything (&"" -- the window's focus lost, the view off).
func look_solo_release(by: StringName = &"") -> void:
	if studio._look_by == &"" or (by != &"" and by != studio._look_by):
		return
	studio._look_by = &""
	if Session.is_authority():
		var words := studio.look_solo.release()
		if words != "":
			Session.notice.emit(words)
		return
	Session.ask_room(&"look_solo", [0, false])
	studio._look_asked = 0


## Whether a look-solo is held in this room as far as this machine knows: its own (or, on a guest,
## its ask), or a guest's the host runs.
func look_solo_held() -> bool:
	if studio._look_by != &"" or studio.look_solo.held:
		return true
	for p in studio.guest_look_solos:
		if (studio.guest_look_solos[p] as LookSolo).held:
			return true
	return false


## Whoever other than `peer` holds a look-solo here (the host's own, or a guest's), by name; "".
func _look_solo_holder(peer: int) -> String:
	if studio.look_solo.held and peer != Session.local_peer_id:
		return Session.name_of(Session.local_peer_id)
	for p in studio.guest_look_solos:
		if p != peer and (studio.guest_look_solos[p] as LookSolo).held:
			return Session.name_of(p)
	return ""


## Host: a guest's look-solo asked (`track`, 0 for nothing; `held` false to let go).
func _on_look_solo_asked(track: int, held: bool, from: int) -> void:
	var ls: LookSolo = studio.guest_look_solos.get(from)
	if not held:
		if ls != null:
			var words := ls.release()
			studio.guest_look_solos.erase(from)
			if words != "":
				Session.tell_room("%s let go of look to solo: every solo and mute as it was." % Session.name_of(from))
		return
	if ls != null and ls.held:
		ls.look(track, LookSolo.FOLLOW_AFTER)
		return
	var other := _look_solo_holder(from)
	if other != "":
		Session.tell(from, "Look to solo is %s's just now: one at a time." % other)
		return
	ls = LookSolo.new()
	ls.peer = from
	studio.guest_look_solos[from] = ls
	ls.press(track)
	if ls.track > 0:
		Session.tell_room("%s is look-soloing %s: the room hears it alone while they hold." % [Session.name_of(from), LookSolo._title(ls.track)])


## Host: a guest gone lets their look-solo go.
func _on_look_solo_player_left(peer: int) -> void:
	if not is_instance_valid(studio):
		return
	var ls: LookSolo = studio.guest_look_solos.get(peer)
	if ls != null:
		ls.release()
		studio.guest_look_solos.erase(peer)


## Every frame: a hand cupped to an ear holds it in a headset; held, the solo follows the look;
## the view going off lets go.
func _follow_look_solo(delta: float) -> void:
	_follow_ear_cup(delta)
	if studio._look_by == &"":
		return
	if not signal_view_on():
		look_solo_release()
		return
	var on := looked_track()
	if Session.is_authority():
		var words := studio.look_solo.look(on, delta)
		if words != "":
			Session.notice.emit(words)
		return
	# A guest's look rests FOLLOW_AFTER on another track before it is asked.
	if on <= 0 or on == studio._look_asked:
		studio._look_resting = [on, 0.0]
		return
	if on != int(studio._look_resting[0]):
		studio._look_resting = [on, 0.0]
	studio._look_resting[1] = float(studio._look_resting[1]) + delta
	if float(studio._look_resting[1]) >= LookSolo.FOLLOW_AFTER:
		studio._look_asked = on
		Session.ask_room(&"look_solo", [on, true])


## A headset's hand cupped to an ear, with the view on: a controller beside the head with its grip
## squeezed, or a bare hand there, carrying nothing either way. Held EAR_DWELL, it presses; taken
## away, it lets go.
func _follow_ear_cup(delta: float) -> void:
	if studio.rig == null or studio.rig.head == null or not studio.rig.head.is_inside_tree():
		return
	var head := studio.rig.head.global_transform
	var nearest := INF
	for controller in studio.rig.interactors:
		var hand := studio.rig.interactors[controller] as XRInteractor
		if hand == null or not is_instance_valid(hand) or is_instance_valid(hand.carrying) or hand.held != null:
			continue
		var palm := hand.clap_palm()
		if palm.is_empty():
			continue
		if not hand._reads_hand() and not (hand.controller != null and hand.controller.is_button_pressed(hand.grip_action)):
			continue
		var at: Vector3 = palm[0]
		for side in [-1.0, 1.0]:
			nearest = minf(nearest, at.distance_to(head.origin + head.basis.x.normalized() * side * Studio.EAR_OUT))
	if studio._look_by == &"ear":
		if nearest > Studio.EAR_REACH + Studio.EAR_LEAVE:
			look_solo_release(&"ear")
		return
	if nearest <= Studio.EAR_REACH and signal_view_on() and studio._look_by == &"":
		studio._ear_for += delta
		if studio._ear_for >= Studio.EAR_DWELL:
			look_solo_press(&"ear")
	else:
		studio._ear_for = 0.0


## The stage a trace of what `node` is starts from, and what it is called: an instrument or a
## station, its source; anything of a track (a strip, a voice, a control on one), that track's own
## playback. Empty for nothing that sounds.
func signal_target_of(node: Node, point := Vector3.ZERO) -> Array:
	if node == null:
		return []
	for r in studio._signal_rows if not studio._signal_rows.is_empty() else signal_sources():
		var n: Node = r["node"]
		if is_instance_valid(n) and (n == node or n.is_ancestor_of(node)):
			return [SignalGraph.source_id(r["id"]), str(r["title"])]
	var track := Studio.track_of(node, point)
	if track > 0 and DAW.state.tracks.has(track):
		return [SignalGraph.play_id(track), DAW.state.track(track).display_name()]
	return []


## "Why can't I hear this?" for what `hand` points at: traced and shown a stage at a time. True if
## there was something to trace.
func trace_pointed(hand: Interactor) -> bool:
	if not signal_view_on():
		Session.notice.emit("Put on the signal glasses first (X at a desk, or a pair from the prop shelf): then Y asks why.")
		return false
	var under: Node = (hand.held if hand.held != null else hand.hovered) if hand != null else null
	if under == null and hand != null and is_instance_valid(hand.carrying):
		under = hand.carrying
	var target := signal_target_of(under, hand.hover_point if hand != null else Vector3.ZERO)
	if target.is_empty():
		Session.notice.emit("Nothing that sounds is under the cursor: point at an instrument, a station, a stage voice or a channel strip.")
		return false
	return trace_from(target[0], target[1])


## A trace from stage `from`, called `title`, shown in the view and said in the toast.
func trace_from(from: String, title: String) -> bool:
	if studio.signal_view == null:
		_follow_signal(0.0)
	studio._signal_rows = signal_sources()
	studio.signal_graph = SignalGraph.build(DAW.state, studio._signal_rows)
	if studio.signal_graph.stage(from) == null:
		return false
	studio._traced_from = from
	studio._traced_title = title
	var tr := studio.signal_graph.trace(from)
	studio.signal_view.trace(tr, title)
	if tr.heard():
		Session.notice.emit("%s is heard: it reaches the speakers." % title)
	elif tr.broke_at != null:
		Session.notice.emit("%s stops at %s: %s.%s" % [title, tr.broke_at.title, tr.words,
				(" Shift-Y: %s." % tr.fix["label"]) if not tr.fix.is_empty() else ""])
	return true


## Shift-Y, the card's FIX or the key by the sign: the trace's fix, one undo step, then traced again.
func fix_traced() -> bool:
	if studio.signal_view == null or studio.signal_view.tracing == null or studio.signal_view.tracing.fix.is_empty():
		Session.notice.emit("No fix to do: trace something with Y first.")
		return false
	_do_signal_fix(studio.signal_view.tracing.fix)
	return true


func _do_signal_fix(fix: Dictionary) -> void:
	if not SignalGraph.apply_fix(fix):
		return
	Session.notice.emit("%s: done, one undo step (Ctrl-Z puts it back)." % fix["label"])
	studio._retrace_in = 0.0 if Session.is_authority() else Studio.RETRACE_AFTER


## A headset's trigger held still on something for TRACE_HOLD, with the view on, traces it.
func _follow_trace_holds(delta: float) -> void:
	if studio.rig == null:
		return
	for controller in studio.rig.interactors:
		var hand := studio.rig.interactors[controller] as Interactor
		if hand == null or not is_instance_valid(hand):
			continue
		var on: Node = hand.held if hand.held != null else hand.hovered
		var held: Array = studio._trace_holds.get(hand, [null, 0.0, false])
		if hand.is_pressing() and on != null and on == held[0]:
			held[1] = float(held[1]) + delta
			if float(held[1]) >= Studio.TRACE_HOLD and not held[2]:
				held[2] = true
				trace_pointed(hand)
		else:
			held = [on if hand.is_pressing() else null, 0.0, false]
		studio._trace_holds[hand] = held
