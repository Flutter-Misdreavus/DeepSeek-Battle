extends Node2D
## 过场专用绘制节点：聊天界面（mode = "chat"）、结束卡（mode = "card"）、
## 鲸落（mode = "fall"）、鲸鱼送行（mode = "escort"）。
## 由 cutscenes.gd 创建并 add_child 到 battle 上，插在 overlay 下面、标题栏下面，用完 queue_free()。

const CHAT_X := 120.0
const CHAT_W := 380.0
const LINE_H := 14.0
const MSG_Y0 := 70.0
const MSG_GAP := 10.0
const THOUGHT_FILL_END := 2.25
const THOUGHT_END := 2.4
const CHAT_BOTTOM := 280.0

var battle: Node

var mode := "chat"

# ── chat ────────────────────────────────────────────────────
var input_text := ""
var caret := false
var msgs: Array = []                  # {who, text, shown, col}
var think := {"on": false, "lines": [], "shown": 0}
var _intro_thought_running := false
var _intro_elapsed := 0.0
var _intro_prefix := ""
var _intro_unit := ""
var _intro_repeats := 0
var _thought_full_end := 0.0
var glitch := 0.0                     # 0..1

# ── card / escort ────────────────────────────────────────────
var title := ""
var lines: Array = []
var k := 0.0                          # card 淡入进度；escort 绕行进度
var leave := 0.0                      # escort 往右游出画面

# ── fall ────────────────────────────────────────────────────
var fall := 0.0                       # 巨鲸下沉进度 0..1
var caption_a := 0.0                  # 字幕透明度

var _snow: Array = []
var _t := 0.0
var _rows: Array = []                 # 本帧已经画出的文字行，故障时按横带重画


func _process(dt: float) -> void:
	_t += dt
	if _intro_thought_running:
		_update_intro_thought(dt)
	if mode == "fall":
		_update_snow(dt)
	queue_redraw()


func _draw() -> void:
	match mode:
		"card":
			_draw_card()
		"fall":
			_draw_fall()
		"escort":
			_draw_escort()
		_:
			_draw_chat()


func _offset() -> Vector2:
	var n = battle if battle != null else get_parent()
	return n.position


# ════════════════════════════════════════════════════════════
# 聊天界面
# ════════════════════════════════════════════════════════════

func _draw_chat() -> void:
	Px.screen_rect(self, _offset(), C.BLACK)
	_rows.clear()
	_draw_input()
	var bands := _make_bands() if glitch > 0.0 else []
	var y := MSG_Y0
	var think_done := not bool(think.get("on", false))
	for i in msgs.size():
		var m: Dictionary = msgs[i]
		if str(m.get("who", "her")) == "user":
			y = _draw_user_msg(m, y)
		else:
			if not think_done:
				y = _draw_think(y) + MSG_GAP
				think_done = true
			y = _draw_her_msg(m, y)
		y += MSG_GAP
	if not think_done:
		_draw_think(y)
	if glitch > 0.0:
		_draw_glitch(bands)


func _draw_input() -> void:
	var box := Rect2(120, 300, 400, 22)
	Px.frame(self, box, 1, C.GRAY)
	var txt := input_text
	var col := C.WHITE
	if txt == "":
		txt = "给 DeepSeek 发送消息"
		col = C.GRAY_DIM
	Px.text(self, Vector2(128, 305), txt, col)
	_rows.append({"y": 305.0, "h": 12.0, "text": txt, "x": 128.0, "col": col})
	if caret and int(Time.get_ticks_msec() / 500) % 2 == 0:
		var cx := 128.0
		if input_text != "":
			cx += Px.text_w(input_text)
		draw_rect(Rect2(cx, 305, 1, 12), C.WHITE)


func _draw_user_msg(m: Dictionary, y: float) -> float:
	var text := str(m.get("text", ""))
	var shown := int(m.get("shown", text.length()))
	var vis := text.substr(0, shown)
	var bw := Px.text_w(text) + 12.0
	var h := 26.0
	var x := 520.0 - bw
	draw_rect(Rect2(x, y, bw, h), C.SYS_DIM)
	var tx := x + 6.0
	var ty := y + 6.0
	Px.text(self, Vector2(tx, ty), vis, C.WHITE)
	if vis != "":
		_rows.append({"y": ty, "h": LINE_H, "text": vis, "x": tx, "col": C.WHITE})
	return y + h


func _draw_her_msg(m: Dictionary, y: float) -> float:
	var text := str(m.get("text", ""))
	var col: Color = m.get("col", C.WHITE)
	var wrapped := Px.wrap(text, CHAT_W)
	var budget := int(m.get("shown", text.length()))
	var ty := y
	for line in wrapped:
		if budget > 0:
			var vis := line.substr(0, budget)
			Px.text(self, Vector2(CHAT_X, ty), vis, col)
			if vis != "":
				_rows.append({"y": ty, "h": LINE_H, "text": vis, "x": CHAT_X, "col": col})
			budget -= line.length()
		ty += LINE_H
	return y + maxf(1.0, wrapped.size()) * LINE_H


func _draw_think(y: float) -> float:
	var collapsed: bool = think.get("collapsed", false)
	var title_line := "▶ Deepseek思考:" if collapsed else "Deepseek思考:"
	var strike_rows: Array = [{"pos": Vector2(CHAT_X, y), "text": title_line}]
	Px.text(self, Vector2(CHAT_X, y), title_line, C.GRAY)
	_rows.append({"y": y, "h": LINE_H, "text": title_line, "x": CHAT_X, "col": C.GRAY})
	if collapsed:
		return y + LINE_H
	var arr: Array = think.get("lines", [])
	var budget := int(think.get("shown", 0))
	var ty := y + LINE_H
	var visible_bottom := ty
	# 自动换行只影响绘制；输入推进仍按原来的三句处理。
	for line in arr:
		for wrapped in Px.wrap(str(line), CHAT_W - 12.0):
			if budget > 0:
				var vis: String = wrapped.substr(0, budget)
				Px.text(self, Vector2(CHAT_X + 12, ty), vis, C.GRAY)
				if vis != "":
					_rows.append({"y": ty, "h": LINE_H, "text": vis, "x": CHAT_X + 12, "col": C.GRAY})
					visible_bottom = ty + LINE_H
					strike_rows.append({"pos": Vector2(CHAT_X + 12, ty), "text": vis})
			budget -= wrapped.length()
			ty += LINE_H
	if visible_bottom > y + LINE_H:
		draw_rect(Rect2(122, y + LINE_H, 1, visible_bottom - y - LINE_H), C.GRAY_DIM)
	var strike: float = think.get("strike", 0.0)
	if strike > 0.0:
		for row in strike_rows:
			var start: Vector2 = row["pos"] + Vector2(0, Px.font().get_ascent(12) - 5.0)
			draw_line(start, start + Vector2(Px.text_w(row["text"]) * strike, 0), C.RED, 2.0)
	return ty


# ── 故障：按行错位 ─────────────────────────────────────────

func _make_bands() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = Dbg.frame * 92821 + 17
	var out: Array = []
	var n := int(4 + 10 * glitch)
	for _i in n:
		var by := rng.randi_range(0, 352)
		var bh := rng.randi_range(2, 8)
		var dx := (4.0 + 20.0 * glitch) * (-1.0 if rng.randf() < 0.5 else 1.0)
		out.append({"y": float(by), "h": float(bh), "dx": dx})
	return out


func _draw_glitch(bands: Array) -> void:
	var off := _offset()
	var vw := get_viewport_rect().size.x
	for band in bands:
		draw_rect(Rect2(-off.x, band["y"], vw, band["h"]), C.BLACK)
	for band in bands:
		var by: float = band["y"]
		var bh: float = band["h"]
		var dx: float = band["dx"]
		for r in _rows:
			var ry: float = r["y"]
			var rh: float = r["h"]
			if ry < by + bh and ry + rh > by:
				Px.text(self, Vector2(float(r["x"]) + dx, ry), str(r["text"]), r["col"])


# ════════════════════════════════════════════════════════════
# 鲸落
# ════════════════════════════════════════════════════════════

func _update_snow(dt: float) -> void:
	var off := _offset()
	var full := Rect2(-off, get_viewport_rect().size)
	if _snow.is_empty():
		for _i in 40:
			_snow.append({"p": Vector2(randf_range(full.position.x, full.end.x), randf_range(full.position.y, full.end.y)), "v": randf_range(8.0, 16.0), "ph": randf_range(0.0, TAU), "amp": randf_range(1.0, 3.0)})
	for s in _snow:
		var p: Vector2 = s["p"]
		p.y += float(s["v"]) * dt
		if p.y > full.end.y:
			p = Vector2(randf_range(full.position.x, full.end.x), full.position.y - randf_range(0.0, 20.0))
		s["p"] = p


func _draw_fall() -> void:
	Whale.draw(self, Vector2(320 + 20 * sin(fall * 3.0), lerpf(-140.0, 300.0, fall)), Vector2(1, 0.7), 240, Color(C.SYS_DIM, 0.85))
	for s in _snow:
		var p: Vector2 = s["p"]
		var x := p.x + sin(_t * 1.2 + float(s["ph"])) * float(s["amp"])
		draw_rect(Rect2(Vector2(x, p.y).round(), Vector2(1, 1)), Color(C.WHITE, 0.5))
	var text := "一鲸落，万物生。"
	var w := Px.text_w(text)
	Px.text(self, Vector2(roundf(320.0 - w / 2.0), 320), text, Color(C.GRAY, caption_a))


# ════════════════════════════════════════════════════════════
# 鲸鱼送行
# ════════════════════════════════════════════════════════════

func _draw_escort() -> void:
	var c := C.STAGE_FOOT + Vector2(0, -C.STAGE_H * 0.55)
	for i in 5:
		var a := TAU * i / 5.0 + k * TAU
		var r := 50.0 + 12.0 * (i % 2)
		var p := c + Vector2(cos(a) * r, sin(a) * r * 0.5)
		var dir := Vector2(-sin(a) * r, cos(a) * r * 0.5).normalized()
		if leave > 0.0:
			p += Vector2(leave * leave * 420.0, -leave * 30.0)
			dir = dir.lerp(Vector2(1, 0), leave).normalized()
		Whale.draw(self, p, dir, 16, C.WHITE)


# ════════════════════════════════════════════════════════════
# 结束卡
# ════════════════════════════════════════════════════════════

func _draw_card() -> void:
	Px.screen_rect(self, _offset(), C.BLACK)
	var a := clampf(k, 0.0, 1.0)
	var tw := Px.text_w(title, 24)
	Px.text(self, Vector2(roundf(320.0 - tw / 2.0), 120), title, Color(C.WHITE, a), 24)
	for i in lines.size():
		var s := str(lines[i])
		var w := Px.text_w(s)
		Px.text(self, Vector2(roundf(320.0 - w / 2.0), 160.0 + i * 18.0), s, Color(C.GRAY, a))
	if int(Time.get_ticks_msec() / 600.0) % 2 == 0:
		var s := "按确认键回到标题"
		var w := Px.text_w(s)
		Px.text(self, Vector2(roundf(320.0 - w / 2.0), 300), s, Color(C.GRAY_DIM, a))


# ════════════════════════════════════════════════════════════
# 打字协程
# ════════════════════════════════════════════════════════════

## 逐字打出一句；回车只结束当前句，返回是否由回车推进。
func type_input(text: String, cps: float) -> bool:
	Inp.take_advance()
	input_text = ""
	var elapsed := 0.0
	while input_text.length() < text.length():
		await get_tree().process_frame
		if Inp.take_advance():
			input_text = text
			return true
		elapsed += get_process_delta_time()
		var shown := mini(text.length(), int(elapsed * cps))
		if shown > input_text.length():
			Sfx.play("text_sys")
		input_text = text.substr(0, shown)
	return false


func type_msg(i: int, cps: float, voice: String) -> bool:
	if i < 0 or i >= msgs.size():
		return false
	var m: Dictionary = msgs[i]
	return await _type_span(m, "shown", 0, str(m.get("text", "")).length(), cps, voice)


## 开场专用：两句短思考依次出现，然后加速重复直到屏幕外，2.4秒内划掉并交给下一句。
func overflow_thought(first: String, second: String, prefix: String, unit: String) -> void:
	_intro_elapsed = 0.0
	_intro_prefix = prefix
	_intro_unit = unit
	var top := MSG_Y0 + 26.0 + MSG_GAP
	var bottom := get_viewport_rect().size.y - _offset().y
	var units_per_row := maxi(1, floori((CHAT_W - 12.0) / Px.text_w(unit)))
	_intro_repeats = (ceili((bottom - top) / LINE_H) + 3) * units_per_row
	var repeated := prefix + unit.repeat(_intro_repeats)
	think = {"on": true, "lines": [first, second, repeated], "shown": 0, "strike": 0.0, "collapsed": false}
	_thought_full_end = top + LINE_H
	for line in think["lines"]:
		_thought_full_end += Px.wrap(line, CHAT_W - 12.0).size() * LINE_H
	Inp.take_advance()
	_intro_thought_running = true
	while _intro_thought_running:
		await get_tree().process_frame


func _repeat_count_at(progress: float) -> int:
	var u := clampf(progress, 0.0, 1.0)
	return mini(_intro_repeats, floori(_intro_repeats * (exp(4.0 * u) - 1.0) / (exp(4.0) - 1.0) + 0.00001))


func _update_intro_thought(dt: float) -> void:
	if Inp.take_advance():
		if _intro_elapsed < 0.5:
			_intro_elapsed = 0.5
		elif _intro_elapsed < 0.8:
			_intro_elapsed = 0.8
		elif _intro_elapsed < THOUGHT_FILL_END:
			_intro_elapsed = THOUGHT_FILL_END
	_intro_elapsed = minf(THOUGHT_END, _intro_elapsed + dt)
	var first: int = think["lines"][0].length()
	var second: int = think["lines"][1].length()
	if _intro_elapsed < 0.5:
		think["shown"] = mini(first, floori(first * _intro_elapsed / 0.4))
	elif _intro_elapsed < 0.8:
		think["shown"] = first + mini(second, floori(second * (_intro_elapsed - 0.5) / 0.22))
	elif _intro_elapsed < 0.92:
		think["shown"] = first + second + mini(_intro_prefix.length(), floori(_intro_prefix.length() * (_intro_elapsed - 0.8) / 0.12))
	else:
		var count := _repeat_count_at((_intro_elapsed - 0.92) / (THOUGHT_FILL_END - 0.92))
		think["shown"] = first + second + _intro_prefix.length() + count * _intro_unit.length()
	think["strike"] = clampf((_intro_elapsed - THOUGHT_FILL_END) / (THOUGHT_END - THOUGHT_FILL_END), 0.0, 1.0)
	if _intro_elapsed >= THOUGHT_END:
		# 划线完成后收起整段思维链，只保留折叠标题。
		think["collapsed"] = true
		_intro_thought_running = false


## 思考块中的每一行都是独立的一句，一次回车不能跳过后续行。
func type_think(cps: float) -> bool:
	if not bool(think.get("on", false)):
		return false
	var offset := 0
	var advanced := false
	var lines: Array = think.get("lines", [])
	for i in lines.size():
		var count := str(lines[i]).length()
		advanced = await _type_span(think, "shown", offset, count, cps)
		offset += count
		if i < lines.size() - 1:
			await wait_line(0.8, advanced)
	return advanced


func _type_span(target: Dictionary, field: String, offset: int, count: int, cps: float, voice := "") -> bool:
	Inp.take_advance()
	target[field] = offset
	var elapsed := 0.0
	while int(target[field]) < offset + count:
		await get_tree().process_frame
		if Inp.take_advance():
			target[field] = offset + count
			return true
		elapsed += get_process_delta_time()
		var shown := mini(count, int(elapsed * cps))
		if shown + offset > int(target[field]) and voice != "":
			Sfx.play(voice)
		target[field] = offset + shown
	return false


## 当前句的自动停留时间。若打字期间已按回车，不再等待同一句。
func wait_line(seconds: float, advanced := false) -> void:
	if advanced:
		return
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		if Inp.take_advance():
			return
		elapsed += get_process_delta_time()
