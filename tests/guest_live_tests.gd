extends RefCounted

## What a guest sees of the host's music while it plays: the host's meters and clock instead of a stand-in's, the
## modular room's step lights, module meters, scopes and glow (`RackLive`), and the lights that follow them. Called
## from the `_test_*` wrappers in tests/run_tests.gd.

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func the_rack_state_survives_the_wire_and_bad_input_is_ignored() -> void:
	var scope := PackedFloat32Array([0.0, 0.5, -1.0, 1.0])
	var args := RackLive.pack(0.6, 0.25, {"out": 0.5, "pl": 1.0}, {"seq": 7}, {"scope": scope}, true)
	var heard: Array = bytes_to_var(var_to_bytes([[RackLive.ADDRESS, args]]))[0][1]
	var got := RackLive.unpack(heard, {})
	check("level and hit arrive", is_equal_approx(got["level"], 0.6) and is_equal_approx(got["hit"], 0.25))
	check("a meter is within a byte's step of what was sent", absf(got["meters"]["out"] - 0.5) < 0.005 and is_equal_approx(got["meters"]["pl"], 1.0))
	check("the sequencer's step arrives", got["steps"] == {"seq": 7})
	var wave: PackedFloat32Array = got["scopes"]["scope"]
	check("a scope keeps its length and its extremes", wave.size() == 4 and is_equal_approx(wave[2], -1.0) and is_equal_approx(wave[3], 1.0) and absf(wave[1] - 0.5) < 0.01)
	var lean := RackLive.unpack(RackLive.pack(0.1, 0.0, {}, {"seq": 8}, {"scope": scope}, false), got)
	check("a tick without scopes keeps the ones the guest has, and moves the step", lean["scopes"] == got["scopes"] and lean["steps"]["seq"] == 8)
	check("a rack that stopped blanks the guest's", RackLive.unpack([false], got).is_empty())
	check("nonsense leaves what was there", RackLive.unpack(["x", 1], got) == got and RackLive.unpack([true, true, 0.0, 0.0, PackedStringArray(["a"]), PackedByteArray(), PackedStringArray(),
			PackedInt32Array(), PackedStringArray(), []], got) == got)
	check("an old reading is not live, a fresh one is", RackLive.fresh({"at": Time.get_ticks_msec() - 5000}).is_empty() and not RackLive.fresh(got).is_empty())
	var backend := OfflineBackend.new()
	t.add_child(backend)
	check("the entry travels volatile, unreliable like a meter", backend.is_volatile(RackLive.ADDRESS))
	MixWire.apply_replicated(backend.state, [[RackLive.ADDRESS, heard]])
	check("and lands in the project state", backend.state.rack_live["steps"] == {"seq": 7})
	backend.queue_free()


func a_guest_keeps_the_hosts_meters_and_the_stand_in_still_makes_its_own_solo() -> void:
	var guest := OfflineBackend.new()
	guest.is_authority = false
	t.add_child(guest)
	guest.state.playing = true
	MixWire.apply_replicated(guest.state, [["/master/vu/L", [0.81]], ["/master/vu/R", [0.62]], ["/track/1/vu/L", [0.7]]])
	for i in 5:
		guest._drive_meters(1.0 / 60.0)
	t.close_to("a guest's master meter stays the host's across frames (L)", guest.state.master.vu_l, 0.81)
	t.close_to("(R)", guest.state.master.vu_r, 0.62)
	t.close_to("a track's meter too", guest.state.tracks[1].vu_l, 0.7)
	var before := guest.state.position_seconds
	guest._drive_meters(0.5)
	check("its clock still runs on between the host's updates", guest.state.position_seconds > before + 0.4)
	var solo := OfflineBackend.new()
	t.add_child(solo)
	solo.state.playing = true
	solo.state.master.volume = 0.8
	MixWire.apply_replicated(solo.state, [["/track/1/volume", [0.8]]])
	solo._drive_meters(0.1)
	check("solo and the host still get the stand-in's meters, unchanged", solo.state.master.vu_l > 0.0 and solo.is_authority)
	guest.queue_free()
	solo.queue_free()


func the_host_sends_the_rack_and_a_guest_shows_its_steps_meters_and_light() -> void:
	var role := Session.role
	DAW.use(OfflineBackend.new(), false)
	RackAutosave.disabled = true
	var host := Studio.new()
	host.medium = Presentation.Medium.SCREEN
	t.add_child(host)
	await t.get_tree().physics_frame
	var raw := RackPatch.preset(&"keys_voice")
	raw["modules"]["seq"] = {"type": "builtin.seq", "at": [1, 0], "w": 2, "knobs": {}}
	var state: Dictionary = host.room_rows.room_state().duplicate(true)
	state[RackPatch.ROW]["patch"] = raw
	host.room_rows.apply_room(state)
	# The host's voice with something playing in it (no engine needed: the fields the engine fills).
	host.rack_voice.steps = {"seq": 5}
	host.rack_voice.meters = {"out": 0.75}
	host.rack_voice.level = 0.7
	host.rack_voice.hit = 0.5
	Session.participants[776] = Session.Participant.new()
	Session.participants[777] = Session.Participant.new()
	host.rack_host._publish_live_rack(true)
	var sent: Array = DAW.backend._repl_volatile.get(RackLive.ADDRESS, [])
	check("the host records the rack's state for the guests as a volatile entry", not sent.is_empty() and not DAW.backend._repl_durable.has(RackLive.ADDRESS))
	host.rack_host._publish_live_rack(false)
	check("and says so once when the rack stops", DAW.backend._repl_volatile[RackLive.ADDRESS] == [false])
	DAW.backend._repl_volatile.clear()
	Session.participants.erase(776)
	Session.participants.erase(777)
	host.rack_host._publish_live_rack(true)
	check("with nobody to send to it records nothing", DAW.backend._repl_volatile.is_empty())
	t.close_to("the host reads no rack level while its engine is not running", host.rack_host.rack_level(), 0.0)
	host.queue_free()
	# The guest: the same room, the entry as it came over.
	Session.start_solo()
	Session.role = Session.Role.GUEST
	Session.local_peer_id = 5
	var guest := Studio.new()
	guest.medium = Presentation.Medium.SCREEN
	t.add_child(guest)
	await t.get_tree().physics_frame
	guest.room_rows.apply_room(state)
	check("a guest shows nothing before it hears the host", guest.rack_host.live_rack().is_empty() and guest.rack_host.rack_level() == 0.0)
	MixWire.apply_replicated(DAW.state, [[RackLive.ADDRESS, bytes_to_var(var_to_bytes([sent]))[0]]])
	guest.rack_host._follow_modular()
	var bars: RackBars = guest.rack_wall._pads["seq"]["node"]
	check("the guest's sequencer lights the step the host's is on", bars.playhead == 5)
	t.close_to("the guest's room hears the host's rack as a level", guest.rack_host.rack_level(), 0.7)
	DAW.state.master.vu_l = 0.0
	DAW.state.master.vu_r = 0.0
	for i in 30:
		guest.venue.pulse(maxf(0.0, guest.rack_host.rack_level()))
	check("so the venue's lights have something to follow with the mix silent", guest.venue.heard > 0.1)
	MixWire.apply_replicated(DAW.state, [[RackLive.ADDRESS, [false]]])
	guest.rack_host._follow_modular()
	check("when the host's rack stops the guest's steps go dark", bars.playhead == -1)
	guest.queue_free()
	Session.role = role
	DAW.use(OfflineBackend.new(), false)
	await t.get_tree().process_frame
