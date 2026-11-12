extends Node2D
## 顶部窗口标题栏「determination.exe」和右侧三个按钮「_ □ ✕」，铺满可见宽度，画在最上层。
## hit(p)：p 是本场景逻辑坐标，返回 "min" / "max" / "close" / ""。
## cracks：裂纹条数（第三阶段越来越多）；broken：终局时标题栏碎掉不画。

var title := "determination.exe"
var cracks := 0
var broken := false
var col := C.SYS_DIM


func _process(_dt: float) -> void:
	queue_redraw()


func _btn_rects() -> Array:
	var off: Vector2 = get_parent().position
	var right := get_viewport_rect().size.x - off.x
	return [Rect2(right - 54, 0, 18, C.TITLE_H), Rect2(right - 36, 0, 18, C.TITLE_H), Rect2(right - 18, 0, 18, C.TITLE_H)]


func hit(p: Vector2) -> String:
	if broken:
		return ""
	var rs := _btn_rects()
	var names := ["min", "max", "close"]
	for i in 3:
		if (rs[i] as Rect2).grow_individual(4, 0, 4, 10).has_point(p):
			return names[i]
	return ""


func _draw() -> void:
	if broken:
		return
	var off: Vector2 = get_parent().position
	var vs := get_viewport_rect().size
	draw_rect(Rect2(-off.x, 0, vs.x, C.TITLE_H), col)
	Px.text(self, Vector2(-off.x + 5, 1), title)
	var rs := _btn_rects()
	# _
	draw_rect(Rect2(rs[0].position + Vector2(5, 9), Vector2(8, 1)), C.WHITE)
	# □
	Px.frame(self, Rect2(rs[1].position + Vector2(5, 3), Vector2(8, 8)), 1, C.WHITE)
	# ✕（第三阶段起是红底）
	if cracks > 0:
		draw_rect(rs[2], C.RED_DIM)
	for i in 7:
		draw_rect(Rect2(rs[2].position + Vector2(5 + i, 3 + i), Vector2(1, 1)), C.WHITE)
		draw_rect(Rect2(rs[2].position + Vector2(11 - i, 3 + i), Vector2(1, 1)), C.WHITE)
	# 裂纹：从标题栏往下的折线
	for k in cracks:
		var x := fposmod(97.0 * (k + 1) * 3.7, vs.x) - off.x
		var p := Vector2(x, 0)
		for s in 6:
			var q := p + Vector2(fposmod(sin(k * 7.1 + s * 3.3) * 999.0, 14.0) - 7.0, 6 + s * 2)
			draw_line(p, q, Color(C.WHITE, 0.55), 1.0)
			p = q
