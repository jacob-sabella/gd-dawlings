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
	check("guest got some tracks at all", guest.state.tracks.size() == 12)

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
	check("on a monitor the room is drawn", _count_meshes(desk) > 0)

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
	func aim() -> Transform3D:
		return pose


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

	check("the stand-in arrangement is not empty", DAW.state.track(1).items.size() > 0)
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
	var parts := {
		Knob.MESH_PATH: Vector2(0.0235, 0.0235),
		Fader.MESH_PATH: Vector2(0.0150, 0.0225),
	}
	for path in parts:
		var mesh := Part.mesh(path)
		check("%s resolves" % path.get_file(), mesh != null)
		if mesh == null:
			continue
		check("%s is the two-material part, not a primitive" % path.get_file(),
				mesh.get_surface_count() == 2)

		var named := 0
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m != null and String(m.resource_name).containsn("indicator"):
				named += 1
		check("%s names exactly one surface the indicator" % path.get_file(), named == 1)

		# The envelope every panel laid itself out around, before any of this was a mesh.
		var size: Vector2 = parts[path]
		var box := mesh.get_aabb()
		check("%s still fits its footprint" % path.get_file(),
				box.size.x < size.x and box.size.y < size.y)

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

	var knob := Knob.new()
	add_child(knob)
	knob.value = 1.0
	knob._on_value_changed()
	var spindle := knob.get_child(0) as Node3D
	# The indicator is moulded into the part, so the part itself is the only thing that can
	# move: at value 1.0 the whole knob has turned half a sweep past centre.
	close_to("turning the value turns the whole part", spindle.rotation.z, -0.5 * Knob.SWEEP)
	knob.queue_free()
