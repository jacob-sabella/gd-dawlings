class_name SessionPanel
extends CanvasLayer

## The way into a session from inside the app: host one, find one on the LAN, join it, see who
## is here. M opens it.
##
## The command line could already do all of this, and that was the problem with it. A session is
## something you start when the second person walks in, not something you decide on before you
## launch -- and the person walking in has no terminal and has not been told an IP address.
## So: one key, a list of the sessions the network can see, and a button with a name on it.
##
## Also the room's noticeboard. Who arrived, who left, who already has that fader, and the host
## going away all reach here as Session.notice and are shown for a few seconds where the eye
## already is, rather than in a log nobody at a mixing desk is reading.

const WIDTH := 360.0
const TOAST_SECONDS := 4.5
## A beacon is heard once a second. Three missed and the session is taken to be gone.
const NEARBY_FORGET_MSEC := 3500

const INK := Color(0.86, 0.89, 0.93)
const DIM := Color(0.56, 0.60, 0.67)
const CARD := Color(0.055, 0.062, 0.078, 0.95)
const WELL := Color(0.10, 0.11, 0.135)
const EDGE := Color(1, 1, 1, 0.07)

var _root: PanelContainer
var _pill: Label
var _status: Label
var _name_edit: LineEdit
var _swatch: Panel
var _roster: VBoxContainer
var _solo_box: VBoxContainer
var _host_box: VBoxContainer
var _guest_box: VBoxContainer
var _address_edit: LineEdit
var _nearby: VBoxContainer
var _nearby_empty: Label
var _addresses: Label
var _ask_code: CheckBox
var _code_edit: LineEdit
var _code_shown: Label
var _code_box: VBoxContainer
var _hear: CheckButton
var _volume: HSlider
var _hearing: Label
var _sharing: Label
var _audio_clock := 0.0
var _toasts: VBoxContainer
var _strip: HBoxContainer

var _listener: PacketPeerUDP = null
var _found: Dictionary = {}


func _ready() -> void:
	layer = 20
	_build_panel()
	_build_toasts()
	_build_strip()
	_root.visible = false
	Session.notice.connect(toast)
	Session.roster_changed.connect(_refresh)
	Session.role_changed.connect(_refresh)
	Session.holds_changed.connect(_refresh)
	_refresh()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	_name_edit.text = Session.local_name
	_refresh()


func close() -> void:
	_root.visible = false
	_stop_listening()
	var focused := _root.get_viewport().gui_get_focus_owner()
	if focused != null and _root.is_ancestor_of(focused):
		focused.release_focus()


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_M and not key.ctrl_pressed:
		toggle()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and is_open():
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open():
		return
	_audio_clock += delta
	if _audio_clock > 0.5:
		_audio_clock = 0.0
		_refresh_sound()
	if Session.role == Session.Role.SOLO:
		_listen()
	else:
		_stop_listening()


# --- the panel ----------------------------------------------------------------------------

func _build_panel() -> void:
	_root = PanelContainer.new()
	_root.name = "SessionPanel"
	_root.add_theme_stylebox_override("panel", _box(CARD, 14, 18, EDGE))
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.offset_left = -WIDTH - 18
	_root.offset_right = -18
	_root.offset_top = 70
	_root.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(_root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_root.add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var title := _label("SESSION", 15, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_pill = _label("SOLO", 11, Color.BLACK)
	_pill.add_theme_stylebox_override("normal", _box(DIM, 9, 0))
	_pill.add_theme_constant_override("line_spacing", 0)
	_pill.custom_minimum_size = Vector2(74, 20)
	_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_pill)

	_status = _label("", 13, DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	column.add_child(_caption("YOUR NAME"))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	column.add_child(name_row)
	_swatch = Panel.new()
	_swatch.custom_minimum_size = Vector2(12, 34)
	name_row.add_child(_swatch)
	_name_edit = _edit("Your name")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(t: String): _rename(t))
	_name_edit.focus_exited.connect(func(): _rename(_name_edit.text))
	name_row.add_child(_name_edit)

	column.add_child(_caption("IN THE ROOM"))
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 4)
	column.add_child(_roster)

	# Solo: start one, or find one.
	_solo_box = VBoxContainer.new()
	_solo_box.add_theme_constant_override("separation", 8)
	column.add_child(_solo_box)
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 10)
	_solo_box.add_child(host_row)
	var host_button := _button("Host a session", true)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.pressed.connect(_host)
	host_row.add_child(host_button)
	# A code is for the room with a neighbour on the same wifi. Off by default: four people in
	# one studio should not have to read each other numbers to get started.
	_ask_code = CheckBox.new()
	_ask_code.text = "Ask for a code"
	_ask_code.add_theme_font_size_override("font_size", 13)
	_ask_code.add_theme_color_override("font_color", DIM)
	host_row.add_child(_ask_code)
	_solo_box.add_child(_caption("ON THIS NETWORK"))
	_nearby = VBoxContainer.new()
	_nearby.add_theme_constant_override("separation", 6)
	_solo_box.add_child(_nearby)
	_nearby_empty = _label("Looking for sessions…", 13, DIM)
	_solo_box.add_child(_nearby_empty)
	_solo_box.add_child(_caption("SESSION CODE  ·  IF THE HOST GAVE YOU ONE"))
	_code_edit = _edit("AB12")
	_code_edit.max_length = 12
	_solo_box.add_child(_code_edit)
	_solo_box.add_child(_caption("JOIN BY ADDRESS"))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_solo_box.add_child(join_row)
	_address_edit = _edit("192.168.1.40")
	_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_edit.text_submitted.connect(func(t: String): _join(t, Session.DEFAULT_PORT))
	join_row.add_child(_address_edit)
	var join_button := _button("Join", false)
	join_button.pressed.connect(func(): _join(_address_edit.text, Session.DEFAULT_PORT))
	join_row.add_child(join_button)

	# Hosting: who can reach you, and the way out.
	_host_box = VBoxContainer.new()
	_host_box.add_theme_constant_override("separation", 8)
	column.add_child(_host_box)
	_code_box = VBoxContainer.new()
	_code_box.add_theme_constant_override("separation", 2)
	_host_box.add_child(_code_box)
	_code_box.add_child(_caption("SESSION CODE"))
	_code_shown = _label("", 30, INK)
	_code_shown.add_theme_constant_override("outline_size", 0)
	_code_box.add_child(_code_shown)
	_host_box.add_child(_caption("OTHERS JOIN AT"))
	_addresses = _label("", 14, INK)
	_host_box.add_child(_addresses)
	var end_button := _button("End session", false)
	end_button.pressed.connect(func(): Session.leave())
	_host_box.add_child(end_button)

	_host_box.add_child(_caption("SOUND"))
	_sharing = _label("", 13, DIM)
	_sharing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_box.add_child(_sharing)
	# The way out stays last.
	_host_box.move_child(end_button, -1)

	_guest_box = VBoxContainer.new()
	_guest_box.add_theme_constant_override("separation", 8)
	column.add_child(_guest_box)
	_guest_box.add_child(_caption("SOUND"))
	var hear_row := HBoxContainer.new()
	hear_row.add_theme_constant_override("separation", 10)
	_guest_box.add_child(hear_row)
	_hear = CheckButton.new()
	_hear.text = "Hear the mix"
	_hear.add_theme_font_size_override("font_size", 14)
	_hear.add_theme_color_override("font_color", INK)
	_hear.toggled.connect(func(on: bool): Session.hear_mix = on)
	hear_row.add_child(_hear)
	_volume = HSlider.new()
	_volume.min_value = -30.0
	_volume.max_value = 6.0
	_volume.step = 0.5
	_volume.value = 0.0
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume.tooltip_text = "Your level for the host's mix. Changes nothing for anyone else."
	_volume.value_changed.connect(func(v: float): Session.mix_feed.volume_db = v if v > -29.9 else -80.0)
	hear_row.add_child(_volume)
	_hearing = _label("", 13, DIM)
	_hearing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guest_box.add_child(_hearing)
	var leave_button := _button("Leave session", false)
	leave_button.pressed.connect(func(): Session.leave())
	_guest_box.add_child(leave_button)

	var foot := _label("M  close   ·   the mix is the host's; your view is your own", 11, DIM)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(foot)


func _refresh() -> void:
	if _root == null:
		return
	var me = Session.local_participant()
	var colour: Color = me.colour if me != null else Session.PALETTE[0]
	_swatch.add_theme_stylebox_override("panel", _box(colour, 4, 0))
	var people := Session.participants.size()
	match Session.role:
		Session.Role.SOLO:
			_set_pill("SOLO", DIM)
			_status.text = "Just you. Host a session and anyone on this network can join your mix."
		Session.Role.HOST:
			_set_pill("HOSTING", colour)
			_status.text = "Your mix, shared. %d %s in the room." % [people, "person" if people == 1 else "people"]
		Session.Role.GUEST:
			var host = Session.participants.get(1)
			_set_pill("JOINED", host.colour if host != null else colour)
			_status.text = "In %s's session at %s. Their Reaper, your view." % [
					Session.name_of(1), Session.joined_address]
	_refresh_sound()
	_solo_box.visible = Session.role == Session.Role.SOLO
	_host_box.visible = Session.role == Session.Role.HOST
	_guest_box.visible = Session.role == Session.Role.GUEST
	_code_box.visible = not Session.code.is_empty()
	var spaced := PackedStringArray()
	for c in Session.code:
		spaced.append(c)
	_code_shown.text = " ".join(spaced)
	_addresses.text = "\n".join(_lan_addresses().map(
			func(a): return "%s : %d" % [a, Session.port]))

	for child in _roster.get_children():
		child.queue_free()
	var ids := Session.participants.keys()
	ids.sort()
	for id in ids:
		_roster.add_child(_roster_row(Session.participants[id]))
	_refresh_strip()


## What this person hears, and how late. The number is the point: "the mix" is useless to play
## along to at 120ms and fine at 40, and nobody can tell which they have by listening while
## they are also trying to play.
func _refresh_sound() -> void:
	var feed := Session.mix_feed
	if feed == null:
		return
	var s := feed.stats()
	if Session.role == Session.Role.HOST:
		var n := int(s.get("listeners", 0))
		var source: String = s.get("source", "")
		_sharing.text = "%s\n%s" % [source if source != "" else "No mix audio to share.",
				"Nobody listening yet." if n == 0 else "%d listening." % n]
	elif Session.role == Session.Role.GUEST:
		if _hear.button_pressed != Session.hear_mix:
			_hear.set_pressed_no_signal(Session.hear_mix)
		_volume.editable = Session.hear_mix
		if not Session.hear_mix:
			_hearing.text = "Off. Turn it on unless you can already hear %s's speakers." % Session.name_of(1)
		elif not s.get("listening", false):
			_hearing.text = "%s is not sharing sound." % Session.name_of(1)
		elif not s.get("hearing", false):
			_hearing.text = "Waiting for sound…"
		else:
			var drops := int(s.get("underruns", 0)) + int(s.get("lost", 0))
			_hearing.text = "%d ms behind %s's speakers%s" % [roundi(s.get("latency_ms", 0.0)),
					Session.name_of(1), "" if drops == 0 else "  ·  %d dropouts" % drops]


func _roster_row(p) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", _box(p.colour, 5, 0))
	row.add_child(dot)
	var who := _label(p.display_name + ("  (you)" if p.peer_id == Session.local_peer_id else ""), 14, INK)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.clip_text = true
	row.add_child(who)
	var held := ""
	for key in Session.holds:
		if Session.holds[key] == p.peer_id:
			held = key
	var what: String = ("on " + held.to_lower()) if not held.is_empty() else \
			"%s · %s" % [_role_word(p.peer_id), ["screen", "ar", "vr"][clampi(p.medium, 0, 2)]]
	row.add_child(_label(what, 12, p.colour if not held.is_empty() else DIM))
	return row


static func _role_word(peer_id: int) -> String:
	if Session.role == Session.Role.SOLO:
		return "solo"
	return "host" if peer_id == 1 else "guest"


func _set_pill(text: String, colour: Color) -> void:
	_pill.text = text
	_pill.add_theme_stylebox_override("normal", _box(colour, 9, 0))


func _rename(text: String) -> void:
	if text.strip_edges() != Session.local_name:
		Session.set_local_name(text)


func _host() -> void:
	_rename(_name_edit.text)
	Session.code = make_code() if _ask_code.button_pressed else ""
	Session.host()


## Four characters, from an alphabet with nothing in it that can be misread across a room or
## misheard when spoken: no 0/O, 1/I/L, 5/S, 2/Z, 8/B.
static func make_code() -> String:
	const ALPHABET := "ACDEFGHJKMNPQRTUVWXY34679"
	var out := ""
	for i in 4:
		out += ALPHABET[randi() % ALPHABET.length()]
	return out


func _join(address: String, port: int) -> void:
	address = address.strip_edges()
	if address.is_empty():
		_address_edit.grab_focus()
		return
	_rename(_name_edit.text)
	if Session.join(address, port, _code_edit.text):
		toast("Joining %s…" % address)


## This machine's addresses a person across the room could type. Loopback is useless to them,
## link-local means the network has not handed out an address at all, and a container or VM
## bridge (docker0, br-…, virbr0, veth…) is a network that exists only inside this machine.
static func _lan_addresses() -> Array:
	var out: Array = []
	for iface in IP.get_local_interfaces():
		var named: String = iface.get("name", "")
		if ["docker", "br-", "virbr", "veth", "lo"].any(
				func(p): return named.begins_with(p)):
			continue
		for a in iface.get("addresses", []):
			if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
				continue
			out.append(a)
	if out.is_empty():
		out.append("127.0.0.1")
	return out


# --- finding sessions ---------------------------------------------------------------------

func _listen() -> void:
	if _listener == null:
		_listener = PacketPeerUDP.new()
		if _listener.bind(Session.DISCOVERY_PORT) != OK:
			_listener = null
			_nearby_empty.text = "Cannot listen for sessions here (port %d busy)." % Session.DISCOVERY_PORT
			return
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var packet := _listener.get_packet()
		var from := _listener.get_packet_ip()
		var said = JSON.parse_string(packet.get_string_from_utf8())
		if typeof(said) != TYPE_DICTIONARY or said.get("app") != "reaper-3d":
			continue
		var port := int(said.get("port", Session.DEFAULT_PORT))
		# The same host heard on loopback and over the LAN is one session, listed under the
		# address someone on another machine would use.
		var key := "%s:%d:%s" % [said.get("name", "?"), port, said.get("tracks", 0)]
		var known: Dictionary = _found.get(key, {})
		if known.is_empty() or (String(known["ip"]).begins_with("127.") and not from.begins_with("127.")):
			changed = true
		_found[key] = {"ip": from if known.is_empty() or not from.begins_with("127.") else known["ip"],
				"port": port, "said": said, "heard": Time.get_ticks_msec()}
	for key in _found.keys():
		if Time.get_ticks_msec() - int(_found[key]["heard"]) > NEARBY_FORGET_MSEC:
			_found.erase(key)
			changed = true
	if changed or _nearby.get_child_count() != _found.size():
		_draw_nearby()


func _stop_listening() -> void:
	if _listener != null:
		_listener.close()
	_listener = null
	_found.clear()


func _draw_nearby() -> void:
	for child in _nearby.get_children():
		child.queue_free()
	_nearby_empty.visible = _found.is_empty()
	_nearby_empty.text = "Looking for sessions…"
	for key in _found:
		var entry: Dictionary = _found[key]
		var said: Dictionary = entry["said"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 0)
		words.add_child(_label("%s's session" % said.get("name", "?"), 14, INK))
		var people := int(said.get("people", 1))
		words.add_child(_label("%d tracks · %d %s · %s%s" % [int(said.get("tracks", 0)), people,
				"person" if people == 1 else "people", entry["ip"],
				"  ·  code needed" if said.get("locked", false) else ""], 12, DIM))
		row.add_child(words)
		var join := _button("Join", true)
		var ip: String = entry["ip"]
		var port: int = entry["port"]
		join.pressed.connect(func(): _join(ip, port))
		row.add_child(join)
		_nearby.add_child(row)


# --- the noticeboard ----------------------------------------------------------------------

func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.name = "Toasts"
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.offset_left = -260
	_toasts.offset_right = 260
	_toasts.offset_top = 72
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)


func toast(text: String) -> void:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _box(Color(CARD, 0.9), 10, 10, EDGE))
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var line := _label(text, 14, INK)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(line)
	_toasts.add_child(card)
	# Five at most: a room filling up all at once should not bury the desk in cards.
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).free()
	var fade := card.create_tween()
	fade.tween_interval(TOAST_SECONDS)
	fade.tween_property(card, "modulate:a", 0.0, 0.6)
	fade.tween_callback(card.queue_free)


## Who is here, at a glance, without opening anything: a dot and a name each, top right.
func _build_strip() -> void:
	_strip = HBoxContainer.new()
	_strip.name = "Roster"
	_strip.anchor_left = 1.0
	_strip.anchor_right = 1.0
	_strip.offset_left = -WIDTH - 18
	_strip.offset_right = -18
	_strip.offset_top = 40
	_strip.alignment = BoxContainer.ALIGNMENT_END
	_strip.add_theme_constant_override("separation", 14)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)


func _refresh_strip() -> void:
	for child in _strip.get_children():
		child.queue_free()
	_strip.visible = Session.role != Session.Role.SOLO and not is_open()
	var ids := Session.participants.keys()
	ids.sort()
	for id in ids:
		var p = Session.participants[id]
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 6)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(9, 9)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", _box(p.colour, 5, 0))
		chip.add_child(dot)
		var label := _label(p.display_name, 13, INK)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 5)
		chip.add_child(label)
		_strip.add_child(chip)


# --- parts --------------------------------------------------------------------------------

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


func _caption(text: String) -> Label:
	var l := _label(text, 11, DIM)
	l.add_theme_constant_override("line_spacing", 0)
	return l


func _edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 34)
	e.add_theme_font_size_override("font_size", 14)
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", Color(DIM, 0.6))
	var normal := _box(WELL, 8, 10, EDGE)
	var focus := _box(WELL, 8, 10, Color(0.45, 0.65, 0.95, 0.7))
	e.add_theme_stylebox_override("normal", normal)
	e.add_theme_stylebox_override("focus", focus)
	return e


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 14)
	var base := Color(0.92, 0.6, 0.25) if primary else Color(0.15, 0.16, 0.19)
	var ink := Color(0.08, 0.06, 0.04) if primary else INK
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", ink)
	b.add_theme_color_override("font_pressed_color", ink)
	b.add_theme_color_override("font_focus_color", ink)
	b.add_theme_stylebox_override("normal", _box(base, 8, 14))
	b.add_theme_stylebox_override("hover", _box(base.lightened(0.12), 8, 14))
	b.add_theme_stylebox_override("pressed", _box(base.darkened(0.15), 8, 14))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), 8, 14, Color(1, 1, 1, 0.25)))
	return b
