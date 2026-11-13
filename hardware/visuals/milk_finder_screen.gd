class_name MilkFinderScreen
extends CanvasLayer

## The picture finder for a visualizer TV (MilkScreen): every picture by name, found by typing, with what it does.
## Choosing one in the list puts it on the TV at once and shows it live beside the list, so trying them is
## scrolling through them. HOLD keeps the TV on the one chosen (no change every half minute); unticked, it moves
## on by itself again. Opened by the TV's FIND key; Escape or CLOSE shuts it. Like the rack's module finder
## (RackFinderScreen), and as plain.
##
## The list is MilkLibrary's: the built-in looks, the player's own `.milk` files and, once downloaded here
## (MORE PICTURES, MilkDownload, never automatic), projectM's "Cream of the Crop" pack, by category (GROUP).
## A file that plays only approximately (its MilkDrop 2 shaders not translated, some code dropped) is
## marked "approx" once it has been shown.

const _DIM := Color(0.62, 0.68, 0.78)
const _HEAD := Color(1.0, 0.86, 0.5)
## At most this many are listed at once (the pack holds thousands); the count says how many matched.
const MOST_LISTED := 600
const ALL := "ALL"
## What each built-in picture does, by name, for the list and the card.
const ABOUT := {
	"Tunnel Dive": "Flies into a tunnel of the wave's trails; the bass pushes the zoom.",
	"Spiral Arms": "The wave wound into turning spiral arms that speed up with the music.",
	"Kaleidoscope": "The picture mirrored into a kaleidoscope round the middle.",
	"Liquid": "A slow liquid warp that wobbles harder on every hit.",
	"Starburst": "Rays from the middle, a punch of zoom and a flash of negative on each hit.",
	"Nebula Drift": "Slow coloured clouds drifting; calm, for quiet music.",
	"Radial Bloom": "The spectrum drawn as rays, blooming outward from the middle.",
	"Strobe Lines": "Lines of the wave, flashing negative on the beat when it is loud.",
	"Vortex": "A whirlpool that pulls the wave in and round.",
	"Echo Hall": "The wave echoed back on itself, layer behind layer.",
}
const PACK_ABOUT := "projectM's \"Cream of the Crop\": about 9,800 MilkDrop presets curated by ISOSCELES, downloaded from GitHub (about 25 MB). They are their authors' work and come with no licence; they are fetched to this computer only and never shipped with the game."

var screen: MilkScreen
var download: MilkDownload
var _panel: PanelContainer
var _search: LineEdit
var _groups: OptionButton
var _list: ItemList
var _detail: RichTextLabel
var _preview: TextureRect
var _hold: CheckBox
var _shuffle: CheckBox
var _count: Label
var _found: Array[int] = []
var _pack_status: Label
var _get: Button
var _confirm: Button
var _cancel: Button
var _remove: Button


func _ready() -> void:
	layer = 10
	download = MilkDownload.new()
	download.name = "Download"
	download.changed.connect(_show_download)
	add_child(download)
	_panel = PanelContainer.new()
	_panel.visible = false
	PanelLook.solid(_panel)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "FIND A PICTURE"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", _HEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "CLOSE  (Esc)"
	PanelLook.button(close)
	close.pressed.connect(close_finder)
	head.add_child(close)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	column.add_child(filters)
	_search = LineEdit.new()
	_search.placeholder_text = "type to search: a name, an author, or a word like tunnel, calm, flash, spectrum"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	filters.add_child(_search)
	filters.add_child(_lead("GROUP"))
	_groups = OptionButton.new()
	_groups.custom_minimum_size = Vector2(170, 0)
	_groups.clip_text = true
	_groups.item_selected.connect(func(_i: int) -> void: refresh())
	filters.add_child(_groups)
	_count = Label.new()
	_count.add_theme_color_override("font_color", _DIM)
	filters.add_child(_count)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(300, 0)
	_list.item_selected.connect(func(_i: int) -> void: _choose())
	body.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.custom_minimum_size = Vector2(0, 120)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_stretch_ratio = 2.0
	right.add_child(_preview)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	# It scrolls rather than grows: a long blurb must not push the pop-up off the screen.
	_detail.fit_content = false
	_detail.scroll_active = true
	_detail.custom_minimum_size = Vector2(0, 70)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 15)
	_detail.add_theme_font_size_override("bold_font_size", 15)
	right.add_child(_detail)
	_hold = CheckBox.new()
	_hold.text = "HOLD this picture (no change by itself)"
	_hold.toggled.connect(func(on: bool) -> void:
		if screen != null and is_instance_valid(screen):
			screen.auto_advance = not on)
	right.add_child(_hold)
	_shuffle = CheckBox.new()
	_shuffle.text = "Include the pack in the shuffle"
	_shuffle.tooltip_text = "Off: moving on by itself picks only the built-in pictures and your own."
	_shuffle.toggled.connect(func(on: bool) -> void: MilkLibrary.set_shuffle_pack(on))
	right.add_child(_shuffle)
	column.add_child(HSeparator.new())
	_build_more(column)
	get_viewport().size_changed.connect(_fit)
	_panel.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)


## MORE PICTURES: the pack's download (asked for, confirmed, never automatic) and the player's own folder.
func _build_more(column: VBoxContainer) -> void:
	var head := Label.new()
	head.text = "MORE PICTURES"
	head.add_theme_color_override("font_color", _HEAD)
	column.add_child(head)
	var about := Label.new()
	about.text = PACK_ABOUT
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.add_theme_color_override("font_color", _DIM)
	column.add_child(about)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	_get = Button.new()
	_get.text = "DOWNLOAD"
	PanelLook.button(_get)
	_get.pressed.connect(func() -> void:
		_get.visible = false
		_confirm.visible = true
		_cancel.visible = true
		_pack_status.text = "Download about 25 MB from GitHub now?")
	row.add_child(_get)
	_confirm = Button.new()
	_confirm.text = "YES, DOWNLOAD"
	PanelLook.button(_confirm)
	_confirm.pressed.connect(func() -> void:
		_confirm.visible = false
		_cancel.visible = false
		download.start())
	row.add_child(_confirm)
	_cancel = Button.new()
	_cancel.text = "CANCEL"
	PanelLook.button(_cancel)
	_cancel.pressed.connect(func() -> void:
		if download.state == MilkDownload.State.DOWNLOADING:
			download.cancel()
		_show_download())
	row.add_child(_cancel)
	_remove = Button.new()
	_remove.text = "REMOVE"
	PanelLook.button(_remove)
	_remove.pressed.connect(_ask_remove)
	row.add_child(_remove)
	_pack_status = Label.new()
	_pack_status.add_theme_color_override("font_color", _DIM)
	_pack_status.clip_text = true
	_pack_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pack_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_pack_status)
	var own := HBoxContainer.new()
	own.add_theme_constant_override("separation", 8)
	column.add_child(own)
	var open := Button.new()
	open.text = "OPEN FOLDER"
	PanelLook.button(open)
	open.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(MilkLibrary.own_dir())
		OS.shell_open(ProjectSettings.globalize_path(MilkLibrary.own_dir())))
	own.add_child(open)
	var rescan := Button.new()
	rescan.text = "LOOK AGAIN"
	PanelLook.button(rescan)
	rescan.pressed.connect(func() -> void:
		MilkLibrary.rescan()
		_fill_groups()
		refresh())
	own.add_child(rescan)
	var hint := Label.new()
	hint.text = "Drop your own .milk files here, then LOOK AGAIN."
	hint.add_theme_color_override("font_color", _DIM)
	own.add_child(hint)


func _lead(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", _DIM)
	return l


func _ask_remove() -> void:
	if _remove.text == "REMOVE":
		_remove.text = "YES, REMOVE THEM"
		_pack_status.text = "Delete the downloaded pack from this computer?"
		return
	MilkDownload.remove()
	if screen != null and is_instance_valid(screen) and screen.preset_index >= MilkLibrary.count():
		screen.use_preset(0)
	_remove.text = "REMOVE"
	_fill_groups()
	refresh()
	_show_download()


## The download's buttons and line, for where it is now.
func _show_download() -> void:
	if _get == null:
		return
	var n := MilkDownload.installed()
	var busy := download.state in [MilkDownload.State.DOWNLOADING, MilkDownload.State.UNPACKING]
	_confirm.visible = false
	_cancel.visible = download.state == MilkDownload.State.DOWNLOADING
	_get.visible = not busy and n == 0
	_get.text = "TRY AGAIN" if download.state == MilkDownload.State.FAILED else "DOWNLOAD"
	_remove.visible = not busy and n > 0
	if busy or download.state == MilkDownload.State.FAILED:
		_pack_status.text = download.message
	elif n > 0:
		_pack_status.text = "%d presets on this computer." % n
	else:
		_pack_status.text = "Not downloaded."
	if download.state == MilkDownload.State.DONE:
		download.state = MilkDownload.State.IDLE
		_pack_status.text = download.message
		_fill_groups()
		refresh()


func is_open() -> bool:
	return _panel != null and _panel.visible


## Open the finder for `tv`, its picture now chosen.
func open_finder(tv: MilkScreen) -> void:
	screen = tv
	_search.text = ""
	_hold.set_pressed_no_signal(tv != null and not tv.auto_advance)
	_shuffle.set_pressed_no_signal(MilkLibrary.shuffle_pack())
	_panel.visible = true
	_fit()
	_fill_groups()
	refresh()
	_show_download()
	_search.grab_focus()


func close_finder() -> void:
	if _panel != null:
		_panel.visible = false


func _fill_groups() -> void:
	var keep := _groups.get_item_text(_groups.selected) if _groups.item_count > 0 and _groups.selected >= 0 else ALL
	_groups.clear()
	_groups.add_item(ALL)
	for c in MilkLibrary.categories():
		_groups.add_item(c)
	_groups.select(0)
	for i in _groups.item_count:
		if _groups.get_item_text(i) == keep:
			_groups.select(i)


## The text a picture is searched by: its name, its category and what it does.
static func _text(i: int) -> String:
	var name := MilkLibrary.preset_name(i)
	return (name + " " + MilkLibrary.category(i) + " " + String(ABOUT.get(name, ""))).to_lower()


## The indices (MilkLibrary's) of the pictures that match `words` (every word somewhere in the name,
## category or what it does), in `group` (ALL or a category), in order.
static func search(words: String, group := ALL) -> Array[int]:
	var out: Array[int] = []
	var want := Array(words.to_lower().split(" ", false))
	for i in MilkLibrary.count():
		if group != ALL and MilkLibrary.category(i) != group:
			continue
		var text := _text(i)
		if want.all(func(w: String) -> bool: return text.contains(w)):
			out.append(i)
	return out


func refresh() -> void:
	var group := _groups.get_item_text(_groups.selected) if _groups.item_count > 0 and _groups.selected >= 0 else ALL
	_found = search(_search.text, group)
	var shown := _found.slice(0, MOST_LISTED)
	_list.clear()
	var now := screen.preset_index if screen != null and is_instance_valid(screen) else -1
	for i in shown:
		var mark := ""
		if MilkLibrary.is_broken(i):
			mark = "   (broken)"
		elif not MilkLibrary.notes(i).is_empty():
			mark = "   approx"
		_list.add_item(("▶ " if i == now else "    ") + MilkLibrary.preset_name(i) + mark)
	_count.text = "%d of %d" % [_found.size(), MilkLibrary.count()] if _found.size() <= MOST_LISTED \
			else "%d found (showing %d)" % [_found.size(), MOST_LISTED]
	var at := shown.find(now)
	if at >= 0:
		_list.select(at)
		_list.ensure_current_is_visible()
	_describe()


## The picture chosen in the list, or -1.
func chosen() -> int:
	var sel := _list.get_selected_items()
	return _found[sel[0]] if not sel.is_empty() and sel[0] < _found.size() else -1


func _choose() -> void:
	var i := chosen()
	if i >= 0 and screen != null and is_instance_valid(screen) and screen.preset_index != i:
		screen.use_preset(i)
		var keep := _list.get_selected_items()
		refresh()
		if not keep.is_empty():
			_list.select(keep[0])
	_describe()


func _describe() -> void:
	var i := chosen()
	if i < 0:
		_detail.text = "Nothing matches. Try fewer words, or GROUP: ALL."
		return
	var name := MilkLibrary.preset_name(i)
	var what := String(ABOUT.get(name, ""))
	if not MilkLibrary.is_builtin(i):
		what = "A MilkDrop preset, from %s." % MilkLibrary.category(i)
		var notes := MilkLibrary.notes(i)
		if notes.has("broken"):
			what += " It could not be read."
		elif not notes.is_empty():
			what += " Plays approximately: %s." % ", ".join(notes)
	_detail.text = "[b][color=#ffdc80]%s[/color][/b]\n%s\n[color=#9fb0c8]On the TV now. Click the TV itself to move on to the next.[/color]" \
			% [name, what]


func _process(_delta: float) -> void:
	if is_open() and screen != null and is_instance_valid(screen):
		_preview.texture = screen.picture()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_finder()
		get_viewport().set_input_as_handled()


func _fit() -> void:
	if _panel == null:
		return
	PanelLook.fit_modal(_panel, Vector2(1040.0, 820.0))
