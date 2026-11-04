extends Node
## Global state for UZI RUSH: input map, settings, records, UI theme and the PSX lighting
## presets behind the global shader uniforms.

const SAVE_PATH := "user://uzi_rush.cfg"
const FONT_PATH := "res://assets/fonts/psx_font.fnt"

var settings := {
	"music": 0.7,
	"sfx": 0.9,
	"jitter": true,
	"dither": true,
	"hires": false,
	"shake": true,
	"sens": 1.0,
	"fov": 74.0,
}
var high_score := 0
var best_wave := 0
var best_combo := 0
var total_kills := 0

var no_save := false              ## set for automated sims/screenshots so tests never touch records
var ui_theme: Theme
var font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_load()
	_build_theme()


# ------------------------------------------------------------------ input
func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = button
	return e


func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = -1
	e.axis = axis
	e.axis_value = value
	return e


func _add(action: String, events: Array, deadzone: float = 0.4) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
	for e in events:
		InputMap.action_add_event(action, e)


func _setup_input() -> void:
	_add("move_forward", [_key(KEY_W), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)], 0.2)
	_add("move_back", [_key(KEY_S), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)], 0.2)
	_add("move_left", [_key(KEY_A), _joy_axis(JOY_AXIS_LEFT_X, -1.0)], 0.2)
	_add("move_right", [_key(KEY_D), _joy_axis(JOY_AXIS_LEFT_X, 1.0)], 0.2)
	# arrow keys look around (retro-FPS style) so the game works without mouse lock too
	_add("look_left", [_key(KEY_LEFT), _joy_axis(JOY_AXIS_RIGHT_X, -1.0)], 0.15)
	_add("look_right", [_key(KEY_RIGHT), _joy_axis(JOY_AXIS_RIGHT_X, 1.0)], 0.15)
	_add("look_up", [_key(KEY_UP), _joy_axis(JOY_AXIS_RIGHT_Y, -1.0)], 0.15)
	_add("look_down", [_key(KEY_DOWN), _joy_axis(JOY_AXIS_RIGHT_Y, 1.0)], 0.15)
	_add("jump", [_key(KEY_SPACE), _joy_button(JOY_BUTTON_A)])
	_add("dash", [_key(KEY_SHIFT), _joy_button(JOY_BUTTON_B), _joy_button(JOY_BUTTON_LEFT_SHOULDER)])
	_add("fire", [_mouse(MOUSE_BUTTON_LEFT), _key(KEY_J), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0),
		_joy_button(JOY_BUTTON_RIGHT_SHOULDER)])
	_add("focus", [_mouse(MOUSE_BUTTON_RIGHT), _key(KEY_K), _joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_add("grenade", [_key(KEY_Q), _key(KEY_G), _key(KEY_E), _joy_button(JOY_BUTTON_X)])
	_add("pause", [_key(KEY_ESCAPE), _key(KEY_P), _joy_button(JOY_BUTTON_START)])


# ---------------------------------------------------------------- save data
func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	high_score = int(cfg.get_value("records", "high_score", 0))
	best_wave = int(cfg.get_value("records", "best_wave", 0))
	best_combo = int(cfg.get_value("records", "best_combo", 0))
	total_kills = int(cfg.get_value("records", "total_kills", 0))
	for k in settings.keys():
		settings[k] = cfg.get_value("settings", k, settings[k])


func save() -> void:
	if no_save:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("records", "high_score", high_score)
	cfg.set_value("records", "best_wave", best_wave)
	cfg.set_value("records", "best_combo", best_combo)
	cfg.set_value("records", "total_kills", total_kills)
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.save(SAVE_PATH)


# -------------------------------------------------------------------- theme
func _build_theme() -> void:
	var f: FontFile = load(FONT_PATH)
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font = f
	ui_theme = Theme.new()
	ui_theme.default_font = f
	ui_theme.default_font_size = 10
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		ui_theme.set_stylebox(s, "Button", empty)
	ui_theme.set_color("font_color", "Button", Color(0.85, 0.85, 0.9))
	ui_theme.set_color("font_hover_color", "Button", Color(1.0, 0.85, 0.25))
	ui_theme.set_color("font_focus_color", "Button", Color(1.0, 0.85, 0.25))
	ui_theme.set_color("font_pressed_color", "Button", Color(1.0, 1.0, 1.0))
	ui_theme.set_font_size("font_size", "Button", 20)
	ui_theme.set_color("font_color", "Label", Color.WHITE)


static func fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


func label(text: String, size: int = 10, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --------------------------------------------------------------- PSX looks
func set_look(preset: String) -> void:
	match preset:
		"menu":
			RenderingServer.global_shader_parameter_set("psx_light_dir", Vector3(0.4, -0.8, -0.4))
			RenderingServer.global_shader_parameter_set("psx_light_color", Color(1.0, 0.72, 0.9))
			RenderingServer.global_shader_parameter_set("psx_ambient", Color(0.42, 0.34, 0.6))
			RenderingServer.global_shader_parameter_set("psx_fog_color", Color(0.45, 0.12, 0.42))
			RenderingServer.global_shader_parameter_set("psx_fog_range", Vector2(26.0, 95.0))
		_:
			RenderingServer.global_shader_parameter_set("psx_light_dir", Vector3(0.4, -0.8, -0.4))
			RenderingServer.global_shader_parameter_set("psx_light_color", Color(1.0, 0.78, 0.92))
			RenderingServer.global_shader_parameter_set("psx_ambient", Color(0.46, 0.38, 0.62))
			RenderingServer.global_shader_parameter_set("psx_fog_color", Color(0.42, 0.1, 0.38))
			RenderingServer.global_shader_parameter_set("psx_fog_range", Vector2(30.0, 100.0))


func apply_psx_settings(low_res: Vector2i) -> void:
	var snap := Vector2(low_res) * 0.5 if settings["jitter"] else Vector2.ZERO
	RenderingServer.global_shader_parameter_set("psx_snap", snap)
	RenderingServer.global_shader_parameter_set("psx_affine", 1.0 if settings["jitter"] else 0.0)
