extends Node
## 调试开关（自动加载 Dbg）。参数写在命令行 `--` 之后，例如：
##   godot --path game -- --jump=P1-1 --god --auto=spare --shots=/tmp/x --shot-every=30 --quit-at=1800
## 支持的开关：
##   --jump=<P1-1|P2-3|P3-2|final_kill|final_spare|end_kill|end_spare|gameover|title>  跳过开场直接进入某处
##   --god               不扣血
##   --auto=<kill|spare> 自动驾驶：自动选菜单、自动翻页（配合 --god 跑通整条路线）
##   --mute              静音
##   --shots=<目录>      截图目录；--shot-every=<帧> 每隔几帧截一张；--shot-at=<帧,帧,...> 指定帧截图
##   --quit-at=<帧>      到这一帧退出
##   --speed=<倍数>      时间倍速（Engine.time_scale）
##   --seed=<整数>       随机种子
##   --keys=<帧:键[:按住帧数],...>  在指定帧模拟按键（键：z x left right up down esc；默认按住 2 帧），测试真实输入路径用

var args := {}
var frame := 0
var _shot_at := {}
var _keys := {}                  # 帧 -> 键名（按下）
var _key_up := {}                # 帧 -> 键名（松开）
const KEYMAP := {"z": KEY_Z, "x": KEY_X, "left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN, "esc": KEY_ESCAPE}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	for s in str(args.get("shot-at", "")).split(",", false):
		_shot_at[int(s)] = true
	for kv in str(args.get("keys", "")).split(",", false):
		var p := kv.split(":")
		_keys[int(p[0])] = p[1]
		_key_up[int(p[0]) + (int(p[2]) if p.size() > 2 else 2)] = p[1]
	if args.has("speed"):
		Engine.time_scale = float(args["speed"])
	if args.has("shots"):
		DirAccess.make_dir_recursive_absolute(args["shots"])


func has(k: String) -> bool:
	return args.has(k)


func val(k: String, def := "") -> String:
	return str(args.get(k, def))


func _process(_dt: float) -> void:
	frame += 1
	if _keys.has(frame):
		_press(KEYMAP.get(_keys[frame], KEY_Z), true)
	if _key_up.has(frame):
		_press(KEYMAP.get(_key_up[frame], KEY_Z), false)
	if args.has("shots"):
		var every := int(args.get("shot-every", "0"))
		if _shot_at.has(frame) or (every > 0 and frame % every == 0):
			shot("f%05d" % frame)
	if args.has("quit-at") and frame >= int(args["quit-at"]):
		get_tree().quit()


## 截当前画面到 shots 目录
func shot(name: String) -> void:
	if not args.has("shots"):
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [args["shots"], name])


## 打一行日志（安卓上在 logcat 的 godot 标签下）
func log(s: String) -> void:
	print("[dbg %05d] %s" % [frame, s])


func _press(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
