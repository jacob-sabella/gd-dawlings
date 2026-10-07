class_name OSCPeer
extends RefCounted

## One UDP socket, bidirectional, talking to Reaper's OSC control surface.
##
## Reaper's OSC is not a request/response protocol. You bind a port, Reaper floods it with the
## state of the current bank, and you send messages back whenever a control moves. There is no
## handshake and no error: a wrong port is indistinguishable from a stopped Reaper, which is why
## `packets_received` is exposed and the bootstrap scene shows it.

var _udp := PacketPeerUDP.new()
var _bound := false

var packets_received: int = 0
var packets_sent: int = 0
var last_receive_msec: int = 0


func open(reaper_host: String, send_port: int, listen_port: int) -> Error:
	# Bind before setting the destination: binding is the half that can fail, and failing after
	# the destination is set leaves a peer that looks configured and silently drops every send.
	var err := _udp.bind(listen_port, "0.0.0.0")
	if err != OK:
		push_error("OSCPeer: cannot bind UDP %d (in use by another OSC client?): %s" % [listen_port, error_string(err)])
		return err
	_udp.set_dest_address(reaper_host, send_port)
	_bound = true
	return OK


func close() -> void:
	if _bound:
		_udp.close()
		_bound = false


func is_open() -> bool:
	return _bound


func send(address: String, args: Array = []) -> void:
	if not _bound:
		return
	var packet := OSC.message(address, args)
	if packet.is_empty():
		return
	_udp.put_packet(packet)
	packets_sent += 1


## Drain everything waiting and return it flattened. Called once per frame; Reaper can queue
## dozens of meter updates between frames and leaving them in the socket buffer makes meters lag
## further behind with every frame rather than merely being a frame late.
func poll() -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	if not _bound:
		return messages
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		packets_received += 1
		last_receive_msec = Time.get_ticks_msec()
		messages.append_array(OSC.decode(packet))
	return messages
