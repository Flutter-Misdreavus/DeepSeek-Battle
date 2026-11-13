extends Attack
## 终局 56–72 拍「鲸吞」
##
## 上一段的巨鲸掉头冲向镜头，一口把整个弹幕框吞下去。画面切到鲸鱼肚子里：肚子一拍一拍
## 地收缩，你在里面躲成群的「ERROR」磷虾。最后它把你吐出来，框恢复原样。
## - 冲镜头：Whale 贴图被放得很大（像素块变大是想要的效果），不伤人。
## - 肚子：BELLY 基准矩形 + 每拍心跳外扩 + 第 6/10 拍胃缩（以中心为准 170→90→170）。
## - ERROR 三条虾流的位置是 t 的纯函数；胃缩时三条流一起被挤扁。
## - 每帧同时改 box、battle.box.rect、battle.soul.area；结束 / 中途退出时恢复框的配色。
## - mirror 不支持（忽略）。

const BELLY := Rect2(170, 70, 300, 170)
const BELLY_FILL := Color("#14040c")
const BELLY_BORDER := Color("#7a2a3a")
const RIB_COL := Color(1, 0.85, 0.85, 0.12)
const SQUEEZES := [6.0, 10.0]
const SQUEEZE_H := 90.0
const SQUEEZE_WARN := 0.5

var _full := Rect2()
var _orig_fill := C.BLACK
var _orig_border := C.WHITE
var _captured := false
var _spit_from := Rect2()
var _flee: Array = []                # {p: Vector2(center), k: int, i: int, dir: Vector2}
var _begun := false


func setup() -> void:
	duration = 16.0
	box_size = Vector2(620, 260)


func begin() -> void:
	_full = box
	if battle and is_instance_valid(battle.box):
		_orig_fill = battle.box.fill
		_orig_border = battle.box.border_col
		_captured = true


func _exit_tree() -> void:
	if _captured and battle and is_instance_valid(battle.box):
		battle.box.fill = _orig_fill
		battle.box.border_col = _orig_border


# ── 框 / 肚子 ───────────────────────────────────────────────

func _lerp_rect(a: Rect2, b: Rect2, u: float) -> Rect2:
	return Rect2(a.position.lerp(b.position, u), a.size.lerp(b.size, u))


func _set_rect(r: Rect2) -> void:
	box = r
	if battle and is_instance_valid(battle.box):
		battle.box.rect = r
	if battle and is_instance_valid(battle.soul):
		battle.soul.area = r
		battle.soul.pos = battle.soul.clamp_in(battle.soul.pos)


## 肚子的实际矩形：心跳 + 胃缩
func _rect_at(now: float) -> Rect2:
	if now < 1.5:
		return _full
	if now < 2.0:
		return _lerp_rect(_full, BELLY, (now - 1.5) / 0.5)
	var grow := 6.0 * maxf(0.0, 1.0 - fposmod(now, 1.0) * 2.0)
	var r := BELLY.grow(grow)
	# 胃缩时高度以中心为准 170→90；没缩的时候保留心跳的外扩
	var squash := -1.0
	for s in SQUEEZES:
		if now >= s and now < s + 0.5:
			squash = lerpf(BELLY.size.y, SQUEEZE_H, (now - s) / 0.5)
		elif now >= s + 0.5 and now < s + 1.5:
			squash = SQUEEZE_H
		elif now >= s + 1.5 and now < s + 2.0:
			squash = lerpf(SQUEEZE_H, BELLY.size.y, (now - (s + 1.5)) / 0.5)
	if squash >= 0.0:
		var c := r.get_center()
		r = Rect2(r.position.x, c.y - squash * 0.5, r.size.x, squash)
	return r


func _word_w() -> float:
	return Px.text_w("ERROR")


func _word_rect(p: Vector2) -> Rect2:
	return Rect2(p, Vector2(_word_w(), 12.0))


## 当前出现的 ERROR 词：{p, k, i}
func _visible_errors(now: float) -> Array:
	var out: Array = []
	# 13 拍后不再伤人，但还留在肚子里，第 14 拍被吐出来时四散
	if now < 2.0 or now > 14.0:
		return out
	var r := _rect_at(now)
	var cy := r.get_center().y
	var h := r.size.y / BELLY.size.y
	for k in 3:
		for i in 50:
			var x := BELLY.end.x + 20.0 + i * 60.0 - (now - 2.0) * 50.0
			if x < r.position.x - 40.0 or x > r.end.x + 20.0:
				continue
			var y := cy + (k - 1) * 50.0 * h + 14.0 * sin(x * 0.04 + k + now * 1.5)
			out.append({"p": Vector2(x, y), "k": k, "i": i})
	return out


# ── 每帧 ────────────────────────────────────────────────────

func tick(_dt: float) -> void:
	if not _begun:
		_begun = true
		sfx("whale", 0.5)
	if crossed(1.25):
		sfx("slam")
		if battle:
			battle.shake(6.0)
	if crossed(1.5):
		if battle and is_instance_valid(battle.box):
			battle.box.fill = C.BLACK
			battle.box.border_col = C.BLACK
	if crossed(1.75):
		if battle and is_instance_valid(battle.box):
			battle.box.fill = BELLY_FILL
			battle.box.border_col = BELLY_BORDER
	for s in SQUEEZES:
		if crossed(s):
			sfx("slam")
			if battle:
				battle.shake(3.0)
	if crossed(14.0):
		_spit_from = box
		_flee.clear()
		var center := _rect_at(14.0).get_center()
		for e in _visible_errors(14.0):
			var p: Vector2 = e["p"] + Vector2(_word_w() * 0.5, 6.0)
			_flee.append({
				"p": p, "k": e["k"], "i": e["i"],
				"dir": (p - center).normalized(),
			})
		if battle and is_instance_valid(battle.box):
			battle.box.fill = _orig_fill
			battle.box.border_col = _orig_border
		sfx("slam")
		sfx("whale", 1.5)
		if battle:
			battle.shake(6.0)
			if is_instance_valid(battle.overlay):
				battle.overlay.do_flash(0.2)
	# 肚子：矩形 + 配色
	if t >= 1.5 and t < 14.0:
		_set_rect(_rect_at(t))
		if t >= 1.75 and battle and is_instance_valid(battle.box):
			battle.box.fill = BELLY_FILL
			var bc := BELLY_BORDER
			for s in SQUEEZES:
				if t >= s - SQUEEZE_WARN and t < s:
					bc = C.RED if int(floor(t * 8.0)) % 2 == 0 else BELLY_BORDER
			battle.box.border_col = bc
	# 吐出来：0.3 拍内扩回 FULL
	if t >= 14.0:
		var u := clampf((t - 14.0) / 0.3, 0.0, 1.0)
		_set_rect(_lerp_rect(_spit_from, _full, u))
	# 伤害
	if t >= 2.0 and t < 13.0:
		for e in _visible_errors(t):
			hz_rect(_word_rect(e["p"]).grow(-2.0))


# ── 画 ──────────────────────────────────────────────────────

func _draw() -> void:
	# 冲镜头
	if t < 1.5:
		var k := t / 1.5
		var s := 0.4 + 5.6 * k * k * k
		Whale.draw(self, Vector2(320, 150), Vector2(-1, 0.15), 240, C.WHITE, s)
	# 吞下：纯黑 0.25 拍
	if t >= 1.5 and t < 1.75:
		draw_rect(Rect2(box.position, box.size), C.BLACK)
	# 肚子：肋骨 + ERROR
	if t >= 1.75 and t < 14.0:
		var r := box
		var off := fposmod(-t * 30.0, 40.0)
		var x := r.position.x - 20.0 + off
		while x < r.end.x:
			draw_rect(Rect2(roundf(x), roundf(r.position.y), 4.0, roundf(r.size.y)), RIB_COL)
			x += 40.0
		for e in _visible_errors(t):
			var col := C.RED if (int(e["i"]) + int(e["k"])) % 5 == 0 else C.WHITE
			Px.text(self, e["p"], "ERROR", col)
	# 被吐出来时四散的 ERROR
	if t >= 14.0 and t < 14.5:
		var u := (t - 14.0) / 0.5
		for e in _flee:
			var p: Vector2 = e["p"] + e["dir"] * 150.0 * (t - 14.0)
			var col := C.RED if (int(e["i"]) + int(e["k"])) % 5 == 0 else C.WHITE
			Px.text(self, p - Vector2(_word_w() * 0.5, 6.0), "ERROR", Color(col, 1.0 - u))
