class_name Hud
extends Control
## All in-game HUD, drawn in one _draw() pass: crosshair + hit markers, HP, score/combo, wave,
## dash pips, grenade, item row, power-up timers, boss bar, damage popups and banners.

const ICONS := preload("res://assets/textures/items.png")
const ICON_COLS := 8

var run: Run
var player: Player
var project: Callable          ## Vector3 -> Vector2 in HUD space (x < -900 when behind the camera)
var capture_needed := false

var _popups: Array = []        ## {text, pos, age, life, color, size, drift}
var _banners: Array = []       ## {text, sub, color, age, life, size}
var _hit_t := 0.0
var _hit_kill := false
var _hit_head := false
var _hurt_a := 0.0
var _hint := ""
var _hint_t := 0.0
var _score_shown := 0.0
var _score_pop := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Game.ui_theme


func bind(p_run: Run, p_player: Player) -> void:
	run = p_run
	player = p_player
	run.popup_requested.connect(_on_popup)
	run.announce_requested.connect(_on_announce)
	run.score_changed.connect(func() -> void: _score_pop = 1.0)
	player.hit_marker.connect(_on_hit_marker)
	player.hurt_signal.connect(func(a: float) -> void: _hurt_a = clampf(_hurt_a + 0.25 + a * 0.015, 0.0, 0.7))


func show_hint(text: String, secs: float) -> void:
	_hint = text
	_hint_t = secs


func _on_hit_marker(killed: bool, head: bool) -> void:
	_hit_t = 0.16 if not killed else 0.3
	_hit_kill = killed
	_hit_head = head


func _on_popup(world_pos: Vector3, text: String, color: Color, size: int) -> void:
	if _popups.size() > 40:
		_popups.pop_front()
	_popups.append({"text": text, "wp": world_pos + Vector3(randf_range(-0.25, 0.25), randf_range(0.0, 0.3), 0), "age": 0.0,
		"life": 0.8, "color": color, "size": size})


func _on_announce(text: String, color: Color, time: float, sub: String) -> void:
	_banners.append({"text": text, "sub": sub, "color": color, "age": 0.0, "life": time + 0.5})
	if _banners.size() > 3:
		_banners.pop_front()


func reset() -> void:
	_popups.clear()
	_banners.clear()
	_hurt_a = 0.0
	_score_shown = 0.0


func _process(dt: float) -> void:
	_hit_t = maxf(0.0, _hit_t - dt)
	_hurt_a = maxf(0.0, _hurt_a - dt * 0.7)
	_score_pop = maxf(0.0, _score_pop - dt * 4.0)
	_hint_t = maxf(0.0, _hint_t - dt)
	for p in _popups:
		p["age"] = float(p["age"]) + dt
	_popups = _popups.filter(func(p: Dictionary) -> bool: return float(p["age"]) < float(p["life"]))
	for b in _banners:
		b["age"] = float(b["age"]) + dt
	_banners = _banners.filter(func(b: Dictionary) -> bool: return float(b["age"]) < float(b["life"]))
	if run != null:
		_score_shown = move_toward(_score_shown, float(run.score), maxf(50.0, absf(run.score - _score_shown) * 6.0) * dt)
	queue_redraw()


# ------------------------------------------------------------------ drawing
func _txt(text: String, pos: Vector2, size: int, color: Color, align: int = 0) -> void:
	var w := Game.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == 1:
		x -= w * 0.5
	elif align == 2:
		x -= w
	draw_string(Game.font, Vector2(x, pos.y + size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw() -> void:
	if run == null or player == null:
		return
	var sz := size
	var cx := sz.x * 0.5
	var cy := sz.y * 0.5
	# damage vignette
	if _hurt_a > 0.01 or (player.alive and player.hp < player.max_hp * 0.3):
		var low := 0.0
		if player.alive and player.hp < player.max_hp * 0.3:
			low = 0.12 + 0.08 * sin(Time.get_ticks_msec() * 0.008)
		var a := maxf(_hurt_a, low)
		var th := 26.0
		var col := Color(0.9, 0.05, 0.05, a)
		draw_rect(Rect2(0, 0, sz.x, th), col)
		draw_rect(Rect2(0, sz.y - th, sz.x, th), col)
		draw_rect(Rect2(0, th, th, sz.y - th * 2), col)
		draw_rect(Rect2(sz.x - th, th, th, sz.y - th * 2), col)
	# power-up tint
	if player.rampage_t > 0.0:
		draw_rect(Rect2(0, 0, sz.x, sz.y), Color(1, 0.1, 0.05, 0.05))
	if player.midas_t > 0.0:
		draw_rect(Rect2(0, 0, sz.x, sz.y), Color(1, 0.8, 0.1, 0.045))
	if player.slowmo_t > 0.0:
		draw_rect(Rect2(0, 0, sz.x, sz.y), Color(0.2, 0.7, 1.0, 0.07))

	_draw_crosshair(cx, cy)
	_draw_world_popups()
	_draw_top(sz)
	_draw_bottom(sz)
	_draw_banners(sz)
	if capture_needed:
		var a2 := 1.0 if int(Time.get_ticks_msec() / 400) % 2 == 0 else 0.45
		_txt("CLICK TO LOCK MOUSE  -  ARROW KEYS ALSO LOOK", Vector2(cx, sz.y * 0.62), 10, Color(1, 0.9, 0.3, a2), 1)
	if _hint_t > 0.0:
		_txt(_hint, Vector2(cx, sz.y - 70), 10, Color(1, 1, 1, clampf(_hint_t, 0.0, 1.0)), 1)


func _draw_crosshair(cx: float, cy: float) -> void:
	if not player.alive:
		return
	var spread_px := 5.0 + player.bloom * 11.0 * (0.4 if player.focus > 0.5 else 1.0) * float(player.inv.stats["spread"])
	var col := Color(1, 1, 1, 0.9)
	var g := spread_px
	var l := 5.0
	draw_rect(Rect2(cx - g - l, cy - 1, l, 2), col)
	draw_rect(Rect2(cx + g, cy - 1, l, 2), col)
	draw_rect(Rect2(cx - 1, cy - g - l, 2, l), col)
	draw_rect(Rect2(cx - 1, cy + g, 2, l), col)
	draw_rect(Rect2(cx - 1, cy - 1, 2, 2), Color(1, 0.3, 0.3, 0.9))
	if _hit_t > 0.0:
		var k := _hit_t / (0.3 if _hit_kill else 0.16)
		var c := Color(1, 0.15, 0.1, k) if _hit_kill else (Color(1, 0.85, 0.2, k) if _hit_head else Color(1, 1, 1, k))
		var d := 8.0 + (1.0 - k) * 6.0
		var r := 5.0
		for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(Vector2(cx, cy) + s * d, Vector2(cx, cy) + s * (d + r), c, 2.0)


func _draw_world_popups() -> void:
	if not project.is_valid():
		return
	for p in _popups:
		var k: float = float(p["age"]) / float(p["life"])
		var pos: Vector2 = project.call(p["wp"])
		if pos.x < -900.0:
			continue
		pos.y -= k * 28.0
		var c: Color = p["color"]
		c.a = clampf(2.2 - k * 2.2, 0.0, 1.0)
		_txt(String(p["text"]), pos - Vector2(0, int(p["size"])), int(p["size"]), c, 1)


func _draw_top(sz: Vector2) -> void:
	var cx := sz.x * 0.5
	# wave + enemies
	var left := run.enemy_list.size() + run.to_spawn.size()
	_txt("WAVE %d" % maxi(run.wave, 1), Vector2(14, 10), 20, Color(1.0, 0.85, 0.25))
	if run.state == "fighting":
		_txt("%d ENEMIES LEFT" % left, Vector2(14, 34), 10, Color(0.85, 0.85, 0.95))
	else:
		_txt("GET READY", Vector2(14, 34), 10, Color(0.5, 1.0, 0.6))
	# score
	var pop := 1.0 + _score_pop * 0.25
	_txt(Game.fmt_int(int(_score_shown)), Vector2(cx, 8), int(20 * pop) if pop < 1.2 else 20, Color(1, 1, 1), 1)
	var mult := 1.0 + minf(run.combo, 40) * 0.05
	if player.midas_t > 0.0:
		mult *= 3.0
	if run.combo > 1:
		var ct := clampf(run.combo_t / 3.5, 0.0, 1.0)
		_txt("x%.2f  %d COMBO" % [mult, run.combo], Vector2(cx, 32), 10, Color(1.0, 0.6 + 0.3 * ct, 0.2), 1)
		draw_rect(Rect2(cx - 40, 46, 80 * ct, 3), Color(1.0, 0.6, 0.2))
	_txt("BEST %s" % Game.fmt_int(Game.high_score), Vector2(sz.x - 14, 10), 10, Color(0.7, 0.7, 0.9), 2)
	_txt("KILLS %d" % run.kills, Vector2(sz.x - 14, 24), 10, Color(0.7, 0.7, 0.9), 2)
	# boss bar
	if run.boss != null and is_instance_valid(run.boss) and run.boss.alive:
		var b := run.boss
		var w := minf(300.0, sz.x * 0.4)
		var x0 := cx - w * 0.5
		_txt("TITAN", Vector2(cx, 54), 10, Color(1, 0.4, 0.4), 1)
		draw_rect(Rect2(x0 - 2, 66, w + 4, 10), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(x0, 68, w * clampf(b.hp / b.max_hp, 0.0, 1.0), 6), Color(0.95, 0.15, 0.25))


func _draw_bottom(sz: Vector2) -> void:
	var inv := player.inv
	# HP bar
	var x := 14.0
	var y := sz.y - 34.0
	var w := 170.0
	draw_rect(Rect2(x - 2, y - 2, w + 4, 16), Color(0, 0, 0, 0.7))
	var f := clampf(player.hp / player.max_hp, 0.0, 1.0)
	var col := Color(0.35, 0.95, 0.45).lerp(Color(1.0, 0.2, 0.2), 1.0 - minf(1.0, f * 1.8))
	draw_rect(Rect2(x, y, w * f, 12), col)
	_txt("HP %d/%d" % [ceili(player.hp), int(player.max_hp)], Vector2(x + 4, y + 2), 10, Color(1, 1, 1))
	# dash + grenade
	var dx := x
	var dy := y - 16.0
	var txt := "DASH "
	var full := int(floor(player.dash_charges + 0.001))
	for i in int(inv.stats["dash_charges"]):
		txt += "@" if i < full else "."
	_txt(txt, Vector2(dx, dy), 10, Color(0.5, 0.85, 1.0) if full > 0 else Color(0.5, 0.5, 0.6))
	var gtxt := "Q GRENADE READY"
	var gcol := Color(0.6, 1.0, 0.5)
	if player.grenade_cd > 0.0:
		var k := 1.0 - player.grenade_cd / maxf(0.01, player.grenade_cd_max)
		var n := int(k * 8.0)
		gtxt = "Q GRENADE [" + "|".repeat(n) + ".".repeat(8 - n) + "]"
		gcol = Color(0.55, 0.55, 0.65)
	_txt(gtxt, Vector2(dx + 90, dy), 10, gcol)
	# power-up timers
	var py := y - 32.0
	if player.rampage_t > 0.0:
		_txt("RAMPAGE %.1f" % player.rampage_t, Vector2(dx, py), 10, Color(1, 0.3, 0.25))
		py -= 12.0
	if player.midas_t > 0.0:
		_txt("MIDAS x3 %.1f" % player.midas_t, Vector2(dx, py), 10, Color(1, 0.85, 0.25))
		py -= 12.0
	if player.slowmo_t > 0.0:
		_txt("BULLET TIME %.1f" % player.slowmo_t, Vector2(dx, py), 10, Color(0.4, 0.9, 1))
		py -= 12.0
	# item row (bottom right)
	var ix := sz.x - 14.0
	var iy := sz.y - 30.0
	var n_items := inv.order.size()
	var per_row := 12
	for i in n_items:
		var id: String = inv.order[i]
		var info: Dictionary = Items.DB[id]
		var row := i / per_row
		var col_i := i % per_row
		var pos := Vector2(ix - (col_i + 1) * 26.0, iy - row * 26.0)
		var rc: Color = Items.COLORS[info["rarity"]]
		draw_rect(Rect2(pos.x - 1, pos.y - 1, 24, 24), Color(rc.r, rc.g, rc.b, 0.9))
		draw_rect(Rect2(pos.x, pos.y, 22, 22), Color(0.06, 0.04, 0.1, 0.92))
		var ic: int = info["icon"]
		draw_texture_rect_region(ICONS, Rect2(pos.x + 3, pos.y + 3, 16, 16),
			Rect2((ic % ICON_COLS) * 8, (ic / ICON_COLS) * 8, 8, 8), rc)
		var c := inv.count(id)
		if c > 1:
			_txt("%d" % c, Vector2(pos.x + 21, pos.y + 14), 10, Color(1, 1, 1), 2)


func _draw_banners(sz: Vector2) -> void:
	var y := sz.y * 0.24
	for b in _banners:
		var age: float = b["age"]
		var life: float = b["life"]
		var a := clampf(minf(age * 8.0, (life - age) * 3.0), 0.0, 1.0)
		var pop := 1.0 + maxf(0.0, 0.5 - age * 4.0)
		var c: Color = b["color"]
		c.a = a
		var s := int(30 * pop)
		s = int(s / 10) * 10
		_txt(String(b["text"]), Vector2(sz.x * 0.5, y), maxi(20, s), c, 1)
		if String(b["sub"]) != "":
			_txt(String(b["sub"]), Vector2(sz.x * 0.5, y + 34), 10, Color(1, 1, 1, a), 1)
		y += 56.0
