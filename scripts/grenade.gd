class_name Grenade
extends Node3D
## Thrown with Q. Bounces, then detonates (or pops on contact with an enemy).

const MODEL := preload("res://assets/models/grenade.glb")

var vel := Vector3.ZERO
var dmg := 150.0
var fuse := 1.5
var world: World
var player: Player
var _model: Node3D
var _spin := Vector3(randf_range(-8, 8), randf_range(-8, 8), 0)


func _ready() -> void:
	_model = MODEL.instantiate()
	PSXMat.apply(_model)
	_model.scale = Vector3.ONE * 1.5
	add_child(_model)


func _process(dt: float) -> void:
	fuse -= dt
	vel.y -= 22.0 * dt
	var step := vel * dt
	var l := step.length()
	if l > 0.0001:
		var t := world.raycast(global_position, vel.normalized(), l + 0.12)
		if t <= l + 0.12:
			var n := world.last_normal
			if n.length() < 0.5:
				n = Vector3.UP if vel.y < 0.0 else -vel.normalized()
			vel = vel.bounce(n) * 0.5
			if n.y > 0.5:
				vel.x *= 0.7
				vel.z *= 0.7
			global_position += n * 0.02
			step = Vector3.ZERO
	global_position += step
	var gy := world.ground_at(global_position.x, global_position.z, global_position.y, 0.1)
	if global_position.y < gy + 0.12:
		global_position.y = gy + 0.12
		if vel.y < 0.0:
			vel.y *= -0.4
			vel.x *= 0.75
			vel.z *= 0.75
	_model.rotation += _spin * dt
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and e.alive and e.center().distance_to(global_position) < e.radius + 0.5:
			fuse = 0.0
	if fuse <= 0.0:
		player.explode(global_position, 6.5, dmg)
		queue_free()
