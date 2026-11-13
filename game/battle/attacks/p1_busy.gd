extends Attack
## 随机加载圈：前五圈依次出现，结尾三圈同时出现。每圈预警两拍后爆开。

const SPAWN_BEATS := [0.0, 2.0, 4.0, 6.0, 8.0, 11.5, 11.5, 11.5]
const PLAYER_CLEARANCE := 48.0
const CIRCLE_SPACING := 32.0
var _centers: Array[Vector2] = []


func setup() -> void:
	duration = 16.0
	box_size = Vector2(180, 120)
	stop_beat = 6.0
	_centers.clear()


func _valid_center(p: Vector2, group: Array[Vector2], player: Vector2) -> bool:
	if p.distance_to(player) < PLAYER_CLEARANCE:
		return false
	for other in group:
		if p.distance_to(other) < CIRCLE_SPACING:
			return false
	return true


func _sample_centers(count: int) -> Array[Vector2]:
	var area := box.grow(-10.0)
	var player := soul_pos()
	var result: Array[Vector2] = []
	for i in count:
		for attempt in 32:
			var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
			if _valid_center(p, result, player):
				result.append(p)
				break
		if result.size() == i + 1:
			continue
		# 有限网格兜底：选离玩家及已选圈最远的合法候选，不降低安全距离。
		var best := Vector2.ZERO
		var score := -INF
		for y in range(int(area.position.y), int(area.end.y) + 1, 4):
			for x in range(int(area.position.x), int(area.end.x) + 1, 4):
				var p := Vector2(x, y)
				if not _valid_center(p, result, player):
					continue
				var d := p.distance_squared_to(player)
				for other in result:
					d = minf(d, p.distance_squared_to(other))
				if d > score:
					best = p
					score = d
		assert(score >= 0.0, "加载圈必须有合法位置")
		result.append(best)
	return result


func _center(j: int) -> Vector2:
	return _centers[j]


func _angle(j: int, k: int) -> float:
	return deg_to_rad(k * 45.0 + (22.5 if j % 2 == 0 else 0.0))


func _burst_pos(c: Vector2, j: int, k: int, burst: float) -> Vector2:
	return c + Vector2.from_angle(_angle(j, k)) * (7.0 + 40.0 * (t - burst))


func tick(_dt: float) -> void:
	while _centers.size() < SPAWN_BEATS.size() and t >= SPAWN_BEATS[_centers.size()]:
		_centers.append_array(_sample_centers(3 if _centers.size() == 5 else 1))
	for j in _centers.size():
		var burst: float = SPAWN_BEATS[j] + 2.0
		if crossed(burst):
			sfx("spinner_burst")
		if t >= burst:
			for k in 8:
				var p := _burst_pos(_center(j), j, k, burst)
				if box.grow(8.0).has_point(p):
					hz_circle(p, 1.6)
	if crossed(11.5):
		pose("snow")


func _draw() -> void:
	for j in _centers.size():
		var spawn: float = SPAWN_BEATS[j]
		var burst := spawn + 2.0
		var c := _center(j)
		if t < burst:
			var head := floori((t - spawn) * 8.0) % 8
			for k in 8:
				var p := c + Vector2.from_angle(_angle(j, k)) * 7.0
				var colors := [C.WHITE, C.COLD, C.SYS, C.SYS_DIM]
				var behind := (head - k + 8) % 8
				var col: Color = colors[behind] if behind < 4 else C.GRAY_DIM
				draw_rect(Rect2((p - Vector2.ONE).round(), Vector2(2, 2)), col)
		else:
			for k in 8:
				var p := _burst_pos(c, j, k, burst)
				if box.grow(8.0).has_point(p):
					draw_rect(Rect2((p - Vector2(1.5, 1.5)).round(), Vector2(3, 3)), C.WHITE)
