extends RefCounted

## A noray server for the suite, on the loopback: the same lines over TCP, the same registrar over
## UDP, the same relay (one port per registered address, passing UDP on as-is), answered the way
## noray answers (trimsock, errors quoted). Polled by the test, so a run never needs bun, the
## internet or a server of anyone's.
##
## Knobs for the failures a real one has: `bad_punch` answers `connect` with an address nobody is
## at, so a guest's punch never opens and it must fall back to the relay; `deaf_registrar` never
## answers the UDP registration.

var tcp_port := 0
var registrar_port := 0
var bad_punch := false
var deaf_registrar := false
## Every line heard, for the test to read.
var heard: Array[String] = []

var _server := TCPServer.new()
var _registrar := PacketPeerUDP.new()
## {stream, buffer, oid, pid, ip, port, relay}
var _hosts: Array = []
## relay port -> PacketPeerUDP
var _relays: Dictionary = {}
var _next_oid := 0


func start(at_tcp: int, at_udp: int) -> bool:
	tcp_port = at_tcp
	registrar_port = at_udp
	if _server.listen(at_tcp, "127.0.0.1") != OK:
		return false
	return _registrar.bind(at_udp, "127.0.0.1") == OK


func stop() -> void:
	for h in _hosts:
		(h["stream"] as StreamPeerTCP).disconnect_from_host()
	_hosts.clear()
	for p in _relays:
		(_relays[p] as PacketPeerUDP).close()
	_relays.clear()
	_server.stop()
	_registrar.close()


func poll() -> void:
	while _server.is_connection_available():
		var stream := _server.take_connection()
		stream.set_no_delay(true)
		_hosts.append({"stream": stream, "buffer": "", "oid": "", "pid": "", "ip": "", "port": 0, "relay": 0})
	for h in _hosts.duplicate():
		var stream: StreamPeerTCP = h["stream"]
		stream.poll()
		if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_hosts.erase(h)
			continue
		var n := stream.get_available_bytes()
		if n > 0:
			h["buffer"] += (stream.get_data(n)[1] as PackedByteArray).get_string_from_utf8()
		while (h["buffer"] as String).contains("\n"):
			var at: int = (h["buffer"] as String).find("\n")
			var line: String = (h["buffer"] as String).substr(0, at)
			h["buffer"] = (h["buffer"] as String).substr(at + 1)
			heard.append(line)
			_command(h, line)
	while _registrar.get_available_packet_count() > 0:
		var pid := _registrar.get_packet().get_string_from_utf8()
		var ip := _registrar.get_packet_ip()
		var port := _registrar.get_packet_port()
		if deaf_registrar:
			continue
		var found = _by("pid", pid)
		if found == null:
			_registrar.set_dest_address(ip, port)
			_registrar.put_packet(("Unknown host pid: \"%s\"" % pid).to_utf8_buffer())
			continue
		if found["ip"] == "":
			found["ip"] = ip
			found["port"] = port
		_registrar.set_dest_address(ip, port)
		_registrar.put_packet("OK".to_utf8_buffer())
	for relay_port in _relays:
		var socket: PacketPeerUDP = _relays[relay_port]
		while socket.get_available_packet_count() > 0:
			var packet := socket.get_packet()
			var sender = _by_address(socket.get_packet_ip(), socket.get_packet_port())
			var target = _by("relay", relay_port)
			if sender == null or target == null or int(sender["relay"]) == 0:
				continue
			var out: PacketPeerUDP = _relays[int(sender["relay"])]
			out.set_dest_address(target["ip"], target["port"])
			out.put_packet(packet)


## How many relays it is passing on for: one per registered address that asked or was asked.
func relay_count() -> int:
	return _relays.size()


func _command(h: Dictionary, line: String) -> void:
	var space := line.find(" ")
	var command := line if space < 0 else line.substr(0, space)
	var data := "" if space < 0 else line.substr(space + 1)
	match command:
		"register-host":
			_next_oid += 1
			h["oid"] = "K7Q%03d" % _next_oid
			h["pid"] = "pid-%d-%d" % [_next_oid, randi()]
			_say(h, "set-oid " + h["oid"])
			_say(h, "set-pid " + h["pid"])
		"connect":
			var host = _by("oid", data)
			if host == null:
				_say(h, "connect \"Error: Unknown host oid: %s\"" % data)
			elif host["ip"] == "":
				_say(h, "connect \"Error: Host has no remote address registered!\"")
			elif h["ip"] == "":
				_say(h, "connect \"Error: Client has no remote address registered!\"")
			else:
				var host_at := "%s:%d" % [host["ip"], host["port"]]
				var guest_at := "%s:%d" % [h["ip"], h["port"]]
				if bad_punch and host != h:
					# Somewhere nobody listens: the punch cannot open.
					host_at = "127.0.0.1:9"
					guest_at = "127.0.0.1:9"
				_say(h, "connect " + host_at)
				_say(host, "connect " + guest_at)
		"connect-relay":
			var host = _by("oid", data)
			if host == null:
				_say(h, "connect-relay \"Error: Unknown host oid: %s\"" % data)
				return
			_relay_for(host)
			_relay_for(h)
			_say(h, "connect-relay %d" % host["relay"])
			_say(host, "connect-relay %d" % h["relay"])


func _relay_for(h: Dictionary) -> void:
	if int(h["relay"]) != 0:
		return
	var socket := PacketPeerUDP.new()
	socket.bind(0, "127.0.0.1")
	h["relay"] = socket.get_local_port()
	_relays[int(h["relay"])] = socket


func _say(h: Dictionary, line: String) -> void:
	(h["stream"] as StreamPeerTCP).put_data((line + "\n").to_utf8_buffer())


func _by(key: String, value: Variant):
	for h in _hosts:
		if h[key] == value and str(value) != "":
			return h
	return null


func _by_address(ip: String, port: int):
	for h in _hosts:
		if h["ip"] == ip and int(h["port"]) == port:
			return h
	return null
