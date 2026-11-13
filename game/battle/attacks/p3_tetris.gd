extends Attack
## P3-2「上下文压缩」
##
## 弹幕框变成 10×12 的俄罗斯方块竖井（每格 12px）。方块按固定表踩着拍子一块块往下掉，
## 蓝心要跳到落地的方块堆上躲开正在掉的方块；一行填满就闪一下消掉，最后整堆一起炸开。
## - 方块只直落、不左右移、不转，落点和消行全部在 setup() 里按顺序模拟好；
##   运行时位置只由 t 算出来（一格一格跳，不平滑移动）。
## - 落地的格子每帧放进 battle.soul.solids（12×12 完整格），蓝心能站上去、会被挡住。
## - 正在下落的格子才伤人（10×10）；落地那一帧也算「正在下落」，之后变成地面。
## - mirror = true：列号与拼块形状同时水平镜像。

const COLS := 10
const ROWS := 12
const CELL := 12.0
const FALL_STEP := 0.125                   # 每 0.125 拍往下跳一整行
const CLEAR_FLASH := 0.25                  # 消行闪烁时长
const FLASH_STEP := 0.0625                 # 闪烁交替间隔
const SHATTER_AT := 16.5                   # 剩下的方块开始闪
const SHATTER_BOOM := 16.75                # 闪完炸开
const FINAL_TEXT := "上下文已全部压缩"
const CLEAR_TEXT := "上下文已压缩"

## 形状：格子偏移 (x, y)，y 朝下
const SHAPES := {
	"I_H": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	"I_V": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)],
	"T": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	"S": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"Z": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
	"O": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"J_H": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	"L_H": [Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
}

## 出场表：[出场拍, 形状, 最左一格所在列]
const SPAWN := [
	[1.0, "I_H", 0], [2.0, "I_H", 4], [3.0, "O", 8],
	[4.0, "T", 3], [5.0, "S", 6], [6.0, "Z", 4],
	[7.0, "J_H", 0], [8.0, "L_H", 1], [9.0, "I_V", 9],
	[10.0, "O", 7], [11.0, "T", 3], [12.0, "S", 7],
	[13.0, "Z", 4], [14.0, "I_H", 0],
]

var _pieces: Array = []
var _frames: Array = []
var _clear_events: Array = []
var _shatter_cells: Array = []


func setup() -> void:
	duration = 18.0
	box_size = Vector2(120, 144)
	soul_mode = "blue"
	stop_beat = 9.0
	_pieces.clear()
	_frames.clear()
	_clear_events.clear()
	_shatter_cells.clear()
	for item in SPAWN:
		var width := 0
		for o in SHAPES[item[1]]:
			width = maxi(width, o.x + 1)
		var shape: Array[Vector2i] = []
		for o in SHAPES[item[1]]:
			shape.append(Vector2i(width - 1 - o.x, o.y) if mirror else o)
		var col: int = COLS - item[2] - width if mirror else item[2]
		_pieces.append({"index": _pieces.size(), "beat": item[0], "kind": item[1], "col": col,
			"top": -4, "land": INF, "cells": [], "shape": shape})
	_simulate()


func _cells(p: Dictionary, top: int) -> Array:
	var cells: Array = []
	for o in p["shape"]:
		cells.append(Vector2i(p["col"] + o.x, top + o.y))
	return cells


func _full_rows(board: Dictionary) -> Array[int]:
	var rows: Array[int] = []
	for y in ROWS:
		var full := true
		for x in COLS:
			if not board.has(Vector2i(x, y)):
				full = false
				break
		if full:
			rows.append(y)
	return rows


## 一次同时移除所有满行，上方格子按实际移除行数下移。
func _clear_board(board: Dictionary, rows: Array[int]) -> Dictionary:
	var shifted := {}
	for cell in board:
		if rows.has(cell.y):
			continue
		var drop := 0
		for row in rows:
			if row > cell.y:
				drop += 1
		shifted[Vector2i(cell.x, cell.y + drop)] = board[cell]
	return shifted


## 按真实时间预模拟：下落物互相阻挡时先等待，落地及延迟消行后再更新地面。
func _simulate() -> void:
	var board := {}
	var clear_at := INF
	for step in int(SHATTER_BOOM / FALL_STEP):
		var now := step * FALL_STEP
		if now >= clear_at:
			var rows := _full_rows(board)
			board = _clear_board(board, rows)
			_clear_events.append({"at": now, "rows": rows})
			clear_at = INF
		for p in _pieces:
			if now <= p["beat"] or p["land"] < INF:
				continue
			var want := _cells(p, p["top"] + 1)
			var blocked := false
			for cell in want:
				if cell.y >= ROWS or board.has(cell):
					blocked = true
					break
			if not blocked:
				var waiting := false
				for other in _pieces:
					if other == p or now < other["beat"] or other["land"] < INF:
						continue
					for cell in _cells(other, other["top"]):
						if want.has(cell):
							waiting = true
				if not waiting:
					p["top"] += 1
				continue
			p["land"] = now
			p["cells"] = _cells(p, p["top"])
			for cell in p["cells"]:
				assert(cell.y >= 0 and cell.y < ROWS, "方块不能堆出井顶")
				board[cell] = p["index"]
			if not _full_rows(board).is_empty() and clear_at == INF:
				clear_at = now + CLEAR_FLASH
		var tops: Array[int] = []
		for p in _pieces:
			tops.append(p["top"])
		_frames.append({"board": board.duplicate(), "tops": tops, "flash": _full_rows(board)})
	for p in _pieces:
		assert(p["land"] < SHATTER_AT, "所有方块必须在全清前落地")
	_shatter_cells = board.keys()


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(box.position + Vector2(cell.x, cell.y) * CELL, Vector2(CELL, CELL))


func _frame_at(now: float) -> Dictionary:
	return _frames[clampi(floori(now / FALL_STEP + 0.000001), 0, _frames.size() - 1)]


func _fall_top(p: Dictionary, now: float) -> int:
	return _frame_at(now)["tops"][p["index"]]


func _board_at(now: float) -> Dictionary:
	return {} if now >= SHATTER_BOOM else _frame_at(now)["board"]


func _flash_row(now: float) -> Array:
	var col := C.WHITE if floori(now / FLASH_STEP) % 2 == 0 else C.SYS
	return [_frame_at(now)["flash"], col]


# ── 每帧 ──────────────────────────────────────────────────────

func tick(_dt: float) -> void:
	if crossed(0.0):
		pose("summon")
	for i in _pieces.size():
		var p: Dictionary = _pieces[i]
		if crossed(p["land"]):
			sfx("brick")
			if battle:
				battle.shake(1.0)
	for event in _clear_events:
		if crossed(event["at"]):
			sfx("delete")
			if battle:
				battle.shake(2.0)
	if crossed(SHATTER_BOOM):
		sfx("shatter")
		if battle:
			battle.shake(3.0)
	# 下落中的格子伤人（落地那一帧也算，之后就是地面了）
	for p in _pieces:
		if t >= p["beat"] and t < p["land"]:
			var top := _fall_top(p, t)
			for o in p["shape"]:
				hz_rect(_cell_rect(Vector2i(p["col"] + o.x, top + o.y)).grow(-1))
		elif crossed(p["land"]):
			for cell in p["cells"]:
				hz_rect(_cell_rect(cell).grow(-1))
	# 已落地的格子变成蓝心能站的地面
	if battle:
		battle.soul.solids.clear()
		var board := _board_at(t)
		for cell in board:
			battle.soul.solids.append(_cell_rect(cell))


# ── 画 ────────────────────────────────────────────────────────

## 所有形状统一使用 10×10 方格和 4×4 黑孔。
func _draw_cell(cell: Vector2i, _kind: String, col: Color) -> void:
	var r := _cell_rect(cell)
	var b := Rect2((r.position + Vector2.ONE).round(), Vector2(10, 10))
	draw_rect(b, col)
	draw_rect(Rect2(b.position + Vector2(3, 3), Vector2(4, 4)), C.BLACK)


func _draw() -> void:
	var now := t
	var board := _board_at(now)
	# 落点预告：出场前 0.5 拍到落地
	for p in _pieces:
		if now >= p["beat"] - 0.5 and now < p["land"]:
			for cell in p["cells"]:
				Px.dashed(self, _cell_rect(cell).grow(-1), C.SYS, now * 12.0)
	# 已落地的方块（消行 / 全清时闪）
	var fr := _flash_row(now)
	var final_flash := now >= SHATTER_AT and now < SHATTER_BOOM
	var final_col := C.WHITE
	if final_flash:
		final_col = C.WHITE if floori((now - SHATTER_AT) / FLASH_STEP) % 2 == 0 else C.SYS
	for cell in board:
		var kind: String = _pieces[board[cell]]["kind"]
		var col := C.WHITE
		if final_flash:
			col = final_col
		elif (fr[0] as Array).has(cell.y):
			col = fr[1]
		_draw_cell(cell, kind, col)
	# 正在下落的方块
	for p in _pieces:
		if now < p["beat"] or now >= p["land"]:
			continue
		var top := _fall_top(p, now)
		for o in p["shape"]:
			_draw_cell(Vector2i(p["col"] + o.x, top + o.y), p["kind"], C.WHITE)
	# 全清：每格 4 个 2×2 白碎块往四个斜方向飞 10px，0.5 拍淡出
	if now >= SHATTER_BOOM and now < SHATTER_BOOM + 0.5:
		var u := (now - SHATTER_BOOM) / 0.5
		var a := 1.0 - u
		var dirs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for cell in _shatter_cells:
			var c := _cell_rect(cell).get_center()
			for d in dirs:
				var p: Vector2 = c + d.normalized() * 10.0 * u
				draw_rect(Rect2(p.round() - Vector2.ONE, Vector2(2, 2)), Color(C.WHITE, a))
	# 消行提示：框顶居中 1 拍
	for event in _clear_events:
		if now >= event["at"] and now < event["at"] + 1.0:
			var w := Px.text_w(CLEAR_TEXT)
			Px.text(self, Vector2(box.get_center().x - w / 2.0, box.position.y + 2.0), CLEAR_TEXT, C.SYS)
	# 全清提示：框中间 1.5 拍
	if now >= SHATTER_AT and now < SHATTER_AT + 1.5:
		var w := Px.text_w(FINAL_TEXT)
		Px.text(self, box.get_center() - Vector2(w / 2.0, 6.0), FINAL_TEXT, C.WHITE)

