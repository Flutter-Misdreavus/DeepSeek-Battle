extends Attack
## P1-2「MoE 路由」
##
## DeepSeek 是混合专家模型：框上方 8 个专家格子，每一拍只激活其中几列，被选中的列向下射光束。
## - 第 b 拍（b = 1…12）先选 k 列闪蚂蚁线，下一拍从这些列射出光束。
## - 选列时保证至少有两列相邻的列没被选中，所以框里始终有一条 48px 宽的安全区。
## - b ≤ 6 激活 2 列；7–9 激活 3 列；10–12 激活 4 列。每次预警时按玩家位置随机选择并缓存。
## - 光束持续 0.6 拍，最后 0.2 拍收窄；伤害只在 [b+1, b+1.5)。
## - mirror = true 时第 i 列画到第 7-i 列的位置。

const COLS := 8
const COL_W := 24.0
const SELECT_BEATS := 12
const FIRE_LEN := 0.6
const SHRINK_LEN := 0.2
const CELL_SIZE := Vector2(20, 13)
const OUTER_W := 20.0
const CORE_W := 10.0

var _picks: Array = []             # 每次预警追加一组已确定的列号，最多12组
var _posed_a := false


func setup() -> void:
	duration = 14.5
	box_size = Vector2(192, 116)
	stop_beat = 7.0
	_picks.clear()


## 每次预警时才抽列：保留相邻两列，且在上一束光消退后仍来得及移入。
func _choose_columns() -> Array:
	var b := _picks.size() + 1
	var count := 2 if b <= 6 else (3 if b <= 9 else 4)
	var candidates: Array = []
	for mask in 256:
		var pick: Array = []
		for col in COLS:
			if mask & (1 << col):
				pick.append(col)
		if pick.size() == count and _pick_ok(pick):
			candidates.append(pick)
	assert(not candidates.is_empty(), "MoE 必须存在可达的安全列")
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _safe_distance(pick: Array, x: float) -> float:
	var nearest := INF
	for i in COLS - 1:
		if pick.has(i) or pick.has(i + 1):
			continue
		var left := minf(_col_x(i), _col_x(i + 1)) + C.SOUL_HALF.x + 1.0
		var right := maxf(_col_x(i), _col_x(i + 1)) + COL_W - C.SOUL_HALF.x - 1.0
		nearest = minf(nearest, absf(x - clampf(x, left, right)))
	return nearest


func _pick_ok(pick: Array) -> bool:
	if not _picks.is_empty() and pick == _picks[-1]:
		return false
	# 上一束光持续半拍，另留 0.05 拍余量；按较慢的键盘横向速度估计。
	var travel := C.SOUL_SPEED * Conductor.spb / speed * 0.45
	return _safe_distance(pick, soul_pos().x) <= travel


func begin() -> void:
	pose("snow")


## 第 i 列（逻辑列号）的左边 x；镜像时画到第 7-i 列
func _col_x(i: int) -> float:
	var c := (COLS - 1 - i) if mirror else i
	return box.position.x + COL_W * c


## 当前（最近一次）选择的序号；第一次选择之前是 -1
func _cur_pick() -> int:
	var cur := -1
	for idx in _picks.size():
		if t >= float(idx + 1):
			cur = idx
	return cur


## 专家格子的状态：idle / pick（被选中）/ fire（发射中）
func _cell_state(i: int) -> String:
	for idx in _picks.size():
		var b := float(idx + 1)
		if _picks[idx].has(i):
			if t >= b + 1.0 and t < b + 1.0 + FIRE_LEN:
				return "fire"
			if t >= b and t < b + 1.0:
				return "pick"
	return "idle"


func tick(_dt: float) -> void:
	while _picks.size() < SELECT_BEATS and t >= float(_picks.size() + 1):
		_picks.append(_choose_columns())
	for idx in _picks.size():
		var b := float(idx + 1)
		if crossed(b):
			sfx("warn")
		if crossed(b + 1.0):
			sfx("beam")
		# 伤害只在光束最粗的 0.5 拍里
		if t >= b + 1.0 and t < b + 1.5:
			for i in _picks[idx]:
				hz_rect(Rect2(_col_x(int(i)) + 4.0, box.position.y, 16.0, box.size.y))
	if t >= 13.0 and not _posed_a:
		_posed_a = true
		pose("A")


func _draw() -> void:
	# 先画预警，再画光束：上一拍的光束盖住这一拍刚出现的蚂蚁线
	for idx in _picks.size():
		var b := float(idx + 1)
		if t >= b and t < b + 1.0:
			for i in _picks[idx]:
				var x := _col_x(int(i))
				Px.dashed(self, Rect2(x + 2.0, box.position.y + 1.0, 20.0, box.size.y - 2.0), Color(C.SYS, 0.8), t * 16.0)
	for idx in _picks.size():
		var b := float(idx + 1)
		if t >= b + 1.0 and t < b + 1.0 + FIRE_LEN:
			for i in _picks[idx]:
				_draw_beam(int(i), b)


func _draw_beam(i: int, b: float) -> void:
	var cx := _col_x(i) + COL_W * 0.5
	# 最后 0.2 拍从整列宽线性收窄到中线
	var u := clampf((t - (b + 1.0 + FIRE_LEN - SHRINK_LEN)) / SHRINK_LEN, 0.0, 1.0)
	var ow := lerpf(OUTER_W, 10.0, u)
	var iw := lerpf(CORE_W, 4.0, u)
	draw_rect(Rect2(Vector2(roundf(cx - ow * 0.5), box.position.y), Vector2(roundf(ow), box.size.y)), C.SYS)
	draw_rect(Rect2(Vector2(roundf(cx - iw * 0.5), box.position.y), Vector2(roundf(iw), box.size.y)), C.WHITE)


func draw_outside(ci: CanvasItem) -> void:
	var top := box.position.y - 18.0
	var cur := _cur_pick()
	var k := 0
	if cur >= 0:
		k = _picks[cur].size()
	Px.text(ci, Vector2(box.position.x - 28.0, box.position.y - 17.0), "路由", C.SYS)
	Px.text(ci, Vector2(box.end.x + 4.0, box.position.y - 17.0), "激活 %d/8" % k, C.SYS)
	for i in COLS:
		var r := Rect2(Vector2(_col_x(i) + 2.0, top).round(), CELL_SIZE)
		var state := _cell_state(i)
		var fill := C.BLACK
		var edge := C.SYS_DIM
		var text_col := C.SYS_DIM
		if state == "pick":
			fill = C.SYS
			edge = C.WHITE
			text_col = C.WHITE
		elif state == "fire":
			fill = C.WHITE
			edge = C.WHITE
			text_col = C.BLACK
		ci.draw_rect(r, fill)
		Px.frame(ci, r, 1.0, edge)
		var label := "E%d" % (i + 1)
		Px.text(ci, Vector2(r.position.x + roundf((CELL_SIZE.x - Px.text_w(label)) * 0.5), r.position.y), label, text_col)
