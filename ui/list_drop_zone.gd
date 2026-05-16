extends Control

# 零散模组拖放区域 + 插入指示线
# 覆盖整个 mod_list_container，用全局鼠标Y计算插入位置

var _indicator: ColorRect
var _current_idx: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	anchors_preset = Control.PRESET_FULL_RECT
	z_index = 50

	_indicator = ColorRect.new()
	_indicator.name = "InsertIndicator"
	_indicator.color = Color(0.3, 0.62, 1.0, 0.9)
	_indicator.custom_minimum_size = Vector2(0, 3)
	_indicator.visible = false
	_indicator.z_index = 1
	add_child(_indicator)


func _find_mod_manager() -> Node:
	var p = get_parent()
	while p:
		if p.has_method("move_mod_to_position"):
			return p
		p = p.get_parent()
	return null


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	if data.get("type", "") == "mod":
		# 必须返回 true 以允许事件继续传播到父节点（ModBox）
		# 鼠标在 ModBox 区域时由 ModBox._can_drop_data 显示盒子内指示线
		# list_drop_zone 只负责显示列表级指示线
		return true
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if data.get("type", "") != "mod":
		return
	# list_drop_zone 只在鼠标不在任何 ModBox 上时接收 drop
	# 所以如果到这里，说明确实要放到零散模组区域
	var mod_id = data.get("mod_id", "")
	var from_box = data.get("from_box", "")
	var mm = _find_mod_manager()
	if not mm:
		return
	var sibling_idx = _current_idx if _current_idx >= 0 else _calc_index_from_mouse()
	var parent = get_parent()
	var zero_level_idx = 0
	if parent and mm.has_method("sibling_idx_to_zero_level_idx"):
		zero_level_idx = mm.sibling_idx_to_zero_level_idx(parent, sibling_idx, mod_id)
	if mm.has_method("move_mod_to_position"):
		mm.move_mod_to_position(mod_id, from_box, "", zero_level_idx)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_hide_indicator()
		_current_idx = -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_indicator()


# 检测鼠标是否在某个 ModBox 区域上方
func _is_over_mod_box() -> bool:
	var parent = get_parent()
	if not parent:
		return false
	var mouse_pos = get_viewport().get_mouse_position()
	for child in parent.get_children():
		if child is PanelContainer and child.name == "ModBox":
			var rect = Rect2(child.global_position, child.size)
			if rect.has_point(mouse_pos):
				return true
	return false


# ============================================================
# 插入索引计算
# ============================================================

func _calc_index_from_mouse() -> int:
	var parent = get_parent()
	if not parent:
		return 0

	var mouse_y_in_parent = get_global_mouse_position().y - parent.global_position.y
	var cum_h: float = 0.0
	var item_idx := 0

	for child in parent.get_children():
		if child == self:
			continue
		if child is PanelContainer:
			continue
		if child.name.begins_with("HSeparator"):
			continue

		var child_h = child.size.y if child is Control else 0.0
		if mouse_y_in_parent < cum_h + child_h:
			var mid_y = cum_h + child_h * 0.5
			return item_idx if mouse_y_in_parent < mid_y else item_idx + 1
		cum_h += child_h
		item_idx += 1

	# 鼠标在末尾之后：插到末尾
	return _count_mod_slots(parent)


func _count_mod_slots(parent: Control) -> int:
	var count := 0
	for child in parent.get_children():
		if child == self:
			continue
		if child is PanelContainer:
			continue
		if child.name.begins_with("HSeparator"):
			continue
		count += 1
	return count


# ============================================================
# 指示线显示
# ============================================================

func _update_indicator() -> void:
	var parent = get_parent()
	if not parent:
		return

	# 鼠标在 ModBox 上时不显示列表级指示线（ModBox 会显示自己的）
	if _is_over_mod_box():
		_hide_indicator()
		return

	var idx = _calc_index_from_mouse()
	if idx == _current_idx:
		return
	_current_idx = idx
	_indicator.visible = true

	var y: float = 0.0
	var item_idx := 0
	for child in parent.get_children():
		if child == self:
			continue
		if child is PanelContainer:
			continue
		if child.name.begins_with("HSeparator"):
			continue
		if item_idx >= idx:
			break
		if child is Control:
			y += child.size.y
		item_idx += 1

	_indicator.position = Vector2(0, y - 1)
	var w = get_parent().size.x if get_parent() and get_parent().size.x > 0 else 600
	_indicator.custom_minimum_size = Vector2(w, 3)


func _hide_indicator() -> void:
	_indicator.visible = false
	_current_idx = -1
