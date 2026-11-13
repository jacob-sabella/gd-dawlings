class_name MilkVM
extends RefCounted

## What a MilkDrop preset's equations run on (docs/visuals.md): MilkEel turns a preset's per-frame, per-point
## or init code into a small GDScript extending this one, one member per variable (`v_` and the name in
## lower case), and these are the functions that code calls. Compiled, the equations run as GDScript
## bytecode, not as a tree walked node by node, which is what lets a preset's custom waves run their
## per-point code on a few hundred points a frame.
##
## MilkDrop's rules, kept here: everything is a float, a division by zero is 0, a comparison or a logical
## function gives 1 or 0, and nothing returns NaN or infinity (a preset that asks for the log of 0 gets 0).

## Where an expression statement's value goes.
var _d := 0.0


static func _div(a: float, b: float) -> float:
	return 0.0 if b == 0.0 else a / b


static func _mod(a: float, b: float) -> float:
	var ib := int(b)
	return 0.0 if ib == 0 else float(int(a) % ib)


static func _fin(x: float) -> float:
	return 0.0 if is_nan(x) or is_inf(x) else x


static func _pow(a: float, b: float) -> float:
	return _fin(pow(a, b))


static func _sqr(a: float) -> float:
	return a * a


static func _sqrt(a: float) -> float:
	return sqrt(absf(a))


static func _invsqrt(a: float) -> float:
	return _div(1.0, sqrt(absf(a)))


static func _exp(a: float) -> float:
	return exp(clampf(a, -80.0, 80.0))


static func _log(a: float) -> float:
	return log(a) if a > 0.0 else 0.0


static func _log10(a: float) -> float:
	return log(a) / log(10.0) if a > 0.0 else 0.0


static func _tan(a: float) -> float:
	return _fin(tan(a))


static func _asin(a: float) -> float:
	return asin(clampf(a, -1.0, 1.0))


static func _acos(a: float) -> float:
	return acos(clampf(a, -1.0, 1.0))


static func _atan2(y: float, x: float) -> float:
	return atan2(y, x)


static func _sign(a: float) -> float:
	return signf(a)


static func _rand(a: float) -> float:
	var n := int(a)
	return float(randi() % n) if n >= 1 else 0.0


static func _int(a: float) -> float:
	return float(int(a))


static func _above(a: float, b: float) -> float:
	return 1.0 if a > b else 0.0


static func _below(a: float, b: float) -> float:
	return 1.0 if a < b else 0.0


static func _equal(a: float, b: float) -> float:
	return 1.0 if absf(a - b) < 0.00001 else 0.0


static func _bnot(a: float) -> float:
	return 1.0 if a == 0.0 else 0.0


static func _band(a: float, b: float) -> float:
	return 1.0 if a != 0.0 and b != 0.0 else 0.0


static func _bor(a: float, b: float) -> float:
	return 1.0 if a != 0.0 or b != 0.0 else 0.0


static func _bits_and(a: float, b: float) -> float:
	return float(int(a) & int(b))


static func _bits_or(a: float, b: float) -> float:
	return float(int(a) | int(b))


static func _sigmoid(a: float, c: float) -> float:
	return _div(1.0, 1.0 + _exp(-a * c))


## Every variable this program knows, by its preset name (lower case), with its value.
func vars() -> Dictionary:
	var out := {}
	for prop in get_property_list():
		var n: String = prop["name"]
		if n.begins_with("v_"):
			out[n.substr(2)] = get(n)
	return out


## Sets variable `name` (a preset name, any case); a name the program does not use is ignored.
func put(name: String, value: float) -> void:
	set("v_" + name.to_lower(), value)


## Variable `name`'s value, finite, or `default` when the program does not use it.
func take(name: String, default := 0.0) -> float:
	var v: Variant = get("v_" + name.to_lower())
	return _fin(float(v)) if v != null else default
