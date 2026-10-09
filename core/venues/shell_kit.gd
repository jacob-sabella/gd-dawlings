class_name ShellKit
extends RefCounted

## The parts of a building's shell that more than one venue builds: a wall with window bays in
## it, and a glazed window with a grid of bars. Static, like ZoneKit; whatever is built is added
## to the `parent` given.


## A wall `thick` deep running along `along` (unit x or z) from `from` to `to`, its centre line
## through `at`, `height` tall, with a window opening `bay` wide from `sill` to `head` centred at
## each of `bays`. Built as a band under the sills, a band over the heads, and piers between the
## bays -- the bands a hair thicker than the piers so no two pieces share a face. Returns each
## opening's centre, for the window that goes in it.
static func wall_with_bays(parent: Node3D, label: String, at: Vector3, along: Vector3, from: float,
		to: float, bays: Array, bay: float, sill: float, head: float, height: float, thick: float,
		material: Material) -> Array[Vector3]:
	var across := Vector3(along.z, 0, along.x)
	var place := func(centre: float, y: float) -> Vector3:
		return at * across.abs() + along * centre + Vector3(0, y, 0)
	var sized := func(length: float, tall: float, deep: float) -> Vector3:
		return along.abs() * length + across.abs() * deep + Vector3(0, tall, 0)
	var length := to - from
	var mid := (from + to) * 0.5
	ZoneKit.block(parent, sized.call(length, sill, thick + 0.004), place.call(mid, sill * 0.5), material,
			label + "Sill")
	ZoneKit.block(parent, sized.call(length, height - head, thick + 0.004),
			place.call(mid, (head + height) * 0.5), material, label + "Head")
	var edges := [from]
	for c: float in bays:
		edges.append(c - bay * 0.5)
		edges.append(c + bay * 0.5)
	edges.append(to)
	for i in range(0, edges.size(), 2):
		var a: float = edges[i]
		var b: float = edges[i + 1]
		if b - a > 0.01:
			ZoneKit.block(parent, sized.call(b - a, head - sill, thick),
					place.call((a + b) * 0.5, (sill + head) * 0.5), material, label + "Pier%d" % (i / 2))
	var out: Array[Vector3] = []
	for c: float in bays:
		out.append(place.call(c, (sill + head) * 0.5))
	return out


## A window filling an opening `size` (along, up) centred at `centre`: one pane of glass in the
## middle of the reveal, and a grid of bars over it -- `uprights` of them including the jambs,
## and crossbars about every `row` metres including the head and sill. The uprights are deeper
## than the crossbars and the crossbars deeper than the pane, their ends tucked inside the jambs,
## so no face is shared.
static func glazed(parent: Node3D, label: String, centre: Vector3, along: Vector3, size: Vector2,
		frame: Material, glass: Material, uprights := 5, row := 0.45, bar := 0.05) -> void:
	var across := Vector3(along.z, 0, along.x).abs()
	var w := size.x - 0.002
	var h := size.y - 0.002
	var pane := ZoneKit.block(parent, along.abs() * w + across * 0.01 + Vector3(0, h, 0), centre, glass,
			label + "Pane")
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inset := bar * 0.5 + 0.001
	for i in uprights:
		var offset := lerpf(-w * 0.5 + inset, w * 0.5 - inset, float(i) / (uprights - 1))
		# A hair shorter than the pane, so their ends are not in one plane.
		ZoneKit.block(parent, along.abs() * bar + across * (bar + 0.02) + Vector3(0, h - 0.004, 0),
				centre + along.abs() * offset, frame, label + "Upright%d" % i)
	var rows := maxi(1, int(round(h / row)))
	for j in rows + 1:
		var y := lerpf(-h * 0.5 + inset, h * 0.5 - inset, float(j) / rows)
		ZoneKit.block(parent, along.abs() * (w - 0.01) + across * bar + Vector3(0, bar, 0),
				centre + Vector3(0, y, 0), frame, label + "Bar%d" % j)
