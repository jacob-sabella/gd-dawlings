class_name ShotScenes
extends RefCounted

## The scenes a shot can ask for by flag: a posed hand, the test drum, the cassette shelf, the platter, the pads,
## the crank, sections, samples and the rope.
## Moved out of `tools/screenshot.gd` without change of behaviour; the state stays on the autoload, which keeps a one-line delegate for each name another file or a string reaches.

var shot: Screenshot


func _init(of: Screenshot) -> void:
	shot = of


## `--posed-hand`'s hand, in the studio's space: a tracker reporting it, its joints drawn, its
## readings read and lettered.
func _pose_a_hand() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Node3D
	if studio == null:
		return
	var at := Vector3(shot._posed_hand[0], shot._posed_hand[1], shot._posed_hand[2])
	var yaw: float = shot._posed_hand[3] if shot._posed_hand.size() > 3 else 0.0
	var roll: float = shot._posed_hand[4] if shot._posed_hand.size() > 4 else 0.0
	var mask := int(shot._posed_hand[5]) if shot._posed_hand.size() > 5 else 0
	var tracker_name := &"/user/hand_tracker/shot"
	var hand := XRHandTracker.new()
	hand.name = tracker_name
	hand.hand = XRPositionalTracker.TRACKER_HAND_RIGHT
	shot._posed_tracker = hand
	shot._posed_place = [at, yaw, mask]
	_tip_posed_hand(roll)
	hand.has_tracking_data = true
	XRServer.add_tracker(hand)
	var skeleton := HandSkeleton.new()
	skeleton.name = "PosedHand"
	skeleton.tracker_name = tracker_name
	studio.add_child(skeleton)
	shot._posed_gestures = HandGestures.new()
	shot._posed_gestures.name = "PosedHandGestures"
	shot._posed_gestures.tracker_name = tracker_name
	shot._posed_gestures.origin = studio
	var camera := shot.get_viewport().get_camera_3d()
	shot._posed_gestures.head = camera
	studio.add_child(shot._posed_gestures)
	shot._posed_label = Label3D.new()
	shot._posed_label.name = "PosedHandReadings"
	shot._posed_label.pixel_size = 0.0006
	shot._posed_label.font_size = 48
	shot._posed_label.outline_size = 10
	shot._posed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shot._posed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	shot._posed_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	studio.add_child(shot._posed_label)


## The posed hand's joints, rolled `roll` degrees and moved `offset`, onto its tracker, every joint
## seen (HandGestures.confident).
func _tip_posed_hand(roll: float, offset := Vector3.ZERO) -> void:
	var palm := Transform3D(Basis(Vector3.UP, shot._posed_place[1]) * Basis(Vector3.FORWARD, deg_to_rad(roll)),
			shot._posed_place[0] + offset)
	var joints := HandPose.posed(shot._posed_curls, int(shot._posed_place[2]), palm)
	var valid := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID \
			| XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED
	for j in XRHandTracker.HAND_JOINT_MAX:
		shot._posed_tracker.set_hand_joint_flags(j, valid)
		shot._posed_tracker.set_hand_joint_radius(j, 0.009)
		shot._posed_tracker.set_hand_joint_transform(j, Transform3D(Basis.IDENTITY, joints[j]))


## `--rope`'s rope: tied and pulled at frame 6, the song played from the start of the kick's first
## item, and at the shot frame how far it ducks.
## `--test-drum`: the test drum on the floor where the view sees floor, low on its right: where the
## ray through that point of the screen meets the floor at the seat's feet.
func _stand_the_test_drum() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
	var camera := shot.get_viewport().get_camera_3d()
	if studio == null or studio.items == null or camera == null:
		return
	var size := shot.get_viewport().get_visible_rect().size
	var through := Vector2(size.x * 0.82, size.y * 0.72)
	var from := studio.items.to_local(camera.project_ray_origin(through))
	var way := studio.items.global_basis.inverse() * camera.project_ray_normal(through)
	var floor := studio.items.ground(Vector2(from.x, from.z))
	if way.y > -0.01:
		return
	var spot := from + way * ((floor - from.y) / way.y)
	spot.y = studio.items.ground(Vector2(spot.x, spot.z))
	studio.items.spawn(&"testdrum", &"testdrum", Transform3D(Basis.IDENTITY, spot))


## `--cassettes`: a clip off each of the first tracks with one, minted as the host mints a pull
## (the studio's own `_mint_for`), shelved one to a slot from the top left, and the rack gone to.
## Its walk there takes up to two seconds: shoot it at a later frame (`tools/shot.sh out 200 206`).
func _shelve_cassettes() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
	if studio == null or studio.items == null or studio.cassette_rack == null:
		return
	var made := 0
	for index in DAW.state.track_indices():
		if made >= shot._cassettes:
			break
		if DAW.state.track(index).items.is_empty():
			continue
		var item := studio.item_host._mint_for(CassetteItem.KIND, "clip:%d:0" % index, Session.local_peer_id)
		if item == null:
			continue
		studio.items.slot_item(item, CassetteRack.RACK, made)
		item.transform = item.resting
		made += 1
	# Where the rack stands and which way its front faces, for a SHOT_CAM framed on its slots.
	var rack := studio.cassette_rack.global_transform
	print("SHOT_CASSETTES ", studio.items.made_ids(), " rack at ", rack.origin, " facing ", rack.basis.z)
	studio.station_host.go_to_station(&"cassette_rack")


## `--platter`: a clip's cassette, minted as the host mints a pull, stood in the platter's slot.
func _slot_the_platter() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
	if studio == null or studio.items == null or studio.platter == null:
		return
	for index in DAW.state.track_indices():
		if DAW.state.track(index).items.is_empty():
			continue
		var item := studio.item_host._mint_for(CassetteItem.KIND, "clip:%d:0" % index, Session.local_peer_id)
		if item == null:
			continue
		studio.items.slot_item(item, Platter.HOLDER, 0)
		item.transform = item.resting
		break
	var at := studio.platter.global_transform
	print("SHOT_PLATTER ", studio.items.made_ids(), " platter at ", at.origin, " facing ", at.basis.z)
	if shot._cam.size() != 6:
		studio.station_host.go_to_station(&"platter")


func _play_the_pads() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
	if studio == null or studio.tv == null or studio.tv.deck == null:
		return
	var deck := studio.tv.deck
	if shot._frames == 8:
		# Sixteen sounds of 3000 frames: pitched sines for the low half, noise bursts for the rest.
		var sound := PackedVector2Array()
		sound.resize(48000)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for slice in 16:
			for i in 3000:
				var env := exp(-i / (500.0 + 90.0 * (slice % 4)))
				var v := 0.0
				if slice % 4 == 0:
					v = sin(i * (0.04 + 0.002 * slice)) * env
				elif slice % 4 == 2:
					v = rng.randf_range(-1, 1) * env * 0.6
				else:
					v = sin(i * (0.1 + 0.01 * slice)) * env * 0.7
				sound[slice * 3000 + i] = Vector2(v, v)
		deck.bank.set_sample(sound)
		deck.refresh()
	if shot._frames >= 30 and shot._frames % 9 == 0:
		var step := (shot._frames - 30) / 9
		var pattern := [0, 8, 2, 8, 0, 5, 2, 12, 0, 8, 2, 10, 1, 5, 2, 15]
		deck.strike(pattern[step % pattern.size()], 70 + (step * 37) % 55)


## `--crank N`: five steps of history, and the deck's crank turned back N of them, held there.
func _turn_the_crank() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
	if studio == null or studio.deck == null or studio.deck.crank == null:
		return
	var s := DAW.state
	var tracks := s.track_indices()
	for n in mini(5, tracks.size()):
		DAW.set_track_volume(tracks[n], 0.5 + 0.05 * n)
	var crank := studio.deck.crank
	# Held still past SETTLE it would undo them: a frame-less crank stands where it was turned.
	crank.set_process(false)
	crank.turn_to(-shot._crank)
	print("SHOT_CRANK ", crank.readout_text(), " at ", crank.global_position, " facing ", crank.global_basis.z)


## `--sections N`: the demo's markers made sections, the playhead in the second, and block N held at
## the front of the row when N is above 0.
func _make_the_sections() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
	if studio == null or studio.sections == null:
		return
	var blocks := studio.sections
	if DAW.state.regions.is_empty():
		blocks.make_sections()
	if DAW.state.regions.size() > 1:
		DAW.seek(lerpf(float(DAW.state.regions[1][0]), float(DAW.state.regions[1][1]), 0.3))
	blocks._process(0.0)
	if shot._sections > 0 and shot._sections <= blocks.blocks().size():
		var block: SectionBlocks.Block = blocks.blocks()[shot._sections - 1]
		shot._sections_hand = Node.new()
		shot.add_child(shot._sections_hand)
		block.grab_begin(shot._sections_hand, block.global_position)
		block.grab_move(shot._sections_hand, blocks.to_global(Vector3(-SectionBlocks.ROW * 0.5 + block.width * 0.5,
				SectionBlocks.LIFT, SectionBlocks.ROW_Z)))
	print("SHOT_SECTIONS ", DAW.state.regions.map(func(r): return r[2]), " shown ", blocks.shown_order(),
			" at ", blocks.global_position, " facing ", blocks.global_basis.z)
	if shot._cam.size() != 6:
		studio.station_host.go_to_station(&"sections")


## `--samples`: REC, then a use, that many times, by the mouse's hand, as a desktop player samples:
## the sampler's own press (Studio._on_rec_pressed) and the item's own use (Item.work).
func _make_samples() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
	if studio == null or studio.items == null or studio.sampler == null:
		return
	var dir := ProjectSettings.globalize_path("user://shot_samples")
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	studio.sampler.media_path = func(name: String) -> String: return dir.path_join(name)
	var hand := studio.get_node_or_null("MouseHand") as MouseInteractor
	var kinds: Array[StringName] = [&"duck", &"yoyo", &"cards"]
	for n in shot._samples:
		var item: Item = studio.items.items.get(kinds[n % kinds.size()])
		if item == null or hand == null:
			continue
		studio.sampler_host._on_rec_pressed(true)
		hand.pick_up(item)
		item.work(true)
		item.work(false)
		hand.lose_carrying()
		item.snap_home()
	studio.sampler_host._on_rec_pressed(true)
	var at := studio.sampler.global_transform
	print("SHOT_SAMPLES ", studio.items.made_ids(), " sampler at ", at.origin, " facing ", at.basis.z,
			" rack at ", studio.cassette_rack.global_position if studio.cassette_rack != null else Vector3.ZERO)
	# Framed by SHOT_CAM, it stays framed there, the rack beside it in the shot too, and the room is
	# the picture: the toasts it said are let go.
	if shot._cam.size() != 6:
		studio.station_host.go_to_station(&"sampler")
		return
	var panel := shot.get_tree().current_scene.find_child("SessionPanel", true, false) as SessionPanel
	if panel != null and panel._toasts != null:
		for card in panel._toasts.get_children():
			card.free()


func _tie_the_rope() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
	var table: StageTable = studio.stage if studio != null else null
	if table == null:
		return
	var from := int(shot._rope[0])
	var to := int(shot._rope[1])
	if shot._frames == 6:
		if Sidechain.key_send(from, to) == 0:
			table.tie(from, to)
		if shot._rope.size() > 2:
			table.pull(from, to, float(shot._rope[2]))
		var t := DAW.state.track(from, false)
		if t != null and not t.items.is_empty():
			DAW.seek((t.items[0] as MixState.ItemState).start)
		DAW.transport_play()
	if shot._frames == shot._shot_frame:
		var rope: StageTable.Rope = table.rope_nodes.get(Sidechain.rope_key(from, to))
		if rope != null:
			var camera := shot.get_viewport().get_camera_3d()
			print("SHOT_ROPE ducking %.1f dB, lifted %.3f m, its middle at %s on screen: %s" % [rope.ducking, rope.lifted,
					camera.unproject_position(rope.global_position) if camera != null else Vector2.ZERO, rope.readout()])


## `--rack-patch`, `--delta` and `--mod` (and the guard for `--make-room`, which writes a room file): files put into the user data before the studio reads it (the
## autoload's `_ready` runs ahead of the main scene). Only into a data dir of the run's own: the player's
## real one is never touched (`SHOT_DATA_HOME`, tools/shot.sh).
func install_files() -> void:
	if shot._rack_patch == "" and shot._delta == "" and shot._mods.is_empty() and shot._make_room == "":
		return
	var real := OS.get_environment("HOME").path_join(".local/share/godot/app_userdata").path_join(
			str(ProjectSettings.get_setting("application/config/name")))
	if OS.get_user_data_dir().simplify_path() == real.simplify_path():
		push_error("SHOT_REFUSED --rack-patch/--delta/--mod would write into the real user data %s; set SHOT_DATA_HOME" % real)
		shot.get_tree().quit(2)
		return
	if shot._rack_patch != "":
		var path := RackPatchFile.current_path()
		print("SHOT_INSTALL patch ", path, " ", _copy_file(shot._rack_patch, path))
	if shot._delta != "":
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(shot._delta))
		var key := str(raw.get("room", "")) if raw is Dictionary else ""
		var path := RoomDeltaFile.path_of(key) if key != "" else ""
		print("SHOT_INSTALL delta ", path, " ", _copy_file(shot._delta, path) if path != "" else "no room key in the file")
	for folder in shot._mods:
		var to := DataHome.dir("mods") + folder.rstrip("/").get_file()
		DirAccess.make_dir_recursive_absolute(to)
		for f in DirAccess.get_files_at(folder):
			_copy_file(folder.path_join(f), to.path_join(f))
		print("SHOT_INSTALL mod ", to)


func _copy_file(from: String, to: String) -> Error:
	if DirAccess.make_dir_recursive_absolute(to.get_base_dir()) != OK and not DirAccess.dir_exists_absolute(to.get_base_dir()):
		return ERR_CANT_CREATE
	return DirAccess.copy_absolute(from, to)


## `--make-room size[:zones[:title[:style]]]`: the room-maker's MAKE, asked for from the maker's own spec.
func _make_a_room() -> void:
	var maker := shot.get_tree().current_scene.find_child("RoomMaker", true, false) as RoomMaker
	if maker == null:
		print("SHOT_MAKE_ROOM no RoomMaker")
		return
	var words: PackedStringArray = shot._make_room.split(":")
	maker.set_size(StringName(words[0]))
	if words.size() > 1 and words[1] != "all":
		var zones: Array = []
		for z in words[1].split("+", false):
			zones.append(z)
		maker.spec["zones"] = zones
		maker._drop_unneeded()
	maker.spec["title"] = words[2].replace("_", " ") if words.size() > 2 and words[2] != "" else "%s shot room" % words[0]
	if words.size() > 3:
		maker.spec["style"] = words[3]
	print("SHOT_MAKE_ROOM spec=", maker.spec, " said='", maker.make(), "' venue=", (shot.get_tree().current_scene.get_node("Studio") as Studio).venue.name)


## `--mod-answer accept|decline`: presses that button on the first waiting offer in the session panel, as a click would.
func _answer_mod_offer() -> void:
	var button := shot.get_tree().current_scene.find_child("Accept" if shot._mod_answer == "accept" else "Decline", true, false) as Button
	print("SHOT_MOD_ANSWER ", shot._mod_answer, " button=", button != null)
	if button != null:
		button.pressed.emit()


## `--panel layout|maker|mods[:piece]`: the F3, F4 or F5 panel open, as the key leaves it.
func _open_panel() -> void:
	var words: PackedStringArray = shot._panel.split(":")
	var root := shot.get_tree().current_scene
	if words[0] == "mods":
		var mods_screen := root.find_child("ModsScreen", true, false) as ModsScreen
		if mods_screen != null and not mods_screen.is_open():
			mods_screen.toggle()
	elif words[0] == "maker":
		var maker := root.find_child("RoomMaker", true, false) as RoomMaker
		if maker != null and not maker.is_open():
			maker.toggle()
	else:
		var editor := root.find_child("LayoutEditor", true, false) as LayoutEditor
		if editor != null:
			if not editor.is_open():
				editor.toggle()
			if words.size() > 1:
				editor._pick(StringName(words[1]))
			# `layout:hoop:nudge`: and pressed once, so the panel's status line says what it did.
			if words.size() > 2 and words[2] == "nudge":
				editor._nudge(0.4, 0.0)
	print("SHOT_PANEL ", shot._panel)
