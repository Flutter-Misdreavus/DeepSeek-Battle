extends Attack
## P2-3「知识蒸馏」
##
## 一条大鲸鱼（「教师模型」）分裂成两条，再分裂……越分越小、越分越多，沿弧线散开。
## 梗：大模型蒸馏出小模型。
## - 两波分裂树：A 波教师从框上方游进来，2.5 拍第一次分裂；B 波从框左边（mirror 时右边）进来，10.5 拍。
## - 第 1 / 2 / 3 代宽 32 / 24 / 16，分别在 S0+1 / S0+2 分裂，孩子从父亲当时的位置和前进方向 ±55° / ±28° / ±14° 出发（整棵树长成扇形）。
## - 孩子的圆弧位置是解析的纯函数；教师停住时也是伤害，孩子分裂前 0.75 拍闪白/蓝并涨到 1.15 倍。
## - 第 3 代游出框外 20px 后不再画也不判定。
## - 字幕逐段显示蒸馏进度；B 波重新从 671B 开始。

const WAVE_START := [0.0, 8.0]
const FIRST_SPLIT := [2.5, 10.5]
const ENTER_LEN := 1.0
const SPLIT_GAP := 1.0
const WIDTHS := [48, 32, 24, 16]
const SPEEDS := [0.0, 30.0, 34.0, 38.0]
const TURNS := [0.0, 0.0, 0.0, 0.2]
const DELTAS := [0.0, deg_to_rad(55.0), deg_to_rad(28.0), deg_to_rad(14.0)]   # 分叉角一代比一代窄：整棵树往下长成扇形，铺满框
const WARN_LEN := 0.75
const WARN_SCALE := 1.15
const GROW_LEN := 0.2
const GEN3_PAD := 20.0
const NO_SPLIT := 1e9

var _tree: Array = []
var _built := false


func setup() -> void:
	duration = 17.0
	box_size = Vector2(220, 140)
	stop_beat = 8.0
	var r := C.dodge_box(box_size.x, box_size.y)
	stop_spot = Vector2(r.end.x - 24.0, r.end.y - 14.0)   # 放右下角，别压住左上的蒸馏字幕


func begin() -> void:
	pose("summon")


# ── 分裂树 ────────────────────────────────────────────────────

func _build() -> void:
	if _built:
		return
	_built = true
	var c := box.get_center()
	for wave in 2:
		var root: Dictionary
		if wave == 0:
			root = {
				"gen": 0, "width": WIDTHS[0], "wave": wave,
				"p0": Vector2(c.x, box.position.y - 30.0),
				"p1": Vector2(c.x, box.position.y + 30.0),
				"th0": PI / 2.0, "w": 0.0, "v": 0.0,
				"birth": WAVE_START[0], "split": FIRST_SPLIT[0],
			}
		else:
			var base := PI if mirror else 0.0
			var p0 := Vector2(box.end.x + 30.0, c.y - 10.0) if mirror else Vector2(box.position.x - 30.0, c.y - 10.0)
			var p1 := Vector2(box.end.x - 34.0, c.y - 10.0) if mirror else Vector2(box.position.x + 34.0, c.y - 10.0)
			root = {
				"gen": 0, "width": WIDTHS[0], "wave": wave,
				"p0": p0, "p1": p1,
				"th0": base, "w": 0.0, "v": 0.0,
				"birth": WAVE_START[1], "split": FIRST_SPLIT[1],
			}
		_tree.append(root)
		_children(root, 1)


## 在父亲的分裂时刻，按父亲的位置和前进方向造两个孩子；再递归往下
func _children(parent: Dictionary, gen: int) -> void:
	if gen > 3:
		return
	var at: float = parent["split"]
	var p := _pos(parent, at)
	var th := _theta(parent, at)
	for side in [-1, 1]:
		var child := {
			"gen": gen, "width": WIDTHS[gen], "wave": parent["wave"],
			"p0": p,
			"th0": th + side * DELTAS[gen],
			"w": side * TURNS[gen],
			"v": SPEEDS[gen],
			"birth": at,
			"split": ((at + SPLIT_GAP) if gen < 3 else NO_SPLIT),
			"entered": false, "gone": false,
		}
		_tree.append(child)
		if gen < 3:
			_children(child, gen + 1)


# ── 位置（t 的纯函数）────────────────────────────────────────

func _pos(n: Dictionary, now: float) -> Vector2:
	if int(n["gen"]) == 0:
		var k := clampf((now - float(n["birth"])) / ENTER_LEN, 0.0, 1.0)
		var a: Vector2 = n["p0"]
		var b: Vector2 = n["p1"]
		return a.lerp(b, k)
	var tau := now - float(n["birth"])
	if tau <= 0.0:
		return n["p0"]
	var th0: float = n["th0"]
	var w: float = n["w"]
	var v: float = n["v"]
	var p0: Vector2 = n["p0"]
	if absf(w) < 1e-6:                    # 不拐弯：直线
		return p0 + Vector2(cos(th0), sin(th0)) * v * tau
	var th := th0 + w * tau
	return p0 + (v / w) * Vector2(sin(th) - sin(th0), -(cos(th) - cos(th0)))


func _theta(n: Dictionary, now: float) -> float:
	if int(n["gen"]) == 0:
		return n["th0"]
	return float(n["th0"]) + float(n["w"]) * (now - float(n["birth"]))


## 画鲸鱼用的前进方向：第 0 代是进场方向，其余是圆弧切线
func _dir(n: Dictionary, now: float) -> Vector2:
	if int(n["gen"]) == 0:
		var a: Vector2 = n["p0"]
		var b: Vector2 = n["p1"]
		return (b - a).normalized()
	var th := _theta(n, now)
	return Vector2(cos(th), sin(th))


## 分裂前 0.75 拍：白 / 蓝闪烁，同时 1.0 → 1.15 放大
func _scale(n: Dictionary, now: float) -> float:
	var s := 1.0
	if int(n["gen"]) > 0:
		s = lerpf(0.6, 1.0, clampf((now - float(n["birth"])) / GROW_LEN, 0.0, 1.0))
	var sp: float = n["split"]
	if sp < NO_SPLIT and now >= sp - WARN_LEN and now < sp:
		s *= lerpf(1.0, WARN_SCALE, (now - (sp - WARN_LEN)) / WARN_LEN)
	return s


func _color(n: Dictionary, now: float) -> Color:
	var sp: float = n["split"]
	if sp < NO_SPLIT and now >= sp - WARN_LEN and now < sp:
		var step := int((now - (sp - WARN_LEN)) / 0.125)
		return C.SYS if step % 2 == 1 else C.WHITE
	return C.WHITE


func _alive(n: Dictionary, now: float) -> bool:
	if now < float(n["birth"]) or now >= float(n["split"]):
		return false
	if int(n["gen"]) == 3:
		if bool(n["gone"]):
			return false
		# 出生就在框外 20px 之外的（A 波上面那 4 条）先留着，等它绕回来；
		# 一旦进过框、再游出 20px，就永久不再处理。
		if bool(n["entered"]) and not box.grow(GEN3_PAD).has_point(_pos(n, now)):
			return false
	return true


# ── 每帧 ──────────────────────────────────────────────────────

func tick(_dt: float) -> void:
	if not _built:
		_build()
	for wave in 2:
		if crossed(WAVE_START[wave]):
			pose("summon")
			sfx("whale", 0.7)
	for n in _tree:
		var sp: float = n["split"]
		if sp < NO_SPLIT and crossed(sp):
			sfx("spinner_burst")
	# 第 3 代：记录「进过框」，以及「进过框之后再出框 20px」→ 永久消失
	for n in _tree:
		if int(n["gen"]) != 3 or bool(n["gone"]):
			continue
		if t < float(n["birth"]):
			continue
		if box.grow(GEN3_PAD).has_point(_pos(n, t)):
			n["entered"] = true
		elif bool(n["entered"]):
			n["gone"] = true
	for n in _tree:
		if not _alive(n, t):
			continue
		hz_circle(_pos(n, t), Whale.radius(int(n["width"])) * _scale(n, t))


func _caption() -> String:
	var s0: float = FIRST_SPLIT[1] if t >= WAVE_START[1] else FIRST_SPLIT[0]
	var stage := 0
	if t >= s0:
		stage = 1
	if t >= s0 + SPLIT_GAP:
		stage = 2
	if t >= s0 + SPLIT_GAP * 2.0:
		stage = 3
	match stage:
		1:
			return "蒸馏中：671B → 70B"
		2:
			return "蒸馏中：… → 70B → 7B"
		3:
			return "蒸馏中：… → 70B → 7B → 1.5B"
	return "蒸馏中：671B"


func _draw() -> void:
	if not _built:
		_build()
	for n in _tree:
		if not _alive(n, t):
			continue
		Whale.draw(self, _pos(n, t), _dir(n, t), int(n["width"]), _color(n, t), _scale(n, t))
	Px.text(self, box.position + Vector2(4, 2), _caption(), C.SYS)
