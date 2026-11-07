class_name ItemHost
extends RefCounted

## Everything the studio does for the things people pick up (`ItemRoom`, docs/items_loop.md): where each lives
## (`_item_homes`), building the room's items, minting and making cassettes, giving an item to a peer, the weather and the
## looper's replies. Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the
## calls other code makes.

## The hands a made item the host has answered for is to go into, oldest first (`_take_given`).
var _awaiting_hands: Array = []

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## The items' homes off the shelf: the headphones on their hook under it, the mic in the booth's stand, where the venue has one, the session in
## miniature on the side table by the seat, the hand drums in their ring on the drum riser, and the venue's
## instrument's bars on its mount.
func _item_homes() -> Dictionary:
	if studio.venue == null:
		return _kit_homes({})
	var out := {&"headphones": studio.venue.headphones_spot(), &"glasses": studio.venue.glasses_spot(), &"tablet": studio.venue.tablet_spot(),
			&"chips": studio.venue.shelf_spots.chips_spot(), &"cards": studio.venue.shelf_spots.cards_spot(),
			&"cradle": studio.venue.shelf_spots.cradle_spot(), &"yoyo": studio.venue.shelf_spots.yoyo_spot(), &"toy": studio.venue.toy_spot(),
			&"rcplane": studio.venue.rcplane_spot()}
	for n in 3:
		out[StringName("dart%d" % (n + 1))] = studio.venue.dart_spot(n)
	var mic_at: Variant = studio.venue.mic_spot()
	if mic_at != null:
		out[&"mic"] = mic_at
	var mini_at: Variant = studio.venue.miniature_spot()
	if mini_at != null:
		out[MiniatureItem.KIND] = mini_at
	# The hand drums round their ring on the drum riser (slice 40); none where there is no riser.
	for n in HandDrum.KINDS.size():
		var drum_at: Variant = studio.venue.drum_circle_spot(n)
		if drum_at != null:
			out[HandDrum.KINDS[n]] = drum_at
	# The venue's instrument's bars on its mount (slice 42); past its count, or with none, put away.
	if studio.venue_instrument != null and is_instance_valid(studio.venue_instrument):
		out.merge(VenueInstrument.homes(studio.venue_instrument.spec))
	return _kit_homes(out)


## `homes` with the drum pads' kit's (slice 41): on the console's front rail, wherever the desk is,
## in AR too; none (put away) with no console built yet.
func _kit_homes(homes: Dictionary) -> Dictionary:
	var at: Variant = studio.view_host.kit_home()
	if at != null:
		homes[KitItem.KIND] = at
	return homes


## The things people pick up (docs/items_loop.md), in the set's frame, the floor plan's. They
## lie only where the walker could stand to pick them up again.
func _build_items() -> void:
	studio.items = ItemRoom.new()
	studio.items.name = "Items"
	if studio.medium == Presentation.Medium.AR:
		studio.items.only = ItemRoom.AR_KINDS
	if studio.walker != null:
		studio.items.fits = studio.walker.reachable
		studio.items.ground_at = studio.walker.ground_at
		studio.items.floor_rects = func() -> Array: return studio.walker.walkable
		# What a throw lands on: the venue's fixed things, and the free-standing ones wherever they
		# have been pushed (the walker stops at those as trolleys, which say nothing of how tall).
		studio.items.solids = func() -> Array:
			return studio.walker.fixed + (studio.venue.wheeled_solids() if studio.venue != null and not studio.live_pieces.is_empty() else [])
		studio.items.gear = studio.walker.footprints
	studio.items.local_peer = func() -> int: return Session.local_peer_id
	Session.takeable = func(key: String) -> bool:
		return is_instance_valid(studio) and is_instance_valid(studio.items) and studio.items.items.values().any(
				func(item: Item) -> bool: return item.network_key() == key)
	# A marked instrument (Item.bound_to, Tour's "marked" spill) is refused every other hand by
	# the host's own arbitration, not only by the hand's own `may_hold` check.
	Session.holdable = func(key: String, _peer: int) -> int:
		if not is_instance_valid(studio) or not is_instance_valid(studio.items):
			return 0
		for item: Item in studio.items.items.values():
			if item.network_key() == key:
				return item.bound_to
		return 0
	if studio.venue != null:
		ToyItem.shown = studio.venue.venue_id()
	studio.studio_set.add_child(studio.items)
	if studio.venue != null:
		studio.items.boards = studio.venue.dart_boards()
		studio.items.hoops = RoomSync.hoops(studio)
		studio.items.set_venue(studio.venue.venue_id())
	var shelf: Array[Transform3D] = []
	if studio.venue != null:
		shelf = studio.venue.item_spots()
	studio.venue_switch._dress_venue_bars()
	studio.items.set_spots(shelf, _item_homes())
	var mic := studio.items.items.get(&"mic") as MicItem
	if mic != null:
		mic.live_changed.connect(func(live: bool) -> void:
			if live:
				studio.mic_arm.take()
			else:
				studio.mic_arm.let_go())
	var phones := studio.items.items.get(&"headphones") as HeadphonesItem
	if phones != null:
		phones.worn_changed.connect(studio.mix_follow._on_phones_changed)
		phones.state_changed.connect(func(_s: Item.State) -> void: studio.mix_follow._on_phones_changed())
	var tablet := studio.items.items.get(&"tablet") as TabletItem
	if tablet != null:
		tablet.mix = studio.personal
		tablet.colour = studio.patch_host._colour_of(Session.local_peer_id)
		tablet.patch_asked.connect(studio.patch_host._on_patch_asked)
		tablet.on_air_asked.connect(studio.patch_host._on_air_asked)
	studio.personal.changed.connect(studio.mix_follow._on_personal_changed)
	studio.station_host._wire_miniature()
	studio.their_keys = TheirKeys.new()
	studio.their_keys.name = "TheirKeys"
	studio.add_child(studio.their_keys)
	Session.note_played.connect(studio.their_keys.play)
	# A guest's keys, live on the instrument plugin of the track they play into.
	var guest_play := GuestPlay.new()
	guest_play.name = "GuestPlay"
	studio.add_child(guest_play)
	# A guest's audio input, offered and allowed, heard live through the track the host put it on.
	var guest_live := GuestLive.new()
	guest_live.name = "GuestLive"
	studio.add_child(guest_live)
	Session.control_played.connect(studio.their_keys.control)
	studio.their_monitor = TheirMonitor.new()
	studio.their_monitor.name = "TheirMonitor"
	studio.add_child(studio.their_monitor)
	studio.ear = EarCue.new()
	studio.ear.name = "EarCue"
	studio.add_child(studio.ear)
	Session.note_played.connect(studio.their_monitor.play)
	Session.control_played.connect(studio.their_monitor.control)
	studio.console.rebuilt.connect(studio.patch_host._show_patches)
	# A rack's OUT is made again with the rack, and shows the plugs in it again.
	if studio.rack != null:
		studio.rack.rebuilt.connect(studio.patch_host._show_patches)
	Session.roster_changed.connect(studio.patch_host._on_roster_for_patches)
	studio.patch_host._show_patches()
	studio.items.asked.connect(studio.player_host._on_items_asked)
	studio.items.refused.connect(studio.tour_room._on_item_refused)
	studio.items.used.connect(func(item: Item, down: bool) -> void: Session.send_item_use(item.id, down, item.use_take))
	# What the sampler catches (slice 26): a use or a hit by a hand here, or anyone's the host hears.
	studio.items.used.connect(studio.sampler_host._sample_use_here)
	studio.items.rang.connect(studio.sampler_host._sample_ring)
	Session.item_used.connect(studio.sampler_host._on_someones_use)
	Session.item_hit.connect(studio.sampler_host._on_someones_hit)
	studio.items.personal_taken.connect(studio.tour_room._on_item_personal_taken)
	studio.hit_recorder = HitRecorder.new()
	studio.hit_recorder.name = "HitRecorder"
	studio.add_child(studio.hit_recorder)
	# Every hit's one song position is read from the take's own stamp (InstrumentItem.clock).
	InstrumentItem.clock = studio.hit_recorder.stamp
	# The shelf tags of the instruments that stand still say, in a headset, which way a hit is heard.
	InstrumentItem.hands_hint = studio.medium != Presentation.Medium.SCREEN
	studio.hit_recorder.unarmed.connect(func() -> void:
		Session.notice.emit("Arm a track to record the percussion: hits are only heard until one is."))
	# A fixed instrument is struck where it stands: by a hand or a controller crossing its head here.
	studio.strike = Strike.new()
	studio.strike.name = "Strike"
	studio.add_child(studio.strike)
	# This player's own hits a few milliseconds after the hand, where the helper can run.
	InstrumentItem.fast_path = studio.input_host._hit_on_fast_path
	InstrumentItem.fast_latency = studio.input_host._fast_path_latency
	studio.input_host._start_hit_voices()
	studio.jacks = Jacks.new()
	studio.jacks.name = "Jacks"
	studio.jacks.recorder = studio.hit_recorder
	studio.add_child(studio.jacks)
	studio.jacks.asked.connect(studio.patch_host._on_plug_asked)
	# A cable into a bandmate ends at their ghost's glove; one into this player plays their keys.
	studio.jacks.far_end = func(peer: int, from: Vector3) -> Variant:
		return studio.presence.cable_end(peer, from) if studio.presence != null else null
	studio.jacks.keys = Session.guest_midi
	Session.jack_played.connect(studio.jacks.received)
	Session.jack_check = studio.patch_host._jack_refusal
	Session.participant_left.connect(studio.patch_host._on_jack_player_left)
	studio.patch_host._wear_wrist_jacks()
	# The sockets made before there were jacks to ask: shown now.
	studio.jacks.show_all()
	studio.items.child_exiting_tree.connect(studio.patch_host._on_item_leaving)
	studio.items.played.connect(studio.patch_host._on_item_played)
	if Session.guest_midi != null:
		# Everything this player's keys send, from every source, into their loop while they loop.
		Session.guest_midi.sends.connect(_on_keys_sent)
	Session.participant_left.connect(_on_looper_player_left)
	studio.items.moved.connect(_on_item_moved)
	if studio.presence != null:
		studio.presence.items = studio.items
	# AR makes no items while playing: no rack, no shelf to keep them on.
	if studio.medium != Presentation.Medium.AR:
		_wire_made_items()


# --- made items: cassettes (docs/spatial_loop.md part two, slice 23) ------------------------
#
# A clip pulled out of the timeline is a cassette in the hand that pulled it: minted by the host
# (ItemRoom.mint) from its own song, its data sent once (Session.publish_made) and named by id in
# the room. A guest's pull is an ask (`make`) and a blank cassette in its hand until the host's
# arrives there or the ask is refused. Handed over: thrown, held by a bandmate's glove
# (GIVE_REACH, GIVE_HOLD), or clicked on their ghost at a desk; the room's `give` puts it in their
# hand. Shelved on the rack's slots, binned in its BIN. Pressed onto a lane, a strip or a stage voice,
# pasted there (slice 24): the host's own at once, a guest's asked by id with the room's `paste`.


func _wire_made_items() -> void:
	studio.items.made = Session.made
	studio.items.authority = Session.is_authority
	studio.items.made_home = studio.venue_switch._made_home
	studio.items.press_ahead = studio.sampler_host._press_ahead
	studio.items.minted.connect(_on_minted)
	studio.items.unmade.connect(_on_unmade)
	studio.items.told.connect(_on_items_told)
	studio.items.used.connect(_on_item_used_here)
	studio.items.paste_pressed.connect(_on_paste_pressed)
	Session.made_changed.connect(_on_made_changed)
	Session.holds_changed.connect(_take_given_soon)
	if studio.timeline != null:
		studio.timeline.clip_pulled.connect(_on_clip_pulled)
	studio.pieces.hold_the_rack()
	studio.sampler_host._restore_made()


## Something in the room moved: told to the room, and a made item's place kept with the layout.
func _on_item_moved(item: Item) -> void:
	studio.player_host._publish_room_soon()
	if ItemRoom.is_made(item.id) and Session.is_authority():
		studio.player_host._remember_made_soon()


func _on_items_told(text: String) -> void:
	Session.notice.emit(text)


## Minted here, on the host: its row to everyone once, and kept with this host's layout.
func _on_minted(item: Item) -> void:
	Session.publish_made(item.id)
	studio.sampler_host._remember_made()
	studio.player_host._publish_room_soon()


## Binned here, on the host: gone everywhere, row and all.
func _on_unmade(id: StringName) -> void:
	Session.drop_made(id)
	Session.notice.emit("Binned %s." % _made_name(id))
	studio.sampler_host._remember_made()
	studio.player_host._publish_room_soon()


func _made_name(id: StringName) -> String:
	var kind := ItemRoom.kind_of(id)
	return "%s %s" % [String(kind), String(id).trim_prefix(String(kind))]


## A guest heard the host take a made item away: here too.
func _on_made_changed(id: StringName, gone: bool) -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	if gone and studio.items != null:
		studio.items.forget_made(id)


## A hand here pulled track `track`'s item `index` out of the timeline: the host's own pull is a
## cassette in that hand at once; a guest's is an ask, and a blank one in the hand meanwhile.
func _on_clip_pulled(track: int, index: int, hand: Node) -> void:
	var interactor := hand as Interactor
	if studio.items == null or interactor == null:
		return
	var from := "clip:%d:%d" % [track, index]
	if Session.is_authority():
		var made := _mint_for(CassetteItem.KIND, from, Session.local_peer_id)
		if made != null:
			interactor.pick_up(made)
			_say_cassette(made)
		return
	var seq := studio.room_rows._predict(&"make", [CassetteItem.KIND, from])
	if seq > 0:
		var look := ItemRoom.look_of(CassetteItem.KIND)
		look.top_level = true
		look.name = "MakingCassette"
		studio.add_child(look)
		studio._making.append({"seq": seq, "hand": interactor, "look": look})
		Session.notice.emit("Asking %s for a cassette of it..." % Session.name_of(1))


## A made item of `kind`, of what `from` names in the host's own song, made by `maker`: minted, or
## null with `maker` told why not.
func _mint_for(kind: StringName, from: String, maker: int) -> Item:
	if studio.items == null:
		return null
	var made := studio.items.mint(kind, ItemRoom.made_data(kind, from), maker)
	if made == null:
		Session.tell(maker, studio.items.mint_refusal)
	return made


## Made item `made`, just minted for `maker`'s pull: in their hand, everywhere.
func _hand_made(made: Item, maker: int) -> void:
	if maker == Session.local_peer_id:
		var hand := _free_hand()
		if hand != null:
			hand.pick_up(made)
	else:
		Session.hand_to(maker, made.network_key())
	studio.player_host._publish_room_soon()


## How a cassette just put in a hand is used, said once. A tracked bare hand has no trigger, so it is
## told only of the push (Interactor.paste_press_words).
func _say_cassette(made: Item) -> void:
	var desk := studio.medium == Presentation.Medium.SCREEN
	var press := made.carried_by.paste_press_words() if is_instance_valid(made.carried_by) else "a press"
	Session.notice.emit(("%s is in your hand: hold L to hear it; click a timeline lane, a strip or a stage voice to paste it, a bandmate to hand it over, a rack slot to shelve it; Q puts it down."
			if desk else "%s is in your hand: hold it to your ear to hear it; " + press + " on a timeline lane, a strip or a stage voice pastes it; hold it by a bandmate's glove to hand it over, let it go by a rack slot to shelve it.")
			% made.item_title().capitalize())


## The blank cassettes waiting in hands follow them.
func _follow_making() -> void:
	for m: Dictionary in studio._making:
		var hand := m["hand"] as Interactor
		var look := m["look"] as Node3D
		if is_instance_valid(hand) and is_instance_valid(look):
			look.global_transform = hand.carry_pose() * Transform3D(Basis(Vector3.UP, PI), Vector3(0, -0.01, 0))


## The host has answered every pull up to `answered`: each one's blank cassette goes, and its hand
## waits for the made one the holds put there (`_take_given`); a refused one's hand waits for
## nothing, and the host has said why.
func _settle_makes(answered: int) -> void:
	var still: Array = []
	for m: Dictionary in studio._making:
		if int(m["seq"]) > answered:
			still.append(m)
			continue
		if is_instance_valid(m["look"]):
			(m["look"] as Node3D).queue_free()
		_awaiting_hands.append(m["hand"])
	studio._making = still
	_take_given()
	_awaiting_hands.clear()


func _take_given_soon() -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	_take_given.call_deferred()


## Whatever the holds say is in this player's hand and no hand here has yet: a made item minted
## for this guest's pull, or something handed over. Into the hand that pulled it, else a free one.
func _take_given() -> void:
	if studio.items == null or not studio.is_inside_tree():
		return
	var pending := {}
	for p in studio._predictions:
		if p["verb"] in [&"put_item", &"home_item", &"throw_item", &"slot_item", &"give"]:
			pending[p["args"][0]] = true
	for id in studio.items.items:
		var item: Item = studio.items.items[id]
		if item.carried_by != null or pending.has(id) or not ItemRoom.is_made(id) \
				or Session.holder_of(item.network_key()) != Session.local_peer_id \
				or not (item.is_held_elsewhere() or item.state == Item.State.HOME):
			continue
		var hand: Interactor = null
		while hand == null and not _awaiting_hands.is_empty():
			var waiting = _awaiting_hands.pop_front()
			if is_instance_valid(waiting) and (waiting as Interactor).carrying == null:
				hand = waiting
		if hand == null:
			hand = _free_hand()
		if hand != null:
			hand.pick_up(item)


## A hand of this player's with nothing in it: the mouse's on a desktop, else an empty controller
## or hand, else the mouse's or the first, whose pick-up pockets what it has.
func _free_hand() -> Interactor:
	var first: Interactor = null
	for node in studio.get_tree().get_nodes_in_group(Interactor.GROUP):
		var hand := node as Interactor
		if hand == null or not hand.is_inside_tree():
			continue
		if hand.carrying == null:
			return hand
		if first == null:
			first = hand
	return first


## Hand `item`, in a hand here, to `peer`: at once on the host; a guest asks, and its glove lets go
## into theirs meanwhile.
func give_item(item: Item, peer: int) -> void:
	if peer <= 0 or peer == Session.local_peer_id or not Session.participants.has(peer):
		return
	if Session.is_authority():
		_give(item, peer, Session.local_peer_id)
		return
	if item.carried_by != null:
		item.carried_by.lose_carrying()
	if studio.presence != null:
		item.follow(studio.presence.palm_of(peer, item))
	studio.room_rows._predict(&"give", [item.id, peer])
	Session.notice.emit("Handed %s to %s." % [_given_name(item), Session.name_of(peer)])


## The host hands `item` from `from` to `peer`: out of a hand here if one has it, into theirs.
func _give(item: Item, peer: int, from: int) -> void:
	if item.carried_by != null:
		item.carried_by.lose_carrying()
	# The table first: the hand that takes it here then finds it already this player's.
	Session.hand_to(peer, item.network_key())
	if peer == Session.local_peer_id:
		var hand := _free_hand()
		if hand != null:
			hand.pick_up(item)
	var what := _given_name(item)
	Session.tell(peer, "%s handed you %s." % [Session.name_of(from), what])
	if from == Session.local_peer_id:
		Session.notice.emit("Handed %s to %s." % [what, Session.name_of(peer)])
	studio.player_host._publish_room_soon()


## A cassette pressed onto `track` at `seconds` by a hand here (ItemRoom.paste_pressed;
## docs/spatial_loop.md part two, slice 24): the host pastes it at once; a guest asks with the room's
## `paste` [id, track, time], and the host pastes the clip it holds. The cassette stays in the hand.
func _on_paste_pressed(item: Item, track: int, seconds: float) -> void:
	var cassette := item as CassetteItem
	if cassette == null or not cassette.pastes():
		return
	if Session.is_authority():
		paste_cassette(cassette, track, seconds, Session.local_peer_id)
		return
	if studio.room_rows._predict(&"paste", [cassette.id, track, seconds]) > 0:
		var t := DAW.state.track(track, false)
		Session.notice.emit("Asking %s to paste the %s cassette onto %s at %s..." % [Session.name_of(1),
				cassette.clip_name(), t.display_name() if t != null else "track %d" % track, DAW.state.bar_beat(seconds)])


## The host pastes `cassette`'s clip onto `track` at `seconds` for `who` (this machine's own peer, or
## the guest who asked): one undo step that is theirs, or refused with the reason. Both are told; the
## host as well when it is a guest's, since an item appearing on its timeline unannounced is a
## surprise mid-session.
func paste_cassette(cassette: CassetteItem, track: int, seconds: float, who: int) -> void:
	var why := DAW.paste_item(track, seconds, cassette.clip)
	if not why.is_empty():
		Session.tell(who, why)
		return
	var said := "the %s cassette onto %s at %s" % [cassette.clip_name(), DAW.state.track(track).display_name(),
			DAW.state.bar_beat(seconds)]
	Session.tell(who, "Pasted %s." % said)
	if who != Session.local_peer_id:
		Session.notice.emit("%s pasted %s." % [Session.name_of(who), said])


## What a hand-over toast calls `item`: a cassette by its clip's name as the song has it ("the
## Kick verse 1 cassette"), anything else by its title.
func _given_name(item: Item) -> String:
	var cassette := item as CassetteItem
	if cassette != null:
		return "the %s cassette" % cassette.clip_name()
	return item.item_title().to_lower()


## A click with a made item in the mouse's hand and nothing under the cursor: on a bandmate's
## ghost, it is theirs.
func _on_item_used_here(item: Item, down: bool) -> void:
	if not down or studio.presence == null or not ItemRoom.is_made(item.id) or not (item.carried_by is MouseInteractor):
		return
	var aim := item.carried_by.aim()
	var peer := studio.presence.peer_at(aim.origin, -aim.basis.z)
	if peer != 0:
		give_item(item, peer)


# --- the weather (docs/spatial_loop.md part two, slice 44) ----------------------------------
#
# The switch is the room's row `weather`: a guest's press is the room's ask `weather` [on], shown at
# once here; the host's is done. Every machine schedules the same drops from its own song clock, so
# nothing else crosses the wire: the host alone records them, onto the track the jack goes into.


## A hand here pressed the weather's switch: `on` for LISTEN, off for OFF.
func _on_weather_pressed(on: bool) -> void:
	if Session.is_authority():
		_set_weather(on)
	elif studio.room_rows._predict(Weather.VERB, [on]) > 0:
		_show_weather(on)
	var what := str(studio.weather.spec.get("title", "the weather")).to_lower() if studio.weather != null else "the weather"
	var said := what.left(1).to_upper() + what.substr(1)
	Session.notice.emit("%s: LISTEN. Each drop is a note of the song's scale, %s, heard by everyone. Its jack records them onto a track." \
			% [said, Weather.pitch_of(studio.weather.spec if studio.weather != null else {})] if on else "%s: OFF. The drops fall silent." % said)


## The room's word on the switch: LISTEN or OFF, shown here and told to the room.
func _set_weather(on: bool) -> void:
	_show_weather(on)
	studio.player_host._publish_room_soon()


## The switch shown as the room has it, on this weather and any stood later.
func _show_weather(on: bool) -> void:
	studio.weather_listening = on
	if studio.weather != null and is_instance_valid(studio.weather):
		studio.weather.listening = on


## A drop landed (Weather.dropped): its jack's lead shows it, and the host records it onto the track
## the jack goes into, heard or not. Every machine has the same drop, so only one takes it down.
func _on_weather_dropped(drop: Dictionary) -> void:
	if studio.jacks == null:
		return
	var source := StringName(drop["source"])
	var track := Jack.track_of(studio.jacks.sink_of(source))
	if track <= 0:
		return
	studio.jacks.heard_from(source, int(drop["velocity"]))
	if Session.is_authority() and studio.hit_recorder != null and Jacks.takes_midi(track):
		studio.hit_recorder.note(track, int(drop["note"]), int(drop["velocity"]), InstrumentItem.MELODIC_CHANNEL,
				float(drop["length"]), float(drop["song"]))


# --- the looper (docs/spatial_loop.md part two, slice 45) -----------------------------------
#
# Who is looping is the room's row `looper` [peer, from_bar, bars]: a guest's slap is the room's ask
# `looper` [from_bar, bars], shown at once here; the host's is answered (Looper.answer). The layer is
# taken down where it is played, by the song as its player hears it, and written on the host: a
# guest's sent whole (`looper_layer`), for the host to put on a track of theirs.


## What a player is called on the looper's screen and their tracks: their name, or this player's own.
func _looper_name(peer: int) -> String:
	if peer == Session.local_peer_id and Session.local_name != "":
		return Session.local_name
	return Session.name_of(peer)


## A hand here slapped the looper's pad: armed (the host's own at once, a guest's asked and shown),
## refused while somebody else loops, called off during this player's own count.
func _on_looper_slapped() -> void:
	if studio.looper == null:
		return
	var me := Session.local_peer_id
	var why := Looper.refusal(studio.looper_row, me, _looper_name)
	if why != "":
		Session.notice.emit("%s: one player at a time. Slap again when their layer is done." % why)
		return
	if not studio.looper_row.is_empty():
		if studio.looper.phase == Looper.Phase.COUNT:
			_on_looper_called_off()
			Session.notice.emit("Loop called off.")
		elif studio.looper.phase == Looper.Phase.REC:
			Session.notice.emit("Recording your layer: it ends at bar %d." % (int(studio.looper_row[1]) + int(studio.looper_row[2])))
		return
	var plan := Looper.plan(DAW.state, studio.looper.heard(), studio.looper_length)
	# Read before the answer, which sets the loop for a first layer.
	var stacking := Looper.loop_set(DAW.state)
	if Session.is_authority():
		_answer_looper(plan[0], plan[1], me)
	elif studio.room_rows._predict(Looper.VERB, plan) > 0:
		_show_looper([me, plan[0], plan[1]])
	var bars := int(plan[1])
	Session.notice.emit(("Stacking a layer: the rest of this pass counts in, then %d bar%s of everything you play." \
			if stacking else "Looping: a bar's count, then %d bar%s of everything you play, keys and hits, as a layer of your own.") \
			% [bars, "" if bars == 1 else "s"])


## Host: `from`'s slap (theirs asked, or this player's own): Looper.answer against the room's row, and
## the row told to the room. A refusal is told to them; their own screen goes back with the room.
func _answer_looper(from_bar: int, bars: int, from: int) -> void:
	var out := Looper.answer(studio.looper_row, from_bar, bars, from, _looper_name)
	if bool(out["refused"]):
		Session.tell(from, "%s One player at a time." % out["said"])
	_show_looper(out["row"])
	studio.player_host._publish_room_soon()


## This player's layer is taken down (Looper.layer_done): the host's written at once, a guest's sent.
func _on_looper_layer(start: float, end: float, notes: Array) -> void:
	if Session.is_authority():
		_write_looper_layer(start, end, notes, Session.local_peer_id)
	elif studio.room_rows._predict(Looper.LAYER_VERB, [start, end, notes]) > 0:
		_show_looper([])


## Host: `from`'s layer onto a track of theirs (Looper.write_layer), their row cleared. A layer with
## nothing played in it makes no track. Only the row's own player's, and only while it is theirs; and
## it goes where the row says, over the row's bars as the host has them (Looper.span_of), not where
## the layer says it began and ended, with only the notes begun inside them (Looper.inside).
func _write_looper_layer(_start: float, _end: float, notes: Array, from: int) -> void:
	if studio.looper_row.is_empty() or int(studio.looper_row[0]) != from:
		return
	var span := Looper.span_of(studio.looper_row, DAW.state)
	_show_looper([])
	studio.player_host._publish_room_soon()
	var kept := Looper.inside(notes, span).slice(0, MidiTake.MAX_NOTES)
	if kept.is_empty():
		Session.tell(from, "Nothing was played into the loop, so there is no layer. Slap again to try another.")
		return
	var made := Looper.write_layer(_looper_name(from), float(span[0]), float(span[1]), kept)
	Session.tell(from, "%s: %d note%s on a track of its own in the LOOPER folder. Slap again while it loops to stack another." \
			% [made["name"], kept.size(), "" if kept.size() == 1 else "s"])


## This player's count or layer was cut short (the transport stopped, the riser gone): their row
## cleared, by the host or asked of it.
func _on_looper_called_off() -> void:
	if Session.is_authority():
		_answer_looper(0, 0, Session.local_peer_id)
	elif studio.room_rows._predict(Looper.VERB, [0, 0]) > 0:
		_show_looper([])


## The room's row on this looper and any stood later.
func _show_looper(row: Array) -> void:
	studio.looper_row = row.duplicate()
	if studio.looper != null and is_instance_valid(studio.looper):
		studio.looper.row = studio.looper_row


## What this player's keys send, into their loop while they loop.
func _on_keys_sent(kind: int, pitch: int, velocity: int, song: float, channel: int) -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	if studio.looper != null and is_instance_valid(studio.looper):
		studio.looper.key(kind, pitch, velocity, song, channel)


## Host: whoever was looping left: nobody is now.
func _on_looper_player_left(peer: int) -> void:
	if not is_instance_valid(studio):
		return  # a signal outliving the studio it was connected for
	if Session.is_authority() and not studio.looper_row.is_empty() and int(studio.looper_row[0]) == peer:
		_show_looper([])
		studio.player_host._publish_room_soon()
