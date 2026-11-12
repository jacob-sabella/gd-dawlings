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


var studio: Studio
var xr := XRBootstrap.new()

var _hud: Label
var session_panel: SessionPanel


## The app's named audio streams, where they opened.
var ports: AudioPorts


func _ready() -> void:
	var args := BootstrapArgs.parse(OS.get_cmdline_user_args())
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
	if args["noray_server"] != "":
		Session.online_server = args["noray_server"]
	Session.force_relay = Session.force_relay or args["relay"]
	if args["join_code"] != "":
		# By the code a host read out, through the noray server (docs/multiplayer.md).
		Session.start_solo()
		_start_daw(args)
		Session.join_by_code(args["join_code"], args["code"])
	elif args["join"] != "":
		# A guest still has a backend: it holds the replicated cache. It just never opens a
		# link of its own, which is the whole of what "one link per session" means.
		Session.join(args["join"], args["session_port"], args["code"])
	elif args["host"] or args["online"]:
		Session.code = args["code"]
		if Session.host(args["session_port"]):
			if args["public"]:
				Session.open_to_internet()
			if args["online"]:
				Session.host_online(args["session_port"])
		_start_daw(args)
		# What guests hear is the DAW's own output (Session.mix_source), and the DAW did not exist yet when hosting
		# began: the feed had taken silence for its source. It is handed the DAW's now, before any guest is in.
		if Session.role == Session.Role.HOST and Session.mix_feed != null and Session.mix_feed.sending:
			Session.mix_feed.start_sending(Session.mix_feed.port, Session.mix_source.call())
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
	# Sitting down first: it is a whole other default body, and what follows is said of it.
	if args["seated"]:
		studio.ergonomics = Ergonomics.seated_default()
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
	# COMFORT as the session panel kept it, beside the height; `--no-motion` over it.
	studio.ergonomics.take_comfort(Ergonomics.HEIGHT_PATH, args["no_motion"])
	studio.fed_level = args["feed_level"]
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
	if args["perf"]:
		RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), true)
		var tick := Timer.new()
		tick.wait_time = 2.0
		tick.autostart = true
		tick.timeout.connect(func() -> void:
			print("PERF gpu=%.1fms cpu_render=%.1fms fps=%d process=%.1fms physics=%.1fms draws=%d prims=%dk objs=%d nodes=%d orphans=%d vram=%dMB" % [
					RenderingServer.viewport_get_measured_render_time_gpu(get_tree().root.get_viewport_rid()),
					RenderingServer.viewport_get_measured_render_time_cpu(get_tree().root.get_viewport_rid()),
					Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
					int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
					int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000,
					int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
					int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
					int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)]))
		add_child(tick)
	# The card's PLAY pages are the stations standing in the studio's venue, and a line walks there.
	welcome.studio = studio
	if welcome.visible:
		welcome.open()

	if args["venue"] != "":
		# `grid:1` is the grid's second arrangement (Venue.variant_titles).
		var asked := (args["venue"] as String).split(":")
		if Venue.is_known(StringName(asked[0])):
			studio.venue_switch.set_venue(StringName(asked[0]), false, int(asked[1]) if asked.size() > 1 else 0)
		else:
			push_warning("bootstrap: --venue %s is not one of %s" % [args["venue"], Venue.IDS])

	if not args["no_hud"]:
		_build_hud()
	session_panel = SessionPanel.new()
	session_panel.name = "SessionPanel"
	add_child(session_panel)
	# EDIT on the lyric board at a desk opens the panel at its LYRICS box (slice 56).
	studio.lyrics_edit_asked.connect(session_panel.edit_lyrics)
	# The join code typed on keys in the room, in a headset: over the note pad, as a note's words are.
	session_panel.pad_parent = func() -> Node3D: return studio.note_pad
	# In a headset it is glass in the room, put up by MENU on the wrist, away by the escape.
	if studio.rig != null:
		session_panel.in_room(studio)
		studio.rig.session_requested.connect(session_panel.toggle)
		studio.rig.escape_requested.connect(func() -> void:
			if session_panel.is_open():
				session_panel.close())
	studio.computer_keys_toggled.connect(session_panel.toggle_computer_keys)
	if args["session_panel"]:
		session_panel.open()
	if Tour.enabled:
		var tour_hud := TourHud.new()
		tour_hud.name = "TourHud"
		add_child(tour_hud)
	# The Workshop (docs/workshop.md): only with its dev flag, on the host's own machine. It reads
	# `--workshop` and `--resume` itself, and puts the room back after a reload.
	Workshop.attach(self, studio)
	# The control API, its MCP server and the assistant (docs/mcp_assistant.md).
	RackEngine.warm()
	ControlHost.attach(self, studio)
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
	for wanted: String in args["lose_plugin"]:
		var w := wanted.split(":")
		var lost := DAW.state.fx(int(w[0]), int(w[1]), false)
		if lost != null:
			lost.set_meta(&"unhosted", {"plugin_format": w[2], "plugin_id": w[3]})
			lost.params.clear()
			lost.param_names.clear()
			lost.name = w[3].get_slice(".", w[3].count("."))
			DAW.fx_changed.emit(int(w[0]), int(w[1]))
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
	if args["play"]:
		DAW.transport_play()
	if args["slap"] and studio.looper != null:
		studio.item_host._on_looper_slapped()
	# `--rings N`: N layers already on the looper (docs/spatial_loop.md part two, slice 46), for a shot
	# of its rings: two bars each from bar 2, the players taking turns, the second muted.
	if args["rings"] > 0 and studio.looper != null:
		var span := [DAW.state.bar_to_seconds(2), DAW.state.bar_to_seconds(4)]
		for n in mini(args["rings"], LooperRings.MOST):
			var made := Looper.write_layer(["Ada", "Grace", "Jsabella"][n % 3], span[0], span[1],
					[[span[0] + 0.25 * n, span[0] + 0.25 * n + 0.2, 60 + n * 4, 100, 0]])
			if n == 1 and int(made["track"]) > 0:
				DAW.set_track_mute(int(made["track"]), true)
		DAW.set_loop_range(span[0], span[1])
		DAW.set_looping(true)
	# `--lyrics`: the song's lyrics on the vocal booth's lyric board (docs/spatial_loop.md part two, slice
	# 56), for a shot of it: four lines timed and two left to TAP, the board held at 7 s, half way
	# through the second line, as the song would put it there.
	if args["lyrics"] and studio.lyric_board != null and DAW.state != null:
		DAW.set_lyrics("[00:01.00]Wires hum beneath the floor\n[00:05.00]Every fader finds its place\n[00:09.00]We tune the room until it's ours\n[00:13.00]And sing it back into the space\n\nTurn the lamps down, let it ring\nHold the last note, let it go")
		studio.lyric_board.heard_source = func() -> Dictionary: return {"seconds": 7.0, "playing": true, "valid": true}
	# `--modular`: the rack with the drum machine preset put in, for a shot of it, and an A held on its
	# touch keys.
	if args["modular"] and studio.rack_wall != null:
		studio.rack_host._rack_wake()
		print("RACKRUN ", studio.rack_voice.running(), " ", RackEngine.available())
		studio.rack_host.ask_rack("preset", [args["rack_preset"]])
		if args["rack_preset"] == "big_rig":
			studio.rack_voice.engine.say("play 0")
		studio.rack_wall.touch_keys[9].grab_begin(studio, studio.rack_wall.touch_keys[9].global_position)
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

	# The room's edit mode: F3, the host only (LayoutEditor).
	var editor := LayoutEditor.new()
	editor.name = "LayoutEditor"
	editor.studio = studio
	add_child(editor)

	# The new-room maker: F4, the host only (RoomMaker).
	var maker := RoomMaker.new()
	maker.name = "RoomMaker"
	maker.studio = studio
	add_child(maker)

	# The mods list: F5, read-only, host or guest (ModsScreen).
	var mods_screen := ModsScreen.new()
	mods_screen.name = "ModsScreen"
	add_child(mods_screen)

	# The whole mix as a flat DAW: F2, or `--flat` to start in it.
	var flat := FlatView.new()
	flat.name = "FlatView"
	flat.studio = studio
	flat.in_headset = medium != Presentation.Medium.SCREEN
	flat.said.connect(func(text: String): Session.notice.emit(text))
	add_child(flat)
	# F2 is the one key the open help card does not keep: the 2D view, later in the tree, hears it
	# first. Its opening puts the card away rather than leave it holding the keyboard over the view.
	flat.visibility_changed.connect(func() -> void:
		if flat.is_open() and welcome.visible:
			welcome.close())
	if args["flat"]:
		flat.set_open(true)
	var fx: Vector2i = args["flat_fx"]
	if fx.x > 0:
		flat.view.effect_panel.show_effect(ProjectBridge.id_of(fx.x), fx.y)
	for spec: String in args["flat_lanes"]:
		var lane := spec.get_slice("@", 0)
		var id := ProjectBridge.id_of(lane.get_slice(":", 0).to_int())
		var target := lane.substr(lane.find(":") + 1)
		if spec.contains("@"):
			var points: Array = []
			for pair in spec.get_slice("@", 1).split(","):
				points.append([pair.get_slice(":", 0).to_float(), pair.get_slice(":", 1).to_float(), DawKitAutomation.LINEAR])
			flat.host.set_automation(id, target, points)
		flat.view.arrange.show_lane(id, target)
	if args["flat_view"] >= 0:
		flat.view.show_view(clampi(args["flat_view"], 0, 2))
	var clip: Vector2i = args["flat_clip"]
	if clip.x > 0:
		flat.view.open_clip(ProjectBridge.id_of(clip.x), clip.y)


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
	# A built-in effect by its kind (`--add-plugin 2:eq`), which needs no hosting.
	if FXCatalogue.kinds().has(StringName(wanted[1])):
		DAW.add_fx(wanted[0], wanted[1])
		return
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
	studio.tablet_host._on_tear_requested(wanted.x, wanted.y, at)
	if wanted.z == 1:
		return
	for id in studio.tablets:
		var tablet: PluginTablet = studio.tablets[id][1]
		if tablet.track_index != wanted.x or tablet.fx_index != wanted.y:
			continue
		if wanted.z == BootstrapArgs.TABLET_WINDOW:
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
			studio.station_host._sit_down()
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
	_hud.add_theme_font_size_override("font_size", HUD_SIZE)
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
	var focused := ""
	var chords := studio.chord_hand.hud_text() if studio != null and studio.chord_hand != null else ""
	if chords != "":
		# The chord layer, or a shape held (docs/spatial_loop.md part two, slice 32): `CHORDS · IV F`.
		focused = chords
	elif studio != null and studio.focus != null and studio.focus.is_focused():
		focused = String(studio.focus.focused_id).to_upper()
	elif studio != null:
		focused = "FLYING" if studio.god_mode else "WALKING"
	_hud.text = hud_text(role_name, medium_name, DAW.summary(), _track_count(),
			studio.venue.title() if studio != null and studio.venue != null else "room", focused,
			_hud.get_theme_font("font"))


## How wide the corner readout may run: a 1600 px window less 16 px either side.
const HUD_WIDTH := 1568
const HUD_SIZE := 13
## Where the rest is said: the help card's pages, the 2D view, the instruments, the session.
const HUD_KEYS := "F1 help · F2 2D view · I instruments · M session"


## The corner readout, both builds: who you are, the DAW, the room and what has your attention,
## then where everything else is said (HUD_KEYS; the long list of keys is the help card's ROOM
## page). Cut to HUD_WIDTH at HUD_SIZE in `font`: the DAW's summary first, then the venue's
## title, each shortened with an ellipsis, so the keys at its end are always on the screen.
static func hud_text(role: String, medium: String, summary: String, tracks: int, venue: String,
		focused: String, font: Font) -> String:
	var line := func(daw: String, where: String) -> String:
		var fields := ["dawlings", "%s / %s" % [role, medium], daw, "%d track%s" % [tracks, "" if tracks == 1 else "s"], where]
		if not focused.is_empty():
			fields.append(focused)
		fields.append(HUD_KEYS)
		return "  |  ".join(fields)
	var daw := summary
	var where := venue
	var text: String = line.call(daw, where)
	if font == null:
		return text
	while font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, HUD_SIZE).x > HUD_WIDTH - 12:
		if daw.length() > 12:
			daw = daw.left(daw.length() - 2).strip_edges() + "…"
			daw = daw.replace("……", "…")
		elif where.length() > 8:
			where = where.left(where.length() - 2).strip_edges() + "…"
			where = where.replace("……", "…")
		else:
			break
		text = line.call(daw, where)
	return text


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
