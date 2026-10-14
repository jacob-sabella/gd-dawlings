extends Node

## Capture harness: run the real studio in a real window and write frames to PNG.
##
## An autoload so it observes whatever is running rather than being wired into a scene. The
## alternative to this -- reading the scene files and asserting the console probably looks like a
## console -- is not verification of anything. A 3D project in particular cannot be reviewed any
## other way: materials, glow and shadow are the difference between gear and grey boxes, and none
## of the three exist until something renders.
##
##   godot --path . -- --shot /tmp/console.png --shot-frame 30 --quit-after 34
##   godot --path . -- --shot /tmp/wide.png --cam 0.5,-0.3,2.6,0,0.95,0
##
## --cam is yaw,pitch,distance,target_x,target_y,target_z. Framing is a command-line argument
## because a capture nobody can reproduce is not evidence: the numbers that produced a shot
## belong next to the shot.

var _shot_path := ""
var _shot_frame := 24
var _quit_after := -1
var _frames := 0
var _cam: Array = []
## x,z,yaw,pitch[,y]: stand the walker somewhere and look, instead of flying the god camera. `y`
## is the floor you stand on, when it is not the ground: a gallery, a riser.
var _walk: Array = []
var _walk_mirror := 0.0
## `--carry duck`: that item in the mouse's hand from frame 9, as if it had been picked up.
## `--carry duck:squeeze` holds it squeezed. `--carry headphones:wear` puts them on. For a
## personal kind (`ItemRoom.PERSONAL_KINDS`) this takes a copy of your own, as a real grab would,
## rather than holding the shelf's dispenser.
## `--carry tablet:mix:keys` puts its plugs A and B in those SEND sockets (`track_5`: a strip's);
## `:home` after them puts it back on its shelf. `--carry keytar:chord` holds a C major chord down
## on it (play these into the null sink: it sounds). `--carry chips:t2@0.5` does a fidget's
## tricks before trick 2 and stops trick 2 half way. `--carry rcplane:fly:cut@300` flies the radio
## plane and cuts its motor on frame 300; `--carry rcplane:fly@400` takes off on frame 400.
var _carry := ""
## `--pockets duck,ball,keytar`: those items picked up and put in pockets 1, 2 and 3 in turn, from
## frame 9, before anything `--carry` puts in the hand.
var _pockets: PackedStringArray = []
## `--visitor 0.6,-0.4,3.0`: another player, Lin (peer 7), standing there (studio x, z) facing
## that yaw, from frame 5: their ghost, and its keys pack (`--carry tablet:keys_7` plugs into it).
var _visitor: Array = []
## `--on-air 7`: that player ON AIR from frame 8, so their pack has its MONITOR socket
## (`--carry tablet:monitor_7`); `--on-air 1` is the one at this machine.
var _on_air := 0
## `--throw 0.6@200`: throw what --carry picked up, wound up that far (0..1), on that physics
## tick. Shoot it in flight with --shot-tick a little later.
var _throw := Vector2(-1, -1)
## `--lob 5.93,2.0,3.12,3@200`: throw what --carry picked up from the hand to that point (studio
## space) at that speed (m/s), on that physics tick: a throw that goes exactly where it is
## pointed, for a shot of it getting there. --spectate watches it as for --throw.
var _lob := PackedFloat32Array()
var _lob_tick := -1
## `--spectate 3,1.2,0:0,0.8,-2`: once --throw has thrown, watch from a camera there looking at
## that point (studio space), to see a flight from the side rather than from behind it.
var _spectate: Array = []
var _shot_res := Vector2i.ZERO
var _hover := Vector2(-1, -1)
## `--drag 400,600:900,640@20-70`: hold the left button at the first point on physics tick 20,
## move to the second by tick 70, let go. `--turn 2` adds that many wheel notches halfway through.
## [from: Vector2, to: Vector2, first_tick: int, last_tick: int] per --drag; repeatable.
var _drags: Array = []
var _turn := 0
var _ticks := 0
## `--shot-tick 240`: capture on that physics tick instead of a drawn frame, for anything that
## moves in simulated time -- a pushed rack coasting to a stop -- rather than in frames.
var _shot_tick := -1
## `--quit-tick 900`: stay up until then after a --shot-tick capture. For a capture that is one
## half of a pair -- a guest that has to still be in the room when the host takes ITS picture.
var _quit_tick := -1
## Controls addressed by what they are called rather than where they happen to be drawn, so a
## step in the walkthrough survives the desk being re-laid out.
##   --aim KICK_IN__LEVEL               park the pointer on it (its hover card is the evidence)
##   --click TRANSPORT__PLAY@40         press it on tick 40 (repeatable)
##   --pull KICK_IN__LEVEL:0,60@40-90   drag from it by that many pixels over those ticks
## `_` stands for a space. An exact title wins; otherwise the first title containing it.
var _aim := ""
## `--look -0.6,-0.1`: turn the head by that much yaw and pitch (radians) where it already is --
## a look to the side from the seat, rather than --walk's standing somewhere else.
var _look := Vector2.ZERO
var _clicks: Array = []
var _pulls: Array = []
## `--rig-roll`: presses the Rig Roulette ROLL from frame 9.
## `--pull-track`: the first track with plugins pulled out of the rack on its own rack, and its
## first plugin on a tablet, frame 12.
## `--pull-tracks <n>`: the first n tracks with plugins pulled out on racks of their own, in a row
## behind the mix position, frame 12.
## `--board <surface id>`: the big board shows that surface live from frame 12 (after any roll).
## `--tour intact|broken|brief|draft|chaos|crowd|clock_low|win|loss|spill|rig`: the Tour case and its run put in that state from frame 9,
## deterministically (Tour.force_state_for_shot) rather than by waiting out a brief's timer.
## Needs the built-in engine (--built-in): Tour is gated to it, and quietly does nothing on any
## other backend, same as in play.
var _tour := ""
## `--tour-band 8`: fake guests 2..N registered on `Session.participants` at frame 8, before
## `--tour` forces the run's state at frame 9, so a brief's flaw/part count is drawn for that
## band size instead of a solo one -- for a shot of how a crowded card holds up, not for any
## real multiplayer behaviour.
var _tour_band := 0
## `--tl-shelf on|off`: the timeline in its 3D view (or flat), whatever the layout says, from frame 6.
var _tl_shelf := ""
## `--tl-road 30`: the timeline as the road, with the playhead parked at that many seconds, from frame 6.
var _tl_road := -1.0
## `--tl-select 3:0,3:1`: those items (track:item) selected from frame 7, so the timeline's item
## page shows. `--tl-pick 3`: that track picked from frame 7, for the track page.
var _tl_select := ""
## `--tl-region 9:17:Verse,17:25:Chorus`: regions from bar to bar, made at frame 7.
var _tl_region := ""
## `--reopen`: the project saved and opened again at frame 5, to see what a reopened project draws.
var _reopen := false
var _tl_pick := -1
var _roll := false
var _rig_roll := false
var _board := ""
var _pull_track := false
var _pull_tracks := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--shot":
				if i + 1 < args.size(): _shot_path = args[i + 1]
			"--shot-frame":
				if i + 1 < args.size(): _shot_frame = int(args[i + 1])
			"--quit-after":
				if i + 1 < args.size(): _quit_after = int(args[i + 1])
			"--shot-res":
				if i + 1 < args.size(): _shot_res = _parse_res(args[i + 1])
			# Where the cursor is, in viewport pixels. The capture window is on a workspace nobody
			# is looking at, so the real mouse is not over it -- and a hover card is only evidence
			# if the same interactor that a person drives produced it. This parks THAT interactor's
			# pointer rather than drawing a card by hand.
			"--hover":
				if i + 1 < args.size():
					var xy := args[i + 1].split(",")
					if xy.size() == 2: _hover = Vector2(float(xy[0]), float(xy[1]))
			"--drag":
				if i + 1 < args.size():
					var spec := args[i + 1].split("@")
					var ends := spec[0].split(":")
					if spec.size() == 2 and ends.size() == 2:
						var a := ends[0].split(",")
						var b := ends[1].split(",")
						var f := spec[1].split("-")
						_drags.append([Vector2(float(a[0]), float(a[1])),
								Vector2(float(b[0]), float(b[1])), int(f[0]), int(f[1])])
			"--shot-tick":
				if i + 1 < args.size(): _shot_tick = int(args[i + 1])
			"--look":
				if i + 1 < args.size():
					var yp := args[i + 1].split(",")
					if yp.size() == 2: _look = Vector2(float(yp[0]), float(yp[1]))
			"--aim":
				if i + 1 < args.size(): _aim = args[i + 1]
			"--click":
				if i + 1 < args.size():
					var at := args[i + 1].rsplit("@", true, 1)
					if at.size() == 2: _clicks.append([at[0], int(at[1])])
			"--pull":
				if i + 1 < args.size():
					var at := args[i + 1].rsplit("@", true, 1)
					var what := at[0].rsplit(":", true, 1)
					if at.size() == 2 and what.size() == 2:
						var by := what[1].split(",")
						var span := at[1].split("-")
						_pulls.append([what[0], Vector2(float(by[0]), float(by[1])),
								int(span[0]), int(span[1])])
			"--turn":
				if i + 1 < args.size(): _turn = int(args[i + 1])
			"--pockets":
				if i + 1 < args.size(): _pockets = args[i + 1].split(",")
			"--carry":
				if i + 1 < args.size(): _carry = args[i + 1]
			"--on-air":
				if i + 1 < args.size(): _on_air = int(args[i + 1])
			"--visitor":
				if i + 1 < args.size(): _visitor = Array(args[i + 1].split(",")).map(func(v): return float(v))
			"--throw":
				if i + 1 < args.size():
					var parts := args[i + 1].split("@")
					_throw = Vector2(float(parts[0]), int(parts[1]) if parts.size() > 1 else 200)
			"--lob":
				if i + 1 < args.size():
					var parts := args[i + 1].split("@")
					_lob = PackedFloat32Array(Array(parts[0].split(",")).map(func(v): return float(v)))
					_lob_tick = int(parts[1]) if parts.size() > 1 else 200
			"--spectate":
				if i + 1 < args.size():
					var ends := args[i + 1].split(":")
					if ends.size() == 2:
						var a := ends[0].split(",")
						var b := ends[1].split(",")
						_spectate = [Vector3(float(a[0]), float(a[1]), float(a[2])),
								Vector3(float(b[0]), float(b[1]), float(b[2]))]
			"--walk":
				# "mirror[,distance]": stood in front of the venue's mirror, facing it.
				if i + 1 < args.size() and args[i + 1].begins_with("mirror"):
					var parts := args[i + 1].split(",")
					_walk_mirror = float(parts[1]) if parts.size() > 1 else 1.4
				elif i + 1 < args.size(): _walk = Array(args[i + 1].split(",")).map(func(s): return float(s))
			"--quit-tick":
				if i + 1 < args.size(): _quit_tick = int(args[i + 1])
			"--cam":
				if i + 1 < args.size(): _cam = Array(args[i + 1].split(",")).map(func(s): return float(s))
			"--tour":
				if i + 1 < args.size(): _tour = args[i + 1]
			"--tl-shelf":
				if i + 1 < args.size(): _tl_shelf = args[i + 1]
			"--roll":
				_roll = true
			"--rig-roll":
				_rig_roll = true
			"--pull-track":
				_pull_track = true
			"--pull-tracks":
				if i + 1 < args.size(): _pull_tracks = int(args[i + 1])
			"--board":
				if i + 1 < args.size(): _board = args[i + 1]
			"--tl-select":
				if i + 1 < args.size(): _tl_select = args[i + 1]
			"--reopen":
				_reopen = true
			"--tl-region":
				if i + 1 < args.size(): _tl_region = args[i + 1]
			"--tl-pick":
				if i + 1 < args.size(): _tl_pick = int(args[i + 1])
			"--tl-road":
				if i + 1 < args.size(): _tl_road = float(args[i + 1])
			"--tour-band":
				if i + 1 < args.size(): _tour_band = int(args[i + 1])
	if _shot_tick >= 0:
		_shot_frame = -1
		_quit_after = -1
	if _shot_path == "" and _quit_after < 0 and _shot_tick < 0:
		set_process(false)


func _parse_res(spec: String) -> Vector2i:
	var parts := spec.split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func _process(_delta: float) -> void:
	_frames += 1
	if _frames % 15 == 0 and OS.get_cmdline_user_args().has("--shot-debug"):
		print("SHOT_FRAME %d tick %d at %d ms" % [_frames, _ticks, Time.get_ticks_msec()])

	# Framing is applied a few frames in, not at frame 0. The studio builds its surfaces on the
	# first processed frame, so a camera positioned before that is aimed at an empty room.
	if _frames == 4 and _cam.size() == 6:
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		if studio and studio.has_method("frame"):
			# A framed shot is a god's-eye view by definition: it hangs wherever it was told to.
			if studio.has_method("set_god_mode"):
				studio.set_god_mode(true)
			studio.frame(Vector3(_cam[3], _cam[4], _cam[5]), _cam[2], _cam[0], _cam[1])

	if _frames == 6 and _tl_shelf != "":
		var tl := get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false)
		if not tl.is_empty():
			(tl[0] as TimelineSurface).set_shelf(_tl_shelf == "on")
			print("SHOT_TL shelf=", (tl[0] as TimelineSurface).shelf)
		else:
			print("SHOT_TL none found")

	if _frames == 6 and _tl_road >= 0.0:
		var tl := get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false)
		if not tl.is_empty():
			DAW.seek(_tl_road)
			(tl[0] as TimelineSurface).set_highway(true)
	if _frames == 7 and (_tl_select != "" or _tl_pick >= 0):
		var tl := get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false)
		if _tl_pick >= 0 and not tl.is_empty():
			(tl[0] as TimelineSurface).pick_track(_tl_pick)
		var first := true
		for pair in _tl_select.split(",", false):
			var ti := pair.split(":")
			if ti.size() == 2:
				DAW.select_item(int(ti[0]), int(ti[1]), not first)
				first = false
		print("SHOT_TL selected=", DAW.state.selected_items(), " picked=", _tl_pick)
	if _frames == 5 and _reopen:
		var path := ProjectSettings.globalize_path("user://shot_reopen.dawproject")
		print("SHOT_REOPEN ", DAW.save_project_as(path), DAW.open_project(path))
	if _frames == 7 and _tl_region != "":
		for spec in _tl_region.split(",", false):
			var r := spec.split(":")
			if r.size() == 3:
				DAW.add_region(DAW.state.bar_to_seconds(float(r[0])), DAW.state.bar_to_seconds(float(r[1])), r[2])
	if _frames == 7 and _roll:
		DAW.transport_play()
	if _frames == 12 and _pull_track:
		var puller := get_tree().current_scene.get_node_or_null("Studio")
		if puller != null:
			for i in DAW.state.track_indices():
				if not DAW.state.track(i).plugins().is_empty():
					puller.open_track_rack(i, Vector2(-0.45, 0.25))
					var first: int = DAW.state.track(i).plugins()[0]
					puller.open_tablet(i, first, DAW.state.fx(i, first).name, Vector2(-0.95, 0.55))
					break
	if _frames == 12 and _pull_tracks > 0:
		var row := get_tree().current_scene.get_node_or_null("Studio")
		if row != null:
			var with_plugins := DAW.state.track_indices().filter(
					func(t): return not DAW.state.track(t).plugins().is_empty())
			var n := mini(_pull_tracks, with_plugins.size())
			for k in n:
				row.open_track_rack(with_plugins[k], Vector2((k - (n - 1) * 0.5) * 0.75, 1.7))
	if _frames == 12 and not _board.is_empty():
		var studio_node := get_tree().current_scene.get_node_or_null("Studio")
		if studio_node != null:
			studio_node.choose_board_source(StringName(_board))
	if _frames == 9 and _rig_roll:
		var rolled := get_tree().current_scene.get_node_or_null("Studio")
		if rolled != null:
			rolled._roll_rig()


	# Later than the camera, so a visit the studio makes on its own at startup has landed first.
	if _frames == 8 and _walk_mirror > 0.0:
		var mirrors := get_tree().current_scene.find_children("*", "Mirror", true, false)
		if not mirrors.is_empty():
			var m := (mirrors[0] as Node3D).global_transform
			var front := Vector3(m.basis.z.x, 0, m.basis.z.z).normalized()
			var at := m.origin + front * _walk_mirror
			_walk = [at.x, at.z, atan2(front.x, front.z), -0.05]
	if _frames == 8 and _walk.size() >= 4:
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		if studio and studio.get("walker") != null:
			var w = studio.walker
			w.global_position = Vector3(_walk[0], _walk[4] if _walk.size() > 4 else 0.0, _walk[1])
			w.yaw = _walk[2]
			w.pitch = _walk[3]
			w.eye_height = w.standing_eye
			w._place_camera()

	if _frames == 5 and _visitor.size() >= 3:
		var lin := Session.Participant.new()
		lin.peer_id = 7
		lin.display_name = "Lin"
		lin.colour_index = 2
		lin.head = Transform3D(Basis(Vector3.UP, _visitor[2]), Vector3(_visitor[0], 1.55, _visitor[1]))
		Session.participants[7] = lin
		Session.roster_changed.emit()
	if _frames >= 5 and Session.participants.has(7):
		(Session.participants[7] as Session.Participant).heard_msec = Time.get_ticks_msec()

	if _frames == 8 and _on_air > 0:
		var on_air_studio := get_tree().current_scene.get_node_or_null("Studio")
		if on_air_studio != null and on_air_studio.has_method("_set_on_air"):
			on_air_studio._set_on_air(_on_air, true)

	if _frames == 8 and _tour_band > 1:
		for n in range(2, _tour_band + 1):
			var mate := Session.Participant.new()
			mate.peer_id = n
			mate.display_name = "Mate%d" % n
			mate.colour_index = n % Session.PALETTE.size()
			Session.participants[n] = mate
		Session.roster_changed.emit()

	if _frames == 9 and _tour != "" and _tour != "intact":
		Tour.force_state_for_shot(StringName(_tour))

	if _frames == 9 and not _pockets.is_empty():
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		var hand := studio.get_node_or_null("MouseHand") as Interactor if studio else null
		var room: ItemRoom = studio.get("items") if studio else null
		if hand != null and room != null:
			for n in mini(_pockets.size(), Pockets.COUNT):
				var item: Item = room.items.get(StringName(_pockets[n]))
				if item != null:
					hand.pick_up(item)
					hand.stow(n)
	if _frames == 9 and _carry != "":
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		var what := _carry.split(":")
		var hand := studio.get_node_or_null("MouseHand") as Interactor if studio else null
		var room: ItemRoom = studio.get("items") if studio else null
		var kind := StringName(what[0])
		if hand != null and room != null and room.items.has(kind):
			var item: Item = room.take_personal(kind, Session.local_peer_id) if kind in ItemRoom.PERSONAL_KINDS else room.items[kind]
			hand.pick_up(item)
			if what.size() > 1 and what[1] == "squeeze":
				item.use(true)
			if what.has("wear"):
				hand.wear()
			# `--carry tablet:mix:keys`: its plugs A, B... in those SEND sockets.
			var receiver := 0
			for word in what.slice(1):
				if PersonalMix.valid_socket(StringName(word)) and word != "" and studio.has_method("_on_patch_asked"):
					studio._on_patch_asked(receiver, StringName(word))
					receiver += 1
			# `--carry tablet:mix:home`: and then back on its shelf, out of the view.
			if what.has("home"):
				hand.lose_carrying()
				item.snap_home()

	# `--carry keytar:chord`: C, E and G held down on it, once it has been in the hand a frame or two.
	if _frames == 13 and _carry.split(":").has("chord") and Session.guest_midi != null:
		for pitch in [60, 64, 67]:
			Session.guest_midi.note_on(pitch, 90)

	# `--rc-debug`: where the radio plane is and how it flies, on this machine, every 30 frames --
	# for a guest watching a host fly it.
	if _frames % 30 == 0 and OS.get_cmdline_user_args().has("--rc-debug"):
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		var room: ItemRoom = studio.get("items") if studio else null
		var rc := room.items.get(&"rcplane") as RcPlaneItem if room != null else null
		if rc != null:
			print("RCDEBUG f%d mode %d plane %s held_elsewhere %s" % [_frames, rc.mode,
					rc.plane.global_position, rc.is_held_elsewhere()])

	# `--carry rcplane:fly`: its motor run up a few frames after the radio is in the hand, so the
	# plane takes off; `:cut@N` cuts the motor on frame N. With --shot-debug, where it is.
	if _carry.begins_with("rcplane:"):
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		var room: ItemRoom = studio.get("items") if studio else null
		var rc := room.items.get(&"rcplane") as RcPlaneItem if room != null else null
		if rc != null:
			if _frames == 13 and _carry.split(":").has("fly"):
				rc.work(true)
			for word in _carry.split(":"):
				if word.begins_with("cut@") and _frames == int(word.substr(4)):
					rc.work(true)
				# `fly@N`: the motor run up on frame N instead, for a guest who joins later to see.
				if word.begins_with("fly@") and _frames == int(word.substr(4)):
					rc.work(true)
			if _frames % 20 == 0 and OS.get_cmdline_user_args().has("--shot-debug"):
				print("RCPLANE f%d mode %d at %s speed %.2f slope %.2f" % [_frames, rc.mode, rc.at, rc.speed, rc.slope])
				if _frames == 20:
					print("RCPLANE floor ", room.floor_rects.call(), " fps ", Engine.get_frames_per_second(), " phys ", Engine.physics_ticks_per_second)

	# `--carry cards:t1@0.8`: the tricks before trick 1 done, and trick 1 stopped 0.8 of the way.
	if _frames == 13 and _carry.contains(":t") and _carry.contains("@"):
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		var room: ItemRoom = studio.get("items") if studio else null
		var what := _carry.split(":")
		var fidget := room.items.get(StringName(what[0])) as FidgetItem if room != null else null
		var at := what[1].substr(1).split("@")
		if fidget != null and at.size() == 2:
			for n in int(at[0]):
				fidget.use(true)
				fidget.finish()
			fidget.use(true)
			fidget.set_process(false)
			fidget.pose(fidget.playing, float(at[1]))

	if _frames == 28 and _carry != "" and OS.get_cmdline_user_args().has("--shot-debug"):
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		var hand := studio.get_node_or_null("MouseHand") as Interactor
		if hand != null and hand.carrying != null:
			print("CARRY item %s glove %s pose %s state %d proc %s" % [hand.carrying.global_position,
					hand._glove.global_position if hand._glove else Vector3.ZERO, hand.carry_pose().origin,
					hand.carrying.state, hand.carrying.is_physics_processing()])

	if _aim != "" and _scripted_hand() != null and _ticks > 2:
		var at := _screen_of(_aim)
		if at.x >= 0.0:
			_hover = at
	var held := _scripted_hand() != null and _scripted_hand().press_override == 1
	if _frames == 10 and _look != Vector2.ZERO:
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		if studio and studio.get("walker") != null:
			var w = studio.walker
			w.yaw += _look.x
			w.pitch += _look.y
			w._place_camera()
	if _hover.x >= 0.0 and not held:
		for hand in get_tree().root.find_children("*", "MouseInteractor", true, false):
			(hand as MouseInteractor).pointer_override = _hover

	if _shot_path != "" and _frames == _shot_frame:
		_capture()

	if _quit_after > 0 and _frames >= _quit_after:
		get_tree().quit()


func _capture() -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_shot_path)
	if err != OK:
		push_error("SHOT_FAILED %s: %s" % [_shot_path, error_string(err)])
		return
	# Echoed with the size the engine ACTUALLY rendered. A capture whose dimensions are not
	# stated can be compared against the wrong thing without anyone noticing -- a window manager
	# that packs the window produces a smaller PNG that still looks like a successful shot.
	print("SHOT_SAVED %s %dx%d" % [_shot_path, image.get_width(), image.get_height()])


## --spectate's camera, from the moment of a throw.
func _watch_the_throw(studio: Node) -> void:
	if studio != null and _spectate.size() == 2:
		var watcher := Camera3D.new()
		watcher.fov = 70.0
		studio.add_child(watcher)
		watcher.look_at_from_position(_spectate[0], _spectate[1])
		watcher.make_current()


## Driven on physics ticks, not rendered frames. Captures run with vsync off, so hundreds of
## frames are drawn per tick, and a drag paced by frames was over before the interactor -- which
## reads its button on the physics tick, like every hand -- had looked once.
func _physics_process(_delta: float) -> void:
	_ticks += 1
	if not _drags.is_empty():
		_drive_drag()
	_drive_scripted()
	if _lob.size() == 4 and _ticks == _lob_tick:
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		var hand := studio.get_node_or_null("MouseHand") as MouseInteractor if studio else null
		if hand != null and hand.carrying is Item:
			var from := hand.carry_pose().origin
			var to := Vector3(_lob[0], _lob[1], _lob[2])
			hand.throw_item(ItemRoom.lob(from, to, _lob[3]), Vector3.ZERO)
		_watch_the_throw(studio)
	if _throw.y > 0 and _ticks == int(_throw.y):
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		var hand := studio.get_node_or_null("MouseHand") as MouseInteractor if studio else null
		if hand != null:
			# Aimed at the middle of the view, not wherever the window's cursor was left.
			if hand.pointer_override.x < 0.0 and hand.camera != null:
				hand.pointer_override = hand.camera.get_viewport().get_visible_rect().size * 0.5
			hand.throw_with(_throw.x)
		_watch_the_throw(studio)
	if _shot_tick >= 0 and _ticks == _shot_tick:
		_shot_frame = _frames + 2
		if _quit_tick < 0:
			_quit_after = _frames + 6
	if _quit_tick > 0 and _ticks >= _quit_tick and _ticks > _shot_tick:
		get_tree().quit()


func _drive_drag() -> void:
	var hands := get_tree().root.find_children("*", "MouseInteractor", true, false)
	if hands.is_empty():
		return
	var hand := hands[0] as MouseInteractor
	for drag in _drags:
		var first: int = drag[2]
		var last: int = drag[3]
		if _ticks == last + 1:
			hand.press_override = 0
		if _ticks < first or _ticks > last:
			continue
		var t := float(_ticks - first) / float(maxi(1, last - first))
		hand.pointer_override = (drag[0] as Vector2).lerp(drag[1], t)
		hand.press_override = 1
		if _turn != 0 and _ticks == (first + last) / 2:
			_wheel(hand)


func _wheel(hand: MouseInteractor) -> void:
	for n in absi(_turn):
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP if _turn > 0 else MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = hand.pointer_override
		get_viewport().push_input(wheel)


func _scripted_hand() -> MouseInteractor:
	var hands := get_tree().root.find_children("*", "MouseInteractor", true, false)
	return hands[0] as MouseInteractor if not hands.is_empty() else null


## The control whose title is this -- exactly if one is, else the first that contains it.
func _control_called(title: String) -> ControlAffordance:
	# `_` for a space: SHOT_ARGS is split on whitespace, and titles are "TRACK  CONTROL".
	# `+` joins pieces that must all appear, for titles with a part too awkward to spell in a
	# shell word: LEAD_VOX__REACOMP+POWER finds "LEAD VOX  REACOMP (COCKOS)  POWER".
	title = title.replace("_", " ")
	var pieces := title.to_upper().split("+")
	var loose: ControlAffordance = null
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is ControlAffordance and (n as Node3D).is_visible_in_tree():
			var t: String = (n as ControlAffordance).title()
			if t == title:
				return n
			if loose == null and Array(pieces).all(func(piece): return t.to_upper().contains(piece)):
				loose = n
	return loose


func _screen_of(title: String) -> Vector2:
	var c := _control_called(title)
	var camera := get_viewport().get_camera_3d()
	if c == null or camera == null:
		if c == null:
			push_warning("SHOT: no control called %s" % title)
		return Vector2(-1, -1)
	var centre := c.global_position
	for child in c.get_children():
		if child is CollisionShape3D:
			centre = (child as CollisionShape3D).global_position
			break
	if OS.get_cmdline_user_args().has("--shot-debug"):
		print("SHOT_AIM %s -> %s at %s (world %s, cam-local %s)" % [title, c.get_path(), camera.unproject_position(centre), centre, camera.global_transform.affine_inverse() * centre])
	return camera.unproject_position(centre)


func _drive_scripted() -> void:
	var hand := _scripted_hand()
	if hand == null:
		return
	for click in _clicks:
		if _ticks == click[1]:
			hand.pointer_override = _screen_of(click[0])
			print("SHOT_CLICK %s at %s" % [click[0], hand.pointer_override])
		if _ticks >= click[1] and _ticks < click[1] + 4:
			hand.press_override = 1
		elif _ticks == click[1] + 4:
			hand.press_override = 0
	for pull in _pulls:
		var a: int = pull[2]
		var b: int = pull[3]
		if _ticks == a - 2:
			pull.append(_screen_of(pull[0]))
			hand.pointer_override = pull[4]
		if _ticks >= a and _ticks <= b and pull.size() > 4:
			var t := float(_ticks - a) / float(maxi(1, b - a))
			hand.pointer_override = (pull[4] as Vector2) + (pull[1] as Vector2) * t
			hand.press_override = 1
		elif _ticks == b + 1:
			hand.press_override = 0
