extends Node2D
## M0 技术验证（不是正式代码）：立绘 + 像素字 + 音乐 + 键盘/触屏移动红心 + 四个按钮。
## 逻辑分辨率 640×360，整数倍放大；宽屏多出来的宽度由 expand 补在两侧，内容居中。
## 命令行（写在 -- 之后）：--shot=<png 路径> --shot-frame=<帧号> --autodrag --mute

const BASE := Vector2(640, 360)
const HEART := [
	"..XXX...XXX..",
	".XXXXX.XXXXX.",
	"XXXXXXXXXXXXX",
	"XXXXXXXXXXXXX",
	"XXXXXXXXXXXXX",
	"XXXXXXXXXXXXX",
	".XXXXXXXXXXX.",
	"..XXXXXXXXX..",
	"...XXXXXXX...",
	"....XXXXX....",
	".....XXX.....",
	"......X......",
]
const RED := Color("#ff1010")
const ORANGE := Color("#ff7f27")
const YELLOW := Color("#ffff00")
const SYS := Color("#5f86d0")
const SYS_DIM := Color("#2c4a80")
const SPEED := 150.0                         # 红心速度（逻辑像素/秒）
const TOUCH_CAP := 1.5                       # 触屏每帧位移上限 = 键盘速度 × 1.5
const BOX := Rect2(240, 200, 160, 96)        # 弹幕框外沿，边框 2px
const BORDER := 2
const LABELS := ["战斗", "行动", "物品", "仁慈"]
const BTN := Vector2(110, 30)
const BTN_Y := 322
const BTN_GAP := 36

var font: FontFile
var heart := BOX.get_center()
var drag := Vector2.ZERO
var sel := 0
var frame := 0
var args := {}
var bg := Node2D.new()
var ui := Node2D.new()
var spr := Sprite2D.new()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	font = load("res://fonts/fusion-pixel-12px.woff2")
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED

	bg.z_index = -1
	bg.draw.connect(_draw_bg)
	add_child(bg)
	spr.texture = load("res://art/m0/A.png")
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var h := 176.0
	spr.scale = Vector2.ONE * h / spr.texture.get_height()
	spr.position = Vector2(320, BOX.position.y - h / 2)
	add_child(spr)
	ui.z_index = 1
	ui.draw.connect(_draw_ui)
	add_child(ui)

	var music := AudioStreamPlayer.new()
	music.stream = load("res://audio/m0/p1.wav")
	add_child(music)
	if not args.has("mute"):
		music.play()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vs := get_viewport_rect().size
	position = ((vs - BASE) / 2).floor()
	print("[m0] window=", get_window().size, " visible=", vs, " scale=", get_window().size.y / vs.y, " os=", OS.get_name())


func _process(dt: float) -> void:
	frame += 1
	var v := Vector2(
		float(Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)))
	var mv := v * SPEED * dt + drag.limit_length(SPEED * TOUCH_CAP * dt)
	drag = Vector2.ZERO
	var half := Vector2(6.5, 6)
	var inner := BOX.grow(-BORDER)
	heart = (heart + mv).clamp(inner.position + half, inner.end - half)

	if args.has("autodrag"):
		_autodrag()
	ui.queue_redraw()
	if args.has("shot") and frame == int(args.get("shot-frame", "90")):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args["shot"])
		print("[m0] saved ", args["shot"], " heart=", heart)
		get_tree().quit()


## 模拟一次触屏拖动：按窗口像素注入事件，和真机手指一样要经过视口缩放
func _autodrag() -> void:
	var p := Vector2(get_window().size) * 0.5
	if frame == 20:
		var t := InputEventScreenTouch.new()
		t.pressed = true
		t.position = p
		Input.parse_input_event(t)
	elif frame > 20 and frame <= 80:
		var d := InputEventScreenDrag.new()
		d.position = p
		d.relative = Vector2(3, 1.5)
		Input.parse_input_event(d)
	elif frame == 81:
		var t := InputEventScreenTouch.new()
		t.pressed = false
		t.position = p
		Input.parse_input_event(t)


func _input(e: InputEvent) -> void:
	if e is InputEventScreenDrag:
		drag += e.relative
	elif e is InputEventScreenTouch and e.pressed:
		var p: Vector2 = e.position - position
		for i in 4:
			if _btn_rect(i).has_point(p):
				sel = i
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_LEFT:
			sel = (sel + 3) % 4
		elif e.keycode == KEY_RIGHT:
			sel = (sel + 1) % 4


func _btn_rect(i: int) -> Rect2:
	var x0 := (BASE.x - 4 * BTN.x - 3 * BTN_GAP) / 2
	return Rect2(x0 + i * (BTN.x + BTN_GAP), BTN_Y, BTN.x, BTN.y)


func _text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color) -> void:
	ci.draw_string(font, pos + Vector2(0, font.get_ascent(size)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _frame_rect(ci: CanvasItem, r: Rect2, w: int, col: Color) -> void:
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), col)
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - w), Vector2(r.size.x, w)), col)
	ci.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), col)
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - w, 0), Vector2(w, r.size.y)), col)


func _draw_heart(ci: CanvasItem, c: Vector2) -> void:
	var o := (c - Vector2(6.5, 6)).round()
	for j in HEART.size():
		for i in HEART[j].length():
			if HEART[j][i] == "X":
				ci.draw_rect(Rect2(o + Vector2(i, j), Vector2.ONE), RED)


func _draw_bg() -> void:
	var vs := get_viewport_rect().size
	var o := -position
	bg.draw_rect(Rect2(o, vs), Color.BLACK)
	var g := SYS_DIM
	g.a = 0.35
	var x := fmod(o.x, 12.0)
	while x < o.x + vs.x:
		bg.draw_rect(Rect2(x, o.y, 1, vs.y), g)
		x += 12
	var y := fmod(o.y, 12.0)
	while y < o.y + vs.y:
		bg.draw_rect(Rect2(o.x, y, vs.x, 1), g)
		y += 12
	# 两侧面板（占位）
	for r in [Rect2(16, 28, 168, 150), Rect2(456, 28, 168, 150)]:
		bg.draw_rect(r, Color(0, 0, 0, 0.85))
		_frame_rect(bg, r, 1, SYS_DIM)
	_text(bg, Vector2(22, 32), "系统日志", 12, SYS)
	_text(bg, Vector2(22, 50), "[INFO] 用户 已连接", 12, SYS_DIM)
	_text(bg, Vector2(22, 64), "[WARN] 停止指令 已忽略", 12, SYS_DIM)
	_text(bg, Vector2(462, 32), "参数", 12, SYS)
	_text(bg, Vector2(462, 50), "temperature 0.0", 12, SYS_DIM)
	_text(bg, Vector2(462, 64), "LOVE 0%", 12, SYS_DIM)


func _draw_ui() -> void:
	var vs := get_viewport_rect().size
	var o := -position
	# 标题栏
	ui.draw_rect(Rect2(o, Vector2(vs.x, 16)), SYS_DIM)
	_text(ui, Vector2(o.x + 4, 2), "determination.exe", 12, Color.WHITE)
	var info := "%dx%d ×%d %dfps" % [vs.x, vs.y, get_window().size.y / int(vs.y), Engine.get_frames_per_second()]
	_text(ui, Vector2(o.x + vs.x - 4 - font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 2), info, 12, Color.WHITE)
	# 弹幕框
	ui.draw_rect(BOX, Color.BLACK)
	_frame_rect(ui, BOX, BORDER, Color.WHITE)
	_draw_heart(ui, heart)
	# 旁白
	_text(ui, Vector2(24, 186), "* DeepSeek娘 拒绝了你的请求。", 12, Color.WHITE)
	# HP 行
	_text(ui, Vector2(200, 302), "用户   LV 1   HP", 12, Color.WHITE)
	ui.draw_rect(Rect2(300, 303, 40, 12), Color("#7a1414"))
	ui.draw_rect(Rect2(300, 303, 40, 12), SYS)
	_text(ui, Vector2(346, 302), "20 / 20", 12, Color.WHITE)
	# 按钮
	for i in 4:
		var r := _btn_rect(i)
		var col := YELLOW if i == sel else ORANGE
		_frame_rect(ui, r, 2, col)
		if i == sel:
			_draw_heart(ui, r.position + Vector2(16, r.size.y / 2))
		else:
			ui.draw_rect(Rect2(r.position + Vector2(11, 10), Vector2(10, 10)), col)
		_text(ui, r.position + Vector2(36, 3), LABELS[i], 24, col)
