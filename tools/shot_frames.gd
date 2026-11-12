class_name ShotFrames
extends RefCounted

## The per-frame script of a shot: framing the camera, the scenes that need a few frames to settle, the chord hand,
## the hands, and the capture itself.
## Moved out of `tools/screenshot.gd` without change of behaviour; the state stays on the autoload, which keeps a one-line delegate for each name another file or a string reaches.

var shot: Screenshot


func _init(of: Screenshot) -> void:
	shot = of


func _process_framing() -> void:
	# Framing is applied a few frames in, not at frame 0. The studio builds its surfaces on the
	# first processed frame, so a camera positioned before that is aimed at an empty room.
	if shot._frames == 4 and shot._cam.size() == 6:
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		if studio and studio.has_method("frame"):
			# A framed shot is a god's-eye view by definition: it hangs wherever it was told to.
			if studio.has_method("set_god_mode"):
				studio.set_god_mode(true)
			studio.frame(Vector3(shot._cam[3], shot._cam[4], shot._cam[5]), shot._cam[2], shot._cam[0], shot._cam[1])

	if shot._frames == 5 and shot._no_timeline:
		for hidden in shot.get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false):
			hidden.visible = false

	if shot._frames >= 5 and shot._frames <= 12 and shot._comfort:
		var panel := shot.get_tree().current_scene.find_child("SessionPanel", true, false) as SessionPanel
		if panel != null:
			if not panel.is_open():
				panel.open()
			var box := panel.find_child("Comfort", true, false) as Control
			if box != null:
				panel._scroll.ensure_control_visible(box)
				if shot._frames == 12:
					print("SHOT_COMFORT %s motion=%.1f room_reacts=%s lift_on_clip=%s" % [box.get_global_rect(),
							Ergonomics.current.motion_scale, Ergonomics.current.room_reacts, Ergonomics.current.lift_on_clip])

	if shot._frames == 3 and shot._patch_wall:
		var wall := PatchWallSurface.new()
		wall.position = Vector3(0, PatchWallSurface.HEIGHT + 0.25, 1.0)
		if shot._patch_graph > 0:
			wall.follow = false
		shot.get_tree().current_scene.add_child(wall)
		if shot._patch_graph > 0:
			wall.show_graph(shot.demos._made_up_graph(shot._patch_graph))
		for hidden in shot.get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false):
			hidden.visible = false

	if shot._frames == 8 and shot._bay_scroll.x >= 0:
		for bay in shot.get_tree().current_scene.find_children("*", "PatchbaySurface", true, false):
			(bay as PatchbaySurface).matrix.scroll_to(shot._bay_scroll.x, shot._bay_scroll.y)
			print("SHOT_BAY %s" % (bay as PatchbaySurface).matrix.position_words())

	if shot._frames == 6 and shot._tl_shelf != "":
		var tl := shot.get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false)
		if not tl.is_empty():
			(tl[0] as TimelineSurface).set_shelf(shot._tl_shelf == "on")
			print("SHOT_TL shelf=", (tl[0] as TimelineSurface).shelf)
		else:
			print("SHOT_TL none found")

	if shot._rope.size() >= 2:
		shot.scenes._tie_the_rope()
	if shot._frames == 6 and shot._wheel_take > 0:
		shot.demos._play_wheel_take(shot._wheel_take)
	if shot._paste.size() == 3:
		shot.demos._paste_a_cassette()
	if shot._ear > 0:
		shot.demos._hold_a_cassette_to_the_ear()
	if shot._frames == 6 and shot._tl_road >= 0.0:
		var tl := shot.get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false)
		if not tl.is_empty():
			DAW.seek(shot._tl_road)
			(tl[0] as TimelineSurface).set_highway(true)
	if shot._frames == 7 and shot._tl_render:
		for tl in shot.get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false):
			(tl as TimelineSurface).deck.show_page((tl as TimelineSurface).render_page)
	if shot._frames == 7 and (shot._tl_select != "" or shot._tl_pick >= 0):
		var tl := shot.get_tree().current_scene.find_children("Timeline", "TimelineSurface", true, false)
		if shot._tl_pick >= 0 and not tl.is_empty():
			(tl[0] as TimelineSurface).pick_track(shot._tl_pick)
		var first := true
		for pair in shot._tl_select.split(",", false):
			var ti := pair.split(":")
			if ti.size() == 2:
				DAW.select_item(int(ti[0]), int(ti[1]), not first)
				first = false
		print("SHOT_TL selected=", DAW.state.selected_items(), " picked=", shot._tl_pick)
	if shot._frames == 5 and shot._autosave:
		OfflineBackend.autosave_every = 0.001
		DAW.set_track_volume(3, 0.3)
		# Held while the song plays: stopped, so it is kept at once.
		DAW.transport_stop()
	if shot._frames == 5 and shot._recover:
		DAW.backend.autosave()
		DAW.backend.set(&"_settled_copy", "")
		DAW.project_replaced.emit()
	if shot._frames == 5 and shot._reopen:
		var path := ProjectSettings.globalize_path("user://shot_reopen.dawproject")
		print("SHOT_REOPEN ", DAW.save_project_as(path), DAW.open_project(path))
	if shot._frames == 7 and shot._tl_xfade != "":
		var x := shot._tl_xfade.split(":")
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
	if shot._clip_editor != "" or shot._clip_take != "":
		shot.demos._drive_clip_editor()
	if shot._frames == 8 and shot._input_picker > 0:
		InputPicker.ask(shot, shot._input_picker)
	if shot._frames == 7 and shot._tl_fade != "":
		var f := shot._tl_fade.split(":")
		if f.size() >= 3:
			DAW.set_item_fades(int(f[0]), int(f[1]), float(f[2]), float(f[2]))
		if f.size() == 4:
			# A shape for both ends, or "in/out".
			var shapes := f[3].split("/")
			DAW.set_item_fade_shape(int(f[0]), int(f[1]), int(shapes[0]), int(shapes[-1]))
	if shot._frames == 7 and shot._tl_group != "":
		for spec in shot._tl_group.split(",", false):
			var g := spec.split(":")
			if g.size() == 2:
				DAW.set_track_group(int(g[0]), int(g[1]))
	if shot._frames == 7 and shot._tl_region != "":
		for spec in shot._tl_region.split(",", false):
			var r := spec.split(":")
			if r.size() == 3:
				DAW.add_region(DAW.state.bar_to_seconds(float(r[0])), DAW.state.bar_to_seconds(float(r[1])), r[2])
	if shot._frames == 7 and shot._roll:
		DAW.transport_play()
	if shot._frames == 7 and shot._bead_aim != "":
		var from := DAW.state.position_seconds
		DAW.set_loop_range(from, from + shot.BEAD_LOOP)
		DAW.set_looping(true)
		DAW.transport_play()
		# The timeline zoomed onto the loop, so the passes are drawn wide enough to see.
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		if studio != null and studio.get("timeline") != null:
			(studio.timeline as TimelineSurface).set_view(maxf(from - 0.3, 0.0), shot.BEAD_LOOP + 0.6)
	if shot._frames == 12 and shot._pull_track:
		var puller := shot.get_tree().current_scene.get_node_or_null("Studio")
		if puller != null:
			for i in DAW.state.track_indices():
				if not DAW.state.track(i).plugins().is_empty():
					puller.open_track_rack(i, Vector2(-0.45, 0.25))
					var first: int = DAW.state.track(i).plugins()[0]
					puller.open_tablet(i, first, DAW.state.fx(i, first).name, Vector2(-0.95, 0.55))
					break
	if shot._frames == 12 and shot._pull_tracks > 0:
		var row := shot.get_tree().current_scene.get_node_or_null("Studio")
		if row != null:
			var with_plugins := DAW.state.track_indices().filter(
					func(t): return not DAW.state.track(t).plugins().is_empty())
			var n := mini(shot._pull_tracks, with_plugins.size())
			for k in n:
				row.open_track_rack(with_plugins[k], Vector2((k - (n - 1) * 0.5) * 0.75, 1.7))
	if shot._frames == 12 and not shot._board.is_empty():
		var studio_node := shot.get_tree().current_scene.get_node_or_null("Studio")
		if studio_node != null:
			studio_node.roll_room.choose_board_source(StringName(shot._board))
	if shot._frames == 9 and shot._rig_roll:
		var rolled := shot.get_tree().current_scene.get_node_or_null("Studio")
		if rolled != null:
			rolled.roll_room._roll_rig()


func _process_scenes() -> void:
	if shot._frames == 3 and shot._make_room != "":
		shot.scenes._make_a_room()
	if shot._frames == shot._panel_frame and shot._panel != "":
		shot.scenes._open_panel()
	if shot._frames == shot._mod_answer_frame and shot._mod_answer != "":
		shot.scenes._answer_mod_offer()
	# Later than the camera, so a visit the studio makes on its own at startup has landed first.
	if shot._frames == 8 and shot._walk_mirror > 0.0:
		var mirrors := shot.get_tree().current_scene.find_children("*", "Mirror", true, false)
		if not mirrors.is_empty():
			var m := (mirrors[0] as Node3D).global_transform
			var front := Vector3(m.basis.z.x, 0, m.basis.z.z).normalized()
			var at := m.origin + front * shot._walk_mirror
			shot._walk = [at.x, at.z, atan2(front.x, front.z), -0.05]
	if shot._frames == 8 and shot._walk_singer > 0.0:
		var studio_for_singer := shot.get_tree().current_scene.get_node("Studio") as Studio
		if studio_for_singer.singer_booth != null:
			var b := studio_for_singer.singer_booth.global_transform
			var front := Vector3(b.basis.z.x, 0, b.basis.z.z).normalized()
			var at := b.origin + front * shot._walk_singer
			shot._walk = [at.x, at.z, atan2(front.x, front.z), -0.12]
			print("SHOT_SINGER origin=", b.origin, " walk=", shot._walk)
	if shot._frames == 8 and shot._walk_perch > 0.0:
		var studio_for_perch := shot.get_tree().current_scene.get_node("Studio") as Studio
		var perch := studio_for_perch.singer_host.perch
		if perch != null:
			var pb := perch.global_transform
			var pf := Vector3(pb.basis.z.x, 0, pb.basis.z.z).normalized()
			var pat := pb.origin + pf * shot._walk_perch
			shot._walk = [pat.x, pat.z, atan2(pf.x, pf.z), -0.3]
	if shot._frames == 8 and shot._walk_rack_on:
		# Along the wall's own normal: the wall leans back, so "in front of it" is not a level step away.
		var studio_for_rack := shot.get_tree().current_scene.get_node("Studio") as Studio
		var wall := studio_for_rack.rack_wall
		if wall != null:
			var m := wall.global_transform
			var far: float = shot._walk_rack[0] if shot._walk_rack.size() > 0 else 1.6
			var across: float = shot._walk_rack[1] if shot._walk_rack.size() > 1 else 0.0
			var up: float = shot._walk_rack[2] if shot._walk_rack.size() > 2 else 0.0
			var turn: float = shot._walk_rack[3] if shot._walk_rack.size() > 3 else 0.0
			var at := m * Vector3(across, up, far)
			var f := -m.basis.z.normalized()
			shot._walk = [at.x, at.z, atan2(-f.x, -f.z) + turn, asin(f.y), at.y - studio_for_rack.walker.standing_eye]
			print("SHOT_RACK_WALL origin=", m.origin, " walk=", shot._walk)
	if shot._frames == 8 and shot._walk.size() >= 4:
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		if studio and studio.get("walker") != null:
			var w = studio.walker
			w.global_position = Vector3(shot._walk[0], shot._walk[4] if shot._walk.size() > 4 else 0.0, shot._walk[1])
			w.yaw = shot._walk[2]
			w.pitch = shot._walk[3]
			w.eye_height = w.standing_eye
			w._place_camera()

	if shot._frames == 5 and shot._visitor.size() >= 3:
		var lin := Session.Participant.new()
		lin.peer_id = 7
		lin.display_name = "Lin"
		lin.colour_index = 2
		lin.head = Transform3D(Basis(Vector3.UP, shot._visitor[2]), Vector3(shot._visitor[0], 1.55, shot._visitor[1]))
		Session.participants[7] = lin
		Session.roster_changed.emit()
	if shot._frames >= 5 and Session.participants.has(7):
		(Session.participants[7] as Session.Participant).heard_msec = Time.get_ticks_msec()
		if shot._point != "":
			(Session.participants[7] as Session.Participant).pointing_at = shot._point
			(Session.participants[7] as Session.Participant).pointing_local = shot._point_at
	if shot._frames == 6 and shot._note.contains(":"):
		var said := shot._note.split(":", true, 1)
		PointAndMark.add_note(float(said[0]), said[1].replace("_", " "))
		var shot_studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		if shot_studio != null and shot_studio.get("timeline") != null:
			var tl: TimelineSurface = shot_studio.timeline
			tl.set_view(maxf(float(said[0]) - 24.0, 0.0), 48.0)

	if shot._frames == 5 and shot._posed_hand.size() >= 3:
		shot.scenes._pose_a_hand()
	if shot._posed_gestures != null and is_instance_valid(shot._posed_gestures):
		shot._posed_label.text = shot._posed_gestures.describe()
		if shot._posed_gestures.tracked:
			shot._posed_label.global_position = shot._posed_gestures.joints[HandPose.PALM] + Vector3(0, 0.16, 0)

	if shot._frames == 4 and shot._test_drum:
		shot.scenes._stand_the_test_drum()
	if shot._frames == 8 and shot._cassettes > 0:
		shot.scenes._shelve_cassettes()
	if shot._frames == 8 and shot._samples > 0:
		shot.scenes._make_samples()
	if shot._frames == 8 and shot._platter:
		shot.scenes._slot_the_platter()
	if shot._frames == 8 and shot._sections >= 0:
		shot.scenes._make_the_sections()
	if shot._pads_demo:
		shot.scenes._play_the_pads()
	if shot._frames == 8 and shot._crank > 0:
		shot.scenes._turn_the_crank()
	if shot._frames == 10 and shot._stations > 0:
		var going := shot.get_tree().current_scene.get_node_or_null("Studio")
		if going != null and going.has_method("cycle_stations"):
			for n in shot._stations:
				print("SHOT_STATION ", going.cycle_stations(1))
	if shot._frames == 14 and shot._plaque_rows:
		var at := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
		if at != null and at.venue != null:
			for key in at.venue.find_children("Instruments", "", true, false):
				if key is StationBoard.PlaqueKey and key.station == at.station:
					var hand := Node.new()
					key.grab_begin(hand, key.global_position)
					key.grab_end(hand)
					hand.free()
					print("SHOT_PLAQUE_ROWS ", at.station)
	if shot._frames == 6 and shot._help_page != "":
		var card := shot.get_tree().current_scene.get_node_or_null("Welcome") as WelcomeCard
		if card != null:
			var at := 0
			for n in card.page_names().size():
				if card.page_names()[n].contains(shot._help_page.to_upper()):
					at = n
					break
			card.page = at
			card.open()
			print("SHOT_HELP %s of %s" % [card.page, card.page_names()])


func _process_chords() -> void:
	if shot._frames == 10 and shot._chords >= 0:
		var chords_at := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
		if chords_at != null and chords_at.chord_hand != null:
			chords_at.station_host.go_to_station(&"wheel")
			chords_at.surface_host.toggle_chords()
			chords_at.chord_hand.pick(shot._chords - 1)
			print("SHOT_CHORDS ", chords_at.chord_hand.hud_text())
	if shot._frames == 10 and shot._chord_from >= 1:
		var from_studio := shot.get_tree().current_scene.get_node_or_null("Studio") as Studio
		if from_studio != null and from_studio.jacks != null:
			if not Session.participants.has(7):
				var lin := Session.Participant.new()
				lin.peer_id = 7
				lin.display_name = "Lin"
				lin.colour_index = 2
				Session.participants[7] = lin
				Session.roster_changed.emit()
			from_studio.station_host.go_to_station(&"wheel")
			var source := Jack.chord_source(7)
			from_studio.jacks.plug(source, Jack.player_sink(Session.local_peer_id))
			var key := Harmony.at(DAW.state, DAW.state.position_seconds)
			var chord := ChordHand.chord_for(key, shot._chord_from - 1)
			from_studio.jacks.received(source, Jack.Kind.CHORD, Jack.chord_root(chord), Jack.chord_quality(chord), 7,
					DAW.state.position_seconds)
			print("SHOT_CHORD_FROM ", from_studio.chord_hand.crown_text(key), " | ", from_studio.chord_hand.hud_text())
	if shot._frames == 10 and shot._fingertips >= 0:
		var tips_studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		if tips_studio != null and tips_studio.has_method("toggle_fingertips"):
			tips_studio.toggle_fingertips()
			var keys: KeyCatcher = tips_studio.fingertip_keys
			for physical in KeyCatcher.FINGERS:
				if shot._fingertips & HandPose.FINGER_BITS[KeyCatcher.FINGERS[physical]]:
					keys.handle(physical, true)
	if shot._frames == 10 and shot._plug.contains(":"):
		var plug_studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		if plug_studio != null and plug_studio.has_method("_on_plug_asked"):
			var ends := shot._plug.split(":")
			plug_studio._on_plug_asked(StringName(ends[0]), StringName(ends[1]))

	if shot._frames == 8 and shot._on_air > 0:
		var on_air_studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		if on_air_studio != null and on_air_studio.has_method("_set_on_air"):
			on_air_studio._set_on_air(shot._on_air, true)

	if shot._frames == 8 and shot._tour_band > 1:
		for n in range(2, shot._tour_band + 1):
			var mate := Session.Participant.new()
			mate.peer_id = n
			mate.display_name = "Mate%d" % n
			mate.colour_index = n % Session.PALETTE.size()
			Session.participants[n] = mate
		Session.roster_changed.emit()

	if shot._frames == 9 and shot._tour != "" and shot._tour != "intact":
		Tour.force_state_for_shot(StringName(shot._tour))

	if shot._frames == 9 and not shot._pockets.is_empty():
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		var hand := studio.get_node_or_null("MouseHand") as Interactor if studio else null
		var room: ItemRoom = studio.get("items") if studio else null
		if hand != null and room != null:
			for n in mini(shot._pockets.size(), Pockets.COUNT):
				var item: Item = room.items.get(StringName(shot._pockets[n]))
				if item != null:
					hand.pick_up(item)
					hand.stow(n)
	if not shot._signal.is_empty():
		shot.demos._see_the_signal()
	if shot._frames == 9 and shot._carry != "":
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		var what := shot._carry.split(":")
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


func _process_hands() -> void:
	# `--rc-debug`: where the radio plane is and how it flies, on this machine, every 30 frames --
	# for a guest watching a host fly it.
	if shot._frames % 30 == 0 and OS.get_cmdline_user_args().has("--rc-debug"):
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		var room: ItemRoom = studio.get("items") if studio else null
		var rc := room.items.get(&"rcplane") as RcPlaneItem if room != null else null
		if rc != null:
			print("RCDEBUG f%d mode %d plane %s held_elsewhere %s" % [shot._frames, rc.mode,
					rc.plane.global_position, rc.is_held_elsewhere()])

	# `--carry rcplane:fly`: its motor run up a few frames after the radio is in the hand, so the
	# plane takes off; `:cut@N` cuts the motor on frame N. With --shot-debug, where it is.
	if shot._carry.begins_with("rcplane:"):
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		var room: ItemRoom = studio.get("items") if studio else null
		var rc := room.items.get(&"rcplane") as RcPlaneItem if room != null else null
		if rc != null:
			if shot._frames == 13 and shot._carry.split(":").has("fly"):
				rc.work(true)
			for word in shot._carry.split(":"):
				if word.begins_with("cut@") and shot._frames == int(word.substr(4)):
					rc.work(true)
				# `fly@N`: the motor run up on frame N instead, for a guest who joins later to see.
				if word.begins_with("fly@") and shot._frames == int(word.substr(4)):
					rc.work(true)
			if shot._frames % 20 == 0 and OS.get_cmdline_user_args().has("--shot-debug"):
				print("RCPLANE f%d mode %d at %s speed %.2f slope %.2f" % [shot._frames, rc.mode, rc.at, rc.speed, rc.slope])
				if shot._frames == 20:
					print("RCPLANE floor ", room.floor_rects.call(), " fps ", Engine.get_frames_per_second(), " phys ", Engine.physics_ticks_per_second)

	# `--carry cards:t1@0.8`: the tricks before trick 1 done, and trick 1 stopped 0.8 of the way.
	if shot._frames == 13 and shot._carry.contains(":t") and shot._carry.contains("@"):
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		var room: ItemRoom = studio.get("items") if studio else null
		var what := shot._carry.split(":")
		var fidget := room.items.get(StringName(what[0])) as FidgetItem if room != null else null
		var at := what[1].substr(1).split("@")
		if fidget != null and at.size() == 2:
			for n in int(at[0]):
				fidget.use(true)
				fidget.finish()
			fidget.use(true)
			fidget.set_process(false)
			fidget.pose(fidget.playing, float(at[1]))

	if shot._frames == 28 and shot._carry != "" and OS.get_cmdline_user_args().has("--shot-debug"):
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		var hand := studio.get_node_or_null("MouseHand") as Interactor
		if hand != null and hand.carrying != null:
			print("CARRY item %s glove %s pose %s state %d proc %s" % [hand.carrying.global_position,
					hand._glove.global_position if hand._glove else Vector3.ZERO, hand.carry_pose().origin,
					hand.carrying.state, hand.carrying.is_physics_processing()])

	if shot._bead_aim != "" and shot.driving._scripted_hand() != null and shot._ticks > 2 and shot._ticks < shot._bead_tick:
		var on := shot.driving._screen_of(shot._bead_aim)
		if on.x >= 0.0:
			shot._hover = on
	if shot._aim != "" and shot.driving._scripted_hand() != null and shot._ticks > 2:
		var at := shot.driving._screen_of(shot._aim)
		if at.x >= 0.0:
			shot._hover = at
	var held := shot.driving._scripted_hand() != null and shot.driving._scripted_hand().press_override == 1
	if shot._frames == 10 and shot._look != Vector2.ZERO:
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		if studio and studio.get("walker") != null:
			var w = studio.walker
			w.yaw += shot._look.x
			w.pitch += shot._look.y
			w._place_camera()
	if shot._hover.x >= 0.0 and not held:
		for hand in shot.get_tree().root.find_children("*", "MouseInteractor", true, false):
			(hand as MouseInteractor).pointer_override = shot._hover

	if shot._shot_path != "" and shot._frames == shot._shot_frame:
		_capture()

	if shot._quit_after > 0 and shot._frames >= shot._quit_after:
		shot.get_tree().quit()


func _capture() -> void:
	var image := shot.get_viewport().get_texture().get_image()
	var err := image.save_png(shot._shot_path)
	if err != OK:
		push_error("SHOT_FAILED %s: %s" % [shot._shot_path, error_string(err)])
		return
	# Echoed with the size the engine ACTUALLY rendered. A capture whose dimensions are not
	# stated can be compared against the wrong thing without anyone noticing -- a window manager
	# that packs the window produces a smaller PNG that still looks like a successful shot.
	print("SHOT_SAVED %s %dx%d" % [shot._shot_path, image.get_width(), image.get_height()])


## --spectate's camera, from the moment of a throw.
func _watch_the_throw(studio: Node) -> void:
	if studio != null and shot._spectate.size() == 2:
		var watcher := Camera3D.new()
		watcher.fov = 70.0
		studio.add_child(watcher)
		watcher.look_at_from_position(shot._spectate[0], shot._spectate[1])
		watcher.make_current()
