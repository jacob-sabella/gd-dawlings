class_name NorayLink
extends RefCounted

## A session reached by a short code instead of an address, through a noray server
## (https://github.com/foxssake/noray, MIT): no port forwarding, and no router asked.
##
## What noray does, and nothing more: it is told by every party, host or guest, "I am here" over
## TCP (`register-host`, answered with an open id, the code, and a private id), and the private id
## is sent from the game's own UDP socket to its registrar, so noray learns the address that
## socket has on the internet -- the router's, not the LAN's. A guest then says `connect <code>`,
## and noray tells each side the other's internet address. Both send at once (the punch), each
## router sees an answer to something its own side sent, and the session's ENet runs straight
## between them. Where a router will not be punched through (a strict NAT, a phone tether),
## `connect-relay <code>` gives each side a port on the noray server itself, which passes the
## same UDP on, as-is.
##
## Why this and not the netfox.noray addon: the addon needs netfox's logger (netfox.internals)
## and two autoloads, waits on the scene tree inside every call, and its reply parser splits on
## the first space and keeps one word -- so noray's errors, which come back quoted
## (`connect "Error: Unknown host oid: X"`), read as a connect to the address "Error". This is
## the same four-line protocol, polled from the session's frame, with every refusal kept in words.
##
## The wire (trimsock, one command a line): `name data\n`, data quoted when it has a space in it.
## A reply to `connect` or `connect-relay` that is not an address or a port is noray refusing.
##
## A host registers a socket it does not own: the ENet server's (`via_enet`, through
## `ENetConnection.socket_send`) or the mix feed's (`MixFeed.send_raw`, on its thread). The reply
## lands on that socket, where it is dropped unread. So the host then asks `connect` to its own
## code -- noray only answers with an address once it has one for both ends -- and an address back
## means registered (and is this machine's public address, which is worth saying).

signal changed
## noray says a party is at `address:port` (host: a guest coming in; guest: the host). Punch to it.
signal punch(address: String, port: int)
## noray gave a relay: send to the noray server's `port` (guest), or punch toward it (host).
signal relay(port: int)

enum State { CLOSED, REACHING, REGISTERING, ONLINE, FAILED }

## Where a dawlings noray is run; docs/multiplayer.md and deploy/noray/ say how.
const DEFAULT_SERVER := "dawlings.jacobsabella.com"
const TCP_PORT := 8890
const REGISTRAR_PORT := 8809
## The project setting a build can ship another default in, and the file a player's own is kept in.
const SETTING := "dawlings/session/noray_server"
const PATH := "user://online.cfg"
## How long the server may take to answer the TCP connect, and to hear the UDP registration.
const REACH_SECONDS := 4.0
const REGISTER_SECONDS := 4.0
## How often the private id is sent again while noray has not said OK. UDP can drop it.
const RESEND_SECONDS := 0.15
## Codes this short are the kind dawlings' server makes (deploy/noray/noray.env): read aloud,
## typed in any case, with spaces or dashes. A longer one is another server's, case and all.
const SHORT_CODE := 10

var state := State.CLOSED
## The open id: the code, given to guests. Not a secret -- see docs/multiplayer.md.
var oid := ""
## Where it is, as typed, and as resolved.
var server_host := ""
var server_ip := ""
var tcp_port := TCP_PORT
var registrar_port := REGISTRAR_PORT
## Guest: the local UDP port that was registered, for ENet to bind.
var local_port := 0
## Host: this machine's address as the internet sees it, once noray said.
var public_address := ""
## Why it failed, in words.
var why_not := ""
## Relay ports noray named, so a host can tell relayed guests from punched ones.
var relay_ports: Array[int] = []
## The time limits, as variables so the suite can be quicker than a person.
var reach_seconds := REACH_SECONDS
var register_seconds := REGISTER_SECONDS

var _tcp: StreamPeerTCP = null
var _buffer := ""
var _pid := ""
var _since := 0.0
var _resend := 0.0
## Guest: the socket registered (it gives up its port to ENet). Host: the ENet server's socket.
var _udp: PacketPeerUDP = null
## Host: how to send from the socket being registered, when that socket is someone else's (the ENet
## server's, or the mix's on its thread): func(ip, port, bytes). Unset, the link has its own.
var _sender: Callable = Callable()
var _self_checked := false
var _check := 0.0


## Reach `server` ("host", "host:port"). For a host, `sender` sends from the socket noray must learn
## (`via_enet` for the session's ENet server); a guest's registration uses a socket of its own,
## whose port (`local_port`) is then bound by whatever is to use it.
func open(server: String, sender: Callable = Callable()) -> void:
	close()
	var parsed := split_server(server)
	server_host = parsed[0]
	tcp_port = parsed[1]
	_sender = sender
	why_not = ""
	if server_host.is_empty():
		_fail("No noray server is set. Set one under ONLINE in the session panel (M).")
		return
	server_ip = server_host if server_host.is_valid_ip_address() \
			else IP.resolve_hostname(server_host, IP.TYPE_IPV4)
	if server_ip.is_empty():
		_fail("Could not find the noray server %s (no such name). %s" % [server_host, _set_yours()])
		return
	_tcp = StreamPeerTCP.new()
	if _tcp.connect_to_host(server_ip, tcp_port) != OK:
		_fail("Could not reach the noray server at %s. %s" % [where(), _set_yours()])
		return
	_tcp.set_no_delay(true)
	_since = 0.0
	_become(State.REACHING)


## Service it: the TCP line, the UDP registration, the time limits. Every frame.
func poll(delta: float) -> void:
	if _tcp == null:
		return
	_tcp.poll()
	_since += delta
	match _tcp.get_status():
		StreamPeerTCP.STATUS_CONNECTING:
			if _since > reach_seconds:
				_fail("The noray server at %s did not answer. %s" % [where(), _set_yours()])
			return
		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			if state == State.ONLINE:
				_fail("Lost the noray server at %s. The code no longer works; new guests cannot join by it." % where())
			else:
				_fail("Could not reach the noray server at %s. %s" % [where(), _set_yours()])
			return
	if state == State.REACHING:
		_since = 0.0
		_send("register-host")
		_become(State.REGISTERING)
	var available := _tcp.get_available_bytes()
	if available > 0:
		var got := _tcp.get_data(available)
		if got[0] == OK:
			_buffer += (got[1] as PackedByteArray).get_string_from_utf8()
		var nl := _buffer.find("\n")
		while nl >= 0 and _tcp != null:
			var line := _buffer.substr(0, nl).strip_edges(false, true)
			_buffer = _buffer.substr(nl + 1)
			if not line.is_empty():
				_heard(line)
			nl = _buffer.find("\n")
	if state == State.REGISTERING and not _pid.is_empty():
		_register_remote(delta)


## Guest: find the host with this code over a punch.
func ask_direct(code: String) -> void:
	_send("connect " + chunk(code))


## Guest: through the server's relay instead.
func ask_relay(code: String) -> void:
	_send("connect-relay " + chunk(code))


## Gone from noray: the code stops working. A guest already in the session stays in it.
func close() -> void:
	if _tcp != null:
		_tcp.disconnect_from_host()
	_tcp = null
	if _udp != null:
		_udp.close()
	_udp = null
	_sender = Callable()
	_buffer = ""
	_pid = ""
	oid = ""
	local_port = 0
	public_address = ""
	relay_ports.clear()
	_self_checked = false
	var was := state
	state = State.CLOSED
	if was != State.CLOSED:
		changed.emit()


func is_online() -> bool:
	return state == State.ONLINE


func where() -> String:
	return server_host if tcp_port == TCP_PORT else "%s:%d" % [server_host, tcp_port]


# --- the conversation ---------------------------------------------------------------------

func _heard(line: String) -> void:
	var parsed := parse_line(line)
	var command: String = parsed[0]
	var data: String = parsed[1]
	match command:
		"set-oid":
			oid = data
		"set-pid":
			_pid = data
			_resend = 0.0
			_since = 0.0
			if not _sender.is_valid():
				_udp = PacketPeerUDP.new()
				if _udp.bind(0) != OK:
					_fail("Could not open a UDP socket to register with noray.")
					return
				_udp.set_dest_address(server_ip, registrar_port)
		"connect":
			var at := parse_address(data)
			if at.is_empty():
				_refused(data)
				return
			if state == State.REGISTERING and _sender.is_valid():
				# The host's own code, asked for to learn it is registered: it is.
				_self_checked = true
				public_address = "%s:%d" % [at["ip"], at["port"]]
				_become(State.ONLINE)
				return
			if "%s:%d" % [at["ip"], at["port"]] == public_address:
				# noray tells the asker and the host; for the self-check, both are the host.
				return
			punch.emit(at["ip"], at["port"])
		"connect-relay":
			if not data.is_valid_int():
				_refused(data)
				return
			if not relay_ports.has(int(data)):
				relay_ports.append(int(data))
			relay.emit(int(data))


func _register_remote(delta: float) -> void:
	_since += delta
	if _since > register_seconds:
		_fail("The noray server at %s never heard this machine over UDP (port %d). A firewall may be blocking it." % [
				where(), registrar_port])
		return
	if _udp != null:
		while _udp.get_available_packet_count() > 0:
			var reply := _udp.get_packet().get_string_from_utf8()
			if reply == "OK":
				local_port = _udp.get_local_port()
				_udp.close()
				_udp = null
				_become(State.ONLINE)
				return
			_fail("The noray server refused to register this machine: %s" % reply)
			return
	_resend -= delta
	if _resend > 0.0:
		return
	_resend = RESEND_SECONDS
	if _udp != null:
		_udp.put_packet(_pid.to_utf8_buffer())
	elif _sender.is_valid():
		_sender.call(server_ip, registrar_port, _pid.to_utf8_buffer())
		# Asked a little after each send: the registrar and the TCP line are not ordered.
		_send("connect " + chunk(oid))


## noray turning a connect down, in the player's words.
func _refused(text: String) -> void:
	if state == State.REGISTERING and _sender.is_valid() and text.contains("no remote address"):
		# The host's self-check, asked before the registrar had heard it. Asked again.
		return
	if text.contains("Unknown host oid"):
		_fail("No session is online with that code. Check it with the host: a code is new every time a session goes online.")
	elif text.contains("no remote address") or text.contains("Unknown client"):
		_fail("The session with that code is not reachable yet. Try again in a moment.")
	else:
		_fail("The noray server said: %s" % text)


func _send(line: String) -> void:
	if _tcp != null and _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_tcp.put_data((line + "\n").to_utf8_buffer())


func _fail(why: String) -> void:
	var keep := why
	close()
	why_not = keep
	_become(State.FAILED)


func _become(to: State) -> void:
	state = to
	changed.emit()


func _set_yours() -> String:
	return "Set your noray server under ONLINE in the session panel (M), or see docs/multiplayer.md to run one."


## A sender for `open` that registers an ENet server's own socket.
static func via_enet(enet: ENetConnection) -> Callable:
	return func(ip: String, port: int, bytes: PackedByteArray) -> void:
		if enet != null:
			enet.socket_send(ip, port, bytes)


# --- the words of it ----------------------------------------------------------------------

## "name data" as [name, data], the data unquoted and unescaped as trimsock sends it.
static func parse_line(line: String) -> Array:
	var space := line.find(" ")
	if space < 0:
		return [line, ""]
	var data := line.substr(space + 1).strip_edges()
	if data.length() >= 2 and data.begins_with("\"") and data.ends_with("\""):
		data = data.substr(1, data.length() - 2)
	data = data.replace("\\n", "\n").replace("\\r", "\r").replace("\\\"", "\"")
	return [line.substr(0, space), data]


## A piece of data as trimsock wants it: quoted if it has a space in it.
static func chunk(text: String) -> String:
	if text.contains(" "):
		return "\"%s\"" % text.replace("\"", "\\\"")
	return text.replace("\n", "\\n").replace("\r", "\\r").replace("\"", "\\\"")


## "1.2.3.4:5678" as {ip, port}, or {} for anything else (which is noray saying no).
static func parse_address(data: String) -> Dictionary:
	var colon := data.rfind(":")
	if colon <= 0:
		return {}
	var ip := data.substr(0, colon)
	var port := data.substr(colon + 1)
	if not ip.is_valid_ip_address() or not port.is_valid_int() or int(port) <= 0 or int(port) > 65535:
		return {}
	return {"ip": ip, "port": int(port)}


## "host" or "host:port" as [host, port].
static func split_server(text: String) -> Array:
	text = text.strip_edges()
	var colon := text.rfind(":")
	if colon > 0 and text.substr(colon + 1).is_valid_int() and not text.substr(0, colon).contains(":"):
		return [text.substr(0, colon), int(text.substr(colon + 1))]
	return [text, TCP_PORT]


## A code as typed, as noray wants it. A short one is read aloud and typed in a hurry, so case,
## spaces and dashes are not the code; a long one (another server's default) is taken exactly.
static func clean_code(typed: String) -> String:
	var bare := typed.strip_edges().replace(" ", "").replace("\t", "")
	var short := bare.replace("-", "")
	if short.length() <= SHORT_CODE:
		return short.to_upper()
	return bare


## A code as shown and said: a short one in threes, "N6U U9K".
static func spoken(code: String) -> String:
	if code.length() > SHORT_CODE or code.length() <= 4:
		return code
	var half := ceili(code.length() / 2.0)
	return "%s %s" % [code.substr(0, half), code.substr(half)]


## A code a letter at a time, for reading aloud: "N 6 U U 9 K".
static func letters(code: String) -> String:
	var out := PackedStringArray()
	for c in code:
		out.append(c)
	return " ".join(out)


# --- which server -------------------------------------------------------------------------

## The noray server to use: DAWLINGS_NORAY in the environment (the tooling's), then the player's
## own (kept by `keep_server`), then the project's setting, then dawlings' own.
static func server_setting(path: String = PATH) -> String:
	var env := OS.get_environment("DAWLINGS_NORAY")
	if not env.is_empty():
		return env
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		var kept := str(cfg.get_value("noray", "server", "")).strip_edges()
		if not kept.is_empty():
			return kept
	return str(ProjectSettings.get_setting(SETTING, DEFAULT_SERVER))


## Keep the player's own noray server. Empty goes back to the default.
static func keep_server(server: String, path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("noray", "server", server.strip_edges())
	cfg.save(path)
