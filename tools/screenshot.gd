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
## `--plug shaker:player_7`: that source's jack stepped into that sink at frame 10, asked as a hand
## here asks (Studio._on_plug_asked; docs/spatial_loop.md slices 5 and 6). With --visitor, a
## jack into `player_7` runs its cable to Lin's ghost.
var _plug := ""
## `--fingertips 5`: the desktop's fingertips turned on at frame 10, as T turns them, with the keys
## of that mask's fingers held down (HandPose's bits: 1 J, 2 K, 4 L, 8 ;), for a shot of the glove
## playing them (docs/spatial_loop.md slice 8).
var _fingertips := -1
## `--stations 2`: I pressed that many times at frame 10, as a desktop player goes to the
## instruments one by one (Studio.cycle_stations).
var _stations := 0
## `--cassettes 3`: that many clips pulled out of the timeline at frame 8, each a cassette shelved
## in the cassette rack, and the rack gone to, for a shot of it holding them (docs/spatial_loop.md
## part two, slice 23).
var _cassettes := 0
## `--samples 2`: at frame 8 the sampler's REC pressed and something carried used that many times
## (the duck squeezed, the tambourine struck, the shaker struck), each a sample cassette on the rack,
## REC pressed once more so it is lit and listening, and the sampler gone to unless SHOT_CAM frames
## it (docs/spatial_loop.md part two, slice 26). Its WAVs go to user://shot_samples, never the project's media.
var _samples := 0
## `--plaque-rows`: after `--stations`, INSTRUMENTS pressed on the plaque of the station gone to,
## at frame 14, for a shot of the board's rows beside it (docs/spatial_loop.md slice 11).
var _plaque_rows := false
## `--help-page LIVE`: the help card open from frame 6 at the first page whose name has that in it
## (`PLAY · LIVE ROOM`).
var _help_page := ""
## `--posed-hand 1.2,1.1,-3.4,0.5,20,1`: a right hand posed (HandPose.posed) at that studio point,
## turned by that yaw (radians), rolled that many degrees right side down, its thumb pinching the
## fingers in that mask (HandPose's bits), from frame 5: reported on a tracker of its own, drawn by
## a HandSkeleton and read by a HandGestures, whose readings are lettered over it
## (docs/spatial_loop.md slice 7). Its index and middle tips strum the harp, as a tracked hand's do.
var _posed_hand: Array = []
var _posed_gestures: HandGestures
var _posed_label: Label3D
## `--harp-bend 20`: with `--posed-hand`, the harp string nearest the hand plucked by it at frame
## HARP_PLUCK_FRAME, at its posed roll, and the hand then tipped that many degrees further over the
## next four frames, so the string rings bent and bows by it (docs/spatial_loop.md part two, slice
## 15). Late, so it still rings at a shot at frame 38 or so: a shot's frames are slow, and the ring
## is ChordHarp.RING of physics time, which catches up.
const HARP_PLUCK_FRAME := 30
var _harp_bend := NAN
var _posed_tracker: XRHandTracker
var _posed_place: Array = []
## `--fist-shake`: with `--posed-hand`, the hand put round the studio's shaker instead, palm down
## over its grip, open at first and closed round it at frame FIST_FRAME, so a bare hand's closed-hand
## hold takes it (XRInteractor.step_hold, read off the posed hand); then lifted FIST_LIFT and swung
## across at 4 Hz, so it plays (docs/spatial_loop.md slice 17). Its yaw and roll still apply.
const FIST_FRAME := 8
const FIST_LIFT := 0.22
var _fist_shake := false
var _fist_hand: XRInteractor
var _posed_curls: Array = [0.15, 0.05, 0.1, 0.35, 0.5]
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
## `--patch-wall`: the audio-device patch wall, hung in the middle of the room, showing this machine's graph.
var _patch_wall := false
## `--comfort`: the session panel open from frame 5 and scrolled to its COMFORT box.
var _comfort := false
## `--no-timeline`: the timeline hidden, for a shot of something it would cover.
var _no_timeline := false
## `--tl-region 9:17:Verse,17:25:Chorus`: regions from bar to bar, made at frame 7.
var _tl_region := ""
## `--tl-group 2:1,3:1`: those tracks put in those groups (track:group), at frame 7.
var _tl_group := ""
## `--reopen`: the project saved and opened again at frame 5, to see what a reopened project draws.
var _reopen := false
## `--autosave`: the transport stopped and an edit at frame 5, and the autosave kept straight
## after, to see what says so.
var _autosave := false
## `--recover`: a copy kept at frame 5 as if by an earlier run, so the RECOVER token offers it.
var _recover := false
## `--tl-fade T:I:S[:shape]`: item I of track T given fades of S seconds at each end, frame 7,
## and with a shape (1: equal power) that shape too.
var _tl_fade := ""
## `--tl-xfade T:I`: item I of track T copied to start halfway along itself, and the two
## crossfaded over the overlap, frame 7.
var _tl_xfade := ""
var _tl_pick := -1
## `--wheel-take 7`: a phrase played on track 7 from a MIDI keyboard at frame 6, through the door a
## real one comes in by (GuestMidi._input), its pitch wheel swept and wobbled and its mod wheel
## raised, recorded to a clock of its own a second past the playhead, and the take selected: the
## thinned controls stand on its block as the timeline draws them (docs/spatial_loop.md slice 14).
var _wheel_take := -1
## `--tl-render`: the deck on its RENDER page, from frame 7.
var _tl_render := false
var _roll := false
var _rig_roll := false
var _board := ""
var _pull_track := false
var _pull_tracks := 0
## `--rope 2,6,0.3`: a rope tied on the stage table at frame 6 from track 2's knot to track 6's
## voice, pulled that far (0..1), and the song played, so the kick's own meter lifts it
## (docs/spatial_loop.md slice 20). How far it ducks at the shot is printed.
var _rope: Array = []
## `--paste 6:4@30`: the first item of track 6 pulled into the mouse hand as a cassette at frame 6,
## the timeline opened round bar 30 with the pointer parked on track 4's lane a third of a beat
## past it, and the mouse pressed there at frame 12, so the take is pasted onto the beat and the
## lanes' card still says what a press pastes (docs/spatial_loop.md part two slice 24).
var _paste: Array = []
## `--ear 6`: the first item of track 6 pulled into the mouse hand as a cassette at frame 6 and held to
## the ear with L at frame 8, so it rides raised beside the view with its tag saying what it is doing
## and the toast what it plays (docs/spatial_loop.md part two slice 25).
var _ear := 0
## `--bead KICK_IN__LEVEL@40`: the song rolling round a loop of BEAD_LOOP seconds from the playhead
## (frame 7), the pointer parked on that control so its write bead shows over it, and on that
## physics tick the bead pressed and dragged up and down in a wave, held to the shot: a pass is
## written at each wrap, and its lane drawn (docs/spatial_loop.md part two slice 22).
var _bead_aim := ""
var _bead_tick := -1
var _bead_from := Vector2(-1, -1)
const BEAD_LOOP := 2.4


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
			"--plug":
				if i + 1 < args.size(): _plug = args[i + 1]
			"--fingertips":
				if i + 1 < args.size(): _fingertips = int(args[i + 1])
			"--stations":
				if i + 1 < args.size(): _stations = int(args[i + 1])
			"--cassettes":
				if i + 1 < args.size(): _cassettes = int(args[i + 1])
			"--samples":
				if i + 1 < args.size(): _samples = int(args[i + 1])
			"--plaque-rows":
				_plaque_rows = true
			"--help-page":
				if i + 1 < args.size(): _help_page = args[i + 1]
			"--harp-bend":
				if i + 1 < args.size(): _harp_bend = float(args[i + 1])
			"--posed-hand":
				if i + 1 < args.size(): _posed_hand = Array(args[i + 1].split(",")).map(func(v): return float(v))
			"--fist-shake":
				_fist_shake = true
			"--rope":
				if i + 1 < args.size(): _rope = Array(args[i + 1].split(",")).map(func(v): return float(v))
			"--bead":
				if i + 1 < args.size():
					var at := args[i + 1].rsplit("@", true, 1)
					_bead_aim = at[0]
					_bead_tick = int(at[1]) if at.size() == 2 else 40
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
			"--no-timeline":
				_no_timeline = true
			"--patch-wall":
				_patch_wall = true
			"--comfort":
				_comfort = true
			"--tl-select":
				if i + 1 < args.size(): _tl_select = args[i + 1]
			"--reopen":
				_reopen = true
			"--autosave":
				_autosave = true
			"--recover":
				_recover = true
			"--tl-xfade":
				if i + 1 < args.size(): _tl_xfade = args[i + 1]
			"--tl-fade":
				if i + 1 < args.size(): _tl_fade = args[i + 1]
			"--tl-region":
				if i + 1 < args.size(): _tl_region = args[i + 1]
			"--tl-group":
				if i + 1 < args.size(): _tl_group = args[i + 1]
			"--tl-render":
				_tl_render = true
			"--tl-pick":
				if i + 1 < args.size(): _tl_pick = int(args[i + 1])
			"--tl-road":
				if i + 1 < args.size(): _tl_road = float(args[i + 1])
			"--wheel-take":
				if i + 1 < args.size(): _wheel_take = int(args[i + 1])
			"--paste":
				if i + 1 < args.size():
					var at := args[i + 1].split("@")
					var ends := at[0].split(":")
					if at.size() == 2 and ends.size() == 2:
						_paste = [int(ends[0]), int(ends[1]), float(at[1])]
			"--ear":
				if i + 1 < args.size(): _ear = int(args[i + 1])
			"--tour-band":
				if i + 1 < args.size(): _tour_band = int(args[i + 1])
	if _shot_tick >= 0:
		_shot_frame = -1
		_quit_after = -1
	if _shot_path == "" and _quit_after < 0 and _shot_tick < 0:
		set_process(false)


## `--posed-hand`'s hand, in the studio's space: a tracker reporting it, its joints drawn, its
## readings read and lettered.
func _pose_a_hand() -> void:
	var studio := get_tree().current_scene.get_node_or_null("Studio") as Node3D
	if studio == null:
		return
	var at := Vector3(_posed_hand[0], _posed_hand[1], _posed_hand[2])
	var yaw: float = _posed_hand[3] if _posed_hand.size() > 3 else 0.0
	var roll: float = _posed_hand[4] if _posed_hand.size() > 4 else 0.0
	var mask := int(_posed_hand[5]) if _posed_hand.size() > 5 else 0
	var tracker_name := &"/user/hand_tracker/shot"
	var shaker := (studio as Studio).items.items.get(&"shaker") as ShakerItem if _fist_shake else null
	if shaker != null:
		at = shaker.grip_point() + Vector3(0, 0.03, 0)
		_posed_curls = [0.0, 0.0, 0.0, 0.0, 0.0]
		print("SHOT_SHAKER grip ", shaker.grip_point())
	var hand := XRHandTracker.new()
	hand.name = tracker_name
	hand.hand = XRPositionalTracker.TRACKER_HAND_RIGHT
	_posed_tracker = hand
	_posed_place = [at, yaw, mask]
	_tip_posed_hand(roll)
	hand.has_tracking_data = true
	XRServer.add_tracker(hand)
	var skeleton := HandSkeleton.new()
	skeleton.name = "PosedHand"
	skeleton.tracker_name = tracker_name
	studio.add_child(skeleton)
	_posed_gestures = HandGestures.new()
	_posed_gestures.name = "PosedHandGestures"
	_posed_gestures.tracker_name = tracker_name
	_posed_gestures.origin = studio
	var camera := get_viewport().get_camera_3d()
	_posed_gestures.head = camera
	studio.add_child(_posed_gestures)
	_posed_label = Label3D.new()
	_posed_label.name = "PosedHandReadings"
	_posed_label.pixel_size = 0.0006
	_posed_label.font_size = 48
	_posed_label.outline_size = 10
	_posed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_posed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_posed_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	studio.add_child(_posed_label)
	if shaker != null:
		# Up close to a shelf: smaller lettering, so the readings sit beside the hand.
		_posed_label.pixel_size = 0.00028
		# A bare hand's pinch ray and closed-hand hold, reading the posed hand, as the rig makes one.
		_fist_hand = XRInteractor.new()
		_fist_hand.name = "PosedFist"
		_fist_hand.gestures = _posed_gestures
		studio.add_child(_fist_hand)


## The posed hand's joints, rolled `roll` degrees and moved `offset`, onto its tracker, every joint
## seen (HandGestures.confident).
func _tip_posed_hand(roll: float, offset := Vector3.ZERO) -> void:
	var palm := Transform3D(Basis(Vector3.UP, _posed_place[1]) * Basis(Vector3.FORWARD, deg_to_rad(roll)),
			_posed_place[0] + offset)
	var joints := HandPose.posed(_posed_curls, int(_posed_place[2]), palm)
	var valid := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID \
			| XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED
	for j in XRHandTracker.HAND_JOINT_MAX:
		_posed_tracker.set_hand_joint_flags(j, valid)
		_posed_tracker.set_hand_joint_radius(j, 0.009)
		_posed_tracker.set_hand_joint_transform(j, Transform3D(Basis.IDENTITY, joints[j]))


## `--rope`'s rope: tied and pulled at frame 6, the song played from the start of the kick's first
## item, and at the shot frame how far it ducks.
## `--cassettes`: a clip off each of the first tracks with one, minted as the host mints a pull
## (the studio's own `_mint_for`), shelved one to a slot from the top left, and the rack gone to.
## Its walk there takes up to two seconds: shoot it at a later frame (`tools/shot.sh out 200 206`).
func _shelve_cassettes() -> void:
	var studio := get_tree().current_scene.get_node_or_null("Studio") as Studio
	if studio == null or studio.items == null or studio.cassette_rack == null:
		return
	var made := 0
	for index in DAW.state.track_indices():
		if made >= _cassettes:
			break
		if DAW.state.track(index).items.is_empty():
			continue
		var item := studio._mint_for(CassetteItem.KIND, "clip:%d:0" % index, Session.local_peer_id)
		if item == null:
			continue
		studio.items.slot_item(item, CassetteRack.RACK, made)
		item.transform = item.resting
		made += 1
	# Where the rack stands and which way its front faces, for a SHOT_CAM framed on its slots.
	var rack := studio.cassette_rack.global_transform
	print("SHOT_CASSETTES ", studio.items.made_ids(), " rack at ", rack.origin, " facing ", rack.basis.z)
	studio.go_to_station(&"cassette_rack")


## `--samples`: REC, then a use, that many times, by the mouse's hand, as a desktop player samples:
## the sampler's own press (Studio._on_rec_pressed) and the item's own use (Item.work).
func _make_samples() -> void:
	var studio := get_tree().current_scene.get_node_or_null("Studio") as Studio
	if studio == null or studio.items == null or studio.sampler == null:
		return
	var dir := ProjectSettings.globalize_path("user://shot_samples")
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	studio.sampler.media_path = func(name: String) -> String: return dir.path_join(name)
	var hand := studio.get_node_or_null("MouseHand") as MouseInteractor
	var kinds: Array[StringName] = [&"duck", &"tambourine", &"shaker"]
	for n in _samples:
		var item: Item = studio.items.items.get(kinds[n % kinds.size()])
		if item == null or hand == null:
			continue
		studio._on_rec_pressed(true)
		hand.pick_up(item)
		item.work(true)
		item.work(false)
		hand.lose_carrying()
		item.snap_home()
	studio._on_rec_pressed(true)
	var at := studio.sampler.global_transform
	print("SHOT_SAMPLES ", studio.items.made_ids(), " sampler at ", at.origin, " facing ", at.basis.z,
			" rack at ", studio.cassette_rack.global_position if studio.cassette_rack != null else Vector3.ZERO)
	# Framed by SHOT_CAM, it stays framed there, the rack beside it in the shot too, and the room is
	# the picture: the toasts it said are let go.
	if _cam.size() != 6:
		studio.go_to_station(&"sampler")
		return
	var panel := get_tree().current_scene.find_child("SessionPanel", true, false) as SessionPanel
	if panel != null and panel._toasts != null:
		for card in panel._toasts.get_children():
			card.free()


func _tie_the_rope() -> void:
	var studio := get_tree().current_scene.get_node_or_null("Studio") as Studio
	var table: StageTable = studio.stage if studio != null else null
	if table == null:
		return
	var from := int(_rope[0])
	var to := int(_rope[1])
	if _frames == 6:
		if Sidechain.key_send(from, to) == 0:
			table.tie(from, to)
		if _rope.size() > 2:
			table.pull(from, to, float(_rope[2]))
		var t := DAW.state.track(from, false)
		if t != null and not t.items.is_empty():
			DAW.seek((t.items[0] as MixState.ItemState).start)
		DAW.transport_play()
	if _frames == _shot_frame:
		var rope: StageTable.Rope = table.rope_nodes.get(Sidechain.rope_key(from, to))
		if rope != null:
			var camera := get_viewport().get_camera_3d()
			print("SHOT_ROPE ducking %.1f dB, lifted %.3f m, its middle at %s on screen: %s" % [rope.ducking, rope.lifted,
					camera.unproject_position(rope.global_position) if camera != null else Vector2.ZERO, rope.readout()])


## `--harp-bend`: the string nearest the posed hand plucked by it, at HARP_PLUCK_FRAME; then the hand
## tipped further, a quarter of the way a frame.
func _bend_the_harp() -> void:
	var studio := get_tree().current_scene.get_node_or_null("Studio")
	var harp: ChordHarp = studio.get("harp") if studio != null else null
	if harp == null or _posed_tracker == null:
		return
	var roll: float = _posed_hand[4] if _posed_hand.size() > 4 else 0.0
	if _frames == HARP_PLUCK_FRAME:
		var x := harp.to_local(_posed_place[0] as Vector3).x
		harp.pluck([ChordHarp.nearest(x)], 96, _posed_gestures)
	elif _frames > HARP_PLUCK_FRAME:
		_tip_posed_hand(roll + _harp_bend * clampf((_frames - HARP_PLUCK_FRAME) / 4.0, 0.0, 1.0))
	if OS.get_cmdline_user_args().has("--shot-debug"):
		print("HARP_BEND frame %d at %d ms: ringing %s, wheel %s, engaged %s, %.2f st" % [_frames,
				Time.get_ticks_msec(), harp.ringing(), harp.keys.wheel_source() if harp.keys != null else "-",
				harp.wobble != null and harp.wobble.engaged(), harp.wobble.semitones if harp.wobble != null else 0.0])


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

	if _frames == 5 and _no_timeline:
		for hidden in get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false):
			hidden.visible = false

	if _frames >= 5 and _frames <= 12 and _comfort:
		var panel := get_tree().current_scene.find_child("SessionPanel", true, false) as SessionPanel
		if panel != null:
			if not panel.is_open():
				panel.open()
			var box := panel.find_child("Comfort", true, false) as Control
			if box != null:
				panel._scroll.ensure_control_visible(box)
				if _frames == 12:
					print("SHOT_COMFORT %s motion=%.1f room_reacts=%s lift_on_clip=%s" % [box.get_global_rect(),
							Ergonomics.current.motion_scale, Ergonomics.current.room_reacts, Ergonomics.current.lift_on_clip])

	if _frames == 3 and _patch_wall:
		var wall := PatchWallSurface.new()
		wall.position = Vector3(0, 2.2, 1.0)
		get_tree().current_scene.add_child(wall)
		for hidden in get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false):
			hidden.visible = false

	if _frames == 6 and _tl_shelf != "":
		var tl := get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false)
		if not tl.is_empty():
			(tl[0] as TimelineSurface).set_shelf(_tl_shelf == "on")
			print("SHOT_TL shelf=", (tl[0] as TimelineSurface).shelf)
		else:
			print("SHOT_TL none found")

	if _rope.size() >= 2:
		_tie_the_rope()
	if _frames == 6 and _wheel_take > 0:
		_play_wheel_take(_wheel_take)
	if _paste.size() == 3:
		_paste_a_cassette()
	if _ear > 0:
		_hold_a_cassette_to_the_ear()
	if _frames == 6 and _tl_road >= 0.0:
		var tl := get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false)
		if not tl.is_empty():
			DAW.seek(_tl_road)
			(tl[0] as TimelineSurface).set_highway(true)
	if _frames == 7 and _tl_render:
		for tl in get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false):
			(tl as TimelineSurface).deck.show_page((tl as TimelineSurface).render_page)
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
	if _frames == 5 and _autosave:
		OfflineBackend.autosave_every = 0.001
		DAW.set_track_volume(3, 0.3)
		# Held while the song plays: stopped, so it is kept at once.
		DAW.transport_stop()
	if _frames == 5 and _recover:
		DAW.backend.autosave()
		DAW.backend.set(&"_settled_copy", "")
		DAW.project_replaced.emit()
	if _frames == 5 and _reopen:
		var path := ProjectSettings.globalize_path("user://shot_reopen.dawproject")
		print("SHOT_REOPEN ", DAW.save_project_as(path), DAW.open_project(path))
	if _frames == 7 and _tl_xfade != "":
		var x := _tl_xfade.split(":")
		var it: MixState.ItemState = DAW.state.item(int(x[0]), int(x[1])) if x.size() == 2 else null
		if it != null:
			var at := it.start + it.length * 0.5
			DAW.select_item(int(x[0]), int(x[1]), false)
			DAW.copy_selected_to(at)
			DAW.clear_item_selection()
			var items: Array = DAW.state.track(int(x[0])).items
			for k in items.size():
				if is_equal_approx(items[k].start, at):
					DAW.crossfade_items(int(x[0]), int(x[1]), k)
	if _frames == 7 and _tl_fade != "":
		var f := _tl_fade.split(":")
		if f.size() >= 3:
			DAW.set_item_fades(int(f[0]), int(f[1]), float(f[2]), float(f[2]))
		if f.size() == 4:
			# A shape for both ends, or "in/out".
			var shapes := f[3].split("/")
			DAW.set_item_fade_shape(int(f[0]), int(f[1]), int(shapes[0]), int(shapes[-1]))
	if _frames == 7 and _tl_group != "":
		for spec in _tl_group.split(",", false):
			var g := spec.split(":")
			if g.size() == 2:
				DAW.set_track_group(int(g[0]), int(g[1]))
	if _frames == 7 and _tl_region != "":
		for spec in _tl_region.split(",", false):
			var r := spec.split(":")
			if r.size() == 3:
				DAW.add_region(DAW.state.bar_to_seconds(float(r[0])), DAW.state.bar_to_seconds(float(r[1])), r[2])
	if _frames == 7 and _roll:
		DAW.transport_play()
	if _frames == 7 and _bead_aim != "":
		var from := DAW.state.position_seconds
		DAW.set_loop_range(from, from + BEAD_LOOP)
		DAW.set_looping(true)
		DAW.transport_play()
		# The timeline zoomed onto the loop, so the passes are drawn wide enough to see.
		var studio := get_tree().current_scene.get_node_or_null("Studio")
		if studio != null and studio.get("timeline") != null:
			(studio.timeline as TimelineSurface).set_view(maxf(from - 0.3, 0.0), BEAD_LOOP + 0.6)
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

	if _frames == 5 and _posed_hand.size() >= 3:
		_pose_a_hand()
	if _frames >= HARP_PLUCK_FRAME and not is_nan(_harp_bend):
		_bend_the_harp()
	if _fist_hand != null and is_instance_valid(_fist_hand) and _frames >= FIST_FRAME:
		# Closed round it, then up and shaken across at 4 Hz.
		_posed_curls = [0.5, 0.8, 0.8, 0.8, 0.8]
		var lifted := clampf((_frames - FIST_FRAME - 2) / 6.0, 0.0, 1.0) * FIST_LIFT
		var swing := 0.03 * sin(TAU * 4.0 * Time.get_ticks_msec() / 1000.0) if _frames > FIST_FRAME + 8 else 0.0
		_tip_posed_hand(_posed_hand[4] if _posed_hand.size() > 4 else 0.0, Vector3(swing, lifted, 0))
	if _posed_gestures != null and is_instance_valid(_posed_gestures):
		_posed_label.text = _posed_gestures.describe()
		if _fist_hand != null and is_instance_valid(_fist_hand) and _fist_hand.fist_holding:
			_posed_label.text += "\nHOLDING %s, CLOSED HAND" % (_fist_hand.carrying as Item).item_title()
		var studio_harp: ChordHarp = get_tree().current_scene.get_node_or_null("Studio").get("harp") \
				if get_tree().current_scene.get_node_or_null("Studio") != null else null
		if studio_harp != null and studio_harp.wobble != null and studio_harp.wobble.engaged():
			_posed_label.text += "\nBEND %s semitones" % Wobble.words(studio_harp.wobble.semitones)
		if _posed_gestures.tracked:
			_posed_label.global_position = _posed_gestures.joints[HandPose.PALM] + Vector3(0, 0.16, 0)

	if _frames == 8 and _cassettes > 0:
		_shelve_cassettes()
	if _frames == 8 and _samples > 0:
		_make_samples()
	if _frames == 10 and _stations > 0:
		var going := get_tree().current_scene.get_node_or_null("Studio")
		if going != null and going.has_method("cycle_stations"):
			for n in _stations:
				print("SHOT_STATION ", going.cycle_stations(1))
	if _frames == 14 and _plaque_rows:
		var at := get_tree().current_scene.get_node_or_null("Studio") as Studio
		if at != null and at.venue != null:
			for key in at.venue.find_children("Instruments", "", true, false):
				if key is StationBoard.PlaqueKey and key.station == at.station:
					var hand := Node.new()
					key.grab_begin(hand, key.global_position)
					key.grab_end(hand)
					hand.free()
					print("SHOT_PLAQUE_ROWS ", at.station)
	if _frames == 6 and _help_page != "":
		var card := get_tree().current_scene.get_node_or_null("Welcome") as WelcomeCard
		if card != null:
			var at := 0
			for n in card.page_names().size():
				if card.page_names()[n].contains(_help_page.to_upper()):
					at = n
					break
			card.page = at
			card.open()
			print("SHOT_HELP %s of %s" % [card.page, card.page_names()])
	if _frames == 10 and _fingertips >= 0:
		var tips_studio := get_tree().current_scene.get_node_or_null("Studio")
		if tips_studio != null and tips_studio.has_method("toggle_fingertips"):
			tips_studio.toggle_fingertips()
			var keys: KeyCatcher = tips_studio.fingertip_keys
			for physical in KeyCatcher.FINGERS:
				if _fingertips & HandPose.FINGER_BITS[KeyCatcher.FINGERS[physical]]:
					keys.handle(physical, true)
	if _frames == 10 and _plug.contains(":"):
		var plug_studio := get_tree().current_scene.get_node_or_null("Studio")
		if plug_studio != null and plug_studio.has_method("_on_plug_asked"):
			var ends := _plug.split(":")
			plug_studio._on_plug_asked(StringName(ends[0]), StringName(ends[1]))

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

	if _bead_aim != "" and _scripted_hand() != null and _ticks > 2 and _ticks < _bead_tick:
		var on := _screen_of(_bead_aim)
		if on.x >= 0.0:
			_hover = on
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
	_drive_bead()
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


## `--bead`: on its tick the shown bead's place on the screen, and from two ticks on the button
## down on it and the pointer up and down from there, 70 px each way every 1.2 s, drifting down.
func _drive_bead() -> void:
	var hand := _scripted_hand()
	if hand == null or _bead_aim == "" or _ticks < _bead_tick:
		return
	var camera := get_viewport().get_camera_3d()
	if _ticks == _bead_tick:
		if hand.bead != null and hand.bead.shown() and camera != null:
			_bead_from = camera.unproject_position(hand.bead.global_position)
			hand.pointer_override = _bead_from
			_hover = _bead_from
			print("SHOT_BEAD over %s at %s" % [hand.bead.control.title(), _bead_from])
		else:
			push_warning("SHOT: no bead shown over %s" % _bead_aim)
		return
	if _bead_from.x < 0.0:
		return
	var t := float(_ticks - _bead_tick - 2) / 60.0
	hand.pointer_override = _bead_from + Vector2(0, -70.0 * sin(TAU * t / 1.2) + 50.0 * minf(t, 1.0))
	hand.press_override = 1 if _ticks >= _bead_tick + 2 else 0


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


## `--paste`: a cassette pulled at frame 6, the pointer parked on the lane it goes on, and the press.
func _paste_a_cassette() -> void:
	var studio := get_tree().current_scene.get_node_or_null("Studio") as Studio
	var mouse := _scripted_hand()
	if studio == null or mouse == null or studio.timeline == null:
		return
	var s := DAW.state
	var bar_at := s.bar_to_seconds(float(_paste[2]))
	if _frames == 6:
		studio._on_clip_pulled(int(_paste[0]), 0, mouse)
		studio.timeline.set_view(s.bar_to_seconds(float(_paste[2]) - 2.0), s.bar_to_seconds(float(_paste[2]) + 6.0) - s.bar_to_seconds(float(_paste[2]) - 2.0))
	if _frames == 9:
		var timeline: TimelineSurface = studio.timeline
		var i := s.track_indices().find(int(_paste[1]))
		var raw := s.seconds_at_beat(s.beat_at(bar_at) + 0.35)
		var point := timeline.to_global(Vector3(timeline._x_for(raw), timeline._lane_y[i], timeline._lanes.position.z))
		_hover = get_viewport().get_camera_3d().unproject_position(point)
		mouse.pointer_override = _hover
		print("SHOT_PASTE carrying %s, pointer at %s" % [mouse.carrying.item_title() if mouse.carrying != null else "nothing", _hover])
	if _frames == 12:
		mouse.press_override = 1
	if _frames == 15:
		mouse.press_override = 0
		var pasted: Array = s.track(int(_paste[1])).items.filter(func(it): return is_equal_approx(it.start, bar_at))
		print("SHOT_PASTE pasted %d onto track %d at %s; the lanes say: %s" % [pasted.size(), _paste[1], s.bar_beat(bar_at), studio.timeline._lanes.card_hint()])


## `--ear`: a cassette pulled at frame 6 and held to the ear with L at frame 8.
func _hold_a_cassette_to_the_ear() -> void:
	var studio := get_tree().current_scene.get_node_or_null("Studio") as Studio
	var mouse := _scripted_hand()
	if studio == null or mouse == null:
		return
	if _frames == 6:
		studio._on_clip_pulled(_ear, 0, mouse)
	if _frames == 8:
		mouse.ear_held = true
	if _frames == 238:
		print("SHOT_EAR %s: %s (%s)" % [mouse.carrying.item_title() if mouse.carrying != null else "nothing",
				EarCue.Hearing.keys()[studio.ear.hearing], studio.ear.tag()])


## `--wheel-take`: a phrase on `track` from a MIDI keyboard, wheels and all, taken down and selected.
func _play_wheel_take(track: int) -> void:
	var gm := Session.guest_midi
	var start := DAW.state.position_seconds + 1.0
	var now := {"seconds": start, "playing": true, "recording": true, "valid": true}
	gm.heard_source = func() -> Dictionary: return now.duplicate()
	gm.target_track = track
	gm.follow(now)
	var midi := func(message: int, a: int, b: int) -> void:
		var e := InputEventMIDI.new()
		e.message = message
		e.pitch = a
		e.velocity = b
		e.controller_number = a
		e.controller_value = b
		gm._input(e)
	# A note bent up a whole tone over 0.6 s and held there.
	midi.call(MIDI_MESSAGE_NOTE_ON, 60, 100)
	for i in 37:
		now["seconds"] = start + 0.1 + i / 60.0
		midi.call(MIDI_MESSAGE_PITCH_BEND, 8192 + roundi(8191.0 * sin(PI / 2.0 * i / 36.0)), 0)
	now["seconds"] = start + 1.4
	midi.call(MIDI_MESSAGE_NOTE_OFF, 60, 0)
	# A second, wobbled at 5 Hz with the mod wheel coming up under it.
	now["seconds"] = start + 1.7
	midi.call(MIDI_MESSAGE_NOTE_ON, 64, 100)
	for i in 90:
		now["seconds"] = start + 1.8 + i / 60.0
		midi.call(MIDI_MESSAGE_PITCH_BEND, 8192 + roundi(2048.0 * sin(TAU * 5.0 * i / 60.0)), 0)
		if i % 6 == 0:
			midi.call(MIDI_MESSAGE_CONTROL_CHANGE, 1, i)
	now["seconds"] = start + 3.4
	midi.call(MIDI_MESSAGE_NOTE_OFF, 64, 0)
	now["seconds"] = start + 3.8
	gm.follow(now)
	now["recording"] = false
	gm.follow(now)
	gm.heard_source = Callable()
	gm.target_track = 0
	var items: Array = DAW.state.track(track).items
	for k in items.size():
		if is_equal_approx(items[k].start, start):
			DAW.select_item(track, k, false)
	# The take filling the timeline's window, so its posts can be told apart.
	for tl in get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false):
		(tl as TimelineSurface).set_view(start - 0.4, 4.6)
		(tl as TimelineSurface).set_size((tl as TimelineSurface).width_scale, TimelineSurface.LANE_HEIGHT_MAX)
	print("SHOT_WHEEL_TAKE ", gm.last_take)
