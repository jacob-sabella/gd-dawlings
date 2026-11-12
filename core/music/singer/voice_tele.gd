class_name VoiceTele
extends RefCounted

## What a VOICE module's body is doing, as the engine reports it (native/rack/modules_voice.cc `report`, the
## shim's `dv_telemetry` layout): a flat array read here into the parts the singer's head draws.
##
## Header (16): phLen, orLen (the pharynx's and the mouth's length, cm), velumPort (the nose's door, cm²), f0 (Hz),
## voicing (0..1), pLung (the lungs' push), outRms, noiseLevel, noiseNode, gate, clock (s), then the counts nArtic,
## nPh, nOr, nScope, and 1 while a creature plays. Then the articulators (nArtic, CHIMERA's ArticKey order), the
## pharynx's and the mouth's cross-sections (cm²), the pressure in every section then the airflow through every
## section (nPh + nOr each), and the vocal folds' opening over a cycle (16 points).

## CHIMERA's articulators, in its order.
const ARTIC := ["jaw", "tbX", "tbY", "ttX", "ttY", "ttCurl", "root", "lipAp", "lipProt", "lipWidth", "labiodental",
		"velum", "larynx", "epilarynx", "ventricular", "lateral", "dorsum"]
const HEADER := 16
## The vocal folds' points the module sends.
const FOLDS := 16


## The parts of telemetry `t` (as RackEngine.voices[id]["tele"]); `{}` for anything too short to be one.
static func read(t: PackedFloat32Array) -> Dictionary:
	if t.size() < HEADER:
		return {}
	var n_artic := int(t[11])
	var n_ph := int(t[12])
	var n_or := int(t[13])
	var n := n_ph + n_or
	if n_artic != ARTIC.size() or n_ph < 1 or n_or < 1 or t.size() < HEADER + n_artic + 3 * n:
		return {}
	var at := HEADER
	var artic := {}
	for k in n_artic:
		artic[ARTIC[k]] = t[at + k]
	at += n_artic
	var areas := t.slice(at, at + n)
	at += n
	var pressure := t.slice(at, at + n)
	at += n
	var flow := t.slice(at, at + n)
	at += n
	var folds := t.slice(at, mini(at + FOLDS, t.size()))
	return {"ph_len": t[0], "or_len": t[1], "velum_port": t[2], "f0": t[3], "voicing": t[4], "lungs": t[5],
			"rms": t[6], "noise": t[7], "noise_node": int(t[8]), "gate": t[9], "clock": t[10], "creature": t[15] > 0.5,
			"n_ph": n_ph, "n_or": n_or, "artic": artic, "areas": areas, "pressure": pressure, "flow": flow, "folds": folds}


## The loudest airflow or pressure along the airway, for scaling the glow (never 0).
static func peak(values: PackedFloat32Array) -> float:
	var m := 1e-6
	for v in values:
		m = maxf(m, absf(v))
	return m


## The head's outlines in `voiceframe` order (native/voice dv_frame).
const LINES := ["outer", "inner", "tongue", "velum", "upper_lip", "lower_lip", "upper_teeth", "lower_teeth", "jaw_bone",
		"epiglottis", "nasal_cavity"]


## A `voiceframe` line's numbers (after its id) as {glottis: Vector2, lines: {name: PackedVector2Array}}; {} if broken.
static func read_frame(words: PackedStringArray) -> Dictionary:
	if words.size() < 2 + LINES.size():
		return {}
	var at := 2
	var lines := {}
	for name in LINES:
		if at >= words.size():
			return {}
		var n := int(words[at])
		at += 1
		if n < 0 or at + 2 * n > words.size():
			return {}
		var pts := PackedVector2Array()
		pts.resize(n)
		for i in n:
			pts[i] = Vector2(float(words[at + 2 * i]), float(words[at + 2 * i + 1]))
		at += 2 * n
		lines[name] = pts
	return {"glottis": Vector2(float(words[0]), float(words[1])), "lines": lines}
