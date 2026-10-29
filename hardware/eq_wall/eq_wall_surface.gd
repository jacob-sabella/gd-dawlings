class_name EqWall
extends Surface

## EQ as a wall of frequencies (docs/spatial_loop.md part two, slice 36, idea #8): a board 2 m tall
## on its own trolley at the control room's side wall, with frequency up its height, 20 Hz at the
## floor to 20 kHz at the top, logarithmically, lettered down its left edge.
##
## Each track's spectrum (Spectra) is a see-through shape, centred on the board and overlaid on the
## others, whose width at each height is the track's level in that band, against the mix's loudest
## band (Spectra's reference, `reference`): the whole of the board at it, no width SHOWN_FLOOR_DB
## under it, linear in decibels. Each is named beside its loudest band, clear of the glows and of
## the other names, and in the key down the board's right-hand column, and hatched its own way
## (HATCHES), so no shape is told from another by its colour alone.
##
## Where two tracks are both above Spectra.LOUD_DB under the reference in a band and within
## Spectra.NEAR_DB of each other, they clash (Spectra.clashes). The worst LETTERED clashes that do
## not sit over one another glow: the overlap of their two shapes, brighter and cross-hatched, each
## side of it lettered with a track's name (the lower-numbered track's on the left) and the span it
## covers above it. The rest are counted under SHOW. A glow is hovered for its card (`Clash`).
##
## Its SHOW key picks what it shows: every track, the soloed ones, or the two that clash most
## (Spectra.worst_pair). Where there is nothing to show it says why across the middle: the reason
## the spectra are not here (`reason`: "spectra need the built-in engine" on Reaper), or that
## nothing is playing.
##
## A glow is carved (slice 37, EqCarve): grabbed on one track's lettered side and pushed into the
## wall, or at a desk dragged down it or turned with the wheel, it cuts that track where the two
## fight, an EQ at the end of its chain put there by the first push, one edit a push. A glow in a
## hand keeps its clash while it is held, so the carving that ends a clash does not take the glow
## out from under the hand, and its span is lettered with the cut. Everything else here only reads.
## The spectra come from whoever stands it up (`spectra` and `reason`, the studio's Spectra node),
## so the surface never asks where they came from or whether this process is the host: every write
## goes through DAW, a guest's an intent its host carries out.
##
## Its frame: the origin is the floor under the board's middle, +Y up, +Z out of its face toward
## whoever reads it.

## The graph: how wide and tall (m), and how far off the floor its foot is, over the trolley's
## casters.
const WIDE := 1.3
const TALL := 2.0
const BOTTOM := 0.16
## The lettered margin left of the graph, the key column right of it, and the border round both.
const MARGIN := 0.13
const SIDE := 0.36
const BORDER := 0.04
const PLATE_WIDE := MARGIN + WIDE + SIDE
## A band this far under the reference or more has no width (dB).
const SHOWN_FLOOR_DB := -60.0
## The lines across the board, and the levels marked down it either side of the middle.
const GRID_HZ := [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0]
const GUIDE_DB := [-30.0, 0.0]
## What SHOW steps through.
const SHOWS := [&"all", &"soloed", &"clash"]
## Each track's hatch, by its number: [angle (radians), spacing (m)]. Eight angles, two spacings.
const HATCHES := [[0.785, 0.045], [-0.785, 0.045], [0.0, 0.05], [1.571, 0.05],
		[0.393, 0.065], [-0.393, 0.065], [1.178, 0.065], [-1.178, 0.065]]
## How many clashes glow at once, each lettered, the rest only counted under SHOW; how many tracks
## the key lists.
const LETTERED := 4
const KEY_ROWS := 10
const KEY_STEP := 0.052
## How often the shapes are drawn again (Hz), and with motion turned down (Ergonomics).
const REDRAW_HZ := 10.0
const CALM_HZ := 1.0
## Where SHOW is (m up), under the key; and the top of the station's plaque (Stations.plaque), on
## the trolley under it.
const SHOW_Y := 1.3
const PLAQUE_TOP := 1.1
## The lettering's heights (m): track names, the clash names, the margin's frequencies, the
## middle's words.
const NAME_CAP := 0.032
const CLASH_CAP := 0.036
const GRID_CAP := 0.026
const WORDS_CAP := 0.045
const PIXEL := 0.0004
## About how wide a capital is, as a share of its height, for keeping a name on the board.
const CHAR_WIDE := 0.62
const GLOW := Color(1.0, 0.86, 0.42)
## Drawing order among the see-through layers: the shapes, then the glows, then all lettering.
const GLOW_PRIORITY := 1
const LABEL_PRIORITY := 3
## A clash's name where it sits on its glow.
const GLOW_INK := Color(0.1, 0.08, 0.03)

## What the wall shows: every track, the soloed ones, or the worst clash's two.
var showing := &"all"
## () -> Dictionary, track -> Spectra.BANDS levels in dB: what there is to show.
var spectra: Callable = func() -> Dictionary: return {}
## () -> float: what the spectra stand against (dBFS), the mix's loudest band (Spectra.reference).
var reference: Callable = func() -> float: return 0.0
## () -> String: why there is nothing to show, or empty.
var reason: Callable = func() -> String: return ""
## () -> float, Ergonomics.motion_scale: at 0 the shapes are drawn again only CALM_HZ times a
## second.
var motion: Callable = func() -> float: return 1.0

## The tracks shown and their bands as last drawn; and the clashes among them, worst first.
var shown := {}
var clashes: Array = []
## The reference they were last drawn against (dBFS).
var drawn_against := 0.0
## Per shown track, its shape: {"fill", "edge", "name"}; the glows lit, worst first, and how many
## clashes went unlit (see _draw_glows).
var shapes := {}
var glows: Array[Clash] = []
var unlit := 0
var _glow_spans: Array[Vector2] = []
var _glow_clashes: Array[Dictionary] = []
var key_rows: Array[KeyRow] = []
var _live: Node3D
var _words: Label3D
var _show_label: Label3D
var _show_key: WallKey
var _redraw_in := 0.0

static var _shader: Shader


func _ready() -> void:
	surface_kind = &"eq_wall"
	if surface_id == &"":
		surface_id = &"eq_wall"
	# A place, 2 m tall: visited, or brought on its own, and never parked in the arc beside other
	# gear, where its height alone would push the whole arc out (Surface.parks).
	parks = false
	super()
	DAW.track_changed.connect(func(_i: int, field: StringName) -> void:
		if field == &"name" or field == &"colour" or field == &"solo":
			_redraw_in = 0.0)
	DAW.project_replaced.connect(mark_dirty)


func _process(delta: float) -> void:
	super(delta)
	if _live == null:
		return
	_redraw_in -= delta
	if _redraw_in <= 0.0:
		_redraw_in = 1.0 / (REDRAW_HZ if float(motion.call()) > 0.0 else CALM_HZ)
		redraw()


# --- the arithmetic of the wall -------------------------------------------------------------

## Where the graph's middle is across the board (m): the plate is centred, the margin on its left.
static func middle_x() -> float:
	return -PLATE_WIDE * 0.5 + MARGIN + WIDE * 0.5


## How high up the board `hz` is (m, from the floor).
static func y_of_hz(hz: float) -> float:
	return BOTTOM + TALL * Spectra.height_of(hz)


static func y_of_band(band: int) -> float:
	return y_of_hz(Spectra.centre(band))


## How far either side of the middle a band `db` under the reference reaches (m).
static func half_width_of(db: float) -> float:
	return WIDE * 0.5 * clampf((db - SHOWN_FLOOR_DB) / -SHOWN_FLOOR_DB, 0.0, 1.0)


## How far under the reference a reach from the middle stands for (dB).
static func db_of_half_width(half: float) -> float:
	return SHOWN_FLOOR_DB * (1.0 - clampf(half / (WIDE * 0.5), 0.0, 1.0))


## A band's reach, as drawn now: its level against the reference it was drawn against.
func reach_of(db: float) -> float:
	return half_width_of(db - drawn_against)


## A track as the wall names it: "2 KICK".
static func title_of(track: int) -> String:
	var t := DAW.state.track(track, false) if DAW.state != null else null
	var n := t.display_name() if t != null else "Track %d" % track
	return "%d %s" % [DAW.state.bank_offset + track if DAW.state != null else track, n.to_upper()]


## A track's hatch: [angle, spacing].
static func hatch_of(track: int) -> Array:
	return HATCHES[posmod(track - 1, HATCHES.size())]


## Put `label` beside a shape's edge `reach` out from the middle, on the left (`side` -1) or the
## right: just outside the edge, reading away from it, or just inside it when outside it would run
## off the plot, into the key's column or past the board's edge. Answers whether it is outside.
static func beside(label: Label3D, side: float, reach: float, y: float, z: float) -> bool:
	var cap := label.font_size * label.pixel_size
	var wide := label.text.length() * cap * CHAR_WIDE
	# On the left it may run into the margin, between the frequencies lettered there.
	var clear_of_grid := GRID_HZ.all(func(hz: float) -> bool: return absf(y - y_of_hz(hz)) > (cap + GRID_CAP) * 0.6)
	var room := WIDE * 0.5 + (MARGIN * 0.5 if side < 0.0 and clear_of_grid else 0.0)
	var outside := reach + 0.02 + wide <= room or reach < wide + 0.04
	var x := reach + 0.02 if outside else reach - 0.02
	label.position = Vector3(middle_x() + side * x, y, z)
	var away := outside == (side > 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if away else HORIZONTAL_ALIGNMENT_RIGHT
	return outside


## The height nearest `want` (m) for a name `half` m either side of it that overlaps nothing in
## `taken` ([bottom, top] spans) and stays on the board: `want` itself, or just under or just over
## one of them. `want` if nowhere is clear.
static func clear_height(want: float, half: float, taken: Array[Vector2]) -> float:
	var low := BOTTOM + half
	var high := BOTTOM + TALL - half
	var tries: Array[float] = [clampf(want, low, high)]
	for span in taken:
		tries.append(span.x - half - 0.002)
		tries.append(span.y + half + 0.002)
	var best := want
	var nearest := INF
	for y in tries:
		if y < low - 0.0001 or y > high + 0.0001 or absf(y - want) >= nearest:
			continue
		if taken.all(func(span: Vector2) -> bool: return y + half <= span.x + 0.0001 or y - half >= span.y - 0.0001):
			best = y
			nearest = absf(y - want)
	return best


## The band at height `y` (m) up the board: a band is a tenth of a decade, and the board three.
static func band_at(y: float) -> int:
	return clampi(roundi((y - BOTTOM) / TALL * float(Spectra.BANDS - 1)), 0, Spectra.BANDS - 1)


## Its loudest band.
static func loudest(bands: PackedFloat32Array) -> int:
	var best := 0
	for i in bands.size():
		if bands[i] > bands[best]:
			best = i
	return best


## The tracks `showing` picks out of `all` (track -> bands): every one, the soloed, or the two that
## clash most against `against` (dBFS).
static func pick(all: Dictionary, show: StringName, against := NAN) -> Dictionary:
	var out := {}
	match show:
		&"soloed":
			for t in all:
				var ts := DAW.state.track(t, false)
				if ts != null and ts.solo:
					out[t] = all[t]
		&"clash":
			for t in Spectra.worst_pair(all, against):
				out[t] = all[t]
		_:
			out = all.duplicate()
	return out


# --- what SHOW does -------------------------------------------------------------------------

func step_show() -> void:
	showing = SHOWS[(SHOWS.find(showing) + 1) % SHOWS.size()]
	if _show_key != null:
		_show_key.lit = showing != &"all"
	redraw()


func show_words() -> String:
	match showing:
		&"soloed":
			return "SOLOED"
		&"clash":
			return "WORST CLASH"
	return "ALL TRACKS"


# --- building -------------------------------------------------------------------------------

func _rebuild() -> void:
	_clear_built()
	shapes.clear()
	glows.clear()
	_glow_spans.clear()
	key_rows.clear()
	shown = {}
	clashes = []
	var plate := MeshInstance3D.new()
	plate.name = "Board"
	var box := BoxMesh.new()
	box.size = Vector3(PLATE_WIDE + BORDER * 2.0, TALL + BORDER * 2.0, 0.03)
	plate.mesh = box
	plate.position = Vector3(0, BOTTOM + TALL * 0.5, -0.016)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.055, 0.06, 0.075)
	paint.roughness = 0.92
	plate.material_override = paint
	_adopt(plate)
	_build_grid()
	_build_column()
	_live = Node3D.new()
	_live.name = "Spectra"
	_adopt(_live)
	_words = _label("", WORDS_CAP, Color(0.9, 0.9, 0.86))
	_words.name = "Words"
	_words.position = Vector3(middle_x(), BOTTOM + TALL * 0.55, 0.012)
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.width = (WIDE - 0.1) / PIXEL
	_adopt(_words)
	_redraw_in = 0.0
	redraw()


## How far off the board the grid's uprights (the middle and the dB reaches) stand: in front of
## the lines across it, at 0.001, by more than their depth.
const UPRIGHT_Z := 0.0022


## Lines across the board at GRID_HZ, lettered in the margin; the middle; and the -30 dB and 0 dB
## reaches either side of it, lettered along the top.
func _build_grid() -> void:
	var x0 := middle_x()
	var line := StandardMaterial3D.new()
	line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.albedo_color = Color(0.5, 0.55, 0.62, 0.35)
	line.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for hz: float in GRID_HZ:
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(WIDE, 0.003, 0.001)
		bar.mesh = mesh
		bar.position = Vector3(x0, y_of_hz(hz), 0.001)
		bar.material_override = line
		_adopt(bar)
		var l := _label(Spectra.hz_words(hz), GRID_CAP, Color(0.78, 0.8, 0.84))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.position = Vector3(x0 - WIDE * 0.5 - 0.015, y_of_hz(hz), 0.004)
		_adopt(l)
	var under := _label("dB under the mix's loudest band", GRID_CAP, Color(0.72, 0.75, 0.8))
	under.position = Vector3(x0, BOTTOM + TALL + 0.022, 0.004)
	_adopt(under)
	var hz_label := _label("Hz", GRID_CAP, Color(0.78, 0.8, 0.84))
	hz_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hz_label.position = Vector3(x0 - WIDE * 0.5 - 0.015, BOTTOM + TALL + 0.035, 0.004)
	_adopt(hz_label)
	var up := MeshInstance3D.new()
	var spine := BoxMesh.new()
	spine.size = Vector3(0.003, TALL, 0.001)
	up.mesh = spine
	# The uprights a hair proud of the lines across, so where they cross the two are not one
	# plane fighting for the same depth.
	up.position = Vector3(x0, BOTTOM + TALL * 0.5, UPRIGHT_Z)
	up.material_override = line
	_adopt(up)
	for db: float in GUIDE_DB:
		for side in [-1.0, 1.0]:
			var x: float = x0 + side * half_width_of(db)
			var guide := MeshInstance3D.new()
			var g := BoxMesh.new()
			g.size = Vector3(0.002, TALL, 0.001)
			guide.mesh = g
			guide.position = Vector3(x, BOTTOM + TALL * 0.5, UPRIGHT_Z)
			guide.material_override = line
			_adopt(guide)
			var l := _label("%d dB" % roundi(db), GRID_CAP, Color(0.72, 0.75, 0.8))
			l.position = Vector3(x - side * 0.04 if db == 0.0 else x, BOTTOM + TALL + 0.022, 0.004)
			_adopt(l)


## The column right of the graph: the title, SHOW and what it is showing, and the key.
func _build_column() -> void:
	var cx := PLATE_WIDE * 0.5 - SIDE * 0.5
	var title := _label("EQ WALL", 0.05, Color(0.95, 0.9, 0.78))
	title.position = Vector3(cx, BOTTOM + TALL - 0.04, 0.004)
	_adopt(title)
	var sub := _label("each track's level in each band", 0.022, Color(0.8, 0.8, 0.78))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.width = (SIDE - 0.04) / PIXEL
	sub.position = Vector3(cx, BOTTOM + TALL - 0.1, 0.004)
	_adopt(sub)
	# SHOW at hand height, where a standing player presses it and a seated one sees it.
	_show_key = WallKey.new()
	_show_key.name = "Show"
	_show_key.legend = "SHOW"
	_show_key.size = Vector2(SIDE - 0.08, 0.08)
	_show_key.says = "every track, the soloed ones, or the two that clash most"
	_show_key.describe_title = func() -> String: return "EQ WALL  SHOW"
	_show_key.describe_value = func(_v: float) -> String: return show_words()
	_show_key.position = Vector3(cx, SHOW_Y, 0.0)
	_show_key.pressed.connect(step_show)
	_adopt(_show_key)
	_show_label = _label("", 0.03, Color(0.9, 0.88, 0.8))
	_show_label.name = "Showing"
	_show_label.position = Vector3(cx, SHOW_Y - 0.1, 0.004)
	_adopt(_show_label)


## The wall drawn again from the spectra as they are now: a shape per track shown, a glow per
## clash among them, the key, and the words across the middle where there is nothing to draw.
func redraw() -> void:
	if _live == null:
		return
	var why: String = reason.call()
	var all: Dictionary = {} if why != "" else spectra.call()
	drawn_against = float(reference.call())
	shown = pick(all, showing, drawn_against)
	clashes = Spectra.clashes(shown, drawn_against)
	if _show_label != null:
		_show_label.text = show_words()
	var quiet := shown.values().all(func(b: PackedFloat32Array) -> bool: return not Spectra.any_above(b, Spectra.FLOOR_DB + 6.0))
	if why != "":
		_words.text = why
	elif showing == &"soloed" and shown.is_empty():
		_words.text = "nothing is soloed: solo a track to see it alone"
	elif showing == &"clash" and shown.is_empty():
		_words.text = "no two tracks clash now"
	elif all.is_empty() or quiet:
		_words.text = "play the song to see each track's spectrum"
	else:
		_words.text = ""
	_words.visible = _words.text != ""
	for t in shapes.keys():
		if not shown.has(t):
			for n: Node in shapes[t].values():
				n.queue_free()
			shapes.erase(t)
	var tracks: Array = shown.keys()
	tracks.sort()
	# The glows first, so the shapes' names keep off them: each glow is lettered, and a name
	# across one would print over its own.
	var taken := _draw_glows().duplicate()
	for t: int in tracks:
		_draw_shape(t, shown[t], taken)
	if _show_label != null and unlit > 0:
		_show_label.text = "%s\n%d more clash%s not lit" % [show_words(), unlit, "" if unlit == 1 else "es"]
	_draw_key(tracks)


## A track's shape drawn again, and its name put beside it at the first height near its loudest
## band that is clear of everything in `taken` (spans up the board, [bottom, top] in m), which it
## then joins. Where a glow over that band already names the track, the shape's name is left
## off: the glow says it there.
func _draw_shape(track: int, bands: PackedFloat32Array, taken: Array[Vector2]) -> void:
	if not shapes.has(track):
		var fill := MeshInstance3D.new()
		fill.name = "Shape%d" % track
		fill.mesh = ImmediateMesh.new()
		fill.material_override = hatch_material(track)
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_live.add_child(fill)
		var edge := MeshInstance3D.new()
		edge.name = "Edge%d" % track
		edge.mesh = ImmediateMesh.new()
		var ink := StandardMaterial3D.new()
		ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ink.albedo_color = _colour(track).lightened(0.2)
		edge.material_override = ink
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_live.add_child(edge)
		var tag := _label(title_of(track), NAME_CAP, _colour(track).lightened(0.35))
		tag.name = "Name%d" % track
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_live.add_child(tag)
		shapes[track] = {"fill": fill, "edge": edge, "name": tag}
	var parts: Dictionary = shapes[track]
	# A hair in front of the one before, so overlapping shapes do not fight for the same depth.
	var z := 0.004 + 0.0008 * float(shown.keys().find(track))
	var outline := _outline(bands)
	var fill_mesh := parts["fill"].mesh as ImmediateMesh
	fill_mesh.clear_surfaces()
	fill_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(outline.size() / 2 - 1):
		var l0: Vector2 = outline[i]
		var l1: Vector2 = outline[i + 1]
		var r0: Vector2 = outline[outline.size() - 1 - i]
		var r1: Vector2 = outline[outline.size() - 2 - i]
		for p: Vector2 in [l0, r0, l1, l1, r0, r1]:
			fill_mesh.surface_add_vertex(Vector3(p.x, p.y, z))
	fill_mesh.surface_end()
	var edge_mesh := parts["edge"].mesh as ImmediateMesh
	edge_mesh.clear_surfaces()
	edge_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: Vector2 in outline:
		edge_mesh.surface_add_vertex(Vector3(p.x, p.y, z + 0.0004))
	edge_mesh.surface_add_vertex(Vector3(outline[0].x, outline[0].y, z + 0.0004))
	edge_mesh.surface_end()
	var top := loudest(bands)
	var tag := parts["name"] as Label3D
	tag.visible = reach_of(bands[top]) > 0.0
	if not tag.visible:
		return
	var half := NAME_CAP * 0.8
	var want := y_of_band(top)
	for n in _glow_spans.size():
		var span := _glow_spans[n]
		var c := _glow_clashes[n]
		if (c["a"] == track or c["b"] == track) and want + half > span.x and want - half < span.y:
			tag.visible = false
			return
	var y := clear_height(want, half, taken)
	taken.append(Vector2(y - half, y + half))
	# Its reach where it ended up, the widest of the bands it sits across, so it stays off the edge.
	var at := band_at(y)
	var reach := 0.0
	for i in range(maxi(at - 1, 0), mini(at + 2, Spectra.BANDS)):
		reach = maxf(reach, reach_of(bands[i]))
	beside(tag, 1.0, reach, y, 0.03)


## A shape's outline, in the wall's frame: up its left side, from 20 Hz at the foot to 20 kHz at
## the top, and down its right.
func _outline(bands: PackedFloat32Array) -> PackedVector2Array:
	var x0 := middle_x()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	left.append(Vector2(x0 - reach_of(bands[0]), BOTTOM))
	right.append(Vector2(x0 + reach_of(bands[0]), BOTTOM))
	for i in Spectra.BANDS:
		var w := reach_of(bands[i])
		var y := clampf(y_of_band(i), BOTTOM, BOTTOM + TALL)
		left.append(Vector2(x0 - w, y))
		right.append(Vector2(x0 + w, y))
	left.append(Vector2(x0 - reach_of(bands[Spectra.BANDS - 1]), BOTTOM + TALL))
	right.append(Vector2(x0 + reach_of(bands[Spectra.BANDS - 1]), BOTTOM + TALL))
	right.reverse()
	return left + right


## The glows: the worst clashes, up to LETTERED of them that do not sit over one another, each its
## overlap's outline (the narrower of the two shapes over its run, half a band past either end) and
## lettered. A full mix clashes in more places than a wall can letter, and a wall lit all over says
## nothing; the rest are counted under SHOW, which steps to the worst pair alone. A glow in a hand
## keeps the clash it was grabbed on, redrawn over the shapes as they are now, and the others keep
## off it. Answers the spans up the board the lit ones take, their span's lettering above them
## included, as `_glow_spans` keeps them beside `_glow_clashes`.
func _draw_glows() -> Array[Vector2]:
	var lit: Array[Dictionary] = []
	var spans: Array[Vector2] = []
	var kept: Array[Clash] = []
	for g: Clash in glows:
		if g.is_held() and not g.clash.is_empty():
			kept.append(g)
			spans.append(_span_of(g.clash))
	for c: Dictionary in clashes:
		if lit.size() + kept.size() >= LETTERED:
			break
		var span := _span_of(c)
		if spans.all(func(s: Vector2) -> bool: return span.y < s.x - 0.02 or span.x > s.y + 0.02):
			spans.append(span)
			lit.append(c)
	unlit = 0
	for c: Dictionary in clashes:
		if not lit.has(c) and not kept.any(func(g: Clash) -> bool: return _same_fight(g.clash, c)):
			unlit += 1
	var free: Array[Clash] = []
	for g: Clash in glows:
		if not kept.has(g):
			free.append(g)
	while free.size() < lit.size():
		var g := Clash.new()
		g.wall = self
		_live.add_child(g)
		glows.append(g)
		free.append(g)
	for n in free.size():
		if n >= lit.size():
			free[n].hide_clash()
		else:
			free[n].show_clash(lit[n], shown)
	for g in kept:
		if shown.has(g.clash["a"]) and shown.has(g.clash["b"]):
			g.show_clash(g.clash, shown)
	_glow_spans = spans
	_glow_clashes.clear()
	for g in kept:
		_glow_clashes.append(g.clash)
	_glow_clashes.append_array(lit)
	return spans


## Whether two clashes are the same pair over bands that meet: a held glow's, and the one the wall
## finds there now.
static func _same_fight(x: Dictionary, y: Dictionary) -> bool:
	return x["a"] == y["a"] and x["b"] == y["b"] and y["from"] <= x["to"] and y["to"] >= x["from"]


## The span up the board a glow for clash `c` takes, its span's lettering above it included.
static func _span_of(c: Dictionary) -> Vector2:
	return Vector2(y_of_hz(Spectra.edges(c["from"]).x), y_of_hz(Spectra.edges(c["to"]).y) + Clash.SPAN_ABOVE + GRID_CAP * 0.7)


## The key down the column: each track shown, its hatch and its name, and how many more.
func _draw_key(tracks: Array) -> void:
	var cx := PLATE_WIDE * 0.5 - SIDE * 0.5
	var rows := mini(tracks.size(), KEY_ROWS)
	while key_rows.size() < KEY_ROWS + 1:
		var r := KeyRow.new()
		r.wall = self
		r.size = Vector2(SIDE - 0.04, KEY_STEP - 0.004)
		_live.add_child(r)
		key_rows.append(r)
	for n in key_rows.size():
		var r: KeyRow = key_rows[n]
		r.position = Vector3(cx, BOTTOM + TALL - 0.19 - KEY_STEP * n, 0.0)
		if n < rows:
			r.show_track(tracks[n])
		elif n == rows and tracks.size() > rows:
			r.show_more(tracks.size() - rows)
		else:
			r.visible = false
			r.track = 0


func _colour(track: int) -> Color:
	var t := DAW.state.track(track, false) if DAW.state != null else null
	return t.shown_colour() if t != null else Color(0.7, 0.7, 0.7)


## A see-through, hatched material in track `track`'s colour, at its HATCHES angle and spacing.
func hatch_material(track: int) -> ShaderMaterial:
	var h := hatch_of(track)
	return EqWall.hatch(_colour(track), h[0], h[1], 0.12, 0.55, 0.0, 0.0)


## The wall's see-through, hatched fill: `tint`, stripes at `angle` every `spacing` m, `fill` and
## `line` its alpha between and on them, a second set of stripes across the first by `cross`, and
## lifted by `glow`.
static func hatch(tint: Color, angle: float, spacing: float, fill: float, line: float, cross: float,
		glow: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = HATCH_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter(&"tint", tint)
	m.set_shader_parameter(&"angle", angle)
	m.set_shader_parameter(&"spacing", spacing)
	m.set_shader_parameter(&"fill", fill)
	m.set_shader_parameter(&"line", line)
	m.set_shader_parameter(&"cross", cross)
	m.set_shader_parameter(&"glow", glow)
	return m


const HATCH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float angle = 0.0;
uniform float spacing = 0.05;
uniform float fill = 0.12;
uniform float line = 0.5;
uniform float cross = 0.0;
uniform float glow = 0.0;
varying vec2 at;
void vertex() {
	at = VERTEX.xy;
}
float stripes(vec2 p, float a) {
	float s = dot(p, vec2(cos(a), sin(a))) / spacing;
	float g = abs(fract(s + 0.5) - 0.5);
	float w = fwidth(s) * 1.5;
	return 1.0 - smoothstep(0.09, 0.09 + w, g);
}
void fragment() {
	float on = stripes(at, angle);
	on = max(on, cross * stripes(at, angle + 1.5708));
	ALBEDO = tint.rgb * (1.0 + glow);
	ALPHA = clamp((fill + line * on) * tint.a, 0.0, 1.0);
}
"""


func _label(words: String, cap: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = words
	l.pixel_size = PIXEL
	l.font_size = roundi(cap / PIXEL)
	l.modulate = colour
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	# Over the see-through shapes and glows, whichever is nearer the eye: transparent things are
	# drawn far to near by their origins, and a name at a shape's edge is often the farther.
	l.render_priority = LABEL_PRIORITY
	l.outline_render_priority = LABEL_PRIORITY - 1
	Lettering.range_to_legibility(l)
	return l


## A key on the wall: a plaque's key (StationBoard.dress_key) with its legend on it and a lamp that
## lights while it is not at its first setting; it says what it does on the hover card.
class WallKey extends ControlAffordance:
	signal pressed()
	var legend := ""
	var says := ""
	var size := Vector2(0.24, 0.08)
	var lit := false:
		set(v):
			lit = v
			if _lamp != null:
				_lamp.visible = v
	var _lamp: MeshInstance3D

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		StationBoard.dress_key(self, size, legend, 0.03)
		_lamp = MeshInstance3D.new()
		_lamp.name = "Lamp"
		var bar := BoxMesh.new()
		bar.size = Vector3(size.x * 0.5, 0.006, 0.002)
		_lamp.mesh = bar
		_lamp.position = Vector3(0, -size.y * 0.5 + 0.01, 0.0135)
		_lamp.material_override = Materials.led(Color(0.45, 0.68, 0.95), true)
		_lamp.visible = lit
		add_child(_lamp)

	func hint() -> String:
		return says

	func dwell_activates() -> bool:
		return true

	func personal() -> bool:
		return true

	func _default_readout() -> String:
		return ""

	func _on_grab_begin(_at: Vector3) -> void:
		pressed.emit()


## A clash, glowing: the overlap of two tracks' shapes over a run of bands, brighter and
## cross-hatched, the lower-numbered track's name on its left side and the other's on its right,
## and the span above it. Hovered, its card says who clashes where and how loud, and what a push on
## the side under the pointer cuts.
##
## Carved (slice 37, EqCarve): grabbed, the track whose side the grab is on is cut where the two
## clash, by how far the hand pushes into the wall since it closed (a hand's or a controller's aim,
## as the fifths wheel's pull is read), or how far the grab is dragged down the wall (a mouse, or a
## ray from afar), whichever went further: EqCarve.PUSH_FULL for CUT_MOST_DB, and back out or up
## again to raise it. The wheel, over a side, cuts NOTCH_DB a notch. One edit a push or a wheel
## turn: the EQ's adding where the first push makes it, and every band it moves. A grab that has
## not cut yet (a click to see what it does, a hand closed to look) asks for nothing, so leaves no
## EQ and no undo step. Where the EQ is not here yet (a guest's host, Reaper's poll), the push is
## kept and written as it arrives, and a track's EQ is asked for once while it is on its way.
class Clash extends ControlAffordance:
	## How far over the glow's top its span is lettered (m).
	const SPAN_ABOVE := EqWall.GRID_CAP * 0.9
	## The least cut (dB) that is a push: a Shift notch. Less, and the grab has not pushed yet, and
	## the track gets no EQ for it.
	const PUSHED_DB := EqCarve.FINE_NOTCH_DB
	## How long a track's EQ asked for and not yet in the state stops a second asking (msec): a
	## let-go and a grab again, a double click, or another glow over the same track, while the
	## first is on its way. Past it, an asking that never came (refused, a link lost) may be made
	## again.
	const ASKED_FOR_MSEC := 8000
	## Tracks whose EQ this machine has asked for and not seen come: track -> when (msec), the
	## asking or its push's let-go, whichever was later.
	static var _asked := {}
	var wall: EqWall
	## {"a", "b", "from", "to", "score"} (Spectra.clashes), and both tracks' bands.
	var clash := {}
	## The carve being made: {"track", "from", "to", "start": {param: dB} (EqCarve.start_of, empty
	## until the EQ has come), "change": dB, "base": dB the wheel has turned, and a push before this
	## grab that was still waiting for its EQ, "drag": dB this grab's movement has cut, "asked":
	## whether this push asked for the EQ, "at": the grab's point in the wall's frame, "out": the
	## hand's distance out from the wall at the grab}; {} for none. Its change is base plus drag.
	var push := {}
	## The track the edit opening now is named for: the grab's or the wheel's side.
	var _edit_track := 0
	var _nudger: Node
	var _a := PackedFloat32Array()
	var _b := PackedFloat32Array()
	var _fill: MeshInstance3D
	var _left: Label3D
	var _right: Label3D
	var _span: Label3D
	var _shape: CollisionShape3D

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		name = "Clash"
		_fill = MeshInstance3D.new()
		_fill.name = "Glow"
		_fill.mesh = ImmediateMesh.new()
		_fill.material_override = EqWall.hatch(EqWall.GLOW, 0.785, 0.032, 0.2, 0.6, 1.0, 0.6)
		_fill.material_override.render_priority = EqWall.GLOW_PRIORITY
		_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_fill)
		_left = wall._label("", EqWall.CLASH_CAP, EqWall.GLOW.lightened(0.3))
		_left.name = "Left"
		_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_left)
		_right = wall._label("", EqWall.CLASH_CAP, EqWall.GLOW.lightened(0.3))
		_right.name = "Right"
		_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(_right)
		_span = wall._label("", EqWall.GRID_CAP, EqWall.GLOW.lightened(0.3))
		_span.name = "Span"
		add_child(_span)
		_shape = CollisionShape3D.new()
		_shape.shape = BoxShape3D.new()
		add_child(_shape)
		edits_as_one = true
		describe_edit = func() -> String:
			var t := DAW.state.track(_edit_track, false) if DAW.state != null else null
			var who := t.display_name() if t != null else "Track %d" % _edit_track
			return "%s: carve %s" % [who, Spectra.span_words(clash.get("from", 0), clash.get("to", 0))]
		DAW.fx_changed.connect(_on_fx_changed)

	## The left side's track and the right side's.
	func left_track() -> int:
		return int(clash.get("a", 0))

	func right_track() -> int:
		return int(clash.get("b", 0))

	## Light it for clash `c` among `spectra` (track -> bands), and letter it.
	func show_clash(c: Dictionary, spectra: Dictionary) -> void:
		clash = c
		_a = spectra[c["a"]]
		_b = spectra[c["b"]]
		visible = true
		var x0 := EqWall.middle_x()
		var from: int = c["from"]
		var to: int = c["to"]
		var lo := EqWall.y_of_hz(Spectra.edges(from).x)
		var hi := EqWall.y_of_hz(Spectra.edges(to).y)
		var halves := PackedFloat32Array()
		var ys := PackedFloat32Array()
		halves.append(_half(from))
		ys.append(lo)
		for i in range(from, to + 1):
			halves.append(_half(i))
			ys.append(EqWall.y_of_band(i))
		halves.append(_half(to))
		ys.append(hi)
		var z := 0.022
		var m := _fill.mesh as ImmediateMesh
		m.clear_surfaces()
		m.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var widest := 0.0
		for n in ys.size() - 1:
			widest = maxf(widest, halves[n])
			for p: Vector2 in [Vector2(-halves[n], ys[n]), Vector2(halves[n], ys[n]), Vector2(-halves[n + 1], ys[n + 1]),
					Vector2(-halves[n + 1], ys[n + 1]), Vector2(halves[n], ys[n]), Vector2(halves[n + 1], ys[n + 1])]:
				m.surface_add_vertex(Vector3(x0 + p.x, p.y, z))
		m.surface_end()
		var mid := (lo + hi) * 0.5
		var reach := _half(roundi((from + to) * 0.5))
		_left.text = EqWall.title_of(c["a"])
		_right.text = EqWall.title_of(c["b"])
		# Inside the glow a name is dark on it; outside, the glow's own colour on the board.
		for side: Label3D in [_left, _right]:
			var outside := EqWall.beside(side, -1.0 if side == _left else 1.0, reach, mid, 0.034)
			side.modulate = EqWall.GLOW.lightened(0.3) if outside else EqWall.GLOW_INK
		_letter_span()
		_span.position = Vector3(x0, hi + SPAN_ABOVE, 0.034)
		(_shape.shape as BoxShape3D).size = Vector3(maxf(widest * 2.0, 0.06), maxf(hi - lo, 0.04), 0.02)
		_shape.position = Vector3(x0, mid, z)
		_shape.disabled = false

	## The span above the glow, and while a push carves it, the cut: "50-100 Hz · BASS DI -6 dB".
	func _letter_span() -> void:
		if clash.is_empty():
			return
		_span.text = Spectra.span_words(clash["from"], clash["to"])
		if not push.is_empty():
			var t := DAW.state.track(int(push["track"]), false)
			_span.text += " · %s %+.1f dB" % [t.display_name().to_upper() if t != null else "", _cut_shown()]

	## Put out: unseen, and no longer in the way of a pointer, so it shows no card.
	func hide_clash() -> void:
		visible = false
		clash = {}
		if _shape != null:
			_shape.disabled = true

	## The overlap's reach at band `i`: the narrower shape's.
	func _half(i: int) -> float:
		return wall.reach_of(minf(_a[i], _b[i]))

	func _default_title() -> String:
		if clash.is_empty():
			return "EQ WALL  CLASH"
		return "CLASH  %s / %s" % [EqWall.title_of(clash["a"]), EqWall.title_of(clash["b"])]

	func _default_readout() -> String:
		if clash.is_empty():
			return ""
		var from: int = clash["from"]
		var to: int = clash["to"]
		var mid := roundi((from + to) * 0.5)
		var said := "%s · %.0f and %.0f dBFS" % [Spectra.span_words(from, to), _a[mid], _b[mid]]
		if not push.is_empty():
			var t := DAW.state.track(int(push["track"]), false)
			said += " · %s cut %+.1f dB%s" % [t.display_name().to_upper() if t != null else "", _cut_shown(),
					", its EQ on its way" if _eq_on_its_way() else ""]
		return said

	func hint() -> String:
		if clash.is_empty():
			return ""
		var side := 1
		for by in _hovered_by:
			if by is Interactor:
				side = side_at((by as Interactor).hover_point)
				break
		return "%s\nat a desk drag it down, or the wheel, %.1f dB a notch · both within %d dB of the mix's loudest band and within %d dB of each other here: they fight for these bands" \
				% [EqCarve.push_words(track_on(side), clash["from"], clash["to"]), EqCarve.NOTCH_DB,
				roundi(-Spectra.LOUD_DB), roundi(Spectra.NEAR_DB)]

	# --- the carve ------------------------------------------------------------------------

	## Which side of the glow a point (global) is on: the left track's (-1), or the right's (1).
	func side_at(point: Vector3) -> int:
		if not is_inside_tree():
			return 1
		return -1 if wall.to_local(point).x < EqWall.middle_x() else 1

	## The track lettered on `side`.
	func track_on(side: int) -> int:
		return left_track() if side < 0 else right_track()

	## The cut the push has made so far (dB), as it was asked, whether or not the EQ has come.
	func _cut_shown() -> float:
		var start: Dictionary = push.get("start", {})
		var most := 0.0
		if start.is_empty():
			return EqCarve.carved(0.0, float(push.get("change", 0.0)))
		for p in start:
			most = minf(most, EqCarve.carved(float(start[p]), float(push["change"])))
		return most

	func grab_begin(by: Node, at: Vector3) -> void:
		_edit_track = track_on(side_at(at)) if not clash.is_empty() else 0
		super(by, at)

	func nudge(by: Node, notches: int, fine: bool) -> bool:
		_nudger = by
		if not clash.is_empty() and push.is_empty():
			_edit_track = track_on(side_at((by as Interactor).hover_point) if by is Interactor else 1)
		return super(by, notches, fine)

	## A push begun on `track`. Its EQ is not asked for yet: that waits for the push to cut
	## (`_ask_for_eq`). A push on the same track and clash still waiting for its EQ is carried on,
	## its cut kept as where this one starts.
	func begin_carve(track: int) -> bool:
		if clash.is_empty() or EqCarve.choice() == "" or DAW.state.track(track, false) == null:
			return false
		var was := push
		push = {"track": track, "from": clash["from"], "to": clash["to"], "start": {}, "change": 0.0,
				"base": 0.0, "drag": 0.0, "asked": false, "at": Vector3.ZERO, "out": NAN}
		if not was.is_empty() and (was["start"] as Dictionary).is_empty() and int(was["track"]) == track \
				and was["from"] == push["from"] and was["to"] == push["to"]:
			push["base"] = float(was["change"])
			push["change"] = push["base"]
			# Its asking still counts unless it has lapsed, when this push may ask again.
			push["asked"] = bool(was["asked"]) and asked_for(track)
		_take_start()
		return true

	## Whether the push's EQ has been asked for and is not here yet, or is here without what the push
	## needs of it (a ReaEQ whose parameters' names have not come).
	func _eq_on_its_way() -> bool:
		return not push.is_empty() and (push["start"] as Dictionary).is_empty() and (bool(push["asked"])
				or asked_for(int(push["track"])) or EqCarve.carver_on(int(push["track"])) >= 0)

	## Whether this machine has asked for `track`'s EQ and is still waiting for it.
	static func asked_for(track: int) -> bool:
		return _asked.has(track) and Time.get_ticks_msec() - int(_asked[track]) < ASKED_FOR_MSEC

	## The push's EQ asked for, at the end of its track's chain, inside the push's edit: once it
	## has cut, where the track has none and none is on its way.
	func _ask_for_eq() -> void:
		var track := int(push["track"])
		if push["asked"] or EqCarve.carver_on(track) >= 0 or asked_for(track) \
				or EqCarve.carved(0.0, float(push["change"])) > -PUSHED_DB + 0.0001:
			return
		DAW.add_fx(track, EqCarve.choice(), -1)
		push["asked"] = true
		_asked[track] = Time.get_ticks_msec()

	## Where the push starts from, once its EQ is here.
	func _take_start() -> void:
		if push.is_empty() or not (push["start"] as Dictionary).is_empty():
			return
		push["start"] = EqCarve.start_of(push["track"], EqCarve.carver_on(push["track"]), push["from"], push["to"])
		if not (push["start"] as Dictionary).is_empty():
			_asked.erase(int(push["track"]))

	## The push at `change` dB from where it started, written.
	func carve_to(change: float) -> void:
		if push.is_empty():
			return
		push["change"] = change
		_apply()

	func _apply() -> void:
		_ask_for_eq()
		_take_start()
		var start: Dictionary = push["start"]
		if not start.is_empty():
			EqCarve.write(push["track"], EqCarve.carver_on(push["track"]), push["from"], push["to"], start, push["change"])
		_letter_span()

	## The EQ a push asked for has come, or its parameters have: what the push has asked so far
	## written into it, once the plugin has finished landing. A plugin is said to have come as its
	## name arrives, before its parameters' values do, and those would lay a flat EQ over the cut.
	func _on_fx_changed(track: int, _fx: int) -> void:
		if _asked.has(track) and EqCarve.carver_on(track) >= 0:
			_asked.erase(track)
		if push.is_empty() or int(push["track"]) != track or not (push["start"] as Dictionary).is_empty():
			return
		_land.call_deferred(track)

	func _land(track: int) -> void:
		if push.is_empty() or int(push["track"]) != track or not (push["start"] as Dictionary).is_empty():
			return
		_take_start()
		if not (push["start"] as Dictionary).is_empty():
			_apply()
			if held_by == null and not _edit_open:
				push = {}

	## How far in front of the wall the hand holding the glow is (m), or NAN for a mouse, whose ray
	## starts at the eye.
	func _hand_out() -> float:
		var by := held_by as Interactor
		if by == null or by is MouseInteractor or not is_inside_tree():
			return NAN
		return (by.aim().origin - global_position).dot(global_basis.z.normalized())

	func _on_grab_begin(at: Vector3) -> void:
		if not begin_carve(_edit_track):
			return
		push["at"] = wall.to_local(at)
		push["out"] = _hand_out()

	## How far the push has gone (m): into the wall since the grab, or down it, whichever is further.
	func _on_grab_move(at: Vector3) -> void:
		if push.is_empty():
			return
		var drop: float = (push["at"] as Vector3).y - wall.to_local(at).y
		var out := _hand_out()
		var into: float = float(push["out"]) - out if not is_nan(out) and not is_nan(float(push["out"])) else 0.0
		push["drag"] = EqCarve.cut_of(into if absf(into) > absf(drop) else drop)
		carve_to(float(push["base"]) + float(push["drag"]))

	## The wheel over a side: NOTCH_DB a notch, down cuts and up gives back; Shift FINE_NOTCH_DB.
	## Notches close together are one turn, one edit, carrying on the same push. Turned while a
	## grab holds a push, it carries that push on, moving the base under the drag, so the drag is
	## not counted twice.
	func _on_nudge(notches: int, fine: bool) -> bool:
		if clash.is_empty():
			return false
		# While a grab holds a push, the wheel carries that push on, whichever side it is over.
		var track := int(push["track"]) if held_by != null and not push.is_empty() \
				else track_on(side_at((_nudger as Interactor).hover_point) if _nudger is Interactor else 1)
		if push.is_empty() or int(push["track"]) != track:
			if not begin_carve(track):
				return false
		var step := EqCarve.FINE_NOTCH_DB if fine else EqCarve.NOTCH_DB
		push["base"] = float(push["base"]) + notches * step
		carve_to(float(push["base"]) + float(push["drag"]))
		return true

	## A push ends with its edit: its let-go, or its wheel turn's last notch. One still waiting for
	## the EQ it asked for is kept until the EQ comes; one that never cut asked for nothing, and
	## ends.
	func _close_edit() -> void:
		super()
		if held_by != null or push.is_empty():
			return
		if (push["start"] as Dictionary).is_empty() and _eq_on_its_way():
			if push["asked"]:
				# Reaper sends the edit's adding only now, so the wait for it starts now.
				_asked[int(push["track"])] = Time.get_ticks_msec()
			return
		push = {}
		_letter_span()

	func personal() -> bool:
		return true


## A row of the key: a swatch of a track's hatch and its name; hovered, its card says where it is
## loudest. Or, last, how many more tracks are shown than it lists.
class KeyRow extends ControlAffordance:
	var wall: EqWall
	var track := 0
	var size := Vector2(0.3, 0.05)
	var _swatch: MeshInstance3D
	var _name: Label3D

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, 0.02)
		shape.shape = box
		shape.position = Vector3(0, 0, 0.01)
		add_child(shape)
		_swatch = MeshInstance3D.new()
		_swatch.name = "Swatch"
		var quad := QuadMesh.new()
		quad.size = Vector2(0.06, size.y - 0.012)
		_swatch.mesh = quad
		_swatch.position = Vector3(-size.x * 0.5 + 0.035, 0, 0.004)
		add_child(_swatch)
		_name = wall._label("", 0.026, Color(0.9, 0.9, 0.9))
		_name.name = "Name"
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_name.position = Vector3(-size.x * 0.5 + 0.075, 0, 0.004)
		add_child(_name)

	func show_track(t: int) -> void:
		visible = true
		if track != t:
			track = t
			_swatch.material_override = wall.hatch_material(t)
		_swatch.visible = true
		_name.text = EqWall.title_of(t)
		_name.modulate = wall._colour(t).lightened(0.35)
		Lettering.fit(_name, size.x - 0.08, roundi(0.026 / EqWall.PIXEL), 30)

	func show_more(n: int) -> void:
		visible = true
		track = 0
		_swatch.visible = false
		_name.text = "+%d more" % n
		_name.modulate = Color(0.8, 0.8, 0.8)

	func _default_title() -> String:
		return "EQ WALL  %s" % (EqWall.title_of(track) if track > 0 else "KEY")

	func _default_readout() -> String:
		if track <= 0 or not wall.shown.has(track):
			return ""
		var bands: PackedFloat32Array = wall.shown[track]
		var top := EqWall.loudest(bands)
		return "loudest at %s Hz, %.0f dBFS" % [Spectra.label(top), bands[top]]

	func hint() -> String:
		return "its shape's width at each height is its level in that band"

	func personal() -> bool:
		return true
