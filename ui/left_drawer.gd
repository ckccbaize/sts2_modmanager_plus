extends CanvasLayer
class_name LeftDrawer

## 左侧抽屉导航面板
## 鼠标靠近左边缘时显示 ToggleButton，点击展开导航栏目

# ============================================================
# 样式常量 (复用 mod_item.gd 配色)
# ============================================================
const COL_ACCENT = Color(0.4, 0.753, 0.976)
const COL_TEXT = Color(0.898, 0.898, 0.898)
const COL_MUTED = Color(0.545, 0.596, 0.627)
const COL_BG = Color(0.082, 0.122, 0.18, 0.95)
const COL_BORDER = Color(0.337, 0.514, 0.675, 0.15)
const COL_HOVER = Color(0.4, 0.753, 0.976, 0.15)

# ============================================================
# 尺寸常量
# ============================================================
const DRAWER_WIDTH = 220.0
const TOGGLE_BTN_SIZE = 36.0
const TOGGLE_DETECT_MARGIN = 80.0
const ANIM_DURATION = 0.25

# ============================================================
# 信号
# ============================================================
signal config_pressed

# ============================================================
# 内部状态
# ============================================================
var _is_open := false
var _is_animating := false
var _toggle_btn: Button
var _drawer_panel: PanelContainer
var _drawer_content: VBoxContainer
var _nav_config_btn: Button
var _mouse_leave_timer: Timer
var _is_hovering_toggle := false

func _ready() -> void:
	layer = 500  # CanvasLayer 层级
	_create_drawer()
	_create_toggle_button()
	_setup_mouse_leave_timer()

	# 调试：打印 ToggleButton 信息
	await get_tree().create_timer(0.5).timeout
	print("[LeftDrawer] === 调试信息 ===")
	if _toggle_btn:
		var rect = _toggle_btn.get_global_rect()
		print("[LeftDrawer] ToggleBtn global pos: ", rect.position)
		print("[LeftDrawer] ToggleBtn size: ", rect.size)
		print("[LeftDrawer] ToggleBtn visible: ", _toggle_btn.visible)
		print("[LeftDrawer] ToggleBtn modulate: ", _toggle_btn.modulate)
	if _drawer_panel:
		var rect = _drawer_panel.get_global_rect()
		print("[LeftDrawer] DrawerPanel global pos: ", rect.position)
		print("[LeftDrawer] DrawerPanel size: ", rect.size)
	print("[LeftDrawer] ================")

func _create_drawer() -> void:
	_drawer_panel = PanelContainer.new()
	_drawer_panel.name = "LeftDrawerPanel"
	_drawer_panel.set_position(Vector2(-DRAWER_WIDTH, 0))
	_drawer_panel.set_size(Vector2(DRAWER_WIDTH, 800))
	_drawer_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_drawer_panel.anchor_bottom = 1.0  # 锚定到底部
	_drawer_panel.z_index = 1000  # 必须在 BrowserHost 之上
	_drawer_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style = StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.border_color = COL_BORDER
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_top_left = 8
	style.corner_radius_bottom_left = 8
	_drawer_panel.add_theme_stylebox_override("panel", style)

	add_child(_drawer_panel)

	# 抽屉内容
	_drawer_content = VBoxContainer.new()
	_drawer_content.name = "DrawerContent"
	_drawer_content.set_anchors_preset(Control.PRESET_FULL_RECT)  # 撑满整个 panel
	_drawer_content.add_theme_constant_override("separation", 6)
	_drawer_panel.add_child(_drawer_content)

	# 导航项 - 配置
	_nav_config_btn = Button.new()
	_nav_config_btn.text = "配置"
	_nav_config_btn.custom_minimum_size = Vector2(DRAWER_WIDTH - 20, 44)
	_nav_config_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nav_config_btn.add_theme_color_override("font_color", COL_TEXT)
	_nav_config_btn.add_theme_color_override("font_hover_color", COL_ACCENT)

	var nav_style = StyleBoxFlat.new()
	nav_style.bg_color = Color(1, 1, 1, 0.0)
	nav_style.bg_color = Color(1, 1, 1, 0.0)
	nav_style.corner_radius_top_left = 6
	nav_style.corner_radius_top_right = 6
	nav_style.corner_radius_bottom_left = 6
	nav_style.corner_radius_bottom_right = 6
	_nav_config_btn.add_theme_stylebox_override("normal", nav_style)
	_nav_config_btn.add_theme_stylebox_override("hover", _make_hover_style())
	_nav_config_btn.add_theme_stylebox_override("pressed", _make_pressed_style())
	_nav_config_btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.add_child(_nav_config_btn)
	_drawer_content.add_child(margin)

	_nav_config_btn.pressed.connect(_on_config_pressed)

func _create_toggle_button() -> void:
	_toggle_btn = Button.new()
	_toggle_btn.name = "ToggleBtn"
	_toggle_btn.set_position(Vector2(0, 300))  # 垂直居中附近
	_toggle_btn.size = Vector2(TOGGLE_BTN_SIZE, 60)
	_toggle_btn.z_index = 1000  # 必须在 BrowserHost 之上
	_toggle_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_toggle_btn.modulate.a = 1.0  # 常驻显示（不隐藏）

	# 箭头图标
	var arrow_lbl = Label.new()
	arrow_lbl.name = "Arrow"
	arrow_lbl.text = ">"
	arrow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arrow_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arrow_lbl.add_theme_color_override("font_color", COL_ACCENT)
	_toggle_btn.add_child(arrow_lbl)

	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.9, 0.2, 0.2, 1.0)  # 红色背景更容易看到
	btn_style.border_color = COL_BORDER
	btn_style.border_width_left = 1
	btn_style.border_width_right = 1
	btn_style.corner_radius_top_left = 0
	btn_style.corner_radius_bottom_left = 0
	btn_style.corner_radius_top_right = 8
	btn_style.corner_radius_bottom_right = 8
	_toggle_btn.add_theme_stylebox_override("normal", btn_style)
	_toggle_btn.add_theme_stylebox_override("hover", _make_toggle_hover_style())

	_toggle_btn.mouse_entered.connect(_on_toggle_mouse_entered)
	_toggle_btn.mouse_exited.connect(_on_toggle_mouse_exited)
	_toggle_btn.pressed.connect(_on_toggle_pressed)

	add_child(_toggle_btn)

func _setup_mouse_leave_timer() -> void:
	_mouse_leave_timer = Timer.new()
	_mouse_leave_timer.wait_time = 0.3
	_mouse_leave_timer.one_shot = true
	_mouse_leave_timer.timeout.connect(_on_mouse_leave_timer)
	add_child(_mouse_leave_timer)

func _make_hover_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = COL_HOVER
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style

func _make_pressed_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.4, 0.753, 0.976, 0.25)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style

func _make_toggle_hover_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.082, 0.122, 0.18, 1.0)
	style.border_color = COL_ACCENT
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_top_left = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	return style

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_x = event.position.x
		var near_left_edge = mouse_x < TOGGLE_DETECT_MARGIN
		var near_toggle = _is_mouse_near_toggle(event.position)

		if near_left_edge or near_toggle:
			_mouse_leave_timer.stop()
		elif not near_toggle and not _is_hovering_toggle:
			pass  # 不再隐藏按钮

func _is_mouse_near_toggle(pos: Vector2) -> bool:
	if not is_instance_valid(_toggle_btn):
		return false
	var rect = _toggle_btn.get_global_rect()
	rect.position.x -= TOGGLE_DETECT_MARGIN * 0.5
	rect.size.x += TOGGLE_DETECT_MARGIN
	return rect.has_point(pos)

func _show_toggle_button() -> void:
	if _toggle_btn.modulate.a >= 1.0:
		return
	var tween = create_tween()
	tween.tween_property(_toggle_btn, "modulate:a", 1.0, ANIM_DURATION * 0.5)

func _hide_toggle_button() -> void:
	if _toggle_btn.modulate.a <= 0.0:
		return
	var tween = create_tween()
	tween.tween_property(_toggle_btn, "modulate:a", 0.0, ANIM_DURATION * 0.5)

func _on_toggle_mouse_entered() -> void:
	_is_hovering_toggle = true
	_mouse_leave_timer.stop()

func _on_toggle_mouse_exited() -> void:
	_is_hovering_toggle = false
	if not _is_open:
		_mouse_leave_timer.start()

func _on_mouse_leave_timer() -> void:
	if not _is_hovering_toggle and not _is_open:
		_hide_toggle_button()

func _on_toggle_pressed() -> void:
	if _is_animating:
		return
	_animate_drawer(not _is_open)

func _animate_drawer(open: bool) -> void:
	_is_animating = true

	var tween = create_tween()
	tween.set_parallel(true)

	if open:
		# 更新箭头方向
		var arrow = _toggle_btn.get_node_or_null("Arrow") as Label
		if arrow:
			arrow.text = "<"
		# 抽屉滑入
		tween.tween_property(_drawer_panel, "position:x", 0.0, ANIM_DURATION) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		# ToggleButton 跟随
		tween.tween_property(_toggle_btn, "position:x", DRAWER_WIDTH, ANIM_DURATION) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	else:
		# 更新箭头方向
		var arrow = _toggle_btn.get_node_or_null("Arrow") as Label
		if arrow:
			arrow.text = ">"
		# 抽屉滑出
		tween.tween_property(_drawer_panel, "position:x", -DRAWER_WIDTH, ANIM_DURATION) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		# ToggleButton 跟随
		tween.tween_property(_toggle_btn, "position:x", 0.0, ANIM_DURATION) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	await tween.finished
	_is_animating = false
	_is_open = open

	if open:
		_show_toggle_button()
	else:
		_hide_toggle_button()

func _on_config_pressed() -> void:
	config_pressed.emit()
	# 收起抽屉
	if _is_open:
		_animate_drawer(false)

func close_drawer() -> void:
	if _is_open:
		_animate_drawer(false)
