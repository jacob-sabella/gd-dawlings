class_name TourDeck
extends RefCounted

## The gear draft: three boons (two of the three weighted to show up, with a chance one rides
## in cursed) offered after every brief. `apply` on the card chosen is the only place any of
## this touches the DAW, and only through `DAW`'s own verbs.

## Boons the draft offers. A card with no DAW effect (`loose_tempo`) is pure run-state.
static func all_cards() -> Array[TourCard]:
	var out: Array[TourCard] = []

	var extra_track := TourCard.new()
	extra_track.id = &"extra_track"
	extra_track.title = "Extra Track"
	extra_track.description = "One more track on the desk, free and clear."
	extra_track.is_curse = false
	extra_track._effect = func(_run: TourRun) -> void:
		DAW.add_track(DAW.state.track_indices().size() + 1, "Tour Gear")
	out.append(extra_track)

	var free_effect := TourCard.new()
	free_effect.id = &"free_effect"
	free_effect.title = "Free Effect"
	free_effect.description = "A plugin on the house, dropped on your first track."
	free_effect.is_curse = false
	free_effect._effect = func(_run: TourRun) -> void:
		var tracks := DAW.state.track_indices()
		if tracks.is_empty() or DAW.state.fx_choices.is_empty():
			return
		var plugin: String = DAW.state.fx_choices[0][0]
		DAW.add_fx(tracks[0], plugin, -1)
	out.append(free_effect)

	var loose_tempo := TourCard.new()
	loose_tempo.id = &"loose_tempo"
	loose_tempo.title = "Loose Tempo"
	loose_tempo.description = "The pocket check's beat window opens up, for the rest of the run."
	loose_tempo.is_curse = false
	loose_tempo._effect = func(run: TourRun) -> void:
		run.tempo_tolerance_mult *= 1.5
	out.append(loose_tempo)

	var tight_tempo := TourCard.new()
	tight_tempo.id = &"tight_tempo"
	tight_tempo.title = "Tight Tempo"
	tight_tempo.description = "A curse: the pocket check's beat window closes in."
	tight_tempo.is_curse = true
	tight_tempo._effect = func(run: TourRun) -> void:
		run.tempo_tolerance_mult *= 0.6
	out.append(tight_tempo)

	var muted_track := TourCard.new()
	muted_track.id = &"muted_track"
	muted_track.title = "Muted Track"
	muted_track.description = "A curse: one of your tracks goes quiet."
	muted_track.is_curse = true
	# One of the tracks still sounding: muting one already muted is no curse at all, and was
	# the one roll that made this card do nothing (and its test flake) now and then.
	muted_track._effect = func(run: TourRun) -> void:
		var tracks := DAW.state.track_indices().filter(
				func(i: int) -> bool: return not DAW.state.track(i).mute)
		if tracks.is_empty():
			return
		# Off the run's own seed, like every other draw a card or a brief makes -- so two plays
		# of the same seed mute the same track, not whichever one an unseeded roll happened to
		# land on.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([run.attempt_seed, "muted_track", run.brief_index])
		DAW.set_track_mute(tracks[rng.randi() % tracks.size()], true)
	out.append(muted_track)

	var shorter_clock := TourCard.new()
	shorter_clock.id = &"shorter_clock"
	shorter_clock.title = "Shorter Clock"
	shorter_clock.description = "A curse: the next brief's clock runs down faster."
	shorter_clock.is_curse = true
	shorter_clock._effect = func(run: TourRun) -> void:
		run.next_brief_seconds_mult *= 0.75
	out.append(shorter_clock)

	out.append(_spill_card(&"spill_cowbell", "Cowbell",
			"A cowbell falls out of the case. Somebody grab it: the next brief has a part for it.",
			&"cowbell"))
	out.append(_spill_card(&"spill_woodblock", "Woodblock",
			"A woodblock falls out of the case. Dry, loud, and now somebody's job.", &"woodblock"))
	out.append(_spill_card(&"spill_pad", "Drum Pad",
			"A drum pad falls out of the case. Toms for whoever gets there first.", &"pad"))

	var sour_spill := TourCard.new()
	sour_spill.id = &"sour_spill"
	sour_spill.title = "Sour Spill"
	sour_spill.description = "Something falls out of the case tuned sour. It still has to keep time."
	sour_spill.is_curse = true
	sour_spill.repeatable = true
	sour_spill._effect = func(_run: TourRun) -> void:
		Tour.spill_cursed(&"sour")
	out.append(sour_spill)

	var low_spill := TourCard.new()
	low_spill.id = &"low_spill"
	low_spill.title = "Low Spill"
	low_spill.description = "Something falls out of the case an octave low, like it is under water."
	low_spill.is_curse = true
	low_spill.repeatable = true
	low_spill._effect = func(_run: TourRun) -> void:
		Tour.spill_cursed(&"low")
	out.append(low_spill)

	var marked_spill := TourCard.new()
	marked_spill.id = &"marked_spill"
	marked_spill.title = "Marked Spill"
	marked_spill.description = "Something falls out of the case with one name on it. Nobody else may hold it."
	marked_spill.is_curse = true
	marked_spill.repeatable = true
	marked_spill._effect = func(_run: TourRun) -> void:
		Tour.spill_cursed(&"bound")
	out.append(marked_spill)

	return out


## A boon that spills `kind` out of the case: its effect only ever touches `Tour.run` through
## `Tour.spill`, never the DAW, since an instrument is a room item, not a mix move.
static func _spill_card(id: StringName, title: String, description: String, kind: StringName) -> TourCard:
	var card := TourCard.new()
	card.id = id
	card.title = title
	card.description = description
	card.is_curse = false
	card.repeatable = true
	card._effect = func(_run: TourRun) -> void:
		Tour.spill(kind)
	return card


## Three cards for the draft: never one `exclude` already names (a run never offers a card it
## already holds -- except a repeatable instrument card, which `exclude` never hides), weighted
## toward gear, with a chance one of the three rides in as a curse -- matching "curses can ride
## along". `band_size`/`spilled` (TourRun.band_size/instruments) say how much of the room's
## instruments the band has filled: a spill boon drops once its kind is full (`TourParts.COPIES`
## copies out), a spill curse drops once every kind is, and a band bigger than the room's own
## three is always offered one while it still wants more (`want`).
static func draw(rng: RandomNumberGenerator, exclude: Array[StringName], band_size := 1,
		spilled: Array[StringName] = []) -> Array[TourCard]:
	var pool: Array[TourCard] = []
	for c in all_cards():
		if (c.repeatable or not (c.id in exclude)) and _spill_available(c.id, spilled):
			pool.append(c)
	var boons: Array[TourCard] = pool.filter(func(c: TourCard) -> bool: return not c.is_curse)
	var curses: Array[TourCard] = pool.filter(func(c: TourCard) -> bool: return c.is_curse)
	_shuffle(boons, rng)
	_shuffle(curses, rng)

	var want := band_size - (TourParts.ROOM.size() + spilled.size())
	if want > 0:
		var idx := -1
		for i in boons.size():
			if _is_spill_boon(boons[i].id):
				idx = i
				break
		if idx > 0:
			var promoted := boons[idx]
			boons.remove_at(idx)
			boons.insert(0, promoted)
	else:
		var kept: Array[TourCard] = []
		for c in boons:
			# One roll per card, in pool order, so the same seed always spends the same number
			# of rolls here regardless of how many instrument boons happen to be in the pool.
			if _is_spill_boon(c.id) and rng.randf() >= 0.3:
				continue
			kept.append(c)
		boons = kept

	var curse_slot := not curses.is_empty() and rng.randf() < 0.4
	var boon_slots := 3 - (1 if curse_slot else 0)
	var picked: Array[TourCard] = []
	for c in boons:
		if picked.size() >= boon_slots:
			break
		picked.append(c)
	if curse_slot:
		picked.append(curses[0])
	# Backfill from whatever is left, without a duplicate, so a thin pool (a run that has
	# already drafted most of the deck) still offers three where it can.
	if picked.size() < 3:
		for c in boons + curses:
			if picked.size() >= 3:
				break
			if not (c in picked):
				picked.append(c)
	_shuffle(picked, rng)
	return picked


static func _is_spill_boon(id: StringName) -> bool:
	return String(id).begins_with("spill_")


## Whether `id` still has something to offer, given what the case has already spilled
## (`spilled`, TourRun.instruments): a boon for a kind that is full is a card with nothing to
## do; the three curse spills are only out once every kind is.
static func _spill_available(id: StringName, spilled: Array[StringName]) -> bool:
	if _is_spill_boon(id):
		var kind := StringName(String(id).substr(6))
		return TourParts.copies_of(kind, spilled) < TourParts.COPIES
	if id == &"sour_spill" or id == &"low_spill" or id == &"marked_spill":
		for kind in TourParts.SPILL_KINDS:
			if TourParts.copies_of(kind, spilled) < TourParts.COPIES:
				return true
		return false
	return true


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
