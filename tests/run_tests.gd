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
	_test_room_anchor_two_point()
	_test_room_anchor_ignores_height_difference()
	_test_room_anchor_rejects_close_marks()
	_test_layout_defaults()

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

func _fresh_link() -> Node:
	var link = load("res://core/reaper/reaper_link.gd").new()
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
	link.mode = 1  # HOST, so write() takes the OSC path and arms the guard.
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
		close_to("taper round-trips %.0fdB" % db, ReaperState.taper_to_db(ReaperState.db_to_taper(db)), db, 0.001)
	check("silence is -inf", ReaperState.taper_to_db(0.0) == -INF)


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
