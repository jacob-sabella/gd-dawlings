class_name RackWall
extends Surface

## The modular room's rack (docs/architecture.md, "The modular room"): the case over the synth zone's
## keyboard stand, a skiff of ROWS rows by COLS columns that holds any of the engine's modules
## (RackCatalogue) in any place, patched with cables. Under the modules a palette: a row of groups, a
## row of what is in the group, and a press on one puts it in the next free place.
##
## It shows the room's patch (`show_patch`) and never changes it: a cable, a module put in or taken out,
## a knob let go are asks (`edit_asked`, `knob_set`) the studio puts to the room, whose answer comes back
## through `show_patch`. A knob turning is streamed to the band (`knob_streamed`) at most
## Session.KNOBS_PER_SECOND, and the room's only when it has rested for SETTLE.
##
## It lights up with what it plays: each module's lamp follows its meter (`show_meters`), and the case
## glows in the venue's mood (`mood`, RackMood) brighter with the rack's loudness and flashing on a hit,
## which the studio also gives to the room's own lights.
##
## Hardware: it knows nothing of the session.

## A change to the patch is asked for: `op` and `args` as `RackPatch.answer` takes them.
signal edit_asked(op: String, args: Array)
## The help card of module `id` was asked for (a click on its name).
signal help_asked(id: String)
## The module finder is asked for, with this palette group chosen ("" for all).
signal find_asked(group: String)
## A knob is being turned: module id, knob and value 0..1, on every change.
signal knob_turning(id: String, knob: String, v: float)
## A knob being turned, at a limited rate, to be sent on as a live ask.
signal knob_streamed(id: String, knob: String, v: float)
## A knob was let go at its final value.
signal knob_set(id: String, knob: String, v: float)
## A touch key was pressed (`down`) or released at MIDI `pitch`.
signal touched(pitch: int, down: bool)
## The PLAY key was pressed: play the rack from the computer keys.
signal keys_asked()
## The wall has something to say to the player.
signal told(text: String)
## The TRACK key was pressed: the player asks to move the rack's sound to a track.
signal track_asked()
## The REC key was pressed.
signal record_asked()

const COLS := RackLayout.COLS
const ROWS := RackLayout.ROWS
const MODULE_WIDE := 0.11
const WIDE := MODULE_WIDE * COLS
const ROW_TALL := 0.55
const ROW_GAP := 0.02
const PALETTE_TALL := 0.15
const TALL := ROW_TALL * ROWS + ROW_GAP * (ROWS - 1) + PALETTE_TALL
const BORDER := 0.025
## The floor, below the case's foot (Venue.MODULAR_BOTTOM).
const MODULAR_FLOOR := 1.26
const CASE_DEEP := 0.05
const KNOB_PITCH := 0.055
const KNOB_ROW := 0.062
const JACK_ROW := 0.06
const TITLE_CAP := 0.032
const LETTER_CAP := 0.018
const TOUCH_COUNT := 13
const TOUCH_SIZE := Vector2(0.078, 0.17)
const TOUCH_X := 0.08
const TOUCH_Y := 1.0325 - 1.26
const TOUCH_Z := 0.14
const PLAQUE_WIDE := 0.42
const PLAQUE_GAP := 0.03
const PLAQUE_X := WIDE * 0.5 + BORDER + PLAQUE_GAP + PLAQUE_WIDE * 0.5
const PLAQUE_Z := 0.01
const POST := 0.04
const LOOK := Vector3(0, 0.3, 0.1)
const FRAME_TOP := Vector3(0, TALL + BORDER, 0)
const FRAME_FOOT := Vector3(0, TOUCH_Y, TOUCH_Z + TOUCH_SIZE.y * 0.5)
const SETTLE := 0.3
const STREAM_GAP_MSEC := 34
const CABLE_SAG := 0.16
const GROUP_PRESETS := "PRESETS"


var within_reach := true:
	set(v):
		if within_reach == v:
			return
		within_reach = v
		_apply_reach()
var clock: Callable = func() -> int: return Time.get_ticks_msec()

var patch := RackPatch.empty()
## {"id.port": RackJack}, {"id.knob": Knob}, {module id: Node3D}
var jacks := {}
var knobs := {}
var module_nodes := {}
var touch_keys: Array[ModularTouch] = []
var play_key: EqWall.WallKey
var cables: Array[PatchCable] = []
## The stubs of cables with only one plug here (RackStubs): dangling cables and those to absent modules.
var _stubs := RackStubs.new()
var touch_base := 48
var panel: Node3D
## The group the palette shows.
var group := "Source"
## The venue's mood, RackMood.palette: {base, hit, glow}.
var mood := RackMood.palette(&"")
var _built := false
var _shape_key := ""
## What is built on the wall, {module id: [type, column, row]}, and the blank plates' paint.
var _on_wall := {}
var _blank_paint: StandardMaterial3D
var _lamps := {}
## The screens of the SCOPE modules, by module id.
var _scopes := {}
var _track := 0
var _track_name := ""
var _recording := false
var _playing := false
var _extras := {}
var _lamp_hot: StandardMaterial3D
var _lamp_cold: StandardMaterial3D
var _glow: OmniLight3D
var _halo: MeshInstance3D
var _halo_material := StandardMaterial3D.new()
var _drag := {}
## The case, its dressing, pillars and glow.
var dressing := RackWallDressing.new(self)
## Building, moving and removing the modules in the case.
var modules := RackWallModules.new(self)
## The touch keys, legends and the module palette.
var keys := RackWallKeys.new(self)
## Showing the room's patch, meters, scopes and cables.
var shown := RackWallShow.new(self)
## Grips, knobs and cable drags: the asks the wall makes.
var dragging := RackWallDrag.new(self)

## The two knobs of a module's orb pad, or an empty Array when it has none: the `pad_knobs` of the
## `rack_module` entry that provides the type.
static func pad_knobs(type: String) -> Array:
	var e := ModRegistry.ensure_current().rack_module_entry(type)
	return e["pad_knobs"] if e.get("pad_knobs") is Array else []


## Pads and bars on the modules: id -> {"node", "keys": [knob ids]}.
var _pads := {}
## A module being carried about the case: its id, node, ghost cell and where it came from.
var _carry := {}
var _streamed_at := {}
var _stream_due := {}
var _settle_at := {}
var _palette_nodes: Array[Node] = []
var _level := 0.0
var _hit := 0.0
## The level bar along the case's top edge, its segments, and the lit materials they take; the case's
## edge lines; and each module's colour band by id (it lights while the module sounds).
const VU_SEGMENTS := 36
var _vu: Array[MeshInstance3D] = []
var _vu_off: StandardMaterial3D
var _vu_on: StandardMaterial3D
var _vu_peak: StandardMaterial3D
var _edge_material := StandardMaterial3D.new()
var _bands := {}
## The room's own part of the rack: light pillars standing in an arc around the player, one for each
## module (in order across the case), each as tall as its module is loud and in its module's colour.
const PILLARS := 12
const PILLAR_RADIUS := 1.55
const PILLAR_TALL := 1.7
## Whether the floor pillars stand in front of the case (a room that has its own skyline turns them off).
var pillars := true
var _pillars: Array[MeshInstance3D] = []
var _pillar_for: Array = []
var _pillar_level: Array[float] = []


func _ready() -> void:
	surface_kind = &"modular"
	if surface_id == &"":
		surface_id = &"modular"
	super()
	_rebuild()
	child_entered_tree.connect(func(n: Node) -> void:
		if n is SurfaceHandle:
			_apply_reach.call_deferred())


func _on_shape_changed(_index: int) -> void:
	pass


func _on_connection_changed() -> void:
	pass


func _rebuild() -> void:
	if _built:
		return
	_built = true
	panel = Node3D.new()
	panel.name = "Panel"
	_adopt(panel)
	_lamp_hot = Materials.led(Color(0.4, 1.0, 0.5), true)
	_lamp_cold = Materials.led(Color(0.4, 1.0, 0.5), false)
	dressing._build_case()
	keys._build_touch()
	dressing._build_glow()
	var plaque := Stations.plaque(Modular.STATION, PLAQUE_WIDE)
	plaque.position = Vector3(PLAQUE_X, TALL - float(plaque.get_meta(&"plaque_tall")) * 0.5, PLAQUE_Z)
	_adopt(plaque)
	show_patch(patch)
	_apply_reach()


func framing_root() -> Node3D:
	return panel if panel != null else self


var _shone_key := Vector3(-1, -1, -1)


func _process(delta: float) -> void:
	super(delta)
	var now := int(clock.call())
	for id: String in _stream_due.keys():
		if now - int(_streamed_at.get(id, -100000)) >= STREAM_GAP_MSEC:
			_streamed_at[id] = now
			var d: Array = _stream_due[id]
			knob_streamed.emit(d[0], d[1], float(d[2]))
			_stream_due.erase(id)
	for id: String in _settle_at.keys():
		var k: Knob = knobs.get(id)
		if k != null and k.is_held():
			continue
		if now >= int(_settle_at[id]):
			_settle_at.erase(id)
			if k != null:
				knob_set.emit(String(id).get_slice(".", 0), String(id).get_slice(".", 1), k.value)
	_hit = maxf(_hit - delta * 3.0, 0.0)
	_shine()


# --- the case ---------------------------------------------------------------------------------

func _put(node: Node) -> void:
	node.set_meta("built", true)
	panel.add_child(node)


func _x_of(col: float) -> float:
	return -WIDE * 0.5 + MODULE_WIDE * col


## The foot of module row `row`, up the case: row 0 is the top one, over the palette.
func _row_foot(row: int) -> float:
	return PALETTE_TALL + (ROWS - 1 - row) * (ROW_TALL + ROW_GAP)
















## What the rack plays, for the light: its loudness 0..1 and whether it just hit. (`RackWallDressing.glow_with`)
func glow_with(level: float, hit: float) -> void: dressing.glow_with(level, hit)


## `RackWallDressing._shine`.
func _shine() -> void: dressing._shine()


## Take a new mood palette (`RackMood`) and repaint the glow.
func set_mood(m: Dictionary) -> void:
	mood = m
	_shine()






## `RackWallKeys._letter`.
func _letter(text: String, cap: float, at: Vector3, colour: Color, width := 0.0) -> Label3D:
	return keys._letter(text, cap, at, colour, width)


# --- the modules ------------------------------------------------------------------------------

## A key on the panel. (`RackWallKeys._key`)
func _key(legend: String, size: Vector2, at: Vector3, says: String, press: Callable, lit := false) -> EqWall.WallKey:
	return keys._key(legend, size, at, says, press, lit)


## A node out of the tree at once and freed at the frame's end: what replaces it never stands over it.
func _drop(n: Node) -> void:
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	n.queue_free()


## A jack's key in `jacks`: a module can have an input and an output of one name (a reverb's `l`), so an
## output's carries a mark.
static func _jack_key(path: String, is_output: bool) -> String:
	return path + ">" if is_output else path




























# --- the palette ------------------------------------------------------------------------------





## The track the rack sounds through (0 for none) and its name, on the TRK key. (`RackWallShow.set_track`)
func set_track(t: int, track_name := "") -> void: shown.set_track(t, track_name)


## `RackWallShow.set_recording`.
func set_recording(on: bool) -> void: shown.set_recording(on)


## True while the rack is being recorded to its track.
func is_recording() -> bool:
	return _recording




# --- what it shows ----------------------------------------------------------------------------

## The room's patch, shown. The modules are rebuilt only when their shape changes (one put in, taken out, moved, or a different set of knobs); a cable or a knob value changes in place. (`RackWallShow.show_patch`)
func show_patch(to: Dictionary) -> void: shown.show_patch(to)




## `RackWallShow.show_knob`.
func show_knob(id: String, k: String, v: float) -> void: shown.show_knob(id, k, v)


## How loud each module is now ({id: peak}), on its lamp. (`RackWallShow.module_levels`)
func module_levels(meters: Dictionary) -> Array: return shown.module_levels(meters)


## The traces of the SCOPE modules' screens: module id -> points. (`RackWallShow.show_steps`)
func show_steps(on: Dictionary) -> void: shown.show_steps(on)


## `RackWallShow.show_scopes`.
func show_scopes(waves: Dictionary) -> void: shown.show_scopes(waves)


## `RackWallShow.show_meters`.
func show_meters(meters: Dictionary) -> void: shown.show_meters(meters)


## `RackWallShow.turning`.
func turning() -> Dictionary: return shown.turning()




## `RackWallShow.show_keys`.
func show_keys(pitch: int, gate: bool) -> void: shown.show_keys(pitch, gate)


## `RackWallShow.show_playing`.
func show_playing(on: bool) -> void: shown.show_playing(on)


func _apply_reach() -> void:
	for c in reach_controls():
		for node in c.get_children():
			if node is CollisionShape3D:
				(node as CollisionShape3D).disabled = not within_reach


## Controls elsewhere in the room that this wall's hand reaches too (the CV bench's knobs).
var extra_controls: Array[ControlAffordance] = []


## Every control a hand can reach on the wall: extras, jacks, knobs and touch keys.
func reach_controls() -> Array[ControlAffordance]:
	var out: Array[ControlAffordance] = []
	out.append_array(extra_controls)
	for j: RackJack in jacks.values():
		out.append(j)
	for k: Knob in knobs.values():
		out.append(k)
	for t in touch_keys:
		out.append(t)
	for id: String in _pads:
		if is_instance_valid(_pads[id]["node"]):
			out.append(_pads[id]["node"])
	for key in module_nodes:
		var grip := (module_nodes[key] as Node).get_node_or_null("Grip") if not str(key).ends_with("/x") else null
		if grip is ControlAffordance:
			out.append(grip)
	for n in _palette_nodes:
		if n is ControlAffordance:
			out.append(n)
	for key in module_nodes:
		if str(key).ends_with("/x"):
			out.append(module_nodes[key])
	for n in get_children():
		if n is SurfaceHandle:
			out.append(n)
	return out


# --- a knob's turn ----------------------------------------------------------------------------



# --- carrying a module -----------------------------------------------------------------------



## `RackWallDrag._on_grip_began`.
func _on_grip_began(from: RackHandle, at: Vector3) -> void: dragging._on_grip_began(from, at)


## `RackWallDrag._on_grip_moved`.
func _on_grip_moved(from: RackHandle, at: Vector3) -> void: dragging._on_grip_moved(from, at)




## `RackWallDrag._on_grip_finished`.
func _on_grip_finished(from: RackHandle, _at: Vector3) -> void: dragging._on_grip_finished(from, _at)


# --- carrying a cable -------------------------------------------------------------------------














