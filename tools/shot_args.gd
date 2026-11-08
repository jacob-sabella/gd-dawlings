class_name ShotArgs
extends RefCounted

## The capture harness's command line: every `--shot`, `--cam`, `--walk` and the rest, parsed once into the
## autoload's fields, and the scene the shot asks to be set up first.
## Moved out of `tools/screenshot.gd` without change of behaviour; the state stays on the autoload, which keeps a one-line delegate for each name another file or a string reaches.

var shot: Screenshot


func _init(of: Screenshot) -> void:
	shot = of


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--shot":
				if i + 1 < args.size(): shot._shot_path = args[i + 1]
			"--shot-frame":
				if i + 1 < args.size(): shot._shot_frame = int(args[i + 1])
			"--quit-after":
				if i + 1 < args.size(): shot._quit_after = int(args[i + 1])
			"--shot-res":
				if i + 1 < args.size(): shot._shot_res = _parse_res(args[i + 1])
			# Where the cursor is, in viewport pixels. The capture window is on a workspace nobody
			# is looking at, so the real mouse is not over it -- and a hover card is only evidence
			# if the same interactor that a person drives produced it. This parks THAT interactor's
			# pointer rather than drawing a card by hand.
			"--hover":
				if i + 1 < args.size():
					var xy := args[i + 1].split(",")
					if xy.size() == 2: shot._hover = Vector2(float(xy[0]), float(xy[1]))
			"--drag":
				if i + 1 < args.size():
					var spec := args[i + 1].split("@")
					var ends := spec[0].split(":")
					if spec.size() == 2 and ends.size() == 2:
						var a := ends[0].split(",")
						var b := ends[1].split(",")
						var f := spec[1].split("-")
						shot._drags.append([Vector2(float(a[0]), float(a[1])),
								Vector2(float(b[0]), float(b[1])), int(f[0]), int(f[1])])
			"--shot-tick":
				if i + 1 < args.size(): shot._shot_tick = int(args[i + 1])
			"--look":
				if i + 1 < args.size():
					var yp := args[i + 1].split(",")
					if yp.size() == 2: shot._look = Vector2(float(yp[0]), float(yp[1]))
			"--aim":
				if i + 1 < args.size(): shot._aim = args[i + 1]
			"--click":
				if i + 1 < args.size():
					var at := args[i + 1].rsplit("@", true, 1)
					if at.size() == 2: shot._clicks.append([at[0], int(at[1])])
			"--pull":
				if i + 1 < args.size():
					var at := args[i + 1].rsplit("@", true, 1)
					var what := at[0].rsplit(":", true, 1)
					if at.size() == 2 and what.size() == 2:
						var by := what[1].split(",")
						var span := at[1].split("-")
						shot._pulls.append([what[0], Vector2(float(by[0]), float(by[1])),
								int(span[0]), int(span[1])])
			"--turn":
				if i + 1 < args.size(): shot._turn = int(args[i + 1])
			"--pockets":
				if i + 1 < args.size(): shot._pockets = args[i + 1].split(",")
			"--carry":
				if i + 1 < args.size(): shot._carry = args[i + 1]
			"--signal":
				if i + 1 < args.size(): shot._signal = args[i + 1].split(",")
			"--on-air":
				if i + 1 < args.size(): shot._on_air = int(args[i + 1])
			"--visitor":
				if i + 1 < args.size(): shot._visitor = Array(args[i + 1].split(",")).map(func(v): return float(v))
			"--point":
				if i + 1 < args.size(): shot._point = args[i + 1]
			"--point-at":
				if i + 1 < args.size():
					var xyz := args[i + 1].split(",")
					if xyz.size() == 3: shot._point_at = Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
			"--note":
				if i + 1 < args.size(): shot._note = args[i + 1]
			"--plug":
				if i + 1 < args.size(): shot._plug = args[i + 1]
			"--fingertips":
				if i + 1 < args.size(): shot._fingertips = int(args[i + 1])
			"--stations":
				if i + 1 < args.size(): shot._stations = int(args[i + 1])
			"--chords":
				if i + 1 < args.size(): shot._chords = int(args[i + 1])
			"--chord-from":
				if i + 1 < args.size(): shot._chord_from = int(args[i + 1])
			"--cassettes":
				if i + 1 < args.size(): shot._cassettes = int(args[i + 1])
			"--test-drum":
				shot._test_drum = true
			"--samples":
				if i + 1 < args.size(): shot._samples = int(args[i + 1])
			"--platter":
				shot._platter = true
			"--pads-demo":
				shot._pads_demo = true
			"--crank":
				if i + 1 < args.size(): shot._crank = int(args[i + 1])
			"--sections":
				if i + 1 < args.size(): shot._sections = int(args[i + 1])
			"--plaque-rows":
				shot._plaque_rows = true
			"--help-page":
				if i + 1 < args.size(): shot._help_page = args[i + 1]
			"--posed-hand":
				if i + 1 < args.size(): shot._posed_hand = Array(args[i + 1].split(",")).map(func(v): return float(v))
			"--rope":
				if i + 1 < args.size(): shot._rope = Array(args[i + 1].split(",")).map(func(v): return float(v))
			"--bead":
				if i + 1 < args.size():
					var at := args[i + 1].rsplit("@", true, 1)
					shot._bead_aim = at[0]
					shot._bead_tick = int(at[1]) if at.size() == 2 else 40
			"--throw":
				if i + 1 < args.size():
					var parts := args[i + 1].split("@")
					shot._throw = Vector2(float(parts[0]), int(parts[1]) if parts.size() > 1 else 200)
			"--lob":
				if i + 1 < args.size():
					var parts := args[i + 1].split("@")
					shot._lob = PackedFloat32Array(Array(parts[0].split(",")).map(func(v): return float(v)))
					shot._lob_tick = int(parts[1]) if parts.size() > 1 else 200
			"--spectate":
				if i + 1 < args.size():
					var ends := args[i + 1].split(":")
					if ends.size() == 2:
						var a := ends[0].split(",")
						var b := ends[1].split(",")
						shot._spectate = [Vector3(float(a[0]), float(a[1]), float(a[2])),
								Vector3(float(b[0]), float(b[1]), float(b[2]))]
			"--walk":
				# "mirror[,distance]": stood in front of the venue's mirror, facing it.
				if i + 1 < args.size() and args[i + 1].begins_with("mirror"):
					var parts := args[i + 1].split(",")
					shot._walk_mirror = float(parts[1]) if parts.size() > 1 else 1.4
				# "rack[,distance[,sideways[,height[,turn]]]]": stood in front of the modular rack wall, facing it square on (along its normal; it leans back),
				# `sideways` and `height` metres along the wall (height from its middle), turned `turn` radians.
				elif i + 1 < args.size() and args[i + 1].begins_with("rack"):
					shot._walk_rack = Array(args[i + 1].split(",")).slice(1).map(func(s): return float(s))
					shot._walk_rack_on = true
				elif i + 1 < args.size(): shot._walk = Array(args[i + 1].split(",")).map(func(s): return float(s))
			"--quit-tick":
				if i + 1 < args.size(): shot._quit_tick = int(args[i + 1])
			"--cam":
				if i + 1 < args.size(): shot._cam = Array(args[i + 1].split(",")).map(func(s): return float(s))
			"--tour":
				if i + 1 < args.size(): shot._tour = args[i + 1]
			"--tl-shelf":
				if i + 1 < args.size(): shot._tl_shelf = args[i + 1]
			"--roll":
				shot._roll = true
			"--rig-roll":
				shot._rig_roll = true
			"--pull-track":
				shot._pull_track = true
			"--pull-tracks":
				if i + 1 < args.size(): shot._pull_tracks = int(args[i + 1])
			"--board":
				if i + 1 < args.size(): shot._board = args[i + 1]
			"--no-timeline":
				shot._no_timeline = true
			"--patch-wall":
				shot._patch_wall = true
			"--patch-graph":
				if i + 1 < args.size():
					shot._patch_graph = int(args[i + 1])
					shot._patch_wall = true
			"--bay-scroll":
				if i + 1 < args.size():
					var rc := args[i + 1].split(",")
					if rc.size() == 2: shot._bay_scroll = Vector2i(int(rc[0]), int(rc[1]))
			"--comfort":
				shot._comfort = true
			"--clip-editor":
				if i + 1 < args.size(): shot._clip_editor = args[i + 1]
			"--input-picker":
				if i + 1 < args.size(): shot._input_picker = int(args[i + 1])
			"--clip-take":
				if i + 1 < args.size(): shot._clip_take = args[i + 1]
			"--clip-span":
				if i + 1 < args.size(): shot._clip_span = float(args[i + 1])
			"--clip-hover":
				if i + 1 < args.size(): shot._clip_hover = args[i + 1]
			"--clip-fade":
				if i + 1 < args.size(): shot._clip_fade = float(args[i + 1])
			"--clip-select":
				if i + 1 < args.size(): shot._clip_select = args[i + 1]
			"--clip-zero":
				shot._clip_zero = true
			"--clip-screen":
				shot._clip_screen = true
			"--tl-select":
				if i + 1 < args.size(): shot._tl_select = args[i + 1]
			"--reopen":
				shot._reopen = true
			"--autosave":
				shot._autosave = true
			"--recover":
				shot._recover = true
			"--tl-xfade":
				if i + 1 < args.size(): shot._tl_xfade = args[i + 1]
			"--tl-fade":
				if i + 1 < args.size(): shot._tl_fade = args[i + 1]
			"--tl-region":
				if i + 1 < args.size(): shot._tl_region = args[i + 1]
			"--tl-group":
				if i + 1 < args.size(): shot._tl_group = args[i + 1]
			"--tl-render":
				shot._tl_render = true
			"--tl-pick":
				if i + 1 < args.size(): shot._tl_pick = int(args[i + 1])
			"--tl-road":
				if i + 1 < args.size(): shot._tl_road = float(args[i + 1])
			"--wheel-take":
				if i + 1 < args.size(): shot._wheel_take = int(args[i + 1])
			"--paste":
				if i + 1 < args.size():
					var at := args[i + 1].split("@")
					var ends := at[0].split(":")
					if at.size() == 2 and ends.size() == 2:
						shot._paste = [int(ends[0]), int(ends[1]), float(at[1])]
			"--ear":
				if i + 1 < args.size(): shot._ear = int(args[i + 1])
			"--tour-band":
				if i + 1 < args.size(): shot._tour_band = int(args[i + 1])
			"--panel":
				if i + 1 < args.size(): shot._panel = args[i + 1]
			"--panel-frame":
				if i + 1 < args.size(): shot._panel_frame = int(args[i + 1])
			"--mod-answer":
				if i + 1 < args.size(): shot._mod_answer = args[i + 1]
			"--mod-answer-frame":
				if i + 1 < args.size(): shot._mod_answer_frame = int(args[i + 1])
			"--make-room":
				if i + 1 < args.size(): shot._make_room = args[i + 1]
			"--rack-patch":
				if i + 1 < args.size(): shot._rack_patch = args[i + 1]
			"--delta":
				if i + 1 < args.size(): shot._delta = args[i + 1]
			"--mod":
				if i + 1 < args.size(): shot._mods.append(args[i + 1])
	shot.scenes.install_files()
	if shot._shot_tick >= 0:
		shot._shot_frame = -1
		shot._quit_after = -1
	if shot._shot_path == "" and shot._quit_after < 0 and shot._shot_tick < 0:
		shot.set_process(false)


func _parse_res(spec: String) -> Vector2i:
	var parts := spec.split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))
