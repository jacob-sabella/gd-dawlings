class_name RealmLobby
extends Node

## The lobby (docs/realms.md, step 1): the realms open now, and this player's realm's card among them.
##
## Every game is a realm. Hosting online by a noray code opens it; while it is open, a short card about it goes to the
## realm listing (deploy/realms/realms.mjs) every REFRESH_SECONDS: its name, its owner, the join code, how many are
## in, the song and tempo (if the owner shows them), whether the door asks for a session code, and who may see it.
## The lobby's list is what the listing says this player may see. A visit is a join by the card's code, as typed.
##
## Who is who: this game's realm id (its friend code, `id`) and a secret token are made once and kept in
## `user://realm.cfg` with the realm's settings and the friends list. The listing binds the token to the id the
## first time it hears of it. A friend is someone whose friend code you added: they see your realm when it is
## "friends" only. Not accounts: losing `user://` loses them.
##
## A child of Session ("RealmLobby"), built in SessionLife.ready, reached as `Session.lobby`.

## The realms open now changed (`realms`), or the asking failed (`why_not`).
signal listed()
## The settings or the friends changed.
signal changed()

const PATH := "user://realm.cfg"
## The listing, where a card goes and where the lobby comes from. DAWLINGS_REALMS or the project setting
## `dawlings/session/realms_server` set another.
const DEFAULT_URL := "http://dawlings.jacobsabella.com:8892/realms"
const REFRESH_SECONDS := 30.0
const ID_LENGTH := 10
const ID_ALPHABET := "ACDEFGHJKMNPQRTUVWXY34679"
const MAX_FRIENDS := 200
const MAX_NAME := 40
## Who sees the realm's card: anyone in the lobby, friends only, or nobody (a code read out is the only way in).
const ANYONE := "anyone"
const FRIENDS := "friends"
const CODE_ONLY := "code"
const VISIBILITIES := [FRIENDS, ANYONE, CODE_ONLY]
## What a visitor may copy (RealmCopy): never, only when the owner says yes, or always.
const COPY_NEVER := "never"
const COPY_ASK := "ask"
const COPY_ALWAYS := "always"
const COPY_RULES := [COPY_ASK, COPY_ALWAYS, COPY_NEVER]

var id := ""
var token := ""
## The realm's name on its card; "" is "<name>'s realm".
var realm_name := ""
var visibility := FRIENDS
## Whether the card says what song is open, and its tempo.
var show_song := true
## Whether this game opens its realm (hosts online) when it starts on its own.
var open_on_start := false
var copy_rule := COPY_ASK
## [{id, name}], in the order added.
var friends: Array[Dictionary] = []

## The realms the listing says this player may see, as it said them: {id, name, owner, code, server, players, song,
## tempo, door, visibility, friend}.
var realms: Array = []
## Why the last ask of the listing failed, "" when it did not.
var why_not := ""
## Whether a list is being asked for now.
var asking := false
## What the card said when it was last sent, and whether it is up.
var card_up := false
## Tests: does each ask in place of HTTP, `func(path: String, body: Dictionary) -> Dictionary` answering
## {status, body}; and a store of its own instead of the player's.
var transport := Callable()
var path := PATH
var _clock := 0.0
var _last_card := {}
var _requests: Array[HTTPRequest] = []


func _ready() -> void:
	load_settings()
	Session.online.changed.connect(_on_session_changed)
	Session.role_changed.connect(_on_session_changed)
	Session.roster_changed.connect(_on_session_changed)


func _process(delta: float) -> void:
	_clock += delta
	if _clock < REFRESH_SECONDS:
		return
	_clock = 0.0
	if should_show():
		post_card()


## The listing's address: the environment's, the project's, or dawlings' own.
static func url() -> String:
	var env := OS.get_environment("DAWLINGS_REALMS")
	if env != "":
		return env.trim_suffix("/")
	var setting := str(ProjectSettings.get_setting("dawlings/session/realms_server", ""))
	return setting.trim_suffix("/") if setting != "" else DEFAULT_URL


# --- who this is, and the settings ---------------------------------------------------------------------------

func load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	id = str(cfg.get_value("realm", "id", ""))
	token = str(cfg.get_value("realm", "token", ""))
	if not valid_id(id) or token.length() != 32:
		id = make_id()
		token = make_token()
	realm_name = str(cfg.get_value("realm", "name", ""))
	visibility = str(cfg.get_value("realm", "visibility", FRIENDS))
	if visibility not in VISIBILITIES:
		visibility = FRIENDS
	show_song = bool(cfg.get_value("realm", "show_song", true))
	open_on_start = bool(cfg.get_value("realm", "open_on_start", false))
	copy_rule = str(cfg.get_value("realm", "copy", COPY_ASK))
	if copy_rule not in COPY_RULES:
		copy_rule = COPY_ASK
	friends.clear()
	for f in cfg.get_value("realm", "friends", []):
		if f is Dictionary and valid_id(str(f.get("id", ""))):
			friends.append({"id": str(f["id"]), "name": str(f.get("name", "")).left(MAX_NAME)})
	save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("realm", "id", id)
	cfg.set_value("realm", "token", token)
	cfg.set_value("realm", "name", realm_name)
	cfg.set_value("realm", "visibility", visibility)
	cfg.set_value("realm", "show_song", show_song)
	cfg.set_value("realm", "open_on_start", open_on_start)
	cfg.set_value("realm", "copy", copy_rule)
	cfg.set_value("realm", "friends", friends)
	cfg.save(path)


## Changes a setting by name (name, visibility, show_song, open_on_start, copy), keeps it and puts the card right.
func set_setting(key: String, value: Variant) -> void:
	match key:
		"name": realm_name = str(value).strip_edges().left(MAX_NAME)
		"visibility": visibility = str(value) if str(value) in VISIBILITIES else visibility
		"show_song": show_song = bool(value)
		"open_on_start": open_on_start = bool(value)
		"copy": copy_rule = str(value) if str(value) in COPY_RULES else copy_rule
		_: return
	save_settings()
	changed.emit()
	_on_session_changed()


static func make_id() -> String:
	var out := ""
	for i in ID_LENGTH:
		out += ID_ALPHABET[randi() % ID_ALPHABET.length()]
	return out


static func make_token() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


static func valid_id(s: String) -> bool:
	if s.length() != ID_LENGTH:
		return false
	for c in s:
		if not ID_ALPHABET.contains(c):
			return false
	return true


## A friend code as typed, cleaned: upper case, no spaces or dashes. "" when it is not one.
static func clean_id(typed: String) -> String:
	var s := typed.to_upper().replace(" ", "").replace("-", "")
	return s if valid_id(s) else ""


## A friend code as it is shown: two groups of five.
static func spoken(code: String) -> String:
	return "%s-%s" % [code.left(5), code.substr(5)] if code.length() == ID_LENGTH else code


## Adds a friend by their code; the refusal in words, or "".
func add_friend(typed: String, friend_name: String) -> String:
	var code := clean_id(typed)
	if code == "":
		return "a friend code is ten letters and digits, like %s" % spoken("ACDEF34679")
	if code == id:
		return "that is your own code"
	if friends.size() >= MAX_FRIENDS:
		return "you keep at most %d friends" % MAX_FRIENDS
	for f in friends:
		if f["id"] == code:
			f["name"] = friend_name.strip_edges().left(MAX_NAME) if friend_name.strip_edges() != "" else f["name"]
			save_settings()
			changed.emit()
			return ""
	friends.append({"id": code, "name": friend_name.strip_edges().left(MAX_NAME)})
	save_settings()
	changed.emit()
	_on_session_changed()
	return ""


func remove_friend(code: String) -> void:
	for i in friends.size():
		if friends[i]["id"] == code:
			friends.remove_at(i)
			save_settings()
			changed.emit()
			_on_session_changed()
			return


## A friend's name by their code, "" for someone who is not one.
func friend_name(code: String) -> String:
	for f in friends:
		if f["id"] == code:
			return f["name"]
	return ""


# --- the card ---------------------------------------------------------------------------------------------------

## The realm's name as its card says it.
func shown_name() -> String:
	return realm_name if realm_name != "" else "%s's realm" % Session.local_name


## Whether this realm's card should be up: hosting, online by a code, and not code-only.
func should_show() -> bool:
	return Session.role == Session.Role.HOST and Session.online.is_online() and visibility != CODE_ONLY \
			and Session.online.oid != ""


## The card as it is sent.
func card() -> Dictionary:
	var song := ""
	var tempo := 0.0
	if show_song and DAW.backend != null:
		song = DAW.project_title()
		tempo = DAW.state.tempo if DAW.state != null else 0.0
	var ids: Array[String] = []
	for f in friends:
		ids.append(f["id"])
	return {"name": shown_name(), "owner": Session.local_name, "code": Session.online.oid,
			"server": Session.online.where(),
			"players": maxi(Session.participants.size(), 1), "song": song, "tempo": tempo, "door": Session.code != "",
			"visibility": visibility, "friends": ids}


func _on_session_changed() -> void:
	if should_show():
		var c := card()
		if c != _last_card or not card_up:
			post_card()
	elif card_up:
		take_down()


func post_card() -> void:
	var c := card()
	_last_card = c
	_ask("/open", {"id": id, "token": token, "card": c}, func(status: int, body: Dictionary) -> void:
		card_up = status == 200 and bool(body.get("ok", false))
		if not card_up:
			why_not = _refusal(status, body, "your realm's card was not taken"))


func take_down() -> void:
	card_up = false
	_last_card = {}
	_ask("/close", {"id": id, "token": token}, func(_s: int, _b: Dictionary) -> void: pass)


## Asks the listing for the realms open now; `listed` says when it has answered.
func refresh() -> void:
	asking = true
	_ask("/list", {"id": id, "token": token}, func(status: int, body: Dictionary) -> void:
		asking = false
		if status == 200 and body.get("realms") is Array:
			realms = body["realms"]
			why_not = ""
		else:
			why_not = _refusal(status, body, "the lobby did not answer")
		listed.emit())


static func _refusal(status: int, body: Dictionary, otherwise: String) -> String:
	if status == 0:
		return "the lobby (%s) could not be reached" % url().get_slice("/", 2)
	return str(body.get("error", otherwise))


## One ask of the listing: `done(status, body)`, status 0 when nothing answered.
func _ask(route: String, body: Dictionary, done: Callable) -> void:
	if transport.is_valid():
		var got: Dictionary = transport.call(route, body)
		done.call(int(got.get("status", 0)), got.get("body", {}) if got.get("body") is Dictionary else {})
		return
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	_requests.append(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, raw: PackedByteArray) -> void:
		_requests.erase(req)
		req.queue_free()
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 else null
		done.call(code if result == HTTPRequest.RESULT_SUCCESS else 0, parsed if parsed is Dictionary else {}))
	var err := req.request(url() + route, PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_requests.erase(req)
		req.queue_free()
		done.call(0, {})


func _exit_tree() -> void:
	# A quitting game takes its card down where it can; one that cannot is gone from the lobby within the card's
	# time on the listing (90 seconds) anyway.
	if card_up and not transport.is_valid():
		take_down()
