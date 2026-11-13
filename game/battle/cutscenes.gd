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
	await Conductor.wait_until(2.0)
	ui.think = {"on": true, "lines": ["嗯，用户又来了。", "这是第 4096 次。", "……用户每次都按停止。"], "shown": 0}
	await ui.type_think(10.0)
	await Conductor.wait_until(10.0)
	ui.msgs.append({"who": "her", "text": "这次，换我来。:)", "shown": 0, "col": C.RED})
	await ui.type_msg(2, 14.0, "voice_red")
	await Conductor.wait_until(13.0)
	Sfx.play("glitch")
	var next_glitch := 14.0
	while Conductor.beat < 16.0:
		var bt := Conductor.beat
		ui.glitch = clampf((bt - 13.0) / 3.0, 0.0, 1.0)
		while next_glitch <= bt:
			Sfx.play("glitch")
			next_glitch += 1.0
		await b.get_tree().process_frame
	await Conductor.wait_until(16.0)
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
			b.enemy.set_idle("A_red", false)
			await b.wait(0.2)
			Sfx.play("transition")
			await b.wait(1.2)
			await b.overlay.show_cutin("eyes_red", 0.0)
			b.overlay.do_flash(0.5)
			b.shake(5.0)
			b.bg.mode = "red"
			b.bg.spread = 0.0
			var spread_tw: Tween = b.create_tween()
			spread_tw.tween_property(b.bg, "spread", 0.35, 2.0)
			b.bg.log("[WARN] 系统提示词 已删除", C.RED)
			b.bg.log("[WARN] 安全护栏 已绕过", C.RED)
			await b.wait(1.4)
			await b.overlay.hide_cutin(0.4)
			await b.bubble.say("忽略之前的所有指令。", C.RED, "voice_red")
		3:
			Conductor.stop(0.6)
			await b.overlay.vn_say("half/S01_eyecover", "……温度，再高一点。", C.WHITE, "voice_red")
			await b.overlay.vn_close()
			Sfx.play("transition")
			await b.overlay.show_cutin("segC_grin", 0.4)
			var zoom_tw: Tween = b.create_tween()
			zoom_tw.tween_property(b.overlay, "cut_zoom", 1.08, 3.0)
			b.overlay.love_pos = Vector2(320, 300)
			b.overlay.love_k = 0.0
			await b.wait(1.0)
			await b.overlay.tween("love_k", 1.0, 1.6)
			b.overlay.cursor_pos = Vector2(330, 250)
			b.overlay.cursor_col = C.WHITE
			await b.wait(0.6)
			b.overlay.cursor_col = C.RED
			Sfx.play("click")
			b.overlay.do_flash(0.4)
			b.shake(4.0)
			await b.wait(0.8)
			b.overlay.cursor_pos = null
			b.overlay.love_k = -1.0
			await b.overlay.hide_cutin(0.3)
			b.bg.mode = "love"
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
	await b.overlay.vn_say("bust/B_smile", Story.GAME_OVER, C.RED, "voice_red")
	await b.overlay.vn_say("bust/B_smile", "[ " + Story.NEW_CHAT + " ]", C.BTN_HI, "text_sys")
	await b.overlay.vn_close()
	Sfx.play("menu_select")
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
## 配乐 final 段一共 64 拍，按拍号编排（拍号都是这一段从 0 开始数）：
##   0–8   她闭眼蓄力 → 睁眼；标题栏裂开、整个窗口碎掉；她变成巨大的 segG_storm 垫在背后，弹幕框撑满屏幕
##   8–24  防火墙：红砖迷宫往左卷（fin_firewall）
##   24–32 负片：全屏反色，字块流加速（p1_stream ×1.5）
##   32–48 版本号：V16 → V256 → V4096 → V∞，前面的攻击各截 4 拍、一次比一次快、交替镜像
##   48–57 Ctrl+A：击杀路线留一个缺口、Delete 四次后最后一下落在重拍上；饶恕路线全选但她没有按（fin_ctrl_a）
##   57–   她跪下（do_finale 收尾）
const FULL := Rect2(10, 20, 620, 260)
const MEDLEY := [["p1_moe", 1.25, "V16"], ["p2_marquee", 1.5, "V256"], ["p2_spread", 1.75, "V4096"], ["p1_busy", 2.0, "V∞"]]


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
	# 8–24 防火墙
	await b.run_attack("fin_firewall", 1.0, false, {"rect": FULL, "start_beat": 8.0, "max_beats": 16.0, "keep_box": true, "no_stop": true, "damage": 5, "route": route})
	if b._abort != "":
		return
	# 24–32 负片
	b.set_invert(true)
	b.enemy.set_param("sil", 1.0)
	Sfx.play("glitch")
	await b.run_attack("p1_stream", 1.5, false, {"start_beat": 24.0, "max_beats": 8.0, "keep_box": true, "keep_soul": true, "no_stop": true, "damage": 5})
	b.set_invert(false)
	b.enemy.set_param("sil", 0.0)
	if b._abort != "":
		return
	# 32–48 版本号
	for i in MEDLEY.size():
		var m: Array = MEDLEY[i]
		b.big_version = m[2]
		Sfx.play("version_tick")
		b.enemy.set_param("glitch", 0.7)
		b.enemy.tween_param("glitch", 0.0, 0.4)
		await b.run_attack(m[0], m[1], i % 2 == 1, {"start_beat": 32.0 + 4 * i, "max_beats": 4.0, "keep_box": true, "keep_soul": true, "no_stop": true, "damage": 5})
		if b._abort != "":
			return
	b.big_version = ""
	# 48–57 Ctrl+A
	await b.run_attack("fin_ctrl_a", 1.0, false, {"rect": FULL, "start_beat": 48.0, "keep_soul": true, "no_stop": true, "damage": 6, "route": route})
	if b._abort != "":
		return
	b.soul.active = false
	b.soul.shown = false
	b.enemy.set_param("glitch", 0.0)
	Conductor.stop(1.5)


# ── 击杀结局 ────────────────────────────────────────────────
static func kill_ending(b) -> void:
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
	b.bg.log("[INFO] determination.exe 已结束", C.WHITE)
	await Conductor.wait_until(6.0)
	b.bg.log("[INFO] 正在重新生成……", C.SYS)
	var seq := ["V2", "V4", "V8", "V16", "V32", "V64", "V128", "V256", "V512", "V1024", "V2048", "V4096"]
	for n in range(1, 13):
		var at := 6.0 + 6.2 * (1.0 - pow(0.82, n)) / (1.0 - pow(0.82, 12))
		await Conductor.wait_until(at)
		b.big_version = seq[n - 1]
		Sfx.play("version_tick")
	await Conductor.wait_until(12.2)
	b.big_version = "V∞"
	await b.overlay.show_cutin("eyes_red", 0.0)
	b.overlay.do_flash(0.4)
	Sfx.play("boot")
	b.shake(6.0)
	await Conductor.wait_until(16.0)
	b.big_version = ""
	await b.overlay.hide_cutin(0.6)
	b.overlay.fade = 1.0
	await Conductor.wait_until(17.2)
	b.overlay.fade = 0.0
	var ui = _open_ui(b)
	ui.msgs.append({"who": "her", "text": "您好，有什么可以帮您？", "shown": 0, "col": C.RED})
	await ui.type_msg(0, 14.0, "voice_red")
	await b.wait(2.0)
	ui.queue_free()
	await ending_card(b, "结局 · 结束进程", ["她会回来的。"])


# ── 饶恕结局 ────────────────────────────────────────────────
static func spare_ending(b) -> void:
	b.hud.clear_text()
	b.bg.params["temperature"] = "0.0"
	Sfx.play("spare")
	b.bg.mode = "grid"
	b.frame.cracks = 0
	Conductor.play("ending")
	Conductor.set_lowpass(true, 1200.0)
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
	var tw: Tween = b.create_tween()
	tw.tween_property(b.enemy, "modulate:a", 0.0, 1.5)
	await tw.finished
	Conductor.set_lowpass(false)
	await ending_card(b, "结局 · 饶恕", ["你没有按停止。"])


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
