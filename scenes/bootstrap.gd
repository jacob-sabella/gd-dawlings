extends Node

## Entry point. Decides what kind of participant this launch is, then builds the studio.
##
## Everything here is a command-line switch rather than a menu, because the first thing this
## project needs to be is scriptable: a hybrid session is tested by launching four of these at
## once with different flags, and a screenshot is taken by launching one with a camera position.
## A launcher UI is worth building once the arrangement it launches has stopped changing daily.
##
##   godot --path .                                      offline stand-in, screen participant
##   godot --path . -- --reaper                          host, OSC to a local Reaper
##   godot --path . -- --reaper --host                   host, and open the session to peers
##   godot --path . -- --join 192.168.1.40 --xr --ar     join someone else's session, in passthrough
##   godot --path . -- --place console=screen --stage    console as a panel, with the mover open
##
## Ports default to Reaper's own OSC defaults: send to 8000, listen on 9000. They are the numbers
## in Reaper's own OSC device dialog, so a mismatch here is the first thing to check when the
## link stays silent -- see docs/transport.md.

const DEFAULT_SEND_PORT := 8000
const DEFAULT_LISTEN_PORT := 9000

var studio: Studio
var xr := XRBootstrap.new()

var _hud: Label


func _ready() -> void:
	var args := _parse(OS.get_cmdline_user_args())

	add_child(xr)
	var medium := xr.start(args["xr"], args["ar"])
	# A capture or a demo starts from the authored room and keeps whatever it moves to itself.
	# Without this, a screenshot that pushed a rack would move the rack in the real layout.
	if args["fresh_layout"]:
		Session.layout.save_path = "user://scratch_layout.cfg"
	else:
		Session.layout.load_saved()
	Session.layout.medium = medium

	if args["join"] != "":
		Session.join(args["join"])
		# A guest still has a backend: it holds the replicated cache. It just never opens a
		# link of its own, which is the whole of what "one link per session" means.
		DAW.use(OfflineBackend.new(), false)
	elif args["host"]:
		Session.host()
		_start_daw(args)
	else:
		Session.start_solo()
		_start_daw(args)

	studio = Studio.new()
	studio.name = "Studio"
	# Both set before the studio enters the tree: _ready() builds the whole room off the medium,
	# and it only gets one chance to do it.
	studio.medium = medium
	studio.xr_bootstrap = xr
	# The body before the room, so nothing is ever built for the wrong one and then corrected.
	var vision := String(args["vision"]).to_upper()
	if not vision.is_empty():
		if Ergonomics.ColourVision.has(vision):
			studio.ergonomics.colour_vision = Ergonomics.ColourVision[vision]
		else:
			push_warning("bootstrap: --vision %s is not one of %s"
					% [vision, Ergonomics.ColourVision.keys()])
	if args["step"] > 0.0:
		studio.ergonomics.step = args["step"]
	if args["dwell"] > 0.0:
		studio.ergonomics.dwell_seconds = args["dwell"]
	if args["no_motion"]:
		studio.ergonomics.motion_scale = 0.0
	if args["seated"]:
		studio.ergonomics = Ergonomics.seated_default()
	if args["eyes"] > 0.0:
		studio.ergonomics.text_scale = args["eyes"]
	Ergonomics.current = studio.ergonomics
	add_child(studio)

	if args["venue"] != "":
		if Venue.is_known(StringName(args["venue"])):
			studio.set_venue(StringName(args["venue"]), false)
		else:
			push_warning("bootstrap: --venue %s is not one of %s" % [args["venue"], Venue.IDS])

	_build_hud()

	_apply_cli_placement(args["place"])
	_apply_cli_focus(args["focus"])
	if args["detach_body"] and studio.body != null:
		# After one frame, so the rig has taken its pose from the head before it is cut loose.
		studio.body._process(0.0)
		studio.body.detach()
	var loop: Vector2 = args["loop"]
	if loop.y > loop.x:
		DAW.set_loop_range(DAW.state.bar_to_seconds(loop.x), DAW.state.bar_to_seconds(loop.y))
		DAW.set_looping(true)
	var view: Vector2 = args["view"]
	if view.y > 0.0 and studio.timeline != null:
		studio.timeline.set_view(view.x, view.y)

	var stage := StageManager.new()
	stage.name = "StageManager"
	stage.mount = studio.mount
	stage.studio = studio
	add_child(stage)
	if args["stage"]:
		stage.open()


## The backend is started BEFORE the studio is built, and the order matters: surfaces build
## themselves from whatever is in the state cache, so a studio built first would come up as an
## empty room and rebuild a frame later. Cosmetic in a desktop launch and not cosmetic in a
## headset, where a frame of empty room at startup is a frame of nothing where the console is.
func _start_daw(args: Dictionary) -> void:
	if args["reaper"]:
		var options := {
			"host": args["reaper_host"],
			"send_port": args["send_port"],
			"listen_port": args["listen_port"],
		}
		if args["reaper_resource"] != "":
			options["bridge_dir"] = args["reaper_resource"].path_join("Scripts/reaper3d_bridge_data")
		if DAW.use(ReaperBackend.new(), true, options):
			return
		push_warning("bootstrap: could not open the OSC link; falling back to the offline stand-in.")
	var offline := OfflineBackend.new()
	offline.track_count = args["tracks"]
	DAW.use(offline)


func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {
		"reaper": false, "reaper_host": "127.0.0.1",
		"send_port": DEFAULT_SEND_PORT, "listen_port": DEFAULT_LISTEN_PORT,
		"host": false, "join": "", "xr": false, "ar": false,
		"place": {}, "stage": false, "view": Vector2.ZERO, "tracks": 0,
		"focus": "", "fresh_layout": false, "detach_body": false, "no_motion": false, "vision": "", "dwell": 0.0, "step": 0.0, "eyes": 0.0, "seated": false,
		"venue": "", "reaper_resource": "", "loop": Vector2.ZERO,
	}
	var i := 0
	while i < argv.size():
		match argv[i]:
			"--tracks":
				# Pads the offline stand-in out to N tracks. Only the stand-in: with --reaper
				# the project is whatever Reaper has open, and inventing tracks on top of a
				# real session would be a lie told to the measuring tool.
				i += 1
				if i < argv.size():
					out["tracks"] = int(argv[i])
			"--focus":
				# `--focus rack`. Same reason as --place: the summoned arrangement is the
				# whole claim this feature makes and it cannot be photographed by hand.
				i += 1
				if i < argv.size():
					out["focus"] = argv[i]
			"--eyes":
				# `--eyes 2.0` -- this reader needs twice the angular cap height. The one
				# switch that proves the accessibility work is real rather than declared:
				# everything in the room has to get closer, not merely larger.
				i += 1
				if i < argv.size():
					out["eyes"] = float(argv[i])
			"--reaper-resource":
				# The resource path of a Reaper that is not the default one -- the live rig's,
				# or a portable install. Implies --reaper.
				i += 1
				if i < argv.size():
					out["reaper_resource"] = argv[i]
					out["reaper"] = true
			"--venue":
				# `--venue grid`. For one run: a look asked for on the command line is not a
				# change of mind, so it is not written to the layout.
				i += 1
				if i < argv.size():
					out["venue"] = argv[i]
			"--fresh-layout": out["fresh_layout"] = true
			"--seated": out["seated"] = true
			"--detach-body": out["detach_body"] = true
			"--no-motion": out["no_motion"] = true
			"--step":
				i += 1
				if i < argv.size():
					out["step"] = float(argv[i])
			"--dwell":
				i += 1
				if i < argv.size():
					out["dwell"] = float(argv[i])
			"--vision":
				i += 1
				if i < argv.size():
					out["vision"] = argv[i]
			"--reaper": out["reaper"] = true
			"--host": out["host"] = true
			"--xr": out["xr"] = true
			"--stage": out["stage"] = true
			"--view":
				# `--view 32:64` -- start and span in seconds, for photographing the timeline
				# at a zoom. Same reason as --place: a view you have to drag your way into
				# cannot be captured reproducibly.
				i += 1
				if i < argv.size():
					var window := argv[i].split(":")
					if window.size() == 2:
						out["view"] = Vector2(float(window[0]), float(window[1]))
			"--loop":
				# `--loop 9:17` -- loop bars 9 to 17 and switch looping on. For photographing the
				# loop and for starting a session already looping the section being worked on.
				i += 1
				if i < argv.size():
					var bars := argv[i].split(":")
					if bars.size() == 2:
						out["loop"] = Vector2(float(bars[0]), float(bars[1]))
			"--place":
				# `--place console=screen`. Scriptable for the same reason everything else here
				# is a switch: a hybrid arrangement is tested by launching several of these at
				# once, and a layout you have to click your way into cannot be screenshotted.
				i += 1
				if i < argv.size():
					var pair := argv[i].split("=")
					if pair.size() == 2:
						out["place"][StringName(pair[0])] = pair[1]
			"--ar":
				out["xr"] = true
				out["ar"] = true
			"--join":
				i += 1
				if i < argv.size():
					out["join"] = argv[i]
			"--reaper-host":
				i += 1
				if i < argv.size():
					out["reaper_host"] = argv[i]
					out["reaper"] = true
			"--send-port":
				i += 1
				if i < argv.size():
					out["send_port"] = int(argv[i])
			"--listen-port":
				i += 1
				if i < argv.size():
					out["listen_port"] = int(argv[i])
		i += 1
	return out


## Named modes rather than numbers on the command line, because `--place console=2` is a thing
## nobody can read back a week later. An unknown name is reported rather than ignored: a typo
## that silently leaves the console where it was looks exactly like the feature not working.
func _apply_cli_placement(places: Dictionary) -> void:
	for id in places:
		var wanted := String(places[id])
		var mode := -1
		for candidate in Presentation.MODE_NAMES:
			if Presentation.MODE_NAMES[candidate] == wanted:
				mode = candidate
		if mode < 0:
			push_warning("bootstrap: --place %s=%s is not one of %s" % [id, wanted, Presentation.MODE_NAMES.values()])
			continue
		studio.mount.set_mode(id, mode)


## Snapped rather than glided, and the distinction is not a detail. The glide exists so that a
## surface arriving at your hands reads as having travelled there; a surface that was ALWAYS
## there has not travelled, and animating it in at startup says something untrue about where it
## came from. It also meant every screenshot of a focused surface caught it in flight -- the
## first `--focus rack` render was the rack still sitting in the room, photographed from behind.
func _apply_cli_focus(wanted: String) -> void:
	if wanted.is_empty():
		return
	if studio.focus == null:
		# Loud, because the silent version of this cost an afternoon: --focus did nothing, every
		# screenshot came back as an untouched room, and the renders were read as a placement bug
		# in the maths rather than as the rig never having been asked.
		push_warning("bootstrap: --focus %s ignored, this studio has no focus rig" % wanted)
		return
	for surface in studio.focus.surfaces:
		if String(surface.surface_id) == wanted:
			var motion: float = studio.ergonomics.motion_scale
			studio.ergonomics.motion_scale = 0.0
			studio.focus.focus(surface.surface_id)
			studio.ergonomics.motion_scale = motion
			# Same as pressing F: summoning gear to the mix position and leaving the camera
			# across the room shows you the back of it. See studio._sit_down.
			studio._sit_down()
			return
	push_warning("bootstrap: --focus %s is not one of %s" % [wanted,
			studio.focus.surfaces.map(func(s): return String(s.surface_id))])


## A corner readout of what this participant actually is. It exists because every failure mode of
## this project looks identical from the inside: a silent OSC port, a guest that thinks it is a
## host, and an uncalibrated room all render as a perfectly normal studio.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	_hud.add_theme_font_size_override("font_size", 13)
	# Outlined, because some venues put a sunset behind it.
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_theme_constant_override("outline_size", 5)
	layer.add_child(_hud)
	set_process(true)


func _process(_delta: float) -> void:
	if _hud == null:
		return
	var role_name: String = ["solo", "host", "guest"][Session.role]
	var medium_name: String = ["screen", "ar", "vr"][Session.layout.medium]
	_hud.text = "reaper-3d  |  %s / %s  |  %s  |  %d track(s)  |  F focus / shift-F back / esc release  |  G bring gear to you  |  WASD walk / shift run / space jump / right-drag look  |  N %s  |  V venue: %s  |  E expand desk  |  +/- text size  |  tab move gear  |  drag stands to roll them" % [
		role_name, medium_name, DAW.summary(), DAW.state.tracks.size(),
		"god mode" if studio.god_mode else "walking",
		studio.venue.title() if studio.venue != null else "room"]
