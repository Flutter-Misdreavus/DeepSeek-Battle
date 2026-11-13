extends Attack
## P3-2「上下文压缩」
##
## 弹幕框变成 10×12 的俄罗斯方块竖井（每格 12px）。方块按固定表踩着拍子一块块往下掉，
## 蓝心要跳到落地的方块堆上躲开正在掉的方块；一行填满就闪一下消掉，最后整堆一起炸开。
## - 方块只直落、不左右移、不转，落点和消行全部在 setup() 里按顺序模拟好；
##   运行时位置只由 t 算出来（一格一格跳，不平滑移动）。
## - 落地的格子每帧放进 battle.soul.solids（12×12 完整格），蓝心能站上去、会被挡住。
## - 正在下落的格子才伤人（10×10）；落地那一帧也算「正在下落」，之后变成地面。
## - mirror = true：列号镜像（新列 = 10 - 列 - 方块宽）。

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
	"O": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"J_H": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	"L_H": [Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
}

## 出场表：[出场拍, 形状, 最左一格所在列]
const SPAWN := [
	[1.0, "I_H", 0],
	[2.5, "I_H", 6],
	[4.0, "O", 4],
	[5.5, "J_H", 0],
	[7.0, "L_H", 7],
	[8.5, "I_V", 3],
	[10.0, "I_V", 6],
	[11.5, "O", 1],
	[13.0, "O", 4],
	[14.5, "O", 7],
]

# 每块：beat 出场拍 / kind 形状 / col 最左列 / cells 落地格（自己的消行之前）/
#       land 落地拍 / clear_row 这块落地后填满的行（-1 = 没有）/ clear_at 这行消失的拍
var _pieces: Array = []
var _shatter_cells: Array = []             # 最后炸开的格子（setup 里算好）


func setup() -> void:
	duration = 18.0
	box_size = Vector2(120, 144)
	soul_mode = "blue"
	stop_beat = 9.0
	var board := {}                        # Vector2i -> 第几块
	for item in SPAWN:
		var beat: float = item[0]
		var kind: String = item[1]
		var col: int = item[2]
		var shape: Array = SHAPES[kind]
		var width := 0
		for o in shape:
			width = maxi(width, o.x + 1)
		if mirror:
			col = COLS - col - width
		# 从顶上第 -3 行往下直落，碰到井底或已有方块就停
		var top := -3
		while true:
			var nxt := top + 1
			var ok := true
			for o in shape:
				var c: int = col + o.x
				var r: int = nxt + o.y
				if c < 0 or c >= COLS or r >= ROWS:
					ok = false
					break
				if r >= 0 and board.has(Vector2i(c, r)):
					ok = false
					break
			if not ok:
				break
			top = nxt
		var land := beat + (top + 3) * FALL_STEP
		var cells := []
		for o in shape:
			var cell := Vector2i(col + o.x, top + o.y)
			cells.append(cell)
			if cell.y >= 0:
				board[cell] = _pieces.size()
		# 这块落地后有没有填满的行（本表最多一行；有就立刻在模拟里消掉，给下一块用）
		var clear_row := -1
		for r in range(ROWS - 1, -1, -1):
			var full := true
			for c in COLS:
				if not board.has(Vector2i(c, r)):
					full = false
					break
			if full:
				clear_row = r
				break
		var clear_at := -1.0
		if clear_row >= 0:
			clear_at = land + CLEAR_FLASH
			var shifted := {}
			for cell in board:
				if cell.y == clear_row:
					continue
				var nc: Vector2i = cell if cell.y > clear_row else Vector2i(cell.x, cell.y + 1)
				shifted[nc] = board[cell]
			board = shifted
		_pieces.append({
			"beat": beat, "kind": kind, "col": col, "cells": cells, "top": top,
			"land": land, "clear_row": clear_row, "clear_at": clear_at,
		})
	for cell in board:
		_shatter_cells.append(cell)


func begin() -> void:
	pass


# ── 坐标 / 时间 ──────────────────────────────────────────────

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(box.position + Vector2(cell.x, cell.y) * CELL, Vector2(CELL, CELL))


## 下落中的方块当前最上面一行（一格一格跳，落地后夹住）
func _fall_top(p: Dictionary, now: float) -> int:
	var rows := floori((now - p["beat"]) / FALL_STEP)
	return mini(-3 + rows, p["top"])


## 拍 now 的场地：Vector2i -> 第几块。把已落地的块按顺序摆好，再按时间消行。
func _board_at(now: float) -> Dictionary:
	var board := {}
	if now >= SHATTER_BOOM:
		return board
	for i in _pieces.size():
		var p: Dictionary = _pieces[i]
		if now >= p["land"]:
			for cell in p["cells"]:
				if cell.y >= 0:
					board[cell] = i
		var cr: int = p["clear_row"]
		if cr >= 0 and now >= p["clear_at"]:
			var shifted := {}
			for cell in board:
				if cell.y == cr:
					continue
				var nc: Vector2i = cell if cell.y > cr else Vector2i(cell.x, cell.y + 1)
				shifted[nc] = board[cell]
			board = shifted
	return board


## 正在闪的那一行（没有 = -1）和它这一刻的颜色
func _flash_row(now: float) -> Array:
	for p in _pieces:
		if p["clear_row"] >= 0 and now >= p["land"] and now < p["clear_at"]:
			var col := C.WHITE if floori((now - p["land"]) / FLASH_STEP) % 2 == 0 else C.SYS
			return [p["clear_row"], col]
	return [-1, C.WHITE]


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
		if p["clear_row"] >= 0 and crossed(p["clear_at"]):
			sfx("delete")
			if battle:
				battle.shake(2.0)
	if crossed(SHATTER_BOOM):
		sfx("shatter")
		if battle:
			battle.shake(3.0)
	# 下落中的格子伤人（落地那一帧也算，之后就是地面了）
	for p in _pieces:
		if t < p["land"]:
			var top := _fall_top(p, t)
			for o in SHAPES[p["kind"]]:
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

## 普通格：10×10 白块 + 中间 4×4 黑孔；I 形四格画成小鲸鱼
func _draw_cell(cell: Vector2i, kind: String, col: Color) -> void:
	var r := _cell_rect(cell)
	if kind == "I_H" or kind == "I_V":
		var dir := Vector2.RIGHT if kind == "I_H" else Vector2.DOWN
		Whale.draw(self, r.get_center(), dir, 12, col)
		return
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
		elif cell.y == fr[0]:
			col = fr[1]
		_draw_cell(cell, kind, col)
	# 正在下落的方块
	for p in _pieces:
		if now < p["beat"] or now >= p["land"]:
			continue
		var top := _fall_top(p, now)
		for o in SHAPES[p["kind"]]:
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
	for p in _pieces:
		if p["clear_row"] >= 0 and now >= p["clear_at"] and now < p["clear_at"] + 1.0:
			var w := Px.text_w(CLEAR_TEXT)
			Px.text(self, Vector2(box.get_center().x - w / 2.0, box.position.y + 2.0), CLEAR_TEXT, C.SYS)
	# 全清提示：框中间 1.5 拍
	if now >= SHATTER_AT and now < SHATTER_AT + 1.5:
		var w := Px.text_w(FINAL_TEXT)
		Px.text(self, box.get_center() - Vector2(w / 2.0, 6.0), FINAL_TEXT, C.WHITE)

