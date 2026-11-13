extends SceneTree
## godot --headless --path game --log-file /tmp/menu-navigation.log --script res://tests/menu_navigation.gd

var _battle: Node
var _failed := false
var _turn_ended := false


func _initialize() -> void:
	call_deferred("_run")


func _frames() -> void:
	for i in 4:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)


func _turn() -> void:
	await _battle._player_turn()
	_turn_ended = true


func _tap(p: Vector2) -> void:
	root.get_node("Inp").inject_tap(_battle.hud.to_global(p))
	await _frames()


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _frames()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames()


func _run() -> void:
	# 同时覆盖一列菜单、两列菜单，以及行动的第二层菜单。
	for button in 4:
		var depths := 2 if button == 1 else 1
		for depth in depths:
			for back in ["left", "center", "right", "x", "shift", "android"]:
				_battle = load("res://tests/fixtures/menu_battle.gd").new()
				root.add_child(_battle)
				_turn_ended = false
				_turn()
				await _frames()
				await _tap(C.btn_rect(button).get_center())
				if depth == 1:
					await _key(KEY_Z)
				_check(_battle.hud._menu, "必须进入子菜单")
				var counts: Array = _battle.items.map(func(item): return item["count"])
				match back:
					"left":
						# 此位置此前同时命中右列第一项，导致返回变成使用物品。
						await _tap(Vector2(557, 205))
					"center":
						await _tap(_battle.hud.BACK_RECT.get_center())
					"right":
						await _tap(Vector2(601, 205))
					"x":
						await _key(KEY_X)
					"shift":
						await _key(KEY_SHIFT)
					"android":
						root.get_node("Inp")._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
						await _frames()
				var label := "button=%d depth=%d back=%s" % [button, depth, back]
				_check(not _battle.hud._menu and _battle.hud.btn_cursor, "必须回到主菜单：" + label)
				_check(not _turn_ended, "返回不能消耗回合：" + label)
				_check(counts == _battle.items.map(func(item): return item["count"]), "返回不能消耗物品：" + label)
				_battle.queue_free()
				await _frames()
	if not _failed:
		print("PASS: 30 种子菜单返回操作，均回到主菜单且不消耗回合或物品")
	quit(1 if _failed else 0)
