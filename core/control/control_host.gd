class_name ControlHost
extends Node

## The control API and what stands on it, for this process (docs/mcp_assistant.md): the ControlApi with every tool,
## the MCP server (only when wanted, only on the host or solo), the assistant that runs Claude Code against it, and the
## assistant's overlay (F10). Attached once by the bootstrap; `Studio` stays unaware of it.
##
## The server starts when `--control` is given (or DAWLINGS_CONTROL=1, or `server=true` under [control] in
## user://control.cfg), or when the assistant first runs. It stops if this machine joins a session as a guest,
## whose host is the authority. `--control-yes` (DAWLINGS_CONTROL_YES=1, `auto_confirm=true`) answers tier 2 calls
## from clients that are not the assistant (a headless script) with yes; without it they are refused.

const SETTINGS := "user://control.cfg"

## Whether a host is attached to a studio in this process: the assistant's panel stands (Venue.assistant_spot)
## only then, as the Workshop's only where it is on. A studio the tests build has none.
static var stands := false

var studio: Node
var api: ControlApi
var server: ControlServer
var assistant: Assistant
var screen: AssistantScreen
var panel: AssistantPanel
var auto_confirm := false
var _checked := 0.0


static func attach(parent: Node, s: Node) -> ControlHost:
	var h := ControlHost.new()
	h.name = "ControlHost"
	h.studio = s
	if s != null:
		stands = true  # before it is in the tree: its _ready stands the panel
		h.tree_exiting.connect(func() -> void: stands = false)
	parent.add_child(h)
	return h


static func server_wanted() -> bool:
	if OS.get_cmdline_user_args().has("--control") or OS.get_environment("DAWLINGS_CONTROL") == "1":
		return true
	var cfg := ConfigFile.new()
	return cfg.load(SETTINGS) == OK and bool(cfg.get_value("control", "server", false))


static func auto_confirm_wanted() -> bool:
	if OS.get_cmdline_user_args().has("--control-yes") or OS.get_environment("DAWLINGS_CONTROL_YES") == "1":
		return true
	var cfg := ConfigFile.new()
	return cfg.load(SETTINGS) == OK and bool(cfg.get_value("control", "auto_confirm", false))


func _ready() -> void:
	api = ControlTools.make_api(studio)
	auto_confirm = auto_confirm_wanted()
	assistant = Assistant.new()
	assistant.name = "Assistant"
	assistant.host = self
	add_child(assistant)
	api.confirm = _confirm
	screen = AssistantScreen.new()
	screen.name = "AssistantScreen"
	screen.assistant = assistant
	add_child(screen)
	if studio != null and studio.has_signal("venue_changed"):
		studio.venue_changed.connect(func(_id: StringName) -> void: stand_panel())
		stand_panel()
	if server_wanted():
		ensure_server()


## The panel stood again in the studio's venue (a new venue drops the old one with it).
func stand_panel() -> void:
	if studio == null or studio.venue == null:
		return
	var spot: Variant = Stations.spot(studio.venue, AssistantPanel.STATION)
	if spot == null:
		return
	panel = AssistantPanel.new()
	panel.host = self
	panel.transform = spot
	studio.venue.add_child(panel)


## The server, started if it is not: false if this machine may not serve (a guest) or no port was free.
func ensure_server() -> bool:
	if not Session.is_authority():
		return false
	if server != null and server.listening():
		return true
	if server == null:
		server = ControlServer.new()
		server.name = "ControlServer"
		server.api = api
		add_child(server)
	return server.start()


func _confirm(tool_name: String, args: Dictionary, who: int) -> bool:
	return await assistant.confirm(tool_name, args, who)


func _process(delta: float) -> void:
	_checked += delta
	if _checked < 1.0:
		return
	_checked = 0.0
	if server != null and server.listening() and not Session.is_authority():
		server.stop()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F10:
		get_viewport().set_input_as_handled()
		screen.toggle()
