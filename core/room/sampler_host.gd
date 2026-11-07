class_name SamplerHost
extends RefCounted

## The sampler: arming it, sampling a take from an item, the platter and the scratch, other players' hits and uses, the gives,
## and remembering and restoring what the player made. Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the calls other code makes.

## A headset hand holding a made item by a bandmate's glove: {hand: [peer, seconds]} (`_follow_gives`).
var _give_held := {}

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


# --- the sampler (docs/spatial_loop.md part two, slice 26) ----------------------------------
#
# REC is the room's row `sampler`, the peer it is armed for: a guest's press is the room's ask
# `sampler` [on], shown at once here; the host's is done. Every use and hit reaches the host with
# the Foley take its player's hand rang, and the host's sampler (`Sampler.heard`) catches the first
# one in its reach, or in its presser's hand, as a WAV and a cassette on the rack, and REC goes off.

## A hand here pressed the sampler's REC.
func _on_rec_pressed(on: bool) -> void:
	if studio.sampler == null or not is_instance_valid(studio.sampler):
		return
	var me := Session.local_peer_id
	if Session.is_authority():
		_arm_sampler(on, me)
	elif studio.room_rows._predict(Sampler.VERB, [on]) > 0:
		studio.sampler.armed_by = me if on else 0
	var desk := studio.medium == Presentation.Medium.SCREEN
	Session.notice.emit(("Sampler REC: the next thing you squeeze, click or shake, a yo-yo or card trick, or a bounce of the ball, or anything used within %.1f m of its mic, is a sample on the rack. Click REC again to stop."
			if desk else "Sampler REC: the next thing you squeeze, hit or shake, a yo-yo or card trick, or a bounce of the ball, or anything used within %.1f m of its mic, is a sample on the rack. Press REC again to stop.") % Sampler.REACH
			if on else "Sampler REC off.")


## The room's word on REC: on for `from`'s next sound, or off.
func _arm_sampler(on: bool, from: int) -> void:
	if studio.sampler == null or not is_instance_valid(studio.sampler):
		return
	studio.sampler.armed_by = from if on else 0
	studio.player_host._publish_room_soon()


## A use of `item` (Foley's `kind`, take `take`, played `pitch` fast) by `from`, for the sampler to
## catch: only the host's does (Sampler.heard).
func _sample(item: Item, kind: StringName, take: int, from: int, pitch := 1.0) -> void:
	if _sampling():
		studio.sampler.heard(item, kind, take, from, pitch)


## Whether the sampler is waiting for a sound: what is asked of a use (its pitch reads the song
## clock) only then.
func _sampling() -> bool:
	return studio.sampler != null and is_instance_valid(studio.sampler) and studio.sampler.armed_by != 0


## Where this machine has the platter's audio clip's file `source`: the host's media folder, or a
## guest's fetched copy, its fetch begun when it has none yet (FileSend.fetch); "" until then.
func _platter_file(source: String) -> String:
	if source.is_empty():
		return ""
	if Session.role == Session.Role.GUEST:
		if Session.files == null:
			return ""
		var got := Session.files.fetched_path(source)
		if got.is_empty() and Session.files.fetch_state(source) == &"":
			Session.files.fetch(source)
		return got
	var path := DAW.backend.media_path(source) if DAW.backend != null else ""
	return path if not path.is_empty() and FileAccess.file_exists(path) else ""


## A scratch a hand here made on the platter (Platter.scratched), for the sampler: the host renders
## it from its own render of the clip and catches it as a sound of the cassette; a guest's is the
## room's ask `scratch`, its path, only while REC waits.
func _on_scratched(cassette: CassetteItem, path: PackedFloat32Array) -> void:
	if not _sampling() or cassette == null or not is_instance_valid(cassette):
		return
	if Session.is_authority():
		_sample_scratch(cassette, path, Session.local_peer_id)
	else:
		Session.ask_room(Platter.SCRATCH_VERB, [cassette.id, path])


## The host: `from`'s scratch of `cassette` along `path`, rendered (Platter.render_scratch) and given
## the sampler as the platter's sound of it. Only when REC waits and would catch it (Sampler.catches):
## a render is real work, and nobody's ask makes it for nothing.
func _sample_scratch(cassette: CassetteItem, path: PackedFloat32Array, from: int) -> void:
	if studio.platter == null or not is_instance_valid(studio.platter) or not _sampling() \
			or not studio.sampler.catches(cassette, from) or not Varispeed.fits(path):
		return
	studio.platter.render_scratch(cassette, path, func(wav: AudioStreamWAV) -> void:
		if wav != null and _sampling() and is_instance_valid(cassette):
			studio.sampler.heard_stream(cassette, &"platter_scratch", wav, from))


## A hand here used what it carries: a squeeze, a click, a trick.
func _sample_use_here(item: Item, down: bool) -> void:
	if down and _sampling():
		_sample(item, item.use_kind(true), item.use_take, Session.local_peer_id, item.use_pitch())


## A sound an item rang of its own on this copy (Item.rang): a ball's bounce, the thrower's. Every
## copy flies a throw the same, so the host's copy's is the one its thrower heard.
func _sample_ring(item: Item, kind: StringName, take: int, pitch: float) -> void:
	_sample(item, kind, take, item.thrown_by, pitch)


## Somebody else's use, as the host hears it, with the take their hand rang: only of what is in
## their hand, as Presence rings only that. A pitched instrument's click comes as a hit too, with
## the song position that pitches it, and is caught from that (`_on_someones_hit`).
func _on_someones_use(id: StringName, down: bool, from: int, take := -1) -> void:
	if not is_instance_valid(studio):
		return
	var item: Item = studio.items.items.get(id) if studio.items != null else null
	if down and _sampling() and item != null and from != Session.local_peer_id and Session.is_authority() \
			and Session.holder_of(item.network_key()) == from \
			and not (item is InstrumentItem and (item as InstrumentItem).pitched()):
		_sample(item, item.use_kind(true), take, from, item.use_pitch())


## Somebody else's shake: heard here as shaken (Presence: `heard`, not struck), and caught so, at
## the pitch it rang for them (their song position `song` pitches a bar). Their strike on one that
## stands still is nobody's to hold: caught struck, on its zone.
func _on_someones_hit(id: StringName, velocity: int, from: int, song := -1.0, _snap := false, take := -1,
		zone := &"") -> void:
	if not is_instance_valid(studio):
		return
	var item := studio.items.items.get(id) as InstrumentItem if studio.items != null else null
	if item != null and studio.modular_world != null and from != Session.local_peer_id \
			and item.jack_source() == VenueInstrument.SOURCE:
		studio.modular_world.strike(song, velocity)
	if not _sampling() or item == null or from == Session.local_peer_id or not Session.is_authority():
		return
	if item.fixed:
		_sample(item, item.kind_of_hit(true, zone if item.has_zone(zone) else &""), take, from, item.tune_at(song))
	elif Session.holder_of(item.network_key()) == from:
		_sample(item, item.sound_kind(false), take, from, item.tune_at(song))


## How far along the mouse's ray the bandmate a made item in its hand would be handed to stands,
## or INF: nearer than the control behind them, the click is the hand-over (Interactor).
func _press_ahead(item: Item, origin: Vector3, direction: Vector3) -> float:
	if studio.presence == null or not ItemRoom.is_made(item.id) or not (item.carried_by is MouseInteractor):
		return INF
	var hit := studio.presence.peer_along(origin, direction)
	return float(hit[1]) if int(hit[0]) != 0 else INF


## A headset hand holding a made item within GIVE_REACH of a bandmate's glove for GIVE_HOLD hands
## it to them.
func _follow_gives(delta: float) -> void:
	if studio.presence == null or studio.items == null:
		return
	for node in studio.get_tree().get_nodes_in_group(Interactor.GROUP):
		var hand := node as Interactor
		if hand == null or hand is MouseInteractor or not hand.is_inside_tree():
			continue
		var item := hand.carrying
		if not is_instance_valid(item) or not ItemRoom.is_made(item.id):
			_give_held.erase(hand)
			continue
		var peer := studio.presence.glove_near(item.middle(), Studio.GIVE_REACH)
		var was: Array = _give_held.get(hand, [0, 0.0])
		if peer == 0:
			_give_held.erase(hand)
			continue
		var held := (float(was[1]) if int(was[0]) == peer else 0.0) + delta
		if held >= Studio.GIVE_HOLD:
			_give_held.erase(hand)
			studio.item_host.give_item(item, peer)
		else:
			_give_held[hand] = [peer, held]


## The host's made items, with where each is, kept with its layout to be there next time.
func _remember_made() -> void:
	if Session.layout == null or not Session.is_authority() or studio.items == null:
		return
	var where := studio.items.state()
	var out := {}
	for id in studio.items.made:
		var row: Array = studio.items.made[id]
		out[id] = [row[0], row[1], row[2], where.get(id, [])]
	if out == Session.layout.made:
		return
	Session.layout.set_made(out)
	Session.layout.save()


## What the host's layout kept of its made items: theirs again, where they were. `missing_only`,
## only those not here already (back from being a guest), never moving one a hand may have.
func _restore_made(missing_only := false) -> void:
	if Session.layout == null or not Session.is_authority() or studio.items == null:
		return
	for id in Session.layout.made:
		if missing_only and studio.items.items.has(id):
			continue
		var row: Array = Session.layout.made[id]
		# A row the session still has (a studio built again in the same run) is the same row.
		if not studio.items.made.has(id):
			if not ItemRoom.made_refusal(studio.items.made, (row[2] as PackedByteArray).size()).is_empty():
				continue
			studio.items.made[id] = [row[0], int(row[1]), row[2]]
		var item := studio.items._make_real(id)
		var place: Variant = row[3]
		if item == null or not (place is Array):
			continue
		if (place as Array).size() == 3 and str(place[0]) == "slot":
			studio.items.slot(item, StringName(str(place[1])), int(place[2]))
		elif (place as Array).size() >= 4:
			studio.items.lay(item, Vector2(float(place[0]), float(place[2])), float(place[3]))
