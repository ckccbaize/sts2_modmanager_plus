extends PanelContainer

# 存档列表项脚本 (Steam×Windows 11 风格)

# Steam颜色
const COLORS_STEAM = {
	"bg_normal": Color(0.071, 0.09, 0.118, 1),
	"bg_hover": Color(0.106, 0.157, 0.22, 0.8),
	"bg_selected": Color(0.4, 0.753, 0.976, 0.12),
	"text_primary": Color(0.78, 0.835, 0.878),
	"text_secondary": Color(0.65, 0.65, 0.65, 1),
}

# UI节点引用
@onready var bg_color: ColorRect = $BgColor
@onready var hbox: HBoxContainer = $HBox
@onready var lbl_name: Label = $HBox/NameLabel
@onready var lbl_date: Label = $HBox/DateLabel
@onready var lbl_type: Label = $HBox/TypeLabel
@onready var lbl_size: Label = $HBox/SizeLabel

var save_data: Dictionary = {}
var on_select_callback: Callable
var is_selected: bool = false
var _is_mouse_over: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	if bg_color:
		bg_color.color = COLORS_STEAM.bg_normal
		bg_color.visible = true


func _on_mouse_entered() -> void:
	_is_mouse_over = true
	if not is_selected:
		if bg_color:
			bg_color.color = COLORS_STEAM.bg_hover


func _on_mouse_exited() -> void:
	_is_mouse_over = false
	if not is_selected:
		if bg_color:
			bg_color.color = COLORS_STEAM.bg_normal


# 设置存档数据
func setup(data: Dictionary) -> void:
	save_data = data
	print("[save_item.setup] Called with data: ", data)

	# 构建显示名称：账号 - 存档# [模组版]
	var display_name = data.get("full_name", data.get("name", "Unknown"))
	print("[save_item.setup] display_name: ", display_name)
	if lbl_name:
		lbl_name.text = display_name
		print("[save_item.setup] NameLabel set to: ", lbl_name.text)

	if lbl_date:
		lbl_date.text = data.get("date", "Unknown Date")

	if lbl_type:
		# 显示类型：steam/modded + 当前游戏状态
		var save_type = data.get("type", "steam")
		if data.get("has_current_save", false):
			lbl_type.text = save_type + " (有当前游戏)"
		else:
			lbl_type.text = save_type

	if lbl_size:
		lbl_size.text = data.get("size", "0 KB")

	print("[save_item.setup] Complete")


# GUI输入处理（点击选中）
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if on_select_callback:
				on_select_callback.call(save_data)


# 获取存档数据
func get_save_data() -> Dictionary:
	return save_data


# 设置选中状态
func set_selected(selected: bool) -> void:
	is_selected = selected
	if bg_color:
		if selected:
			bg_color.color = COLORS_STEAM.bg_selected
		else:
			if _is_mouse_over:
				bg_color.color = COLORS_STEAM.bg_hover
			else:
				bg_color.color = COLORS_STEAM.bg_normal


# 获取选中状态
func get_selected() -> bool:
	return is_selected
