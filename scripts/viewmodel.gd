class_name ViewModel
extends Node3D
## The two Uzis. Lives in its own transparent SubViewport (so the guns never clip into walls)
## that is composited over the 3D world before the PSX post pass.

const UZI_R := preload("res://assets/models/uzi_r.glb")
const UZI_L := preload("res://assets/models/uzi_l.glb")

const REST_R := Vector3(0.25, -0.23, -0.6)
const REST_L := Vector3(-0.25, -0.23, -0.6)

var cam: Camera3D
var holders: Array[Node3D] = []      ## [0] = left, [1] = right
var muzzles: Array[Node3D] = []
var flashes: Array[MeshInstance3D] = []
var _recoil := [0.0, 0.0]
var _flash_t := [0.0, 0.0]
var _bob_t := 0.0
var _sway := Vector2.ZERO
var _raise := 0.0                    ## 0 = lowered out of view, 1 = ready
var _dash := 0.0
var _focus := 0.0
var _vy := 0.0
var _kick := [0.0, 0.0]              ## visual muzzle-climb rotation per hand


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = float(Game.settings["fov"])
	cam.near = 0.02
	cam.far = 10.0
	cam.current = true
	add_child(cam)
	for i in 2:
		var holder := Node3D.new()
		add_child(holder)
		var model := (UZI_L if i == 0 else UZI_R).instantiate()
		PSXMat.apply(model)
		model.scale = Vector3.ONE * 0.82
		holder.add_child(model)
		holders.append(holder)
		var mz := model.find_child("Muzzle", true, false) as Node3D
		muzzles.append(mz)
		var flash := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.42, 0.42)
		var mat := PSXMat.sprite_material("flash", true)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		q.material = mat
		flash.mesh = q
		flash.visible = false
		flash.position = Vector3(0, 0.045, -0.6)
		holder.add_child(flash)
		flashes.append(flash)
	_apply_pose(0.0)


func set_fov(f: float) -> void:
	cam.fov = f


func fire(hand: int) -> void:
	_recoil[hand] = 1.0
	_kick[hand] = minf(1.0, _kick[hand] + 0.35)
	_flash_t[hand] = 0.055
	flashes[hand].visible = true
	flashes[hand].rotation.z = randf() * TAU
	var s := randf_range(0.8, 1.35)
	flashes[hand].scale = Vector3(s, s, s)


func muzzle_local(hand: int) -> Vector3:
	var mz := muzzles[hand]
	if mz == null:
		return holders[hand].position + Vector3(0, 0.045, -0.54)
	return cam.global_transform.affine_inverse() * mz.global_position


func raise() -> void:
	_raise = 0.0


func update(dt: float, speed01: float, grounded: bool, vy: float, look_delta: Vector2, dashing: bool, focus: float) -> void:
	_raise = minf(1.0, _raise + dt * 3.2)
	_bob_t += dt * (4.0 + 6.0 * speed01)
	_sway = _sway.lerp(look_delta * 0.55, clampf(dt * 10.0, 0.0, 1.0))
	_dash = move_toward(_dash, 1.0 if dashing else 0.0, dt * 9.0)
	_focus = move_toward(_focus, focus, dt * 8.0)
	_vy = lerpf(_vy, clampf(vy, -8.0, 8.0) if not grounded else 0.0, clampf(dt * 8.0, 0.0, 1.0))
	for i in 2:
		_recoil[i] = maxf(0.0, _recoil[i] - dt * 11.0)
		_kick[i] = maxf(0.0, _kick[i] - dt * 6.0)
		if _flash_t[i] > 0.0:
			_flash_t[i] -= dt
			if _flash_t[i] <= 0.0:
				flashes[i].visible = false
	_apply_pose(speed01)


func _apply_pose(speed01: float) -> void:
	var raise_off := (1.0 - ease(_raise, 0.4)) * 0.45
	for i in 2:
		var rest := REST_L if i == 0 else REST_R
		var side := -1.0 if i == 0 else 1.0
		var phase := _bob_t + (PI if i == 1 else 0.0)
		var p := rest
		# focus: guns tuck toward the centre line, level with the sights
		p.x = lerpf(p.x, side * 0.14, _focus)
		p.y = lerpf(p.y, -0.2, _focus)
		p.x += cos(phase * 0.5) * 0.012 * speed01 - _sway.x * 0.35
		p.y += sin(phase) * 0.012 * speed01 - raise_off - _sway.y * 0.35 - _vy * 0.006
		p.z += _recoil[i] * 0.075 + _dash * 0.12
		holders[i].position = p
		# inward yaw so both barrels converge on the crosshair, muzzle climb on recoil
		holders[i].rotation = Vector3(_kick[i] * 0.16 + _dash * 0.25 + _sway.y * 0.6 + _vy * 0.004,
			side * (0.045 + 0.02 * (1.0 - _focus)) + _sway.x * 0.5, -side * _dash * 0.2)
