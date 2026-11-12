extends Node
## 节拍时钟和配乐（自动加载 Conductor）。
## 配乐段在 res://audio/music/<名字>.wav，参数在 sections.json（pipeline/cut_music.py 生成）。
## beat：当前段落从第一个整拍算起的拍数（连续的小数，循环段会一直累加，不会跳回 0）。
## 时钟平时按帧时间累加，有真实音频输出时再慢慢对齐到播放位置，所以静音、无界面运行也能走。

signal section_changed(name: String)

var beat := 0.0
var section := ""
var looped := false
var _t := 0.0                     # 本段从 clip 开头算起的秒数（不回绕）
var _first := 0.0                 # clip 里第一个整拍的秒数
var _len := 0.0                   # clip 长度（秒）
var _playing := false
var _sections := {}
var _player: AudioStreamPlayer
var _bus := 0
var _lowpass: AudioEffectLowPassFilter
var _audio_ok := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = -90
	_bus = AudioServer.bus_count
	AudioServer.add_bus(_bus)
	AudioServer.set_bus_name(_bus, "Music")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 900.0
	AudioServer.add_bus_effect(_bus, _lowpass)
	AudioServer.set_bus_effect_enabled(_bus, 0, false)
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)
	_audio_ok = AudioServer.get_driver_name() != "Dummy"
	var f := FileAccess.open("res://audio/music/sections.json", FileAccess.READ)
	if f:
		_sections = JSON.parse_string(f.get_as_text()).get("sections", {})
	else:
		push_warning("Conductor: 没有 sections.json，配乐不可用，只走节拍时钟")
	if Dbg.has("mute"):
		AudioServer.set_bus_volume_db(_bus, -80.0)


## 播放一段配乐，从第 from_beat 拍开始
func play(name: String, from_beat := 0.0) -> void:
	section = name
	var s: Dictionary = _sections.get(name, {})
	looped = s.get("loop", true)
	_first = s.get("first_beat_in_clip", 0.0)
	_len = s.get("length_sec", 0.0)
	_t = _first + from_beat * C.SPB
	_playing = true
	var path := "res://audio/music/%s.wav" % name
	if not s.is_empty() and ResourceLoader.exists(path):
		var st: AudioStreamWAV = load(path)
		if looped:
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = int(_len * st.mix_rate)
		else:
			st.loop_mode = AudioStreamWAV.LOOP_DISABLED
		_player.stream = st
		_player.play(_t)
	else:
		_player.stop()
		if _len <= 0.0:
			_len = 64 * C.SPB
	beat = (_t - _first) / C.SPB
	section_changed.emit(name)


func stop(fade := 0.0) -> void:
	_playing = false
	if fade > 0.0 and _player.playing:
		var tw := create_tween()
		tw.tween_property(_player, "volume_db", -60.0, fade)
		await tw.finished
	_player.stop()
	_player.volume_db = 0.0


func set_lowpass(on: bool, cutoff := 900.0) -> void:
	_lowpass.cutoff_hz = cutoff
	AudioServer.set_bus_effect_enabled(_bus, 0, on)


func set_paused(p: bool) -> void:
	_player.stream_paused = p


## 本段结束了吗（只对不循环的段有意义）
func finished() -> bool:
	return not looped and _len > 0.0 and _t >= _len


func _process(dt: float) -> void:
	if not _playing:
		return
	_t += dt
	if _audio_ok and _player.playing and _len > 0.0:
		var pos := _player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		if looped:
			pos += floorf((_t - pos) / _len + 0.5) * _len
		var err := pos - _t
		if absf(err) > 0.12:
			_t = pos
		else:
			_t += err * 0.1
	beat = (_t - _first) / C.SPB


## 等到下一个整拍（或下第 n 个整拍）
func wait_beat(n := 1) -> void:
	var target := floorf(beat) + n
	while beat < target:
		await get_tree().process_frame


## 等 b 拍
func wait_beats(b: float) -> void:
	var target := beat + b
	while beat < target:
		await get_tree().process_frame
