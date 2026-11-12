extends Node2D
## 最上层的全屏效果（在标题栏下面）：
##   fade      黑幕透明度 0..1（fade_col 可改颜色）
##   flash     白闪透明度 0..1
##   cut-in    全屏插图（res://art/cutin/<名字>.png，按「铺满」缩放，可淡入、放大）
##   VN 对白   画面压暗，半身立绘（res://art/half/<名字>.png）从右侧滑入，左边白框对话框逐字打出
##             构图照 MV 结尾那张：对话框 x 24–356，y 214–340；立绘右侧，高 380，底部出画

const VN_BOX := Rect2(24, 214, 332, 118)
const VN_H := 380.0
const CPS := 26.0

var battle: Node
var fade := 0.0
var fade_col := C.BLACK
var flash := 0.0
var cut_tex: Texture2D
var cut_alpha := 0.0
var cut_zoom := 1.0
var vn_on := false
var vn_dim := 0.0
var vn_x := 1.0                    # 立绘滑入进度 0..1（1 = 在场外）
var vn_tex: Texture2D
var vn_glow := false               # 立绘身后红光（MV 结尾那样）
var _vn_lines := PackedStringArray()
var _vn_col := C.WHITE
var _vn_shown := 0.0
var _vn_total := 0
var _vn_typing := false
var _vn_voice := "voice_blue"
var _vn_last := 0
var _half := {}


func _process(dt: float) -> void:
	if _vn_typing:
		_vn_shown = minf(_vn_shown + dt * CPS, _vn_total)
		var n := int(_vn_shown)
		if n > _vn_last:
			_vn_last = n
			Sfx.play(_vn_voice, randf_range(0.97, 1.03))
	queue_redraw()


func tween(prop: String, to: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, prop, to, dur)
	await tw.finished


func do_flash(dur := 0.25) -> void:
	flash = 1.0
	await tween("flash", 0.0, dur)


func show_cutin(name: String, dur := 0.2, zoom := 1.0) -> void:
	cut_tex = load("res://art/cutin/%s.png" % name)
	cut_zoom = zoom
	if dur <= 0.0:
		cut_alpha = 1.0
	else:
		await tween("cut_alpha", 1.0, dur)


func hide_cutin(dur := 0.2) -> void:
	if dur <= 0.0:
		cut_alpha = 0.0
	else:
		await tween("cut_alpha", 0.0, dur)
	cut_tex = null


## name 可以是 "C"（默认 half 目录）或带目录的 "bust/B_red"、"half/cheeks"
func half_tex(name: String) -> Texture2D:
	if not _half.has(name):
		var path := "res://art/%s.png" % name if "/" in name else "res://art/half/%s.png" % name
		_half[name] = load(path)
	return _half[name]


## VN 对白一句：立绘换成 half（若和上一句不同，用像素化过渡也可以；这里直接换），逐字打出，等确认
func vn_say(half: String, text: String, col := C.WHITE, voice := "voice_blue") -> void:
	vn_tex = half_tex(half)
	if not vn_on:
		vn_on = true
		vn_x = 1.0
		var tw := create_tween().set_parallel()
		tw.tween_property(self, "vn_dim", 0.72, 0.25)
		tw.tween_property(self, "vn_x", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await tw.finished
	_vn_lines = Px.wrap("* " + text, VN_BOX.size.x - 28)
	_vn_total = 0
	for l in _vn_lines:
		_vn_total += l.length()
	_vn_col = col
	_vn_voice = voice
	_vn_shown = 0.0
	_vn_last = 0
	_vn_typing = true
	Inp.take_ok()
	Inp.take_tap()
	while _vn_shown < _vn_total:
		await get_tree().process_frame
		if Inp.take_ok() or Inp.take_tap() != null:
			_vn_shown = _vn_total
	_vn_typing = false
	if battle and battle.auto != "":
		await get_tree().create_timer(0.5, false).timeout
	else:
		while true:
			await get_tree().process_frame
			if Inp.take_ok() or Inp.take_tap() != null:
				break


func vn_close() -> void:
	if not vn_on:
		return
	_vn_lines = PackedStringArray()
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "vn_dim", 0.0, 0.25)
	tw.tween_property(self, "vn_x", 1.0, 0.25)
	await tw.finished
	vn_on = false
	vn_tex = null


func _draw() -> void:
	var off: Vector2 = get_parent().position
	var vs := get_viewport_rect().size
	var full := Rect2(-off, vs)
	if vn_on:
		_draw_vn(full)
	if cut_tex and cut_alpha > 0.0:
		var ts := cut_tex.get_size()
		var s := maxf(vs.x / ts.x, vs.y / ts.y) * cut_zoom
		var sz := ts * s
		draw_texture_rect(cut_tex, Rect2(full.get_center() - sz / 2, sz), false, Color(1, 1, 1, cut_alpha))
	if fade > 0.0:
		draw_rect(full, Color(fade_col, fade))
	if flash > 0.0:
		draw_rect(full, Color(1, 1, 1, flash))


func _draw_vn(full: Rect2) -> void:
	draw_rect(full, Color(0, 0, 0, vn_dim))
	if vn_tex:
		var ts := vn_tex.get_size()
		var s := VN_H / ts.y
		var w := ts.x * s
		var x := 590.0 - w / 2.0 + vn_x * 260.0
		if vn_glow:
			for i in 6:
				draw_circle(Vector2(x + w / 2, 150), 60 + i * 30, Color(0.9, 0.05, 0.05, 0.07))
		draw_texture_rect(vn_tex, Rect2(x, 14, w, VN_H), false)
	if _vn_lines.size() > 0 or _vn_typing:
		Px.panel(self, VN_BOX)
		var budget := int(_vn_shown)
		var y := VN_BOX.position.y + 8
		var first := true
		for l in _vn_lines:
			if budget <= 0:
				break
			Px.text(self, Vector2(VN_BOX.position.x + 12 + (0 if first else 14), y), l.substr(0, budget), _vn_col)
			budget -= l.length()
			y += C.LINE_H
			first = false
