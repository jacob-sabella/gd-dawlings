class_name PluginTablet
extends Surface

## One plugin, torn off the rack: a tablet of its own, laid out from the plugin's parameters.
##
## The rack shows eight knobs per unit because a rack unit is two inches tall. A plugin worth
## tearing off is one somebody is working on, and this is the face for that: twelve named knobs
## a page, the plugin's own preset list, and the four things a rack unit has no room for --
##
##   MIX       the plugin's own wet/dry, which every plugin in Reaper has whether or not it
##             has a mix knob of its own.
##   KEY IN    a sidechain: which track the plugin hears on its key input (3/4). Scroll to a
##             track, click to patch it; click the one that is patched to pull it.
##   CHAIN     where the plugin sits on its track, and two buttons to move it up and down.
##   MOVE TO   another track. Click to move it there; the tablet goes with it.
##
## TWO FACES. The knobs are the tablet's own reading of the plugin: every parameter by name, a
## section a page. UI turns the tablet over to the plugin's own window, as its maker drew it,
## live, with the pointer passed back into it -- for what parameters never say, a preset browser
## or a tuner, and for anyone who knows the plugin by its face. The footer stays on both: MIX,
## KEY IN, CHAIN and MOVE TO are the host's, and no plugin's window has them. Only on the host,
## where the window is (DAW.shows_plugin_windows).
##
## The UI face is on (`window_face`) wherever the DAW's plugin windows can be read: the helper
## (native/plugin_view.c) reparents the plugin's window into one of its own far off every screen,
## as Reaper docks a window into its FX chain, so it never lands on the desktop while shown.
##
## THE TABLET FOLLOWS ITS PLUGIN, not a slot. Moving a plugin renumbers its chain, and on Reaper
## the new numbering arrives later than the move. So the tablet keeps the plugin's name and the
## slot it expects, and after any change to the chain it looks for the plugin again: where it
## asked it to go first, then anywhere on the track, then anywhere at all. A tablet that stayed
## on slot 2 after its compressor moved to slot 1 would turn the EQ that slid into its place.
##
## A Surface like the others, so it knows nothing of who is looking or where it stands: the
## studio puts it on a stand and keeps the list of torn-off plugins. See scenes/studio.gd.

## Asked for by the DOCK button. The studio takes the tablet and its stand away.
signal dock_requested()
## The UI face was turned on or off: a viewer on a monitor is brought up to it.
signal window_shown(on: bool)

const WIDTH := 0.32
const HEIGHT := 0.30
const DEPTH := 0.012
const COLUMNS := 4
const ROWS := 3
const PER_PAGE := COLUMNS * ROWS
const KNOB_PITCH := Vector2(0.074, 0.048)
## The first row of knobs, from the top edge.
const GRID_TOP := HEIGHT * 0.5 - 0.098
## The footer's controls, from the bottom edge, and the rule over them.
const FOOTER_Y := -HEIGHT * 0.5 + 0.035
const FOOTER_RULE := -HEIGHT * 0.5 + 0.070
const CAPTION_DROP := 0.017
const CAPTION_SIZE := 38
## How long after asking for a reading before asking again. See RackUnit.TEXT_ASK_MSEC.
const TEXT_ASK_MSEC := 150
## How often the page on show is read again. OSC streams only a plugin's first 32 parameters;
## everything past them is only as fresh as the last read, and a plugin's own GUI or automation
## can move them at any time.
const PAGE_READ_MSEC := 700
## A plugin's own preset buttons, exposed as parameters. Neural DSP's presets live inside the
## plugin, where Reaper cannot list them, and these are how the plugin lets a host step them.
const PRESET_NEXT := "Preset Next"
const PRESET_PREVIOUS := "Preset Previous"

## Whether tablets offer the UI face at all.
static var window_face := true
## How much bigger the tablet grows while it shows a plugin's own window: the knobs are
## readable at 0.32 m, a plugin's drawing of its own is not.
const WINDOW_SCALE := 2.4

var track_index := 1
var fx_index := 0
## The plugin's name, which is how the tablet finds it again after the chain moves.
var fx_name := ""
var page_offset := 0
## True while the plugin cannot be found anywhere: deleted in Reaper, or the project closed.
var lost := false
## Showing the plugin's own window rather than the knobs.
var showing_window := false
## 0 at rest, 1 grown to WINDOW_SCALE. It grows from its bottom edge, so the stand keeps holding it.
var _grown := 0.0
## Off where the viewer walks up to the tablet instead (a monitor); see studio._build_tablet.
var grows_with_window := true
var _resting := Transform3D.IDENTITY

var _knobs: Array[Knob] = []
var _captions: Array[Label3D] = []
var _bypass: PanelButton
var _mix: Knob
var _mix_label: Label3D
var _title: Label3D
var _subtitle: Label3D
var _chip_material := StandardMaterial3D.new()
var _preset_label: Label3D
var _page_label: Label3D
var _preset_prev: PanelButton
var _preset_next: PanelButton
var _page_prev: PanelButton
var _page_next: PanelButton
var _chain_label: Label3D
var _chain_up: PanelButton
var _chain_down: PanelButton
var _key: TabletSelector
var _move_to: TabletSelector
var _lost_label: Label3D
var _preset_word: Label3D
var _window_button: PanelButton
var _window_word: Label3D
var _screen: PluginScreen
var _window: PluginWindow
## The plugin the window was opened for, [track, fx]: a plugin that moves is a different window.
var _window_for: Array = []
var _built_shape := ""
var _text_asked_msec := 0
## Where the tablet asked its plugin to go, until the chain says it got there: [track, fx].
var _expect: Array = []
## The plugin whose parameter list was last asked for, so it is asked once and not per rebuild.
var _listed := ""
var _page_read_msec := 0
var _starts: Array = [0]
var _starts_for := ""


static func create(track: int, fx: int, plugin_name: String) -> PluginTablet:
	var t := PluginTablet.new()
	t.track_index = track
	t.fx_index = fx
	t.fx_name = MixState.FXState.bare_name(plugin_name)
	t.surface_kind = &"plugin"
	t.name = "Tablet_%s" % plugin_name.validate_node_name()
	return t


func _ready() -> void:
	super()
	DAW.track_changed.connect(_on_track_changed)
	DAW.tracks_renumbered.connect(_on_tracks_renumbered)


func _exit_tree() -> void:
	_close_window()


# --- finding the plugin ---------------------------------------------------------------------

func fx() -> MixState.FXState:
	return DAW.state.fx(track_index, fx_index, false) if DAW.state.tracks.has(track_index) else null


## Point at the plugin again after the chain has changed. True when it is found.
func find_plugin() -> bool:
	var here := fx()
	if here != null and here.name == fx_name:
		lost = false
		return true
	var tracks: Array = DAW.state.track_indices()
	# Where it was sent first, then its own track, then everywhere.
	var order: Array = []
	if not _expect.is_empty():
		order.append(int(_expect[0]))
	order.append(track_index)
	order.append_array(tracks)
	for t in order:
		if not DAW.state.tracks.has(t):
			continue
		var found := -1
		for i in DAW.state.track(t).plugins():
			if DAW.state.fx(t, i).name == fx_name:
				found = i
				# The last match on the track it was sent to: a move lands at the end, and a
				# copy of the same plugin may already be sitting earlier in that chain.
				if _expect.is_empty() or int(_expect[0]) != t:
					break
		if found >= 0:
			track_index = t
			fx_index = found
			lost = false
			return true
	lost = true
	return false


# --- building -------------------------------------------------------------------------------

func _shape_key() -> String:
	var count := _params().size()
	return "%s|%d|%d|%d|%s|%s" % [fx_name, count, page_offset, track_index, lost, showing_window]


## Looked at once a frame: Reaper names a thousand plugins in one refresh, and finding this
## one again is a walk through all of them.
func _on_fx_shape_changed(_t: int, _fx: int) -> void:
	_once_this_frame(_check_plugin)


func _check_plugin() -> void:
	var was := [track_index, fx_index]
	find_plugin()
	if [track_index, fx_index] != was or _shape_key() != _built_shape:
		mark_dirty()
	else:
		refresh()


## Its track moved: followed by number, not found again by name, because another track may well
## have a plugin of the same name. A track that is gone leaves the name to search everywhere.
func _on_tracks_renumbered(map: Dictionary) -> void:
	track_index = int(map.get(track_index, 0))
	_check_plugin()


func _on_track_changed(_index: int, field: StringName) -> void:
	# A key patched or pulled anywhere is a send on the track doing the keying; names and
	# colours are the title strip's.
	if field in [&"sends", &"name", &"colour"]:
		_once_this_frame(refresh)


func _rebuild() -> void:
	_clear_built()
	find_plugin()
	_ask_for_list()
	_built_shape = _shape_key()
	_knobs.clear()
	_captions.clear()
	_build_body()
	_build_header()
	if showing_window and not lost:
		_build_screen()
	else:
		_build_grid()
	_build_footer()
	refresh()


func _build_body() -> void:
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, HEIGHT, DEPTH)
	shell.mesh = box
	shell.position.z = -DEPTH * 0.5
	shell.material_override = Materials.brushed_metal()
	_adopt(shell)

	var face := MeshInstance3D.new()
	face.name = "Face"
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH - 0.014, HEIGHT - 0.014)
	face.mesh = quad
	face.position.z = 0.0004
	face.material_override = Materials.chassis()
	_adopt(face)

	# A hairline under the header and over the footer, so the three parts read as three.
	for y in [HEIGHT * 0.5 - 0.050, FOOTER_RULE]:
		var rule := MeshInstance3D.new()
		var line := BoxMesh.new()
		line.size = Vector3(WIDTH - 0.04, 0.0008, 0.0008)
		rule.mesh = line
		rule.position = Vector3(0, y, 0.001)
		rule.material_override = Materials.cap_plastic(Color(0.32, 0.33, 0.35))
		_adopt(rule)


func _label(text: String, size: int, at: Vector3, colour := Color(0.82, 0.83, 0.86),
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0002
	l.position = at
	l.horizontal_alignment = align
	l.modulate = colour
	Lettering.range_to_legibility(l)
	_adopt(l)
	return l


func _button(at: Vector3, colour: Color, describe: String, on_press: Callable) -> PanelButton:
	var b := PanelButton.new()
	b.position = at
	b.led_colour = colour
	b.hit_pad = Vector2(1.6, 1.8)
	b.describe_title = func() -> String: return "%s  %s" % [_caption(), describe]
	b.pressed.connect(on_press)
	_adopt(b)
	return b


func _build_header() -> void:
	var top := HEIGHT * 0.5
	var chip := MeshInstance3D.new()
	chip.name = "Chip"
	var bar := QuadMesh.new()
	bar.size = Vector2(0.007, 0.03)
	chip.mesh = bar
	chip.position = Vector3(-WIDTH * 0.5 + 0.018, top - 0.026, 0.001)
	_chip_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chip.material_override = _chip_material
	_adopt(chip)

	_title = _label("", 72, Vector3(-WIDTH * 0.5 + 0.028, top - 0.019, 0.001),
			Color(0.95, 0.94, 0.90), HORIZONTAL_ALIGNMENT_LEFT)
	_title.name = "Title"
	_subtitle = _label("", 40, Vector3(-WIDTH * 0.5 + 0.028, top - 0.037, 0.001),
			Color(0.62, 0.65, 0.70), HORIZONTAL_ALIGNMENT_LEFT)
	_subtitle.name = "Subtitle"

	_bypass = _button(Vector3(WIDTH * 0.5 - 0.024, top - 0.024, 0.004), Color(0.4, 0.95, 0.5),
			"POWER", func(): _act(func(): DAW.set_fx_enabled(track_index, fx_index, not fx().enabled)))
	_bypass.name = "Power"
	_bypass.describe_value = func(_v: float) -> String: return "ACTIVE" if _bypass.lit else "BYPASSED"
	_label("POWER", 30, Vector3(WIDTH * 0.5 - 0.024, top - 0.037, 0.001), Color(0.55, 0.58, 0.62))

	var dock := _button(Vector3(WIDTH * 0.5 - 0.056, top - 0.024, 0.004), Color(0.75, 0.78, 0.85),
			"BACK TO THE RACK", func(): dock_requested.emit())
	dock.name = "Dock"
	dock.describe_value = func(_v: float) -> String: return "click to put the tablet away"
	_label("DOCK", 30, Vector3(WIDTH * 0.5 - 0.056, top - 0.037, 0.001), Color(0.55, 0.58, 0.62))

	_window_button = _button(Vector3(WIDTH * 0.5 - 0.088, top - 0.024, 0.004), Color(0.55, 0.85, 0.95),
			"THE PLUGIN'S OWN WINDOW", func(): _act(func(): show_window(not showing_window)))
	_window_button.name = "Window"
	_window_button.describe_value = func(_v: float) -> String:
		return "showing it  ·  click for the knobs" if showing_window else "click to show it here"
	_window_word = _label("UI", 30, Vector3(WIDTH * 0.5 - 0.088, top - 0.037, 0.001),
			Color(0.55, 0.58, 0.62))

	# Presets on the left of the second line, pages on the right.
	var y := top - 0.064
	_preset_word = _label("PRESET", 30, Vector3(-WIDTH * 0.5 + 0.03, y + 0.001, 0.001),
			Color(0.55, 0.58, 0.62))
	_preset_prev = _button(Vector3(-WIDTH * 0.5 + 0.058, y, 0.004), Color(0.95, 0.75, 0.35),
			"PREVIOUS PRESET", func(): _act(func(): _step_preset(-1)))
	_preset_next = _button(Vector3(-WIDTH * 0.5 + 0.078, y, 0.004), Color(0.95, 0.75, 0.35),
			"NEXT PRESET", func(): _act(func(): _step_preset(1)))
	_preset_label = _label("", 44, Vector3(-WIDTH * 0.5 + 0.092, y, 0.001), Color(0.98, 0.86, 0.6),
			HORIZONTAL_ALIGNMENT_LEFT)
	_preset_label.name = "Preset"
	for b in [_preset_prev, _preset_next]:
		(b as PanelButton).describe_value = func(_v: float) -> String: return _preset_label.text
	_preset_prev.lit = true
	_preset_next.lit = true

	_page_label = _label("", 38, Vector3(WIDTH * 0.5 - 0.072, y, 0.001), Color(0.62, 0.65, 0.70),
			HORIZONTAL_ALIGNMENT_RIGHT)
	_page_prev = _button(Vector3(WIDTH * 0.5 - 0.056, y, 0.004), Color(0.45, 0.68, 0.95),
			"PREVIOUS PAGE", func(): _step_page(-1))
	_page_next = _button(Vector3(WIDTH * 0.5 - 0.036, y, 0.004), Color(0.45, 0.68, 0.95),
			"NEXT PAGE", func(): _step_page(1))
	for b in [_page_prev, _page_next]:
		(b as PanelButton).describe_value = func(_v: float) -> String: return _page_label.text


func _build_grid() -> void:
	var count := _params().size()
	var shown := mini(_page_size(), count)
	var left := -KNOB_PITCH.x * (COLUMNS - 1) * 0.5
	for slot in shown:
		var at := Vector3(left + (slot % COLUMNS) * KNOB_PITCH.x,
				GRID_TOP - int(slot / COLUMNS) * KNOB_PITCH.y, 0.005)
		var k := Knob.new()
		k.name = "Knob%d" % slot
		k.position = at
		k.turned.connect(func(v: float):
			var param := _param_for(slot)
			if param >= 0:
				DAW.set_fx_param(track_index, fx_index, param, v))
		k.describe_title = func() -> String: return "%s  %s" % [_caption(), _param_name(slot)]
		k.describe_value = func(v: float) -> String: return _param_reading(slot, v)
		_adopt(k)
		_knobs.append(k)
		var caption := _label("", CAPTION_SIZE, at + Vector3(0, -CAPTION_DROP, -0.004),
				Color(0.70, 0.72, 0.75))
		caption.name = "Caption%d" % slot
		_captions.append(caption)

	_lost_label = _label("PLUGIN NOT FOUND", 64, Vector3(0, 0, 0.002), Color(0.95, 0.55, 0.45))
	_lost_label.name = "Lost"
	_lost_label.visible = lost


func _build_footer() -> void:
	var y := FOOTER_Y
	var head := y + 0.021
	var muted := Color(0.55, 0.58, 0.62)

	# MIX: the plugin's own wet/dry.
	_mix = Knob.new()
	_mix.name = "Mix"
	_mix.position = Vector3(-WIDTH * 0.5 + 0.034, y - 0.002, 0.005)
	_mix.turned.connect(func(v: float): _act(func(): DAW.set_fx_wet(track_index, fx_index, v)))
	_mix.describe_title = func() -> String: return "%s  MIX" % _caption()
	_mix.describe_value = func(v: float) -> String:
		return "%d%% wet" % roundi(v * 100.0) if v < 0.995 else "all plugin"
	_adopt(_mix)
	_label("MIX", 30, Vector3(-WIDTH * 0.5 + 0.034, head, 0.001), muted)
	_mix_label = _label("", 32, Vector3(-WIDTH * 0.5 + 0.053, y - 0.002, 0.001),
			Color(0.82, 0.83, 0.86), HORIZONTAL_ALIGNMENT_LEFT)
	_mix_label.name = "MixReading"

	# KEY IN: which track the plugin hears on its sidechain.
	_label("KEY IN", 30, Vector3(-0.044, head, 0.001), muted)
	_key = TabletSelector.new()
	_key.name = "KeyIn"
	_key.size = Vector2(0.066, 0.017)
	_key.position = Vector3(-0.044, y, 0.001)
	_key.options = _other_tracks
	_key.hint_text = "scroll to pick a track  ·  click to key the plugin from it, or to pull it"
	_key.describe_title = func() -> String: return "%s  KEY IN" % _caption()
	_key.describe_value = func(_v: float) -> String:
		return ("%s keys it" if _key.lit else "%s  (click to key)") % _key.words()
	_key.pressed.connect(_on_key_pressed)
	_adopt(_key)
	# Which track keys it now, picked out in the window from the start.
	var keyed := keyed_by()
	if not keyed.is_empty():
		_key.choice = keyed[0]

	# CHAIN: where it sits on its track.
	_label("CHAIN", 30, Vector3(0.041, head, 0.001), muted)
	_chain_up = _button(Vector3(0.017, y, 0.004), Color(0.45, 0.68, 0.95), "EARLIER IN THE CHAIN",
			func(): _shift(-1))
	_chain_down = _button(Vector3(0.065, y, 0.004), Color(0.45, 0.68, 0.95), "LATER IN THE CHAIN",
			func(): _shift(1))
	_chain_label = _label("", 36, Vector3(0.041, y - 0.0005, 0.001), Color(0.82, 0.83, 0.86))
	_chain_label.name = "Chain"
	for b in [_chain_up, _chain_down]:
		(b as PanelButton).describe_value = func(_v: float) -> String: return _chain_words()

	# MOVE TO: another track.
	_label("MOVE TO", 30, Vector3(0.117, head, 0.001), muted)
	_move_to = TabletSelector.new()
	_move_to.name = "MoveTo"
	_move_to.size = Vector2(0.064, 0.017)
	_move_to.position = Vector3(0.117, y, 0.001)
	_move_to.options = _other_tracks
	_move_to.hint_text = "scroll to pick a track  ·  click to move the plugin there"
	_move_to.describe_title = func() -> String: return "%s  MOVE TO" % _caption()
	_move_to.describe_value = func(_v: float) -> String: return "%s  (click to move)" % _move_to.words()
	_move_to.pressed.connect(func(to: int): move_to_track(to))
	_adopt(_move_to)


## The plugin's own window, between the header and the footer, where the knobs were.
func _build_screen() -> void:
	var top := HEIGHT * 0.5 - 0.050
	_screen = PluginScreen.new()
	_screen.name = "Screen"
	_screen.size = Vector2(WIDTH - 0.03, top - FOOTER_RULE - 0.012)
	_screen.position = Vector3(0, (top + FOOTER_RULE) * 0.5, 0.001)
	_screen.window = _window
	_screen.describe_title = func() -> String: return "%s  OWN WINDOW" % _caption()
	_adopt(_screen)
	_lost_label = _label("PLUGIN NOT FOUND", 64, Vector3(0, 0, 0.002), Color(0.95, 0.55, 0.45))
	_lost_label.name = "Lost"
	_lost_label.visible = lost


# --- the plugin's own window ----------------------------------------------------------------

## Turn the tablet over to the plugin's own window (true) or back to the knobs. Nothing where
## the window cannot be shown: on a guest, or a DAW that cannot.
func show_window(on: bool) -> void:
	if on == showing_window:
		return
	if on:
		if lost or not _windows_here():
			return
		_open_window()
		if _window == null:
			return
	else:
		_close_window()
	showing_window = on
	window_shown.emit(on)
	mark_dirty()


func _windows_here() -> bool:
	return window_face and DAW.shows_plugin_windows() and not _drawn_by_the_daw()


## Reaper's own plugins (ReaEQ, ReaComp, JSFX) draw their windows with the same toolkit Reaper
## does, and that toolkit takes its pointer from the X input extension, which ignores the plain
## events the helper sends. Their knobs here are the way in; a window it could show but not
## touch would only be a picture.
func _drawn_by_the_daw() -> bool:
	return fx_name.ends_with("(Cockos)") or fx_name.begins_with("JS:")


func _open_window() -> void:
	_close_window()
	_window = DAW.open_plugin_window(track_index, fx_index)
	_window_for = [track_index, fx_index]
	if _screen != null and is_instance_valid(_screen):
		_screen.window = _window


func _close_window() -> void:
	if _window != null:
		_window.close()
	_window = null
	_window_for = []


## Grow the tablet while it shows a window, and shrink it back when it shows the knobs.
func _grow(delta: float) -> void:
	var target := 1.0 if showing_window and grows_with_window else 0.0
	if is_equal_approx(_grown, target):
		return
	if _grown == 0.0:
		_resting = transform
	_grown = move_toward(_grown, target, delta * 4.0)
	if _grown == 0.0:
		transform = _resting
		return
	var s := lerpf(1.0, WINDOW_SCALE, _grown)
	transform = _resting * Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(0, HEIGHT * 0.5 * (s - 1.0), 0))


## The window follows its plugin like the knobs do: moved along the chain or to another track,
## it is another window in Reaper, under another title, so the old one is put away and the new
## one opened. Lost, or no longer showable here, and the tablet goes back to its knobs.
func _follow_window() -> void:
	if not showing_window:
		return
	if lost or not _windows_here():
		show_window(false)
		return
	if _window_for != [track_index, fx_index]:
		_open_window()


# --- reading the plugin ---------------------------------------------------------------------

func refresh() -> void:
	if _title == null:
		return
	var f := fx()
	var here := f != null and not lost
	var track := DAW.state.track(track_index) if DAW.state.tracks.has(track_index) else null
	_title.text = fx_name
	var windows := _windows_here()
	Lettering.fit(_title, WIDTH - (0.15 if windows else 0.12), 72)
	_subtitle.text = "%s   ·   %s" % [track.display_name().to_upper() if track else "?", _chain_words()]
	Lettering.fit(_subtitle, WIDTH - 0.12, 40)
	_chip_material.albedo_color = Materials.chip_colour(track.shown_colour() if track else Color.GRAY)
	_lost_label.visible = lost
	_window_button.visible = windows and here
	_window_word.visible = _window_button.visible
	_window_button.lit = showing_window
	_give_the_window_the_footer()
	if not here:
		return
	_bypass.lit = f.enabled
	_mix.apply_remote(f.wet)
	_mix_label.text = "%d%%" % roundi(f.wet * 100.0)

	var presets := DAW.can(DAWBackend.Capability.FX_PRESETS)
	var own := _own_presets()
	if f.preset_count == 0 and own:
		_preset_label.text = "plugin's own"
	elif f.preset_count == 0:
		_preset_label.text = "none saved"
		presets = false
	else:
		_preset_label.text = f.preset if f.preset != "" else ("—" if presets else "no presets here")
	Lettering.fit(_preset_label, WIDTH * 0.5 - 0.1, 44)
	_preset_prev.visible = presets
	_preset_next.visible = presets
	# The plugin's own window has its own presets and no pages; the row would only crowd it.
	for n in [_preset_word, _preset_label, _preset_prev, _preset_next]:
		if showing_window:
			(n as Node3D).visible = false

	var params := _params()
	var shown := _page_size()
	for i in _knobs.size():
		var on := i < shown
		_knobs[i].visible = on
		_captions[i].visible = on
		if on:
			var index: int = params[page_offset + i]
			if f.params.has(index):
				_knobs[i].apply_remote(f.params[index])
			_captions[i].text = _caption_for(i)
			Lettering.fit(_captions[i], KNOB_PITCH.x - 0.008, CAPTION_SIZE)
	var paged := params.size() > PER_PAGE and not showing_window
	_page_label.visible = paged
	_page_prev.visible = paged
	_page_next.visible = paged
	if paged:
		var section := _page_section()
		var span := "%d" % (page_offset + 1) if shown == 1 else "%d-%d" % [page_offset + 1, page_offset + shown]
		_page_label.text = ("%s   " % section if section != "" else "") + "%s OF %d" % [span, params.size()]
		Lettering.fit(_page_label, WIDTH * 0.5 - 0.02, 38)
		_page_prev.lit = page_offset > 0
		_page_next.lit = page_offset + shown < params.size()

	_chain_label.text = _chain_words()
	var order := DAW.state.track(track_index).plugins()
	var at := order.find(fx_index)
	var can_chain := DAW.can(DAWBackend.Capability.FX_CHAIN)
	_chain_up.lit = can_chain and at > 0
	_chain_down.lit = can_chain and at >= 0 and at < order.size() - 1
	_move_to.visible = can_chain and not showing_window

	var keyed := keyed_by()
	_key.refresh()
	_key.lit = _key.choice in keyed
	_move_to.refresh()


## A plugin's own window is drawn for a screen, and the picture is the point of this face: it takes
## the footer's room too, and the footer (mix, key in, chain, move to) comes back with the knobs.
func _give_the_window_the_footer() -> void:
	for c in get_children():
		if c is Node3D and c != _screen and c.position.y <= FOOTER_RULE + 0.0005 and c.position.y > -HEIGHT * 0.5:
			c.visible = not showing_window
	if _screen == null:
		return
	var top := HEIGHT * 0.5 - 0.050
	var low := -HEIGHT * 0.5 + 0.010 if showing_window else FOOTER_RULE
	_screen.size = Vector2(WIDTH - 0.03, top - low - (0.0 if showing_window else 0.012))
	_screen.position.y = (top + low) * 0.5


func _params() -> Array:
	var f := fx()
	if f == null:
		return []
	var out := f.controls()
	# A plugin's own preset buttons are the PRESET buttons here, not two knobs that do nothing
	# until they are flicked.
	if _own_presets():
		out = out.filter(func(i): return str(f.param_names.get(i, "")) not in [PRESET_NEXT, PRESET_PREVIOUS])
	return out


## The parameter called `called`, or -1.
func _named(called: String) -> int:
	var f := fx()
	if f == null:
		return -1
	for i in f.controls():
		if str(f.param_names.get(i, "")) == called:
			return int(i)
	return -1


## Whether the plugin steps its own presets, and Reaper has none of its own to step.
func _own_presets() -> bool:
	var f := fx()
	return f != null and f.preset_count == 0 and _named(PRESET_NEXT) >= 0 and _named(PRESET_PREVIOUS) >= 0


func _step_preset(direction: int) -> void:
	if not _own_presets():
		DAW.step_fx_preset(track_index, fx_index, direction)
		return
	# Flicked like the button it is: on, then off again, so the next press is a change too.
	var param := _named(PRESET_NEXT if direction > 0 else PRESET_PREVIOUS)
	DAW.set_fx_param(track_index, fx_index, param, 1.0)
	var t := track_index
	var at := fx_index
	get_tree().create_timer(0.12).timeout.connect(func(): DAW.set_fx_param(t, at, param, 0.0))
	_page_read_msec = 0


## Ask for the plugin's full list of parameters, once per plugin, when the cache does not have
## it. On the stand-in the cache has everything and this asks for nothing.
func _ask_for_list() -> void:
	var f := fx()
	if f == null or lost or not f.param_list.is_empty():
		return
	var who := "%d|%d|%s" % [track_index, fx_index, fx_name]
	if _listed == who:
		return
	_listed = who
	DAW.read_fx_params(track_index, fx_index, [])


func _process(delta: float) -> void:
	super(delta)
	_follow_window()
	_grow(delta)
	if lost or _knobs.is_empty() or not is_visible_in_tree():
		return
	_follow_values()
	var now := Time.get_ticks_msec()
	if now - _page_read_msec < PAGE_READ_MSEC:
		return
	_page_read_msec = now
	var f := fx()
	if f == null or f.param_list.is_empty():
		return
	var page: Array = []
	for i in _knobs.size():
		var index := _param_for(i)
		if index >= 0:
			page.append(index)
	DAW.read_fx_params(track_index, fx_index, page)


## Parameter values arrive without a signal -- OSC streams them by the hundred a second -- so
## the knobs on show are matched to the cache every frame instead. Twelve comparisons.
func _follow_values() -> void:
	var f := fx()
	if f == null:
		return
	for i in _knobs.size():
		var index := _param_for(i)
		if index >= 0 and f.params.has(index) and not is_equal_approx(_knobs[i].value, f.params[index]):
			_knobs[i].apply_remote(f.params[index])


## The words every name on this page starts with -- "HOT AMP" over HOT Amp Gain, HOT Amp Bass
## and the rest -- so the page can say them once and each caption only what is its own. Empty
## when the page has nothing in common, or when taking it off would leave a caption empty.
func _page_section() -> String:
	var names: Array = []
	for i in _knobs.size():
		if _param_for(i) >= 0:
			names.append((_param_name(i) as String).split(" ", false))
	if names.size() < 2:
		return ""
	var common := _common_words(names)
	# A section's own on/off often leads its page under a name of its own; the page is still
	# that section.
	if common.is_empty() and names.size() >= 3:
		common = _common_words(names.slice(1))
	return " ".join(common)


static func _common_words(names: Array) -> Array:
	var common: Array = names[0].duplicate()
	for words in names:
		var n := 0
		while n < common.size() and n < words.size() - 1 and common[n] == words[n]:
			n += 1
		common = common.slice(0, n)
	return common


func _caption_for(slot: int) -> String:
	var whole := _param_name(slot)
	var section := _page_section()
	if section == "" or not whole.begins_with(section + " "):
		return whole
	return whole.substr(section.length() + 1)


func _param_for(slot: int) -> int:
	var params := _params()
	var at := page_offset + slot
	return int(params[at]) if slot < _page_size() and at < params.size() else -1


## Where each page starts in `_params()`. Twelve to a page, but a plugin's controls come in
## sections -- Gojira's CLN, RST and HOT amps, Mantra's EQ bands -- and a section that would not
## fit on what is left of a page starts the next one, so a page is one section's controls rather
## than the tail of one and the head of another. Sections are runs of names sharing a first word;
## one big enough to be worth a page (half of one) gets a page to itself, and the scraps share.
func _page_starts() -> Array:
	var params := _params()
	if _starts_for == _shape_seed(params):
		return _starts
	var f := fx()
	var starts: Array = [0]
	var used := 0
	var i := 0
	while i < params.size():
		var word := _first_word(f, params[i])
		var run := 1
		while i + run < params.size() and _first_word(f, params[i + run]) == word:
			run += 1
		var big := run >= PER_PAGE / 2
		if used > 0 and (big or used + run > PER_PAGE):
			starts.append(i)
			used = 0
		used += run
		while used > PER_PAGE:
			starts.append(int(starts[-1]) + PER_PAGE)
			used -= PER_PAGE
		# Nothing else on a section's own page, except a last scrap that would be a page alone:
		# Bypass, on its own at the end of every Neural DSP plugin.
		var left := params.size() - (i + run)
		if big and left > 0 and not (left <= 2 and used + left <= PER_PAGE):
			starts.append(i + run)
			used = 0
		i += run
	# A page of one or two -- "Active Post FX Section" between the EQs and the delay -- joins the
	# page after it, or else the one before, wherever they fit together.
	var k := 0
	while k < starts.size() and starts.size() > 1:
		var end: int = starts[k + 1] if k + 1 < starts.size() else params.size()
		var size: int = end - int(starts[k])
		if size <= 2:
			var next_end: int = starts[k + 2] if k + 2 < starts.size() else params.size()
			if k + 1 < starts.size() and next_end - int(starts[k]) <= PER_PAGE:
				starts.remove_at(k + 1)
				continue
			if k > 0 and end - int(starts[k - 1]) <= PER_PAGE:
				starts.remove_at(k)
				continue
		k += 1
	_starts = starts
	_starts_for = _shape_seed(params)
	return starts


func _shape_seed(params: Array) -> String:
	return "%s|%d|%d" % [fx_name, params.size(), hash(params)]


static func _first_word(f: MixState.FXState, index: int) -> String:
	var words := str(f.param_names.get(index, "")).to_upper().split(" ", false)
	return words[0] if not words.is_empty() else ""


## How many knobs the page at `page_offset` has.
func _page_size() -> int:
	var starts := _page_starts()
	var total := _params().size()
	var at := starts.find(page_offset)
	if at < 0:
		return clampi(total - page_offset, 0, PER_PAGE)
	var end: int = starts[at + 1] if at + 1 < starts.size() else total
	return mini(end - page_offset, PER_PAGE)


func _param_name(slot: int) -> String:
	var f := fx()
	var index := _param_for(slot)
	if f == null or index < 0:
		return "?"
	return str(f.param_names.get(index, "P%d" % index)).to_upper().strip_edges()


## The plugin's own words for a value when it has said them, else a percentage. The same rule as
## the rack's, for the same reason: see RackUnit._param_reading.
func _param_reading(slot: int, v: float) -> String:
	var f := fx()
	var index := _param_for(slot)
	if f == null or index < 0:
		return "%d%%" % roundi(v * 100.0)
	var at := float(f.param_text_at.get(index, f.params.get(index, -1.0)))
	if f.param_text.has(index) and absf(at - v) < 0.002:
		var text := str(f.param_text[index]).strip_edges()
		if not text.is_empty():
			return text
	var now := Time.get_ticks_msec()
	if now - _text_asked_msec > TEXT_ASK_MSEC:
		_text_asked_msec = now
		DAW.read_fx_param_text(track_index, fx_index, index)
	return "%d%%" % roundi(v * 100.0)


func _caption() -> String:
	var track := DAW.state.track(track_index) if DAW.state.tracks.has(track_index) else null
	return "%s  %s" % [track.display_name().to_upper() if track else "?", fx_name.to_upper()]


func _chain_words() -> String:
	if not DAW.state.tracks.has(track_index):
		return ""
	var order := DAW.state.track(track_index).plugins()
	return "%d OF %d" % [order.find(fx_index) + 1, order.size()]


func _other_tracks() -> Array:
	var out: Array = []
	for i in DAW.state.track_indices():
		if i != track_index:
			out.append([i, DAW.state.track(i).display_name().to_upper()])
	return out


## The tracks sending into this plugin's track's key input, in track order.
func keyed_by() -> Array:
	var out: Array = []
	for i in DAW.state.track_indices():
		for s in DAW.state.track(i).sends.values():
			var send := s as MixState.SendState
			if send.key and send.resolve(DAW.state) == track_index:
				out.append(i)
				break
	return out


# --- acting on it ---------------------------------------------------------------------------

## Nothing is sent for a plugin that is not there: every write is to a slot, and the slot of a
## plugin that has gone holds something else, or nothing.
func _act(what: Callable) -> void:
	if not lost and fx() != null:
		what.call()


func _step_page(direction: int) -> void:
	var starts := _page_starts()
	var at := starts.find(page_offset)
	if at < 0:
		# Pages are drawn by the names, and the names have changed under this one: start over.
		page_offset = 0
		mark_dirty()
		return
	var to := at + signi(direction)
	if to < 0 or to >= starts.size() or int(starts[to]) >= _params().size():
		return
	page_offset = starts[to]
	mark_dirty()


## One place earlier (-1) or later (+1) on its own track.
func _shift(direction: int) -> void:
	if lost or not DAW.can(DAWBackend.Capability.FX_CHAIN):
		return
	var order := DAW.state.track(track_index).plugins()
	var at := order.find(fx_index)
	var to := at + direction
	if at < 0 or to < 0 or to >= order.size():
		return
	# Slots are named as they are now; going down, the slot to aim for is the one past the
	# plugin being stepped over, or past the end.
	var aim: int
	if direction < 0:
		aim = order[to]
	else:
		aim = order[to + 1] if to + 1 < order.size() else int(order[-1]) + 1
	_expect = [track_index, order[to]]
	DAW.move_fx(track_index, fx_index, track_index, aim)
	fx_index = order[to]
	mark_dirty()


func move_to_track(to: int) -> void:
	if lost or to == track_index or not DAW.state.tracks.has(to) \
			or not DAW.can(DAWBackend.Capability.FX_CHAIN):
		return
	var order := DAW.state.track(to).plugins()
	var end := int(order[-1]) + 1 if not order.is_empty() else 999
	_expect = [to, end]
	DAW.move_fx(track_index, fx_index, to, end)
	mark_dirty()


func _on_key_pressed(from: int) -> void:
	if lost or from < 0:
		return
	# Already keying it: pull that send. Otherwise patch it.
	var sends := DAW.state.track(from).sends
	var keys: Array = sends.keys()
	keys.sort()
	for k in keys:
		var send := sends[k] as MixState.SendState
		if send.key and send.resolve(DAW.state) == track_index:
			DAW.remove_send(from, int(k))
			refresh()
			return
	DAW.create_sidechain(from, track_index)
	refresh()
