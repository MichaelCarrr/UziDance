class_name Enemy
extends Node3D
## One enemy class for every robot: SCRAPPER (melee), SENTRY (ranged), BRUTE (charger),
## HOVERBOT (flying), TITAN (boss). Models are Blender .glb files animated procedurally.

signal died(enemy: Enemy)

const MODELS := {
	"grunt": preload("res://assets/models/grunt.glb"),
	"gunner": preload("res://assets/models/gunner.glb"),
	"brute": preload("res://assets/models/brute.glb"),
	"drone": preload("res://assets/models/drone.glb"),
	"titan": preload("res://assets/models/titan.glb"),
}

## spheres: [height above feet, radius, is_head] (scaled by `scale_mul`)
const TYPES := {
	"grunt": {"name": "SCRAPPER", "hp": 42.0, "speed": 3.8, "radius": 0.45, "height": 1.9, "score": 100,
		"spheres": [[1.74, 0.23, true], [1.3, 0.34, false], [0.95, 0.3, false], [0.45, 0.27, false]]},
	"gunner": {"name": "SENTRY", "hp": 34.0, "speed": 3.0, "radius": 0.4, "height": 1.9, "score": 175,
		"spheres": [[1.72, 0.21, true], [1.3, 0.3, false], [0.95, 0.26, false], [0.45, 0.23, false]]},
	"brute": {"name": "BRUTE", "hp": 300.0, "speed": 2.7, "radius": 0.78, "height": 2.5, "score": 500,
		"spheres": [[2.1, 0.28, true], [1.55, 0.58, false], [1.05, 0.46, false], [0.5, 0.42, false]]},
	"drone": {"name": "HOVERBOT", "hp": 26.0, "speed": 5.6, "radius": 0.36, "height": 0.8, "score": 150,
		"spheres": [[0.0, 0.17, true], [0.0, 0.36, false]]},
	"titan": {"name": "TITAN", "hp": 1700.0, "speed": 2.3, "radius": 1.2, "height": 3.6, "score": 5000,
		"spheres": [[3.05, 0.4, true], [2.2, 0.95, false], [1.5, 0.7, false], [0.7, 0.6, false]]},
}

var kind := "grunt"
var run: Run
var world: World
var player: Player
var fx: FX
var hp := 40.0
var max_hp := 40.0
var radius := 0.45
var height := 1.9
var flying := false
var alive := true
var speed := 3.5
var dmg_mul := 1.0
var scale_mul := 1.0
var score := 100
var boss := false
var spawn_t := 0.0                  ## >0 while rising out of the gate
var model: Node3D
var _mats: Array = []
var _flash := 0.0
var _flash_col := Color.WHITE
var _anim := 0.0
var _atk_cd := 1.0
var _state := "move"
var _state_t := 0.0
var _charge_dir := Vector3.ZERO
var _strafe := 1.0
var _strafe_t := 0.0
var _burn_dps := 0.0
var _burn_t := 0.0
var _burn_tick := 0.0
var _stuck_t := 0.0
var _stuck_last := Vector3.ZERO
var _side_t := 0.0
var _side_dir := Vector3.ZERO
var _phase := 0
var _wave_r := -1.0                  ## titan shockwave radius (-1 = inactive)
var _wave_hit := false
var _hover_y := 2.4
var _hover_ph := 0.0
var _spheres: Array = []
var _nodes := {}
var _vy := 0.0


func setup(p_kind: String, p_run: Run, wave: int) -> void:
	kind = p_kind
	run = p_run
	world = run.world
	player = run.player
	fx = run.fx
	var t: Dictionary = TYPES[kind]
	radius = float(t["radius"])
	height = float(t["height"])
	score = int(t["score"])
	flying = kind == "drone"
	boss = kind == "titan"
	var w := float(maxi(0, wave - 1))
	max_hp = float(t["hp"]) * (1.0 + 0.13 * w)
	if boss:
		max_hp *= 1.0 + 0.18 * w
	hp = max_hp
	speed = float(t["speed"]) * minf(1.55, 1.0 + 0.025 * w)
	dmg_mul = 1.0 + 0.035 * w
	_spheres = t["spheres"]
	scale_mul = 1.45 if boss else 1.0
	if boss:
		radius *= 1.0
		height *= 1.0
	model = (MODELS[kind] as PackedScene).instantiate()
	add_child(model)
	model.scale = Vector3.ONE * scale_mul
	var made := PSXMat.apply(model)
	_mats = made.values()
	for n in ["Hips", "Torso", "Head", "ArmL", "ArmR", "ForearmL", "ForearmR", "LegL", "LegR", "ShinL", "ShinR",
			"Rotor", "Muzzle", "SpikeL", "SpikeR"]:
		_nodes[n] = model.find_child(n, true, false)
	add_to_group("enemies")
	_atk_cd = randf_range(0.6, 1.6)
	_strafe = 1.0 if randf() < 0.5 else -1.0
	_hover_ph = randf() * TAU
	_hover_y = 2.2 + randf() * 1.0
	spawn_t = 0.9 if not boss else 1.6
	_stuck_last = global_position


func center() -> Vector3:
	var s: Array = _spheres[1] if _spheres.size() > 1 else _spheres[0]
	return global_position + Vector3(0, float(s[0]) if not flying else 0.0, 0)


func top() -> Vector3:
	return global_position + Vector3(0, height, 0)


# ----------------------------------------------------------------- damage
func ray_hit(o: Vector3, d: Vector3, max_t: float) -> Dictionary:
	if not alive or spawn_t > 0.55:
		return {}
	var best := INF
	var is_head := false
	for s in _spheres:
		var hy := float(s[0]) * (1.0 if boss else 1.0)
		var c := global_position + Vector3(0, hy if not flying else 0.0, 0)
		var r := float(s[1])
		var oc := o - c
		var b := oc.dot(d)
		var cc := oc.dot(oc) - r * r
		var disc := b * b - cc
		if disc < 0.0:
			continue
		var t := -b - sqrt(disc)
		if t < 0.0:
			t = -b + sqrt(disc)
			if t < 0.0:
				continue
		if t < best:
			best = t
			is_head = bool(s[2])
	if best > max_t:
		return {}
	return {"t": best, "head": is_head}


## Returns true if this hit killed the enemy.
func take_hit(dmg: float, head: bool, point: Vector3, dir: Vector3, crit: bool) -> bool:
	if not alive:
		return false
	hp -= dmg
	_flash = 0.09
	_flash_col = Color(1, 1, 1) if not crit else Color(1.0, 0.9, 0.3)
	fx.burst(point, "scrap" if randf() < 0.5 else "spark", Color(1.0, 0.7, 0.3) if kind != "gunner" else Color(0.7, 0.6, 1.0),
		3 if not head else 6, 0.7, -dir, 80.0)
	if head or crit:
		fx.impact(point, Color(1, 0.9, 0.3), 0.7)
	if hp <= 0.0:
		_die()
		return true
	if not boss and randf() < 0.35:
		Sfx.play("enemy_hurt", -12.0, randf_range(0.8, 1.2))
	return false


func ignite(dps: float, secs: float) -> void:
	_burn_dps = maxf(_burn_dps, dps)
	_burn_t = secs


func _die() -> void:
	alive = false
	remove_from_group("enemies")
	Sfx.play("enemy_die", -4.0 if not boss else 0.0, 1.0 if not boss else 0.6, 0.08)
	fx.burst(center(), "scrap", Color(1.0, 0.65, 0.25), 10 if not boss else 30, 1.0)
	fx.burst(center(), "smoke", Color(0.3, 0.28, 0.35), 3 if not boss else 10, 0.8)
	if boss or kind == "brute":
		fx.explosion(center(), 3.5 if kind == "brute" else 7.0)
	elif kind == "drone":
		fx.explosion(global_position, 2.0)
	died.emit(self)
	_state = "dead"
	_state_t = 0.0
	if kind == "drone" or boss:
		queue_free()


# ------------------------------------------------------------------- loop
func _process(dt: float) -> void:
	if run == null:
		return
	if _state == "dead":
		_state_t += dt
		var k := clampf(_state_t / 0.45, 0.0, 1.0)
		model.rotation.x = -k * 1.35
		model.position.y = -k * 0.25
		if _state_t > 0.9:
			queue_free()
		return
	# flash
	if _flash > 0.0:
		_flash -= dt
		var on := _flash > 0.0
		for m in _mats:
			(m as ShaderMaterial).set_shader_parameter("flash", 0.75 if on else 0.0)
			if on:
				(m as ShaderMaterial).set_shader_parameter("flash_color", _flash_col)
	# burning
	if _burn_t > 0.0:
		_burn_t -= dt
		_burn_tick -= dt
		if _burn_tick <= 0.0:
			_burn_tick = 0.25
			fx.burst(center() + Vector3(randf_range(-0.2, 0.2), 0.3, randf_range(-0.2, 0.2)), "fire",
				Color(1.0, 0.5, 0.15, 0.8), 1, 0.3)
			if take_hit(_burn_dps * 0.25, false, center(), Vector3.UP, false):
				return
	if not player.alive:
		_idle_anim(dt)
		return
	if spawn_t > 0.0:
		spawn_t -= dt
		var k := 1.0 - clampf(spawn_t / (0.9 if not boss else 1.6), 0.0, 1.0)
		model.position.y = -height * (1.0 - k) * (0.0 if flying else 1.0)
		if flying:
			model.position.y = 0.0
		_anim += dt * 3.0
		return
	model.position.y = 0.0
	if run.debug_freeze:
		return
	match kind:
		"grunt":
			_ai_grunt(dt)
		"gunner":
			_ai_gunner(dt)
		"brute":
			_ai_brute(dt)
		"drone":
			_ai_drone(dt)
		"titan":
			_ai_titan(dt)
	_separate(dt)
	# keep to the ground / stage
	if not flying:
		var p := global_position
		var g := world.ground_at(p.x, p.z, p.y, radius)
		if p.y > g + 0.01:
			_vy -= 24.0 * dt
			p.y = maxf(g, p.y + _vy * dt)
			if p.y <= g:
				_vy = 0.0
		else:
			p.y = g
			_vy = 0.0
		global_position = p


func _idle_anim(dt: float) -> void:
	_anim += dt * 2.0
	if _nodes.get("Rotor") != null:
		(_nodes["Rotor"] as Node3D).rotation.y += dt * 30.0


func _to_player() -> Vector3:
	var d := player.global_position - global_position
	d.y = 0.0
	return d


func _face(dir: Vector3, dt: float, rate: float = 10.0) -> void:
	if dir.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(dt * rate, 0.0, 1.0))


func _walk(dir: Vector3, spd: float, dt: float) -> void:
	if dir.length() < 0.01:
		return
	# stuck detection: if barely moving toward the player, slide sideways for a moment
	_stuck_t += dt
	if _stuck_t > 0.6:
		if global_position.distance_to(_stuck_last) < spd * 0.25:
			_side_t = 0.7
			_side_dir = dir.rotated(Vector3.UP, PI * 0.5 * (1.0 if randf() < 0.5 else -1.0))
		_stuck_t = 0.0
		_stuck_last = global_position
	var d := dir.normalized()
	if _side_t > 0.0:
		_side_t -= dt
		d = (d * 0.35 + _side_dir * 0.8).normalized()
	var p := global_position + d * spd * dt
	p = world.push_out(p, radius, height)
	global_position = p


func _separate(dt: float) -> void:
	var p := global_position
	for o in run.enemy_list:
		var e := o as Enemy
		if e == null or e == self or not e.alive or e.flying != flying:
			continue
		var dx := p.x - e.global_position.x
		var dz := p.z - e.global_position.z
		var md := radius + e.radius
		var d2 := dx * dx + dz * dz
		if d2 < md * md and d2 > 0.0001:
			var d := sqrt(d2)
			var push := (md - d) * 0.5 * minf(1.0, dt * 12.0)
			p.x += dx / d * push
			p.z += dz / d * push
	global_position = world.push_out(p, radius, height) if not flying else p


func _hurt_player(amount: float) -> void:
	player.hurt(amount * dmg_mul, global_position)


# ---------------------------------------------------------------- grunt
func _ai_grunt(dt: float) -> void:
	var to := _to_player()
	var dist := to.length()
	_face(to, dt)
	_atk_cd -= dt
	if _state == "windup":
		_state_t -= dt
		_arms(-2.5 + (1.0 - _state_t / 0.35) * 0.0, dt)
		if _state_t <= 0.0:
			_state = "move"
			_atk_cd = 1.0
			if _to_player().length() < 2.1:
				_hurt_player(13.0)
				Sfx.play("hit_big", -10.0, 1.4)
			_arms(-0.2, dt, true)
		return
	if dist < 1.55 and _atk_cd <= 0.0:
		_state = "windup"
		_state_t = 0.35
		return
	if dist > 1.2:
		_walk(to, speed, dt)
		_anim += dt * speed * 2.4
	_gait(0.7)
	_arms(-1.45 + sin(_anim * 0.5) * 0.08, dt)


func _arms(rot_x: float, _dt: float, snap: bool = false) -> void:
	for n in ["ArmL", "ArmR"]:
		var a := _nodes.get(n) as Node3D
		if a != null:
			a.rotation.x = rot_x if snap else lerpf(a.rotation.x, rot_x, 0.5)
	for n in ["ForearmL", "ForearmR"]:
		var a := _nodes.get(n) as Node3D
		if a != null:
			a.rotation.x = -0.25


func _gait(amount: float) -> void:
	var s := sin(_anim)
	var ll := _nodes.get("LegL") as Node3D
	var lr := _nodes.get("LegR") as Node3D
	if ll != null:
		ll.rotation.x = s * amount
		lr.rotation.x = -s * amount
		(_nodes["ShinL"] as Node3D).rotation.x = maxf(0.0, -s) * amount * 1.3
		(_nodes["ShinR"] as Node3D).rotation.x = maxf(0.0, s) * amount * 1.3
	var hips := _nodes.get("Hips") as Node3D
	if hips != null:
		hips.position.y = hips.position.y * 0.0 + (0.88 if kind == "grunt" else 0.92 if kind == "gunner" else 0.98) \
			+ absf(s) * 0.03


# --------------------------------------------------------------- gunner
func _ai_gunner(dt: float) -> void:
	var to := _to_player()
	var dist := to.length()
	_face(to, dt, 12.0)
	_atk_cd -= dt
	_strafe_t -= dt
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.5, 3.0)
		_strafe = -_strafe
	if _state == "windup":
		_state_t -= dt
		var pulse := 0.5 + 0.5 * sin(_state_t * 40.0)
		_set_flash(Color(1, 1, 0.3), 0.6 * pulse)
		if _state_t <= 0.0:
			_set_flash(Color.WHITE, 0.0)
			_state = "move"
			_atk_cd = maxf(0.9, 2.0 - 0.03 * float(run.wave))
			_fire_bolt()
		_gait(0.0)
		return
	var dir := Vector3.ZERO
	if dist > 13.0:
		dir = to
	elif dist < 7.0:
		dir = -to
	dir = (dir.normalized() + to.normalized().rotated(Vector3.UP, PI * 0.5) * _strafe * 0.7)
	_walk(dir, speed, dt)
	_anim += dt * speed * 2.4
	_gait(0.55)
	var al := _nodes.get("ArmL") as Node3D
	if al != null:
		al.rotation.x = sin(_anim) * 0.4
	if _atk_cd <= 0.0 and dist < 26.0 and world.line_clear(global_position + Vector3(0, 1.4, 0), player.center()):
		_state = "windup"
		_state_t = 0.45


func _set_flash(col: Color, amt: float) -> void:
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("flash_color", col)
		(m as ShaderMaterial).set_shader_parameter("flash", amt)


func _muzzle_pos() -> Vector3:
	var mz := _nodes.get("Muzzle") as Node3D
	if mz != null:
		return mz.global_position
	return global_position + Vector3(0, 1.3, 0) + (-global_transform.basis.z * -0.6)


func _fire_bolt() -> void:
	var from := _muzzle_pos()
	var target := player.center() + Vector3(player.vel.x, 0, player.vel.z) * 0.18
	var d := (target - from).normalized()
	run.spawn_bolt(from, d * 15.0, 11.0 * dmg_mul, Color(0.8, 0.5, 1.0))
	Sfx.play("enemy_shot", -8.0)


# ---------------------------------------------------------------- brute
func _ai_brute(dt: float) -> void:
	var to := _to_player()
	var dist := to.length()
	_atk_cd -= dt
	match _state:
		"charge_wind":
			_state_t -= dt
			_face(to, dt, 6.0)
			_set_flash(Color(1, 0.2, 0.1), 0.45 + 0.4 * sin(_state_t * 30.0))
			_arms(-2.2, dt)
			if _state_t <= 0.0:
				_state = "charging"
				_state_t = 0.75
				_charge_dir = to.normalized()
				_set_flash(Color.WHITE, 0.0)
				Sfx.play("boss_roar", -10.0, 1.6)
			return
		"charging":
			_state_t -= dt
			_walk(_charge_dir, 13.0, dt)
			rotation.y = atan2(_charge_dir.x, _charge_dir.z)
			_anim += dt * 16.0
			_gait(0.9)
			_arms(-1.0, dt)
			if dist < radius + 0.7:
				_hurt_player(28.0)
				player.vel += _charge_dir * 9.0 + Vector3(0, 3.0, 0)
				_state = "recover"
				_state_t = 0.9
			elif _state_t <= 0.0:
				_state = "recover"
				_state_t = 0.9
			return
		"recover":
			_state_t -= dt
			_atk_cd = 2.5
			_gait(0.1)
			_arms(-0.3, dt)
			if _state_t <= 0.0:
				_state = "move"
			return
		"slam":
			_state_t -= dt
			_arms(-2.6, dt)
			if _state_t <= 0.0:
				_state = "move"
				_atk_cd = 1.3
				fx.burst(global_position + _charge_dir * 1.4, "dust", Color(0.8, 0.75, 0.85), 6, 1.0)
				fx.flat_ring(global_position + _charge_dir * 1.4, Color(1, 0.6, 0.3), 5.0, 0.3)
				Sfx.play("hit_big", -5.0, 0.7)
				if _to_player().length() < 3.2:
					_hurt_player(22.0)
				_arms(-0.2, dt, true)
			return
	_face(to, dt, 6.0)
	if dist < 3.0 and _atk_cd <= 0.0:
		_state = "slam"
		_state_t = 0.45
		_charge_dir = to.normalized()
		return
	if dist < 14.0 and dist > 5.0 and _atk_cd <= 0.0:
		_state = "charge_wind"
		_state_t = 0.8
		return
	if dist > 2.0:
		_walk(to, speed, dt)
		_anim += dt * speed * 1.8
	_gait(0.6)
	_arms(-0.15 + sin(_anim * 0.5) * 0.1, dt)


# ---------------------------------------------------------------- drone
func _ai_drone(dt: float) -> void:
	var to := _to_player()
	var dist := to.length()
	_face(to, dt, 8.0)
	_idle_anim(dt)
	_hover_ph += dt * 2.0
	_atk_cd -= dt
	var want_y := _hover_y + sin(_hover_ph) * 0.35
	var p := global_position
	p.y = lerpf(p.y, want_y, clampf(dt * 2.5, 0.0, 1.0))
	var dir := Vector3.ZERO
	if dist > 11.0:
		dir = to
	elif dist < 6.0:
		dir = -to
	dir = dir.normalized() + to.normalized().rotated(Vector3.UP, PI * 0.5) * _strafe * 0.9
	global_position = p
	_walk(dir, speed, dt)
	global_position.y = p.y
	_strafe_t -= dt
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.2, 2.5)
		_strafe = -_strafe
	if _state == "windup":
		_state_t -= dt
		_set_flash(Color(1, 0.3, 0.2), 0.4 + 0.4 * sin(_state_t * 50.0))
		if _state_t <= 0.0:
			_set_flash(Color.WHITE, 0.0)
			_state = "move"
			_atk_cd = randf_range(2.0, 3.0)
			for i in 3:
				var tgt := player.center() + Vector3(randf_range(-0.6, 0.6), randf_range(-0.4, 0.4), randf_range(-0.6, 0.6))
				var from := _muzzle_pos()
				run.spawn_bolt(from, (tgt - from).normalized() * 19.0, 6.0 * dmg_mul, Color(0.4, 1.0, 0.6), 0.2)
			Sfx.play("enemy_shot", -9.0, 1.6)
	elif _atk_cd <= 0.0 and dist < 22.0 and world.line_clear(global_position, player.center()):
		_state = "windup"
		_state_t = 0.4


# ---------------------------------------------------------------- titan
func _ai_titan(dt: float) -> void:
	var to := _to_player()
	var dist := to.length()
	_atk_cd -= dt
	# expanding floor shockwave from a slam
	if _wave_r >= 0.0:
		_wave_r += dt * 24.0
		if not _wave_hit and player.on_ground and absf(dist - _wave_r) < 1.4 and player.global_position.y < 0.9:
			_wave_hit = true
			_hurt_player(26.0)
			player.vel += to.normalized() * 8.0 + Vector3(0, 4.0, 0)
		if _wave_r > 34.0:
			_wave_r = -1.0
	match _state:
		"volley":
			_state_t -= dt
			_face(to, dt, 5.0)
			_set_flash(Color(1, 0.3, 0.3), 0.3 + 0.3 * sin(_state_t * 30.0))
			_arms(-0.6 - sin(_state_t * 6.0) * 0.3, dt)
			if _state_t <= 0.0:
				_set_flash(Color.WHITE, 0.0)
				Sfx.play("boss_roar", -4.0, 0.9)
				var n := 16
				var off := randf() * TAU
				for i in n:
					var a := off + TAU * i / n
					var dirv := Vector3(cos(a), 0.0, sin(a))
					run.spawn_bolt(global_position + Vector3(0, 1.8, 0) + dirv * 1.4, dirv * 11.0, 12.0 * dmg_mul, Color(1.0, 0.35, 0.3), 0.3)
				_state = "recover"
				_state_t = 0.8
			return
		"slam_wind":
			_state_t -= dt
			_face(to, dt, 3.0)
			_set_flash(Color(1, 0.6, 0.1), 0.3 + 0.3 * sin(_state_t * 30.0))
			_arms(-2.8, dt)
			model.position.y = 0.0
			if _state_t <= 0.0:
				_set_flash(Color.WHITE, 0.0)
				_arms(-0.2, dt, true)
				Sfx.play("explosion", -2.0, 0.7)
				fx.flat_ring(global_position, Color(1.0, 0.45, 0.2), 66.0, 1.4)
				fx.burst(global_position + Vector3(0, 0.3, 0), "dust", Color(0.9, 0.8, 0.9), 14, 1.5)
				player.shake = 1.0
				_wave_r = 0.5
				_wave_hit = false
				_state = "recover"
				_state_t = 1.0
			return
		"summon":
			_state_t -= dt
			_arms(-2.0, dt)
			if _state_t <= 0.0:
				for i in 3:
					var a := randf() * TAU
					run.spawn_enemy("grunt", global_position + Vector3(cos(a), 0, sin(a)) * 3.0)
				fx.ring(global_position + Vector3(0, 1.5, 0), Color(1, 0.3, 0.3), 6.0, 0.4)
				_state = "recover"
				_state_t = 0.7
			return
		"recover":
			_state_t -= dt
			_arms(-0.3, dt)
			if _state_t <= 0.0:
				_state = "move"
				_atk_cd = randf_range(1.2, 2.2)
			return
	_face(to, dt, 4.0)
	if _atk_cd <= 0.0:
		_phase += 1
		match _phase % 3:
			0:
				_state = "volley"
				_state_t = 1.0
			1:
				_state = "slam_wind"
				_state_t = 1.15
			2:
				_state = "summon" if run.enemy_list.size() < 12 else "volley"
				_state_t = 1.0
		Sfx.play("boss_roar", -6.0, 1.0)
		return
	if dist > 6.0:
		_walk(to, speed, dt)
		_anim += dt * speed * 1.6
	_gait(0.5)
	_arms(-0.2 + sin(_anim * 0.5) * 0.12, dt)
	if dist < radius + 1.4:
		_hurt_player(0.0 if _atk_cd > 0.0 else 18.0)
