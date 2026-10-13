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
	_test_link_offers_reapers_stock_fx_until_the_bridge_answers()
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
	_test_timeline_screen_band_was_widened_but_not_past_the_seat_audit()
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
	_test_the_welcome_card_opens_on_f1_and_is_seen_once()
	_test_plugins_are_added_and_removed_from_the_rack()
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
	_test_rack_unit_name_stays_off_the_header_icons()
	_test_a_wide_desk_bends_round_you_instead_of_past_you()
	_test_the_desk_knows_how_small_its_own_lettering_is()
	_test_every_label_is_set_in_the_distance_field_face()
	_test_fitted_lettering_stays_in_its_slot()
	_test_footprints_separate_by_the_shallowest_way_out()
	_test_furniture_rolls_where_it_is_pushed()
	_test_a_stand_taken_at_eye_height_pushes_naturally()
	_test_you_can_say_how_tall_you_are_in_the_room()
	_test_furniture_is_solid()
	_test_the_wheel_turns_furniture_only_while_held()
	_test_a_summoned_surface_goes_home_to_where_its_stand_went()
	_test_a_monitor_goes_to_the_gear_and_leaves_the_room_alone()
	_test_the_zfight_scan_finds_a_planted_fight()
	_test_no_two_faces_in_the_room_share_a_plane()
	_test_venues_change_the_world_and_not_the_setup()
	_test_every_venue_leaves_room_for_the_activities()
	_test_gear_never_leaves_its_stand()
	await _test_the_mix_and_its_stems_are_rendered_to_files()
	await _test_you_walk_into_the_room_and_not_through_it()
	await _test_a_duck_is_picked_up_squeezed_and_put_down()
	await _test_the_duck_is_the_rooms()
	await _test_personal_items_give_each_player_a_copy_of_their_own()
	await _test_a_ball_is_thrown_and_flies_the_same_everywhere()
	await _test_a_paper_plane_glides()
	await _test_a_throw_is_caught()
	_test_a_mic_arms_a_track_and_puts_it_back()
	await _test_the_mic_lives_in_the_stand_and_is_live_in_a_hand()
	_test_headphones_shut_the_room_out()
	await _test_headphones_go_on_your_head()
	_test_a_personal_mix_adds_up_its_receivers()
	await _test_the_tablet_patches_your_headphones()
	_test_a_track_has_a_cue_for_headphones()
	await _test_a_strip_send_puts_one_track_in_your_headphones()
	await _test_a_players_keys_pack_puts_their_playing_in_your_headphones()
	await _test_their_monitor_plays_their_notes_where_they_heard_them()
	await _test_on_air_puts_a_monitor_socket_on_your_pack()
	await _test_a_shaker_plays_when_a_stroke_stops()
	await _test_percussion_is_heard_by_the_room_and_recorded_onto_the_armed_track()
	await _test_a_keytar_plays_your_keys_and_shows_them()
	await _test_chips_and_cards_do_their_tricks_in_turn()
	await _test_darts_stick_in_the_board_and_score()
	await _test_a_ball_goes_through_the_hoop()
	await _test_the_cradle_swings_and_clacks()
	await _test_the_yoyo_does_its_tricks()
	await _test_each_venue_has_a_toy_of_its_own()
	_test_the_neon_ball_glows_without_blooming_into_one_colour()
	_test_the_beach_ball_does_not_crowd_the_view()
	_test_a_held_keytar_clears_the_console_instead_of_covering_it()
	_test_a_held_cradle_rests_on_the_mouses_glove_instead_of_floating_over_it()
	await _test_pockets_carry_more_than_one_thing()
	await _test_the_radio_plane_flies_where_you_point()
	await _test_somebody_elses_radio_plane_flies_where_they_say()
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
	_test_a_recording_counts_in()
	_test_a_recording_punches_in_and_out()
	_test_a_track_records_from_its_own_input()
	_test_the_time_signature_changes()
	_test_the_demo_song_follows_the_tempo_map()
	_test_the_demo_song_follows_the_meter()
	_test_markers_are_dropped_and_found_from_the_deck()
	_test_input_monitoring_is_set_from_the_strip()
	_test_the_built_in_engine_is_a_real_mix()
	_test_a_project_goes_into_dawkit_and_back()
	_test_saved_data_follows_the_rename()
	_test_a_clip_keeps_its_fades_and_gain()
	_test_the_built_in_engine_saves_and_opens_dawproject()
	_test_the_official_dawproject_examples_open_in_the_game()
	_test_the_project_is_saved_from_the_room_and_the_room_is_told()
	await _test_sound_files_are_brought_in_onto_a_track()
	_test_one_recording_goes_onto_every_armed_track_of_its_input()
	_test_the_host_records_its_own_microphone_on_the_built_in_engine()
	_test_the_host_records_its_own_keys_on_the_built_in_engine()
	_test_a_keytar_reaches_its_track_choice_even_where_reaper_records_its_own_midi()
	_test_hit_recorder_rolls_takes_every_bar()
	_test_a_looped_item_survives_the_wire_and_a_split()
	_test_the_demo_song_loops_on_the_bar()
	_test_a_recorded_take_is_a_wav_with_an_overview()
	_test_the_host_places_an_audio_take()
	_test_a_guest_microphone_stays_on_the_song()
	_test_the_built_in_engine_plays_a_recorded_take()
	_test_the_lanes_hear_the_newest_item_where_items_overlap()
	_test_the_built_in_engine_plays_notes_through_its_instrument()
	_test_items_are_deleted_duplicated_trimmed_and_shaped()
	_test_notes_are_transposed_and_quantised()
	_test_tracks_are_added_removed_and_renamed()
	_test_the_tempo_changes_through_the_song()
	_test_controls_follow_their_automation()
	_test_a_guest_sets_up_their_microphone_from_the_panel()
	_test_each_kind_of_sound_has_its_own_bus()
	await _test_every_sound_leaves_on_its_own_stream()
	await _test_a_named_input_is_read_whole_frames_at_a_time()
	_test_the_keys_helper_plays_the_monitor_synth_note_for_note()
	_test_the_monitor_synth_holds_notes_under_the_pedal()
	_test_the_keys_helper_is_understood()
	_test_a_note_the_helper_heard_is_stamped_when_it_went_down()
	_test_a_recorded_take_shows_its_waveform_on_the_timeline()
	_test_reaper_hears_the_transport_in_its_own_words()
	_test_a_bank_wider_than_the_project_draws_only_the_project()
	_test_the_room_gets_out_of_the_way_of_the_gear_that_left_it()
	_test_the_desk_is_lit_evenly_end_to_end()
	_test_focused_gear_fits_the_frame_it_is_shown_in()
	_test_every_control_says_what_it_is()
	_test_rig_roulette_rolls_outside_tour()
	_test_each_venue_dresses_the_gear_in_its_own_finishes()
	_test_rack_plugin_search_finds_and_adds_one()
	_test_channel_strip_name_opens_plugin_search()
	_test_escape_releases_a_surface_fullscreened_by_mistake()
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
	_test_a_ghosts_name_and_caption_respect_what_is_in_front_of_them()
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
	_test_the_timeline_clips_are_the_brightest_thing_on_their_lane()
	_test_the_timelines_keys_are_big_enough_to_aim_at()
	_test_the_tape_decks_keys_are_big_enough_to_aim_at()
	_test_a_simulated_headset_builds_the_vr_and_ar_rigs()
	_test_the_timeline_can_be_watched_as_a_road()
	_test_midi_items_show_their_notes_on_the_timeline()
	_test_a_block_goes_from_one_shelf_onto_another()
	_test_someone_elses_motion_plays_back_as_it_was_made()
	_test_the_timeline_is_resized_by_its_corner()
	_test_tour_briefs_are_defined_and_the_boss_is_last()
	_test_tour_loudness_judges_in_range()
	_test_tour_balance_judges_spread()
	_test_tour_timing_judges_beat_grid()
	_test_tour_boss_requires_every_measure_to_pass()
	_test_tour_deck_draws_three_with_no_duplicates()
	_test_tour_card_apply_uses_daw_verbs_only()
	_test_tour_project_restores_exactly()
	_test_tour_unlocks_persist_without_touching_layout()
	_test_tour_unlocks_a_loss_costs_a_point_of_reputation()
	_test_tour_asks_follow_the_verbs_shape()
	_test_tour_run_round_trips_through_its_dict()
	_test_tour_song_has_a_playing_band()
	_test_a_loaded_project_keeps_its_demo_parts()
	_test_tour_flaws_bake_and_are_fixed_through_daw_verbs()
	_test_tour_rig_roulette_lands_character_fx_on_a_big_enough_band()
	_test_tour_flaws_scale_with_the_band_and_the_seed()
	_test_tour_brief_judges_its_flaws()
	_test_tour_parts_scale_with_the_band_and_the_seed()
	_test_tour_song_has_a_stage_lane()
	_test_tour_part_is_played_by_notes_on_its_lane()
	_test_tour_untaken_part_blocks_the_pass()
	_test_tour_open_part_is_reassigned_after_the_grace()
	_test_tour_run_round_trips_parts_with_eight_peers()
	_test_tour_brief_ticks_a_part_off_the_stage_lane_and_gates_the_pass()
	_test_tour_hud_names_who_holds_each_part()
	_test_a_shorter_clock_card_shortens_the_very_next_brief()
	_test_tour_hud_rebuilds_its_flaw_lines_for_the_next_brief()
	_test_tour_case_breaks_after_enough_hits_and_resets()
	_test_tour_deck_muted_track_draws_off_the_runs_own_seed()
	_test_item_room_target_struck_finds_the_nearest_one_in_range()
	_test_only_the_host_can_break_the_case()
	_test_tour_venue_solids_include_the_case()
	_test_tour_spill_puts_a_real_item_in_the_room()
	_test_tour_run_ended_announces_the_result_to_the_room()
	_test_tour_guest_spawns_spilled_instruments_from_the_run()
	_test_tour_new_parts_are_judged_by_their_instruments_pitch()
	_test_tour_marked_instrument_refuses_another_hand()
	_test_tour_parts_count_the_instruments_in_the_room()
	_test_tour_deck_offers_instruments_to_a_big_band()
	_test_tour_chaos_schedule_is_seeded_and_scaled()
	_test_tour_chaos_strikes_and_recovers_through_daw_verbs()
	_test_tour_chaos_blocks_the_pass_until_recovered()
	_test_tour_chaos_telegraphs_and_strikes_on_the_brief_clock()
	_test_tour_clock_low_fires_once_near_the_end_of_the_brief()
	_test_tour_chaos_guest_plays_the_telegraph_from_the_run()
	_test_tour_flaw_fixed_fires_once_per_flaw_from_the_wire()
	_test_tour_chaos_leaves_the_real_project_untouched()
	_test_tour_chaos_round_trips_and_never_draws_a_conflict()
	_test_tour_ear_reads_inert_off_the_stand_in()
	_test_tour_ear_judges_from_its_table()
	_test_tour_brief_judges_the_crowd()
	_test_tour_brief_waits_for_the_crowd()
	_test_tour_brief_finishes_on_the_bar_not_the_frame()
	_test_tour_run_round_trips_the_crowd()
	_test_tour_hud_shows_the_crowd_lines()

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


## `fx_choices` offers Reaper's own stock plugins until `_on_installed_fx` answers -- never
## leaving the desk with nothing to offer before the bridge round-trip completes, or if it never
## completes at all -- then the host's own real installed plugins once it has, by `id` (what a
## later `add_fx` is given back), not display name. A malformed or empty answer changes nothing,
## rather than blanking an already-good list.
func _test_link_offers_reapers_stock_fx_until_the_bridge_answers() -> void:
	var link := _fresh_link()
	check("stock FX until the bridge answers", link.fx_choices().any(func(c): return c[0] == "ReaEQ"))
	link._on_installed_fx(null)
	check("a null answer changes nothing", link.fx_choices().any(func(c): return c[0] == "ReaEQ"))
	link._on_installed_fx({"ok": false, "fx": [["VST3:x", "x"]]})
	check("an answer saying ok=false is ignored", link.fx_choices().any(func(c): return c[0] == "ReaEQ"))
	link._on_installed_fx({"ok": true, "fx": [{"id": "VST3:1234:Serum.vst3", "label": "Serum"},
			{"id": "", "label": "no id, skipped"}, {"id": "VST:5678:Massive", "label": ""},
			{"id": "VST:9999:Vital", "label": "Vital"}]})
	var choices := link.fx_choices()
	check("the host's own real plugins now, not the stock set (%s)" % [choices],
			choices.size() == 2 and choices[0] == ["VST3:1234:Serum.vst3", "Serum"]
			and choices[1] == ["VST:9999:Vital", "Vital"])
	check("entries missing an id or a label are skipped, not placeholders",
			not choices.any(func(c): return c[1] == "no id, skipped" or c[0] == "VST:5678:Massive"))
	link._on_installed_fx({"ok": true, "fx": []})
	check("an empty answer never overwrites an already-good list", link.fx_choices().size() == 2)
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
		# Colour is dawlings's own address, not Reaper's. It is the thing that makes a strip
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
	check("in AR, the timeline stands in the room too, not pinned to the face", profile.mode_for(&"timeline", &"timeline") == Presentation.Mode.ROOM)

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

	# Reaper's project, by name and file, for the room: only the file's name, never its folder.
	link._on_timeline({"length": 240.0, "markers": [], "tracks": [], "project_name": "Night Drive",
			"project_file": "/home/someone/Songs/Night Drive.rpp"})
	check("Reaper's project name and file land (%s, %s)" % [link.state.project_title, link.state.project_file],
			link.state.project_title == "Night Drive" and link.state.project_file == "Night Drive.rpp")
	var told := MixState.new()
	MixWire.apply_replicated(told, MixWire.snapshot(link.state))
	check("and reach a joining guest", told.project_title == "Night Drive" and told.project_file == "Night Drive.rpp")

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


## 0.33, Surface's own default, left the timeline a third further from the eye on a monitor than
## its own width already allowed to (2026-10-11: "the timeline is still just ungodly
## unreadable"). Raised, but not as far as the panel's width would allow outright: the seat-click
## audit (`_test_every_control_is_clickable_from_the_seat`) is what actually bounds this, by
## catching the tape deck's tempo knob and Rig Roulette's wall going dark behind an oversized
## panel -- this just pins the number that audit measured clean, so a future "make it bigger"
## does not have to rediscover the ceiling the slow way.
func _test_timeline_screen_band_was_widened_but_not_past_the_seat_audit() -> void:
	var timeline := TimelineSurface.new()
	add_child(timeline)
	check("the timeline's screen band is wider than Surface's own unturned default",
			timeline.screen_band > 0.33)
	check("and not past what the seat-click audit measured clean",
			is_equal_approx(timeline.screen_band, 0.40))
	timeline.queue_free()


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
		"squeak out": {"stream": Foley.squeak(true), "loop": false, "seconds": 0.2},
		"squeak in": {"stream": Foley.squeak(false), "loop": false, "seconds": 0.26},
		"rubber tap": {"stream": Foley.rubber_tap(), "loop": false, "seconds": 0.08},
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
	# Colour, folder and dest are dawlings's own addresses rather than Reaper's, so they have
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
	DAW.remove_track(1)
	check("a track above it removed, it follows its track up (%d)" % tablet.track_index,
			tablet.track_index == 5 and tablet.fx().name == plugin)
	DAW.undo()
	check("and back down when that is undone", tablet.track_index == 6 and tablet.fx().name == plugin)

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
	check("nor how it is arranged", not studio.choose_variant(1) and studio.venue.variant == 0
			and not Session.room_ask_is_valid(&"set_variant", [1]))
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
	studio.apply_room({"venue": &"grid", "variant": 1,
			"tablets": {&"tablet_3": [2, order[1], plugin, 0.4, 0.2, 0.25]}})
	check("the host's arrangement of it is the guest's", studio.venue.venue_id() == &"grid"
			and studio.venue.variant == 1 and studio.tablets.has(&"tablet_3"))
	studio.apply_room({"venue": &"grid", "variant": 99,
			"tablets": {&"tablet_3": [2, order[1], plugin, 0.4, 0.2, 0.25]}})
	check("an arrangement the guest does not have is the venue's first", studio.venue.variant == 0)
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
	# Their push, as sent: a step every 50ms, played back a moment behind (PoseTrail).
	var asked := studio._predictions.size()
	for k in 6:
		studio._on_room_motion(&"rack", rack_home.x - 0.05 * (k + 1), rack_home.y, 0.05 * (k + 1), 5)
		PoseTrail.skew_msec += 50.0
	# Now 300ms after the first: drawn at 200ms, between the fifth and the sixth sent.
	studio._drive_pushed()
	studio.rack_trolley._physics_process(1.0 / 60.0)
	var moved_by := Vector2(studio.rack_trolley.position.x, studio.rack_trolley.position.z).distance_to(rack_home)
	check("someone else's push plays back as they pushed, a moment behind (%.3f)" % moved_by,
			absf(moved_by - 0.25) < 0.02)
	PoseTrail.skew_msec += 400.0
	studio._drive_pushed()
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


func _test_plugins_are_added_and_removed_from_the_rack() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var s := DAW.state
	var bus: int = backend._bus[6]
	var effects := func() -> Array:
		var out: Array = []
		for i in range(1, AudioServer.get_bus_effect_count(bus)):
			out.append(AudioServer.get_bus_effect(bus, i).get_class())
		return out
	check("the built-in engine offers its own effects (%d)" % s.fx_choices.size(),
			s.fx_choices.any(func(c): return c[0] == "reverb" and c[1] == "Reverb"))
	var guest := MixState.new()
	for pair in MixWire.snapshot(s):
		MixWire.apply(guest, pair[0], pair[1])
	check("and a guest is told what they are", guest.fx_choices == s.fx_choices)
	check("the bass has a compressor (%s)" % [effects.call()], effects.call() == ["AudioEffectCompressor"])
	DAW.add_fx(6, "reverb")
	check("add_fx puts a reverb after it, on the bus too (%s)" % [effects.call()],
			s.track(6).plugins().size() == 2 and s.fx(6, 1).name == "Reverb"
			and effects.call() == ["AudioEffectCompressor", "AudioEffectReverb"]
			and s.fx(6, 1).param_names.get(0, "") == "Size")
	DAW.add_fx(6, "eq", 0)
	check("and an EQ before both (%s)" % [effects.call()],
			effects.call() == ["AudioEffectEQ6", "AudioEffectCompressor", "AudioEffectReverb"])
	DAW.remove_fx(6, 1)
	check("remove_fx takes the compressor out of the chain and off the bus (%s)" % [effects.call()],
			s.track(6).plugins().size() == 2 and effects.call() == ["AudioEffectEQ6", "AudioEffectReverb"])
	DAW.undo()
	check("undone, the bus has it back where it was (%s)" % [effects.call()],
			effects.call() == ["AudioEffectEQ6", "AudioEffectCompressor", "AudioEffectReverb"])
	DAW.undo()
	DAW.undo()
	check("and two more undos leave the chain as it began (%s)" % [effects.call()],
			effects.call() == ["AudioEffectCompressor"] and s.track(6).plugins().size() == 1)
	DAW.apply_intent(&"add_fx", [6, "ReaPlugin Of Doom", -1])
	DAW.apply_intent(&"remove_fx", [6])
	check("a guest may only add what the DAW offers, and a malformed removal is refused",
			s.track(6).plugins().size() == 1 and &"add_fx" in DAW.COMMANDS and &"remove_fx" in DAW.COMMANDS)

	# On the rack: the window on the bottom rail adds, a fine press on POWER removes.
	var rack := RackSurface.new()
	add_child(rack)
	rack.show_track(6)
	rack._process(0.0)
	var adder: TabletSelector = rack.find_child("PluginAdder", true, false)
	var eq_choice := -1
	for i in s.fx_choices.size():
		if s.fx_choices[i][0] == "eq":
			eq_choice = i
	check("the rack has a window to add a plugin with", adder != null and adder.words().begins_with("ADD"))
	adder.choice = eq_choice
	adder.pressed.emit(eq_choice)
	check("clicking it adds the plugin in it to the racked track", s.track(6).plugins().size() == 2
			and s.fx(6, 1).name == "EQ6")
	rack._rebuild()
	var units: Array = rack.find_children("*", "RackUnit", true, false)
	var eq_unit: RackUnit = units.filter(func(u): return u.fx_index == 1).front() if not units.is_empty() else null
	var finger := FakeHand.new()
	add_child(finger)
	finger.holding_shift = true
	eq_unit._bypass.grab_begin(finger, eq_unit._bypass.global_position)
	eq_unit._bypass.grab_end(finger)
	check("a fine press on its POWER removes it", s.track(6).plugins().size() == 1)
	finger.holding_shift = false
	var comp_unit: RackUnit = units.filter(func(u): return u.fx_index == 0).front()
	comp_unit._bypass.grab_begin(finger, comp_unit._bypass.global_position)
	comp_unit._bypass.grab_end(finger)
	check("and a plain press still bypasses", not s.fx(6, 0).enabled and s.track(6).plugins().size() == 1)
	finger.queue_free()
	rack.queue_free()

	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	add_child(reaper)
	check("Reaper offers its own stock plugins", reaper.fx_choices().any(func(c): return c[0] == "ReaComp"))
	reaper.add_fx(1, "ReaComp", -1)
	check("and without the bridge adds nothing", reaper.state.tracks.is_empty() or reaper.state.track(1).plugins().is_empty())
	reaper.free()
	_offline()


func _test_the_welcome_card_opens_on_f1_and_is_seen_once() -> void:
	var card := WelcomeCard.new()
	card.seen_path = "user://test_welcome_seen"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(card.seen_path))
	add_child(card)
	check("the welcome card starts hidden", not card.visible)
	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	card._input(f1)
	check("F1 opens it", card.visible)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	card._input(esc)
	check("Esc puts it away, and it is marked seen", not card.visible and FileAccess.file_exists(card.seen_path))
	card._input(f1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card._input(click)
	check("a click puts it away too", not card.visible)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(card.seen_path))
	card.queue_free()


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


## THE OVERLAP THIS EXISTS FOR (2026-10-11: "Rack unit labels can overlap their first knob
## caption on long plugin names"). `_name_label` was the one label on this panel nothing ever
## called `Lettering.fit` on, so a long track name beside a long plugin name ran straight through
## the bypass button and, past MAX_KNOBS, the page readout beside it too -- confirmed off an
## actual screenshot (a track and plugin name long enough to overflow), not guessed from the
## source. Checked here as a measurement against the label's own font, not a screenshot, so it
## stays checked without a render.
func _test_rack_unit_name_stays_off_the_header_icons() -> void:
	DAW.use(OfflineBackend.new())

	DAW.state.track(2).name = "Rhythm Guitar Double"
	var fx := DAW.state.fx(2, 0)
	fx.name = "UAD Precision Buss Compressor"
	check("the stand-in still has a plugin that overflows a faceplate, so the page readout is on",
			fx.params.size() > RackUnit.MAX_KNOBS)

	var unit := RackUnit.create(2, 0)
	add_child(unit)
	var f := unit._name_label.font if unit._name_label.font != null else Lettering.face()
	var rendered := f.get_string_size(unit._name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			unit._name_label.font_size).x * unit._name_label.pixel_size
	check("a long track-and-plugin name is shrunk to fit the tab's own width (%.3fm of %.3fm)" %
			[rendered, RackUnit.NAME_SPAN - 0.012], rendered <= RackUnit.NAME_SPAN - 0.012 + 0.0005)
	check("it did not shrink past the floor size", unit._name_label.font_size >= RackUnit.NAME_SIZE_MIN)

	unit.queue_free()
	DAW.use(OfflineBackend.new())


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

	check("a strip's buttons and pan knob are drawn %.2fx, not at the parts' own size" % ChannelStrip.BUTTON_SCALE,
			ChannelStrip.BUTTON_SCALE >= 1.4 and is_equal_approx(banked_strip._rec.scale.x, ChannelStrip.BUTTON_SCALE)
			and is_equal_approx(banked_strip._pan.scale.x, ChannelStrip.KNOB_SCALE))
	var widest := PanelButton.SIZE.x * ChannelStrip.BUTTON_SCALE
	check("an enlarged button still fits inside the strip's width", widest < ChannelStrip.WIDTH)

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


## RigRouletteStation.roll_requested, outside Tour entirely: host-only (a guest's roll is
## refused, with a notice, and mutates nothing); refused while the open project has unsaved
## changes; otherwise it starts a NEW project with a random number of tracks, lands exactly
## `count` pedals on them, the CHARACTER pool only ever drawing from
## RigRouletteStation.CHARACTER_KINDS, and leaves the rolled project counted as saved so it can be
## rolled again untouched.
func _test_rig_roulette_rolls_outside_tour() -> void:
	_as_session(Session.Role.HOST, 1)
	Session.roll = {}
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	while not DAW.state.track_indices().is_empty():
		DAW.remove_track(DAW.state.track_indices()[0])
	for i in 3:
		DAW.add_track(i + 1, "Track %d" % (i + 1))
	backend.mark_clean()

	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	check("the station is built", studio.rig_roulette_station != null)
	var station := studio.rig_roulette_station
	station.count = 2
	station.pool = RigRouletteStation.Pool.CHARACTER

	Session.role = Session.Role.GUEST
	var notices: Array[String] = []
	var hear := func(t: String): notices.append(t)
	Session.notice.connect(hear)
	station.roll_requested.emit()
	check("a guest's roll is refused, and told why", DAW.state.track_indices().size() == 3
			and notices.size() == 1 and notices[0].begins_with("Only "))
	Session.role = Session.Role.HOST

	notices.clear()
	DAW.set_tempo(97.0)
	check("an edit leaves the project with unsaved changes", DAW.has_unsaved_changes())
	station.roll_requested.emit()
	check("a roll with unsaved changes is refused, and told why", DAW.state.track_indices().size() == 3
			and DAW.state.tempo == 97.0 and notices.size() == 1 and notices[0].begins_with("Save the project"))
	Session.notice.disconnect(hear)

	backend.mark_clean()
	var counts := {}
	for n in 12:
		station.roll_requested.emit()
		var tracks: int = DAW.state.track_indices().size()
		counts[tracks] = true
		var fx := 0
		var character_names := {}
		for k in RigRouletteStation.CHARACTER_KINDS:
			character_names[FXCatalogue.kinds()[k]["name"]] = true
		var only_character := true
		for i in DAW.state.track_indices():
			for f: MixState.FXState in DAW.state.track(i).fx.values():
				fx += 1
				only_character = only_character and character_names.has(f.name)
		check("roll %d: %d tracks inside the range, exactly 2 character pedals (%d)" % [n, tracks, fx],
				tracks >= Studio.ROLL_TRACKS_MIN and tracks <= Studio.ROLL_TRACKS_MAX and fx == 2 and only_character)
		check("roll %d leaves the rolled project saved, so it can be rolled again" % n, not DAW.has_unsaved_changes())
		var said: Dictionary = Session.roll
		var writing := studio.roll_board.find_child("Writing", false, false)
		var board_text := ""
		for l in writing.get_children():
			board_text += (l as Label3D).text + "\n"
		check("roll %d is written up for the room: %d tracks, 2 pedals, on the board" % [n, tracks],
				said["tracks"] == tracks and said["n"] == n + 1 and (said["pedals"] as Array).size() == 2
				and board_text.contains("%d TRACKS" % tracks)
				and board_text.contains(str(said["pedals"][0]["fx"]).to_upper()))
	check("the track count really varies from roll to roll (%s)" % [counts.keys()], counts.size() > 1)
	var spot := studio.venue.rig_roulette_spot()
	var board := studio.venue.roll_board_spot()
	check("the panel and the board stand clear of the wall they hang on (%.2f, %.2f)" % [spot.origin.z, board.origin.z],
			spot.origin.z >= Studio.ROOM_FRONT + 0.06 and board.origin.z >= Studio.ROOM_FRONT + 0.1)
	Session.roll = {}

	remove_child(studio)
	studio.free()
	DAW.use(OfflineBackend.new())


## Venue.gear_style, through Materials.apply_style: every venue puts its own finish on the
## furniture the gear stands in, the shared materials change in place so gear already built
## changes with them, the lit-edge venues light their trim, and going back to the studio puts
## every default back. The roll board stands on posts where the venue has no wall for it.
func _test_each_venue_dresses_the_gear_in_its_own_finishes() -> void:
	var looks := {}
	for id in Venue.IDS:
		var style := Venue.make(id, 0).gear_style()
		Materials.apply_style(style)
		var f := Materials.furniture()
		looks[id] = [f.albedo_color, f.albedo_texture, Materials.trim().emission_enabled,
				Materials.trim().emission if Materials.trim().emission_enabled else Color.BLACK,
				Materials.end_cheek().albedo_texture, Materials.end_cheek().albedo_color,
				Materials.lamp_shade().albedo_color]
	var distinct := {}
	for id in looks:
		distinct[str(looks[id])] = id
	check("all %d venues dress the gear differently (%d distinct)" % [looks.size(), distinct.size()],
			distinct.size() == looks.size())
	Materials.apply_style(Venue.make(&"grid", 0).gear_style())
	check("the grid's trim is a lit cyan edge", Materials.trim().emission_enabled
			and Materials.trim().emission.is_equal_approx(Color(0.2, 1.0, 1.0)))
	Materials.apply_style(Venue.make(&"studio", 0).gear_style())
	check("back in the studio the furniture is the chassis's powder coat again, trim unlit steel",
			Materials.furniture().albedo_color.is_equal_approx(Materials.chassis().albedo_color)
			and not Materials.trim().emission_enabled
			and Materials.trim().metallic == Materials.brushed_metal().metallic)
	for id in [&"chalk", &"dome", &"grid", &"rooftop"]:
		check("%s has nothing to hang the roll board on, so it stands" % id,
				Venue.make(id, 0).back_wall_gear_stands())
	for id in [&"studio", &"cabin", &"club", &"loft", &"station"]:
		check("%s hangs the roll board on its wall" % id, not Venue.make(id, 0).back_wall_gear_stands())
	var board := RollBoard.new()
	board.free_standing = true
	board.position = Vector3(0, 2.14, 0)
	add_child(board)
	var posts := board.find_children("Post*", "MeshInstance3D", false, false)
	check("a free-standing board has two posts reaching the floor (%d)" % posts.size(), posts.size() == 2
			and is_equal_approx(((posts[0] as MeshInstance3D).mesh as BoxMesh).size.y, 2.14))
	board.free()
	var station := RigRouletteStation.new()
	station.position = Vector3(0, 1.05, 0)
	add_child(station)
	station.set_free_standing(true)
	check("a free-standing roulette panel has a post", station.get_node_or_null("Post") != null)
	station.set_free_standing(false)
	check("and loses it back on a wall", station.get_node_or_null("Post") == null)
	station.free()
	var shades := {}
	for id in Venue.IDS:
		Materials.apply_style(Venue.make(id, 0).gear_style())
		shades[str([Materials.lamp_shade().albedo_color, Materials.lamp_shade().emission_enabled])] = id
	check("every venue's lamp shades are its own (%d distinct)" % shades.size(), shades.size() == Venue.IDS.size())
	Materials.apply_style(null)


## The rack's FIND button, beside the ADD wheel: opens a searchable list for when the DAW
## offers more plugins than anyone could scroll to one at a time.
func _test_rack_plugin_search_finds_and_adds_one() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	while not DAW.state.track_indices().is_empty():
		DAW.remove_track(DAW.state.track_indices()[0])
	DAW.add_track(1, "Track 1")

	var rack := RackSurface.new()
	add_child(rack)
	rack.show_track(1)
	rack._process(0.0)

	var find_button: PanelButton = rack.find_child("FindPlugin", true, false)
	check("the rack offers a FIND button beside the ADD wheel", find_button != null)
	find_button.pressed.emit()

	var picker: PluginPicker = null
	for n in get_tree().root.get_children():
		if n is PluginPicker:
			picker = n
	check("pressing FIND opens a search picker", picker != null)
	check("it starts showing every plugin the DAW offers",
			picker._filtered.size() == DAW.state.fx_choices.size())

	var edit: LineEdit = picker.find_child("Search", true, false)
	edit.text_changed.emit("rev")
	check("typing narrows the list to matches (%s)" % [picker._filtered],
			picker._filtered.size() == 1 and str(picker._filtered[0][1]) == "Reverb")

	var chosen_ids: Array[String] = []
	picker.chosen.connect(func(id: String): chosen_ids.append(id))
	edit.text_submitted.emit("rev")
	check("Enter on the one match adds it, and leaves the picker",
			DAW.state.track(1).fx.size() == 1 and chosen_ids.size() == 1
			and picker.is_queued_for_deletion())
	var added: MixState.FXState = DAW.state.track(1).fx.values()[0]
	check("and it is the plugin that was searched for (%s)" % added.name, added.name == "Reverb")

	rack.queue_free()
	DAW.use(OfflineBackend.new())


## The same search, reached from the console directly: a click on the strip's own name, with no
## need to find the rack first (2026-10-11: "i genuinely cant tell how to do it... adding a
## plugin").
func _test_channel_strip_name_opens_plugin_search() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	while not DAW.state.track_indices().is_empty():
		DAW.remove_track(DAW.state.track_indices()[0])
	DAW.add_track(1, "Track 1")

	var strip := ChannelStrip.create(1)
	add_child(strip)

	check("the strip carries a hit target over its own name", strip._name_tab != null)
	strip._name_tab.pressed.emit()

	var picker: PluginPicker = null
	for n in get_tree().root.get_children():
		if n is PluginPicker:
			picker = n
	check("clicking the name opens the same search picker the rack's FIND button does",
			picker != null)

	var chosen_ids: Array[String] = []
	picker.chosen.connect(func(id: String): chosen_ids.append(id))
	var edit: LineEdit = picker.find_child("Search", true, false)
	edit.text_changed.emit("rev")
	edit.text_submitted.emit("rev")
	check("Enter on the one match adds it to THIS strip's track",
			DAW.state.track(1).fx.size() == 1 and chosen_ids.size() == 1)
	var added: MixState.FXState = DAW.state.track(1).fx.values()[0]
	check("and it is the plugin that was searched for (%s)" % added.name, added.name == "Reverb")

	strip.queue_free()
	DAW.use(OfflineBackend.new())


## A surface pushed into SCREEN mode by a stray tap on its handle -- easy to do reaching for a
## control beside it -- and Escape putting it back, without touching a surface that is in SCREEN
## mode on purpose.
func _test_escape_releases_a_surface_fullscreened_by_mistake() -> void:
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)

	check("the rack starts in its own default mode, not fullscreen",
			studio.mount.mode_of(&"rack") == Presentation.Mode.STUDIO)
	check("the timeline defaults to fullscreen on screen, on purpose",
			studio.mount.mode_of(&"timeline") == Presentation.Mode.SCREEN)

	studio.mount.set_mode(&"rack", Presentation.Mode.SCREEN)
	check("the rack can still be put in SCREEN mode by hand, same as the handle does",
			studio.mount.mode_of(&"rack") == Presentation.Mode.SCREEN)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	studio._unhandled_input(esc)
	check("Escape puts a stray fullscreen rack back (2026-10-11: \"escape was not working\")",
			studio.mount.mode_of(&"rack") == Presentation.Mode.STUDIO)
	check("and leaves the timeline's own, on-purpose fullscreen alone",
			studio.mount.mode_of(&"timeline") == Presentation.Mode.SCREEN)

	remove_child(studio)
	studio.free()


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


## The timeline's stand is taken by its top bar, which is at about the eye of someone 1.58 m
## tall. Read off the level plane through the bar, the aim runs along that plane instead of
## crossing it: the stand flew metres for a twitch of the mouse, or did not move at all. Aimed
## that flat, a nudge across moves it across, and a nudge up pushes it away -- by about as much
## as the same nudge would on the floor.
func _test_a_stand_taken_at_eye_height_pushes_naturally() -> void:
	var rig := _floor_studio()
	var studio: Studio = rig["studio"]
	var hand: FakeHand = rig["hand"]
	var stand := studio.timeline_stand
	var bar := Vector3(stand.position.x + 0.1, Studio.TIMELINE_STAND_TOP + 0.012, stand.position.z)
	var eye := bar + Vector3(0, 0.002, 1.8)
	hand.pose = Transform3D(Basis.IDENTITY, eye).looking_at(bar, Vector3.UP)
	var from := Vector2(stand.position.x, stand.position.z)
	stand.grab_begin(hand, bar)
	hand.pose = Transform3D(Basis(Vector3.UP, deg_to_rad(-2.0)), eye).looking_at(bar, Vector3.UP)
	hand.pose.basis = Basis(Vector3.UP, deg_to_rad(-2.0)) * hand.pose.basis
	stand.grab_move(hand, Vector3.ZERO)
	var across := stand._target - from
	check("a nudge to the right moves it right, a little (%s)" % across,
			across.x > 0.03 and across.x < 0.15 and absf(across.y) < 0.02)
	hand.pose.basis = Basis(Vector3.RIGHT, deg_to_rad(2.0)) * Transform3D(Basis.IDENTITY, eye).looking_at(bar, Vector3.UP).basis
	stand.grab_move(hand, Vector3.ZERO)
	var away := stand._target - from
	check("a nudge up pushes it away from you, not off to the horizon (%s)" % away,
			away.y < -0.05 and away.y > -0.5 and absf(away.x) < 0.02)
	stand.grab_end(hand)
	_roll_until_still(stand)
	var went := Vector2(stand.position.x, stand.position.z) - from
	check("and it rolls there (%s)" % went, went.distance_to(away) < 0.01)
	_drop_floor_studio(rig)


## Too tall, or too short, for the room: said in the room, felt at once, kept for next time.
func _test_you_can_say_how_tall_you_are_in_the_room() -> void:
	var rig := _floor_studio()
	var studio: Studio = rig["studio"]
	studio.body_path = "user://test_body.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(studio.body_path))
	# The gear standing in the room. What rides in front of your face comes down with your eye.
	var poses := {}
	for surface in studio.focus.surfaces:
		if studio.mount.mode_of(surface.surface_id) == Presentation.Mode.STUDIO:
			poses[surface.surface_id] = surface.global_transform
	check("you start at the default height", is_equal_approx(studio.ergonomics.height,
			Ergonomics.DEFAULT_HEIGHT))
	studio.set_body_height(1.48)
	check("a shorter you has a lower eye (%.2f)" % studio.walker.eye_height,
			is_equal_approx(studio.walker.eye_height, 1.48 - Ergonomics.EYE_BELOW_CROWN)
			and is_equal_approx(studio.walker.standing_eye, studio.walker.eye_height))
	check("and sees from there", is_equal_approx(studio.camera.global_position.y,
			studio.walker.global_position.y + studio.walker.eye_height) or studio.god_mode)
	check("and is remembered", is_equal_approx(Ergonomics.load_height(studio.body_path), 1.48))
	var moved := []
	for surface in studio.focus.surfaces:
		if poses.has(surface.surface_id) \
				and not surface.global_transform.is_equal_approx(poses[surface.surface_id]):
			moved.append(surface.surface_id)
	check("the gear in the room stays where it is (%s of %d)" % [moved, poses.size()],
			moved.is_empty() and poses.size() >= 3)
	studio.set_body_height(9.0)
	check("but not beyond a person", is_equal_approx(studio.ergonomics.height, Ergonomics.HEIGHT_RANGE.y))

	var panel := StageManager.new()
	panel.studio = studio
	add_child(panel)
	studio.set_body_height(1.58)
	panel.rebuild()
	var row: Node = null
	for child in panel._rows.get_children():
		if child.name == &"HeightRow" and not child.is_queued_for_deletion():
			row = child
	check("the stage manager has a height row", row != null)
	if row != null:
		check("saying what you are", (row.get_node("Reading") as Label).text == "1.58 m")
		(row.get_node("Shorter") as Button).pressed.emit()
		check("and its minus makes you shorter (%.2f)" % studio.ergonomics.height,
				is_equal_approx(studio.ergonomics.height, 1.53))
	remove_child(panel)
	panel.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(studio.body_path))
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
## The scan that the room's check rests on: it finds two faces in one plane that overlap, and
## nothing for faces that only touch, lie apart in the same plane, or face another way.
func _test_the_zfight_scan_finds_a_planted_fight() -> void:
	var root := Node3D.new()
	add_child(root)
	var box := func(at: Vector3, size: Vector3, turn := 0.0) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mi.mesh = mesh
		mi.position = at
		mi.rotation.y = turn
		root.add_child(mi)
		return mi
	# Two tiles side by side, edge to edge, and a third far along the same plane.
	box.call(Vector3(0, 0, 0), Vector3(1, 0.1, 1))
	box.call(Vector3(1, 0, 0), Vector3(1, 0.1, 1))
	box.call(Vector3(5, 0, 0), Vector3(1, 0.1, 1))
	check("faces that touch or lie apart in one plane do not fight (%d)" % ZFightProbe.scan(root).size(),
			ZFightProbe.scan(root).is_empty())
	# A plate turned 30 degrees lying across the first tile, its top in the tile's top.
	var plate: MeshInstance3D = box.call(Vector3(0.2, 0.025, 0.1), Vector3(0.6, 0.05, 0.2), deg_to_rad(30))
	var hits := ZFightProbe.scan(root)
	check("a turned plate whose top is in a tile's top fights it (%d)" % hits.size(),
			not hits.is_empty() and hits.all(func(h): return plate in [h[0], h[1]]))
	plate.position.y = 0.03
	check("and does not once it stands proud", ZFightProbe.scan(root).is_empty())
	# One drawn by a bank, its top in the far tile's top.
	var bank := MeshBank.meshed(BoxMesh.new())
	(bank.multimesh.mesh as BoxMesh).size = Vector3(0.5, 0.1, 0.5)
	root.add_child(bank)
	bank.claim(Transform3D(Basis(), Vector3(5.2, 0, 0)), Color.WHITE)
	bank.commit()
	hits = ZFightProbe.scan(root)
	check("a bank's instance is scanned like a mesh (%d)" % hits.size(), hits.size() >= 1
			and hits.any(func(h): return h[0] is Array or h[1] is Array))
	remove_child(root)
	root.free()


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
		for v in Venue.variant_titles(id).size():
			studio.set_venue(id, false, v)
			var hits := ZFightProbe.scan(studio)
			var named := hits.slice(0, 3).map(func(h): return "%s | %s" % [
					ZFightProbe.label(h[0]), ZFightProbe.label(h[1])])
			check("no two faces in the %s/%d share a plane (%d: %s)" % [id, v, hits.size(),
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

	# Arranged another way: still the same room for the gear, and the arrangement kept.
	studio.set_venue(&"grid", false)
	var grid_poses := {}
	for surface in studio.focus.surfaces:
		grid_poses[surface.surface_id] = surface.global_transform
	var grid_zones := studio.venue.zones()
	var grid_walkable := studio._walkable()
	check("a venue with arrangements has more than one", Venue.variant_titles(&"grid").size() > 1)
	check("one without has its own name as its only one", Venue.variant_titles(&"loft")
			== PackedStringArray([Venue.make_title(&"loft")]))
	check("the host can arrange it another way", studio.choose_variant(1) and studio.venue.variant == 1
			and studio.venue.venue_id() == &"grid")
	check("and is told which (%s)" % studio.venue.title(), studio.venue.title().ends_with(
			Venue.variant_titles(&"grid")[1]))
	check("the downtown grid has its city close in", studio.venue.find_child("Downtown", false, false) != null
			and studio.venue.find_child("Mountains", false, false) == null)
	var shifted := []
	for surface in studio.focus.surfaces:
		if not surface.global_transform.is_equal_approx(grid_poses[surface.surface_id]):
			shifted.append(surface.surface_id)
	check("arranging it moves no gear (%s)" % [shifted], shifted.is_empty())
	check("and keeps its zones", studio.venue.zones() == grid_zones)
	check("and where you can walk", studio._walkable() == grid_walkable)
	check("the arrangement is remembered", Session.layout.venue == &"grid"
			and Session.layout.venue_variant == 1)
	check("and travels in the room", studio.room_state()["variant"] == 1)
	studio.set_venue(&"grid", true, 7)
	check("an arrangement a venue lacks is its first", studio.venue.variant == 0
			and Session.layout.venue_variant == 0)
	studio.choose_variant(1)
	studio.choose_venue(&"studio")
	check("another venue starts at its first arrangement", studio.venue.variant == 0)
	studio.set_venue(&"grid", true, 1)

	Session.layout.save()
	var reloaded := LayoutProfile.new()
	reloaded.save_path = Session.layout.save_path
	reloaded.load_saved()
	check("the venue survives a restart", reloaded.venue == &"grid")
	check("and so does its arrangement", reloaded.venue_variant == 1)

	# The stage manager's venue row: a picker for the arrangements, only where there is a choice.
	var panel := StageManager.new()
	panel.studio = studio
	add_child(panel)
	var picker := func() -> HBoxContainer:
		for row in panel._rows.get_children():
			if row.name == &"VariantRow" and not row.is_queued_for_deletion():
				return row
		return null
	panel.rebuild()
	var row: HBoxContainer = picker.call()
	var buttons := row.find_children("*", "Button", false, false) if row != null else []
	check("the panel offers the grid's arrangements", buttons.size() == Venue.variant_titles(&"grid").size()
			and (buttons[1] as Button).button_pressed and (buttons[1] as Button).disabled
			and not (buttons[0] as Button).disabled)
	(buttons[0] as Button).pressed.emit()
	check("and picking one arranges it", studio.venue.variant == 0)
	studio.set_venue(&"chalk", false)
	panel.rebuild()
	check("a venue with one arrangement shows no picker", picker.call() == null)
	studio.set_venue(&"grid", true, 1)
	remove_child(panel)
	panel.free()
	remove_child(studio)
	studio.free()

	var again := Studio.new()
	again.medium = Presentation.Medium.SCREEN
	add_child(again)
	check("a saved venue is where the next session starts", again.venue.venue_id() == &"grid"
			and again.venue.variant == 1)
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
	var arrangements := []
	for id in Venue.IDS:
		for v in Venue.variant_titles(id).size():
			arrangements.append([id, v])
	for width in [Studio.ROOM_WIDTH, Studio.ROOM_WIDTH + 3.2]:
		for arranged: Array in arrangements:
			var id: StringName = arranged[0]
			var venue := Venue.make(id, arranged[1])
			venue.room_width = width
			add_child(venue)
			var tag := "%s/%d at %.1f m" % [id, arranged[1], width]
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
					var floor_rect := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
					check("%s: %s is inside one of the live rooms" % [tag, zone_id],
							venue.rooms().any(func(r: Rect2): return r.grow(0.051).encloses(floor_rect))
							and box.end.y <= Venue.LIVE_ROOM_HEIGHT)
			if id == &"studio":
				# The live room is lit from fittings on its walls, and each throws its light along
				# the wall it hangs on -- into the room, never into the plaster behind it.
				var sconces := venue.find_children("Sconce*", "Node3D", false, false)
				var washing := sconces.all(func(n: Node3D):
					var spots := n.find_children("*", "SpotLight3D", false, false)
					return spots.size() == 2 and spots.all(func(l: SpotLight3D):
						var aim := -l.global_transform.basis.z
						return absf(aim.y) > 0.9 and aim.dot(n.global_transform.basis.z) > 0.0))
				check("%s: the live room has sconces washing its walls (%d)" % [tag, sconces.size()],
						sconces.size() >= 4 and washing)
			var stand := venue.find_child("MicStand", true, false) as Node3D
			if stand != null:
				var clip := (stand.get_node("Clip") as Node3D).global_position
				var booth: AABB = zones[&"vocals"]
				var middle := Vector2(booth.get_center().x, booth.get_center().z)
				check("%s: the booth's mic waits at a singer's mouth (%.2f m up)" % [tag, clip.y],
						clip.y > 1.25 and clip.y < Ergonomics.DEFAULT_HEIGHT - 0.1)
				check("%s: its boom reaches in from the glass, not across the middle" % tag,
						Vector2(clip.x, clip.z).distance_to(middle)
						< Vector2(stand.global_position.x, stand.global_position.z).distance_to(middle)
						and Vector2(stand.global_position.x, stand.global_position.z).distance_to(middle) > 0.4)
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


func _test_a_duck_is_picked_up_squeezed_and_put_down() -> void:
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	check("the studio has its items, a rubber duck among them", room != null and room.items.has(&"duck"))
	if room == null or not room.items.has(&"duck"):
		studio.queue_free()
		return
	var duck: Item = room.items[&"duck"]
	var hand := studio.get_node("MouseHand") as MouseInteractor
	var walker := studio.walker
	var step := func(item: Item, seconds: float) -> void:
		for i in int(seconds * 60.0):
			item._physics_process(1.0 / 60.0)

	# Every venue has a prop shelf, off the footprint, clear of the zones, on the floor, and
	# somewhere you can stand in front of; the duck lives on it.
	for id: StringName in Venue.IDS:
		for v in Venue.variant_titles(id).size():
			studio.set_venue(id, false, v)
			var venue := studio.venue
			var shelf := venue.prop_shelf_spot()
			var spots := venue.item_spots()
			var corners: Array[Vector2] = []
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := shelf * Vector3(c.x * ZoneKit.SHELF.x * 0.5, 0, c.y * ZoneKit.SHELF.z * 0.5)
				corners.append(Vector2(p.x, p.z))
			var rect := Rect2(corners[0], Vector2.ZERO)
			for c in corners:
				rect = rect.expand(c)
			var clear_of_zones := true
			for box: AABB in venue.zones().values():
				if rect.intersects(Rect2(box.position.x, box.position.z, box.size.x, box.size.z)):
					clear_of_zones = false
			var on_floor := corners.all(func(c: Vector2) -> bool:
				return walker.walkable.any(func(r: Rect2) -> bool: return r.has_point(c)))
			var clear_of_solids := true
			for f: Dictionary in venue.zone_solids():
				for c in corners + [Vector2(shelf.origin.x, shelf.origin.z)]:
					if Walker._gap(f, c) <= 0.0:
						clear_of_solids = false
			var before := shelf * Vector3(0, 0, ZoneKit.SHELF.z * 0.5 + Walker.RADIUS + 0.12)
			var standable: bool = walker.fits(Vector2(before.x, before.z))
			# A spot on the shelf for everything but the headphones, the tablet, the percussion, the
			# keytar, the chips, the cards, the darts, the cradle and the yo-yo, which have homes of
			# their own.
			var home_ok := duck.state == Item.State.HOME and spots.size() >= ItemRoom.KINDS.size() - 14 \
					and duck.position.is_equal_approx(spots[0].origin)
			check("%s:%d: the prop shelf is off the footprint, clear of the zones and their solids, on the floor, with room to stand at it, and the duck on it"
					% [id, v], not rect.intersects(studio._room_bounds()) and clear_of_zones
					and clear_of_solids and on_floor and standable and home_ok)
	studio.set_venue(&"studio", false)
	var shelf_print: Dictionary = studio.venue.solids().back()
	check("the shelf stops you walking into it", walker.fixed.has(shelf_print)
			and not walker.fits(shelf_print["c"]))
	check("and in the chalk zone it is only drawn", ChalkVenue.new().solids().size() == ChalkVenue.new().zone_solids().size())

	# Picked up through the grab contract, as a mouse, a controller or a pinch would: it is in
	# the hand, out of the way of the hand's own ray, and stays there when the button comes up.
	duck.grab_begin(hand, duck.global_position)
	check("a grab picks the duck up", duck.state == Item.State.HELD and hand.carrying == duck
			and duck.carried_by == hand and duck._shape.disabled)
	duck.grab_end(hand)
	step.call(duck, 1.0)
	var pose := hand.carry_pose() * duck.held_pose()
	check("and it rides in the hand when the button comes up (%.3f m off)"
			% duck.global_position.distance_to(pose.origin), duck.state == Item.State.HELD
			and duck.global_position.distance_to(pose.origin) < 0.01)
	hand._show_glove()
	for i in 60:
		hand._glove.step(1.0 / 60.0)
	var palm := hand._glove.global_position.distance_to(duck.global_position)
	check("a mouse's hand is a glove of its own, palm up under the duck (%.3f m)" % palm,
			hand._glove.visible and palm < 0.05 and hand._glove.pose == Glove.Pose.OPEN)
	check("drawn in your own view, never in a mirror", duck.body.find_children("*", "VisualInstance3D",
			true, false).all(func(n: VisualInstance3D) -> bool: return n.layers == Mirror.NOT_REFLECTED))

	# Squeezed by the hand's button, when the ray is on nothing.
	duck.use(true)
	step.call(duck, 0.05)
	var squashed := duck.body.scale.y
	duck.use(false)
	step.call(duck, 1.0)
	check("a squeeze squashes it (%.2f) and it springs back (%.2f)" % [squashed, duck.body.scale.y],
			squashed < 0.92 and absf(duck.body.scale.y - 1.0) < 0.02)
	hand.press_override = 1
	hand.hovered = null
	hand._was_pressed = false
	var squeezed := [false]
	hand._physics_process(1.0 / 60.0)
	squeezed[0] = hand._using if hand.hovered == null else true
	hand.press_override = 0
	hand._physics_process(1.0 / 60.0)
	check("the button squeezes what the hand carries when it points at nothing, and lets go with it",
			squeezed[0] and not hand._using and hand.carrying == duck)
	hand.press_override = -1

	# Put down: on the floor where you look, if a person could stand there to pick it up.
	var at := Vector3(-1.0, 0.0, 3.6)
	var eye := at + Vector3(0.4, 1.6, 0.6)
	room.put_down(duck, Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye))
	step.call(duck, 3.0)
	check("put down, it lies on the floor where you looked (%s)" % duck.position,
			duck.state == Item.State.LOOSE and hand.carrying == null
			and Vector2(duck.position.x - at.x, duck.position.z - at.z).length() < 0.01
			and absf(duck.position.y) < 0.01 and not duck._shape.disabled)
	check("and at rest it stops ticking", not duck.is_physics_processing())
	hand.pick_up(duck)
	# Aimed at the console, where nobody can stand: it goes home instead.
	var desk := Vector3(0, 0, -0.4)
	eye = Vector3(0, 1.6, Studio.MIX_POSITION_Z)
	room.put_down(duck, Transform3D(Basis.looking_at(desk - eye, Vector3.UP), eye))
	check("put down on the gear, it goes home instead", duck.state == Item.State.HOME)
	step.call(duck, 6.0)
	check("and floats back onto its shelf (%.3f m off)" % duck.position.distance_to(duck.home.origin),
			duck.position.distance_to(duck.home.origin) < 0.01)
	# Out on the grid's open floor, then the venue changes to one whose walls stop short of it.
	studio.set_venue(&"grid", false)
	hand.pick_up(duck)
	var far := Vector3(-studio.venue.live_room_half() - 1.5, 0, 3.0)
	eye = far + Vector3(0.5, 1.6, 0)
	room.put_down(duck, Transform3D(Basis.looking_at(far - eye, Vector3.UP), eye))
	check("on the grid it lies out past where the studio's walls would be", duck.state == Item.State.LOOSE)
	studio.set_venue(&"studio", false)
	check("and a venue without that floor sends it home", duck.state == Item.State.HOME
			and duck.position.is_equal_approx(duck.home.origin))
	# Left lying long enough, it tidies itself away.
	hand.pick_up(duck)
	room.put_down(duck, Transform3D(Basis.looking_at(at - Vector3(-0.6, 1.6, 4.2), Vector3.UP), Vector3(-0.6, 1.6, 4.2)))
	duck.loose_for = Item.TIDY_SECONDS + 1.0
	duck.set_physics_process(true)
	duck._physics_process(1.0 / 60.0)
	check("left lying, it goes home in the end", duck.state == Item.State.HOME)

	# A ghost carries a look of it on its left palm: the mirror's, and later everyone else's.
	var ghost := Presence.Avatar.new()
	add_child(ghost)
	ghost.carry(&"duck")
	var carried := ghost._carried
	ghost._process(0.1)
	var left_glove: Glove = ghost._hands[0]
	check("a ghost carries the duck on its left palm", carried != null and carried.is_inside_tree()
			and carried.global_position.is_equal_approx(ghost.carried_pose().origin)
			and left_glove.target.origin.is_equal_approx(carried.global_position
				- Vector3.UP * Presence.Avatar.PALM_LIFT * left_glove.size)
			and carried.find_children("*", "CollisionShape3D", true, false).is_empty())
	ghost.carry(&"")
	check("and puts it away", ghost._carried == null)
	ghost.queue_free()
	studio.queue_free()
	await get_tree().process_frame


## In a session the duck is the room's (docs/items_loop.md): a pick-up is a hold claimed with
## the host; whoever has it carries it in their ghost's glove, in their colour, where they say
## it is; a squeeze is heard by everyone; only its holder may put it down, and a guest's
## put-down is done at once and asked of the host, whose word then stands.
func _test_the_duck_is_the_rooms() -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	var duck: Item = room.items[&"duck"]
	var key := duck.network_key()
	var hand := studio.get_node("MouseHand") as MouseInteractor
	var presence := studio.presence
	var step := func(seconds: float) -> void:
		for i in int(seconds * 60.0):
			duck._physics_process(1.0 / 60.0)
	var rimmed := func() -> bool:
		for mesh: MeshInstance3D in duck.body.find_children("*", "MeshInstance3D", true, false):
			for i in mesh.get_surface_override_material_count():
				var m := mesh.get_active_material(i) as BaseMaterial3D
				if m != null and m.next_pass != null:
					return true
		return false
	var front := studio.venue.prop_shelf_spot() * Vector3(0, 0, ZoneKit.SHELF.z * 0.5 + Walker.RADIUS + 0.15)
	var spot := Vector2(front.x, front.z)
	check("the studio's company knows the room's items", presence.items == room)
	check("and the duck is the room's, not mine alone", not duck.personal() and key == "RUBBER DUCK")

	# The host, with a guest in the room. On a peer that is always connected, to nobody.
	_as_session(Session.Role.HOST, 1)
	Session.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Session._register(1, "Ada", 0)
	var grace = Session._register(7, "Grace", 1)
	grace.heard_msec = Time.get_ticks_msec()
	grace.head = Transform3D(Basis.IDENTITY, Vector3(-1.0, 1.5, 1.2))
	presence._sync_avatars()
	presence._process(0.016)
	var avatar = presence._avatars[7]

	duck.grab_begin(hand, duck.global_position)
	duck.grab_end(hand)
	presence.claim_carries()
	check("picking it up claims it with the host", hand.carrying == duck and Session.holder_of(key) == 1)
	check("and the room has it in a hand", studio.room_state()["items"].get(&"duck") == [])
	room.lay(duck, spot, 0.0)
	presence.claim_carries()
	check("putting it down lets the claim go", Session.holder_of(key) == 0 and hand.carrying == null)
	check("and the room has it on the floor", (studio.room_state()["items"].get(&"duck", []) as Array).size() == 4)
	duck.snap_home()

	Session._grant(7, key)
	check("a guest's pick-up puts it in her ghost's glove", duck.is_held_elsewhere()
			and presence._item_held_by(7) == duck)
	check("in her colour", rimmed.call())
	check("claimed: hers", duck.claimed_by != null)
	check("and says so, and that it can be taken (%s; %s)" % [duck.readout(), duck.hint()],
			duck.readout() == "in Grace's hand" and duck.hint() == "click to take it from them")
	check("and her ghost's right hand is free: carrying is not pointing", presence._key_held_by(7) == "")
	# Handed over: the host reaches for it in her hand and takes it.
	var told: Array = []
	var heard_notice := func(text: String) -> void: told.append(text)
	Session.notice.connect(heard_notice)
	duck.grab_begin(hand, duck.global_position)
	duck.grab_end(hand)
	check("but held out, the host's grab takes it from her", hand.carrying == duck and duck.taken
			and not duck.is_held_elsewhere() and not rimmed.call())
	presence.claim_carries()
	check("and the hold is handed over, not refused", Session.holder_of(key) == 1)
	Session._hand_over(7, key)
	check("she takes it back: out of the host's hand, into hers", hand.carrying == null
			and duck.is_held_elsewhere() and presence._item_held_by(7) == duck and rimmed.call())
	check("and the host is told who took it (%s)" % [told], told.has("Grace took the rubber duck."))
	presence.claim_carries()
	check("its claim forgotten, not let go of: it is hers now", presence._carry_claims.is_empty()
			and Session.holder_of(key) == 7)
	Session.notice.disconnect(heard_notice)
	Session._grant(7, "KICK  VOLUME")
	Session._hand_over(1, "KICK  VOLUME")
	check("a fader she has cannot be taken from her", Session.holder_of("KICK  VOLUME") == 7)
	Session._release(7, "KICK  VOLUME")
	var says := Transform3D(Basis(Vector3.UP, 0.4), Vector3(-0.2, -0.2, -0.45))
	Session.item_carried.emit(&"duck", says, 7)
	presence._process(0.016)
	avatar._process(0.0)
	step.call(2.0)
	var want: Transform3D = avatar.carried_pose()
	check("it rides where she says it is, relative to her head (%.3f)" % duck.global_position.distance_to(want.origin),
			avatar.carry_at.is_equal_approx(says) and duck.global_position.distance_to(want.origin) < 0.02)
	check("on her ghost's palm", (avatar._hands[0] as Glove).target.origin.distance_to(
			want.origin - Vector3.UP * Presence.Avatar.PALM_LIFT * avatar._hands[0].size) < 0.001
			and avatar._hands[0].pose == Glove.Pose.OPEN)
	check("and her ghost says what it is holding", avatar._caption.text == "HOLDING  RUBBER DUCK")
	duck._squash_speed = 0.0
	Session.item_used.emit(&"duck", true, 9)
	check("a squeeze from someone not holding it is nothing", duck._squash_speed == 0.0)
	Session.item_used.emit(&"duck", true, 7)
	check("hers squeezes ours", duck._squash_speed < -1.0)
	studio._on_room_asked(&"put_item", [&"duck", spot.x, spot.y, 0.3], 9)
	check("nobody else may put it down", duck.is_held_elsewhere())
	studio._on_room_asked(&"put_item", [&"duck", spot.x, spot.y, 0.3], 7)
	check("she may, and it lies where she put it", duck.state == Item.State.LOOSE
			and Vector2(duck.resting.origin.x, duck.resting.origin.z).is_equal_approx(spot))
	check("which the room now says", (studio.room_state()["items"].get(&"duck", []) as Array).size() == 4)
	Session._release(7, key)
	check("her letting go after leaves it there, without her colour", duck.state == Item.State.LOOSE
			and not rimmed.call())
	Session._grant(7, key)
	Session._on_peer_disconnected(7)
	check("carried out of the session, it goes home", duck.state == Item.State.HOME
			and not duck.is_held_elsewhere() and not rimmed.call())

	# A guest, whose pick-up loses a race to the host.
	_as_session(Session.Role.GUEST, 5)
	Session.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	presence._item_holders.clear()
	presence._carry_claims.clear()
	var ada = Session._register(1, "Ada", 0)
	ada.heard_msec = Time.get_ticks_msec()
	ada.head = Transform3D(Basis.IDENTITY, Vector3(1.0, 1.5, 1.2))
	Session._register(5, "Grace", 1)
	presence._sync_avatars()
	presence._process(0.016)
	duck.snap_home()
	duck.grab_begin(hand, duck.global_position)
	duck.grab_end(hand)
	presence.claim_carries()
	check("a guest's pick-up is in its hand at once", hand.carrying == duck and presence._carry_claims.size() == 1)
	var notices: Array[String] = []
	var heard := func(t: String): notices.append(t)
	Session.notice.connect(heard)
	Session._receive_holds({key: 1})
	Session.hold_refused.emit(key, 1)
	Session.notice.disconnect(heard)
	check("refused, it leaves the hand for the ghost of whoever had it", hand.carrying == null
			and duck.is_held_elsewhere() and presence._item_holders.get(&"duck") == 1)
	check("the claim is forgotten, not let go of: it was never ours", presence._carry_claims.is_empty())
	check("and the guest is told whose it is (%s)" % [notices], notices.has("Ada already has rubber duck."))
	var here := {"venue": studio.venue.venue_id(), "variant": studio.venue.variant}
	var with_items := func(entries: Dictionary, acks := 0) -> Dictionary:
		var out := here.duplicate()
		out["items"] = entries
		out["acks"] = {5: acks}
		return out
	studio.apply_room(with_items.call({&"duck": []}))
	check("a room that says it is in a hand leaves it there", duck.is_held_elsewhere())
	studio.apply_room(with_items.call({&"duck": [spot.x, 0.0, spot.y, 0.2]}))
	check("the host's word on where she put it lays it there", duck.state == Item.State.LOOSE
			and Vector2(duck.resting.origin.x, duck.resting.origin.z).is_equal_approx(spot))
	Session._receive_holds({})
	check("and her letting go after leaves it there", duck.state == Item.State.LOOSE and not rimmed.call())

	Session.room_seq = 0
	studio._predictions.clear()
	duck.grab_begin(hand, duck.global_position)
	duck.grab_end(hand)
	var over := Vector3(spot.x + 0.3, 1.6, spot.y + 0.9)
	room.put_down(duck, Transform3D.IDENTITY.translated(over).looking_at(Vector3(spot.x, 0, spot.y)))
	check("a guest's put-down is done at once", duck.state == Item.State.LOOSE)
	check("and asked of the host", studio._predictions.size() == 1 and studio._predictions[0]["verb"] == &"put_item")
	studio.apply_room(with_items.call({}))
	check("a room from before the host heard the ask does not take it back", duck.state == Item.State.LOOSE)
	studio.apply_room(with_items.call({}, Session.room_seq))
	check("the host's answer, that it is home, sends it home", duck.state == Item.State.HOME
			and studio._predictions.is_empty())

	Session.start_solo()
	Session.layout = saved_layout
	studio.queue_free()
	await get_tree().process_frame


## THE SHARING THIS EXISTS FOR: the tablet, headphones, mic and keytar are each one shared Item
## today, claimed in turn (`_test_the_duck_is_the_rooms`, above, proves a toy stays that way, on
## purpose). Picking one of the four up from the shelf now gives the hand a copy of its own
## (`ItemRoom.take_personal`, triggered by `Item._on_grab_begin`'s redirect, the same spawn-and-
## bind `scenes/studio.gd`'s Tour spills already use) instead of a claim on the one shelf copy;
## putting it down retires that copy for good (`ItemRoom.retire`) rather than sending it to a
## shelf spot two people's copies would have to share.
func _test_personal_items_give_each_player_a_copy_of_their_own() -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	var dispenser: Item = room.items[&"tablet"]
	var hand := studio.get_node("MouseHand") as MouseInteractor

	check("a toy is not personal, a tablet is", not (&"duck" in ItemRoom.PERSONAL_KINDS)
			and &"tablet" in ItemRoom.PERSONAL_KINDS)

	_as_session(Session.Role.HOST, 1)
	Session.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Session._register(1, "Ada", 0)

	dispenser.grab_begin(hand, dispenser.global_position)
	check("the shelf's own tablet is never actually held: the grab was given a copy instead",
			dispenser.state == Item.State.HOME and dispenser.held_by == null
			and hand.carrying != null and hand.carrying != dispenser)
	var mine: Item = hand.carrying
	check("the copy is id'd and bound to whoever took it (%s)" % mine.id,
			mine.id == &"tablet1" and mine.bound_to == 1 and mine.bound_name == "Ada")
	check("the shelf keeps its one dispenser, not a second one for the copy", room.items[&"tablet"] == dispenser
			and ItemRoom.KINDS.has(&"tablet") and room.spawned_ids() == [mine.id])

	var other := room.take_personal(&"tablet", 2)
	check("a second peer gets a second, distinct copy of their own", other != null and other != mine
			and other.id == &"tablet2" and other.bound_to == 2)
	check("the host's own hand may hold its own copy, not the other peer's",
			mine.may_hold() and not other.may_hold())
	var real_local_peer := room.local_peer
	room.local_peer = func() -> int: return 2
	check("peer 2's hand may not take peer 1's copy", not mine.may_hold() and other.may_hold())
	room.local_peer = real_local_peer

	room.pocket(mine, 0)
	check("pocketing a copy keeps it real", room.items.has(&"tablet1") and mine.pocket == 0)
	room.pocket(mine, -1)

	room.send_home(mine)
	check("putting it down retires it instead of sending it to a shelf spot",
			not room.items.has(&"tablet1") and mine.get_parent() == null)

	dispenser.grab_begin(hand, dispenser.global_position)
	check("the next pick-up makes a fresh copy, not the retired one",
			hand.carrying != null and hand.carrying.id == &"tablet1" and hand.carrying != mine)

	Session.start_solo()
	Session.layout = saved_layout
	studio.queue_free()
	await get_tree().process_frame


## A throw is launched once and flown the same everywhere (docs/items_loop.md): ballistic, off
## the room's walls and the venue's solids, down onto what it lands on, to rest; and the room
## carries the launch so every copy flies it.
func _test_a_ball_is_thrown_and_flies_the_same_everywhere() -> void:
	var box: Array = [Rect2(-2, -2, 4, 4)]
	var q := Quaternion.IDENTITY
	var a := Flight.fly(Vector3(0, 1.2, 0), Vector3(1.5, 2.0, -6.0), Vector3(-8, 0, 0), q, box, [], 0.78, 0.7, 0.05)
	var b := Flight.fly(Vector3(0, 1.2, 0), Vector3(1.5, 2.0, -6.0), Vector3(-8, 0, 0), q, box, [], 0.78, 0.7, 0.05)
	check("the same launch flies the same flight, step for step", a.points == b.points and a.rest == b.rest
			and a.seconds() == b.seconds())
	check("and comes to rest on the floor, inside the room's walls (%s)" % [a.rest],
			box[0].has_point(Vector2(a.rest.x, a.rest.z)) and is_zero_approx(a.rest.y))
	check("having bounced off a wall on the way (%d hits)" % a.hits.size(), a.hits.size() >= 3
			and a.points.slice(0).to_byte_array().size() > 0
			and Array(a.points).any(func(p: Vector3) -> bool: return p.z < -1.9))
	check("before it ran out of time (%.1fs)" % a.seconds(), a.seconds() < Flight.LONGEST - 0.1)
	var duck := Flight.fly(Vector3(0, 1.2, 0), Vector3(1.5, 2.0, -6.0), Vector3(-8, 0, 0), q, box, [], 0.3, 5.0, 0.12)
	check("a duck thuds where a ball bounces (%d hits, %d)" % [duck.hits.size(), a.hits.size()],
			duck.hits.size() < a.hits.size() and duck.seconds() < a.seconds())

	var wall := {"c": Vector2(0, -1.0), "h": Vector2(1.5, 0.05), "a": 0.0, "top": 1.25}
	var off := Flight.fly(Vector3(0, 0.6, 0), Vector3(0, 0.5, -4.0), Vector3.ZERO, q, box, [wall], 0.6, 2.0, 0.05)
	check("a solid in the way is bounced off, not flown through (%s)" % [off.rest], off.rest.z > -0.95
			and not Array(off.points).any(func(p: Vector3) -> bool: return Walker._gap(wall, Vector2(p.x, p.z)) <= 0.0))
	var riser := {"c": Vector2(0, 0), "h": Vector2(0.8, 0.8), "a": 0.3, "top": 0.2}
	var onto := Flight.fly(Vector3(0, 1.0, 0), Vector3(0.2, 0, 0.1), Vector3.ZERO, q, box, [riser], 0.3, 4.0, 0.05)
	check("one that comes down on a riser rests on top of it (%.3f)" % onto.rest.y, is_equal_approx(onto.rest.y, 0.2))
	var tilted := Flight.fly(Vector3(0, 0.15, 0.9), Vector3(0, 0, -3.0), Vector3.ZERO, q, box, [riser], 0.5, 2.0, 0.05)
	check("and one thrown low at its side does not end up inside it (%s)" % [tilted.rest],
			Walker._gap(riser, Vector2(tilted.rest.x, tilted.rest.z)) > 0.0 or is_equal_approx(tilted.rest.y, 0.2))

	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	check("the shelf has a ball on it too", room.items.has(&"ball")
			and (room.items[&"ball"] as Item).state == Item.State.HOME)
	var ball: Item = room.items[&"ball"]
	var hand := studio.get_node("MouseHand") as MouseInteractor
	var asks: Array = []
	var heard := func(verb: StringName, args: Array) -> void: asks.append([verb, args])
	room.asked.connect(heard)
	var landings := [0]
	ball.landed.connect(func() -> void: landings[0] += 1)
	var front := studio.venue.prop_shelf_spot() * Vector3(0, 0, ZoneKit.SHELF.z * 0.5 + Walker.RADIUS + 0.15)

	hand.pick_up(ball)
	hand.begin_throw()
	check("winding up draws the hand back", hand.charge() >= 0.0 and hand._charge_from >= 0)
	hand._charge_from -= int(MouseInteractor.CHARGE_SECONDS * 1000.0)
	check("all the way after a long hold", is_equal_approx(hand.charge(), 1.0)
			and hand.carry_pose().origin.distance_to(hand.camera.global_transform * MouseInteractor.CARRY_AT) > 0.1)
	hand.release_throw()
	check("letting go throws it: out of the hand, in the air", hand.carrying == null and ball.is_flying()
			and ball.state == Item.State.LOOSE and hand.charge() == 0.0)
	check("and says so, with the launch (%s)" % [asks], asks.size() == 1 and asks[0][0] == &"throw_item"
			and Session.room_ask_is_valid(&"throw_item", asks[0][1]))
	var entry: Array = room.state()[&"ball"]
	check("the room carries the launch while it flies (%d)" % entry.size(), entry.size() == 8
			and int(entry[4]) == ball.throws and ball.throws == 1)
	var hard: Vector3 = (asks[0][1][2] as Vector3)
	check("a full wind-up is a hard throw (%.1f m/s)" % hard.length(), is_equal_approx(hard.length(), MouseInteractor.THROW_FASTEST))
	var flight := ball.flight
	var rest := flight.rest
	for i in int(flight.seconds() * 60.0) + 2:
		ball._physics_process(1.0 / 60.0)
	var landed_at := ball.position
	for i in 120:
		ball._physics_process(1.0 / 60.0)
	check("it comes down where the flight said, once, and settles there (%s %s %s)" % [landed_at, ball.position, rest],
			not ball.is_flying() and landings[0] == 1 and landed_at.distance_to(rest) < 0.1
			and ball.position.distance_to(rest) < 0.01)
	check("and the room has it lying there, no longer flying", (room.state()[&"ball"] as Array).size() == 4
			or ball.state == Item.State.HOME)

	# Somebody else's copy, told by the room it was thrown, flies the same throw.
	var other := ItemRoom.new()
	other.floor_rects = room.floor_rects
	other.solids = room.solids
	other.fits = room.fits
	other.ground_at = room.ground_at
	studio.studio_set.add_child(other)
	var theirs: Item = other.items[&"ball"]
	other.apply({&"ball": entry})
	check("a copy that has not flown the throw flies it", theirs.is_flying() and theirs.throws == 1)
	check("to the same place (%s, %s)" % [theirs.flight.rest, rest], theirs.flight.rest.is_equal_approx(rest)
			and theirs.flight.points == flight.points)
	theirs.flight = null
	theirs.resting = Transform3D(Basis.IDENTITY, Vector3(entry[0], entry[1], entry[2]))
	other.apply({&"ball": entry})
	check("and does not fly it twice", not theirs.is_flying())
	other.queue_free()

	# Thrown somewhere nobody could stand to fetch it: it comes down, and then goes home.
	ball.snap_home()
	hand.pick_up(ball)
	var keep := room.fits
	room.fits = func(_p: Vector2) -> bool: return false
	hand.throw_with(0.2)
	room.fits = keep
	check("one coming down where it cannot stay flies first", ball.is_flying())
	for i in int(ball.flight.seconds() * 60.0) + 2:
		ball._physics_process(1.0 / 60.0)
	check("and then goes home", ball.state == Item.State.HOME)

	# The host flies a guest's throw; nobody else's.
	_as_session(Session.Role.HOST, 1)
	ball.snap_home()
	Session._grant(7, ball.network_key())
	studio._on_room_asked(&"throw_item", [&"ball", Vector3(front.x, 1.2, front.z), Vector3(0, 2, 1), Vector3.ZERO], 9)
	check("the host will not fly a throw from someone without the ball", not ball.is_flying())
	studio._on_room_asked(&"throw_item", [&"ball", Vector3(front.x, 1.2, front.z), Vector3(0, 2, 1), Vector3.ZERO], 7)
	check("but flies its holder's", ball.is_flying())
	Session.start_solo()

	room.asked.disconnect(heard)
	Session.layout = saved_layout
	studio.queue_free()
	await get_tree().process_frame


## The paper plane (docs/items_loop.md): a good throw crosses the room, a bad one noses into the
## floor, a hard one flutters and falls short, a lean turns it, and touching anything ends the
## glide.
func _test_a_paper_plane_glides() -> void:
	var box: Array = [Rect2(-20, -20, 40, 40)]
	var q := Quaternion.IDENTITY
	var paper: Dictionary = PlaneItem.new().flies()
	var wing: Dictionary = paper["wing"]
	var level := func(speed: float, pitch: float, lean := 0.0, floor := box) -> Flight:
		var w := wing.duplicate()
		w["bank"] = lean
		return Flight.fly(Vector3(0, 1.4, 0), Vector3(0, sin(pitch), -cos(pitch)) * speed, Vector3.ZERO, q,
				floor, [], paper["bounce"], paper["roll"], paper["drag"], w)
	var down := func(f: Flight) -> Vector3:
		for p in f.points:
			if p.y <= 0.001:
				return p
		return f.rest
	var good: Flight = level.call(4.5, 0.16)
	var thrown := Flight.fly(Vector3(0, 1.4, 0), Vector3(0, sin(0.16), -cos(0.16)) * 4.5, Vector3.ZERO, q, box, [],
			paper["bounce"], paper["roll"], paper["drag"])
	check("a good throw glides: it comes down %.1fm out, where the same throw without wings falls at %.1fm"
			% [-(down.call(good) as Vector3).z, -(down.call(thrown) as Vector3).z],
			-(down.call(good) as Vector3).z > 6.0 and -(down.call(thrown) as Vector3).z < 3.0)
	var top := 0.0
	for p in good.points:
		top = maxf(top, p.y)
	check("level, not up into the ceiling (%.2fm at most)" % top, top < 1.7)
	check("and it is the same glide every time", (level.call(4.5, 0.16) as Flight).points == good.points)
	var dive: Flight = level.call(4.5, -0.6)
	check("thrown at the floor, it noses in close (%.1fm)" % -(down.call(dive) as Vector3).z,
			-(down.call(dive) as Vector3).z < 2.5)
	var hard: Flight = level.call(8.0, 0.16)
	check("thrown as hard as you can, the paper flutters and it goes little further (%.1fm)" % -(down.call(hard) as Vector3).z,
			-(down.call(hard) as Vector3).z < -(down.call(good) as Vector3).z + 3.0)
	var weak: Flight = level.call(2.2, 0.16)
	check("and lobbed, it drops (%.1fm)" % -(down.call(weak) as Vector3).z, -(down.call(weak) as Vector3).z < 2.5)
	var right: Flight = level.call(4.5, 0.16, 0.3)
	var left: Flight = level.call(4.5, 0.16, -0.3)
	check("leaning right it turns right, and left, left (%.1f, %.1f)" % [right.rest.x, left.rest.x],
			right.rest.x > 1.0 and left.rest.x < -1.0)
	var near: Array = [Rect2(-2, -2, 4, 4)]
	var walled: Flight = level.call(4.5, 0.16, 0.0, near)
	check("into a wall, it stops gliding and drops at its foot (%s)" % [walled.rest],
			walled.rest.z > -2.0 and walled.rest.z < -1.4 and walled.seconds() < good.seconds())

	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	var plane: Item = room.items.get(&"plane")
	check("the shelf has a paper plane on it", plane is PlaneItem and plane.state == Item.State.HOME
			and plane.position.is_equal_approx(studio.venue.item_spots()[2].origin))
	var walker := studio.walker
	var by_wall := Vector2.INF
	for r: Rect2 in walker.walkable:
		var p := Vector2(r.position.x + 0.06, r.get_center().y)
		if walker.reachable(p) and not walker.fits(p):
			by_wall = p
			break
	check("a thing against a wall can lie there, though nobody could stand there (%s)" % [by_wall],
			by_wall != Vector2.INF)
	var shelf_print: Dictionary = studio.venue.solids().back()
	check("but not inside the shelf, nor off the floor", not walker.reachable(shelf_print["c"])
			and not walker.reachable(Vector2(1000, 1000)))
	var hand := studio.get_node("MouseHand") as MouseInteractor
	hand.pick_up(plane)
	var start := hand.carry_pose().origin
	hand.throw_with(0.4)
	check("thrown, it is in the air on a glide (%.1fs)" % (plane.flight.seconds() if plane.flight else 0.0),
			plane.is_flying() and plane.flight.seconds() > 0.6)
	var entry: Array = room.state()[&"plane"]
	var other := ItemRoom.new()
	other.floor_rects = room.floor_rects
	other.solids = room.solids
	other.fits = room.fits
	other.ground_at = room.ground_at
	studio.studio_set.add_child(other)
	other.apply({&"plane": entry})
	var theirs: Item = other.items[&"plane"]
	check("and anyone else's copy flies the same glide", theirs.is_flying()
			and theirs.flight.points == plane.flight.points)
	other.queue_free()
	Session.layout = saved_layout
	studio.queue_free()
	await get_tree().process_frame


## Catching (docs/items_loop.md): an empty hand catches what is thrown at it, once it has left the
## hand that threw it; a full one does not, nor one it misses.
func _test_a_throw_is_caught() -> void:
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	var ball: Item = room.items[&"ball"]
	var duck: Item = room.items[&"duck"]
	var hand := studio.get_node("MouseHand") as MouseInteractor
	# In the air on a throw, `t` seconds in, with its middle at `at`.
	var flying_at := func(at: Vector3, t: float) -> void:
		ball.snap_home()
		room.fly(ball, ball.position, Vector3(0, 3, 0), Vector3.ZERO)
		ball._flight_t = t
		ball.global_position = at - Vector3.UP * ball.centre_height()
	var head := hand.catch_point()
	check("a screen's hand catches round its head (%.2fm ahead)" % hand.camera.global_position.distance_to(head),
			hand.catch_reach() > 0.3 and hand.camera.global_position.distance_to(head) < 0.4)
	flying_at.call(head + Vector3(0.1, 0.05, 0), 0.2)
	hand._catch()
	check("not a throw still leaving the hand", hand.carrying == null and ball.is_flying())
	flying_at.call(head + Vector3(0.1, 0.05, 0), 0.6)
	hand._catch()
	check("but one thrown at it, it catches", hand.carrying == ball and not ball.is_flying()
			and ball.state == Item.State.HELD)
	check("caught is carried, like anything picked up", ball.carried_by == hand and not ball.taken)
	hand.put_down()
	hand.pick_up(duck)
	flying_at.call(head, 0.6)
	hand._catch()
	check("a full hand does not", hand.carrying == duck and ball.is_flying())
	duck.snap_home()
	hand.lose_carrying()
	flying_at.call(head + Vector3(0, 0, 1.0), 0.6)
	hand._catch()
	check("nor one that goes by out of reach", hand.carrying == null and ball.is_flying())
	var lying := head + Vector3(0.1, 0, 0)
	ball.snap_home()
	ball.global_position = lying
	hand._catch()
	check("and nothing that is not in the air", hand.carrying == null)
	var xr := XRInteractor.new()
	check("a headset's hand catches in its palm, a hand's span", xr.catch_reach() > 0.0 and xr.catch_reach() < 0.25)
	xr.free()
	Session.layout = saved_layout
	studio.queue_free()
	await get_tree().process_frame


## The mic (docs/items_loop.md): picked up here it puts your voice on a track -- the host's
## armed and monitored, a guest's taken with the host's -- and put down, the track is as it was.
func _test_a_mic_arms_a_track_and_puts_it_back() -> void:
	_offline()
	var tracks := DAW.state.tracks
	var vox := MicArm.track_for(tracks)
	check("a mic goes to the track named for a voice (%s)" % DAW.state.track(vox).name,
			DAW.state.track(vox).name == "Lead Vox")
	check("or the one a guest already chose for their mic", MicArm.track_for(tracks, 3) == 3)
	check("and a choice that is not a track is not one", MicArm.track_for(tracks, 99) == vox)
	var plain := {}
	for i in [4, 2, 9]:
		var t := MixState.TrackState.new()
		t.name = "Gtr %d" % i
		plain[i] = t
	check("with none for a voice, the first track", MicArm.track_for(plain) == 2)
	check("and with no tracks, none", MicArm.track_for({}) == 0)

	var told: Array = []
	var listen := func(text: String): told.append(text)
	Session.notice.connect(listen)
	var saved_role := Session.role
	Session.role = Session.Role.SOLO
	var t := DAW.state.track(vox)
	t.rec_arm = false
	t.monitor = DAW.MONITOR_AUTO
	var arm := MicArm.new()
	arm.take()
	check("taken up here, it arms that track and monitors it", t.rec_arm and t.monitor == DAW.MONITOR_ON)
	check("and says so (%s)" % [told], told.size() == 1 and (told[0] as String).contains("Lead Vox, armed"))
	arm.take()
	check("taken twice is still one take", told.size() == 1)
	arm.let_go()
	check("put down, the track is as it was", not t.rec_arm and t.monitor == DAW.MONITOR_AUTO and arm.track == 0)
	t.rec_arm = true
	arm.take()
	arm.let_go()
	check("one already armed stays armed", t.rec_arm)
	t.rec_arm = false

	var saved_audio := Session.guest_audio
	var audio := GuestAudio.new()
	Session.guest_audio = audio
	Session.role = Session.Role.GUEST
	audio.target_track = 0
	arm.take()
	check("a guest's mic records their voice onto it with the host", audio.target_track == vox
			and audio.record_with_host)
	check("and arms nothing on the host, whose input would record over it", not t.rec_arm)
	check("and says when it records (%s)" % [told], (told.back() as String).contains("records when the host records"))
	arm.let_go()
	check("put down, the guest's recording is as it was", audio.target_track == 0 and not audio.record_with_host)
	audio.target_track = 5
	arm.take()
	check("a guest who chose a track sings into it", audio.target_track == 5 and audio.record_with_host)
	arm.let_go()
	check("and keeps it after", audio.target_track == 5 and not audio.record_with_host)
	audio.free()
	Session.guest_audio = saved_audio
	Session.role = saved_role
	Session.notice.disconnect(listen)


## The mic in the studio: it lives in the booth's stand, it is live only in a hand here, and the
## studio arms on it.
func _test_the_mic_lives_in_the_stand_and_is_live_in_a_hand() -> void:
	_offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	var saved_role := Session.role
	Session.role = Session.Role.SOLO
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	var mic := room.items.get(&"mic") as MicItem
	check("there is a mic", mic != null and mic.state == Item.State.HOME)
	var wrong: Array = []
	for id in Venue.IDS:
		studio.set_venue(id, false)
		var stand := studio.venue.find_child("MicStand", true, false) as Node3D
		var spot: Variant = studio.venue.mic_spot()
		if stand == null:
			if spot != null:
				wrong.append("%s: a spot with no stand" % id)
			continue
		var clip := stand.get_node("Clip") as Node3D
		var middle := mic.global_transform * Vector3(0, MicItem.AXIS_HEIGHT, 0)
		if middle.distance_to(clip.global_position) > 0.03:
			wrong.append("%s: %.2fm from the clip" % [id, middle.distance_to(clip.global_position)])
		if (mic.global_basis * Vector3.FORWARD).dot(stand.global_basis * Vector3.FORWARD) < 0.9:
			wrong.append("%s: not along the boom" % id)
	check("in every venue with a stand, the mic is in its clip, along the boom (%s)" % [wrong], wrong.is_empty())
	studio.set_venue(&"chalk", false)
	var shelf := studio.venue.item_spots()
	check("with no stand it takes a place on the shelf", studio.venue.mic_spot() != null
			or shelf.any(func(s: Transform3D) -> bool: return s.origin.is_equal_approx(mic.home.origin)))
	studio.set_venue(&"studio", false)
	shelf = studio.venue.item_spots()
	check("and the shelf's places still go to the others in order",
			(room.items[&"duck"] as Item).home.origin.is_equal_approx(shelf[0].origin)
			and (room.items[&"plane"] as Item).home.origin.is_equal_approx(shelf[2].origin))

	var lit := func() -> float: return mic._band.emission_energy_multiplier
	var vox := MicArm.track_for(DAW.state.tracks)
	var t := DAW.state.track(vox)
	t.rec_arm = false
	var hand := studio.get_node("MouseHand") as MouseInteractor
	check("at home it is dark and live nowhere", not mic.live and lit.call() == 0.0)
	hand.pick_up(mic)
	check("picked up here it is live, and its band glows", mic.live and lit.call() > 0.0)
	check("and the studio arms a track for it", t.rec_arm and studio.mic_arm.track == vox)
	hand.put_down()
	check("put down, it is not, and the track is not armed", not mic.live and lit.call() == 0.0
			and not t.rec_arm)
	hand.pick_up(mic)
	hand.throw_with(0.4)
	check("thrown, it is not live either", not mic.live and not t.rec_arm)
	mic.snap_home()
	var palm := func() -> Transform3D: return Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))
	mic.follow(palm)
	check("in someone else's hand it glows but is not live here", lit.call() > 0.0 and not mic.live
			and not t.rec_arm)
	mic.snap_home()
	hand.pick_up(mic)
	hand.lose_carrying()
	mic.follow(palm)
	check("taken from this hand, it lets the track go", not mic.live and not t.rec_arm)
	mic.snap_home()
	Session.role = saved_role
	Session.layout = saved_layout
	studio.queue_free()
	await get_tree().process_frame


## Headphones on: the room's own sounds drop, and the personal mix plays -- the mix and your
## keys until the tablet says otherwise.
func _test_headphones_shut_the_room_out() -> void:
	AudioPorts.ensure_buses()
	Ears.listen(true)
	check("on, the mix and your keys play as they were", is_zero_approx(Ears.gain_db(Ears.MIX))
			and is_zero_approx(Ears.gain_db(Ears.KEYS)))
	check("and the room is shut out (%.0f dB)" % Ears.gain_db(Ears.ROOM), Ears.gain_db(Ears.ROOM) == Ears.ROOM_DB)
	Ears.listen(true, {Ears.MIX: -6.0})
	check("a personal mix plays what is in it at its level", Ears.gain_db(Ears.MIX) == -6.0)
	check("and nothing of what is not", Ears.gain_db(Ears.KEYS) == Ears.OFF_DB)
	Ears.listen(false)
	check("off, everything is as it was", is_zero_approx(Ears.gain_db(Ears.MIX))
			and is_zero_approx(Ears.gain_db(Ears.KEYS)) and is_zero_approx(Ears.gain_db(Ears.ROOM)))
	check("a guest's mix is the game's to change", Ears.reaches_mix(true, false))
	check("so is a host's on the built-in engine", Ears.reaches_mix(false, false))
	check("but not a host's on Reaper, which plays through the system", not Ears.reaches_mix(false, true))


## The headphones in the studio: they hang on the shelf's hook, go on your head from your hand
## and back, the room carries that they are on, and a ghost wears them in place of its hat.
func _test_headphones_go_on_your_head() -> void:
	_offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	var saved_role := Session.role
	Session.role = Session.Role.SOLO
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	var phones := room.items.get(&"headphones") as HeadphonesItem
	check("there are headphones, at home", phones != null and phones.state == Item.State.HOME)
	var wrong: Array = []
	for id in Venue.IDS:
		studio.set_venue(id, false)
		if not phones.home.is_equal_approx(studio.venue.headphones_spot()):
			wrong.append(id)
	check("in every venue they hang on the shelf's hook (%s)" % [wrong], wrong.is_empty() and phones.own_home)
	studio.set_venue(&"studio", false)
	for i in 30:
		phones._process(0.1)
	check("hung, their cups are square, not swivelled flat", is_zero_approx(phones._flat))

	var hand := studio.get_node("MouseHand") as MouseInteractor
	var self_only := func() -> bool:
		return phones.body.find_children("*", "VisualInstance3D", true, false).all(
				func(v: VisualInstance3D) -> bool: return v.layers == Mirror.SELF_ONLY)
	hand.pick_up(phones)
	check("picked up, they are in the hand and not on a head", hand.carrying == phones and not phones.on_head)
	phones.use(true)
	check("a click puts them on, and the hand is free", hand.carrying == null and hand.worn == phones
			and phones.on_head and phones.carried_by == hand and phones.state == Item.State.HELD)
	check("the room has them on a head", room.state().get(&"headphones") == [true])
	check("you see them only in your mirror", self_only.call())
	check("and the room is shut out", Ears.gain_db(Ears.ROOM) == Ears.ROOM_DB)
	studio._toggle_headphones()
	check("H takes them off into your hand", hand.carrying == phones and hand.worn == null
			and not phones.on_head and room.state().get(&"headphones") == [])
	check("seen again, and the room heard again", not self_only.call() and is_zero_approx(Ears.gain_db(Ears.ROOM)))
	studio._toggle_headphones()
	check("H puts them back on", hand.worn == phones and phones.on_head)
	var duck := room.items[&"duck"] as Item
	hand.pick_up(duck)
	var told: Array = []
	var listen := func(text: String): told.append(text)
	Session.notice.connect(listen)
	studio._toggle_headphones()
	check("with your hand full they stay on, and you are told why (%s)" % [told], hand.worn == phones
			and told.size() == 1 and (told[0] as String).contains("hand is full"))
	Session.notice.disconnect(listen)
	duck.snap_home()
	hand.lose_carrying()
	check("taken off by hand", hand.take_off() and hand.carrying == phones)
	phones.lay_down(Vector3(0, 0, 1.5), 0.0)
	for i in 30:
		phones._process(0.1)
	check("left lying, they are off every head with their cups flat", not phones.on_head
			and hand.carrying == null and is_equal_approx(phones._flat, 1.0))

	phones.snap_home()
	var palm := func() -> Transform3D: return Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))
	phones.follow(palm)
	room.apply({&"headphones": [true]})
	check("in somebody else's hand, the room puts them on their head", phones.on_head and phones._shape.disabled)
	check("and nothing changes in your ears", is_zero_approx(Ears.gain_db(Ears.ROOM)))
	room.apply({&"headphones": []})
	check("and takes them off again", not phones.on_head and not phones._shape.disabled)
	studio._on_room_asked(&"wear_item", [&"headphones", true], 0)
	check("a host puts them on the head of whoever has them", phones.on_head)
	phones.snap_home()
	studio._on_room_asked(&"wear_item", [&"headphones", true], 0)
	check("but not when nobody has them", not phones.on_head)

	var ghost := Presence.Avatar.new()
	add_child(ghost)
	ghost.wear_item(true)
	var pose := ghost.worn_pose()
	check("a ghost wearing them takes its hat off", not ghost._hat.visible)
	check("and wears them at the size of its head", pose.basis.get_scale().x > 1.0)
	ghost.wear_item(false)
	check("and puts its hat back when they come off", ghost._hat.visible)
	ghost.queue_free()

	hand.pick_up(phones)
	hand.wear()
	studio.queue_free()
	await get_tree().process_frame
	check("leaving the studio with them on gives you the room back", is_zero_approx(Ears.gain_db(Ears.ROOM)))
	Session.role = saved_role
	Session.layout = saved_layout


## A personal mix: four receivers, each plugged into a source or not, each at a level, and what
## a pair of headphones plays is what they add up to.
func _test_a_personal_mix_adds_up_its_receivers() -> void:
	var mix := PersonalMix.new()
	var changes := [0]
	mix.changed.connect(func() -> void: changes[0] += 1)
	check("a new one has four receivers, all in the tray", mix.sockets.size() == PersonalMix.RECEIVERS
			and not mix.is_patched())
	check("with nothing patched, headphones play the mix and your keys", mix.ears_levels() == Ears.PERSONAL)
	mix.set_sockets(["mix"])
	check("one plug in MIX: the mix alone, at unity (%s)" % [mix.ears_levels()],
			mix.ears_levels() == {Ears.MIX: 0.0} and mix.bus_of(0) == Ears.MIX and mix.bus_of(1) == &"")
	mix.set_level(0, -6.0)
	check("at its receiver's level", is_equal_approx(float(mix.ears_levels()[Ears.MIX]), -6.0))
	mix.set_level(0, 0.0)
	mix.set_sockets(["mix", "mix"])
	check("two receivers on one source add up (%.2f dB)" % float(mix.ears_levels()[Ears.MIX]),
			absf(float(mix.ears_levels()[Ears.MIX]) - 6.02) < 0.01)
	mix.set_sockets(["mix", "keys"])
	mix.set_level(1, PersonalMix.FLOOR_DB)
	check("a receiver turned all the way down is not in it", mix.ears_levels() == {Ears.MIX: 0.0})
	mix.set_level(1, 100.0)
	check("and one turned all the way up stops at the top", mix.levels_db[1] == PersonalMix.TOP_DB)
	var before: int = changes[0]
	mix.set_sockets(["mix", "keys"])
	mix.set_level(1, PersonalMix.TOP_DB)
	check("telling it what it already is changes nothing", changes[0] == before)
	mix.set_sockets(["nowhere"])
	check("a socket there is not is the tray", not mix.is_patched())
	check("the sockets there are", PersonalMix.valid_socket(&"mix") and PersonalMix.valid_socket(&"keys")
			and PersonalMix.valid_socket(&"") and not PersonalMix.valid_socket(&"talkback"))
	check("and a strip's, by its track", PersonalMix.track_socket(5) == &"track_5"
			and PersonalMix.track_of(&"track_5") == 5 and PersonalMix.valid_socket(&"track_5")
			and not PersonalMix.valid_socket(&"track_") and not PersonalMix.valid_socket(&"track_x")
			and not PersonalMix.valid_socket(&"track_0") and PersonalMix.track_of(&"mix") == 0)
	mix.set_level(1, 0.0)
	mix.set_sockets(["track_5", "mix", "track_5", "track_2"])
	check("where the tracks are not played here, one patched is not heard (%s)" % [mix.ears_levels()],
			mix.unheard(0) and not mix.unheard(1) and mix.ears_levels() == {Ears.MIX: 0.0})
	before = changes[0]
	mix.hears_tracks = true
	check("where they are, it is the track's cue", changes[0] == before + 1 and not mix.unheard(0)
			and mix.bus_of(0) == GodotBackend.cue_bus(5) and mix.ears_levels().has(GodotBackend.cue_bus(2)))
	check("the tracks patched, each once, in order", mix.tracks() == [2, 5])
	check("a player's keys, by their peer", PersonalMix.player_socket(7) == &"keys_7"
			and PersonalMix.player_of(&"keys_7") == 7 and PersonalMix.valid_socket(&"keys_7")
			and PersonalMix.player_of(&"keys") == 0 and PersonalMix.player_of(&"track_7") == 0)
	mix.hears_tracks = false
	mix.set_sockets(["keys_7", "keys_7", "keys_3"])
	check("heard wherever this machine is: their notes are played here (%s)" % [mix.ears_levels()],
			not mix.unheard(0) and mix.bus_of(0) == TheirKeys.bus_of(7) and mix.players() == [3, 7]
			and mix.ears_levels().has(TheirKeys.bus_of(3)))


## The tablet in the studio: it lies on the shelf's lower tier, shows your personal mix on its
## glass only in your hand, its plugs go into the desk's SEND sockets for everyone to see, and
## headphones play what they patch.
func _test_the_tablet_patches_your_headphones() -> void:
	_offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	var saved_role := Session.role
	Session.role = Session.Role.SOLO
	AudioPorts.ensure_buses()
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	var tablet := room.items.get(&"tablet") as TabletItem
	check("there is a tablet, at home", tablet != null and tablet.state == Item.State.HOME)
	var wrong: Array = []
	for id in Venue.IDS:
		studio.set_venue(id, false)
		var shelf := studio.venue.prop_shelf_spot().affine_inverse() * tablet.home.origin
		if not tablet.home.is_equal_approx(studio.venue.tablet_spot()) or shelf.y > ZoneKit.SHELF.y \
				or absf(shelf.x) + 0.13 > ZoneKit.SHELF.x * 0.5 or absf(shelf.z) + 0.1 > ZoneKit.SHELF.z * 0.5:
			wrong.append(id)
	check("in every venue it lies on the shelf's lower tier (%s)" % [wrong], wrong.is_empty())
	studio.set_venue(&"studio", false)
	check("at home its glass is dark and shows nothing", tablet.face == null
			and tablet._glass.emission_energy_multiplier == 0.0)

	var hand := studio.get_node("MouseHand") as MouseInteractor
	hand.pick_up(tablet)
	var face := tablet.face
	check("in your hand its glass lights with your personal mix", face != null and face.is_inside_tree()
			and tablet._glass.emission_energy_multiplier > 0.0 and face.mix == studio.personal)
	check("four receivers, each with a level and a plug", face._rows.size() == 4 and face._senders.size() == 4)
	var sends := studio.console.master.sends
	check("the desk has a SEND socket for the mix and one for your keys", sends.size() == 2
			and sends[0].source == &"mix" and sends[1].source == &"keys")
	var told: Array = []
	var listen := func(text: String): told.append(text)
	Session.notice.connect(listen)
	var sender: TabletFace.Sender = face._senders[0]
	sender.grab_begin(hand, sender.global_position)
	sender.grab_move(hand, sends[0].global_position)
	hand.hovered = sends[0]
	sender.grab_end(hand)
	hand.hovered = null
	var me := Session.local_peer_id
	check("plug A dropped on SEND MIX is in it (%s)" % [studio.patches], studio.patches.get(me) == ["mix", "", "", ""]
			and studio.personal.sockets[0] == &"mix")
	check("for everyone to see, in your colour", sends[0].plug_count() == 1 and sends[1].plug_count() == 0)
	check("its place in the tray is empty, and its row says MIX", not sender._plug.visible
			and (face._rows[0]["source"] as Label3D).text == "MIX")
	check("and you are told (%s)" % [told], told.size() == 1 and (told[0] as String).contains("Plug A in SEND MIX"))
	check("the room carries it", (studio.room_state()["patches"] as Dictionary).get(me) == ["mix", "", "", ""])
	sender.grab_begin(hand, sender.global_position)
	sender.grab_move(hand, sender.global_position + Vector3(0, 0.1, 0))
	hand.hovered = null
	sender.grab_end(hand)
	check("dragged off nowhere, a plug stays where it was", studio.patches.get(me) == ["mix", "", "", ""])

	hand.lose_carrying()
	tablet.snap_home()
	check("put back, its glass goes dark, and the plug stays in", tablet.face == null
			and studio.personal.sockets[0] == &"mix" and sends[0].plug_count() == 1)
	var phones := room.items[&"headphones"] as HeadphonesItem
	hand.pick_up(phones)
	hand.wear()
	check("headphones on play what is patched: the mix, not your keys",
			is_zero_approx(Ears.gain_db(Ears.MIX)) and Ears.gain_db(Ears.KEYS) == Ears.OFF_DB)
	studio.personal.set_level(0, -9.0)
	check("at the receiver's level, at once", is_equal_approx(Ears.gain_db(Ears.MIX), -9.0))
	studio._on_patch_asked(1, &"keys")
	check("a second plug in KEYS brings your keys in", is_zero_approx(Ears.gain_db(Ears.KEYS))
			and sends[1].plug_count() == 1)
	studio._on_send_pressed(&"mix")
	check("clicking SEND MIX brings your plug back from it", studio.patches.get(me) == ["", "keys", "", ""]
			and sends[0].plug_count() == 0 and Ears.gain_db(Ears.MIX) == Ears.OFF_DB)
	told.clear()
	studio._on_send_pressed(&"mix")
	check("with none of yours in it, it says where the plugs are (%s)" % [told], told.size() == 1
			and (told[0] as String).contains("lower tier"))
	Session.notice.disconnect(listen)

	studio._on_room_asked(&"patch", [2, &"mix"], 7)
	check("a host puts a guest's plug where they asked", studio.patches.get(7) == ["", "", "mix", ""]
			and sends[0].plug_count() == 1)
	check("and it is not in your ears", studio.personal.sockets[2] == &"")
	studio._on_room_asked(&"patch", [2, &"talkback"], 7)
	check("but not into a socket there is not", studio.patches.get(7) == ["", "", "mix", ""])
	studio._on_room_asked(&"patch", [2, &""], 7)
	check("and a guest with every plug back in the tray has no row", not studio.patches.has(7))
	studio.apply_room({"patches": {7: ["keys", "", "", ""]}})
	check("the host's room says where everyone's plugs are, yours too", studio.patches == {7: ["keys", "", "", ""]}
			and not studio.personal.is_patched() and sends[1].plug_count() == 1)
	check("and with none of yours in, the headphones are back to the mix and your keys",
			is_zero_approx(Ears.gain_db(Ears.MIX)) and is_zero_approx(Ears.gain_db(Ears.KEYS)))

	hand.take_off()
	hand.lose_carrying()
	phones.snap_home()
	studio.queue_free()
	await get_tree().process_frame
	Session.role = saved_role
	Session.layout = saved_layout


## The built-in engine plays a cue of a track on request: the same part, in time, through the
## track's own effects but not its fader, on a bus of its own for headphones.
func _test_a_track_has_a_cue_for_headphones() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	check("nothing is cued to begin with", backend.cues().is_empty()
			and AudioServer.get_bus_index(GodotBackend.cue_bus(2)) < 0)
	backend.set_cues([2, 99, 2])
	var cue := AudioServer.get_bus_index(GodotBackend.cue_bus(2))
	var own: int = backend._bus[2]
	check("a cue of a track there is, once (%s)" % [backend.cues()], backend.cues() == [2] and cue >= 0)
	var shared := AudioServer.get_bus_effect_count(own) - 1 == AudioServer.get_bus_effect_count(cue) \
			and AudioServer.get_bus_effect_count(cue) > 0
	for slot in range(1, AudioServer.get_bus_effect_count(own)):
		shared = shared and AudioServer.get_bus_effect(own, slot) == AudioServer.get_bus_effect(cue, slot - 1)
	check("through the track's own effects, the very ones, and not its panner", shared)
	check("to Master, not into the mix", AudioServer.get_bus_send(cue) == &"Master")
	var players: Array = backend._players[2].filter(func(p: Node) -> bool: return p.has_meta(&"cue"))
	check("played by a player of its own", players.size() == 1
			and (players[0] as AudioStreamPlayer).bus == GodotBackend.cue_bus(2))
	DAW.state.playing = true
	DAW.state.position_seconds = 40.0
	backend._sync_players()
	var main: AudioStreamPlayer = backend._players[2][0]
	check("the same part, at the same place in it", players[0].playing and players[0].stream == main.stream
			and absf(players[0].get_playback_position() - main.get_playback_position()) < 0.01)
	DAW.state.playing = false
	backend._sync_players()
	DAW.set_track_volume(2, 0.1)
	backend._apply_tracks()
	check("before the fader: pulling the track down does not pull its cue down",
			is_zero_approx(AudioServer.get_bus_volume_db(cue)) and is_zero_approx(players[0].volume_db))
	DAW.set_track_mute(2, true)
	check("but muting it mutes it", AudioServer.is_bus_mute(cue))
	DAW.set_track_mute(2, false)
	var had := AudioServer.get_bus_effect_count(cue)
	backend.add_effect(2, &"reverb")
	cue = AudioServer.get_bus_index(GodotBackend.cue_bus(2))
	check("an effect added to the track is in its cue too", AudioServer.get_bus_effect_count(cue) == had + 1
			and AudioServer.get_bus_effect(cue, had) == AudioServer.get_bus_effect(own, had + 1))
	backend.set_cues([])
	check("let go, the cue's bus and player go", AudioServer.get_bus_index(GodotBackend.cue_bus(2)) < 0
			and backend._players[2].all(func(p: Node) -> bool: return not p.has_meta(&"cue")))
	_offline()


## A plug on a channel strip's send, with headphones on: that one track in your ears, at the
## receiver's level, and where it cannot be heard, the tablet and a notice say why.
func _test_a_strip_send_puts_one_track_in_your_headphones() -> void:
	# The last engine leaves a frame late, and takes every built-in bus with it as it goes.
	await get_tree().process_frame
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	var saved_role := Session.role
	Session.role = Session.Role.SOLO
	AudioPorts.ensure_buses()
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var strip: ChannelStrip = studio.console.strips[1]
	var index := strip.track_index
	check("every strip has a send socket, for its track", studio.console.strips.all(
			func(c: ChannelStrip) -> bool: return c.send != null and c.send.source == PersonalMix.track_socket(c.track_index))
			and strip.send.title().contains(DAW.state.track(index).display_name().to_upper()))
	var bank := studio.console.find_child("SendSockets", true, false) as MeshBank
	check("drawn as one bank, not a mesh apiece", bank != null and bank.count() == studio.console.strips.size()
			and strip.send.find_children("*", "MeshInstance3D", true, false).is_empty())
	check("this machine plays the tracks, so a strip's is heard here", studio.personal.hears_tracks)
	var told: Array = []
	var listen := func(text: String): told.append(text)
	Session.notice.connect(listen)
	studio._on_patch_asked(0, strip.send.source)
	var me := Session.local_peer_id
	check("a plug in it is there for all to see", strip.send.plug_count() == 1
			and studio.patches.get(me) == [String(strip.send.source), "", "", ""])
	check("and you are told (%s)" % [told], told.size() == 1 and (told[0] as String).contains(
			"in SEND " + DAW.state.track(index).display_name().to_upper()))
	check("with headphones off, nothing is cued", backend.cues().is_empty())
	var hand := studio.get_node("MouseHand") as MouseInteractor
	var phones := studio.items.items[&"headphones"] as HeadphonesItem
	hand.pick_up(phones)
	hand.wear()
	var cue := GodotBackend.cue_bus(index)
	check("on, the track is cued, and in your ears alone (%s)" % [backend.cues()], backend.cues() == [index]
			and AudioServer.get_bus_index(cue) >= 0 and is_zero_approx(Ears.gain_db(cue))
			and Ears.gain_db(Ears.MIX) == Ears.OFF_DB and Ears.gain_db(Ears.KEYS) == Ears.OFF_DB)
	studio.personal.set_level(0, -12.0)
	check("at its receiver's level", is_equal_approx(Ears.gain_db(cue), -12.0))
	studio._on_patch_asked(1, &"mix")
	check("with the mix under it on another", is_zero_approx(Ears.gain_db(Ears.MIX))
			and is_equal_approx(Ears.gain_db(cue), -12.0))
	strip.send.grab_begin(hand, strip.send.global_position)
	strip.send.grab_end(hand)
	check("clicking the strip's socket brings your plug back, and the cue goes", backend.cues().is_empty()
			and studio.patches.get(me) == ["", "mix", "", ""] and strip.send.plug_count() == 0)
	hand.take_off()
	hand.lose_carrying()
	phones.snap_home()
	check("headphones off, every cue is silent", Ears.gain_db(cue) == Ears.OFF_DB or AudioServer.get_bus_index(cue) < 0)

	Session.role = Session.Role.GUEST
	studio._show_patches()
	told.clear()
	studio._on_patch_asked(2, strip.send.source)
	check("a guest hears the host's mix whole: the track's plug is in, and not heard (%s)" % [told],
			studio.personal.unheard(2) and not studio.personal.hears_tracks and told.size() == 1
			and (told[0] as String).contains("a guest hears the host's mix as one stream"))
	Session.role = Session.Role.SOLO
	Session.notice.disconnect(listen)
	studio.queue_free()
	await get_tree().process_frame
	check("leaving the studio lets every cue go", backend.cues().is_empty())
	Session.role = saved_role
	Session.layout = saved_layout
	_offline()


## Another player's keys: their ghost wears a pack with a SEND socket, a plug from your tablet
## in it plays their notes here, in your headphones, and nobody else's.
func _test_a_players_keys_pack_puts_their_playing_in_your_headphones() -> void:
	_offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	_as_session(Session.Role.HOST, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	for spec in [[1, "Ada", 0], [7, "Lin", 1]]:
		var p := Session.Participant.new()
		p.peer_id = spec[0]
		p.display_name = spec[1]
		p.colour_index = spec[2]
		Session.participants[spec[0]] = p
	Session.roster_changed.emit()
	await get_tree().process_frame
	var ghost := studio.presence.avatar_of(7)
	check("another player's ghost wears a keys pack with a SEND socket", ghost != null and ghost.send != null
			and ghost.send.source == &"keys_7" and ghost.send.title().contains("LIN'S KEYS"))
	check("at its real size, on a ghost scaled down (%.3f, the ghost %.3f)" % [
			ghost.send.global_basis.get_scale().x, ghost._ghost.global_basis.get_scale().x],
			is_equal_approx(ghost.send.global_basis.get_scale().x * Presence.Avatar.SIZE,
					ghost._ghost.global_basis.get_scale().x))
	var told: Array = []
	var listen := func(text: String): told.append(text)
	Session.notice.connect(listen)
	var hand := studio.get_node("MouseHand") as MouseInteractor
	var tablet := studio.items.items[&"tablet"] as TabletItem
	hand.pick_up(tablet)
	var sender: TabletFace.Sender = tablet.face._senders[0]
	sender.grab_begin(hand, sender.global_position)
	hand.hovered = ghost.send
	sender.grab_end(hand)
	hand.hovered = null
	check("plug A dropped on it is in it, for everyone to see (%s)" % [studio.patches],
			studio.patches.get(1) == ["keys_7", "", "", ""] and ghost.send.plug_count() == 1)
	check("and you are told whose keys (%s)" % [told], told.size() == 1
			and (told[0] as String).contains("Plug A in SEND LIN'S KEYS"))
	check("its row says so", (tablet.face._rows[0]["source"] as Label3D).text == "LIN'S KEYS")
	check("with headphones off, nothing of theirs is played", studio.their_keys.players().is_empty())
	hand.lose_carrying()
	tablet.snap_home()
	var phones := studio.items.items[&"headphones"] as HeadphonesItem
	hand.pick_up(phones)
	hand.wear()
	var bus := TheirKeys.bus_of(7)
	check("on, their keys are played here, on a bus of their own, in your ears alone",
			studio.their_keys.players() == [7] and AudioServer.get_bus_index(bus) >= 0
			and is_zero_approx(Ears.gain_db(bus)) and Ears.gain_db(Ears.MIX) == Ears.OFF_DB)
	var synth: MonitorSynth = studio.their_keys.synths[7]
	synth._events.clear()
	Session.note_played.emit(Session.Note.ON, 60, 100, 7, -1.0)
	Session.note_played.emit(Session.Note.ON, 64, 90, 9, -1.0)
	Session.note_played.emit(Session.Note.PEDAL_DOWN, 0, 0, 7, -1.0)
	Session.note_played.emit(Session.Note.OFF, 60, 0, 7, -1.0)
	check("their notes play, and nobody else's (%s)" % [synth._events],
			synth._events == [[MonitorSynth.ON, 60, 100], [MonitorSynth.SUSTAIN, 1, 0], [MonitorSynth.OFF, 60, 0]])
	studio.personal.set_level(0, -10.0)
	check("at the receiver's level", is_equal_approx(Ears.gain_db(bus), -10.0))

	Session.participants.erase(7)
	Session.roster_changed.emit()
	await get_tree().process_frame
	check("when they leave, the plug in their keys comes back to its tray, and they are not played",
			not studio.patches.has(1) and studio.their_keys.players().is_empty()
			and studio.presence.avatar_of(7) == null)
	Session.notice.disconnect(listen)
	hand.take_off()
	hand.lose_carrying()
	phones.snap_home()
	studio.queue_free()
	await get_tree().process_frame
	check("headphones gone with the studio, their bus is silent", Ears.gain_db(bus) == Ears.OFF_DB)
	_as_session(Session.Role.SOLO, 1)
	Session.layout = saved_layout


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

	# The walls hold too -- round where you can walk, which is more than where the furniture
	# goes: out of the control room's open back and into the live room, and no further.
	var b := studio.floor_plan.bounds
	var live := studio.venue.back_of_house()
	var walk_until_still := func(from: Vector3, toward: Vector3) -> Vector3:
		walker.global_position = from
		walker.velocity = Vector3.ZERO
		for i in 300:
			walker.step(1.0 / 60.0, toward * Walker.SPRINT_SPEED)
		return walker.global_position
	var at: Vector3 = walk_until_still.call(Vector3(0, 0, b.end.y - 0.6), Vector3(0, 0, 1))
	check("you walk out of the back of the control room (z %.2f, its edge %.2f)" % [at.z, b.end.y],
			at.z > b.end.y + 1.0)
	check("and the live room's back wall stops you (z %.2f, wall %.2f)" % [at.z, live.end.y],
			at.z < live.end.y and at.z > live.end.y - Walker.RADIUS - 0.1)
	# Just in front of the doorway, where nothing of the gear's stands between you and the wall.
	at = walk_until_still.call(Vector3(0, 0, b.end.y - 0.3), Vector3(-1, 0, 0))
	check("the control room's side wall still holds (x %.2f, wall %.2f)" % [at.x, b.position.x],
			at.x > b.position.x and at.x < b.position.x + Walker.RADIUS + 0.1)
	at = walk_until_still.call(Vector3(b.end.x + 1.0, 0, live.position.y + 1.0), Vector3(0, 0, -1))
	check("beside the doorway, the live room's front wall holds (z %.2f, wall %.2f)" % [
			at.z, live.position.y], at.z > live.position.y and at.z < live.position.y + Walker.RADIUS + 0.1)
	# Along the front of the live room, clear of the table and the keys.
	at = walk_until_still.call(Vector3(0, 0, live.position.y + 0.45), Vector3(1, 0, 0))
	check("and so does its side wall (x %.2f, wall %.2f)" % [at.x, live.end.x],
			at.x < live.end.x and at.x > live.end.x - Walker.RADIUS - 0.1)
	var zone_reached := true
	for box: AABB in studio.venue.zones().values():
		var room_floor := Rect2(live.position + Vector2(Walker.RADIUS, Walker.RADIUS),
				live.size - Vector2(Walker.RADIUS, Walker.RADIUS) * 2.0)
		if not room_floor.has_point(Vector2(box.get_center().x, box.get_center().z)):
			zone_reached = false
	check("every zone's centre is somewhere you can stand", zone_reached)

	# And what stands in the zones is solid where it should be.
	var zones := studio.venue.zones()
	var riser: AABB = zones[&"drums"]
	var riser_edge := riser.end.x - ZoneKit.RISER_INSET * 0.5
	# A few steps at a walk, then stand: far enough to be up on it, not across it and off.
	walker.global_position = Vector3(riser_edge + 0.5, 0, riser.get_center().z)
	walker.velocity = Vector3.ZERO
	for i in 75:
		walker.step(1.0 / 60.0, Vector3(-Walker.WALK_SPEED, 0, 0))
	for i in 60:
		walker.step(1.0 / 60.0, Vector3.ZERO)
	at = walker.global_position
	check("you walk up onto the drum riser (x %.2f, y %.2f)" % [at.x, at.y],
			at.x < riser_edge - 0.3 and absf(at.y - ZoneKit.RISER_HEIGHT) < 0.03)
	var desk_zone: AABB = zones[&"bricks"]
	var table_edge := desk_zone.get_center().x - ZoneKit.TABLE_TOP.x * 0.5
	at = walk_until_still.call(Vector3(table_edge - 1.0, 0, desk_zone.get_center().z), Vector3(1, 0, 0))
	check("the brick table stops you (x %.2f, its edge %.2f)" % [at.x, table_edge],
			at.x < table_edge and at.x > table_edge - Walker.RADIUS - 0.1)
	var booth: AABB = zones[&"vocals"]
	at = walk_until_still.call(Vector3(booth.get_center().x, 0, booth.position.z - 0.8), Vector3(0, 0, 1))
	check("the booth's glass stops you (z %.2f, glass %.2f)" % [at.z, booth.position.z],
			at.z < booth.position.z and at.z > booth.position.z - Walker.RADIUS - 0.1)
	var doorway := Vector3(booth.end.x + Walker.RADIUS + 0.03, 0, booth.end.z - ZoneKit.BOOTH_DOOR * 0.5)
	at = walk_until_still.call(doorway, Vector3(-1, 0, 0))
	check("and its door lets you in (x %.2f, booth %.2f..%.2f)" % [at.x, booth.position.x, booth.end.x],
			at.x < booth.end.x - 0.5 and at.x > booth.position.x)
	check("the lattice's zone is open floor", ZoneKit.solids(zones, true).all(func(f):
			return not Rect2(zones[&"matrix"].position.x, zones[&"matrix"].position.z,
					zones[&"matrix"].size.x, zones[&"matrix"].size.z).has_point(f["c"])))
	check("the grid's booth, only neon edges, has no walls you cannot see",
			GridVenue.new().zone_solids().size() == ZoneKit.solids(zones, true).size() - 4 + GridVenue.NEAR_PALMS.size())
	check("and the chalk zone's sketches are walked through", ChalkVenue.new().zone_solids().is_empty())

	# The studio arranged with its live room beside: through the window you only look; the door
	# lets you in, and every zone is somewhere you can stand.
	studio.set_venue(&"studio", false, StudioVenue.BESIDE)
	var wall_x := -studio.room_width * 0.5
	at = walk_until_still.call(Vector3(wall_x + 0.4, 0, -1.6), Vector3(-1, 0, 0))
	check("beside: the window stops you (x %.2f, glass %.2f)" % [at.x, wall_x],
			at.x > wall_x and at.x < wall_x + 0.06 + Walker.RADIUS + 0.1)
	at = walk_until_still.call(Vector3(wall_x + 0.4, 0, (StudioVenue.WINDOW_TO + StudioVenue.DOOR_TO) * 0.5),
			Vector3(-1, 0, 0))
	check("and the door lets you into the side room (x %.2f)" % at.x, at.x < wall_x - 2.0)
	var side_rooms := studio.venue.rooms()
	var all_standable := true
	for box: AABB in studio.venue.zones().values():
		var centre := Vector2(box.get_center().x, box.get_center().z)
		if not side_rooms.any(func(r: Rect2): return r.grow(-Walker.RADIUS).has_point(centre)):
			all_standable = false
	check("and every zone's centre is in a room you can walk", all_standable)

	# The loft is one room: the floor beside the desk is walkable to the brick, and its iron
	# columns and the gallery's ladder stand in your way.
	studio.set_venue(&"loft", false)
	var loft := studio.venue as LoftVenue
	var brick := -loft.live_room_half()
	at = walk_until_still.call(Vector3(wall_x + 0.4, 0, -1.6), Vector3(-1, 0, 0))
	check("loft: you walk out past the footprint to the brick (x %.2f, wall %.2f)" % [at.x, brick],
			at.x < wall_x - 2.0 and at.x > brick and at.x < brick + Walker.RADIUS + 0.1)
	var column: Vector2 = loft._column_spots()[0]
	at = walk_until_still.call(Vector3(column.x, 0, column.y + 1.5), Vector3(0, 0, -1))
	check("an iron column stops you (z %.2f, column %.2f)" % [at.z, column.y],
			at.z > column.y + LoftVenue.COLUMN_RADIUS
			and at.z < column.y + LoftVenue.COLUMN_RADIUS + Walker.RADIUS + 0.1)
	# Up the stair at a walk, along the gallery, and to its rail over the lattice.
	var steps := loft.stair_steps()
	var stair_z: float = steps[0]["c"].y
	var walk_on := func(toward: Vector3, ticks: int) -> Vector3:
		for i in ticks:
			walker.step(1.0 / 60.0, toward * Walker.WALK_SPEED)
		for i in 30:
			walker.step(1.0 / 60.0, Vector3.ZERO)
		return walker.global_position
	walker.global_position = Vector3(steps[0]["c"].x - 0.8, 0, stair_z)
	walker.velocity = Vector3.ZERO
	at = walk_on.call(Vector3(1, 0, 0), 300)
	check("loft: you walk up the stair (y %.2f, top %.2f)" % [at.y, LoftVenue.DECK_TOP],
			absf(at.y - LoftVenue.DECK_TOP) < 0.05)
	at = walk_on.call(Vector3(0, 0, 1), 60)
	at = walk_on.call(Vector3(-1, 0, 0), 240)
	check("and along the gallery (x %.2f, y %.2f)" % [at.x, at.y],
			at.x < 0.0 and absf(at.y - LoftVenue.DECK_TOP) < 0.05)
	var edge := Venue.LIVE_ROOM_BACK - LoftVenue.GALLERY_DEPTH
	at = walk_on.call(Vector3(0, 0, -1), 120)
	check("and its rail keeps you up there (z %.2f, edge %.2f, y %.2f)" % [at.z, edge, at.y],
			at.z > edge and absf(at.y - LoftVenue.DECK_TOP) < 0.05)
	var lattice: AABB = loft.zones()[&"matrix"]
	check("looking down on the lattice from above it (eye %.2f, lattice top %.2f)" % [
			walker.eye().y, lattice.end.y], walker.eye().y > lattice.end.y + 1.0)
	var loft_rooms := loft.rooms()
	var loft_standable := true
	for box: AABB in loft.zones().values():
		var centre := Vector2(box.get_center().x, box.get_center().z)
		if not loft_rooms.any(func(r: Rect2): return r.grow(-Walker.RADIUS).has_point(centre)):
			loft_standable = false
	check("and every zone's centre is somewhere you can stand", loft_standable)

	# The cabin: the stove in the corner is hot iron you walk round, the floor beside the desk
	# reaches the log wall, and the snow falls outside it, never in.
	studio.set_venue(&"cabin", false)
	var cabin := studio.venue as CabinVenue
	var stove := cabin.stove_spot()
	at = walk_until_still.call(Vector3(stove.x + 1.6, 0, stove.y), Vector3(-1, 0, 0))
	check("cabin: the stove stops you (x %.2f, stove %.2f)" % [at.x, stove.x],
			at.x > stove.x + CabinVenue.STOVE_SIZE.x * 0.5
			and at.x < stove.x + CabinVenue.STOVE_SIZE.x * 0.5 + 0.15 + Walker.RADIUS + 0.1)
	at = walk_until_still.call(Vector3(wall_x + 0.4, 0, 1.5), Vector3(-1, 0, 0))
	check("and you walk past the footprint to the logs (x %.2f, wall %.2f)" % [at.x, -cabin.live_room_half()],
			at.x < -cabin.live_room_half() + Walker.RADIUS + 0.1)
	var indoors := AABB(Vector3(-cabin.live_room_half(), 0, CabinVenue.FRONT),
			Vector3(cabin.live_room_half() * 2.0, CabinVenue.RIDGE, Venue.LIVE_ROOM_BACK - CabinVenue.FRONT))
	var dry := true
	for fall: GPUParticles3D in cabin.find_children("Snow*", "GPUParticles3D", false, false):
		var box := (fall.process_material as ParticleProcessMaterial).emission_box_extents
		var falls := AABB(fall.position - box, box * 2.0).grow(0.5)
		if falls.intersects(indoors):
			dry = false
	check("and no snow falls within half a metre of the room", dry
			and not cabin.find_children("Snow*", "GPUParticles3D", false, false).is_empty())
	var lows := INF
	var highs := 0.0
	for i in 120:
		cabin._process(1.0 / 30.0)
		var e := (cabin.find_child("Firelight", false, false) as SpotLight3D).light_energy
		lows = minf(lows, e)
		highs = maxf(highs, e)
	check("the fire flickers and never goes out (%.2f..%.2f)" % [lows, highs],
			highs - lows > 0.2 and lows > 1.0)
	# The back wall has a shelf of jars, some with candles burning, all of them on the plank.
	var plank := cabin.find_child("Shelf", false, false) as MeshInstance3D
	var candles := cabin.find_child("CandleJars", false, false) as MultiMeshInstance3D
	var on_shelf := plank != null and candles != null and candles.multimesh.instance_count >= 2 \
			and cabin.shelf_jars.size() >= 12
	if on_shelf:
		var top := plank.position.y + (plank.mesh as BoxMesh).size.y * 0.5
		var half := (plank.mesh as BoxMesh).size.x * 0.5
		for jar: Transform3D in cabin.shelf_jars:
			on_shelf = on_shelf and absf(jar.origin.y - top) < 0.01 and absf(jar.origin.z - plank.position.z) < 0.05 \
					and absf(jar.origin.x - plank.position.x) < half - 0.05
	var glass := candles.multimesh.mesh.surface_get_material(0) as StandardMaterial3D if candles else null
	var flames := cabin.find_child("CandleFlames", false, false) as MultiMeshInstance3D
	check("a shelf of jars on the back wall, candles burning in some through tinted glass", on_shelf
			and glass.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and glass.emission_enabled
			and candles.multimesh.mesh.get_surface_count() == 1 and flames != null
			and flames.multimesh.instance_count == candles.multimesh.instance_count)
	var beats: Array[float] = []
	for light: SpotLight3D in cabin.candle_lights:
		var low := INF
		var high := 0.0
		for i in 60:
			cabin._process(1.0 / 30.0)
			low = minf(low, light.light_energy)
			high = maxf(high, light.light_energy)
		beats.append(high - low)
	check("and the candles' light gutters", beats.size() == 2 and beats.all(func(b: float) -> bool: return b > 0.1))
	var chair := cabin.find_child("RockingChair", false, false) as Node3D
	var rug := cabin.find_child("Rug0", false, false) as MeshInstance3D
	check("and the rocking chair stands on a rug", chair != null and rug != null
			and Vector2(chair.position.x - rug.position.x, chair.position.z - rug.position.z).length() < 0.4)

	# The rooftop: a festoon pole stops you, the strings hang over every zone's head room and
	# inside the parapet, and what stands on the rest of the roof is past the parapet.
	studio.set_venue(&"rooftop", false)
	var roof := studio.venue as RooftopVenue
	var pole: Vector2 = roof.pole_spots()[0]
	at = walk_until_still.call(Vector3(pole.x + 1.2, 0, pole.y), Vector3(-1, 0, 0))
	check("rooftop: a festoon pole stops you (x %.2f, pole %.2f)" % [at.x, pole.x],
			at.x > pole.x + 0.06 and at.x < pole.x + 0.06 + Walker.RADIUS + 0.1)
	var lowest := INF
	var inside := true
	for bulb in roof.bulbs():
		lowest = minf(lowest, bulb.y)
		inside = inside and absf(bulb.x) < roof.live_room_half() and bulb.z > RooftopVenue.FRONT \
				and bulb.z < Venue.LIVE_ROOM_BACK
	var head_room := 0.0
	for box: AABB in roof.zones().values():
		head_room = maxf(head_room, box.end.y)
	check("the strings hang over every zone's head room (lowest bulb %.2f, room %.2f) and inside the parapet"
			% [lowest, head_room], lowest > head_room + 0.05 and inside and roof.bulbs().size() > 60)
	var past := true
	var terrace := Rect2(-roof.live_room_half() - RooftopVenue.WALL, RooftopVenue.FRONT,
			(roof.live_room_half() + RooftopVenue.WALL) * 2.0, Venue.LIVE_ROOM_BACK + RooftopVenue.WALL - RooftopVenue.FRONT)
	for spot in roof.tank_spots():
		# A tank is 3.4 m across its ladder.
		past = past and not terrace.grow(1.8).has_point(spot)
	past = past and not terrace.grow(1.6).has_point(roof.stair_house_spot())
	past = past and not terrace.grow(1.2).has_point(roof.skylight_spot())
	for vent in roof.vent_spots():
		past = past and not terrace.grow(0.3).has_point(vent)
		for spot in roof.tank_spots():
			past = past and vent.distance_to(spot) > 2.0
	check("the tanks, the stair house, the skylight and the vents stand on the roof past the parapet", past
			and roof.find_children("WaterTank*", "", false, false).size() == 2)
	var seen_on := false
	var seen_off := false
	for i in 60:
		roof._process(1.0 / 20.0)
		seen_on = seen_on or roof.beacons.all(func(b: MeshInstance3D) -> bool: return b.visible)
		seen_off = seen_off or roof.beacons.all(func(b: MeshInstance3D) -> bool: return not b.visible)
	check("the tanks' red lights blink", roof.beacons.size() == 2 and seen_on and seen_off)
	var by_night := Venue.make(&"rooftop", RooftopVenue.NIGHT)
	add_child(by_night)
	var string_energy := func(v: Venue) -> float:
		return (v.find_child("StringLight*", false, false) as SpotLight3D).light_energy
	check("and at night the strings are turned up", string_energy.call(by_night) > string_energy.call(roof) * 1.2)
	by_night.free()
	# Its three evenings: one per title, the sun brightest at golden hour and the sky darkest at
	# night, the sun's disc only while it is up.
	var keys: Array[float] = []
	var skies: Array[float] = []
	var discs: Array[float] = []
	for n in Venue.variant_titles(&"rooftop").size():
		var evening := Venue.make(&"rooftop", n)
		var env := Environment.new()
		var sun := DirectionalLight3D.new()
		evening.dress(env, sun)
		keys.append(sun.light_energy)
		var mat := env.sky.sky_material as ShaderMaterial
		skies.append((mat.get_shader_parameter("upper") as Color).get_luminance())
		discs.append(mat.get_shader_parameter("sun_radius"))
		sun.free()
		evening.free()
	check("rooftop: dusk, golden hour and night (keys %s, skies %s)" % [keys, skies],
			keys.size() == RooftopVenue.EVENINGS.size() and keys.size() == 3
			and keys[RooftopVenue.GOLDEN] > keys[RooftopVenue.DUSK] and keys[RooftopVenue.DUSK] > keys[RooftopVenue.NIGHT]
			and skies[RooftopVenue.NIGHT] < skies[RooftopVenue.DUSK] and skies[RooftopVenue.DUSK] < skies[RooftopVenue.GOLDEN]
			and discs[RooftopVenue.GOLDEN] > 0.0 and discs[RooftopVenue.DUSK] == 0.0 and discs[RooftopVenue.NIGHT] == 0.0)

	# The station: glass in the deck under the lattice and no deck plate over it, a hatch of glass
	# each side, the corridor beyond rising round the ring, and the dust hanging in the lattice.
	studio.set_venue(&"station", false)
	var station := studio.venue as StationVenue
	var lattice_box: AABB = station.zones()[&"matrix"]
	var spin_set: Variant = station._sky_mat.get_shader_parameter("spin")
	var spin_before := 0.0 if spin_set == null else float(spin_set)
	station._process(StationVenue.ORBIT_STEP * 2.0)
	var spin_after := float(station._sky_mat.get_shader_parameter("spin"))
	station._process(StationVenue.ORBIT_STEP * 0.1)
	check("station: the ground and the stars turn slowly past as it orbits (%.4f -> %.4f)" % [spin_before, spin_after],
			spin_after > spin_before and spin_after - spin_before < 0.01)
	check("and the sky is not redrawn every frame for it",
			float(station._sky_mat.get_shader_parameter("spin")) == spin_after)
	var deck_glass := station.glass_floor()
	var deck_pane := station.find_child("FloorGlass", false, false) as MeshInstance3D
	var deck_plated := false
	for piece: Node in station.find_children("Floor*", "MeshInstance3D", false, false):
		var plate := piece as MeshInstance3D
		if plate == deck_pane:
			continue
		var size := (plate.mesh as PlaneMesh).size
		var r := Rect2(plate.position.x - size.x * 0.5, plate.position.z - size.y * 0.5, size.x, size.y)
		deck_plated = deck_plated or r.grow(-0.01).intersects(deck_glass.grow(-0.01))
	check("station: glass under the lattice (%s) and no plate over it" % deck_glass, deck_pane != null and not deck_plated
			and Rect2(lattice_box.position.x, lattice_box.position.z, lattice_box.size.x, lattice_box.size.z).encloses(deck_glass)
			and deck_glass.has_point(Vector2(deck_pane.position.x, deck_pane.position.z)))
	check("a hatch of glass in each side wall", station.find_children("Hatch*", "", false, false).size() >= 4
			and station.find_children("HatchGlass*", "", false, false).size() == 2)
	var hatch_foot := station.ring_point(1.0, 0.0)
	var round_ring := station.ring_point(1.0, 40.0)
	check("the corridor leaves level from the hatch and rises round the ring (%.2f, %.2f)" % [hatch_foot.y, round_ring.y],
			absf(hatch_foot.y) < 0.01 and hatch_foot.x > station.live_room_half() and round_ring.y > 5.0
			and station.ring_point(-1.0, 40.0).x < -round_ring.x + 0.01)
	var station_dust := station.find_child("Dust", true, false) as GPUParticles3D
	check("the dust hangs in the lattice", station_dust != null and lattice_box.has_point(station_dust.global_position))

	# The underwater dome: the vault's glass clears every zone, the deck's edge is railed, the
	# kelp stands outside the glass and clear of the sub, the sub is outside with the collar run
	# from the booth's back to it, and the floors carry caustics.
	studio.set_venue(&"dome", false)
	var dome := studio.venue as DomeVenue
	var r := dome.radius()
	var clear := true
	for box: AABB in dome.zones().values():
		for x in [box.position.x, box.end.x]:
			clear = clear and sqrt(r * r - x * x) > box.end.y + 0.3
	check("dome: the vault clears every zone's head room (radius %.2f)" % r, clear)
	var railed := dome.find_children("RailGlass*", "", false, false).size()
	# Front, right, and left up to the booth; the booth's own back is the edge past it.
	check("the deck's edge is railed, front and sides (%d panes)" % railed, railed >= 3)
	var kelp_out := true
	var sub_at := dome.sub_spot()
	for spot in dome.kelp_spots:
		var p := spot.origin
		var out := absf(p.x) - r if p.z > DomeVenue.NOSE else Vector2(p.x, p.z - DomeVenue.NOSE).length() - r
		kelp_out = kelp_out and out > 1.0 and Vector2(p.x - sub_at.x, p.z - sub_at.z).length() > 3.0
	check("the kelp stands outside the glass and clear of the sub (%d stalks)" % dome.kelp_spots.size(),
			kelp_out and dome.kelp_spots.size() > 100)
	var collar := dome.find_child("Collar", false, false) as MeshInstance3D
	var booth_box: AABB = dome.zones()[&"vocals"]
	var reach := (collar.mesh as CylinderMesh).height
	check("the sub is docked outside the glass, its collar run from the booth's back to it",
			dome.find_child("Sub", false, false) != null and absf(sub_at.x) - 0.85 > r
			and absf(collar.position.x + reach * 0.5 - booth_box.position.x) < 0.1
			and absf(collar.position.x - reach * 0.5 - (sub_at.x + DomeVenue.SUB_FLANGE)) < 0.01)
	var deck := dome.find_child("Floor", false, false) as MeshInstance3D
	var sand := dome.find_child("Sand", false, false) as MeshInstance3D
	var caustic := func(m: MeshInstance3D) -> bool:
		var mat := m.material_override as ShaderMaterial
		return mat != null and mat.shader.resource_path.ends_with("caustic_ground.gdshader") \
				and float(mat.get_shader_parameter("strength")) > 0.0
	check("caustics play on the deck and the sand", caustic.call(deck) and caustic.call(sand)
			and sand.position.y < -0.3)
	var leaning := dome.shafts.size() >= 12
	for shaft in dome.shafts:
		leaning = leaning and shaft.basis.y.normalized().dot(DomeVenue.SUN_DIR.normalized()) > 0.999
	check("the shafts of light lean the way the sun comes down", leaning)
	var on_sand := dome.reef.size() > 40
	var in_front := 0
	for piece: Array in dome.reef:
		var reef_at: Vector3 = (piece[1] as Transform3D).origin
		var off_deck := reef_at.z < DomeVenue.NOSE or absf(reef_at.x) > dome.live_room_half()
		on_sand = on_sand and off_deck and absf(reef_at.y + DomeVenue.TRENCH) < 0.001
		if reef_at.z < DomeVenue.NOSE and Vector2(reef_at.x, reef_at.z - DomeVenue.NOSE).length() < r:
			in_front += 1
	check("dome: rocks and coral sit in the sand, none on the deck, most of them in front (%d of %d)"
			% [in_front, dome.reef.size()], on_sand and in_front >= 25)
	var clear_of_glass := dome.fish_paths.size() > 40
	for f in dome.fish_paths:
		for k in 85:
			var swim_a := -PI * 0.5 + DomeVenue.SCHOOL_SWEEP * (k / 42.0 - 1.0)
			var swim_p := DomeVenue.school_point(swim_a, f.y, f.z)
			var swim_out := absf(swim_p.x) - r if swim_p.z > DomeVenue.NOSE \
					else (swim_p - Vector3(0, 0, DomeVenue.NOSE)).length() - r
			clear_of_glass = clear_of_glass and swim_out > 0.5 and swim_p.y > 0.5 \
					and swim_p.z < DomeVenue.BACK - 0.3
	check("the schools sweep round outside the glass and turn before the bulkhead (%d fish)" % dome.fish_paths.size(),
			clear_of_glass)
	var fish_node := dome.find_child("Fish", false, false) as MultiMeshInstance3D
	check("and swim in their shader, each with its own path",
			fish_node.multimesh.use_custom_data and fish_node.multimesh.instance_count == dome.fish_paths.size()
			and (fish_node.multimesh.mesh.surface_get_material(0) as ShaderMaterial).shader.resource_path.ends_with("fish.gdshader"))

	# The jazz club: one spot on the stage, the furniture along the side walls, the bottles on
	# their shelves, the stools turned up on the bar, the curtain behind the stage.
	studio.set_venue(&"club", false)
	var club := studio.venue as ClubVenue
	var stage_box: AABB = club.zones()[&"drums"]
	var beam_dir := -club.spot.global_transform.basis.z.normalized()
	var drop := club.spot.global_position.y - ZoneKit.RISER_HEIGHT
	var lands := club.spot.global_position + beam_dir * (drop / -beam_dir.y)
	check("club: the one spot lands on the stage (%.2f, %.2f), and casts shadows" % [lands.x, lands.z],
			stage_box.grow(-0.3).has_point(Vector3(lands.x, 1.0, lands.z)) and club.spot.shadow_enabled
			and club.find_children("*", "SpotLight3D", true, false).filter(
				func(l): return l.light_energy > 5.0).size() == 1)
	var club_house := club.back_of_house()
	var club_strips := club.rooms().slice(1)
	var furniture_ok := true
	for solid: Dictionary in club.zone_solids().slice(ZoneKit.solids(club.zones(), true).size()):
		var c: Vector2 = solid["c"]
		furniture_ok = furniture_ok and not club_house.has_point(c) and club_strips.any(
				func(s: Rect2): return s.has_point(c))
	check("the bar, booths and stools are solid, along the sides, not in the back of house",
			furniture_ok and club.zone_solids().size() > ZoneKit.solids(club.zones(), true).size() + 6)
	var shelved := club.bottle_spots.size() > 40
	for spot in club.bottle_spots:
		shelved = shelved and club.bottle_levels.any(func(y): return absf(spot.origin.y - y) < 0.001) \
				and spot.origin.x > club.bar_front() + ClubVenue.COUNTER_DEPTH
	check("every bottle stands on a shelf behind the counter (%d)" % club.bottle_spots.size(), shelved)
	var upturned := 0
	for stool in club.find_children("Stool*", "", false, false):
		if (stool as Node3D).basis.y.y < -0.99 and (stool as Node3D).position.y > ClubVenue.BAR_TOP:
			upturned += 1
	check("after hours: the stools are up on the bar, all but two (%d)" % upturned,
			upturned == club.stool_spots().size() - 2 and upturned > 0)
	var curtain := club.find_child("Curtain", false, false) as MeshInstance3D
	check("the curtain hangs behind the stage, facing the room",
			curtain.position.z > stage_box.end.z and curtain.global_transform.basis.z.z < -0.99)
	check("and runs the back wall's whole width, so no bare brick shows behind the zones",
			(curtain.mesh as PlaneMesh).size.x > club.live_room_half() * 2.0 - 0.2)
	var flame_before := club.candles[0].light_energy
	club._process(0.13)
	check("the candles flicker", club.candles.size() == 3 and club.candles[0].light_energy != flame_before)
	# What the band left: the piano against the wall facing the room, the bass lying on the floor,
	# a coat over a booth's bench, glasses on the tables and the bar, and dust in the beam.
	var piano_box := (club.find_child("Piano", false, false) as MeshInstance3D).get_aabb()
	piano_box = club.find_child("Piano", false, false).transform * piano_box
	var booth_ends := -club.live_room_half() + ClubVenue.BENCH
	check("the piano stands against the booths' bench ends, between their openings, keys to the room",
			piano_box.position.x > booth_ends and piano_box.position.x < booth_ends + 0.1
			and piano_box.position.z > ClubVenue.BOOTHS[0] + 0.3 and piano_box.end.z < ClubVenue.BOOTHS[1] - 0.3
			and piano_box.end.x > club.piano_x() + 0.5 and absf(piano_box.position.y) < 0.01
			and absf(piano_box.end.y - 1.25) < 0.02)
	var bass_node := club.find_child("Bass", false, false) as MeshInstance3D
	var bass_box := bass_node.transform * bass_node.get_aabb()
	check("the bass lies on its side on the floor (%.2f high, %.2f long)" % [bass_box.size.y, maxf(bass_box.size.x, bass_box.size.z)],
			absf(bass_box.position.y) < 0.01 and bass_box.size.y < 0.75 and maxf(bass_box.size.x, bass_box.size.z) > 1.7
			and not bass_box.intersects(piano_box) and not club.zones().values().any(
				func(z: AABB): return z.intersects(bass_box)))
	var coat_node := club.find_child("Coat", false, false) as MeshInstance3D
	var coat_box := coat_node.transform * coat_node.get_aabb()
	var coat_bench := club.find_child("Bench1a", false, false) as MeshInstance3D
	var coat_bench_box := coat_bench.transform * coat_bench.get_aabb()
	check("the coat hangs over a booth's bench, off the floor",
			coat_box.intersects(coat_bench_box) and coat_box.position.y > 0.3 and coat_box.end.y < 1.3)
	var glasses_ok := club.glass_spots.size() >= 6
	var table_x := -club.live_room_half() + ClubVenue.BENCH * 0.5
	for g in club.glass_spots:
		var on_table := absf(g.y - 0.74) < 0.001 and ClubVenue.BOOTHS.any(
				func(bz: float): return Vector2(g.x - table_x, g.z - bz).length() < 0.28)
		var on_bar := absf(g.y - ClubVenue.BAR_TOP) < 0.001 and g.x > club.bar_front() \
				and g.x < club.bar_front() + ClubVenue.COUNTER_DEPTH and g.z > ClubVenue.BAR_FROM and g.z < ClubVenue.BAR_TO
		glasses_ok = glasses_ok and (on_table or on_bar)
	check("every glass left stands on a booth table or the bar (%d)" % club.glass_spots.size(), glasses_ok)
	var dust := club.find_child("Dust", false, false) as MultiMeshInstance3D
	var dust_aim := (club.stage_centre() - ClubVenue.SPOT_AT).normalized()
	var dust_spread: float = (dust.material_override as ShaderMaterial).get_shader_parameter("spread")
	var in_beam := club.motes.size() == ClubVenue.MOTES and dust.multimesh.use_custom_data
	for m in club.motes:
		var mote_along := (m - ClubVenue.SPOT_AT).dot(dust_aim)
		var mote_off := ((m - ClubVenue.SPOT_AT) - dust_aim * mote_along).length()
		in_beam = in_beam and mote_along > 0.4 and mote_off < 0.1 + mote_along * dust_spread
	check("dust turns in the spot's beam, every mote put inside its cone", in_beam
			and (dust.material_override as ShaderMaterial).shader.resource_path.ends_with("dust.gdshader")
			and (dust.material_override as ShaderMaterial).get_shader_parameter("lamp") == ClubVenue.SPOT_AT)

	# The chalk zone's sketched room: the board stands behind every zone and over all of them,
	# the room is drawn round the floor, and the doodles are gathered in, none left in the sky.
	studio.set_venue(&"chalk", false, ChalkVenue.SKETCHED_ROOM)
	var sketched := studio.venue as ChalkVenue
	var board := sketched.find_child("BoardWall", false, false) as MeshInstance3D
	var board_box := board.global_transform * board.get_aabb()
	var behind_all := true
	for zone_box: AABB in sketched.zones().values():
		behind_all = behind_all and board_box.position.z >= zone_box.end.z and board_box.end.y > zone_box.end.y + 1.0 \
				and board_box.position.x <= zone_box.position.x and board_box.end.x >= zone_box.end.x
	check("chalk, sketched: the board stands behind every zone, taller than all of them", behind_all)
	var room_lines := sketched.find_child("RoomSketch", false, false) as MeshInstance3D
	var room_box := room_lines.get_aabb()
	check("the room is drawn round the floor (%s)" % room_box,
			absf(room_box.size.x - sketched.live_room_half() * 2.0) < 0.2
			and absf(room_box.end.z - Venue.LIVE_ROOM_BACK) < 0.2 and absf(room_box.end.y - ChalkVenue.ROOM_HEIGHT) < 0.2)
	var words := sketched.find_children("BoardWords*", "Label3D", true, false)
	var written := words.size() >= 3
	for w: Label3D in words:
		written = written and w.global_transform.basis.z.z < -0.99 and w.global_position.z < board_box.position.z
	check("the session is written on the board, facing the room (%d)" % words.size(), written)
	var board_lit := true
	for i in 4:
		var lamp := sketched.find_child("BoardLight%d" % i, false, false) as SpotLight3D
		board_lit = board_lit and lamp != null and lamp.position.y > ChalkVenue.BOARD_HEIGHT \
				and (-lamp.basis.z).y < -0.9 and (-lamp.basis.z).z > 0.0
	check("picture lights along its top wash the slate down its height", board_lit)
	check("and no doodles are left in the sky", sketched._doodles.is_empty()
			and sketched.find_child("Rainbow", false, false) == null)
	# The board says what the session says: its sections from the markers in order, the tempo,
	# how many tracks, the take on the armed track; and is rubbed out and rewritten when that changes.
	check("the board is written from the mix in front of it", sketched.board == ChalkVenue.board_from(DAW.state)
			and sketched.find_child("BoardSession", false, false) != null)
	var mix := MixState.new()
	mix.markers = {30.0: "Chorus", 0.0: " intro", 45.0: "", 60.0: "bridge"}
	mix.tempo = 92.0
	var armed := mix.track(1)
	armed.rec_arm = true
	for k in 3:
		armed.items.append(MixState.ItemState.new())
	mix.track(2)
	var said := ChalkVenue.board_from(mix)
	check("sections come from the markers in time order, unnamed ones skipped (%s)" % said,
			said["sections"] == PackedStringArray(["INTRO", "CHORUS", "BRIDGE"]) and said["tempo"] == "92 bpm"
			and said["tracks"] == "2 tracks" and said["take"] == "take 4")
	mix.recording = true
	mix.tempo = 87.5
	var while_rolling := ChalkVenue.board_from(mix)
	armed.rec_arm = false
	check("the take is the one being recorded while it rolls, and there is none with nothing armed",
			while_rolling["take"] == "take 3" and while_rolling["tempo"] == "87.5 bpm"
			and ChalkVenue.board_from(mix)["take"] == "")
	var rewrites_before := sketched._rewrites
	sketched._session_news()
	sketched._reread_the_session()
	check("news that changes nothing on the board leaves the writing alone", sketched._rewrites == rewrites_before)
	var before_rewrite := sketched.find_child("BoardSession", false, false)
	sketched.rewrite_board(said)
	var fresh := sketched.find_child("BoardSession", false, false)
	var fresh_words := fresh.find_children("BoardWords*", "Label3D", false, false).map(func(l: Label3D): return l.text)
	check("a change rubs the old writing out and writes the new in its place (%s)" % [fresh_words],
			fresh != before_rewrite and before_rewrite.name.begins_with("BoardRubbedOut")
			and fresh_words.has("CHORUS") and fresh_words.has("take 4") and fresh_words.has("92 bpm"))
	for k in 4:
		sketched._process(0.5)
	check("the old writing is gone once rubbed out, the new is all there",
			before_rewrite.is_queued_for_deletion() and fresh.find_children("*", "Label3D", false, false).all(
				func(l: Label3D): return l.modulate.a > 0.5))
	studio.set_venue(&"studio", false)

	# Open ground round the room: in the grid and the chalk's open sky the floor runs past the
	# zones and in front of the desk, and a palm's trunk is something you walk round.
	var plan := walker._plan_frame()
	var plan_spot := func() -> Vector2:
		var p := plan.affine_inverse() * walker.global_position
		return Vector2(p.x, p.z)
	var stand_at := func(p: Vector2) -> void:
		walker.global_position = plan * Vector3(p.x, 0, p.y)
		walker.velocity = Vector3.ZERO
	for open: Array in [[&"grid", 0, GridVenue.OPEN_FLOOR], [&"chalk", ChalkVenue.OPEN_SKY, ChalkVenue.OPEN_FLOOR]]:
		studio.set_venue(open[0], false, open[1])
		var half: float = studio.venue.live_room_half()
		var front := Studio.ROOM_FRONT + 0.05
		var round_the_room := [Vector2(-half - open[2] + 0.5, 3.0), Vector2(half + open[2] - 0.5, 3.0),
				Vector2(-half, Venue.LIVE_ROOM_BACK + open[2] - 0.5), Vector2(0, front - open[2] + 0.5),
				Vector2(-studio.room_width * 0.5 - 1.0, 0.0)]
		var shut := round_the_room.filter(func(p: Vector2) -> bool: return not walker.fits(p))
		check("%s: you can stand past the zones, beside the desk and in front of it (shut: %s)" % [open[0], shut],
				shut.is_empty())
	studio.set_venue(&"grid", false)
	var palm := Vector2(GridVenue.NEAR_PALMS[0].x, GridVenue.NEAR_PALMS[0].z)
	check("grid: a palm's trunk is solid", not walker.fits(palm)
			and not walker.fits(palm + Vector2(GridVenue.TRUNK, 0)))
	stand_at.call(palm)
	check("and standing in one, you are put beside it", walker.unstick() and walker.fits(plan_spot.call())
			and plan_spot.call().distance_to(palm) < GridVenue.TRUNK + Walker.RADIUS + 0.2)

	# A venue changed under your feet never leaves you where you cannot be: out on open ground the
	# next room has walled off, or inside something it has put there.
	var out_there := Vector2(-studio.venue.live_room_half() - GridVenue.OPEN_FLOOR + 0.5, 3.0)
	for next: StringName in Venue.IDS:
		studio.set_venue(&"grid", false)
		stand_at.call(out_there)
		studio.set_venue(next, false)
		var now: Vector2 = plan_spot.call()
		check("grid's open ground to %s: you are put where you fit (%.2f, %.2f)" % [next, now.x, now.y],
				walker.fits(now) and walker.walkable.any(func(r: Rect2) -> bool: return r.has_point(now)))
	studio.set_venue(&"studio", false)
	var inside_something := false
	for f in walker.fixed:
		if f.get("top", Walker.SOLID_HEIGHT) > Walker.STEP_HEIGHT:
			stand_at.call(f["c"])
			inside_something = true
			break
	check("standing inside something solid, you are moved clear of it",
			inside_something and walker.unstick() and walker.fits(plan_spot.call()))
	# And at the desk, in every venue, you are left where you are.
	for id: StringName in Venue.IDS:
		stand_at.call(Vector2(0, Studio.MIX_POSITION_Z))
		studio.set_venue(id, false)
		check("%s: at the desk a change of venue leaves you be" % id,
				plan_spot.call().is_equal_approx(Vector2(0, Studio.MIX_POSITION_Z)) and not walker.unstick())
	studio.set_venue(&"studio", false)

	# The outline the walls stand on: two rooms meeting leave a doorway where they meet.
	var edges := Walker.outline([Rect2(-1, 0, 2, 2), Rect2(-3, 2, 6, 2)])
	var on_the_seam := func(e: Array) -> bool:
		return absf((e[0] as Vector2).y - 2.0) < 0.001 and absf((e[1] as Vector2).y - 2.0) < 0.001
	var across := edges.filter(on_the_seam)
	var lengths := across.map(func(e): return (e[0] as Vector2).distance_to(e[1]))
	check("the outline leaves a doorway where two rooms meet (%s)" % [lengths],
			across.size() == 2 and lengths.all(func(l): return is_equal_approx(l, 2.0)))
	check("and walls everything else (%d edges)" % edges.size(), edges.size() == 8)

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

	# Trim: an edge, dragged, moves only that edge, snapped to the beat.
	check("an item's middle is not an edge", timeline.item_edge_at_point(at.call(2, 13.0)) == 0)
	check("its ends are", timeline.item_edge_at_point(at.call(2, 9.02)) == -1
			and timeline.item_edge_at_point(at.call(2, 24.98)) == 1)
	lanes.grab_begin(hand, at.call(2, 9.02))
	lanes.grab_move(hand, at.call(2, 11.1))
	check("dragging the left edge reads as a trim (%s)" % lanes.readout(), lanes.readout() == "trim start to 11.1.00")
	close_to("and is drawn trimmed while the project waits", timeline._preview[3], s.bar_to_seconds(25.0) - s.bar_to_seconds(11.0), 0.001)
	lanes.grab_end(hand)
	close_to("let go, the item starts on the beat it was dragged to", s.item(2, 0).start, s.bar_to_seconds(11.0), 0.001)
	close_to("and still ends where it did", s.item(2, 0).end(), s.bar_to_seconds(25.0), 0.001)
	lanes.grab_begin(hand, at.call(2, 24.98))
	lanes.grab_move(hand, at.call(2, 23.0))
	lanes.grab_end(hand)
	close_to("the right edge, dragged in, ends it there", s.item(2, 0).end(), s.bar_to_seconds(23.0), 0.001)
	close_to("leaving its start", s.item(2, 0).start, s.bar_to_seconds(11.0), 0.001)
	DAW.undo()
	DAW.undo()
	close_to("two undos put both edges back", s.item(2, 0).start, s.bar_to_seconds(9.0), 0.001)

	# Fades: a block's top corners. Item (2, 0) runs bar 9 to 25.
	var top := func(bar: float) -> Vector3:
		return at.call(2, bar) + timeline.global_basis.y * ((TimelineSurface.LANE_HEIGHT - 0.0024) * 0.5 - 0.001)
	check("a block's top corners are its fades, the rest of its edges trims",
			timeline.fade_handle_at_point(top.call(9.02)) == -1 and timeline.fade_handle_at_point(top.call(24.98)) == 1
			and timeline.fade_handle_at_point(at.call(2, 9.02)) == 0 and timeline.fade_handle_at_point(top.call(13.0)) == 0)
	var fade_depth := s.undo_depth
	lanes.grab_begin(hand, top.call(9.02))
	lanes.grab_move(hand, top.call(11.1))
	check("dragging the top left corner reads as a fade in (%s)" % lanes.readout(),
			lanes.readout() == "fade in %.2f s" % (s.bar_to_seconds(11.0) - s.bar_to_seconds(9.0)))
	check("drawn while the project waits", timeline._fade_preview.size() == 4 and s.item(2, 0).fade_in == 0.0)
	lanes.grab_end(hand)
	close_to("let go, the fade in ends on the beat it was dragged to", s.item(2, 0).fade_in, s.bar_to_seconds(11.0) - s.bar_to_seconds(9.0), 0.001)
	check("in one undo step, the item where it was", s.undo_depth == fade_depth + 1 and timeline._fade_preview.is_empty()
			and is_equal_approx(s.item(2, 0).start, s.bar_to_seconds(9.0)))
	check("its handle is now where its line ends", timeline.fade_handle_at_point(top.call(11.0)) == -1)
	lanes.grab_begin(hand, top.call(24.98))
	lanes.grab_move(hand, top.call(23.0))
	lanes.grab_end(hand)
	close_to("the top right corner sets the fade out", s.item(2, 0).fade_out, s.bar_to_seconds(25.0) - s.bar_to_seconds(23.0), 0.001)
	close_to("leaving the fade in", s.item(2, 0).fade_in, s.bar_to_seconds(11.0) - s.bar_to_seconds(9.0), 0.001)
	lanes.grab_begin(hand, top.call(11.0))
	lanes.grab_move(hand, top.call(5.0))
	lanes.grab_end(hand)
	check("dragged off the item's start, the fade in is none", s.item(2, 0).fade_in == 0.0)
	DAW.undo()
	DAW.undo()
	DAW.undo()
	check("three undos, no fades", s.item(2, 0).fade_in == 0.0 and s.item(2, 0).fade_out == 0.0 and s.undo_depth == fade_depth)
	click.call(at.call(2, 12.0))

	# The item's own controls, under the panel, while exactly one item is selected.
	var strip: TimelineItemStrip = timeline._item_controls
	check("one item selected, its controls show", strip.visible and strip.gain.collision_layer == 2)
	strip.gain.value = 0.5
	strip.gain.value_committed.emit(0.5)
	close_to("its gain knob, let go, sets its gain", s.item(2, 0).gain_db, lerpf(TimelineItemStrip.GAIN_LOW, TimelineItemStrip.GAIN_HIGH, 0.5), 0.001)
	strip.fade_in.value_committed.emit(0.5)
	close_to("a fade in at half the knob is a quarter of the item", s.item(2, 0).fade_in, s.item(2, 0).length * 0.25, 0.001)
	strip.fade_out.value_committed.emit(0.2)
	check("and the fade out leaves it", is_equal_approx(s.item(2, 0).fade_in, s.item(2, 0).length * 0.25)
			and is_equal_approx(s.item(2, 0).fade_out, s.item(2, 0).length * 0.04))
	close_to("the knob follows the item", strip.fade_in.value, 0.5, 0.001)
	timeline._process(0.0)
	var faded := s.item(2, 0)
	var fades := timeline._item_fades
	check("both fades are drawn on it (%d)" % fades.multimesh.visible_instance_count,
			fades.multimesh.visible_instance_count == 2)
	var fade_line := fades.transform_of(0)
	close_to("the fade in's line runs from its start to where the fade ends",
			fade_line.origin.x, (timeline._x_for(faded.start) + TimelineSurface.EDGE_GAP
			+ timeline._x_for(faded.start + faded.fade_in)) * 0.5, 0.0005)
	check("rising, from silence to full", fade_line.basis.x.y > 0.0 and fades.transform_of(1).basis.x.y < 0.0)
	# A flat overview, as a take at a steady level would have, so what is drawn is its level.
	var flat := PackedByteArray()
	flat.resize(int(s.item(2, 0).length * AudioTake.PEAKS_PER_SECOND) + 8)
	flat.fill(160)
	s.item(2, 0).peaks = flat
	timeline.mark_dirty()
	timeline._process(0.0)
	var waves := timeline._item_waves
	var shown := waves.multimesh.visible_instance_count
	var first_column := waves.transform_of(0).basis.y.length()
	var middle_column := waves.transform_of(shown / 2).basis.y.length()
	check("its take is drawn as heard: quiet at the start of the fade in, full in the middle (%.4f, %.4f)"
			% [first_column, middle_column], shown > 10 and first_column < middle_column * 0.4)
	var gains := timeline._gain_labels.get_children().filter(func(l): return l.visible)
	check("and its gain is written on it (%s)" % [gains.map(func(l): return l.text)],
			gains.size() == 1 and gains[0].text == "-6.0 dB")
	check("an audio-less stand-in item has no notes, so the note keys stay dark", not strip.up.lit)
	DAW.undo()
	DAW.undo()
	DAW.undo()
	check("each knob is one undo step", is_equal_approx(s.item(2, 0).gain_db, 0.0) and s.item(2, 0).fade_in == 0.0)
	hand.holding_shift = true
	click.call(at.call(3, 12.0))
	hand.holding_shift = false
	check("two selected, they hide", not strip.visible and strip.gain.collision_layer == 0)
	click.call(at.call(2, 12.0))

	# Tracks: a name pressed picks it; ADD, DEL and NAME act on it.
	var header: TimelineHeader = timeline._header
	var tracks: TimelineTrackStrip = timeline._track_controls
	var names_were: Array = s.track_indices().map(func(i): return s.track(i).name)
	check("with no track picked, only ADD is lit", tracks.add.lit and not tracks.remove.lit and not tracks.rename.lit)
	header.grab_begin(hand, at.call(3, 1.0) - timeline.global_basis.x * 0.05)
	header.grab_end(hand)
	check("a press on a track's name picks it (%d)" % timeline.picked_track, timeline.picked_track == 3
			and tracks.remove.lit and tracks.rename.lit)
	check("its AUTO key is dark while it reads its lanes", not tracks.auto.lit)
	tracks.auto.pressed.emit()
	check("AUTO puts it in touch, and lights", s.track(3).automation_mode == DAW.AUTOMATION_TOUCH and tracks.auto.lit)
	tracks.auto.pressed.emit()
	tracks.auto.pressed.emit()
	check("then latch, then back to read", s.track(3).automation_mode == DAW.AUTOMATION_READ and not tracks.auto.lit)
	DAW.undo()
	DAW.undo()
	DAW.undo()
	var colour_was := s.track(3).colour
	tracks.colour.pressed.emit()
	check("COLOUR gives it the palette's next colour, its lamp that colour (%s)" % s.track(3).colour,
			s.track(3).colour == TimelineTrackStrip.next_colour(colour_was) and tracks.colour.lit
			and tracks.colour.led_colour == s.track(3).colour)
	var colour_repl: Array = DAW.backend._repl_durable.get("/track/3/colour", [])
	check("and replicates it", colour_repl.size() == 3 and is_equal_approx(colour_repl[0], s.track(3).colour.r))
	DAW.undo()
	check("which is one undo", s.track(3).colour == colour_was)
	DAW.apply_intent(&"set_track_colour", [3, Color(2.0, -1.0, 0.5, 0.2)])
	check("a guest's colour is kept within 0-1 and opaque (%s)" % s.track(3).colour,
			s.track(3).colour == Color(1.0, 0.0, 0.5, 1.0) and &"set_track_colour" in DAW.COMMANDS)
	DAW.apply_intent(&"set_track_colour", [3, "red"])
	check("and one that is not a colour is refused", s.track(3).colour == Color(1.0, 0.0, 0.5, 1.0))
	DAW.undo()
	tracks.add.pressed.emit()
	check("ADD puts a new track after it, and picks that (%d)" % timeline.picked_track,
			s.tracks.size() == names_were.size() + 1 and s.track(4).items.is_empty() and timeline.picked_track == 4
			and s.track(5).name == names_were[3])
	var prompt: NamePrompt = timeline.ask_track_name(4)
	check("NAME asks for a name on the monitor", prompt != null and prompt._edit.text == s.track(4).name)
	prompt._edit.text_submitted.emit("  Overdub ")
	check("and the name typed is the track's (%s)" % s.track(4).name, s.track(4).name == "Overdub")

	# Where there is no keyboard -- a headset -- on a keypad in front of the panel, by hand.
	timeline.type_on_desk = true
	var pad: TypingPad = timeline.ask_track_name(4)
	check("in a headset NAME opens a keypad in the room", pad != null and pad.get_parent() == timeline
			and pad.text == "Overdub" and tracks.rename.lit)
	var finger := FakeHand.new()
	add_child(finger)
	var press := func(what: String) -> void:
		var key: PanelButton = pad.keys[what]
		key.grab_begin(finger, key.global_position)
		key.grab_end(finger)
	for ch in ["B", "A", "S", "S", " ", "SHIFT", "D", "I"]:
		press.call(ch)
	check("its keys type, the first over the old name, small unless shifted (%s)" % pad.text, pad.text == "Bass Di")
	press.call("DEL")
	press.call("SHIFT")
	press.call("I")
	press.call("OK")
	check("OK names the track (%s)" % s.track(4).name, s.track(4).name == "Bass DI" and pad.is_queued_for_deletion())
	pad = timeline.ask_track_name(4)
	(pad.keys["DEL"] as PanelButton).pressed.emit()
	(pad.keys["OK"] as PanelButton).pressed.emit()
	check("DEL first clears it, and OK on nothing names nothing", s.track(4).name == "Bass DI")
	pad = timeline.ask_track_name(4)
	var second: TypingPad = timeline.ask_track_name(4)
	check("one keypad at a time", pad.is_queued_for_deletion() and not second.is_queued_for_deletion())
	(second.keys["Q"] as PanelButton).pressed.emit()
	(second.keys["LEAVE"] as PanelButton).pressed.emit()
	check("and LEAVE leaves the name be", s.track(4).name == "Bass DI" and second.is_queued_for_deletion())
	finger.queue_free()
	timeline.type_on_desk = false
	DAW.undo()
	tracks.remove.pressed.emit()
	check("DEL removes the picked track, and nothing is picked after",
			s.track_indices().map(func(i): return s.track(i).name) == names_were and timeline.picked_track == 0)
	DAW.undo()
	DAW.undo()
	DAW.undo()
	check("three undos, and the tracks are as they were",
			s.track_indices().map(func(i): return s.track(i).name) == names_were)

	# A lane of automation over the picked track's lane, drawn and edited there.
	timeline.pick_track(3)
	check("LANE is dark while no lane is shown", not tracks.lane.lit)
	tracks.lane.pressed.emit()
	timeline._process(0.0)
	check("LANE shows the track's volume lane, and lights", timeline.shown_lane == "volume" and tracks.lane.lit
			and (timeline._automation.mesh as ImmediateMesh).get_surface_count() == 1)
	var row := s.track_indices().find(3)
	check("in a row of its own under the track, taller than a lane, the lanes below it moved down by it",
			not is_nan(timeline._auto_row_y) and timeline._auto_row_y < timeline._lane_y[row]
			and is_equal_approx(timeline._lane_y[row] - timeline._lane_y[row + 1],
					TimelineSurface.LANE_HEIGHT + 2.0 * TimelineSurface.LANE_GAP + TimelineSurface.AUTOMATION_ROW)
			and TimelineSurface.AUTOMATION_ROW > 2.0 * TimelineSurface.LANE_HEIGHT)
	check("a press on the track's own lane is not on the automation",
			not timeline.on_shown_lane(timeline.to_global(Vector3(timeline._x_for(s.bar_to_seconds(5.0)), timeline._lane_y[row], 0.0))))
	var on_lane := func(bar: float, v: float) -> Vector3:
		return timeline.to_global(Vector3(timeline._x_for(s.bar_to_seconds(bar)), timeline._automation_y(row, v), lanes.position.z))
	var lane_depth := s.undo_depth
	var selected_were := s.selected_items()
	click.call(on_lane.call(5.0, -6.0))
	var vol: Array = s.track(3).automation.get("volume", [])
	check("a press on bare lane adds a point there (%s)" % [vol], vol.size() == 1
			and is_equal_approx(vol[0][0], s.bar_to_seconds(5.0)) and absf(vol[0][1] + 6.0) < 0.05)
	check("one undo step, and no item touched", s.undo_depth == lane_depth + 1 and s.selected_items() == selected_were)
	lanes.grab_begin(hand, on_lane.call(5.0, -6.0))
	lanes.grab_move(hand, on_lane.call(7.0, -12.0))
	check("dragged, it is drawn where it is going", timeline._lane_preview.size() == 1)
	lanes.grab_end(hand)
	vol = s.track(3).automation.get("volume", [])
	check("and lands there (%s)" % [vol], vol.size() == 1 and is_equal_approx(vol[0][0], s.bar_to_seconds(7.0))
			and absf(vol[0][1] + 12.0) < 0.05 and timeline._lane_preview.is_empty())
	click.call(on_lane.call(7.0, vol[0][1]))
	check("a click on a point makes it hold", s.track(3).automation["volume"][0][2] == DawKitAutomation.HOLD)
	hand.hover_point = on_lane.call(7.0, s.track(3).automation["volume"][0][1])
	lanes.hover_enter(hand)
	check("hovered, the card names the lane and reads the point (%s, %s)" % [lanes.title(), lanes.readout()],
			lanes.title() == "AUTOMATION  VOLUME" and lanes.readout().contains("dB at 7.1.00, held"))
	var before := float(s.track(3).automation["volume"][0][1])
	lanes._on_nudge(2, false)
	close_to("the wheel over it nudges its value", s.track(3).automation["volume"][0][1], before + 2 * TimelineLanes.nudge_step("volume"))
	lanes.hover_exit(hand)
	hand.holding_shift = true
	click.call(on_lane.call(7.0, s.track(3).automation["volume"][0][1]))
	hand.holding_shift = false
	check("a fine click takes it away, and with it the lane", not s.track(3).automation.has("volume"))
	check("each edit one undo step", s.undo_depth == lane_depth + 5)
	for _i in 5:
		DAW.undo()
	check("all undone", not s.track(3).automation.has("volume") and s.undo_depth == lane_depth)
	for _i in 12:
		if timeline.shown_lane == "":
			break
		tracks.lane.pressed.emit()
	timeline._process(0.0)
	check("LANE steps through pan and mute to none, and the row closes", timeline.shown_lane == "" and not tracks.lane.lit
			and (timeline._automation.mesh as ImmediateMesh).get_surface_count() == 0 and is_nan(timeline._auto_row_y)
			and is_equal_approx(timeline._lane_y[row] - timeline._lane_y[row + 1], TimelineSurface.LANE_HEIGHT + TimelineSurface.LANE_GAP))
	timeline.pick_track(0)
	# With no track picked, LANE is the master's.
	check("with no track picked, LANE offers the master's lanes (%s)" % tracks.lane.describe_value.call(0.0),
			tracks.lane.describe_value.call(0.0) == "show the master's volume")
	tracks.lane.pressed.emit()
	timeline._process(0.0)
	var last_row: int = timeline._lane_y.size() - 1
	check("which opens its row under the last track", timeline.shown_lane == "volume" and tracks.lane.lit
			and not is_nan(timeline._auto_row_y) and timeline._auto_row_y < timeline._lane_y[last_row])
	var master_depth := s.undo_depth
	click.call(timeline.to_global(Vector3(timeline._x_for(s.bar_to_seconds(9.0)), timeline._automation_y(last_row, -3.0), lanes.position.z)))
	var master_vol: Array = s.master.automation.get("volume", [])
	check("a press there puts a point on the master's fader lane, not a track's (%s)" % [master_vol],
			master_vol.size() == 1 and absf(master_vol[0][1] + 3.0) < 0.05 and s.undo_depth == master_depth + 1
			and s.track_indices().all(func(i): return not s.track(i).automation.has("volume"))
			and not s.tracks.has(0))
	check("and it is drawn (%d, %s)" % [(timeline._automation.mesh as ImmediateMesh).get_surface_count(), timeline.shown_points()], (timeline._automation.mesh as ImmediateMesh).get_surface_count() == 1
			and timeline.shown_points() == master_vol)
	DAW.undo()
	check("undone, the master has no lane", not s.master.automation.has("volume"))
	check("AUTO, with no track picked, is the master's (%s)" % tracks.auto.describe_value.call(0.0),
			tracks.auto.describe_value.call(0.0) == "the master reads its lanes: TOUCH next" and not tracks.auto.lit)
	tracks.auto.pressed.emit()
	check("and puts the master in touch, lit", s.master.automation_mode == DAW.AUTOMATION_TOUCH and tracks.auto.lit)
	DAW.undo()
	check("one undo step", s.master.automation_mode == DAW.AUTOMATION_READ and not tracks.auto.lit)
	timeline.pick_track(3)
	check("picking a track puts the master's lane away", timeline.shown_lane == "")
	timeline.pick_track(0)
	timeline._process(0.0)
	click.call(at.call(2, 12.0))
	var render: TimelineRenderStrip = timeline._render_controls
	check("the stand-in cannot render, and its MIX and STEMS keys say so (%s)" % render.mix.describe_value.call(0.0),
			not render.mix.lit and not render.stems.lit and render.mix.describe_value.call(0.0).contains("cannot render"))

	# The tempo's changes, from the strip under the middle.
	var tempo: TimelineTempoStrip = timeline._tempo_controls
	var was_tempo := s.tempo
	DAW.seek(s.bar_to_seconds(5.0))
	check("one tempo: no change to remove or ramp", not tempo.remove.lit and not tempo.ramp.lit and tempo.current() == 0)
	tempo.add.pressed.emit()
	check("ADD puts a change at the playhead's bar (%s)" % [s.tempo_points], s.tempo_points.size() == 2
			and is_equal_approx(s.tempo_points[1][0], 16.0) and tempo.current() == 1 and tempo.remove.lit)
	tempo.bpm.value_committed.emit(0.5)
	close_to("its BPM knob sets that change's tempo", s.tempo_points[1][1], lerpf(TimelineTempoStrip.BPM_LOW, TimelineTempoStrip.BPM_HIGH, 0.5), 0.05)
	close_to("and not the song's", s.tempo, was_tempo)
	DAW.seek(s.bar_to_seconds(2.0))
	check("before it, the strip is on the song's own tempo", tempo.current() == 0 and tempo.ramp.lit == false)
	tempo.ramp.pressed.emit()
	check("RAMP glides from there to the change", s.tempo_points[0][2] == DawKitTempoMap.RAMP_BEATS and tempo.ramp.lit)
	check("and the ruler says where the tempo changes, and to what",
			timeline._ruler.get_children().any(func(c): return c is Label3D and c.text == "/%d" % roundi(s.tempo_points[1][1])))
	DAW.seek(s.bar_to_seconds(6.0))
	tempo.remove.pressed.emit()
	check("DEL on the change leaves one tempo again", s.tempo_points.is_empty() and is_equal_approx(s.tempo, was_tempo))
	for i in 4:
		DAW.undo()
	check("four undos, and the tempo is as it was", s.tempo_points.is_empty() and is_equal_approx(s.tempo, was_tempo))
	DAW.seek(s.bar_to_seconds(5.0))
	click.call(at.call(2, 12.0))

	# Copy and delete, under the track names, for the selection.
	check("copy and delete light with a selection", timeline._copy_key.lit and timeline._delete_key.lit)
	timeline._copy_key.pressed.emit()
	check("copy puts a copy after the item (%d)" % s.track(2).items.size(), s.track(2).items.size() == count + 1)
	timeline._delete_key.pressed.emit()
	check("delete takes the selection, which is the copy", s.track(2).items.size() == count)
	DAW.undo()
	DAW.undo()
	DAW.clear_item_selection()
	check("with nothing selected they go dark", not timeline._copy_key.lit and not timeline._delete_key.lit)
	click.call(at.call(2, 12.0))

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


func _test_saved_data_follows_the_rename() -> void:
	var root := OS.get_temp_dir().path_join("dawlings_rename_%d" % OS.get_process_id())
	var old := root.path_join("reaper-3d")
	var new := root.path_join("dawlings")
	DirAccess.make_dir_recursive_absolute(old.path_join("takes"))
	DirAccess.make_dir_recursive_absolute(old.path_join("shader_cache"))
	DirAccess.make_dir_recursive_absolute(new)
	for f in [["layout_profile.cfg", "old layout"], ["ghost_look.cfg", "old ghost"],
			["takes/Grace-take1.wav", "RIFF"], ["shader_cache/x", "cache"]]:
		FileAccess.open(old.path_join(f[0]), FileAccess.WRITE).store_string(f[1])
	FileAccess.open(new.path_join("ghost_look.cfg"), FileAccess.WRITE).store_string("new ghost")
	FileAccess.open(old.path_join("run.sh"), FileAccess.WRITE).store_string("#!/bin/sh")
	FileAccess.set_unix_permissions(old.path_join("run.sh"), 493)  # 0755
	var copied := DataHome.migrate(new)
	check("the old app's saved files are copied across (%d)" % copied, copied == 3
			and FileAccess.get_file_as_string(new.path_join("layout_profile.cfg")) == "old layout"
			and FileAccess.file_exists(new.path_join("takes/Grace-take1.wav")))
	check("without overwriting what the new one already has",
			FileAccess.get_file_as_string(new.path_join("ghost_look.cfg")) == "new ghost")
	check("or bringing the engine's caches", not FileAccess.file_exists(new.path_join("shader_cache/x")))
	check("a file keeps its permissions", FileAccess.get_unix_permissions(new.path_join("run.sh")) & 64 != 0)  # owner execute
	check("and the old folder is left as it was",
			FileAccess.get_file_as_string(old.path_join("layout_profile.cfg")) == "old layout")
	FileAccess.open(old.path_join("later.cfg"), FileAccess.WRITE).store_string("x")
	check("only once", DataHome.migrate(new) == 0 and not FileAccess.file_exists(new.path_join("later.cfg")))
	OS.execute("rm", ["-rf", root])


func _test_a_project_goes_into_dawkit_and_back() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var s := DAW.state
	DAW.set_track_volume(6, 0.5)
	DAW.set_loop_range(8.0, 16.0)
	DAW.set_looping(true)
	var first := ProjectBridge.capture(backend)
	check("the demo is a project of its own tracks (%d)" % first.tracks.size(),
			first.tracks.size() == s.tracks.size() and first.problems().is_empty())
	check("the kick is in the DRUMS folder, as a parent", first.track("t2").parent == "t1"
			and first.track("t6").parent == "")
	check("an effect of the engine's own keeps its kind",
			first.tracks.any(func(t): return t.effects.any(func(e): return not e.kind.is_empty())))
	check("the Rhodes part keeps its notes",
			first.tracks.any(func(t): return t.clips.any(func(c): return c.is_midi())))

	var replaced := [0]
	DAW.project_replaced.connect(func(): replaced[0] += 1)
	var fresh := GodotBackend.new()
	fresh.state = MixState.new()
	DAW.use(fresh)
	DAW.set_track_volume(3, 0.1)
	check("a fresh engine has history to lose", DAW.state.undo_depth > 0)
	var refused := ProjectBridge.load(first, fresh)
	check("the project loads (%s)" % [refused], refused.is_empty())
	check("and says it replaced the project, once", replaced[0] == 1)
	check("with nothing left to undo", DAW.state.undo_depth == 0)
	var again := ProjectBridge.capture(fresh)
	check("captured again it is the same project (%s)" % first.first_difference(again), first.same_as(again))
	var bus := func(index: int) -> int: return AudioServer.get_bus_index("%s%d" % [GodotBackend.BUS_PREFIX, index])
	check("the loaded kick still plays through the DRUMS bus",
			AudioServer.get_bus_send(bus.call(2)) == AudioServer.get_bus_name(bus.call(1)))
	close_to("and the loaded bass fader is the bus's gain", AudioServer.get_bus_volume_db(bus.call(6)),
			fresh.taper_to_db(0.5), 0.01)

	var smaller := first.duplicate()
	smaller.tracks.resize(4)
	for t in smaller.tracks:
		t.sends = t.sends.filter(func(sd): return smaller.track(sd.target) != null)
	check("a smaller project loads over a bigger one", ProjectBridge.load(smaller, fresh).is_empty())
	check("and the desk has only its tracks (%d)" % DAW.state.tracks.size(), DAW.state.tracks.size() == 4)
	var broken := first.duplicate()
	broken.tracks[0].parent = "t99"
	check("a project with a broken folder is refused", not ProjectBridge.load(broken, fresh).is_empty())
	check("and the open one is left alone", DAW.state.tracks.size() == 4)


func _test_the_built_in_engine_saves_and_opens_dawproject() -> void:
	var dir := OS.get_temp_dir().path_join("dawlings_projects_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("demo.dawproject")
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	check("the built-in engine can save and open its own files",
			DAW.can(DAWBackend.Capability.PROJECT_FILES) and DAW.can(DAWBackend.Capability.PROJECT_SAVE))
	var said := DAW.save_project_as(path)
	check("the demo saves as a .dawproject (%s)" % [said], said.is_empty() and FileAccess.file_exists(path))
	check("and the engine knows where it is now", backend.project_path == path)
	if OS.execute("sh", ["-c", "command -v xmllint"]) == 0:
		var r := ZIPReader.new()
		r.open(path)
		var out := dir.path_join("demo_project.xml")
		var copy := FileAccess.open(out, FileAccess.WRITE)
		copy.store_buffer(r.read_file("project.xml"))
		copy.close()
		r.close()
		var lint_said: Array = []
		var rc := OS.execute("xmllint", ["--noout", "--schema", ProjectSettings.globalize_path(
				"res://vendor/dawkit/tests/fixtures/dawproject/Project.xsd"), out], lint_said, true)
		check("and is valid DAWproject (%s)" % str(lint_said).substr(0, 300), rc == 0)

	var media := dir.path_join("inspect")
	var inspected: DawKitProject = DawKitDawproject.open(path, media)["project"]
	var drums: DawKitTrack = null
	for t in inspected.tracks:
		if DemoSong.role_of(t.name) != "" and not t.clips.is_empty() and drums == null:
			drums = t
	check("a demo track's items became clips of a rendered part", drums != null
			and drums.clips[0].source.begins_with("audio/demo_") and drums.clips[0].is_looped())
	if drums != null:
		var wav := FileAccess.get_file_as_bytes(media.path_join(drums.clips[0].source))
		var info := DawKitDawproject.wav_info(wav)
		close_to("the part in the file is exactly its loop long", float(info.get("seconds", 0.0)),
				DemoSong.loop_seconds(inspected.tempo), 0.0001)
		close_to("and the clip loops all of it", drums.clips[0].loop_end, DemoSong.loop_seconds(inspected.tempo), 0.0001)
		var peak := 0.0
		var stream := AudioStreamWAV.load_from_file(media.path_join(drums.clips[0].source))
		var data := stream.data
		for i in range(0, data.size() - 1, 2):
			peak = maxf(peak, absf(data.decode_s16(i) / 32768.0))
		check("and is the music, not silence (peak %.2f)" % peak, peak > 0.1)
		var bar := DemoSong.loop_seconds(inspected.tempo)
		var off := drums.clips.filter(func(c):
			return absf(wrapf(c.source_offset - c.start, -bar * 0.5, bar * 0.5)) >= 0.0001)
		check("each clip starts where the song's loop had got to (%s)" % [off.map(func(c): return [c.start, c.source_offset])],
				off.is_empty())

	var fresh := GodotBackend.new()
	fresh.state = MixState.new()
	DAW.use(fresh)
	var opened := DAW.open_project(path)
	check("a fresh engine opens it (%s)" % [opened], opened.is_empty())
	check("with the demo's tracks", DAW.state.tracks.size() == backend.state.tracks.size())
	var looped: MixState.ItemState = null
	for index in DAW.state.track_indices():
		for it in DAW.state.track(index).items:
			if it.is_looped() and looped == null:
				looped = it
	check("its parts are now files it plays, looped", looped != null and looped.source.begins_with("demo_")
			and FileAccess.file_exists(fresh.media_path(looped.source)))
	if looped != null:
		var stream := fresh.looped_stream(looped.source, looped.loop_start, looped.loop_end)
		check("as a stream that goes round its loop", stream != null
				and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end > stream.loop_begin)
	var first := ProjectBridge.capture(fresh)
	DAW.save_project()
	var again := GodotBackend.new()
	again.state = MixState.new()
	DAW.use(again)
	DAW.open_project(path)
	var second := ProjectBridge.capture(again)
	check("saved again where it was and reopened, it is the same (%s)" % first.first_difference(second),
			first.same_as(second))

	var elsewhere := dir.path_join("not_here.dawproject")
	DAW.apply_intent(&"save_project", [elsewhere])
	check("a guest's save goes where the host's project is, never where the guest says",
			not FileAccess.file_exists(elsewhere))

	DAW.set_track_volume(1, 0.2)
	var blank := DAW.new_project()
	check("a new project is an empty one (%s)" % [blank], blank.is_empty() and DAW.state.tracks.size() == 4
			and DAW.state.track(1).items.is_empty() and again.project_path == "")
	check("with nothing to undo", DAW.state.undo_depth == 0)
	OS.execute("rm", ["-rf", dir])


## The official DAWproject examples dawkit keeps as fixtures, opened by the built-in engine as a
## player would open them, saved by the game, and opened again.
func _test_the_official_dawproject_examples_open_in_the_game() -> void:
	var fixtures := ProjectSettings.globalize_path("res://vendor/dawkit/tests/fixtures/dawproject")
	var dir := OS.get_temp_dir().path_join("dawlings_examples_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir.path_join("target"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("test-data"))
	var wav := fixtures.path_join("reference/white-glasses.wav")
	DirAccess.copy_absolute(wav, dir.path_join("test-data/white-glasses.wav"))
	var lint := OS.execute("sh", ["-c", "command -v xmllint"]) == 0
	var names := Array(DirAccess.get_files_at(fixtures.path_join("reference"))).filter(
			func(f): return f.ends_with(".xml"))
	check("the examples are there to open (%d)" % names.size(), names.size() >= 20)
	for f in names:
		var name: String = f.get_basename()
		var xml := FileAccess.get_file_as_string(fixtures.path_join("reference").path_join(f)) \
				.replace("@FIXTURES@", fixtures.path_join("reference"))
		var path := dir.path_join("target").path_join(name + ".dawproject")
		var zip := ZIPPacker.new()
		zip.open(path)
		zip.start_file("project.xml")
		zip.write_file(xml.to_utf8_buffer())
		zip.close_file()
		if 'path="white-glasses.wav" external="false"' in xml:
			zip.start_file("white-glasses.wav")
			zip.write_file(FileAccess.get_file_as_bytes(wav))
			zip.close_file()
		zip.close()
		var read := DawKitDawproject.open(path, dir.path_join("read_" + name))
		var want: DawKitProject = read["project"]
		var backend := GodotBackend.new()
		backend.state = MixState.new()
		DAW.use(backend)
		var said := DAW.open_project(path)
		check("%s opens in the game saying what dawkit says (%s)" % [name, said],
				want != null and said == read["warnings"])
		if want == null:
			continue
		var items: Array = []
		for index in DAW.state.track_indices():
			for it in DAW.state.track(index).items:
				items.append([snappedf(it.start, 0.0001), snappedf(it.length, 0.0001), it.notes.size() / 5])
		var clips: Array = []
		for t in want.tracks:
			for c in t.clips:
				clips.append([snappedf(c.start, 0.0001), snappedf(c.length, 0.0001), c.note_count()])
		check("%s's clips are the game's items (%s vs %s)" % [name, items, clips], items == clips)
		for index in DAW.state.track_indices():
			for it in DAW.state.track(index).items:
				if not it.source.is_empty():
					check("%s's sound is one the engine can play (%s)" % [name, it.source],
							FileAccess.file_exists(backend.media_path(it.source)))
		var first := ProjectBridge.capture(backend)
		var saved := dir.path_join("saved_" + name + ".dawproject")
		var wrote := DAW.save_project_as(saved)
		check("%s saves from the game (%s)" % [name, wrote], wrote.is_empty())
		if lint:
			var out := dir.path_join("saved_" + name + "_project.xml")
			var r := ZIPReader.new()
			r.open(saved)
			var copy := FileAccess.open(out, FileAccess.WRITE)
			copy.store_buffer(r.read_file("project.xml"))
			copy.close()
			r.close()
			var lint_said: Array = []
			var rc := OS.execute("xmllint", ["--noout", "--schema", fixtures.path_join("Project.xsd"), out], lint_said, true)
			check("%s as the game saves it is valid DAWproject (%s)" % [name, str(lint_said).substr(0, 300)], rc == 0)
		var again := GodotBackend.new()
		again.state = MixState.new()
		DAW.use(again)
		DAW.open_project(saved)
		var second := ProjectBridge.capture(again)
		check("%s saved by the game and opened again is the same (%s)" % [name, first.first_difference(second)],
				first.same_as(second))
		if name == "test-complex":
			check("test-complex's volume lane and markers reach the game",
					DAW.state.track(1).automation.has("volume") and DAW.state.markers.size() == 2)
	OS.execute("rm", ["-rf", dir])


func _test_the_project_is_saved_from_the_room_and_the_room_is_told() -> void:
	var dir := OS.get_temp_dir().path_join("dawlings_panel_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var notices: Array[String] = []
	var hear := func(t: String): notices.append(t)
	Session.notice.connect(hear)
	_as_session(Session.Role.HOST, 1)
	Session.local_name = "Ada"
	var panel := SessionPanel.new()
	add_child(panel)
	panel.open()
	check("the panel names the project (%s)" % panel._project_name.text, panel._project_name.text == backend.project_title)
	check("which has not been saved yet", panel._project_where.text == "Not saved yet.")
	check("and the host may save it elsewhere, open one or start one", panel._project_host_row.visible)

	var path := dir.path_join("Our Song.dawproject")
	var said := panel.save_project_as(dir.path_join("Our Song"))
	check("Save As adds the extension and writes the file (%s)" % [said], said.is_empty() and FileAccess.file_exists(path))
	check("the room hears where it went (%s)" % [notices], notices == ["Ada saved the project as Our Song.dawproject."])
	check("and the panel shows it", panel._project_where.text == "Our Song.dawproject")
	notices.clear()
	var key := InputEventKey.new()
	key.keycode = KEY_S
	key.ctrl_pressed = true
	key.pressed = true
	panel._unhandled_input(key)
	check("Ctrl+S saves it where it is, and says so (%s)" % [notices],
			notices == ["Ada saved the project as Our Song.dawproject."] and FileAccess.file_exists(path))
	notices.clear()
	Session.save_project_for("Grace")
	check("a guest's save is announced in the guest's name (%s)" % [notices],
			notices == ["Grace saved the project as Our Song.dawproject."])
	notices.clear()
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)
	var save_key := timeline.get_node_or_null(^"SaveKey") as PanelButton
	check("the timeline has a save key, lit where saving works", save_key != null and save_key.lit)
	if save_key != null:
		save_key.pressed.emit()
		check("which saves the same way (%s)" % [notices], notices == ["Ada saved the project as Our Song.dawproject."])
	notices.clear()
	remove_child(timeline)
	timeline.free()

	DAW.set_track_volume(1, 0.2)
	said = panel.start_new_project()
	check("New starts an empty project and tells the room (%s)" % [notices],
			said.is_empty() and notices == ["Ada started an empty project."] and DAW.state.tracks.size() == 4)
	check("which the panel shows unsaved", panel._project_where.text == "Not saved yet.")
	notices.clear()
	said = panel.open_project(path)
	check("Open brings the saved one back (%s %s)" % [said, notices],
			said.is_empty() and notices == ["Ada opened Our Song.dawproject."] and DAW.state.tracks.size() > 4)
	notices.clear()
	var fixtures := ProjectSettings.globalize_path("res://vendor/dawkit/tests/fixtures/dawproject/reference")
	var other := dir.path_join("From Elsewhere.dawproject")
	var zip := ZIPPacker.new()
	zip.open(other)
	zip.start_file("project.xml")
	zip.write_file(FileAccess.get_file_as_bytes(fixtures.path_join("MIDI-CC1-AutomationOnTrack.xml")))
	zip.close_file()
	zip.close()
	said = panel.open_project(other)
	check("a file that opens with something left out is opened, and the room hears what (%s)" % [notices],
			said.size() == 1 and notices.size() == 1 and notices[0].begins_with("Ada opened From Elsewhere.dawproject, but: ")
			and "MIDI" in notices[0] and DAW.project_file() == other)
	notices.clear()
	said = panel.open_project(dir.path_join("missing.dawproject"))
	var shown: String = panel._toasts.get_child(-1).get_child(0).text
	check("a file that is not there is refused, to the one who asked and not the room (%s / %s)" % [shown, notices],
			not said.is_empty() and notices.is_empty() and shown.begins_with("You could not open"))
	notices.clear()

	_as_session(Session.Role.GUEST, 5)
	panel._refresh_project()
	var host_title := backend.project_title if not backend.project_title.is_empty() else "%s's project" % Session.name_of(1)
	check("a guest sees the host's project by its name and file, and no file buttons (%s / %s)" % [
			panel._project_name.text, panel._project_where.text],
			panel._project_name.text == host_title and panel._project_where.text.begins_with("From Elsewhere.dawproject, on ")
			and not panel._project_host_row.visible)
	var told := MixState.new()
	MixWire.apply_replicated(told, MixWire.snapshot(DAW.state))
	check("the name and file reach a guest in the snapshot, without the host's folders (%s, %s)" % [
			told.project_title, told.project_file],
			told.project_title == backend.project_title and told.project_file == "From Elsewhere.dawproject")
	check("but may still press save", not panel._project_save.disabled)
	check("and the host-only verbs refuse a guest", not DAW.save_project_as(path).is_empty()
			and not DAW.open_project(path).is_empty() and not DAW.new_project().is_empty())
	Session.notice.disconnect(hear)
	remove_child(panel)
	panel.free()
	Session.start_solo()
	_offline()
	OS.execute("rm", ["-rf", dir])


func _test_sound_files_are_brought_in_onto_a_track() -> void:
	var dir := OS.get_temp_dir().path_join("dawlings_import_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	# Two files: a second of a 441 Hz tone at half scale, as 32-bit float, and as 16-bit.
	var tone := PackedFloat32Array()
	for f in 44100:
		var v := 0.5 * sin(TAU * 441.0 * f / 44100.0)
		tone.append_array([v, v])
	var first := dir.path_join("Tone One.wav")
	DawKitAudioFile.write_wav(first, tone, 2, 44100)
	var second := dir.path_join("tone two.wav")
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100
	var pcm := PackedByteArray()
	pcm.resize(22050 * 4)
	for f in 22050:
		var q := int(0.25 * 32767.0 * sin(TAU * 441.0 * f / 44100.0))
		pcm.encode_s16(f * 4, q)
		pcm.encode_s16(f * 4 + 2, q)
	wav.data = pcm
	wav.save_to_wav(second)

	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var notices: Array[String] = []
	var hear := func(t: String): notices.append(t)
	Session.notice.connect(hear)
	_as_session(Session.Role.HOST, 1)
	Session.local_name = "Ada"
	var panel := SessionPanel.new()
	add_child(panel)
	panel.open()
	check("the host is offered to bring in audio", panel._import_box.visible)

	var track: int = DAW.state.track_indices()[2]
	DAW.state.track(track).items.clear()
	panel._import_into.select(panel._import_into.get_item_index(track))
	DAW.seek(4.0)
	var depth := maxi(DAW.state.undo_depth, 0)
	var failed := panel.bring_in_files(PackedStringArray([first, second]))
	check("nothing is placed until a file is in, off the main thread (%d)" % DAW.state.track(track).items.size(),
			failed.is_empty() and DAW.importing() and DAW.state.track(track).items.is_empty())
	var done: Array = await DAW.audio_import_done
	# The panel hears the same signal; in whichever order, it has by the next frame.
	await get_tree().process_frame
	var items: Array = DAW.state.track(track).items
	check("both files land on the chosen track (%s, %d items)" % [done, items.size()],
			(done[1] as PackedStringArray).is_empty() and items.size() == 2 and done[2] == track and not DAW.importing())
	if items.size() == 2:
		close_to("the first at the playhead", items[0].start, 4.0, 0.001)
		close_to("a second long", items[0].length, 1.0, 0.0001)
		close_to("the second straight after it", items[1].start, 5.0, 0.001)
		close_to("half a second long", items[1].length, 0.5, 0.0001)
		check("named after their files", items[0].name == "Tone One" and items[1].source == "tone two.wav")
		check("each drawn from its own overview (%d)" % items[0].peaks.size(),
				items[0].peaks.size() == 50 and absi(items[0].peaks[10] - 127) <= 1 and absi(items[1].peaks[10] - 63) <= 1)
		var stream := backend.take_stream(items[0].source)
		check("and the engine plays it", stream != null and absf(stream.get_length() - 1.0) < 0.001)
	check("the room hears what came in (%s)" % [notices],
			notices.size() == 1 and notices[0].begins_with("Ada brought in Tone One.wav, tone two.wav on "))
	check("each file is a step to undo (%d -> %d)" % [depth, DAW.state.undo_depth], DAW.state.undo_depth == depth + 2)
	notices.clear()

	# Let go over a lane of the timeline: that lane's track, at the beat under the cursor.
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)
	timeline.set_view(0.0, DAW.state.bar_to_seconds(41.0))
	var lanes: TimelineLanes = timeline._lanes
	var other: int = DAW.state.track_indices()[3]
	var row := DAW.state.track_indices().find(other)
	var over := timeline.to_global(Vector3(timeline._x_for(DAW.state.bar_to_seconds(6.3)), timeline._lane_y[row], lanes.position.z))
	var spot := lanes.drop_spot(over, false)
	var beat := DAW.state.seconds_at_beat(roundf(DAW.state.beat_at(DAW.state.bar_to_seconds(6.3))))
	check("a drop on a lane picks its track (%s)" % [spot], spot.size() == 2 and spot[0] == other)
	if spot.size() == 2:
		close_to("and the beat under it", spot[1], beat, 0.001)
		close_to("or, fine, the time itself", lanes.drop_spot(over, true)[1], DAW.state.bar_to_seconds(6.3), 0.01)
	var above := timeline.to_global(Vector3(timeline._x_for(4.0), timeline._lane_y[0] + 0.05, lanes.position.z))
	check("off the lanes, no spot", lanes.drop_spot(above, false).is_empty())
	var before: int = DAW.state.track(other).items.size()
	failed = panel.bring_in_files(PackedStringArray([second]), spot[0], spot[1])
	done = await DAW.audio_import_done
	await get_tree().process_frame
	var landed: Array = DAW.state.track(other).items.filter(func(it): return it.source.begins_with("tone two"))
	check("dropped there, the file lands there (%s)" % [failed], failed.is_empty()
			and DAW.state.track(other).items.size() == before + 1 and landed.size() == 1
			and absf(landed[0].start - beat) < 0.001)
	check("and the import box's track is not used", DAW.state.track(track).items.size() == 2)
	DAW.undo()
	timeline.queue_free()
	notices.clear()

	var flac := DAW.import_audio(ProjectSettings.globalize_path("res://vendor/dawkit/tests/fixtures/audio/flac/s16_stereo_8.flac"), track, 20.0)
	check("a FLAC file comes in too, as a WAV the engine plays (%s)" % flac["error"], flac["error"] == ""
			and flac["name"] == "s16_stereo_8.wav" and absf(float(flac["seconds"]) - 9000.0 / 44100.0) < 0.0001
			and backend.take_stream("s16_stereo_8.wav") != null)
	DAW.undo()
	var again := DAW.import_audio(first, track, 10.0)
	check("the same file again gets a name of its own (%s)" % again.get("name"), again.get("name") == "Tone One 2.wav")
	var bad := dir.path_join("notes.txt")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("not a sound")
	f.close()
	failed = panel.bring_in_files(PackedStringArray([bad]))
	done = await DAW.audio_import_done
	await get_tree().process_frame
	var shown: String = panel._toasts.get_child(-1).get_child(0).text
	check("a file that is not sound is turned away, to the host alone (%s)" % shown,
			failed.is_empty() and (done[1] as PackedStringArray).size() == 1 and notices.is_empty()
			and shown.contains("not a sound file"))

	# A long file: the call comes straight back while it is read, and the frames keep coming.
	var long_wav := AudioStreamWAV.new()
	long_wav.format = AudioStreamWAV.FORMAT_16_BITS
	long_wav.stereo = true
	long_wav.mix_rate = 44100
	var long_pcm := PackedByteArray()
	for n in 120:
		long_pcm.append_array(pcm)
	long_wav.data = long_pcm
	var long_path := dir.path_join("long one.wav")
	long_wav.save_to_wav(long_path)
	var asked := Time.get_ticks_usec()
	failed = panel.bring_in_files(PackedStringArray([long_path]), track, 30.0)
	var returned_ms := (Time.get_ticks_usec() - asked) / 1000.0
	var frames := 0
	while DAW.importing():
		await get_tree().process_frame
		frames += 1
	var whole_ms := (Time.get_ticks_usec() - asked) / 1000.0
	var long_item = DAW.state.track(track).items.filter(func(it): return it.source.begins_with("long one"))
	check("a minute of sound comes back at once (%.1f ms of %.0f ms, %d frames meanwhile)" % [returned_ms, whole_ms, frames],
			failed.is_empty() and returned_ms < 20.0 and frames >= 2 and long_item.size() == 1
			and absf(long_item[0].length - 60.0) < 0.001)
	DAW.undo()
	notices.clear()

	var saved := dir.path_join("with_audio.dawproject")
	check("a project with brought-in audio saves", DAW.save_project_as(saved).is_empty())
	var inspected: DawKitProject = DawKitDawproject.open(saved, dir.path_join("inspect"))["project"]
	var clip_sources: Array = []
	for t in inspected.tracks:
		for c in t.clips:
			if c.source.contains("Tone One"):
				clip_sources.append(c.source)
	check("and carries the files inside it (%s)" % [clip_sources], clip_sources.has("audio/Tone One.wav"))
	DAW.undo()
	DAW.undo()
	DAW.undo()
	check("undone, the files are gone from the track", DAW.state.track(track).items.is_empty())

	DAW.select_item(DAW.state.track_indices()[4], 0)
	if not DAW.state.track(DAW.state.track_indices()[4]).items.is_empty():
		check("with no track chosen, files go where the selection is",
				AudioImport.target_track(DAW.state) == DAW.state.track_indices()[4])
	check("names are made safe and kept apart", AudioImport.file_name_for("/x/a:b.mp3", func(n): return n == "a_b.wav") == "a_b 2.wav")

	_as_session(Session.Role.GUEST, 5)
	panel._refresh_project()
	check("a guest is offered to send files to the host instead (%s)" % panel._import_caption.text,
			panel._import_box.visible and panel._import_caption.text.begins_with("SEND AUDIO TO"))
	check("and a guest's drop is refused", not DAW.import_audio(first, track, 0.0)["error"].is_empty()
			and not DAW.import_audio_files(PackedStringArray([first]), track, 0.0).is_empty()
			and panel.bring_in_files(PackedStringArray([first])).size() == 1)
	Session.notice.disconnect(hear)
	remove_child(panel)
	panel.free()
	Session.start_solo()
	_offline()
	for name in ["Tone One.wav", "Tone One 2.wav", "tone two.wav", "tone two 2.wav", "long one.wav", "s16_stereo_8.wav"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioTake.DIR.path_join(name)))
	OS.execute("rm", ["-rf", dir])


func _test_the_host_records_its_own_microphone_on_the_built_in_engine() -> void:
	var backend := _offline()
	_as_session(Session.Role.HOST, 1)
	Session.local_name = "Ada"
	var notices: Array[String] = []
	var hear := func(t: String): notices.append(t)
	Session.notice.connect(hear)
	var ha := Session.host_audio
	var mic := _FakeMic.new()
	ha.record_with_host = false
	ha.target_track = 0
	check("the host's microphone is off until asked", not ha.armed())
	ha.record_with_host = true
	var armed := HitRecorder.armed_track()
	check("asked, it goes on the armed track with none chosen (%d)" % armed, armed > 0 and ha.take_track() == armed)
	check("and is armed, as the stand-in does not record its own inputs", ha.armed())
	DAW.state.track(armed).items.clear()
	ha._source = mic
	# The host hears its song from 20s, its output 15ms late; the microphone is 10ms late.
	var song := func(wall: float) -> float: return 20.0 + wall
	var ticks := 400
	for tick in ticks:
		var got := ha._read()
		var read_at := float(mic.made - 1) / 48000.0 + mic.latency
		ha.follow({"seconds": song.call(read_at), "playing": true, "recording": tick < ticks - 1,
				"valid": true}, got)
	var items: Array = DAW.state.track(armed).items
	check("the take is placed on the host's own timeline (%d)" % items.size(), items.size() == 1)
	if items.size() == 1:
		# The first read is from before recording was heard to start, so the take is from the
		# second: 480 frames on.
		close_to("where the song was when its first sound was made", items[0].start, 20.0 + 480.0 / 48000.0, 0.0001)
		close_to("as long as it ran", items[0].length, 4.0, 0.02)
		check("its file is a take, named for the host (%s)" % items[0].source, items[0].source.begins_with("Ada"))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioTake.DIR.path_join(items[0].source)))
	check("and the host is told, once (%s)" % [notices], notices.size() == 1 and notices[0].begins_with("Ada recorded 4.0s onto"))

	var h := Session.host_heard()
	DAW.state.position_seconds = 12.0
	DAW.state.playing = true
	DAW.state.recording = true
	h = Session.host_heard()
	close_to("what the host hears is its playhead less the output's latency", h["seconds"],
			12.0 - AudioServer.get_output_latency(), 0.0001)
	check("recording while it rolls", h["recording"])
	DAW.state.playing = false
	DAW.state.recording = false

	var panel := SessionPanel.new()
	add_child(panel)
	panel.open()
	check("the host has the microphone's controls on the built-in engine",
			panel._mic_box.visible and panel._mic_box.get_parent() == panel._column)
	check("saying it records with them", panel._mic_record.text == "Record my mic when I record")
	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	DAW.use(reaper)
	panel._refresh()
	check("but not where the DAW records its own inputs", not ha.armed() and not panel._mic_box.visible)
	_as_session(Session.Role.GUEST, 5)
	panel._refresh()
	check("a guest's microphone is in the guest's section", panel._mic_box.visible
			and panel._mic_box.get_parent() == panel._guest_box)
	remove_child(panel)
	panel.free()
	ha.record_with_host = false
	ha._source = null
	Session.notice.disconnect(hear)
	Session.start_solo()
	_offline()
	if is_instance_valid(reaper):
		reaper.queue_free()


func _test_one_recording_goes_onto_every_armed_track_of_its_input() -> void:
	var backend := _offline()
	backend.publish_inputs()
	_as_session(Session.Role.HOST, 1)
	Session.local_name = "Ada"
	var s := DAW.state
	var ids: Array = s.inputs.map(func(p): return p[0])
	check("each device is offered both sides and each alone (%s)" % [ids.slice(0, 3)],
			ids.slice(0, 3) == ["audio:", "audio:#1", "audio:#2"])
	check("a track input names its device and side", GuestAudio.device_of("audio:Box#2") == "Box"
			and GuestAudio.channel_of("audio:Box#2") == 2 and GuestAudio.channel_of("audio:Box") == 0
			and GuestAudio.device_of("audio:") == "" and GuestAudio.device_of("audio:#1") == "")
	var order: Array = s.track_indices().filter(func(i): return s.track(i).folder_depth <= 0)
	for i in s.track_indices():
		s.track(i).rec_arm = false
	var guitar: int = order[0]
	var voice: int = order[1]
	var room: int = order[2]
	var elsewhere: int = order[3]
	var keys: int = order[4]
	var more_keys: int = order[5]
	for pair in [[guitar, "audio:#1"], [voice, "audio:#2"], [room, "audio:"], [elsewhere, "audio:Other#1"],
			[keys, "midi"], [more_keys, "midi"]]:
		s.track(pair[0]).rec_arm = true
		s.track(pair[0]).items.clear()
		DAW.set_track_input(pair[0], pair[1])
	var notices: Array[String] = []
	var hear := func(t: String): notices.append(t)
	Session.notice.connect(hear)
	var ha := Session.host_audio
	ha.target_track = 0
	ha.record_with_host = true
	var mic := _FakeMic.new()
	mic.sides = Vector2(0.9, 0.3)
	ha._source = mic
	check("the microphone's take leads on the first armed track (%d)" % ha.take_track(), ha.take_track() == guitar and ha.armed())
	for tick in 200:
		var got := ha._read()
		ha.follow({"seconds": 10.0 + float(mic.made) / 48000.0, "playing": true, "recording": tick < 199, "valid": true}, got)
	var loudest := func(index: int) -> float:
		var items: Array = s.track(index).items
		if items.size() != 1:
			return -1.0
		var read := DawKitAudioFile.read(ProjectSettings.globalize_path(AudioTake.DIR.path_join(items[0].source)))
		var peak := 0.0
		for v in (read["samples"] as PackedFloat32Array):
			peak = maxf(peak, absf(v))
		return peak
	var peaks := [loudest.call(guitar), loudest.call(voice), loudest.call(room)]
	check("one recording lands on every armed track of the device (%s)" % [peaks], peaks.min() > 0.0)
	close_to("input 1 alone on the first", peaks[0], 0.9, 0.001)
	close_to("input 2 alone on the second", peaks[1], 0.3, 0.001)
	close_to("both, averaged, on the one that takes the device whole", peaks[2], 0.6, 0.001)
	if peaks.min() > 0.0:
		close_to("all from the same moment", s.track(voice).items[0].start, s.track(guitar).items[0].start, 0.00001)
		check("each its own file", s.track(voice).items[0].source != s.track(guitar).items[0].source)
	check("not the track on another device, nor the keys' (%d, %d)" % [s.track(elsewhere).items.size(), s.track(keys).items.size()],
			s.track(elsewhere).items.is_empty() and s.track(keys).items.is_empty())
	var said := notices.filter(func(t): return t.begins_with("Not recorded on"))
	check("and the host is told why the other device's track was left out (%s)" % [said],
			said.size() == 1 and said[0].contains(s.track(elsewhere).display_name()) and said[0].contains("one input device"))
	for index in [guitar, voice, room]:
		for item in s.track(index).items:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(AudioTake.DIR.path_join(item.source)))
		s.track(index).items.clear()
	ha.record_with_host = false
	ha._source = null

	# The keys onto every armed track that takes them.
	var gm := Session.guest_midi
	gm.target_track = 0
	gm.record_with_host = true
	check("the keys lead on the first armed track that does not take a microphone (%d)" % gm.take_track(), gm.take_track() == keys)
	gm.follow({"seconds": 20.0, "playing": true, "recording": true, "valid": true})
	gm.note_on(60, 100)
	gm.follow({"seconds": 20.5, "playing": true, "recording": true, "valid": true})
	gm.note_off(60)
	gm.follow({"seconds": 21.0, "playing": true, "recording": false, "valid": true})
	check("and one take of them lands on each (%d, %d, %s)" % [s.track(keys).items.size(), s.track(more_keys).items.size(), gm.last_take.get("tracks")],
			s.track(keys).items.size() == 1 and s.track(more_keys).items.size() == 1
			and s.track(guitar).items.is_empty())
	gm.record_with_host = false
	# As GuestMidi._process does once the keys no longer play: the next test starts them afresh.
	gm._host_synth = false
	gm.synth.set_bus(&"")
	gm.synth.stop()
	Session.notice.disconnect(hear)
	Session.start_solo()
	_offline()


func _test_the_host_records_its_own_keys_on_the_built_in_engine() -> void:
	_offline()
	_as_session(Session.Role.HOST, 1)
	Session.local_name = "Ada"
	var gm := Session.guest_midi
	gm.target_track = 0
	gm.record_with_host = true
	check("a host on the built-in engine plays its own keys", gm.plays() and gm.host_records())
	var armed := HitRecorder.armed_track()
	check("onto the armed track when none is chosen", gm.take_track() == armed and armed > 0)
	var engine := GodotBackend.new()
	engine.state = DAW.state
	add_child(engine)
	engine._build_buses()
	var stand_in := DAW.backend
	DAW.backend = engine
	gm._hear_host_keys()
	check("heard through that track, as the engine monitors it (%s)" % gm.synth.bus,
			gm.through_track and gm.synth.bus != &"" and gm.synth.bus == engine.monitor_bus(armed) and not gm.synth.allow_native)
	gm.target_track = armed + 1
	gm._process(0.016)
	check("and through another, chosen", gm.synth.bus == engine.monitor_bus(armed + 1))
	gm.target_track = 0
	gm.through_track = false
	check("or, asked, straight out, as soon as they can be (%s)" % gm.synth.bus,
			gm.synth.bus == &"" and gm.synth.allow_native == (OS.get_environment("R3D_GODOT_KEYS") != "1"))
	gm.through_track = true
	DAW.backend = stand_in
	var monitor := MonitorSynth.new()
	monitor.note_on(60, 100)
	var tine := DawKitTine.new(MonitorSynth.RATE)
	tine.note_on(60, 100)
	check("what a player hears of their keys is the engine's own instrument, sample for sample",
			monitor.render(2400) == tine.render(2400))
	monitor.free()
	engine._remove_buses()
	remove_child(engine)
	engine.free()
	DAW.state.track(armed).items.clear()
	var s := DAW.state
	s.position_seconds = 30.0
	s.playing = true
	s.recording = true
	gm._process(0.016)
	check("a take begins when the host records", gm.is_recording())
	var late := AudioServer.get_output_latency() - (gm.synth.latency_seconds() if gm.monitor and gm.synth.is_running() else 0.0)
	s.position_seconds = 31.0
	gm.note_on(60, 100)
	gm._process(0.016)
	s.position_seconds = 31.5
	gm.note_off(60)
	gm._process(0.016)
	s.recording = false
	s.playing = false
	gm._process(0.016)
	var items: Array = s.track(armed).items
	check("stopped, the take is on the armed track (%d)" % items.size(), items.size() == 1 and not gm.is_recording())
	if items.size() == 1:
		var it: MixState.ItemState = items[0]
		check("with its note (%d)" % (it.notes.size() / 5), it.notes.size() == 5)
		if it.notes.size() == 5:
			close_to("on the song second the host heard, less the output's lateness",
					it.start + it.notes[0], 31.0 - late, 0.0001)
			close_to("and let go half a second later", it.notes[1] - it.notes[0], 0.5, 0.0001)
	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	DAW.use(reaper)
	check("where the DAW records its own inputs, the host's keys are its business", not gm.host_records()
			and not gm.plays())
	gm._process(0.016)
	Session.start_solo()
	_offline()
	if is_instance_valid(reaper):
		reaper.queue_free()


## THE GAP THIS EXISTS FOR (docs/loop_backlog.md, "Known rough edges": "Keytar: on a host, a
## MIDI keyboard still goes to Reaper rather than through the keytar (GuestMidi opens MIDI only
## from the guest's panel)"). A keytar in hand plays through GuestMidi regardless of whether the
## DAW records its own MIDI input -- `plays()` says "anyone's with a keytar" -- but the panel
## that lets a player choose where its notes land (`_place_mic`'s `_keys_box`) was hidden whenever
## `host_records()` was false, the same test that correctly hides it for ordinary ambient MIDI
## input on a host whose Reaper already takes that itself. The keytar is not that ambient input:
## it is this panel's own `target_track`, and had no way back to it.
func _test_a_keytar_reaches_its_track_choice_even_where_reaper_records_its_own_midi() -> void:
	_offline()
	_as_session(Session.Role.HOST, 1)
	Session.local_name = "Ada"
	var gm := Session.guest_midi
	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	DAW.use(reaper)
	var panel := SessionPanel.new()
	add_child(panel)
	panel.open()
	check("hidden for an ordinary host on Reaper, same as before", not panel._keys_box.visible)
	gm.keytar = true
	check("but back once a keytar is in hand, in the host's own section",
			panel._keys_box.visible and panel._keys_box.get_parent() == panel._column)
	gm.target_track = 0
	panel._refresh_midi()
	check("unset still reads as the armed track, not nowhere, matching take_track()'s own fallback",
			panel._play_into.get_item_text(panel._play_into.get_item_index(0)) == "The armed track")
	gm.keytar = false
	check("and hidden again once it is put down", not panel._keys_box.visible)
	remove_child(panel)
	panel.free()
	Session.start_solo()
	_offline()
	if is_instance_valid(reaper):
		reaper.queue_free()


## `roll_every`, Tour's one opt-in change to either recorder (core/items/hit_recorder.gd,
## core/session/guest_midi.gd): 0.0, the default, behaves exactly as before -- a take runs the
## whole time recording does, and is sent only when it stops. Set past 0.0, the running take is
## sent and a fresh one begun once the song has moved on that far, and also when it steps
## sharply backward -- the loop's wrap -- so a part can be judged while the brief is still going,
## not only once it ends.
func _test_hit_recorder_rolls_takes_every_bar() -> void:
	var backend := _offline()
	_as_session(Session.Role.HOST, 1)
	Session.local_name = "Ada"
	DAW.state.track(1).rec_arm = true
	DAW.state.track(1).items.clear()
	var rec := HitRecorder.new()
	var heard := {"seconds": 20.0, "playing": true, "recording": true, "valid": true}
	rec.heard_source = func() -> Dictionary: return heard

	# roll_every == 0.0, the default: the running take is left alone until recording stops.
	rec.follow(heard)
	rec._take.note_on(60, 100, HitRecorder.CHANNEL, 20.0)
	rec._take.note_off(60, HitRecorder.CHANNEL, 20.05)
	heard["seconds"] = 25.0
	rec.follow(heard)
	check("roll_every 0 never rolls mid-recording", rec.takes_sent == 0 and rec.is_recording())
	heard["recording"] = false
	rec.follow(heard)
	check("recording stopping sends the one take (%d)" % rec.takes_sent, rec.takes_sent == 1)
	DAW.state.track(1).items.clear()

	# roll_every == 2.0 (a bar, say): the running take is sent and a fresh one begun once the
	# song has moved on that far, and again when it steps sharply backward (the loop's wrap).
	rec.takes_sent = 0
	rec.roll_every = 2.0
	heard["recording"] = true
	heard["seconds"] = 20.0
	rec.follow(heard)
	rec._take.note_on(60, 100, HitRecorder.CHANNEL, 20.0)
	rec._take.note_off(60, HitRecorder.CHANNEL, 20.05)
	var first_take := rec._take
	heard["seconds"] = 22.1
	rec.follow(heard)
	check("past roll_every, the running take is sent and a fresh one begins (%d)" % rec.takes_sent,
			rec.takes_sent == 1 and rec.is_recording() and rec._take != first_take)
	var second_take := rec._take
	rec._take.note_on(62, 100, HitRecorder.CHANNEL, 22.1)
	rec._take.note_off(62, HitRecorder.CHANNEL, 22.15)
	heard["seconds"] = 23.0
	rec.follow(heard)
	check("not yet two seconds into the new one, it still runs",
			rec.takes_sent == 1 and rec._take == second_take)
	heard["seconds"] = 0.2 # the song wrapped its loop
	rec.follow(heard)
	check("stepping back past the loop's wrap rolls the take too (%d)" % rec.takes_sent,
			rec.takes_sent == 2 and rec.is_recording() and rec._take != second_take)
	rec._take.note_on(64, 100, HitRecorder.CHANNEL, 0.2)
	rec._take.note_off(64, HitRecorder.CHANNEL, 0.25)
	heard["recording"] = false
	rec.follow(heard)
	check("and stopping sends the last one (%d)" % rec.takes_sent, rec.takes_sent == 3)

	DAW.state.track(1).items.clear()
	Session.start_solo()
	_offline()


func _test_a_looped_item_survives_the_wire_and_a_split() -> void:
	var item := MixState.ItemState.new()
	item.start = 10.0
	item.length = 8.0
	item.source = "demo_drums.wav"
	item.source_offset = 1.0
	item.loop_start = 0.0
	item.loop_end = 2.0
	var back: MixState.ItemState = MixWire._unpack_items(MixWire._pack_items([item]))[0]
	check("a loop crosses the wire", back.loop_start == 0.0 and back.loop_end == 2.0)
	close_to("and plays round it", back.file_time(11.5), 0.5)
	_offline()
	DAW.state.set_track_items(3, [item])
	DAW.select_item(3, 0)
	DAW.split_selected(13.0)
	var halves: Array = DAW.state.track(3).items
	check("both halves of a split loop keep the loop", halves.size() == 2
			and halves[0].is_looped() and halves[1].is_looped())
	close_to("and the right half plays on from where the left stopped",
			halves[1].file_time(13.0), item.file_time(13.0))


func _test_a_clip_keeps_its_fades_and_gain() -> void:
	var item := MixState.ItemState.new()
	item.start = 4.0
	item.length = 2.0
	item.fade_in = 0.05
	item.fade_out = 0.5
	item.gain_db = -3.0
	var back: MixState.ItemState = MixWire._unpack_items(MixWire._pack_items([item]))[0]
	check("fades and gain cross the wire", back.fade_in == 0.05 and back.fade_out == 0.5 and back.gain_db == -3.0)
	var plain := MixState.ItemState.new()
	plain.length = 1.0
	check("an item without them costs what it did", MixWire._pack_items([plain]).size() == 5)
	_offline()
	DAW.state.set_track_items(2, [item])
	DAW.select_item(2, 0)
	DAW.split_selected(5.0)
	var halves: Array = DAW.state.track(2).items
	check("a split keeps the fade in on the left and the fade out on the right",
			halves.size() == 2 and halves[0].fade_in == 0.05 and halves[0].fade_out == 0.0
			and halves[1].fade_in == 0.0 and halves[1].fade_out == 0.5)
	check("and both halves keep the gain", halves[0].gain_db == -3.0 and halves[1].gain_db == -3.0)


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
	# Post-effects: the guitar's send carries its drive and delay, the same objects as its rack.
	DAW.create_send(8, 13)
	var slot := -1
	for k in s.track(8).sends:
		if s.track(8).sends[k].dest_track == 13 and not s.track(8).sends[k].key:
			slot = k
	var sb := AudioServer.get_bus_index(GodotBackend.send_bus(8, 13))
	var tb: int = bus.call(8)
	check("a send patched while playing gets its own bus at once", slot > 0 and sb >= 0
			and backend._players[8].any(func(p): return p.has_meta(&"send") and p.bus == GodotBackend.send_bus(8, 13)))
	check("which runs the track's own effects, after its pan, before the send's (%d)" % AudioServer.get_bus_effect_count(sb),
			AudioServer.get_bus_effect_count(sb) == AudioServer.get_bus_effect_count(tb) + 1
			and range(1, AudioServer.get_bus_effect_count(tb)).all(func(i):
				return AudioServer.get_bus_effect(sb, i) == AudioServer.get_bus_effect(tb, i))
			and AudioServer.get_bus_effect(sb, 0) is AudioEffectPanner
			and AudioServer.get_bus_effect(sb, AudioServer.get_bus_effect_count(sb) - 1) is AudioEffectPanner)
	DAW.set_fx_enabled(8, 0, false)
	check("a bypass reaches the send's copy", not AudioServer.is_bus_effect_enabled(sb, 1))
	DAW.set_fx_enabled(8, 0, true)
	DAW.set_send_pan(8, slot, 0.0)
	DAW.set_track_pan(8, 0.75)
	close_to("the send has its own pan", (AudioServer.get_bus_effect(sb, AudioServer.get_bus_effect_count(sb) - 1) as AudioEffectPanner).pan, -1.0)
	close_to("on top of the track's", (AudioServer.get_bus_effect(sb, 0) as AudioEffectPanner).pan, 0.5)
	DAW.remove_send(8, slot)
	check("and pulled, its bus and player go", AudioServer.get_bus_index(GodotBackend.send_bus(8, 13)) < 0
			and not backend._players[8].any(func(p): return p.has_meta(&"send") and not p.is_queued_for_deletion()))
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
	var stand_in := _offline()
	var sk := stand_in.state
	var kick_track := sk.track_indices().filter(func(i): return sk.track(i).name == "Kick")[0] as int
	check("the stand-in's tracks are given their parts as it is made", sk.track(kick_track).part == "kick"
			and sk.track(1).part == "")
	DAW.rename_track(kick_track, "Boom")
	DAW.add_track(1, "New")
	check("and keep them renamed and moved (%s)" % sk.track(kick_track + 1).part,
			sk.track(kick_track + 1).name == "Boom" and sk.track(kick_track + 1).part == "kick"
			and sk.track(1).part == "")
	DAW.undo()
	DAW.undo()
	var kick := DemoSong.render("kick", 120.0)
	check("a part is exactly four bars (%d)" % kick.size(), kick.size() == 8 * DemoSong.RATE)
	var top := 0.0
	for v in kick:
		top = maxf(top, absf(v))
	# Brought to 0.8, then to its place in the mix (DemoSong.LEVEL_DB and TRIM_DB).
	close_to("and normalised, then trimmed", top, 0.8 * DemoSong._trim("kick"), 0.001)
	var first := 0.0
	for i in 200:
		first = maxf(first, absf(kick[i]))
	check("the kick lands on the one", first > 0.3 * DemoSong._trim("kick"))
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


func _test_a_recording_counts_in() -> void:
	var backend := _offline()
	var s := DAW.state
	var bar := 4.0 * 60.0 / s.tempo
	check("no count-in to start with", s.count_in_bars == 0)
	DAW.seek(10.0)
	DAW.transport_record()
	backend._process(0.0)
	check("without one, recording takes at once", s.taking() and not s.counting_in())
	close_to("from where the playhead stood", s.position_seconds, 10.0)
	DAW.transport_stop()

	backend._repl_durable.clear()
	DAW.set_count_in(2)
	check("set_count_in sets the bars", s.count_in_bars == 2)
	check("and replicates them as /countin", backend._repl_durable.get("/countin", []) == [2.0])
	DAW.seek(10.0)
	DAW.transport_record()
	backend._process(0.0)
	check("with the click off there is no count, as in Reaper", s.taking())
	DAW.transport_stop()

	DAW.set_metronome(true)
	DAW.seek(10.0)
	DAW.transport_record()
	check("with the click on, recording counts in", s.counting_in() and not s.taking())
	check("the rec state is said at once, as Reaper says it", s.recording and s.playing)
	close_to("to where the playhead stood", s.count_in_to, 10.0)
	close_to("from two bars before it", s.position_seconds, 10.0 - 2.0 * bar)
	check("a guest is told where the take begins", backend._repl_durable.get("/countin/to", []) == [10.0])
	check("and the host's own takes wait for it", not Session.host_heard()["recording"])
	backend._process(bar)
	check("a bar in it is still counting", s.counting_in())
	backend._process(bar + 0.01)
	check("two bars in, the take has begun", s.taking() and not s.counting_in())
	var told := MixState.new()
	for pair in MixWire.snapshot(s):
		MixWire.apply(told, pair[0], pair[1])
	check("which a guest is told", told.taking())
	check("and the host's own takes begin", Session.host_heard()["recording"])
	DAW.transport_stop()

	DAW.seek(10.0)
	DAW.transport_record()
	backend._process(0.5)
	DAW.transport_stop()
	check("stopped while counting, nothing is counting", not s.counting_in() and s.count_in_to < 0.0)
	close_to("and the playhead is back where it stood", s.position_seconds, 10.0)

	DAW.seek(0.0)
	DAW.transport_record()
	close_to("from the top of the song it counts in from before it", s.position_seconds, -2.0 * bar)
	DAW.transport_stop()
	DAW.set_tempo_map([[0.0, 120.0, 0], [8.0, 60.0, 0]])
	DAW.seek(s.tempo_map().seconds_at(12.0))
	DAW.transport_record()
	close_to("across a tempo change it counts the beats of the map", s.position_seconds,
			s.tempo_map().seconds_at(4.0))
	DAW.transport_stop()
	DAW.set_tempo_map([])

	check("a verb a guest may use", &"set_count_in" in DAW.COMMANDS)
	DAW.apply_intent(&"set_count_in", [99])
	check("a guest's intent is held to the longest count", s.count_in_bars == MixState.COUNT_IN_MAX)
	DAW.apply_intent(&"set_count_in", ["two"])
	DAW.apply_intent(&"set_count_in", [])
	check("and a malformed one refused", s.count_in_bars == MixState.COUNT_IN_MAX)
	DAW.set_count_in(1)
	DAW.seek(10.0)
	DAW.transport_record()
	var guest := MixState.new()
	for pair in MixWire.snapshot(s):
		MixWire.apply(guest, pair[0], pair[1])
	check("a joining guest is told the count and that it is counting", guest.count_in_bars == 1
			and guest.counting_in() and not guest.taking())
	DAW.transport_stop()

	# Reaper counts in itself, saying it records all the while: the backend tells the count from
	# the take by where the transport stood.
	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	add_child(reaper)
	var r := reaper.state
	reaper._apply("/click", [1.0])
	reaper._on_timeline({"count_in": 2})
	check("Reaper's count-in is read from its project", r.count_in_bars == 2)
	reaper._apply("/time", [10.0])
	reaper.follow_count_in()
	reaper._apply("/record", [1.0])
	reaper._apply("/play", [1.0])
	reaper.follow_count_in()
	check("Reaper recording from a standstill is counting in", r.counting_in())
	close_to("to where it stood", r.count_in_to, 10.0)
	reaper.follow_count_in()
	check("still, until its playhead reaches the record point", r.counting_in())
	reaper._apply("/time", [6.0])
	reaper.follow_count_in()
	reaper._apply("/time", [10.02])
	reaper.follow_count_in()
	check("and taking once it reaches the record point", r.taking())
	reaper._apply("/record", [0.0])
	reaper._apply("/play", [0.0])
	reaper.follow_count_in()
	reaper._apply("/record", [1.0])
	reaper._apply("/play", [1.0])
	reaper.follow_count_in()
	check("its playhead is put back where Reaper is about to say it is (%.2f)" % r.position_seconds,
			r.counting_in() and r.position_seconds < 10.0)
	reaper._apply("/time", [10.05])
	reaper.follow_count_in()
	check("a playhead Reaper says is past the record point means it did not count in", r.taking())
	reaper._apply("/click", [0.0])
	reaper._apply("/record", [0.0])
	reaper._apply("/play", [0.0])
	reaper.follow_count_in()
	reaper._apply("/record", [1.0])
	reaper._apply("/play", [1.0])
	reaper.follow_count_in()
	check("nor does it with the click off", r.taking())
	reaper.free()

	DAW.set_count_in(0)
	var deck := TapeDeck.new()
	add_child(deck)
	deck._process(0.0)
	check("the COUNT lamp is dark with no count-in", not deck._count_lamp.lit)
	var seen: Array = []
	for i in 4:
		deck._count_lamp.pressed.emit()
		seen.append(DAW.state.count_in_bars)
	check("COUNT steps 1, 2, 4 bars and off (%s)" % [seen], seen == [1, 2, 4, 0])
	deck._count_lamp.pressed.emit()
	deck._process(0.0)
	check("and lights while there is one", deck._count_lamp.lit)
	check("it says what it does (%s)" % TapeDeck.count_in_text(DAW.state),
			TapeDeck.count_in_text(DAW.state).begins_with("1 bar of click"))

	# Before playback too: Reaper's "Count-in before playback".
	var finger := FakeHand.new()
	add_child(finger)
	finger.holding_shift = true
	deck._count_lamp.grab_begin(finger, deck._count_lamp.global_position)
	deck._count_lamp.grab_end(finger)
	finger.holding_shift = false
	check("a fine press on COUNT counts in before playback too (%s)" % TapeDeck.count_in_text(DAW.state),
			DAW.state.count_in_play and DAW.state.count_in_bars == 1
			and TapeDeck.count_in_text(DAW.state).contains("and playback"))
	check("and replicates it", backend._repl_durable.get("/countin/play", []) == [1.0])
	var bar_now := 4.0 * 60.0 / s.tempo
	DAW.seek(20.0)
	DAW.transport_play()
	check("playing from a standstill then counts in, not recording", s.counting_in() and not s.recording)
	close_to("from a bar before where it stood", s.position_seconds, 20.0 - bar_now)
	backend._process(bar_now + 0.01)
	check("and the song plays from where it stood", not s.counting_in() and s.position_seconds >= 20.0)
	DAW.transport_stop()
	DAW.seek(20.0)
	DAW.transport_play()
	DAW.transport_stop()
	close_to("stopped while counting, back where it stood", s.position_seconds, 20.0)
	var heard := MixState.new()
	for pair in MixWire.snapshot(s):
		MixWire.apply(heard, pair[0], pair[1])
	check("a guest is told", heard.count_in_play)
	check("a verb a guest may use", &"set_count_in_play" in DAW.COMMANDS)
	DAW.apply_intent(&"set_count_in_play", [false])
	check("which turns it off", not s.count_in_play)
	# Pre-roll: the song under the count.
	check("a fine press steps neither, playback, playback with the song, the song (%s)" % [[
			TapeDeck.next_count_mode(false, false), TapeDeck.next_count_mode(true, false),
			TapeDeck.next_count_mode(true, true), TapeDeck.next_count_mode(false, true)]],
			TapeDeck.next_count_mode(false, false) == Vector2i(1, 0) and TapeDeck.next_count_mode(true, false) == Vector2i(1, 1)
			and TapeDeck.next_count_mode(true, true) == Vector2i(0, 1) and TapeDeck.next_count_mode(false, true) == Vector2i(0, 0))
	DAW.apply_intent(&"set_pre_roll", [1])
	check("a guest may turn pre-roll on", s.pre_roll and &"set_pre_roll" in DAW.COMMANDS)
	check("and it says so (%s)" % TapeDeck.count_in_text(s), TapeDeck.count_in_text(s).contains("and the song"))
	DAW.apply_intent(&"set_pre_roll", [])
	check("a malformed one is refused", s.pre_roll)
	DAW.seek(20.0)
	DAW.transport_record()
	check("recording counts in with the song playing under it", s.counting_in() and not s.song_held())
	DAW.transport_stop()
	heard = MixState.new()
	for pair in MixWire.snapshot(s):
		MixWire.apply(heard, pair[0], pair[1])
	check("a guest is told of pre-roll", heard.pre_roll)
	DAW.set_pre_roll(false)
	DAW.seek(20.0)
	DAW.transport_record()
	check("without it, the song is held while counting", s.song_held())
	DAW.transport_stop()
	DAW.set_count_in(0)
	DAW.set_count_in_play(true)
	DAW.seek(20.0)
	DAW.transport_play()
	check("with no bars to count, playing starts at once", not s.counting_in())
	DAW.transport_stop()
	DAW.set_count_in_play(false)
	finger.queue_free()
	var reaper_play := ReaperBackend.new()
	reaper_play.state = MixState.new()
	add_child(reaper_play)
	var rp := reaper_play.state
	reaper_play._apply("/click", [1.0])
	reaper_play._on_timeline({"count_in": 1, "count_in_play": true})
	check("Reaper's count before playback is read from its project", rp.count_in_play)
	reaper_play._on_timeline({"count_in": 1, "count_in_play": true, "pre_roll": true})
	check("and its pre-roll", rp.pre_roll)
	reaper_play._on_timeline({"count_in": 1, "count_in_play": true, "pre_roll": false})
	reaper_play._apply("/time", [10.0])
	reaper_play.follow_count_in()
	reaper_play._apply("/play", [1.0])
	reaper_play.follow_count_in()
	check("and playing from a standstill there counts in too", rp.counting_in() and not rp.recording)
	reaper_play.free()
	deck.queue_free()
	DAW.set_count_in(0)
	DAW.set_metronome(false)


func _test_a_recording_punches_in_and_out() -> void:
	var backend := _offline()
	var s := DAW.state
	check("no punching to start with", not s.punch)
	backend._repl_durable.clear()
	DAW.set_punch(true)
	check("set_punch turns it on", s.punch)
	check("and replicates it as /punch", backend._repl_durable.get("/punch", []) == [1.0])
	DAW.set_loop_range(0.0, 0.0)
	DAW.seek(5.0)
	DAW.transport_record()
	check("with no loop range, recording takes all it plays", s.taking())
	DAW.transport_stop()
	DAW.set_loop_range(10.0, 12.0)
	DAW.seek(8.0)
	DAW.transport_record()
	check("before the range it records but does not take", s.recording and s.playing and not s.taking())
	check("so the host's own takes wait", not Session.host_heard()["recording"])
	backend._process(2.01)
	check("in the range it takes", s.taking() and Session.host_heard()["recording"])
	var guest := MixState.new()
	for pair in MixWire.snapshot(s):
		MixWire.apply(guest, pair[0], pair[1])
	check("which a joining guest is told", guest.punch and guest.taking())
	backend._process(2.0)
	check("past it, it stops taking and goes on playing", not s.taking() and s.recording and s.playing)
	DAW.transport_stop()
	DAW.set_count_in(1)
	DAW.set_metronome(true)
	DAW.seek(10.0)
	DAW.transport_record()
	check("a count-in to the range's start is counted before it takes", s.counting_in() and not s.taking())
	backend._process(4.0 * 60.0 / s.tempo + 0.01)
	check("and takes from the range's start", s.taking())
	DAW.transport_stop()
	DAW.set_count_in(0)
	DAW.set_metronome(false)

	check("a verb a guest may use", &"set_punch" in DAW.COMMANDS)
	DAW.apply_intent(&"set_punch", [0.0])
	check("a guest's intent switches it off", not s.punch)
	DAW.apply_intent(&"set_punch", [])
	check("and an empty one is refused", not s.punch)

	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	add_child(reaper)
	reaper._on_timeline({"punch": true})
	check("Reaper's record mode is read from it", reaper.state.punch)
	reaper._on_timeline({"punch": false})
	check("both ways", not reaper.state.punch)
	reaper.free()

	var deck := TapeDeck.new()
	add_child(deck)
	deck._process(0.0)
	check("the PUNCH lamp is dark while not punching", not deck._punch_lamp.lit)
	deck._punch_lamp.pressed.emit()
	deck._process(0.0)
	check("pressing PUNCH punches, and lights it", DAW.state.punch and deck._punch_lamp.lit)
	check("it says what it takes (%s)" % TapeDeck.punch_text(DAW.state),
			TapeDeck.punch_text(DAW.state).begins_with("recording takes only"))
	deck.queue_free()
	DAW.set_punch(false)
	DAW.set_loop_range(0.0, 0.0)


func _test_a_track_records_from_its_own_input() -> void:
	var backend := _offline()
	backend.publish_inputs()
	var s := DAW.state
	var ids: Array = s.inputs.map(func(p): return p[0])
	check("the built-in engine offers the default microphone, each device and the keys (%s)" % [ids],
			ids[0] == "audio:" and ids[-1] == "midi")
	check("and no track has chosen one", s.input_of(2) == "")
	backend._repl_durable.clear()
	DAW.set_track_input(2, "midi")
	check("set_track_input chooses one", s.input_of(2) == "midi" and s.input_name(s.input_of(2)) == "the keys")
	check("and replicates it", backend._repl_durable.get("/track/2/input", []) == ["midi"])
	DAW.undo()
	check("it is undoable", s.input_of(2) == "")
	DAW.redo()
	check("and redoable", s.input_of(2) == "midi")
	check("a verb a guest may use", &"set_track_input" in DAW.COMMANDS)
	DAW.apply_intent(&"set_track_input", [3, "audio:"])
	check("a guest's intent chooses one", s.input_of(3) == "audio:")
	DAW.apply_intent(&"set_track_input", [3, "audio:Nothing here"])
	DAW.apply_intent(&"set_track_input", [0, "midi"])
	DAW.apply_intent(&"set_track_input", [3])
	check("and one this DAW does not offer, or for no track, is refused", s.input_of(3) == "audio:")
	var guest := MixState.new()
	for pair in MixWire.snapshot(s):
		MixWire.apply(guest, pair[0], pair[1])
	check("a joining guest is told each track's input and the inputs there are",
			guest.input_of(2) == "midi" and guest.input_of(3) == "audio:" and guest.inputs == s.inputs)

	# Saved with the project, through a DAWproject file.
	var file := OS.get_temp_dir().path_join("dawlings_inputs_test.dawproject")
	var problems := DawKitDawproject.save(ProjectBridge.capture(backend), file)
	var opened := DawKitDawproject.open(file)
	DirAccess.remove_absolute(file)
	check("the project saves (%s)" % [problems], problems.is_empty() and opened["project"] != null)
	if opened["project"] != null:
		DAW.set_track_input(2, "")
		DAW.set_track_input(3, "")
		ProjectBridge.load(opened["project"], backend)
		check("and opened again, each track records from what it did (%s, %s)" % [s.input_of(2), s.input_of(3)],
				s.input_of(2) == "midi" and s.input_of(3) == "audio:")

	# The host's own recorders go by it.
	_as_session(Session.Role.HOST, 1)
	var ha := Session.host_audio
	ha.input_device = "Chosen in the panel"
	ha.record_with_host = true
	ha.target_track = 2
	check("the host's microphone does not record onto a track that takes the keys", not ha.armed())
	ha.target_track = 3
	check("it records onto one that takes the default microphone", ha.armed() and ha.device() == "")
	DAW.set_track_input(3, "audio:Interface")
	check("from the device the track names (%s)" % ha.device(), ha.device() == "Interface")
	DAW.set_track_input(3, "")
	check("and with none named, from the panel's", ha.device() == "Chosen in the panel")
	ha.record_with_host = false
	ha.target_track = 0
	ha.input_device = ""
	var gm := Session.guest_midi
	gm.target_track = 3
	gm.record_with_host = true
	DAW.set_track_input(3, "audio:")
	gm.follow({"seconds": 4.0, "playing": true, "recording": true, "valid": true})
	check("the host's keys do not go onto a track that takes a microphone", not gm.is_recording())
	DAW.set_track_input(3, "midi")
	gm.follow({"seconds": 4.0, "playing": true, "recording": true, "valid": true})
	check("but onto one that takes the keys", gm.is_recording())
	gm.follow({"seconds": 4.5, "playing": true, "recording": false, "valid": true})
	gm.record_with_host = false
	gm.target_track = 0
	Session.start_solo()

	# Reaper's I_RECINPUT, both ways.
	check("Reaper's input codes are named (%s)" % [[ReaperBackend.input_id(-1), ReaperBackend.input_id(0),
			ReaperBackend.input_id(1024 | 2), ReaperBackend.input_id(ReaperBackend.INPUT_ALL_MIDI), ReaperBackend.input_id(512)]],
			ReaperBackend.input_id(-1) == "none" and ReaperBackend.input_id(0) == "in:1"
			and ReaperBackend.input_id(1024 | 2) == "in:3/4" and ReaperBackend.input_id(ReaperBackend.INPUT_ALL_MIDI) == "midi"
			and ReaperBackend.input_id(512) == "reaper:512")
	var round_trips := true
	for code in [-1, 0, 7, 1024, 1024 | 5, ReaperBackend.INPUT_ALL_MIDI, 4096 | (1 << 5) | 3, 512]:
		round_trips = round_trips and ReaperBackend.input_code(ReaperBackend.input_id(code)) == code
	check("and every one comes back as itself", round_trips)
	check("and nonsense is not one", ReaperBackend.input_code("in:3/7") == ReaperBackend.INPUT_UNKNOWN
			and ReaperBackend.input_code("") == ReaperBackend.INPUT_UNKNOWN)
	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	add_child(reaper)
	reaper.state.track(1)
	reaper.state.track(2)
	reaper._on_timeline({"inputs": [1024, ReaperBackend.INPUT_ALL_MIDI], "audio_inputs": 2})
	check("Reaper's tracks' inputs are read from it", reaper.state.input_of(1) == "in:1/2"
			and reaper.state.input_of(2) == "midi")
	check("and what there is to choose (%s)" % [reaper.state.inputs], reaper.state.inputs.map(func(p): return p[0])
			== ["none", "in:1", "in:2", "in:1/2", "midi"])
	reaper.free()

	_offline()
	DAW.backend.publish_inputs()
	var timeline := TimelineSurface.new()
	add_child(timeline)
	var strip: TimelineTrackStrip = timeline._track_controls
	timeline.pick_track(2)
	strip.refresh()
	check("IN is dark for a track that has not chosen", not strip.input.lit)
	var seen: Array = []
	for i in DAW.state.inputs.size() + 1:
		strip.input.pressed.emit()
		seen.append(DAW.state.input_of(2))
	check("IN steps the picked track through every input and back to none (%s)" % [seen],
			seen.slice(0, -1) == DAW.state.inputs.map(func(p): return p[0]) and seen[-1] == "")
	strip.input.pressed.emit()
	strip.refresh()
	check("and lights once it has", strip.input.lit)
	timeline.queue_free()


func _test_the_time_signature_changes() -> void:
	var backend := _offline()
	var s := DAW.state
	DAW.set_tempo(120.0)
	check("the song starts in 4/4", s.beats_per_bar == 4 and s.beat_unit == 4 and s.time_signature_points.is_empty())
	backend._repl_durable.clear()
	# 4/4 for two bars, then 6/8 from bar 3 (beat 8), then 4/4 from bar 5 (beat 14).
	DAW.set_time_signature_map([[0.0, 4, 4], [8.0, 6, 8], [14.0, 4, 4]])
	check("set_time_signature_map keeps the changes", s.time_signature_points.size() == 3)
	check("and replicates them", backend._repl_durable.get("/timesig/map", []).size() == 9)
	check("bar 3 is where the change is (%s)" % s.bar_beat(s.seconds_at_beat(8.0)), s.bar_beat(s.seconds_at_beat(8.0)) == "3.1.00")
	check("6/8 is counted in eighths (%s)" % s.bar_beat(s.seconds_at_beat(9.5)), s.bar_beat(s.seconds_at_beat(9.5)) == "3.4.00")
	check("and bar 4 starts three beats on (%s)" % s.bar_beat(s.seconds_at_beat(11.0)), s.bar_beat(s.seconds_at_beat(11.0)) == "4.1.00")
	check("4/4 again from bar 5 (%s)" % s.bar_beat(s.seconds_at_beat(15.0)), s.bar_beat(s.seconds_at_beat(15.0)) == "5.2.00")
	close_to("bar 5 is at its beat in seconds", s.bar_to_seconds(5.0), s.seconds_at_beat(14.0))
	close_to("a bar of 6/8 is three beats long", s.bar_to_seconds(4.0) - s.bar_to_seconds(3.0), 1.5)
	# next_bar_start reads the same two maps count_in_start does, the other way round: a touch
	# into 6/8's bar 4 rounds up to bar 5, still through the signature change.
	close_to("a touch into bar 4 asks for bar 5", s.next_bar_start(s.bar_to_seconds(4.0) + 0.1), s.bar_to_seconds(5.0))
	check("already sat on a bar's own first instant asks for nothing more (%.4f vs %.4f)" \
			% [s.next_bar_start(s.bar_to_seconds(3.0)), s.bar_to_seconds(3.0)],
			is_equal_approx(s.next_bar_start(s.bar_to_seconds(3.0)), s.bar_to_seconds(3.0)))
	DAW.set_count_in(1)
	DAW.set_metronome(true)
	close_to("a count-in of a bar into bar 4 is a bar of 6/8", s.count_in_start(s.bar_to_seconds(4.0)), s.bar_to_seconds(3.0))
	DAW.set_count_in(0)
	DAW.set_metronome(false)
	DAW.undo()
	check("the change is one undo step", s.time_signature_points.is_empty() and s.bar_beat(s.seconds_at_beat(8.0)) == "3.1.00"
			and s.bar_beat(s.seconds_at_beat(9.5)) == "3.2.50")
	DAW.redo()
	check("and redone", s.time_signature_points.size() == 3)
	var guest := MixState.new()
	for pair in MixWire.snapshot(s):
		MixWire.apply(guest, pair[0], pair[1])
	check("a joining guest counts the same bars", guest.bar_beat(guest.seconds_at_beat(15.0)) == "5.2.00")
	check("a verb a guest may use", &"set_time_signature_map" in DAW.COMMANDS)
	DAW.apply_intent(&"set_time_signature_map", [[0.0, 3.0, 4.0]])
	check("a guest's intent sets the song's signature", s.beats_per_bar == 3 and s.time_signature_points.is_empty())
	DAW.apply_intent(&"set_time_signature_map", [[1.0, 3.0, 4.0]])
	DAW.apply_intent(&"set_time_signature_map", [[0.0, 0.0, 4.0]])
	DAW.apply_intent(&"set_time_signature_map", [[0.0, 3.0, 4.0, 2.0, 5.0]])
	DAW.apply_intent(&"set_time_signature_map", [[]])
	check("and a malformed one is refused", s.beats_per_bar == 3)
	DAW.set_time_signature_map([[0.0, 6, 8], [6.0, 4, 4]])

	# Saved with the project, through a DAWproject file.
	var file := OS.get_temp_dir().path_join("dawlings_meter_test.dawproject")
	var problems := DawKitDawproject.save(ProjectBridge.capture(backend), file)
	var opened := DawKitDawproject.open(file)
	DirAccess.remove_absolute(file)
	DAW.set_time_signature_map([[0.0, 4, 4]])
	if opened["project"] != null:
		ProjectBridge.load(opened["project"], backend)
	check("and opened again, the song changes signature where it did (%s, %s/%d)" % [problems, s.time_signature_points, s.beat_unit],
			problems.is_empty() and s.time_signature_points == [[0.0, 6, 8], [6.0, 4, 4]] and s.beat_unit == 8)
	var engine := GodotBackend.new()
	engine.state = s
	check("the built-in engine's click counts the meter, not one bar of quarters", engine._click_windowed())
	engine.free()

	# SIG on the tempo strip, at the playhead's bar.
	DAW.set_time_signature_map([[0.0, 4, 4]])
	var timeline := TimelineSurface.new()
	add_child(timeline)
	var strip: TimelineTempoStrip = timeline._tempo_controls
	DAW.seek(s.bar_to_seconds(3.0) + 0.1)
	strip.signature.pressed.emit()
	check("SIG at bar 3 starts a change there, to 3/4 (%s)" % [s.time_signature_points],
			s.time_signature_points == [[0.0, 4, 4], [8.0, 3, 4]])
	strip.signature.pressed.emit()
	check("again, that change goes to 6/8 (%s)" % [s.time_signature_points], s.time_signature_points == [[0.0, 4, 4], [8.0, 6, 8]])
	for i in TimelineTempoStrip.SIGNATURES.size() - 2:
		strip.signature.pressed.emit()
	check("and round to 4/4, which is no change and goes (%s)" % [s.time_signature_points], s.time_signature_points.is_empty())
	DAW.seek(0.0)
	strip.signature.pressed.emit()
	check("at bar 1 it is the song's own signature (%d/%d)" % [s.beats_per_bar, s.beat_unit],
			s.beats_per_bar == 3 and s.beat_unit == 4 and s.time_signature_points.is_empty())
	timeline.queue_free()
	DAW.set_time_signature_map([[0.0, 4, 4]])

	# Reaper: its markers' signatures, and a marker that holds only a signature is no tempo change.
	var reaper := ReaperBackend.new()
	reaper.state = MixState.new()
	add_child(reaper)
	reaper._on_timeline({"timesig": [[0.0, 4, 4], [8.0, 7, 8]], "tempo": [[0.0, 120.0, false], [8.0, 120.0, false]]})
	check("Reaper's signatures are read from its markers (%s)" % [reaper.state.time_signature_points],
			reaper.state.time_signature_points == [[0.0, 4, 4], [8.0, 7, 8]])
	check("and its marker for one is not a change of tempo (%s)" % [reaper.state.tempo_points], reaper.state.tempo_points.is_empty())
	reaper._on_timeline({"timesig": [[0.0, 3, 4]]})
	check("one signature throughout is no map (%d/%d)" % [reaper.state.beats_per_bar, reaper.state.beat_unit],
			reaper.state.time_signature_points.is_empty() and reaper.state.beats_per_bar == 3)
	reaper.free()


func _test_the_demo_song_follows_the_tempo_map() -> void:
	# At one tempo, a window of a part is the part as it loops.
	var loop := DemoSong.render("kick", 120.0)
	var made := DemoSong.render_window("kick", [[0.0, 120.0, 0]], 1)
	var window: PackedFloat32Array = made[0]
	var lead := int(roundf(DemoSong.WINDOW_LEAD_BEATS * 0.5 * DemoSong.RATE))
	var worst := 0.0
	for i in loop.size():
		worst = maxf(worst, absf(window[lead + i] - loop[i]))
	close_to("a window starts its lead before its loop", made[1], 16.0 * 0.5 - DemoSong.WINDOW_LEAD_BEATS * 0.5)
	check("at one tempo, a window is the loop, sample for sample (%.6f)" % worst, worst < 0.0001)
	# Through a ramp, every kick is where the map puts its beat.
	var points := [[0.0, 120.0, DawKitTempoMap.RAMP_BEATS], [32.0, 60.0, DawKitTempoMap.HOLD]]
	var map := DawKitTempoMap.from_array(points)
	made = DemoSong.render_window("kick", points, 1)
	window = made[0]
	var hits: Array = []
	var misses: Array = []
	for bar in range(4, 12):
		for b in ([0.0, 2.5] if bar % 4 != 3 else [0.0, 2.5, 3.5]):
			var at := int((map.seconds_at(bar * 4.0 + b) - float(made[1])) * DemoSong.RATE)
			if at <= 1 or at >= window.size():
				continue
			hits.append(at)
			# The kick's click is a step of its own: on this sample and not the one before, over
			# whatever the last kick still rings.
			if absf(window[at] - window[at - 1]) < 0.05 or absf(window[at - 1] - window[at - 2]) > 0.05:
				misses.append(bar * 4.0 + b)
	check("through a ramp, each kick starts on its beat's sample (%d hits, off at %s)" % [hits.size(), misses],
			hits.size() >= 15 and misses.is_empty())
	close_to("and the window ends where the map puts its last beat", float(window.size()) / DemoSong.RATE,
			map.seconds_at(48.0) - map.seconds_at(12.0), 0.001)


func _test_the_demo_song_follows_the_meter() -> void:
	check("a bar of 4/4 is felt on each count", DemoSong.pulses(Vector2i(4, 4)) == [0.0, 1.0, 2.0, 3.0])
	check("one of 3/4 on its three", DemoSong.pulses(Vector2i(3, 4)) == [0.0, 1.0, 2.0])
	check("6/8 in two dotted beats", DemoSong.pulses(Vector2i(6, 8)) == [0.0, 1.5])
	check("7/8 as 2+2+3", DemoSong.pulses(Vector2i(7, 8)) == [0.0, 1.0, 2.0])
	var steps := func(wav: PackedFloat32Array, origin: float, beats: Array) -> Array:
		# The kicks whose click is not a step of its own on its beat's sample, at 120 (half a second
		# a beat).
		var off: Array = []
		for b in beats:
			var at := int((b * 0.5 - origin) * DemoSong.RATE)
			if absf(wav[at] - wav[at - 1]) < 0.05 or absf(wav[at - 1] - wav[at - 2]) > 0.05:
				off.append(b)
		return off
	var waltz := DemoSong.render("kick", 120.0, Vector2i(3, 4))
	check("a loop in 3/4 is four bars of three", waltz.size() == 6 * DemoSong.RATE)
	var off: Array = steps.call(waltz, 0.0, [3.0, 6.0, 9.0, 11.0])
	check("its kicks on each bar's first beat, and a pickup on the last bar's third (off at %s)" % [off],
			off.is_empty())
	# 4/4 for a loop, then 6/8: a window of the second loop has the end of the first in its lead.
	var meter := [[0.0, 4, 4], [16.0, 6, 8]]
	var made := DemoSong.render_window("kick", [[0.0, 120.0, 0]], 1, meter)
	close_to("a window after a change of signature starts its lead before the change", made[1], 6.0)
	close_to("and holds eight bars of 6/8 after it", float((made[0] as PackedFloat32Array).size()) / DemoSong.RATE,
			(16.0 + 24.0) * 0.5 - 6.0, 0.001)
	off = steps.call(made[0], made[1], [14.5, 15.5, 16.0, 19.0, 22.0, 25.0, 27.5, 28.0, 31.0, 34.0, 37.0, 39.5])
	check("the 4/4 bar before it plays as 4/4, and each 6/8 bar as 6/8 (off at %s)" % [off], off.is_empty())


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
	# On a marker, MARK renames it; a fine press removes it.
	var mark_at := s.position_seconds
	deck._mark_key.pressed.emit()
	var prompt: NamePrompt = get_tree().root.get_children().filter(func(n): return n is NamePrompt).back()
	check("MARK on a marker asks for its name, not another marker (%d)" % s.markers.size(),
			prompt != null and prompt._edit.text == "MARK 1" and s.markers.size() == before + 1)
	prompt._edit.text_submitted.emit("Bridge")
	check("and the name typed is the marker's", s.markers.get(mark_at) == "Bridge")
	DAW.undo()
	check("which is one undo", s.markers.get(mark_at) == "MARK 1")
	var finger := FakeHand.new()
	add_child(finger)
	finger.holding_shift = true
	deck._mark_key.grab_begin(finger, deck._mark_key.global_position)
	deck._mark_key.grab_end(finger)
	finger.queue_free()
	check("a fine press on it removes it", not s.markers.has(mark_at) and s.markers.size() == before)
	DAW.undo()
	DAW.edit_marker(mark_at, mark_at + 2.0, "Moved")
	check("edit_marker moves and renames one", not s.markers.has(mark_at) and s.markers.get(mark_at + 2.0) == "Moved")
	DAW.apply_intent(&"edit_marker", [mark_at + 2.0, -5.0, "x".repeat(500)])
	check("a guest's edit is kept on the timeline and its name to a sane length",
			s.markers.has(0.0) and str(s.markers[0.0]).length() == DAW.MARKER_NAME_MAX)
	var sizes := s.markers.size()
	DAW.apply_intent(&"remove_marker", ["here"])
	DAW.apply_intent(&"edit_marker", [0.0, INF, "x"])
	check("and malformed ones are refused", s.markers.size() == sizes and s.markers.has(0.0)
			and &"edit_marker" in DAW.COMMANDS and &"remove_marker" in DAW.COMMANDS)
	DAW.remove_marker(123456.0)
	check("removing where there is none changes nothing", s.markers.size() == sizes)
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
		# Five minutes, compressed: long enough that an uncorrected buffer would have drifted
		# by 0.3 s, over thirty times the depth allowed off the target.
		while t < 5.0 * 60.0 * 1000.0:
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
	check("twenty-four keys share sixteen voices", synth.sounding() == DawKitTine.VOICES)
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
	# A host on Reaper, which records its own keys: these are the guest's alone.
	backend.records_inputs = true
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


func _test_someone_elses_motion_plays_back_as_it_was_made() -> void:
	var trail := PoseTrail.new()
	var at := func(x: float) -> Transform3D: return Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
	# Moving at 1 m/s, a pose every 50ms -- heard a little unevenly.
	for k in 5:
		trail.push(1000.0 + k * 50.0 + (8.0 if k == 2 else 0.0), at.call(k * 0.05))
	var x := func(now: float) -> float: return trail.sample(now).origin.x
	check("drawn a moment behind, between the two poses either side (%.3f)" % x.call(1175.0),
			absf(x.call(1175.0) - 0.075) < 0.004)
	check("smooth through the late one: no step where it came in (%.3f, %.3f, %.3f)" % [x.call(1195.0), x.call(1200.0), x.call(1205.0)],
			x.call(1200.0) > x.call(1195.0) and x.call(1205.0) > x.call(1200.0))
	check("past the newest, carried on as it was going (%.3f)" % x.call(1350.0), x.call(1350.0) > 0.2)
	check("then back where it was last heard to be, not left beyond it (%.3f)" % x.call(1600.0),
			is_equal_approx(x.call(1600.0), 0.2) and trail.settled(1600.0))
	# Stood still a second, then moved on: it waits where it was, not creeping all second.
	trail.push(2600.0, at.call(0.4))
	check("a stop is a stop, not a slow creep to where it moved on to (%.3f)" % x.call(2600.0),
			is_equal_approx(x.call(2600.0), 0.2))


func _test_the_timeline_is_resized_by_its_corner() -> void:
	_offline()
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)
	var grip: TimelineResizeGrip = timeline._grip
	var wide := timeline.width
	var tall := timeline._height
	var lanes := timeline._lane_y.size()
	var chosen: Array = []
	timeline.size_chosen.connect(func(w: float, l: float): chosen.append([w, l]))
	var corner := grip.global_position
	grip._on_grab_begin(corner)
	grip._on_grab_move(corner + timeline.global_basis.x * 0.05 - timeline.global_basis.y * 0.03)
	grip._on_grab_end()
	timeline._process(0.0)
	check("dragged out, the panel is wider by twice the hand's travel (%.3f -> %.3f)" % [wide, timeline.width],
			absf(timeline.width - (wide + 0.1)) < 0.001)
	check("and down, the lanes taller, the panel by twice the travel (%.4f -> %.4f)" % [tall, timeline._height],
			absf(timeline.lane_height - (TimelineSurface.LANE_HEIGHT + 0.06 / lanes)) < 0.0001
			and absf(timeline._height - (tall + 0.06)) < 0.001)
	check("the corner is where the hand let go", grip.global_position.distance_to(
			corner + timeline.global_basis.x * 0.05 - timeline.global_basis.y * 0.03) < 0.003)
	check("and the size is said, to be kept (%s)" % [chosen], chosen.size() == 1
			and is_equal_approx(chosen[0][1], timeline.lane_height))
	grip._on_grab_begin(grip.global_position)
	grip._on_grab_end()
	timeline._process(0.0)
	check("a click on the corner puts the usual size back", is_equal_approx(timeline.width, wide)
			and is_equal_approx(timeline.lane_height, TimelineSurface.LANE_HEIGHT))
	timeline.set_size(10.0, 1.0)
	check("and no bigger than it stays readable and fits", is_equal_approx(timeline.width_scale, TimelineSurface.WIDTH_SCALE_MAX)
			and is_equal_approx(timeline.lane_height, TimelineSurface.LANE_HEIGHT_MAX))
	timeline.free()


func _test_a_block_goes_from_one_shelf_onto_another() -> void:
	_offline()
	var tracks: Array = DAW.state.track_indices().filter(func(i): return not DAW.state.track(i).items.is_empty())
	check("the stand-in has items on two tracks at least (%d)" % tracks.size(), tracks.size() >= 2)
	if tracks.size() < 2:
		return
	var from: int = tracks[0]
	var to: int = tracks[1]
	var had := [DAW.state.track(from).items.size(), DAW.state.track(to).items.size()]
	var moving: String = DAW.state.track(from).items[0].name
	DAW.move_item(from, 0, 12.0, to)
	var landed: Array = DAW.state.track(to).items.filter(func(it): return it.name == moving and is_equal_approx(it.start, 12.0))
	check("moved onto the other track, where it was let go (%d -> %d)" % [from, to],
			DAW.state.track(from).items.size() == had[0] - 1 and DAW.state.track(to).items.size() == had[1] + 1
			and landed.size() == 1)
	DAW.undo()
	check("and undone, back on its own", DAW.state.track(from).items.size() == had[0]
			and DAW.state.track(to).items.size() == had[1] and DAW.state.track(from).items[0].name == moving)
	DAW.apply_intent(&"move_item", [from, 0, "soon", to])
	check("a guest's move with a start that is not a number is refused", DAW.state.track(from).items.size() == had[0])
	DAW.apply_intent(&"move_item", [from, 0, 3.0])
	check("one without a track, as older guests send, moves it along its own",
			is_equal_approx(DAW.state.track(from).items[0].start, 3.0) and DAW.state.track(to).items.size() == had[1])
	DAW.undo()

	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)
	timeline.set_shelf(true)
	timeline._process(0.0)
	var blocks := timeline.get_node_or_null("ItemBlocks") as MeshBank
	var lips := timeline.get_node_or_null("ShelfLips") as MeshBank
	check("on the shelves: a board under every lane (%d)" % (lips.count() if lips else -1),
			lips != null and lips.count() == timeline._lane_y.size())
	check("and the blocks stand out of the panel", blocks != null and blocks.multimesh.visible_instance_count > 0
			and is_equal_approx(blocks.transform_of(0).basis.get_scale().z, TimelineSurface.BLOCK_DEPTH))
	var box := blocks.transform_of(0)
	var face := timeline.to_global(box.origin + Vector3(0, 0, box.basis.get_scale().z * 0.5))
	var lanes_box := timeline._lanes.global_transform * (timeline._lanes._shape.transform
			* AABB(-(timeline._lanes._shape.shape as BoxShape3D).size * 0.5, (timeline._lanes._shape.shape as BoxShape3D).size))
	check("a press on a block's face lands on the lanes, and on that block",
			lanes_box.grow(0.0002).has_point(face) and not timeline.item_at_point(face).is_empty())
	var hits := ZFightProbe.scan(timeline)
	check("no two faces of the shelves share a plane (%d: %s)" % [hits.size(), ", ".join(hits.slice(0, 4).map(
			func(h): return "%s | %s" % [ZFightProbe.label(h[0]), ZFightProbe.label(h[1])]))], hits.is_empty())
	# Dragged over another lane, it is drawn there until it is let go.
	var shown: Array = timeline._shown()
	var hit: Array = timeline.item_at_point(face)
	var other: int = shown[0] if shown[0] != hit[0] else shown[1]
	timeline.preview_item(hit[0], hit[1], DAW.state.item(hit[0], hit[1]).start, -1.0, other)
	var on_other := false
	for k in blocks.multimesh.visible_instance_count:
		on_other = on_other or (is_equal_approx(blocks.transform_of(k).origin.y, timeline._lane_y[shown.find(other)])
				and blocks.transform_of(k).origin.z > box.origin.z + 0.001)
	check("dragged over another shelf, it is drawn there, out of it as in the hand", on_other)
	timeline.preview_item(-1, -1, 0.0)
	# By hand: taken by its face, carried down onto the other shelf, and let go there.
	var on_from := DAW.state.track(hit[0]).items.size()
	var on_to := DAW.state.track(other).items.size()
	var drop := timeline.to_global(Vector3(box.origin.x, timeline._lane_y[shown.find(other)],
			box.origin.z + box.basis.get_scale().z * 0.5))
	timeline._lanes._on_grab_begin(face)
	timeline._lanes._on_grab_move(drop)
	timeline._lanes._on_grab_end()
	check("a block carried onto another shelf and let go is on that shelf (%d -> %d)" % [hit[0], other],
			DAW.state.track(hit[0]).items.size() == on_from - 1 and DAW.state.track(other).items.size() == on_to + 1)
	DAW.undo()
	timeline.set_shelf(false)
	timeline._process(0.0)
	check("and flat again, with no boards", timeline.get_node_or_null("ShelfLips") == null)
	timeline.free()


func _test_the_timeline_clips_are_the_brightest_thing_on_their_lane() -> void:
	# 2026-10-12: "hard to see... can't tell tracks, clips or the playhead apart at a glance". A
	# clip is read against its lane bed, so the figure that matters is how far apart they are.
	var kick := Color(1.0, 0.48, 0.36)
	var body := TimelineSurface.item_body(kick, false, false)
	check("a clip is far brighter than the lane it lies on (%.2f vs %.2f)" % [body.v, TimelineSurface.LANE_BED.v],
			body.v >= 0.58 and body.v - TimelineSurface.LANE_BED.v >= 0.40)
	check("and a muted one is not, though it is still there", TimelineSurface.item_body(kick, true, false).v < 0.35
			and TimelineSurface.item_body(kick, true, false).v > TimelineSurface.LANE_BED.v)
	check("and a selected one is lifted toward white", TimelineSurface.item_body(kick, false, true).s < body.s - 0.2)
	# Ink on a lit clip, light on a muted one: names were white on pastel, a smudge at a distance.
	var ink := TimelineSurface.ITEM_NAME_INK
	check("a lit clip's name is dark and a muted one's is light",
			ink.v < 0.2 and TimelineSurface.ITEM_NAME_LIGHT.v > 0.8)
	_offline()
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)
	var shades := timeline.get_node_or_null("ItemShades") as MeshBank
	var blocks := timeline.get_node_or_null("ItemBlocks") as MeshBank
	check("every clip has a shadow and a bottom edge under it, flat as well as on the shelves",
			shades != null and blocks != null and shades.count() == blocks.count() * 2
			and shades.multimesh.visible_instance_count == blocks.multimesh.visible_instance_count * 2)
	timeline.free()


func _test_the_timelines_keys_are_big_enough_to_aim_at() -> void:
	# 2026-10-12: "all the buttons and dials and knobs are sooooo tiny". The keys under the
	# timeline were 22 mm with 7 px captions, and the strips ran past the panel's own edge.
	_offline()
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline.set_wide(true)
	timeline._process(0.0)
	check("the panel's own keys are drawn at %.1fx, up from 1.4x" % TimelineSurface.KEY_SCALE,
			is_equal_approx(timeline._split_key.scale.x, TimelineSurface.KEY_SCALE) and TimelineSurface.KEY_SCALE >= 1.7)
	var strips: Array = [timeline._item_controls, timeline._tempo_controls, timeline._render_controls, timeline._track_controls]
	var pitches: Array = [TimelineItemStrip.PITCH, TimelineTempoStrip.PITCH, TimelineRenderStrip.PITCH, TimelineTrackStrip.PITCH]
	var keys: Array = [6, 5, 2, 7]
	var scale_ok := true
	var clear := true
	var right_edge := -INF
	for i in strips.size():
		var strip: Node3D = strips[i]
		scale_ok = scale_ok and strip.scale.x >= 1.15
		var left: float = strip.position.x - 0.5 * pitches[i] * strip.scale.x
		var right: float = strip.position.x + (keys[i] - 0.5) * pitches[i] * strip.scale.x
		clear = clear and left > right_edge
		right_edge = maxf(right_edge, right)
	check("the strips of keys under it are drawn at least 1.15x, in order, and clear of one another",
			scale_ok and clear)
	check("and none runs past the panel's right edge (%.3f of %.3f)" % [right_edge, timeline.width * 0.5],
			right_edge <= timeline.width * 0.5)
	# What the camera frames is the panel; the keys hang below it.
	var framed := timeline.content_aabb()
	var panel_bottom := -timeline._top_y
	check("the framing leaves the strips out, so a bigger key does not shrink the arrangement (%.3f)" % framed.position.y,
			framed.position.y >= panel_bottom - 0.01)
	timeline.free()


func _test_the_timeline_can_be_watched_as_a_road() -> void:
	_offline()
	var timeline := TimelineSurface.new()
	add_child(timeline)
	timeline._process(0.0)
	var road := timeline.get_node_or_null("Highway") as TimelineHighway
	check("the road is built with the timeline, and not shown until asked for", road != null and not road.visible and not timeline.highway)
	check("while it is not, the lanes take presses", timeline._lanes.collision_layer == 2 and timeline._header.collision_layer == 2)
	timeline.set_highway(true)
	check("asked for, it is shown and has a lane for each track on the panel",
			road.visible and road.lane_count() == timeline._shown().size() and road.lane_count() > 0)
	check("and then the lanes let presses through: nothing hidden takes one",
			timeline._lanes.collision_layer == 0 and timeline._header.collision_layer == 0
			and timeline._seek_strip.collision_layer == 0 and timeline._loop_strip.collision_layer == 0)
	var drawn_flat := false
	for child in timeline.get_children():
		if child.get_meta("built", false) and child is Node3D and (child as Node3D).visible:
			drawn_flat = true
	check("and none of the flat lanes is drawn under it", not drawn_flat)

	# Parked in the middle of verse 1 -- bar 9 begins at 20.8s at 92.6bpm -- the kick, snare and
	# vocal lanes have a take under the gate, and the hat's is muted.
	DAW.seek(30.0)
	road.update_now()
	var bank := road.find_child("Blocks", true, false) as MeshBank
	check("blocks are on the road", bank != null and bank.multimesh.visible_instance_count > 0)
	var under := 0
	var lit := 0
	var shown: Array = timeline._shown()
	for i in shown.size():
		var track := DAW.state.track(shown[i])
		var has := false
		for item in track.items:
			if item.start <= 30.0 and item.end() > 30.0 and not item.muted and not track.mute:
				has = true
		under += 1 if has else 0
		lit += 1 if road._pad_lit[i] else 0
	check("a lane's receptor is lit exactly while its lane has a take under the gate (%d of %d lit)" % [lit, under],
			under > 0 and lit == under)
	# The nearest face of the nearest block is at the gate, give or take the gap between blocks:
	# a take that is playing starts at the gate, not somewhere down the road.
	var nearest := -INF
	for k in bank.multimesh.visible_instance_count:
		var box := bank.transform_of(k)
		nearest = maxf(nearest, box.origin.z + box.basis.get_scale().z * 0.5)
	check("a take that is playing starts at the gate (%.4f)" % nearest, absf(nearest + TimelineHighway.GAP) < 0.0005)
	# And nothing starts before it does: the road is what is coming, in order.
	DAW.seek(10.0)
	road.update_now()
	var from_ten := 0.0
	for k in bank.multimesh.visible_instance_count:
		var box := bank.transform_of(k)
		from_ten = minf(from_ten, box.origin.z - box.basis.get_scale().z * 0.5)
	check("the far end of the road is the same length of song whenever it is looked at (%.3f)" % from_ten,
			from_ten >= -road._length - 0.0005 and from_ten < -road._length * 0.5)
	# Ten seconds in only the intro is playing; the verse is still down the road, in its lanes.
	var intro_lit := 0
	for flag in road._pad_lit:
		intro_lit += 1 if flag else 0
	var furthest_start := INF
	var started_late := 0
	for k in bank.multimesh.visible_instance_count:
		var box := bank.transform_of(k)
		var near := box.origin.z + box.basis.get_scale().z * 0.5
		if near < -road._length * 0.2:
			started_late += 1
		furthest_start = minf(furthest_start, near)
	check("at 10s only the intro is under the gate (%d lit) and the verse is still on its way (%d takes)" % [intro_lit, started_late],
			intro_lit > 0 and intro_lit < lit and started_late > 0)

	timeline.set_highway(false)
	check("put back, the lanes are drawn and take presses again",
			not road.visible and timeline._lanes.collision_layer == 2 and timeline._header.collision_layer == 2)
	timeline.free()


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
	## What a click is on each side.
	var sides := Vector2(0.9, 0.9)

	func read() -> PackedVector2Array:
		var out := PackedVector2Array()
		out.resize(480)
		for i in 480:
			if (made + i) % 48000 < 24:
				out[i] = sides
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


func _test_the_lanes_hear_the_newest_item_where_items_overlap() -> void:
	check("a span with nothing over it is whole", LaneEngine.visible(0.0, 4.0, []) == [[0.0, 4.0]])
	check("one over its middle leaves either side",
			LaneEngine.visible(0.0, 4.0, [[1.0, 2.0]]) == [[0.0, 1.0], [2.0, 4.0]])
	check("one over all of it leaves nothing", LaneEngine.visible(1.0, 2.0, [[0.0, 4.0]]).is_empty())
	check("and two over its ends leave what is between",
			LaneEngine.visible(0.0, 4.0, [[3.0, 5.0], [-1.0, 0.5]]) == [[0.5, 3.0]])
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var take := AudioTake.create("suite-lanes-take.wav")
	var tone := PackedVector2Array()
	tone.resize(AudioTake.RATE * 4)
	take.append(AudioTake.encode(tone))
	take.finish()
	DAW.insert_audio_take(6, 300.0, take.file_name(), take.seconds(), take.peaks(), "Grace audio 1")
	DAW.insert_audio_take(6, 301.0, take.file_name(), 1.0, take.peaks(), "Grace audio 2")
	var lanes := LaneEngine.new()
	lanes.backend = backend
	# The track's demo part is on it too, before the takes.
	var clips := lanes.clips_for(6).filter(func(c): return c["start"] >= 300.0)
	clips.sort_custom(func(a, b): return a["start"] < b["start"])
	check("the lane plays the older take round the newer, and the newer in its place",
			clips.size() == 3 and is_equal_approx(clips[0]["start"], 300.0) and is_equal_approx(clips[0]["length"], 1.0)
			and is_equal_approx(clips[1]["start"], 301.0) and is_equal_approx(clips[1]["offset"], 0.0)
			and is_equal_approx(clips[2]["start"], 302.0) and is_equal_approx(clips[2]["offset"], 2.0))
	lanes.free()
	_offline()
	take.discard()


func _test_the_built_in_engine_plays_notes_through_its_instrument() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	DAW.state.track(6).items.clear()
	DAW.insert_midi_take(6, 300.0, 302.0, [[300.25, 300.75, 60, 100, 0], [300.8125, 301.5, 67, 90, 0]], "Ada take 1")
	var it: MixState.ItemState = DAW.state.track(6).items[0]
	var stream := backend.midi_stream(it, true)
	var rate := AudioServer.get_mix_rate()
	check("a MIDI item is rendered through the instrument", stream != null and stream.stereo
			and absf(stream.get_length() - (2.0 + DawKitTine.TAIL_SECONDS)) < 0.001)
	if stream != null:
		# Measured: the render is silent until the first note, which starts on its sample (a voice
		# starts on a zero crossing, so the next sample is the first with sound).
		var first := -1
		for f in stream.data.size() / 4:
			if stream.data.decode_s16(f * 4) != 0 or stream.data.decode_s16(f * 4 + 2) != 0:
				first = f
				break
		var want := int(round(it.notes[0] * rate)) + 1
		check("silent until its first note, which is on its sample (%d, %d)" % [first, want],
				it.notes[0] == 0.25 and first == want)
	check("asked again, it is the same sound, not rendered again", backend.midi_stream(it) == stream)
	DAW.state.position_seconds = 300.5
	DAW.state.playing = true
	backend._sync_players()
	var own: AudioStreamPlayer = backend._players[6][0]
	check("and plays on its track's bus while the playhead is in it", own.playing and own.stream == stream)
	DAW.state.position_seconds = 303.0
	backend._sync_players()
	check("and stops where the item does", not own.playing)
	DAW.state.playing = false

	var p := ProjectBridge.capture(backend)
	var t := p.track(ProjectBridge.id_of(6))
	check("in the project, the track plays its notes through the tine",
			not t.effects.is_empty() and t.effects[0].instrument and t.effects[0].kind == ProjectBridge.INSTRUMENT)
	var chain := backend.state.track(6).plugins().size()
	var fresh := GodotBackend.new()
	fresh.state = MixState.new()
	DAW.use(fresh)
	ProjectBridge.load(p, fresh)
	check("and opened, the instrument is not an effect on the desk (%d, %d)" % [fresh.state.track(6).plugins().size(), chain],
			fresh.state.track(6).plugins().size() == chain)
	var again := ProjectBridge.capture(fresh)
	check("so it comes back the same (%s)" % p.first_difference(again), p.same_as(again))

	# Another DAW's instrument on the track: the engine cannot run it, so the notes play through
	# the tine, and the track is saved with the instrument it came with.
	var surge := DawKitEffect.new()
	surge.name = "Surge XT"
	surge.instrument = true
	surge.plugin_format = "CLAP"
	surge.plugin_id = "org.surge-synth-team.surge-xt"
	surge.state = PackedByteArray([1, 2, 3])
	t.effects[0] = surge
	ProjectBridge.load(p, fresh)
	var kept := ProjectBridge.capture(fresh)
	var first_fx := kept.track(ProjectBridge.id_of(6)).effects[0]
	check("another DAW's instrument is kept, not swapped for the tine (%s)" % first_fx.name,
			first_fx.instrument and first_fx.plugin_id == surge.plugin_id and first_fx.state == surge.state)
	check("and the desk's chain is still only effects", fresh.state.track(6).plugins().size() == chain)

	var stale := fresh.state.track(6).items[0] as MixState.ItemState
	fresh.midi_stream(stale, true)
	var key := GodotBackend.midi_key(stale)
	stale.notes = PackedFloat32Array([0.1, 0.2, 72, 100, 0])
	fresh.prune_renders()
	check("a render of notes no longer on the timeline is let go", not fresh._midi_streams.has(key))
	_offline()


func _test_items_are_deleted_duplicated_trimmed_and_shaped() -> void:
	_offline()
	var s := DAW.state
	var lane := 6
	s.track(lane).items.clear()
	DAW.insert_midi_take(lane, 10.0, 14.0, [[10.5, 11.0, 60, 100, 0], [12.5, 13.5, 64, 90, 0]], "Keys")
	DAW.insert_audio_take(lane, 20.0, "suite-edit.wav", 4.0, PackedByteArray(), "Vox")
	var depth := maxi(s.undo_depth, 0)

	DAW.select_item(lane, 0)
	DAW.duplicate_selected()
	var items: Array = s.track(lane).items
	check("duplicated, a copy follows the item (%d)" % items.size(), items.size() == 3)
	if items.size() == 3:
		# The lane is kept in order of start, as Reaper numbers it.
		var copy: MixState.ItemState = items[1]
		check("straight after it, with its notes", is_equal_approx(copy.start, 14.0)
				and copy.notes == items[0].notes)
		check("and the copy is the selection now", copy.selected and not items[0].selected)
	DAW.delete_selected()
	check("deleted, the copy is gone", s.track(lane).items.size() == 2)
	DAW.undo()
	check("undone, it is back", s.track(lane).items.size() == 3)
	DAW.undo()
	check("and undone again, there was never a copy", s.track(lane).items.size() == 2)

	DAW.trim_item(lane, 0, 12.0, 13.0)
	var keys: MixState.ItemState = s.item(lane, 0)
	check("trimmed from both ends (%.2f, %.2f)" % [keys.start, keys.length],
			is_equal_approx(keys.start, 12.0) and is_equal_approx(keys.length, 1.0))
	var notes := MidiTake.unpack_relative(keys.notes, keys.start)
	check("its notes stay where they were in the song, and only those inside it (%s)" % [notes],
			notes.size() == 1 and is_equal_approx(notes[0][0], 12.5) and is_equal_approx(notes[0][1], 13.0))
	DAW.trim_item(lane, 1, 21.5, 24.0)
	var vox: MixState.ItemState = s.item(lane, 1)
	check("an audio item trimmed on the left starts later in its file (%.2f)" % vox.source_offset,
			is_equal_approx(vox.start, 21.5) and is_equal_approx(vox.source_offset, 1.5))
	DAW.trim_item(lane, 1, 15.0, 24.0)
	check("and cannot be pulled out before its file begins (%.2f)" % s.item(lane, 1).start,
			is_equal_approx(s.item(lane, 1).start, 20.0) and is_equal_approx(s.item(lane, 1).source_offset, 0.0))

	DAW.set_item_gain(lane, 1, -6.0)
	DAW.set_item_fades(lane, 1, 0.5, 9.0)
	vox = s.item(lane, 1)
	check("an item's own gain", is_equal_approx(vox.gain_db, -6.0))
	check("and its fades, never longer than it is (%.2f, %.2f)" % [vox.fade_in, vox.fade_out],
			is_equal_approx(vox.fade_in, 0.5) and is_equal_approx(vox.fade_out, vox.length - 0.5))
	close_to("heard half way through its fade in at half level", GodotBackend.item_level(vox, vox.start + 0.25),
			-6.0 + linear_to_db(0.5), 0.001)
	check("each edit one step to undo (%d)" % (s.undo_depth - depth), s.undo_depth - depth == 5)

	DAW.apply_intent(&"set_item_gain", [lane, 1, NAN])
	DAW.apply_intent(&"trim_item", [lane, 1, 20.0])
	check("a guest's malformed edit is refused", is_equal_approx(s.item(lane, 1).gain_db, -6.0)
			and is_equal_approx(s.item(lane, 1).start, 20.0))
	DAW.apply_intent(&"set_item_gain", [lane, 1, 999.0])
	check("and its gain kept on the scale", is_equal_approx(s.item(lane, 1).gain_db, DAWBackend.ITEM_GAIN_MAX))

	var link := _fresh_link()
	link.state.track(4)
	link._on_timeline({"length": 60.0, "markers": [], "tracks": [{"index": 4, "items": [
			{"start": 1.0, "length": 2.0, "muted": false, "name": "A", "selected": false,
			"fade_in": 0.25, "fade_out": 0.01, "gain": 0.5},
			{"start": 4.0, "length": 2.0, "muted": false, "name": "B", "selected": false,
			"fade_in": 0.01, "fade_out": 0.01, "gain": 1.0}]}]})
	var a := link.state.item(4, 0)
	var b := link.state.item(4, 1)
	check("Reaper's fades and item volume reach the desk (%s)" % [[a.fade_in, a.gain_db] if a else null],
			a != null and is_equal_approx(a.fade_in, 0.25) and absf(a.gain_db - linear_to_db(0.5)) < 0.001)
	check("and its default anti-click fade is no fade", b != null and b.fade_in == 0.0 and b.gain_db == 0.0)
	link._on_timeline({"length": 60.0, "markers": [], "tracks": [],
			"tempo": [[0.0, 120.0, false], [8.0, 90.0, true], [16.0, 60.0, false]]})
	check("Reaper's tempo markers are the map, its gradual change a ramp in time (%s)" % [link.state.tempo_points],
			link.state.tempo_points == [[0.0, 120.0, 0], [8.0, 90.0, 2], [16.0, 60.0, 0]])
	link._on_timeline({"length": 60.0, "markers": [], "tracks": [], "tempo": [[0.0, 120.0, false]]})
	check("and one marker is one tempo", link.state.tempo_points.is_empty())
	link.free()
	_offline()


func _test_notes_are_transposed_and_quantised() -> void:
	_offline()
	var s := DAW.state
	var lane := 6
	s.track(lane).items.clear()
	var beat := 60.0 / s.tempo
	# A beat late, a little early, a little late; and one at the very top of the range.
	DAW.insert_midi_take(lane, 4.0 * beat, 8.0 * beat, [[4.0 * beat + 0.02, 5.0 * beat, 60, 100, 0],
			[6.0 * beat - 0.03, 6.5 * beat, 64, 90, 0], [7.0 * beat + 0.04, 7.5 * beat, 126, 80, 0]], "Keys")
	var depth := maxi(s.undo_depth, 0)
	var key := GodotBackend.midi_key(s.item(lane, 0))

	DAW.transpose_item(lane, 0, 3)
	var notes := MidiTake.unpack_relative(s.item(lane, 0).notes, s.item(lane, 0).start)
	check("transposed, every note is three semitones up, and none past 127 (%s)" % [notes.map(func(n): return n[2])],
			notes.map(func(n): return int(n[2])) == [63, 67, 127])
	check("and the engine renders it again", GodotBackend.midi_key(s.item(lane, 0)) != key)

	DAW.quantize_item(lane, 0, 1.0, 0.5)
	notes = MidiTake.unpack_relative(s.item(lane, 0).notes, s.item(lane, 0).start)
	check("quantised at half strength, each note half way to its beat (%s)" % [notes.map(func(n): return n[0])],
			absf(notes[0][0] - (4.0 * beat + 0.01)) < 1e-4 and absf(notes[1][0] - (6.0 * beat - 0.015)) < 1e-4
			and absf(notes[2][0] - (7.0 * beat + 0.02)) < 1e-4)
	DAW.quantize_item(lane, 0, 1.0)
	notes = MidiTake.unpack_relative(s.item(lane, 0).notes, s.item(lane, 0).start)
	check("and at full strength, on it, keeping each note's length (%s)" % [notes.map(func(n): return n[0])],
			absf(notes[0][0] - 4.0 * beat) < 1e-4 and absf(notes[1][0] - 6.0 * beat) < 1e-4
			and absf(notes[1][1] - (6.5 * beat + 0.03)) < 1e-4)
	DAW.quantize_item(lane, 0, 4.0)
	notes = MidiTake.unpack_relative(s.item(lane, 0).notes, s.item(lane, 0).start)
	check("a note pulled before its item stops at the item's start (%s)" % [notes.map(func(n): return n[0])],
			absf(notes[0][0] - 4.0 * beat) < 1e-4 and absf(notes[2][0] - 8.0 * beat) < 1e-4)
	check("each edit one step to undo (%d)" % (s.undo_depth - depth), s.undo_depth - depth == 4)
	DAW.undo()
	DAW.undo()
	DAW.undo()
	DAW.undo()
	notes = MidiTake.unpack_relative(s.item(lane, 0).notes, s.item(lane, 0).start)
	check("and undone, the notes are as played", int(notes[0][2]) == 60
			and absf(notes[0][0] - (4.0 * beat + 0.02)) < 1e-4)

	DAW.apply_intent(&"transpose_item", [lane, 0, 999])
	notes = MidiTake.unpack_relative(s.item(lane, 0).notes, s.item(lane, 0).start)
	check("a guest's transpose is kept within %d semitones" % DAWBackend.TRANSPOSE_MAX,
			int(notes[0][2]) == 60 + DAWBackend.TRANSPOSE_MAX)
	DAW.apply_intent(&"quantize_item", [lane, 0, INF, 1.0])
	check("and a malformed quantise refused", s.undo_depth - depth == 1)

	var project := ProjectBridge.capture(DAW.backend as OfflineBackend)
	var file := OS.get_temp_dir().path_join("suite_transpose.dawproject")
	var saved := DawKitDawproject.save(project, file)
	DirAccess.remove_absolute(file)
	var pitch := -1
	for t in project.tracks:
		for c in t.clips:
			if c.name == "Keys" and not c.notes.is_empty():
				pitch = int(c.notes[2])
	check("and saved to DAWproject transposed (%s %d)" % [saved, pitch], pitch == 60 + DAWBackend.TRANSPOSE_MAX)
	_offline()


func _test_tracks_are_added_removed_and_renamed() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var s := DAW.state
	var shape := func() -> Array:
		var out: Array = []
		for index in s.track_indices():
			var t: MixState.TrackState = s.tracks[index]
			var sends: Array = []
			for slot in t.sends:
				sends.append([slot, t.sends[slot].dest_track])
			out.append([index, t.name, t.folder_depth, sends, t.items.size(), backend.fx_kind(index, 0)])
		return out
	var was: Array = shape.call()
	var count := s.tracks.size()
	var depth := maxi(s.undo_depth, 0)
	var replaced := [0]
	var count_replaced := func(): replaced[0] += 1
	DAW.project_replaced.connect(count_replaced)
	var maps: Array = []
	var keep_map := func(map: Dictionary): maps.append(map)
	DAW.tracks_renumbered.connect(keep_map)
	Session.guest_audio.target_track = 5
	Session.guest_midi.target_track = 2

	DAW.add_track(3, "Overdub")
	check("a track added at 3 is there, empty, and the rest move down (%s)" % [s.track(3).name],
			s.tracks.size() == count + 1 and s.track(3).name == "Overdub" and s.track(3).items.is_empty()
			and s.track(4).name == was[2][1] and s.track(3).index == 3 and s.track(4).index == 4)
	check("the room is sent the whole mix", replaced[0] == 1)
	check("the renumbering is told, old to new (%s)" % [maps], maps.size() == 1 and maps[0].get(2) == 2
			and maps[0].get(3) == 4 and maps[0].size() == count)
	check("and a take's chosen track follows its track (%d, %d)" % [Session.guest_audio.target_track,
			Session.guest_midi.target_track], Session.guest_audio.target_track == 6 and Session.guest_midi.target_track == 2)
	DAW.remove_track(6)
	check("and is none once its track is gone", Session.guest_audio.target_track == 0)
	DAW.undo()
	check("undone, the map says where each track went back to (%s)" % [maps[-1]],
			maps.size() == 3 and maps[-1].get(5) == 5 and maps[-1].get(6) == 7 and maps[-1].size() == count)
	Session.guest_audio.target_track = 4
	Session.guest_midi.target_track = 0
	Session._tracks_renumbered({4: 5, "x": 1, 2: "y"})
	check("a guest told of a renumbering follows it, and ignores what is not a track number",
			Session.guest_audio.target_track == 5 and Session.guest_midi.target_track == 0)
	DAW.tracks_renumbered.disconnect(keep_map)
	Session.guest_audio.target_track = 0
	Session.guest_midi.target_track = 0
	var follows := true
	for row in was:
		for send in row[3]:
			var from: int = row[0] + (1 if row[0] >= 3 else 0)
			var to: int = send[1] + (1 if send[1] >= 3 else 0)
			follows = follows and s.track(from).sends[send[0]].dest_track == to
	check("every send still goes to the same track", follows)
	check("and every effect is still the same kind",
			was.all(func(row): return backend.fx_kind(row[0] + (1 if row[0] >= 3 else 0), 0) == row[5]))
	check("saved, the project has it", ProjectBridge.capture(backend).tracks[2].name == "Overdub")

	# The demo's DRUMS folder, track 1, holds the kit.
	var kit_level := s.folder_level(2)
	DAW.undo()
	check("undone, the mix is as it was", shape.call() == was)
	DAW.remove_track(1)
	var p := ProjectBridge.capture(backend)
	check("a folder removed, its children move out a level (%d -> %d)" % [kit_level, s.folder_level(1)],
			s.tracks.size() == count - 1 and s.track(1).name == was[1][1]
			and s.folder_level(1) == kit_level - 1 and p.problems().is_empty())
	check("and the folders after it keep their shape", range(2, count).all(func(i):
			return s.folder_level(i) == maxi(_level_in(was, i + 1) - (1 if _level_in(was, i + 1) > 0 and i + 1 <= _folder_end(was, 1) else 0), 0)))
	DAW.undo()
	check("undone, it is back with its children in it", shape.call() == was)

	var target := -1
	for row in was:
		for send in row[3]:
			if send[1] > 0:
				target = send[1]
	if target > 0:
		var senders := was.filter(func(row): return row[3].any(func(sd): return sd[1] == target))
		DAW.remove_track(target)
		var gone := true
		for index in s.track_indices():
			for slot in s.tracks[index].sends:
				var sd: MixState.SendState = s.tracks[index].sends[slot]
				gone = gone and sd.dest_track > 0 and sd.dest_track < s.tracks.size() + 1 and sd.index == slot
		var first: int = senders[0][0] - (1 if senders[0][0] > target else 0)
		check("a return removed takes the sends to it, and the rest are numbered from 1 (%d)" % target,
				gone and s.track(first).sends.size() == senders[0][3].size() - 1)
		DAW.undo()
		check("undone, the sends to it are back", shape.call() == was)

	DAW.rename_track(2, "Kick In")
	check("renamed", s.track(2).name == "Kick In")
	DAW.undo()
	check("and undone", s.track(2).name == was[1][1])
	check("each edit one step to undo, and all undone (%d)" % (s.undo_depth - depth), s.undo_depth == depth)
	DAW.redo()
	check("and redone", s.track(2).name == "Kick In")
	DAW.undo()

	DAW.apply_intent(&"remove_track", ["x"])
	DAW.apply_intent(&"remove_track", [0])
	DAW.apply_intent(&"add_track", [2])
	check("a guest's malformed track edit is refused", shape.call() == was)
	DAW.apply_intent(&"rename_track", [2, "x".repeat(500)])
	check("and a long name cut to %d" % DAW.TRACK_NAME_MAX, s.track(2).name.length() == DAW.TRACK_NAME_MAX)
	DAW.project_replaced.disconnect(count_replaced)
	_offline()


func _test_the_tempo_changes_through_the_song() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var s := DAW.state
	DAW.set_tempo(120.0)
	var depth := maxi(s.undo_depth, 0)
	# Two bars at 120, then 60 from beat 8 (bar 3).
	DAW.set_tempo_map([[0.0, 120.0, DawKitTempoMap.HOLD], [8.0, 60.0, DawKitTempoMap.HOLD]])
	check("a tempo map is set (%s)" % [s.tempo_points], s.tempo_points.size() == 2 and s.tempo == 120.0)
	close_to("bar 3 starts where two bars at 120 end", s.bar_to_seconds(3.0), 4.0)
	close_to("and bar 4 a bar at 60 later", s.bar_to_seconds(4.0), 8.0)
	check("the counter reads through the change (%s)" % s.bar_beat(6.0), s.bar_beat(6.0) == "3.3.00")
	check("one undo step", s.undo_depth - depth == 1)

	s.track(6).items.clear()
	DAW.insert_midi_take(6, 4.0, 8.0, [[5.1, 5.5, 60, 100, 0]], "Slow")
	DAW.quantize_item(6, 0, 1.0)
	var on: float = MidiTake.unpack_relative(s.item(6, 0).notes, s.item(6, 0).start)[0][0]
	close_to("quantise finds the beat at the new tempo (a second long now)", on, 5.0)
	close_to("so does the timeline's snap", TimelineLanes.snap(6.4, false), 6.0)

	var wire := MixWire.snapshot(s)
	var guest := MixState.new()
	MixWire.apply_replicated(guest, wire)
	check("a joining guest gets the map", guest.tempo_points == s.tempo_points
			and guest.bar_beat(6.0) == "3.3.00")
	var p := ProjectBridge.capture(backend)
	check("it is saved in the project (%s)" % [p.tempo_points], p.tempo_points.size() == 2
			and p.problems().is_empty())

	s.metronome = true
	s.playing = true
	s.position_seconds = 9.0
	backend._sync_click()
	close_to("the click plays a window of the song's own clicks from the bar it is in",
			backend._click_from, 8.0)
	close_to("of %d seconds" % GodotBackend.CLICK_WINDOW, backend._click.stream.get_length(), GodotBackend.CLICK_WINDOW, 0.001)
	s.playing = false
	s.metronome = false
	backend._sync_click()

	DAW.apply_intent(&"set_tempo_map", [[0.0, 120.0, 0.0, 0.0, 90.0, 0.0]])
	check("a guest's map that goes backwards is refused", s.tempo_points.size() == 2 and s.tempo_points[1][1] == 60.0)
	DAW.apply_intent(&"set_tempo_map", ["x"])
	check("and one that is not a list", s.tempo_points.size() == 2)
	# The quantise, the take, then the map.
	DAW.undo()
	DAW.undo()
	DAW.undo()
	check("undone, one tempo again", s.tempo_points.is_empty())
	close_to("and bar 4 is where 120 puts it", s.bar_to_seconds(4.0), 6.0)
	_offline()


func _test_the_mix_and_its_stems_are_rendered_to_files() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var s := DAW.state
	check("the built-in engine renders", DAW.can(DAWBackend.Capability.RENDER))
	var effects_before := AudioServer.get_bus_effect_count(backend._master_bus)
	s.looping = true
	s.loop_start = 2.0
	s.loop_end = 2.5
	var heard: Array = []
	var on_done := func(files: PackedStringArray, problems: PackedStringArray) -> void:
		heard.append([files, problems])
	DAW.render_finished.connect(on_done)
	DAW.render(true)
	check("a render is under way, not looping", backend.rendering != null and not s.looping)
	DAW.render(false)
	check("and a second is refused while it runs", heard.size() == 1 and not (heard[0][1] as PackedStringArray).is_empty())
	heard.clear()
	var waited := 0.0
	while heard.is_empty() and waited < 10.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	DAW.render_finished.disconnect(on_done)
	check("it finishes (%.1fs)" % waited, not heard.is_empty())
	if heard.is_empty():
		_offline()
		return
	var files: PackedStringArray = heard[0][0]
	check("the mix and a stem per track (%d files, %s)" % [files.size(), heard[0][1]],
			files.size() == 1 + s.track_indices().size() and (heard[0][1] as PackedStringArray).is_empty())
	var mix := DawKitAudioFile.read(files[0])
	var rate := int(AudioServer.get_mix_rate())
	var range_frames := int(roundf(0.5 * rate))
	var frames := int(mix["frames"])
	check("the mix is the loop range and its tail, in stereo (%.2fs)" % (frames / float(rate)),
			files[0].ends_with(" - mix.wav") and int(mix["channels"]) == 2
			and frames >= range_frames and frames <= range_frames + int(DAWBackend.RENDER_TAIL_SECONDS * rate))
	var mix_samples: PackedFloat32Array = mix["samples"]
	var end_peak := 0.0
	for f in range(maxi(frames - rate / 20, 0), frames):
		end_peak = maxf(end_peak, absf(mix_samples[f * 2]))
	check("which rings out to silence (%.1f dB at its end)" % linear_to_db(maxf(end_peak, 1e-9)),
			linear_to_db(maxf(end_peak, 1e-9)) < -70.0 and frames < range_frames + int(DAWBackend.RENDER_TAIL_SECONDS * rate))
	check("and every stem is as long", int(DawKitAudioFile.read(files[2])["frames"]) == frames)
	check("the stems are named for their tracks", files[2].get_file().ends_with(" - %s.wav" % s.track(2).display_name()))
	check("the looping comes back, and the captures come off", s.looping and backend.rendering == null
			and AudioServer.get_bus_effect_count(backend._master_bus) == effects_before)
	for f in files:
		DirAccess.remove_absolute(f)
	DirAccess.remove_absolute(files[0].get_base_dir())
	s.looping = false
	_offline()


func _test_controls_follow_their_automation() -> void:
	var backend := GodotBackend.new()
	backend.state = MixState.new()
	DAW.use(backend)
	var s := DAW.state
	var depth := maxi(s.undo_depth, 0)
	# The fader from 0 dB down to -12 over the first two seconds, then held.
	DAW.set_automation(2, "volume", [[0.0, 0.0, DawKitAutomation.LINEAR], [2.0, -12.0, DawKitAutomation.HOLD]])
	DAW.set_automation(2, "pan", [[0.0, -1.0, DawKitAutomation.HOLD], [1.0, 1.0, DawKitAutomation.HOLD]])
	DAW.set_automation(2, "mute", [[0.0, 0.0, DawKitAutomation.HOLD], [3.0, 1.0, DawKitAutomation.HOLD]])
	check("lanes are set, one undo step each", s.track(2).automation.size() == 3 and s.undo_depth - depth == 3)
	s.position_seconds = 1.0
	backend.follow_automation()
	close_to("halfway down the ramp the fader reads -6 dB", s.track(2).volume_db, -6.0)
	close_to("its taper too", s.track(2).volume, backend.db_to_taper(-6.0))
	close_to("the pan has jumped right at its point", s.track(2).pan, 1.0)
	check("and it is not muted yet", not s.track(2).mute)
	s.position_seconds = 5.0
	backend.follow_automation()
	close_to("after the last point the last value holds", s.track(2).volume_db, -12.0)
	check("and the mute has come on", s.track(2).mute)
	check("following is not history", s.undo_depth - depth == 3)

	# A send's level and an effect's parameter.
	var sender := -1
	var slot := -1
	for i in s.track_indices():
		for k in s.track(i).sends:
			if s.track(i).sends[k].dest_track > 0 and not s.track(i).sends[k].key:
				sender = i
				slot = k
	check("the demo has a send to automate", sender > 0)
	var dest: int = s.track(sender).sends[slot].dest_track
	DAW.set_automation(sender, "send:%d" % dest, [[0.0, -20.0, DawKitAutomation.HOLD]])
	var fx_track := -1
	for i in s.track_indices():
		if not s.track(i).plugins().is_empty():
			fx_track = i
			break
	var fx_index: int = s.track(fx_track).plugins()[0]
	DAW.set_automation(fx_track, "fx:%d:0" % fx_index, [[0.0, 0.25, DawKitAutomation.HOLD]])
	s.position_seconds = 0.5
	backend.follow_automation()
	close_to("the send follows its lane", backend.taper_to_db(s.track(sender).sends[slot].volume), -20.0, 0.01)
	close_to("so does the effect's parameter", float(s.fx(fx_track, fx_index).params[0]), 0.25)

	var guest := MixState.new()
	MixWire.apply_replicated(guest, MixWire.snapshot(s))
	check("a joining guest gets the lanes", guest.track(2).automation == s.track(2).automation
			and guest.track(sender).automation.has("send:%d" % dest))

	var p := ProjectBridge.capture(backend)
	var lane := p.track(ProjectBridge.id_of(sender)).automation_of("send:" + ProjectBridge.id_of(dest))
	check("the project names the send by its track's id", lane != null and p.problems().is_empty())
	var back := MixState.new()
	var other := GodotBackend.new()
	other.state = back
	check("loaded again (%s)" % [ProjectBridge.load(p, other)], back.track(2).automation == s.track(2).automation
			and back.track(fx_track).automation.has("fx:0:0")
			and back.track(sender).automation.has("send:%d" % dest))
	other.free()

	DAW.add_track(1, "")
	check("a send's lane follows its track when the tracks are renumbered",
			s.track(sender + 1).automation.has("send:%d" % (dest + 1)))
	DAW.undo()
	check("and back", s.track(sender).automation.has("send:%d" % dest))

	DAW.apply_intent(&"set_automation", [2, "gain", [0.0, 1.0, 0.0]])
	DAW.apply_intent(&"set_automation", [2, "volume", [1.0, 0.0, 0.0, 0.5, 0.0, 0.0]])
	DAW.apply_intent(&"set_automation", [2, "volume", [0.0, NAN, 0.0]])
	check("a guest's lane that is not one is refused (%s)" % [s.track(2).automation], not s.track(2).automation.has("gain")
			and s.track(2).automation["volume"].size() == 2)
	DAW.apply_intent(&"set_automation", [2, "pan", [0.0, 7.0, 0.0]])
	close_to("and a value past the control's end clamped", s.track(2).automation["pan"][0][1], 1.0)
	DAW.set_automation(2, "pan", [])
	check("an empty lane is no lane", not s.track(2).automation.has("pan"))

	# The master's volume and pan, as track 0.
	DAW.set_automation(0, "volume", [[0.0, -6.0, DawKitAutomation.HOLD], [4.0, -2.0, DawKitAutomation.HOLD]])
	s.position_seconds = 5.0
	backend.follow_automation()
	close_to("the master's fader follows its lane", s.master.volume_db, -2.0)
	close_to("its taper too", s.master.volume, backend.db_to_taper(-2.0))
	var mguest := MixState.new()
	MixWire.apply_replicated(mguest, MixWire.snapshot(s))
	check("a joining guest gets the master's lane", mguest.master.automation == s.master.automation)
	var mp := ProjectBridge.capture(backend)
	check("it is the project's master lane", mp.master.automation_of("volume") != null)
	var mback := GodotBackend.new()
	mback.state = MixState.new()
	ProjectBridge.load(mp, mback)
	check("and opened again", mback.state.master.automation == s.master.automation)
	mback.free()
	DAW.apply_intent(&"set_automation", [0, "mute", [0.0, 1.0, 0.0]])
	check("the master has no mute lane to set", not s.master.automation.has("mute"))
	DAW.undo()
	check("undone, the master has no lane", s.master.automation.is_empty())

	# Written from the desk. Track 3 in touch: the fader moved from 2 s to 3 s while playing.
	var t3 := s.track(3)
	DAW.set_track_volume(3, backend.db_to_taper(0.0))
	DAW.set_automation(3, "volume", [[0.0, -3.0, DawKitAutomation.HOLD]])
	DAW.set_track_automation_mode(3, DAW.AUTOMATION_TOUCH)
	depth = s.undo_depth
	s.playing = true
	for step in 11:
		s.position_seconds = 2.0 + step * 0.1
		DAW.set_track_volume(3, backend.db_to_taper(-6.0 - step))
		backend.follow_automation()
	close_to("while touched, the fader is where the hand puts it, not the written", t3.volume_db, -16.0, 0.05)
	check("and none of it is an undo step yet", s.undo_depth == depth)
	backend._passes[[3, "volume"]]["ms"] = 0
	s.position_seconds = 3.1
	backend.follow_automation()
	var written: Array = t3.automation["volume"]
	check("let go, the pass is one undo step", s.undo_depth == depth + 1)
	close_to("the written has what the hand did", DawKitAutomation.value_in(written, 2.5), -11.0, 0.05)
	close_to("what came before is as it was", DawKitAutomation.value_in(written, 1.0), -3.0)
	close_to("and after, it goes back to the written", DawKitAutomation.value_in(written, 3.0 + backend.RETURN_SECONDS + 0.1), -3.0)
	s.position_seconds = 5.0
	backend.follow_automation()
	close_to("which the fader then follows", t3.volume_db, -3.0)
	DAW.undo()
	check("undone, the written is as it was", t3.automation["volume"] == [[0.0, -3.0, DawKitAutomation.HOLD]])

	# Latch: the pan, moved once at 1 s, holds there until the transport stops at 4 s.
	DAW.set_track_automation_mode(3, DAW.AUTOMATION_LATCH)
	s.position_seconds = 1.0
	var pan_was := t3.pan * 2.0 - 1.0
	DAW.set_track_pan(3, 0.75)
	backend._passes[[3, "pan"]]["ms"] = 0
	s.position_seconds = 4.0
	backend.follow_automation()
	check("latch is not let go by a still hand", backend._passes.has([3, "pan"]))
	DAW.transport_stop()
	written = t3.automation.get("pan", [])
	close_to("stopped, the written holds the pan from the touch to the stop", DawKitAutomation.value_in(written, 3.9), 0.5)
	close_to("and where it was before it", DawKitAutomation.value_in(written, 0.5), pan_was)
	DAW.set_track_automation_mode(3, DAW.AUTOMATION_READ)
	s.playing = true
	DAW.set_track_volume(3, backend.db_to_taper(-1.0))
	check("in read, a fader moved while playing is a plain change", not backend._passes.has([3, "volume"]))
	s.playing = false
	DAW.apply_intent(&"set_track_automation_mode", [3, 3])
	check("a mode the desk does not offer is read", t3.automation_mode == DAW.AUTOMATION_READ)

	# The master, track 0, in touch: its fader moved from 2 s to 3 s while playing.
	DAW.set_master_volume(backend.db_to_taper(0.0))
	DAW.set_track_automation_mode(0, DAW.AUTOMATION_TOUCH)
	check("the master has a mode of its own", s.master.automation_mode == DAW.AUTOMATION_TOUCH
			and s.track_indices().all(func(i): return s.track(i).automation_mode == DAW.AUTOMATION_READ)
			and not s.tracks.has(0))
	var mtold := MixState.new()
	MixWire.apply_replicated(mtold, MixWire.snapshot(s))
	check("which a joining guest is told", mtold.master.automation_mode == DAW.AUTOMATION_TOUCH)
	depth = s.undo_depth
	s.playing = true
	for step in 11:
		s.position_seconds = 2.0 + step * 0.1
		DAW.set_master_volume(backend.db_to_taper(-6.0 - step))
		backend.follow_automation()
	close_to("touched, the master fader is where the hand puts it", s.master.volume_db, -16.0, 0.05)
	check("and none of it an undo step yet", s.undo_depth == depth)
	backend._passes[[0, "volume"]]["ms"] = 0
	s.position_seconds = 3.1
	backend.follow_automation()
	var master_written: Array = s.master.automation.get("volume", [])
	check("let go, the master's pass is one undo step, on the master's lane", s.undo_depth == depth + 1
			and not s.tracks.has(0))
	close_to("with what the hand did", DawKitAutomation.value_in(master_written, 2.5), -11.0, 0.05)
	close_to("and back to where it was after", DawKitAutomation.value_in(master_written, 3.0 + backend.RETURN_SECONDS + 0.1), 0.0)
	DAW.undo()
	DAW.set_track_automation_mode(0, DAW.AUTOMATION_LATCH)
	s.position_seconds = 1.0
	DAW.set_master_pan(0.25)
	s.position_seconds = 4.0
	backend.follow_automation()
	DAW.transport_stop()
	close_to("latched, the master's pan holds to the stop", DawKitAutomation.value_in(s.master.automation.get("pan", []), 3.9), -0.5)
	DAW.set_track_automation_mode(0, DAW.AUTOMATION_READ)
	_offline()


## The level a track sat at in a `shape` from `_test_tracks_are_added_removed_and_renamed`.
func _level_in(rows: Array, index: int) -> int:
	var level := 0
	for row in rows:
		if row[0] >= index:
			break
		level = maxi(level + row[2], 0)
	return level


## The last track inside the folder `index` opens.
func _folder_end(rows: Array, index: int) -> int:
	var level := 0
	for row in rows:
		if row[0] < index:
			continue
		level += row[2]
		if row[0] > index and level <= 0:
			return row[0]
	return rows.size()


## The mix, a guest's own keys and the room's clicks each play on a bus of their own, so each
## can leave the app on a stream of its own.
func _test_each_kind_of_sound_has_its_own_bus() -> void:
	AudioPorts.ensure_buses()
	var spent := AudioServer.get_bus_index(AudioPorts.SPENT)
	for kind in AudioPorts.KINDS:
		var b := AudioServer.get_bus_index(kind)
		check("the %s bus is there, after the one it is sent to when ported" % kind, b > spent and spent > 0)
		check("and plays to Master until then", AudioServer.get_bus_send(b) == &"Master")
	check("which, spent, is silent", AudioServer.is_bus_mute(spent))
	var click := Foley.emitter(AudioStreamWAV.new())
	check("the gear's sounds play on Gear", click.bus == AudioPorts.GEAR)
	click.free()
	var backend := GodotBackend.new()
	add_child(backend)
	backend._build_buses()
	check("the built-in engine's master plays into Mix",
			AudioServer.get_bus_send(backend._master_bus) == AudioPorts.MIX
			and backend._master_bus > AudioServer.get_bus_index(AudioPorts.MIX))
	backend._remove_buses()
	backend.free()
	var boot: Node = load("res://scenes/bootstrap.gd").new()
	check("--direct-audio keeps everything on one output",
			boot._parse(PackedStringArray(["--direct-audio"]))["direct_audio"]
			and not boot._parse(PackedStringArray([]))["direct_audio"])
	boot.free()
	var none := AudioPorts.new()
	none.player_tool = "dawlings-no-such-player"
	add_child(none)
	check("with no player, no ports", not none.open() and not AudioPorts.active and none.why_not != "")
	check("and the buses still play to Master",
			AudioServer.get_bus_send(AudioServer.get_bus_index(AudioPorts.GEAR)) == &"Master")
	none.queue_free()
	AudioPorts.why_not = ""


## Each kind's sound goes out to a player of its own, named for a patchbay, in raw stereo float,
## and not also out of the app's own output. A shell stands in for pacat and keeps what it gets.
func _test_every_sound_leaves_on_its_own_stream() -> void:
	var dir := OS.get_cache_dir().path_join("dawlings/tmp/ports")
	DirAccess.make_dir_recursive_absolute(dir)
	for kind in AudioPorts.KINDS:
		DirAccess.remove_absolute(dir.path_join("dawlings_%s.raw" % AudioPorts.NAMES[kind]))
		DirAccess.remove_absolute(dir.path_join("dawlings_%s.args" % AudioPorts.NAMES[kind]))
	var ports := AudioPorts.new()
	ports.player_tool = "sh"
	ports.player_prefix = PackedStringArray(["-c", ("for a; do case $a in --property=node.name=*) n=${a##*=};; esac; done; "
			+ "printf '%%s\\n' \"$@\" > '%s'/$n.args; exec cat > '%s'/$n.raw") % [dir, dir], "player"])
	add_child(ports)
	check("the ports open", ports.open() and AudioPorts.active and ports.ports.size() == 3)
	var gear := AudioServer.get_bus_index(AudioPorts.GEAR)
	check("a ported bus goes on into the silent one", AudioServer.get_bus_send(gear) == AudioPorts.SPENT)
	var tone := AudioStreamGenerator.new()
	tone.mix_rate = AudioPorts.RATE
	var player := AudioStreamPlayer.new()
	player.stream = tone
	player.bus = AudioPorts.GEAR
	add_child(player)
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	for i in 30:
		var frames := PackedVector2Array()
		frames.resize(playback.get_frames_available())
		frames.fill(Vector2(0.25, -0.5))
		playback.push_buffer(frames)
		await get_tree().create_timer(0.02).timeout
	var sent: int = ports.ports[AudioPorts.GEAR]["sent"]
	ports.close()
	player.queue_free()
	check("closed, the buses play to Master again", not AudioPorts.active
			and AudioServer.get_bus_send(gear) == &"Master" and ports.ports.is_empty())
	await get_tree().create_timer(0.1).timeout
	var said := FileAccess.get_file_as_string(dir.path_join("dawlings_gear.args"))
	check("the gear's stream is named for a patchbay",
			"--stream-name=dawlings · gear" in said and "--property=application.name=dawlings · gear" in said)
	check("and is raw stereo float at the mix rate",
			"--format=float32le" in said and "--channels=2" in said and "--rate=48000" in said)
	var raw := FileAccess.get_file_as_bytes(dir.path_join("dawlings_gear.raw"))
	check("the gear's sound reached its player (%d frames, %d bytes)" % [sent, raw.size()],
			sent > 0 and raw.size() == sent * 8)
	var samples := raw.to_float32_array()
	var found := false
	for i in range(0, samples.size() - 1, 2):
		if is_equal_approx(samples[i], 0.25) and is_equal_approx(samples[i + 1], -0.5):
			found = true
			break
	check("left and right, in that order", found)
	var mix := FileAccess.get_file_as_bytes(dir.path_join("dawlings_mix.raw")).to_float32_array()
	var quiet := true
	for v in mix:
		quiet = quiet and is_zero_approx(v)
	check("and none of it on the mix's stream", quiet)
	ports.queue_free()


## A named input hands over whole stereo frames however its pipe splits them: a part of one is
## kept for the next read.
func _test_a_named_input_is_read_whole_frames_at_a_time() -> void:
	var file := OS.get_cache_dir().path_join("dawlings/tmp/ports/in.raw")
	var bytes := PackedFloat32Array([0.5, -0.5, 0.25, -0.25, 1.0, -1.0]).to_byte_array()
	var tail := PackedFloat32Array([0.125, -0.125]).to_byte_array()
	var out := FileAccess.open(file, FileAccess.WRITE)
	out.store_buffer(bytes + tail.slice(0, 4))
	out.close()
	var piped := MixSource.Piped.new("Default", "Your microphone", "mic")
	check("the default device is left to the session manager", piped.device == ""
			and not ("--device" in " ".join(piped.arguments())))
	check("and the stream is named for a patchbay", "--stream-name=dawlings · mic" in piped.arguments()
			and "--property=node.name=dawlings_mic" in piped.arguments() and "--record" in piped.arguments())
	piped.tool = "sh"
	piped.prefix = PackedStringArray(["-c", "cat '%s'" % file, "parec"])
	check("it starts", piped.start())
	var got := PackedVector2Array()
	for i in 20:
		got.append_array(piped.read())
		if got.size() >= 3:
			break
		await get_tree().create_timer(0.02).timeout
	check("whole frames come out (%s)" % got, got == PackedVector2Array([Vector2(0.5, -0.5), Vector2(0.25, -0.25), Vector2(1.0, -1.0)]))
	check("and half of one waits for the rest", piped._spare.size() == 4)
	piped.stop()
	var tapped := MixSource.Piped.new("dawlings_tap", "tap", "mix tap")
	check("a device named is asked for", "--device=dawlings_tap" in tapped.arguments()
			and "--property=node.name=dawlings_mix_tap" in tapped.arguments())
	check("an input is Godot's own while the ports are shut",
			MixSource.input("", "x", "mic") is MixSource.Captured)


## The keys' own node (native/keys.c) is MonitorSynth in C: the same notes make the same sound,
## at the volume the app gives it (-6dB, which MonitorSynth leaves to its player).
func _test_the_keys_helper_plays_the_monitor_synth_note_for_note() -> void:
	var helper := NativeKeys.helper()
	check("the keys helper builds here", helper != "")
	if helper == "":
		return
	var file := OS.get_cache_dir().path_join("dawlings/tmp/ports/keys.raw")
	OS.execute("sh", ["-c", "printf 'on 60 100\\non 67 64\\noff 99\\n' | '%s' --render 9600 > '%s'" % [helper, file]])
	var native := FileAccess.get_file_as_bytes(file).to_float32_array()
	var synth := MonitorSynth.new()
	synth.allow_native = false
	add_child(synth)
	synth.note_on(60, 100)
	synth.note_on(67, 64)
	var ours := synth.render(9600)
	check("it renders what it was asked (%d samples)" % native.size(), native.size() == 9600 * 2)
	var worst := 0.0
	var loudest := 0.0
	for i in mini(ours.size(), native.size() / 2):
		worst = maxf(worst, absf(native[i * 2] / 0.5 - ours[i].x) + absf(native[i * 2 + 1] / 0.5 - ours[i].y))
		loudest = maxf(loudest, absf(ours[i].x))
	check("and it is the same sound (worst difference %.5f of %.3f)" % [worst, loudest], loudest > 0.05 and worst < 0.002)
	synth.free()


## The pedal: a key let go while it is down rings on, and stops when it comes up -- in both synths.
func _test_the_monitor_synth_holds_notes_under_the_pedal() -> void:
	var tail := func(make: Callable) -> float:
		var out: PackedVector2Array = make.call()
		var e := 0.0
		for i in range(out.size() - 4800, out.size()):
			e = maxf(e, absf(out[i].x))
		return e
	var played := func(pedal: bool, lift: bool) -> PackedVector2Array:
		var synth := MonitorSynth.new()
		synth.allow_native = false
		add_child(synth)
		synth.note_on(60, 100)
		synth.render(2400)
		if pedal:
			synth.sustain(true)
		synth.note_off(60)
		var out := synth.render(24000)
		if lift:
			synth.sustain(false)
			out = synth.render(24000)
		synth.free()
		return out
	var damped: float = tail.call(func(): return played.call(false, false))
	var held: float = tail.call(func(): return played.call(true, false))
	var lifted: float = tail.call(func(): return played.call(true, true))
	check("a key let go stops (%.4f)" % damped, damped < 0.001)
	check("under the pedal it rings on (%.4f)" % held, held > 0.02)
	check("until the pedal comes up (%.4f)" % lifted, lifted < 0.001)
	var helper := NativeKeys.helper()
	if helper == "":
		return
	var file := OS.get_cache_dir().path_join("dawlings/tmp/ports/keys_pedal.raw")
	OS.execute("sh", ["-c", "printf 'on 60 100\\nsus 1\\noff 60\\n' | '%s' --render 24000 > '%s'" % [helper, file]])
	var native := FileAccess.get_file_as_bytes(file).to_float32_array()
	var end := 0.0
	for i in range(native.size() - 9600, native.size(), 2):
		end = maxf(end, absf(native[i]))
	check("and the helper holds it too (%.4f)" % end, end > 0.01)


## What the helper says: MIDI it has played, with when it arrived; the sources it took; how late.
func _test_the_keys_helper_is_understood() -> void:
	var keys := NativeKeys.new()
	var now := 1000.0
	keys.hear("ready 48000 128", now)
	keys.hear("midi-from MPC Key 37 MIDI 1", now)
	keys.hear("midi-from MPC Key 37 MIDI 1", now)
	keys.hear("note 1 60 100 2 999990000", now)
	keys.hear("sus 1 2 999995000", now)
	keys.hear("note 0 60 0 2 1000000000", now)
	keys.hear("latency 4650", now)
	keys.hear("seq 128:0", now)
	check("it is ready", keys.ready)
	check("a source taken is named once", keys.devices == PackedStringArray(["MPC Key 37 MIDI 1"]))
	check("its latency is read (%.4f)" % keys.latency, is_equal_approx(keys.latency, 0.00465))
	var got := keys.take()
	check("its MIDI comes through in order", got.size() == 3 and got[0]["on"] and got[0]["pitch"] == 60
			and got[0]["velocity"] == 100 and got[0]["channel"] == 2 and got[1]["sustain"] and not got[2]["on"])
	check("aged by when it arrived (%.4f)" % got[0]["age"], is_equal_approx(got[0]["age"], 0.01)
			and is_equal_approx(got[2]["age"], 0.0))
	check("and taken once", keys.take().is_empty())
	var ports := AudioPorts.new()
	AudioPorts.target = "dawlings_null"
	check("every port plays where the app was told to", "--device=dawlings_null" in ports.player_args(AudioPorts.GEAR))
	ports.device = "elsewhere"
	check("unless it was told otherwise", "--device=elsewhere" in ports.player_args(AudioPorts.GEAR))
	AudioPorts.target = ""
	ports.free()


## A note the helper played reaches the app a frame later; it goes into the take where the key
## went down, not where the app heard about it.
func _test_a_note_the_helper_heard_is_stamped_when_it_went_down() -> void:
	_offline()
	_as_session(Session.Role.GUEST, 5)
	var gm := Session.guest_midi
	gm.heard_source = func() -> Dictionary:
		return {"seconds": 20.0, "playing": true, "recording": true, "valid": true}
	gm.target_track = 3
	gm.record_with_host = true
	gm.follow(gm.heard())
	gm.synth.native = NativeKeys.new()
	gm.synth._running = true
	gm.synth.native.latency = 0.005
	var now := Time.get_unix_time_from_system()
	gm.synth.native.hear("note 1 64 90 0 %d" % int((now - 0.03) * 1e6), now)
	gm._take_native_midi()
	check("the key is held", gm.held.get(64) == 90)
	var down: Array = gm._take._held.get("0:64", [-1.0]) if gm._take != null else [-1.0]
	check("stamped when it went down, plus its sound's way to the ear (%.4f)" % down[0],
			absf(down[0] - (20.0 - 0.03 + 0.005)) < 0.002)
	gm.synth.native = null
	gm.synth._running = false
	gm._take = null
	gm.held.clear()
	gm.heard_source = Callable()
	gm.target_track = 0
	Session.start_solo()


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


## THE BLEED-THROUGH THIS EXISTS FOR (docs/loop_backlog.md, "Known rough edges": "A ghost's
## caption ... is drawn over whatever is behind its head"). Confirmed with a screenshot before
## touching anything: a visitor placed behind the timeline's SCREEN-mode surface, close enough to
## the seat to be fully hidden by it, still showed "Lin" and "HOLDING KEYTAR" floating in the
## middle of the timeline -- `no_depth_test` skips the depth comparison outright, so the label
## drew over the nearer, opaque screen rather than being hidden by it the way the ghost's own
## head already was. Removed it (the engine default is the ordinary depth test); re-shot the
## same repro and the label is cut by the screen's edge exactly where the screen's mesh is, same
## as the head it floats above.
func _test_a_ghosts_name_and_caption_respect_what_is_in_front_of_them() -> void:
	var ghost := Presence.Avatar.new()
	for label in [ghost._tag, ghost._caption]:
		check("no_depth_test off, so the ordinary depth test hides it behind what is nearer",
				not label.no_depth_test)
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
	var path := OS.get_temp_dir().path_join("dawlings_test_look_%d.cfg" % OS.get_process_id())
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
				absf(at.origin.x) < half and at.origin.z < Studio.ROOM_BACK
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


func _test_their_monitor_plays_their_notes_where_they_heard_them() -> void:
	var monitor := TheirMonitor.new()
	add_child(monitor)
	var now := {"seconds": 10.0, "playing": true, "valid": true}
	monitor.heard_source = func() -> Dictionary: return now
	monitor.set_performers([7])
	var line: TheirMonitor.Line = monitor.lines[7]
	check("a performer listened to has a line on a bus of their own, held back by a first guess",
			monitor.performers() == [7] and AudioServer.get_bus_index(TheirMonitor.bus_of(7)) >= 0
			and is_equal_approx(line.delay, TheirMonitor.START_S))
	# Here the backing is at 10.0 - 0.08 = 9.92 in the line.
	monitor.play(Session.Note.ON, 60, 100, 7, 9.95)
	monitor.play(Session.Note.ON, 64, 100, 9, 9.95)
	check("a note played to 9.95 waits for the delayed backing to get there", line.sounded.is_empty()
			and line.waiting.size() == 1)
	now["seconds"] = 10.02
	monitor._process(0.0)
	check("not yet at 9.94", line.sounded.is_empty())
	now["seconds"] = 10.04
	monitor._process(0.0)
	check("and played when it is (%s)" % [line.sounded], line.sounded == [[Session.Note.ON, 60]])
	monitor.play(Session.Note.PEDAL_DOWN, 0, 0, 7, 9.80)
	check("a note later than the line allows is played at once, and the line grows to hold the next (%.3f, %.3f)"
			% [line.delay, line.last_late], line.sounded.size() == 2 and is_equal_approx(line.last_late, 0.16)
			and is_equal_approx(line.delay, TheirMonitor.START_S + 0.16 + TheirMonitor.MARGIN_S))
	monitor.play(Session.Note.OFF, 60, 0, 7, 9.85)
	check("so the next is in time again: it waits", line.sounded.size() == 2 and line.waiting.size() == 1)
	now["seconds"] = 10.12
	monitor._process(0.0)
	check("for the backing (%s)" % [line.sounded], line.sounded.size() == 3
			and line.sounded[2] == [Session.Note.OFF, 60])
	monitor.play(Session.Note.ON, 62, 90, 7, -1.0)
	check("one played with their transport stopped is played as it comes", line.sounded.size() == 4)
	monitor.play(Session.Note.ON, 67, 90, 7, 40.0)
	check("and one too far ahead to be one performance (a seek) too", line.sounded.size() == 5)
	monitor.play(Session.Note.ON, 69, 90, 7, 10.0)
	now["playing"] = false
	monitor._process(0.0)
	check("a note waiting when this machine stops is not kept", line.waiting.is_empty() and line.sounded.size() == 6)
	var grown := line.delay
	monitor.set_performers([7])
	check("asked again, the line it has stays as it is", monitor.lines[7] == line and line.delay == grown)
	monitor.set_performers([])
	check("nobody listened to, no lines", monitor.lines.is_empty())
	monitor.queue_free()
	await get_tree().process_frame


func _test_on_air_puts_a_monitor_socket_on_your_pack() -> void:
	_offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	_as_session(Session.Role.HOST, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	for spec in [[1, "Ada", 0], [7, "Lin", 1]]:
		var p := Session.Participant.new()
		p.peer_id = spec[0]
		p.display_name = spec[1]
		p.colour_index = spec[2]
		Session.participants[spec[0]] = p
	Session.roster_changed.emit()
	await get_tree().process_frame
	var ghost := studio.presence.avatar_of(7)
	check("off air, a pack has no monitor socket", ghost.monitor_send == null)
	studio._on_room_asked(&"patch", [1, &"monitor_7"], 1)
	check("and nobody can plug into one", not studio.patches.has(1))
	studio._on_room_asked(&"on_air", [true], 7)
	check("on air, their pack has a MONITOR socket (%s)" % [studio.on_air], studio.on_air == [7]
			and ghost.monitor_send != null and ghost.monitor_send.source == &"monitor_7"
			and ghost.monitor_send.title().contains("LIN'S MONITOR")
			and studio.room_state()["on_air"] == [7])
	var told: Array = []
	var listen := func(text: String): told.append(text)
	Session.notice.connect(listen)
	var hand := studio.get_node("MouseHand") as MouseInteractor
	var tablet := studio.items.items[&"tablet"] as TabletItem
	hand.pick_up(tablet)
	var sender: TabletFace.Sender = tablet.face._senders[1]
	sender.grab_begin(hand, sender.global_position)
	hand.hovered = ghost.monitor_send
	sender.grab_end(hand)
	hand.hovered = null
	check("plug B dropped on it is in it (%s)" % [studio.patches], studio.patches.get(1) == ["", "monitor_7", "", ""]
			and ghost.monitor_send.plug_count() == 1)
	check("and you are told it is in time, not live (%s)" % [told], told.size() == 1
			and (told[0] as String).contains("LIN'S MONITOR") and (told[0] as String).contains("In time with the backing"))
	check("its row says whose", (tablet.face._rows[1]["source"] as Label3D).text == "LIN'S MONITOR")
	# This person's own switch.
	tablet.face._air._on_grab_begin(Vector3.ZERO)
	check("the ON AIR key on your own tablet puts you on air, and says so (%s)" % [studio.on_air],
			studio.on_air == [1, 7] and tablet.face.on_air and (told[-1] as String).begins_with("On air"))
	tablet.face._air._on_grab_begin(Vector3.ZERO)
	check("and off", studio.on_air == [7] and not tablet.face.on_air)
	hand.lose_carrying()
	tablet.snap_home()
	var phones := studio.items.items[&"headphones"] as HeadphonesItem
	hand.pick_up(phones)
	hand.wear()
	var bus := TheirMonitor.bus_of(7)
	check("headphones on, their monitor is rebuilt here, on a bus of its own in your ears",
			studio.their_monitor.performers() == [7] and AudioServer.get_bus_index(bus) >= 0
			and is_zero_approx(Ears.gain_db(bus)))
	var line: TheirMonitor.Line = studio.their_monitor.lines[7]
	Session.note_played.emit(Session.Note.ON, 60, 100, 7, -1.0)
	check("their notes reach it", line.sounded == [[Session.Note.ON, 60]])
	studio._on_room_asked(&"on_air", [false], 7)
	check("off air, the plug comes back to its tray, the socket goes, and nothing is rebuilt",
			not studio.patches.has(1) and ghost.monitor_send == null
			and studio.their_monitor.performers().is_empty())
	studio._on_room_asked(&"on_air", [true], 7)
	Session.participants.erase(7)
	Session.roster_changed.emit()
	await get_tree().process_frame
	check("whoever leaves is not on air any more", studio.on_air.is_empty())
	Session.notice.disconnect(listen)
	hand.take_off()
	hand.lose_carrying()
	phones.snap_home()
	studio.queue_free()
	await get_tree().process_frame
	_as_session(Session.Role.SOLO, 1)
	Session.layout = saved_layout


func _test_a_shaker_plays_when_a_stroke_stops() -> void:
	var shaker := ShakerItem.new()
	add_child(shaker)
	var hits: Array = []
	shaker.played.connect(func(v: int, struck: bool) -> void: hits.append([v, struck]))
	var dt := 1.0 / 60.0
	var at := Vector3.ZERO
	# Drifting the hand about is not playing it.
	for i in 30:
		at.x += 0.2 * dt
		shaker._since += dt
		shaker.feel(at, dt)
	at.x -= 0.0
	for i in 5:
		shaker._since += dt
		shaker.feel(at, dt)
	check("moving it slowly plays nothing (%s)" % [hits], hits.is_empty())
	# A brisk stroke one way, brought up short.
	for i in 6:
		at.x += 1.6 * dt
		shaker._since += dt
		shaker.feel(at, dt)
	shaker._since += dt
	shaker.feel(at, dt)
	check("a stroke that stops is one hit (%s)" % [hits], hits.size() == 1 and not hits[0][1])
	check("as hard as the stroke was fast", hits.size() == 1 and hits[0][0] == InstrumentItem.velocity_for(1.6))
	# Back the other way, harder: the turn is the next hit.
	for i in 6:
		at.x -= 2.4 * dt
		shaker._since += dt
		shaker.feel(at, dt)
	for i in 6:
		at.x += 2.4 * dt
		shaker._since += dt
		shaker.feel(at, dt)
	check("turned round, a stroke the other way is a hit too, and harder (%s)" % [hits],
			hits.size() == 2 and hits[1][0] > hits[0][0])
	check("velocities run from soft to full", InstrumentItem.velocity_for(0.1) == 0
			and InstrumentItem.velocity_for(InstrumentItem.STROKE_MIN) == 40
			and InstrumentItem.velocity_for(9.0) == 127)
	# Strokes faster than the beads can cross are one hit.
	hits.clear()
	shaker._since = 0.0
	for i in 2:
		at.y += 2.0 * dt
		shaker.feel(at, dt)
	shaker.feel(at, dt)
	check("a stop sooner than the beads can travel is not a second hit", hits.is_empty())
	shaker.use(true)
	check("loose, a click is heard in the room, not played (%s)" % [hits], hits.is_empty())
	shaker.queue_free()

	# A mouse shakes it by wiggling: the hand follows the cursor a little way and springs back.
	var hand := MouseInteractor.new()
	add_child(hand)
	hand.wiggle(Vector2(400, 300), dt)
	check("with nothing in the hand, the mouse does not wiggle it", hand.shake_point() == Vector3.ZERO)
	var shaken := ShakerItem.new()
	add_child(shaken)
	hand.carrying = shaken
	hand.wiggle(Vector2(400, 300), dt)
	hand.wiggle(Vector2(460, 300), dt)
	var moved := hand.shake_point()
	check("with an instrument, a flick of the mouse moves the hand that way (%s)" % moved, moved.x > 0.02
			and moved.x <= MouseInteractor.WIGGLE_MOST)
	for i in 60:
		hand.wiggle(Vector2(460, 300), dt)
	check("and it springs back when the mouse rests (%s)" % hand.shake_point(), hand.shake_point().length() < 0.002)
	hand.wiggle(Vector2(5000, 300), dt)
	check("however far the flick, the hand moves a little", hand.shake_point().x <= MouseInteractor.WIGGLE_MOST + 1e-6)
	hand.carrying = null
	shaken.queue_free()
	hand.queue_free()
	await get_tree().process_frame


func _test_percussion_is_heard_by_the_room_and_recorded_onto_the_armed_track() -> void:
	_offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	_as_session(Session.Role.SOLO, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	var shaker := room.items.get(&"shaker") as ShakerItem
	var tambourine := room.items.get(&"tambourine") as TambourineItem
	check("there is a shaker and a tambourine, at home", shaker != null and tambourine != null
			and shaker.state == Item.State.HOME and tambourine.state == Item.State.HOME)
	var wrong: Array = []
	for id in Venue.IDS:
		studio.set_venue(id, false)
		var shelf := studio.venue.prop_shelf_spot()
		for spec in [[shaker, studio.venue.shaker_spot()], [tambourine, studio.venue.tambourine_spot()]]:
			var item: Item = spec[0]
			var local: Vector3 = shelf.affine_inverse() * item.home.origin
			if not item.home.is_equal_approx(spec[1]) or not item.own_home \
					or not is_equal_approx(local.y, ZoneKit.SHELF_LOWER_TOP) \
					or absf(local.x) > ZoneKit.SHELF.x * 0.5 - 0.14 or absf(local.z) > ZoneKit.SHELF.z * 0.5 - 0.1:
				wrong.append([id, item.id])
	check("in every venue they lie on the shelf's lower tier (%s)" % [wrong], wrong.is_empty())
	studio.set_venue(&"studio", false)
	var tablet_x := (studio.venue.prop_shelf_spot().affine_inverse() * studio.venue.tablet_spot().origin).x
	var apart := func(a: Vector3, b: Vector3) -> float:
		var shelf := studio.venue.prop_shelf_spot().affine_inverse()
		return absf((shelf * a).x - (shelf * b).x)
	check("clear of each other and of the tablet", apart.call(shaker.home.origin, tambourine.home.origin)
			> TambourineItem.RADIUS + 0.03 and tablet_x - (studio.venue.prop_shelf_spot().affine_inverse()
			* shaker.home.origin).x > 0.15)

	var hand := studio.get_node("MouseHand") as MouseInteractor
	var played: Array = []
	room.played.connect(func(item: InstrumentItem, v: int, struck: bool) -> void: played.append([item.id, v, struck]))
	hand.pick_up(shaker)
	shaker.use(true)
	check("in the hand, a click strikes it, firmly (%s)" % [played],
			played == [[&"shaker", InstrumentItem.STRUCK, true]])
	var mine := shaker.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer)
	check("and you hear it at once, on your own keys' bus", mine.size() == 1
			and (mine[0] as AudioStreamPlayer).bus == AudioPorts.bus(AudioPorts.MONITOR))

	# The take: hits stamped by the song position heard, onto the first armed track.
	var heard := {"seconds": 10.0, "playing": true, "recording": false, "valid": true}
	var rec := studio.hit_recorder
	rec.heard_source = func() -> Dictionary: return heard
	var told: Array = []
	var listen := func(text: String): told.append(text)
	Session.notice.connect(listen)
	for t: MixState.TrackState in DAW.state.tracks.values():
		t.rec_arm = false
	heard["recording"] = true
	rec.follow(heard)
	shaker.play(90)
	check("recording with nothing armed, the hit has nowhere to go, and you are told once (%s)" % [told],
			not rec.is_recording() and told.size() == 1 and (told[0] as String).contains("Arm a track"))
	shaker.play(90)
	check("only once", told.size() == 1)
	heard["recording"] = false
	rec.follow(heard)
	DAW.state.track(5).rec_arm = true
	DAW.state.track(3).rec_arm = true
	var before := DAW.state.track(3).items.size()
	heard["seconds"] = 20.0
	heard["recording"] = true
	rec.follow(heard)
	check("recording with a track armed, a take is running", rec.is_recording())
	heard["seconds"] = 20.5
	shaker.play(100)
	var lands := 20.5 + AudioServer.get_output_latency()
	heard["seconds"] = 21.25
	hand.lose_carrying()
	shaker.snap_home()
	hand.pick_up(tambourine)
	tambourine.use(true)
	heard["seconds"] = 22.0
	heard["recording"] = false
	rec.follow(heard)
	check("stopped, the take lands on the first armed track (%s)" % [rec.last_take],
			DAW.state.track(3).items.size() == before + 1 and rec.last_take.get("track") == 3
			and rec.last_take.get("notes") == 2)
	var taken := DAW.state.track(3).items.filter(func(it: MixState.ItemState) -> bool: return it.name.contains("percussion"))
	check("the take is named for the percussion", taken.size() == 1)
	var item: MixState.ItemState = taken.front() if taken.size() == 1 else MixState.ItemState.new()
	var notes := MidiTake.unpack_relative(item.notes, item.start)
	check("each hit a drum note, where it was heard (%s)" % [notes], notes.size() == 2
			and is_equal_approx(notes[0][0], lands) and notes[0][2] == ShakerItem.new().pitch() and notes[0][3] == 100
			and notes[0][4] == HitRecorder.CHANNEL and notes[1][2] == 54 and notes[1][3] == InstrumentItem.STRUCK
			and is_equal_approx(notes[0][1] - notes[0][0], InstrumentItem.NOTE_SECONDS))
	Session.notice.disconnect(listen)

	# Somebody else's: heard in the room from their hand, and only from whoever has it.
	hand.lose_carrying()
	tambourine.snap_home()
	var sounds_before := tambourine._take
	studio.presence._item_holders[&"tambourine"] = 7
	Session.item_hit.emit(&"tambourine", 80, 9)
	check("a hit from somebody not holding it is not played", tambourine._take == sounds_before)
	Session.item_hit.emit(&"tambourine", 80, 7)
	check("one from whoever has it is", tambourine._take == sounds_before + 1)
	studio.presence._item_holders.erase(&"tambourine")
	studio.queue_free()
	await get_tree().process_frame
	_as_session(Session.Role.SOLO, 1)
	Session.layout = saved_layout


func _test_a_keytar_plays_your_keys_and_shows_them() -> void:
	# A host on Reaper, which records its own keys: here only a keytar makes them the game's.
	_offline().records_inputs = true
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	_as_session(Session.Role.SOLO, 1)
	var gm := Session.guest_midi
	var saved_heard := gm.heard_source
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var keytar := studio.items.items.get(&"keytar") as KeytarItem
	check("there is a keytar, at home, with its 25 keys", keytar != null and keytar.state == Item.State.HOME
			and keytar.keys.size() == KeytarItem.KEYS)
	check("a note is shown on its own key, or the same note an octave in", KeytarItem.key_of(48) == 0
			and KeytarItem.key_of(72) == 24 and KeytarItem.key_of(36) == 0 and KeytarItem.key_of(85) == 13)
	var wrong: Array = []
	for id in Venue.IDS:
		studio.set_venue(id, false)
		var shelf := studio.venue.prop_shelf_spot()
		var local: Transform3D = shelf.affine_inverse() * keytar.home
		# Standing on its edge, keys out: its body's front edge is on the low peg.
		var edge := local * Vector3(0, 0, KeytarItem.FRONT_EDGE)
		if not keytar.home.is_equal_approx(studio.venue.keytar_spot()) or not keytar.own_home \
				or not is_equal_approx(edge.y, ZoneKit.KEYTAR_REST) or local.basis.y.dot(Vector3.BACK) < 0.99 \
				or absf(edge.z - ZoneKit.KEYTAR_BACK_Z) > 0.001:
			wrong.append(id)
	check("in every venue it stands on its rack at the back of the shelf, keys out (%s)" % [wrong], wrong.is_empty())
	check("the rack is inside the shelf's footprint", ZoneKit.KEYTAR_PEGS.all(func(p: Vector2) -> bool:
			return absf(p.x) < ZoneKit.SHELF.x * 0.5) and ZoneKit.KEYTAR_BACK_Z + ZoneKit.KEYTAR_PEG_REACH < 0.0)
	studio.set_venue(&"studio", false)

	var hand := studio.get_node("MouseHand") as MouseInteractor
	var told: Array = []
	var listen := func(text: String): told.append(text)
	Session.notice.connect(listen)
	hand.pick_up(keytar)
	studio._process(0.016)
	check("in your hand, your keys play it, alone too", gm.keytar and gm.plays())
	check("and on a desktop the computer keyboard is its piano, and you are told how, arrows and all (%s)" % [told],
			studio.keytar_keys.is_active() and told.size() == 1 and (told[0] as String).contains("arrows walk"))
	check("its piano lets the arrows walk", studio.keytar_keys.is_in_group(KeyCatcher.WALKS_ON_ARROWS))
	studio.keytar_keys.handle(KEY_A, true)
	studio.keytar_keys.handle(KEY_E, true)
	check("a key down plays the note, and its key on the keytar goes down and lights (%s)" % [gm.held],
			gm.held.has(60) and gm.held.has(63) and keytar.is_down(60) and keytar.is_down(63)
			and is_equal_approx(keytar.keys[12].rotation.x, KeytarItem.PRESS) and keytar.keys[12].material_override != null)
	studio.keytar_keys.handle(KEY_A, false)
	check("let go, it comes up", not gm.held.has(60) and not keytar.is_down(60)
			and is_zero_approx(keytar.keys[12].rotation.x) and keytar.keys[12].material_override == null)
	studio.keytar_keys.set_active(false)
	keytar.use(true)
	check("the keys given back, a click with it in hand takes them again", studio.keytar_keys.is_active())
	var walker := studio.walker
	walker.active = true
	walker.velocity = Vector3.ZERO
	var up := InputEventKey.new()
	up.physical_keycode = KEY_UP
	up.pressed = true
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	for i in 10:
		walker._physics_process(1.0 / 60.0)
	var moving := Vector2(walker.velocity.x, walker.velocity.z).length()
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	walker.velocity = Vector3.ZERO
	check("with the keytar's piano on, the arrows walk you (%.2f m/s)" % moving, moving > 0.5
			and studio.keytar_keys.is_active())

	# A take, onto the armed track, by the song position heard.
	for t: MixState.TrackState in DAW.state.tracks.values():
		t.rec_arm = false
	DAW.state.track(4).rec_arm = true
	var heard := {"seconds": 30.0, "playing": true, "recording": true, "valid": true}
	gm.heard_source = func() -> Dictionary: return heard
	gm.follow(gm.heard())
	check("recording, with no track chosen, a take runs for the armed one", gm.is_recording() and gm.take_track() == 4)
	heard["seconds"] = 30.5
	studio.keytar_keys.handle(KEY_D, true)
	heard["seconds"] = 31.0
	studio.keytar_keys.handle(KEY_D, false)
	studio.keytar_keys.handle(KEY_E, false)
	heard["recording"] = false
	gm.follow(gm.heard())
	var taken := DAW.state.track(4).items.filter(func(it: MixState.ItemState) -> bool: return it.name.contains("keytar"))
	check("stopped, the keytar's take lands on the armed track (%s)" % [gm.last_take], taken.size() == 1
			and gm.last_take.get("track") == 4)
	if taken.size() == 1:
		var notes := MidiTake.unpack_relative(taken[0].notes, taken[0].start)
		check("with its notes where they were heard (%s)" % [notes], notes.any(func(n: Array) -> bool:
				return n[2] == 64 and is_equal_approx(n[0], 30.5) and is_equal_approx(n[1], 31.0)))

	hand.lose_carrying()
	keytar.snap_home()
	studio._process(0.016)
	check("put down, your keys are a guest's again and the keyboard is the studio's",
			not gm.keytar and not gm.plays() and not studio.keytar_keys.is_active() and gm.held.is_empty())

	# Somebody else's keytar: their notes play out of it, and show on it.
	studio.presence._item_holders[&"keytar"] = 7
	Session.note_played.emit(Session.Note.ON, 62, 90, 9, -1.0)
	check("notes from someone not holding it do not", not keytar.is_down(62))
	Session.note_played.emit(Session.Note.ON, 62, 90, 7, -1.0)
	var room := keytar.get_node_or_null("Room") as MonitorSynth
	check("notes from whoever has it play out of it, into the room, and press its keys", keytar.is_down(62)
			and room != null and room.speaker == keytar)
	Session.note_played.emit(Session.Note.OFF, 62, 0, 7, -1.0)
	check("and let go", not keytar.is_down(62))
	studio.presence._item_holders.erase(&"keytar")

	Session.notice.disconnect(listen)
	gm.heard_source = saved_heard
	studio.queue_free()
	await get_tree().process_frame
	_as_session(Session.Role.SOLO, 1)
	Session.layout = saved_layout


func _test_chips_and_cards_do_their_tricks_in_turn() -> void:
	_offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	_as_session(Session.Role.SOLO, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var chips := studio.items.items.get(&"chips") as ChipsItem
	var cards := studio.items.items.get(&"cards") as CardsItem
	check("there are chips and a deck of cards, at home", chips != null and cards != null
			and chips.state == Item.State.HOME and cards.state == Item.State.HOME
			and chips.chips.size() == ChipsItem.COUNT and cards.cards.size() == CardsItem.LOOSE)
	var wrong: Array = []
	for id in Venue.IDS:
		studio.set_venue(id, false)
		var shelf := studio.venue.prop_shelf_spot()
		for item: Item in [chips, cards]:
			var local: Transform3D = shelf.affine_inverse() * item.home
			# On the shelf's top, in front of the toys and inside its edge.
			if not item.own_home or not is_equal_approx(local.origin.y, ZoneKit.SHELF.y) \
					or local.origin.z < 0.1 or local.origin.z > ZoneKit.SHELF.z * 0.5 - 0.04 \
					or absf(local.origin.x) > ZoneKit.SHELF.x * 0.5 - 0.06:
				wrong.append("%s:%s" % [id, item.id])
		for spot: Transform3D in studio.venue.item_spots():
			if spot.origin.distance_to(chips.home.origin) < 0.08 or spot.origin.distance_to(cards.home.origin) < 0.08:
				wrong.append("%s: crowds a toy" % id)
	check("in every venue they lie at the front corners of the shelf's top, clear of the toys (%s)" % [wrong],
			wrong.is_empty())
	studio.set_venue(&"studio", false)

	# The chips: riffle, flip, cut, in turn; a press mid-trick finishes it.
	var hand := studio.get_node("MouseHand") as MouseInteractor
	hand.pick_up(chips)
	check("in the hand, a click offers the riffle", chips.hint().contains("riffle"))
	var used: Array = []
	var on_used := func(item: Item, down: bool): used.append([item.id, down])
	studio.items.used.connect(on_used)
	chips.work(true)
	chips.work(false)
	check("a click starts the riffle, and is told to the room", chips.playing == 0 and used.size() == 2
			and used[0] == [&"chips", true])
	chips.pose(0, 0.3)
	var lows: Array = []
	var highs: Array = []
	for i in ChipsItem.COUNT:
		(lows if chips.chips[i].position.x < -0.01 else highs).append(i)
	check("split, the bottom half to the left and the top half to the right (%s %s)" % [lows, highs],
			lows == [0, 1, 2, 3, 4, 5] and highs == [6, 7, 8, 9, 10, 11])
	chips.work(true)
	check("the next click finishes it at once, stack square and the halves riffled, and starts the flip",
			chips.playing == 1 and chips.order == [0, 6, 1, 7, 2, 8, 3, 9, 4, 10, 5, 11] and _stack_square(chips))
	var top := chips.chips[chips.order[ChipsItem.COUNT - 1]]
	chips.pose(1, 0.5)
	check("a flip throws the top chip up off the stack, turning", top.position.y > 0.1 and absf(top.rotation.x) > 1.0)
	for f in 80:
		chips._process(0.016)
	check("and it lands back on top: the trick plays out by itself", chips.playing == -1 and _stack_square(chips)
			and is_equal_approx(top.position.y, (ChipsItem.COUNT - 1) * ChipsItem.THICK))
	var was := chips.order.duplicate()
	chips.work(true)
	chips.finish()
	check("a cut puts the top four under the rest", chips.order == was.slice(8) + was.slice(0, 8) and _stack_square(chips))
	check("and then it is a riffle again", chips.next_trick() == 0)
	# Somebody else's copy, played the same clicks, ends the same.
	var twin := ChipsItem.new()
	add_child(twin)
	for n in 3:
		twin.use(true)
		twin.use(false)
	twin.finish()
	check("another copy given the same clicks stacks the same", twin.order == chips.order)
	twin.queue_free()
	hand.lose_carrying()
	chips.go_home()
	check("put down, it is a plain stack again and starts over", chips.tricks_done == 0 and chips.playing == -1
			and _stack_square(chips))

	# The cards: shuffle, fan, square up.
	hand.pick_up(cards)
	check("in the hand, a click offers a shuffle", cards.hint().contains("shuffle"))
	cards.work(true)
	cards.pose(0, 0.3)
	check("a shuffle splits the deck into halves either side", cards.lower.position.x < -0.03
			and cards.upper.position.x > 0.03 and cards.upper.position.y < 0.001)
	cards.work(true)
	check("finished, the halves are square again and their cards riffled together",
			cards.order == [0, 4, 1, 5, 2, 6, 3, 7] and cards.lower.position == Vector3.ZERO
			and cards.upper.position.is_equal_approx(Vector3(0, CardsItem.BLOCK_H, 0)) and cards.playing == 1)
	var faces := {}
	for c in cards.dealt:
		faces[c] = true
	check("a fan deals seven different cards (%s)" % [cards.dealt.map(CardsItem.card_name)],
			cards.dealt.size() == CardsItem.FAN and faces.size() == CardsItem.FAN
			and cards.dealt.all(func(c: int) -> bool: return c >= 0 and c < 52))
	cards.pose(1, 1.0)
	var fanned := cards.cards[cards.order[CardsItem.LOOSE - 1]]
	var first := cards.cards[cards.order[CardsItem.LOOSE - CardsItem.FAN]]
	check("fanned, face up and spread either way", fanned.basis.y.dot(Vector3.UP) < -0.99
			and first.basis.y.dot(Vector3.UP) < -0.99 and fanned.basis.z.x * first.basis.z.x < 0.0)
	check("the names of the cards", CardsItem.card_name(0) == "A♠" and CardsItem.card_name(51) == "K♣"
			and CardsItem.card_name(22) == "10♥")
	var dealt := cards.dealt.duplicate()
	cards.work(true)
	cards.finish()
	check("square, every card face down on the deck again", cards.cards.all(func(c: Node3D) -> bool:
			return c.basis.is_equal_approx(Basis.IDENTITY)) and cards.playing == -1)
	var deck := CardsItem.new()
	add_child(deck)
	deck.use(true)
	deck.use(true)
	check("another copy given the same clicks deals the same hand", deck.dealt == dealt)
	deck.queue_free()
	cards.work(true)
	cards.work(true)
	check("the next fan deals another hand", cards.dealt != dealt)
	hand.lose_carrying()
	cards.go_home()
	check("put down, the fan is folded away", cards.playing == -1 and cards.tricks_done == 0
			and cards.cards.all(func(c: Node3D) -> bool: return c.basis.is_equal_approx(Basis.IDENTITY)))

	studio.items.used.disconnect(on_used)
	studio.queue_free()
	await get_tree().process_frame
	_as_session(Session.Role.SOLO, 1)
	Session.layout = saved_layout


## Every chip on the one below it, in `order`, square.
func _stack_square(chips: ChipsItem) -> bool:
	for slot in ChipsItem.COUNT:
		var chip := chips.chips[chips.order[slot]]
		if not chip.position.is_equal_approx(Vector3(0, slot * ChipsItem.THICK, 0)) or chip.rotation.x != 0.0 \
				or chip.rotation.z != 0.0:
			return false
	return true


## Pockets (docs/items_loop.md): more than one thing carried, the rest on your hips and back.
func _test_pockets_carry_more_than_one_thing() -> void:
	_as_session(Session.Role.SOLO, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	var hand := studio.get_node("MouseHand") as MouseInteractor
	var duck := room.items[&"duck"] as Item
	var ball := room.items[&"ball"] as Item
	var plane := room.items[&"plane"] as Item
	var cradle := room.items[&"cradle"] as CradleItem
	var shaker := room.items[&"shaker"] as Item
	check("a hand has pockets, and they are this machine's person's", hand.pockets != null and hand.pockets == Pockets.mine())
	hand.pockets._slots = [null, null, null]

	hand.pick_up(duck)
	check("a number key puts what is in the hand in that pocket", hand.swap_pocket(0)
			and hand.carrying == null and duck.state == Item.State.HELD and duck.pocket == 0
			and hand.pockets.at(0) == duck and not duck.in_hand())
	check("and the room has it in a pocket", room.state().get(&"duck") == ["pocket", 0])
	duck._physics_process(1.0 / 60.0)
	check("with no ghost of yours to wear it, it is not drawn in your view", not duck.body.visible)
	check("an empty pocket's key does nothing", not hand.swap_pocket(2))
	hand.pick_up(ball)
	hand.pick_up(plane)
	check("picking up with a full hand pockets what was in it, in the first free pocket",
			hand.carrying == plane and ball.pocket == 1 and hand.pockets.at(1) == ball and ball.state == Item.State.HELD)
	hand.swap_pocket(0)
	check("a full hand and a full pocket swap", hand.carrying == duck and duck.pocket == -1 and plane.pocket == 0
			and room.state().get(&"duck") == [] and hand.pockets.summary() == "1 paper plane · 2 bouncy ball · 3 —")
	hand.cycle_pockets(1)
	check("the wheel swaps the hand for the next full pocket", hand.carrying == plane and duck.pocket == 0)
	hand.cycle_pockets(1)
	check("and round again", hand.carrying == ball and plane.pocket == 1 and duck.pocket == 0)
	hand.pick_up(shaker)
	check("all three full", hand.pockets.free_slot() == -1 and hand.pockets.items().size() == 3)
	hand.pick_up(cradle)
	check("and then a full hand's goes home, as it always did", shaker.state == Item.State.HOME and hand.carrying == cradle)

	# A toy mid-trick stops when it is pocketed.
	hand.swap_pocket(2)
	check("reaching for your own pocketed thing with a full hand swaps them", hand.carrying == ball and cradle.pocket == 2)
	hand.pick_up(cradle)
	check("both ways", hand.carrying == cradle and ball.pocket == 2)
	cradle.work(true)
	cradle.work(false)
	check("a cradle in the hand swings", cradle.playing >= 0)
	hand.swap_pocket(2)
	check("pocketed, it stops", cradle.playing < 0 and cradle.pocket == 2 and hand.carrying == ball)

	# Sent home by the room, a pocket is empty again.
	duck.snap_home()
	check("a thing sent home from a pocket is out of it", hand.pockets.at(0) == null and duck.pocket == -1)

	# Another machine's copy, told by the room.
	var other := ItemRoom.new()
	add_child(other)
	await get_tree().process_frame
	var copy := other.items[&"plane"] as Item
	copy.follow(func() -> Transform3D: return Transform3D.IDENTITY)
	other.apply({&"plane": ["pocket", 1]})
	check("a copy told it is in somebody's pocket puts it there, and it cannot be taken out of it",
			copy.pocket == 1 and copy._shape.disabled)
	other.apply({&"plane": []})
	check("and back in their hand when they take it out", copy.pocket == -1 and not copy._shape.disabled)
	other.queue_free()

	# On a ghost: either hip and across the back.
	var ghost := Presence.Avatar.new()
	add_child(ghost)
	ghost.snap(Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)))
	var left := ghost.pocket_pose(0).origin
	var right := ghost.pocket_pose(1).origin
	var back := ghost.pocket_pose(2).origin
	var middle := ghost._lean.global_position
	check("a ghost's pockets are at its two sides, low (%s %s)" % [left, right],
			signf(left.x - middle.x) != signf(right.x - middle.x) and left.y < 1.6 - 0.2 and absf(left.y - right.y) < 0.001)
	check("and one on its back, higher, behind (%s)" % back, back.z > middle.z + 0.1 and back.y > left.y)
	ghost.queue_free()

	# Claimed with the host while in a pocket, and let go when it leaves it for home.
	_as_session(Session.Role.HOST, 1)
	Session.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Session._register(1, "Ada", 0)
	var presence := studio.presence
	presence.claim_carries()
	check("what is in a pocket is still claimed", Session.holder_of(plane.network_key()) == 1
			and Session.holder_of(cradle.network_key()) == 1)
	plane.snap_home()
	presence.claim_carries()
	check("and let go of once it is not", Session.holder_of(plane.network_key()) == 0)

	for item in [duck, ball, plane, cradle, shaker]:
		item.snap_home()
	hand.pockets._slots = [null, null, null]
	studio.queue_free()
	await get_tree().process_frame
	_as_session(Session.Role.SOLO, 1)


## Every venue has a toy of its own (docs/items_loop.md): one item, the room's look and flight.
func _test_each_venue_has_a_toy_of_its_own() -> void:
	_as_session(Session.Role.SOLO, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var toy := studio.items.items.get(&"toy") as ToyItem
	check("the room has a toy", toy != null)
	if toy == null:
		studio.queue_free()
		return

	# In every venue: its own, lying on floor you can walk up to, clear of everything.
	var wrong: Array = []
	var titles := {}
	for id in Venue.IDS:
		studio.set_venue(id, false)
		titles[toy.item_title()] = true
		if toy.venue != id or not ToyItem.TOYS.has(id):
			wrong.append("%s: the toy is %s's" % [id, toy.venue])
		var meshes := toy.body.find_children("*", "MeshInstance3D", true, false)
		if meshes.size() != 1 or meshes[0].name != ToyItem.TOYS[id]["model"]:
			wrong.append("%s: looks wrong" % id)
		var spot := studio.venue.toy_spot()
		if not toy.home.origin.is_equal_approx(spot.origin):
			wrong.append("%s: lives somewhere else" % id)
		var reach := float(ToyItem.TOYS[id]["size"])
		for way in [Vector3.ZERO, Vector3(reach, 0, 0), Vector3(-reach, 0, 0), Vector3(0, 0, reach), Vector3(0, 0, -reach)]:
			var at: Vector3 = spot.origin + way
			if not studio.walker.reachable.call(Vector2(at.x, at.z)) \
					or Flight._over_solid(studio.walker.fixed, Vector2(at.x, at.z)):
				wrong.append("%s: lies where it cannot be reached" % id)
				break
	check("every venue has its own toy, lying where it can be picked up (%s)" % [wrong], wrong.is_empty())
	check("and no two are the same toy", titles.size() == Venue.IDS.size())

	# Changed under a hand: still in it, and now the new room's.
	studio.set_venue(&"studio", false)
	check("at home it lies by the hoop", toy.readout() == "by the hoop")
	var hand := studio.get_node("MouseHand") as MouseInteractor
	hand.pick_up(toy)
	studio.set_venue(&"cabin", false)
	check("a toy in a hand when the venue changes stays in it, and is the new venue's",
			toy.state == Item.State.HELD and hand.carrying == toy and toy.item_title() == "SNOWBALL"
			and toy.body.find_child("Snowball", true, false) != null and toy.body.get_parent() == toy)
	var look := ItemRoom.look_of(&"toy")
	check("and a ghost carrying it carries a snowball too", look != null and look.find_child("Snowball", true, false) != null)
	if look != null:
		look.free()

	# Each flies as what it is: a snowball lands and stays, a neon ball bounces; a beach ball is
	# all air; a starfish is not round, so a hoop is not there for it.
	var stand := studio.items.global_transform * (studio.venue.toy_spot() * Vector3(0, 1.5, 0.3))
	var aim := studio.items.global_transform * (studio.venue.toy_spot() * Vector3(0, 0, 3.5))
	var flights := {}
	for id in [&"cabin", &"grid", &"rooftop", &"loft"]:
		studio.set_venue(id, false)
		hand.pick_up(toy)
		studio.items.throw(toy, stand, ItemRoom.lob(stand, aim, 6.0), Vector3.ZERO)
		flights[id] = toy.flight
		toy.snap_home()
	var floor_hits := func(f: Flight) -> int:
		return Array(f.hit_on).count(Flight.FLOOR) if f != null else -1
	check("a snowball lands and stays where it lands (%d hits)" % floor_hits.call(flights[&"cabin"]),
			floor_hits.call(flights[&"cabin"]) == 1)
	check("a neon ball bounces (%d hits)" % floor_hits.call(flights[&"grid"]), floor_hits.call(flights[&"grid"]) >= 3)
	var first_down := func(f: Flight) -> float:
		return f.hits[0] if f != null and f.hits.size() > 0 else -1.0
	var beach_out := (flights[&"rooftop"] as Flight).points[int(first_down.call(flights[&"rooftop"]) / Flight.STEP)]
	var tennis_out := (flights[&"loft"] as Flight).points[int(first_down.call(flights[&"loft"]) / Flight.STEP)]
	var from := studio.items.global_transform.affine_inverse() * stand
	check("a beach ball thrown as hard as a tennis ball comes down far shorter: the air holds it up",
			Vector2(beach_out.x - from.x, beach_out.z - from.z).length() < 0.8 * Vector2(tennis_out.x - from.x, tennis_out.z - from.z).length())
	studio.set_venue(&"dome", false)
	check("a starfish is not round: no hoop for it", not toy.flies().has("radius"))
	studio.set_venue(&"club", false)
	check("an eight ball is", toy.flies().has("radius") and toy.body.find_child("Number", true, false) is Label3D)

	# A snowball bursts a little where it lands.
	studio.set_venue(&"cabin", false)
	toy.on_bounce(4.0)
	check("a snowball landing hard throws up a puff of snow", toy.get_node_or_null("Puff") is CPUParticles3D)

	studio.queue_free()
	await get_tree().process_frame
	_as_session(Session.Role.SOLO, 1)


## THE WASHOUT THIS EXISTS FOR (docs/loop_backlog.md, "Known rough edges": "The neon ball reads
## as a pink ball; its bands do not show as bands"). At 3.0 -- the highest emission multiplier
## anywhere in the project, against the LED's own 2.4 for something a few millimetres across --
## bloom bled the bright bands straight across the dark shell between them. Checked as a number
## against the project's own established range rather than a render, so it fails the moment
## someone turns the glow back up without fixing the actual washout.
func _test_the_neon_ball_glows_without_blooming_into_one_colour() -> void:
	var toy := ToyItem.new()
	add_child(toy)
	var glow := toy._skin("glow") as StandardMaterial3D
	check("the bands still glow", glow.emission_enabled and glow.emission == ToyItem.NEON)
	check("but no brighter than the project's own established range for something this size (%.1f)" %
			glow.emission_energy_multiplier, glow.emission_energy_multiplier <= 2.4)
	var shell := toy._skin("shell") as StandardMaterial3D
	check("and the shell between the bands carries no glow of its own to bloom with",
			not shell.emission_enabled)
	toy.queue_free()


## THE CROWDING THIS EXISTS FOR (docs/loop_backlog.md, "Known rough edges": "The beach ball,
## held on a desktop, is a big thing over the desk and hides some of it"). `held_pose`'s old
## `-size - 0.3` put the ball's CENTRE a radius-plus-30cm from the glove, which means its own
## radius cancels out of where its NEAR surface ends up -- always a flat 30cm away, for a toy
## 3cm across or 20cm across alike. Confirmed off a screenshot: at 30cm the beach ball (the only
## toy past the 0.1 branch) covered the console's whole BPM/ADD/RAMP/DEL/SIG row.
func _test_the_beach_ball_does_not_crowd_the_view() -> void:
	ToyItem.shown = &"rooftop"
	var toy := ToyItem.new()
	add_child(toy)
	check("it is the big one", float(toy._toy()["size"]) >= 0.1)
	var size := float(toy._toy()["size"])
	var near_edge := -toy.held_pose().origin.z - size
	check("its near surface clears the old flat 30cm by a real margin (%.2fm)" % near_edge,
			near_edge > 0.4)
	check("and a toy too small to need pushing out is untouched (palm pose is the origin)",
			ToyItem.TOYS[&"studio"]["size"] < 0.1)
	toy.queue_free()
	ToyItem.shown = &"studio"


## THE CROWDING THIS EXISTS FOR (docs/loop_backlog.md, "Known rough edges": "Keytar: ... Held on
## a desktop, it covers most of the desk"). The desktop pose's base offset had a zero z -- the
## instrument's own 0.9m length ran forward from right in front of the glove, straight across the
## console's whole fader row (confirmed off a screenshot, frame 90 so the carry spring-damper had
## settled: every one of the 13 strips hidden). Pinning the exact -0.35 pushed into the base
## offset, and that it reads as further from the eye along local -Z (the glove's own frame is
## camera-aligned; `MouseInteractor.carry_pose()` offsets a held item by a negative z to put it
## in front of the camera, so a more negative z is further from the eye, not closer).
func _test_a_held_keytar_clears_the_console_instead_of_covering_it() -> void:
	var hand := MouseInteractor.new()
	var keytar := KeytarItem.new()
	add_child(keytar)
	keytar.carried_by = hand
	var turn := Basis(Vector3.UP, -0.42) * Basis(Vector3.FORWARD, -0.12) * Basis(Vector3.RIGHT, 0.75)
	var base := keytar.held_pose().origin + turn * KeytarItem.CRADLE
	check("the base offset carries the -0.35m pushed out to clear the console (%.2f)" % base.z,
			is_equal_approx(base.z, -0.35))
	keytar.queue_free()


## THE FLOATING THIS EXISTS FOR (docs/loop_backlog.md, "Known rough edges": "Held on a desktop
## it floats just over the glove rather than resting on it"). Measured rather than eyeballed: a
## --shot-debug print of the settled item's and the mouse's own CarryGlove's global_position (90
## frames in, past the carry spring-damper) put the cradle's base a good 4cm below the palm's own
## top surface -- `held_pose`'s old flat `-0.03` in y, shared with the headset pose, never
## accounted for the glove only a mouse draws under it. Raising the desktop branch's y to `0.0`
## closed it in a re-shot of the same repro: the base now sits on the fingers rather than
## hovering clear of them. The headset branch (no Glove drawn; a tracked hand holds it exactly
## where it is) is untouched.
func _test_a_held_cradle_rests_on_the_mouses_glove_instead_of_floating_over_it() -> void:
	var hand := MouseInteractor.new()
	var cradle := CradleItem.new()
	add_child(cradle)
	cradle.carried_by = hand
	check("on a desktop its base sits right at the carry pose, not the old flat -0.03 below it",
			is_equal_approx(cradle.held_pose().origin.y, 0.0))
	cradle.carried_by = null
	check("a tracked hand (no carried_by, or anything but a mouse) keeps the untouched pose",
			is_equal_approx(cradle.held_pose().origin.y, -0.03))
	cradle.queue_free()


func _test_the_yoyo_does_its_tricks() -> void:
	_offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	_as_session(Session.Role.SOLO, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var yoyo := studio.items.items.get(&"yoyo") as YoyoItem
	check("there is a yo-yo at home, lying on its side with its string wound up", yoyo != null
			and yoyo.state == Item.State.HOME and yoyo.own_home and not yoyo.cord.visible
			and absf(yoyo.yoyo.global_basis.x.normalized().y) > 0.99)
	var wrong: Array = []
	for id in Venue.IDS:
		studio.set_venue(id, false)
		var on_shelf := studio.venue.prop_shelf_spot().affine_inverse() * yoyo.home.origin
		if absf(on_shelf.x) + 0.05 > ZoneKit.SHELF.x * 0.5 or absf(on_shelf.z) + 0.05 > ZoneKit.SHELF.z * 0.5 \
				or absf(on_shelf.y - ZoneKit.SHELF.y) > 0.001:
			wrong.append(id)
	check("in every venue it lies on the shelf's top (%s)" % [wrong], wrong.is_empty())
	studio.set_venue(&"studio", false)

	var hand := studio.get_node("MouseHand") as MouseInteractor
	hand.pick_up(yoyo)
	var finger := func() -> Vector3: return yoyo.global_position
	var at := func() -> Vector3: return yoyo.yoyo.global_position
	check("in the hand it is just under the finger, offering a throw", yoyo.hint().contains("throw it down")
			and (at.call() - finger.call()).normalized().y < -0.99
			and absf(finger.call().distance_to(at.call()) - YoyoItem.IN_HAND) < 0.001)
	var full := yoyo.string_length()
	check("your own hand on a desktop throws a short string, that the tricks play out in the picture",
			full == YoyoItem.DESK_STRING)
	yoyo.work(true)
	yoyo.work(false)
	yoyo._process(0.7)
	var hang: Vector3 = at.call() - finger.call()
	check("thrown down, it sleeps at the end of its string, straight down from the finger (%s)" % [hang],
			absf(hang.length() - full) < 0.02 and hang.normalized().y < -0.99 and yoyo.cord.visible
			and absf(yoyo.cord.transform.basis.y.length() - hang.length()) < 0.02)
	yoyo._process(1.1)
	check("and comes back up into the hand", yoyo.playing == -1
			and absf(finger.call().distance_to(at.call()) - YoyoItem.IN_HAND) < 0.001)
	yoyo.work(true)
	yoyo.work(false)
	yoyo._process(0.95)
	var ahead := yoyo.global_basis * Vector3.FORWARD
	ahead = Vector3(ahead.x, 0, ahead.z).normalized()
	var round_at: Vector3 = at.call() - finger.call()
	check("around the world, half way round it is behind the hand, at its height (%s)" % [round_at],
			absf(round_at.length() - full) < 0.01 and round_at.normalized().dot(ahead) < -0.99)
	yoyo.work(true)
	yoyo.work(false)
	check("a press mid-trick finishes it and starts the next", yoyo.playing == 2)
	yoyo._process(0.69)
	var loop_at: Vector3 = at.call() - finger.call()
	check("looping, it goes round past the hand, a short string's length away (%s)" % [loop_at],
			absf(loop_at.length() - minf(full, YoyoItem.STRING * 0.45)) < 0.01)
	yoyo.snap_home()
	check("put away mid-loop, it lies on its side again, wound up", yoyo.playing == -1 and not yoyo.cord.visible
			and absf(yoyo.yoyo.global_basis.x.normalized().y) > 0.99)
	check("in anybody else's hand, the full string", yoyo.string_length() == YoyoItem.STRING)
	check("it is round: it goes through a hoop", yoyo.flies().get("radius", 0.0) == YoyoItem.RADIUS)

	studio.queue_free()
	await get_tree().process_frame
	_as_session(Session.Role.SOLO, 1)
	Session.layout = saved_layout


func _test_the_cradle_swings_and_clacks() -> void:
	# The swing: pulled out, let go, and only ever one group out at a time, dying away to still.
	check("pulled out first, then let go from all the way out",
			CradleItem.swing(0.0) == 0.0 and is_equal_approx(CradleItem.swing(CradleItem.LIFT), CradleItem.LIFT_ANGLE))
	var quarter := CradleItem.LIFT + PI * 0.5 / CradleItem.SWING_RATE
	var half := CradleItem.LIFT + PI / CradleItem.SWING_RATE
	check("a quarter swing later it strikes the row, and half a swing later the far group is out",
			absf(CradleItem.swing(quarter)) < 0.001 and CradleItem.swing(half) < -0.3)
	check("each swing a little less than the last", absf(CradleItem.swing(half)) < CradleItem.LIFT_ANGLE
			and absf(CradleItem.swing(half + PI / CradleItem.SWING_RATE)) < absf(CradleItem.swing(half)))
	check("and played out, it is still", CradleItem.swing(CradleItem.RUNS) == 0.0)
	var strikes := CradleItem.strikes()
	check("it clacks at every strike, a dozen times or more (%d)" % strikes.size(), strikes.size() >= 12
			and absf(strikes[0] - (quarter - CradleItem.LIFT)) < 0.0001)

	_offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	_as_session(Session.Role.SOLO, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var cradle := studio.items.items.get(&"cradle") as CradleItem
	check("there is a cradle, five balls, at home on the shelf", cradle != null and cradle.balls.size() == CradleItem.BALLS
			and cradle.state == Item.State.HOME and cradle.own_home)
	var wrong: Array = []
	for id in Venue.IDS:
		studio.set_venue(id, false)
		var on_shelf := studio.venue.prop_shelf_spot().affine_inverse() * cradle.home.origin
		if absf(on_shelf.x) + 0.11 > ZoneKit.SHELF.x * 0.5 or absf(on_shelf.z) + 0.06 > ZoneKit.SHELF.z * 0.5 \
				or absf(on_shelf.y - ZoneKit.SHELF.y) > 0.001:
			wrong.append(id)
	check("in every venue it stands on the shelf's top, all of it (%s)" % [wrong], wrong.is_empty())
	studio.set_venue(&"studio", false)

	var hand := studio.get_node("MouseHand") as MouseInteractor
	hand.pick_up(cradle)
	check("in the hand it offers to swing one", cradle.hint().contains("swing one"))
	cradle.work(true)
	cradle.work(false)
	cradle._process(CradleItem.LIFT + 0.05)
	var out := cradle.balls.map(func(b: Node3D) -> float: return b.rotation.z)
	check("a click pulls the end ball out and lets it go, the rest hanging still (%s)" % [out],
			out[4] > 0.5 and out.slice(0, 4).all(func(a: float) -> bool: return a == 0.0))
	cradle._process(PI / CradleItem.SWING_RATE)
	out = cradle.balls.map(func(b: Node3D) -> float: return b.rotation.z)
	check("half a swing on, the ball at the other end is out instead (%s)" % [out],
			out[0] < -0.3 and out.slice(1).all(func(a: float) -> bool: return a == 0.0))
	cradle.work(true)
	cradle.work(false)
	cradle._process(CradleItem.LIFT)
	out = cradle.balls.map(func(b: Node3D) -> float: return b.rotation.z)
	check("the next click stops it dead and swings two (%s)" % [out], cradle.playing == 1
			and out[3] > 0.5 and out[4] > 0.5 and out.slice(0, 3).all(func(a: float) -> bool: return a == 0.0))
	cradle.work(true)
	cradle.work(false)
	cradle._process(CradleItem.LIFT + PI / CradleItem.SWING_RATE)
	out = cradle.balls.map(func(b: Node3D) -> float: return b.rotation.z)
	check("and three: the middle one goes out with both groups (%s)" % [out], cradle.playing == 2
			and out[0] < -0.3 and out[1] < -0.3 and out[2] < -0.3 and out[3] == 0.0 and out[4] == 0.0)
	for step in 20:
		cradle._process(0.5)
	check("left alone it swings itself still", cradle.playing == -1
			and cradle.balls.all(func(b: Node3D) -> bool: return b.rotation.z == 0.0))
	cradle.work(true)
	cradle.work(false)
	cradle._process(CradleItem.LIFT)
	cradle.snap_home()
	check("put away mid-swing, it is still on the shelf", cradle.playing == -1 and cradle.tricks_done == 0
			and cradle.balls.all(func(b: Node3D) -> bool: return b.rotation.z == 0.0))

	studio.queue_free()
	await get_tree().process_frame
	_as_session(Session.Role.SOLO, 1)
	Session.layout = saved_layout


func _test_a_ball_goes_through_the_hoop() -> void:
	# A hoop at the origin, its board facing +Z; a ball lobbed at it from across the room.
	var shape := Hoop.shape(Transform3D.IDENTITY)
	var rim: Vector3 = (shape["at"] as Transform3D).origin
	var from := Vector3(0.1, 1.5, 2.6)
	var fly := func(to: Vector3, speed: float, radius := BallItem.RADIUS) -> Flight:
		return Flight.fly(from, ItemRoom.lob(from, to, speed), Vector3.ZERO, Quaternion.IDENTITY, [], [],
				0.78, 0.7, 0.0, {}, [], 0.0, [shape], radius)
	var swish: Flight = fly.call(rim, 3.0)
	check("a ball lobbed down into the middle of the rim goes through it, a swish (%s)" % [swish.baskets],
			swish.baskets.size() == 1 and swish.baskets[0]["clean"] and swish.baskets[0]["hoop"] == 0
			and not swish.hit_on.has(Flight.RIM) and not swish.hit_on.has(Flight.BOARD))
	var under := swish.at(swish.baskets[0]["t"] + 0.1).origin
	check("and drops out of the net below it (%s)" % [under], under.y < rim.y - 0.1
			and Vector2(under.x - rim.x, under.z - rim.z).length() < Hoop.RIM_RADIUS)
	var clang: Flight = fly.call(rim + Vector3(0, 0.0, Hoop.RIM_RADIUS), 3.0)
	check("one dropped onto the front of the rim comes off it (%s)" % [clang.hit_on],
			clang.hit_on.size() > 0 and clang.hit_on[0] == Flight.RIM)
	var banked: Flight = fly.call(Vector3(0, Hoop.BOARD_Y, 0), 6.0)
	check("one thrown at the board comes back off it, in front of it (%s)" % [banked.hit_on],
			banked.hit_on.size() > 0 and banked.hit_on[0] == Flight.BOARD
			and banked.at(banked.hits[0] + 0.05).origin.z > Hoop.BOARD_FRONT + BallItem.RADIUS * 0.9)
	var rimmed_in := false
	for dx in [-0.06, -0.04, 0.04, 0.06]:
		for dz in [-0.05, 0.05, 0.08]:
			var f: Flight = fly.call(rim + Vector3(dx, 0, dz), 3.0)
			if f.baskets.size() == 1 and not f.baskets[0]["clean"]:
				rimmed_in = true
	check("one that touches the rim on its way in still counts, not as a swish", rimmed_in)
	var nothing := Flight.fly(from, ItemRoom.lob(from, rim, 3.0), Vector3.ZERO, Quaternion.IDENTITY, [], [])
	check("and with no hoop there is no basket", nothing.baskets.is_empty())

	_offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	_as_session(Session.Role.SOLO, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame

	# In every venue: a hoop, standing where it can be walked up to, in nobody's way.
	var wrong: Array = []
	for id in Venue.IDS:
		studio.set_venue(id, false)
		var spot := studio.venue.hoop_spot()
		var hoop := studio.venue.get_node_or_null("Hoop") as Hoop
		if hoop == null or studio.items.hoops.size() != 1 or studio.items.hoops[0].get("node") != hoop:
			wrong.append("%s: no hoop" % id)
			continue
		var front := spot * Vector3(0, 0, 1.0)
		if not Flight._on_floor(studio.walker.walkable, Vector2(front.x, front.z)) \
				or Flight._over_solid(studio.walker.fixed, Vector2(front.x, front.z)):
			wrong.append("%s: nowhere to stand in front of it" % id)
		var own := Hoop.solids(spot)
		for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
			var at := spot * Vector3(corner.x * Hoop.BASE_HALF.x, 0, Hoop.BASE_Z + corner.z * Hoop.BASE_HALF.y)
			for s: Dictionary in studio.walker.fixed:
				if not own.has(s) and Walker._gap(s, Vector2(at.x, at.z)) <= 0.0:
					wrong.append("%s: its base is in something" % id)
		var foot := Vector2(spot.origin.x, spot.origin.z)
		if absf(foot.x) < studio.venue.room_width * 0.5 + 0.3:
			wrong.append("%s: on the footprint" % id)
	check("in every venue there is a hoop, with floor in front of it and nothing under it (%s)" % [wrong], wrong.is_empty())
	studio.set_venue(&"studio", false)

	# Thrown through it in the room: it swishes, and says so.
	var hoop := studio.venue.get_node("Hoop") as Hoop
	var ball := studio.items.items[&"ball"] as BallItem
	var hand := studio.get_node("MouseHand") as MouseInteractor
	var room_rim := studio.items.global_transform * (studio.items.hoops[0]["at"] as Transform3D).origin
	var stand := studio.items.global_transform * (studio.venue.hoop_spot() * Vector3(0.1, 1.5, 2.2))
	hand.pick_up(ball)
	# Aimed a touch long, as a thrower does: the air takes a little off a ball on the way.
	var long := room_rim + (room_rim - stand) * Vector3(1, 0, 1) * 0.015
	studio.items.throw(ball, stand, ItemRoom.lob(stand, long, 3.0), Vector3.ZERO)
	check("a ball thrown at the hoop is flying into it", ball.is_flying() and ball.flight.baskets.size() == 1)
	for step in 600:
		ball._physics_process(1.0 / 60.0)
		if not ball.is_flying():
			break
	var said := hoop.get_node_or_null("Said") as Label3D
	check("through it, the hoop counts it and says so (%s)" % [said.text if said else "nothing"],
			hoop.made == 1 and said != null and said.text == "SWISH")
	check("and its net swings", hoop.is_processing())
	for step in 400:
		hoop._process(1.0 / 60.0)
	check("and settles, and stops costing anything", not hoop.is_processing() and hoop.net.scale.is_equal_approx(Vector3.ONE))
	check("the ball comes down in front of it, on the floor", ball.state == Item.State.LOOSE or ball.state == Item.State.HOME)
	var duck := studio.items.items[&"duck"] as Item
	hand.pick_up(duck)
	studio.items.throw(duck, stand, ItemRoom.lob(stand, long, 3.0), Vector3.ZERO)
	check("a duck is not a ball: thrown the same way, the hoop is not there for it",
			duck.flight != null and duck.flight.baskets.is_empty() and not duck.flight.hit_on.has(Flight.RIM))
	duck.snap_home()
	hoop.struck(true, 3.0)
	check("a ball off its rim swings it too", hoop.is_processing())
	ball.snap_home()

	studio.queue_free()
	await get_tree().process_frame
	_as_session(Session.Role.SOLO, 1)
	Session.layout = saved_layout


func _test_darts_stick_in_the_board_and_score() -> void:
	# The score of a dart by where it went in.
	var cases := [[Vector2.ZERO, 50], [Vector2(0, 0.01), 25], [Vector2(0, 0.103), 60], [Vector2(0, 0.166), 40],
			[Vector2(0, 0.13), 20], [Vector2(sin(deg_to_rad(18)), cos(deg_to_rad(18))) * 0.13, 1],
			[Vector2(0.13, 0), 6], [Vector2(0, -0.13), 3], [Vector2(-0.13, 0), 11], [Vector2(0, 0.2), 0],
			[Vector2(-0.0705, -0.0705), 48]]
	var wrong: Array = []
	for c: Array in cases:
		var s := DartItem.score(c[0])
		if s["points"] != c[1]:
			wrong.append([c[0], s])
	check("a dart scores by its ring and its number: bull, outer bull, trebles, doubles, singles, off the board (%s)"
			% [wrong], wrong.is_empty() and DartItem.score(Vector2(0, 0.103))["name"] == "T20"
			and DartItem.score(Vector2(0, -0.166))["name"] == "D3")

	# A flight into a board sticks, point first, where it crosses the face.
	var board := Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 0))
	var boards := [{"at": board, "radius": 0.2255}]
	var from := Vector3(0.05, 1.5, 2.37)
	var v := ItemRoom.lob(from, Vector3(0, 1.7, 0), 7.0)
	var f := Flight.fly(from, v, Vector3.ZERO, Quaternion.IDENTITY, [], [], 0.2, 6.0, 0.0, {}, boards, 0.012)
	var nose := Basis(f.rest_turn) * Vector3.FORWARD
	check("a dart lobbed at the bull sticks in the bull, point in, nose into the board (%s %s)" % [f.stuck_on, f.rest],
			f.stuck and f.stuck_board == 0 and f.stuck_on.length() < 0.002 and nose.z < -0.9
			and f.rest.z < 0.0 and f.rest.z > -0.02)
	var past := Flight.fly(from, v, Vector3.ZERO, Quaternion.IDENTITY, [], [], 0.2, 6.0, 0.0, {}, [], 0.012)
	check("with no board it flies on and comes down", not past.stuck and past.rest.y < 0.01)
	var wide := Flight.fly(from, ItemRoom.lob(from, Vector3(0.5, 1.7, 0), 7.0), Vector3.ZERO, Quaternion.IDENTITY,
			[], [], 0.2, 6.0, 0.0, {}, boards, 0.012)
	check("and one aimed wide of the board misses it", not wide.stuck)
	var ball := Flight.fly(from, v, Vector3.ZERO, Quaternion.IDENTITY, [], [], 0.2, 6.0, 0.0, {}, boards, 0.0)
	check("only something with a point sticks", not ball.stuck)

	_offline()
	var saved_layout := Session.layout
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://test_layout_profile.cfg"
	_as_session(Session.Role.SOLO, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var darts: Array[DartItem] = []
	for n in 3:
		darts.append(studio.items.items.get(StringName("dart%d" % (n + 1))) as DartItem)
	check("there are three darts, each its own colour of flight", darts.all(func(d: DartItem) -> bool: return d != null)
			and darts[0].index == 0 and darts[2].index == 2)
	var homeless: Array = []
	for id in Venue.IDS:
		studio.set_venue(id, false)
		var face := studio.venue.dartboard_spot()
		var shelf := studio.venue.prop_shelf_spot()
		var on_shelf := shelf.affine_inverse() * face.origin
		if absf(on_shelf.x) > ZoneKit.SHELF.x * 0.5 or absf(on_shelf.z) > ZoneKit.SHELF.z * 0.5 \
				or studio.venue.find_child("Dartboard", true, false) == null:
			homeless.append(id)
		for d in darts:
			var in_board := face.affine_inverse() * d.home
			var tip := Vector2(in_board.origin.x, in_board.origin.y)
			if not d.own_home or absf(in_board.origin.z + DartItem.POINT_IN) > 0.001 or tip.length() > 0.2 \
					or in_board.basis.z.z < 0.9:
				homeless.append("%s:%s" % [id, d.id])
		if studio.items.boards.size() != 2:
			homeless.append("%s: boards" % id)
	check("in every venue there is a board over the shelf, and the darts live in it, points in (%s)" % [homeless],
			homeless.is_empty())
	studio.set_venue(&"studio", false)

	# Thrown at the board from the oche: in, scored, and the room says so.
	var face := studio.items.global_transform * studio.venue.dartboard_spot()
	var oche := face * Vector3(0.1, -0.15, 2.37)
	var target := face * Vector3(0, 0.103, 0)
	var hand := studio.get_node("MouseHand") as MouseInteractor
	hand.pick_up(darts[0])
	studio.items.throw(darts[0], oche, ItemRoom.lob(oche, target, 7.0), Vector3.ZERO)
	check("thrown, it is flying", darts[0].is_flying() and darts[0].flight.stuck)
	for step in 120:
		darts[0]._physics_process(1.0 / 60.0)
		if not darts[0].is_flying():
			break
	var stuck_at := (studio.items.global_transform * darts[0].resting).origin
	var on_face := face.affine_inverse() * stuck_at
	var popup := darts[0].get_node_or_null("Score") as Label3D
	check("it goes in where it was aimed and stays there: in the treble 20 (%s)" % [on_face],
			darts[0].state == Item.State.LOOSE and absf(on_face.y - 0.103) < 0.004 and absf(on_face.x) < 0.004
			and absf(on_face.z + DartItem.POINT_IN) < 0.004)
	check("and what it scored is shown over it (%s)" % [popup.text if popup else "none"],
			popup != null and popup.text.begins_with("T20") and popup.text.ends_with("60"))
	check("it reads as in the board, with its score, not on the floor (%s)" % darts[0].readout(),
			darts[0].is_stuck() and darts[0].readout() == "in the board: T20")
	var entry: Array = studio.items.state().get(&"dart1", [])
	check("the room has it stuck in the board, turned as it went in", entry.size() == 9 and entry[4] == "stuck")
	var pose := darts[0].resting
	darts[0].snap_home()
	studio.items.apply({&"dart1": entry})
	check("and a room told so puts it there, point in", darts[0].state == Item.State.LOOSE
			and darts[0].resting.is_equal_approx(pose))
	check("stuck in the board it is to be pulled out", darts[0].hint().contains("pull it out"))
	check("a copy told it is in knows only that", darts[0].readout() == "in the board")
	darts[0].lay_down(Vector3(0, 0, 1), 0.4)
	check("a dart on the floor is not stuck", not darts[0].is_stuck() and darts[0].readout() == "on the floor"
			and not darts[0].hint().contains("pull it out"))
	check("lying on its side its flights clear the floor rather than sinking into it (%s)"
			% [darts[0].resting.origin.y], is_equal_approx(darts[0].resting.origin.y, DartItem.LOOSE_LIFT))

	# Aimed, on a desktop: at the board where the cursor's ray meets it.
	var aim := Transform3D(Basis.looking_at(target - oche, Vector3.UP), oche)
	check("an aimed throw is aimed where the aim meets the board", studio.items.aim_point(aim).distance_to(target) < 0.001)
	var away := Transform3D(Basis.looking_at(face.basis.z, Vector3.UP), oche)
	check("and at nothing, a throw's length along it",
			is_equal_approx(studio.items.aim_point(away).distance_to(oche), ItemRoom.AIM_LENGTH))
	var lobbed := ItemRoom.lob(Vector3.ZERO, Vector3(2, 0.5, 0), 6.0)
	var t := 2.0 / lobbed.x
	check("a lob gets there", absf(lobbed.y * t - 0.5 * Flight.GRAVITY * t * (t + Flight.STEP) - 0.5) < 0.0001)
	check("a dart is aimed, and a soft throw wobbles more than a hard one",
			darts[1].aim_scatter(0.0) > darts[1].aim_scatter(1.0) and darts[1].aim_scatter(1.0) > 0.0
			and studio.items.items[&"duck"].aim_scatter(0.5) < 0.0)
	hand.pick_up(darts[1])
	darts[1].work(true)
	darts[1].work(false)
	await get_tree().process_frame
	check("a click with a dart in hand throws it", darts[1].is_flying() and hand.carrying == null)
	for d in darts:
		d.snap_home()

	studio.queue_free()
	await get_tree().process_frame
	_as_session(Session.Role.SOLO, 1)
	Session.layout = saved_layout


func _test_the_radio_plane_flies_where_you_point() -> void:
	_as_session(Session.Role.SOLO, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var room := studio.items
	var rc := room.items.get(&"rcplane") as RcPlaneItem
	check("the room has a radio plane", rc != null and rc.item_title() == "RADIO PLANE")
	if rc == null:
		studio.queue_free()
		return
	var spot := studio.venue.rcplane_spot()
	check("at home on the floor by the hoop, its plane beside its radio", rc.state == Item.State.HOME
			and rc.home.is_equal_approx(spot) and rc.mode == RcPlaneItem.Mode.DOCKED and not rc.plane.top_level
			and rc.plane.transform.is_equal_approx(RcPlaneItem.DOCK) and rc.readout() == "by the hoop")
	var nose := spot.basis * Vector3.FORWARD
	var hoop_at := studio.venue.hoop_spot().origin
	check("nose out into the room, away from the hoop", nose.dot(Vector3(hoop_at.x - spot.origin.x, 0, hoop_at.z - spot.origin.z)) < 0.0)
	var look := ItemRoom.look_of(&"rcplane")
	check("what a ghost carries is the radio, not the plane", look.find_child("Radio", true, false) != null
			and look.find_child("Plane", true, false) == null)
	look.free()
	check("its sounds: a motor that loops, a crash and a touchdown",
			Foley.rc_motor().loop_mode == AudioStreamWAV.LOOP_FORWARD and Foley.rc_crash(0).data.size() > 0
			and Foley.rc_touchdown(0).data.size() > 0 and Foley.rc_crash(1) == Foley.rc_crash(1))

	# Picked up: the radio is in the hand, the plane stays on the floor.
	var hand := FakeHand.new()
	studio.add_child(hand)
	hand.pockets._slots = [null, null, null]
	var lay := rc.plane.global_transform
	hand.pick_up(rc)
	check("picking it up takes the radio; the plane stays where it lay, landed", rc.carried_by == hand
			and rc.plane.top_level and rc.plane.global_transform.origin.is_equal_approx(lay.origin)
			and rc.mode == RcPlaneItem.Mode.LANDED and rc.away())
	var frame := room.global_transform
	var run := func(seconds: float) -> void:
		for i in int(seconds * 60.0):
			rc._process(1.0 / 60.0)
	# Pointed along its nose, a little up, from behind it.
	var ahead := rc._ahead()
	var behind := rc.at - ahead * 1.0 + Vector3(0, 1.2, 0)
	hand.pose = frame * Transform3D(Basis.looking_at(ahead + Vector3(0, 0.15, 0), Vector3.UP), behind)
	rc.work(true)
	check("a click runs the motor up", rc.mode == RcPlaneItem.Mode.RUNNING and rc._motor_running()
			and rc.hint().contains("cut the motor"))
	run.call(0.5)
	check("and it runs along the floor gathering speed", rc.mode == RcPlaneItem.Mode.RUNNING and rc.speed > 0.8
			and is_equal_approx(rc.at.y, room.ground(Vector2(rc.at.x, rc.at.z)) + RcPlaneItem.WHEELS))
	run.call(1.2)
	check("until it lifts off and climbs", rc.mode == RcPlaneItem.Mode.FLYING and rc.at.y > RcPlaneItem.WHEELS + 0.15)
	check("and the plane is drawn where it is flown", rc.plane.global_position.is_equal_approx(frame * rc.at))

	# In the open middle of the live room, heading -X; pointed off to its left, it turns left.
	rc.at = Vector3(0.0, 1.0, 5.0)
	rc.heading = PI * 0.5
	rc.slope = 0.0
	rc.bank = 0.0
	var left := Vector3(0, 0, 1)
	hand.pose = frame * Transform3D(Basis.looking_at(left, Vector3.UP), rc.at - left * 0.5)
	run.call(0.3)
	check("pointed off to one side, it banks into the turn", rc.bank > 0.15 and rc.plane.global_basis.x.y > 0.1)
	run.call(0.4)
	check("and comes round that way", wrapf(rc.heading - PI * 0.5, -PI, PI) > 0.8)

	# Motor cut, nose ahead: it glides down and lands on its wheels, and rolls to a stop.
	# (Down the back of the live room, clear of its riser and what stands in it: into the side of
	# either, low, is a crash.)
	rc.at = Vector3(4.5, 0.7, 6.6)
	rc.heading = PI * 0.5
	rc.slope = 0.0
	rc.speed = RcPlaneItem.SPEED
	hand.pose = frame * Transform3D(Basis.looking_at(Vector3(-1, -0.05, 0), Vector3.UP), Vector3(6.0, 1.0, 6.6))
	rc.work(true)
	check("a click in the air cuts the motor, and it glides", rc.mode == RcPlaneItem.Mode.GLIDING and not rc._motor_running())
	run.call(0.4)
	check("coming down", rc.at.y < 0.7 and rc.slope < 0.0)
	run.call(2.5)
	check("down gently, it has landed", rc.mode == RcPlaneItem.Mode.LANDED
			and is_equal_approx(rc.at.y, room.ground(Vector2(rc.at.x, rc.at.z)) + RcPlaneItem.WHEELS))
	run.call(1.5)
	check("and rolled to a stop, level", rc.speed == 0.0 and rc.plane.global_basis.y.y > 0.99)

	# Into the floor too steeply: crashed, and it lies nosed in.
	rc.mode = RcPlaneItem.Mode.FLYING
	rc.at = Vector3(0.0, 1.2, 5.0)
	rc.heading = PI * 0.5
	rc.speed = RcPlaneItem.SPEED
	rc.slope = -RcPlaneItem.DIVE
	hand.pose = frame * Transform3D(Basis.looking_at(Vector3(-1, -2, 0), Vector3.UP), Vector3(1.0, 1.6, 5.0))
	run.call(1.2)
	check("dived into the floor, it crashes", rc.mode == RcPlaneItem.Mode.CRASHED and rc.at.y < 1.0)
	run.call(1.5)
	var lying := rc.plane.global_basis
	check("and comes to lie on the floor nosed in", not rc.falling and lying.y.y < 0.95
			and absf(rc.at.y - RcPlaneItem._lift(rc._turned) - room.ground(Vector2(rc.at.x, rc.at.z))) < 0.001
			and rc.hint().contains("back on its wheels"))
	rc.work(true)
	check("a click sets it back on its wheels", rc.mode == RcPlaneItem.Mode.LANDED and rc.plane.global_basis.y.y > 0.99)

	# Into a wall: crashed too. The live room's right-hand wall, in a room of the base width.
	var wall_x := Venue.LIVE_ROOM_HALF + (Studio.ROOM_WIDTH - Venue.DRAWN_WIDTH) * 0.5
	rc.mode = RcPlaneItem.Mode.FLYING
	rc.at = Vector3(wall_x - 0.6, 1.0, 6.6)
	rc.heading = -PI * 0.5
	rc.slope = 0.0
	rc.speed = RcPlaneItem.SPEED
	hand.pose = frame * Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), Vector3(wall_x - 1.8, 1.0, 6.6))
	run.call(0.5)
	check("flown at a wall, it crashes into it", rc.mode == RcPlaneItem.Mode.CRASHED and rc.at.x < wall_x - 0.05)
	run.call(1.5)
	rc.work(true)

	# Pocketed while it flies: the motor is cut and it glides on, unsteered.
	rc.mode = RcPlaneItem.Mode.FLYING
	rc.at = Vector3(0.0, 1.5, 5.0)
	rc.heading = PI * 0.5
	hand.swap_pocket(0)
	check("the radio pocketed in flight cuts the motor; nobody steers it", rc.pocket == 0
			and rc.mode == RcPlaneItem.Mode.GLIDING and rc._steer_to() == null)
	hand.swap_pocket(0)

	# Somebody else's, on this machine: flown where they say.
	var other := ItemRoom.new()
	add_child(other)
	await get_tree().process_frame
	var copy := other.items[&"rcplane"] as RcPlaneItem
	copy.follow(func() -> Transform3D: return Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0)))
	check("in somebody else's hand, the plane stays where it was", copy.mode == RcPlaneItem.Mode.LANDED
			and copy.plane.top_level)
	var there := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.0, 1.4, 2.0))
	copy.hear(there, RcPlaneItem.Mode.FLYING)
	check("told it flies, it flies there, motor running", copy.mode == RcPlaneItem.Mode.FLYING
			and copy.plane.global_position.is_equal_approx(there.origin) and copy._motor_running())
	PoseTrail.skew_msec += 50.0
	copy.hear(there.translated(Vector3(0.5, 0, 0)), RcPlaneItem.Mode.FLYING)
	PoseTrail.skew_msec += 400.0
	for i in 30:
		copy._process(1.0 / 60.0)
	check("and follows where it is said to be", copy.plane.global_position.distance_to(there.origin + Vector3(0.5, 0, 0)) < 0.02)
	copy.use(true)
	check("their clicks fly it, not this copy's", copy.mode == RcPlaneItem.Mode.FLYING)
	copy.hear(there, RcPlaneItem.Mode.CRASHED)
	check("told it crashed, it has", copy.mode == RcPlaneItem.Mode.CRASHED and not copy._motor_running())
	copy.go_home()
	check("out of their hand, the plane is back beside its radio", copy.mode == RcPlaneItem.Mode.DOCKED
			and not copy.plane.top_level)
	other.queue_free()

	# Put down: the plane comes back to its radio.
	hand.put_down()
	await get_tree().physics_frame
	check("out of the hand, the plane is back beside its radio", rc.state != Item.State.HELD
			and rc.mode == RcPlaneItem.Mode.DOCKED and rc.plane.transform.is_equal_approx(RcPlaneItem.DOCK))
	hand.queue_free()
	studio.queue_free()
	await get_tree().process_frame


func _test_somebody_elses_radio_plane_flies_where_they_say() -> void:
	_as_session(Session.Role.SOLO, 1)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().physics_frame
	var rc := studio.items.items[&"rcplane"] as RcPlaneItem
	var presence := studio.presence
	presence._item_holders[&"rcplane"] = 7
	rc.follow(func() -> Transform3D: return rc.global_transform)
	var there := Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.5, 1.3, 2.0))
	Session.item_flown.emit(&"rcplane", there, RcPlaneItem.Mode.FLYING, 9)
	check("a flight from somebody not holding the radio is not shown", rc.mode == RcPlaneItem.Mode.LANDED)
	Session.item_flown.emit(&"rcplane", there, RcPlaneItem.Mode.FLYING, 7)
	var world := presence._from_session(there)
	check("one from whoever has it flies ours there, in this room's frame", rc.mode == RcPlaneItem.Mode.FLYING
			and rc.plane.global_position.is_equal_approx(world.origin))
	Session.item_flown.emit(&"rcplane", there, RcPlaneItem.Mode.DOCKED, 7)
	check("and when they say it is back by the radio, it is", rc.mode == RcPlaneItem.Mode.DOCKED
			and not rc.plane.top_level)
	presence._item_holders.erase(&"rcplane")
	studio.queue_free()
	await get_tree().process_frame


# --- Tour (core/tour) ----------------------------------------------------------------------
#
# Work Package A only: the run's data, its judging, its deck, its project swap and its
# unlocks, and the Session.tour channel's shape -- none of it touching core/items/, scenes/
# or hardware/, which is Package B's job.

func _test_tour_briefs_are_defined_and_the_boss_is_last() -> void:
	check("one venue's worth: three briefs and a boss", TourBriefs.count() == 4)
	check("the boss is last", TourBriefs.brief(3).is_boss)
	check("and nothing before it is", not TourBriefs.brief(0).is_boss
			and not TourBriefs.brief(1).is_boss and not TourBriefs.brief(2).is_boss)
	check("brief() clamps rather than indexing off the end", TourBriefs.brief(99) == TourBriefs.brief(3))


## These four build their own TourBrief with the old measures/targets rather than reading
## TourBriefs.brief(n): they test `judge`'s arithmetic, not venue data -- the real briefs now
## judge flaws instead (briefs.gd's "Tour" comment says why) and carry empty measures/targets.
func _test_tour_loudness_judges_in_range() -> void:
	var brief := TourBrief.new()
	brief.measures = [&"loudness"]
	brief.targets = {"loudness_min_db": -16.0, "loudness_max_db": -10.0, "loudness_peak_max_db": -1.0}
	check("at the bottom edge of the window, with headroom, it passes",
			bool(brief.judge({"loudness": {"avg_db": -16.0, "peak_db": -1.0}}, 1.0)["passed"]))
	check("at the top edge it passes too",
			bool(brief.judge({"loudness": {"avg_db": -10.0, "peak_db": -1.0}}, 1.0)["passed"]))
	check("a hair under the bottom edge fails",
			not bool(brief.judge({"loudness": {"avg_db": -16.01, "peak_db": -1.0}}, 1.0)["passed"]))
	check("a hair over the top edge fails",
			not bool(brief.judge({"loudness": {"avg_db": -9.99, "peak_db": -1.0}}, 1.0)["passed"]))
	check("in range but clipping past the ceiling fails",
			not bool(brief.judge({"loudness": {"avg_db": -13.0, "peak_db": -0.5}}, 1.0)["passed"]))
	check("dead centre scores at or near the top",
			int(brief.judge({"loudness": {"avg_db": -13.0, "peak_db": -6.0}}, 1.0)["score"]) == 100)


func _test_tour_balance_judges_spread() -> void:
	var brief := TourBrief.new()
	brief.measures = [&"balance"]
	brief.targets = {"balance_spread_max_db": 8.0}
	check("exactly at the spread limit passes", bool(brief.judge(
			{"balance": {"low_db": -20.0, "mid_db": -14.0, "high_db": -12.0}}, 1.0)["passed"]))
	check("a hair past it fails", not bool(brief.judge(
			{"balance": {"low_db": -20.01, "mid_db": -14.0, "high_db": -12.0}}, 1.0)["passed"]))
	check("flat across all three bands passes easily", bool(brief.judge(
			{"balance": {"low_db": -14.0, "mid_db": -14.0, "high_db": -14.0}}, 1.0)["passed"]))


func _test_tour_timing_judges_beat_grid() -> void:
	var brief := TourBrief.new()
	brief.measures = [&"timing"]
	brief.targets = {"timing_mean_max_beats": 0.12, "timing_worst_max_beats": 0.30}
	var at_edge := {"timing": {"avg_beats_off": 0.12, "worst_beats_off": 0.30, "notes": 5}}
	check("right at both edges passes", bool(brief.judge(at_edge, 1.0)["passed"]))
	var just_over := {"timing": {"avg_beats_off": 0.1201, "worst_beats_off": 0.30, "notes": 5}}
	check("a hair over the mean edge fails", not bool(brief.judge(just_over, 1.0)["passed"]))
	var no_notes := {"timing": {"avg_beats_off": 0.0, "worst_beats_off": 0.0, "notes": 0}}
	check("nothing played is not a pass", not bool(brief.judge(no_notes, 1.0)["passed"]))
	var widened := {"timing": {"avg_beats_off": 0.20, "worst_beats_off": 0.50, "notes": 5}}
	check("tight without tolerance fails", not bool(brief.judge(widened, 1.0)["passed"]))
	check("the same numbers pass once tempo_tolerance_mult widens the window",
			bool(brief.judge(widened, 2.0)["passed"]))


func _test_tour_boss_requires_every_measure_to_pass() -> void:
	var boss := TourBrief.new()
	boss.measures = [&"loudness", &"balance", &"timing"]
	boss.targets = {
		"loudness_min_db": -14.0, "loudness_max_db": -12.0, "loudness_peak_max_db": -2.0,
		"balance_spread_max_db": 5.0,
		"timing_mean_max_beats": 0.08, "timing_worst_max_beats": 0.18,
	}
	var all_good := {"loudness": {"avg_db": -13.0, "peak_db": -6.0},
			"balance": {"low_db": -14.0, "mid_db": -14.0, "high_db": -14.0},
			"timing": {"avg_beats_off": 0.05, "worst_beats_off": 0.10, "notes": 8}}
	check("every measure clean is a pass", bool(boss.judge(all_good, 1.0)["passed"]))
	var one_bad := all_good.duplicate(true)
	one_bad["timing"] = {"avg_beats_off": 0.20, "worst_beats_off": 0.40, "notes": 8}
	check("one measure failing fails the whole brief, not an average",
			not bool(boss.judge(one_bad, 1.0)["passed"]))


func _test_tour_deck_draws_three_with_no_duplicates() -> void:
	for seed in range(20):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var hand := TourDeck.draw(rng, [])
		check("a draft is three cards (seed %d)" % seed, hand.size() == 3)
		var ids: Array = hand.map(func(c: TourCard) -> StringName: return c.id)
		var unique := {}
		for id in ids:
			unique[id] = true
		check("none repeated (seed %d, %s)" % [seed, ids], unique.size() == ids.size())
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 1
	var excluded: Array[StringName] = [&"extra_track", &"free_effect"]
	var hand2 := TourDeck.draw(rng2, excluded)
	for c in hand2:
		check("a card already held is never offered again (%s)" % c.id, not (c.id in excluded))


func _test_tour_card_apply_uses_daw_verbs_only() -> void:
	var previous := DAW.backend
	DAW.use(OfflineBackend.new())
	var run := TourRun.new()

	var before_tracks := DAW.state.track_indices().size()
	for c in TourDeck.all_cards():
		if c.id == &"extra_track":
			c.apply(run)
	check("extra_track went through DAW.add_track", DAW.state.track_indices().size() == before_tracks + 1)

	var first_track: int = DAW.state.track_indices()[0]
	var fx_before := DAW.state.track(first_track).plugins().size()
	for c in TourDeck.all_cards():
		if c.id == &"free_effect":
			c.apply(run)
	check("free_effect went through DAW.add_fx", DAW.state.track(first_track).plugins().size() == fx_before + 1)

	# Not "nothing is muted beforehand": a track mute is exactly the kind of change other,
	# unrelated tests leave lying around on whichever backend happens to be current when their
	# own (possibly deferred) signal lands, so this checks the one thing that is actually
	# `muted_track`'s to answer for -- that applying it mutes at least one track it did not
	# already find muted -- rather than asserting a clean slate this test does not own.
	var muted_before := {}
	for t: MixState.TrackState in DAW.state.tracks.values():
		if t.mute:
			muted_before[t.index] = true
	for c in TourDeck.all_cards():
		if c.id == &"muted_track":
			c.apply(run)
	var newly_muted := 0
	for t: MixState.TrackState in DAW.state.tracks.values():
		if t.mute and not muted_before.has(t.index):
			newly_muted += 1
	check("muted_track went through DAW.set_track_mute", newly_muted >= 1)

	for c in TourDeck.all_cards():
		if c.id == &"loose_tempo":
			c.apply(run)
	check("loose_tempo touches only run state, not the DAW", is_equal_approx(run.tempo_tolerance_mult, 1.5))

	# A spill card's effect runs through `Tour.spill` against the global `Tour.run` (the same
	# object `run` is, once a brief's own `card.apply(run)` is the one calling it) rather than
	# the DAW: no new track, no fx, nothing muted -- only the run's own `instruments` moves.
	var tracks_before_spill := DAW.state.track_indices().size()
	var fx_before_spill := DAW.state.track(first_track).plugins().size()
	_as_session(Session.Role.HOST, 1)
	Tour.run = run
	for c in TourDeck.all_cards():
		if c.id == &"spill_cowbell":
			c.apply(run)
	Tour.run = null
	_as_session(Session.Role.SOLO, 1)
	check("spill_cowbell only touches run state (%s)" % [run.instruments], run.instruments == [&"cowbell"])
	check("and never the DAW", DAW.state.track_indices().size() == tracks_before_spill
			and DAW.state.track(first_track).plugins().size() == fx_before_spill)

	DAW.use(previous, false)


func _test_tour_project_restores_exactly() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	ProjectBridge.load(ProjectFiles.blank("Studio Song", 3), backend)
	backend.project_path = "user://projects/Studio Song.dawproject"
	backend.name_project()

	var snapshot := TourProject.capture(backend)
	var original: DawKitProject = snapshot["project"]

	var song_rng := RandomNumberGenerator.new()
	song_rng.seed = 7
	TourProject.load(TourProject.song_for(TourBriefs.brief(0), 120.0, [], song_rng), backend)
	DAW.add_track(DAW.state.track_indices().size() + 1, "Gear")
	DAW.rename_track(1, "Renamed While Touring")
	DAW.set_tempo(140.0)

	TourProject.restore(backend, snapshot)
	var restored := ProjectBridge.capture(backend)
	check("the restored project is exactly the one that was captured (%s)" % [original.first_difference(restored)],
			original.same_as(restored))
	check("the project's file path comes back too", backend.project_path == snapshot["path"])

	DAW.use(previous, false)


func _test_tour_unlocks_persist_without_touching_layout() -> void:
	var path := "user://tour_unlocks_test.cfg"
	var u := TourUnlocks.new()
	u.save_path = path
	u.record_run(false)
	u.record_run(true)
	check("the file is not layout_profile.cfg", u.save_path != "user://layout_profile.cfg")
	check("nor under the projects folder", not u.save_path.begins_with(ProjectFiles.DEFAULT_DIR))

	var reloaded := TourUnlocks.new()
	reloaded.save_path = path
	reloaded.load_saved()
	check("runs persisted", reloaded.runs == 2)
	check("and wins among them", reloaded.wins == 1)
	check("and reputation with the win", reloaded.reputation == 1)

	var fresh := TourUnlocks.new()
	fresh.save_path = path
	fresh.save_path = "user://tour_unlocks_test_unread.cfg"
	fresh.load_saved()
	check("a never-saved path loads as all zero", fresh.runs == 0 and fresh.wins == 0)

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A loss costs a point of reputation, floored at 0 -- a losing streak never goes negative, only
## back to where a band that has never played already starts.
func _test_tour_unlocks_a_loss_costs_a_point_of_reputation() -> void:
	var u := TourUnlocks.new()
	u.save_path = "user://tour_unlocks_test_cost.cfg"

	u.record_run(false)
	check("a loss at 0 reputation stays at 0, not negative (%d)" % u.reputation, u.reputation == 0)

	u.record_run(true)
	u.record_run(true)
	check("two wins: reputation 2 (%d)" % u.reputation, u.reputation == 2)

	u.record_run(false)
	check("a loss costs one (%d)" % u.reputation, u.reputation == 1)

	u.record_run(false)
	u.record_run(false)
	check("losing it all the way down still floors at 0, not negative (%d)" % u.reputation,
			u.reputation == 0)

	if FileAccess.file_exists(u.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(u.save_path))


func _test_tour_asks_follow_the_verbs_shape() -> void:
	check("draft_pick with one int is valid", Session.tour_ask_is_valid(&"draft_pick", [1]))
	check("two ints is not the shape", not Session.tour_ask_is_valid(&"draft_pick", [1, 2]))
	check("a string is not an int", not Session.tour_ask_is_valid(&"draft_pick", ["x"]))
	check("starting a run is never an ask -- it is not in TOUR_VERBS at all",
			not Session.tour_ask_is_valid(&"start_run", []))
	check("neither is ending one", not Session.tour_ask_is_valid(&"abandon_run", []))


func _test_tour_run_round_trips_through_its_dict() -> void:
	var run := TourRun.new()
	run.state = TourRun.State.DRAFTING
	run.brief_index = 2
	run.score = 87
	run.seconds_left = 12.5
	run.gear = [&"extra_track", &"loose_tempo"]
	run.curses = [&"tight_tempo"]
	run.tempo_tolerance_mult = 0.9
	run.attempt_seed = 4242
	run.band_size = 8
	run.song_tempo = 108.0
	run.flaws = [&"quiet_vox", &"muddy_bass", &"muted_rhodes", &"hard_pan", &"wrong_tempo"]
	run.fixed = [true, true, true, false, false]
	run.tuning = true
	var back := TourRun.from_dict(run.to_dict())
	check("state rides the wire", back.state == run.state)
	check("so does everything else about the run",
			back.brief_index == run.brief_index and back.score == run.score
			and is_equal_approx(back.seconds_left, run.seconds_left)
			and back.gear == run.gear and back.curses == run.curses
			and is_equal_approx(back.tempo_tolerance_mult, run.tempo_tolerance_mult)
			and back.attempt_seed == run.attempt_seed)
	check("band_size rides the wire", back.band_size == run.band_size)
	check("so does song_tempo", is_equal_approx(back.song_tempo, run.song_tempo))
	check("and flaws, in order", back.flaws == run.flaws)
	check("and which of them are fixed, index for index", back.fixed == run.fixed)
	check("and tuning", back.tuning == run.tuning)


func _test_tour_song_has_a_playing_band() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	TourProject.load(TourProject.song_for(TourBriefs.brief(0), 100.0, [], rng), backend)

	check("twelve tracks", DAW.state.track_indices().size() == TourProject.BAND.size())
	for i in TourProject.BAND.size():
		check("desk %d is %s" % [i + 1, TourProject.BAND[i]],
				DAW.state.track(i + 1).name == TourProject.BAND[i])
	check("TourProject.KEYS_TRACK and Tour.TIMING_TRACK agree", TourProject.KEYS_TRACK == Tour.TIMING_TRACK)
	check("TourProject.STAGE_TRACK and Tour.STAGE_TRACK agree", TourProject.STAGE_TRACK == Tour.STAGE_TRACK)

	var stage := DAW.state.track(TourProject.STAGE_TRACK)
	check("the Stage lane is armed for midi, no role, no clip",
			stage.name == "Stage" and stage.rec_arm and stage.input == "midi" and stage.part == ""
			and stage.items.is_empty())

	var roles := {}
	for i in range(TourProject.KEYS_TRACK + 1, TourProject.BAND.size() + 1):
		var t := DAW.state.track(i)
		var role := DemoSong.role_of(t.name)
		check("track %d (%s) plays its DemoSong role" % [i, t.name], role != "" and t.part == role)
		roles[role] = true
		var covering := 0
		for it: MixState.ItemState in t.items:
			if not it.muted and it.source.is_empty() and it.notes.is_empty() \
					and it.start <= 0.0 and it.start + it.length >= DAW.state.project_length:
				covering += 1
		check("track %d has exactly one covering demo item" % i, covering == 1)
	check("ten distinct roles across the band", roles.size() == 10)

	# The built-in engine's own view of that desk: ten roles to render at this tempo, and on
	# every band track the item under the playhead is the kind `_sync_players` plays a part
	# through (no file, no notes) -- the exact precondition for `_parts.get(part)`.
	var engine := GodotBackend.new()
	engine.state = DAW.state
	check("the engine sees ten roles to render (%s)" % [engine._roles()], engine._roles().size() == 10)
	for i in range(TourProject.KEYS_TRACK + 1, TourProject.BAND.size() + 1):
		var it := engine.item_at(i, 0.0)
		check("track %d's item at the top is a part window" % i,
				it != null and it.source.is_empty() and it.notes.is_empty())
	check("the keys lane plays its own notes, not a part",
			engine.item_at(TourProject.KEYS_TRACK, 0.0) != null
			and not engine.item_at(TourProject.KEYS_TRACK, 0.0).notes.is_empty())
	engine.free()

	var keys := DAW.state.track(TourProject.KEYS_TRACK)
	check("the keys track plays no DemoSong role -- its notes are all it plays", keys.part == "")
	var notes := 0
	for it: MixState.ItemState in keys.items:
		notes += it.notes.size() / MidiTake.NOTE_WIDTH
	check("48 stabs on the keys track (8 bars x 2 x 3 tones)", notes == 48)

	var timing := TourMeasure.Timing.new()
	timing.start(Tour.TIMING_TRACK, 0.0, 1.0)
	var r := timing.result()
	check("the clean lane is dead on a quarter-beat grid (%s)" % [r],
			is_equal_approx(float(r["avg_beats_off"]), 0.0) and int(r["notes"]) == 48)

	check("the song is at the brief's tempo", is_equal_approx(DAW.state.tempo, 100.0))
	check("and loops over its own length",
			DAW.state.looping and is_equal_approx(DAW.state.loop_start, 0.0)
			and is_equal_approx(DAW.state.loop_end, DAW.state.project_length))

	DAW.use(previous, false)


func _test_a_loaded_project_keeps_its_demo_parts() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})

	var demo_p := DawKitProject.new()
	var kick := demo_p.add_track("Kick")
	var demo_clip := DawKitClip.new()
	demo_clip.length = 4.0
	kick.clips.append(demo_clip)
	ProjectBridge.load(demo_p, backend, {1: "kick"})
	check("a track loaded with a part given plays the demo song's kick",
			DAW.state.track(1).part == "kick")
	ProjectBridge.load(demo_p, backend)
	check("and loaded plainly, as a file's project is, the same track is silent of the demo song",
			DAW.state.track(1).part == "")

	var stand_in := OfflineBackend.new()
	stand_in.open({})
	var before := {}
	for i in stand_in.state.track_indices():
		before[i] = stand_in.state.track(i).part
	check("the stand-in's own song actually has parts to lose", before.values().any(func(p): return p != ""))
	var snap := TourProject.capture(stand_in)
	TourProject.restore(stand_in, snap)
	for i in stand_in.state.track_indices():
		check("track %d's part survives a capture/restore (%s vs %s)" \
				% [i, before[i], stand_in.state.track(i).part],
				stand_in.state.track(i).part == before[i])

	DAW.use(previous, false)


func _test_tour_flaws_bake_and_are_fixed_through_daw_verbs() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})

	var brief := TourBriefs.brief(0)
	var quiet_vox := TourFlaws.by_id(&"quiet_vox")
	var muddy_bass := TourFlaws.by_id(&"muddy_bass")
	var muted_rhodes := TourFlaws.by_id(&"muted_rhodes")
	var hard_pan := TourFlaws.by_id(&"hard_pan")
	var wrong_tempo := TourFlaws.by_id(&"wrong_tempo")
	var five: Array[TourFlaw] = [quiet_vox, muddy_bass, muted_rhodes, hard_pan, wrong_tempo]

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	TourProject.load(TourProject.song_for(brief, 100.0, five, rng), backend)

	var run := TourRun.new()
	run.song_tempo = 100.0

	for f in five:
		check("%s starts broken" % f.id, not f.fixed(DAW.state, run))

	DAW.set_track_volume(10, DAW.db_to_taper(0.0))
	check("quiet_vox is fixed by its fader", quiet_vox.fixed(DAW.state, run))
	check("nothing else moved with it", not muddy_bass.fixed(DAW.state, run)
			and not muted_rhodes.fixed(DAW.state, run) and not hard_pan.fixed(DAW.state, run)
			and not wrong_tempo.fixed(DAW.state, run))

	DAW.set_fx_param(7, 0, 0, 0.5)
	DAW.set_fx_param(7, 0, 1, 0.5)
	check("muddy_bass is fixed by pulling both bands back under +3 dB", muddy_bass.fixed(DAW.state, run))
	check("still nothing else moved", not muted_rhodes.fixed(DAW.state, run)
			and not hard_pan.fixed(DAW.state, run) and not wrong_tempo.fixed(DAW.state, run))
	DAW.add_fx(7, "ReaComp", -1)
	DAW.set_fx_param(7, 1, 0, 0.62)
	check("a compressor added to the bass, threshold high, is not mud (%s)" % [DAW.state.fx(7, 1).name],
			DAW.state.track(7).fx.size() == 2 and muddy_bass.fixed(DAW.state, run))
	DAW.set_fx_param(7, 0, 1, 0.9)
	check("but the EQ's 100 Hz band shoved back up is", not muddy_bass.fixed(DAW.state, run))
	DAW.set_fx_enabled(7, 0, false)
	check("and switching that EQ off fixes it again", muddy_bass.fixed(DAW.state, run))
	DAW.set_fx_enabled(7, 0, true)
	DAW.set_fx_param(7, 0, 1, 0.5)

	DAW.set_track_mute(8, false)
	check("muted_rhodes is fixed by its MUTE", muted_rhodes.fixed(DAW.state, run))
	check("still nothing else moved", not hard_pan.fixed(DAW.state, run) and not wrong_tempo.fixed(DAW.state, run))

	DAW.set_track_pan(9, 0.5)
	check("hard_pan is fixed by its pan knob", hard_pan.fixed(DAW.state, run))
	check("wrong_tempo is still broken", not wrong_tempo.fixed(DAW.state, run))

	DAW.set_tempo(100.0)
	check("wrong_tempo is fixed by the deck knob", wrong_tempo.fixed(DAW.state, run))
	check("and the earlier four are still fixed, not re-broken", quiet_vox.fixed(DAW.state, run)
			and muddy_bass.fixed(DAW.state, run) and muted_rhodes.fixed(DAW.state, run)
			and hard_pan.fixed(DAW.state, run))

	# muddy_bass is also fixed by removing the EQ outright, checked on a fresh project.
	var rm_rng := RandomNumberGenerator.new()
	rm_rng.seed = 5
	TourProject.load(TourProject.song_for(brief, 100.0, [muddy_bass], rm_rng), backend)
	check("muddy_bass starts broken again on a fresh project", not muddy_bass.fixed(DAW.state, run))
	DAW.remove_fx(7, 0)
	check("removing the EQ outright also fixes muddy_bass", muddy_bass.fixed(DAW.state, run))

	# dragging_keys is judged through the Timing measure (grid_beats 1.0), not the desk.
	var dragging_keys := TourFlaws.by_id(&"dragging_keys")
	var drag_rng := RandomNumberGenerator.new()
	drag_rng.seed = 9
	TourProject.load(TourProject.song_for(brief, 100.0, [dragging_keys], drag_rng), backend)
	var timing := TourMeasure.Timing.new()
	timing.start(Tour.TIMING_TRACK, 0.0, 1.0)
	var r := timing.result()
	check("the dragging lane reads about 0.22 beats off (%s)" % [r],
			absf(float(r["avg_beats_off"]) - 0.22) < 0.001)
	var drag_run := TourRun.new()
	drag_run.song_tempo = 100.0
	check("dragging_keys is not fixed yet", not dragging_keys.fixed(DAW.state, drag_run))
	DAW.quantize_item(TourProject.KEYS_TRACK, 0, 1.0)
	check("quantizing the item fixes dragging_keys", dragging_keys.fixed(DAW.state, drag_run))
	drag_run.tempo_tolerance_mult = 0.6
	check("a tight_tempo card's narrower window still passes a quantised lane",
			dragging_keys.fixed(DAW.state, drag_run))

	check("wrong_tempo excludes dragging_keys", &"dragging_keys" in wrong_tempo.excludes)

	DAW.use(previous, false)


## Rig roulette: a brief's own seed can land a character FX (never a utility one, never on
## Stage, never on a track a flaw already claimed) on a big enough band, nothing on a duo or on
## the first brief, and the same seed lands the same gear twice.
func _test_tour_rig_roulette_lands_character_fx_on_a_big_enough_band() -> void:
	check("none at all for a duo", TourProject.rig_count_for(2) == 0)
	check("one for a band of 4", TourProject.rig_count_for(4) == 1)
	check("two for a band of 6", TourProject.rig_count_for(6) == 2)
	check("three for a band of 8", TourProject.rig_count_for(8) == 3)

	var brief := TourBriefs.brief(1)
	var utility := [&"eq", &"compressor", &"limiter"]

	var solo_rng := RandomNumberGenerator.new()
	solo_rng.seed = 7
	var solo := TourProject.song_for(brief, 100.0, [], solo_rng, 1, 1)
	var solo_fx := 0
	for t in solo.tracks:
		solo_fx += t.effects.size()
	check("a solo band gets no rig roulette at all (%d)" % solo_fx, solo_fx == 0)

	var first_rng := RandomNumberGenerator.new()
	first_rng.seed = 7
	var first := TourProject.song_for(brief, 100.0, [], first_rng, 8, 0)
	var first_fx := 0
	for t in first.tracks:
		first_fx += t.effects.size()
	check("never on the first brief, even for a full band (%d)" % first_fx, first_fx == 0)

	var a_rng := RandomNumberGenerator.new()
	a_rng.seed = 11
	var a := TourProject.song_for(brief, 100.0, [], a_rng, 8, 2)
	var landed := 0
	var on_stage := false
	for t in a.tracks:
		for fx in t.effects:
			landed += 1
			if t.name == "Stage":
				on_stage = true
			check("%s's rig fx (%s) is a character FX, not a utility one" % [t.name, fx.kind],
					not (StringName(fx.kind) in utility))
	check("a full band's seed lands rig_count_for(8) == 3 pedals (%d)" % landed, landed == 3)
	check("never on the Stage lane", not on_stage)

	var b_rng := RandomNumberGenerator.new()
	b_rng.seed = 11
	var b := TourProject.song_for(brief, 100.0, [], b_rng, 8, 2)
	var a_kinds: Array = a.tracks.map(func(t: DawKitTrack) -> Array: return t.effects.map(
			func(fx: DawKitEffect) -> String: return "%s:%s" % [t.name, fx.kind]))
	var b_kinds: Array = b.tracks.map(func(t: DawKitTrack) -> Array: return t.effects.map(
			func(fx: DawKitEffect) -> String: return "%s:%s" % [t.name, fx.kind]))
	check("the same seed lands the same gear twice", a_kinds == b_kinds)

	var quiet_vox := TourFlaws.by_id(&"quiet_vox")
	var c_rng := RandomNumberGenerator.new()
	c_rng.seed = 11
	var c := TourProject.song_for(brief, 100.0, [quiet_vox], c_rng, 8, 2)
	for t in c.tracks:
		if t.name == "Lead Vox":
			check("a track a flaw already claimed is never also given a rig pedal (%d fx)"
					% t.effects.size(), t.effects.size() == 0)


func _test_tour_flaws_scale_with_the_band_and_the_seed() -> void:
	check("count_for(1, false) == 1", TourFlaws.count_for(1, false) == 1)
	check("count_for(2, false) == 2", TourFlaws.count_for(2, false) == 2)
	check("count_for(3, false) == 2", TourFlaws.count_for(3, false) == 2)
	check("count_for(4, false) == 3", TourFlaws.count_for(4, false) == 3)
	check("count_for(5, false) == 3", TourFlaws.count_for(5, false) == 3)
	check("count_for(6, false) == 4", TourFlaws.count_for(6, false) == 4)
	check("count_for(8, false) == 4", TourFlaws.count_for(8, false) == 4)
	check("count_for(12, false) == 4", TourFlaws.count_for(12, false) == 4)
	check("the boss adds one, capped at 5", TourFlaws.count_for(8, true) == 5)

	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	var brief := TourBriefs.brief(0)
	var track_named := func(p: DawKitProject, n: String) -> DawKitTrack:
		for t in p.tracks:
			if t.name == n:
				return t
		return null

	for band in [1, 4, 8]:
		for is_boss in [false, true]:
			var count := TourFlaws.count_for(band, is_boss)
			for seed in range(10):
				var rng := RandomNumberGenerator.new()
				rng.seed = seed
				var song_tempo := TourFlaws.tempo_for(rng)
				var drawn := TourFlaws.draw(rng, count)
				check("band %d boss %s seed %d draws %d distinct flaws" % [band, is_boss, seed, count],
						drawn.size() == count)
				var ids: Array = drawn.map(func(f: TourFlaw) -> StringName: return f.id)
				var unique := {}
				for id in ids:
					unique[id] = true
				check("none repeated", unique.size() == ids.size())
				check("never both wrong_tempo and dragging_keys",
						not (&"wrong_tempo" in ids and &"dragging_keys" in ids))

				var clean := TourProject.song_for(brief, song_tempo, [], RandomNumberGenerator.new())
				var dirty := TourProject.song_for(brief, song_tempo, drawn, rng)
				var affected := {}
				var tempo_flawed := false
				for f in drawn:
					if f.track == "":
						tempo_flawed = true
					else:
						affected[f.track] = true
				for name in TourProject.BAND:
					var ct: DawKitTrack = track_named.call(clean, name)
					var dt: DawKitTrack = track_named.call(dirty, name)
					if affected.has(name):
						check("%s's track changed for this flaw" % name, ct.to_dict() != dt.to_dict())
					else:
						check("%s's track is untouched" % name, ct.to_dict() == dt.to_dict())
				if tempo_flawed:
					check("tempo changed for wrong_tempo", not is_equal_approx(clean.tempo, dirty.tempo))
				else:
					check("tempo unaffected", is_equal_approx(clean.tempo, dirty.tempo))

	var a := TourRun.new()
	a.attempt_seed = 4242
	var b := TourRun.new()
	b.attempt_seed = 4242
	var rng_a := a.song_rng(2)
	var rng_b := b.song_rng(2)
	var tempo_a := TourFlaws.tempo_for(rng_a)
	var tempo_b := TourFlaws.tempo_for(rng_b)
	check("the same attempt_seed draws the same tempo for brief 2", is_equal_approx(tempo_a, tempo_b))
	var ids_a: Array = TourFlaws.draw(rng_a, 3).map(func(f: TourFlaw) -> StringName: return f.id)
	var ids_b: Array = TourFlaws.draw(rng_b, 3).map(func(f: TourFlaw) -> StringName: return f.id)
	check("and the same flaws, in the same order", ids_a == ids_b)

	var tempos := {}
	var first_flaws := {}
	for seed in range(20):
		var run := TourRun.new()
		run.attempt_seed = seed
		var rng := run.song_rng(0)
		tempos[TourFlaws.tempo_for(rng)] = true
		var drawn: Array[TourFlaw] = TourFlaws.draw(rng, 1)
		if not drawn.is_empty():
			first_flaws[drawn[0].id] = true
	check("at least 3 distinct tempos over 20 seeds (%d)" % tempos.size(), tempos.size() >= 3)
	check("at least 3 distinct first flaws over 20 seeds (%d)" % first_flaws.size(), first_flaws.size() >= 3)

	DAW.use(previous, false)


func _test_tour_brief_judges_its_flaws() -> void:
	var brief := TourBrief.new()
	var all_fixed := brief.judge({"flaws": {"fixed": 3, "total": 3, "seconds_left_frac": 0.5}})
	check("all fixed with half the clock left passes with score 80",
			bool(all_fixed["passed"]) and int(all_fixed["score"]) == 80)
	var partial := brief.judge({"flaws": {"fixed": 2, "total": 3, "seconds_left_frac": 0.0}})
	check("2 of 3 fixed fails with score 40",
			not bool(partial["passed"]) and int(partial["score"]) == 40)
	check("no samples at all is still not a pass", not bool(brief.judge({})["passed"]))


func _test_tour_untaken_part_blocks_the_pass() -> void:
	var brief := TourBrief.new()
	var blocked := brief.judge({"flaws": {"fixed": 2, "total": 2, "seconds_left_frac": 0.5},
			"parts": {"played": 0, "total": 1}})
	check("a part nobody took blocks the pass even with every flaw fixed", not bool(blocked["passed"]))
	var cleared := brief.judge({"flaws": {"fixed": 2, "total": 2, "seconds_left_frac": 0.5},
			"parts": {"played": 1, "total": 1}})
	check("and clearing it passes", bool(cleared["passed"]))
	check("the score reflects both, flaws and parts averaged (%d vs %d)" % [blocked["score"], cleared["score"]],
			int(cleared["score"]) > int(blocked["score"]))


func _test_tour_parts_scale_with_the_band_and_the_seed() -> void:
	check("count_for(1, false) == 1 -- solo holds one job at a time", TourParts.count_for(1, false) == 1)
	check("count_for(2, false) == 2", TourParts.count_for(2, false) == 2)
	check("count_for(3, false) == 3 -- one per instrument the room has", TourParts.count_for(3, false) == 3)
	check("count_for(4, false) == 3", TourParts.count_for(4, false) == 3)
	check("count_for(8, false) == 3", TourParts.count_for(8, false) == 3)
	check("the boss adds nothing -- nothing more in the room to hold a fourth",
			TourParts.count_for(8, true) == 3)

	for seed in range(20):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var drawn := TourParts.draw(rng, TourParts.count_for(8, false))
		var instruments := {}
		for p: TourPart in drawn:
			check("seed %d never draws two parts for the same instrument" % seed,
					not instruments.has(p.instrument))
			instruments[p.instrument] = true

	var a := TourRun.new()
	a.attempt_seed = 777
	var b := TourRun.new()
	b.attempt_seed = 777
	var rng_a := a.song_rng(1)
	var drawn_a := TourParts.draw(rng_a, 3)
	var holders_a := TourParts.assign(rng_a, drawn_a, [1, 2, 3, 4, 5, 6, 7, 8])
	var rng_b := b.song_rng(1)
	var drawn_b := TourParts.draw(rng_b, 3)
	var holders_b := TourParts.assign(rng_b, drawn_b, [1, 2, 3, 4, 5, 6, 7, 8])
	check("the same attempt_seed draws the same parts",
			drawn_a.map(func(p: TourPart) -> StringName: return p.id)
			== drawn_b.map(func(p: TourPart) -> StringName: return p.id))
	check("and hands them to the same holders", holders_a == holders_b)

	var unique := {}
	for h in holders_a:
		unique[h] = true
	check("three parts to eight peers go to three distinct people (%s)" % [holders_a], unique.size() == 3)

	var solo_parts := TourParts.draw(RandomNumberGenerator.new(), 1)
	var solo_holders := TourParts.assign(RandomNumberGenerator.new(), solo_parts, [1])
	check("solo holds its own one part", solo_holders == [1])

	var first_ids := {}
	for seed in range(20):
		var run := TourRun.new()
		run.attempt_seed = seed
		var drawn: Array[TourPart] = TourParts.draw(run.song_rng(0), 1)
		if not drawn.is_empty():
			first_ids[drawn[0].id] = true
	check("at least 3 distinct first parts over 20 seeds (%d)" % first_ids.size(), first_ids.size() >= 3)


func _test_tour_song_has_a_stage_lane() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	TourProject.load(TourProject.song_for(TourBriefs.brief(0), 100.0, [], rng), backend)

	check("STAGE_TRACK and KEYS_TRACK agree with Tour's own",
			TourProject.STAGE_TRACK == Tour.STAGE_TRACK and TourProject.KEYS_TRACK == Tour.TIMING_TRACK
			and Tour.TIMING_TRACK == 2)
	var stage := DAW.state.track(TourProject.STAGE_TRACK)
	check("track 1 is Stage", stage.name == "Stage")
	check("armed, for midi, no clip, no DemoSong role of its own",
			stage.rec_arm and stage.input == "midi" and stage.items.is_empty() and stage.part == "")
	check("so it is the one HitRecorder picks up, being the first armed track",
			HitRecorder.armed_track() == TourProject.STAGE_TRACK)

	DAW.use(previous, false)


func _test_tour_part_is_played_by_notes_on_its_lane() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	TourProject.load(TourProject.song_for(TourBriefs.brief(0), 100.0, [], RandomNumberGenerator.new()), backend)
	var beat := 60.0 / 100.0
	var rhythm := TourMeasure.Rhythm.new()

	# Eight tambourine hits, dead on 2 and 4 of four bars: clears the backbeat part, but not the
	# shaker's (wrong pitch) nor the keytar's (wrong channel).
	var on_grid: Array = []
	for k in 4:
		for b in [1.0, 3.0]:
			var on: float = (k * 4.0 + b) * beat
			on_grid.append([on, on + 0.05, 54, 104, HitRecorder.CHANNEL])
	DAW.insert_midi_take(TourProject.STAGE_TRACK, on_grid[0][0], on_grid.back()[1] + 1.0, on_grid, "tambourine")

	var tamb_backbeat := TourParts.by_id(&"tamb_backbeat")
	rhythm.start(TourProject.STAGE_TRACK, 0.0, tamb_backbeat)
	var r := rhythm.result()
	check("eight hits on 2 and 4 clear tamb_backbeat (%s)" % [r], tamb_backbeat.played(r))

	var shaker_eighths := TourParts.by_id(&"shaker_eighths")
	rhythm.start(TourProject.STAGE_TRACK, 0.0, shaker_eighths)
	check("but not shaker_eighths -- wrong pitch", not shaker_eighths.played(rhythm.result()))

	var keys_one := TourParts.by_id(&"keys_one")
	rhythm.start(TourProject.STAGE_TRACK, 0.0, keys_one)
	check("nor keys_one -- wrong channel", not keys_one.played(rhythm.result()))

	DAW.state.track(TourProject.STAGE_TRACK).items.clear()

	# Eight off-grid tambourine hits (on the one and the three, a full beat from either target):
	# flailing, not playing.
	var off_grid: Array = []
	for k in 4:
		for b in [0.0, 2.0]:
			var on: float = (k * 4.0 + b) * beat
			off_grid.append([on, on + 0.05, 54, 100, HitRecorder.CHANNEL])
	DAW.insert_midi_take(TourProject.STAGE_TRACK, off_grid[0][0], off_grid.back()[1] + 1.0, off_grid, "flail")
	rhythm.start(TourProject.STAGE_TRACK, 0.0, tamb_backbeat)
	check("eight off-grid hits do not clear it", not tamb_backbeat.played(rhythm.result()))
	DAW.state.track(TourProject.STAGE_TRACK).items.clear()

	# Four channel-0 notes on the one: the keytar's part, whatever pitch the chord was.
	var keys_notes: Array = []
	for k in 4:
		var on: float = (k * 4.0) * beat
		keys_notes.append([on, on + 0.1, 60, 100, 0])
	DAW.insert_midi_take(TourProject.STAGE_TRACK, keys_notes[0][0], keys_notes.back()[1] + 1.0, keys_notes, "keys")
	rhythm.start(TourProject.STAGE_TRACK, 0.0, keys_one)
	check("four stabs on the one clear keys_one", keys_one.played(rhythm.result()))

	DAW.use(previous, false)


func _test_tour_open_part_is_reassigned_after_the_grace() -> void:
	var run := TourRun.new()
	run.parts = [&"tamb_backbeat", &"shaker_eighths"]
	run.holders = [7, 3]
	run.hits = [0, 0]
	run.played = [false, false]
	run.open_since = [0.0, 0.0]
	run.seconds_left = 40.0

	TourParts.open(run, 7)
	check("the departed peer's part goes open, timestamped by the clock",
			run.holders == [0, 3] and is_equal_approx(run.open_since[0], 40.0))

	run.seconds_left = 40.0 - (TourParts.PART_GRACE - 1.0)
	var too_soon: Array[bool] = [run.open_since[0] - run.seconds_left >= TourParts.PART_GRACE, false]
	check("before the grace, nothing changes",
			TourParts.reassign(run, [1, 3], too_soon) == 0 and run.holders == [0, 3])

	# A second part opens later: past the first's grace, only the first is handed on.
	run.seconds_left = 40.0 - TourParts.PART_GRACE
	TourParts.open(run, 3)
	var ready: Array[bool] = [run.open_since[0] - run.seconds_left >= TourParts.PART_GRACE,
			run.open_since[1] - run.seconds_left >= TourParts.PART_GRACE]
	var winner := TourParts.reassign(run, [1, 3], ready)
	check("past the grace, the fewest-parts peer (1, who holds none yet) takes it over (%d)" % winner,
			winner == 1 and run.holders[0] == 1)
	check("while a part still inside its own grace stays open (%s)" % [run.holders], run.holders == [1, 0])

	run.seconds_left -= TourParts.PART_GRACE
	ready = [false, run.open_since[1] - run.seconds_left >= TourParts.PART_GRACE]
	winner = TourParts.reassign(run, [1, 3], ready)
	check("and once its own grace is out it goes to whoever holds fewest, 3 (%d)" % winner,
			winner == 3 and run.holders == [1, 3])


func _test_tour_run_round_trips_parts_with_eight_peers() -> void:
	var run := TourRun.new()
	run.parts = [&"tamb_backbeat", &"shaker_eighths", &"keys_one"]
	run.holders = [8, 0, 3]
	run.hits = [4, 0, 2]
	run.played = [true, false, false]
	run.open_since = [0.0, 12.5, 0.0]
	var back := TourRun.from_dict(run.to_dict())
	check("parts ride the wire", back.parts == run.parts)
	check("holders, peer ids up to eight and 0 for open", back.holders == run.holders)
	check("hits", back.hits == run.hits)
	check("played", back.played == run.played)
	check("and open_since", back.open_since == run.open_since)


## The whole host-side loop a part goes through, with the real brief tick: notes land on the
## Stage lane by the same DAW verb both recorders use (insert_midi_take), `_tick_parts` reads
## them back as hits, and `_physics_process` will not pass the brief -- every flaw fixed -- until
## the part is played too. No notes, no pass; eight on the backbeat, and it is into the draft.
func _test_tour_brief_ticks_a_part_off_the_stage_lane_and_gates_the_pass() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	Session.start_solo()
	var saved_run := Tour.run
	var brief := TourBriefs.brief(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	TourProject.load(TourProject.song_for(brief, 100.0, [], rng), backend)
	# Nothing baked, and the vocal's fader put where quiet_vox reads as fixed: the gate under
	# test is the part's alone.
	DAW.set_track_volume(TourProject.BAND.find("Lead Vox") + 1, DAW.db_to_taper(0.0))

	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.tuning = false
	run.brief_index = 0
	run.band_size = 1
	run.song_tempo = 100.0
	run.flaws = [&"quiet_vox"]
	run.fixed = [false]
	run.parts = [&"tamb_backbeat"]
	run.holders = [1]
	run.hits = [0]
	run.played = [false]
	run.open_since = [0.0]
	run.seconds_left = brief.seconds
	Tour.run = run

	Tour._physics_process(0.1)
	check("the one flaw reads fixed off the desk", run.fixed == [true])
	check("but with the part unplayed the brief runs on, clock ticking (%s, %.1f s)" % [run.played, run.seconds_left],
			run.state == TourRun.State.BRIEF and run.played == [false] and run.seconds_left < brief.seconds)

	var beat := 60.0 / 100.0
	var hits: Array = []
	for k in 4:
		for b in [1.0, 3.0]:
			var on: float = (k * 4.0 + b) * beat
			hits.append([on, on + 0.05, 54, 104, HitRecorder.CHANNEL])
	DAW.insert_midi_take(Tour.STAGE_TRACK, hits[0][0], hits.back()[1] + 1.0, hits, "Ada percussion 1")
	Tour._physics_process(0.1)
	check("eight hits on 2 and 4 tick the part off the Stage lane (%d/8)" % run.hits[0],
			run.hits[0] == 8 and run.played == [true])
	check("and the brief passes into the draft, scored (%d)" % run.score,
			run.state == TourRun.State.DRAFTING and run.score > 0)

	Tour.run = saved_run
	DAW.use(previous, false)


## The HUD's part lines: who holds each one, by name -- "YOU" for this player's own, so a job is
## found at a glance -- "OPEN" once its holder has left, the count against what is needed, and
## the tag's PARTS count beside FIXED.
func _test_tour_hud_names_who_holds_each_part() -> void:
	var saved_run := Tour.run
	_as_session(Session.Role.HOST, 1)
	Session._register(1, "Ada", 0)
	Session._register(2, "Grace", 1)
	var hud := TourHud.new()
	add_child(hud)
	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.band_size = 2
	run.song_tempo = 100.0
	run.flaws = [&"quiet_vox"]
	run.fixed = [false]
	run.parts = [&"tamb_backbeat", &"keys_one"]
	run.holders = [1, 2]
	run.hits = [3, 0]
	run.played = [false, false]
	run.open_since = [0.0, 0.0]
	Tour.run = run
	hud._refresh()
	var mine := hud._parts_box.get_node_or_null("Part0") as Label
	var theirs := hud._parts_box.get_node_or_null("Part1") as Label
	check("two part lines (%d)" % hud._parts_box.get_child_count(), hud._parts_box.get_child_count() == 2)
	check("this player's own line says YOU, the instrument, the job and the count (%s)" % (mine.text if mine else "none"),
			mine != null and mine.text == "YOU  " + TourParts.by_id(&"tamb_backbeat").line + "  3/8"
			and mine.get_theme_color("font_color") == TourHud.INK)
	check("the other's names them (%s)" % (theirs.text if theirs else "none"),
			theirs != null and theirs.text.begins_with("GRACE  KEYTAR: ")
			and theirs.get_theme_color("font_color") == TourHud.DIM)
	check("the tag counts parts beside fixes (%s)" % hud._tag.text, hud._tag.text == "BAND OF 2   0 / 1 FIXED   0 / 2 PARTS")

	TourParts.open(run, 2)
	run.played[0] = true
	run.hits[0] = 8
	# Both, as `_process` does each frame: the tag is `_refresh_flaws`'s.
	hud._refresh_flaws(run)
	hud._refresh_parts(run)
	check("a leaver's part reads OPEN in the curse colour (%s)" % theirs.text,
			theirs.text.begins_with("OPEN  ") and theirs.get_theme_color("font_color") == TourHud.CURSE)
	check("a played one lights up (%s)" % mine.text,
			mine.text.ends_with("  8/8") and mine.get_theme_color("font_color") == TourHud.ACCENT)
	check("and the tag ticks it (%s)" % hud._tag.text, hud._tag.text.ends_with("1 / 2 PARTS"))

	Tour.run = saved_run
	remove_child(hud)
	hud.free()
	Session.start_solo()


## A card is applied once the next brief's song is in, so its DAW side lands on that song --
## and before that brief's clock is set, so "shorter_clock" shortens the brief it was picked
## into, not the one after.
func _test_a_shorter_clock_card_shortens_the_very_next_brief() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	var saved_run := Tour.run
	var card: TourCard = null
	for c in TourDeck.all_cards():
		if c.id == &"shorter_clock":
			card = c
	check("the deck has a shorter_clock card", card != null)

	Tour.run = TourRun.new()
	Tour.run.attempt_seed = 99
	Tour._start_brief(1, card)
	var brief := TourBriefs.brief(1)
	check("the brief the card was picked into runs on three quarters of its clock (%.1f)" % Tour.run.seconds_left,
			is_equal_approx(Tour.run.seconds_left, brief.seconds * 0.75))
	check("and the multiplier is spent on it, not carried on", is_equal_approx(Tour.run.next_brief_seconds_mult, 1.0))
	check("the rescue song is in underneath", DAW.state.track_indices().size() == TourProject.BAND.size()
			and Tour.run.flaws.size() == TourFlaws.count_for(Session.participants.size(), false))
	check("and the brief opens at soundcheck", Tour.run.tuning and Tour.run.state == TourRun.State.BRIEF)

	Tour.run = saved_run
	DAW.use(previous, false)


## The HUD's flaw lines, as the host sees them: named by strip, ticked by `_refresh_flaws` with
## no signal (the host's `_tick_flaws` publishes to the room only), and rebuilt clean for the
## next brief inside one frame -- a stale label queued for freeing must not swallow the new
## line of the same name.
func _test_tour_hud_rebuilds_its_flaw_lines_for_the_next_brief() -> void:
	var saved_run := Tour.run
	var hud := TourHud.new()
	add_child(hud)
	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.band_size = 3
	run.song_tempo = 108.0
	run.flaws = [&"quiet_vox"]
	run.fixed = [false]
	Tour.run = run
	hud._refresh()
	var first := hud._flaws_box.get_node_or_null("Flaw0") as Label
	check("the first brief's one line names the strip, then the trouble (%s)" % (first.text if first else "none"),
			first != null and first.text == "--  LEAD VOX: " + TourFlaws.by_id(&"quiet_vox").line)
	check("the tag counts the band and the fixes (%s)" % hud._tag.text, hud._tag.text == "BAND OF 3   0 / 1 FIXED")
	run.fixed = [true]
	hud._refresh_flaws(run)
	check("a fix ticks the line and the tag without a signal (%s / %s)" % [first.text, hud._tag.text],
			first.text.begins_with("OK ") and hud._tag.text == "BAND OF 3   1 / 1 FIXED")

	run.flaws = [&"wrong_tempo", &"hard_pan"]
	run.fixed = [false, false]
	hud._refresh()
	check("the next brief shows two lines and nothing left of the first (%d)" % hud._flaws_box.get_child_count(),
			hud._flaws_box.get_child_count() == 2)
	var l0 := hud._flaws_box.get_node_or_null("Flaw0") as Label
	var l1 := hud._flaws_box.get_node_or_null("Flaw1") as Label
	check("the deck's line carries the setlist tempo (%s)" % (l0.text if l0 else "none"),
			l0 != null and l0.text == "--  DECK: Someone kicked the deck. The setlist says 108 BPM.")
	check("the guitar's points at its strip (%s)" % (l1.text if l1 else "none"),
			l1 != null and l1.text.begins_with("--  GTR AMP: "))
	check("and the tag is this brief's", hud._tag.text == "BAND OF 3   0 / 2 FIXED")

	Tour.run = saved_run
	remove_child(hud)
	hud.free()


# --- the Tour case (Work Package B) ------------------------------------------------------

func _test_tour_case_breaks_after_enough_hits_and_resets() -> void:
	var case := TourCase.new()
	add_child(case)
	var opened := [0]
	case.broken_open.connect(func(): opened[0] += 1)
	for i in TourCase.HITS_TO_BREAK - 1:
		case.struck(3.0, 1)
	check("not broken before enough hits", not case.broken and opened[0] == 0)
	case.struck(3.0, 1)
	check("the hit that reaches the threshold bursts it open, once", case.broken and opened[0] == 1)
	check("the chain comes off", case._chain == null or not case._chain.visible)
	case.struck(3.0, 1)
	check("a hit once it is open does nothing further", opened[0] == 1 and case.hits == TourCase.HITS_TO_BREAK)
	case.reset(3, 1)
	check("reset chains it again", not case.broken and case.hits == 0)
	check("the chain is back", case._chain == null or case._chain.visible)
	check("and its tally is brought up to date (%s)" % case._tally.text,
			case._tally.text.contains("3") and case._tally.text.contains("1"))
	case.show_seed(123456)
	check("show_seed swaps the tally for the run's own number (%s)" % case._tally.text,
			case._tally.text.contains("123456"))
	case.reset(4, 2)
	check("and reset puts the RUNS/WINS tally back (%s)" % case._tally.text,
			case._tally.text.contains("4") and case._tally.text.contains("2")
			and not case._tally.text.contains("123456"))
	remove_child(case)
	case.free()


## `muted_track`'s pick rides the run's own seed (TourDeck.all_cards, deck.gd) like every other
## draw: the same `attempt_seed`/`brief_index` mutes the same track given the same starting mix,
## a different `brief_index` can (not must -- it is still one roll of a die) land on another.
func _test_tour_deck_muted_track_draws_off_the_runs_own_seed() -> void:
	var previous := DAW.backend

	var mute_with := func(seed: int, brief_index: int) -> int:
		DAW.use(OfflineBackend.new())
		var run := TourRun.new()
		run.attempt_seed = seed
		run.brief_index = brief_index
		for c in TourDeck.all_cards():
			if c.id == &"muted_track":
				c.apply(run)
		var muted := -1
		for t: MixState.TrackState in DAW.state.tracks.values():
			if t.mute:
				muted = t.index
				break
		return muted

	var a: int = mute_with.call(42, 0)
	var b: int = mute_with.call(42, 0)
	check("the same seed and brief mute the same track both times (%d, %d)" % [a, b], a == b and a != -1)
	DAW.use(previous, false)


func _test_item_room_target_struck_finds_the_nearest_one_in_range() -> void:
	var room := ItemRoom.new()
	add_child(room)
	var near := TourCase.new()
	var far := TourCase.new()
	far.position = Vector3(2.0, 0, 0)
	room.add_child(near)
	room.add_child(far)
	room.targets = [{"node": near, "radius": 0.4}, {"node": far, "radius": 0.4}]
	check("the nearer one in range is struck, and the farther one is left alone",
			room.target_struck(3.0, Vector3(0.1, 0, 0), 1) and near.hits == 1 and far.hits == 0)
	check("a point outside every radius finds nothing", not room.target_struck(3.0, Vector3(5.0, 0, 0), 1))
	remove_child(room)
	room.free()


## Not just the toast: a guest's hits must not advance the case toward breaking at all, even
## though the toast and the host's own hits both still work -- the host flies every valid
## throw, guest's included (see item.gd's test "the host flies a guest's throw"), so the gate
## has to be on `thrown_by`, not on who is watching.
func _test_only_the_host_can_break_the_case() -> void:
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	var notices: Array[String] = []
	var hear := func(t: String): notices.append(t)
	Session.notice.connect(hear)

	_as_session(Session.Role.GUEST, 5)
	studio.tour_case.break_attempted.emit()
	check("a guest's hit never starts a run", Tour.run == null)
	check("and is told only the host can break the case (%s)" % [notices],
			notices.size() == 1 and notices[0].begins_with("Only ")
			and notices[0].ends_with("can start the tour."))

	notices.clear()
	_as_session(Session.Role.HOST, 1)
	studio.tour_case.break_attempted.emit()
	check("the host's own hit draws no toast", notices.is_empty())

	var case := studio.tour_case
	var opened := [0]
	case.broken_open.connect(func(): opened[0] += 1)
	for i in TourCase.HITS_TO_BREAK + 2:
		case.struck(3.0, 5)
	check("a guest's throws never add up to a break, however many",
			not case.broken and opened[0] == 0 and case.hits == 0)
	for i in TourCase.HITS_TO_BREAK - 1:
		case.struck(3.0, 1)
		case.struck(3.0, 5)
	check("a guest's hits mixed in with the host's don't speed it up (%d)" % case.hits,
			case.hits == TourCase.HITS_TO_BREAK - 1 and not case.broken)
	notices.clear()
	case.struck(3.0, 1)
	check("but the host's own fifth, even with a guest's mixed in, really breaks it",
			opened[0] == 1)
	check("and on an engine a tour cannot run on, says why and chains itself again (%s)" % [notices],
			notices.size() == 1 and "--built-in" in notices[0] and not case.broken and case.hits == 0)

	# A click on the case is a knock by whoever is at this machine.
	var knock := case.find_children("*", "ControlAffordance", false, false)[0] as ControlAffordance
	_as_session(Session.Role.GUEST, 5)
	knock._on_grab_begin(Vector3.ZERO)
	check("a guest's knock by hand counts for nothing either", case.hits == 0)
	_as_session(Session.Role.HOST, 1)
	knock._on_grab_begin(Vector3.ZERO)
	knock._on_grab_begin(Vector3.ZERO)
	check("the host's knocks by hand count toward the break (%d)" % case.hits, case.hits == 2)
	check("and the case says how many (%s)" % knock._default_readout(),
			knock._default_readout() == "2 of %d knocks" % TourCase.HITS_TO_BREAK)

	Session.notice.disconnect(hear)
	remove_child(studio)
	studio.free()
	Session.start_solo()


func _test_tour_venue_solids_include_the_case() -> void:
	for id in Venue.IDS:
		var venue := Venue.make(id)
		add_child(venue)
		var at := venue.tour_case_spot()
		var found := false
		for f: Dictionary in venue.solids():
			if (f.get("c") as Vector2).is_equal_approx(Vector2(at.origin.x, at.origin.z)):
				found = true
				break
		# A venue that only draws its furniture (the chalk zone -- see `prop_shelf_solid`) draws
		# the case the same way, same as the shelf and the hoop: not a walker obstacle there.
		check("the %s's solids include the Tour case" % id, found == venue.prop_shelf_solid())
		remove_child(venue)
		venue.free()


## Instruments spilling out of the case: `Tour.spill` puts a real item in the host's own room
## (`Tour.instrument_spilled`, wired in `_build_tour_case`), the second copy out is the low
## voice, a third finds nothing left to give, the run remembers all of it through a round trip,
## and the run ending takes every spilled copy back out of the room.
func _test_tour_spill_puts_a_real_item_in_the_room() -> void:
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	_as_session(Session.Role.HOST, 1)
	Tour.run = TourRun.new()
	Tour.run.state = TourRun.State.BRIEF

	check("the first cowbell out of the case is the plain one", Tour.spill(&"cowbell") == &"cowbell")
	check("the run remembers it", Tour.run.instruments == [&"cowbell"])
	var item: Item = studio.items.items.get(&"cowbell")
	check("a real item in the room, tossed out flying", item is CowbellItem and item.is_flying())
	var room_items: Dictionary = studio.room_state()["items"]
	check("and an 8-wide entry rides the room (%s)" % [room_items.get(&"cowbell")],
			room_items.has(&"cowbell") and (room_items[&"cowbell"] as Array).size() == 8)

	check("the second is the low voice", Tour.spill(&"cowbell") == &"cowbell2")
	var low: CowbellItem = studio.items.items.get(&"cowbell2")
	check("voice 1, pitched the low agogo (%d)" % low.pitch(), low.voice == 1 and low.pitch() == 68)

	check("a third finds no copies left", Tour.spill(&"cowbell") == &"")

	# A peer leaving unmarks what was theirs in any run state, not only mid-brief: a leaver
	# during the draft must not leave a brick behind.
	Tour.run.instrument_bound[1] = 7
	Tour.run.state = TourRun.State.DRAFTING
	Tour._on_participant_left(7)
	check("a leaver's mark is cleared even while drafting", Tour.run.instrument_bound == [0, 0])
	Tour.run.state = TourRun.State.BRIEF

	var back := TourRun.from_dict(Tour.run.to_dict())
	check("instruments round-trip through the dict", back.instruments == Tour.run.instruments)
	check("so do their curses and who they are bound to",
			back.instrument_curses == Tour.run.instrument_curses
			and back.instrument_bound == Tour.run.instrument_bound)

	studio._on_tour_run_ended(false)
	check("the run ending clears both out of the room",
			not studio.items.items.has(&"cowbell") and not studio.items.items.has(&"cowbell2"))
	check("and out of the published room", not (studio.room_state()["items"] as Dictionary).has(&"cowbell"))

	Tour.run = null
	remove_child(studio)
	studio.free()
	_as_session(Session.Role.SOLO, 1)


## The run's own result, told to the room -- a different line for a win than a loss, the fresh
## `Tour.unlocks.reputation` (already bumped by `Tour._end_run`'s own `unlocks.record_run` before
## this ever runs) read straight into it rather than a stale copy.
func _test_tour_run_ended_announces_the_result_to_the_room() -> void:
	DAW.use(OfflineBackend.new())
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	_as_session(Session.Role.HOST, 1)

	var heard: Array[String] = []
	var hear := func(t: String) -> void: heard.append(t)
	Session.notice.connect(hear)

	Tour.unlocks.reputation = 4
	studio._on_tour_run_ended(true)
	check("a win announces the result with the fresh reputation (%s)" % [heard],
			not heard.is_empty() and heard.back().contains("4")
			and heard.back().to_lower().contains("hit"))

	heard.clear()
	Tour.unlocks.reputation = 4
	studio._on_tour_run_ended(false)
	check("a loss announces too, a different line (%s)" % [heard],
			not heard.is_empty() and heard.back().contains("4")
			and not heard.back().to_lower().contains("hit"))

	Session.notice.disconnect(hear)
	remove_child(studio)
	studio.free()
	_as_session(Session.Role.SOLO, 1)


## A guest never hears `Tour.instrument_spilled` (host-only, see Tour's own class note) -- it
## learns the same thing off `Session.tour`'s `instruments`, through `_sync_spilled`.
func _test_tour_guest_spawns_spilled_instruments_from_the_run() -> void:
	DAW.use(OfflineBackend.new())
	_as_session(Session.Role.GUEST, 5)
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)

	var notices: Array[String] = []
	var hear := func(t: String) -> void: notices.append(t)
	Session.notice.connect(hear)
	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.instruments = [&"woodblock", &"pad"]
	run.instrument_curses = [&"", &"bound"]
	run.instrument_bound = [0, 3]
	Session.tour = run.to_dict()
	Session.tour_changed.emit()

	var block: Item = studio.items.items.get(&"woodblock")
	var pad: Item = studio.items.items.get(&"pad")
	check("a guest spawns both spilled instruments off the run", block is WoodblockItem and pad is PadItem)
	check("the marked one is bound to its peer, by name",
			pad.bound_to == 3 and pad.bound_name == Session.name_of(3))
	# Counted by text rather than in total: a Studio an earlier synchronous test queue_freed is
	# still wired to `Session.tour_changed` until the frame ends, and says the same things.
	var block_told := func() -> int:
		return notices.filter(func(t: String) -> bool: return t == "A woodblock fell out of the case.").size()
	var pad_told := func() -> int:
		return notices.filter(func(t: String) -> bool:
			return t.begins_with("A drum pad fell out of the case, marked for")).size()
	check("and is told of each, like the host is (%s)" % [notices],
			block_told.call() >= 1 and pad_told.call() == block_told.call())
	var told_before: Array = [block_told.call(), pad_told.call()]

	# The mark leaves with its peer (Tour._on_participant_left, published): a guest told again
	# unbinds its own copy.
	run.instrument_bound = [0, 0]
	Session.tour = run.to_dict()
	Session.tour_changed.emit()
	check("a mark cleared in the run is cleared on the item", pad.bound_to == 0 and pad.bound_name == "")
	check("without telling of the spill twice", [block_told.call(), pad_told.call()] == told_before)

	Session.tour = {}
	Session.tour_changed.emit()
	check("the run ending takes them with it",
			not studio.items.items.has(&"woodblock") and not studio.items.items.has(&"pad"))
	Session.notice.disconnect(hear)

	remove_child(studio)
	studio.free()
	_as_session(Session.Role.SOLO, 1)


## The twelve new parts are judged exactly like the original seven (TourMeasure.Rhythm, by
## channel and pitch, not by who played them), and every spilled kind's cataloged pitch agrees
## with the real item's own `pitch()` -- the one fact the judge and the room must never disagree
## on, kept honest here rather than only by eye (see docs/loop_backlog.md's "Tour" section).
func _test_tour_new_parts_are_judged_by_their_instruments_pitch() -> void:
	# `insert_midi_take` goes nowhere without authority, so this is explicit rather than
	# trusting whatever role an earlier test left behind.
	_as_session(Session.Role.SOLO, 1)
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	TourProject.load(TourProject.song_for(TourBriefs.brief(0), 100.0, [], RandomNumberGenerator.new()), backend)
	var beat := 60.0 / 100.0
	var rhythm := TourMeasure.Rhythm.new()

	var on_grid: Array = []
	for k in 4:
		var on: float = (k * 4.0) * beat
		on_grid.append([on, on + 0.05, 56, 100, HitRecorder.CHANNEL])
	DAW.insert_midi_take(TourProject.STAGE_TRACK, on_grid[0][0], on_grid.back()[1] + 1.0, on_grid, "cowbell")

	var cowbell_one := TourParts.by_id(&"cowbell_one")
	rhythm.start(TourProject.STAGE_TRACK, 0.0, cowbell_one)
	var r := rhythm.result()
	check("four clanks on the one clear cowbell_one (%s)" % [r], cowbell_one.played(r))
	var cowbell_four := TourParts.by_id(&"cowbell_four")
	rhythm.start(TourProject.STAGE_TRACK, 0.0, cowbell_four)
	check("but not cowbell_four -- not enough of them", not cowbell_four.played(rhythm.result()))
	var lowbell_backbeat := TourParts.by_id(&"lowbell_backbeat")
	rhythm.start(TourProject.STAGE_TRACK, 0.0, lowbell_backbeat)
	check("nor lowbell_backbeat -- wrong pitch", not lowbell_backbeat.played(rhythm.result()))

	DAW.state.track(TourProject.STAGE_TRACK).items.clear()
	DAW.use(previous, false)

	var pairs := [[&"cowbell_one", CowbellItem.new(), 0], [&"lowbell_backbeat", CowbellItem.new(), 1],
			[&"block_offbeats", WoodblockItem.new(), 0], [&"lowblock_one_three", WoodblockItem.new(), 1],
			[&"pad_four", PadItem.new(), 0], [&"lowpad_one", PadItem.new(), 1],
			[&"triangle_turnaround", TriangleItem.new(), 0], [&"mute_triangle_backbeat", TriangleItem.new(), 1],
			[&"claves_one", ClavesItem.new(), 0], [&"lowclaves_backbeat", ClavesItem.new(), 1],
			[&"hihat_eighths", HihatItem.new(), 0], [&"openhat_backbeat", HihatItem.new(), 1],
			[&"bongo_eighths", BongoItem.new(), 0], [&"lowbongo_backbeat", BongoItem.new(), 1]]
	for pair in pairs:
		var part: TourPart = TourParts.by_id(pair[0])
		var item: InstrumentItem = pair[1]
		item.voice = pair[2]
		check("%s's catalogued pitch (%s) agrees with the real item's (%d)" % [pair[0], part.pitches, item.pitch()],
				part.pitches.size() == 1 and part.pitches[0] == item.pitch())
		item.free()


## `Interactor.pick_up` refuses an item marked for somebody else (`Item.may_hold`), and the room
## says so (`ItemRoom.refused`) -- the hand it is marked for takes it exactly as any other item.
func _test_tour_marked_instrument_refuses_another_hand() -> void:
	var room := ItemRoom.new()
	add_child(room)
	room.local_peer = func() -> int: return 5
	var item := room.spawn(&"cowbell", &"cowbell", Transform3D.IDENTITY)
	item.bound_to = 2
	item.bound_name = "Grace"

	var refused: Array = []
	room.refused.connect(func(it: Item, why: String) -> void: refused.append([it.id, why]))
	var hand := Interactor.new()
	hand.pick_up(item)
	check("a hand that is not who it is marked for is refused, and the room says whose it is",
			item.carried_by == null and refused == [[&"cowbell", "Grace"]])

	room.local_peer = func() -> int: return 2
	hand.pick_up(item)
	check("but the hand it is marked for takes it", item.carried_by == hand)

	# The host's own arbitration, not only the hand's: a claim from the wrong peer is refused
	# (`Session.holdable`, set by the studio to the item's `bound_to`), naming whose it is.
	_as_session(Session.Role.HOST, 1)
	var refusals: Array = []
	var hear := func(key: String, holder: int) -> void: refusals.append([key, holder])
	Session.hold_refused.connect(hear)
	Session.holdable = func(key: String, _peer: int) -> int:
		return item.bound_to if key == item.network_key() else 0
	Session._grant(5, item.network_key())
	check("the host refuses a claim on a marked item from any other peer",
			not Session.holds.has(item.network_key()))
	Session._grant(1, item.network_key())
	check("its own hand too, and is told whose it is (%s)" % [refusals],
			not Session.holds.has(item.network_key()) and refusals == [[item.network_key(), 2]])
	Session._grant(2, item.network_key())
	check("but the peer it is marked for is granted it", Session.holds.get(item.network_key(), 0) == 2)
	item.bound_to = 0
	Session.holds.clear()
	Session._grant(5, item.network_key())
	check("unmarked, anyone's", Session.holds.get(item.network_key(), 0) == 5)
	Session.hold_refused.disconnect(hear)
	Session.holdable = Callable()
	_as_session(Session.Role.SOLO, 1)

	# A guest's own copy of the shelf: the darts are KINDS ids that end in a digit, and the
	# ghost's look-alike of one must still be a dart, not the nothing `make(&"dart")` gives.
	check("kind_of leaves a shelf id alone", ItemRoom.kind_of(&"dart2") == &"dart2")
	check("so a ghost carrying a dart still shows one", ItemRoom.look_of(&"dart2") != null)
	check("while a spilled id gives its kind", ItemRoom.kind_of(&"cowbell2") == &"cowbell")

	hand.queue_free()
	remove_child(room)
	room.free()


## `TourParts.count_for` scales with how many instruments are actually in the room, not the
## fixed three; `first_spill` seeds a big band's first brief with something to do already; and
## `draw`/`assign` can fill eight parts on eight distinct instruments when the case has spilled
## enough of them, while an ordinary room (the default `available`) still caps at three.
func _test_tour_parts_count_the_instruments_in_the_room() -> void:
	check("count_for(8, false, 3) == 3 -- the room alone", TourParts.count_for(8, false, 3) == 3)
	check("count_for(8, false, 9) == 8 -- a full case", TourParts.count_for(8, false, 9) == 8)
	check("count_for(1, false, 9) == 1 -- solo still holds one job at a time",
			TourParts.count_for(1, false, 9) == 1)

	var empty_rng := RandomNumberGenerator.new()
	empty_rng.seed = 11
	check("a band of 3 or fewer spills nothing at the start", TourParts.first_spill(empty_rng, 3).is_empty())
	for pair in [[4, 1], [5, 2], [6, 3], [7, 4], [8, 5]]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		check("band %d seeds %d kind(s) already out of the case" % [pair[0], pair[1]],
				TourParts.first_spill(rng, pair[0]).size() == pair[1])
	var a := RandomNumberGenerator.new()
	a.seed = 42
	var b := RandomNumberGenerator.new()
	b.seed = 42
	check("the same seed spills the same kinds", TourParts.first_spill(a, 8) == TourParts.first_spill(b, 8))

	var six: Array[StringName] = [&"cowbell", &"cowbell2", &"woodblock", &"woodblock2", &"pad", &"pad2"]
	var available: Array[StringName] = TourParts.ROOM + six
	var rng8 := RandomNumberGenerator.new()
	rng8.seed = 5
	var drawn := TourParts.draw(rng8, 8, available)
	check("a full case draws all 8 parts", drawn.size() == 8)
	var instruments := {}
	for p: TourPart in drawn:
		instruments[p.instrument] = true
	check("on 8 distinct instruments (%s)" % [instruments.keys()], instruments.size() == 8)
	var roster: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
	var holders := TourParts.assign(rng8, drawn, roster)
	var unique := {}
	for h in holders:
		unique[h] = true
	check("handed to 8 distinct peers", unique.size() == 8)

	var rng_room := RandomNumberGenerator.new()
	rng_room.seed = 5
	check("without a case full of extras, draw(rng, 8) still gives 3 -- the room's own",
			TourParts.draw(rng_room, 8).size() == 3)


## A band bigger than the room's own three instruments is always offered one to spill while it
## still wants more; a solo player, who never needs one, sees one far less often; a kind already
## fully spilled drops out of the draft; and a repeatable card is never hidden by `exclude`.
func _test_tour_deck_offers_instruments_to_a_big_band() -> void:
	var has_spill_boon := func(hand: Array[TourCard]) -> bool:
		for c in hand:
			if String(c.id).begins_with("spill_"):
				return true
		return false

	var always := true
	for seed in range(20):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		if not has_spill_boon.call(TourDeck.draw(rng, [], 8, [])):
			always = false
	check("a band of 8 with nothing spilled yet is always offered an instrument", always)

	# A sample big enough that the per-kind roll's sampling noise (small at 40 seeds, and the
	# actual cause of this check's own repeated near-misses as SPILL_KINDS grew -- a seed sample
	# that close to its own bar is not a tight pass, it is luck) cannot swing the count across a
	# bar set well inside the ~45% the roll in deck.gd's `draw` targets regardless of catalogue
	# size, rather than tightening the bar itself every time a kind is added.
	var seen := 0
	var samples := 2000
	for seed in range(samples):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		if has_spill_boon.call(TourDeck.draw(rng, [], 1, [])):
			seen += 1
	check("a solo player sees one well under half of %d seeds (%d)" % [samples, seen], seen < samples / 2)

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 3
	var spilled: Array[StringName] = [&"cowbell", &"cowbell2"]
	var has_cowbell_boon: bool = has_spill_boon.call(TourDeck.draw(rng2, [], 8, spilled).filter(
			func(c: TourCard) -> bool: return c.id == &"spill_cowbell"))
	check("a cowbell already fully spilled is never offered again", not has_cowbell_boon)

	var excluded: Array[StringName] = [&"spill_cowbell"]
	var still_offered := false
	for seed in range(20):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		for c in TourDeck.draw(rng, excluded, 8, []):
			if c.id == &"spill_cowbell":
				still_offered = true
	check("but excluding a repeatable card never hides it", still_offered)


## `TourChaos.count_for` scales with the band (never on brief 0, whatever the band; 0-1 for a
## duo, 1-2 for a mid band, 2-3 for a big one; the boss adds exactly one more, capped at the
## catalogue's own size), and its schedule respects the gap and the first/last windows -- both
## off the run's own `chaos_rng`, which replays identically for the same `attempt_seed`.
func _test_tour_chaos_schedule_is_seeded_and_scaled() -> void:
	for band in [1, 2, 3, 5, 6, 8]:
		for seed in range(30):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed
			check("band %d, seed %d: count_for(.., 0, false) is always 0 -- never on brief 0" % [band, seed],
					TourChaos.count_for(band, 0, false, rng) == 0)

	for band in [1, 2]:
		for seed in range(30):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed
			var n := TourChaos.count_for(band, 1, false, rng)
			check("band %d, seed %d: a duo sees 0 or 1 (%d)" % [band, seed, n], n == 0 or n == 1)
	for band in [3, 5]:
		for seed in range(30):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed
			var n := TourChaos.count_for(band, 1, false, rng)
			check("band %d, seed %d: a mid band sees 1 or 2 (%d)" % [band, seed, n], n == 1 or n == 2)
	for band in [6, 8]:
		for seed in range(30):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed
			var n := TourChaos.count_for(band, 1, false, rng)
			check("band %d, seed %d: a big band sees 2 or 3 (%d)" % [band, seed, n], n == 2 or n == 3)

	for seed in range(30):
		var rng_a := RandomNumberGenerator.new()
		rng_a.seed = seed
		var rng_b := RandomNumberGenerator.new()
		rng_b.seed = seed
		var plain := TourChaos.count_for(8, 1, false, rng_a)
		var boss := TourChaos.count_for(8, 1, true, rng_b)
		check("the boss adds exactly one more, capped at the catalogue (plain %d, boss %d)" % [plain, boss],
				boss == mini(plain + 1, TourChaos.all().size()))

	var sched := TourChaos.schedule(RandomNumberGenerator.new(), 3, 45.0)
	var sorted := sched.duplicate()
	sorted.sort()
	check("schedule(.., 3, 45.0) comes back sorted ascending (%s)" % [sched], sched == sorted)
	for t in sched:
		check("every strike time sits in [10, 37] (%s)" % [sched], t >= 10.0 and t <= 37.0)
	for i in sched.size():
		for j in range(i + 1, sched.size()):
			check("no two strikes land closer than 8 s apart (%s)" % [sched],
					absf(sched[i] - sched[j]) >= 8.0)

	var a := TourRun.new()
	a.attempt_seed = 4242
	var b := TourRun.new()
	b.attempt_seed = 4242
	var crng_a := a.chaos_rng(2)
	var crng_b := b.chaos_rng(2)
	var n_a := TourChaos.count_for(8, 2, false, crng_a)
	var n_b := TourChaos.count_for(8, 2, false, crng_b)
	check("the same attempt_seed draws the same count for brief 2", n_a == n_b)
	var drawn_a := TourChaos.draw(crng_a, n_a, [])
	var drawn_b := TourChaos.draw(crng_b, n_b, [])
	var ids_a: Array = drawn_a.map(func(e: TourChaosEvent) -> StringName: return e.id)
	var ids_b: Array = drawn_b.map(func(e: TourChaosEvent) -> StringName: return e.id)
	check("and the same events, in the same order", ids_a == ids_b)
	var sched_a := TourChaos.schedule(crng_a, drawn_a.size(), 45.0)
	var sched_b := TourChaos.schedule(crng_b, drawn_b.size(), 45.0)
	check("and the same schedule", sched_a == sched_b)

	var c := TourRun.new()
	c.attempt_seed = 777
	var crng_c := c.chaos_rng(2)
	var n_c := TourChaos.count_for(8, 2, false, crng_c)
	var drawn_c := TourChaos.draw(crng_c, n_c, [])
	var ids_c: Array = drawn_c.map(func(e: TourChaosEvent) -> StringName: return e.id)
	check("a different seed differs somewhere", n_a != n_c or ids_a != ids_c)


## Each of the six, struck and recovered through nothing but DAW verbs (OfflineBackend has no
## `eq` plugin by that catalogue kind to add, which `plugin_haywire` needs -- see
## TourChaosEvent's own doc -- so this uses GodotBackend, the one backend an actual run ever
## plays on anyway): `recovered()` true before, false the instant it strikes, true again once
## the room's own control undoes it, and nothing else's judge moves in between.
func _test_tour_chaos_strikes_and_recovers_through_daw_verbs() -> void:
	var previous := DAW.backend
	var backend := GodotBackend.new()
	DAW.use(backend, false)
	backend.open({})

	var brief := TourBriefs.brief(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	TourProject.load(TourProject.song_for(brief, 100.0, [], rng), backend)

	var run := TourRun.new()
	run.song_tempo = 100.0

	var rhodes := TourProject.BAND.find("Rhodes") + 1
	var gtr := TourProject.BAND.find("Gtr Amp") + 1
	var oh := TourProject.BAND.find("OH") + 1
	var snare := TourProject.BAND.find("Snare") + 1

	var targets := {&"power_flicker": rhodes, &"solo_leaned": gtr, &"stage_unplugged": 0,
			&"crowd_throws": oh, &"plugin_haywire": snare, &"tempo_lurch": 1}
	var others_recovered := func(except_id: StringName) -> bool:
		for id in targets:
			if id != except_id and not TourChaos.by_id(id).recovered(DAW.state, run, targets[id]):
				return false
		return true

	check("every event starts recovered, nothing struck yet", others_recovered.call(&""))

	var power := TourChaos.by_id(&"power_flicker")
	power.strike(run, rhodes)
	check("power_flicker mutes the struck strip", DAW.state.track(rhodes).mute)
	check("and reads unrecovered", not power.recovered(DAW.state, run, rhodes))
	check("nothing else moved", others_recovered.call(&"power_flicker"))
	DAW.set_track_mute(rhodes, false)
	check("the strip's own MUTE recovers it", power.recovered(DAW.state, run, rhodes))

	var solo := TourChaos.by_id(&"solo_leaned")
	solo.strike(run, gtr)
	check("solo_leaned solos the struck strip", DAW.state.track(gtr).solo)
	check("and reads unrecovered", not solo.recovered(DAW.state, run, gtr))
	check("nothing else moved", others_recovered.call(&"solo_leaned"))
	DAW.set_track_solo(gtr, false)
	check("the strip's own SOLO recovers it", solo.recovered(DAW.state, run, gtr))

	var stage := TourChaos.by_id(&"stage_unplugged")
	check("Stage starts armed", DAW.state.track(Tour.STAGE_TRACK).rec_arm)
	stage.strike(run, 0)
	check("stage_unplugged disarms Stage", not DAW.state.track(Tour.STAGE_TRACK).rec_arm)
	check("and reads unrecovered", not stage.recovered(DAW.state, run, 0))
	check("a part really stops landing: armed_track() is 0 (the master)", HitRecorder.armed_track() == 0)
	check("and a take is refused", DAW.midi_take_refusal([0, 0.0, 1.0, [[0.0, 0.1, 60, 100, 0]]]) != "")
	check("nothing else moved", others_recovered.call(&"stage_unplugged"))
	DAW.set_track_rec_arm(Tour.STAGE_TRACK, true)
	check("REC arm recovers it", stage.recovered(DAW.state, run, 0))

	var crowd := TourChaos.by_id(&"crowd_throws")
	crowd.strike(run, oh)
	check("crowd_throws drops the fader to -30 dB", is_equal_approx(DAW.state.track(oh).volume_db, -30.0))
	check("and reads unrecovered", not crowd.recovered(DAW.state, run, oh))
	check("nothing else moved", others_recovered.call(&"crowd_throws"))
	DAW.set_track_volume(oh, DAW.db_to_taper(0.0))
	check("pushing the fader back up recovers it", crowd.recovered(DAW.state, run, oh))

	var haywire := TourChaos.by_id(&"plugin_haywire")
	haywire.strike(run, snare)
	check("plugin_haywire adds the built-in EQ to the struck strip (%s)" % [DAW.state.fx(snare, 0).name],
			DAW.state.track(snare).fx.size() == 1 and DAW.state.fx(snare, 0).name == TourFlaws.EQ_NAME)
	check("and reads unrecovered", not haywire.recovered(DAW.state, run, snare))
	check("nothing else moved", others_recovered.call(&"plugin_haywire"))
	DAW.set_fx_enabled(snare, 0, false)
	check("bypassing it recovers it", haywire.recovered(DAW.state, run, snare))
	DAW.set_fx_enabled(snare, 0, true)
	check("re-enabled, it is unrecovered again", not haywire.recovered(DAW.state, run, snare))
	DAW.remove_fx(snare, 0)
	check("removing it outright also recovers it", haywire.recovered(DAW.state, run, snare))

	var lurch := TourChaos.by_id(&"tempo_lurch")
	lurch.strike(run, 1)
	check("tempo_lurch kicks the tempo by 14 BPM (%.1f)" % DAW.state.tempo, is_equal_approx(DAW.state.tempo, 114.0))
	check("and reads unrecovered", not lurch.recovered(DAW.state, run, 1))
	check("nothing else moved", others_recovered.call(&"tempo_lurch"))
	DAW.set_tempo(100.0)
	check("the tempo knob recovers it", lurch.recovered(DAW.state, run, 1))

	check("every event is recovered again at the end", others_recovered.call(&""))

	DAW.use(previous, false)


## A struck chaos event blocks the pass exactly as an unfixed flaw or an untaken part does, live
## in `Tour._physics_process`, and `TourBrief.judge` refuses one directly the same way.
func _test_tour_chaos_blocks_the_pass_until_recovered() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	Session.start_solo()
	var saved_run := Tour.run
	var brief := TourBriefs.brief(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	TourProject.load(TourProject.song_for(brief, 100.0, [], rng), backend)
	DAW.set_track_volume(TourProject.BAND.find("Lead Vox") + 1, DAW.db_to_taper(0.0))

	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.tuning = false
	run.attempt_seed = 301
	run.brief_index = 0
	run.band_size = 1
	run.song_tempo = 100.0
	run.flaws = [&"quiet_vox"]
	run.fixed = [true]
	run.parts = [&"tamb_backbeat"]
	run.holders = [1]
	run.hits = [0]
	run.played = [false]
	run.open_since = [0.0]
	run.seconds_left = brief.seconds
	run.seconds_total = brief.seconds
	run.events = [&"solo_leaned"]
	run.event_at = [brief.seconds - 5.0]
	run.event_track = [3]
	run.event_state = [TourChaos.State.STRUCK]
	Tour.run = run

	var beat := 60.0 / 100.0
	var hits: Array = []
	for k in 4:
		for b in [1.0, 3.0]:
			var on: float = (k * 4.0 + b) * beat
			hits.append([on, on + 0.05, 54, 104, HitRecorder.CHANNEL])
	DAW.insert_midi_take(Tour.STAGE_TRACK, hits[0][0], hits.back()[1] + 1.0, hits, "Ada percussion 1")

	DAW.set_track_solo(3, true)
	Tour._physics_process(0.1)
	check("the flaw fixes and the part lands, but a struck event keeps the brief going (%s, %s)" \
			% [run.state, run.event_state], run.state == TourRun.State.BRIEF
			and run.event_state == [TourChaos.State.STRUCK] and run.fixed == [true] and run.played == [true])

	DAW.set_track_solo(3, false)
	Tour._physics_process(0.1)
	check("recovering it lets the brief pass (%s, %s)" % [run.event_state, run.state],
			run.event_state == [TourChaos.State.RECOVERED] and run.state == TourRun.State.DRAFTING)

	var verdict := TourBrief.new().judge({"chaos": {"open": 1, "total": 1}})
	check("judge refuses a pass while a chaos event is open, and says so (%s)" % [verdict["detail"]],
			not bool(verdict["passed"]) and String(verdict["detail"][0]).contains("loose"))

	Tour.run = saved_run
	DAW.use(previous, false)


## The host's state machine, PENDING -> TELEGRAPHED -> STRUCK, each exactly once, off the brief's
## own clock -- the strike's DAW verb (a mute) lands only at the one moment, never before.
func _test_tour_chaos_telegraphs_and_strikes_on_the_brief_clock() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	Session.start_solo()
	var saved_run := Tour.run
	var brief := TourBriefs.brief(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	TourProject.load(TourProject.song_for(brief, 100.0, [], rng), backend)

	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.tuning = false
	run.attempt_seed = 401
	run.song_tempo = 100.0
	run.seconds_total = 45.0
	run.events = [&"power_flicker"]
	run.event_at = [12.0]
	run.event_track = [3]
	run.event_state = [TourChaos.State.PENDING]
	Tour.run = run

	# Arrays, not a plain int: a lambda captures a local by value in GDScript, so `+= 1` inside
	# one would only ever change the lambda's own copy. `.append()` on a captured Array mutates
	# the one the outer scope sees too.
	var telegraphed: Array = []
	var struck: Array = []
	var on_telegraph := func(i: int) -> void: telegraphed.append(i)
	var on_struck := func(i: int) -> void: struck.append(i)
	Tour.chaos_telegraphed.connect(on_telegraph)
	Tour.chaos_struck.connect(on_struck)

	run.seconds_left = 35.5
	Tour._physics_process(0.1)
	check("elapsed 9.5 s: still PENDING, nothing fired (%d/%d)" % [telegraphed.size(), struck.size()],
			run.event_state == [TourChaos.State.PENDING] and telegraphed.is_empty() and struck.is_empty())

	run.seconds_left = 34.5
	Tour._physics_process(0.1)
	check("elapsed 10.5 s: telegraphed once, the desk untouched (%d/%d, mute=%s)" \
			% [telegraphed.size(), struck.size(), DAW.state.track(3).mute],
			run.event_state == [TourChaos.State.TELEGRAPHED] and telegraphed.size() == 1 and struck.is_empty()
			and not DAW.state.track(3).mute)

	run.seconds_left = 32.9
	Tour._physics_process(0.1)
	check("elapsed 12.1 s: struck once, the desk mutes (%d/%d)" % [telegraphed.size(), struck.size()],
			run.event_state == [TourChaos.State.STRUCK] and telegraphed.size() == 1 and struck.size() == 1
			and DAW.state.track(3).mute)

	Tour._physics_process(0.1)
	Tour._physics_process(0.1)
	check("settled: two more ticks fire nothing more (%d/%d)" % [telegraphed.size(), struck.size()],
			telegraphed.size() == 1 and struck.size() == 1)

	Tour.chaos_telegraphed.disconnect(on_telegraph)
	Tour.chaos_struck.disconnect(on_struck)
	Tour.run = saved_run
	DAW.use(previous, false)


## `Tour.clock_low` fires once, at CLOCK_LOW_SECONDS left on the host's own clock -- win or lose
## still undecided, the same "presentation only" reasoning as the chaos telegraph.
func _test_tour_clock_low_fires_once_near_the_end_of_the_brief() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	Session.start_solo()
	var saved_run := Tour.run
	var brief := TourBriefs.brief(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	TourProject.load(TourProject.song_for(brief, 100.0, [], rng), backend)

	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.tuning = false
	run.attempt_seed = 701
	run.song_tempo = 100.0
	run.seconds_total = 45.0
	Tour.run = run

	var fired: Array = []
	var on_low := func() -> void: fired.append(true)
	Tour.clock_low.connect(on_low)

	run.seconds_left = 15.5
	Tour._physics_process(0.1)
	check("15.5 s left: not yet (%d)" % fired.size(), fired.is_empty())

	run.seconds_left = 9.9
	Tour._physics_process(0.1)
	check("9.9 s left: clock_low fires once (%d)" % fired.size(), fired.size() == 1)

	run.seconds_left = 3.0
	Tour._physics_process(0.1)
	Tour._physics_process(0.1)
	check("settled: running further down fires nothing more (%d)" % fired.size(), fired.size() == 1)

	Tour.clock_low.disconnect(on_low)
	Tour.run = saved_run
	DAW.use(previous, false)


## A guest plays the telegraph, the strike and the recovery from its OWN clock and `Session.tour`
## alone -- `Tour.run` here is never the live one `_tick_chaos` host-ticks, only the read-only
## copy `_on_tour_changed` rebuilds -- and the HUD's line follows `Tour.chaos_shown`.
func _test_tour_chaos_guest_plays_the_telegraph_from_the_run() -> void:
	_as_session(Session.Role.GUEST, 5)
	var saved_run := Tour.run
	var hud := TourHud.new()
	add_child(hud)

	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.tuning = false
	run.attempt_seed = 501
	run.band_size = 1
	run.song_tempo = 100.0
	run.seconds_total = 45.0
	run.seconds_left = 34.0
	run.events = [&"power_flicker"]
	run.event_at = [12.0]
	run.event_track = [0]
	run.event_state = [TourChaos.State.PENDING]
	Session.tour = run.to_dict()

	var telegraphed: Array = []
	var on_telegraph := func(i: int) -> void: telegraphed.append(i)
	Tour.chaos_telegraphed.connect(on_telegraph)
	Session.tour_changed.emit()
	Tour._physics_process(0.0)
	Tour.chaos_telegraphed.disconnect(on_telegraph)
	check("a guest's own clock telegraphs it (brief_elapsed %.1f)" % Tour.brief_elapsed(),
			telegraphed.size() == 1)

	hud._refresh()
	var line := hud._chaos_box.get_node_or_null("Chaos0") as Label
	check("Chaos0 reads the telegraph, in CURSE (%s)" % (line.text if line else "none"),
			line != null and line.visible and line.text.begins_with("!!  ")
			and line.get_theme_color("font_color") == TourHud.CURSE)

	run.event_state = [TourChaos.State.STRUCK]
	Session.tour = run.to_dict()
	Session.tour_changed.emit()
	hud._refresh_chaos(Tour.run)
	check("struck reads XX, still CURSE (%s)" % line.text,
			line.text.begins_with("XX  ") and line.get_theme_color("font_color") == TourHud.CURSE)

	run.event_state = [TourChaos.State.RECOVERED]
	Session.tour = run.to_dict()
	Session.tour_changed.emit()
	hud._refresh_chaos(Tour.run)
	check("recovered reads OK, in ACCENT (%s)" % line.text,
			line.text.begins_with("OK  ") and line.get_theme_color("font_color") == TourHud.ACCENT)

	Session.tour = {}
	Session.tour_changed.emit()
	hud._refresh()
	check("the run ending hides the hud", not hud._root.visible)

	Tour.run = saved_run
	remove_child(hud)
	hud.free()
	_as_session(Session.Role.SOLO, 1)


## `Tour.flaw_fixed` fires once a flaw, off a guest's own copy of `run.fixed` -- the same
## not-host-only reasoning as `chaos_telegraphed`, but over a plain bool with no clock of its own.
## A fresh brief (even one that reuses a flaw id, or starts already fixed) must not inherit the
## last brief's shown state: the same singleton-leak care `_finish_at` needed.
func _test_tour_flaw_fixed_fires_once_per_flaw_from_the_wire() -> void:
	_as_session(Session.Role.GUEST, 6)
	var saved_run := Tour.run

	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.tuning = false
	run.attempt_seed = 601
	run.brief_index = 0
	run.band_size = 1
	run.song_tempo = 100.0
	run.seconds_total = 45.0
	run.seconds_left = 45.0
	run.flaws = [&"quiet_vox", &"muddy_bass"]
	run.fixed = [false, false]
	Session.tour = run.to_dict()

	var fired: Array = []
	var on_fixed := func(i: int) -> void: fired.append(i)
	Tour.flaw_fixed.connect(on_fixed)

	Session.tour_changed.emit()
	Tour._physics_process(0.0)
	check("nothing fixed yet: no signal (%s)" % [fired], fired.is_empty())

	run.fixed = [true, false]
	Session.tour = run.to_dict()
	Session.tour_changed.emit()
	Tour._physics_process(0.0)
	check("flaw 0 just fixed: fires once (%s)" % [fired], fired == [0])

	Tour._physics_process(0.0)
	Tour._physics_process(0.0)
	check("settled: ticking again fires nothing more (%s)" % [fired], fired == [0])

	run.fixed = [true, true]
	Session.tour = run.to_dict()
	Session.tour_changed.emit()
	Tour._physics_process(0.0)
	check("flaw 1 fixed too: fires for it, not again for 0 (%s)" % [fired], fired == [0, 1])

	# A new brief (a fresh attempt_seed:brief_index key) must not inherit the shown state above --
	# flaw 0, already fixed on arrival, fires fresh rather than being swallowed as "already shown".
	run.brief_index = 1
	run.flaws = [&"quiet_vox"]
	run.fixed = [true]
	Session.tour = run.to_dict()
	Session.tour_changed.emit()
	Tour._physics_process(0.0)
	check("a new brief's already-fixed flaw fires fresh, not swallowed by the old one's shown state (%s)" \
			% [fired], fired == [0, 1, 0])

	Tour.flaw_fixed.disconnect(on_fixed)
	Tour.run = saved_run
	_as_session(Session.Role.SOLO, 1)


## Striking all six, including the haywire EQ and the kicked tempo, leaves nothing behind once
## the run ends: `TourProject.restore` brings back exactly the project that was captured, same
## shape `_test_tour_project_restores_exactly` already proves for the flaws and the parts.
func _test_tour_chaos_leaves_the_real_project_untouched() -> void:
	var previous := DAW.backend
	var backend := GodotBackend.new()
	DAW.use(backend, false)
	backend.open({})
	ProjectBridge.load(ProjectFiles.blank("Studio Song", 3), backend)
	backend.project_path = "user://projects/Studio Song.dawproject"
	backend.name_project()

	var snapshot := TourProject.capture(backend)
	var original: DawKitProject = snapshot["project"]

	var song_rng := RandomNumberGenerator.new()
	song_rng.seed = 7
	TourProject.load(TourProject.song_for(TourBriefs.brief(0), 120.0, [], song_rng), backend)

	var run := TourRun.new()
	run.song_tempo = 120.0
	var rhodes := TourProject.BAND.find("Rhodes") + 1
	var gtr := TourProject.BAND.find("Gtr Amp") + 1
	var oh := TourProject.BAND.find("OH") + 1
	var snare := TourProject.BAND.find("Snare") + 1

	TourChaos.by_id(&"power_flicker").strike(run, rhodes)
	TourChaos.by_id(&"solo_leaned").strike(run, gtr)
	TourChaos.by_id(&"stage_unplugged").strike(run, 0)
	TourChaos.by_id(&"crowd_throws").strike(run, oh)
	TourChaos.by_id(&"plugin_haywire").strike(run, snare)
	TourChaos.by_id(&"tempo_lurch").strike(run, 1)

	check("the rescue desk really changed under all six strikes",
			DAW.state.track(rhodes).mute and DAW.state.track(gtr).solo
			and not DAW.state.track(Tour.STAGE_TRACK).rec_arm and DAW.state.track(oh).volume_db < -20.0
			and DAW.state.track(snare).fx.size() == 1 and not is_equal_approx(DAW.state.tempo, 120.0))

	TourProject.restore(backend, snapshot)
	var restored := ProjectBridge.capture(backend)
	check("the restored project is exactly the one that was captured (%s)" % [original.first_difference(restored)],
			original.same_as(restored))
	check("the project's file path comes back too", backend.project_path == snapshot["path"])
	check("the live desk's tempo is the real project's again, not the chaos-kicked rescue one's",
			is_equal_approx(DAW.state.tempo, original.tempo))
	var names: Array[String] = []
	for i in DAW.state.track_indices():
		names.append(DAW.state.tracks[i].name)
	check("and the chaos-marked Stage lane is gone with the rest of the rescue song's tracks (%s)" % [names],
			DAW.state.track_indices().size() == 3 and not ("Stage" in names))

	DAW.use(previous, false)


## `to_dict`/`from_dict` carries every chaos field index for index and pads a short one;
## `draw` never pairs `tempo_lurch` with the flaw it excludes; `pick_track` never hands out
## Stage, Keys, a name it was told to skip, or a muted strip.
func _test_tour_chaos_round_trips_and_never_draws_a_conflict() -> void:
	var run := TourRun.new()
	run.seconds_total = 45.0
	run.events = [&"power_flicker", &"crowd_throws"]
	run.event_at = [12.0, 30.0]
	run.event_track = [3, 7]
	run.event_state = [TourChaos.State.TELEGRAPHED, TourChaos.State.STRUCK]
	var back := TourRun.from_dict(run.to_dict())
	check("seconds_total rides the wire", is_equal_approx(back.seconds_total, run.seconds_total))
	check("events ride the wire, in order", back.events == run.events)
	check("event_at, index for index", back.event_at == run.event_at)
	check("event_track, index for index", back.event_track == run.event_track)
	check("event_state, index for index", back.event_state == run.event_state)

	var short := {"events": ["power_flicker", "crowd_throws"], "event_at": [12.0],
			"event_track": [], "event_state": [int(TourChaos.State.TELEGRAPHED)]}
	var padded := TourRun.from_dict(short)
	check("a short event_at is padded with INF (%s)" % [padded.event_at],
			padded.event_at.size() == 2 and is_inf(padded.event_at[1]))
	check("a short event_track is padded with 0 (%s)" % [padded.event_track], padded.event_track == [0, 0])
	check("a short event_state is padded PENDING (%s)" % [padded.event_state],
			padded.event_state == [TourChaos.State.TELEGRAPHED, TourChaos.State.PENDING])

	for seed in range(50):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var drawn := TourChaos.draw(rng, 6, [&"wrong_tempo"])
		var ids: Array = drawn.map(func(e: TourChaosEvent) -> StringName: return e.id)
		check("seed %d never draws tempo_lurch alongside wrong_tempo" % seed, not (&"tempo_lurch" in ids))

	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	var song_rng := RandomNumberGenerator.new()
	song_rng.seed = 2
	TourProject.load(TourProject.song_for(TourBriefs.brief(0), 100.0, [], song_rng), backend)
	DAW.set_track_mute(TourProject.BAND.find("Kick") + 1, true)
	for seed in range(50):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var picked := TourChaos.pick_track(rng, DAW.state, ["Rhodes"])
		var t := DAW.state.track(picked, false)
		check("seed %d pick_track never returns Stage, Keys, Rhodes or a muted track (%d, %s)" \
				% [seed, picked, t.name if t != null else "none"],
				picked != Tour.STAGE_TRACK and picked != Tour.TIMING_TRACK and t != null
				and t.name != "Rhodes" and not t.mute)
	DAW.use(previous, false)


class _FakeEar extends TourMeasure.Ear:
	var avg_db := -100.0
	var spread_db := 0.0
	var tilt_db := 0.0

	func ready() -> bool:
		return true

	func result() -> Dictionary:
		return {"heard": true, "avg_db": avg_db, "low_db": 0.0, "mid_db": 0.0, "high_db": 0.0,
				"spread_db": spread_db, "tilt_db": tilt_db}


## Off `GodotBackend` (the suite's stand-in), `Ear` has nothing to read: it adds no analyzer,
## never fills its window, and `stop()` -- even called twice -- touches no bus.
func _test_tour_ear_reads_inert_off_the_stand_in() -> void:
	var previous := DAW.backend
	DAW.use(OfflineBackend.new(), false)
	var before: Array[int] = []
	for b in AudioServer.bus_count:
		before.append(AudioServer.get_bus_effect_count(b))

	var ear := TourMeasure.Ear.new()
	ear.start()
	for _i in 30:
		ear.sample(0.1)
	check("never fills a window off the stand-in", not ear.ready())
	var r := ear.result()
	check("not heard", r["heard"] == false)
	check("every value reads -100 while not heard (%s)" % [r],
			r["avg_db"] == -100.0 and r["low_db"] == -100.0 and r["mid_db"] == -100.0
			and r["high_db"] == -100.0 and r["spread_db"] == -100.0 and r["tilt_db"] == -100.0)
	ear.stop()
	ear.stop()

	var after: Array[int] = []
	for b in AudioServer.bus_count:
		after.append(AudioServer.get_bus_effect_count(b))
	check("no bus gained or lost an effect (%s -> %s)" % [before, after], before == after)
	DAW.use(previous, false)


## Pins `TourEar`'s arithmetic to the table it was measured against: a hair under `quiet_db`
## reads under, right at it reads happy, hysteresis holds an unhappy reading unhappy until it
## clears the margin, the balance bar's one-sided spread check picks its message off `tilt_db`,
## the boss window is strictly tighter than the regular one, and every clean row this file's
## `THRESHOLDS` comment quotes still reads happy on both -- so a table edited without rerunning
## the tool fails here first.
func _test_tour_ear_judges_from_its_table() -> void:
	var w := TourEar.window(false)
	var hyst: float = TourEar.THRESHOLDS["hyst_db"]
	check("a hair under quiet_db reads under",
			TourEar.judge_level(float(w["quiet_db"]) - 0.01, false, true) == -1)
	check("right at quiet_db reads happy",
			TourEar.judge_level(float(w["quiet_db"]), false, true) == 0)
	check("already unhappy, a bit over quiet_db still reads under (hysteresis)",
			TourEar.judge_level(float(w["quiet_db"]) + 0.5, false, false) == -1)
	check("past the hysteresis margin it reads happy again",
			TourEar.judge_level(float(w["quiet_db"]) + hyst, false, false) == 0)
	check("over spread_max with a non-negative tilt reads mud",
			TourEar.judge_balance(float(w["spread_max_db"]) + 0.01, 1.0, false, true) == 1)
	check("over spread_max with a negative tilt reads thin",
			TourEar.judge_balance(float(w["spread_max_db"]) + 0.01, -1.0, false, true) == -1)
	check("right at spread_max is still happy",
			TourEar.judge_balance(float(w["spread_max_db"]), 1.0, false, true) == 0)

	var boss := TourEar.window(true)
	check("the boss window sits strictly inside the regular one (%s vs %s)" % [boss, w],
			float(boss["quiet_db"]) > float(w["quiet_db"]) and float(boss["loud_db"]) < float(w["loud_db"])
			and float(boss["spread_max_db"]) < float(w["spread_max_db"]))

	for row in TourEar.MEASURED_CLEAN:
		var level := TourEar.judge_level(float(row["avg_db"]), false, true)
		var bal := TourEar.judge_balance(float(row["spread_db"]), float(row["tilt_db"]), false, true)
		check("clean @ %.0f still reads happy,clear under the regular window" % float(row["tempo"]),
				level == 0 and bal == 0)
		var boss_level := TourEar.judge_level(float(row["avg_db"]), true, true)
		var boss_bal := TourEar.judge_balance(float(row["spread_db"]), float(row["tilt_db"]), true, true)
		check("and under the boss window too (@ %.0f)" % float(row["tempo"]),
				boss_level == 0 and boss_bal == 0)

	var muddy := TourEar.MEASURED_MUDDY_BASS
	check("muddy_bass still reads mud on balance",
			TourEar.judge_balance(float(muddy["spread_db"]), float(muddy["tilt_db"]), false, true) > 0)


## The crowd's own block in `TourBrief.judge`: both bars happy is a pass, one of two unhappy
## fails it, and a crowd that never heard a full window (`total == 0`) gates nothing at all.
func _test_tour_brief_judges_the_crowd() -> void:
	var brief := TourBrief.new()
	var base := {"flaws": {"fixed": 1, "total": 1, "seconds_left_frac": 0.5},
			"parts": {"played": 1, "total": 1}}

	var partial := base.duplicate(true)
	partial["crowd"] = {"happy": 1, "total": 2, "seconds_left_frac": 0.5}
	check("one of two crowd bars unhappy fails the brief", not bool(brief.judge(partial)["passed"]))

	var full := base.duplicate(true)
	full["crowd"] = {"happy": 2, "total": 2, "seconds_left_frac": 0.5}
	check("both happy passes", bool(brief.judge(full)["passed"]))

	var never_heard := base.duplicate(true)
	never_heard["crowd"] = {"happy": 0, "total": 0, "seconds_left_frac": 0.5}
	check("the crowd never heard is no gate -- still a pass",
			bool(brief.judge(never_heard)["passed"]))


## `Tour._tick_crowd` end to end: the brief-tick test's own setup (OfflineBackend, a solo
## session, the rescue song loaded, the vocal fixed, a tambourine take already placed so flaws
## and parts are both done from the first tick), but with `Tour._ear` a deterministic
## `_FakeEar` standing in for the real master bus. Unhappy on the level bar alone holds the
## brief in BRIEF with the clock still running; once the crowd is happy on both, the same tick
## that would otherwise finish the brief does, straight into the draft, and `_ear` is let go.
func _test_tour_brief_waits_for_the_crowd() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	Session.start_solo()
	var saved_run := Tour.run
	var saved_ear := Tour._ear
	var brief := TourBriefs.brief(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	TourProject.load(TourProject.song_for(brief, 100.0, [], rng), backend)
	DAW.set_track_volume(TourProject.BAND.find("Lead Vox") + 1, DAW.db_to_taper(0.0))

	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.tuning = false
	run.brief_index = 0
	run.band_size = 1
	run.song_tempo = 100.0
	run.flaws = [&"quiet_vox"]
	run.fixed = [false]
	run.parts = [&"tamb_backbeat"]
	run.holders = [1]
	run.hits = [0]
	run.played = [false]
	run.open_since = [0.0]
	run.seconds_left = brief.seconds
	Tour.run = run

	var beat := 60.0 / 100.0
	var hits: Array = []
	for k in 4:
		for b in [1.0, 3.0]:
			var on: float = (k * 4.0 + b) * beat
			hits.append([on, on + 0.05, 54, 104, HitRecorder.CHANNEL])
	DAW.insert_midi_take(Tour.STAGE_TRACK, hits[0][0], hits.back()[1] + 1.0, hits, "Ada percussion 1")

	var fake := _FakeEar.new()
	fake.avg_db = float(TourEar.window(false)["quiet_db"]) - 5.0
	fake.spread_db = 1.0
	fake.tilt_db = 0.0
	Tour._ear = fake

	Tour._physics_process(0.1)
	check("the flaw and part read fixed/played off the desk regardless of the crowd",
			run.fixed == [true] and run.played == [true])
	check("but the crowd is unhappy with the level, so the brief runs on (%s, %s)" % [run.crowd_happy, run.crowd_over],
			run.crowd_happy == [false, true] and run.crowd_over == [false, false]
			and run.state == TourRun.State.BRIEF and run.seconds_left < brief.seconds)

	fake.avg_db = (float(TourEar.window(false)["quiet_db"]) + float(TourEar.window(false)["loud_db"])) * 0.5
	Tour._physics_process(0.1)
	check("once the crowd is happy on both bars the brief passes into the draft, and the ear is let go",
			run.state == TourRun.State.DRAFTING and Tour._ear == null)

	Tour.run = saved_run
	Tour._ear = saved_ear
	DAW.use(previous, false)


## A brief that qualifies to end -- every flaw fixed, nothing else outstanding -- does not cut
## the song off wherever the qualifying tick happens to land: it holds until the song's own next
## bar (`MixState.next_bar_start`, off the live `DAW.state.position_seconds`), same as a take
## roll already waits for one (`take_roll_seconds`), just the other end of a brief instead.
func _test_tour_brief_finishes_on_the_bar_not_the_frame() -> void:
	var previous := DAW.backend
	var backend := OfflineBackend.new()
	DAW.use(backend, false)
	backend.open({})
	Session.start_solo()
	var saved_run := Tour.run
	var brief := TourBriefs.brief(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	TourProject.load(TourProject.song_for(brief, 120.0, [], rng), backend)
	DAW.set_track_volume(TourProject.BAND.find("Lead Vox") + 1, DAW.db_to_taper(0.0))

	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.tuning = false
	run.brief_index = 0
	run.band_size = 1
	run.song_tempo = 120.0
	run.flaws = [&"quiet_vox"]
	run.fixed = [false]
	run.parts = [&"tamb_backbeat"]
	run.holders = [1]
	run.hits = [0]
	run.played = [false]
	run.open_since = [0.0]
	run.seconds_left = brief.seconds
	Tour.run = run

	var beat := 60.0 / 120.0
	var hits: Array = []
	for k in 4:
		for b in [1.0, 3.0]:
			var on: float = (k * 4.0 + b) * beat
			hits.append([on, on + 0.05, 54, 104, HitRecorder.CHANNEL])
	DAW.insert_midi_take(Tour.STAGE_TRACK, hits[0][0], hits.back()[1] + 1.0, hits, "Ada percussion 1")

	# 120 BPM, 4/4: a bar is 2.0 s. Qualifying a touch past bar 5 (10.0 s) must not finish the
	# brief until the song reaches bar 6 (12.0 s).
	DAW.state.position_seconds = 10.3
	Tour._physics_process(0.1)
	check("the flaw reads fixed and the part played off the desk at once",
			run.fixed == [true] and run.played == [true])
	check("but qualifying mid-bar does not finish the brief yet (%s)" % [run.state],
			run.state == TourRun.State.BRIEF)

	DAW.state.position_seconds = 11.5
	Tour._physics_process(0.1)
	check("still short of the bar, still waiting", run.state == TourRun.State.BRIEF)

	DAW.state.position_seconds = 12.0
	Tour._physics_process(0.1)
	check("the song reaches the bar it qualified on: the brief ends there, into the draft",
			run.state == TourRun.State.DRAFTING)

	Tour.run = saved_run
	DAW.use(previous, false)


## `crowd_happy`/`crowd_over` ride `TourRun.to_dict`/`from_dict` like every other per-bar array,
## and a guest handed mismatched lengths (a stale write caught mid-flight) pads both to the
## longer of the two rather than throwing or silently dropping an entry.
func _test_tour_run_round_trips_the_crowd() -> void:
	var run := TourRun.new()
	run.crowd_happy = [true, false]
	run.crowd_over = [false, true]
	var back := TourRun.from_dict(run.to_dict())
	check("crowd_happy rides the wire", back.crowd_happy == run.crowd_happy)
	check("and crowd_over", back.crowd_over == run.crowd_over)

	var mismatched := {"crowd_happy": [true], "crowd_over": [false, true]}
	var back2 := TourRun.from_dict(mismatched)
	check("a shorter crowd_happy is padded to match (%s)" % [back2.crowd_happy],
			back2.crowd_happy.size() == 2 and back2.crowd_happy[0] == true and back2.crowd_happy[1] == false)
	check("and crowd_over is unaffected", back2.crowd_over == [false, true])


## The HUD's two crowd lines: DIM "listening..." while `run.crowd_happy` is still empty (the ear
## has not heard a full window), then INK/ACCENT with the right words once it has, and the
## one-line tag carries a CROWD OK/-- once heard too.
func _test_tour_hud_shows_the_crowd_lines() -> void:
	var saved_run := Tour.run
	_as_session(Session.Role.HOST, 1)
	var hud := TourHud.new()
	add_child(hud)
	var run := TourRun.new()
	run.state = TourRun.State.BRIEF
	run.band_size = 1
	run.song_tempo = 100.0
	run.flaws = [&"quiet_vox"]
	run.fixed = [false]
	Tour.run = run
	hud._refresh()

	var level_l := hud._crowd_box.get_node_or_null("Crowd0") as Label
	var bal_l := hud._crowd_box.get_node_or_null("Crowd1") as Label
	check("two crowd lines", hud._crowd_box.get_child_count() == 2)
	check("empty crowd_happy reads listening on both, DIM (%s / %s)" %
			[level_l.text if level_l else "none", bal_l.text if bal_l else "none"],
			level_l != null and level_l.text.ends_with("listening...")
			and level_l.get_theme_color("font_color") == TourHud.DIM
			and bal_l != null and bal_l.text.ends_with("listening...")
			and bal_l.get_theme_color("font_color") == TourHud.DIM)

	run.crowd_happy = [false, true]
	run.crowd_over = [false, false]
	hud._refresh_flaws(run)
	hud._refresh_crowd(run)
	check("level unhappy reads too quiet, in INK (%s)" % level_l.text,
			level_l.text.contains("too quiet") and level_l.get_theme_color("font_color") == TourHud.INK)
	check("balance happy reads clear, in ACCENT (%s)" % bal_l.text,
			bal_l.text.contains("clear") and bal_l.get_theme_color("font_color") == TourHud.ACCENT)
	check("the tag ends CROWD -- (%s)" % hud._tag.text, hud._tag.text.ends_with("CROWD --"))

	run.crowd_happy = [true, false]
	run.crowd_over = [false, true]
	hud._refresh_flaws(run)
	hud._refresh_crowd(run)
	check("balance unhappy and over reads mudslide (%s)" % bal_l.text, bal_l.text.contains("mudslide"))
	check("and now the tag ends CROWD -- too, since one bar still isn't happy (%s)" % hud._tag.text,
			hud._tag.text.ends_with("CROWD --"))

	Tour.run = saved_run
	remove_child(hud)
	hud.free()
	Session.start_solo()


func _test_the_tape_decks_keys_are_big_enough_to_aim_at() -> void:
	# 2026-10-13: the deck's keys were 1.4x/1.6x of a 16 mm part, small at the seat.
	_offline()
	var deck := TapeDeck.new()
	add_child(deck)
	deck._process(0.0)
	var tap: PanelButton = deck.find_child("TapKey", true, false)
	check("the deck's tap key is drawn at %.2fx" % TapeDeck.KEY_SCALE,
			tap != null and is_equal_approx(tap.scale.x, TapeDeck.KEY_SCALE) and TapeDeck.KEY_SCALE >= 1.6)
	check("the transport keys are the bigger set", TapeDeck.BIG_KEY_SCALE > TapeDeck.KEY_SCALE)
	deck.queue_free()


func _test_a_simulated_headset_builds_the_vr_and_ar_rigs() -> void:
	# --xr-sim: no runtime and no headset, the rig and the medium are still the headset's.
	var vr := XRBootstrap.new()
	add_child(vr)
	check("--xr-sim without --ar is a VR participant", vr.start(true, false, true) == Presentation.Medium.VR and vr.simulated)
	var ar := XRBootstrap.new()
	add_child(ar)
	check("--xr-sim with --ar is a passthrough participant", ar.start(true, true, true) == Presentation.Medium.AR)
	var screen := XRBootstrap.new()
	add_child(screen)
	check("--xr-sim without --xr is still a screen participant", screen.start(false, false, true) == Presentation.Medium.SCREEN and not screen.simulated)
	var rig := XRRig.new()
	rig.simulated = true
	add_child(rig)
	check("a simulated rig starts at a standing person's head and hands",
			is_equal_approx(rig.head.position.y, XRRig.SIM_EYE_HEIGHT) and rig.left.position.x < 0.0 and rig.right.position.x > 0.0)
	for n in [vr, ar, screen, rig]:
		n.queue_free()
