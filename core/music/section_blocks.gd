class_name SectionBlocks
extends Node3D

## Song sections as blocks on a table (docs/spatial_loop.md part two, slice 30; idea #9): the
## song's regions (MixState.regions, in song order) as a row of blocks along the bricks table's far
## long edge (Venue.sections_spot), each as long as its region's bars and lettered with its name
## and its bars. The block the playhead is in is lit brighter and has a mark on it at the
## playhead, moving with it (Ergonomics.motion_scale; at 0 it steps a bar at a time).
##
## Take a block and move it along the row, and the others make room for it where it would go.
## Nothing changes in the song while it is held. Let go, and `DAW.arrange_sections` is called once
## with the new order (slice 29): one undo step per rearrangement, which the 2D view shows. Let
## go further than OFF_ROW from the row and it goes back to where it was. At a desk: drag a block
## along the row, or [ and ] (Studio) move the one under the cursor a place earlier or later, as
## the wheel and the thumbstick do over it. Again with the pointer where it was, the same block goes
## on along the row (not the one that slid in under the pointer). On a held block they move it in
## the held order, and still nothing is asked until it is let go. A refusal (arrange_refusal) is
## said, and the block goes back. Should the sections change under a held block (the host, an
## undo), the hold ends and it goes back.
##
## A chord brick pressed into a block (slice 31, Block.paste_spot_for) writes its row's harmony into
## that section's marker, as the fifths wheel's SET does (Studio.press_brick).
##
## A song with no regions shows MAKE SECTIONS FROM MARKERS: a region for each marker's span that
## names a section (`spans`: brackets alone and sticky notes are not sections), added inside one
## edit, so one undo step.
##
## A guest's rearrangement is an intent carrying the order (DAW.arrange_sections). The guest's row
## shows the order it asked for until the host's regions arrive, or PENDING seconds pass with
## nothing (a refusal the host tells them, Session._arrange_for). One is asked at a time: the host
## applies an order to the sections it has then, so a move made while one is asked is shown, and
## asked of the new sections once the host's answer comes.
##
## Its frame: the band's middle on the table top, +X along the row away from the wheel (left to
## right for the player), +Z toward the player at the near long edge.

const STATION := &"sections"
## How long the row is (m), the gap between blocks, and the most a bar is long.
const ROW := 1.3
const GAP := 0.008
const PER_BAR_MOST := 0.05
## The shortest a block is drawn, however many bars the others have.
const SHORTEST := 0.018
## Each block: this deep, its top sloped up from FRONT high at the player's side to BACK at the
## far side, so its lettering faces the player, its middle ROW_Z toward them from the band's.
const DEPTH := 0.12
const FRONT := 0.03
const BACK := 0.06
const ROW_Z := 0.05
## How far a held block stands above the row, and how far from the row it may be let go and still
## be put in it (m).
const LIFT := 0.05
const OFF_ROW := 0.3
## How long a guest's asked order is shown before the old one comes back (s), and how fast the
## blocks slide to their places (1/s, times motion_scale; at 0 they are there at once).
const PENDING := 3.0
const EASE := 14.0
## A step's block is stepped again while the pointer stays within STILL of where it was along the
## row (m), and forgotten once no block of the row has been under a pointer for LEAVE (s).
const STILL := 0.025
const LEAVE := 0.3
## The plaque's stand, behind the row at the far edge, and how high its top is above the table.
const PLAQUE_Z := -0.15
const PLAQUE_TOP := 0.4
## A block's paint, and the playing one's, lighter: it is also the one with the mark on it.
const UNLIT := Color(0.4, 0.31, 0.21)
const LIT := Color(0.68, 0.58, 0.4)
## The MAKE key's size on the row.
const MAKE_SIZE := Vector2(0.56, 0.1)

## (order: Array) -> String: how a rearrangement is asked for. DAW.arrange_sections unless told
## otherwise (a test's spy).
var arrange: Callable = Callable()

var _blocks: Array[Block] = []
## The region indices in the order the row shows them now.
var _order: Array = []
## The order a guest asked for and the host has not answered, and until when it is shown without
## the answer; and the order the row was moved to since, asked once the answer comes. Region
## indices, as `regions()` has them now.
var _pending: Array = []
var _pending_until := 0.0
var _queued: Array = []
## The regions' names when the row was last built: how a rebuild knows the host answered.
var _names: Array = []
var _clock := 0.0
var _seen := 0
var _seen_regions := 0
## The block a step ([ ], the wheel, the stick) last moved, as its place on the row, and where the
## pointer was along the row (x, NAN when not known) when it did: another step with the pointer
## still there moves that block on, not the one that slid in under the pointer in its place. With
## the sections' names in the order that step asked: once the row shows any other (an undo, someone
## else's move, a guest's ask refused or gone unanswered), it is forgotten.
var _stepped := -1
var _stepped_x := NAN
var _stepped_names: Array = []
var _on_row_at := 0.0
var _make: MakeKey
var _row: Node3D


func _init() -> void:
	name = "SectionBlocks"


func _ready() -> void:
	_row = Node3D.new()
	_row.name = "Row"
	add_child(_row)
	_build_tray()
	_make = MakeKey.new()
	_make.blocks = self
	_make.position = Vector3(0, 0, ROW_Z)
	add_child(_make)
	_hang_plaque()
	_rebuild()


## The tray the row lies in: a low wooden board along the band, with a lip at its back.
func _build_tray() -> void:
	var wood := FifthsWheel._paint(Color(0.3, 0.19, 0.1), 0.6, 0.0, 0.2)
	ZoneKit.block(self, Vector3(ROW + 0.04, 0.008, DEPTH + 0.03), Vector3(0, 0.004, ROW_Z), wood, "Tray")
	ZoneKit.block(self, Vector3(ROW + 0.04, 0.02, 0.012), Vector3(0, 0.01, ROW_Z - DEPTH * 0.5 - 0.021), wood, "Lip")
	# A tick a bar? No: the row's length is the song's, not a ruler's. Its two ends are marked.
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(0.006, 0.012, DEPTH + 0.03), Vector3(side * (ROW * 0.5 + 0.017), 0.014, ROW_Z),
				Materials.brushed_metal(), "End")


## The plaque, stood upright on two rods behind the row, facing the player: its top PLAQUE_TOP above
## the table, so opened to its how-to-play lines its foot is still above the table top.
func _hang_plaque() -> void:
	var plaque := Stations.plaque(STATION)
	plaque.position = Vector3(0, PLAQUE_TOP - float(plaque.get_meta(&"plaque_tall", 0.2)) * 0.5, PLAQUE_Z)
	add_child(plaque)
	# Each rod stops a centimetre under the plate's top edge, into its back, rather than flush with
	# it: flush, the rod's top and the plate's were one plane fighting for the same depth.
	var rod := PLAQUE_TOP - 0.01
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(0.008, rod, 0.008), Vector3(side * (Stations.PLAQUE_WIDTH * 0.5 - 0.03),
				rod * 0.5, PLAQUE_Z - 0.01), Materials.brushed_metal(), "Rod")


# --- the song's sections -----------------------------------------------------------------------

## The regions, as the row has them: MixState.regions, or none.
static func regions() -> Array:
	return DAW.state.regions if DAW.state != null else []


## How many bars region `i` is, through the tempo's and meter's changes.
static func bars_of(i: int) -> float:
	var r: Array = regions()[i]
	return maxf(DAW.state.bar_at(float(r[1])) - DAW.state.bar_at(float(r[0])), 0.0)


## The region's bars as the tape deck counts them, from 1: "bars 9–24".
static func bars_text(i: int) -> String:
	var r: Array = regions()[i]
	var first := floori(DAW.state.bar_at(float(r[0])) + Harmony.BAR_SLACK) + 1
	var last := maxi(first, ceili(DAW.state.bar_at(float(r[1])) - Harmony.BAR_SLACK))
	return "bar %d" % first if last == first else "bars %d–%d" % [first, last]


## The sections MAKE SECTIONS would make, [start, end, name] each: one per marker that names a
## section (Harmony.section_of; a marker that is only brackets sets a key, and a sticky note,
## Harmony.NOTE_PREFIX, is a note), from it to the next one, the last to the song's end.
static func spans(state: MixState) -> Array:
	var out: Array = []
	if state == null:
		return out
	var times: Array = state.markers.keys()
	times.sort()
	var kept: Array = []
	for t in times:
		var said := str(state.markers[t])
		if Harmony.is_note(said) or Harmony.section_of(said).strip_edges() == "":
			continue
		kept.append([float(t), Harmony.section_of(said).strip_edges()])
	var end := song_end(state)
	for k in kept.size():
		var from: float = kept[k][0]
		var to: float = kept[k + 1][0] if k + 1 < kept.size() else maxf(end, state.next_bar_start(from + 0.001))
		if to - from > 0.001:
			out.append([from, to, kept[k][1]])
	return out


## Where the song ends, for the last section: the bar line at or after the last thing on the
## timeline, or the project's length when nothing is.
static func song_end(state: MixState) -> float:
	var last := 0.0
	for index in state.tracks:
		var t: MixState.TrackState = state.tracks[index]
		if not t.items.is_empty():
			last = maxf(last, t.items[-1].end())
	if last <= 0.0:
		return state.project_length
	return state.next_bar_start(last - 0.001)


## MAKE SECTIONS FROM MARKERS: a region for each of `spans`, inside one edit, so one undo step. The
## number made; 0 (and said) when no marker names a section.
func make_sections() -> int:
	var made := spans(DAW.state)
	if made.is_empty():
		Session.notice.emit("No marker names a section: add markers at the sections' starts first.")
		return 0
	DAW.open_edit("make sections")
	for span in made:
		DAW.add_region(span[0], span[1], span[2])
	DAW.close_edit()
	Session.notice.emit("Made %d sections from the markers: %s." % [made.size(), " · ".join(made.map(func(s): return s[2]))])
	return made.size()


# --- the row -----------------------------------------------------------------------------------

## The blocks, in song order (block `i` is region `i`).
func blocks() -> Array[Block]:
	return _blocks


## The order the row shows now: region indices, left to right.
func shown_order() -> Array:
	return _order.duplicate()


## Metres a bar on the row, so the song fills it and no bar is longer than PER_BAR_MOST.
func per_bar() -> float:
	var total := 0.0
	for i in _blocks.size():
		total += bars_of(i)
	if total <= 0.0:
		return PER_BAR_MOST
	return minf(PER_BAR_MOST, (ROW - GAP * maxi(_blocks.size() - 1, 0)) / total)


## How long block `i` is on the row.
func width_of(i: int) -> float:
	return maxf(SHORTEST, bars_of(i) * per_bar())


## Where each block's middle is along the row (x), laid left to right in `order` from the row's
## start: {region index: x}.
func layout(order: Array) -> Dictionary:
	var out := {}
	var widths := order.map(func(i): return width_of(i))
	var total := 0.0
	for w in widths:
		total += w
	total += GAP * maxi(order.size() - 1, 0)
	# Wider than the row only when the shortest blocks add up past it: centred, a little over.
	var x := -maxf(total, ROW) * 0.5 if total > ROW else -ROW * 0.5
	for k in order.size():
		out[order[k]] = x + widths[k] * 0.5
		x += widths[k] + GAP
	return out


## The song order, unchanged: [0, 1, ...].
func song_order() -> Array:
	return range(_blocks.size())


## Rebuilt when the regions, or the bars they are, change: not while one is held, unless the
## regions changed under it (_process).
func _rebuild() -> void:
	for b in _blocks:
		b.queue_free()
		_row.remove_child(b)
	_blocks.clear()
	var regs := regions()
	for i in regs.size():
		var b := Block.new()
		b.blocks = self
		b.index = i
		_row.add_child(b)
		_blocks.append(b)
	var names_were := _names
	_names = regs.map(func(r): return str(r[2]))
	_seen_regions = regs.hash()
	_settle_asked(names_were)
	_order = _base_order()
	_forget_stale_step()
	var at := layout(_order)
	for b in _blocks:
		b.shape_to(width_of(b.index), str(regs[b.index][2]), bars_text(b.index))
		b.place(Vector3(at[b.index], 0, ROW_Z))
	_make.visible = regs.is_empty()
	_make.collision_layer = 2 if regs.is_empty() else 0
	_seen = _signature()


func _signature() -> int:
	var s := DAW.state
	if s == null:
		return 0
	return [s.regions, s.tempo, s.tempo_points, s.time_signature_points, s.beats_per_bar].hash()


## After a rebuild, what a guest asked: answered when the regions' names are now in the asked order,
## and then a move made since is asked, in the new regions' indices. Names unchanged (a tempo, a
## region moved in time) keep it asked; anything else drops it.
func _settle_asked(names_were: Array) -> void:
	if _pending.is_empty():
		_queued = []
		return
	if _names == names_were:
		return
	var answered := _pending.size() == names_were.size() and _names == _pending.map(func(i): return names_were[i])
	var next: Array = _queued.map(func(i): return _pending.find(i)) if answered else []
	_pending = []
	_queued = []
	if not next.is_empty():
		ask(next)


## The order the row shows with nothing held: the one moved to and not yet asked, else the one asked
## and not yet answered, else the song's.
func _base_order() -> Array:
	if not _queued.is_empty():
		return _queued.duplicate()
	if not _pending.is_empty():
		return _pending.duplicate()
	return song_order()


## The stepped block forgotten when the row no longer shows the order that step asked: checked
## against the names in the order shown, so a host's answer in the asked order (the regions renamed,
## the indices new) keeps it, and a row gone back without one forgets it.
func _forget_stale_step() -> void:
	if _stepped >= 0 and _base_order().map(func(i): return _names[i]) != _stepped_names:
		_stepped = -1


## The held block, or null.
func held() -> Block:
	for b in _blocks:
		if b.is_held():
			return b
	return null


func _process(delta: float) -> void:
	_clock += delta
	var holding := held()
	if holding != null and regions().hash() != _seen_regions:
		# The sections changed under the hand (the host, an undo): its index is another region's
		# now, so the hold ends there and the row is the song's.
		Session.notice.emit("The sections changed while %s was held, so it went back." % holding.section)
		_rebuild()
		holding = null
	elif holding == null and _signature() != _seen:
		_rebuild()
	if not _pending.is_empty() and _clock > _pending_until:
		# Unanswered, or refused (a refusal sends no regions): the row goes back to the song's.
		_pending = []
		_queued = []
		_forget_stale_step()
	if _blocks.any(func(b): return b.is_hovered() or b.is_held()):
		_on_row_at = _clock
	elif _clock - _on_row_at > LEAVE:
		_stepped = -1
	if holding != null:
		_order = order_with(holding.index, holding.row_x)
	else:
		_order = _base_order()
	var at := layout(_order)
	var motion := Ergonomics.current.motion_scale
	var k := 1.0 if motion <= 0.0 else clampf(delta * EASE / maxf(motion, 0.05), 0.0, 1.0)
	for b in _blocks:
		if b == holding:
			# Where the hand has it, lifted off the row.
			b.place(Vector3(b.row_x, LIFT, b.row_z))
		else:
			b.place(b.row_at.lerp(Vector3(at[b.index], 0, ROW_Z), k))
	_show_playhead()


## The order with block `index` put in the place nearest `x` along the row, the others in their
## order round it.
func order_with(index: int, x: float) -> Array:
	var others: Array = _base_order()
	others.erase(index)
	var best: Array = []
	var nearest := INF
	for k in others.size() + 1:
		var tried := others.duplicate()
		tried.insert(k, index)
		var d := absf(layout(tried)[index] - x)
		if d < nearest - 0.0001:
			nearest = d
			best = tried
	return best


## Block `index` let go at row position `x`, `z` (its frame): put in the place nearest, or back
## where it was when let go off the row. The order asked for, or [] for none.
func let_go(index: int, x: float, z: float) -> Array:
	if absf(z - ROW_Z) > OFF_ROW:
		return []
	return ask(order_with(index, x))


## The row in `order` (region indices): one rearrangement, or nothing when it is the order now. Said
## when refused. The order asked for, or [] for none.
func ask(order: Array) -> Array:
	if order.size() != _blocks.size():
		return []
	if not Session.is_authority() and not _pending.is_empty():
		# One asked at a time: the host applies an order to the sections it has then, and this is of
		# the sections before its answer. Shown now, and asked of the new ones when it comes.
		_queued = [] if order == _pending else order.duplicate()
		_order = _base_order()
		return order
	if order == song_order():
		return []
	var why: String = arrange.call(order) if arrange.is_valid() else DAW.arrange_sections(order)
	if not why.is_empty():
		Session.notice.emit(why)
		return []
	var names := order.map(func(i): return str(regions()[i][2]))
	if Session.is_authority():
		Session.notice.emit("The sections are now %s." % " · ".join(names))
	else:
		_pending = order.duplicate()
		_pending_until = _clock + PENDING
		_order = _base_order()
		Session.notice.emit("Asked the host for %s." % " · ".join(names))
	return order


## Block `index` a place earlier (`by` -1) or later (1), or more, from where the row shows it: [
## and ], the wheel, the stick. A held block moves in the held order, and nothing is asked until it
## is let go; while one is held no other moves. The order asked for, or [].
func step(index: int, by: int) -> Array:
	if by == 0 or index < 0 or index >= _blocks.size():
		return []
	var holding := held()
	if holding != null and holding.index != index:
		Session.notice.emit("Let go of %s first." % holding.section)
		return []
	var order: Array = order_with(index, holding.row_x) if holding != null else _base_order()
	var from := order.find(index)
	var at := clampi(from + by, 0, order.size() - 1)
	if at == from:
		Session.notice.emit("%s is %s already." % [str(regions()[index][2]), "first" if by < 0 else "last"])
		return []
	order.erase(index)
	order.insert(at, index)
	if holding != null:
		holding.slide_to(layout(order)[index])
		_order = order
		return []
	return ask(order)


## [ or ] on a desktop, the wheel or the stick over a block: the block under the pointer (`at`,
## where it is in the world, null when not known) moved a place. Again with the pointer still where
## it was, the block that step moved goes on: the one beside it has slid in under the pointer, and a
## second ] walks the same block along rather than swapping that one back. Whether `control` was
## one of the row's.
func step_under(control: Object, by: int, at: Variant = null) -> bool:
	var b := control as Block
	if b == null or b.blocks != self:
		return false
	if held() != null:
		step(b.index, by)
		return true
	var x: float = to_local(at).x if at is Vector3 else NAN
	var place := _order.find(b.index)
	# The row as the song is now: a step this frame has already changed the regions.
	if _signature() != _seen:
		_rebuild()
	if _stepped >= 0 and (is_nan(x) or is_nan(_stepped_x) or absf(x - _stepped_x) <= STILL):
		place = _stepped
	if place < 0 or place >= _order.size():
		return true
	var index: int = _order[place]
	var asked := step(index, by)
	if not asked.is_empty():
		_stepped = asked.find(index)
		_stepped_x = x
		_stepped_names = asked.map(func(i): return _names[i])
		_on_row_at = _clock
	return true


## The block the playhead is in, lit, with the mark at the playhead: a bar at a time at motion 0.
func playing_index() -> int:
	return DAW.state.region_at(DAW.state.position_seconds) if DAW.state != null else -1


## How far through block `i` the playhead is shown (0..1).
func mark_fraction(i: int) -> float:
	var s := DAW.state
	var r: Array = regions()[i]
	var bars := bars_of(i)
	if bars <= 0.0:
		return 0.0
	var into := s.bar_at(s.position_seconds) - s.bar_at(float(r[0]))
	if Ergonomics.current.motion_scale <= 0.0:
		into = floorf(into + Harmony.BAR_SLACK)
	return clampf(into / bars, 0.0, 1.0)


func _show_playhead() -> void:
	var now := playing_index()
	for b in _blocks:
		b.show_playing(b.index == now, mark_fraction(b.index) if b.index == now else 0.0)


## One section of the song: a block as long as its bars, lettered with its name and its bars, its
## own control (a hover card, a grab, a nudge). Its frame's +Z is up, so a held ray moves it along
## the table (Interactor._plane_point); what it shows is under `Look`, in the row's frame.
class Block extends ControlAffordance:
	var blocks: SectionBlocks
	var index := 0
	## Where it is on the row now (the row's frame), and where the hand has it while held.
	var row_at := Vector3.ZERO
	var row_x := 0.0
	var row_z := 0.0
	var width := 0.1
	## Its region's name, as lettered.
	var section := ""
	## Where the pointer that nudged it was on it (world), or null.
	var _nudged_at: Variant = null
	var _look: Node3D
	var _shape: CollisionShape3D
	var _body: MeshInstance3D
	var _paint: StandardMaterial3D
	var _name: Label3D
	var _bars: Label3D
	var _mark: MeshInstance3D
	var _grab_off := 0.0
	var _playing := false
	## Up as +Z: a turn about X, and back for what it shows.
	const UP := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		basis = UP
		_shape = CollisionShape3D.new()
		_shape.shape = BoxShape3D.new()
		add_child(_shape)
		_look = Node3D.new()
		_look.name = "Look"
		_look.basis = UP.inverse()
		add_child(_look)
		_body = MeshInstance3D.new()
		_body.name = "Body"
		_paint = FifthsWheel._paint(SectionBlocks.UNLIT, 0.55)
		_body.material_override = _paint
		_look.add_child(_body)
		var slope := Basis(Vector3.RIGHT, Vector3(0, BACK - FRONT, -DEPTH).normalized(),
				Vector3(0, DEPTH, BACK - FRONT).normalized())
		var mid_y := (FRONT + BACK) * 0.5
		_name = _letter(96, Color(0.08, 0.06, 0.04))
		_name.transform = Transform3D(slope, Vector3(0, mid_y + (BACK - FRONT) * 0.12, -DEPTH * 0.12) + slope.z * 0.0015)
		_bars = _letter(56, Color(0.2, 0.15, 0.1))
		_bars.transform = Transform3D(slope, Vector3(0, mid_y - (BACK - FRONT) * 0.28, DEPTH * 0.28) + slope.z * 0.0015)
		# The playhead's mark: a bright bar across the top, front to back, standing a little proud.
		_mark = MeshInstance3D.new()
		_mark.name = "Mark"
		var m := BoxMesh.new()
		m.size = Vector3(0.004, 0.016, DEPTH + 0.006)
		_mark.mesh = m
		_mark.basis = Basis(Vector3.RIGHT, atan2(BACK - FRONT, DEPTH))
		_mark.position = Vector3(0, mid_y + 0.004, 0)
		_mark.material_override = ZoneKit.glow(Color(1.0, 0.78, 0.4), 2.0)
		_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mark.visible = false
		_look.add_child(_mark)

	func _letter(size: int, colour: Color) -> Label3D:
		var l := Label3D.new()
		l.font_size = size
		l.pixel_size = 0.00025
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.modulate = colour
		l.double_sided = false
		Lettering.range_to_legibility(l)
		l.outline_size = 0
		_look.add_child(l)
		return l

	## `length` long on the row, lettered `title` and `bars`.
	func shape_to(length: float, title: String, bars: String) -> void:
		width = length
		section = title
		_body.mesh = SectionBlocks.wedge(length, DEPTH, FRONT, BACK)
		(_shape.shape as BoxShape3D).size = Vector3(length, DEPTH, BACK)
		_shape.position = Vector3(0, 0, BACK * 0.5)
		_name.text = title.to_upper()
		_name.autowrap_mode = TextServer.AUTOWRAP_OFF
		Lettering.fit(_name, length - 0.012, 96, 24)
		_name.outline_size = 0
		_bars.text = bars
		Lettering.fit(_bars, length - 0.01, 56, 20)
		_bars.outline_size = 0
		name = "Block%d" % (index + 1)

	## Stood at `at` on the row (its frame).
	func place(at: Vector3) -> void:
		row_at = at
		position = at

	## Lit and marked as the playhead's, the mark `fraction` of the way along; else plain.
	func show_playing(on: bool, fraction: float) -> void:
		_mark.visible = on
		if on:
			_mark.position.x = lerpf(-width * 0.5 + 0.003, width * 0.5 - 0.003, fraction)
		if on == _playing:
			return
		_playing = on
		# Lighter paint, not a glow: a glow blooms over its own lettering.
		_paint.albedo_color = SectionBlocks.LIT if on else SectionBlocks.UNLIT

	## Whether the playhead's mark is on it, and where along it (0..1 of its length).
	func marked() -> bool:
		return _mark != null and _mark.visible

	func mark_x() -> float:
		return _mark.position.x

	func lit() -> bool:
		return _playing

	## Held, moved along the row to `x` by a step: the hand's hold goes on from there.
	func slide_to(x: float) -> void:
		_grab_off += x - row_x
		row_x = x

	func _default_title() -> String:
		return "SECTIONS  %s" % str(SectionBlocks.regions()[index][2]).to_upper() if index < SectionBlocks.regions().size() else "SECTIONS"

	func _default_readout() -> String:
		if blocks == null or index >= SectionBlocks.regions().size():
			return ""
		var shown := blocks.shown_order()
		var place := shown.find(index) + 1
		var said := "%s · %d bars · %d of %d" % [SectionBlocks.bars_text(index), roundi(SectionBlocks.bars_of(index)),
				place, shown.size()]
		if is_held():
			said = "to place %d: %s" % [place, " · ".join(shown.map(func(i): return str(SectionBlocks.regions()[i][2])))]
		return said

	func hint() -> String:
		return "drag along the row to move it, the others make room  ·  [ or ] or the wheel moves it a place  ·  let go to rearrange the song, one undo step"

	## A chord brick pressed into it (docs/spatial_loop.md part two, slice 31) writes the harmony of
	## its row into this section: [ChordBrick.SECTION, the section's start]. Nothing else pastes here.
	func paste_spot_for(item: Item, _at: Vector3, _fine: bool) -> Array:
		if not (item is ChordBrick) or index >= SectionBlocks.regions().size():
			return []
		return [ChordBrick.SECTION, float(SectionBlocks.regions()[index][0])]

	func _on_grab_begin(at: Vector3) -> void:
		var p := blocks.to_local(at)
		_grab_off = row_at.x - p.x
		row_x = row_at.x
		row_z = row_at.z
		blocks._stepped = -1

	func _on_grab_move(at: Vector3) -> void:
		var p := blocks.to_local(at)
		row_x = p.x + _grab_off
		row_z = p.z

	func _on_grab_end() -> void:
		# Not when the row was rebuilt under the hand: its index is another region's now.
		if self in blocks.blocks():
			blocks.let_go(index, row_x, row_z)

	## The wheel's or the stick's: where its pointer is, so a second notch walks the same block on.
	func nudge(by: Node, notches: int, fine: bool) -> bool:
		_nudged_at = (by as Interactor).hover_point if by is Interactor else null
		return super(by, notches, fine)

	func _on_nudge(notches: int, _fine: bool) -> bool:
		blocks.step_under(self, signi(notches), _nudged_at)
		return true


## MAKE SECTIONS FROM MARKERS: a dark key lying in the empty row, while the song has no regions.
class MakeKey extends ControlAffordance:
	var blocks: SectionBlocks

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		name = "MakeSections"
		basis = Block.UP
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(MAKE_SIZE.x, MAKE_SIZE.y, 0.03)
		shape.shape = box
		shape.position = Vector3(0, 0, 0.015)
		add_child(shape)
		var look := Node3D.new()
		look.basis = Block.UP.inverse()
		add_child(look)
		var cap := MeshInstance3D.new()
		cap.mesh = SectionBlocks.wedge(MAKE_SIZE.x, MAKE_SIZE.y, 0.018, 0.034)
		cap.material_override = FifthsWheel._paint(Color(0.16, 0.12, 0.08), 0.4, 0.5)
		look.add_child(cap)
		var l := Label3D.new()
		l.text = "MAKE SECTIONS\nFROM MARKERS"
		l.font_size = 96
		l.pixel_size = 0.00025
		l.modulate = Color(0.95, 0.9, 0.78)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.double_sided = false
		Lettering.range_to_legibility(l)
		l.basis = Basis(Vector3.RIGHT, Vector3(0, 0.016, -MAKE_SIZE.y).normalized(), Vector3(0, MAKE_SIZE.y, 0.016).normalized())
		l.position = Vector3(0, 0.0275, 0)
		look.add_child(l)

	func _default_title() -> String:
		return "SECTIONS  MAKE FROM MARKERS"

	func _default_readout() -> String:
		var made := SectionBlocks.spans(DAW.state)
		if made.is_empty():
			return "no marker names a section yet"
		return "%d sections: %s" % [made.size(), " · ".join(made.map(func(s): return s[2]))]

	func hint() -> String:
		return "press to make a region of each marker's span, as one undo step"

	func dwell_activates() -> bool:
		return true

	func _on_grab_begin(_at: Vector3) -> void:
		if blocks != null:
			blocks.make_sections()


## A block `length` long and `depth` deep, standing on y 0 with its middle at x 0 and z 0, its top
## sloped from `front` high at +Z to `back` high at -Z.
static func wedge(length: float, depth: float, front: float, back: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := length * 0.5
	var hz := depth * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return Vector3(x, y, z)
	var bfl: Vector3 = p.call(-hx, 0.0, hz)
	var bfr: Vector3 = p.call(hx, 0.0, hz)
	var bbl: Vector3 = p.call(-hx, 0.0, -hz)
	var bbr: Vector3 = p.call(hx, 0.0, -hz)
	var tfl: Vector3 = p.call(-hx, front, hz)
	var tfr: Vector3 = p.call(hx, front, hz)
	var tbl: Vector3 = p.call(-hx, back, -hz)
	var tbr: Vector3 = p.call(hx, back, -hz)
	var top := Vector3(0, depth, back - front).normalized()
	_face(st, [tfl, tbl, tbr, tfr], top)
	_face(st, [bfl, tfl, tfr, bfr], Vector3.BACK)
	_face(st, [bbr, tbr, tbl, bbl], Vector3.FORWARD)
	_face(st, [bbl, tbl, tfl, bfl], Vector3.LEFT)
	_face(st, [bfr, tfr, tbr, bbr], Vector3.RIGHT)
	_face(st, [bfl, bfr, bbr, bbl], Vector3.DOWN)
	return st.commit()


## Corners in clockwise order as seen from the side the face faces (Godot's front).
static func _face(st: SurfaceTool, corners: Array, normal: Vector3) -> void:
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.add_vertex(corners[k])
