class_name FX
extends Node3D
## One-shot PSX particle bursts, impact stars, rings, explosions and travelling bullet tracers.

const KINDS := {
	"spark": {"tex": "spark", "add": true, "size": 0.3, "life": 0.3, "speed": 8.0, "grav": 14.0, "damp": 6.0},
	"star": {"tex": "spark", "add": true, "size": 0.6, "life": 0.45, "speed": 6.0, "grav": 4.0, "damp": 4.0},
	"dust": {"tex": "puff", "add": false, "size": 0.5, "life": 0.45, "speed": 2.5, "grav": -1.5, "damp": 4.0},
	"scrap": {"tex": "spark", "add": false, "size": 0.22, "life": 0.7, "speed": 7.0, "grav": 18.0, "damp": 1.0},
	"fire": {"tex": "puff", "add": true, "size": 1.3, "life": 0.55, "speed": 7.0, "grav": -2.0, "damp": 5.0},
	"smoke": {"tex": "puff", "add": false, "size": 1.1, "life": 0.9, "speed": 3.0, "grav": -2.5, "damp": 3.0},
	"confetti": {"tex": "puff", "add": false, "size": 0.2, "life": 1.4, "speed": 8.0, "grav": 7.0, "damp": 2.0},
}
const TRACER_POOL := 64
const TRACER_SPEED := 170.0

var camera: Camera3D
var _mats := {}
var _tracers: Array = []   ## {node, mat, a, b, age, life, len}
var _free_tracers: Array = []
var _tracer_tex_mat: StandardMaterial3D


func _ready() -> void:
	_tracer_tex_mat = StandardMaterial3D.new()
	_tracer_tex_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_tex_mat.albedo_texture = PSXMat.tex("tracer")
	_tracer_tex_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_tracer_tex_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_tex_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer_tex_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tracer_tex_mat.no_depth_test = false
	for i in TRACER_POOL:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1, 0.07)
		var m := _tracer_tex_mat.duplicate() as StandardMaterial3D
		q.material = m
		mi.mesh = q
		mi.visible = false
		mi.top_level = true
		add_child(mi)
		_free_tracers.append({"node": mi, "mat": m})


func _mat(tex_name: String, additive: bool) -> StandardMaterial3D:
	var key := tex_name + ("+" if additive else "")
	if not _mats.has(key):
		_mats[key] = PSXMat.sprite_material(tex_name, additive)
	return _mats[key]


func burst(pos: Vector3, kind: String, color: Color = Color.WHITE, count: int = 12, speed_mul: float = 1.0,
		dir: Vector3 = Vector3.UP, spread: float = 180.0) -> void:
	var k: Dictionary = KINDS.get(kind, KINDS["spark"])
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = count
	p.explosiveness = 1.0
	p.lifetime = k["life"]
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(k["size"], k["size"])
	q.material = _mat(k["tex"], k["add"])
	p.mesh = q
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = k["speed"] * 0.45 * speed_mul
	p.initial_velocity_max = k["speed"] * speed_mul
	p.gravity = Vector3(0, -k["grav"], 0)
	p.damping_min = k["damp"] * 0.5
	p.damping_max = k["damp"]
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.color = color
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(float(k["life"]) + 0.4, false).timeout.connect(p.queue_free)


func _billboard(tex_name: String, size: float, color: Color, additive: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := PSXMat.sprite_material(tex_name, additive)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	q.material = m
	mi.mesh = q
	return mi


func impact(pos: Vector3, color: Color = Color.WHITE, size: float = 1.0) -> void:
	var mi := _billboard("impact", size, color, false)
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.4
	mi.rotation.z = randf() * TAU
	var t := create_tween()
	t.tween_property(mi, "scale", Vector3.ONE * 1.1, 0.04)
	t.tween_property(mi, "scale", Vector3.ONE * 0.2, 0.09)
	t.tween_callback(mi.queue_free)


func ring(pos: Vector3, color: Color = Color.WHITE, size: float = 3.0, time: float = 0.3) -> void:
	var mi := _billboard("ring", 1.0, color, true)
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.3
	var mat: StandardMaterial3D = (mi.mesh as QuadMesh).material
	var t := create_tween().set_parallel(true)
	t.tween_property(mi, "scale", Vector3.ONE * size, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(mat, "albedo_color:a", 0.0, time)
	t.chain().tween_callback(mi.queue_free)


func flat_ring(pos: Vector3, color: Color, size: float, time: float) -> void:
	## A ring lying on the floor (boss shockwave / grenade blast).
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	var m := PSXMat.sprite_material("ring", true)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.albedo_color = color
	q.material = m
	mi.mesh = q
	add_child(mi)
	mi.global_position = Vector3(pos.x, 0.08, pos.z)
	mi.scale = Vector3.ONE * 0.5
	var t := create_tween().set_parallel(true)
	t.tween_property(mi, "scale", Vector3(size, 1, size), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(m, "albedo_color:a", 0.0, time)
	t.chain().tween_callback(mi.queue_free)


func explosion(pos: Vector3, radius: float = 5.0, color: Color = Color(1.0, 0.6, 0.2)) -> void:
	burst(pos, "fire", color, 14, radius / 5.0)
	burst(pos, "smoke", Color(0.35, 0.3, 0.4), 8, radius / 6.0)
	burst(pos, "spark", Color(1.0, 0.9, 0.5), 16, radius / 4.0)
	burst(pos, "scrap", Color(0.9, 0.5, 0.2), 10, radius / 5.0)
	ring(pos + Vector3(0, 0.3, 0), color, radius * 1.1, 0.35)
	flat_ring(pos, color, radius * 2.2, 0.4)
	impact(pos + Vector3(0, 0.4, 0), Color(1, 0.9, 0.6), radius * 0.5)


## Fast streak flying from a to b. Colour tints the white-hot core.
func tracer(a: Vector3, b: Vector3, color: Color = Color(1, 0.95, 0.7), width: float = 0.07) -> void:
	if _free_tracers.is_empty():
		return
	var t: Dictionary = _free_tracers.pop_back()
	var d := b - a
	var dist := d.length()
	if dist < 0.5:
		_free_tracers.append(t)
		return
	t["a"] = a
	t["dir"] = d / dist
	t["dist"] = dist
	t["age"] = 0.0
	t["life"] = dist / TRACER_SPEED + 0.05
	t["len"] = minf(5.0, dist)
	var mi: MeshInstance3D = t["node"]
	(mi.mesh as QuadMesh).size = Vector2(1, width)
	var mat: StandardMaterial3D = t["mat"]
	mat.albedo_color = color
	mi.visible = true
	_tracers.append(t)


func _process(dt: float) -> void:
	if _tracers.is_empty() or camera == null:
		return
	var cam_pos := camera.global_position
	var i := _tracers.size() - 1
	while i >= 0:
		var t: Dictionary = _tracers[i]
		t["age"] = float(t["age"]) + dt
		var age: float = t["age"]
		var dist: float = t["dist"]
		var travelled := minf(dist, age * TRACER_SPEED)
		var tail := maxf(0.0, travelled - float(t["len"]))
		var dir: Vector3 = t["dir"]
		var a: Vector3 = t["a"]
		var mi: MeshInstance3D = t["node"]
		if age >= float(t["life"]) or tail >= dist - 0.05:
			mi.visible = false
			_tracers.remove_at(i)
			_free_tracers.append(t)
		else:
			var p_head := a + dir * travelled
			var p_tail := a + dir * tail
			var mid := (p_head + p_tail) * 0.5
			var seg_len := maxf(0.05, travelled - tail)
			var up := dir.cross(cam_pos - mid)
			if up.length() < 0.001:
				up = Vector3.UP
			up = up.normalized()
			var z := dir.cross(up)
			mi.global_transform = Transform3D(Basis(dir * seg_len, up, z), mid)
		i -= 1


func glow_sprite(size: float, color: Color) -> MeshInstance3D:
	return make_glow(size, color)


## A free-standing additive glow billboard.
static func make_glow(size: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := PSXMat.sprite_material("glow", true)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	q.material = m
	mi.mesh = q
	return mi
