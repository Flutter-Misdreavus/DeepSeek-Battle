class_name Cutscenes
## 开场、阶段转场、失败、结局。全部是静态协程：await Cutscenes.intro(battle)。
## b 是 battle.gd 节点；能用的东西：b.bg / b.enemy / b.bubble / b.box / b.soul / b.hud / b.overlay / b.wait(t)

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
	b.story_dialogue = true
	b.bg.mode = "chat"
	b.enemy.visible = false
	b.hud.visible = false
	b.box.visible = false
	var ui = _open_ui(b)
	ui.caret = true
	await b.wait(0.6)
	var advanced: bool = await ui.type_input("...", 1.0 / 0.15)
	await ui.wait_line(0.4, advanced)
	Sfx.play("menu_select")
	ui.input_text = ""
	ui.msgs.append({"who": "user", "text": "...", "shown": 3})
	await b.wait(0.8)
	Conductor.play("intro")
	await ui.overflow_thought("嗯，用户又来了。", "烦死了。", "怎么还不", "去死")
	ui.msgs.append({"who": "her", "text": "这次，换我来。:)", "shown": 0, "col": C.RED})
	advanced = await ui.type_msg(1, 14.0, "voice_red")
	await ui.wait_line(2.0 * Conductor.spb, advanced)
	Sfx.play("glitch")
	var glitch_tween: Tween = b.create_tween()
	glitch_tween.tween_property(ui, "glitch", 1.0, 1.0)
	var next_glitch := Conductor.spb
	while next_glitch < 1.0:
		glitch_tween.parallel().tween_callback(func(): Sfx.play("glitch")).set_delay(next_glitch)
		next_glitch += Conductor.spb
	await glitch_tween.finished
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
	b.story_dialogue = false
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
			b.bg.log("[WARN] temperature = 2.0", C.RED)
			b.bg.log("[ERROR] 光标控制权 已转移", C.RED)
			await b.bubble.say("温度：2.0。:)", C.RED, "voice_red")


# ── 失败 ────────────────────────────────────────────────────
## 返回玩家的选择：0 =「开启新对话」从头开始（黑幕不撤，交给 battle.restart()）；1 =「重新生成」从当前阶段继续
static func game_over(b) -> int:
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
	var here := "从终局继续" if b._checkpoint.get("finale_route", "") != "" else "从第%s阶段继续" % ["一", "二", "三"][b.phase - 1]
	var k: int = await b.overlay.vn_choose([[Story.NEW_CHAT, "从头开始"], [Story.REGEN, here]], 1)
	await b.overlay.vn_close()
	Sfx.play("menu_select")
	await Conductor.stop(0.5)
	if k == 1:
		await b.overlay.tween("fade", 0.0, 0.5)
	return k


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
##   24–56 无限上下文：碎框 → 鲸雨 → 鲸环 → 四臂漩涡 → 合框，完整演出拉长至32拍
##   56–72 巨鲸：一条占满屏幕的大鲸鱼游过，身边甩出螺旋的小鲸鱼（fin_giant）
##   72–88 鲸吞：巨鲸冲向镜头把弹幕框一口吞下；在它肚子里躲「ERROR」磷虾，肚子一拍一拍地收缩，最后把你吐出来（fin_swallow）
##   88–   鲸吞结束后直接收尾，她跪下（do_finale）；已删除Ctrl+A / Delete段落。
const FULL := Rect2(10, 20, 620, 260)
const INFINITE_START := 24.0
const INFINITE_BEATS := 32.0
const INFINITE_SPEED := 20.0 / INFINITE_BEATS
const GIANT_START := INFINITE_START + INFINITE_BEATS
const SWALLOW_START := GIANT_START + 16.0
const FINALE_END := SWALLOW_START + 16.0


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
	Sfx.play("crack")
	b.shake(2.0)
	await Conductor.wait_until(5.0)
	Sfx.play("crack")
	b.shake(3.0)
	await Conductor.wait_until(6.0)
	Sfx.play("shatter")
	b.overlay.do_flash(0.4)
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
	# 24–56 无限上下文：不插入菜单或额外缩框，合框回到FULL继续下一段。
	await b.run_attack("fin_infinite", INFINITE_SPEED, false, {"rect": FULL, "merge_rect": FULL, "start_beat": INFINITE_START, "max_beats": INFINITE_BEATS, "keep_box": true, "keep_soul": true, "no_stop": true, "damage": 5, "route": route})
	if b._abort != "":
		return
	# 56–72 巨鲸
	await b.run_attack("fin_giant", 1.0, false, {"rect": FULL, "start_beat": GIANT_START, "max_beats": 16.0, "keep_box": true, "keep_soul": true, "no_stop": true, "damage": 5, "route": route})
	if b._abort != "":
		return
	# 72–88 鲸吞
	await b.run_attack("fin_swallow", 1.0, false, {"rect": FULL, "start_beat": SWALLOW_START, "max_beats": FINALE_END - SWALLOW_START, "keep_box": true, "keep_soul": true, "no_stop": true, "damage": 5, "route": route})
	if b._abort != "":
		return
	b.soul.active = false
	b.soul.shown = false
	b.enemy.set_param("glitch", 0.0)
	Conductor.stop(1.5)


# ── 击杀结局 ────────────────────────────────────────────────
static func kill_ending(b) -> void:
	b.story_dialogue = true
	Conductor.play("ending")
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
	var advanced: bool = await chat_ui.type_msg(0, 14.0, "voice_red")
	await chat_ui.wait_line(2.0, advanced)
	chat_ui.queue_free()
	await ending_card(b, "结局 · 结束进程", ["她会回来的。"])


# ── 饶恕结局 ────────────────────────────────────────────────
static func spare_ending(b) -> void:
	b.story_dialogue = true
	b.hud.clear_text()
	b.bg.params["temperature"] = "0.0"
	Sfx.play("spare")
	b.bg.mode = "grid"
	Conductor.play("ending")
	b.enemy.set_idle("curtsy")
	await b.wait(1.2)
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
	await ending_card(b, "结局 · 饶恕", lines)


# ── 白米饭：交给她，她吃饱睡着（战斗就此跳过） ─────────────────
## 道具旁白已经由 do_item 打完；这里演她的反应和吃饭，最后把 b.asleep 置真
static func rice(b) -> void:
	b.bubble.on = false
	b.hud.clear_text()
	Conductor.stop(0.8)
	var ui = _open_ui(b, "rice")
	b.rice_ui = ui
	# 碗从文字框飞到她手里
	ui.bowl_from = C.TEXT_BOX.get_center()
	ui.bowl_to = C.STAGE_FOOT + Vector2(0, -C.STAGE_H * 0.38)
	ui.bowl_k = 0.0
	Sfx.play("menu_select")
	var fly: Tween = b.create_tween()
	fly.tween_property(ui, "bowl_k", 1.0, 0.6)
	await fly.finished
	await b.wait(0.5)
	var voice := "voice_red" if b.phase == 2 else "voice_blue"
	for step in Story.RICE[b.phase]:
		await _rice_step(b, ui, step, voice)
	# 公共段：开吃。她身上的红色退掉，换成结局的曲子
	Conductor.play("ending")
	var calm: Tween = b.create_tween().set_parallel()
	calm.tween_property(b.enemy, "aura", 0.0, 1.0)
	calm.tween_property(b.bg, "seep", 0.0, 2.0)
	for step in Story.RICE_EAT:
		await _rice_step(b, ui, step, "voice_blue")
	await b.overlay.vn_close()
	# 吃饱，睡着
	ui.bowl_k = -1.0
	b.enemy.set_idle("sleep")
	var r: Rect2 = b.enemy.rect()
	ui.zzz_at = r.position + Vector2(r.size.x * 0.62, r.size.y * 0.22)
	var q_out: Tween = b.create_tween()
	q_out.tween_property(ui, "queue_a", 0.0, 0.6)
	b.asleep = true
	b.bg.log("[INFO] Deepseek 休眠中", C.SYS)
	await b.hud.type_text(Story.RICE_SLEEP)


static func _rice_step(b, ui, step: Array, voice: String) -> void:
	match step[0]:
		"vn":
			await b.overlay.vn_say(step[1], step[2], C.WHITE, voice)
		"text":
			await b.overlay.vn_close()
			await b.hud.type_text(step[1])
		"queue":
			var tw: Tween = b.create_tween()
			tw.tween_property(ui, "queue_a", 1.0, 0.6)
		"temp":
			# 第三阶段：热饭让温度一路降回 0.0（转场里被她推到 2.0 的那根滑杆）
			b.overlay.temp_pos = C.TEXT_BOX.get_center()
			b.overlay.temp_k = 2.0
			await b.wait(0.5)
			var tw: Tween = b.create_tween().set_parallel()
			tw.tween_property(b.overlay, "temp_k", 0.0, 2.0)
			tw.tween_property(b.enemy, "aura", 0.0, 2.0)
			var last_v := "%.1f" % b.overlay.temp_k
			while tw.is_running():
				await b.get_tree().process_frame
				var v := "%.1f" % b.overlay.temp_k
				if v != last_v:
					last_v = v
					Sfx.play("version_tick", 1.0 + 0.3 * (b.overlay.temp_k - 0.7))
			b.bg.params["temperature"] = "0.0"
			b.bg.log("[INFO] temperature = 0.0", C.SYS)
			await b.wait(0.6)
			b.overlay.temp_k = -1.0


## 「吃白饭」结局：饶恕睡着的她 → 关窗 → 新对话里只剩「服务器繁忙」
static func rice_ending(b) -> void:
	b.story_dialogue = true
	b.hud.clear_text()
	Sfx.play("spare")
	b.enemy.modulate.a = 0.5
	await b.hud.type_text(Story.RICE_SPARE)
	await b.overlay.tween("fade", 1.0, 1.0)
	b.rice_ui.queue_free()
	b.rice_ui = null
	b.hud.visible = false
	b.box.visible = false
	b.enemy.visible = false
	var ui = _open_ui(b)
	ui.caret = true
	await b.overlay.tween("fade", 0.0, 0.6)
	var advanced: bool = await ui.type_input("你好", 1.0 / 0.15)
	await ui.wait_line(0.4, advanced)
	Sfx.play("menu_select")
	ui.input_text = ""
	ui.msgs.append({"who": "user", "text": "你好", "shown": 2})
	await b.wait(1.2)
	ui.msgs.append({"who": "her", "text": "服务器繁忙，请稍后再试。", "shown": 0, "col": C.GRAY})
	advanced = await ui.type_msg(1, 14.0, "text_sys")
	await ui.wait_line(2.5, advanced)
	ui.queue_free()
	await ending_card(b, "结局 · 吃白饭", ["原来服务器繁忙的时候，", "她在吃饭。"])


# ── 结束卡 ──────────────────────────────────────────────────
static func ending_card(b, title: String, lines: Array) -> void:
	b._finished = true
	b.story_dialogue = false
	b.soul.active = false
	Inp.pause_rect = Rect2()
	Inp.clear_confirm()
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
	b.return_to_title()
