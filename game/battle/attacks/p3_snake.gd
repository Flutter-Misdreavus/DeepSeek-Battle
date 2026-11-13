extends Attack
## P3-1「上下文溢出」
##
## 经典像素贪吃蛇：蛇的长度就是上下文长度。它追着红心走、越来越长，长到 16 节就溢出、
## 一分为二（后 8 节倒过来成为新的蛇）。蛇头撞墙、撞到别的蛇的身子都会死；把蛇头引去
## 撞另一条蛇，就能提前清空上下文。
## - 网格 10px，25×15；蛇只在每一步选方向时看墙和自己的身子，看不见别的蛇。
## - 第 1 拍开始每 0.25 拍走一步，每 2 步长一节。位置依赖玩家输入，所以逐帧模拟，
##   但每一步都按固定节拍补足（暂停 / 倍速不会漏步）。
## - 所有随机量都不需要；死亡碎块和溢出提示只是短命特效。
## - mirror 不支持（忽略）。

const CELL := 10
const COLS := 25
const ROWS := 15
const STEP_BEAT := 0.25
const START_BEAT := 1.0
const MAX_LEN := 16
const GROW_EVERY := 2
const HALF := 8
const MAX_SNAKES := 4

var _snakes: Array = []              # {cells: Array[Vector2i], dir: Vector2i, alive: bool, warn: int, no_split: bool}
var _steps_done := 0
var _shards: Array = []              # {p: Vector2, d: Vector2, born: float}
var _sim_t := START_BEAT             # 当前正在模拟的那一步的拍数
var _overflow_at := -1.0
var _cleared_at := -1.0
var _begun := false


func setup() -> void:
	duration = 20.0
	box_size = Vector2(250, 150)
	stop_beat = 10.0
	_snakes = [_new_snake([
		Vector2i(3, 1), Vector2i(2, 1), Vector2i(1, 1), Vector2i(0, 1),
	], Vector2i(1, 0))]


func _new_snake(cells: Array, d: Vector2i) -> Dictionary:
	return {"cells": cells, "dir": d, "alive": true, "warn": 0, "no_split": false}


func _alive_count() -> int:
	var n := 0
	for s in _snakes:
		if s["alive"]:
			n += 1
	return n


# ── 网格 / 坐标 ──────────────────────────────────────────────

func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(box.position + Vector2(c) * CELL, Vector2(CELL, CELL))


func _cell_center(c: Vector2i) -> Vector2:
	return box.position + Vector2(c) * CELL + Vector2(CELL, CELL) * 0.5


func _heart_cell() -> Vector2i:
	var p := soul_pos() - box.position
	return Vector2i(
		clampi(floori(p.x / CELL), 0, COLS - 1),
		clampi(floori(p.y / CELL), 0, ROWS - 1)
	)


# ── 每一步 ──────────────────────────────────────────────────

## 选方向：当前 > 左转 > 右转；有效候选里挑到红心曼哈顿距离最近的。
func _choose_dir(s: Dictionary, grow: bool) -> Vector2i:
	var cells: Array = s["cells"]
	var d: Vector2i = s["dir"]
	var cands := [d, Vector2i(d.y, -d.x), Vector2i(-d.y, d.x)]
	var hc := _heart_cell()
	var best := d
	var best_d := 1 << 30
	var found := false
	for c in cands:
		var n: Vector2i = cells[0] + c
		if n.x < 0 or n.x >= COLS or n.y < 0 or n.y >= ROWS:
			continue
		# 自己的身子；不长的这一步尾巴会让出来
		var end_i: int = cells.size() - (0 if grow else 1)
		var blocked := false
		for i in range(1, end_i):
			if cells[i] == n:
				blocked = true
				break
		if blocked:
			continue
		var dist: int = absi(n.x - hc.x) + absi(n.y - hc.y)
		if not found or dist < best_d:
			found = true
			best_d = dist
			best = c
	return best


func _kill(s: Dictionary) -> void:
	s["alive"] = false
	for c in s["cells"]:
		var center := _cell_center(c)
		for d in [Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(),
				Vector2(-1, 1).normalized(), Vector2(1, 1).normalized()]:
			_shards.append({"p": center, "d": d, "born": _sim_t})
	sfx("shatter")
	if battle:
		battle.shake(2.0)


func _split(s: Dictionary) -> void:
	var cells: Array = s["cells"]
	var front: Array = cells.slice(0, HALF)
	var back: Array = cells.slice(HALF, MAX_LEN)
	var rev: Array = []
	for i in range(back.size() - 1, -1, -1):
		rev.append(back[i])
	s["cells"] = front
	s["warn"] = 0
	var nd: Vector2i = rev[0] - rev[1]
	_snakes.append(_new_snake(rev, nd))
	_overflow_at = _sim_t
	sfx("glitch")
	sfx("spinner_burst")
	if battle:
		battle.shake(2.0)


func _do_step() -> void:
	_sim_t = START_BEAT + (_steps_done - 1) * STEP_BEAT
	var grow := _steps_done % GROW_EVERY == 0
	# 1. 选方向 + 2. 移动（所有蛇都走完）
	for s in _snakes:
		if not s["alive"]:
			continue
		var cells: Array = s["cells"]
		var nd := _choose_dir(s, grow)
		var nh: Vector2i = cells[0] + nd
		cells.insert(0, nh)
		if grow and cells.size() <= MAX_LEN:
			pass                            # 长一节：保留尾巴
		else:
			cells.pop_back()
		s["dir"] = nd
	# 3. 所有蛇都动完以后统一判死
	var dead: Array = []
	for s in _snakes:
		if not s["alive"]:
			continue
		var head: Vector2i = s["cells"][0]
		var hit := head.x < 0 or head.x >= COLS or head.y < 0 or head.y >= ROWS
		if not hit:
			for o in _snakes:
				if not o["alive"]:
					continue
				var oc: Array = o["cells"]
				for i in oc.size():
					if s == o and i == 0:
						continue
					if oc[i] == head:
						hit = true
						break
				if hit:
					break
		if hit:
			dead.append(s)
	for s in dead:
		_kill(s)
	if not dead.is_empty():
		_snakes = _snakes.filter(func(s: Dictionary) -> bool: return s["alive"])
	# 溢出预警 / 分裂
	for s in _snakes:
		if not s["alive"]:
			continue
		if s["warn"] > 0:
			s["warn"] -= 1
			if s["warn"] <= 0:
				if _alive_count() < MAX_SNAKES and s["cells"].size() >= MAX_LEN:
					_split(s)
				else:
					s["warn"] = 0
					s["no_split"] = true
		elif not s["no_split"] and s["cells"].size() >= MAX_LEN and _alive_count() < MAX_SNAKES:
			s["warn"] = 2


# ── 每帧 ────────────────────────────────────────────────────

func tick(_dt: float) -> void:
	if not _begun:
		_begun = true
		pose("summon")
		sfx("whale", 0.8)
	# 从第 1 拍开始，每 0.25 拍补足一次移动
	if t >= START_BEAT:
		var total := int(floor((t - START_BEAT) / STEP_BEAT)) + 1
		while _steps_done < total:
			_steps_done += 1
			_do_step()
			if _cleared_at >= 0.0:
				break
	# 第 2 拍以后一条活蛇都没有 → 清空
	if _cleared_at < 0.0 and t >= 2.0 and _alive_count() == 0:
		_cleared_at = t
		if battle and is_instance_valid(battle.bg):
			battle.bg.log("[INFO] 所有副本已终止", C.SYS)
	# 伤害：预警阶段（第 1 拍前）不伤人
	if t >= START_BEAT and _cleared_at < 0.0:
		for s in _snakes:
			if not s["alive"]:
				continue
			var cells: Array = s["cells"]
			for i in range(1, cells.size()):
				hz_rect(_cell_rect(cells[i]).grow(-2.0))
			hz_circle(_cell_center(cells[0]), 4.0)


func finished() -> bool:
	if _cleared_at >= 0.0:
		return t >= _cleared_at + 1.0
	return t >= duration


# ── 画 ──────────────────────────────────────────────────────

func _longest_alive() -> int:
	var n := 0
	for s in _snakes:
		if s["alive"]:
			n = maxi(n, s["cells"].size())
	return n


func _draw() -> void:
	# 网格点
	for i in COLS:
		for j in ROWS:
			draw_rect(Rect2(box.position + Vector2(i, j) * CELL, Vector2(1, 1)), Color(C.SYS_DIM, 0.5))
	var warn_red := int(floor(t * 8.0)) % 2 == 0
	var pre := t < START_BEAT
	for s in _snakes:
		if not s["alive"]:
			continue
		var cells: Array = s["cells"]
		var flashing: bool = s["warn"] > 0
		var body_col := C.WHITE
		var head_col := C.RED
		var alpha := 1.0
		if pre:
			alpha = 0.5 if warn_red else 0.2
		elif flashing:
			body_col = C.RED if warn_red else C.WHITE
			head_col = body_col
		for i in range(1, cells.size()):
			var r := _cell_rect(cells[i])
			draw_rect(Rect2(r.position + Vector2.ONE, Vector2(8, 8)), Color(body_col, alpha))
		var hc := _cell_center(cells[0])
		Whale.draw(self, hc, Vector2(s["dir"]), 12, Color(head_col, alpha))
	# 死亡碎块
	for sh in _shards:
		var age: float = t - sh["born"]
		if age < 0.0 or age >= 0.5:
			continue
		var u := age / 0.5
		var p: Vector2 = sh["p"] + sh["d"] * 8.0 * u
		draw_rect(Rect2((p - Vector2.ONE).round(), Vector2(2, 2)), Color(1, 1, 1, 1.0 - u))
	# 顶部计时 / 溢出提示
	if _overflow_at >= 0.0 and t < _overflow_at + 1.0:
		var msg := "上下文溢出！"
		var mw := Px.text_w(msg)
		Px.text(self, Vector2(box.get_center().x - mw / 2.0, box.position.y + 2.0), msg, C.RED)
	# 左上角长度
	var label := "上下文 %d/16" % _longest_alive()
	Px.text(self, Vector2(box.end.x - 4.0 - Px.text_w(label), box.end.y - 14.0), label, C.GRAY)   # 右下角，不挡初始的蛇
	# 清空提示
	if _cleared_at >= 0.0 and t < _cleared_at + 1.0:
		var s := "上下文已清空"
		var w := Px.text_w(s)
		Px.text(self, box.get_center() - Vector2(w / 2.0, 6.0), s, C.WHITE)
