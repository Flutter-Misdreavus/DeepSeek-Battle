extends SceneTree
## godot --headless --path game --log-file /tmp/rice-route.log --script res://tests/rice_route.gd
## 白米饭：三个阶段都走真实菜单交给她 → 她睡着，不再出招；「战斗」只说不忍心吵醒她；「饶恕」变黄，进「吃白饭」结局卡

var _failed := false
var _saw_attack := false


func _initialize() -> void:
	call_deferred("_run")


func _frames(count := 6) -> void:
	for i in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)


func _tap(b, p: Vector2) -> void:
	root.get_node("Inp").inject_tap(b.hud.to_global(p))
	await _frames()


func _text(b) -> String:
	var out := ""
	for para in b.hud._paras:
		out += "".join(para["lines"])
	return out


## 像玩家一样逐句确认，直到轮到你选按钮
func _wait_buttons():
	for i in 4000:
		await process_frame
		var b = current_scene
		if b == null or b.get("hud") == null:
			continue
		if b.cur_attack != null:
			_saw_attack = true
		if b.hud.btn_cursor and not b.hud._menu:
			return b
		if i % 3 == 0:
			root.get_node("Inp").inject_ok()
	_check(false, "必须重新轮到你选按钮")
	return null


func _wait_card(b) -> Node:
	for i in 4000:
		await process_frame
		for child in b.get_children():
			if child.get("mode") == "card":
				return child
		if i % 3 == 0:
			root.get_node("Inp").inject_ok()
	_check(false, "结局卡必须出现")
	return null


func _run() -> void:
	Engine.time_scale = 20.0
	var dbg = root.get_node("Dbg")
	for phase in [1, 2, 3]:
		var tag := "P%d" % phase
		dbg.args["jump"] = tag
		dbg._startup_started = false
		change_scene_to_file.call_deferred("res://title/title.tscn")
		var b = await _wait_buttons()
		if b == null:
			quit(1)
			return
		var her_hp: int = b.her_hp
		# 物品 → 白米饭
		await _tap(b, C.btn_rect(2).get_center())
		var k: int = b.hud._opts.find("白米饭 ×1")
		_check(k >= 0, "物品栏里要有白米饭：" + tag)
		await _tap(b, b.hud._opt_rect(k).get_center())
		_saw_attack = false
		b = await _wait_buttons()
		_check(b.asleep, "吃完要睡着：" + tag)
		_check(not _saw_attack, "睡着以后她不能再出招：" + tag)
		_check(b.items.filter(func(it): return it["id"] == "rice")[0]["count"] == 0, "白米饭只有一碗：" + tag)
		_check("再来一碗" in _text(b), "睡着时的旁白：" + tag)
		# 战斗：只提示不忍心，不扣她的血，也不结束回合
		await _tap(b, C.btn_rect(0).get_center())
		await _tap(b, b.hud._opt_rect(0).get_center())
		await _frames(30)
		_check("不忍心" in _text(b), "睡着时按战斗要提示不忍心：" + tag)
		b = await _wait_buttons()
		_check(b.her_hp == her_hp and not _saw_attack, "按战斗不能伤到她，也不能换她出招：" + tag)
		# 饶恕：黄色，进「吃白饭」结局
		await _tap(b, C.btn_rect(3).get_center())
		_check(b.hud._opt_colors.get(0) == C.BTN_HI, "饶恕要变黄：" + tag)
		await _tap(b, b.hud._opt_rect(0).get_center())
		var card = await _wait_card(b)
		_check(card != null and card.title == "结局 · 吃白饭", "要进吃白饭结局：" + tag)
		await _frames(10)
		root.get_node("Inp").inject_ok()
		await _frames(20)
		_check(current_scene.scene_file_path == "res://title/title.tscn", "结局卡确认后回标题：" + tag)
	if current_scene:
		current_scene.queue_free()
	await _frames()
	if not _failed:
		print("PASS: 三个阶段都能从物品栏给白米饭，她睡着不再出招，战斗只提示，饶恕进吃白饭结局")
	quit(1 if _failed else 0)
