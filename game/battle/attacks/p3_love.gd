extends Attack
## P3-3「L·O·V·E」
##
## 四个巨大的像素字母 L、O、V、E 连续四次砸进框里，几乎占满整个框，只有字母的空当能躲。
## - 5×5 格，每格 40×26；字母图案里的 X 是笔画（伤人），. 是空当（安全）。
## - 第 k 个字母在 b = 2 + 2k 拍砸下：先闪 1.25 拍红色预警，再落 0.12 拍，
##   实心 1 拍（伤害从 b+0.12 开始），最后碎成每格一块、每拍 45px 向外飞的 3×3 碎片。
## - E 碎掉后进入收尾：全称收拢成 LOVE，下方显示 LV；[9.5, 14) 不伤人。
## - 本攻击不镜像（字母不能反着写）。

const COLS := 5
const ROWS := 5
const CELL_W := 40.0
const CELL_H := 26.0
const LETTER_BEATS := [2.0, 4.0, 6.0, 8.0]
const WARN_LEAD := 1.25
const SLAM_LEN := 0.12
const SOLID_LEN := 1.0
const SHARD_SPEED := 45.0

## 字母图案：X = 笔画（伤害），. = 空当（安全）
const SHAPES := [
	["XX...", "XX...", "XX...", "XXXXX", "XXXXX"],   # L
	["XXXXX", "XXXXX", "XX.XX", "XXXXX", "XXXXX"],   # O
	["X...X", "XX.XX", "XX.XX", "XXXXX", "XXXXX"],   # V
	["XXXXX", "XX...", "XXXXX", "XX...", "XXXXX"],   # E
]

var _shards: Array = []               # {p0, v, t0}


## 第 (c, r) 格
func _cell(c: int, r: int) -> Rect2:
	return Rect2(
		box.position.x + CELL_W * c,
		box.position.y + CELL_H * r,
		CELL_W,
		CELL_H
	)


## 第 k 个字母的第 (c, r) 格是不是笔画
func _is_x(k: int, c: int, r: int) -> bool:
	var row: String = SHAPES[k][r]
	return row[c] == "X"


## 第 k 个字母的砸下拍
func _beat(k: int) -> float:
	return LETTER_BEATS[k]


func setup() -> void:
	duration = 14.0
	box_size = Vector2(200, 130)
	stop_beat = 3.0


## 把一个字母的所有 X 格变成向外飞的碎片
func _shatter(k: int, born: float) -> void:
	var center := box.get_center()
	for r in ROWS:
		for c in COLS:
			if not _is_x(k, c, r):
				continue
			var p0 := _cell(c, r).get_center()
			var dir := p0 - center
			if dir.length_squared() < 0.0001:
				dir = Vector2(0, 1)
			else:
				dir = dir.normalized()
			_shards.append({"p0": p0, "p": p0, "v": dir * SHARD_SPEED, "t0": born})


func tick(_dt: float) -> void:
	for k in LETTER_BEATS.size():
		var b := _beat(k)
		if crossed(b - 1.0):
			sfx("warn")
		if crossed(b):
			sfx("slam")
			battle.shake(4.0)
			pose("A_smile")
		if crossed(b + 1.0):
			sfx("shatter")
			pose("E")
			_shatter(k, b + 1.0)
	# 实心字母的伤害：砸下 0.12 拍后才开始
	for k in LETTER_BEATS.size():
		var b := _beat(k)
		if t < b + SLAM_LEN or t >= b + SOLID_LEN:
			continue
		for r in ROWS:
			for c in COLS:
				if _is_x(k, c, r):
					hz_rect(_cell(c, r).grow(-2.0))
	# 碎片：按拍数直线飞出去，出框外扩 6px 就删掉；收尾阶段不伤人
	for s in _shards:
		s["p"] = s["p0"] + s["v"] * (t - s["t0"])
	_shards = _shards.filter(func(s): return box.grow(6).has_point(s["p"]))
	if t < 9.5:
		for s in _shards:
			hz_circle(s["p"], 1.6)
	if crossed(11.0):
		sfx("levelup")


func _draw() -> void:
	# 预警：X 格淡红闪烁，每 1/4 拍闪一次
	for k in LETTER_BEATS.size():
		var b := _beat(k)
		if t < b - WARN_LEAD or t >= b:
			continue
		if int(t * 4.0) % 2 != 0:
			continue
		for r in ROWS:
			for c in COLS:
				if _is_x(k, c, r):
					draw_rect(_cell(c, r), Color(C.RED, 0.18))
	# 实心字母：前 0.12 拍从上方 30px 落下
	for k in LETTER_BEATS.size():
		var b := _beat(k)
		if t < b or t >= b + SOLID_LEN:
			continue
		var oy := 0.0
		if t < b + SLAM_LEN:
			oy = roundf(lerpf(-30.0, 0.0, (t - b) / SLAM_LEN))
		for r in ROWS:
			for c in COLS:
				if not _is_x(k, c, r):
					continue
				var cell := _cell(c, r)
				var r2 := Rect2(cell.position + Vector2(0, oy), cell.size)
				draw_rect(r2, C.RED)
				Px.frame(self, r2, 1.0, C.RED_DIM)
	# 碎片
	for s in _shards:
		var p: Vector2 = s["p"]
		draw_rect(Rect2((p - Vector2(1.5, 1.5)).round(), Vector2(3, 3)), C.RED)
	# 收尾：全称收拢成 LOVE，再显示 LV
	var c := box.get_center()
	if t >= 9.5 and t < 11.0:
		var k := clampf((t - 9.5) / 1.5, 0.0, 1.0)
		Fx.love_acronym(self, c + Vector2(0, -8), 24, k, C.RED, C.WHITE)
	elif t >= 11.0:
		Fx.love_acronym(self, c + Vector2(0, -8), 24, 1.0, C.RED, C.WHITE)
		var s := "LV %d" % battle.lv
		Px.text(self, Vector2(roundf(c.x - Px.text_w(s) * 0.5), roundf(c.y + 14.0)), s, C.WHITE)
