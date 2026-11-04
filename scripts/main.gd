extends Node
## Root of UZI RUSH. Renders the 3D arena into a low-res SubViewport and the Uzis into a second
## transparent one, composites both through the PSX dither / 15-bit post shader, manages mouse
## capture (pointer lock on the web) and switches between the title screen and the endless run.

const POST_SHADER := preload("res://shaders/psx_post.gdshader")

var world_vp: SubViewport
var gun_vp: SubViewport
var view: TextureRect
var gun_view: TextureRect
var post: ShaderMaterial
var post_gun: ShaderMaterial
var stage_root: Node3D
var world: World
var fx: FX
var entities: Node3D
var player: Player
var vm: ViewModel
var run: Run
var title_cam: Camera3D
var hud_layer: CanvasLayer
var menu_layer: CanvasLayer
var menus: Menus
var hud: Hud
var draft: Draft
var mode := "title"
var _title_t := 0.0
var _had_capture := false
var _capture_tried := false
var _capture_try_t := 0.0
var _capture_req_t := 0.0
var _fallback_hint := false
var _mouse_inside := true
var _edge_armed := false
var _testing := false
var _auto_t := 0.0
var _auto_dir := Vector2.ZERO
var _gallery := false
var _show_fake_results := false

const EDGE_ZONE := 0.82
const EDGE_YAW_RATE := 2.8
const EDGE_PITCH_RATE := 1.6


func _ready() -> void:
	get_tree().root.theme = Game.ui_theme
	Game.set_look("arena")
	world_vp = SubViewport.new()
	world_vp.own_world_3d = true
	world_vp.msaa_3d = Viewport.MSAA_DISABLED
	world_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_vp.size = Vector2i(427, 240)
	add_child(world_vp)
	stage_root = Node3D.new()
	world_vp.add_child(stage_root)
	world = World.new()
	stage_root.add_child(world)
	fx = FX.new()
	stage_root.add_child(fx)
	entities = Node3D.new()
	stage_root.add_child(entities)
	player = Player.new()
	stage_root.add_child(player)
	title_cam = Camera3D.new()
	title_cam.far = 400.0
	stage_root.add_child(title_cam)

	gun_vp = SubViewport.new()
	gun_vp.own_world_3d = true
	gun_vp.transparent_bg = true
	gun_vp.msaa_3d = Viewport.MSAA_DISABLED
	gun_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	gun_vp.size = world_vp.size
	add_child(gun_vp)
	vm = ViewModel.new()
	gun_vp.add_child(vm)

	view = _make_view(world_vp)
	post = view.material as ShaderMaterial
	add_child(view)
	gun_view = _make_view(gun_vp)
	post_gun = gun_view.material as ShaderMaterial
	add_child(gun_view)

	var inv := Inventory.new()
	run = Run.new()
	add_child(run)
	player.setup(run, world, fx, vm, inv)
	run.setup(world, fx, player, inv, entities)
	run.draft_requested.connect(_on_draft)
	run.game_over.connect(_on_game_over)
	player.revived.connect(func() -> void: hud.show_hint("SECOND WIND!", 2.0))

	hud_layer = CanvasLayer.new()
	hud_layer.layer = 2
	add_child(hud_layer)
	hud = Hud.new()
	hud_layer.add_child(hud)
	hud.bind(run, player)
	hud.project = Callable(self, "_project")

	menu_layer = CanvasLayer.new()
	menu_layer.layer = 5
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_layer)
	draft = Draft.new()
	draft.visible = false
	menu_layer.add_child(draft)
	draft.picked.connect(_on_card_picked)
	menus = Menus.new()
	menu_layer.add_child(menus)
	menus.chosen.connect(_on_menu)
	menus.settings_changed.connect(_on_resize)

	get_tree().root.size_changed.connect(_on_resize)
	_on_resize()
	_parse_cmdline()
	if run.autoplay:
		start_game()
	elif _show_fake_results:
		go_title()
		menus.show_results({"score": 48210, "wave": 9, "kills": 112, "combo": 31, "time": 412.0, "headshots": 40,
			"new_best": true, "items": [["hollow_points", 3], ["tesla", 1], ["glass_cannon", 1], ["sentry", 2], ["feather", 1],
			["devils_deal", 1], ["explosive", 2]]})
	else:
		go_title()


func _make_view(vp: SubViewport) -> TextureRect:
	var v := TextureRect.new()
	v.texture = vp.get_texture()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	v.stretch_mode = TextureRect.STRETCH_SCALE
	v.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = POST_SHADER
	v.material = m
	return v


func _parse_cmdline() -> void:
	var args: Array = Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("window.location.search")
		if q is String and "autoplay" in (q as String):
			args.append("--autoplay")
		if q is String and "gallery" in (q as String):
			args.append("--gallery")
		if q is String and "results" in (q as String):
			args.append("--results")
	for a in args:
		if a == "--results":
			_show_fake_results = true
		if a == "--gallery":
			_gallery = true
			_testing = true
			Game.no_save = true
		if a == "--autoplay":
			run.autoplay = true
			_testing = true
			Game.no_save = true


func _on_resize() -> void:
	var s := get_viewport().get_visible_rect().size
	var h := 360 if Game.settings["hires"] else 240
	var w := int(roundf(h * s.x / maxf(1.0, s.y)))
	world_vp.size = Vector2i(maxi(w, 16), h)
	gun_vp.size = world_vp.size
	for m: ShaderMaterial in [post, post_gun]:
		m.set_shader_parameter("src_size", Vector2(world_vp.size))
		m.set_shader_parameter("dither_amount", 1.0 if Game.settings["dither"] else 0.0)
		m.set_shader_parameter("color_levels", 32.0 if Game.settings["dither"] else 256.0)
	post_gun.set_shader_parameter("vignette", 0.0)
	Game.apply_psx_settings(world_vp.size)


func _project(p: Vector3) -> Vector2:
	var cam := player.cam
	if cam.is_position_behind(p):
		return Vector2(-999, -999)
	var v := cam.unproject_position(p)
	return v * (view.size / Vector2(world_vp.size))


# ------------------------------------------------------------------ states
func go_title() -> void:
	mode = "title"
	get_tree().paused = false
	Engine.time_scale = 1.0
	run.clear_entities()
	run.state = "idle"
	player.active = false
	hud.visible = false
	gun_view.visible = false
	draft.close()
	title_cam.current = true
	_release()
	Sfx.play_music("sunset")
	menus.show_title()


func start_game() -> void:
	mode = "play"
	get_tree().paused = false
	menus.hide_all()
	hud.visible = true
	hud.reset()
	gun_view.visible = true
	player.cam.current = true
	vm.cam.current = true
	Sfx.play_music("battle")
	run.start()
	if not run.autoplay:
		_capture()


func _on_menu(id: String) -> void:
	match id:
		"play":
			start_game()
		"title":
			go_title()
		"how":
			menus.show_how()
		"options":
			menus.show_options(false)
		"options_pause":
			menus.show_options(true)
		"pause":
			menus.show_pause()
		"resume":
			_resume()


func _pause() -> void:
	if mode != "play" or get_tree().paused or draft.visible or run.state == "over":
		return
	get_tree().paused = true
	_release()
	Sfx.play("ui_select", -6.0)
	menus.show_pause()


func _resume() -> void:
	get_tree().paused = false
	menus.hide_all()
	_capture()


func _on_draft(cards: Array, title: String) -> void:
	get_tree().paused = true
	_release()
	draft.open(cards, title, func(id: String) -> int: return run.inv.count(id))
	if run.autoplay or _gallery:
		get_tree().create_timer(0.5, true, false, true).timeout.connect(func() -> void:
			if draft.visible:
				draft._pick(randi() % cards.size()))


func _on_card_picked(id: String) -> void:
	draft.close()
	get_tree().paused = false
	run.pick_card(id)
	if _gallery:
		_spawn_gallery()
	if not run.autoplay:
		_capture()


func _on_game_over(summary: Dictionary) -> void:
	if run.autoplay:
		print("[sim] GAME OVER ", summary)
		start_game()
		return
	_release()
	menus.show_results(summary)


# -------------------------------------------------------------- mouse capture
func _playing() -> bool:
	return mode == "play" and not get_tree().paused and not menus.results_open and not draft.visible \
		and run.state != "over"


func _capture() -> void:
	_edge_armed = false
	if not _testing:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_capture_req_t = 0.0


func _release() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_had_capture = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_ENTER:
		_mouse_inside = true
	elif what == NOTIFICATION_WM_MOUSE_EXIT:
		_mouse_inside = false


func _process(dt: float) -> void:
	if mode == "title":
		_title_t += dt * 0.12
		var r := 17.0
		title_cam.global_position = Vector3(sin(_title_t) * r, 5.5 + sin(_title_t * 1.7) * 1.2, cos(_title_t) * r)
		title_cam.look_at(Vector3(0, 2.5, 0))
	if run.autoplay and mode == "play":
		_autoplay(dt)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _playing():
		# the browser drops pointer lock on Esc without sending the key: treat it as pause
		if _had_capture and not captured:
			_pause()
			return
		_had_capture = captured
		hud.capture_needed = not captured and not _testing and not _capture_tried
		if not captured and not _testing:
			_capture_req_t += dt
			if _capture_req_t > 0.4 and Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
				Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
			_edge_turn(dt)
			if _capture_tried:
				_capture_try_t += dt
				if _capture_try_t > 0.8 and not _fallback_hint:
					_fallback_hint = true
					hud.show_hint("MOUSE LOCK BLOCKED HERE - MOVE THE MOUSE TO AIM, HOLD IT AT THE EDGE TO KEEP TURNING", 7.0)
	else:
		hud.capture_needed = false


func _edge_turn(dt: float) -> void:
	if not _mouse_inside or not _edge_armed:
		return
	var vp := get_viewport()
	var sz := vp.get_visible_rect().size
	var mp := vp.get_mouse_position()
	var n := Vector2(mp.x / maxf(1.0, sz.x), mp.y / maxf(1.0, sz.y)) * 2.0 - Vector2.ONE
	if absf(n.x) > 1.05 or absf(n.y) > 1.05:
		return
	var turn := Vector2.ZERO
	if absf(n.x) > EDGE_ZONE:
		turn.x = signf(n.x) * (absf(n.x) - EDGE_ZONE) / (1.0 - EDGE_ZONE)
	if absf(n.y) > EDGE_ZONE:
		turn.y = signf(n.y) * (absf(n.y) - EDGE_ZONE) / (1.0 - EDGE_ZONE)
	if turn != Vector2.ZERO:
		var sens := float(Game.settings["sens"])
		player.add_look(-turn.x * EDGE_YAW_RATE * sens * dt, -turn.y * EDGE_PITCH_RATE * sens * dt)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _playing() and player.active:
		player.mouse_look((event as InputEventMouseMotion).screen_relative)
		if (event as InputEventMouseMotion).screen_relative.length() > 0.5:
			_edge_armed = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and _playing():
		# first click on the page locks the pointer if the browser refused earlier
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _testing:
			_capture_tried = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("pause"):
		if mode == "play" and not get_tree().paused:
			_pause()
		elif mode == "play" and get_tree().paused and not draft.visible and menus.results_open == false:
			pass


# ------------------------------------------------------------------ autoplay
## Headless self-play used to smoke-test the whole game loop (--autoplay).
func _autoplay(dt: float) -> void:
	if not player.alive or not player.active:
		Input.action_release("fire")
		return
	var best: Enemy = null
	var bd := 1e9
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and e.alive:
			var d := e.center().distance_to(player.global_position)
			if d < bd:
				bd = d
				best = e
	if best != null:
		var to := best.center() - player.eye()
		var want_yaw := atan2(-to.x, -to.z)
		var want_pitch := asin(clampf(to.y / maxf(0.01, to.length()), -1.0, 1.0))
		player.yaw = lerp_angle(player.yaw, want_yaw, clampf(dt * 14.0, 0.0, 1.0))
		player.pitch = lerpf(player.pitch, want_pitch, clampf(dt * 14.0, 0.0, 1.0))
		Input.action_press("fire")
		if randf() < dt * 0.4:
			Input.action_press("grenade")
		else:
			Input.action_release("grenade")
	else:
		Input.action_release("fire")
	_auto_t -= dt
	if _auto_t <= 0.0:
		_auto_t = randf_range(0.4, 1.2)
		_auto_dir = Vector2(randf_range(-1, 1), randf_range(-0.2, 1)).normalized()
		if bd < 4.0:
			_auto_dir = Vector2(randf_range(-1, 1), 1.0).normalized()
		if randf() < 0.3:
			Input.action_press("jump")
		else:
			Input.action_release("jump")
		if randf() < 0.2:
			Input.action_press("dash")
		else:
			Input.action_release("dash")
	Input.action_press("move_right", maxf(0.0, _auto_dir.x))
	Input.action_press("move_left", maxf(0.0, -_auto_dir.x))
	Input.action_press("move_back", maxf(0.0, _auto_dir.y))
	Input.action_press("move_forward", maxf(0.0, -_auto_dir.y))


## Debug (?gallery): line up one of every enemy in front of the player, frozen, for screenshots.
func _spawn_gallery() -> void:
	run.debug_freeze = true
	var spots := {"grunt": Vector3(-3.2, 0, 2.5), "gunner": Vector3(-1.1, 0, 2.0), "brute": Vector3(1.6, 0, 1.8),
		"drone": Vector3(3.6, 0, 3.0), "titan": Vector3(0, 0, -4.5)}
	for k in spots:
		var e := run.spawn_enemy(k, spots[k])
		e.rotation.y = PI
