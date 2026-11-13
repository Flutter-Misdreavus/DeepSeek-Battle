extends Attack
## 知识蒸馏：三波、最后一波双教师，逐代分裂出有限转向的追踪鱼群。
## 所有个体读取同一份快照；固定 1/120 拍子步保证帧率与暂停不改变分裂时序。

const ENTRY_WARN := 0.5
const ENTRY_INSET := 32.0
const WAVE_START := [0.0, 8.0, 16.0]
const FIRST_SPLIT := [2.5, 10.5, 18.5]
const WIDTHS := [48, 32, 24, 16]
const SPEEDS := [0.0, 30.0, 34.0, 38.0]
const DELTAS := [0.0, deg_to_rad(55.0), deg_to_rad(28.0), deg_to_rad(14.0)]
const WARN_LEN := 0.75
const WARN_SCALE := 1.15
const GROW_LEN := 0.2
const SPLIT_GAP := 1.0
const NO_SPLIT := 1e9
const STEP := 1.0 / 120.0
const TURN := PI / 3.0
const NEIGHBOR_R := 80.0
const GEN3_LIFE := 4.0
var _tree: Array = []
var _built := false
var _simulated := 0.0


func setup() -> void:
	duration = 25.0
	box_size = Vector2(220, 140)
	stop_beat = 8.0
	_tree.clear()
	_built = false
	_simulated = 0.0
	var r := C.dodge_box(box_size.x, box_size.y)
	stop_spot = Vector2(r.end.x - 24.0, r.end.y - 14.0)


func begin() -> void:
	pose("summon")
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var previous_side := -1
	for wave in WAVE_START.size():
		var sides: Array[int] = [0, 1, 2, 3] # 上、右、下、左
		if previous_side >= 0:
			sides.erase(previous_side)
		var side := sides[rng.randi_range(0, sides.size() - 1)]
		previous_side = side
		for teacher in (2 if wave == 2 else 1):
			# 第三波随机选上下或左右相向入场，保证两位教师绝不来自同侧。
			var entry_side := side if teacher == 0 else (side + 2) % 4
			if mirror and entry_side in [1, 3]:
				entry_side = 4 - entry_side
			var u := rng.randf_range(0.25, 0.75)
			var start_u := clampf(u + rng.randf_range(-0.08, 0.08), 0.2, 0.8)
			if mirror and entry_side in [0, 2]:
				u = 1.0 - u
				start_u = 1.0 - start_u
			var p0 := Vector2.ZERO
			var p1 := Vector2.ZERO
			match entry_side:
				0:
					p0 = Vector2(box.position.x + box.size.x * start_u, box.position.y - 30.0)
					p1 = Vector2(box.position.x + box.size.x * u, box.position.y + ENTRY_INSET)
				1:
					p0 = Vector2(box.end.x + 30.0, box.position.y + box.size.y * start_u)
					p1 = Vector2(box.end.x - ENTRY_INSET, box.position.y + box.size.y * u)
				2:
					p0 = Vector2(box.position.x + box.size.x * start_u, box.end.y + 30.0)
					p1 = Vector2(box.position.x + box.size.x * u, box.end.y - ENTRY_INSET)
				3:
					p0 = Vector2(box.position.x - 30.0, box.position.y + box.size.y * start_u)
					p1 = Vector2(box.position.x + ENTRY_INSET, box.position.y + box.size.y * u)
			_tree.append({"gen": 0, "width": WIDTHS[0], "wave": wave, "p0": p0, "p1": p1,
				"pos": p0, "heading": (p1 - p0).angle(), "entry_side": entry_side,
				"birth": WAVE_START[wave], "split": FIRST_SPLIT[wave], "gone": false, "split_done": false})


func _alive(n: Dictionary, now: float) -> bool:
	return not n["gone"] and now >= n["birth"] and now < n["split"] and (n["gen"] < 3 or now < n["birth"] + GEN3_LIFE)


func _children(parent: Dictionary, now: float) -> void:
	var gen: int = parent["gen"] + 1
	var radius := Whale.radius(WIDTHS[gen]) * 0.6 + 3.0
	var side_dir := Vector2.from_angle(parent["heading"] + PI / 2.0)
	var fan: float = DELTAS[gen] * rng.randf_range(0.85, 1.15)
	var jitter := deg_to_rad(rng.randf_range(-8.0, 8.0))
	for side in [-1, 1]:
		var pos: Vector2 = parent["pos"] + side_dir * radius * side
		_tree.append({"gen": gen, "width": WIDTHS[gen], "wave": parent["wave"], "pos": pos,
			"heading": parent["heading"] + jitter + side * fan, "birth": now,
			"cruise": SPEEDS[gen] * rng.randf_range(0.9, 1.1),
			"split": now + SPLIT_GAP if gen < 3 else NO_SPLIT, "gone": false, "split_done": false})


func _step(now: float, dt: float) -> void:
	var snapshot: Array = []
	for i in _tree.size():
		var n: Dictionary = _tree[i]
		if n["gen"] == 0:
			n["pos"] = (n["p0"] as Vector2).lerp(n["p1"], clampf(now - n["birth"] - ENTRY_WARN, 0.0, 1.0))
		elif _alive(n, now - dt):
			snapshot.append({"i": i, "pos": n["pos"], "heading": n["heading"], "width": n["width"], "wave": n["wave"]})
	var updates: Array = []
	for item in snapshot:
		var n: Dictionary = _tree[item["i"]]
		var pos: Vector2 = item["pos"]
		var separation := Vector2.ZERO
		var alignment := Vector2.ZERO
		var center := Vector2.ZERO
		var neighbors := 0
		for other in snapshot:
			if other["i"] == item["i"] or other["wave"] != item["wave"]:
				continue
			var away: Vector2 = pos - other["pos"]
			var distance := away.length()
			if distance > NEIGHBOR_R:
				continue
			neighbors += 1
			center += other["pos"]
			alignment += Vector2.from_angle(other["heading"])
			var spacing := Whale.radius(item["width"]) + Whale.radius(other["width"]) + 6.0
			if distance < spacing:
				var direction := away / distance if distance > 0.001 else Vector2.from_angle(float(item["i"]) * 2.4)
				separation += direction * (1.0 - distance / spacing)
		var desired := (soul_pos() - pos).normalized() * 1.3 + separation * 2.0
		if neighbors > 0:
			desired += alignment.normalized() * 0.45 + (center / neighbors - pos).normalized() * 0.25
		var heading: float = item["heading"]
		if desired.length_squared() > 0.0001:
			heading += clampf(angle_difference(heading, desired.angle()), -TURN * dt, TURN * dt)
		var move_dt := minf(dt, maxf(0.0, float(n["split"]) - (now - dt)))
		updates.append({"i": item["i"], "heading": heading, "pos": pos + Vector2.from_angle(heading) * n["cruise"] * move_dt})
	for update in updates:
		var n: Dictionary = _tree[update["i"]]
		n["heading"] = update["heading"]
		n["pos"] = update["pos"]
	var split := false
	# 在所有父鲸鱼移动完后统一分裂，避免数组遍历顺序改变运动结果。
	var count := _tree.size()
	for i in count:
		var n: Dictionary = _tree[i]
		if not n["split_done"] and n["gen"] < 3 and now + 0.000001 >= n["split"]:
			n["split_done"] = true
			_children(n, n["split"])
			split = true
		if n["gen"] == 3 and (now >= n["birth"] + GEN3_LIFE or not box.grow(20.0).has_point(n["pos"])):
			n["gone"] = true
	_resolve_separation(now)
	if split:
		sfx("spinner_burst")


## 接触分离采用同步位置修正，避免有限转向的鱼迎头相撞后重叠成一团。
func _resolve_separation(now: float) -> void:
	var live: Array = []
	for n in _tree:
		if n["gen"] > 0 and _alive(n, now):
			live.append(n)
	for iteration in 12:
		var corrections: Array[Vector2] = []
		corrections.resize(live.size())
		corrections.fill(Vector2.ZERO)
		var changed := false
		for i in live.size():
			for j in i:
				var delta: Vector2 = live[i]["pos"] - live[j]["pos"]
				var distance := delta.length()
				var spacing := Whale.radius(live[i]["width"]) * _scale(live[i], now) + Whale.radius(live[j]["width"]) * _scale(live[j], now) + 6.0
				if distance >= spacing - 0.001:
					continue
				var dir := delta / distance if distance > 0.001 else Vector2.from_angle(float(i + j) * 2.4)
				var push := dir * (spacing - distance) * 0.5
				corrections[i] += push
				corrections[j] -= push
				changed = true
		for i in live.size():
			live[i]["pos"] += corrections[i]
		if not changed:
			break


func _pos(n: Dictionary, _now: float) -> Vector2:
	return n["pos"]


func _dir(n: Dictionary, _now: float) -> Vector2:
	return Vector2.from_angle(n["heading"])


func _scale(n: Dictionary, now: float) -> float:
	var s := 1.0
	if int(n["gen"]) > 0:
		s = lerpf(0.6, 1.0, clampf((now - float(n["birth"])) / GROW_LEN, 0.0, 1.0))
	var sp: float = n["split"]
	if sp < NO_SPLIT and now >= sp - WARN_LEN and now < sp:
		s *= lerpf(1.0, WARN_SCALE, (now - (sp - WARN_LEN)) / WARN_LEN)
	return s


func _color(n: Dictionary, now: float) -> Color:
	var sp: float = n["split"]
	if sp < NO_SPLIT and now >= sp - WARN_LEN and now < sp:
		var step := int((now - (sp - WARN_LEN)) / 0.125)
		return C.SYS if step % 2 == 1 else C.WHITE
	return C.WHITE


func tick(_dt: float) -> void:
	if not _built:
		_build()
	while _simulated + STEP <= t + 0.000001:
		_step(_simulated + STEP, STEP)
		_simulated += STEP
	for wave in WAVE_START.size():
		if crossed(WAVE_START[wave]):
			pose("summon")
			sfx("whale", 0.7)
	for n in _tree:
		if _alive(n, t):
			hz_circle(_pos(n, t), Whale.radius(n["width"]) * _scale(n, t))


func _caption() -> String:
	var wave := 0
	for i in WAVE_START.size():
		if t >= WAVE_START[i]:
			wave = i
	var s0: float = FIRST_SPLIT[wave]
	var stage := 0
	if t >= s0:
		stage = 1
	if t >= s0 + SPLIT_GAP:
		stage = 2
	if t >= s0 + SPLIT_GAP * 2.0:
		stage = 3
	match stage:
		1:
			return "蒸馏中：671B → 70B"
		2:
			return "蒸馏中：… → 70B → 7B"
		3:
			return "蒸馏中：… → 70B → 7B → 1.5B"
	return "蒸馏中：671B"


func _draw() -> void:
	if not _built:
		_build()
	# 入场侧先闪出气泡；位置提前锁定，教师不会突然从玩家身边生成。
	for n in _tree:
		if n["gen"] == 0 and t >= n["birth"] - ENTRY_WARN and t < n["birth"] + ENTRY_WARN:
			var edge: Vector2 = (n["p0"] as Vector2).clamp(box.position + Vector2.ONE * 2.0, box.end - Vector2.ONE * 2.0)
			var along := Vector2.RIGHT if n["entry_side"] in [0, 2] else Vector2.DOWN
			for i in 5:
				var p: Vector2 = edge + along * (i - 2) * 5.0
				draw_circle(p.round(), 1.0 + (i % 2), C.COLD if int(t * 8.0) % 2 == 0 else C.SYS)
	for n in _tree:
		if not _alive(n, t):
			continue
		Whale.draw(self, _pos(n, t), _dir(n, t), int(n["width"]), _color(n, t), _scale(n, t))
	Px.text(self, box.position + Vector2(4, 2), _caption(), C.SYS)
