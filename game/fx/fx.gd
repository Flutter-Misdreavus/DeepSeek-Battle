class_name Fx
## 共享的特效绘制（从 MV 的 version.ts / love.ts 移植）：
##   Fx.version(ci, "V∞", pos, col, 24)        版本号，「∞」手画（字体里没有）
##   Fx.love_acronym(ci, center, 24, k, ...)    「Level Of ViolencE」⇄「LOVE」变形，k = 0 全称，k = 1 只剩 LOVE

const INF := [
	".XXX.....XXX.",
	"X...X...X...X",
	"X....X.X....X",
	"X.....X.....X",
	"X....X.X....X",
	"X...X...X...X",
	".XXX.....XXX.",
]
const LOVE_PHRASE := "Level Of ViolencE"
const LOVE_KEYS := [0, 6, 9, 16]


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


## 全称和 LOVE 之间的变形，center 是中心点。
## k 从 0 到 1：其余字母先淡出并往下掉（k 0–0.45），L、O、V、E 再滑到一起（k 0.3–1）。k 从 1 到 0 就是展开。
static func love_acronym(ci: CanvasItem, center: Vector2, size: int, k: float, key_col := C.RED, rest_col := C.WHITE) -> void:
	var kk := clampf(k, 0.0, 1.0)
	var full_w := Px.text_w(LOVE_PHRASE, size)
	var love_w := Px.text_w("LOVE", size)
	var y := roundf(center.y - size / 2.0)
	var fade := 1.0 - minf(1.0, kk / 0.45)
	var m := clampf((kk - 0.3) / 0.7, 0.0, 1.0)
	var slide := -(cos(PI * m) - 1.0) / 2.0
	for i in LOVE_PHRASE.length():
		var ch := LOVE_PHRASE[i]
		if ch == " ":
			continue
		var x0 := center.x - full_w / 2.0 + Px.text_w(LOVE_PHRASE.substr(0, i), size)
		var j: int = LOVE_KEYS.find(i)
		if j >= 0:
			var x1 := center.x - love_w / 2.0 + Px.text_w("LOVE".substr(0, j), size)
			Px.text(ci, Vector2(roundf(lerpf(x0, x1, slide)), y), ch, key_col, size)
		elif fade > 0.0:
			var drop := (1.0 - fade) * size * 0.8
			Px.text(ci, Vector2(roundf(x0), roundf(y + drop)), ch, Color(rest_col, fade), size)
