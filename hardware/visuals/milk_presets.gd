class_name MilkPresets
extends RefCounted

## The looks a MilkScreen cycles through (docs/visuals.md): each one a set of base parameters and a
## per-frame function that moves them with the music, in the spirit of a MilkDrop preset.
##
## A frame's parameters are a flat Dictionary, `defaults()` overlaid with the preset's `base`, then
## handed to its `frame` Callable together with this frame's features and the preset's own memory:
##   frame.call(p: Dictionary, f: Dictionary, mem: Dictionary)
## `p` is written in place and thrown away after the frame (the next starts from the base again), `mem`
## persists for as long as the preset is showing, for a value that has to build up (a hue that jumps on
## each hit, a slow accumulated angle).
##
## The features `f` carries: `t` (s, the screen's own clock), `bass`, `mid`, `treb` (1 is typical, 0 is
## silence, up to 4), `bass_att`, `mid_att`, `treb_att` (the same, eased), `hit` (1 when something lands,
## falling), `level` (0..1), `beat_phase` (0..1) and `hue` (the room's mood colour's hue, 0..1), which
## most looks start their colours from. Silence must still move and glow: every look keeps a slow motion
## of its own on `t`.
##
## What the parameters mean, as MilkScreen draws them:
##  - the warp, each frame, of last frame's picture: `zoom` (>1 flies in), `zoom_curve` (0 even, 1 the
##    edges zoom more than the middle: a tunnel), `rot` (radians a frame), `warp`, `warp_speed` and
##    `warp_scale` (a liquid wobble), `cx`/`cy` (the centre, 0..1), `dx`/`dy` (a drift a frame), `sx`/`sy`
##    (stretch), `ripple`/`ripple_freq` (rings of zoom running outward), `fold`/`sides` (a kaleidoscope's
##    mirror, 0..1 of it, and how many segments), `wrap` (1 the edges mirror back in, 0 they fade to
##    black), `blur` (0..1), `hue_drift` (turns a frame the whole picture's hue rotates) and `decay` (how
##    much of last frame survives);
##  - the ink drawn on top: `wave_mode` (WAVE_*), `wave_color`, `wave_alpha`, `wave_scale`, `wave_thick`
##    (px of a 512-wide buffer), `wave_rad` (a circle's radius, of the height), `wave_x`/`wave_y` (0..1), `wave_rot` (radians); a shape: `shape_kind`
##    (SHAPE_*), `shape_sides`, `shape_rad` (of the height), `shape_ang`, `shape_x`/`shape_y`,
##    `shape_color`, `shape_alpha`, `shape_thick`;
##  - the final look on the glass: `gamma`, `bright`, `hue` (turns), `saturate`, `echo` (0..1 of a second,
##    zoomed and flipped copy), `echo_zoom`, `echo_orient` (0 none, 1 flip x, 2 flip y, 3 both), `invert`
##    (0..1), `solar` (0..1) and `vignette`.

enum { WAVE_LINE, WAVE_DOTS, WAVE_CIRCLE, WAVE_MIRROR, WAVE_XY, WAVE_BLOOM }
enum { SHAPE_NONE, SHAPE_RING, SHAPE_RAYS }

## Parameters that are chosen, not mixed: in a crossfade they switch half way.
const DISCRETE := ["wave_mode", "shape_kind", "shape_sides", "sides", "echo_orient"]

static var _list: Array[Dictionary] = []


## Every parameter at rest: a slow, even, slightly zooming picture with a line through it.
static func defaults() -> Dictionary:
	return {
		"zoom": 1.01, "zoom_curve": 0.0, "rot": 0.0, "warp": 0.3, "warp_speed": 1.0, "warp_scale": 1.0,
		"cx": 0.5, "cy": 0.5, "dx": 0.0, "dy": 0.0, "sx": 1.0, "sy": 1.0,
		"ripple": 0.0, "ripple_freq": 14.0, "fold": 0.0, "sides": 6, "wrap": 1.0, "blur": 0.3,
		"hue_drift": 0.0, "decay": 0.97,
		"wave_mode": WAVE_LINE, "wave_color": Color(0.6, 0.8, 1.0), "wave_alpha": 0.9, "wave_scale": 1.0,
		"wave_thick": 2.5, "wave_rad": 0.22, "wave_x": 0.5, "wave_y": 0.5, "wave_rot": 0.0,
		"shape_kind": SHAPE_NONE, "shape_sides": 6, "shape_rad": 0.2, "shape_ang": 0.0,
		"shape_x": 0.5, "shape_y": 0.5, "shape_color": Color(1, 1, 1), "shape_alpha": 0.0, "shape_thick": 2.0,
		"gamma": 1.0, "bright": 1.0, "hue": 0.0, "saturate": 1.0, "echo": 0.0, "echo_zoom": 1.0,
		"echo_orient": 0, "invert": 0.0, "solar": 0.0, "vignette": 0.35,
	}


static func count() -> int:
	return all().size()


static func preset_name(i: int) -> String:
	return String(all()[posmod(i, count())]["name"])


## The presets, each {name, base, frame}. Built once.
static func all() -> Array[Dictionary]:
	if _list.is_empty():
		_list = [
			_tunnel(), _spiral(), _kaleido(), _liquid(), _starburst(),
			_drift(), _bloom(), _strobe(), _vortex(), _echo_hall(),
		]
	return _list


## Preset `i`'s parameters for this frame: the defaults, its base, then its frame function.
static func evaluate(i: int, f: Dictionary, mem: Dictionary) -> Dictionary:
	var preset: Dictionary = all()[posmod(i, count())]
	var p := defaults()
	p.merge(preset["base"], true)
	(preset["frame"] as Callable).call(p, f, mem)
	return p


## `a` turned into `b` by `k` (0..1): numbers and colours mixed, the discrete ones switched half way.
static func blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := {}
	for key in b:
		var vb: Variant = b[key]
		var va: Variant = a.get(key, vb)
		if key in DISCRETE:
			out[key] = vb if k >= 0.5 else va
		elif vb is Color:
			out[key] = _mix_colour(va, vb, k)
		else:
			out[key] = lerpf(float(va), float(vb), k)
	return out


## Two colours mixed the short way round the hue wheel, so red to cyan passes through a colour and
## not through grey.
static func _mix_colour(a: Color, b: Color, k: float) -> Color:
	var h := a.h + wrapf(b.h - a.h, -0.5, 0.5) * k
	if a.s < 0.02:
		h = b.h
	elif b.s < 0.02:
		h = a.h
	return Color.from_hsv(fposmod(h, 1.0), lerpf(a.s, b.s, k), lerpf(a.v, b.v, k), lerpf(a.a, b.a, k))


## Features for silence, for a test or a screen with nothing to listen to.
static func quiet(t := 0.0, hue := 0.6) -> Dictionary:
	return {"t": t, "bass": 0.0, "mid": 0.0, "treb": 0.0, "bass_att": 0.0, "mid_att": 0.0,
			"treb_att": 0.0, "hit": 0.0, "level": 0.0, "beat_phase": fposmod(t * 2.0, 1.0), "hue": hue}


static func _hsv(h: float, s: float, v: float) -> Color:
	return Color.from_hsv(fposmod(h, 1.0), clampf(s, 0.0, 1.0), clampf(v, 0.0, 1.0))


# --- the looks ------------------------------------------------------------------------------------

## Flying down a tunnel: an even zoom that pulls the circle of the wave past you, harder on the bass,
## its centre wandering so the walls bend.
static func _tunnel() -> Dictionary:
	return {
		"name": "Tunnel Dive",
		"base": {"zoom_curve": 0.7, "decay": 0.945, "blur": 0.2, "warp": 0.35, "wave_mode": WAVE_CIRCLE,
				"wave_thick": 3.0, "wave_alpha": 0.85, "hue_drift": 0.009, "gamma": 1.05, "vignette": 0.45, "saturate": 1.15},
		"frame": func(p: Dictionary, f: Dictionary, _mem: Dictionary) -> void:
			var t: float = f.t
			p.zoom = 1.03 + 0.03 * f.bass_att + 0.05 * f.hit
			p.rot = 0.006 * sin(t * 0.21)
			p.cx = 0.5 + 0.08 * sin(t * 0.37)
			p.cy = 0.5 + 0.06 * cos(t * 0.29)
			p.wave_x = p.cx
			p.wave_y = p.cy
			p.wave_color = _hsv(f.hue + t * 0.03, 0.8, 1.0)
			p.wave_scale = 0.55 + 0.3 * f.bass + 0.15 * sin(t * 0.8)
			p.bright = 1.0 + 0.35 * f.hit,
	}


## Spiral arms: a slow turn and a gentle zoom smear a spinning line into curling arms; the bass winds it
## tighter.
static func _spiral() -> Dictionary:
	return {
		"name": "Spiral Arms",
		"base": {"zoom_curve": 0.3, "decay": 0.958, "blur": 0.2, "warp": 0.1, "wave_mode": WAVE_LINE,
				"wave_thick": 3.0, "wave_scale": 0.8, "hue_drift": 0.004, "gamma": 1.15},
		"frame": func(p: Dictionary, f: Dictionary, mem: Dictionary) -> void:
			var t: float = f.t
			p.zoom = 1.012 + 0.012 * f.bass_att
			p.rot = 0.02 + 0.025 * f.bass_att + 0.04 * f.hit
			mem.ang = float(mem.get("ang", 0.0)) + 0.012 + 0.02 * f.mid_att
			p.wave_rot = mem.ang
			p.wave_color = _hsv(f.hue + 0.5 + 0.25 * sin(t * 0.17), 0.7, 1.0)
			p.wave_scale = 0.6 + 0.6 * f.mid
			p.hue = 0.08 * sin(t * 0.05),
	}


## A kaleidoscope: the picture folded into six mirrored segments, breathing in and out with the bass, a
## mirrored wave and a flipped echo laid over it.
static func _kaleido() -> Dictionary:
	return {
		"name": "Kaleidoscope",
		"base": {"fold": 1.0, "sides": 6, "decay": 0.965, "blur": 0.3, "warp": 0.45, "warp_speed": 0.7,
				"wave_mode": WAVE_MIRROR, "wave_thick": 2.5, "echo": 0.3, "echo_zoom": 1.35, "echo_orient": 1,
				"saturate": 1.25, "vignette": 0.3},
		"frame": func(p: Dictionary, f: Dictionary, _mem: Dictionary) -> void:
			var t: float = f.t
			p.zoom = 0.986 + 0.006 * sin(t * 0.4) + 0.008 * f.bass_att
			p.rot = 0.008 * sin(t * 0.23) + 0.01 * f.mid_att
			p.wave_y = 0.42 + 0.06 * sin(t * 0.31)
			p.wave_color = _hsv(f.hue + 0.15 * sin(t * 0.13) + 0.2 * f.treb_att, 0.85, 1.0)
			p.wave_scale = 0.5 + 0.3 * f.mid + 0.3 * f.hit
			p.hue_drift = 0.002 + 0.004 * f.treb_att,
	}


## Liquid: a strong slow wobble that pours the dots of the wave about like ink in water, stirred harder
## by the mids.
static func _liquid() -> Dictionary:
	return {
		"name": "Liquid",
		"base": {"zoom": 1.004, "decay": 0.972, "blur": 0.45, "warp_speed": 0.6, "warp_scale": 1.3,
				"wave_mode": WAVE_DOTS, "wave_thick": 4.0, "hue_drift": 0.004, "saturate": 1.2,
				"gamma": 1.1, "vignette": 0.25},
		"frame": func(p: Dictionary, f: Dictionary, _mem: Dictionary) -> void:
			var t: float = f.t
			p.warp = 2.0 + 1.5 * f.mid_att + 1.0 * f.hit
			p.zoom = 1.003 + 0.01 * f.bass_att
			p.dx = 0.0008 * sin(t * 0.11)
			p.wave_color = _hsv(f.hue + 0.45 + 0.1 * sin(t * 0.21), 0.6, 1.0)
			p.wave_y = 0.5 + 0.25 * sin(t * 0.17)
			p.wave_scale = 0.7 + 0.6 * f.bass,
	}


## A starburst: rays and a punch of zoom flash out of the centre on every hit, the colour flips for a
## moment, and between the hits a small ring of wave turns quietly.
static func _starburst() -> Dictionary:
	return {
		"name": "Starburst",
		"base": {"zoom_curve": 0.5, "decay": 0.9, "blur": 0.2, "warp": 0.15, "wave_mode": WAVE_CIRCLE,
				"wave_thick": 2.5, "wave_scale": 0.45, "shape_kind": SHAPE_RAYS, "shape_sides": 28,
				"shape_thick": 2.0, "hue_drift": 0.006, "gamma": 1.2, "saturate": 1.2},
		"frame": func(p: Dictionary, f: Dictionary, mem: Dictionary) -> void:
			var t: float = f.t
			if f.hit > 0.8 and float(mem.get("last", 0.0)) < 0.8:
				mem.spin = randf() * TAU
				mem.shift = fposmod(float(mem.get("shift", 0.0)) + 0.13, 1.0)
			mem.last = f.hit
			var shift: float = mem.get("shift", 0.0)
			p.zoom = 1.015 + 0.06 * f.hit + 0.01 * f.bass_att
			p.rot = 0.012 * sin(t * 0.3) + 0.02 * f.hit
			p.shape_rad = 0.15 + 0.6 * f.hit + 0.05 * sin(t)
			p.shape_alpha = 0.7 * f.hit * f.hit
			p.shape_ang = float(mem.get("spin", 0.0)) + t * 0.2
			p.shape_color = _hsv(f.hue + shift + 0.1, 0.8, 1.0)
			p.wave_color = _hsv(f.hue + shift, 0.8, 1.0)
			p.wave_rot = t * 0.4
			p.invert = 0.18 * maxf(f.hit - 0.75, 0.0) * 4.0
			p.bright = 1.0 + 0.4 * f.hit,
	}


## Nebula drift: slow ambient clouds. A soft, faint loop of wave wanders the whole screen, a long blur
## and a slow wobble turn its trail into smoke; the music only nudges it.
static func _drift() -> Dictionary:
	return {
		"name": "Nebula Drift",
		"base": {"zoom": 1.006, "decay": 0.984, "blur": 0.6, "warp": 1.3, "warp_speed": 0.35,
				"warp_scale": 0.9, "wave_mode": WAVE_XY, "wave_alpha": 0.4, "wave_thick": 4.0, "gamma": 1.1,
				"hue_drift": 0.0015, "saturate": 1.05, "vignette": 0.4},
		"frame": func(p: Dictionary, f: Dictionary, _mem: Dictionary) -> void:
			var t: float = f.t
			p.dx = 0.002 * sin(t * 0.13)
			p.dy = 0.0015 * cos(t * 0.11)
			p.rot = 0.003 * sin(t * 0.07)
			p.zoom = 1.005 + 0.008 * f.bass_att
			p.wave_x = 0.5 + 0.36 * sin(t * 0.31)
			p.wave_y = 0.5 + 0.34 * cos(t * 0.43)
			p.wave_rot = t * 0.2
			p.wave_scale = 0.9 + 0.4 * f.level
			p.wave_color = _hsv(f.hue + 0.25 * sin(t * 0.07), 0.6, 1.0)
			p.hue = 0.1 * sin(t * 0.03),
	}


## A radial bloom: the spectrum drawn as rays out of the middle, flowering outward on rings of ripple and
## mirrored back on itself by a four-way echo.
static func _bloom() -> Dictionary:
	return {
		"name": "Radial Bloom",
		"base": {"zoom": 1.03, "zoom_curve": 0.4, "ripple": 0.6, "ripple_freq": 18.0, "decay": 0.94,
				"blur": 0.3, "warp": 0.2, "wave_mode": WAVE_BLOOM, "wave_thick": 3.0, "hue_drift": 0.005,
				"echo": 0.25, "echo_zoom": 1.0, "echo_orient": 3, "gamma": 1.2, "saturate": 1.2},
		"frame": func(p: Dictionary, f: Dictionary, _mem: Dictionary) -> void:
			var t: float = f.t
			p.zoom = 1.02 + 0.03 * f.bass_att + 0.04 * f.hit
			p.ripple = 0.5 + 1.0 * f.bass_att
			p.rot = 0.01 * sin(t * 0.17)
			p.wave_rot = t * 0.15
			p.wave_scale = 0.8 + 0.5 * f.level
			p.wave_color = _hsv(f.hue + 0.6 + 0.2 * f.treb_att, 0.75, 1.0)
			p.bright = 1.0 + 0.25 * f.hit,
	}


## Strobe lines: a thick line through the middle stretched up and down into bars, the hue jumping on
## each hit and the picture flashing negative on the beat when the music is loud.
static func _strobe() -> Dictionary:
	return {
		"name": "Strobe Lines",
		"base": {"zoom": 1.0, "decay": 0.95, "blur": 0.15, "warp": 0.1, "wave_mode": WAVE_LINE,
				"wave_thick": 4.0, "gamma": 1.05, "saturate": 1.3, "vignette": 0.25, "hue_drift": 0.003},
		"frame": func(p: Dictionary, f: Dictionary, mem: Dictionary) -> void:
			var t: float = f.t
			if f.hit > 0.7 and float(mem.get("last", 0.0)) <= 0.7:
				mem.jump = fposmod(float(mem.get("jump", 0.0)) + 0.31, 1.0)
			mem.last = f.hit
			var jump: float = mem.get("jump", 0.0)
			p.sy = 1.018 + 0.02 * f.bass_att
			p.sx = 1.0 - 0.002 * sin(t * 0.3)
			p.wave_y = 0.5 + 0.05 * sin(t * 0.5)
			p.wave_rot = 0.05 * sin(t * 0.23)
			p.wave_color = _hsv(f.hue + jump, 0.9, 1.0)
			p.wave_scale = 0.35 + 0.15 * f.bass
			var flash := 1.0 - smoothstep(0.0, 0.12, float(f.beat_phase))
			p.invert = 0.35 * flash * clampf(f.level * 1.5 - 0.3, 0.0, 1.0)
			p.bright = 1.0 + 0.3 * flash * f.level
			p.hue = 0.03 * sin(t * 0.4),
	}


## A vortex: everything pours inward and turns as it goes, fed by a wide ring of wave and a spinning
## seven-sided frame near the edges; the bass spins it faster.
static func _vortex() -> Dictionary:
	return {
		"name": "Vortex",
		"base": {"zoom": 0.982, "zoom_curve": 0.3, "decay": 0.965, "blur": 0.25, "warp": 0.4,
				"wave_mode": WAVE_CIRCLE, "wave_thick": 3.0, "wave_rad": 0.46, "wave_scale": 0.7,
				"shape_kind": SHAPE_RING, "shape_sides": 7, "shape_rad": 0.62, "shape_thick": 3.0, "shape_alpha": 0.55,
				"hue_drift": 0.004, "gamma": 1.1, "saturate": 1.15},
		"frame": func(p: Dictionary, f: Dictionary, mem: Dictionary) -> void:
			var t: float = f.t
			mem.spin = float(mem.get("spin", 0.0)) + 0.015 + 0.04 * f.bass_att
			p.cx = 0.5 + 0.06 * sin(t * 0.21)
			p.cy = 0.5 + 0.06 * cos(t * 0.27)
			p.rot = 0.03 + 0.025 * f.bass_att + 0.03 * f.hit
			p.zoom = 0.982 - 0.015 * f.hit
			p.wave_x = p.cx
			p.wave_y = p.cy
			p.wave_rot = -mem.spin
			p.shape_x = p.cx
			p.shape_y = p.cy
			p.shape_ang = mem.spin
			p.shape_color = _hsv(f.hue + 0.5, 0.6, 1.0)
			p.wave_color = _hsv(f.hue + 0.1 * sin(t * 0.3), 0.85, 1.0)
			p.wave_scale = 0.6 + 0.3 * f.bass,
	}


## An echo hall: a mirrored pair of waves drifting, every frame laid over a doubled, upside-down copy of
## itself, so whatever plays is answered across the middle.
static func _echo_hall() -> Dictionary:
	return {
		"name": "Echo Hall",
		"base": {"zoom": 1.012, "decay": 0.94, "blur": 0.3, "warp": 1.0, "warp_speed": 0.8,
				"wave_mode": WAVE_MIRROR, "wave_thick": 3.0, "echo": 0.45, "echo_zoom": 1.8, "echo_orient": 2,
				"hue_drift": 0.005, "gamma": 1.15, "saturate": 1.1},
		"frame": func(p: Dictionary, f: Dictionary, _mem: Dictionary) -> void:
			var t: float = f.t
			p.zoom = 1.01 + 0.025 * f.bass_att
			p.warp = 0.8 + 1.2 * f.mid_att
			p.rot = 0.005 * sin(t * 0.19)
			p.wave_y = 0.3 + 0.1 * sin(t * 0.27)
			p.wave_scale = 0.6 + 0.4 * f.bass
			p.wave_color = _hsv(f.hue + 0.3 + 0.15 * sin(t * 0.09), 0.75, 1.0)
			p.echo_zoom = 1.8 + 0.4 * sin(t * 0.07)
			p.echo = 0.3 + 0.2 * f.hit,
	}
