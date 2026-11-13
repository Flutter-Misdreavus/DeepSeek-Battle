extends Node2D
## 她的对话气泡（传说之下式）：白底黑字，左侧一个尖角指向她，逐字打出，每个字一声「哔」。
## await say("您好。")；col 可以给红字。自动驾驶时 0.5 秒后自动翻页。

const PAD := 6
const CPS := 26.0

var battle: Node
var _lines := PackedStringArray()
var _col := C.BLACK
var _shown := 0.0
var _total := 0
var _typing := false
var _voice := "voice_blue"
var _last := 0
var on := false
var pos := C.BUBBLE_POS


func say(text: String, col := C.BLACK, voice := "voice_blue") -> void:
	_lines = Px.wrap(text, C.BUBBLE_W - PAD * 2)
	_total = 0
	for l in _lines:
		_total += l.length()
	_col = col
	_voice = voice
	_shown = 0.0
	_last = 0
	_typing = true
	on = true
	Inp.take_advance()
	Inp.take_ok()
	Inp.take_tap()
	while _shown < _total:
		await get_tree().process_frame
		if battle and battle.story_dialogue and Inp.take_advance():
			_shown = _total
			_typing = false
			on = false
			return
		if Inp.take_ok() or Inp.take_tap() != null:
			_shown = _total
	_typing = false
	if battle and battle.auto != "":
		await get_tree().create_timer(0.5, false).timeout
	else:
		while true:
			await get_tree().process_frame
			if battle and battle.story_dialogue and Inp.take_advance():
				break
			if Inp.take_ok() or Inp.take_tap() != null:
				break
	on = false


## 不等确认：打完字停留 hold 秒后自己消失（终局里用，不打断节奏）。不 await 也可以。
func say_timed(text: String, col := C.BLACK, voice := "voice_red", hold := 1.0) -> void:
	_lines = Px.wrap(text, C.BUBBLE_W - PAD * 2)
	_total = 0
	for l in _lines:
		_total += l.length()
	_col = col
	_voice = voice
	_shown = 0.0
	_last = 0
	_typing = true
	on = true
	while _shown < _total:
		await get_tree().process_frame
	_typing = false
	await get_tree().create_timer(hold, false).timeout
	on = false


func _process(dt: float) -> void:
	if _typing:
		_shown = minf(_shown + dt * CPS, _total)
		var n := int(_shown)
		if n > _last:
			_last = n
			Sfx.play(_voice, randf_range(0.97, 1.03))
	queue_redraw()


func _draw() -> void:
	if not on:
		return
	var h := _lines.size() * 14 + PAD * 2 - 2
	var r := Rect2(pos, Vector2(C.BUBBLE_W, h))
	draw_rect(r, C.WHITE)
	# 尖角：左边中上，往左伸 8px
	for j in 13:
		var w := 7 - absi(j - 6)
		draw_rect(Rect2(r.position.x - w, r.position.y + 6 + j, w, 1), C.WHITE)
	var budget := int(_shown)
	var y := r.position.y + PAD - 1
	for l in _lines:
		if budget <= 0:
			break
		var s: String = l.substr(0, budget)
		budget -= l.length()
		Px.text(self, Vector2(r.position.x + PAD, y), s, _col)
		y += 14
