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
	add_child(studio)

	_build_hud()

	_apply_cli_placement(args["place"])
	var view: Vector2 = args["view"]
	if view.y > 0.0 and studio.timeline != null:
		studio.timeline.set_view(view.x, view.y)

	var stage := StageManager.new()
	stage.name = "StageManager"
	stage.mount = studio.mount
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
		if DAW.use(ReaperBackend.new(), true, options):
			return
		push_warning("bootstrap: could not open the OSC link; falling back to the offline stand-in.")
	DAW.use(OfflineBackend.new())


func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {
		"reaper": false, "reaper_host": "127.0.0.1",
		"send_port": DEFAULT_SEND_PORT, "listen_port": DEFAULT_LISTEN_PORT,
		"host": false, "join": "", "xr": false, "ar": false,
		"place": {}, "stage": false, "view": Vector2.ZERO,
	}
	var i := 0
	while i < argv.size():
		match argv[i]:
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
	layer.add_child(_hud)
	set_process(true)


func _process(_delta: float) -> void:
	if _hud == null:
		return
	var role_name: String = ["solo", "host", "guest"][Session.role]
	var medium_name: String = ["screen", "ar", "vr"][Session.layout.medium]
	_hud.text = "reaper-3d  |  %s / %s  |  %s  |  %d track(s)  |  right-drag orbit, wheel zoom, WASD walk, tab to move gear" % [
		role_name, medium_name, DAW.summary(), DAW.state.tracks.size()]
