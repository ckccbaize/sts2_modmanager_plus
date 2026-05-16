extends PanelContainer
class_name ModBox

# 收纳盒子：可折叠的模组容器
# 由 modmanager.gd 创建和管理

signal box_clicked(box_id: String)
signal box_delete_requested(box_id: String)
signal box_collapse_toggled(box_id: String, collapsed: bool)
signal box_rename_requested(box_id: String, new_name: String)
signal box_color_changed(box_id: String, new_color: Color)
signal mod_dropped_on_box(box_id: String, mod_id: String, index: int)
signal box_move_requested(box_id: String, direction: int)  # direction: -1=up, 1=down

var box_id: String = ""
var box_name: String = ""
var box_color: Color = Color(0.3, 0.62, 1.0, 1.0)
var is_collapsed: bool = false
var mod_ids: Array = []
var mod_manager_ref: Node = null
var _drop_indicator: ColorRect
var _indicator_index: int = -1

# 节点引用（通过 find_child 初始化）
var left_bar: ColorRect
var bg_color: ColorRect
var header: PanelContainer
var header_hbox: HBoxContainer
var drag_handle: Label
var color_dot: ColorRect
var name_label: Label
var count_label: Label
var collapse_btn: Button
var delete_btn: Button
var up_btn: Button
var down_btn: Button
var mod_items_vbox: VBoxContainer


func _ready() -> void:
	# 通过 find_child 查找子节点，避免 @onready 路径解析问题
	# 所有节点都在 Content 下，必须使用递归搜索
	left_bar = find_child("LeftBar", true, false) as ColorRect
	bg_color = find_child("BgColor", true, false) as ColorRect
	header = find_child("Header", true, false) as PanelContainer
	header_hbox = find_child("HeaderHBox", true, false) as HBoxContainer
	drag_handle = find_child("DragHandle", true, false) as Label
	color_dot = find_child("ColorDot", true, false) as ColorRect
	name_label = find_child("NameLabel", true, false) as Label
	count_label = find_child("CountLabel", true, false) as Label
	collapse_btn = find_child("CollapseBtn", true, false) as Button
	delete_btn = find_child("DeleteBtn", true, false) as Button
	up_btn = find_child("UpBtn", true, false) as Button
	down_btn = find_child("DownBtn", true, false) as Button
	mod_items_vbox = find_child("ModItemsVBox", true, false) as VBoxContainer

	_apply_visual_state()

	# 折叠按钮
	if collapse_btn:
		collapse_btn.pressed.connect(_on_collapse_pressed)

	# 删除按钮
	if delete_btn:
		delete_btn.pressed.connect(_on_delete_pressed)

	# 上下排序按钮
	if up_btn:
		up_btn.pressed.connect(_on_up_pressed)
	if down_btn:
		down_btn.pressed.connect(_on_down_pressed)

	# 折叠/展开区域点击（非按钮部分）可以折叠
	if header:
		header.gui_input.connect(_on_header_input)
		# Header 设为 IGNORE，使拖放事件透传到根节点 ModBox 处理
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# BgColor 也设为 IGNORE，让背景区域的拖放事件透传到 ModBox
	if bg_color:
		bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 颜色条点击选择颜色
	if color_dot:
		color_dot.gui_input.connect(_on_color_dot_input)

	# 右键删除盒子
	if header:
		header.gui_input.connect(_on_header_right_click)

	# 双击名称编辑
	if name_label:
		name_label.gui_input.connect(_on_name_label_input)

	# 拖动手柄（通过 ModBox._gui_input 统一处理，无需单独连接）

	# 创建插入位置指示线
	_drop_indicator = ColorRect.new()
	_drop_indicator.name = "DropIndicator"
	_drop_indicator.color = Color(0.3, 0.62, 1.0, 0.9)
	_drop_indicator.custom_minimum_size = Vector2(0, 3)
	_drop_indicator.visible = false
	_drop_indicator.z_index = 100
	_drop_indicator.mouse_filter = Control.MOUSE_FILTER_STOP
	_drop_indicator.gui_input.connect(_on_indicator_input)
	if mod_items_vbox:
		mod_items_vbox.add_child(_drop_indicator)


func setup(p_box_id: String, p_box_name: String, p_box_color: Color, p_collapsed: bool, p_mod_ids: Array, p_mod_manager: Node) -> void:
	box_id = p_box_id
	box_name = p_box_name
	box_color = p_box_color
	is_collapsed = p_collapsed
	mod_ids = p_mod_ids
	mod_manager_ref = p_mod_manager

	print("[ModBox.setup] box_id=%s p_box_color=%s box_color=%s" % [p_box_id, p_box_color, box_color])

	# 通过 find_child 确保节点已找到
	if name_label == null:
		name_label = find_child("NameLabel", false, false) as Label
	if count_label == null:
		count_label = find_child("CountLabel", false, false) as Label

	if name_label:
		name_label.text = box_name
	if count_label:
		count_label.text = "(%d)" % mod_ids.size()

	print("[ModBox.setup] before _apply_visual_state: left_bar=%s color_dot=%s" % [left_bar, color_dot])
	_apply_visual_state()

	# 渲染完毕后再次应用颜色（确保 setup 中的 box_color 已生效）
	_apply_visual_state()
	print("[ModBox.setup] after _apply_visual_state: left_bar.color=%s color_dot.color=%s" % [left_bar.color if left_bar else "null", color_dot.color if color_dot else "null"])


func _apply_visual_state() -> void:
	if left_bar:
		left_bar.color = box_color
	if color_dot:
		color_dot.color = box_color
	if mod_items_vbox:
		mod_items_vbox.visible = not is_collapsed
	if collapse_btn:
		collapse_btn.text = "▶" if is_collapsed else "▼"


func _on_collapse_pressed() -> void:
	is_collapsed = not is_collapsed
	_apply_visual_state()
	box_collapse_toggled.emit(box_id, is_collapsed)


func _on_delete_pressed() -> void:
	box_delete_requested.emit(box_id)


func _on_up_pressed() -> void:
	box_move_requested.emit(box_id, -1)


func _on_down_pressed() -> void:
	box_move_requested.emit(box_id, 1)


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				_start_rename()
			else:
				box_clicked.emit(box_id)


func _on_header_right_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		box_delete_requested.emit(box_id)


func _on_name_label_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		_start_rename()


func _start_rename() -> void:
	if header_hbox == null:
		header_hbox = find_child("HeaderHBox", true, false) as HBoxContainer
	if name_label == null:
		name_label = find_child("NameLabel", true, false) as Label
	if not header_hbox or not name_label:
		return

	var line_edit = LineEdit.new()
	line_edit.text = box_name
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.placeholder_text = "盒子名称"
	line_edit.text_submitted.connect(func(new_text):
		var final_text = new_text.strip_edges()
		if not final_text.is_empty() and final_text != box_name:
			box_name = final_text
			name_label.text = box_name
			box_rename_requested.emit(box_id, final_text)
		else:
			name_label.text = box_name
		line_edit.queue_free()
		header_hbox.remove_child(line_edit)
		header_hbox.add_child(name_label)
		name_label.show()
	)

	header_hbox.remove_child(name_label)
	name_label.hide()
	header_hbox.add_child(line_edit)
	line_edit.grab_focus()
	line_edit.select_all()


func _on_color_dot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_cycle_color()


const PRESET_COLORS = [
	Color(0.3, 0.62, 1.0, 1.0),
	Color(0.3, 0.9, 0.5, 1.0),
	Color(1.0, 0.5, 0.3, 1.0),
	Color(1.0, 0.3, 0.4, 1.0),
	Color(0.9, 0.3, 0.9, 1.0),
	Color(1.0, 0.85, 0.2, 1.0),
	Color(0.4, 0.4, 0.4, 1.0),
	Color(0.2, 0.8, 0.8, 1.0),
]


func _cycle_color() -> void:
	var current_index = PRESET_COLORS.find(box_color)
	var next_index = (current_index + 1) % PRESET_COLORS.size()
	box_color = PRESET_COLORS[next_index]
	_apply_visual_state()
	box_color_changed.emit(box_id, box_color)


func update_count() -> void:
	if count_label:
		count_label.text = "(%d)" % mod_ids.size()


func get_box_id() -> String:
	return box_id


# ============================================================
# 模组拖放支持
# ============================================================

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	if data.get("type") == "mod":
		var idx = _get_drop_index(at_position)
		_show_drop_indicator(idx)
		return true
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	_hide_indicator()
	if data.get("type") == "mod":
		var mod_id = data.get("mod_id", "")
		var from_box = data.get("from_box", "")
		var drop_index = _get_drop_index(at_position)
		mod_dropped_on_box.emit(box_id, mod_id, drop_index)


func _on_indicator_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var local_pos: Vector2 = mouse_pos - global_position
		var drop_idx: int = _calc_drop_index_from_local(local_pos)
		_show_drop_indicator(drop_idx)
	elif event is InputEventMouseButton and not event.pressed:
		_hide_indicator()


func _calc_drop_index_from_local(local_pos: Vector2) -> int:
	return _get_drop_index(local_pos)


func _get_drop_index(at_position: Vector2) -> int:
	if mod_items_vbox == null:
		return 0
	var header_node = find_child("Header", true, false) as Control
	var header_h = header_node.size.y if header_node else 0.0
	var local_y = at_position.y - header_h
	# 鼠标在 Header 下方或第一个 item 之前 → 返回 0
	if local_y < header_h:
		return 0
	var cum_h: float = 0.0
	for i in range(mod_items_vbox.get_child_count()):
		var child = mod_items_vbox.get_child(i)
		if child is Control and child.name != "DropIndicator":
			cum_h += child.size.y
			if local_y < cum_h:
				return i
	return mod_ids.size()




# ============================================================
# 模组在盒子内的拖放指示线
# ============================================================

func _show_drop_indicator(index: int) -> void:
	if _indicator_index == index:
		return
	_indicator_index = index
	if _drop_indicator:
		_drop_indicator.visible = true
	_reposition_indicator(index)


func _reposition_indicator(index: int) -> void:
	if not _drop_indicator or not mod_items_vbox:
		return
	var header_h = 0.0
	var header_node = find_child("Header", true, false) as Control
	if header_node:
		header_h = header_node.size.y
	var y: float = header_h
	for i in range(mini(index, mod_items_vbox.get_child_count())):
		var child = mod_items_vbox.get_child(i)
		if child is Control and child.name != "DropIndicator":
			y += child.size.y
	_drop_indicator.position = Vector2(4, y)
	_drop_indicator.custom_minimum_size = Vector2(maxf(mod_items_vbox.size.x - 8, 0), 3)


func _hide_indicator() -> void:
	_indicator_index = -1
	if _drop_indicator:
		_drop_indicator.visible = false
