extends Attack
## 终局「防火墙」
##
## MV 结尾那堵红砖墙：一道道砖墙从右边卷进来，每道墙上留一个缺口，红心要一路钻过去。
## - 第 k 道墙在 2.2k 拍从框右边外面进入，以每拍 46px 往左扫；墙宽 36px，高 = 整个框高。
## - 墙进入后的头 1 拍里，砖从最上面和最下面同时往缺口砌，每 0.05 拍砌一行（行高 12px）。
##   还没砌的行不画、不伤人；每砌好 4 行响一次砖声。
## - 墙进入后的头 0.5 拍只画不登记伤害，避免红心贴着右边缘时被刚出现的墙突然撞上。
## - 每道墙的缺口高 54px，位置由 GAP_RATIOS 决定；缺口以外都是砖。
## - 每越过一个整拍，所有墙在前 0.1 拍里闪一下亮砖色。
## - mirror 不参与：终局这一段固定不镜像。

const WALLS := 7
const WALL_INTERVAL := 2.2        # 相邻两道墙进入的间隔（拍）
const WALL_SPEED := 46.0          # 每拍往左扫的像素
const WALL_W := 36.0
const WALL_ENTER_X := 4.0         # 进入时墙左边在框右边外面多少像素
const GAP_H := 54.0
const GAP_RATIOS := [0.50, 0.30, 0.66, 0.26, 0.72, 0.42, 0.56]
const ROW_H := 12.0
const BRICK_W := 24.0
const BUILD_STEP := 0.05          # 每 0.05 拍砌一行
const FLASH_LEN := 0.1            # 整拍开头闪多久

const BRICK := Color("#58101a")
const BRICK_FLASH := Color("#7a1c28")
const BRICK_TOP := Color("#8a2030")
const MORTAR := Color("#000000")
const MORTAR_H := 1.0

var _brick_sfx: Array = []        # 每道墙已经响到第几行（每 4 行一次）


func setup() -> void:
	duration = 16.0
	box_size = Vector2(620, 260)
	_brick_sfx.clear()
	for k in WALLS:
		_brick_sfx.append(0)


## 第 k 道墙在拍 t 的左边 x
func _wall_x(k: int) -> float:
	return box.end.x + WALL_ENTER_X - (t - WALL_INTERVAL * k) * WALL_SPEED


## 第 k 道墙的缺口（绝对坐标）
func _gap(k: int) -> Rect2:
	var cy := box.position.y + box.size.y * float(GAP_RATIOS[k])
	return Rect2(box.position.x, cy - GAP_H * 0.5, box.size.x, GAP_H)


## 第 k 道墙最多要砌几行（上段 + 下段）
func _row_budget(k: int) -> Vector2i:
	var g := _gap(k)
	var top_h := g.position.y - box.position.y
	var bot_h := box.end.y - g.end.y
	return Vector2i(ceili(top_h / ROW_H), ceili(bot_h / ROW_H))


## 第 k 道墙在拍 t 已经砌好了几行
func _laid_rows(k: int) -> int:
	var since := t - WALL_INTERVAL * k
	if since < 0.0:
		return 0
	var budget := _row_budget(k)
	var total := budget.x + budget.y
	return clampi(floori(since / BUILD_STEP + 0.0001), 0, total)


## 从已经砌好的行数拆成「缺口上面几行」「缺口下面几行」。
## 交替从上、下两端往缺口砌；一边砌满了，剩下的行就都去另一边。
func _laid_counts(k: int, laid: int) -> Vector2i:
	var budget := _row_budget(k)
	var top := 0
	var bot := 0
	for q in laid:
		if q % 2 == 0:
			if top < budget.x:
				top += 1
			elif bot < budget.y:
				bot += 1
		else:
			if bot < budget.y:
				bot += 1
			elif top < budget.x:
				top += 1
	return Vector2i(top, bot)


## 这一拍是否在整拍开头的闪光窗口里
func _flashing() -> bool:
	return t - floorf(t) < FLASH_LEN


func tick(_dt: float) -> void:
	for k in WALLS:
		if t < WALL_INTERVAL * k:
			continue
		var x := _wall_x(k)
		if x + WALL_W < box.position.x:
			continue                       # 整道墙已经移出框左边，不再处理
		var laid := _laid_rows(k)
		# 砌砖声：每砌好 4 行一次
		var heard: int = _brick_sfx[k]
		if laid >= heard + 4:
			_brick_sfx[k] = laid
			sfx("brick")
		# 进入后的头 0.5 拍只画不伤人，给贴右边缘的红心留反应时间
		if t < WALL_INTERVAL * k + 0.5:
			continue
		if laid <= 0:
			continue
		var counts := _laid_counts(k, laid)
		var g := _gap(k)
		var x0 := x + 2.0
		var w := WALL_W - 4.0                    # 左右各内缩 2px
		# 缺口上面那一段
		if counts.x > 0:
			var y_end := minf(g.position.y, box.position.y + counts.x * ROW_H)
			if y_end > box.position.y:
				hz_rect(Rect2(x0, box.position.y, w, y_end - box.position.y))
		# 缺口下面那一段
		if counts.y > 0:
			var y_start := maxf(g.end.y, box.end.y - counts.y * ROW_H)
			if y_start < box.end.y:
				hz_rect(Rect2(x0, y_start, w, box.end.y - y_start))


func _draw() -> void:
	var brick := BRICK_FLASH if _flashing() else BRICK
	for k in WALLS:
		if t < WALL_INTERVAL * k:
			continue
		var x := _wall_x(k)
		if x + WALL_W < box.position.x:
			continue
		var laid := _laid_rows(k)
		if laid <= 0:
			continue
		var counts := _laid_counts(k, laid)
		_draw_side(k, x, 0, counts.x, brick)
		_draw_side(k, x, -1, counts.y, brick)


## 画第 k 道墙的一段砖。side = 0 是从墙顶往下砌，side = -1 是从墙底往上砌。
func _draw_side(k: int, x: float, side: int, rows: int, brick: Color) -> void:
	if rows <= 0:
		return
	var g := _gap(k)
	var seg := Rect2(x, box.position.y, WALL_W, g.position.y - box.position.y)
	if side == -1:
		seg = Rect2(x, g.end.y, WALL_W, box.end.y - g.end.y)
	for j in rows:
		# 上段以墙顶为基准，下段以墙底为基准；最后一行会被缺口边缘裁掉一点
		var y: float = (box.position.y + j * ROW_H) if side == 0 else (box.end.y - (j + 1) * ROW_H)
		var row_seg := Rect2(x, y, WALL_W, ROW_H).intersection(seg)
		if row_seg.size.x <= 0.0 or row_seg.size.y <= 0.0:
			continue
		# 行号按「从墙顶往下数」取，保证上下两段的错缝方向一致
		var r := floori((y - box.position.y) / ROW_H)
		# 偶数行从墙左边开始，奇数行错开半块砖；超出墙宽的部分由 intersection 裁掉
		var start := x if r % 2 == 0 else x - BRICK_W * 0.5
		var bx := start
		while bx < x + WALL_W:
			var cell := Rect2(bx, y, BRICK_W, ROW_H).intersection(row_seg)
			if cell.size.x > 0.0 and cell.size.y > 0.0:
				# 砖缝：先铺 1px 黑，再把砖体缩进右边和下边，露出砖缝
				draw_rect(Rect2(cell.position.round(), cell.size.round()), MORTAR)
				var body := Rect2(
					cell.position,
					Vector2(maxf(0.0, cell.size.x - MORTAR_H), maxf(0.0, cell.size.y - MORTAR_H))
				)
				if body.size.x > 0.0 and body.size.y > 0.0:
					var body_r := Rect2(body.position.round(), body.size.round())
					draw_rect(body_r, brick)
					draw_rect(Rect2(body_r.position.x, body_r.position.y, body_r.size.x, 1.0), BRICK_TOP)
			bx += BRICK_W
