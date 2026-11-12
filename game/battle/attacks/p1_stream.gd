extends Attack
## P1-1「流式输出」（标杆攻击，后面所有攻击照这个写法）
##
## AI 的客套话一字一字打出来，成行从框底往上滚（聊天窗口自动滚屏）。每行有一个 2 格宽的空当，就是能钻过去的缝。
## - 一行 16 格，每格 12px（一个汉字）。第 k 行在第 2k 拍从框底出现，以每拍 14px 往上滚。
## - 字是一个个打出来的：每拍打 4 个字，打字的位置有一根白色输入光标。没打出来的格子不伤人。
## - 预警：每行出现前 1 拍，框底左侧（行首）有输入光标闪两下。
## - 伤害判定：每个已打出的字是 10×10 的方块（比字格各缩 1px）。
## - mirror = true 时整行从右往左打。

const SLOT := 12.0
const SLOTS := 16
const ROW_EVERY := 2.0            # 每隔几拍出一行
const ROWS := 7
const SCROLL := 14.0              # 每拍上移的像素
const TYPE_RATE := 4.0            # 每拍打几个字
const GAP_AT := [2, 11, 6, 13, 0, 8, 4]   # 每行空当的起始格（2 格宽）
const PHRASES := ["作为一个人工智能语言模型", "您说得对", "希望对您有帮助", "这个问题很有深度"]

var _rows: Array = []             # 每行：{chars: Array[String]（空当是 ""），spawn: 拍}
var _last_blip := -1


func setup() -> void:
	duration = 16.0
	box_size = Vector2(SLOTS * SLOT + 4, 120)
	stop_beat = 8.0
	for k in ROWS:
		var phrase: String = PHRASES[k % PHRASES.size()] + "。"
		var chars: Array[String] = []
		for i in SLOTS:
			chars.append(phrase[i % phrase.length()])
		var g: int = GAP_AT[k]
		chars[g] = ""
		chars[mini(g + 1, SLOTS - 1)] = ""
		_rows.append({"chars": chars, "spawn": k * ROW_EVERY})


## 第 i 格的左边 x（考虑镜像）
func _slot_x(i: int) -> float:
	if mirror:
		return box.end.x - 2.0 - (i + 1) * SLOT
	return box.position.x + 2.0 + i * SLOT


## 第 k 行在拍 t 的顶边 y
func _row_y(row: Dictionary) -> float:
	return box.end.y - (t - row["spawn"]) * SCROLL


## 第 k 行在拍 t 已经打出了几个字
func _typed(row: Dictionary) -> int:
	return clampi(int((t - row["spawn"]) * TYPE_RATE), 0, SLOTS)


func tick(_dt: float) -> void:
	for row in _rows:
		if t < row["spawn"]:
			continue
		var y := _row_y(row)
		if y < box.position.y - SLOT:
			continue
		var n := _typed(row)
		for i in n:
			if row["chars"][i] != "":
				hz_rect(Rect2(_slot_x(i) + 1, y + 1, SLOT - 2, SLOT - 2))
	# 打字声：每拍两下
	var half := floori(t * 2.0)
	if half != _last_blip and t < _rows[-1]["spawn"] + SLOTS / TYPE_RATE:
		_last_blip = half
		sfx("text_sys")


func _draw() -> void:
	for row in _rows:
		var since: float = t - row["spawn"]
		# 预警：出现前 1 拍，行首输入光标闪两下
		if since < 0.0:
			if since > -1.0 and int(since * 4.0) % 2 == 0:
				draw_rect(Rect2(_slot_x(0) + (SLOT - 2.0 if mirror else 0.0), box.end.y - SLOT - 1, 2, SLOT), C.WHITE)
			continue
		var y := roundf(_row_y(row))
		if y < box.position.y - SLOT:
			continue
		var n := _typed(row)
		for i in n:
			var ch: String = row["chars"][i]
			if ch != "":
				Px.text(self, Vector2(_slot_x(i), y), ch, C.WHITE)
		# 打字位置的输入光标
		if n < SLOTS and int(t * 4.0) % 2 == 0:
			var cx := _slot_x(n) + (SLOT - 2.0 if mirror else 0.0)
			draw_rect(Rect2(cx, y, 2, SLOT), C.WHITE)
