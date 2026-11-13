extends Attack
## P3-4「温度 2.0」
##
## 同一组鲸鱼跑三遍，温度一遍比一遍高：温度 0 时直直地游、完全可预测；
## 温度 1、2 时路线变成正弦，温度越高越扭。每条鲸鱼出发前 0.75 拍先画出整条路线。
## - 每轮 8 次出发，间隔 0.5 拍；三轮共用同一个车道序列。
## - 相位 φ 在 setup() 里用 rng 预先生好，之后位置和朝向都是 t 的纯函数。
## - 温度滑杆画在框上方；拉温度时红光标贴在滑块中心。
## - 第 17 拍她把滑杆拉爆：框里所有鲸鱼变成气泡，不再画、不再伤人。
## - mirror = true：鲸鱼从右往左游。

const ROUND_START := [0.5, 6.5, 12.5]
const LANES := [[0], [3], [1, 4], [2], [0, 3], [4], [1], [2, 4]]
const LANE_Y := 13.0
const LANE_GAP := 26.0
const VX := 70.0
const W := 20
const SPAWN_OFF := 12.0
const PREVIEW := 0.75
const BURST := 17.0

var _phases: Array = []              # [轮][第 n 次出发][车道序号] = φ
var _bubbles: Array = []             # 拉爆时的气泡：{p, ang}
var _burst := -1.0


func setup() -> void:
	duration = 18.0
	box_size = Vector2(220, 130)
	stop_beat = 9.0
	for r in 3:
		var rows := []
		for n in 8:
			var ps := []
			for _lane in LANES[n]:
				ps.append(rng.randf_range(0.0, TAU))
			rows.append(ps)
		_phases.append(rows)


func begin() -> void:
	pass


# ── 温度 ──────────────────────────────────────────────────────

func _temp_at(now: float) -> float:
	if now < 5.0:
		return 0.0
	if now < 6.0:
		return (now - 5.0)
	if now < 11.0:
		return 1.0
	if now < 12.0:
		return 1.0 + (now - 11.0)
	return 2.0


func _amp(r: int) -> float:
	return [0.0, 12.0, 24.0][r]


func _wavelen(r: int) -> float:
	return [120.0, 80.0, 80.0][r]


func _round_temp(r: int) -> int:
	return [0, 1, 2][r]


# ── 滑杆 ──────────────────────────────────────────────────────

func _y0() -> float:
	return box.position.y - 22.0


func _track() -> Rect2:
	return Rect2(box.position.x + 90.0, _y0() + 5.0, 110.0, 2.0)


func _handle_center(temp: float) -> Vector2:
	var tr := _track()
	return Vector2(tr.position.x + 110.0 * temp / 2.0, _y0() + 6.0)


## 拉爆时滑块左右抖 3 次
func _shake_x(now: float) -> float:
	if now < BURST or now >= BURST + 0.5:
		return 0.0
	return 3.0 * sin((now - BURST) / 0.5 * TAU * 3.0)


func _idle_tip() -> Vector2:
	return Vector2(box.end.x + 10.0, box.position.y - 10.0)


func _tip(now: float) -> Vector2:
	# 两次拉温度：提前 0.5 拍过来，拉完 0.5 拍内回去
	for s in [5.0, 11.0]:
		if now >= s - 0.5 and now < s:
			return _idle_tip().lerp(_handle_center(_temp_at(s)), (now - (s - 0.5)) / 0.5)
		if now >= s and now < s + 1.0:
			return _handle_center(_temp_at(now))
		if now >= s + 1.0 and now < s + 1.5:
			var t_end := _temp_at(s + 1.0)
			return _handle_center(t_end).lerp(_idle_tip(), (now - (s + 1.0)) / 0.5)
	# 第 17 拍拉爆滑杆
	if now >= BURST - 0.5 and now < BURST:
		return _idle_tip().lerp(_handle_center(2.0), (now - (BURST - 0.5)) / 0.5)
	if now >= BURST and now < BURST + 0.5:
		return _handle_center(2.0) + Vector2(_shake_x(now), 0.0)
	return _idle_tip()


# ── 鲸鱼 ──────────────────────────────────────────────────────

## 第 r 轮第 n 次出发的第 li 条（对应 LANES[n][li]）在 now 的 [位置, 速度]
func _whale_state(r: int, n: int, li: int, now: float) -> Array:
	var d: float = ROUND_START[r] + n * 0.5
	if now < d:
		return []
	var xr := box.position.x - SPAWN_OFF + VX * (now - d)
	if xr > box.end.x + SPAWN_OFF:
		return []
	var lane: int = LANES[n][li]
	var phi: float = _phases[r][n][li]
	var a := _amp(r)
	var l := _wavelen(r)
	var ph := TAU * (xr - box.position.x) / l + phi
	var y := box.position.y + LANE_Y + lane * LANE_GAP + a * sin(ph)
	var dy := a * TAU / l * cos(ph) * VX
	var p := Vector2(xr, y)
	var v := Vector2(VX, dy)
	if mirror:
		p.x = box.position.x + box.end.x - p.x
		v.x = -v.x
	return [p, v]


## 现在还在框附近的鲸鱼：[位置, 速度, 轮]
func _whales(now: float) -> Array:
	var out := []
	for r in 3:
		for n in 8:
			for li in LANES[n].size():
				var s := _whale_state(r, n, li, now)
				if not s.is_empty():
					out.append([s[0], s[1], r])
	return out


# ── 每帧 ──────────────────────────────────────────────────────

func tick(_dt: float) -> void:
	if crossed(5.0) or crossed(11.0):
		sfx("click")
	if crossed(12.0):
		sfx("glitch")
		if battle:
			battle.shake(2.0)
	if crossed(BURST):
		_burst = t
		sfx("shatter")
		if battle:
			battle.shake(4.0)
		# 框里还在游的鲸鱼全部变成气泡
		for r in 3:
			for n in 8:
				for li in LANES[n].size():
					var s := _whale_state(r, n, li, t)
					if s.is_empty():
						continue
					var p: Vector2 = s[0]
					if not box.grow(14.0).has_point(p):
						continue
					var phi: float = _phases[r][n][li]
					for k in 6:
						_bubbles.append({"p": p, "ang": TAU * k / 6.0 + phi})
	if t < BURST:
		for w in _whales(t):
			hz_circle(w[0], Whale.radius(W))


func _draw() -> void:
	var blink := int(t * 8.0) % 2 == 0
	# 路线预告：每条鲸鱼出发前 0.75 拍
	if blink:
		for r in 3:
			for n in 8:
				var d: float = ROUND_START[r] + n * 0.5
				if t < d - PREVIEW or t >= d:
					continue
				var a := _amp(r)
				var l := _wavelen(r)
				var col := C.RED if _round_temp(r) == 2 else C.SYS
				for li in LANES[n].size():
					var lane: int = LANES[n][li]
					var phi: float = _phases[r][n][li]
					var x := box.position.x - SPAWN_OFF
					while x <= box.end.x + SPAWN_OFF:
						var ph := TAU * (x - box.position.x) / l + phi
						var y := box.position.y + LANE_Y + lane * LANE_GAP + a * sin(ph)
						var p := Vector2(x, y)
						if mirror:
							p.x = box.position.x + box.end.x - p.x
						draw_rect(Rect2(p.round() - Vector2.ONE, Vector2(2, 2)), col)
						x += 6.0
	# 鲸鱼
	if t < BURST:
		for w in _whales(t):
			var r: int = w[2]
			var col := C.RED if _round_temp(r) == 2 else C.WHITE
			Whale.draw(self, w[0], w[1], W, col)
	# 拉爆后的气泡
	if _burst >= 0.0 and t < _burst + 0.4:
		var u := (t - _burst) / 0.4
		for b in _bubbles:
			var p: Vector2 = b["p"] + Vector2(cos(b["ang"]), sin(b["ang"])) * 12.0 * u
			draw_arc(p.round(), 1.0, 0.0, TAU, 8, C.SYS, 1.0)


func draw_outside(ci: CanvasItem) -> void:
	var y0 := _y0()
	Px.text(ci, Vector2(box.position.x, y0), "temperature", C.GRAY)
	var tr := _track()
	ci.draw_rect(Rect2(tr.position.round(), tr.size.round()), C.GRAY_DIM)
	var temp := _temp_at(t)
	var hc := _handle_center(temp)
	if t >= BURST:
		hc.x += _shake_x(t)
	var hr := Rect2((hc - Vector2(3, 5)).round(), Vector2(6, 10))
	ci.draw_rect(hr, C.WHITE if temp < 1.5 else C.RED)
	Px.text(ci, Vector2(tr.end.x + 6.0, y0), "%.1f" % temp, C.WHITE)
	Px.cursor(ci, _tip(t), C.RED)
