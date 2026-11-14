extends SceneTree
## godot --headless --fixed-fps 60 --path game --log-file /tmp/finale-infinite.log --script res://tests/finale_infinite.gd

var failed := false
var done := false
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(message)

func play(b, route: String) -> void:
	done = false
	await b.do_finale(route)
	done = true

func frames(count := 4) -> void:
	for i in count:
		await process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func flow(b, route: String, controls := false) -> void:
	var conductor = root.get_node("Conductor")
	var seen: Array[String] = []
	var starts := {"fin_bsod": 8.0, "fin_infinite": 24.0, "fin_giant": 56.0, "fin_swallow": 72.0}
	var paused_once := false
	var tested_controls := false
	var tested_merge := false
	play(b, route)
	for frame in 12000:
		await process_frame
		if done:
			break
		var a = b.cur_attack
		if a == null or a.t <= 0:
			continue
		var id: String = a.get_script().resource_path.get_file().get_basename()
		if not seen.has(id):
			seen.append(id)
			check(starts.has(id), "终局不能再调用混剪攻击")
			check(absf(a.t - (conductor.beat - starts[id]) * a.speed) <= b.get_process_delta_time() / conductor.spb * a.speed + 0.0001, "串段必须以绝对拍号为时间原点")
			check(b.soul.mode == "red" and a.damage == 5 and not b.stop["on"], "终局必须保持红心、伤害5和无停止按钮")
		if id != "fin_infinite":
			continue
		check(a.speed == 0.625, "无限上下文必须将20拍映射为32拍")
		if a.t > 3.0 and a.t < 16.0:
			check(b.box.border_col.a == 0.0 and b.soul.area == a._full, "碎框后应允许在整个屏幕移动")
		if a.t > 5.0 and not paused_once:
			var old_t: float = a.t
			var old_beat: float = conductor.beat
			b.set_paused(true)
			await frames(10)
			check(a.t == old_t and conductor.beat == old_beat, "暂停时攻击和绝对音乐时钟必须一起冻结")
			b.set_paused(false)
			paused_once = true
		if controls and a.t > 6.0 and not tested_controls:
			b.soul.pos = a._full.get_center()
			var before: Vector2 = b.soul.pos
			key(KEY_RIGHT, true)
			await frames(8)
			key(KEY_RIGHT, false)
			check(b.soul.pos.x > before.x, "全屏红心必须能由键盘移动")
			await frames()
			before = b.soul.pos
			var finger: Vector2 = b.soul.to_global(before)
			var tap := InputEventScreenTouch.new()
			tap.position = finger
			tap.pressed = true
			Input.parse_input_event(tap)
			await frames()
			var drag := InputEventScreenDrag.new()
			drag.position = finger + Vector2(0, -20)
			Input.parse_input_event(drag)
			await frames()
			tap.pressed = false
			tap.position = drag.position
			Input.parse_input_event(tap)
			check(b.soul.pos.y < before.y, "全屏红心必须能由触屏拖动")
			tested_controls = true
		if a.t >= 19.0:
			check(b.box.rect == load("res://battle/cutscenes.gd").FULL and b.soul.area == b.box.rect, "合框必须回到终局大框")
			check(b.soul.pos == b.soul.clamp_in(b.soul.pos) and b.box.border_col == Color.WHITE, "合框后玩家不能越界且边框应恢复")
			tested_merge = true
	check(done and paused_once and tested_merge, "两条路线都必须完整播放无限上下文")
	check(seen == ["fin_bsod", "fin_infinite", "fin_giant", "fin_swallow"], "终局顺序必须正确且没有重复攻击")
	check(conductor.beat >= 88.0 and conductor.beat <= 88.0 + b.get_process_delta_time() / conductor.spb + 0.001, "终局必须在88拍结束，允许一帧误差")
	await frames()
	check(b.box.fill == Color.BLACK and b.box.border_col == Color.WHITE and b.enemy.height == C.STAGE_H, "结束后必须恢复普通舞台样式")

func run() -> void:
	var settings = root.get_node("Settings")
	var saved: bool = settings.invincible
	settings.invincible = true
	for route in ["kill", "spare"]:
		var b = load("res://tests/fixtures/menu_battle.gd").new()
		root.add_child(b)
		b.phase = 3
		await flow(b, route, route == "spare")
		check(b.finale_done and (b.spare_ready if route == "spare" else true), "终局状态必须正常推进")
		b.queue_free()
		await frames()
	# 真正受伤导致终局中断，再使用保存的终局检查点重试。
	var b = load("res://tests/fixtures/menu_battle.gd").new()
	root.add_child(b)
	b.phase = 3
	settings.invincible = false
	play(b, "spare")
	var forced := false
	for frame in 10000:
		await process_frame
		if done:
			break
		var a = b.cur_attack
		if a != null and a.get_script().resource_path.ends_with("fin_infinite.gd") and a.t > 5.0:
			b.hp = 1
			b.soul.iframe = 0.0
			b.soul.pos = a._rain(a.t)[0][0]
			forced = true
	print("失败注入：forced=", forced, " done=", done, " abort=", b._abort, " hp=", b.hp)
	check(forced and done and b._abort == "gameover", "无限上下文中必须能正常失败并退出攻击")
	await frames()
	check(b.box.fill == Color.BLACK and b.box.border_col == Color.WHITE, "失败后必须恢复边框与背景")
	check(b._checkpoint.get("finale_route") == "spare", "失败时应保留终局检查点")
	b._abort = ""
	b.hp = b.maxhp
	settings.invincible = true
	await flow(b, b._checkpoint["finale_route"])
	b.queue_free()
	await frames()
	settings.invincible = saved
	print("%s: %d 项终局顺序、时序、移动、暂停及失败重试检查" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)
