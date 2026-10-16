class_name ProjectBridge
extends RefCounted

## Between the game's mix and dawkit's project: the one place that knows both.
##
## dawkit (addons/dawkit, its own repository) is the DAW engine, and knows nothing of this game.
## The game's backends speak MixState: Reaper's vocabulary, faders as tapers, pan 0..1, folders as
## Reaper's depth deltas, tracks by bank-relative index. A DawKitProject speaks a DAW's: decibels,
## pan -1..1, folders as parents, tracks by id. This class turns one into the other, both ways,
## and is all the adapting there is -- dawkit never adapts to the game.
##
## `capture` takes the whole project out of an OfflineBackend (the stand-in or the built-in
## engine), and `load` puts one in, replacing what was there.


## The engine's instrument, as dawkit names it (DawKitTine).
const INSTRUMENT := "tine"

static func capture(backend: OfflineBackend) -> DawKitProject:
	var s := backend.state
	var p := DawKitProject.new()
	p.title = backend.project_title
	p.tempo = s.tempo
	p.tempo_points = s.tempo_points.map(func(pt): return [float(pt[0]), float(pt[1]), DawKitTempoMap.shape_of(pt[2])])
	if not p.tempo_points.is_empty():
		p.tempo_points[0][1] = s.tempo
	p.time_signature = Vector2i(s.beats_per_bar, s.beat_unit)
	p.time_signature_points = s.time_signature_points.duplicate(true)
	p.length = s.project_length
	p.metronome = s.metronome
	p.loop_on = s.looping
	p.loop_start = s.loop_start
	p.loop_end = s.loop_end
	var at: Array = s.markers.keys()
	at.sort()
	for t in at:
		p.markers.append(DawKitMarker.new(float(t), str(s.markers[t])))
	for r in s.regions:
		p.regions.append(DawKitRegion.new(float(r[0]), float(r[1]), str(r[2])))
	p.master.volume_db = s.master.volume_db
	p.master.pan = s.master.pan * 2.0 - 1.0
	for target in s.master.automation:
		p.master.automation.append(DawKitAutomation.new(target, (s.master.automation[target] as Array).duplicate(true)))

	var order: Array = s.track_indices()
	var folders: Array[String] = []
	for index in order:
		var t: MixState.TrackState = s.tracks[index]
		var out := DawKitTrack.new(id_of(index), t.name)
		out.colour = t.colour
		out.parent = folders.back() if not folders.is_empty() else ""
		# The cache's own decibels, not the taper's: taper -> dB -> taper is not exact, and a
		# project opened and saved unchanged must come back unchanged.
		out.volume_db = t.volume_db
		out.pan = t.pan * 2.0 - 1.0
		out.mute = t.mute
		out.solo = t.solo
		out.armed = t.rec_arm
		out.monitor = clampi(t.monitor, 0, 2) as DawKitTrack.Monitor
		out.input = t.input
		out.group = t.group
		# A track with notes on it plays them through the engine's instrument, first in its chain.
		# One the project came with and the engine cannot run is kept as it came.
		if backend.track_instrument(index) != null:
			pass  # an instrument plugin of its own, in its chain
		elif backend.instruments.has(index):
			out.effects.append(DawKitEffect.from_dict(backend.instruments[index]))
		elif t.items.any(func(it: MixState.ItemState) -> bool: return not it.notes.is_empty()):
			var tine := DawKitEffect.new()
			tine.kind = INSTRUMENT
			tine.name = "Tine"
			tine.instrument = true
			out.effects.append(tine)
		for fx_index in t.plugins():
			out.effects.append(_effect(backend, t, fx_index))
		var keys: Array = t.sends.keys()
		keys.sort()
		for k in keys:
			var sd: MixState.SendState = t.sends[k]
			var dest := sd.resolve(s)
			if dest <= 0:
				continue
			var send := DawKitSend.new()
			send.target = id_of(dest)
			# A send keeps only its taper, so its level is rounded to a millionth of a dB, where
			# the conversion both ways settles on the same number.
			send.volume_db = snappedf(backend.taper_to_db(sd.volume), 0.000001)
			send.pan = sd.pan * 2.0 - 1.0
			send.key = sd.key
			send.pre_fader = sd.pre_fader
			out.sends.append(send)
		for it in t.items:
			out.clips.append(_clip(it))
		out.comp = t.comp.map(func(s): return s.duplicate())
		# The engine's instrument, when there is one, is first in the project's chain.
		var shift := out.effects.size() - t.plugins().size()
		var plugins: Array = t.plugins()
		for target in t.automation:
			var name: String = target
			if name.begins_with("send:"):
				name = "send:" + id_of(int(name.substr(5)))
			elif name.begins_with("fx:"):
				var parts := name.split(":")
				if not plugins.has(int(parts[1])):
					continue
				name = "fx:%d:%s" % [plugins.find(int(parts[1])) + shift, parts[2]]
			out.automation.append(DawKitAutomation.new(name, (t.automation[target] as Array).duplicate(true)))
		p.tracks.append(out)
		# Reaper's folder depth: +1 makes this track a folder holding what follows, -n closes n
		# folders after it.
		if t.folder_depth > 0:
			folders.append(out.id)
		else:
			for _i in -t.folder_depth:
				if not folders.is_empty():
					folders.pop_back()
	return p


static func id_of(index: int) -> String:
	return "t%d" % index


## The track index an id from `id_of` names, or 0.
static func index_of(id: String) -> int:
	return id.trim_prefix("t").to_int() if id.begins_with("t") and id.trim_prefix("t").is_valid_int() else 0


static func _effect(backend: OfflineBackend, t: MixState.TrackState, fx_index: int) -> DawKitEffect:
	var f: MixState.FXState = t.fx[fx_index]
	var e := DawKitEffect.new()
	e.kind = String(backend.fx_kind(t.index, fx_index))
	e.name = f.name
	var hosted = backend.hosted_plugin(t.index, fx_index) if backend is GodotBackend else null
	if hosted != null:
		# A third-party plugin: found again by its format and id, and set as it was by its state.
		var info: Dictionary = hosted.info()
		e.kind = ""
		e.plugin_format = info["format"]
		e.plugin_id = info["id"]
		e.state = hosted.get_state()
		e.instrument = hosted.is_instrument()
	elif f.has_meta(&"unhosted"):
		# One this machine could not load, kept as it came so saving does not lose it.
		var kept := DawKitEffect.from_dict(f.get_meta(&"unhosted"))
		kept.enabled = f.enabled
		return kept
	e.enabled = f.enabled
	e.wet = f.wet
	e.preset = f.preset
	var count := 0
	for k in f.params.keys() + f.param_names.keys():
		count = maxi(count, int(k) + 1)
	for i in count:
		e.values.append(float(f.params.get(i, 0.0)))
		e.names.append(str(f.param_names.get(i, "")))
	return e


static func _clip(item: MixState.ItemState) -> DawKitClip:
	var c := DawKitClip.new()
	c.start = item.start
	c.length = item.length
	c.name = item.name
	c.muted = item.muted
	c.locked = item.locked
	c.lane = item.lane
	c.reversed = item.reversed
	c.source = item.source
	c.source_offset = item.source_offset
	c.notes = PackedFloat64Array(Array(item.notes))
	c.fade_in = item.fade_in
	c.fade_out = item.fade_out
	c.fade_shape = item.fade_shape
	c.fade_out_shape = item.fade_out_shape
	c.gain_db = item.gain_db
	c.loop_start = item.loop_start
	c.loop_end = item.loop_end
	return c


## Replaces the backend's project with `p`. Undo history goes with the old project, the desk
## rebuilds, and a session host sends every guest the new project whole (Session listens for
## `project_replaced`). Refused, with the reasons, when the project's references are broken.
##
## `track_parts`: the synthesised part each track plays, by track index (MixState.TrackState.part), for
## a caller that wants the built-in engine's own band under a project it made in memory -- what
## the stand-in gives its tracks by name (OfflineBackend._populate), and what a saved file has
## rendered to WAVs instead. A DawKitProject does not carry it, so a plain load leaves every
## track with none: giving loaded tracks parts by name sounded the band under a count-in and
## after a render's range, where a file's own tracks are meant to be silent.
static func load(p: DawKitProject, backend: OfflineBackend, track_parts: Dictionary = {}) -> PackedStringArray:
	var problems := p.problems()
	if not problems.is_empty():
		return problems
	var s := backend.state
	s.tracks.clear()
	backend.instruments.clear()
	if backend is GodotBackend:
		# The last project's plugins, windows and all; this one's are loaded as its chains are.
		(backend as GodotBackend).hosted.clear()
	# Another project's takes may share a file name with this one's.
	backend.take_peaks.clear()
	s.markers.clear()
	s.regions = p.regions.map(func(r: DawKitRegion) -> Array: return [r.start, r.end, r.name])
	backend.project_title = p.title
	s.beat_unit = p.time_signature.y
	s.time_signature_points = p.time_signature_points.duplicate(true)
	s.tempo = p.tempo
	s.tempo_points = p.tempo_points.duplicate(true)
	s.beats_per_bar = p.time_signature.x
	s.project_length = p.length
	s.metronome = p.metronome
	s.looping = p.loop_on
	s.loop_start = p.loop_start
	s.loop_end = p.loop_end
	s.playing = false
	s.recording = false
	s.position_seconds = 0.0
	s.position_string = s.bar_beat(0.0)
	for m in p.markers:
		s.markers[m.time] = m.name
	s.master.volume = backend.db_to_taper(p.master.volume_db)
	s.master.volume_db = p.master.volume_db
	s.master.pan = (p.master.pan + 1.0) * 0.5
	s.master.automation.clear()
	for lane in p.master.automation:
		if lane.target in MixWire.MASTER_LANES and not lane.points.is_empty():
			s.master.automation[lane.target] = lane.points.duplicate(true)

	var index_of := {}
	for i in p.tracks.size():
		index_of[p.tracks[i].id] = i + 1
	var kinds := {}
	for i in p.tracks.size():
		var src := p.tracks[i]
		var t := s.track(i + 1)
		t.name = src.name
		t.part = str(track_parts.get(i + 1, ""))
		t.colour = src.colour
		t.volume = backend.db_to_taper(src.volume_db)
		t.volume_db = src.volume_db
		t.pan = (src.pan + 1.0) * 0.5
		t.mute = src.mute
		t.solo = src.solo
		t.rec_arm = src.armed
		t.monitor = src.monitor
		t.group = clampi(src.group, 0, DAW.GROUPS)
		t.comp = src.comp.map(func(s): return s.duplicate())
		t.input = src.input
		t.folder_depth = _depth_delta(p, i)
		# Instruments are not in the desk's chain: the engine plays every track's notes through its
		# own (INSTRUMENT), and one it cannot run is left out.
		var chain := src.effects.filter(func(e: DawKitEffect) -> bool: return not e.instrument or _hostable(backend, e))
		for e in src.effects:
			if e.instrument and e.kind != INSTRUMENT and not _hostable(backend, e):
				backend.instruments[i + 1] = e.to_dict()
				break
		for fx_index in chain.size():
			var e: DawKitEffect = chain[fx_index]
			var f := s.fx(i + 1, fx_index)
			f.name = e.name
			f.enabled = e.enabled
			f.wet = e.wet
			f.preset = e.preset
			for pi in e.values.size():
				f.params[pi] = e.values[pi]
				if pi < e.names.size() and not e.names[pi].is_empty():
					f.param_names[pi] = e.names[pi]
			var kind := StringName(e.kind)
			if e.kind.is_empty() and not e.plugin_format.is_empty():
				kind = _host(backend, e, f)
			if kind != &"":
				if not kinds.has(i + 1):
					kinds[i + 1] = {}
				kinds[i + 1][fx_index] = kind
		for send_index in src.sends.size():
			var send := src.sends[send_index]
			var sd := s.send(i + 1, send_index + 1)
			sd.dest_track = int(index_of.get(send.target, -1))
			sd.dest_name = p.track(send.target).name if p.track(send.target) != null else ""
			sd.volume = backend.db_to_taper(send.volume_db)
			sd.pan = (send.pan + 1.0) * 0.5
			sd.key = send.key
			sd.pre_fader = send.pre_fader
		for lane in src.automation:
			var target: String = lane.target
			if target.begins_with("send:"):
				if not index_of.has(target.substr(5)):
					continue
				target = "send:%d" % index_of[target.substr(5)]
			elif target.begins_with("fx:"):
				# The project's chain counts the instrument; the desk's does not.
				var parts := target.split(":")
				var at := int(parts[1])
				if at < 0 or at >= src.effects.size() or src.effects[at].instrument:
					continue
				target = "fx:%d:%s" % [chain.find(src.effects[at]), parts[2]]
			if not lane.points.is_empty():
				t.automation[target] = lane.points.duplicate(true)
		var items: Array = []
		for c in src.clips:
			var item := MixState.ItemState.new()
			item.start = c.start
			item.length = c.length
			item.name = c.name
			item.muted = c.muted
			item.locked = c.locked
			item.lane = c.lane
			item.reversed = c.reversed
			item.source = c.source
			item.source_offset = c.source_offset
			# The file's overview, so a reopened project draws its takes as the sounds they are.
			if not c.source.is_empty():
				if not backend.take_peaks.has(c.source):
					backend.take_peaks[c.source] = AudioTake.overview_of(backend.media_path(c.source))
				item.peaks = backend.take_peaks[c.source]
				if c.reversed:
					item.peaks = item.peaks.duplicate()
					item.peaks.reverse()
			item.notes = PackedFloat32Array(Array(c.notes))
			item.fade_in = c.fade_in
			item.fade_out = c.fade_out
			item.fade_shape = c.fade_shape
			item.fade_out_shape = c.fade_out_shape
			item.gain_db = c.gain_db
			item.loop_start = c.loop_start
			item.loop_end = c.loop_end
			items.append(item)
		s.set_track_items(i + 1, items)
	s.bank_offset = 0
	s.project_track_count = p.tracks.size()
	s.bank_size = mini(maxi(p.tracks.size(), 1), 64)
	backend.forget_history()
	backend.project_loaded(kinds)
	s.bank_changed.emit()
	s.transport_changed.emit()
	s.timeline_changed.emit()
	s.master_changed.emit(&"")
	s.project_replaced.emit()
	return PackedStringArray()


## Whether the built-in engine can load this third-party plugin here.
static func _hostable(backend: OfflineBackend, e: DawKitEffect) -> bool:
	return backend is GodotBackend and not e.plugin_format.is_empty() and HostedPlugins.available() \
			and not PluginCatalogue.shared().find(e.plugin_format, e.plugin_id).is_empty()


## A third-party plugin from the project loaded into its slot `f`, with its saved state: its
## kind, or none when this machine does not have it, in which case it is kept as it came.
static func _host(backend: OfflineBackend, e: DawKitEffect, f: MixState.FXState) -> StringName:
	if _hostable(backend, e):
		var g := backend as GodotBackend
		var key := g.hosted.host(PluginCatalogue.shared().find(e.plugin_format, e.plugin_id), e.state)
		if key != "":
			var row := g.hosted.row(key)
			f.name = MixState.FXState.bare_name(row["name"])
			f.type = MixState.FXState.type_of(row["name"])
			f.host_key = key
			f.params = row["params"]
			f.param_names = row["param_names"]
			f.param_list = row["param_list"]
			return StringName(GodotBackend.HOSTED + key)
	f.type = e.plugin_format
	f.set_meta(&"unhosted", e.to_dict())
	return &""


## Reaper's folder depth for the track at `i`: +1 when the next track is inside it, minus the
## number of folders that close after it otherwise.
static func _depth_delta(p: DawKitProject, i: int) -> int:
	var here := _nesting(p, p.tracks[i])
	var next := _nesting(p, p.tracks[i + 1]) if i + 1 < p.tracks.size() else 0
	return next - here


static func _nesting(p: DawKitProject, t: DawKitTrack) -> int:
	var n := 0
	var up := t.parent
	while not up.is_empty() and n <= p.tracks.size():
		n += 1
		var parent := p.track(up)
		up = parent.parent if parent != null else ""
	return n
