extends Attack
## P1-2「MoE 路由」
##
## DeepSeek 是混合专家模型：框上方 8 个专家格子，每一拍只激活其中几列，被选中的列向下射光束。
## - 每次预警有50%概率激活玩家当时所在列，否则不选该列；之后不追踪换列。
## - 选列时保证至少有两列相邻的列没被选中，所以框里始终有一条 48px 宽的安全区。
## - b ≤ 6 激活 2 列；7–9 激活 3 列；10–12 激活 4 列。每次预警时按玩家位置随机选择并缓存。
## - 光束覆盖整列，消除列边缘可站桩的判定缝；持续0.6拍，伤害0.5拍后才收窄。
## - mirror = true 时第 i 列画到第 7-i 列的位置。

const COLS := 8
const SELECT_BEATS := 12
const FIRE_LEN := 0.6
const SHRINK_LEN := 0.1
const CELL_SIZE := Vector2(20, 13)
const CORE_W := 10.0

var _picks: Array = []             # 每次预警追加一组已确定的列号，最多12组
var _posed_a := false
var _warning_beats := 1.0


func setup() -> void:
	duration = 14.5
	box_size = Vector2(192, 116)
	stop_beat = 7.0
	_picks.clear()
	_posed_a = false
	_warning_beats = 1.0


## 每次预警时才抽列：保留相邻两列，且在上一束光消退后仍来得及移入。
func _choose_columns() -> Array:
	var b := _picks.size() + 1
	var count := 2 if b <= 6 else (3 if b <= 9 else 4)
	var target_player := rng.randf() < 0.5
	var player_col := _player_column()
	var candidates: Array = []
	for mask in 256:
		var pick: Array = []
		for col in COLS:
			if mask & (1 << col):
				pick.append(col)
		if pick.size() == count and pick.has(player_col) == target_player and _pick_ok(pick):
			candidates.append(pick)
	assert(not candidates.is_empty(), "MoE 必须存在可达的安全列")
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _safe_distance(pick: Array, x: float) -> float:
	var nearest := INF
	for i in COLS - 1:
		if pick.has(i) or pick.has(i + 1):
			continue
		var left := minf(_col_x(i), _col_x(i + 1)) + C.HITBOX.x / 2.0 + 1.0
		var right := maxf(_col_x(i), _col_x(i + 1)) + _column_width() - C.HITBOX.x / 2.0 - 1.0
		nearest = minf(nearest, absf(x - clampf(x, left, right)))
	return nearest


func _player_column() -> int:
	var physical := clampi(floori((soul_pos().x - box.position.x) / _column_width()), 0, COLS - 1)
	return COLS - 1 - physical if mirror else physical


func _column_width() -> float:
	return box.size.x / COLS


func _pick_ok(pick: Array) -> bool:
	if not _picks.is_empty() and pick == _picks[-1]:
		return false
	# 上一束光持续半拍，另留 0.05 拍余量；按较慢的键盘横向速度估计。
	var travel := C.SOUL_SPEED * Conductor.spb / speed * (_warning_beats - 0.55)
	return _safe_distance(pick, soul_pos().x) <= travel


func begin() -> void:
	# 宽屏混剪也将整个框分成八列。较宽的列需要更长预警，避免锁列变成必中。
	# 靠近第二列边界时，一侧只有单列，需预留横穿一列到双列安全区的时间。
	var escape := _column_width() + C.HITBOX.x / 2.0 + 1.0
	_warning_beats = maxf(1.0, ceilf(escape / (C.SOUL_SPEED * Conductor.spb / speed) + 0.55))
	duration = SELECT_BEATS + _warning_beats + 1.5
	pose("snow")


## 第 i 列（逻辑列号）的左边 x；镜像时画到第 7-i 列
func _col_x(i: int) -> float:
	var c := (COLS - 1 - i) if mirror else i
	return box.position.x + _column_width() * c


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
			if t >= b + _warning_beats and t < b + _warning_beats + FIRE_LEN:
				return "fire"
			if t >= b and t < b + _warning_beats:
				return "pick"
	return "idle"


func tick(_dt: float) -> void:
	while _picks.size() < SELECT_BEATS and t >= float(_picks.size() + 1):
		_picks.append(_choose_columns())
	for idx in _picks.size():
		var b := float(idx + 1)
		if crossed(b):
			sfx("warn")
		if crossed(b + _warning_beats):
			sfx("beam")
		# 伤害只在光束最粗的 0.5 拍里
		if t >= b + _warning_beats and t < b + _warning_beats + 0.5:
			for i in _picks[idx]:
				hz_rect(Rect2(_col_x(int(i)), box.position.y, _column_width(), box.size.y))
	if t >= SELECT_BEATS + _warning_beats and not _posed_a:
		_posed_a = true
		pose("A")


func _draw() -> void:
	# 先画预警，再画光束：上一拍的光束盖住这一拍刚出现的蚂蚁线
	for idx in _picks.size():
		var b := float(idx + 1)
		if t >= b and t < b + _warning_beats:
			for i in _picks[idx]:
				var x := _col_x(int(i))
				Px.dashed(self, Rect2(x + 2.0, box.position.y + 1.0, _column_width() - 4.0, box.size.y - 2.0), Color(C.SYS, 0.8), t * 16.0)
	for idx in _picks.size():
		var b := float(idx + 1)
		if t >= b + _warning_beats and t < b + _warning_beats + FIRE_LEN:
			for i in _picks[idx]:
				_draw_beam(int(i), b)


func _draw_beam(i: int, b: float) -> void:
	var cx := _col_x(i) + _column_width() * 0.5
	# 伤害结束后，最后0.1拍从整列宽收窄到中线
	var u := clampf((t - (b + _warning_beats + FIRE_LEN - SHRINK_LEN)) / SHRINK_LEN, 0.0, 1.0)
	var ow := lerpf(_column_width(), 10.0, u)
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
		var r := Rect2(Vector2(_col_x(i) + 2.0, top).round(), Vector2(_column_width() - 4.0, CELL_SIZE.y))
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
		Px.text(ci, Vector2(r.position.x + roundf((_column_width() - 4.0 - Px.text_w(label)) * 0.5), r.position.y), label, text_col)
