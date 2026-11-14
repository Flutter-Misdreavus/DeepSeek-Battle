extends Node2D
## 战斗主控：搭场景、回合循环、三个阶段、两条路线、失败与重来、暂停、自动驾驶。
## 设计见仓库外的设计方案；这里的流程全部写成协程，读起来就是剧本顺序。
##
## 图层（从下到上）：bg 背景+两侧面板 → enemy 她 → bubble 气泡 → box 框（攻击挂在框的裁剪层里，红心在最上）
##                   → over 框外的攻击元素 / 停止按钮 / 弹窗 → hud 界面 → overlay 全屏效果和 VN 对白 → pause 暂停菜单

const PAUSE_RECT := Rect2(8, 338, 32, 18)
const ATTACK_DIR := "res://battle/attacks/%s.gd"

var story_dialogue := false             # 开场 / 结尾：回车一次推进一句对白
var auto := ""                         # 自动驾驶："" / "kill" / "spare"
var bg := preload("res://battle/bg.gd").new()
var enemy := preload("res://battle/enemy.gd").new()
var bubble := preload("res://battle/bubble.gd").new()
var box := preload("res://battle/box.gd").new()
var soul := preload("res://battle/soul.gd").new()
var over := Node2D.new()
var hud := preload("res://battle/hud.gd").new()
var overlay := preload("res://battle/overlay.gd").new()
var pause_ui := preload("res://battle/pause_node.gd").new()

# ── 战斗状态 ──
var phase := 1
var her_hp := C.ENEMY_HP
var maxhp := C.PLAYER_HP
var hp := C.PLAYER_HP
var items: Array = []
var version := 4096
var spare := 0                         # 0 = 没进展；1 = 本阶段做了关键行动；2 = 又躲过一次攻击且没碰停止 → 进下一阶段
var spare_ready := false               # 终局后她跪下，可以饶恕
var asleep := false                    # 吃了白米饭睡着了：她不再出招，饶恕进「吃白饭」结局
var rice_ui = null                     # 白米饭的碗、排队的小鲸鱼、Zzz（Cutscenes.rice 创建，结局时释放）
var finale_done := false
var event_line := ""                   # 她下回合先说的话（打中她、按了停止之后）
var next_speed := 1.0
var _run_seed := 0
var _attack_serial := 0
var attack_i := 0
var talk_i := 0
var flavor_i := 0
var last_damage := 0                   # 上一回合受到的伤害（Ctrl+Z 用）
var turn_damage := 0
var hits_landed := 0
var cur_attack: Attack = null
var _abort := ""
var _checkpoint := {}
var _base_off := Vector2.ZERO
var _shake := 0.0
var _finished := false
var _returning_to_title := false
var _paused := false
var _pause_sel := 0

# 「■ 停止」按钮
var stop := {}
var _stop_msg_t := -1.0
var _stop_msg := ""
var _shards: Array = []                # 第二阶段停止按钮炸开的碎片 {p, v}
var kill_dialog := {}                  # 「结束进程」弹窗
var big_version := ""                  # 终局里框上方的大号版本号（空 = 不画）


func _ready() -> void:
	auto = Dbg.val("auto")
	_run_seed = int(Dbg.val("seed")) if Dbg.has("seed") else randi()
	Dbg.log("战斗随机种子 %d" % _run_seed)
	for n in [bg, enemy, bubble, box, over, hud, overlay, pause_ui]:
		add_child(n)
	box.add_child(soul)
	soul.shown = false
	soul.slammed.connect(func() -> void:
		shake(4.0)
		Sfx.play("slam"))
	bubble.battle = self
	hud.battle = self
	overlay.battle = self
	over.draw.connect(_draw_over)
	pause_ui.battle = self
	items = Story.ITEMS.duplicate(true)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_sync_hud()
	_main()


func _layout() -> void:
	_base_off = ((get_viewport_rect().size - C.BASE) / 2).floor()
	position = _base_off
	Inp.pause_rect = Rect2() if _finished else Rect2(_base_off + PAUSE_RECT.position, PAUSE_RECT.size)


func wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout


# ════════════════════════════════════════════════════════════
# 主循环
# ════════════════════════════════════════════════════════════

func _main() -> void:
	var j := Dbg.consume_startup_jump()
	if j == "":
		await Cutscenes.intro(self)
		await enter_phase(1, true)
		flavor_i = 0          # 第一回合的旁白是「* Deepseek 拒绝了你的请求。」
	else:
		await _jump(j)
	if _finished or not is_inside_tree():
		return
	while not _finished:
		var ended := await _round()
		if ended:
			return
		if _abort == "gameover":
			if await Cutscenes.game_over(self) == 0:
				restart()
				return
			_abort = ""
			_restore()
			var fr: String = _checkpoint.get("finale_route", "")
			if fr == "kill":
				if await _kill_route():
					return
			elif fr == "spare":
				await do_finale("spare")


## 一个完整回合；返回 true 表示已经演完结局
func _round() -> bool:
	var res := await _player_turn()
	if res == "spared":
		await Cutscenes.spare_ending(self)
		return true
	if res == "rice_spared":
		await Cutscenes.rice_ending(self)
		return true
	if her_hp <= 0:
		return await _kill_route()
	var hp_phase := _phase_for_hp()
	if hp_phase > phase:
		await enter_phase(hp_phase)
	await _enemy_turn()
	if _abort != "":
		return false
	if spare >= 2 and not spare_ready:
		if phase < 3:
			await enter_phase(phase + 1)
		else:
			await do_finale("spare")
	return false


## 终局：先存一个检查点（失败后直接从终局重来），演完后记下状态
func do_finale(route: String) -> void:
	_save()
	_checkpoint["finale_route"] = route
	await Cutscenes.finale(self, route)
	reset_stage()
	if _abort != "":
		return
	finale_done = true
	_checkpoint["finale_route"] = ""
	if route == "spare":
		spare_ready = true
		enemy.set_idle("kneel_blue")
	else:
		enemy.set_idle("kneel")
	enemy.breathing = false


## 把终局改过的舞台恢复原样（立绘大小位置、标题栏、面板、大号版本号）
func reset_stage() -> void:
	enemy.height = C.STAGE_H
	enemy.foot = C.STAGE_FOOT
	enemy.modulate = Color.WHITE
	enemy.spr.visible = true
	enemy.aura = 0.0
	bg.panels = true
	box.fill = C.BLACK
	box.border_col = C.WHITE
	big_version = ""


func _phase_for_hp() -> int:
	if her_hp <= C.ENEMY_HP / 3:
		return 3
	if her_hp <= C.ENEMY_HP * 2 / 3:
		return 2
	return 1


## 进入第 n 阶段：放转场（quick = 不放），换待机姿势、配乐、背景，存检查点
func enter_phase(n: int, quick := false) -> void:
	var from := phase
	phase = n
	var P: Dictionary = Story.PHASES[n]
	spare = 0
	attack_i = 0
	talk_i = 0
	flavor_i = 1 if n == 1 else 0
	if not quick:
		await Cutscenes.transition(self, from, n)
	enemy.set_idle(P["idle"])
	enemy.aura = 1.0 if n == 3 else 0.0
	Conductor.play(P["music"])
	Conductor.set_lowpass(P["lowpass"])
	bg.mode = P["bg"]
	bg.seep = 1.0 if n == 2 else 0.0
	bg.params["temperature"] = P["temperature"]
	_save()


func _save() -> void:
	_checkpoint = {"finale_route": "", "phase": phase, "her_hp": her_hp, "items": items.duplicate(true), "version": version, "finale": finale_done}


func _restore() -> void:
	her_hp = _checkpoint["her_hp"]
	hp = maxhp
	items = _checkpoint["items"].duplicate(true)
	version = _checkpoint["version"]
	finale_done = _checkpoint["finale"]
	spare_ready = false
	event_line = ""
	next_speed = 1.0
	soul.iframe = 0.0
	overlay.fade = 0.0
	reset_stage()
	enemy.breathing = true
	enemy.visible = true
	hud.visible = true
	box.visible = true
	_sync_hud()
	enter_phase(_checkpoint["phase"], true)


func _sync_hud() -> void:
	hud.hp = hp
	hud.maxhp = maxhp
	bg.params["version"] = "V%d" % version


# ════════════════════════════════════════════════════════════
# 你的回合
# ════════════════════════════════════════════════════════════

func _player_turn() -> String:
	box.morph(C.TEXT_BOX, 0.25)
	soul.shown = false
	hud.btn_dead = [false, false, false, false]
	var P: Dictionary = Story.PHASES[phase]
	var flavor: String = P["flavor"][flavor_i % P["flavor"].size()]
	if spare_ready:
		flavor = "* Deepseek 跪在地上。\n* 她不再攻击了。"
	if asleep:
		flavor = Story.RICE_FLAVOR
	flavor_i += 1
	hud.start_typing(flavor)
	if auto != "":
		await wait(0.4)
		return await _auto_turn()
	while true:
		var b := await hud.pick_button()
		match b:
			0:
				var t := await hud.pick_option(["Deepseek"], 1, _name_col())
				if t < 0:
					hud.start_typing(flavor, C.WHITE, false)
					continue
				if asleep:
					await hud.type_text(Story.RICE_FIGHT)
					hud.start_typing(flavor, C.WHITE, false)
					continue
				var acc := await hud.fight_bar()
				await do_fight(acc)
				return "fight"
			1:
				var t := await hud.pick_option(["Deepseek"], 1, _name_col())
				if t < 0:
					hud.start_typing(flavor, C.WHITE, false)
					continue
				var acts: Array = [{"id": "check", "name": "查看"}] if asleep else P["acts"]
				var names := acts.map(func(a): return a["name"])
				var k := await hud.pick_option(names, 2)
				if k < 0:
					hud.start_typing(flavor, C.WHITE, false)
					continue
				if asleep:
					await hud.type_text(Story.RICE_CHECK)
					return "act"
				await do_act(acts[k]["id"], acts[k]["name"])
				return "act"
			2:
				var have := items.filter(func(it): return it["count"] > 0)
				if have.is_empty():
					await hud.type_text("* 什么都没有了。")
					hud.start_typing(flavor, C.WHITE, false)
					continue
				var names := have.map(func(it): return "%s ×%d" % [it["name"], it["count"]])
				var k := await hud.pick_option(names, 2)
				if k < 0:
					hud.start_typing(flavor, C.WHITE, false)
					continue
				await do_item(have[k])
				return "item"
			3:
				var k := await hud.pick_option(["饶恕", "逃跑"], 1, _name_col())
				if k < 0:
					hud.start_typing(flavor, C.WHITE, false)
					continue
				if k == 0:
					if asleep:
						return "rice_spared"
					if spare_ready:
						return "spared"
					await hud.type_text(Story.SPARE_NO)
				else:
					await hud.type_text(Story.FLEE)
				return "mercy"
	return ""


func _name_col() -> Dictionary:
	return {0: C.BTN_HI} if spare_ready or asleep else {}


func _auto_turn() -> String:
	hud.btn_hold = false
	if auto == "rice":
		if asleep:
			return "rice_spared"
		await do_item(items.filter(func(it): return it["id"] == "rice")[0])
		return "item"
	if spare_ready:
		if auto == "spare":
			return "spared"
		await do_fight(0.97)
		return "fight"
	if auto == "kill":
		hud.btn_sel = 0
		await do_fight(0.97)
		return "fight"
	var key: String = Story.PHASES[phase]["key"]
	if spare == 0:
		await do_act(key, key)
	else:
		await do_act("check", "查看")
	return "act"


func do_fight(acc: float) -> void:
	bg.log("[INFO] 用户 · 战斗", C.SYS)
	if acc < 0.0:
		Sfx.play("miss")
		hud.show_damage(-1, her_hp, her_hp, C.ENEMY_HP)
		await wait(1.0)
		return
	var dmg := int(round(lerpf(45.0, 110.0, pow(acc, 1.5))))
	if acc > 0.96:
		dmg = int(dmg * 1.2)
	if spare_ready or finale_done:
		dmg = her_hp          # 终局后她已经没有防御了
	hud.slash()
	await wait(0.22)
	Sfx.play("hit_enemy")
	enemy.hurt()
	var before := her_hp
	her_hp = maxi(0, her_hp - dmg)
	hud.show_damage(dmg, before, her_hp, C.ENEMY_HP)
	await wait(1.3)
	hits_landed += 1
	bg.log("[WARN] 命中  -%d" % dmg, C.RED)
	if spare > 0:
		bg.log("[INFO] 信任 已清零", C.SYS_DIM)
	spare = 0
	if her_hp > 0:
		event_line = Story.HIT_LINE[phase]


func do_act(id: String, name: String) -> void:
	bg.log("[INFO] 用户 · 行动 · %s" % name, C.SYS)
	var P: Dictionary = Story.PHASES[phase]
	var is_key: bool = id == P["key"]
	var k := "%d/%s" % [phase, id]
	if is_key and spare >= 1 and Story.ACTS.has(k + "_again"):
		k += "_again"
	var a: Dictionary = Story.ACTS.get(k, {"text": "* ……"})
	await hud.type_text(a["text"])
	if a.has("vn"):
		for line in a["vn"]:
			await overlay.vn_say(line[0], line[1], C.RED if line.size() > 2 and line[2] else C.WHITE, "voice_red" if phase > 1 else "voice_blue")
		await overlay.vn_close()
	if a.has("reply"):
		await bubble.say(a["reply"], C.RED if a.get("red", false) else C.BLACK, "voice_red" if phase > 1 else "voice_blue")
	if a.has("after"):
		await hud.type_text(a["after"])
	if is_key and spare == 0:
		spare = 1
		bg.log("[INFO] 她在听。", C.SYS)
	match id:
		"regen":
			version += 1
			next_speed = 1.25
			_sync_hud()
			Sfx.play("glitch")
			enemy.set_param("glitch", 0.8)
			enemy.tween_param("glitch", 0.0, 0.5)
			bg.log("[INFO] 重新生成  V%d" % version, C.SYS_DIM)
		"stop", "erase":
			if spare > 0:
				bg.log("[INFO] 信任 已清零", C.SYS_DIM)
			spare = 0
			next_speed = 1.25


func do_item(it: Dictionary) -> void:
	it["count"] -= 1
	for orig in items:
		if orig["id"] == it["id"]:
			orig["count"] = it["count"]
	if it.get("give", false):
		bg.log("[INFO] 用户 · 物品 · %s" % it["name"], C.SYS)
		await hud.type_text(it["text"])
		await Cutscenes.rice(self)
		return
	var heal: int = it["heal"]
	if heal < 0:
		heal = last_damage
	var before := hp
	hp = mini(maxhp, hp + heal)
	_sync_hud()
	Sfx.play("heal")
	bg.log("[INFO] 用户 · 物品 · %s" % it["name"], C.SYS)
	var msg: String = it["text"]
	if hp >= maxhp:
		msg += "\n* HP 回满了。"
	elif hp == before:
		msg += "\n* 可是上一回合你没有受伤。"
	else:
		msg += "\n* HP 回复了 %d 点。" % (hp - before)
	await hud.type_text(msg)


# ════════════════════════════════════════════════════════════
# 她的回合
# ════════════════════════════════════════════════════════════

func _enemy_turn() -> void:
	if spare_ready or asleep:
		return
	var P: Dictionary = Story.PHASES[phase]
	var line := event_line
	if line == "":
		line = P["talk"][talk_i % P["talk"].size()]
		talk_i += 1
	event_line = ""
	var voice := "voice_blue" if phase == 1 else "voice_red"
	await bubble.say(line, C.BLACK, voice)
	var id: String = P["attacks"][attack_i % P["attacks"].size()]
	attack_i += 1
	last_damage = 0
	await run_attack(id, next_speed)
	next_speed = 1.0
	last_damage = turn_damage
	if spare == 1 and not stop.get("touched", false) and _abort == "":
		spare = 2


## 跑一个攻击（终局也用它串起几段）。opts：
##   damage      伤害（默认本阶段的值）
##   box / rect  覆盖弹幕框大小 / 直接给内框矩形
##   start_beat  以配乐绝对拍号开始，并以该拍号作为时间原点（默认下一个整拍）
##   max_beats   最多跑几拍（真实拍数）就截断
##   keep_box    结束后不变回文字框、红心继续可动（终局串段用）
##   keep_soul   开始时不把红心挪到框底（终局串段用）
##   no_stop     不出「■ 停止」按钮
##   其余键原样放进 atk.opts
func run_attack(id: String, speed := 1.0, mirror := false, opts := {}) -> void:
	var path := ATTACK_DIR % id
	if not ResourceLoader.exists(path):
		push_warning("缺少攻击 " + id)
		await wait(0.5)
		return
	var atk: Attack = load(path).new()
	atk.battle = self
	atk.speed = speed
	atk.mirror = mirror
	atk.damage = opts.get("damage", Story.PHASES[phase]["damage"])
	atk.rng.seed = hash(id) + _attack_serial * 7919 + _run_seed
	_attack_serial += 1
	atk.opts = opts
	atk.setup()
	var size: Vector2 = opts.get("box", atk.box_size)
	var r: Rect2 = opts["rect"] if opts.has("rect") else C.dodge_box(size.x, size.y)
	hud.clear_text()
	hud.btn_hold = false
	if box.rect != r:
		await box.morph(r, 0.3)
	atk.box = r
	soul.area = r
	if opts.get("keep_soul", false):
		soul.pos = soul.clamp_in(soul.pos)
	else:
		soul.pos = soul.clamp_in(Vector2(r.get_center().x, r.end.y - 20))
	soul.set_mode(atk.soul_mode)
	if atk.soul_mode == "green":
		soul.pos = r.get_center()
		soul.shield_dir = Vector2i(0, -1)
	soul.active = true
	soul.shown = true
	soul.iframe = 0.0
	soul.pull = Vector2.ZERO
	soul.tether = null
	soul.solids.clear()
	box.mask.add_child(atk)
	cur_attack = atk
	turn_damage = 0
	_shards.clear()
	var sb := atk.stop_beat if atk.stop_beat >= 0.0 else atk.duration * 0.5
	var sp := atk.stop_spot if atk.stop_spot.x >= 0.0 else Vector2(r.end.x - 24, r.position.y + 14)
	stop = {"beat": sb, "pos": sp, "on": false, "touched": false, "state": "", "t": 0.0}
	if opts.has("start_beat"):
		await Conductor.wait_until(opts["start_beat"])
	else:
		await Conductor.wait_beat()
	atk.begin()
	var last := Conductor.beat
	var b_start: float = opts.get("start_beat", last)
	var max_b: float = opts.get("max_beats", 1e9)
	var stopped := false
	var first := true
	while not atk.finished() and Conductor.beat - b_start < max_b:
		await get_tree().process_frame
		if get_tree().paused:
			last = Conductor.beat
			continue
		var b := Conductor.beat
		var db := clampf(b - last, 0.0, 0.5)
		last = b
		atk.prev_t = -0.001 if first else atk.t           # 第一帧从 -0.001 起算，crossed(0) 才会触发（只触发一次）
		first = false
		if opts.has("start_beat"):
			atk.t = maxf(0.0, b - b_start) * atk.speed
		else:
			atk.t += db * atk.speed
		atk.clear_hazards()
		atk.tick(db * atk.speed)
		atk.queue_redraw()
		if not opts.get("no_stop", false) and not atk.no_stop:
			stopped = _stop_update(atk, db)
		_shards_update(db)
		if stopped:
			break
		var hb := soul.hitbox()
		if soul.iframe <= 0.0 and (atk.hits(hb) or _shards_hit(hb)):
			hurt(atk.damage)
			if hp <= 0:
				_abort = "gameover"
				break
	if not opts.get("keep_box", false) or _abort != "":
		soul.active = false
		soul.set_mode("red", true)
	soul.pull = Vector2.ZERO
	soul.tether = null
	soul.solids.clear()
	cur_attack = null
	# 立即执行攻击的样式恢复，避免延迟退出覆盖下一段或终局重置。
	box.mask.remove_child(atk)
	atk.queue_free()
	enemy.set_pose(enemy.idle)
	_shards.clear()
	stop["on"] = false
	if _abort == "" and not opts.get("keep_box", false):
		soul.shown = false
		await box.morph(C.TEXT_BOX, 0.25)


## 屏幕抖动（逻辑像素），攻击里砸地、爆炸时用
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func hurt(d: int) -> void:
	soul.iframe = C.IFRAMES
	Sfx.play("player_hurt")
	_shake = 3.0
	if Settings.invincible or Dbg.has("god"):
		return
	hp = maxi(0, hp - d)
	turn_damage += d
	_sync_hud()
	bg.log("[WARN] 用户 HP -%d" % d, C.RED)


# ── 「■ 停止」按钮 ──────────────────────────────────────────
## 第一阶段：碰到就结束攻击（饶恕进度清零）；第二阶段：盖「已忽略」后炸成碎片；第三阶段：被她的红光标拖走
func _stop_update(atk: Attack, db: float) -> bool:
	if not stop["on"] and stop["state"] == "" and atk.t >= stop["beat"]:
		stop["on"] = true
		stop["t"] = 0.0
		Sfx.play("popup_open")
	if not stop["on"]:
		return false
	stop["t"] += db
	var r := Rect2(stop["pos"] - Vector2(18, 8), Vector2(36, 16))
	match phase:
		1:
			if stop["state"] == "" and r.intersects(soul.hitbox()):
				stop["touched"] = true
				stop["on"] = false
				stop["state"] = "done"
				Sfx.play("stop_press")
				_stop_msg = "已停止生成"
				_stop_msg_t = 0.0
				event_line = Story.STOPPED_LINE
				if spare > 0:
					bg.log("[INFO] 信任 已清零", C.SYS_DIM)
				spare = 0
				bg.log("[INFO] 用户 按下了 停止", C.SYS)
				return true
		2:
			if stop["state"] == "" and r.intersects(soul.hitbox()):
				stop["touched"] = true
				stop["state"] = "stamped"
				stop["t"] = 0.0
				Sfx.play("stamp")
				if spare > 0:
					bg.log("[INFO] 信任 已清零", C.SYS_DIM)
				spare = 0
				bg.log("[WARN] 停止指令 已忽略", C.RED)
			elif stop["state"] == "stamped" and stop["t"] >= 0.5:
				stop["state"] = "done"
				stop["on"] = false
				Sfx.play("shatter")
				for i in 12:
					var a := TAU * i / 12.0
					_shards.append({"p": stop["pos"], "v": Vector2(cos(a), sin(a)) * 70.0})
		3:
			# 出现一拍后，红光标把它往框外拖，1.5 拍拖出画面
			if stop["t"] > 1.0:
				stop["pos"] += Vector2(0, -60.0) * db
				if stop["t"] > 2.5:
					stop["on"] = false
					stop["state"] = "done"
	return false


func _shards_update(db: float) -> void:
	for s in _shards:
		s["p"] += s["v"] * db * Conductor.spb
	_shards = _shards.filter(func(s): return box.rect.grow(10).has_point(s["p"]))


func _shards_hit(hb: Rect2) -> bool:
	for s in _shards:
		if Rect2(s["p"] - Vector2(1.5, 1.5), Vector2(3, 3)).intersects(hb):
			return true
	return false


# ════════════════════════════════════════════════════════════
# 击杀路线
# ════════════════════════════════════════════════════════════

## 返回 true = 结局演完；false = 终局里失败了（主循环会处理重来）
func _kill_route() -> bool:
	if not finale_done:
		await Cutscenes.hp_zero(self)
		await do_finale("kill")
		if _abort != "":
			return false
	# 只剩「战斗」能按
	while true:
		box.morph(C.TEXT_BOX, 0.25)
		hud.btn_dead = [false, true, true, true]
		hud.btn_sel = 0
		hud.start_typing("* Deepseek 跪在地上。\n* 只剩一个按钮还有反应。")
		if auto == "":
			await hud.pick_button()
		else:
			await wait(0.4)
		hud.btn_hold = false
		if await kill_confirm():
			break
	await Cutscenes.kill_ending(self)
	return true


## 「结束进程 determination.exe？」弹窗：确认返回 true
func kill_confirm() -> bool:
	hud.clear_text()
	kill_dialog = {"on": true, "hover": true}
	Sfx.play("popup_open")
	var ok := false
	while true:
		await get_tree().process_frame
		if auto != "":
			await wait(0.6)
			ok = true
			break
		if Inp.take_ok():
			ok = true
			break
		if Inp.take_cancel():
			break
		var tp = Inp.take_tap()
		if tp != null:
			ok = _kill_btn_rect().has_point(to_local(tp))
			if ok:
				break
	if ok:
		Sfx.play("click")
		kill_dialog["pressed"] = true
		await wait(0.25)
	kill_dialog = {}
	return ok


func _kill_btn_rect() -> Rect2:
	return Rect2(240, 246, 160, 26)


# ════════════════════════════════════════════════════════════
# 调试跳转
# ════════════════════════════════════════════════════════════

func _jump(j: String) -> void:
	if j.begins_with("P"):
		var parts := j.substr(1).split("-")
		var n := int(parts[0])
		her_hp = [0, C.ENEMY_HP, C.ENEMY_HP * 2 / 3, C.ENEMY_HP / 3][n]
		await enter_phase(n, true)
		if parts.size() > 1:
			attack_i = int(parts[1]) - 1
		return
	match j:
		"final_kill", "final_spare":
			her_hp = 0 if j == "final_kill" else C.ENEMY_HP / 3
			await enter_phase(3, true)
			if j == "final_spare":
				spare = 2
			else:
				await _kill_route()
		"end_kill":
			await enter_phase(3, true)
			await Cutscenes.kill_ending(self)
		"end_spare":
			await enter_phase(3, true)
			await Cutscenes.spare_ending(self)
		"gameover":
			await enter_phase(1, true)
			if await Cutscenes.game_over(self) == 0:
				restart()
				return
			_restore()
		_:
			await enter_phase(1, true)


# ════════════════════════════════════════════════════════════
# 每帧：屏幕抖动、暂停、标题栏按钮
# ════════════════════════════════════════════════════════════

func _process(dt: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - dt * 20.0)
		position = _base_off + Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake)).round()
	else:
		position = _base_off
	if _stop_msg_t >= 0.0:
		_stop_msg_t += dt
		if _stop_msg_t > 1.0:
			_stop_msg_t = -1.0
	over.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and OS.has_feature("mobile") and not _paused and not _finished:
		set_paused(true)


func set_paused(p: bool) -> void:
	_paused = p
	get_tree().paused = p
	Inp.locked = p
	Conductor.set_paused(p)
	_pause_sel = 0


## 结局只接受结局卡的输入，普通战斗支持Esc及左下角触屏暂停按钮。
func pause_input() -> void:
	if _finished:
		return
	if not _paused:
		if Inp.pause:
			Inp.pause = false
			set_paused(true)
		return
	var d := Inp.take_dir(true)
	if d.y != 0:
		_pause_sel = wrapi(_pause_sel + d.y, 0, 4)
		Sfx.play("menu_move")
	var choose := Inp.take_ok(true)
	if Inp.take_cancel(true) or Inp.pause:
		Inp.pause = false
		set_paused(false)
		return
	var tp = Inp.take_tap(true)
	if tp != null:
		var p := to_local(tp)
		for i in 4:
			if _pause_rect(i).has_point(p):
				_pause_sel = i
				choose = true
	if choose:
		Sfx.play("menu_select")
		match _pause_sel:
			0:
				set_paused(false)
			1:
				Settings.toggle_invincible()
			2:
				return_to_title()
			3:
				get_tree().quit()


func return_to_title() -> void:
	_leave("res://title/title.tscn")


## 失败后选「开启新对话」：整场从头再来（重新载入战斗，开场照常播放，物品和血量全部重置）
func restart() -> void:
	_leave("res://battle/battle.tscn")


func _leave(scene: String) -> void:
	if _returning_to_title:
		return
	_returning_to_title = true
	_finished = true
	Inp.clear_confirm()
	Inp.pause_rect = Rect2()
	set_paused(false)
	get_tree().change_scene_to_file.call_deferred(scene)


func _pause_rect(i: int) -> Rect2:
	return Rect2(230, 138 + i * 24, 180, 20)


# ════════════════════════════════════════════════════════════
# 绘制：框外的攻击元素、停止按钮、碎片、弹窗、暂停菜单
# ════════════════════════════════════════════════════════════

func _draw_over() -> void:
	if big_version != "":
		var w := Fx.version_w(big_version, 24)
		Fx.version(over, big_version, Vector2(roundf(320 - w / 2), 22), C.RED, 24)
	if cur_attack:
		cur_attack.draw_outside(over)
		# 框的上边框兼做进度条：已过去的部分变蓝
		var r := box.rect.grow(C.BORDER)
		var k := clampf(cur_attack.t / cur_attack.duration, 0.0, 1.0)
		over.draw_rect(Rect2(r.position.round(), Vector2(roundf(r.size.x * k), C.BORDER)), C.SYS)
	if stop.get("on", false):
		var p: Vector2 = stop["pos"].round()
		var r := Rect2(p - Vector2(18, 8), Vector2(36, 16))
		var blink: bool = stop["t"] < 0.5 and int(stop["t"] * 8.0) % 2 == 1
		if not blink:
			over.draw_rect(r, C.BLACK)
			Px.frame(over, r, 1, C.BTN)
			over.draw_rect(Rect2(r.position + Vector2(4, 5), Vector2(6, 6)), C.BTN)
			Px.text(over, r.position + Vector2(12, 2), "停止", C.BTN)
		if stop["state"] == "stamped":
			over.draw_rect(Rect2(r.position + Vector2(-3, 1), Vector2(42, 14)), Color(C.RED, 0.9))
			Px.text(over, r.position + Vector2(0, 2), "已忽略", C.WHITE)
		if phase == 3 and stop["t"] > 1.0:
			Px.cursor(over, p + Vector2(6, 2), C.RED)
	for s in _shards:
		over.draw_rect(Rect2(s["p"].round() - Vector2(1, 1), Vector2(3, 3)), C.BTN)
	if _stop_msg_t >= 0.0:
		var w := Px.text_w(_stop_msg)
		var c := box.rect.get_center()
		over.draw_rect(Rect2(c.x - w / 2 - 4, c.y - 9, w + 8, 18), C.BLACK)
		Px.text(over, Vector2(c.x - w / 2, c.y - 6), _stop_msg, C.GRAY)
	if not kill_dialog.is_empty():
		var dr := Rect2(150, 200, 340, 82)
		Px.panel(over, dr)
		Px.text(over, dr.position + Vector2(14, 10), "* 结束进程 determination.exe？")
		var br := _kill_btn_rect()
		var pressed: bool = kill_dialog.get("pressed", false)
		over.draw_rect(br, C.BTN_HI if pressed else C.BLACK)
		Px.frame(over, br, 2, C.BTN_HI)
		Px.text(over, br.position + Vector2(44, 1), "结束进程", C.BLACK if pressed else C.BTN_HI, 24)


func draw_pause(ci: CanvasItem) -> void:
	if _finished:
		return
	if not _paused:
		ci.draw_rect(PAUSE_RECT, Color(C.BLACK, 0.8))
		Px.frame(ci, PAUSE_RECT, 1, C.GRAY_DIM)
		Px.text(ci, PAUSE_RECT.position + Vector2(4, 3), "暂停", C.GRAY)
		return
	Px.screen_rect(ci, position, Color(0, 0, 0, 0.75))
	var r := Rect2(210, 108, 220, 144)
	Px.panel(ci, r)
	Px.text(ci, r.position + Vector2(12, 8), "* 已暂停")
	var labels := ["继续", Settings.invincible_label(), "回到标题", "退出游戏"]
	for i in labels.size():
		var pr := _pause_rect(i)
		Px.text(ci, pr.position + Vector2(16, 2), labels[i], C.BTN_HI if i == _pause_sel else C.WHITE)
		if i == _pause_sel:
			Px.heart(ci, pr.position + Vector2(6, 8))
