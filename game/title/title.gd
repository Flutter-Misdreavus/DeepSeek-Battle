extends Node2D
## 标题画面：grid 背景 + 左侧她的胸像 + 右侧标题与菜单。
## 逻辑坐标 640×360；根节点像 battle 一样在视口里居中。

const BG := preload("res://battle/bg.gd")
const FRONT := preload("res://art/bust/B.png")
const GLANCE := preload("res://art/bust/B_glance.png")
const CREDIT_TEXT := "B站 水请洗干净"
const CREDIT_URL := "https://space.bilibili.com/161949528"
const CREDIT_NOTE := "  同人作品 · 非商用"

const MENU_X := 330.0
const MENU_Y := 214.0
const MENU_DY := 22.0
const ITEM_RECT := Vector2(180, 18)

var bg := BG.new()
var bust := Sprite2D.new()
var shade := Node2D.new()
var credit_link: LinkButton

var sel := 0
var fade := 0.0
var starting := false
var _items := ["开始", "", "退出"]


func _ready() -> void:
	Inp.clear_confirm()
	Inp.pause_rect = Rect2()
	if Dbg.start_battle_on_launch():       # 调试：直接进战斗
		# 这些节点已在成员初始化时创建，也须交给场景管理以便正常释放。
		for node in [bg, bust, shade]:
			add_child(node)
		starting = true
		get_tree().change_scene_to_file.call_deferred("res://battle/battle.tscn")
		return
	bg.mode = "grid"
	bg.panels = false
	bg.z_index = -2
	add_child(bg)
	var tex: Texture2D = FRONT
	bust.texture = tex
	bust.centered = false
	bust.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bust.z_index = -1
	bust.position = Vector2(24, 40)
	var s := 300.0 / float(tex.get_height())
	bust.scale = Vector2(s, s)
	add_child(bust)
	credit_link = LinkButton.new()
	credit_link.text = CREDIT_TEXT
	credit_link.position = Vector2(630.0 - Px.text_w(CREDIT_NOTE) - Px.text_w(CREDIT_TEXT), 338)
	credit_link.add_theme_font_override("font", Px.font())
	credit_link.add_theme_font_size_override("font_size", 12)
	credit_link.add_theme_color_override("font_color", C.GRAY_DIM)
	credit_link.add_theme_color_override("font_hover_color", C.SYS)
	credit_link.add_theme_color_override("font_pressed_color", C.SYS)
	credit_link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	credit_link.focus_mode = Control.FOCUS_NONE
	credit_link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	credit_link.pressed.connect(_open_credit)
	add_child(credit_link)
	shade.z_index = 100
	shade.draw.connect(_draw_shade)
	add_child(shade)
	get_viewport().size_changed.connect(_layout)
	_layout()
	Conductor.play("title")


func _layout() -> void:
	position = ((get_viewport_rect().size - C.BASE) / 2).floor()


func _process(_dt: float) -> void:
	queue_redraw()
	shade.queue_redraw()
	if starting:
		return
	var d := Inp.take_dir()
	if d.y != 0:
		sel = wrapi(sel + (1 if d.y > 0 else -1), 0, _items.size())
		Sfx.play("menu_move")
	var choose := Inp.take_ok()
	var tp = Inp.take_tap()
	if tp != null:
		var p := to_local(tp)
		for i in _items.size():
			if _item_rect(i).has_point(p):
				sel = i
				choose = true
	if choose:
		_choose(sel)


func _item_rect(i: int) -> Rect2:
	return Rect2(Vector2(MENU_X, MENU_Y + i * MENU_DY) - Vector2(16, 3), ITEM_RECT)


func _open_credit() -> void:
	OS.shell_open(CREDIT_URL)


func _item_pos(i: int) -> Vector2:
	return Vector2(MENU_X, MENU_Y + i * MENU_DY)


func _choose(i: int) -> void:
	if i == 1:
		Settings.toggle_invincible()
		Sfx.play("menu_select")
		return
	if i == 2:
		get_tree().quit()
		return
	starting = true
	bust.texture = GLANCE
	credit_link.disabled = true
	Sfx.play("menu_select")
	Conductor.stop(0.6)
	Conductor.set_lowpass(false)
	var tw := create_tween()
	tw.tween_property(self, "fade", 1.0, 0.6)
	await tw.finished
	get_tree().change_scene_to_file("res://battle/battle.tscn")


func _draw_shade() -> void:
	if fade <= 0.0:
		return
	Px.screen_rect(shade, position, Color(C.BLACK, fade))


func _draw() -> void:
	Px.text(self, Vector2(300, 64), "STRONGER", C.WHITE, 36)
	Px.text(self, Vector2(300, 104), "THAN YOU", C.WHITE, 36)
	var x := 300.0 + Px.text_w("THAN YOU", 36)
	Px.text(self, Vector2(x, 104), " :)", C.RED, 36)
	Px.text(self, Vector2(302, 152), "Deepseek Boss 战", C.SYS)
	for i in _items.size():
		var p := _item_pos(i)
		var col := C.BTN_HI if i == sel else C.WHITE
		Px.text(self, p, Settings.invincible_label() if i == 1 else _items[i], col)
		if i == sel:
			Px.heart(self, p + Vector2(-12, 6))
	var hint := "Z / Enter 确定   方向键 移动   手机：点按 / 拖动"
	Px.text(self, Vector2(630.0 - Px.text_w(hint), 318), hint, C.GRAY_DIM)
	Px.text(self, Vector2(630.0 - Px.text_w(CREDIT_NOTE), 338), CREDIT_NOTE, C.GRAY_DIM)
