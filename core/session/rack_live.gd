class_name RackLive
extends RefCounted

## What the modular room is doing right now, as the host sends it to guests: how loud each module is, the
## step each sequencer is on, the traces on the scopes, and the rack's own glow (level and hit). The engine is a
## process on the host only, so a guest has none of this to read; without it a guest's rack wall, its
## sequencer's step lights and the room's lights stand still while the host plays.
##
## It travels with the project state as the volatile entry `/rack/live` (DAWBackend.is_volatile: unreliable,
## sent again every tick, never queued behind a name change) and lands in `MixState.rack_live`. Small on
## purpose: meters are a byte each (1/255 steps), a scope point a byte (-1..1), the scopes every other tick.

## The entry's address.
const ADDRESS := "/rack/live"
## A scope's points are bytes: this is the byte that means zero.
const SCOPE_ZERO := 128
## A guest that has heard nothing for this long shows the rack as quiet (the host stopped, or the link did).
const STALE_MSEC := 1500


## The entry's arguments for the host's rack now. `with_scopes` leaves the scopes out of a tick that need not carry
## them (the guest keeps the ones it has). A rack that is not running is `[false]`, which blanks the guest's.
static func pack(level: float, hit: float, meters: Dictionary, steps: Dictionary, scopes: Dictionary,
		with_scopes: bool) -> Array:
	var meter_ids := PackedStringArray()
	var meter_bytes := PackedByteArray()
	for id: String in meters:
		meter_ids.append(id)
		meter_bytes.append(int(roundf(clampf(float(meters[id]), 0.0, 1.0) * 255.0)))
	var step_ids := PackedStringArray()
	var step_at := PackedInt32Array()
	for id: String in steps:
		step_ids.append(id)
		step_at.append(int(steps[id]))
	var scope_ids := PackedStringArray()
	var scope_bytes: Array = []
	if with_scopes:
		for id: String in scopes:
			var wave: PackedFloat32Array = scopes[id]
			var bytes := PackedByteArray()
			bytes.resize(wave.size())
			for k in wave.size():
				bytes[k] = clampi(SCOPE_ZERO + int(roundf(clampf(wave[k], -1.0, 1.0) * 127.0)), 0, 255)
			scope_ids.append(id)
			scope_bytes.append(bytes)
	return [true, with_scopes, clampf(level, 0.0, 1.0), clampf(hit, 0.0, 1.0), meter_ids, meter_bytes, step_ids,
			step_at, scope_ids, scope_bytes]


## The state a guest keeps for entry arguments `args`, over what it had (`before`, for the scopes a tick left out):
## `{level, hit, meters, steps, scopes, at}`, `at` the moment it was heard; `{}` for a rack that has stopped. Anything
## that is not what `pack` makes leaves `before` as it was.
static func unpack(args: Array, before: Dictionary) -> Dictionary:
	if args.size() == 1 and args[0] == false:
		return {}
	if args.size() < 10 or not (args[0] is bool and args[1] is bool and args[2] is float and args[3] is float \
			and args[4] is PackedStringArray and args[5] is PackedByteArray and args[6] is PackedStringArray \
			and args[7] is PackedInt32Array and args[8] is PackedStringArray and args[9] is Array):
		return before
	var meter_ids: PackedStringArray = args[4]
	var meter_bytes: PackedByteArray = args[5]
	var step_ids: PackedStringArray = args[6]
	var step_at: PackedInt32Array = args[7]
	var scope_ids: PackedStringArray = args[8]
	var scope_bytes: Array = args[9]
	if meter_ids.size() != meter_bytes.size() or step_ids.size() != step_at.size() or scope_ids.size() != scope_bytes.size():
		return before
	var meters := {}
	for k in meter_ids.size():
		meters[meter_ids[k]] = float(meter_bytes[k]) / 255.0
	var steps := {}
	for k in step_ids.size():
		steps[step_ids[k]] = step_at[k]
	var scopes: Dictionary = before.get("scopes", {})
	if args[1]:
		scopes = {}
		for k in scope_ids.size():
			if not scope_bytes[k] is PackedByteArray:
				return before
			var bytes: PackedByteArray = scope_bytes[k]
			var wave := PackedFloat32Array()
			wave.resize(bytes.size())
			for j in bytes.size():
				wave[j] = float(int(bytes[j]) - SCOPE_ZERO) / 127.0
			scopes[scope_ids[k]] = wave
	return {"level": clampf(args[2], 0.0, 1.0), "hit": clampf(args[3], 0.0, 1.0), "meters": meters, "steps": steps,
			"scopes": scopes, "at": Time.get_ticks_msec()}


## The rack's state as a guest holds it (`MixState.rack_live`), `{}` when it is missing or too old to be live.
static func fresh(live: Dictionary) -> Dictionary:
	if live.is_empty() or Time.get_ticks_msec() - int(live.get("at", 0)) > STALE_MSEC:
		return {}
	return live
