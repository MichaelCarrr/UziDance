class_name EnemyBolt
extends Node3D
## A glowing energy ball fired by SENTRIES, HOVERBOTS and the TITAN. Dodge it (or dash through it).

var vel := Vector3.ZERO
var dmg := 10.0
var life := 6.0
var world: World
var player: Player
var fx: FX
var color := Color(0.8, 0.5, 1.0)
var size := 0.28
var _spin := 0.0


func _ready() -> void:
	var glow := FX.make_glow(size * 3.2, Color(color.r, color.g, color.b, 0.8))
	add_child(glow)
	var core := FX.make_glow(size * 1.3, Color(1, 1, 1, 1))
	add_child(core)


func _process(dt: float) -> void:
	life -= dt
	if life <= 0.0:
		queue_free()
		return
	var step := vel * dt
	var l := step.length()
	if l > 0.0001:
		var t := world.raycast(global_position, vel.normalized(), l + 0.1)
		if t <= l + 0.1:
			fx.burst(global_position, "spark", color, 4, 0.5)
			queue_free()
			return
	global_position += step
	if player != null and player.alive:
		var pc := player.global_position
		var dx := global_position.x - pc.x
		var dz := global_position.z - pc.z
		if dx * dx + dz * dz < 0.42 * 0.42 + size * size and global_position.y > pc.y - 0.1 and global_position.y < pc.y + 1.95:
			player.hurt(dmg, global_position - vel.normalized())
			fx.burst(global_position, "spark", color, 6, 0.8)
			queue_free()
