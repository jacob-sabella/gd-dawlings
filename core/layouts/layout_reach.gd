class_name LayoutReach
extends RefCounted

## Where a person can walk to from the mixing position, on a grid, without a Studio: the walkable
## rectangles, less everything within `clearance` of a solid taller than a step, flooded four ways from
## the start. The query the placement tests make in `_walk_grid`/`_walk_from`/`_walked_to`
## (tests/run_tests.gd), taken from them for the layout validator. The cell is 15 cm, so the 45 cm
## walkway of the tests is three cells; the diagonal probes are at 42 cm.

## The grid's cell size (m).
const CELL := 0.15

var _free := PackedByteArray()
var _seen := PackedByteArray()
var _x0 := 0.0
var _z0 := 0.0
var _nx := 0
var _nz := 0


## Builds the grid over `floor` for a body that needs `clearance` (m) round it. `solids` are
## footprints `{c, h, a, top}`; only those taller than Walker.STEP_HEIGHT block.
static func build(floor: Array[Rect2], solids: Array, clearance: float) -> LayoutReach:
	var g := LayoutReach.new()
	var lo := floor[0].position
	var hi := floor[0].end
	for r in floor:
		lo = Vector2(minf(lo.x, r.position.x), minf(lo.y, r.position.y))
		hi = Vector2(maxf(hi.x, r.end.x), maxf(hi.y, r.end.y))
	g._x0 = lo.x
	g._z0 = lo.y
	g._nx = int((hi.x - lo.x) / CELL) + 1
	g._nz = int((hi.y - lo.y) / CELL) + 1
	var on := PackedByteArray()
	on.resize(g._nx * g._nz)
	for i in g._nx:
		for j in g._nz:
			on[i * g._nz + j] = 1 if LayoutGeometry.on_floor(floor, lo + Vector2(i, j) * CELL) else 0
	g._free.resize(g._nx * g._nz)
	var k := roundi(clearance / CELL)
	var d := roundi(clearance / CELL * 0.7071)
	var ring := [Vector2i(k, 0), Vector2i(-k, 0), Vector2i(0, k), Vector2i(0, -k), Vector2i(d, d), Vector2i(d, -d), Vector2i(-d, d), Vector2i(-d, -d)]
	for i in g._nx:
		for j in g._nz:
			var ok := on[i * g._nz + j] == 1
			for o: Vector2i in ring:
				if not ok:
					break
				var a := i + o.x
				var b := j + o.y
				ok = a >= 0 and a < g._nx and b >= 0 and b < g._nz and on[a * g._nz + b] == 1
			g._free[i * g._nz + j] = 1 if ok else 0
	for s: Dictionary in solids:
		if s.get("top", Walker.SOLID_HEIGHT) > Walker.STEP_HEIGHT:
			g._block(s, clearance)
	return g


## Floods from the free cell nearest `start`. Call before `reached`.
func flood(start: Vector2) -> void:
	_seen = PackedByteArray()
	_seen.resize(_nx * _nz)
	var si := roundi((start.x - _x0) / CELL)
	var sj := roundi((start.y - _z0) / CELL)
	var first := -1
	for r in 20:
		for i in range(si - r, si + r + 1):
			for j in range(sj - r, sj + r + 1):
				if first < 0 and i >= 0 and i < _nx and j >= 0 and j < _nz and _free[i * _nz + j] == 1:
					first = i * _nz + j
		if first >= 0:
			break
	if first < 0:
		return
	var queue := PackedInt32Array([first])
	_seen[first] = 1
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		var i := at / _nz
		var j := at % _nz
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var a := i + step.x
			var b := j + step.y
			if a >= 0 and a < _nx and b >= 0 and b < _nz and _free[a * _nz + b] == 1 and _seen[a * _nz + b] == 0:
				_seen[a * _nz + b] = 1
				queue.append(a * _nz + b)


## Whether a flooded cell lies within `slack` of `p`: the walkway reaches that spot.
func reached(p: Vector2, slack: float) -> bool:
	var si := roundi((p.x - _x0) / CELL)
	var sj := roundi((p.y - _z0) / CELL)
	var r := int(slack / CELL)
	for i in range(si - r, si + r + 1):
		for j in range(sj - r, sj + r + 1):
			if i >= 0 and i < _nx and j >= 0 and j < _nz and _seen[i * _nz + j] == 1:
				return true
	return false


## Whether a flooded cell lies within `within` of the rectangle `box`: one can walk up to it.
func reached_box(box: Rect2, within: float) -> bool:
	var lo := box.position - Vector2.ONE * within
	var hi := box.end + Vector2.ONE * within
	for i in range(maxi(0, int((lo.x - _x0) / CELL)), mini(_nx, int((hi.x - _x0) / CELL) + 2)):
		for j in range(maxi(0, int((lo.y - _z0) / CELL)), mini(_nz, int((hi.y - _z0) / CELL) + 2)):
			if _seen[i * _nz + j] == 1:
				var p := Vector2(_x0 + i * CELL, _z0 + j * CELL)
				var q := Vector2(maxf(maxf(box.position.x - p.x, p.x - box.end.x), 0.0), maxf(maxf(box.position.y - p.y, p.y - box.end.y), 0.0))
				if q.length() <= within:
					return true
	return false


func _block(s: Dictionary, clearance: float) -> void:
	var quad := LayoutGeometry.corners(s)
	var lo := quad[0]
	var hi := quad[0]
	for p in quad:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	for i in range(maxi(0, int((lo.x - clearance - _x0) / CELL)), mini(_nx, int((hi.x + clearance - _x0) / CELL) + 2)):
		for j in range(maxi(0, int((lo.y - clearance - _z0) / CELL)), mini(_nz, int((hi.y + clearance - _z0) / CELL) + 2)):
			if _free[i * _nz + j] == 1 and LayoutGeometry.point_gap(s, Vector2(_x0 + i * CELL, _z0 + j * CELL)) < clearance:
				_free[i * _nz + j] = 0
