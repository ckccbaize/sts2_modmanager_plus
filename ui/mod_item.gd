extends Control
class_name ModItem

# ============================================================
# 模板规范颜色 (Steam×Windows 11)
# ============================================================
const COL_BG_NORMAL    = Color(1, 1, 1, 0.03)
const COL_BG_HOVER    = Color(1, 1, 1, 0.06)
const COL_BG_SELECTED = Color(0.4, 0.753, 0.976, 0.15)
const COL_ACCENT      = Color(0.4, 0.753, 0.976)
const COL_TEXT        = Color(0.898, 0.898, 0.898)
const COL_MUTED       = Color(0.545, 0.596, 0.627)
# 图标渐变色 (模板: linear-gradient(135deg, #color1, #color2))
# 使用渐变的起始色作为ColorRect颜色，通过modulate叠加实现渐变效果
const ICON_GAMEPLAY   = Color(0.957, 0.447, 0.714)   # #f472b6 (gameplay主色)
const ICON_GAMEPLAY_DARK = Color(0.745, 0.094, 0.365) # #be185d
const ICON_COSMETIC   = Color(0.063, 0.725, 0.506)   # #10b981
const ICON_COSMETIC_DARK = Color(0.016, 0.471, 0.341) # #047857
const ICON_DEFAULT    = Color(0.4, 0.753, 0.976)      # #66c0f9
const ICON_DEFAULT_DARK = Color(0.106, 0.337, 0.478)  # #1b567a

# ============================================================
# 节点引用
# ============================================================
var bg: PanelContainer
var icon_bg: ColorRect
var icon_lbl: Label
var name_lbl: Label
var author_lbl: Label
var toggle_btn: TextureButton
var toggle_knob: PanelContainer

# ============================================================
# 状态
# ============================================================
var mod_data: Dictionary = {}
var is_selected: bool = false
var is_hovered: bool = false
var is_toggled_on: bool = false
var multi_select_mode: bool = false
var box_id: String = ""

var on_toggled_callback: Callable
var on_selected_callback: Callable
var on_batch_toggle_callback: Callable


func _ready() -> void:
	pass  # _build_visual 由 _make_mod_item_row 在入树后显式调用


func _build_visual() -> void:
	# 根节点：填充宽度，最小高度64px（模板: padding上下12 + 内容40）
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size.y = 64

	# ---- PanelContainer 作为根背景（支持圆角/边框样式）----
	bg = PanelContainer.new()
	bg.name = "Bg"
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.size_flags_vertical = Control.SIZE_FILL
	bg.add_theme_stylebox_override("normal", _make_bg_style(COL_BG_NORMAL))
	bg.add_theme_stylebox_override("hover", _make_bg_style(COL_BG_HOVER))
	add_child(bg)

	# ---- MarginContainer: 左右14px内边距 ----
	var margin = MarginContainer.new()
	margin.name = "ItemMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_FILL
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	bg.add_child(margin)

	# ---- HBox ----
	var hbox = HBoxContainer.new()
	hbox.name = "HBox"
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	# ---- 图标 (40×40, 圆角6px) ----
	var icon_panel = PanelContainer.new()
	icon_panel.name = "IconPanel"
	icon_panel.custom_minimum_size = Vector2(40, 40)
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = ICON_DEFAULT
	icon_style.corner_radius_top_left = 6
	icon_style.corner_radius_top_right = 6
	icon_style.corner_radius_bottom_left = 6
	icon_style.corner_radius_bottom_right = 6
	icon_panel.add_theme_stylebox_override("normal", icon_style)
	hbox.add_child(icon_panel)

	icon_bg = ColorRect.new()
	icon_bg.name = "IconBg"
	icon_bg.custom_minimum_size = Vector2(40, 40)
	icon_bg.color = ICON_DEFAULT
	icon_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_panel.add_child(icon_bg)

	icon_lbl = Label.new()
	icon_lbl.name = "IconLbl"
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_bg.add_child(icon_lbl)

	# ---- 信息区 ----
	var info_vbox = VBoxContainer.new()
	info_vbox.name = "InfoVBox"
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(info_vbox)

	name_lbl = Label.new()
	name_lbl.name = "NameLbl"
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	name_lbl.add_theme_color_override("font_color", COL_TEXT)
	info_vbox.add_child(name_lbl)

	author_lbl = Label.new()
	author_lbl.name = "AuthorLbl"
	author_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	author_lbl.add_theme_color_override("font_color", COL_MUTED)
	info_vbox.add_child(author_lbl)

	# ---- Toggle (36×20, 模板: border-radius 10px) ----
	var toggle_container = Control.new()
	toggle_container.name = "ToggleContainer"
	toggle_container.custom_minimum_size = Vector2(36, 20)
	toggle_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(toggle_container)

	# Toggle 背景轨道 (PanelContainer, 圆角10px)
	var toggle_track = PanelContainer.new()
	toggle_track.name = "ToggleTrack"
	toggle_track.custom_minimum_size = Vector2(36, 20)
	toggle_track.anchors_preset = Control.PRESET_CENTER
	toggle_track.anchor_left = 0.5
	toggle_track.anchor_top = 0.5
	toggle_track.anchor_right = 0.5
	toggle_track.anchor_bottom = 0.5
	toggle_track.offset_left = -18.0
	toggle_track.offset_top = -10.0
	toggle_track.offset_right = 18.0
	toggle_track.offset_bottom = 10.0
	var track_style = StyleBoxFlat.new()
	track_style.bg_color = Color(0.165, 0.278, 0.369, 0.8)  # rgba(42,71,94,0.8)
	track_style.corner_radius_top_left = 10
	track_style.corner_radius_top_right = 10
	track_style.corner_radius_bottom_left = 10
	track_style.corner_radius_bottom_right = 10
	toggle_track.add_theme_stylebox_override("normal", track_style)
	toggle_container.add_child(toggle_track)

	# 使用 TextureButton 作为点击区域（透明）
	toggle_btn = TextureButton.new()
	toggle_btn.name = "ToggleBtn"
	toggle_btn.toggle_mode = true
	toggle_btn.custom_minimum_size = Vector2(36, 20)
	toggle_btn.anchors_preset = Control.PRESET_FULL_RECT
	toggle_btn.toggled.connect(_on_toggle_toggled)
	toggle_track.add_child(toggle_btn)

	# 圆点 (16×16, 白色, 圆角8px)
	toggle_knob = PanelContainer.new()
	toggle_knob.name = "ToggleKnob"
	toggle_knob.custom_minimum_size = Vector2(16, 16)
	var knob_style = StyleBoxFlat.new()
	knob_style.bg_color = Color.WHITE
	knob_style.corner_radius_top_left = 8
	knob_style.corner_radius_top_right = 8
	knob_style.corner_radius_bottom_left = 8
	knob_style.corner_radius_bottom_right = 8
	toggle_knob.add_theme_stylebox_override("normal", knob_style)
	toggle_knob.anchors_preset = Control.PRESET_LEFT_WIDE
	toggle_knob.offset_top = 2.0
	toggle_knob.offset_bottom = -2.0
	toggle_knob.offset_left = 2.0
	toggle_knob.offset_right = 18.0
	toggle_btn.add_child(toggle_knob)

	# 存储track引用用于_update_toggle_visual
	toggle_btn.set_meta("track", toggle_track)
	_update_toggle_visual(false)

	# ---- 事件 ----
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)


func _make_bg_style(color: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	return s


func _on_mouse_entered() -> void:
	if not is_selected:
		bg.add_theme_stylebox_override("normal", _make_bg_style(COL_BG_HOVER))


func _on_mouse_exited() -> void:
	if not is_selected:
		bg.add_theme_stylebox_override("normal", _make_bg_style(COL_BG_NORMAL))


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if on_selected_callback:
				if multi_select_mode:
					is_selected = not is_selected
					_update_selection_style()
					on_selected_callback.call(mod_data, is_selected)
				else:
					is_selected = true
					_update_selection_style()
					on_selected_callback.call(mod_data)


func _update_selection_style() -> void:
	if is_selected:
		# 模板: background: linear-gradient(90deg, rgba(102,192,249,0.15), transparent)
		#        border: 1px solid rgba(102,192,249,0.3)
		# 用左侧强调色背景 + 四边边框模拟
		var selected_style = StyleBoxFlat.new()
		selected_style.bg_color = Color(0.4, 0.753, 0.976, 0.12)
		selected_style.corner_radius_top_left = 6
		selected_style.corner_radius_top_right = 6
		selected_style.corner_radius_bottom_left = 6
		selected_style.corner_radius_bottom_right = 6
		selected_style.border_width_left = 1
		selected_style.border_width_right = 1
		selected_style.border_width_top = 1
		selected_style.border_width_bottom = 1
		selected_style.border_color = Color(0.4, 0.753, 0.976, 0.3)
		bg.add_theme_stylebox_override("normal", selected_style)
	else:
		bg.add_theme_stylebox_override("normal", _make_bg_style(COL_BG_NORMAL))


func _on_toggle_toggled(toggled_on: bool) -> void:
	is_toggled_on = toggled_on
	_update_toggle_visual(toggled_on)
	if multi_select_mode and on_batch_toggle_callback:
		on_batch_toggle_callback.call(mod_data, toggled_on)
	elif on_toggled_callback:
		on_toggled_callback.call(mod_data, toggled_on)


func _update_toggle_visual(on: bool) -> void:
	if toggle_btn == null or toggle_knob == null:
		return
	# 更新轨道背景色
	var track = toggle_btn.get_meta("track", null)
	if track and track is PanelContainer:
		var track_style = StyleBoxFlat.new()
		if on:
			track_style.bg_color = COL_ACCENT  # #66c0f9
		else:
			track_style.bg_color = Color(0.165, 0.278, 0.369, 0.8)  # rgba(42,71,94,0.8)
		track_style.corner_radius_top_left = 10
		track_style.corner_radius_top_right = 10
		track_style.corner_radius_bottom_left = 10
		track_style.corner_radius_bottom_right = 10
		track.add_theme_stylebox_override("normal", track_style)
	# 移动圆点
	if on:
		toggle_knob.offset_left = 18.0
		toggle_knob.offset_right = -2.0
	else:
		toggle_knob.offset_left = 2.0
		toggle_knob.offset_right = 18.0


# ============================================================
# 公开 API
# ============================================================
func setup(data: Dictionary, enabled: bool = false) -> void:
	mod_data = data
	is_toggled_on = enabled
	_update_toggle_visual(enabled)

	name_lbl.text = data.get("name", "Unknown")
	var author = data.get("author", "Unknown")
	var version = data.get("version", "v1.0")
	author_lbl.text = "%s • %s" % [author, version]

	var icon_char = "🎴"
	if data.get("has_pck", false):
		icon_char = "📦"
	icon_lbl.text = icon_char

	var icon_color = ICON_DEFAULT
	if data.get("affects_gameplay", false):
		icon_color = ICON_GAMEPLAY
	elif data.get("icon", "") == "cosmetic":
		icon_color = ICON_COSMETIC
	icon_bg.color = icon_color

	# 更新图标面板背景色
	var icon_panel = icon_bg.get_parent()
	if icon_panel is PanelContainer:
		var style = icon_panel.get_theme_stylebox("normal")
		if style:
			var new_style = style.duplicate()
			new_style.bg_color = icon_color
			icon_panel.add_theme_stylebox_override("normal", new_style)

	# 添加图标渐变叠加效果
	_update_icon_border(icon_bg, icon_color)


func _update_icon_border(icon: ColorRect, col: Color) -> void:
	"""为图标添加渐变叠加效果（模板: linear-gradient(135deg, color, dark_color)）"""
	# 移除旧的叠加层节点
	if icon.has_node("IconOverlay"):
		icon.get_node("IconOverlay").queue_free()

	# 创建右下角深色叠加层模拟渐变效果
	var overlay = ColorRect.new()
	overlay.name = "IconOverlay"
	# 使用col对应的深色
	var dark_col = ICON_DEFAULT_DARK
	if col == ICON_GAMEPLAY:
		dark_col = ICON_GAMEPLAY_DARK
	elif col == ICON_COSMETIC:
		dark_col = ICON_COSMETIC_DARK
	overlay.color = Color(dark_col.r, dark_col.g, dark_col.b, 0.4)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.position = Vector2(0, 0)
	icon.add_child(overlay)
	icon.move_child(overlay, 0)  # 移到底层，让基础颜色透出


func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_selection_style()


func update_enabled_status(enabled: bool) -> void:
	is_toggled_on = enabled
	_update_toggle_visual(enabled)


func set_multi_select_mode(enabled: bool) -> void:
	multi_select_mode = enabled


func set_batch_toggle_callback(callback: Callable) -> void:
	on_batch_toggle_callback = callback


# ============================================================
# 拖放
# ============================================================
func _get_drag_data(at_position: Vector2) -> Variant:
	var preview = Control.new()
	preview.custom_minimum_size = Vector2(200, 64)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.106, 0.157, 0.22, 0.95)
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_color = COL_ACCENT
	var ps = PanelContainer.new()
	ps.add_theme_stylebox_override("normal", s)
	var lbl = Label.new()
	lbl.text = mod_data.get("name", "")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ps.add_child(lbl)
	preview.add_child(ps)
	set_drag_preview(preview)
	return {"type": "mod", "mod_id": mod_data.get("id", ""), "from_box": box_id}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type", "") == "mod"


func _drop_data(at_position: Vector2, data: Variant) -> void:
	pass
