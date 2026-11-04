class_name Menus
extends Control
## Title / how to play / options / pause / game-over screens. Emits `chosen(id)`.

signal chosen(id: String)
signal settings_changed

var _box: VBoxContainer
var _root: Control
var _back_id := ""
var results_open := false
var _blink: Label


func _ready() -> void:
	theme = Game.ui_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _clear() -> void:
	results_open = false
	_back_id = ""
	_blink = null
	if _root != null:
		_root.queue_free()
		_root = null


func hide_all() -> void:
	_clear()


func _frame(dim: float) -> VBoxContainer:
	_clear()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	if dim > 0.0:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.0, 0.06, dim)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_box)
	return _box


func _title_label(text: String, size: int, color: Color, shadow: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Game.label(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if shadow.a > 0.0:
		l.add_theme_color_override("font_shadow_color", shadow)
		l.add_theme_constant_override("shadow_offset_x", maxi(1, size / 10))
		l.add_theme_constant_override("shadow_offset_y", maxi(1, size / 10))
	_box.add_child(l)
	return l


func _spacer(h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	_box.add_child(c)


func _button(text: String, id: String, size: int = 20) -> Button:
	var b := Button.new()
	b.text = "  " + text + "  "
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_entered.connect(func() -> void:
		b.text = "> " + text + " <"
		Sfx.play("ui_move", -6.0))
	b.focus_exited.connect(func() -> void: b.text = "  " + text + "  ")
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	b.pressed.connect(func() -> void:
		Sfx.play("ui_select", -3.0)
		chosen.emit(id))
	_box.add_child(b)
	return b


func _focus_first() -> void:
	for c in _box.get_children():
		if c is Button:
			(c as Button).call_deferred("grab_focus")
			return


func _unhandled_input(event: InputEvent) -> void:
	if _back_id != "" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back", -3.0)
		chosen.emit(_back_id)


func _process(_dt: float) -> void:
	if _blink != null:
		_blink.modulate.a = 1.0 if int(Time.get_ticks_msec() / 500) % 2 == 0 else 0.25


# ------------------------------------------------------------------ screens
func show_title() -> void:
	_frame(0.0)
	_title_label("UZI RUSH", 60, Color(1, 0.85, 0.25), Color(0.65, 0.1, 0.4))
	_title_label("ENDLESS MODE", 20, Color(0.4, 0.95, 1.0), Color(0.0, 0.1, 0.25))
	_title_label("- DUAL UZIS - ROGUELIKE ITEMS - PSX -", 10, Color(1, 0.9, 0.95))
	_spacer(22)
	_button("PLAY", "play")
	_button("HOW TO PLAY", "how")
	_button("OPTIONS", "options")
	_spacer(14)
	if Game.high_score > 0:
		_title_label("BEST  %s    WAVE %d    COMBO %d" % [Game.fmt_int(Game.high_score), Game.best_wave, Game.best_combo],
			10, Color(0.8, 0.8, 1.0))
	_blink = _title_label("PRESS ENTER OR CLICK", 10, Color(1, 1, 1))
	_focus_first()


func show_how() -> void:
	_frame(0.78)
	_back_id = "title"
	_title_label("HOW TO PLAY", 30, Color(1, 0.85, 0.25), Color(0.5, 0.1, 0.3))
	_spacer(8)
	var lines := [
		["WASD", "MOVE"], ["MOUSE", "AIM"], ["LEFT CLICK", "FIRE BOTH UZIS"], ["RIGHT CLICK", "FOCUS - TIGHT AIM, SLOWER"],
		["SPACE", "JUMP (CRATES ARE JUMPABLE)"], ["SHIFT", "DASH - BRIEFLY INVINCIBLE"], ["Q / G", "THROW GRENADE"],
		["ESC", "PAUSE"],
	]
	for l in lines:
		var row := Game.label("%-13s %s" % [l[0], l[1]], 10, Color(0.9, 0.9, 1.0))
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(row)
	_spacer(8)
	_title_label("SURVIVE ENDLESS WAVES. HEADSHOTS HIT HARDER.", 10, Color(1, 0.9, 0.6))
	_title_label("EVERY WAVE YOU PICK 1 OF 3 ITEM CARDS - THEY STACK.", 10, Color(0.6, 1.0, 0.7))
	_title_label("EVERY 5TH WAVE IS A TITAN BOSS - JUMP ITS SHOCKWAVE.", 10, Color(1, 0.5, 0.5))
	_spacer(12)
	_button("BACK", "title")
	_focus_first()


func show_options(from_pause: bool) -> void:
	_frame(0.8)
	_back_id = "pause" if from_pause else "title"
	_title_label("OPTIONS", 30, Color(1, 0.85, 0.25), Color(0.5, 0.1, 0.3))
	_spacer(8)
	_opt_row("MUSIC", "music", 0.0, 1.0, 0.1, true)
	_opt_row("SFX", "sfx", 0.0, 1.0, 0.1, true)
	_opt_row("SENSITIVITY", "sens", 0.3, 2.5, 0.1, false)
	_opt_row("FIELD OF VIEW", "fov", 60.0, 100.0, 4.0, false)
	_opt_row("VERTEX JITTER", "jitter")
	_opt_row("DITHERING", "dither")
	_opt_row("HIGH RES", "hires")
	_opt_row("SCREEN SHAKE", "shake")
	_spacer(10)
	_button("BACK", _back_id)
	_focus_first()


func _opt_row(title: String, key: String, lo: float = 0.0, hi: float = 1.0, step: float = 0.1, pct: bool = false) -> void:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 10)
	b.focus_mode = Control.FOCUS_ALL
	var is_bool := typeof(Game.settings[key]) == TYPE_BOOL
	var upd := func() -> void:
		var v: Variant = Game.settings[key]
		var s: String
		if is_bool:
			s = "ON" if v else "OFF"
		elif pct:
			s = "%d%%" % roundi(float(v) * 100.0)
		else:
			s = "%.1f" % float(v)
		b.text = "%-15s < %s >" % [title, s]
	upd.call()
	b.focus_entered.connect(func() -> void: Sfx.play("ui_move", -6.0))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	var change := func(dir: int) -> void:
		if is_bool:
			Game.settings[key] = not bool(Game.settings[key])
		else:
			Game.settings[key] = clampf(snappedf(float(Game.settings[key]) + dir * step, step / 10.0), lo, hi)
		upd.call()
		Sfx.play("ui_select", -6.0)
		Game.save()
		Sfx.update_music_volume()
		settings_changed.emit()
	b.pressed.connect(func() -> void: change.call(1 if not is_bool else 0))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev.is_action_pressed("ui_left"):
			change.call(-1)
			b.accept_event()
		elif ev.is_action_pressed("ui_right"):
			change.call(1)
			b.accept_event()
		elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			change.call(-1))
	_box.add_child(b)


func show_pause() -> void:
	_frame(0.6)
	_back_id = "resume"
	_title_label("PAUSED", 40, Color(1, 0.85, 0.25), Color(0.5, 0.1, 0.3))
	_spacer(14)
	_button("RESUME", "resume")
	_button("OPTIONS", "options_pause")
	_button("QUIT TO TITLE", "title")
	_focus_first()


func show_results(s: Dictionary) -> void:
	_frame(0.82)
	results_open = true
	_title_label("YOU DIED", 50, Color(1.0, 0.25, 0.3), Color(0.3, 0.0, 0.1))
	_spacer(8)
	_title_label(Game.fmt_int(int(s["score"])), 40, Color(1, 0.9, 0.3), Color(0.5, 0.2, 0.0))
	if bool(s["new_best"]):
		_title_label("NEW HIGH SCORE!", 20, Color(0.4, 1.0, 0.6))
	_spacer(6)
	var t: float = s["time"]
	var stats := "WAVE %d    KILLS %d    BEST COMBO %d    HEADSHOTS %d    TIME %d:%02d" % [
		int(s["wave"]), int(s["kills"]), int(s["combo"]), int(s["headshots"]), int(t / 60.0), int(t) % 60]
	_title_label(stats, 10, Color(0.85, 0.85, 1.0))
	_spacer(6)
	var items: Array = s["items"]
	if items.size() > 0:
		_title_label("YOUR BUILD", 10, Color(0.7, 0.7, 0.9))
		var line := ""
		var count := 0
		for it in items:
			var id: String = it[0]
			var entry := "%s%s" % [Items.DB[id]["name"], ("" if int(it[1]) == 1 else " x%d" % int(it[1]))]
			line += (" - " if line != "" else "") + entry
			count += 1
			if count % 4 == 0:
				var l := _title_label(line, 10, Color(0.9, 0.95, 1.0))
				l.custom_minimum_size = Vector2(560, 0)
				line = ""
		if line != "":
			_title_label(line, 10, Color(0.9, 0.95, 1.0))
	_spacer(16)
	_button("RETRY", "play")
	_button("TITLE", "title")
	_focus_first()
