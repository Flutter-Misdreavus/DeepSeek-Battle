extends SceneTree
## godot --headless --path game --log-file /tmp/ending-navigation.log --script res://tests/ending_navigation.gd

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


func _card(b) -> Node:
	for child in b.get_children():
		if child.get("mode") == "card":
			return child
	return null


func _wait_card() -> Node:
	for i in 600:
		await process_frame
		var b = current_scene
		if b == null or b.get("overlay") == null:
			continue
		if _card(b) != null:
			return b
		# 像玩家一样逐句确认剧情，不使用会在结局直接退出的--auto。
		if i % 3 == 0 and (b.overlay.vn_on or b.bubble.on):
			root.get_node("Inp").inject_ok()
	_check(false, "结局卡必须正常出现")
	return null


func _run() -> void:
	Engine.time_scale = 20.0
	var dbg = root.get_node("Dbg")
	var inp = root.get_node("Inp")
	for route in ["end_kill", "end_spare"]:
		for confirm in ["enter", "z", "tap"]:
			dbg.args["jump"] = route
			dbg._startup_started = false
			change_scene_to_file.call_deferred("res://title/title.tscn")
			var b = await _wait_card()
			if b == null:
				quit(1)
				return
			_check(b._finished and not b.soul.active, "结局卡期间战斗必须已经停止")
			var title: String = _card(b).title
			_check(title == ("结局 · 结束进程" if route == "end_kill" else "结局 · 饶恕"), "必须保留对应结局")
			if confirm == "tap":
				inp.inject_tap(Vector2(320, 300))
				await _frames()
			else:
				await _key(KEY_ENTER if confirm == "enter" else KEY_Z)
			await _frames(20)
			_check(current_scene.scene_file_path == "res://title/title.tscn", "结局确认后必须停在标题：" + route + "/" + confirm)
			_check(not current_scene.starting and not dbg.start_battle_on_launch(), "调试跳转和同一次确认不能再次启动战斗")
			_check(inp.pause_rect == Rect2(), "标题页不能残留战斗暂停热区")
			_check(not ResourceLoader.exists("res://battle/frame.gd"), "应完整移除顶部模拟窗口栏")
			# 返回标题后，只有新的确认才会开始一局，而且不能沿用上局调试结局。
			await _key(KEY_Z)
			await _frames()
			_check(current_scene.scene_file_path == "res://battle/battle.tscn" and current_scene.story_dialogue, "新游戏应正常播放开场而非再次跳入旧结局")

	# 原P1-1调试入口同样只触发一次；手机暂停按钮不抢占顶部点击。
	dbg.args["jump"] = "P1-1"
	dbg._startup_started = false
	change_scene_to_file.call_deferred("res://title/title.tscn")
	await _frames(12)
	var battle = current_scene
	_check(battle.scene_file_path == "res://battle/battle.tscn", "调试首次启动仍应跳到战斗")
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = inp.pause_rect.get_center()
	touch.pressed = true
	Input.parse_input_event(touch)
	await _frames()
	_check(battle._paused, "触屏左下角暂停应正常工作")
	touch.pressed = false
	Input.parse_input_event(touch)
	await _key(KEY_ESCAPE)
	_check(not battle._paused, "Esc应正常恢复战斗")
	battle.return_to_title()
	await _frames(20)
	_check(current_scene.scene_file_path == "res://title/title.tscn", "战斗中回标题也不能触发调试重进")
	if current_scene:
		current_scene.queue_free()
	await _frames()
	if not _failed:
		print("PASS: 两种结局的回车/Z/触屏均返回并停留在标题，调试跳转只生效一次，手机暂停正常")
	quit(1 if _failed else 0)
