extends Node2D
## 暂停菜单的载体：暂停时也运行，每帧把输入交给 battle.pause_input()，并画暂停菜单。

var battle: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_dt: float) -> void:
	battle.pause_input()
	queue_redraw()


func _draw() -> void:
	battle.draw_pause(self)
