extends Node2D
## 玩家的红心。pos 是中心（逻辑像素）。弹幕阶段 active = true 时可以移动，被限制在 area（框的内框）里。
## pull：外力（逻辑像素/秒），拖拽攻击用；tether：非 null 时从这点到红心画一根红线。

var pos := Vector2(320, 238)
var active := false
var area := Rect2()
var pull := Vector2.ZERO
var tether = null
var iframe := 0.0
var shown := true
var col := C.HEART


func _process(dt: float) -> void:
	if iframe > 0.0:
		iframe -= dt
	if active:
		var v := Inp.move_vec() * C.SOUL_SPEED * dt
		v += Inp.drag.limit_length(C.SOUL_SPEED * C.TOUCH_CAP * dt)
		v += pull * dt
		pos = clamp_in(pos + v)
	queue_redraw()


func clamp_in(p: Vector2) -> Vector2:
	if area.size == Vector2.ZERO:
		return p
	return p.clamp(area.position + C.SOUL_HALF, area.end - C.SOUL_HALF)


func hitbox() -> Rect2:
	return Rect2(pos - C.HITBOX / 2, C.HITBOX)


func _draw() -> void:
	if not shown:
		return
	if tether != null:
		var a: Vector2 = tether
		draw_line(a.round() + Vector2(0.5, 0.5), pos.round() + Vector2(0.5, 0.5), C.RED, 1.0)
	if iframe > 0.0 and int(iframe * 12.0) % 2 == 0:
		return
	Px.heart(self, pos, col)
