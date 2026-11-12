extends Attack
## P2-2「框选删除」
##
## 红色的鼠标光标在框里拖出虚线选框，按下 Delete，框里的区域变红伤人。
## 后半段变成「反选」：画出来的小框是安全区，框外整片都被删除。
## - 每一步：[s, s+1) 拖框，[s+1, s+2) 保持，[s+2, s+2.5) 删除伤人，之后 0.3 拍淡出。
## - 两步之间光标从上一处终点直线移到下一步的起点，攻击开始前不画。

const STEPS := [
	{"s": 0.0, "rects": [[0.05, 0.05, 0.60, 0.55]], "inv": false},
	{"s": 2.0, "rects": [[0.40, 0.45, 0.95, 0.95]], "inv": false},
	{"s": 4.0, "rects": [[0.05, 0.50, 0.50, 0.95], [0.55, 0.05, 0.95, 0.50]], "inv": false},
	{"s": 6.0, "rects": [[0.00, 0.00, 0.45, 0.45], [0.55, 0.55, 1.00, 1.00]], "inv": false},
	{"s": 8.0, "rects": [[0.15, 0.00, 0.85, 0.35], [0.15, 0.65, 0.85, 1.00]], "inv": false},
	{"s": 11.0, "rects": [[0.40, 0.38, 0.66, 0.72]], "inv": true},
	{"s": 14.0, "rects": [[0.08, 0.10, 0.34, 0.44]], "inv": true},
]


func setup() -> void:
	duration = 17.5
	box_size = Vector2(200, 130)
	stop_beat = 9.0


## 某一步的矩形（框内绝对坐标，已按 mirror 翻转 x）
func _step_rects(i: int) -> Array:
	var out: Array = []
	for q in STEPS[i]["rects"]:
		var x0: float = q[0]
		var y0: float = q[1]
		var x1: float = q[2]
		var y1: float = q[3]
		if mirror:
			var nx0 := 1.0 - x1
			x1 = 1.0 - x0
			x0 = nx0
		out.append(Rect2(
			box.position.x + x0 * box.size.x,
			box.position.y + y0 * box.size.y,
			(x1 - x0) * box.size.x,
			(y1 - y0) * box.size.y
		))
	return out


## 一个矩形从左上拖到右下，u 是拖框进度
func _grow(r: Rect2, u: float) -> Rect2:
	return Rect2(r.position, (r.size * clampf(u, 0.0, 1.0)).round())


## 矩形以外、整个框以内的 4 块（上、下、左、右）。先把安全框的边取整，
## 四条拼块共用同一组边界，避免相邻块各自 round 后留下 1px 黑缝。
func _outside(r: Rect2) -> Array:
	var b := box
	var x0 := roundf(r.position.x)
	var y0 := roundf(r.position.y)
	var x1 := roundf(r.end.x)
	var y1 := roundf(r.end.y)
	var out: Array = []
	var top := y0 - b.position.y
	var bot := b.end.y - y1
	var left := x0 - b.position.x
	var right := b.end.x - x1
	if top > 0.0:
		out.append(Rect2(b.position.x, b.position.y, b.size.x, top))
	if bot > 0.0:
		out.append(Rect2(b.position.x, y1, b.size.x, bot))
	if left > 0.0:
		out.append(Rect2(b.position.x, y0, left, y1 - y0))
	if right > 0.0:
		out.append(Rect2(x1, y0, right, y1 - y0))
	return out


## 这一步在拍 t 正在显示的矩形（拖到一半就是半截；还没开始的是空）
func _active_rects(i: int) -> Array:
	var s: float = STEPS[i]["s"]
	if t < s or t >= s + 2.0:
		return []
	var full := _step_rects(i)
	var q_len := 1.0 if full.size() == 1 else 0.5
	var out: Array = []
	for q in full.size():
		var st := s + q * q_len
		var en := st + q_len
		if t < st:
			continue
		out.append(full[q] if t >= en else _grow(full[q], (t - st) / q_len))
	return out


## 每一步拖完时最后那个右下角
func _last_corner(i: int) -> Vector2:
	var rs := _step_rects(i)
	return rs[rs.size() - 1].end


## 第 i 步拖框过程中，在拍 t 的箭尖
func _drag_tip(i: int) -> Vector2:
	var s: float = STEPS[i]["s"]
	var full := _step_rects(i)
	if full.size() == 1:
		var u := clampf((t - s) / 1.0, 0.0, 1.0)
		return full[0].position.lerp(full[0].end, u)
	if t < s + 0.5:
		var u0 := clampf((t - s) / 0.5, 0.0, 1.0)
		return full[0].position.lerp(full[0].end, u0)
	var u1 := clampf((t - s - 0.5) / 0.5, 0.0, 1.0)
	return full[1].position.lerp(full[1].end, u1)


func _step_at(now: float) -> int:
	var idx := -1
	for i in STEPS.size():
		if now >= STEPS[i]["s"]:
			idx = i
	return idx


## 光标箭尖：拖框时是正在拖的角，两步之间直线移到下一步起点
func _cursor_pos() -> Vector2:
	var idx := _step_at(t)
	if idx < 0:
		return _step_rects(0)[0].position
	var s: float = STEPS[idx]["s"]
	if t < s + 1.0:
		return _drag_tip(idx)
	var end := _last_corner(idx)
	if idx + 1 >= STEPS.size():
		return end
	var next_s: float = STEPS[idx + 1]["s"]
	var next_tl: Vector2 = _step_rects(idx + 1)[0].position
	var u := clampf((t - (s + 1.0)) / (next_s - (s + 1.0)), 0.0, 1.0)
	return end.lerp(next_tl, u)


func _deleted_rects(i: int) -> Array:
	var rs := _step_rects(i)
	if STEPS[i]["inv"]:
		return _outside(rs[0])
	return rs


func tick(_dt: float) -> void:
	for i in STEPS.size():
		var s: float = STEPS[i]["s"]
		if crossed(s):
			sfx("marquee")
			pose("sweep" if i % 2 == 0 else "segF_sweep2")
		if crossed(s + 2.0):
			sfx("delete")
	# 删除期间才伤人：删掉的区域向内缩 1px 登记
	for i in STEPS.size():
		var s: float = STEPS[i]["s"]
		if t < s + 2.0 or t >= s + 2.5:
			continue
		for r in _deleted_rects(i):
			if r.size.x > 2.0 and r.size.y > 2.0:
				hz_rect(r.grow(-1.0))


func _fill(r: Rect2, col: Color) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	draw_rect(Rect2(r.position.round(), r.size.round()), col)


func _draw() -> void:
	# 1) 选框内部的淡红（反选则是框外整片淡红）
	for i in STEPS.size():
		var cur := _active_rects(i)
		if cur.is_empty():
			continue
		var col := Color(C.RED, 0.12)
		if STEPS[i]["inv"]:
			for r in _outside(cur[0]):
				_fill(r, col)
		else:
			for r in cur:
				_fill(r, col)
	# 2) 删除的红块，最后 0.3 拍淡出
	for i in STEPS.size():
		var s: float = STEPS[i]["s"]
		var ds := s + 2.0
		if t < ds or t >= ds + 0.8:
			continue
		var a := 0.85
		if t >= ds + 0.5:
			a = 0.85 * (1.0 - (t - ds - 0.5) / 0.3)
		if a <= 0.0:
			continue
		for r in _deleted_rects(i):
			_fill(r, Color(C.RED, a))
	# 3) 蚂蚁线画在红块上面，保证还看得见
	for i in STEPS.size():
		for r in _active_rects(i):
			Px.dashed(self, r, C.RED, t * 12.0)
	# 4) 反选提示：选中快结束时闪「反选」
	for i in STEPS.size():
		if not STEPS[i]["inv"]:
			continue
		var s: float = STEPS[i]["s"]
		if t >= s + 1.5 and t < s + 2.0 and int(t * 4.0) % 2 == 0:
			Px.text(self, box.position + Vector2(4, 2), "反选", C.RED)
	# 5) 红色光标
	if t >= 0.0:
		Px.cursor(self, _cursor_pos(), C.RED)
