class_name StationHost
extends RefCounted

## Sitting, walking to a seat or a station, the station board, the desk wing and the point-and-mark pad. Moved out of
## `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the calls other code makes.

## How fast going to a station covers the floor (m/s), at motion 1: a brisk walk, so the live
## room's far wall is a second and a half from the desk rather than a lurch.
const STATION_PACE := 4.0

## The stand's grip, round the board's foot and post.
var _board_grip: CollisionShape3D

## Where the table stands at home, on the floor under the middle of its board, and its turn: its
## reader's edge (+Z, the side the miniature is read from) toward the mix position.
## How far into the timeline's window an item it is brought to starts, of the window's span.
const SHOWN_IN := 0.1

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


func _sit_down() -> void:
	if studio.camera == null or studio.body == null or studio.medium != Presentation.Medium.SCREEN:
		return
	if studio.focus != null and studio.focus.visits:
		_walk_to_seat()
		return
	# Aimed at where focused gear GOES, not at where the focused surface currently is. Asking
	# the surface was the first version, and it reads its bounds a frame too early -- focus
	# moves the surface immediately but the rebuild that gives it its shape happens on the next
	# _process, so the camera was aimed using the previous layout's box and ended up on the
	# floor looking at a lamp. This point is a property of the body, which is already final.
	var eye := studio.body.global_position
	var drop := deg_to_rad(studio.ergonomics.gaze_down)
	var ahead := Vector3(0, -sin(drop), -cos(drop)) * studio.ergonomics.working_distance()
	var at: Vector3 = eye + studio.body.global_transform.basis * ahead
	# Aimed at the focused surface's own middle once it HAS one. Reading its bounds is only
	# safe after the rebuild -- focus moves a surface immediately but the rebuild that gives it
	# its shape happens on the next _process -- so this takes the measurement when it is real
	# and falls back to the body's working point when it is not.
	if studio.focus != null and studio.focus.is_focused():
		for surface in studio.focus.surfaces:
			if surface.surface_id == studio.focus.focused_id:
				var box := surface.content_aabb()
				if box.size.y > 0.01:
					# Aimed at where the surface is GOING, not where it currently is. Gear
					# glides to the mix position over a few hundred milliseconds, and the
					# camera is seated the instant placement is decided -- reading the live
					# transform aims it at a console still halfway across the room, and
					# nothing fires afterwards to correct it once the tween lands. This is
					# why `--focus rack` kept coming back as a photograph of the floor even
					# after the signal race behind it was fixed: two separate bugs with one
					# symptom, and fixing the first changed the render not at all.
					#
					# Dead centre of the box, not a quarter up it. The lift was there to
					# stop the camera staring into the desk's underside, and the underside
					# was really the carcass being counted as content, which it no longer is.
					var target := studio.body.global_transform * studio.focus.placement(surface, 0)
					at = target * box.get_center()
	var back := eye - at
	# Through frame() rather than by assigning the four orbit fields, which is what the version
	# before that did: those values are only read when something applies them, so setting them
	# and stopping leaves the camera exactly where it was. The render came back identical twice
	# and both times read as a placement bug rather than a call that never reached the camera.
	#
	# Negative pitch, because the offset is built with Basis(RIGHT, pitch), which sends +pitch
	# DOWN -- the eye is above the desk, so it wants the sign that lifts it.
	# A longer lens while you are working at something. The default 75-degree field is right
	# for walking around a room and wrong for standing over a desk: at half a metre it bows the
	# arc outward at the edges and spends most of the frame on everything that is not the desk.
	# Nobody photographs a console on a wide angle either, and for the same reason.
	studio.camera.fov = Studio.SEATED_FOV if studio.focus.is_focused() else Studio.ROOM_FOV
	studio.view_host.frame(at, back.length(), atan2(back.x, back.z),
			-atan2(back.y, Vector2(back.x, back.z).length()))


## Where the mix position stands when nothing is being visited.
func _home_seat() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, studio.ergonomics.eye_height, Studio.MIX_POSITION_Z))


## Visiting: walk the mix position over to the focused gear and look at it from there.
##
## The body goes, not just the lens, because the body is what carries the work light -- and
## because "where I am standing" is what release has to undo. A surface that is not standing in
## the room (a timeline on the monitor) has no seat; focusing it leaves you where you are.
func _walk_to_seat() -> void:
	var seat := _home_seat()
	var look_at := Vector3.ZERO
	var target: Surface = null
	if studio.focus.is_focused():
		for surface in studio.focus.surfaces:
			if surface.surface_id == studio.focus.focused_id:
				target = surface
	# A surface that is a station mounted in a zone (the modular wall, slice 51) is visited where its
	# station is played: where `seat_for` would stand a desk to fit it, the bricks table stands, and
	# the fifths wheel's board across the view.
	if target != null and target == studio.rack_wall and studio.venue != null and Stations.spot(studio.venue, Modular.STATION) != null:
		_walk_to_station(Modular.STATION)
		return
	# Anywhere in the set: a tablet stands on its own stand, a level further down.
	if target != null and studio.studio_set.is_ancestor_of(target):
		var box := target.content_aabb()
		if box.size.y > 0.01:
			seat = studio.focus.seat_for(target)
			# Inside the room and at a height a person's eyes can be at. A rack's bottom unit
			# asks for a seat on the floor; nobody mixes lying down.
			var bounds := studio.floor_plan.bounds if studio.floor_plan != null \
					else studio.venue_switch._room_bounds()
			seat.origin = Vector3(
					clampf(seat.origin.x, bounds.position.x + 0.2, bounds.end.x - 0.2),
					clampf(seat.origin.y, 0.95, 1.95),
					clampf(seat.origin.z, bounds.position.y + 0.2, bounds.end.y + 0.6))
			look_at = target.global_transform * box.get_center()
	elif target != null:
		return
	_stand_down_screen(target != null)
	if look_at == Vector3.ZERO:
		var drop := deg_to_rad(studio.ergonomics.gaze_down)
		look_at = seat * (Vector3(0, -sin(drop), -cos(drop)) * studio.ergonomics.working_distance())
	studio.camera.fov = Studio.SEATED_FOV if target != null else Studio.ROOM_FOV
	var back := seat.origin - look_at
	var to := [look_at, back.length(), atan2(back.x, back.z),
			-atan2(back.y, Vector2(back.x, back.z).length())]
	var seconds := 0.55 * clampf(studio.ergonomics.motion_scale, 0.0, 2.0)
	if seconds <= 0.01 or not studio.is_inside_tree():
		studio.body.transform = seat
		studio.view_host.frame(to[0], to[1], to[2], to[3])
		return
	# Both at once, on one curve. A body that arrived before its camera would leave the work
	# light lighting the gear from an empty spot for half a second; a camera that arrived first
	# would see the light swing in after it.
	if studio.walker != null and not studio.god_mode:
		studio._orbit_target = to[0]
		studio.walker.travel_to(seat.origin, look_at, seconds)
		if studio._walk != null and studio._walk.is_valid():
			studio._walk.kill()
		studio._walk = studio.create_tween()
		studio._walk.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		studio._walk.tween_property(studio.body, "transform", seat, seconds)
		return
	var body_from := studio.body.transform
	var cam_from := studio.camera.global_transform
	studio.view_host.frame(to[0], to[1], to[2], to[3])
	var cam_to := studio.camera.global_transform
	studio.camera.global_transform = cam_from
	if studio._walk != null and studio._walk.is_valid():
		studio._walk.kill()
	studio._walk = studio.create_tween()
	studio._walk.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	studio._walk.tween_method(func(t: float) -> void:
		studio.body.transform = body_from.interpolate_with(seat, t)
		studio.camera.global_transform = cam_from.interpolate_with(cam_to, t), 0.0, 1.0, seconds)


## The monitor's own panels step aside while you are over at a piece of gear.
##
## A surface on the screen stage hangs off the lens, so walking to the console carries the
## timeline with you and holds it a hand's width in front of the desk you walked over to see --
## the first honest visit render was a timeline with a console somewhere behind it. Summoning
## never showed this because it pulled the timeline into the arc with everything else.
##
## Disabled as well as hidden: a hidden ControlAffordance is still in the physics space, and
## a click aimed at a fader would land on the invisible clip lane in front of it.
func _stand_down_screen(away: bool) -> void:
	if studio.screen_stage == null:
		return
	studio.screen_stage.visible = not away
	studio.screen_stage.process_mode = Node.PROCESS_MODE_DISABLED if away \
			else Node.PROCESS_MODE_INHERIT


## Visit the gear, or have it brought. Visiting is the monitor's default; bringing is still
## the right answer for some work -- a patchbay you want flat in front of you -- and is how a
## headset works, so it is one key away rather than gone.
func _toggle_summoning() -> void:
	var was := studio.focus.focused_id
	studio.focus.release()
	studio.focus.visits = not studio.focus.visits
	if not studio.focus.visits:
		# Summoned gear lands in front of the mix position, so the mix position has to be back
		# where it stands before anything is summoned to it.
		_stand_down_screen(false)
		studio.body.transform = _home_seat()
	if was != &"":
		studio.focus.focus(was)
	_sit_down()


## The stations that stand here, in Stations' order: none in AR, where the room is a real one and
## nothing stands in it yet (slice 60), and none without a venue.
func station_ids() -> Array[StringName]:
	if studio.medium == Presentation.Medium.AR or studio.venue == null:
		return []
	return Stations.ids(studio.venue)


## I and Shift-I: go to the next station, or the one before, from the one last gone to, round
## and round. Unlike F's cycle there is no end to walk off: Esc is the way back to the desk, and
## the toast at each one says so. Answers the station gone to, or empty.
func cycle_stations(direction: int) -> StringName:
	var ids := station_ids()
	if ids.is_empty():
		Session.notice.emit("No instruments stand in this room.")
		return &""
	var at := ids.find(studio.station)
	var next := (0 if direction >= 0 else ids.size() - 1) if at < 0 \
			else posmod(at + (1 if direction >= 0 else -1), ids.size())
	return ids[next] if go_to_station(ids[next]) else &""


## Walk to station `id`: the walker eased to its seat (Stations.seat, SEAT in front of it on
## floor a person fits on), facing what is played, on the curve visiting gear uses
## (`_walk_to_seat`), longer for a longer way and scaled by Ergonomics.motion_scale (a cut at 0),
## and looking where it holds the station's controls in view (Stations.look_from). God mode is
## left first and focused gear let go, and the monitor's own panels step aside, as they do at
## gear, so the instrument is in full view. The body goes too, as it does to gear,
## so Esc walks back to the desk. A toast says its title and its desk line. In a headset the
## play space travels there instead (`_travel_to_station`). False where it does not stand here,
## or travel is refused.
func go_to_station(id: StringName) -> bool:
	var r := Stations.row(id)
	if r.is_empty() or not station_ids().has(id):
		Session.notice.emit("%s does not stand in this room." % r.get("title", String(id)))
		return false
	# A headset puts the rows beside a plaque away only once it goes: refused, they stay up and
	# say why, where the press was made.
	if studio.medium != Presentation.Medium.SCREEN or studio.camera == null:
		return _travel_to_station(id)
	_put_away_beside()
	if studio.god_mode:
		studio.player_host.set_god_mode(false)
	if studio.focus != null and studio.focus.is_focused():
		studio.focus.release()
	studio.station = id
	_walk_to_station(id)
	Session.notice.emit("%s, %s: %s  ·  Esc back to the desk" % [r["title"], Stations.where(r), r["desk"]])
	return true


## The walk (or the cut, at motion 0) to station `id`'s seat, the look framing it from there: for going
## to it, and for visiting a surface that is one (the modular wall, `_walk_to_seat`).
func _walk_to_station(id: StringName) -> void:
	var fits := studio.walker.fits if studio.walker != null else Callable()
	var frame_of := studio.venue.global_transform if studio.venue.is_inside_tree() else studio.venue.transform
	var seat: Transform3D = frame_of * (Stations.seat(studio.venue, id, fits) as Transform3D)
	_stand_down_screen(true)
	studio.camera.fov = Studio.ROOM_FOV
	var standing := studio.walker.standing_eye if studio.walker != null else studio.ergonomics.eye_height
	var eye := seat.origin + Vector3(0, standing, 0)
	# Framed from where you actually stand, which the room may have brought in short of SEAT:
	# the look tips to hold the station's top and foot, its controls' top first.
	var look: Vector3 = frame_of * (Stations.look_from(studio.venue, id, frame_of.affine_inverse() * eye, studio.camera.fov) as Vector3)
	var from := studio.walker.global_position if studio.walker != null else studio.camera.global_position
	var way := Vector2(eye.x - from.x, eye.z - from.z).length()
	var seconds := clampf(way / STATION_PACE, 0.55, 2.0) * clampf(studio.ergonomics.motion_scale, 0.0, 2.0)
	if not studio.is_inside_tree():
		seconds = 0.0
	var stand := Transform3D(seat.basis, eye)
	if studio.walker != null:
		studio.walker.eye_height = studio.walker.standing_eye
		studio._orbit_target = look
		studio.walker.travel_to(eye, look, seconds)
	else:
		var back := eye - look
		studio.view_host.frame(look, back.length(), atan2(back.x, back.z), -atan2(back.y, Vector2(back.x, back.z).length()))
	if studio.body != null and studio.focus != null and studio.focus.visits:
		if studio._walk != null and studio._walk.is_valid():
			studio._walk.kill()
		if seconds <= 0.01:
			studio.body.transform = stand
		else:
			studio._walk = studio.create_tween()
			studio._walk.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			studio._walk.tween_property(studio.body, "transform", stand, seconds)


## The board stands on a stand of its own on the floor, pushed about like the rest of the gear
## (`live_pieces`' "station_board"): taken by its post or its foot, the face's rows still being
## pressed. Behind the mix position, so a desk of any width grows clear of it; one it is pushed
## into is shoved off the desk as the room is fitted to it.
func _build_station_board() -> void:
	studio.station_board = StationBoard.new()
	studio.station_board.name = "StationBoard"
	studio.station_board.venue = studio.venue
	studio.station_board.transform = ControlRoom.spot(&"station_board", studio.room_width)
	studio.station_board.chosen.connect(_on_board_chosen)
	studio.studio_set.add_child(studio.station_board)
	var stand := studio.rack_host._authored("StationBoardStand", &"station_board")
	stand.follow = 11.0
	stand.rolls = false
	_board_grip = studio.furniture_host._grip(stand, Vector3.ONE * 0.1, Vector3.ZERO)
	studio.furniture_host._go_live(stand)
	_fit_board_stand()
	studio.furniture_host._carry_live(&"station_board")
	studio.venue_changed.connect(func(_id: StringName) -> void:
		_put_away_beside()
		studio.station_board.set_venue(studio.venue)
		_fit_board_stand())


## The stand's footprint and grip to the board as it now stands: the face is as tall as its rows,
## and the foot comes forward under its middle (StationBoard.footprint).
func _fit_board_stand() -> void:
	var stand: Trolley = studio.live_pieces.get(&"station_board")
	if stand == null or studio.station_board == null:
		return
	var z := studio.station_board._middle_z()
	stand.footprint_centre = Vector2(0, z)
	stand.footprint_half = StationBoard.FOOT
	var top := StationBoard.FACE_TOP - studio.station_board._height * 0.5 * cos(StationBoard.TILT)
	(_board_grip.shape as BoxShape3D).size = Vector3(StationBoard.FOOT.x * 2.0, maxf(top - 0.05, 0.1), 0.12)
	_board_grip.position = Vector3(0, maxf(top - 0.05, 0.1) * 0.5, z - 0.03)


func _on_board_chosen(id: StringName) -> void:
	go_to_station(id)


## A key on a station's plaque (StationBoard.PlaqueKey) was pressed: INSTRUMENTS puts the board's
## rows up beside that plaque, or away again; BACK goes home to the desk.
func plaque_key(id: StringName, kind: StringName, key: Node3D) -> void:
	if kind == StationBoard.PlaqueKey.BACK:
		go_home()
		return
	var plaque := key.get_parent() as Node3D
	var shown := studio._beside != null and is_instance_valid(studio._beside) and studio._beside.get_parent() == plaque
	_put_away_beside()
	if shown or plaque == null:
		return
	studio._beside = StationBoard.new()
	studio._beside.name = "Beside"
	studio._beside.compact = true
	studio._beside.venue = studio.venue
	studio._beside.chosen.connect(_on_board_chosen)
	# To the plaque's right, its top level with the plaque's, on the plaque's own lean.
	var plate := plaque.get_node_or_null("Plate") as MeshInstance3D
	var size: Vector3 = (plate.mesh as BoxMesh).size if plate != null else Vector3(Stations.PLAQUE_WIDTH, 0.2, 0.01)
	var top := plate.position.y + size.y * 0.5 if plate != null else 0.1
	studio._beside.position = Vector3(size.x * 0.5 + 0.02 + studio._beside.face_width() * 0.5, top, 0)
	plaque.add_child(studio._beside)
	Session.notice.emit("Every instrument, beside the %s's plaque: press one to go there, INSTRUMENTS again to put them away."
			% String(Stations.row(id).get("title", id)).to_lower())


## Take the rows beside a plaque away, if they are up: hidden and out of the physics space at
## once, freed at the frame's end, since the press that put them away may be one of their own.
func _put_away_beside() -> void:
	if studio._beside != null and is_instance_valid(studio._beside):
		studio._beside.visible = false
		studio._beside.process_mode = Node.PROCESS_MODE_DISABLED
		studio._beside.queue_free()
	studio._beside = null


## Why a headset may not travel now, or empty if it may. In a co-located room (`co_located`) a
## body has to stay where the others in the room see it: they see the real person, and a ghost
## sent somewhere else would be standing in the wrong place for everyone.
func travel_refusal() -> String:
	if studio.rig == null:
		return "only a headset travels; on a screen I walks there"
	if co_located():
		return "you share this floor with the others in the room, who see you where you stand: walk over to it, as they would"
	return ""


## Whether this headset shares a real floor with someone else in the session: its frame was taken
## from marks on a real floor (RoomAnchor.marked), and another headset is in the session. Two
## rigs calibrated to the same marks are standing in the same room; a frame handed over whole
## (`adopt_virtual_frame`) is a room of one's own.
func co_located() -> bool:
	if studio.room_anchor == null or not studio.room_anchor.marked or Session.role == Session.Role.SOLO:
		return false
	for peer: int in Session.participants:
		var p: Session.Participant = Session.participants[peer]
		if peer != Session.local_peer_id and p.medium != Presentation.Medium.SCREEN:
			return true
	return false


## The headset's way to station `id`: the play space travels (XRRig.travel) so its centre is on
## the station's seat, facing it, behind a blink of XRRig.FADE (a plain cut at motion 0). The seat
## is the desktop's (Stations.seat, where a person fits) but for a set played only by hand, whose
## headset seat is within arm's reach of it (its row's `reach`), and focused gear is let go first, as on
## a desktop. Refused, the boards say why (StationBoard.refuse) and so does a toast, the rows
## beside a plaque staying up to say it where they were pressed; going, those are put away. The
## toast at the station says its title, its hands line and how to come back.
func _travel_to_station(id: StringName) -> bool:
	var r := Stations.row(id)
	var refused := travel_refusal()
	if refused != "":
		for board in [studio.station_board, studio._beside]:
			if board != null and is_instance_valid(board):
				(board as StationBoard).refuse(refused)
		Session.notice.emit("%s: %s." % [StationBoard.REFUSED.capitalize(), refused])
		return false
	_put_away_beside()
	if studio.focus != null and studio.focus.is_focused():
		studio.focus.release()
	var frame_of := studio.venue.global_transform if studio.venue.is_inside_tree() else studio.venue.transform
	var seat: Transform3D = frame_of * (Stations.seat(studio.venue, id, _station_fits(), true) as Transform3D)
	studio.station = id
	if studio.station_board != null:
		studio.station_board.clear_refusal()
	studio.rig.travel(seat, _travel_fade())
	Session.notice.emit("%s, %s: %s  ·  BACK on its plaque comes home" % [r["title"], Stations.where(r),
			r["hands"]])
	return true


## Home to the desk: BACK on a plaque. A headset's play space travels back to the mix position
## (XRRig.travel_home), co-located or not, since home is where everyone expects you, and at home
## already a toast says so; a desktop walks back as Esc does.
func go_home() -> void:
	_put_away_beside()
	studio.station = &""
	if studio.rig != null:
		if studio.rig.away:
			studio.rig.travel_home(_travel_fade())
			Session.notice.emit("Back at the desk.")
		else:
			Session.notice.emit("Already at the desk.")
		return
	studio.view_host._on_escape()


## How long the blink closes, and opens, on a travel: XRRig.FADE, or none at motion 0.
func _travel_fade() -> float:
	return XRRig.FADE if studio.ergonomics.motion_scale > 0.0 else 0.0


## Where a person fits on the floor (Walker.fits): our walker's, or, in a headset that has none,
## one kept out of the tree for the purpose, told the same floor and solids.
func _station_fits() -> Callable:
	if studio.walker != null:
		return studio.walker.fits
	if studio.floor_plan == null:
		return Callable()
	if studio._seat_finder == null:
		studio._seat_finder = Walker.new()
	studio._seat_finder.floor_plan = studio.floor_plan
	studio._seat_finder.walkable = studio.venue_look._walkable()
	studio._seat_finder.fixed = studio.venue.solids() if studio.venue != null else []
	return studio._seat_finder.fits


## The board on a cheek at either end down to the floor, an apron under its front edge: taken by
## any of it, the tray's bed still being pressed. The apron first, the grip a click from the seat
## finds: the board's top is under the tray.
func _build_desk_wing() -> void:
	studio.desk_wing = studio.rack_host._authored("MiniTable", &"mini_table")
	studio.desk_wing.follow = 10.0
	studio.desk_wing.rolls = false
	studio.desk_wing.footprint_centre = Vector2(-Studio.WING_PAD * 0.5, 0)
	studio.desk_wing.footprint_half = Vector2(Studio.WING.x + Studio.WING_PAD, Studio.WING.z) * 0.5
	var apron := MeshInstance3D.new()
	apron.name = "Apron"
	var strip := BoxMesh.new()
	strip.size = Vector3(Studio.WING.x + Studio.WING_PAD - 0.08, 0.07, 0.02)
	apron.mesh = strip
	apron.position = Vector3(-Studio.WING_PAD * 0.5, Studio.WING_TOP - Studio.WING.y - 0.035, Studio.WING.z * 0.5 - 0.03)
	apron.material_override = Materials.furniture()
	studio.desk_wing.add_part(apron)
	var board := MeshInstance3D.new()
	board.name = "Board"
	var top := BoxMesh.new()
	top.size = Studio.WING + Vector3(Studio.WING_PAD, 0, 0)
	board.mesh = top
	board.position = Vector3(-Studio.WING_PAD * 0.5, Studio.WING_TOP - Studio.WING.y * 0.5, 0)
	board.material_override = Materials.furniture()
	GearTrim.edges(board)
	studio.desk_wing.add_part(board)
	var side := BoxMesh.new()
	side.size = Vector3(0.025, Studio.WING_TOP - Studio.WING.y, Studio.WING.z - 0.04)
	var cheeks: Array[float] = [-Studio.WING.x * 0.5 - Studio.WING_PAD + 0.03, Studio.WING.x * 0.5 - 0.03]
	for n in cheeks.size():
		var cheek := MeshInstance3D.new()
		cheek.name = "Cheek%d" % n
		cheek.mesh = side
		cheek.position = Vector3(cheeks[n], (Studio.WING_TOP - Studio.WING.y) * 0.5, 0)
		cheek.material_override = Materials.furniture()
		studio.desk_wing.add_part(cheek)
	studio.furniture_host._go_live(studio.desk_wing)
	studio.pieces.rehome_items()


## Point, mark and listen together (PointAndMark, docs/spatial_loop.md part two, slice 35): Z, Enter
## and O at a desk, a pointing hand and its pinch in a headset. Presence reads song times through
## it and finds them on this timeline's ruler; a note card's LISTEN key and the wing's note pad
## (`note_pad`) are its too. A controller points by the stick click of the hand that is not the
## chord hand (whose click is the chord stick's).
func _build_point_and_mark() -> void:
	studio.point_and_mark = PointAndMark.new()
	studio.point_and_mark.name = "PointAndMark"
	studio.point_and_mark.studio = studio
	studio.point_and_mark.mouse = studio.get_node_or_null("MouseHand") as MouseInteractor
	if studio.rig != null:
		var chords: XRController3D = studio.rig.left if studio.ergonomics.handedness >= 0 else studio.rig.right
		for controller in studio.rig.interactors:
			var hand := studio.rig.interactors[controller] as XRInteractor
			if hand != null:
				hand.points_by_stick = controller != chords
				studio.point_and_mark.hands.append(hand)
	studio.add_child(studio.point_and_mark)
	if studio.presence != null:
		studio.presence.time_at = studio.point_and_mark.time_at
		studio.presence.ruler_point = func(seconds: float) -> Vector3:
			return studio.timeline.ruler_point(seconds) if studio.timeline != null and is_instance_valid(studio.timeline) \
					and studio.timeline.is_visible_in_tree() else Vector3.INF
	if studio.timeline != null:
		studio.timeline.listen_asked.connect(studio.point_and_mark.listen_from)
	if studio.desk_wing == null and studio.console == null:
		return
	studio.note_pad = NotePad.new()
	studio.note_pad.name = "NotePad"
	if studio.desk_wing != null:
		studio.note_pad.position = Vector3(-Studio.WING.x * 0.5 - Studio.WING_PAD * 0.5, Studio.WING_TOP, 0.02)
		studio.desk_wing.add_child(studio.note_pad)
	else:
		studio.studio_set.add_child(studio.note_pad)
		_place_note_pad()
		studio.console.rebuilt.connect(_place_note_pad)
	studio.note_pad.stuck.connect(studio.point_and_mark.on_pad_stuck)


## In AR, the note pad beside the console's left end, as the wing would be, at the desk's height
## and its front edge with the desk's: where the console is at home, wherever it has grown to.
func _place_note_pad() -> void:
	if studio.note_pad == null or studio.desk_wing != null or studio.console == null:
		return
	var home := studio.focus.home_of(&"console") if studio.focus != null and studio.focus.holds(&"console") \
			else studio.console.transform
	var box := studio.console.content_aabb()
	if box.size.x <= 0.0:
		return
	studio.note_pad.transform = home * Transform3D(Basis.IDENTITY,
			Vector3(box.position.x - Studio.NOTE_PAD_GAP - NotePad.SIZE.x * 0.5, 0.0, box.end.z - NotePad.SIZE.z * 0.5))


## The miniature's pins are the stations standing here; its presses are the studio's.
func _wire_miniature() -> void:
	var mini := studio.items.items.get(MiniatureItem.KIND) as MiniatureItem
	if mini == null:
		return
	mini.pressed.connect(_on_miniature_pressed)
	mini.station_pressed.connect(func(id: StringName) -> void: go_to_station(id))
	_pin_stations()
	studio.venue_changed.connect(func(_id: StringName) -> void: _pin_stations())


## The stations standing here, for the miniature's pins: each with its plan bearing from the mix
## position, the side of the tray its pin stands on.
func _pin_stations() -> void:
	var mini := studio.items.items.get(MiniatureItem.KIND) as MiniatureItem if studio.items != null else null
	if mini == null:
		return
	var rows: Array = []
	for id in station_ids():
		var spot: Variant = Stations.spot(studio.venue, id)
		if spot == null:
			continue
		var at := studio.venue_switch._venue_to_set(spot as Transform3D).origin
		var r := Stations.row(id)
		rows.append([id, r["title"], r["area"], Vector2(at.x, at.z - Studio.MIX_POSITION_Z)])
	mini.set_stations(rows)


## A press on the miniature's bed: the song sought to `seconds` (none for a track's name), and the
## gear for what was pressed brought by FocusRig. On an item, the item selected alone and the
## timeline brought, its window scrolled so the item starts SHOWN_IN into it; on a track, the
## console brought, banked to the page with that track on it. A guest's seek and selection are
## intents like any other (DAW).
func _on_miniature_pressed(track: int, seconds: float, item: int) -> void:
	if seconds >= 0.0:
		DAW.seek(seconds)
	var it := DAW.state.item(track, item) if item >= 0 else null
	if it != null:
		DAW.select_item(track, item)
		if studio.timeline != null and is_instance_valid(studio.timeline):
			studio.timeline.pick_track(track)
			var span := studio.timeline.view_span if studio.timeline.view_span > 0.0 else DAW.state.timeline_length()
			studio.timeline.set_view(maxf(0.0, it.start - span * SHOWN_IN), span)
			_bring(&"timeline")
		return
	if track > 0 and studio.console != null:
		studio.console.bank_to_track(track)
		_bring(&"console")


## Bring surface `id` by FocusRig: to you in a headset, you to it at a desk (FocusRig.visits). One
## the mount shows on the screen is in front of you already: at a desk, whatever gear you went to is
## let go so the screen's panels come back (`_stand_down_screen`).
func _bring(id: StringName) -> void:
	if studio.focus == null or studio.focus.surface(id) == null:
		return
	if studio.mount != null and studio.mount.mode_of(id) == Presentation.Mode.SCREEN:
		if studio.focus.visits and studio.focus.is_focused():
			studio.focus.release()
		return
	# At a desk that would walk the player to it: a press on the miniature only shows the track or
	# the item, from where they are. A headset's is brought to them.
	if studio.focus.visits:
		return
	studio.focus.focus(id)
