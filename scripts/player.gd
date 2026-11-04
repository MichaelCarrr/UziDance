class_name Player
extends Node3D
## First-person controller + dual Uzis. Everything (movement, hitscan, grenades) is plain maths
## against World / Enemy so it behaves identically in the browser.

signal hit_marker(killed: bool, head: bool)
signal damage_number(point: Vector3, amount: float, head: bool, crit: bool)
signal hurt_signal(amount: float)
signal died
signal revived
signal dashed

const EYE := 1.6
const RADIUS := 0.4
const GRAVITY := 25.0
const JUMP_V := 8.2
const BASE_SPEED := 7.2
const BASE_DMG := 13.0
const BASE_RATE := 10.0           ## total shots per second, alternating hands

var run: Run
var world: World
var fx: FX
var vm: ViewModel
var inv: Inventory
var cam: Camera3D

var yaw := 0.0
var pitch := 0.0
var vel := Vector3.ZERO
var on_ground := true
var hp := 100.0
var max_hp := 100.0
var alive := true
var active := false               ## false while menus / card draft / game over are up
var air_jumps_used := 0
var coyote := 0.0
var jump_buf := 0.0
var dash_t := 0.0
var dash_dir := Vector3.ZERO
var dash_charges := 2.0
var iframes := 0.0
var fire_cd := 0.0
var hand := 0
var bloom := 0.0
var shot_count := 0
var kill_count := 0
var grenade_cd := 0.0
var grenade_cd_max := 7.0
var bloodlust_t := 0.0
var rampage_t := 0.0
var midas_t := 0.0
var slowmo_t := 0.0
var shake := 0.0
var kick := 0.0
var focus := 0.0
var fov_now := 74.0
var _look := Vector2.ZERO
var _look_vis := Vector2.ZERO
var _bob := 0.0
var _heart_t := 0.0
var _land_dip := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 220.0
	cam.current = true
	add_child(cam)
	cam.position = Vector3(0, EYE, 0)


func setup(p_run: Run, p_world: World, p_fx: FX, p_vm: ViewModel, p_inv: Inventory) -> void:
	run = p_run
	world = p_world
	fx = p_fx
	vm = p_vm
	inv = p_inv
	fx.camera = cam
	reset()


func reset() -> void:
	var st: Dictionary = inv.stats
	max_hp = float(st["max_hp"])
	hp = max_hp
	alive = true
	vel = Vector3.ZERO
	pitch = 0.0
	yaw = 0.0
	global_position = world.player_start
	dash_charges = float(st["dash_charges"])
	grenade_cd = 0.0
	iframes = 1.0
	rampage_t = 0.0
	midas_t = 0.0
	slowmo_t = 0.0
	bloodlust_t = 0.0
	kick = 0.0
	on_ground = true
	vm.raise()


func stats_changed(heal_new_hp: bool = false) -> void:
	var st: Dictionary = inv.stats
	var old_max := max_hp
	max_hp = float(st["max_hp"])
	if max_hp > old_max and heal_new_hp:
		hp += (max_hp - old_max)
	hp = minf(hp, max_hp)
	grenade_cd_max = 7.0 * float(st["gren_cd"])


# ---------------------------------------------------------------- input
func mouse_look(rel: Vector2) -> void:
	var s := 0.0022 * float(Game.settings["sens"]) * (0.62 if focus > 0.5 else 1.0)
	add_look(-rel.x * s, -rel.y * s)


func add_look(dyaw: float, dpitch: float) -> void:
	yaw += dyaw
	pitch = clampf(pitch + dpitch, -1.5, 1.5)
	_look += Vector2(dyaw, dpitch)


func eye() -> Vector3:
	return cam.global_position


func aim_dir() -> Vector3:
	return -cam.global_transform.basis.z


func center() -> Vector3:
	return global_position + Vector3(0, 1.0, 0)


# --------------------------------------------------------------- per frame
func _process(dt: float) -> void:
	if run == null:
		return
	var dtp := dt / maxf(Engine.time_scale, 0.1)       # the player ignores bullet-time
	var st: Dictionary = inv.stats
	_update_timers(dtp)
	if alive and active:
		_look_gamepad(dtp)
		_move(dtp, st)
		_shoot_logic(dtp, st)
		if Input.is_action_just_pressed("grenade") and grenade_cd <= 0.0:
			_throw_grenade(st)
	_camera(dtp)
	var speed01 := clampf(Vector2(vel.x, vel.z).length() / (BASE_SPEED * 1.1), 0.0, 1.0) if on_ground else 0.15
	_look_vis = _look_vis.lerp(_look / maxf(dtp, 0.001) * 0.012, clampf(dtp * 12.0, 0.0, 1.0))
	_look = Vector2.ZERO
	vm.update(dtp, speed01, on_ground, vel.y, _look_vis, dash_t > 0.0, focus)


func _update_timers(dt: float) -> void:
	iframes = maxf(0.0, iframes - dt)
	coyote = maxf(0.0, coyote - dt)
	jump_buf = maxf(0.0, jump_buf - dt)
	fire_cd = maxf(-0.1, fire_cd - dt)
	grenade_cd = maxf(0.0, grenade_cd - dt)
	bloodlust_t = maxf(0.0, bloodlust_t - dt)
	rampage_t = maxf(0.0, rampage_t - dt)
	midas_t = maxf(0.0, midas_t - dt)
	bloom = maxf(0.0, bloom - dt * 1.8)
	shake = maxf(0.0, shake - dt * 3.0)
	kick = move_toward(kick, 0.0, dt * 0.5)
	_land_dip = move_toward(_land_dip, 0.0, dt * 1.2)
	if slowmo_t > 0.0:
		slowmo_t -= dt
		if slowmo_t <= 0.0:
			Engine.time_scale = 1.0
	var st: Dictionary = inv.stats
	var maxc: float = float(st["dash_charges"])
	if dash_charges < maxc:
		dash_charges = minf(maxc, dash_charges + dt / (2.4 * float(st["dash_cd"])))
	if alive and hp < max_hp * 0.3:
		_heart_t -= dt
		if _heart_t <= 0.0:
			_heart_t = 0.8
			Sfx.play("heartbeat", -4.0)


func _look_gamepad(dt: float) -> void:
	var lx := Input.get_axis("look_left", "look_right")
	var ly := Input.get_axis("look_up", "look_down")
	if lx != 0.0 or ly != 0.0:
		var s := 2.6 * float(Game.settings["sens"]) * (0.62 if focus > 0.5 else 1.0)
		add_look(-lx * s * dt, -ly * s * 0.7 * dt)


func _move(dt: float, st: Dictionary) -> void:
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3(inp.x, 0, inp.y).rotated(Vector3.UP, yaw)
	var focusing := Input.is_action_pressed("focus")
	focus = move_toward(focus, 1.0 if focusing else 0.0, dt * 8.0)
	var boost := 1.0 + (float(st["bloodlust"]) if bloodlust_t > 0.0 else 0.0)
	var speed := BASE_SPEED * float(st["speed"]) * boost * lerpf(1.0, 0.62, focus)
	# jump input
	if Input.is_action_just_pressed("jump"):
		jump_buf = 0.12
	if jump_buf > 0.0:
		if on_ground or coyote > 0.0:
			_jump(1.0)
		elif air_jumps_used < int(st["air_jumps"]):
			air_jumps_used += 1
			_jump(0.92)
			fx.burst(global_position + Vector3(0, 0.1, 0), "dust", Color(1, 1, 1, 0.7), 5, 0.6)
	# dash
	if Input.is_action_just_pressed("dash") and dash_charges >= 1.0 and dash_t <= 0.0:
		dash_charges -= 1.0
		dash_t = 0.17
		dash_dir = dir if dir.length() > 0.1 else -Vector3(sin(yaw), 0, cos(yaw))
		dash_dir = dash_dir.normalized()
		iframes = maxf(iframes, 0.28)
		Sfx.play("dash", -2.0)
		dashed.emit()
		if float(st["slow_dash"]) > 0.0:
			slowmo_t = float(st["slow_dash"])
			Engine.time_scale = 0.35
	if dash_t > 0.0:
		dash_t -= dt
		vel.x = dash_dir.x * 19.0
		vel.z = dash_dir.z * 19.0
		vel.y = maxf(vel.y, 0.0) * 0.9 if not on_ground else vel.y
	else:
		var accel := 75.0 if on_ground else 24.0
		vel.x = move_toward(vel.x, dir.x * speed, accel * dt)
		vel.z = move_toward(vel.z, dir.z * speed, accel * dt)
	if not on_ground:
		vel.y -= GRAVITY * dt * (0.3 if dash_t > 0.0 else 1.0)
	var was_ground := on_ground
	var pos := global_position + vel * dt
	pos = world.push_out(pos, RADIUS)
	# step up / land / fall
	var g := world.ground_at(pos.x, pos.z, pos.y, RADIUS)
	if vel.y <= 0.0 and pos.y <= g + 0.05:
		if not on_ground and vel.y < -7.0:
			Sfx.play("land", -3.0)
			_land_dip = clampf(-vel.y * 0.012, 0.0, 0.14)
			fx.burst(pos + Vector3(0, 0.1, 0), "dust", Color(1, 1, 1, 0.6), 5, 0.7)
		pos.y = g
		vel.y = 0.0
		on_ground = true
		air_jumps_used = 0
	elif on_ground and vel.y <= 0.0 and pos.y - g < 0.35:
		pos.y = g
	else:
		on_ground = false
	if was_ground and not on_ground and vel.y <= 0.0:
		coyote = 0.1
	# do not stand inside enemies
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or not e.alive or e.flying:
			continue
		var dx := pos.x - e.global_position.x
		var dz := pos.z - e.global_position.z
		var min_d := RADIUS + e.radius
		var d2 := dx * dx + dz * dz
		if d2 < min_d * min_d and d2 > 0.0001 and absf(pos.y - e.global_position.y) < e.height * 0.8:
			var d := sqrt(d2)
			pos.x += dx / d * (min_d - d)
			pos.z += dz / d * (min_d - d)
	pos = world.push_out(pos, RADIUS)
	global_position = pos
	_bob += dt * (Vector2(vel.x, vel.z).length() * 1.1) if on_ground else 0.0


func _jump(mult: float) -> void:
	vel.y = JUMP_V * mult
	on_ground = false
	coyote = 0.0
	jump_buf = 0.0
	Sfx.play("jump", -6.0, 1.0, 0.05)


func _camera(dt: float) -> void:
	rotation = Vector3(0, yaw, 0)
	var bob_y := sin(_bob) * 0.035 * clampf(Vector2(vel.x, vel.z).length() / BASE_SPEED, 0.0, 1.0) if on_ground else 0.0
	cam.position = Vector3(0, EYE + bob_y - _land_dip, 0)
	var sk := shake * (1.0 if bool(Game.settings["shake"]) else 0.0)
	cam.rotation = Vector3(pitch + kick + randf_range(-sk, sk) * 0.03, randf_range(-sk, sk) * 0.03,
		randf_range(-sk, sk) * 0.04 + sin(_bob * 0.5) * 0.004)
	var target_fov := float(Game.settings["fov"]) * lerpf(1.0, 0.8, focus) + (7.0 if dash_t > 0.0 else 0.0)
	fov_now = lerpf(fov_now, target_fov, clampf(dt * 12.0, 0.0, 1.0))
	cam.fov = fov_now
	vm.set_fov(fov_now)


# --------------------------------------------------------------- shooting
func _shoot_logic(dt: float, st: Dictionary) -> void:
	if Input.is_action_pressed("fire") and fire_cd <= 0.0:
		var rate := BASE_RATE * float(st["rate"])
		if rampage_t > 0.0:
			rate *= 2.0
		if bloodlust_t > 0.0:
			rate *= 1.0 + float(st["bloodlust"])
		fire_cd += 1.0 / rate
		_shoot(st)


func _damage_now(st: Dictionary) -> float:
	var d := BASE_DMG * float(st["dmg"])
	if rampage_t > 0.0:
		d *= 1.5
	if hp < max_hp * 0.35:
		d *= float(st["low_hp_dmg"])
	return d


func _shoot(st: Dictionary) -> void:
	hand = 1 - hand
	vm.fire(hand)
	Sfx.play("uzi%d" % (randi() % 3), -5.0, 1.0, 0.05)
	kick = minf(0.05, kick + 0.0045)
	shake = minf(0.35, shake + 0.045)
	shot_count += 1
	var bullets := 1 + int(st["pellets"])
	var base_spread := (0.9 + bloom * 3.2) * float(st["spread"]) * lerpf(1.0, 0.35, focus)
	bloom = minf(1.0, bloom + 0.07)
	var dmg := _damage_now(st) / (1.0 + 0.35 * (bullets - 1))
	var muzzle := cam.global_transform * vm.muzzle_local(hand)
	var origin := eye()
	var b := cam.global_transform.basis
	for i in bullets:
		var sp := base_spread + (0.0 if i == 0 else 1.2)
		var a := randf() * TAU
		var r := tan(deg_to_rad(sp)) * sqrt(randf())
		var dir := (-b.z + b.x * cos(a) * r + b.y * sin(a) * r).normalized()
		_bullet(origin, dir, muzzle, dmg, st)
	if int(st["tesla"]) > 0 and shot_count % 5 == 0:
		_tesla(st)


func _bullet(origin: Vector3, dir: Vector3, muzzle: Vector3, dmg: float, st: Dictionary) -> void:
	var wall_t := world.raycast(origin, dir, 90.0)
	var wall_n := world.last_normal
	var hits: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or not e.alive:
			continue
		var r := e.ray_hit(origin, dir, wall_t)
		if not r.is_empty():
			hits.append({"e": e, "t": float(r["t"]), "head": bool(r["head"])})
	hits.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["t"] < y["t"])
	var pierce_left := 1 + int(st["pierce"])
	var end_t := wall_t
	var hit_something := false
	var first_hit_point := Vector3.ZERO
	var first_enemy: Enemy = null
	for h in hits:
		if pierce_left <= 0:
			break
		var e: Enemy = h["e"]
		var t: float = h["t"]
		var p := origin + dir * t
		if not hit_something:
			first_hit_point = p
			first_enemy = e
		hit_something = true
		_hit_enemy(e, dmg, bool(h["head"]), p, dir, st)
		pierce_left -= 1
		if pierce_left <= 0:
			end_t = t
	var tr_col := Color(1.0, 0.85, 0.3) if bool(st["gold"]) else Color(1.0, 0.95, 0.75)
	var end_p := origin + dir * minf(end_t, 75.0)
	fx.tracer(muzzle, end_p, tr_col, 0.07 if bool(st["gold"]) else 0.055)
	if not hit_something and wall_t < 89.0:
		var np := origin + dir * wall_t + wall_n * 0.04
		fx.burst(np, "spark", Color(1.0, 0.85, 0.5), 3, 0.6, wall_n, 75.0)
		if randf() < 0.5:
			fx.burst(np, "dust", Color(0.8, 0.75, 0.85, 0.7), 1, 0.5, wall_n, 60.0)
		fx.impact(np, Color(1, 0.9, 0.6), 0.32)
	# explosive tips
	if hit_something and randf() < float(st["explosive"]):
		_explode_at(first_hit_point, 3.2, 40.0 * float(st["dmg"]), null)
	# ricochet chain
	if hit_something and int(st["ricochet"]) > 0 and first_enemy != null and first_enemy.alive:
		_ricochet(first_enemy, first_hit_point, dmg * 0.5, int(st["ricochet"]), [first_enemy], st)


func _hit_enemy(e: Enemy, dmg: float, head: bool, point: Vector3, dir: Vector3, st: Dictionary) -> void:
	var d := dmg
	var crit := randf() < float(st["crit"])
	if crit:
		d *= float(st["crit_mul"])
	if head:
		d *= float(st["head"])
	var burn := float(st["burn"])
	var killed := e.take_hit(d, head, point, dir, crit)
	if burn > 0.0 and e.alive:
		e.ignite(burn, 3.0)
	damage_number.emit(point, d, head, crit)
	hit_marker.emit(killed, head)
	if killed:
		Sfx.play("headshot" if head else "hit_tick", -3.0, 1.0, 0.03)
	else:
		Sfx.play("hit_tick", -9.0, 1.0 + (0.25 if head else 0.0), 0.05)


func pet_hit(e: Enemy, dmg: float) -> void:
	_hit_enemy(e, dmg, false, e.center(), Vector3.UP, inv.stats)


func _ricochet(from_e: Enemy, from_p: Vector3, dmg: float, bounces: int, visited: Array, st: Dictionary) -> void:
	var best: Enemy = null
	var best_d := 9.0
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or not e.alive or visited.has(e):
			continue
		var d := e.center().distance_to(from_p)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	visited.append(best)
	var tgt := best.center()
	fx.tracer(from_p, tgt, Color(0.6, 1.0, 0.6), 0.05)
	fx.burst(tgt, "spark", Color(0.6, 1, 0.6), 4, 0.6)
	_hit_enemy(best, dmg, false, tgt, (tgt - from_p).normalized(), st)
	if bounces > 1 and best.alive:
		_ricochet(best, tgt, dmg, bounces - 1, visited, st)


func _tesla(st: Dictionary) -> void:
	var targets: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and e.alive and e.center().distance_to(eye()) < 16.0:
			targets.append(e)
	targets.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.center().distance_squared_to(eye()) < b.center().distance_squared_to(eye()))
	var n_max := int(st["tesla"])
	var prev := cam.global_transform * vm.muzzle_local(hand)
	for i in mini(n_max, targets.size()):
		var e: Enemy = targets[i]
		fx.tracer(prev, e.center(), Color(0.5, 0.9, 1.0), 0.11)
		fx.burst(e.center(), "spark", Color(0.5, 0.9, 1.0), 6, 0.8)
		_hit_enemy(e, 28.0 * float(st["dmg"]), false, e.center(), Vector3.UP, st)
		prev = e.center()


func _explode_at(p: Vector3, radius: float, dmg: float, _src: Node) -> void:
	fx.explosion(p, radius * 0.9)
	Sfx.play("explosion", -8.0 if radius < 4.0 else -2.0, 1.3 if radius < 4.0 else 1.0)
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or not e.alive:
			continue
		var d := e.center().distance_to(p)
		if d < radius + e.radius:
			var fall := clampf(1.0 - d / (radius + e.radius), 0.35, 1.0)
			var killed := e.take_hit(dmg * fall, false, e.center(), (e.center() - p).normalized(), false)
			damage_number.emit(e.center(), dmg * fall, false, false)
			hit_marker.emit(killed, false)


func explode(p: Vector3, radius: float, dmg: float) -> void:
	_explode_at(p, radius, dmg, null)
	shake = minf(0.8, shake + 0.5)


func nova(st: Dictionary) -> void:
	var n := 20
	var o := eye()
	Sfx.play("transform", -4.0)
	fx.ring(global_position + Vector3(0, 1.0, 0), Color(1.0, 0.5, 0.9), 7.0, 0.4)
	for i in n:
		var a := TAU * i / n
		var d := Vector3(cos(a), 0.0, sin(a))
		_bullet(Vector3(o.x, 1.1, o.z), d, Vector3(o.x, 1.1, o.z) + d * 0.6, 30.0 * float(st["dmg"]), st)


func _throw_grenade(st: Dictionary) -> void:
	grenade_cd = grenade_cd_max
	Sfx.play("grenade_throw", -2.0)
	var g := Grenade.new()
	g.world = world
	g.player = self
	g.dmg = 150.0 * float(st["gren_dmg"])
	run.entities.add_child(g)
	g.global_position = eye() + aim_dir() * 0.6 + Vector3(0, -0.15, 0)
	g.vel = aim_dir() * 17.0 + Vector3(0, 4.0, 0) + Vector3(vel.x, 0, vel.z) * 0.5
	vm.fire(1)


# ------------------------------------------------------------ taking damage
func hurt(amount: float, from: Vector3 = Vector3.ZERO) -> void:
	if not alive or iframes > 0.0:
		return
	hp -= amount
	iframes = 0.4
	shake = minf(1.0, shake + 0.6)
	Sfx.play("damage", -3.0)
	hurt_signal.emit(amount)
	if from != Vector3.ZERO:
		var away := global_position - from
		away.y = 0.0
		if away.length() > 0.1:
			vel += away.normalized() * 4.0
	if hp <= 0.0:
		if int(inv.stats["revives"]) > 0:
			_revive()
		else:
			hp = 0.0
			alive = false
			Engine.time_scale = 1.0
			slowmo_t = 0.0
			died.emit()


func _revive() -> void:
	inv.counts["second_wind"] = inv.count("second_wind") - 1
	if inv.counts["second_wind"] <= 0:
		inv.counts.erase("second_wind")
		inv.order.erase("second_wind")
	inv.recompute()
	inv.changed.emit()
	max_hp = float(inv.stats["max_hp"])
	hp = max_hp * 0.5
	iframes = 2.5
	Sfx.play("extra_life")
	fx.ring(global_position + Vector3(0, 1, 0), Color(1, 1, 0.5), 9.0, 0.5)
	explode(global_position + Vector3(0, 0.5, 0), 9.0, 200.0)
	revived.emit()


func heal(n: float) -> void:
	var amt := n * float(inv.stats["heal_mul"])
	hp = minf(max_hp, hp + amt)


func give_powerup(kind: String) -> void:
	Sfx.play("powerup")
	match kind:
		"rampage":
			rampage_t = 9.0
		"slowmo":
			slowmo_t = 6.0
			Engine.time_scale = 0.4
		"midas":
			midas_t = 12.0
