extends RefCounted

## Realms (docs/realms.md), called from tests/run_tests.gd's `_test_realm_*`: home set aside and come back to, the
## save/discard prompt, the lobby's settings, friends and card (and the real listing, deploy/realms, where node is
## here), and copying a rack, a room and a song between realms.

var t: Node

const DIR := "user://realm_tests"


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


func _clean(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.make_dir_recursive_absolute(dir)


## A project of its own on a stand-in DAW, saved to `DIR/home.dawproject`, then changed and not saved. An empty one:
## saving the demo song renders its parts, which waits on the audio server, and in the suite an earlier test may have
## left the dummy driver's thread busy enough to hold it for minutes.
func _home_with_changes() -> String:
	DAW.use(OfflineBackend.new())
	DAW.new_project(1)
	var path := DIR.path_join("home.dawproject")
	DAW.save_project_as(path)
	DAW.set_tempo(133.0)
	return path


func home_set_aside_and_come_back() -> void:
	_clean(DIR)
	var home := Session.home
	var kept := [home.away, home.project, home.reopen, home.replaced]
	var path := _home_with_changes()
	check("a project with changes no save has kept is asked about", RealmHome.before_leaving()["unsaved"]
			and RealmHome.needs_asking())
	check("SAVE keeps it where it is", RealmHome.save_home() == "" and not DAW.has_unsaved_changes()
			and DAW.project_file() == path)
	check("and leaving needs no asking then", not RealmHome.needs_asking())
	# Nothing over another project of the same name.
	FileAccess.open(DIR.path_join("Song.dawproject"), FileAccess.WRITE).store_string("x")
	check("a free name beside one that is there", RealmHome.free_path(DIR.path_join("Song.dawproject")) == DIR.path_join("Song 2.dawproject"))

	home.set_aside()
	check("set aside: away, with the project's file", home.away and home.project == path and home.reopen == RealmHome.OPEN_NOT)
	var opened: Array = []
	var realm: Array = []
	home.open_project_with = func(p: String) -> PackedStringArray:
		opened.append(p)
		return PackedStringArray()
	home.open_realm_with = func(how: String) -> void: realm.append(how)
	home._check()
	check("a visit that never got in opens nothing again", opened.is_empty() and not home.away)
	home.set_aside()
	home.replaced = true
	home.reopen = RealmHome.OPEN_ONLINE
	var link := Session.link_phase
	Session.link_phase = "finding"
	home._check()
	check("on the way into another realm, home waits", home.away and opened.is_empty())
	Session.link_phase = link
	home._check()
	check("on your own again, the song opens again", opened == [path])
	check("and the realm opens as it was", realm == [RealmHome.OPEN_ONLINE] and not home.away)
	# A guest hopping on keeps home as it was set aside.
	home.set_aside()
	var role := Session.role
	Session.role = Session.Role.GUEST
	home.project = path
	home.set_aside()
	check("hopping on keeps the home set aside", home.away and home.project == path)
	Session.role = role
	home.open_project_with = Callable()
	home.open_realm_with = Callable()
	home.away = kept[0]
	home.project = kept[1]
	home.reopen = kept[2]
	home.replaced = kept[3]
	DAW.use(OfflineBackend.new(), false)
	_clean(DIR)


func leave_prompt_saves_or_discards() -> void:
	_clean(DIR)
	var home := Session.home
	var kept := [home.away, home.project, home.reopen]
	var path := _home_with_changes()
	var gone := [0]
	var go := func() -> void: gone[0] += 1
	RealmLeavePrompt.leave_home(t, "Ada's realm", go)
	var prompt: RealmLeavePrompt = null
	for c in t.get_children():
		if c is RealmLeavePrompt:
			prompt = c
	check("unsaved changes are asked about before going", prompt != null and prompt.is_open() and gone[0] == 0)
	if prompt == null:
		DAW.use(OfflineBackend.new(), false)
		return
	check("the question names the song", prompt._title.text.contains(DAW.project_title()))
	prompt.choose(RealmLeavePrompt.STAY)
	check("STAY goes nowhere", gone[0] == 0 and not prompt.is_open() and not home.away)
	RealmLeavePrompt.leave_home(t, "Ada's realm", go)
	prompt.choose(RealmLeavePrompt.DISCARD)
	check("GO WITHOUT SAVING goes, the changes left unsaved", gone[0] == 1 and DAW.has_unsaved_changes()
			and home.away and home.project == path)
	home.away = false
	RealmLeavePrompt.leave_home(t, "Ada's realm", go)
	prompt.choose(RealmLeavePrompt.SAVE)
	check("SAVE AND GO keeps the song, then goes", gone[0] == 2 and not DAW.has_unsaved_changes())
	home.away = false
	RealmLeavePrompt.leave_home(t, "Ada's realm", go)
	check("nothing to lose: it just goes", gone[0] == 3 and not prompt.is_open())
	prompt.queue_free()
	home.away = kept[0]
	home.project = kept[1]
	home.reopen = kept[2]
	DAW.use(OfflineBackend.new(), false)
	_clean(DIR)


## A RealmLobby of the test's own, its settings in DIR, asking `listing` (an in-process stand-in) instead of HTTP.
func _lobby(listing: Dictionary) -> RealmLobby:
	var lobby := RealmLobby.new()
	lobby.path = DIR.path_join("realm.cfg")
	lobby.transport = func(route: String, body: Dictionary) -> Dictionary:
		listing["asked"].append([route, body])
		return listing["answer"].call(route, body)
	lobby.load_settings()
	return lobby


func lobby_settings_friends_and_card() -> void:
	_clean(DIR)
	var listing := {"asked": [], "answer": func(_r: String, _b: Dictionary) -> Dictionary: return {"status": 200, "body": {"ok": true}}}
	var lobby := _lobby(listing)
	check("a realm id is made, a friend code", RealmLobby.valid_id(lobby.id) and lobby.token.length() == 32)
	var again := _lobby(listing)
	check("and kept", again.id == lobby.id and again.token == lobby.token)
	check("friends see it, by default", lobby.visibility == RealmLobby.FRIENDS and lobby.copy_rule == RealmLobby.COPY_ASK)
	check("a friend code is read in any case, with a dash", RealmLobby.clean_id(RealmLobby.spoken("ACDEF34679").to_lower()) == "ACDEF34679")
	check("nonsense is not a friend", lobby.add_friend("hello", "x") != "")
	check("nor is your own code", lobby.add_friend(lobby.id, "me") != "")
	check("a friend is added", lobby.add_friend("acdef-34679", "Ada") == "" and lobby.friend_name("ACDEF34679") == "Ada")
	check("twice is once", lobby.add_friend("ACDEF34679", "") == "" and lobby.friends.size() == 1)
	lobby.set_setting("name", "  The Basement  ")
	lobby.set_setting("visibility", "everyone")
	check("settings are kept, a wrong one refused", _lobby(listing).realm_name == "The Basement"
			and _lobby(listing).visibility == RealmLobby.FRIENDS and _lobby(listing).friends.size() == 1)
	var card := lobby.card()
	check("the card carries the friends' codes and the realm's name", card["friends"] == ["ACDEF34679"]
			and card["name"] == "The Basement" and card.has("code") and card.has("door"))
	lobby.set_setting("show_song", false)
	check("a song not shown is not on the card", lobby.card()["song"] == "")
	listing["answer"] = func(route: String, _b: Dictionary) -> Dictionary:
		if route == "/list":
			return {"status": 200, "body": {"ok": true, "realms": [{"id": "ACDEF34679", "name": "Ada's", "owner": "Ada", "code": "N6UU9K", "players": 2}]}}
		return {"status": 200, "body": {"ok": true}}
	lobby.refresh()
	check("the lobby lists what the listing says", lobby.realms.size() == 1 and lobby.why_not == "")
	listing["answer"] = func(_r: String, _b: Dictionary) -> Dictionary: return {"status": 0, "body": {}}
	lobby.refresh()
	check("a listing that does not answer is said so", lobby.why_not.contains("could not be reached") and lobby.realms.size() == 1)
	lobby.post_card()
	check("a card not taken is not up", not lobby.card_up)
	check("asks carry who is asking", listing["asked"].all(func(a: Array) -> bool: return a[1]["id"] == lobby.id and a[1]["token"] == lobby.token))
	lobby.remove_friend("ACDEF34679")
	check("a friend removed", lobby.friends.is_empty())
	lobby.free()
	again.free()
	_clean(DIR)


## The real listing (deploy/realms/realms.mjs) under node, where there is one: a card posted by one realm is seen by
## a friend over HTTP, and not by a stranger.
func lobby_against_the_listing() -> void:
	var node := _which("node")
	if node == "":
		check("(no node here: the listing's own tests are deploy/realms/realms.test.mjs)", true)
		return
	var port := 18892 + randi() % 500
	var script := ProjectSettings.globalize_path("res://deploy/realms/realms.mjs")
	var pid := OS.create_process("/bin/sh", ["-c", "REALMS_PORT=%d exec '%s' '%s'" % [port, node, script]])
	var env := OS.get_environment("DAWLINGS_REALMS")
	OS.set_environment("DAWLINGS_REALMS", "http://127.0.0.1:%d/realms" % port)
	_clean(DIR)
	var ada := RealmLobby.new()
	ada.path = DIR.path_join("ada.cfg")
	t.add_child(ada)
	var grace := RealmLobby.new()
	grace.path = DIR.path_join("grace.cfg")
	t.add_child(grace)
	var stranger := RealmLobby.new()
	stranger.path = DIR.path_join("stranger.cfg")
	t.add_child(stranger)
	ada.add_friend(grace.id, "Grace")
	var up := [false]
	for i in 40:
		await t.get_tree().create_timer(0.1).timeout
		var c := ada.card()
		c["code"] = "N6UU9K"
		var said := [false]
		ada._ask("/open", {"id": ada.id, "token": ada.token, "card": c}, func(status: int, b: Dictionary) -> void:
			said[0] = true
			up[0] = status == 200)
		while not said[0]:
			await t.get_tree().process_frame
		if up[0]:
			break
	check("a card goes up on the listing", up[0])
	grace.refresh()
	while grace.asking:
		await t.get_tree().process_frame
	check("a friend sees it (%s)" % grace.why_not, grace.realms.size() == 1 and grace.realms[0]["code"] == "N6UU9K"
			and grace.realms[0].get("friend", false))
	stranger.refresh()
	while stranger.asking:
		await t.get_tree().process_frame
	check("a stranger does not", stranger.why_not == "" and stranger.realms.is_empty())
	OS.kill(pid)
	OS.set_environment("DAWLINGS_REALMS", env)
	for l in [ada, grace, stranger]:
		l.transport = func(_r: String, _b: Dictionary) -> Dictionary: return {}
		l.queue_free()
	_clean(DIR)


static func _which(program: String) -> String:
	var out: Array = []
	if OS.execute("/bin/sh", ["-c", "command -v %s" % program], out) != 0 or out.is_empty():
		return ""
	return str(out[0]).strip_edges()


func copy_rack_room_and_rules() -> void:
	_clean(DIR)
	var copy := Session.realm_copy
	RackUserPresets.dir_override = DIR.path_join("presets")
	var rack := RackPatch.preset(&"acid_line")
	var said := copy.keep_rack(RackPatch.to_dict(rack), "Ada's rack")
	check("a rack sent is kept among the presets (%s)" % said, RackUserPresets.has("Ada's rack"))
	copy.keep_rack(RackPatch.to_dict(rack), "Ada's rack")
	check("again, beside it rather than over it", RackUserPresets.has("Ada's rack 2"))
	check("a rack that is not one is refused", copy.keep_rack("junk", "X").begins_with("The rack could not"))
	RackUserPresets.dir_override = ""

	check("a shipped room is had already", copy.keep_room({"venue": "control_room", "made_room": {}}, "Ada").contains("you have it already"))
	MadeRooms.disabled = false
	MadeRooms.dir_override = DIR.path_join("rooms/")
	_clean(DIR.path_join("rooms"))
	LiveRoom.reset()
	var pieces: Array = []
	for kind in PieceCatalogue.maker_kinds():
		if not MadeRoom.NEEDS.has(kind):
			pieces.append(String(kind))
	var made := MadeRooms.make({"title": "Den", "size": "small", "style": "warm", "zones": [], "pieces": pieces, "annex": true})
	check("(a room to send: %s)" % str(made.get("errors", [])), made["ok"])
	if made["ok"]:
		var row := MadeRooms.row_of(StringName(made["id"]))
		said = copy.keep_room({"venue": made["id"], "made_room": row}, "Ada")
		var own := MadeRooms.own_ids()
		check("a made room sent is kept as one of your own (%s)" % said, own.size() == 2 and said.begins_with("Kept"))
		check("under a name that says whose it was", own.any(func(id: StringName) -> bool:
				return (LiveRoom.layouts().layouts[String(id)] as LayoutData).to_dict().get("title", "") == "Den (from Ada)"))
	check("something not a room is refused", not MadeRooms.keep_copy({"id": "x"}, "X")["ok"])
	_clean(DIR.path_join("rooms"))
	MadeRooms.disabled = true
	MadeRooms.dir_override = ""
	LiveRoom.reset()

	# The owner's rule.
	var rule := Session.lobby.copy_rule
	var notices: Array = []
	var heard := func(text: String) -> void: notices.append(text)
	Session.notice.connect(heard)
	Session.lobby.copy_rule = RealmLobby.COPY_NEVER
	copy.asked_by(7, RealmCopy.RACK, "", 0)
	check("never: nothing waits for the owner", copy.pending.is_empty())
	Session.lobby.copy_rule = RealmLobby.COPY_ASK
	copy.asked_by(7, RealmCopy.SONG, "", 0)
	copy.asked_by(7, RealmCopy.SONG, "", 0)
	check("ask: it waits for the owner, once", copy.pending.size() == 1 and notices.any(func(n: String) -> bool: return n.contains("asks to copy your song")))
	copy.asked_by(7, RealmCopy.BRING, "Tune", RealmCopy.MAX_BYTES + 1)
	check("a song too big to bring is refused", copy.pending.size() == 1)
	Session.lobby.copy_rule = RealmLobby.COPY_ALWAYS
	copy.asked_by(7, RealmCopy.BRING, "Tune", 1000)
	check("a song brought in always asks", copy.pending.size() == 2 and copy.pending[1]["kind"] == RealmCopy.BRING)
	copy.decide(0, false)
	copy.decide(0, false)
	check("answered, nothing waits", copy.pending.is_empty())
	Session.notice.disconnect(heard)
	Session.lobby.copy_rule = rule
	_clean(DIR)


## A song arriving in slices: kept in the projects folder under a name that says whose, only when asked for, and
## not when it comes short or long.
func copy_song_in_slices() -> void:
	_clean(DIR)
	var copy := Session.realm_copy
	var dir := copy.projects_dir
	copy.projects_dir = DIR.path_join("projects")
	var role := Session.role
	Session.role = Session.Role.GUEST
	var bytes := PackedByteArray()
	for i in RealmCopy.SLICE + 100:
		bytes.append(i % 251)
	copy.begun(1, RealmCopy.SONG, "Tune", bytes.size())
	check("a song nobody asked for is not taken", copy._in.is_empty())
	copy.answered(RealmCopy.SONG, true, "", {"title": "Tune", "size": bytes.size(), "owner": "Ada"})
	copy.begun(1, RealmCopy.SONG, "Tune", bytes.size())
	copy.got(1, bytes.slice(0, RealmCopy.SLICE))
	copy.got(1, bytes.slice(RealmCopy.SLICE))
	copy.ended(1)
	var kept := copy.own_projects()
	check("the song asked for is kept in the projects", kept.size() == 1 and kept[0]["title"].begins_with("Tune (from"))
	check("whole", kept.size() == 1 and FileAccess.get_file_as_bytes(kept[0]["path"]) == bytes)
	copy.answered(RealmCopy.SONG, true, "", {"title": "Tune", "size": 10, "owner": "Ada"})
	copy.begun(1, RealmCopy.SONG, "Tune", 10)
	copy.got(1, bytes.slice(0, 20))
	check("one longer than it said is not kept", copy._in.is_empty() and copy.own_projects().size() == 1)
	copy.answered(RealmCopy.SONG, true, "", {"title": "Tune", "size": 10, "owner": "Ada"})
	copy.begun(1, RealmCopy.SONG, "Tune", 10)
	copy.got(1, bytes.slice(0, 5))
	copy.ended(1)
	check("nor one that came short", copy.own_projects().size() == 1)
	copy.answered(RealmCopy.SONG, true, "", {"title": "Tune", "size": 10, "owner": "Ada"})
	copy.begun(5, RealmCopy.SONG, "Tune", 10)
	check("nor one from anyone but the owner", copy._in.is_empty())
	Session.role = role
	copy._on_role_changed()
	copy.projects_dir = dir
	_clean(DIR.path_join("projects"))
	_clean(DIR)
