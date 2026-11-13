extends SceneTree
## 把 assets/whale.svg 栅格化成像素鲸鱼图集，输出 game/art/whale/w<宽>.png。
## - 原图的身体是空心的环，小尺寸下认不出，所以把大的内洞填实，只留眼睛那个小洞。
## - 每种尺寸 16 个朝向（第 i 帧朝 i × 22.5°，0 = 朝右，角度顺时针，和 Godot 的 Vector2.angle() 一致），横排成一张图集。
##   朝左半边的帧先上下翻转再转，肚皮始终朝下。每帧是 S×S 的正方形，鲸鱼**身体圆心**在正中间。
##   注意：原图尾巴在右，看起来是往左游，所以游戏里往 d 方向游的鲸鱼用的是 d + 180° 那一帧（见 fx/whale.gd）。
##   游戏里按速度方向挑最近的一帧直接画，不在运行时旋转（运行时转像素图会把边缘啃花）。
## - 白色剪影，透明度二值化。
## 运行（在仓库根目录）：godot --headless --path game --script ../pipeline/whale_raster.gd

const WIDTHS := [12, 16, 20, 24, 32, 48, 64, 96, 160]
const DIRS := 16
const MASTER_W := 960
const BODY := Vector2(0.37, 0.39)      # 身体圆心在原图里的位置（按宽度的比例，从左上角量）；和 fx/whale.gd 一致

var _m: Image
var _mw := 0
var _mh := 0


func _init() -> void:
	var src := ProjectSettings.globalize_path("res://").path_join("../assets/whale.svg")
	var svg := FileAccess.get_file_as_string(src)
	var out := ProjectSettings.globalize_path("res://art/whale")
	_m = Image.new()
	_m.load_svg_from_string(svg, MASTER_W / 48.0)
	_m.convert(Image.FORMAT_RGBA8)
	_m = _m.get_region(_m.get_used_rect())
	_m.resize(MASTER_W, roundi(_m.get_height() * float(MASTER_W) / _m.get_width()), Image.INTERPOLATE_LANCZOS)
	_mw = _m.get_width()
	_mh = _m.get_height()
	_binarize(_m)
	_fill_holes(_m)
	for w in WIDTHS:
		var s := cell(w)
		var ss := 3 if w <= 48 else 2          # 超采样
		var atlas := Image.create(s * DIRS, s, false, Image.FORMAT_RGBA8)
		for i in DIRS:
			var ang := TAU * i / DIRS
			var flip := cos(ang) < -0.01
			var k: float = float(_mw) / w        # 原图像素 / 成品像素
			for y in s:
				for x in s:
					var hit := 0
					for sy in ss:
						for sx in ss:
							# 成品里相对身体圆心的位置 → 反转 → 原图坐标
							var p := Vector2(x + (sx + 0.5) / ss - s / 2.0, y + (sy + 0.5) / ss - s / 2.0)
							p = p.rotated(-ang)
							if flip:
								p.y = -p.y
							var q: Vector2 = (p * k + BODY * _mw).floor()
							if q.x >= 0 and q.y >= 0 and q.x < _mw and q.y < _mh and _m.get_pixel(int(q.x), int(q.y)).a > 0.0:
								hit += 1
					if hit * 2 >= ss * ss:
						atlas.set_pixel(i * s + x, y, Color.WHITE)
		atlas.save_png(out.path_join("w%d.png" % w))
		print("w%d.png  cell %d  atlas %dx%d" % [w, s, atlas.get_width(), atlas.get_height()])
	quit()


## 每帧正方形的边长（身体圆心到最远一点约 0.74 × 宽）
static func cell(w: int) -> int:
	return ceili(w * 1.5) + 2


func _binarize(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if img.get_pixel(x, y).a >= 0.5 else 0.0))


## 透明的连通块里，碰不到边的就是洞；面积超过总面积 3% 的洞填实（身体），小的留着（眼睛）
func _fill_holes(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	for y in h:
		for x in w:
			if seen[y * w + x] or img.get_pixel(x, y).a > 0.0:
				continue
			var comp: Array[int] = []
			var edge := false
			var stack: Array[int] = [y * w + x]
			seen[y * w + x] = 1
			while not stack.is_empty():
				var q: int = stack.pop_back()
				comp.append(q)
				var qx := q % w
				var qy := q / w
				if qx == 0 or qy == 0 or qx == w - 1 or qy == h - 1:
					edge = true
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = qx + d.x
					var ny: int = qy + d.y
					if nx >= 0 and ny >= 0 and nx < w and ny < h and not seen[ny * w + nx] and img.get_pixel(nx, ny).a == 0.0:
						seen[ny * w + nx] = 1
						stack.append(ny * w + nx)
			if not edge and comp.size() > w * h * 0.03:
				for q in comp:
					img.set_pixel(q % w, q / w, Color.WHITE)
