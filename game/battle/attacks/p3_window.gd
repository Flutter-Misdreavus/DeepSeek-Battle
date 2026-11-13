extends Attack
## P3-2「窗口暴力」
##
## 弹幕框就是一个窗口。A 段重力朝下，桌面图标贴着底边从右往左滑，要跳过去；
## B 段她拖住窗口右边把框压窄再拉回；C 段她抓住标题栏连甩四次，每次都换重力，
## 新一批图标贴着新的「地面」滑进来。
## - 窗口的位移 / 缩放全部写成 t 的函数：每帧同时改 box、battle.box.rect、battle.soul.area，
##   甩的时候心也跟着同样的位移走。
## - 图标的速度、进场端和重力都预先写在 ICON_PLAN 里；这里的「地面」就是当前重力那面墙。
## - mirror = true：甩的方向和水平墙的进场端左右镜像。

const ICON_SPEED := 70.0
const FLING_LEN := 0.25
const FLING_PX := 12.0
const SHRINK_FROM := 6.5
const SHRINK_TO := 7.25
const SHRINK_W := 110.0
const WARN_LEN := 0.5

const FOLDER := [
	"XXXXX.......",
	"X...XXXXXXXX",
	"X..........X",
	"XXXXXXXXXXXX",
	"X..........X",
	"X..........X",
	"X..........X",
	"X..........X",
	"X..........X",
	"XXXXXXXXXXXX",
]
const RECYCLE := [
	"...XXXXXX...",
	"XXXXXXXXXXXX",
	".X........X.",
	".X.X.XX.X.X.",
	".X.X.XX.X.X.",
	".X.X.XX.X.X.",
	".X.X.XX.X.X.",
	".X.X.XX.X.X.",
	".X.X.XX.X.X.",
	".X........X.",
	"..XXXXXXXX..",
	"............",
]
const DOC := [
	"XXXXXXX...",
	"X.....XX..",
	"X.....X.X.",
	"X.....XXXX",
	"X.XXXXX..X",
	"X........X",
	"X.XXXXXX.X",
	"X........X",
	"X.XXXXX..X",
	"X........X",
	"X........X",
	"XXXXXXXXXX",
]

## 甩窗口：拍、新重力
const FLINGS := [
	[9.0, 1, 0],
	[12.0, 0, -1],
	[14.5, -1, 0],
	[16.5, 0, 1],
]

## 图标：进入拍、种类、层数、重力 (gx, gy)、进场端（0 = 左/上，1 = 右/下）
const ICON_PLAN := [
	[1.0, "folder", 1, 0, 1, 1],
	[2.0, "doc", 1, 0, 1, 1],
	[3.0, "recycle", 2, 0, 1, 1],
	[4.5, "folder", 1, 0, 1, 1],
	[5.5, "doc", 2, 0, 1, 1],
	[10.0, "doc", 1, 1, 0, 0],
	[11.0, "folder", 1, 1, 0, 0],
	[13.0, "recycle", 1, 0, -1, 0],
	[14.0, "doc", 1, 0, -1, 0],
	[15.5, "folder", 1, -1, 0, 1],
	[17.0, "doc", 1, 0, 1, 1],
]

var _base_rect := Rect2()


func setup() -> void:
	duration = 18.0
	box_size = Vector2(200, 120)
	soul_mode = "blue"
	stop_beat = 7.0


func _ready() -> void:
	# battle 在 add_child 之前就把 box 设好了
	_base_rect = box


# ── 窗口矩形 ──────────────────────────────────────────────────

## B 段被拖的宽度：200 → 110 → 200
func _width_at(now: float) -> float:
	if now >= SHRINK_FROM and now < SHRINK_TO:
		return lerpf(_base_rect.size.x, SHRINK_W, (now - SHRINK_FROM) / (SHRINK_TO - SHRINK_FROM))
	if now >= SHRINK_TO and now < 8.0:
		return lerpf(SHRINK_W, _base_rect.size.x, (now - SHRINK_TO) / (8.0 - SHRINK_TO))
	return _base_rect.size.x


## C 段每次甩的位移：到点先出去 12px，再在 0.25 拍里回到原位
func _fling_offset(now: float) -> Vector2:
	for f in FLINGS:
		var ft: float = f[0]
		var d := Vector2(f[1], f[2])
		if mirror:
			d.x = -d.x
		if now >= ft and now < ft + FLING_LEN:
			var u := (now - ft) / FLING_LEN
			return d * FLING_PX * (1.0 - u)
	return Vector2.ZERO


## 每帧把窗口矩形推给框和心；心跟着窗口平移
func _apply_box(now: float) -> void:
	var r := Rect2(_base_rect.position, Vector2(_width_at(now), _base_rect.size.y))
	r.position += _fling_offset(now)
	if r == box:
		return
	var dp := r.position - box.position
	box = r
	if battle and is_instance_valid(battle.box):
		battle.box.rect = r
	if battle and is_instance_valid(battle.soul):
		battle.soul.area = r
		battle.soul.pos += dp
		battle.soul.pos = battle.soul.clamp_in(battle.soul.pos)


# ── 图标 ──────────────────────────────────────────────────────

func _rows(kind: String) -> Array:
	match kind:
		"folder":
			return FOLDER
		"recycle":
			return RECYCLE
	return DOC


func _icon_w(ic: Array) -> int:
	return 10 if ic[1] == "doc" else 12


func _icon_h(ic: Array) -> int:
	match ic[1]:
		"folder":
			return 10
		"recycle":
			return 12
	return 12


## 当前重力；mirror 时左右墙互换
func _gravity(ic: Array) -> Vector2i:
	var g := Vector2i(ic[3], ic[4])
	if mirror:
		g.x = -g.x
	return g


## mirror 时水平墙的两端互换
func _entry(ic: Array) -> int:
	var side: int = ic[5]
	# 只有水平墙（重力朝上/下）的左右端要镜像；竖直墙的上下端不变
	if mirror and ic[4] != 0:
		return 1 - side
	return side


func _wall_len(g: Vector2i) -> float:
	return box.size.x if g.y != 0 else box.size.y


func _wall_base(g: Vector2i, s: float) -> Vector2:
	if g.y > 0:
		return Vector2(box.position.x + s, box.end.y)
	if g.y < 0:
		return Vector2(box.position.x + s, box.position.y)
	if g.x > 0:
		return Vector2(box.end.x, box.position.y + s)
	return Vector2(box.position.x, box.position.y + s)


func _rot(g: Vector2i) -> float:
	if g.y > 0:
		return 0.0
	if g.x > 0:
		return -PI / 2.0
	if g.y < 0:
		return PI
	return PI / 2.0


## 图标沿墙的坐标（0 = 左/上端，L = 右/下端）
func _icon_s(ic: Array, now: float) -> float:
	var g := _gravity(ic)
	var l := _wall_len(g)
	var w := float(_icon_w(ic))
	var side := _entry(ic)
	var s0 := -w / 2.0 if side == 0 else l + w / 2.0
	var dir := 1.0 if side == 0 else -1.0
	return s0 + dir * ICON_SPEED * (now - float(ic[0]))


func _icon_alive(ic: Array, now: float) -> bool:
	if now < float(ic[0]):
		return false
	# B 段（拖边）简报要求框里没有图标：A 段还没滑出去的最后两个在 6.0 提前消失
	if now >= 6.0 and float(ic[0]) < 8.0:
		return false
	var g := _gravity(ic)
	var l := _wall_len(g)
	var w := float(_icon_w(ic))
	var s := _icon_s(ic, now)
	if _entry(ic) == 0:
		return s - w / 2.0 < l
	return s + w / 2.0 > 0.0


func _icon_rect(ic: Array, now: float) -> Rect2:
	var g := _gravity(ic)
	var s := _icon_s(ic, now)
	var w := float(_icon_w(ic))
	var d := float(_icon_h(ic) * int(ic[2]))
	var r: Rect2
	if g.y > 0:
		r = Rect2(box.position.x + s - w / 2.0, box.end.y - d, w, d)
	elif g.y < 0:
		r = Rect2(box.position.x + s - w / 2.0, box.position.y, w, d)
	elif g.x > 0:
		r = Rect2(box.end.x - d, box.position.y + s - w / 2.0, d, w)
	else:
		r = Rect2(box.position.x, box.position.y + s - w / 2.0, d, w)
	return r.grow(-1.0)


func _draw_icon(ic: Array, now: float) -> void:
	var g := _gravity(ic)
	var s := _icon_s(ic, now)
	var base := _wall_base(g, s).round()
	var rows := _rows(ic[1])
	var w := float(_icon_w(ic))
	var h := float(_icon_h(ic))
	draw_set_transform(base, _rot(g), Vector2.ONE)
	for layer in int(ic[2]):
		Px.bitmap(self, rows, Vector2(-w / 2.0, -h * (layer + 1)), C.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ── 光标 ──────────────────────────────────────────────────────

func _idle_tip() -> Vector2:
	if mirror:
		return Vector2(box.position.x - 10.0, box.position.y - 10.0)
	return Vector2(box.end.x + 10.0, box.position.y - 10.0)


func _right_mid() -> Vector2:
	return Vector2(box.end.x, box.get_center().y)


func _title_mid() -> Vector2:
	return Vector2(box.get_center().x, box.position.y - 9.0)


func _tip(now: float) -> Vector2:
	if now < 6.0:
		return _idle_tip()
	if now < 6.5:
		return _idle_tip().lerp(_right_mid(), (now - 6.0) / 0.5)
	if now < 8.0:
		# 拖着右边：整个 B 段都贴在右边中点
		return _right_mid()
	if now < 8.5:
		return _right_mid().lerp(_title_mid(), (now - 8.0) / 0.5)
	return _title_mid()


# ── 每帧 ──────────────────────────────────────────────────────

func tick(_dt: float) -> void:
	_apply_box(t)
	for f in FLINGS:
		if crossed(float(f[0])):
			if battle and is_instance_valid(battle.soul):
				var d := Vector2i(f[1], f[2])
				if mirror:
					d.x = -d.x
				battle.soul.slam(d)
	for ic in ICON_PLAN:
		if _icon_alive(ic, t):
			hz_rect(_icon_rect(ic, t))
	if crossed(SHRINK_FROM):
		sfx("click")
	if crossed(8.5):
		sfx("click")


func _draw() -> void:
	var blink := int(t * 8.0) % 2 == 0
	# 预警：进场那一端贴地的「!」
	if blink:
		for ic in ICON_PLAN:
			var b: float = ic[0]
			if t >= b - WARN_LEN and t < b:
				var g := _gravity(ic)
				var l := _wall_len(g)
				var side := _entry(ic)
				var s := 3.0 if side == 0 else l - 3.0
				var base := _wall_base(g, s).round()
				draw_set_transform(base, _rot(g), Vector2.ONE)
				draw_rect(Rect2(-1, -6, 2, 6), C.WHITE)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 图标
	for ic in ICON_PLAN:
		if _icon_alive(ic, t):
			_draw_icon(ic, t)


func draw_outside(ci: CanvasItem) -> void:
	# 标题栏（跟着窗口一起动）
	var tr := Rect2(box.position.x - 2.0, box.position.y - 16.0, box.size.x + 4.0, 14.0)
	ci.draw_rect(Rect2(tr.position.round(), tr.size.round()), C.SYS_DIM)
	Px.text(ci, tr.position + Vector2(4, 1), "determination.exe", C.WHITE)
	var by := tr.position.y + 3.0
	for i in 3:
		var bx := tr.end.x - 3.0 - 8.0 - i * 10.0
		var r := Rect2(Vector2(bx, by).round(), Vector2(8, 8))
		match i:
			0:  # 关闭（最右）
				ci.draw_line(r.position + Vector2(1, 1), r.position + Vector2(7, 7), C.WHITE, 1.0)
				ci.draw_line(r.position + Vector2(7, 1), r.position + Vector2(1, 7), C.WHITE, 1.0)
			1:  # 最大化
				Px.frame(ci, Rect2(r.position + Vector2(1, 1), Vector2(6, 6)), 1.0, C.WHITE)
			2:  # 最小化
				ci.draw_rect(Rect2(r.position.x + 1, r.position.y + 7, 6, 1), C.WHITE)
	# 甩之前的红三角预警
	var blink := int(t * 8.0) % 2 == 0
	if blink:
		for f in FLINGS:
			var ft: float = f[0]
			if t >= ft - WARN_LEN and t < ft:
				var g := Vector2i(f[1], f[2])
				if mirror:
					g.x = -g.x
				var c := box.get_center()
				var p: Vector2
				if g.y > 0:
					p = Vector2(c.x, box.end.y + 6.0)
				elif g.y < 0:
					p = Vector2(c.x, box.position.y - 6.0)
				elif g.x > 0:
					p = Vector2(box.end.x + 6.0, c.y)
				else:
					p = Vector2(box.position.x - 6.0, c.y)
				var d := -Vector2(g)
				var n := Vector2(-d.y, d.x)
				var tip := p + d * 5.0
				var back := p - d * 4.0
				ci.draw_colored_polygon(PackedVector2Array([tip, back + n * 5.0, back - n * 5.0]), C.RED)
	# 第一次甩之后 2 拍内提示
	if t >= 9.0 and t < 11.0:
		var s := "重力变了：往反方向按跳"
		var w := Px.text_w(s)
		Px.text(ci, Vector2(box.get_center().x - w / 2.0, box.position.y - 30.0), s, C.GRAY)
	# 红光标
	Px.cursor(ci, _tip(t), C.RED)
