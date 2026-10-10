class_name TourHud
extends CanvasLayer

## The run's own HUD: the brief card, a live score and countdown, and the draft (pick 1 of 3)
## once a brief is cleared. Tour's own presentation, not the studio's -- instantiated by
## scenes/bootstrap.gd the way SessionPanel is, so scenes/studio.gd never holds UI code.
##
## Shown only while a run is under way. Reads `Tour.run` rather than `Session.tour` directly:
## that is the one place a run's state is correct on BOTH sides -- live on the host, rebuilt
## from the wire on a guest (core/tour/tour.gd's `_on_tour_changed`) -- and it is refreshed from
## every signal either side ever sees it change on: `Tour`'s own (host) and
## `Session.tour_changed` (guest).
##
## Desktop-first, mouse-clickable, per the brief: a CanvasLayer of ordinary Controls, exactly
## the technique `SessionPanel` already ships to every medium, so nothing extra is needed for a
## headset to see it too.

const INK := Color(0.92, 0.94, 0.97)
const DIM := Color(0.62, 0.66, 0.74)
const CARD := Color(0.06, 0.05, 0.035, 0.95)
const ACCENT := Color(0.95, 0.65, 0.18)
const CURSE := Color(0.82, 0.33, 0.33)
const EDGE := Color(1, 1, 1, 0.08)
const WIDTH := 460.0

var _root: PanelContainer
var _title: Label
var _flavour: Label
var _clock: Label
var _score: Label
var _tag: Label
var _flaws_box: VBoxContainer
var _drawn_flaws: Array[StringName] = []
var _parts_edge: ColorRect
var _parts_box: VBoxContainer
var _drawn_parts: Array[StringName] = []
var _draft_box: HBoxContainer
var _drawn_draft: Array[StringName] = []


func _ready() -> void:
	layer = 19
	_build()
	Tour.run_started.connect(_refresh)
	Tour.brief_started.connect(_on_brief_started)
	Tour.brief_ended.connect(_on_brief_ended)
	Tour.drafting_started.connect(_on_drafting_started)
	Tour.run_ended.connect(_on_run_ended)
	Session.tour_changed.connect(_refresh)
	_refresh()


func _on_brief_started(_index: int) -> void:
	_refresh()


func _on_brief_ended(_passed: bool, _score: int, _detail: PackedStringArray) -> void:
	_refresh()


func _on_drafting_started(_cards: Array) -> void:
	_refresh()


func _on_run_ended(_won: bool) -> void:
	_refresh()


func _process(_delta: float) -> void:
	if not _root.visible:
		return
	_refresh_clock()
	# A fix lands mid-brief without a signal of its own (the host ticks `run.fixed` every
	# physics frame, and only publishes to the network when it changes) -- cheap enough, a
	# handful of labels, to just read it here every frame rather than add one.
	var run := Tour.run
	if run != null and run.state == TourRun.State.BRIEF and not run.tuning:
		_refresh_flaws(run)
		_refresh_parts(run)


func _build() -> void:
	_root = PanelContainer.new()
	_root.name = "TourHud"
	_root.add_theme_stylebox_override("panel", _box(CARD, 14, 18))
	_root.anchor_left = 0.5
	_root.anchor_right = 0.5
	_root.offset_left = -WIDTH * 0.5
	_root.offset_right = WIDTH * 0.5
	_root.offset_top = 20
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_root.add_child(column)

	_title = _label("", 20, INK)
	column.add_child(_title)
	_flavour = _label("", 13, DIM)
	_flavour.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_flavour)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)
	_score = _label("", 15, ACCENT)
	row.add_child(_score)
	_clock = _label("", 15, INK)
	row.add_child(_clock)

	_tag = _label("", 10, DIM)
	column.add_child(_tag)

	_flaws_box = VBoxContainer.new()
	_flaws_box.name = "Flaws"
	_flaws_box.add_theme_constant_override("separation", 2)
	column.add_child(_flaws_box)

	_parts_edge = ColorRect.new()
	_parts_edge.color = EDGE
	_parts_edge.custom_minimum_size = Vector2(0, 1)
	_parts_edge.visible = false
	column.add_child(_parts_edge)
	_parts_box = VBoxContainer.new()
	_parts_box.name = "Parts"
	_parts_box.add_theme_constant_override("separation", 2)
	column.add_child(_parts_box)

	_draft_box = HBoxContainer.new()
	_draft_box.name = "Draft"
	_draft_box.add_theme_constant_override("separation", 10)
	_draft_box.visible = false
	column.add_child(_draft_box)


func _refresh() -> void:
	var run := Tour.run
	_root.visible = run != null
	if run == null:
		_drawn_draft = []
		_drawn_flaws = []
		_drawn_parts = []
		return
	var brief := TourBriefs.brief(run.brief_index)
	_title.text = ("BOSS: " if brief.is_boss else "") + brief.title
	_flavour.text = brief.flavour
	_score.text = "SCORE %d" % run.score
	_refresh_clock()
	_tag.visible = run.state == TourRun.State.BRIEF
	_flaws_box.visible = run.state == TourRun.State.BRIEF
	if run.state == TourRun.State.BRIEF and run.flaws != _drawn_flaws:
		_build_flaws(run)
	elif run.state == TourRun.State.BRIEF:
		_refresh_flaws(run)
	var showing_parts := run.state == TourRun.State.BRIEF and not run.parts.is_empty()
	_parts_box.visible = showing_parts
	_parts_edge.visible = showing_parts
	if run.state == TourRun.State.BRIEF and run.parts != _drawn_parts:
		_build_parts(run)
	elif run.state == TourRun.State.BRIEF:
		_refresh_parts(run)
	var drafting := run.state == TourRun.State.DRAFTING
	_draft_box.visible = drafting
	if drafting and run.draft != _drawn_draft:
		_build_draft(run.draft)


func _refresh_clock() -> void:
	var run := Tour.run
	if run == null or run.state != TourRun.State.BRIEF:
		_clock.text = ""
		return
	_clock.text = "SOUNDCHECK" if run.tuning else "%d s" % int(ceil(run.seconds_left))


## One line per flaw, rebuilt only when the set of flaws changes (a new brief): a fixed/not-fixed
## mark, the strip to go to, and the flaw's own line, in ACCENT once fixed and INK until then.
## The old labels leave the tree before the new ones arrive: queued alone, a stale "Flaw0" would
## still be a child when the new "Flaw0" is added, Godot would rename the newcomer, and
## `_refresh_flaws` would go on writing into a label about to be freed -- the second brief's
## lines never showing.
func _build_flaws(run: TourRun) -> void:
	_drawn_flaws = run.flaws.duplicate()
	for child in _flaws_box.get_children():
		_flaws_box.remove_child(child)
		child.queue_free()
	var size := _line_font_size(run)
	for i in run.flaws.size():
		var flaw := TourFlaws.by_id(run.flaws[i])
		if flaw == null:
			continue
		var l := _label("", size, INK)
		l.name = "Flaw%d" % i
		_flaws_box.add_child(l)
	_refresh_flaws(run)


## Also the "x / y FIXED" tag (and, once there are parts to hold, "x / y PARTS" beside it): the
## host's `_tick_flaws`/`_tick_parts` publish to the room without a local signal of their own, so
## this is the one place both counts are kept current on both sides.
func _refresh_flaws(run: TourRun) -> void:
	var tag := "BAND OF %d   %d / %d FIXED" % [run.band_size, run.fixed.count(true), run.flaws.size()]
	if not run.parts.is_empty():
		tag += "   %d / %d PARTS" % [run.played.count(true), run.parts.size()]
	_tag.text = tag
	for i in run.flaws.size():
		var flaw := TourFlaws.by_id(run.flaws[i])
		if flaw == null:
			continue
		var l := _flaws_box.get_node_or_null("Flaw%d" % i) as Label
		if l == null:
			continue
		var done: bool = i < run.fixed.size() and run.fixed[i]
		l.text = "%s  %s" % ["OK " if done else "--", flaw_line(flaw, run)]
		l.add_theme_color_override("font_color", ACCENT if done else INK)


## "LEAD VOX: The lead vocal is buried..." -- the strip to walk to, then the line. A flaw with no
## track of its own (the kicked tempo) points at the deck. So the band can read, in the first
## seconds, where each of them is going.
static func flaw_line(flaw: TourFlaw, run: TourRun) -> String:
	var where := flaw.track.to_upper() if not flaw.track.is_empty() else "DECK"
	return "%s: %s" % [where, flaw.line_for(run)]


## Rebuilt only when the set of parts changes (a new brief), same reasoning and the same
## stale-label care as `_build_flaws`.
func _build_parts(run: TourRun) -> void:
	_drawn_parts = run.parts.duplicate()
	for child in _parts_box.get_children():
		_parts_box.remove_child(child)
		child.queue_free()
	var size := _line_font_size(run)
	for i in run.parts.size():
		var part := TourParts.by_id(run.parts[i])
		if part == null:
			continue
		var l := _label("", size, DIM)
		l.name = "Part%d" % i
		_parts_box.add_child(l)
	_refresh_parts(run)


## "ADA  TAMBOURINE: strike it on 2 and 4 .. 3/8" -- who holds it (or "OPEN", nobody has),
## what the band is told, then the on-grid count against what is needed. This player's own line
## says "YOU" in INK, so a job is found at a glance on a card of eight lines; everyone else's is
## DIM while held and not yet played. CURSE while open (a job the band is not doing), ACCENT once
## it has cleared.
func _refresh_parts(run: TourRun) -> void:
	for i in run.parts.size():
		var part := TourParts.by_id(run.parts[i])
		if part == null:
			continue
		var l := _parts_box.get_node_or_null("Part%d" % i) as Label
		if l == null:
			continue
		var holder: int = run.holders[i] if i < run.holders.size() else 0
		var done: bool = i < run.played.size() and run.played[i]
		var hits: int = run.hits[i] if i < run.hits.size() else 0
		var mine := holder > 0 and holder == Session.local_peer_id
		var who := "OPEN" if holder <= 0 else ("YOU" if mine else Session.name_of(holder).to_upper())
		l.text = "%s  %s  %s" % [who, part.line, part.progress_line(hits)]
		var colour := ACCENT if done else (CURSE if holder <= 0 else (INK if mine else DIM))
		l.add_theme_color_override("font_color", colour)


## 12 while there is room, 11 once flaws and parts together would crowd the card (the max today,
## 5 flaws + 3 parts, already needs it).
static func _line_font_size(run: TourRun) -> int:
	return 11 if run.flaws.size() + run.parts.size() > 6 else 12


## Three clickable cards, one per `draft` id: the host applies the pick at once
## (`Tour.pick_draft`); a guest asks for it (`Session.ask_tour`) and waits for the host's word,
## which arrives as the next `Session.tour_changed` -- there is nothing here to predict.
func _build_draft(draft: Array[StringName]) -> void:
	_drawn_draft = draft.duplicate()
	for child in _draft_box.get_children():
		child.queue_free()
	var all := TourDeck.all_cards()
	for index in draft.size():
		var id: StringName = draft[index]
		var card: TourCard = null
		for c in all:
			if c.id == id:
				card = c
				break
		if card == null:
			continue
		_draft_box.add_child(_draft_card(card, index))


func _draft_card(card: TourCard, index: int) -> Control:
	var tint := CURSE if card.is_curse else ACCENT
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(tint, 0.14), 10, 14, Color(tint, 0.6)))
	box.custom_minimum_size = Vector2(130, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	box.add_child(column)
	var kind := _label("CURSE" if card.is_curse else "BOON", 10, tint)
	column.add_child(kind)
	column.add_child(_label(card.title, 14, INK))
	var desc := _label(card.description, 11, DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(120, 0)
	column.add_child(desc)
	var button := Button.new()
	button.text = "Pick"
	button.custom_minimum_size = Vector2(0, 30)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(func() -> void: _pick(index))
	column.add_child(button)
	return box


func _pick(index: int) -> void:
	if Session.is_authority():
		Tour.pick_draft(index)
	else:
		Session.ask_tour(&"draft_pick", [index])


func _box(colour: Color, radius: int, pad: int, edge := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad * 0.6 if pad > 0 else 0
	box.content_margin_bottom = pad * 0.6 if pad > 0 else 0
	if edge.a > 0.0:
		box.set_border_width_all(1)
		box.border_color = edge
	box.anti_aliasing = true
	return box


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
