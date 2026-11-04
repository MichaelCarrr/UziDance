extends Node
## Sound effect pool + looping music player.

const NAMES := ["uzi0", "uzi1", "uzi2", "hit_tick", "headshot", "enemy_hurt", "enemy_die", "explosion", "enemy_shot",
	"pickup", "heal", "dash", "wave_start", "wave_clear", "boss_roar", "grenade_throw", "heartbeat", "powerup",
	"reload_click", "beep", "go", "ui_move", "ui_select", "ui_back", "jump", "land", "damage", "item_get", "card_flip",
	"transform", "extra_life", "ko", "combo", "crit", "cheer", "whistle", "hit", "hit_big", "enemy_pop", "drop",
	"spell_cast"]
const POOL := 20

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _music_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		_streams[n] = load("res://assets/audio/%s.wav" % n)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_music.finished.connect(func() -> void: _music.play())


func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0, pitch_var: float = 0.0) -> void:
	var s: AudioStream = _streams.get(sound)
	if s == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.volume_db = volume_db + linear_to_db(maxf(0.001, float(Game.settings["sfx"])))
	p.pitch_scale = maxf(0.1, pitch + randf_range(-pitch_var, pitch_var))
	p.play()


func play_music(track: String) -> void:
	if track == _music_name and _music.playing:
		return
	_music_name = track
	var s: AudioStream = load("res://assets/audio/music_%s.wav" % track)
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	_music.stream = s
	update_music_volume()
	_music.play()


func stop_music() -> void:
	_music_name = ""
	_music.stop()


func update_music_volume() -> void:
	_music.volume_db = linear_to_db(maxf(0.001, float(Game.settings["music"]))) - 7.0
