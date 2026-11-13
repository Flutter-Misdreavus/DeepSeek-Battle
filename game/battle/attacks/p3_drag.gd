extends Attack
## P3-1「拖拽」
##
## 她的红色光标点住你的心，拖着它走；框里有四条横向滚动的字块，被拖过去就会撞上。
## - 4 条车道，奇数道向右、偶数道向左，每拍滚 26px；每条 7 个字块，字取自「光标控制权已转移」。
## - 第 2 / 8 / 14 拍各抓一次，每次 4 拍：悬停 1 拍预警，然后沿两段匀速直线把心拖向框角。
## - 被抓期间用 soul.tether 画红线、用 soul.pull 施加 72px/s 的外力；松手时两样都复位。
## - 本攻击不镜像。

const LANES := 4
const BLOCKS_PER_LANE := 7
const LANE_Y := [10.0, 38.0, 66.0, 94.0]
const LANE_PHASE := [0.0, 20.0, 10.0, 30.0]
const SPACING := 40.0
const PERIOD := 280.0
const SCROLL := 26.0
const CHARS := "光标控制权已转移"
const GRABS := [2.0, 8.0, 14.0]
const GRAB_LEN := 4.0
const PULL_SPEED := 72.0
## 每次抓取的两个路点（框尺寸的比例）
const WAYPOINTS := [
	[Vector2(0.15, 0.08), Vector2(0.15, 0.92)],
	[Vector2(0.85, 0.92), Vector2(0.85, 0.08)],
	[Vector2(0.50, 0.08), Vector2(0.50, 0.92)],
]

var _starts: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]


func setup() -> void:
	duration = 18.0
	box_size = Vector2(200, 130)
	stop_beat = 6.0


func begin() -> void:
	pose("A_smile")


## 第 k 条车道、第 n 个字块在拍 now 的左边 x
func _block_x(k: int, n: int, now: float) -> float:
	var dir := 1.0 if k % 2 == 0 else -1.0
	return box.position.x - 20.0 + fposmod(
		n * SPACING + LANE_PHASE[k] + dir * SCROLL * now,
		PERIOD
	)


## 第 k 条车道的顶边 y
func _lane_y(k: int) -> float:
	return box.position.y + LANE_Y[k]


## 第 i 次抓取的第 j 个路点
func _waypoint(i: int, j: int) -> Vector2:
	var f: Vector2 = WAYPOINTS[i][j]
	return box.position + f * box.size


## 现在正处在第 i 次抓取中（含松手那一帧之前）
func _grab_at(now: float) -> int:
	for i in GRABS.size():
		if now >= GRABS[i] and now < GRABS[i] + GRAB_LEN:
			return i
	return -1


## 现在是在第 i 次抓取前的悬停预警
func _hover_at(now: float) -> int:
	for i in GRABS.size():
		if now >= GRABS[i] - 1.0 and now < GRABS[i]:
			return i
	return -1


## 箭尖在拍 now 的位置
func _tip(now: float) -> Vector2:
	var gi := _grab_at(now)
	if gi >= 0:
		var g: float = GRABS[gi]
		var p1 := _waypoint(gi, 0)
		var p2 := _waypoint(gi, 1)
		if now < g + 1.0:
			return _starts[gi].lerp(p1, clampf(now - g, 0.0, 1.0))
		return p1.lerp(p2, clampf((now - (g + 1.0)) / 3.0, 0.0, 1.0))
	return soul_pos() + Vector2(5, 3)


func _cursor_on(now: float) -> bool:
	return _grab_at(now) >= 0 or _hover_at(now) >= 0


func tick(_dt: float) -> void:
	# 字块伤害；前 1 拍只画不伤人，避免出生点被扫到
	if t >= 1.0:
		for k in LANES:
			var y := _lane_y(k)
			for n in BLOCKS_PER_LANE:
				var x := _block_x(k, n, t)
				hz_rect(Rect2(x + 1.0, y + 1.0, 10.0, 10.0))
	# 抓取状态：预警 → 抓住 → 松手
	for i in GRABS.size():
		var g: float = GRABS[i]
		if crossed(g - 1.0):
			sfx("warn")
		if crossed(g):
			_starts[i] = soul_pos()
			sfx("click")
		if crossed(g + GRAB_LEN):
			sfx("click")
			_release()
	# 抓住期间：画连线、施加外力
	var gi := _grab_at(t)
	if gi >= 0 and battle and is_instance_valid(battle.soul):
		var tip := _tip(t)
		var heart := soul_pos()
		battle.soul.tether = tip
		var d := tip - heart
		if d.length() > 3.0:
			battle.soul.pull = d.normalized() * PULL_SPEED
		else:
			battle.soul.pull = Vector2.ZERO


func _release() -> void:
	if battle and is_instance_valid(battle.soul):
		battle.soul.tether = null
		battle.soul.pull = Vector2.ZERO


func _exit_tree() -> void:
	# 攻击被中途结束（退出战斗、游戏结束）时也不要把红心留在被拖着的状态
	if battle and is_instance_valid(battle) and is_instance_valid(battle.soul):
		battle.soul.tether = null
		battle.soul.pull = Vector2.ZERO


func _draw() -> void:
	# 字块（会被框裁掉）
	for k in LANES:
		var y := roundf(_lane_y(k))
		for n in BLOCKS_PER_LANE:
			var x := roundf(_block_x(k, n, t))
			var ch := CHARS[(k * BLOCKS_PER_LANE + n) % CHARS.length()]
			Px.text(self, Vector2(x, y), ch, C.RED)
	# 红光标只在预警和抓取期间出现
	if _cursor_on(t):
		Px.cursor(self, _tip(t), C.RED)
