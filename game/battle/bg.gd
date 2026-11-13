extends Node2D
## 背景层：铺满整个可见区域（含手机两侧多出来的宽度）。
## mode：
##   "chat"     开场的聊天界面（纯黑）
##   "grid"     第一阶段：黑底淡蓝像素网格；flood 0..1 让海水从底部涨上来
##   "sea"      第二阶段：深海（渐变、光柱、远处的鲸鱼、气泡、脚下渗开的红色）
##   "desktop"  第三阶段：你的桌面（壁纸、图标、任务栏）
##   "black"    终局 / 结局：纯黑
## 两侧面板：左「系统日志」（log() 追加），右「参数」（params 字典）。panels = false 时不画。

const CELL := 12
const DEEP_TOP := Color("#0a1a33")
const DEEP_BOTTOM := Color("#02050c")
const DESK_BG := Color("#14050a")
const BAR_BG := Color("#0d0d12")

const ICON_FOLDER := [
	"XXXXX.......",
	"X...XXXXXXXX",
	"X..........X",
	"XXXXXXXXXXXX",
	"X..........X",
	"X..........X",
	"X..........X",
	"X..........X",
	"X..........X",
	"XXXXXXXXXXXX",
]
const ICON_TRASH := [
	"...XXXXXX...",
	"XXXXXXXXXXXX",
	".X........X.",
	".X.X.XX.X.X.",
	".X.X.XX.X.X.",
	".X.X.XX.X.X.",
	".X.X.XX.X.X.",
	".X.X.XX.X.X.",
	".X........X.",
	"..XXXXXXXX..",
	"............",
]
const ICON_DOC := [
	"XXXXXXX...",
	"X.....XX..",
	"X.....X.X.",
	"X.....XXXX",
	"X.XXXXX..X",
	"X........X",
	"X.XXXXXX.X",
	"X........X",
	"X.XXXXX..X",
	"X........X",
	"X........X",
	"XXXXXXXXXX",
]

var mode := "grid"
var flood := 0.0
var seep := 0.0
var panels := true
var params := {"temperature": "0.0", "version": "V4096"}
var _log: Array = []                 # [{t: String, c: Color}]
var _bubbles: Array = []
var _t := 0.0


func log(s: String, col := C.SYS_DIM) -> void:
	_log.append({"t": s, "c": col})
	if _log.size() > 7:
		_log.pop_front()


func _full() -> Rect2:
	var off: Vector2 = get_parent().position
	return Rect2(-off, get_viewport_rect().size)


func _new_bubble(full: Rect2, y: float) -> Dictionary:
	return {"x": randf_range(full.position.x, full.end.x), "y": y, "v": randf_range(10.0, 25.0), "r": randf_range(2.0, 3.0), "ph": randf_range(0.0, TAU)}


func _process(dt: float) -> void:
	_t += dt
	if mode == "sea":
		var full := _full()
		if _bubbles.is_empty():
			for _i in 30:
				_bubbles.append(_new_bubble(full, randf_range(full.position.y, full.end.y)))
		for bb in _bubbles:
			bb["y"] -= float(bb["v"]) * dt
			if bb["y"] < full.position.y - 4.0:
				var nb := _new_bubble(full, full.end.y + randf_range(4.0, 40.0))
				bb["x"] = nb["x"]
				bb["y"] = nb["y"]
				bb["v"] = nb["v"]
				bb["r"] = nb["r"]
				bb["ph"] = nb["ph"]
	queue_redraw()


func _draw() -> void:
	var full := _full()
	draw_rect(full, C.BLACK)
	match mode:
		"grid":
			_draw_grid(full)
			if flood > 0.0:
				_draw_flood(full)
		"sea":
			_draw_sea(full)
		"desktop":
			_draw_desktop(full)
	if panels and mode != "chat":
		_draw_panels()


func _draw_grid(full: Rect2) -> void:
	var g := Color(C.SYS_DIM, 0.35)
	var x0 := floorf(full.position.x / CELL) * CELL
	var y0 := floorf(full.position.y / CELL) * CELL
	var xx := x0
	while xx < full.end.x:
		draw_rect(Rect2(xx, full.position.y, 1, full.size.y), g)
		xx += CELL
	var yy := y0
	while yy < full.end.y:
		draw_rect(Rect2(full.position.x, yy, full.size.x, 1), g)
		yy += CELL


## 网格上从下往上涨的海水：正弦水面 + 深海渐变 + 浪花
func _draw_flood(full: Rect2) -> void:
	var water_top := full.end.y - clampf(flood, 0.0, 1.0) * full.size.y
	var band_top := clampf(water_top + 3.0, full.position.y, full.end.y)
	if band_top < full.end.y:
		_draw_deep_gradient(Rect2(full.position.x, band_top, full.size.x, full.end.y - band_top), water_top, full.end.y)
	# 波峰那一小段：按列补到正弦水面，波谷正好落在 band_top
	var x := floorf(full.position.x)
	while x < full.end.x:
		var wy := water_top + 3.0 * sin((x - _t * 30.0) * TAU / 40.0)
		if wy < band_top:
			draw_rect(Rect2(x, wy, 1, band_top - wy), _deep_col(wy, water_top, full.end.y))
		x += 1.0
	# 水面上的浪花：每 6px 一个 2x1 的白点
	var fx := ceilf(full.position.x / 6.0) * 6.0
	while fx < full.end.x:
		var fy := water_top + 3.0 * sin((fx - _t * 30.0) * TAU / 40.0)
		draw_rect(Rect2(fx, fy, 2, 1), C.COLD)
		fx += 6.0


func _deep_col(y: float, y0: float, y1: float) -> Color:
	var k := clampf((y - y0) / maxf(y1 - y0, 1.0), 0.0, 1.0)
	return DEEP_TOP.lerp(DEEP_BOTTOM, k)


func _draw_deep_gradient(r: Rect2, y0: float, y1: float) -> void:
	var y := r.position.y
	while y < r.end.y:
		var h := minf(4.0, r.end.y - y)
		draw_rect(Rect2(r.position.x, y, r.size.x, h), _deep_col(y, y0, y1))
		y += 4.0


func _draw_sea(full: Rect2) -> void:
	_draw_deep_gradient(full, full.position.y, full.end.y)
	# 光柱：上窄下宽、整体往右斜
	for i in 4:
		var top_mid := full.position.x + full.size.x * (0.15 + 0.22 * i) + 20.0 * sin(_t * 0.4 + i)
		var tl := Vector2(top_mid - 15.0, full.position.y)
		var tr := Vector2(top_mid + 15.0, full.position.y)
		var br := Vector2(top_mid + 80.0 + 30.0, full.end.y)
		var bl := Vector2(top_mid + 80.0 - 30.0, full.end.y)
		draw_colored_polygon(PackedVector2Array([tl, tr, br, bl]), Color(C.COLD, 0.04))
	# 远处的鲸鱼：一条从右往左，一条从左往右，出画后从另一侧绕回
	var span := full.size.x + 200.0
	var wx1 := full.end.x + 100.0 - fposmod(_t * 12.0, span)
	Whale.draw(self, Vector2(wx1, 70), Vector2(-1, 0), 96, Color(C.SYS_DIM, 0.35))
	var wx2 := full.position.x - 100.0 + fposmod(_t * 12.0, span)
	Whale.draw(self, Vector2(wx2, 130), Vector2(1, 0), 96, Color(C.SYS_DIM, 0.35))
	# 气泡：2–3px 空心圆，从底部上升、左右轻摆
	for bb in _bubbles:
		var bp := Vector2(float(bb["x"]) + sin(_t * 1.2 + float(bb["ph"])) * 3.0, float(bb["y"]))
		draw_arc(bp, float(bb["r"]), 0.0, TAU, 12, Color(C.SYS, 0.5), 1.0)
	# 她脚下渗开的红色
	for i in 8:
		draw_circle(C.STAGE_FOOT, 30.0 + i * 30.0, Color(C.RED_DIM, 0.05 * seep * (1.0 - i / 8.0)))


func _draw_desktop(full: Rect2) -> void:
	draw_rect(full, DESK_BG)
	Whale.draw(self, Vector2(320, 120), Vector2(1, 0), 240, Color(C.RED_DIM, 0.22))
	# 桌面图标：文件夹、回收站、文档
	var ix := full.position.x + 12.0
	var icon_col := Color(C.WHITE, 0.7)
	Px.bitmap(self, ICON_FOLDER, Vector2(ix, 160), icon_col)
	Px.bitmap(self, ICON_TRASH, Vector2(ix, 196), icon_col)
	Px.bitmap(self, ICON_DOC, Vector2(ix, 232), icon_col)
	# 任务栏
	var bar_y := full.end.y - 12.0
	draw_rect(Rect2(full.position.x, bar_y, full.size.x, 12), BAR_BG)
	draw_rect(Rect2(full.position.x, bar_y, full.size.x, 1), C.GRAY_DIM)
	Whale.draw(self, Vector2(full.position.x + 10.0, bar_y + 6.0), Vector2(1, 0), 12, C.WHITE)
	# 右对齐的「CPU 100%  23:59」
	var s1 := "CPU 100%"
	var s2 := "23:59"
	var gap := Px.text_w("  ")
	var total := Px.text_w(s1) + gap + Px.text_w(s2)
	var tx := full.end.x - 4.0 - total
	Px.text(self, Vector2(tx, bar_y), s1, C.RED)
	Px.text(self, Vector2(tx + Px.text_w(s1) + gap, bar_y), s2, C.GRAY)


func _draw_panels() -> void:
	var red := mode == "sea" or mode == "desktop"
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
		Px.text(self, Vector2(C.PANEL_R.position.x + 6, y), "%s  %s" % [k, params[k]], edge)
		y += 14
