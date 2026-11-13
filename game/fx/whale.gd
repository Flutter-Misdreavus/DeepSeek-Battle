class_name Whale
## 鲸鱼弹幕：她的招牌。图集由 pipeline/whale_raster.gd 从 assets/whale.svg 生成：
## 每种宽度一张 res://art/whale/w<宽>.png，16 个朝向横排，每帧 cell(w)×cell(w)，身体圆心在帧中间，肚皮始终朝下。
## 画的时候按前进方向挑最近的一帧，不在运行时旋转（运行时转像素图会把边缘啃花）。
## 前进方向 = 圆圆的身体那头，尾巴在后面（原图尾巴在右，所以原图是往左游）。
## pos 是身体圆心，判定圆也以它为圆心，半径 radius(w)。

const SIZES := [12, 16, 20, 24, 32, 48, 64, 96, 160]
const DIRS := 16

static var _tex := {}


static func tex(w: int) -> Texture2D:
	if not _tex.has(w):
		_tex[w] = load("res://art/whale/w%d.png" % w)
	return _tex[w]


static func cell(w: int) -> int:
	return ceili(w * 1.5) + 2


## 判定圆半径：比身体略小，宽容一点
static func radius(w: int) -> float:
	return w * 0.28


## 画一条往 dir 方向游的鲸鱼。w 必须是 SIZES 里的值；scale_k 整体缩放（出场、分裂时用，会糊一点，只用在短暂的过渡）
static func draw(ci: CanvasItem, pos: Vector2, dir: Vector2, w: int, col := Color.WHITE, scale_k := 1.0) -> void:
	var s := cell(w)
	var i := posmod(roundi((dir.angle() + PI) / (TAU / DIRS)), DIRS)
	var size := Vector2(s, s) * scale_k
	ci.draw_texture_rect_region(tex(w), Rect2((pos - size / 2.0).round(), size), Rect2(i * s, 0, s, s), col)
