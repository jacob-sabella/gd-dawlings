class_name LatencyReport
extends RefCounted

## What the plugins on a project add to the sound's way out, track by track, and what a desk
## that lined them up would delay each track by. Pure: the plugins' latencies come in as a
## Callable (track, fx) -> samples, so any backend can be reported on.
##
## A track's path is its own chain plus every folder it sits in (a folder's chain is run after
## its children's). Sends are not followed. `comp` is how much later than the slowest path a track
## would have to be held back to line up with it: the delay a compensating engine adds.

## One row per track, in track order: {track, own, path, comp} in samples.
static func build(state: MixState, fx_latency: Callable) -> Array:
	var own := {}
	var parent := {}
	var stack: Array = []
	for i in state.track_indices():
		var t: MixState.TrackState = state.tracks[i]
		var sum := 0
		for k in t.plugins():
			var f: MixState.FXState = t.fx[k]
			if f.enabled:
				sum += maxi(int(fx_latency.call(i, k)), 0)
		own[i] = sum
		parent[i] = stack[-1] if not stack.is_empty() else 0
		if t.folder_depth > 0:
			stack.append(i)
		elif t.folder_depth < 0:
			for _n in -t.folder_depth:
				if not stack.is_empty():
					stack.pop_back()
	var rows: Array = []
	var longest := 0
	for i in state.track_indices():
		var path := int(own[i])
		var up: int = parent[i]
		while up > 0:
			path += int(own[up])
			up = parent[up]
		longest = maxi(longest, path)
		rows.append({"track": i, "own": own[i], "path": path, "comp": 0})
	for r in rows:
		r["comp"] = longest - int(r["path"])
	return rows


## The slowest path, in samples.
static func longest(rows: Array) -> int:
	var out := 0
	for r in rows:
		out = maxi(out, int(r["path"]))
	return out


static func milliseconds(samples: int, rate: float) -> float:
	return 1000.0 * float(samples) / maxf(rate, 1.0)


## One line for the desk: "plugin latency 12.3 ms (Lead), 0 ms on every other track".
static func summary(state: MixState, rows: Array, rate: float) -> String:
	var slow := longest(rows)
	if slow <= 0:
		return "no plugin adds latency"
	var who: Array = []
	for r in rows:
		if int(r["path"]) == slow:
			who.append(state.track(int(r["track"])).display_name())
	return "%.1f ms through %s" % [milliseconds(slow, rate), ", ".join(who)]
