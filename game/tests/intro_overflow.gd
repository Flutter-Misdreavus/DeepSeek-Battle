extends SceneTree
## godot --headless --path game --log-file /tmp/intro-overflow.log --script res://tests/intro_overflow.gd

var _failed := false
var _done := false


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)


func _play(ui) -> void:
	_done = false
	await ui.overflow_thought("嗯，用户又来了。", "烦死了。", "怎么还不", "去死")
	ui.msgs.append({"who": "her", "text": "这次，换我来。:)", "shown": 12})
	_done = true


func _key() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	Input.parse_input_event(event)
	for i in 3:
		await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	for i in 3:
		await process_frame


func _run() -> void:
	var b = load("res://tests/fixtures/menu_battle.gd").new()
	root.add_child(b)
	var ui = load("res://battle/scene_ui.gd").new()
	ui.battle = b
	b.add_child(ui)
	ui.msgs = [{"who": "user", "text": "...", "shown": 3}]
	_play(ui)
	var old_count := 0
	var old_increment := -1
	for i in range(1, 11):
		var count: int = ui._repeat_count_at(i / 10.0)
		_check(count - old_count > old_increment, "去死重复文字的生成速度应持续加快")
		old_increment = count - old_count
		old_count = count
	var full: int = ui.think["lines"].reduce(func(total, line): return total + line.length(), 0)
	var saw_overflow := false
	var saw_strike := false
	var clock := 0.0
	for i in 300:
		await process_frame
		clock += b.get_process_delta_time()
		if ui.think["shown"] == full:
			_check(ui._intro_elapsed <= 2.5, "整段思考文字必须在2.5秒内生成完成")
			_check(ui._thought_full_end > ui.get_viewport_rect().size.y - b.position.y, "文字必须真正溢出可见屏幕")
			saw_overflow = true
		if ui.think["strike"] > 0.0:
			_check(saw_overflow, "必须先溢出再划掉思考")
			saw_strike = true
		if _done:
			break
	_check(_done and saw_strike and clock < 2.5, "划线和下一句应在2.5秒内衔接")
	_check(ui.think["strike"] == 1.0, "所有思考文字必须完成划线")
	_check(ui.think.get("collapsed", false), "划线完成后必须收起整段思维链")
	ui.msgs = [{"who": "user", "text": "...", "shown": 3}]
	_play(ui)
	await _key()
	_check(not _done and ui._intro_elapsed < 0.8, "一次回车不能跳过整段思考")
	await _key()
	_check(not _done and ui._intro_elapsed < ui.THOUGHT_FILL_END, "第二次回车仍只推进当前句")
	await _key()
	for i in 20:
		await process_frame
	_check(_done and ui.think["strike"] == 1.0 and ui.think.get("collapsed", false), "快进最后一句仍需执行溢出、划线和收起")
	b.queue_free()
	await process_frame
	await process_frame
	if not _failed:
		print("PASS: 2.5秒内加速溢出、划线、收起思维链并显示下一句，回车仍逐句推进")
	quit(1 if _failed else 0)
