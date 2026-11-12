extends Node
## 统一输入（自动加载 Inp）。
## 键盘：方向键 / WASD 移动，Z / Enter 确认，X / Shift 返回，Esc 暂停，F11 全屏。
## 触屏（桌面上鼠标会模拟触屏）：点按 = tap；按住拖动 = drag（按两次事件的绝对坐标相减，不丢起步的几个像素）。
## 事件先记进 _p*，每帧最先执行的 _process 把它们变成「本帧状态」；读的一方用 take_*() 读完即清，避免一次按键被两处消费。

var ok := false
var cancel := false
var pause := false
var dir := Vector2i.ZERO          # 本帧刚按下的方向（菜单用）
var tap = null                    # 本帧的点按位置（视口坐标），没有则 null
var drag := Vector2.ZERO          # 本帧触屏拖动位移（视口坐标）
var touching := false

var _p_ok := false
var _p_cancel := false
var _p_pause := false
var _p_dir := Vector2i.ZERO
var _p_tap = null
var _p_drag := Vector2.ZERO
var _last := {}                   # 手指 index -> 上一次位置


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100


func _process(_dt: float) -> void:
	ok = _p_ok
	cancel = _p_cancel
	pause = _p_pause
	dir = _p_dir
	tap = _p_tap
	drag = _p_drag
	_p_ok = false
	_p_cancel = false
	_p_pause = false
	_p_dir = Vector2i.ZERO
	_p_tap = null
	_p_drag = Vector2.ZERO


func take_ok() -> bool:
	var v := ok
	ok = false
	return v


func take_cancel() -> bool:
	var v := cancel
	cancel = false
	return v


func take_tap():
	var v = tap
	tap = null
	return v


func take_dir() -> Vector2i:
	var v := dir
	dir = Vector2i.ZERO
	return v


## 持续按住的方向（移动红心用）。斜向两轴都满速，和传说之下一样不做归一化。
func move_vec() -> Vector2:
	var x := float(Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A))
	var y := float(Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W))
	return Vector2(x, y)


## 注入一次点按（自动驾驶 / 测试用），pos 是视口坐标
func inject_tap(pos: Vector2) -> void:
	_p_tap = pos


func inject_ok() -> void:
	_p_ok = true


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_Z, KEY_ENTER, KEY_KP_ENTER:
				_p_ok = true
			KEY_X, KEY_SHIFT:
				_p_cancel = true
			KEY_ESCAPE:
				_p_pause = true
			KEY_LEFT, KEY_A:
				_p_dir = Vector2i(-1, 0)
			KEY_RIGHT, KEY_D:
				_p_dir = Vector2i(1, 0)
			KEY_UP, KEY_W:
				_p_dir = Vector2i(0, -1)
			KEY_DOWN, KEY_S:
				_p_dir = Vector2i(0, 1)
			KEY_F11:
				var w := get_window()
				w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	elif e is InputEventScreenTouch:
		if e.pressed:
			_last[e.index] = e.position
			_p_tap = e.position
		else:
			_last.erase(e.index)
		touching = not _last.is_empty()
	elif e is InputEventScreenDrag:
		if _last.has(e.index):
			_p_drag += e.position - _last[e.index]
		_last[e.index] = e.position


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_p_cancel = true
