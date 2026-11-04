class_name Pet
extends Node3D
## SENTRY DRONE item: orbits the player and zaps the nearest enemy.

const MODEL := preload("res://assets/models/orb.glb")

var player: Player
var fx: FX
var world: World
var index := 0
var _a := 0.0
var _cd := 0.5
var _model: Node3D


func _ready() -> void:
	_model = MODEL.instantiate()
	var def: Dictionary = PSXMat.DEFS["Orb"].duplicate()
	def["color"] = Color(0.4, 1.0, 1.0)
	def["emit"] = Color(0.0, 0.3, 0.35)
	PSXMat.apply(_model, {"Orb": def})
	_model.scale = Vector3.ONE * 0.55
	add_child(_model)
	_a = index * 2.1


func _process(dt: float) -> void:
	if player == null or not player.alive:
		return
	_a += dt * 1.8
	var target := player.global_position + Vector3(cos(_a) * 1.9, 2.1 + sin(_a * 2.0) * 0.2, sin(_a) * 1.9)
	global_position = global_position.lerp(target, clampf(dt * 8.0, 0.0, 1.0))
	_model.rotation.y += dt * 4.0
	_cd -= dt
	if _cd > 0.0:
		return
	var best: Enemy = null
	var best_d := 22.0
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or not e.alive:
			continue
		var d := e.center().distance_to(global_position)
		if d < best_d and world.line_clear(global_position, e.center()):
			best_d = d
			best = e
	if best != null:
		_cd = 0.42
		fx.tracer(global_position, best.center(), Color(0.4, 1.0, 1.0), 0.06)
		player.pet_hit(best, 11.0 * float(player.inv.stats["dmg"]))
