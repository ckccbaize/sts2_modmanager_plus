extends VBoxContainer

# 让 ModItemsVBox 接受拖放，委托给父节点 ModBox 处理
# VBoxContainer 默认 _can_drop_data 返回 false，会阻止事件冒泡

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var p = get_parent()
	if p and p.has_method("_can_drop_data"):
		# 将 VBox 局部坐标转换为 ModBox 局部坐标
		# at_position.y = 0 对应 VBox 顶部，需要加上 Header 高度才是 ModBox 局部坐标
		var header_h = 0.0
		var header_node = p.find_child("Header", true, false) as Control
		if header_node:
			header_h = header_node.size.y
		var adjusted_pos = Vector2(at_position.x, at_position.y + header_h)
		return p._can_drop_data(adjusted_pos, data)
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var p = get_parent()
	if p and p.has_method("_drop_data"):
		# 将 VBox 局部坐标转换为 ModBox 局部坐标
		var header_h = 0.0
		var header_node = p.find_child("Header", true, false) as Control
		if header_node:
			header_h = header_node.size.y
		var adjusted_pos = Vector2(at_position.x, at_position.y + header_h)
		p._drop_data(adjusted_pos, data)
