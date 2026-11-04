class_name Pickup
extends Node3D
## Medkits and power-up orbs dropped by enemies. They drift toward you when close.

const MEDKIT := preload("res://assets/models/medkit.glb")
const ORB := preload("res://assets/models/orb.glb")
const KINDS := {
	"health": {"label": "+HEALTH", "color": Color(0.4, 1.0, 0.5)},
	"rampage": {"label": "RAMPAGE!", "color": Color(1.0, 0.25, 0.2), "sub": "x2 FIRE RATE, +50% DAMAGE"},
	"slowmo": {"label": "BULLET TIME!", "color": Color(0.3, 0.9, 1.0), "sub": "THE WORLD SLOWS DOWN"},
	"midas": {"label": "MIDAS!", "color": Color(1.0, 0.85, 0.2), "sub": "x3 SCORE"},
}

var kind := "health"
var player: Player
var run: Run
var life := 24.0
var _model: Node3D
var _t := randf() * TAU
var _base_y := 0.0


func _ready() -> void:
	if kind == "health":
		_model = MEDKIT.instantiate()
		PSXMat.apply(_model)
		_model.scale = Vector3.ONE * 1.4
	else:
		_model = ORB.instantiate()
		var c: Color = KINDS[kind]["color"]
		var def: Dictionary = PSXMat.DEFS["Orb"].duplicate()
		def["color"] = c
		def["emit"] = c * 0.35
		PSXMat.apply(_model, {"Orb": def})
		_model.scale = Vector3.ONE * 1.3
	add_child(_model)
	var glow := FX.make_glow(1.8, Color(KINDS[kind]["color"].r, KINDS[kind]["color"].g, KINDS[kind]["color"].b, 0.6))
	glow.position.y = 0.5
	add_child(glow)
	_base_y = global_position.y


func _process(dt: float) -> void:
	life -= dt
	if life <= 0.0:
		queue_free()
		return
	_t += dt * 3.0
	_model.rotation.y += dt * 2.5
	_model.position.y = (0.55 if kind != "health" else 0.15) + sin(_t) * 0.12
	_model.visible = life > 5.0 or int(life * 6.0) % 2 == 0
	if player == null or not player.alive:
		return
	var to := player.center() - global_position
	var d := to.length()
	var mag := float(player.inv.stats["magnet"])
	if d < mag:
		global_position += to.normalized() * (6.0 + (mag - d) * 3.0) * dt
	if d < 1.25:
		if kind == "health":
			if player.hp >= player.max_hp - 0.5:
				return    # keep it for later
			player.heal(30.0)
			Sfx.play("heal")
			run.popup_world(global_position + Vector3(0, 1, 0), "+HP", Color(0.4, 1, 0.5))
		else:
			player.give_powerup(kind)
			run.announce(KINDS[kind]["label"], KINDS[kind]["color"], 1.1, String(KINDS[kind]["sub"]))
		queue_free()
