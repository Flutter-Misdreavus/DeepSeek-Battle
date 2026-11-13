extends Attack
## P3-4「无限上下文」
##
## 弹幕框的四条边碎掉，「上下文长度：无限」——红心可以跑遍整个屏幕（按钮区、她身上都能去），
## 全屏鲸鱼弹幕分三段扫过来：鲸雨（带缺口）→ 鲸环 → 四臂漩涡。最后碎片飞回来重新拼成框，
## 把红心关回 200×120 的小框。
## - 所有鲸鱼位置 / 朝向都是 t 的纯函数；缺口在 setup() 里用 rng 预先生好。
## - 碎框 / 合框时每帧同时改 box、battle.box.rect、battle.soul.area，合框时把心推进去。
## - mirror 不支持（忽略）。

const W := 20
# A 鲸雨
const RAIN_START := 2.0
const RAIN_END := 8.0
const RAIN_EVERY := 0.5
const RAIN_DOWN := 60.0
const RAIN_SWAY := 10.0
const RAIN_STEP := 64.0
const RAIN_EDGE := 16.0
# B 鲸环
const RING_START := 8.0
const RING_N := 16
const RING_SPEED := 70.0
# C 四臂漩涡
const VORTEX_START := 14.0
const VORTEX_END := 17.0
const VORTEX_ARMS := 4
const VORTEX_EMIT := 0.25
const VORTEX_SPEED := 90.0
const VORTEX_CURL := 0.8
const VORTEX_SPIN := 0.7
# 合框
const MERGE_START := 17.5
const MERGE_END := 19.0
const TARGET := Vector2(200, 120)

var _vis := Rect2()
var _full := Rect2()
var _orig_fill := C.BLACK
var _orig_border := C.WHITE
var _captured := false

var _rain_rows := 0
var _rain_cols := 0
var _gaps: Array = []                # 每排缺口起始序号（去掉 k、k+1）

var _frags: Array = []               # {home: Vector2, size: Vector2, normal: Vector2, dir: Vector2, side: int}
var _shatter_rect := Rect2()


func setup() -> void:
	duration = 20.0
	box_size = Vector2(200, 120)
	no_stop = true
	_vis = Rect2(-battle.position, battle.get_viewport_rect().size)
	_full = Rect2(
		_vis.position.x + 4.0,
		_vis.position.y + 4.0,
		_vis.size.x - 8.0,
		_vis.size.y - 8.0
	)
	_rain_rows = int(ceil((RAIN_END - RAIN_START) / RAIN_EVERY))
	_rain_cols = int((_full.size.x - 2.0 * RAIN_EDGE) / RAIN_STEP) + 1
	for i in _rain_rows:
		_gaps.append(rng.randi_range(0, maxi(0, _rain_cols - 2)))


func begin() -> void:
	if battle and is_instance_valid(battle.box):
		_orig_fill = battle.box.fill
		_orig_border = battle.box.border_col
		_captured = true
	_shatter_rect = box


func _exit_tree() -> void:
	if _captured and battle and is_instance_valid(battle.box):
		battle.box.fill = _orig_fill
		battle.box.border_col = _orig_border


# ── 框 ──────────────────────────────────────────────────────

func _set_rect(r: Rect2) -> void:
	box = r
	if battle and is_instance_valid(battle.box):
		battle.box.rect = r
	if battle and is_instance_valid(battle.soul):
		battle.soul.area = r
		battle.soul.pos = battle.soul.clamp_in(battle.soul.pos)


func _lerp_rect(a: Rect2, b: Rect2, u: float) -> Rect2:
	return Rect2(a.position.lerp(b.position, u), a.size.lerp(b.size, u))


func _build_frags() -> void:
	_frags.clear()
	var r := _shatter_rect
	var c := r.get_center()
	for side in 4:
		for i in 12:
			var home: Vector2
			var size: Vector2
			var normal: Vector2
			match side:
				0:
					home = Vector2(r.position.x + (i + 0.5) * r.size.x / 12.0, r.position.y)
					size = Vector2(6, 2)
					normal = Vector2(0, -1)
				1:
					home = Vector2(r.position.x + (i + 0.5) * r.size.x / 12.0, r.end.y)
					size = Vector2(6, 2)
					normal = Vector2(0, 1)
				2:
					home = Vector2(r.position.x, r.position.y + (i + 0.5) * r.size.y / 12.0)
					size = Vector2(2, 6)
					normal = Vector2(-1, 0)
				_:
					home = Vector2(r.end.x, r.position.y + (i + 0.5) * r.size.y / 12.0)
					size = Vector2(2, 6)
					normal = Vector2(1, 0)
			_frags.append({
				"home": home, "size": size, "normal": normal,
				"dir": (home - c).normalized(), "side": side,
			})


func _merge_start(f: Dictionary) -> Vector2:
	var home: Vector2 = f["home"]
	match int(f["side"]):
		0:
			return Vector2(home.x, _full.position.y - 20.0)
		1:
			return Vector2(home.x, _full.end.y + 20.0)
		2:
			return Vector2(_full.position.x - 20.0, home.y)
	return Vector2(_full.end.x + 20.0, home.y)


# ── 鲸鱼（全是 t 的纯函数）──────────────────────────────────

func _is_gap(row: int, k: int) -> bool:
	var g: int = _gaps[row]
	return k == g or k == g + 1


func _rain(now: float) -> Array:
	var out: Array = []
	for i in _rain_rows:
		var st := RAIN_START + i * RAIN_EVERY
		if now < st:
			continue
		var y := _full.position.y - 10.0 + RAIN_DOWN * (now - st)
		if y > _full.end.y + 20.0:
			continue
		var sway := RAIN_SWAY * sin(now * 2.0 + i)
		for k in _rain_cols:
			if _is_gap(i, k):
				continue
			var x := _full.position.x + RAIN_EDGE + k * RAIN_STEP + sway
			var v := Vector2(RAIN_SWAY * 2.0 * cos(now * 2.0 + i), RAIN_DOWN)
			out.append([Vector2(x, y), v])
	return out


func _rings(now: float) -> Array:
	var out: Array = []
	for k in 6:
		var st := RING_START + k
		if now < st:
			continue
		var r := RING_SPEED * (now - st)
		for j in RING_N:
			var ang := TAU * j / RING_N + k * TAU / 32.0
			var u := Vector2(cos(ang), sin(ang))
			var p := Vector2(C.STAGE_FOOT.x, C.STAGE_FOOT.y - 100.0) + u * r
			if _full.grow(20.0).has_point(p):
				out.append([p, u * RING_SPEED])
	return out


## C：在 te 放出、属于第 j 条臂的鲸鱼在 now 的 [位置, 速度]
func _arm_whale(j: int, te: float, now: float) -> Array:
	var a := now - te
	var r := VORTEX_SPEED * a
	var th := -PI / 2.0 + TAU * j / VORTEX_ARMS + VORTEX_SPIN * (te - VORTEX_START) + VORTEX_CURL * a
	var u := Vector2(cos(th), sin(th))
	var p := Vector2(C.STAGE_FOOT.x, C.STAGE_FOOT.y - 100.0) + u * r
	var v := u * VORTEX_SPEED + Vector2(-u.y, u.x) * r * VORTEX_CURL
	return [p, v]


func _vortex(now: float) -> Array:
	var out: Array = []
	if now < VORTEX_START:
		return out
	var last := minf(now, VORTEX_END - 0.01)
	var n := int(floor((last - VORTEX_START) / VORTEX_EMIT))
	for e in n + 1:
		var te := VORTEX_START + e * VORTEX_EMIT
		for j in VORTEX_ARMS:
			var pv := _arm_whale(j, te, now)
			if _full.grow(20.0).has_point(pv[0]):
				out.append(pv)
	return out


# ── 每帧 ────────────────────────────────────────────────────

func tick(_dt: float) -> void:
	if crossed(0.5):
		sfx("crack")
		if battle:
			battle.shake(2.0)
	if crossed(1.0):
		_shatter_rect = box
		_build_frags()
		_set_rect(_full)
		if battle and is_instance_valid(battle.box):
			battle.box.border_col = Color(0, 0, 0, 0)
			battle.box.fill = Color(0, 0, 0, 0)
		pose("summon")
		sfx("shatter")
		if battle:
			battle.shake(4.0)
			if is_instance_valid(battle.overlay):
				battle.overlay.do_flash(0.3)
	if crossed(RAIN_START):
		sfx("whale")
	if crossed(RING_START):
		pose("twirl")
		sfx("whale")
	for k in 6:
		if crossed(RING_START + k):
			sfx("bubble")
	if crossed(VORTEX_START):
		sfx("whale")
	# 合框：线性收回；心被收紧的边界推进去
	if t >= MERGE_START and t < MERGE_END:
		var u := (t - MERGE_START) / (MERGE_END - MERGE_START)
		_set_rect(_lerp_rect(_full, C.dodge_box(TARGET.x, TARGET.y), u))
	if crossed(MERGE_END):
		_set_rect(C.dodge_box(TARGET.x, TARGET.y))
		if battle and is_instance_valid(battle.box):
			battle.box.border_col = _orig_border
			battle.box.fill = _orig_fill
		sfx("slam")
		if battle:
			battle.shake(3.0)
	# 伤害（第 17 拍起全部淡出、不再伤人）
	if t >= RAIN_START and t < 17.0:
		for w in _rain(t):
			hz_circle(w[0], Whale.radius(W))
		for w in _rings(t):
			hz_circle(w[0], Whale.radius(W))
		for w in _vortex(t):
			hz_circle(w[0], Whale.radius(W))


# ── 画 ──────────────────────────────────────────────────────

func _draw() -> void:
	var fade := clampf(1.0 - (t - 17.0) / 0.5, 0.0, 1.0)
	# 碎框向外飞
	if t >= 1.0 and t < 2.0:
		var age := t - 1.0
		for f in _frags:
			var p: Vector2 = f["home"] + f["dir"] * 120.0 * age
			draw_rect(Rect2((p - f["size"] * 0.5).round(), f["size"]), Color(1, 1, 1, 1.0 - age))
	# 「上下文长度：无限」
	if t >= 1.0 and t < 3.0:
		var s := "上下文长度：无限"
		var w := Px.text_w(s, 24)
		Px.text(self, Vector2(_full.get_center().x - w / 2.0, 140.0), s, C.RED, 24)
	# 鲸鱼
	if t < 17.5:
		for w in _rain(t):
			Whale.draw(self, w[0], w[1], W, Color(1, 1, 1, fade))
		for w in _rings(t):
			Whale.draw(self, w[0], w[1], W, Color(1, 1, 1, fade))
		for w in _vortex(t):
			Whale.draw(self, w[0], w[1], W, Color(1, 1, 1, fade))
	# 碎片飞回来（在地上/框外，交给 draw_outside 画，避免被正在缩小的框裁掉）


## 合框时碎片从屏幕四周飞回原位；这一段框正在缩小，画在裁剪层外面才看得见。
func draw_outside(ci: CanvasItem) -> void:
	if t < MERGE_START or t >= MERGE_END:
		return
	var u := (t - MERGE_START) / (MERGE_END - MERGE_START)
	for f in _frags:
		var p: Vector2 = _merge_start(f).lerp(f["home"], u)
		ci.draw_rect(Rect2((p - f["size"] * 0.5).round(), f["size"]), C.WHITE)
