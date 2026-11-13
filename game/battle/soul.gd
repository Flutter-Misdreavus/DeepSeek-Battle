extends Node2D
## 玩家的心。pos 是中心（逻辑像素）。弹幕阶段 active = true 时可以动，被限制在 area（框的内框）里。
## mode（照传说之下的心的颜色）：
##   "red"   红心：自由移动（默认）
##   "green" 绿心：钉在原地不能动。方向键把盾转到上 / 下 / 左 / 右；触屏点按或滑动，按方向决定盾朝哪边。
##           挡没挡住由攻击自己判断（读 shield_dir），挡住时调用 block() 出火花和音效。
##   "blue"  蓝心：往 gravity 方向掉。只能沿地面方向移动；落地后按「和重力相反的方向键」起跳，按得越久跳得越高。
##           触屏：沿地面方向拖动移动；手指按下起跳，按住跳得更高。
##           slam(方向)：把重力改到那个方向并猛地摔过去（她拖窗口、转窗口时用），撞墙时发 slammed 信号。
## pull：外力（逻辑像素/秒），拖拽攻击用；tether：非 null 时从这点到心画一根红线。

signal slammed

const GREEN := Color("#22d822")
const BLUE := Color("#2f6bff")
const SHIELD_R := 13.0          # 盾离心中心的距离
const SHIELD_LEN := 20.0
const GRAV := 900.0             # 蓝心重力加速度（逻辑像素/秒²）
const GRAV_HOLD := 420.0        # 按住起跳键往上升时的重力（按得久跳得高）
const JUMP_V := 210.0           # 起跳速度
const CUT_V := 110.0            # 松开起跳键时，上升速度最多保留这么多（轻点一下约跳 17px，刚好越过一层图标）
const SLAM_V := 480.0           # 被摔出去的速度

var pos := Vector2(320, 238)
var active := false
var area := Rect2()
var pull := Vector2.ZERO
var tether = null
var iframe := 0.0
var shown := true
var col := C.HEART
var mode := "red"
var shield_dir := Vector2i(0, -1)
var gravity := Vector2i(0, 1)
var vel := 0.0                  # 蓝心：沿重力方向的速度（正 = 往「下」掉）
var on_floor := false
var _slamming := false
var _drag_acc := Vector2.ZERO
var _swipe := 0.0
var _touch_jump := false
var _jump_buf := 0.0
var _flash := 0.0               # 换颜色时的白圈
var _block_fx := 0.0            # 挡住时的火花


## 换心的颜色。quiet = 不放音效、不闪（攻击结束时复位用）
func set_mode(m: String, quiet := false) -> void:
	if m == mode:
		return
	mode = m
	vel = 0.0
	on_floor = false
	_slamming = false
	_drag_acc = Vector2.ZERO
	if m == "blue":
		gravity = Vector2i(0, 1)
	if not quiet:
		_flash = 0.25
		Sfx.play("soul_mode")


## 蓝心：改重力方向（不摔）
func set_gravity(d: Vector2i) -> void:
	gravity = d
	vel = 0.0
	on_floor = false


## 蓝心：猛地摔向 d
func slam(d: Vector2i) -> void:
	gravity = d
	vel = SLAM_V
	on_floor = false
	_slamming = true


## 绿心：攻击判定挡住了一次
func block() -> void:
	_block_fx = 0.15
	Sfx.play("block")


func _process(dt: float) -> void:
	if iframe > 0.0:
		iframe -= dt
	_flash = maxf(0.0, _flash - dt)
	_block_fx = maxf(0.0, _block_fx - dt)
	if active:
		match mode:
			"green":
				_green_input()
			"blue":
				_blue_step(dt)
			_:
				var v := Inp.move_vec() * C.SOUL_SPEED * dt
				v += Inp.drag.limit_length(C.SOUL_SPEED * C.TOUCH_CAP * dt)
				v += pull * dt
				pos = clamp_in(pos + v)
	queue_redraw()


func _green_input() -> void:
	var d := Inp.take_dir()
	if d != Vector2i.ZERO:
		shield_dir = d
	var tp = Inp.take_tap()
	if tp != null:
		shield_dir = _axis((tp as Vector2) - to_global(pos))
	_drag_acc += Inp.drag
	if _drag_acc.length() > 6.0:
		shield_dir = _axis(_drag_acc)
		_drag_acc = Vector2.ZERO
	if not Inp.touching:
		_drag_acc = Vector2.ZERO


static func _axis(v: Vector2) -> Vector2i:
	if absf(v.x) > absf(v.y):
		return Vector2i(1 if v.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if v.y > 0.0 else -1)


func _blue_step(dt: float) -> void:
	var g := Vector2(gravity)
	var side := Vector2(absf(g.y), absf(g.x))           # 沿地面的轴
	# 沿地面移动
	var m := Inp.move_vec().dot(side) * C.SOUL_SPEED * dt
	m += Inp.drag.dot(side)
	m = clampf(m, -C.SOUL_SPEED * C.TOUCH_CAP * dt, C.SOUL_SPEED * C.TOUCH_CAP * dt)
	pos += side * m
	# 起跳：键盘按住「反重力方向键」；触屏往反重力方向滑超过 8px（一次滑动只跳一次，按住手指跳得更高）
	var key_up := Inp.move_vec().dot(-g) > 0.0
	if not Inp.touching or Inp.tap != null:
		_swipe = 0.0
		_touch_jump = false
	_swipe += Inp.drag.dot(-g)
	if Inp.touching and not _touch_jump and _swipe > 8.0:
		_touch_jump = true
		_jump_buf = 0.15                                  # 还没落地就先记着，落地马上跳
	_jump_buf = maxf(0.0, _jump_buf - dt)
	var held := key_up or (_touch_jump and Inp.touching)
	if on_floor and (key_up or _jump_buf > 0.0) and not _slamming:
		vel = -JUMP_V
		on_floor = false
		_jump_buf = 0.0
	if not on_floor:
		if not held and vel < -CUT_V and not _slamming:
			vel = -CUT_V
		vel += (GRAV_HOLD if held and vel < 0.0 else GRAV) * dt
		pos += g * vel * dt
	pos += pull * dt
	# 落地 / 顶头
	var c := clamp_in(pos)
	var hit_floor := (c - pos).dot(g) < 0.0 or _at_wall(c, g)
	var hit_ceil := (c - pos).dot(g) > 0.0
	pos = c
	if hit_floor and vel >= 0.0:
		if _slamming:
			_slamming = false
			slammed.emit()
		on_floor = true
		vel = 0.0
	elif hit_ceil and vel < 0.0:
		vel = 0.0
	if on_floor and not _at_wall(pos, g):
		on_floor = false                                  # 地面被拿走了（窗口变大、换了重力）


## p 是否贴着重力方向那面墙
func _at_wall(p: Vector2, g: Vector2) -> bool:
	if area.size == Vector2.ZERO:
		return false
	var lo := area.position + C.SOUL_HALF
	var hi := area.end - C.SOUL_HALF
	if g.y > 0.0:
		return p.y >= hi.y - 0.01
	if g.y < 0.0:
		return p.y <= lo.y + 0.01
	if g.x > 0.0:
		return p.x >= hi.x - 0.01
	return p.x <= lo.x + 0.01


func clamp_in(p: Vector2) -> Vector2:
	if area.size == Vector2.ZERO:
		return p
	return p.clamp(area.position + C.SOUL_HALF, area.end - C.SOUL_HALF)


func hitbox() -> Rect2:
	return Rect2(pos - C.HITBOX / 2, C.HITBOX)


func color() -> Color:
	match mode:
		"green":
			return GREEN
		"blue":
			return BLUE
	return col


func _draw() -> void:
	if not shown:
		return
	if tether != null:
		var a: Vector2 = tether
		draw_line(a.round() + Vector2(0.5, 0.5), pos.round() + Vector2(0.5, 0.5), C.RED, 1.0)
	if _flash > 0.0:
		draw_arc(pos.round(), 8.0 + (0.25 - _flash) * 60.0, 0.0, TAU, 24, Color(1, 1, 1, _flash * 4.0), 1.0)
	if mode == "green":
		draw_arc(pos.round(), SHIELD_R + 1.0, 0.0, TAU, 24, Color(GREEN, 0.35), 1.0)
		var d := Vector2(shield_dir)
		var c := pos.round() + d * SHIELD_R
		var along := Vector2(absf(d.y), absf(d.x))
		var r := Rect2(c - along * SHIELD_LEN / 2.0 - d.abs() * 1.0, along * SHIELD_LEN + d.abs() * 3.0)
		r = r.abs()
		draw_rect(r, C.WHITE if _block_fx > 0.0 else GREEN)
	if iframe > 0.0 and int(iframe * 12.0) % 2 == 0:
		return
	Px.heart(self, pos, color())
