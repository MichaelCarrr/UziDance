class_name World
extends Node3D
## The arena: Blender model, collision boxes from levels/arena.json, neon sky dome, plus the
## small amount of collision maths the game needs (circle push-out, step-up ground, ray casts).

const ARENA_SCENE := preload("res://assets/models/arena.glb")
const STEP := 0.62          ## ledges up to this high are walked / jumped onto, anything taller blocks

var half := 22.0
var wall_h := 9.0
var boxes: Array = []        ## {"aabb": AABB, "kind": String, "top": float}
var spawns: Array[Vector2] = []
var player_start := Vector3(0, 0, 14)
var last_normal := Vector3.UP


func _ready() -> void:
	_load_level()
	var arena := ARENA_SCENE.instantiate()
	PSXMat.apply(arena)
	add_child(arena)
	# neon sky: an inside-out sphere using the cull-disabled cutout shader
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 150.0
	sm.height = 300.0
	sm.radial_segments = 28
	sm.rings = 14
	dome.mesh = sm
	var def: Dictionary = PSXMat.DEFS["Sky"].duplicate()
	def["shader"] = "cutout"
	dome.material_override = PSXMat.make(def)
	dome.position = Vector3(0, 0, 0)
	add_child(dome)


func _load_level() -> void:
	var f := FileAccess.open("res://levels/arena.json", FileAccess.READ)
	if f == null:
		push_error("arena.json missing")
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	half = float(d["half"])
	wall_h = float(d["wall_h"])
	for b in d["boxes"]:
		var c := Vector3(float(b["c"][0]), float(b["c"][1]), float(b["c"][2]))
		var s := Vector3(float(b["s"][0]), float(b["s"][1]), float(b["s"][2]))
		boxes.append({"aabb": AABB(c - s * 0.5, s), "kind": String(b["kind"]), "top": c.y + s.y * 0.5})
	for sp in d["spawns"]:
		spawns.append(Vector2(float(sp[0]), float(sp[1])))
	var ps: Array = d["player_start"]
	player_start = Vector3(float(ps[0]), float(ps[1]), float(ps[2]))


## Height of the floor under (x, z) for something whose feet are at feet_y.
func ground_at(x: float, z: float, feet_y: float, radius: float = 0.3) -> float:
	var h := 0.0
	var m := radius * 0.6
	for b in boxes:
		var a: AABB = b["aabb"]
		var top: float = b["top"]
		if top > h and top <= feet_y + STEP:
			if x > a.position.x - m and x < a.end.x + m and z > a.position.z - m and z < a.end.z + m:
				h = top
	return h


## Push a circle (feet position) out of every box too tall to step onto, and keep it in the arena.
func push_out(p: Vector3, radius: float, height: float = 1.8) -> Vector3:
	for b in boxes:
		var a: AABB = b["aabb"]
		var top: float = b["top"]
		if top <= p.y + STEP or a.position.y >= p.y + height:
			continue
		var cx := clampf(p.x, a.position.x, a.end.x)
		var cz := clampf(p.z, a.position.z, a.end.z)
		var dx := p.x - cx
		var dz := p.z - cz
		var d2 := dx * dx + dz * dz
		if d2 < radius * radius:
			if d2 > 0.000001:
				var d := sqrt(d2)
				var k := (radius - d) / d
				p.x += dx * k
				p.z += dz * k
			else:
				# centre is inside the box: leave through the nearest face
				var l := p.x - a.position.x
				var r := a.end.x - p.x
				var n := p.z - a.position.z
				var f := a.end.z - p.z
				var m := minf(minf(l, r), minf(n, f))
				if m == l:
					p.x = a.position.x - radius
				elif m == r:
					p.x = a.end.x + radius
				elif m == n:
					p.z = a.position.z - radius
				else:
					p.z = a.end.z + radius
	var lim := half - radius
	p.x = clampf(p.x, -lim, lim)
	p.z = clampf(p.z, -lim, lim)
	return p


## Distance along a ray to the first solid thing (box, wall, floor); max_t if none. Sets last_normal.
func raycast(o: Vector3, d: Vector3, max_t: float) -> float:
	var best := max_t
	var nrm := Vector3.ZERO
	# floor
	if d.y < -0.00001:
		var tf := -o.y / d.y
		if tf >= 0.0 and tf < best:
			best = tf
			nrm = Vector3.UP
	# arena walls (inside faces); rays that clear the wall top escape
	for axis in 2:
		var od := o.x if axis == 0 else o.z
		var dd := d.x if axis == 0 else d.z
		if absf(dd) < 0.00001:
			continue
		var plane := half if dd > 0.0 else -half
		var t := (plane - od) / dd
		if t >= 0.0 and t < best and o.y + d.y * t <= wall_h and o.y + d.y * t >= 0.0:
			best = t
			nrm = Vector3(-signf(dd), 0, 0) if axis == 0 else Vector3(0, 0, -signf(dd))
	# boxes (slab test)
	for b in boxes:
		var a: AABB = b["aabb"]
		var tmin := 0.0
		var tmax := best
		var hit_n := Vector3.ZERO
		var ok := true
		for axis in 3:
			var oa := o[axis]
			var da := d[axis]
			var lo := a.position[axis]
			var hi := a.end[axis]
			if absf(da) < 0.00001:
				if oa < lo or oa > hi:
					ok = false
					break
			else:
				var t1 := (lo - oa) / da
				var t2 := (hi - oa) / da
				var sgn := -1.0
				if t1 > t2:
					var tmp := t1
					t1 = t2
					t2 = tmp
					sgn = 1.0
				if t1 > tmin:
					tmin = t1
					hit_n = Vector3.ZERO
					hit_n[axis] = sgn
				tmax = minf(tmax, t2)
				if tmin > tmax:
					ok = false
					break
		if ok and tmin < best:
			best = tmin
			nrm = hit_n
	last_normal = nrm
	return best


func line_clear(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return true
	return raycast(a, d / l, l) >= l - 0.05


func random_spawn(away_from: Vector3, min_dist: float = 12.0) -> Vector2:
	var opts: Array[Vector2] = []
	for s in spawns:
		if Vector2(away_from.x, away_from.z).distance_to(s) >= min_dist:
			opts.append(s)
	if opts.is_empty():
		opts = spawns
	return opts[randi() % opts.size()]
