class_name Run
extends Node
## One endless run: the wave director, scoring/combo, loot drops and the roguelike card drafts.

signal popup_requested(world_pos: Vector3, text: String, color: Color, size: int)
signal announce_requested(text: String, color: Color, time: float, sub: String)
signal draft_requested(cards: Array, title: String)
signal game_over(summary: Dictionary)
signal score_changed

const CARD_DEAL := 3

var world: World
var fx: FX
var player: Player
var inv: Inventory
var entities: Node3D

var wave := 0
var score := 0
var combo := 0
var combo_t := 0.0
var best_combo := 0
var kills := 0
var headshots := 0
var run_time := 0.0
var state := "idle"           ## idle / draft / countdown / fighting / over
var enemy_list: Array = []
var to_spawn: Array = []
var boss: Enemy
var _spawn_cd := 0.0
var _count_t := 0.0
var _pets: Array = []
var _draft_boss := false
var autoplay := false
var debug_freeze := false
var _rng := RandomNumberGenerator.new()


func setup(p_world: World, p_fx: FX, p_player: Player, p_inv: Inventory, p_entities: Node3D) -> void:
	world = p_world
	fx = p_fx
	player = p_player
	inv = p_inv
	entities = p_entities
	_rng.randomize()
	player.died.connect(_on_player_died)
	player.damage_number.connect(_on_damage_number)
	inv.changed.connect(_on_inv_changed)


func start() -> void:
	clear_entities()
	inv = Inventory.new()
	inv.changed.connect(_on_inv_changed)
	player.inv = inv
	wave = 0
	score = 0
	combo = 0
	combo_t = 0.0
	best_combo = 0
	kills = 0
	headshots = 0
	run_time = 0.0
	player.kill_count = 0
	player.reset()
	player.active = false
	boss = null
	_sync_pets()
	score_changed.emit()
	# the run opens with a draft: pick your starting item
	_open_draft("CHOOSE YOUR STARTING ITEM", 0, false)


func clear_entities() -> void:
	for c in entities.get_children():
		c.queue_free()
	enemy_list.clear()
	to_spawn.clear()
	_pets.clear()
	boss = null
	Engine.time_scale = 1.0


# ----------------------------------------------------------------- the loop
func _process(dt: float) -> void:
	if state == "idle" or state == "over":
		return
	var rdt := dt / maxf(Engine.time_scale, 0.1)
	run_time += rdt
	if combo > 0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
			score_changed.emit()
	enemy_list = enemy_list.filter(func(e: Variant) -> bool: return is_instance_valid(e) and (e as Enemy).alive)
	match state:
		"countdown":
			_count_t -= rdt
			if _count_t <= 0.0:
				_begin_wave()
		"fighting":
			_spawn_logic(dt)
			if to_spawn.is_empty() and enemy_list.is_empty():
				_wave_clear()


func _begin_wave() -> void:
	wave += 1
	state = "fighting"
	player.active = true
	_build_queue()
	_spawn_cd = 0.3
	var is_boss := wave % 5 == 0
	if autoplay:
		print("[sim] wave %d  score %d  hp %d/%d  kills %d  items %s" % [wave, score, player.hp, player.max_hp, kills, inv.order])
	Sfx.play("boss_roar" if is_boss else "wave_start", -2.0)
	announce("WAVE %d" % wave if not is_boss else "WAVE %d  -  BOSS" % wave,
		Color(1.0, 0.3, 0.3) if is_boss else Color(1.0, 0.85, 0.25), 1.4)
	score_changed.emit()


func _build_queue() -> void:
	to_spawn.clear()
	var mul := float(inv.stats["enemy_mul"])
	var budget := int((6.0 + 2.7 * wave) * mul)
	if wave % 5 == 0:
		to_spawn.append("titan")
		budget = int(budget * 0.55)
	var pool: Array = [["grunt", 1.0, 5.0, 1]]
	if wave >= 2:
		pool.append(["gunner", 2.0, 2.6, 2])
	if wave >= 3:
		pool.append(["drone", 1.5, 2.2, 3])
	if wave >= 4:
		pool.append(["brute", 5.0, 1.3, 4])
	var guard := 0
	while budget > 0 and guard < 400:
		guard += 1
		var total := 0.0
		for p in pool:
			if p[1] <= budget:
				total += float(p[2])
		if total <= 0.0:
			break
		var r := _rng.randf() * total
		for p in pool:
			if p[1] > budget:
				continue
			r -= float(p[2])
			if r <= 0.0:
				to_spawn.append(p[0])
				budget -= int(ceilf(float(p[1])))
				break
	# the boss walks in first, then it is shuffled underlings
	var rest: Array = to_spawn.filter(func(k: Variant) -> bool: return k != "titan")
	rest.shuffle()
	to_spawn = (["titan"] if wave % 5 == 0 else []) + rest


func _spawn_logic(dt: float) -> void:
	if to_spawn.is_empty():
		return
	var cap := mini(22, 9 + wave / 2 + (4 if inv.count("devils_deal") > 0 else 0))
	_spawn_cd -= dt
	if _spawn_cd > 0.0 or enemy_list.size() >= cap:
		return
	var kind: String = to_spawn.pop_front()
	var sp := world.random_spawn(player.global_position, 14.0)
	spawn_enemy(kind, Vector3(sp.x + _rng.randf_range(-1.5, 1.5), 0.0, sp.y + _rng.randf_range(-1.5, 1.5)))
	_spawn_cd = maxf(0.25, 0.9 - 0.02 * wave)


func spawn_enemy(kind: String, pos: Vector3) -> Enemy:
	var e := Enemy.new()
	entities.add_child(e)
	e.global_position = Vector3(pos.x, 2.4 if kind == "drone" else 0.0, pos.z)
	e.setup(kind, self, wave)
	e.died.connect(_on_enemy_died)
	enemy_list.append(e)
	if e.boss:
		boss = e
		announce("TITAN", Color(1.0, 0.3, 0.3), 1.6, "DODGE THE SHOCKWAVE - JUMP!")
	fx.ring(e.global_position + Vector3(0, 0.6, 0), Color(1.0, 0.3, 0.7), 3.0, 0.4)
	return e


func spawn_bolt(from: Vector3, vel: Vector3, dmg: float, color: Color, size: float = 0.28) -> void:
	var b := EnemyBolt.new()
	b.world = world
	b.player = player
	b.fx = fx
	b.vel = vel
	b.dmg = dmg
	b.color = color
	b.size = size
	entities.add_child(b)
	b.global_position = from


func _wave_clear() -> void:
	state = "countdown"
	_count_t = 999.0           # the draft decides when the next wave starts
	var bonus := 250 * wave
	_add_score(bonus, false)
	Sfx.play("wave_clear")
	var is_boss := wave % 5 == 0
	announce("WAVE %d CLEAR" % wave, Color(0.4, 1.0, 0.6), 1.6, "+%s BONUS" % Game.fmt_int(bonus))
	player.heal(player.max_hp * (1.0 if is_boss else 0.25))
	if wave > Game.best_wave:
		Game.best_wave = wave
	# short beat, then the card draft
	await get_tree().create_timer(1.5, true, false, true).timeout
	if state != "countdown":
		return
	_open_draft("WAVE %d CLEAR  -  PICK AN ITEM" % wave, 1 if is_boss else 0, is_boss)


# --------------------------------------------------------------- the draft
func _open_draft(title: String, min_rarity: int, boss_reward: bool) -> void:
	state = "draft"
	player.active = false
	_draft_boss = boss_reward
	var n := int(inv.stats["cards"])
	var cards := Items.roll_cards(n, int(inv.stats["luck"]), min_rarity, _rng)
	Sfx.play("card_flip")
	draft_requested.emit(cards, title)


func pick_card(id: String) -> void:
	if state != "draft":
		return
	Sfx.play("item_get")
	inv.add(id)
	player.stats_changed(true)
	if id == "megaheart":
		player.hp = player.max_hp
	var info: Dictionary = Items.DB[id]
	announce(String(info["name"]), Items.COLORS[info["rarity"]], 1.0, String(info["desc"]))
	_count_t = 2.2
	state = "countdown"
	player.active = true
	score_changed.emit()


func _on_inv_changed() -> void:
	_sync_pets()


func _sync_pets() -> void:
	var want := int(inv.stats["pets"])
	_pets = _pets.filter(func(p: Variant) -> bool: return is_instance_valid(p))
	while _pets.size() < want:
		var p := Pet.new()
		p.player = player
		p.fx = fx
		p.world = world
		p.index = _pets.size()
		entities.add_child(p)
		p.global_position = player.global_position + Vector3(0, 2, 0)
		_pets.append(p)


# ------------------------------------------------------------ kills + score
func _on_enemy_died(e: Enemy) -> void:
	var st: Dictionary = inv.stats
	combo += 1
	combo_t = 3.5
	best_combo = maxi(best_combo, combo)
	kills += 1
	player.kill_count += 1
	Game.total_kills += 1
	var mult := 1.0 + minf(combo, 40) * 0.05
	if player.midas_t > 0.0:
		mult *= 3.0
	var pts := int(float(e.score) * mult * float(st["score"]))
	_add_score(pts, true)
	popup_world(e.center() + Vector3(0, 0.6, 0), "+%d" % pts, Color(1.0, 0.9, 0.3) if mult < 2.5 else Color(1.0, 0.5, 0.2))
	if combo > 0 and combo % 10 == 0:
		Sfx.play("combo")
		announce("%d KILL STREAK" % combo, Color(1.0, 0.6, 0.2), 0.7)
	# kill effects
	if float(st["lifesteal"]) > 0.0:
		player.heal(float(st["lifesteal"]))
	if float(st["bloodlust"]) > 0.0:
		player.bloodlust_t = 3.0
	var blossom := int(st["blossom"])
	if blossom > 0 and kills % blossom == 0:
		player.nova(st)
	# loot
	var drop_p := 0.07 + float(st["medkit"]) + (0.25 if e.kind == "brute" else 0.0)
	if player.hp < player.max_hp * 0.8:
		drop_p += 0.06
	if _rng.randf() < drop_p or e.boss:
		_drop("health", e.global_position)
	if _rng.randf() < 0.028 + (0.1 if e.kind == "brute" else 0.0) + (1.0 if e.boss else 0.0):
		_drop(["rampage", "slowmo", "midas"][_rng.randi() % 3], e.global_position + Vector3(0.6, 0, 0.3))
	if e.boss:
		boss = null
		Sfx.play("cheer")
		announce("TITAN DESTROYED", Color(1.0, 0.85, 0.3), 1.8, "BOSS REWARD AFTER THE WAVE")
	score_changed.emit()


func _drop(kind: String, pos: Vector3) -> void:
	var p := Pickup.new()
	p.kind = kind
	p.player = player
	p.run = self
	entities.add_child(p)
	p.global_position = Vector3(pos.x, 0.0, pos.z)


func _add_score(n: int, _from_kill: bool) -> void:
	score += n
	score_changed.emit()


func _on_damage_number(point: Vector3, amount: float, head: bool, crit: bool) -> void:
	if head:
		headshots += 1
	var col := Color(1, 1, 1)
	var size := 10
	if crit:
		col = Color(1.0, 0.85, 0.2)
		size = 20
	elif head:
		col = Color(1.0, 0.5, 0.3)
		size = 10
	popup_requested.emit(point, str(int(amount)), col, size)


func popup_world(pos: Vector3, text: String, color: Color = Color.WHITE, size: int = 10) -> void:
	popup_requested.emit(pos, text, color, size)


func announce(text: String, color: Color = Color.WHITE, time: float = 1.2, sub: String = "") -> void:
	announce_requested.emit(text, color, time, sub)


func _on_player_died() -> void:
	state = "over"
	player.active = false
	Engine.time_scale = 1.0
	var new_best := score > Game.high_score
	if new_best:
		Game.high_score = score
	Game.best_combo = maxi(Game.best_combo, best_combo)
	Game.best_wave = maxi(Game.best_wave, wave)
	Game.save()
	Sfx.play("ko")
	var items: Array = []
	for id in inv.order:
		items.append([id, inv.count(id)])
	var summary := {"score": score, "wave": wave, "kills": kills, "combo": best_combo, "time": run_time,
		"headshots": headshots, "new_best": new_best, "items": items}
	await get_tree().create_timer(1.6, true, false, true).timeout
	game_over.emit(summary)
