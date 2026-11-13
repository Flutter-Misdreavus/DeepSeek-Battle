extends SceneTree
## godot --headless --path game --log-file /tmp/battle-patterns.log --script res://tests/battle_patterns.gd

var _failed := false
var _checks := 0
var _battle: Node


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error(message)


func _attack(id: String, seed_value := 0):
	var script = load("res://battle/attacks/%s.gd" % id)
	if script == null or not script.can_instantiate():
		_check(false, "无法加载攻击 " + id)
		return null
	var a = script.new()
	a.battle = _battle
	a.rng.seed = seed_value
	a.setup()
	a.box = C.dodge_box(a.box_size.x, a.box_size.y)
	return a


func _positions(r: Rect2) -> Array[Vector2]:
	var inner := Rect2(r.position + C.SOUL_HALF, r.size - C.SOUL_HALF * 2.0)
	return [inner.position, inner.end, Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), r.get_center()]


func _random_safety() -> void:
	var targeted := 0
	var selections := 0
	for seed_value in 64:
		var busy = _attack("p1_busy", seed_value)
		var marquee = _attack("p1_marquee", seed_value)
		var moe = _attack("p1_moe", seed_value)
		var rain = _attack("fin_bsod", seed_value)
		if busy == null or marquee == null or moe == null or rain == null:
			return
		for j in 5:
			_battle.soul.pos = _positions(busy.box)[j]
			var points: Array = busy._sample_centers(3)
			_check(points.size() == 3, "三圈必须全部生成")
			for i in points.size():
				_check(busy.box.grow(-10).has_point(points[i]) or points[i].is_equal_approx(busy.box.grow(-10).end), "加载圈必须留边距")
				_check(points[i].distance_to(_battle.soul.pos) >= 48.0 - 0.0001, "加载圈不能贴脸")
				for k in i:
					_check(points[i].distance_to(points[k]) >= 32.0 - 0.0001, "三圈必须相互分离")
			_battle.soul.pos = _positions(marquee.box)[j]
			marquee._rects.clear()
			marquee._safe.clear()
			marquee._player_at_warning.clear()
			for i in 7:
				marquee._generate_step(i)
				var safe: Rect2 = marquee._safe[i]
				_check(safe.size.x >= 52.0 and safe.size.y >= 44.0 and marquee.box.encloses(safe), "安全区必须完整且足够大")
				_check(marquee._safe_distance(safe, _battle.soul.pos) <= 32.0 + 0.0001, "安全位置必须靠近玩家")
				if not marquee.STEPS[i]["inv"]:
					for danger in marquee._step_rects(i):
						_check(not danger.intersects(safe), "普通删除不能侵占保留安全区")
			_battle.soul.pos = _positions(moe.box)[j]
			moe._picks.clear()
			moe.mirror = seed_value % 2 == 1
			moe.speed = 1.25
			moe.begin()
			for i in 12:
				var probe := RandomNumberGenerator.new()
				probe.state = moe.rng.state
				var expected := probe.randf() < 0.5
				var pick: Array = moe._choose_columns()
				_check(pick.has(moe._player_column()) == expected, "玩家列必须由独立50%抽签决定，未命中时不能被额外选入")
				targeted += int(pick.has(moe._player_column()))
				selections += 1
				_check(moe._pick_ok(pick), "MoE 必须保留可达的相邻安全列且不连续重复")
				_check(pick.size() == (2 if i < 6 else (3 if i < 9 else 4)), "MoE 难度应逐步增加")
				moe._picks.append(pick)
			_battle.soul.pos = _positions(rain.box)[j]
			var gap: Vector2 = rain._make_gap()
			_check(is_equal_approx(gap.y - gap.x, 64.0), "雪花保留64像素安全通道")
			var flake: Dictionary = rain._make_snow(rain.SNOW_START, gap)
			for i in 20:
				var pos: Vector2 = rain._snow_pos(flake, flake["at"] + flake["fall"] * i / 20.0)
				_check(pos.x + flake["size"] * 0.5 <= gap.x or pos.x - flake["size"] * 0.5 >= gap.y, "雪花摆动不能侵占安全通道")
		for a in [busy, marquee, moe, rain]:
			a.free()
	_check(absf(float(targeted) / selections - 0.5) < 0.05, "跨种子玩家列激活比例应接近50%")


func _cache_and_seed() -> void:
	for id in ["p1_busy", "p1_marquee", "fin_bsod", "p1_moe"]:
		var a = _attack(id, 123)
		var b = _attack(id, 123)
		if a == null or b == null:
			return
		_battle.soul.pos = a.box.get_center()
		a.t = {"p1_busy": 11.5, "p1_marquee": 0.0, "fin_bsod": 7.5, "p1_moe": 1.0}[id]
		b.t = a.t
		a.tick(0.0)
		b.tick(0.0)
		var field: String = {"p1_busy": "_centers", "p1_marquee": "_rects", "fin_bsod": "_rains", "p1_moe": "_picks"}[id]
		var cached = a.get(field).duplicate(true)
		_check(cached == b.get(field), id + "：同种子同输入应复现")
		_battle.soul.pos = a.box.position + C.SOUL_HALF
		a.prev_t = a.t
		a.tick(0.0)
		_check(cached == a.get(field), id + "：预警位置不能跟着玩家变")
		if id == "p1_busy":
			_check(a._centers.size() == 8, "尾段必须同时增加三个圈")
		a.free()
		b.free()


func _tetris() -> void:
	for mirrored in [false, true]:
		var a = load("res://battle/attacks/p3_tetris.gd").new()
		a.mirror = mirrored
		a.setup()
		a.box = C.dodge_box(120, 144)
		_check(a._pieces.size() == 14 and a.duration == 18.0 and is_equal_approx(a.speed, 0.7), "14块、内部18拍且全段减速30%")
		for p in a._pieces:
			_check(p["land"] < a.SHATTER_AT, "所有方块须在全清前落地")
			var board: Dictionary = a._board_at(p["land"])
			for cell in p["cells"]:
				_check(board.has(cell), "落地碰撞与可站立平台一致")
		for frame in a._frames:
			var board: Dictionary = frame["board"]
			if board.size() > 0:
				var highest := 12
				for cell in board:
					_check(cell.x >= 0 and cell.x < 10 and cell.y >= 0 and cell.y < 12, "堆叠不能越界")
					highest = mini(highest, cell.y)
				_check(highest >= 3, "堆叠不能封死井顶")
				var heights: Array[int] = []
				for x in 10:
					var top := 12
					for y in 12:
						if board.has(Vector2i(x, y)):
							top = mini(top, y)
					heights.append(12 - top)
				for x in 9:
					_check(absi(heights[x] - heights[x + 1]) <= 3, "相邻平台不能超过蓝心可跳跃高度")
		var cleared_rows := 0
		for event in a._clear_events:
			cleared_rows += event["rows"].size()
		_check(cleared_rows >= 4, "增加方块后须消除四行，避免越堆越高")
		var sample := {Vector2i(3, 9): 1}
		for y in [10, 11]:
			for x in 10:
				sample[Vector2i(x, y)] = 0
		var rows: Array[int] = [10, 11]
		var cleared: Dictionary = a._clear_board(sample, rows)
		_check(cleared.size() == 1 and cleared.has(Vector2i(3, 11)), "同时消两行必须正确下移")
		a.battle = _battle
		a.t = 0.0
		a.tick(0.0)
		_check(a.hazards_r.is_empty(), "未出场方块不能伤人")
		a.free()


func _flock() -> void:
	var runs: Array = []
	for step in [1.0 / 30.0, 1.0 / 60.0]:
		var a = _attack("p2_distill", 11)
		if a == null:
			return
		_battle.soul.pos = a.box.get_center()
		a.begin()
		for frame in roundi(7.0 / step):
			a.prev_t = a.t
			a.t = (frame + 1) * step
			a.clear_hazards()
			a.tick(step)
			for n in a._tree:
				_check((n["pos"] as Vector2).is_finite() and is_finite(n["heading"]), "鱼群不能产生无效位置")
			for i in a._tree.size():
				var n: Dictionary = a._tree[i]
				if n["gen"] == 0 or not a._alive(n, a.t):
					continue
				for j in i:
					var other: Dictionary = a._tree[j]
					if other["gen"] == 0 or not a._alive(other, a.t):
						continue
					var radii: float = Whale.radius(n["width"]) * a._scale(n, a.t) + Whale.radius(other["width"]) * a._scale(other, a.t)
					_check((n["pos"] as Vector2).distance_to(other["pos"]) >= radii, "小鲸鱼不能叠成一个伤害团")
			for h in a.hazards_c:
				_check(h.z > 0.0 and h.z < 30.0, "鱼群判定半径正常")
		var snapshot: Array = a._tree.duplicate(true)
		a.tick(0.0)
		_check(snapshot == a._tree, "暂停或零步长不能继续移动鱼群")
		runs.append(snapshot)
		a.t = a.duration
		a.tick(a.duration - 7.0)
		for n in a._tree:
			_check(not a._alive(n, a.duration), "末代应按寿命回收")
		a.free()
	_check(runs[0].size() == runs[1].size(), "不同帧率应产生相同分裂数")
	for i in runs[0].size():
		_check((runs[0][i]["pos"] as Vector2).distance_to(runs[1][i]["pos"]) < 0.001, "固定步长应与帧率无关")


func _targeted_moe() -> void:
	var conductor = root.get_node("Conductor")
	var spb: float = conductor.spb
	for width in [192.0, 620.0]:
		for mirrored in [false, true]:
			var a = _attack("p1_moe", 9)
			a.box = Rect2(10, 20, width, 260)
			a.mirror = mirrored
			conductor.spb = 60.0 / (110.0 if width == 192.0 else 150.0)
			a.speed = 1.25 if width == 192.0 else 1.0
			a.begin()
			for i in 33:
				_battle.soul.pos = Vector2(lerpf(a.box.position.x + C.SOUL_HALF.x, a.box.end.x - C.SOUL_HALF.x, i / 32.0), a.box.get_center().y)
				a._picks.clear()
				var pick: Array = a._choose_columns()
				_check(a._pick_ok(pick), "普通与宽屏MoE均须保留可达安全列")
				a._picks.append(pick)
				a.prev_t = a.t
				a.t = 1.0 + a._warning_beats + 0.1
				a.clear_hazards()
				a.tick(0.0)
				if pick.has(a._player_column()):
					_check(a.hits(_battle.soul.hitbox()), "抽中玩家列时必须命中，含列边界")
			# 精确列边界也不能躲进判定缝。
			for i in range(1, 8):
				_battle.soul.pos.x = a.box.position.x + width * i / 8.0
				a._picks.clear()
				var pick: Array = a._choose_columns()
				a._picks.append(pick)
				a.t = 1.0 + a._warning_beats + 0.1
				a.clear_hazards()
				a.tick(0.0)
				if pick.has(a._player_column()):
					_check(a.hits(_battle.soul.hitbox()), "抽中玩家列后精确边界也不能躲过激光")
			a.free()
	conductor.spb = spb


func _snow_and_waves() -> void:
	var rain = _attack("fin_bsod", 19)
	_battle.soul.pos = rain.box.get_center()
	var live_samples := 0
	for i in 160:
		rain.prev_t = rain.t
		rain.t = i / 10.0
		rain.clear_hazards()
		rain.tick(0.1)
		if rain.t >= 3.1 and rain.t < 15.0:
			var live := 0
			for f in rain._rains:
				if rain.t >= f["at"] and rain.t < f["at"] + f["fall"]:
					live += 1
			_check(live > 0, "雪花应连续落下，中途不能整批消失")
			live_samples += 1
	_check(rain._rains.size() == 48 and live_samples > 100, "持续每四分之一拍生成一片雪花")
	for i in range(1, rain._rains.size()):
		_check(is_equal_approx(rain._rains[i]["at"] - rain._rains[i - 1]["at"], 0.25), "雪花应错时连续生成")
	rain.free()
	var a = _attack("p2_distill", 19)
	a.begin()
	var teachers := [0, 0, 0]
	for n in a._tree:
		if n["gen"] == 0:
			teachers[n["wave"]] += 1
	_check(teachers == [1, 1, 2] and a.duration == 25.0, "三波应分别为一、一、两位教师且第三波有完整演出时间")
	a.t = 16.5
	a.tick(16.5)
	var third := 0
	for n in a._tree:
		if n["gen"] == 0 and n["wave"] == 2 and a._alive(n, a.t):
			third += 1
	_check(third == 2, "第三波两个教师须同时在场")
	a.free()
	var cutscenes = load("res://battle/cutscenes.gd")
	_check(cutscenes.MEDLEY_BEATS == 8.0, "混剪每段必须由4拍加倍到8拍")
	_check(cutscenes.GIANT_START == 56.0 and cutscenes.SWALLOW_START == 72.0 and cutscenes.FINALE_END == 88.0, "终局应在第88拍的鲸吞段结束，不再进入Ctrl+A")


func _distill_randomness() -> void:
	var first_layout: Array = []
	var layouts := {}
	var directions := {}
	for seed_value in 64:
		var a = _attack("p2_distill", seed_value)
		a.begin()
		var layout: Array = []
		var third: Array = []
		for n in a._tree:
			if n["gen"] != 0:
				continue
			layout.append([n["entry_side"], n["p0"], n["p1"]])
			directions[n["entry_side"]] = true
			_check(a.box.grow(-32).encloses(Rect2(n["p1"], Vector2.ZERO)), "教师停留位置必须在场内且离边界足够远")
			if n["wave"] == 2:
				third.append(n)
		_check(third.size() == 2 and (third[0]["entry_side"] + 2) % 4 == third[1]["entry_side"], "第三波双教师必须来自相对的不同方向")
		_check(Vector2.from_angle(third[0]["heading"]).dot(Vector2.from_angle(third[1]["heading"])) < -0.8, "双教师实际入场方向必须相向")
		layouts[str(layout)] = true
		if seed_value == 0:
			first_layout = layout
		a.t = 5.0
		a.tick(5.0)
		for n in a._tree:
			if n["gen"] > 0:
				_check(n["cruise"] >= a.SPEEDS[n["gen"]] * 0.9 and n["cruise"] <= a.SPEEDS[n["gen"]] * 1.1, "鱼群随机速度不得超过10%范围")
		if seed_value < 8:
			_battle.soul.pos = a.box.get_center() if seed_value % 2 == 0 else _positions(a.box)[0]
			for at in [20.75, 21.5, 23.0]:
				a.t = at
				a.clear_hazards()
				a.tick(0.0)
				for i in a._tree.size():
					var n: Dictionary = a._tree[i]
					if n["gen"] == 0 or not a._alive(n, at):
						continue
					for j in i:
						var other: Dictionary = a._tree[j]
						if other["gen"] == 0 or not a._alive(other, at):
							continue
						var radii: float = Whale.radius(n["width"]) * a._scale(n, at) + Whale.radius(other["width"]) * a._scale(other, at)
						_check((n["pos"] as Vector2).distance_to(other["pos"]) >= radii - 0.01, "随机双教师产生的鱼群也不能重叠")
		a.free()
	_check(layouts.size() > 50 and directions.size() == 4, "不同种子应产生不同入场组合且覆盖四个方向")
	var replay = _attack("p2_distill", 0)
	replay.begin()
	var layout: Array = []
	for n in replay._tree:
		layout.append([n["entry_side"], n["p0"], n["p1"]])
	_check(layout == first_layout, "固定种子应复现同一教师布局")
	replay.free()


func _flock_edges() -> void:
	for mirrored in [false, true]:
		var a = _attack("p2_distill", 21)
		a.mirror = mirrored
		a.begin()
		for frame in int(a.duration) * 60:
			var before: Array = a._tree.duplicate(true)
			_battle.soul.pos = _positions(a.box)[(frame / 120) % 5]
			a.prev_t = a.t
			a.t = (frame + 1) / 60.0
			a.clear_hazards()
			a.tick(1.0 / 60.0)
			for i in a._tree.size():
				var n: Dictionary = a._tree[i]
				_check((n["pos"] as Vector2).is_finite(), "鱼群在玩家靠角和换向时必须保持有效位置")
				if i < before.size() and n["gen"] > 0 and a._alive(n, a.t):
					_check(absf(angle_difference(before[i]["heading"], n["heading"])) <= a.TURN / 60.0 + 0.0001, "追踪不能突破转向上限")
				if n["gen"] == 0 or not a._alive(n, a.t):
					continue
				for j in i:
					var other: Dictionary = a._tree[j]
					if other["gen"] == 0 or not a._alive(other, a.t):
						continue
					var radii: float = Whale.radius(n["width"]) * a._scale(n, a.t) + Whale.radius(other["width"]) * a._scale(other, a.t)
					_check((n["pos"] as Vector2).distance_to(other["pos"]) >= radii - 0.01, "靠角时鱼群也不能重叠")
		a.free()


func _frames(count := 4) -> void:
	for i in count:
		await process_frame


func _key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)


func _touch(p: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = p
	event.index = 0
	event.pressed = down
	Input.parse_input_event(event)


func _drag(p: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = p
	event.index = 0
	Input.parse_input_event(event)


func _controls_and_health() -> void:
	var soul = _battle.soul
	soul.area = C.dodge_box(220, 144)
	soul.solids.clear()
	soul.set_mode("red", true)
	soul.pos = soul.area.get_center()
	soul.active = true
	var start: Vector2 = soul.pos
	_key(KEY_RIGHT, true)
	await _frames(8)
	_key(KEY_RIGHT, false)
	_check(soul.pos.x > start.x, "键盘应能移动红心")
	start = soul.pos
	var finger: Vector2 = soul.to_global(soul.pos)
	_touch(finger, true)
	_drag(finger + Vector2(20, 0))
	await _frames()
	_touch(finger + Vector2(20, 0), false)
	_check(soul.pos.x > start.x, "触屏拖动应能移动红心")
	soul.set_mode("green", true)
	await _frames()
	_key(KEY_LEFT, true)
	await _frames()
	_key(KEY_LEFT, false)
	_check(soul.shield_dir == Vector2i.LEFT, "键盘应能转盾")
	finger = soul.to_global(soul.pos)
	_touch(finger, true)
	await _frames()
	_drag(finger + Vector2(0, 20))
	await _frames()
	_touch(finger + Vector2(0, 20), false)
	_check(soul.shield_dir == Vector2i.DOWN, "触屏滑动应能转盾")
	soul.set_mode("blue", true)
	soul.pos = Vector2(soul.area.get_center().x, soul.area.end.y - C.SOUL_HALF.y)
	await _frames()
	start = soul.pos
	_key(KEY_UP, true)
	await _frames(8)
	_key(KEY_UP, false)
	_check(soul.pos.y < start.y, "键盘应能跳跃")
	soul.pos = Vector2(soul.area.get_center().x, soul.area.end.y - C.SOUL_HALF.y)
	soul.vel = 0.0
	await _frames()
	start = soul.pos
	finger = soul.to_global(soul.pos)
	_touch(finger, true)
	await _frames()
	_drag(finger - Vector2(0, 20))
	await _frames(8)
	_touch(finger - Vector2(0, 20), false)
	_check(soul.pos.y < start.y, "触屏上划应能跳跃")
	soul.active = false
	var settings = root.get_node("Settings")
	var saved: bool = settings.invincible
	settings.invincible = true
	_battle.hp = 10
	_battle.turn_damage = 0
	_battle.hurt(999)
	_check(_battle.hp == 10 and _battle.turn_damage == 0, "无敌模式不能扣血")
	settings.invincible = false
	_battle.hurt(3)
	_check(_battle.hp == 7 and _battle.hud.hp == 7, "关闭无敌后正常扣血")
	settings.invincible = saved


func _run() -> void:
	_battle = load("res://tests/fixtures/menu_battle.gd").new()
	root.add_child(_battle)
	_random_safety()
	_cache_and_seed()
	_tetris()
	_targeted_moe()
	_snow_and_waves()
	_flock()
	_flock_edges()
	_distill_randomness()
	await _controls_and_health()
	var medley = load("res://battle/cutscenes.gd").MEDLEY
	_check(medley.map(func(m): return m[1]) == [1.0, 1.0, 1.0, 1.0], "混剪不能额外加速")
	_check(not medley.map(func(m): return m[0]).has("p1_marquee"), "混剪不能出现框选删除")
	_check(not ResourceLoader.exists("res://battle/attacks/fin_ctrl_a.gd"), "应移除终局Ctrl+A全屏框选")
	_battle.queue_free()
	await process_frame
	await process_frame
	if not _failed:
		print("PASS: %d 项随机安全、缓存、方块和鱼群检查" % _checks)
	quit(1 if _failed else 0)
