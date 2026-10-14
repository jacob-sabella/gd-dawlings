class_name InternetDoor
extends RefCounted

## A hosted session opened to the internet, not just the room: the router asked over UPnP to
## forward the session's ports to this machine, and asked what its public address is, so the
## host can tell someone across town where to join.
##
## Why the router and not a bind: a machine at home has only its LAN address (192.168.x.x); the
## public one belongs to the router, and nothing here can listen on it. The host already listens
## on every address it has (ENet binds "*"); what is missing is the router passing the traffic on.
##
## Opt in, never automatic: opening a port on someone's router is a change to their network.
## Closed again when the session ends. The mapping has no lease, so a crash leaves it open until
## the router forgets it or the next session's close removes it -- the same ports, the same name.
##
## UPnP discovery blocks for a couple of seconds, so it runs on a thread and reports back on the
## main one through `changed`.

signal changed

enum State { CLOSED, OPENING, OPEN, FAILED }

const DESCRIPTION := "dawlings session"

var state := State.CLOSED
## The router's public address, once it said; "" before.
var public_address := ""
## Why it failed, for the host, in words.
var why_not := ""
## The ports asked for (UDP).
var ports: Array[int] = []

var _upnp: UPNP
var _thread: Thread


## Ask the router to forward `to_ports` (UDP) here. Reports through `changed`.
func open(to_ports: Array[int]) -> void:
	if state == State.OPENING or state == State.OPEN:
		return
	ports = to_ports.duplicate()
	public_address = ""
	why_not = ""
	_become(State.OPENING)
	if _busy():
		# Still asking from a close a moment ago; the router answers one thing at a time.
		_thread.wait_to_finish()
	_join_thread()
	_thread = Thread.new()
	_thread.start(_open_on_thread.bind(ports.duplicate()))


## Take the forwarding down again, if it was put up. Quietly: the session is ending either way.
## Still being asked, the router's answer is undone when it comes (`_report`).
func close() -> void:
	if state == State.OPEN and _upnp != null:
		var upnp := _upnp
		var mapped := ports.duplicate()
		if _busy():
			for p in mapped:
				upnp.delete_port_mapping(p, "UDP")
		else:
			_join_thread()
			_thread = Thread.new()
			_thread.start(func() -> void:
				for p in mapped:
					upnp.delete_port_mapping(p, "UDP"))
	_upnp = null
	public_address = ""
	why_not = ""
	_become(State.CLOSED)


## Wait for whatever the thread is doing; for quitting, so a mapping is not left behind.
func finish() -> void:
	_join_thread()


func _open_on_thread(mapping: Array) -> void:
	var upnp := UPNP.new()
	var found := upnp.discover(2000, 2, "InternetGatewayDevice")
	if found != UPNP.UPNP_RESULT_SUCCESS or upnp.get_gateway() == null \
			or not upnp.get_gateway().is_valid_gateway():
		_report.call_deferred(null, "", "No router answered over UPnP (it may be off in the router's settings).")
		return
	for p in mapping:
		var result := upnp.add_port_mapping(p, p, DESCRIPTION, "UDP", 0)
		if result != UPNP.UPNP_RESULT_SUCCESS:
			_report.call_deferred(null, "", "The router refused to forward UDP %d (UPnP error %d)." % [p, result])
			for undo in mapping:
				upnp.delete_port_mapping(undo, "UDP")
			return
	_report.call_deferred(upnp, upnp.query_external_address(), "")


func _report(upnp: UPNP, address: String, failure: String) -> void:
	_join_thread()
	if state != State.OPENING:
		# Closed while the router was still being asked: take back what it agreed to.
		if upnp != null:
			for p in ports:
				upnp.delete_port_mapping(p, "UDP")
		return
	if upnp == null:
		why_not = failure
		_become(State.FAILED)
		return
	_upnp = upnp
	public_address = address
	_become(State.OPEN)


func _become(to: State) -> void:
	state = to
	changed.emit()


func _busy() -> bool:
	return _thread != null and _thread.is_alive()


func _join_thread() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
