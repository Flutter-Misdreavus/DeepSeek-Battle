class_name Fx
## 共享的特效绘制（从 MV 的 version.ts 移植）：
##   Fx.version(ci, "V∞", pos, col, 24)        版本号，「∞」手画（字体里没有）

const INF := [
	".XXX.....XXX.",
	"X...X...X...X",
	"X....X.X....X",
	"X.....X.....X",
	"X....X.X....X",
	"X...X...X...X",
	".XXX.....XXX.",
]


static func version_w(text: String, size := 12) -> float:
	var s := size / 12.0
	var w := 0.0
	for p in _parts(text):
		w += (14.0 * s) if p == "∞" else Px.text_w(p, size)
	return w


## 以左上角为基准画版本号；size 用 12 / 24 / 36
static func version(ci: CanvasItem, text: String, pos: Vector2, col: Color, size := 12) -> void:
	var s := size / 12.0
	var x := roundf(pos.x)
	for p in _parts(text):
		if p == "∞":
			Px.bitmap(ci, INF, Vector2(x, roundf(pos.y + 4.0 * s)), col, s)
			x += 14.0 * s
		else:
			Px.text(ci, Vector2(x, pos.y), p, col, size)
			x += Px.text_w(p, size)


static func _parts(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for ch in text:
		if ch == "∞":
			if cur != "":
				out.append(cur)
			out.append("∞")
			cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out

