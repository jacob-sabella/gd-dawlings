class_name TimelineDeck
extends Node3D

## The tools under the arrangement: two rows of glass tokens standing in the air on ledges of
## light, no panel behind them.
##
##   TOOLS   undo, redo · split, duplicate, delete, select all · zoom out, in, fit ·
##           lanes, shelves, road · save
##   PAGES   item, track, tempo, render  then the tokens and rails of the page whose tab is lit
##
## Each a token with a sculpted mark (see GlyphKey) rather than a key with a word on it: the
## timeline is a thing in the room and so are its tools. Only one page's controls at a time: the
## page follows what was last pressed (an item on the lanes brings up ITEM, a track's name
## TRACK), and a tab brings up any page by hand.
##
## Not framed with the arrangement (TimelineSurface.content_aabb), so the tools do not shrink the
## lanes on a monitor: they hang under them. Narrower than the arrangement, from its left edge,
## because its bottom right corner is over the tape deck's tempo knob.

## Of the arrangement's width, the most the deck takes, from its left edge.
const SHARE := 0.80
const MARGIN := 0.006
const ROW_GAP := 0.010
const KEY_GAP := 0.006
const GROUP_GAP := 0.018
## Between the tabs and the page they show.
const TAB_GAP := 0.026

## The TimelineSurface. Typed loosely so the files load in any order.
var surface: Node
## How wide the deck may be, set by the surface before `layout`.
var width := 0.6
## How tall it came out, after `layout`.
var height := 0.0

var tools: Array[Node3D] = []
var _tool_breaks: Array[int] = []
var pages: Array[TimelinePage] = []
var tabs: Array[GlyphKey] = []
var shown_page: TimelinePage = null

## The ledges the rows stand on, one a row, and the seam of light between tabs and page.
var _ledges: Array[MeshInstance3D] = []
var _seam: MeshInstance3D
var _laid_out := false


func _ready() -> void:
	_seam = MeshInstance3D.new()
	_seam.name = "Seam"
	_seam.mesh = BoxMesh.new()
	_seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_seam)
	DAW.timeline_changed.connect(_on_timeline_changed)


## A key for the tools row. `group` starts a new group before it.
func add_tool(key: Node3D, group := false) -> void:
	if group and not tools.is_empty():
		_tool_breaks.append(tools.size())
	tools.append(key)
	if key.get_parent() == null:
		add_child(key)


func add_page(page: TimelinePage) -> void:
	page.surface = surface
	pages.append(page)
	add_child(page)
	var tab := GlyphKey.new()
	tab.name = "Tab" + page.tab_name.capitalize().replace(" ", "")
	tab.toggle = true
	tab.glyph = page.tab_glyph
	tab.label = page.tab_name
	tab.led_colour = Color(0.55, 0.72, 1.0)
	tab.describe_title = func() -> String: return page.tab_name
	tab.describe_value = func(_v: float) -> String:
		return page.notice if page.notice != "" else "its tools"
	tab.pressed.connect(show_page.bind(page))
	add_child(tab)
	tabs.append(tab)
	if shown_page == null:
		show_page(page)
	else:
		page.visible = false
		_reach(page, false)


## That page's controls in the deck, and its tab lit.
func show_page(page: TimelinePage) -> void:
	if page == shown_page and _laid_out:
		return
	shown_page = page
	for p in pages:
		p.visible = p == page
		_reach(p, p == page)
	for i in tabs.size():
		tabs[i].lit = pages[i] == page
	page.refresh()
	layout()


func page_named(tab_name: String) -> TimelinePage:
	for p in pages:
		if p.tab_name == tab_name:
			return p
	return null


func _reach(page: TimelinePage, on: bool) -> void:
	for c in page.controls():
		c.set("reachable", on)


var _had_selection := false


## An item pressed on the lanes is what the next press is most likely for: its page comes up.
func _on_timeline_changed() -> void:
	var any: bool = not DAW.state.selected_items().is_empty()
	if any and not _had_selection:
		var items := page_named("ITEM")
		if items != null:
			show_page(items)
	_had_selection = any


## Lays the rows out from the deck's top left corner, which is its origin.
func layout() -> void:
	_laid_out = true
	var right := width - MARGIN
	var pitch := GlyphKey.SIZE + ROW_GAP
	var y := -MARGIN - GlyphKey.SIZE * 0.5
	var rows: Array = [[MARGIN, y, MARGIN]]
	# The tools, wrapping onto another row when the deck is narrow.
	var x := MARGIN
	for i in tools.size():
		var w: float = tools[i].call("width")
		if i in _tool_breaks:
			x += GROUP_GAP - KEY_GAP
		if x + w > right and x > MARGIN:
			x = MARGIN
			y -= pitch
			rows.append([MARGIN, y, MARGIN])
		tools[i].position = Vector3(x + w * 0.5, y, 0.0)
		x += w + KEY_GAP
		rows[-1][2] = x - KEY_GAP
	y -= pitch + ROW_GAP * 0.6
	# The tabs, then the page.
	x = MARGIN
	rows.append([MARGIN, y, MARGIN])
	for tab in tabs:
		var w := tab.width()
		tab.position = Vector3(x + w * 0.5, y, 0.0)
		x += w + KEY_GAP
	var page_left := x - KEY_GAP + TAB_GAP
	_seam.position = Vector3(page_left - TAB_GAP * 0.5, y, 0.003)
	(_seam.mesh as BoxMesh).size = Vector3(0.0012, GlyphKey.SIZE * 0.8, 0.0012)
	_seam.material_override = Materials.led(Color(0.55, 0.72, 1.0), true)
	x = page_left
	rows[-1][2] = x
	if shown_page != null:
		for c in shown_page.controls():
			var w: float = c.call("width")
			if shown_page.breaks_before(c):
				x += GROUP_GAP - KEY_GAP
			if x + w > right and x > page_left:
				x = page_left
				y -= pitch
				rows.append([page_left, y, page_left])
			c.position = Vector3(x + w * 0.5, y, 0.0)
			x += w + KEY_GAP
			rows[-1][2] = x - KEY_GAP
	height = -(y - GlyphKey.SIZE * 0.5) + MARGIN
	_place_ledges(rows)


## A ledge of smoked glass under each row, lit along its front edge: what the tokens stand on.
func _place_ledges(rows: Array) -> void:
	while _ledges.size() < rows.size():
		var ledge := MeshInstance3D.new()
		ledge.mesh = BoxMesh.new()
		ledge.material_override = GlyphKey.puck_finish()
		ledge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lip := MeshInstance3D.new()
		lip.name = "Lip"
		lip.mesh = BoxMesh.new()
		lip.material_override = Materials.led(Color(0.40, 0.55, 0.85), true)
		lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ledge.add_child(lip)
		add_child(ledge)
		_ledges.append(ledge)
	for i in _ledges.size():
		var ledge := _ledges[i]
		ledge.visible = i < rows.size()
		if not ledge.visible:
			continue
		var from: float = rows[i][0] - 0.004
		var to: float = rows[i][2] + 0.004
		var y: float = rows[i][1] - GlyphKey.SIZE * 0.5 - 0.0016
		(ledge.mesh as BoxMesh).size = Vector3(maxf(to - from, 0.01), 0.0022, 0.022)
		ledge.position = Vector3((from + to) * 0.5, y, 0.002)
		var lip := ledge.get_node("Lip") as MeshInstance3D
		# Short of the ledge's ends, whose planes its own would share.
		(lip.mesh as BoxMesh).size = Vector3(maxf(to - from - 0.002, 0.008), 0.0007, 0.0007)
		lip.position = Vector3(0, 0.0004, 0.011)
