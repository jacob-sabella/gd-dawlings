extends Node

## Headless test run:  godot --headless --path . tests/tests.tscn
## or:                 tools/verify.sh
##
## What is tested here is everything that FAILS SILENTLY. An OSC message with wrong padding is
## not rejected by Reaper, it is ignored; a room calibration that is a degree off does not error,
## it just puts your console somewhere slightly wrong; a track index off by one moves a different
## fader. None of those announce themselves, and all of them are arithmetic -- which is the kind
## of thing a test can actually pin down.
##
## What is NOT tested here is how any of it looks. That is what tools/shot.sh is for, and no
## amount of green here is evidence that the console reads as a console.

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_test_osc_roundtrip()
	_test_osc_padding()
	_test_osc_bundle()
	_test_osc_rejects_short()
	_test_link_parses_track_fields()
	_test_no_hud_is_a_launch_switch()
	_test_link_parses_fx_and_sends()
	_test_link_ignores_its_own_echo()
	_test_taper_roundtrip()
	_test_volatile_classification()
	_test_host_buffers_split_and_dedupe()
	_test_snapshot_reconstructs_a_guest()
	_test_room_anchor_two_point()
	_test_room_anchor_ignores_height_difference()
	_test_room_anchor_rejects_close_marks()
	_test_layout_defaults()
	_test_master_parsing()
	_test_master_is_not_a_track()
	_test_rig_calibration_gesture()
	_test_rig_tip_is_ahead_of_the_grip()
	_test_ar_studio_draws_no_room()
	_test_handle_is_chrome_not_gear()
	_test_handle_cycle_skips_missing_anchors()
	_test_handle_tap_cycles_and_carry_places()
	_test_timeline_wire_roundtrip()
	_test_timeline_length_covers_the_arrangement()
	_test_timeline_maps_seconds_onto_the_lane()
	_test_arrangement_is_durable_not_volatile()
	_test_timeline_window_scroll_and_zoom()
	_test_timeline_follows_the_playhead_only_while_rolling()
	_test_bank_redefines_what_an_index_means()
	_test_bank_is_stated_before_the_tracks_it_renumbers()
	_test_bank_waits_for_the_hand_to_let_go()
	_test_bank_selector_says_which_tracks_these_are()
	_test_bridge_arrangement_is_parsed()
	_test_knob_is_the_moulded_part()
	_test_the_reels_say_how_far_through_the_song_you_are()
	_test_each_reel_turns_at_its_own_rate()
	_test_the_gear_makes_a_noise()
	_test_the_project_has_a_shape()
	_test_the_studio_fits_in_a_frame()
	_test_many_little_boxes_are_one_object()
	_test_lettering_stops_when_nobody_can_read_it()
	_test_scrolling_the_timeline_does_not_rebuild_it()
	_test_a_surface_showing_a_bank_says_it_is_showing_a_bank()
	_test_an_unfilled_rack_bay_is_blanked_off()
	_test_one_jack_takes_one_plug()
	_test_the_bay_reads_left_to_right()
	_test_dragging_across_the_bay_patches_and_unpatches()
	_test_hovering_a_row_picks_out_its_cables()
	_test_a_removed_send_leaves_the_mix()
	_test_a_plugin_moves_and_copies_along_the_chains()
	_test_wet_and_presets_ride_the_wire()
	_test_a_sidechain_is_a_send_into_the_key()
	_test_a_tablet_is_built_from_its_plugin()
	_test_a_tablet_follows_its_plugin_along_the_chain()
	_test_a_tablet_keys_its_plugin_from_another_track()
	_test_a_plugin_torn_off_the_rack_gets_a_stand()
	_test_the_room_is_the_hosts()
	_test_a_big_plugin_is_listed_and_named_once()
	await _test_a_tablet_pages_by_section_and_steps_the_plugins_own_presets()
	_test_a_tablet_turns_over_to_the_plugins_own_window()
	_test_a_banked_control_still_moves()
	_test_nothing_on_a_faceplate_overlaps_or_overhangs()
	_test_the_rack_holds_one_track_and_follows_the_selection()
	_test_a_person_says_how_tall_they_are()
	_test_the_rack_rebuilds_only_for_its_own_chain()
	_test_a_flood_from_reaper_is_taken_in_over_frames()
	_test_the_tape_leaves_the_pack_where_the_pack_is()
	_test_every_grab_tab_is_clipped_to_its_own_gear()
	_test_a_loom_lies_on_the_floor_and_misses_the_furniture()
	_test_every_light_in_the_room_comes_out_of_something()
	_test_a_body_is_measured_rather_than_assumed()
	_test_the_frame_follows_a_turn_without_chasing_a_glance()
	_test_summoned_gear_lands_where_a_person_can_use_it()
	_test_no_signal_is_carried_by_colour_alone()
	_test_a_control_can_be_worked_without_a_steady_hand()
	_test_a_value_can_be_set_without_a_precise_drag()
	_test_you_can_tell_which_surface_has_your_attention()
	_test_a_surface_cannot_ask_what_it_is_looking_through()
	_test_a_rack_unit_reaches_every_parameter()
	_test_a_wide_desk_bends_round_you_instead_of_past_you()
	_test_the_desk_knows_how_small_its_own_lettering_is()
	_test_every_label_is_set_in_the_distance_field_face()
	_test_fitted_lettering_stays_in_its_slot()
	_test_footprints_separate_by_the_shallowest_way_out()
	_test_furniture_rolls_where_it_is_pushed()
	_test_furniture_is_solid()
	_test_the_wheel_turns_furniture_only_while_held()
	_test_a_summoned_surface_goes_home_to_where_its_stand_went()
	_test_a_monitor_goes_to_the_gear_and_leaves_the_room_alone()
	_test_no_two_faces_in_the_room_share_a_plane()
	_test_venues_change_the_world_and_not_the_setup()
	_test_every_venue_leaves_room_for_the_activities()
	_test_gear_never_leaves_its_stand()
	await _test_you_walk_into_the_room_and_not_through_it()
	await _test_every_control_is_clickable_from_the_seat()
	_test_the_room_is_laid_out_for_the_size_of_the_session()
	_test_the_transport_is_driven_from_the_desk()
	_test_the_ruler_moves_the_playhead_and_draws_the_loop()
	_test_items_are_edited_on_the_timeline()
	_test_a_late_arrangement_is_still_fitted()
	_test_a_late_timeline_poll_does_not_undo_an_edit()
	_test_undo_takes_back_a_gesture_not_a_frame()
	_test_the_tempo_is_set_from_the_deck()
	_test_the_sends_ride_the_faders()
	_test_the_click_is_switched_from_the_deck()
	_test_markers_are_dropped_and_found_from_the_deck()
	_test_input_monitoring_is_set_from_the_strip()
	_test_the_built_in_engine_is_a_real_mix()
	_test_the_demo_song_loops_on_the_bar()
	_test_a_recorded_take_is_a_wav_with_an_overview()
	_test_the_host_places_an_audio_take()
	_test_a_guest_microphone_stays_on_the_song()
	_test_the_built_in_engine_plays_a_recorded_take()
	_test_a_guest_sets_up_their_microphone_from_the_panel()
	_test_a_recorded_take_shows_its_waveform_on_the_timeline()
	_test_reaper_hears_the_transport_in_its_own_words()
	_test_a_bank_wider_than_the_project_draws_only_the_project()
	_test_the_room_gets_out_of_the_way_of_the_gear_that_left_it()
	_test_the_desk_is_lit_evenly_end_to_end()
	_test_focused_gear_fits_the_frame_it_is_shown_in()
	_test_every_control_says_what_it_is()
	_test_hover_is_counted_per_interactor()
	_test_the_rim_brackets_what_the_cursor_can_hit()
	_test_a_monitor_draws_no_presentation_brackets()
	_test_the_wheel_adjusts_what_the_cursor_is_on()
	_test_a_cursor_drags_a_knob_up_and_down()
	_test_a_released_control_ignores_its_own_late_echoes()
	_test_a_surface_never_rebuilds_under_a_hand()
	_test_the_mix_survives_the_wire()
	_test_the_jitter_buffer_rides_out_a_bad_network()
	_test_the_jitter_buffer_follows_a_drifting_clock()
	_test_the_jitter_buffer_fills_losses_and_drops_the_late()
	_test_the_jitter_buffer_feeds_a_mixer_that_gulps()
	_test_the_room_keeps_listening_across_a_change_of_backend()
	_test_a_session_code_is_a_door()
	_test_a_restated_project_size_is_not_a_new_bank()
	_test_a_control_held_elsewhere_refuses_hands_but_still_moves()
	_test_the_roster_is_the_hosts_word()
	_test_the_host_keeps_one_hand_per_control()
	_test_presence_marks_what_others_hold()
	_test_a_ghost_is_the_size_of_a_large_person()
	_test_a_glove_flies_with_a_bounce()
	_test_a_ghosts_hand_goes_to_what_they_touch()
	_test_a_look_is_kept_and_cleaned()
	_test_the_roster_carries_what_everyone_wears()
	_test_a_ghost_wears_its_look()
	_test_the_wardrobe_changes_my_look()
	_test_a_mirror_shows_the_room_reversed()
	_test_every_venue_has_a_mirror_you_can_see_yourself_in()
	_test_meters_go_out_in_parcels_under_the_mtu()
	_test_the_mix_carries_the_song_position()
	_test_the_song_clock_runs_between_reports()
	_test_the_guest_knows_which_moment_it_is_hearing()
	_test_the_jitter_buffer_knows_which_host_frame_is_next()
	_test_a_take_is_assembled_from_stamped_notes()
	_test_a_take_from_a_peer_is_cleaned_before_it_lands()
	_test_a_take_lands_on_the_stand_in_and_comes_off_again()
	_test_notes_ride_the_wire_with_their_item()
	_test_reaper_is_asked_for_a_take_in_one_flat_call()
	_test_the_monitor_piano_sounds_decays_and_shares_its_voices()
	_test_the_computer_keys_are_a_piano_by_position()
	_test_a_guest_take_follows_the_host_transport_it_hears()
	_test_the_host_places_a_guest_take_and_says_so()
	_test_midi_items_show_their_notes_on_the_timeline()

	print("\n%d checks, %d failed" % [_checks, _failures.size()])
	for f in _failures:
		print("  FAIL  %s" % f)
	get_tree().quit(1 if _failures.size() > 0 else 0)


func check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func close_to(label: String, a: float, b: float, epsilon: float = 0.0001) -> void:
	_checks += 1
	if absf(a - b) > epsilon:
		_failures.append("%s (got %.6f, wanted %.6f)" % [label, a, b])


# --- OSC ----------------------------------------------------------------------------------

func _test_osc_roundtrip() -> void:
	var packet := OSC.message("/track/3/volume", [0.625])
	var decoded := OSC.decode(packet)
	check("roundtrip yields one message", decoded.size() == 1)
	check("roundtrip keeps address", decoded[0]["address"] == "/track/3/volume")
	close_to("roundtrip keeps float", decoded[0]["args"][0], 0.625)

	var mixed := OSC.decode(OSC.message("/mix", [7, 0.5, "Lead Vox"]))
	check("int survives", mixed[0]["args"][0] == 7)
	close_to("float survives", mixed[0]["args"][1], 0.5)
	check("string survives", mixed[0]["args"][2] == "Lead Vox")


## Every OSC chunk is a multiple of four bytes, and a string that already lands on a boundary
## still gets a full four bytes of padding because its null terminator must be inside the pad.
## Reaper does not complain about a packet that gets this wrong -- it drops it, which from the
## outside is indistinguishable from the wrong port number.
func _test_osc_padding() -> void:
	for address in ["/a", "/ab", "/abc", "/abcd", "/abcde", "/track/12/vu"]:
		var packet := OSC.message(address, [])
		check("packet for %s is 4-byte aligned" % address, packet.size() % 4 == 0)
		var decoded := OSC.decode(packet)
		check("address %s survives padding" % address, decoded.size() == 1 and decoded[0]["address"] == address)

	# "/abcd" is 5 bytes; +1 null = 6; padded to 8. Plus "," padded to 4 = 12 total.
	check("boundary-length address pads to a whole extra word", OSC.message("/abcd", []).size() == 12)


## Reaper coalesces a bank of meter updates into one bundle. A decoder that returns only the
## first message makes channel 1 move and leaves the other 63 still.
func _test_osc_bundle() -> void:
	var inner_a := OSC.message("/track/1/vu", [0.5])
	var inner_b := OSC.message("/track/2/vu", [0.25])
	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_data("#bundle".to_utf8_buffer())
	buf.put_u8(0)
	buf.put_32(0)
	buf.put_32(1)
	for inner in [inner_a, inner_b]:
		buf.put_32(inner.size())
		buf.put_data(inner)

	var decoded := OSC.decode(buf.data_array)
	check("bundle yields both messages", decoded.size() == 2)
	if decoded.size() == 2:
		check("first bundled address", decoded[0]["address"] == "/track/1/vu")
		check("second bundled address", decoded[1]["address"] == "/track/2/vu")
		close_to("second bundled value", decoded[1]["args"][0], 0.25)


func _test_osc_rejects_short() -> void:
	check("empty packet decodes to nothing", OSC.decode(PackedByteArray()).is_empty())
	check("runt packet decodes to nothing", OSC.decode(PackedByteArray([1, 2])).is_empty())


# --- link ---------------------------------------------------------------------------------

## A ReaperBackend on its own, with no socket. Everything these tests exercise -- parsing, the
## echo guard, the replication split -- happens before a packet would ever leave, so there is
## nothing to open and nothing to mock.
func _fresh_link() -> ReaperBackend:
	var link := ReaperBackend.new()
	add_child(link)
	return link


## A photograph has no debugging readout in its corner; an ordinary launch keeps it.
func _test_no_hud_is_a_launch_switch() -> void:
	var boot: Node = load("res://scenes/bootstrap.gd").new()
	check("an ordinary launch has the corner readout", not boot._parse(PackedStringArray([]))["no_hud"])
	check("--no-hud leaves it out", boot._parse(PackedStringArray(["--no-hud"]))["no_hud"])
	boot.free()


func _test_link_parses_track_fields() -> void:
	var link := _fresh_link()
	link._apply("/track/4/name", ["Bass DI"])
	link._apply("/track/4/volume", [0.8])
	link._apply("/track/4/volume/db", [-3.5])
	link._apply("/track/4/pan", [0.25])
	link._apply("/track/4/mute", [1.0])
	link._apply("/track/4/solo", [0.0])
	link._apply("/track/4/recarm", [1.0])
	link._apply("/track/4/vu/L", [0.6])
	link._apply("/track/4/vu/R", [0.4])

	var t = link.state.track(4)
	check("name parsed", t.name == "Bass DI")
	close_to("volume parsed", t.volume, 0.8)
	close_to("volume_db parsed", t.volume_db, -3.5)
	close_to("pan parsed", t.pan, 0.25)
	check("mute parsed as true", t.mute)
	check("solo parsed as false", not t.solo)
	check("recarm parsed", t.rec_arm)
	close_to("vu left parsed", t.vu_l, 0.6)
	close_to("vu right parsed", t.vu_r, 0.4)

	# Reaper addresses tracks from 1. A message about track 4 must not touch track 3 or 5.
	check("neighbouring track untouched", link.state.track(3, false) == null)
	link.free()


func _test_link_parses_fx_and_sends() -> void:
	var link := _fresh_link()
	link._apply("/track/2/fx/1/name", ["ReaComp"])
	link._apply("/track/2/fx/1/bypass", [1.0])
	link._apply("/track/2/fx/1/fxparam/3/value", [0.42])
	link._apply("/track/2/fx/1/fxparam/3/name", ["Ratio"])
	link._apply("/track/2/send/0/name", ["Verb Rtn"])
	link._apply("/track/2/send/0/volume", [0.33])

	var f = link.state.fx(2, 1)
	check("fx name parsed", f.name == "ReaComp")
	check("fx bypass means ENABLED in Reaper's wording", f.enabled)
	close_to("fx param value parsed", f.params[3], 0.42)
	check("fx param name parsed", f.param_names[3] == "Ratio")

	# The plugin's own reading rides beside the number and must not be mistaken for it: a
	# "-12.0 dB" read as a float is -12, a normalised value nineteen times off the end.
	link._apply("/track/2/fx/1/fxparam/3/value/str", ["4.0:1"])
	check("fx param text parsed", f.param_text.get(3) == "4.0:1")
	close_to("and the value it sits beside is untouched", f.params[3], 0.42)
	link._apply("/track/2/fx/1/fxparam/3/value/str", ["-12.0 dB", 0.25])
	close_to("text read through the bridge carries the value it was read at",
			float(f.param_text_at.get(3, -1.0)), 0.25)
	check("a guest is sent both", MixWire.snapshot(link.state).any(func(m):
			return m[0] == "/track/2/fx/1/fxparam/3/value/str" and m[1] == ["-12.0 dB", 0.25]))

	# A knob's caption is its name, so a name that arrives later has to say so.
	var told := [0]
	var count := func(_t, _f): told[0] += 1
	link.state.fx_changed.connect(count)
	link._apply("/track/2/fx/1/fxparam/3/name", ["Ratio"])
	check("a name that has not changed tells nobody", told[0] == 0)
	link._apply("/track/2/fx/1/fxparam/4/name", ["Knee"])
	check("a new name is announced", told[0] == 1)
	link.state.fx_changed.disconnect(count)

	# OSC names only the parameters of the track selected in Reaper; the bridge's slow poll
	# names the rest, onto the same addresses, 0-based from Lua and 1-based on the wire.
	link._on_structure({"tracks": [{"index": 5, "fx": [{"index": 0, "name": "ReaEQ",
			"param_names": ["Freq-Low Shelf", "Gain-Low Shelf"]}]}], "track_count": 5})
	var eq = link.state.fx(5, 1, false)
	check("the bridge names every track's parameters (%s)" % (eq.param_names if eq else "no fx"),
			eq != null and eq.param_names.get(1) == "Freq-Low Shelf" and eq.param_names.get(2) == "Gain-Low Shelf")

	var s = link.state.send(2, 0)
	check("send destination parsed", s.dest_name == "Verb Rtn")
	close_to("send volume parsed", s.volume, 0.33)
	link.free()


## Reaper echoes every change back. Without the guard, a fader being dragged receives its own
## previous value one frame later and visibly fights the hand holding it.
func _test_link_ignores_its_own_echo() -> void:
	var link := _fresh_link()
	link._apply("/track/1/volume", [0.2])
	link._echo_guard["/track/1/volume"] = {"v": [0.9], "t": Time.get_ticks_msec()}
	link._apply("/track/1/volume", [0.9])
	close_to("echo of our own write is ignored", link.state.track(1).volume, 0.2)

	# A value we did NOT write must still get through, or the guard would deafen the surface to
	# someone moving the same fader in Reaper's own mixer.
	link._apply("/track/1/volume", [0.55])
	close_to("a different value still applies", link.state.track(1).volume, 0.55)
	link.free()


func _test_taper_roundtrip() -> void:
	for db in [-24.0, -12.0, -6.0, 0.0, 6.0]:
		close_to("taper round-trips %.0fdB" % db, DAW.taper_to_db(DAW.backend.db_to_taper(db)), db, 0.001)
	check("silence is -inf", DAW.taper_to_db(0.0) == -INF)
	# What Reaper itself reported on /track/n/volume for each of these, measured on a live rig.
	# A fader cap labelled from any other curve tells you a number Reaper does not agree with.
	var reaper := {12.0: 1.0, 6.0: 0.8523, 0.0: 0.716, -6.0: 0.5928, -12.0: 0.4839,
			-24.0: 0.3133, -40.0: 0.1710, -60.0: 0.0795, -90.0: 0.0251, -120.0: 0.00795}
	for db in reaper:
		close_to("Reaper puts %.0f dB at %.4f of travel" % [db, reaper[db]],
				DAW.db_to_taper(db), reaper[db], 0.0006)
		close_to("and %.4f of travel reads %.0f dB" % [reaper[db], db],
				DAW.taper_to_db(reaper[db]), db, 0.02 if db > -60.0 else 0.1)


# --- replication --------------------------------------------------------------------------

## Meters and the playhead go out unreliably; everything else must not. Getting this backwards
## is invisible on a loopback test and ruinous on real wifi -- either names arrive late behind a
## queue of stale meter readings, or they are dropped and never resent.
func _test_volatile_classification() -> void:
	var link := _fresh_link()
	for address in ["/track/3/vu", "/track/3/vu/L", "/track/12/vu/R", "/time", "/time/str"]:
		check("%s is volatile" % address, link.is_volatile(address))
	for address in ["/track/3/name", "/track/3/volume", "/track/3/mute",
			"/track/3/fx/1/fxparam/2/value", "/tempo/raw", "/play"]:
		check("%s is durable" % address, not link.is_volatile(address))
	link.free()


## The buffers are keyed by address so that 30Hz of meter updates collapse into one value per
## tick. Without that, a 32-track project would replicate ~1000 messages a second to every guest
## to convey 32 numbers.
func _test_host_buffers_split_and_dedupe() -> void:
	var link := _fresh_link()
	link._apply("/track/1/vu", [0.1])
	link._apply("/track/1/vu", [0.2])
	link._apply("/track/1/vu", [0.3])
	link._apply("/track/1/name", ["Kick"])
	link._apply("/track/1/volume", [0.5])
	link._apply("/track/1/volume", [0.7])

	check("meter collapses to one pending entry", link._repl_volatile.size() == 1)
	close_to("meter keeps the newest value", link._repl_volatile["/track/1/vu"][0], 0.3)
	check("two durable addresses pending", link._repl_durable.size() == 2)
	close_to("durable keeps the newest value", link._repl_durable["/track/1/volume"][0], 0.7)
	check("meters are not in the durable buffer", not link._repl_durable.has("/track/1/vu"))
	link.free()


## A guest built only from a snapshot must be indistinguishable from the host. This is the test
## the whole multi-user design rests on, and its failure mode is quiet: a missing field does not
## error, it just leaves one guest looking at a console that is subtly not the session.
func _test_snapshot_reconstructs_a_guest() -> void:
	var host := OfflineBackend.new()
	add_child(host)
	host.open()
	host.set_process(false)

	var guest := _fresh_link()
	guest.is_authority = false
	guest.apply_replicated(host.snapshot())

	check("guest has every track", guest.state.track_indices() == host.state.track_indices())
	# Against the host rather than against a literal. The count was hard-coded, and the demo
	# gaining two bus tracks broke a check that was never about how many tracks there are.
	check("guest got some tracks at all",
			guest.state.tracks.size() == host.state.tracks.size() and guest.state.tracks.size() > 0)

	for index in host.state.track_indices():
		var h: MixState.TrackState = host.state.tracks[index]
		var g: MixState.TrackState = guest.state.track(index, false)
		if g == null:
			check("guest has track %d" % index, false)
			continue
		check("track %d name" % index, g.name == h.name)
		close_to("track %d volume" % index, g.volume, h.volume)
		close_to("track %d pan" % index, g.pan, h.pan)
		check("track %d mute" % index, g.mute == h.mute)
		check("track %d solo" % index, g.solo == h.solo)
		check("track %d recarm" % index, g.rec_arm == h.rec_arm)
		# Colour is reaper-3d's own address, not Reaper's. It is the thing that makes a strip
		# findable on a wide desk, so a guest losing it is a real regression rather than cosmetic.
		close_to("track %d colour r" % index, g.colour.r, h.colour.r, 0.002)
		close_to("track %d colour g" % index, g.colour.g, h.colour.g, 0.002)
		close_to("track %d colour b" % index, g.colour.b, h.colour.b, 0.002)
		check("track %d fx count" % index, g.fx.size() == h.fx.size())
		for fx_index in h.fx:
			var hf: MixState.FXState = h.fx[fx_index]
			var gf = g.fx.get(fx_index)
			if gf == null:
				check("track %d fx %d present" % [index, fx_index], false)
				continue
			check("track %d fx %d name" % [index, fx_index], gf.name == hf.name)
			check("track %d fx %d param count" % [index, fx_index], gf.params.size() == hf.params.size())
			for param in hf.params:
				close_to("track %d fx %d param %d" % [index, fx_index, param], gf.params[param], hf.params[param])
			for param in hf.param_names:
				check("track %d fx %d param %d name" % [index, fx_index, param], gf.param_names.get(param) == hf.param_names[param])
		check("track %d send count" % index, g.sends.size() == h.sends.size())
		for send_index in h.sends:
			var hs: MixState.SendState = h.sends[send_index]
			var gs = g.sends.get(send_index)
			if gs == null:
				check("track %d send %d present" % [index, send_index], false)
				continue
			check("track %d send %d dest" % [index, send_index], gs.dest_name == hs.dest_name)
			close_to("track %d send %d volume" % [index, send_index], gs.volume, hs.volume)

	close_to("tempo replicated", guest.state.tempo, host.state.tempo)
	check("transport replicated", guest.state.playing == host.state.playing)

	# Meters are deliberately absent from a snapshot: they are level-triggered and the next
	# volatile tick carries them 50ms later. A snapshot that included them would be shipping a
	# value already stale on arrival.
	check("snapshot carries no meter readings", guest.state.track(1).vu_l == 0.0)
	host.free()
	guest.free()


# --- co-location --------------------------------------------------------------------------

## Two people marking the same two pieces of tape must land on the same frame. This is the
## arithmetic the whole shared-room premise rests on, and it is invisible when wrong: everything
## renders, it is just in the wrong place for one of them.
func _test_room_anchor_two_point() -> void:
	var anchor := RoomAnchor.new()
	add_child(anchor)
	anchor.mark_origin(Vector3(2.0, 0.0, 1.0))
	check("two-point calibration succeeds", anchor.mark_forward(Vector3(3.2, 0.0, 1.0)))
	check("anchor reports calibrated", anchor.is_calibrated)
	close_to("span measured", anchor.session_span, 1.2)

	# The first mark is the session origin.
	var origin_in_world: Vector3 = anchor.world_from_session(Vector3.ZERO)
	close_to("origin x", origin_in_world.x, 2.0)
	close_to("origin z", origin_in_world.z, 1.0)

	# The second mark lies on session +X, at the measured span.
	var second_in_session: Vector3 = anchor.session_from_world(Vector3(3.2, 0.0, 1.0))
	close_to("second mark is on +X", second_in_session.x, 1.2, 0.001)
	close_to("second mark has no y", second_in_session.y, 0.0, 0.001)
	close_to("second mark has no z", second_in_session.z, 0.0, 0.001)
	anchor.free()


## The two marks are placed by hand and are never at the same height. If that tilt reached the
## frame, the whole studio would rotate a degree or two about the horizontal -- which over a 2m
## console is several centimetres of disagreement at the far end.
func _test_room_anchor_ignores_height_difference() -> void:
	var level := RoomAnchor.new()
	add_child(level)
	level.mark_origin(Vector3.ZERO)
	level.mark_forward(Vector3(1.0, 0.0, 0.0))

	var tilted := RoomAnchor.new()
	add_child(tilted)
	tilted.mark_origin(Vector3.ZERO)
	tilted.mark_forward(Vector3(1.0, 0.06, 0.0))

	var a: Vector3 = level.world_from_session(Vector3(0.0, 0.0, -1.0))
	var b: Vector3 = tilted.world_from_session(Vector3(0.0, 0.0, -1.0))
	close_to("a 6cm height difference does not tilt the frame", a.distance_to(b), 0.0, 0.0005)
	level.free()
	tilted.free()


func _test_room_anchor_rejects_close_marks() -> void:
	var anchor := RoomAnchor.new()
	add_child(anchor)
	anchor.mark_origin(Vector3.ZERO)
	check("marks 10cm apart are refused", not anchor.mark_forward(Vector3(0.1, 0.0, 0.0)))
	check("a refused calibration leaves the anchor uncalibrated", not anchor.is_calibrated)
	anchor.free()


# --- presentation -------------------------------------------------------------------------

func _test_layout_defaults() -> void:
	var profile := LayoutProfile.new()

	profile.medium = Presentation.Medium.AR
	check("in AR, hardware stands in the room", profile.mode_for(&"console", &"console") == Presentation.Mode.ROOM)
	check("in AR, the timeline stays on a screen", profile.mode_for(&"timeline", &"timeline") == Presentation.Mode.SCREEN)

	profile.medium = Presentation.Medium.VR
	check("in VR, hardware is in the virtual set", profile.mode_for(&"console", &"console") == Presentation.Mode.STUDIO)

	profile.medium = Presentation.Medium.SCREEN
	check("on a monitor, hardware is in the virtual set", profile.mode_for(&"rack", &"rack") == Presentation.Mode.STUDIO)

	# An explicit choice beats every default. This is the line that makes a hybrid session
	# possible at all: one participant overriding what everyone else sees by default.
	profile.set_mode(&"console", Presentation.Mode.SCREEN)
	check("an explicit mode overrides the default", profile.mode_for(&"console", &"console") == Presentation.Mode.SCREEN)


# --- xr rig -------------------------------------------------------------------------------

## The gesture, driven directly rather than through a controller, because there is no runtime in
## a test run and the thing worth pinning down is the state machine, not the button.
func _test_rig_calibration_gesture() -> void:
	var rig := XRRig.new()
	add_child(rig)
	var anchor := RoomAnchor.new()
	add_child(anchor)
	rig.room_anchor = anchor

	rig._take_mark()
	check("one mark does not calibrate", not anchor.is_calibrated)

	# Too close: the second mark is refused, and the rig must STAY on step one so the next press
	# retries it. Advancing here would leave the participant pressing for a third mark that
	# silently starts a new calibration instead.
	rig.left = null
	anchor.mark_origin(Vector3.ZERO)
	check("a refused forward mark is refused", not anchor.mark_forward(Vector3(0.08, 0, 0)))

	anchor.mark_origin(Vector3.ZERO)
	check("two marks 1.2m apart calibrate", anchor.mark_forward(Vector3(0, 0, -1.2)))
	check("the agreed span is the distance between the marks", absf(anchor.session_span - 1.2) < 0.001)

	rig.free()
	anchor.free()


## The tip offset is the difference between calibrating against a floor mark and calibrating
## against the user's fist, which is most of a hand's error in the shared frame.
func _test_rig_tip_is_ahead_of_the_grip() -> void:
	check("the tip is ahead of the grip", XRRig.TIP_OFFSET.z < -0.02)
	check("the tip is below the grip", XRRig.TIP_OFFSET.y < 0.0)


## An AR participant is standing in a real room. Building a virtual floor over it is not a
## degraded VR experience, it is a wrong one, and nothing about it errors.
func _test_ar_studio_draws_no_room() -> void:
	var ar := Studio.new()
	ar.medium = Presentation.Medium.AR
	add_child(ar)
	check("in AR there is no desktop camera", ar.camera == null)
	check("in AR there is an xr rig", ar.rig != null)
	check("in AR the room frame is not guessed", not ar.room_anchor.is_calibrated)
	check("in AR no floor is drawn", _count_meshes(ar) == 0)

	var desk := Studio.new()
	desk.medium = Presentation.Medium.SCREEN
	add_child(desk)
	check("on a monitor there is a camera", desk.camera != null)
	check("on a monitor the frame is adopted so the layout is usable", desk.room_anchor.is_calibrated)
	check("on a monitor the room is drawn", desk.venue != null and _count_meshes(desk.venue) > 0)
	check("in AR no venue is stood in", ar.venue == null)

	ar.queue_free()
	desk.queue_free()


## Direct children only: the floor and the back wall. Furniture hangs off studio_set and the
## surfaces build their own meshes, so counting the whole subtree would measure the console.
func _count_meshes(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			n += 1
	return n


# --- master bus ---------------------------------------------------------------------------

func _test_master_parsing() -> void:
	var link := _fresh_link()
	link._apply("/master/volume", [0.5])
	close_to("master volume is the taper as sent", link.state.master.volume, 0.5, 0.0001)
	close_to("master dB is derived from the taper", link.state.master.volume_db,
			DAW.taper_to_db(0.5), 0.0001)

	link._apply("/master/volume/db", [-3.5])
	close_to("an explicit dB overrides the derived one", link.state.master.volume_db, -3.5, 0.0001)

	link._apply("/master/pan", [0.42])
	close_to("master pan", link.state.master.pan, 0.42, 0.0001)

	link._apply("/master/vu/L", [0.8])
	link._apply("/master/vu/R", [0.3])
	close_to("master vu left", link.state.master.vu_l, 0.8, 0.0001)
	close_to("master vu right", link.state.master.vu_r, 0.3, 0.0001)

	# A device configured with MASTER_VU and not the split pair sends one number. Taking it as
	# left only would leave the right half of the bus meter dead with nothing to explain why.
	link._apply("/master/vu", [0.55])
	close_to("a mono master vu fills both channels (L)", link.state.master.vu_l, 0.55, 0.0001)
	close_to("a mono master vu fills both channels (R)", link.state.master.vu_r, 0.55, 0.0001)
	link.free()


## The master is not track zero, and nothing that walks the track list may pick it up -- the one
## that forgets puts a MASTER strip on the console twice, or a MASTER jack on the patchbay.
func _test_master_is_not_a_track() -> void:
	var link := _fresh_link()
	var before := link.state.tracks.size()
	link._apply("/master/volume", [0.6])
	check("a master message creates no track", link.state.tracks.size() == before)

	var addresses: Array = []
	for entry in link.snapshot():
		addresses.append(entry[0])
	check("the snapshot carries the master volume", "/master/volume" in addresses)
	check("the snapshot carries the master pan", "/master/pan" in addresses)
	link.free()


# --- the in-world grab handle -------------------------------------------------------------

## A surface that is one 20cm cube, so every number below is checkable by hand.
class BoxSurface extends Surface:
	func _rebuild() -> void:
		_clear_built()
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.2, 0.2, 0.2)
		m.mesh = box
		_adopt(m)


## An interactor whose aim is whatever the test says it is.
class FakeHand extends Interactor:
	var pose := Transform3D.IDENTITY
	var holding_shift := false
	func aim() -> Transform3D:
		return pose
	func fine() -> bool:
		return holding_shift


## Builds a mount with the anchors named in `modes`, one registered BoxSurface, and a throwaway
## layout profile so the run does not overwrite the layout of whoever is running the tests.
func _fake_mount(modes: Array) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var mount := SurfaceMount.new()
	root.add_child(mount)
	for mode in modes:
		var anchor := Node3D.new()
		mount.add_child(anchor)
		match mode:
			Presentation.Mode.SCREEN: mount.screen_stage = anchor
			Presentation.Mode.ROOM: mount.room_anchor = anchor
			Presentation.Mode.STUDIO: mount.studio_set = anchor

	var surface := BoxSurface.new()
	surface.surface_id = &"box"
	surface.surface_kind = &"console"
	mount.add_child(surface)

	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	mount.register(surface)
	# Surfaces build on the next _process, and every number the handle needs comes from the
	# geometry, so the test has to let that frame happen rather than reading an empty box.
	surface._process(0.0)
	return {"root": root, "mount": mount, "surface": surface, "saved_layout": saved_layout}


func _drop_mount(rig: Dictionary) -> void:
	Session.layout = rig["saved_layout"]
	rig["root"].queue_free()


## The handle hangs off the surface and travels with it, but a surface framed to fill a monitor
## must not measure its own handle: the handle is placed from that measurement, so counting it
## would grow the box, which moves the handle, which grows the box again.
func _test_handle_is_chrome_not_gear() -> void:
	var rig := _fake_mount([Presentation.Mode.SCREEN, Presentation.Mode.ROOM, Presentation.Mode.STUDIO])
	var surface: Surface = rig["surface"]
	var handle := (rig["mount"] as SurfaceMount).handle_for(&"box")

	check("registering a surface builds it a handle", handle != null)
	check("the handle rides on the surface", handle.get_parent() == surface)

	var bounds := surface.content_aabb()
	close_to("the measured width is the gear, not the gear plus a tab", bounds.size.x, 0.2, 0.001)
	check("the handle sits outside the gear", handle.position.x > bounds.end.x)
	check("the handle is within a hand's reach of the corner", handle.position.x - bounds.end.x < 0.05)

	_drop_mount(rig)


## An AR participant has no virtual set. A tap that parked the console in a studio nobody is
## drawing would make it vanish with no handle left to tap.
func _test_handle_cycle_skips_missing_anchors() -> void:
	var rig := _fake_mount([Presentation.Mode.SCREEN, Presentation.Mode.ROOM])
	var mount: SurfaceMount = rig["mount"]

	check("a mode with no anchor is not offered", not mount.available_modes().has(Presentation.Mode.STUDIO))
	check("the two anchored modes are", mount.available_modes().size() == 2)

	mount.set_mode(&"box", Presentation.Mode.SCREEN)
	check("screen cycles to room", mount.next_mode(&"box") == Presentation.Mode.ROOM)
	mount.set_mode(&"box", Presentation.Mode.ROOM)
	check("room wraps back to screen, not into the missing studio",
			mount.next_mode(&"box") == Presentation.Mode.SCREEN)

	_drop_mount(rig)


## The two gestures the handle has to tell apart, and the thing that goes wrong if it cannot:
## a tap that drifts is a mode switch that also silently nudges the gear, and a carry that
## reads as a tap throws the surface to another anchor mid-drag.
func _test_handle_tap_cycles_and_carry_places() -> void:
	var rig := _fake_mount([Presentation.Mode.SCREEN, Presentation.Mode.ROOM, Presentation.Mode.STUDIO])
	var mount: SurfaceMount = rig["mount"]
	var surface: Surface = rig["surface"]
	var handle := mount.handle_for(&"box")

	var hand := FakeHand.new()
	hand.set_physics_process(false)
	rig["root"].add_child(hand)

	mount.set_mode(&"box", Presentation.Mode.ROOM)
	var before := mount.mode_of(&"box")
	var resting := surface.global_position

	# A tap: held, jittered by less than the slop, released.
	handle.grab_begin(hand, handle.global_position)
	hand.pose = Transform3D(Basis.IDENTITY, Vector3(0, SurfaceHandle.TAP_SLOP * 0.4, 0))
	handle.grab_move(hand, handle.global_position)
	handle.grab_end(hand)

	check("a tap moves the surface to the next mode", mount.mode_of(&"box") != before)
	check("a tap leaves no drift behind",
			surface.global_position.distance_to(resting) < 0.0001)
	check("a tap stores no placement",
			not Session.layout.has_transform(&"box", before))

	# A carry: held and moved well past the slop.
	var carried_mode := mount.mode_of(&"box")
	handle.grab_begin(hand, handle.global_position)
	hand.pose = Transform3D(Basis.IDENTITY, Vector3(0.35, 0, 0))
	handle.grab_move(hand, handle.global_position)
	handle.grab_end(hand)

	check("a carry does not also switch modes", mount.mode_of(&"box") == carried_mode)
	check("a carry moves the surface", surface.global_position.distance_to(resting) > 0.1)
	check("a carry is remembered for the mode it happened in",
			Session.layout.has_transform(&"box", carried_mode))
	check("and not for any other mode",
			not Session.layout.has_transform(&"box", mount.next_mode(&"box")))

	_drop_mount(rig)


# --- the arrangement ----------------------------------------------------------------------

func _item(start: float, length: float, name: String, muted := false) -> MixState.ItemState:
	var i := MixState.ItemState.new()
	i.start = start
	i.length = length
	i.name = name
	i.muted = muted
	return i


## Items ride the same wire as everything else, so a guest gets the arrangement for free -- but
## only if the packing survives the trip. A silently truncated lane draws blocks that are the
## right colour in the wrong bars, which looks like a correct timeline of a different song.
func _test_timeline_wire_roundtrip() -> void:
	var here := MixState.new()
	here.set_track_items(3, [_item(0.0, 8.0, "Kick Intro"), _item(16.0, 32.0, "Kick Verse", true)])
	here.set_project_length(192.0)
	here.markers = {0.0: "Intro", 16.0: "Verse 1"}

	var there := MixState.new()
	MixWire.apply_replicated(there, MixWire.snapshot(here))
	var items: Array = there.track(3).items

	check("both items arrive", items.size() == 2)
	close_to("the first starts where it started", items[0].start, 0.0)
	close_to("the second starts where it started", items[1].start, 16.0)
	close_to("length survives", items[1].length, 32.0)
	check("a name with a space in it survives", items[0].name == "Kick Intro")
	check("muted survives", items[1].muted and not items[0].muted)
	close_to("the project length survives", there.project_length, 192.0)
	check("the markers survive", there.markers.size() == 2 and there.markers[16.0] == "Verse 1")


## The ruler divides by this, and a timeline is routinely asked for its length before any
## backend has said anything about one.
func _test_timeline_length_covers_the_arrangement() -> void:
	var state := MixState.new()
	check("an empty project still has a drawable length", state.timeline_length() >= 1.0)

	state.set_project_length(100.0)
	close_to("the stated length is used", state.timeline_length(), 100.0)

	# A DAW can report a project shorter than the thing on it -- dragging an item past the end
	# is how a song gets longer -- and a ruler that believed the stated length would draw the
	# last block running off the panel.
	state.set_track_items(1, [_item(80.0, 40.0, "Outro")])
	close_to("an item past the end extends the ruler", state.timeline_length(), 120.0)

	state.set_track_items(2, [_item(30.0, 4.0, "Late"), _item(5.0, 4.0, "Early")])
	close_to("items are kept in start order", state.track(2).items[0].start, 5.0)


## The one piece of arithmetic on this surface: seconds to a position across the lane area.
## Off-by-a-margin here puts every block in the wrong bar, which nothing errors about.
func _test_timeline_maps_seconds_onto_the_lane() -> void:
	var previous := DAW.backend
	DAW.use(OfflineBackend.new())

	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)

	var span := DAW.state.timeline_length()
	var left := timeline._lane_area_x
	var right := left + timeline._lane_area_width

	check("the lane area is to the right of the track headers",
			left > -TimelineSurface.WIDTH * 0.5)
	close_to("the start of the song is the start of the lane", timeline._x_for(0.0), left)
	close_to("the end of the song is the end of the lane", timeline._x_for(span), right)
	close_to("halfway is halfway", timeline._x_for(span * 0.5), (left + right) * 0.5, 0.0005)
	# Unclamped on purpose. Clamping here would pile everything before the window onto the left
	# edge and everything after it onto the right, as stacks of zero-width blocks that read as
	# real content at both ends of every scroll.
	check("before the window maps left of the lane", timeline._x_for(-30.0) < left)
	check("past the window maps right of the lane", timeline._x_for(span * 2.0) > right)

	# Not track 1: that is the DRUMS bus now, and a bus legitimately carries no media. What
	# matters is that the arrangement exists at all, on whichever tracks have it.
	var with_items := 0
	for index in DAW.state.track_indices():
		if not DAW.state.track(index).items.is_empty():
			with_items += 1
	check("the stand-in arrangement is not empty", with_items >= 8)
	check("the stand-in has sections named on the ruler", DAW.state.markers.size() >= 4)

	timeline.queue_free()
	DAW.use(previous, false)


## The arrangement is edge-triggered structure. Classified volatile it would go out unreliably,
## be dropped by the first lossy frame and never resent -- so a guest would show a project with
## no items in it, and nothing anywhere would report an error. `/timeline/...` sharing four
## characters of prefix with `/time` is the entire trap.
func _test_arrangement_is_durable_not_volatile() -> void:
	var link := _fresh_link()
	check("the playhead is volatile", link.is_volatile("/time"))
	check("the playhead string is volatile", link.is_volatile("/time/str"))
	check("meters are volatile", link.is_volatile("/track/3/vu/L"))
	check("the arrangement is NOT volatile", not link.is_volatile("/timeline/length"))
	check("markers are NOT volatile", not link.is_volatile("/timeline/markers"))
	check("items are NOT volatile", not link.is_volatile("/track/3/items"))
	link.free()


## What the ReaScript bridge actually hands back, including the two shapes that are easy to get
## wrong: a track reported by its absence because everything on it was deleted, and an empty
## Lua table arriving as `{}` rather than `[]`.
func _test_bridge_arrangement_is_parsed() -> void:
	var link := _fresh_link()
	link.state.track(1)
	link.state.track(2)

	link._on_timeline({
		"length": 240.0,
		"markers": [{"position": 0.0, "name": "Intro"}, {"position": 32.0, "name": "Verse"}],
		"tracks": [
			{"index": 1, "items": [
				{"start": 0.0, "length": 16.0, "muted": false, "name": "Kick A"},
				{"start": 32.0, "length": 16.0, "muted": true, "name": "Kick B"},
			]},
			{"index": 2, "items": {}},
		],
	})

	check("a lane is filled", link.state.track(1).items.size() == 2)
	close_to("an item lands where the bridge said", link.state.track(1).items[1].start, 32.0)
	check("a take name survives", link.state.track(1).items[0].name == "Kick A")
	check("mute survives", link.state.track(1).items[1].muted)
	check("an empty lua table is not one broken item", link.state.track(2).items.is_empty())
	close_to("the project length lands", link.state.project_length, 240.0)
	check("markers land", link.state.markers.size() == 2)

	# Everything on track 1 deleted. The bridge reports that by OMITTING the track, so a merge
	# would leave the old blocks on screen with nothing ever clearing them.
	link._on_timeline({"length": 240.0, "markers": [], "tracks": []})
	check("a track that lost its items is cleared, not left stale",
			link.state.track(1).items.is_empty())

	link.free()


## The overview bar's three gestures, and the clamping that keeps a window inside a project
## whose length changes under it.
func _test_timeline_window_scroll_and_zoom() -> void:
	var bar := TimelineScrubber.new()
	bar.width = 0.4
	bar.project_length = 200.0
	bar.view_start = 0.0
	bar.view_span = 200.0
	add_child(bar)

	var seen := []
	bar.view_changed.connect(func(start, span): seen.append([start, span]))

	# Drag the right edge in: the left edge must not move, or a zoom also scrolls.
	bar.view_span = 100.0
	bar._grab_start = 0.0
	bar._grab_span = 100.0
	bar._grab_x = 0.0
	bar._zone = TimelineScrubber.Zone.RIGHT
	bar._on_grab_move(bar.to_global(Vector3(-0.05, 0, 0)))
	close_to("resizing from the right leaves the left edge alone", bar.view_start, 0.0)
	check("the window got shorter", bar.view_span < 100.0)

	# Drag the left edge out: the RIGHT edge must not move, for the same reason.
	bar.view_start = 50.0
	bar.view_span = 50.0
	bar._grab_start = 50.0
	bar._grab_span = 50.0
	bar._grab_x = 0.0
	bar._zone = TimelineScrubber.Zone.LEFT
	bar._on_grab_move(bar.to_global(Vector3(-0.04, 0, 0)))
	close_to("resizing from the left leaves the right edge alone",
			bar.view_start + bar.view_span, 100.0, 0.001)

	# Scroll the body hard left: it stops at the start rather than going negative.
	bar._grab_start = bar.view_start
	bar._grab_span = bar.view_span
	bar._grab_x = 0.0
	bar._zone = TimelineScrubber.Zone.BODY
	bar._on_grab_move(bar.to_global(Vector3(-0.4, 0, 0)))
	close_to("scrolling past the start stops at the start", bar.view_start, 0.0)

	# And hard right: the window stops with its end at the end of the project, never past it.
	bar._grab_start = bar.view_start
	bar._grab_span = bar.view_span
	bar._grab_x = 0.0
	bar._on_grab_move(bar.to_global(Vector3(0.9, 0, 0)))
	close_to("scrolling past the end stops at the end",
			bar.view_start + bar.view_span, 200.0, 0.001)

	check("every move was reported", seen.size() >= 4)
	bar.queue_free()


## Following is the behaviour that makes a timeline usable during a take and ruins it during an
## edit, so which one is happening has to be read off the transport rather than guessed.
func _test_timeline_follows_the_playhead_only_while_rolling() -> void:
	var previous := DAW.backend
	DAW.use(OfflineBackend.new())

	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)

	var project := DAW.state.timeline_length()
	timeline.view_span = project * 0.25
	timeline.view_start = 0.0

	# Stopped, playhead far past the window: the view must stay where it was put.
	DAW.state.playing = false
	DAW.state.position_seconds = project * 0.8
	timeline._move_playhead()
	close_to("a stopped transport does not drag the view around", timeline.view_start, 0.0)
	check("a playhead outside the window is hidden, not pinned to the edge",
			not timeline._playhead.visible)

	# Rolling: the window pages to contain it.
	DAW.state.playing = true
	timeline._move_playhead()
	check("rolling past the edge pages the window forward", timeline.view_start > 0.0)
	check("the playhead is now inside the window",
			DAW.state.position_seconds >= timeline.view_start
			and DAW.state.position_seconds <= timeline.view_start + timeline.view_span)

	# Already inside: no paging, or the arrangement would slide under a stationary playhead.
	var settled := timeline.view_start
	DAW.state.position_seconds = settled + timeline.view_span * 0.5
	timeline._move_playhead()
	close_to("a playhead inside the window moves the line, not the view",
			timeline.view_start, settled)

	DAW.state.playing = false
	timeline.queue_free()
	DAW.use(previous, false)


# --- track banking ------------------------------------------------------------------------

## A bank is not a scroll position, it is a change of meaning: after it, index 1 is a different
## track. Everything keyed by index is therefore wrong rather than stale, and keeping it would
## leave the previous bank's names on this bank's faders until each happened to be re-sent.
func _test_bank_redefines_what_an_index_means() -> void:
	var state := MixState.new()
	state.bank_size = 64
	state.project_track_count = 90
	state.track(1).name = "Kick"
	state.track(2).name = "Snare"

	check("a project bigger than the bank has more banks", state.has_more_banks())
	check("track 1 of bank 0 is track 1 of the project", state.absolute_track_number(1) == 1)

	# An Array and not a bool: a GDScript lambda captures a local by VALUE, so a captured bool
	# set inside one stays false outside it and the check passes for the wrong reason.
	var banked: Array = []
	state.bank_changed.connect(func(): banked.append(true))
	state.set_bank(64)

	check("moving the bank is announced", banked.size() == 1)
	check("the old bank's cache is dropped, not kept", state.tracks.is_empty())
	check("track 1 of bank 1 is track 65 of the project", state.absolute_track_number(1) == 65)

	# Asking for the bank it is already on must not wipe anything: a redundant statement arrives
	# in every snapshot, and a cache cleared by one would be cleared on arrival.
	state.track(1).name = "Horns"
	state.set_bank(64)
	check("restating the current bank changes nothing", state.track(1).name == "Horns")
	check("and is not announced either", banked.size() == 1)

	state.project_track_count = 12
	state.bank_size = 64
	check("a project smaller than the bank has no second bank", not state.has_more_banks())


## Snapshot ORDER, which is normally not a thing a wire format has to care about and is here.
func _test_bank_is_stated_before_the_tracks_it_renumbers() -> void:
	var here := MixState.new()
	here.set_bank(64, 64)
	here.project_track_count = 90
	here.track(1).name = "Horns"
	here.track(2).name = "Trombone"

	var batch := MixWire.snapshot(here)
	var first: String = batch[0][0]
	check("the bank is the first thing in a snapshot", first == "/bank")

	# The failure this guards: a bank stated at the END of a snapshot delivers a whole project
	# and then clears it, leaving a guest with an empty desk and nothing in the log.
	var there := MixState.new()
	MixWire.apply_replicated(there, batch)
	check("the guest kept the tracks", there.track_indices().size() == 2)
	check("the guest knows which tracks they are", there.absolute_track_number(1) == 65)
	check("the guest knows how big the project is", there.project_track_count == 90)


## The one rule banking must not break.
func _test_bank_waits_for_the_hand_to_let_go() -> void:
	var previous := DAW.backend
	DAW.use(OfflineBackend.new())

	var console := ConsoleSurface.new()
	add_child(console)
	console._process(0.0)
	check("the stand-in needs no bank module", console.bank == null)
	check("a desk with nothing held reports nothing held", not console._anything_held())

	var hand := FakeHand.new()
	hand.set_physics_process(false)
	add_child(hand)
	var fader := console.strips[0]._fader if console.strips[0].get("_fader") != null else null
	var grabbed: ControlAffordance = fader
	if grabbed == null:
		for node in console.find_children("*", "ControlAffordance", true, false):
			grabbed = node
			break

	grabbed.grab_begin(hand, grabbed.global_position)
	check("a held control is reported held", console._anything_held())

	console._request_bank(64)
	check("a bank asked for mid-grab is deferred, not applied", console._pending_bank == 64)
	console._process(0.0)
	check("and stays deferred while the hand is still on it", console._pending_bank == 64)

	grabbed.grab_end(hand)
	console._process(0.0)
	check("and is applied once the hand lets go", console._pending_bank == -1)

	hand.queue_free()
	console.queue_free()
	DAW.use(previous, false)


## The caption is the feature. Without it a 90-track session looks like a complete desk for a
## smaller session than the one that is open, which is the worst shape a limitation can take.
func _test_bank_selector_says_which_tracks_these_are() -> void:
	var sel := BankSelector.new()
	sel.bank_offset = 64
	sel.bank_size = 64
	sel.project_count = 90
	add_child(sel)

	check("the caption names the tracks on the desk", sel._range_label.text == "65-90")
	check("and the size of the project they came from", sel._total_label.text == "OF 90")
	check("there is a bank behind this one", sel._prev.lit)
	check("and none in front of it", not sel._next.lit)

	sel.bank_offset = 0
	sel.refresh()
	check("the first bank is a full bank", sel._range_label.text == "1-64")
	check("with nothing behind it", not sel._prev.lit)
	check("and more in front", sel._next.lit)

	# Asking past the end does nothing rather than paging onto an empty desk.
	var asked: Array = []
	sel.bank_requested.connect(func(o): asked.append(o))
	sel.bank_offset = 64
	sel._step(1)
	check("paging past the last track is refused", asked.is_empty())
	sel._step(-1)
	check("paging back is not", asked == [0])

	sel.queue_free()


## The knob is the first thing in the project whose shape lives in a file rather than in code,
## which brings two failure modes that no other control has.
##
## The asset can be missing -- unexported, or exported and not imported -- and the knob would
## then be a hundred empty nodes on the desk with working collision and nothing drawn. And the
## two primitives in the file can come back in either order, because their order is the glTF
## exporter's business; matching them by index would paint the body white and the indicator
## black, which is a perfectly plausible-looking knob that is wrong.
func _test_knob_is_the_moulded_part() -> void:
	# Authored parts bring two failure modes procedural geometry does not have, and neither one
	# announces itself.
	#
	# The asset can be missing -- unexported, or exported and not imported -- and the control
	# would then be an empty node with working collision and nothing drawn. The stand-ins cover
	# that at runtime, but a desk quietly running on stand-ins is still a regression, so the
	# suite is where it gets noticed.
	#
	# And the primitives can come back in either order, because their order is the glTF
	# exporter's business. Matching by index would paint a knob's body white and its line
	# black: a perfectly plausible-looking part that is wrong. Everything is matched on the
	# authored material name instead, so the names are a contract and the suite holds it.
	# `accent` is the material-name fragment the control actually passes to Part.build, and the
	# footprint is the envelope the panel laid itself out around before any of this was a mesh.
	# The fragment is not a shared convention -- a knob's second surface is its indicator, a
	# reel's is its hub -- so each part states its own, which is the only way this check means
	# anything.
	# The envelope is stated in all three axes, and in the MESH's own space -- not the panel's,
	# because the parts are not modelled in one shared orientation and should not be. A knob and
	# a reel are modelled axis-up and stood up by the importing node; a fader cap is modelled
	# standing and needs no rotation. Collapsing that to "width and height" quietly compared a
	# jack's 20mm barrel against a hole spacing and failed on a part that was correct.
	var parts := {
		Knob.MESH_PATH: {"size": Vector3(0.0230, 0.0140, 0.0230), "accent": "indicator"},
		Fader.MESH_PATH: {"size": Vector3(0.0152, 0.0224, 0.0140), "accent": "indicator"},
		TapeDeck.MESH_PATH: {"size": Vector3(0.1705, 0.0160, 0.1705), "accent": "hub"},
		PatchPoint.MESH_PATH: {"size": Vector3(0.0160, 0.0220, 0.0185), "accent": "bore"},
		RackUnit.MESH_PATH: {"size": Vector3(0.4840, 0.0890, 0.0140), "accent": "screw"},
	}
	for path in parts:
		var accent: String = parts[path]["accent"]
		var mesh := Part.mesh(path)
		check("%s resolves" % path.get_file(), mesh != null)
		if mesh == null:
			continue
		check("%s is the two-material part, not a primitive" % path.get_file(),
				mesh.get_surface_count() == 2)

		var named := 0
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m != null and String(m.resource_name).containsn(accent):
				named += 1
		check("%s names exactly one surface '%s'" % [path.get_file(), accent], named == 1)

		var size: Vector3 = parts[path]["size"]
		var box := mesh.get_aabb()
		check("%s still fits its envelope" % path.get_file(),
				box.size.x < size.x and box.size.y < size.y and box.size.z < size.z)

	# A surface whose material name matches nothing must still be painted, or the importer's
	# guess ends up on the desk.
	var dressed := Part.build(Knob.MESH_PATH, Materials.legend(), {"nothing-matches-this": null})
	if dressed != null:
		var unpainted := 0
		for i in dressed.mesh.get_surface_count():
			if dressed.get_surface_override_material(i) == null:
				unpainted += 1
		check("an unmatched surface falls back rather than going unpainted", unpainted == 0)
		dressed.free()

	# A hexagon repeats every sixty degrees, so a clocking outside that range is turning nuts
	# further than there is anywhere to turn them, and two jacks a multiple of sixty apart
	# would be indistinguishable -- which defeats the point of clocking them at all.
	var angles := {}
	for t in 12:
		for k in [PatchPoint.Kind.OUTPUT, PatchPoint.Kind.INPUT]:
			var a := PatchPoint.nut_angle(t, k)
			check("nut clocking stays inside one hex face", a >= 0.0 and a < 60.0)
			angles[a] = true
	check("and the bay is not all one angle", angles.size() > 6)
	close_to("the same jack is clocked the same way twice",
			PatchPoint.nut_angle(5, PatchPoint.Kind.INPUT),
			PatchPoint.nut_angle(5, PatchPoint.Kind.INPUT))

	var knob := Knob.new()
	add_child(knob)
	knob.value = 1.0
	knob._on_value_changed()
	var spindle := knob.get_child(0) as Node3D
	# The indicator is moulded into the part, so the part itself is the only thing that can
	# move: at value 1.0 the whole knob has turned half a sweep past centre.
	close_to("turning the value turns the whole part", spindle.rotation.z, -0.5 * Knob.SWEEP)
	knob.queue_free()


## The tape pack is the one place in this project where authored and computed geometry meet on
## the same object, so the seam gets its own checks.
##
## It is also the first thing on the deck that makes a CLAIM about the song rather than about
## the transport. A reel that reports progress it does not have is exactly the peripheral lie
## the deck's own header warns about -- you read it from across the room, at a glance, and
## never think to doubt it.
func _test_the_reels_say_how_far_through_the_song_you_are() -> void:
	var state := MixState.new()

	state.set_project_length(0.0)
	state.position_seconds = 42.0
	check("with no timeline, the reels decline to say", TapeDeck.song_fraction(state) < 0.0)

	state.set_project_length(200.0)
	state.position_seconds = 50.0
	close_to("a quarter in reads a quarter in", TapeDeck.song_fraction(state), 0.25)

	state.position_seconds = 999.0
	close_to("past the end is the end, not more than it", TapeDeck.song_fraction(state), 1.0)

	# Tape winds by area, so the radius goes as a square root. The test that matters is not the
	# endpoints -- any formula gets those -- but the middle: half the song must leave a pack
	# well over half way out, and a linear one would not.
	close_to("an empty reel is down to the hub", TapeDeck.pack_radius(0.0), TapeDeck.PACK_HUB)
	close_to("a full reel is out to the rim", TapeDeck.pack_radius(1.0), TapeDeck.PACK_FULL)
	var half := TapeDeck.pack_radius(0.5)
	var linear := (TapeDeck.PACK_HUB + TapeDeck.PACK_FULL) * 0.5
	check("half the song leaves more than half the tape", half > linear)
	check("and not all of it", half < TapeDeck.PACK_FULL)

	# The two reels are one tape. Whatever has left the supply is on the takeup, which in radius
	# terms means the two packs' AREAS add up to one full pack, at every point in the song.
	var hub_area := TapeDeck.PACK_HUB * TapeDeck.PACK_HUB
	var full_area := TapeDeck.PACK_FULL * TapeDeck.PACK_FULL
	for f in [0.0, 0.2, 0.5, 0.85, 1.0]:
		var supply := TapeDeck.pack_radius(1.0 - f)
		var takeup := TapeDeck.pack_radius(f)
		close_to("tape is conserved at %.2f through" % f,
				(supply * supply - hub_area) + (takeup * takeup - hub_area),
				full_area - hub_area)


## The reels turn from the position, which is the claim the deck's header makes and the one
## thing about this surface that is read from across the room without being checked.
##
## What makes it worth a test rather than an eyeball is that the failure modes are all SILENT:
## two reels sharing a rate looks like motion, a reel that ignores a rewind looks like motion,
## and a reel spinning after a stop looks like motion. Each is only wrong if you know what the
## position was doing at the time.
func _test_each_reel_turns_at_its_own_rate() -> void:
	# A half-wound reel turns at the rate the deck was tuned to by eye when the rate was flat.
	# This is the one number in here chosen for looks, so it is the one worth pinning: a change
	# to TAPE_SPEED or the pack geometry that moves it has changed how the deck reads.
	close_to("a half-wound reel turns at the rate the deck was tuned to",
			TapeDeck.reel_rate(0.5, 1.0), 2.4, 0.02)

	# The signature. An empty reel is paying out at the hub, so it has to turn faster than a
	# full one to move the same tape -- and the ratio is the radius ratio, not something else.
	var empty := TapeDeck.reel_rate(0.0, 1.0)
	var full := TapeDeck.reel_rate(1.0, 1.0)
	check("an empty reel turns faster than a full one", empty > full)
	close_to("by exactly the ratio of their radii",
			empty / full, TapeDeck.PACK_FULL / TapeDeck.PACK_HUB, 0.001)

	# Supply and takeup only ever agree at the exact middle. If they agreed anywhere else the
	# tape between them would have to stretch.
	for f in [0.1, 0.35, 0.5, 0.8]:
		var supply := TapeDeck.reel_rate(1.0 - f, 1.0)
		var takeup := TapeDeck.reel_rate(f, 1.0)
		if is_equal_approx(f, 0.5):
			close_to("at the middle the two reels agree", supply, takeup, 0.0001)
		else:
			check("at %.2f through the two reels disagree" % f, absf(supply - takeup) > 0.05)

	check("standing still turns nothing", TapeDeck.reel_rate(0.5, 0.0) == 0.0)
	check("a rewind turns the other way", TapeDeck.reel_rate(0.5, -1.0) < 0.0)
	close_to("twice the speed is twice the rate",
			TapeDeck.reel_rate(0.5, 2.0), TapeDeck.reel_rate(0.5, 1.0) * 2.0, 0.0001)

	# A locate is a position jump, and a jump over one frame divides out to a huge number. It is
	# capped rather than special-cased, so the reels spin hard and briefly instead of by NaN.
	check("a locate is capped, not unbounded",
			TapeDeck.reel_rate(0.5, 10000.0) == TapeDeck.MAX_SPOOL_RATE)
	check("and capped in both directions",
			TapeDeck.reel_rate(0.5, -10000.0) == -TapeDeck.MAX_SPOOL_RATE)

	# --- and now the built deck, because a correct rule that is wired up backwards is the
	# --- actual risk here: supply and takeup are identical objects in different places.
	DAW.use(OfflineBackend.new())
	var deck := TapeDeck.new()
	add_child(deck)
	deck._process(0.0)

	DAW.state.set_project_length(200.0)
	DAW.state.position_seconds = 20.0
	deck._process(0.0)
	var left_before: float = deck._left_reel.rotation.z
	var right_before: float = deck._right_reel.rotation.z

	# Move the song on by one second of a 200-second project over one second of wall clock, so
	# the observed speed is 1x, and give the follower long enough to have arrived there.
	for i in 40:
		DAW.state.position_seconds += 0.1
		deck._process(0.1)
	var left_moved: float = absf(deck._left_reel.rotation.z - left_before)
	var right_moved: float = absf(deck._right_reel.rotation.z - right_before)
	check("the supply reel turned", left_moved > 0.01)
	check("the takeup reel turned", right_moved > 0.01)
	# Early in the song the takeup is nearly empty and the supply is nearly full, so the takeup
	# is the faster of the two. Backwards here is the mistake nobody reports and everybody sees.
	check("early in the song the takeup outruns the supply", right_moved > left_moved)

	# A stop is not a flag the deck is told about; it is the position stopping. The reels must
	# come to rest from that alone.
	for i in 40:
		deck._process(0.1)
	var resting: float = deck._right_reel.rotation.z
	deck._process(0.1)
	close_to("a stopped position stops the reels", deck._right_reel.rotation.z, resting, 0.001)

	# And a rewind runs them backwards, again without being told.
	var before_rewind: float = deck._right_reel.rotation.z
	for i in 20:
		DAW.state.position_seconds = maxf(0.0, DAW.state.position_seconds - 0.4)
		deck._process(0.1)
	check("a rewind turns the reels the other way",
			deck._right_reel.rotation.z > before_rewind)

	# --- the reason the speed is smoothed at all ---------------------------------------------
	#
	# Position arrives over a wire at its own rate, not once per frame. This is that case: the
	# position moves on every third frame and sits still on the other two, which is what a 20Hz
	# link looks like at 60fps. The raw reading alternates between 3x and nothing, so an
	# unsmoothed deck stutters to a dead stop twenty times a second and reads as a fault.
	#
	# The assertion is on the SPREAD of the per-frame rotation, not on its value: that is the
	# thing an eye picks up, and it is the thing a raw reading destroys.
	DAW.state.position_seconds = 20.0
	deck._last_position = -1.0
	deck._song_speed = 0.0
	for i in 60:
		if i % 3 == 0:
			DAW.state.position_seconds += 0.05
		deck._process(1.0 / 60.0)
	var steps: Array[float] = []
	var previous: float = deck._right_reel.rotation.z
	for i in 60:
		if i % 3 == 0:
			DAW.state.position_seconds += 0.05
		deck._process(1.0 / 60.0)
		steps.append(absf(deck._right_reel.rotation.z - previous))
		previous = deck._right_reel.rotation.z
	var smallest := steps[0]
	var largest := steps[0]
	for step in steps:
		smallest = minf(smallest, step)
		largest = maxf(largest, step)
	check("a reel on a polled position never stops dead", smallest > 0.0)
	check("and does not lurch between frames", largest < smallest * 2.0)

	deck.queue_free()


func _test_the_gear_makes_a_noise() -> void:
	# Everything here is about the sample buffer, not about playback. The suite is headless and
	# the audio driver is a stub, so "does it play" is not a question that can be asked -- but
	# the two ways synthesised audio actually goes wrong are both plainly visible in the buffer,
	# and neither of them is visible to someone who is not listening for it.
	var sounds := {
		"button": {"stream": Foley.button_click(), "loop": false, "seconds": 0.045},
		"detent": {"stream": Foley.knob_detent(), "loop": false, "seconds": 0.018},
		"plug": {"stream": Foley.plug_seat(), "loop": false, "seconds": 0.075},
		"slide": {"stream": Foley.fader_slide(), "loop": true, "seconds": 0.670},
		"motor": {"stream": Foley.reel_motor(), "loop": true, "seconds": 0.388},
	}

	for key in sounds:
		var spec: Dictionary = sounds[key]
		var wav := spec["stream"] as AudioStreamWAV
		check("foley %s synthesises" % key, wav != null)
		if wav == null:
			continue
		var samples := _pcm(wav)
		check("foley %s is 16-bit mono at 44.1k" % key,
				wav.format == AudioStreamWAV.FORMAT_16_BITS
				and wav.mix_rate == Foley.RATE and not wav.stereo)
		close_to("foley %s runs the length it claims" % key,
				float(samples.size()) / float(Foley.RATE), spec["seconds"], 0.004)

		# Nothing may clip. A synthesised sound that sums several partials is one careless
		# amplitude away from wrapping, and a wrapped sample is a buzz, not a louder sound.
		var peak := 0.0
		for v in samples:
			peak = maxf(peak, absf(v))
		check("foley %s does not clip" % key, peak < 0.999)
		check("foley %s is not silence" % key, peak > 0.02)

		if spec["loop"]:
			check("foley %s loops" % key, wav.loop_mode == AudioStreamWAV.LOOP_FORWARD)
			check("foley %s loops over its whole buffer" % key,
					wav.loop_begin == 0 and wav.loop_end == samples.size())
			# THE SEAM. A loop whose last sample is far from its first has a step
			# discontinuity at the loop point, which is a click repeating at the loop rate --
			# inaudible as a defect and impossible to ignore as a rhythm.
			var step: float = absf(samples[samples.size() - 1] - samples[0])
			check("foley %s has no step at the loop point" % key, step < 0.06)
		else:
			check("foley %s is a one-shot" % key, wav.loop_mode == AudioStreamWAV.LOOP_DISABLED)
			# THE TAIL. A one-shot cut off before it has decayed ends in a step down to
			# silence, which is the same click by another route.
			check("foley %s has decayed before it ends" % key,
					absf(samples[samples.size() - 1]) < 0.02)
			# ...and it has to actually start at the top, or the attack has been thrown away.
			var early := 0.0
			for i in mini(samples.size() / 4, samples.size()):
				early = maxf(early, absf(samples[i]))
			check("foley %s puts its energy at the front" % key, early > peak * 0.7)

	# Determinism. The noise is seeded, so a build is the same build -- which is what lets the
	# checks above mean anything at all on the next run.
	check("foley is cached rather than re-synthesised",
			Foley.button_click() == Foley.button_click())

	# The spatial settings are what make a sound say WHICH control, so they are not optional.
	var emitter := Foley.emitter(Foley.button_click(), -6.0, 1.0)
	check("foley emits positionally", emitter is AudioStreamPlayer3D)
	close_to("foley emitter carries the trim", emitter.volume_db, -6.0)
	check("foley emitter is scaled to a room, not a hall",
			emitter.unit_size < 1.0 and emitter.max_distance < 20.0)
	emitter.free()

	# Playing at a node that is not in a tree must be a no-op rather than an error: controls are
	# built before they are parented, and a missing sound should be silence.
	var orphan := Node3D.new()
	Foley.play(orphan, Foley.button_click())
	check("foley at an unparented node adds nothing", orphan.get_child_count() == 0)
	Foley.play(null, Foley.button_click())
	Foley.play(orphan, null)
	check("foley survives a null sound", true)
	orphan.free()

	# --- The knob's detents ---------------------------------------------------------------
	#
	# What matters is not that a tick fires but that a sweep crosses every notch exactly once:
	# a knob that skips notches ticks less the faster you turn it, which is backwards.
	check("a knob at rest sits in the first detent", Knob.detent_of(0.0) == 0)
	check("a knob wide open sits in the last detent",
			Knob.detent_of(1.0) == Knob.DETENTS - 1)
	check("detents clamp past the ends",
			Knob.detent_of(-3.0) == 0 and Knob.detent_of(9.0) == Knob.DETENTS - 1)
	var seen := {}
	var crossings := 0
	var previous := Knob.detent_of(0.0)
	for i in range(1, 2001):
		var d := Knob.detent_of(float(i) / 2000.0)
		seen[d] = true
		if d != previous:
			crossings += 1
			previous = d
	check("a full sweep visits every detent", seen.size() == Knob.DETENTS)
	check("a full sweep crosses each boundary once", crossings == Knob.DETENTS - 1)

	# --- The fader's slide ----------------------------------------------------------------
	check("a still fader is silent", Fader.slide_gain(0.0) == 0.0)
	check("a crawling fader is silent", Fader.slide_gain(0.005) == 0.0)
	check("a moving fader is audible", Fader.slide_gain(0.3) > 0.0)
	check("the slide gets louder with speed",
			Fader.slide_gain(2.0) > Fader.slide_gain(0.5))
	check("the slide tops out", Fader.slide_gain(500.0) <= 1.0 + 0.0001)
	close_to("the slide reaches full at full speed",
			Fader.slide_gain(Fader.SPEED_FOR_FULL), 1.0)
	# The square-root law exists so the slow part of a move is not silent. Half speed should be
	# well over half as loud, and a linear law is exactly what this would catch.
	check("the slide favours slow movement over a linear law",
			Fader.slide_gain(Fader.SPEED_FOR_FULL * 0.25) > 0.4)


## Unpack an AudioStreamWAV back to floats so the checks can read it.
func _pcm(wav: AudioStreamWAV) -> PackedFloat32Array:
	var bytes := wav.data
	var out := PackedFloat32Array()
	out.resize(bytes.size() / 2)
	for i in out.size():
		out[i] = float(bytes.decode_s16(i * 2)) / 32767.0
	return out


func _test_the_project_has_a_shape() -> void:
	# The three things OSC cannot say -- colour, folder structure, and a send's destination as
	# an index -- now arrive off the ReaScript bridge. Everything here is about the state and
	# wire layer, which is where the answers land before anything draws them.
	var state := MixState.new()
	var names := ["Kick", "Snare", "OH", "Bass", "Verb", "Gtr", "Verb", "Vox"]
	for i in names.size():
		state.track(i + 1).name = names[i]

	# --- a send's destination ---------------------------------------------------------------
	#
	# THE CASE THAT MATTERS. Two tracks called "Verb" is completely normal in a real project,
	# and resolving a send by name picks whichever comes first -- silently, and forever. This
	# is the bug the index fixes, so it is the one worth pinning.
	var by_name := state.send(1, 0)
	by_name.dest_name = "Verb"
	check("a send resolved by name finds a track", by_name.resolve(state) == 5)
	check("...but picks the FIRST of two tracks with that name, which is the ambiguity",
			by_name.resolve(state) != 7)

	var by_index := state.send(2, 0)
	by_index.dest_name = "Verb"
	by_index.dest_track = 7
	check("a send carrying an index resolves to it, not to the first name match",
			by_index.resolve(state) == 7)

	# The index wins even when it disagrees with the name, because the bridge read it off the
	# destination track itself and OSC only ever guessed.
	by_index.dest_name = "Kick"
	check("the index outranks a stale name", by_index.resolve(state) == 7)

	var unknown := state.send(3, 0)
	check("a send with neither name nor index resolves to nothing", unknown.resolve(state) == -1)
	unknown.dest_name = "Nothing By This Name"
	check("a send naming a track that is not here resolves to nothing",
			unknown.resolve(state) == -1)
	# -1 is the bridge's "no destination", and it must not be mistaken for track -1 or fall
	# through to the name.
	var cleared := state.send(4, 0)
	cleared.dest_track = -1
	cleared.dest_name = "Bass"
	check("a bridge that reports no destination falls back to the name",
			cleared.resolve(state) == 4)

	# --- folder structure -------------------------------------------------------------------
	#
	# Reaper stores a DELTA per track and the level is the running sum, so the arithmetic is
	# worth pinning on a tree with a nested folder and a double close.
	var tree := MixState.new()
	#                         1   2   3   4   5   6   7   8
	var depths := [1, 0, 1, 0, -1, -1, 0, 0]
	for i in depths.size():
		var t := tree.track(i + 1)
		t.name = "T%d" % (i + 1)
		t.folder_depth = depths[i]
	var levels := [0, 1, 1, 2, 2, 1, 0, 0]
	for i in levels.size():
		check("track %d sits at folder level %d" % [i + 1, levels[i]],
				tree.folder_level(i + 1) == levels[i])

	# A delta that would take the level negative is clamped. Reaper will not normally emit one,
	# but a bank that starts mid-tree hands us the tail of a project whose opening folders are
	# simply not in the window -- and a negative level would put a break on every strip.
	var ragged := MixState.new()
	for i in 3:
		ragged.track(i + 1).folder_depth = -1
	check("a bank starting mid-tree does not go below the root",
			ragged.folder_level(3) == 0 and ragged.folder_level(2) == 0)

	# starts_group is what the desk divides on, and the rule is not "the level changed".
	check("the first strip is a group start", tree.starts_group(1))
	check("a folder's parent heads its own group", tree.starts_group(3))
	# THE CASE THE OBVIOUS RULE GETS WRONG. Track 2 is the first child of the folder track 1
	# opened; its level differs from track 1's, but cutting there separates a bus from the
	# tracks it sums. On the demo project that put the VOX bus in with the guitars.
	check("the first child of a folder is NOT cut off from its parent",
			not tree.starts_group(2) and not tree.starts_group(4))
	check("a strip at the same level as the one before it is not a break",
			not tree.starts_group(5))
	check("leaving a folder is a break", tree.starts_group(6) and tree.starts_group(7))
	check("staying at the root is not a break", not tree.starts_group(8))

	# --- and the desk's own copy of that arithmetic -------------------------------------------
	#
	# ConsoleSurface recomputes breaks in one pass because asking per strip makes laying out a
	# 90-track desk quadratic. That optimisation is only safe while it AGREES with the readable
	# definition, so this checks the two against each other rather than checking either alone.
	var indices := tree.track_indices()
	var breaks := ConsoleSurface._group_breaks(tree, indices)
	for i in indices.size():
		var index: int = indices[i]
		var expected := tree.starts_group(index) and i > 0
		check("the desk and the state agree on a break at %d" % index,
				breaks.has(index) == expected)
	check("the desk never rules off the left edge of the panel", not breaks.has(indices[0]))
	check("the demo tree actually has breaks to draw", breaks.size() >= 3)

	# --- the wire ---------------------------------------------------------------------------
	#
	# Colour, folder and dest are reaper-3d's own addresses rather than Reaper's, so they have
	# to survive the snapshot/apply round trip or a guest sees a grey, ungrouped, mis-cabled
	# desk while the host sees the real one.
	var host := MixState.new()
	host.track(1).name = "Kick"
	host.track(1).colour = Color(0.86, 0.33, 0.28)
	host.track(1).folder_depth = 1
	host.track(2).name = "Snare"
	host.track(2).folder_depth = -1
	var hs := host.send(1, 0)
	hs.dest_name = "Snare"
	hs.dest_track = 2

	var guest := MixState.new()
	for pair in MixWire.snapshot(host):
		MixWire.apply(guest, pair[0], pair[1])

	close_to("colour crosses the wire", guest.track(1).colour.r, 0.86, 0.002)
	check("folder depth crosses the wire",
			guest.track(1).folder_depth == 1 and guest.track(2).folder_depth == -1)
	check("a send's destination index crosses the wire",
			guest.send(1, 0).dest_track == 2)
	check("a guest resolves the same cable the host drew",
			guest.send(1, 0).resolve(guest) == hs.resolve(host))

	# --- the stand-in -------------------------------------------------------------------------
	#
	# The offline project is the only session anyone can open without Reaper running, so it is
	# the one that has to exercise this. A demo at depth zero throughout would make the feature
	# invisible exactly where it is most likely to be looked at.
	var offline := OfflineBackend.new()
	offline.state = MixState.new()
	offline.open()
	var demo_breaks := ConsoleSurface._group_breaks(offline.state, offline.state.track_indices())
	check("the stand-in project has a folder tree", demo_breaks.size() >= 3)
	var coloured := 0
	for index in offline.state.track_indices():
		if offline.state.track(index).colour != Color(0.55, 0.57, 0.6):
			coloured += 1
	check("the stand-in project is coloured", coloured >= 10)
	var routed := 0
	for index in offline.state.track_indices():
		for si in offline.state.track(index).sends:
			var sd: MixState.SendState = offline.state.track(index).sends[si]
			if sd.resolve(offline.state) > 0:
				routed += 1
	check("every stand-in send resolves to a track", routed == 4)
	offline.free()


func _test_the_studio_fits_in_a_frame() -> void:
	# The target is a standalone passthrough headset drawing this whole room twice per frame at
	# 72Hz. tools/budget.sh is what measures that; these are the facts the measurement depends
	# on, pinned so a later change cannot quietly undo the win without failing here.

	# --- the meter is ONE object ----------------------------------------------------------
	#
	# THE REGRESSION THIS EXISTS FOR. The obvious way to write a segmented ladder is a mesh per
	# segment, it is what this was, and at 90 tracks it was 1,260 draw calls -- thirty-seven
	# percent of the entire studio for one widget. Nothing about the scene LOOKS wrong when it
	# comes back, which is exactly why it needs a test rather than an eye.
	var meter := VUMeter.new()
	add_child(meter)
	var multis := meter.find_children("*", "MultiMeshInstance3D", true, false)
	var singles := meter.find_children("*", "MeshInstance3D", true, false)
	check("a meter is one MultiMesh", multis.size() == 1)
	check("a meter is not a pile of MeshInstance3Ds", singles.is_empty())

	var mm: MultiMesh = (multis[0] as MultiMeshInstance3D).multimesh
	check("the ladder has every segment", mm.instance_count == VUMeter.SEGMENTS)
	check("the ladder carries per-instance colour", mm.use_colors)
	check("the lamp material is shared across meters, not one per meter",
			(multis[0] as MultiMeshInstance3D).material_override is ShaderMaterial)

	# NOTE: everything below asks the pure functions, not the MultiMesh. Its instance buffer
	# lives in the rendering server, and headless that server is a stub -- set_instance_color
	# writes happily and get_instance_color returns black forever. Converting a widget to a
	# MultiMesh makes it untestable unless the decision is lifted out of the buffer, which is
	# why VUMeter.segment_colour and segment_y exist at all.

	# Segments climb. A ladder whose instances all sit at the origin draws as one bright block
	# and measures as a win.
	check("the ladder actually climbs",
			VUMeter.segment_y(VUMeter.SEGMENTS - 1) > VUMeter.segment_y(0))
	close_to("the ladder is evenly spaced",
			VUMeter.segment_y(2) - VUMeter.segment_y(1),
			VUMeter.segment_y(1) - VUMeter.segment_y(0))
	close_to("the ladder is as tall as it says",
			VUMeter.segment_y(VUMeter.SEGMENTS - 1) + VUMeter.SEG_HEIGHT + VUMeter.SEG_GAP,
			meter.total_height())

	# --- and it still reads as a meter ------------------------------------------------------
	var all_dark := VUMeter.segment_colour(0, 0, -1)
	var all_lit := VUMeter.segment_colour(0, VUMeter.SEGMENTS, -1)
	check("a lit segment is brighter than a dark one", all_lit.g > all_dark.g)
	# Over 1.0 on purpose: that is what the glow pass picks up, and without it a lit LED is
	# only a paler shade of plastic.
	check("a lit segment is driven past 1.0 so it blooms", all_lit.g > 1.0)
	check("an unlit segment keeps its tint rather than going black", all_dark.g > 0.01)

	check("segments below the level are lit",
			VUMeter.segment_colour(0, 3, -1).g > 1.0)
	check("segments above the level are not",
			VUMeter.segment_colour(10, 3, -1).g < 1.0)
	# The peak marker is a lit segment ABOVE an unlit gap, which is the whole point of it.
	check("the peak marker lights on its own",
			VUMeter.segment_colour(9, 3, 9).g > 1.0)
	check("the gap below the peak marker stays dark",
			VUMeter.segment_colour(7, 3, 9).g < 1.0)

	# Red at the top, amber below it, green beneath. The colour boundaries are the only
	# calibration a meter at a glance conveys, so they are worth pinning.
	var top := VUMeter.colour_at(VUMeter.SEGMENTS - 1)
	var middle := VUMeter.colour_at(int(VUMeter.SEGMENTS * 0.82))
	var bottom := VUMeter.colour_at(0)
	check("the top of the ladder is red", top.r > top.g)
	check("below the top it is amber", middle.r > 0.6 and middle.g > 0.5 and middle.b < 0.3)
	check("the bottom of the ladder is green", bottom.g > bottom.r)

	# Repainting only on change. A ladder is fourteen buffer writes and a meter spends most of
	# its life on the same segment count; across ninety strips that is 1,260 writes a frame to
	# say nothing at all.
	meter._paint(5, 2)
	check("the meter remembers what it drew",
			meter._lit_shown == 5 and meter._peak_shown == 2)
	meter.queue_free()

	# --- the stand-in can be session-sized ---------------------------------------------------
	#
	# The authored demo is thirteen tracks, which is readable and is not what a session costs.
	# Neither "what does this draw at scale" nor "does the bank paging work" could be asked
	# without Reaper open until the stand-in could be told to be bigger.
	var big := OfflineBackend.new()
	big.state = MixState.new()
	big.track_count = 90
	big.open()
	check("a scaled stand-in has the tracks it was asked for",
			big.state.track_indices().size() == 90)
	check("a scaled stand-in reports its real size",
			big.state.project_track_count == 90)
	check("a project bigger than a bank still streams only a bank",
			big.state.bank_size == 64)
	check("a project bigger than a bank offers the bank controls",
			big.can(DAWBackend.Capability.TRACK_BANKING))
	# Names stay distinct, or a 90-strip desk is 90 strips called the same thing and every
	# layout problem long names cause is hidden again.
	var seen_names := {}
	for index in big.state.track_indices():
		seen_names[big.state.track(index).display_name()] = true
	check("a scaled stand-in does not repeat track names", seen_names.size() == 90)
	check("a scaled stand-in keeps a folder tree",
			ConsoleSurface._group_breaks(big.state, big.state.track_indices()).size() >= 10)
	big.free()

	var small := OfflineBackend.new()
	small.state = MixState.new()
	small.open()
	check("the authored stand-in is unchanged by the knob existing",
			small.state.track_indices().size() == 13)
	# A session that fits on the desk needs no bank controls, and two dead buttons invite the
	# question of what they are for.
	check("a project that fits in a bank offers no bank controls",
			not small.can(DAWBackend.Capability.TRACK_BANKING))
	small.free()

	# --- the room is a fixed cost ------------------------------------------------------------
	#
	# Everything above is about what a TRACK costs. This is about what the room costs, which
	# should be nothing per track: there are three looms because there are three machines, and
	# three lamps because someone put three lamps in. The regression to catch is the plausible
	# one -- a loom per send, a lamp per strip -- which would not look wrong in a screenshot of
	# thirteen tracks and would be a thousand meshes at ninety.
	var scenery := func(tracks: int) -> Array:
		var backend := OfflineBackend.new()
		backend.state = MixState.new()
		backend.track_count = tracks
		DAW.use(backend)
		var room := Studio.new()
		room.medium = Presentation.Medium.SCREEN
		add_child(room)
		for node in room.find_children("*", "Node3D", true, false):
			if node is Surface:
				(node as Surface)._process(0.0)
		var dressing := room.studio_set.get_children().filter(
				func(n): return n is GearLoom or n.is_in_group(&"lamp_stand"))
		var meshes := 0
		var casting := 0
		for item in dressing:
			for mesh in (item as Node3D).find_children("*", "MeshInstance3D", true, false):
				meshes += 1
				if (mesh as MeshInstance3D).cast_shadow != \
						GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					casting += 1
		var counted := [dressing.size(), meshes, casting]
		room.queue_free()
		return counted

	var thin: Array = scenery.call(13)
	var fat: Array = scenery.call(64)
	check("the room has the pieces it was told to have (%d)" % thin[0],
			thin[0] == Studio.LOOM_RUNS.size() + Studio.PRACTICALS.size())
	check("the room costs the same at 64 tracks as at 13 (%d vs %d meshes)" % [thin[1], fat[1]],
			thin == fat)
	# The looms were drawn into the shadow map by one 30mm collar at each end, left casting by
	# oversight: twelve draw calls for the shadow of the one part of a cable that is not the
	# cable. Measured at 90 tracks wide, 976 draws before and 964 after.
	var lamp_meshes := Studio.PRACTICALS.size() * 4
	check("nothing on a loom casts a shadow (%d casters, %d lamp parts)"
			% [thin[2], lamp_meshes], thin[2] <= lamp_meshes)


func _test_scrolling_the_timeline_does_not_rebuild_it() -> void:
	# THE REGRESSION THIS EXISTS FOR. Dragging the overview scrubber called mark_dirty(), which
	# tore down and recreated every lane, every lane label, every flag and every item -- once
	# per frame, for the whole drag. At twelve lanes that was survivable; at ninety it was not.
	# Scrolling changes WHERE the project is looked at, not what shape it is.
	DAW.use(OfflineBackend.new())
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)

	var labels := timeline.find_children("*", "Label3D", true, false)
	check("the timeline built some lanes to scroll", labels.size() > 4)
	# Identity, not count: a rebuild that happened to make the same NUMBER of labels would slip
	# past a count. These must be the same objects afterwards.
	var lane_label: Label3D = null
	for node in labels:
		if (node as Label3D).text.to_upper().contains("KICK"):
			lane_label = node
			break
	check("a lane is labelled with its track", lane_label != null)
	var before_id := lane_label.get_instance_id() if lane_label else 0

	var blocks := timeline.get_node_or_null("ItemBlocks") as MeshBank
	check("items are drawn as one object", blocks != null)
	var drawn_before := blocks.multimesh.visible_instance_count if blocks else -1
	var first_before := blocks.transform_of(0).origin.x if blocks else 0.0

	# Scroll, the way the scrubber does.
	timeline._on_view_changed(timeline.view_start + 4.0, timeline.view_span)
	check("scrolling did not destroy the lanes",
			lane_label != null and is_instance_id_valid(before_id))
	check("and did not mark the surface for a rebuild", not timeline._dirty)
	# It did have to DO something, or it is not a scroll.
	check("but the items did move",
			blocks != null and not is_equal_approx(blocks.transform_of(0).origin.x, first_before))

	# Scrolling far past the end empties the window without resizing anything.
	timeline._on_view_changed(100000.0, timeline.view_span)
	check("an empty window draws no items", blocks.multimesh.visible_instance_count == 0)
	check("and the bank kept its capacity", blocks.count() > 0)
	check("which is more than it is drawing", blocks.count() >= drawn_before)

	# --- and the other caller, which is the one nobody watches -------------------------------
	#
	# The drag above is the case that got noticed, because someone was holding the thing when it
	# stuttered. _follow() is the same scroll arriving by itself: the playhead runs off the right
	# edge during a take and the window pages. It fired unattended, once per window, for the
	# whole of a rolling session, and it tore down every lane label while the transport was
	# running. Fixing one caller and leaving the other is how this kind of bug survives a fix.
	# Zoomed in, which is the only state paging can happen in: the timeline opens showing the
	# whole project, and a playhead cannot run off a window that contains everything.
	timeline._on_view_changed(0.0, 40.0)
	timeline._process(0.0)
	var follow_label: Label3D = null
	for node in timeline.find_children("*", "Label3D", true, false):
		if (node as Label3D).text.to_upper().contains("KICK"):
			follow_label = node
			break
	check("there is a lane label to lose", follow_label != null)
	var follow_id := follow_label.get_instance_id() if follow_label else 0
	var start_before := timeline.view_start

	# Rolling, with the playhead well past the right edge of the window.
	DAW.state.playing = true
	DAW.state.position_seconds = timeline.view_start + timeline.view_span * 2.0
	check("the playhead is off the window, so the view must page",
			timeline._follow(DAW.state.position_seconds))
	check("paging moved the window", not is_equal_approx(timeline.view_start, start_before))
	check("paging did not destroy the lanes",
			follow_label != null and is_instance_id_valid(follow_id))
	check("and did not mark the surface for a rebuild", not timeline._dirty)

	# Stopped, it must leave the view alone: that is when someone is deliberately looking
	# somewhere other than the playhead, and yanking the window back would fight them.
	DAW.state.playing = false
	var parked := timeline.view_start
	DAW.state.position_seconds = parked + timeline.view_span * 1.5
	check("a stopped transport does not drag the view around",
			not timeline._follow(DAW.state.position_seconds))
	check("and the window stayed where it was put", is_equal_approx(timeline.view_start, parked))
	DAW.state.playing = false

	timeline.queue_free()


## The three things a surface is not allowed to know, enforced on the source rather than stated
## in a header.
##
## presentation.gd says it plainly -- "A surface is written once and works in all three. It must
## never ask which mode it is in" -- and surface.gd repeats it for who is looking and for which
## process is the host. All three were still true when this was written. None of them was
## CHECKED, which is a different thing: an invariant that holds today and is enforced by a
## comment is one careless `if` away from not holding, and the `if` will look reasonable in
## review because the rule lives in a file nobody is editing at the time.
##
## This is the tick's actual lesson. Two bugs in two days were both a header describing a
## mechanism the code did not have, and a third turned up during the sweep that found this one.
## Prose makes claims; only the suite holds anyone to them.
##
## Scoped to hardware/, which is where surfaces live. The mounts and the studio are exactly the
## layer that IS allowed to know these things, which is the whole point of the separation.
## A part-filled rack is a rack with room in it, not a rack with a hole in it.
##
## The frame is built to the bay's full capacity because that is what makes two bays line up,
## so a bay holding six units out of twelve left six empty rows you could see the far wall
## through. It read as a modelling mistake rather than as space, which is the same class of
## failure as the bank selector and the rack's own page control: the gear misrepresenting the
## project, in the direction of looking simpler than it is.
## Every surface that draws one thing per track has to say when it is drawing a BANK.
##
## The console has said so since it was written, which is exactly why this went unnoticed for
## so long: the room contains a desk captioned "17-64 OF 90" standing next to a timeline
## showing 64 lanes and a patchbay showing 64 pairs of jacks, both captioned nothing. The desk
## being right made the other two look right.
##
## Asserted over a LIST of surfaces rather than one test each, so a fourth surface that draws
## per-track geometry gets added here and is held to the rule on the day it is written, instead
## of joining the two that quietly were not.
func _test_a_surface_showing_a_bank_says_it_is_showing_a_bank() -> void:
	var state := MixState.new()
	for i in 64:
		state.track(i)
	check("a cache with no project count behind it says nothing", state.bank_caption() == "")
	state.project_track_count = 64
	check("a cache holding the whole project says nothing", state.bank_caption() == "")

	state.project_track_count = 90
	state.bank_offset = 16
	check("a truncated cache names the window and the whole",
			state.bank_caption() == "TRACKS 17-80 OF 90")

	# A cache holding FEWER than the bank it asked for. Without this case the suite cannot tell
	# "count what is held" from "assume a full bank", because with 64 of 64 the two agree to the
	# character -- and a mutation swapping one for the other sailed through every check above.
	var partial := MixState.new()
	for i in 40:
		partial.track(i)
	partial.project_track_count = 90
	partial.bank_size = 64
	check("a half-filled bank counts what it has, not what it asked for",
			partial.bank_caption() == "TRACKS 1-40 OF 90")

	# The caption is measured from what is HELD, not from bank_size, and this is the case that
	# told them apart: the offline stand-in at 90 tracks caches all 90 while bank_size is still
	# 64, so a bank_size caption read "TRACKS 1-64 OF 90" over ninety drawn lanes. Found by
	# looking at it. The first version of this test passed, because it only checked that the
	# number 90 appeared somewhere -- and it did, in the wrong sentence.
	var everything := MixState.new()
	for i in 90:
		everything.track(i)
	everything.project_track_count = 90
	everything.bank_size = 64
	check("a cache holding more than a bank still says nothing",
			everything.bank_caption() == "")

	# The real shape, which only Reaper produces: banking is on, the cache holds 64 of 90.
	var big := OfflineBackend.new()
	big.track_count = 90
	DAW.use(big)
	check("banking is available at this size",
			DAW.can(DAWBackend.Capability.TRACK_BANKING))
	# FORTY, not sixty-four, and the odd number is the point. A cache holding exactly bank_size
	# cannot tell "count what is held" apart from "assume a full bank" -- both formulas return
	# the same sentence, and a mutation swapping one for the other passes. That is the bug this
	# whole test exists for, so the fixture has to be able to see it: a bank still filling, or
	# a backend that capped lower than it was asked, holds fewer than it was promised.
	#
	# Keep the first 40 by sorted order rather than by index value: the stand-in's indices are
	# Reaper's numbering, not 0..89, so "index >= 40" is not the same set as "the first 40".
	var held_indices := DAW.state.track_indices()
	for position in range(40, held_indices.size()):
		DAW.state.tracks.erase(held_indices[position])
	check("the cache now holds part of a bank, not the project", DAW.state.tracks.size() == 40)
	check("and fewer than the bank it asked for", DAW.state.tracks.size() < DAW.state.bank_size)

	# EXACT text, not a substring, and this is the correction of last tick's mistake rather than
	# a flourish. The previous version searched every label for "90" and called a hit proof the
	# surface had said the right thing. The caption it was meant to be guarding read "TRACKS
	# 1-64 OF 90" over ninety drawn lanes -- a sentence that is wrong in the only way that
	# matters and contains "90" in passing. A substring check will accept any lie that contains
	# the substring, which is most of them.
	#
	# The console splits the same fact across two labels because its strip is 40mm wide, so it
	# is checked as the pair it draws rather than being forced into one string it does not have.
	var first := DAW.state.bank_offset + 1
	var last := DAW.state.bank_offset + DAW.state.tracks.size()
	var total := DAW.state.project_track_count
	# Named explicitly. get_class() on a scripted node returns the native base -- every one of
	# these is "Node3D" -- so a failure would name nothing, in the test whose whole job is to
	# say WHICH surface went quiet.
	# Spelled out here rather than fetched from bank_caption(). Asking the thing under test what
	# it ought to have said makes both sides of the comparison move together: the mutation that
	# swapped held for bank_size changed the surface AND the expectation, and passed. An
	# expectation has to be written independently or it is not an expectation.
	var sentence := "TRACKS %d-%d OF %d" % [first, last, total]
	for named in [
			["console", ConsoleSurface.new(), ["%d-%d" % [first, last], "OF %d" % total]],
			["timeline", TimelineSurface.new(), [sentence]],
			["patchbay", PatchbaySurface.new(), [sentence]]]:
		var surface: Surface = named[1]
		add_child(surface)
		surface._process(0.0)
		var texts: Array[String] = []
		for node in surface.find_children("*", "Label3D", true, false):
			texts.append((node as Label3D).text)
		for wanted in named[2]:
			check("the %s says exactly \"%s\"" % [named[0], wanted], texts.has(wanted))
		surface.queue_free()

	# And the other half of the rule, which is the half that erodes: a caption that is always
	# there is one people stop reading. A session that fits must be uncaptioned.
	DAW.use(OfflineBackend.new())
	check("the stand-in on its own fits in a bank", not DAW.state.has_more_banks())
	for named in [["console", ConsoleSurface.new()], ["timeline", TimelineSurface.new()],
			["patchbay", PatchbaySurface.new()]]:
		var surface: Surface = named[1]
		add_child(surface)
		surface._process(0.0)
		var shouted := false
		for node in surface.find_children("*", "Label3D", true, false):
			if (node as Label3D).text.contains(" OF "):
				shouted = true
				break
		check("the %s is quiet about a session that fits" % named[0], not shouted)
		surface.queue_free()


func _test_one_jack_takes_one_plug() -> void:
	# The physical premise of a patchbay: four tracks sending to the reverb return must not be
	# four cables ending in the same bore. The bay gives every row one more jack than its busiest
	# row needs, so each cable has its own.
	DAW.use(OfflineBackend.new())
	var bay := PatchbaySurface.new()
	add_child(bay)
	bay._process(0.0)
	bay._draw_cables()

	var cables: Array = bay._cables
	check("the stand-in session patches the bay", cables.size() >= 4)
	var ends: Array[Vector3] = []
	for cable in cables:
		var c: PatchCable = cable
		ends.append(c.from_xform.origin)
		ends.append(c.to_xform.origin)
	var closest := INF
	for i in ends.size():
		for j in range(i + 1, ends.size()):
			closest = minf(closest, ends[i].distance_to(ends[j]))
	check("no two plugs share a bore (%.1fmm apart)" % (closest * 1000.0),
			closest >= PatchCable.PLUG_RADIUS * 2.0)
	# The four into the return fill four jacks, and the row still has a free one.
	var verb := bay.input_row(13)
	check("the return's row has a plug per send", verb != null and verb.used == 4)
	check("and a jack to spare", verb.jack_xs.size() > verb.used)
	check("every row has as many jacks", bay.output_row(1).jack_xs.size() == verb.jack_xs.size())
	bay.queue_free()


func _test_the_bay_reads_left_to_right() -> void:
	# FROM on the left, TO on the right, every cable crossing the gap between them: which track
	# feeds which is something you see.
	DAW.use(OfflineBackend.new())
	var bay := PatchbaySurface.new()
	add_child(bay)
	bay._process(0.0)
	bay._draw_cables()
	for index in DAW.state.track_indices():
		check("%d's output is on the left" % index, bay.output_row(index).position.x < 0.0)
		check("%d's input is on the right" % index, bay.input_row(index).position.x > 0.0)
	var crossing := true
	for cable in bay._cables:
		var c: PatchCable = cable
		var a := bay.to_local(c.from_xform.origin)
		var b := bay.to_local(c.to_xform.origin)
		crossing = crossing and a.x < -0.05 and b.x > 0.05
	check("every cable runs from the FROM column to the TO column", crossing)
	# Names inside the bay: the jacks are on the gap side of each column, the names outside.
	var row := bay.output_row(1)
	var name_label := row.get_node("Name") as Label3D
	check("a FROM row's name is outside its jacks", name_label.position.x < row.jack_xs.min())
	var to_row := bay.input_row(1)
	check("a TO row's name is outside its jacks",
			(to_row.get_node("Name") as Label3D).position.x > to_row.jack_xs.max())
	check("a row's name is big enough to read across a room (%.1fmm caps)"
			% (Lettering.cap_height(name_label) * 1000.0), Lettering.cap_height(name_label) >= 0.012)
	bay.queue_free()


## A fake hand for the drag tests: an Interactor that is told what it is over.
func _bay_hand(over: ControlAffordance) -> Interactor:
	var hand := Interactor.new()
	hand.hovered = over
	return hand


func _drag(hand: Interactor, from: ControlAffordance, to: ControlAffordance) -> void:
	from.grab_begin(hand, from.global_position)
	hand.hovered = to
	from.grab_move(hand, to.global_position if to != null else from.global_position + Vector3(0, -2, 0))
	from.grab_end(hand)


func _test_dragging_across_the_bay_patches_and_unpatches() -> void:
	var backend := OfflineBackend.new()
	DAW.use(backend)
	var bay := PatchbaySurface.new()
	add_child(bay)
	bay._process(0.0)
	bay._draw_cables()
	check("the stand-in can patch now", DAW.can(DAWBackend.Capability.ROUTING))

	# A new send: drag the kick's row across to the bass's.
	var before := DAW.state.track(1).sends.size()
	var hand := _bay_hand(null)
	var from := bay.output_row(1)
	from.grab_begin(hand, from.global_position)
	check("picking up a row carries a cable", bay.find_child("CarriedCable", true, false) != null)
	check("the rows it could go to light up",
			bay.input_row(4).light() == PatchPoint.Light.CANDIDATE)
	check("but not its own input", bay.input_row(1).light() == PatchPoint.Light.PLAIN)
	hand.hovered = bay.input_row(4)
	from.grab_move(hand, bay.input_row(4).global_position)
	check("the row under it says it is where the cable goes",
			bay.input_row(4).light() == PatchPoint.Light.TARGET)
	from.grab_end(hand)
	check("letting go there makes the send", DAW.state.track(1).sends.size() == before + 1)
	var made: MixState.SendState = DAW.state.track(1).sends[before + 1]
	check("to the row it was let go on", made.resolve(DAW.state) == 4)
	check("at unity", absf(FaderLaw.to_db(made.volume)) < 0.05)
	check("and nothing is left lit", bay.input_row(4).light() == PatchPoint.Light.PLAIN)

	# Dropped on nothing, nothing happens.
	bay._process(0.0)
	bay._draw_cables()
	var count := DAW.state.track(2).sends.size()
	_drag(hand, bay.output_row(2), null)
	check("a cable let go over nothing goes back", DAW.state.track(2).sends.size() == count)
	# Nor twice into the same place.
	bay._process(0.0)
	_drag(hand, bay.output_row(1), bay.input_row(4))
	check("the same send twice is refused", DAW.state.track(1).sends.size() == before + 1)

	# Scroll a plug: the level.
	bay._process(0.0)
	bay._draw_cables()
	var plug: PatchPlug = bay.plugs_of(1, before + 1)[0]
	check("the new cable has a plug to hold", plug != null)
	check("which names the send", plug.title() == "%s  →  %s" % [
			DAW.state.track(1).display_name().to_upper(), DAW.state.track(4).display_name().to_upper()])
	plug.nudge(hand, -6, false)
	close_to("scrolling a plug sets the send level", FaderLaw.to_db(made.volume), -6.0, 0.05)
	check("and says so", plug.readout() == "-6.0 dB")

	# Re-patch the TO end to another row.
	var into: PatchPlug = bay.plugs_of(1, before + 1)[1]
	_drag(hand, into, bay.input_row(6))
	var moved: Array = DAW.state.track(1).sends.values().map(
			func(sd): return (sd as MixState.SendState).resolve(DAW.state))
	check("a plug dragged to another row re-patches", moved.has(6) and not moved.has(4))

	# Pull it off: gone.
	bay._process(0.0)
	bay._draw_cables()
	var last := DAW.state.track(1).sends.size()
	var pulled: PatchPlug = bay.plugs_of(1, last)[0]
	_drag(hand, pulled, null)
	check("a plug pulled off the bay unplugs the send", DAW.state.track(1).sends.size() == last - 1)
	# A wiggle -- picked up and put back on its own row -- changes nothing.
	bay._process(0.0)
	bay._draw_cables()
	var verb_sends := DAW.state.track(3).sends.size()
	var wiggled: PatchPlug = bay.plugs_of(3, 1)[0]
	_drag(hand, wiggled, wiggled.row)
	check("a plug put back where it was stays patched", DAW.state.track(3).sends.size() == verb_sends)

	# And the whole lot is one undo per change, like Reaper.
	backend.undo()
	check("undo puts the unplugged send back", DAW.state.track(1).sends.size() == last)
	hand.free()
	bay.queue_free()


func _test_hovering_a_row_picks_out_its_cables() -> void:
	DAW.use(OfflineBackend.new())
	var bay := PatchbaySurface.new()
	add_child(bay)
	bay._process(0.0)
	bay._draw_cables()
	var hand := Node.new()
	bay.output_row(3).hover_enter(hand)
	var lit := 0
	var dim := 0
	for cable in bay._cables:
		if (cable as PatchCable).dimmed:
			dim += 1
		else:
			lit += 1
	check("hovering a row keeps its own cable lit", lit == 1)
	check("and dims the rest", dim == bay._cables.size() - 1)
	check("and lights the row at the other end",
			bay.input_row(13).light() == PatchPoint.Light.EMPHASIS)
	bay.output_row(3).hover_exit(hand)
	check("leaving it lights everything again",
			bay._cables.all(func(c): return not (c as PatchCable).dimmed))
	hand.free()
	bay.queue_free()


func _test_a_removed_send_leaves_the_mix() -> void:
	# Every other send address can only say what a send IS; this one says how many there are,
	# which is the only way a pulled cable stops being drawn -- on the host and on every guest.
	var state := MixState.new()
	state.project_track_count = 4
	for k in [1, 2, 3]:
		MixWire.apply(state, "/track/1/send/%d/dest" % k, [float(k + 1)])
	MixWire.apply(state, "/track/1/sends", [2.0])
	check("a send past the count is gone", state.track(1).sends.keys() == [1, 2])
	var snap := MixWire.snapshot(state)
	var said := snap.filter(func(pair): return pair[0] == "/track/1/sends")
	check("and the count travels in a snapshot", said.size() == 1 and int(said[0][1][0]) == 2)


func _names_on(state: MixState, track_index: int) -> Array:
	var t := state.track(track_index)
	return t.plugins().map(func(i): return (t.fx[i] as MixState.FXState).name)


func _test_a_plugin_moves_and_copies_along_the_chains() -> void:
	# Torn off the rack and dropped somewhere else, a plugin has to land there with its settings
	# and leave its old slot empty -- on the host and, through the wire, on every guest.
	var backend := OfflineBackend.new()
	DAW.use(backend)
	var state := DAW.state
	check("the stand-in can rearrange a chain", DAW.can(DAWBackend.Capability.FX_CHAIN))
	check("track 2 starts EQ then compressor", _names_on(state, 2) == ["ReaEQ", "ReaComp"])
	var comp_threshold: float = state.fx(2, 1).params[0]

	DAW.move_fx(2, 1, 2, 0)
	check("moved up its own chain", _names_on(state, 2) == ["ReaComp", "ReaEQ"])
	check("and took its settings with it", is_equal_approx(state.fx(2, 0).params[0], comp_threshold))
	check("its names came too", state.fx(2, 0).param_names[0] == "Thresh")

	var guest := MixState.new()
	MixWire.apply_replicated(guest, MixWire.snapshot(state))
	DAW.move_fx(2, 0, 6, 99)
	check("moved to the end of another track's chain", _names_on(state, 6) == ["ReaComp", "ReaComp"])
	check("and gone from where it was", _names_on(state, 2) == ["ReaEQ"])
	MixWire.apply_replicated(guest, MixWire.snapshot(state))
	check("a guest sees the slot it left empty", _names_on(guest, 2) == ["ReaEQ"])
	check("and the plugin where it went", _names_on(guest, 6) == ["ReaComp", "ReaComp"])

	DAW.move_fx(10, 1, 13, 0, true)
	check("a copy goes in front", _names_on(state, 13) == ["ReaVerbate", "ReaVerbate"])
	check("and leaves the original", _names_on(state, 10) == ["ReaEQ", "ReaVerbate"])

	DAW.undo()
	check("undo takes the copy back", _names_on(state, 13) == ["ReaVerbate"])
	DAW.undo()
	check("and puts the moved one back", _names_on(state, 2) == ["ReaComp", "ReaEQ"] \
			and _names_on(state, 6) == ["ReaComp"])

	check("move_fx is a verb a guest may use", &"move_fx" in DAW.COMMANDS)
	DAW.apply_intent(&"move_fx", [2, -1, 6, 0, false])
	check("a malformed move from a peer is refused", _names_on(state, 2) == ["ReaComp", "ReaEQ"])


func _test_wet_and_presets_ride_the_wire() -> void:
	var backend := OfflineBackend.new()
	DAW.use(backend)
	var state := DAW.state
	DAW.set_fx_wet(6, 0, 0.35)
	check("wet/dry is the plugin's own field", is_equal_approx(state.fx(6, 0).wet, 0.35))
	var guest := MixState.new()
	MixWire.apply_replicated(guest, MixWire.snapshot(state))
	check("and a guest hears it", is_equal_approx(guest.fx(6, 0).wet, 0.35))
	DAW.undo()
	check("undo puts it back to all plugin", is_equal_approx(state.fx(6, 0).wet, 1.0))

	var before: Dictionary = state.fx(6, 0).params.duplicate()
	DAW.step_fx_preset(6, 0, 1)
	var preset := state.fx(6, 0).preset
	check("stepping lands on a named preset", preset != "" and preset != "Default")
	check("and the preset moves the knobs", state.fx(6, 0).params != before)
	MixWire.apply_replicated(guest, MixWire.snapshot(state))
	check("a guest reads the same preset", guest.fx(6, 0).preset == preset)
	DAW.step_fx_preset(6, 0, -1)
	check("and back again", state.fx(6, 0).preset == "Default")
	for verb in [&"set_fx_wet", &"step_fx_preset"]:
		check("%s is a verb a guest may use" % verb, verb in DAW.COMMANDS)


func _test_a_sidechain_is_a_send_into_the_key() -> void:
	var backend := OfflineBackend.new()
	DAW.use(backend)
	var state := DAW.state
	check("a sidechain can be made", DAW.create_sidechain(1, 6))
	var keyed: Array = state.track(1).sends.values().filter(
			func(s): return (s as MixState.SendState).resolve(state) == 6)
	check("as a send to the keyed track", keyed.size() == 1)
	check("into its key, not its mix", keyed.size() == 1 and (keyed[0] as MixState.SendState).key)
	check("a second key from the same track is refused", not DAW.create_sidechain(1, 6))
	check("but an ordinary send alongside it is not", DAW.create_send(1, 6))
	var guest := MixState.new()
	MixWire.apply_replicated(guest, MixWire.snapshot(state))
	var guest_keys := guest.track(1).sends.values().filter(func(s): return (s as MixState.SendState).key)
	check("a guest knows which is the key", guest_keys.size() == 1)
	check("create_sidechain is a verb a guest may use", &"create_sidechain" in DAW.COMMANDS)


## A tablet is a plugin's face laid out from the plugin's own parameters, and every control on it
## writes the plugin it is showing.
func _test_a_tablet_is_built_from_its_plugin() -> void:
	DAW.use(OfflineBackend.new())
	var state := DAW.state
	var order := state.track(2).plugins()
	var slot: int = order[1]
	var f := state.fx(2, slot)
	var total := f.params.size()
	check("the stand-in has a plugin that overflows a tablet", total > PluginTablet.PER_PAGE)

	var tablet := PluginTablet.create(2, slot, f.name)
	add_child(tablet)
	tablet._process(0.0)
	check("a full page of knobs", tablet._knobs.size() == PluginTablet.PER_PAGE)
	check("captioned with the plugin's own names",
			tablet._captions[0].text == str(f.param_names[0]).to_upper())
	check("the title is the plugin", tablet._title.text == f.name)
	check("it says where on the chain it is", tablet._chain_label.text == "2 OF %d" % order.size())
	check("and that there are more parameters than knobs",
			tablet._page_label.visible and tablet._page_label.text == "1-12 OF %d" % total)

	var before: float = f.params[0]
	tablet._knobs[0].turned.emit(clampf(before + 0.3, 0.0, 1.0) if before < 0.6 else before - 0.3)
	check("a knob writes its parameter", not is_equal_approx(state.fx(2, slot).params[0], before))

	tablet._step_page(1)
	tablet._process(0.0)
	check("the next page holds what is left",
			tablet._knobs.size() == total - PluginTablet.PER_PAGE and tablet._param_for(0) == PluginTablet.PER_PAGE)

	tablet._bypass.pressed.emit()
	check("power bypasses it", not state.fx(2, slot).enabled)
	tablet._mix.turned.emit(0.4)
	check("mix sets its wet/dry", is_equal_approx(state.fx(2, slot).wet, 0.4))
	tablet.refresh()
	check("and the reading follows", tablet._mix_label.text == "40%")
	tablet._preset_next.pressed.emit()
	check("a preset can be stepped to", state.fx(2, slot).preset not in ["", "Default"])
	tablet.refresh()
	check("and is named on the face", tablet._preset_label.text == state.fx(2, slot).preset)
	var docked := [false]
	tablet.dock_requested.connect(func(): docked[0] = true)
	tablet.get_node("Dock").pressed.emit()
	check("DOCK asks for the tablet to be put away", docked[0])
	remove_child(tablet)
	tablet.free()


## Moving a plugin is done from its tablet, and the tablet goes with it.
func _test_a_tablet_follows_its_plugin_along_the_chain() -> void:
	DAW.use(OfflineBackend.new())
	var state := DAW.state
	var order := state.track(2).plugins()
	var plugin := state.fx(2, order[1]).name
	var tablet := PluginTablet.create(2, order[1], plugin)
	add_child(tablet)
	tablet._process(0.0)
	check("the last plugin cannot go later", not tablet._chain_down.lit and tablet._chain_up.lit)

	tablet._shift(-1)
	tablet._process(0.0)
	check("it moves up its chain", _names_on(state, 2)[0] == plugin)
	check("and the tablet still shows it", tablet.fx().name == plugin and not tablet.lost)
	check("now first", tablet._chain_label.text == "1 OF %d" % order.size())
	tablet._shift(1)
	tablet._process(0.0)
	check("and back down", _names_on(state, 2)[-1] == plugin and tablet.fx().name == plugin)

	tablet.move_to_track(6)
	tablet._process(0.0)
	check("it moves to another track", _names_on(state, 6)[-1] == plugin)
	check("the tablet goes with it", tablet.track_index == 6 and tablet.fx().name == plugin)
	check("and is not lost", not tablet.lost and not tablet._lost_label.visible)

	# Gone altogether -- deleted, or renamed in the DAW -- it says so, and its controls write
	# nothing: the slot it was pointing at now holds something else, or nothing.
	var at := tablet.fx_index
	var wet: float = state.fx(6, at).wet
	tablet.fx_name = "Nothing By This Name"
	tablet._on_fx_shape_changed(6, at)
	tablet._run_later()
	tablet._process(0.0)
	check("a plugin that has gone is shown as gone", tablet.lost and tablet._lost_label.visible)
	tablet._mix.turned.emit(0.1)
	check("and a lost tablet writes nothing", is_equal_approx(state.fx(6, at).wet, wet))
	remove_child(tablet)
	tablet.free()


func _test_a_tablet_keys_its_plugin_from_another_track() -> void:
	DAW.use(OfflineBackend.new())
	var state := DAW.state
	var order := state.track(2).plugins()
	var tablet := PluginTablet.create(2, order[1], state.fx(2, order[1]).name)
	add_child(tablet)
	tablet._process(0.0)
	check("nothing keys it yet", tablet.keyed_by().is_empty() and not tablet._key.lit)
	check("its own track is not offered", not tablet._other_tracks().any(func(o): return o[0] == 2))

	tablet._key.choice = 1
	tablet._key.pressed.emit(1)
	check("KEY IN patches a sidechain", tablet.keyed_by() == [1])
	check("into the key", state.track(1).sends.values().any(
			func(s): return s.key and s.resolve(state) == 2))
	check("and the window lights", tablet._key.lit)
	tablet._key.pressed.emit(1)
	check("pressed again it pulls it", tablet.keyed_by().is_empty() and not tablet._key.lit)
	remove_child(tablet)
	tablet.free()


## Pulled off the rack, a plugin stands on the floor on its own stand; docked, the stand goes.
## The list of what is out is part of the layout, and comes back next time.
func _test_a_plugin_torn_off_the_rack_gets_a_stand() -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	studio.focus.visits = false
	var order := DAW.state.track(2).plugins()
	var plugin := DAW.state.fx(2, order[1]).name
	var surfaces := studio.focus.surfaces.size()

	studio.rack.tear_requested.emit(2, order[1], studio.rack.global_position)
	check("pulling a plugin off the rack stands it on a tablet", studio.tablets.size() == 1)
	var id: StringName = studio.tablets.keys()[0]
	var stand: Trolley = studio.tablets[id][0]
	var tablet: PluginTablet = studio.tablets[id][1]
	check("showing that plugin", tablet.fx_name == plugin and tablet.track_index == 2)
	check("on the floor", is_equal_approx(stand.global_position.y, 0.0))
	check("in front of the rack, not in it",
			stand.global_position.distance_to(studio.rack.global_position * Vector3(1, 0, 1)) > 0.4)
	check("and something F can find", studio.focus.surfaces.size() == surfaces + 1)
	check("it is written down", Session.layout.tablets.get(id, []) == [2, order[1], plugin])

	studio.rack.tear_requested.emit(2, order[1], studio.rack.global_position)
	check("pulling the same plugin again brings the same stand", studio.tablets.size() == 1)

	var reloaded := LayoutProfile.new()
	reloaded.save_path = Session.layout.save_path
	reloaded.load_saved()
	check("the stand survives a restart", reloaded.tablets.get(id, []) == [2, order[1], plugin])

	tablet.dock_requested.emit()
	check("docking puts the stand away", studio.tablets.is_empty() and not is_instance_valid(stand) \
			or stand.is_queued_for_deletion())
	check("and F no longer finds it", studio.focus.surfaces.size() == surfaces)
	check("and it is forgotten", Session.layout.tablets.is_empty())
	remove_child(studio)
	studio.free()
	Session.layout = saved_layout
	DAW.use(OfflineBackend.new())


## In a session the room is the host's: the venue and the plugins out on stands are the same for
## everyone in it. A guest asks for a stand and is shown the host's room; it cannot change the
## venue; and its own room comes back when it is on its own again.
func _test_the_room_is_the_hosts() -> void:
	var saved_layout := Session.layout
	var saved_role := Session.role
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	studio.focus.visits = false
	var order := DAW.state.track(2).plugins()
	var plugin := DAW.state.fx(2, order[1]).name

	# The host, answering a guest: the same stand its own hand would have pulled.
	studio._on_room_asked(&"open_tablet", [2, order[1], plugin, 0.4, 0.2], 7)
	check("a guest's ask puts a stand out on the host", studio.tablets.size() == 1)
	var id: StringName = studio.tablets.keys()[0]
	var room := studio.room_state()
	check("and the room says so, where it stands (%s)" % [room], room["tablets"].has(id)
			and room["tablets"][id][0] == 2 and room["tablets"][id][2] == plugin
			and Vector2(room["tablets"][id][3], room["tablets"][id][4]).is_equal_approx(Vector2(0.4, 0.2)))
	studio._on_room_asked(&"move_tablet", [id, -0.3, 0.1, 0.5], 7)
	var stand: Trolley = studio.tablets[id][0]
	check("a guest wheeling it moves it on the host",
			Vector2(stand.position.x, stand.position.z).is_equal_approx(Vector2(-0.3, 0.1)))
	studio._on_room_asked(&"close_tablet", [id], 7)
	check("and docking it puts it away", studio.tablets.is_empty())
	var rack_home := Vector2(studio.rack_trolley.position.x, studio.rack_trolley.position.z)
	studio._on_room_asked(&"move_piece", [&"rack", rack_home.x - 0.2, rack_home.y + 0.1, 0.4], 7)
	check("a guest rolling the rack rolls it on the host", Vector2(studio.rack_trolley.position.x,
			studio.rack_trolley.position.z).is_equal_approx(rack_home + Vector2(-0.2, 0.1)))
	check("and the room says where it is", Vector2(studio.room_state()["floor"][&"rack"][0],
			studio.room_state()["floor"][&"rack"][1]).is_equal_approx(rack_home + Vector2(-0.2, 0.1)))
	var desk_at := studio.mount.studio_home(&"console").translated(Vector3(0.05, 0, 0))
	studio._on_room_asked(&"place_surface", [&"console", desk_at], 7)
	check("a guest putting the desk down puts it down on the host",
			studio.room_state()["placed"][&"console"].is_equal_approx(desk_at))
	studio._on_room_asked(&"move_piece", [&"rack", rack_home.x, rack_home.y, deg_to_rad(38.0)], 7)
	Session.layout.local_transforms.clear()
	studio.mount.share_studio({})
	check("only what a guest may ask is heard", not Session.room_ask_is_valid(&"set_venue", [&"grid"])
			and not Session.room_ask_is_valid(&"open_tablet", [2, "x"]))

	# A guest, shown the host's room.
	Session.role = Session.Role.GUEST
	var own_venue := studio.venue.venue_id()
	var own_choice := Session.layout.venue
	var notices: Array[String] = []
	var heard := func(t: String): notices.append(t)
	Session.notice.connect(heard)
	check("a guest cannot change the venue", not studio.choose_venue(&"grid")
			and studio.venue.venue_id() == own_venue)
	check("and is told why", notices.size() == 1 and notices[0].begins_with("Only "))
	Session.notice.disconnect(heard)
	studio.rack.tear_requested.emit(2, order[1], studio.rack.global_position)
	check("a guest's pull is out at once, under a name of its own (%s)" % [studio.tablets.keys()],
			studio.tablets.size() == 1 and String(studio.tablets.keys()[0]).begins_with("mine_"))
	check("and waits on the host's answer", studio._predictions.size() == 1
			and studio._predictions[0]["verb"] == &"open_tablet")
	for predicted in studio.tablets.keys():
		studio._take_down_tablet(predicted)
	studio._predictions.clear()
	Session.room_seq = 0

	var host_desk := studio.mount.studio_home(&"console").translated(Vector3(0, 0, 0.04))
	studio.apply_room({"venue": &"grid", "tablets": {&"tablet_3": [2, order[1], plugin, 0.4, 0.2, 0.25]},
			"floor": {&"rack": [rack_home.x - 0.25, rack_home.y + 0.05, 0.3]}, "placed": {&"console": host_desk}})
	check("the host's rack is where the host rolled it", Vector2(studio.rack_trolley.position.x,
			studio.rack_trolley.position.z).is_equal_approx(rack_home + Vector2(-0.25, 0.05)))
	check("and the host's desk where the host put it", studio.console.transform.is_equal_approx(host_desk))
	check("none of the furniture written into the guest's own layout",
			not Session.layout.has_transform(&"floor/rack", Presentation.Mode.STUDIO))
	studio.rack_trolley.place(rack_home + Vector2(-0.1, 0.0), 0.3)
	check("a guest rolling the rack is not its own layout",
			not Session.layout.has_transform(&"floor/rack", Presentation.Mode.STUDIO))
	check("the host's venue is the guest's", studio.venue.venue_id() == &"grid")
	check("and so are its stands", studio.tablets.has(&"tablet_3"))
	stand = studio.tablets[&"tablet_3"][0]
	check("where the host has them", Vector2(stand.position.x, stand.position.z).is_equal_approx(Vector2(0.4, 0.2))
			and is_equal_approx(stand.rotation.y, 0.25))
	check("none of it written into the guest's own layout",
			Session.layout.tablets.is_empty() and Session.layout.venue == own_choice)
	studio.apply_room({"venue": &"grid", "tablets": {}})
	check("a stand the host docks goes from the guest's room too", studio.tablets.is_empty())
	studio.apply_room({"venue": &"chalk", "tablets": {&"tablet_3": [2, order[1], plugin, 0.4, 0.2, 0.25]}})

	_check_a_guest_predicts_and_rolls_back(studio, order, plugin, rack_home)

	Session.role = Session.Role.SOLO
	studio._on_role_changed()
	check("on its own again, the guest is back in its own venue", studio.venue.venue_id() == own_venue)
	check("without the host's stands", studio.tablets.is_empty())
	check("with its rack back where it had it", Vector2(studio.rack_trolley.position.x,
			studio.rack_trolley.position.z).is_equal_approx(rack_home))
	check("and its own desk", not studio.console.transform.is_equal_approx(host_desk))
	remove_child(studio)
	studio.free()
	Session.role = saved_role
	Session.layout = saved_layout
	DAW.use(OfflineBackend.new())


## A guest's own moves happen at once and are kept over the host's room until the host has
## answered them; answered, the room is the truth, and what the host would not do goes back.
## Someone else's push rolls the stand after their hand rather than putting it down.
func _check_a_guest_predicts_and_rolls_back(studio: Studio, order: Array, plugin: String, rack_home: Vector2) -> void:
	var me := Session.local_peer_id
	var room := func(acked: int, tablets: Dictionary, rack: Vector2) -> Dictionary:
		return {"venue": &"chalk", "tablets": tablets, "floor": {&"rack": [rack.x, rack.y, 0.3]},
				"placed": {}, "acks": {me: acked}}
	studio.apply_room(room.call(0, {}, rack_home), false)
	check("the room is empty to start with", studio.tablets.is_empty())

	# Pulled off the rack: out at once, under the guest's own name.
	studio._predictions.clear()
	var mine := studio._predicted_tablet(2, order[1], plugin, Vector2(0.4, 0.2))
	var pulled: int = studio._predictions[-1]["seq"]
	var stand: Trolley = studio.tablets[mine][0]
	# And the rack wheeled, before the host has heard of either.
	studio.rack_trolley.place(rack_home + Vector2(0.15, 0.0), 0.3)
	var rolled: int = studio._predictions[-1]["seq"]
	check("both are waiting on the host", studio._predictions.size() == 2 and rolled > pulled
			and studio._predictions[-1]["verb"] == &"move_piece")

	studio.apply_room(room.call(pulled - 1, {}, rack_home), false)
	check("a room from before the ask does not take the guest's stand back", studio.tablets.has(mine))
	check("nor its rack", Vector2(studio.rack_trolley.position.x, studio.rack_trolley.position.z)
			.is_equal_approx(rack_home + Vector2(0.15, 0.0)))

	studio.apply_room(room.call(pulled, {&"tablet_9": [2, order[1], plugin, 0.4, 0.2, 0.0]}, rack_home), false)
	check("answered, the guest's stand takes the host's name", studio.tablets.has(&"tablet_9")
			and not studio.tablets.has(mine))
	check("and is the same stand, not a new one", studio.tablets.get(&"tablet_9", [null])[0] == stand)
	check("the rack, not yet answered, stays where the guest put it", Vector2(studio.rack_trolley.position.x,
			studio.rack_trolley.position.z).is_equal_approx(rack_home + Vector2(0.15, 0.0)))

	studio.apply_room(room.call(rolled, {&"tablet_9": [2, order[1], plugin, 0.4, 0.2, 0.0]}, rack_home), false)
	check("the host would not move the rack, so it goes back", Vector2(studio.rack_trolley.position.x,
			studio.rack_trolley.position.z).is_equal_approx(rack_home))
	check("and nothing is left waiting (%s)" % [studio._predictions], studio._predictions.is_empty())

	# A pull the host turns down.
	var refused := studio._predicted_tablet(3, 0, "Nothing", Vector2(0.0, 0.4))
	studio.apply_room(room.call(studio._predictions[-1]["seq"], {&"tablet_9": [2, order[1], plugin, 0.4, 0.2, 0.0]},
			rack_home), false)
	check("a stand the host would not put out is taken back", not studio.tablets.has(refused))

	# Someone else wheeling the rack: it rolls after them, and its coming to rest is not news.
	var asked := studio._predictions.size()
	studio._on_room_motion(&"rack", rack_home.x - 0.3, rack_home.y, 0.3, 5)
	studio.rack_trolley._physics_process(1.0 / 60.0)
	var moved_by := Vector2(studio.rack_trolley.position.x, studio.rack_trolley.position.z).distance_to(rack_home)
	check("someone else's push rolls the rack rather than putting it there (%.3f)" % moved_by,
			moved_by > 0.0 and moved_by < 0.3)
	for i in 240:
		studio.rack_trolley._physics_process(1.0 / 60.0)
	check("and it gets there", Vector2(studio.rack_trolley.position.x, studio.rack_trolley.position.z)
			.distance_to(rack_home + Vector2(-0.3, 0.0)) < 0.01)
	check("without the guest telling the host it moved it", studio._predictions.size() == asked
			and not studio.rack_trolley.steered)
	studio._take_down_tablet(&"tablet_9")


## Reaper names a plugin two ways depending on who is asked, and a VST3 reports thousands of MIDI
## CC slots past its own controls. What reaches the cache is one name and the real list.
func _test_a_big_plugin_is_listed_and_named_once() -> void:
	check("the type comes off a plugin's name",
			MixState.FXState.bare_name("VST3: Mantra (Neural DSP)") == "Mantra (Neural DSP)")
	check("and a name with a colon of its own keeps it",
			MixState.FXState.bare_name("Pro-Q 3: Mid") == "Pro-Q 3: Mid")
	var state := MixState.new()
	MixWire.apply(state, "/track/1/fx/1/name", ["VST3: Archetype Gojira X (Neural DSP)"])
	check("whichever road it came by", state.fx(1, 1).name == "Archetype Gojira X (Neural DSP)")
	MixWire.apply(state, "/track/1/fx/1/paramlist", [1.0, 2.0, 40.0, 139.0])
	MixWire.apply(state, "/track/1/fx/1/fxparam/40/name", ["HOT Amp Gain"])
	MixWire.apply(state, "/track/1/fx/1/presets", [0.0])
	check("the real list is the plugin's controls", state.fx(1, 1).controls() == [1, 2, 40, 139])
	check("and Reaper's preset count is kept", state.fx(1, 1).preset_count == 0)
	var guest := MixState.new()
	MixWire.apply_replicated(guest, MixWire.snapshot(state))
	check("a guest gets the list", guest.fx(1, 1).controls() == [1, 2, 40, 139])
	check("the names on it", guest.fx(1, 1).param_names.get(40) == "HOT Amp Gain")
	check("and the preset count", guest.fx(1, 1).preset_count == 0)
	MixWire.apply(state, "/track/1/fxs", [0.0])
	check("an emptied slot forgets its list", state.fx(1, 1).param_list.is_empty() \
			and state.fx(1, 1).preset_count == -1)

	DAW.use(OfflineBackend.new())
	check("read_fx_params is a verb a guest may use", &"read_fx_params" in DAW.COMMANDS)
	var refused := [0]
	for bad in [[2, 0], [2, 0, "all"], [0, 0, []], [2, 0, range(DAW.READ_PARAMS_MAX + 1)]]:
		DAW.apply_intent(&"read_fx_params", bad)
		refused[0] += 1
	check("and malformed reads are refused without a crash", refused[0] == 4)


## A tablet on a plugin with sections: a page per section where one fits, the section said once
## over the page, and the plugin's own preset buttons used when the DAW has no presets for it.
func _test_a_tablet_turns_over_to_the_plugins_own_window() -> void:
	var backend := OfflineBackend.new()
	DAW.use(backend)
	var state := DAW.state
	var slot: int = state.track(2).plugins()[0]
	var tablet := PluginTablet.create(2, slot, state.fx(2, slot).name)
	add_child(tablet)
	tablet._process(0.0)
	backend.stand_in_windows = true
	tablet.refresh()
	check("no UI button while the UI face is parked", not tablet._window_button.visible)
	tablet.show_window(true)
	check("and asking for it does nothing", not tablet.showing_window and backend.windows_opened.is_empty())
	PluginTablet.window_face = true
	backend.stand_in_windows = false
	tablet.refresh()
	check("no UI button where the window cannot be shown", not tablet._window_button.visible \
			and not tablet._window_word.visible)
	tablet.show_window(true)
	check("and asking for it does nothing", not tablet.showing_window and backend.windows_opened.is_empty())

	backend.stand_in_windows = true
	tablet.refresh()
	check("a UI button where it can", tablet._window_button.visible and not tablet._window_button.lit)
	tablet._window_button.pressed.emit()
	tablet._process(0.0)
	check("pressed, the plugin's window is opened", tablet.showing_window and backend.windows_opened.size() == 1)
	var window: PluginWindow = backend.windows_opened[0]
	check("and shown where the knobs were", tablet._knobs.is_empty() and is_instance_valid(tablet._screen) \
			and tablet._screen.window == window and tablet._window_button.lit)
	check("the footer stays", is_instance_valid(tablet._mix) and is_instance_valid(tablet._key) \
			and is_instance_valid(tablet._move_to))
	check("the preset and page rows give it room", not tablet._preset_label.visible \
			and not tablet._preset_word.visible and not tablet._page_label.visible)

	var screen := tablet._screen
	screen._process(0.0)
	check("the picture keeps its shape (%s)" % screen._shown,
			is_equal_approx(screen._shown.x / screen._shown.y, 400.0 / 300.0) \
			and screen._shown.y <= screen.size.y + 0.0001 and screen._shown.x <= screen.size.x + 0.0001)
	screen.grab_begin(self, screen.global_position)
	check("a press on the picture is a press on the window, there (%s)" % [window.events],
			window.events.has([&"down", 200, 150, 1]))
	screen.grab_move(self, screen.to_global(Vector3(screen._shown.x, screen._shown.y, 0)))
	check("a drag past its edge stays on the window", window.events[-1] == [&"move", 399, 0, 0])
	screen.grab_end(self)
	check("and lets go there", window.events[-1] == [&"up", 399, 0, 1])
	screen.nudge(self, -2, false)
	check("the wheel turns what is under the pointer", window.events[-1] == [&"wheel", 399, 0, -2])

	tablet.move_to_track(3)
	tablet._process(0.0)
	tablet._process(0.0)
	check("moved, the plugin's new window is opened and the old one put away",
			tablet.track_index != 2 and backend.windows_opened.size() == 2 and not window.is_open() \
			and backend.windows_opened[1].is_open())
	window = backend.windows_opened[1]

	tablet._window_button.pressed.emit()
	tablet._process(0.0)
	check("pressed again, the knobs are back and the window put away", not tablet.showing_window \
			and not tablet._knobs.is_empty() and not window.is_open() and tablet._preset_word.visible)

	tablet.show_window(true)
	window = backend.windows_opened[-1]
	remove_child(tablet)
	tablet.free()
	check("a tablet put away puts its window away", not window.is_open())
	PluginTablet.window_face = false
	DAW.use(OfflineBackend.new())


func _test_a_tablet_pages_by_section_and_steps_the_plugins_own_presets() -> void:
	DAW.use(OfflineBackend.new())
	var state := DAW.state
	var slot: int = state.track(2).plugins()[0]
	var f := state.fx(2, slot)
	var names := ["Input Gain", "Output Gain", "Preset Previous", "Preset Next", "Transpose"]
	for amp in ["CLN", "HOT"]:
		for knob in ["Gain", "Bass", "Mid", "Treble", "Master", "Output"]:
			names.append("%s Amp %s" % [amp, knob])
	names.append("Bypass")
	f.params.clear()
	f.param_names.clear()
	f.param_list = []
	for i in names.size():
		f.params[i] = 0.5
		f.param_names[i] = names[i]
		f.param_list.append(i)
	f.preset_count = 0
	var tablet := PluginTablet.create(2, slot, f.name)
	add_child(tablet)
	tablet._process(0.0)

	check("the plugin's preset buttons are not knobs", not tablet._params().has(2) and not tablet._params().has(3))
	check("they are the PRESET buttons", tablet._own_presets() and tablet._preset_next.visible \
			and tablet._preset_label.text == "plugin's own")
	check("the first page stops where a section begins (%s)" % tablet._page_label.text,
			tablet._knobs.size() == 3)
	tablet._step_page(1)
	tablet._process(0.0)
	check("a section gets its own page", tablet._knobs.size() == 6 and tablet._page_section() == "CLN AMP")
	check("named once, over the page (%s)" % tablet._page_label.text, tablet._page_label.text.begins_with("CLN AMP"))
	check("so each knob says only what is its own", tablet._captions[0].text == "GAIN")
	tablet._step_page(1)
	tablet._process(0.0)
	check("and a last scrap joins the page before it", tablet._knobs.size() == 7 \
			and tablet._captions[6].text == "BYPASS" and not tablet._page_next.lit)
	tablet._step_page(-1)
	tablet._step_page(-1)
	tablet._process(0.0)
	check("and back to the start", tablet.page_offset == 0)

	# A page of one or two is folded into its neighbour, and a page led by a section's own
	# on/off is still that section's page.
	f.param_list = [5, 6, 7, 8, 9, 10, 0, 11, 12, 13, 14, 15, 16]
	f.param_names[0] = "Active Hot Section"
	tablet._step_page(1)
	tablet._process(0.0)
	tablet.page_offset = 0
	tablet.mark_dirty()
	tablet._process(0.0)
	check("a stray switch joins the section after it (%s)" % [tablet._page_starts()],
			tablet._page_starts() == [0, 6])
	tablet._step_page(1)
	tablet._process(0.0)
	check("which keeps its heading (%s)" % tablet._page_label.text, tablet._page_section() == "HOT AMP" \
			and tablet._captions[0].text == "ACTIVE HOT SECTION" and tablet._captions[1].text == "GAIN")
	f.param_names[0] = "Input Gain"
	f.param_list = range(names.size())
	tablet.page_offset = 0
	tablet.mark_dirty()
	tablet._process(0.0)

	tablet._preset_next.pressed.emit()
	check("PRESET ▶ presses the plugin's own button", is_equal_approx(state.fx(2, slot).params[3], 1.0))
	await get_tree().create_timer(0.2).timeout
	check("and lets go of it", is_equal_approx(state.fx(2, slot).params[3], 0.0))

	# Moved from anywhere else -- the plugin's own window, automation -- the knob follows.
	state.fx(2, slot).params[0] = 0.9
	tablet._process(0.0)
	check("a knob follows its parameter", is_equal_approx(tablet._knobs[0].value, 0.9))

	f.param_names[3] = "Something Else"
	tablet.refresh()
	check("with no presets anywhere it says so", tablet._preset_label.text == "none saved" \
			and not tablet._preset_next.visible)
	remove_child(tablet)
	tablet.free()
	DAW.use(OfflineBackend.new())


func _test_a_banked_control_still_moves() -> void:
	# The knob and the fader cap are the only MOVING geometry that got instanced, and the whole
	# objection to instancing them was that a bank is filled once. It is not -- a transform is
	# per-instance -- but that only holds if the move actually reaches the buffer, and a
	# MultiMesh that never updated would look exactly like a desk whose controls are frozen in
	# whatever position they were built at. Nothing else in the suite would notice.
	#
	# Mounted under a tilted, offset, rotated parent on purpose. A bank slot is composed
	# through the entire chain from the bank's own transform down, and a test done at the
	# origin agrees with every wrong composition.
	DAW.use(OfflineBackend.new())
	var desk := Node3D.new()
	desk.position = Vector3(0.31, 0.92, -0.14)
	desk.rotation_degrees = Vector3(-24.0, 11.0, 0.0)
	add_child(desk)

	var cap_bank := MeshBank.of(
		Fader.MESH_PATH,
		Materials.cap_plastic(Color(0.17, 0.18, 0.2)),
		{"indicator": Materials.legend()})
	var knob_bank := MeshBank.of(
		Knob.MESH_PATH,
		Materials.cap_plastic(Color(0.14, 0.15, 0.17)),
		{"indicator": Materials.legend()})
	check("the fader cap asset resolves", cap_bank != null)
	check("the knob asset resolves", knob_bank != null)
	if cap_bank == null or knob_bank == null:
		desk.queue_free()
		return
	desk.add_child(cap_bank)
	desk.add_child(knob_bank)

	# One of each on both paths, at the same place, so the comparison is instanced-against-loose
	# rather than instanced-against-a-formula-written-twice.
	var banked_fader := Fader.new()
	banked_fader.cap_bank = cap_bank
	banked_fader.position = Vector3(0.05, 0.02, 0.004)
	desk.add_child(banked_fader)
	var loose_fader := Fader.new()
	loose_fader.position = Vector3(0.05, 0.02, 0.004)
	desk.add_child(loose_fader)

	var banked_knob := Knob.new()
	banked_knob.body_bank = knob_bank
	banked_knob.position = Vector3(-0.03, 0.11, 0.004)
	desk.add_child(banked_knob)
	var loose_knob := Knob.new()
	loose_knob.position = Vector3(-0.03, 0.11, 0.004)
	desk.add_child(loose_knob)

	cap_bank.commit()
	knob_bank.commit()

	var cap_seen: Array[Vector3] = []
	var knob_seen: Array[Basis] = []
	for v in [0.0, 0.5, 1.0]:
		banked_fader.value = v
		banked_fader._on_value_changed()
		loose_fader.value = v
		loose_fader._on_value_changed()
		var cap_slot := cap_bank.global_transform * cap_bank.transform_of(0)
		var cap_gap: float = cap_slot.origin.distance_to(loose_fader._cap.global_transform.origin)
		check("a banked cap at %.1f sits where a loose one does (%.2fmm)" % [v, cap_gap * 1000.0],
				cap_gap < 0.0002)
		cap_seen.append(cap_slot.origin)

		banked_knob.value = v
		banked_knob._on_value_changed()
		loose_knob.value = v
		loose_knob._on_value_changed()
		var knob_slot := knob_bank.global_transform * knob_bank.transform_of(0)
		var knob_gap: float = knob_slot.origin.distance_to(loose_knob._aim.global_transform.origin)
		check("a banked knob at %.1f sits where a loose one does (%.2fmm)" % [v, knob_gap * 1000.0],
				knob_gap < 0.0002)
		knob_seen.append(knob_slot.basis.orthonormalized())

	# And it moved the right distance, which the agreement above cannot show: two frozen caps
	# agree with each other perfectly. 100mm of travel, measured end to end.
	var travelled: float = cap_seen[0].distance_to(cap_seen[2])
	check("the cap travelled its full throw (%.1fmm)" % (travelled * 1000.0),
			absf(travelled - Fader.TRAVEL) < 0.0005)
	check("and half of it at half value",
			absf(cap_seen[0].distance_to(cap_seen[1]) - Fader.TRAVEL * 0.5) < 0.0005)

	# The knob's 270-degree sweep, taken in two halves because an angle between two vectors
	# cannot express more than 180 and a single end-to-end reading would come back as 90.
	var lower: float = knob_seen[0].x.angle_to(knob_seen[1].x)
	var upper: float = knob_seen[1].x.angle_to(knob_seen[2].x)
	check("the knob turned half its sweep to centre (%.1f deg)" % rad_to_deg(lower),
			absf(lower - Knob.SWEEP * 0.5) < 0.01)
	check("and the other half past it (%.1f deg)" % rad_to_deg(upper),
			absf(upper - Knob.SWEEP * 0.5) < 0.01)

	desk.queue_free()


## How tall you are moves the eye and nothing else, and is remembered.
func _test_a_person_says_how_tall_they_are() -> void:
	var e := Ergonomics.standing()
	close_to("the default person stands with their eyes at 1.47m", e.eye_height, 1.47, 0.001)
	var room_desk := e.desk_height()
	e.set_height(1.50)
	close_to("someone 1.50 tall has their eyes at 1.39", e.eye_height, 1.39, 0.001)
	check("and a lower desk to work at", e.desk_height() < room_desk)
	var sitting := Ergonomics.seated_default()
	sitting.set_height(1.50)
	check("sitting, the same person's eyes are lower again", sitting.eye_height < e.eye_height)
	e.set_height(9.0)
	close_to("a height nobody is is held to one somebody is", e.eye_height,
			Ergonomics.HEIGHT_RANGE.y - Ergonomics.EYE_BELOW_CROWN, 0.001)

	var path := "user://test_body.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check("nobody has said a height yet", Ergonomics.load_height(path) == 0.0)
	Ergonomics.save_height(1.61, path)
	close_to("a height said is remembered", Ergonomics.load_height(path), 1.61, 0.001)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A fifty-plugin project racked whole was six bays across and twice the frame time. The rack
## holds one track's chain: whichever track is selected in Reaper, or whichever the window over
## it is scrolled to, and a track with nothing on it says so rather than standing empty.
func _test_the_rack_holds_one_track_and_follows_the_selection() -> void:
	DAW.use(OfflineBackend.new())
	var rack := RackSurface.new()
	add_child(rack)
	rack._process(0.0)

	var with_plugins: Array = []
	var bare := -1
	for t in DAW.state.track_indices():
		if DAW.state.track(t).plugins().is_empty():
			bare = t if bare < 0 else bare
		else:
			with_plugins.append(t)
	check("the stand-in has two tracks with plugins (%d)" % with_plugins.size(), with_plugins.size() >= 2)
	var racked := func() -> Array:
		var out: Array = []
		for n in rack.find_children("*", "Node3D", true, false):
			if n is RackUnit and not n.is_queued_for_deletion():
				out.append([(n as RackUnit).track_index, (n as RackUnit).fx_index])
		return out
	var first: int = with_plugins[0]
	check("with nothing selected it racks the first track with plugins (%d)" % rack.track_index,
			rack.track_index == first)
	var want: Array = []
	for i in DAW.state.track(first).plugins():
		want.append([first, i])
	check("and exactly that track's chain, in order", racked.call() == want)

	var other: int = with_plugins[1]
	DAW.state.set_track_field(other, &"selected", true)
	rack._process(0.0)
	check("selecting a track in Reaper racks it (%d)" % rack.track_index, rack.track_index == other)
	check("and only its plugins", racked.call().all(func(u): return u[0] == other))
	check("the window over the rack says it is following Reaper", rack._picker.lit)

	rack._picker.choice = first
	rack._picker.chosen.emit(first)
	rack._process(0.0)
	check("scrolling the window racks another track", rack.track_index == first)
	check("and then it is no longer following", not rack._picker.lit)

	var banked: MeshBank = rack.find_child("Faceplates", true, false)
	if banked != null:
		check("the faceplates are drawn as one bank (%d plates)" % banked.multimesh.instance_count,
				banked.multimesh.instance_count == racked.call().size())
	var bodies: MeshBank = rack.find_child("ButtonBodies", true, false)
	check("so are the power buttons", bodies != null and bodies.multimesh.instance_count == racked.call().size())

	if bare >= 0:
		rack.show_track(bare)
		rack._process(0.0)
		check("a track with no plugins racks no units", racked.call().is_empty())
		var empty: Label3D = rack.find_child("Empty", true, false)
		check("and says so", empty != null and empty.text == "NO PLUGINS ON THIS TRACK")
		check("and keeps the window to scroll away from it", is_instance_valid(rack._picker))
	DAW.state.set_track_field(other, &"selected", false)
	rack.queue_free()
	remove_child(rack)


## Reaper refreshing its control surface is some fifty thousand messages at once. Applied in one
## frame they stopped the room for two seconds; they are applied a few milliseconds' worth a
## frame, gear waits for them to finish before rebuilding, and a patchbay asked a thousand times
## in a frame whether its sends changed looks once.
func _test_a_flood_from_reaper_is_taken_in_over_frames() -> void:
	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	add_child(reaper)
	for i in 60000:
		reaper._inbox.append({"address": "/track/1/fx/1/fxparam/%d/value" % (i % 32 + 1), "args": [0.25]})
	reaper._inbox.append({"address": "/track/1/fx/1/fxparam/7/value", "args": [0.75]})
	var t0 := Time.get_ticks_usec()
	reaper._apply_inbox()
	var took := (Time.get_ticks_usec() - t0) / 1000.0
	check("one frame takes in only its share (%.1fms, %d of 60001)" % [took, reaper._inbox_at],
			took < 20.0 and reaper._inbox_at > 0 and reaper._inbox_at < 60001)
	check("and says it is still catching up", reaper.catching_up())
	var frames := 1
	while reaper.catching_up() and frames < 2000:
		reaper._apply_inbox()
		frames += 1
	check("the rest arrives over the next frames (%d)" % frames, not reaper.catching_up() and frames > 1)
	close_to("in order: the last word is the one that stands",
			float(reaper.state.fx(1, 1).params.get(7, -1.0)), 0.75)

	# Gear holds its rebuild while the DAW is catching up -- but not for ever.
	DAW.use(reaper, false)
	var bay := PatchbaySurface.new()
	add_child(bay)
	bay._process(0.0)
	reaper._inbox.append({"address": "/track/1/volume", "args": [0.5]})
	bay.mark_dirty()
	bay._process(0.0)
	check("a rebuild waits while news is still arriving", bay._dirty)
	bay._dirty_since -= Surface.HOLD_FOR_NEWS_MSEC + 1
	bay._process(0.0)
	check("and stops waiting after a while", not bay._dirty)
	reaper._inbox.clear()
	reaper._inbox_at = 0
	bay.mark_dirty()
	bay._process(0.0)
	check("with nothing arriving it rebuilds at once", not bay._dirty)

	for i in 1000:
		DAW.track_changed.emit(i % 8, &"sends")
	check("a thousand sends in a frame are one look at the bay (%d)" % bay._later.size(),
			bay._later.size() == 1)
	bay._run_later()
	bay.queue_free()
	remove_child(bay)
	DAW.use(OfflineBackend.new())


## What made a busy project hitch: every plugin anywhere reporting anything rebuilt the rack. A
## parameter list arriving, or a plugin on another track, is not a reason; the racked chain
## gaining, losing or swapping a plugin is.
func _test_the_rack_rebuilds_only_for_its_own_chain() -> void:
	DAW.use(OfflineBackend.new())
	var rack := RackSurface.new()
	add_child(rack)
	rack._process(0.0)
	var mine := rack.track_index
	var elsewhere := -1
	for t in DAW.state.track_indices():
		if t != mine and not DAW.state.track(t).plugins().is_empty():
			elsewhere = t
			break
	var slot: int = DAW.state.track(mine).plugins()[0]

	rack._dirty = false
	for i in 50:
		DAW.fx_changed.emit(mine, slot)
	check("fifty reports in a frame are looked at once (%d checks)" % rack._later.size(),
			rack._later.size() == 1)
	rack._run_later()
	check("a plugin on the racked track reporting in does not rebuild it", not rack._dirty)
	if elsewhere >= 0:
		DAW.fx_changed.emit(elsewhere, DAW.state.track(elsewhere).plugins()[0])
		rack._run_later()
		check("nor does one on another track", not rack._dirty)
	var was := DAW.state.fx(mine, slot).name
	DAW.state.fx(mine, slot).name = was + " II"
	DAW.fx_changed.emit(mine, slot)
	rack._run_later()
	check("a different plugin in the racked chain does", rack._dirty)
	DAW.state.fx(mine, slot).name = was
	rack.queue_free()
	remove_child(rack)

	# And gear that draws no plugins does not rebuild for one at all. The console and patchbay
	# did, for every plugin's every report, and that was most of the hitch.
	for pair in [["console", ConsoleSurface], ["patchbay", PatchbaySurface]]:
		var gear: Surface = pair[1].new()
		add_child(gear)
		gear._process(0.0)
		gear._dirty = false
		DAW.fx_changed.emit(mine, slot)
		check("a plugin reporting in leaves the %s alone" % pair[0], not gear._dirty)
		gear.queue_free()
		remove_child(gear)


func _test_nothing_on_a_faceplate_overlaps_or_overhangs() -> void:
	# What this does NOT pin is where the knob row looks best. That was settled by a
	# photograph, as it has to be. What it pins is the BRACKET the row has to stay inside,
	# which is geometry and not taste: raise it and the knobs grow through the rule under the
	# title; drop it and the captions walk off the bottom of the plate. Both ends are real
	# failures and neither is visible from any other test in this suite.
	DAW.use(OfflineBackend.new())
	var rack := RackSurface.new()
	add_child(rack)
	rack._process(0.0)

	# Every plugin in the stand-in, a track's chain at a time, as the rack shows them.
	var units: Array = []
	for t in DAW.state.track_indices():
		if DAW.state.track(t).plugins().is_empty():
			continue
		rack.show_track(t)
		rack._process(0.0)
		units.append_array(rack.find_children("*", "Node3D", true, false).filter(
				func(n): return n is RackUnit and not n.is_queued_for_deletion()))
	check("the stand-in session racks some units", units.size() >= 4)

	var half := RackUnit.U * RackUnit.UNITS_TALL * 0.5
	# Written out rather than read off the label, because a label's own idea of its height is
	# the thing a font-size change moves and this is what it has to be checked against.
	var caption_half := 36 * 0.00018 * 0.5
	var title_half := 52 * 0.00019 * 0.5

	for node in units:
		var unit: RackUnit = node
		var named := "%s" % unit.name

		var rules := unit.find_children("*", "MeshInstance3D", false, false).filter(
				func(n): return (n as MeshInstance3D).mesh is BoxMesh \
						and ((n as MeshInstance3D).mesh as BoxMesh).size.y < 0.002)
		check("%s has a rule under its title" % named, rules.size() == 1)
		if rules.is_empty():
			continue
		var rule_y: float = (rules[0] as MeshInstance3D).position.y
		var rule_w: float = ((rules[0] as MeshInstance3D).mesh as BoxMesh).size.x
		check("%s keeps its rule on the metal" % named, rule_w < RackUnit.RACK_WIDTH)

		# The title sits above the rule, not through it.
		var title: Label3D = unit._name_label
		check("%s keeps its title clear of the rule" % named,
				title.position.y - title_half > rule_y)

		var knobs := unit.find_children("*", "Node3D", true, false).filter(
				func(n): return n is Knob and (n as Knob).visible)
		check("%s carries knobs" % named, not knobs.is_empty())
		for k in knobs:
			var knob: Knob = k
			check("%s keeps knob %s under the rule" % [named, knob.name],
					knob.position.y + Knob.RADIUS < rule_y)

		for i in knobs.size():
			var caption := unit.get_node_or_null("Caption%d" % i) as Label3D
			if caption == null or not caption.visible:
				continue
			var lowest: float = caption.position.y - caption_half
			check("%s keeps caption %d on the plate (%.1fmm from the edge)"
					% [named, i, (lowest + half) * 1000.0], lowest > -half)

	rack.queue_free()


func _test_the_tape_leaves_the_pack_where_the_pack_is() -> void:
	# The deck had two reels and nothing between them. Now it has a path, and the one thing
	# that makes the path worth drawing is that it is not a fixed picture: the tape comes off
	# the pack on a TANGENT, so the angle it leaves at swings round as the reel empties. A run
	# drawn to a fixed point on the flange would look identical in a still and dead in motion.
	var centre := Vector2(-TapeDeck.REEL_SPACING * 0.5, 0.0)
	var guide := Vector2(-TapeDeck.GUIDE_X, TapeDeck.PATH_Y)

	# A tangent is a tangent: on the circle, and square to the line that reaches it.
	for fraction in [0.0, 0.25, 0.6, 1.0]:
		var radius := TapeDeck.pack_radius(fraction)
		var touch := TapeDeck.tangent_point(centre, radius, guide, -1.0)
		check("a tangent at %.2f sits on the pack (%.2fmm out)"
				% [fraction, (touch.distance_to(centre) - radius) * 1000.0],
				absf(touch.distance_to(centre) - radius) < 1e-5)
		# Square, which is the whole definition and the thing a sign error breaks silently.
		var square: float = (touch - centre).normalized().dot((touch - guide).normalized())
		check("and leaves square to the pack at %.2f (dot %.4f)" % [fraction, square],
				absf(square) < 1e-4)

	# The two sides are the two tangents, and they are not the same point. A deck that used one
	# sign for both reels would run the takeup's tape off the back of the machine.
	var r := TapeDeck.pack_radius(0.5)
	check("the two tangents are different points",
			TapeDeck.tangent_point(centre, r, guide, -1.0).distance_to(
				TapeDeck.tangent_point(centre, r, guide, 1.0)) > 0.005)

	# What is DRAWN stops at the flange rim, because the pack lives behind the flange and a run
	# drawn to it ends in the middle of a solid disc.
	var angles: Array[float] = []
	for fraction in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
		var radius := TapeDeck.pack_radius(fraction)
		var touch := TapeDeck.tangent_point(centre, radius, guide, -1.0)
		var rim := TapeDeck.rim_crossing(centre, guide, touch, TapeDeck.REEL_RADIUS)
		check("the run at %.1f stops on the rim (%.2fmm out)"
				% [fraction, (rim.distance_to(centre) - TapeDeck.REEL_RADIUS) * 1000.0],
				absf(rim.distance_to(centre) - TapeDeck.REEL_RADIUS) < 1e-5)
		# Between the guide and the pack, not behind the guide and not past the pack.
		check("and lies between the guide and the pack at %.1f" % fraction,
				rim.distance_to(guide) > 0.0 and rim.distance_to(guide) < touch.distance_to(guide))
		angles.append((rim - guide).angle())

	# The payoff: six pack sizes, six different exit angles, moving one way. If this came back
	# flat the path would be a decal.
	#
	# Stepped with angle_difference rather than subtracted. The run crosses due-west partway
	# through the reel, so the raw angles run 163, 173, 180, -174 -- which a plain subtraction
	# reads as the tape snapping back through half a turn. That is the test being wrong about
	# the circle, not the deck; the first version of this failed on it.
	var swing := 0.0
	var monotone := true
	var first := angle_difference(angles[0], angles[1])
	for i in range(1, angles.size()):
		var step := angle_difference(angles[i - 1], angles[i])
		swing += absf(step)
		if step * first <= 0.0:
			monotone = false
	check("the exit angle swings as the reel empties (%.1f deg)" % rad_to_deg(swing),
			swing > deg_to_rad(6.0))
	check("and swings one way, not back and forth", monotone)

	# All of the above is the static geometry, and a mutation proved it does not cover the
	# thing most likely to be got wrong: WHICH tangent each reel uses. Flipping the takeup's
	# sign left every check above green, because the takeup is never touched by them. The two
	# reels are mirror images, so with equal packs the tape must leave one and arrive at the
	# other at mirrored points -- which is exactly what the sign decides.
	DAW.use(OfflineBackend.new())
	var deck := TapeDeck.new()
	add_child(deck)
	deck._process(0.0)
	DAW.state.position_seconds = DAW.state.project_length * 0.5
	deck._update_packs()
	check("the deck laid three runs", deck._tape_runs.size() == 3)
	if deck._tape_runs.size() == 3:
		# Run 0 was laid rim-first, run 2 rim-last, so the reel end of each is the far one.
		var off_supply: Vector3 = deck._tape_runs[0].transform.origin \
				- deck._tape_runs[0].transform.basis.x * 0.5
		var onto_takeup: Vector3 = deck._tape_runs[2].transform.origin \
				+ deck._tape_runs[2].transform.basis.x * 0.5
		check("at half a song the two packs are the same size",
				absf(TapeDeck.song_fraction(DAW.state) - 0.5) < 0.01)
		check("so the tape leaves and lands at mirrored heights (%.1fmm apart)"
				% (absf(off_supply.y - onto_takeup.y) * 1000.0),
				absf(off_supply.y - onto_takeup.y) < 0.0005)
		check("and at mirrored distances from the middle (%.1fmm apart)"
				% (absf(off_supply.x + onto_takeup.x) * 1000.0),
				absf(off_supply.x + onto_takeup.x) < 0.0005)
		check("both on the gap side of their own reel",
				off_supply.x > -TapeDeck.REEL_SPACING * 0.5 \
				and onto_takeup.x < TapeDeck.REEL_SPACING * 0.5)
	deck.queue_free()


func _test_every_grab_tab_is_clipped_to_its_own_gear() -> void:
	# A grab tab is placed from the surface's content box, ONCE, when the surface says it has
	# rebuilt. So anything that is the wrong size at that instant parks the tab somewhere it
	# does not belong -- and nothing complains, because the tab is correct relative to a box
	# that no longer exists.
	#
	# That is not hypothetical. The tape path's runs are unit-length boxes that a transform
	# shrinks to size, and the two outer runs were left unlaid until the first frame. `rebuilt`
	# fires before that frame, so the handle measured a deck with two one-metre planks across
	# it and ended up floating a foot to its right, attached to nothing. Found in a wide shot
	# of the room; invisible in every close-up, because it is outside every close-up.
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)

	# Stepped a frame first, and this is the whole point of the test rather than setup. The
	# handle is placed during the rebuild; anything a surface settles AFTER that -- the tape
	# runs are laid in the same frame, just later -- is a box the handle never saw. Measuring
	# without stepping compares the handle against the same wrong box it was placed from, and
	# the first version of this test passed the bug for exactly that reason.
	for node in studio.find_children("*", "Node3D", true, false):
		if node is Surface:
			(node as Surface)._process(0.0)

	var handles := studio.find_children("*", "Node3D", true, false).filter(
			func(n): return n is SurfaceHandle)
	check("the studio hangs a tab on every surface", handles.size() >= 5)

	for node in handles:
		var handle: SurfaceHandle = node
		var surface := handle.surface
		check("a tab knows what it is clipped to", surface != null)
		if surface == null:
			continue
		var bounds := surface.content_aabb()
		if bounds.size.x <= 0.0:
			continue
		var edge := bounds.end.x
		var over := handle.position.x - edge
		# Outside the gear, because a tab buried in a fader bank cannot be aimed at. Loose at
		# the bottom end by a few millimetres: a surface whose content moves after it is built
		# -- a playhead, a tape run -- grows its own box slightly under a tab already placed.
		check("%s's tab is not buried in it (%.1fmm past the edge)" % [surface.name, over * 1000.0],
				over > -0.006)
		# And ON it. The bug this exists for put the tape deck's tab 388mm past the edge of a
		# 474mm machine, which no margin explains.
		check("%s's tab is clipped to the edge, not floating beside it (%.1fmm out)"
				% [surface.name, over * 1000.0], over < 0.060)
		# At mid height, which is the framing constraint SurfaceHandle.reposition documents.
		check("%s's tab sits at the middle of it" % surface.name,
				absf(handle.position.y - bounds.get_center().y) < 0.020)

	studio.queue_free()


func _test_an_unfilled_rack_bay_is_blanked_off() -> void:
	DAW.use(OfflineBackend.new())
	var rack := RackSurface.new()
	add_child(rack)
	rack._process(0.0)

	var units := rack.find_children("*", "RackUnit", true, false)
	check("the stand-in racks some plugins", units.size() > 0)

	var plates := rack.find_children("BlankPlates", "MeshBank", true, false)
	check("a part-filled bay is blanked off", plates.size() > 0)

	var unit_height := RackUnit.U * RackUnit.UNITS_TALL
	var per_bay := int(floor(RackSurface.BAY_HEIGHT / unit_height))
	var screws := rack.find_children("BlankScrews", "MeshBank", true, false)
	check("the blanks are screwed in", screws.size() == plates.size())

	var blanked := 0
	for bank in plates:
		blanked += (bank as MeshBank).count()
	# Rows, not counts. The whole bug was a row with nothing in it, so the assertion has to be
	# that every row of every bay is accounted for -- a blank bank with the right NUMBER of
	# plates sitting in the wrong bay would satisfy a count and leave the hole exactly where
	# it was.
	var bays := int(ceil(float(units.size()) / float(per_bay)))
	check("the stand-in fills one bay and does not fill it", bays == 1 and units.size() < per_bay)
	check("every row of the bay is either a unit or a blank",
			units.size() + blanked == per_bay * bays)
	check("four screws to a blank", (screws[0] as MeshBank).count() == blanked * 4)

	# Banked, not loose. Six blanks and twenty-four screws as individual meshes would be thirty
	# objects to say nothing at all, in the surface that already has the most of anything.
	check("the blanks are one object, not one each", (plates[0] as MeshBank).count() > 1)

	# WHERE, not just how many. The arithmetic above is satisfied by blanks laid over the top of
	# the units -- the same count, the same rows, the gear hidden behind panels and the hole
	# still at the bottom. Found by mutation: reversing the row range left every check green.
	# Units fill top-down, so every blank must sit below the lowest unit.
	var lowest_unit := INF
	for unit in units:
		lowest_unit = minf(lowest_unit, (unit as Node3D).position.y)
	var highest_blank := -INF
	for bank in plates:
		var mesh_bank := bank as MeshBank
		for i in mesh_bank.count():
			highest_blank = maxf(highest_blank, mesh_bank.transform_of(i).origin.y)
	check("the blanks are below the gear, not over it", highest_blank < lowest_unit)

	rack.queue_free()


func _test_a_surface_cannot_ask_what_it_is_looking_through() -> void:
	# Each: a thing a surface must not reach for, and what goes wrong when one does.
	var forbidden := {
		"Presentation.": "branch on its presentation mode",
		"Medium.": "branch on screen, AR or VR",
		"XRServer": "ask whether a headset is on",
		"Session.": "ask who else is in the room",
		"is_authority": "ask whether this process is the host",
		"multiplayer.": "talk to the network directly",
	}
	var files := _gd_files_under("res://hardware")
	check("there are surfaces to check", files.size() > 15)

	var offences: Array[String] = []
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for line in text.split("\n"):
			var code := line.strip_edges()
			# Doc comments may NAME these -- timeline_surface.gd cites Presentation.default_mode
			# to explain why it is a screen surface, which is the comment doing its job.
			if code.begins_with("#"):
				continue
			for needle in forbidden:
				if code.contains(needle):
					offences.append("%s would %s: %s" % [
							path.get_file(), forbidden[needle], code])
	if not offences.is_empty():
		for offence in offences:
			print("    " + offence)
	check("no surface asks what it is being looked at through", offences.is_empty())

	# The check has to be able to fail, or it is decoration. Point it at the layer that is
	# SUPPOSED to know these things and it must light up -- if it does not, the scan is broken
	# and the green above means nothing.
	var aware := _gd_files_under("res://core/presentation")
	var found := false
	for path in aware:
		var text := FileAccess.get_file_as_string(path)
		for line in text.split("\n"):
			var code := line.strip_edges()
			if not code.begins_with("#") and code.contains("Presentation."):
				found = true
	check("the scan does light up on the layer that is allowed to know", found)


## Every .gd under a directory, recursively. Plain DirAccess rather than a preloaded list: a
## list is something a new file can be left out of, and a file left out is a file exempt from
## every rule above without anyone deciding that.
func _gd_files_under(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := root.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_gd_files_under(path))
		elif entry.ends_with(".gd"):
			out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _test_a_rack_unit_reaches_every_parameter() -> void:
	# THE GAP THIS EXISTS FOR. A faceplate fits eight knobs, and this showed a plugin's first
	# eight with nothing saying there were more -- a unit that looked complete for a simpler
	# plugin than the one loaded. Exactly the failure the console's BankSelector was written to
	# prevent, in a second place, missed because every FX in the stand-in had four parameters
	# and so the case never arose.
	DAW.use(OfflineBackend.new())

	var unit := RackUnit.create(2, 0)
	add_child(unit)
	var fx := DAW.state.fx(2, 0)
	check("the stand-in has a plugin that overflows a faceplate",
			fx.params.size() > RackUnit.MAX_KNOBS)

	var total := fx.params.size()
	check("a page control appears when the plugin does not fit", unit._page_label.visible)
	check("it says which parameters these knobs are",
			unit._page_label.text == "1-8 OF %d" % total)
	check("there is nothing before the first page", not unit._page_prev.lit)
	check("and there is something after it", unit._page_next.lit)

	# The knob must mean the parameter it is CURRENTLY pointed at, not the one it was built
	# with. A captured index would keep writing the first page forever, silently.
	check("a knob on the first page means the first parameter", unit._param_for(0) == 0)
	unit._step_page(1)
	check("paging moves the window", unit.page_offset == RackUnit.MAX_KNOBS)
	check("and the knobs are re-pointed", unit._param_for(0) == RackUnit.MAX_KNOBS)
	check("the readout follows", unit._page_label.text == "9-16 OF %d" % total)
	check("and now there is something both ways", unit._page_prev.lit and unit._page_next.lit)

	# Turning a knob writes the page it is showing.
	var before: float = fx.params[RackUnit.MAX_KNOBS]
	unit._knobs[0].turned.emit(clampf(before + 0.25, 0.0, 1.0))
	check("turning a knob writes the parameter it currently means",
			not is_equal_approx(DAW.state.fx(2, 0).params[RackUnit.MAX_KNOBS], before))
	check("and leaves the parameter it used to mean alone",
			is_equal_approx(DAW.state.fx(2, 0).params[0], fx.params[0]))

	# The last page is short, and the spare knobs go away rather than showing stale values.
	while unit._page_next.lit:
		unit._step_page(1)
	var left := total - unit.page_offset
	check("the last page shows only what is left",
			unit._page_label.text == "%d-%d OF %d" % [unit.page_offset + 1, total, total])
	var shown := 0
	for k in unit._knobs:
		if k.visible:
			shown += 1
	check("and hides the knobs with nothing behind them", shown == left)
	check("there is nothing after the last page", not unit._page_next.lit)
	var at_end := unit.page_offset
	unit._step_page(1)
	check("paging past the end does nothing", unit.page_offset == at_end)

	# --- a page may not change under a hand -------------------------------------------------
	#
	# The console's rule in a smaller place: applying immediately would send the NEW parameter
	# the OLD hand position -- a value nobody asked for, written somewhere nobody was looking.
	unit.page_offset = 0
	unit.refresh()
	var hand := FakeHand.new()
	hand.set_physics_process(false)
	add_child(hand)
	var knob := unit._knobs[0]
	knob.grab_begin(hand, knob.global_position)
	check("a held knob is reported as held", unit._anything_held())
	unit._step_page(1)
	check("a page asked for under a hand does not land yet", unit.page_offset == 0)
	unit._process(0.0)
	check("and still does not while the hand is there", unit.page_offset == 0)
	knob.grab_end(hand)
	unit._process(0.0)
	check("it lands as soon as the hand lets go", unit.page_offset == RackUnit.MAX_KNOBS)

	# A plugin that fits carries no page control, for the same reason the console's bank module
	# is not built for a session that fits: two dead buttons invite the question of what for.
	var small := DAW.state.fx(2, 0)
	small.params.clear()
	small.param_names.clear()
	for i in 3:
		small.params[i] = 0.5
	var tidy := RackUnit.create(2, 0)
	add_child(tidy)
	check("a plugin that fits shows no page control", not tidy._page_label.visible)

	hand.queue_free()
	unit.queue_free()
	tidy.queue_free()


func _test_lettering_stops_when_nobody_can_read_it() -> void:
	# THE MEASUREMENT THIS EXISTS FOR. An ablation -- hide every Label3D, re-read the counters --
	# put the 517 labels in a 90-track session at 735 of 2,492 draw calls and 0.70ms of a 1.82ms
	# frame. Text was the studio's single largest drawing cost, and it is the one thing a
	# MultiMesh cannot help with: every label carries its own glyph texture, so every label is
	# its own material and the renderer has nothing to batch it with.

	var l := Label3D.new()
	l.font_size = 56
	l.pixel_size = 0.00018
	close_to("cap height is pixel_size x font_size", Lettering.cap_height(l), 0.01008, 0.000001)

	var far := Lettering.legible_to(l)
	var small := Label3D.new()
	small.font_size = 28
	small.pixel_size = 0.00018
	check("smaller lettering stops being readable sooner", Lettering.legible_to(small) < far)
	close_to("and exactly in proportion to its height", Lettering.legible_to(small) * 2.0, far,
			0.0001)

	Lettering.range_to_legibility(l)
	# The label must be at FULL opacity for the whole distance it can be read at. A fade that
	# started inside the readable range would be dimming text someone is reading.
	close_to("the fade starts only once the text is unreadable",
			l.visibility_range_end - l.visibility_range_end_margin, far, 0.0001)
	check("and it has somewhere to fade over", l.visibility_range_end_margin > 0.0)
	check("it fades rather than popping",
			l.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF)
	# Nothing is culled for being too CLOSE. A label you have walked up to is the one case where
	# it certainly matters.
	close_to("nothing is hidden for being near", l.visibility_range_begin, 0.0)
	l.free()
	small.free()

	# --- every label, not just the helper ----------------------------------------------------
	#
	# The helper being correct is worth little if a site forgets to call it, and a new label is
	# exactly the kind of thing added without thinking about draw calls. So this walks what the
	# surfaces actually built and insists on the property for all of it.
	# A project of its own, because an earlier test may have left the DAW pointing at an empty
	# one and a studio with no tracks builds no lettering to check.
	DAW.use(OfflineBackend.new())
	var studio := Node3D.new()
	add_child(studio)
	for surface in [ConsoleSurface.new(), PatchbaySurface.new(), TimelineSurface.new(),
			RackSurface.new(), TapeDeck.new()]:
		studio.add_child(surface)
		# Surfaces batch their rebuild to a frame boundary, and this test does not run one.
		# Driving _process by hand is what the engine would have done a frame later.
		(surface as Surface)._process(0.0)
	var labels := studio.find_children("*", "Label3D", true, false)
	check("the studio has lettering to check at all", labels.size() > 20)
	var unranged: Array[String] = []
	for node in labels:
		var label := node as Label3D
		if label.visibility_range_end <= 0.0:
			unranged.append(label.get_parent().name if label.get_parent() else label.name)
	check("every label in the studio stops when it cannot be read: %s" % str(unranged.slice(0, 4)),
			unranged.is_empty())
	studio.queue_free()


func _test_many_little_boxes_are_one_object() -> void:
	# A console is mostly repetition, and the obvious way to draw repetition is one object each.
	# At 90 tracks that was 540 button bodies and lamps -- a quarter of everything the studio
	# drew. These pin the bank that replaced them.
	#
	# Everything reads MeshBank's own retained copy, never the MultiMesh: its buffer lives in
	# the rendering server, and headless that server accepts every write and returns black.

	var bank := MeshBank.parts(Vector3(0.01, 0.01, 0.01), Materials.chassis())
	add_child(bank)
	check("an empty bank holds nothing", bank.count() == 0)

	var a := bank.claim(Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)), Color.RED)
	var b := bank.claim(Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)), Color.GREEN)
	check("claims come back as distinct slots", a == 0 and b == 1)
	check("the bank counts what it was given", bank.count() == 2)
	check("a slot remembers its colour", bank.colour_of(a) == Color.RED)
	close_to("a slot remembers where it is", bank.transform_of(b).origin.x, 2.0)

	# Writable before the buffer exists, because a button sets its lamp in _ready and the
	# surface does not commit until every strip is built.
	bank.set_colour(a, Color.BLUE)
	check("a slot can be recoloured before commit", bank.colour_of(a) == Color.BLUE)

	bank.commit()
	check("committing sizes the buffer", bank.multimesh.instance_count == 2)
	check("committing keeps the count", bank.count() == 2)
	bank.set_colour(b, Color.WHITE)
	check("a slot can be recoloured after commit", bank.colour_of(b) == Color.WHITE)
	# Commit is idempotent: a surface should be able to call it without tracking whether it has.
	bank.commit()
	check("committing twice changes nothing", bank.count() == 2 and bank.colour_of(a) == Color.BLUE)

	# Out-of-range writes are ignored rather than crashing. A button whose claim was refused
	# holds -1, and a desk should not die because one lamp has nowhere to go.
	bank.set_colour(-1, Color.RED)
	bank.set_colour(99, Color.RED)
	check("a slot that does not exist is ignored", bank.colour_of(a) == Color.BLUE)
	bank.queue_free()

	var lamps := MeshBank.lamps(Vector3(0.01, 0.01, 0.001))
	# A lamp is drawn above 1.0 so it blooms, and a bloomed object that also casts a shadow
	# reads as a solid lump with a bright face. Lamps light; they do not occlude.
	check("a lamp bank casts no shadow",
			lamps.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	check("a lamp bank is unshaded", lamps.material_override is ShaderMaterial)
	var part_mat := MeshBank.parts(Vector3.ONE, Materials.chassis()).material_override
	check("a part bank keeps a real lit material", part_mat is StandardMaterial3D)
	# Without this flag a StandardMaterial3D ignores per-instance colour entirely, which is how
	# the first version of parts() silently drew every plate in one shade.
	check("a part bank actually honours per-instance colour",
			(part_mat as StandardMaterial3D).vertex_color_use_as_albedo)
	# Duplicated, not the cached singleton: flipping the flag on Materials.chassis() itself
	# would change every unbanked thing in the studio that happens to be made of chassis.
	check("a part bank does not mutate the shared material",
			not Materials.chassis().vertex_color_use_as_albedo)
	lamps.free()

	# --- one definition of what a lit lamp looks like ---------------------------------------
	#
	# Two routes draw indicators now -- a material for a lone button, a per-instance colour for
	# a banked one -- and an LED that looks different depending on which drew it is worse than
	# either. Materials.lamp_colour is the single definition; VUMeter uses it too.
	var tint := Color(0.95, 0.25, 0.22)
	var on := Materials.lamp_colour(tint, true)
	var off := Materials.lamp_colour(tint, false)
	check("a lit lamp is brighter than an unlit one", on.r > off.r)
	check("a lit lamp is driven past 1.0 so it blooms", on.r > 1.0)
	check("an unlit lamp keeps its tint rather than going black", off.r > 0.02)
	# Hue is preserved both ways, which is what makes an unlit red mute readable as the mute
	# rather than as a grey smudge on a desk of ninety strips.
	check("an unlit lamp keeps its hue", off.r > off.g and off.r > off.b)
	check("the meter and the buttons agree on what lit means",
			VUMeter.segment_colour(0, 14, -1) == Materials.lamp_colour(VUMeter.colour_at(0), true))

	# --- a chip is an identifier, not an indicator -------------------------------------------
	#
	# Both are unshaded patches of per-instance colour, so it is tempting to drive them the same
	# way. They must not be: a lamp only says on or off and can clip freely, while a colour chip
	# says WHICH TRACK and clipping is exactly what destroys that. Reaper's palette is pastel,
	# so at the lamp's gain every chip came back the same pale wash.
	var pastel := Color(0.86, 0.62, 0.44)
	var chip := Materials.chip_colour(pastel)
	check("a chip is lit rather than painted", chip.r > pastel.r)
	check("a chip does not clip its brightest channel", chip.r <= 1.0)
	check("a chip is gentler than a lamp", chip.r < Materials.lamp_colour(pastel, true).r)
	# The real property: two different pastels stay different. A gain that clips makes them one.
	var other := Color(0.62, 0.86, 0.80)
	check("two chips of different hue stay distinguishable",
			Materials.chip_colour(other) != chip)
	# Hue survives exactly, because every channel is scaled by the same factor. A flat multiply
	# that clipped one channel would rotate the hue and quietly mis-report the track's colour.
	close_to("a chip keeps its hue", Materials.chip_colour(pastel).g / Materials.chip_colour(pastel).r,
			pastel.g / pastel.r, 0.001)
	# A colour with nothing left to give is left alone rather than clipped.
	var full := Color(1.0, 0.4, 0.1)
	check("a chip at full brightness is not pushed past it", Materials.chip_colour(full).r <= 1.0)
	close_to("and keeps its hue too", Materials.chip_colour(full).g, 0.4, 0.001)


	# --- a bank of an authored part ----------------------------------------------------------
	#
	# A MultiMeshInstance3D has no per-surface override, so an authored part's two finishes have
	# to be baked into a duplicate of the mesh. The duplicate is the part worth pinning: Part
	# caches one Mesh per asset and hands it to everyone, so painting the shared copy would
	# repaint every loose jack in the studio.
	var source := Part.mesh(PatchPoint.MESH_PATH)
	if source != null:
		var authored_0 := source.surface_get_material(0)
		var jacks := MeshBank.of(PatchPoint.MESH_PATH, Materials.brushed_metal(),
				{"bore": Materials.recess()})
		check("a bank of an authored part resolves", jacks != null)
		check("it keeps every surface the part had",
				jacks.multimesh.mesh.get_surface_count() == source.get_surface_count())
		check("it paints the surfaces rather than overriding them all at once",
				jacks.material_override == null)
		check("the shared mesh is left alone", source.surface_get_material(0) == authored_0)
		check("the baked mesh is not the shared one", jacks.multimesh.mesh != source)
		# One rule for both paths, or a banked jack and a loose one are two kinds of jack.
		check("a bank paints a surface the same way Part.build would",
				jacks.multimesh.mesh.surface_get_material(1)
				== Part.paint_for(source, 1, Materials.brushed_metal(),
						{"bore": Materials.recess()}))
		jacks.free()
	check("a bank of a missing part is null rather than empty",
			MeshBank.of("res://assets/hardware/does_not_exist.glb", Materials.chassis()) == null)

	# A fader cap slides and a knob turns, so a slot has to be movable after it is claimed --
	# without ever changing the instance count, which is fixed at commit.
	var movers := MeshBank.parts(Vector3.ONE, Materials.chassis())
	var slot_a := movers.claim(Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)), Color.WHITE)
	movers.commit()
	movers.move_slot(slot_a, Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)))
	close_to("a slot can be moved after commit", movers.transform_of(slot_a).origin.x, 5.0)
	movers.move_slot(99, Transform3D(Basis.IDENTITY, Vector3(9, 0, 0)))
	check("moving a slot that does not exist is ignored", movers.count() == 1)
	movers.free()

	# --- the rest of a strip banks the same way ----------------------------------------------
	#
	# Plate, colour chip and fader slot are each one identical box per strip, which is 270 more
	# objects at 90 tracks. Same two-branch contract as the button: a bank if one was given, own
	# meshes if not, so a strip still works outside a console surface.
	var plates := MeshBank.parts(ChannelStrip.PLATE_SIZE, Materials.chassis())
	var chips := MeshBank.lamps(ChannelStrip.CHIP_SIZE)
	var slots := MeshBank.parts(Fader.SLOT_SIZE, Materials.recess())
	add_child(plates)
	add_child(chips)
	add_child(slots)

	var banked_strip := ChannelStrip.create(0)
	banked_strip.plate_bank = plates
	banked_strip.chip_bank = chips
	banked_strip.slot_bank = slots
	add_child(banked_strip)
	check("a banked strip puts its plate in the bank", plates.count() == 1)
	check("a banked strip puts its chip in the bank", chips.count() == 1)
	check("a banked strip passes the slot bank down to its fader", slots.count() == 1)
	check("a banked strip builds no loose colour chip",
			banked_strip.get_node_or_null("ColourChip") == null)
	# The chip is the one banked box whose colour changes after the fact, so it has to have kept
	# its slot. A -1 here would mean every track's colour silently went to the same place.
	check("a banked chip carries the track's colour, not a lamp's clipped version",
			chips.colour_of(0) == Materials.chip_colour(DAW.state.track(0).colour))

	var alone := ChannelStrip.create(0)
	add_child(alone)
	check("a strip with no banks still builds its own chip",
			alone.get_node_or_null("ColourChip") != null)
	banked_strip.queue_free()
	alone.queue_free()
	plates.queue_free()
	chips.queue_free()
	slots.queue_free()

	# --- a button draws through a bank when it has one, and alone when it does not ------------
	var lone := PanelButton.new()
	add_child(lone)
	check("a button with no bank builds its own meshes",
			lone.find_children("*", "MeshInstance3D", true, false).size() == 2)
	lone.queue_free()

	var bodies := MeshBank.parts(PanelButton.BODY_SIZE, PanelButton.body_material())
	var lit_bank := MeshBank.lamps(PanelButton.LAMP_SIZE)
	add_child(bodies)
	add_child(lit_bank)
	var banked := PanelButton.new()
	banked.led_colour = Color(0.35, 0.72, 0.98)
	banked.body_bank = bodies
	banked.lamp_bank = lit_bank
	add_child(banked)
	check("a banked button builds no meshes of its own",
			banked.find_children("*", "MeshInstance3D", true, false).is_empty())
	check("a banked button still has a collider",
			banked.find_children("*", "CollisionShape3D", true, false).size() == 1)
	check("a banked button claimed a body and a lamp",
			bodies.count() == 1 and lit_bank.count() == 1)
	check("a banked button starts unlit",
			lit_bank.colour_of(0) == Materials.lamp_colour(banked.led_colour, false))
	banked.lit = true
	check("lighting a banked button reaches the bank",
			lit_bank.colour_of(0) == Materials.lamp_colour(banked.led_colour, true))
	banked.lit = false
	check("unlighting it reaches the bank too",
			lit_bank.colour_of(0) == Materials.lamp_colour(banked.led_colour, false))

	# The lamp sits proud of the body, or it is buried inside it and never seen.
	close_to("the lamp sits on the face of the button",
			lit_bank.transform_of(0).origin.z - bodies.transform_of(0).origin.z,
			PanelButton.LAMP_OFFSET.z)
	# And the bank's shared box is the shape the button thinks its lamp is -- a bank sized from
	# different numbers than the thing it stands for is a bug that only shows in a photograph.
	check("the bank draws the button's own lamp shape",
			(lit_bank.multimesh.mesh as BoxMesh).size == PanelButton.LAMP_SIZE)
	check("the bank draws the button's own body shape",
			(bodies.multimesh.mesh as BoxMesh).size == PanelButton.BODY_SIZE)

	banked.queue_free()
	bodies.queue_free()
	lit_bank.queue_free()


func _test_a_loom_lies_on_the_floor_and_misses_the_furniture() -> void:
	# The looms are the one piece of this room whose shape is entirely a routing problem, and
	# routing problems fail silently: a cable that goes through the floor renders exactly like
	# one that does not, from above. Three things are pinned here and each of them was broken
	# at some point this tick.

	# ONE. The spline's contract, on its own: it passes through the waypoints it was given and
	# it starts and ends on them rather than a span short. The overshoot BETWEEN them is pinned
	# further down, on the real geometry, because that is where it was measured and where the
	# number means something.
	var route := PackedVector3Array([
		Vector3(0, 1.20, 0), Vector3(0, 1.12, -0.08),
		Vector3(-0.35, 0.0, -0.30), Vector3(-1.20, 0.0, -0.30),
		Vector3(-1.55, 0.18, -0.20), Vector3(-1.60, 0.26, -0.18)])
	var smoothed := CableSweep.smooth(route, 10)
	check("the route starts where it was told", smoothed[0].is_equal_approx(route[0]))
	check("the route ends where it was told",
			smoothed[smoothed.size() - 1].is_equal_approx(route[route.size() - 1]))
	for waypoint in route:
		var nearest := INF
		for p in smoothed:
			nearest = minf(nearest, p.distance_to(waypoint))
		check("the route passes through its waypoints (%.1fmm off)" % (nearest * 1000.0),
				nearest < 0.002)

	# TWO. Resting on a surface. Above the blend the curve is untouched, below it the curve is
	# lifted, and it arrives at the level rather than through it.
	var dipping := PackedVector3Array([
		Vector3(0, 0.50, 0), Vector3(1, -0.20, 0), Vector3(2, 0.50, 0)])
	var rested := CableSweep.rest_on(dipping.duplicate(), 0.10, 0.03)
	check("a point well clear of the floor is left alone", is_equal_approx(rested[0].y, 0.50))
	check("a point well under the floor is laid on it", is_equal_approx(rested[1].y, 0.10))
	# C1 at the contact: a clamp would put a corner here, and the whole point of the blend is
	# that it does not. Sampled either side of the level, the lift has to be continuous.
	var just_above := CableSweep.rest_on(
			PackedVector3Array([Vector3(0, 0.1001, 0)]), 0.10, 0.03)[0].y
	var just_below := CableSweep.rest_on(
			PackedVector3Array([Vector3(0, 0.0999, 0)]), 0.10, 0.03)[0].y
	check("the touchdown has no step in it (%.4fmm)" % (absf(just_above - just_below) * 1000.0),
			absf(just_above - just_below) < 0.0005)
	check("the touchdown is a curve, not a corner", just_above > 0.1005)

	# THREE. The real looms in the real room.
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	# The looms are measured off the bay, and the bay is as wide as the session has tracks, so
	# they are not built until it has rebuilt once. Same step as the grab-tab test, same reason.
	for node in studio.find_children("*", "Node3D", true, false):
		if node is Surface:
			(node as Surface)._process(0.0)

	var looms := studio.studio_set.get_children().filter(func(n): return n is GearLoom)
	check("every machine in the set is wired to the bay", looms.size() == Studio.LOOM_RUNS.size())

	# The bay's own cabinet, which the looms climb up behind: measured off the built mesh, in
	# the set's space, so moving the stand moves the test with it.
	var cabinet := studio._patch_cabinet
	var bar := (studio.studio_set.global_transform.affine_inverse() * cabinet.global_transform) \
			* cabinet.get_aabb()
	bar = bar.grow(-0.002)

	for node in looms:
		var loom: GearLoom = node
		var sank := 0.0
		var rose := 0.0
		var through := 0
		for core in GearLoom.CORES:
			var sp := loom.spine(core)
			check("%s core %d is a curve, not a line" % [loom.name, core], sp.size() > 20)
			for p in sp:
				sank = minf(sank, p.y - loom.floor_y)
				# Only on the way in: a loom into a low gland comes DOWN from higher gear.
				if Vector2(p.x - loom.to_point.x, p.z - loom.to_point.z).length() < 0.2:
					rose = maxf(rose, p.y - loom.to_point.y)
				if bar.has_point(studio.studio_set.to_local(loom.to_global(p))):
					through += 1
		# How far the arrival overshoots the gland it is arriving at. This is the number the
		# centripetal knots bought: with uniform ones the same loom climbed 108mm above its own
		# entry point and came back down through the face of the bay. 50mm leaves room for the
		# exit run, which legitimately rises a little on a bay tilted back 18 degrees.
		check("%s arrives at the bay instead of over it (%.1fmm above)"
				% [loom.name, rose * 1000.0], rose < 0.050)
		check("%s does not go through the floor (%.1fmm under)" % [loom.name, -sank * 1000.0],
				sank > -0.001)
		check("%s misses the patch stand's cabinet (%d samples inside it)" % [loom.name, through],
				through == 0)
		if loom.on_floor:
			# And it does reach the floor. A loom that merely avoided going through it could be
			# hanging in the air, which is the other way to get this wrong.
			var touched := false
			for core in GearLoom.CORES:
				for p in loom.spine(core):
					if p.y - loom.floor_y < GearLoom.CORE_RADIUS * 2.0:
						touched = true
			check("%s actually lies on the floor" % loom.name, touched)

	studio.queue_free()


func _test_every_light_in_the_room_comes_out_of_something() -> void:
	# The room was lit by two OmniLights floating in mid-air with nothing around them. That is
	# the same defect as the patchbay wired to nothing, one layer up: the light is real, the
	# source of it does not exist, and nothing anywhere says so. The pairing is now a table read
	# twice -- once to make the lights, once to make the stands -- and what this pins is that
	# both readings agree. Adding a practical and forgetting its stand is the regression.
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)

	# Two populations, and the distinction is the whole reason this check reads the way it does.
	# A light in the ROOM is at a place, so it needs a fixture at that place or it is a bug. A
	# light on the BODY is at a person, travels with them, and has no place to put a fixture --
	# nor any business having one, since a lamp hanging in front of your own eyes is not a thing
	# that exists. Lumping them together is what this test did first, and it reported the work
	# light as a missing lamp stand.
	var every_light := studio.find_children("*", "OmniLight3D", true, false)
	var carried := every_light.filter(func(n): return studio.body.is_ancestor_of(n))
	var lamps := every_light.filter(func(n): return not studio.body.is_ancestor_of(n))
	var stands := studio.studio_set.get_children().filter(
			func(n): return n.is_in_group(&"lamp_stand"))
	check("every practical in the table is a light (%d of %d)"
			% [lamps.size(), Studio.PRACTICALS.size()], lamps.size() == Studio.PRACTICALS.size())
	# A carried light is exempt from needing a fixture, so it has to pay for that exemption some
	# other way: it must cost nothing extra to move. A shadow-casting light bolted to the head
	# re-renders every shadow in the room on every frame the person turns, which is the one thing
	# a body-relative light must never do.
	check("the body carries a work light", carried.size() >= 1)
	for light in carried:
		check("%s casts no shadows" % light.name, not (light as OmniLight3D).shadow_enabled)
	check("every practical in the table has a stand (%d of %d)"
			% [stands.size(), Studio.PRACTICALS.size()], stands.size() == Studio.PRACTICALS.size())

	var half_width := Studio.ROOM_WIDTH * 0.5
	var half_depth := Studio.ROOM_DEPTH * 0.5
	for i in mini(stands.size(), Studio.PRACTICALS.size()):
		var at: Vector3 = Studio.PRACTICALS[i][0]
		var stand: Node3D = stands[i]

		# Standing on the floor, under the light, rather than beside it. A stand offset from its
		# own lamp lights nothing and the lamp still floats -- it just floats next to a pole.
		check("lamp %d stands under its own light (%.1fmm off)"
				% [i, Vector2(stand.position.x - at.x, stand.position.z - at.z).length() * 1000.0],
				Vector2(stand.position.x - at.x, stand.position.z - at.z).length() < 0.001)
		check("lamp %d stands on the floor" % i, is_equal_approx(stand.position.y, 0.0))

		var shade: Node3D = stand.get_node_or_null("Shade")
		check("lamp %d has a shade" % i, shade != null)
		if shade != null:
			# And the bulb is INSIDE it. A shade hung above or below its own lamp is the version
			# of this bug that still renders a fixture, so the count check alone would pass it.
			var gap: float = absf(shade.global_position.y - at.y)
			check("lamp %d's light is inside its shade (%.1fmm out)" % [i, gap * 1000.0],
					gap < Studio.LAMP_SHADE_HEIGHT * 0.5)

		# Inside the room. A stand is a solid object two metres tall, and the lights were placed
		# back when nothing was drawn at their position, so nothing stopped one being in a wall.
		check("lamp %d is inside the room" % i,
				absf(at.x) < half_width - 0.2 and absf(at.z) < half_depth - 0.2
				and at.y < Studio.WALL_HEIGHT - 0.2)

	studio.queue_free()


func _test_a_body_is_measured_rather_than_assumed() -> void:
	# For six ticks the only statement this project made about human eyesight was one constant in
	# the renderer -- MIN_CAP_ANGLE, 0.0054 radians -- and everything downstream silently assumed
	# the reader was the person who typed it. These checks exist to keep that number, and the
	# reach and the height beside it, as properties of a PERSON that the layout asks about.
	var standing := Ergonomics.standing()
	var seated := Ergonomics.seated_default()
	check("a seated person's eyes are lower than a standing one's",
			seated.eye_height < standing.eye_height)
	check("a seated person looks further down", seated.gaze_down > standing.gaze_down)
	check("a seated person reaches less far", seated.reach < standing.reach)

	# Legibility scales with the text setting, and that is the whole accessibility claim: turning
	# text up does not merely enlarge it, it buys DISTANCE, which is what lets a surface be
	# further away and therefore bigger in the room. A version that only scaled the glyphs would
	# pass a screenshot and fail the person.
	var cap := 0.005
	var plain := standing.legible_to(cap)
	standing.text_scale = 2.0
	check("doubling the text setting halves the distance a label must be read from (%.2fm -> %.2fm)"
			% [plain, standing.legible_to(cap)],
			is_equal_approx(standing.legible_to(cap) * 2.0, plain))
	standing.text_scale = 1.0

	# Both axes, against different angles. The width-only version of this put a 1.2m rack 35cm
	# from the viewer's face, because the rack is narrow and nothing asked about its height.
	var wide := Vector3(1.2, 0.2, 0.1)
	var tall := Vector3(0.2, 1.2, 0.1)
	check("a wide surface is pushed back", standing.fits_in_sweep(wide) > 0.3)
	check("a tall surface is pushed back further than a wide one of the same span",
			standing.fits_in_sweep(tall) > standing.fits_in_sweep(wide))

	# Reach is a preference the two bounds clamp, not a third hard constraint. Placing a surface
	# that cannot fit inside the sweep at arm's length anyway is how it ends up in your face.
	var big := AABB(Vector3(-0.6, -0.6, 0), Vector3(1.2, 1.2, 0.1))
	var near := AABB(Vector3(-0.1, -0.05, 0), Vector3(0.2, 0.1, 0.1))
	var placed_big := standing.place(0.0, big, true, cap)
	var placed_near := standing.place(0.0, near, true, cap)
	check("a surface too big for the sweep is placed beyond reach rather than inside it",
			(placed_big * big.get_center()).length() > standing.reach)
	check("a small surface is placed at a comfortable working distance (%.2fm)"
			% (placed_near * near.get_center()).length(),
			absf((placed_near * near.get_center()).length() - standing.working_distance()) < 0.02)
	check("nothing is ever placed closer than the near limit",
			(placed_near * near.get_center()).length() >= Ergonomics.NEAR_LIMIT - 0.001)

	# And when the two bounds genuinely cross, it says so rather than returning a compromise.
	check("a surface that cannot be both read and swept is reported, not fudged",
			standing.too_big_to_place(big, 0.0005))
	check("a surface that can be both is not", not standing.too_big_to_place(near, cap))

	# The gaze drop yields to a tall surface. Applied blind to the centre, a 20-degree drop put
	# the rack's bottom row 50 degrees below the horizon and straight off the bottom of the
	# frame -- comfortable for the middle of the surface and useless for the ends of it.
	var flat := AABB(Vector3(-0.2, -0.05, 0), Vector3(0.4, 0.1, 0.05))
	var high := AABB(Vector3(-0.2, -0.3, 0), Vector3(0.4, 0.6, 0.05))
	check("a small panel gets the full comfortable drop",
			is_equal_approx(rad_to_deg(standing.drop_for(flat, 0.5, true)), standing.gaze_down))
	check("a tall panel straightens up",
			standing.drop_for(high, 0.5, true) < standing.drop_for(flat, 0.5, true))
	check("no surface is ever lifted above the horizon",
			standing.drop_for(AABB(Vector3(-1, -2, 0), Vector3(2, 4, 0.1)), 0.5, true) >= 0.0)
	for box in [flat, high]:
		var placed := standing.place(0.0, box, true, cap)
		var lowest: Vector3 = placed * (box.get_center() - Vector3(0, box.size.y * 0.5, 0))
		check("the bottom edge of a %.1fm surface stays inside the eye sweep (%.0f deg)"
				% [box.size.y, rad_to_deg(atan2(-lowest.y, -lowest.z))],
				rad_to_deg(atan2(-lowest.y, -lowest.z)) <= standing.gaze_sweep + 1.0)

	# Placement is bearing-relative, which is what makes the arc an arc.
	var left := standing.place(-60.0, near, false, cap) * near.get_center()
	var right := standing.place(60.0, near, false, cap) * near.get_center()
	check("a bearing to the left puts the surface to the left", left.x < -0.1)
	check("left and right are mirror images (%.3f vs %.3f)" % [left.x, right.x],
			is_equal_approx(left.x, -right.x) and is_equal_approx(left.z, right.z))


func _test_the_frame_follows_a_turn_without_chasing_a_glance() -> void:
	# The single most important comfort rule in the project, and the cheapest to get wrong: gear
	# bolted to the head is gear that can never be looked away from, which is nauseating within
	# about a minute. Gear bolted to the ROOM is what this studio already was, and it made people
	# walk. The frame between them follows a deliberate turn and ignores a glance, and these
	# checks pin exactly that boundary.
	var dead := 42.0
	check("a glance inside the deadzone moves nothing",
			is_equal_approx(BodyFrame.follow_yaw(0.0, deg_to_rad(30.0), dead, 0.5, 1.0), 0.0))
	check("a glance right to the edge still moves nothing",
			is_equal_approx(BodyFrame.follow_yaw(0.0, deg_to_rad(41.9), dead, 0.5, 1.0), 0.0))

	# Past the edge it chases the EDGE, not the head. Chasing the head would drag the whole
	# workspace round with every turn and leave nothing to turn TOWARDS.
	var turned := BodyFrame.follow_yaw(0.0, deg_to_rad(90.0), dead, 0.0, 1.0)
	check("a real turn moves the frame to the deadzone edge, not to the head (%.0f deg)"
			% rad_to_deg(turned), is_equal_approx(rad_to_deg(turned), 90.0 - dead))
	check("turning the other way is symmetric",
			is_equal_approx(BodyFrame.follow_yaw(0.0, deg_to_rad(-90.0), dead, 0.0, 1.0), -turned))

	# Damped, and the damping is frame-rate independent -- an exponential close, not a fixed
	# fraction per tick. A lerp per frame makes the comfort setting mean different things at
	# 72Hz and 120Hz, which are both headset refresh rates this has to run at.
	var one_step := BodyFrame.follow_yaw(0.0, deg_to_rad(90.0), dead, 0.5, 0.2)
	check("damping lands short of the target", absf(one_step) < absf(turned))
	check("damping moves in the right direction", one_step > 0.0)
	var halves := BodyFrame.follow_yaw(BodyFrame.follow_yaw(0.0, deg_to_rad(90.0), dead, 0.5, 0.1),
			deg_to_rad(90.0), dead, 0.5, 0.1)
	check("two half steps land where one whole step does, so refresh rate does not change feel",
			absf(halves - one_step) < 0.002)

	# Wrapping. A turn across the back of the compass is a short turn, not a 350-degree one.
	var wrapped := BodyFrame.follow_yaw(deg_to_rad(175.0), deg_to_rad(-175.0), dead, 0.0, 1.0)
	check("a turn across the wrap is treated as the short way round",
			absf(rad_to_deg(angle_difference(wrapped, deg_to_rad(175.0)))) < 1.0)


func _test_summoned_gear_lands_where_a_person_can_use_it() -> void:
	# What a screenshot cannot check. The first arc put two of five surfaces at 132 degrees --
	# behind the shoulders, where "still visible at a glance" is simply false -- and parked a
	# small surface at 0.47m while the focused rack sat at 0.98m, so the thing you were NOT using
	# was nearer than the thing you were. Both rendered as a plausible-looking room.
	var seen: Array[float] = []
	for i in 8:
		var bearing := FocusRig.bearing_for(i)
		check("parked surface %d is in front of the person (%+.0f deg)" % [i, bearing],
				absf(bearing) <= FocusRig.MAX_BEARING)
		check("parked surface %d is clear of the work (%+.0f deg)" % [i, bearing],
				absf(bearing) >= FocusRig.FIRST_BEARING)
		seen.append(bearing)
	check("the arc fills outward from the work alternately, not off one shoulder",
			seen[0] > 0.0 and seen[1] < 0.0 and absf(seen[2]) > absf(seen[0]))

	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	# Summoning: what this checks is where gear lands when it is BROUGHT. A monitor visits by
	# default; summoning is one key away and is how a headset works.
	studio.focus.visits = false
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	studio.ergonomics.motion_scale = 0.0
	studio.focus.focus(&"rack")
	studio.body._process(0.0)

	var work := 0.0
	var parked: Array[float] = []
	for surface in studio.focus.surfaces:
		var local := studio.body.global_transform.affine_inverse() * surface.global_transform
		var centre := local * surface.content_aabb().get_center()
		if surface.surface_id == &"rack":
			work = centre.length()
		else:
			parked.append(centre.length())
			check("%s is not behind the viewer (%+.0f deg)" % [surface.surface_id,
					rad_to_deg(atan2(centre.x, -centre.z))],
					absf(rad_to_deg(atan2(centre.x, -centre.z))) <= FocusRig.MAX_BEARING + 1.0)
		check("%s is below eye level, not above it" % surface.surface_id, centre.y < 0.0)
	for distance in parked:
		check("nothing parked is nearer than the work (%.2fm vs %.2fm)" % [distance, work],
				distance > work)

	# Released, everything goes home. Focus is attention, and attention does not persist.
	studio.focus.release()
	for surface in studio.focus.surfaces:
		check("%s went home when focus was released" % surface.surface_id,
				not studio.body.is_ancestor_of(surface))
	check("nothing is still held by the rig",
			studio.focus.surfaces.all(func(s): return not studio.focus.holds(s.surface_id)))

	studio.queue_free()


func _test_no_signal_is_carried_by_colour_alone() -> void:
	# The three buttons in a channel strip are identical rectangles in a vertical column, and
	# until now the only thing separating record from solo from mute was red against amber
	# against blue -- the exact pair a deutan cannot separate, with no label, shape or position
	# to fall back on. Roughly one man in twelve reads this console wrong.
	#
	# What makes this testable rather than a matter of taste is that colour deficiency is a
	# measurable transform: run the palette through it and ask whether the signals are still
	# distinguishable. A tuned palette is not a claim, it is a number.
	var worst_default := 99.0
	for vision in [Ergonomics.ColourVision.FULL, Ergonomics.ColourVision.DEUTAN,
			Ergonomics.ColourVision.PROTAN, Ergonomics.ColourVision.TRITAN,
			Ergonomics.ColourVision.MONO]:
		var eyes := Ergonomics.new()
		eyes.colour_vision = vision
		var plain := Ergonomics.new()
		for group in [[&"record", &"solo", &"mute"], [&"ok", &"warn", &"over"]]:
			for i in group.size():
				for j in range(i + 1, group.size()):
					var tuned: float = eyes.separation(eyes.signal_colour(group[i]),
							eyes.signal_colour(group[j]))
					check("%s and %s stay apart for vision %d (%.2f)"
							% [group[i], group[j], vision, tuned], tuned > 0.30)
					if vision != Ergonomics.ColourVision.FULL:
						worst_default = minf(worst_default, eyes.separation(
								plain.signal_colour(group[i]), plain.signal_colour(group[j])))

	# And the palette is actually doing work. If the default one survived every deficiency there
	# would be nothing here to fix, and this whole mechanism would be ceremony.
	check("the default palette really does collapse for some reader (worst %.2f)"
			% worst_default, worst_default < 0.15)

	# Simulation sanity, so a broken matrix cannot quietly make everything look fine.
	var deutan := Ergonomics.new()
	deutan.colour_vision = Ergonomics.ColourVision.DEUTAN
	var mono := Ergonomics.new()
	mono.colour_vision = Ergonomics.ColourVision.MONO
	check("full colour vision changes nothing",
			Ergonomics.new().simulate(Color(0.9, 0.2, 0.1)) == Color(0.9, 0.2, 0.1))
	# Against full vision rather than against an absolute, because the naive version of this
	# check is wrong about the science: a deuteranope separates pure red from pure green
	# perfectly well, by BRIGHTNESS -- green is far lighter. The confusion is of hues matched in
	# lightness, which is exactly what a row of equally bright status LEDs is.
	var plain_eyes := Ergonomics.new()
	var red_green := Color(0.86, 0.42, 0.20)
	var green_red := Color(0.40, 0.62, 0.24)
	check("deuteranopia collapses two equally bright red-green hues (%.2f -> %.2f)"
			% [plain_eyes.separation(red_green, green_red),
			deutan.separation(red_green, green_red)],
			deutan.separation(red_green, green_red)
			< plain_eyes.separation(red_green, green_red) * 0.5)
	check("deuteranopia leaves blue and yellow apart",
			deutan.separation(Color.BLUE, Color.YELLOW) > 0.5)
	var grey := mono.simulate(Color(0.2, 0.9, 0.4))
	check("monochromacy returns a grey", is_equal_approx(grey.r, grey.g)
			and is_equal_approx(grey.g, grey.b))

	# The shape half. Colour is never the only channel even when it works, because the palette
	# is a guess about one reader and the silhouette is a fact about the button.
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	studio.console._process(0.0)
	var strips := studio.console.find_children("*", "ChannelStrip", true, false)
	check("there are strips to look at", strips.size() > 0)
	if strips.size() > 0:
		var shapes: Array[Vector2] = []
		for button in strips[0].find_children("*", "PanelButton", true, false):
			shapes.append((button as PanelButton).lamp_scale)
		check("a strip has three signal lamps (%d)" % shapes.size(), shapes.size() >= 3)
		for i in shapes.size():
			for j in range(i + 1, shapes.size()):
				check("lamp %d and lamp %d are different shapes (%v vs %v)"
						% [i, j, shapes[i], shapes[j]], shapes[i] != shapes[j])
	studio.queue_free()


func _test_a_control_can_be_worked_without_a_steady_hand() -> void:
	# Every control in this studio needs a press held steady on a small target. That is the one
	# interaction a tremor, a prosthetic, a one-handed session or a cheap tracker all fail at,
	# and until now there was no alternative to it anywhere.
	var erg := Ergonomics.new()
	Ergonomics.current = erg
	var rig := Node3D.new()
	add_child(rig)
	var probe := _DwellProbe.new()
	rig.add_child(probe)
	var button := PanelButton.new()
	rig.add_child(button)

	var fired: Array[int] = []
	button.pressed.connect(func(): fired.append(1))

	# Off by default, and that is the right default: an always-on dwell fires at anything the
	# eye happens to rest on.
	erg.dwell_seconds = 0.0
	probe.hovered = button
	for i in 20:
		probe._tick_dwell(Vector3.ZERO, 0.1)
	check("dwell does nothing until someone asks for it", fired.is_empty())

	erg.dwell_seconds = 0.5
	for i in 3:
		probe._tick_dwell(Vector3.ZERO, 0.1)
	check("a dwell short of the time does not fire", fired.is_empty())
	check("but it shows how far through it is (%.2f)" % button.dwell_progress,
			button.dwell_progress > 0.4 and button.dwell_progress < 1.0)
	for i in 3:
		probe._tick_dwell(Vector3.ZERO, 0.1)
	check("a dwell that completes fires exactly once (%d)" % fired.size(), fired.size() == 1)
	check("and clears its own indicator", is_equal_approx(button.dwell_progress, 0.0))

	# It must not then fire again while the person is still looking at it. A dwell that repeats
	# is a button that holds itself down.
	for i in 5:
		probe._tick_dwell(Vector3.ZERO, 0.1)
	check("it does not repeat while the gaze stays put", fired.size() == 1)

	# Looking away resets it. A dwell that survives looking away has stopped measuring
	# attention and started measuring elapsed time.
	probe.hovered = null
	probe._tick_dwell(Vector3.ZERO, 0.1)
	probe.hovered = button
	for i in 4:
		probe._tick_dwell(Vector3.ZERO, 0.1)
	check("looking away starts the count again", fired.size() == 1)

	# And a press beats it rather than racing it, so a half-finished dwell followed by a real
	# press does not fire twice.
	probe.pressing = true
	for i in 20:
		probe._tick_dwell(Vector3.ZERO, 0.1)
	check("pressing cancels an unfinished dwell", fired.size() == 1)
	probe.pressing = false

	# Only controls where a mistaken activation is cheap opt in. A fader dwelt on by accident
	# takes a mix somewhere nobody asked for.
	check("a button opts into dwell", button.dwell_activates())
	var fader := Fader.new()
	rig.add_child(fader)
	check("a fader does not", not fader.dwell_activates())
	var knob := Knob.new()
	rig.add_child(knob)
	check("nor does a knob", not knob.dwell_activates())

	rig.queue_free()
	Ergonomics.current = Ergonomics.new()


## An interactor that points wherever the test says, so dwell can be driven without a mouse,
## a headset or a physics frame.
class _DwellProbe extends Interactor:
	var pressing := false

	func is_pressing() -> bool:
		return pressing

	func _physics_process(_delta: float) -> void:
		pass


func _test_a_value_can_be_set_without_a_precise_drag() -> void:
	# The other half of the same problem as dwell. Dwell removed the PRESS; this removes the
	# DRAG, which is the harder one: a press is a moment, a drag is a press sustained while the
	# hand moves accurately, and nothing in this studio could set a value without one.
	var erg := Ergonomics.new()
	Ergonomics.current = erg

	erg.step = 0.0
	check("notches are off by default, so nobody loses resolution they were using",
			is_equal_approx(erg.quantise(0.4137), 0.4137))
	check("and nudging does nothing when they are off",
			is_equal_approx(erg.nudge(0.4137, 1), 0.4137))

	erg.step = 0.05
	check("a value lands on the nearest notch", is_equal_approx(erg.quantise(0.4137), 0.40))
	check("rounding goes to the nearer one", is_equal_approx(erg.quantise(0.4812), 0.50))
	check("notches never leave the range", is_equal_approx(erg.quantise(1.4), 1.0)
			and is_equal_approx(erg.quantise(-0.3), 0.0))

	# Off the current value, not off the nearest notch. Snapping first and moving second loses
	# the first tap, and losing the first tap is how a stepped control earns a reputation for
	# being unresponsive.
	check("a nudge from between notches still moves a full notch",
			is_equal_approx(erg.nudge(0.4137, 1), 0.4637))
	check("and down as well as up", is_equal_approx(erg.nudge(0.4137, -1), 0.3637))
	check("a nudge cannot walk off the end", is_equal_approx(erg.nudge(0.99, 1), 1.0)
			and is_equal_approx(erg.nudge(0.01, -1), 0.0))

	# The fader, which is where it has to actually work. A tap on the trough with notches on is
	# a nudge rather than a jump -- the jump is the behaviour that demands precisely the aim
	# this whole mechanism exists to stop needing.
	var rig := Node3D.new()
	add_child(rig)
	var fader := Fader.new()
	var written: Array[float] = []
	fader.write_value = func(v: float): written.append(v)
	rig.add_child(fader)

	erg.step = 0.0
	fader.value = 0.5
	fader._on_grab_begin(fader.to_global(Vector3(0, 0.95 * Fader.TRAVEL, 0)))
	check("with notches off, a tap on the trough still jumps where you tapped (%.2f)"
			% fader.value, fader.value > 0.9)
	fader._on_grab_end()

	erg.step = 0.05
	fader.value = 0.5
	fader._on_grab_begin(fader.to_global(Vector3(0, 0.95 * Fader.TRAVEL, 0)))
	check("with notches on, the same tap moves one notch (%.2f)" % fader.value,
			is_equal_approx(fader.value, 0.55))
	fader._on_grab_end()
	fader._on_grab_begin(fader.to_global(Vector3(0, 0.02 * Fader.TRAVEL, 0)))
	check("and a tap below moves one notch down (%.2f)" % fader.value,
			is_equal_approx(fader.value, 0.50))
	fader._on_grab_end()
	check("every nudge was reported onward, not just drawn", written.size() >= 2)

	# A drag still works, and lands on notches.
	fader.value = 0.5
	fader._on_grab_begin(fader.to_global(Vector3(0, 0.5 * Fader.TRAVEL, 0)))
	fader._on_grab_move(fader.to_global(Vector3(0, 0.637 * Fader.TRAVEL, 0)))
	check("a drag still works and lands on a notch (%.3f)" % fader.value,
			is_equal_approx(fader.value, erg.quantise(fader.value)))
	fader._on_grab_end()

	rig.queue_free()
	Ergonomics.current = Ergonomics.new()


func _test_you_can_tell_which_surface_has_your_attention() -> void:
	# The rig moves five surfaces at once and only one of them is the work. From inside the arc
	# the only thing distinguishing them was distance -- which is also what changes when a
	# surface is a different size, so a small surface close by and a large one further out read
	# identically. State needs its own channel.
	var size := Vector2(0.5, 0.3)
	var marks := FocusHalo.brackets(size)
	check("the brackets are one mesh, so the whole arc costs one draw per state",
			marks.get_surface_count() == 1)
	var points: PackedVector3Array = marks.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check("there are eight bars, two per corner", points.size() == 8 * 6)

	# Present at every corner and nowhere in the middle. A bracket set that drifted to one side
	# would still render as something and still look deliberate.
	var corners := 0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var want := Vector2(sx * size.x * 0.5, sy * size.y * 0.5)
			for p in points:
				if Vector2(p.x, p.y).distance_to(want) < FocusHalo.THICKNESS:
					corners += 1
					break
	check("every corner is marked (%d of 4)" % corners, corners == 4)
	for p in points:
		check("nothing is drawn across the middle of the surface",
				absf(p.x) > size.x * 0.25 or absf(p.y) > size.y * 0.25)

	# The arm scales with the surface but is capped. A fixed arm is a border on a patchbay and
	# a speck on a ninety-track desk; an uncapped fraction is two sides of a box that failed
	# to meet.
	var small: PackedVector3Array = FocusHalo.brackets(Vector2(0.2, 0.2)).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var huge: PackedVector3Array = FocusHalo.brackets(Vector2(4.0, 2.0)).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check("a bigger surface gets a longer arm",
			_halo_arm(huge, 4.0) > _halo_arm(small, 0.2))
	check("but never longer than the cap (%.3f)" % _halo_arm(huge, 4.0),
			_halo_arm(huge, 4.0) <= FocusHalo.MAX_ARM + 0.001)

	# And in the studio: marked while held, gone when released, and never counted as part of
	# the surface it is sized from.
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	# Summoning: what this checks is where gear lands when it is BROUGHT. A monitor visits by
	# default; summoning is one key away and is how a headset works.
	studio.focus.visits = false
	# Halos are a headset cue and a screen studio turns them off; this is a test of the
	# mechanism, and a headset studio cannot be built without a headset. Switched on by hand,
	# and `_test_a_monitor_draws_no_presentation_brackets` covers the screen default.
	studio.focus.show_halo = true
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	studio.ergonomics.motion_scale = 0.0
	studio.focus.focus(&"rack")
	for surface in studio.focus.surfaces:
		surface._process(0.0)

	var focused_colour := Color.BLACK
	var parked_colour := Color.BLACK
	for surface in studio.focus.surfaces:
		var halo := surface.get_node_or_null("FocusHalo") as FocusHalo
		if surface.wrap_radius() > 0.0:
			# A bent surface gets no corner brackets, and that is deliberate rather than a
			# gap: its bounding box is a chord-shaped slab that no part of the geometry
			# follows, so brackets drawn on it would hang in space off the ends of the arc.
			# It is marked by its berth instead, which the next block checks.
			check("%s is bent, so it is not bracketed" % surface.surface_id, halo == null)
			continue
		check("%s is marked while the rig holds it" % surface.surface_id, halo != null)
		if halo == null:
			continue
		var shown: Color = (halo.material_override as StandardMaterial3D).albedo_color
		if surface.surface_id == &"rack":
			focused_colour = shown
		else:
			parked_colour = shown
	check("the focused surface is marked differently from the parked ones",
			focused_colour != parked_colour)
	# What this is really about is chrome never being counted as content, and the first version
	# tested it by measuring one surface before and after focus. That stopped meaning anything
	# the moment focusing a console also PAGED it: the box changed because the desk changed,
	# which is correct, and the test failed for a reason that had nothing to do with halos.
	# Measured against itself with the chrome taken away instead.
	var marked: Surface = null
	for surface in studio.focus.surfaces:
		if surface.get_node_or_null("FocusHalo") != null:
			marked = surface
			break
	check("some surface in the room is bracketed", marked != null)
	if marked != null:
		var with_chrome: AABB = marked.content_aabb()
		var halo: Node = marked.get_node("FocusHalo")
		marked.remove_child(halo)
		halo.queue_free()
		check("marking a surface does not change how big it measures",
				marked.content_aabb().size.is_equal_approx(with_chrome.size))

	# The place it came out of is marked too, so a rack frame with its units gone reads as a
	# vacant berth rather than as a modelling mistake -- but only when the surface really did
	# come out of the room. The timeline lives under the screen stage, which is a child of the
	# CAMERA: a berth drawn there is parented to the viewpoint and sails around the room with
	# it, marking a place that does not exist and that nothing was ever vacated from.
	var berthed := 0
	for surface in studio.focus.surfaces:
		var berth := studio.studio_set.get_node_or_null("Berth_%s" % surface.surface_id)
		if surface.surface_id == &"timeline":
			check("a surface that was never standing in the room gets no berth", berth == null)
			check("and nothing is drawn on the camera for it",
					studio.camera.find_children("Berth_*", "", true, false).is_empty())
		else:
			check("%s leaves a berth behind" % surface.surface_id, berth != null)
			if berth != null:
				berthed += 1
				check("%s's berth is where it was standing" % surface.surface_id,
						berth.global_position.distance_to(
						(studio.studio_set.global_transform * (studio.focus._home[
						surface.surface_id][1] as Transform3D)).origin) < 0.001)
	check("every room surface left one (%d)" % berthed, berthed == 4)

	studio.focus.release()
	for surface in studio.focus.surfaces:
		check("%s loses its marks when released" % surface.surface_id,
				surface.get_node_or_null("FocusHalo") == null)
		check("and its berth is cleaned up too",
				studio.studio_set.get_node_or_null("Berth_%s" % surface.surface_id) == null)
	studio.queue_free()


## The longest distance any bracket vertex runs in from its own corner.
func _halo_arm(points: PackedVector3Array, width: float) -> float:
	var arm := 0.0
	for p in points:
		arm = maxf(arm, width * 0.5 - absf(p.x))
	return arm


## --- A desk too wide to face ---------------------------------------------------------------

func _test_a_wide_desk_bends_round_you_instead_of_past_you() -> void:
	var erg := Ergonomics.standing()
	var pitch := ChannelStrip.HEIGHT * cos(deg_to_rad(ConsoleSurface.PANEL_TILT)) + ConsoleSurface.ROW_GAP

	# The arithmetic first, where it can be checked against a protractor rather than a render.
	close_to("one head-turn each way is two radii of arc",
			erg.wrap_span(1.0), 2.0 * deg_to_rad(erg.head_turn))
	check("a bigger circle brings more arc to the front",
			erg.wrap_span(1.0) > erg.wrap_span(0.5))
	check("a bigger circle also makes room for another row",
			erg.wrap_rows(1.0, pitch) > erg.wrap_rows(0.5, pitch))
	check("one row always, even when nothing fits", erg.wrap_rows(0.01, pitch) >= 1)
	var in_strips := erg.wrap_capacity(0.8, pitch, ChannelStrip.WIDTH) / ChannelStrip.WIDTH
	check("capacity is whole strips, never a fraction of one (%.3f)" % in_strips,
			absf(in_strips - roundf(in_strips)) < 0.001)

	# THE number this whole exercise turns on: at arm's length a neck sweeps about a metre of
	# arc. Seventeen strips. Anyone who expects a wrap to swallow a 90-track session in one
	# circle is off by a factor of five, and would reach for a bigger circle -- which is why
	# wrap_radius_for grows rows and radius together rather than radius alone.
	check("a neck at arm's length sweeps about a metre of arc (%.2fm)" % erg.wrap_span(0.508),
			erg.wrap_span(0.508) > 0.9 and erg.wrap_span(0.508) < 1.1)

	var narrow := erg.wrap_radius_for(0.9, pitch, ChannelStrip.WIDTH, ConsoleSurface.SMALLEST_CAP)
	close_to("a desk that already fits is left at arm's length", narrow, erg.working_distance())
	var wide := erg.wrap_radius_for(5.5, pitch, ChannelStrip.WIDTH, ConsoleSurface.SMALLEST_CAP)
	check("a desk that does not fit is pushed back (%.2fm)" % wide, wide > narrow)
	check("but never past the point the lettering gives out (%.2fm)" % wide,
			wide <= erg.legible_to(ConsoleSurface.SMALLEST_CAP) + 0.0001)
	check("and the radius it lands on is the smallest one that works",
			erg.wrap_capacity(wide, pitch, ChannelStrip.WIDTH) >= 5.5
			and erg.wrap_capacity(wide - Ergonomics.WRAP_SEARCH_STEP, pitch,
					ChannelStrip.WIDTH) < 5.5)
	var hopeless := erg.wrap_radius_for(50.0, pitch, ChannelStrip.WIDTH,
			ConsoleSurface.SMALLEST_CAP)
	close_to("nothing fits and it says so by stopping at the ceiling, not by going further",
			hopeless, erg.legible_to(ConsoleSurface.SMALLEST_CAP))

	# The sign. The first wrapped desk was tipped UP by its gaze drop instead of down, because
	# rotating an arc about a centre AHEAD of it moves it the opposite way to tilting a panel in
	# place. Every strip was above the horizon and the top row was sixty degrees up.
	var bounds := AABB(Vector3(-0.5, 0.0, -0.1), Vector3(1.0, 0.9, 0.2))
	var placed := erg.place_wrapped(0.0, 0.8, true, bounds.get_center().y)
	var middle: Vector3 = placed * Vector3(0.0, bounds.get_center().y, 0.0)
	check("a wrapped desk sits below the horizon, not above it (%.2fm)" % middle.y,
			middle.y < 0.0)
	close_to("and at elbow height, which is where a desk is",
			middle.y, erg.desk_height() - erg.eye_height, 0.001)
	# IN PLAN. The arc is a vertical cylinder sat below the eye, so the eye is at its axis and
	# not at its centre: every point is one radius away measured on the floor, and further than
	# that measured through the air, by exactly how far down the desk is.
	close_to("and its middle is exactly a radius away in plan",
			Vector2(middle.x, middle.z).length(), 0.8, 0.001)
	# The edge has to be taken off the ARC, not off a ruler: place_wrapped sets where the circle
	# goes, and the surface's own _seat is what puts a strip on it. A straight x offset of 0.6
	# is a point floating off the curve, a metre away, which is exactly what it measured.
	var theta := 0.75
	var on_arc := Vector3(sin(theta) * 0.8, bounds.get_center().y, 0.8 - cos(theta) * 0.8)
	var edge: Vector3 = placed * on_arc
	close_to("so is its edge -- that is the whole point of bending it",
			Vector2(edge.x, edge.z).length(), 0.8, 0.001)
	# Two degrees of slack, and they are real rather than sloppy: the gaze drop tilts the whole
	# circle about the eye, and a tilted circle seen from its own centre reads a point off to
	# the side as very slightly further round than it is. The bend is exact; the bearing is
	# what a head actually has to turn, which is the number worth asserting.
	# Exact now, not within two degrees. The slack was there because the old placement tipped
	# the circle and a tilted circle reads its side points as further round than they are; an
	# upright one does not, so the bearing is simply the angle.
	close_to("and the edge is exactly that far round (%.0f deg)" % rad_to_deg(theta),
			absf(rad_to_deg(atan2(edge.x, -edge.z))), rad_to_deg(theta), 0.2)

	# And the desk itself. Before the rows went in, a 90-track console at a fixed arm's-length
	# radius wrapped to plus or minus 179 degrees: sixty strips behind the mixer's own head,
	# rendering as a perfectly convincing wall of channels from any camera placed in front.
	for tracks in [48, 90]:
		var offline := OfflineBackend.new()
		offline.track_count = tracks
		DAW.use(offline)
		var studio := Studio.new()
		studio.medium = Presentation.Medium.SCREEN
		add_child(studio)
		# Summoning: what this checks is where gear lands when it is BROUGHT. A monitor visits by
		# default; summoning is one key away and is how a headset works.
		studio.focus.visits = false
		studio.ergonomics.motion_scale = 0.0
		Ergonomics.current = studio.ergonomics
		for surface in studio.focus.surfaces:
			surface._process(0.0)
		studio.focus.focus(&"console")
		for surface in studio.focus.surfaces:
			surface._process(0.0)
		studio.focus.focus(&"console")

		var console: ConsoleSurface = null
		for surface in studio.focus.surfaces:
			if surface.surface_id == &"console":
				console = surface
		check("%d tracks is wide enough to be worth bending" % tracks,
				console.wrap_radius() > 0.0)
		var inv := studio.body.global_transform.affine_inverse()
		var widest := 0.0
		var furthest := 0.0
		var below := true
		for strip in console.find_children("Strip*", "Node3D", true, false):
			var at: Vector3 = inv * strip.global_position
			widest = maxf(widest, absf(rad_to_deg(atan2(at.x, -at.z))))
			furthest = maxf(furthest, at.length())
			below = below and at.y < studio.ergonomics.shoulder_height() * 0.5
		check("every one of %d strips is inside a head-turn (worst %+.0f deg)"
				% [tracks, widest], widest <= studio.ergonomics.head_turn + 7.0)
		check("and none of them is behind the mixer", widest < 90.0)
		check("%d tracks stays inside reading distance (%.2fm of %.2fm)"
				% [tracks, furthest, studio.ergonomics.legible_to(ConsoleSurface.SMALLEST_CAP)],
				furthest <= studio.ergonomics.legible_to(ConsoleSurface.SMALLEST_CAP) + 0.05)
		studio.queue_free()
		remove_child(studio)

	DAW.use(OfflineBackend.new())


## The console declares its own smallest lettering, because it has to choose a radius before a
## single label exists. This is the test that stops the declaration drifting from the truth.
func _test_the_desk_knows_how_small_its_own_lettering_is() -> void:
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	var console: Surface = null
	for surface in studio.focus.surfaces:
		if surface.surface_id == &"console":
			console = surface

	var smallest := INF
	for node in console.find_children("*", "Label3D", true, false):
		var label: Label3D = node
		if label.text.is_empty() or not label.visible:
			continue
		if label.is_in_group(&"presentation_chrome") or FocusRig._chrome_above(label, console):
			continue
		smallest = minf(smallest, Lettering.cap_height(label))
	close_to("the declared smallest cap is the one actually built",
			ConsoleSurface.SMALLEST_CAP, smallest, 0.00001)
	close_to("and that is what the rig reads off the desk",
			FocusRig.smallest_cap(console), smallest, 0.00001)

	# Chrome is not lettering you read the desk by. The handle caption is 5.2mm against the
	# panel's 5.8mm, and counting it held every desk 10cm nearer than its own legends asked
	# for -- to keep legible a label that only exists while you are dragging the thing.
	var chrome_cap := 0.0
	for node in console.find_children("*", "Label3D", true, false):
		var label: Label3D = node
		if FocusRig._chrome_above(label, console) or label.is_in_group(&"presentation_chrome"):
			chrome_cap = maxf(chrome_cap, Lettering.cap_height(label))
	if chrome_cap > 0.0:
		check("chrome lettering exists and is smaller than the desk's own (%.4f)" % chrome_cap,
				chrome_cap < smallest)
		check("yet it does not drag the desk nearer",
				FocusRig.smallest_cap(console) > chrome_cap)
	studio.queue_free()
	remove_child(studio)


## A summoned desk arrives where the furniture already is. This is the test that the furniture
## notices.
##
## The collision is BUILT here rather than waited for. In the shipped room nothing currently
## stands inside the paged desk -- the stands are all further back than the mix position -- so
## a test that asserted "something got hidden" would have been asserting a coincidence of this
## year's furniture layout, and would go green for the wrong reason the day someone nudges a
## trolley. What is worth holding is the rule: while gear is summoned, nothing visible in the
## room is inside it.
func _test_the_room_gets_out_of_the_way_of_the_gear_that_left_it() -> void:
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	# Summoning: what this checks is where gear lands when it is BROUGHT. A monitor visits by
	# default; summoning is one key away and is how a headset works.
	studio.focus.visits = false
	studio.ergonomics.motion_scale = 0.0
	for surface in studio.focus.surfaces:
		surface._process(0.0)

	var furniture: Array[Node3D] = []
	for node in studio.studio_set.find_children("*", "Node3D", true, false):
		if node.is_in_group(&"room_furniture"):
			furniture.append(node)
	check("the room's furniture comes in assemblies, not loose boxes (%d)" % furniture.size(),
			furniture.size() >= 4)
	for piece in furniture:
		check("%s is whole before anything is focused" % piece.name, piece.visible)

	studio.focus.focus(&"console")
	for surface in studio.focus.surfaces:
		surface._process(0.0)

	var console: Surface = null
	for surface in studio.focus.surfaces:
		if surface.surface_id == &"console":
			console = surface
	var desk := console.global_transform * console.content_aabb()

	# A stand put exactly where the desk now is. Nothing in the room does this today; the
	# point is that the rig does not depend on nothing in the room doing it.
	var intruder := Node3D.new()
	intruder.name = "TestStand"
	intruder.add_to_group(&"room_furniture")
	studio.studio_set.add_child(intruder)
	var pole := MeshInstance3D.new()
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.04, 1.4, 0.04)
	pole.mesh = pole_mesh
	pole.position = desk.get_center() - studio.studio_set.global_position
	intruder.add_child(pole)
	check("the planted stand really is inside the desk",
			FocusRig._world_aabb(intruder).intersects(desk))

	studio.focus._clear_the_way()
	check("and it yields", not intruder.visible)
	for piece in furniture:
		if piece.visible:
			check("%s was clear and stays" % piece.name,
					not FocusRig._world_aabb(piece).intersects(desk))

	studio.focus.release()
	check("the planted stand comes back when the gear does", intruder.visible)
	for piece in furniture:
		check("%s comes back too" % piece.name, piece.visible)

	studio.queue_free()
	remove_child(studio)
	DAW.use(OfflineBackend.new())


## One lamp too close to one end of the desk, and that end blows to white.
##
## This is a thing renders show and nobody reads as a bug, because an overexposed panel looks
## like a lit panel until you put the other end beside it. The third practical used to stand
## 0.71m from the left end of a summoned desk and 1.55m from the right -- five to one from
## that lamp alone, 1.74x once every other light in the room is added in, which is what this
## measures and what it rejected when the old position was put back to check. The left end
## blew to white: the BANK module read as a hole in the panel and its indicator bar came back
## white instead of blue.
##
## Inverse square only, no range curve and no shadowing, so this is a model and not a render.
## That is enough: the failure was never subtle, and the thing worth catching is somebody
## moving a lamp or turning one up without looking at what is standing under it.
func _test_the_desk_is_lit_evenly_end_to_end() -> void:
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	# Summoning: what this checks is where gear lands when it is BROUGHT. A monitor visits by
	# default; summoning is one key away and is how a headset works.
	studio.focus.visits = false
	studio.ergonomics.motion_scale = 0.0
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	studio.focus.focus(&"console")
	for surface in studio.focus.surfaces:
		surface._process(0.0)

	var console: Surface = null
	for surface in studio.focus.surfaces:
		if surface.surface_id == &"console":
			console = surface
	var desk := console.global_transform * console.content_aabb()
	var mid := desk.get_center()
	var left := Vector3(desk.position.x, mid.y, mid.z)
	var right := Vector3(desk.position.x + desk.size.x, mid.y, mid.z)

	var lamps: Array = []
	for node in studio.find_children("*", "OmniLight3D", true, false):
		var lamp: OmniLight3D = node
		lamps.append([lamp.global_position, lamp.light_energy])
	check("there are lamps to measure (%d)" % lamps.size(), lamps.size() >= 2)

	var at_left := 0.0
	var at_right := 0.0
	for lamp in lamps:
		var pos: Vector3 = lamp[0]
		var energy: float = lamp[1]
		at_left += energy / maxf(pos.distance_squared_to(left), 0.01)
		at_right += energy / maxf(pos.distance_squared_to(right), 0.01)

	var ratio := maxf(at_left, at_right) / maxf(minf(at_left, at_right), 0.0001)
	check("the desk's two ends are lit within 25%% of each other (%.2fx: %.2f vs %.2f)"
			% [ratio, at_left, at_right], ratio < 1.25)

	studio.queue_free()
	remove_child(studio)
	DAW.use(OfflineBackend.new())


## Whatever is focused has to be entirely on screen.
##
## The rig sized gear to the BODY -- what a neck yaws and eyes sweep -- which is the right
## constraint for a headset and the wrong one for a window. A neck turns 55 degrees each way;
## a seated 54-degree lens shows 27. Wherever those disagree the lens wins, and for a long
## time nothing noticed: the patchbay at 48 tracks sat exactly where the sweep asked and ran
## three-quarters of its width past each edge of the frame, having passed every ergonomics
## check in this file on the way past.
##
## Checked by projecting the corners rather than by eye, because a surface overflowing the
## frame renders as a surface filling the frame, which is what you wanted it to do.
func _test_focused_gear_fits_the_frame_it_is_shown_in() -> void:
	var off := OfflineBackend.new()
	off.track_count = 48
	DAW.use(off)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	# Summoning: what this checks is where gear lands when it is BROUGHT. A monitor visits by
	# default; summoning is one key away and is how a headset works.
	studio.focus.visits = false
	studio.ergonomics.motion_scale = 0.0
	for surface in studio.focus.surfaces:
		surface._process(0.0)

	var ids: Array[StringName] = []
	for surface in studio.focus.surfaces:
		ids.append(surface.surface_id)
	check("there is gear to focus (%d)" % ids.size(), ids.size() >= 3)

	for id in ids:
		studio.focus.focus(id)
		# Twice: the rebuild a focus triggers changes the surface's size, and the placement
		# that follows is computed from the new size. One pass measures the old shape in the
		# new place.
		for _pass in 2:
			for surface in studio.focus.surfaces:
				surface._process(0.0)
		studio._sit_down()

		var focused: Surface = null
		for surface in studio.focus.surfaces:
			if surface.surface_id == id:
				focused = surface
		var box := focused.content_aabb()
		if box.size.x <= 0.0:
			continue
		var world := focused.global_transform * box
		var cam := studio.camera
		var half_v := tan(deg_to_rad(cam.fov * 0.5))
		var half_h := half_v * studio.ergonomics.view_aspect
		var worst := 0.0
		var behind := 0
		for corner in 8:
			var local := cam.global_transform.affine_inverse() * world.get_endpoint(corner)
			if local.z >= -0.01:
				behind += 1
				continue
			worst = maxf(worst, absf(local.x / -local.z) / half_h)
			worst = maxf(worst, absf(local.y / -local.z) / half_v)
		check("%s has no corner behind the camera" % id, behind == 0)
		check("%s fits the frame (worst corner at %.2f of the half-frame)" % [id, worst],
				worst <= 1.0)

	studio.queue_free()
	remove_child(studio)
	DAW.use(OfflineBackend.new())


## A hover card that says "KNOB3" is the scene graph talking, not the desk. Every control in a
## built studio has to name itself by what it does -- and the check is against the node name
## precisely because that is the fallback a builder gets by forgetting.
func _test_every_control_says_what_it_is() -> void:
	var off := OfflineBackend.new()
	off.track_count = 13
	DAW.use(off)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	for surface in studio.focus.surfaces:
		surface._process(0.0)

	var controls := studio.find_children("*", "ControlAffordance", true, false)
	check("the studio has controls to describe (%d)" % controls.size(), controls.size() > 40)
	var anonymous: Array[String] = []
	var faders := 0
	var faders_in_db := 0
	for node in controls:
		var c := node as ControlAffordance
		var t := c.title()
		if t.strip_edges() == "" or t == String(c.name).to_upper():
			anonymous.append("%s (%s)" % [c.get_path(), t])
		if c is Fader:
			faders += 1
			if c.readout().ends_with(" dB"):
				faders_in_db += 1
	check("every control names itself, not its node (%s)" % ", ".join(anonymous.slice(0, 4)),
			anonymous.is_empty())
	check("every fader reads in dB (%d of %d)" % [faders_in_db, faders], faders > 0 \
			and faders_in_db == faders)

	var strips := studio.find_children("*", "ChannelStrip", true, false)
	check("there is a channel strip to read (%d)" % strips.size(), not strips.is_empty())
	if not strips.is_empty():
		var strip := strips[0] as ChannelStrip
		var pan := strip._pan
		check("a pan knob names its track (%s)" % pan.title(),
				pan.title().begins_with(DAW.state.track(strip.track_index).display_name().to_upper()))
		pan.value = 0.5
		check("centre pan reads C (%s)" % pan.readout(), pan.readout() == "C")
		pan.value = 0.2
		check("hard-ish left reads L 60 (%s)" % pan.readout(), pan.readout() == "L 60")
	studio.queue_free()


## Two hands, or a hand and a cursor, on one button. The first to leave must not turn the
## highlight off under the second.
func _test_hover_is_counted_per_interactor() -> void:
	var button := PanelButton.new()
	add_child(button)
	var events: Array[bool] = []
	button.hover_changed.connect(func(on: bool): events.append(on))
	var a := Interactor.new()
	var b := Interactor.new()
	add_child(a)
	add_child(b)
	a._set_hovered(button)
	b._set_hovered(button)
	a._set_hovered(null)
	check("still hovered while one interactor remains", button.is_hovered())
	b._set_hovered(null)
	check("not hovered once both have left", not button.is_hovered())
	check("one enter and one exit, not one per interactor (%s)" % [events],
			events == [true, false])
	b._set_hovered(button)
	# remove_child rather than queue_free: leaving the tree is the event, and it has to have
	# happened by the next line rather than at the end of a frame this suite does not wait for.
	remove_child(b)
	b.free()
	check("an interactor that goes away takes its hover with it", not button.is_hovered())
	a.queue_free()
	button.queue_free()


## The rim marks where a click LANDS. A fader's collision covers its whole travel -- click the
## slot to jump -- so brackets around the cap alone would misstate the control.
func _test_the_rim_brackets_what_the_cursor_can_hit() -> void:
	var fader := Fader.new()
	add_child(fader)
	var box := HoverRim.footprint(fader)
	check("the fader's footprint covers its travel (%.3f >= %.3f)" % [box.size.y, Fader.TRAVEL],
			box.size.y >= Fader.TRAVEL)
	var knob := Knob.new()
	add_child(knob)
	var round := HoverRim.footprint(knob)
	check("a knob's footprint faces the panel, not edge-on (%s)" % round.size,
			round.size.x > 0.015 and round.size.y > 0.015 and round.size.z < round.size.x)
	fader.queue_free()
	knob.queue_free()


## On a monitor, brackets mean "the control under the cursor" and nothing else. The focus halo
## and the berth both hung in mid-air round a summoned desk, and both spoke the hover rim's
## visual language with a different meaning.
func _test_a_monitor_draws_no_presentation_brackets() -> void:
	var off := OfflineBackend.new()
	off.track_count = 13
	DAW.use(off)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	# Summoning: what this checks is where gear lands when it is BROUGHT. A monitor visits by
	# default; summoning is one key away and is how a headset works.
	studio.focus.visits = false
	studio.ergonomics.motion_scale = 0.0
	check("a screen studio does not halo", not studio.focus.show_halo)
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	for id in [&"console", &"rack"]:
		studio.focus.focus(id)
		for _pass in 2:
			for surface in studio.focus.surfaces:
				surface._process(0.0)
		var marks := studio.find_children("*", "FocusHalo", true, false)
		check("no halo or berth with %s focused on a monitor (%d)" % [id, marks.size()],
				marks.is_empty())
	studio.queue_free()


class _LinearProbe extends Interactor:
	var reading := 0.0
	var fine_held := false
	func drag_reading() -> float:
		return reading
	func fine() -> bool:
		return fine_held


## Through the real path: a wheel event pushed into the viewport, caught by the studio's own
## MouseInteractor, before the studio's camera ever hears of it.
func _test_the_wheel_adjusts_what_the_cursor_is_on() -> void:
	var off := OfflineBackend.new()
	off.track_count = 13
	DAW.use(off)
	Ergonomics.current.step = 0.0
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	var hand := studio.get_node("MouseHand") as MouseInteractor
	var strip := studio.find_children("*", "ChannelStrip", true, false)[0] as ChannelStrip

	var wheel := func(up: bool) -> void:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		get_viewport().push_input(e)

	var zoom := studio._orbit_distance
	var pan := strip._pan
	pan.value = 0.5
	hand.hovered = pan
	wheel.call(true)
	close_to("one wheel notch is one detent on a knob", pan.value, 0.5 + 1.0 / Knob.DETENTS)
	close_to("and the knob wrote it to the mix", DAW.state.track(strip.track_index).pan,
			pan.value, 0.001)
	close_to("and the camera did not zoom", studio._orbit_distance, zoom)

	var fader := strip._fader
	var before := DAW.taper_to_db(fader.value)
	hand.hovered = fader
	wheel.call(false)
	close_to("one wheel notch down is one dB on a fader", DAW.taper_to_db(fader.value),
			before - 1.0, 0.01)
	var mid := fader.value
	fader.nudge(hand, 1, true)
	close_to("a fine notch is a tenth of a dB", DAW.taper_to_db(fader.value),
			DAW.taper_to_db(mid) + 0.1, 0.01)
	fader.value = 0.0
	fader.nudge(hand, 1, false)
	close_to("out of -inf the first notch lands on -60 dB", DAW.taper_to_db(fader.value), -60.0, 0.01)

	var committed := [0]
	pan.value_committed.connect(func(_v: float): committed[0] += 1)
	pan.nudge(hand, -1, false)
	check("a nudge commits, so history can hear it", committed[0] == 1)

	var other := FakeHand.new()
	add_child(other)
	pan.grab_begin(other, pan.global_position)
	var held_value := pan.value
	check("a nudge is refused while another hand holds the control",
			not pan.nudge(hand, 1, false) and pan.value == held_value)
	pan.grab_end(other)
	other.queue_free()

	hand.hovered = strip._mute
	var lens := studio.camera.fov
	wheel.call(true)
	check("over a button the wheel still zooms the walker's lens (%.1f -> %.1f)" % [lens,
			studio.camera.fov], studio.camera.fov < lens)
	studio.set_god_mode(true)
	zoom = studio._orbit_distance
	wheel.call(true)
	check("and in god mode it zooms the orbit (%.2f -> %.2f)" % [zoom, studio._orbit_distance],
			studio._orbit_distance < zoom)
	hand.hovered = null
	studio.queue_free()


func _test_a_cursor_drags_a_knob_up_and_down() -> void:
	Ergonomics.current.step = 0.0
	var knob := Knob.new()
	add_child(knob)
	var probe := _LinearProbe.new()
	add_child(probe)
	knob.value = 0.5
	probe.reading = 400.0
	knob.grab_begin(probe, knob.global_position + Vector3(0.005, 0, 0))
	# Sideways across the knob's face, which on a circular drag would be a big turn.
	probe.reading = 400.0
	knob.grab_move(probe, knob.global_position + Vector3(-0.005, 0.0, 0))
	close_to("moving across a knob without moving up does not turn it", knob.value, 0.5)
	probe.reading = 400.0 - Knob.PIXELS_PER_SWEEP * 0.25
	knob.grab_move(probe, knob.global_position)
	close_to("up a quarter of the sweep's pixels is a quarter turn up", knob.value, 0.75)
	probe.fine_held = true
	knob.grab_end(probe)
	knob.grab_begin(probe, knob.global_position)
	probe.reading -= Knob.PIXELS_PER_SWEEP * 0.25
	knob.grab_move(probe, knob.global_position)
	close_to("shift makes the same move a tenth as far", knob.value, 0.775)
	knob.grab_end(probe)

	var hand := FakeHand.new()
	add_child(hand)
	knob.value = 0.5
	knob.grab_begin(hand, knob.global_position + Vector3(0, 0.008, 0))
	knob.grab_move(hand, knob.global_position + Vector3(0.008, 0, 0))
	check("a hand still turns a knob by turning it (%.3f)" % knob.value, knob.value < 0.45)
	knob.grab_end(hand)
	for n in [knob, probe, hand]:
		n.queue_free()


## The face is the readability fix, so a label built without it is a regression nobody would
## see in a diff: the engine's default font draws fine, just soft and grey at a desk's distance.
func _test_every_label_is_set_in_the_distance_field_face() -> void:
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	var face := Lettering.face()
	check("the face is a distance field", face != null and face.multichannel_signed_distance_field)
	var bare := PackedStringArray()
	var seen := 0
	for surface in studio.focus.surfaces:
		for node in surface.find_children("*", "Label3D", true, false):
			var label: Label3D = node
			if label.text.is_empty():
				continue
			seen += 1
			if label.font != face or label.outline_size <= 0 \
					or label.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR:
				bare.append("%s/%s" % [surface.surface_id, label.text])
	check("the studio has lettering to judge (%d)" % seen, seen > 20)
	check("every label wears the face, an outline and a linear filter %s" % [bare], bare.is_empty())
	studio.queue_free()
	remove_child(studio)


func _test_fitted_lettering_stays_in_its_slot() -> void:
	var label := Label3D.new()
	label.pixel_size = 0.00018
	Lettering.dress(label)
	var f := Lettering.face()
	label.text = "1-9"
	Lettering.fit(label, 0.036, 64, 40)
	check("a short legend keeps the size it was offered", label.font_size == 64)
	label.text = "1017-1080"
	Lettering.fit(label, 0.036, 64, 40)
	var wide := f.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	check("a long one shrinks until it fits (%d)" % label.font_size,
			label.font_size < 64 and wide * label.pixel_size <= 0.036)
	check("and its outline follows it down",
			label.outline_size == maxi(2, roundi(label.font_size * Lettering.OUTLINE_FRACTION)))
	label.text = "AN ABSURDLY LONG LEGEND NOBODY COULD FIT"
	Lettering.fit(label, 0.036, 64, 40)
	check("but never below the floor it was given", label.font_size == 40)
	label.text = "RMS SIZE"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Lettering.fit(label, 0.020, 64, 20)
	var word := f.get_string_size("SIZE", HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	var whole := f.get_string_size("RMS SIZE", HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	check("a wrapping label is fitted by its longest word, not its whole line",
			word * label.pixel_size <= 0.020 and whole * label.pixel_size > 0.020)
	label.free()


# --- the floor ------------------------------------------------------------------------------

func _test_footprints_separate_by_the_shallowest_way_out() -> void:
	var a := FloorPlan.footprint(Vector2(0, 0), Vector2(0.5, 0.5), 0.0)
	var b := FloorPlan.footprint(Vector2(0.9, 0.2), Vector2(0.5, 0.5), 0.0)
	var push := FloorPlan.separation(a, b)
	check("two boxes overlapping by 10cm in x are pushed apart in x (%s)" % push,
			push.x < -0.099 and push.x > -0.102 and is_zero_approx(push.y))
	var apart := FloorPlan.footprint(Vector2(1.2, 0), Vector2(0.5, 0.5), 0.0)
	check("boxes that do not touch are left alone", FloorPlan.separation(a, apart) == Vector2.ZERO)
	# The case an axis-aligned test gets wrong: a diamond whose bounding box overlaps the
	# square but whose actual corner stops short of it.
	var diamond := FloorPlan.footprint(Vector2(1.15, 1.15), Vector2(0.5, 0.5), PI / 4.0)
	check("a turned box clear of the corner is clear", FloorPlan.separation(a, diamond) == Vector2.ZERO)
	var cornered := FloorPlan.footprint(Vector2(0.75, 0.75), Vector2(0.5, 0.5), PI / 4.0)
	check("and one into the corner is not", FloorPlan.separation(a, cornered) != Vector2.ZERO)


## A studio on its own throwaway layout, because pushing furniture SAVES where it went, and the
## layout it saves into is the real one of whoever runs the suite.
func _floor_studio() -> Dictionary:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	studio.ergonomics.motion_scale = 0.0
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	var hand := FakeHand.new()
	return {"studio": studio, "hand": hand, "saved_layout": saved_layout}


func _drop_floor_studio(rig: Dictionary) -> void:
	Session.layout = rig["saved_layout"]
	(rig["hand"] as Node).free()
	var studio: Studio = rig["studio"]
	remove_child(studio)
	studio.free()


## A hand straight above a floor point, pointing down at it.
func _hand_over(hand: FakeHand, at: Vector2) -> void:
	hand.pose = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(at.x, 2.0, at.y))


## Run a trolley's physics until it comes to rest, or give up.
func _roll_until_still(piece: Trolley, frames := 600) -> int:
	for i in frames:
		if not piece.is_physics_processing():
			return i
		piece._physics_process(1.0 / 60.0)
	return frames


## Push from where the piece stands to `delta` further on, over `frames` frames.
func _push(piece: Trolley, hand: FakeHand, delta: Vector2, frames := 40) -> void:
	var start := Vector2(piece.position.x, piece.position.z)
	_hand_over(hand, start)
	piece.grab_begin(hand, Vector3(start.x, 0.2, start.y))
	for i in frames:
		_hand_over(hand, start + delta * float(i + 1) / float(frames))
		piece.grab_move(hand, Vector3.ZERO)
		piece._physics_process(1.0 / 60.0)
	piece.grab_end(hand)


func _test_furniture_rolls_where_it_is_pushed() -> void:
	var rig := _floor_studio()
	var studio: Studio = rig["studio"]
	var hand: FakeHand = rig["hand"]
	var piece := studio.rack_trolley
	check("the rack stands on a trolley", piece != null and piece.casters().size() == 4)
	var from := Vector2(piece.position.x, piece.position.z)
	var rack_from := studio.rack.position
	var headings := piece.casters().map(func(c): return c.heading())
	var wheel: Node3D = piece.casters()[0].get_node("Swivel/Wheel")
	var spin_from := wheel.transform.basis

	var delta := Vector2(-0.30, 0.45)
	_hand_over(hand, from)
	piece.grab_begin(hand, Vector3(from.x, 0.2, from.y))
	_hand_over(hand, from + delta)
	piece.grab_move(hand, Vector3.ZERO)
	piece._physics_process(1.0 / 60.0)
	var first := (Vector2(piece.position.x, piece.position.z) - from).length()
	# Something with mass accelerates; something dragged by the cursor is simply there. A frame
	# in, a rack is under two centimetres along a fifty-four centimetre shove -- the speed limit
	# alone would let an instant follow cover over four.
	check("a rack starts from rest (%.1fmm in the first frame)" % [first * 1000.0],
			first > 0.0005 and first < 0.02)
	for i in 2:
		piece._physics_process(1.0 / 60.0)
	var early := Vector2(piece.position.x, piece.position.z) - from
	# Heavy: three frames after a 54cm shove it has started and is nowhere near there.
	check("a rack gets going a beat after the push (%.0f%% of the way after 3 frames)"
			% [early.length() / delta.length() * 100.0],
			early.length() > 0.001 and early.length() < delta.length() * 0.5)
	piece.grab_end(hand)
	var frames := _roll_until_still(piece)
	check("and comes to rest by itself (%d frames)" % frames, frames < 600)

	var went := Vector2(piece.position.x, piece.position.z) - from
	check("it ends up where it was pushed (%.1fmm off)" % [(went - delta).length() * 1000.0],
			(went - delta).length() < 0.01)
	check("standing on the floor still", is_zero_approx(piece.position.y))
	var rack_went := studio.rack.position - rack_from
	check("the rack rides on it (%.1fmm off)"
			% [(Vector2(rack_went.x, rack_went.z) - went).length() * 1000.0],
			(Vector2(rack_went.x, rack_went.z) - went).length() < 0.001
					and is_zero_approx(rack_went.y))
	var turned := 0
	for i in piece.casters().size():
		if absf(piece.casters()[i].heading() - headings[i]) > 0.1:
			turned += 1
	check("the casters swung round to trail the push (%d of 4)" % turned, turned == 4)
	check("and the wheels turned", not wheel.transform.basis.is_equal_approx(spin_from))

	check("where it went is remembered",
			Session.layout.has_transform(&"floor/rack", Presentation.Mode.STUDIO))
	# Not saved separately: the rack's place is its plinth's, so remembering the plinth is
	# remembering the rack.
	check("and so is where the rack went with it",
			studio.mount.studio_home(&"rack").is_equal_approx(studio.rack.transform))

	# The cable out of the back follows. Its floor point is written against the authored stand.
	studio.refresh_looms()
	var loom: GearLoom = null
	for node in studio.studio_set.get_children():
		if node is GearLoom and not node.is_queued_for_deletion() \
				and (node as GearLoom).variation_seed == hash("rack"):
			loom = node
	var via: Vector3 = Studio.LOOM_RUNS[1][4]
	check("the rack's loom found", loom != null)
	if loom != null:
		# Moved AND turned with it: a push that leaves the plinth a fraction of a degree round
		# swings a floor point half a metre away by a millimetre.
		var authored: Transform3D = studio._authored_floor[&"rack"]
		var want := piece.transform * authored.affine_inverse() * via
		var off := Vector2(loom.via.x - want.x, loom.via.z - want.z).length()
		check("its run across the floor moved with the rack (%.1fmm off, pushed %.0fmm)"
				% [off * 1000.0, went.length() * 1000.0], off < 0.001 and went.length() > 0.05)
	_drop_floor_studio(rig)


func _test_furniture_is_solid() -> void:
	var rig := _floor_studio()
	var studio: Studio = rig["studio"]
	var hand: FakeHand = rig["hand"]
	var piece := studio.rack_trolley
	var desk: Array = studio._desk_footprint()
	check("the desk is on the floor plan", desk.size() == 1)

	# Straight at the console, hard, and well past where it stands.
	var at := Vector2(piece.position.x, piece.position.z)
	_push(piece, hand, Vector2(0.2, 0.5) - at)
	_roll_until_still(piece)
	var mine := piece.footprint_at(Vector2(piece.position.x, piece.position.z), piece.rotation.y)
	check("a rack pushed into the console stops at it", desk.size() == 1 and \
			FloorPlan.separation(mine, desk[0]).length() < 0.002)
	var travelled := Vector2(piece.position.x, piece.position.z) - at
	check("having got as far as it could (%.0fcm)" % [travelled.length() * 100.0],
			travelled.length() > 0.3)

	# And into the wall.
	_push(piece, hand, Vector2(-6.0, 0.0))
	_roll_until_still(piece)
	var reach := FloorPlan._reach(piece.footprint_at(
			Vector2(piece.position.x, piece.position.z), piece.rotation.y))
	var c: Vector2 = piece.footprint_at(Vector2(piece.position.x, piece.position.z),
			piece.rotation.y)["c"]
	check("and one pushed at the wall stays in the room (%.3f)" % (c.x - reach.x),
			c.x - reach.x >= studio.floor_plan.bounds.position.x - 0.001)

	# Into another trolley.
	var deck := studio.deck_trolley
	var deck_at := Vector2(deck.position.x, deck.position.z)
	var rack_at := Vector2(piece.position.x, piece.position.z)
	_push(piece, hand, deck_at - rack_at)
	_roll_until_still(piece)
	var overlap := FloorPlan.separation(
			piece.footprint_at(Vector2(piece.position.x, piece.position.z), piece.rotation.y),
			deck.footprint_at(deck_at, deck.rotation.y))
	check("and two trolleys do not pass through each other", overlap.length() < 0.002)
	_drop_floor_studio(rig)


func _test_the_wheel_turns_furniture_only_while_held() -> void:
	var rig := _floor_studio()
	var studio: Studio = rig["studio"]
	var hand: FakeHand = rig["hand"]
	var piece := studio.deck_trolley
	var heading := piece.rotation.y
	check("over a trolley, the wheel still zooms", not piece.nudge(hand, 1, false))
	var at := Vector2(piece.position.x, piece.position.z)
	_hand_over(hand, at)
	piece.grab_begin(hand, Vector3(at.x, 0.4, at.y))
	check("holding it, the wheel turns it", piece.nudge(hand, 2, false))
	check("and shift turns it finely", piece.nudge(hand, -1, true))
	piece.grab_end(hand)
	_roll_until_still(piece)
	var turned := rad_to_deg(wrapf(piece.rotation.y - heading, -PI, PI))
	check("two notches and one fine notch back is 27 degrees (%.2f)" % turned,
			absf(turned - 27.0) < 0.05)
	var deck_turned := rad_to_deg(wrapf(studio.deck.rotation.y - deg_to_rad(-32.0), -PI, PI))
	check("and the tape machine turned with its cart (%.2f)" % deck_turned,
			absf(deck_turned - 27.0) < 0.05)
	_drop_floor_studio(rig)


func _test_a_summoned_surface_goes_home_to_where_its_stand_went() -> void:
	var rig := _floor_studio()
	var studio: Studio = rig["studio"]
	var hand: FakeHand = rig["hand"]
	var piece := studio.rack_trolley
	var offset := piece.transform.affine_inverse() * studio.rack.transform
	# Summoning, which a monitor no longer does by default; this is about the stand moving
	# while its gear is away, so the gear has to be away.
	studio.focus.visits = false
	studio.focus.focus(&"rack")
	check("the rack is away being worked on", studio.focus.holds(&"rack"))
	_push(piece, hand, Vector2(0.0, 0.6))
	_roll_until_still(piece)
	check("its stand stayed in the room", piece.get_parent() == studio.studio_set)
	studio.focus.release()
	var expected := piece.transform * offset
	check("released, the rack goes back onto its stand where the stand now is (%.1fmm off)"
			% [(studio.rack.transform.origin - expected.origin).length() * 1000.0],
			studio.rack.transform.is_equal_approx(expected))
	_drop_floor_studio(rig)


## On a monitor, focus walks you to the gear. Everything about the room stays as it was
## arranged; only the mix position, its light and the camera move.
func _test_a_monitor_goes_to_the_gear_and_leaves_the_room_alone() -> void:
	var rig := _floor_studio()
	var studio: Studio = rig["studio"]
	var hand: FakeHand = rig["hand"]
	check("a monitor visits by default", studio.focus.visits)
	var before := {}
	for surface in studio.focus.surfaces:
		before[surface.surface_id] = [surface.get_parent(), surface.global_transform]
	var home_seat := studio.body.global_transform

	var rack_seat := func() -> Array:
		var cam := studio.camera.global_transform
		var box := studio.rack.global_transform * studio.rack.content_aabb()
		var centre := box.get_center()
		var off := rad_to_deg((-cam.basis.z).angle_to(centre - cam.origin))
		var inside := 0
		for i in 8:
			if studio.camera.is_position_in_frustum(box.get_endpoint(i)):
				inside += 1
		return [off, inside, cam.origin.distance_to(centre)]

	studio.focus.focus(&"rack")
	var moved := 0
	for surface in studio.focus.surfaces:
		var was: Array = before[surface.surface_id]
		# A surface on the monitor rides the camera, so it goes wherever you go. That is the
		# monitor moving, not the gear.
		if was[0] == studio.screen_stage:
			continue
		if surface.get_parent() != was[0] or not surface.global_transform.is_equal_approx(was[1]):
			moved += 1
	check("focusing the rack moves no gear (%d moved)" % moved, moved == 0)
	var hidden := studio.studio_set.find_children("*", "Node3D", true, false).filter(
			func(n): return n.is_in_group(&"room_furniture") and not n.visible)
	check("and hides no furniture (%d)" % hidden.size(), hidden.is_empty())
	# Gear rebuilds whenever Reaper changes shape under it, and the rebuild handler is shared
	# with summoning. It used to summon: every visit render was really a summoned rack.
	studio.rack.rebuilt.emit()
	check("a rebuild while visiting still leaves the rack on its stand",
			studio.rack.get_parent() == before[&"rack"][0]
			and studio.rack.global_transform.is_equal_approx(before[&"rack"][1]))
	check("the monitor's own panels step out from in front of it",
			not studio.screen_stage.visible
			and studio.screen_stage.process_mode == Node.PROCESS_MODE_DISABLED)
	check("the mix position walked over to it",
			studio.body.global_position.distance_to(home_seat.origin) > 0.3)
	var seen: Array = rack_seat.call()
	check("the camera looks straight at the rack (%.1f degrees off)" % seen[0], seen[0] < 3.0)
	check("all of it is in frame (%d of 8 corners)" % seen[1], seen[1] == 8)
	var lamp := studio.body.find_children("*", "OmniLight3D", true, false)
	var reach := 0.0
	if not lamp.is_empty():
		reach = (lamp[0] as Node3D).global_position.distance_to(
				studio.rack.global_transform * studio.rack.content_aabb().get_center()) \
				/ (lamp[0] as OmniLight3D).omni_range
	# Well inside its range, where inverse-square still has something to give. At the mix
	# position the rack is over two metres from it, at the far end of its reach.
	check("and the work light came along (%.0f%% of its range away)" % [reach * 100.0],
			not lamp.is_empty() and reach < 0.75)

	# Rearrange the room and go back: the seat is wherever the rack now is.
	studio.focus.release()
	check("released, you are back at the mix position",
			studio.body.global_transform.is_equal_approx(home_seat))
	check("and the monitor's panels are back", studio.screen_stage.visible
			and studio.screen_stage.process_mode == Node.PROCESS_MODE_INHERIT)
	var piece := studio.rack_trolley
	_push(piece, hand, Vector2(0.5, 0.35))
	_roll_until_still(piece)
	studio.focus.focus(&"rack")
	seen = rack_seat.call()
	check("a rack wheeled somewhere else is visited where it went (%.1f degrees off)" % seen[0],
			seen[0] < 3.0 and seen[1] == 8)

	# And bringing is one key away.
	studio._toggle_summoning()
	check("G brings the gear instead", not studio.focus.visits and studio.focus.holds(&"rack"))
	studio._toggle_summoning()
	check("and G again goes back to visiting", studio.focus.visits and not studio.focus.holds(&"rack")
			and studio.rack.get_parent() == studio.studio_set)
	_drop_floor_studio(rig)


## Two visible faces in one plane, facing one way, are drawn in whichever order the depth
## buffer's rounding picks that frame -- the crawling edges people call z-fighting. It hides in
## stills and shows the moment the camera moves, so this searches for it instead of looking.
## The first run found 424 such pairs, the worst being the top edge of every console strip.
func _test_no_two_faces_in_the_room_share_a_plane() -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	# Everything in the room at once, so every pairing that can happen does.
	for id in [&"console", &"timeline", &"patchbay", &"rack", &"tape_deck"]:
		Session.layout.set_mode(id, Presentation.Mode.STUDIO)
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	# In every venue: the gear is the same, but the floor it stands on is not.
	for id in Venue.IDS:
		studio.set_venue(id, false)
		var hits := ZFightProbe.scan(studio)
		var named := hits.slice(0, 3).map(func(h): return "%s | %s" % [
				ZFightProbe.label(h[0]), ZFightProbe.label(h[1])])
		check("no two faces in the %s share a plane (%d: %s)" % [id, hits.size(),
				", ".join(named)], hits.is_empty())
	Session.layout = saved_layout
	remove_child(studio)
	studio.free()


## A venue is scenery. Changing it must leave every piece of gear where it was, every stand and
## lamp standing, and the choice remembered for next time; and each one must give you a floor,
## because gear standing on nothing is the one thing no venue may look like.
func _test_venues_change_the_world_and_not_the_setup() -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	check("a new layout stands in the studio", studio.venue.venue_id() == &"studio")

	var poses := {}
	for surface in studio.focus.surfaces:
		poses[surface.surface_id] = surface.global_transform
	var others := studio.get_child_count()
	var lamps := studio._lamps.size()

	var seen: Array[StringName] = []
	var id := studio.venue.venue_id()
	for step in Venue.IDS.size():
		var old := studio.venue
		studio.cycle_venue()
		id = studio.venue.venue_id()
		seen.append(id)
		check("%s: the old venue leaves the room" % id, not old.is_inside_tree())
		check("%s: one venue at a time" % id,
				studio.find_children("Venue*", "Venue", false, false).size() == 1)
		check("%s: nothing else in the studio is added or lost" % id,
				studio.get_child_count() == others)
		check("%s: every lamp is still standing" % id, studio._lamps.size() == lamps)
		check("%s: the lamps shine what the venue says" % id,
				studio._lamps[0].light_color == studio.venue.lamp_colour(0, Studio.PRACTICALS[0][1]))
		var moved := []
		for surface in studio.focus.surfaces:
			if not surface.global_transform.is_equal_approx(poses[surface.surface_id]):
				moved.append(surface.surface_id)
		check("%s: no gear moves (%s)" % [id, moved], moved.is_empty())
		var floor_found := false
		for child in studio.venue.get_children():
			if child is MeshInstance3D and child.mesh is PlaneMesh \
					and absf(child.global_position.y) < 0.001 and child.mesh.size.x >= Studio.ROOM_WIDTH:
				floor_found = true
		check("%s: there is a floor under the gear" % id, floor_found)
		check("%s: the choice is remembered" % id, Session.layout.venue == id)
		studio.venue.pulse(0.8)
		studio.venue.pulse(0.0)
	check("cycling visits every venue and comes home", seen.size() == Venue.IDS.size()
			and seen[seen.size() - 1] == Venue.IDS[0] and Venue.IDS.all(func(v): return seen.has(v)))

	studio.set_venue(&"nowhere")
	check("an unknown venue is the studio", studio.venue.venue_id() == &"studio")
	studio.set_venue(&"grid")
	studio.set_venue(&"chalk", false)
	check("a venue for one run is not written down", Session.layout.venue == &"grid")

	Session.layout.save()
	var reloaded := LayoutProfile.new()
	reloaded.save_path = Session.layout.save_path
	reloaded.load_saved()
	check("the venue survives a restart", reloaded.venue == &"grid")
	remove_child(studio)
	studio.free()

	var again := Studio.new()
	again.medium = Presentation.Medium.SCREEN
	add_child(again)
	check("a saved venue is where the next session starts", again.venue.venue_id() == &"grid")
	remove_child(again)
	again.free()
	Session.layout = saved_layout


## The activities coming later -- the brick editor, the matrix, the kit, the booth, the synth --
## each need a place in every venue, sized for what will stand there and clear of the gear. A
## venue that forgets one, or puts one through the rack, fails here before anyone builds the
## activity and finds out.
func _test_every_venue_leaves_room_for_the_activities() -> void:
	# The least each needs, along its short side, its long side, and up (docs/environments_loop.md).
	var needs := {
		&"bricks": Vector3(1.0, 2.0, 0.9),
		&"matrix": Vector3(3.0, 3.0, 3.0),
		&"drums": Vector3(2.5, 2.5, 2.0),
		&"vocals": Vector3(2.0, 2.0, 2.0),
		&"synth": Vector3(0.6, 1.5, 1.2),
	}
	for width in [Studio.ROOM_WIDTH, Studio.ROOM_WIDTH + 3.2]:
		for id in Venue.IDS:
			var venue := Venue.make(id)
			venue.room_width = width
			add_child(venue)
			var tag := "%s at %.1f m" % [id, width]
			var zones := venue.zones()
			check("%s: has every activity's zone" % tag, zones.size() == Venue.ZONE_IDS.size()
					and Venue.ZONE_IDS.all(func(z): return zones.has(z)))
			var corners := venue.footprint_corners()
			var footprint := Rect2(corners[0], Vector2.ZERO)
			for c in corners:
				footprint = footprint.expand(c)
			for zone_id: StringName in zones:
				var box: AABB = zones[zone_id]
				var plan := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
				check("%s: %s clears the gear's footprint" % [tag, zone_id], not plan.intersects(footprint))
				var need: Vector3 = needs[zone_id]
				var floor := [minf(box.size.x, box.size.z), maxf(box.size.x, box.size.z)]
				check("%s: %s is big enough" % [tag, zone_id], floor[0] >= need.x and floor[1] >= need.y
						and box.size.y >= need.z)
				for other_id: StringName in zones:
					if other_id != zone_id:
						var other: AABB = zones[other_id]
						check("%s: %s and %s do not overlap" % [tag, zone_id, other_id],
								not Rect2(other.position.x, other.position.z, other.size.x, other.size.z)
								.intersects(plan))
				var dressing := venue.get_node_or_null("Zone_" + String(zone_id)) as Node3D
				check("%s: %s is dressed" % [tag, zone_id], dressing != null
						and dressing.get_child_count() > 0)
				if dressing != null:
					check("%s: %s's dressing stands in its zone" % [tag, zone_id],
							plan.has_point(Vector2(dressing.position.x, dressing.position.z)))
				if id == &"studio":
					check("%s: %s is inside the live room" % [tag, zone_id],
							absf(box.position.x) <= venue.live_room_half()
							and absf(box.end.x) <= venue.live_room_half()
							and box.end.z <= Venue.LIVE_ROOM_BACK and box.end.y <= Venue.LIVE_ROOM_HEIGHT)
			if id == &"chalk":
				var in_the_way := 0
				for doodle in venue.find_children("Doodle", "Node3D", false, false):
					for box: AABB in zones.values():
						if box.has_point((doodle as Node3D).position):
							in_the_way += 1
				check("%s: no doodle hangs in an activity's space" % tag, in_the_way == 0)
			remove_child(venue)
			venue.free()


## The timeline once stood a metre from its stand, square to the room while the stand was at
## forty-five degrees, because each saved its own place and several paths moved only one. A
## surface on a stand now has no place but the stand's. Every way of moving either is tried.
func _test_gear_never_leaves_its_stand() -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	for id in [&"timeline", &"tape_deck", &"rack"]:
		Session.layout.set_mode(id, Presentation.Mode.STUDIO)
	# The drift as it was found in a real profile: a timeline saved square and far from home.
	Session.layout.set_transform(&"timeline", Presentation.Mode.STUDIO,
			Transform3D(Basis.IDENTITY, Vector3(-0.09, 1.62, -2.31)))
	Session.layout.set_transform(&"floor/timeline_stand", Presentation.Mode.STUDIO,
			Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)), Vector3(-0.9, 0, -1.63)))
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)

	var on_stand := func(surface: Surface, piece: Trolley) -> bool:
		var seat: Transform3D = studio._seated_on[surface.surface_id][1]
		return (piece.transform * seat).is_equal_approx(surface.transform)
	check("a drifted saved placement is ignored: the timeline is on its stand",
			on_stand.call(studio.timeline, studio.timeline_stand))
	check("and the drift is gone from the profile", not Session.layout.has_transform(
			&"timeline", Presentation.Mode.STUDIO))
	check("the deck is on its trolley", on_stand.call(studio.deck, studio.deck_trolley))
	check("the rack is on its plinth", on_stand.call(studio.rack, studio.rack_trolley))

	studio.deck_trolley.place(Vector2(1.6, 0.9), deg_to_rad(-70.0))
	check("rolling the trolley carries the deck", on_stand.call(studio.deck, studio.deck_trolley))

	studio.mount.reset_placement(&"tape_deck")
	check("RESET leaves the deck on its trolley, wherever that is",
			on_stand.call(studio.deck, studio.deck_trolley))

	var before := studio.timeline_stand.position
	studio.timeline.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-20.0)),
			studio.timeline.transform.origin + Vector3(0.6, 0.0, 0.5))
	studio.mount.remember_placement(&"timeline")
	check("dropping the timeline by its handle rolls the stand to it",
			studio.timeline_stand.position.distance_to(before) > 0.3)
	check("and the timeline is back on the stand", on_stand.call(studio.timeline, studio.timeline_stand))

	remove_child(studio)
	studio.free()
	Session.layout = saved_layout


## Found against a live Reaper: a 40-track session in a 64-wide OSC bank arrived as 64 tracks,
## the last 24 named "Track 41".."Track 64" with faders at -inf, and every track carried sixteen
## plugin slots because Reaper reports the empty ones too, with empty names.
func _test_a_bank_wider_than_the_project_draws_only_the_project() -> void:
	var state := MixState.new()
	MixWire.apply(state, "/track/39/name", ["Room Rtn"])
	MixWire.apply(state, "/track/41/name", ["Track 41"])
	MixWire.apply(state, "/track/41/volume", [0.003])
	check("before the project's size is known, every slot is admitted", state.tracks.has(41))
	MixWire.apply(state, "/project/tracks", [40])
	check("once it is, slots past the end are dropped", not state.tracks.has(41) and state.tracks.has(39))
	MixWire.apply(state, "/track/44/name", ["Track 44"])
	check("and later ones are not admitted", not state.tracks.has(44))
	MixWire.apply(state, "/track/39/fx/1/name", ["VST: ReaVerbate (Cockos)"])
	MixWire.apply(state, "/track/39/fx/2/name", [""])
	MixWire.apply(state, "/track/39/fx/3/name", [""])
	check("empty plugin slots are not plugins", state.track(39).plugins() == [1])
	state.set_bank(64)
	MixWire.apply(state, "/track/1/name", ["Track 65"])
	check("past the end on a later bank too", not state.tracks.has(1))


## Seated where the walk starts -- the mix position -- turn to face each control in the room in
## turn and click its middle. The click must land on THAT control: not on a neighbour standing
## proud of it, not on a panel in front of it, not on nothing. And the target must be big enough
## on a 1600x900 monitor to hit without aiming twice. This is the goal's "every control can be
## clicked from the seat without a misclick", as a search rather than a tour with a mouse.
const SEAT_MIN_PIXELS := 7.0


func _test_every_control_is_clickable_from_the_seat() -> void:
	for tracks in [13, 40]:
		await _seat_audit(tracks)


func _seat_audit(tracks: int) -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	var backend := OfflineBackend.new()
	backend.track_count = tracks
	DAW.use(backend)
	# A monitor's shape, not the headless window's: screen framing is computed from the aspect,
	# and audited through a 64px square it describes a layout no one sees.
	var monitor := SubViewport.new()
	monitor.size = Vector2i(1600, 900)
	add_child(monitor)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	monitor.add_child(studio)
	for i in 3:
		for surface in studio.focus.surfaces:
			surface._process(0.0)
		await get_tree().physics_frame
	for i in 4:
		await get_tree().process_frame
	await get_tree().physics_frame
	var hand: Interactor = studio.get_node("MouseHand")
	var eye := studio.camera.global_position
	var px_per_rad := 900.0 / deg_to_rad(studio.camera.fov)

	var controls: Array = []
	var stack: Array = [studio]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is ControlAffordance and n.is_visible_in_tree() and (n.collision_layer & 2) != 0:
			controls.append(n)
		stack.append_array(n.get_children())

	var missed: Array = []
	var small: Array = []
	var smallest := INF
	for c: ControlAffordance in controls:
		var shape: CollisionShape3D = null
		for child in c.get_children():
			if child is CollisionShape3D:
				shape = child
				break
		if shape == null or shape.disabled:
			continue
		var centre := shape.global_position
		var to := centre - eye
		var box := shape.shape as BoxShape3D
		var hit: Dictionary = hand._cast(eye, to.normalized())
		if hit["control"] != c and box != null:
			# Its middle is covered -- a stand's middle is under what it carries. It still has
			# to be reachable, so: does a third of its face answer to a click?
			var answered := 0
			for gx in 5:
				for gy in 5:
					var at := shape.global_transform * Vector3(
							(gx / 4.0 - 0.5) * 0.8 * box.size.x, (gy / 4.0 - 0.5) * 0.8 * box.size.y, 0)
					if hand._cast(eye, (at - eye).normalized())["control"] == c:
						answered += 1
			if answered * 3 >= 25:
				hit = {"control": c, "point": centre}
		if hit["control"] != c:
			var other: Node = hit["control"]
			missed.append("%s (got %s at %.2fm, wanted %.2fm)" % [_who(c), _who(other) if other != null else "nothing",
					(hit["point"] - eye).length(), to.length()])
			continue
		if box == null:
			continue
		# The face's smaller side, through the shape's scale, at that distance.
		var basis := shape.global_transform.basis
		var w := (basis.x * box.size.x).length()
		var h := (basis.y * box.size.y).length()
		var pixels := minf(w, h) / to.length() * px_per_rad
		smallest = minf(smallest, pixels)
		if pixels < SEAT_MIN_PIXELS:
			small.append("%s %.1fpx" % [_who(c), pixels])

	check("%d tracks: from the seat, a click on each of %d controls lands on it (%d miss: %s)" % [
			tracks, controls.size(), missed.size(), ", ".join(missed.slice(0, 8))], missed.is_empty())
	check("%d tracks: and each is at least %.0fpx to aim at (smallest %.1fpx; %d under: %s)" % [
			tracks, SEAT_MIN_PIXELS, smallest, small.size(), ", ".join(small.slice(0, 8))], small.is_empty())
	monitor.queue_free()
	await get_tree().process_frame
	Session.layout = saved_layout


func _who(n: Node) -> String:
	if n == null:
		return "?"
	var label := ""
	if n is ControlAffordance:
		label = n.title()
	var parent := n.get_parent()
	var trail := "%s/%s" % [parent.name if parent else "", n.name]
	return "%s[%s]" % [label, trail] if label != "" else trail


func _test_you_walk_into_the_room_and_not_through_it() -> void:
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	var walker := studio.walker
	check("a monitor puts you on foot by default", walker != null and not studio.god_mode)
	if walker == null:
		studio.queue_free()
		return
	walker.sync_solids()
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Drop from a height: gravity brings you to the floor and the floor holds you there.
	walker.global_position = Vector3(1.5, 0.6, 1.6)
	for i in 90:
		walker.step(1.0 / 60.0, Vector3.ZERO)
	check("you fall to the floor and stand on it (y %.3f)" % walker.global_position.y,
			absf(walker.global_position.y) < 0.05 and walker.is_on_floor())
	close_to("and the camera is at your eyes", studio.camera.global_position.y,
			walker.global_position.y + walker.eye_height, 0.05)

	# Walk straight at the desk from in front of it. The desk stops you.
	var desk: Array = studio._desk_footprint()
	check("the desk has a footprint to walk into", desk.size() == 1)
	if desk.size() == 1:
		var f: Dictionary = desk[0]
		var c: Vector2 = f["c"]
		var half: Vector2 = f["h"]
		walker.global_position = Vector3(c.x, 0, c.y + half.y + 0.8)
		walker.velocity = Vector3.ZERO
		for i in 240:
			walker.step(1.0 / 60.0, Vector3(0, 0, -Walker.WALK_SPEED))
		var front := c.y + half.y
		check("walking into the desk stops at its front edge (z %.2f, desk front %.2f)" % [
				walker.global_position.z, front],
				walker.global_position.z > front + Walker.RADIUS - 0.05)
		check("and you did get there", walker.global_position.z < front + Walker.RADIUS + 0.1)

	# The walls hold too.
	var b := studio.floor_plan.bounds
	walker.global_position = Vector3(0, 0, b.end.y - 0.6)
	walker.velocity = Vector3.ZERO
	for i in 240:
		walker.step(1.0 / 60.0, Vector3(0, 0, Walker.SPRINT_SPEED))
	check("the back wall stops you inside the room (z %.2f, wall %.2f)" % [
			walker.global_position.z, b.end.y], walker.global_position.z < b.end.y)

	# Momentum: letting go does not stop you dead, but friction does stop you.
	walker.global_position = Vector3(0, 0, 1.6)
	walker.velocity = Vector3.ZERO
	for i in 60:
		walker.step(1.0 / 60.0, Vector3(Walker.WALK_SPEED, 0, 0))
	var start_x := walker.global_position.x
	walker.step(1.0 / 60.0, Vector3.ZERO)
	check("letting go carries you on a little", walker.global_position.x > start_x)
	for i in 60:
		walker.step(1.0 / 60.0, Vector3.ZERO)
	check("and friction brings you to rest", walker.velocity.length() < 0.01)

	# Jumping leaves the floor and comes back to it.
	for i in 2:
		walker.step(1.0 / 60.0, Vector3.ZERO)
	walker.step(1.0 / 60.0, Vector3.ZERO, true)
	var peak := 0.0
	for i in 120:
		walker.step(1.0 / 60.0, Vector3.ZERO, false)
		peak = maxf(peak, walker.global_position.y)
	check("space jumps (peak %.2f m)" % peak, peak > 0.3)
	check("and you land", absf(walker.global_position.y) < 0.05)

	# God mode takes the view where you were, and hands it back.
	var eye := walker.eye()
	studio.set_god_mode(true)
	check("N leaves your body", studio.god_mode and not walker.active)
	check("and the orbit starts from your eyes (%.2f m off)" % studio.camera.global_position.distance_to(eye),
			studio.camera.global_position.distance_to(eye) < 0.05)
	studio.frame(Vector3(1.0, 0.9, -1.0), 2.0, 0.6, -0.3)
	check("god mode flies the camera off the floor plan's rules",
			studio.camera.global_position.distance_to(walker.eye()) > 0.5)
	studio.set_god_mode(false)
	check("and N comes back down, inside the room",
			studio.floor_plan.bounds.has_point(Vector2(walker.global_position.x, walker.global_position.z)))

	# A visit walks you to the seat.
	studio.focus.focus(&"rack")
	for surface in studio.focus.surfaces:
		surface._process(0.0)
	studio._sit_down()
	for i in 60:
		await get_tree().process_frame
	var seat := studio.body.global_position
	check("visiting walks you to the seat (%.2f m off)" % walker.eye().distance_to(seat),
			walker.eye().distance_to(seat) < 0.15)
	check("and the solids are not on the control layer",
			walker._solid_body.collision_layer & (1 << (Interactor.CONTROL_LAYER - 1)) == 0)
	studio.queue_free()


func _test_the_room_is_laid_out_for_the_size_of_the_session() -> void:
	# The rule on its own: the authored room is what a thirteen-track desk gets.
	var small := SessionLayout.fit(0.461)
	close_to("a small desk keeps the authored room width", small["room_width"], SessionLayout.BASE_WIDTH)
	check("and the rack where it was authored", (small["rack"][0] as Vector2).distance_to(SessionLayout.RACK_AT) < 0.01)
	check("and the deck", (small["deck_trolley"][0] as Vector2).distance_to(SessionLayout.DECK_AT) < 0.01)
	var huge := SessionLayout.fit(3.0)
	check("a six-metre desk gets a wider room (%.1f m)" % huge["room_width"],
			huge["room_width"] > 6.0 + SessionLayout.RACK_GAP * 2.0)
	check("in whole steps", is_equal_approx(fmod(huge["room_width"] - SessionLayout.BASE_WIDTH,
			SessionLayout.WIDTH_STEP), 0.0) or is_equal_approx(fmod(huge["room_width"]
			- SessionLayout.BASE_WIDTH, SessionLayout.WIDTH_STEP), SessionLayout.WIDTH_STEP))

	var saved_path := Session.layout.save_path
	for tracks in [13, 40, 64]:
		var backend := OfflineBackend.new()
		backend.state = MixState.new()
		backend.track_count = tracks
		DAW.use(backend)
		var room := Studio.new()
		room.medium = Presentation.Medium.SCREEN
		add_child(room)
		for node in room.find_children("*", "Node3D", true, false):
			if node is Surface:
				(node as Surface)._process(0.0)
		var desk: Dictionary = room._desk_footprint()[0]
		var bounds := room.floor_plan.bounds
		var lost: Array = []
		for piece in room.floor_plan.pieces:
			var at := Vector2(piece.position.x, piece.position.z)
			if not room.floor_plan.is_clear(piece, at, piece.rotation.y):
				lost.append(piece.piece_id)
		check("%d tracks: nothing on the floor overlaps the desk or anything else %s" % [tracks, lost],
				lost.is_empty())
		var desk_ends := (desk["h"] as Vector2).x
		check("%d tracks: the room is wider than the desk with the rack and deck beside it (%.1f m for a %.1f m desk)" % [
				tracks, room.room_width, desk_ends * 2.0], bounds.size.x > desk_ends * 2.0 + 1.0)
		close_to("%d tracks: the venue was drawn to the same width" % tracks, room.venue.room_width, room.room_width)
		var cabinet_top := room._patch_cabinet.position.y + (room._patch_cabinet.mesh as BoxMesh).size.y * 0.5
		var bay_bottom := Studio.PATCH_BAY_TOP - room.patchbay.panel_height()
		check("%d tracks: the patch stand's cabinet comes up to the bay (%.2f under %.2f)" % [
				tracks, cabinet_top, bay_bottom], cabinet_top <= bay_bottom + 0.001
				and cabinet_top > bay_bottom - 0.02 or bay_bottom < 0.2)
		check("%d tracks: and the stand is right of the deck" % tracks,
				room.patch_stand.position.x > room.deck_trolley.position.x)
		check("%d tracks: and the rack still faces the desk from its left" % tracks,
				room.rack_trolley.position.x < -desk_ends)
		check("%d tracks: and the deck from its right" % tracks,
				room.deck_trolley.position.x > desk_ends)
		room.free()
	check("fitting the room wrote nothing to the saved layout",
			not Session.layout.has_transform(&"floor/rack", Presentation.Mode.STUDIO))
	Session.layout.save_path = saved_path


func _offline(tracks := 13) -> OfflineBackend:
	var backend := OfflineBackend.new()
	backend.state = MixState.new()
	backend.track_count = tracks
	DAW.use(backend)
	return backend


func _test_the_transport_is_driven_from_the_desk() -> void:
	var backend := _offline()
	var s := DAW.state
	close_to("bar 1 is zero seconds", s.bar_to_seconds(1.0), 0.0)
	check("bar/beat is spelled from seconds (%s)" % s.bar_beat(s.bar_to_seconds(17.0) + 60.0 / s.tempo),
			s.bar_beat(s.bar_to_seconds(17.0) + 60.0 / s.tempo) == "17.2.00")

	DAW.transport_stop()
	var at := s.position_seconds
	backend._drive_meters(0.5)
	close_to("a stopped transport does not move the playhead", s.position_seconds, at)
	for i in 40:
		backend._drive_meters(0.05)
	check("and the meters fall to nothing (%.3f)" % s.track(1).vu_l, s.track(1).vu_l < 0.001)
	check("the master too", s.master.vu_l < 0.001)

	DAW.seek(s.bar_to_seconds(9.0))
	close_to("seek puts the playhead where it was asked", s.position_seconds, s.bar_to_seconds(9.0))
	check("and the desk's counter says bar 9 (%s)" % s.position_string, s.position_string.begins_with("9.1."))

	DAW.transport_play()
	backend._drive_meters(0.25)
	close_to("play runs the clock", s.position_seconds, s.bar_to_seconds(9.0) + 0.25, 0.001)
	check("and the meters move (%.3f, playing %s, mute %s)" % [s.track(1).vu_l, s.playing, s.track(1).mute], s.track(1).vu_l > 0.0)

	# Solo: what is not soloed is not heard, and does not meter.
	DAW.set_track_solo(2, true)
	for i in 40:
		backend._drive_meters(0.05)
	check("solo silences every other meter (track 1 at %.3f)" % s.track(1).vu_l, s.track(1).vu_l < 0.001)
	check("and the soloed one still moves", s.track(2).vu_l > 0.0)
	DAW.set_track_solo(2, false)

	DAW.set_loop_range(s.bar_to_seconds(5.0), s.bar_to_seconds(7.0))
	DAW.set_looping(true)
	DAW.seek(s.bar_to_seconds(7.0) - 0.1)
	backend._drive_meters(0.3)
	check("a loop wraps the playhead back to its start (at %.2f, loop %.2f-%.2f)" % [
			s.position_seconds, s.loop_start, s.loop_end],
			s.position_seconds >= s.loop_start and s.position_seconds < s.loop_start + 0.5)
	DAW.set_looping(false)
	DAW.seek(s.bar_to_seconds(7.0) - 0.1)
	backend._drive_meters(0.3)
	check("and with looping off it plays straight through", s.position_seconds > s.loop_end)

	# The deck's own keys.
	var deck := TapeDeck.new()
	add_child(deck)
	deck._process(0.0)
	var keys := deck.find_children("*", "PanelButton", true, false)
	var by_title := {}
	for k in keys:
		by_title[(k as PanelButton).title()] = k
	for wanted in ["TRANSPORT  PLAY", "TRANSPORT  STOP", "TRANSPORT  RECORD", "TRANSPORT  LOOP",
			"TRANSPORT  RETURN TO START", "EDIT  UNDO", "EDIT  REDO"]:
		check("the deck has %s" % wanted, by_title.has(wanted))
	if by_title.has("TRANSPORT  LOOP") and by_title.has("TRANSPORT  RETURN TO START"):
		(by_title["TRANSPORT  LOOP"] as PanelButton).pressed.emit()
		check("the deck's loop key turns looping on", s.looping)
		check("and its lamp says so", (by_title["TRANSPORT  LOOP"] as PanelButton).lit)
		check("and the deck shows the range (%s)" % deck._loop_label.text, deck._loop_label.text.begins_with("LOOP 5.1"))
		DAW.seek(s.bar_to_seconds(30.0))
		(by_title["TRANSPORT  RETURN TO START"] as PanelButton).pressed.emit()
		close_to("return-to-start goes to the loop's start while looping", s.position_seconds, s.loop_start)
		(by_title["TRANSPORT  LOOP"] as PanelButton).pressed.emit()
		(by_title["TRANSPORT  RETURN TO START"] as PanelButton).pressed.emit()
		close_to("and to the top of the song when not", s.position_seconds, 0.0)
	(by_title["TRANSPORT  STOP"] as PanelButton).pressed.emit()
	check("stop stops", not s.playing)
	(by_title["TRANSPORT  PLAY"] as PanelButton).pressed.emit()
	check("play plays", s.playing)
	(by_title["TRANSPORT  RECORD"] as PanelButton).pressed.emit()
	check("record records", s.recording)
	check("and the counter on the deck is the bar/beat", deck._counter.text == s.position_string)
	DAW.transport_stop()
	deck.queue_free()


func _test_the_ruler_moves_the_playhead_and_draws_the_loop() -> void:
	_offline()
	var s := DAW.state
	DAW.transport_stop()
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)
	timeline.set_view(0.0, s.bar_to_seconds(33.0))
	var hand := FakeHand.new()
	add_child(hand)
	var seek: TimelineRuler = timeline._seek_strip
	var loop: TimelineRuler = timeline._loop_strip
	var at_bar := func(strip: TimelineRuler, bar: float) -> Vector3:
		var x := timeline._x_for(s.bar_to_seconds(bar))
		return timeline.to_global(Vector3(x, strip.position.y, strip.position.z))

	seek.grab_begin(hand, at_bar.call(seek, 13.0))
	close_to("a click on the ruler puts the playhead on that bar", s.position_seconds, s.bar_to_seconds(13.0), 0.01)
	seek.grab_move(hand, at_bar.call(seek, 21.03))
	close_to("dragging scrubs it, snapped to the beat", s.position_seconds, s.bar_to_seconds(21.0), 0.01)
	seek.grab_end(hand)
	timeline._process(0.0)
	close_to("and the playhead line is drawn there", timeline._playhead.position.x,
			timeline._x_for(s.bar_to_seconds(21.0)), 0.0005)
	check("the ruler reads out the exact position (%s)" % seek.readout(), seek.readout().begins_with("21.1.00"))

	loop.grab_begin(hand, at_bar.call(loop, 9.0))
	loop.grab_move(hand, at_bar.call(loop, 17.0))
	loop.grab_end(hand)
	close_to("dragging the loop band sets the loop start", s.loop_start, s.bar_to_seconds(9.0), 0.01)
	close_to("and its end", s.loop_end, s.bar_to_seconds(17.0), 0.01)
	check("and turns looping on", s.looping)
	timeline._process(0.0)
	var bar := timeline._loop_bar
	check("the loop is drawn on the band", bar.visible)
	close_to("from its start", bar.position.x - bar.scale.x * 0.5, timeline._x_for(s.loop_start), 0.0005)
	close_to("to its end", bar.position.x + bar.scale.x * 0.5, timeline._x_for(s.loop_end), 0.0005)
	loop.grab_begin(hand, at_bar.call(loop, 12.0))
	loop.grab_end(hand)
	check("a click on the band switches looping off", not s.looping)
	close_to("and keeps the range", s.loop_end, s.bar_to_seconds(17.0), 0.01)
	check("the controls are on the control layer", seek.collision_layer == 2 and loop.collision_layer == 2)
	hand.queue_free()
	timeline.queue_free()


func _test_items_are_edited_on_the_timeline() -> void:
	_offline()
	var s := DAW.state
	DAW.transport_stop()
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)
	timeline.set_view(0.0, s.bar_to_seconds(41.0))
	var hand := FakeHand.new()
	add_child(hand)
	var lanes: TimelineLanes = timeline._lanes
	var beat := 60.0 / s.tempo
	var at := func(track_index: int, bar: float) -> Vector3:
		var i := s.track_indices().find(track_index)
		return timeline.to_global(Vector3(timeline._x_for(s.bar_to_seconds(bar)),
				timeline._lane_y[i], lanes.position.z))
	var click := func(point: Vector3) -> void:
		lanes.grab_begin(hand, point)
		lanes.grab_end(hand)

	check("the lanes are on the control layer", lanes.collision_layer == 2)
	check("Kick's first item is Verse 1, bar 9", is_equal_approx(s.item(2, 0).start, s.bar_to_seconds(9.0)))
	click.call(at.call(2, 12.0))
	check("a click selects the item under it", s.item(2, 0).selected)
	hand.holding_shift = true
	click.call(at.call(3, 12.0))
	hand.holding_shift = false
	check("shift adds to the selection", s.item(2, 0).selected and s.item(3, 0).selected)
	click.call(at.call(3, 30.0))
	check("a plain click replaces it", s.item(3, 1).selected and not s.item(2, 0).selected
			and not s.item(3, 0).selected)
	check("selecting is not history (%d)" % s.undo_depth, s.undo_depth <= 0)

	hand.hover_point = at.call(3, 30.0)
	lanes.hover_enter(hand)
	check("hovering an item names it (%s)" % lanes.title(), lanes.title().contains("Chorus 1")
			and lanes.title().contains("SELECTED"))
	check("and reads out exactly where it is (%s)" % lanes.readout(), lanes.readout().begins_with("25.1.00 - 41.1.00"))
	lanes.hover_exit(hand)

	# Move: Kick's Verse 1, grabbed at bar 12 and let go 2.3 bars on, lands on the beat.
	lanes.grab_begin(hand, at.call(2, 12.0))
	lanes.grab_move(hand, at.call(2, 14.3))
	check("while dragging, the block is drawn where it is going", not timeline._preview.is_empty())
	close_to("and the project is not touched until it is let go", s.item(2, 0).start, s.bar_to_seconds(9.0), 0.001)
	lanes.grab_end(hand)
	var moved := s.bar_to_seconds(9.0) + 9.0 * beat
	close_to("let go, it moves, its start snapped to the beat", s.item(2, 0).start, moved, 0.001)
	check("and the drag draws nothing extra afterwards", timeline._preview.is_empty())
	hand.hover_point = at.call(2, 14.3)
	lanes.hover_enter(hand)
	check("let go, the card reads where it landed, not where it was going (%s)" % lanes.readout(),
			not lanes.readout().begins_with("move to"))
	lanes.hover_exit(hand)
	check("the moved item is the selection", s.item(2, 0).selected)
	check("a move is one undo step", s.undo_depth == 1)
	DAW.undo()
	close_to("undo puts it back", s.item(2, 0).start, s.bar_to_seconds(9.0), 0.001)
	DAW.redo()
	close_to("redo moves it again", s.item(2, 0).start, moved, 0.001)
	DAW.undo()

	# Split: the selection, at the playhead.
	click.call(at.call(2, 12.0))
	var count := s.track(2).items.size()
	DAW.seek(s.bar_to_seconds(17.0))
	check("the split key lights when there is something under the playhead to cut", timeline._split_key.lit)
	timeline._split_key.pressed.emit()
	check("split cuts the selected item in two (%d -> %d)" % [count, s.track(2).items.size()],
			s.track(2).items.size() == count + 1)
	close_to("the left half ends at the playhead", s.item(2, 0).end(), s.bar_to_seconds(17.0), 0.001)
	close_to("the right half starts there", s.item(2, 1).start, s.bar_to_seconds(17.0), 0.001)
	close_to("and runs to where the item ended", s.item(2, 1).end(), s.bar_to_seconds(25.0), 0.001)
	check("both halves stay selected", s.item(2, 0).selected and s.item(2, 1).selected)
	check("nothing else was cut", s.track(3).items.size() == 4 or s.track(3).items.size() == 5)
	DAW.undo()
	check("undo joins it again", s.track(2).items.size() == count)
	DAW.seek(s.bar_to_seconds(5.0))
	DAW.split_selected(s.position_seconds)
	check("a split where nothing selected is under the playhead does nothing", s.track(2).items.size() == count)

	# Bare lane: drop the selection, put the playhead there.
	click.call(at.call(13, 21.0))
	check("a click on empty lane drops the selection", s.selected_items().is_empty())
	close_to("and moves the playhead there", s.position_seconds, s.bar_to_seconds(21.0), 0.01)

	# Zoom, round the playhead.
	var span := timeline.view_span
	var x_before := timeline._x_for(s.position_seconds)
	lanes.nudge(hand, 1, false)
	check("the wheel zooms in (%.1fs -> %.1fs)" % [span, timeline.view_span], timeline.view_span < span * 0.85)
	close_to("round the playhead, which stays where it was on the panel",
			timeline._x_for(s.position_seconds), x_before, 0.001)
	lanes.nudge(hand, -3, false)
	check("and out again", timeline.view_span > span)

	# The wire carries the selection, so a guest sees it and Reaper's answer can set it.
	var copy := MixState.new()
	MixWire.apply(copy, "/track/2/items", MixWire._pack_items(s.track(2).items))
	check("selection rides the wire", copy.item(2, 0).selected == s.item(2, 0).selected)
	hand.queue_free()
	timeline.queue_free()


func _test_a_late_timeline_poll_does_not_undo_an_edit() -> void:
	var link := ReaperBackend.new()
	link.state = MixState.new()
	add_child(link)
	var item := MixState.ItemState.new()
	item.start = 10.0
	item.length = 4.0
	link.state.set_track_items(1, [item])
	var asked := link._timeline_epoch
	# The edit is made locally while a poll is out...
	link._timeline_epoch += 1
	link._locally_move(1, 0, 20.0)
	# ...and the poll comes back with the lanes as they were.
	link._on_timeline({"length": 60.0, "markers": [], "tracks": [{"index": 1, "items": [
			{"start": 10.0, "length": 4.0, "muted": false, "name": "", "selected": false}]}]}, asked)
	close_to("an answer to a poll sent before the edit is not laid over it",
			link.state.item(1, 0).start, 20.0, 0.001)
	link._on_timeline({"length": 60.0, "markers": [], "tracks": [{"index": 1, "items": [
			{"start": 20.0, "length": 4.0, "muted": false, "name": "", "selected": true}]}]},
			link._timeline_epoch)
	check("one sent after it is", link.state.item(1, 0).selected)
	link.queue_free()


func _test_the_built_in_engine_is_a_real_mix() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var s := DAW.state
	var bus := func(index: int) -> int: return AudioServer.get_bus_index("%s%d" % [GodotBackend.BUS_PREFIX, index])
	check("opens stopped at the top, not playing music at whoever opened it",
			not s.playing and s.position_seconds == 0.0)
	check("a bus per track", s.track_indices().all(func(i): return bus.call(i) >= 0))
	check("and a master of its own", AudioServer.get_bus_index(GodotBackend.MASTER_BUS) >= 0)
	check("the kick plays through the DRUMS folder",
			AudioServer.get_bus_send(bus.call(2)) == AudioServer.get_bus_name(bus.call(1)))
	check("the last drum is still in the folder", backend.parent_of(5) == 1)
	check("the bass is not", backend.parent_of(6) == 0
			and AudioServer.get_bus_send(bus.call(6)) == GodotBackend.MASTER_BUS)

	DAW.set_track_volume(6, 0.5)
	close_to("a fader is the bus's gain", AudioServer.get_bus_volume_db(bus.call(6)), backend.taper_to_db(0.5), 0.01)
	DAW.set_track_pan(6, 1.0)
	close_to("a pan is the bus's panner", (AudioServer.get_bus_effect(bus.call(6), 0) as AudioEffectPanner).pan, 1.0)
	check("the demo's muted hat is silent", AudioServer.is_bus_mute(bus.call(4)))
	DAW.set_track_solo(3, true)
	check("a solo silences the rest", AudioServer.is_bus_mute(bus.call(6)))
	check("but not the soloed track", not AudioServer.is_bus_mute(bus.call(3)))
	check("nor the folder it plays through", not AudioServer.is_bus_mute(bus.call(1)))
	check("nor the reverb it sends to", not AudioServer.is_bus_mute(bus.call(13)))
	DAW.undo()
	check("undo reaches the speakers too", not AudioServer.is_bus_mute(bus.call(6)))

	check("the kick's rack is Godot's EQ and compressor",
			s.fx(2, 0).name == "EQ6" and s.fx(2, 1).name == "Compressor")
	DAW.set_fx_param(2, 1, 0, 0.0)
	var comp := AudioServer.get_bus_effect(bus.call(2), 2) as AudioEffectCompressor
	close_to("a knob is the effect's parameter", comp.threshold, -60.0, 0.01)
	DAW.read_fx_param_text(2, 1, 0)
	check("read in the effect's own units (%s)" % s.fx(2, 1).param_text.get(0, ""),
			s.fx(2, 1).param_text.get(0, "") == "-60.0 dB")
	DAW.set_fx_enabled(2, 1, false)
	check("bypass is the effect switched off", not AudioServer.is_bus_effect_enabled(bus.call(2), 2))

	check("a send is a second player into the return", backend._players[3].size() == 2
			and AudioServer.get_bus_send(AudioServer.get_bus_index(backend._players[3][1].bus))
				== AudioServer.get_bus_name(bus.call(13)))
	check("there is an item under bar 9 on the kick", backend.item_at(2, s.bar_to_seconds(9.5)) != null)
	check("and none in the intro", backend.item_at(2, s.bar_to_seconds(2.0)) == null)
	check("it is a meter on the fader law", backend.meter(0.0) > 0.7 and backend.meter(-200.0) == 0.0)
	check("the host's guests hear its master bus", backend.mix_source() is GodotBackend.BusSource
			and backend.mix_source().start())

	var resampler := GodotBackend.BusSource.new(backend)
	var made := 0
	var last := Vector2.ZERO
	var smooth := true
	for block in 10:
		var tone := PackedVector2Array()
		for i in 441:
			var v := sin(TAU * 441.0 * (block * 441 + i) / 44100.0)
			tone.append(Vector2(v, v))
		var out := resampler.resample(tone, 44100.0)
		for f in out:
			smooth = smooth and (made == 0 or absf(f.x - last.x) < 0.07)
			last = f
		made += out.size()
	check("a 44.1kHz card is sent at the wire's 48kHz (%d of 4800)" % made, absi(made - 4800) <= 1)
	check("without a seam between blocks", smooth)
	var same := PackedVector2Array([Vector2.ONE, Vector2.ZERO])
	check("and a 48kHz one untouched", resampler.resample(same, 48000.0) == same)

	var p := FXCatalogue.params(&"compressor")[1] as FXCatalogue.Param
	close_to("a log parameter round-trips", p.value_of(p.normalise(4.0)), 4.0, 0.001)
	check("and prints like a ratio", p.text(p.normalise(4.0)) == "4.0:1")

	_offline()
	check("leaving the engine takes its buses with it",
			AudioServer.get_bus_index(GodotBackend.MASTER_BUS) < 0 and bus.call(2) < 0)


func _test_the_demo_song_loops_on_the_bar() -> void:
	check("tracks find their parts by name", DemoSong.role_of("Lead Vox") == "voice"
			and DemoSong.role_of("Kick 2") == "kick" and DemoSong.role_of("Verb Rtn") == "")
	var kick := DemoSong.render("kick", 120.0)
	check("a part is exactly four bars (%d)" % kick.size(), kick.size() == 8 * DemoSong.RATE)
	var top := 0.0
	for v in kick:
		top = maxf(top, absf(v))
	close_to("and normalised", top, 0.8, 0.001)
	var first := 0.0
	for i in 200:
		first = maxf(first, absf(kick[i]))
	check("the kick lands on the one", first > 0.3)
	var wav := DemoSong.to_stream(kick)
	close_to("and loops as a stream of that length", wav.get_length(), 8.0, 0.001)
	check("forever", wav.loop_mode == AudioStreamWAV.LOOP_FORWARD)


func _test_the_tempo_is_set_from_the_deck() -> void:
	var backend := _offline()
	var s := DAW.state
	var before := s.tempo
	backend._repl_durable.clear()
	DAW.set_tempo(96.0)
	close_to("set_tempo sets the tempo", s.tempo, 96.0)
	check("and replicates it as /tempo/raw", backend._repl_durable.has("/tempo/raw"))
	DAW.undo()
	close_to("tempo is undoable", s.tempo, before)
	DAW.set_tempo(5000.0)
	close_to("clamped to Reaper's limit", s.tempo, DAW.TEMPO_MAX)
	DAW.apply_intent(&"set_tempo", [-3.0])
	close_to("a guest's intent is clamped too", s.tempo, DAW.TEMPO_MIN)
	check("set_tempo is a verb a guest may use", &"set_tempo" in DAW.COMMANDS)

	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	add_child(reaper)
	reaper.set_tempo(132.5)
	close_to("Reaper's backend speaks /tempo/raw in BPM", reaper.state.tempo, 132.5)
	reaper.free()

	close_to("knob bottom is the low tempo", TapeDeck.knob_to_bpm(0.0), TapeDeck.TEMPO_LOW)
	close_to("knob round-trips", TapeDeck.knob_to_bpm(TapeDeck.bpm_to_knob(128.0)), 128.0)
	close_to("four taps half a second apart is 120", TapeDeck.tapped_bpm([0, 500, 1000, 1500]), 120.0)
	close_to("one rushed tap moves it a little", TapeDeck.tapped_bpm([0, 500, 1000, 1400]), 128.6, 0.1)
	check("one tap is no tempo", TapeDeck.tapped_bpm([100]) == 0.0)

	_offline()
	var deck := TapeDeck.new()
	add_child(deck)
	deck._process(0.0)
	DAW.set_tempo(100.0)
	close_to("the deck's knob follows the tempo", deck._tempo_knob.value, TapeDeck.bpm_to_knob(100.0))
	check("the knob goes by its name across a session", deck._tempo_knob.network_key() == "TRANSPORT  TEMPO")
	deck._tempo_knob.turned.emit(TapeDeck.bpm_to_knob(150.0))
	close_to("turning it sets the tempo", DAW.state.tempo, 150.0)
	deck.queue_free()


func _test_the_sends_ride_the_faders() -> void:
	var backend := _offline()
	var s := DAW.state
	var verb := 13
	var snare := s.send(3, 1, false)
	check("the stand-in numbers its sends from 1, as the wire does", snare != null and s.send(3, 0, false) == null)
	var before := snare.volume
	backend._repl_durable.clear()
	DAW.set_send_volume(3, 1, 0.5)
	close_to("set_send_volume sets the send's level", snare.volume, 0.5)
	check("and replicates it on the send's own address", backend._repl_durable.has("/track/3/send/1/volume"))
	DAW.set_send_pan(3, 1, 0.2)
	close_to("set_send_pan sets the send's pan", snare.pan, 0.2)
	DAW.undo()
	DAW.undo()
	close_to("a send level is undoable", snare.volume, before)
	DAW.set_send_volume(2, 4, 0.9)
	check("turning a send that is not there does not make one", s.send(2, 4, false) == null)
	check("both are verbs a guest may use", &"set_send_volume" in DAW.COMMANDS and &"set_send_pan" in DAW.COMMANDS)
	DAW.apply_intent(&"set_send_volume", [3, 1, 7.0])
	close_to("a guest's send level is clamped", snare.volume, 1.0)
	DAW.apply_intent(&"set_send_volume", [3, 0, 0.1])
	DAW.apply_intent(&"set_send_volume", [3])
	close_to("a malformed send intent is refused", snare.volume, 1.0)

	# The wire. Reaper spells every send level a second time as text, and that must not be read
	# as the number.
	var told := [0]
	var count := func(_i: int, field: StringName): if field == &"sends": told[0] += 1
	s.track_changed.connect(count)
	MixWire.apply(s, "/track/3/send/1/volume", [0.25])
	MixWire.apply(s, "/track/3/send/1/volume/str", ["-11.0dB"])
	close_to("a send level's text is not its level", snare.volume, 0.25)
	MixWire.apply(s, "/track/3/send/1/volume", [0.25])
	check("a send change is told once, and a restatement not at all (%d)" % told[0], told[0] == 1)
	s.track_changed.disconnect(count)

	# Reaper: ReaScript counts sends from 0 and OSC from 1, and both describe the same send.
	var link := _fresh_link()
	link._apply("/track/4/send/1/name", ["Verb Rtn"])
	link._apply("/track/4/send/1/volume", [0.7])
	link._on_structure({"tracks": [{"index": 4, "sends": [{"index": 0, "dest_track": 26,
			"dest_name": "Verb Rtn"}]}], "track_count": 40})
	check("the bridge's send 0 is OSC's send 1 (%s)" % [link.state.track(4).sends.keys()],
			link.state.track(4).sends.size() == 1 and link.state.send(4, 1).dest_track == 26)
	link.set_send_volume(4, 1, 0.4)
	close_to("Reaper's backend writes the send level on its OSC address", link.state.send(4, 1).volume, 0.4)
	link.set_send_pan(4, 1, 0.9)
	close_to("and the send pan", link.state.send(4, 1).pan, 0.9)
	link.free()

	# The desk: SENDS ON FADERS.
	_offline()
	s = DAW.state
	var console := ConsoleSurface.new()
	add_child(console)
	console._process(0.0)
	check("the returns the SENDS key steps through (%s)" % [ConsoleSurface.send_destinations(s)],
			ConsoleSurface.send_destinations(s) == [verb])
	var by_track := {}
	for strip in console.strips:
		by_track[strip.track_index] = strip
	var snare_strip: ChannelStrip = by_track[3]
	var kick_strip: ChannelStrip = by_track[2]
	console.cycle_sends()
	check("one press puts the sends to the return on the faders", console.send_dest == verb and snare_strip.send_dest == verb)
	close_to("the snare's fader is its send level", snare_strip._fader.value, s.send(3, 1).volume)
	check("and says so by name (%s)" % snare_strip._fader.title(), snare_strip._fader.title() == "SNARE  SEND TO VERB RTN")
	check("a strip with no send has a fader nobody can take hold of", kick_strip._fader.collision_layer == 0)
	check("and says it has none", kick_strip._db_label.text == "NO SEND")
	snare_strip._fader._set_value(0.3)
	close_to("moving it moves the send", s.send(3, 1).volume, 0.3, 0.02)
	close_to("and not the snare", s.track(3).volume, 0.72)
	snare_strip._pan.turned.emit(0.1)
	close_to("the pan knob is the send's pan", s.send(3, 1).pan, 0.1)
	close_to("not the track's", s.track(3).pan, 0.5)
	check("the master's key is lit", console.master._sends_key.lit)
	console.cycle_sends()
	check("past the last return the faders are levels again", console.send_dest == 0 and snare_strip.send_dest == 0)
	close_to("and the snare's fader is its level", snare_strip._fader.value, s.track(3).volume)
	check("with a fader anyone can take hold of", kick_strip._fader.collision_layer == 2)
	console.queue_free()


func _test_the_click_is_switched_from_the_deck() -> void:
	var backend := _offline()
	var s := DAW.state
	check("the stand-in starts with the click off", not s.metronome)
	backend._repl_durable.clear()
	DAW.set_metronome(true)
	check("set_metronome turns it on", s.metronome)
	check("and replicates it as /click", backend._repl_durable.get("/click", []) == [1.0])
	check("a verb a guest may use", &"set_metronome" in DAW.COMMANDS)
	DAW.apply_intent(&"set_metronome", [0.0])
	check("a guest's intent switches it off", not s.metronome)
	DAW.apply_intent(&"set_metronome", ["1"])
	check("whatever shape the value arrives in", s.metronome)
	DAW.apply_intent(&"set_metronome", [])
	check("and an empty one is refused", s.metronome)

	var guest := MixState.new()
	for pair in MixWire.snapshot(s):
		MixWire.apply(guest, pair[0], pair[1])
	check("a joining guest is told the click is on", guest.metronome)

	# Reaper's /click is a toggle: 1 flips it and 0 is ignored, so a release must never be sent
	# and a press must never be sent twice.
	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	add_child(reaper)
	reaper.set_metronome(true)
	check("Reaper's backend takes the click on", reaper.state.metronome)
	reaper.set_metronome(true)
	check("and asking again leaves it on rather than flipping it", reaper.state.metronome)
	reaper._apply("/click", [0.0])
	check("Reaper switching it off is heard", not reaper.state.metronome)
	reaper.free()

	_offline()
	var deck := TapeDeck.new()
	add_child(deck)
	deck._process(0.0)
	check("the deck's CLICK lamp is dark with the click off", not deck._click_lamp.lit)
	deck._click_lamp.pressed.emit()
	check("pressing CLICK turns the click on", DAW.state.metronome)
	deck._process(0.0)
	check("and lights its lamp", deck._click_lamp.lit)
	check("it goes by its name across a session", deck._click_lamp.network_key() == "TRANSPORT  CLICK")
	deck.queue_free()


func _test_input_monitoring_is_set_from_the_strip() -> void:
	var backend := _offline()
	var s := DAW.state
	check("the stand-in's armed vocal monitors on auto", s.track(2).monitor == DAW.MONITOR_AUTO)
	check("and an unarmed track not at all", s.track(1).monitor == DAW.MONITOR_OFF)
	backend._repl_durable.clear()
	DAW.set_track_monitor(1, DAW.MONITOR_ON)
	check("set_track_monitor turns it on", s.track(1).monitor == DAW.MONITOR_ON)
	check("and replicates it as Reaper's own address", backend._repl_durable.get("/track/1/monitor", []) == [1.0])
	DAW.undo()
	check("it is undoable", s.track(1).monitor == DAW.MONITOR_OFF)
	DAW.redo()
	check("and redoable", s.track(1).monitor == DAW.MONITOR_ON)
	DAW.set_track_monitor(1, 7)
	check("a mode past auto is auto", s.track(1).monitor == DAW.MONITOR_AUTO)
	check("a verb a guest may use", &"set_track_monitor" in DAW.COMMANDS)
	DAW.apply_intent(&"set_track_monitor", [1, -3])
	check("a guest's intent is clamped to Reaper's three modes", s.track(1).monitor == DAW.MONITOR_OFF)
	DAW.apply_intent(&"set_track_monitor", [0, 1])
	DAW.apply_intent(&"set_track_monitor", [1])
	check("and one naming no track, or no mode, is refused", s.track(1).monitor == DAW.MONITOR_OFF)

	var guest := MixState.new()
	for pair in MixWire.snapshot(s):
		MixWire.apply(guest, pair[0], pair[1])
	check("a joining guest is told every track's monitoring", guest.track(2).monitor == DAW.MONITOR_AUTO
			and guest.track(10).monitor == DAW.MONITOR_ON)
	MixWire.apply(guest, "/track/2/monitor", [9.0])
	check("and a reading off the end of the scale is kept on it", guest.track(2).monitor == DAW.MONITOR_AUTO)

	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	add_child(reaper)
	reaper.set_track_monitor(3, DAW.MONITOR_AUTO)
	check("Reaper's backend takes the mode", reaper.state.track(3).monitor == DAW.MONITOR_AUTO)
	reaper._apply("/track/3/monitor", [1.0])
	check("and hears Reaper change it", reaper.state.track(3).monitor == DAW.MONITOR_ON)
	reaper.free()

	check("a press goes off, on, auto, off", ChannelStrip.next_monitor(0) == 1
			and ChannelStrip.next_monitor(1) == 2 and ChannelStrip.next_monitor(2) == 0)
	_offline()
	s = DAW.state
	var strip := ChannelStrip.create(1)
	add_child(strip)
	check("the strip's monitor lamp is dark when monitoring is off", not strip._monitor.lit
			and not strip.is_processing())
	strip._monitor.pressed.emit()
	check("pressing it turns monitoring on", s.track(1).monitor == DAW.MONITOR_ON)
	check("and lights it steady", strip._monitor.lit and not strip.is_processing())
	strip._monitor.pressed.emit()
	check("again puts it on auto, and the lamp blinks", s.track(1).monitor == DAW.MONITOR_AUTO
			and strip.is_processing())
	check("which the card says in words", strip._monitor.describe_value.call(0.0).begins_with("AUTO"))
	check("it goes by its track's name across a session",
			strip._monitor.network_key() == s.track(1).display_name().to_upper() + "  INPUT MONITOR")
	var lamps := {}
	for b in [strip._rec, strip._solo, strip._mute, strip._monitor]:
		lamps[b.lamp_scale] = true
	check("its lamp has a shape of its own among the four", lamps.size() == 4)
	strip._monitor.pressed.emit()
	check("and a third press turns it off", s.track(1).monitor == DAW.MONITOR_OFF)
	strip.queue_free()


func _test_markers_are_dropped_and_found_from_the_deck() -> void:
	var backend := _offline()
	var s := DAW.state
	var count := s.markers.size()
	check("the stand-in has sections to find (%d)" % count, count >= 4)
	check("the offline stand-in can drop markers", DAW.can(DAWBackend.Capability.MARKERS))
	backend._repl_durable.clear()
	DAW.add_marker(12.5, "Drop")
	check("add_marker drops a marker", s.markers.get(12.5) == "Drop" and s.markers.size() == count + 1)
	check("and replicates the markers", backend._repl_durable.has("/timeline/markers"))
	DAW.undo()
	check("a marker is undoable", not s.markers.has(12.5) and s.markers.size() == count)
	DAW.redo()
	check("and redoable", s.markers.get(12.5) == "Drop")
	check("a verb a guest may use", &"add_marker" in DAW.COMMANDS)
	DAW.apply_intent(&"add_marker", [-4.0, "x".repeat(500)])
	check("a guest's marker is kept on the timeline and its name to a sane length",
			s.markers.has(0.0) and str(s.markers[0.0]).length() == DAW.MARKER_NAME_MAX)
	DAW.apply_intent(&"add_marker", [3.0])
	check("and a malformed one is refused", not s.markers.has(3.0))
	var guest := MixState.new()
	for pair in MixWire.snapshot(s):
		MixWire.apply(guest, pair[0], pair[1])
	check("a joining guest is told every marker", guest.markers.size() == s.markers.size()
			and guest.markers.get(12.5) == "Drop")

	# Locating, which is arithmetic on the markers and needs no DAW behind it.
	var m := {10.0: "A", 20.0: "B", 30.0: "C"}
	close_to("next from between two is the later", TapeDeck.marker_after(m, 15.0), 20.0)
	close_to("next from on a marker is the one after it", TapeDeck.marker_after(m, 20.0), 30.0)
	close_to("next past the last is none", TapeDeck.marker_after(m, 31.0), -1.0)
	close_to("prev from between two is the earlier", TapeDeck.marker_before(m, 25.0), 20.0)
	close_to("prev just past a marker skips it, so rolling cannot pin the key",
			TapeDeck.marker_before(m, 20.1), 10.0)
	close_to("prev before the first is none", TapeDeck.marker_before(m, 5.0), -1.0)
	check("the section is the marker at or before", TapeDeck.section_at(m, 25.0) == "B" and TapeDeck.section_at(m, 20.0) == "B")
	check("and nothing before the first", TapeDeck.section_at(m, 2.0) == "")
	check("MARK names the next free number", TapeDeck.next_marker_name({1.0: "MARK 1", 2.0: "MARK 3"}) == "MARK 2")

	# Reaper: the bridge makes it, and the cache shows it before the timeline poll says so.
	var link := _fresh_link()
	check("Reaper without the bridge cannot drop a marker", not link.can(DAWBackend.Capability.MARKERS))
	link.add_marker(4.0, "Nope")
	check("and does not pretend to", not link.state.markers.has(4.0))
	link.free()

	_offline()
	s = DAW.state
	var deck := TapeDeck.new()
	add_child(deck)
	deck._process(0.0)
	DAW.seek(s.bar_to_seconds(30.0))
	deck._process(0.0)
	check("the deck names the section the playhead is in (%s)" % deck._section_label.text,
			deck._section_label.text == "CHORUS 1")
	var next := TapeDeck.marker_after(s.markers, s.position_seconds)
	deck._locate(1)
	close_to("NEXT goes to the next marker", s.position_seconds, next)
	deck._locate(-1)
	close_to("PREV from there goes back one", s.position_seconds, s.bar_to_seconds(25.0))
	DAW.seek(s.bar_to_seconds(27.0))
	var before := s.markers.size()
	deck._mark_key.pressed.emit()
	check("MARK drops a marker at the playhead", s.markers.size() == before + 1
			and s.markers.get(s.position_seconds) == "MARK 1")
	check("MARK goes by its name across a session", deck._mark_key.network_key() == "TRANSPORT  ADD MARKER")
	deck.queue_free()


func _test_undo_takes_back_a_gesture_not_a_frame() -> void:
	_offline()
	var s := DAW.state
	var before := s.track(3).volume
	for i in 20:
		DAW.set_track_volume(3, before - 0.01 * i)
	var dragged := s.track(3).volume
	check("one drag is one step (%d)" % s.undo_depth, s.undo_depth == 1)
	DAW.set_track_mute(3, true)
	DAW.set_fx_enabled(1, 1, false)
	check("each switch is its own step", s.undo_depth == 3)
	DAW.undo()
	check("undo puts the plugin back in", s.fx(1, 1).enabled)
	DAW.undo()
	check("then unmutes", not s.track(3).mute)
	DAW.undo()
	close_to("then puts the fader back where the drag started", s.track(3).volume, before)
	check("and there is nothing left to undo", s.undo_depth == 0 and s.redo_depth == 3)
	DAW.redo()
	close_to("redo puts it where the drag ended", s.track(3).volume, dragged)
	DAW.set_track_pan(3, 0.2)
	check("a new change clears what could be redone", s.redo_depth == 0)
	DAW.transport_play()
	DAW.seek(10.0)
	check("the transport is not history", s.undo_depth == 2)


func _test_reaper_hears_the_transport_in_its_own_words() -> void:
	var state := MixState.new()
	MixWire.apply(state, "/repeat", [1.0])
	check("/repeat is the loop switch", state.looping)
	MixWire.apply(state, "/loop/start/time", [8.0])
	MixWire.apply(state, "/loop/end/time", [16.0])
	check("/loop/start|end/time is the range", state.loop_start == 8.0 and state.loop_end == 16.0)
	MixWire.apply(state, "/beat/str", ["33.2.50"])
	check("/beat/str is the bar/beat counter", state.position_string == "33.2.50")
	MixWire.apply(state, "/time/str", ["1:23.456"])
	check("/time/str does not overwrite it", state.position_string == "33.2.50" and state.time_string == "1:23.456")

	var reaper := ReaperBackend.new()
	var sent: Array = []
	reaper.state = MixState.new()
	add_child(reaper)
	# No socket: write() applies locally, which is what the desk sees between send and echo.
	reaper.set_looping(true)
	check("set_looping turns looping on", reaper.state.looping)
	reaper.seek(42.0)
	close_to("seek is /time in seconds", reaper.state.position_seconds, 42.0)
	reaper.set_loop_range(4.0, 12.0)
	check("the loop range goes as two times", reaper.state.loop_start == 4.0 and reaper.state.loop_end == 12.0)
	check("undo and redo are Reaper's own actions", ReaperBackend.UNDO_ACTION == 40029 and ReaperBackend.REDO_ACTION == 40030)
	reaper.queue_free()
	_offline()


## A live Reaper's arrangement arrives over the bridge after the timeline has already built once
## with nothing on it. Fitting only the first build pinned the window to that empty stub.
func _test_a_late_arrangement_is_still_fitted() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	backend.track_count = 4
	DAW.use(backend)
	for index in DAW.state.track_indices():
		DAW.state.set_track_items(index, [])
	DAW.state.project_length = 0.0
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)
	close_to("an empty project is shown whole", timeline.view_span, maxf(DAW.state.timeline_length(), TimelineScrubber.MIN_SPAN))
	DAW.state.set_track_items(2, [_item(0.0, 180.0, "Song")])
	timeline.mark_dirty()
	timeline._process(0.0)
	close_to("the song that turned up later is shown whole too", timeline.view_span, 180.0)
	timeline.set_view(20.0, 30.0)
	DAW.state.set_track_items(2, [_item(0.0, 240.0, "Longer")])
	timeline.mark_dirty()
	timeline._process(0.0)
	close_to("once the viewer has zoomed, the window is theirs", timeline.view_span, 30.0)
	timeline.queue_free()
	DAW.use(previous)


# --- the session ----------------------------------------------------------------------------

func _test_a_released_control_ignores_its_own_late_echoes() -> void:
	var control := ControlAffordance.new()
	add_child(control)
	var hand := Interactor.new()
	control.grab_begin(hand, Vector3.ZERO)
	control.value = 0.8
	control.grab_end(hand)
	# Replies still in flight from the drag, describing where the fader was a moment ago.
	control.apply_remote(0.3)
	check("an echo from before the release does not drag the fader back", is_equal_approx(control.value, 0.8))
	control.apply_remote(0.8)
	check("the echo of the value the hand left ends the wait", not control.is_settling())
	control.apply_remote(0.5)
	check("after which the mix moves it as normal", is_equal_approx(control.value, 0.5))

	# A mix that really did settle somewhere else still has the last word, once the wait is over.
	control.grab_begin(hand, Vector3.ZERO)
	control.value = 0.9
	control.grab_end(hand)
	control.apply_remote(0.85)
	check("a different settle is held back while it might be stale", is_equal_approx(control.value, 0.9))
	control._settle_until = 0
	control._echo_wait_over()
	check("and applied when the wait runs out", is_equal_approx(control.value, 0.85))

	check("controls are findable by group", control.is_in_group(ControlAffordance.GROUP))
	hand.free()
	remove_child(control)
	control.free()


func _test_a_control_held_elsewhere_refuses_hands_but_still_moves() -> void:
	var control := ControlAffordance.new()
	add_child(control)
	var hand := Interactor.new()
	control.claimed_by = RefCounted.new()
	control.grab_begin(hand, Vector3.ZERO)
	check("a hand is refused a control someone else in the session holds", control.held_by == null)
	check("and so is the wheel", not control.nudge(hand, 1, false))
	control.apply_remote(0.4)
	check("but it still follows the mix they are moving", is_equal_approx(control.value, 0.4))
	control.claimed_by = null
	control.grab_begin(hand, Vector3.ZERO)
	check("let go of, it can be taken", control.held_by == hand)
	control.grab_end(hand)
	hand.free()
	remove_child(control)
	control.free()


## Session state is global; every session test leaves it solo, as it found it.
func _as_session(role: int, me: int) -> void:
	Session.start_solo()
	Session.role = role
	Session.local_peer_id = me
	Session.participants.clear()
	Session.holds.clear()


func _test_the_roster_is_the_hosts_word() -> void:
	var notices: Array[String] = []
	var hear := func(t: String): notices.append(t)
	Session.notice.connect(hear)
	_as_session(Session.Role.GUEST, 5)
	Session._has_settled = false
	Session.apply_roster([[1, "Ada", 0, 0], [5, "Grace", 0, 1]])
	check("a guest takes names from the host's roster", Session.name_of(1) == "Ada" and Session.name_of(5) == "Grace")
	check("and colours", Session.participants[5].colour == Session.PALETTE[1])
	check("and says whose session it joined, once (%s)" % [notices], notices == ["Joined Ada's session."])
	notices.clear()
	Session.apply_roster([[1, "Ada", 0, 0], [5, "Grace", 0, 1], [9, "Lin", 2, 2]])
	check("a later arrival is announced (%s)" % [notices], notices == ["Lin joined the session."])
	check("with the medium they came in", Session.participants[9].medium == 2)
	notices.clear()
	Session.apply_roster([[1, "Ada", 0, 0], [5, "Grace", 0, 1]])
	check("and a departure (%s)" % [notices], notices == ["Lin left the session."])
	check("who is then gone", not Session.participants.has(9))

	_as_session(Session.Role.HOST, 1)
	Session._register(1, "Ada", Session._free_colour())
	Session._register(2, "joining…", Session._free_colour())
	Session._register(3, "joining…", Session._free_colour())
	Session.participants.erase(2)
	check("a colour given up is the next one handed out",
			Session._register(4, "joining…", Session._free_colour()).colour_index == 1)
	Session.notice.disconnect(hear)
	Session.start_solo()


func _test_the_host_keeps_one_hand_per_control() -> void:
	var refused: Array = []
	var hear := func(k: String, h: int): refused.append([k, h])
	Session.hold_refused.connect(hear)
	_as_session(Session.Role.HOST, 1)
	Session._grant(7, "KICK  LEVEL")
	check("the first hand gets the control", Session.holder_of("KICK  LEVEL") == 7)
	Session._grant(1, "KICK  LEVEL")
	check("the second is refused, and told by whom (%s)" % [refused], refused == [["KICK  LEVEL", 7]])
	check("and the first keeps it", Session.holder_of("KICK  LEVEL") == 7)
	Session._release(1, "KICK  LEVEL")
	check("nobody can let go of a control for somebody else", Session.holder_of("KICK  LEVEL") == 7)
	Session._release(7, "KICK  LEVEL")
	check("its holder can", Session.holder_of("KICK  LEVEL") == 0)
	Session._grant(1, "KICK  LEVEL")
	check("after which anyone may take it", Session.holder_of("KICK  LEVEL") == 1)

	# Somebody leaving with their hand on a fader must not leave it held forever.
	Session._register(7, "Grace", 1)
	Session._grant(7, "SNARE  PAN")
	Session._on_peer_disconnected(7)
	check("a departed holder's controls are freed", Session.holder_of("SNARE  PAN") == 0)
	check("and nobody else's", Session.holder_of("KICK  LEVEL") == 1)
	Session.hold_refused.disconnect(hear)
	Session.start_solo()


func _test_presence_marks_what_others_hold() -> void:
	var control := ControlAffordance.new()
	control.describe_title = func() -> String: return "TEST  PRESENCE FADER"
	add_child(control)
	var presence := Presence.new()
	add_child(presence)
	_as_session(Session.Role.GUEST, 5)
	Session.apply_roster([[1, "Ada", 0, 0], [5, "Grace", 0, 1]])
	check("an avatar for everyone but me", presence._avatars.size() == 1 and presence._avatars.has(1))
	presence._scan_msec = -100000
	check("a control is found by the name it goes by", presence.find_control("TEST  PRESENCE FADER") == control)
	Session.holds = {"TEST  PRESENCE FADER": 1}
	presence._apply_holds()
	check("a control the host holds is claimed on my desk", control.claimed_by == Session.participants[1])
	Session.holds = {"TEST  PRESENCE FADER": 5}
	presence._apply_holds()
	check("one I hold is not refused to me", control.claimed_by == null)
	Session.holds = {}
	presence._apply_holds()
	check("and a released one is free", control.claimed_by == null)
	Session.start_solo()
	presence._sync_avatars()
	check("alone again, the avatars go", presence._avatars.is_empty())
	remove_child(presence)
	presence.free()
	remove_child(control)
	control.free()


func _test_meters_go_out_in_parcels_under_the_mtu() -> void:
	var batch: Array = []
	for t in 64:
		batch.append(["/track/%d/vu/L" % t, [0.123456]])
		batch.append(["/track/%d/vu/R" % t, [0.654321]])
	var parcels := Session._parcels(batch)
	var biggest := 0
	var count := 0
	for parcel in parcels:
		biggest = maxi(biggest, var_to_bytes(parcel).size())
		count += parcel.size()
	check("sixty-four tracks of meters is several parcels (%d)" % parcels.size(), parcels.size() > 1)
	check("none of them fragmented (%d bytes)" % biggest, biggest < 1300)
	check("and nothing lost on the way", count == batch.size())


## A rebuild frees every control a surface built, so one that lands mid-drag leaves the hand
## holding nothing. Found live: Reaper restating its project size cut a fader drag off a second in.
func _test_a_surface_never_rebuilds_under_a_hand() -> void:
	var previous := DAW.backend
	DAW.use(OfflineBackend.new())
	var console := ConsoleSurface.new()
	add_child(console)
	console._process(0.0)
	var hand := FakeHand.new()
	hand.set_physics_process(false)
	add_child(hand)
	var grabbed: ControlAffordance = null
	for node in console.find_children("*", "ControlAffordance", true, false):
		grabbed = node
		break
	grabbed.grab_begin(hand, grabbed.global_position)
	console.mark_dirty()
	console._process(0.0)
	check("a dirty surface keeps the control a hand is on", is_instance_valid(grabbed)
			and not grabbed.is_queued_for_deletion() and grabbed.is_inside_tree())
	grabbed.grab_end(hand)
	console._process(0.0)
	check("and rebuilds once the hand lets go", not grabbed.is_inside_tree())
	hand.queue_free()
	console.queue_free()
	DAW.use(previous, false)


func _test_a_restated_project_size_is_not_a_new_bank() -> void:
	var state := MixState.new()
	var count := [0]
	state.bank_changed.connect(func(): count[0] += 1)
	MixWire.apply(state, "/project/tracks", [40])
	MixWire.apply(state, "/project/tracks", [40])
	MixWire.apply(state, "/project/tracks", [40])
	check("the project size announces a bank change once, not per restatement", count[0] == 1)
	MixWire.apply(state, "/project/tracks", [41])
	check("and again when it really changes", count[0] == 2)


func _test_the_mix_survives_the_wire() -> void:
	var frames := PackedVector2Array()
	for i in MixFeed.FRAMES:
		frames.append(Vector2(sin(i * 0.1) * 0.5, -0.25 if i % 2 == 0 else 1.5))
	var packet := MixFeed.encode(77, frames)
	check("a packet of audio fits in one datagram (%d bytes)" % packet.size(), packet.size() <= 600)
	var back := MixFeed.decode(packet)
	check("and decodes to the same sequence number", back.get("seq") == 77)
	var worst := 0.0
	for i in frames.size():
		worst = maxf(worst, absf(back["frames"][i].x - frames[i].x))
	check("with every frame within one 16-bit step (%f)" % worst, worst <= 1.0 / 32767.0 + 1e-6)
	check("and an over-full sample clipped rather than wrapped", is_equal_approx(back["frames"][1].y, 1.0))
	check("a listen packet is not mistaken for audio", MixFeed.decode(MixFeed.listen_packet(5, 9)).is_empty())
	check("nor is a stranger's datagram", MixFeed.decode(PackedByteArray([1, 2, 3])).is_empty())


## Packets every 2.7ms, arriving with up to 6ms of jitter, read in 512-frame gulps the way a
## sound card reads. After priming it must never run dry.
func _test_the_jitter_buffer_rides_out_a_bad_network() -> void:
	var jb := JitterBuffer.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var packet_ms := MixFeed.FRAMES * 1000.0 / 48000.0
	var arrivals: Array = []
	for seq in 3000:
		arrivals.append([seq * packet_ms + rng.randf_range(0.0, 6.0), seq])
	arrivals.sort_custom(func(a, b): return a[0] < b[0])
	var chunk := PackedVector2Array()
	chunk.resize(MixFeed.FRAMES)
	chunk.fill(Vector2(0.1, 0.1))
	var next := 0
	var underruns_after_prime := -1
	var t := 0.0
	while t < 3000 * packet_ms - 50.0:
		while next < arrivals.size() and arrivals[next][0] <= t:
			jb.push(arrivals[next][1], chunk, arrivals[next][0])
			next += 1
		jb.pull(512)
		if underruns_after_prime < 0 and jb.depth() > 0:
			underruns_after_prime = jb.underruns
		t += 512 * 1000.0 / 48000.0
	check("a jittery network is measured as jittery (%.2fms)" % jb.jitter_ms(), jb.jitter_ms() > 0.5)
	check("and the buffer is kept deep enough that it never runs dry (%d)" % jb.underruns,
			jb.underruns == underruns_after_prime)
	check("but no deeper than a few deviations of it (%d frames)" % jb.target, jb.target < 1600)
	check("reordered packets are counted, not played (%d late)" % jb.late, jb.late > 0)


## The host's card at 48048Hz against the guest's at 48000: a tenth of a percent, a whole
## second of drift an hour. The read rate must bend to hold the depth.
func _test_the_jitter_buffer_follows_a_drifting_clock() -> void:
	for host_rate in [48048.0, 47952.0]:
		var jb := JitterBuffer.new()
		var chunk := PackedVector2Array()
		chunk.resize(MixFeed.FRAMES)
		var packet_ms: float = MixFeed.FRAMES * 1000.0 / host_rate
		var seq := 0
		var t := 0.0
		var pull_ms := 256 * 1000.0 / 48000.0
		var next_pull := 0.0
		# Twenty minutes, compressed: long enough that an uncorrected buffer would have drifted
		# by over a second.
		while t < 20.0 * 60.0 * 1000.0:
			if t >= seq * packet_ms:
				jb.push(seq, chunk, t)
				seq += 1
			if t >= next_pull:
				jb.pull(256)
				next_pull += pull_ms
			t = minf(seq * packet_ms, next_pull)
		check("a %s host clock is followed (depth %d against target %d, %d underruns)" % [
				"fast" if host_rate > 48000.0 else "slow", jb.depth(), jb.target, jb.underruns],
				absi(jb.depth() - jb.target) < 400 and jb.underruns <= 1)
		check("by bending the read rate the right way (%.5f)" % jb.ratio(),
				(jb.ratio() > 1.0) == (host_rate > 48000.0))


func _test_the_jitter_buffer_fills_losses_and_drops_the_late() -> void:
	var jb := JitterBuffer.new()
	var chunk := PackedVector2Array()
	chunk.resize(128)
	chunk.fill(Vector2(0.5, 0.5))
	jb.push(0, chunk, 0.0)
	jb.push(1, chunk, 2.7)
	jb.push(4, chunk, 10.7)
	check("two lost packets are counted", jb.lost == 2)
	check("and their time is filled, so what follows is not pulled early", jb.depth() == 128 * 5)
	jb.push(2, chunk, 11.0)
	check("a packet that arrives after its gap was filled is dropped", jb.late == 1 and jb.depth() == 128 * 5)
	var quiet := JitterBuffer.new()
	quiet.push(0, chunk, 0.0)
	var out := quiet.pull(256)
	check("a buffer still priming plays silence, not its first packet at once",
			out.size() == 256 and out[0] == Vector2.ZERO)


func _test_a_session_code_is_a_door() -> void:
	var was := Session.local_name
	Session.local_name = "Ada"
	Session.code = ""
	check("an open session lets anyone in", Session.admission_refusal("").is_empty())
	Session.code = "K7QX"
	check("a locked one does not let in no code", Session.admission_refusal("") != "")
	check("nor the wrong one", Session.admission_refusal("K7QY") == "That is not Ada's code.")
	check("and does not care how it was typed", Session.admission_refusal(" k7 qx ").is_empty())
	var code := SessionPanel.make_code()
	check("a made code is four characters with nothing to misread (%s)" % code,
			code.length() == 4 and not code.contains("0") and not code.contains("O")
			and not code.contains("1") and not code.contains("I"))
	Session.code = ""
	Session.local_name = was


## The shape Godot actually consumes in: a generator queue the mixer empties 512 frames at a
## time, refilled from the jitter buffer a packet at a time as packets land. The first version
## of this sized the buffer for the packet and ran dry fifteen times a second on the gulp.
func _test_the_jitter_buffer_feeds_a_mixer_that_gulps() -> void:
	var jb := JitterBuffer.new()
	jb.step_frames = MixFeed.MIX_STEP
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var chunk := PackedVector2Array()
	chunk.resize(MixFeed.FRAMES)
	chunk.fill(Vector2(0.2, 0.2))
	var packet_ms := MixFeed.FRAMES * 1000.0 / 48000.0
	var step_ms := MixFeed.MIX_STEP * 1000.0 / 48000.0
	var arrivals: Array = []
	for seq in 4000:
		arrivals.append([seq * packet_ms + rng.randf_range(0.0, 2.0), seq])
	arrivals.sort_custom(func(a, b): return a[0] < b[0])
	var queued := 0
	var next := 0
	var next_step := 0.0
	var started := false
	var buffered_ms: Array = []
	var t := 0.0
	while t < 3900 * packet_ms:
		while next < arrivals.size() and arrivals[next][0] <= t:
			jb.push(arrivals[next][1], chunk, arrivals[next][0])
			next += 1
		while queued + MixFeed.FRAMES <= MixFeed.QUEUE_FRAMES:
			if jb.take(MixFeed.FRAMES, queued).is_empty():
				break
			queued += MixFeed.FRAMES
			started = true
		if t >= next_step:
			if queued < MixFeed.MIX_STEP:
				jb.reprime()
			queued = maxi(0, queued - MixFeed.MIX_STEP)
			next_step += step_ms
			if started:
				buffered_ms.append((jb.depth() + queued) * 1000.0 / 48000.0)
		t += 0.5
	buffered_ms.sort()
	var median: float = buffered_ms[buffered_ms.size() / 2]
	check("a gulping mixer never finds the queue short (%d)" % jb.underruns, jb.underruns == 0)
	check("and the queue is not kept needlessly deep either (median %.1fms buffered)" % median,
			median < 20.0)
	var fresh := JitterBuffer.new()
	fresh.reprime()
	check("a player that starts before the first packet is not a dropout", fresh.underruns == 0)


## Joining a session, leaving one, falling back to the stand-in: each replaces the backend, and
## its MixState with it. A surface subscribed to the state it was built under would go on
## listening to a mix nobody changes any more -- a guest who fell back to solo kept the host's
## forty-track timeline on the stand.
func _test_the_room_keeps_listening_across_a_change_of_backend() -> void:
	var previous := DAW.backend
	var heard := [0]
	var hear := func(): heard[0] += 1
	DAW.use(OfflineBackend.new(), false)
	var first := DAW.backend
	DAW.timeline_changed.connect(hear)
	DAW.use(OfflineBackend.new(), false)
	heard[0] = 0
	DAW.state.timeline_changed.emit()
	check("a change to the new mix reaches whoever listened through DAW", heard[0] == 1)
	if is_instance_valid(first):
		first.state.timeline_changed.emit()
	check("and the old mix, if anything still stirs it, does not", heard[0] == 1)
	DAW.timeline_changed.disconnect(hear)
	DAW.use(previous, false)

	var offences: Array[String] = []
	for path in _gd_files_under("res://hardware") + _gd_files_under("res://core/presentation") + _gd_files_under("res://scenes"):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			if RegEx.create_from_string("DAW\\.state\\.[a-z_]+\\.(connect|is_connected)").search(code) != null:
				offences.append("%s: %s" % [path.get_file(), code])
	for offence in offences:
		print("    " + offence)
	check("nothing subscribes to a mix that can be swapped out from under it", offences.is_empty())
	check("and the scan would have caught the line that did", RegEx.create_from_string(
			"DAW\\.state\\.[a-z_]+\\.(connect|is_connected)").search(
			"DAW.state.timeline_changed.connect(mark_dirty)") != null)


# --- recording a guest ------------------------------------------------------------------------

func _test_the_mix_carries_the_song_position() -> void:
	var frames := PackedVector2Array()
	frames.resize(MixFeed.FRAMES)
	var flags := MixFeed.FLAG_VALID | MixFeed.FLAG_PLAYING | MixFeed.FLAG_RECORDING
	var packet := MixFeed.encode(9, frames, 1234.567890123456, flags)
	check("a stamped packet still fits one datagram (%d bytes)" % packet.size(), packet.size() <= 600)
	var back := MixFeed.decode(packet)
	check("the song position survives to the bit (%.12f)" % back.get("position", -1.0),
			back.get("position", -1.0) == 1234.567890123456)
	check("and the transport with it", back.get("valid", false) and back.get("playing", false)
			and back.get("recording", false))
	var stopped := MixFeed.decode(MixFeed.encode(10, frames, 3.0, MixFeed.FLAG_VALID))
	check("a stopped transport is said as stopped", not stopped["playing"] and not stopped["recording"])
	check("an unstamped packet says it does not know", not MixFeed.decode(MixFeed.encode(1, frames))["valid"])
	var old := packet.duplicate()
	old.encode_u32(0, 0x41334452)
	check("a packet from a build without stamps is not misread as one", MixFeed.decode(old).is_empty())
	check("flags read off a clock", MixFeed.flags_of({"valid": true, "playing": true, "recording": false})
			== MixFeed.FLAG_VALID | MixFeed.FLAG_PLAYING)


## Reaper says where its playhead is thirty times a second, late, and the stand-in once a frame.
## Packets need a position every 2.7ms. The clock runs between reports and is only corrected by
## them -- and a seek or a stop is taken at once, not eased into.
func _test_the_song_clock_runs_between_reports() -> void:
	var clock := SongClock.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var truth := func(usec: int) -> float: return 10.0 + usec / 1000000.0
	var worst := 0.0
	var t := 0
	var next_report := 0
	while t < 4000000:
		if t >= next_report:
			# Up to 3ms stale, only to the millisecond, and read up to a frame (16ms) late, the
			# way a busy DAW's reports reach a game loop.
			var said := snappedf(truth.call(t - rng.randi_range(0, 3000) - rng.randi_range(0, 16000)), 0.001)
			clock.observe(said, true, true, t)
			next_report = t + 33000 + rng.randi_range(0, 4000)
		if t > 1000000:
			# Against the truth less the reports' average lateness: that part is a constant, and
			# a constant is what the capture offset is for.
			worst = maxf(worst, absf(float(clock.at(t)["seconds"]) - truth.call(t - 9500)))
		t += 500
	check("between coarse, late reports the clock is within 3ms of the song (worst %.2fms)" % (worst * 1000.0),
			worst < 0.003)
	var held := clock.at(t)
	check("it says the transport it was told", held["playing"] and held["recording"] and held["valid"])

	clock.observe(100.0, true, false, t)
	close_to("a seek is a jump, not drift", clock.at(t + 1000)["seconds"], 100.001, 0.0005)
	clock.observe(100.0, true, false, t + 50000)
	close_to("the same report again is no news: the clock keeps running", clock.at(t + 50000)["seconds"],
			100.05, 0.0005)
	clock.observe(100.2, false, false, t + 200000)
	close_to("stopped, it stands still", clock.at(t + 900000)["seconds"], 100.2)
	check("and is not recording", not clock.at(t + 900000)["recording"])
	clock.observe(100.2, false, true, t + 950000)
	check("a record flag without the transport rolling is not a recording",
			not clock.at(t + 950000)["recording"])
	check("a fresh clock knows nothing", not SongClock.new().at(0)["valid"])

	# Reaper, asked to record: playing at once, its playhead still for 130ms.
	var start := SongClock.new()
	start.observe(4.0, false, false, 0)
	start.observe(4.0, true, true, 1000000)
	start.observe(4.0, true, true, 1050000)
	var held_still := start.at(1100000)
	check("a start holds still until the playhead is seen to move",
			held_still["seconds"] == 4.0 and not held_still["playing"] and not held_still["recording"])
	start.observe(4.004, true, true, 1134000)
	close_to("then runs from where it was seen", start.at(1234000)["seconds"], 4.104, 0.0005)
	check("rolling, and recording", start.at(1234000)["playing"] and start.at(1234000)["recording"])
	var mute := SongClock.new()
	mute.observe(7.0, true, false, 0)
	mute.observe(7.0, true, false, 600000)
	close_to("a playhead never seen to move is taken as rolling after half a second",
			mute.at(700000)["seconds"], 7.1, 0.0005)


## The guest's speakers, measured as a staircase -- the mixer takes 512 frames at a gulp -- and the
## song position of whatever frame is coming out of them.
func _test_the_guest_knows_which_moment_it_is_hearing() -> void:
	var heard := HeardClock.new()
	var flags := MixFeed.FLAG_VALID | MixFeed.FLAG_PLAYING | MixFeed.FLAG_RECORDING
	for seq in 200:
		if seq != 9:
			heard.stamp(seq, 20.0 + seq * 128 / 48000.0, flags, 0)
	var at := heard.position_of(1000.0)
	close_to("a frame is its packet's stamp plus how far into the packet",
			at["seconds"], 20.0 + 1000.0 / 48000.0, 0.000001)
	check("with the transport its packet carried", at["playing"] and at["recording"] and at["valid"])
	close_to("a lost packet's frames count on from the last stamp heard",
			heard.position_of(9 * 128 + 5.0)["seconds"], 20.0 + (9 * 128 + 5) / 48000.0, 0.000001)
	heard.stamp(300, 55.5, MixFeed.FLAG_VALID, 0)
	close_to("a stopped stream stands at its stamp", heard.position_of(300 * 128 + 100.0)["seconds"], 55.5)
	check("and says it is stopped", not heard.position_of(300 * 128 + 100.0)["playing"])
	check("a frame before any stamp is not a position", not heard.position_of(-5.0)["valid"])

	# The playhead: the true frame at the speaker runs at 48 a millisecond; what is measured is a
	# staircase round it, as Godot's mixer gulps.
	var staircase := HeardClock.new()
	var worst := 0.0
	for step in 8000:
		var usec := step * 500
		var truth := usec * 0.048
		staircase.observe(floorf(truth / 512.0) * 512.0 + 256.0, usec)
		if usec > 2000000:
			worst = maxf(worst, absf(staircase.frame_at(usec + 250) - (truth + 12.0)))
	check("a staircase measurement becomes a smooth playhead, within 1ms (worst %.2fms)" % (worst / 48.0),
			worst < 48.0)
	staircase.observe(500000.0, 4000000)
	close_to("a playhead that jumps (a reprime) is followed at once", staircase.frame_at(4000000), 500000.0, 1.0)

	heard.observe(1000.0, 0)
	check("stamps a second old are not trusted", not heard.at(1500000)["valid"])
	check("fresh ones are", heard.at(200000)["valid"])


func _test_the_jitter_buffer_knows_which_host_frame_is_next() -> void:
	var jb := JitterBuffer.new()
	var chunk := PackedVector2Array()
	chunk.resize(128)
	for seq in range(10, 40):
		if seq != 25:
			jb.push(seq, chunk, seq * 2.67)
	close_to("before playing, the next frame is the first one that arrived", jb.read_frame(), 10 * 128)
	var pulled := 0
	for i in 6:
		jb.pull(512)
	pulled = 6 * 512
	var expected := 10.0 * 128 + pulled
	check("after playing, it is that many frames on, losses and all (%.1f for %.1f)" % [jb.read_frame(), expected],
			absf(jb.read_frame() - expected) < pulled * MixFeed.QUEUE_FRAMES * 0.000001 + pulled * JitterBuffer.MAX_BEND + 1.0)


func _test_a_take_is_assembled_from_stamped_notes() -> void:
	var take := MidiTake.new()
	take.begin(10.0)
	take.note_on(60, 100, 0, 10.5)
	take.note_off(60, 0, 11.0)
	take.note_on(64, 80, 0, 10.75)
	# Struck again before it was let go: the first strike ends where the second begins.
	take.note_on(64, 90, 0, 11.25)
	take.note_off(64, 0, 11.5)
	# Let go under the pedal: it sounds until the pedal comes up.
	take.sustain(true, 0, 11.6)
	take.note_on(67, 70, 0, 11.7)
	take.note_off(67, 0, 11.8)
	take.sustain(false, 0, 12.4)
	# Still down when the take ends.
	take.note_on(72, 127, 0, 12.8)
	take.note_off(48, 0, 12.9)
	take.reach(13.0)
	check("a key that is down counts as being in the take", take.held_count() == 1)
	var done := take.finish()
	var notes: Array = done["notes"]
	close_to("the take starts where recording was first heard", done["start"], 10.0)
	close_to("and ends at the furthest position heard", done["end"], 13.0)
	check("every note is in it, in time order (%d)" % notes.size(), notes.size() == 5
			and notes.map(func(n): return n[2]) == [60, 64, 64, 67, 72])
	check("a note is [on, off, pitch, velocity, channel]", notes[0] == [10.5, 11.0, 60, 100, 0])
	close_to("a retriggered key is cut at the retrigger", notes[1][1], 11.25)
	close_to("a note let go under the pedal lasts until the pedal is lifted", notes[3][1], 12.4)
	close_to("a note still held when the take ends is closed at its end", notes[4][1], 13.0)
	check("a release with no press is ignored", notes.all(func(n): return n[2] != 48))

	var early := MidiTake.new()
	early.begin(5.0)
	early.note_on(60, 64, 0, 4.9)
	early.note_off(60, 0, 4.9)
	var e: Array = early.finish(6.0)["notes"]
	check("a note stamped a hair before the take is pulled onto its start, and keeps a length",
			e.size() == 1 and e[0][0] == 5.0 and e[0][1] > e[0][0])


func _test_a_take_from_a_peer_is_cleaned_before_it_lands() -> void:
	var clean := MidiTake.clean_args([3, 2.0, 6.0, [
		[1.0, 2.5, 60, 100, 0],        # starts before the take: pulled onto it
		[3.0, 9.0, 200, 0, 99],        # past the end, out-of-range pitch, velocity, channel
		[4.0, 3.0, 62, 90],            # off before on, and no channel
		["x", 4.0, 64, 90, 0],         # not a number
		[NAN, 4.0, 64, 90, 0],         # not a finite one
		"not a note",
	], "Grace, \"take\" [1]"])
	check("a take with bad notes in it is still a take", clean.size() == 5)
	var notes: Array = clean[3]
	check("the unreadable notes are dropped and the rest kept (%d)" % notes.size(), notes.size() == 3)
	close_to("a note before the take starts at its start", notes[0][0], 2.0)
	check("a note past the end ends at the end, and its numbers are made MIDI",
			notes[1] == [3.0, 6.0, 127, 1, 15])
	check("a note whose off came before its on still has a length and a channel",
			notes[2][1] > notes[2][0] and notes[2][4] == 0)
	check("the name keeps its words and loses the bridge's punctuation (%s)" % clean[4],
			clean[4] == "Grace take 1")
	check("no track is not a take", MidiTake.clean_args([0, 1.0, 2.0, []]).is_empty())
	check("an end before the start is not a take", MidiTake.clean_args([1, 5.0, 2.0, []]).is_empty())
	check("notes that are not a list are not a take", MidiTake.clean_args([1, 1.0, 2.0, "x"]).is_empty())
	check("a missing argument is not a take", MidiTake.clean_args([1, 1.0, 2.0]).is_empty())
	var long := MidiTake.clean_args([1, 0.0, 1e9, []])
	close_to("an endless take is cut to an hour", long[2], MidiTake.MAX_SECONDS)
	var many: Array = []
	for i in MidiTake.MAX_NOTES + 50:
		many.append([0.0, 0.1, 60, 64, 0])
	check("and a flood of notes to the limit", (MidiTake.clean_args([1, 0.0, 1.0, many])[3] as Array).size()
			== MidiTake.MAX_NOTES)
	check("insert_midi_take is a verb a guest may use", &"insert_midi_take" in DAW.COMMANDS)


func _test_a_take_lands_on_the_stand_in_and_comes_off_again() -> void:
	var backend := _offline()
	var s := DAW.state
	var before := s.track(7).items.size()
	var depth := maxi(s.undo_depth, 0)
	backend._repl_durable.clear()
	var notes := [[30.25, 30.5, 60, 100, 0], [31.0, 31.75, 64, 90, 1]]
	check("the stand-in takes MIDI", DAW.can(DAWBackend.Capability.MIDI_TAKES))
	check("a good take has nothing to refuse", DAW.midi_take_refusal([7, 30.0, 32.0, notes, "Grace take 1"]).is_empty())
	DAW.apply_intent(&"insert_midi_take", [7, 30.0, 32.0, notes, "Grace take 1"])
	check("a guest's take lands as a new item on its track", s.track(7).items.size() == before + 1)
	var item: MixState.ItemState = null
	for it in s.track(7).items:
		if it.name == "Grace take 1":
			item = it
	check("named for whoever played it", item != null)
	if item != null:
		close_to("where the guest heard it", item.start, 30.0)
		close_to("as long as the take", item.length, 2.0)
		var back := MidiTake.unpack_relative(item.notes, item.start)
		check("with its notes, at the song positions they were stamped with (%s)" % [back],
				back.size() == 2 and is_equal_approx(back[0][0], 30.25) and is_equal_approx(back[1][1], 31.75)
				and back[1][2] == 64 and back[1][4] == 1)
	check("and it replicates on the lane's own address", backend._repl_durable.has("/track/7/items"))
	check("a take is one undo step (%d -> %d)" % [depth, s.undo_depth], s.undo_depth == depth + 1)
	var guest := MixState.new()
	MixWire.apply_replicated(guest, backend.snapshot())
	var copied: MixState.ItemState = guest.track(7).items.filter(func(it): return it.name == "Grace take 1").front() \
			if guest.track(7).items.any(func(it): return it.name == "Grace take 1") else null
	check("a guest joining later is sent the take, notes and all",
			copied != null and copied.notes == item.notes)
	DAW.undo()
	check("undo takes it off", s.track(7).items.size() == before)
	DAW.redo()
	check("redo puts it back", s.track(7).items.size() == before + 1)
	DAW.undo()

	check("a take onto a track that is not there is refused in words",
			DAW.midi_take_refusal([99, 1.0, 2.0, notes]).contains("no track"))
	DAW.apply_intent(&"insert_midi_take", [99, 1.0, 2.0, notes])
	check("and nothing lands", not s.tracks.has(99) or s.track(99).items.is_empty())
	check("a take with no notes is refused", not DAW.midi_take_refusal([7, 1.0, 2.0, []]).is_empty())
	DAW.apply_intent(&"insert_midi_take", [7, 1.0, 2.0, [], "empty"])
	check("and makes no item", s.track(7).items.size() == before)

	# Cut through the middle of it: the notes go with the half they start in.
	DAW.insert_midi_take(7, 30.0, 32.0, notes, "cut me")
	var index := -1
	for it in s.track(7).items:
		if it.name == "cut me":
			index = it.index
	DAW.select_item(7, index, false)
	DAW.split_selected(30.75)
	var halves := s.track(7).items.filter(func(it): return it.name == "cut me")
	check("a split take is two items", halves.size() == 2)
	if halves.size() == 2:
		var left := MidiTake.unpack_relative(halves[0].notes, halves[0].start)
		var right := MidiTake.unpack_relative(halves[1].notes, halves[1].start)
		check("each half keeps the notes that start in it",
				left.size() == 1 and right.size() == 1 and right[0][2] == 64)
		close_to("and the moved note is still at its song position", right[0][0], 31.0, 0.0001)


func _test_notes_ride_the_wire_with_their_item() -> void:
	var a := _item(4.0, 2.0, "Keys")
	a.notes = MidiTake.pack_relative([[4.5, 5.0, 60, 100, 0]], 4.0)
	var b := _item(8.0, 1.0, "Audio")
	var packed := MixWire._pack_items([a, b])
	check("an item with notes carries them, one without does not (%d entries)" % packed.size(),
			packed.size() == 11)
	var back := MixWire._unpack_items(packed)
	check("both come back, the second still the second", back.size() == 2 and back[1].name == "Audio")
	check("with the notes on the first", back[0].notes == a.notes and back[1].notes.is_empty())
	var legacy := MixWire._unpack_items([1.0, 2.0, 0.0, "Old", 0.0, 3.0, 1.0, 0.0, "Older", 1.0])
	check("a lane from a sender that knows nothing of notes reads as it always did",
			legacy.size() == 2 and legacy[1].name == "Older" and legacy[1].selected)


func _test_reaper_is_asked_for_a_take_in_one_flat_call() -> void:
	var args := ReaperBackend.midi_take_request(4, 12.5, 14.0,
			[[12.75, 13.0, 60, 100, 0], [13.25, 13.9, 67, 80, 2]], "Grace, take [2]")
	check("the bridge gets one flat list: track, start, end, name, count, then five per note",
			args.size() == 5 + 10 and args[0] == 4 and args[3] == "Grace take 2" and args[4] == 2
			and args[5] == 12.75 and args[14] == 2)
	check("with nothing in it the bridge's decoder would split or end on",
			not JSON.stringify(args).trim_prefix("[").trim_suffix("]").contains("[")
			and not (args[3] as String).contains(","))

	var link := _fresh_link()
	check("without the bridge, Reaper cannot take MIDI", not link.can(DAWBackend.Capability.MIDI_TAKES))
	link.state.track(4)
	link.insert_midi_take(4, 1.0, 2.0, [[1.0, 1.5, 60, 100, 0]], "x")
	check("and a take is not pretended onto its timeline", link.state.track(4).items.is_empty())

	# A MIDI item comes back from the bridge with its notes, relative to the item.
	link._on_timeline({"length": 60.0, "markers": [], "tracks": [{"index": 4, "items": [
			{"start": 12.5, "length": 1.5, "muted": false, "name": "Grace take 2", "selected": false,
			"notes": [0.25, 0.5, 60, 100, 0]}]}]})
	var item := link.state.item(4, 0)
	check("Reaper's own copy of a take arrives with its notes", item != null and item.notes.size() == 5)
	link.free()


## The guest's own piano. Rendered straight, as the suite has no sound card: what matters is that
## a key makes a sound, the sound is a sane level, it dies when let go, and a fistful of keys
## does not run out of voices into silence or into noise.
func _test_the_monitor_piano_sounds_decays_and_shares_its_voices() -> void:
	var synth := MonitorSynth.new()
	add_child(synth)
	synth.note_on(60, 100)
	var first := synth.render(4800)
	var peak := 0.0
	var finite := true
	for f in first:
		peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
		finite = finite and is_finite(f.x) and is_finite(f.y)
	check("a key makes a sound (peak %.3f)" % peak, peak > 0.05)
	check("at a level that leaves room for the mix", peak < 0.9 and finite)
	check("it starts without a click: the first frame is near silent", absf(first[0].x) < 0.01)
	var soft := MonitorSynth.new()
	add_child(soft)
	soft.note_on(60, 20)
	var soft_peak := 0.0
	for f in soft.render(4800):
		soft_peak = maxf(soft_peak, absf(f.x))
	check("a light touch is properly quieter (%.3f against %.3f)" % [soft_peak, peak], soft_peak < peak * 0.5)
	soft.free()
	synth.note_off(60)
	synth.render(48000)
	check("let go, it dies away", synth.sounding() == 0)
	for p in 24:
		synth.note_on(40 + p, 110)
	var full := synth.render(2400)
	var full_peak := 0.0
	finite = true
	for f in full:
		full_peak = maxf(full_peak, absf(f.x))
		finite = finite and is_finite(f.x)
	check("twenty-four keys share sixteen voices", synth.sounding() == MonitorSynth.VOICES)
	check("and a fistful saturates rather than clips (%.3f)" % full_peak, full_peak < 1.0 and finite)
	synth.enabled = false
	synth.note_on(72, 100)
	synth.render(48000 * 4)
	check("turned off, keys make no sound", synth.sounding() == 0)
	check("with no sound card there is no latency to stamp around", synth.latency_seconds() == 0.0)
	synth.free()


func _test_the_computer_keys_are_a_piano_by_position() -> void:
	var keys := KeyCatcher.new()
	var played: Array = []
	keys.note_on.connect(func(p: int, v: int): played.append(["on", p, v]))
	keys.note_off.connect(func(p: int): played.append(["off", p]))
	check("A is middle C", keys.handle(KEY_A, true) and played.back() == ["on", 60, KeyCatcher.VELOCITY])
	keys.handle(KEY_W, true)
	check("the row above is the black keys", played.back()[1] == 61)
	keys.handle(KEY_APOSTROPHE, true)
	check("and the home row runs on to the F above", played.back()[1] == 77)
	keys.handle(KEY_X, true)
	keys.handle(KEY_A, false)
	check("a key let go after an octave change stops the note it started", played.back() == ["off", 60])
	keys.handle(KEY_A, true)
	check("X is an octave up", played.back()[1] == 72 and keys.octave_name() == "C5")
	check("keys the piano does not use are left for the studio", not keys.handle(KEY_V, true)
			and not keys.handle(KEY_SPACE, true))
	for i in 10:
		keys.handle(KEY_Z, true)
	check("Z goes down, and not off the bottom", keys.base == KeyCatcher.LOWEST_C)
	played.clear()
	keys.release_all()
	check("giving the keys back lets go of everything still down", played.size() == 3
			and played.all(func(e): return e[0] == "off"))
	keys.free()


## A take begins when the guest HEARS the host start recording and ends when it hears it stop,
## and each note carries the song position the guest was hearing when it was played.
func _test_a_guest_take_follows_the_host_transport_it_hears() -> void:
	var backend := _offline()
	var gm := GuestMidi.new()
	add_child(gm)
	var now := {"seconds": 40.0, "playing": true, "recording": true, "valid": true}
	gm.heard_source = func(): return now.duplicate()
	gm.follow(now)
	check("no track chosen, nothing is taken", not gm.is_recording())
	gm.target_track = 7
	gm.note_on(55, 80)
	gm.follow(now)
	check("a track chosen and recording heard, a take begins", gm.is_recording())
	check("a key already down is in the take from its first moment", gm.take_note_count() == 1)
	now["seconds"] = 40.5
	gm.note_on(62, 90)
	now["seconds"] = 41.0
	gm.note_off(62)
	gm.note_off(55)
	now["seconds"] = 41.25
	gm.note_on(65, 70)
	gm.follow(now)
	now["seconds"] = 42.0
	gm.follow(now)
	var before := DAW.state.track(7).items.size()
	now["recording"] = false
	now["seconds"] = 42.02
	gm.follow(now)
	check("recording heard to stop, the take is sent", not gm.is_recording())
	check("as one item on the chosen track", DAW.state.track(7).items.size() == before + 1)
	var item: MixState.ItemState = null
	for it in DAW.state.track(7).items:
		if it.name.ends_with(" take 1"):
			item = it
	if item != null:
		close_to("the item starts where recording was heard to start", item.start, 40.0)
		close_to("and ends where it was last heard running", item.end(), 42.0)
		var notes := MidiTake.unpack_relative(item.notes, item.start)
		check("with every note (%s)" % [notes], notes.size() == 3)
		if notes.size() == 3:
			check("each at the song position heard when it was played",
					is_equal_approx(notes[1][0], 40.5) and is_equal_approx(notes[1][1], 41.0)
					and notes[1][2] == 62 and notes[1][3] == 90)
			check("and a note still down at the end closed there",
					notes[2][2] == 65 and is_equal_approx(notes[2][1], 42.0))
	check("the panel is told what the take did", gm.last_take.get("notes", 0) == 3)
	gm.follow(now)
	check("one stop is one take", DAW.state.track(7).items.size() == before + 1)
	gm.free()


func _test_the_host_places_a_guest_take_and_says_so() -> void:
	_offline()
	var told: Array = []
	var listen := func(text: String): told.append(text)
	Session.notice.connect(listen)
	var before := DAW.state.track(3).items.size()
	Session._place_take(1, [3, 8.0, 10.0, [[8.5, 9.0, 60, 100, 0]], "Grace take 1"])
	check("a guest's take is placed", DAW.state.track(3).items.size() == before + 1)
	check("and the room is told where (%s)" % [told], told.size() == 1 and (told[0] as String).contains("1 note onto %s at %s." % [DAW.state.track(3).display_name(), DAW.state.bar_beat(8.0)]))
	Session._place_take(1, [99, 8.0, 10.0, [[8.5, 9.0, 60, 100, 0]], "Grace take 2"])
	check("a take for a track that is not there is refused out loud (%s)" % [told],
			told.size() == 2 and (told[1] as String).contains("was not placed"))
	Session.notice.disconnect(listen)


func _test_midi_items_show_their_notes_on_the_timeline() -> void:
	_offline()
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)
	var notes := timeline.get_node_or_null("ItemNotes") as MeshBank
	var blocks := timeline.get_node_or_null("ItemBlocks") as MeshBank
	check("MIDI items get a piano roll, in one object", notes != null and notes.count() > 0)
	if notes == null or blocks == null:
		timeline.free()
		return
	var drawn := notes.multimesh.visible_instance_count
	check("drawn where the window is (%d of %d)" % [drawn, notes.count()], drawn > 0)
	# Every drawn note sits inside some drawn item block.
	var inside := true
	for i in drawn:
		var at := notes.transform_of(i)
		var held := false
		for b in blocks.multimesh.visible_instance_count:
			var box := blocks.transform_of(b)
			var half := box.basis.get_scale() * 0.5
			var half_note := at.basis.get_scale() * 0.5
			if at.origin.x - half_note.x >= box.origin.x - half.x - 0.00001 \
					and at.origin.x + half_note.x <= box.origin.x + half.x + 0.00001 \
					and absf(at.origin.y - box.origin.y) + half_note.y <= half.y:
				held = true
				break
		inside = inside and held
	check("and every note is on its item, inside the block", inside)
	timeline._on_view_changed(100000.0, timeline.view_span)
	check("scrolled away, no notes are drawn", notes.multimesh.visible_instance_count == 0)
	timeline.free()
	var thin := TimelineSurface.note_layout(PackedFloat32Array([0, 1, 60, 90, 0, 1, 2, 62, 90, 0]))
	check("two notes a tone apart are drawn on an octave's rows, not stretched to fill",
			thin["rows"] == 12 and thin["low"] <= 60 and thin["low"] + thin["rows"] > 62)
	var wide := TimelineSurface.note_layout(PackedFloat32Array([0, 1, 36, 90, 0, 1, 2, 84, 90, 0]))
	check("a wide part gets a row per semitone it spans", wide["low"] == 36 and wide["rows"] == 49)


func _test_a_recorded_take_is_a_wav_with_an_overview() -> void:
	var take := AudioTake.create("suite-take.wav")
	check("a take is a file in the takes folder", take != null and take.path.begins_with(AudioTake.DIR))
	if take == null:
		return
	var second := PackedVector2Array()
	second.resize(AudioTake.RATE)
	for i in second.size():
		second[i] = Vector2(0.5, 0.3) if i < AudioTake.RATE / 2 else Vector2.ZERO
	check("written as it arrives", take.append(AudioTake.encode(second)))
	take.finish()
	var bytes := FileAccess.get_file_as_bytes(take.path)
	check("a whole RIFF/WAVE file, its sizes filled in (%d bytes)" % bytes.size(),
			bytes.size() == AudioTake.HEADER_BYTES + AudioTake.RATE * 2
			and bytes.decode_u32(0) == 0x46464952 and bytes.decode_u32(40) == AudioTake.RATE * 2
			and bytes.decode_u32(24) == AudioTake.RATE and bytes.decode_u16(22) == 1)
	check("one channel, the two sides of the input averaged",
			bytes.decode_s16(AudioTake.HEADER_BYTES) == int(round(0.4 * 32767.0)))
	var wav := AudioStreamWAV.load_from_file(take.path)
	check("and Godot opens it", wav != null and is_equal_approx(wav.get_length(), 1.0))
	var peaks := take.peaks()
	check("with an overview of 50 a second (%d)" % peaks.size(), peaks.size() == AudioTake.PEAKS_PER_SECOND)
	check("loud where the sound is and silent where it is not",
			peaks[0] == int(round(0.4 * 32767.0) / 128.5) and peaks[AudioTake.PEAKS_PER_SECOND - 1] == 0)
	take.discard()
	check("and a discarded take leaves nothing behind", not FileAccess.file_exists(take.path))
	var named := AudioTake.file_name_for("Zoë/../D'Arcy", 3)
	check("a file name every disk takes (%s)" % named, not named.contains("/") and not named.contains("'")
			and named.begins_with("Zo__") and named.ends_with(".wav") and named.contains("take3"))


func _test_the_host_places_an_audio_take() -> void:
	var backend := _offline(13)
	var peaks := PackedByteArray([10, 200, 30])
	DAW.insert_audio_take(6, 12.0, "../../etc/nonsense/x.wav", 3.0, peaks, "Grace audio 1")
	var lane: Array = DAW.state.track(6).items
	var at := lane.find_custom(func(it): return it.name == "Grace audio 1")
	var item: MixState.ItemState = lane[at] if at >= 0 else MixState.ItemState.new()
	check("the host's take is an item where it was played", item.start == 12.0 and item.length == 3.0
			and item.name == "Grace audio 1")
	check("naming its file, never a path", item.source == "x.wav")
	check("and carrying its overview", item.peaks == peaks)
	var round_trip: Array = MixWire._unpack_items(MixWire._pack_items(DAW.state.track(6).items))
	var back: MixState.ItemState = round_trip[at] if at >= 0 else MixState.ItemState.new()
	check("which travels with the item", back.source == "x.wav" and back.peaks == peaks
			and back.start == 12.0)
	check("and a lane from before takes carries none", (MixWire._unpack_items(
			[1.0, 2.0, 0.0, "old", 0.0]) [0] as MixState.ItemState).source == "")

	DAW.select_item(6, at, false)
	DAW.split_selected(13.25)
	var halves: Array = DAW.state.track(6).items.filter(func(it): return it.source == "x.wav")
	var right: MixState.ItemState = halves[0] if halves[0].start > 12.0 else halves[1]
	check("cut, its right half plays on from where the cut was", halves.size() == 2
			and absf(right.source_offset - 1.25) < 0.0001)
	DAW.undo()
	DAW.undo()
	check("and one undo takes the take off", DAW.state.track(6).items.all(func(it): return it.source == ""))

	var before: int = DAW.state.track(6).items.size()
	DAW.apply_intent(&"insert_audio_take", [6, 1.0, "x.wav", 1.0, PackedByteArray(), "sneaky"])
	check("a guest cannot name a file for the host to place", DAW.state.track(6).items.size() == before)
	check("a take for a track that is not there is refused in words",
			DAW.audio_take_refusal(99, 1.0).begins_with("There is no track 99"))
	DAW.insert_audio_take(99, 1.0, "x.wav", 1.0, PackedByteArray(), "lost")
	check("and nothing happens", DAW.state.tracks.values().all(func(t): return t.items.all(
			func(it): return it.name != "lost")))
	check("an empty take is refused too", DAW.audio_take_refusal(6, 0.0) == "The take had no sound in it.")


## A microphone that is a perfect player's: a clap every second of its own clock.
class _FakeMic extends MixSource:
	var made := 0
	var latency := 0.01

	func read() -> PackedVector2Array:
		var out := PackedVector2Array()
		out.resize(480)
		for i in 480:
			if (made + i) % 48000 < 24:
				out[i] = Vector2(0.9, 0.9)
		made += 480
		return out

	func latency_ms() -> float:
		return latency * 1000.0

	func rate() -> float:
		return 48000.0


class _TakeRecorder extends RefCounted:
	var start := NAN
	var pcm := PackedByteArray()
	var ended := false

	func send_audio_begin(_id: int, _track: int, at: float, _name: String) -> void:
		start = at

	func send_audio_chunk(_id: int, bytes: PackedByteArray) -> void:
		pcm.append_array(bytes)

	func send_audio_end(_id: int) -> void:
		ended = true


func _test_a_guest_microphone_stays_on_the_song() -> void:
	# The song runs 300 parts per million faster than the microphone's clock, and the take
	# begins 0.3s before the top of the song -- a take started at zero and heard late.
	var drift := 300e-6
	var song := func(wall: float) -> float: return -0.3 + wall * (1.0 + drift)
	var ga := GuestAudio.new()
	var rec := _TakeRecorder.new()
	var mic := _FakeMic.new()
	ga.sink = rec
	ga.target_track = 3
	ga._source = mic
	var ticks := 1500
	for tick in ticks:
		var got := ga._read()
		# The newest frame left the microphone mic.latency before this read.
		var read_at := float(mic.made - 1) / 48000.0 + mic.latency
		ga.follow({"seconds": song.call(read_at), "playing": true, "recording": tick < ticks - 1,
				"valid": true}, got)
	check("the take was sent and ended", rec.ended and not is_nan(rec.start))
	check("nothing from before the song's first moment (%.5f)" % rec.start,
			rec.start >= 0.0 and rec.start < 1.0 / 48000.0 * 2.0)
	close_to("the loop found the clocks' difference (%.0f ppm)" % ga.drift_ppm(), ga.drift_ppm(), 300.0, 60.0)
	var worst := 0.0
	var claps := 0
	var last := -48000
	for i in range(0, rec.pcm.size() - 1, 2):
		var k := i / 2
		if rec.pcm.decode_s16(i) > 16000 and k - last > 24000:
			last = k
			var placed := rec.start + float(k) / 48000.0
			# Which clap of the microphone's this is: the one nearest in its own clock.
			var wall := roundf(placed / (1.0 + drift) + 0.3)
			if wall >= 3.0:
				worst = maxf(worst, absf(placed - song.call(wall)))
			claps += 1
	check("every clap of a 15 second take is there (%d)" % claps, claps >= 14)
	check("and each where the song was when it was made, once settled (worst %.3fms)" % (worst * 1000.0),
			worst < 0.0005)


func _test_the_built_in_engine_plays_a_recorded_take() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var take := AudioTake.create("suite-engine-take.wav")
	var tone := PackedVector2Array()
	tone.resize(AudioTake.RATE * 2)
	for i in tone.size():
		tone[i] = Vector2.ONE * sin(TAU * 220.0 * i / AudioTake.RATE) * 0.5
	take.append(AudioTake.encode(tone))
	take.finish()
	DAW.insert_audio_take(6, 300.0, take.file_name(), take.seconds(), take.peaks(), "Grace audio 1")
	DAW.state.position_seconds = 300.5
	DAW.state.playing = true
	backend._sync_players()
	var own: AudioStreamPlayer = backend._players[6][0]
	check("a recorded take plays on its track's bus",
			own.playing and own.stream == backend.take_stream(take.file_name()) and own.stream != null)
	DAW.state.position_seconds = 302.5
	backend._sync_players()
	check("and stops where the take does", not own.playing)
	DAW.state.playing = false
	_offline()
	take.discard()


func _test_a_guest_sets_up_their_microphone_from_the_panel() -> void:
	_offline()
	_as_session(Session.Role.GUEST, 5)
	var ga := Session.guest_audio
	var made_source := ga.make_source
	ga.make_source = func() -> MixSource: return _FakeMic.new()
	var panel := SessionPanel.new()
	add_child(panel)
	panel.open()
	check("the microphone is opt-in: no track, not recording",
			ga.target_track == 0 and not ga.record_with_host and not ga.mic_open())
	check("and the panel says what to do first (%s)" % panel._mic_status.text,
			panel._mic_status.text.begins_with("Choose a track"))
	var eight := panel._mic_into.get_item_index(8)
	check("every track of the project is offered", eight > 0
			and panel._mic_into.item_count == DAW.state.track_indices().size() + 1)
	panel._mic_into.select(eight)
	panel._mic_into.item_selected.emit(eight)
	check("choosing one is the track the take goes onto", ga.target_track == 8)
	check("which still records nothing until asked (%s)" % panel._mic_status.text,
			panel._mic_status.text == "Your microphone is off.")
	panel._mic_record.button_pressed = true
	check("asked, it records with the host", ga.record_with_host)
	ga._process(0.016)
	check("and the microphone opens, so the level shows before the take", ga.mic_open())
	panel._refresh_mic()
	check("ready, and says where it will go (%s)" % panel._mic_status.text,
			panel._mic_status.text.contains("Gtr") or panel._mic_status.text.begins_with("Ready"))
	check("the keys' and the microphone's switches say which is which",
			panel._mic_record.text.contains("mic") and panel._record_with.text.contains("keys"))
	ga.record_with_host = false
	ga.target_track = 0
	ga._process(0.016)
	check("turned off, the microphone closes", not ga.mic_open())
	ga.make_source = made_source
	remove_child(panel)
	panel.free()
	Session.start_solo()


func _test_a_recorded_take_shows_its_waveform_on_the_timeline() -> void:
	# Two seconds: quiet, then loud.
	var peaks := PackedByteArray()
	for i in 2 * AudioTake.PEAKS_PER_SECOND:
		peaks.append(20 if i < AudioTake.PEAKS_PER_SECOND else 240)
	var cols := TimelineSurface.wave_columns(peaks, 0.0, 10.0, 2.0, 0.0, 0.2, -1.0, 1.0, 0.01)
	check("a column every centimetre of a 20cm take (%d)" % cols.size(), cols.size() == 20)
	check("quiet where the take is quiet and loud where it is loud",
			cols[2][1] < 0.1 and cols[17][1] > 0.9)
	var right_half := TimelineSurface.wave_columns(peaks, 1.0, 11.0, 1.0, 0.0, 0.1, -1.0, 1.0, 0.01)
	check("the right half of a cut take draws its own, loud, part",
			right_half.all(func(c): return c[1] > 0.9))
	var clipped := TimelineSurface.wave_columns(peaks, 0.0, 10.0, 2.0, 0.0, 0.2, 0.1, 0.15, 0.01)
	check("and only where the window shows it", clipped.size() == 5
			and clipped.all(func(c): return c[0] >= 0.1 and c[0] <= 0.15))

	_offline().open()
	DAW.insert_audio_take(8, 2.0, "suite-wave.wav", 2.0, peaks, "Grace audio 1")
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)
	timeline._on_view_changed(0.0, 8.0)
	var waves := timeline.get_node_or_null("ItemWaves") as MeshBank
	check("a recorded take gets a waveform, in one object", waves != null and waves.count() > 0)
	if waves != null:
		var drawn := waves.multimesh.visible_instance_count
		var tallest := 0.0
		var shortest := INF
		for i in drawn:
			var h := waves.transform_of(i).basis.get_scale().y
			tallest = maxf(tallest, h)
			shortest = minf(shortest, h)
		check("drawn across it (%d columns)" % drawn, drawn > 10)
		check("its loud second taller than its quiet one (%.1fx)" % (tallest / shortest), tallest > shortest * 3.0)
		check("and no taller than its lane", tallest < TimelineSurface.LANE_HEIGHT)
	timeline.free()
	_offline()


func _test_a_ghost_is_the_size_of_a_large_person() -> void:
	var ghost := Presence.Avatar.new()
	add_child(ghost)
	ghost._pose = Transform3D(Basis.IDENTITY, Vector3(0, 1.62, 0))
	ghost._place()
	# Hands at its sides, where they float, not both still at the origin they were made at.
	ghost._aim_hands()
	for glove in ghost._hands:
		glove.step(0.0)
	var box := AABB()
	var first := true
	for m in ghost.find_children("*", "MeshInstance3D", true, false):
		# The gloves float free of the body; they are measured on their own.
		if not m.is_visible_in_tree() or m.top_level or m.find_parent("*Hand") != null:
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	# A standing person's eye is at 1.62m, the top of their head ~1.75m, the desk ~0.75m.
	check("a little taller than the person it stands for (dome at %.2fm)" % box.end.y,
			box.end.y > 1.75 and box.end.y < 1.95)
	check("its hem near the desk, not on the floor or over the gear (%.2fm)" % box.position.y,
			box.position.y > 0.7 and box.position.y < 1.05)
	var body := ghost._lean.get_child(0) as MeshInstance3D
	var girth: float = (body.global_transform * body.get_aabb()).size.x
	check("rotund, but about as wide as a person, arms aside (%.2fm)" % girth, girth > 0.45 and girth < 0.6)
	check("its skin takes no shadow from itself, which crawls as it sways",
			Presence.Avatar.SKIN_SHADER.contains("shadows_disabled"))
	var hits := ZFightProbe.scan(ghost)
	check("and no two of its faces share a plane (%d)" % hits.size(), hits.is_empty())
	remove_child(ghost)
	ghost.free()


func _test_a_glove_flies_with_a_bounce() -> void:
	var glove := Glove.new(1.0)
	add_child(glove)
	glove.step(0.0)
	glove.target = Transform3D(Basis.IDENTITY, Vector3(0.5, 0, 0))
	var furthest := 0.0
	for i in 120:
		glove.step(1.0 / 60.0)
		furthest = maxf(furthest, glove.global_position.x)
	check("it flies past where it was sent, and comes back (%.3fm over)" % (furthest - 0.5),
			furthest > 0.52 and furthest < 0.65)
	check("and settles there (%.4fm off)" % absf(glove.global_position.x - 0.5),
			absf(glove.global_position.x - 0.5) < 0.002)
	glove.poke(-0.6)
	var low := 0.0
	var high := 0.0
	for i in 30:
		glove.step(1.0 / 60.0)
		low = minf(low, glove.squash)
		if low < -0.1:
			high = maxf(high, glove.squash)
	check("a grab squashes it (%.2f) and it boings back past round (%.2f)" % [low, high],
			low < -0.2 and high > 0.03)
	for i in 120:
		glove.step(1.0 / 60.0)
	check("before it settles round again (%.3f)" % glove.squash, absf(glove.squash) < 0.01)
	var open := glove.curls()
	glove.pose = Glove.Pose.POINT
	for i in 60:
		glove.step(1.0 / 60.0)
	var pointing := glove.curls()
	check("pointing, the index stays out and the rest curl (%.2f vs %.2f)" % [pointing[0], pointing[1]],
			pointing[0] < 0.3 and pointing[1] > 1.0)
	glove.pose = Glove.Pose.GRIP
	for i in 60:
		glove.step(1.0 / 60.0)
	var gripping := glove.curls()
	check("gripping, every finger curls (%.2f index)" % gripping[0],
			gripping[0] > 1.0 and gripping[0] > open[0] + 0.7)
	var hits := ZFightProbe.scan(glove)
	check("no two of its faces share a plane (%d)" % hits.size(), hits.is_empty())
	remove_child(glove)
	glove.free()


func _test_a_ghosts_hand_goes_to_what_they_touch() -> void:
	var ghost := Presence.Avatar.new()
	add_child(ghost)
	ghost.snap(Transform3D(Basis.IDENTITY, Vector3(0, 1.62, 0)))
	var right: Glove = ghost._hands[1]
	var settle := func(seconds: float) -> void:
		for i in roundi(seconds * 60.0):
			ghost._process(1.0 / 60.0)
			for glove in ghost._hands:
				glove.step(1.0 / 60.0)
	settle.call(1.0)
	var rest := right.global_position
	check("it has two hands and no arms", ghost._hands.size() == 2)
	check("the right floats at its right, beside its belly (%.2f, %.2f)" % [rest.x, rest.y],
			rest.x > 0.25 and rest.x < 0.5 and rest.y > 1.2 and rest.y < 1.45)
	var control := ControlAffordance.new()
	add_child(control)
	control.position = Vector3(0.3, 1.0, -0.6)
	var spot := Vector3(0.3, 1.0, -0.6)
	ghost.point_at(control, spot, false)
	settle.call(1.5)
	ghost.point_at(control, spot, false)
	check("pointing at something in reach, its fingertip goes to it (%.3fm off)" % right.fingertip().distance_to(spot),
			right.fingertip().distance_to(spot) < 0.04)
	check("with no beam to draw", not ghost._beam.visible)
	ghost.point_at(control, spot, true)
	check("and taking hold squashes it", right._squash_speed < -5.0)
	settle.call(1.5)
	check("then it grips (%.2f)" % right.curls()[0], right.curls()[0] > 1.0)
	check("palm on it (%.3fm off)" % right.global_position.distance_to(spot),
			right.global_position.distance_to(spot) < 0.08)
	var far := Vector3(3.0, 1.0, -4.0)
	ghost.point_at(control, far, false)
	settle.call(1.5)
	ghost.point_at(control, far, false)
	check("out of reach, it goes only as far as it can (%.2fm)" % right.global_position.distance_to(rest),
			right.global_position.distance_to(rest) < Presence.Avatar.REACH + 0.05)
	check("and the beam carries the rest", ghost._beam.visible)
	ghost.point_at(null, Vector3.ZERO, false)
	settle.call(2.0)
	var home := ghost._rest(1.0).origin
	check("let go of, it comes home (%.3fm off)" % right.global_position.distance_to(home),
			right.global_position.distance_to(home) < 0.03)
	var hits := ZFightProbe.scan(ghost)
	check("nothing on the ghost shares a plane with its gloves (%d)" % hits.size(), hits.is_empty())
	remove_child(ghost)
	ghost.free()
	control.free()

	var mine := Presence.Avatar.new()
	add_child(mine)
	mine.only_in_mirrors()
	var drawn := true
	for m in mine._hands[1].find_children("*", "MeshInstance3D", true, false):
		drawn = drawn and (m as MeshInstance3D).layers == Mirror.SELF_ONLY
	check("your own gloves are drawn only in mirrors", drawn)
	remove_child(mine)
	mine.free()


func _test_a_look_is_kept_and_cleaned() -> void:
	check("a look with nothing in it is the default", GhostLook.clean({}) == GhostLook.default_look())
	var odd := GhostLook.clean({"hat": 99, "body": -3, "eyes": 2.0, "cape": 1})
	check("out-of-range choices are pulled into range, and unknown ones dropped",
			odd["hat"] == GhostLook.HATS.size() - 1 and odd["body"] == 0 and odd["eyes"] == 2
			and not odd.has("cape"))
	check("not even a dictionary is still a look", GhostLook.clean("nonsense") == GhostLook.default_look())
	var last := GhostLook.stepped(GhostLook.default_look(), "hat", -1)
	check("stepping back from the first hat wraps to the last (%s)" % GhostLook.label(last, "hat"),
			last["hat"] == GhostLook.HATS.size() - 1)
	check("and forward from the last wraps to none",
			GhostLook.label(GhostLook.stepped(last, "hat", 1), "hat") == "None")
	check("every body has a colour", GhostLook.BODIES.size() == GhostLook.BODY_COLOURS.size())
	var path := OS.get_temp_dir().path_join("reaper3d_test_look_%d.cfg" % OS.get_process_id())
	var mine := {"body": 3, "eyes": 1, "hat": 4, "gloves": 2}
	GhostLook.save_to(mine, path)
	check("a look survives being put away", GhostLook.load_from(path) == mine)
	DirAccess.remove_absolute(path)
	check("with nothing put away, the default", GhostLook.load_from(path) == GhostLook.default_look())


func _test_the_roster_carries_what_everyone_wears() -> void:
	var was_path := Session.look_path
	var was_look := Session.local_look
	Session.look_path = ""
	_as_session(Session.Role.GUEST, 5)
	var hers := {"body": 2, "eyes": 3, "hat": 2, "gloves": 3}
	Session.apply_roster([[1, "Ada", 0, 0, hers], [5, "Grace", 0, 1, GhostLook.default_look()]])
	check("a guest is told what the host wears", Session.participants[1].look == hers)
	Session.apply_roster([[1, "Ada", 0, 0], [5, "Grace", 0, 1]])
	check("a host from before looks dresses everyone in the default",
			Session.participants[1].look == GhostLook.default_look())
	Session.start_solo()
	var changed := [0]
	var count := func() -> void: changed[0] += 1
	Session.roster_changed.connect(count)
	Session.set_look({"hat": 3})
	Session.roster_changed.disconnect(count)
	check("dressing myself is mine at once", Session.local_participant().look["hat"] == 3
			and Session.local_look["hat"] == 3)
	check("and redraws the ghosts", changed[0] == 1)
	var rows := Session._roster_rows()
	check("and goes out in the roster", rows[0].size() == 5 and rows[0][4]["hat"] == 3)
	Session.set_look(was_look)
	Session.look_path = was_path


func _test_a_ghost_wears_its_look() -> void:
	var ghost := Presence.Avatar.new()
	add_child(ghost)
	ghost.snap(Transform3D(Basis.IDENTITY, Vector3(0, 1.62, 0)))
	ghost._aim_hands()
	for glove in ghost._hands:
		glove.step(0.0)
	ghost.dress("Ada", Session.PALETTE[0], 0, true, {"body": 5})
	var body: Color = ghost._skin.get_shader_parameter("body")
	check("the body takes the look's colour (%s)" % body,
			body.g > body.b and body.is_equal_approx(GhostLook.BODY_COLOURS[5].lerp(Session.PALETTE[0], 0.12)))
	var dome := 1.62 + Presence.Avatar.TOP * Presence.Avatar.SIZE
	for i in GhostLook.HATS.size():
		var hat: String = GhostLook.HATS[i]
		ghost.dress("Ada", Session.PALETTE[0], 0, true, {"hat": i})
		ghost._place()
		var parts := ghost._hat.get_children().filter(func(n): return not n.is_queued_for_deletion())
		if hat == "None":
			check("no hat is nothing on the head", parts.is_empty())
			continue
		var top := -INF
		for m in ghost._hat.find_children("*", "MeshInstance3D", true, false):
			if m.is_queued_for_deletion() or m.get_parent().is_queued_for_deletion():
				continue
			top = maxf(top, (m.global_transform * m.get_aabb()).end.y)
		check("the %s sits on top of the dome (%.2f over it)" % [hat, top - dome], top > dome + 0.01)
		check("and the name floats over the %s" % hat, ghost._tag.global_position.y > top)
		var hits := ZFightProbe.scan(ghost._hat)
		check("the %s has no two faces in one plane (%d)" % [hat, hits.size()], hits.is_empty())
	ghost.dress("Ada", Session.PALETTE[0], 0, true, {"eyes": GhostLook.EYES.find("Wide")})
	check("wide eyes open the lids", ghost._lid_rest > Presence.Avatar.LID_AWAKE)
	ghost.dress("Ada", Session.PALETTE[0], 0, true, {"eyes": GhostLook.EYES.find("Grumpy")})
	ghost._process(0.016)
	check("grumpy ones tilt them in", absf(ghost._lids[0].rotation.z) > 0.2
			and signf(ghost._lids[0].rotation.z) != signf(ghost._lids[1].rotation.z))
	ghost.dress("Ada", Session.PALETTE[0], 0, true, {"gloves": GhostLook.GLOVES.find("Gold")})
	check("gold gloves are metal", ghost._hands[0]._cloth.metallic > 0.5)
	ghost.dress("Ada", Session.PALETTE[0], 0, true, {"gloves": GhostLook.GLOVES.find("My colour")})
	check("and theirs are their colour", ghost._hands[1]._cloth.albedo_color.is_equal_approx(
			Session.PALETTE[0].lightened(0.2)))
	remove_child(ghost)
	ghost.free()

	var mine := Presence.Avatar.new()
	add_child(mine)
	mine.only_in_mirrors()
	mine.dress("Me", Session.PALETTE[1], 0, true, {"hat": GhostLook.HATS.find("Crown")})
	var hidden := mine._hat.find_children("*", "MeshInstance3D", true, false).all(
			func(m): return m.is_queued_for_deletion() or m.layers == Mirror.SELF_ONLY)
	check("a hat put on in the mirror is only in the mirror too", hidden)
	remove_child(mine)
	mine.free()


func _test_the_wardrobe_changes_my_look() -> void:
	var board := Wardrobe.new()
	add_child(board)
	var told: Array = []
	board.look_changed.connect(func(look): told.append(look))
	board.press("hat", 1)
	check("next hat puts one on", told.size() == 1 and told[0]["hat"] == 1)
	check("and the board says which (%s)" % board._values["hat"].text,
			board._values["hat"].text == GhostLook.HATS[1])
	board.press("body", -1)
	check("back from the first body is the last", board.look["body"] == GhostLook.BODIES.size() - 1)
	check("its swatch shows it", board._swatch.albedo_color.is_equal_approx(GhostLook.BODY_COLOURS[-1]))
	var button: Wardrobe.Choice = board._buttons[0]
	check("its buttons are mine alone", button.personal() and not ControlAffordance.new().personal())
	check("and say what they do", button.title() == "BODY  BACK")
	var presence := Presence.new()
	add_child(presence)
	presence._on_grabbed(button, Interactor.new())
	check("grabbing one claims nothing in the session", presence._my_claims.is_empty())
	remove_child(presence)
	presence.free()
	board.look = {"eyes": 2}
	check("set from outside, it shows what I already wear", board._values["eyes"].text == GhostLook.EYES[2])
	remove_child(board)
	board.free()


func _test_a_mirror_shows_the_room_reversed() -> void:
	# A glass 0.6 x 1.6 on the left wall, facing +X, centre 0.94m up; an eye in the room.
	var glass := Vector2(0.6, 1.6)
	var at := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-3.0, 0.94, 2.2))
	var eye := Vector3(-1.2, 1.62, 1.4)
	var r := Mirror.reflection(at, glass, eye)
	check("the camera stands at the eye reflected through the glass",
			r["transform"].origin.is_equal_approx(Vector3(-4.8, 1.62, 1.4)))
	close_to("its near plane is the glass", r["near"], 1.8, 0.0001)
	# A point in the room, seen in the glass: where the line from the eye to its mirror image
	# crosses the glass is where the reflected camera must put it.
	var thing := Vector3(-2.2, 1.1, 1.9)
	var image := Vector3(-3.8, 1.1, 1.9)
	var through := eye.lerp(image, (eye.x - (-3.0)) / (eye.x - image.x))
	var cam: Transform3D = r["transform"]
	var local := cam.affine_inverse() * thing
	var near: float = r["near"]
	var half_h: float = r["size"] * 0.5
	var half_w := half_h * glass.x / glass.y
	var ndc := Vector2((local.x * near / -local.z - r["offset"].x) / half_w,
			(local.y * near / -local.z - r["offset"].y) / half_h)
	# Texture u runs with the camera's right; the glass draws it at 1 - u.
	var glass_u := 1.0 - (ndc.x + 1.0) * 0.5
	var glass_v := (ndc.y + 1.0) * 0.5
	var drawn_at := at * Vector3((glass_u - 0.5) * glass.x, (glass_v - 0.5) * glass.y, 0.0)
	check("a thing in the room is drawn where its reflection is seen (%.4fm off)" % drawn_at.distance_to(through),
			drawn_at.distance_to(through) < 0.0005)
	check("and nothing is drawn from behind the glass", Mirror.reflection(at, glass,
			Vector3(-3.4, 1.6, 2.2)).is_empty())


func _test_every_venue_has_a_mirror_you_can_see_yourself_in() -> void:
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	check("your own view never draws your own ghost",
			studio.camera.cull_mask & Mirror.SELF_ONLY == 0)
	for id in Venue.IDS:
		studio.set_venue(id, false)
		var mirror := studio.venue.get_node_or_null("Mirror") as Mirror
		check("the %s has a mirror" % id, mirror != null)
		if mirror == null:
			continue
		var at := mirror.global_transform
		var half := studio.room_width * 0.5
		check("inside the %s's footprint, on the floor plan's edge (%s)" % [id, at.origin],
				absf(at.origin.x) < half and at.origin.z < Studio.ROOM_DEPTH * 0.5 + 0.3
				and absf(at.origin.x) > half - 0.4)
		check("facing into the room", at.basis.z.dot(Vector3(0, 0, Studio.MIX_POSITION_Z) - at.origin) > 0.0)
		check("framed in the %s's own style (%d parts)" % [id, mirror.get_child_count()],
				mirror.get_child_count() >= 4)
		check("its camera draws you, and not the panels on your face",
				mirror._camera.cull_mask & Mirror.SELF_ONLY != 0
				and mirror._camera.cull_mask & Mirror.NOT_REFLECTED == 0)
		check("and the glass is not in its own reflection", mirror._glass.layers == Mirror.NOT_REFLECTED)
		check("its glass rolls highlights off rather than handing the room's glow a smear",
				Mirror.GLASS_SHADER.contains("KNEE + over / (1.0 + over * 2.0)"))
		var board := mirror.wardrobe
		check("with a wardrobe beside it", board != null and board.get_parent() == mirror)
		if board != null:
			var y := board.global_position.y
			check("at hand height (%.2fm)" % y, y > 1.05 and y < 1.45)
			var side := board.position.x - Wardrobe.WIDTH * 0.5
			check("clear of the glass (%.2fm from its edge)" % (side - mirror.glass_size.x * 0.5),
					side > mirror.glass_size.x * 0.5 + 0.06)
			check("facing the room too", board.global_basis.z.dot(at.basis.z) > 0.8)
			check("its board in the %s's style" % id, board.board_material != null)
			var hits := ZFightProbe.scan(board)
			check("no two of its faces share a plane (%d)" % hits.size(), hits.is_empty())
			check("the studio dresses me from it", board.look_changed.is_connected(Session.set_look))
	# A panel brought to your face leaves the mirror; sent back to the room, it returns.
	var panel := MeshInstance3D.new()
	studio.screen_stage.add_child(panel)
	check("a panel in front of your face is not reflected", panel.layers == Mirror.NOT_REFLECTED)
	panel.reparent(studio)
	check("and back in the room it is", panel.layers == 1)
	panel.queue_free()

	var presence := studio.presence
	presence._make_reflection()
	presence._sync_avatars()
	var only_mirrors := presence.reflection.find_children("*", "VisualInstance3D", true, false).all(
			func(v): return v.layers == Mirror.SELF_ONLY)
	check("you have a ghost of your own, drawn only in mirrors", only_mirrors)
	presence._process(0.016)
	check("standing where your eye is", presence.reflection.head_position().is_equal_approx(
			presence.head_node.global_position))
	remove_child(studio)
	studio.free()
