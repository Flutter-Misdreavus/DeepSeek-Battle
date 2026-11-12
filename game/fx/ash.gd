class_name Ash
extends Node2D
## 像素灰（从 MV 的 ash.ts 移植）：把一张立绘切成方块，按进度 u 一块块脱落、发白、变灰、飘走。
##   u = 0 完整，u = 1 全部消失；u 倒着走（1 → 0）就是「重新生成」：灰飞回来拼成人。
## 纯函数：同样的参数和 u 永远画出同一帧。
## 用法：
##   var ash := Ash.new(); add_child(ash)
##   ash.setup(enemy.spr.texture, enemy.rect())     # 立绘在屏幕上的矩形
##   enemy.spr.visible = false
##   await ash.play(1.2)                              # 碎掉；ash.play(0.8, 1.0, 0.0) 倒放重组

var u := 0.0
var block := 3.0                    # 方块边长（逻辑像素）
var dir := Vector2(0, -1)           # 飞行方向
var travel := 120.0                 # 飞多远
var noise := 0.45                   # 顺序里随机的成分
var band := 0.25                    # 每块从脱落到消失占总进度的比例
var hot := Color(1, 1, 1)           # 脱落瞬间的高亮色
var ash_col := Color(0.62, 0.65, 0.72)
var origin := Vector2(-1, -1)       # 不为 (-1,-1) 时：从这个屏幕点向外扩散（代替「从边缘往里吃」）

var _rect := Rect2()
var _blocks: Array = []             # 每块：[gx, gy, Color, order]
var _bw := 3.0
var _bh := 3.0


func setup(tex: Texture2D, rect: Rect2, seed := 1) -> void:
	_rect = rect
	var cols := maxi(1, int(round(rect.size.x / block)))
	var rows := maxi(1, int(round(rect.size.y / block)))
	_bw = rect.size.x / cols
	_bh = rect.size.y / rows
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(cols, rows, Image.INTERPOLATE_LANCZOS)
	var solid := PackedByteArray()
	solid.resize(cols * rows)
	for gy in rows:
		for gx in cols:
			solid[gy * cols + gx] = 1 if img.get_pixel(gx, gy).a > 0.5 else 0
	# 到最近透明格的距离（4 邻域 BFS），用来「从边缘往里吃」
	var dist := PackedInt32Array()
	dist.resize(cols * rows)
	dist.fill(-1)
	var q := PackedInt32Array()
	for gy in rows:
		for gx in cols:
			var i := gy * cols + gx
			var border := gx == 0 or gy == 0 or gx == cols - 1 or gy == rows - 1
			if solid[i] == 0 or border:
				dist[i] = 1 if solid[i] == 1 else 0
				q.append(i)
	var k := 0
	while k < q.size():
		var i := q[k]
		k += 1
		var gx := i % cols
		var gy := i / cols
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = gx + d.x
			var ny: int = gy + d.y
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var j := ny * cols + nx
			if dist[j] >= 0:
				continue
			dist[j] = dist[i] + 1
			q.append(j)
	var max_edge := 1
	for i in dist.size():
		max_edge = maxi(max_edge, dist[i])
	var max_r := Vector2(cols, rows).length()
	_blocks.clear()
	for gy in rows:
		for gx in cols:
			var i := gy * cols + gx
			if solid[i] == 0:
				continue
			var c := img.get_pixel(gx, gy)
			c.a = 1.0
			var h1 := _hash(gx, gy, seed, 1)
			var base: float
			if origin.x >= 0.0:
				var p := Vector2(rect.position.x + (gx + 0.5) * _bw, rect.position.y + (gy + 0.5) * _bh)
				base = p.distance_to(origin) / (max_r * block)
			else:
				base = float(dist[i] - 1) / max_edge
			var order := clampf(base * (1.0 - noise) + h1 * noise, 0.0, 1.0) * (1.0 - band)
			_blocks.append([gx, gy, c, order, _hash(gx, gy, seed, 2), _hash(gx, gy, seed, 3)])
	queue_redraw()


## 把 u 从 from_u 补间到 to_u（dur 秒），可以 await
func play(dur: float, from_u := 0.0, to_u := 1.0) -> void:
	u = from_u
	var tw := create_tween()
	tw.tween_property(self, "u", to_u, dur)
	await tw.finished


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if u >= 1.0 or _blocks.is_empty():
		return
	for b in _blocks:
		var order: float = b[3]
		var lp := clampf((u - order) / band, 0.0, 1.0)
		if lp >= 1.0:
			continue
		var p := Vector2(_rect.position.x + b[0] * _bw, _rect.position.y + b[1] * _bh)
		if lp <= 0.0:
			draw_rect(Rect2(p.round(), Vector2(ceilf(_bw), ceilf(_bh))), b[2])
			continue
		var col: Color
		if lp < 0.15:
			col = (b[2] as Color).lerp(hot, lp / 0.15)
		else:
			col = hot.lerp(ash_col, clampf((lp - 0.15) / 0.35, 0.0, 1.0))
		col.a = 1.0 - smoothstep(0.6, 1.0, lp)
		var h2: float = b[4]
		var h3: float = b[5]
		var off: Vector2 = dir * travel * lp * lp * (0.7 + 0.6 * h3) + Vector2((h2 - 0.5) * travel * 0.35 * lp, 0)
		var s := maxf(1.0, _bw * (1.0 - 0.4 * lp))
		draw_rect(Rect2((p + off).round(), Vector2(s, s).round()), col)


static func _hash(a: int, b: int, c: int, d: int) -> float:
	var h := (a * 374761393 + b * 668265263 + c * 2147483647 + d * 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 100000) / 100000.0
