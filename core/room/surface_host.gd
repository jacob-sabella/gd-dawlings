class_name SurfaceHost
extends RefCounted

## Where surfaces hang: the three anchors, the surfaces built on them, the fingertips and chord hand lent to them, the lamp
## stands and the looms. Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the studio, which
## delegates the calls other code makes.

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## The trolley a surface rides on, told how to move that surface's HOME.
##
## Not simply "move the node". A surface on a trolley may be somewhere else entirely when its
## stand is pushed: summoned to the mix position by focus, or sitting on a monitor in SCREEN
## mode. In both cases the stand still moves, and the surface must come back to where the stand
## now is -- so what rides is the surface's studio placement, and the node only moves with it
## when the node is actually standing on the trolley.
## The clip editor, beside the timeline, opened by it: a double click on an item or its EDIT CLIP
## key opens the item here, or retargets the editor to it if it is open on another.
func _build_clip_editor() -> void:
	studio.clip_editor = ClipEditorSurface.new()
	studio.clip_editor.name = "ClipEditor"
	var yaw := deg_to_rad(Studio.CLIP_EDITOR_YAW)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * Studio.CLIP_EDITOR_SCALE)
	var left := Vector3(Studio.CLIP_EDITOR_LEFT.x, Studio.CLIP_EDITOR_Y, Studio.CLIP_EDITOR_LEFT.y)
	var at := Transform3D(basis, left - basis * Vector3(-ClipEditorSurface.WIDE * 0.5, 0, 0))
	studio.clip_editor.transform = at
	# Held by an arm from the stand's right-hand leg, which stands just behind it.
	studio.clip_editor.arm_to = at.affine_inverse() * Vector3(Studio.TIMELINE_LEG_X, Studio.CLIP_EDITOR_Y + 0.1, Studio.TIMELINE_STAND_Z)
	studio.studio_set.add_child(studio.clip_editor)
	studio.mount.register(studio.clip_editor)
	studio.timeline.edit_asked.connect(studio.clip_editor.open)


func _ride(piece: Trolley, surface: Surface) -> void:
	var id := surface.surface_id
	var standing := func() -> bool:
		return studio.mount.mode_of(id) == Presentation.Mode.STUDIO and surface.get_parent() == studio.studio_set
	piece.riders.append({
		"get": func() -> Transform3D:
			if studio.focus != null and studio.focus.holds(id):
				return studio.focus.home_of(id)
			if standing.call():
				return surface.transform
			return studio.mount.studio_home(id),
		"set": func(xform: Transform3D, settled_now: bool) -> void:
			if studio.focus != null and studio.focus.holds(id):
				studio.focus.rehome(id, xform)
			elif standing.call():
				surface.transform = xform
			# Nothing saved: a seated surface's place is its stand's, and the stand saves
			# itself. See SurfaceMount.seats.
			pass,
	})
	var offset: Transform3D = studio._authored_floor[piece.piece_id].affine_inverse() * studio.mount.authored_of(id)
	studio._seated_on[id] = [piece, offset]
	studio.mount.seat(id, func() -> Transform3D: return piece.transform * offset)


## A seated surface put down by its own handle: roll its stand to where that puts it.
func _reseat(id: StringName, put: Transform3D) -> void:
	if not studio._seated_on.has(id):
		return
	var piece: Trolley = studio._seated_on[id][0]
	if piece.built_in:
		return
	var under: Transform3D = put * (studio._seated_on[id][1] as Transform3D).affine_inverse()
	var ahead := under.basis.z
	piece.place(Vector2(under.origin.x, under.origin.z), atan2(ahead.x, ahead.z))


func _build_anchors() -> void:
	# The head and the hands differ by medium; everything downstream of them does not. That is
	# the point of putting screen_stage on whichever camera exists rather than on the desktop
	# one: a surface in SCREEN mode is a panel in front of your face whether your face is behind
	# a monitor or inside a headset.
	var head: Node3D
	if studio.medium == Presentation.Medium.SCREEN:
		studio.camera = Camera3D.new()
		studio.camera.fov = Studio.ROOM_FOV
		# Everything but your own ghost, which only mirrors draw. See core/venues/mirror.gd.
		studio.camera.cull_mask = Mirror.MAIN_VIEW_MASK

		studio.camera.near = 0.02
		studio.add_child(studio.camera)
		head = studio.camera

		var mouse := MouseInteractor.new()
		mouse.camera = studio.camera
		mouse.name = "MouseHand"
		studio.add_child(mouse)
		mouse.bare_jack.connect(studio.patch_host._on_bare_jack)
	else:
		studio.rig = XRRig.new()
		studio.rig.name = "XRRig"
		studio.rig.simulated = studio.xr_bootstrap != null and studio.xr_bootstrap.simulated
		studio.add_child(studio.rig)
		head = studio.rig.head
		studio.rig.escape_requested.connect(studio._on_escape)
		studio.rig.travelled.connect(func(_home: bool) -> void:
			if studio.body != null:
				studio.body.recentre())
		# A bare hand pinched at the floor goes there (Teleport).
		studio.teleport = Teleport.new()
		studio.teleport.name = "Teleport"
		studio.teleport.rig = studio.rig
		# The floor plan's frame, which the walker's footprints and floor are measured in.
		studio.teleport.frame = func() -> Transform3D:
			return studio.studio_set.global_transform if studio.studio_set != null and studio.studio_set.is_inside_tree() else Transform3D.IDENTITY
		studio.teleport.fits = func(p: Vector2) -> bool:
			var fit := studio.station_host._station_fits()
			return fit.is_valid() and bool(fit.call(p))
		studio.teleport.ground = func(p: Vector2) -> float:
			return Walker.ground_of(studio.venue.solids(), p) if studio.venue != null else 0.0
		studio.teleport.refusal = studio.station_host.travel_refusal
		studio.teleport.went.connect(func(_to: Vector3) -> void:
			studio.station_host._put_away_beside()
			studio.station = &"")
		studio.add_child(studio.teleport)
		# A VR player's play space is centred on the mix position, in front of the desk, where a
		# desktop's body stands: not at the room's origin, which is inside the console's carcass.
		# From here the desk is at arm's length and the station board is in view, ahead and to
		# the left. Passthrough keeps its own: its floor is a real one, put where the marks say.
		if studio.medium == Presentation.Medium.VR:
			studio.rig.settle(Transform3D(Basis.IDENTITY, Vector3(0, 0, Studio.MIX_POSITION_Z)))

	studio.screen_stage = Node3D.new()
	studio.screen_stage.name = "ScreenStage"
	studio.screen_stage.position = Vector3(0, 0, -0.75)
	head.add_child(studio.screen_stage)
	if not studio.get_tree().node_added.is_connected(studio._keep_out_of_mirrors):
		studio.get_tree().node_added.connect(studio._keep_out_of_mirrors)

	studio.room_anchor = RoomAnchor.new()
	studio.room_anchor.name = "RoomAnchor"
	studio.add_child(studio.room_anchor)

	studio.studio_set = Node3D.new()
	studio.studio_set.name = "StudioSet"
	studio.add_child(studio.studio_set)

	# The frame a person's own gear sits in, as distinct from the room's. Parented to the studio
	# rather than the head: it follows the head itself, with a deadzone, which is the whole
	# reason it exists. See body_frame.gd.
	studio.body = BodyFrame.new()
	studio.body.name = "BodyFrame"
	studio.add_child(studio.body)
	if studio.medium == Presentation.Medium.SCREEN:
		# On a monitor the camera is NOT a head, and pretending it is makes people ill. The
		# orbit camera swings on a two-metre boom; letting the body take its position meant a
		# mouse drag carried the console bodily around the room on the end of that boom,
		# through the furniture, while the mixer stood still. A drag on a screen is a LOOK.
		#
		# So the body is a mix position instead: a fixed standing spot in the room at eye
		# height, facing the way the room faces. Summoned gear lands in front of it and stays
		# there, and the camera is free to fly around and look at it from anywhere. The gear
		# is still placed from a body -- it is just not a body that chases the lens.
		# In FRONT of the desk, not on top of it. The first version stood the mixer at the room
		# origin, which is where the console's own carcass is, so every summoned surface landed
		# inside the furniture and the render came back with a table sawn through the middle of
		# a mixing desk. A mix position is a place you could actually stand.
		studio.body.position = Vector3(0, studio.ergonomics.eye_height, Studio.MIX_POSITION_Z)
	else:
		# In AR and VR it really is a head, and following it is the whole point. See
		# body_frame.gd for the deadzone that keeps a glance from dragging the room.
		studio.body.head = head

	# What a surface may assume it will be seen through. On a monitor that is the seated lens;
	# in a headset it is the visor, which is far wider, and sizing gear to a 54-degree crop
	# there would stack a patchbay into four units that would have fitted in one.
	studio.ergonomics.seated_fov = Studio.SEATED_FOV if studio.medium == Presentation.Medium.SCREEN else Studio.HEADSET_FOV
	studio._follow_viewport_shape()
	var view := studio.get_viewport()
	if view != null and not view.size_changed.is_connected(studio._follow_viewport_shape):
		view.size_changed.connect(studio._follow_viewport_shape)

	# A light that travels with the person. Summoned gear leaves the room's lamps behind -- the
	# first rack pulled to arm's length arrived in total darkness, which is both useless and a
	# fair description of what body-relative content is: not in the room any more. A headlamp
	# would flatten everything it hit, so this sits up and to the working side, which is where
	# the lamp on a real desk goes and for the same reason. A little ahead of the head rather
	# than over the shoulder, as a desk lamp is: the light is for what is in front, and the
	# full-height rack, framed whole, stands nearly two metres off.
	var work_light := OmniLight3D.new()
	work_light.name = "WorkLight"
	work_light.position = Vector3(0.42 * signf(studio.ergonomics.handedness), 0.30, -0.08)
	work_light.light_color = Color(1.0, 0.95, 0.88)
	work_light.light_energy = 1.0
	work_light.omni_range = 2.4
	work_light.shadow_enabled = false
	studio.body.add_child(work_light)

	studio.mount = SurfaceMount.new()
	studio.mount.name = "SurfaceMount"
	studio.mount.screen_stage = studio.screen_stage
	studio.mount.room_anchor = studio.room_anchor
	studio.mount.studio_set = studio.studio_set
	studio.add_child(studio.mount)

	if studio.rig != null:
		studio.rig.room_anchor = studio.room_anchor

	# A participant with no physical room to mark adopts the session frame outright and stands in
	# the same layout as everyone else. 1.2m is the span the default layout assumes between the
	# two floor marks. An AR participant does NOT get this: they have a real room, and handing
	# them a guessed frame would put the console somewhere plausible and wrong, which is harder
	# to notice than no console at all.
	if studio.medium != Presentation.Medium.AR:
		studio.room_anchor.adopt_virtual_frame(1.2)

	# Everyone else. Built for a solo run too, empty: a session can be hosted from the panel at
	# any moment, and the people who then walk in need somewhere to stand.
	studio.presence = Presence.new()
	studio.presence.name = "Presence"
	studio.presence.head_node = head
	studio.presence.frame = studio.room_anchor
	studio.add_child(studio.presence)
	_lend_fingertips()
	_lend_chord_hand()


## This player's fingertips as notes (FingertipNotes, docs/spatial_loop.md slice 8), one per hand:
## each of the headset's, turned on by an open palm up; on a desktop the mouse's, whose fingers
## are J K L ; on a KeyCatcher of their own (`fingertip_keys`), on while it has the keyboard (T).
func _lend_fingertips() -> void:
	if studio.camera != null:
		var mouse := studio.get_node_or_null("MouseHand") as MouseInteractor
		studio.fingertip_keys = KeyCatcher.new()
		studio.fingertip_keys.name = "FingertipKeys"
		studio.fingertip_keys.layout = KeyCatcher.FINGERS
		studio.fingertip_keys.base = 0
		studio.fingertip_keys.octave_keys = false
		studio.fingertip_keys.velocity = FingertipNotes.KEY_VELOCITY
		studio.fingertip_keys.click_releases = true
		studio.add_child(studio.fingertip_keys)
		if mouse != null:
			mouse.finger_source = studio.fingertip_keys
			_add_fingertips(mouse, null)
	if studio.rig != null:
		for controller in studio.rig.interactors:
			_add_fingertips(studio.rig.interactors[controller], studio.rig.skeletons.get(controller) as HandSkeleton)


func _add_fingertips(hand: Interactor, skeleton: HandSkeleton) -> void:
	var notes := FingertipNotes.new()
	notes.name = "Fingertips" + String(hand.get_parent().name if hand.get_parent() != studio else hand.name)
	notes.hand = hand
	notes.skeleton = skeleton
	if hand is MouseInteractor:
		notes.catcher = studio.fingertip_keys
	studio.add_child(notes)
	studio.fingertips.append(notes)


## This player's chord hand (ChordHand): in a headset the rig's left hand, or its right for a
## left-handed player (Ergonomics.handedness); on a desktop the chord layer, over the mouse's view
## and the fingertips' keys.
func _lend_chord_hand() -> void:
	studio.chord_hand = ChordHand.new()
	if studio.camera != null:
		studio.chord_hand.mouse = studio.get_node_or_null("MouseHand") as MouseInteractor
		studio.chord_hand.fingertip_keys = studio.fingertip_keys
	if studio.rig != null:
		var controller: XRController3D = studio.rig.left if studio.ergonomics.handedness >= 0 else studio.rig.right
		if controller != null:
			studio.chord_hand.hand = studio.rig.interactors.get(controller) as XRInteractor
			studio.chord_hand.gestures = studio.rig.gestures.get(controller) as HandGestures
			studio.chord_hand.head = studio.rig.head
	studio.add_child(studio.chord_hand)


## C on a desktop: the chord layer on, or off (ChordHand.set_layer). On, 1 to 7 pick the key's
## chords in whichever keys have the keyboard, and with none, the fingertips' take it. Said the
## first time.
func toggle_chords() -> void:
	if studio.chord_hand == null or studio.camera == null:
		return
	studio.chord_hand.set_layer(not studio.chord_hand.layer)
	if studio.chord_hand.layer and not studio._told_chords:
		studio._told_chords = true
		Session.notice.emit("Chords: 1 to 7 play the key's I to vii° on the fingertips (J K L ;); Shift adds the seventh, 0 the song's own. C or Esc ends it.")


## T on a desktop: the fingertips' keys on, or back to the studio. Said the first time.
func toggle_fingertips() -> void:
	if studio.fingertip_keys == null:
		return
	var on := not studio.fingertip_keys.is_active()
	studio.fingertip_keys.set_active(on)
	if on and not studio._told_fingertips:
		studio._told_fingertips = true
		Session.notice.emit("Fingertips: J K L ; play the chord's root, third, fifth and top, held as long as the key. T, Esc or a click gives the keys back.")


func _build_surfaces() -> void:
	# These transforms are the DEFAULT LAYOUT, used until a participant moves something and their
	# LayoutProfile starts overriding them. Heights are real: the desk surface at 0.74m, the
	# patchbay at eye level over it, the rack within arm's reach to the left.
	studio.console = ConsoleSurface.new()
	studio.console.name = "Console"
	studio.console.position = Vector3(0, 0.74, 0.1)
	studio.studio_set.add_child(studio.console)
	studio.mount.register(studio.console)
	if studio.medium != Presentation.Medium.AR:
		studio.station_host._build_desk_wing()

	# On its stand, as authored: the stand's own placement times where the bay sits on it. The
	# stand may since have been wheeled somewhere else; riding it (below) takes care of that.
	studio.patchbay = PatchbaySurface.new()
	studio.patchbay.name = "Patchbay"
	StageLink.wire_bay(studio.patchbay)
	studio.patchbay.transform = (ControlRoom.spot(&"patch_stand", studio.room_width) as Transform3D) * Transform3D(Basis.IDENTITY, Vector3(0, Studio.PATCH_BAY_TOP, Studio.PATCH_BAY_FRONT))
	studio.studio_set.add_child(studio.patchbay)
	studio.mount.register(studio.patchbay)

	studio.rack = RackSurface.new()
	studio.rack.name = "Rack"
	studio.rack.position = Vector3(-1.18, 0.30, -0.42)
	studio.rack.rotation_degrees = Vector3(0, 38, 0)
	studio.studio_set.add_child(studio.rack)
	studio.mount.register(studio.rack)

	# Hung on the back wall in the virtual set, which is where it goes for anyone who has
	# chosen to see it as an object. Its default mode is SCREEN in every medium -- a
	# forty-minute song is not furniture -- so most of the time this placement is unused, and
	# it is written anyway so that choosing ROOM does not drop it at the origin.
	studio.timeline = TimelineSurface.new()
	studio.timeline.name = "Timeline"
	studio.timeline.position = Vector3(0, Studio.TIMELINE_Y, Studio.TIMELINE_Z)
	studio.timeline.scale = Vector3.ONE * Studio.TIMELINE_SCALE
	# Shelves or flat lanes, as this person last chose.
	studio.timeline.shelf = Session.layout != null and Session.layout.timeline_shelves
	studio.timeline.shelf_chosen.connect(studio._on_timeline_shelf_chosen)
	if Session.layout != null:
		studio.timeline.set_size(Session.layout.timeline_width_scale, Session.layout.timeline_lane_height)
	studio.timeline.size_chosen.connect(studio._on_timeline_size_chosen)
	studio.studio_set.add_child(studio.timeline)
	studio.mount.register(studio.timeline)
	# A write bead pulled out shows its lane on the timeline, so the pass is seen to land there.
	WriteBead.on_pull = studio._show_written_lane
	_build_clip_editor()

	studio.deck = TapeDeck.new()
	studio.deck.name = "TapeDeck"
	studio.deck.position = Vector3(0.80, 1.02, -0.20)
	studio.deck.rotation_degrees = Vector3(-20, -32, 0)
	studio.studio_set.add_child(studio.deck)
	studio.mount.register(studio.deck)

	studio.focus = FocusRig.new()
	studio.focus.name = "FocusRig"
	studio.focus.body = studio.body
	studio.focus.ergonomics = studio.ergonomics
	studio.focus.surfaces = [studio.console, studio.patchbay, studio.rack, studio.deck, studio.timeline]
	# The stage table, on its trolley beside the mix position (slice 18). None in AR, which has
	# no furniture to stand it on yet.
	if studio.stage_trolley != null:
		studio.stage = StageTable.new()
		studio.stage.name = "StageTable"
		StageLink.wire(studio.stage)
		studio.stage.transform = studio.stage_trolley.transform * Transform3D(Basis.IDENTITY, Vector3(0, Studio.STAGE_TOP, 0))
		studio.studio_set.add_child(studio.stage)
		studio.mount.register(studio.stage)
		studio.stage.ropes_changed.connect(studio._publish_room_soon)
		studio.focus.surfaces.append(studio.stage)
	# The spectra the EQ wall shows: measured here on the built-in engine, sent on to guests, or a
	# guest's host's (slice 36). And the wall, on its trolley at the side wall; none in AR.
	studio.spectra = Spectra.new()
	studio.spectra.name = "Spectra"
	studio.add_child(studio.spectra)
	if studio.eq_wall_trolley != null:
		studio.eq_wall = EqWall.new()
		studio.eq_wall.name = "EqWall"
		studio.eq_wall.spectra = studio.spectra.latest
		studio.eq_wall.reason = studio.spectra.reason
		studio.eq_wall.reference = func() -> float: return studio.spectra.reference
		studio.eq_wall.motion = func() -> float: return studio.ergonomics.motion_scale
		studio.eq_wall.transform = studio._authored_floor[&"eq_wall"]
		studio.studio_set.add_child(studio.eq_wall)
		studio.mount.register(studio.eq_wall)
		studio.focus.surfaces.append(studio.eq_wall)
	# LEVELS (slice 66), on its trolley at the front left; none in AR.
	if studio.levels_niche != null:
		studio.levels = LevelsWall.new()
		studio.levels.name = "Levels"
		studio.levels.motion = func() -> float: return studio.ergonomics.motion_scale
		studio.levels.transform = studio._authored_floor[&"levels"]
		studio.studio_set.add_child(studio.levels)
		studio.mount.register(studio.levels)
		studio.focus.surfaces.append(studio.levels)
	# The TV (docs/sampling_station.md), on its bracket right of the timeline; none in AR.
	if studio.tv_mount != null:
		studio.tv = TvSurface.new()
		studio.tv.name = "Tv"
		studio.tv.transform = studio._authored_floor[&"tv"]
		studio.tv.find_asked.connect(studio.furniture_host.find_on_tv)
		studio.tv.song_position = func() -> float: return studio.hit_recorder.stamp() if studio.hit_recorder != null else 0.0
		studio.tv.pad_struck.connect(studio.furniture_host._on_pad_struck)
		studio.tv.changed.connect(studio.room_rows._on_tv_changed)
		studio.tv.asked.connect(func(video: String, playing: bool, at: float) -> void:
			Session.ask_room(&"tv", [video, playing, at]))
		studio.tv.pads_changed.connect(studio.room_rows._on_pads_changed)
		studio.tv.pads_said.connect(func(words: String) -> void: Session.notice.emit(words))
		studio.tv.pads_rejoined.connect(func() -> void:
			studio._pads_loaded = ""
			if not studio._pads_followed.is_empty():
				studio.room_rows._follow_pads_row(studio._pads_followed))
		studio.tv.searched.connect(studio.furniture_host._on_tv_searched)
		studio.studio_set.add_child(studio.tv)
		studio.mount.register(studio.tv)
		studio.focus.surfaces.append(studio.tv)
	# The modular wall, over the synth zone's keyboard stand (slice 51); none in AR.
	if studio.medium != Presentation.Medium.AR:
		studio._build_rack()
		studio.focus.surfaces.append(studio.rack_wall)
	studio.focus.show_halo = studio.medium != Presentation.Medium.SCREEN
	studio.focus.visits = studio.medium == Presentation.Medium.SCREEN
	# Re-seat once the focused surface has been PLACED, which is when it finally knows both its
	# own size and where it ended up. Without this the camera is always aimed using the layout
	# the desk had before it was summoned, and a paged single-tier console is a very different
	# object from the flat 48-track plank it was a frame earlier.
	#
	# Placement, not rebuilding. Both this and the rig itself used to listen to `rebuilt`, and
	# which of them ran first was decided by connection order; this one won, so the camera sat
	# down facing where the gear had been a moment before the rig moved it, and nothing fired
	# again to correct it. `--focus rack` came back as a photograph of the floor.
	studio.focus.placed.connect(studio.station_host._sit_down)
	# A release walks nobody anywhere on its own: what releases to go home (Escape, F off the end,
	# G, BACK) sits down itself, and one that happens to something else -- a tablet closed, a rack
	# folded, a guest handing focus back -- leaves the player where they are (2026-10-30, "i dont
	# like how clicking things moves me to other things in almost all scenarios"). The monitor's
	# panels, put away while gear is visited, come back all the same.
	studio.focus.focus_changed.connect(func(id: StringName) -> void:
		if id == &"" and studio.focus.visits:
			studio.station_host._stand_down_screen(false))
	studio.focus.room = studio.studio_set
	studio.focus.move = studio._glide
	studio.add_child(studio.focus)
	if studio.mount != null:
		studio.mount.held = studio.focus.holds
	studio._stand_the_modular()

	# What rides on what. After the rig, because a surface that is summoned rides by its home,
	# and the rig is what holds that.
	if studio.floor_plan != null:
		studio.mount.reseat = _reseat
		studio.mount.studio_placed = studio.room_rows._on_studio_placed
		_ride(studio.rack_trolley, studio.rack)
		_ride(studio.deck_trolley, studio.deck)
		_ride(studio.timeline_stand, studio.timeline)
		_ride(studio.timeline_stand, studio.clip_editor)
		_ride(studio.patch_stand, studio.patchbay)
		if studio.stage != null:
			_ride(studio.stage_trolley, studio.stage)
		if studio.eq_wall != null:
			_ride(studio.eq_wall_trolley, studio.eq_wall)
		if studio.levels != null:
			_ride(studio.levels_niche, studio.levels)
		if studio.tv != null:
			_ride(studio.tv_mount, studio.tv)

	# After the gear, because a loom is measured off the transforms of the two things it joins.
	# Rebuilt with the bay, because the bay's width is the track count and the glands are spaced
	# across it: a session that gains tracks moves where its own looms land.
	studio.patchbay.rebuilt.connect(refresh_looms)
	refresh_looms()
	# The beads ride whatever cables there are, found every frame, so a cable rebuilt or freed
	# needs telling nobody.
	studio.signal_beads = SignalBeads.create()
	studio.add_child(studio.signal_beads)

	# The room is fitted to the desk every time the desk changes shape: a live session's tracks
	# arrive after the room is built, and a project that gains a bank gains a metre of console.
	studio.console.rebuilt.connect(studio._forget_desk_box)
	studio.console.rebuilt.connect(studio._fit_room_to_session)
	studio.patchbay.rebuilt.connect(studio._fit_stand_to_bay)
	studio._fit_room_to_session()

	if studio.floor_plan != null:
		studio.rack.tear_requested.connect(studio.tablet_host._on_tear_requested)
		studio.rack.track_tear_requested.connect(func(t: int, at: Vector3) -> void: studio.tablet_host._on_track_tear_requested(t, at, studio.rack))
		studio.tablet_host._restore_tablets()
		studio.tablet_host._restore_track_racks()
	Session.room_changed.connect(studio.room_rows._on_room_changed)
	# The tablets follow their tracks themselves; what is remembered and told follows them.
	DAW.tracks_renumbered.connect(_on_tracks_renumbered)
	Session.room_asked.connect(studio.room_rows._on_room_asked)
	Session.participant_left.connect(studio.signal_views._on_look_solo_player_left)
	DAW.project_replaced.connect(func() -> void:
		if not is_instance_valid(studio):
			return
		studio.look_solo.forget()
		studio._look_by = &""
		studio.guest_look_solos.clear())
	Session.role_changed.connect(studio._on_role_changed)
	Session.room_motion.connect(studio.room_rows._on_room_motion)
	studio.room_rows._publish_room()


## A renumbering is answered a frame late, once every tablet has followed its track.
##
## A named method rather than a lambda, because DAW is an autoload that outlives every studio:
## a bound method's connection goes when the studio is freed, and a lambda's does not, so a
## renumbering after a studio was gone ran its deferred body on whatever object later took the
## freed one's memory. A bound method is checked by instance id before it is called, deferred or
## not, and the deferred half also stands down when the studio has left the tree between the
## signal and the next idle frame.
func _on_tracks_renumbered(_map: Dictionary) -> void:
	if not is_instance_valid(studio):
		return
	_after_tracks_renumbered.call_deferred()


func _after_tracks_renumbered() -> void:
	if not is_instance_valid(studio):
		return
	if not studio.is_inside_tree():
		return
	studio.tablet_host._remember_tablets()
	studio.tablet_host._fold_orphaned_track_racks()
	studio._publish_room_soon()


## A stand under every practical.
##
## A tripod floor lamp rather than a pendant, and that is forced rather than chosen: this room
## has three walls and no ceiling, so there is nothing for a hanging fixture to hang from, and a
## stem disappearing into open sky above the wall line would be worse than no fixture at all.
##
## The shade is a cone open at the bottom with an emissive disc inside it, so the lamp reads as
## ON. Nothing about the geometry emits light -- the OmniLight does that, from the middle of the
## shade -- and that division is why the head sits where the light is rather than the other way
## round. Move a practical in the table and its stand follows; there is a test on the pairing,
## because the failure mode is an invisible light source, which is the thing this fixes.
func _build_lamp_stands() -> void:
	for spec in Studio.PRACTICALS:
		var at: Vector3 = spec[0]
		var tint: Color = spec[1]
		var number := Studio.PRACTICALS.find(spec) + 1
		var stand := studio._trolley("LampStand", StringName("lamp_%d" % number),
				Vector3(at.x, 0.0, at.z), 0.0)
		stand.add_to_group(&"lamp_stand")
		stand.rolls = false
		stand.follow = 15.0
		stand.footprint_half = Vector2(0.15, 0.15)
		# The light goes with its lamp. Reparented rather than built here, because an AR
		# participant gets the lights with no stands at all -- see _build_environment.
		if number - 1 < studio._lamps.size():
			studio._lamps[number - 1].reparent(stand, true)

		var base := MeshInstance3D.new()
		var base_mesh := CylinderMesh.new()
		base_mesh.top_radius = 0.085
		base_mesh.bottom_radius = 0.150
		base_mesh.height = 0.032
		base_mesh.radial_segments = 16
		base.mesh = base_mesh
		base.position = Vector3(0, 0.016, 0)
		base.material_override = Materials.furniture()
		stand.add_part(base)

		# Up to the middle of the shade, so the pole is hidden by the head rather than stopping
		# just short of it and leaving a gap you can see the wall through.
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.0145
		pole_mesh.bottom_radius = 0.0205
		# Rising out of the base rather than standing on the floor inside it, where its foot and
		# the base's underside were one plane.
		pole_mesh.height = at.y - 0.02
		pole_mesh.radial_segments = 10
		pole.mesh = pole_mesh
		pole.position = Vector3(0, (at.y + 0.02) * 0.5, 0)
		pole.material_override = Materials.brushed_metal()
		stand.add_part(pole)

		var shade := MeshInstance3D.new()
		shade.name = "Shade"
		var shade_mesh := CylinderMesh.new()
		shade_mesh.top_radius = Studio.LAMP_SHADE_RADIUS * 0.42
		shade_mesh.bottom_radius = Studio.LAMP_SHADE_RADIUS
		shade_mesh.height = Studio.LAMP_SHADE_HEIGHT
		shade_mesh.radial_segments = 20
		shade_mesh.cap_bottom = false
		shade.mesh = shade_mesh
		shade.position = Vector3(0, at.y, 0)
		shade.material_override = Materials.lamp_shade()
		stand.add_part(shade)

		# The glowing bit. Above the shade's lower rim so the cone shields it from straight on,
		# which is what stops a lamp pointing down reading as a bare bulb from across the room.
		var glow := MeshInstance3D.new()
		var glow_mesh := CylinderMesh.new()
		glow_mesh.top_radius = Studio.LAMP_SHADE_RADIUS * 0.80
		glow_mesh.bottom_radius = Studio.LAMP_SHADE_RADIUS * 0.80
		glow_mesh.height = 0.004
		glow_mesh.radial_segments = 20
		glow.mesh = glow_mesh
		glow.position = Vector3(0, at.y - Studio.LAMP_SHADE_HEIGHT * 0.28, 0)
		glow.material_override = Materials.led(tint, true)
		stand.add_part(glow, false)


# --- looms --------------------------------------------------------------------------------

## The permanent runs from each machine to the back of the patchbay. See hardware/gear_loom.gd
## for what they are claiming.
##
## Skipped for any machine not standing in the virtual set. A surface in SCREEN mode is a panel
## riding in front of someone's face, and a two-metre cable from a panel in the viewer's head
## down to the floor of a room they may not even be rendering is worse than no cable: it moves
## with them, so it reads as the room being dragged around rather than as a loose cable.
func refresh_looms() -> void:
	for loom in studio._looms:
		if is_instance_valid(loom):
			loom.queue_free()
	studio._looms.clear()
	if studio.medium == Presentation.Medium.AR or studio.studio_set == null or studio.patchbay == null:
		return
	if studio.patchbay.get_parent() != studio.studio_set:
		return
	# A bay with no jacks has no width, so every landing fraction resolves to the same point and
	# the three looms would stack into one. An empty session gets no looms.
	if studio.patchbay.loom_entry(-1.0).is_equal_approx(studio.patchbay.loom_entry(1.0)):
		return

	for run in Studio.LOOM_RUNS:
		var machine: Node3D = studio.get(run[0])
		if machine == null or machine.get_parent() != studio.studio_set:
			continue
		var from_at: Vector3 = machine.transform * (run[1] as Vector3)
		var from_dir: Vector3 = (machine.transform.basis * (run[2] as Vector3)).normalized()
		var entry: Vector3 = studio.patchbay.loom_entry(run[3])
		var to_at: Vector3 = studio.patchbay.transform * entry
		# Into the panel, which is the bay's own -Z however the bay is tilted. Negated because a
		# loom's axis is the direction it RUNS AWAY along, not the direction it points in.
		var to_dir: Vector3 = (studio.patchbay.transform.basis * Vector3.BACK).normalized()
		# A bay standing in its cabinet takes its looms in low, through the cheek on the end
		# that faces the desk, the way a floor-standing bay is wired: from there they go
		# straight to the floor and away behind the desk instead of round the carcass.
		if _stands_in_cabinet():
			var side := -(PatchbaySurface.PANEL_WIDTH * 0.5 + 0.035)
			var fraction: float = run[3]
			to_at = studio.patch_stand.transform * Vector3(side, Caster.HEIGHT + 0.14 + (fraction + 1.0) * 0.045,
					Studio.PATCH_BAY_FRONT - 0.06 + fraction * 0.035)
			to_dir = (studio.patch_stand.transform.basis * Vector3.LEFT).normalized()
		var via: Vector3 = run[4]
		# The floor point was written against where the authored layout stood the machine. A
		# machine that has been wheeled somewhere else takes its run of trunking with it.
		var stand := _stand_of(String(run[0]))
		if stand != null and studio._authored_floor.has(stand.piece_id):
			via = stand.transform * (studio._authored_floor[stand.piece_id] as Transform3D).affine_inverse() * via
		var loom := GearLoom.create(from_at, from_dir, to_at, to_dir, via, hash(run[0]))
		loom.on_floor = run[5]
		loom.level_source = Studio.loom_level(String(run[0]))
		loom.name = "Loom_%s" % run[0]
		studio.studio_set.add_child(loom)
		studio._looms.append(loom)


func _stands_in_cabinet() -> bool:
	return studio.patch_stand != null and studio._patch_cabinet != null and studio._seated_on.has(studio.patchbay.surface_id) \
			and (studio._patch_cabinet.mesh as BoxMesh).size.y > 0.2


func _stand_of(machine: String) -> Trolley:
	match machine:
		"rack": return studio.rack_trolley
		"deck": return studio.deck_trolley
	return null


## Looms follow furniture that is being pushed, but not every physics frame: a loom is a swept
## mesh, and rebuilding three of them sixty times a second for a rack moving two centimetres is
## the furniture costing more than the console.
func _refresh_looms_if_moved(delta: float) -> void:
	studio._loom_clock += delta
	if studio._looms_dirty and studio._loom_clock >= 0.05:
		studio._looms_dirty = false
		studio._loom_clock = 0.0
		refresh_looms()


# --- desktop camera -----------------------------------------------------------------------

## EDIT on the lyric board: in a headset, the typing pad by the singer's hand (LyricBoard.PAD_AT), its
## line added to the end of the lyrics untimed; at a desk, the session panel's LYRICS box, which has
## them all, or where it is when nothing opens it.
func edit_lyrics() -> void:
	if studio.lyric_board == null or not is_instance_valid(studio.lyric_board):
		return
	if studio.get_viewport() != null and studio.get_viewport().use_xr:
		var old := studio.lyric_board.get_node_or_null("TypingPad")
		if old != null:
			old.queue_free()
		var pad := TypingPad.ask(studio.lyric_board, "A line for the lyrics: OK adds it at the end, untimed", "",
				LyricBoard.PAD_AT)
		pad.answered.connect(func(words: String) -> void:
			if studio.lyric_board != null and is_instance_valid(studio.lyric_board):
				studio.lyric_board.add_line(words))
		return
	if studio.lyrics_edit_asked.get_connections().is_empty():
		Session.notice.emit("M opens the session panel: its LYRICS box has the song's lyrics.")
		return
	studio.lyrics_edit_asked.emit()
