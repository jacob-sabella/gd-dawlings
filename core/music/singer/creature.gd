class_name Creature
extends RackVoice

## The venue's creature, sounding: a rack of its own with one VOICE module set to BEAST (CHIMERA's animals,
## native/rack/modules_voice.cc) into OUT, run on the host while someone is at its perch (CreaturePerch). A stone
## struck is one call at its note (`call`), told to the module as words, so no keys are shared with the singer's
## own rack. It plays out of the room's speakers (track 0, RackVoice's direct path, on the bus a host's guests are
## sent: see `start`), not onto a track.

const ID := "c"

var _beast := -1


func _init() -> void:
	patch = RackPatch.sanitize({"modules": {ID: {"type": "builtin.voice", "at": [0, 0]}, "o": {"type": RackPatch.OUT_MODULE, "at": [6, 0]}},
			"cables": [[ID + ".out", "o.l"], [ID + ".out", "o.r"]]})


func start() -> bool:
	# The room's sound, not a monitor, and where a host's guests are sent it from: the built-in DAW's master bus
	# (GodotBackend's BusSource captures there, before the Mix), else the Mix itself.
	direct_bus = StringName(GodotBackend.MASTER_BUS) if AudioServer.get_bus_index(GodotBackend.MASTER_BUS) >= 0 \
			else AudioPorts.MIX
	set_patch(patch)
	if not super.start():
		return false
	knob(ID, "mode", Singer.position("mode", SingerRow.Mode.BEAST))
	var b := _beast
	_beast = -1
	if b >= 0:
		be(b)
	return true


## Become creature `beast` (an index into SingerRow.BEASTS).
func be(beast: int) -> void:
	if beast == _beast:
		return
	_beast = beast
	knob(ID, "beast", Singer.position("beast", beast))


## Call `index` at MIDI note `midi`.
func call_at(index: int, midi: int) -> void:
	engine.say("text %s.call %d %d" % [ID, index, midi])
