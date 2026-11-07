class_name PieceHost
extends RefCounted

## Stands the pieces of the live room in a Studio and carries what rides with them
## (docs/layouts.md 4.1, 11 step 6). The studio keeps the pieces' trolleys (`live_pieces`) and the
## nodes themselves, which are the venue's children; this reads each piece's `PieceDef` and does
## what the studio used to do per piece: `build` makes the trolley from the definition, `carry`
## moves the piece's node to where its trolley is and runs its followers, and `stand` makes a
## piece's node (the fifths wheel, the section blocks, the rack, the sampler, the drums' plaque, the
## looper, the lyric board, the venue's instrument and weather) at its spot in the venue and hangs
## it there. The spot is the station's (`Stations.spot`), which for the wheeled and the zone-mounted
## ones is the layout's (`Venue.default_spot`). The rehoming
## helpers (`rehome_items`, `rehome_spills`, `hold_the_rack`) live here because the followers are
## what call them; the studio calls them too, when a room is built or an item set up.

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## A trolley for each of `Venue.WHEELED`, from its definition, stood where this venue has it and
## registered as a live piece. Pushed across the floor on its own feet, not wheeled.
func build() -> void:
	var venue := studio.venue
	for id: StringName in Venue.WHEELED:
		var def := PieceDef.of(id)
		var spot: Variant = venue.default_spot(id) if venue != null else null
		var at: Transform3D = spot if spot != null else Transform3D.IDENTITY
		var t := studio._trolley(def.trolley_name, id, at.origin, rad_to_deg(at.basis.get_euler().y))
		equip(t, def)
		studio._go_live(t)


## Give trolley `t` the feet of definition `def`: its footprint, how heavy it is to push, what it is taken
## by and where a walker bumps it. The five pieces' trolleys and a copy a room added are made alike.
func equip(t: Trolley, def: PieceDef) -> void:
	t.footprint_centre = def.foot_centre
	t.footprint_half = def.foot_half
	t.follow = def.weight
	t.rolls = false
	for grip: Array in def.grips:
		studio._grip(t, grip[0], grip[1])
	if def.body_half != Vector2.ZERO:
		t.body_centre = def.body_centre
		t.body_half = def.body_half


## Stand every piece in `PieceDef.standing()` in the venue, each a child of it, in the order the
## studio always did. Called once a venue is in the tree; the modular rack and the weather, which the
## studio stands after, are not in the list (`stand` takes the weather by itself).
func stand_all() -> void:
	for id in PieceDef.standing():
		stand(id)


## Make piece `id`'s node and hang it on the venue where its spot is; the studio's variable for it
## (`PieceDef.studio_node`) is the new node, or null where the venue has no room for it (no bricks
## table, no riser, no booth, no instrument, no weather in this arrangement). What carried over from
## the last venue's node (`was`) is taken across by that piece's arm of `_make`.
func stand(id: StringName) -> void:
	var def := PieceDef.of(id)
	var venue := studio.venue
	var held: Variant = studio.get(def.studio_node)
	var was: Node3D = held as Node3D if _stands(held) else null
	studio.set(def.studio_node, null)
	var spec := {}
	var at: Variant = null
	if def.mount == PieceDef.Mount.VENUE:
		spec = VenueInstrument.spec_of(venue) if id == VenueInstrument.STATION else Weather.spec_of(venue)
		at = spec.get("spot")
	else:
		at = null if studio.room_deltas.delta.is_removed(id) else Stations.spot(venue, id)
	var node: Node3D = _make(id, at, spec, was) if at != null else null
	if node != null:
		studio.set(def.studio_node, node)
		venue.add_child(node)
		_hung(id, node)
	elif id == Looper.STATION and was != null and (was as Looper).mine():
		# A layer it was taking down in the last venue has nowhere to finish.
		studio._on_looper_called_off()
	if id == VenueInstrument.STATION:
		studio._dress_venue_bars()


## Take piece `id`'s node down (a room that does without it): freed, the studio's variable null as where
## a venue has no room for it, and what rode on it let go of (the rack's slots, the shelf's toys).
func unstand(id: StringName) -> void:
	var def := PieceDef.of(id)
	var held: Variant = studio.get(def.studio_node)
	if id == Looper.STATION and _stands(held) and (held as Looper).mine():
		# A layer this player was taking down has nowhere to finish.
		studio._on_looper_called_off()
	if _stands(held):
		(held as Node).get_parent().remove_child(held)
		(held as Node).queue_free()
	studio.set(def.studio_node, null)
	hold_the_rack()
	rehome_items()


## The node of piece `id` for spot `at` (and `spec`, for the two the shell describes), with what it
## needs of the studio wired; `was` is the last venue's node of it, or null.
func _make(id: StringName, at: Transform3D, spec: Dictionary, was: Node3D) -> Node3D:
	match id:
		&"wheel":
			var wheel := FifthsWheel.new()
			wheel.transform = FifthsWheel.on_stand(at)
			return wheel
		&"sections":
			var sections := SectionBlocks.new()
			sections.transform = at
			return sections
		&"cassette_rack":
			var rack := CassetteRack.new()
			rack.transform = at
			rack.items = studio.items
			return rack
		&"sampler":
			# REC is the room's, kept across a change of venue.
			var sampler := Sampler.new()
			sampler.transform = at
			sampler.items = studio.items
			sampler.authority = Session.is_authority
			sampler.local_peer = func() -> int: return Session.local_peer_id
			sampler.name_of = Session.name_of
			sampler.armed_by = (was as Sampler).armed_by if was != null else 0
			sampler.rec_pressed.connect(studio._on_rec_pressed)
			sampler.told.connect(func(peer: int, text: String) -> void: Session.tell(peer, text))
			sampler.armed_changed.connect(studio._publish_room_soon)
			return sampler
		&"drums":
			return _drum_circle(at)
		&"looper":
			var looper := Looper.new()
			looper.transform = at
			looper.local_peer = func() -> int: return Session.local_peer_id
			looper.name_of = studio._looper_name
			looper.length = studio.looper_length
			looper.row = studio.looper_row
			if was != null:
				looper.take_over(was as Looper)
			looper.slapped.connect(studio._on_looper_slapped)
			looper.length_changed.connect(func(bars: int) -> void: studio.looper_length = bars)
			looper.layer_done.connect(studio._on_looper_layer)
			looper.called_off.connect(studio._on_looper_called_off)
			return looper
		&"lyrics":
			var board := LyricBoard.new()
			board.transform = at
			board.told.connect(func(text: String) -> void: Session.notice.emit(text))
			board.edit_asked.connect(studio.edit_lyrics)
			return board
		&"venue":
			var instrument := VenueInstrument.new(spec)
			instrument.transform = at
			return instrument
		&"weather":
			var weather := Weather.new(spec, Weather.seed_of(studio.venue.venue_id()))
			weather.transform = at
			weather.listening = studio.weather_listening
			weather.switch_pressed.connect(studio._on_weather_pressed)
			weather.dropped.connect(studio._on_weather_dropped)
			return weather
	return null


## What a piece needs once it is a child of the venue (its own children exist then).
func _hung(id: StringName, node: Node3D) -> void:
	if id == Looper.STATION:
		# Its layers' rings say what a grab, a click or a pull did, as a toast.
		(node as Looper).rings.told.connect(func(text: String) -> void: Session.notice.emit(text))


## The circle of hand drums' plaque, at the ring's middle on the drum riser. The drums themselves are
## the room's items, whose homes are their places round it (`Studio._item_homes`).
func _drum_circle(at: Transform3D) -> Node3D:
	var ring := Node3D.new()
	ring.name = "DrumCircle"
	ring.transform = at
	var plaque := Stations.plaque(&"drums", Stations.DRUM_PLAQUE_WIDTH)
	plaque.transform = Transform3D(Basis(Vector3.RIGHT, -Stations.DRUM_PLAQUE_TILT), Stations.DRUM_PLAQUE)
	ring.add_child(plaque)
	# A slim post under it, so it stands on the riser rather than hanging in the air.
	var post := MeshInstance3D.new()
	post.name = "Post"
	var rod := CylinderMesh.new()
	rod.top_radius = 0.012
	rod.bottom_radius = 0.018
	rod.height = Stations.DRUM_PLAQUE.y - 0.02
	post.mesh = rod
	post.position = Vector3(0, rod.height * 0.5, Stations.DRUM_PLAQUE.z - 0.03)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.1, 0.1, 0.11)
	metal.roughness = 0.4
	metal.metallic = 0.8
	post.material_override = metal
	ring.add_child(post)
	return ring


## Take piece `id` to where its trolley is now: its node, then each follower in order. Each frame
## the trolley moves, so a shelf's toys ride on it rather than catching up. False when `id` is not
## one of the defined pieces or a copy a room added (the caller's own arms handle the rest).
func carry(id: StringName) -> bool:
	var def := PieceDef.of(id)
	if def == null:
		return RoomSync.carry_copy(studio, id)
	var venue := studio.venue
	var node: Node3D = _node_of(def)
	var spot: Variant = venue.call(StringName("%s_spot" % id))
	var standing := node != null and spot != null
	if standing:
		node.transform = studio._venue_to_set(spot) if def.node_in_set else spot
	for follower in def.followers:
		match follower:
			PieceDef.HOLD_RACK:
				if standing:
					hold_the_rack()
			PieceDef.SPILLS:
				if standing:
					rehome_spills()
			PieceDef.BOARDS:
				if studio.items != null:
					studio.items.boards = venue.dart_boards()
			PieceDef.HOOPS:
				if studio.items != null:
					studio.items.hoops = RoomSync.hoops(studio)
			PieceDef.ITEMS:
				rehome_items()
			PieceDef.HOLD_RACK_IF_GONE:
				# A cassette lies on the shelf when the rack is gone (`Studio._made_home`).
				if not _stands(studio.cassette_rack):
					hold_the_rack()
	return true


## The node that is piece `def`, or null where it is not built: a variable of the studio (valid
## only while alive) or a child of the venue.
func _node_of(def: PieceDef) -> Node3D:
	if def.studio_node != &"":
		var held: Variant = studio.get(def.studio_node)
		return held as Node3D if _stands(held) else null
	return studio.venue.get_node_or_null(def.venue_child) as Node3D


static func _stands(node: Variant) -> bool:
	return node != null and is_instance_valid(node)


## The items' homes from where the shelf and the hoop now are: one at home goes to its new spot
## (ItemRoom.set_spots).
func rehome_items() -> void:
	if studio.items != null and studio.venue != null:
		studio.items.set_spots(studio.venue.item_spots(), studio._item_homes())


## What the Tour case spilled, homed round where the case now stands (`Studio._spill_home`).
func rehome_spills() -> void:
	var items := studio.items
	if items == null or studio.tour_case == null:
		return
	var spilled := items.spawned_ids()
	for n in spilled.size():
		var item: Item = items.items.get(spilled[n])
		if item != null:
			item.home = studio._spill_home(n)


## The rack's slots and bin as the room's holders, and each made item's home its tray, in the
## room's frame (the venue's, as the shelf's spots are).
func hold_the_rack() -> void:
	var items := studio.items
	if items == null:
		return
	var rack := studio.cassette_rack
	if not _stands(rack):
		items.holders.clear()
		studio._hold_the_platter()
		return
	rack.items = items
	if _stands(studio.sampler):
		studio.sampler.items = items
	var at := rack.transform
	items.set_holder(CassetteRack.RACK, CassetteRack.slots_in(at))
	var bin: Array[Transform3D] = [at * CassetteRack.bin_pose()]
	items.set_holder(CassetteRack.BIN, bin)
	for id in items.made_ids():
		var item: Item = items.items[id]
		item.home = studio._made_home(ItemRoom.kind_of(id), int(String(id).trim_prefix(String(ItemRoom.kind_of(id)))))
		if item.state == Item.State.HOME:
			item.snap_home()
	studio._hold_the_platter()
