class_name VenueSwitch
extends RefCounted

## Changing venue: set and choose a venue, the roulette room and its door, the stops and the venue/set transforms, the role
## change, fitting the stand and the room to the session, and the desk footprint. Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the calls other code makes.

const PATCH_CABINET_DEPTH := 0.12

## How much brighter than each venue's own exposure the room is shown.
const EXPOSURE_LIFT := 1.2

## Where the band was before the Rig Roulette room took them: {"id", "variant"}, or empty.
var _before_the_room := {}

var _desk_box_cache := AABB()

var _desk_box_at := -Studio.DESK_BOX_FOR_MSEC

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


func set_venue(id: StringName, persist := true, variant := 0) -> void:
	if studio.medium == Presentation.Medium.AR:
		return
	if not Venue.is_known(id):
		id = Venue.IDS[0]
	if studio.venue != null:
		studio.remove_child(studio.venue)
		studio.venue.queue_free()
	studio.venue = Venue.make(id, variant)
	studio.venue.name = "Venue"
	studio.room_deltas.enter(studio.venue.venue_id(), studio.venue.variant)
	# The rows that are the venue's own (its instrument's) say this one's from now on.
	Stations.here = studio.venue
	studio.venue.rich = rich_rendering()
	studio.venue.room_width = studio.room_width
	var env := studio.venue_look._house_environment()
	studio.venue_look._house_key(studio.key_light)
	studio.venue.dress(env, studio.key_light)
	if standalone_headset():
		env.glow_enabled = false
		env.ssao_enabled = false
		studio.key_light.shadow_enabled = false
	Materials.apply_style(studio.venue.gear_style())
	GearShape.use(id, studio.venue.roll_board_chalky(), studio.get_tree() if studio.is_inside_tree() else null)
	TrackColours.use(studio.venue.track_palette())
	studio.tablet_host._recolour_tracks()
	# Every venue a touch brighter than it dressed itself: the mid-tones read dark on an ordinary
	# monitor, AgX's above all. Exposure rather than brightness, so blacks stay black.
	env.tonemap_exposure *= EXPOSURE_LIFT
	studio.world_env.environment = env
	studio.add_child(studio.venue)
	_hang_the_roulette_door()
	# Before anything stands at its spot: the spots of what is wheeled about are its trolley's.
	RoomSync.wheel_in(studio)
	studio.pieces.stand_all()
	studio.rack_host._stand_the_modular()
	studio.pieces.stand(&"weather")
	studio.furniture_host._hang_hood_signs()
	var mirror := studio.venue.make_mirror(env)
	studio.venue.add_child(mirror)
	_stand_a_patch_wall()
	studio.furniture_host._set_levels_niche()
	studio.furniture_host._set_tv_mount()
	# The venue built its shelf and hoop where their trolleys stood in the last one.
	studio.furniture_host._carry_all_live()
	mirror.wardrobe.look = Session.local_look
	mirror.wardrobe.look_changed.connect(Session.set_look)
	studio.venue_look._relight()
	if persist and Session.layout != null and Session.is_authority():
		Session.layout.venue = id
		Session.layout.venue_variant = studio.venue.variant
		Session.layout.save()
	studio.venue_look._walk_where_the_venue_lets()
	studio.venue_changed.emit(id)
	studio.room_rows._publish_room()


## The door to (or, in the room itself, out of) Rig Roulette, in the venue's own frame. It is a
## child of the venue, so it goes with it; the venue's own `solids` keep people out of it and the
## floor plan keeps furniture out of it (`_door_footprint`).
func _hang_the_roulette_door() -> void:
	if not studio.roulette_enabled:
		return
	var door := RouletteDoor.new()
	door.name = "RouletteDoor"
	door.leaving = Studio.in_roulette_room_venue(studio.venue)
	door.transform = studio.venue.rig_roulette_door()
	door.used.connect(_on_roulette_door_used)
	studio.venue.add_child(door)


## The room's venue bars dressed as this venue's set, the first of them its count, for the mount to
## brush across: before their homes are stood (ItemRoom.set_spots), so each stands in its own look.
func _dress_venue_bars() -> void:
	if studio.items == null or studio.venue_instrument == null or not is_instance_valid(studio.venue_instrument):
		return
	studio.venue_instrument.bars = VenueInstrument.dress(studio.items, studio.venue_instrument.spec)


## The platter's slot as a holder, where the deck cart stands now (slice 27): again whenever the
## cart is pushed, so a cassette stood in it rides with it.
func _hold_the_platter() -> void:
	if studio.items == null or studio.platter == null or not is_instance_valid(studio.platter):
		return
	studio.platter.items = studio.items
	if studio.deck_trolley == null or not is_instance_valid(studio.deck_trolley):
		return
	var at: Array[Transform3D] = [studio.deck_trolley.transform * Platter.ON_CART * Platter.SLOT_POSE]
	studio.items.set_holder(Platter.HOLDER, at)


## Where made item number `n` lies with nowhere else to be: the rack's tray.
func _made_home(_kind: StringName, n: int) -> Transform3D:
	if studio.cassette_rack == null or not is_instance_valid(studio.cassette_rack):
		return studio.venue.prop_shelf_spot() if studio.venue != null else Transform3D.IDENTITY
	return studio.cassette_rack.transform * CassetteRack.tray_spot(n)


## The wheel in this player's reach (`&"wheel"` in GuestMidi.instruments) while a hand of theirs
## is on it or over it, or a chord pressed on it still sounds: so the synth is up before the
## first press, and a run of presses is one take.
func _follow_wheel() -> void:
	if Session.guest_midi == null:
		return
	var near := studio.wheel != null and is_instance_valid(studio.wheel) and studio.wheel.is_inside_tree() \
			and (studio.wheel.touched() or studio.wheel.sounding())
	Session.guest_midi.reach(FifthsWheel.SOURCE, near)


## Where this player stands, in global space: the walker on a desktop, the head in a headset.
func _standing_at() -> Vector3:
	if studio.walker != null and studio.walker.is_inside_tree():
		return studio.walker.global_position
	if studio.rig != null and studio.rig.head != null and studio.rig.head.is_inside_tree():
		return studio.rig.head.global_position
	if studio.camera != null and studio.camera.is_inside_tree():
		return studio.camera.global_position
	return Vector3(0, 0, 1e6)


## The door was used: the host takes the band through it, the way it points. A guest is told whose
## call it is (the enter and leave asks say so themselves).
func _on_roulette_door_used() -> void:
	if in_roulette_room():
		leave_roulette_room()
	else:
		enter_roulette_room()


## What furniture keeps clear of: the door's footprint, as the floor plan's rectangles.
func _door_footprint() -> Array:
	if studio.venue == null or not studio.roulette_enabled:
		return []
	var door := studio.venue.door_solid()
	return [FloorPlan.footprint(door["c"], door["h"], door["a"])]


## The audio patch wall in every venue: where a venue has hung one (the studio's side room), that
## is the one; anywhere else it stands on two legs, at a little over half the size of the room's
## own: the legs are a trolley (`live_pieces`' "patch_wall"), pushed about like the rest of the
## gear, and the screen goes where they are. By default against the control room's left side,
## turned to face the desk (`ControlRoom`, the `patch_wall` piece).
func _stand_a_patch_wall() -> void:
	if studio.venue.get_node_or_null("PatchWall") != null:
		return
	var wall := PatchWallSurface.new()
	wall.name = "PatchWall"
	wall.set_meta(&"on_legs", true)
	wall.transform = _patch_wall_frame()
	wall.follow = DisplayServer.get_name() != "headless"
	studio.venue.add_child(wall)


func _patch_wall_frame() -> Transform3D:
	var legs: Trolley = studio.live_pieces.get(&"patch_wall")
	var at: Transform3D = legs.transform if legs != null else ControlRoom.spot(&"patch_wall", studio.room_width)
	return _set_to_venue(at) * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * Studio.PATCH_WALL_SCALE),
			Vector3(0, Studio.PATCH_WALL_TOP, 0))


func choose_venue(id: StringName, variant := 0) -> bool:
	if not Session.is_authority():
		Session.notice.emit("Only %s can change the venue." % Session.name_of(1))
		return false
	set_venue(id, true, variant)
	return true


func in_roulette_room() -> bool:
	return studio.venue != null and studio.venue.venue_id() == Venue.ROULETTE_ID


## The host takes the whole band into the Rig Roulette room. It is a place, not a venue: it is
## not saved as the room's venue (a restart opens the venue it was left from), and it reaches
## guests the way a venue does, through the room the host publishes. Remembers the venue and its
## arrangement for `leave_roulette_room`.
func enter_roulette_room() -> bool:
	if not studio.roulette_enabled:
		return false
	if not Session.is_authority():
		Session.notice.emit("Only %s can take the band into the roulette room." % Session.name_of(1))
		return false
	if in_roulette_room() or studio.venue == null:
		return false
	if Tour.run != null:
		Session.notice.emit("Not in the middle of a tour.")
		return false
	_before_the_room = {"id": studio.venue.venue_id(), "variant": studio.venue.variant}
	studio._rolls_this_visit = 0
	set_venue(Venue.ROULETTE_ID, false)
	return true


## And back out, to the venue and arrangement the band left, or the room's saved venue if this
## never saw them go in.
func leave_roulette_room() -> bool:
	if not Session.is_authority():
		Session.notice.emit("Only %s can take the band out of the roulette room." % Session.name_of(1))
		return false
	if not in_roulette_room():
		return false
	var id: StringName = _before_the_room.get("id", &"")
	var variant: int = _before_the_room.get("variant", 0)
	if not Venue.is_known(id) or id == Venue.ROULETTE_ID:
		id = Session.layout.venue if Session.layout != null and Venue.is_known(Session.layout.venue) \
				and Session.layout.venue != Venue.ROULETTE_ID else Venue.IDS[0]
		variant = Session.layout.venue_variant if Session.layout != null else 0
	_before_the_room = {}
	set_venue(id, false, variant)
	return true


## The same venue, arranged another way. The host's to choose, like the venue.
func choose_variant(variant: int) -> bool:
	return choose_venue(studio.venue.venue_id() if studio.venue != null else Venue.IDS[0], variant)


func cycle_venue() -> void:
	choose_venue(Venue.next_after(studio.venue.venue_id() if studio.venue != null else Venue.IDS[0]))


## Whether this participant gets the whole renderer: global illumination, screen-space
## reflections, volumetric light, soft shadows. A desktop does; a standalone headset runs the
## mobile renderer, which has none of it and must not be asked. Decided by what is actually
## running rather than by medium alone -- a desktop forced onto the compatibility renderer
## must fall back too.
func rich_rendering() -> bool:
	return studio.medium == Presentation.Medium.SCREEN \
			and RenderingServer.get_current_rendering_method() == "forward_plus"


## A standalone headset: the mobile renderer, drawn twice a frame, with a mobile GPU to do it.
func standalone_headset() -> bool:
	return studio.medium != Presentation.Medium.SCREEN and not rich_rendering()


## Furniture: the things that hold the gear up.
##
## Separate from the surfaces on purpose, and the line matters. A surface is DRIVEN BY REAPER --
## it exists because the project has tracks or plugins, and its size follows them. A stand is
## not; it is set dressing, it means nothing, and in ROOM mode it is not drawn at all because the
## participant already has real furniture. Mixing the two would mean a rack that cannot be put
## on the floor without inventing a plugin to justify its legs.
## One piece of furniture, as one node.
##
## The furniture used to be a flat heap of boxes under the set: four posts, a shelf, two legs,
## a crossbar, all siblings. That is fine to LOOK at and useless to move, and moving it is now
## required -- a surface summoned to the mix position lands exactly where the stand that used
## to hold it is still standing, and a trolley through the master section is the kind of thing
## no amount of lighting rescues. A rig can hide an assembly. It cannot hide half a trolley
## and leave the other two legs up.
func _assembly(of_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = of_name
	node.add_to_group(&"room_furniture")
	studio.studio_set.add_child(node)
	return node


## What a pushed piece stops at among the venue's own things: its solids (Venue.solids), which in
## a studio no longer include anything of `live_pieces`, flattened to floor-plan footprints.
func _venue_stops() -> Array:
	var out: Array = []
	if studio.venue == null or not studio.venue.is_inside_tree():
		return out
	for f: Dictionary in studio.venue.solids():
		out.append(FloorPlan.footprint(f["c"], f["h"], f["a"]))
	return out


## A transform in the venue's frame, in the set's (where the trolleys and the items are); and back.
func _venue_to_set(at: Transform3D) -> Transform3D:
	if studio.venue == null or studio.studio_set == null:
		return at
	return studio.studio_set.transform.affine_inverse() * studio.venue.transform * at


func _set_to_venue(at: Transform3D) -> Transform3D:
	if studio.venue == null or studio.studio_set == null:
		return at
	return studio.venue.transform.affine_inverse() * studio.studio_set.transform * at


## Joined someone: their room arrives on its own. Back on our own, or hosting: our own room, and
## as host, everyone is told what it is.
func _on_role_changed() -> void:
	if not is_instance_valid(studio):
		return
	# This player's keys are `keys:P` for whoever they are now.
	if studio.jacks != null:
		studio.jacks.show_all()
	if Session.role == Session.Role.GUEST:
		return
	if studio._showing_hosts_room:
		_put_back_own_room()
	# This player's made items, set aside while a guest (Session.join): theirs again.
	studio.sampler_host._restore_made(true)
	studio.room_rows._publish_room()


func _put_back_own_room() -> void:
	studio._showing_hosts_room = false
	studio._predictions.clear()
	if Session.layout == null:
		return
	studio.room_deltas.enter_own(Session.layout)
	for id in studio.tablets.keys():
		studio.tablet_host._take_down_tablet(id)
	for id in studio.track_racks.keys():
		studio.tablet_host._take_down_track_rack(id)
	if studio.mount != null:
		studio.mount.share_studio({})
	if studio.floor_plan != null:
		studio._applying_room = true
		for piece in studio.floor_plan.pieces:
			var t := piece as Trolley
			if t == null or not is_instance_valid(t) or not studio._authored_floor.has(t.piece_id):
				continue
			# Each venue stands these where it does: put back for this one below; the niche is in
			# the venue's wall.
			if studio.live_pieces.has(t.piece_id) or t.built_in:
				continue
			var left: Variant = studio.room_deltas.saved(t.piece_id, Session.layout)
			var own: Transform3D = left if left != null else studio._authored_floor[t.piece_id]
			t.place(Vector2(own.origin.x, own.origin.z), own.basis.get_euler().y)
		RoomSync.wheel_in(studio)
		studio.furniture_host._carry_all_live()
		studio._applying_room = false
		_fit_room_to_session()
	var own := Session.layout.venue if Venue.is_known(Session.layout.venue) else Venue.IDS[0]
	var own_variant := Venue.known_variant(own, Session.layout.venue_variant)
	if studio.medium != Presentation.Medium.AR and studio.venue != null \
			and (studio.venue.venue_id() != own or studio.venue.variant != own_variant):
		set_venue(own, false, own_variant)
	# The host's made room goes with the host's room: it was held for this guest in memory only.
	MadeRooms.drop_adopted()
	if studio.floor_plan != null:
		studio.tablet_host._restore_tablets()
		studio.tablet_host._restore_track_racks()


## The carcass fills from the plinth up to the bay's lower edge and the cheeks run past its top,
## whatever height the session has made the bay.
func _fit_stand_to_bay() -> void:
	if studio._patch_cabinet == null:
		return
	var height := studio.patchbay.panel_height() if studio.patchbay != null else 0.0
	if height <= 0.0:
		height = 0.8
	var floor_top := Caster.HEIGHT + 0.03
	var under := maxf(Studio.PATCH_BAY_TOP - height - 0.004, floor_top + 0.01)
	(studio._patch_cabinet.mesh as BoxMesh).size = Vector3(PatchbaySurface.PANEL_WIDTH,
			under - floor_top, PATCH_CABINET_DEPTH)
	studio._patch_cabinet.position = Vector3(0, (under + floor_top) * 0.5,
			Studio.PATCH_BAY_FRONT - PatchbaySurface.PANEL_DEPTH - PATCH_CABINET_DEPTH * 0.5 + 0.01)
	GearTrim.edges(studio._patch_cabinet)
	var top := Studio.PATCH_BAY_TOP + 0.03
	for i in studio._patch_cheeks.size():
		var side := -1.0 if i == 0 else 1.0
		(studio._patch_cheeks[i].mesh as BoxMesh).size = Vector3(0.035, top - floor_top, 0.16)
		studio._patch_cheeks[i].position = Vector3(side * (PatchbaySurface.PANEL_WIDTH * 0.5 + 0.0175),
				(top + floor_top) * 0.5, Studio.PATCH_BAY_FRONT - 0.06)


func _on_timeline_size_chosen(width_scale: float, lane_height: float) -> void:
	if Session.layout != null:
		Session.layout.timeline_width_scale = width_scale
		Session.layout.timeline_lane_height = lane_height
		Session.layout.save()


func _on_timeline_shelf_chosen(on: bool) -> void:
	if Session.layout != null:
		Session.layout.timeline_shelves = on
		Session.layout.save()


func _room_bounds() -> Rect2:
	return Rect2(-studio.room_width * 0.5 + 0.05, Studio.ROOM_FRONT + 0.05, studio.room_width - 0.10, Studio.ROOM_DEPTH - 0.05)


## Move the room round the desk. See SessionLayout for the rule.
##
## A piece this participant has put somewhere themselves stays there unless the desk has grown
## into it, and then it is pushed just clear, the way a person would shove it -- not sent back to
## a default they had already rejected. A piece still where the room put it goes where the room
## would put it now.
func _fit_room_to_session() -> void:
	if studio.floor_plan == null or studio.console == null:
		return
	var desk := _desk_footprint()
	if desk.is_empty():
		return
	var fit := SessionLayout.fit((desk[0]["h"] as Vector2).x)
	var width: float = fit["room_width"]
	if not is_equal_approx(width, studio.room_width):
		studio.room_width = width
		studio.floor_plan.bounds = _room_bounds()
		if studio.venue != null:
			set_venue(studio.venue.venue_id(), false, studio.venue.variant)
		studio.venue_look._walk_where_the_venue_lets()
	# A guest's room is fitted by the host, who says where everything went.
	if studio._showing_hosts_room:
		studio.room_rows.apply_room(Session.room)
		return
	studio._fitting = true
	for piece in studio.floor_plan.pieces:
		var t := piece as Trolley
		if t == null or not is_instance_valid(t):
			continue
		var id := String(t.piece_id)
		var want: Variant = null
		if fit.has(id):
			want = [fit[id][0], deg_to_rad(fit[id][1])]
		elif id == "eq_wall":
			var at: Transform3D = ControlRoom.spot(&"eq_wall", studio.room_width)
			want = [Vector2(at.origin.x, at.origin.z), ControlRoom.heading(at)]
		elif t.built_in:
			continue
		elif id.begins_with("lamp_") and studio._authored_floor.has(t.piece_id):
			var home: Transform3D = studio._authored_floor[t.piece_id]
			want = [SessionLayout.widen(Vector2(home.origin.x, home.origin.z), studio.room_width),
					home.basis.get_euler().y]
		var saved := studio.room_deltas.saved(t.piece_id, Session.layout) != null
		var here := Vector2(t.position.x, t.position.z)
		if want != null and not saved:
			if not (want[0] as Vector2).is_equal_approx(here) or not studio.floor_plan.is_clear(t, here, t.rotation.y):
				t.place(want[0], want[1])
		elif not studio.floor_plan.is_clear(t, here, t.rotation.y):
			t.place(here, t.rotation.y)
	studio._fitting = false
	studio._looms_dirty = true
	studio.room_rows._publish_room()


## The console does not roll. It is the desk the room is arranged around and the one thing in
## it the mix position is measured from, so it is a fixture: solid, and in the way.
##
## Measured from its home, not its node, because a summoned desk is at the mix position and
## the place it will come back to still has to be kept clear.
func _desk_footprint() -> Array:
	if studio.console == null or studio.mount == null or studio.mount.mode_of(&"console") != Presentation.Mode.STUDIO:
		return []
	var home := studio.focus.home_of(&"console") if studio.focus != null and studio.focus.holds(&"console") \
			else studio.console.transform
	var box := _desk_box()
	if box.size.x <= 0.0:
		return []
	var flat := home * box
	# Down to the floor and out to the toe of the carcass: the panel is what is measured, and
	# the desk under it is what a trolley actually runs into.
	flat = flat.merge(AABB(Vector3(flat.position.x, 0.0, flat.position.z), Vector3(flat.size.x, 0.01, 0.0)))
	return [FloorPlan.footprint_of_box(flat)]


func _desk_box() -> AABB:
	var now := Time.get_ticks_msec()
	if now - _desk_box_at >= Studio.DESK_BOX_FOR_MSEC:
		_desk_box_cache = studio.console.content_aabb()
		_desk_box_at = now
	return _desk_box_cache


func _forget_desk_box() -> void:
	_desk_box_at = -Studio.DESK_BOX_FOR_MSEC


static func in_roulette_room_venue(v: Venue) -> bool:
	return v != null and v.venue_id() == Venue.ROULETTE_ID
