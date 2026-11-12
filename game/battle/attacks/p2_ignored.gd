extends Attack
## P2-1「已忽略」
##
## 她的「停止」弹窗一个接一个弹开，每到节拍就被盖上「已忽略」，再碎成像素飞出去。
## - 第 k 个弹窗在 0.5 + 1.5k 拍弹开，1 拍后盖章，1.5 拍后碎裂。
## - 弹窗本身不伤人；12 块碎片以每拍约 52px 向外飞散，碎片才伤人。
## - 碎片出框（外扩 6px）后就消失，位置写成 t 的纯函数。

const POPUP_SIZE := Vector2(64, 38)
const POPUPS := 9

const OFFSETS := [
	Vector2(8, 8),
	Vector2(128, 10),
	Vector2(68, 50),
	Vector2(12, 86),
	Vector2(124, 88),
	Vector2(40, 26),
	Vector2(96, 62),
	Vector2(10, 48),
	Vector2(130, 48),
]

var _popups: Array = []           # 每个弹窗：{s, off, frags: [{dir, speed}]}


func setup() -> void:
	duration = 16.0
	box_size = Vector2(200, 130)
	stop_beat = 5.0
	for k in POPUPS:
		var frags: Array = []
		for j in 12:
			var local := Vector2(
				8.0 + 16.0 * (j % 4),
				8.0 + 11.0 * int(j / 4.0)
			)
			# 起点相对弹窗中心的偏移，归一化后就是飞散方向
			var dir := (local - POPUP_SIZE * 0.5).normalized()
			var spd := 52.0 * (0.85 + 0.3 * rng.randf())
			frags.append({"dir": dir, "speed": spd})
		_popups.append({
			"s": 0.5 + 1.5 * k,
			"off": OFFSETS[k],
			"frags": frags,
		})


## 第 k 个弹窗左上角（镜像时以框右边为轴翻 x）
func _popup_pos(k: int) -> Vector2:
	var off: Vector2 = _popups[k]["off"]
	if mirror:
		return Vector2(box.end.x - off.x - POPUP_SIZE.x, box.position.y + off.y)
	return box.position + off


## 第 j 块碎片在拍 t 的位置
func _frag_pos(k: int, j: int) -> Vector2:
	var p := _popup_pos(k)
	var local := Vector2(
		8.0 + 16.0 * (j % 4),
		8.0 + 11.0 * int(j / 4.0)
	)
	var f: Dictionary = _popups[k]["frags"][j]
	var age: float = t - (_popups[k]["s"] + 1.5)
	return p + local + f["dir"] * f["speed"] * age


func tick(_dt: float) -> void:
	for k in POPUPS:
		var s: float = _popups[k]["s"]
		if crossed(s):
			sfx("popup_open")
		if crossed(s + 1.0):
			sfx("stamp")
			pose("sweep" if k % 2 == 0 else "segF_sweep2")
		if crossed(s + 1.5):
			sfx("shatter")
	# 碎片伤害：只在碎裂后、还没飞出框外扩 6px 的范围时登记
	for k in POPUPS:
		var shatter: float = _popups[k]["s"] + 1.5
		if t < shatter:
			continue
		for j in 12:
			var pos := _frag_pos(k, j)
			if box.grow(6).has_point(pos):
				hz_circle(pos, 1.6)


func _draw() -> void:
	for k in POPUPS:
		var s: float = _popups[k]["s"]
		if t < s:
			continue
		var shatter: float = s + 1.5
		if t >= shatter:
			for j in 12:
				var pos := _frag_pos(k, j)
				if box.grow(6).has_point(pos):
					draw_rect(Rect2((pos - Vector2(1.5, 1.5)).round(), Vector2(3, 3)), C.RED)
			continue
		var p := _popup_pos(k)
		if t < s + 0.15:
			# 弹开动画：只有缩放后的主体和边框，没有文字
			var sc := lerpf(0.6, 1.0, clampf((t - s) / 0.15, 0.0, 1.0))
			var center := p + POPUP_SIZE * 0.5
			var sz := (POPUP_SIZE * sc).round()
			var r := Rect2((center - sz * 0.5).round(), sz)
			draw_rect(r, C.BLACK)
			Px.frame(self, r, 1.0, C.WHITE)
			continue
		_draw_popup(p)
		if t >= s + 1.0:
			_draw_stamp(p)


func _draw_popup(p: Vector2) -> void:
	var r := Rect2(p.round(), POPUP_SIZE)
	draw_rect(r, C.BLACK)
	Px.frame(self, r, 1.0, C.WHITE)
	draw_rect(Rect2((p + Vector2(1, 1)).round(), Vector2(62, 12)), C.SYS_DIM)
	Px.text(self, p + Vector2(4, 1), "提示", C.WHITE)
	Px.text(self, p + Vector2(53, 1), "×", C.WHITE)
	Px.text(self, p + Vector2(14, 18), "■ 停止", C.BTN)


func _draw_stamp(p: Vector2) -> void:
	var r := Rect2((p + Vector2(6, 14)).round(), Vector2(52, 18))
	draw_rect(r, Color(C.RED, 0.92))
	Px.frame(self, r, 1.0, C.WHITE)
	Px.text(self, p + Vector2(14, 17), "已忽略", C.WHITE)
