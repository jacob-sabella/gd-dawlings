class_name ShotDemos
extends RefCounted

## The longer demonstrations a shot can stage: pasting a cassette, holding one to the ear, a wheel take playing, a made-up
## graph, the signal seen and the clip editor driven.
## Moved out of `tools/screenshot.gd` without change of behaviour; the state stays on the autoload, which keeps a one-line delegate for each name another file or a string reaches.

var shot: Screenshot


func _init(of: Screenshot) -> void:
	shot = of


## `--paste`: a cassette pulled at frame 6, the pointer parked on the lane it goes on, and the press.
func _paste_a_cassette() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
	var mouse := shot.driving._scripted_hand()
	if studio == null or mouse == null or studio.timeline == null:
		return
	var s := DAW.state
	var bar_at := s.bar_to_seconds(float(shot._paste[2]))
	if shot._frames == 6:
		studio.item_host._on_clip_pulled(int(shot._paste[0]), 0, mouse)
		studio.timeline.set_view(s.bar_to_seconds(float(shot._paste[2]) - 2.0), s.bar_to_seconds(float(shot._paste[2]) + 6.0) - s.bar_to_seconds(float(shot._paste[2]) - 2.0))
	if shot._frames == 9:
		var timeline: TimelineSurface = studio.timeline
		var i := s.track_indices().find(int(shot._paste[1]))
		var raw := s.seconds_at_beat(s.beat_at(bar_at) + 0.35)
		var point := timeline.to_global(Vector3(timeline._x_for(raw), timeline._lane_y[i], timeline._lanes.position.z))
		shot._hover = shot.get_viewport().get_camera_3d().unproject_position(point)
		mouse.pointer_override = shot._hover
		print("SHOT_PASTE carrying %s, pointer at %s" % [mouse.carrying.item_title() if mouse.carrying != null else "nothing", shot._hover])
	if shot._frames == 12:
		mouse.press_override = 1
	if shot._frames == 15:
		mouse.press_override = 0
		var pasted: Array = s.track(int(shot._paste[1])).items.filter(func(it): return is_equal_approx(it.start, bar_at))
		print("SHOT_PASTE pasted %d onto track %d at %s; the lanes say: %s" % [pasted.size(), shot._paste[1], s.bar_beat(bar_at), studio.timeline._lanes.card_hint()])


## `--ear`: a cassette pulled at frame 6 and held to the ear with L at frame 8.
func _hold_a_cassette_to_the_ear() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
	var mouse := shot.driving._scripted_hand()
	if studio == null or mouse == null:
		return
	if shot._frames == 6:
		studio.item_host._on_clip_pulled(shot._ear, 0, mouse)
	if shot._frames == 8:
		mouse.ear_held = true
	if shot._frames == 238:
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
	for tl in shot.get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false):
		(tl as TimelineSurface).set_view(start - 0.4, 4.6)
		(tl as TimelineSurface).set_size((tl as TimelineSurface).width_scale, TimelineSurface.LANE_HEIGHT_MAX)
	print("SHOT_WHEEL_TAKE ", gm.last_take)


## A graph of about `ports` output and input ports for --patch-graph: an interface with a dozen
## of each, then nodes of four, a few linked, named as a machine's are.
func _made_up_graph(ports: int) -> PipeGraph:
	var outs := ""
	var ins := ""
	for k in 12:
		outs += "alsa_input.usb-Focusrite_Scarlett_18i20:capture_%d\n" % (k + 1)
		ins += "alsa_output.usb-Focusrite_Scarlett_18i20:playback_%d\n" % (k + 1)
	var apps := ["Firefox", "dawlings · mix", "dawlings · mic", "Carla", "OBS", "Discord", "Bitwig", "VLC",
			"Mixxx", "SuperCollider", "Ardour", "qpwgraph"]
	var n := 0
	while 12 + n * 4 < ports:
		var app: String = apps[n % apps.size()] + ("" if n < apps.size() else " %d" % (n / apps.size() + 1))
		for side in ["output_FL", "output_FR", "output_RL", "output_RR"]:
			outs += "%s:%s\n" % [app, side]
		for side in ["input_FL", "input_FR", "input_RL", "input_RR"]:
			ins += "%s:%s\n" % [app, side]
		n += 1
	var links := "dawlings · mix:output_FL\n  |-> alsa_output.usb-Focusrite_Scarlett_18i20:playback_1\n" \
			+ "dawlings · mix:output_FR\n  |-> alsa_output.usb-Focusrite_Scarlett_18i20:playback_2\n" \
			+ "alsa_input.usb-Focusrite_Scarlett_18i20:capture_1\n  |-> dawlings · mic:input_FL\n" \
			+ "Firefox:output_FL\n  |-> alsa_output.usb-Focusrite_Scarlett_18i20:playback_1\n" \
			+ "Firefox:output_FR\n  |-> alsa_output.usb-Focusrite_Scarlett_18i20:playback_2\n"
	return PipeGraph.parse(outs, ins, links)


## `--signal`'s doings, frame by frame.
func _see_the_signal() -> void:
	var studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
	if studio == null:
		return
	for word in shot._signal:
		var w := word.split(":")
		var track := int(w[1]) if w.size() > 1 else 0
		if shot._frames == 9:
			match w[0]:
				"clip": DAW.set_track_volume(track, 1.0)
				"mute": DAW.set_track_mute(track, true)
				"x": studio.signal_views.toggle_signal_view()
		if w[0] == "look" and shot._frames == 12:
			# Look to solo held over the track (docs/spatial_loop.md part three, G), as U held does.
			var said := studio.look_solo.press(track)
			if said != "":
				Session.notice.emit(said)
		if w[0] == "trace" and shot._frames == maxi(shot._shot_frame - (int(w[2]) if w.size() > 2 else 14), 10):
			studio.signal_views.trace_from(SignalGraph.play_id(track), DAW.state.track(track).display_name())


## `--clip-take` and `--clip-editor`: see their vars.
func _drive_clip_editor() -> void:
	var found := shot.get_tree().current_scene.find_children("ClipEditor", "ClipEditorSurface", true, false)
	if found.is_empty():
		return
	var editor := found[0] as ClipEditorSurface
	if shot._frames == 6 and shot._clip_take != "":
		var spec := shot._clip_take.split(":")
		var track := int(spec[0])
		var at := DAW.state.bar_to_seconds(float(spec[1]) if spec.size() > 1 else 9.0)
		var mixed := PackedFloat32Array()
		for role in ["kick", "snare", "hat"]:
			var part := DemoSong.render(role, DAW.state.tempo)
			if mixed.is_empty():
				mixed = part
			else:
				for n in mini(mixed.size(), part.size()):
					mixed[n] += part[n]
		var file := "shot_drum_take.wav"
		var path := ProjectSettings.globalize_path(AudioTake.DIR.path_join(file))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		DawKitAudioFile.write_wav(path, mixed, 1, DemoSong.RATE)
		var length := float(mixed.size()) / DemoSong.RATE
		DAW.insert_audio_take(track, at, file, length, DawKitAudioFile.peaks(mixed, 1, DemoSong.RATE), "Drum take")
		var items: Array = DAW.state.track(track).items
		for k in items.size():
			if absf((items[k] as MixState.ItemState).start - at) < 0.001:
				shot._clip_editor = "%d:%d" % [track, k]
		DAW.item_transients(track, 0)
		print("SHOT_CLIP take on %s at %.3f s: %s" % [track, at, shot._clip_editor])
	if shot._frames == 8 and shot._clip_editor != "":
		var ti := shot._clip_editor.split(":")
		var track := int(ti[0])
		var index := int(ti[1])
		if shot._clip_fade > 0.0:
			DAW.set_item_fades(track, index, shot._clip_fade, shot._clip_fade)
		DAW.select_item(track, index, false)
		editor.open(track, index)
		if shot._clip_span > 0.0:
			var it := editor.item()
			editor.set_view(it.start - shot._clip_span * 0.3, shot._clip_span)
		if shot.CLIP_HANDLES.has(shot._clip_select):
			editor.select_handle(shot.CLIP_HANDLES[shot._clip_select])
		editor.set_zero_crossings(shot._clip_zero)
		if shot._clip_screen:
			var studio := shot.get_tree().current_scene.find_children("*", "Studio", true, false)
			if not studio.is_empty():
				(studio[0] as Studio).mount.set_mode(editor.surface_id, Presentation.Mode.SCREEN)
		DawKitTransients.settle()
		ClipWave.settle()
		print("SHOT_CLIP open=%s view=%.4f+%.4f title=%s" % [editor.target, editor.view_start, editor.view_span, editor.title_text()])
	if shot._frames >= 10 and shot._clip_hover != "" and editor.is_open():
		var point: Vector3
		if shot.CLIP_HANDLES.has(shot._clip_hover):
			var h: int = shot.CLIP_HANDLES[shot._clip_hover]
			var t := editor.handle_time(h)
			var local := Vector3(editor.x_for(t), ClipEditorSurface.WAVE_MID, 0.002)
			if h in [ClipEditorSurface.FADE_IN, ClipEditorSurface.FADE_OUT]:
				local.y = ClipEditorSurface.WAVE_TOP - 0.004
			elif h == ClipEditorSurface.GAIN:
				local.y = editor.gain_y(editor.shown("gain"))
			point = editor.to_global(local)
		elif editor.key(StringName(shot._clip_hover)) != null:
			point = editor.key(StringName(shot._clip_hover)).to_global(Vector3(0, 0, 0.01))
		else:
			return
		shot._hover = shot.get_viewport().get_camera_3d().unproject_position(point)
