extends Node2D
## 框：你的回合是文字框，她的回合缩成弹幕框。rect 是内框，2px 白边画在内框外面。
## 子节点 mask 打开了 clip_children：攻击节点挂在 mask 下面，画出框的部分会被裁掉。
## 红心（soul）挂在 mask 后面，不被裁剪，永远画在弹幕上面。

var rect := C.TEXT_BOX
var border_col := C.WHITE
var mask := Node2D.new()
var _tw: Tween


func _ready() -> void:
	mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	mask.draw.connect(_draw_mask)
	add_child(mask)


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
	queue_redraw()
	mask.queue_redraw()


func _draw_mask() -> void:
	mask.draw_rect(Rect2(rect.position.round(), rect.size.round()), C.BLACK)


func _draw() -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	Px.frame(self, r.grow(C.BORDER), C.BORDER, border_col)
