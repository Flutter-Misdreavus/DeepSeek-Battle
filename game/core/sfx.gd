extends Node
## 音效（自动加载 Sfx）。音效文件在 res://audio/sfx/<名字>.wav（pipeline/sfx_synth.py 合成）。
## Sfx.play("menu_move")；同时最多 10 个声音，轮流复用播放器。

var _players: Array[AudioStreamPlayer] = []
var _cache := {}
var _next := 0
var _missing := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	if Dbg.has("mute"):
		AudioServer.set_bus_volume_db(0, -80.0)


func play(name: String, pitch := 1.0, vol_db := 0.0) -> void:
	var st = _cache.get(name)
	if st == null:
		var path := "res://audio/sfx/%s.wav" % name
		if not ResourceLoader.exists(path):
			if not _missing.has(name):
				_missing[name] = true
				push_warning("Sfx: 缺少音效 " + name)
			return
		st = load(path)
		_cache[name] = st
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = st
	p.pitch_scale = pitch
	p.volume_db = vol_db
	p.play()
