extends Node
## 玩家设置：跨场景保留，并保存到本机。

const SAVE_PATH := "user://settings.cfg"

var invincible := false


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		invincible = config.get_value("gameplay", "invincible", false) == true


func toggle_invincible() -> void:
	invincible = not invincible
	var config := ConfigFile.new()
	config.set_value("gameplay", "invincible", invincible)
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_warning("无法保存游戏设置：%s" % error_string(err))


func invincible_label() -> String:
	return "无敌模式：%s" % ("开启" if invincible else "关闭")
