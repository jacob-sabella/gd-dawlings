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
## A wheel or the key lock moved: the owner reads `settings()` again.
signal changed()
## The BIG SCREEN wheel moved, or was clicked on to step it: show what is at `choice` of
## `screen_sources` on the board. Asked of the room by whoever owns the panel, never done here.
signal screen_chosen(choice: int)
## A preset was picked off the PRESET wheel (an id from `preset_sources`) or SAVE was pressed.
signal preset_chosen(choice: int)
signal preset_save_requested()
## UNDO ROLL was pressed.
signal undo_requested()

## Sized for a wall the band reads from across the room, not a console the seat is already close
## to -- about twice the linear size console controls get away with, so a wheel here still clears
## `tests/run_tests.gd`'s seat-aim-size floor from `core/venues/venue.gd`'s `rig_roulette_spot`.
const WIDTH := 0.2
const HEIGHT := 0.71

enum Pool { CHARACTER, EVERYTHING, TIME_BASED, DIRTY, CUSTOM }

## Character-only FX, the same curated set Rig Roulette's own Tour-mode version draws from
## (`TourProject.RIG_FX`) -- meaningful only against the built-in engine's FXCatalogue kinds.
## Against a live Reaper plugin list there is no reliable way to tell a reverb from a synth by
## name alone, so EVERYTHING and CHARACTER draw from the same pool there; see `_pool_choices`.
const CHARACTER_KINDS: Array[StringName] = RollSettings.CHARACTER_KINDS

var count := 2
var pool := Pool.CHARACTER
var key_locked := false
var per_track_cap := 1
var no_repeats := false
var scales := 0
var replay_last := false
var reroll_limit := -1
var chaos := 0
var tempo_pick := 0
## A CUSTOM pool's weights by kind name, as `RollSettings.weights`.
var weights := {}
var near_semitones := 0

## () -> Array of [id: int, words: String]: what the board can show, the write-up first. Set by
## whoever owns the panel, since only the room knows what gear it has.
var screen_sources: Callable = Callable()
var screen_wheel: TabletSelector
## () -> Array of [id: int, words: String] for the PRESET wheel; id 0 is the resting word.
var preset_sources: Callable = Callable()
var preset_wheel: TabletSelector
## A guest's wall: the wheels show the host's settings and a nudge is put back (the owner
## calls `apply_settings` again from `changed`).
var read_only := false

var _count_wheel: TabletSelector
var _pool_wheel: TabletSelector
var _cap_wheel: TabletSelector
var _scale_wheel: TabletSelector
var _near_wheel: TabletSelector
var _seed_wheel: TabletSelector
var _limit_wheel: TabletSelector
var _chaos_wheel: TabletSelector
var _tempo_wheel: TabletSelector
var _kind_wheel: TabletSelector
var _no_repeats_button: PanelButton

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
	count_wheel.options = func() -> Array: return _count_choices()
	count_wheel.choice = count
	_count_wheel = count_wheel
	count_wheel.position = Vector3(0, _row(0), 0.004)
	count_wheel.chosen.connect(_on_count_chosen)
	count_wheel.describe_title = func() -> String: return "RIG ROULETTE  PEDAL COUNT"
	add_child(count_wheel)

	var pool_wheel := TabletSelector.new()
	pool_wheel.name = "PoolWheel"
	pool_wheel.size = Vector2(0.15, 0.034)
	pool_wheel.hint_text = "scroll: which pedals are in the pool"
	pool_wheel.options = func() -> Array: return _pool_choices()
	pool_wheel.choice = pool
	_pool_wheel = pool_wheel
	pool_wheel.position = Vector3(0, _row(1), 0.004)
	pool_wheel.chosen.connect(_on_pool_chosen)
	pool_wheel.describe_title = func() -> String: return "RIG ROULETTE  PEDAL POOL"
	add_child(pool_wheel)

	var cap_wheel := TabletSelector.new()
	cap_wheel.name = "CapWheel"
	cap_wheel.size = Vector2(0.15, 0.030)
	cap_wheel.hint_text = "scroll: most pedals one track may take, or the whole mix on one"
	cap_wheel.options = func() -> Array:
		return [[0, "WHOLE MIX: ONE TRACK"], [1, "1 PER TRACK"], [2, "UP TO 2 PER TRACK"], [3, "UP TO 3 PER TRACK"]]
	cap_wheel.choice = per_track_cap
	_cap_wheel = cap_wheel
	cap_wheel.position = Vector3(0, _row(2), 0.004)
	cap_wheel.chosen.connect(_on_cap_chosen)
	cap_wheel.describe_title = func() -> String: return "RIG ROULETTE  PEDALS PER TRACK"
	add_child(cap_wheel)

	_scale_wheel = TabletSelector.new()
	_scale_wheel.name = "ScaleWheel"
	_scale_wheel.size = Vector2(0.15, 0.030)
	_scale_wheel.hint_text = "scroll: which scales the key is drawn from"
	_scale_wheel.options = func() -> Array:
		return [[0, "MAJOR OR MINOR"], [1, "ANY MODE"], [2, "PENTATONIC + BLUES"]]
	_scale_wheel.choice = scales
	_scale_wheel.position = Vector3(0, _row(3), 0.004)
	_scale_wheel.chosen.connect(func(c: int) -> void:
		scales = c
		changed.emit())
	_scale_wheel.describe_title = func() -> String: return "RIG ROULETTE  SCALES"
	add_child(_scale_wheel)

	_near_wheel = TabletSelector.new()
	_near_wheel.name = "NearWheel"
	_near_wheel.size = Vector2(0.15, 0.030)
	_near_wheel.hint_text = "scroll: how far from the last roll's key the new one may land"
	_near_wheel.options = func() -> Array:
		var out := [[0, "ANY KEY"]]
		for n in range(1, RollSettings.NEAR_MAX + 1):
			out.append([n, "WITHIN %d SEMITONE%s" % [n, "" if n == 1 else "S"]])
		return out
	_near_wheel.choice = near_semitones
	_near_wheel.position = Vector3(0, _row(4), 0.004)
	_near_wheel.chosen.connect(func(c: int) -> void:
		near_semitones = c
		changed.emit())
	_near_wheel.describe_title = func() -> String: return "RIG ROULETTE  NEAR THE LAST KEY"
	add_child(_near_wheel)

	_seed_wheel = TabletSelector.new()
	_seed_wheel.name = "SeedWheel"
	_seed_wheel.size = Vector2(0.15, 0.030)
	_seed_wheel.hint_text = "scroll: a fresh seed each roll, or the last roll again"
	_seed_wheel.options = func() -> Array: return [[0, "FRESH SEED EACH ROLL"], [1, "REPLAY THE LAST ROLL"]]
	_seed_wheel.choice = 1 if replay_last else 0
	_seed_wheel.position = Vector3(0, _row(5), 0.004)
	_seed_wheel.chosen.connect(func(c: int) -> void:
		replay_last = c == 1
		changed.emit())
	_seed_wheel.describe_title = func() -> String: return "RIG ROULETTE  SEED"
	add_child(_seed_wheel)

	_limit_wheel = TabletSelector.new()
	_limit_wheel.name = "RerollWheel"
	_limit_wheel.size = Vector2(0.15, 0.030)
	_limit_wheel.hint_text = "scroll: how many times the band may roll again after the first"
	_limit_wheel.options = func() -> Array:
		var out := [[-1, "RE-ROLL: AS MANY AS IT TAKES"], [0, "NO RE-ROLLS: WRITE WITH IT"]]
		for n in range(1, RollSettings.REROLLS_MAX + 1):
			out.append([n, "%d RE-ROLL%s" % [n, "" if n == 1 else "S"]])
		return out
	_limit_wheel.choice = reroll_limit
	_limit_wheel.position = Vector3(0, _row(6), 0.004)
	_limit_wheel.chosen.connect(func(c: int) -> void:
		reroll_limit = c
		changed.emit())
	_limit_wheel.describe_title = func() -> String: return "RIG ROULETTE  RE-ROLLS"
	add_child(_limit_wheel)

	_chaos_wheel = TabletSelector.new()
	_chaos_wheel.name = "ChaosWheel"
	_chaos_wheel.size = Vector2(0.15, 0.030)
	_chaos_wheel.hint_text = "scroll: leave each pedal's knobs alone, or throw them"
	_chaos_wheel.options = func() -> Array:
		var out := [[0, "KNOBS: SAFE DEFAULTS"]]
		for n in range(1, RollSettings.CHAOS_MAX + 1):
			out.append([n, "KNOBS: CHAOS %d%%" % (n * 100 / RollSettings.CHAOS_MAX)])
		return out
	_chaos_wheel.choice = chaos
	_chaos_wheel.position = Vector3(0, _row(7), 0.004)
	_chaos_wheel.chosen.connect(func(c: int) -> void:
		chaos = c
		changed.emit())
	_chaos_wheel.describe_title = func() -> String: return "RIG ROULETTE  KNOBS"
	add_child(_chaos_wheel)

	_tempo_wheel = TabletSelector.new()
	_tempo_wheel.name = "TempoWheel"
	_tempo_wheel.size = Vector2(0.15, 0.030)
	_tempo_wheel.hint_text = "scroll: keep the tempo, or roll one in a range"
	_tempo_wheel.options = func() -> Array:
		var names := ["TEMPO: LOCKED", "TEMPO: ANY 60-180", "TEMPO: SLOW 60-90", "TEMPO: MEDIUM 90-120", "TEMPO: FAST 120-160"]
		var out := []
		for i in names.size():
			out.append([i, names[i]])
		return out
	_tempo_wheel.choice = tempo_pick
	_tempo_wheel.position = Vector3(0, _row(9), 0.004)
	_tempo_wheel.chosen.connect(func(c: int) -> void:
		tempo_pick = c
		changed.emit())
	_tempo_wheel.describe_title = func() -> String: return "RIG ROULETTE  TEMPO"
	add_child(_tempo_wheel)

	_kind_wheel = TabletSelector.new()
	_kind_wheel.name = "KindWheel"
	_kind_wheel.size = Vector2(0.15, 0.030)
	_kind_wheel.hint_text = "scroll: which kind of pedal  ·  click: how much it weighs (off, 1, 2, 3)"
	_kind_wheel.options = _kind_choices
	_kind_wheel.choice = 0
	_kind_wheel.position = Vector3(0, _row(10), 0.004)
	_kind_wheel.pressed.connect(_on_kind_stepped)
	_kind_wheel.describe_title = func() -> String: return "RIG ROULETTE  KINDS"
	add_child(_kind_wheel)

	screen_wheel = TabletSelector.new()
	screen_wheel.name = "ScreenWheel"
	screen_wheel.size = Vector2(0.15, 0.030)
	screen_wheel.hint_text = "scroll: what the big screen shows  ·  click: the next"
	screen_wheel.options = func() -> Array:
		return screen_sources.call() if screen_sources.is_valid() else [[0, "ROLL"]]
	screen_wheel.choice = 0
	screen_wheel.position = Vector3(0, _row(8), 0.004)
	screen_wheel.chosen.connect(func(c: int) -> void: screen_chosen.emit(c))
	screen_wheel.pressed.connect(_on_screen_stepped)
	screen_wheel.describe_title = func() -> String: return "BIG SCREEN"
	add_child(screen_wheel)

	preset_wheel = TabletSelector.new()
	preset_wheel.name = "PresetWheel"
	preset_wheel.size = Vector2(0.15, 0.030)
	preset_wheel.hint_text = "scroll: load a preset, built in or saved"
	preset_wheel.options = func() -> Array:
		return preset_sources.call() if preset_sources.is_valid() else [[0, "PRESETS"]]
	preset_wheel.choice = 0
	preset_wheel.position = Vector3(0, _row(11), 0.004)
	preset_wheel.chosen.connect(func(c: int) -> void:
		preset_chosen.emit(c)
		# It loads and rests: the wheel says what it does, not what is set.
		preset_wheel.choice = 0
		preset_wheel.refresh())
	preset_wheel.describe_title = func() -> String: return "RIG ROULETTE  PRESETS"
	add_child(preset_wheel)

	var lock_label := _label(15, Vector3(-0.068, HEIGHT - 0.527, 0.001))
	lock_label.text = "LOCK KEY"
	add_child(lock_label)

	_lock_key_button = PanelButton.new()
	_lock_key_button.name = "LockKeyButton"
	_lock_key_button.led_colour = Color(0.95, 0.75, 0.2)
	# A PanelButton's body sits at its own local z origin, so scaling it up pushes its back face
	# backward too -- clear of the backing plate's own front face (z = -0.001) by the scaled
	# half-depth plus a margin, not the unscaled 0.004 every other flat-against-the-plate control
	# here uses.
	_lock_key_button.position = Vector3(-0.020, HEIGHT - 0.527, 0.014)
	_lock_key_button.scale = Vector3(2.8, 2.8, 2.8)
	_lock_key_button.lit = key_locked
	_lock_key_button.pressed.connect(_on_lock_key_pressed)
	_lock_key_button.describe_title = func() -> String: return "RIG ROULETTE  LOCK KEY"
	add_child(_lock_key_button)

	var save_label := _label(15, Vector3(0.044, HEIGHT - 0.527, 0.001))
	save_label.text = "SAVE"
	add_child(save_label)

	var save_button := PanelButton.new()
	save_button.name = "SaveButton"
	save_button.led_colour = Color(0.4, 0.8, 0.95)
	save_button.position = Vector3(0.086, HEIGHT - 0.527, 0.014)
	save_button.scale = Vector3(2.8, 2.8, 2.8)
	save_button.pressed.connect(func() -> void: preset_save_requested.emit())
	save_button.describe_title = func() -> String: return "RIG ROULETTE  SAVE PRESET"
	add_child(save_button)

	var undo_label := _label(15, Vector3(0.044, HEIGHT - 0.569, 0.001))
	undo_label.text = "UNDO"
	add_child(undo_label)

	var undo_button := PanelButton.new()
	undo_button.name = "UndoButton"
	undo_button.led_colour = Color(0.95, 0.4, 0.3)
	undo_button.position = Vector3(0.086, HEIGHT - 0.569, 0.014)
	undo_button.scale = Vector3(2.8, 2.8, 2.8)
	undo_button.pressed.connect(func() -> void: undo_requested.emit())
	undo_button.describe_title = func() -> String: return "RIG ROULETTE  UNDO THE LAST ROLL"
	add_child(undo_button)

	var repeat_label := _label(15, Vector3(-0.052, HEIGHT - 0.569, 0.001))
	repeat_label.text = "NO REPEATS"
	add_child(repeat_label)

	_no_repeats_button = PanelButton.new()
	_no_repeats_button.name = "NoRepeatsButton"
	_no_repeats_button.led_colour = Color(0.95, 0.75, 0.2)
	_no_repeats_button.position = Vector3(0.036, HEIGHT - 0.569, 0.014)
	_no_repeats_button.scale = Vector3(2.8, 2.8, 2.8)
	_no_repeats_button.lit = no_repeats
	_no_repeats_button.pressed.connect(_on_no_repeats_pressed)
	_no_repeats_button.describe_title = func() -> String: return "RIG ROULETTE  NO REPEATS"
	add_child(_no_repeats_button)

	var roll_button := PanelButton.new()
	roll_button.name = "RollButton"
	roll_button.led_colour = Color(0.3, 0.85, 0.4)
	roll_button.position = Vector3(0, 0.056, 0.022)
	roll_button.scale = Vector3(5.0, 5.0, 5.0)
	roll_button.pressed.connect(_on_roll_pressed)
	roll_button.describe_title = func() -> String: return "RIG ROULETTE  ROLL"
	add_child(roll_button)

	var roll_label := _label(18, Vector3(0, 0.020, 0.001))
	roll_label.text = "ROLL"
	add_child(roll_label)

	_last_label = _label(13, Vector3(0, HEIGHT - 0.611, 0.001))
	_last_label.text = "no roll yet"
	add_child(_last_label)

	_lamp()
	_letter_for_the_scale()


## The labels work out how far away they can be read for a panel of their own size; a wall stood
## bigger than that (`scale`) is readable from further off by as much, so they say so.
func _letter_for_the_scale() -> void:
	var by := maxf(scale.x, 1.0)
	if by <= 1.0:
		return
	for n in find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l.visibility_range_end > 0.0:
			l.visibility_range_end *= by
			l.visibility_range_end_margin *= by


## The wheels as the roll's settings.
func settings() -> RollSettings:
	var s := RollSettings.new()
	s.count = count
	s.pool = pool as RollSettings.Pool
	s.key_locked = key_locked
	s.per_track_cap = per_track_cap
	s.no_repeats = no_repeats
	s.scales = scales as RollSettings.Scales
	s.near_semitones = near_semitones
	s.replay_last = replay_last
	s.reroll_limit = reroll_limit
	s.chaos = chaos
	s.tempo_pick = tempo_pick
	s.weights = RollSettings.clean_weights(weights)
	return s


## Show `s` on the wheels and the lock, without telling the owner it changed.
func apply_settings(s: RollSettings) -> void:
	count = s.count
	pool = int(s.pool) as Pool
	key_locked = s.key_locked
	per_track_cap = s.per_track_cap
	no_repeats = s.no_repeats
	scales = int(s.scales)
	near_semitones = s.near_semitones
	replay_last = s.replay_last
	reroll_limit = s.reroll_limit
	chaos = s.chaos
	tempo_pick = s.tempo_pick
	weights = s.weights.duplicate()
	if _count_wheel != null:
		_kind_wheel.refresh()
		_tempo_wheel.choice = tempo_pick
		_tempo_wheel.refresh()
		_chaos_wheel.choice = chaos
		_chaos_wheel.refresh()
		_seed_wheel.choice = 1 if replay_last else 0
		_seed_wheel.refresh()
		_limit_wheel.choice = reroll_limit
		_limit_wheel.refresh()
		_scale_wheel.choice = scales
		_scale_wheel.refresh()
		_near_wheel.choice = near_semitones
		_near_wheel.refresh()
		_cap_wheel.choice = per_track_cap
		_cap_wheel.refresh()
		_no_repeats_button.lit = no_repeats
		_count_wheel.choice = count
		_count_wheel.refresh()
		_pool_wheel.choice = pool
		_pool_wheel.refresh()
		_lock_key_button.lit = key_locked


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
	return [[Pool.CHARACTER, "CHARACTER"], [Pool.EVERYTHING, "EVERYTHING"], [Pool.TIME_BASED, "TIME-BASED ONLY"],
			[Pool.DIRTY, "DIRTY ONLY"], [Pool.CUSTOM, "CUSTOM (KINDS ROW)"]]


## The y of the n-th wheel down the wall.
func _row(n: int) -> float:
	return HEIGHT - 0.076 - 0.037 * n


func _count_choices() -> Array:
	var out := []
	for n in range(RollSettings.COUNT_MIN, RollSettings.COUNT_MAX + 1):
		out.append([n, "NO PEDALS" if n == 0 else ("%d PEDAL%s" % [n, "" if n == 1 else "S"])])
	return out


func _on_cap_chosen(c: int) -> void:
	per_track_cap = c
	changed.emit()


func _on_no_repeats_pressed() -> void:
	no_repeats = not no_repeats
	_no_repeats_button.lit = no_repeats
	changed.emit()


func _on_count_chosen(c: int) -> void:
	count = c
	changed.emit()


## What each kind weighs as the wall shows it: the CUSTOM pool's own, or what the pool in force
## amounts to.
func _shown_weights() -> Dictionary:
	return weights if pool == Pool.CUSTOM else RollSettings.weights_of(pool as RollSettings.Pool)


func _kind_choices() -> Array:
	var shown := _shown_weights()
	var out := []
	for i in RollSettings.ALL_KINDS.size():
		var k := String(RollSettings.ALL_KINDS[i])
		var w := int(shown.get(k, 0))
		out.append([i, "%s: %s" % [k.to_upper(), "OFF" if w == 0 else "x%d" % w]])
	return out


## A click on the KIND row: the next weight for the kind in the window. Touching any kind makes the
## pool CUSTOM, starting from whatever it was.
func _on_kind_stepped(choice: int) -> void:
	var k := String(RollSettings.ALL_KINDS[choice])
	var now := _shown_weights().duplicate()
	now[k] = (int(now.get(k, 0)) + 1) % (RollSettings.WEIGHT_MAX + 1)
	weights = now
	pool = Pool.CUSTOM
	_pool_wheel.choice = pool
	_pool_wheel.refresh()
	_kind_wheel.refresh()
	changed.emit()


func _on_pool_chosen(p: int) -> void:
	if p == Pool.CUSTOM and weights.is_empty():
		weights = RollSettings.weights_of(pool as RollSettings.Pool)
	pool = p
	if _kind_wheel != null:
		_kind_wheel.refresh()
	changed.emit()


## A click on the BIG SCREEN wheel: the next thing on the list, so it can be stepped through
## without a scroll wheel.
func _on_screen_stepped(_choice: int) -> void:
	screen_wheel._on_nudge(1, false)


func _on_lock_key_pressed() -> void:
	key_locked = not key_locked
	_lock_key_button.lit = key_locked
	changed.emit()


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
