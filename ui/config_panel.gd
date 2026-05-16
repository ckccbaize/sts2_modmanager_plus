extends CanvasLayer
class_name ConfigPanel

## 管理器配置面板
## 从右侧展开，包含端口设置和版本检查

# ============================================================
# 样式常量 (复用 mod_item.gd 配色)
# ============================================================
const COL_ACCENT = Color(0.4, 0.753, 0.976)
const COL_TEXT = Color(0.898, 0.898, 0.898)
const COL_MUTED = Color(0.545, 0.596, 0.627)
const COL_BG = Color(0.082, 0.122, 0.18, 0.95)
const COL_BORDER = Color(0.337, 0.514, 0.675, 0.15)
const COL_HOVER = Color(0.4, 0.753, 0.976, 0.15)
const COL_PRESSED = Color(0.4, 0.753, 0.976, 0.25)
const COL_SECTION_BG = Color(0, 0, 0, 0.2)

# ============================================================
# 尺寸常量
# ============================================================
const PANEL_WIDTH = 320.0
const ANIM_DURATION = 0.3

# ============================================================
# 信号
# ============================================================
signal closed

# ============================================================
# 内部状态
# ============================================================
var _is_open := false
var _is_animating := false
var _panel: PanelContainer
var _port_spinbox: SpinBox
var _version_label: Label
var _version_status_label: Label
var _check_btn: Button
var _save_btn: Button

# 引用外部组件（由 modmanager.gd 设置）
var _srv  # LocalServer (RefCounted, not Node)
var _upd  # UpdateChecker (RefCounted, not Node)
var _cfg: ConfigFile

func _ready() -> void:
	_create_panel()

# 设置依赖注入
func setup(local_server, update_checker, config: ConfigFile) -> void:
	_srv = local_server
	_upd = update_checker
	_cfg = config

func _create_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "ConfigPanel"
	_panel.anchors_preset = Control.PRESET_RIGHT_WIDE
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = 0
	_panel.offset_top = 0
	_panel.offset_right = PANEL_WIDTH
	_panel.offset_bottom = 0
	_panel.custom_minimum_size.x = PANEL_WIDTH
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.z_index = 600
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.modulate.a = 0.0  # 初始隐藏

	var style = StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.border_color = COL_BORDER
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_top_left = 8
	style.corner_radius_bottom_left = 8
	_panel.add_theme_stylebox_override("panel", style)

	add_child(_panel)

	# 主容器
	var main_vbox = VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(main_vbox)

	# 标题栏
	var header = _create_header()
	main_vbox.add_child(header)

	# 内容区域（可滚动）
	var scroll = ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = 1  # SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	var content_vbox = VBoxContainer.new()
	content_vbox.name = "ContentVBox"
	content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(content_vbox)

	# 端口设置区
	var port_section = _create_port_section()
	content_vbox.add_child(port_section)

	# 版本信息区
	var version_section = _create_version_section()
	content_vbox.add_child(version_section)

	# 底部保存按钮
	var save_container = _create_save_section()
	main_vbox.add_child(save_container)

func _create_header() -> HBoxContainer:
	var header = HBoxContainer.new()
	header.name = "Header"
	header.custom_minimum_size.y = 50
	header.add_theme_constant_override("separation", 10)

	var title = Label.new()
	title.name = "Title"
	title.text = "管理器配置"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_color_override("font_color", COL_TEXT)
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)

	var close_btn = Button.new()
	close_btn.name = "CloseBtn"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", COL_MUTED)
	close_btn.add_theme_color_override("font_hover_color", COL_TEXT)
	close_btn.text = "X"
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)

	return header

func _create_port_section() -> VBoxContainer:
	var section = VBoxContainer.new()
	section.name = "PortSection"
	section.add_theme_constant_override("separation", 8)

	var label = Label.new()
	label.name = "PortLabel"
	label.text = "服务器端口"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_color_override("font_color", COL_TEXT)
	section.add_child(label)

	var port_row = HBoxContainer.new()
	port_row.name = "PortRow"
	port_row.add_theme_constant_override("separation", 10)

	var port_spinbox = SpinBox.new()
	port_spinbox.name = "PortSpinBox"
	port_spinbox.custom_minimum_size = Vector2(120, 30)
	port_spinbox.min_value = 1024
	port_spinbox.max_value = 65535
	port_spinbox.step = 1
	port_spinbox.value = 8765
	port_spinbox.rounded = true
	port_row.add_child(port_spinbox)
	_port_spinbox = port_spinbox

	var hint = Label.new()
	hint.name = "PortHint"
	hint.text = "修改后需重启服务生效"
	hint.add_theme_color_override("font_color", COL_MUTED)
	hint.add_theme_font_size_override("font_size", 11)
	port_row.add_child(hint)

	section.add_child(port_row)

	return section

func _create_version_section() -> VBoxContainer:
	var section = VBoxContainer.new()
	section.name = "VersionSection"
	section.add_theme_constant_override("separation", 8)

	var label = Label.new()
	label.name = "VersionLabel"
	label.text = "版本信息"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_color_override("font_color", COL_TEXT)
	section.add_child(label)

	var version_row = HBoxContainer.new()
	version_row.name = "VersionRow"
	version_row.add_theme_constant_override("separation", 10)

	var version_lbl = Label.new()
	version_lbl.name = "VersionLbl"
	version_lbl.text = "当前版本: v0.0.0"
	version_lbl.add_theme_color_override("font_color", COL_MUTED)
	version_row.add_child(version_lbl)
	_version_label = version_lbl

	section.add_child(version_row)

	var status_row = HBoxContainer.new()
	status_row.name = "StatusRow"
	status_row.add_theme_constant_override("separation", 10)

	var check_btn = Button.new()
	check_btn.name = "CheckBtn"
	check_btn.custom_minimum_size = Vector2(100, 30)
	check_btn.text = "检查更新"
	check_btn.add_theme_color_override("font_color", COL_TEXT)
	check_btn.add_theme_stylebox_override("normal", _make_btn_style())
	check_btn.add_theme_stylebox_override("hover", _make_btn_hover_style())
	check_btn.add_theme_stylebox_override("pressed", _make_btn_pressed_style())
	check_btn.pressed.connect(_on_check_update_pressed)
	status_row.add_child(check_btn)
	_check_btn = check_btn

	var status_lbl = Label.new()
	status_lbl.name = "StatusLbl"
	status_lbl.text = ""
	status_lbl.add_theme_color_override("font_color", COL_MUTED)
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_row.add_child(status_lbl)
	_version_status_label = status_lbl

	section.add_child(status_row)

	return section

func _create_save_section() -> MarginContainer:
	var margin = MarginContainer.new()
	margin.name = "SaveMargin"
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)

	var save_btn = Button.new()
	save_btn.name = "SaveBtn"
	save_btn.text = "保存设置"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.custom_minimum_size = Vector2(0, 40)
	save_btn.add_theme_color_override("font_color", COL_TEXT)
	save_btn.add_theme_stylebox_override("normal", _make_primary_btn_style())
	save_btn.add_theme_stylebox_override("hover", _make_primary_btn_hover_style())
	save_btn.add_theme_stylebox_override("pressed", _make_btn_pressed_style())
	save_btn.pressed.connect(_on_save_pressed)
	margin.add_child(save_btn)
	_save_btn = save_btn

	return margin

func _make_btn_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.165, 0.278, 0.369, 0.6)
	style.border_color = COL_BORDER
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style

func _make_btn_hover_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.165, 0.278, 0.369, 0.8)
	style.border_color = COL_ACCENT
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style

func _make_btn_pressed_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = COL_PRESSED
	style.border_color = COL_ACCENT
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style

func _make_primary_btn_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = COL_ACCENT
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style

func _make_primary_btn_hover_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.4, 0.753, 0.976, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style

func _refresh_ui() -> void:
	if _srv == null:
		return

	var current_port = _srv.get_port()
	if is_instance_valid(_port_spinbox):
		_port_spinbox.value = current_port

	# 读取当前版本
	if _cfg != null:
		var ver = _cfg.get_value("current_version", "version", "v0.0.0")
		if is_instance_valid(_version_label):
			_version_label.text = "当前版本: " + ver
	elif is_instance_valid(_version_label):
		_version_label.text = "当前版本: v0.0.0"

func show_panel() -> void:
	if _is_open or _is_animating:
		return
	_is_open = true
	_is_animating = true
	_refresh_ui()

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 1.0, ANIM_DURATION * 0.5)
	tween.tween_property(_panel, "offset_left", -PANEL_WIDTH, ANIM_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	await tween.finished
	_is_animating = false

func hide_panel() -> void:
	if not _is_open or _is_animating:
		return
	_is_open = false
	_is_animating = true

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 0.0, ANIM_DURATION * 0.5)
	tween.tween_property(_panel, "offset_left", 0.0, ANIM_DURATION) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	await tween.finished
	_is_animating = false

func _on_close_pressed() -> void:
	hide_panel()
	closed.emit()

func _on_save_pressed() -> void:
	if _srv == null or _cfg == null:
		return

	var new_port = int(_port_spinbox.value)
	_srv.set_port(new_port)

	# 保存到 config.cfg
	var cfg_path = _cfg.get_value("config_path", "path", "user://config.cfg")
	_cfg.set_value("server", "port", new_port)
	_cfg.save(cfg_path)

	_version_status_label.text = "设置已保存"
	await get_tree().create_timer(1.5).timeout
	_version_status_label.text = ""

func _on_check_update_pressed() -> void:
	if _upd == null:
		return

	_version_status_label.text = "检查中..."
	_check_btn.disabled = true

	_upd.set_callbacks(_on_version_checked)
	_upd.check_for_updates(false)

func _on_version_checked(result: Dictionary) -> void:
	_check_btn.disabled = false

	if not result.get("success", false):
		_version_status_label.text = result.get("error", "检查失败")
		return

	if result.get("has_update", false):
		var data = result.get("data", {})
		var new_ver = data.get("version", "未知")
		_version_status_label.text = "发现新版本: " + new_ver
		_version_status_label.add_theme_color_override("font_color", COL_ACCENT)
	else:
		_version_status_label.text = "已是最新版本"
		_version_status_label.add_theme_color_override("font_color", COL_MUTED)

	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(_version_status_label):
		_version_status_label.text = ""
		_version_status_label.add_theme_color_override("font_color", COL_MUTED)
