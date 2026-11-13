extends Attack
## 终局「巨鲸」（56–72 拍）
##
## 一条 240px 宽的巨鲸从右往左横穿整个屏幕，头顶气孔不停地甩出成对反向的螺旋小鲸鱼，
## 第 4/8/12 拍还会朝上喷一道水柱。
## - 身体圆心 P(t) 是 t 的纯函数，前进方向用解析导数。
## - 判定圆 hz_circle(P, 70)；P.y 在 c.y±30，所以判定圆离框上下边最窄各 30px。
## - [0,1) 巨鲸还在框外：框右边内侧冒一串气泡预警。
## - 螺旋小鲸鱼从第 1 拍到 14.5 拍每 0.5 拍放两条，方向相反。位置用匀速圆弧公式。
## - 水柱前 0.5 拍：气孔冒小气泡、框顶两道竖杠闪烁；喷的 0.5 拍里是竖直伤害矩形。

const WHALE_W := 240
const BODY_R := 70.0
const SPIRAL_W := 16
const RELEASE_START := 1.0
const RELEASE_END := 14.5
const RELEASE_EVERY := 0.5
const SPIRAL_V := 70.0
const SPIRAL_OMEGA := 0.5
const JETS := [4.0, 8.0, 12.0]
const JET_LEN := 0.5
const WARN := 0.5

var _c := Vector2.ZERO


func setup() -> void:
	duration = 16.0
	box_size = Vector2(620, 260)


func begin() -> void:
	_c = box.get_center()


# ── 坐标（全是 t 的纯函数）──────────────────────────────────
func _body(tt: float) -> Vector2:
	return Vector2(
		box.end.x + 110.0 - 50.0 * tt,
		_c.y + 30.0 * sin(tt * PI / 8.0)
	)


func _body_v(tt: float) -> Vector2:
	return Vector2(-50.0, 30.0 * PI / 8.0 * cos(tt * PI / 8.0))


func _hole(tt: float) -> Vector2:
	return _body(tt) + Vector2(10.0, -72.0)


func _gone() -> bool:
	return _body(t).x < box.position.x - 140.0


## 所有已放出、还在框外 20px 以内的螺旋小鲸鱼：[位置, 前进方向, 缩放]
func _spirals() -> Array:
	var out: Array = []
	var last := minf(t, RELEASE_END)
	var k := 0
	while RELEASE_START + RELEASE_EVERY * k <= last + 0.0001:
		var e := RELEASE_START + RELEASE_EVERY * k
		for side in 2:
			var th0: float = -PI / 2.0 + 0.7 * k + (PI if side == 1 else 0.0)
			var tau := t - e
			if tau < 0.0:
				continue
			var th := th0 + SPIRAL_OMEGA * tau
			var p0 := _hole(e)
			var p: Vector2 = p0 + (SPIRAL_V / SPIRAL_OMEGA) * Vector2(
				sin(th) - sin(th0),
				-(cos(th) - cos(th0))
			)
			if not box.grow(20.0).has_point(p):
				continue
			var v := Vector2(cos(th), sin(th)) * SPIRAL_V
			out.append([p, v, clampf(tau / 0.2, 0.0, 1.0)])
		k += 1
	return out


# ── 每帧 ────────────────────────────────────────────────────
func tick(_dt: float) -> void:
	if crossed(0.0):
		sfx("whale", 0.6)
		pose("summon")
	if not _gone():
		hz_circle(_body(t), BODY_R)
	for w in _spirals():
		hz_circle(w[0], Whale.radius(SPIRAL_W))
	for j in JETS:
		if crossed(j):
			sfx("beam")
			if battle:
				battle.shake(2.0)
		if t >= j and t < j + JET_LEN:
			var h := _hole(t)
			if h.y > box.position.y:
				hz_rect(Rect2(h.x - 8.0, box.position.y, 16.0, h.y - box.position.y))


func _draw() -> void:
	# [0,1) 巨鲸还在框外：右边内侧的气泡预警
	if t < 1.0:
		var by := _body(t).y
		for i in 6:
			var u := fposmod(t * 0.75 + float(i) / 6.0, 1.0)
			var p := Vector2(box.end.x - 8.0, by + 60.0 - u * 120.0)
			draw_arc(p.round(), 1.5, 0.0, TAU, 8, C.SYS, 1.0)
	# 水柱预警：气孔小气泡 + 框顶两道竖杠
	for j in JETS:
		if t >= j - WARN and t < j:
			for i in 4:
				var ts: float = j - WARN + 0.125 * i
				var age := t - ts
				if age >= 0.0 and age < 0.5:
					var p := _hole(ts) + Vector2(0.0, -80.0 * age)
					draw_circle(p.round(), 1.0, C.SYS)
			if int(floor(t / 0.125)) % 2 == 0:
				var h := _hole(t)
				draw_rect(Rect2(h.x - 8.0, box.position.y, 2.0, 6.0), C.WHITE)
				draw_rect(Rect2(h.x + 8.0, box.position.y, 2.0, 6.0), C.WHITE)
	# 水柱
	for j in JETS:
		if t >= j and t < j + JET_LEN:
			var h := _hole(t)
			draw_rect(Rect2(h.x - 8.0, box.position.y, 16.0, h.y - box.position.y), C.WHITE)
	# 巨鲸
	if not _gone():
		Whale.draw(self, _body(t), _body_v(t), WHALE_W, Color(1, 1, 1, 0.9))
	# 螺旋小鲸鱼
	for w in _spirals():
		Whale.draw(self, w[0], w[1], SPIRAL_W, C.WHITE, lerpf(0.5, 1.0, w[2]))
