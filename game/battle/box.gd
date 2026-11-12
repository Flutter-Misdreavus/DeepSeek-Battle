extends Node2D
## 框：你的回合是文字框，她的回合缩成弹幕框。rect 是内框，2px 白边画在内框外面。
## 裁剪：_clip 是一个打开 clip_contents 的 Control，位置和大小每帧跟着 rect；
## 它下面的 mask（Node2D）反向偏移 -rect.position，所以挂在 mask 下的攻击节点仍然用整个战斗场景的坐标，画出框的部分会被裁掉。
## （CanvasItem 的 clip_children、渲染服务器的自定义矩形裁剪在 Compatibility 渲染器下实测都不生效，所以用 Control。）
## 红心（soul）挂在 box 下、_clip 后面，不被裁剪，永远画在弹幕上面。

var rect := C.TEXT_BOX
var border_col := C.WHITE
var fill := C.BLACK                  # 框里的底色；终局里用半透明，让背后巨大的她透出来
var mask := Node2D.new()
var _clip := Control.new()
var _tw: Tween


func _ready() -> void:
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.draw.connect(_draw_fill)
	add_child(_clip)
	_clip.add_child(mask)
	_update_clip()


func _update_clip() -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	_clip.position = r.position
	_clip.size = r.size
	mask.position = -r.position


## 变形到新的内框（dur 秒）。可以 await。
func morph(r: Rect2, dur := 0.25) -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	if dur <= 0.0:
		rect = r
		return
	_tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "rect", r, dur)
	await _tw.finished


func _process(_dt: float) -> void:
	_update_clip()
	queue_redraw()
	_clip.queue_redraw()


func _draw_fill() -> void:
	_clip.draw_rect(Rect2(Vector2.ZERO, _clip.size), fill)


func _draw() -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	Px.frame(self, r.grow(C.BORDER), C.BORDER, border_col)
