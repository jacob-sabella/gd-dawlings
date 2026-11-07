class_name PatchHost
extends RefCounted

## The studio's jacks and patching: plugging an instrument's jack into a bandmate or a track, who is told, the wrist jacks, the
## patch lines drawn between them and the ON AIR light. Moved out of `scenes/studio.gd` without change of behaviour;
## the state stays on the studio, which delegates the calls other code makes.

## How far up the arm from MY KEYS the wrist's INTO ME socket is worn (m): clear of both reaches.
const WRIST_IN_APART := 0.06

## How far down onto the back of the hand from MY KEYS the chord hand's MY CHORDS socket is worn,
## and across the controller from it (m): clear of both reaches, as INTO ME is the other way.
const WRIST_CHORD_APART := 0.056

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## A plug dropped on a socket by a hand here, or brought back to the tray: done here at once,
## and asked of the host, whose table it is.
func _on_patch_asked(receiver: int, socket: StringName) -> void:
	if not PersonalMix.valid_socket(socket) or receiver < 0 or receiver >= PersonalMix.RECEIVERS:
		return
	var letter: String = PersonalMix.LETTERS[receiver]
	_set_patch(Session.local_peer_id, receiver, socket)
	if Session.is_authority():
		studio.player_host._publish_room_soon()
	else:
		studio.room_rows._predict(&"patch", [receiver, socket])
	if socket == &"":
		Session.notice.emit("Plug %s is back in the tray." % letter)
	elif studio.personal.unheard(receiver):
		Session.notice.emit("Plug %s in %s. One track by itself is not heard here: %s" % [letter,
				PersonalMix.place_of(socket), _why_no_tracks()])
	else:
		var late := ""
		var player := PersonalMix.player_of(socket)
		if player > 0 and Session.note_delay_ms(player) >= 0.0:
			late = " Their notes are played here, about %d ms after they play them." \
					% roundi(Session.note_delay_ms(player))
		if PersonalMix.monitor_of(socket) > 0:
			late = " In time with the backing they hear: your mix waits for their notes."
			if not Ears.reaches_mix(Session.role == Session.Role.GUEST, DAW.backend is ReaperBackend):
				late += " Reaper's mix is not the game's to copy, so only their notes are heard."
		Session.notice.emit("Plug %s in %s: in your headphones%s.%s" % [letter,
				PersonalMix.place_of(socket), "" if studio._heard_phones else " when you put them on", late])


## An instrument played by a hand here: into the take, and, shaken, out to everyone else. A
## click on percussion is out already, as a use; a pitched item's click is sent as a hit too,
## since its ring is all a use of it is, and only a hit carries the song position (`at`) that
## pitches it. The take and the room both get that one `at`, unmoved: a snap moves only the
## recorded note (HitRecorder.snapped_at), and whether this player snaps goes with the hit, with the
## Foley take their hand rang, so everyone hears the sound they heard. A strike on an instrument that
## stands still (Item.fixed) has no use to go as, so it goes as a hit, with where on it it landed
## (`zone`).
func _on_item_played(item: InstrumentItem, velocity: int, struck: bool, at: float, zone := &"") -> void:
	# Onto the armed track, or the track its jack goes into.
	studio.jacks.hit(item, velocity, at, zone)
	# A strike of the venue's instrument into the rack's `world` module.
	if studio.modular_world != null and item.jack_source() == VenueInstrument.SOURCE:
		studio.modular_world.strike(at, velocity)
	# And into this player's loop, while they loop (slice 45).
	if studio.looper != null and is_instance_valid(studio.looper):
		studio.looper.hit(item, velocity, at, zone)
	if studio.sampler_host._sampling():
		studio.sampler_host._sample(item, item.kind_of_hit(struck, zone), item.sound_take(), Session.local_peer_id, item.tune_at(at))
	if not struck or item.pitched() or item.fixed:
		studio.send_item_hit.call(item.id, velocity, at, HitRecorder.snaps(), item.sound_take(), zone)


## A hand here stepped an instrument's jack (Jacks.asked): done here at once, and asked of the
## host, whose table it is. One that plainly is not this player's to plug -- in somebody else's
## hand, or lying on the floor -- is said instead, and nothing is asked.
func _on_plug_asked(source: StringName, sink: StringName) -> void:
	var item: Item = studio.items.source_item(source) if studio.items != null else null
	if item == null and Jack.is_item(source):
		return
	var whose := "Your keys'" if Jack.keys_player(source) > 0 else "The %s's" % Jacks.source_name(source, item)
	if Jack.chord_player(source) > 0:
		whose = "Your chord hand's"
	var why := _plug_refusal(source, sink, Session.local_peer_id, true)
	if why != "":
		Session.notice.emit("%s jack: %s." % [whose, why])
		return
	if Jack.own_player(source) > 0 and sink == &"" and studio.jacks.sink_of(source) == &"":
		Session.notice.emit("%s jack: there is nobody in the room to plug %s into." % [whose,
				"them" if Jack.keys_player(source) > 0 else "it"])
		return
	var was := studio.jacks.sink_of(source)
	if not studio.jacks.plug(source, sink):
		return
	if Session.is_authority():
		_tell_plugged(source, was, sink, Session.local_peer_id)
		studio.player_host._publish_room_soon()
	else:
		studio.room_rows._predict(&"plug", [source, sink])
	Session.notice.emit(studio.plugged_text(source, item, was, sink))


## The host's word on `from`'s plug of `source` into `sink` (Jacks.plug_refusal), from what this
## machine knows: who holds the source item, where it goes now, who is in the room. `here`: asked
## by a hand on this machine, which knows its own hand better than the holds table does.
func _plug_refusal(source: StringName, sink: StringName, from: int, here := false) -> String:
	var item: Item = studio.items.source_item(source) if studio.items != null else null
	var holder := 0
	if item != null:
		holder = _holder_here(item) if here else Session.holder_of(item.network_key())
	var members: Array = Session.participants.keys()
	if not members.has(Session.local_peer_id):
		members.append(Session.local_peer_id)
	return Jacks.plug_refusal(source, item, sink, from, holder, studio.jacks.sink_of(source), members)


## The host tells whoever a jack now goes into, or no longer does, who plugged what: a bandmate's
## cowbell playing your keys is not a thing to find out by surprise. Not the one who did it.
func _tell_plugged(source: StringName, was: StringName, sink: StringName, by: int) -> void:
	var item: Item = studio.items.source_item(source) if studio.items != null else null
	var what := "the %s" % Jacks.source_name(source, item) if Jack.keys_player(source) == 0 \
			else "their keys"
	if Jack.chord_player(source) > 0:
		what = "their chord hand"
	var into := Jack.player_of(sink)
	if into > 0 and into != by:
		var plays := "its hits play chord tones" if item is InstrumentItem and not (item as InstrumentItem).pitched() \
				else "its notes play"
		if Jack.keys_player(source) > 0:
			plays = "what they play plays"
		var said := "%s on your keys" % plays
		if Jack.chord_player(source) > 0:
			said = "the chord they hold is yours, on your fingertips, while you hold none"
		Session.tell(into, "%s plugged %s into you: %s. %s"
				% [Session.name_of(by), what, said, studio.unplug_how(_medium_of(into), Jack.own_player(source) == 0)])
	var out := Jack.player_of(was)
	if out > 0 and out != by and out != into:
		Session.tell(out, "%s unplugged %s from you." % [Session.name_of(by), what])


## The medium player `peer` is in, as they said on joining (screen where not known).
func _medium_of(peer: int) -> int:
	if peer == Session.local_peer_id:
		return studio.medium
	var p: Variant = Session.participants.get(peer)
	return int(p.medium) if p != null else Presentation.Medium.SCREEN


## Host: the studio's word on a jack's event (Session.jack_check): the room's patch and who has
## the source in hand (Jacks.send_refusal).
func _jack_refusal(to: int, source: StringName, from: int) -> String:
	if studio.jacks == null:
		return "there is no room here to say where it goes"
	var item: Item = studio.items.source_item(source) if studio.items != null else null
	var holder := Session.holder_of(item.network_key()) if item != null else 0
	return Jacks.send_refusal(studio.jacks.patch, source, to, from, holder, item != null and item.fixed)


## Somebody left: as host, every jack into them and out of their keys comes out.
func _on_jack_player_left(peer: int) -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	if Session.role == Session.Role.HOST and studio.jacks != null and studio.jacks.drop_player(peer):
		studio.player_host._publish_room_soon()


## P with nothing in the mouse's hand: this player's own keys' jack steps on (a headset wears it on
## the wrist); Shift+P takes out every jack going into this player.
func _on_bare_jack(unplug: bool) -> void:
	if studio.jacks == null:
		return
	if not unplug:
		studio.jacks.step_source(Jack.keys_source(Session.local_peer_id), 1)
	elif studio.jacks.unplug_mine() == 0:
		Session.notice.emit("Nothing is plugged into you.")


## This player's keys' jack, worn on the left wrist: on the tracked hand's wrist, and on the left
## controller while it is held, a hand's width back from the grip. The other hand presses it.
## Beside each, a little further up the arm, the socket for what goes into this player
## (JackSocket.into_me), there while anything does: a press takes it all out, as Shift+P does at a
## desk, and it is the only way a bandmate's keys come out of a headset player.
func _wear_wrist_jacks() -> void:
	if studio.rig == null or studio.rig.left == null or not studio.rig.skeletons.has(studio.rig.left) or not studio.wrist_jacks.is_empty():
		return
	var skeleton := studio.rig.skeletons[studio.rig.left] as HandSkeleton
	var poke := studio.rig.pokes.get(studio.rig.left) as PokeInteractor
	var on_hand := JackSocket.new(null)
	on_hand.mine_keys = true
	on_hand.label = "MY KEYS"
	skeleton.wrist.add_child(on_hand)
	var on_controller := JackSocket.new(null)
	on_controller.mine_keys = true
	on_controller.label = "MY KEYS"
	on_controller.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.03, 0.09))
	on_controller.available = func() -> bool: return poke == null or not poke.tracked()
	studio.rig.left.add_child(on_controller)
	var in_hand := JackSocket.new(null)
	in_hand.into_me = true
	in_hand.label = "INTO ME"
	# The wrist mount's +Y runs out toward the fingers: up the forearm, clear of MY KEYS' reach.
	in_hand.position = Vector3(0, -WRIST_IN_APART, 0)
	skeleton.wrist.add_child(in_hand)
	var in_controller := JackSocket.new(null)
	in_controller.into_me = true
	in_controller.label = "INTO ME"
	in_controller.transform = on_controller.transform.translated(Vector3(0, 0, WRIST_IN_APART))
	in_controller.available = on_controller.available
	studio.rig.left.add_child(in_controller)
	studio.wrist_jacks = [on_hand, on_controller, in_hand, in_controller]
	_wear_chord_jacks()


## The chord hand's jack (`chord:P`, MY CHORDS; part two, slice 33), worn on the chord hand as
## MY KEYS is: on the tracked hand's wrist and on its controller while it holds one. On the left
## hand it sits beside MY KEYS, down onto the back of the hand on the wrist and across the
## controller, clear of both reaches; a left-handed player's chord hand is the right, where it
## sits where MY KEYS does on the left. The other hand presses it, through each bandmate.
func _wear_chord_jacks() -> void:
	var controller: XRController3D = studio.rig.left if studio.ergonomics.handedness >= 0 else studio.rig.right
	if controller == null or not studio.rig.skeletons.has(controller):
		return
	var skeleton := studio.rig.skeletons[controller] as HandSkeleton
	var poke := studio.rig.pokes.get(controller) as PokeInteractor
	var beside := controller == studio.rig.left
	var on_hand := JackSocket.new(null)
	on_hand.mine_chord = true
	on_hand.label = "MY CHORDS"
	on_hand.position = Vector3(0, WRIST_CHORD_APART if beside else 0.0, 0)
	skeleton.wrist.add_child(on_hand)
	var on_controller := JackSocket.new(null)
	on_controller.mine_chord = true
	on_controller.label = "MY CHORDS"
	on_controller.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.03, 0.09))
	if beside:
		on_controller.transform = on_controller.transform.translated(Vector3(WRIST_CHORD_APART, 0, 0))
	on_controller.available = func() -> bool: return poke == null or not poke.tracked()
	controller.add_child(on_controller)
	studio.wrist_jacks.append_array([on_hand, on_controller])


## Whose hand has `item`, as this machine sees it: this player's when a hand here carries it,
## the holder's (or somebody's, -1) when a ghost does, else nobody's (0).
func _holder_here(item: Item) -> int:
	if item.carried_by != null:
		return Session.local_peer_id
	if item.is_held_elsewhere():
		var holder := Session.holder_of(item.network_key())
		return holder if holder != 0 else -1
	return 0


## An item left the room (ItemRoom.despawn: a Tour spill swallowed, a personal copy put back):
## its jack goes with it. Not one leaving with the whole room, which still lists it.
func _on_item_leaving(node: Node) -> void:
	var item := node as Item
	if item == null or studio.jacks == null or studio.items == null or studio.items.items.has(item.id):
		return
	if studio.jacks.drop(item.id):
		studio.player_host._publish_room_soon()


## Why a single track is not heard on this machine (`_hears_tracks`).
func _why_no_tracks() -> String:
	if Session.role == Session.Role.GUEST:
		return "a guest hears the host's mix as one stream."
	if DAW.backend is ReaperBackend:
		return "Reaper plays the tracks, not the game."
	return "the stand-in DAW makes no sound."


## Put `peer`'s receiver `receiver`'s plug in `socket`, or back in its tray (empty).
func _set_patch(peer: int, receiver: int, socket: StringName, show := true) -> void:
	if receiver < 0 or receiver >= PersonalMix.RECEIVERS:
		return
	var row: Array = []
	for i in PersonalMix.RECEIVERS:
		var had: Array = studio.patches.get(peer, [])
		row.append(String(had[i]) if i < had.size() else "")
	row[receiver] = String(socket)
	if row.all(func(s: String) -> bool: return s == ""):
		studio.patches.erase(peer)
	else:
		studio.patches[peer] = row
	if show:
		_show_patches()


## Everyone's plugs in the sockets, in their colours, and this person's own in their ears.
func _show_patches() -> void:
	studio.personal.hears_tracks = studio.mix_follow._hears_tracks()
	studio.personal.set_sockets(studio.patches.get(Session.local_peer_id, []))
	var peers := studio.patches.keys()
	peers.sort()
	# The desk's sockets once it is built (it builds a frame or two after the studio, and shows
	# them then: `console.rebuilt`); a bandmate's pack and the racks' OUTs whether it is or not.
	var sockets: Array[SendSocket] = []
	if studio.console != null and studio.console.master != null:
		sockets.append_array(studio.console.master.sends)
		for strip in studio.console.strips:
			sockets.append(strip.send)
	# Every effects rack's OUT: the main one and each track pulled out on a rack of its own.
	var racks: Array = [studio.rack] if studio.rack != null else []
	for id in studio.track_racks:
		racks.append(studio.track_racks[id][1])
	for r: RackSurface in racks:
		if is_instance_valid(r):
			sockets.append_array(r.out_sockets())
	if studio.presence != null:
		for peer in Session.participants:
			var avatar := studio.presence.avatar_of(peer)
			if avatar != null:
				avatar.set_on_air(peer in studio.on_air, peer)
		for avatar: Presence.Avatar in studio.presence.avatars():
			if avatar.send != null:
				sockets.append(avatar.send)
			if avatar.monitor_send != null:
				sockets.append(avatar.monitor_send)
	var tablet := studio.items.items.get(&"tablet") as TabletItem if studio.items != null else null
	if tablet != null:
		tablet.on_air = Session.local_peer_id in studio.on_air
	for socket in sockets:
		if not socket.pressed.is_connected(_on_send_pressed):
			socket.pressed.connect(_on_send_pressed.bind(socket.source))
		var colours: Array[Color] = []
		for peer in peers:
			for s: String in studio.patches[peer]:
				if StringName(s) == socket.source:
					colours.append(_colour_of(peer))
		socket.set_plugs(colours)


## A SEND socket clicked: this person's plugs in it come back to their tray. With none in it,
## where the plugs are.
func _on_send_pressed(source: StringName) -> void:
	var mine: Array = studio.patches.get(Session.local_peer_id, [])
	var any := false
	for i in mine.size():
		if StringName(mine[i]) == source:
			_on_patch_asked(i, &"")
			any = true
	if not any:
		Session.notice.emit("Drag a plug onto %s from your tablet: it lies on the prop shelf's lower tier."
				% PersonalMix.place_of(source))


## Who is here changed: colours may have, and a guest who left takes their plugs with them.
func _on_roster_for_patches() -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	var tablet := studio.items.items.get(&"tablet") as TabletItem if studio.items != null else null
	if tablet != null:
		tablet.colour = _colour_of(Session.local_peer_id)
	if Session.role == Session.Role.HOST:
		for peer in studio.patches.keys():
			if not Session.participants.has(peer):
				studio.patches.erase(peer)
				studio.player_host._publish_room_soon()
		for peer in studio.on_air.duplicate():
			if not Session.participants.has(peer):
				_set_on_air(peer, false, false)
				studio.player_host._publish_room_soon()
		# And the plugs in the keys of whoever left come back to their trays.
		for peer in studio.patches.keys():
			var row: Array = studio.patches[peer]
			for i in row.size():
				var into := PersonalMix.player_of(StringName(row[i]))
				if into > 0 and not Session.participants.has(into):
					_set_patch(peer, i, &"", false)
					studio.player_host._publish_room_soon()
	# After the ghosts: a new one's pack is made on the same news.
	_show_patches.call_deferred()


## The ON AIR switch on the tablet in a hand here: done here at once, and asked of the host.
func _on_air_asked(on: bool) -> void:
	_set_on_air(Session.local_peer_id, on)
	if Session.is_authority():
		studio.player_host._publish_room_soon()
	else:
		studio.room_rows._predict(&"on_air", [on])
	if on:
		Session.notice.emit("On air: anyone can plug into the MONITOR on your pack and hear your keys in time with the backing you play to.")
	else:
		Session.notice.emit("Off air: the plugs in your monitor went back to their trays.")


## `peer` ON AIR or off. Off, the plugs in their monitor come back to their owners' trays: the
## host's to do, as it keeps the table; a guest predicting its own leaves the others to it.
func _set_on_air(peer: int, on: bool, show := true) -> void:
	if on and peer not in studio.on_air:
		studio.on_air.append(peer)
		studio.on_air.sort()
	elif not on:
		studio.on_air.erase(peer)
		if Session.is_authority():
			for listener in studio.patches.keys():
				var row: Array = studio.patches[listener]
				for i in row.size():
					if PersonalMix.monitor_of(StringName(row[i])) == peer:
						_set_patch(listener, i, &"", false)
	if show:
		_show_patches()


func _colour_of(peer: int) -> Color:
	var p: Session.Participant = Session.participants.get(peer)
	return p.colour if p != null else SendSocket.LAMP


## What this player is told on plugging `source` (its `item`, if it is one) from `was` into
## `sink`: where what it plays goes now.
static func plugged_text(source: StringName, item: Item, was: StringName, sink: StringName) -> String:
	var the := "Your keys" if Jack.keys_player(source) > 0 else "The " + Jacks.source_name(source, item)
	var player := Jack.player_of(sink)
	if Jack.chord_player(source) > 0:
		# A chord hand (part two, slice 33): no notes, a chord for their fingertips.
		if player > 0:
			return "Your chord hand goes into %s: the chord you hold is theirs, on their fingertips." \
					% Session.name_of(player)
		return "Your chord hand is unplugged."
	if player > 0:
		var plays := "its hits play chord tones" if item is InstrumentItem and not (item as InstrumentItem).pitched() \
				else "its notes play"
		if Jack.keys_player(source) > 0:
			plays = "what you play plays"
		return "%s go%s into %s: %s on their keys." % [the, "" if Jack.keys_player(source) > 0 else "es",
				Session.name_of(player), plays]
	if sink != &"" and Jack.is_world(source):
		return "%s's jack is in %s: every drop is recorded there while the song records, heard or not." % [the, Jacks.sink_name(sink)]
	if sink != &"":
		return "%s's jack is in %s: its hits are recorded there, armed or not." % [the, Jacks.sink_name(sink)]
	if Jack.player_of(was) == Session.local_peer_id and Session.local_peer_id != 0:
		return "%s is unplugged from you." % the
	if Jack.is_world(source):
		return "%s is unplugged: its drops are recorded nowhere." % the
	if not Jack.is_item(source):
		return "%s %s unplugged." % [the, "are" if Jack.keys_player(source) > 0 else "is"]
	return "%s is unplugged: its hits go on the armed track again." % the


## How a player at `medium` (Presentation.Medium) takes out a jack that goes into them, in words:
## at a desk Shift+P with an empty hand, in a headset a press on the INTO ME jack on their left
## wrist; and, `own_jack` (an item, not a bandmate's keys, whose socket is on the
## bandmate), a press on its own jack as well.
static func unplug_how(medium: int, own_jack: bool) -> String:
	var how := "Shift+P with an empty hand" if medium == Presentation.Medium.SCREEN \
			else "A press on the INTO ME jack on your left wrist"
	return "%s%s unplugs it." % [how, ", or a press on its jack," if own_jack else ""]
