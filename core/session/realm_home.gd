class_name RealmHome
extends Node

## Your own realm while you visit someone else's (docs/realms.md, step 2).
##
## Visiting replaces this game's DAW with a stand-in that only mirrors the owner's (SessionLife.join), and leaving
## starts a fresh one from the launch arguments (Session.solo_backend). So before going anywhere, the project open
## here is set aside: its file is remembered (saved first, if the player chose SAVE in RealmLeavePrompt), and whether
## the realm was open to visitors. Coming home -- on your own again and not on the way somewhere else -- the project
## is opened again from that file and the realm opened again as it was.
##
## A child of Session ("RealmHome"), built in SessionLife.ready, reached as `Session.home`.

signal came_home()

## How the realm was open when its owner went visiting: not at all, on this network, or online by a code.
const OPEN_NOT := ""
const OPEN_LAN := "lan"
const OPEN_ONLINE := "online"

## True from leaving home until coming back to it.
var away := false
## The project file open at home when its owner left, "" for one never saved (or a DAW that keeps its own).
var project := ""
## How the realm was open (OPEN_*), to open it the same way again.
var reopen := OPEN_NOT
## Whether this game's DAW was replaced while away (a visit got as far as the door): only then is the project
## opened again. A visit that never reached anyone left the project open as it was.
var replaced := false
## Tests: what opens a project and what opens the realm, in place of DAW.open_project and Session.host_online.
var open_project_with := Callable()
var open_realm_with := Callable()
var _checking := false


func _ready() -> void:
	Session.role_changed.connect(_on_change)
	Session.link_changed.connect(_on_change)


## What there is to ask before leaving home: `{unsaved, title, guests, file}`. `guests` is how many visitors this
## realm has now (a host going visiting sends them home).
static func before_leaving() -> Dictionary:
	var guests := 0
	if Session.role == Session.Role.HOST:
		guests = maxi(Session.participants.size() - 1, 0)
	var unsaved := Session.is_authority() and DAW.backend != null and DAW.has_unsaved_changes()
	return {"unsaved": unsaved, "title": DAW.project_title() if DAW.backend != null else "",
			"guests": guests, "file": DAW.project_file() if DAW.backend != null and Session.is_authority() else ""}


## Whether leaving home needs the player's word first: unsaved changes, or visitors who would be sent home.
static func needs_asking() -> bool:
	var b := before_leaving()
	return b["unsaved"] or int(b["guests"]) > 0


## Saves the home project where it is, or (never saved) under its title in the projects folder, beside and never over
## another project of that name. "" when it is kept, else why not.
static func save_home() -> String:
	if DAW.backend == null or not Session.is_authority():
		return "there is no project here to save"
	var path := DAW.project_file()
	if path.is_empty() and DAW.backend is OfflineBackend:
		path = free_path(ProjectFiles.default_path(DAW.project_title()))
	var said := DAW.save_project_as(path)
	if DAW.has_unsaved_changes():
		return "it could not be saved%s" % (": " + "; ".join(said) if not said.is_empty() else "")
	return ""


## `path`, or the same name with " 2", " 3"... before its extension when a file is there already.
static func free_path(path: String) -> String:
	if not FileAccess.file_exists(path):
		return path
	var stem := path.get_basename()
	var ext := path.get_extension()
	var n := 2
	while FileAccess.file_exists("%s %d.%s" % [stem, n, ext]):
		n += 1
	return "%s %d.%s" % [stem, n, ext]


## Remembers home as it is, just before leaving it. A guest hopping on to another realm is already away: home stays
## as it was set aside.
func set_aside() -> void:
	if Session.role == Session.Role.GUEST or away:
		away = true
		return
	away = true
	replaced = false
	project = DAW.project_file() if DAW.backend != null else ""
	if Session.role != Session.Role.HOST:
		reopen = OPEN_NOT
	elif Session.online.is_online():
		reopen = OPEN_ONLINE
	else:
		reopen = OPEN_LAN


func _on_change() -> void:
	if Session.role == Session.Role.GUEST and away:
		replaced = true
	if not _checking:
		_checking = true
		_check.call_deferred()


## Home again once this game is on its own and not on its way into another realm.
func _check() -> void:
	_checking = false
	if not away or Session.role != Session.Role.SOLO or not Session.link_phase.is_empty():
		return
	come_home()


## Opens the project set aside and the realm as it was open. Called once a visit is over (`_check`).
func come_home() -> void:
	away = false
	if replaced and project != "" and FileAccess.file_exists(project):
		var said: PackedStringArray = open_project_with.call(project) if open_project_with.is_valid() \
				else DAW.open_project(project)
		if not said.is_empty():
			Session.notice.emit("Your song did not open again: %s" % "; ".join(said))
	replaced = false
	var how := reopen
	reopen = OPEN_NOT
	if how != OPEN_NOT:
		if open_realm_with.is_valid():
			open_realm_with.call(how)
		elif how == OPEN_ONLINE:
			Session.host_online()
		else:
			Session.host()
	came_home.emit()
