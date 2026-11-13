extends SceneTree
## godot --headless --path game --log-file /tmp/story-skip.log --script res://tests/story_skip.gd

var _failed := false
var _stage := 0
var _thought_done := false
const LONG_LINE := "这是一句用于测试回车推进的较长对白，下一句必须保留下来。"


func _initialize() -> void:
	call_deferred("_run")


func _frames(count := 4) -> void:
	for i in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)


func _key(code: Key, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	await _frames()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames()


func _sequence(b, kind: String, ui) -> void:
	for i in 2:
		match kind:
			"vn":
				await b.overlay.vn_say("half/G_blue", LONG_LINE)
			"bubble":
				await b.bubble.say(LONG_LINE)
			"chat":
				var advanced: bool = await ui.type_msg(i, 10.0, "voice_blue")
				await ui.wait_line(10.0, advanced)
		_stage += 1


func _thought(ui) -> void:
	await ui.type_think(10.0)
	_thought_done = true


func _run() -> void:
	for kind in ["vn", "bubble", "chat"]:
		var b = load("res://tests/fixtures/menu_battle.gd").new()
		root.add_child(b)
		current_scene = b
		b.story_dialogue = true
		var ui = load("res://battle/scene_ui.gd").new()
		ui.battle = b
		b.add_child(ui)
		for i in 2:
			ui.msgs.append({"who": "her", "text": LONG_LINE, "shown": 0})
		_stage = 0
		_sequence(b, kind, ui)
		await _frames(24) # 等立绘滑入，但对白仍在打字。
		await _key(KEY_ENTER)
		_check(_stage == 1, kind + "：一次回车应结束当前句，保留下一句")
		_check(is_instance_valid(b) and current_scene == b, kind + "：回车不能切换场景")
		await _key(KEY_ENTER, true)
		_check(_stage == 1, kind + "：长按重复事件不能推进下一句")
		b.set_paused(true)
		await _key(KEY_ENTER)
		_check(_stage == 1, kind + "：暂停时回车不能推进对白")
		b.set_paused(false)
		await _key(KEY_KP_ENTER)
		_check(_stage == 2, kind + "：小键盘回车应只结束第二句")
		b.free()
		await _frames()

	var b = load("res://tests/fixtures/menu_battle.gd").new()
	root.add_child(b)
	current_scene = b
	var ui = load("res://battle/scene_ui.gd").new()
	b.add_child(ui)
	ui.battle = b
	ui.think = {"on": true, "lines": [LONG_LINE, LONG_LINE, LONG_LINE], "shown": 0}
	_thought(ui)
	await _frames()
	await _key(KEY_ENTER)
	_check(ui.think["shown"] >= LONG_LINE.length() and ui.think["shown"] < LONG_LINE.length() * 2, "思考块：一次回车只跳过一行")
	await _key(KEY_ENTER)
	_check(ui.think["shown"] >= LONG_LINE.length() * 2 and not _thought_done, "思考块：第二次回车不能跳过第三行")
	await _key(KEY_ENTER)
	_check(_thought_done, "思考块：第三次回车才结束三句")
	# 已打完字的停留阶段，也应由一次回车结束。
	ui.msgs = [{"text": "短句", "shown": 0}, {"text": LONG_LINE, "shown": 0}]
	_stage = 0
	_sequence(b, "chat", ui)
	await _frames(30)
	_check(ui.msgs[0]["shown"] == 2 and _stage == 0, "短句应停留等待，而非自动跳到下一句")
	await _key(KEY_ENTER)
	_check(_stage == 1, "已显示完整的一句也应能回车推进")
	await _key(KEY_ENTER)
	b.free()
	await _frames()
	if not _failed:
		print("PASS: 聊天、VN、气泡、思考块均一次回车推进一句，且不会切换场景或连跳")
	quit(1 if _failed else 0)
