extends Node2D
## 过场专用绘制节点：聊天界面（mode = "chat"）、结束卡（mode = "card"）、
## 鲸落（mode = "fall"）、鲸鱼送行（mode = "escort"）。
## 由 cutscenes.gd 创建并 add_child 到 battle 上，插在 overlay 下面、标题栏下面，用完 queue_free()。

const CHAT_X := 120.0
const CHAT_W := 380.0
const LINE_H := 14.0
const MSG_Y0 := 70.0
const MSG_GAP := 10.0

var battle: Node

var mode := "chat"

# ── chat ────────────────────────────────────────────────────
var input_text := ""
var caret := false
var msgs: Array = []                  # {who, text, shown, col}
var think := {"on": false, "lines": [], "shown": 0}
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
			y = _draw_her_msg(m, y)
		if not think_done and str(m.get("who", "her")) == "her":
			y += MSG_GAP
			y = _draw_think(y)
			think_done = true
		y += MSG_GAP
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
	var title_line := "▶ 已深度思考（用时 0.3 秒）"
	Px.text(self, Vector2(CHAT_X, y), title_line, C.GRAY)
	_rows.append({"y": y, "h": LINE_H, "text": title_line, "x": CHAT_X, "col": C.GRAY})
	var arr: Array = think.get("lines", [])
	var n := arr.size()
	var budget := int(think.get("shown", 0))
	if n > 0:
		draw_rect(Rect2(122, y + LINE_H, 1, n * LINE_H), C.GRAY_DIM)
	var ty := y + LINE_H
	for line in arr:
		var s := str(line)
		if budget > 0:
			var vis := s.substr(0, budget)
			Px.text(self, Vector2(CHAT_X + 12, ty), vis, C.GRAY)
			if vis != "":
				_rows.append({"y": ty, "h": LINE_H, "text": vis, "x": CHAT_X + 12, "col": C.GRAY})
			budget -= s.length()
		ty += LINE_H
	return y + LINE_H + n * LINE_H


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

## 逐字打出第 i 条消息（每字一声 voice）
func type_msg(i: int, cps: float, voice: String) -> void:
	if i < 0 or i >= msgs.size():
		return
	var m: Dictionary = msgs[i]
	var text := str(m.get("text", ""))
	var total := text.length()
	m["shown"] = 0
	var wait_s := 1.0 / maxf(cps, 0.001)
	for n in total:
		m["shown"] = n + 1
		Sfx.play(voice)
		await _wait(wait_s)


## 逐字打出思考块（不用声音）
func type_think(cps: float) -> void:
	if not bool(think.get("on", false)):
		return
	var arr: Array = think.get("lines", [])
	var total := 0
	for line in arr:
		total += str(line).length()
	think["shown"] = 0
	var wait_s := 1.0 / maxf(cps, 0.001)
	for n in total:
		think["shown"] = n + 1
		await _wait(wait_s)


func _wait(sec: float) -> void:
	if battle != null:
		await battle.wait(sec)
	else:
		await get_tree().create_timer(sec, false).timeout
