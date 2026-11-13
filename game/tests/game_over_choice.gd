extends SceneTree
## godot --headless --path game --log-file /tmp/game-over-choice.log --script res://tests/game_over_choice.gd
## 失败画面两个选项：「重新生成」（键盘）从当前阶段继续；「开启新对话」（触屏）整场从头开始，开场照常播放、物品重置

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _frames(count := 6) -> void:
	for i in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _frames()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames()


## 站着不动挨打，直到失败画面列出选项（轮到你时选「行动 → 查看」）
func _die(b) -> bool:
	var inp = root.get_node("Inp")
	for i in 20000:
		await process_frame
		if b.overlay._choice.size() > 0:
			return true
		b.hp = mini(b.hp, 1)
		if b.hud.btn_cursor and not b.hud._menu:
			inp.inject_tap(b.hud.to_global(C.btn_rect(1).get_center()))
			await _frames()
			inp.inject_tap(b.hud.to_global(b.hud._opt_rect(0).get_center()))
			await _frames()
			inp.inject_tap(b.hud.to_global(b.hud._opt_rect(0).get_center()))
			continue
		if i % 3 == 0 and not b.hud._menu:
			inp.inject_ok()
	_check(false, "站着不动必须会失败并出现选项")
	return false


func _start(dbg, jump: String):
	dbg.args["jump"] = jump
	dbg._startup_started = false
	change_scene_to_file.call_deferred("res://title/title.tscn")
	for i in 600:
		await process_frame
		var b = current_scene
		if b != null and b.get("hud") != null and b.hud.btn_cursor:
			return b
	_check(false, "必须进入战斗：" + jump)
	return null


func _run() -> void:
	Engine.time_scale = 20.0
	root.get_node("Settings").invincible = false   # 只改内存，不写回本机设置
	var dbg = root.get_node("Dbg")
	var inp = root.get_node("Inp")

	# 「重新生成」：键盘往下选、Z 确认 → 还在第二阶段，血回满，物品沿用阶段开头的
	var b = await _start(dbg, "P2")
	if b == null or not await _die(b):
		quit(1)
		return
	_check(b.overlay._choice[1][1] == "从第二阶段继续", "第二阶段失败时说明要写从第二阶段继续")
	_check(b.overlay._choice_sel == 0, "光标默认停在开启新对话")
	await _key(KEY_DOWN)
	_check(b.overlay._choice_sel == 1, "往下能选到重新生成")
	await _key(KEY_Z)
	for i in 300:
		await process_frame
		if b.hud.btn_cursor:
			break
	_check(current_scene == b, "重新生成不能换场景")
	_check(b.phase == 2 and b.hp == b.maxhp and b.overlay.fade == 0.0, "重新生成要回到第二阶段、血回满、黑幕撤掉")

	# 「开启新对话」：触屏点第一项 → 新的战斗场景，从开场重新来，物品重置
	b.items[0]["count"] = 0
	if not await _die(b):
		quit(1)
		return
	inp.inject_tap(b.overlay.to_global(b.overlay._choice_rect(0).get_center()))
	for i in 300:
		await process_frame
		if current_scene != b and current_scene != null and current_scene.get("hud") != null:
			break
	var nb = current_scene
	_check(nb != b and nb.scene_file_path == "res://battle/battle.tscn", "开启新对话要重新载入战斗")
	await _frames(10)
	_check(nb.story_dialogue and nb.phase == 1, "开启新对话要从开场重新播放")
	_check(nb.items[0]["count"] == Story.ITEMS[0]["count"], "开启新对话要重置物品")
	nb.return_to_title()
	await _frames(20)
	if current_scene:
		current_scene.queue_free()
	await _frames()
	if not _failed:
		print("PASS: 失败后可选重新生成（键盘，从当前阶段继续）或开启新对话（触屏，从开场重来）")
	quit(1 if _failed else 0)
