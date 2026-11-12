class_name VisualBudget
extends RefCounted

## What the heavy visuals (docs/visuals.md: the MilkDrop-style screens and the simulations) may cost.
##
## A quality tier, OFF, LOW or HIGH, chosen by the player (`set_tier`, kept in user://visuals.cfg), or by
## --visuals=off|low|high or DAWLINGS_VISUALS for a run; with neither, HIGH on the desktop renderer, LOW
## on the mobile one, OFF on the compatibility renderer (no compute) and headless (nothing is drawn).
##
## Then who runs. A simulation asks every frame (`ask(node, distance)`) and runs only when granted: the
## nearest few that are on screen, at most `slots()` of them, ranked from what was asked the frame
## before. Further away it steps less often (`rate_hz`). And when the frames get slow (`pressure`, the
## average frame against the target) the slots fall to one until they recover.

enum Tier { OFF, LOW, HIGH }

const CONFIG := "user://visuals.cfg"
## A frame slower than this (s), averaged, is under pressure: 1/50 s leaves a 60 Hz screen some room.
const SLOW_FRAME := 1.0 / 50.0

static var _tier := -1
static var _asks := {}
static var _granted := {}
static var _ranked_frame := -1
static var _avg_frame := 1.0 / 60.0
static var _seen_frame := -1


static func tier() -> int:
	if _tier < 0:
		_tier = _decide()
	return _tier


static func _decide() -> int:
	var asked := OS.get_environment("DAWLINGS_VISUALS")
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--visuals="):
			asked = a.get_slice("=", 1)
	if asked != "":
		return _named(asked)
	if DisplayServer.get_name() == "headless":
		return Tier.OFF
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG) == OK and cfg.has_section_key("visuals", "tier"):
		return clampi(int(cfg.get_value("visuals", "tier")), Tier.OFF, Tier.HIGH)
	match RenderingServer.get_current_rendering_method():
		"forward_plus":
			return Tier.HIGH
		"mobile":
			return Tier.LOW
	return Tier.OFF


static func _named(word: String) -> int:
	match word.to_lower():
		"off", "0":
			return Tier.OFF
		"low", "1":
			return Tier.LOW
	return Tier.HIGH


## Choose the tier; kept for next time unless `keep` is false (a test).
static func set_tier(t: int, keep := true) -> void:
	_tier = clampi(t, Tier.OFF, Tier.HIGH)
	_asks.clear()
	_granted.clear()
	if keep:
		var cfg := ConfigFile.new()
		cfg.load(CONFIG)
		cfg.set_value("visuals", "tier", _tier)
		cfg.save(CONFIG)


static func tier_name(t := -1) -> String:
	return ["off", "low", "high"][tier() if t < 0 else t]


## Whether compute shaders can run here (the simulations need them): a RenderingDevice, and not OFF.
static func can_compute() -> bool:
	return tier() != Tier.OFF and RenderingServer.get_rendering_device() != null


## How many heavy visuals may run at once.
static func slots() -> int:
	match tier():
		Tier.HIGH:
			return 1 if pressure() > 1.0 else 3
		Tier.LOW:
			return 1
	return 0


## `high` on HIGH, `low` on LOW: a simulation's grid size, particle count, and so on.
static func pick(high: Variant, low: Variant) -> Variant:
	return high if tier() == Tier.HIGH else low


## How often (Hz) something this far away (m) is stepped: every frame close up, less across a room.
static func rate_hz(distance: float) -> float:
	if distance < 4.0:
		return 60.0
	if distance < 9.0:
		return 30.0
	return 15.0


## The average frame against SLOW_FRAME: over 1 is too slow. Fed by `ask`, once a frame.
static func pressure() -> float:
	return _avg_frame / SLOW_FRAME


## A heavy visual asks to run this frame: `distance` from the eye (m), or INF when it is not on screen.
## True if it may.
static func ask(node: Object, distance: float) -> bool:
	if tier() == Tier.OFF or node == null:
		return false
	var frame := Engine.get_process_frames()
	if frame != _seen_frame:
		_seen_frame = frame
		var tree := Engine.get_main_loop() as SceneTree
		var dt: float = tree.root.get_process_delta_time() if tree != null else 1.0 / 60.0
		_avg_frame = lerpf(_avg_frame, clampf(dt, 0.0, 0.25), 0.05)
	if frame != _ranked_frame:
		_rank(frame)
	var id := node.get_instance_id()
	_asks[id] = [distance, frame]
	return _granted.has(id) and is_finite(distance)


static func _rank(frame: int) -> void:
	_ranked_frame = frame
	var live: Array = []
	for id in _asks.keys():
		var a: Array = _asks[id]
		# Only what asked last frame (or this one) is still in the running.
		if frame - int(a[1]) > 2 or not is_instance_id_valid(id):
			_asks.erase(id)
		elif is_finite(float(a[0])):
			live.append([float(a[0]), id])
	live.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	_granted.clear()
	for k in mini(slots(), live.size()):
		_granted[live[k][1]] = true
	# A newcomer with a free slot is let in at once rather than a frame late.
	if live.size() < slots():
		for id in _asks.keys():
			_granted[id] = true


## For a test: forget every ask.
static func reset() -> void:
	_asks.clear()
	_granted.clear()
	_ranked_frame = -1
	_avg_frame = 1.0 / 60.0
