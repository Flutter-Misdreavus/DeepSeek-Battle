extends Node2D
## 她站在舞台上的全身立绘。贴图：res://art/full/<姿势>.png（683×1024，画布底边中点对准 C.STAGE_FOOT）。
## 换姿势一律换图（Codex 画的），代码只做：像素化过渡、白闪、抖动、呼吸、剪影、负片、故障、红色光晕、透明度。

const SHADER := preload("res://battle/enemy.gdshader")

var idle := "A"
var pose := ""
var breathing := true
var aura := 0.0                  # 红色光晕强度 0..1（第三阶段）
var shake := 0.0                 # 当前横向抖动幅度（逻辑像素）
var foot := C.STAGE_FOOT
var height := C.STAGE_H
var spr := Sprite2D.new()
var glow := Sprite2D.new()
var _mat := ShaderMaterial.new()
var _glow_mat := ShaderMaterial.new()
var _tex := {}
var _busy := 0


func _ready() -> void:
	for s in [glow, spr]:
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(s)
	_mat.shader = SHADER
	spr.material = _mat
	_glow_mat.shader = SHADER
	_glow_mat.set_shader_parameter("sil", 1.0)
	_glow_mat.set_shader_parameter("sil_color", C.RED)
	glow.material = _glow_mat
	glow.visible = false
	set_pose(idle, false)


func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := "res://art/full/%s.png" % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else load("res://art/full/A.png")
	return _tex[name]


func has_pose(name: String) -> bool:
	return ResourceLoader.exists("res://art/full/%s.png" % name)


## 设置待机姿势并切过去
func set_idle(name: String, trans := true) -> void:
	idle = name
	set_pose(name, trans)


## 换姿势；trans = 两帧像素化过渡（约 0.1 秒）
func set_pose(name: String, trans := true) -> void:
	if name == pose:
		return
	pose = name
	if not trans:
		spr.texture = tex(name)
		glow.texture = spr.texture
		return
	_busy += 1
	var tw := create_tween()
	tw.tween_method(func(v): _mat.set_shader_parameter("pixel", v), 1.0, 10.0, 0.05)
	tw.tween_callback(func():
		spr.texture = tex(name)
		glow.texture = spr.texture)
	tw.tween_method(func(v): _mat.set_shader_parameter("pixel", v), 10.0, 1.0, 0.05)
	await tw.finished
	_busy -= 1


## 受击：换 hurt 图、白闪两帧、横向抖动 0.45 秒，然后回到待机姿势
func hurt() -> void:
	var back := idle
	if has_pose("hurt"):
		pose = "hurt"
		spr.texture = tex("hurt")
		glow.texture = spr.texture
	set_param("flash", 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	set_param("flash", 0.0)
	shake = 7.0
	var tw := create_tween()
	tw.tween_property(self, "shake", 0.0, 0.45)
	await tw.finished
	await get_tree().create_timer(0.15, false).timeout
	set_pose(back)


func set_param(k: String, v) -> void:
	_mat.set_shader_parameter(k, v)


func get_param(k: String):
	return _mat.get_shader_parameter(k)


## 用 Tween 改一个着色器参数，可以 await
func tween_param(k: String, to: float, dur: float) -> void:
	var from = get_param(k)
	if from == null:
		from = 0.0
	var tw := create_tween()
	tw.tween_method(func(v): set_param(k, v), float(from), to, dur)
	await tw.finished


func _process(_dt: float) -> void:
	var tx := spr.texture
	if tx == null:
		return
	var s := height / tx.get_height()
	var breath := 0.0
	if breathing:
		breath = 0.006 * sin(Conductor.beat * PI / 2.0)
	var sc := Vector2(s, s * (1.0 + breath))
	spr.scale = sc
	var jitter := 0.0
	if shake > 0.0:
		jitter = round(shake * sin(Time.get_ticks_msec() * 0.09))
	spr.position = Vector2(foot.x - tx.get_width() * s / 2.0 + jitter, foot.y - tx.get_height() * sc.y)
	glow.visible = aura > 0.01
	if glow.visible:
		var gs := sc * (1.0 + 0.035 + 0.01 * sin(Conductor.beat * PI))
		glow.scale = gs
		glow.texture = tx
		glow.position = Vector2(foot.x - tx.get_width() * gs.x / 2.0 + jitter, foot.y + 2 - tx.get_height() * gs.y)
		glow.modulate = Color(1, 1, 1, 0.55 * aura)


## 立绘在屏幕上的矩形（逻辑像素）
func rect() -> Rect2:
	return Rect2(spr.position, spr.texture.get_size() * spr.scale) if spr.texture else Rect2(foot, Vector2.ZERO)
