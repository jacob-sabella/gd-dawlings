class_name BoxStyle
extends RefCounted

## The looks a made room can be given (docs/layouts.md 8): a floor, a wall, a trim, a lamp colour, the
## mood the modular room glows in and the tone of the gear. A made room names one by `shell.style`; one
## it does not know is the first.

const IDS: Array[StringName] = [&"warm", &"cool", &"neon", &"daylight", &"dark"]

const TABLE := {
	&"warm": {"title": "Warm wood", "floor": "#4A3220", "wall": "#6B4A33", "trim": "#B88A3E", "lamp": "#FFD9A0",
			"ambient": "#FFE3C2", "base": "#FF9E4D", "hit": "#FFE599"},
	&"cool": {"title": "Cool concrete", "floor": "#2B2F36", "wall": "#4A5260", "trim": "#9DB4D0", "lamp": "#CFE3FF",
			"ambient": "#BFD2EA", "base": "#6BB5FF", "hit": "#D6ECFF"},
	&"neon": {"title": "Neon", "floor": "#14101E", "wall": "#241636", "trim": "#FF4FD8", "lamp": "#9A6BFF",
			"ambient": "#6A4FA8", "base": "#FF4FD8", "hit": "#7DF9FF"},
	&"daylight": {"title": "Daylight", "floor": "#B9A88F", "wall": "#E8E1D3", "trim": "#8C7B63", "lamp": "#FFF6E0",
			"ambient": "#FFFFFF", "base": "#FFD27A", "hit": "#FFFFFF"},
	&"dark": {"title": "Black box", "floor": "#0E0E10", "wall": "#18181C", "trim": "#5A5A66", "lamp": "#FFFFFF",
			"ambient": "#80808C", "base": "#9E9EAE", "hit": "#FFFFFF"},
}


## True when `style` is one of the looks.
static func has(style: StringName) -> bool:
	return TABLE.has(style)


## The look called `style`, or the first for a name nobody ships.
static func of(style: StringName) -> Dictionary:
	return TABLE[style] if TABLE.has(style) else TABLE[IDS[0]]


## The mood of the modular room for `style` ({base, hit, glow}, as a layout's `mood`).
static func mood(style: StringName) -> Dictionary:
	var t := of(style)
	return {"base": t["base"], "hit": t["hit"], "glow": 0.7}
