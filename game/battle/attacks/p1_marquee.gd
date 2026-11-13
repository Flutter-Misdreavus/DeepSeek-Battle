extends Attack
## P1-3「框选删除」
##
## 上下文满了，她用系统蓝色光标框选早期对话，按下 Delete 删掉。
## 前半段框选一块块旧对话，后半段「反选」：画出来的小框是安全区，框外整片都被删除。
## - 每一步：[s, s+1) 拖框，[s+1, s+2) 保持，[s+2, s+2.5) 删除伤人（白色闪一下），之后 0.3 拍淡出。
## - 两步之间光标从上一处终点直线移到下一步的起点，攻击开始前不画。
## - 框里一直躺着 6 行淡灰的旧对话；每一步删除结束后，被删过的那片区域永久变黑。
## - 选框在每步预警时生成，保留靠近当前玩家的安全区域；绘制和碰撞共用缓存。

const CHAT := [
	"用户：你好",
	"DeepSeek：您好，有什么可以帮您？",
	"用户：写一首诗",
	"DeepSeek：好的，以下是……",
	"用户：再改改",
	"DeepSeek：好的，修改如下……",
]

const STEPS := [
	{"s": 0.0, "inv": false}, {"s": 2.0, "inv": false},
	{"s": 4.0, "inv": false}, {"s": 6.0, "inv": false},
	{"s": 8.0, "inv": false}, {"s": 11.0, "inv": true},
	{"s": 14.0, "inv": true},
]
const SAFE_SIZE := Vector2(52, 44)
var _rects: Array = []
var _safe: Array[Rect2] = []
var _player_at_warning: Array[Vector2] = []


func setup() -> void:
	duration = 17.5
	box_size = Vector2(200, 130)
	stop_beat = 9.0
	_rects.clear()
	_safe.clear()
	_player_at_warning.clear()


func _safe_distance(r: Rect2, player: Vector2) -> float:
	var stand := Rect2(r.position + C.SOUL_HALF, r.size - 2.0 * C.SOUL_HALF)
	return player.distance_to(player.clamp(stand.position, stand.end))


func _sample_safe() -> Rect2:
	var player := soul_pos()
	for attempt in 32:
		var p := player - SAFE_SIZE * 0.5 + Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-36.0, 36.0))
		p = p.round().clamp(box.position, box.end - SAFE_SIZE)
		var r := Rect2(p, SAFE_SIZE)
		if _safe_distance(r, player) <= 32.0:
			return r
	# 近邻网格中的合法点，有限遍历且保留完整安全框。
	for y in range(int(box.position.y), int(box.end.y - SAFE_SIZE.y) + 1, 4):
		for x in range(int(box.position.x), int(box.end.x - SAFE_SIZE.x) + 1, 4):
			var r := Rect2(Vector2(x, y), SAFE_SIZE)
			if _safe_distance(r, player) <= 32.0:
				return r
	assert(false, "框选删除必须有可达安全区")
	return Rect2(box.position, SAFE_SIZE)


func _generate_step(i: int) -> void:
	var safe := _sample_safe()
	_safe.append(safe)
	_player_at_warning.append(soul_pos())
	if STEPS[i]["inv"]:
		_rects.append([safe])
		return
	# 在安全框以外选一至两块旧对话删除，不侵占已承诺的安全区。
	var regions := _outside(safe)
	var selected: Array = []
	var want := 1 if i < 2 else 2
	while not regions.is_empty() and selected.size() < want:
		var j := rng.randi_range(0, regions.size() - 1)
		var r: Rect2 = regions.pop_at(j)
		if r.size.x >= 12.0 and r.size.y >= 12.0:
			selected.append(r)
	assert(not selected.is_empty())
	_rects.append(selected)


func _step_rects(i: int) -> Array:
	return _rects[i] if i < _rects.size() else []


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
	for i in _rects.size():
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
	if idx + 1 >= _rects.size():
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
	while _rects.size() < STEPS.size() and t >= STEPS[_rects.size()]["s"]:
		_generate_step(_rects.size())
	for i in _rects.size():
		var s: float = STEPS[i]["s"]
		if crossed(s):
			sfx("marquee")
			pose("sweep" if i % 2 == 0 else "segF_sweep2")
		if crossed(s + 2.0):
			sfx("delete")
	# 删除期间才伤人：删掉的区域向内缩 1px 登记
	for i in _rects.size():
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
	# 0) 框里的旧对话；已经删过的区域涂黑，旧对话随之永久消失
	for i in CHAT.size():
		Px.text(self, Vector2(box.position.x + 6.0, box.position.y + 18.0 + i * 18.0), CHAT[i], C.GRAY_DIM)
	for i in _rects.size():
		if t < float(STEPS[i]["s"]) + 2.5:
			continue
		for r in _deleted_rects(i):
			_fill(r, C.BLACK)
	# 1) 选框内部的淡蓝（反选则是框外整片淡蓝）
	for i in _rects.size():
		var cur := _active_rects(i)
		if cur.is_empty():
			continue
		var col := Color(C.SYS, 0.12)
		if STEPS[i]["inv"]:
			for r in _outside(cur[0]):
				_fill(r, col)
		else:
			for r in cur:
				_fill(r, col)
	# 2) 删除的白块（白色 = 伤害），最后 0.3 拍淡出
	for i in _rects.size():
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
			_fill(r, Color(C.WHITE, a))
	# 3) 蚂蚁线画在白块上面，保证还看得见
	for i in _rects.size():
		for r in _active_rects(i):
			Px.dashed(self, r, C.SYS, t * 12.0)
	# 4) 反选提示：选中快结束时闪「反选」
	for i in _rects.size():
		if not STEPS[i]["inv"]:
			continue
		var s: float = STEPS[i]["s"]
		if t >= s + 1.5 and t < s + 2.0 and int(t * 4.0) % 2 == 0:
			Px.text(self, box.position + Vector2(4, 2), "反选", C.SYS)
	# 5) 蓝色系统光标
	if not _rects.is_empty():
		Px.cursor(self, _cursor_pos(), C.SYS)
	# 6) 开头 1 拍的提示
	if t < 1.0:
		var msg := "上下文已满，正在清理早期对话"
		var w := Px.text_w(msg)
		Px.text(self, Vector2(box.get_center().x - w / 2.0, box.position.y + 2.0), msg, C.SYS)
