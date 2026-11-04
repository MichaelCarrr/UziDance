class_name Draft
extends Control
## The roguelike card draft: three item cards, pick one (click, 1-3, arrows + Enter / A).

signal picked(id: String)

const ICONS := preload("res://assets/textures/items.png")
const FRAME := preload("res://assets/textures/card_frame.png")
const CARD_W := 200.0
const CARD_H := 250.0

var _ids: Array = []
var _title := ""
var _sel := 0
var _age := 0.0
var _owned: Callable
var _rects: Array[Rect2] = []
var _done := false


func _ready() -> void:
	theme = Game.ui_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(ids: Array, title: String, owned: Callable) -> void:
	_ids = ids
	_title = title
	_owned = owned
	_sel = 1 if ids.size() > 1 else 0
	_age = 0.0
	_done = false
	visible = true
	grab_focus()


func close() -> void:
	visible = false
	_done = true


func _process(dt: float) -> void:
	if not visible:
		return
	_age += dt
	queue_redraw()


func _layout() -> void:
	_rects.clear()
	var n := _ids.size()
	var gap := 18.0
	var total := n * CARD_W + (n - 1) * gap
	var x0 := (size.x - total) * 0.5
	var y0 := (size.y - CARD_H) * 0.5 + 14.0
	for i in n:
		_rects.append(Rect2(x0 + i * (CARD_W + gap), y0, CARD_W, CARD_H))


func _gui_input(event: InputEvent) -> void:
	if _done or _age < 0.35:
		return
	_layout()
	if event is InputEventMouseMotion:
		var p := (event as InputEventMouseMotion).position
		for i in _rects.size():
			if _rects[i].has_point(p) and _sel != i:
				_sel = i
				Sfx.play("ui_move", -6.0)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			for i in _rects.size():
				if _rects[i].has_point(mb.position):
					_pick(i)
					return
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k < KEY_1 + _ids.size():
			_pick(k - KEY_1)
		elif k == KEY_LEFT or k == KEY_A:
			_sel = posmod(_sel - 1, _ids.size())
			Sfx.play("ui_move", -6.0)
		elif k == KEY_RIGHT or k == KEY_D:
			_sel = posmod(_sel + 1, _ids.size())
			Sfx.play("ui_move", -6.0)
		elif k == KEY_ENTER or k == KEY_SPACE or k == KEY_KP_ENTER:
			_pick(_sel)
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var b := (event as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_A:
			_pick(_sel)
		elif b == JOY_BUTTON_DPAD_LEFT:
			_sel = posmod(_sel - 1, _ids.size())
		elif b == JOY_BUTTON_DPAD_RIGHT:
			_sel = posmod(_sel + 1, _ids.size())


func _pick(i: int) -> void:
	if _done or i < 0 or i >= _ids.size():
		return
	_done = true
	picked.emit(_ids[i])


func _wrap(text: String, size_px: int, width: float) -> Array:
	var words := text.split(" ")
	var lines: Array = []
	var cur := ""
	for w in words:
		var t: String = w if cur == "" else cur + " " + w
		if Game.font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > width and cur != "":
			lines.append(cur)
			cur = w
		else:
			cur = t
	if cur != "":
		lines.append(cur)
	return lines


func _txt(text: String, pos: Vector2, size_px: int, color: Color, centered_w: float = 0.0) -> void:
	var x := pos.x
	if centered_w > 0.0:
		x += (centered_w - Game.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x) * 0.5
	draw_string(Game.font, Vector2(x, pos.y + size_px), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.0, 0.06, 0.78))
	_layout()
	var tc := Color(1, 0.85, 0.3)
	var ts := Game.font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_txt(_title, Vector2((size.x - ts) * 0.5, _rects[0].position.y - 52.0 if _rects.size() > 0 else 40.0), 20, tc)
	if _rects.is_empty():
		return
	for i in _ids.size():
		var id: String = _ids[i]
		var info: Dictionary = Items.DB[id]
		var rc: Color = Items.COLORS[info["rarity"]]
		var delay := 0.1 * i
		var k := clampf((_age - delay) * 5.0, 0.0, 1.0)
		var r := _rects[i]
		var lift := (1.0 - ease(k, 0.3)) * 60.0
		var sel := i == _sel
		var up := -10.0 if sel else 0.0
		var rr := Rect2(r.position + Vector2(0, lift + up), r.size)
		var a := k
		# frame
		draw_rect(Rect2(rr.position - Vector2(3, 3), rr.size + Vector2(6, 6)), Color(rc.r, rc.g, rc.b, a * (1.0 if sel else 0.55)))
		draw_rect(rr, Color(0.07, 0.04, 0.12, a * 0.97))
		draw_rect(Rect2(rr.position + Vector2(4, 4), rr.size - Vector2(8, 8)), Color(rc.r * 0.14, rc.g * 0.14, rc.b * 0.14, a))
		# number
		_txt("%d" % (i + 1), rr.position + Vector2(10, 8), 10, Color(1, 1, 1, a * 0.6))
		_txt(Items.RARITY_NAMES[info["rarity"]], rr.position + Vector2(0, 10), 10, Color(rc.r, rc.g, rc.b, a), rr.size.x)
		# icon
		var ic: int = info["icon"]
		var icon_r := Rect2(rr.position.x + rr.size.x * 0.5 - 28, rr.position.y + 32, 56, 56)
		draw_rect(Rect2(icon_r.position - Vector2(4, 4), icon_r.size + Vector2(8, 8)), Color(0, 0, 0, a * 0.6))
		draw_texture_rect_region(ICONS, icon_r, Rect2((ic % 8) * 8, (ic / 8) * 8, 8, 8), Color(rc.r, rc.g, rc.b, a))
		# name
		var nm: String = info["name"]
		var nsz := 10
		_txt(nm, rr.position + Vector2(0, 102), 20 if Game.font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x < rr.size.x - 14 else nsz,
			Color(1, 1, 1, a), rr.size.x)
		# description
		var lines := _wrap(String(info["desc"]), 10, rr.size.x - 28)
		var ly := rr.position.y + 134.0
		for ln in lines:
			_txt(String(ln), Vector2(rr.position.x, ly), 10, Color(0.85, 0.85, 0.95, a), rr.size.x)
			ly += 14.0
		_txt(String(info["stack"]), Vector2(rr.position.x, rr.end.y - 44), 10, Color(rc.r, rc.g, rc.b, a * 0.8), rr.size.x)
		var owned: int = int(_owned.call(id)) if _owned.is_valid() else 0
		if owned > 0:
			_txt("OWNED x%d" % owned, Vector2(rr.position.x, rr.end.y - 26), 10, Color(0.6, 1.0, 0.6, a), rr.size.x)
		else:
			_txt("NEW", Vector2(rr.position.x, rr.end.y - 26), 10, Color(1.0, 0.9, 0.3, a), rr.size.x)
	_txt("CLICK A CARD  -  OR PRESS 1 2 3", Vector2(0, _rects[0].end.y + 30), 10, Color(0.8, 0.8, 0.95, 0.8), size.x)
