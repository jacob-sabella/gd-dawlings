class_name RealmBox
extends VBoxContainer

## The session panel's REALMS part (docs/realms.md): your realm (its name, who sees it, what visitors may copy, your
## friend code), your friends, the realms open now with a VISIT for each, and, while visiting, GO HOME and what you
## can take home or bring. Built in the panel's own look (SessionPanel's _label, _button...).
##
## Leaving home always goes through RealmLeavePrompt.leave_home, which asks about unsaved changes first.

var panel: SessionPanel
var _status: Label
var _mine: VBoxContainer
var _open_button: Button
var _name_edit: LineEdit
var _visibility: OptionButton
var _copy_rule: OptionButton
var _show_song: CheckBox
var _open_on_start: CheckBox
var _friend_code: Label
var _friends: VBoxContainer
var _friend_edit: LineEdit
var _friend_name: LineEdit
var _lobby: VBoxContainer
var _lobby_said: Label
var _refresh_button: Button
var _visiting: VBoxContainer
var _bring: OptionButton
var _asks: VBoxContainer
## The realms shown, as the lobby listed them (row i is _shown[i]).
var _shown: Array = []

const VISIBILITY_WORDS := {RealmLobby.FRIENDS: "Friends see it", RealmLobby.ANYONE: "Anyone sees it",
		RealmLobby.CODE_ONLY: "Code only"}
const COPY_WORDS := {RealmLobby.COPY_ASK: "Visitors ask to copy", RealmLobby.COPY_ALWAYS: "Visitors copy freely",
		RealmLobby.COPY_NEVER: "No copying"}


func _init(of: SessionPanel) -> void:
	panel = of
	name = "Realms"
	add_theme_constant_override("separation", 8)


func _ready() -> void:
	_build()
	Session.role_changed.connect(refresh)
	Session.roster_changed.connect(refresh)
	Session.online.changed.connect(refresh)
	Session.lobby.listed.connect(refresh)
	Session.lobby.changed.connect(refresh)
	Session.realm_copy.asked.connect(refresh)
	Session.realm_copy.changed.connect(refresh)
	refresh()


func _build() -> void:
	add_child(panel._caption("REALMS  ·  YOURS, AND EVERYONE ELSE'S"))
	_status = panel._label("", 13, SessionPanel.DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	# Your realm: open it, name it, who sees it, what visitors may copy, your friend code.
	_mine = VBoxContainer.new()
	_mine.add_theme_constant_override("separation", 6)
	add_child(_mine)
	_open_button = panel._button("Open my realm", true)
	_open_button.tooltip_text = "Your realm gets a join code anyone, anywhere can use (no port forwarding), and its card goes up in the lobby for whoever may see it."
	_open_button.pressed.connect(func() -> void: panel._host_online())
	_mine.add_child(_open_button)
	_name_edit = panel._edit("%s's realm" % Session.local_name)
	_name_edit.max_length = RealmLobby.MAX_NAME
	_name_edit.text = Session.lobby.realm_name
	_name_edit.tooltip_text = "Your realm's name on its card in the lobby."
	_name_edit.text_submitted.connect(func(t: String) -> void: Session.lobby.set_setting("name", t))
	_name_edit.focus_exited.connect(func() -> void: Session.lobby.set_setting("name", _name_edit.text))
	_mine.add_child(_name_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_mine.add_child(row)
	_visibility = _options(VISIBILITY_WORDS, Session.lobby.visibility, "visibility", row)
	_visibility.tooltip_text = "Who sees your realm in the lobby while it is open: your friends (whose codes you added), anyone, or nobody (only someone you read the join code to gets in)."
	_copy_rule = _options(COPY_WORDS, Session.lobby.copy_rule, "copy", row)
	_copy_rule.tooltip_text = "What visitors may take home: your rack, this room, your song. Ask: you say yes or no to each. A song brought to you always asks."
	_show_song = _check("Show my song on my card", Session.lobby.show_song, "show_song")
	_open_on_start = _check("Open my realm when the game starts", Session.lobby.open_on_start, "open_on_start")
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	_mine.add_child(code_row)
	_friend_code = panel._label("", 14, SessionPanel.INK)
	_friend_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend_code.tooltip_text = "Your friend code. Give it to a friend: once they add it, you see their realm when it is for friends."
	code_row.add_child(_friend_code)
	var copy := panel._button("Copy", false)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(RealmLobby.spoken(Session.lobby.id))
		panel.toast("Friend code copied: %s" % RealmLobby.spoken(Session.lobby.id)))
	code_row.add_child(copy)

	_mine.add_child(panel._caption("FRIENDS  ·  THEY SEE YOUR REALM WHEN IT IS FOR FRIENDS"))
	_friends = VBoxContainer.new()
	_friends.add_theme_constant_override("separation", 4)
	_mine.add_child(_friends)
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	_mine.add_child(add_row)
	_friend_edit = panel._edit("their code")
	_friend_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_friend_edit)
	_friend_name = panel._edit("their name")
	_friend_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_friend_name)
	var add := panel._button("Add", false)
	add.pressed.connect(_add_friend)
	add_row.add_child(add)

	# While visiting: home, and what to take or bring.
	_visiting = VBoxContainer.new()
	_visiting.add_theme_constant_override("separation", 6)
	add_child(_visiting)
	var home := panel._button("Go home", true)
	home.tooltip_text = "Back to your own realm: your song as you left it, and your realm open again if it was."
	home.pressed.connect(func() -> void: Session.leave())
	_visiting.add_child(home)
	_visiting.add_child(panel._caption("TAKE HOME FROM THIS REALM"))
	var take := HBoxContainer.new()
	take.add_theme_constant_override("separation", 6)
	_visiting.add_child(take)
	for kind in [RealmCopy.RACK, RealmCopy.ROOM, RealmCopy.SONG]:
		var b := panel._button({RealmCopy.RACK: "The rack", RealmCopy.ROOM: "The room", RealmCopy.SONG: "The song"}[kind], false)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = {RealmCopy.RACK: "Keep the rack as it is now among your rack presets.",
				RealmCopy.ROOM: "Keep this room (one its owner made) as a room of your own.",
				RealmCopy.SONG: "Keep the song, with every sound in it, in your projects, to open at home."}[kind]
		b.pressed.connect(func() -> void: _said(Session.realm_copy.ask(kind)))
		take.add_child(b)
	_visiting.add_child(panel._caption("BRING ONE OF YOUR SONGS"))
	var bring_row := HBoxContainer.new()
	bring_row.add_theme_constant_override("separation", 6)
	_visiting.add_child(bring_row)
	_bring = panel._choice()
	bring_row.add_child(_bring)
	var offer := panel._button("Offer", false)
	offer.tooltip_text = "Send the song, sounds and all, to this realm's owner. They say yes or no; it lands in their projects."
	offer.pressed.connect(func() -> void:
		if _bring.selected >= 0:
			_said(Session.realm_copy.offer_song(str(_bring.get_item_metadata(_bring.selected)))))
	bring_row.add_child(offer)

	# Hosting: visitors' asks to copy.
	_asks = VBoxContainer.new()
	_asks.add_theme_constant_override("separation", 4)
	add_child(_asks)

	# The lobby.
	var lobby_head := HBoxContainer.new()
	lobby_head.add_theme_constant_override("separation", 8)
	add_child(lobby_head)
	var cap := panel._caption("OPEN NOW")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lobby_head.add_child(cap)
	_refresh_button = panel._button("Refresh", false)
	_refresh_button.pressed.connect(func() -> void: Session.lobby.refresh())
	lobby_head.add_child(_refresh_button)
	_lobby = VBoxContainer.new()
	_lobby.add_theme_constant_override("separation", 6)
	add_child(_lobby)
	_lobby_said = panel._label("Press Refresh to see the realms open now.", 13, SessionPanel.DIM)
	_lobby_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_lobby_said)


func _options(words: Dictionary, now: String, key: String, row: HBoxContainer) -> OptionButton:
	var o := panel._choice()
	var i := 0
	for k in words:
		o.add_item(words[k])
		o.set_item_metadata(i, k)
		if k == now:
			o.select(i)
		i += 1
	o.item_selected.connect(func(at: int) -> void: Session.lobby.set_setting(key, o.get_item_metadata(at)))
	row.add_child(o)
	return o


func _check(text: String, on: bool, key: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", 13)
	c.add_theme_color_override("font_color", SessionPanel.DIM)
	c.toggled.connect(func(v: bool) -> void: Session.lobby.set_setting(key, v))
	_mine.add_child(c)
	return c


func _add_friend() -> void:
	var why := Session.lobby.add_friend(_friend_edit.text, _friend_name.text)
	if why != "":
		_said(why)
		return
	_friend_edit.text = ""
	_friend_name.text = ""
	_said("Added. They see your realm when it is for friends.")


func _said(text: String) -> void:
	if text != "":
		_status.text = text


## Visits the realm at `row` of the lobby: home is set aside first (asking about unsaved changes).
func visit(realm: Dictionary, door := "") -> void:
	if bool(realm.get("door", false)) and door.strip_edges() == "":
		_said("%s's realm asks for a session code: type it beside VISIT." % realm.get("owner", "Their"))
		return
	panel._rename(panel._name_edit.text)
	var code := str(realm.get("code", ""))
	var server := str(realm.get("server", ""))
	RealmLeavePrompt.leave_home(panel, "%s's realm" % realm.get("owner", "someone"), func() -> void:
		Session.join_by_code(code, door.strip_edges(), server))


func refresh() -> void:
	if _status == null:
		return
	var lobby := Session.lobby
	var role := Session.role
	_mine.visible = role != Session.Role.GUEST
	_open_button.visible = role == Session.Role.SOLO
	_visiting.visible = role == Session.Role.GUEST
	_name_edit.placeholder_text = "%s's realm" % Session.local_name
	_friend_code.text = "Your friend code: %s" % RealmLobby.spoken(lobby.id)
	if Session.realm_copy.status != "":
		_status.text = Session.realm_copy.status
	elif role == Session.Role.HOST and Session.online.is_online():
		_status.text = "Your realm is open: %s." % ({RealmLobby.FRIENDS: "your friends see it in their lobby",
				RealmLobby.ANYONE: "anyone sees it in the lobby", RealmLobby.CODE_ONLY: "only someone with the join code gets in"}[lobby.visibility])
		if lobby.why_not != "" and not lobby.card_up and lobby.visibility != RealmLobby.CODE_ONLY:
			_status.text += " (Not in the lobby: %s.)" % lobby.why_not
	elif role == Session.Role.HOST:
		_status.text = "Your realm is open on this network. Go online to put it in the lobby."
	elif role == Session.Role.GUEST:
		_status.text = "Visiting %s's realm. Your own waits for you." % Session.name_of(1)
	else:
		_status.text = "Your realm is closed. Open it to let friends visit, or visit theirs below."

	for c in _friends.get_children():
		c.queue_free()
	for f in lobby.friends:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		var l := panel._label("%s  ·  %s" % [f["name"] if f["name"] != "" else "(no name)", RealmLobby.spoken(f["id"])], 13, SessionPanel.INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		var x := panel._button("Remove", false)
		var fid: String = f["id"]
		x.pressed.connect(func() -> void: lobby.remove_friend(fid))
		r.add_child(x)
		_friends.add_child(r)

	if role == Session.Role.GUEST:
		var keep: Variant = _bring.get_item_metadata(_bring.selected) if _bring.selected >= 0 else null
		_bring.clear()
		var i := 0
		for p in Session.realm_copy.own_projects():
			_bring.add_item(p["title"])
			_bring.set_item_metadata(i, p["path"])
			if p["path"] == keep:
				_bring.select(i)
			i += 1
		if i == 0:
			_bring.add_item("(no saved songs)")
			_bring.set_item_disabled(0, true)

	for c in _asks.get_children():
		c.queue_free()
	_asks.visible = role == Session.Role.HOST and not Session.realm_copy.pending.is_empty()
	if _asks.visible:
		_asks.add_child(panel._caption("VISITORS ASK"))
		var at := 0
		for p in Session.realm_copy.pending:
			var r := VBoxContainer.new()
			var l := panel._label(RealmCopy.ask_words(p), 13, SessionPanel.INK)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			r.add_child(l)
			var buttons := HBoxContainer.new()
			buttons.add_theme_constant_override("separation", 6)
			var index := at
			var yes := panel._button("Yes", true)
			yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			yes.pressed.connect(func() -> void: Session.realm_copy.decide(index, true))
			buttons.add_child(yes)
			var no := panel._button("No", false)
			no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			no.pressed.connect(func() -> void: Session.realm_copy.decide(index, false))
			buttons.add_child(no)
			r.add_child(buttons)
			_asks.add_child(r)
			at += 1

	_refresh_lobby()


func _refresh_lobby() -> void:
	var lobby := Session.lobby
	for c in _lobby.get_children():
		c.queue_free()
	_shown = lobby.realms.duplicate()
	_refresh_button.text = "Asking…" if lobby.asking else "Refresh"
	if lobby.why_not != "" and not lobby.asking:
		_lobby_said.text = "The lobby did not answer: %s." % lobby.why_not
	elif _shown.is_empty():
		_lobby_said.text = "Nobody's realm is open to you right now." if not lobby.asking else "Asking…"
	else:
		_lobby_said.text = ""
	_lobby_said.visible = _lobby_said.text != ""
	for realm in _shown:
		_lobby.add_child(_realm_row(realm))


## One realm in the lobby: its name, whose, who is in, what is playing, and VISIT.
func _realm_row(realm: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", panel._box(SessionPanel.WELL, 8, 10, SessionPanel.EDGE))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	box.add_child(col)
	var friend := Session.lobby.friend_name(str(realm.get("id", "")))
	var head := panel._label("%s%s" % [realm.get("name", "A realm"), "  ★" if friend != "" or realm.get("friend", false) else ""], 14, SessionPanel.INK)
	col.add_child(head)
	var bits := PackedStringArray()
	bits.append(str(realm.get("owner", "")))
	var n := int(realm.get("players", 1))
	bits.append("%d here" % n)
	if str(realm.get("song", "")) != "":
		bits.append("\"%s\"%s" % [realm["song"], "  %d bpm" % int(realm["tempo"]) if int(realm.get("tempo", 0)) > 0 else ""])
	var line := panel._label("  ·  ".join(bits), 12, SessionPanel.DIM)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	var door: LineEdit = null
	if bool(realm.get("door", false)):
		door = panel._edit("session code")
		door.max_length = 12
		door.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(door)
	var go := panel._button("Visit", true)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.disabled = Session.role == Session.Role.GUEST and Session.joined_code == str(realm.get("code", ""))
	go.pressed.connect(func() -> void: visit(realm, door.text if door != null else ""))
	row.add_child(go)
	return box
