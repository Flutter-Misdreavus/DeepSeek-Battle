class_name Attack
extends Node2D
## 所有攻击的基类。一个攻击 = 一个节点，挂在弹幕框的裁剪层下面（画出框的部分自动被裁掉）。
##
## 时间一律用「拍」：t 是攻击开始后经过的拍数（已乘 speed）。位置尽量写成 t 的函数，这样和音乐对得上、结果可复现。
## 每帧 battle 依次调用：clear_hazards() → tick(dt) → queue_redraw()；然后用 hazards 和红心判定碰撞。
##
## 子类要做的：
##   - 在 _init() 或 setup() 里设 duration（拍数）、box_size（弹幕框内框大小）、damage
##   - tick(dt)：更新状态；用 hz_rect() / hz_circle() 登记本帧所有会伤人的形状
##   - _draw()：画框里的东西（坐标是逻辑像素，和整个战斗场景同一坐标系）
##   - draw_outside(ci)：可选，画在框外、不被裁剪的东西（比如框上方的「专家」格子）
##   - 用 pose("sweep") 让她换姿势，sfx("warn") 放音效，box 是当前内框（Rect2）

var battle: Node                 # 战斗主控（battle.gd）
var box := Rect2()               # 弹幕框内框（攻击开始时已经变形到位）
var t := 0.0                     # 已经过的拍数
var prev_t := -0.001             # 上一帧的 t（判断「刚越过第 n 拍」用；从 -0.001 开始，第 0 拍也算越过）
var speed := 1.0                 # 倍速（重新生成、版本号会调高）
var duration := 16.0             # 总拍数，到了就结束
var box_size := Vector2(156, 116)
var damage := 3
var stop_beat := -1.0            # 「■ 停止」按钮出现的拍；-1 = duration 的一半
var stop_spot := Vector2(-1, -1) # 「■ 停止」按钮的中心；(-1,-1) = 框内右上角
var mirror := false              # 左右镜像（重新生成第二遍用）
var rng := RandomNumberGenerator.new()
var opts := {}                   # battle.run_attack 传进来的选项（比如终局的 "route": "kill" / "spare"）

var hazards_r: Array[Rect2] = []
var hazards_c: Array[Vector3] = []   # x, y, 半径


func setup() -> void:
	pass


func begin() -> void:
	pass


func tick(_dt: float) -> void:
	pass


func draw_outside(_ci: CanvasItem) -> void:
	pass


func finished() -> bool:
	return t >= duration


func clear_hazards() -> void:
	hazards_r.clear()
	hazards_c.clear()


func hz_rect(r: Rect2) -> void:
	hazards_r.append(r)


func hz_circle(c: Vector2, rad: float) -> void:
	hazards_c.append(Vector3(c.x, c.y, rad))


## 红心判定框和本帧任一伤害形状重叠？
func hits(hb: Rect2) -> bool:
	for r in hazards_r:
		if r.intersects(hb):
			return true
	for c in hazards_c:
		var p := Vector2(clampf(c.x, hb.position.x, hb.end.x), clampf(c.y, hb.position.y, hb.end.y))
		if p.distance_squared_to(Vector2(c.x, c.y)) < c.z * c.z:
			return true
	return false


## 这一帧是否刚越过第 n 拍（n 可以是小数）
func crossed(n: float) -> bool:
	return prev_t < n and t >= n


## 刚越过的整拍号；没有越过就是 -1
func beat_hit() -> int:
	var a := floori(prev_t)
	var b := floori(t)
	return b if b > a else -1


func pose(name: String) -> void:
	if battle:
		battle.enemy.set_pose(name)


func sfx(name: String, pitch := 1.0) -> void:
	Sfx.play(name, pitch)


func soul_pos() -> Vector2:
	return battle.soul.pos if battle else box.get_center()


## 镜像时把 x 翻过来（以框的中线为轴）
func mx(x: float) -> float:
	return box.position.x + box.end.x - x if mirror else x
