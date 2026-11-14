extends SceneTree
## godot --headless --path game --log-file /tmp/reject-patterns.log --script res://tests/reject_patterns.gd

const EARLY_ARRIVALS := [1.0, 2.0, 3.0, 4.0, 5.0, 5.5, 6.0, 6.5, 7.5, 8.5, 9.5, 10.0]
var failed := false
var checks := 0
var battle: Node
var attack_script: GDScript
var round_done := false

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(message)

func make_attack(seed_value: int, mirrored := false):
	var a = attack_script.new()
	a.battle = battle
	a.rng.seed = seed_value
	a.mirror = mirrored
	a.setup()
	a.box = Rect2(288, 220, 64, 64)
	a.begin()
	return a

func geometry_and_randomness() -> void:
	var layouts := {}
	var coverage := {}
	for seed_value in 128:
		var a = make_attack(seed_value)
		var repeat = make_attack(seed_value)
		var mirrored = make_attack(seed_value, true)
		check(a._whales == repeat._whales and a._whales == mirrored._whales, "相同种子必须复现，镜像不能改变随机抽样")
		check(a.ARRIVALS.size() == 20 and a.ARRIVALS.slice(0, 12) == EARLY_ARRIVALS and a.V == 60.0, "保留20条、前12条原节奏和鲸鱼速度")
		check(is_equal_approx(a._arrive(12), 11.0) and is_equal_approx(a.duration - a._arrive(19), 1.0), "后段首条保持11拍，末条之后保留完整收尾时间")
		check(a._arrive(19) + a.R_HIT / a.V < a.duration, "最后一条鲸鱼必须能完整经过判定区")
		var average_interval: float = (a._arrive(11) - a._arrive(0)) / 11.0
		for i in range(13, 20):
			check(is_equal_approx(a._arrive(i) - a._arrive(i - 1), average_interval), "后8条的密度必须与前12条的平均密度一致")
		layouts[str(a._whales)] = true
		var reds := 0
		var snapshot: Array = a._whales.duplicate(true)
		var rng_state: int = a.rng.state
		for i in 20:
			var red: bool = a._kind(i) == "r"
			coverage[str([red, a._side(i)])] = true
			if i < 12:
				check(not red, "前12条只能是直线白鲸")
			else:
				reds += int(red)
				if i >= 14:
					check(not (a._kind(i) == a._kind(i - 1) and a._kind(i) == a._kind(i - 2)), "后八条不能连续三条同色")
			if red:
				check(a._arrive(i) - a.EXIST >= 8.5, "红鲸不能提前进入前12条白鲸的教学段")
			var initial: Vector2 = a.DIR_VEC[a._side(i)]
			var guard: Vector2 = a._guard_dir(i)
			check(guard == (-initial if red else initial), "红鲸反向格挡，白鲸迎面格挡")
			for j in 25:
				var rem := 2.4 - j * 0.11
				var now: float = a._arrive(i) - rem
				var pv: Array = a._path(i, now)
				var mv: Array = mirrored._path(i, now)
				var offset: Vector2 = pv[0] - a.c
				var velocity: Vector2 = pv[1]
				check(offset.is_finite() and velocity.is_finite(), "轨迹不得产生异常数值")
				check((mv[0] - a.c).distance_to(Vector2(-offset.x, offset.y)) < 0.001, "左右镜像必须同步反转曲线")
				if not red or rem >= a.TURN_BEATS:
					check(absf(offset.cross(initial)) < 0.001 and velocity.distance_to(-initial * a.V) < 0.001, "白鲸和红鲸绕行前必须直线前进")
				var delta := 0.0001
				var numeric: Vector2 = (a._path(i, now + delta)[0] - a._path(i, now - delta)[0]) / (2.0 * delta)
				check(numeric.distance_to(velocity) < 0.5, "绘制朝向必须与实际移动方向一致")
			for rem in [a.TURN_BEATS, 0.0]:
				var now: float = a._arrive(i) - rem
				check(a._path(i, now - 0.00001)[1].distance_to(a._path(i, now + 0.00001)[1]) < 0.1, "曲线与直线段速度应连续")
			check(a._path(i, a._arrive(i))[0].distance_to(a.c + guard * a.R_HIT) < 0.001, "落点必须与格挡侧一致")
			check(a._path(i, a._arrive(i) + 0.2)[1].distance_to(-guard * a.V) < 0.001, "未挡住后必须继续向心直线移动")
		check(reds == 4, "后8条必须4白4红")
		check(a._whales == snapshot and a.rng.state == rng_state, "查询轨迹不得重新随机")
		for attack in [a, repeat, mirrored]:
			attack.free()
	check(layouts.size() > 100 and coverage.size() == 8, "不同种子应产生不同布局，并覆盖红白鲸全部四向")

func block_checks() -> void:
	for mirrored in [false, true]:
		var a = make_attack(57, mirrored)
		for i in 20:
			for correct in [true, false]:
				a._blocked.fill(true)
				a._blocked[i] = false
				a._bubbles.clear()
				a.clear_hazards()
				a.prev_t = a._arrive(i) - 0.01
				a.t = a._arrive(i) + 0.25
				battle.soul.shield_dir = a._guard_dir(i) * (1 if correct else -1)
				a.tick(0.26)
				check(a._blocked[i] == correct, "只有正确方向才能挡住鲸鱼")
				if correct:
					check(a._bubbles.size() == 6 and a.hazards_c.is_empty(), "成功格挡应消除伤害并产生气泡")
					check(a._bubbles[0]["p"].distance_to(a.c + Vector2(a._guard_dir(i)) * a.R_HIT) < 0.001, "气泡必须出现在最终格挡侧")
				else:
					check(a._bubbles.is_empty() and a.hits(battle.soul.hitbox()), "错误格挡应继续进入玩家判定")
		a.free()

func frames() -> void:
	for i in 4:
		await process_frame

func input_checks() -> void:
	var a = make_attack(57)
	battle.soul.set_mode("green", true)
	battle.soul.active = true
	battle.soul.pos = a.c
	var keys := {Vector2i.UP: KEY_UP, Vector2i.DOWN: KEY_DOWN, Vector2i.LEFT: KEY_LEFT, Vector2i.RIGHT: KEY_RIGHT}
	for i in 20:
		var d: Vector2i = a._guard_dir(i)
		for touch in [false, true]:
			var event: InputEvent
			if touch:
				var tap := InputEventScreenTouch.new()
				tap.position = battle.soul.to_global(a.c + Vector2(d) * 40.0)
				tap.pressed = true
				event = tap
			else:
				var key := InputEventKey.new()
				key.keycode = keys[d]
				key.pressed = true
				event = key
			Input.parse_input_event(event)
			await frames()
			check(battle.soul.shield_dir == d, "键盘与触屏都应能选择实际格挡侧")
			a._blocked.fill(true)
			a._blocked[i] = false
			a.prev_t = a._arrive(i) - 0.01
			a.t = a._arrive(i)
			a.tick(0.01)
			check(a._blocked[i], "实际输入必须能够格挡红白鲸")
			event.pressed = false
			Input.parse_input_event(event)
			await frames()
	battle.soul.active = false
	a.free()

func play_round() -> void:
	await battle.run_attack("p2_reject")
	round_done = true

func pause_checks() -> void:
	var settings = root.get_node("Settings")
	var saved: bool = settings.invincible
	settings.invincible = true
	Engine.time_scale = 6.0
	battle.phase = 2
	root.get_node("Conductor").play("p2")
	play_round()
	var paused_once := false
	while not round_done:
		await process_frame
		var a = battle.cur_attack
		if a != null and a.t > 11.0 and not paused_once:
			var time: float = a.t
			var layout: Array = a._whales.duplicate(true)
			battle.set_paused(true)
			await frames()
			check(a.t == time and a._whales == layout, "实际战斗暂停时必须冻结时间和随机布局")
			battle.set_paused(false)
			await process_frame
			check(a.t - time < 0.5, "恢复时不能补算暂停时间造成鲸鱼突跳")
			paused_once = true
	check(paused_once and battle.cur_attack == null, "整招应正常完成并退出绿心攻击")
	settings.invincible = saved
	Engine.time_scale = 1.0

func _run() -> void:
	battle = load("res://tests/fixtures/menu_battle.gd").new()
	root.add_child(battle)
	attack_script = load("res://battle/attacks/p2_reject.gd")
	if not attack_script or not attack_script.can_instantiate():
		quit(1)
		return
	battle.soul.pos = Vector2(320, 252)
	geometry_and_randomness()
	block_checks()
	await input_checks()
	await pause_checks()
	battle.queue_free()
	await process_frame
	print("%s: %d 项拒绝随机、曲线、镜像、格挡及输入检查" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)
