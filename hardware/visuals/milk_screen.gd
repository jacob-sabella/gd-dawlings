class_name MilkScreen
extends Node3D

## A big glowing screen showing a MilkDrop-style picture that moves with the music (docs/visuals.md):
## a dark bezel round a quad of glass, and behind the glass two small 2D buffers that take turns.
##
## Each step, the buffer not shown last draws the other one back over itself warped a little (zoomed,
## turned, shifted, wobbled, faded: milk_warp.gdshader), then the wave of the music on top (and now and
## then a shape); the glass shows it through milk_comp.gdshader, which adds the echo, the gamma, a hue
## turn and the flashes. Done over and over, the warp drags each frame's wave into trails, tunnels and
## spirals. What it does each frame is a preset's (MilkPresets): base parameters and a function of the
## music; the screen moves on to another every half minute or so (sooner on a big hit, after 20 s),
## crossfading the parameters over two seconds.
##
## It costs nothing when not watched: each frame it asks VisualBudget whether it may run (by its distance
## from the eye, or not at all when off screen); when not, its buffers stop updating and the last picture
## stays on the glass. Far away it steps less often. With the visuals OFF it builds no buffers at all and
## is plain dark glass. Three or four draws a step: the warp, the ink, the glass.
##
## Clicked, the glass moves on to the next picture; the FIND key under its corner asks for the finder
## (`find_asked`, MilkFinderScreen), where a picture is chosen by name. Each change letters its name
## along the bottom of the glass for a moment. Only this machine's: the pictures are for the eye, not part of the song.

## How long one preset shows before the next, and the soonest a big hit may move it on (s).
const HOLD_SECONDS := 30.0
const HIT_SECONDS := 20.0
## A hit this strong (AudioFeatures.hit) counts as big.
const BIG_HIT := 0.9
const FADE_SECONDS := 2.0
## A wave from `set_wave` older than this (s) is stale: the screen goes back to the mix's own.
const WAVE_STALE := 0.5
## Points the wave is resampled to before it is drawn.
const WAVE_POINTS := 96

## Asks for the picture finder (the FIND key).
signal find_asked
## How long a picture's name stays lettered in the corner after it changes (s).
const NAME_SECONDS := 2.5
## The brightest the glass is drawn, and the light it throws scaled with it (the composite shaders' `peak`).
const PEAK := 0.5

const WARP_SHADER := preload("res://hardware/visuals/milk_warp.gdshader")
const COMP_SHADER := preload("res://hardware/visuals/milk_comp.gdshader")

var size := Vector2(2.8, 1.5)
## The room's mood colour: the glow, the wash on dark glass, and the hue most presets start from.
var tint := Color(0.45, 0.55, 1.0):
	set(v):
		tint = v
		_restyle()
## Where the music is read from; null is AudioFeatures.now(). A test sets its own.
var features: AudioFeatures = null
## The preset showing (or being faded to).
var preset_index := 0
## Whether presets move on by themselves.
var auto_advance := true
## A distance (m) to ask the budget with instead of the eye's, for a test or a screen whose distance is
## known some other way; negative (the default) measures from the active camera.
var eye_distance := -1.0

var _built := false
var _built_tier := -1
var _glass := MeshInstance3D.new()
var _comp: ShaderMaterial = null
var _glow := OmniLight3D.new()
var _notifier := VisibleOnScreenNotifier3D.new()
var _vp: Array[SubViewport] = []
var _warp: Array[ShaderMaterial] = []
var _ink: Array[Ink] = []
var _glow_ink: Array[Ink] = []
var _rect: Array[ColorRect] = []
## A file preset's warp materials, one per buffer, made for its shader.
var _file_mat: Array[ShaderMaterial] = []
var _file_shader: Shader = null
## A tiny buffer a newly chosen preset's warp shader is drawn into once, so it is compiled during the
## crossfade and not when it takes over.
var _warm: SubViewport = null
var _warm_rect: ColorRect = null
## The players of the preset showing and the one faded from (null for a built-in look).
var _player: MilkPlayer = null
## A file preset's own (MilkDrop 2) composite, on the glass instead of `_comp` while it plays.
var _md2_comp: ShaderMaterial = null
var _from_player: MilkPlayer = null
## Which buffer the next step draws into.
var _write := 0
var _buffer := Vector2i.ZERO
var _running := false
var _acc := 0.0
var _clock := 0.0
var _since_switch := 0.0
var _from := -1
var _fade := 1.0
var _mem := {}
var _from_mem := {}
var _params := {}
var _ext_wave := PackedFloat32Array()
var _ext_at := -1.0
var _power := 0.0
var _name: Label3D
var _name_left := 0.0
## The glass as a key (a click moves on) and the FIND key; null with the visuals OFF.
var glass_key: MilkKey
var find_key: MilkKey


## The 2D ink of one buffer: the waves, shapes and borders, drawn after the warp each step. Each buffer has
## two, one blended and one adding light (a MilkDrop preset's additive waves and shapes).
class Ink extends Node2D:
	## Each [points, colour, width, kind]: kind 0 a polyline, 1 dots, 2 separate segments, 3 a polyline and
	## 4 dots with a colour per point (colour is then a PackedColorArray).
	var strokes: Array = []
	## Filled triangles, three points (and colours) each: shapes and borders, one draw for all.
	var tri_points := PackedVector2Array()
	var tri_colors := PackedColorArray()
	## Triangles showing a texture (a textured shape: the last frame), each [texture, points, colours, uvs].
	var tex_tris: Array = []

	func clear() -> void:
		strokes.clear()
		tri_points.clear()
		tri_colors.clear()
		tex_tris.clear()

	func add_tri(a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color) -> void:
		tri_points.append_array([a, b, c])
		tri_colors.append_array([ca, cb, cc])

	func add_tex_tri(a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color,
			ua: Vector2, ub: Vector2, uc: Vector2, tex: Texture2D) -> void:
		if tex_tris.is_empty() or tex_tris[-1][0] != tex:
			tex_tris.append([tex, PackedVector2Array(), PackedColorArray(), PackedVector2Array()])
		var t: Array = tex_tris[-1]
		t[1].append_array([a, b, c])
		t[2].append_array([ca, cb, cc])
		t[3].append_array([ua, ub, uc])

	func _draw() -> void:
		var ci := get_canvas_item()
		if not tri_points.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci, _seq(tri_points.size()), tri_points, tri_colors)
		for t in tex_tris:
			var pts: PackedVector2Array = t[1]
			RenderingServer.canvas_item_add_triangle_array(ci, _seq(pts.size()), pts, t[2], t[3], [], [],
					(t[0] as Texture2D).get_rid())
		for s in strokes:
			var pts: PackedVector2Array = s[0]
			var c: Variant = s[1]
			var w: float = s[2]
			match int(s[3]):
				0:
					if pts.size() > 1:
						draw_polyline(pts, c, w, true)
				1:
					for v in pts:
						draw_rect(Rect2(v - Vector2(w, w) * 0.5, Vector2(w, w)), c)
				2:
					if pts.size() > 1:
						draw_multiline(pts, s[1], w)
				3:
					if pts.size() > 1:
						draw_polyline_colors(pts, s[1], w, true)
				4:
					var cols: PackedColorArray = s[1]
					for k in pts.size():
						if cols[k].a > 0.004:
							draw_rect(Rect2(pts[k] - Vector2(w, w) * 0.5, Vector2(w, w)), cols[k])

	static func _seq(n: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		out.resize(n)
		for i in n:
			out[i] = i
		return out


func _ready() -> void:
	build()


## Makes the bezel, the glass and (unless the visuals are OFF) the buffers. Safe to call again.
func build() -> void:
	var t := VisualBudget.tier()
	if _built and t == _built_tier:
		return
	if _built:
		_teardown()
	_built = true
	_built_tier = t
	var bezel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var rim := minf(size.x, size.y) * 0.05
	bm.size = Vector3(size.x + rim * 2.0, size.y + rim * 2.0, 0.04)
	bezel.mesh = bm
	bezel.position = Vector3(0, 0, -0.022)
	var bz := StandardMaterial3D.new()
	bz.albedo_color = Color(0.025, 0.025, 0.03)
	bz.roughness = 0.45
	bz.metallic = 0.6
	bezel.material_override = bz
	bezel.set_meta(&"milk", true)
	add_child(bezel)
	var quad := QuadMesh.new()
	quad.size = size
	_glass.mesh = quad
	_glass.position = Vector3(0, 0, 0.0)
	add_child(_glass)
	_glow.omni_range = maxf(size.x * 2.2, 1.0)
	_glow.light_energy = 0.0
	_glow.shadow_enabled = false
	_glow.position = Vector3(0, 0, maxf(size.x * 0.35, 0.2))
	add_child(_glow)
	_notifier.aabb = AABB(Vector3(-size.x * 0.5, -size.y * 0.5, -0.05), Vector3(size.x, size.y, 0.1))
	add_child(_notifier)
	if t == VisualBudget.Tier.OFF:
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.01, 0.012, 0.016)
		gm.roughness = 0.12
		gm.metallic = 0.3
		_glass.material_override = gm
	else:
		_build_buffers()
		_build_keys()
	_restyle()


## The glass, clickable for the next picture, the FIND key on the bezel's lower right, and the name in the corner.
func _build_keys() -> void:
	glass_key = MilkKey.new()
	glass_key.name = "GlassKey"
	glass_key.size = size
	glass_key.depth = 0.02
	glass_key.title_text = "VISUALIZER"
	glass_key.tip = "Click for the next picture. FIND, under the corner, chooses one by name."
	glass_key.says = func() -> String: return MilkLibrary.preset_name(preset_index)
	glass_key.position = Vector3(0, 0, 0.012)
	glass_key.pressed.connect(next_preset)
	add_child(glass_key)
	var rim := minf(size.x, size.y) * 0.05
	find_key = MilkKey.new()
	find_key.name = "FindKey"
	find_key.size = Vector2(maxf(size.x * 0.09, 0.12), maxf(rim * 1.4, 0.05))
	find_key.legend = "FIND"
	find_key.title_text = "VISUALIZER  FIND"
	find_key.tip = "Choose the picture by name, with a preview, and hold it."
	find_key.position = Vector3(size.x * 0.5 - find_key.size.x * 0.5 - rim, -size.y * 0.5 - rim - find_key.size.y * 0.5 + 0.004, 0.006)
	find_key.pressed.connect(func() -> void: find_asked.emit())
	add_child(find_key)
	_name = Label3D.new()
	_name.name = "PictureName"
	_name.font_size = 48
	_name.pixel_size = size.y * 0.055 / 48.0
	_name.position = Vector3(0, -size.y * 0.5 + size.y * 0.07, 0.004)
	_name.shaded = false
	_name.outline_size = 10
	# The outline has a colour of its own, which `modulate` does not fade: both go together (`_show_name`).
	_name.modulate = Color(1, 1, 1, 0)
	_name.outline_modulate = Color(0, 0, 0, 0)
	add_child(_name)


## The picture now on the glass (the buffer last written), for a preview elsewhere; null with no buffers.
func picture() -> Texture2D:
	return _vp[1 - _write].get_texture() if _vp.size() == 2 else null


func _teardown() -> void:
	for c in get_children():
		if c == _glass or c == _glow or c == _notifier:
			remove_child(c)
		else:
			c.queue_free()
	_vp.clear()
	_warp.clear()
	_ink.clear()
	_glow_ink.clear()
	_rect.clear()
	_file_mat.clear()
	_file_shader = null
	_warm = null
	_warm_rect = null
	_comp = null
	_md2_comp = null
	_running = false


func _build_buffers() -> void:
	var w: int = VisualBudget.pick(512, 256)
	_buffer = Vector2i(w, maxi(int(round(w * size.y / maxf(size.x, 0.01))), 16))
	for i in 2:
		var vp := SubViewport.new()
		vp.size = _buffer
		vp.disable_3d = true
		vp.transparent_bg = false
		# Float buffers: a slow fade in 8 bits climbs down in visible steps and never quite reaches black.
		vp.use_hdr_2d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		add_child(vp)
		var rect := ColorRect.new()
		rect.size = Vector2(_buffer)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = WARP_SHADER
		m.set_shader_parameter(&"aspect", float(_buffer.x) / _buffer.y)
		m.set_shader_parameter(&"texel", Vector2(1.0 / _buffer.x, 1.0 / _buffer.y))
		rect.material = m
		vp.add_child(rect)
		var ink := Ink.new()
		vp.add_child(ink)
		var glow := Ink.new()
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = add
		vp.add_child(glow)
		_vp.append(vp)
		_warp.append(m)
		_ink.append(ink)
		_glow_ink.append(glow)
		_rect.append(rect)
	_warm = SubViewport.new()
	_warm.size = Vector2i(8, 8)
	_warm.disable_3d = true
	_warm.use_hdr_2d = true
	_warm.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_warm)
	_warm_rect = ColorRect.new()
	_warm_rect.size = Vector2(8, 8)
	_warm.add_child(_warm_rect)
	# Each buffer warps the other's last picture.
	_warp[0].set_shader_parameter(&"prev", _vp[1].get_texture())
	_warp[1].set_shader_parameter(&"prev", _vp[0].get_texture())
	_comp = ShaderMaterial.new()
	_comp.shader = COMP_SHADER
	_comp.set_shader_parameter(&"buf", _vp[1].get_texture())
	_comp.set_shader_parameter(&"power", 0.0)
	_glass.material_override = _comp
	_write = 0


func _restyle() -> void:
	if not _built:
		return
	_glow.light_color = tint.lerp(Color.WHITE, 0.2)
	if _comp != null:
		_comp.set_shader_parameter(&"wash", Vector3(tint.r, tint.g, tint.b) * 0.025)


## The SubViewports behind the glass (none with the visuals OFF): for a test.
func buffers() -> Array[SubViewport]:
	return _vp


## Whether the budget let it run this frame.
func is_running() -> bool:
	return _running


## This frame's parameters, as last worked out: for a test.
func params() -> Dictionary:
	return _params


## Whether a crossfade between presets is under way.
func fading() -> bool:
	return _fade < 1.0


## A wave (-1..1, any count) to draw instead of the mix's own, from a SCOPE module; used while it keeps
## coming (each newer than WAVE_STALE).
func set_wave(w: PackedFloat32Array) -> void:
	_ext_wave = w
	_ext_at = Time.get_ticks_msec() / 1000.0


func next_preset() -> void:
	use_preset(preset_index + 1)


## Fades to preset `i` (wrapped into range) over FADE_SECONDS.
func use_preset(i: int) -> void:
	var n := MilkLibrary.count()
	i = posmod(i, n)
	_from = preset_index
	_from_mem = _mem
	_from_player = _player
	_mem = {}
	preset_index = i
	_player = MilkLibrary.player(i)
	_fade = 0.0 if _from != i else 1.0
	_since_switch = 0.0
	if _player != null:
		_warm_up(_player.shader)
	if _name != null:
		_name.text = MilkLibrary.preset_name(i).to_upper()
		_name_left = NAME_SECONDS


func _process(delta: float) -> void:
	if _name != null and _name_left > 0.0:
		_name_left = maxf(_name_left - delta, 0.0)
		var a := clampf(_name_left / 0.6, 0.0, 1.0)
		_name.modulate.a = a
		_name.outline_modulate.a = a
	if VisualBudget.tier() != _built_tier:
		build()
	if _vp.is_empty():
		return
	var d := _distance()
	var granted := VisualBudget.ask(self, d)
	if not granted:
		if _running:
			_running = false
			for vp in _vp:
				vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_running = true
	_acc += delta
	var step := 1.0 / VisualBudget.rate_hz(d)
	# A little slack, so a 60 Hz rate at a slightly fast frame still steps every frame.
	if _acc < step * 0.9:
		return
	var dt := minf(_acc, 0.25)
	_acc = 0.0
	step_frame(dt)


## Metres from the eye to the screen, or INF when it is not on screen (or there is no eye).
func _distance() -> float:
	if eye_distance >= 0.0:
		return eye_distance
	if not is_inside_tree() or not _notifier.is_on_screen():
		return INF
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return INF
	return cam.global_position.distance_to(global_position)


## One step of the picture, `delta` seconds after the last: the preset worked out, the buffers drawn.
## Called by _process when the budget allows; a test may call it straight.
func step_frame(delta: float) -> void:
	_clock += delta
	_since_switch += delta
	var a := features if features != null else AudioFeatures.now()
	var f := {
		"t": _clock, "bass": a.bass, "mid": a.mid, "treb": a.treb, "bass_att": a.bass_att,
		"mid_att": a.mid_att, "treb_att": a.treb_att, "hit": a.hit, "level": a.level,
		"beat_phase": a.beat_phase, "hue": tint.h,
	}
	if auto_advance and (_since_switch >= HOLD_SECONDS or (_since_switch >= HIT_SECONDS and a.hit >= BIG_HIT)):
		_advance_random()
	f["progress"] = clampf(_since_switch / HOLD_SECONDS, 0.0, 1.0)
	var old_mode := -1
	var k := 1.0
	if _fade < 1.0:
		_fade = minf(_fade + delta / FADE_SECONDS, 1.0)
		k = smoothstep(0.0, 1.0, _fade)
	# A file preset's warp is a shader of its own, so between it and anything else there is nothing to mix:
	# the old one plays the first half of the fade (while the new one's shader compiles), the new one the
	# second, taking over the old one's picture as it stands.
	if _player != null or (_fade < 1.0 and _from_player != null):
		var use_new := _fade >= 0.5 or _from < 0
		var pl := _player if use_new else _from_player
		if pl == null:
			var p0 := MilkPresets.evaluate(_builtin_of(preset_index if use_new else _from), f, _mem if use_new else _from_mem)
			_params = p0
			if not _vp.is_empty():
				_power = minf(_power + delta * 1.5, 1.0)
				_draw_step(p0, delta, a, -1, 1.0)
			return
		_params = pl.step(f, delta, float(maxi(_buffer.x, 1)) / maxi(_buffer.y, 1), _buffer)
		if not _vp.is_empty():
			_power = minf(_power + delta * 1.5, 1.0)
			_draw_file_step(pl, a)
		return
	var p := MilkPresets.evaluate(_builtin_of(preset_index), f, _mem)
	if _fade < 1.0:
		var q := MilkPresets.evaluate(_builtin_of(_from), f, _from_mem)
		if int(q["wave_mode"]) != int(p["wave_mode"]):
			old_mode = int(q["wave_mode"])
		p = MilkPresets.blend(q, p, k)
	_params = p
	if _vp.is_empty():
		return
	_power = minf(_power + delta * 1.5, 1.0)
	_draw_step(p, delta, a, old_mode, k)


## The built-in look to play for picture `i`: its own, or the first for a file that could not be read.
func _builtin_of(i: int) -> int:
	if i < 0:
		return 0
	return maxi(int(MilkLibrary.entry(i).builtin), 0)


func _advance_random() -> void:
	use_preset(MilkLibrary.pick_random(preset_index))


## Draws `shader` once into the tiny buffer, so its pipeline is compiled now rather than on the frame it
## takes over.
func _warm_up(shader: Shader) -> void:
	if _warm == null or shader == null or shader == _file_shader:
		return
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter(&"prev", _vp[0].get_texture())
	_warm_rect.material = m
	_warm.render_target_update_mode = SubViewport.UPDATE_ONCE


## One step of a file preset: its warp shader, its ink, MilkDrop's composite.
func _draw_file_step(pl: MilkPlayer, a: AudioFeatures) -> void:
	if _file_shader != pl.shader or _file_mat.size() != 2:
		_file_shader = pl.shader
		_file_mat.clear()
		for i in 2:
			var fm := ShaderMaterial.new()
			fm.shader = pl.shader
			fm.set_shader_parameter(&"prev", _vp[1 - i].get_texture())
			fm.set_shader_parameter(&"main_w", _vp[1 - i].get_texture())
			fm.set_shader_parameter(&"main_c", _vp[1 - i].get_texture())
			_file_mat.append(fm)
	var m := _file_mat[_write]
	_rect[_write].material = m
	pl.apply_warp(m, _buffer)
	var ink := _ink[_write]
	var glow := _glow_ink[_write]
	ink.clear()
	glow.clear()
	pl.draw(ink, glow, _buffer, _wave(a), a.bars, _vp[1 - _write].get_texture())
	ink.queue_redraw()
	glow.queue_redraw()
	_vp[_write].render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := pl.comp()
	_comp.set_shader_parameter(&"buf", _vp[_write].get_texture())
	_comp.set_shader_parameter(&"md", 1.0)
	_comp.set_shader_parameter(&"bright", float(c.gamma))
	_comp.set_shader_parameter(&"gamma", 1.0)
	_comp.set_shader_parameter(&"hue", 0.0)
	_comp.set_shader_parameter(&"saturate", 1.0)
	_comp.set_shader_parameter(&"echo", float(c.echo))
	_comp.set_shader_parameter(&"echo_zoom", float(c.echo_zoom))
	_comp.set_shader_parameter(&"echo_orient", int(c.echo_orient))
	_comp.set_shader_parameter(&"invert", float(c.invert))
	_comp.set_shader_parameter(&"solar", float(c.solar))
	_comp.set_shader_parameter(&"brighten", float(c.brighten))
	_comp.set_shader_parameter(&"darken", float(c.darken))
	_comp.set_shader_parameter(&"vignette", 0.0)
	_comp.set_shader_parameter(&"power", _power)
	if pl.comp_shader != null:
		if _md2_comp == null or _md2_comp.shader != pl.comp_shader:
			_md2_comp = ShaderMaterial.new()
			_md2_comp.shader = pl.comp_shader
		var t := _vp[_write].get_texture()
		_md2_comp.set_shader_parameter(&"main_w", t)
		_md2_comp.set_shader_parameter(&"main_c", t)
		_md2_comp.set_shader_parameter(&"power", _power)
		_md2_comp.set_shader_parameter(&"wash", _comp.get_shader_parameter(&"wash"))
		pl.apply_shared(_md2_comp, _buffer)
		_glass.material_override = _md2_comp
	elif _glass.material_override != _comp:
		_glass.material_override = _comp
	var wc := Color(float(pl.vars.get("wave_r", 1.0)), float(pl.vars.get("wave_g", 1.0)), float(pl.vars.get("wave_b", 1.0)))
	_glow.light_color = tint.lerp(wc, 0.6)
	_glow.light_energy = (0.25 + 0.6 * a.level + 0.4 * a.hit) * _power * PEAK
	_write = 1 - _write


func _draw_step(p: Dictionary, delta: float, a: AudioFeatures, old_mode: int, k: float) -> void:
	# The parameters are for a 60 Hz step; a slower one takes the same motion in fewer, bigger steps.
	var s := clampf(delta * 60.0, 0.25, 4.0)
	var m := _warp[_write]
	_rect[_write].material = m
	_glow_ink[_write].clear()
	_glow_ink[_write].queue_redraw()
	m.set_shader_parameter(&"time", _clock)
	m.set_shader_parameter(&"zoom", pow(maxf(float(p["zoom"]), 0.01), s))
	m.set_shader_parameter(&"zoom_curve", float(p["zoom_curve"]))
	m.set_shader_parameter(&"rot", float(p["rot"]) * s)
	m.set_shader_parameter(&"warp", float(p["warp"]) * sqrt(s))
	m.set_shader_parameter(&"warp_speed", float(p["warp_speed"]))
	m.set_shader_parameter(&"warp_scale", float(p["warp_scale"]))
	m.set_shader_parameter(&"center", Vector2(float(p["cx"]), float(p["cy"])))
	m.set_shader_parameter(&"shift", Vector2(float(p["dx"]), float(p["dy"])) * s)
	m.set_shader_parameter(&"stretch", Vector2(pow(float(p["sx"]), s), pow(float(p["sy"]), s)))
	m.set_shader_parameter(&"ripple", float(p["ripple"]))
	m.set_shader_parameter(&"ripple_freq", float(p["ripple_freq"]))
	m.set_shader_parameter(&"fold", float(p["fold"]))
	m.set_shader_parameter(&"sides", float(p["sides"]))
	m.set_shader_parameter(&"wrap", float(p["wrap"]))
	m.set_shader_parameter(&"blur", float(p["blur"]))
	m.set_shader_parameter(&"hue_drift", float(p["hue_drift"]) * s)
	m.set_shader_parameter(&"decay", pow(clampf(float(p["decay"]), 0.0, 1.0), s))

	var ink := _ink[_write]
	ink.clear()
	var wave := _wave(a)
	if old_mode >= 0:
		_ink_wave(ink, p, wave, a, old_mode, 1.0 - k)
		_ink_wave(ink, p, wave, a, int(p["wave_mode"]), k)
	else:
		_ink_wave(ink, p, wave, a, int(p["wave_mode"]), 1.0)
	_ink_shape(ink, p)
	ink.queue_redraw()

	_vp[_write].render_target_update_mode = SubViewport.UPDATE_ONCE
	_comp.set_shader_parameter(&"buf", _vp[_write].get_texture())
	if _glass.material_override != _comp:
		_glass.material_override = _comp
	_comp.set_shader_parameter(&"md", 0.0)
	_comp.set_shader_parameter(&"brighten", 0.0)
	_comp.set_shader_parameter(&"darken", 0.0)
	_comp.set_shader_parameter(&"gamma", float(p["gamma"]))
	_comp.set_shader_parameter(&"bright", float(p["bright"]))
	_comp.set_shader_parameter(&"hue", float(p["hue"]))
	_comp.set_shader_parameter(&"saturate", float(p["saturate"]))
	_comp.set_shader_parameter(&"echo", float(p["echo"]))
	_comp.set_shader_parameter(&"echo_zoom", float(p["echo_zoom"]))
	_comp.set_shader_parameter(&"echo_orient", int(p["echo_orient"]))
	_comp.set_shader_parameter(&"invert", clampf(float(p["invert"]), 0.0, 1.0))
	_comp.set_shader_parameter(&"solar", clampf(float(p["solar"]), 0.0, 1.0))
	_comp.set_shader_parameter(&"vignette", float(p["vignette"]))
	_comp.set_shader_parameter(&"power", _power)
	var wc: Color = p["wave_color"]
	_glow.light_color = tint.lerp(wc, 0.6)
	_glow.light_energy = (0.25 + 0.6 * a.level + 0.4 * a.hit) * _power * PEAK
	_write = 1 - _write


## The wave as it would be drawn now: for a test.
func current_wave() -> PackedFloat32Array:
	return _wave(features if features != null else AudioFeatures.now())


## The wave to draw, WAVE_POINTS long: the SCOPE's while it is fresh, else the mix's; under silence a
## slow made-up swell, so a quiet room still has something moving on its screen.
func _wave(a: AudioFeatures) -> PackedFloat32Array:
	var src := a.wave
	if not _ext_wave.is_empty() and Time.get_ticks_msec() / 1000.0 - _ext_at < WAVE_STALE:
		src = _ext_wave
	var out := PackedFloat32Array()
	out.resize(WAVE_POINTS)
	var n := src.size()
	var peak := 0.0
	for i in WAVE_POINTS:
		var v := 0.0
		if n > 0:
			var x := float(i) / (WAVE_POINTS - 1) * (n - 1)
			var j := int(x)
			v = lerpf(src[j], src[mini(j + 1, n - 1)], x - j)
		out[i] = v
		peak = maxf(peak, absf(v))
	var idle := 1.0 - clampf(peak * 5.0, 0.0, 1.0)
	if idle > 0.0:
		for i in WAVE_POINTS:
			var u := float(i) / (WAVE_POINTS - 1)
			out[i] += idle * (0.22 * sin(u * TAU * 2.0 + _clock * 1.3) + 0.12 * sin(u * TAU * 5.0 - _clock * 2.1))
	# A light smoothing: MilkDrop-ish waves read better a little rounded.
	for i in range(1, WAVE_POINTS - 1):
		out[i] = out[i] * 0.5 + (out[i - 1] + out[i + 1]) * 0.25
	return out


func _ink_wave(ink: Ink, p: Dictionary, w: PackedFloat32Array, a: AudioFeatures, mode: int, alpha: float) -> void:
	var W := float(_buffer.x)
	var H := float(_buffer.y)
	var c: Color = p["wave_color"]
	c.a = clampf(float(p["wave_alpha"]) * alpha, 0.0, 1.0)
	if c.a <= 0.01:
		return
	var px := W / 512.0
	var thick := float(p["wave_thick"]) * px
	# However hard the bass pushes, the wave stays on the screen.
	var scale := minf(float(p["wave_scale"]), 1.8)
	var centre := Vector2(float(p["wave_x"]) * W, float(p["wave_y"]) * H)
	var rot := float(p["wave_rot"])
	var n := w.size()
	match mode:
		MilkPresets.WAVE_LINE, MilkPresets.WAVE_DOTS:
			var pts := PackedVector2Array()
			pts.resize(n)
			for i in n:
				var v := Vector2((float(i) / (n - 1) - 0.5) * W * 1.1, -w[i] * H * 0.3 * scale)
				pts[i] = centre + v.rotated(rot)
			ink.strokes.append([pts, c, thick * (1.6 if mode == MilkPresets.WAVE_DOTS else 1.0), 1 if mode == MilkPresets.WAVE_DOTS else 0])
		MilkPresets.WAVE_MIRROR:
			for side in [-1.0, 1.0]:
				var pts := PackedVector2Array()
				pts.resize(n)
				for i in n:
					var v := Vector2((float(i) / (n - 1) - 0.5) * W * 1.1, side * (H * 0.18 + w[i] * H * 0.22 * scale))
					pts[i] = Vector2(W * 0.5, H * 0.5) + Vector2(v.x * side, v.y + (centre.y - H * 0.5) * side).rotated(rot)
				ink.strokes.append([pts, c, thick, 0])
		MilkPresets.WAVE_CIRCLE:
			var pts := PackedVector2Array()
			pts.resize(n + 1)
			var r0 := H * float(p["wave_rad"])
			for i in n + 1:
				var j := i % n
				# The ends of the wave pulled together, so the loop closes without a step.
				var u := float(j) / n
				var v := lerpf(w[j], w[0], clampf(float(j - (n - 12)) / 12.0, 0.0, 1.0))
				var r := r0 * (1.0 + v * 0.55 * scale) * (0.6 + 0.4 * scale)
				var ang := u * TAU + rot
				pts[i] = centre + Vector2(cos(ang), sin(ang)) * r
			ink.strokes.append([pts, c, thick, 0])
		MilkPresets.WAVE_XY:
			var pts := PackedVector2Array()
			pts.resize(n)
			# One against itself a little later: a loop for a tone, a tangle for a mix (and an ellipse for the
			# idle swell, whose first part turns a quarter in an eighth of the wave).
			var q := n / 8
			for i in n:
				var v := Vector2(w[i], w[(i + q) % n]) * H * 0.7 * scale
				pts[i] = centre + v.rotated(rot)
			ink.strokes.append([pts, c, thick, 0])
		MilkPresets.WAVE_BLOOM:
			var bars := a.bars
			var nb := bars.size()
			var segs := PackedVector2Array()
			var r0 := H * 0.06
			for i in nb * 2:
				var b := bars[i % nb] if nb > 0 else 0.0
				# A little life at rest, so silence still shows a flower.
				b = maxf(b, 0.18 + 0.12 * sin(float(i) * 0.9 + _clock * 1.7))
				var ang := float(i) / (nb * 2) * TAU + rot
				var dir := Vector2(cos(ang), sin(ang))
				segs.append(centre + dir * r0)
				segs.append(centre + dir * (r0 + b * H * 0.38 * scale))
			ink.strokes.append([segs, c, thick, 2])


func _ink_shape(ink: Ink, p: Dictionary) -> void:
	var kind := int(p["shape_kind"])
	var c: Color = p["shape_color"]
	c.a = clampf(float(p["shape_alpha"]), 0.0, 1.0)
	if kind == MilkPresets.SHAPE_NONE or c.a <= 0.01:
		return
	var W := float(_buffer.x)
	var H := float(_buffer.y)
	var centre := Vector2(float(p["shape_x"]) * W, float(p["shape_y"]) * H)
	var r := float(p["shape_rad"]) * H
	var sides := maxi(int(p["shape_sides"]), 3)
	var ang0 := float(p["shape_ang"])
	var thick := float(p["shape_thick"]) * W / 512.0
	if kind == MilkPresets.SHAPE_RING:
		var pts := PackedVector2Array()
		for i in sides + 1:
			var ang := ang0 + float(i) / sides * TAU
			pts.append(centre + Vector2(cos(ang), sin(ang)) * r)
		ink.strokes.append([pts, c, thick, 0])
	else:
		var segs := PackedVector2Array()
		for i in sides:
			var ang := ang0 + float(i) / sides * TAU
			var dir := Vector2(cos(ang), sin(ang))
			segs.append(centre + dir * r * 0.15)
			segs.append(centre + dir * r * (0.7 + 0.3 * float(i % 2)))
		ink.strokes.append([segs, c, thick, 2])


## A key on the screen: the glass itself (no cap, a click moves on) or a small lettered one (FIND).
class MilkKey extends ControlAffordance:
	signal pressed
	var size := Vector2(0.12, 0.05)
	var depth := 0.012
	var legend := ""
	var title_text := "VISUALIZER"
	var tip := ""
	var says := Callable()

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, depth)
		shape.shape = box
		add_child(shape)
		if legend == "":
			return
		var cap := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(size.x, size.y, 0.008)
		cap.mesh = slab
		var paint := StandardMaterial3D.new()
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		paint.albedo_color = Color(0.13, 0.14, 0.17)
		cap.material_override = paint
		add_child(cap)
		var word := Label3D.new()
		word.text = legend
		word.font_size = 40
		word.pixel_size = size.y * 0.5 / 40.0
		word.position.z = 0.0045
		word.shaded = false
		word.modulate = Color(0.95, 0.9, 0.75)
		add_child(word)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return title_text

	func _default_readout() -> String:
		return String(says.call()) if says.is_valid() else ""

	func hint() -> String:
		return tip

	func _on_grab_begin(_at: Vector3) -> void:
		pressed.emit()
