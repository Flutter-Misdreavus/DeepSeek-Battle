extends Attack
## 终局「Ctrl+A」
##
## 她抢走鼠标，在框里按下 Ctrl+A，把整个屏幕都选中了。
## - [0,1) 红光标从框左上角匀速拖到右下角，选框随箭尖长大，越过第 0 拍响 click / marquee。
## - 第 1 拍起选框 = 整个框。
## - 击杀路线：5 个缺口依次出现；每次 Delete 的 0.5 拍里，框里除缺口以外整片变红伤人。
##   最后一下 Delete 落在第 9 拍，同时响 delete + slam，抖得更狠。9.5 拍后什么都不画。
## - 饶恕路线：全程不伤人。全选后光标停在 Delete 键帽上发抖，第 6 拍松手淡出，她没有按。
##   第 2–6 拍，你可以把心移过去碰她的光标（箭头尖为左上角的 8×12 矩形）；碰到的那一刻
##   光标停止发抖、由红变白，响起 heal，键帽上方出现「……」，之后流程照旧。

const GAP_SIZE := Vector2(32, 28)
const GAP_OFFSETS := [
	Vector2(-40, -20),
	Vector2(10, 10),
	Vector2(-30, 40),
	Vector2(25, 35),
	Vector2(0, -15),
]
const DELETE_AT := [3.0, 4.5, 6.0, 7.5, 9.0]
const DELETE_LEN := 0.5
const FADE_LEN := 0.3
const CURSOR_MOVE := 0.4
const SELECT_ALPHA := 0.12
const DELETE_ALPHA := 0.85
const REACH_FROM := 2.0
const REACH_TO := 6.0
const CURSOR_HIT := Vector2(8, 12)

var _c := Vector2.ZERO
var _touched := false


func setup() -> void:
	duration = 10.0
	box_size = Vector2(620, 260)


func begin() -> void:
	_c = box.get_center()


func _spare() -> bool:
	return opts.get("route", "kill") == "spare"


func _drag_start() -> Vector2:
	return box.position + Vector2(4, 4)


func _drag_end() -> Vector2:
	return box.end - Vector2(12, 16)


func _opening_tip() -> Vector2:
	return _drag_start().lerp(_drag_end(), clampf(t, 0.0, 1.0))


## 缺口 i 的矩形（中心对齐）
func _gap_rect(i: int) -> Rect2:
	return Rect2(_c + GAP_OFFSETS[i] - GAP_SIZE * 0.5, GAP_SIZE)


## 击杀路线当前还画着的缺口：第 0 个从第 1 拍出现；第 i 个从上次删除开始出现。
func _visible_gaps() -> Array:
	var out: Array = []
	if _spare() or t < 1.0:
		return out
	for i in DELETE_AT.size():
		var start: float = 1.0 if i == 0 else DELETE_AT[i - 1]
		if t >= start and t < DELETE_AT[i] + DELETE_LEN:
			out.append(_gap_rect(i))
	return out


## 当前是否正处在某一次 Delete 的 0.5 拍里
func _deleting() -> bool:
	for d in DELETE_AT:
		if t >= d and t < d + DELETE_LEN:
			return true
	return false


## 框里红色选区的透明度。删除时 0.85，删除后 0.3 拍淡回选中色；其余时候 0.12。
func _fill_alpha() -> float:
	if _spare():
		return SELECT_ALPHA
	if _deleting():
		return DELETE_ALPHA
	for d in DELETE_AT:
		var f: float = d + DELETE_LEN
		if t >= f and t < f + FADE_LEN:
			return lerpf(DELETE_ALPHA, SELECT_ALPHA, (t - f) / FADE_LEN)
	return SELECT_ALPHA


## 一个矩形减去一个缺口，返回剩下的若干块（用于把选区里的缺口挖掉）
func _subtract(r: Rect2, h: Rect2) -> Array:
	var cut := r.intersection(h)
	if cut.size.x <= 0.0 or cut.size.y <= 0.0:
		return [r]
	var out: Array = []
	if cut.position.y > r.position.y:
		out.append(Rect2(r.position.x, r.position.y, r.size.x, cut.position.y - r.position.y))
	if cut.end.y < r.end.y:
		out.append(Rect2(r.position.x, cut.end.y, r.size.x, r.end.y - cut.end.y))
	var y0 := maxf(r.position.y, cut.position.y)
	var y1 := minf(r.end.y, cut.end.y)
	if cut.position.x > r.position.x:
		out.append(Rect2(r.position.x, y0, cut.position.x - r.position.x, y1 - y0))
	if cut.end.x < r.end.x:
		out.append(Rect2(cut.end.x, y0, r.end.x - cut.end.x, y1 - y0))
	return out


## 从整个框里挖掉所有可见缺口后剩下的矩形
func _outside_gaps(gaps: Array) -> Array:
	var rects: Array = [box]
	for h in gaps:
		var next: Array = []
		for r in rects:
			next.append_array(_subtract(r, h))
		rects = next
	return rects


## 击杀路线的光标：先跟着选框拖；之后在两次删除之间，用 0.4 拍移到下一个缺口的右下角外面。
func _kill_cursor() -> Vector2:
	if t < 1.0:
		return _opening_tip()
	var pos := _drag_end()
	var starts := [1.0, DELETE_AT[0] + DELETE_LEN, DELETE_AT[1] + DELETE_LEN, DELETE_AT[2] + DELETE_LEN, DELETE_AT[3] + DELETE_LEN]
	for i in starts.size():
		var s: float = starts[i]
		if t < s:
			break
		var target: Vector2 = _c + GAP_OFFSETS[i] + Vector2(20, 18)
		pos = pos.lerp(target, clampf((t - s) / CURSOR_MOVE, 0.0, 1.0))
	return pos


## 饶恕路线的光标：拖完框后移到 Delete 键帽上，停住并每帧抖 1px；被碰到后不再抖。
func _spare_cursor() -> Vector2:
	if t < 1.0:
		return _opening_tip()
	var key := _c + Vector2(4, 2)
	if t < 2.0:
		return _drag_end().lerp(key, clampf(t - 1.0, 0.0, 1.0))
	if _touched:
		return key
	return key + Vector2(0, roundf(sin(t * 20.0)))


## 饶恕路线：心第一次碰到她停在 Delete 上的光标
func _check_reach() -> void:
	if _touched or t < REACH_FROM or t >= REACH_TO or battle == null:
		return
	var cursor := Rect2(_spare_cursor(), CURSOR_HIT)
	if cursor.intersects(battle.soul.hitbox()):
		_touched = true
		battle.spare_touched = true
		sfx("heal")


func tick(_dt: float) -> void:
	# 共同开头：按下 Ctrl+A
	if crossed(0.0):
		sfx("click")
		sfx("marquee")
	if _spare():
		if crossed(6.0):
			sfx("menu_back")
		_check_reach()
		# [6,7.5) 选框、键帽、光标一起淡出
		modulate.a = clampf(1.0 - (t - 6.0) / 1.5, 0.0, 1.0) if t >= 6.0 else 1.0
		return
	# 击杀路线：5 次 Delete，最后一下落在第 9 拍的重拍上
	for i in DELETE_AT.size():
		if not crossed(DELETE_AT[i]):
			continue
		sfx("delete")
		if i == DELETE_AT.size() - 1:
			sfx("slam")
			if battle:
				battle.shake(7.0)
		else:
			if battle:
				battle.shake(3.0)
	# 删除期间，选区里除缺口以外都伤人
	if _deleting():
		for r in _outside_gaps(_visible_gaps()):
			if r.size.x > 0.0 and r.size.y > 0.0:
				hz_rect(r)


func _draw() -> void:
	if _spare():
		_draw_spare()
	else:
		_draw_kill()


func _draw_kill() -> void:
	if t >= 9.5:
		return
	var sel := box if t >= 1.0 else Rect2(box.position, _opening_tip() - box.position)
	var gaps := _visible_gaps()
	draw_rect(Rect2(sel.position.round(), sel.size.round()), Color(C.RED, _fill_alpha()))
	for h in gaps:
		draw_rect(Rect2(h.position.round(), h.size.round()), C.BLACK)
	Px.dashed(self, sel, C.RED, t * 12.0)
	for h in gaps:
		Px.dashed(self, h, C.WHITE, t * 12.0)
	if t < 2.0:
		_draw_labels()
	Px.cursor(self, _kill_cursor(), C.RED)


func _draw_spare() -> void:
	if t >= 7.5:
		return
	var sel := box if t >= 1.0 else Rect2(box.position, _opening_tip() - box.position)
	draw_rect(Rect2(sel.position.round(), sel.size.round()), Color(C.RED, SELECT_ALPHA))
	Px.dashed(self, sel, C.RED, t * 12.0)
	if t >= 1.0:
		_draw_keycap()
	if t < 2.0:
		_draw_labels()
	Px.cursor(self, _spare_cursor(), C.WHITE if _touched else C.RED)
	if _touched:
		var w := Px.text_w("……", 12)
		Px.text(self, Vector2(_c.x - w * 0.5, _c.y - 12.0 - 16.0), "……", C.WHITE, 12)


func _draw_labels() -> void:
	var w := Px.text_w("Ctrl+A", 24)
	Px.text(self, Vector2(_c.x - w * 0.5, box.position.y + 6), "Ctrl+A", C.WHITE, 24)
	var w2 := Px.text_w("全选", 12)
	Px.text(self, Vector2(_c.x - w2 * 0.5, box.position.y + 32), "全选", C.RED, 12)


func _draw_keycap() -> void:
	var r := Rect2(_c - Vector2(26, 12), Vector2(52, 24))
	draw_rect(r, C.BLACK)
	Px.frame(self, r, 1.0, C.WHITE)
	var w := Px.text_w("Delete", 12)
	Px.text(self, Vector2(_c.x - w * 0.5, _c.y - 6.0), "Delete", C.WHITE, 12)
