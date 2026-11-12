class_name Px
## 像素风绘制工具。坐标都是逻辑像素；画像素块时先取整，保证落在整像素上。

static var _font: FontFile

const HEART_ROWS := [
	"..XXX...XXX..",
	".XXXXX.XXXXX.",
	"XXXXXXXXXXXXX",
	"XXXXXXXXXXXXX",
	"XXXXXXXXXXXXX",
	"XXXXXXXXXXXXX",
	".XXXXXXXXXXX.",
	"..XXXXXXXXX..",
	"...XXXXXXX...",
	"....XXXXX....",
	".....XXX.....",
	"......X......",
]

## 按钮图标 11×11（自己画的，不是原作素材）：战斗=剑，行动=对话气泡，物品=背包，仁慈=握手的叉
const ICONS := [
	[
		".........XX",
		"........XXX",
		".......XXX.",
		"......XXX..",
		".X...XXX...",
		".XX.XXX....",
		"..XXXX.....",
		"..XXX......",
		".XX.XX.....",
		"XX...X.....",
		"X..........",
	],
	[
		".XXXXXXXXX.",
		"XX.......XX",
		"X.........X",
		"X..X.X.X..X",
		"X.........X",
		"XX.......XX",
		".XXXXXXXXX.",
		"...XX......",
		"..XX.......",
		".XX........",
		"...........",
	],
	[
		"....XXX....",
		"...X...X...",
		"...X...X...",
		".XXXXXXXXX.",
		"XX.......XX",
		"X..XXXXX..X",
		"X..X...X..X",
		"X..XXXXX..X",
		"X.........X",
		"XX.......XX",
		".XXXXXXXXX.",
	],
	[
		"XX.......XX",
		"XXX.....XXX",
		".XXX...XXX.",
		"..XXX.XXX..",
		"...XXXXX...",
		"....XXX....",
		"...XXXXX...",
		"..XXX.XXX..",
		".XXX...XXX.",
		"XXX.....XXX",
		"XX.......XX",
	],
]


static func font() -> FontFile:
	if _font == null:
		_font = load("res://fonts/fusion-pixel-12px.woff2")
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font


## 以左上角为基准画一行字。size 只用 12 的整数倍（12 / 24 / 36），否则笔画不齐。
static func text(ci: CanvasItem, pos: Vector2, s: String, col := Color.WHITE, size := 12) -> void:
	var f := font()
	ci.draw_string(f, pos.round() + Vector2(0, f.get_ascent(size)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func text_w(s: String, size := 12) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 按像素宽度折行（中文逐字折，英文单词不拆）
static func wrap(s: String, width: float, size := 12) -> PackedStringArray:
	var out := PackedStringArray()
	for para in s.split("\n"):
		var line := ""
		var word := ""
		for ch in para:
			var is_ascii := ch.unicode_at(0) < 128 and ch != " "
			if is_ascii:
				word += ch
				continue
			line = _push_word(out, line, word, width, size)
			word = ""
			if text_w(line + ch, size) > width:
				out.append(line)
				line = ch.strip_edges() if ch == " " else ch
			else:
				line += ch
		line = _push_word(out, line, word, width, size)
		out.append(line)
	return out


static func _push_word(out: PackedStringArray, line: String, word: String, width: float, size: int) -> String:
	if word == "":
		return line
	if text_w(line + word, size) > width and line != "":
		out.append(line)
		return word
	return line + word


## 空心框：w 是线宽
static func frame(ci: CanvasItem, r: Rect2, w: float, col: Color) -> void:
	r = Rect2(r.position.round(), r.size.round())
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), col)
	ci.draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), col)
	ci.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), col)
	ci.draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), col)


## 白框黑底的窗口（r 是内框）
static func panel(ci: CanvasItem, inner: Rect2, border_col := Color.WHITE, fill := Color.BLACK, w := 2.0) -> void:
	ci.draw_rect(inner, fill)
	frame(ci, inner.grow(w), w, border_col)


## 13×12 红心，c 是中心
static func heart(ci: CanvasItem, c: Vector2, col := C.HEART) -> void:
	var o := (c - C.SOUL_HALF).round()
	for j in HEART_ROWS.size():
		var row: String = HEART_ROWS[j]
		var i := 0
		while i < row.length():
			if row[i] == "X":
				var k := i
				while k < row.length() and row[k] == "X":
					k += 1
				ci.draw_rect(Rect2(o.x + i, o.y + j, k - i, 1), col)
				i = k
			else:
				i += 1


## 画一个字符串数组表示的像素图（"X" 是实心），左上角在 pos，每格 s 像素
static func bitmap(ci: CanvasItem, rows: Array, pos: Vector2, col: Color, s := 1.0) -> void:
	var o := pos.round()
	for j in rows.size():
		var row: String = rows[j]
		for i in row.length():
			if row[i] == "X":
				ci.draw_rect(Rect2(o.x + i * s, o.y + j * s, s, s), col)


## 「蚂蚁线」虚线框（选框）。phase 让虚线沿边框流动
static func dashed(ci: CanvasItem, r: Rect2, col: Color, phase := 0.0, dash := 4) -> void:
	r = Rect2(r.position.round(), r.size.round())
	var per := 2.0 * (r.size.x + r.size.y)
	var p := fposmod(phase, dash * 2.0)
	var d := -p
	while d < per:
		var a := maxf(d, 0.0)
		var b := minf(d + dash, per)
		if b > a:
			_perim_seg(ci, r, a, b, col)
		d += dash * 2.0


static func _perim_seg(ci: CanvasItem, r: Rect2, a: float, b: float, col: Color) -> void:
	var w := r.size.x
	var h := r.size.y
	var edges := [[0.0, w], [w, w + h], [w + h, 2 * w + h], [2 * w + h, 2 * w + 2 * h]]
	for e in 4:
		var s0: float = maxf(a, edges[e][0])
		var s1: float = minf(b, edges[e][1])
		if s1 <= s0:
			continue
		var u0: float = s0 - edges[e][0]
		var u1: float = s1 - edges[e][0]
		match e:
			0: ci.draw_rect(Rect2(r.position.x + u0, r.position.y, u1 - u0, 1), col)
			1: ci.draw_rect(Rect2(r.end.x - 1, r.position.y + u0, 1, u1 - u0), col)
			2: ci.draw_rect(Rect2(r.end.x - u1, r.end.y - 1, u1 - u0, 1), col)
			3: ci.draw_rect(Rect2(r.position.x, r.end.y - u1, 1, u1 - u0), col)


## 全屏矩形：从可见区域左上角铺满（battle 根节点有居中偏移，传入 offset = 根节点 position）
static func screen_rect(ci: CanvasItem, offset: Vector2, col: Color) -> void:
	ci.draw_rect(Rect2(-offset, ci.get_viewport_rect().size), col)
