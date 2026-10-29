class_name WelcomeCard
extends CanvasLayer

## What someone opening dawlings for the first time needs to make a sound, record and play with
## friends, and where every instrument is, on one card of pages. Shown once, on a sent-out build's
## first launch (`first_time`), and again with F1 whenever it is wanted.
##
## The pages (PAGES, docs/spatial_loop.md part two): START, the few things everything else rests
## on (F2's 2D view, the precise way into everything; Ctrl-Z; B to split); PLAY, made from
## Stations, one page an area (PLAY · HELD, then CONTROL ROOM, LIVE ROOM and THIS VENUE for the
## stations that stand in this venue), each line a station's title and its desk line; TOGETHER,
## playing with friends; and ROOM, getting about and the room's own keys. A PLAY area too long for
## one page runs on to numbered pages (`PLAY · LIVE ROOM 2/2`), each measured to fit (FIT), so the
## card grows with the stations rather than off the screen.
##
## While open it holds the keyboard focus, so the walker stands still (Walker walks only with no
## focus owner) and no key reaches the studio, but for F2: the 2D view hears it first, and its
## opening puts the card away (scenes/bootstrap.gd). Left and Right, Page Up and Page Down, or the wheel
## turn the page. A click on a page's name goes to that page; a click on a PLAY line closes the
## card and walks there (`studio.go_to_station`); a click anywhere else, Esc or F1 puts it away.
## The line under the cursor is marked with an arrow, not only by the pointer.
##
## Not shown on runs from the editor, which are the tests', the probes' and the screenshots', unless
## asked for with --welcome.

const SEEN := "user://welcome_seen"
const TEXT := Color(0.92, 0.9, 0.84)
const DIM := Color(0.62, 0.64, 0.68)
const ACCENT := Color(0.88, 0.74, 0.44)
## Where each kind of thing carried is kept, as PLAY · HELD says under its heading: not all on
## the shelf, so a desktop player looking for a bell does not look there.
const HELD_HOMES := "Carried, not stood anywhere. The keytar, shaker and tambourine: on the prop shelf by the left wall. The handbells: on their stand beside the harp. The fingertips and the jacks: always on you."
## The most a page may measure: a 1600x900 window less a 28 px margin on every side.
const FIT := Vector2(1600 - 2 * 28, 900 - 2 * 28)
## How wide a line's words run before they wrap (px at text scale 1).
const WRAP := 660
## The sections, in order. PLAY is generated from Stations, a page an area.
const PAGES := ["START", "PLAY", "TOGETHER", "ROOM"]
const PLAY := "PLAY"

const START := [
	["Play the song", "PLAY on the tape deck, to your right. Drag along the top band of the timeline to loop a stretch."],
	["Look and move", "Right-drag looks, WASD walks. F brings you to the gear you are looking at, Shift-F back again."],
	["Change things", "Click, drag or scroll any control. Hover over it first to see what it does."],
	["Automation", "While the song plays, a bead rises over the control you point at: drag it up and down to write its automation, one undo a loop. In a headset, pinch it."],
	["The 2D view", "F2 opens the whole mix as a flat DAW: the precise way into everything the room does, and back."],
	["Undo", "Ctrl-Z undoes and Ctrl-Shift-Z redoes, from anywhere in the room: a whole drag at a time, however much it moved. Or turn the crank on the tape deck's left reel, a notch a step: stopped, it plays you two bars as it was."],
	["Record", "Press a channel's red key to arm it, then REC on the tape deck. B splits the selected items at the playhead."],
	["Your keys and mic", "M opens the session panel: \"Play with the computer keys\", \"Open MIDI\", your microphone."],
	["Instruments", "I walks to each instrument in turn, Shift-I back; the PLAY pages and the board left of the desk name them all. Esc, or BACK on a plaque, comes back to the desk."],
]
const TOGETHER := [
	["Host", "M, then \"Host a session\". Others on this network see it; \"Open to internet\" for everyone else."],
	["Join", "M, then a session ON THIS NETWORK, or an address under JOIN BY ADDRESS, and its code if it has one."],
	["Hear the mix", "As a guest, \"Hear the mix\" in the session panel plays the host's mix to you."],
	["Into their takes", "\"Record when the host records\" puts your keys and your mic on the host's tracks."],
	["Hand it over", "Carrying a cassette (a clip dragged off the timeline's edge), click a bandmate to give it to them. In a headset, hold it by their glove."],
	["Paste it", "Carrying a cassette, click a timeline lane to paste its clip there, on the beat (Shift: anywhere), or a channel strip or stage voice for that track at the playhead. It stays in your hand to paste again; Ctrl-Z takes it back."],
	["Listen to it", "Carrying a cassette, hold L to hear its clip in your ears alone, the room 10 dB down. In a headset, hold it to your ear."],
	["Sample it", "At the SAMPLER by the cassette rack, click REC, then squeeze, click or shake what you carry, do a yo-yo or card trick, or bounce the ball: that one sound is a WAV and a cassette on the rack, whoever's REC it was."],
	["Scratch it", "Click a cassette into the slot of the PLATTER on the tape deck's cart, then drag round the record: its clip scratched, in your ears alone. REC first and the scratch is a sample."],
	["A cable to a bandmate", "P steps the jack of what you carry into a track or a bandmate's keys; with an empty hand, your own keys; with chords on (C), your chord hand, to drive their harp. Shift-P unplugs."],
	["Headphones", "H puts them on. Best when you record, so the song does not end up in your microphone."],
	["Point", "Hold Z: bandmates see your ray and your name on what you point at. In a headset, point your index level, or hold in the other hand's stick."],
	["Sticky notes", "O sticks a note at the ruler's time under the cursor, or the playhead. In a headset, drag one off the note pad at the desk's left end."],
	["Listen from there", "Z and Enter over the ruler, or a note's LISTEN: the song plays from there for everyone. In a headset, pinch thumb and middle as you point."],
]
const ROOM := [
	["Walking", "WASD or the arrows walk, Shift runs, Space jumps, right-drag looks. N flies instead, and back."],
	["The gear", "F walks you to the gear you look at, Shift-F the other way, Esc lets go. G brings it to you instead."],
	["The desk", "E spreads the console out to every track at once, and back to its pages."],
	["Carrying", "Q puts down what you carry. Hold R and let go to throw it. 1 to 3 pocket it, and the wheel picks a pocket."],
	["Somewhere else", "V changes the venue. Tab opens the stage manager, to move the gear about."],
	["Rolling stands", "Drag a stand on wheels to roll it somewhere else."],
	["Lettering", "+ and - make the room's lettering larger or smaller, 0 puts it back."],
	["Signal and comfort", "Beads ride every cable, closer, faster and brighter the louder it is: follow them to where the sound stops. M, then COMFORT: Motion, Room reacts, Lift on clip."],
	["Fingertips", "T makes J K L ; play the song's chord. T, Esc or a click gives the keys back."],
	["Chords", "C, then 1 to 7: the key's chords for everything you play, Shift the seventh, 0 the song's. C or Esc ends it."],
	["Bend", "Hold Alt and move the mouse up or down to bend what you are playing; let go and it springs back. A wiggle wobbles it. \"Tilt bends\" in the session panel."],
]

## Where "seen" is kept; the suite points it elsewhere.
var seen_path := SEEN
## The studio, for the stations that stand in its venue and for going to them. Without one (the
## suite's card) every station is listed and a PLAY line goes nowhere.
var studio: Studio = null
## Extra rows for an area, {area: [row, ...]}: the suite pads one to see it run on.
var extra_rows := {}
## The page showing, an index into `pages()`.
var page := 0

var _panel: PanelContainer
var _centre: CenterContainer
## Holds the keyboard while the card is open.
var _keys: Control
var _pages: Array = []
## What a click can land on: [Control, first page index] for the names, and [[cells], station id,
## marker Label] for the PLAY lines.
var _tabs: Array = []
var _lines: Array = []
var _hovered := -1


## Whether this machine has not seen the card yet.
static func first_time() -> bool:
	return not FileAccess.file_exists(SEEN)


func _ready() -> void:
	layer = 90
	_centre = CenterContainer.new()
	_centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_centre)
	_keys = Control.new()
	_keys.name = "Keys"
	_keys.focus_mode = Control.FOCUS_ALL
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_keys)
	visible = false


## Shown, the pages made again (the venue may have changed), at the page it was last on.
func open() -> void:
	visible = true
	_pages = pages()
	show_page(clampi(page, 0, _pages.size() - 1))
	if _keys.is_inside_tree():
		_keys.grab_focus()


func close() -> void:
	visible = false
	_set_hovered(-1)
	if _keys != null and _keys.has_focus():
		_keys.release_focus()
	if not FileAccess.file_exists(seen_path):
		var f := FileAccess.open(seen_path, FileAccess.WRITE)
		if f != null:
			f.store_string("1\n")


## Every page, built from the sections and Stations now: [{name, section, heading, sub, lines,
## play}], each line [label, text, station id or empty].
func pages() -> Array:
	var out: Array = []
	out.append({"name": "START", "section": "START", "heading": "Welcome to dawlings",
			"sub": "A studio you walk around in, with a song already on the desk.", "lines": _plain(START)})
	var held: Array = []
	for r: Dictionary in Stations.HELD + extra_rows.get(Stations.HELD_AREA, []):
		held.append([r["title"], r["desk"], &""])
	var sections := [[_held_name(), held, HELD_HOMES]]
	var here := Stations.by_area(studio.venue if studio != null else null)
	for area in Stations.AREAS:
		var lines: Array = []
		for r: Dictionary in (here[area] as Array) + extra_rows.get(area, []):
			lines.append([r["title"], r["desk"], r["id"]])
		if not lines.is_empty():
			sections.append(["%s · %s" % [PLAY, Stations.AREA_TITLES[area]], lines,
					"Click one to walk to it. I and Shift-I go to each in turn, Esc back to the desk."])
	for s: Array in sections:
		out.append_array(_run_on(s[0], s[2], s[1]))
	out.append({"name": "TOGETHER", "section": "TOGETHER", "heading": "Together",
			"sub": "Playing with friends, in this room or another.", "lines": _plain(TOGETHER)})
	out.append({"name": "ROOM", "section": "ROOM", "heading": "The room",
			"sub": "Getting about, and the room's own keys.", "lines": _plain(ROOM)})
	for p: Dictionary in out:
		p["play"] = String(p["section"]).begins_with(PLAY)
	return out


## The pages' names, in order: `PLAY · LIVE ROOM 2/2` for a run-on page.
func page_names() -> PackedStringArray:
	var out := PackedStringArray()
	for p: Dictionary in (_pages if not _pages.is_empty() else pages()):
		out.append(p["name"])
	return out


## How big page `index` measures, built as it would be shown, at the text scale now.
func page_size(index: int) -> Vector2:
	var all := _pages if not _pages.is_empty() else pages()
	var built := _build(all, index, [], [])
	var size := built.get_combined_minimum_size()
	built.free()
	return size


func show_page(index: int) -> void:
	if _pages.is_empty():
		_pages = pages()
	page = posmod(index, _pages.size())
	_set_hovered(-1)
	if _panel != null:
		_centre.remove_child(_panel)
		_panel.queue_free()
	_tabs.clear()
	_lines.clear()
	_panel = _build(_pages, page, _tabs, _lines)
	_centre.add_child(_panel)


func turn(by: int) -> void:
	show_page(page + by)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null:
		if key.pressed and not key.echo and key.keycode == KEY_F1:
			if visible:
				close()
			else:
				open()
			get_viewport().set_input_as_handled()
			return
		if not visible:
			return
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_ESCAPE:
					close()
				KEY_RIGHT, KEY_PAGEDOWN:
					turn(1)
				KEY_LEFT, KEY_PAGEUP:
					turn(-1)
		# Every other key that reaches the card stays here while it is open, pressed, held or
		# let go. F2 does not reach it: the 2D view takes it first, and closes the card.
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_set_hovered(_line_at(motion.position))
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	get_viewport().set_input_as_handled()
	if click.button_index == MOUSE_BUTTON_WHEEL_DOWN or click.button_index == MOUSE_BUTTON_WHEEL_UP:
		turn(1 if click.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
		return
	for tab: Array in _tabs:
		if (tab[0] as Control).get_global_rect().has_point(click.position):
			show_page(tab[1])
			return
	var at := _line_at(click.position)
	var id: StringName = _lines[at][1] if at >= 0 else &""
	close()
	if id != &"" and studio != null:
		studio.go_to_station(id)


## The PLAY line under `point` (an index into the shown lines), or -1.
func _line_at(point: Vector2) -> int:
	for i in _lines.size():
		for cell: Control in _lines[i][0]:
			# Its row's height and the gap to the next cell, so the line is one target.
			if cell.get_global_rect().grow_individual(0, 4, 24, 4).has_point(point):
				return i
	return -1


func _set_hovered(i: int) -> void:
	if i == _hovered:
		return
	if _hovered >= 0 and _hovered < _lines.size():
		(_lines[_hovered][2] as Label).text = ""
	_hovered = i
	if i >= 0:
		(_lines[i][2] as Label).text = "→"
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if i >= 0 else Input.CURSOR_ARROW)


static func _held_name() -> String:
	return "%s · %s" % [PLAY, Stations.AREA_TITLES[Stations.HELD_AREA]]


## A section's lines as pages: the one, or as many numbered pages as it takes to fit, shared out
## evenly between them where they still fit that way, so the last is not a page of one line.
func _run_on(section: String, sub: String, lines: Array) -> Array:
	var chunks: Array = []
	var chunk: Array = []
	for line: Array in lines:
		chunk.append(line)
		if chunk.size() > 1 and not _fits(section, sub, chunk):
			chunk.pop_back()
			chunks.append(chunk)
			chunk = [line]
	chunks.append(chunk)
	if chunks.size() > 1:
		var even: Array = []
		var each := ceili(float(lines.size()) / chunks.size())
		for at in range(0, lines.size(), each):
			even.append(lines.slice(at, at + each))
		if even.size() == chunks.size() and even.all(func(c: Array) -> bool: return _fits(section, sub, c)):
			chunks = even
	var out: Array = []
	for n in chunks.size():
		var name := section if chunks.size() == 1 else "%s %d/%d" % [section, n + 1, chunks.size()]
		out.append({"name": name, "section": section, "heading": name, "sub": sub, "lines": chunks[n]})
	return out


## Whether a page of these lines fits, measured with the longest name it could be given and every
## section's name in the row, so cutting it into pages cannot make it grow.
func _fits(section: String, sub: String, lines: Array) -> bool:
	var trial := [{"name": section + " 99/99", "section": section, "heading": section + " 99/99",
			"sub": sub, "lines": lines, "play": true}]
	var built := _build(trial, 0, [], [], _section_names())
	var size := built.get_combined_minimum_size()
	built.free()
	return size.x <= FIT.x and size.y <= FIT.y


## Every name the row of names could show, whatever the pages are cut into.
func _section_names() -> PackedStringArray:
	var out := PackedStringArray(["START", _held_name()])
	for area in Stations.AREAS:
		out.append("%s · %s" % [PLAY, Stations.AREA_TITLES[area]])
	out.append_array(["TOGETHER", "ROOM"])
	return out


static func _plain(lines: Array) -> Array:
	return lines.map(func(l: Array) -> Array: return [l[0], l[1], &""])


## Page `index` of `all` as a panel, not yet in the tree. The row of names has one a section, the
## page's own boxed and the others dim; `tabs` and `lines` are filled with what a click can land
## on. `names`, given, stands in for the sections' names while a page is measured before the cut.
func _build(all: Array, index: int, tabs: Array, lines: Array, names := PackedStringArray()) -> PanelContainer:
	var k := clampf(Ergonomics.current.text_scale, 0.6, 3.0) if Ergonomics.current != null else 1.0
	var p: Dictionary = all[index]
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.085, 0.1, 0.96)
	style.border_color = Color(0.3, 0.31, 0.34)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(9 * k))
	panel.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(6 * k))
	column.add_child(row)
	var shown := names
	if shown.is_empty():
		for q: Dictionary in all:
			if not shown.has(q["section"]):
				shown.append(q["section"])
	for section in shown:
		var first := -1
		for i in all.size():
			if all[i]["section"] == section:
				first = i
				break
		var here: bool = section == p["section"]
		var tab := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.17, 0.17, 0.19) if here else Color(0, 0, 0, 0)
		box.border_color = ACCENT if here else Color(0, 0, 0, 0)
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 2
		box.content_margin_bottom = 2
		tab.add_theme_stylebox_override("panel", box)
		tab.add_child(_label(section, roundi(13 * k), TEXT if here else DIM))
		row.add_child(tab)
		if first >= 0:
			tabs.append([tab, first])
	column.add_child(_label(p["heading"], roundi(24 * k), TEXT))
	column.add_child(_label(p["sub"], roundi(14 * k), DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", roundi(12 * k))
	grid.add_theme_constant_override("v_separation", roundi(7 * k))
	column.add_child(grid)
	var size := roundi(15 * k)
	for line: Array in p["lines"]:
		var mark := _label("", size, ACCENT)
		mark.custom_minimum_size.x = roundi(14 * k)
		grid.add_child(mark)
		var title := _label(line[0], size, ACCENT)
		grid.add_child(title)
		var said := _label(_wrap(line[1], size, WRAP * k), size, TEXT)
		grid.add_child(said)
		if line[2] != &"":
			lines.append([[title, said], line[2], mark])
	var foot := "← →  or  Page Up / Page Down turn the pages  ·  F1 or Esc closes"
	if p.get("play", false) and p["section"] != _held_name():
		foot = "Click an instrument to walk to it  ·  " + foot
	column.add_child(_label("%s      %d / %d" % [foot, index + 1, all.size()], roundi(13 * k), DIM))
	return panel


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


## `text` broken into lines no wider than `width` px at `size`, at the spaces: wrapped here rather
## than by the Label, so a page measures the same out of the tree as on the screen.
static func _wrap(text: String, size: int, width: float) -> String:
	var font := ThemeDB.fallback_font
	var out := PackedStringArray()
	var run := ""
	for word in text.split(" ", false):
		var trial := word if run.is_empty() else run + " " + word
		if not run.is_empty() and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			out.append(run)
			run = word
		else:
			run = trial
	if not run.is_empty():
		out.append(run)
	return "\n".join(out)
