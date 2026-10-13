class_name RigRouletteStation
extends Node3D

## A small panel on the control room wall: start a new project with a random number of tracks, roll
## a few FX onto them and, unless locked, a key -- a fresh random roll every press, off nothing seeded,
## since this has nothing to do with a Tour run's own replay.
##
## A DUMB PANEL, NOT A DAW VERB
##
## This only ever reads its own wheels and emits `roll_requested`; it never calls `DAW` or checks
## `Session` itself. The actual roll -- the host gate, the track picking, the `DAW.add_fx`/
## `DAW.transpose_item` calls -- lives in `Studio.roll_rig`, called from the handler the owning
## scene wires to `roll_requested`, the same split `TourCase.break_attempted` /
## `Studio._on_tour_case_struck` already uses. Only the ROLL press itself is gated: a guest is
## free to nudge the wheels on their own view (local-only, unreplicated -- what they see is their
## own client's idea of the settings, not something that reaches anyone else), since nothing
## happens until the host's own press on ROLL, and that is the one place this matters.

signal roll_requested()

## Sized for a wall the band reads from across the room, not a console the seat is already close
## to -- about twice the linear size console controls get away with, so a wheel here still clears
## `tests/run_tests.gd`'s seat-aim-size floor from `core/venues/venue.gd`'s `rig_roulette_spot`.
const WIDTH := 0.2
const HEIGHT := 0.32

enum Pool { CHARACTER, EVERYTHING }

## Character-only FX, the same curated set Rig Roulette's own Tour-mode version draws from
## (`TourProject.RIG_FX`) -- meaningful only against the built-in engine's FXCatalogue kinds.
## Against a live Reaper plugin list there is no reliable way to tell a reverb from a synth by
## name alone, so EVERYTHING and CHARACTER draw from the same pool there; see `_pool_choices`.
const CHARACTER_KINDS: Array[StringName] = [&"distortion", &"chorus", &"reverb", &"delay", &"phaser"]

var count := 2
var pool := Pool.CHARACTER
var key_locked := false

var _last_label: Label3D
var _lock_key_button: PanelButton


func _ready() -> void:
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(WIDTH, HEIGHT, 0.01)
	plate.mesh = plate_mesh
	plate.position = Vector3(0, HEIGHT * 0.5, -0.006)
	plate.material_override = Materials.master_plate()
	add_child(plate)

	var caption := _label(28, Vector3(0, HEIGHT - 0.030, 0.001))
	caption.text = "RIG ROULETTE"
	add_child(caption)

	var count_wheel := TabletSelector.new()
	count_wheel.name = "CountWheel"
	count_wheel.size = Vector2(0.15, 0.034)
	count_wheel.hint_text = "scroll: how many pedals land"
	count_wheel.options = func() -> Array: return [[1, "1 PEDAL"], [2, "2 PEDALS"], [3, "3 PEDALS"]]
	count_wheel.choice = count
	count_wheel.position = Vector3(0, HEIGHT - 0.082, 0.004)
	count_wheel.chosen.connect(_on_count_chosen)
	count_wheel.describe_title = func() -> String: return "RIG ROULETTE  PEDAL COUNT"
	add_child(count_wheel)

	var pool_wheel := TabletSelector.new()
	pool_wheel.name = "PoolWheel"
	pool_wheel.size = Vector2(0.15, 0.034)
	pool_wheel.hint_text = "scroll: which pedals are in the pool"
	pool_wheel.options = func() -> Array: return _pool_choices()
	pool_wheel.choice = pool
	pool_wheel.position = Vector3(0, HEIGHT - 0.130, 0.004)
	pool_wheel.chosen.connect(_on_pool_chosen)
	pool_wheel.describe_title = func() -> String: return "RIG ROULETTE  PEDAL POOL"
	add_child(pool_wheel)

	var lock_label := _label(15, Vector3(-0.052, HEIGHT - 0.218, 0.001))
	lock_label.text = "LOCK KEY"
	add_child(lock_label)

	_lock_key_button = PanelButton.new()
	_lock_key_button.name = "LockKeyButton"
	_lock_key_button.led_colour = Color(0.95, 0.75, 0.2)
	# A PanelButton's body sits at its own local z origin, so scaling it up pushes its back face
	# backward too -- clear of the backing plate's own front face (z = -0.001) by the scaled
	# half-depth plus a margin, not the unscaled 0.004 every other flat-against-the-plate control
	# here uses.
	_lock_key_button.position = Vector3(0.024, HEIGHT - 0.218, 0.014)
	_lock_key_button.scale = Vector3(2.8, 2.8, 2.8)
	_lock_key_button.pressed.connect(_on_lock_key_pressed)
	_lock_key_button.describe_title = func() -> String: return "RIG ROULETTE  LOCK KEY"
	add_child(_lock_key_button)

	var roll_button := PanelButton.new()
	roll_button.name = "RollButton"
	roll_button.led_colour = Color(0.3, 0.85, 0.4)
	roll_button.position = Vector3(0, 0.064, 0.022)
	roll_button.scale = Vector3(5.0, 5.0, 5.0)
	roll_button.pressed.connect(_on_roll_pressed)
	roll_button.describe_title = func() -> String: return "RIG ROULETTE  ROLL"
	add_child(roll_button)

	var roll_label := _label(18, Vector3(0, 0.030, 0.001))
	roll_label.text = "ROLL"
	add_child(roll_label)

	_last_label = _label(13, Vector3(0, HEIGHT - 0.250, 0.001))
	_last_label.text = "no roll yet"
	add_child(_last_label)

	_lamp()


## Reported after a roll actually lands (from `Studio._roll_rig`), so the panel reads back what
## happened rather than only what is set up to happen next. `key` is empty when it was locked.
func show_result(tracks: int, fx_count: int, key: String) -> void:
	var line := "last roll: %d tracks, %d pedal%s" % [tracks, fx_count, "" if fx_count == 1 else "s"]
	if not key.is_empty():
		line += ", %s" % key
	_last_label.text = line


## On a post of its own and a foot, for a venue with no wall where it hangs
## (`Venue.back_wall_gear_stands`), or back on the wall. Again on a change of venue.
func set_free_standing(on: bool) -> void:
	var old := get_node_or_null("Post")
	if old != null:
		remove_child(old)
		old.queue_free()
	if not on:
		return
	var post := Node3D.new()
	post.name = "Post"
	add_child(post)
	var upright := MeshInstance3D.new()
	var upright_mesh := BoxMesh.new()
	upright_mesh.size = Vector3(0.05, position.y + HEIGHT * 0.5, 0.05)
	upright.mesh = upright_mesh
	upright.position = Vector3(0, (HEIGHT * 0.5 - position.y) * 0.5, -0.04)
	upright.material_override = Materials.furniture()
	GearTrim.edges(upright)
	post.add_child(upright)
	var foot := MeshInstance3D.new()
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(0.28, 0.03, 0.28)
	foot.mesh = foot_mesh
	foot.position = Vector3(0, 0.015 - position.y, -0.04)
	foot.material_override = Materials.furniture()
	post.add_child(foot)


## A small light of its own, the same fix `TourCase._lamp` makes for the back of house: this
## panel hangs on whichever stretch of wall the venue finds for it (`rig_roulette_spot`), which
## for the control room is past the ceiling downlights' own reach -- a dark panel on a dark wall
## without one, however correctly it is modelled.
func _lamp() -> void:
	var at := Vector3(0, HEIGHT + 0.10, 0.22)
	var strip := ZoneKit.block(self, Vector3(0.10, 0.012, 0.025), at, ZoneKit.glow(Color(1.0, 0.85, 0.7), 3.0),
			"StationLampStrip")
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := SpotLight3D.new()
	light.name = "StationLight"
	light.light_color = Color(1.0, 0.85, 0.7)
	light.light_energy = 3.0
	light.spot_range = 1.4
	light.spot_angle = 48.0
	light.spot_attenuation = 0.7
	light.shadow_enabled = false
	light.transform = Transform3D(Basis.looking_at(Vector3(0, HEIGHT * 0.5, 0) - at, Vector3.UP), at)
	add_child(light)


func _pool_choices() -> Array:
	# Reaper's own live plugin list carries no kind metadata to tell a reverb from a synth by, so
	# both wheel positions mean the same thing there -- said honestly in the label rather than
	# left to look broken when CHARACTER quietly does nothing different from EVERYTHING.
	if DAW.backend is ReaperBackend:
		return [[Pool.CHARACTER, "WHATEVER'S THERE"], [Pool.EVERYTHING, "WHATEVER'S THERE"]]
	return [[Pool.CHARACTER, "CHARACTER"], [Pool.EVERYTHING, "EVERYTHING"]]


func _on_count_chosen(c: int) -> void:
	count = c


func _on_pool_chosen(p: int) -> void:
	pool = p


func _on_lock_key_pressed() -> void:
	key_locked = not key_locked
	_lock_key_button.lit = key_locked


func _on_roll_pressed() -> void:
	roll_requested.emit()


func _label(font_size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = font_size * 4
	l.pixel_size = 0.00018
	l.position = pos
	l.modulate = Color(0.88, 0.89, 0.91)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(l)
	return l
