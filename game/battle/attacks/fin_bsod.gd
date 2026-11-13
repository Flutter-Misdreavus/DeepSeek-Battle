extends Attack
## 终局「蓝屏」（8–24 拍）
##
## 整个屏幕死机，刷成一块 Windows 蓝屏。蓝屏上的「:(」翻过来变成她的「:)」，
## 左下角二维码的像素被一片片抛出去，两波碎片从框顶落下。
## - [0, 0.25) 蓝色从框顶向下刷满；之后整个框 #0b56c4。
## - [2, 2.5) 「(」以自身中心水平翻成「)」，过零时白变红；第 2 拍响 glitch、换 F_smile。
## - 二维码 21×21、每格 4px，三个角是 7×7 定位块，其余 50% 随机实心（格子够六批碎片用）。
## - 第 3/5/7/9/11/13 拍各从二维码里抛出一批像素碎片，碎片位置是爆开拍数的纯函数。
## - [8,10) / [12,14) 两波带 64px 安全通道的顶部碎片；第 15 拍「重启」，蓝色和文字淡出。

const BLUE := Color("#0b56c4")
const QR_N := 21
const QR_CELL := 4.0
const QR_OFF := Vector2(48.0, 164.0)
const BURSTS := [3.0, 5.0, 7.0, 9.0, 11.0, 13.0]
const RAIN_AT := [8.0, 12.0]
const RAIN_GAP := 64.0
const RAIN_SIZE := 4.0
const WARN := 0.5
const GRAVITY := 90.0

var _qr: Array = []                 # 非定位块：实心 / 空
var _finder: Array = []             # 这一格属不属于三个定位块
var _removed: Array = []            # 已经被抛走的格子
var _bursts: Array = []             # 每次爆：[{cell:Vector2i, ang:float, spd:float}]
var _rains: Array = []


func setup() -> void:
	duration = 16.0
	box_size = Vector2(620, 260)
	_rains.clear()
	_qr = []
	_finder = []
	_removed = []
	for y in QR_N:
		var row_q: Array = []
		var row_f: Array = []
		var row_r: Array = []
		for x in QR_N:
			var f := _is_finder(x, y)
			row_f.append(f)
			row_q.append(false if f else rng.randf() < 0.5)
			row_r.append(false)
		_qr.append(row_q)
		_finder.append(row_f)
		_removed.append(row_r)
	# 先把所有可抛的实心格洗牌，再按批次预先分好；随机量全部在 setup 里算完。
	var pool: Array = []
	for y in QR_N:
		for x in QR_N:
			if _qr[y][x] and not _finder[y][x]:
				pool.append(Vector2i(x, y))
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	_bursts = []
	var idx := 0
	for n in BURSTS.size():
		var want := 10 + 2 * n
		var arr: Array = []
		for _i in want:
			if idx >= pool.size():
				break
			var cell: Vector2i = pool[idx]
			idx += 1
			arr.append({
				"cell": cell,
				"ang": deg_to_rad(rng.randf_range(-80.0, -20.0)),
				"spd": rng.randf_range(110.0, 170.0),
			})
		_bursts.append(arr)


## 顶部雨只在预警开始时生成一次。缺口按玩家当前位置约束，覆盖红心的完整宽度。
func _make_rain() -> Dictionary:
	var cx := clampf(soul_pos().x + rng.randf_range(-24.0, 24.0), box.position.x + RAIN_GAP / 2.0, box.end.x - RAIN_GAP / 2.0)
	var gap := Vector2(cx - RAIN_GAP / 2.0, cx + RAIN_GAP / 2.0)
	var candidates: Array[float] = []
	for x in range(int(box.position.x + 4), int(box.end.x - 3), 8):
		if x + RAIN_SIZE / 2.0 <= gap.x or x - RAIN_SIZE / 2.0 >= gap.y:
			candidates.append(float(x))
	var xs: Array[float] = []
	for i in 10:
		var j := rng.randi_range(0, candidates.size() - 1)
		xs.append(candidates.pop_at(j))
	return {"gap": gap, "xs": xs}


func _rain_y(at: float) -> float:
	return lerpf(box.position.y - RAIN_SIZE, box.end.y + RAIN_SIZE, (t - at) / 2.0)


# ── 二维码 ──────────────────────────────────────────────────
func _is_finder(x: int, y: int) -> bool:
	return _finder_local(x, y).x >= 0


## 定位块里第 (lx, ly) 格是不是实心：外圈 + 正中 3×3
func _finder_solid(lx: int, ly: int) -> bool:
	if lx == 0 or lx == 6 or ly == 0 or ly == 6:
		return true
	return lx >= 2 and lx <= 4 and ly >= 2 and ly <= 4


## 定位块里的局部坐标；不在定位块返回 (-1, -1)
func _finder_local(x: int, y: int) -> Vector2i:
	if x < 7 and y < 7:
		return Vector2i(x, y)
	if x >= QR_N - 7 and y < 7:
		return Vector2i(x - (QR_N - 7), y)
	if x < 7 and y >= QR_N - 7:
		return Vector2i(x, y - (QR_N - 7))
	return Vector2i(-1, -1)


func _qr_pos() -> Vector2:
	return box.position + QR_OFF


func _cell_pos(cell: Vector2i) -> Vector2:
	return _qr_pos() + (Vector2(cell) + Vector2(0.5, 0.5)) * QR_CELL


# ── 时间 ────────────────────────────────────────────────────
func _fade_a() -> float:
	if t < 15.0:
		return 1.0
	return clampf(1.0 - (t - 15.0), 0.0, 1.0)


## 当前正在预警的批次；没有就返回 -1
func _warning_burst() -> int:
	for n in BURSTS.size():
		var b: float = BURSTS[n]
		if t >= b - WARN and t < b:
			return n
	return -1


## 碎片在爆开拍 b 之后 tau 拍的位置
func _frag_pos(fr: Dictionary, b: float) -> Vector2:
	var tau := t - b
	var v: Vector2 = Vector2(cos(fr["ang"]), sin(fr["ang"])) * fr["spd"]
	return _cell_pos(fr["cell"]) + v * tau + Vector2(0.0, 0.5 * GRAVITY * tau * tau)


# ── 每帧 ────────────────────────────────────────────────────
func tick(_dt: float) -> void:
	if crossed(2.0):
		sfx("glitch")
		pose("F_smile")
	for n in BURSTS.size():
		var b: float = BURSTS[n]
		if not crossed(b):
			continue
		for fr in _bursts[n]:
			var cell: Vector2i = fr["cell"]
			_removed[cell.y][cell.x] = true
		sfx("spinner_burst")
		if battle:
			battle.shake(2.0)
	while _rains.size() < RAIN_AT.size() and t >= RAIN_AT[_rains.size()] - WARN:
		_rains.append(_make_rain())
	for i in _rains.size():
		var at: float = RAIN_AT[i]
		if crossed(at - WARN):
			sfx("warn")
		if t >= at and t < at + 2.0:
			for x in _rains[i]["xs"]:
				hz_rect(Rect2(Vector2(x - 2.0, _rain_y(at) - 2.0), Vector2(4, 4)))
	# 碎片：爆开后到掉出框底 10px 前都伤人
	for n in BURSTS.size():
		var b: float = BURSTS[n]
		if t < b:
			continue
		for fr in _bursts[n]:
			var p := _frag_pos(fr, b)
			if p.y <= box.end.y + 10.0:
				hz_rect(Rect2(p - Vector2(2.0, 2.0), Vector2(4.0, 4.0)))
	if crossed(15.0):
		if battle:
			battle.overlay.do_flash(0.3)
		sfx("boot")


func _draw() -> void:
	var a := _fade_a()
	# 蓝底
	var fill_h := box.size.y
	if t < 0.25:
		fill_h = box.size.y * clampf(t / 0.25, 0.0, 1.0)
	if fill_h > 0.0:
		draw_rect(Rect2(box.position, Vector2(box.size.x, fill_h)), Color(BLUE, a))
	# 二维码（被取走的格子变空）
	var o := _qr_pos()
	for y in QR_N:
		for x in QR_N:
			if _removed[y][x]:
				continue
			var solid := false
			if _finder[y][x]:
				var lc := _finder_local(x, y)
				solid = _finder_solid(lc.x, lc.y)
			else:
				solid = _qr[y][x]
			if solid:
				var p := o + Vector2(x, y) * QR_CELL
				draw_rect(Rect2(p.round(), Vector2(QR_CELL, QR_CELL)), Color(C.WHITE, a))
	# 预警：即将脱落的格子闪红
	var wb := _warning_burst()
	if wb >= 0:
		var b: float = BURSTS[wb]
		var red := int(floor((t - (b - WARN)) / 0.125)) % 2 == 1
		if red:
			for fr in _bursts[wb]:
				var cell: Vector2i = fr["cell"]
				if _removed[cell.y][cell.x]:
					continue
				var p := o + Vector2(cell) * QR_CELL
				draw_rect(Rect2(p.round(), Vector2(QR_CELL, QR_CELL)), Color(C.RED, a))
	# 文字
	var tx := box.position.x + 48.0
	_draw_face(a)
	Px.text(self, Vector2(tx, box.position.y + 110.0), "你的电脑遇到问题，需要重新启动。", Color(C.WHITE, a), 12)
	Px.text(self, Vector2(tx, box.position.y + 130.0), "我们只收集某些错误信息，然后为你重新启动。", Color(C.WHITE, a), 12)
	var pct := clampi(int((t - 1.0) / 14.0 * 100.0), 0, 100)
	Px.text(self, Vector2(tx, box.position.y + 146.0), str(pct) + "% 完成", Color(C.WHITE, a), 12)
	Px.text(self, Vector2(o.x + QR_N * QR_CELL + 12.0, o.y + 4.0), "停止代码：DETERMINATION_OVERFLOW", Color(C.WHITE, a), 12)
	# 顶部落点预警与落下碎片，使用同一份缓存位置。
	for i in _rains.size():
		var at: float = RAIN_AT[i]
		for x in _rains[i]["xs"]:
			if t >= at - WARN and t < at:
				draw_line(Vector2(x, box.position.y), Vector2(x, box.position.y + 10), C.RED, 2.0)
			elif t >= at and t < at + 2.0:
				draw_rect(Rect2(Vector2(x - 2.0, _rain_y(at) - 2.0).round(), Vector2(4, 4)), Color(C.WHITE, a))
	# 碎片
	for n in BURSTS.size():
		var b: float = BURSTS[n]
		if t < b:
			continue
		for fr in _bursts[n]:
			var p := _frag_pos(fr, b)
			if p.y > box.end.y + 10.0:
				continue
			draw_rect(Rect2((p - Vector2(3.0, 3.0)).round(), Vector2(6.0, 6.0)), C.WHITE)


## 哭脸「:(」24px 放大 3 倍；[2,2.5) 中「(」绕自身中心水平翻成「)」
func _draw_face(a: float) -> void:
	var x := box.position.x + 48.0
	var y := box.position.y + 16.0
	var sx := 1.0
	var col := C.WHITE
	if t >= 2.0 and t < 2.5:
		sx = lerpf(1.0, -1.0, (t - 2.0) / 0.5)
		if sx <= 0.0:
			col = C.RED
	elif t >= 2.5:
		sx = -1.0
		col = C.RED
	var cw := Px.text_w(":", 24)
	var pw := Px.text_w("(", 24)
	# 冒号：从脸左上角整体放大 3 倍
	draw_set_transform(Vector2(x, y), 0.0, Vector2(3.0, 3.0))
	Px.text(self, Vector2.ZERO, ":", Color(col, a), 24)
	# 括号：以自身中心为轴水平翻转
	draw_set_transform(Vector2(x + (cw + pw * 0.5) * 3.0, y), 0.0, Vector2(sx * 3.0, 3.0))
	Px.text(self, Vector2(-pw * 0.5, 0.0), "(", Color(col, a), 24)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
