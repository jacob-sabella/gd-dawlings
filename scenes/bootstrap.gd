extends Node

## Entry point. Decides what kind of participant this launch is, then builds the studio.
##
## Everything here is a command-line switch rather than a menu, because the first thing this
## project needs to be is scriptable: a hybrid session is tested by launching four of these at
## once with different flags, and a screenshot is taken by launching one with a camera position.
## A launcher UI is worth building once the arrangement it launches has stopped changing daily.
##
##   godot --path .                                      offline stand-in, screen participant
##   godot --path . -- --built-in                         the built-in DAW: Godot's own audio
##                                                        (the default in an exported build;
##                                                        --stand-in there for the silent mix)
##   godot --path . -- --reaper                          host, OSC to a local Reaper
##   godot --path . -- --reaper --host                   host, and open the session to peers
##   godot --path . -- --reaper --host --code AB12       host, letting in only those told AB12
##   godot --path . -- --host --public --code AB12       and open it to the internet: the router
##                                                        forwards the ports (UPnP), the session
##                                                        panel shows the public address
##   godot --path . -- --join 192.168.1.40 --xr --ar     join someone else's session, in passthrough
##   godot --path . -- --xr-sim [--ar]                   a simulated headset on the desktop (no hardware)
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
var session_panel: SessionPanel


## The app's named audio streams, where they opened.
var ports: AudioPorts


func _ready() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	Materials.prefetch_startup()

	add_child(xr)
	var medium := xr.start(args["xr"], args["ar"], args["xr_sim"])
	# A capture or a demo starts from the authored room and keeps whatever it moves to itself.
	# Without this, a screenshot that pushed a rack would move the rack in the real layout.
	if args["fresh_layout"]:
		Session.layout.save_path = "user://scratch_layout.cfg"
		# Nor does it dress your ghost: whatever a capture puts on stays in that capture.
		Session.look_path = ""
	else:
		Session.layout.load_saved()
	Session.layout.medium = medium

	if args["name"] != "":
		Session.local_name = args["name"]
	if not args["ghost"].is_empty():
		Session.look_path = ""
		Session.local_look = GhostLook.clean(args["ghost"])
	# How this process gets its own mix back after being someone else's guest: the same link
	# it would have opened on its own, Reaper or the stand-in.
	Session.solo_backend = func(): _start_daw(args)
	# What a host passes on to its guests' ears: the DAW's own output where there is a DAW,
	# a test tone where asked for one, and silence on the offline stand-in, which has none.
	Session.mix_source = func() -> MixSource:
		if args["mix_tone"]:
			return MixSource.Tone.new()
		if DAW.backend is GodotBackend:
			return (DAW.backend as GodotBackend).mix_source()
		if not args["reaper"] and args["mix_from"] == "":
			return MixSource.new()
		var tapped := MixTap.open(args["mix_from"])
		if not MixTap.why_not.is_empty():
			# Said where the host will see it: a session that is silent for a reason nobody was
			# told looks like a session that is broken.
			Session.notice.emit("Guests won't hear the mix. " + MixTap.why_not)
		return tapped
	Session.listen_choice = args["listen"]
	Session.mix_feed.report = args["audio_stats"]
	if args["audio_out"] != "":
		AudioServer.output_device = args["audio_out"]
	_open_ports(args)
	# What to do first, on a sent-out build's first launch, and on F1 from then on.
	var welcome := WelcomeCard.new()
	welcome.name = "Welcome"
	add_child(welcome)
	if args["welcome"] or (OS.has_feature("template") and WelcomeCard.first_time()):
		welcome.open()
	if args["join"] != "":
		# A guest still has a backend: it holds the replicated cache. It just never opens a
		# link of its own, which is the whole of what "one link per session" means.
		Session.join(args["join"], args["session_port"], args["code"])
	elif args["host"]:
		Session.code = args["code"]
		if Session.host(args["session_port"]) and args["public"]:
			Session.open_to_internet()
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
	studio.fed_level = args["feed_level"]
	if args["seated"]:
		studio.ergonomics = Ergonomics.seated_default()
	# How tall you are, said once and remembered: `--height 1.60`. Applied after sitting down,
	# because a seated eye is a different fraction of the same height.
	if args["height"] > 0.0:
		Ergonomics.save_height(args["height"], Ergonomics.HEIGHT_PATH)
	var height: float = args["height"] if args["height"] > 0.0 \
			else Ergonomics.load_height(Ergonomics.HEIGHT_PATH)
	if height > 0.0:
		studio.ergonomics.set_height(height)
	if args["eyes"] > 0.0:
		studio.ergonomics.text_scale = args["eyes"]
	Ergonomics.current = studio.ergonomics
	add_child(studio)

	if args["venue"] != "":
		# `grid:1` is the grid's second arrangement (Venue.VARIANTS).
		var asked := (args["venue"] as String).split(":")
		if Venue.is_known(StringName(asked[0])):
			studio.set_venue(StringName(asked[0]), false, int(asked[1]) if asked.size() > 1 else 0)
		else:
			push_warning("bootstrap: --venue %s is not one of %s" % [args["venue"], Venue.IDS])

	if not args["no_hud"]:
		_build_hud()
	session_panel = SessionPanel.new()
	session_panel.name = "SessionPanel"
	add_child(session_panel)
	if args["session_panel"]:
		session_panel.open()
	var tour_hud := TourHud.new()
	tour_hud.name = "TourHud"
	add_child(tour_hud)
	if args["play_into"] > 0:
		Session.guest_midi.target_track = args["play_into"]
	if args["mic_into"] > 0:
		Session.guest_audio.target_track = args["mic_into"]
		Session.guest_audio.record_with_host = true
	if args["computer_keys"]:
		session_panel.play_with_computer_keys.call_deferred(true)
	if not args["bring_in"].is_empty():
		session_panel.bring_in_files.call_deferred(args["bring_in"])

	_apply_cli_placement(args["place"])
	for wanted in args["plugins"]:
		_apply_cli_plugin(wanted)
	for wanted in args["tablets"]:
		_apply_cli_tablet(wanted)
	_apply_cli_focus(args["focus"])
	if args["detach_body"] and studio.body != null:
		# After one frame, so the rig has taken its pose from the head before it is cut loose.
		studio.body._process(0.0)
		studio.body.detach()
	var loop: Vector2 = args["loop"]
	if loop.y > loop.x:
		DAW.set_loop_range(DAW.state.bar_to_seconds(loop.x), DAW.state.bar_to_seconds(loop.y))
		DAW.set_looping(true)
	# Selected items and a playhead, for photographing an edit about to be made.
	for pair in args["select"]:
		DAW.select_item(pair.x, pair.y, true)
	if args["at_bar"] > 0.0:
		DAW.seek(DAW.state.bar_to_seconds(args["at_bar"]))
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
			options["bridge_dir"] = args["reaper_resource"].path_join("Scripts/dawlings_bridge_data")
		if DAW.use(ReaperBackend.new(), true, options):
			return
		push_warning("bootstrap: could not open the OSC link; falling back to the offline stand-in.")
	var offline := GodotBackend.new() if args["built_in"] else OfflineBackend.new()
	offline.track_count = args["tracks"]
	DAW.use(offline)


func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {
		# A build sent out (an export template) makes sound from the start: whoever runs it has
		# no Reaper. Run from the editor, as the tests and probes are, the silent stand-in.
		"reaper": false, "built_in": OS.has_feature("template"), "reaper_host": "127.0.0.1",
		"send_port": DEFAULT_SEND_PORT, "listen_port": DEFAULT_LISTEN_PORT,
		"host": false, "public": false, "join": "", "xr": OS.has_feature("android"), "xr_sim": false, "ar": OS.has_feature("android"),
		"place": {}, "stage": false, "view": Vector2.ZERO, "tracks": 0,
		"focus": "", "fresh_layout": false, "detach_body": false, "no_motion": false, "feed_level": -1.0, "vision": "", "dwell": 0.0, "step": 0.0, "eyes": 0.0, "seated": false, "height": 0.0, "no_hud": false,
		"name": "", "code": "", "mix_tone": false, "audio_stats": false, "session_port": Session.DEFAULT_PORT, "mix_from": "", "listen": -1, "audio_out": "", "direct_audio": false, "session_panel": false, "play_into": 0, "mic_into": 0, "computer_keys": false, "bring_in": PackedStringArray(),
		"venue": "", "reaper_resource": "", "loop": Vector2.ZERO, "select": [], "at_bar": 0.0,
		"ghost": {}, "tablets": [], "plugins": [], "welcome": false,
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
			"--add-plugin":
				# `--add-plugin 2:NAMix` -- an installed plugin put at the end of track 2's chain,
				# in the built-in engine, for photographing it (with --tablet) without a hand.
				i += 1
				if i < argv.size() and argv[i].find(":") > 0:
					var colon := argv[i].find(":")
					out["plugins"].append([int(argv[i].left(colon)), argv[i].substr(colon + 1)])
			"--tablet":
				# `--tablet 2:1` -- this plugin, torn off onto a stand in front of the rack, as
				# if it had been pulled. For photographing the tablet without a hand to pull it.
				# `--tablet 2:1:5` opens it on its fifth page, and `--tablet 2:1:ui` on the
				# plugin's own window, where the DAW can show it -- the one way to turn that
				# face on where it would otherwise be off (PluginTablet.window_face).
				i += 1
				if i < argv.size():
					var parts := argv[i].split(":")
					if parts.size() in [2, 3]:
						var page := 1
						if parts.size() == 3:
							page = CLI_TABLET_WINDOW if parts[2] == "ui" else int(parts[2])
						out["tablets"].append(Vector3i(int(parts[0]), int(parts[1]), page))
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
				# `--venue grid`, or `--venue grid:1` for its second arrangement. For one run: a look asked for on the command line is not a
				# change of mind, so it is not written to the layout.
				i += 1
				if i < argv.size():
					out["venue"] = argv[i]
			"--ghost":
				# `--ghost hat=4,eyes=1` -- what this run's ghost wears, kept for this run only.
				# Two windows on one machine share a saved look; this tells them apart.
				i += 1
				if i < argv.size():
					for pair in argv[i].split(",", false):
						var kv := pair.split("=")
						if kv.size() == 2:
							out["ghost"][kv[0].strip_edges()] = int(kv[1])
			"--name":
				# What everyone else's room calls this participant.
				i += 1
				if i < argv.size():
					out["name"] = argv[i]
			"--code":
				# The session code: the one a host asks for, or the one a guest offers.
				i += 1
				if i < argv.size():
					out["code"] = argv[i]
			"--mix-tone": out["mix_tone"] = true
			"--audio-stats": out["audio_stats"] = true
			"--session-port":
				# Two sessions on one machine -- the tooling's, beside a real one.
				i += 1
				if i < argv.size():
					out["session_port"] = int(argv[i])
			"--mix-from":
				# A PipeWire node to tap instead of whichever REAPER registered first.
				i += 1
				if i < argv.size():
					out["mix_from"] = argv[i]
			"--listen": out["listen"] = 1
			"--no-listen": out["listen"] = 0
			"--audio-out":
				# Where this process plays, by PipeWire/Pulse sink name. For the tooling: a guest
				# whose sound goes to a null sink can be recorded instead of heard.
				i += 1
				if i < argv.size():
					out["audio_out"] = argv[i]
			"--direct-audio":
				# Everything out of the app's one output, as before AudioPorts: for a machine
				# whose sound server takes badly to a process with several streams.
				out["direct_audio"] = true
			"--session-panel": out["session_panel"] = true
			"--bring-in":
				# `--bring-in ~/loop.wav` -- a sound file onto a track at the start, as the panel's
				# Import audio would. Repeatable.
				i += 1
				if i < argv.size():
					out["bring_in"].append(argv[i])
			"--play-into":
				# `--play-into 7` -- a guest's keys go onto track 7 when the host records.
				i += 1
				if i < argv.size():
					out["play_into"] = int(argv[i])
			"--mic-into":
				# `--mic-into 8` -- a guest's microphone goes onto track 8 when the host records.
				i += 1
				if i < argv.size():
					out["mic_into"] = int(argv[i])
			"--computer-keys": out["computer_keys"] = true
			"--fresh-layout": out["fresh_layout"] = true
			"--welcome": out["welcome"] = true
			"--seated": out["seated"] = true
			"--detach-body": out["detach_body"] = true
			"--no-motion": out["no_motion"] = true
			"--feed-level":
				if i + 1 < argv.size():
					i += 1
					out["feed_level"] = float(argv[i])
			"--step":
				i += 1
				if i < argv.size():
					out["step"] = float(argv[i])
			# For photographs: the corner readout is for whoever is debugging, not for a picture.
			"--no-hud": out["no_hud"] = true
			"--height":
				i += 1
				if i < argv.size():
					out["height"] = float(argv[i])
			"--dwell":
				i += 1
				if i < argv.size():
					out["dwell"] = float(argv[i])
			"--vision":
				i += 1
				if i < argv.size():
					out["vision"] = argv[i]
			"--reaper": out["reaper"] = true
			"--built-in": out["built_in"] = true
			"--stand-in": out["built_in"] = false
			"--host": out["host"] = true
			"--public": out["public"] = true
			"--xr": out["xr"] = true
			"--xr-sim":
				# A headset simulated from the mouse and keyboard; --ar with it simulates passthrough.
				out["xr"] = true
				out["xr_sim"] = true
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
			"--select":
				# `--select 2:0,3:1` -- select those items (track:index in lane).
				i += 1
				if i < argv.size():
					for pair in argv[i].split(","):
						var parts := pair.split(":")
						if parts.size() == 2:
							out["select"].append(Vector2i(int(parts[0]), int(parts[1])))
			"--at":
				# `--at 17` -- put the playhead on bar 17.
				i += 1
				if i < argv.size():
					out["at_bar"] = float(argv[i])
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


## `--add-plugin T:NAME`: the installed plugin called NAME onto track T, where the engine hosts them.
func _apply_cli_plugin(wanted: Array) -> void:
	if not DAW.backend is GodotBackend or not HostedPlugins.available():
		push_warning("bootstrap: --add-plugin needs the built-in engine, hosting plugins")
		return
	var catalogue := PluginCatalogue.shared()
	catalogue.wait()
	for p in catalogue.plugins():
		if p["name"] == wanted[1]:
			DAW.add_fx(wanted[0], GodotBackend.plugin_choice(p))
			return
	push_warning("bootstrap: --add-plugin: no plugin called %s is installed" % wanted[1])


## `--tablet T:F:ui`, as the page it asks for.
const CLI_TABLET_WINDOW := -1


func _apply_cli_tablet(wanted: Vector3i) -> void:
	# A live DAW reports its plugins a moment after the link opens; the stand-in has them already.
	var waited := 0.0
	while waited < 10.0 and (DAW.state.fx(wanted.x, wanted.y, false) == null \
			or DAW.state.fx(wanted.x, wanted.y, false).name == ""):
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var f := DAW.state.fx(wanted.x, wanted.y, false)
	if f == null or f.name == "" or studio.floor_plan == null:
		push_warning("bootstrap: --tablet %d:%d is not a plugin in this session" % [wanted.x, wanted.y])
		return
	var at := studio.rack.global_position
	studio._on_tear_requested(wanted.x, wanted.y, at)
	if wanted.z == 1:
		return
	for id in studio.tablets:
		var tablet: PluginTablet = studio.tablets[id][1]
		if tablet.track_index != wanted.x or tablet.fx_index != wanted.y:
			continue
		if wanted.z == CLI_TABLET_WINDOW:
			PluginTablet.window_face = true
			var asked := 0.0
			while asked < 10.0 and not DAW.shows_plugin_windows():
				await get_tree().create_timer(0.25).timeout
				asked += 0.25
			tablet.show_window(true)
			if not tablet.showing_window:
				push_warning("bootstrap: --tablet %d:%d:ui -- this DAW cannot show the plugin's window here" \
						% [wanted.x, wanted.y])
			continue
		# The page needs the plugin's full list, which a live DAW sends a moment later.
		var paged := 0.0
		while paged < 10.0 and tablet._page_starts().size() < wanted.z:
			await get_tree().create_timer(0.25).timeout
			tablet._process(0.0)
			paged += 0.25
		for step in wanted.z - 1:
			tablet._step_page(1)


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
	if OS.has_feature("template"):
		# A sent-out build: what it is, and where the rest is said (WelcomeCard).
		_hud.text = "dawlings  |  %s  |  %s  |  %d track(s)  |  F1 help  |  M session  |  WASD walk / right-drag look  |  F focus / shift-F back" % [
			role_name, DAW.summary(), _track_count()]
		return
	_hud.text = "dawlings  |  %s / %s  |  %s  |  %d track(s)  |  F focus / shift-F back / esc release  |  G bring gear to you  |  WASD walk / shift run / space jump / right-drag look  |  N %s  |  V venue: %s  |  E expand desk  |  Q put down / hold R throw / 1-3 pockets  |  M session  |  +/- text size  |  tab move gear  |  drag stands to roll them" % [
		role_name, medium_name, DAW.summary(), _track_count(),
		"god mode" if studio.god_mode else "walking",
		studio.venue.title() if studio.venue != null else "room"]


## The project's size once Reaper has said it, and only until then the slots that have arrived.
## Reaper streams its bank before the project's count, so counting the cache read 43 or 44 for
## a moment on a 40-track session -- a number contradicted by the desk right under it.
func _track_count() -> int:
	var known: int = DAW.state.project_track_count
	if known > 0:
		return known
	return DAW.state.tracks.size()


## The mix tap, if this process made it, goes with it. A virtual source left behind is harmless,
## but it is a device in someone's sound settings that they did not add.
func _exit_tree() -> void:
	MixTap.close()
	if ports != null:
		ports.close()


## The app's sound out on streams of its own -- mix, monitor, gear -- each routable on its own.
## The buses are made either way, so every player has its own to name.
func _open_ports(args: Dictionary) -> void:
	AudioPorts.ensure_buses()
	AudioPorts.target = args["audio_out"]
	AudioPorts.direct = args["direct_audio"]
	if args["direct_audio"] or AudioServer.get_driver_name() == "Dummy":
		return
	ports = AudioPorts.new()
	ports.name = "AudioPorts"
	if NativeKeys.available():
		# A guest's keys are their own node, made when the session starts. The helper was just
		# built if it needed to be, so that start does not wait for a compiler.
		ports.skip = [AudioPorts.MONITOR]
	add_child(ports)
	if not ports.open():
		Session.notice.emit("The app's sound plays through one output. " + AudioPorts.why_not)
