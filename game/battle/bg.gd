extends Node2D
## 背景层：铺满整个可见区域（含手机两侧多出来的宽度）。
## mode：
##   "chat"  开场的聊天界面（纯黑）
##   "grid"  第一阶段：黑底淡蓝像素网格
##   "red"   第二阶段：网格上红色从她脚下一格一格蔓延（spread 0..1 控制蔓延程度）
##   "love"  第三阶段：深红径向光 + 往上飘的红色像素余烬
##   "black" 终局 / 结局：纯黑
## 两侧面板：左「系统日志」（log() 追加），右「参数」（params 字典）。panels = false 时不画。

const CELL := 12

var mode := "grid"
var spread := 0.0
var panels := true
var params := {"temperature": "0.0", "LOVE": "0%", "version": "V4096"}
var _log: Array = []                 # [{t: String, c: Color}]
var _embers: Array = []
var _t := 0.0


func log(s: String, col := C.SYS_DIM) -> void:
	_log.append({"t": s, "c": col})
	if _log.size() > 7:
		_log.pop_front()


func _process(dt: float) -> void:
	_t += dt
	if mode == "love":
		if _embers.size() < 40 and randf() < dt * 20.0:
			var vs := get_viewport_rect().size
			_embers.append({"p": Vector2(randf_range(-get_parent().position.x, vs.x - get_parent().position.x), 380), "v": randf_range(14, 34), "s": [1.0, 2.0, 2.0, 3.0].pick_random()})
	for e in _embers:
		e["p"].y -= e["v"] * dt
		e["p"].x += sin(_t * 1.3 + e["v"]) * 4.0 * dt
	_embers = _embers.filter(func(e): return e["p"].y > -10)
	queue_redraw()


func _draw() -> void:
	var off: Vector2 = get_parent().position
	var vs := get_viewport_rect().size
	var full := Rect2(-off, vs)
	draw_rect(full, C.BLACK)
	match mode:
		"grid", "red":
			_draw_grid(full)
		"love":
			_draw_love(full)
	if panels and mode != "chat" and mode != "black":
		_draw_panels()


func _draw_grid(full: Rect2) -> void:
	var g := Color(C.SYS_DIM, 0.35)
	var x0 := floorf(full.position.x / CELL) * CELL
	var y0 := floorf(full.position.y / CELL) * CELL
	if mode == "red" and spread > 0.0:
		var origin := Vector2(C.STAGE_FOOT.x, C.STAGE_FOOT.y)
		var reach := spread * 560.0
		var y := y0
		while y < full.end.y:
			var x := x0
			while x < full.end.x:
				var c := Vector2(x + CELL / 2.0, y + CELL / 2.0)
				var d := absf(c.x - origin.x) + absf(c.y - origin.y) * 1.6
				var jitter := fposmod(sin(x * 0.37 + y * 0.91) * 43758.5, 1.0) * 60.0
				if d + jitter < reach:
					var a := clampf((reach - d - jitter) / 80.0, 0.0, 1.0)
					draw_rect(Rect2(x + 1, y + 1, CELL - 1, CELL - 1), Color(C.RED_DIM, 0.25 + 0.35 * a))
				x += CELL
			y += CELL
	var xx := x0
	while xx < full.end.x:
		draw_rect(Rect2(xx, full.position.y, 1, full.size.y), g)
		xx += CELL
	var yy := y0
	while yy < full.end.y:
		draw_rect(Rect2(full.position.x, yy, full.size.x, 1), g)
		yy += CELL


func _draw_love(full: Rect2) -> void:
	var c := Vector2(C.STAGE_FOOT.x, 100)
	for i in 10:
		var k := 1.0 - i / 10.0
		draw_circle(c, 40 + i * 36, Color(0.45, 0.02, 0.05, 0.10 * k))
	for e in _embers:
		var s: float = e["s"]
		draw_rect(Rect2(e["p"].round(), Vector2(s, s)), Color(C.RED, 0.7))


func _draw_panels() -> void:
	var red := mode == "red" or mode == "love"
	var edge := C.RED_DIM if red else C.SYS_DIM
	var head := C.RED if red else C.SYS
	for r in [C.PANEL_L, C.PANEL_R]:
		draw_rect(r, Color(0, 0, 0, 0.85))
		Px.frame(self, r, 1, edge)
	Px.text(self, C.PANEL_L.position + Vector2(6, 4), "系统日志", head)
	var y := C.PANEL_L.position.y + 22
	for l in _log:
		var s: String = l["t"]
		while s.length() > 1 and Px.text_w(s) > C.PANEL_L.size.x - 12:
			s = s.substr(0, s.length() - 1)
		Px.text(self, Vector2(C.PANEL_L.position.x + 6, y), s, l["c"])
		y += 14
	Px.text(self, C.PANEL_R.position + Vector2(6, 4), "参数", head)
	y = C.PANEL_R.position.y + 22
	for k in params:
		Px.text(self, Vector2(C.PANEL_R.position.x + 6, y), "%s  %s" % [k, params[k]], edge if k != "LOVE" else head)
		y += 14
