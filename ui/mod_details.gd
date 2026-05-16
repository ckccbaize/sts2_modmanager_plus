extends PanelContainer

# 模板规范颜色
const COL_ACCENT   = Color(0.4, 0.753, 0.976)    # #66c0f9
const COL_GAMEPLAY = Color(0.957, 0.447, 0.714)  # #f472b6
const COL_TEXT     = Color(0.898, 0.898, 0.898)  # #e5e5e5
const COL_MUTED   = Color(0.545, 0.596, 0.627)   # #8b98a0
const BG_BADGE    = Color(0.165, 0.278, 0.369, 0.6)
const BG_PANEL    = Color(0, 0, 0, 0.2)
const BORDER_COL  = Color(0.337, 0.514, 0.675, 0.15)
const BG_NOTES    = Color(0.165, 0.278, 0.369, 0.15)

# 节点引用
var title_lbl: Label
var version_lbl: Label
var badge_hbox: HBoxContainer
var info_lbl: Label
var desc_lbl: Label
var notes_bg: PanelContainer
var notes_content: Label
var notes_lbl: Label
var btn_enable: Button
var btn_uninstall: Button

# 回调
var on_enable_callback: Callable
var on_uninstall_callback: Callable

var _current_mod: Dictionary = {}


func _ready() -> void:
	# 节点映射（通过路径查找）
	title_lbl    = find_child("TitleLbl", true, false) as Label
	version_lbl  = find_child("VersionLbl", true, false) as Label
	badge_hbox   = find_child("BadgeHBox", true, false) as HBoxContainer
	info_lbl     = find_child("InfoLbl", true, false) as Label
	desc_lbl     = find_child("DescLbl", true, false) as Label
	notes_bg     = find_child("NotesBg", true, false) as PanelContainer
	notes_content= find_child("NotesContent", true, false) as Label
	notes_lbl    = find_child("NotesLbl", true, false) as Label
	btn_enable   = find_child("BtnEnable", true, false) as Button
	btn_uninstall= find_child("BtnUninstall", true, false) as Button

	if btn_enable:
		btn_enable.button_up.connect(_on_enable_pressed)
	if btn_uninstall:
		btn_uninstall.button_up.connect(_on_uninstall_pressed)

	# 初始隐藏备注区
	if notes_bg:
		notes_bg.visible = false


func setup(mod_data: Dictionary, enabled: bool, enable_cb: Callable, uninstall_cb: Callable) -> void:
	_current_mod = mod_data
	on_enable_callback = enable_cb
	on_uninstall_callback = uninstall_cb

	if mod_data.is_empty():
		_clear()
		return

	# 标题
	if title_lbl:
		title_lbl.text = mod_data.get("name", "Unknown")

	# 版本
	if version_lbl:
		version_lbl.text = mod_data.get("version", "v1.0.0")

	# Badge (玩法/外观)
	if badge_hbox:
		for ch in badge_hbox.get_children():
			ch.queue_free()
		var affects = mod_data.get("affects_gameplay", false)
		_add_badge(badge_hbox, "游戏性" if affects else "外观",
			COL_GAMEPLAY if affects else COL_ACCENT)
		_add_badge(badge_hbox, "兼容 v2.0+", COL_ACCENT)

	# 信息
	if info_lbl:
		var author = mod_data.get("author", "Unknown")
		var installed = mod_data.get("installed_time", "Unknown")
		info_lbl.text = "作者: %s\n安装: %s" % [author, installed]

	# 描述
	if desc_lbl:
		desc_lbl.text = mod_data.get("description", "")

	# 备注（notes 字段）
	var notes = mod_data.get("notes", "")
	if notes_bg:
		notes_bg.visible = not notes.is_empty()
		if not notes_bg.get_theme_stylebox("normal"):
			var notes_style = StyleBoxFlat.new()
			notes_style.bg_color = BG_NOTES
			notes_style.corner_radius_top_left = 6
			notes_style.corner_radius_top_right = 6
			notes_style.corner_radius_bottom_left = 6
			notes_style.corner_radius_bottom_right = 6
			notes_style.border_width_left = 1
			notes_style.border_width_right = 1
			notes_style.border_width_top = 1
			notes_style.border_width_bottom = 1
			notes_style.border_color = BORDER_COL
			notes_bg.add_theme_stylebox_override("normal", notes_style)
	if notes_content:
		notes_content.text = notes

	# 备注 Header 样式
	if notes_lbl:
		notes_lbl.add_theme_color_override("font_color", COL_ACCENT)
		notes_lbl.add_theme_font_size_override("font_size", 11)

	# 启用按钮文字
	if btn_enable:
		if enabled:
			btn_enable.text = "停用"
			btn_enable.add_theme_color_override("font_color", COL_MUTED)
		else:
			btn_enable.text = "启用"
			btn_enable.add_theme_color_override("font_color", COL_TEXT)


func _add_badge(parent: HBoxContainer, text: String, col: Color) -> void:
	"""添加带渐变效果的徽章"""
	# 使用 PanelContainer + StyleBoxFlat 创建圆角徽章
	var badge_panel = PanelContainer.new()
	badge_panel.custom_minimum_size = Vector2(0, 24)

	# 模板: background: rgba(color, 0.2), 低透明度
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = Color(col.r, col.g, col.b, 0.2)  # 模板规范透明度
	badge_style.corner_radius_top_left = 4
	badge_style.corner_radius_top_right = 4
	badge_style.corner_radius_bottom_left = 4
	badge_style.corner_radius_bottom_right = 4

	badge_panel.add_theme_stylebox_override("normal", badge_style)

	# 文字标签 (模板: 使用对应颜色，非白色)
	var lbl = Label.new()
	lbl.text = " " + text + " "
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 内边距
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)

	margin.add_child(lbl)
	badge_panel.add_child(margin)
	parent.add_child(badge_panel)


func _on_enable_pressed() -> void:
	if on_enable_callback.is_valid():
		on_enable_callback.call(_current_mod)


func _on_uninstall_pressed() -> void:
	if on_uninstall_callback.is_valid():
		on_uninstall_callback.call(_current_mod)


func _clear() -> void:
	if title_lbl: title_lbl.text = "未选择模组"
	if version_lbl: version_lbl.text = ""
	if info_lbl: info_lbl.text = ""
	if desc_lbl: desc_lbl.text = "点击左侧列表中的模组查看详情"
	if notes_bg: notes_bg.visible = false
	if badge_hbox:
		for ch in badge_hbox.get_children():
			ch.queue_free()
	if btn_enable: btn_enable.text = "启用"
