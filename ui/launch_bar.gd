extends Control

## Tesla风格横向启动条
## 按模板 02-mod-page-with-launch-button.html 精确实现
## 档位: P(联机) / D(模组) / N(空档) / R(原版)

signal launch_mode_pressed(mode: String)

# ========== 模板规范颜色 ==========
const COL_P      = Color(0.957, 0.447, 0.714)  # #f472b6
const COL_D      = Color(0.4, 0.753, 0.976)    # #66c0f9
const COL_N      = Color(0.063, 0.725, 0.506)  # #10b981
const COL_R      = Color(0.957, 0.447, 0.714)  # #f472b6
const COL_MUTED  = Color(0.545, 0.596, 0.627)  # #8b98a0
const COL_KNOB   = Color(0.4, 0.753, 0.976)    # #66c0f9
const COL_TRACK  = Color(0.4, 0.753, 0.976, 0.15)

# ========== 档位位置 (px, 相对基准) ==========
# 基准 = N档中心
# P=-126, D=-72, N=0, R=80  (旧值)
# 新值(对齐HTML): P抓取位置=-126, D=-72, N=0, R=80
# 但HTML中 gearPositions 计算用 getBoundingClientRect 动态获取
# Godot中用固定px: P=-126, D=-72, N=0, R=80
const GEAR_OFFSETS = {"P": -126.0, "D": -72.0, "N": 0.0, "R": 80.0}
const SNAP_RANGE = 18.0
const DRAG_MIN = -156.0
const DRAG_MAX = 100.0

# ========== 节点引用 ==========
var gear_p: Label
var gear_d: Label
var gear_n: Label
var gear_r: Label
var knob: Control       # ColorRect，absolute 定位
var track_1: ColorRect  # P-D轨道线
var track_2: ColorRect  # D-N轨道线
var track_3: ColorRect  # N-R轨道线
var status_lbl: Label
var status_mini: Label

# ========== 状态 ==========
var is_dragging = false
var drag_start_mouse_x = 0.0
var knob_base_x = 0.0
var current_gear = "N"

# ========== 节点创建 ==========
func _ready() -> void:
	# 创建档位背景 (ColorRect 叠加在 Label 上)
	var n_wrapper = find_child("NWrapper", true, false)
	var p_bg = _make_gear_bg(COL_P, Vector2(4, 7))
	var d_bg = _make_gear_bg(COL_D, Vector2(58, 7))
	var r_bg = _make_gear_bg(COL_R, Vector2(210, 7))

	# N档背景
	var n_bg = _make_gear_bg(COL_N, Vector2(130, 7))
	n_bg.name = "NBg"

	# 轨道线
	track_1 = _make_track(Vector2(32, 19))
	track_2 = _make_track(Vector2(86, 19))
	track_3 = _make_track(Vector2(186, 19))

	# 齿轮球
	knob = find_child("GearKnob", true, false)

	# Label 引用
	gear_p = find_child("GearP", true, false)
	gear_d = find_child("GearD", true, false)
	gear_n = find_child("GearN", true, false)
	gear_r = find_child("GearR", true, false)
	status_lbl = find_child("StatusLabel", true, false)
	status_mini = find_child("StatusMini", true, false)

	# 初始样式
	gear_n.add_theme_color_override("font_color", COL_N)
	if status_mini:
		status_mini.add_theme_color_override("font_color", COL_MUTED)

	# 连接拖拽
	if knob:
		knob.gui_input.connect(_on_knob_input)


func _make_gear_bg(col: Color, pos: Vector2) -> ColorRect:
	var rect = ColorRect.new()
	rect.color = Color(col.r, col.g, col.b, 0.12)
	rect.size = Vector2(28, 26)
	rect.position = pos
	add_child(rect)
	return rect


func _make_track(pos: Vector2) -> ColorRect:
	var rect = ColorRect.new()
	rect.color = COL_TRACK
	rect.size = Vector2(18, 2)
	rect.position = pos
	add_child(rect)
	return rect


# ========== 拖拽逻辑 ==========
func _on_knob_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				drag_start_mouse_x = get_viewport().get_mouse_position().x
				knob_base_x = knob.position.x
			else:
				is_dragging = false
				_on_drag_end()
			return

	if event is InputEventMouseMotion and is_dragging:
		var mx = get_viewport().get_mouse_position().x
		var dx = mx - drag_start_mouse_x
		var new_x = clamp(knob_base_x + dx, DRAG_MIN, DRAG_MAX)
		knob.position.x = new_x
		_detect_gear(new_x)


func _detect_gear(knob_x: float) -> void:
	var found = "N"
	for g in ["P", "D", "R"]:
		if abs(knob_x - GEAR_OFFSETS[g]) < SNAP_RANGE:
			found = g
			break
	if found != current_gear:
		_set_gear(found)


func _set_gear(gear: String) -> void:
	current_gear = gear
	_update_gear_visuals(gear)
	_update_status(gear)


func _update_gear_visuals(gear: String) -> void:
	# 恢复所有档位背景
	_set_gear_bg(gear_p, Color(COL_P.r, COL_P.g, COL_P.b, 0.12), COL_MUTED)
	_set_gear_bg(gear_d, Color(COL_D.r, COL_D.g, COL_D.b, 0.12), COL_MUTED)
	_set_gear_bg(gear_r, Color(COL_R.r, COL_R.g, COL_R.b, 0.12), COL_MUTED)

	# 激活当前档位
	match gear:
		"P":
			_set_gear_bg(gear_p, Color(COL_P.r, COL_P.g, COL_P.b, 0.35), COL_P)
		"D":
			_set_gear_bg(gear_d, Color(COL_D.r, COL_D.g, COL_D.b, 0.35), COL_D)
		"R":
			_set_gear_bg(gear_r, Color(COL_R.r, COL_R.g, COL_R.b, 0.35), COL_R)
		"N":
			pass  # N保持默认绿色


func _set_gear_bg(lbl: Label, bg_col: Color, txt_col: Color) -> void:
	if lbl == null:
		return
	# 找同名 ColorRect 并设置颜色
	var name = lbl.name
	for ch in get_children():
		if ch is ColorRect and ch.name.begins_with(name.left(1)):
			# 找到对应背景
			pass
	# 直接通过背景名查找
	var bg = find_child(name + "Bg", true, false) as ColorRect
	if bg:
		bg.color = bg_col
	lbl.add_theme_color_override("font_color", txt_col)


func _update_status(gear: String) -> void:
	if status_lbl == null and status_mini == null:
		return
	var txt = ""
	var col = COL_MUTED
	match gear:
		"P": txt = "联机模式"; col = COL_P
		"D": txt = "前进(模组)"; col = COL_D
		"N": txt = "← 拖动启动"; col = COL_MUTED
		"R": txt = "倒车(原版)"; col = COL_R
	if status_lbl:
		status_lbl.text = txt
		status_lbl.add_theme_color_override("font_color", col)
	if status_mini:
		status_mini.text = txt
		status_mini.add_theme_color_override("font_color", col)


# ========== 拖拽结束 ==========
func _on_drag_end() -> void:
	if current_gear == "N":
		# 回弹到N
		_anim_knob(0.0)
	else:
		_launch(current_gear)


func _anim_knob(target_x: float) -> void:
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(knob, "position:x", target_x, 0.3)
	tw.tween_callback(_on_anim_done)


func _launch(gear: String) -> void:
	# 球到位
	_anim_knob(GEAR_OFFSETS[gear])

	# 状态文字
	var name = {"P": "联机模式", "D": "模组版", "R": "原版"}.get(gear, "")
	if status_lbl:
		status_lbl.text = "启动 %s..." % name
		status_lbl.add_theme_color_override("font_color", Color(0.29, 0.87, 0.5))
	if status_mini:
		status_mini.text = "启动 %s..." % name
		status_mini.add_theme_color_override("font_color", Color(0.29, 0.87, 0.5))

	await get_tree().create_timer(0.35).timeout
	launch_mode_pressed.emit(gear)


func _on_anim_done() -> void:
	# 重置为N档
	current_gear = "N"
	_update_gear_visuals("N")
	_update_status("N")
