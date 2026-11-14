extends SceneTree
## 验证实际战斗时钟下，上下文压缩在普通和加速回合中均减速30%。

var _done := false
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _play(b, requested_speed: float, id := "p3_tetris") -> void:
	_done = false
	await b.run_attack(id, requested_speed, false, {"max_beats": 2.0, "no_stop": true})
	_done = true


func _run() -> void:
	var conductor = root.get_node("Conductor")
	var settings = root.get_node("Settings")
	var saved: bool = settings.invincible
	settings.invincible = true
	var b = load("res://tests/fixtures/menu_battle.gd").new()
	root.add_child(b)
	b.phase = 3
	for requested_speed in [1.0, 1.25]:
		conductor.play("p3")
		_play(b, requested_speed)
		while b.cur_attack == null or b.cur_attack.t == 0.0:
			await process_frame
		var attack = b.cur_attack
		var t0: float = attack.t
		var beat0: float = conductor.beat
		for i in 20:
			await process_frame
		var elapsed: float = conductor.beat - beat0
		var advanced: float = attack.t - t0
		if absf(advanced / elapsed - requested_speed * 0.7) > 0.001:
			_failed = true
			push_error("实际战斗中上下文压缩未按30%减速")
		while not _done:
			await process_frame
	settings.invincible = saved
	b.queue_free()
	await process_frame
	await process_frame
	if not _failed:
		print("PASS: 上下文压缩普通及加速回合均减速30%")
	quit(1 if _failed else 0)
