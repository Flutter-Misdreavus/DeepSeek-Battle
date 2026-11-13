extends Attack
## P2-1「鲸群」（鲸鱼标杆攻击，后面所有鲸鱼攻击照这个写法）
##
## 第二阶段「深海」，她第一次召唤鲸鱼。两段：
## A「洄游」[0.5, 9.6)：4 列小鲸鱼从框左边外面游进来，往右横穿整个框。每列整体上下起伏（正弦），
##   列里少两条鲸鱼，就是能钻过去的缺口。
## B「漩涡」[8, 17)：框中心开一个漩涡，鲸鱼沿 3 条旋臂往外游。每条鲸鱼自己边游边拐弯，所以旋臂是弯的；
##   旋臂整体在转，第 12.5 拍起反着转。
## - 鲸鱼位置都是 t 的纯函数；朝向用解析求导出来的速度（不用前后帧差分）。
## - 先在「不镜像」的坐标里算，最后统一用 _out() 做镜像。
## - 预警：每列进场前 1 拍，框左沿着这一列的鲸鱼位置冒蓝色气泡（缺口处没有）；
##   漩涡开始前 1.5 拍，中心画出 3 条旋臂的点状虚影。
## - mirror = true：从右往左游，漩涡转向也反过来。

const W := 20                              # 鲸鱼贴图宽（Whale.SIZES 里的值）
# ── A 洄游 ──
const COL_SPAWN := [0.5, 2.0, 3.5, 5.0]    # 第 k 列进场的拍
const COL_GAP := [4, 2, 5, 3]              # 第 k 列缺口的起始序号（连续 2 条不画）
const VX := 55.0                           # 每拍横向游的像素
const SP := 20.0                           # 列里相邻鲸鱼的竖直间距
const N_COL := 10                          # 每列鲸鱼数（比框高多出上下各一截，起伏时边上不会露空）
const AMP := 24.0                          # 起伏幅度
const OMEGA := PI / 2.0                    # 起伏角速度（弧度/拍，4 拍一个来回）
# ── B 漩涡 ──
const SPIN_WARN := 8.0
const SPIN_START := 9.5
const SPIN_END := 14.5                     # 最后一批鲸鱼放出的拍
const EMIT := 0.25                         # 每条旋臂每隔几拍放一条
const ARMS := 3
const VR := 60.0                           # 往外游的速度（像素/拍）
const CURL := 0.9                          # 每条鲸鱼自己的拐弯速度（弧度/拍）
const SPIN := 0.6                          # 旋臂整体转速（弧度/拍）
const FLIP_AT := 12.5                      # 从这一拍起反着转
const GROW := 0.3                          # 刚放出的鲸鱼从 0.3 倍长到 1 倍要几拍
const R_OUT := 150.0                       # 游出这么远就不管了

var _theta0 := 0.0


func setup() -> void:
	duration = 17.0
	box_size = Vector2(220, 130)
	stop_beat = 7.0
	# 让第一批鲸鱼游到红心起点那一圈（离中心约 45px）时，红心正好在两条旋臂中间
	var r0 := 45.0
	_theta0 = PI / 2.0 + PI / ARMS - (CURL + SPIN) * (r0 / VR)


func begin() -> void:
	pose("summon")


# ── 坐标 ──────────────────────────────────────────────────────

## 不镜像坐标 → 实际坐标；速度只翻 x
func _out(p: Vector2) -> Vector2:
	return Vector2(mx(p.x), p.y)


func _out_v(v: Vector2) -> Vector2:
	return Vector2(-v.x, v.y) if mirror else v


## A：第 k 列在拍 tt 的 x（不镜像）
func _col_x(k: int, tt: float) -> float:
	return box.position.x - 10.0 + (tt - COL_SPAWN[k]) * VX


## A：第 k 列第 i 条在拍 tt 的 y
func _col_y(k: int, i: int, tt: float) -> float:
	return box.position.y - 28.0 + i * SP + AMP * sin(k * PI / 2.0 + OMEGA * (tt - COL_SPAWN[k]))


func _col_v(k: int, tt: float) -> Vector2:
	return Vector2(VX, AMP * OMEGA * cos(k * PI / 2.0 + OMEGA * (tt - COL_SPAWN[k])))


func _col_alive(k: int) -> bool:
	return t >= COL_SPAWN[k] and _col_x(k, t) < box.end.x + 12.0


func _in_gap(k: int, i: int) -> bool:
	return i == COL_GAP[k] or i == COL_GAP[k] + 1


## B：旋臂在放出时刻 te 的整体转角（转速在 FLIP_AT 反向）
func _spin_angle(te: float) -> float:
	return SPIN * (minf(te, FLIP_AT) - SPIN_START) - SPIN * maxf(0.0, te - FLIP_AT)


## B：在 te 放出、属于第 j 条旋臂的鲸鱼，在拍 tt 的 [位置, 速度]（不镜像）
func _arm_whale(j: int, te: float, tt: float) -> Array:
	var a := tt - te
	var r := VR * a
	var th := _theta0 + TAU * j / ARMS + _spin_angle(te) + CURL * a
	var u := Vector2(cos(th), sin(th))
	var p := box.get_center() + u * r
	var v := u * VR + Vector2(-u.y, u.x) * r * CURL
	return [p, v]


## B：所有已放出、还在框附近的鲸鱼：[位置, 速度, 缩放]
func _arm_whales() -> Array:
	var out := []
	if t < SPIN_START:
		return out
	var n := int((minf(t, SPIN_END) - SPIN_START) / EMIT)
	for e in n + 1:
		var te := SPIN_START + e * EMIT
		if VR * (t - te) > R_OUT:
			continue
		var k := clampf((t - te) / GROW, 0.0, 1.0)
		for j in ARMS:
			var pv := _arm_whale(j, te, t)
			out.append([pv[0], pv[1], lerpf(0.3, 1.0, k)])
	return out


# ── 每帧 ──────────────────────────────────────────────────────

func tick(_dt: float) -> void:
	for k in COL_SPAWN.size():
		if crossed(COL_SPAWN[k] - 1.0):
			sfx("bubble")
		if crossed(COL_SPAWN[k]):
			sfx("whale")
		if not _col_alive(k):
			continue
		var x := _col_x(k, t)
		for i in N_COL:
			if not _in_gap(k, i):
				hz_circle(_out(Vector2(x, _col_y(k, i, t))), Whale.radius(W))
	if crossed(SPIN_WARN):
		sfx("whale", 0.8)
	if crossed(SPIN_START):
		sfx("spread")
	if crossed(FLIP_AT):
		sfx("whale", 1.2)
	for w in _arm_whales():
		hz_circle(_out(w[0]), Whale.radius(W) * w[2])


func _draw() -> void:
	var blink := fmod(t * 4.0, 1.0) < 0.6
	# A 预警：气泡
	for k in COL_SPAWN.size():
		var s: float = COL_SPAWN[k]
		if t >= s - 1.0 and t < s and blink:
			for i in N_COL:
				if not _in_gap(k, i):
					var p := _out(Vector2(box.position.x + 4.0, _col_y(k, i, s)))
					draw_arc(p.round(), 2.0, 0.0, TAU, 8, C.SYS, 1.0)
	# A 鲸鱼
	for k in COL_SPAWN.size():
		if not _col_alive(k):
			continue
		var x := _col_x(k, t)
		var v := _out_v(_col_v(k, t))
		for i in N_COL:
			if not _in_gap(k, i):
				Whale.draw(self, _out(Vector2(x, _col_y(k, i, t))), v, W)
	# B 预警：旋臂虚影（画成放出 1 拍后的样子）
	if t >= SPIN_WARN and t < SPIN_START and blink:
		for j in ARMS:
			var r := 6.0
			while r <= VR:
				var te := SPIN_START + 1.0 - r / VR
				var p: Vector2 = _arm_whale(j, te, SPIN_START + 1.0)[0]
				draw_rect(Rect2(_out(p).round() - Vector2.ONE, Vector2(2, 2)), C.SYS)
				r += 6.0
	# B 漩涡口
	if t >= SPIN_WARN and t < SPIN_END + 0.5:
		var c := box.get_center()
		var spin := t * 3.0 * (-1.0 if mirror else 1.0)
		draw_arc(c.round(), 7.0, spin, spin + PI * 1.4, 12, C.SYS_DIM, 2.0)
		draw_arc(c.round(), 4.0, -spin, -spin + PI * 1.2, 10, C.SYS, 1.0)
	# B 鲸鱼
	for w in _arm_whales():
		Whale.draw(self, _out(w[0]), _out_v(w[1]), W, C.WHITE, w[2])
