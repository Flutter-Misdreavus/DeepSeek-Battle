extends Attack
## P1-3「服务器繁忙」
##
## 五个加载圈按节拍冒出来，转两拍后把八个点朝八个方向射出去；最后一条带缺口的「服务器繁忙」横幅
## 从上往下扫过整个框。
## - 加载圈出现后 2 拍只是转圈（预警），第 spawn+2 拍炸开；飞点出框后不再画也不判定。
## - 横幅在第 10.5 拍开始闪顶边预警，11.5 拍出现并向下扫，15.5 拍离开。
## - 横幅 26px 的缺口里什么都没有，红心从缺口穿过去。
## - mirror = true 时加载圈和缺口左右镜像。

const SPAWN_BEATS := [0.0, 2.0, 4.0, 6.0, 8.0]
const CENTER_RATIOS := [
	Vector2(0.25, 0.30),
	Vector2(0.75, 0.35),
	Vector2(0.50, 0.62),
	Vector2(0.22, 0.72),
	Vector2(0.78, 0.70),
]
const GAP_W := 26.0
const BANNER_H := 16.0
const CHAR_W := 12.0
const PHRASE := "服务器繁忙，请稍后再试。"


func setup() -> void:
	duration = 16.0
	box_size = Vector2(180, 120)
	stop_beat = 6.0


## 第 j 个加载圈在拍 t 的圆心
func _center(j: int) -> Vector2:
	var r: Vector2 = CENTER_RATIOS[j]
	if mirror:
		r.x = 1.0 - r.x
	return box.position + r * box.size


## 第 j 个加载圈第 k 个点的角度；第 1、3 个圈整体多转 22.5°
func _angle(j: int, k: int) -> float:
	var deg := k * 45.0
	if j == 0 or j == 2:
		deg += 22.5
	return deg_to_rad(deg)


## 横幅缺口左边的 x
func _gap_x() -> float:
	var gx := box.position.x + 0.62 * box.size.x - GAP_W * 0.5
	if mirror:
		gx = box.end.x - (gx - box.position.x) - GAP_W
	return gx


## 横幅顶边 y
func _banner_y() -> float:
	return box.position.y - BANNER_H + (t - 11.5) / 4.0 * (box.size.y + BANNER_H)


## 炸开的第 k 个点在这一帧的位置
func _burst_pos(c: Vector2, j: int, k: int, burst: float) -> Vector2:
	var d := Vector2(cos(_angle(j, k)), sin(_angle(j, k)))
	return c + d * (7.0 + 40.0 * (t - burst))


func tick(_dt: float) -> void:
	for j in SPAWN_BEATS.size():
		var burst: float = SPAWN_BEATS[j] + 2.0
		if crossed(burst):
			sfx("spinner_burst")
		if t >= burst:
			var c := _center(j)
			for k in 8:
				var p := _burst_pos(c, j, k, burst)
				if box.grow(8.0).has_point(p):
					hz_circle(p, 1.6)
	if crossed(10.5):
		sfx("warn")
	if crossed(11.5):
		sfx("glitch")
		pose("snow")
	if t >= 11.5 and t < 15.5:
		var gx := _gap_x()
		var by := roundf(_banner_y())
		var lw := gx - box.position.x
		var rw := box.end.x - (gx + GAP_W)
		if lw > 0.0:
			hz_rect(Rect2(box.position.x, by + 1.0, lw, BANNER_H - 2.0))
		if rw > 0.0:
			hz_rect(Rect2(gx + GAP_W, by + 1.0, rw, BANNER_H - 2.0))


func _draw() -> void:
	for j in SPAWN_BEATS.size():
		var spawn: float = SPAWN_BEATS[j]
		var burst := spawn + 2.0
		if t < spawn:
			continue
		var c := _center(j)
		if t < burst:
			var h := floori((t - spawn) * 8.0) % 8
			for k in 8:
				var p := c + Vector2(cos(_angle(j, k)), sin(_angle(j, k))) * 7.0
				var behind := (h - k + 8) % 8
				var col := C.GRAY_DIM
				match behind:
					0:
						col = C.WHITE
					1:
						col = C.COLD
					2:
						col = C.SYS
					3:
						col = C.SYS_DIM
				draw_rect(Rect2((p - Vector2(1, 1)).round(), Vector2(2, 2)), col)
		else:
			for k in 8:
				var p := _burst_pos(c, j, k, burst)
				if box.grow(8.0).has_point(p):
					draw_rect(Rect2((p - Vector2(1.5, 1.5)).round(), Vector2(3, 3)), C.WHITE)
	# 横幅出现前：顶边一条闪烁的灰线，缺口处断开
	if t >= 10.5 and t < 11.5 and int(t * 4.0) % 2 == 0:
		var gx := _gap_x()
		var y := roundf(box.position.y + 1.0)
		var x0 := roundf(box.position.x)
		var x1 := roundf(gx)
		var x2 := roundf(gx + GAP_W)
		var x3 := roundf(box.end.x)
		draw_rect(Rect2(x0, y, x1 - x0, 1.0), C.GRAY)
		draw_rect(Rect2(x2, y, x3 - x2, 1.0), C.GRAY)
	# 横幅：缺口两侧各一段，文字逐字画、跳过缺口
	if t >= 11.5 and t < 15.5:
		var gx := _gap_x()
		var by := roundf(_banner_y())
		_draw_banner_seg(Rect2(box.position.x, by, gx - box.position.x, BANNER_H))
		_draw_banner_seg(Rect2(gx + GAP_W, by, box.end.x - gx - GAP_W, BANNER_H))
		var phrase_w := CHAR_W * PHRASE.length()
		var scroll := fposmod(20.0 * (t - 11.5), phrase_w)
		var x := box.position.x - scroll
		var ty := by + 2.0
		var ci := 0
		while x < box.end.x:
			var ch := PHRASE[ci % PHRASE.length()]
			# 和缺口有重叠的字整个不画
			if not (x < gx + GAP_W and x + CHAR_W > gx):
				Px.text(self, Vector2(x, ty), ch, C.GRAY)
			x += CHAR_W
			ci += 1


## 横幅的一段：直接画，框外部分交给框的裁剪
func _draw_banner_seg(r: Rect2) -> void:
	if r.size.x <= 0.0:
		return
	var rr := Rect2(r.position.round(), Vector2(roundf(r.size.x), BANNER_H))
	draw_rect(rr, C.BLACK)
	Px.frame(self, rr, 1.0, C.WHITE)
