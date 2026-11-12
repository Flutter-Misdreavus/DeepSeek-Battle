extends Attack
## P2-3「红色蔓延」
##
## 框被分成 12×8 的格子，红色从左上角一格一格蔓延（像系统后台被写入一样）。
## 右下角始终留出一块没被染红的安全区；随后蓝色修复把红色推回去，第二波又从右下角反扑。
## - 第一波：s = i + j，红色窗口 [0.5s + 0.5, 15 - 0.5s)，只有 s <= 14 的格子会红。
## - 第二波：s2 = (11 - i) + (7 - j)，红色窗口 [10 + 0.5s2, 16 - 0.25s2)，只有 s2 <= 7 的格子会红。
## - 每格红之前 0.5 拍有暗红预警，红结束 0.3 拍内有蓝色修复闪光。

const COLS := 12
const ROWS := 8
const CELL := 16.0

var _last_half := -1


func setup() -> void:
	duration = 17.0
	box_size = Vector2(COLS * CELL, ROWS * CELL)
	stop_beat = 4.0


func begin() -> void:
	pose("twirl")


## 第 (i, j) 格；mirror 时列号翻成 11 - i
func _cell(i: int, j: int) -> Rect2:
	var ci := 11 - i if mirror else i
	return Rect2(
		box.position.x + CELL * ci,
		box.position.y + CELL * j,
		CELL,
		CELL
	)


func _w1_start(i: int, j: int) -> float:
	return 0.5 * (i + j) + 0.5


func _w1_end(i: int, j: int) -> float:
	return 15.0 - 0.5 * (i + j)


func _w2_start(i: int, j: int) -> float:
	return 10.0 + 0.5 * ((11 - i) + (7 - j))


func _w2_end(i: int, j: int) -> float:
	return 16.0 - 0.25 * ((11 - i) + (7 - j))


func _red1(i: int, j: int) -> bool:
	return i + j <= 14 and t >= _w1_start(i, j) and t < _w1_end(i, j)


func _red2(i: int, j: int) -> bool:
	return (11 - i) + (7 - j) <= 7 and t >= _w2_start(i, j) and t < _w2_end(i, j)


func _warn1(i: int, j: int) -> bool:
	return i + j <= 14 and t >= _w1_start(i, j) - 0.5 and t < _w1_start(i, j)


func _warn2(i: int, j: int) -> bool:
	return (11 - i) + (7 - j) <= 7 and t >= _w2_start(i, j) - 0.5 and t < _w2_start(i, j)


func _heal1(i: int, j: int) -> bool:
	return i + j <= 14 and t >= _w1_end(i, j) and t < _w1_end(i, j) + 0.3


func _heal2(i: int, j: int) -> bool:
	return (11 - i) + (7 - j) <= 7 and t >= _w2_end(i, j) and t < _w2_end(i, j) + 0.3


func tick(_dt: float) -> void:
	if crossed(4.0):
		pose("A_red")
	for i in COLS:
		for j in ROWS:
			if _red1(i, j) or _red2(i, j):
				var c := _cell(i, j)
				hz_rect(Rect2(c.position + Vector2(2, 2), Vector2(12, 12)))
	# 每半个拍子一声「蔓延」，只在两段红色推进的区间里
	var half := floori(t * 2.0)
	if half != _last_half:
		_last_half = half
		var hb := half * 0.5
		if (hb >= 0.5 and hb <= 7.5) or (hb >= 10.0 and hb <= 13.5):
			sfx("spread")


func _draw() -> void:
	# 先画格线，再画格子（最右/最下的边界收进框内 1px，否则会被裁掉）
	var line_col := Color(C.SYS_DIM, 0.4)
	for i in COLS + 1:
		var x := box.position.x + CELL * i
		if i == COLS:
			x = box.end.x - 1.0
		draw_rect(Rect2(x, box.position.y, 1, box.size.y), line_col)
	for j in ROWS + 1:
		var y := box.position.y + CELL * j
		if j == ROWS:
			y = box.end.y - 1.0
		draw_rect(Rect2(box.position.x, y, box.size.x, 1), line_col)
	for i in COLS:
		for j in ROWS:
			var c := _cell(i, j)
			var inner := Rect2((c.position + Vector2(1, 1)).round(), Vector2(14, 14))
			if _red1(i, j) or _red2(i, j):
				draw_rect(inner, Color(C.RED, 0.85))
			elif _warn1(i, j) or _warn2(i, j):
				draw_rect(inner, Color(C.RED_DIM, 0.9))
			elif _heal1(i, j) or _heal2(i, j):
				draw_rect(inner, Color(C.SYS, 0.6))
