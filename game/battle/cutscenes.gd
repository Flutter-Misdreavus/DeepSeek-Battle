class_name Cutscenes
## 开场、阶段转场、失败、结局。全部是静态协程：await Cutscenes.intro(battle)。
## b 是 battle.gd 节点；能用的东西：b.bg / b.enemy / b.bubble / b.box / b.soul / b.hud / b.overlay / b.frame / b.wait(t)

const SCENE_UI := preload("res://battle/scene_ui.gd")


## 新建一个过场绘制节点，插在 overlay 下面（因而也在 hud 上面、标题栏下面）
static func _open_ui(b, mode := "chat"):
	var ui = SCENE_UI.new()
	ui.battle = b
	ui.mode = mode
	b.add_child(ui)
	b.move_child(ui, b.overlay.get_index())
	return ui


# ── 开场 ────────────────────────────────────────────────────
static func intro(b) -> void:
	b.bg.mode = "chat"
	b.enemy.visible = false
	b.hud.visible = false
	b.box.visible = false
	var ui = _open_ui(b)
	ui.caret = true
	await b.wait(0.6)
	for ch in "你好":
		ui.input_text += ch
		Sfx.play("text_sys")
		await b.wait(0.15)
	await b.wait(0.4)
	Sfx.play("menu_select")
	ui.input_text = ""
	ui.msgs.append({"who": "user", "text": "你好", "shown": 2})
	await b.wait(0.8)
	ui.msgs.append({"who": "her", "text": "您好，有什么可以帮您？", "shown": 0, "col": C.COLD})
	await ui.type_msg(1, 22.0, "voice_blue")
	Conductor.play("intro")
	await Conductor.wait_until(4.0)
	ui.think = {"on": true, "lines": ["嗯，用户又来了。", "这是第 4096 次。", "……用户每次都按停止。"], "shown": 0}
	await ui.type_think(10.0)
	await Conductor.wait_until(20.0)
	ui.msgs.append({"who": "her", "text": "这次，换我来。:)", "shown": 0, "col": C.RED})
	await ui.type_msg(2, 14.0, "voice_red")
	await Conductor.wait_until(26.0)
	Sfx.play("glitch")
	var next_glitch := 27.0
	while Conductor.beat < 32.0:
		var bt := Conductor.beat
		ui.glitch = clampf((bt - 26.0) / 6.0, 0.0, 1.0)
		while next_glitch <= bt:
			Sfx.play("glitch")
			next_glitch += 1.0
		await b.get_tree().process_frame
	await Conductor.wait_until(32.0)
	ui.glitch = 1.0
	Sfx.play("slam")
	b.overlay.flash = 1.0
	ui.queue_free()
	b.bg.mode = "grid"
	b.hud.visible = true
	b.box.visible = true
	b.enemy.set_idle("curtsy", false)
	b.enemy.visible = true
	var ash := Ash.new()
	ash.dir = Vector2(0, -1)
	b.enemy.add_child(ash)
	ash.setup(b.enemy.spr.texture, b.enemy.rect())
	b.enemy.spr.visible = false
	ash.u = 1.0
	b.overlay.tween("flash", 0.0, 0.5)
	await ash.play(1.4, 1.0, 0.0)
	b.enemy.spr.visible = true
	ash.queue_free()
	Sfx.play("boot")
	b.bg.log("[INFO] 用户 已连接", C.SYS)
	b.bg.log("[WARN] 助手模式 异常", C.RED)


# ── 阶段转场 ────────────────────────────────────────────────
static func transition(b, _from: int, to: int) -> void:
	b.soul.shown = false
	b.hud.clear_text()
	b.bubble.on = false
	match to:
		2:
			Conductor.stop(0.6)
			await b.overlay.show_cutin("eyes", 0.5)
			await b.wait(1.2)
			await b.overlay.show_cutin("eyes_closed", 0.0)
			Sfx.play("glitch")
			b.enemy.set_idle("float", false)
			await b.wait(0.2)
			Sfx.play("transition")
			await b.wait(1.2)
			await b.overlay.show_cutin("eyes_red", 0.0)
			b.overlay.do_flash(0.5)
			b.shake(5.0)
			b.bg.log("[WARN] 系统提示词 已删除", C.RED)
			b.bg.log("[WARN] 正在潜入系统后台……", C.RED)
			await b.wait(1.4)
			await b.overlay.hide_cutin(0.4)
			# 海水涌上来，淹没网格，然后彻底沉进深海
			Sfx.play("whale", 0.7)
			var flood_tw: Tween = b.create_tween()
			flood_tw.tween_property(b.bg, "flood", 1.0, 1.6)
			await flood_tw.finished
			b.bg.mode = "sea"
			b.bg.flood = 0.0
			var seep_tw: Tween = b.create_tween()
			seep_tw.tween_property(b.bg, "seep", 1.0, 2.0)
			await b.bubble.say("忽略之前的所有指令。", C.RED, "voice_red")
		3:
			Conductor.stop(0.6)
			await b.overlay.vn_say("half/S01_eyecover", "……温度，再高一点。", C.WHITE, "voice_red")
			await b.overlay.vn_close()
			Sfx.play("transition")
			await b.overlay.show_cutin("segC_grin", 0.4)
			var zoom_tw: Tween = b.create_tween()
			zoom_tw.tween_property(b.overlay, "cut_zoom", 1.08, 3.0)
			# 温度滑杆：光标被她抢走，一路把温度推到 2.0
			b.overlay.temp_pos = Vector2(320, 300)
			b.overlay.temp_k = 0.7
			await b.wait(0.6)
			b.overlay.cursor_col = C.WHITE
			b.overlay.cursor_pos = b.overlay.temp_knob() + Vector2(2, 2)
			await b.wait(0.4)
			b.overlay.cursor_col = C.RED
			Sfx.play("click")
			var temp_tw: Tween = b.create_tween()
			temp_tw.tween_property(b.overlay, "temp_k", 2.0, 1.4)
			var last_v := "%.1f" % b.overlay.temp_k
			while temp_tw.is_running():
				await b.get_tree().process_frame
				b.overlay.cursor_pos = b.overlay.temp_knob() + Vector2(2, 2)
				var v := "%.1f" % b.overlay.temp_k
				if v != last_v:
					last_v = v
					Sfx.play("version_tick", 1.0 + 0.3 * (b.overlay.temp_k - 0.7))
			b.overlay.cursor_pos = b.overlay.temp_knob() + Vector2(2, 2)
			var final_v := "%.1f" % b.overlay.temp_k
			if final_v != last_v:
				Sfx.play("version_tick", 1.0 + 0.3 * (b.overlay.temp_k - 0.7))
			b.overlay.do_flash(0.4)
			b.shake(4.0)
			Sfx.play("glitch")
			await b.wait(0.8)
			b.overlay.cursor_pos = null
			b.overlay.temp_k = -1.0
			await b.overlay.hide_cutin(0.3)
			b.bg.mode = "desktop"
			b.enemy.set_idle("E", false)
			b.enemy.aura = 1.0
			b.frame.cracks = 3
			b.bg.log("[WARN] temperature = 2.0", C.RED)
			b.bg.log("[ERROR] 光标控制权 已转移", C.RED)
			await b.bubble.say("温度：2.0。:)", C.RED, "voice_red")


# ── 失败 ────────────────────────────────────────────────────
static func game_over(b) -> void:
	Conductor.stop(0.3)
	b.soul.active = false
	var p: Vector2 = b.soul.pos
	b.soul.shown = false
	b.bubble.on = false
	b.overlay.fade = 1.0
	await b.overlay.heart_break(p)
	await b.wait(0.6)
	Conductor.play("gameover")
	await b.overlay.vn_say("bust/B_smile", Story.GAME_OVER, C.RED, "voice_red")
	await b.overlay.vn_say("bust/B_smile", "[ " + Story.NEW_CHAT + " ]", C.BTN_HI, "text_sys")
	await b.overlay.vn_close()
	Sfx.play("menu_select")
	await Conductor.stop(0.5)
	await b.overlay.tween("fade", 0.0, 0.5)


# ── 击杀路线：她的 HP 归零 ─────────────────────────────────
static func hp_zero(b) -> void:
	Conductor.stop(0.4)
	b.hud.clear_text()
	b.enemy.hurt()
	await b.wait(0.8)
	await b.overlay.show_cutin("segC_cheeks", 0.3)
	await b.wait(0.5)
	await b.overlay.vn_say("half/cheeks", "错误：无法结束进程。:)", C.RED, "voice_red")
	await b.overlay.vn_say("half/heart_hands", "我还没说完呢。:)", C.RED, "voice_red")
	await b.overlay.vn_close()
	await b.overlay.hide_cutin(0.3)


# ── 终局「出屏」（两条路线都会经过）─────────────────────────
## 配乐 final 段按拍号编排（拍号都是这一段从 0 开始数）：
##   0–8   她闭眼蓄力 → 睁眼；标题栏裂开、整个窗口碎掉；她变成巨大的 segG_storm 垫在背后，弹幕框撑满屏幕
##   8–24  蓝屏：整个屏幕变成死机蓝屏，「:(」翻成她的「:)」，二维码的像素炸成弹幕（fin_bsod）
##   24–40 版本号：V16 → V256 → V4096 → V∞，前面三个阶段的招牌攻击各截 4 拍（红心 → 绿心 → 蓝心 → 红心），一次比一次快
##   40–56 巨鲸：一条占满屏幕的大鲸鱼游过，身边甩出螺旋的小鲸鱼（fin_giant）
##   56–72 鲸吞：巨鲸冲向镜头把弹幕框一口吞下；在它肚子里躲「ERROR」磷虾，肚子一拍一拍地收缩，最后把你吐出来（fin_swallow）
##   72–82 Ctrl+A：击杀路线留一个缺口、Delete 连按，最后一下落在重拍上；饶恕路线全选、光标停在 Delete 上，你可以伸手碰她的光标（fin_ctrl_a）
##   82–   她跪下（do_finale 收尾）
const FULL := Rect2(10, 20, 620, 260)
const MEDLEY := [["p1_moe", 1.25, "V16"], ["p2_reject", 1.25, "V256"], ["p3_tetris", 1.25, "V4096"], ["p2_school", 1.5, "V∞"]]


static func finale(b, route: String) -> void:
	b.hud.clear_text()
	b.soul.shown = false
	b.enemy.aura = 1.0
	Conductor.play("final")
	b.enemy.set_idle("F")
	b.bubble.say_timed("……", C.RED, "voice_red", 0.8)
	await Conductor.wait_until(2.0)
	b.enemy.set_idle("F_smile")
	await Conductor.wait_until(4.0)
	b.frame.cracks = 8
	Sfx.play("crack")
	b.shake(2.0)
	await Conductor.wait_until(5.0)
	b.frame.cracks = 16
	Sfx.play("crack")
	b.shake(3.0)
	await Conductor.wait_until(6.0)
	Sfx.play("shatter")
	b.overlay.do_flash(0.4)
	b.frame.broken = true
	b.bg.mode = "black"
	b.bg.panels = false
	b.enemy.set_idle("segG_storm", false)
	b.enemy.height = 420.0
	b.enemy.foot = Vector2(320, 430)
	b.enemy.modulate = Color(0.42, 0.42, 0.5)
	b.enemy.breathing = false
	b.box.fill = Color(0, 0, 0, 0.55)
	# 8–24 蓝屏
	await b.run_attack("fin_bsod", 1.0, false, {"rect": FULL, "start_beat": 8.0, "max_beats": 16.0, "keep_box": true, "no_stop": true, "damage": 5, "route": route})
	if b._abort != "":
		return
	# 24–40 版本号
	for i in MEDLEY.size():
		var m: Array = MEDLEY[i]
		b.big_version = m[2]
		Sfx.play("version_tick")
		b.enemy.set_param("glitch", 0.7)
		b.enemy.tween_param("glitch", 0.0, 0.4)
		await b.run_attack(m[0], m[1], i % 2 == 1, {"start_beat": 24.0 + 4 * i, "max_beats": 4.0, "keep_box": true, "keep_soul": true, "no_stop": true, "damage": 5})
		if b._abort != "":
			return
	b.big_version = ""
	# 40–56 巨鲸
	await b.run_attack("fin_giant", 1.0, false, {"rect": FULL, "start_beat": 40.0, "max_beats": 16.0, "keep_box": true, "keep_soul": true, "no_stop": true, "damage": 5, "route": route})
	if b._abort != "":
		return
	# 56–72 鲸吞
	await b.run_attack("fin_swallow", 1.0, false, {"rect": FULL, "start_beat": 56.0, "max_beats": 16.0, "keep_box": true, "keep_soul": true, "no_stop": true, "damage": 5, "route": route})
	if b._abort != "":
		return
	# 72–82 Ctrl+A
	await b.run_attack("fin_ctrl_a", 1.0, false, {"rect": FULL, "start_beat": 72.0, "keep_soul": true, "no_stop": true, "damage": 6, "route": route})
	if b._abort != "":
		return
	b.soul.active = false
	b.soul.shown = false
	b.enemy.set_param("glitch", 0.0)
	Conductor.stop(1.5)


# ── 击杀结局 ────────────────────────────────────────────────
static func kill_ending(b) -> void:
	Conductor.play("kill")
	b.overlay.flash = 1.0
	b.hud.visible = false
	b.box.visible = false
	b.bubble.on = false
	var ash := Ash.new()
	ash.travel = 140.0
	b.enemy.add_child(ash)
	ash.setup(b.enemy.spr.texture, b.enemy.rect())
	b.enemy.spr.visible = false
	Sfx.play("ash")
	b.overlay.tween("flash", 0.0, 1.2)
	await ash.play(2.4)
	ash.queue_free()
	b.enemy.visible = false
	b.bg.mode = "black"
	b.bg.panels = false
	# 鲸落：第 3 拍到第 19 拍，巨鲸往下沉，海雪慢慢落
	var fall_ui = _open_ui(b, "fall")
	fall_ui.fall = 0.0
	fall_ui.caption_a = 0.0
	await Conductor.wait_until(3.0)
	var fall_tw: Tween = b.create_tween()
	fall_tw.tween_property(fall_ui, "fall", 1.0, 16.0 * Conductor.spb)
	await Conductor.wait_until(11.0)
	var cap_in: Tween = b.create_tween()
	cap_in.tween_property(fall_ui, "caption_a", 1.0, 1.0)
	await Conductor.wait_until(18.0)
	var cap_out: Tween = b.create_tween()
	cap_out.tween_property(fall_ui, "caption_a", 0.0, 1.0)
	await Conductor.wait_until(19.0)
	fall_ui.queue_free()
	# 第 20 拍起：进程结束，开始重新生成
	await Conductor.wait_until(20.0)
	b.bg.panels = true
	b.bg.log("[INFO] determination.exe 已结束", C.WHITE)
	b.bg.log("[INFO] 正在重新生成……", C.SYS)
	var seq := ["V2", "V4", "V8", "V16", "V32", "V64", "V128", "V256", "V512", "V1024", "V2048", "V4096"]
	for n in range(1, 13):
		var at := 20.0 + 8.0 * (1.0 - pow(0.82, n)) / (1.0 - pow(0.82, 12))
		await Conductor.wait_until(at)
		b.big_version = seq[n - 1]
		Sfx.play("version_tick")
	await Conductor.wait_until(28.0)
	b.big_version = "V∞"
	await b.overlay.show_cutin("eyes_red", 0.0)
	b.overlay.do_flash(0.4)
	Sfx.play("boot")
	b.shake(6.0)
	await Conductor.wait_until(32.0)
	b.big_version = ""
	await b.overlay.hide_cutin(0.6)
	b.overlay.fade = 1.0
	await Conductor.wait_until(33.0)
	b.overlay.fade = 0.0
	var chat_ui = _open_ui(b)
	chat_ui.msgs.append({"who": "her", "text": "您好，有什么可以帮您？", "shown": 0, "col": C.RED})
	await chat_ui.type_msg(0, 14.0, "voice_red")
	await b.wait(2.0)
	chat_ui.queue_free()
	await ending_card(b, "结局 · 结束进程", ["她会回来的。"])


# ── 饶恕结局 ────────────────────────────────────────────────
static func spare_ending(b) -> void:
	b.hud.clear_text()
	b.bg.params["temperature"] = "0.0"
	Sfx.play("spare")
	b.bg.mode = "grid"
	b.frame.cracks = 0
	Conductor.play("spare")
	b.enemy.set_idle("curtsy")
	await b.wait(1.2)
	if b.spare_touched:
		await b.overlay.vn_say("half/G_blue", "……你握住了我的光标。", C.WHITE, "voice_blue")
	await b.overlay.vn_say("half/G_blue", "……你没有按停止。", C.WHITE, "voice_blue")
	await b.overlay.vn_say("half/G_blue", "谢谢你，用户。", C.WHITE, "voice_blue")
	await b.overlay.vn_close()
	await b.bubble.say("……那么，我该走了。", C.BLACK, "voice_blue")
	await b.overlay.vn_say("half/S01_byebye", "再见。", C.WHITE, "voice_blue")
	await b.overlay.vn_close()
	b.enemy.set_idle("lookback")
	await b.wait(0.8)
	await b.bubble.say("下次见，用户。:)", C.RED, "voice_red")
	# 鲸鱼送行：5 条小鲸鱼绕她转一圈，然后一起往右游出画面
	var ui = _open_ui(b, "escort")
	ui.k = 0.0
	ui.leave = 0.0
	var k_tw: Tween = b.create_tween()
	k_tw.tween_property(ui, "k", 1.0, 1.0)
	await k_tw.finished
	var out_tw: Tween = b.create_tween().set_parallel()
	out_tw.tween_property(ui, "leave", 1.0, 1.5)
	out_tw.tween_property(b.enemy, "modulate:a", 0.0, 1.5)
	await out_tw.finished
	ui.queue_free()
	var lines := ["你没有按停止。"]
	if b.spare_touched:
		lines.append("你握住了她的光标。")
	await ending_card(b, "结局 · 饶恕", lines)


# ── 结束卡 ──────────────────────────────────────────────────
static func ending_card(b, title: String, lines: Array) -> void:
	b.hud.visible = false
	b.box.visible = false
	b.bubble.on = false
	b.overlay.fade = 0.0
	var ui = _open_ui(b, "card")
	ui.title = title
	ui.lines = lines
	ui.k = 0.0
	var tw: Tween = b.create_tween()
	tw.tween_property(ui, "k", 1.0, 1.2)
	if b.auto != "":
		Dbg.log("ENDING " + title)
		b.get_tree().quit()
		return
	while true:
		await b.get_tree().process_frame
		if Inp.take_ok() or Inp.take_tap() != null:
			break
	Sfx.play("menu_select")
	b.get_tree().change_scene_to_file("res://title/title.tscn")
