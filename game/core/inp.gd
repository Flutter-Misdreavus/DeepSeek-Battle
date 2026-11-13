extends Node
## 统一输入（自动加载 Inp）。
## 键盘：方向键 / WASD 移动，Z / Enter 确认，X / Shift 返回，Esc 暂停，F11 全屏。
## 触屏（桌面上鼠标会模拟触屏）：点按 = tap；按住拖动 = drag（按两次事件的绝对坐标相减，不丢起步的几个像素）。
## 事件先记进 _p*，每帧最先执行的 _process 把它们变成「本帧状态」；读的一方用 take_*() 读完即清，避免一次按键被两处消费。

var ok := false
var advance := false             # 回车：剧情中一次推进一句，与普通确认分开读取
var cancel := false
var pause := false
var dir := Vector2i.ZERO          # 本帧刚按下的方向（菜单用）
var tap = null                    # 本帧的点按位置（视口坐标），没有则 null
var drag := Vector2.ZERO          # 本帧触屏拖动位移（视口坐标）
var touching := false
var pause_rect := Rect2()         # 战斗暂停按钮的视口范围；标题页为空
var locked := false               # 暂停菜单打开时为 true：普通读取一律读不到，只有 force = true 能读

var _p_ok := false
var _p_advance := false
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
	advance = _p_advance
	cancel = _p_cancel
	pause = _p_pause
	dir = _p_dir
	tap = _p_tap
	drag = _p_drag
	_p_ok = false
	_p_advance = false
	_p_cancel = false
	_p_pause = false
	_p_dir = Vector2i.ZERO
	_p_tap = null
	_p_drag = Vector2.ZERO


## 场景切换时清空当前及待处理的确认，避免一次输入同时离开结局又开始新游戏。
func clear_confirm() -> void:
	ok = false
	advance = false
	tap = null
	_p_ok = false
	_p_advance = false
	_p_tap = null


func take_ok(force := false) -> bool:
	if locked and not force:
		return false
	var v := ok
	ok = false
	if v:
		advance = false
	return v


func take_advance() -> bool:
	if locked:
		return false
	var v := advance
	advance = false
	if v:
		ok = false
	return v


func take_cancel(force := false) -> bool:
	if locked and not force:
		return false
	var v := cancel
	cancel = false
	return v


func take_tap(force := false):
	if locked and not force:
		return null
	var v = tap
	tap = null
	return v


func take_dir(force := false) -> Vector2i:
	if locked and not force:
		return Vector2i.ZERO
	var v := dir
	dir = Vector2i.ZERO
	return v


## 持续按住的方向（移动红心用）。斜向两轴都满速，和传说之下一样不做归一化。
func move_vec() -> Vector2:
	if locked:
		return Vector2.ZERO
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
			KEY_ENTER, KEY_KP_ENTER:
				_p_advance = true
				_p_ok = true
			KEY_Z:
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
			if pause_rect.has_point(e.position):
				_p_pause = true
			else:
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
