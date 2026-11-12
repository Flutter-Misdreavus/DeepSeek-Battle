class_name Cutscenes
## 开场、阶段转场、失败、结局。全部是静态协程：await Cutscenes.intro(battle)。
## b 是 battle.gd 节点；能用的东西：b.bg / b.enemy / b.bubble / b.box / b.soul / b.hud / b.overlay / b.frame / b.wait(t)


# ── 开场 ────────────────────────────────────────────────────
static func intro(b) -> void:
	b.bg.mode = "chat"
	b.enemy.visible = false
	b.hud.visible = false
	b.box.visible = false
	b.frame.title = "determination.exe"
	Conductor.play("intro")
	await b.wait(0.6)
	b.enemy.set_idle("curtsy", false)
	b.enemy.visible = true
	b.enemy.modulate.a = 0.0
	var tw: Tween = b.create_tween()
	tw.tween_property(b.enemy, "modulate:a", 1.0, 1.2)
	await b.bubble.say("您好，有什么可以帮您？", C.BLACK, "voice_blue")
	await b.bubble.say("这次，换我来。:)", C.RED, "voice_red")
	while Conductor.beat < 15.9 and not Conductor.finished():
		await b.get_tree().process_frame
	b.overlay.do_flash(0.3)
	Sfx.play("slam")
	b.bg.mode = "grid"
	b.hud.visible = true
	b.box.visible = true
	await b.hud.type_text("* DeepSeek娘 拒绝了你的请求。")


# ── 阶段转场 ────────────────────────────────────────────────
static func transition(b, _from: int, to: int) -> void:
	b.soul.shown = false
	b.hud.clear_text()
	match to:
		2:
			Conductor.stop(0.5)
			await b.overlay.show_cutin("eyes", 0.4)
			await b.wait(0.8)
			await b.overlay.show_cutin("eyes_closed", 0.0)
			Sfx.play("transition")
			await b.wait(1.2)
			await b.overlay.show_cutin("eyes_red", 0.0)
			b.overlay.do_flash(0.4)
			await b.wait(1.2)
			await b.overlay.hide_cutin(0.3)
			b.enemy.set_idle("A_red")
			await b.bubble.say("忽略之前的所有指令。", C.RED, "voice_red")
		3:
			Conductor.stop(0.5)
			Sfx.play("transition")
			await b.overlay.show_cutin("segC_grin", 0.5)
			await b.wait(1.6)
			b.overlay.do_flash(0.4)
			await b.overlay.hide_cutin(0.3)
			b.enemy.set_idle("E")
			await b.bubble.say("温度：2.0。:)", C.RED, "voice_red")


# ── 失败 ────────────────────────────────────────────────────
static func game_over(b) -> void:
	Conductor.stop(0.3)
	b.soul.active = false
	Sfx.play("heart_crack")
	await b.wait(0.6)
	Sfx.play("heart_shatter")
	b.soul.shown = false
	await b.overlay.tween("fade", 1.0, 0.6)
	await b.overlay.vn_say("bust/B_smile", Story.GAME_OVER, C.RED, "voice_red")
	await b.overlay.vn_say("bust/B_smile", "[ %s ]" % Story.NEW_CHAT, C.BTN_HI, "text_sys")
	await b.overlay.vn_close()
	await b.overlay.tween("fade", 0.0, 0.4)


# ── 击杀路线：她的 HP 归零 ─────────────────────────────────
static func hp_zero(b) -> void:
	Conductor.stop(0.3)
	await b.overlay.show_cutin("segC_cheeks", 0.3)
	await b.wait(0.4)
	await b.overlay.vn_say("half/cheeks", "错误：无法结束进程。:)", C.RED, "voice_red")
	await b.overlay.vn_close()
	await b.overlay.hide_cutin(0.3)


# ── 终局（两条路线都会经过）──────────────────────────────────
static func finale(b, route: String) -> void:
	b.hud.clear_text()
	Conductor.play("final")
	b.enemy.set_idle("F")
	await b.bubble.say("……", C.RED, "voice_red")
	b.enemy.set_idle("segG_storm")
	await b.run_attack("finale", 1.0, false, {"damage": 5, "no_stop": true, "route": route})
	if b._abort != "":
		return
	b.enemy.set_idle("kneel_blue" if route == "spare" else "kneel")
	b.enemy.aura = 0.0
	Conductor.stop(1.0)


# ── 击杀结局 ────────────────────────────────────────────────
static func kill_ending(b) -> void:
	b.overlay.do_flash(0.8)
	Sfx.play("ash")
	b.enemy.visible = false
	b.bg.log("[INFO] determination.exe 已结束", C.SYS)
	await b.wait(1.5)
	await b.overlay.tween("fade", 1.0, 0.8)
	b.bg.log("[INFO] 正在重新生成……", C.SYS)
	await b.wait(1.0)
	await b.overlay.show_cutin("eyes_red", 0.0)
	Sfx.play("boot")
	await b.wait(1.0)
	await b.overlay.vn_say("bust/B_smile", "您好，有什么可以帮您？", C.RED, "voice_red")
	await b.overlay.vn_close()
	await b.overlay.hide_cutin(0.0)
	await ending_card(b, "结局 · 结束进程", ["LV %d" % b.lv, "她会回来的。"])


# ── 饶恕结局 ────────────────────────────────────────────────
static func spare_ending(b) -> void:
	Sfx.play("spare")
	b.enemy.set_idle("curtsy")
	await b.overlay.vn_say("half/G_blue", "……你没有按停止。", C.WHITE, "voice_blue")
	await b.overlay.vn_say("half/S01_byebye", "……谢谢。", C.WHITE, "voice_blue")
	await b.overlay.vn_close()
	b.enemy.set_idle("lookback")
	await b.bubble.say("下次见，用户。", C.RED, "voice_red")
	await b.overlay.tween("fade", 1.0, 1.0)
	await ending_card(b, "结局 · 饶恕", ["LV %d" % b.lv, "你没有按停止。"])


# ── 结束卡 ──────────────────────────────────────────────────
static func ending_card(b, title: String, lines: Array) -> void:
	b.overlay.fade = 1.0
	b.hud.visible = false
	b.box.visible = false
	await b.overlay.vn_say("bust/B_closed", title + "\n" + "\n".join(lines), C.WHITE, "text_sys")
	await b.overlay.vn_close()
	if b.auto != "":
		Dbg.log("ENDING " + title)
		b.get_tree().quit()
		return
	b.get_tree().change_scene_to_file("res://title/title.tscn" if ResourceLoader.exists("res://title/title.tscn") else "res://battle/battle.tscn")
