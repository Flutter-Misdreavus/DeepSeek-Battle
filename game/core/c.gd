class_name C
## 全局常量：配色、布局（640×360 逻辑像素）、节拍。所有攻击和界面都从这里取数，不要在别处写死同样的值。

const BASE := Vector2(640, 360)
const SPB := 60.0 / 98.0               # 一拍的秒数（98 BPM）

# ── 配色（沿用 MV 的 palette.ts）──────────────────────────────
const BLACK := Color("#000000")
const WHITE := Color("#ffffff")
const SYS := Color("#5f86d0")          # 系统 / 用户的蓝
const SYS_DIM := Color("#2c4a80")
const COLD := Color("#cfe0ff")         # 冷白屏幕光
const RED := Color("#ff2a2a")          # 她的红
const RED_DIM := Color("#7a1414")
const HEART := Color("#ff1010")        # 红心本体
const BTN := Color("#ff7f27")          # 按钮橙
const BTN_HI := Color("#ffff00")       # 选中黄 / 可饶恕
const GRAY := Color("#8a8a8a")         # 思考块灰字、不可用
const GRAY_DIM := Color("#4a4a4a")

# ── 布局 ──────────────────────────────────────────────────────
const TITLE_H := 14                    # 顶部标题栏高度
const TEXT_BOX := Rect2(34, 196, 572, 84)   # 文字框的内框；边框 2px 画在内框外
const BORDER := 2
const BOX_BOTTOM := 280.0              # 弹幕框内框的底边固定在这里，变大时往上长
const BOX_CX := 320.0
const STAGE_FOOT := Vector2(320, 193)  # 她的全身立绘画布底边中点
const STAGE_H := 176.0                 # 全身立绘画布的显示高度
const HP_Y := 287                      # HP 行文字的顶边
const BTN_Y := 310
const BTN_SIZE := Vector2(110, 32)
const BTN_GAP := 36
const BUBBLE_POS := Vector2(382, 30)   # 气泡左上角
const BUBBLE_W := 120
const PANEL_L := Rect2(10, 22, 150, 128)
const PANEL_R := Rect2(480, 22, 150, 128)
const LINE_H := 16                     # 文字框行距

# ── 红心 ──────────────────────────────────────────────────────
const SOUL_SPEED := 120.0              # 逻辑像素 / 秒
const TOUCH_CAP := 1.5                 # 触屏每帧位移上限 = 键盘速度 × 1.5
const IFRAMES := 1.0                   # 受击后无敌秒数
const HITBOX := Vector2(7, 6)          # 判定框（比 13×12 的心小）
const SOUL_HALF := Vector2(6.5, 6)

# ── 数值 ──────────────────────────────────────────────────────
const ENEMY_HP := 1200
const PLAYER_HP := 20                  # LV 1 的最大 HP；每升一级 +4


static func btn_rect(i: int) -> Rect2:
	var x0 := (BASE.x - 4 * BTN_SIZE.x - 3 * BTN_GAP) / 2
	return Rect2(x0 + i * (BTN_SIZE.x + BTN_GAP), BTN_Y, BTN_SIZE.x, BTN_SIZE.y)


## 弹幕框内框：宽 w 高 h，水平居中，底边固定在 BOX_BOTTOM
static func dodge_box(w: float, h: float) -> Rect2:
	return Rect2(BOX_CX - w / 2, BOX_BOTTOM - h, w, h)


static func beats(sec: float) -> float:
	return sec / SPB
