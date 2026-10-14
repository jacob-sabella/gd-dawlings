class_name PipeGraph
extends RefCounted

## The audio graph of this machine, as PipeWire has it: every node that makes or takes sound, each
## node's ports, and which output port is patched to which input port -- the picture a patchbay
## such as Carla or qpwgraph draws. Read from `pw-link` (`-o` the output ports, `-i` the input
## ports, `-l` the links), so it is the real devices, not a model of them.
##
## This is the machine's, not the session's: a guest's sound card is the guest's, and the host's
## patching of its own interface means nothing on another computer. Nothing here is sent.

## A port is named "node:port", the way `pw-link` names it.
## {node name: {"outputs": [port, ...], "inputs": [port, ...]}}, in the order they were listed.
var nodes := {}
## Each link as [output port, input port].
var links: Array = []
## Why there is no graph, for the wall to say; empty when there is one.
var error := ""


## The graph that three `pw-link` listings describe.
static func parse(outputs: String, inputs: String, linked: String) -> PipeGraph:
	var g := PipeGraph.new()
	for port in _lines(outputs):
		g._port(port, true)
	for port in _lines(inputs):
		g._port(port, false)
	var from := ""
	for line in linked.split("\n"):
		if line.strip_edges().is_empty():
			continue
		if not line.begins_with(" "):
			from = line.strip_edges()
		elif line.strip_edges().begins_with("|->") and not from.is_empty():
			g.links.append([from, line.strip_edges().trim_prefix("|->").strip_edges()])
	return g


## The node a port belongs to.
static func node_of(port: String) -> String:
	var at := port.find(":")
	return port if at < 0 else port.substr(0, at)


## The part of a port's name after its node's.
static func label_of(port: String) -> String:
	var at := port.find(":")
	return port if at < 0 else port.substr(at + 1)


## A node's name as a wall can fit it: the device prefix off, cut short with an ellipsis.
static func short_name(node: String, limit := 26) -> String:
	for prefix in ["alsa_output.", "alsa_input.", "bluez_output.", "bluez_input."]:
		node = node.trim_prefix(prefix)
	return node if node.length() <= limit else node.substr(0, limit - 1) + "…"


## Nodes with a link first, so what is in use is on the wall when there is no room for the rest.
func nodes_by_use() -> Array:
	var used := {}
	for link in links:
		used[node_of(link[0])] = true
		used[node_of(link[1])] = true
	var names: Array = nodes.keys()
	names.sort_custom(func(a, b): return int(used.has(a)) > int(used.has(b)))
	return names


func is_linked(out_port: String, in_port: String) -> bool:
	return links.any(func(l): return l[0] == out_port and l[1] == in_port)


## Something that changes when the graph does, so a wall rebuilds only when it must.
func signature() -> String:
	var parts := PackedStringArray()
	for n in nodes:
		parts.append("%s:%s|%s" % [n, ",".join(nodes[n]["outputs"]), ",".join(nodes[n]["inputs"])])
	for l in links:
		parts.append("%s>%s" % [l[0], l[1]])
	return "\n".join(parts) + error


func _port(port: String, is_output: bool) -> void:
	var node := node_of(port)
	if not nodes.has(node):
		nodes[node] = {"outputs": [], "inputs": []}
	nodes[node]["outputs" if is_output else "inputs"].append(port)


static func _lines(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in text.split("\n"):
		if not line.strip_edges().is_empty():
			out.append(line.strip_edges())
	return out


## The graph as the machine has it now, by asking `tool` (`pw-link`, or a stand-in). Blocks while
## the tool runs: call it from a thread.
static func fetch(tool := "pw-link") -> PipeGraph:
	var listings: Array[String] = []
	for flag in ["-o", "-i", "-l"]:
		var out := []
		var code := OS.execute(tool, [flag], out, true)
		if code != 0 or out.is_empty():
			var g := PipeGraph.new()
			g.error = "no audio graph: %s %s did not answer" % [tool, flag]
			return g
		listings.append(str(out[0]))
	return parse(listings[0], listings[1], listings[2])


## Patch an output port to an input port, or take that patch out, on this machine. True when the
## tool said it was done. Blocks while it runs.
static func link(out_port: String, in_port: String, tool := "pw-link") -> bool:
	return OS.execute(tool, [out_port, in_port], [], true) == 0


static func unlink(out_port: String, in_port: String, tool := "pw-link") -> bool:
	return OS.execute(tool, ["-d", out_port, in_port], [], true) == 0
