extends Node2D
## 界面：四个按钮、HP 行、文字框里的打字机文字和选项、「战斗」瞄准条、她头上的伤害数字和血条、砍她的红色删除线。
## 所有交互都是协程：await type_text(...) / pick_button() / pick_option(...) / fight_bar()。
## 键盘和触屏都能操作；battle.auto 非空时（自动驾驶）文字自动翻页。

const LABELS := ["战斗", "行动", "物品", "仁慈"]
const CPS := 40.0                        # 打字速度（字/秒）
const OPT_X := [58.0, 330.0]             # 选项两列的文字左边
const OPT_Y0 := 202.0
const OPT_DY := 18.0
const BACK_RECT := Rect2(556, 198, 46, 14)
const BAR_AREA := Rect2(48, 204, 544, 68)

var battle: Node
var player_name := "用户"
var lv := 1
var hp := 20
var maxhp := 20

# 按钮
var btn_sel := 0
var btn_cursor := false                  # 红心停在按钮上
var btn_hold := false                    # 选中的按钮保持黄色（进了子菜单）
var btn_dead := [false, false, false, false]   # 「未响应」

# 文字框
var _paras: Array = []                   # [{lines: PackedStringArray, col: Color}]
var _shown := 0.0
var _total := 0
var _typing := false
var _voice := "text_sys"
var _last_blip := 0
var text_visible := true
var _free_typing := false

# 选项
var _opts: Array = []
var _opt_cols := 2
var _opt_sel := 0
var _opt_colors := {}
var _menu := false
var _back := false

# 瞄准条
var _bar_on := false
var _bar_x := 0.0
var _bar_hit := -1.0
var _bar_blink := 0.0

# 伤害数字 / 她的血条 / 删除线
var _dmg_t := -1.0
var _dmg_text := ""
var _dmg_hp0 := 0.0
var _dmg_hp1 := 0.0
var _dmg_max := 1.0
var _slash_t := -1.0


func _process(dt: float) -> void:
	if _typing:
		_shown = minf(_shown + dt * CPS, _total)
		var n := int(_shown)
		if n > _last_blip and n % 2 == 0:
			_last_blip = n
			Sfx.play(_voice)
		if _shown >= _total and _free_typing:
			_typing = false
			_free_typing = false
	if _bar_on and _bar_hit < 0.0:
		_bar_x += dt * 420.0
	if _bar_blink > 0.0:
		_bar_blink -= dt
	if _dmg_t >= 0.0:
		_dmg_t += dt
		if _dmg_t > 1.4:
			_dmg_t = -1.0
	if _slash_t >= 0.0:
		_slash_t += dt
		if _slash_t > 0.6:
			_slash_t = -1.0
	queue_redraw()


func _auto() -> bool:
	return battle != null and battle.auto != ""


## 把视口坐标的点按位置转成本场景的逻辑坐标
func _local(p) -> Vector2:
	return to_local(p)


# ── 文字框 ──────────────────────────────────────────────────

## 在文字框里逐字打出文字。text 用 "\n" 分段，每段以「* 」开头的会做悬挂缩进。
## wait = true：打完后等确认（Z / 点按）再返回；false：打完就返回（文字留在框里）。
func type_text(text: String, col := C.WHITE, voice := "text_sys", wait := true) -> void:
	set_text(text, col)
	_shown = 0.0
	_last_blip = 0
	_voice = voice
	_typing = true
	_free_typing = false
	Inp.take_ok()
	Inp.take_tap()
	while _shown < _total:
		await get_tree().process_frame
		if Inp.take_ok() or Inp.take_tap() != null or Inp.take_cancel():
			_shown = _total
	_typing = false
	if wait:
		await wait_confirm()


## 开始打字但不等、不读输入（你的回合的旁白：边打字边可以选按钮）。animate = false 时直接整段显示
func start_typing(text: String, col := C.WHITE, animate := true) -> void:
	set_text(text, col)
	if animate:
		_shown = 0.0
		_last_blip = 0
		_voice = "text_sys"
		_typing = true
		_free_typing = true


## 直接显示整段文字（不打字）
func set_text(text: String, col := C.WHITE) -> void:
	_paras.clear()
	_total = 0
	for para in text.split("\n"):
		var star := para.begins_with("* ")
		var body := para.substr(2) if star else para
		var lines := Px.wrap(body, C.TEXT_BOX.size.x - 28 - (14 if star else 0))
		if star:
			lines[0] = "* " + lines[0]
		_paras.append({"lines": lines, "col": col, "star": star})
		for l in lines:
			_total += l.length()
	_shown = _total


func clear_text() -> void:
	_paras.clear()
	_total = 0
	_shown = 0


func wait_confirm() -> void:
	if _auto():
		await get_tree().create_timer(0.35, false).timeout
		return
	while true:
		await get_tree().process_frame
		if Inp.take_ok() or Inp.take_tap() != null:
			Sfx.play("menu_move")
			return


# ── 按钮 ────────────────────────────────────────────────────

## 红心停在按钮上，左右选，确认返回序号。点按直接选中。
func pick_button() -> int:
	btn_cursor = true
	btn_hold = false
	Inp.take_ok()
	while true:
		await get_tree().process_frame
		var d := Inp.take_dir()
		if d.x != 0:
			btn_sel = wrapi(btn_sel + d.x, 0, 4)
			Sfx.play("menu_move")
		var choose := Inp.take_ok()
		var tp = Inp.take_tap()
		if tp != null:
			var p := _local(tp)
			for i in 4:
				if C.btn_rect(i).grow_individual(6, 10, 6, 14).has_point(p):
					btn_sel = i
					choose = true
		if choose and not btn_dead[btn_sel]:
			Sfx.play("menu_select")
			btn_cursor = false
			btn_hold = true
			return btn_sel
	return 0


# ── 选项 ────────────────────────────────────────────────────

## 在文字框里列出选项（最多 3 行 × cols 列），返回序号；返回 -1 表示取消。
## colors：{序号: Color}，比如可饶恕时「饶恕」是黄色。
func pick_option(opts: Array, cols := 2, colors := {}) -> int:
	clear_text()
	_opts = opts
	_opt_cols = cols
	_opt_sel = 0
	_opt_colors = colors
	_menu = true
	_back = true
	Inp.take_ok()
	Inp.take_cancel()
	var result := -2
	while result == -2:
		await get_tree().process_frame
		var d := Inp.take_dir()
		if d != Vector2i.ZERO:
			var row := _opt_sel / _opt_cols
			var col := _opt_sel % _opt_cols
			col = wrapi(col + d.x, 0, _opt_cols)
			row += d.y
			var n := row * _opt_cols + col
			if row >= 0 and n < _opts.size() and n >= 0:
				_opt_sel = n
				Sfx.play("menu_move")
		if Inp.take_ok():
			result = _opt_sel
		elif Inp.take_cancel():
			result = -1
		var tp = Inp.take_tap()
		if tp != null:
			var p := _local(tp)
			if BACK_RECT.grow(6).has_point(p):
				result = -1
			for i in _opts.size():
				if _opt_rect(i).has_point(p):
					_opt_sel = i
					result = i
	_menu = false
	_back = false
	Sfx.play("menu_select" if result >= 0 else "menu_back")
	return result


func _opt_pos(i: int) -> Vector2:
	return Vector2(OPT_X[i % _opt_cols] if _opt_cols > 1 else OPT_X[0], OPT_Y0 + (i / _opt_cols) * OPT_DY)


func _opt_rect(i: int) -> Rect2:
	var p := _opt_pos(i)
	return Rect2(p.x - 18, p.y - 3, 250, OPT_DY)


# ── 瞄准条 ──────────────────────────────────────────────────

## 「战斗」瞄准条：竖条从左往右扫，按确认 / 点按停下。返回准度 0..1（1 = 正中），没按就是 -1（未命中）。
func fight_bar() -> float:
	clear_text()
	_bar_on = true
	_bar_x = BAR_AREA.position.x
	_bar_hit = -1.0
	Inp.take_ok()
	Inp.take_tap()
	var acc := -1.0
	var auto_x := BAR_AREA.get_center().x - 6.0
	while _bar_x < BAR_AREA.end.x:
		await get_tree().process_frame
		var hit := Inp.take_ok() or Inp.take_tap() != null
		if _auto() and _bar_x >= auto_x:
			hit = true
		if hit:
			_bar_hit = _bar_x
			acc = clampf(1.0 - absf(_bar_x - BAR_AREA.get_center().x) / (BAR_AREA.size.x / 2.0), 0.0, 1.0)
			_bar_blink = 0.5
			break
	await get_tree().create_timer(0.5, false).timeout
	_bar_on = false
	return acc


# ── 伤害 ────────────────────────────────────────────────────

func show_damage(amount: int, hp0: float, hp1: float, hpmax: float) -> void:
	_dmg_text = "MISS" if amount < 0 else str(amount)
	_dmg_hp0 = hp0
	_dmg_hp1 = hp1
	_dmg_max = hpmax
	_dmg_t = 0.0


func slash() -> void:
	_slash_t = 0.0
	Sfx.play("slash")


# ── 绘制 ────────────────────────────────────────────────────

func _draw() -> void:
	_draw_hp_line()
	for i in 4:
		_draw_button(i)
	var tb: Rect2 = battle.box.rect if battle else C.TEXT_BOX
	var box_is_text := tb.is_equal_approx(C.TEXT_BOX)
	if box_is_text and text_visible:
		_draw_text()
		if _menu:
			_draw_options()
		if _bar_on:
			_draw_bar()
	if _slash_t >= 0.0:
		_draw_slash()
	if _dmg_t >= 0.0:
		_draw_damage()


func _draw_hp_line() -> void:
	var y := C.HP_Y
	var x := 150.0
	Px.text(self, Vector2(x, y), player_name)
	Px.text(self, Vector2(x + 56, y), "LV %d" % lv)
	Px.text(self, Vector2(x + 112, y), "HP")
	var bw := roundf(maxhp * 1.5)
	var bx := x + 132
	draw_rect(Rect2(bx, y + 1, bw, 10), C.RED)
	draw_rect(Rect2(bx, y + 1, roundf(bw * clampf(float(hp) / maxhp, 0, 1)), 10), C.BTN_HI)
	Px.text(self, Vector2(bx + bw + 10, y), "%d / %d" % [hp, maxhp])


func _draw_button(i: int) -> void:
	var r := C.btn_rect(i)
	var dead: bool = btn_dead[i]
	var col := C.GRAY_DIM if dead else (C.BTN_HI if (i == btn_sel and (btn_cursor or btn_hold)) else C.BTN)
	Px.frame(self, r, 2, col)
	if i == btn_sel and btn_cursor:
		Px.heart(self, r.position + Vector2(14, 16))
	else:
		Px.bitmap(self, Px.ICONS[i], r.position + Vector2(8, 10), col)
	if dead:
		Px.text(self, r.position + Vector2(34, 10), "未响应", col)
	else:
		Px.text(self, r.position + Vector2(32, 4), LABELS[i], col, 24)


func _draw_text() -> void:
	var y := C.TEXT_BOX.position.y + 6
	var left := C.TEXT_BOX.position.x + 14
	var budget := int(_shown)
	for p in _paras:
		var first := true
		for l in p["lines"]:
			if budget <= 0:
				return
			var s: String = l
			if budget < s.length():
				s = s.substr(0, budget)
			budget -= l.length()
			var x := left if (first or not p["star"]) else left + 14
			Px.text(self, Vector2(x, y), s, p["col"])
			y += C.LINE_H
			first = false


func _draw_options() -> void:
	for i in _opts.size():
		var p := _opt_pos(i)
		var col: Color = _opt_colors.get(i, C.WHITE)
		Px.text(self, p, "* " + str(_opts[i]), col)
		if i == _opt_sel:
			Px.heart(self, p + Vector2(-11, 6))
	if _back:
		Px.text(self, BACK_RECT.position, "← 返回", C.GRAY)


func _draw_bar() -> void:
	var a := BAR_AREA
	var c := a.get_center()
	# 靶子：一层层收窄的框，越往中间越亮；正中一条红色
	var widths := [544.0, 380.0, 230.0, 100.0]
	var heights := [68.0, 54.0, 40.0, 26.0]
	var cols := [C.SYS_DIM, C.SYS, C.COLD, C.WHITE]
	for k in 4:
		var r := Rect2(c.x - widths[k] / 2, c.y - heights[k] / 2, widths[k], heights[k])
		Px.frame(self, r, 1, cols[k])
	var x := a.position.x + 8
	while x < a.end.x:
		draw_rect(Rect2(x, c.y - 2, 1, 4), C.SYS_DIM)
		x += 16
	draw_rect(Rect2(c.x - 3, a.position.y, 6, a.size.y), C.RED)
	# 竖条：白边黑芯
	var bx := roundf(_bar_hit if _bar_hit >= 0.0 else _bar_x)
	var white := C.BTN_HI if (_bar_blink > 0.0 and int(_bar_blink * 16) % 2 == 0) else C.WHITE
	draw_rect(Rect2(bx - 4, a.position.y - 4, 8, a.size.y + 8), white)
	draw_rect(Rect2(bx - 2, a.position.y - 2, 4, a.size.y + 4), C.BLACK)


func _draw_slash() -> void:
	var er: Rect2 = battle.enemy.rect()
	var y := roundf(er.position.y + er.size.y * 0.46)
	var k := clampf(_slash_t / 0.18, 0, 1)
	var a := 1.0 - clampf((_slash_t - 0.38) / 0.22, 0, 1)
	var x0 := er.position.x + 6
	var w := (er.size.x - 12) * k
	draw_rect(Rect2(x0, y - 1, w, 3), Color(C.RED, a))


func _draw_damage() -> void:
	var t := _dmg_t
	var er: Rect2 = battle.enemy.rect()
	var cx := er.get_center().x
	var y := 22.0 - minf(t, 0.25) * 24.0
	var col := C.GRAY if _dmg_text == "MISS" else C.RED
	Px.text(self, Vector2(cx - Px.text_w(_dmg_text, 24) / 2, y), _dmg_text, col, 24)
	if _dmg_text != "MISS":
		var k := clampf((t - 0.15) / 0.5, 0, 1)
		var cur := lerpf(_dmg_hp0, _dmg_hp1, k)
		var bar := Rect2(cx - 50, 52, 100, 6)
		draw_rect(bar, C.RED_DIM)
		draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * clampf(cur / _dmg_max, 0, 1)), bar.size.y)), C.RED)
