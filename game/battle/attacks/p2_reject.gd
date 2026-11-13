extends Attack
## P2-2「拒绝」
##
## 绿心：她发起「提示词注入」，鲸鱼从四面八方游向你的心，你举着「拒绝」盾一条条挡回去。
## 参考传说之下 Undyne 的绿心。
## - 20 条鲸鱼按原节奏到达，初始来向随机；前 12 条为白鲸，后 8 条随机混合 4 白 4 红。
## - 到达那一帧看盾的方向：对准了就挡住（这条消失、出气泡），没对准就继续往里飞并开始伤人。
## - 白鲸直线迎面格挡；红鲸最后 0.75 拍绕到对侧，朝初始来向的反方向格挡。
## - 鲸鱼画在框外也看得见，所以全部画在 draw_outside；框只有 64×64。
## - 所有随机结果在 setup 缓存；mirror 同时反转初始来向与绕行方向。

const W := 24
const V := 60.0                          # 每拍向心靠近多少像素
const R_HIT := 13.0 + 6.72 + 2.0         # Soul.SHIELD_R + Whale.radius(W) + 2 ≈ 21.7
const EXIST := 2.4                       # 还剩几拍时出现
const HINT_BEATS := 3.0

const TURN_BEATS := 0.75
const ARRIVALS := [
	1.0, 2.0, 3.0, 4.0, 5.0, 5.5, 6.0, 6.5,
	7.5, 8.5, 9.5, 10.0, 11.0, 12.0, 12.5, 13.5,
	14.5, 15.0, 15.5, 16.0,
]

const DIR_VEC := {
	"U": Vector2i(0, -1),
	"D": Vector2i(0, 1),
	"L": Vector2i(-1, 0),
	"R": Vector2i(1, 0),
}
const DIR_ANG := {"U": -PI / 2.0, "D": PI / 2.0, "L": PI, "R": 0.0}
const DIR_ORDER := ["U", "D", "L", "R"]   # 气泡音高用的方向序号

var _whales: Array = []                 # [初始来向, s/r, 绕行方向 ±1]
var c := Vector2.ZERO
var _blocked: Array[bool] = []
var _bubbles: Array = []                 # {p: 到达点, d: 方向, t0: 拍}
var _first_tick := true


func setup() -> void:
	duration = 17.0
	box_size = Vector2(64, 64)
	soul_mode = "green"
	no_stop = true
	_whales.clear()
	_blocked.clear()
	_bubbles.clear()
	_first_tick = true
	# 枚举合法的后八条配色，有限候选中随机选择，避免重抽循环。
	var mixes: Array[int] = []
	for mask in 256:
		var reds := 0
		var valid := true
		for j in 8:
			var red := (mask >> j) & 1
			reds += red
			if j >= 2 and red == ((mask >> (j - 1)) & 1) and red == ((mask >> (j - 2)) & 1):
				valid = false
		if valid and reds == 4:
			mixes.append(mask)
	var mix := mixes[rng.randi_range(0, mixes.size() - 1)]
	for i in ARRIVALS.size():
		var red := i >= 12 and ((mix >> (i - 12)) & 1) == 1
		_whales.append([DIR_ORDER[rng.randi_range(0, 3)], "r" if red else "s", -1 if rng.randi_range(0, 1) == 0 else 1])
		_blocked.append(false)


func begin() -> void:
	pose("summon")
	c = box.get_center()


## 镜像后的来向
func _side(i: int) -> String:
	var s: String = _whales[i][0]
	if mirror:
		if s == "L":
			return "R"
		if s == "R":
			return "L"
	return s


func _kind(i: int) -> String:
	return _whales[i][1]


func _spin(i: int) -> float:
	return float(_whales[i][2]) * (-1.0 if mirror else 1.0)


## 红鲸的初始来向和最终格挡侧相反。
func _guard_dir(i: int) -> Vector2i:
	var d: Vector2i = DIR_VEC[_side(i)]
	return -d if _kind(i) == "r" else d


func _arrive(i: int) -> float:
	return ARRIVALS[i]


## 最后 0.75 拍绕半圈，smoothstep 使两端角速度为零。
func _theta(i: int, rem: float) -> float:
	var th: float = DIR_ANG[_side(i)]
	if _kind(i) == "r":
		var u := clampf(1.0 - rem / TURN_BEATS, 0.0, 1.0)
		th += _spin(i) * PI * u * u * (3.0 - 2.0 * u)
	return th


## 极角对时间（拍）的导数，用于鲸鱼贴图朝向。
func _dtheta(i: int, rem: float) -> float:
	if _kind(i) == "r":
		var u := clampf(1.0 - rem / TURN_BEATS, 0.0, 1.0)
		return _spin(i) * PI * 6.0 * u * (1.0 - u) / TURN_BEATS
	return 0.0


## 在拍 now 的 [位置, 前进方向, 剩余拍数]
func _path(i: int, now: float) -> Array:
	var a := _arrive(i)
	var rem := a - now
	var r := R_HIT + rem * V
	var th := _theta(i, rem)
	var u := Vector2(cos(th), sin(th))
	var p := c + u * r
	var dth := _dtheta(i, rem)
	var v := u * -V + Vector2(-u.y, u.x) * r * dth
	return [p, v, rem]


## 这条还在场吗（出现后、没被挡住、还没缩到心里）
func _alive(i: int, now: float) -> bool:
	if _blocked[i]:
		return false
	var rem := _arrive(i) - now
	return rem <= EXIST and rem > -R_HIT / V


func tick(_dt: float) -> void:
	for i in _whales.size():
		var a := _arrive(i)
		# 出现（第 0 拍之前就出现的两条，在第一帧补一次声音）
		if crossed(a - EXIST) or (_first_tick and a - EXIST <= 0.0):
			sfx("bubble", 1.0 + 0.1 * DIR_ORDER.find(_side(i)))
		if _kind(i) == "r" and crossed(a - TURN_BEATS):
			sfx("whale", 1.3)
		# 到达：对准方向就挡住
		if crossed(a) and not _blocked[i]:
			if battle.soul.shield_dir == _guard_dir(i):
				_blocked[i] = true
				_burst(i)
				battle.soul.block()
		# 没挡住：越过到达拍之后才伤人，继续往心里飞
		if _blocked[i]:
			continue
		if not _alive(i, t):
			continue
		var pv := _path(i, t)
		if float(pv[2]) <= 0.0:
			hz_circle(pv[0], Whale.radius(W))
	_first_tick = false


## 挡住时在到达点炸出 6 个向外飞的气泡
func _burst(i: int) -> void:
	var p := c + Vector2(_guard_dir(i)) * R_HIT
	for k in 6:
		var a := TAU * k / 6.0
		_bubbles.append({"p": p, "d": Vector2(cos(a), sin(a)), "t0": t})


func draw_outside(ci: CanvasItem) -> void:
	if c == Vector2.ZERO:
		return                     # begin() 之前不画
	# 鲸鱼（框外也画）
	for i in _whales.size():
		if not _alive(i, t):
			continue
		var pv := _path(i, t)
		var col := C.RED if _kind(i) == "r" else C.WHITE
		Whale.draw(ci, pv[0], pv[1], W, col)
	# 挡住的火花：2px 圆圈向外飞 10px，0.3 拍内消失
	for b in _bubbles:
		var age: float = t - b["t0"]
		if age < 0.0 or age > 0.3:
			continue
		var p: Vector2 = b["p"] + b["d"] * (10.0 * age / 0.3)
		ci.draw_arc(p.round(), 1.0, 0.0, TAU, 8, C.SYS, 1.0)
	# 头 3 拍的教学提示
	if t < HINT_BEATS:
		var l1 := "方向键：举盾"
		var l2 := "手机：往鲸鱼来的方向点"
		Px.text(ci, Vector2(c.x - Px.text_w(l1) / 2.0, box.position.y - 34.0), l1, C.WHITE)
		Px.text(ci, Vector2(c.x - Px.text_w(l2) / 2.0, box.position.y - 20.0), l2, C.GRAY)
