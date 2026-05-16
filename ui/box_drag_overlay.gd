extends Control

# 盒子拖拽时的全屏透明覆盖层，捕获松开事件
# 放置于 Viewport 顶层，z_index > 预览

signal drag_ended()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 2000

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		drag_ended.emit()
