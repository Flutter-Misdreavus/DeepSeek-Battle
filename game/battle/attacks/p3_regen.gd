extends Attack
## P3-2「重新生成」
##
## 她碎成像素灰，灰像帘子一样落进框里；然后「↻ 重新生成」，所有灰沿原路倒飞回去、她重新拼好；
## 接着整段左右镜像、1.5 倍速再来一遍。
## - 64 块灰在 setup() 里用 rng 定好出现拍、x 比例、速度、摆动和颜色，位置全部写成等效时间 τ 的纯函数。
## - τ：t<7 正常；[7,9) 倒放回 0；t>=9 从 0 以 1.5 倍速再走，同时 x 左右镜像。
## - 倒放期间灰变白、半透明、不伤人；其余时候原色伤人。她的立绘用 Ash 同步碎掉 / 拼好。
## - 第 7 拍版本号 +1，框里显示「↻ 重新生成」和新的版本号。

const GRAINS := 64
const GRAIN_LIFE := 6.0               # 第 i 块在 i * 6 / 64 拍出现
const REWIND_FROM := 7.0
const REWIND_TO := 9.0
const MIRROR_FROM := 9.0
const MIRROR_SPEED := 1.5
const ASH_DUR := 6.0
const COLORS := [Color("#2b2f4a"), Color("#5f6fa8"), Color("#d8d8e8"), C.RED]

var _grains: Array = []               # {s, fx, v, a, ph, col}
var _ash: Ash = null


func setup() -> void:
	duration = 17.5
	box_size = Vector2(180, 130)
	stop_beat = 4.0
	for i in GRAINS:
		_grains.append({
			"s": i * GRAIN_LIFE / float(GRAINS),
			"fx": 0.02 + 0.94 * rng.randf(),
			"v": 34.0 + 22.0 * rng.randf(),
			"a": 3.0 + 5.0 * rng.randf(),
			"ph": TAU * rng.randf(),
			"col": COLORS[rng.randi_range(0, 3)],
		})


func begin() -> void:
	_ash = Ash.new()
	_ash.dir = Vector2(0, 1)
	_ash.travel = 90.0
	battle.enemy.add_child(_ash)
	_ash.setup(battle.enemy.spr.texture, battle.enemy.rect())
	battle.enemy.spr.visible = false


## 等效时间 τ：第一遍正常、7–9 拍倒放、9 拍后左右镜像 1.5 倍速再来
func _tau(now: float) -> float:
	if now < REWIND_FROM:
		return now
	if now < REWIND_TO:
		return maxf(0.0, REWIND_FROM - (now - REWIND_FROM) * 3.5)
	return (now - MIRROR_FROM) * MIRROR_SPEED


func _mirrored(now: float) -> bool:
	return now >= MIRROR_FROM


## 第 i 块灰在拍 now 的位置（未取整）
func _grain_pos(g: Dictionary, tau: float, now: float) -> Vector2:
	var left: float = box.position.x + g["fx"] * box.size.x
	var x: float = left + g["a"] * sin((tau - g["s"]) * 2.0 + g["ph"])
	var y: float = box.position.y - 4.0 + (tau - g["s"]) * g["v"]
	if _mirrored(now):
		x = box.position.x + box.end.x - x - 3.0
	return Vector2(x, y)


func _grain_alive(g: Dictionary, tau: float, now: float) -> bool:
	return tau >= g["s"] and _grain_pos(g, tau, now).y < box.end.y + 4.0


func tick(_dt: float) -> void:
	if crossed(0.0) or crossed(MIRROR_FROM):
		sfx("ash")
	if crossed(REWIND_FROM):
		sfx("rewind")
		battle.version += 1
		battle._sync_hud()
	# 她的立绘跟着 τ 碎掉 / 拼好；最后 2 拍倒回原样
	var u := clampf(_tau(t) / ASH_DUR, 0.0, 1.0)
	if t >= 15.0:
		u *= 1.0 - clampf((t - 15.0) / 2.0, 0.0, 1.0)
	if _ash and is_instance_valid(_ash):
		_ash.u = u
	# 灰块伤害（倒放期间不伤人）
	var tau := _tau(t)
	var rewind := t >= REWIND_FROM and t < REWIND_TO
	if not rewind:
		for g in _grains:
			if not _grain_alive(g, tau, t):
				continue
			var p := _grain_pos(g, tau, t)
			hz_rect(Rect2(p.x, p.y, 3.0, 3.0))


func _draw() -> void:
	_draw_grains()
	if t >= REWIND_FROM and t < REWIND_TO:
		_draw_regen_prompt()


func _draw_grains() -> void:
	var tau := _tau(t)
	var rewind := t >= REWIND_FROM and t < REWIND_TO
	for g in _grains:
		if not _grain_alive(g, tau, t):
			continue
		var p := _grain_pos(g, tau, t)
		var col: Color = g["col"]
		if rewind:
			col = col.lerp(C.WHITE, 0.5)
			col.a = 0.6
		draw_rect(Rect2((p - Vector2(1.5, 1.5)).round(), Vector2(3, 3)), col)


func _draw_regen_prompt() -> void:
	var c := box.get_center()
	var s := "↻ 重新生成"
	var x := c.x - Px.text_w(s) * 0.5
	Px.text(self, Vector2(x, c.y - 14.0), s, C.WHITE)
	var ver := "V%d" % battle.version
	var vx := c.x - Fx.version_w(ver) * 0.5
	Fx.version(self, ver, Vector2(vx, c.y + 2.0), C.SYS, 12)


func _exit_tree() -> void:
	if _ash and is_instance_valid(_ash):
		_ash.queue_free()
		_ash = null
	if battle and is_instance_valid(battle) and is_instance_valid(battle.enemy):
		battle.enemy.spr.visible = true
