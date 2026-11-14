class_name BootstrapArgs
extends RefCounted

## The command line, read: every switch `scenes/bootstrap.gd` understands (see its header for the
## launches that matter) and the value each has when it is not given. Pure: it touches no node, so
## the tests read switches straight from a list of words.

const DEFAULT_SEND_PORT := 8000
const DEFAULT_LISTEN_PORT := 9000
## `--tablet T:F:ui`, as the page it asks for.
const TABLET_WINDOW := -1
## `--tablet T:F:big`: the plugin's own window, stood up big over the stand (PluginTablet.show_big).
const TABLET_BIG := -2


## `argv` (the arguments after `--`) as a dictionary of every switch, with its default for the ones
## not given. An unknown word is ignored.
static func parse(argv: PackedStringArray) -> Dictionary:
	var out := {
		# A build sent out (an export template) makes sound from the start: whoever runs it has
		# no Reaper. Run from the editor, as the tests and probes are, the silent stand-in.
		"reaper": false, "built_in": OS.has_feature("template"), "reaper_host": "127.0.0.1",
		"send_port": DEFAULT_SEND_PORT, "listen_port": DEFAULT_LISTEN_PORT,
		"host": false, "public": false, "join": "", "online": false, "join_code": "", "noray_server": "", "relay": false, "xr": OS.has_feature("android"), "xr_sim": false, "ar": OS.has_feature("android"),
		"place": {}, "stage": false, "view": Vector2.ZERO, "tracks": 0,
		"focus": "", "fresh_layout": false, "detach_body": false, "no_motion": false, "feed_level": -1.0, "vision": "", "dwell": 0.0, "step": 0.0, "eyes": 0.0, "seated": false, "height": 0.0, "no_hud": false, "perf": false, "play": false, "slap": false, "rings": 0, "lyrics": false, "modular": false, "rack_preset": "acid_line", "modular_rec": false, "world": false, "flat": false, "flat_fx": Vector2i.ZERO, "flat_clip": Vector2i.ZERO, "flat_lanes": [], "flat_view": -1,
		"name": "", "code": "", "mix_tone": false, "audio_stats": false, "session_port": Session.DEFAULT_PORT, "mix_from": "", "listen": -1, "audio_out": "", "direct_audio": false, "session_panel": false, "play_into": 0, "mic_into": 0, "computer_keys": false, "bring_in": PackedStringArray(),
		"venue": "", "reaper_resource": "", "loop": Vector2.ZERO, "select": [], "at_bar": 0.0,
		"ghost": {}, "tablets": [], "plugins": [], "lose_plugin": [], "welcome": false,
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
			"--rack-preset":
				# `--rack-preset big_rig`: with --modular, the preset the wall is put in (default acid_line).
				i += 1
				if i < argv.size():
					out["rack_preset"] = argv[i]
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
			"--lose-plugin":
				# `--lose-plugin 2:1:vst3:org.example.synth` -- the plugin in track 2's slot 1 as a
				# project that was saved with a plugin this machine lacks keeps it: for photographing the
				# unavailable plate (RackUnitDress).
				i += 1
				if i < argv.size() and argv[i].count(":") >= 3:
					out["lose_plugin"].append(argv[i])
			"--tablet":
				# `--tablet 2:1` -- this plugin, torn off onto a stand in front of the rack, as
				# if it had been pulled. For photographing the tablet without a hand to pull it.
				# `--tablet 2:1:5` opens it on its fifth page, and `--tablet 2:1:ui` on the
				# plugin's own window, where the DAW can show it -- the one way to turn that
				# face on where it would otherwise be off (PluginTablet.window_face). `--tablet 2:1:big`
				# stands that window up big over the stand.
				i += 1
				if i < argv.size():
					var parts := argv[i].split(":")
					if parts.size() in [2, 3]:
						var page := 1
						if parts.size() == 3:
							page = TABLET_WINDOW if parts[2] == "ui" else TABLET_BIG if parts[2] == "big" else int(parts[2])
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
			# A readout of the frame's cost every two seconds on stdout: script, physics, draw calls, nodes.
			"--perf": out["perf"] = true
			# The song playing from the start: for photographing what moves with it, the weather's
			# drops (docs/spatial_loop.md part two, slice 44) among them.
			"--play": out["play"] = true
			# `--slap`: the looper's pad slapped once everything is up (docs/spatial_loop.md part two,
			# slice 45), for a shot of its count or its recording.
			"--slap": out["slap"] = true
			# `--lyrics`: lyrics on the booth's lyric board, held mid-song, for a shot of it (slice 56).
			"--lyrics": out["lyrics"] = true
			# `--modular`: the modular wall re-patched, an A held on its keys, for a shot of it (slice 51).
			"--modular": out["modular"] = true
			# `--modular-rec`: and a take recording through it, OUT saying REC (slice 52).
			"--modular-rec":
				out["modular"] = true
				out["modular_rec"] = true
			# `--world`: the weather patched into the modular wall, for a shot of its cable (slice 53).
			"--world": out["world"] = true
			# `--rings N`: N layers on the looper, for a shot of its rings (slice 46).
			"--rings":
				i += 1
				if i < argv.size():
					out["rings"] = int(argv[i])
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
			# Online by a code, through a noray server: no address, no router (docs/multiplayer.md).
			"--online": out["online"] = true
			"--relay": out["relay"] = true
			"--join-code":
				i += 1
				if i < argv.size():
					out["join_code"] = argv[i]
			"--noray-server":
				i += 1
				if i < argv.size():
					out["noray_server"] = argv[i]
			"--xr": out["xr"] = true
			"--xr-sim":
				# A headset simulated from the mouse and keyboard; --ar with it simulates passthrough.
				out["xr"] = true
				out["xr_sim"] = true
			"--stage": out["stage"] = true
			"--flat": out["flat"] = true
			# `--flat-fx 2:0`: the 2D view's controls for track 2's first effect, for a photograph.
			"--flat-fx":
				i += 1
				if i < argv.size() and argv[i].contains(":"):
					out["flat_fx"] = Vector2i(argv[i].get_slice(":", 0).to_int(), argv[i].get_slice(":", 1).to_int())
			# `--flat-clip 2:0`: the 2D view's piano roll on track 2's first clip, for a photograph.
			"--flat-clip":
				i += 1
				if i < argv.size() and argv[i].contains(":"):
					out["flat_clip"] = Vector2i(argv[i].get_slice(":", 0).to_int(), argv[i].get_slice(":", 1).to_int())
			# `--flat-lane 7:volume` (repeatable): the 2D view shows that automation lane; with
			# `@1:-6,6:0` after it, the lane is drawn with those points first, for a photograph.
			# `--flat-view 0`: the 2D view's arrangement (0), mixer (1) or both (2).
			"--flat-view":
				i += 1
				if i < argv.size():
					out["flat_view"] = int(argv[i])
			"--flat-lane":
				i += 1
				if i < argv.size() and argv[i].contains(":"):
					out["flat_lanes"].append(argv[i])
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
