extends Control

# 模组管理器主脚本

# 全局颜色常量 (Steam×Windows 11混合风格)
const COLORS = {
	"bg_deep": Color(0.106, 0.157, 0.22),       # #1b2838
	"bg_light": Color(0.071, 0.09, 0.118),      # #12171e
	"accent": Color(0.4, 0.753, 0.976),        # #66c0f9
	"accent_dark": Color(0.165, 0.278, 0.369),   # #2a475e
	"text_primary": Color(0.78, 0.835, 0.878), # #c7d5e0
	"text_secondary": Color(0.545, 0.596, 0.627), # #8b98a0
	"border": Color(0.337, 0.514, 0.675, 0.3),  # rgba(86,131,172,0.3)
	"hover": Color(0.4, 0.753, 0.976, 0.15),    # rgba(102,192,249,0.15)
}

# 功能颜色
const FUNC_COLORS = {
	"gameplay": Color(0.957, 0.447, 0.714),   # #f472b6
	"cosmetic": Color(0.4, 0.753, 0.976),     # #66c0f9
	"success": Color(0.29, 0.87, 0.5),        # #4ade80
	"warning": Color(1, 0.663, 0.251)        # #ffa940
}

# 字体大小常量
const FONT_SIZES = {
	"title": 24,
	"header": 18,
	"body": 14,
	"caption": 12,
	"small": 10
}

# 间距常量
const SPACING = {
	"large": 20,
	"medium": 16,
	"small": 12,
	"tiny": 8
}

# DPI 缩放
const DPI_SCALE_MIN: float = 0.8
const DPI_SCALE_MAX: float = 2.0
const DPI_SCALE_STEP: float = 0.05
var dpi_scale: float = 1.0  # 当前缩放因子

# 拖放处理（用于Godot内部拖放）
func _get_drag_data(at_position: Vector2) -> Variant:
	return null

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# 接受外部文件拖放
	if typeof(data) == TYPE_DICTIONARY and data.has("files"):
		var files = data["files"]
		if files.size() > 0:
			var file_path = str(files[0])
			return file_path.to_lower().ends_with(".zip")
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if typeof(data) == TYPE_DICTIONARY and data.has("files"):
		var files = data["files"]
		for file_path in files:
			if str(file_path).to_lower().ends_with(".zip"):
				install_mod_from_path(str(file_path))

# 连接窗口的文件拖放信号
func _on_window_files_dropped(files: PackedStringArray) -> void:
	print("=== 拖放文件检测到 ===")
	print("=== 文件列表:", files)

	# 过滤出ZIP文件
	var zip_files = []
	for file_path in files:
		if str(file_path).to_lower().ends_with(".zip"):
			zip_files.append(file_path)

	if zip_files.size() == 0:
		return

	# 判断当前标签页
	var current_tab = 0
	var tc = find_child_node(self, "TabContainer")
	if tc:
		current_tab = tc.current_tab
		print("=== 当前标签页:", current_tab)

	if current_tab == 2:  # 存档管理页面
		# 处理存档导入
		_handle_save_drop(zip_files)
	elif current_tab == 1:  # 整合包页面
		# 处理整合包导入
		_handle_bundle_drop(zip_files)
	else:
		# 处理模组导入（原有逻辑）
		_handle_mod_drop(zip_files)


# 窗口大小改变时保存配置
func _on_window_size_changed() -> void:
	var window = get_window()
	var mode = window.mode
	# 只在非最大化状态下保存具体尺寸
	if mode != Window.MODE_MAXIMIZED:
		var size = window.get_size()
		config.set_value("window", "width", size.x)
		config.set_value("window", "height", size.y)
	# 保存最大化状态
	config.set_value("window", "maximized", mode == Window.MODE_MAXIMIZED)
	config.save("user://config.cfg")


# 获取pack_mods目录路径
func _get_new_package_dir() -> String:
	# 使用 Engine.is_editor_hint() 和项目路径判断是否在编辑器中运行
	var exe_path = OS.get_executable_path()
	var project_dir = get_base_path()

	# 检查exe路径是否在项目目录或其父目录中（编辑器模式特征）
	# Godot编辑器运行时，exe在Godot安装目录，项目在另一个位置
	var is_editor = false

	# 方法1: 如果exe路径包含Godot但项目路径不包含Godot，则认为是编辑器模式
	if "Godot" in exe_path.get_file() and not "Godot" in project_dir:
		is_editor = true

	# 方法2: 检查is_editor_hint
	if Engine.is_editor_hint():
		is_editor = true

	if is_editor:
		# 编辑器模式 - 使用项目根目录
		return project_dir + "/pack_mods"
	else:
		# 导出后模式 - 使用exe旁边
		return exe_path.get_base_dir() + "/pack_mods"


# 兼容旧名称
func _get_newpackage_dir() -> String:
	return _get_new_package_dir()


# 加载JSON文件
func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		return {}

	return json.data


# 保存JSON文件
func _save_bundle_json(bundle_id: String, data: Dictionary) -> bool:
	var package_dir = _get_newpackage_dir()
	if package_dir.is_empty():
		return false

	DirAccess.make_dir_recursive_absolute(package_dir + "/" + bundle_id)

	var json_path = package_dir + "/" + bundle_id + "/bundle.json"
	var json = JSON.new()
	var json_string = json.stringify(data, "\t")
	var file = FileAccess.open(json_path, FileAccess.WRITE)
	if not file:
		return false

	file.store_string(json_string)
	file.close()
	return true


# 保存bundle数据到配置
func _save_bundle_data() -> void:
	config.set_value("bundles", "active_bundle", active_bundle)

	# 为当前选中的整合包保存预设
	if not selected_bundle_id.is_empty():
		var bundle_selected_presets = config.get_value("bundles", "bundle_selected_presets", {})
		bundle_selected_presets[selected_bundle_id] = selected_bundle_preset
		config.set_value("bundles", "bundle_selected_presets", bundle_selected_presets)

	# 加载全局的选中预设
	selected_bundle_preset = config.get_value("bundles", "selected_preset", "")

	# 保存启用前的状态，供重启后恢复使用
	if not active_bundle.is_empty():
		var previous_state = {
			"enabled_mods": previous_enabled_mods,
			"tag_data": previous_tag_data
		}
		var bundle_previous_state = config.get_value("bundles", "bundle_previous_state", {})
		bundle_previous_state[active_bundle] = previous_state
		config.set_value("bundles", "bundle_previous_state", bundle_previous_state)

	config.save(config_path)


# 清理文件夹名称，移除或替换不允许的字符
func _sanitize_folder_name(name: String) -> String:
	var result = name
	# 替换Windows不允许的字符
	var invalid_chars = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]
	for char in invalid_chars:
		result = result.replace(char, "_")
	# 移除前后空格和点
	result = result.strip_edges().trim_suffix(".")
	# 如果结果为空，使用默认名称
	if result.is_empty():
		result = "bundle_" + str(Time.get_unix_time_from_system())
	return result


# 比较版本号
func _compare_versions(local: String, remote: String) -> int:
	var local_ver = local.lstrip("v")
	var remote_ver = remote.lstrip("v")

	var local_parts = local_ver.split(".")
	var remote_parts = remote_ver.split(".")

	var max_parts = max(local_parts.size(), remote_parts.size())
	for i in range(max_parts):
		var l = 0
		var r = 0
		if i < local_parts.size():
			l = local_parts[i].to_int()
		if i < remote_parts.size():
			r = remote_parts[i].to_int()

		if r > l:
			return 1
		elif r < l:
			return -1

	return 0


# 处理模组拖入
func _handle_mod_drop(zip_files: Array) -> void:
	var existing_mod_ids = {}
	for mod in mods:
		if mod.has("id"):
			existing_mod_ids[mod["id"]] = true

	# 显示加载动画并记录开始时间
	var start_time = Time.get_ticks_msec()
	_show_loading("正在安装模组...")

	# 等待一帧让UI更新显示
	await get_tree().process_frame
	await get_tree().process_frame

	# 安装所有ZIP文件
	var total_installed = 0
	var installed_mod_names = []
	var failed_mod_names = []
	var error_messages = []
	for file_path in zip_files:
		var file_name = str(file_path).get_file()
		var result = ModUtils.install_mod(str(file_path), "", "", mod_required_fields)

		# 处理失败的模组信息（无论success是否为true）
		var failed_mods = result.get("failed_mods", [])
		for failed_mod in failed_mods:
			var mod_name = failed_mod.get("name", "未知")
			var reason = failed_mod.get("reason", "缺少必要字段")
			failed_mod_names.append(mod_name + " (" + reason + ")")

		if result.success:
			total_installed += result.get("installed_count", 0)
			# 获取安装的模组名称
			var installed_mods = result.get("installed_mods", [])
			for mod_info in installed_mods:
				if mod_info.has("name") and mod_info["name"] != "":
					installed_mod_names.append(mod_info["name"])
				else:
					installed_mod_names.append(file_name.get_basename())

			# 如果没有返回模组名称，使用文件名前缀
			if installed_mods.is_empty():
				installed_mod_names.append(file_name.get_basename())
		else:
			# 记录失败的文件信息
			error_messages.append(file_name + " - " + result.get("message", "解压失败"))

	# 确保加载动画至少显示1.5秒
	var elapsed = Time.get_ticks_msec() - start_time
	if elapsed < 1500:
		await get_tree().create_timer(1.5 - elapsed / 1000.0).timeout

	# 隐藏加载动画
	_hide_loading()

	# 重新加载模组列表
	load_mods()

	# 只获取新安装的模组名称
	var new_mod_names = []
	for mod in mods:
		if mod.has("id") and not existing_mod_ids.has(mod["id"]):
			if mod.has("name"):
				new_mod_names.append(mod["name"])

	# 如果有新安装的模组，使用新模组名称
	if not new_mod_names.is_empty():
		installed_mod_names = new_mod_names

	# 构建通知消息
	var notification_message = ""

	if total_installed > 0 and installed_mod_names.size() > 0:
		# 成功安装的部分
		if total_installed == 1:
			notification_message = "模组安装成功: " + str(installed_mod_names[0])
		else:
			notification_message = "成功安装 %d 个模组:\n" % total_installed
			for i in range(min(installed_mod_names.size(), 5)):
				notification_message += "• " + str(installed_mod_names[i]) + "\n"
			if installed_mod_names.size() > 5:
				notification_message += "...等 %d 个模组" % total_installed
	elif total_installed > 0:
		notification_message = "成功安装 %d 个模组" % total_installed

	# 添加安装失败的模组信息
	if not failed_mod_names.is_empty():
		if notification_message != "":
			notification_message += "\n\n"
		notification_message += "以下模组缺少必要字段未能安装:\n"
		for i in range(failed_mod_names.size()):
			notification_message += "• " + failed_mod_names[i] + "\n"
	if not error_messages.is_empty():
		if notification_message != "":
			notification_message += "\n\n"
		notification_message += "以下文件解压失败:\n"
		# 只显示文件名，不显示详细的错误信息
		for i in range(error_messages.size()):
			var msg = error_messages[i]
			# 提取文件名部分（冒号前的内容）
			var file_name = msg
			if ":" in msg:
				file_name = msg.split(":")[0]
			notification_message += "• " + file_name + "\n"

	# 显示通知
	var is_success = total_installed > 0 and error_messages.is_empty()
	if notification_message != "":
		show_notification(notification_message, is_success)
	elif total_installed == 0:
		show_notification(translate("no_valid_mod_found"), false)


# 处理存档拖入
func _handle_save_drop(zip_files: Array) -> void:
	print("=== 正在导入存档 ===")

	# 显示加载动画
	_show_loading("正在导入存档...")

	# 等待一帧让UI更新显示
	await get_tree().process_frame
	await get_tree().process_frame

	var imported_count = 0
	var failed_count = 0
	var error_messages = []

	for file_path in zip_files:
		var file_name = str(file_path).get_file()
		var result = SaveUtils.import_save(str(file_path), temp_save_path, file_name.get_basename())

		if result.success:
			imported_count += 1
			print("=== 成功导入: ", file_name)
		else:
			failed_count += 1
			error_messages.append(file_name + " - " + result.get("message", "未知错误"))
			print("=== 导入失败: ", file_name, " - ", result.get("message", "未知错误"))

	# 确保加载动画至少显示1秒
	await get_tree().create_timer(1.0).timeout

	# 隐藏加载动画
	_hide_loading()

	# 重新加载存档列表
	load_saves()

	# 构建通知消息
	var notification_message = ""

	if imported_count > 0:
		if imported_count == 1:
			notification_message = "存档导入成功"
		else:
			notification_message = "成功导入 %d 个存档" % imported_count

	if failed_count > 0:
		if notification_message != "":
			notification_message += "\n\n"
		notification_message += "以下存档导入失败:\n"
		for i in range(error_messages.size()):
			notification_message += "• " + error_messages[i] + "\n"

	# 显示通知
	var is_success = imported_count > 0 and failed_count == 0
	if notification_message != "":
		show_notification(notification_message, is_success)
	elif imported_count == 0:
		show_notification(translate("no_valid_save_found"), false)


# UI节点引用
@onready var tab_container: TabContainer
@onready var mod_search: LineEdit
@onready var search_button: Button
@onready var install_mod_button: Button
@onready var uninstall_mod_button: Button
@onready var batch_enable_button: Button
@onready var batch_uninstall_button: Button
@onready var batch_select_button: Button
@onready var refresh_mods_button: Button
@onready var sort_option: OptionButton
@onready var category_filter: OptionButton
@onready var mod_list_container: VBoxContainer
@onready var mod_details_panel: ScrollContainer
@onready var mod_details_name: Label
@onready var mod_details_author: Label
@onready var mod_details_version: Label
@onready var mod_details_source: Label
@onready var mod_details_type: Label
@onready var mod_details_desc: Label
@onready var mod_details_dep: Label

# 模组备注数据
var mod_notes: Dictionary = {}  # {mod_id: note_text}
var mod_notes_file_path: String = ""
var current_mod_data: Dictionary = {}  # 当前选中的模组数据

@onready var mod_note_edit_btn: Button
@onready var mod_note_label: Label
@onready var mod_note_separator: HSeparator
@onready var mod_details_vbox: VBoxContainer

@onready var save_list_container: VBoxContainer
@onready var import_save_button: Button
@onready var export_save_button: Button
@onready var backup_save_button: Button
@onready var restore_save_button: Button
@onready var overwrite_save_button: Button
@onready var save_details_panel: PanelContainer
@onready var save_details_name: Label
@onready var save_details_date: Label
@onready var save_details_size: Label
@onready var save_details_type: Label
@onready var save_profile_selector: OptionButton

# 当前选中的存档信息
var current_save_steam_id: String = ""
var current_save_is_modded: bool = false
var current_save_profiles: Array = []
var current_selected_profile: int = 1
var save_left_panel_collapsed: bool = false
var save_left_panel: Control
var save_collapse_btn: Button
var char_stats_vbox: VBoxContainer

# Settings UI variables (not @onready, initialized manually)
var game_path_edit: LineEdit
var game_path_browse_btn: Button
var game_path_detect_btn: Button
var save_path_edit: LineEdit
var save_path_browse_btn: Button
var save_path_detect_btn: Button
# 云端存档路径变量
var gse_cloud_path_edit: LineEdit
var steam_cloud_path_edit: LineEdit
var gse_cloud_detect_btn: Button
var steam_cloud_detect_btn: Button
var language_option: OptionButton
var dpi_scale_slider: HSlider
var dpi_scale_value_label: Label
var auto_backup_check: CheckBox
var auto_backup_on_startup_check: CheckBox
var auto_backup_max_count_spin: SpinBox
var launch_via_steam_check: CheckBox
var enable_fix_steam_check: CheckBox
var fix_steam_path_edit: LineEdit
var fix_steam_path_browse_btn: Button
var fix_steam_path_detect_btn: Button
var mod_drag_check: CheckBox
var override_order_check: CheckBox
var save_settings_btn: Button
var temp_mods_path_edit: LineEdit
var temp_mods_path_browse_btn: Button
var backup_path_edit: LineEdit
var backup_path_browse_btn: Button
@onready var loading_panel: Panel
@onready var loading_label: Label
@onready var loading_spinner: ProgressBar
@onready var loading_progress: ColorRect

# 设置拖放接受
# 设置拖放接受 - 由ModTab处理
# func _get_drag_control_at_position(pos: Vector2) -> Control:
# 	return self

# func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
# 	print("=== _can_drop_data ===", data, " type:", typeof(data))
# 	return true

# func _drop_data(at_position: Vector2, data: Variant) -> void:
# 	print("=== _drop_data ===", data, " type:", typeof(data))


# 安装模组（从文件路径）
func install_mod_from_path(zip_path: String) -> void:
	# 保存当前已存在的模组ID
	var existing_mod_ids = {}
	for mod in mods:
		if mod.has("id"):
			existing_mod_ids[mod["id"]] = true

	# 显示加载动画并记录开始时间
	var start_time = Time.get_ticks_msec()
	_show_loading(translate("installing_mod"))

	# 等待一帧让UI更新显示
	await get_tree().process_frame
	await get_tree().process_frame

	# 调用ModUtils安装模组（使用用户配置的必需字段）
	var result = ModUtils.install_mod(zip_path, "", "", mod_required_fields)

	# 确保加载动画至少显示1.5秒
	var elapsed = Time.get_ticks_msec() - start_time
	if elapsed < 1500:
		await get_tree().create_timer(1.5 - elapsed / 1000.0).timeout

	# 隐藏加载动画
	_hide_loading()

	if result.success:
		# 重新加载模组列表
		load_mods()

		# 检查是否成功安装了任何模组
		var installed_count = result.get("installed_count", 0)
		if installed_count == 0:
			# 获取文件名作为失败信息
			var file_name = str(zip_path).get_file()
			show_notification(translate("file_install_failed").format({"file": file_name}), false)
			return

		# 获取新安装的模组名称
		var new_mod_names = []
		for mod in mods:
			if mod.has("id") and not existing_mod_ids.has(mod["id"]):
				if mod.has("name"):
					new_mod_names.append(mod["name"])

		# 如果没有新模组，使用result中的信息或文件名
		if new_mod_names.is_empty():
			var installed_mods = result.get("installed_mods", [])
			if not installed_mods.is_empty():
				for mod_info in installed_mods:
					if mod_info.has("name") and mod_info["name"] != "":
						new_mod_names.append(mod_info["name"])
			else:
				# 使用文件名
				new_mod_names.append(str(zip_path).get_file().get_basename())

		# 获取失败的模组名称和原因
		var failed_mod_names = []
		var failed_mods = result.get("failed_mods", [])
		for failed_mod in failed_mods:
			var mod_name = failed_mod.get("name", "未知")
			var reason = failed_mod.get("reason", "缺少必要字段")
			failed_mod_names.append(mod_name + " (" + reason + ")")

		# 构建通知消息
		var notification_message = ""
		if installed_count == 1:
			notification_message = "模组安装成功: " + str(new_mod_names[0])
		else:
			notification_message = "成功安装 %d 个模组:\n" % installed_count
			for i in range(min(new_mod_names.size(), 5)):
				notification_message += "• " + str(new_mod_names[i]) + "\n"
			if new_mod_names.size() > 5:
				notification_message += "...等 %d 个模组" % installed_count

		# 添加失败的模组信息
		if not failed_mod_names.is_empty():
			notification_message += "\n\n以下模组缺少必要字段未能安装:\n"
			for i in range(failed_mod_names.size()):
				notification_message += "• " + failed_mod_names[i] + "\n"

		# 显示通知
		var is_success = failed_mod_names.is_empty()
		show_notification(notification_message, is_success)
	else:
		# 显示错误信息，可能有失败的模组信息
		var error_msg = result.message
		var failed_mods = result.get("failed_mods", [])
		if not failed_mods.is_empty():
			error_msg += "\n\n以下模组缺少必要字段未能安装:\n"
			for failed_mod in failed_mods:
				var mod_name = failed_mod.get("name", "未知")
				var reason = failed_mod.get("reason", "缺少必要字段")
				error_msg += "• " + mod_name + " (" + reason + ")\n"
		show_notification(error_msg, false)

# 显示安装成功通知（通用函数）
func show_install_notification(installed_count: int, mod_names: Array) -> void:
	var message = ""
	if installed_count == 1 and mod_names.size() > 0:
		message = "模组安装成功: " + str(mod_names[0])
	elif installed_count > 1:
		message = "成功安装 %d 个模组:\n" % installed_count
		# 添加所有模组名称
		for i in range(min(mod_names.size(), 5)):
			message += "• " + str(mod_names[i]) + "\n"
		if mod_names.size() > 5:
			message += "...等 %d 个模组" % installed_count
	else:
		message = "模组安装成功"

	show_notification(message, true)

# 显示加载动画（带进度动画）
func _show_loading(message: String = "正在处理...") -> void:
	if loading_panel:
		loading_panel.visible = true
	if loading_label:
		loading_label.text = message

	# 重置进度条
	if loading_progress:
		loading_progress.custom_minimum_size.x = 0

	# 启动进度动画（使用定时器）
	_start_loading_animation()

	# 禁用安装按钮防止重复点击
	if install_mod_button:
		install_mod_button.disabled = true

# 启动加载动画循环
func _start_loading_animation() -> void:
	if not loading_progress:
		return

	# 先停止之前的动画
	if loading_tween and loading_tween.is_valid():
		loading_tween.kill()

	# 创建循环动画：从左到右然后返回
	loading_tween = create_tween()
	loading_tween.set_loops()

	# 第一段：从0到200 (1秒)
	loading_tween.tween_property(loading_progress, "custom_minimum_size:x", 200.0, 0.8).set_trans(Tween.TRANS_SINE)
	# 第二段：从200回到0 (0.2秒)
	loading_tween.tween_property(loading_progress, "custom_minimum_size:x", 0.0, 0.2).set_trans(Tween.TRANS_SINE)

# 停止加载动画
func _stop_loading_animation() -> void:
	# 停止tween
	if loading_tween and loading_tween.is_valid():
		loading_tween.kill()
		loading_tween = null

	# 设置为满格
	if loading_progress:
		loading_progress.custom_minimum_size.x = 200

# 隐藏加载动画（带短暂延迟以显示完成动画）
func _hide_loading(wait_and_show_complete: bool = true) -> void:
	print("[_hide_loading] Called, wait=", wait_and_show_complete, " loading_panel=", loading_panel)
	if loading_panel:
		print("[_hide_loading] Before hide, visible=", loading_panel.visible)
	if wait_and_show_complete:
		# 停止动画并显示满格
		_stop_loading_animation()

		# 显示完成状态，短暂等待
		if loading_label:
			loading_label.text = translate("install_complete")
		await get_tree().create_timer(0.5).timeout

	if loading_panel:
		loading_panel.visible = false
		print("[_hide_loading] After hide, visible=", loading_panel.visible)
	# 重新启用安装按钮
	if install_mod_button:
		install_mod_button.disabled = false

# 模组管理相关
var mods: Array = []  # 所有模组数据
var displayed_mods: Array = []  # 当前显示的模组
var enabled_mods: Dictionary = {}  # 已启用的模组 {id: true/false}
var mod_items: Dictionary = {}  # 模组ID到列表项的映射
var current_sort: String = "name"  # 当前排序方式：name, install_time
var current_search: String = ""  # 当前搜索关键词
var current_category: String = "all"  # 当前分类：all, gameplay, cosmetic
var current_launch_mode: String = "singleplayer"  # 当前启动模式：singleplayer, multiplayer, custom
var selected_mod_id: String = ""  # 当前选中的模组ID

# 下载任务管理
var download_tasks: Dictionary = {}  # download_id -> {mod_name, status, progress, speed, save_path, error}
var download_history: Array = []  # 下载历史记录
var download_tasks_container: VBoxContainer  # 下载任务列表容器
var download_history_container: VBoxContainer  # 下载历史容器
var _download_id_counter: int = 0
var download_history_file: String = ""  # 下载历史文件路径
var _download_progress_timers: Dictionary = {}  # 下载进度监控定时器
var _download_threads: Dictionary = {}  # 下载线程引用 {download_id: Thread}
var _download_processes: Dictionary = {}  # 下载进程PID {download_id: pid}

# 整合包相关
var bundle_data: Dictionary = {}  # bundle_id -> bundle.json数据
var bundle_items: Dictionary = {}  # bundle_id -> UI项
var active_bundle: String = ""  # 当前启用的整合包ID（空=未启用）
var previous_enabled_mods: Dictionary = {}  # 禁用整合包前启用的模组
var previous_tag_data: Dictionary = {}  # 禁用整合包前保存的预设
var _bundle_ui_initialized: bool = false  # UI初始化状态
var bundle_container: GridContainer  # 整合包卡片容器
#var bundle_enable_switch: CheckBox  # 已移除，详情面板不再需要额外的启用开关
var bundles_list: ItemList
var bundle_details_vbox: VBoxContainer
var bundle_mods_list: ItemList
var bundle_info_labels: Dictionary
var selected_bundle_id: String = ""  # 当前选中的整合包ID
var selected_bundle_preset: String = ""  # 当前选中的整合包的预设

# 标签相关
var current_tag: String = "单人模组"  # 当前标签
var tag_data: Dictionary = {}  # 标签数据 {tag_name: [enabled_mod_ids]}
var tag_buttons: Dictionary = {}  # 标签按钮映射 {tag_name: Button}
var tag_container: HBoxContainer = null  # 标签栏容器
var custom_tag_scroll_index: int = -1  # 自定义标签滚轮索引（-1表示显示默认"联机模组"）
const DEFAULT_TAGS = ["单人模组", "联机模组"]  # 默认显示的标签

# 长按删除相关
var longpress_timer: Timer = null  # 长按定时器
var longpress_progress: ProgressBar = null  # 充能条
var longpress_target_tag: String = ""  # 正在长按的标签
var longpress_button: Button = null  # 正在长按的按钮
var selected_save_id: String = ""  # 当前选中的存档ID
var backed_up_saves: Dictionary = {}  # 已备份的存档 {save_id: backup_path}

# 收纳盒子与覆盖顺序（实验性）
var mod_boxes: Array = []     # [{id, name, color, collapsed, mod_ids[]}, ...]
var mod_order_override: Array = []  # 全局模组显示顺序（仅启用覆盖顺序时生效）
var enable_override_order: bool = false    # 覆盖顺序开关（实验性）
var enable_mod_drag: bool = false          # 收纳功能开关（拖动、盒子）
var _manifest_backups: Dictionary = {}     # {mod_id: original_json_content_string}，游戏退出后恢复用
var _staged_mod_order: Array = []  # 临时暂存的顺序（用于拖动时实时更新）
var save_panels: Dictionary = {}  # 存档面板引用 {steam_id: {panel: Control, bg: ColorRect}}
var loading_tween: Tween = null  # 加载动画tween引用

# 存档管理相关
var steam_saves: Array = []  # Steam存档列表
var imported_saves: Array = []  # 导入存档列表
var grouped_saves: Dictionary = {}  # 分组后的存档 { "steam": {}, "modded": {} }

# 配置相关
var config: ConfigFile = ConfigFile.new()  # 配置文件
var current_language: String = "zh_CN"  # 当前语言
var locale_data: Dictionary = {}  # 语言数据
var game_path: String = ""  # 游戏路径
var save_path: String = ""  # 存档路径
var gse_cloud_path: String = ""  # GSE云端存档路径（学习版）
var steam_cloud_path: String = ""  # Steam云端存档路径（正版）
var fix_steam_path: String = "" # 联机补丁路径
var _skip_auto_backup: bool = false  # 跳过自动备份标志
var settings_dirty: bool = false  # 设置是否有未保存的更改

# 教程弹窗状态
var tutorial_panel: Panel = null
var tutorial_current_step: int = 0
var tutorial_steps: Array = ["welcome", "game_path", "mods", "saves", "nexus", "nexus_api_tutorial"]

# 通知相关
var notification_message: String = ""  # 通知消息内容
var notification_click_action: String = ""  # 通知点击后的动作

# 模组JSON必要字段配置
var mod_required_fields: Array = ["id", "name", "author", "description", "version", "has_pck", "has_dll", "affects_gameplay"]  # 默认必要字段
var mod_optional_fields: Array = ["dependencies"]  # 默认可选字段
var mod_required_fields_edit: LineEdit = null  # 已废弃，改用复选框

# 获取应用基础路径（编辑器中为res://，导出后为exe所在目录）
var _base_path: String = ""

# 日志文件路径
var _log_file_path: String = ""

func _init() -> void:
	# 在 _ready 之前初始化日志
	_init_log()

func _init_log() -> void:
	# 获取日志路径 - 优先使用临时目录
	if OS.has_feature("editor"):
		_log_file_path = "res://debug.log"
	else:
		# 尝试使用临时目录，避免闪退时路径问题
		var temp_dir = OS.get_environment("TEMP")
		if temp_dir.is_empty():
			temp_dir = OS.get_environment("TMP")
		if temp_dir.is_empty():
			temp_dir = OS.get_executable_path().get_base_dir()
		_log_file_path = temp_dir + "\\sts2_modmanager.log"

	# 写入启动标记
	_write_log("=== APP START ===")
	_write_log("Executable: " + OS.get_executable_path())
	_write_log("Base dir: " + OS.get_executable_path().get_base_dir())
	_write_log("Log path: " + _log_file_path)

func _write_log(msg: String) -> void:
	var timestamp = Time.get_datetime_string_from_system(false, true)
	var log_line = timestamp + " " + msg
	print(log_line)
	# 写入文件
	if _log_file_path.is_empty():
		return

	# 使用 file_exists 检查文件是否存在
	if not FileAccess.file_exists(_log_file_path):
		# 文件不存在，尝试创建
		var file = FileAccess.open(_log_file_path, FileAccess.WRITE)
		if file:
			file.close()
		else:
			print("[LOG] 无法创建日志文件: ", _log_file_path)
			return

	var file = FileAccess.open(_log_file_path, FileAccess.READ_WRITE)
	if file == null:
		print("[LOG] 无法打开日志文件: ", _log_file_path)
		return
	file.seek_end()
	file.store_line(log_line)
	file.close()

func get_base_path() -> String:
	if _base_path.is_empty():
		# 先初始化目录
		_init_required_directories()

		if OS.has_feature("editor"):
			# 在编辑器中，使用 ProjectSettings 获取项目路径
			_base_path = ProjectSettings.globalize_path("res://")
			# 移除 "res://" 前缀，获得实际文件系统路径
			_base_path = _base_path.replace("res://", "")
			if _base_path.is_empty():
				# 如果失败，使用备选方案 - 尝试从 config_path 获取
				_base_path = config_path.get_base_dir()
				_base_path = _base_path.get_base_dir()
		else:
			# 导出版本使用exe所在目录
			_base_path = OS.get_executable_path().get_base_dir()
		if not _base_path.ends_with("/"):
			_base_path += "/"
	print("[get_base_path] returning: ", _base_path)
	return _base_path

var mod_notes_path: String:
	get: return get_base_path() + "mod_notes.json"

# 初始化必要文件夹（编辑器用项目目录，导出版本用exe所在目录）
func _init_required_directories() -> void:
	# 直接获取路径，不依赖 _base_path
	var fs_base_path: String
	if OS.has_feature("editor"):
		fs_base_path = ProjectSettings.globalize_path("res://").replace("res://", "")
		if fs_base_path.is_empty():
			fs_base_path = config_path.get_base_dir().get_base_dir()
	else:
		fs_base_path = OS.get_executable_path().get_base_dir()

	if not fs_base_path.ends_with("/"):
		fs_base_path += "/"

	print("[_init_required_directories] Starting...")
	print("[_init_required_directories] fs_base_path: ", fs_base_path)
	var dirs_to_create = ["temp_save", "temp_mods", "backups", "test_mods", "mod_backups", "backup_fix_steam"]
	for dir_name in dirs_to_create:
		var dir_path = fs_base_path + dir_name
		print("[_init_required_directories] Checking: ", dir_path)
		if not DirAccess.dir_exists_absolute(dir_path):
			var err = DirAccess.make_dir_recursive_absolute(dir_path)
			if err == OK:
				print("[_init_required_directories] Created: ", dir_path)
			else:
				print("[_init_required_directories] Failed to create: ", dir_path, " error: ", err)
		else:
			print("[_init_required_directories] Already exists: ", dir_path)
	print("[_init_required_directories] Done")

# 配置文件路径
var config_path: String:
	get: return get_base_path() + "config.cfg"

# 动态路径属性
var temp_save_path: String:
	get: return get_base_path() + "temp_save"
	
var temp_mods_path: String:
	get: return get_base_path() + "temp_mods"
	
var backup_path: String:
	get: return get_base_path() + "backups"

# 常量
const MOD_ITEM_SCENE = preload("res://ui/mod_item.tscn")
const MOD_BOX_SCENE = preload("res://ui/mod_box.tscn")
const SORT_OPTIONS = ["name", "安装时间"]  # 排序选项

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("=== _ready 开始 ===")

	# 启用窗口接受文件拖放
	get_window().files_dropped.connect(_on_window_files_dropped)

	# 启用窗口大小调整检测
	get_window().size_changed.connect(_on_window_size_changed)

	# 加载配置
	load_config()

	# 检测并修复 .bak 文件
	var fixed_count = _check_and_fix_bak_files()
	if fixed_count > 0:
		show_notification(translate("bak_files_repaired").format({"count": fixed_count}), true)
	else:
		# 仅在非首次运行时显示"未发现问题"
		if not config.get_value("settings", "first_run", true):
			print("[_ready] No .bak files to repair")

	# 检查是否需要显示教程（首次启动：game_path 未配置）
	if game_path.is_empty():
		print("[_ready] 首次启动，显示教程")
		call_deferred("_show_tutorial_if_needed")

	# 加载语言
	load_locale()
	load_mod_notes()

	# 初始化下载历史文件路径
	download_history_file = get_base_path() + "download_history.json"
	# 加载下载历史
	_load_download_history()

	# 初始化UI
	init_ui()

	# 恢复上次退出的标签页并初始化对应UI
	_restore_last_tab()

	# 初始化本地HTTP服务器（用于浏览器扩展通信）
	_init_local_server()

	# 初始化更新检查器
	_update_checker_init()

	# === 内嵌浏览器集成：隐藏原版 UI，显示 WebView ===
	_hide_legacy_ui_and_show_webview()

	# 延迟检查更新（启动后 2 秒）
	await get_tree().create_timer(2.0).timeout
	_check_for_updates(true)

	# 自动检测路径（如果未配置）
	_auto_detect_paths_on_startup()

	# 延迟加载模组，让界面先显示
	call_deferred("_delayed_load_mods")

	# 延迟加载存档，让界面先显示
	call_deferred("_delayed_load_saves")

	# 注意：Nexus模组页面延迟初始化移到 _on_tab_changed 中，用户首次切换到Nexus标签页时再加载


func _delayed_init_nexus() -> void:
	# 等待界面渲染完成
	await get_tree().create_timer(1.0).timeout
	print("[_delayed_init_nexus] Starting...")
	_init_nexus_mods_ui()
	print("[_delayed_init_nexus] Done")

	# 设置窗口标题（应用名 + 版本）
	var app_version = _read_version_from_file()
	get_tree().root.title = translate("app_name") + " " + app_version


func _delayed_load_mods() -> void:
	# 先让界面渲染
	await get_tree().create_timer(0.1).timeout
	print("[_delayed_load_mods] Starting...")
	load_mods()
	print("[_delayed_load_mods] Done")


func _delayed_load_saves() -> void:
	# 等待模组加载完成
	await get_tree().create_timer(0.5).timeout
	print("[_delayed_load_saves] Starting...")
	load_saves()
	print("[_delayed_load_saves] Done")
	# 注意：自动备份已在load_saves() -> _scan_backup_folders()中触发，无需再次等待


# 初始化更新检查器
func _update_checker_init() -> void:
	print("[_update_checker_init] === START ===")
	update_checker = UpdateChecker.new()
	update_checker.set_urls(update_check_url_gitee, update_check_url_github)

	# 注意：版本同步已在 load_config 中完成，这里直接读取
	config.load(config_path)
	var current_ver = config.get_value("current_version", "version", "v0.0.0")
	print("[_update_checker_init] Read version from config: ", current_ver)
	update_checker.set_current_version(current_ver)

	# 设置回调
	update_checker.set_callbacks(
		_on_update_checked,
		_on_download_progress,
		_on_download_complete,
		_on_download_error
	)

	print("[_update_checker_init] Update checker initialized, current version: ", current_ver)


# 从 version.json 读取版本
func _read_version_from_file() -> String:
	var version = "v0.0.0"
	var exe_dir = OS.get_executable_path().get_base_dir()
	var version_file_path = exe_dir + "/version.json"

	if FileAccess.file_exists(version_file_path):
		var version_file = FileAccess.open(version_file_path, FileAccess.READ)
		if version_file:
			var json_str = version_file.get_as_text()
			version_file.close()
			var json = JSON.new()
			if json.parse(json_str) == OK:
				version = json.data.get("version", "v0.0.0")
	else:
		# 备选：从 res:// 读取（编辑器版本）
		version_file_path = "res://version.json"
		if FileAccess.file_exists(version_file_path):
			var version_file = FileAccess.open(version_file_path, FileAccess.READ)
			if version_file:
				var json_str = version_file.get_as_text()
				version_file.close()
				var json = JSON.new()
				if json.parse(json_str) == OK:
					version = json.data.get("version", "v0.0.0")

	return version


# 同步项目版本到 config.cfg
func _sync_version_to_config() -> void:
	var project_version = _read_version_from_file()
	var config_version = config.get_value("current_version", "version", "")

	# 只有当 project_version 有效且与 config 不同时才同步
	if project_version != "v0.0.0" and not project_version.is_empty() and config_version != project_version:
		config.set_value("current_version", "version", project_version)
		config.save(config_path)
		print("[_sync_version_to_config] Synced version to config: ", project_version)


# 检查更新
func _check_for_updates(auto_check: bool) -> void:
	if update_checker:
		# 从 version.json 读取最新版本
		var latest_version = _read_version_from_file()
		update_checker.set_current_version(latest_version)
		print("[_check_for_updates] Reset current_version to: ", latest_version)
		print("[_check_for_updates] About to check updates, current_version in checker: ", update_checker.current_version)
		update_checker.check_for_updates(auto_check)


# 更新检查完成回调
func _on_update_checked(result: Dictionary) -> void:
	print("[_on_update_checked] Result: ", result)

	if not result.get("success", false):
		# 检查失败，仅在手动检查时提示
		var error_msg = result.get("error", "")
		if error_msg != "":
			show_notification(translate("check_update_failed"), false)
		return

	if result.get("has_update", false):
		# 发现新版本
		pending_update_info = result.get("data", {})
		var new_version = pending_update_info.get("version", "")
		var changelog = pending_update_info.get("changelog", "")
		var current_ver = _read_version_from_file()

		print("[_on_update_checked] Current version: ", current_ver, ", New version: ", new_version)

		# 显示通知气泡
		notification_message = translate("new_version_available").format({"version": new_version})
		notification_click_action = "show_update_dialog"
		show_notification(notification_message, true)
		print("[_on_update_checked] New version available: ", new_version)
	else:
		# 已是最新版本
		var current_ver = _read_version_from_file()
		show_notification(translate("already_latest_version").format({"version": current_ver}), true)
		print("[_on_update_checked] Already at latest version: ", current_ver)


# 下载进度回调
func _on_download_progress(percent: float) -> void:
	var percent_str = str(round(percent * 100))
	notification_message = translate("downloading_update").format({"percent": percent_str})
	# 更新进度显示
	_update_download_progress_ui(percent)


# 下载完成回调
func _on_download_complete(zip_path: String) -> void:
	# 移除下载进度 UI
	_remove_download_progress_ui()

	# 如果收到 needs_quit 信号，说明安装脚本已启动，程序需要退出
	if zip_path == "needs_quit":
		get_tree().quit()
		return

	# 保存 zip 路径，等待用户确认
	_update_pending_zip_path = zip_path
	_update_pending_dest_dir = OS.get_executable_path().get_base_dir()

	# 显示安装确认对话框（下载完成直接弹窗）
	_show_update_install_dialog()


# 待安装的更新包信息
var _update_pending_zip_path: String = ""
var _update_pending_dest_dir: String = ""


# 显示安装确认对话框
func _show_update_install_dialog() -> void:
	if _update_pending_zip_path == "":
		return

	# 创建确认对话框（使用 ConfirmationDialog 才有取消按钮）
	var dialog = ConfirmationDialog.new()
	dialog.title = "安装更新"
	dialog.ok_button_text = "开始安装"
	dialog.cancel_button_text = "取消"

	# 构建内容
	var content_label = Label.new()
	content_label.text = "更新包已下载完成。\n\n点击「开始安装」将解压并更新文件，之后自动启动新版本。"
	content_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var container = VBoxContainer.new()
	container.add_child(content_label)
	container.size = Vector2(350, 120)

	dialog.add_child(container)
	add_child(dialog)

	dialog.popup_centered(Vector2(400, 180))

	# 连接信号
	dialog.confirmed.connect(_on_update_install_confirmed)
	dialog.canceled.connect(_on_update_install_canceled)


# 用户确认安装
func _on_update_install_confirmed() -> void:
	if _update_pending_zip_path != "" and _update_pending_dest_dir != "":
		_extract_and_execute_update(_update_pending_zip_path, _update_pending_dest_dir)
		# 清理待安装状态
		_update_pending_zip_path = ""
		_update_pending_dest_dir = ""


# 用户取消安装
func _on_update_install_canceled() -> void:
	# 保持待安装状态，用户可以稍后从设置页面重新安装
	pass


# 更新下载进度 UI
var _download_progress_panel: Control = null


func _update_download_progress_ui(percent: float) -> void:
	# 如果没有进度 UI，创建它
	if _download_progress_panel == null:
		_download_progress_panel = _create_download_progress_ui()
		get_tree().root.add_child(_download_progress_panel)

	# 更新进度条
	var progress_bar = _download_progress_panel.get_node_or_null("ProgressBar")
	if progress_bar:
		progress_bar.value = percent * 100

	# 更新百分比标签
	var percent_label = _download_progress_panel.get_node_or_null("PercentLabel")
	if percent_label:
		percent_label.text = str(round(percent * 100)) + "%"


func _remove_download_progress_ui() -> void:
	if _download_progress_panel != null:
		_download_progress_panel.queue_free()
		_download_progress_panel = null


func _create_download_progress_ui() -> Control:
	var panel = Panel.new()
	panel.name = "DownloadProgressPanel"
	panel.z_index = 1000

	# 获取窗口大小并居中
	var screen_size = get_viewport().get_visible_rect().size
	var panel_size = Vector2(400, 80)
	panel.position = (screen_size - panel_size) / 2
	panel.size = panel_size

	# 设置样式
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.6, 1.0, 1.0)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)

	panel.custom_minimum_size = Vector2(400, 80)

	# 标题标签
	var title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = translate("downloading_update_title")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.position = Vector2(0, 5)
	title_label.size = Vector2(400, 25)
	panel.add_child(title_label)

	# 进度条
	var progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.position = Vector2(20, 35)
	progress_bar.size = Vector2(360, 20)
	progress_bar.value = 0
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.show_percentage = false

	# 进度条样式
	var pb_style = StyleBoxFlat.new()
	pb_style.bg_color = Color(0.2, 0.2, 0.2, 1)
	pb_style.set_corner_radius_all(4)
	pb_style.set_content_margin_all(2)
	progress_bar.add_theme_stylebox_override("background", pb_style)

	var pb_fill = StyleBoxFlat.new()
	pb_fill.bg_color = Color(0.2, 0.6, 1.0, 1.0)
	pb_fill.set_corner_radius_all(4)
	progress_bar.add_theme_stylebox_override("fill", pb_fill)

	panel.add_child(progress_bar)

	# 百分比标签
	var percent_label = Label.new()
	percent_label.name = "PercentLabel"
	percent_label.text = "0%"
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	percent_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	percent_label.position = Vector2(0, 60)
	percent_label.size = Vector2(400, 20)
	panel.add_child(percent_label)

	return panel


# 解压更新包并执行安装脚本
func _extract_and_execute_update(zip_path: String, dest_dir: String) -> void:
	var temp_dir = OS.get_environment("TEMP")
	var extract_dir = temp_dir + "\\STS2-ModManager-update"

	# 转换路径为 Windows 格式（确保使用反斜杠）
	dest_dir = dest_dir.replace("/", "\\")
	if not dest_dir.ends_with("\\"):
		dest_dir += "\\"

	_write_log("[_extract_and_execute_update] dest_dir: " + dest_dir)

	# 使用 PowerShell 解压 ZIP（先清理旧目录）
	var clean_cmd = 'Remove-Item -Path "%s" -Recurse -Force -ErrorAction SilentlyContinue' % extract_dir
	OS.execute("powershell", ["-NoProfile", "-Command", clean_cmd], [], true)

	var ps_command = 'Expand-Archive -Path "%s" -DestinationPath "%s" -Force' % [zip_path, extract_dir]
	var output = []
	var exit_code = OS.execute("powershell", ["-NoProfile", "-Command", ps_command], output, true)

	print("[_extract_and_execute_update] 解压 exit_code: ", exit_code)
	print("[_extract_and_execute_update] output: ", output)

	if exit_code != OK:
		show_notification("无法解压更新包", false)
		return

	# 检查解压目录是否有文件
	var check_cmd = 'Get-ChildItem -Path "%s" -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count' % extract_dir
	var file_count_output = []
	OS.execute("powershell", ["-NoProfile", "-Command", check_cmd], file_count_output, true)
	print("[_extract_and_execute_update] 解压后文件数: ", file_count_output)

	# 动态查找子目录（ZIP 解压后可能会有子目录）
	var sub_dir_cmd = 'Get-ChildItem -Path "%s" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName' % extract_dir
	var sub_dir_output = []
	var sub_dir_exit = OS.execute("powershell", ["-NoProfile", "-Command", sub_dir_cmd], sub_dir_output, true)
	var actual_sub_dir = ""
	if sub_dir_exit == OK and sub_dir_output.size() > 0 and sub_dir_output[0].strip_edges() != "":
		actual_sub_dir = sub_dir_output[0].strip_edges()
		_write_log("[_extract_and_execute_update] 找到子目录: " + actual_sub_dir)
	else:
		actual_sub_dir = extract_dir
		_write_log("[_extract_and_execute_update] 无子目录，使用根目录")

	# 创建并执行安装脚本
	var script_path = _create_install_script(extract_dir, dest_dir, zip_path)

	if script_path != "":
		print("[_extract_and_execute_update] 脚本路径: ", script_path)

		# 创建 PowerShell 安装脚本，传入实际子目录路径
		var ps_path = _create_install_ps1(script_path, actual_sub_dir, dest_dir, zip_path)

		if ps_path != "":
			_write_log("[_extract_and_execute_update] PS 脚本路径: " + ps_path)
			_write_log("[_extract_and_execute_update] 开始执行...")

			# 使用 cmd start /B 在后台启动 PowerShell（不创建新窗口，脚本在后台运行）
			# -ExecutionPolicy Bypass 允许执行脚本，-NoExit 脚本完成后不退出
			OS.execute("cmd", ["/C", "start", "/B", "powershell", "-ExecutionPolicy", "Bypass", "-NoExit", "-File", ps_path], [], false)

			# 延迟退出，给脚本 2 秒时间启动
			await get_tree().create_timer(2.0).timeout
			get_tree().quit()


# 创建 PowerShell 安装脚本
func _create_install_ps1(script_path: String, source_dir: String, dest_dir: String, zip_path: String) -> String:
	var temp_dir = OS.get_environment("TEMP")
	var ps_path = temp_dir + "\\install_update.ps1"

	# 转换路径格式
	source_dir = source_dir.replace("/", "\\")
	dest_dir = dest_dir.replace("/", "\\")
	zip_path = zip_path.replace("/", "\\")

	# 确保目标目录以反斜杠结尾
	if not dest_dir.ends_with("\\"):
		dest_dir += "\\"

	# 直接使用传入的 source_dir 作为源目录
	var sub_dir = source_dir

	# PowerShell 脚本内容
	var ps_content = ""
	ps_content += "Write-Host '[Update] Source: " + sub_dir + "'\n"
	ps_content += "Write-Host '[Update] Dest: " + dest_dir + "'\n"
	ps_content += "Get-ChildItem '" + sub_dir + "'\n"

	# 强制关闭旧程序
	ps_content += "Write-Host '[Update] Killing old program...'\n"
	ps_content += "Get-Process -Name 'sts2_modmanager','sts2_modmanager.console','godot' -ErrorAction SilentlyContinue | Stop-Process -Force\n"
	ps_content += "Start-Sleep -Seconds 3\n"

	# 复制文件
	ps_content += "Write-Host '[Update] Copying files...'\n"
	ps_content += "Copy-Item -Path '" + sub_dir + "\\*' -Destination '" + dest_dir + "' -Recurse -Force\n"
	ps_content += "Write-Host '[Update] Copy complete'\n"

	# 验证所有文件和目录都已复制
	ps_content += "Write-Host '[Update] Verifying copy results...'\n"
	ps_content += "Get-ChildItem -Path '" + dest_dir + "' | ForEach-Object { Write-Host ('[Verify] ' + $_.FullName) }\n"

	# 清理
	ps_content += "Write-Host '[Update] Cleaning up...'\n"
	ps_content += "Remove-Item -Path '" + source_dir + "' -Recurse -Force -ErrorAction SilentlyContinue\n"
	ps_content += "Remove-Item -Path '" + zip_path + "' -Force -ErrorAction SilentlyContinue\n"

	# 启动新版本
	ps_content += "Write-Host '[Update] Starting new version...'\n"
	ps_content += "Start-Process '" + dest_dir + "sts2_modmanager.exe'\n"

	# 等待新版本启动后自动退出（不等待用户按 Enter）
	ps_content += "Start-Sleep -Seconds 5\n"
	ps_content += "Write-Host '[Update] Update complete! Window will close in 3 seconds...'\n"
	ps_content += "Start-Sleep -Seconds 3\n"
	ps_content += "exit\n"

	_write_log("[_create_install_ps1] ps_content:\n" + ps_content)

	var file = FileAccess.open(ps_path, FileAccess.WRITE)
	if file:
		file.store_string(ps_content)
		file.close()
		return ps_path
	return ""


# 创建安装脚本
func _create_install_script(extract_dir: String, dest_dir: String, zip_path: String) -> String:
	var temp_dir = OS.get_environment("TEMP")
	var script_path = temp_dir + "\\update-install.ps1"

	var script_content = """param([string]$SourceDir, [string]$DestDir, [string]$ZipPath)

Write-Host "[Update] 开始安装更新..."
Write-Host "[Update] SourceDir: $SourceDir"
Write-Host "[Update] DestDir: $DestDir"
Write-Host "[Update] ZipPath: $ZipPath"

# 等待原程序退出
Write-Host "[Update] 等待原程序退出..."
Start-Sleep -Seconds 3

# 检查源目录
if (-not (Test-Path $SourceDir)) {
	Write-Host "[Update] 错误: 源目录不存在: $SourceDir"
    exit 1
}

# 复制新文件
Write-Host "[Update] 复制新文件..."
$files = Get-ChildItem -Path $SourceDir -File -ErrorAction SilentlyContinue
if ($files) {
    foreach ($file in $files) {
        $destFile = Join-Path $DestDir $file.Name
		Write-Host "[Update] 复制: $($file.Name) -> $destFile"
        Copy-Item -Path $file.FullName -Destination $destFile -Force
    }
	Write-Host "[Update] 文件复制完成"
} else {
	Write-Host "[Update] 警告: 源目录没有文件"
}

# 清理临时解压目录
Write-Host "[Update] 清理临时目录..."
Remove-Item -Path $SourceDir -Recurse -Force -ErrorAction SilentlyContinue

# 删除 zip 包
Write-Host "[Update] 删除 ZIP 包..."
if (Test-Path $ZipPath) {
    Remove-Item -Path $ZipPath -Force
}

# 启动新版本
Write-Host "[Update] 启动新版本..."
$exeFiles = Get-ChildItem -Path $DestDir -Filter "*.exe" -ErrorAction SilentlyContinue
if ($exeFiles) {
	Write-Host "[Update] 启动: $($exeFiles[0].FullName)"
    Start-Process $exeFiles[0].FullName
} else {
	Write-Host "[Update] 警告: 未找到 exe 文件"
}

# 删除自身
Start-Sleep -Seconds 2
try {
    Remove-Item -Path $MyInvocation.InvocationName -Force -ErrorAction Stop
} catch {
    # 忽略删除失败
}

Write-Host "[Update] 安装完成"
"""

	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file:
		file.store_string(script_content)
		file.close()
		return script_path

	return ""


# 下载错误回调
func _on_download_error(message: String) -> void:
	show_notification(translate("download_update_failed").format({"error": message}), false)


# 检查更新按钮点击
func _on_check_update_pressed() -> void:
	# 检查是否已有下载好的更新包
	var downloads_dir = OS.get_environment("USERPROFILE") + "\\Downloads"
	var existing_zip = downloads_dir + "\\STS2-ModManager-update.zip"

	if FileAccess.file_exists(existing_zip):
		# 已下载过，显示安装确认
		_update_pending_zip_path = existing_zip
		_update_pending_dest_dir = OS.get_executable_path().get_base_dir()
		_show_update_install_dialog()
		return

	# 没有下载过，执行检查更新
	show_notification(translate("checking_update"), true)
	_check_for_updates(false)


# 导出调试信息按钮点击
func _on_export_debug_info_pressed() -> void:
	var temp_dir = OS.get_environment("TEMP")
	var debug_file = temp_dir + "\\STS2-ModManager-debug.log"

	# 收集调试信息
	var debug_content = "=== STS2 Mod Manager Debug Info ===\n"
	debug_content += "Generated: " + Time.get_datetime_string_from_system() + "\n\n"

	# 版本信息
	debug_content += "=== Version Info ===\n"
	debug_content += "Version: " + config.get_value("current_version", "version", "") + "\n"
	debug_content += "Engine: Godot " + Engine.get_version_info()["string"] + "\n\n"

	# 路径配置
	debug_content += "=== Paths ===\n"
	debug_content += "Executable: " + OS.get_executable_path() + "\n"
	debug_content += "Base Dir: " + OS.get_executable_path().get_base_dir() + "\n"
	debug_content += "Game Path: " + config.get_value("paths", "game_path", "") + "\n"
	debug_content += "Save Path: " + config.get_value("paths", "save_path", "") + "\n\n"

	# 模组数量
	debug_content += "=== Mods ===\n"
	debug_content += "Total Mods: " + str(mods.size()) + "\n"
	debug_content += "Enabled Mods: " + str(enabled_mods.size()) + "\n\n"

	# 当前日志文件内容
	debug_content += "=== Recent Log (last 200 lines) ===\n"
	var log_path = OS.get_environment("USERPROFILE") + "/AppData/Local/Temp/sts2_modmanager.log"
	if FileAccess.file_exists(log_path):
		var log_file = FileAccess.open(log_path, FileAccess.READ)
		if log_file:
			var lines = []
			while not log_file.eof_reached():
				var line = log_file.get_line()
				if line.strip_edges() != "":
					lines.append(line)
			log_file.close()

			# 取最后 200 行
			var start_idx = max(0, lines.size() - 200)
			for i in range(start_idx, lines.size()):
				debug_content += lines[i] + "\n"

	# 保存到文件
	var file = FileAccess.open(debug_file, FileAccess.WRITE)
	if file:
		file.store_string(debug_content)
		file.close()

		# 打开调试日志文件
		OS.shell_open(debug_file)
		show_notification(translate("debug_info_exported"), true)
	else:
		show_notification(translate("debug_info_export_failed"), false)


# 显示更新确认对话框
func _show_update_dialog() -> void:
	if pending_update_info.is_empty():
		return

	var new_version = pending_update_info.get("version", "")
	var current_version = _read_version_from_file()
	var changelog = pending_update_info.get("changelog", "")

	# 创建确认对话框
	var dialog = ConfirmationDialog.new()
	dialog.title = translate("new_version_title")
	dialog.ok_button_text = translate("update_now")
	dialog.cancel_button_text = translate("remind_later")

	# 使用 dialog_text 而非自定义内容
	var message = translate("current_version_label").format({"current": current_version, "new": new_version})
	if changelog != "" and changelog.length() > 0:
		message += "\n\n" + translate("changelog_label") + ":\n" + changelog
	dialog.dialog_text = message

	add_child(dialog)

	dialog.popup_centered(Vector2(450, 350))

	# 连接信号
	dialog.confirmed.connect(_on_update_confirmed)
	dialog.canceled.connect(_on_update_canceled)


# 用户确认更新
func _on_update_confirmed() -> void:
	# 开始下载
	var download_url = pending_update_info.get("download_url", "")
	print("[_on_update_confirmed] download_url: ", download_url)
	print("[_on_update_confirmed] update_checker: ", update_checker)
	if download_url != "" and update_checker:
		show_notification(translate("downloading_update").format({"percent": "0"}), true)
		# 直接在 modmanager 中处理下载
		_start_update_download(download_url)
	else:
		print("[_on_update_confirmed] No download_url or no update_checker!")
		show_notification("更新失败: 无效的下载链接", false)


# 更新下载相关变量
var _update_zip_path: String = ""
var _update_monitor_timer: Timer = null


func _start_update_download(download_url: String) -> void:
	# 下载到用户下载目录（使用 Windows 格式）
	var downloads_dir = OS.get_environment("USERPROFILE") + "\\Downloads"
	_update_zip_path = downloads_dir + "\\STS2-ModManager-update.zip"

	# 使用线程执行下载（与模组下载相同的模式）
	var thread = Thread.new()
	var args = {
		"url": download_url,
		"abs_save_path": _update_zip_path,
		"download_id": "update",
		"mod_name": "STS2-ModManager-update"
	}
	thread.start(_update_thread_download_wrapper.bind(args))

	# 更新进度 UI
	_update_download_progress_ui(0.1)

	# 启动监控定时器（监控线程传入的路径）
	_update_monitor_timer = Timer.new()
	_update_monitor_timer.wait_time = 1.0
	_update_monitor_timer.timeout.connect(_check_update_download_status)
	add_child(_update_monitor_timer)
	_update_monitor_timer.start()


func _update_thread_download_wrapper(args: Dictionary) -> void:
	"""后台线程下载包装器（更新下载用）"""
	var url = args["url"]
	var abs_save_path = args["abs_save_path"]

	print("[_update_thread_download_wrapper] Starting download...")

	# 确保目标目录存在
	var dir_path = abs_save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	# 使用 curl 下载
	# URL需要编码空格
	var encoded_url = url.replace(" ", "%20")
	var curl_command = 'curl -L --max-time 600 -o "%s" -A "STS2-ModManager/2.6.9" -- "%s"' % [abs_save_path, encoded_url]

	var output = []
	var exit_code = OS.execute("cmd", ["/C", curl_command], output, true)
	print("[_update_thread_download_wrapper] curl exit code: ", exit_code)

	var result = false
	if exit_code == 0 and FileAccess.file_exists(abs_save_path):
		var file = FileAccess.open(abs_save_path, FileAccess.READ)
		if file:
			var file_size = file.get_length()
			file.close()
			if file_size > 1024:
				result = true
				print("[_update_thread_download_wrapper] Downloaded bytes: ", file_size)

	# 回到主线程处理结果
	call_deferred("_on_update_download_complete", result)


func _on_update_download_complete(success: bool) -> void:
	print("[_on_update_download_complete] success: ", success)
	if _update_monitor_timer:
		_update_monitor_timer.stop()
		_update_monitor_timer.queue_free()
		_update_monitor_timer = null

	if success:
		_update_download_progress_ui(1.0)
		_on_download_complete(_update_zip_path)
	else:
		show_notification("更新下载失败", false)
		_remove_download_progress_ui()


func _check_update_download_status() -> void:
	# 通过文件大小监控下载进度
	if FileAccess.file_exists(_update_zip_path):
		var file = FileAccess.open(_update_zip_path, FileAccess.READ)
		if file:
			var current_size = file.get_length()
			file.close()

			# 估算进度（假设文件大约 65MB）
			var estimated_total = 65 * 1024 * 1024
			var progress = min(float(current_size) / estimated_total, 0.99)
			_update_download_progress_ui(progress)


# 用户取消更新
func _on_update_canceled() -> void:
	pending_update_info = {}


# 更新模组 JSON 文件中的下载来源
func _update_mod_json_download_source(mod_path: String, download_source: String) -> void:
	if mod_path.is_empty() or download_source.is_empty():
		print("[_update_mod_json_download_source] Early return - mod_path: '", mod_path, "', source: '", download_source, "'")
		return

	# 查找 JSON 文件
	var json_path = ModUtils.find_json_file(mod_path)
	if json_path.is_empty():
		print("[_update_mod_json_download_source] No JSON file found in: ", mod_path)
		return

	print("[_update_mod_json_download_source] Found JSON at: ", json_path)

	# 读取现有内容
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		print("[_update_mod_json_download_source] Failed to open JSON file: ", json_path)
		return

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		print("[_update_mod_json_download_source] JSON parse error")
		return

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		print("[_update_mod_json_download_source] Invalid JSON format")
		return

	# 添加或更新 download_source 字段
	data["download_source"] = download_source

	# 写回文件
	var json_string = JSON.stringify(data, "\t")
	var new_file = FileAccess.open(json_path, FileAccess.WRITE)
	if new_file == null:
		print("[_update_mod_json_download_source] Failed to write JSON file")
		return
	new_file.store_string(json_string)
	new_file.close()
	print("[_update_mod_json_download_source] Updated download_source to: ", download_source)


# 检测 DPI 并返回合适的缩放因子
func _detect_dpi_scale() -> float:
	var screen_dpi = DisplayServer.screen_get_dpi()
	print("[_detect_dpi_scale] Screen DPI: ", screen_dpi)
	if screen_dpi >= 192:
		return 1.5
	elif screen_dpi >= 144:
		return 1.25
	return 1.0

# 应用全局缩放到 UI
func _apply_font_scale() -> void:
	# 计算缩放后的字体大小
	var scaled_body_size = int(FONT_SIZES["body"] * dpi_scale)

	# 获取 TabContainer 作为根容器
	var tab_container = find_child_node(self, "TabContainer")
	if tab_container:
		# 递归设置所有控件的字体大小
		_apply_font_scale_to_node(tab_container, scaled_body_size)
		print("[_apply_font_scale] Applied scale: ", dpi_scale, ", font_size: ", scaled_body_size)

# 递归设置节点及其子节点的字体大小
func _apply_font_scale_to_node(node: Node, base_size: int) -> void:
	# 设置 Label 的字体大小
	if node is Label:
		node.add_theme_font_size_override("font_size", base_size)
	# 设置 Button 的字体大小
	elif node is Button:
		node.add_theme_font_size_override("font_size", base_size)
	# 设置 CheckBox 的字体大小
	elif node is CheckBox:
		node.add_theme_font_size_override("font_size", base_size)
	# 设置 LineEdit 的字体大小
	elif node is LineEdit:
		node.add_theme_font_size_override("font_size", base_size)
	# 设置 SpinBox 的字体大小
	elif node is SpinBox:
		node.add_theme_font_size_override("font_size", base_size)
	# 设置 OptionButton 的字体大小
	elif node is OptionButton:
		node.add_theme_font_size_override("font_size", base_size)
	# 设置 TabBar 的字体大小
	elif node is TabBar:
		node.add_theme_font_size_override("font_size", base_size)

	# 递归处理所有子节点
	for child in node.get_children():
		_apply_font_scale_to_node(child, base_size)

# 计算缩放后的间距
func get_scaled_spacing(key: String) -> int:
	var base = SPACING.get(key, 8)
	return int(base * dpi_scale)

# 加载配置文件
func load_config() -> void:
	print("[load_config] Loading config from: ", config_path)
	var err = config.load(config_path)
	print("[load_config] Config load error: ", err)
	if err != OK:
		# 创建默认配置
		print("[load_config] Creating default config...")
		config.set_value("paths", "game_path", "")
		config.set_value("paths", "save_path", "")
		config.set_value("paths", "temp_mods_path", temp_mods_path)
		config.set_value("paths", "backup_path", backup_path)
		config.set_value("settings", "language", "zh_CN")
		config.set_value("settings", "minimize_to_tray", true)
		config.set_value("settings", "auto_backup", true)
		config.set_value("settings", "auto_backup_on_startup", true)
		config.set_value("settings", "auto_backup_max_count", 5)
		config.set_value("settings", "launch_via_steam", true)
		config.set_value("settings", "dpi_scale", 1.0)
		# 设置默认版本
		var default_version = ProjectSettings.get_setting("config/version", "v0.0.0")
		config.set_value("current_version", "version", default_version)
		var save_err = config.save(config_path)
		print("[load_config] Config save error: ", save_err)
	else:
		# 检查是否已有 current_version 配置节
		var existing_version = config.get_value("current_version", "version", "")
		print("[load_config] Existing config current_version: '", existing_version, "'")

	# 读取配置值
	dpi_scale = config.get_value("settings", "dpi_scale", 0.0)
	current_language = config.get_value("settings", "language", "zh_CN")
	game_path = config.get_value("paths", "game_path", "")
	save_path = config.get_value("paths", "save_path", "")
	gse_cloud_path = config.get_value("paths", "gse_cloud_path", "")
	steam_cloud_path = config.get_value("paths", "steam_cloud_path", "")
	fix_steam_path = config.get_value("paths", "fix_steam_path", "")

	# 强制同步版本：从 version.json 读取（编辑器/导出版本通用）
	var project_version = ""

	# 先尝试从 exe 目录读取 version.json
	var exe_dir = OS.get_executable_path().get_base_dir()
	var version_file_path = exe_dir + "/version.json"
	if FileAccess.file_exists(version_file_path):
		var version_file = FileAccess.open(version_file_path, FileAccess.READ)
		if version_file:
			var json_str = version_file.get_as_text()
			version_file.close()
			var json = JSON.new()
			if json.parse(json_str) == OK:
				project_version = json.data.get("version", "v0.0.0")
	else:
		# 备选：从 res:// 读取（编辑器版本）
		version_file_path = "res://version.json"
		if FileAccess.file_exists(version_file_path):
			var version_file = FileAccess.open(version_file_path, FileAccess.READ)
			if version_file:
				var json_str = version_file.get_as_text()
				version_file.close()
				var json = JSON.new()
				if json.parse(json_str) == OK:
					project_version = json.data.get("version", "v0.0.0")

	print("[load_config] project_version: ", project_version)

	# 设置版本
	config.set_value("current_version", "version", project_version)
	print("[load_config] Setting config version to: ", project_version)

	# 保存并验证
	var save_result = config.save(config_path)
	print("[load_config] Save result: ", save_result)

	# 验证保存是否成功
	var verify_version = config.get_value("current_version", "version", "NOT_FOUND")
	print("[load_config] Verified version in config: ", verify_version)

	# 如果配置中没有云端路径，自动检测
	if gse_cloud_path.is_empty():
		gse_cloud_path = SaveUtils.get_gse_cloud_save_path()
		if not gse_cloud_path.is_empty():
			config.set_value("paths", "gse_cloud_path", gse_cloud_path)

	if steam_cloud_path.is_empty():
		steam_cloud_path = SaveUtils.detect_steam_cloud_save_path()
		if not steam_cloud_path.is_empty():
			config.set_value("paths", "steam_cloud_path", steam_cloud_path)

	# temp_mods_path 和 backup_path 现在是动态属性，不需要从配置读取

	# 加载导入存档的备份信息（持久化存储）
	var saved_imported_backups = config.get_value("imported_backups", "saves", {})
	for key in saved_imported_backups:
		var backup_path_value = saved_imported_backups[key]
		# 只加载仍然存在的备份
		if not backup_path_value.is_empty() and DirAccess.dir_exists_absolute(backup_path_value):
			backed_up_saves[key] = backup_path_value
			print("[load_config] Loaded imported backup: ", key, " -> ", backup_path_value)
		else:
			print("[load_config] Skipping stale imported backup: ", key)

	# 加载已保存的模组启用状态（用于重启后恢复）
	enabled_mods = config.get_value("mods", "enabled_mods", {})

	# 加载模组JSON必要字段配置
	var saved_required = config.get_value("mods", "required_fields", [])
	if saved_required.is_empty() and not config.has_section_key("mods", "required_fields"):
		pass  # 没有配置，使用默认值
	else:
		mod_required_fields = saved_required
	var saved_optional = config.get_value("mods", "optional_fields", [])
	if saved_optional.is_empty() and not config.has_section_key("mods", "optional_fields"):
		pass  # 没有配置，使用默认值
	else:
		mod_optional_fields = saved_optional

	# 检查是否需要恢复原版启动后的mods
	if config.get_value("settings", "vanilla_mode_pending", false):
		print("[load_config] Checking for pending mods restore...")
		_restore_mods_after_vanilla()
		config.set_value("settings", "vanilla_mode_pending", false)
		config.save(config_path)

	# 确保temp_save目录存在
	if not DirAccess.dir_exists_absolute(temp_save_path):
		DirAccess.make_dir_recursive_absolute(temp_save_path)

	# 加载标签数据
	_load_tag_data()

	# 加载收纳盒子与覆盖顺序数据
	_load_mod_organization_data()

	# DPI 缩放：如果 dpi_scale 为 0 或未设置，执行自动检测
	if dpi_scale <= 0.0:
		dpi_scale = _detect_dpi_scale()
		print("[load_config] Auto-detected dpi_scale: ", dpi_scale)

	# 应用初始缩放
	_apply_font_scale()

# 加载标签数据
func _load_tag_data() -> void:
	# 从配置中读取标签数据
	var saved_tag_data = config.get_value("tags", "data", {})
	var saved_current_tag = config.get_value("tags", "current_tag", "单人模组")

	# 如果没有保存的数据，初始化默认标签
	if saved_tag_data.is_empty():
		tag_data = {
			"单人模组": [],
			"联机模组": []
		}
	else:
		tag_data = saved_tag_data

	# 确保预置标签存在
	if not tag_data.has("单人模组"):
		tag_data["单人模组"] = []
	if not tag_data.has("联机模组"):
		tag_data["联机模组"] = []

	current_tag = saved_current_tag
	if not tag_data.has(current_tag):
		current_tag = "单人模组"

	print("[_load_tag_data] Loaded tag_data: ", tag_data)
	print("[_load_tag_data] current_tag: ", current_tag)


# 保存标签数据
func _save_tag_data() -> void:
	config.set_value("tags", "data", tag_data)
	config.set_value("tags", "current_tag", current_tag)
	config.save(config_path)
	print("[_save_tag_data] Saved tag_data: ", tag_data)


# 保存模组启用状态到配置文件
func _save_enabled_mods() -> void:
	config.set_value("mods", "enabled_mods", enabled_mods)
	config.save(config_path)
	print("[_save_enabled_mods] Saved enabled_mods: ", enabled_mods)


# 加载收纳盒子与覆盖顺序数据
func _load_mod_organization_data() -> void:
	var saved_boxes = config.get_value("mod_organization", "boxes", [])
	if typeof(saved_boxes) == TYPE_ARRAY and not saved_boxes.is_empty():
		mod_boxes = saved_boxes
	else:
		mod_boxes = []

	mod_order_override = config.get_value("mod_organization", "mod_order_override", [])
	enable_override_order = config.get_value("mod_organization", "enable_override_order", false)
	enable_mod_drag = config.get_value("mod_organization", "enable_mod_drag", false)

	print("[_load_mod_organization_data] Loaded boxes: ", mod_boxes.size())
	print("[_load_mod_organization_data] enable_override_order: ", enable_override_order)
	print("[_load_mod_organization_data] mod_order_override: ", mod_order_override)

	# 检查是否有残留的 manifest 备份（上次异常退出未恢复）
	if not _manifest_backups.is_empty():
		print("[_load_mod_organization_data] WARNING: Found stale manifest backups, restoring...")
		restore_manifests_after_exit()


# 保存收纳盒子与覆盖顺序数据（内部设置值，调用者负责 config.save()）
func _save_mod_organization_data() -> void:
	config.set_value("mod_organization", "boxes", mod_boxes)
	config.set_value("mod_organization", "mod_order_override", mod_order_override)
	config.set_value("mod_organization", "enable_override_order", enable_override_order)
	config.set_value("mod_organization", "enable_mod_drag", enable_mod_drag)
	print("[_save_mod_organization_data] Saved boxes: ", mod_boxes.size())


# 恢复 manifest 文件（在游戏退出后调用，或启动时检查残留）
func restore_manifests_after_exit() -> void:
	if _manifest_backups.is_empty():
		print("[restore_manifests_after_exit] No backups to restore")
		return
	print("[restore_manifests_after_exit] Restoring ", _manifest_backups.size(), " manifests...")
	for mod_id in _manifest_backups:
		var json_content = _manifest_backups[mod_id]
		_write_manifest_json_content(mod_id, json_content)
	_manifest_backups.clear()
	print("[restore_manifests_after_exit] All manifests restored")


# 写入 manifest JSON 内容（供 restore 使用，内部用）
func _write_manifest_json_content(mod_id: String, json_content: String) -> bool:
	if game_path.is_empty():
		return false
	var mod_dir = game_path.path_join("mods").path_join(mod_id)
	var manifest_path = ModUtils.find_manifest_json(mod_dir)
	if manifest_path.is_empty():
		print("[_write_manifest_json_content] Manifest not found for: ", mod_id)
		return false
	var file = FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		print("[_write_manifest_json_content] Cannot write manifest: ", manifest_path)
		return false
	file.store_string(json_content)
	file.close()
	print("[_write_manifest_json_content] Restored manifest: ", manifest_path)
	return true


# ============================================================
# 模组覆盖顺序功能
# ============================================================

# 读取模组的 manifest JSON 内容（返回原始文本）
func _read_manifest_content(mod_id: String) -> String:
	if game_path.is_empty():
		return ""
	var mod_dir = game_path.path_join("mods").path_join(mod_id)
	var manifest_path = ModUtils.find_manifest_json(mod_dir)
	if manifest_path.is_empty():
		return ""
	var file = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return ""
	var content = file.get_as_text()
	file.close()
	return content


# 根据 mod_order_override 构建依赖链
# 返回: {mod_id: [dep_ids]} - 只包含需要管理器添加的依赖（原来为空/空的）
func _build_dependency_chain() -> Dictionary:
	var deps_map: Dictionary = {}
	if mod_order_override.is_empty():
		return deps_map

	for i in range(mod_order_override.size()):
		var mod_id = mod_order_override[i]
		if i == 0:
			deps_map[mod_id] = []  # 第一个模组，无依赖
			continue

		# 检查 manifest 中是否已有依赖
		var manifest_content = _read_manifest_content(mod_id)
		var has_existing_deps = false
		if not manifest_content.is_empty():
			var json = JSON.new()
			if json.parse(manifest_content) == OK:
				var data = json.get_data()
				if typeof(data) == TYPE_DICTIONARY:
					var existing_deps = data.get("dependencies", [])
					if typeof(existing_deps) == TYPE_ARRAY and not existing_deps.is_empty():
						has_existing_deps = true

		if has_existing_deps:
			deps_map[mod_id] = []  # 有已有依赖，保留不覆盖
		else:
			# 添加对前一个模组的依赖
			var prev_mod_id = mod_order_override[i - 1]
			deps_map[mod_id] = [prev_mod_id]

	print("[_build_dependency_chain] Dependency chain: ", deps_map)
	return deps_map


# 启动前应用覆盖顺序（备份 + 写入）
func apply_override_order_before_launch() -> bool:
	if not enable_override_order:
		print("[apply_override_order] Override order is disabled, skipping")
		return true

	if game_path.is_empty():
		show_notification("无法写入模组顺序：未配置游戏路径", false)
		return false

	if mod_order_override.is_empty():
		print("[apply_override_order] No mod order defined, skipping")
		return true

	print("[apply_override_order] Applying override order before launch...")
	print("[apply_override_order] mod_order_override: ", mod_order_override)

	# 1. 备份所有 manifest
	_manifest_backups.clear()
	for mod_id in mod_order_override:
		var content = _read_manifest_content(mod_id)
		if not content.is_empty():
			_manifest_backups[mod_id] = content
			print("[apply_override_order] Backed up manifest: ", mod_id)
		else:
			print("[apply_override_order] WARNING: No manifest found for: ", mod_id)

	# 2. 构建依赖链
	var deps_chain = _build_dependency_chain()

	# 3. 写入依赖
	for mod_id in deps_chain:
		var deps = deps_chain[mod_id]
		if deps.is_empty():
			continue  # 无需修改

		_write_mod_dependencies(mod_id, deps)

	print("[apply_override_order] Override order applied to ", deps_chain.size(), " mods")
	return true


# 写入单个模组的 dependencies
func _write_mod_dependencies(mod_id: String, deps: Array) -> bool:
	if game_path.is_empty():
		return false

	var mod_dir = game_path.path_join("mods").path_join(mod_id)
	var manifest_path = ModUtils.find_manifest_json(mod_dir)
	if manifest_path.is_empty():
		print("[_write_mod_dependencies] Manifest not found: ", mod_id)
		return false

	# 读取现有内容
	var file = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return false
	var content = file.get_as_text()
	file.close()

	# 解析 JSON
	var json = JSON.new()
	if json.parse(content) != OK:
		print("[_write_mod_dependencies] JSON parse error for: ", mod_id)
		return false
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return false

	# 更新 dependencies
	data["dependencies"] = deps

	# 写回
	var pretty_json = JSON.stringify(data, "\t")
	file = FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(pretty_json)
	file.close()
	print("[_write_mod_dependencies] Updated dependencies for ", mod_id, ": ", deps)
	return true


# 监听游戏进程退出并恢复 manifest
var _game_process_pid: int = -1
var _game_process_timer: Timer = null


func _watch_game_process(pid: int) -> void:
	_game_process_pid = pid
	if _game_process_timer != null:
		_game_process_timer.stop()
		_game_process_timer.queue_free()

	_game_process_timer = Timer.new()
	_game_process_timer.wait_time = 1.0  # 每秒检查一次
	_game_process_timer.timeout.connect(_check_game_process)
	add_child(_game_process_timer)
	_game_process_timer.start()
	print("[_watch_game_process] Started watching process: ", pid)


func _check_game_process() -> void:
	if _game_process_pid < 0:
		return

	# 检查进程是否存在
	var pid_str = str(_game_process_pid)
	var output = []
	var exit_code = OS.execute("tasklist", ["/FI", "PID eq " + pid_str], output, false)
	if exit_code != 0 or output.is_empty():
		_finish_game_process()
		return

	var result = output[0] if not output.is_empty() else ""
	if pid_str in result and "No tasks" not in result:
		return  # 进程仍在运行

	_finish_game_process()


func _finish_game_process() -> void:
	if _game_process_timer != null:
		_game_process_timer.stop()
		_game_process_timer.queue_free()
		_game_process_timer = null

	_game_process_pid = -1
	print("[_finish_game_process] Game process exited, restoring manifests...")

	restore_manifests_after_exit()
	show_notification("游戏已退出，模组覆盖顺序已恢复", true)



# 加载语言文件
func load_locale() -> void:
	print("[load_locale] current_language: ", current_language)
	# locale 文件始终从 res:// 读取（打包资源）
	var locale_path = "res://locales/" + current_language + ".json"
	print("[load_locale] locale_path: ", locale_path)
	if FileAccess.file_exists(locale_path):
		var file = FileAccess.open(locale_path, FileAccess.READ)
		if file != null:
			var content = file.get_as_text()
			file.close()

			var json = JSON.new()
			var error = json.parse(content)
			if error == OK:
				locale_data = json.get_data()
				print("[load_locale] Loaded locale data successfully")
				# 刷新Tab标题（启动时需要）
				_update_tab_titles()
	else:
		print("[load_locale] Locale file not found: ", locale_path)


# 加载模组备注
func load_mod_notes() -> void:
	var path = mod_notes_path
	if not FileAccess.file_exists(path):
		print("[load_mod_notes] File not exists, creating empty notes")
		mod_notes = {}
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[load_mod_notes] Open failed")
		mod_notes = {}
		return

	var text = file.get_as_text()
	file.close()

	if text.is_empty():
		mod_notes = {}
		return

	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		print("[load_mod_notes] Parse failed: ", err)
		mod_notes = {}
		return

	var data = json.get_data()
	if data is Dictionary:
		mod_notes = data.get("mod_notes", {})
	else:
		mod_notes = {}
	print("[load_mod_notes] Loaded: ", mod_notes.size(), " notes")


# 保存模组备注
func save_mod_notes() -> void:
	var path = mod_notes_path

	# 确保目录存在
	var dir = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var json_str = JSON.stringify({"mod_notes": mod_notes}, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("[save_mod_notes] Open failed")
		return

	file.store_string(json_str)
	file.close()
	print("[save_mod_notes] Saved: ", mod_notes.size(), " notes")


# 显示备注编辑弹窗
func _show_mod_note_edit_dialog(mod_id: String) -> void:
	var current_note = mod_notes.get(mod_id, "")

	# 创建对话框（使用ConfirmationDialog才有取消按钮）
	var dialog = ConfirmationDialog.new()
	dialog.title = translate("mod_note_edit")
	dialog.ok_button_text = translate("confirm")
	dialog.cancel_button_text = translate("cancel")
	add_child(dialog)

	# 创建内容容器
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(350, 150)

	# 创建输入框
	var text_edit = TextEdit.new()
	text_edit.text = current_note
	text_edit.custom_minimum_size = Vector2(350, 120)
	text_edit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 字符限制提示
	var hint_label = Label.new()
	hint_label.text = "最多500字符"
	hint_label.add_theme_font_size_override("font_size", 10)
	hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))

	vbox.add_child(text_edit)
	vbox.add_child(hint_label)
	dialog.add_child(vbox)

	# 连接信号
	dialog.confirmed.connect(func():
		var new_note = text_edit.text.strip_edges().left(500)
		if new_note.is_empty():
			mod_notes.erase(mod_id)
		else:
			mod_notes[mod_id] = new_note
		save_mod_notes()
		# 刷新显示备注
		_refresh_mod_note_display(mod_id)
		dialog.queue_free()
	)

	dialog.canceled.connect(func():
		dialog.queue_free()
	)

	dialog.popup_centered(Vector2(400, 200))


# 编辑备注按钮点击处理
func _on_mod_note_edit_btn_pressed() -> void:
	if current_mod_data.is_empty():
		return
	var mod_id = current_mod_data.get("id", "")
	if not mod_id.is_empty():
		_show_mod_note_edit_dialog(mod_id)


# 刷新备注显示
func _refresh_mod_note_display(mod_id: String) -> void:
	var note_text = mod_notes.get(mod_id, "")
	if mod_note_label:
		if not note_text.is_empty():
			mod_note_label.text = translate("mod_note") + ": " + note_text
			mod_note_label.visible = true
			if mod_note_separator:
				mod_note_separator.visible = true
		else:
			mod_note_label.visible = false
			if mod_note_separator:
				mod_note_separator.visible = false


# 自定义翻译函数
func translate(key: String) -> String:
	if locale_data.has(key):
		return locale_data[key]
	else:
		return key

# 带参数的翻译函数（更安全的格式化）
func translate_fmt(key: String, args: Array) -> String:
	var template = translate(key)
	# 如果 translate 返回的是键名（没有找到翻译），直接返回键名
	if not locale_data.has(key):
		return key
	# 尝试格式化，如果失败则返回模板
	if args.size() > 0:
		# 检查模板中占位符数量
		var placeholder_count = 0
		var i = 0
		while i < template.length() - 1:
			if template[i] == "%" and (template[i + 1] == "s" or template[i + 1] == "d"):
				placeholder_count += 1
				i += 2
			else:
				i += 1
		
		# 只有当占位符数量匹配时才格式化
		if placeholder_count == args.size():
			# 安全地使用 % 操作符
			var result = template
			match args.size():
				1:
					result = template % args[0]
				2:
					result = template % [args[0], args[1]]
				3:
					result = template % [args[0], args[1], args[2]]
				4:
					result = template % [args[0], args[1], args[2], args[3]]
				_:
					# 对于更多参数，使用数组
					result = template % args
			return result
		else:
			# 占位符数量不匹配，返回原始模板
			print("[translate_fmt] Placeholder count mismatch for key '", key, "': expected ", args.size(), ", found ", placeholder_count)
			return template
	return template


# 更新Tab标题（启动时和切换语言时调用）
func _update_tab_titles() -> void:
	if not tab_container:
		tab_container = find_child_node(self, "TabContainer")
	if tab_container:
		print("[_update_tab_titles] Setting tab titles, tab count: ", tab_container.get_tab_count())
		tab_container.set_tab_title(0, translate("mods"))
		tab_container.set_tab_title(1, translate("bundle_tab"))
		tab_container.set_tab_title(2, translate("saves"))
		tab_container.set_tab_title(3, translate("nexus_mods"))
		tab_container.set_tab_title(4, translate("downloads"))
		tab_container.set_tab_title(5, translate("settings"))
	else:
		print("[_update_tab_titles] TabContainer not found!")


# 构建标签按钮
func _build_tag_buttons() -> void:
	# 清除现有按钮
	for child in tag_container.get_children():
		child.queue_free()
	tag_buttons.clear()

	# 收集自定义标签（非默认标签）
	var custom_tags = []
	for tag_name in tag_data.keys():
		if not tag_name in DEFAULT_TAGS:
			custom_tags.append(tag_name)

	# 确定当前显示的标签列表 - 默认始终显示单人模组和联机模组
	var tags_to_display = DEFAULT_TAGS.duplicate()

	# 如果当前选中的是自定义标签，在第二个位置显示它
	if current_tag in custom_tags:
		tags_to_display[1] = current_tag
	# 否则根据滚轮索引决定第二个位置显示什么
	elif custom_tag_scroll_index >= 0 and custom_tag_scroll_index < custom_tags.size():
		# 显示当前滚轮位置的自定义标签
		tags_to_display[1] = custom_tags[custom_tag_scroll_index]

	# 创建标签按钮
	for tag_name in tags_to_display:
		if not tag_data.has(tag_name):
			continue

		var btn = Button.new()
		# 使用翻译后的标签名称
		var display_name = tag_name
		if tag_name == "单人模组":
			display_name = translate("single_player_mods")
		elif tag_name == "联机模组":
			display_name = translate("multiplayer_mods")
		btn.text = display_name
		btn.toggle_mode = true
		btn.button_pressed = (tag_name == current_tag)

		# 设置样式
		if tag_name == current_tag:
			btn.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0))  # 选中颜色

		# 连接点击信号
		btn.pressed.connect(_on_tag_selected.bind(tag_name))

		# 只对自定义标签添加长按检测
		if not tag_name in DEFAULT_TAGS:
			btn.gui_input.connect(_on_custom_tag_input.bind(tag_name, btn))

		tag_container.add_child(btn)
		tag_buttons[tag_name] = btn

	# 添加新增标签按钮
	var add_btn = Button.new()
	add_btn.text = "+"
	add_btn.tooltip_text = translate("add_tag_tip")
	add_btn.pressed.connect(_on_add_tag_pressed)
	tag_container.add_child(add_btn)

	print("[_build_tag_buttons] Built buttons for tags: ", tags_to_display)


# 自定义标签输入事件（处理长按删除）
func _on_custom_tag_input(event: InputEvent, tag_name: String, btn: Button) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 开始长按
				_start_longpress_delete(tag_name, btn)
			else:
				# 释放，取消长按
				_cancel_longpress_delete()


# 开始长按删除
func _start_longpress_delete(tag_name: String, btn: Button) -> void:
	# 防止重复触发
	if longpress_timer != null and longpress_target_tag == tag_name:
		return

	longpress_target_tag = tag_name
	longpress_button = btn

	# 保存原始文字
	var original_text = btn.text

	# 创建进度条
	longpress_progress = ProgressBar.new()
	longpress_progress.min_value = 0
	longpress_progress.max_value = 3.0  # 3秒
	longpress_progress.value = 0
	longpress_progress.show_percentage = false

	# 设置样式 - 红色充能条
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.9, 0.2, 0.2, 1.0)  # 红色
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	longpress_progress.add_theme_stylebox_override("fill", style)

	# 设置位置和大小
	longpress_progress.size = Vector2(btn.size.x, 6)
	longpress_progress.position = Vector2(0, btn.size.y - 6)

	btn.add_child(longpress_progress)

	# 改变按钮文字为×，设置最小宽度保持按钮大小不变
	btn.custom_minimum_size.x = btn.size.x  # 保持当前宽度
	btn.text = "×"
	btn.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))  # 红色

	# 创建定时器
	longpress_timer = Timer.new()
	longpress_timer.wait_time = 0.1  # 每0.1秒更新一次
	longpress_timer.timeout.connect(_on_longpress_timeout)
	add_child(longpress_timer)
	longpress_timer.start()

	print("[_start_longpress_delete] Started for tag: ", tag_name)


# 长按超时处理
func _on_longpress_timeout() -> void:
	if longpress_progress == null or longpress_button == null:
		_cancel_longpress_delete()
		return

	# 更新进度条
	longpress_progress.value += 0.1

	# 检查是否完成
	if longpress_progress.value >= 3.0:
		# 完成删除
		_delete_tag(longpress_target_tag)
		_cancel_longpress_delete()


# 取消长按
func _cancel_longpress_delete() -> void:
	if longpress_timer:
		longpress_timer.stop()
		longpress_timer.queue_free()
		longpress_timer = null

	# 恢复按钮样式
	if longpress_button and longpress_target_tag != "":
		longpress_button.text = longpress_target_tag
		longpress_button.custom_minimum_size.x = 0  # 恢复默认宽度
		longpress_button.remove_theme_color_override("font_color")

	# 移除进度条
	if longpress_progress:
		longpress_progress.queue_free()
		longpress_progress = null

	longpress_target_tag = ""
	longpress_button = null


# 删除标签
func _delete_tag(tag_name: String) -> void:
	if not tag_data.has(tag_name):
		return

	# 从数据中移除
	tag_data.erase(tag_name)

	# 如果删除的是当前选中的标签，切换到默认标签
	if current_tag == tag_name:
		current_tag = "单人模组"
		custom_tag_scroll_index = -1

	# 重建按钮
	_build_tag_buttons()

	# 保存
	_save_tag_data()

	print("[_delete_tag] Deleted tag: ", tag_name)


# 标题栏输入事件处理（捕获滚轮切换标签显示）
func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# 收集自定义标签
			var custom_tags = []
			for t in tag_data.keys():
				if not t in DEFAULT_TAGS:
					custom_tags.append(t)

			# 如果没有自定义标签，不需要处理
			if custom_tags.size() == 0:
				return

			# 处理滚轮 - 切换第二个位置的显示
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				custom_tag_scroll_index -= 1
				if custom_tag_scroll_index < -1:
					custom_tag_scroll_index = custom_tags.size() - 1
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				custom_tag_scroll_index += 1
				if custom_tag_scroll_index >= custom_tags.size():
					custom_tag_scroll_index = -1

			# 重建按钮显示新的标签
			_build_tag_buttons()

			# 显示提示
			if custom_tag_scroll_index >= 0 and custom_tag_scroll_index < custom_tags.size():
				var current_custom_tag = custom_tags[custom_tag_scroll_index]
				print("[_on_title_bar_input] Scrolled to custom tag: ", current_custom_tag)
			else:
				print("[_on_title_bar_input] Scrolled to default: 联机模组")


# 标签选中处理
func _on_tag_selected(tag_name: String) -> void:
	# 如果已启用整合包，禁止切换标签
	if not active_bundle.is_empty():
		show_notification(translate("bundle_active_tag_locked"), false)
		return

	if current_tag == tag_name:
		return

	# 退出全选模式（避免切换标签后点击复选框触发全选逻辑）
	_all_selected = false
	if batch_select_button:
		batch_select_button.text = translate("select_all")

	# 保存当前标签的启用模组
	_save_current_tag_mods()

	# 切换标签
	current_tag = tag_name

	# 如果切换到默认标签，重置滚轮索引
	if tag_name in DEFAULT_TAGS:
		custom_tag_scroll_index = -1
		_build_tag_buttons()
	# 如果切换到自定义标签，更新滚轮索引到该标签
	else:
		var custom_tags = []
		for t in tag_data.keys():
			if not t in DEFAULT_TAGS:
				custom_tags.append(t)
		var idx = custom_tags.find(tag_name)
		if idx >= 0:
			custom_tag_scroll_index = idx
			_build_tag_buttons()

	# 更新按钮样式
	for name in tag_buttons.keys():
		var btn = tag_buttons[name]
		if name == current_tag:
			btn.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0))
		else:
			btn.remove_theme_color_override("font_color")

	# 加载新标签的启用模组并应用
	_apply_tag_mods()

	# 保存标签数据
	_save_tag_data()

	print("[_on_tag_selected] Switched to tag: ", current_tag)


# 保存当前标签的启用模组
func _save_current_tag_mods() -> void:
	var enabled_ids = []
	for mod_id in enabled_mods.keys():
		if enabled_mods[mod_id]:
			enabled_ids.append(mod_id)
	tag_data[current_tag] = enabled_ids
	print("[_save_current_tag_mods] Saved to ", current_tag, ": ", enabled_ids)


# 应用标签保存的模组
func _apply_tag_mods() -> void:
	var saved_mods = tag_data.get(current_tag, [])
	print("[_apply_tag_mods] Current tag: ", current_tag, ", saved mods: ", saved_mods)

	# 1. 获取所有需要在游戏中启用的模组ID
	var mods_to_enable = []
	for mod in mods:
		var mod_id = mod.get("id", "")
		if mod_id in saved_mods:
			mods_to_enable.append(mod_id)

	# 2. 禁用当前不在标签保存列表中的模组
	for mod_id in enabled_mods.keys():
		if enabled_mods[mod_id] and mod_id not in mods_to_enable:
			# 找到对应的mod数据并禁用
			for mod in mods:
				if mod.get("id") == mod_id:
					ModUtils.disable_mod(mod, game_path)
					break
			enabled_mods[mod_id] = false

	# 3. 启用标签保存的模组
	for mod_id in mods_to_enable:
		# 找到对应的mod数据并启用
		for mod in mods:
			if mod.get("id") == mod_id:
				ModUtils.enable_mod(mod, game_path)
				enabled_mods[mod_id] = true
				break

	# 刷新显示
	update_mod_list_display()

	print("[_apply_tag_mods] Applied mods for ", current_tag, ": ", saved_mods)


# ============================================================
# 收纳盒子管理
# ============================================================

func create_mod_box(name: String = "", color: Color = Color(0.3, 0.62, 1.0)) -> Dictionary:
	var box_id = "box_" + str(Time.get_unix_time_from_system())
	var box_name = name if not name.is_empty() else "新建盒子"
	var box: Dictionary = {
		"id": box_id,
		"name": box_name,
		"color": "#4A9EFF",
		"collapsed": false,
		"mod_ids": []
	}
	# 转换 Color 为十六进制字符串
	box["color"] = "#%02X%02X%02X" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	mod_boxes.append(box)
	_save_mod_organization_data()
	print("[create_mod_box] Created box: ", box_id, " name: ", box_name)
	return box


func delete_mod_box(box_id: String) -> void:
	# 从 mod_boxes 中移除
	for i in range(mod_boxes.size()):
		if mod_boxes[i].get("id") == box_id:
			# 将盒子内的模组移出（变为零散模组）
			# mod_order_override 中的位置由 UI 重建时处理
			mod_boxes.remove_at(i)
			break
	_save_mod_organization_data()
	print("[delete_mod_box] Deleted box: ", box_id)


func rename_mod_box(box_id: String, new_name: String) -> void:
	for box in mod_boxes:
		if box.get("id") == box_id:
			box["name"] = new_name
			break
	_save_mod_organization_data()


func set_mod_box_color(box_id: String, new_color: Color) -> void:
	for box in mod_boxes:
		if box.get("id") == box_id:
			box["color"] = "#%02X%02X%02X" % [int(new_color.r * 255), int(new_color.g * 255), int(new_color.b * 255)]
			break
	_save_mod_organization_data()


func toggle_box_collapsed(box_id: String) -> void:
	for box in mod_boxes:
		if box.get("id") == box_id:
			box["collapsed"] = not box.get("collapsed", false)
			break
	_save_mod_organization_data()


func move_mod_to_position(mod_id: String, from_box: String, to_box: String, index: int) -> void:
	print("[move_mod_to_position] mod=", mod_id, " from=", from_box, " to=", to_box, " index=", index)

	# 从源盒子移除
	if not from_box.is_empty():
		for box in mod_boxes:
			if box.get("id") == from_box:
				var mod_ids: Array = box.get("mod_ids", [])
				if mod_id in mod_ids:
					mod_ids.erase(mod_id)
				break
	# 从 mod_order_override 移除
	if mod_id in mod_order_override:
		mod_order_override.erase(mod_id)

	# 加入目标盒子
	if not to_box.is_empty():
		for box in mod_boxes:
			if box.get("id") == to_box:
				var mod_ids: Array = box.get("mod_ids", [])
				var insert_idx = mini(index, mod_ids.size())
				mod_ids.insert(insert_idx, mod_id)
				break
	else:
		# 加入零散模组列表（插到指定索引位置）
		var insert_idx = mini(index, mod_order_override.size())
		mod_order_override.insert(insert_idx, mod_id)

	_save_mod_organization_data()

	# 重新渲染列表
	_build_mod_list_with_boxes()


# ============================================================
# 新建盒子按钮
# ============================================================

func _build_new_box_button() -> Button:
	var btn = Button.new()
	btn.text = "+ " + translate("new_mod_box")
	btn.tooltip_text = translate("new_mod_box_tip")
	btn.pressed.connect(_on_new_box_pressed)
	btn.add_theme_color_override("font_color", Color(0.4, 0.753, 0.976))  # 模板 accent
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.4, 0.753, 0.976, 0.1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.4, 0.753, 0.976, 0.3)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	return btn


func _on_new_box_pressed() -> void:
	_show_new_box_dialog()


func _show_new_box_dialog() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = translate("new_mod_box")
	dialog.ok_button_text = translate("confirm")
	dialog.cancel_button_text = translate("cancel")

	# 使用 MarginContainer 作为内容容器（Dialog 规范子节点）
	var margin = MarginContainer.new()
	margin.name = "_BoxContent"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# 名称输入
	var name_lbl = Label.new()
	name_lbl.text = translate("box_name")
	vbox.add_child(name_lbl)

	var name_input = LineEdit.new()
	name_input.placeholder_text = "新建盒子"
	name_input.custom_minimum_size = Vector2(300, 0)
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_input)

	# 颜色选择
	var color_lbl = Label.new()
	color_lbl.text = translate("box_color")
	vbox.add_child(color_lbl)

	var color_hbox = HBoxContainer.new()
	color_hbox.add_theme_constant_override("separation", 6)
	var selected_color = Color(0.3, 0.62, 1.0)
	var color_btns: Array = []

	var PRESET_COLORS = [
		Color(0.3, 0.62, 1.0),
		Color(0.3, 0.9, 0.5),
		Color(1.0, 0.5, 0.3),
		Color(1.0, 0.3, 0.4),
		Color(0.9, 0.3, 0.9),
		Color(1.0, 0.85, 0.2),
		Color(0.4, 0.4, 0.4),
		Color(0.2, 0.8, 0.8),
	]
	for i in range(PRESET_COLORS.size()):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(28, 28)
		var s = StyleBoxFlat.new()
		s.bg_color = PRESET_COLORS[i]
		s.set_corner_radius_all(4)
		if i == 0:
			s.border_color = Color(1, 1, 1, 0.8)
			s.border_width_left = 2
			s.border_width_right = 2
			s.border_width_top = 2
			s.border_width_bottom = 2
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_stylebox_override("hover", s)
		btn.add_theme_stylebox_override("pressed", s)
		var idx = i
		btn.pressed.connect(func():
			selected_color = PRESET_COLORS[idx]
			for j in range(color_btns.size()):
				var bs = StyleBoxFlat.new()
				bs.bg_color = PRESET_COLORS[j]
				bs.set_corner_radius_all(4)
				if PRESET_COLORS[j] == selected_color:
					bs.border_color = Color(1, 1, 1, 0.8)
					bs.border_width_left = 2
					bs.border_width_right = 2
					bs.border_width_top = 2
					bs.border_width_bottom = 2
				color_btns[j].add_theme_stylebox_override("normal", bs)
				color_btns[j].add_theme_stylebox_override("hover", bs)
				color_btns[j].add_theme_stylebox_override("pressed", bs)
		)
		color_btns.append(btn)
		color_hbox.add_child(btn)

	vbox.add_child(color_hbox)
	margin.add_child(vbox)
	dialog.add_child(margin)
	add_child(dialog)
	dialog.custom_minimum_size = Vector2(360, 240)

	dialog.confirmed.connect(func():
		var box_name = name_input.text.strip_edges()
		if box_name.is_empty():
			box_name = "新建盒子"
		create_mod_box(box_name, selected_color)
		_build_mod_list_with_boxes()
	)
	dialog.canceled.connect(func():
		dialog.hide()
	)
	dialog.popup_centered(Vector2(360, 240))


# ============================================================
# 收纳盒子信号处理
# ============================================================

func _on_box_collapse_toggled(box_id: String, collapsed: bool) -> void:
	for box in mod_boxes:
		if box.get("id") == box_id:
			box["collapsed"] = collapsed
			break
	_save_mod_organization_data()


func _on_box_rename_requested(box_id: String, new_name: String) -> void:
	rename_mod_box(box_id, new_name)
	# 名称已通过信号更新到盒子节点，这里只需保存


func _on_box_color_changed(box_id: String, new_color: Color) -> void:
	set_mod_box_color(box_id, new_color)


func _on_box_delete_requested(box_id: String) -> void:
	# 找到盒子在列表中的索引
	var box_index = -1
	for i in range(mod_boxes.size()):
		if mod_boxes[i].get("id") == box_id:
			box_index = i
			break

	var popup = PopupMenu.new()
	popup.add_item(translate("delete_box"), 0)
	if box_index > 0:
		popup.add_item(translate("move_box_up"), 1)
	if box_index < mod_boxes.size() - 1:
		popup.add_item(translate("move_box_down"), 2)
	popup.id_pressed.connect(func(id):
		match id:
			0:  # 删除
				delete_mod_box(box_id)
				_build_mod_list_with_boxes()
			1:  # 上移
				if box_index > 0:
					var box = mod_boxes[box_index]
					mod_boxes.remove_at(box_index)
					mod_boxes.insert(box_index - 1, box)
					_save_mod_organization_data()
					_build_mod_list_with_boxes()
			2:  # 下移
				if box_index < mod_boxes.size() - 1:
					var box = mod_boxes[box_index]
					mod_boxes.remove_at(box_index)
					mod_boxes.insert(box_index + 1, box)
					_save_mod_organization_data()
					_build_mod_list_with_boxes()
		popup.queue_free()
	)
	add_child(popup)
	popup.position = DisplayServer.mouse_get_position()
	popup.popup()


func _on_box_move_requested(box_id: String, direction: int) -> void:
	# direction: -1 = 上移, 1 = 下移
	var from_index = -1
	for i in range(mod_boxes.size()):
		if mod_boxes[i].get("id") == box_id:
			from_index = i
			break
	if from_index < 0:
		return

	var new_index = from_index + direction
	if new_index < 0 or new_index >= mod_boxes.size():
		return

	# 交换盒子位置
	var box = mod_boxes[from_index]
	mod_boxes[from_index] = mod_boxes[new_index]
	mod_boxes[new_index] = box
	_save_mod_organization_data()
	_build_mod_list_with_boxes()


func _on_mod_dropped_on_box(box_id: String, mod_id: String, index: int) -> void:
	# 找到模组当前所在盒子
	var from_box = ""
	for box in mod_boxes:
		var mod_ids: Array = box.get("mod_ids", [])
		if mod_id in mod_ids:
			from_box = box.get("id")
			break
	move_mod_to_position(mod_id, from_box, box_id, index)


# ============================================================
# 模组列表渲染（完全代码构建，匹配 HTML 模板）
# ============================================================

# 模板颜色常量
const _COL_BG_NORMAL    = Color(1, 1, 1, 0.03)
const _COL_BG_HOVER     = Color(1, 1, 1, 0.06)
const _COL_BG_SELECTED  = Color(0.4, 0.753, 0.976, 0.15)
const _COL_ACCENT       = Color(0.4, 0.753, 0.976)
const _COL_MUTED        = Color(0.545, 0.596, 0.627)
const _COL_TEXT         = Color(0.898, 0.898, 0.898)
const _COL_BG_DARK     = Color(0.082, 0.122, 0.18)
const _COL_BORDER       = Color(0.337, 0.514, 0.675, 0.15)

# 列表内间距（模板: .mod-list { padding: 10px }, .mod-item { padding: 12px 14px }）
const _LIST_PADDING = 10
const _ITEM_GAP     = 6

# 列表顶部 spacer 引用
var _list_top_spacer: Control
var _list_bottom_spacer: Control

func _build_mod_list_with_boxes() -> void:
	if mod_list_container == null:
		mod_list_container = find_child_node(self, "ModList")
		if mod_list_container == null:
			print("[_build_mod_list_with_boxes] mod_list_container is null!")
			return

	for child in mod_list_container.get_children():
		child.queue_free()

	# 1. 顶部间距
	_list_top_spacer = Control.new()
	_list_top_spacer.name = "_TopSpacer"
	_list_top_spacer.custom_minimum_size.y = _LIST_PADDING
	_list_top_spacer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mod_list_container.add_child(_list_top_spacer)

	# 2. 标题栏
	var title_section = _build_list_title_section()
	mod_list_container.add_child(title_section)

	# 3. 分隔线（模板: rgba(86,131,172,0.15) 细线）
	var sep = HSeparator.new()
	sep.name = "_TitleSep"
	sep.custom_minimum_size.y = 1
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = Color(0.337, 0.514, 0.675, 0.15)
	sep.add_theme_stylebox_override("separator", sep_style)
	sep.add_theme_stylebox_override("bg", sep_style)
	mod_list_container.add_child(sep)

	# 4. 列表级拖放区域
	var drop_zone = Control.new()
	drop_zone.name = "_ListDropZone"
	drop_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_zone.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	drop_zone.custom_minimum_size.y = 0
	drop_zone.mouse_filter = Control.MOUSE_FILTER_PASS

	# 5. 渲染盒子（放在 drop_zone 之前，这样 drop_zone 在最底部但不影响布局）
	var boxed_ids: Dictionary = {}
	for box in mod_boxes:
		for mid in box.get("mod_ids", []):
			boxed_ids[mid] = true

	var rendered_box_ids: Array = []
	var loose_mods: Array = []

	for mod_id in mod_order_override:
		if boxed_ids.get(mod_id, false):
			for box in mod_boxes:
				var b_ids: Array = box.get("mod_ids", [])
				if mod_id in b_ids:
					if not (box.get("id") in rendered_box_ids):
						rendered_box_ids.append(box.get("id"))
						_build_mod_box_item(box)
					break
		else:
			for m in displayed_mods:
				if m.get("id") == mod_id:
					loose_mods.append(m)
					break

	for m in loose_mods:
		_add_mod_item_row(m, "")

	for box in mod_boxes:
		if not (box.get("id") in rendered_box_ids) and box.get("mod_ids", []).is_empty():
			_build_mod_box_item(box)

	var ordered_set: Dictionary = {}
	for mid in mod_order_override:
		ordered_set[mid] = true
	for m in displayed_mods:
		var mid = m.get("id", "")
		if not mid.is_empty() and not ordered_set.get(mid, false):
			_add_mod_item_row(m, "")

	# 6. 底部间距
	_list_bottom_spacer = Control.new()
	_list_bottom_spacer.name = "_BottomSpacer"
	_list_bottom_spacer.custom_minimum_size.y = _LIST_PADDING
	_list_bottom_spacer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mod_list_container.add_child(_list_bottom_spacer)

	# 7. 拖放区域（最后添加，渲染在最上层，最小高度不抢占布局空间）
	mod_list_container.add_child(drop_zone)


func _build_list_title_section() -> Control:
	var hbox = HBoxContainer.new()
	hbox.name = "_ListTitle"
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.custom_minimum_size.y = 44  # 足够容纳标签按钮文字
	hbox.add_theme_constant_override("separation", 10)

	# 标签筛选栏（占据左侧可扩展空间）
	var tags_scroll = ScrollContainer.new()
	tags_scroll.name = "_TagsScroll"
	tags_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tags_scroll.size_flags_stretch_ratio = 1.0
	tags_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tags_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(tags_scroll)

	tag_container = HBoxContainer.new()
	tag_container.name = "_TagContainer"
	tag_container.add_theme_constant_override("separation", 8)
	tags_scroll.add_child(tag_container)
	_build_tag_buttons()

	# 模组计数（右对齐）
	var count_lbl = Label.new()
	count_lbl.name = "_CountLabel"
	count_lbl.text = "%d 个模组" % displayed_mods.size()
	count_lbl.add_theme_color_override("font_color", _COL_MUTED)
	count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(count_lbl)

	# 新建盒子按钮（右对齐）
	if enable_mod_drag:
		var new_box_btn = _build_new_box_button()
		hbox.add_child(new_box_btn)

	return hbox


func _build_mod_box_item(box_data: Dictionary) -> void:
	var box_id = box_data.get("id", "")
	var box_name = box_data.get("name", "盒子")
	var box_color = Color(box_data.get("color", "#4A9EFF"))
	var is_collapsed = box_data.get("collapsed", false)
	var box_mod_ids: Array = box_data.get("mod_ids", [])

	# 盒子根节点
	var box_root = PanelContainer.new()
	box_root.name = "ModBox_" + box_id
	box_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box_root.custom_minimum_size.y = 40
	box_root.add_theme_stylebox_override("normal", _make_box_bg_style())
	box_root.add_theme_stylebox_override("hover", _make_box_bg_style(Color(1,1,1,0.04)))
	box_root.mouse_filter = Control.MOUSE_FILTER_STOP
	mod_list_container.add_child(box_root)

	# HBox 布局（盒子标题栏，40px 高，带顶部/底部内边距）
	var box_hbox = HBoxContainer.new()
	box_hbox.name = "_BoxHeader"
	box_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box_hbox.custom_minimum_size.y = 40
	box_hbox.add_theme_constant_override("separation", 8)
	box_root.add_child(box_hbox)

	# 左侧色条
	var left_bar = ColorRect.new()
	left_bar.custom_minimum_size = Vector2(3, 0)
	left_bar.color = box_color
	left_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box_hbox.add_child(left_bar)

	# 折叠按钮
	var collapse_btn = Button.new()
	collapse_btn.name = "_CollapseBtn"
	collapse_btn.text = "v" if not is_collapsed else ">"
	collapse_btn.custom_minimum_size = Vector2(24, 24)
	collapse_btn.flat = true
	collapse_btn.add_theme_color_override("font_color", _COL_MUTED)
	collapse_btn.add_theme_color_override("font_hover_color", _COL_ACCENT)
	collapse_btn.pressed.connect(func(): _on_box_collapse_clicked(box_id, not is_collapsed))
	box_hbox.add_child(collapse_btn)

	# 盒子名称
	var name_lbl = Label.new()
	name_lbl.text = box_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", _COL_TEXT)
	box_hbox.add_child(name_lbl)

	# 数量
	var count_lbl = Label.new()
	count_lbl.text = "%d 个" % box_mod_ids.size()
	count_lbl.add_theme_color_override("font_color", _COL_MUTED)
	count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box_hbox.add_child(count_lbl)

	# 删除按钮
	var del_btn = Button.new()
	del_btn.text = "x"
	del_btn.custom_minimum_size = Vector2(24, 24)
	del_btn.flat = true
	del_btn.add_theme_color_override("font_color", _COL_MUTED)
	del_btn.add_theme_color_override("font_hover_color", Color(1, 0.3, 0.3))
	del_btn.pressed.connect(func(): _on_box_delete_clicked(box_id))
	box_hbox.add_child(del_btn)

	# 内部模组列表（用 MarginContainer 提供 16px 左缩进）
	var items_margin = MarginContainer.new()
	items_margin.name = "_BoxItemsMargin"
	items_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items_margin.add_theme_constant_override("margin_left", 16)
	items_margin.add_theme_constant_override("margin_right", 8)
	items_margin.add_theme_constant_override("margin_top", 6)
	items_margin.add_theme_constant_override("margin_bottom", 6)
	box_root.add_child(items_margin)

	var items_vbox = VBoxContainer.new()
	items_vbox.name = "_BoxItemsVBox"
	items_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_vbox.add_theme_constant_override("separation", _ITEM_GAP)
	items_margin.add_child(items_vbox)
	items_vbox.visible = not is_collapsed

	box_root.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			_on_box_collapse_clicked(box_id, not is_collapsed)
	)

	for mod_id in box_mod_ids:
		for m in displayed_mods:
			if m.get("id") == mod_id:
				_make_mod_item_row(m, box_id, items_vbox)
				break


func _make_box_bg_style(hover: Color = Color(1,1,1,0.02)) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = hover
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	return s


func _on_box_collapse_clicked(box_id: String, collapsed: bool) -> void:
	var box_root_name = "ModBox_" + box_id
	var box_root = find_child_node(mod_list_container, box_root_name)
	if box_root:
		var items_vbox = find_child_node(box_root, "_BoxItemsVBox")
		if items_vbox:
			items_vbox.visible = not collapsed
		var collapse_btn = find_child_node(box_root, "_CollapseBtn")
		if collapse_btn:
			collapse_btn.text = "v" if not collapsed else ">"
	for box in mod_boxes:
		if box.get("id") == box_id:
			box["collapsed"] = collapsed
			break
	_save_mod_organization_data()


func _on_box_delete_clicked(box_id: String) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = "确定删除盒子？盒子内的模组会移至零散模组区域。"
	dialog.confirmed.connect(func():
		var box_mod_ids: Array = []
		for box in mod_boxes:
			if box.get("id") == box_id:
				box_mod_ids = box.get("mod_ids", [])
				mod_boxes.erase(box)
				break
		for mid in box_mod_ids:
			if not mod_order_override.has(mid):
				mod_order_override.append(mid)
		_save_mod_organization_data()
		_build_mod_list_with_boxes()
	)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()


func _add_mod_item_row(mod: Dictionary, box_id: String) -> void:
	_make_mod_item_row(mod, box_id)  # _make_mod_item_row 内部已加入树

func _make_mod_item_row(mod: Dictionary, box_id: String, target_container: Node = null) -> ModItem:
	var item = ModItem.new()
	item.name = "ModItem_" + mod.get("id", "")
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# 加入目标容器（默认为 mod_list_container）
	var container = target_container if target_container != null else mod_list_container
	container.add_child(item)
	# 构建视觉（setup 需要节点已创建）
	item._build_visual()

	var mod_id = mod.get("id", "")
	var is_enabled = enabled_mods.get(mod_id, false)
	item.setup(mod, is_enabled)
	item.box_id = box_id
	item.on_toggled_callback = _on_mod_toggled
	item.on_selected_callback = _on_mod_selected
	item.set_multi_select_mode(multi_select_mode)
	item.set_batch_toggle_callback(_on_mod_batch_toggled)
	mod_items[mod_id] = item
	return item



func reorder_box(box_id: String, new_index: int) -> void:
	var from_index = -1
	for i in range(mod_boxes.size()):
		if mod_boxes[i].get("id") == box_id:
			from_index = i
			break

	if from_index < 0 or from_index == new_index:
		return

	var box = mod_boxes[from_index]
	mod_boxes.remove_at(from_index)
	var insert_idx = mini(new_index, mod_boxes.size())
	mod_boxes.insert(insert_idx, box)
	_save_mod_organization_data()
	_build_mod_list_with_boxes()


# 新建标签
func _on_add_tag_pressed() -> void:
	# 创建输入对话框（使用AcceptDialog）
	var dialog = AcceptDialog.new()
	dialog.title = translate("new_tag_title")
	dialog.size = Vector2i(300, 150)

	# 创建输入框和布局
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -50

	var label = Label.new()
	label.text = translate("new_tag_name")
	vbox.add_child(label)

	var input = LineEdit.new()
	input.placeholder_text = translate("new_tag_placeholder")
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(input)

	dialog.add_child(vbox)

	# 添加对话框到场景
	add_child(dialog)

	# 连接确认信号
	dialog.confirmed.connect(func(): _create_new_tag(input.text, dialog))
	dialog.canceled.connect(func(): dialog.queue_free())

	# 禁用关闭按钮（X）的功能，让它和取消按钮一样
	dialog.close_requested.connect(func(): dialog.queue_free())

	# 设置焦点
	dialog.popup_centered(Vector2i(300, 150))
	input.grab_focus()


# 创建新标签
func _create_new_tag(tag_name: String, dialog: AcceptDialog) -> void:
	if tag_name.is_empty():
		return

	if tag_data.has(tag_name):
		return  # 已存在

	# 添加新标签
	tag_data[tag_name] = []

	# 更新滚轮索引到新创建的标签
	var custom_tags = []
	for t in tag_data.keys():
		if not t in DEFAULT_TAGS:
			custom_tags.append(t)
	custom_tag_scroll_index = custom_tags.find(tag_name)

	# 重建按钮
	_build_tag_buttons()

	# 保存
	_save_tag_data()

	dialog.queue_free()
	print("[_create_new_tag] Created new tag: ", tag_name)


# 初始化UI
func init_ui() -> void:
	# 设置窗口大小和最小尺寸
	var window = get_window()
	var window_size = config.get_value("window", "width", 800)
	var window_height = config.get_value("window", "height", 700)
	window.size = Vector2i(window_size, window_height)

	# 设置最小窗口尺寸
	window.min_size = Vector2i(800, 600)

	# 恢复最大化状态（如果之前保存了）
	var was_maximized = config.get_value("window", "maximized", false)
	if was_maximized:
		window.mode = Window.MODE_MAXIMIZED

	# ===== 应用Steam×Windows 11混合风格主题 =====
	_apply_steam_theme()

	# 获取UI节点引用
	mod_search = find_child_node(self, "TopBarBg/TopBar/SearchBox")
	search_button = find_child_node(self, "SearchBtn")
	install_mod_button = find_child_node(self, "InstallModBtn")
	uninstall_mod_button = find_child_node(self, "UninstallModBtn")
	batch_enable_button = find_child_node(self, "BatchEnableBtn")
	batch_uninstall_button = find_child_node(self, "BatchUninstallBtn")
	batch_select_button = find_child_node(self, "BatchSelectBtn")
	refresh_mods_button = find_child_node(self, "RefreshModsBtn")
	sort_option = find_child_node(self, "SortOption")
	category_filter = find_child_node(self, "CategoryFilter")
	mod_list_container = find_child_node(self, "ModList")

	# 获取模组详情面板节点
	mod_details_panel = find_child_node(self, "ModDetailsPanel")
	mod_details_name = find_child_node(self, "NameLabel")
	mod_details_author = find_child_node(self, "AuthorLabel")
	mod_details_version = find_child_node(self, "VersionLabel")
	mod_details_source = find_child_node(self, "SourceLabel")
	mod_details_type = find_child_node(self, "TypeLabel")
	mod_details_desc = find_child_node(self, "DescLabel")
	mod_details_dep = find_child_node(self, "DepLabel")
	mod_details_vbox = find_child_node(self, "DetailsVBox")
	mod_note_label = find_child_node(self, "ModNoteLabel")
	mod_note_separator = find_child_node(self, "ModNoteSeparator")
	mod_note_edit_btn = find_child_node(self, "ModNoteEditBtn")

	# 获取加载面板节点
	loading_panel = find_child_node(self, "LoadingPanel")
	loading_label = find_child_node(self, "LoadingLabel")
	loading_spinner = find_child_node(self, "LoadingSpinner")
	loading_progress = find_child_node(self, "LoadingProgress")

	# 连接UI信号
	if mod_search:
		mod_search.text_changed.connect(_on_search_text_changed)
		mod_search.placeholder_text = translate("search_hint")
	if search_button:
		search_button.pressed.connect(_on_search_button_pressed)
		search_button.text = translate("search")

	if install_mod_button:
		install_mod_button.pressed.connect(_on_install_mod_pressed)
		install_mod_button.text = translate("install_mod")

	if uninstall_mod_button:
		uninstall_mod_button.pressed.connect(_on_uninstall_mod_pressed)
		uninstall_mod_button.text = translate("uninstall_mod")

	if batch_enable_button:
		batch_enable_button.pressed.connect(_on_batch_enable_pressed)
		batch_enable_button.text = translate("batch_enable")

	if batch_uninstall_button:
		batch_uninstall_button.pressed.connect(_on_batch_disable_pressed)
		batch_uninstall_button.text = translate("batch_uninstall")

	if batch_select_button:
		batch_select_button.pressed.connect(_on_batch_select_pressed)
		batch_select_button.text = translate("select_all")
	if refresh_mods_button:
		refresh_mods_button.pressed.connect(_on_refresh_mods_pressed)
		refresh_mods_button.text = translate("refresh")
	if sort_option:
		# 添加排序选项
		sort_option.clear()
		sort_option.add_item(translate("sort_by_name"))  # 名称排序
		sort_option.add_item(translate("sort_by_time"))    # 安装时间
		sort_option.add_item(translate("sort_by_version"))  # 版本
		sort_option.add_item(translate("sort_by_author"))  # 作者
		sort_option.selected = 0  # 默认名称排序
		sort_option.item_selected.connect(_on_sort_option_selected)
	if category_filter:
		# 添加分类选项
		category_filter.clear()
		category_filter.add_item(translate("all"))  # 全部
		category_filter.add_item(translate("gameplay_mods"))  # 玩法
		category_filter.add_item(translate("cosmetic_mods"))  # 外观
		category_filter.selected = 0  # 默认全部
		category_filter.item_selected.connect(_on_category_filter_selected)

	# 连接分类标签信号
	var category_tags = find_child_node(self, "TopBarBg/TopBar/CategoryTags")
	if category_tags:
		for ch in category_tags.get_children():
			if ch is Button:
				ch.button_up.connect(_on_category_tag_clicked.bind(ch.name))

	# 连接启动模式信号
	var start_modes = find_child_node(self, "ModStartModes")
	if start_modes:
		for ch in start_modes.get_children():
			if ch is Button:
				ch.button_up.connect(_on_start_mode_clicked.bind(ch.name))

	# 获取存档UI节点引用
	save_list_container = find_child_node(self, "SaveList")
	print("[init_ui] save_list_container: ", save_list_container)
	if save_list_container:
		print("[init_ui] SaveList children count: ", save_list_container.get_child_count())
		print("[init_ui] SaveList parent: ", save_list_container.get_parent())
		print("[init_ui] SaveList parent type: ", save_list_container.get_parent().get_class())
	import_save_button = find_child_node(self, "ImportSaveBtn")
	export_save_button = find_child_node(self, "ExportSaveBtn")
	backup_save_button = find_child_node(self, "BackupSaveBtn")
	restore_save_button = find_child_node(self, "RestoreSaveBtn")
	overwrite_save_button = find_child_node(self, "OverwriteSaveBtn")

	# 获取存档详情面板节点
	save_details_panel = find_child_node(self, "SaveDetailsPanel")
	save_details_name = find_child_node(self, "NameLabel")
	save_details_date = find_child_node(self, "DateLabel")
	save_details_size = find_child_node(self, "SizeLabel")
	save_details_type = find_child_node(self, "TypeLabel")
	save_profile_selector = find_child_node(self, "ProfileSelector")

	# 初始隐藏详情面板
	if save_details_panel:
		save_details_panel.visible = false

	# 配置Profile选择器
	if save_profile_selector:
		save_profile_selector.clear()
		save_profile_selector.add_item("Profile 1", 1)
		save_profile_selector.add_item("Profile 2", 2)
		save_profile_selector.add_item("Profile 3", 3)
		save_profile_selector.selected = 0
		save_profile_selector.item_selected.connect(_on_profile_selector_changed)

	# 获取左侧面板和折叠按钮
	save_left_panel = find_child_node(self, "LeftPanelWrapper")
	save_collapse_btn = find_child_node(self, "CollapseBtn")
	char_stats_vbox = find_child_node(self, "CharStatsVBox")
	save_list_container = find_child_node(self, "SaveList")

	# 配置折叠按钮
	if save_collapse_btn:
		save_collapse_btn.pressed.connect(_on_save_collapse_pressed)

	# 禁用存档列表水平滚动条
	var save_scroll = find_child_node(self, "SaveScroll")
	if save_scroll:
		save_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	# 连接存档UI信号
	if import_save_button:
		import_save_button.pressed.connect(_on_import_save_pressed)
		import_save_button.text = translate("import")

	if export_save_button:
		export_save_button.pressed.connect(_on_export_save_pressed)
		export_save_button.text = translate("export")

	if backup_save_button:
		backup_save_button.pressed.connect(_on_backup_save_pressed)
		backup_save_button.text = translate("backup")

	if restore_save_button:
		restore_save_button.pressed.connect(_on_restore_save_pressed)
		restore_save_button.text = translate("restore")

	if overwrite_save_button:
		overwrite_save_button.pressed.connect(_on_overwrite_save_pressed)
		overwrite_save_button.text = translate("overwrite")

	# 设置Tab标题
	if tab_container:
		# 检查是否已经有TutorialTab（避免重复创建）
		var tab_count = tab_container.get_tab_count()
		var has_tutorial_tab = false
		for i in range(tab_count):
			if tab_container.get_tab_title(i) == translate("tutorial"):
				has_tutorial_tab = true
				break

		# 更新所有Tab标题
		_update_tab_titles()

		# 连接标签页切换信号
		tab_container.tab_changed.connect(_on_tab_changed)

	# Nexus模组在 _ready() 中已经延迟初始化，这里不再重复调用

	# 初始化启动游戏按钮
	_init_launch_buttons()


# 初始化启动游戏按钮（显示在每个标签页右下角）
func _init_launch_buttons() -> void:
	var LAUNCH_BUTTON_SCENE = preload("res://ui/launch_button.tscn")
	var LAUNCH_BAR_SCENE = preload("res://ui/launch_bar.tscn")

	# 为每个标签页添加启动按钮
	var tabs = ["ModTab", "BundleTab", "SaveTab", "NexusTab", "DownloadTab", "SettingsTab"]
	for tab_name in tabs:
		var tab = find_child_node(self, tab_name)
		if not tab:
			continue
		# ModTab使用Tesla风格的底部启动条
		if tab_name == "ModTab":
			var footer = find_child_node(tab, "Footer")
			if footer:
				var placeholder = find_child_node(footer, "LaunchBarPlaceholder")
				if placeholder:
					var launch_bar = LAUNCH_BAR_SCENE.instantiate()
					launch_bar.name = "LaunchBar"
					# 档位字母 -> 启动模式字符串映射
					launch_bar.launch_mode_pressed.connect(_map_gear_to_mode)
					placeholder.add_child(launch_bar)
					print("[init_ui] Added LaunchBar to ", tab_name)
		else:
			var btn = LAUNCH_BUTTON_SCENE.instantiate()
			btn.name = "LaunchButton"
			btn.anchor_left = 1.0
			btn.anchor_top = 1.0
			btn.anchor_right = 1.0
			btn.anchor_bottom = 1.0
			btn.offset_left = -60
			btn.offset_top = -60
			btn.offset_right = -12
			btn.offset_bottom = -12
			tab.add_child(btn)
			btn.launch_mode_pressed.connect(_on_launch_mode_pressed)
			print("[init_ui] Added LaunchButton to ", tab_name)


# 初始化N网模组页面
var nexus_mods_ui: Control
var _nexus_initialized: bool = false  # Nexus模组页面是否已初始化
var nexus_mods_instance: Control  # 实际的 NexusMods 控件实例
var nexus_api_key_edit: LineEdit
var nexus_validate_btn: Button
var nexus_status_label: Label
var nexus_api: NexusAPI  # 独立的 Nexus API 实例，用于下载功能

# 本地HTTP服务器（浏览器扩展通信）
var local_server: LocalServer
var _api_bridge: ApiBridge  # API 桥接（Web UI 通信）

# 更新检查器
var update_checker: UpdateChecker = null
var update_check_url_gitee: String = "https://gitee.com/ckccbaize/STS2_modmanager/raw/class/version.json"
var update_check_url_github: String = "https://raw.githubusercontent.com/ckccbaize/STS2_modmanager/class/version.json"
var pending_update_info: Dictionary = {}

func _init_local_server() -> void:
	"""初始化并启动本地HTTP服务器用于浏览器扩展通信"""
	print("[_init_local_server] Creating local server...")
	local_server = LocalServer.new()

	# 从配置加载服务器端口
	var server_port = config.get_value("server", "port", 8765)
	local_server.set_port(server_port)
	print("[_init_local_server] Server port set to: ", server_port)

	# 创建独立的 Nexus API 实例
	nexus_api = NexusAPI.new()
	local_server.set_nexus_api(nexus_api)
	print("[_init_local_server] Created standalone NexusAPI instance")

	# 从配置加载 API Key
	var saved_api_key = config.get_value("nexus", "api_key", "")
	if not saved_api_key.is_empty():
		nexus_api.set_api_key(saved_api_key)
		print("[_init_local_server] Loaded API key from config")

	# 连接下载请求信号
	local_server.download_request_received.connect(_on_server_download_request)

	# 初始化 API 桥接（Web UI 通信）
	_api_bridge = ApiBridge.new()
	_api_bridge.set_handler(_api_handle_request)
	local_server.set_api_bridge(_api_bridge)

	# 立即启动服务器（不需要等待 Nexus UI 初始化）
	_start_local_server_early()


# ========== Steam×Windows 11 混合风格主题 ==========
func _apply_steam_theme() -> void:
	"""应用Steam×Windows 11混合风格主题"""
	print("[_apply_steam_theme] Applying Steam theme...")

	# 窗口背景 (模板: linear-gradient #1b2838 → #12171e)
	var window_bg = find_child_node(self, "WindowBg")
	if window_bg:
		window_bg.color = Color(0.071, 0.153, 0.212, 1.0)  # #12171e

	# 窗口边框
	_apply_window_border_theme()

	# TabContainer 样式（Godot内置标签栏）
	var tab_container = find_child_node(self, "TabContainer")
	if tab_container:
		# 标签栏字体颜色
		tab_container.add_theme_color_override("font_color", Color(0.545, 0.596, 0.627))   # #8b98a0
		tab_container.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))     # #fff
		tab_container.add_theme_color_override("font_hover_color", Color(0.78, 0.835, 0.878)) # #c7d5e0
		tab_container.add_theme_color_override("font_selected_color", Color(1, 1, 1, 1))     # #fff
		# 标签栏背景
		var tc_style = StyleBoxFlat.new()
		tc_style.bg_color = Color(0.082, 0.122, 0.18, 0.8)
		tc_style.border_width_bottom = 1
		tc_style.border_color = Color(0.337, 0.514, 0.675, 0.15)
		tab_container.add_theme_stylebox_override("tabbar_background", tc_style)

	# 应用TopBar样式
	_apply_topbar_theme()

	# 应用模组列表样式
	_apply_modlist_theme()

	# 应用分类标签样式
	_apply_category_tags_theme()

	# 应用启动模式样式
	_apply_start_modes_theme()

	# 应用模组详情样式
	_apply_moddetails_theme()

	# 应用底部栏样式
	_apply_footer_theme()

	# 应用按钮样式
	_apply_button_theme()

	print("[_apply_steam_theme] Steam theme applied")


# ════════════════════════════════════════════════════════════════
#  内嵌浏览器集成
# ════════════════════════════════════════════════════════════════

var webview_control: Control = null  # 内嵌浏览器控件
var config_panel: CanvasLayer = null  # 配置面板

## 隐藏原版 UI，显示 WebView
func _hide_legacy_ui_and_show_webview() -> void:
	print("[WebView] 正在初始化内嵌浏览器...")

	# 1. 隐藏原版 TabContainer UI
	var tab_container = find_child_node(self, "TabContainer")
	if tab_container:
		tab_container.visible = false
		print("[WebView] 已隐藏原版 TabContainer")

	# 2. 加载 WebUiMain 场景并添加到场景树
	var webui_scene = load("res://scenes/webui_main.tscn")
	if webui_scene:
		print("[WebView] 成功加载 WebUiMain 场景")
		var webui_instance = webui_scene.instantiate()
		if webui_instance:
			add_child(webui_instance)
			webview_control = webui_instance
			print("[WebView] WebUiMain 场景已添加")
		else:
			printerr("[WebView] 无法实例化 WebUiMain 场景！")
	else:
		printerr("[WebView] 无法加载 WebUiMain 场景！")

	# 3. 隐藏 Footer
	var footer = find_child_node(self, "Footer")
	if footer:
		footer.visible = false
		print("[WebView] 已隐藏 Footer")

	# 4. 创建配置面板
	_create_config_panel()

func _create_config_panel() -> void:
	"""创建配置面板"""
	print("[ConfigPanel] 创建配置面板...")
	var panel = preload("res://ui/config_panel.gd").new()
	panel.name = "ConfigPanel"
	add_child(panel)
	config_panel = panel
	panel.setup(local_server, update_checker, config)
	panel.closed.connect(_on_config_panel_closed)
	print("[ConfigPanel] 配置面板已创建")

func _on_config_panel_closed() -> void:
	"""配置面板关闭"""
	print("[ConfigPanel] 配置面板已关闭")


# ════════════════════════════════════════════════════════════════
#  Web API 处理函数（在主线程执行）
# ════════════════════════════════════════════════════════════════

## API 请求总分发器（由 ApiBridge 在主线程调用）
## request_id 由 api_bridge 生成并传入，用于 select_directory 等需要信号回调的协程场景
func _api_handle_request(type: String, params: Dictionary, request_id: String = "") -> Dictionary:
	# 同步请求：立即返回结果（异步请求如 select_directory 返回空字典，结果通过 set_result 写入）
	match type:
		"scan_mods": return _api_scan_mods(params)
		"get_mod": return _api_get_mod(params)
		"toggle_mod": return _api_toggle_mod(params)
		"install_mod": return _api_install_mod(params)
		"uninstall_mod": return _api_uninstall_mod(params)
		"batch_enable_mods": return _api_batch_enable_mods(params)
		"batch_disable_mods": return _api_batch_disable_mods(params)
		"get_mod_notes": return _api_get_mod_notes(params)
		"save_mod_notes": return _api_save_mod_notes(params)
		"save_tag_data": return _api_save_tag_data(params)
		"save_mod_organization": return _api_save_mod_organization(params)
		"get_mod_organization": return _api_get_mod_organization(params)
		"scan_saves": return _api_scan_saves(params)
		"import_save": return _api_import_save(params)
		"export_save": return _api_export_save(params)
		"backup_save": return _api_backup_save(params)
		"restore_save": return _api_restore_save(params)
		"get_save_backups": return _api_get_save_backups(params)
		"overwrite_save": return _api_overwrite_save(params)
		"delete_save": return _api_delete_save(params)
		"sync_cloud": return _api_sync_cloud(params)
		"get_save_details": return _api_get_save_details(params)
		"scan_bundles": return _api_scan_bundles(params)
		"enable_bundle": return _api_enable_bundle(params)
		"disable_bundle": return _api_disable_bundle(params)
		"delete_bundle": return _api_delete_bundle(params)
		"import_bundle": return _api_import_bundle(params)
		"import_bundle_local": return _api_import_bundle_local(params)
		"save_bundle": return _api_save_bundle(params)
		"update_bundle_presets": return _api_update_bundle_presets(params)
		"export_bundle": return _api_export_bundle(params)
		"export_current_bundle": return _api_export_current_bundle(params)
		"apply_bundle_preset": return _api_apply_bundle_preset(params)
		"get_settings": return _api_get_settings(params)
		"set_settings": return _api_set_settings(params)
		"detect_game_path": return _api_detect_game_path(params)
		"detect_save_path": return _api_detect_save_path(params)
		"get_downloads": return _api_get_downloads(params)
		"pause_download": return _api_pause_download(params)
		"resume_download": return _api_resume_download(params)
		"cancel_download": return _api_cancel_download(params)
		"launch_game": return _api_launch_game(params)
		_: return {"code": 404, "data": {"error": "Unknown request type: " + type}}


# ── 模组 API ───────────────────────────────────────────────────

func _api_scan_mods(_params: Dictionary) -> Dictionary:
	# 确保模组列表已加载
	if mods.is_empty():
		load_mods()

	var mods_array: Array = []
	for mod_data in mods:
		var m = mod_data.duplicate()
		# 移除内部路径字段
		m.erase("path")
		mods_array.append(m)

	# 构建有效模组 ID 集合
	var valid_mod_ids = {}
	for mod_data in mods:
		if mod_data.has("id"):
			valid_mod_ids[mod_data["id"]] = true

	# 清理 enabled_mods 中的无效条目并返回
	var enabled_list: Array = []
	var cleaned = false
	var keys_to_remove = []
	for mod_id in enabled_mods:
		# 清理以 .zip 结尾的无效 ID
		if mod_id.to_lower().ends_with(".zip"):
			keys_to_remove.append(mod_id)
			cleaned = true
		# 清理不存在于 mods 数组中的 ID
		elif not valid_mod_ids.has(mod_id):
			keys_to_remove.append(mod_id)
			cleaned = true
		# 只添加启用的模组
		elif enabled_mods[mod_id]:
			enabled_list.append(mod_id)

	# 如果有清理，保存并应用更改
	if cleaned:
		for mod_id in keys_to_remove:
			enabled_mods.erase(mod_id)
		_save_enabled_mods()
		print("[_api_scan_mods] Cleaned ", keys_to_remove.size(), " invalid mod IDs from enabled_mods")

	return {"code": 200, "data": {
		"mods": mods_array,
		"enabled": enabled_list,
		"tag_data": tag_data,
		"current_tag": current_tag
	}}


func _api_get_mod(params: Dictionary) -> Dictionary:
	var mod_id: String = params.get("mod_id", "")
	for mod_data in mods:
		if mod_data.get("id", "") == mod_id:
			var m = mod_data.duplicate()
			m.erase("path")
			var is_enabled: bool = enabled_mods.get(mod_id, false)
			return {"code": 200, "data": {"mod": m, "enabled": is_enabled}}
	return {"code": 404, "data": {"error": "Mod not found"}}


func _api_toggle_mod(params: Dictionary) -> Dictionary:
	var mod_id: String = params.get("mod_id", "")
	var enable: bool = params.get("enable", true)

	# 查找模组数据
	var mod_data: Dictionary = {}
	for m in mods:
		if m.get("id", "") == mod_id:
			mod_data = m
			break

	if mod_data.is_empty():
		return {"code": 404, "data": {"success": false, "message": "Mod not found"}}

	if enable:
		var success = ModUtils.enable_mod(mod_data, game_path)
		if success:
			enabled_mods[mod_id] = true
			_save_enabled_mods()
			return {"code": 200, "data": {"success": true, "message": "Mod enabled"}}
		return {"code": 500, "data": {"success": false, "message": "Failed to enable mod"}}
	else:
		var success = ModUtils.disable_mod(mod_data, game_path)
		if success:
			enabled_mods.erase(mod_id)
			_save_enabled_mods()
			return {"code": 200, "data": {"success": true, "message": "Mod disabled"}}
		return {"code": 500, "data": {"success": false, "message": "Failed to disable mod"}}


func _api_install_mod(params: Dictionary) -> Dictionary:
	var filename: String = params.get("filename", "")
	var data_base64: String = params.get("data_base64", "")

	if data_base64.is_empty():
		return {"code": 400, "data": {"success": false, "message": "No file data"}}

	# 解码 base64 并写入临时文件
	var bytes = Marshalls.base64_to_raw(data_base64)
	var temp_path = get_base_path().path_join("temp_upload_" + filename)
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"code": 500, "data": {"success": false, "message": "Failed to write temp file"}}
	file.store_buffer(bytes)
	file.close()

	# 调用现有安装函数
	var result = ModUtils.install_mod(temp_path, "", "", mod_required_fields)

	# 清理临时文件
	DirAccess.remove_absolute(temp_path)

	if result.get("success", false):
		load_mods()  # 重新加载模组列表
		var mod_info = result.get("mod_info", {})
		mod_info.erase("path")
		return {"code": 200, "data": {
			"success": true,
			"message": "Mod installed successfully",
			"mod_info": mod_info
		}}
	elif result.get("has_conflicts", false):
		return {"code": 200, "data": {
			"success": false,
			"has_conflicts": true,
			"conflicts": result.get("conflicts", []),
			"message": result.get("message", "Conflicts detected")
		}}
	else:
		var response_data = {
			"success": false,
			"message": result.get("message", "Installation failed")
		}
		# 保留 error_type 字段以便前端识别错误类型
		if result.has("error_type"):
			response_data["error_type"] = result.get("error_type")
		if result.has("bundle_name"):
			response_data["bundle_name"] = result.get("bundle_name")
		return {"code": 200, "data": response_data}


func _api_uninstall_mod(params: Dictionary) -> Dictionary:
	var mod_id: String = params.get("mod_id", "")
	var is_enabled: bool = enabled_mods.get(mod_id, false)
	var success = ModUtils.uninstall_mod(mod_id, is_enabled, game_path)
	if success:
		load_mods()
		return {"code": 200, "data": {"success": true, "message": "Mod uninstalled"}}
	return {"code": 500, "data": {"success": false, "message": "Failed to uninstall mod"}}


func _api_batch_enable_mods(params: Dictionary) -> Dictionary:
	var mod_ids: Array = params.get("mod_ids", [])
	var count = 0
	for mod_id in mod_ids:
		var mod_data: Dictionary = {}
		for m in mods:
			if m.get("id", "") == mod_id:
				mod_data = m
				break
		if not mod_data.is_empty() and not enabled_mods.get(mod_id, false):
			if ModUtils.enable_mod(mod_data, game_path):
				enabled_mods[mod_id] = true
				count += 1
	_save_enabled_mods()
	return {"code": 200, "data": {"success": true, "enabled_count": count}}


func _api_batch_disable_mods(params: Dictionary) -> Dictionary:
	var mod_ids: Array = params.get("mod_ids", [])
	var count = 0
	for mod_id in mod_ids:
		var mod_data: Dictionary = {}
		for m in mods:
			if m.get("id", "") == mod_id:
				mod_data = m
				break
		if not mod_data.is_empty() and enabled_mods.get(mod_id, false):
			if ModUtils.disable_mod(mod_data, game_path):
				enabled_mods.erase(mod_id)
				count += 1
	_save_enabled_mods()
	return {"code": 200, "data": {"success": true, "disabled_count": count}}


func _api_get_mod_notes(_params: Dictionary) -> Dictionary:
	return {"code": 200, "data": {"notes": mod_notes}}


func _api_save_mod_notes(params: Dictionary) -> Dictionary:
	var mod_id: String = params.get("mod_id", "")
	var note: String = params.get("note", "")
	if mod_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "mod_id is required"}}
	# Truncate to 500 chars like the original app
	note = note.strip_edges().substr(0, 500)
	if note.is_empty():
		mod_notes.erase(mod_id)
	else:
		mod_notes[mod_id] = note
	save_mod_notes()
	return {"code": 200, "data": {"success": true}}


# ── 存档 API ───────────────────────────────────────────────────

func _api_scan_saves(_params: Dictionary) -> Dictionary:
	var all_saves: Array = []

	# Steam 存档
	if not save_path.is_empty():
		var steam_saves = SaveUtils.scan_all_saves(save_path)
		all_saves.append_array(steam_saves)

	# 导入的存档
	var imported = SaveUtils.scan_saves(temp_save_path)
	all_saves.append_array(imported)

	return {"code": 200, "data": {"saves": all_saves}}


## 辅助：通过 ID 查找存档信息
func _find_save_by_id(save_id: String) -> Dictionary:
	if save_path.is_empty():
		return {}
	var all_saves = SaveUtils.scan_all_saves(save_path)
	for s in all_saves:
		# 优先匹配 id 字段
		if s.get("id", "") == save_id:
			return s
		# 兼容匹配 steam_id (账号 ID)
		if s.get("steam_id", "") == save_id:
			return s
		# 兼容匹配 full_name 或 name
		if s.get("full_name", "") == save_id or s.get("name", "") == save_id:
			return s
	# 也搜索导入的存档
	var imported = SaveUtils.scan_saves(temp_save_path)
	for s in imported:
		# 优先匹配 id 字段
		if s.get("id", "") == save_id:
			return s
		# 兼容匹配 steam_id (账号 ID)
		if s.get("steam_id", "") == save_id:
			return s
		# 兼容匹配 full_name 或 name
		if s.get("full_name", "") == save_id or s.get("name", "") == save_id:
			return s
	return {}


func _api_import_save(params: Dictionary) -> Dictionary:
	var filename: String = params.get("filename", "")
	var data_base64: String = params.get("data_base64", "")

	if data_base64.is_empty():
		return {"code": 400, "data": {"success": false, "message": "No file data"}}

	# 解码 base64 并写入临时文件
	var bytes = Marshalls.base64_to_raw(data_base64)
	var temp_path = get_base_path().path_join("temp_upload_save_" + filename)
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"code": 500, "data": {"success": false, "message": "Failed to write temp file"}}
	file.store_buffer(bytes)
	file.close()

	# 导入存档
	var save_name = filename.get_basename()
	var result = SaveUtils.import_save(temp_path, temp_save_path, save_name)

	# 清理临时文件
	DirAccess.remove_absolute(temp_path)

	if result.get("success", false):
		return {"code": 200, "data": {"success": true, "message": "Save imported", "save_info": result.get("save_info", {})}}
	return {"code": 200, "data": {"success": false, "message": result.get("message", "Import failed")}}


func _api_export_save(params: Dictionary) -> Dictionary:
	print("[api_export_save] 收到参数：", params)
	var save_id: String = params.get("save_id", "")
	var export_path_param: String = params.get("export_path", "")
	if save_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing save_id"}}

	# 检查 save_path 配置
	print("[api_export_save] save_path: ", save_path)
	if save_path.is_empty():
		return {"code": 500, "data": {"success": false, "message": "Save path not configured"}}

	# 使用 _find_save_by_id() 直接查找存档数据
	var save_data = _find_save_by_id(save_id)
	print("[api_export_save] save_data: ", save_data)
	if save_data.is_empty():
		return {"code": 404, "data": {"success": false, "message": "Save not found"}}

	# 复用原版 _on_export_save_pressed 的逻辑
	var profile_path = save_data.get("path", "")
	print("[api_export_save] profile_path: ", profile_path)
	if profile_path.is_empty():
		return {"code": 404, "data": {"success": false, "message": "Save path not found"}}

	# 获取账号目录（去掉 /profile1 等后缀）
	var account_path = profile_path
	if "/profile" in account_path:
		account_path = account_path.get_base_dir()
	if "/saves" in account_path:
		account_path = account_path.get_base_dir()
	print("[api_export_save] account_path: ", account_path)

	# 检查账号目录是否存在
	if not DirAccess.dir_exists_absolute(account_path):
		print("[api_export_save] account_path not exists: ", account_path)
		return {"code": 500, "data": {"success": false, "message": "Account path not exists: " + account_path}}

	# 获取账号 ID 用于文件名
	var steam_id = save_data.get("steam_id", "")
	var is_imported = save_data.get("is_imported", false)
	if steam_id.is_empty():
		steam_id = save_data.get("name", "")

	# 确定导出路径
	var final_export_path: String = ""
	if not export_path_param.is_empty():
		final_export_path = export_path_param
		if not final_export_path.ends_with(".zip"):
			final_export_path = final_export_path + "_" + steam_id + ".zip"
	else:
		var export_path = get_base_path().path_join("exports")
		DirAccess.make_dir_recursive_absolute(export_path)
		final_export_path = export_path.path_join(steam_id + ".zip")

	print("[api_export_save] final_export_path: ", final_export_path)

	# 使用账号目录路径进行导出
	var result = SaveUtils.export_save(account_path, final_export_path)
	print("[api_export_save] result: ", result)
	if result.get("success", false):
		return {"code": 200, "data": {"success": true, "message": "Save exported", "export_path": final_export_path}}
	return {"code": 500, "data": {"success": false, "message": result.get("message", "Export failed")}}


func _api_backup_save(params: Dictionary) -> Dictionary:
	var save_id: String = params.get("save_id", "")
	if save_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing save_id"}}

	print("[api_backup] 收到 save_id: ", save_id)

	var save_data = _find_save_by_id(save_id)
	print("[api_backup] save_data: ", save_data)
	if save_data.is_empty():
		print("[api_backup] 未找到存档数据！")
		return {"code": 404, "data": {"success": false, "message": "Save not found"}}

	var backup_key = save_id
	var steam_id = save_data.get("steam_id", "")
	var is_imported = save_data.get("is_imported", false)

	var profile_path = save_data.get("path", "")
	print("[api_backup] profile_path: ", profile_path)
	if profile_path.is_empty():
		print("[api_backup] profile_path 为空！")
		return {"code": 404, "data": {"success": false, "message": "Save path not found"}}

	# 获取账号目录
	var account_path = profile_path
	if "/profile" in account_path:
		account_path = account_path.get_base_dir()
	if "/saves" in account_path:
		account_path = account_path.get_base_dir()

	print("[api_backup] 账号目录：", account_path)
	print("[api_backup] steam_id: ", steam_id)

	var backup_dir = backup_path
	if backup_dir.is_empty():
		backup_dir = get_base_path() + "backups"

	if not DirAccess.dir_exists_absolute(backup_dir):
		DirAccess.make_dir_recursive_absolute(backup_dir)

	var backup_result = SaveUtils.create_backup(account_path, backup_dir, steam_id, false)
	print("[api_backup] backup_result: ", backup_result)

	if not backup_result.is_empty():
		return {"code": 200, "data": {"success": true, "message": "Backup created", "backup_path": backup_result}}
	return {"code": 500, "data": {"success": false, "message": "Backup failed"}}


func _api_restore_save(params: Dictionary) -> Dictionary:
	var save_id: String = params.get("save_id", "")
	if save_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing save_id"}}

	var save_data = _find_save_by_id(save_id)
	if save_data.is_empty():
		return {"code": 404, "data": {"success": false, "message": "Save not found"}}

	var is_imported = save_data.get("is_imported", false)
	var steam_id = save_data.get("steam_id", "")
	var target_path = ""

	if is_imported:
		var import_info = save_data.get("import_info", {})
		target_path = import_info.get("path", "")
		if target_path.is_empty():
			return {"code": 404, "data": {"success": false, "message": "Imported save path not found"}}
	else:
		if not save_path.is_empty() and DirAccess.dir_exists_absolute(save_path):
			var accounts = SaveUtils.get_all_steam_accounts(save_path)
			for account in accounts:
				if account["steam_id"] == steam_id:
					target_path = account["path"]
					break

		if target_path.is_empty():
			return {"code": 404, "data": {"success": false, "message": "Cannot determine save path"}}

	var backup_path = params.get("backup_path", "")
	if backup_path.is_empty():
		backup_path = _get_latest_backup_path(steam_id, is_imported)
		if backup_path.is_empty():
			return {"code": 404, "data": {"success": false, "message": "No backup found"}}

	print("[api_restore] Restoring from: ", backup_path)
	print("[api_restore] Target: ", target_path)

	# 调试：检查路径是否存在
	if not DirAccess.dir_exists_absolute(backup_path):
		push_error("[api_restore] Backup path does not exist: " + backup_path)
	if not DirAccess.dir_exists_absolute(target_path):
		push_warning("[api_restore] Target path may not exist: " + target_path)

	var success = SaveUtils.restore_backup(backup_path, target_path)

	if success:
		return {"code": 200, "data": {"success": true, "message": "Save restored"}}
	return {"code": 500, "data": {"success": false, "message": "Restore failed"}}


# 获取最新备份路径
func _get_latest_backup_path(steam_id: String, is_imported: bool) -> String:
	var backups = _get_all_backups_for_save(steam_id, is_imported)
	if backups.is_empty():
		return ""
	return backups[0].get("path", "")


func _api_get_save_backups(params: Dictionary) -> Dictionary:
	print("[_api_get_save_backups] START")
	var save_id: String = params.get("save_id", "")
	if save_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing save_id"}}

	var save_info = _find_save_by_id(save_id)
	if save_info.is_empty():
		return {"code": 404, "data": {"success": false, "message": "Save not found"}}

	var is_imported: bool = save_info.get("is_imported", false)
	var steam_id: String = save_info.get("steam_id", "")
	print("[_api_get_save_backups] is_imported=", is_imported, " steam_id=", steam_id)

	var all_backups = _get_all_backups_for_save(steam_id, is_imported)
	print("[_api_get_save_backups] Got ", all_backups.size(), " backups")

	# 跳过耗时的 size 计算，避免超时
	var backups_data = []
	for backup in all_backups:
		backups_data.append({
			"name": backup.get("name", ""),
			"path": backup.get("path", ""),
			"time": backup.get("time", ""),
			"type": backup.get("type", "manual"),
			"size": 0
		})

	print("[_api_get_save_backups] Returning ", backups_data.size(), " backups")
	return {"code": 200, "data": {"success": true, "backups": backups_data}}


# 计算文件夹大小（带安全限制防止卡死）
func _get_folder_size(folder_path: String, depth: int = 0) -> int:
	const MAX_DEPTH: int = 10  # 最大递归深度
	if depth > MAX_DEPTH:
		return 0
	var total_size = 0
	var dir = DirAccess.open(folder_path)
	if dir == null:
		return 0

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var file_path = folder_path.path_join(file_name)
			if dir.current_is_dir():
				total_size += _get_folder_size(file_path, depth + 1)
			else:
				var file_obj = FileAccess.open(file_path, FileAccess.READ)
				if file_obj:
					total_size += file_obj.get_length()
		dir.get_next()
	dir.list_dir_end()
	return total_size


func _api_overwrite_save(params: Dictionary) -> Dictionary:
	var source_steam_id: String = params.get("source_steam_id", "")
	var target_steam_id: String = params.get("target_steam_id", "")
	var source_path_param: String = params.get("source_path", "")
	var direction: String = params.get("direction", "")
	var create_backup: bool = params.get("create_backup", true)

	print("[API overwrite] source_steam_id: ", source_steam_id)
	print("[API overwrite] target_steam_id: ", target_steam_id)
	print("[API overwrite] direction: ", direction)

	if source_steam_id.is_empty() or target_steam_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing steam_id parameters"}}

	if direction != "vanilla_to_modded" and direction != "modded_to_vanilla":
		return {"code": 400, "data": {"success": false, "message": "Invalid direction"}}

	if save_path.is_empty() or not DirAccess.dir_exists_absolute(save_path):
		return {"code": 400, "data": {"success": false, "message": "Save path not configured"}}

	var accounts = SaveUtils.get_all_steam_accounts(save_path)

	var source_profile_path = ""
	var target_profile_path = ""

	for account in accounts:
		if account["steam_id"] == source_steam_id:
			source_profile_path = account["path"]
		if account["steam_id"] == target_steam_id:
			target_profile_path = account["path"]

	if source_profile_path.is_empty():
		return {"code": 404, "data": {"success": false, "message": "Source account not found"}}
	if target_profile_path.is_empty():
		return {"code": 404, "data": {"success": false, "message": "Target account not found"}}

	# 确定源和目标存档路径
	var source_save_path = source_profile_path
	var target_save_path = target_profile_path

	if direction == "vanilla_to_modded":
		source_save_path = source_profile_path.path_join("saves")
		target_save_path = target_profile_path.path_join("modded/saves")
	else:
		source_save_path = source_profile_path.path_join("modded/saves")
		target_save_path = target_profile_path.path_join("saves")

	print("[API overwrite] source_save_path: ", source_save_path)
	print("[API overwrite] target_save_path: ", target_save_path)

	if not DirAccess.dir_exists_absolute(source_save_path):
		return {"code": 404, "data": {"success": false, "message": "Source save not found"}}

	# 如果需要，先创建备份
	if create_backup:
		var backup_dir = target_save_path.get_base_dir().path_join("backups")
		DirAccess.make_dir_recursive_absolute(backup_dir)
		# 创建目标目录的备份
		var backup_result = SaveUtils.create_backup(target_save_path, backup_dir, target_steam_id, false)
		print("[API overwrite] Backup created: ", backup_result)

	# 执行覆盖（不包含备份参数）
	var overwrite_result = SaveUtils.overwrite_save(source_save_path, target_save_path)

	if overwrite_result.get("success", false):
		return {"code": 200, "data": {"success": true, "message": "Save overwritten successfully"}}
	return {"code": 500, "data": {"success": false, "message": overwrite_result.get("message", "Overwrite failed")}}


func _api_get_save_details(params: Dictionary) -> Dictionary:
	var save_id: String = params.get("save_id", "")
	if save_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing save_id"}}

	var save_data = _find_save_by_id(save_id)
	if save_data.is_empty():
		return {"code": 404, "data": {"success": false, "message": "Save not found"}}

	return {"code": 200, "data": {"save": save_data}}


func _api_delete_save(params: Dictionary) -> Dictionary:
	var save_id: String = params.get("save_id", "")
	if save_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing save_id"}}

	var save_data = _find_save_by_id(save_id)
	if save_data.is_empty():
		return {"code": 404, "data": {"success": false, "message": "Save not found"}}

	var is_imported = save_data.get("is_imported", false)
	var save_path_to_delete = save_data.get("path", "")

	if save_path_to_delete.is_empty():
		return {"code": 404, "data": {"success": false, "message": "Save path not found"}}

	var success = SaveUtils.delete_directory(save_path_to_delete)
	if success:
		return {"code": 200, "data": {"success": true, "message": "Save deleted"}}
	return {"code": 500, "data": {"success": false, "message": "Delete failed"}}


func _api_sync_cloud(params: Dictionary) -> Dictionary:
	var provider: String = params.get("provider", "")
	var steam_id: String = params.get("steam_id", "")

	if provider.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing provider"}}

	if steam_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing steam_id"}}

	if save_path.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Save path not configured"}}

	var accounts = SaveUtils.get_all_steam_accounts(save_path)
	var account_path = ""
	for account in accounts:
		if account["steam_id"] == steam_id:
			account_path = account["path"]
			break

	if account_path.is_empty():
		return {"code": 404, "data": {"success": false, "message": "Account not found"}}

	# 解析 provider 确定同步目标
	var sync_gse: bool = false
	var sync_steam: bool = false
	match provider:
		"gse":
			sync_gse = true
		"steam":
			sync_steam = true
		"both":
			sync_gse = true
			sync_steam = true

	print("[API sync_cloud] Provider: ", provider, ", Account: ", account_path)

	# 调用 SaveUtils 的云同步功能（与 _do_sync_to_cloud 相同的逻辑）
	var sync_result = SaveUtils.sync_save_to_all_locations(account_path, steam_id, sync_steam, sync_gse, gse_cloud_path, steam_cloud_path)
	print("[API sync_cloud] Result: ", sync_result)

	return {"code": 200, "data": sync_result}


func _apply_window_border_theme() -> void:
	"""应用窗口边框样式 (模板: rgba(86,131,172,0.15))"""
	var border_color = Color(0.337, 0.514, 0.675, 0.15)  # rgba(86,131,172,0.15)
	var bl = find_child_node(self, "WindowBorderLeft")
	if bl: bl.color = border_color
	var br = find_child_node(self, "WindowBorderRight")
	if br: br.color = border_color
	# 左侧面板右边框 (通过RightPanel左边框实现)
	var rp = find_child_node(self, "RightPanel")
	if rp:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_width_left = 1
		style.border_width_right = 0
		style.border_width_top = 0
		style.border_width_bottom = 0
		style.border_color = border_color
		rp.add_theme_stylebox_override("normal", style)


func _apply_topbar_theme() -> void:
	"""应用TopBar区域Steam样式 — 标题栏 + Tab选择器 + 工具栏"""
	var border_color = Color(0.337, 0.514, 0.675, 0.15)

	# ===== 标题栏 =====
	var titlebar = find_child_node(self, "TitleBar")
	if titlebar:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.082, 0.122, 0.18, 0.95)  # rgba(21,31,46,0.95)
		style.corner_radius_top_left = 0
		style.corner_radius_top_right = 0
		style.corner_radius_bottom_left = 0
		style.corner_radius_bottom_right = 0
		style.border_width_left = 0
		style.border_width_right = 0
		style.border_width_top = 0
		style.border_width_bottom = 1
		style.border_color = border_color
		titlebar.add_theme_stylebox_override("panel", style)
		# AppTitle 文字颜色
		var title = find_child_node(self, "AppTitle")
		if title:
			title.add_theme_color_override("font_color", Color(0.78, 0.835, 0.878))  # #c7d5e0

	# ===== Tab选择器 =====
	var tabsel = find_child_node(self, "TabSelector")
	if tabsel:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.082, 0.122, 0.18, 0.8)  # rgba(21,31,46,0.8)
		style.corner_radius_top_left = 0
		style.corner_radius_top_right = 0
		style.corner_radius_bottom_left = 0
		style.corner_radius_bottom_right = 0
		style.border_width_left = 0
		style.border_width_right = 0
		style.border_width_top = 0
		style.border_width_bottom = 1
		style.border_color = border_color
		tabsel.add_theme_stylebox_override("panel", style)
		# Tab按钮样式
		for ch in tabsel.get_children():
			if ch is Button:
				ch.add_theme_color_override("font_color", Color(0.545, 0.596, 0.627))  # #8b98a0

	# ===== 工具栏 =====
	var topbar_bg = find_child_node(self, "TopBarBg")
	if topbar_bg:
		var toolbar_bg_style = StyleBoxFlat.new()
		toolbar_bg_style.bg_color = Color(0.082, 0.122, 0.18, 0.5)  # rgba(21,31,46,0.5)
		toolbar_bg_style.corner_radius_top_left = 8
		toolbar_bg_style.corner_radius_top_right = 8
		toolbar_bg_style.corner_radius_bottom_left = 8
		toolbar_bg_style.corner_radius_bottom_right = 8
		toolbar_bg_style.border_width_left = 1
		toolbar_bg_style.border_width_right = 1
		toolbar_bg_style.border_width_top = 1
		toolbar_bg_style.border_width_bottom = 1
		toolbar_bg_style.border_color = Color(0.337, 0.514, 0.675, 0.15)
		topbar_bg.add_theme_stylebox_override("panel", toolbar_bg_style)

	# 搜索框 — 药丸形 (模板: border-radius: 20px, bg rgba(42,71,94,0.6))
	var search = find_child_node(self, "TopBarBg/TopBar/SearchBox")
	if search:
		search.custom_minimum_size = Vector2(200, 32)
		var s_style = StyleBoxFlat.new()
		s_style.bg_color = Color(0.165, 0.278, 0.369, 0.6)
		s_style.corner_radius_top_left = 16
		s_style.corner_radius_top_right = 16
		s_style.corner_radius_bottom_left = 16
		s_style.corner_radius_bottom_right = 16
		s_style.border_width_left = 1
		s_style.border_width_right = 1
		s_style.border_width_top = 1
		s_style.border_width_bottom = 1
		s_style.border_color = Color(0.337, 0.514, 0.675, 0.3)
		search.add_theme_stylebox_override("normal", s_style)
		search.add_theme_stylebox_override("focus", s_style)
		search.add_theme_color_override("font_color", Color(0.78, 0.835, 0.878))
		search.add_theme_color_override("caret_color", Color(0.4, 0.753, 0.976))



func _apply_modlist_theme() -> void:
	"""应用模组列表Steam样式（模板精确还原）"""

	# 1. 列表 VBox separation = 6（模板: margin-bottom: 6px）
	var modlist = find_child_node(self, "ModList")
	if modlist:
		modlist.add_theme_constant_override("separation", _ITEM_GAP)

	# 2. ScrollContainer 透明
	var scroll = find_child_node(self, "ModScroll")
	if scroll:
		scroll.add_theme_stylebox_override("panel", _make_transparent_style())

	# 3. 隐藏多余工具栏按钮（模板只有: 搜索框/筛选/安装）
	var extra_btns = ["UninstallModBtn", "BatchEnableBtn", "BatchUninstallBtn",
		"BatchSelectBtn", "BatchDeselectBtn", "RefreshModsBtn"]
	for btn_name in extra_btns:
		var btn = find_child_node(self, btn_name)
		if btn:
			btn.visible = false

	# 4. 工具栏按钮样式（模板: rgba(42,71,94,0.6) + 边框 + 6px圆角）
	var filter_btn = find_child_node(self, "FilterDropdown")
	if filter_btn:
		_apply_toolbar_btn_style(filter_btn)

	# 5. 安装按钮（模板: 渐变 #47bfff）
	var install_btn = find_child_node(self, "InstallModBtn")
	if install_btn:
		_apply_install_btn_style(install_btn)


func _apply_category_tags_theme() -> void:
	"""应用分类标签按钮样式"""
	var category_tags = find_child_node(self, "TopBarBg/TopBar/CategoryTags")
	if not category_tags:
		return

	for ch in category_tags.get_children():
		if ch is Button:
			# 存储基础样式
			var normal_style = StyleBoxFlat.new()
			normal_style.bg_color = Color(0.165, 0.278, 0.369, 0.4)
			normal_style.corner_radius_top_left = 6
			normal_style.corner_radius_top_right = 6
			normal_style.corner_radius_bottom_left = 6
			normal_style.corner_radius_bottom_right = 6
			normal_style.border_width_left = 1
			normal_style.border_width_right = 1
			normal_style.border_width_top = 1
			normal_style.border_width_bottom = 1
			normal_style.border_color = Color(0.337, 0.514, 0.675, 0.3)

			# 激活样式
			var active_style = StyleBoxFlat.new()
			active_style.bg_color = Color(0.4, 0.753, 0.976, 0.2)
			active_style.corner_radius_top_left = 6
			active_style.corner_radius_top_right = 6
			active_style.corner_radius_bottom_left = 6
			active_style.corner_radius_bottom_right = 6
			active_style.border_width_left = 1
			active_style.border_width_right = 1
			active_style.border_width_top = 1
			active_style.border_width_bottom = 1
			active_style.border_color = Color(0.4, 0.753, 0.976)  # accent

			ch.add_theme_stylebox_override("normal", normal_style)
			ch.add_theme_stylebox_override("hover", normal_style)
			ch.add_theme_stylebox_override("pressed", active_style)
			ch.add_theme_color_override("font_color", Color(0.545, 0.596, 0.627))

			ch.set_meta("normal_style", normal_style)
			ch.set_meta("active_style", active_style)

	# 默认激活 TagAll
	var tag_all = category_tags.find_child("TagAll", false, false)
	if tag_all and tag_all is Button:
		tag_all.add_theme_stylebox_override("normal", tag_all.get_meta("active_style"))
		tag_all.add_theme_color_override("font_color", Color(0.4, 0.753, 0.976))


func _apply_start_modes_theme() -> void:
	"""应用启动模式切换按钮样式"""
	var start_modes = find_child_node(self, "ModStartModes")
	if not start_modes:
		return

	for ch in start_modes.get_children():
		if ch is Button:
			# 基础样式（未激活 - 无边框）
			var normal_style = StyleBoxFlat.new()
			normal_style.bg_color = Color(0, 0, 0, 0)
			normal_style.border_width_bottom = 2
			normal_style.border_color = Color(0, 0, 0, 0)

			# 激活样式（底部 2px 强调色边框）
			var active_style = StyleBoxFlat.new()
			active_style.bg_color = Color(0, 0, 0, 0)
			active_style.border_width_bottom = 2
			active_style.border_color = Color(0.4, 0.753, 0.976)  # accent

			ch.add_theme_stylebox_override("normal", normal_style)
			ch.add_theme_stylebox_override("hover", normal_style)
			ch.add_theme_stylebox_override("pressed", active_style)
			ch.add_theme_color_override("font_color", Color(0.545, 0.596, 0.627))  # 灰色
			ch.add_theme_color_override("font_hover_color", Color(0.78, 0.835, 0.878))  # 悬停白色

			ch.set_meta("normal_style", normal_style)
			ch.set_meta("active_style", active_style)

	# 设置默认激活按钮
	_update_start_mode_buttons("ModeSingleplayer")


func _update_start_mode_buttons(active_btn_name: String) -> void:
	"""更新启动模式按钮激活状态"""
	var start_modes = find_child_node(self, "ModStartModes")
	if not start_modes:
		return

	for ch in start_modes.get_children():
		if ch is Button:
			if ch.name == active_btn_name:
				ch.add_theme_stylebox_override("normal", ch.get_meta("active_style"))
				ch.add_theme_color_override("font_color", Color.WHITE)
			else:
				ch.add_theme_stylebox_override("normal", ch.get_meta("normal_style"))
				ch.add_theme_color_override("font_color", Color(0.545, 0.596, 0.627))


func _on_start_mode_clicked(btn_name: String) -> void:
	"""处理启动模式切换"""
	if "Multiplayer" in btn_name:
		current_launch_mode = "multiplayer"
	elif "Custom" in btn_name:
		current_launch_mode = "custom"
	else:
		current_launch_mode = "singleplayer"

	_update_start_mode_buttons(btn_name)
	print("[Launch Mode] Switched to: ", current_launch_mode)


func _make_transparent_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	return s


func _apply_toolbar_btn_style(btn: Control) -> void:
	if btn == null:
		return
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.165, 0.278, 0.369, 0.6)
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.337, 0.514, 0.675, 0.3)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)


func _apply_install_btn_style(btn: Button) -> void:
	if btn == null:
		return
	btn.custom_minimum_size = Vector2(90, 32)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.278, 0.749, 1.0)  # #47bfff
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_color_override("font_color", Color.WHITE)


func _apply_moddetails_theme() -> void:
	"""应用模组详情面板Steam样式 (模板: rgba(0,0,0,0.2) + 边框)"""
	var border_color = Color(0.337, 0.514, 0.675, 0.15)

	# 外层 ScrollContainer 透明
	var details_scroll = find_child_node(self, "ModDetailsPanel")
	if details_scroll:
		var scroll_style = StyleBoxFlat.new()
		scroll_style.bg_color = Color(0, 0, 0, 0)
		scroll_style.border_width_left = 0
		scroll_style.border_width_right = 0
		scroll_style.border_width_top = 0
		scroll_style.border_width_bottom = 0
		details_scroll.add_theme_stylebox_override("panel", scroll_style)

	# 详情面板背景 (DetailsPanelBg)
	var details_bg = find_child_node(self, "DetailsPanelBg")
	if details_bg:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.2)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = border_color
		details_bg.add_theme_stylebox_override("panel", style)

	# 标题样式 (NameLbl: #66c0f9, 22px)
	var name_lbl = find_child_node(self, "NameLbl")
	if name_lbl:
		name_lbl.add_theme_font_size_override("font_size", 22)
		name_lbl.add_theme_color_override("font_color", Color(0.4, 0.753, 0.976))

	# 版本标签样式
	var version_lbl = find_child_node(self, "VersionLbl")
	if version_lbl:
		version_lbl.add_theme_color_override("font_color", Color(0.545, 0.596, 0.627))
		var v_style = StyleBoxFlat.new()
		v_style.bg_color = Color(0.165, 0.278, 0.369, 0.6)
		v_style.corner_radius_top_left = 4
		v_style.corner_radius_top_right = 4
		v_style.corner_radius_bottom_left = 4
		v_style.corner_radius_bottom_right = 4
		version_lbl.add_theme_stylebox_override("normal", v_style)

	# 启用按钮 (渐变 #47bfff → #2a475e)
	var btn_enable = find_child_node(self, "BtnEnable")
	if btn_enable:
		btn_enable.custom_minimum_size = Vector2(80, 34)
		var norm = StyleBoxFlat.new()
		norm.bg_color = Color(0.278, 0.749, 1.0)  # #47bfff 近似
		norm.corner_radius_top_left = 4
		norm.corner_radius_top_right = 4
		norm.corner_radius_bottom_left = 4
		norm.corner_radius_bottom_right = 4
		btn_enable.add_theme_stylebox_override("normal", norm)
		btn_enable.add_theme_stylebox_override("hover", norm)
		btn_enable.add_theme_stylebox_override("pressed", norm)
		btn_enable.add_theme_color_override("font_color", Color(1, 1, 1))

	# 卸载按钮 (透明+边框)
	var btn_uninstall = find_child_node(self, "BtnUninstall")
	if btn_uninstall:
		btn_uninstall.custom_minimum_size = Vector2(80, 34)
		var sec = StyleBoxFlat.new()
		sec.bg_color = Color(0, 0, 0, 0)
		sec.corner_radius_top_left = 4
		sec.corner_radius_top_right = 4
		sec.corner_radius_bottom_left = 4
		sec.corner_radius_bottom_right = 4
		sec.border_width_left = 1
		sec.border_width_right = 1
		sec.border_width_top = 1
		sec.border_width_bottom = 1
		sec.border_color = Color(0.337, 0.514, 0.675, 0.4)
		btn_uninstall.add_theme_stylebox_override("normal", sec)
		btn_uninstall.add_theme_stylebox_override("hover", sec)
		btn_uninstall.add_theme_stylebox_override("pressed", sec)
		btn_uninstall.add_theme_color_override("font_color", Color(0.639, 0.788, 0.906))  # #a3c9e7


func _apply_footer_theme() -> void:
	"""应用底部栏Steam样式 - 透明背景，只有顶部分隔线"""
	var footer = find_child_node(self, "Footer")
	if footer:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)  # 完全透明，不遮挡内容
		style.border_width_left = 0
		style.border_width_right = 0
		style.border_width_top = 1
		style.border_width_bottom = 0
		style.border_color = Color(0.337, 0.514, 0.675, 0.15)  # rgba(86,131,172,0.15)
		footer.add_theme_stylebox_override("panel", style)

	# StatusMini label (← 拖动启动 提示文字)
	var status_mini = find_child_node(self, "StatusMini")
	if status_mini:
		status_mini.add_theme_color_override("font_color", Color(0.545, 0.596, 0.627))  # #8b98a0


func _apply_button_theme() -> void:
	"""应用按钮Steam样式（模板: rgba(42,71,94,0.6), border rgba(86,131,172,0.3), border-radius 6px）"""
	var btn_border_color = Color(0.337, 0.514, 0.675, 0.3)

	# 工具栏按钮通用样式
	var toolbar_btns = ["InstallModBtn", "UninstallModBtn", "BatchEnableBtn",
		"BatchUninstallBtn", "BatchSelectBtn", "RefreshModsBtn"]
	for btn_name in toolbar_btns:
		var btn = find_child_node(self, btn_name)
		if btn:
			btn.custom_minimum_size = Vector2(80, 32)
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.165, 0.278, 0.369, 0.6)
			style.corner_radius_top_left = 6
			style.corner_radius_top_right = 6
			style.corner_radius_bottom_left = 6
			style.corner_radius_bottom_right = 6
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			style.border_color = btn_border_color
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", style)
			btn.add_theme_color_override("font_color", Color(0.639, 0.788, 0.906))  # #a3c9e7

	# 安装按钮 — 主按钮（模板: 渐变 #47bfff → #2a475e）
	var install_btn = find_child_node(self, "InstallModBtn")
	if install_btn:
		install_btn.custom_minimum_size = Vector2(90, 32)
		var norm = StyleBoxFlat.new()
		norm.bg_color = Color(0.278, 0.749, 1.0)  # #47bfff
		norm.corner_radius_top_left = 6
		norm.corner_radius_top_right = 6
		norm.corner_radius_bottom_left = 6
		norm.corner_radius_bottom_right = 6
		install_btn.add_theme_stylebox_override("normal", norm)
		install_btn.add_theme_stylebox_override("hover", norm)
		install_btn.add_theme_stylebox_override("pressed", norm)
		install_btn.add_theme_color_override("font_color", Color(1, 1, 1))

	# 刷新按钮
	var refresh_btn = find_child_node(self, "RefreshModsBtn")
	if refresh_btn:
		refresh_btn.custom_minimum_size = Vector2(80, 36)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.165, 0.278, 0.369, 0.6)
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = COLORS.border
		refresh_btn.add_theme_stylebox_override("normal", style)
		refresh_btn.add_theme_stylebox_override("hover", style)
		refresh_btn.add_theme_color_override("font_color", COLORS.text_primary)


func _start_local_server_early() -> void:
	"""立即启动本地服务器（不依赖Nexus UI）"""
	if local_server == null:
		return

	if local_server.is_running():
		return

	var started = local_server.start()
	if started:
		var port = local_server.get_port()
		print("[_start_local_server_early] Server started on localhost:", port)
		# 初始化下载标签页UI
		_init_download_ui()
	else:
		print("[_start_local_server_early] Failed to start server")


func _start_local_server() -> void:
	"""启动本地HTTP服务器（用于Nexus UI初始化后的同步）"""
	if local_server == null:
		return

	if local_server.is_running():
		return

	# 如果有 Nexus UI 的 API 实例，优先使用它（包含更完整的设置）
	if nexus_mods_instance:
		var ui_nexus_api = nexus_mods_instance.get_nexus_api()
		if ui_nexus_api:
			local_server.set_nexus_api(ui_nexus_api)
			nexus_api = ui_nexus_api  # 同步到独立实例引用

	var started = local_server.start()
	if started:
		var port = local_server.get_port()
		print("[_start_local_server] Server started on localhost:", port)
		show_notification(translate("local_server_started"), true)
		# 初始化下载标签页UI
		_init_download_ui()
	else:
		print("[_start_local_server] Failed to start server")
		show_notification(translate("local_server_start_failed"), false)


# 创建教程页面（新Tab）
func _create_tutorial_tab() -> void:
	if not tab_container:
		tab_container = find_child_node(self, "TabContainer")
	if not tab_container:
		print("[_create_tutorial_tab] ERROR: TabContainer not found!")
		return

	# 创建新的Tab页面
	var tutorial_tab = Control.new()
	tutorial_tab.name = "TutorialTab"
	tab_container.add_child(tutorial_tab)

	# 设置Tab标题
	tab_container.set_tab_title(5, translate("tutorial"))
	print("[_create_tutorial_tab] Created TutorialTab at index 5")

	# 创建内容容器
	var scroll = ScrollContainer.new()
	scroll.name = "TutorialScroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.custom_minimum_size = Vector2(0, 400)
	tutorial_tab.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.name = "TutorialVBox"
	vbox.custom_minimum_size = Vector2(400, 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# ===== N网API配置部分 =====
	var api_section = VBoxContainer.new()
	api_section.name = "APISection"
	vbox.add_child(api_section)

	# API配置标题
	var api_title = Label.new()
	api_title.text = translate("nexus_api_title")
	api_title.add_theme_font_size_override("font_size", 20)
	api_title.add_theme_color_override("font_color", Color(0.2, 0.6, 0.9, 1))
	api_section.add_child(api_title)

	# API配置描述
	var api_desc = Label.new()
	api_desc.text = translate("nexus_api_desc")
	api_desc.add_theme_font_size_override("font_size", 14)
	api_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	api_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	api_section.add_child(api_desc)

	# 分隔线
	var separator1 = HSeparator.new()
	api_section.add_child(separator1)

	# API Key输入行
	var api_key_row = HBoxContainer.new()
	api_key_row.name = "APIKeyRow"
	api_key_row.custom_minimum_size = Vector2(0, 40)
	api_section.add_child(api_key_row)

	# API Key标签
	var api_key_label = Label.new()
	api_key_label.name = "APIKeyLabel"
	api_key_label.text = translate("nexus_api_key_label")
	api_key_label.custom_minimum_size = Vector2(100, 0)
	api_key_row.add_child(api_key_label)

	# API Key输入框
	var api_key_edit = LineEdit.new()
	api_key_edit.name = "APIKeyEdit"
	api_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	api_key_edit.placeholder_text = translate("nexus_api_key_placeholder")
	# 加载已保存的API Key
	var saved_api_key = config.get_value("nexus", "api_key", "")
	if not saved_api_key.is_empty():
		api_key_edit.text = saved_api_key
	api_key_row.add_child(api_key_edit)

	# 验证按钮
	var validate_btn = Button.new()
	validate_btn.name = "ValidateBtn"
	validate_btn.text = translate("nexus_validate_btn_text")
	validate_btn.pressed.connect(_on_tutorial_tab_validate_pressed)
	api_key_row.add_child(validate_btn)

	# 获取API Key按钮
	var get_api_btn = Button.new()
	get_api_btn.name = "GetAPIBtn"
	get_api_btn.text = translate("nexus_get_api_btn")
	get_api_btn.tooltip_text = translate("nexus_get_api_tip")
	get_api_btn.pressed.connect(_on_get_nexus_api_key_pressed)
	api_section.add_child(get_api_btn)

	# 状态标签
	var status_label = Label.new()
	status_label.name = "StatusLabel"
	# 显示已保存的验证状态
	var validated = config.get_value("nexus", "validated", false)
	var username = config.get_value("nexus", "username", "")
	var is_premium = config.get_value("nexus", "is_premium", false)
	if validated and not username.is_empty():
		status_label.text = translate("api_validated_success") % username
		status_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))
	elif not saved_api_key.is_empty():
		status_label.text = translate("nexus_api_key_saved")
		status_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2, 1))
	else:
		status_label.text = translate("nexus_status_unverified")
	api_section.add_child(status_label)

	# 分隔线
	var separator2 = HSeparator.new()
	api_section.add_child(separator2)

	# 如何获取API Key说明
	var howto_label = Label.new()
	howto_label.text = translate("nexus_how_to_get_api")
	howto_label.add_theme_font_size_override("font_size", 16)
	howto_label.add_theme_color_override("font_color", Color(0.3, 0.5, 0.8, 1))
	api_section.add_child(howto_label)

	# 步骤说明
	var steps = [
		translate("nexus_api_step1"),
		translate("nexus_api_step2"),
		translate("nexus_api_step3"),
		translate("nexus_api_step4"),
		translate("nexus_api_step5")
	]
	for step_text in steps:
		var step_label = Label.new()
		step_label.text = step_text
		step_label.add_theme_font_size_override("font_size", 13)
		api_section.add_child(step_label)

	# 注意事项
	var note_label = Label.new()
	note_label.text = translate("nexus_api_note")
	note_label.add_theme_font_size_override("font_size", 12)
	note_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4, 1))
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	api_section.add_child(note_label)

	# 保存按钮
	var save_btn = Button.new()
	save_btn.name = "SaveAPIKeyBtn"
	save_btn.text = translate("confirm")
	save_btn.custom_minimum_size = Vector2(120, 35)
	save_btn.pressed.connect(_on_tutorial_tab_save_pressed)
	api_section.add_child(save_btn)

	# ===== 教程使用说明部分 =====
	var tutorial_section = VBoxContainer.new()
	tutorial_section.name = "TutorialSection"
	vbox.add_child(tutorial_section)

	# 教程标题
	var tut_title = Label.new()
	tut_title.text = translate("tutorial")
	tut_title.add_theme_font_size_override("font_size", 20)
	tut_title.add_theme_color_override("font_color", Color(0.2, 0.6, 0.9, 1))
	tutorial_section.add_child(tut_title)

	# 教程内容 - 可以后续添加更多内容
	var tutorial_content = Label.new()
	tutorial_content.text = translate("tutorial_welcome_content")
	tutorial_content.add_theme_font_size_override("font_size", 14)
	tutorial_content.autowrap_mode = TextServer.AUTOWRAP_WORD
	tutorial_section.add_child(tutorial_content)

	print("[_create_tutorial_tab] Tutorial tab created successfully!")


# 更新所有Tab标题（支持新增的教程页）
func _update_all_tab_titles() -> void:
	if not tab_container:
		return
	var tab_count = tab_container.get_tab_count()
	print("[_update_all_tab_titles] Tab count: ", tab_count)
	tab_container.set_tab_title(0, translate("mods"))
	tab_container.set_tab_title(1, translate("saves"))
	tab_container.set_tab_title(2, translate("nexus_mods"))
	tab_container.set_tab_title(3, translate("downloads"))
	tab_container.set_tab_title(4, translate("settings"))
	if tab_count > 5:
		tab_container.set_tab_title(5, translate("tutorial"))


# 教程页面验证按钮 pressed
func _on_tutorial_tab_validate_pressed() -> void:
	print("[_on_tutorial_tab_validate_pressed] Called")

	# 获取API Key输入框
	var api_key_edit = get_node_or_null("/root/Control/TabContainer/TutorialTab/TutorialScroll/TutorialVBox/APISection/APIKeyRow/APIKeyEdit")
	var status_label = get_node_or_null("/root/Control/TabContainer/TutorialTab/TutorialScroll/TutorialVBox/APISection/StatusLabel")

	if not api_key_edit:
		print("[_on_tutorial_tab_validate_pressed] ERROR: API key edit not found!")
		return

	var api_key = api_key_edit.text.strip_edges()
	if api_key.is_empty():
		show_notification(translate("nexus_api_key") + " " + translate("cannot_be_empty"), false)
		return

	# 保存API Key到配置
	config.set_value("nexus", "api_key", api_key)
	config.save(config_path)

	# 使用Nexus API验证
	if not nexus_api:
		nexus_api = NexusAPI.new()

	nexus_api.set_api_key(api_key)
	show_notification(translate("nexus_validating"), true)

	# 异步验证
	validate_nexus_api_key(api_key)


# 验证Nexus API Key
func validate_nexus_api_key(api_key: String) -> void:
	var validation_result = await nexus_api.validate_api_key()

	if validation_result.success:
		config.set_value("nexus", "validated", true)
		config.set_value("nexus", "username", validation_result.get("username", ""))
		config.set_value("nexus", "is_premium", validation_result.get("is_premium", false))
		config.save(config_path)

		var username = validation_result.get("username", "unknown")
		show_notification(translate("api_validated_success") % username, true)

		# 更新状态标签
		var status_label = get_node_or_null("/root/Control/TabContainer/TutorialTab/TutorialScroll/TutorialVBox/APISection/StatusLabel")
		if status_label:
			status_label.text = translate("api_validated_success") % username
			status_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))
	else:
		config.set_value("nexus", "validated", false)
		config.set_value("nexus", "username", "")
		config.set_value("nexus", "is_premium", false)
		config.save(config_path)

		var error_msg = validation_result.get("error", "Unknown error")
		show_notification(translate("nexus_validation_failed") + ": " + error_msg, false)

		# 更新状态标签
		var status_label = get_node_or_null("/root/Control/TabContainer/TutorialTab/TutorialScroll/TutorialVBox/APISection/StatusLabel")
		if status_label:
			status_label.text = translate("nexus_validation_failed") + ": " + error_msg
			status_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2, 1))


# 教程页面保存按钮 pressed
func _on_tutorial_tab_save_pressed() -> void:
	# 获取API Key输入框
	var api_key_edit = get_node_or_null("/root/Control/TabContainer/TutorialTab/TutorialScroll/TutorialVBox/APISection/APIKeyRow/APIKeyEdit")

	if api_key_edit:
		var api_key = api_key_edit.text.strip_edges()
		if not api_key.is_empty():
			config.set_value("nexus", "api_key", api_key)
			config.save(config_path)
			show_notification(translate("api_saved_success"), true)

			# 同步到本地服务器
			if local_server:
				nexus_api.set_api_key(api_key)
			# 同步到N网UI实例
			if nexus_mods_instance:
				nexus_mods_instance.set_api_key(api_key)

			print("[_on_tutorial_tab_save_pressed] API key saved: ", api_key.substr(0, 10), "...")


# 获取Nexus API Key按钮 pressed
func _on_get_nexus_api_key_pressed() -> void:
	# 打开Nexus Mods网站
	OS.shell_open("https://www.nexusmods.com/my-account")


# 教程弹窗中获取Nexus API Key按钮
func _on_tutorial_get_nexus_api_key() -> void:
	# 打开Nexus Mods API Key申请页面
	OS.shell_open("https://www.nexusmods.com/settings/api-keys")


# 教程弹窗中配置Nexus API按钮
func _on_tutorial_open_nexus_config() -> void:
	# 先关闭教程弹窗
	if tutorial_panel and is_instance_valid(tutorial_panel):
		tutorial_panel.queue_free()
		tutorial_panel = null

	# 保存game_path
	if not game_path.is_empty():
		config.set_value("paths", "game_path", game_path)
		config.save(config_path)

	# 跳转到设置页面
	if tab_container:
		tab_container.current_tab = 3  # Settings tab
	show_notification(translate("tutorial_nexus_config_hint"), true)


# 教程弹窗中Nexus API Key验证按钮 pressed
func _on_tutorial_nexus_validate_pressed() -> void:
	print("[_on_tutorial_nexus_validate_pressed] Called")

	# 获取弹窗中的API Key输入框 - 教程弹窗使用独立结构
	var api_key_edit = find_child_node(tutorial_panel, "APIKeyEdit")
	var status_label = find_child_node(tutorial_panel, "ValidateStatus")
	var validate_btn = find_child_node(tutorial_panel, "ValidateBtn")

	if not api_key_edit:
		# 尝试另一种路径查找
		if tutorial_panel and tutorial_panel.has_node("GamePathContainer/APIKeyEdit"):
			api_key_edit = tutorial_panel.get_node("GamePathContainer/APIKeyEdit")
		if tutorial_panel and tutorial_panel.has_node("GamePathContainer/ValidateStatus"):
			status_label = tutorial_panel.get_node("GamePathContainer/ValidateStatus")
		if tutorial_panel and tutorial_panel.has_node("GamePathContainer/ValidateBtn"):
			validate_btn = tutorial_panel.get_node("GamePathContainer/ValidateBtn")

	if not api_key_edit:
		print("[_on_tutorial_nexus_validate_pressed] ERROR: APIKeyEdit not found in popup")
		show_notification(translate("interface_not_ready"), false)
		return

	var api_key = api_key_edit.text.strip_edges()
	if api_key.is_empty():
		show_notification(translate("please_enter_api_key"), false)
		return

	# 保存API Key到config
	config.set_value("nexus", "api_key", api_key)
	config.save(config_path)
	print("[_on_tutorial_nexus_validate_pressed] Saved API key to config")

	# 设置状态显示
	if status_label:
		status_label.text = translate("validating") + "..."
		status_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.8, 1))

	# 禁用按钮防止重复点击
	if validate_btn:
		validate_btn.disabled = true

	# 调用NexusAPI验证
	if not nexus_api:
		print("[_on_tutorial_nexus_validate_pressed] ERROR: nexus_api is null")
		if status_label:
			status_label.text = translate("nexus_api_not_initialized")
			status_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2, 1))
		if validate_btn:
			validate_btn.disabled = false
		return

	nexus_api.set_api_key(api_key)

	# 异步验证
	_show_loading(translate("validating"))
	var result = await nexus_api.validate_api_key()
	_hide_loading()

	if validate_btn:
		validate_btn.disabled = false

	if result.success:
		var username = result.get("username", "")
		var is_premium = result.get("is_premium", false)
		var status_text = translate_fmt("api_validated_user", [username])
		if is_premium:
			status_text += " (Premium)"

		if status_label:
			status_label.text = status_text
			status_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))

		show_notification(translate_fmt("api_key_validate_success", [username]), true)

		# 保存验证状态
		config.set_value("nexus", "validated", true)
		config.set_value("nexus", "username", username)
		config.set_value("nexus", "is_premium", is_premium)
		config.save(config_path)

		# 同步到其他实例
		if nexus_mods_instance:
			nexus_mods_instance.set_api_key(api_key)

		print("[_on_tutorial_nexus_validate_pressed] API key validated: ", username)
	else:
		var error_msg = result.get("error", translate("unknown_error"))
		if status_label:
			status_label.text = translate("nexus_validation_failed") + ": " + error_msg
			status_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2, 1))

		show_notification(translate_fmt("api_key_validate_failed", [error_msg]), false)

		# 清除验证状态
		config.set_value("nexus", "validated", false)
		config.save(config_path)


# 初始化整合包标签页UI
func _init_bundle_ui() -> void:
	print("[_init_bundle_ui] Initializing bundle tab UI...")

	# 获取UI节点引用
	bundles_list = find_child_node(self, "BundlesList")
	bundle_details_vbox = find_child_node(self, "BundleDetailsVBox")
	bundle_mods_list = find_child_node(self, "BundleModsList")

	# 尝试获取已有的GridContainer，如果没有则动态创建
	bundle_container = find_child_node(self, "BundlesGrid")
	if not bundle_container:
		# 动态创建GridContainer
		var scroll = find_child_node(self, "BundleListScroll")
		if scroll:
			bundle_container = GridContainer.new()
			bundle_container.name = "BundlesGrid"
			bundle_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bundle_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
			bundle_container.columns = 2  # 每行2个卡片
			bundle_container.add_theme_constant_override("h_separation", 20)
			bundle_container.add_theme_constant_override("v_separation", 20)
			bundle_container.add_theme_constant_override("margin_left", 20)
			bundle_container.add_theme_constant_override("margin_top", 20)
			bundle_container.add_theme_constant_override("margin_right", 20)
			bundle_container.add_theme_constant_override("margin_bottom", 20)
			scroll.add_child(bundle_container)
			print("[_init_bundle_ui] Created BundlesGrid dynamically")

	# 检查是否存在预设选择器，不存在则动态创建
	if bundle_info_labels.has("preset_selector") and bundle_info_labels["preset_selector"]:
		var preset_selector = bundle_info_labels["preset_selector"]
		if preset_selector:
			preset_selector.item_selected.connect(_on_bundle_preset_changed)

	# 不再使用旧的ItemList，改为卡片展示

	# 连接按钮信号
	var import_btn = find_child_node(self, "ImportBundleBtn")
	var url_btn = find_child_node(self, "AddByUrlBtn")
	var export_btn = find_child_node(self, "ExportBundleBtn")
	var update_btn = find_child_node(self, "CheckUpdateBtn")

	if import_btn:
		import_btn.pressed.connect(_on_import_bundle_pressed)
	if url_btn:
		url_btn.pressed.connect(_on_add_by_url_pressed)
	if export_btn:
		export_btn.pressed.connect(_on_export_bundle_pressed)
	if update_btn:
		update_btn.pressed.connect(_on_check_bundle_update_pressed)

	# 连接删除按钮
	var delete_btn = find_child_node(self, "DeleteBundleBtn")
	if delete_btn:
		delete_btn.pressed.connect(_on_delete_bundle_pressed)

	# 连接编辑按钮
	var edit_btn = find_child_node(self, "EditBundleBtn")
	if edit_btn:
		edit_btn.pressed.connect(_on_edit_bundle_pressed)

	# 保存详情面板的标签引用
	bundle_info_labels = {
		"name": find_child_node(self, "BundleNameLabel"),
		"author": find_child_node(self, "BundleAuthorLabel"),
		"version": find_child_node(self, "BundleVersionLabel"),
		"desc": find_child_node(self, "BundleDescLabel"),
		"empty": find_child_node(self, "EmptyDetailsLabel"),
		"preset_selector": _get_or_create_preset_selector()
	}

	# 加载已保存的整合包
	_load_bundles()


# 获取或创建预设选择器
func _get_or_create_preset_selector() -> OptionButton:
	# 尝试查找已存在的
	var existing = find_child_node(self, "BundlePresetSelector")
	if existing:
		return existing

	# 如果详情面板容器存在，添加到里面
	if bundle_details_vbox:
		var preset_selector = OptionButton.new()
		preset_selector.name = "BundlePresetSelector"
		preset_selector.custom_minimum_size = Vector2(200, 30)
		preset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# 找到模组列表的位置，在它之前插入
		var insert_pos = 0
		for i in range(bundle_details_vbox.get_child_count()):
			var child = bundle_details_vbox.get_child(i)
			if child.name == "BundleModsList":
				insert_pos = i
				break
			insert_pos = i + 1

		# 在最前面插入标签选择器（名称、作者、版本、描述之后）
		bundle_details_vbox.add_child(preset_selector)
		if insert_pos < bundle_details_vbox.get_child_count():
			bundle_details_vbox.move_child(preset_selector, insert_pos)

		# 连接信号
		preset_selector.item_selected.connect(_on_bundle_preset_changed)

		return preset_selector

	return null


# 整合包列表项选中
func _on_bundle_item_selected(index: int) -> void:
	if not bundles_list:
		return

	var item_text = bundles_list.get_item_text(index)
	# 从item获取bundle_id（存储在metadata中）
	var bundle_id = bundles_list.get_item_metadata(index)

	if bundle_id.is_empty():
		return

	selected_bundle_id = bundle_id
	_update_bundle_panel(bundle_id)


# 导入整合包按钮回调
func _on_import_bundle_pressed() -> void:
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.zip"]
	file_dialog.title = translate("select_bundle_file")
	add_child(file_dialog)
	file_dialog.file_selected.connect(_on_bundle_file_selected)
	file_dialog.popup_centered(Vector2(600, 400))


# 文件选择回调
func _on_bundle_file_selected(path: String) -> void:
	print("[_on_bundle_file_selected] path: ", path)
	_import_bundle(path)


# 处理整合包拖入
func _handle_bundle_drop(zip_files: Array) -> void:
	print("[_handle_bundle_drop] Processing ", zip_files.size(), " files")

	for file_path in zip_files:
		var result = _check_bundle_drop_conflict(str(file_path))
		if result.get("action") == "import":
			var success = _import_bundle(str(file_path))
			if success:
				show_notification(translate("bundle_imported").format({"name": result.get("bundle_name", "未知")}), true)
			else:
				show_notification(translate("extract_failed"), false)
		elif result.get("action") == "cancel":
			# 用户取消，不处理
			pass


# 检查整合包拖入时的冲突
# 返回: {"action": "import"|"skip"|"cancel", "bundle_name": String}
func _check_bundle_drop_conflict(file_path: String) -> Dictionary:
	var temp_dir = OS.get_environment("TEMP") + "/STS2_BundleCheck_" + str(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(temp_dir)

	# 解压检查
	var zip_reader = ZIPReader.new()
	if zip_reader.open(file_path) != OK:
		zip_reader.close()
		DirAccess.remove_absolute(temp_dir)
		return {"action": "skip", "bundle_name": ""}

	var files = zip_reader.get_files()
	for f in files:
		if f.ends_with("/"):
			continue
		var full_dest = temp_dir.path_join(f)
		DirAccess.make_dir_recursive_absolute(full_dest.get_base_dir())
		var data = zip_reader.read_file(f)
		var file = FileAccess.open(full_dest, FileAccess.WRITE)
		if file:
			file.store_buffer(data)
			file.close()
	zip_reader.close()

	# 查找bundle.json
	var bundle_json_path = ""
	var bundle_id = ""
	var bundle_name = ""
	var dir = DirAccess.open(temp_dir)
	if dir:
		dir.list_dir_begin()
		var entry = dir.get_next()
		while entry != "":
			if dir.current_is_dir() and entry != "." and entry != "..":
				var test_json = temp_dir + "/" + entry + "/bundle.json"
				if FileAccess.file_exists(test_json):
					bundle_json_path = test_json
					bundle_id = entry
					break
			entry = dir.get_next()
		dir.list_dir_end()

	if bundle_json_path.is_empty():
		bundle_json_path = temp_dir + "/bundle.json"
		if FileAccess.file_exists(bundle_json_path):
			bundle_id = "bundle_" + str(Time.get_unix_time_from_system())

	DirAccess.remove_absolute(temp_dir)

	if bundle_json_path.is_empty() or bundle_id.is_empty():
		show_notification(translate("bundle_json_missing"), false)
		return {"action": "skip", "bundle_name": ""}

	# 读取bundle.json
	var bundle_data = _load_json(bundle_json_path)
	if bundle_data.is_empty():
		show_notification(translate("bundle_json_invalid"), false)
		return {"action": "skip", "bundle_name": ""}

	bundle_name = bundle_data.get("name", bundle_id)
	var new_version = bundle_data.get("version", "v0.0.0")
	var new_sanitized = _sanitize_folder_name(bundle_name)

	# 检查是否已存在同名整合包
	var existing_bundle_id = _find_bundle_by_name(new_sanitized)
	if existing_bundle_id.is_empty():
		# 没有冲突，直接导入
		return {"action": "import", "bundle_name": bundle_name}

	# 存在同名整合包，比较版本
	var existing_data = self.bundle_data.get(existing_bundle_id, {})
	var existing_version = existing_data.get("version", "v0.0.0")
	print("[_check_bundle_drop_conflict] existing_bundle_id: '", existing_bundle_id, "'")
	print("[_check_bundle_drop_conflict] existing_version from self.bundle_data: '", existing_version, "'")
	print("[_check_bundle_drop_conflict] new_version: '", new_version, "'")

	var cmp = _compare_versions(existing_version, new_version)
	print("[_check_bundle_drop_conflict] cmp result: ", cmp, " (1=newer, -1=older, 0=same)")
	_show_bundle_conflict_dialog(bundle_name, existing_version, new_version, file_path, existing_bundle_id)
	return {"action": "cancel", "bundle_name": bundle_name}


# 显示整合包冲突对话框
func _show_bundle_conflict_dialog(bundle_name: String, existing_version: String, new_version: String, file_path: String, existing_bundle_id: String) -> void:
	var dialog = Window.new()
	dialog.name = "BundleConflictDialog"
	dialog.title = translate("bundle_conflict_title")
	dialog.size = Vector2i(450, 280)
	dialog.unresizable = false
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	add_child(dialog)
	dialog.close_requested.connect(func(): dialog.queue_free())

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 15)
	dialog.add_child(vbox)

	# 标题
	var title_label = Label.new()
	title_label.text = translate("bundle_conflict_detected").format({"name": bundle_name})
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	# 版本信息
	var version_label = Label.new()
	version_label.text = translate("bundle_version_info").format({"existing": existing_version, "new": new_version})
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(version_label)

	# 按钮容器
	var btn_vbox = VBoxContainer.new()
	btn_vbox.custom_minimum_size = Vector2(300, 0)
	btn_vbox.add_theme_constant_override("separation", 10)
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND
	vbox.add_child(spacer)
	vbox.add_child(btn_vbox)

	# 保留现有按钮
	var keep_btn = Button.new()
	keep_btn.text = translate("bundle_keep_existing").format({"version": existing_version})
	keep_btn.custom_minimum_size = Vector2(0, 40)
	keep_btn.pressed.connect(func():
		dialog.queue_free()
	)
	btn_vbox.add_child(keep_btn)

	# 替换按钮
	var replace_btn = Button.new()
	replace_btn.text = translate("bundle_replace").format({"version": new_version})
	replace_btn.custom_minimum_size = Vector2(0, 40)
	replace_btn.pressed.connect(func():
		dialog.queue_free()
		# 删除旧版本
		_delete_bundle(existing_bundle_id)
		# 导入新版本
		var success = _import_bundle(file_path)
		if success:
			show_notification(translate("bundle_updated").format({"name": bundle_name, "version": new_version}), true)
	)
	btn_vbox.add_child(replace_btn)

	# 同时保留按钮
	var keep_both_btn = Button.new()
	keep_both_btn.text = translate("bundle_keep_both")
	keep_both_btn.custom_minimum_size = Vector2(0, 40)
	keep_both_btn.pressed.connect(func():
		dialog.queue_free()
		# 以新名称导入（添加版本后缀）
		var new_name = bundle_name + "_" + new_version
		var success = _import_bundle_with_name(file_path, new_name)
		if success:
			show_notification(translate("bundle_imported").format({"name": new_name}), true)
	)
	btn_vbox.add_child(keep_both_btn)

	# 取消按钮
	var cancel_btn = Button.new()
	cancel_btn.text = translate("cancel")
	cancel_btn.custom_minimum_size = Vector2(0, 35)
	cancel_btn.pressed.connect(func():
		dialog.queue_free()
	)
	btn_vbox.add_child(cancel_btn)

	dialog.popup_centered()


# 根据名称查找整合包ID
func _find_bundle_by_name(sanitized_name: String) -> String:
	for bid in bundle_data.keys():
		var data = bundle_data[bid]
		var name = data.get("name", "")
		var sanitized = _sanitize_folder_name(name)
		if sanitized == sanitized_name:
			return bid
	return ""


# 导入整合包ZIP
func _import_bundle(zip_path: String) -> bool:
	var extract_dir = _get_newpackage_dir()
	if extract_dir.is_empty():
		show_notification(translate("package_dir_error"), false)
		return false

	# 创建临时解压目录
	var temp_dir = OS.get_environment("TEMP") + "/STS2_Bundle_" + str(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(temp_dir)
	if not DirAccess.dir_exists_absolute(temp_dir):
		show_notification(translate("extract_failed"), false)
		return false

	# 解压ZIP
	var zip_reader = ZIPReader.new()
	var open_result = zip_reader.open(zip_path)
	if open_result != OK:
		show_notification(translate("extract_failed"), false)
		return false

	var files = zip_reader.get_files()
	for file_path in files:
		# 跳过目录（以/结尾）
		if file_path.ends_with("/"):
			continue

		var full_destination = temp_dir.path_join(file_path)

		# 创建目标文件的目录
		var dest_dir = DirAccess.open(full_destination.get_base_dir())
		if dest_dir == null:
			DirAccess.make_dir_recursive_absolute(full_destination.get_base_dir())

		# 读取并写入文件
		var data = zip_reader.read_file(file_path)
		var file = FileAccess.open(full_destination, FileAccess.WRITE)
		if file:
			file.store_buffer(data)
			file.close()

	zip_reader.close()

	# 查找bundle.json
	var bundle_json_path = ""
	var bundle_id = ""
	var dir = DirAccess.open(temp_dir)
	if dir:
		dir.list_dir_begin()
		var entry = dir.get_next()
		while entry != "":
			if dir.current_is_dir() and entry != "." and entry != "..":
				var test_json = temp_dir + "/" + entry + "/bundle.json"
				if FileAccess.file_exists(test_json):
					bundle_json_path = test_json
					bundle_id = entry
					break
			entry = dir.get_next()
		dir.list_dir_end()

	if bundle_json_path.is_empty() or bundle_id.is_empty():
		# 尝试直接在根目录查找
		bundle_json_path = temp_dir + "/bundle.json"
		if FileAccess.file_exists(bundle_json_path):
			bundle_id = "bundle_" + str(Time.get_unix_time_from_system())
		else:
			show_notification(translate("bundle_json_missing"), false)
			_delete_directory_recursive(temp_dir)
			return false

	# 读取bundle.json
	var data = _load_json(bundle_json_path)
	if data.is_empty():
		show_notification(translate("bundle_json_invalid"), false)
		_delete_directory_recursive(temp_dir)
		return false

	# 验证必要字段
	if not data.has("name") or not data.has("mods"):
		show_notification(translate("bundle_json_invalid"), false)
		_delete_directory_recursive(temp_dir)
		return false

	# 使用name作为文件夹名称，清理特殊字符
	var bundle_name = data.get("name", bundle_id)
	var sanitized_name = _sanitize_folder_name(bundle_name)
	var target_dir = extract_dir + "/" + sanitized_name
	_delete_directory_recursive(target_dir)
	DirAccess.make_dir_recursive_absolute(target_dir)

	# 使用FileUtils复制文件
	if not FileUtils.copy_directory(temp_dir, target_dir):
		show_notification(translate("extract_failed"), false)
		_delete_directory_recursive(temp_dir)
		return false

	_delete_directory_recursive(temp_dir)

	# 添加到bundle_data，使用sanitized_name作为key
	bundle_data[sanitized_name] = data

	# 保存
	_save_bundle_json(sanitized_name, data)
	_refresh_bundle_list()
	show_notification(translate_fmt("bundle_imported", [bundle_name]), true)

	return true


# 导入整合包ZIP（指定名称，用于"同时保留"场景）
func _import_bundle_with_name(zip_path: String, custom_name: String) -> bool:
	var extract_dir = _get_newpackage_dir()
	if extract_dir.is_empty():
		show_notification(translate("package_dir_error"), false)
		return false

	# 创建临时解压目录
	var temp_dir = OS.get_environment("TEMP") + "/STS2_Bundle_" + str(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(temp_dir)
	if not DirAccess.dir_exists_absolute(temp_dir):
		show_notification(translate("extract_failed"), false)
		return false

	# 解压ZIP
	var zip_reader = ZIPReader.new()
	var open_result = zip_reader.open(zip_path)
	if open_result != OK:
		show_notification(translate("extract_failed"), false)
		_delete_directory_recursive(temp_dir)
		return false

	var files = zip_reader.get_files()
	for file_path in files:
		if file_path.ends_with("/"):
			continue
		var full_destination = temp_dir.path_join(file_path)
		var dest_dir = DirAccess.open(full_destination.get_base_dir())
		if dest_dir == null:
			DirAccess.make_dir_recursive_absolute(full_destination.get_base_dir())
		var data = zip_reader.read_file(file_path)
		var file = FileAccess.open(full_destination, FileAccess.WRITE)
		if file:
			file.store_buffer(data)
			file.close()
	zip_reader.close()

	# 查找bundle.json并读取数据
	var bundle_json_path = ""
	var dir = DirAccess.open(temp_dir)
	if dir:
		dir.list_dir_begin()
		var entry = dir.get_next()
		while entry != "":
			if dir.current_is_dir() and entry != "." and entry != "..":
				var test_json = temp_dir + "/" + entry + "/bundle.json"
				if FileAccess.file_exists(test_json):
					bundle_json_path = test_json
					break
			entry = dir.get_next()
		dir.list_dir_end()

	if bundle_json_path.is_empty():
		bundle_json_path = temp_dir + "/bundle.json"

	if not FileAccess.file_exists(bundle_json_path):
		show_notification(translate("bundle_json_missing"), false)
		_delete_directory_recursive(temp_dir)
		return false

	var data = _load_json(bundle_json_path)
	if data.is_empty() or not data.has("name") or not data.has("mods"):
		show_notification(translate("bundle_json_invalid"), false)
		_delete_directory_recursive(temp_dir)
		return false

	# 使用指定的名称
	var sanitized_name = _sanitize_folder_name(custom_name)
	var target_dir = extract_dir + "/" + sanitized_name
	_delete_directory_recursive(target_dir)
	DirAccess.make_dir_recursive_absolute(target_dir)

	# 复制文件
	if not FileUtils.copy_directory(temp_dir, target_dir):
		show_notification(translate("extract_failed"), false)
		_delete_directory_recursive(temp_dir)
		return false

	_delete_directory_recursive(temp_dir)

	# 添加到bundle_data
	bundle_data[sanitized_name] = data
	_save_bundle_json(sanitized_name, data)
	_refresh_bundle_list()

	return true


# 导出为整合包按钮回调
func _on_export_bundle_pressed() -> void:
	if enabled_mods.is_empty():
		show_notification(translate("no_enabled_mods"), false)
		return

	_show_export_bundle_dialog()


# 显示导出整合包对话框
func _show_export_bundle_dialog() -> void:
	var dialog = Window.new()
	dialog.name = "ExportBundleDialog"
	dialog.title = translate("export_bundle")
	dialog.size = Vector2i(450, 350)
	dialog.transient = true
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	add_child(dialog)
	dialog.close_requested.connect(func(): dialog.queue_free())

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(vbox)

	# 名称
	var name_label = Label.new()
	name_label.text = translate("bundle_name")
	vbox.add_child(name_label)

	var name_edit = LineEdit.new()
	name_edit.name = "BundleNameEdit"
	name_edit.custom_minimum_size = Vector2(0, 35)
	vbox.add_child(name_edit)

	# 作者
	var author_label = Label.new()
	author_label.text = translate("author_label")
	vbox.add_child(author_label)

	var author_edit = LineEdit.new()
	author_edit.name = "BundleAuthorEdit"
	author_edit.custom_minimum_size = Vector2(0, 35)
	vbox.add_child(author_edit)

	# 版本
	var version_label = Label.new()
	version_label.text = translate("version_label")
	vbox.add_child(version_label)

	var version_edit = LineEdit.new()
	version_edit.name = "BundleVersionEdit"
	version_edit.text = "v1.0.0"
	version_edit.custom_minimum_size = Vector2(0, 35)
	vbox.add_child(version_edit)

	# 描述
	var desc_label = Label.new()
	desc_label.text = translate("description_label")
	vbox.add_child(desc_label)

	var desc_edit = TextEdit.new()
	desc_edit.name = "BundleDescEdit"
	desc_edit.custom_minimum_size = Vector2(0, 80)
	vbox.add_child(desc_edit)

	# 导出按钮
	var export_btn = Button.new()
	export_btn.text = translate("export")
	export_btn.custom_minimum_size = Vector2(0, 40)
	export_btn.pressed.connect(func():
		var name = name_edit.text.strip_edges()
		var author = author_edit.text.strip_edges()
		var version = version_edit.text.strip_edges()
		var desc = desc_edit.text

		if name.is_empty():
			show_notification(translate("name_required"), false)
			return

		_create_and_export_bundle(name, author, version, desc)
		dialog.queue_free()
	)
	vbox.add_child(export_btn)

	dialog.popup_centered()


# 创建并导出的回调
func _create_and_export_bundle(name: String, author: String, version: String, desc: String) -> void:
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.zip"]
	file_dialog.title = translate("save_bundle")
	add_child(file_dialog)
	file_dialog.file_selected.connect(func(path: String):
		call_deferred("_do_export_bundle_deferred", path, name, author, version, desc)
	)
	file_dialog.popup_centered(Vector2(600, 400))


# 异步导出为ZIP（避免卡顿）
func _do_export_bundle_deferred(zip_path: String, name: String, author: String, version: String, desc: String) -> void:
	_show_loading(translate("exporting_bundle") if translate("exporting_bundle") != "exporting_bundle" else "正在导出整合包...")
	await get_tree().process_frame
	_export_bundle_to_zip(zip_path, name, author, version, desc)
	_hide_loading()


# 导出为ZIP
func _export_bundle_to_zip(zip_path: String, name: String, author: String, version: String, desc: String) -> void:
	var bundle_id = "bundle_" + str(Time.get_unix_time_from_system())
	var package_dir = _get_newpackage_dir()
	if package_dir.is_empty():
		show_notification(translate("package_dir_error"), false)
		return

	var bundle_dir = package_dir + "/" + bundle_id
	DirAccess.make_dir_recursive_absolute(bundle_dir)

	# 创建bundle.json
	var data = {
		"id": bundle_id,
		"name": name,
		"author": author,
		"version": version,
		"description": desc,
		"mods": [],
		"presets": tag_data.duplicate(true),  # 导出预设（单人模组、联机模组、自定义标签等）
		"created_at": Time.get_datetime_string_from_system(),
		"updated_at": Time.get_datetime_string_from_system()
	}

	# 收集预设中所有涉及的模组ID（需要在遍历模组之前完成）
	var preset_mod_ids: Array = []
	for preset_name in tag_data.keys():
		for mod_id in tag_data[preset_name]:
			if not mod_id in preset_mod_ids:
				preset_mod_ids.append(mod_id)
	print("[_export_bundle_to_zip] preset_mod_ids: ", preset_mod_ids)

	# 遍历temp_mods中所有的模组，根据配置文件中的enabled_mods来确定启用状态
	# 同时根据预设中涉及的模组来决定复制哪些文件
	var added_mod_ids: Array = []  # 去重
	var mods_dir = temp_mods_path  # 使用temp_mods_path

	if DirAccess.dir_exists_absolute(mods_dir):
		var dir = DirAccess.open(mods_dir)
		if dir:
			dir.list_dir_begin()
			var item_dir = dir.get_next()
			while item_dir != "":
				if item_dir != "." and item_dir != ".." and not item_dir.begins_with("_"):
					var mod_path = mods_dir.path_join(item_dir)
					if DirAccess.dir_exists_absolute(mod_path):
						var mod_id = item_dir

						# 跳过 .zip 结尾的无效模组ID
						if ".zip" in mod_id:
							item_dir = dir.get_next()
							continue

						# 去重
						if mod_id in added_mod_ids:
							item_dir = dir.get_next()
							continue
						added_mod_ids.append(mod_id)

						# 只添加在预设中出现的模组
						if mod_id in preset_mod_ids:
							var mod_info = {
								"id": mod_id,
								"tags": []
							}
							data["mods"].append(mod_info)

							# 复制预设中涉及的模组文件
							var target_mod_dir = bundle_dir + "/mods/" + mod_id
							DirAccess.make_dir_recursive_absolute(target_mod_dir)
							FileUtils.copy_directory(mod_path, target_mod_dir)
							print("[_export_bundle_to_zip] Copied mod: ", mod_id)
				item_dir = dir.get_next()
			dir.list_dir_end()

	# 保存bundle.json
	_save_bundle_json(bundle_id, data)

	# 复制预览图（如果存在）
	var base_path = get_base_path()
	var preview_source = base_path + "/bundle_preview.png"
	if FileAccess.file_exists(preview_source):
		var preview_target = bundle_dir + "/preview.png"
		FileUtils.copy_file(preview_source, preview_target)
		print("[_export_bundle_to_zip] Copied preview.png")

	# 复制配置文件（如果存在）
	_copy_config_to_bundle(bundle_dir)

	# 创建ZIP文件
	if not _create_zip_from_dir(bundle_dir, zip_path):
		show_notification(translate("bundle_export_failed"), false)
		return

	# 清理临时bundle目录
	_delete_directory_recursive(bundle_dir)

	show_notification(translate_fmt("bundle_exported", [name]), true)


# 复制配置文件到整合包
func _copy_config_to_bundle(bundle_dir: String) -> void:
	# 复制模组配置文件（mods 目录下的所有 .json）
	var mods_config_dir = get_base_path() + "/mods"
	if DirAccess.dir_exists_absolute(mods_config_dir):
		var target_configs_dir = bundle_dir + "/mods_configs"
		DirAccess.make_dir_recursive_absolute(target_configs_dir)

		var dir = DirAccess.open(mods_config_dir)
		if dir:
			dir.list_dir_begin()
			var entry = dir.get_next()
			while entry != "":
				if entry.ends_with(".json"):
					var source = mods_config_dir + "/" + entry
					var target = target_configs_dir + "/" + entry
					FileUtils.copy_file(source, target)
					print("[_copy_config_to_bundle] Copied: ", entry)
				entry = dir.get_next()
			dir.list_dir_end()


# 从目录创建ZIP文件
func _create_zip_from_dir(source_dir: String, zip_path: String) -> bool:
	# 确保ZIP路径以.zip结尾
	if not zip_path.to_lower().ends_with(".zip"):
		zip_path += ".zip"

	# 如果已存在，先删除
	if FileAccess.file_exists(zip_path):
		DirAccess.remove_absolute(zip_path)

	# 使用PowerShell压缩为ZIP文件
	var source_dir_win = FileUtils.to_windows_path(ProjectSettings.globalize_path(source_dir))
	var zip_path_win = FileUtils.to_windows_path(ProjectSettings.globalize_path(zip_path))

	var ps_command = 'Compress-Archive -Path "%s\\*" -DestinationPath "%s" -Force' % [source_dir_win, zip_path_win]

	var output = []
	var exit_code = OS.execute("powershell", ["-Command", ps_command], output, true, true)

	if exit_code != 0:
		print("[_create_zip_from_dir] Failed to create ZIP: ", output)
		return false

	print("[_create_zip_from_dir] Created ZIP: ", zip_path)
	return true


# 检查更新按钮回调
func _on_check_bundle_update_pressed() -> void:
	if selected_bundle_id.is_empty():
		show_notification(translate("select_bundle_first"), false)
		return

	_check_bundle_update(selected_bundle_id)


# 删除整合包按钮回调
func _on_delete_bundle_pressed() -> void:
	if selected_bundle_id.is_empty():
		show_notification(translate("select_bundle_first"), false)
		return

	_delete_bundle(selected_bundle_id)
	selected_bundle_id = ""


# 编辑整合包预设中的模组
func _on_edit_bundle_pressed() -> void:
	var bundle_id = selected_bundle_id

	if bundle_id.is_empty():
		show_notification(translate("select_bundle_first"), false)
		return

	var data = bundle_data.get(bundle_id, {})
	if data.is_empty():
		return

	# 创建编辑对话框
	var dialog = Window.new()
	dialog.name = "EditBundleDialog"
	dialog.size = Vector2i(500, 600)
	dialog.title = translate("edit_bundle_presets")
	dialog.transient = true
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	add_child(dialog)

	# 主容器
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("margin_left", 20)
	vbox.add_theme_constant_override("margin_top", 20)
	vbox.add_theme_constant_override("margin_right", 20)
	vbox.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(vbox)

	# 预设选择
	var preset_label = Label.new()
	preset_label.text = translate("select_preset")
	vbox.add_child(preset_label)

	var preset_combo = OptionButton.new()
	preset_combo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(preset_combo)

	# 预设列表
	var presets = data.get("presets", {})
	var current_preset = ""
	for preset_name in presets.keys():
		preset_combo.add_item(preset_name)
		if preset_name == selected_bundle_preset:
			current_preset = preset_name
	if not current_preset.is_empty():
		var idx = presets.keys().find(current_preset)
		if idx >= 0:
			preset_combo.select(idx)
	elif not presets.is_empty():
		current_preset = presets.keys()[0]
		preset_combo.select(0)

	# 模组列表容器（带滚动）
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 350)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var mods_vbox = VBoxContainer.new()
	mods_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mods_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(mods_vbox)

	# 模组复选框列表
	var mod_checks: Array = []

	# 填充模组列表（去重）- 只显示在任意预设中出现的模组
	var mods = data.get("mods", [])
	var seen_mods: Array = []

	# 收集所有预设中出现的模组
	var all_preset_mods: Array = []
	for preset_name in presets.keys():
		for mod_id in presets[preset_name]:
			if not mod_id in all_preset_mods:
				all_preset_mods.append(mod_id)

	var preset_mods = []
	if current_preset in presets:
		preset_mods = presets[current_preset]

	for mod in mods:
		var mod_id = mod.get("id", "")
		if ".zip" in mod_id or mod_id.is_empty():
			continue
		if mod_id in seen_mods:
			continue
		seen_mods.append(mod_id)

		# 只显示在任意预设中出现的模组
		if not mod_id in all_preset_mods:
			continue

		var check = CheckBox.new()
		check.text = mod_id
		check.button_pressed = mod_id in preset_mods
		mods_vbox.add_child(check)
		mod_checks.append(check)

	# 按钮容器
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_hbox)

	var select_all_btn = Button.new()
	select_all_btn.text = translate("select_all")
	btn_hbox.add_child(select_all_btn)

	var deselect_all_btn = Button.new()
	deselect_all_btn.text = translate("deselect_all")
	btn_hbox.add_child(deselect_all_btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_hbox.add_child(spacer)

	var save_btn = Button.new()
	save_btn.text = translate("save")
	btn_hbox.add_child(save_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = translate("cancel")
	btn_hbox.add_child(cancel_btn)

	# 按钮功能
	select_all_btn.pressed.connect(func():
		for check in mod_checks:
			check.button_pressed = true
	)

	deselect_all_btn.pressed.connect(func():
		for check in mod_checks:
			check.button_pressed = false
	)

	# 预设切换时更新模组列表
	preset_combo.item_selected.connect(func(index: int):
		current_preset = presets.keys()[index]
		preset_mods = presets[current_preset]
		for i in range(mod_checks.size()):
			mod_checks[i].button_pressed = mods[i].get("id", "") in preset_mods
	)

	save_btn.pressed.connect(func():
		# 收集选中的模组（去重）
		var new_preset_mods: Array = []
		var seen_ids: Array = []
		for i in range(mod_checks.size()):
			if mod_checks[i].button_pressed:
				var mod_id = mods[i].get("id", "")
				if not mod_id in seen_ids:
					seen_ids.append(mod_id)
					new_preset_mods.append(mod_id)

		# 更新预设数据
		presets[current_preset] = new_preset_mods
		data["presets"] = presets
		bundle_data[bundle_id] = data

		# 保存到文件
		_save_bundle_json(bundle_id, data)

		# 如果当前整合包已启用，重新应用该预设
		if active_bundle == bundle_id:
			_reapply_bundle_preset(bundle_id, current_preset)

		# 更新显示
		selected_bundle_preset = current_preset
		_update_bundle_panel(bundle_id)

		dialog.queue_free()
		show_notification(translate("bundle_preset_saved"), true)
	)

	cancel_btn.pressed.connect(func():
		dialog.queue_free()
	)

	dialog.popup_centered(Vector2(500, 600))


# 加载所有已导入的整合包
func _load_bundles() -> void:
	bundle_data.clear()

	# 获取整合包目录
	var package_dir = _get_newpackage_dir()
	if package_dir.is_empty():
		return

	# 扫描目录
	var dir = DirAccess.open(package_dir)
	if not dir:
		return

	dir.list_dir_begin()
	var bundle_id = dir.get_next()
	while bundle_id != "":
		if not dir.current_is_dir() or bundle_id == "." or bundle_id == "..":
			bundle_id = dir.get_next()
			continue

		var bundle_json_path = package_dir + "/" + bundle_id + "/bundle.json"
		if FileAccess.file_exists(bundle_json_path):
			var data = _load_json(bundle_json_path)
			if not data.is_empty():
				bundle_data[bundle_id] = data

		bundle_id = dir.get_next()

	dir.list_dir_end()

	# 恢复之前启用的整合包及其状态
	var saved_active = config.get_value("bundles", "active_bundle", "")
	var previous_data = config.get_value("bundles", "bundle_previous_state", {})
	var bundle_selected_presets = config.get_value("bundles", "bundle_selected_presets", {})

	if not saved_active.is_empty() and bundle_data.has(saved_active):
		# 恢复active_bundle
		active_bundle = saved_active
		# 从保存的每个整合包的预设中恢复
		selected_bundle_preset = bundle_selected_presets.get(saved_active, "")

		# 恢复 previous_state
		if previous_data.has(saved_active):
			var state = previous_data[saved_active]
			previous_enabled_mods = state.get("enabled_mods", {})
			previous_tag_data = state.get("tag_data", {})

		# 重新应用该预设
		if not selected_bundle_preset.is_empty():
			var data = bundle_data[saved_active]
			var presets = data.get("presets", {})
			if presets.has(selected_bundle_preset):
				_reapply_bundle_preset(saved_active, selected_bundle_preset)

	# 刷新显示
	_refresh_bundle_list()


# 刷新整合包列表显示
func _refresh_bundle_list() -> void:
	if not bundle_container:
		return

	# 清空现有卡片
	for child in bundle_container.get_children():
		child.queue_free()
	bundle_items.clear()

	# 显示空提示
	if bundle_data.is_empty():
		_show_empty_details()
		return

	# 隐藏空提示
	if bundle_info_labels.has("empty") and bundle_info_labels["empty"]:
		bundle_info_labels["empty"].visible = false
	if bundle_info_labels.has("name") and bundle_info_labels["name"]:
		bundle_info_labels["name"].visible = false
	if bundle_info_labels.has("author") and bundle_info_labels["author"]:
		bundle_info_labels["author"].visible = false
	if bundle_info_labels.has("version") and bundle_info_labels["version"]:
		bundle_info_labels["version"].visible = false
	if bundle_info_labels.has("desc") and bundle_info_labels["desc"]:
		bundle_info_labels["desc"].visible = false

	# 创建整合包卡片
	for bundle_id in bundle_data:
		var data = bundle_data[bundle_id]
		_create_bundle_card(bundle_id, data)

	# 刷新选中效果
	_refresh_bundle_cards_selection()


# 显示空状态详情
func _show_empty_details() -> void:
	if bundle_info_labels.has("empty") and bundle_info_labels["empty"]:
		bundle_info_labels["empty"].visible = true
	if bundle_info_labels.has("name") and bundle_info_labels["name"]:
		bundle_info_labels["name"].visible = false
	if bundle_info_labels.has("author") and bundle_info_labels["author"]:
		bundle_info_labels["author"].visible = false
	if bundle_info_labels.has("version") and bundle_info_labels["version"]:
		bundle_info_labels["version"].visible = false
	if bundle_info_labels.has("desc") and bundle_info_labels["desc"]:
		bundle_info_labels["desc"].visible = false

	# 隐藏模组列表
	if bundle_mods_list:
		bundle_mods_list.clear()
		bundle_mods_list.visible = false

	# 已移除详情面板中的启用开关（.BundleEnableSwitch）
	# 显示整合包详情
func _update_bundle_panel(bundle_id: String) -> void:
	if not bundle_data.has(bundle_id):
		return

	var data = bundle_data[bundle_id]

	# 隐藏空提示，显示详情
	if bundle_info_labels.has("empty") and bundle_info_labels["empty"]:
		bundle_info_labels["empty"].visible = false

	# 更新名称
	if bundle_info_labels.has("name") and bundle_info_labels["name"]:
		bundle_info_labels["name"].text = data.get("name", bundle_id)
		bundle_info_labels["name"].visible = true

	# 更新作者
	if bundle_info_labels.has("author") and bundle_info_labels["author"]:
		bundle_info_labels["author"].text = translate_fmt("author_colon", [data.get("author", "Unknown")])
		bundle_info_labels["author"].visible = true

	# 更新版本
	if bundle_info_labels.has("version") and bundle_info_labels["version"]:
		bundle_info_labels["version"].text = translate_fmt("version_colon", [data.get("version", "v1.0.0")])
		bundle_info_labels["version"].visible = true

	# 更新描述
	if bundle_info_labels.has("desc") and bundle_info_labels["desc"]:
		bundle_info_labels["desc"].text = data.get("description", "")
		bundle_info_labels["desc"].visible = true

	# 获取预设数据
	var presets = data.get("presets", {})
	var current_preset_mods = []

	# 获取当前预设的模组列表
	if not presets.is_empty():
		var preset_names = presets.keys()
		# 从config中获取当前整合包保存的预设
		var bundle_selected_presets = config.get_value("bundles", "bundle_selected_presets", {})
		var bundle_saved_preset = bundle_selected_presets.get(bundle_id, "")

		# 如果当前选中的整合包就是要显示的
		if selected_bundle_id == bundle_id:
			# 优先使用保存的选中预设
			if not bundle_saved_preset.is_empty() and bundle_saved_preset in presets:
				current_preset_mods = presets[bundle_saved_preset]
				selected_bundle_preset = bundle_saved_preset
			# 其次使用当前标签（如果整合包已启用）
			elif active_bundle == bundle_id and current_tag in presets:
				current_preset_mods = presets[current_tag]
			# 默认使用第一个预设
			elif preset_names.size() > 0:
				current_preset_mods = presets[preset_names[0]]
				selected_bundle_preset = preset_names[0]
		elif preset_names.size() > 0:
			current_preset_mods = presets[preset_names[0]]

	# 显示模组列表 - 只显示当前预设的模组
	if bundle_mods_list:
		bundle_mods_list.clear()
		if not current_preset_mods.is_empty():
			for mod_id in current_preset_mods:
				bundle_mods_list.add_item(mod_id)
		else:
			# 如果没有预设，显示所有模组（带启用状态标记）
			var mods = data.get("mods", [])
			for mod in mods:
				var mod_id = mod.get("id", "unknown")
				if ".zip" in mod_id:
					continue
				var is_enabled = mod.get("enabled", false)
				var display_text = mod_id + (" [已启用]" if is_enabled else " [未启用]")
				bundle_mods_list.add_item(display_text)
		bundle_mods_list.visible = true

	# 显示预设选择器 - 动态创建如果不存在
	if bundle_info_labels.has("preset_selector") and bundle_info_labels["preset_selector"]:
		var preset_selector = bundle_info_labels["preset_selector"]
		if preset_selector:
			preset_selector.clear()
			if not presets.is_empty():
				var index = 0
				var current_index = 0
				for preset_name in presets.keys():
					preset_selector.add_item(preset_name)
					# 优先使用保存的选中预设
					if preset_name == selected_bundle_preset:
						current_index = index
					elif current_index == 0 and active_bundle == bundle_id and preset_name == current_tag:
						current_index = index
					index += 1
				# 选中当前预设
				if current_index >= 0 and current_index < preset_selector.get_item_count():
					preset_selector.select(current_index)
				preset_selector.visible = true
			else:
				preset_selector.visible = false

	# 显示编辑按钮
	var edit_btn = find_child_node(self, "EditBundleBtn")
	if not edit_btn and bundle_details_vbox:
		# 动态创建按钮
		edit_btn = Button.new()
		edit_btn.name = "EditBundleBtn"
		edit_btn.text = translate("edit")
		edit_btn.custom_minimum_size = Vector2(80, 30)
		bundle_details_vbox.add_child(edit_btn)
		edit_btn.pressed.connect(_on_edit_bundle_pressed)

	if edit_btn:
		edit_btn.visible = true


# 创建整合包卡片
func _create_bundle_card(bundle_id: String, data: Dictionary) -> void:
	var card = PanelContainer.new()
	card.name = "BundleCard_" + bundle_id
	card.custom_minimum_size = Vector2(220, 200)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# 卡片样式 - 增加质感和边框
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.22, 1)  # 稍亮的背景
	style.set_corner_radius_all(12)
	style.set_content_margin_all(10)  # 内边距
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.35, 1)
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	# 预览图
	var texture_rect = TextureRect.new()
	texture_rect.name = "BundlePreview"
	texture_rect.custom_minimum_size = Vector2(200, 112)  # 16:9比例
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vbox.add_child(texture_rect)

	# 加载预览图
	_load_bundle_preview(bundle_id, texture_rect)

	# 信息区域
	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 8)
	info_vbox.add_theme_constant_override("margin_top", 6)
	info_vbox.add_theme_constant_override("margin_bottom", 6)
	vbox.add_child(info_vbox)

	# 名称（放大）
	var name_label = Label.new()
	name_label.name = "BundleName_" + bundle_id
	name_label.text = data.get("name", bundle_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = 4
	name_label.add_theme_font_size_override("font_size", 18)
	info_vbox.add_child(name_label)

	# Switch开关（放大）
	var switch_container = HBoxContainer.new()
	switch_container.alignment = BoxContainer.ALIGNMENT_CENTER
	info_vbox.add_child(switch_container)

	var switch_btn = CheckButton.new()
	switch_btn.name = "BundleSwitch_" + bundle_id
	switch_btn.button_pressed = (active_bundle == bundle_id)
	switch_btn.custom_minimum_size = Vector2(56, 30)  # 放大
	switch_btn.toggled.connect(func(toggled_on): _on_bundle_switch_toggled(bundle_id, toggled_on))
	switch_container.add_child(switch_btn)

	# 点击选中卡片并显示详情
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton:
			var mouse_event = event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
				# 只有在选择不同卡片时才重置预设
				if selected_bundle_id != bundle_id:
					selected_bundle_preset = ""
				selected_bundle_id = bundle_id
				_update_bundle_panel(bundle_id)
				# 刷新卡片选中效果
				_refresh_bundle_cards_selection()
	)

	bundle_container.add_child(card)
	bundle_items[bundle_id] = card


# 刷新卡片选中效果
func _refresh_bundle_cards_selection() -> void:
	for bundle_id in bundle_items:
		var card = bundle_items[bundle_id]
		var style = card.get_theme_stylebox("panel")
		if style:
			if bundle_id == selected_bundle_id:
				# 选中状态 - 边框高亮
				style.border_color = Color(0.4, 0.6, 0.9, 1)  # 蓝色高亮
				style.border_width_bottom = 3
			else:
				# 未选中状态 - 普通边框
				style.border_color = Color(0.3, 0.3, 0.35, 1)
				style.border_width_bottom = 2


# 整合包Switch开关切换
func _on_bundle_switch_toggled(bundle_id: String, toggled_on: bool) -> void:
	print("[_on_bundle_switch_toggled] bundle_id: ", bundle_id, ", toggled_on: ", toggled_on)
	if toggled_on:
		# 启用整合包
		_enable_bundle(bundle_id)
	else:
		# 禁用整合包
		if active_bundle == bundle_id:
			_disable_bundle()


# 加载整合包预览图
func _load_bundle_preview(bundle_id: String, texture_rect: TextureRect) -> void:
	var package_dir = _get_newpackage_dir()
	if package_dir.is_empty():
		return

	var preview_path = package_dir + "/" + bundle_id + "/preview.png"
	if not FileAccess.file_exists(preview_path):
		# 使用占位背景色
		var placeholder = StyleBoxFlat.new()
		placeholder.bg_color = Color(0.2, 0.2, 0.2, 1)
		texture_rect.add_theme_stylebox_override("panel", placeholder)
		return

	var image = Image.new()
	var err = image.load(preview_path)
	if err != OK:
		print("[_load_bundle_preview] Failed to load image: ", preview_path)
		return

	var texture = ImageTexture.create_from_image(image)
	texture_rect.texture = texture


# 整合包开关切换
func _on_bundle_enable_toggled(toggled_on: bool) -> void:
	print("[_on_bundle_enable_toggled] toggled_on: ", toggled_on, ", active_bundle: ", active_bundle)
	if toggled_on:
		# 需要选择一个整合包来启用
		if active_bundle.is_empty():
			# 显示选择整合包的对话框
			_show_select_bundle_dialog()
	else:
		# 禁用当前整合包
		_disable_bundle()


# 重新应用指定预设的模组（用于编辑保存后刷新）
func _reapply_bundle_preset(bundle_id: String, preset_name: String) -> void:
	var data = bundle_data.get(bundle_id, {})
	if data.is_empty():
		return

	var presets = data.get("presets", {})
	if not presets.has(preset_name):
		return

	var preset_mods = presets[preset_name]
	var package_dir = _get_newpackage_dir()
	var bundle_mods_dir = package_dir.path_join(bundle_id).path_join("mods")
	var game_mods_dir = game_path.path_join("mods")

	# 清空并重新复制
	if DirAccess.dir_exists_absolute(game_mods_dir):
		var dir = DirAccess.open(game_mods_dir)
		if dir:
			dir.list_dir_begin()
			var entry = dir.get_next()
			while entry != "":
				if entry != "." and entry != ".." and not entry.begins_with("."):
					var entry_path = game_mods_dir.path_join(entry)
					if DirAccess.dir_exists_absolute(entry_path):
						_delete_directory_recursive(entry_path)
					elif FileAccess.file_exists(entry_path):
						DirAccess.remove_absolute(entry_path)
				entry = dir.get_next()
			dir.list_dir_end()

	# 复制新预设的模组
	for mod_id in preset_mods:
		var source_mod_dir = bundle_mods_dir.path_join(mod_id)
		var target_mod_dir = game_mods_dir.path_join(mod_id)

		if DirAccess.dir_exists_absolute(source_mod_dir):
			DirAccess.make_dir_recursive_absolute(target_mod_dir)
			FileUtils.copy_directory(source_mod_dir, target_mod_dir)

	# 更新enabled_mods
	enabled_mods.clear()
	for mod_id in preset_mods:
		enabled_mods[mod_id] = true
	_save_enabled_mods()

	# 更新标签
	current_tag = preset_name
	tag_data = presets.duplicate(true)
	_save_tag_data()

	# 更新UI
	_build_tag_buttons()


# 切换预设时应用该预设的模组配置
func _on_bundle_preset_changed(index: int) -> void:
	# 优先使用已启用的整合包，否则使用选中的整合包
	var current_bundle = active_bundle
	if current_bundle.is_empty():
		current_bundle = selected_bundle_id

	if current_bundle.is_empty():
		return

	var data = bundle_data.get(current_bundle, {})
	if data.is_empty():
		return

	var presets = data.get("presets", {})
	if presets.is_empty():
		return

	var preset_names = presets.keys()
	if index < 0 or index >= preset_names.size():
		return

	var preset_name = preset_names[index]

	# 更新保存的选中预设
	selected_bundle_preset = preset_name

	# 保存到config（为当前选中的整合包保存预设）
	var bundle_selected_presets = config.get_value("bundles", "bundle_selected_presets", {})
	bundle_selected_presets[current_bundle] = preset_name
	config.set_value("bundles", "bundle_selected_presets", bundle_selected_presets)
	config.save(config_path)

	# 只有在整合包已启用时才实际切换模组
	if active_bundle == current_bundle:
		var preset_mods = presets[preset_name]

		# 清空游戏mods文件夹
		var game_mods_dir = game_path.path_join("mods")
		if DirAccess.dir_exists_absolute(game_mods_dir):
			var dir = DirAccess.open(game_mods_dir)
			if dir:
				dir.list_dir_begin()
				var entry = dir.get_next()
				while entry != "":
					if entry != "." and entry != ".." and not entry.begins_with("."):
						var entry_path = game_mods_dir.path_join(entry)
						if DirAccess.dir_exists_absolute(entry_path):
							_delete_directory_recursive(entry_path)
						elif FileAccess.file_exists(entry_path):
							DirAccess.remove_absolute(entry_path)
					entry = dir.get_next()
				dir.list_dir_end()

		# 从bundle mods目录复制模组到游戏目录
		var package_dir = _get_newpackage_dir()
		var bundle_mods_dir = package_dir.path_join(current_bundle).path_join("mods")

		for mod_id in preset_mods:
			# 复制模组文件
			var source_mod_dir = bundle_mods_dir.path_join(mod_id)
			var target_mod_dir = game_path.path_join("mods").path_join(mod_id)

			if DirAccess.dir_exists_absolute(source_mod_dir):
				DirAccess.make_dir_recursive_absolute(target_mod_dir)
				FileUtils.copy_directory(source_mod_dir, target_mod_dir)

				# 启用标签
				if not tag_data.has(preset_name):
					tag_data[preset_name] = []
				if not tag_data[preset_name].has(mod_id):
					tag_data[preset_name].append(mod_id)

		# 更新当前标签
		current_tag = preset_name
		_save_tag_data()

		# 更新UI
		_build_tag_buttons()

	# 刷新整合包详情面板（更新模组列表显示）
	_update_bundle_panel(current_bundle)


# 显示选择整合包对话框
func _show_select_bundle_dialog() -> void:
	if bundle_data.is_empty():
		show_notification(translate("no_bundle_to_select"), false)
		return

	var dialog = AcceptDialog.new()
	dialog.name = "SelectBundleDialog"
	dialog.title = translate("select_bundle")
	dialog.size = Vector2i(400, 300)
	add_child(dialog)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 250)
	dialog.add_child(scroll)

	var vbox = VBoxContainer.new()
	scroll.add_child(vbox)

	# 为每个整合包创建按钮
	for bundle_id in bundle_data:
		var data = bundle_data[bundle_id]
		var btn = Button.new()
		btn.text = "%s (%s)" % [data.get("name", bundle_id), data.get("version", "v1.0.0")]
		btn.custom_minimum_size = Vector2(0, 40)
		btn.pressed.connect(func(): _enable_bundle(bundle_id, dialog))
		vbox.add_child(btn)

	dialog.popup_centered()


# 启用整合包
func _enable_bundle(bundle_id: String, dialog: Control = null) -> void:
	if dialog and is_instance_valid(dialog):
		dialog.queue_free()

	var data = bundle_data.get(bundle_id, {})
	if data.is_empty():
		return

	# 互斥逻辑：如果已有其他整合包启用，先禁用它（会保存当前模组页状态到config）
	if not active_bundle.is_empty() and active_bundle != bundle_id:
		print("[_enable_bundle] Another bundle is active, disabling it first: ", active_bundle)
		_disable_bundle_and_save_state()

	# 确保game_path已加载
	if game_path.is_empty():
		game_path = config.get_value("paths", "game_path", "")

	# 保存当前启用的模组以便恢复
	previous_enabled_mods = enabled_mods.duplicate()

	# 保存当前预设以便恢复
	previous_tag_data = tag_data.duplicate(true)

	# 先设置active_bundle，以便后续逻辑知道已启用整合包
	active_bundle = bundle_id

	# 清空游戏mods文件夹（删除所有已启用的模组文件）
	var game_mods_dir = game_path.path_join("mods")
	if DirAccess.dir_exists_absolute(game_mods_dir):
		var dir = DirAccess.open(game_mods_dir)
		if dir:
			dir.list_dir_begin()
			var entry = dir.get_next()
			while entry != "":
				if entry != "." and entry != ".." and not entry.begins_with("."):
					var entry_path = game_mods_dir.path_join(entry)
					if DirAccess.dir_exists_absolute(entry_path):
						_delete_directory_recursive(entry_path)
					elif FileAccess.file_exists(entry_path):
						DirAccess.remove_absolute(entry_path)
				entry = dir.get_next()
			dir.list_dir_end()

	# 启用整合包预设的模组（使用当前预设过滤）
	var bundle_mods = data.get("mods", [])
	var bundle_presets = data.get("presets", {})
	var package_dir = _get_newpackage_dir()
	var bundle_mods_dir = package_dir.path_join(bundle_id).path_join("mods")

	# 获取当前预设的模组列表
	var current_preset_mods = []
	if not bundle_presets.is_empty():
		var preset_names = bundle_presets.keys()
		# 优先使用保存的选中预设
		if not selected_bundle_preset.is_empty() and selected_bundle_preset in bundle_presets:
			current_preset_mods = Array(bundle_presets[selected_bundle_preset])
		# 其次使用current_tag
		elif current_tag in bundle_presets:
			current_preset_mods = Array(bundle_presets[current_tag])
		# 默认使用第一个预设
		elif preset_names.size() > 0:
			current_preset_mods = Array(bundle_presets[preset_names[0]])

	print("[_enable_bundle] Using preset mods: ", current_preset_mods)
	print("[_enable_bundle] selected_bundle_preset: ", selected_bundle_preset)
	print("[_enable_bundle] current_tag: ", current_tag)

	# 启用预设中的所有模组
	for mod_id in current_preset_mods:
		# 从bundle mods目录复制到游戏目录
		var source_mod_dir = bundle_mods_dir.path_join(mod_id)
		var target_mod_dir = game_path.path_join("mods").path_join(mod_id)

		# 复制模组文件到游戏mods目录
		if DirAccess.dir_exists_absolute(source_mod_dir):
			DirAccess.make_dir_recursive_absolute(target_mod_dir)
			FileUtils.copy_directory(source_mod_dir, target_mod_dir)
			enabled_mods[mod_id] = true
			print("[_enable_bundle] Enabled mod: ", mod_id)

	# 保存启用的模组配置
	_save_enabled_mods()

	# 应用整合包中保存的预设（如果有）
	if not bundle_presets.is_empty():
		tag_data = bundle_presets.duplicate(true)
		# 确保默认标签存在
		if not tag_data.has("单人模组"):
			tag_data["单人模组"] = []
		if not tag_data.has("联机模组"):
			tag_data["联机模组"] = []
		# 设置当前标签为预设中的第一个
		if not bundle_presets.is_empty():
			current_tag = bundle_presets.keys()[0]
		_save_tag_data()

	_save_bundle_data()

	# 更新UI
	_refresh_bundle_list()
	_update_active_bundle_label()
	_build_tag_buttons()  # 刷新标签按钮状态（会检查active_bundle禁用按钮）

	show_notification(translate_fmt("bundle_enabled", [data.get("name", bundle_id)]), true)


# 禁用整合包
func _disable_bundle() -> void:
	if active_bundle.is_empty():
		return

	var data = bundle_data.get(active_bundle, {})
	var bundle_name = data.get("name", active_bundle)

	# 清空游戏mods文件夹
	var game_mods_dir = game_path.path_join("mods")
	if DirAccess.dir_exists_absolute(game_mods_dir):
		var dir = DirAccess.open(game_mods_dir)
		if dir:
			dir.list_dir_begin()
			var entry = dir.get_next()
			while entry != "":
				if entry != "." and entry != ".." and not entry.begins_with("."):
					var entry_path = game_mods_dir.path_join(entry)
					if DirAccess.dir_exists_absolute(entry_path):
						_delete_directory_recursive(entry_path)
					elif FileAccess.file_exists(entry_path):
						DirAccess.remove_absolute(entry_path)
				entry = dir.get_next()
			dir.list_dir_end()

	# 恢复之前启用的模组（从temp_mods复制到游戏目录）
	for mod_id in previous_enabled_mods:
		if previous_enabled_mods[mod_id]:
			var source_mod_dir = temp_mods_path.path_join(mod_id)
			var target_mod_dir = game_mods_dir.path_join(mod_id)

			if DirAccess.dir_exists_absolute(source_mod_dir):
				DirAccess.make_dir_recursive_absolute(target_mod_dir)
				FileUtils.copy_directory(source_mod_dir, target_mod_dir)

	# 更新enabled_mods并保存
	enabled_mods = previous_enabled_mods.duplicate()
	_save_enabled_mods()

	# 恢复之前保存的预设
	if not previous_tag_data.is_empty():
		tag_data = previous_tag_data.duplicate(true)
		_save_tag_data()

	var old_bundle = active_bundle
	active_bundle = ""
	previous_enabled_mods.clear()
	previous_tag_data.clear()

	# 清除config中保存的状态
	config.set_value("bundles", "active_bundle", "")
	config.set_value("bundles", "bundle_previous_state", {})
	config.save(config_path)

	# 更新UI
	_refresh_bundle_list()
	_update_active_bundle_label()
	_build_tag_buttons()

	show_notification(translate_fmt("bundle_disabled", [bundle_name]), true)


# 禁用整合包并保存模组页状态到配置（用于整合包切换时）
func _disable_bundle_and_save_state() -> void:
	if active_bundle.is_empty():
		return

	var data = bundle_data.get(active_bundle, {})
	var bundle_name = data.get("name", active_bundle)

	# 清空游戏mods文件夹
	var game_mods_dir = game_path.path_join("mods")
	if DirAccess.dir_exists_absolute(game_mods_dir):
		var dir = DirAccess.open(game_mods_dir)
		if dir:
			dir.list_dir_begin()
			var entry = dir.get_next()
			while entry != "":
				if entry != "." and entry != ".." and not entry.begins_with("."):
					var entry_path = game_mods_dir.path_join(entry)
					if DirAccess.dir_exists_absolute(entry_path):
						_delete_directory_recursive(entry_path)
					elif FileAccess.file_exists(entry_path):
						DirAccess.remove_absolute(entry_path)
				entry = dir.get_next()
			dir.list_dir_end()

	# 恢复之前启用的模组
	for mod_id in previous_enabled_mods:
		if previous_enabled_mods[mod_id]:
			var source_mod_dir = temp_mods_path.path_join(mod_id)
			var target_mod_dir = game_mods_dir.path_join(mod_id)

			if DirAccess.dir_exists_absolute(source_mod_dir):
				DirAccess.make_dir_recursive_absolute(target_mod_dir)
				FileUtils.copy_directory(source_mod_dir, target_mod_dir)

	# 更新enabled_mods并保存
	enabled_mods = previous_enabled_mods.duplicate()
	_save_enabled_mods()

	# 恢复之前保存的预设
	if not previous_tag_data.is_empty():
		tag_data = previous_tag_data.duplicate(true)
		_save_tag_data()

	# 保存状态到config（供下次恢复模组页状态使用）
	# _save_enabled_mods() 和 _save_tag_data() 已保存 enabled_mods 和 tag_data 到 config

	# 清除内存中的状态
	var old_bundle = active_bundle
	active_bundle = ""
	previous_enabled_mods.clear()
	previous_tag_data.clear()

	# 清除config中保存的状态
	config.set_value("bundles", "active_bundle", "")
	config.set_value("bundles", "bundle_previous_state", {})
	config.save(config_path)

	# 更新UI
	_refresh_bundle_list()
	_update_active_bundle_label()
	_build_tag_buttons()

	print("[_disable_bundle_and_save_state] Bundle disabled: ", bundle_name)


# 更新当前启用整合包标签
func _update_active_bundle_label() -> void:
	var label = find_child_node(self, "ActiveBundleLabel")
	if label:
		if active_bundle.is_empty():
			label.text = translate("not_enabled")
		else:
			var data = bundle_data.get(active_bundle, {})
			label.text = data.get("name", active_bundle)


# 创建关闭整合包按钮
func _create_close_bundle_button() -> void:
	# 查找现有的关闭按钮
	var close_btn = find_child_node(self, "CloseBundleBtn")
	if not close_btn and not active_bundle.is_empty():
		# 创建关闭按钮（当启用整合包时显示）
		close_btn = Button.new()
		close_btn.name = "CloseBundleBtn"
		close_btn.text = translate("close_bundle")
		close_btn.custom_minimum_size = Vector2(100, 35)

		# 样式
		var normal = StyleBoxFlat.new()
		normal.bg_color = Color(0.8, 0.2, 0.2, 1)
		normal.corner_radius_top_left = 4
		normal.corner_radius_top_right = 4
		normal.corner_radius_bottom_left = 4
		normal.corner_radius_bottom_right = 4
		close_btn.add_theme_stylebox_override("normal", normal)

		var hover = StyleBoxFlat.new()
		hover.bg_color = Color(0.9, 0.3, 0.3, 1)
		hover.corner_radius_top_left = 4
		hover.corner_radius_top_right = 4
		hover.corner_radius_bottom_left = 4
		hover.corner_radius_bottom_right = 4
		close_btn.add_theme_stylebox_override("hover", hover)

		close_btn.pressed.connect(_on_close_bundle_pressed)
		add_child(close_btn)

		# 定位到右上角
		close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		close_btn.anchor_left = 1.0
		close_btn.anchor_right = 1.0
		close_btn.offset_left = -120
		close_btn.offset_top = 10
		close_btn.offset_right = -10
		close_btn.offset_bottom = 45

	# 根据状态显示/隐藏
	if close_btn:
		close_btn.visible = not active_bundle.is_empty()


# 关闭整合包按钮回调
func _on_close_bundle_pressed() -> void:
	_disable_bundle()


# 整合包选择回调
func _on_bundle_selected(bundle_id: String, toggled_on: bool) -> void:
	if toggled_on:
		_update_bundle_panel(bundle_id)


# 添加详情行
func _add_detail_row(parent: Control, key: String, value: String) -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)

	var key_label = Label.new()
	key_label.text = key + ": "
	key_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(key_label)

	var value_label = Label.new()
	value_label.text = value
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.text_overrun_behavior = 4
	row.add_child(value_label)


# 删除整合包
func _delete_bundle(bundle_id: String) -> void:
	if not bundle_data.has(bundle_id):
		return

	# 如果正在启用，先禁用
	if active_bundle == bundle_id:
		_disable_bundle()

	# 删除目录
	var package_dir = _get_newpackage_dir()
	if not package_dir.is_empty():
		var bundle_dir = package_dir + "/" + bundle_id
		_delete_directory_recursive(bundle_dir)

	# 移除数据
	bundle_data.erase(bundle_id)
	if bundle_items.has(bundle_id):
		bundle_items[bundle_id].queue_free()
		bundle_items.erase(bundle_id)

	_refresh_bundle_list()
	show_notification(translate("bundle_deleted"), true)


# 检查整合包更新
func _check_bundle_update(bundle_id: String) -> void:
	var data = bundle_data.get(bundle_id, {})
	var update_url = data.get("update_check_url", "")
	var bundle_name = data.get("name", bundle_id)

	print("[_check_bundle_update] bundle_id: ", bundle_id)
	print("[_check_bundle_update] bundle_name: ", bundle_name)
	print("[_check_bundle_update] update_url: ", update_url)
	print("[_check_bundle_update] local_version: ", data.get("version", "v0.0.0"))

	if update_url.is_empty():
		print("[_check_bundle_update] update_url is empty")
		show_notification(translate("no_update_url"), false)
		return

	show_notification(translate("checking_update") + "...", false)

	var http_request = HTTPRequest.new()
	http_request.name = "BundleUpdateCheck"
	Engine.get_main_loop().root.add_child(http_request)

	var headers = ["User-Agent: STS2-ModManager/2.6.9"]
	print("[_check_bundle_update] Sending request to: ", update_url)
	var error = http_request.request(update_url, headers, HTTPClient.METHOD_GET)

	if error != OK:
		http_request.queue_free()
		print("[_check_bundle_update] Request error: ", error)
		show_notification(translate("check_update_failed"), false)
		return

	var result = await http_request.request_completed
	http_request.queue_free()

	print("[_check_bundle_update] result[0]: ", result[0], " (SUCCESS=", HTTPRequest.RESULT_SUCCESS, ")")

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		print("[_check_bundle_update] Request not successful")
		show_notification(translate("check_update_failed"), false)
		return

	var body = result[3]
	var body_str = body.get_string_from_utf8() if body else ""
	print("[_check_bundle_update] Response body length: ", body_str.length())
	print("[_check_bundle_update] Response body (first 500 chars): ", body_str.substr(0, 500))

	var json = JSON.new()
	var parse_error = json.parse(body_str)

	if parse_error != OK:
		print("[_check_bundle_update] JSON parse error: ", parse_error)
		show_notification(translate("parse_failed"), false)
		return

	var remote_data = json.data
	print("[_check_bundle_update] remote_data: ", remote_data)

	var local_version = data.get("version", "v0.0.0")
	var remote_version = remote_data.get("version", "v0.0.0")
	print("[_check_bundle_update] remote_version type: ", typeof(remote_version))
	print("[_check_bundle_update] remote_version value: '", remote_version, "'")

	var cmp = _compare_versions(local_version, remote_version)
	print("[_check_bundle_update] cmp result: ", cmp, " (1=newer, -1=older, 0=same)")
	if cmp > 0:
		# 发现新版本，显示更新确认对话框
		var download_url = remote_data.get("download_url", "")
		if download_url.is_empty():
			show_notification(translate("no_update_url"), false)
			return
		var remote_ver = str(remote_version)
		_show_bundle_update_dialog(bundle_id, bundle_name, local_version, remote_ver, download_url)
	else:
		show_notification(translate("already_latest"), true)


# 显示整合包更新确认对话框
func _show_bundle_update_dialog(bundle_id: String, bundle_name: String, local_version: String, remote_version: String, download_url: String) -> void:
	var dialog = Window.new()
	dialog.name = "BundleUpdateDialog"
	dialog.title = translate("bundle_update_available")
	dialog.size = Vector2i(400, 220)
	dialog.unresizable = false
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	add_child(dialog)
	dialog.close_requested.connect(func(): dialog.queue_free())

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 15)
	dialog.add_child(vbox)

	# 标题
	var title_label = Label.new()
	title_label.text = translate("bundle_new_version_found").format({"name": bundle_name})
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	# 版本信息
	var version_label = Label.new()
	version_label.text = translate("bundle_version_comparison").format({"old": local_version, "new": remote_version})
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(version_label)

	# 按钮
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND
	vbox.add_child(spacer)
	vbox.add_child(btn_hbox)

	# 取消按钮
	var cancel_btn = Button.new()
	cancel_btn.text = translate("cancel")
	cancel_btn.custom_minimum_size = Vector2(120, 40)
	cancel_btn.pressed.connect(func():
		dialog.queue_free()
	)
	btn_hbox.add_child(cancel_btn)

	# 更新按钮
	var update_btn = Button.new()
	update_btn.text = translate("bundle_update_now")
	update_btn.custom_minimum_size = Vector2(120, 40)
	update_btn.pressed.connect(func():
		dialog.queue_free()
		_download_bundle_for_update(bundle_id, download_url)
	)
	btn_hbox.add_child(update_btn)

	dialog.popup_centered()


# 按下URL下载按钮
func _on_add_by_url_pressed() -> void:
	_show_download_bundle_dialog()


# 显示下载整合包对话框
func _show_download_bundle_dialog() -> void:
	var dialog = Window.new()
	dialog.name = "DownloadBundleDialog"
	dialog.title = translate("download_bundle")
	dialog.size = Vector2i(450, 180)
	dialog.unresizable = false
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	add_child(dialog)
	dialog.close_requested.connect(func(): dialog.queue_free())

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_stylebox_override("panel", StyleBoxFlat.new())
	dialog.add_child(vbox)

	var url_label = Label.new()
	url_label.text = translate("download_url")
	vbox.add_child(url_label)

	var url_edit = LineEdit.new()
	url_edit.name = "URLEdit"
	url_edit.custom_minimum_size = Vector2(0, 35)
	url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(url_edit)

	var download_btn = Button.new()
	download_btn.text = translate("download")
	download_btn.custom_minimum_size = Vector2(0, 40)
	download_btn.pressed.connect(func():
		var url = url_edit.text.strip_edges()
		if url.is_empty():
			show_notification(translate("url_required"), false)
			return

		_download_bundle(url)
		dialog.queue_free()
	)
	vbox.add_child(download_btn)

	dialog.popup_centered()


# 下载整合包
func _download_bundle(url: String) -> void:
	# 生成唯一的bundle名称
	var bundle_name = "bundle_" + str(Time.get_unix_time_from_system())
	var safe_name = bundle_name.replace("/", "_").replace("\\", "_").replace(":", "_").replace("*", "_").replace("?", "_").replace("\"", "_").replace("<", "_").replace(">", "_").replace("|", "_")

	# 获取下载目录
	var downloads_dir = get_base_path() + "downloads"

	# 确保下载目录存在
	if not DirAccess.dir_exists_absolute(downloads_dir):
		DirAccess.make_dir_recursive_absolute(downloads_dir)

	# 生成保存路径
	var save_path = downloads_dir + "/" + safe_name + ".zip"

	# 使用现有的下载任务创建
	var download_id = _create_download_task(bundle_name, url)

	# 设置保存路径
	download_tasks[download_id]["save_path"] = save_path

	# 开始下载
	_download_with_powershell_async(url, save_path, download_id, bundle_name)

	show_notification(translate("download_started"), true)


# 下载整合包更新（检查到新版本后调用）
func _download_bundle_for_update(bundle_id: String, download_url: String) -> void:
	print("[_download_bundle_for_update] bundle_id: ", bundle_id, ", url: ", download_url)

	# 先删除旧版本文件夹，避免残留文件导致问题
	var package_dir = _get_newpackage_dir()
	if not package_dir.is_empty():
		var bundle_dir = package_dir + "/" + bundle_id
		if DirAccess.dir_exists_absolute(bundle_dir):
			_delete_directory_recursive(bundle_dir)
			print("[_download_bundle_for_update] Deleted old bundle dir: ", bundle_dir)

	# 从 bundle_data 中也移除旧数据（导入时会重新添加）
	bundle_data.erase(bundle_id)

	# 显示更新开始通知
	show_notification(translate("bundle_update_downloading"), false)

	# 下载新版本
	_download_bundle(download_url)


func _init_download_ui() -> void:
	"""初始化下载标签页UI"""
	print("[_init_download_ui] Initializing download tab UI...")

	# 获取下载任务列表容器
	download_tasks_container = find_child_node(self, "ActiveDownloadsList")
	download_history_container = find_child_node(self, "HistoryList")

	if download_tasks_container:
		print("[_init_download_ui] download_tasks_container found")
	else:
		print("[_init_download_ui] download_tasks_container NOT found")

	if download_history_container:
		print("[_init_download_ui] download_history_container found")
	else:
		print("[_init_download_ui] download_history_container NOT found")

	# 设置下载页面按钮文字翻译
	var current_downloads_label = find_child_node(self, "ActiveDownloadsLabel")
	var open_folder_btn = find_child_node(self, "OpenFolderBtn")
	var no_download_label = find_child_node(self, "NoDownloadsLabel")
	var history_label = find_child_node(self, "HistoryLabel")
	var clear_history_btn = find_child_node(self, "ClearHistoryBtn")

	if current_downloads_label:
		current_downloads_label.text = translate("current_downloads")
	if open_folder_btn:
		open_folder_btn.text = translate("open_folder")
	if no_download_label:
		no_download_label.text = translate("no_download_task")
	if history_label:
		history_label.text = translate("download_history")
	if clear_history_btn:
		clear_history_btn.text = translate("clear_history")

	# 加载下载历史（如果还没有加载）
	if download_history.is_empty():
		_load_download_history()

	# 更新历史记录UI
	_update_download_history_ui()

	# 更新空状态显示
	_update_download_empty_state()

	# 连接清空历史按钮
	if clear_history_btn:
		clear_history_btn.pressed.connect(_on_clear_history_pressed)

	# 连接打开文件夹按钮
	if open_folder_btn:
		open_folder_btn.pressed.connect(_on_open_downloads_folder)


func _on_open_downloads_folder() -> void:
	"""打开下载文件夹"""
	var downloads_path = ""
	if nexus_api:
		downloads_path = nexus_api.downloads_dir
	else:
		# 默认使用可执行文件目录下的 downloads 文件夹
		downloads_path = OS.get_executable_path().get_base_dir() + "/downloads"

	print("[_on_open_downloads_folder] Opening: ", downloads_path)

	# 确保目录存在
	if not DirAccess.dir_exists_absolute(downloads_path):
		DirAccess.make_dir_recursive_absolute(downloads_path)

	# 使用系统命令打开文件夹
	OS.shell_open(downloads_path)


func _on_clear_history_pressed() -> void:
	"""处理清空历史按钮点击"""
	# 创建自定义确认对话框
	var dialog = ConfirmationDialog.new()
	dialog.title = translate("download_clear_all_title")
	get_tree().root.add_child(dialog)

	# 创建内容容器
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)

	# 添加提示文本
	var msg_label = Label.new()
	msg_label.text = translate("download_clear_all_confirm")
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.custom_minimum_size = Vector2(350, 60)
	vbox.add_child(msg_label)

	# 添加复选框
	var check_box = CheckBox.new()
	check_box.text = translate("download_clear_also_files")
	check_box.button_pressed = false
	vbox.add_child(check_box)

	# 添加到对话框
	dialog.add_child(vbox)

	# 设置大小和位置
	dialog.popup_centered(Vector2(400, 180))

	# 连接确认信号，传递复选框状态
	dialog.confirmed.connect(_on_clear_history_confirmed.bind(check_box))


func _on_clear_history_confirmed(include_files_checkbox: CheckBox = null) -> void:
	"""处理清空历史确认"""
	# 清空历史记录
	download_history.clear()

	# 保存到文件
	_save_download_history()

	# 检查是否也需要清除下载的文件
	if include_files_checkbox and include_files_checkbox.button_pressed:
		_clear_downloads_folder()

	# 更新UI
	_update_download_history_ui()


func _show_windows_notification(title: String, message: String) -> void:
	"""显示 Windows 系统通知"""
	if OS.get_name() != "Windows":
		return

	# 使用 PowerShell 调用 Windows BalloonTip 通知（通过 System.Windows.Forms）
	var ps_script = '''
Add-Type -AssemblyName System.Windows.Forms
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Information
$notify.Visible = $true
$notify.ShowBalloonTip(5000, '%s', '%s', 'Info')
Start-Sleep -Seconds 6
$notify.Dispose()
''' % [title, message]

	# 使用 start /B 后台运行，避免阻塞
	OS.execute("powershell", ["-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command", ps_script], [], true)


func _show_download_success_notification(mod_name: String) -> void:
	"""显示下载成功通知"""
	var title = translate("download_success_notice")
	var message = translate("download_complete").format({"name": mod_name})
	_show_windows_notification(title, message)


func _verify_downloaded_file(abs_save_path: String) -> bool:
	"""验证下载的文件是否完整有效"""
	if not FileAccess.file_exists(abs_save_path):
		print("[_verify_downloaded_file] File does not exist: ", abs_save_path)
		return false

	# 检查文件大小（必须大于1KB）
	var file = FileAccess.open(abs_save_path, FileAccess.READ)
	if not file:
		print("[_verify_downloaded_file] Cannot open file: ", abs_save_path)
		return false

	var file_size = file.get_length()
	file.close()

	if file_size < 1024:
		print("[_verify_downloaded_file] File too small: ", file_size)
		return false

	# 验证是否是有效的压缩文件（ZIP以 PK 开头，RAR以 Rar 开头）
	var check_file = FileAccess.open(abs_save_path, FileAccess.READ)
	if check_file:
		var header_bytes = check_file.get_buffer(4)
		check_file.close()
		print("[_verify_downloaded_file] Header bytes: ", header_bytes.hex_encode())
		if header_bytes.size() >= 2:
			var b0 = header_bytes[0]
			var b1 = header_bytes[1]
			print("[_verify_downloaded_file] Byte[0]=%d (0x%02x), Byte[1]=%d (0x%02x)" % [b0, b0 & 0xFF, b1, b1 & 0xFF])
			# ZIP: PK (0x50 0x4B), RAR: Rar (0x52 0x61)
			if (b0 & 0xFF) == 0x50 and (b1 & 0xFF) == 0x4B:
				print("[_verify_downloaded_file] ZIP file header verified, size: ", file_size)
				return true
			if (b0 & 0xFF) == 0x52 and (b1 & 0xFF) == 0x61:
				print("[_verify_downloaded_file] RAR file header verified, size: ", file_size)
				return true

	print("[_verify_downloaded_file] Invalid archive file header")
	return false


func _retry_corrupted_download(download_id: String) -> void:
	"""重新下载损坏的文件"""
	if not download_tasks.has(download_id):
		return

	var task = download_tasks[download_id]
	var url = task.get("download_url", "")
	var mod_name = task.get("mod_name", "")
	var save_path = task.get("save_path", "")

	# 检查重试次数，避免无限循环
	var retry_count = task.get("retry_count", 0)
	if retry_count >= 3:
		print("[_retry_corrupted_download] Max retries (3) reached, marking as failed")
		_update_download_task_status(download_id, "failed", "下载失败：文件损坏")
		if local_server:
			local_server.notify_download_complete(false, mod_name, "Download failed after 3 retries")
		return

	if url.is_empty() or save_path.is_empty():
		print("[_retry_corrupted_download] Missing url or path")
		_update_download_task_status(download_id, "failed", "Download failed")
		return

	# 转换为绝对路径（curl需要Windows路径）
	var abs_save_path = save_path
	if save_path.begins_with("res://"):
		abs_save_path = ProjectSettings.globalize_path(save_path)
		print("[_retry_corrupted_download] Converted to absolute path: ", abs_save_path)

	print("[_retry_corrupted_download] Retrying download: ", mod_name, " (attempt ", retry_count + 1, "/3)")

	# 删除可能存在的损坏文件
	if FileAccess.file_exists(abs_save_path):
		DirAccess.remove_absolute(abs_save_path)

	# 重新开始下载（使用线程）
	var thread = Thread.new()
	var new_download_id = _create_download_task(mod_name, url)
	if new_download_id.is_empty():
		return

	download_tasks[new_download_id]["save_path"] = save_path  # 保持原始res://路径
	download_tasks[new_download_id]["start_time"] = Time.get_unix_time_from_system()
	download_tasks[new_download_id]["retry_count"] = retry_count + 1

	var args = {
		"url": url,
		"abs_save_path": abs_save_path,  # curl需要Windows绝对路径
		"download_id": new_download_id,
		"mod_name": mod_name
	}
	thread.start(_thread_download_wrapper.bind(args))

	# 启动进度监控
	_monitor_download_progress(abs_save_path, new_download_id, 0)

	# 清理旧任务
	download_tasks.erase(download_id)
	_update_download_task_ui(download_id)

	"""从文件加载下载历史"""
	if download_history_file.is_empty():
		download_history_file = get_base_path() + "download_history.json"

	if not FileAccess.file_exists(download_history_file):
		print("[_load_download_history] No history file found")
		return

	var file = FileAccess.open(download_history_file, FileAccess.READ)
	if file == null:
		print("[_load_download_history] Failed to open file")
		return

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		print("[_load_download_history] JSON parse error")
		return

	var data = json.get_data()
	if typeof(data) == TYPE_ARRAY:
		download_history = data
		print("[_load_download_history] Loaded ", download_history.size(), " history items")
	else:
		print("[_load_download_history] Invalid data format")


func _load_download_history() -> void:
	"""从文件加载下载历史"""
	if download_history_file.is_empty():
		download_history_file = get_base_path() + "download_history.json"

	if not FileAccess.file_exists(download_history_file):
		print("[_load_download_history] No history file found")
		return

	var file = FileAccess.open(download_history_file, FileAccess.READ)
	if file == null:
		print("[_load_download_history] Failed to open file")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		print("[_load_download_history] JSON parse error")
		return

	var data = json.get_data()
	if data is Array:
		download_history = data
		print("[_load_download_history] Loaded ", download_history.size(), " history items")
	else:
		print("[_load_download_history] Invalid data format")


func _save_download_history() -> void:
	"""保存下载历史到文件"""
	if download_history_file.is_empty():
		download_history_file = get_base_path() + "download_history.json"

	# 确保目录存在
	var dir_path = download_history_file.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var json = JSON.new()
	var json_string = json.stringify(download_history)

	var file = FileAccess.open(download_history_file, FileAccess.WRITE)
	if file == null:
		print("[_save_download_history] Failed to create file")
		return

	file.store_string(json_string)
	file.close()
	print("[_save_download_history] Saved ", download_history.size(), " history items")


func _clear_downloads_folder() -> void:
	"""清空下载文件夹"""
	var downloads_path = ""
	if nexus_api:
		downloads_path = nexus_api.downloads_dir
	else:
		downloads_path = get_base_path() + "downloads"

	if not DirAccess.dir_exists_absolute(downloads_path):
		return

	var dir = DirAccess.open(downloads_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	var deleted_count = 0
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path = downloads_path + "/" + file_name
			if dir.current_is_dir():
				DirAccess.remove_absolute(full_path)
			else:
				DirAccess.remove_absolute(full_path)
			deleted_count += 1
		file_name = dir.get_next()
	dir.list_dir_end()

	print("[_clear_downloads_folder] Deleted ", deleted_count, " files/folders")


func _create_download_task(mod_name: String, download_url: String) -> String:
	"""创建下载任务"""
	_download_id_counter += 1
	var download_id = "download_%d" % _download_id_counter

	download_tasks[download_id] = {
		"mod_name": mod_name,
		"download_url": download_url,
		"status": "downloading",  # downloading, paused, installing, completed, failed
		"progress": 0.0,
		"speed": "等待中",  # 默认显示
		"speed_bytes": 0,
		"save_path": "",
		"error": "",
		"start_time": Time.get_unix_time_from_system(),
		"total_size": 0,
		"downloaded_size": 0,
		"file_size": "等待中...",  # 默认显示
		"temp_file_path": "",   # 临时文件路径，支持断点续传
		"is_paused": false,     # 是否已暂停
		"resume_url": "",       # 继续下载时的URL（带Range参数）
		"bytes_downloaded": 0,  # 已下载的字节数
		"version": "v0.0.0",  # 模组版本
		"download_source": ""  # 下载来源
	}

	# 更新下载任务列表UI
	_update_download_task_ui(download_id)

	return download_id


func _update_download_size(download_id: String, total_size: int) -> void:
	"""在主线程中更新下载任务的文件大小信息"""
	if download_id.is_empty() or not download_tasks.has(download_id):
		return

	download_tasks[download_id]["total_size"] = total_size
	# 显示 "0 / 总大小" 格式
	var file_size_str = "0 / " + _format_file_size(total_size)
	download_tasks[download_id]["file_size"] = file_size_str
	_update_download_task_ui(download_id)


func _update_download_task_ui(download_id: String) -> void:
	"""更新下载任务UI"""
	if not download_tasks_container:
		return

	var task = download_tasks.get(download_id)
	if not task:
		return

	# 检查是否已存在该任务的UI
	var existing_item = download_tasks_container.find_child(download_id, true, false)
	if existing_item:
		# 更新现有项
		var name_label = existing_item.find_child("NameLabel", true, false)
		var progress_bar = existing_item.find_child("ProgressBar", true, false)
		var speed_label = existing_item.find_child("SpeedLabel", true, false)
		var status_label = existing_item.find_child("StatusLabel", true, false)
		var size_label = existing_item.find_child("SizeLabel", true, false)
		var arrow_icon = existing_item.find_child("ArrowIcon", true, false)

		if name_label:
			name_label.text = task.get("mod_name", "Unknown")
		if progress_bar:
			progress_bar.value = task.get("progress", 0.0)
		if speed_label:
			speed_label.text = task.get("speed", "")
		if status_label:
			var progress = task.get("progress", 0.0)
			status_label.text = "%.1f%%" % progress
		if size_label:
			size_label.text = task.get("file_size", "")
		# 更新箭头动画
		if arrow_icon:
			var is_paused = task.get("is_paused", false)
			_animate_download_arrow(arrow_icon, is_paused)
		# 更新暂停/继续按钮
		var pause_btn = existing_item.find_child("PauseBtn", true, false)
		if pause_btn:
			var is_paused = task.get("is_paused", false)
			pause_btn.text = translate("download_resume") if is_paused else translate("download_pause")
		# 更新状态标签显示暂停状态
		if status_label:
			var task_status = task.get("status", "")
			if task_status == "paused":
				status_label.text = translate("download_paused")
		return

	# 创建新的任务项
	var task_item = Control.new()
	task_item.name = download_id
	task_item.custom_minimum_size = Vector2(0, 90)
	task_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox = HBoxContainer.new()
	hbox.layout_mode = 1
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_item.add_child(hbox)

	# 下载箭头图标
	var arrow_icon = Label.new()
	arrow_icon.name = "ArrowIcon"
	arrow_icon.text = "↓"
	arrow_icon.custom_minimum_size = Vector2(30, 0)
	arrow_icon.layout_mode = 2
	arrow_icon.horizontal_alignment = 1
	arrow_icon.add_theme_font_size_override("font_size", 24)
	hbox.add_child(arrow_icon)

	# 右侧信息区域
	var info_vbox = VBoxContainer.new()
	info_vbox.layout_mode = 2
	info_vbox.size_flags_horizontal = 3
	hbox.add_child(info_vbox)

	# 模组名称
	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = task.get("mod_name", "Unknown")
	name_label.layout_mode = 2
	name_label.size_flags_horizontal = 3
	info_vbox.add_child(name_label)

	# 进度条
	var progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.custom_minimum_size = Vector2(0, 24)
	progress_bar.layout_mode = 2
	progress_bar.size_flags_horizontal = 3
	progress_bar.max_value = 100
	progress_bar.value = task.get("progress", 0.0)
	progress_bar.show_percentage = false
	info_vbox.add_child(progress_bar)

	# 进度信息和速度
	var info_hbox = HBoxContainer.new()
	info_hbox.layout_mode = 2
	info_vbox.add_child(info_hbox)

	var speed_label = Label.new()
	speed_label.name = "SpeedLabel"
	speed_label.text = task.get("speed", "")
	speed_label.layout_mode = 2
	speed_label.add_theme_font_size_override("font_size", 12)
	info_hbox.add_child(speed_label)

	var size_label = Label.new()
	size_label.name = "SizeLabel"
	size_label.text = task.get("file_size", "")
	size_label.layout_mode = 2
	size_label.add_theme_font_size_override("font_size", 12)
	info_hbox.add_child(size_label)

	var status_label = Label.new()
	status_label.name = "StatusLabel"
	var progress = task.get("progress", 0.0)
	status_label.text = "%.1f%%" % progress
	status_label.layout_mode = 2
	status_label.horizontal_alignment = 2
	status_label.add_theme_font_size_override("font_size", 12)
	info_hbox.add_child(status_label)

	# 按钮区域
	var btn_hbox = HBoxContainer.new()
	btn_hbox.layout_mode = 2
	info_vbox.add_child(btn_hbox)

	# 暂停/继续按钮
	var pause_btn = Button.new()
	pause_btn.name = "PauseBtn"
	pause_btn.custom_minimum_size = Vector2(60, 24)
	pause_btn.layout_mode = 2
	var is_paused = task.get("is_paused", false)
	pause_btn.text = translate("download_resume") if is_paused else translate("download_pause")
	pause_btn.pressed.connect(_on_download_pause_pressed.bind(download_id))
	btn_hbox.add_child(pause_btn)

	# 取消按钮
	var cancel_btn = Button.new()
	cancel_btn.name = "CancelBtn"
	cancel_btn.custom_minimum_size = Vector2(60, 24)
	cancel_btn.layout_mode = 2
	cancel_btn.text = translate("download_cancel")
	cancel_btn.pressed.connect(_on_download_cancel_pressed.bind(download_id))
	btn_hbox.add_child(cancel_btn)

	download_tasks_container.add_child(task_item)

	# 启动箭头动画（延迟调用确保节点已添加到场景树）
	if task.get("status", "") == "downloading":
		arrow_icon.call_deferred("_start_download_arrow_anim", download_id, is_paused)


# 下载箭头动画函数
func _start_download_arrow_anim(download_id: String, is_paused: bool) -> void:
	"""开始下载箭头动画"""
	var task_ui = download_tasks_container.find_child(download_id, true, false)
	if task_ui:
		var arrow = task_ui.find_child("ArrowIcon", true, false)
		if arrow:
			_animate_download_arrow(arrow, is_paused)


func _on_download_pause_pressed(download_id: String) -> void:
	"""处理暂停/继续按钮点击"""
	var task = download_tasks.get(download_id)
	if not task:
		return

	if task.get("is_paused", false):
		# 继续下载
		_resume_download(download_id)
	else:
		# 暂停下载
		_pause_download(download_id)


func _on_download_cancel_pressed(download_id: String) -> void:
	"""处理取消按钮点击"""
	var task = download_tasks.get(download_id)
	if not task:
		return

	# 标记为取消状态
	task["status"] = "cancelled"

	# 停止下载进程
	if _download_processes.has(download_id):
		var pid = _download_processes[download_id]
		# 终止进程
		OS.execute("powershell", ["-NoProfile", "-Command", "Stop-Process -Id %d -Force -ErrorAction SilentlyContinue" % pid], [], true)
		_download_processes.erase(download_id)
		print("[_on_download_cancel_pressed] Stopped process: ", pid)

	# 停止进度监控
	_stop_progress_monitor(download_id)

	# 清理临时文件
	var save_path = task.get("save_path", "")
	if not save_path.is_empty():
		var abs_save_path = save_path
		if save_path.begins_with("res://"):
			abs_save_path = ProjectSettings.globalize_path(save_path)
		elif save_path.begins_with("user://"):
			abs_save_path = ProjectSettings.globalize_path(save_path)
		if FileAccess.file_exists(abs_save_path):
			DirAccess.remove_absolute(abs_save_path)
			print("[_on_download_cancel_pressed] Removed temp file: ", abs_save_path)

	# 移除任务
	download_tasks.erase(download_id)

	# 更新UI（需要手动移除UI项）
	if download_tasks_container:
		var task_item = download_tasks_container.find_child(download_id, true, false)
		if task_item:
			task_item.queue_free()

	# 更新空状态
	_update_download_empty_state()


func _pause_download(download_id: String) -> void:
	"""暂停下载 - 记录已下载大小，下次继续时从头开始下载"""
	var task = download_tasks.get(download_id)
	if not task:
		return

	# 记录当前已下载的字节数
	var save_path = task.get("save_path", "")
	var abs_save_path = save_path
	if save_path.begins_with("res://"):
		abs_save_path = ProjectSettings.globalize_path(save_path)
	elif save_path.begins_with("user://"):
		abs_save_path = ProjectSettings.globalize_path(save_path)

	if FileAccess.file_exists(abs_save_path):
		var file = FileAccess.open(abs_save_path, FileAccess.READ)
		if file:
			var downloaded_size = file.get_length()
			task["bytes_downloaded"] = downloaded_size
			file.close()
			print("[_pause_download] Recorded bytes_downloaded: ", downloaded_size)

	# 标记为暂停状态（不尝试终止进程，因为无法获取PID）
	task["is_paused"] = true
	task["status"] = "paused"

	# 停止进度监控
	_stop_progress_monitor(download_id)

	# 更新UI显示暂停状态
	_update_download_task_ui(download_id)


func _resume_download(download_id: String) -> void:
	"""继续下载 - 支持断点续传"""
	var task = download_tasks.get(download_id)
	if not task:
		return

	# 获取保存路径
	var save_path = task.get("save_path", "")
	var abs_save_path = save_path
	if save_path.begins_with("res://"):
		abs_save_path = ProjectSettings.globalize_path(save_path)
	elif save_path.begins_with("user://"):
		abs_save_path = ProjectSettings.globalize_path(save_path)

	# 恢复下载状态
	task["is_paused"] = false
	task["status"] = "downloading"

	# 获取下载信息
	var download_url = task.get("download_url", "")
	var mod_name = task.get("mod_name", "")

	# 检查是否有部分下载的文件
	var resume_bytes = 0
	if FileAccess.file_exists(abs_save_path):
		var partial_file = FileAccess.open(abs_save_path, FileAccess.READ)
		if partial_file:
			resume_bytes = partial_file.get_length()
			partial_file.close()
			print("[_resume_download] Resuming from byte: ", resume_bytes)
			task["bytes_downloaded"] = resume_bytes
			task["downloaded_size"] = resume_bytes

	# 如果没有部分文件，重新开始
	if resume_bytes == 0:
		if FileAccess.file_exists(abs_save_path):
			DirAccess.remove_absolute(abs_save_path)
		print("[_resume_download] No partial file, starting fresh")

	# 使用线程执行下载（HTTP客户端支持断点续传）
	var thread = Thread.new()
	var args = {
		"url": download_url,
		"abs_save_path": abs_save_path,
		"download_id": download_id,
		"mod_name": mod_name
	}
	thread.start(_thread_download_wrapper.bind(args))

	# 重新启动进度监控
	_monitor_download_progress(abs_save_path, download_id, task.get("total_size", 0))

	# 更新UI
	_update_download_task_ui(download_id)


func _update_download_empty_state() -> void:
	"""更新空状态显示"""
	if not download_tasks_container:
		return

	var has_tasks = download_tasks.size() > 0
	var active_list = find_child_node(self, "ActiveDownloadsList")
	if active_list:
		var empty_label = active_list.find_child("EmptyLabel", true, false)
		if empty_label:
			empty_label.visible = not has_tasks


func _animate_download_arrow(arrow_icon: Control, is_paused: bool) -> void:
	"""下载箭头动画 - 简化版：暂停时停止动画，否则匀速播放"""
	if not arrow_icon:
		return

	# 检查节点是否在场景树中
	if not arrow_icon.is_inside_tree():
		return

	# 获取父节点用于存储tween引用
	var parent = arrow_icon.get_parent()
	if not parent:
		return

	# 停止现有动画
	if parent.has_meta("arrow_tween"):
		var existing_tween = parent.get_meta("arrow_tween")
		if existing_tween and is_instance_valid(existing_tween):
			existing_tween.kill()
		parent.remove_meta("arrow_tween")

	if is_paused:
		# 暂停动画，保持箭头可见
		arrow_icon.visible = true
		arrow_icon.modulate = Color(1, 1, 1, 1)
		# 重置位置
		arrow_icon.offset_top = 0
		arrow_icon.offset_bottom = 0
		return

	# 创建新动画 - 匀速上下运动
	var tween = arrow_icon.create_tween()
	# 存储到父节点的metadata中
	parent.set_meta("arrow_tween", tween)

	tween.set_loops()

	# 匀速上下运动 - 固定时间
	tween.tween_property(arrow_icon, "offset_top", -5.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(arrow_icon, "offset_bottom", 5.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	tween.tween_property(arrow_icon, "offset_top", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(arrow_icon, "offset_bottom", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _format_file_size(bytes: int) -> String:
	"""格式化文件大小"""
	if bytes <= 0:
		return ""
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	elif bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))
	else:
		return "%.2f GB" % (bytes / (1024.0 * 1024.0 * 1024.0))


func _update_download_task_progress(download_id: String, progress: float, speed: String = "", speed_bytes: int = 0, downloaded_size: int = 0, total_size: int = 0, file_size_str: String = "") -> void:
	"""更新下载进度"""
	if download_tasks.has(download_id):
		download_tasks[download_id]["progress"] = progress
		download_tasks[download_id]["speed"] = speed
		download_tasks[download_id]["speed_bytes"] = speed_bytes
		download_tasks[download_id]["downloaded_size"] = downloaded_size
		download_tasks[download_id]["total_size"] = total_size
		download_tasks[download_id]["file_size"] = file_size_str
		_update_download_task_ui(download_id)


func _update_download_task_status(download_id: String, status: String, error: String = "") -> void:
	"""更新下载任务状态"""
	if download_tasks.has(download_id):
		download_tasks[download_id]["status"] = status
		download_tasks[download_id]["error"] = error

		if status == "completed" or status == "failed":
			# 移动到历史记录
			var task = download_tasks[download_id]
			task["end_time"] = Time.get_unix_time_from_system()
			download_history.append(task)

			# 保存到文件
			_save_download_history()

			# 从活跃任务中移除
			download_tasks.erase(download_id)

			# 移除UI项
			if download_tasks_container:
				var task_item = download_tasks_container.find_child(download_id, true, false)
				if task_item:
					task_item.queue_free()

			# 更新历史记录UI
			_update_download_history_ui()

			# 更新空状态
			_update_download_empty_state()

		_update_download_task_ui(download_id)


func _update_download_history_ui() -> void:
	"""更新下载历史UI"""
	if not download_history_container:
		return

	# 清空现有历史记录
	for child in download_history_container.get_children():
		child.queue_free()

	# 添加历史记录项（最多显示20条）
	var history_count = 0
	for i in range(download_history.size() - 1, -1, -1):
		if history_count >= 20:
			break

		var task = download_history[i]

		# 创建单行历史项（使用 HBoxContainer 更简单）
		var history_item = HBoxContainer.new()
		history_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		history_item.custom_minimum_size = Vector2(0, 40)

		# 状态图标
		var status_icon = Label.new()
		status_icon.custom_minimum_size = Vector2(30, 0)
		status_icon.horizontal_alignment = 1
		var task_status = task.get("status", "")
		status_icon.text = "✓" if task_status == "completed" else "✕"
		status_icon.modulate = Color.GREEN if task_status == "completed" else Color.RED
		history_item.add_child(status_icon)

		# 模组名称
		var name_label = Label.new()
		name_label.text = task.get("mod_name", "Unknown")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.size_flags_stretch_ratio = 1.0
		history_item.add_child(name_label)

		# 时间标签（只显示日期）
		var time_label = Label.new()
		var end_time = task.get("end_time", 0)
		if end_time > 0:
			# 只显示日期部分
			var datetime = Time.get_datetime_dict_from_unix_time(end_time)
			time_label.text = "%02d-%02d" % [datetime.month, datetime.day]
		else:
			time_label.text = "-"
		time_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		time_label.add_theme_font_size_override("font_size", 10)
		history_item.add_child(time_label)

		# 版本号（从任务记录或已安装模组获取）
		var version_label = Label.new()
		var task_version = task.get("version", "")
		var version = ""
		if not task_version.is_empty() and task_version != "v0.0.0":
			version = task_version
		else:
			version = _get_installed_mod_version(task)
		version_label.text = version if not version.is_empty() else "-"
		version_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		version_label.add_theme_font_size_override("font_size", 11)
		history_item.add_child(version_label)

		# 删除按钮
		var delete_btn = Button.new()
		delete_btn.custom_minimum_size = Vector2(50, 22)
		delete_btn.text = translate("download_delete_btn")
		delete_btn.pressed.connect(_on_history_item_delete_pressed.bind(i))
		history_item.add_child(delete_btn)

		download_history_container.add_child(history_item)
		history_count += 1


func _get_installed_mod_version(task_or_name, mods_list: Array = []) -> String:
	"""获取已安装模组的版本号"""
	# 支持两种调用方式：
	# 1. _get_installed_mod_version(mod_name) - 只传入模组名称
	# 2. _get_installed_mod_version(task, mods) - 传入任务字典和模组列表
	var mod_name = ""
	var check_mods = mods

	if task_or_name is Dictionary:
		# 传入的是任务字典，先检查任务中是否已有版本号
		var task_version = task_or_name.get("version", "")
		if not task_version.is_empty() and task_version != "v0.0.0":
			return task_version
		mod_name = task_or_name.get("mod_name", "")
		if not task_or_name.get("mod_list", []).is_empty():
			check_mods = task_or_name.get("mod_list")
	else:
		mod_name = task_or_name

	for mod in check_mods:
		if mod.get("name", "") == mod_name:
			return mod.get("version", "")
	return ""


func _get_installed_mod_source(task_or_name) -> String:
	"""获取已安装模组的下载来源"""
	var mod_name = ""
	var check_mods = mods

	if task_or_name is Dictionary:
		# 传入的是任务字典，先检查任务中是否已有来源
		var task_source = task_or_name.get("download_source", "")
		if not task_source.is_empty():
			return task_source
		mod_name = task_or_name.get("mod_name", "")
	else:
		mod_name = task_or_name

	for mod in check_mods:
		if mod.get("name", "") == mod_name:
			return mod.get("download_source", "")
	return ""


func _on_history_item_delete_pressed(index: int) -> void:
	"""处理历史项删除按钮点击"""
	if index < 0 or index >= download_history.size():
		return

	var task = download_history[index]
	var mod_name = task.get("mod_name", "Unknown")

	# 创建确认弹窗
	_show_delete_history_confirm_dialog(index, mod_name)


func _show_delete_history_confirm_dialog(index: int, mod_name: String) -> void:
	"""显示删除历史记录确认对话框"""
	# 创建确认弹窗
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = translate("download_delete_title")

	# 创建自定义内容
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	vbox.add_theme_constant_override("margin_left", 16)
	vbox.add_theme_constant_override("margin_right", 16)
	vbox.add_theme_constant_override("margin_top", 16)
	vbox.add_theme_constant_override("margin_bottom", 16)

	# 提示信息
	var label = Label.new()
	label.text = translate("download_delete_confirm").format({"name": mod_name})
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(label)

	# "同时删除本地文件"复选框
	var checkbox = CheckBox.new()
	checkbox.name = "DeleteFileCheck"
	checkbox.text = translate("download_delete_file")
	vbox.add_child(checkbox)

	confirm_dialog.add_child(vbox)

	# 设置内容区域大小
	confirm_dialog.size = Vector2(400, 150)

	get_tree().root.add_child(confirm_dialog)
	confirm_dialog.popup_centered(Vector2(400, 150))

	# 连接确认按钮
	confirm_dialog.confirmed.connect(_on_history_delete_confirmed.bind(index, confirm_dialog))


func _on_history_delete_confirmed(index: int, dialog: ConfirmationDialog) -> void:
	"""处理历史记录删除确认"""
	if index < 0 or index >= download_history.size():
		return

	var task = download_history[index]

	# 检查是否勾选了"同时删除本地文件"
	var delete_file_check = dialog.find_child("DeleteFileCheck", true, false)
	if delete_file_check and delete_file_check is CheckBox:
		if delete_file_check.button_pressed:
			var file_path = task.get("save_path", "")
			if not file_path.is_empty() and FileAccess.file_exists(file_path):
				DirAccess.remove_absolute(file_path)

	# 从历史中移除
	download_history.remove_at(index)

	# 保存到文件
	_save_download_history()

	# 更新UI
	_update_download_history_ui()

	# 释放弹窗
	dialog.queue_free()


func _format_duration(seconds: int) -> String:
	"""格式化时长"""
	if seconds < 60:
		return "%ds" % seconds
	elif seconds < 3600:
		return "%dm %ds" % [seconds / 60, seconds % 60]
	else:
		return "%dh %dm" % [seconds / 3600, (seconds % 3600) / 60]


func _on_server_download_request(data: Dictionary) -> void:
	"""处理来自浏览器扩展的下载请求"""
	print("[_on_server_download_request] Received data keys: ", data.keys())
	print("[_on_server_download_request] Full data: ", data)

	var mod_id = data.get("mod_id", 0)
	# Handle string mod_id from browser extension
	if typeof(mod_id) == TYPE_STRING:
		mod_id = int(mod_id) if mod_id.is_valid_int() else 0
	elif typeof(mod_id) != TYPE_INT:
		mod_id = 0

	var mod_name = data.get("mod_name", "Unknown")
	var download_url = data.get("download_url", "")  # 直链下载
	var nxm_url = data.get("nxm_url", "")  # NXM URL（来自浏览器扩展）
	var key = data.get("key", "")  # NXM URL 中的 key 参数
	var expires = data.get("expires", 0)  # NXM URL 中的 expires 参数
	var user_id = data.get("user_id", 0)  # NXM URL 中的 user_id 参数
	var file_id = data.get("file_id", 0)  # NXM URL 中的 file_id 参数

	# 检查是否来自 BrowserHost 的 Aria2 下载
	var aria2_gid = data.get("aria2_gid", "")
	var download_type = data.get("download_type", "")

	if mod_id == 0:
		if local_server:
			local_server.notify_download_complete(false, mod_name, "Invalid mod_id")
		show_notification(translate("invalid_mod_id"), false)
		return

	# 创建下载任务并显示在下载标签页
	var download_id = _create_download_task(mod_name, download_url)
	print("[_on_server_download_request] Created download task: ", download_id)

	# 设置下载来源为 Nexus
	if download_tasks.has(download_id):
		download_tasks[download_id]["download_source"] = "nexus"

	# 如果 BrowserHost 已经用 Aria2 开始下载，则跳过 Godot 的下载逻辑
	if download_type == "aria2" and not aria2_gid.is_empty():
		print("[_on_server_download_request] Aria2 download already started (GID=", aria2_gid, "), skipping Godot download")
		# 更新任务状态为"通过Aria2下载"
		if download_tasks.has(download_id):
			download_tasks[download_id]["status"] = "aria2_downloading"
			download_tasks[download_id]["aria2_gid"] = aria2_gid
			_update_download_task_status(download_id, "aria2_downloading")
		return

	# 如果 BrowserHost 的 Aria2 下载失败或不可用，继续使用 Godot 下载
	if download_type == "error" or download_type == "fallback" or download_type == "no-aria2":
		print("[_on_server_download_request] BrowserHost Aria2 failed/unavailable (type=", download_type, "), falling back to Godot download")

	# 关键逻辑：所有下载都使用直链，不依赖 Nexus API
	# 优先使用直链 URL，如果没有则尝试 nxm_url
	if download_url.is_empty() and not nxm_url.is_empty():
		download_url = nxm_url

	# 优先使用直链 URL
	if not download_url.is_empty() and (download_url.begins_with("https://") or download_url.begins_with("http://")):
		print("[_on_server_download_request] Using direct download URL")
		_download_mod_direct(download_url, mod_name, download_id)
		return

	# 如果有 NXM 参数 (key, expires, user_id)
	if not key.is_empty() and expires > 0 and user_id > 0:
		print("[_on_server_download_request] Have NXM params, file_id=", file_id)
		# NXM URL 需要 API key 来获取正确的下载链接（包含文件名）
		if nexus_api and not nexus_api.api_key.is_empty():
			print("[_on_server_download_request] Using Nexus API to get download link")
			_download_mod_via_nexus_api_with_params(mod_id, mod_name, file_id, key, expires, user_id, download_id)
		else:
			print("[_on_server_download_request] No API key available, cannot download NXM URL")
			show_notification(translate("nxm_link_needs_api_key"), false)
			if local_server:
				local_server.notify_download_complete(false, mod_name, "API Key required for NXM downloads")
			# 标记任务为失败并从活跃任务中移除
			if not download_id.is_empty():
				_update_download_task_status(download_id, "failed", "NXM下载需要API Key")
			return
		return

	# 如果 download_url 是 NXM 协议
	if download_url.begins_with("nxm://"):
		print("[_on_server_download_request] Parsing NXM URL")
		var parsed = _parse_nxm_url(download_url)
		if parsed.size() > 0 and parsed.has("mod_id") and parsed.has("file_id"):
			var parsed_mod_id = parsed.get("mod_id")
			var parsed_file_id = parsed.get("file_id")
			var parsed_key = parsed.get("key", "")
			var parsed_expires = parsed.get("expires", 0)
			var parsed_user_id = parsed.get("user_id", 0)

			# NXM URL 需要 API key 来获取正确的下载链接
			if nexus_api and not nexus_api.api_key.is_empty():
				print("[_on_server_download_request] Using Nexus API to get download link")
				_download_mod_via_nexus_api_with_params(parsed_mod_id, mod_name, parsed_file_id, parsed_key, parsed_expires, parsed_user_id, download_id)
			else:
				print("[_on_server_download_request] No API key available, cannot download NXM URL")
				show_notification(translate("nxm_link_needs_api_key"), false)
				if local_server:
					local_server.notify_download_complete(false, mod_name, "API Key required for NXM downloads")
				# 标记任务为失败并从活跃任务中移除
				if not download_id.is_empty():
					_update_download_task_status(download_id, "failed", "NXM下载需要API Key")
			return
		else:
			show_notification(translate("cannot_parse_nxm_link"), false)
			# 标记任务为失败
			if not download_id.is_empty():
				_update_download_task_status(download_id, "failed", "无法解析NXM链接")
			return

	# 如果没有任何 URL 信息，尝试使用 Nexus API（需要 API key）
	print("[_on_server_download_request] No direct URL, falling back to Nexus API (requires API key)")
	_download_mod_via_nexus_api(mod_id, mod_name, download_id)


func _download_mod_via_nexus_api(mod_id: int, mod_name: String, existing_download_id: String = "") -> void:
	"""通过 Nexus API 下载模组（作为回退方案）

	Args:
		mod_id: 模组ID
		mod_name: 模组名称
		existing_download_id: 如果传入已有的下载ID，则使用该ID而不是创建新任务
	"""
	# 获取 Nexus API（使用独立的 API 实例，不依赖 Nexus UI）
	if not nexus_api:
		if local_server:
			local_server.notify_download_complete(false, mod_name, "Nexus API not available")
		show_notification(translate("nexus_api_unavailable"), false)
		return

	show_notification(translate_fmt("downloading_mod", [mod_name]), true)

	# 获取文件列表
	var files_result = await nexus_api.get_mod_files(mod_id)
	if not files_result.success:
		if local_server:
			local_server.notify_download_complete(false, mod_name, files_result.get("error", ""))
		show_notification(translate("getting_files") + ": " + files_result.get("error", ""), false)
		return

	# 处理文件列表
	var raw_data = files_result.get("files", [])
	var files: Array = []

	if typeof(raw_data) == TYPE_DICTIONARY:
		if raw_data.has("files"):
			files = raw_data.get("files", [])
	elif raw_data is Array:
		files = raw_data

	if files.is_empty():
		if local_server:
			local_server.notify_download_complete(false, mod_name, "No files available")
		show_notification(translate("no_download_files"), false)
		return

	# 获取第一个文件的下载链接
	var first_file = files[0]
	if not (first_file is Dictionary):
		if local_server:
			local_server.notify_download_complete(false, mod_name, "Invalid file format")
		show_notification(translate("file_list_format_error"), false)
		return

	var file_id_variant = first_file.get("file_id", 0)
	var file_id: int = 0

	# 处理各种类型的 file_id（整数、字符串、数组）
	match typeof(file_id_variant):
		TYPE_INT:
			file_id = file_id_variant
		TYPE_STRING:
			file_id = file_id_variant.to_int()
		TYPE_ARRAY:
			# file_id 可能是 [1054, 8916] 数组，取第一个
			if file_id_variant.size() > 0:
				var first_elem = file_id_variant[0]
				if typeof(first_elem) == TYPE_INT:
					file_id = first_elem
				elif typeof(first_elem) == TYPE_STRING:
					file_id = first_elem.to_int()
			print("[_on_server_download_request] file_id from array: ", file_id)
		_:
			print("[_on_server_download_request] Unexpected file_id type: ", typeof(file_id_variant))

	if file_id == 0:
		if local_server:
			local_server.notify_download_complete(false, mod_name, "Invalid file_id")
		show_notification(translate("cannot_get_file_id"), false)
		return

	show_notification(translate("getting_link"), true)

	var link_result = await nexus_api.get_download_link(mod_id, file_id)
	if not link_result.success:
		var error_msg = link_result.get("error", "未知错误")
		if "premium" in error_msg.to_lower():
			show_notification(translate("nexus_download_requires_premium"), false)
		else:
			show_notification(translate_fmt("get_link_failed", [error_msg]), false)
		if local_server:
			local_server.notify_download_complete(false, mod_name, error_msg)
		return

	var download_url = link_result.get("download_link", "")
	if download_url.is_empty():
		if local_server:
			local_server.notify_download_complete(false, mod_name, "Empty download URL")
		show_notification(translate("download_link_empty"), false)
		return

	# 生成保存路径
	var safe_name = mod_name.replace("/", "_").replace("\\", "_").replace(":", "_").replace("*", "_").replace("?", "_").replace("\"", "_").replace("<", "_").replace(">", "_").replace("|", "_")
	var save_path = nexus_api.downloads_dir + "/" + safe_name + ".zip"

	show_notification(translate_fmt("downloading_mod", [mod_name]), true)

	# 下载文件，传递已有的下载ID以避免重复创建任务
	await _download_mod_file(download_url, save_path, mod_name, existing_download_id)


func _download_mod_via_nexus_api_with_params(mod_id: int, mod_name: String, file_id: int, key: String, expires: int, user_id: int, existing_download_id: String = "") -> void:
	"""通过 Nexus API 下载模组，使用 key/expires/user_id 参数（非Premium用户）

	Args:
		mod_id: 模组ID
		mod_name: 模组名称
		file_id: 文件ID
		key: 下载密钥
		expires: 过期时间戳
		user_id: 用户ID
		existing_download_id: 如果传入已有的下载ID，则使用该ID而不是创建新任务
	"""
	print("[_download_mod_via_nexus_api_with_params] mod_id=", mod_id, ", file_id=", file_id, ", key=", key.substr(0, 10) if key else "", ", expires=", expires, ", user_id=", user_id)

	# 获取 Nexus API（使用独立的 API 实例，不依赖 Nexus UI）
	if not nexus_api:
		if local_server:
			local_server.notify_download_complete(false, mod_name, "Nexus API not available")
		show_notification(translate("nexus_api_unavailable"), false)
		return

	show_notification(translate("getting_link"), true)

	# 直接使用 key/expires/user_id 参数获取下载链接
	var link_result = await nexus_api.get_download_link_with_key(mod_id, file_id, key, expires, user_id)
	if not link_result.success:
		var error_msg = link_result.get("error", "未知错误")
		if "premium" in error_msg.to_lower():
			show_notification(translate("nexus_download_requires_premium"), false)
		else:
			show_notification(translate_fmt("get_link_failed", [error_msg]), false)
		if local_server:
			local_server.notify_download_complete(false, mod_name, error_msg)
		return

	var download_url = link_result.get("download_link", "")
	if download_url.is_empty():
		if local_server:
			local_server.notify_download_complete(false, mod_name, "Empty download URL")
		show_notification(translate("download_link_empty"), false)
		return

	# 生成保存路径
	var safe_name = mod_name.replace("/", "_").replace("\\", "_").replace(":", "_").replace("*", "_").replace("?", "_").replace("\"", "_").replace("<", "_").replace(">", "_").replace("|", "_")
	var save_path = nexus_api.downloads_dir + "/" + safe_name + ".zip"

	show_notification(translate_fmt("downloading_mod", [mod_name]), true)

	# 下载文件，传递已有的下载ID以避免重复创建任务
	await _download_mod_file(download_url, save_path, mod_name, existing_download_id)


func _parse_nxm_url(nxm_url: String) -> Dictionary:
	"""解析NXM协议URL，返回包含下载信息的字典"""
	# 格式: nxm://slaythespire2/mods/23/files/1028?key=XXX&expires=XXX&user_id=XXX
	var result = {}

	# 提取游戏/模组ID/文件ID
	var path_match = nxm_url.replace("nxm://", "").split("?")[0]
	var path_parts = path_match.split("/")
	if path_parts.size() >= 5 and path_parts[0] == "slaythespire2" and path_parts[1] == "mods":
		result["mod_id"] = path_parts[2].to_int()
		result["file_id"] = path_parts[4].to_int()

	# 提取查询参数
	var query_string = nxm_url.split("?")
	if query_string.size() > 1:
		var params = query_string[1].split("&")
		for param in params:
			var kv = param.split("=")
			if kv.size() == 2:
				match kv[0]:
					"key":
						result["key"] = kv[1]
					"expires":
						result["expires"] = kv[1].to_int()
					"user_id":
						result["user_id"] = kv[1].to_int()

	print("[_parse_nxm_url] Parsed: ", result)
	return result


func _test_http_connection(url: String) -> bool:
	"""测试HTTP连接是否可用"""
	print("[_test_http_connection] Testing: ", url)

	var http_client = HTTPClient.new()

	# 解析URL
	var url_parts = url.replace("https://", "").replace("http://", "")
	var host_end = url_parts.find("/")
	var host = url_parts.substr(0, host_end) if host_end > 0 else url_parts

	print("[_test_http_connection] Host: ", host)

	var err = http_client.connect_to_host(host, 443)
	if err != OK:
		print("[_test_http_connection] Failed to connect: ", err)
		return false

	# 等待连接
	var timeout = 0
	while http_client.get_status() == HTTPClient.STATUS_CONNECTING:
		http_client.poll()
		await get_tree().process_frame
		timeout += 1
		if timeout > 100:  # 10秒超时
			print("[_test_http_connection] Connection timeout")
			return false

	if http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		print("[_test_http_connection] Not connected, status: ", http_client.get_status())
		return false

	# 发送HEAD请求测试
	var path = url_parts.substr(host_end) if host_end > 0 else "/"
	# 添加必要的Headers模拟浏览器请求
	var headers = PackedStringArray([
		"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
		"Accept: */*",
		"Referer: https://www.nexusmods.com/slaythespire2/mods/23",
		"Origin: https://www.nexusmods.com"
	])

	err = http_client.request(HTTPClient.METHOD_HEAD, path, headers)
	if err != OK:
		print("[_test_http_connection] Request failed: ", err)
		return false

	# 等待响应
	timeout = 0
	while http_client.get_status() == HTTPClient.STATUS_REQUESTING:
		http_client.poll()
		await get_tree().process_frame
		timeout += 1
		if timeout > 100:
			print("[_test_http_connection] Request timeout")
			return false

	var status = http_client.get_status()
	print("[_test_http_connection] Response status: ", status)

	# 检查是否成功
	if status == HTTPClient.STATUS_CONNECTED or status == HTTPClient.STATUS_BODY:
		print("[_test_http_connection] Connection successful")
		return true
	else:
		print("[_test_http_connection] Connection failed, status: ", status)
		return false


func _download_with_powershell(url: String, save_path: String, download_id: String = "") -> bool:
	"""使用 PowerShell 下载文件"""
	print("[_download_with_powershell] URL: ", url)
	print("[_download_with_powershell] Save path: ", save_path)
	print("[_download_with_powershell] download_id: ", download_id)

	# 将保存路径转换为绝对路径
	var abs_save_path = save_path
	if save_path.begins_with("res://"):
		abs_save_path = ProjectSettings.globalize_path(save_path)
	elif save_path.begins_with("user://"):
		abs_save_path = ProjectSettings.globalize_path(save_path)
	elif save_path.begins_with("/") or (save_path.length() >= 2 and save_path[1] == ":"):
		# 已经是绝对路径（Unix / 或 Windows E:/ 格式），直接使用
		pass
	else:
		# 相对路径，基于项目目录
		abs_save_path = get_base_path().path_join(save_path)

	print("[_download_with_powershell_async] abs_save_path: ", abs_save_path)

	print("[_download_with_powershell] Absolute save path: ", abs_save_path)

	# 确保目标目录存在
	var dir_path = abs_save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	# 获取文件大小（通过 HEAD 请求）
	var total_size: int = 0
	# URL中的%需要双写为%%才能在PowerShell的-Command参数中正确传递
	var url_for_ps = url.replace("%", "%%")
	var ps_size_script = "(Invoke-WebRequest -Uri '%s' -Method HEAD -UseBasicParsing).Headers['Content-Length']" % url_for_ps
	var output = []
	var exit_code = OS.execute("powershell", ["-NoProfile", "-Command", ps_size_script], output, true)
	if exit_code == 0 and output.size() > 0 and output[0].strip_edges().is_valid_int():
		total_size = output[0].strip_edges().to_int()
		print("[_download_with_powershell] Total size from HEAD: ", total_size)

	# 更新总大小到任务
	if not download_id.is_empty() and download_tasks.has(download_id):
		download_tasks[download_id]["total_size"] = total_size
		if total_size > 0:
			download_tasks[download_id]["file_size"] = _format_file_size(total_size)

	# 构建 PowerShell 下载命令（使用单引号包裹 URL，避免 & 被解析为命令分隔符）
	# URL中的%需要双写为%%才能在PowerShell的-Command参数中正确传递
	var ps_download_script = "Invoke-WebRequest -Uri '%s' -OutFile '%s' -UserAgent 'Mozilla/5.0' -UseBasicParsing" % [url_for_ps, abs_save_path]
	var start_time = Time.get_unix_time_from_system()

	# 开始下载
	exit_code = OS.execute("powershell", ["-NoProfile", "-Command", ps_download_script], output, true)

	# 检查进度（通过文件大小）
	if exit_code == 0 and FileAccess.file_exists(abs_save_path):
		var file = FileAccess.open(abs_save_path, FileAccess.READ)
		if file:
			var downloaded_size = file.get_length()
			file.close()

			# 计算速度和时间
			var elapsed = Time.get_unix_time_from_system() - start_time
			var speed_bytes = 0
			if elapsed > 0:
				speed_bytes = int(downloaded_size / elapsed)

			# 计算进度
			var progress = 100.0
			if total_size > 0:
				progress = (downloaded_size * 100.0) / total_size

			# 更新UI
			var speed_str = ""
			if speed_bytes > 0:
				speed_str = _format_file_size(speed_bytes) + "/s"

			if not download_id.is_empty():
				_update_download_task_progress(download_id, progress, speed_str, speed_bytes, downloaded_size, total_size, _format_file_size(total_size))

	print("[_download_with_powershell] Exit code: ", exit_code)

	if exit_code != 0:
		print("[_download_with_powershell] Failed: ", output)
		return false

	# 检查文件是否存在
	var test_file = FileAccess.open(abs_save_path, FileAccess.READ)
	if test_file == null:
		print("[_download_with_powershell] File not created at: ", abs_save_path)
		return false
	test_file.close()

	# 更新最终进度
	if not download_id.is_empty() and download_tasks.has(download_id):
		var final_size = 0
		var f = FileAccess.open(abs_save_path, FileAccess.READ)
		if f:
			final_size = f.get_length()
			f.close()
		_update_download_task_progress(download_id, 100.0, "", 0, final_size, total_size, _format_file_size(total_size))

	print("[_download_with_powershell] Success!")
	return true


# 异步下载回调信号
signal download_complete(download_id: String, success: bool, mod_name: String, error: String)

func _download_with_powershell_async(url: String, save_path: String, download_id: String, mod_name: String) -> void:
	"""使用 PowerShell 异步下载文件（使用后台线程）"""
	print("[_download_with_powershell_async] Starting async download...")
	print("[_download_with_powershell_async] URL: ", url)
	print("[_download_with_powershell_async] Save path: ", save_path)
	print("[_download_with_powershell_async] download_id: ", download_id)

	# 将保存路径转换为绝对路径
	var abs_save_path = save_path
	if save_path.begins_with("res://"):
		abs_save_path = ProjectSettings.globalize_path(save_path)
	elif save_path.begins_with("user://"):
		abs_save_path = ProjectSettings.globalize_path(save_path)
	elif save_path.begins_with("/") or (save_path.length() >= 2 and save_path[1] == ":"):
		# 已经是绝对路径（Unix / 或 Windows E:/ 格式），直接使用
		pass
	else:
		# 相对路径，基于项目目录
		abs_save_path = get_base_path().path_join(save_path)

	print("[_download_with_powershell_async] abs_save_path: ", abs_save_path)

	# 确保目标目录存在
	var dir_path = abs_save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	# 使用线程执行下载（包含获取文件大小）
	var thread = Thread.new()
	var args = {
		"url": url,
		"abs_save_path": abs_save_path,
		"download_id": download_id,
		"mod_name": mod_name,
		"total_size": 0
	}
	thread.start(_thread_download_wrapper.bind(args))

	# 启动进度监控定时器（每0.5秒检查一次）
	# 延迟启动，确保线程有时间初始化
	await get_tree().create_timer(0.1).timeout
	_monitor_download_progress(abs_save_path, download_id, 0)


func _monitor_download_progress(abs_save_path: String, download_id: String, total_size: int) -> void:
	"""监控下载进度（使用定时器）"""
	if download_id.is_empty() or not download_tasks.has(download_id):
		return

	# 创建定时器
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = false
	# 使用固定参数，因为定时器回调不能有参数
	timer.timeout.connect(_on_progress_timer_timeout)
	add_child(timer)
	timer.start()

	# 保存监控信息到字典（不需要保存total_size，从任务数据获取）
	_download_progress_timers[download_id] = {
		"timer": timer,
		"abs_save_path": abs_save_path
	}


func _on_progress_timer_timeout() -> void:
	"""定时器超时回调"""
	# 遍历所有活跃的下载任务
	var keys_to_check = _download_progress_timers.keys()
	for download_id in keys_to_check:
		if not _download_progress_timers.has(download_id):
			continue
		var monitor_info = _download_progress_timers[download_id]
		if typeof(monitor_info) != TYPE_DICTIONARY:
			continue
		var abs_save_path = monitor_info.get("abs_save_path", "")
		if abs_save_path.is_empty():
			continue
		# 从任务数据中获取总大小，而非从monitor_info获取
		_check_download_progress(abs_save_path, download_id)


func _check_download_progress(abs_save_path: String, download_id: String) -> void:
	"""检查下载进度（定时器回调）"""
	print("[_check_download_progress] Checking: ", download_id)

	# 从任务数据中获取总大小
	var total_size = 0
	if download_tasks.has(download_id):
		total_size = download_tasks[download_id].get("total_size", 0)
		print("[_check_download_progress] Total size from task: ", total_size)

	# 检查任务是否还存在
	if not download_tasks.has(download_id):
		print("[_check_download_progress] Task not found: ", download_id)
		_stop_progress_monitor(download_id)
		return

	var status = download_tasks[download_id].get("status", "")
	print("[_check_download_progress] Status: ", status)

	# 下载完成、安装中或暂停都需要停止监控
	if status != "downloading" and status != "installing" and status != "paused":
		_stop_progress_monitor(download_id)
		return

	# 检查文件是否存在
	if not FileAccess.file_exists(abs_save_path):
		# 文件不存在，显示正在连接
		_update_download_task_progress(download_id, 5.0, "正在连接...", 0, 0, total_size, _format_file_size(total_size))
		return

	var last_size = download_tasks[download_id].get("last_size", 0)
	var start_time = download_tasks[download_id].get("start_time", Time.get_unix_time_from_system())

	# 检查文件大小
	var file = FileAccess.open(abs_save_path, FileAccess.READ)
	if file:
		var current_size = file.get_length()
		file.close()
		print("[_check_download_progress] Current: ", current_size, ", Total: ", total_size, ", Last: ", last_size)

		# 计算速度
		var elapsed = Time.get_unix_time_from_system() - start_time
		var speed_bytes = 0
		if elapsed > 0 and current_size > last_size:
			speed_bytes = int((current_size - last_size) / max(elapsed, 0.1))

		# 计算进度
		var progress = 0.0
		if total_size > 0:
			progress = (current_size * 100.0) / total_size
		else:
			progress = 50.0

		# 更新UI - 速度始终显示
		var speed_str = "等待中"
		if speed_bytes > 0:
			speed_str = _format_file_size(speed_bytes) + "/s"

		# 计算显示的大小字符串
		var file_size_str = "计算中..."
		if total_size > 0:
			file_size_str = _format_file_size(current_size) + " / " + _format_file_size(total_size)
		elif current_size > 0:
			file_size_str = _format_file_size(current_size)

		download_tasks[download_id]["last_size"] = current_size
		_update_download_task_progress(download_id, progress, speed_str, speed_bytes, current_size, total_size, file_size_str)

		# 注意：不要在这里自动触发安装！让下载线程完成后通过正常流程处理
		# 否则会导致文件不完整时也尝试安装


func _stop_progress_monitor(download_id: String) -> void:
	"""停止进度监控"""
	if _download_progress_timers.has(download_id):
		var monitor_info = _download_progress_timers[download_id]
		var timer = monitor_info.get("timer")
		if timer:
			timer.stop()
			timer.queue_free()
		_download_progress_timers.erase(download_id)

func _thread_download_wrapper(args: Dictionary) -> void:
	"""后台线程下载包装器（使用curl）"""
	var url = args["url"]
	var abs_save_path = args["abs_save_path"]
	var download_id = args["download_id"]
	var mod_name = args["mod_name"]

	print("[_thread_download_wrapper] Starting download in thread...")

	# 检查是否已暂停或取消
	if download_tasks.has(download_id):
		var status = download_tasks[download_id].get("status", "")
		if status == "paused" or status == "cancelled":
			print("[_thread_download_wrapper] Download cancelled/paused before start")
			return

	# 获取文件大小（使用PowerShell，更可靠）
	# URL中的%需要双写为%%才能在PowerShell的-Command参数中正确传递
	var url_for_ps = url.replace("%", "%%")
	var total_size: int = 0
	var ps_size_script = "(Invoke-WebRequest -Uri '%s' -Method HEAD -UseBasicParsing).Headers['Content-Length']" % url_for_ps
	var size_output = []
	var size_exit_code = OS.execute("powershell", ["-NoProfile", "-Command", ps_size_script], size_output, true)
	print("[_thread_download_wrapper] Size command exit code: ", size_exit_code)
	print("[_thread_download_wrapper] Size output: ", size_output)
	if size_exit_code == 0 and size_output.size() > 0:
		# PowerShell HEAD 返回的只是数字
		for line in size_output:
			var trimmed = line.strip_edges()
			if trimmed.is_valid_int():
				total_size = trimmed.to_int()
				print("[_thread_download_wrapper] Total size from HEAD: ", total_size)
				# 更新任务信息（需要回到主线程）
				call_deferred("_update_download_size", download_id, total_size)
				break

	# 检查是否需要断点续传
	var resume_bytes = 0
	if FileAccess.file_exists(abs_save_path):
		var partial_file = FileAccess.open(abs_save_path, FileAccess.READ)
		if partial_file:
			resume_bytes = partial_file.get_length()
			partial_file.close()
			# 如果文件太小（小于10KB），认为是无效文件，删除重新下载
			if resume_bytes > 0 and resume_bytes < 10240:
				print("[_thread_download_wrapper] Existing file too small (", resume_bytes, " bytes), deleting to re-download")
				DirAccess.remove_absolute(abs_save_path)
				resume_bytes = 0
			elif resume_bytes > 0:
				print("[_thread_download_wrapper] Partial file exists, resuming from byte: ", resume_bytes)

	# 如果没有部分文件，删除可能存在的旧文件
	if resume_bytes == 0 and FileAccess.file_exists(abs_save_path):
		DirAccess.remove_absolute(abs_save_path)

	# 使用 PowerShell 下载，对 URL 和重定向处理更好
	# URL中的%需要双写为%%才能在PowerShell中正确传递
	var ps_url = url.replace("%", "%%")
	var ps_save_path = abs_save_path.replace("/", "\\")
	var ps_script = "$headers = @{'User-Agent'='Mozilla/5.0'; 'Referer'='https://www.nexusmods.com/'}; Invoke-WebRequest -Uri '%s' -OutFile '%s' -Headers $headers -UseBasicParsing -TimeoutSec 600" % [ps_url, ps_save_path]
	var download_output = []
	print("[_thread_download_wrapper] Running PowerShell download...")
	var download_exit_code = OS.execute("powershell", ["-NoProfile", "-Command", ps_script], download_output, true)
	print("[_thread_download_wrapper] PowerShell exit code: ", download_exit_code)
	print("[_thread_download_wrapper] PowerShell output: ", download_output)

	print("[_thread_download_wrapper] File exists check: ", FileAccess.file_exists(abs_save_path), " at: ", abs_save_path)

	var result = false
	if FileAccess.file_exists(abs_save_path):
		var file = FileAccess.open(abs_save_path, FileAccess.READ)
		if file:
			var downloaded_size = file.get_length()
			file.close()
			print("[_thread_download_wrapper] Downloaded bytes: ", downloaded_size)
			if downloaded_size >= 1024:  # 至少1KB（避免下载到错误页面）
				result = true
			else:
				print("[_thread_download_wrapper] File too small: ", downloaded_size)
		else:
			print("[_thread_download_wrapper] Could not open file")
	else:
		print("[_thread_download_wrapper] File does NOT exist at: ", abs_save_path)

	if not result:
		print("[_thread_download_wrapper] Download failed, exit code: ", download_exit_code)
		print("[_thread_download_wrapper] Output: ", download_output)

	print("[_thread_download_wrapper] Download result: ", result)

	# 回到主线程处理结果
	call_deferred("_on_async_download_complete", download_id, mod_name, result)


func _download_with_http_client(url: String, abs_save_path: String, download_id: String) -> bool:
	"""使用curl下载文件（不依赖断点续传，每次完整下载）"""
	print("[_download_with_http_client] Starting download with curl...")

	# 删除可能存在的旧文件，确保完整下载
	if FileAccess.file_exists(abs_save_path):
		DirAccess.remove_absolute(abs_save_path)
		print("[_download_with_http_client] Deleted existing file for clean download")

	# 使用curl下载（不使用断点续传，完整下载）
	# URL需要编码空格
	var encoded_url = url.replace(" ", "%20")
	var curl_command = "curl -L --max-time 600 -o \"%s\" -A \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\" -- \"%s\"" % [abs_save_path, encoded_url]
	print("[_download_with_http_client] Running: ", curl_command)

	# 执行下载
	var output = []
	var exit_code = OS.execute("cmd", ["/C", curl_command], output, true)

	print("[_download_with_http_client] Exit code: ", exit_code)
	print("[_download_with_http_client] Output: ", output)

	if exit_code == 0:
		# 下载成功，检查文件
		if FileAccess.file_exists(abs_save_path):
			var file = FileAccess.open(abs_save_path, FileAccess.READ)
			if file:
				var downloaded_size = file.get_length()
				file.close()
				print("[_download_with_http_client] Downloaded bytes: ", downloaded_size)

				# 验证文件大小是否合理（至少要大于10KB）
				if downloaded_size < 10240:
					print("[_download_with_http_client] File too small, likely error page")
					DirAccess.remove_absolute(abs_save_path)
					return false

				# 验证ZIP文件头
				var check_file = FileAccess.open(abs_save_path, FileAccess.READ)
				if check_file:
					var header_bytes = check_file.get_buffer(4)
					check_file.close()
					if header_bytes.size() >= 2 and header_bytes[0] == 0x50 and header_bytes[1] == 0x4B:
						# 更新任务信息
						if download_tasks.has(download_id):
							download_tasks[download_id]["bytes_downloaded"] = downloaded_size
							download_tasks[download_id]["downloaded_size"] = downloaded_size
						return true
					else:
						print("[_download_with_http_client] Invalid ZIP header, deleting file")
						DirAccess.remove_absolute(abs_save_path)
						return false

	print("[_download_with_http_client] Download failed, exit code: ", exit_code)
	print("[_download_with_http_client] Output: ", output)
	return false


func _retry_download_command(abs_save_path: String, url: String, download_id: String) -> bool:
	"""重试下载命令的通用逻辑"""
	# 删除部分文件
	if FileAccess.file_exists(abs_save_path):
		DirAccess.remove_absolute(abs_save_path)
		print("[_retry_download_command] Deleted partial file")

	# 重新下载（不使用断点续传），添加超时限制
	# URL中包含空格和特殊字符，需要用双引号包裹
	var retry_command = "curl -L --max-time 300 -o \"%s\" -A \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\" -- \"%s\"" % [abs_save_path, url]
	print("[_retry_download_command] Retry command: ", retry_command)
	var retry_output = []
	var retry_exit_code = OS.execute("cmd", ["/C", retry_command], retry_output, true)
	print("[_retry_download_command] Retry exit code: ", retry_exit_code)
	print("[_retry_download_command] Retry output: ", retry_output)

	if retry_exit_code == 0:
		if FileAccess.file_exists(abs_save_path):
			var retry_file = FileAccess.open(abs_save_path, FileAccess.READ)
			if retry_file:
				var downloaded_size = retry_file.get_length()
				retry_file.close()
				print("[_retry_download_command] Retry successful, downloaded bytes: ", downloaded_size)

				# 验证下载的文件是否有效（必须是有效的ZIP，最小10KB）
				if downloaded_size < 10240:  # 小于10KB可能是错误页面
					print("[_retry_download_command] File too small, likely error page")
					DirAccess.remove_absolute(abs_save_path)
					return false

				# 验证是否是有效的ZIP文件（ZIP文件以 PK 开头）
				var check_file = FileAccess.open(abs_save_path, FileAccess.READ)
				if check_file:
					var header_bytes = check_file.get_buffer(4)
					check_file.close()
					if header_bytes.size() < 4 or header_bytes[0] != 0x50 or header_bytes[1] != 0x4B:
						print("[_retry_download_command] Invalid ZIP file header")
						DirAccess.remove_absolute(abs_save_path)
						return false

				if download_tasks.has(download_id):
					download_tasks[download_id]["bytes_downloaded"] = downloaded_size
					download_tasks[download_id]["downloaded_size"] = downloaded_size
				return true
	else:
		print("[_retry_download_command] Retry failed with exit code: ", retry_exit_code)
		if retry_output.size() > 0:
			print("[_retry_download_command] Retry error output: ", retry_output)

	return false


func _on_async_download_complete(download_id: String, mod_name: String, success: bool) -> void:
	"""异步下载完成的回调"""
	print("[_on_async_download_complete] download_id: ", download_id, ", success: ", success)

	if not success:
		if local_server:
			local_server.notify_download_complete(false, mod_name, "Download failed")
		show_notification(translate("download_failed"), false)
		_update_download_task_status(download_id, "failed", "Download failed")
		return

	print("[_on_async_download_complete] Download complete, installing...")
	show_notification(translate("download_complete_installing"), true)

	# 从download_tasks中获取save_path
	var save_path = ""
	if download_tasks.has(download_id):
		save_path = download_tasks[download_id].get("save_path", "")

	if save_path.is_empty():
		# 尝试从 nexus_api 获取默认路径
		if nexus_api:
			save_path = nexus_api.downloads_dir + "/" + mod_name + ".zip"

	print("[_on_async_download_complete] save_path: ", save_path)

	# 验证下载的文件是否完整有效
	if not save_path.is_empty():
		var abs_save_path = ProjectSettings.globalize_path(save_path)
		if not _verify_downloaded_file(abs_save_path):
			print("[_on_async_download_complete] Downloaded file is corrupted, retrying...")
			# 文件损坏，删除并重新下载
			if FileAccess.file_exists(abs_save_path):
				DirAccess.remove_absolute(abs_save_path)
			# 重新开始下载
			_retry_corrupted_download(download_id)
			return

	# 安装模组或整合包
	_update_download_task_status(download_id, "installing")

	# 判断是整合包还是普通模组：整合包任务名以 "bundle_" 开头
	var is_bundle_download = mod_name.begins_with("bundle_")
	print("[_on_async_download_complete] is_bundle_download: ", is_bundle_download)

	var install_result
	if is_bundle_download:
		# 整合包下载完成，自动导入到整合包列表
		print("[_on_async_download_complete] Importing bundle...")
		var import_ok = _import_bundle(save_path)
		install_result = {"success": import_ok, "message": "" if import_ok else "导入失败", "installed_mods": []}
	else:
		# 普通模组安装
		var download_source = ""
		if download_tasks.has(download_id):
			download_source = download_tasks[download_id].get("download_source", "")
		print("[_on_async_download_complete] Install source: '", download_source, "'")
		install_result = ModUtils.install_mod(save_path, "", download_source, mod_required_fields)

	# 处理安装结果
	if install_result.get("success", false):
		if is_bundle_download:
			# 整合包导入成功
			show_notification(translate("bundle_import_success"), true)
			_show_download_success_notification(mod_name)
			if local_server:
				local_server.notify_download_complete(true, mod_name)
			_update_download_task_status(download_id, "completed")
		else:
			# 普通模组安装成功
			var installed_mods = install_result.get("installed_mods", [])

			# 检查是否有版本冲突
			if install_result.get("has_conflicts", false):
				var conflicts = install_result.get("conflicts", [])
				print("[_on_async_download_complete] Version conflicts detected: ", conflicts.size())
				# 对于下载安装的模组，自动选择用新版本替换旧版本
				_resolve_download_conflicts(download_id, conflicts)
				return

			if not installed_mods.is_empty():
				# 更新已安装模组的 JSON 文件
				var download_source = ""
				if download_tasks.has(download_id):
					download_source = download_tasks[download_id].get("download_source", "")
				var mod_info = installed_mods[0]
				var mod_path = mod_info.get("path", "")
				if not mod_path.is_empty():
					_update_mod_json_download_source(mod_path, download_source)

				var installed_name = installed_mods[0].get("name", mod_name)
				var installed_version = installed_mods[0].get("version", "v0.0.0")
				if download_tasks.has(download_id):
					download_tasks[download_id]["version"] = installed_version
				show_notification(translate_fmt("install_success", [installed_name]), true)
				_show_download_success_notification(installed_name)
				if local_server:
					local_server.notify_download_complete(true, installed_name)
				_update_download_task_status(download_id, "completed")
				call_deferred("_delayed_load_mods")
			else:
				show_notification(translate("install_failed_no_valid_mod"), false)
				if local_server:
					local_server.notify_download_complete(false, mod_name, "No valid mods found")
				_update_download_task_status(download_id, "failed", "No valid mods found")
	else:
		var error_msg = install_result.get("message", "Unknown error")
		show_notification(translate_fmt("install_failed", [error_msg]), false)
		if local_server:
			local_server.notify_download_complete(false, mod_name, error_msg)
		_update_download_task_status(download_id, "failed", error_msg)


# 处理下载安装时的版本冲突（自动用新版本替换旧版本）
func _resolve_download_conflicts(download_id: String, conflicts: Array) -> void:
	print("[_resolve_download_conflicts] Resolving ", conflicts.size(), " conflicts")
	var download_source = ""
	if download_tasks.has(download_id):
		download_source = download_tasks[download_id].get("download_source", "")

	for conflict in conflicts:
		var mod_id = conflict.get("id", "")
		var new_path = conflict.get("new_path", "")
		var existing_path = conflict.get("existing_path", "")

		print("[_resolve_download_conflicts] mod_id: '", mod_id, "'")
		print("[_resolve_download_conflicts] new_path: '", new_path, "'")
		print("[_resolve_download_conflicts] existing_path: '", existing_path, "'")

		if mod_id.is_empty() or new_path.is_empty() or existing_path.is_empty():
			print("[_resolve_download_conflicts] Skipping due to empty path")
			continue

		# 检查新版本文件是否存在
		print("[_resolve_download_conflicts] new_path exists: ", DirAccess.dir_exists_absolute(new_path))
		print("[_resolve_download_conflicts] existing_path exists: ", DirAccess.dir_exists_absolute(existing_path))

		# 列出 new_path 中的文件
		if DirAccess.dir_exists_absolute(new_path):
			var new_dir = DirAccess.open(new_path)
			if new_dir:
				print("[_resolve_download_conflicts] new_path contents: ")
				new_dir.list_dir_begin()
				var entry = new_dir.get_next()
				while entry != "":
					print("  - ", entry)
					entry = new_dir.get_next()
				new_dir.list_dir_end()

		# 删除旧版本
		print("[_resolve_download_conflicts] Deleting existing_path...")
		_delete_directory_recursive(existing_path)

		# 复制新版本到目标位置
		print("[_resolve_download_conflicts] Copying new_path to existing_path...")
		var copy_result = FileUtils.copy_directory(new_path, existing_path)
		print("[_resolve_download_conflicts] Copy result: ", copy_result)

		# 验证复制结果
		if DirAccess.dir_exists_absolute(existing_path):
			var copied_dir = DirAccess.open(existing_path)
			if copied_dir:
				print("[_resolve_download_conflicts] existing_path after copy: ")
				copied_dir.list_dir_begin()
				var entry = copied_dir.get_next()
				while entry != "":
					print("  - ", entry)
					entry = copied_dir.get_next()
				copied_dir.list_dir_end()

		# 更新下载源信息
		_update_mod_json_download_source(existing_path, download_source)

	# 获取第一个冲突模组的信息用于通知
	if not conflicts.is_empty():
		var first_conflict = conflicts[0]
		var mod_name = first_conflict.get("name", "Unknown")
		var new_version = first_conflict.get("new_version", "")
		show_notification(translate_fmt("mod_updated", [mod_name, new_version]), true)
		_show_download_success_notification(mod_name)
		if local_server:
			local_server.notify_download_complete(true, mod_name)
		_update_download_task_status(download_id, "completed")
		call_deferred("_delayed_load_mods")


func _download_mod_direct(url: String, mod_name: String, existing_download_id: String = "") -> void:
	"""使用直链直接下载模组

	Args:
		url: 下载URL
		mod_name: 模组名称
		existing_download_id: 如果传入已有的下载ID，则使用该ID而不是创建新任务
	"""
	print("[_download_mod_direct] Using URL: ", url)

	# 检查是否是直链 URL（来自 "click here" 链接）
	var actual_url = url
	if url.begins_with("https://") or url.begins_with("http://"):
		# 直链 URL，直接使用（可能是 supporter-files.nexus-cdn.com）
		actual_url = url
		print("[_download_mod_direct] Using direct URL as-is: ", actual_url)
	elif url.begins_with("nxm://"):
		# 解析 NXM URL 获取参数
		var parsed = _parse_nxm_url(url)
		if parsed.size() > 0 and parsed.has("mod_id") and parsed.has("file_id"):
			var mod_id = parsed.get("mod_id")
			var file_id = parsed.get("file_id")
			var key = parsed.get("key", "")
			var expires = parsed.get("expires", 0)
			var user_id = parsed.get("user_id", 0)

			# 正确的下载 URL 格式：
			# https://supporter-files.nexus-cdn.com/{game_id}/{mod_id}/{file_id}?key=...&expires=...&user_id=...
			# game_id for Slay the Spire 2 = 8916
			# 注意：file_id 直接作为路径的一部分，不带文件名
			actual_url = "https://supporter-files.nexus-cdn.com/8916/%d/%d?key=%s&expires=%d&user_id=%d" % [mod_id, file_id, key, expires, user_id]
			print("[_download_mod_direct] Constructed URL: ", actual_url)

			# 尝试连接测试
			print("[_download_mod_direct] Testing connection...")
			var test_result = await _test_http_connection(actual_url)
			if not test_result:
				# 如果失败，尝试备用格式 (files.nexusmods.com)
				print("[_download_mod_direct] Primary URL failed, trying fallback...")
				actual_url = "https://files.nexusmods.com/downloader/%d/%d?key=%s&expires=%d&user_id=%d" % [mod_id, file_id, key, expires, user_id]
				print("[_download_mod_direct] Fallback URL: ", actual_url)
		else:
			show_notification(translate("cannot_parse_nxm_link"), false)
			return
	elif url.contains("nexusmods.com") and not url.begins_with("http"):
		# 处理相对路径
		actual_url = "https://" + url

	# 直接下载 URL
	# 获取下载目录（优先使用独立的 nexus_api 实例）
	var downloads_dir = ""
	if nexus_api:
		downloads_dir = nexus_api.downloads_dir
	else:
		# 使用绝对路径
		downloads_dir = get_base_path() + "downloads"

	# 生成保存路径
	var safe_name = mod_name.replace("/", "_").replace("\\", "_").replace(":", "_").replace("*", "_").replace("?", "_").replace("\"", "_").replace("<", "_").replace(">", "_").replace("|", "_")
	var save_path = downloads_dir + "/" + safe_name + ".zip"

	print("[_download_mod_direct] downloads_dir: ", downloads_dir)
	print("[_download_mod_direct] save_path: ", save_path)

	show_notification(translate_fmt("downloading_mod", [mod_name]), true)

	# 直接下载 URL，传递已有的下载ID以避免重复创建任务
	await _download_mod_file(actual_url, save_path, mod_name, existing_download_id)
	# _download_mod_file 内部已经调用 notify_download_complete，无需重复调用


func _download_mod_file(url: String, save_path: String, mod_name: String, existing_download_id: String = "") -> void:
	"""下载模组文件并自动安装

	Args:
		url: 下载URL
		save_path: 保存路径
		mod_name: 模组名称
		existing_download_id: 如果传入已有的下载ID，则使用该ID而不是创建新任务
	"""
	print("[_download_mod_file] Downloading: ", mod_name, " to: ", save_path)

	# 检查save_path是否有效
	if save_path.is_empty():
		print("[_download_mod_file] ERROR: save_path is empty!")
		show_notification("下载路径为空", false)
		return

	# 从URL提取正确的文件扩展名
	var file_ext = ".zip"  # 默认
	if url.contains(".rar?"):
		file_ext = ".rar"
	elif url.contains(".7z?"):
		file_ext = ".7z"

	# 替换保存路径的扩展名
	if file_ext != ".zip":
		var base_path = save_path.get_basename()
		save_path = base_path + file_ext
		print("[_download_mod_file] Corrected extension: ", save_path)

	# 使用已有的下载ID，或者创建新任务
	var download_id: String
	if not existing_download_id.is_empty() and download_tasks.has(existing_download_id):
		download_id = existing_download_id
		print("[_download_mod_file] Using existing download task: ", download_id)
		# 更新URL
		download_tasks[download_id]["download_url"] = url
	else:
		download_id = _create_download_task(mod_name, url)
		print("[_download_mod_file] Created new download task: ", download_id)

	# 自动检测下载来源（基于URL）
	var auto_source = ""
	if url.contains("nexus-cdn.com") or url.contains("nexusmods.com"):
		auto_source = "nexus"
		download_tasks[download_id]["download_source"] = auto_source
		print("[_download_mod_file] Auto-detected source: ", auto_source)
	download_tasks[download_id]["save_path"] = save_path

	# 使用 PowerShell 在后台下载（异步执行避免卡顿）
	print("[_download_mod_file] Starting background download...")
	_download_with_powershell_async(url, save_path, download_id, mod_name)

	# 保留下载的压缩包，不删除


func _init_nexus_mods_ui() -> void:
	push_error("=== _init_nexus_mods_ui START ===")
	print("=== _init_nexus_mods_ui START ===")
	# 获取NexusMods UI节点
	nexus_mods_ui = find_child_node(self, "NexusModsUI")
	push_error("=== _init_nexus_mods_ui nexus_mods_ui = " + str(nexus_mods_ui) + " ===")
	print("[_init_nexus_mods_ui] nexus_mods_ui = ", nexus_mods_ui)
	print("[_init_nexus_mods_ui] TabContainer children: ", $TabContainer.get_children().map(func(n): return n.name))
	if nexus_mods_ui:
		print("[_init_nexus_mods_ui] NexusModsUI found, loading scene")
		# 加载NexusMods UI场景
		var nexus_scene = load("res://ui/nexus_mods.tscn")
		print("[_init_nexus_mods_ui] nexus_scene = ", nexus_scene)
		if nexus_scene:
			var nexus_instance = nexus_scene.instantiate()
			print("[_init_nexus_mods_ui] nexus_instance = ", nexus_instance)

			# 设置回调
			nexus_instance.set_view_details_callback(_on_nexus_mod_view_details)

			# 设置翻译函数
			nexus_instance.translate_func = translate

			# 先添加到场景
			nexus_mods_ui.add_child(nexus_instance)
			nexus_mods_instance = nexus_instance

			# 启动本地HTTP服务器（在 Nexus UI 初始化后）
			_start_local_server()

			# 设置API Key（这会触发load_trending_mods）
			var saved_api_key = config.get_value("nexus", "api_key", "")
			print("[_init_nexus_mods_ui] saved_api_key = '", saved_api_key, "'")
			if not saved_api_key.is_empty():
				nexus_instance.set_api_key(saved_api_key)
				# 同时设置到独立的 nexus_api 实例
				if nexus_api:
					nexus_api.set_api_key(saved_api_key)

			print("[init_ui] Initialized NexusMods UI")
		else:
			print("[_init_nexus_mods_ui] ERROR: failed to load nexus_mods.tscn")
	else:
		print("[_init_nexus_mods_ui] ERROR: NexusModsUI not found")

# 注意: API Key 配置节点现在由 _init_settings_ui_if_needed() 初始化


# 验证Nexus API Key
func _on_nexus_validate_pressed() -> void:
	print("[_on_nexus_validate_pressed] Called!")

	# 延迟获取节点（如果还没有初始化）
	if not nexus_api_key_edit:
		nexus_api_key_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusAPIKeyRow/NexusAPIKeyEdit")
	if not nexus_validate_btn:
		nexus_validate_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusAPIKeyRow/NexusValidateBtn")
	if not nexus_status_label:
		nexus_status_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusStatusLabel")

	print("[_on_nexus_validate_pressed] nexus_api_key_edit: ", nexus_api_key_edit)
	print("[_on_nexus_validate_pressed] nexus_mods_instance: ", nexus_mods_instance)
	print("[_on_nexus_validate_pressed] nexus_api: ", nexus_api)

	if not nexus_api_key_edit:
		print("[_on_nexus_validate_pressed] ERROR: nexus_api_key_edit is null")
		show_notification(translate("interface_not_ready"), false)
		return

	var api_key = nexus_api_key_edit.text.strip_edges()
	if api_key.is_empty():
		show_notification(translate("please_enter_api_key"), false)
		return

	# 保存API Key
	config.set_value("nexus", "api_key", api_key)
	config.save(config_path)
	print("[_on_nexus_validate_pressed] Saved API key to config")

	# 创建独立的Nexus API实例（如果没有）
	if not nexus_api:
		nexus_api = NexusAPI.new()
		print("[_on_nexus_validate_pressed] Created standalone NexusAPI instance")

	# 优先使用独立的nexus_api
	var api_to_validate = nexus_api
	if nexus_mods_instance:
		# 如果Nexus实例可用，也同步API Key
		var nexus_instance_api = nexus_mods_instance.get_nexus_api()
		if nexus_instance_api:
			nexus_instance_api.set_api_key(api_key)
			api_to_validate = nexus_instance_api

	api_to_validate.set_api_key(api_key)

	# 验证API Key
	_show_loading("正在验证API Key...")
	var result = await api_to_validate.validate_api_key()
	_hide_loading()

	if result.success:
		var username = result.get("username", "")
		var is_premium = result.get("is_premium", false)
		var status_text = "已验证: %s" % username
		if is_premium:
			status_text += " (Premium)"
		if nexus_status_label:
			nexus_status_label.text = status_text
		show_notification(translate_fmt("api_key_validate_success", [username]), true)

		# 保存验证状态到config
		config.set_value("nexus", "validated", true)
		config.set_value("nexus", "username", username)
		config.set_value("nexus", "is_premium", is_premium)
		config.save(config_path)
		print("[_on_nexus_validate_pressed] Saved validation status to config")

		# 同步 API Key 到独立的 nexus_api 实例
		if nexus_api:
			nexus_api.set_api_key(api_key)
	else:
		if nexus_status_label:
			nexus_status_label.text = "验证失败: " + result.get("error", "未知错误")
		show_notification(translate_fmt("api_key_validate_failed", [result.get("error", "")]), false)
		# 清除验证状态
		config.set_value("nexus", "validated", false)
		config.set_value("nexus", "username", "")
		config.set_value("nexus", "is_premium", false)
		config.save(config_path)


# Nexus模组详情回调
func _on_nexus_mod_view_details(mod_data: Dictionary) -> void:
	print("[Nexus] View details for: ", mod_data.get("name", ""))
	var mod_page_url = mod_data.get("mod_page_url", "")
	if not mod_page_url.is_empty():
		# 跳转浏览器打开详情页
		OS.shell_open(mod_page_url)


# 下载完成回调
func _on_download_completed(success: bool, file_path: String, error: String) -> void:
	if success:
		show_notification(translate_fmt("download_complete_file", [file_path.get_file()]), true)
		# 从下载列表移除并添加到已下载列表
		if nexus_mods_instance:
			var mod_name = file_path.get_file().get_basename()
			nexus_mods_instance.add_downloaded_item(file_path, mod_name)
	else:
		show_notification(translate_fmt("download_failed_error", [error]), false)


# Steam App ID for Slay the Spire 2
const STEAM_APP_ID := "2868840"


# Tesla档位字母 -> 启动模式字符串
func _map_gear_to_mode(gear: String) -> void:
	var mode_map = {
		"P": "multiplayer",  # P = 联机
		"D": "modded",       # D = 模组
		"R": "vanilla"       # R = 原版
	}
	var mode = mode_map.get(gear, "modded")
	_on_launch_mode_pressed(mode)


# 处理启动模式选择
func _on_launch_mode_pressed(mode: String) -> void:
	print("[Launch] Mode selected: ", mode)
	match mode:
		"vanilla":
			_launch_vanilla_mode()
		"modded":
			_launch_modded_mode()
		"multiplayer":
			# 通过统一的启动入口处理，检查设置决定启动方式
			_launch_multiplayer_mode()


# 原版启动 - 临时移除mods文件夹，启动游戏后恢复
func _launch_vanilla_mode() -> bool:
	var launch_via_steam = config.get_value("settings", "launch_via_steam", true)

	# 先移除 mods 文件夹（无论是否通过Steam启动都需要）
	if not _remove_mods_for_vanilla():
		return false

	if launch_via_steam:
		# 通过Steam协议启动 - 使用shell_open无法获取进程ID
		show_notification(translate("launching_game"), true)
		# Steam启动无法追踪进程，设置待恢复标记，下次启动时检查
		_set_vanilla_mode_pending(true)

		# 使用定时器检查游戏是否退出
		_schedule_steam_vanilla_restore_check()

		return _launch_via_steam("")
	else:
		# 直接启动游戏 - 可以获取进程ID
		if game_path.is_empty():
			show_notification(translate("game_path_not_set"), false)
			return false

		var exe_path = _find_game_executable()
		if exe_path.is_empty():
			show_notification(translate("game_exe_not_found"), false)
			return false

		print("[_launch_vanilla_mode] Starting game: ", exe_path)
		var process = OS.create_process(exe_path, [])
		if process == -1:
			show_notification(translate("launch_failed"), false)
			return false

		# 设置进程ID用于监控
		_vanilla_game_pid = process
		show_notification(translate("launching_game"), true)

		# 开始监控游戏进程
		_schedule_vanilla_restore_check()
		return true


# 原版模式待恢复标记
var _vanilla_mode_pending: bool = false
var _vanilla_game_pid: int = 0
var _vanilla_check_timer: SceneTreeTimer = null
var _vanilla_backup_renamed_path: String = ""  # 重命名后的mods文件夹路径

func _set_vanilla_mode_pending(pending: bool) -> void:
	_vanilla_mode_pending = pending
	config.set_value("settings", "vanilla_mode_pending", pending)
	config.save(config_path)
	print("[_set_vanilla_mode_pending] ", pending)


func _schedule_vanilla_restore_check() -> void:
	if _vanilla_check_timer:
		_vanilla_check_timer.timeout.disconnect(_check_vanilla_game_running)

	_vanilla_check_timer = get_tree().create_timer(2.0)
	_vanilla_check_timer.timeout.connect(_check_vanilla_game_running)
	print("[_schedule_vanilla_restore_check] Started")


# Steam启动时的检查（通过窗口标题检测）
var _steam_vanilla_check_timer: SceneTreeTimer = null
var _steam_vanilla_game_name: String = "SlayTheSpire2"

func _schedule_steam_vanilla_restore_check() -> void:
	if _steam_vanilla_check_timer:
		_steam_vanilla_check_timer.timeout.disconnect(_check_steam_vanilla_game_running)

	_steam_vanilla_check_timer = get_tree().create_timer(5.0)
	_steam_vanilla_check_timer.timeout.connect(_check_steam_vanilla_game_running)
	print("[_schedule_steam_vanilla_restore_check] Started")


func _check_steam_vanilla_game_running() -> void:
	print("[_check_steam_vanilla_game_running] Checking if game is running...")

	# 通过检查Steam进程间接判断游戏是否在运行
	# 查找SlayTheSpire2进程
	var found_process = false
	var output = []

	# 使用tasklist查找进程
	var exit_code = OS.execute("tasklist", ["/FI", "IMAGENAME eq SlayTheSpire2.exe"], output, true)
	print("[_check_steam_vanilla_game_running] tasklist exit code: ", exit_code)

	if exit_code == 0:
		var output_str = ""
		for line in output:
			output_str += line + " "
		print("[_check_steam_vanilla_game_running] output: ", output_str)

		if "SlayTheSpire2" in output_str:
			found_process = true

	if found_process:
		# 游戏还在运行，继续检查
		print("[_check_steam_vanilla_game_running] Game is still running, checking again...")
		_schedule_steam_vanilla_restore_check()
	else:
		# 游戏已退出，恢复mods
		print("[_check_steam_vanilla_game_running] Game exited, restoring mods...")
		_restore_mods_after_vanilla()
		if _steam_vanilla_check_timer:
			_steam_vanilla_check_timer.timeout.disconnect(_check_steam_vanilla_game_running)


func _check_vanilla_game_running() -> void:
	if _vanilla_game_pid == 0:
		print("[_check_vanilla_game_running] No PID, skipping")
		return

	# 检查进程是否还在运行
	var is_running = OS.is_process_running(_vanilla_game_pid)
	print("[_check_vanilla_game_running] PID: ", _vanilla_game_pid, " running: ", is_running)

	if not is_running:
		# 游戏已退出，恢复mods
		print("[_check_vanilla_game_running] Game exited, restoring mods...")
		_restore_mods_after_vanilla()
		_vanilla_game_pid = 0
		if _vanilla_check_timer:
			_vanilla_check_timer.timeout.disconnect(_check_vanilla_game_running)
	else:
		# 游戏还在运行，继续检查
		_schedule_vanilla_restore_check()


# 手动恢复 mods 文件夹（原版启动后调用）
func _restore_mods_after_vanilla() -> void:
	if game_path.is_empty():
		print("[_restore_mods_after_vanilla] game_path is empty, skipping restore")
		return

	var game_mods_dir = game_path.path_join("mods")
	# 备份目录在游戏目录旁边
	var backup_dir = game_path + "_mods_backup"

	print("[_restore_mods_after_vanilla] Starting...")
	print("[_restore_mods_after_vanilla] game_mods_dir: ", game_mods_dir)
	print("[_restore_mods_after_vanilla] backup_dir: ", backup_dir)
	print("[_restore_mods_after_vanilla] _vanilla_backup_renamed_path: ", _vanilla_backup_renamed_path)

	# 检查是否有重命名的mods目录
	if not _vanilla_backup_renamed_path.is_empty():
		print("[_restore_mods_after_vanilla] Checking renamed path...")
		if DirAccess.dir_exists_absolute(_vanilla_backup_renamed_path):
			# 先将 _DISABLED 改回 mods（如果 mods 不存在）
			if not DirAccess.dir_exists_absolute(game_mods_dir):
				var rename_result = DirAccess.rename_absolute(_vanilla_backup_renamed_path, game_mods_dir)
				print("[_restore_mods_after_vanilla] Rename back result: ", rename_result)
				if rename_result == OK:
					_vanilla_backup_renamed_path = ""
					show_notification(translate("mods_restored") if has_translation_key("mods_restored") else "模组已恢复", true)
					return

	# 标准的备份恢复流程
	if DirAccess.dir_exists_absolute(backup_dir):
		# 如果mods目录存在，先重命名
		if DirAccess.dir_exists_absolute(game_mods_dir):
			print("[_restore_mods_after_vanilla] Renaming existing game_mods_dir")
			var renamed_path = game_mods_dir + "_OLD"
			var rename_result = DirAccess.rename_absolute(game_mods_dir, renamed_path)
			if rename_result == OK:
				# 异步删除旧目录
				_delete_directory_force(renamed_path)

		if FileUtils.copy_directory(backup_dir, game_mods_dir):
			# 删除备份目录（重命名代替删除）
			var backup_renamed = backup_dir + "_TO_DELETE"
			if DirAccess.dir_exists_absolute(backup_dir):
				DirAccess.rename_absolute(backup_dir, backup_renamed)
				_delete_directory_force(backup_renamed)
			print("[_restore_mods_after_vanilla] Restored mods directory successfully")
			show_notification(translate("mods_restored") if has_translation_key("mods_restored") else "模组已恢复", true)
		else:
			print("[_restore_mods_after_vanilla] Failed to restore mods directory")
			show_notification(translate("restore_failed") if has_translation_key("restore_failed") else "恢复模组失败", false)
	else:
		print("[_restore_mods_after_vanilla] backup_dir does not exist, nothing to restore")
		show_notification(translate("no_mods_to_restore") if has_translation_key("no_mods_to_restore") else "没有需要恢复的模组", false)

	# 清除待恢复标记
	_vanilla_mode_pending = false
	config.set_value("settings", "vanilla_mode_pending", false)
	config.save(config_path)


# 临时移除 mods 文件夹用于原版启动
func _remove_mods_for_vanilla() -> bool:
	print("[_remove_mods_for_vanilla] Starting...")
	print("[_remove_mods_for_vanilla] game_path: ", game_path)
	if game_path.is_empty():
		show_notification(translate("game_path_not_set"), false)
		return false

	var game_mods_dir = game_path.path_join("mods")
	# 备份目录在游戏目录旁边
	var backup_dir = game_path + "_mods_backup"

	print("[_remove_mods_for_vanilla] game_mods_dir: ", game_mods_dir)
	print("[_remove_mods_for_vanilla] backup_dir: ", backup_dir)

	# 如果 mods 目录存在且不为空
	if DirAccess.dir_exists_absolute(game_mods_dir):
		print("[_remove_mods_for_vanilla] game_mods_dir exists")
		var dir = DirAccess.open(game_mods_dir)
		if dir:
			dir.list_dir_begin()
			var has_files = false
			var first_file = dir.get_next()
			while first_file != "":
				if first_file != "." and first_file != "..":
					has_files = true
					break
				first_file = dir.get_next()
			dir.list_dir_end()
			print("[_remove_mods_for_vanilla] has_files: ", has_files)

			if has_files:
				# 如果备份目录已存在，先删除
				if DirAccess.dir_exists_absolute(backup_dir):
					_delete_directory_recursive(backup_dir)

				var source_path = game_mods_dir
				var dest_path = backup_dir
				print("[_remove_mods_for_vanilla] source: ", source_path, " dest: ", dest_path)
				print("[_remove_mods_for_vanilla] Before copy, source exists: ", DirAccess.dir_exists_absolute(source_path))

				var copy_result = FileUtils.copy_directory(source_path, dest_path)
				print("[_remove_mods_for_vanilla] copy result: ", copy_result)

				if copy_result:
					print("[_remove_mods_for_vanilla] Copy succeeded, now removing source...")

					# 先尝试直接重命名（最快方法）
					var renamed_path = source_path + "_DISABLED"
					var rename_result = DirAccess.rename_absolute(source_path, renamed_path)

					if rename_result == OK:
						print("[_remove_mods_for_vanilla] Renamed to: ", renamed_path)
						# 存储重命名后的路径以便恢复
						_vanilla_backup_renamed_path = renamed_path
					else:
						# 重命名失败，尝试强制删除
						print("[_remove_mods_for_vanilla] Rename failed, trying force delete...")
						# 先关闭目录句柄
						if dir:
							dir.list_dir_end()
							dir = null
						var delete_result = _delete_directory_force(source_path)
						print("[_remove_mods_for_vanilla] Force delete result: ", delete_result)

						if not delete_result:
							print("[_remove_mods_for_vanilla] Warning: Could not remove mods folder")
				else:
					print("[_remove_mods_for_vanilla] Failed to copy mods directory")
					show_notification(translate("launch_failed"), false)
					return false
	else:
		print("[_remove_mods_for_vanilla] game_mods_dir does not exist")

	return true


# 模组启动 - 确保模组已启用后启动游戏
func _launch_modded_mode() -> bool:
	var launch_via_steam = config.get_value("settings", "launch_via_steam", true)

	if launch_via_steam:
		# 先复制启用状态的模组到游戏目录
		if game_path.is_empty():
			show_notification(translate("game_path_not_set"), false)
			return false
		_apply_enabled_mods_to_game()
		# 应用模组覆盖顺序（在模组已复制后，备份正确的 manifest）
		if not apply_override_order_before_launch():
			pass
		# 通过Steam协议启动（无法监控进程退出，manifest 会在下次启动时自动检查残留）
		var ok = _launch_via_steam("")
		if ok:
			show_notification("游戏已启动（Steam模式，覆盖顺序将在退出后自动恢复）", true)
		return ok

	# 以下为直接启动模式（不使用Steam）
	if game_path.is_empty():
		show_notification(translate("game_path_not_set"), false)
		return false

	# 找到游戏可执行文件
	var exe_path = _find_game_executable()
	if exe_path.is_empty():
		show_notification(translate("game_exe_not_found"), false)
		return false

	# 确保启用状态的模组已复制到游戏 mods 目录
	_apply_enabled_mods_to_game()

	# 应用模组覆盖顺序（在模组已复制后，备份正确的 manifest）
	if not apply_override_order_before_launch():
		pass

	# 启动游戏
	print("[_launch_modded_mode] Starting game: ", exe_path)
	var process_id = OS.create_process(exe_path, [])
	if process_id == -1:
		show_notification(translate("launch_failed"), false)
		return false

	# 监控进程退出
	_watch_game_process(process_id)
	show_notification(translate("launching_game"), true)
	return true


# 联机启动 - 检查设置并决定启动方式
func _launch_multiplayer_mode() -> bool:
	var launch_via_steam = config.get_value("settings", "launch_via_steam", true)
	var enable_fix_steam = config.get_value("settings", "enable_fix_steam", false)
	print("[_launch_multiplayer_mode] launch_via_steam: ", launch_via_steam)
	print("[_launch_multiplayer_mode] enable_fix_steam: ", enable_fix_steam)
	print("[_launch_multiplayer_mode] current_tag BEFORE: ", current_tag)
	print("[_launch_multiplayer_mode] tag_data keys: ", tag_data.keys())
	print("[_launch_multiplayer_mode] 联机模组 in tag_data: ", tag_data.has("联机模组"))

	if launch_via_steam:
		# 通过Steam协议启动
		if enable_fix_steam:
			# 使用联机补丁模式启动，然后通过Steam
			_launch_multiplayer_with_fix_steam()
			return true
		else:
			# 直接通过Steam启动：先复制模组再应用覆盖顺序
			if game_path.is_empty():
				show_notification(translate("game_path_not_set"), false)
				return false
			_apply_enabled_mods_to_game()
			if not apply_override_order_before_launch():
				pass
			return _launch_via_steam("dialog")
	else:
		# 直接运行游戏程序（不使用Steam）
		if enable_fix_steam:
			# 使用联机补丁模式启动
			_launch_multiplayer_with_fix()
			return true
		else:
			# 直接运行游戏
			return _launch_via_steam("")

# 联机模式启动（带补丁）- 之后通过Steam
func _launch_multiplayer_with_fix_steam() -> void:
	if game_path.is_empty():
		show_notification(translate("game_path_not_set"), false)
		return

	# 1. 切换到"联机模组"标签（会应用该标签的模组）
	print("[_launch_multiplayer_with_fix_steam] current_tag BEFORE switch: ", current_tag)
	print("[_launch_multiplayer_with_fix_steam] Calling _on_tag_selected...")
	_on_tag_selected("联机模组")
	print("[_launch_multiplayer_with_fix_steam] current_tag AFTER switch: ", current_tag)

	# 2. 应用联机补丁文件
	if not _apply_fix_steam_patch():
		show_notification(translate("launch_failed"), false)
		return

	# 3. 确保启用状态的模组已复制到游戏 mods 目录
	_apply_enabled_mods_to_game()

	# 4. 应用模组覆盖顺序（在模组已复制后，备份正确的 manifest）
	if not apply_override_order_before_launch():
		pass

	# 5. 通过Steam启动游戏
	print("[_launch_multiplayer_with_fix_steam] Launching via Steam...")
	_launch_via_steam("dialog")


# 联机模式启动（带补丁）
func _launch_multiplayer_with_fix() -> void:
	if game_path.is_empty():
		show_notification(translate("game_path_not_set"), false)
		return

	# 1. 切换到"联机模组"标签（会应用该标签的模组）
	print("[_launch_multiplayer_with_fix] current_tag BEFORE switch: ", current_tag)
	print("[_launch_multiplayer_with_fix] Calling _on_tag_selected...")
	_on_tag_selected("联机模组")
	print("[_launch_multiplayer_with_fix] current_tag AFTER switch: ", current_tag)

	# 2. 应用联机补丁文件
	if not _apply_fix_steam_patch():
		show_notification(translate("launch_failed"), false)
		return

	# 3. 启动游戏 - 使用与模组模式相同的启动方式
	var exe_path = _find_game_executable()
	if exe_path.is_empty():
		_restore_fix_steam_backup()
		show_notification(translate("game_exe_not_found"), false)
		return

	# 确保启用状态的模组已复制到游戏 mods 目录（与模组模式一致）
	_apply_enabled_mods_to_game()

	# 应用模组覆盖顺序（在模组已复制后，备份正确的 manifest）
	if not apply_override_order_before_launch():
		pass

	# 使用 create_process 启动（与模组模式一致）
	print("[_launch_multiplayer_with_fix] Starting game via create_process: ", exe_path)
	var process = OS.create_process(exe_path, [])
	print("[_launch_multiplayer_with_fix] process_id: ", process)

	if process == -1:
		_restore_fix_steam_backup()
		show_notification(translate("launch_failed"), false)
		return

	# 等待游戏进程结束（使用轮询）
	while OS.is_process_running(process):
		await get_tree().create_timer(1.0).timeout

	print("[_launch_multiplayer_with_fix] Game process finished")

	# 4. 游戏结束后恢复备份
	_restore_fix_steam_backup()
	# 5. 恢复模组覆盖顺序 manifest
	restore_manifests_after_exit()


# 应用联机补丁文件（使用.bak备份方式）
func _apply_fix_steam_patch() -> bool:
	# 使用 fix_steam_path 配置
	if fix_steam_path.is_empty():
		fix_steam_path = config.get_value("paths", "fix_steam_path", "")

	print("[_apply_fix_steam_patch] fix_steam_path: ", fix_steam_path)
	print("[_apply_fix_steam_patch] game_path: ", game_path)

	if fix_steam_path.is_empty():
		print("[_apply_fix_steam_patch] fix_steam_path is empty!")
		return false

	if not DirAccess.dir_exists_absolute(fix_steam_path):
		print("[_apply_fix_steam_patch] fix_steam directory not found: ", fix_steam_path)
		return false

	# 遍历 fix_steam_path 目录下的所有文件
	var dir = DirAccess.open(fix_steam_path)
	if dir == null:
		print("[_apply_fix_steam_patch] Failed to open fix_steam directory")
		return false

	dir.list_dir_begin()
	var file_name = dir.get_next()
	var copied_files = []
	while file_name != "":
		if file_name != "." and file_name != "..":
			var source_path = fix_steam_path.path_join(file_name)
			var dest_path = game_path.path_join(file_name)
			print("[_apply_fix_steam_patch] Processing: ", file_name)
			print("[_apply_fix_steam_patch] source: ", source_path)

			# 特殊处理 data_sts2_windows_x86_64 目录：只备份并复制 steam_api64.dll
			if file_name == "data_sts2_windows_x86_64":
				var source_steam_api = source_path.path_join("steam_api64.dll")
				var dest_steam_api = dest_path.path_join("steam_api64.dll")
				var bak_steam_api = dest_steam_api + ".bak"
				# 只备份 steam_api64.dll（如果存在）
				if FileAccess.file_exists(dest_steam_api):
					if FileAccess.file_exists(bak_steam_api):
						DirAccess.remove_absolute(bak_steam_api)
					DirAccess.rename_absolute(dest_steam_api, bak_steam_api)
					print("[_apply_fix_steam_patch] Backed up steam_api64.dll to .bak")
				print("[_apply_fix_steam_patch] Special handling: copying only steam_api64.dll")
				_file_copy_safe(source_steam_api, dest_steam_api)
				copied_files.append(file_name)
				file_name = dir.get_next()
				continue

			# 普通文件/目录的备份处理
			var has_dest = FileAccess.file_exists(dest_path) or DirAccess.dir_exists_absolute(dest_path)
			if has_dest:
				var bak_path = dest_path + ".bak"
				if FileAccess.file_exists(bak_path):
					DirAccess.remove_absolute(bak_path)
				if DirAccess.dir_exists_absolute(dest_path):
					DirAccess.rename_absolute(dest_path, bak_path)
					print("[_apply_fix_steam_patch] Renamed directory to .bak: ", file_name)
				else:
					DirAccess.rename_absolute(dest_path, bak_path)
					print("[_apply_fix_steam_patch] Renamed file to .bak: ", file_name)

			# 复制文件或目录到游戏目录
			if DirAccess.dir_exists_absolute(source_path):
				if DirAccess.dir_exists_absolute(dest_path):
					_delete_directory_recursive(dest_path)
				FileUtils.copy_directory(source_path, dest_path)
				print("[_apply_fix_steam_patch]   Copied directory to game: ", file_name)
			else:
				_file_copy_safe(source_path, dest_path)
				print("[_apply_fix_steam_patch]   Copied file to game: ", file_name)

			copied_files.append(file_name)

		file_name = dir.get_next()
	dir.list_dir_end()

	print("[_apply_fix_steam_patch] Total files processed: ", copied_files.size())
	print("[_apply_fix_steam_patch] Applied fix_steam patch successfully")
	return true


# 恢复联机补丁备份（使用.bak方式）
func _restore_fix_steam_backup() -> bool:
	# 使用 fix_steam_path 配置
	if fix_steam_path.is_empty():
		fix_steam_path = config.get_value("paths", "fix_steam_path", "")

	print("[_restore_fix_steam_backup] fix_steam_path: ", fix_steam_path)
	print("[_restore_fix_steam_backup] game_path: ", game_path)

	if fix_steam_path.is_empty():
		print("[_restore_fix_steam_backup] fix_steam_path is empty!")
		return false

	if not DirAccess.dir_exists_absolute(fix_steam_path):
		print("[_restore_fix_steam_backup] fix_steam directory not found: ", fix_steam_path)
		return false

	# 遍历 fix_steam 目录，获取需要恢复的文件列表
	var dir = DirAccess.open(fix_steam_path)
	if dir == null:
		print("[_restore_fix_steam_backup] Failed to open fix_steam directory")
		return false

	var files_to_restore = []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			files_to_restore.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# 遍历文件列表，恢复每个文件
	for restore_file in files_to_restore:
		var dest_path = game_path.path_join(restore_file)
		var bak_path = dest_path + ".bak"

		# 特殊处理 data_sts2_windows_x86_64 目录：只恢复 steam_api64.dll
		if restore_file == "data_sts2_windows_x86_64":
			var dest_steam_api = dest_path.path_join("steam_api64.dll")
			var bak_steam_api = dest_steam_api + ".bak"
			# 删除注入的补丁
			if FileAccess.file_exists(dest_steam_api):
				DirAccess.remove_absolute(dest_steam_api)
				print("[_restore_fix_steam_backup] Deleted injected steam_api64.dll")
			# 恢复 .bak 文件
			if FileAccess.file_exists(bak_steam_api):
				DirAccess.rename_absolute(bak_steam_api, dest_steam_api)
				print("[_restore_fix_steam_backup] Restored steam_api64.dll from .bak")
			continue

		# 删除注入的补丁文件/目录（普通文件和目录正常处理）
		if DirAccess.dir_exists_absolute(dest_path):
			_delete_directory_recursive(dest_path)
			print("[_restore_fix_steam_backup] Deleted injected directory: ", restore_file)
		elif FileAccess.file_exists(dest_path):
			DirAccess.remove_absolute(dest_path)
			print("[_restore_fix_steam_backup] Deleted injected file: ", restore_file)

		# 恢复 .bak 文件
		if FileAccess.file_exists(bak_path):
			DirAccess.rename_absolute(bak_path, dest_path)
			print("[_restore_fix_steam_backup] Restored from .bak: ", restore_file)
		elif DirAccess.dir_exists_absolute(bak_path + ".bak"):
			# 处理目录情况
			var dir_bak_path = bak_path
			DirAccess.rename_absolute(dir_bak_path, dest_path)
			print("[_restore_fix_steam_backup] Restored directory from .bak: ", restore_file)

	print("[_restore_fix_steam_backup] Backup restored successfully")

	show_notification(translate("fix_steam_restored"), true)
	return true

# 检测并修复 .bak 文件
func _check_and_fix_bak_files() -> int:
	print("[_check_and_fix_bak_files] Checking for .bak files in game directory...")

	if game_path.is_empty():
		print("[_check_and_fix_bak_files] game_path is empty, skipping")
		return 0

	if not DirAccess.dir_exists_absolute(game_path):
		print("[_check_and_fix_bak_files] game_path does not exist: ", game_path)
		return 0

	var fixed_count = 0
	var bak_files = _find_all_bak_files(game_path)
	print("[_check_and_fix_bak_files] Found .bak files: ", bak_files.size())

	for bak_path in bak_files:
		var original_path = bak_path.substr(0, bak_path.length() - 4) # 去掉 .bak 后缀
		var file_name = bak_path.get_file()
		var original_file_name = file_name.substr(0, file_name.length() - 4)

		print("[_check_and_fix_bak_files] Processing: ", file_name)
		print("[_check_and_fix_bak_files] original: ", original_path)

		# 检查原始文件是否存在（被补丁覆盖）
		var original_exists = FileAccess.file_exists(original_path) or DirAccess.dir_exists_absolute(original_path)

		if original_exists:
			# 删除被补丁覆盖的版本
			if DirAccess.dir_exists_absolute(original_path):
				_delete_directory_recursive(original_path)
				print("[_check_and_fix_bak_files] Deleted overwritten directory")
			else:
				DirAccess.remove_absolute(original_path)
				print("[_check_and_fix_bak_files] Deleted overwritten file")

			# 将 .bak 重命名为原始文件名
			var dir = bak_path.get_base_dir()
			var original_full_path = dir.path_join(original_file_name)
			DirAccess.rename_absolute(bak_path, original_full_path)
			print("[_check_and_fix_bak_files] Restored .bak to original: ", original_file_name)

			fixed_count += 1

	print("[_check_and_fix_bak_files] Fixed count: ", fixed_count)
	return fixed_count

# 递归查找所有 .bak 文件
func _find_all_bak_files(dir_path: String) -> Array:
	var result = []
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return result

	dir.list_dir_begin()
	var item = dir.get_next()
	while item != "":
		if item != "." and item != "..":
			var full_path = dir_path.path_join(item)
			if item.ends_with(".bak"):
				result.append(full_path)
			elif DirAccess.dir_exists_absolute(full_path):
				# 递归搜索子目录
				var sub_results = _find_all_bak_files(full_path)
				result.append_array(sub_results)
		item = dir.get_next()
	dir.list_dir_end()

	return result


# 直接启动游戏（等待进程结束）
func _launch_game_direct() -> bool:
	print("[_launch_game_direct] game_path: ", game_path)
	# 找到游戏可执行文件
	var exe_path = _find_game_executable()
	print("[_launch_game_direct] exe_path: ", exe_path)
	if exe_path.is_empty():
		show_notification(translate("game_exe_not_found"), false)
		return false

	# 确保启用状态的模组已复制到游戏 mods 目录
	_apply_enabled_mods_to_game()

	# 启动游戏进程 - 使用 create_process（类似直接双击）
	print("[_launch_game_direct] Starting game via create_process: ", exe_path)
	var process_id = OS.create_process(exe_path, [])
	print("[_launch_game_direct] process_id: ", process_id)

	if process_id == -1:
		print("[_launch_game_direct] create_process failed")
		show_notification(translate("launch_failed"), false)
		return false

	show_notification(translate("launching_game"), true)
	return true


# 安全复制文件（覆盖模式）
func _file_copy_safe(source: String, dest: String) -> bool:
	print("[_file_copy_safe] source: ", source, ", dest: ", dest)
	if not FileAccess.file_exists(source):
		print("[_file_copy_safe] source file does not exist!")
		return false

	# 确保目标目录存在
	var dest_dir = dest.get_base_dir()
	print("[_file_copy_safe] dest_dir: ", dest_dir)
	if not DirAccess.dir_exists_absolute(dest_dir):
		print("[_file_copy_safe] Creating dest_dir")
		DirAccess.make_dir_recursive_absolute(dest_dir)

	# 使用 FileAccess 复制
	var source_file = FileAccess.open(source, FileAccess.READ)
	if source_file == null:
		print("[_file_copy_safe] Failed to open source file")
		return false

	var dest_file = FileAccess.open(dest, FileAccess.WRITE)
	if dest_file == null:
		print("[_file_copy_safe] Failed to open dest file for writing")
		source_file.close()
		return false

	var buffer = source_file.get_buffer(source_file.get_length())
	dest_file.store_buffer(buffer)

	source_file.close()
	dest_file.close()
	print("[_file_copy_safe] SUCCESS")

	return true


# 将启用的模组复制到游戏 mods 目录
func _apply_enabled_mods_to_game() -> void:
	if game_path.is_empty():
		return

	var game_mods_dir = game_path.path_join("mods")

	# 确保游戏 mods 目录存在
	if not DirAccess.dir_exists_absolute(game_mods_dir):
		DirAccess.make_dir_recursive_absolute(game_mods_dir)

	# 遍历所有模组，将启用的模组复制到游戏 mods 目录
	for mod in mods:
		var mod_id = mod.get("id", "")
		if enabled_mods.has(mod_id) and enabled_mods[mod_id]:
			var mod_path = mod.get("path", "")
			if not mod_path.is_empty():
				ModUtils.enable_mod(mod, game_path)


# 通过Steam协议或直接运行启动游戏
func _launch_game_via_steam(option: String = "") -> bool:
	# 直接运行游戏程序
	if game_path.is_empty():
		show_notification(translate("game_path_not_set") if has_translation_key("game_path_not_set") else "请先设置游戏路径", false)
		return false

	# 查找游戏可执行文件
	var exe_path = _find_game_executable()
	if exe_path.is_empty():
		show_notification(translate("game_exe_not_found") if has_translation_key("game_exe_not_found") else "未找到游戏可执行文件", false)
		return false

	print("[Launch] Running game directly: ", exe_path)
	var error := OS.shell_open(exe_path)

	if error != OK:
		show_notification(translate("launch_failed") if has_translation_key("launch_failed") else "启动游戏失败", false)
		push_error("Failed to launch game: %s" % error)
		return false

	show_notification(translate("launching_game") if has_translation_key("launching_game") else "正在启动游戏...", true)
	return true


# 通过Steam协议启动游戏
func _launch_via_steam(option: String = "") -> bool:
	var steam_url := "steam://launch/%s" % STEAM_APP_ID
	if not option.is_empty():
		steam_url += "/%s" % option

	print("[Launch] Opening Steam URL: ", steam_url)
	var error := OS.shell_open(steam_url)

	if error != OK:
		show_notification(translate("launch_failed") if has_translation_key("launch_failed") else "启动游戏失败", false)
		push_error("Failed to launch game via Steam: %s" % error)
		return false

	show_notification(translate("launching_game") if has_translation_key("launching_game") else "正在启动游戏...", true)
	return true


# 查找游戏可执行文件
func _find_game_executable() -> String:
	if game_path.is_empty():
		return ""
	
	# 常见的游戏可执行文件名
	var exe_names = ["SlayTheSpire2.exe", "slaythespire2.exe", "Slay the Spire 2.exe"]
	
	for exe_name in exe_names:
		var full_path = game_path.path_join(exe_name)
		if FileAccess.file_exists(full_path):
			return full_path
	
	# 如果没找到，尝试查找任何.exe文件
	var dir = DirAccess.open(game_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".exe") and not file_name.contains("unins"):
				return game_path.path_join(file_name)
			file_name = dir.get_next()
	
	return ""


# 检查翻译键是否存在
func has_translation_key(key: String) -> bool:
	return translate(key) != key


# 当用户切换标签页时
var _current_tab_index: int = 0  # 当前标签页索引
var _settings_ui_initialized: bool = false  # 设置页面是否已初始化

func _on_tab_changed(tab_index: int) -> void:
	print("[_on_tab_changed] tab_index: ", tab_index)
	# 检查是否从设置标签页切换出去且有未保存的更改
	if _current_tab_index == 5 and tab_index != 5 and settings_dirty:
		# 显示未保存提示
		_show_unsaved_settings_warning(tab_index)
		return

	# 启用整合包时，禁止切换到模组页面
	if tab_index == 0 and not active_bundle.is_empty():
		show_notification(translate("bundle_active_tag_locked"), false)
		# 恢复原来的标签页
		tab_container.current_tab = _current_tab_index
		return

	_current_tab_index = tab_index

	# 切换到模组页面时刷新列表
	if tab_index == 0:
		load_mods()

	# 保存当前标签页索引到配置
	config.set_value("window", "current_tab", tab_index)
	config.save(config_path)

	# 首次切换到整合包标签时初始化UI
	if tab_index == 1 and not _bundle_ui_initialized:
		_bundle_ui_initialized = true
		_init_bundle_ui()

	# 首次切换到下载标签时初始化UI
	if tab_index == 4:
		_init_download_ui()

	# 设置tab (index 5)
	if tab_index == 5:  # Settings tab
		# 每次切换到设置标签时都初始化UI（确保节点可用）
		print("========== SETTINGS TAB SELECTED ==========")
		_init_settings_ui_if_needed()

	# 延迟初始化 Nexus 模组页面（用户首次切换到 Nexus 标签页时）
	if tab_index == 3 and not _nexus_initialized:
		_nexus_initialized = true
		_delayed_init_nexus()


# 恢复上次退出的标签页并初始化对应UI
func _restore_last_tab() -> void:
	# 从配置读取上次退出的标签页
	var saved_tab = config.get_value("window", "current_tab", 0)
	print("[_restore_last_tab] Restoring tab: ", saved_tab)

	# 获取TabContainer
	var tab_container = find_child_node(self, "TabContainer")
	if not tab_container:
		print("[_restore_last_tab] TabContainer not found")
		return

	# 如果启用了整合包，且上次退出时在模组页面（0），跳转到整合包页面（1）
	if not active_bundle.is_empty() and saved_tab == 0:
		saved_tab = 1

	# 确保标签页索引有效
	saved_tab = clamp(saved_tab, 0, tab_container.get_tab_count() - 1)

	# 初始化对应页面UI（模拟标签切换）
	if saved_tab == 0:
		# 模组页面 - 延迟加载已在 _ready 中调用
		pass
	elif saved_tab == 1:
		# 整合包页面
		if not _bundle_ui_initialized:
			_bundle_ui_initialized = true
			_init_bundle_ui()
	elif saved_tab == 2:
		# 存档页面 - 已在 _ready 中延迟加载
		pass
	elif saved_tab == 3:
		# Nexus模组页面
		if not _nexus_initialized:
			_nexus_initialized = true
			_delayed_init_nexus()
	elif saved_tab == 4:
		# 下载页面
		_init_download_ui()
	elif saved_tab == 5:
		# 设置页面
		if not _settings_ui_initialized:
			_settings_ui_initialized = true
			_init_settings_ui_if_needed()

	# 切换到对应标签页
	_current_tab_index = saved_tab
	tab_container.current_tab = saved_tab
	print("[_restore_last_tab] Tab restored to: ", saved_tab)


# 显示未保存设置警告
func _show_unsaved_settings_warning(target_tab: int) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = translate("warning")
	dialog.dialog_text = translate("settings_not_saved_warning")
	dialog.ok_button_text = translate("save_and_continue")
	dialog.cancel_button_text = translate("discard_changes")
	
	# 添加"返回设置"按钮
	var back_btn = dialog.add_button(translate("back_to_settings"), true)
	
	add_child(dialog)
	
	# 返回设置 - 关闭对话框，保持在设置标签
	back_btn.pressed.connect(func():
		dialog.queue_free()
		# 确保标签页选择器回到设置
		var tab_container = get_node_or_null("/root/Control/TabContainer")
		if tab_container:
			tab_container.current_tab = 4
			_current_tab_index = 4
	)

	# 取消（放弃更改）- 继续切换，重置dirty状态
	dialog.canceled.connect(func():
		dialog.queue_free()
		settings_dirty = false
		_current_tab_index = target_tab
		var tab_container = get_node_or_null("/root/Control/TabContainer")
		if tab_container:
			tab_container.current_tab = target_tab
		if target_tab == 4:
			_init_settings_ui_if_needed()
	)

	# 确认（保存并继续）- 保存设置后切换
	dialog.confirmed.connect(func():
		dialog.queue_free()
		_on_save_settings_pressed()
		settings_dirty = false
		_current_tab_index = target_tab
		var tab_container = get_node_or_null("/root/Control/TabContainer")
		if tab_container:
			tab_container.current_tab = target_tab
		if target_tab == 4:
			_init_settings_ui_if_needed()
	)
	
	dialog.popup_centered(Vector2(400, 180))


# 启动时自动检测路径
func _auto_detect_paths_on_startup() -> void:
	var detected_game_path = false
	var detected_save_path = false
	var message_parts = []

	# 检测游戏路径
	if game_path.is_empty():
		var detected = _detect_game_path()
		if not detected.is_empty():
			game_path = detected
			config.set_value("paths", "game_path", game_path)
			detected_game_path = true
			message_parts.append(translate("game_path") + ": " + game_path)

	# 检测存档路径
	if save_path.is_empty():
		var detected = _detect_save_path()
		if not detected.is_empty():
			save_path = detected
			config.set_value("paths", "save_path", save_path)
			detected_save_path = true
			message_parts.append(translate("save_path") + ": " + save_path)

	# 如果检测到任何路径，保存配置
	if detected_game_path or detected_save_path:
		config.save(config_path)

	# 更新设置UI中的路径显示
	_update_settings_path_display()

	# 显示检测结果
	if detected_game_path or detected_save_path:
		var msg = translate("path_detected") + ":\n"
		msg += "\n".join(message_parts)
		# 延迟显示，确保UI已初始化完成
		await get_tree().create_timer(0.5).timeout
		show_notification(msg, true)
	elif game_path.is_empty() or save_path.is_empty():
		# 如果有路径未检测到，提示用户手动设置
		await get_tree().create_timer(0.5).timeout
		var msg = translate("path_detection_failed")
		if game_path.is_empty():
			msg += "\n- " + translate("game_path")
		if save_path.is_empty():
			msg += "\n- " + translate("save_path")
		msg += "\n" + translate("select_game_path")
		show_notification(msg, false)


# 延迟初始化设置UI（仅初始化一次）

func _init_settings_ui_if_needed() -> void:
	# 设置UI初始化状态已在 _on_tab_changed 中设置

	print("[_init_settings_ui_if_needed] Starting initialization...")

	# 创建独立的 Nexus API 实例（如果还没有）
	if not nexus_api:
		nexus_api = NexusAPI.new()
		# 从配置加载 API Key
		var saved_api_key = config.get_value("nexus", "api_key", "")
		if not saved_api_key.is_empty():
			nexus_api.set_api_key(saved_api_key)
			print("[_init_settings_ui_if_needed] Loaded API key from config")
		print("[_init_settings_ui_if_needed] Created standalone NexusAPI instance")

	# 等待一帧确保UI完全准备好
	await get_tree().process_frame

	# 使用完整路径获取节点
	print("[_init_settings_ui_if_needed] Getting settings_tab...")
	var settings_tab = get_node_or_null("/root/Control/TabContainer/SettingsTab")
	print("[_init_settings_ui_if_needed] settings_tab: ", settings_tab)
	print("[_init_settings_ui_if_needed] settings_tab visible: ", settings_tab.visible if settings_tab else "N/A")
	if settings_tab:
		print("[_init_settings_ui_if_needed] settings_tab is valid, proceeding...")
		# 获取节点引用 - 使用正确的路径
		game_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/GamePathRow/GamePathEdit")
		save_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/SavePathRow/SavePathEdit")
		game_path_browse_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/GamePathRow/GamePathBrowseBtn")
		game_path_detect_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/GamePathRow/GamePathDetectBtn")
		save_path_browse_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/SavePathRow/SavePathBrowseBtn")
		save_path_detect_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/SavePathRow/SavePathDetectBtn")
		language_option = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/LanguageSection/LanguageOption")
		dpi_scale_slider = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/DpiScaleSection/DpiScaleHBox/DpiScaleSlider")
		dpi_scale_value_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/DpiScaleSection/DpiScaleHBox/DpiScaleValueLabel")
		auto_backup_check = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/BackupSection/AutoBackupCheck")
		auto_backup_on_startup_check = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/BackupSection/AutoBackupOnStartupCheck")
		auto_backup_max_count_spin = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/BackupSection/AutoBackupMaxCountHBox/AutoBackupMaxCountSpinBox")
		save_settings_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/SaveSettingsBtn")
		print("[_init_settings_ui_if_needed] save_settings_btn: ", save_settings_btn)
		temp_mods_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/TempModsPathRow/TempModsPathEdit")
		temp_mods_path_browse_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/TempModsPathRow/TempModsPathBrowseBtn")
		backup_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/BackupPathRow/BackupPathEdit")
		backup_path_browse_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/BackupPathRow/BackupPathBrowseBtn")

		# 加载已保存的路径配置 - 先重新加载config确保最新
		config.load(config_path)
		game_path = config.get_value("paths", "game_path", "")
		save_path = config.get_value("paths", "save_path", "")

		# 同步版本
		var project_version = ProjectSettings.get_setting("config/version", "v0.0.0")
		if project_version == "v0.0.0" or project_version.is_empty():
			var godot_file = FileAccess.open("res://project.godot", FileAccess.READ)
			if godot_file:
				while not godot_file.eof_reached():
					var line = godot_file.get_line()
					if line.begins_with("config/version="):
						project_version = line.substr(line.find("=") + 1).strip_edges().replace("\"", "")
						break
				godot_file.close()
		config.set_value("current_version", "version", project_version)
		config.save(config_path)

		print("[_init_settings_ui_if_needed] Synced version: ", project_version)
		# temp_mods_path 和 backup_path 是动态属性，直接使用

		print("[_init_settings_ui_if_needed] Reloaded config - game_path: '", game_path, "', save_path: '", save_path, "'")
		print("[_init_settings_ui_if_needed] game_path_edit: ", game_path_edit)

		# 设置路径输入框
		if game_path_edit:
			game_path_edit.text = ""  # 先清空
			game_path_edit.text = game_path  # 再设置值
		if save_path_edit:
			save_path_edit.text = ""  # 先清空
			save_path_edit.text = save_path  # 再设置值
		if temp_mods_path_edit:
			temp_mods_path_edit.text = temp_mods_path
		if backup_path_edit:
			backup_path_edit.text = backup_path

		# 设置路径标签文本（从翻译加载）
		var game_path_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/GamePathLabel")
		var save_path_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/SavePathLabel")
		var language_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/LanguageSection/LanguageLabel")
		var game_path_browse_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/GamePathRow/GamePathBrowseBtn")
		var game_path_detect_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/GamePathRow/GamePathDetectBtn")
		var save_path_browse_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/SavePathRow/SavePathBrowseBtn")
		var save_path_detect_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/SavePathRow/SavePathDetectBtn")

		if game_path_label:
			game_path_label.text = translate("game_path")
		if save_path_label:
			save_path_label.text = translate("save_path")
		if language_label:
			language_label.text = translate("language")
		if game_path_browse_btn:
			game_path_browse_btn.text = translate("browse")
		if game_path_detect_btn:
			game_path_detect_btn.text = translate("auto_detect")
		if save_path_browse_btn:
			save_path_browse_btn.text = translate("browse")
		if save_path_detect_btn:
			save_path_detect_btn.text = translate("auto_detect")

		# 设置语言选项
		if language_option:
			language_option.clear()
			language_option.add_item("中文")
			language_option.add_item("English")
			language_option.selected = 0 if current_language == "zh_CN" else 1

		# 设置 DPI 缩放滑块
		if dpi_scale_slider:
			print("[_init_settings_ui_if_needed] dpi_scale_slider found, setting up...")
			dpi_scale_slider.min_value = DPI_SCALE_MIN
			dpi_scale_slider.max_value = DPI_SCALE_MAX
			dpi_scale_slider.step = DPI_SCALE_STEP
			dpi_scale_slider.value = dpi_scale
			print("[_init_settings_ui_if_needed] dpi_scale_slider value set to: ", dpi_scale)
		else:
			print("[_init_settings_ui_if_needed] dpi_scale_slider is null!")
		if dpi_scale_value_label:
			dpi_scale_value_label.text = str(int(dpi_scale * 100)) + "%"
			print("[_init_settings_ui_if_needed] dpi_scale_value_label found, text: ", dpi_scale_value_label.text)
		else:
			print("[_init_settings_ui_if_needed] dpi_scale_value_label is null!")

		# 设置自动备份选项
		if auto_backup_check:
			auto_backup_check.button_pressed = config.get_value("settings", "auto_backup", true)
		if auto_backup_on_startup_check:
			auto_backup_on_startup_check.button_pressed = config.get_value("settings", "auto_backup_on_startup", true)
		if auto_backup_max_count_spin:
			auto_backup_max_count_spin.value = config.get_value("settings", "auto_backup_max_count", 5)

		# 创建启动设置Section（如果不存在）
		var settings_vbox = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox")
		var save_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/SaveSettingsBtn")
		if settings_vbox and save_btn:
			# 检查LaunchSection是否已存在
			var existing_launch_section = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/LaunchSection")
			if not existing_launch_section:
				# 创建启动设置Section
				var launch_section = VBoxContainer.new()
				launch_section.name = "LaunchSection"
				# 插入到SaveSettingsBtn之前
				var save_idx = save_btn.get_index()
				settings_vbox.add_child(launch_section)
				settings_vbox.move_child(launch_section, save_idx)
				
				# 创建标签
				var launch_label = Label.new()
				launch_label.text = translate("launch_settings")
				launch_section.add_child(launch_label)
				
				# 创建正版启动复选框
				launch_via_steam_check = CheckBox.new()
				launch_via_steam_check.name = "LaunchViaSteamCheck"
				launch_via_steam_check.text = translate("launch_via_steam")
				launch_via_steam_check.button_pressed = config.get_value("settings", "launch_via_steam", true)
				launch_section.add_child(launch_via_steam_check)

				# 创建联机补丁路径配置行
				var fix_steam_path_row = HBoxContainer.new()
				fix_steam_path_row.name = "FixSteamPathRow"
				launch_section.add_child(fix_steam_path_row)

				var fix_steam_path_label = Label.new()
				fix_steam_path_label.name = "FixSteamPathLabel"
				fix_steam_path_label.text = translate("fix_steam_path")
				fix_steam_path_label.custom_minimum_size.x = 120
				fix_steam_path_row.add_child(fix_steam_path_label)

				fix_steam_path_edit = LineEdit.new()
				fix_steam_path_edit.name = "FixSteamPathEdit"
				fix_steam_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				fix_steam_path_edit.placeholder_text = translate("fix_steam_path_placeholder")
				fix_steam_path_edit.text = config.get_value("paths", "fix_steam_path", "")
				fix_steam_path_row.add_child(fix_steam_path_edit)

				fix_steam_path_browse_btn = Button.new()
				fix_steam_path_browse_btn.name = "FixSteamPathBrowseBtn"
				fix_steam_path_browse_btn.text = translate("browse")
				fix_steam_path_browse_btn.pressed.connect(_on_fix_steam_path_browse)
				fix_steam_path_row.add_child(fix_steam_path_browse_btn)

				fix_steam_path_detect_btn = Button.new()
				fix_steam_path_detect_btn.name = "FixSteamPathDetectBtn"
				fix_steam_path_detect_btn.text = translate("auto_detect")
				fix_steam_path_detect_btn.pressed.connect(_on_fix_steam_path_detect)
				fix_steam_path_row.add_child(fix_steam_path_detect_btn)

				# 创建联机补丁复选框
				enable_fix_steam_check = CheckBox.new()
				enable_fix_steam_check.name = "EnableFixSteamCheck"
				enable_fix_steam_check.text = translate("enable_fix_steam")
				enable_fix_steam_check.tooltip_text = translate("enable_fix_steam_desc")
				enable_fix_steam_check.button_pressed = config.get_value("settings", "enable_fix_steam", false)
				launch_section.add_child(enable_fix_steam_check)
				# 更新复选框状态（根据路径是否设置）
				_update_fix_steam_checkbox_state()
			else:
				# 如果已存在，获取复选框引用
				launch_via_steam_check = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/LaunchSection/LaunchViaSteamCheck")
				enable_fix_steam_check = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/LaunchSection/EnableFixSteamCheck")
				fix_steam_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/LaunchSection/FixSteamPathRow/FixSteamPathEdit")
				fix_steam_path_browse_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/LaunchSection/FixSteamPathRow/FixSteamPathBrowseBtn")
				fix_steam_path_detect_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/LaunchSection/FixSteamPathRow/FixSteamPathDetectBtn")
				if launch_via_steam_check:
					launch_via_steam_check.button_pressed = config.get_value("settings", "launch_via_steam", true)
				if enable_fix_steam_check:
					enable_fix_steam_check.button_pressed = config.get_value("settings", "enable_fix_steam", false)
				if fix_steam_path_edit:
					fix_steam_path_edit.text_changed.connect(_on_fix_steam_path_changed)
					fix_steam_path = config.get_value("paths", "fix_steam_path", "")
					_update_fix_steam_checkbox_state()

				# 创建云端存档路径Section（如果不存在）
			var existing_cloud_section = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/CloudSaveSection")
			if not existing_cloud_section:
				var cloud_section = VBoxContainer.new()
				cloud_section.name = "CloudSaveSection"
				# 插入到SaveSettingsBtn之前
				var save_idx = save_btn.get_index()
				settings_vbox.add_child(cloud_section)
				settings_vbox.move_child(cloud_section, save_idx)

				# 创建标签
				var cloud_label = Label.new()
				cloud_label.name = "CloudSaveLabel"
				cloud_label.text = translate("cloud_save_paths")
				cloud_section.add_child(cloud_label)

				# GSE云路径（学习版）
				var gse_row = HBoxContainer.new()
				gse_row.name = "GSERow"
				cloud_section.add_child(gse_row)

				var gse_label = Label.new()
				gse_label.text = "GSE: "
				gse_label.custom_minimum_size.x = 120
				gse_row.add_child(gse_label)

				gse_cloud_path_edit = LineEdit.new()
				gse_cloud_path_edit.name = "GSECloudPathEdit"
				gse_cloud_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				gse_cloud_path_edit.placeholder_text = "自动检测或手动输入"
				gse_cloud_path_edit.text = gse_cloud_path
				gse_row.add_child(gse_cloud_path_edit)

				var gse_browse_btn = Button.new()
				gse_browse_btn.name = "GSEBrowseBtn"
				gse_browse_btn.text = translate("browse")
				gse_browse_btn.pressed.connect(_on_gse_cloud_browse)
				gse_row.add_child(gse_browse_btn)

				gse_cloud_detect_btn = Button.new()
				gse_cloud_detect_btn.name = "GSEDetectBtn"
				gse_cloud_detect_btn.text = translate("auto_detect")
				gse_cloud_detect_btn.pressed.connect(_on_gse_cloud_detect)
				gse_row.add_child(gse_cloud_detect_btn)

				# Steam云路径（正版）
				var steam_row = HBoxContainer.new()
				steam_row.name = "SteamCloudRow"
				cloud_section.add_child(steam_row)

				var steam_label = Label.new()
				steam_label.text = "Steam: "
				steam_label.custom_minimum_size.x = 120
				steam_row.add_child(steam_label)

				steam_cloud_path_edit = LineEdit.new()
				steam_cloud_path_edit.name = "SteamCloudPathEdit"
				steam_cloud_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				steam_cloud_path_edit.placeholder_text = "自动检测或手动输入"
				steam_cloud_path_edit.text = steam_cloud_path
				steam_row.add_child(steam_cloud_path_edit)

				var steam_browse_btn = Button.new()
				steam_browse_btn.name = "SteamCloudBrowseBtn"
				steam_browse_btn.text = translate("browse")
				steam_browse_btn.pressed.connect(_on_steam_cloud_browse)
				steam_row.add_child(steam_browse_btn)

				steam_cloud_detect_btn = Button.new()
				steam_cloud_detect_btn.name = "SteamCloudDetectBtn"
				steam_cloud_detect_btn.text = translate("auto_detect")
				steam_cloud_detect_btn.pressed.connect(_on_steam_cloud_detect)
				steam_row.add_child(steam_cloud_detect_btn)
			else:
				# 如果已存在，获取输入框引用
				gse_cloud_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/CloudSaveSection/GSERow/GSECloudPathEdit")
				steam_cloud_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/CloudSaveSection/SteamCloudRow/SteamCloudPathEdit")
				gse_cloud_detect_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/CloudSaveSection/GSERow/GSEDetectBtn")
				steam_cloud_detect_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/CloudSaveSection/SteamCloudRow/SteamCloudDetectBtn")
				if gse_cloud_path_edit:
					gse_cloud_path_edit.text = gse_cloud_path
				if steam_cloud_path_edit:
					steam_cloud_path_edit.text = steam_cloud_path

		# 连接按钮信号
		if game_path_browse_btn:
			game_path_browse_btn.pressed.connect(_on_game_path_browse)
		if game_path_detect_btn:
			game_path_detect_btn.pressed.connect(_on_game_path_detect)
		if save_path_browse_btn:
			save_path_browse_btn.pressed.connect(_on_save_path_browse)
		if save_path_detect_btn:
			save_path_detect_btn.pressed.connect(_on_save_path_detect)
		if save_settings_btn:
			save_settings_btn.pressed.connect(_on_save_settings_pressed)
		
		# 将保存按钮移动到最下方
		if save_settings_btn and settings_vbox:
			var children = settings_vbox.get_children()
			var last_child = children[children.size() - 1]
			if save_settings_btn != last_child:
				settings_vbox.move_child(save_settings_btn, children.size() - 1)
		
		# 为设置控件添加值变化监听
		_connect_settings_change_signals()

		# 在保存设置按钮旁边添加清除所有备份按钮（检查是否已存在）
		_add_clear_backups_button()

		# 加载并显示模组字段配置（复选框形式）
		_add_mod_fields_ui()
		_add_mod_organization_section()

		# 添加教程按钮（如果不存在）
		var settings_vbox_for_tutorial = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox")
		var tutorial_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/TutorialBtn")
		var save_settings_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/SaveSettingsBtn")
		print("[_init_settings_ui_if_needed] Adding tutorial button - settings_vbox: ", settings_vbox_for_tutorial, ", existing_btn: ", tutorial_btn)
		if not tutorial_btn and settings_vbox_for_tutorial:
			tutorial_btn = Button.new()
			tutorial_btn.name = "TutorialBtn"
			tutorial_btn.text = translate("tutorial_button")
			tutorial_btn.pressed.connect(_show_tutorial_from_settings)

			# 添加到设置页面底部（保存按钮之后）
			if save_settings_btn:
				var save_idx = save_settings_btn.get_index()
				settings_vbox_for_tutorial.add_child(tutorial_btn)
				settings_vbox_for_tutorial.move_child(tutorial_btn, save_idx + 1)
			else:
				settings_vbox_for_tutorial.add_child(tutorial_btn)
			print("[_init_settings_ui_if_needed] Added tutorial button successfully")
		elif tutorial_btn:
			# 已存在的按钮也需要设置翻译
			tutorial_btn.text = translate("tutorial_button")
			print("[_init_settings_ui_if_needed] Tutorial button already exists, set translate")
		elif not settings_vbox_for_tutorial:
			print("[_init_settings_ui_if_needed] ERROR: settings_vbox is null!")

		# 添加检查更新按钮（如果不存在）
		var settings_vbox_for_update = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox")
		var update_check_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/UpdateCheckBtn")
		if not update_check_btn and settings_vbox_for_update:
			update_check_btn = Button.new()
			update_check_btn.name = "UpdateCheckBtn"
			update_check_btn.text = translate("check_update")
			update_check_btn.pressed.connect(_on_check_update_pressed)

			# 添加到设置页面底部（教程按钮之后）
			if tutorial_btn:
				var tutorial_idx = tutorial_btn.get_index()
				settings_vbox_for_update.add_child(update_check_btn)
				settings_vbox_for_update.move_child(update_check_btn, tutorial_idx + 1)
			else:
				settings_vbox_for_update.add_child(update_check_btn)
			print("[_init_settings_ui_if_needed] Added update check button")

			# 添加版本显示标签
			var version_label = Label.new()
			version_label.name = "VersionLabel"
			# 直接从 version.json 读取版本
			var current_ver = _read_version_from_file()
			print("[_init_settings_ui_if_needed] Version label - reading version: '", current_ver, "'")
			version_label.text = translate("current_version") + ": " + current_ver
			settings_vbox_for_update.add_child(version_label)
			if update_check_btn:
				settings_vbox_for_update.move_child(version_label, update_check_btn.get_index() + 1)

			# 添加导出调试信息按钮
			var export_debug_btn = Button.new()
			export_debug_btn.name = "ExportDebugBtn"
			export_debug_btn.text = translate("export_debug_info")
			export_debug_btn.pressed.connect(_on_export_debug_info_pressed)
			settings_vbox_for_update.add_child(export_debug_btn)
			if version_label:
				settings_vbox_for_update.move_child(export_debug_btn, version_label.get_index() + 1)

		# 等待布局完成后再打印调试信息
		await get_tree().process_frame
		await get_tree().process_frame
		print("[_init_settings_ui_if_needed] Waiting for layout...")

		# 获取 Nexus API 相关节点并连接信号（必须在函数内部执行）
		nexus_api_key_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusAPIKeyRow/NexusAPIKeyEdit")
		nexus_validate_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusAPIKeyRow/NexusValidateBtn")
		nexus_status_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusStatusLabel")
		print("[_init_settings_ui_if_needed] Nexus API nodes - edit: ", nexus_api_key_edit, ", btn: ", nexus_validate_btn)

		# 检查翻译是否正确加载
		print("[_init_settings_ui_if_needed] Checking translations:")
		print("  - locale_data keys count: ", locale_data.size())
		print("  - nexus_status_unverified in locale_data: ", locale_data.has("nexus_status_unverified"))
		if locale_data.has("nexus_status_unverified"):
			print("  - nexus_status_unverified value: '", locale_data.get("nexus_status_unverified"), "'")

		# 重新加载 config 确保获取最新值
		config.load(config_path)
		var saved_nexus_api_key = config.get_value("nexus", "api_key", "")
		var saved_validated = config.get_value("nexus", "validated", false)
		var saved_username = config.get_value("nexus", "username", "")
		print("[_init_settings_ui_if_needed] Config values - api_key: '", saved_nexus_api_key.substr(0, 10) if saved_nexus_api_key else "", "...', validated: ", saved_validated, ", username: '", saved_username, "'")

		# 加载已保存的 API Key
		if nexus_api_key_edit and not saved_nexus_api_key.is_empty():
			nexus_api_key_edit.text = saved_nexus_api_key
			print("[_init_settings_ui_if_needed] Set API key to input field")

		# 加载并显示已保存的验证状态
		var is_validated = saved_validated
		var is_premium = config.get_value("nexus", "is_premium", false)
		if is_validated and not saved_username.is_empty():
			var status_text = "已验证: %s" % saved_username
			if is_premium:
				status_text += " (Premium)"
			if nexus_status_label:
				nexus_status_label.text = status_text
			print("[_init_settings_ui_if_needed] Loaded saved validation status: ", status_text)
		elif not saved_nexus_api_key.is_empty():
			# 有API Key但未验证
			if nexus_status_label:
				nexus_status_label.text = translate("nexus_api_key_saved")
				print("[_init_settings_ui_if_needed] Set nexus_api_key_saved: ", translate("nexus_api_key_saved"))
		else:
			# 既没有保存的API Key也没有验证，显示未验证状态
			if nexus_status_label:
				nexus_status_label.text = translate("nexus_status_unverified")
				print("[_init_settings_ui_if_needed] Set nexus_status_unverified: ", translate("nexus_status_unverified"))

		# 连接验证按钮信号（避免重复连接）
		if nexus_validate_btn:
			if not nexus_validate_btn.pressed.is_connected(_on_nexus_validate_pressed):
				nexus_validate_btn.pressed.connect(_on_nexus_validate_pressed)

	# 创建本地服务器端口设置Section（在 if 块外面，确保一定执行）
	print("[_init_settings_ui_if_needed] About to call _add_server_port_section()")
	_add_server_port_section()
	print("[_init_settings_ui_if_needed] After _add_server_port_section()")

	print("[_init_settings_ui_if_needed] Settings UI initialized!")


# 添加清除备份按钮
func _add_clear_backups_button() -> void:
	print("[_add_clear_backups_button] Called")
	print("  - save_settings_btn: ", save_settings_btn)
	print("  - backup_path: '", backup_path, "'")
	print("  - get_base_path(): '", get_base_path(), "'")

	if not save_settings_btn:
		print("[_add_clear_backups_button] ERROR: save_settings_btn is null!")
		return

	# 先检查新的位置（BackupSection内）
	var existing_clear_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/BackupSection/ClearBackupsBtn")
	# 兼容旧位置（如果在新位置没找到）
	if not existing_clear_btn:
		existing_clear_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ClearBackupsBtn")
	print("  - existing_clear_btn: ", existing_clear_btn)
	if existing_clear_btn:
		print("[_add_clear_backups_button] Already exists, setting translation")
		existing_clear_btn.text = translate("clear_all_backups")
		return  # 已存在，设置翻译后退出

	print("[_add_clear_backups_button] Creating button...")

	var clear_backups_btn = Button.new()
	clear_backups_btn.name = "ClearBackupsBtn"
	clear_backups_btn.text = translate("clear_all_backups")
	clear_backups_btn.tooltip_text = "删除所有存档备份"
	clear_backups_btn.custom_minimum_size = Vector2(120, 30)

	# 设置布局属性
	clear_backups_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# 获取保存按钮的父容器
	var parent = save_settings_btn.get_parent()
	print("  - parent: ", parent, " (type: ", typeof(parent), ")")

	if parent and parent is VBoxContainer:
		parent.add_child(clear_backups_btn)
		parent.move_child(clear_backups_btn, save_settings_btn.get_index() + 1)
		clear_backups_btn.pressed.connect(_on_clear_all_backups_pressed)
		print("[_add_clear_backups_button] Button added successfully")
		print("[DEBUG] clear_backups_btn position: ", clear_backups_btn.position)

		# 滚动到底部以显示新按钮
		await get_tree().process_frame
		var scroll_cont = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll")
		if scroll_cont:
			scroll_cont.scroll_vertical = 2000  # 滚动到一个较大的位置确保到底部
			print("[_add_clear_backups_button] Scrolled to bottom")
	else:
		print("[_add_clear_backups_button] ERROR: Parent is not VBoxContainer!")

# 打印设置页面布局调试信息
func _print_settings_layout_debug() -> void:
	print("========== SETTINGS LAYOUT DEBUG ==========")

	# 打印父级节点信息
	var tab_container = get_node_or_null("/root/Control/TabContainer")
	var settings_tab = get_node_or_null("/root/Control/TabContainer/SettingsTab")
	var settings_scroll = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll")

	print("TabContainer: ", tab_container)
	if tab_container:
		print("  - size: ", tab_container.size)
		print("  - position: ", tab_container.position)
		print("  - global_position: ", tab_container.global_position)

	print("SettingsTab: ", settings_tab)
	if settings_tab:
		print("  - size: ", settings_tab.size)
		print("  - position: ", settings_tab.position)
		print("  - global_position: ", settings_tab.global_position)
		print("  - visible: ", settings_tab.visible)

	print("SettingsScroll: ", settings_scroll)
	if settings_scroll:
		print("  - size: ", settings_scroll.size)
		print("  - position: ", settings_scroll.position)
		print("  - global_position: ", settings_scroll.global_position)
		print("  - custom_minimum_size: ", settings_scroll.custom_minimum_size)
		print("  - scroll_vertical: ", settings_scroll.scroll_vertical)

	var settings_vbox = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox")
	var save_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/SaveSettingsBtn")
	var clear_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/BackupSection/ClearBackupsBtn")
	# 兼容旧位置
	if not clear_btn:
		clear_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ClearBackupsBtn")

	print("SettingsScroll: ", settings_scroll)
	if settings_scroll:
		print("  - size: ", settings_scroll.size)
		print("  - custom_minimum_size: ", settings_scroll.custom_minimum_size)
		print("  - scroll_vertical: ", settings_scroll.scroll_vertical)
		print("  - get_size(): ", settings_scroll.get_size())

	print("SettingsVBox: ", settings_vbox)
	if settings_vbox:
		print("  - size: ", settings_vbox.size)
		print("  - position: ", settings_vbox.position)
		print("  - get_position(): ", settings_vbox.get_position())
		print("  - custom_minimum_size: ", settings_vbox.custom_minimum_size)
		print("  - min_size: ", settings_vbox.get_minimum_size())
		print("  - size_flags_horizontal: ", settings_vbox.size_flags_horizontal)
		print("  - size_flags_vertical: ", settings_vbox.size_flags_vertical)
		print("  - child_count: ", settings_vbox.get_child_count())

		# 计算子元素总高度
		var total_height = 0.0
		var children = settings_vbox.get_children()
		print("  - children (with global rect):")
		for i in range(children.size()):
			var child = children[i]
			var child_min_size = child.get_minimum_size() if child.has_method("get_minimum_size") else Vector2.ZERO
			total_height += child_min_size.y
			var child_pos = child.position
			if child.has_method("get_position"):
				child_pos = child.get_position()
			print("    [", i, "] ", child.name)
			print("        min_size: ", child_min_size, ", size: ", child.size)
			print("        position: ", child_pos, ", get_position(): ", child.get_position() if child.has_method("get_position") else "N/A")
		print("  - total_min_height: ", total_height)

	print("SaveSettingsBtn: ", save_btn)
	if save_btn:
		print("  - position: ", save_btn.position)
		print("  - get_position(): ", save_btn.get_position())
		print("  - size: ", save_btn.size)
		print("  - get_size(): ", save_btn.get_size())
		print("  - global_position: ", save_btn.global_position)
		print("  - get_global_position(): ", save_btn.get_global_position())
		print("  - visible: ", save_btn.visible)
		print("  - size_flags_horizontal: ", save_btn.size_flags_horizontal)
		var rect = save_btn.get_global_rect()
		print("  - global_rect: ", rect)

	print("ClearBackupsBtn (tscn): ", clear_btn)
	if clear_btn:
		print("  - position: ", clear_btn.position)
		print("  - get_position(): ", clear_btn.get_position())
		print("  - size: ", clear_btn.size)
		print("  - get_size(): ", clear_btn.get_size())
		print("  - global_position: ", clear_btn.global_position)
		print("  - get_global_position(): ", clear_btn.get_global_position())
		print("  - visible: ", clear_btn.visible)
		print("  - size_flags_horizontal: ", clear_btn.size_flags_horizontal)
		var rect = clear_btn.get_global_rect()
		print("  - global_rect: ", rect)

	# 打印动态创建的ClearBackupsBtn
	var clear_btn_dynamic = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/BackupSection/ClearBackupsBtn")
	# 兼容旧位置
	if not clear_btn_dynamic:
		clear_btn_dynamic = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ClearBackupsBtn")
	if clear_btn_dynamic and clear_btn_dynamic != clear_btn:
		print("ClearBackupsBtn (dynamic): ", clear_btn_dynamic)
		print("  - position: ", clear_btn_dynamic.position)
		print("  - size: ", clear_btn_dynamic.size)
		print("  - global_position: ", clear_btn_dynamic.global_position)
		print("  - visible: ", clear_btn_dynamic.visible)

	print("===========================================")

	# 继续设置UI初始化
	if temp_mods_path_browse_btn:
		temp_mods_path_browse_btn.pressed.connect(_on_temp_mods_path_browse)
	if backup_path_browse_btn:
		backup_path_browse_btn.pressed.connect(_on_backup_path_browse)

	# 获取 Nexus API 相关节点并连接信号
	nexus_api_key_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusAPIKeyRow/NexusAPIKeyEdit")
	nexus_validate_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusAPIKeyRow/NexusValidateBtn")
	nexus_status_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusStatusLabel")
	print("[_init_settings_ui_if_needed] Nexus API nodes - edit: ", nexus_api_key_edit, ", btn: ", nexus_validate_btn)

	# 检查翻译是否正确加载
	print("[_init_settings_ui_if_needed] Checking translations:")
	print("  - locale_data keys count: ", locale_data.size())
	print("  - nexus_status_unverified in locale_data: ", locale_data.has("nexus_status_unverified"))
	if locale_data.has("nexus_status_unverified"):
		print("  - nexus_status_unverified value: '", locale_data.get("nexus_status_unverified"), "'")

	# 重新加载 config 确保获取最新值
	config.load(config_path)
	var saved_nexus_api_key = config.get_value("nexus", "api_key", "")
	var saved_validated = config.get_value("nexus", "validated", false)
	var saved_username = config.get_value("nexus", "username", "")
	print("[_init_settings_ui_if_needed] Config values - api_key: '", saved_nexus_api_key.substr(0, 10) if saved_nexus_api_key else "", "...', validated: ", saved_validated, ", username: '", saved_username, "'")

	# 加载已保存的 API Key
	if nexus_api_key_edit and not saved_nexus_api_key.is_empty():
		nexus_api_key_edit.text = saved_nexus_api_key
		print("[_init_settings_ui_if_needed] Set API key to input field")

	# 加载并显示已保存的验证状态
	var is_validated = saved_validated
	var is_premium = config.get_value("nexus", "is_premium", false)
	if is_validated and not saved_username.is_empty():
		var status_text = "已验证: %s" % saved_username
		if is_premium:
			status_text += " (Premium)"
		if nexus_status_label:
			nexus_status_label.text = status_text
		print("[_init_settings_ui_if_needed] Loaded saved validation status: ", status_text)
	elif not saved_nexus_api_key.is_empty():
		# 有API Key但未验证
		if nexus_status_label:
			nexus_status_label.text = translate("nexus_api_key_saved")
			print("[_init_settings_ui_if_needed] Set nexus_api_key_saved: ", translate("nexus_api_key_saved"))
	else:
		# 既没有保存的API Key也没有验证，显示未验证状态
		if nexus_status_label:
			nexus_status_label.text = translate("nexus_status_unverified")
			print("[_init_settings_ui_if_needed] Set nexus_status_unverified: ", translate("nexus_status_unverified"))

	# 连接验证按钮信号（避免重复连接）
	if nexus_validate_btn:
		if not nexus_validate_btn.pressed.is_connected(_on_nexus_validate_pressed):
			nexus_validate_btn.pressed.connect(_on_nexus_validate_pressed)
			print("[_init_settings_ui_if_needed] Connected Nexus validate button signal")

	# 创建本地服务器端口设置Section
	print("[_init_settings_ui_if_needed] About to call _add_server_port_section()")
	_add_server_port_section()
	print("[_init_settings_ui_if_needed] After _add_server_port_section()")

	print("[_init_settings_ui_if_needed] Settings UI initialized!")


# 添加本地服务器端口设置Section
func _add_server_port_section() -> void:
	var settings_vbox = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox")
	if not settings_vbox:
		print("[_add_server_port_section] ERROR: settings_vbox is null!")
		return

	# 检查是否已存在
	if get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ServerPortSection"):
		print("[_add_server_port_section] ServerPortSection already exists")
		return

	# 获取保存设置按钮引用
	var save_settings_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/SaveSettingsBtn")

	# 创建分隔线并插入到保存按钮之前
	var separator_before = HSeparator.new()
	separator_before.name = "SeparatorServerPort"
	if save_settings_btn:
		var save_idx = save_settings_btn.get_index()
		settings_vbox.add_child(separator_before)
		settings_vbox.move_child(separator_before, save_idx)
	else:
		settings_vbox.add_child(separator_before)
	print("[_add_server_port_section] Added separator")

	# 创建Server Port Section并插入到保存按钮之前
	var server_port_section = VBoxContainer.new()
	server_port_section.name = "ServerPortSection"
	if save_settings_btn:
		var save_idx = save_settings_btn.get_index()
		settings_vbox.add_child(server_port_section)
		settings_vbox.move_child(server_port_section, save_idx)
	else:
		settings_vbox.add_child(server_port_section)
	print("[_add_server_port_section] Added ServerPortSection")

	# 创建标题标签
	var section_label = Label.new()
	section_label.text = translate("server_port")
	section_label.add_theme_font_size_override("font_size", 16)
	section_label.add_theme_color_override("font_color", Color(0.2, 0.6, 0.9, 1))
	server_port_section.add_child(section_label)

	# 创建端口输入行
	var port_row = HBoxContainer.new()
	port_row.name = "ServerPortRow"
	port_row.custom_minimum_size = Vector2(0, 35)
	server_port_section.add_child(port_row)

	# 端口标签
	var port_label = Label.new()
	port_label.name = "ServerPortLabel"
	port_label.text = translate("server_port")
	port_label.custom_minimum_size = Vector2(100, 0)
	port_row.add_child(port_label)

	# 端口输入框
	var port_spin = SpinBox.new()
	port_spin.name = "ServerPortSpin"
	port_spin.custom_minimum_size = Vector2(100, 0)
	port_spin.min_value = 1024
	port_spin.max_value = 65535
	port_spin.value = config.get_value("server", "port", 8765)
	port_row.add_child(port_spin)

	# 描述标签
	var desc_label = Label.new()
	desc_label.text = translate("server_port_desc")
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	server_port_section.add_child(desc_label)

	# 提示标签（提示需要重启）
	var tip_label = Label.new()
	tip_label.text = translate("server_restart_tip")
	tip_label.add_theme_font_size_override("font_size", 11)
	tip_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2, 1))
	server_port_section.add_child(tip_label)

	# 连接端口变化信号
	port_spin.value_changed.connect(_on_server_port_changed)
	print("[_add_server_port_section] Server port section added successfully")


# 服务器端口变化时的处理
func _on_server_port_changed(value: float) -> void:
	var new_port = int(value)
	var old_port = config.get_value("server", "port", 8765)
	if new_port != old_port:
		config.set_value("server", "port", new_port)
		config.save(config_path)
		print("[_on_server_port_changed] Port changed from ", old_port, " to ", new_port)


# 连接设置控件的值变化信号
var _settings_signals_connected: bool = false

func _connect_settings_change_signals() -> void:
	if _settings_signals_connected:
		return
	_settings_signals_connected = true
	
	# 路径输入框
	if game_path_edit:
		game_path_edit.text_changed.connect(_on_settings_changed)
	if save_path_edit:
		save_path_edit.text_changed.connect(_on_settings_changed)
	if temp_mods_path_edit:
		temp_mods_path_edit.text_changed.connect(_on_settings_changed)
	if backup_path_edit:
		backup_path_edit.text_changed.connect(_on_settings_changed)
	
	# 语言选项
	if language_option:
		language_option.item_selected.connect(_on_language_changed)

	# DPI 缩放滑块
	if dpi_scale_slider:
		print("[_connect_settings_signals] Connecting dpi_scale_slider signal")
		dpi_scale_slider.value_changed.connect(_on_dpi_scale_changed)
		print("[_connect_settings_signals] dpi_scale_slider signal connected!")
	else:
		print("[_connect_settings_signals] dpi_scale_slider is null!")

	# 复选框
	if auto_backup_check:
		auto_backup_check.toggled.connect(_on_settings_changed)
	if auto_backup_on_startup_check:
		auto_backup_on_startup_check.toggled.connect(_on_settings_changed)
	if launch_via_steam_check:
		launch_via_steam_check.toggled.connect(_on_settings_changed)
	
	# 数值输入
	if auto_backup_max_count_spin:
		auto_backup_max_count_spin.value_changed.connect(_on_settings_changed)


# 添加模组字段配置UI（复选框形式，打勾=检测）
func _add_mod_fields_ui() -> void:
	var settings_vbox = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox")
	if not settings_vbox:
		return

	# 检查是否已存在
	if get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ModFieldsSection"):
		return

	# 创建模组字段Section
	var mod_fields_section = VBoxContainer.new()
	mod_fields_section.name = "ModFieldsSection"

	# 创建标题标签
	var section_label = Label.new()
	section_label.text = translate("mod_json_fields")
	mod_fields_section.add_child(section_label)

	# 提示说明
	var hint_label = Label.new()
	hint_label.text = translate("mod_json_fields_hint")
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	mod_fields_section.add_child(hint_label)

	# 可用字段列表（包含所有可能的字段）
	var available_fields = ["id", "name", "author", "description", "version", "has_pck", "has_dll", "affects_gameplay", "dependencies"]
	var field_labels = {
		"id": translate("field_id"),
		"name": translate("field_name"),
		"author": translate("field_author"),
		"description": translate("field_description"),
		"version": translate("field_version"),
		"has_pck": translate("field_has_pck"),
		"has_dll": translate("field_has_dll"),
		"affects_gameplay": translate("field_affects_gameplay"),
		"dependencies": translate("field_dependencies")
	}

	# 创建字段复选框网格
	var fields_grid = GridContainer.new()
	fields_grid.name = "FieldsGrid"
	fields_grid.columns = 3
	mod_fields_section.add_child(fields_grid)

	# 为每个字段创建复选框
	for field in available_fields:
		var check = CheckBox.new()
		check.name = "Field_" + field
		var label = field_labels.get(field, field)
		check.text = label if label else field
		# 检查是否在必要字段列表中
		check.button_pressed = mod_required_fields.has(field)
		fields_grid.add_child(check)

	# 连接所有复选框信号
	fields_grid.child_entered_tree.connect(func(node):
		if node is CheckBox:
			if not node.toggled.is_connected(_on_mod_field_toggled):
				node.toggled.connect(_on_mod_field_toggled)
	)

	# 查找保存按钮的位置并插入
	var save_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/SaveSettingsBtn")
	if save_btn:
		var save_idx = save_btn.get_index()
		settings_vbox.add_child(mod_fields_section)
		settings_vbox.move_child(mod_fields_section, save_idx)
	else:
		settings_vbox.add_child(mod_fields_section)


# 添加模组收纳与覆盖顺序设置Section
func _add_mod_organization_section() -> void:
	var settings_vbox = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox")
	if not settings_vbox:
		print("[_add_mod_organization_section] ERROR: settings_vbox is null!")
		return

	# 检查是否已存在
	if get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ModOrgSection"):
		print("[_add_mod_organization_section] ModOrgSection already exists")
		return

	# 获取保存设置按钮引用
	var save_settings_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/SaveSettingsBtn")

	# 创建分隔线并插入到保存按钮之前
	var sep = HSeparator.new()
	sep.name = "SepModOrg"
	if save_settings_btn:
		var save_idx = save_settings_btn.get_index()
		settings_vbox.add_child(sep)
		settings_vbox.move_child(sep, save_idx)
	else:
		settings_vbox.add_child(sep)

	# 创建ModOrgSection
	var section = VBoxContainer.new()
	section.name = "ModOrgSection"

	var section_title = Label.new()
	section_title.text = translate("mod_organization_title")
	section_title.add_theme_font_size_override("font_size", 16)
	section_title.add_theme_color_override("font_color", Color(0.2, 0.8, 0.5, 1))
	section.add_child(section_title)

	# 描述
	var desc = Label.new()
	desc.text = translate("mod_organization_desc")
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	section.add_child(desc)

	# 收纳功能复选框
	var drag_row = HBoxContainer.new()
	drag_row.name = "ModDragRow"
	section.add_child(drag_row)

	mod_drag_check = CheckBox.new()
	mod_drag_check.name = "ModDragCheck"
	mod_drag_check.text = translate("enable_mod_drag")
	mod_drag_check.button_pressed = enable_mod_drag
	mod_drag_check.toggled.connect(_on_mod_drag_toggled)
	drag_row.add_child(mod_drag_check)

	var drag_tip = Label.new()
	drag_tip.text = translate("enable_mod_drag_tip")
	drag_tip.add_theme_font_size_override("font_size", 11)
	drag_tip.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	drag_row.add_child(drag_tip)

	# 覆盖顺序复选框
	var order_row = HBoxContainer.new()
	order_row.name = "OverrideOrderRow"
	section.add_child(order_row)

	override_order_check = CheckBox.new()
	override_order_check.name = "OverrideOrderCheck"
	override_order_check.text = translate("enable_override_order")
	override_order_check.button_pressed = enable_override_order
	override_order_check.toggled.connect(_on_override_order_toggled)
	order_row.add_child(override_order_check)

	var order_tip = Label.new()
	order_tip.text = translate("enable_override_order_tip")
	order_tip.add_theme_font_size_override("font_size", 11)
	order_tip.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	order_row.add_child(order_tip)

	# 插入到保存按钮之前
	if save_settings_btn:
		var save_idx = save_settings_btn.get_index()
		settings_vbox.add_child(section)
		settings_vbox.move_child(section, save_idx)
	else:
		settings_vbox.add_child(section)

	print("[_add_mod_organization_section] Added ModOrgSection")


func _on_mod_drag_toggled(toggled_on: bool) -> void:
	enable_mod_drag = toggled_on
	settings_dirty = true
	# 如果开启收纳功能且 mod_order_override 为空，用当前显示的模组初始化
	if toggled_on and mod_order_override.is_empty() and not displayed_mods.is_empty():
		_init_mod_order_from_displayed()
	print("[_on_mod_drag_toggled] enable_mod_drag: ", enable_mod_drag)


func _on_override_order_toggled(toggled_on: bool) -> void:
	enable_override_order = toggled_on
	settings_dirty = true
	# 确保 mod_order_override 已有内容
	if toggled_on and mod_order_override.is_empty() and not displayed_mods.is_empty():
		_init_mod_order_from_displayed()
	print("[_on_override_order_toggled] enable_override_order: ", enable_override_order)


func _init_mod_order_from_displayed() -> void:
	# 从 displayed_mods 构建 mod_order_override 列表
	mod_order_override.clear()
	for mod_item in displayed_mods:
		var mod_id = mod_item.get("id", "")
		if not mod_id.is_empty() and not mod_id in mod_order_override:
			mod_order_override.append(mod_id)
	print("[_init_mod_order_from_displayed] Initialized with ", mod_order_override.size(), " mods")


# 模组字段复选框变化回调
func _on_mod_field_toggled(_toggled_on: bool) -> void:
	settings_dirty = true
	# 更新 mod_required_fields 列表
	var fields_grid = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ModFieldsSection/FieldsGrid")
	if fields_grid:
		mod_required_fields.clear()
		for child in fields_grid.get_children():
			if child is CheckBox and child.button_pressed:
				var field_name = child.name.replace("Field_", "")
				mod_required_fields.append(field_name)
		print("[_on_mod_field_toggled] mod_required_fields: ", mod_required_fields)


# 设置值变化回调
func _on_settings_changed(_value = null) -> void:
	settings_dirty = true
	print("[Settings] Settings modified (unsaved)")


# 刷新设置UI显示
func _refresh_settings_ui() -> void:
	# 重新加载路径配置到UI
	game_path = config.get_value("paths", "game_path", "")
	save_path = config.get_value("paths", "save_path", "")
	# temp_mods_path 和 backup_path 是动态属性，直接使用

	# 尝试获取节点引用（如果之前未获取）
	if not game_path_edit:
		game_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/GamePathRow/GamePathEdit")
	if not save_path_edit:
		save_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/SavePathRow/SavePathEdit")
	if not temp_mods_path_edit:
		temp_mods_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/TempModsPathRow/TempModsPathEdit")
	if not backup_path_edit:
		backup_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/BackupPathRow/BackupPathEdit")

	if game_path_edit:
		game_path_edit.text = ""  # 先清空
		game_path_edit.text = game_path
	if save_path_edit:
		save_path_edit.text = ""  # 先清空
		save_path_edit.text = save_path
	if temp_mods_path_edit:
		temp_mods_path_edit.text = temp_mods_path
	if backup_path_edit:
		backup_path_edit.text = backup_path


# 更新设置UI中的路径显示
func _update_settings_path_display() -> void:
	_refresh_settings_ui()


# 辅助函数：递归查找子节点
func find_child_node(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for child in node.get_children():
		var result = find_child_node(child, name)
		if result:
			return result
	return null


# 读取JSON文件
func read_json_file(file_path: String) -> Dictionary:
	var data = {}
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file != null:
			var content = file.get_as_text()
			file.close()
			var json = JSON.new()
			var error = json.parse(content)
			if error == OK:
				data = json.get_data()
	return data


# 加载模组列表
func load_mods() -> void:
	print("=== load_mods 开始 ===")
	mods.clear()
	mod_items.clear()

	# 【关键修复】不再 clear() enabled_mods
	# enabled_mods 已在 load_config() 中从 config.cfg 加载
	# 这里只扫描文件系统来补充/更新 enabled_mods 的实际状态
	# 避免覆盖从 config 加载的标签预设数据

	# 首先，同步外部模组到 temp_mods
	_sync_external_mods_to_temp()

	# 扫描 temp_mods 目录获取所有已安装的模组
	var temp_mods_dir = temp_mods_path
	var added_ids = {}  # 用于去重 - 按 JSON 中的 id 字段去重
	if DirAccess.dir_exists_absolute(temp_mods_dir):
		var dir = DirAccess.open(temp_mods_dir)
		if dir:
			dir.list_dir_begin()
			var item_dir = dir.get_next()
			while item_dir != "":
				if item_dir != "." and item_dir != ".." and not item_dir.begins_with("_"):
					var mod_path = temp_mods_dir.path_join(item_dir)
					if DirAccess.dir_exists_absolute(mod_path):
						var mod_info = ModUtils.get_mod_info(mod_path)
						if not mod_info.is_empty():
							# 使用 JSON 中的 id 字段作为去重依据
							var json_id = mod_info.get("id", item_dir)
							if added_ids.has(json_id):
								print("跳过重复模组 (id冲突): ", json_id, " (目录: ", item_dir, ")")
								item_dir = dir.get_next()
								continue

							mod_info["id"] = json_id
							mod_info["path"] = mod_path
							mods.append(mod_info)
							added_ids[json_id] = true
							print("添加模组: ", mod_info.get("name", ""))
						else:
							# 没有 JSON 的目录也添加到列表，但用目录名作为 ID
							if not added_ids.has(item_dir):
								mods.append({
									"id": item_dir,
									"name": item_dir,
									"path": mod_path
								})
								added_ids[item_dir] = true
								print("添加模组 (无JSON): ", item_dir)
				item_dir = dir.get_next()
			dir.list_dir_end()

	# 检查 test_mods 目录来判断哪些模组已启用
	var test_mods_dir = get_base_path() + "test_mods"
	if DirAccess.dir_exists_absolute(test_mods_dir):
		var dir = DirAccess.open(test_mods_dir)
		if dir:
			dir.list_dir_begin()
			var item_dir = dir.get_next()
			while item_dir != "":
				if item_dir != "." and item_dir != ".." and not item_dir.begins_with("_"):
					enabled_mods[item_dir] = true
				item_dir = dir.get_next()
			dir.list_dir_end()

	# 检查游戏目录中的 mods
	if not game_path.is_empty():
		var game_mods_dir = game_path.path_join("mods")
		if DirAccess.dir_exists_absolute(game_mods_dir):
			var dir = DirAccess.open(game_mods_dir)
			if dir:
				dir.list_dir_begin()
				var item_dir = dir.get_next()
				while item_dir != "":
					if item_dir != "." and item_dir != ".." and not item_dir.begins_with("_"):
						enabled_mods[item_dir] = true
					item_dir = dir.get_next()
				dir.list_dir_end()

	# 为所有模组标记启用状态（如果还没有记录的，默认为 false）
	for mod in mods:
		var mod_id = mod.get("id", "")
		if not enabled_mods.has(mod_id):
			enabled_mods[mod_id] = false

	print("总模组数: ", mods.size())
	print("enabled_mods: ", enabled_mods)

	# 检测模组依赖（必须在列表更新之前）
	_check_mod_dependencies()

	# 应用搜索和排序
	apply_filters_and_sort()
	update_mod_list_display()

	# 注意：不再在这里调用 _apply_tag_mods()
	# 模组状态已通过扫描游戏 mods 目录确定
	# _apply_tag_mods() 仅在标签切换时调用

	print("=== load_mods 完成 ===")


# 检测模组依赖是否满足
func _check_mod_dependencies() -> void:
	print("=== 开始检测模组依赖 ===")
	# 构建已安装模组ID集合
	var installed_ids: Array = []
	for mod in mods:
		var mod_id = mod.get("id", "")
		if not mod_id.is_empty():
			installed_ids.append(mod_id)

	print("已安装模组ID: ", installed_ids)

	# 遍历每个模组，检查依赖
	for mod in mods:
		var deps = mod.get("dependencies", [])
		var missing: Array = []

		for dep_id in deps:
			if dep_id not in installed_ids:
				missing.append(dep_id)

		mod["missing_dependencies"] = missing
		if not missing.is_empty():
			print("模组 %s 缺少依赖: %s" % [mod.get("name", ""), missing])

	print("=== 依赖检测完成 ===")


# 检查模组的依赖是否已启用（用于启用模组时）
# 返回: {
#     "can_enable": bool,  # 是否可以直接启用
#     "disabled_deps": Array,  # 未启用的依赖ID列表
#     "all_deps_enabled": bool  # 所有依赖是否都已启用
# }
func _check_deps_enabled(mod_data: Dictionary) -> Dictionary:
	var mod_id = mod_data.get("id", "")
	var deps = mod_data.get("dependencies", [])

	var disabled_deps: Array = []
	for dep_id in deps:
		# 检查依赖是否已安装且已启用
		var is_installed = false
		var is_enabled = false
		for mod in mods:
			if mod.get("id") == dep_id:
				is_installed = true
				break
		if is_installed:
			is_enabled = enabled_mods.get(dep_id, false)
		else:
			# 依赖未安装，也视为未启用
			is_enabled = false

		if not is_enabled:
			disabled_deps.append(dep_id)

	return {
		"can_enable": disabled_deps.is_empty(),
		"disabled_deps": disabled_deps,
		"all_deps_enabled": disabled_deps.is_empty()
	}


# 显示依赖启用确认对话框
func _show_dependency_enable_dialog(mod_data: Dictionary, disabled_deps: Array, on_confirm: Callable, on_cancel: Callable = func(): pass) -> void:
	var mod_name = mod_data.get("name", "Unknown")

	# 构建依赖列表文本
	var deps_text = ""
	for dep_id in disabled_deps:
		var dep_name = dep_id
		# 查找依赖的名称
		for mod in mods:
			if mod.get("id") == dep_id:
				dep_name = mod.get("name", dep_id)
				break
		deps_text += "• %s (%s)\n" % [dep_name, dep_id]

	var dialog = ConfirmationDialog.new()
	dialog.title = translate("dependency_enable_title")
	add_child(dialog)

	var warning_text = translate("dependency_enable_warning") % mod_name
	warning_text += "\n\n%s\n" % deps_text
	warning_text += "\n" + translate("dependency_enable_checkbox")

	dialog.dialog_text = warning_text
	dialog.ok_button_text = translate("confirm")
	dialog.cancel_button_text = translate("cancel")

	# 添加复选框（通过创建CheckBox）
	var checkbox = CheckBox.new()
	checkbox.text = translate("dependency_enable_checkbox")
	checkbox.button_pressed = true  # 默认勾选
	checkbox.position = Vector2(20, 80)
	checkbox.size = Vector2(300, 30)
	dialog.add_child(checkbox)

	dialog.canceled.connect(func():
		dialog.queue_free()
		on_cancel.call()
	)
	dialog.confirmed.connect(func():
		dialog.queue_free()
		if checkbox.button_pressed:
			# 一并启用依赖模组
			for dep_id in disabled_deps:
				for mod in mods:
					if mod.get("id") == dep_id:
						# 启用依赖模组
						var success = ModUtils.enable_mod(mod, game_path)
						if success:
							enabled_mods[dep_id] = true
							if mod_items.has(dep_id):
								mod_items[dep_id].update_enabled_status(true)
						break
			# 保存状态
			_save_current_tag_mods()
			_save_tag_data()
			_save_enabled_mods()
		on_confirm.call()
	)

	# 调整弹出大小以适应内容
	dialog.popup_centered(Vector2(450, 250))


# 显示缺少依赖警告对话框
func _show_missing_dep_warning_dialog(mod_data: Dictionary, on_confirm: Callable, on_cancel: Callable = func(): pass) -> void:
	var mod_name = mod_data.get("name", "Unknown")
	var missing_deps = mod_data.get("missing_dependencies", [])

	var dialog = ConfirmationDialog.new()
	dialog.title = translate("warning")
	add_child(dialog)

	var warning_text = translate("dependency_missing_warning")
	warning_text += "\n\n"
	warning_text += translate("dependency_enable_warning") % mod_name
	warning_text += "\n"
	for dep_id in missing_deps:
		warning_text += "• %s\n" % dep_id

	dialog.dialog_text = warning_text
	dialog.ok_button_text = translate("dependency_missing_confirm")
	dialog.cancel_button_text = translate("cancel")

	dialog.canceled.connect(func():
		dialog.queue_free()
		on_cancel.call()
	)
	dialog.confirmed.connect(func():
		dialog.queue_free()
		on_confirm.call()
	)

	dialog.popup_centered(Vector2(450, 250))


# 同步外部模组到 temp_mods
func _sync_external_mods_to_temp() -> void:
	print("=== sync external mods to temp ===")

	# 确保 temp_mods 目录存在
	var temp_mods_dir = temp_mods_path
	if not DirAccess.dir_exists_absolute(temp_mods_dir):
		DirAccess.make_dir_recursive_absolute(temp_mods_dir)

	# 收集所有外部模组目录
	var external_dirs = []

	# 检查游戏 mods 目录（正式版本 - 游戏目录下的mods）
	if not game_path.is_empty():
		var game_mods_dir = game_path.path_join("mods")
		if DirAccess.dir_exists_absolute(game_mods_dir):
			external_dirs.append({"path": game_mods_dir, "name": translate("game_path")})

	# 检查 test_mods 目录（仅用于开发测试）
	var base = get_base_path()
	if DirAccess.dir_exists_absolute(base + "test_mods"):
		external_dirs.append({"path": base + "test_mods", "name": "Test Mods"})

	# 收集所有版本冲突
	var conflicts = []

	# 遍历外部目录
	for ext_dir_info in external_dirs:
		var ext_dir = ext_dir_info["path"]
		var ext_dir_name = ext_dir_info["name"]
		print("检查外部目录: ", ext_dir)
		var dir = DirAccess.open(ext_dir)
		if dir:
			dir.list_dir_begin()
			var item_dir = dir.get_next()
			while item_dir != "":
				if item_dir != "." and item_dir != ".." and not item_dir.begins_with("_"):
					var ext_mod_path = ext_dir.path_join(item_dir)
					if DirAccess.dir_exists_absolute(ext_mod_path):
						var temp_mod_path = temp_mods_dir.path_join(item_dir)

						# 如果 temp_mods 中不存在，直接复制
						if not DirAccess.dir_exists_absolute(temp_mod_path):
							print("复制模组到 temp: ", item_dir)
							FileUtils.copy_directory(ext_mod_path, temp_mod_path)
						else:
							# 如果存在，比较版本号
							var ext_info = ModUtils.get_mod_info(ext_mod_path)
							var temp_info = ModUtils.get_mod_info(temp_mod_path)

							if not ext_info.is_empty() and not temp_info.is_empty():
								var ext_version = ext_info.get("version", "v0.0.0")
								var temp_version = temp_info.get("version", "v0.0.0")
								var ext_name = ext_info.get("name", item_dir)
								var temp_name = temp_info.get("name", item_dir)

								if ext_version != temp_version:
									# 版本不同，记录冲突
									conflicts.append({
										"id": item_dir,
										"ext_path": ext_mod_path,
										"temp_path": temp_mod_path,
										"ext_version": ext_version,
										"temp_version": temp_version,
										"ext_name": ext_name,
										"temp_name": temp_name,
										"ext_dir": ext_dir_name
									})
				item_dir = dir.get_next()
			dir.list_dir_end()

	# 如果有版本冲突，显示对话框让用户选择
	if conflicts.size() > 0:
		_show_version_conflict_dialog(conflicts)

	print("=== sync complete ===")


# 显示版本冲突对话框
func _show_version_conflict_dialog(conflicts: Array) -> void:
	print("=== showing version conflict dialog, count: ", conflicts.size())

	# 使用 ConfirmationDialog 来支持两个按钮
	var dialog = ConfirmationDialog.new()
	dialog.title = "模组版本冲突"
	add_child(dialog)

	# 构建冲突信息文本
	var conflict_text = "发现以下模组版本冲突：\n\n"
	for conflict in conflicts:
		conflict_text += "模组: %s\n" % conflict["temp_name"]
		conflict_text += "  临时文件夹: %s\n" % conflict["temp_version"]
		conflict_text += "  %s: %s\n" % [conflict["ext_dir"], conflict["ext_version"]]
		conflict_text += "\n"

	conflict_text += "请选择处理方式：\n"
	conflict_text += "点击确认 - 用外部版本替换（备份旧版本）\n"
	conflict_text += "点击取消 - 保留临时文件夹中的版本"

	dialog.dialog_text = conflict_text
	dialog.ok_button_text = "替换（备份旧版）"
	dialog.cancel_button_text = "保留旧版"

	# 连接信号
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.confirmed.connect(func():
		# 用户选择替换，备份旧版本并替换
		for conflict in conflicts:
			_backup_and_replace_mod(conflict)
		dialog.queue_free()
		# 重新加载模组列表
		load_mods()
	)

	dialog.popup_centered(Vector2(500, 300))


# 备份并替换模组
func _backup_and_replace_mod(conflict: Dictionary) -> void:
	var mod_id = conflict["id"]
	var temp_path = conflict["temp_path"]
	var ext_path = conflict["ext_path"]

	# 创建备份文件夹
	var backup_dir = get_base_path() + "mod_backups"
	if not DirAccess.dir_exists_absolute(backup_dir):
		DirAccess.make_dir_recursive_absolute(backup_dir)

	# 添加时间戳到备份名称
	var timestamp = Time.get_unix_time_from_system()
	var backup_path = backup_dir.path_join("%s_%d" % [mod_id, timestamp])

	# 备份旧版本
	print("备份模组: ", mod_id, " 到 ", backup_path)
	FileUtils.copy_directory(temp_path, backup_path)

	# 删除旧版本
	var dir = DirAccess.open(temp_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path = temp_path.path_join(file_name)
				DirAccess.remove_absolute(full_path)
			file_name = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(temp_path)

	# 复制新版本
	print("替换模组: ", mod_id, " 从 ", ext_path)
	FileUtils.copy_directory(ext_path, temp_path)


# 比较版本号，返回 1 if v1 > v2, -1 if v1 < v2, 0 if equal
# 获取文件夹创建/修改时间
func get_folder_timestamp(folder_path: String) -> int:
	var dir = DirAccess.open(folder_path)
	if dir == null:
		return 0
	return 0  # Godot 4没有直接获取文件夹时间戳的方法，使用0表示未知


# 加载存档列表
func load_saves() -> void:
	steam_saves.clear()
	imported_saves.clear()
	grouped_saves.clear()
	save_panels.clear()

	print("=== [load_saves] 开始 ===")
	print("[load_saves] save_path from config: '", save_path, "'")

	if save_path.is_empty():
		print("[load_saves] ERROR: save_path is empty!")
		update_save_list_display()
		return

	# 检查路径是否存在
	if not DirAccess.dir_exists_absolute(save_path):
		print("[load_saves] ERROR: save_path does not exist: ", save_path)
		update_save_list_display()
		return

	# 扫描备份文件夹，获取已备份的存档信息
	_scan_backup_folders()

	# 获取分组存档
	grouped_saves = SaveUtils.scan_all_saves_grouped(save_path)
	print("[load_saves] grouped_saves: ", grouped_saves)

	# 兼容旧逻辑
	steam_saves = SaveUtils.scan_all_saves(save_path)
	print("[load_saves] Found ", steam_saves.size(), " steam saves")

	# 扫描导入存档（从temp_save目录）
	print("[load_saves] temp_save_path: ", temp_save_path)
	print("[load_saves] temp_save_path exists: ", DirAccess.dir_exists_absolute(temp_save_path))
	if DirAccess.dir_exists_absolute(temp_save_path):
		imported_saves = SaveUtils.scan_saves(temp_save_path)
		print("[load_saves] Found ", imported_saves.size(), " imported saves")
		print("[load_saves] imported_saves: ", imported_saves)
	else:
		print("[load_saves] temp_save_path does not exist!")

	# 更新存档列表显示
	update_save_list_display()
	print("=== [load_saves] 结束 ===")


# 扫描备份文件夹，获取已备份的存档
func _scan_backup_folders() -> void:
	# 保存已从config加载的导入存档备份，避免被清空
	var saved_imported_backups = {}
	for key in backed_up_saves:
		if key.begins_with("imported_"):
			saved_imported_backups[key] = backed_up_saves[key]

	backed_up_saves.clear()

	print("[_scan_backup_folders] backup_path: ", backup_path)
	print("[_scan_backup_folders] save_path: ", save_path)

	# 扫描用户配置的backup_path
	if not backup_path.is_empty() and DirAccess.dir_exists_absolute(backup_path):
		print("[_scan_backup_folders] Scanning user backup path: ", backup_path)
		_scan_single_backup_folder(backup_path)
	else:
		print("[_scan_backup_folders] User backup path is empty or not exists")

	# 也扫描Steam账号目录下的backups文件夹（兼容旧版本）
	if not save_path.is_empty() and DirAccess.dir_exists_absolute(save_path):
		var accounts = SaveUtils.get_all_steam_accounts(save_path)
		print("[_scan_backup_folders] Found accounts: ", accounts.size())
		for account in accounts:
			var steam_id = account["steam_id"]
			var account_path = account["path"]
			# 只检查，不会在账号目录下创建backups
			var account_backup_dir = account_path.path_join("backups")
			print("[_scan_backup_folders] Checking account backup dir: ", account_backup_dir)
			if DirAccess.dir_exists_absolute(account_backup_dir):
				# 扫描该目录下的备份文件夹
				_scan_single_backup_folder_for_account(account_backup_dir, steam_id)

	# 扫描用户配置的备份目录（或默认的app backups目录）
	var app_backup_dir = ""
	if not backup_path.is_empty() and DirAccess.dir_exists_absolute(backup_path):
		app_backup_dir = backup_path
	else:
		app_backup_dir = get_base_path() + "backups"

	if DirAccess.dir_exists_absolute(app_backup_dir):
		print("[_scan_backup_folders] Scanning app backup dir: ", app_backup_dir)
		_scan_single_backup_folder(app_backup_dir)

	print("[_scan_backup_folders] Final backed_up_saves: ", backed_up_saves)

	# 恢复从config加载的导入存档备份（扫描无法找到这些，因为备份名不含Steam ID）
	for key in saved_imported_backups:
		backed_up_saves[key] = saved_imported_backups[key]
		print("[_scan_backup_folders] Restored imported backup: ", key, " -> ", saved_imported_backups[key])

	# 自动备份所有Steam存档
	_auto_backup_all_saves()


# 自动备份所有Steam存档
# 清理旧备份，保留最新 N 个
# backup_dir: 备份目录
# save_id: Steam ID 或导入存档名称
# is_steam: true=Steam存档（用steam_<id>_*格式），false=导入存档（用*_<id>_*格式或*_*格式）
func _prune_old_backups(backup_dir: String, save_id: String, is_steam: bool) -> void:
	var max_count = config.get_value("settings", "auto_backup_max_count", 5)
	if max_count <= 0:
		max_count = 1

	var dir = DirAccess.open(backup_dir)
	if dir == null:
		return

	# 收集所有相关的自动备份文件夹（排除手动备份）
	var auto_backup_folders = []
	var manual_backup_count = 0
	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir():
			var is_match = false
			var is_manual = false
			if is_steam:
				if folder_name.begins_with("steam_" + save_id + "_"):
					is_match = true
					if "_manual_" in folder_name:
						is_manual = true
			else:
				if folder_name.begins_with("manual_"):
					is_match = true
					is_manual = true
				elif folder_name.begins_with("auto_"):
					is_match = true

			if is_match:
				var full_path = backup_dir.path_join(folder_name)
				if is_manual:
					manual_backup_count += 1
				else:
					auto_backup_folders.append({"name": folder_name, "path": full_path})
		folder_name = dir.get_next()
	dir.list_dir_end()

	print("[_prune_old_backups] Auto: ", auto_backup_folders.size(), ", Manual: ", manual_backup_count)

	if auto_backup_folders.size() <= max_count:
		return

	auto_backup_folders.sort_custom(func(a, b): return a["name"] < b["name"])

	var to_delete = auto_backup_folders.size() - max_count
	print("[_prune_old_backups] Deleting ", to_delete, " old auto backups")
	for i in range(to_delete):
		var folder = auto_backup_folders[i]
		SaveUtils.delete_directory(folder["path"])


func _auto_backup_all_saves() -> void:
	print("[_auto_backup_all_saves] Called, _skip_auto_backup = ", _skip_auto_backup)
	# 检查是否需要跳过自动备份
	if _skip_auto_backup:
		print("[_auto_backup_all_saves] Skipping auto backup (flag set)")
		_skip_auto_backup = false
		return

	# 检查是否启用防误删备份
	var do_backup = config.get_value("settings", "auto_backup", true)
	if not do_backup:
		return

	# 检查是否启用启动时自动备份
	var do_backup_on_startup = config.get_value("settings", "auto_backup_on_startup", true)
	if not do_backup_on_startup:
		return

	if save_path.is_empty() or not DirAccess.dir_exists_absolute(save_path):
		return

	# 延迟执行，避免阻塞启动 - 等待3秒后再执行备份
	call_deferred("_do_auto_backup_delayed")


func _do_auto_backup_delayed() -> void:
	# 等待更长时间，确保界面完全加载后再备份
	await get_tree().create_timer(5.0).timeout
	print("[_do_auto_backup_delayed] Starting delayed auto backup...")
	_do_auto_backup()


func _do_auto_backup() -> void:
	var accounts = SaveUtils.get_all_steam_accounts(save_path)
	if accounts.is_empty():
		print("[_do_auto_backup] No accounts found")
		_hide_loading_immediately()
		return

	print("[_do_auto_backup] Starting auto backup for ", accounts.size(), " accounts")

	# 先显示加载界面
	_show_loading(translate("backing_up_saves"))

	# 使用线程执行备份
	var thread = Thread.new()
	thread.start(_backup_thread_func.bind(accounts))

	# 监控线程进度，定期更新UI
	_monitor_backup_progress(thread, accounts)


func _hide_loading_immediately() -> void:
	# 直接隐藏，不等待
	if loading_panel:
		loading_panel.visible = false
		print("[_hide_loading_immediately] Hidden")
	if install_mod_button:
		install_mod_button.disabled = false


func _backup_thread_func(accounts: Array) -> Array:
	# 在后台线程执行备份，返回结果
	var results = []

	for account in accounts:
		var steam_id = account["steam_id"]
		var account_path = account["path"]

		# 创建备份目录 - 优先使用用户配置的备份路径，避免在Steam账号目录下创建backups
		var backup_dir = ""
		if not backup_path.is_empty() and DirAccess.dir_exists_absolute(backup_path):
			backup_dir = backup_path
		else:
			# 如果没有配置备份路径，使用应用的backups目录（而不是账号目录下的backups）
			backup_dir = get_base_path() + "backups"

		if not DirAccess.dir_exists_absolute(backup_dir):
			DirAccess.make_dir_recursive_absolute(backup_dir)

		# 创建备份
		var backup_result = SaveUtils.create_backup(account_path, backup_dir, steam_id, true)

		# 记录结果（注意：这是在后台线程，不能直接修改主线程数据）
		results.append({
			"steam_id": steam_id,
			"backup_result": backup_result,
			"backup_dir": backup_dir
		})

	return results


func _monitor_backup_progress(thread: Thread, accounts: Array) -> void:
	var total = accounts.size()
	var last_completed = 0

	# 定期检查线程状态并更新UI
	while thread.is_alive():
		# 估算进度（假设每个账号时间相似）
		var current_completed = min(last_completed + 1, total)
		if current_completed != last_completed:
			last_completed = current_completed
			if loading_label:
				loading_label.text = translate("backing_up_saves") + " (" + str(current_completed) + "/" + str(total) + ")"

		# 等待一段时间再检查
		await get_tree().create_timer(0.5).timeout

	# 线程完成，获取结果
	print("[_monitor_backup_progress] Thread finished, waiting to finish...")
	var backup_results = thread.wait_to_finish()
	print("[_monitor_backup_progress] Got results: ", backup_results.size())

	# 同步结果到主线程
	for result in backup_results:
		var steam_id = result["steam_id"]
		var backup_result = result["backup_result"]
		var backup_dir = result["backup_dir"]

		if not backup_result.is_empty():
			backed_up_saves[steam_id] = backup_result
			backed_up_saves["imported_" + steam_id] = backup_result
			# 清理旧备份
			_prune_old_backups(backup_dir, steam_id, true)

	# 刷新备份状态显示
	for steam_id in backed_up_saves.keys():
		if save_panels.has(steam_id):
			_update_backup_time_display(steam_id)

	# 更新显示并隐藏加载
	update_save_list_display()
	print("[_monitor_backup_progress] About to hide loading, loading_panel=", loading_panel)
	_hide_loading_immediately()
	print("[_do_auto_backup] Done")


# 为特定账号扫描备份文件夹
func _scan_single_backup_folder_for_account(backup_dir: String, steam_id: String) -> void:
	if not DirAccess.dir_exists_absolute(backup_dir):
		return

	var dir = DirAccess.open(backup_dir)
	if dir == null:
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	var found_backup = false
	while folder_name != "":
		if dir.current_is_dir():
			# 检查是否是备份文件夹（以backup_或steam_开头）
			if folder_name.begins_with("backup_") or folder_name.begins_with("steam_"):
				var full_path = backup_dir.path_join(folder_name)
				# 验证这个文件夹确实属于这个steam_id
				var extracted_id = _extract_steam_id_from_backup(folder_name)
				if extracted_id == steam_id:
					# 同时为Steam存档和导入存档记录备份状态
					backed_up_saves[steam_id] = full_path
					backed_up_saves["imported_" + steam_id] = full_path
					print("[_scan_backup_folders] Found backup for ", steam_id, ": ", full_path)
					found_backup = true
					break
		folder_name = dir.get_next()

	# 如果没有找到特定格式的备份，不记录备份状态（让系统认为没有备份）
	# 不要使用账号目录本身作为备份路径，因为这会导致备份时间显示不正确
	if not found_backup:
		print("[_scan_backup_folder_for_account] No valid backup found for ", steam_id)


# 扫描单个备份文件夹
func _scan_single_backup_folder(backup_dir: String) -> void:
	var dir = DirAccess.open(backup_dir)
	if dir == null:
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		# 检查两种格式: backup_xxx 或 steam_steamID_xxx
		if dir.current_is_dir() and (folder_name.begins_with("backup_") or folder_name.begins_with("steam_")):
			var full_path = backup_dir.path_join(folder_name)
			# 尝试从文件夹名提取Steam ID
			# 格式可能是 backup_2024-01-01_12-00-00 或 steam_76561199032814693_2024-01-01_12-00-00
			var steam_id = _extract_steam_id_from_backup(folder_name)
			if not steam_id.is_empty():
				# 同时为Steam存档和导入存档记录备份状态
				backed_up_saves[steam_id] = full_path
				backed_up_saves["imported_" + steam_id] = full_path
				print("[_scan_single_backup_folder] Found backup: ", steam_id, " at ", full_path)
		folder_name = dir.get_next()


# 从备份文件夹名提取Steam ID
func _extract_steam_id_from_backup(folder_name: String) -> String:
	# 尝试提取Steam ID
	# 如果文件夹名包含数字Steam ID
	var parts = folder_name.split("_")
	for part in parts:
		if part.is_valid_int() and part.length() >= 15:
			return part
	return ""


# 检查路径是否是一个有效的SteamID目录
func is_valid_steam_id_directory(path: String) -> bool:
	if path.is_empty():
		return false

	var dir = DirAccess.open(path)
	if dir == null:
		return false

	# 检查是否是纯数字目录名(SteamID)
	var dir_name = path.get_file()
	if not dir_name.is_valid_int():
		return false

	# 检查目录下是否有profile目录
	dir.list_dir_begin()
	var has_profile = false
	var folder_name = dir.get_next()
	while folder_name != "":
		if folder_name.begins_with("profile"):
			has_profile = true
			break
		folder_name = dir.get_next()
	dir.list_dir_end()

	return has_profile


# 更新存档列表显示（分组显示：每个账号一个大面板，面板内分原版和模组存档）
func update_save_list_display() -> void:
	print("=== [update_save_list_display] 开始 ===")
	# 如果save_list_container为null，尝试获取
	if save_list_container == null:
		save_list_container = find_child_node(self, "SaveList")
		print("[update_save_list_display] save_list_container (from find): ", save_list_container)

	print("[update_save_list_display] grouped_saves: ", grouped_saves)
	print("[update_save_list_display] steam_saves: ", steam_saves.size())
	print("[update_save_list_display] imported_saves: ", imported_saves.size())

	if save_list_container == null:
		print("[update_save_list_display] ERROR: save_list_container is NULL!")
		_print_save_ui_tree()
		print("=== [update_save_list_display] 结束 (save_list_container is NULL) ===")
		return

	# 清除现有列表项
	for child in save_list_container.get_children():
		child.queue_free()
	print("[update_save_list_display] Cleared items")

	# 使用分组方式显示
	var steam_data = grouped_saves.get("steam", {})
	var modded_data = grouped_saves.get("modded", {})

	print("[update_save_list_display] steam_data keys: ", steam_data.keys())
	print("[update_save_list_display] modded_data keys: ", modded_data.keys())
	print("[update_save_list_display] imported_saves: ", imported_saves)

	# 获取所有Steam账号ID
	var all_ids = []
	for id in steam_data:
		all_ids.append(id)
		print("[update_save_list_display] Adding from steam_data: ", id, " is_int: ", id.is_valid_int())
	for id in modded_data:
		if not id in all_ids:
			all_ids.append(id)
			print("[update_save_list_display] Adding from modded_data: ", id)

	# 合并导入存档的ID（排除已在Steam账号中的ID）
	for imported in imported_saves:
		var id = imported.get("name", "")
		print("[update_save_list_display] Checking imported: ", id)
		# 导入存档使用完整路径或非数字ID作为标识
		# 如果导入的ID是数字，检查是否已在steam_data或modded_data中
		if id.is_valid_int():
			# 如果这个ID已经是Steam账号，不要重复添加
			if steam_data.has(id) or modded_data.has(id):
				print("[update_save_list_display] Skipping imported id (already in steam): ", id)
				continue
		if not id.is_empty():
			all_ids.append(id)
			print("[update_save_list_display] Added imported id: ", id)

	print("[update_save_list_display] all_ids: ", all_ids)

	# 去重Steam账号ID
	var unique_steam_ids = []
	for id in all_ids:
		if id.is_valid_int() and not id in unique_steam_ids:
			unique_steam_ids.append(id)
	print("[update_save_list_display] unique_steam_ids: ", unique_steam_ids)

	if all_ids.is_empty():
		var no_saves_label = Label.new()
		no_saves_label.text = translate("no_saves")
		save_list_container.add_child(no_saves_label)
		print("[update_save_list_display] Added no_saves label")
	else:
		# Steam存档部分 - 使用去重后的ID列表
		var steam_account_ids = []

		# 先获取steam_data中有存档的账号
		for id in unique_steam_ids:
			var s_info = steam_data.get(id, {})
			var m_info = modded_data.get(id, {})
			# 只有当至少有一个存档时才显示
			if not s_info.is_empty() or not m_info.is_empty():
				steam_account_ids.append(id)
				print("[update_save_list_display] Adding to display: ", id)
			else:
				print("[update_save_list_display] Skipping empty account: ", id)

		if not steam_account_ids.is_empty():
			var title = Label.new()
			title.text = translate("steam_saves")
			title.custom_minimum_size.y = 30
			save_list_container.add_child(title)

			# 为每个账号创建一个大面板，面板内分原版和模组存档
			for steam_id in steam_account_ids:
				print("[update_save_list_display] Processing id: ", steam_id)

				var steam_info = steam_data.get(steam_id, {})
				var modded_info = modded_data.get(steam_id, {})

				print("[update_save_list_display] steam_info empty: ", steam_info.is_empty(), " modded_info empty: ", modded_info.is_empty())

				if steam_info.is_empty() and modded_info.is_empty():
					continue

				# 创建账号大面板
				var account_panel = _create_account_save_panel(steam_id, steam_info, modded_info)
				save_list_container.add_child(account_panel)
				print("[update_save_list_display] Added account panel for: ", steam_id)

		# 导入存档部分 - 显示来自temp_save目录的存档
		var has_imported = false
		var imported_ids = []
		for imported in imported_saves:
			var id = imported.get("name", "")
			var path = imported.get("path", "")
			# 检查是否是导入的存档（路径包含temp_save或不是纯数字ID）
			if not id.is_empty() and (temp_save_path in path or "temp_save" in path):
				imported_ids.append(id)
				has_imported = true

		print("[update_save_list_display] imported_ids: ", imported_ids, " has_imported: ", has_imported)

		if has_imported:
			# 分隔标题
			var divider = HBoxContainer.new()
			divider.custom_minimum_size = Vector2(0, 25)

			var line = Control.new()
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.custom_minimum_size.y = 1
			line.add_theme_color_override("color", Color(0.3, 0.3, 0.3, 1))
			divider.add_child(line)

			var import_label = Label.new()
			import_label.text = translate("imported_save")
			import_label.custom_minimum_size = Vector2(85, 0)
			divider.add_child(import_label)

			# 添加拖入提示
			var hint_label = Label.new()
			hint_label.text = translate("drag_zip_hint")
			hint_label.add_theme_font_size_override("font_size", 11)
			hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))
			hint_label.custom_minimum_size = Vector2(100, 0)
			divider.add_child(hint_label)

			var line2 = Control.new()
			line2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line2.custom_minimum_size.y = 1
			line2.add_theme_color_override("color", Color(0.3, 0.3, 0.3, 1))
			divider.add_child(line2)

			save_list_container.add_child(divider)

			# 显示导入的存档 - 每个导入的存档也使用账号面板样式
			for imported in imported_saves:
				var id = imported.get("name", "")
				var path = imported.get("path", "")
				print("[update_save_list_display] Processing imported: ", id, " path: ", path)

				# 只显示来自temp_save目录的导入存档
				if not ("temp_save" in path):
					continue

				# 创建导入存档的账号面板
				var imported_panel = _create_imported_account_panel(imported)
				save_list_container.add_child(imported_panel)
				print("[update_save_list_display] Added imported panel for: ", id)

	print("[update_save_list_display] Final child count: ", save_list_container.get_child_count())

	# 确保滚动到正确位置显示导入的存档
	var save_scroll = find_child_node(self, "SaveScroll")
	if save_scroll and not imported_saves.is_empty():
		# 滚动到底部显示导入的存档
		call_deferred("_scroll_save_list_to_bottom")

	print("=== [update_save_list_display] 结束 ===")


# 创建账号存档面板（包含原版和模组存档区域）
func _create_account_save_panel(steam_id: String, steam_info: Dictionary, modded_info: Dictionary) -> Control:
	# 外层大面板作为账号底板
	var account_panel = PanelContainer.new()
	account_panel.custom_minimum_size = Vector2(0, 120)  # 高度足以容纳原版和模组
	account_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 创建背景用于选中反馈
	var bg_color = ColorRect.new()
	bg_color.color = Color(0.13, 0.13, 0.13, 1)  # 默认背景色（与模组一致）
	bg_color.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透到panel
	# 让背景在panel后面
	account_panel.add_child(bg_color)
	bg_color.z_index = -1

	# 存储存档信息用于选中回调
	var save_data = {
		"steam_id": steam_id,
		"steam_info": steam_info,
		"modded_info": modded_info,
		"is_imported": false
	}

	# 点击选中功能
	account_panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_save_selected(save_data)
	)

	# 存储面板引用
	save_panels[steam_id] = {
		"panel": account_panel,
		"bg": bg_color,
		"data": save_data
	}

	var vbox = VBoxContainer.new()
	account_panel.add_child(vbox)

	# 账号标题栏
	var title_bar = HBoxContainer.new()
	vbox.add_child(title_bar)

	var account_label = Label.new()
	account_label.text = translate_fmt("steam_id", [steam_id])
	account_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(account_label)

	# 添加备份状态标签（显示在名称和删除按钮之间）
	var backup_status_label = Label.new()
	backup_status_label.name = "BackupStatusLabel"
	backup_status_label.custom_minimum_size = Vector2(70, 0)
	if backed_up_saves.has(steam_id):
		var backup_info = backed_up_saves[steam_id]
		if not backup_info.is_empty():
			backup_status_label.text = translate("already_backed_up")
			backup_status_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))  # 绿色
		else:
			backup_status_label.text = ""
	else:
		backup_status_label.text = ""
	backup_status_label.add_theme_font_size_override("font_size", 12)
	title_bar.add_child(backup_status_label)

	# 添加删除按钮（红色X）- Steam存档
	var delete_btn = Button.new()
	delete_btn.text = "✕"
	delete_btn.custom_minimum_size = Vector2(24, 24)
	delete_btn.tooltip_text = "长按1.5秒删除此Steam存档（操作不可逆）"
	# 红色样式
	delete_btn.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 1))
	delete_btn.add_theme_color_override("font_hover_color", Color(1, 0.3, 0.3, 1))
	# 长按删除功能
	_setup_long_press_delete(delete_btn, steam_id, steam_info, modded_info)
	title_bar.add_child(delete_btn)

	# 原版和模组存档的水平分栏
	var saves_hbox = HBoxContainer.new()
	saves_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saves_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(saves_hbox)

	# 原版存档区域
	var steam_section = VBoxContainer.new()
	steam_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steam_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	saves_hbox.add_child(steam_section)

	var steam_header = Label.new()
	steam_header.text = translate("vanilla_saves")
	steam_header.custom_minimum_size.y = 24
	steam_header.add_theme_font_size_override("font_size", 14)
	steam_header.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3, 1))  # 绿色
	steam_section.add_child(steam_header)

	if not steam_info.is_empty():
		var steam_item = _create_save_group_item(steam_info, false)
		steam_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		steam_item.size_flags_vertical = Control.SIZE_EXPAND_FILL
		steam_section.add_child(steam_item)
	else:
		var empty_label = Label.new()
		empty_label.text = translate("no_saves_label")
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.5))
		steam_section.add_child(empty_label)

	# 分隔线
	var separator = VSeparator.new()
	separator.custom_minimum_size.x = 8
	saves_hbox.add_child(separator)

	# 模组存档区域
	var modded_section = VBoxContainer.new()
	modded_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modded_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	saves_hbox.add_child(modded_section)

	var modded_header = Label.new()
	modded_header.text = translate("modded_saves")
	modded_header.custom_minimum_size.y = 24
	modded_header.add_theme_font_size_override("font_size", 14)
	modded_header.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4, 1))  # 红色
	modded_section.add_child(modded_header)

	if not modded_info.is_empty():
		var modded_item = _create_save_group_item(modded_info, true)
		modded_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modded_item.size_flags_vertical = Control.SIZE_EXPAND_FILL
		modded_section.add_child(modded_item)
	else:
		var empty_label = Label.new()
		empty_label.text = translate("no_saves_label")
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.5))
		modded_section.add_child(empty_label)

	# 备份时间显示（如果有备份）
	var backup_time_label = Label.new()
	backup_time_label.name = "BackupTimeLabel"
	# 检查是否有备份
	var has_backup = backed_up_saves.has(steam_id) and not backed_up_saves[steam_id].is_empty()
	if has_backup:
		var backup_info = backed_up_saves[steam_id]
		# 提取备份时间（从路径中获取）
		var backup_time = _extract_backup_time(backup_info)
		var backup_type = _extract_backup_type(backup_info)
		var type_label = translate("auto_backup_label") if backup_type == "auto" else translate("manual_backup")
		backup_time_label.text = "%s: %s (%s)" % [translate("backup"), backup_time, type_label]
		backup_time_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))  # 绿色
		backup_time_label.custom_minimum_size = Vector2(0, 20)
	else:
		# 未备份时隐藏，不占位
		backup_time_label.visible = false
		backup_time_label.custom_minimum_size = Vector2(0, 0)
	backup_time_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(backup_time_label)

	return account_panel


# 创建导入存档的账号面板
func _create_imported_account_panel(info: Dictionary) -> Control:
	# 外层大面板
	var account_panel = PanelContainer.new()
	account_panel.custom_minimum_size = Vector2(0, 100)
	account_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 创建背景用于选中反馈
	var bg_color = ColorRect.new()
	bg_color.color = Color(0.13, 0.13, 0.13, 1)  # 默认背景色（与模组一致）
	bg_color.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透到panel
	account_panel.add_child(bg_color)
	bg_color.z_index = -1

	# 存储存档信息
	var import_id = info.get("name", "")
	var save_data = {
		"steam_id": import_id,
		"steam_info": {},
		"modded_info": {},
		"is_imported": true,
		"import_info": info
	}

	# 点击选中功能
	account_panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_save_selected(save_data)
	)

	# 存储面板引用（使用特殊前缀区分导入存档）
	save_panels["imported_" + import_id] = {
		"panel": account_panel,
		"bg": bg_color,
		"data": save_data
	}

	var vbox = VBoxContainer.new()
	account_panel.add_child(vbox)

	# 备份时间显示（如果有备份）- 导入存档使用 imported_ 前缀
	var import_panel_key = "imported_" + import_id
	var import_backup_time_label = Label.new()
	import_backup_time_label.name = "BackupTimeLabel"
	# 检查是否有备份
	var has_import_backup = backed_up_saves.has(import_panel_key) and not backed_up_saves[import_panel_key].is_empty()
	if has_import_backup:
		var backup_info = backed_up_saves[import_panel_key]
		var backup_time = _extract_backup_time(backup_info)
		var backup_type = _extract_backup_type(backup_info)
		var type_label = translate("auto_backup_label") if backup_type == "auto" else translate("manual_backup")
		import_backup_time_label.text = "%s: %s (%s)" % [translate("backup"), backup_time, type_label]
		import_backup_time_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))  # 绿色
		import_backup_time_label.custom_minimum_size = Vector2(0, 20)
	else:
		# 未备份时隐藏，不占位
		import_backup_time_label.visible = false
		import_backup_time_label.custom_minimum_size = Vector2(0, 0)
	import_backup_time_label.add_theme_font_size_override("font_size", 11)
	# 不在这里添加，稍后移到存档列表下方

	# 账号标题栏
	var title_bar = HBoxContainer.new()
	vbox.add_child(title_bar)

	var account_label = Label.new()
	var raw_name = info.get("name", "导入存档")
	account_label.text = _truncate_save_name(raw_name)
	account_label.tooltip_text = raw_name  # 鼠标悬停显示完整名称
	account_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(account_label)

	# 添加备份状态标签（显示在名称和删除按钮之间）- 导入存档使用 imported_ 前缀
	# 复用之前的 import_panel_key 变量
	var backup_status_label = Label.new()
	backup_status_label.name = "BackupStatusLabel"
	backup_status_label.custom_minimum_size = Vector2(70, 0)
	if backed_up_saves.has(import_panel_key):
		var backup_info = backed_up_saves[import_panel_key]
		if not backup_info.is_empty():
			backup_status_label.text = translate("already_backed_up")
			backup_status_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))  # 绿色
		else:
			backup_status_label.text = ""
	else:
		backup_status_label.text = ""
	backup_status_label.add_theme_font_size_override("font_size", 12)
	title_bar.add_child(backup_status_label)

	# 添加删除按钮（红色X）
	var delete_btn = Button.new()
	delete_btn.text = "✕"
	delete_btn.custom_minimum_size = Vector2(24, 24)
	delete_btn.tooltip_text = "删除此导入存档"
	# 红色样式
	delete_btn.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 1))
	delete_btn.add_theme_color_override("font_hover_color", Color(1, 0.3, 0.3, 1))
	delete_btn.pressed.connect(func(): _delete_imported_save(info))
	title_bar.add_child(delete_btn)

	# 原版和模组存档的水平分栏
	var saves_hbox = HBoxContainer.new()
	saves_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saves_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(saves_hbox)

	var profiles = info.get("profiles", [])
	var modded_profiles = info.get("modded_profiles", [])
	var has_modded = info.get("has_modded", false)

	# 原版存档区域
	var steam_section = VBoxContainer.new()
	steam_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steam_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	saves_hbox.add_child(steam_section)

	var steam_header = Label.new()
	steam_header.text = translate("vanilla_saves")
	steam_header.custom_minimum_size.y = 24
	steam_header.add_theme_font_size_override("font_size", 14)
	steam_header.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3, 1))
	steam_section.add_child(steam_header)

	if profiles.size() > 0:
		var item = _create_imported_save_item(info, false)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.size_flags_vertical = Control.SIZE_EXPAND_FILL
		steam_section.add_child(item)
	else:
		var empty_label = Label.new()
		empty_label.text = translate("no_saves_label")
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.5))
		steam_section.add_child(empty_label)

	# 分隔线
	var separator = VSeparator.new()
	separator.custom_minimum_size.x = 8
	saves_hbox.add_child(separator)

	# 模组存档区域
	var modded_section = VBoxContainer.new()
	modded_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modded_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	saves_hbox.add_child(modded_section)

	var modded_header = Label.new()
	modded_header.text = translate("modded_saves")
	modded_header.custom_minimum_size.y = 24
	modded_header.add_theme_font_size_override("font_size", 14)
	modded_header.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4, 1))
	modded_section.add_child(modded_header)

	if has_modded and modded_profiles.size() > 0:
		var modded_item = _create_imported_save_item(info, true)
		modded_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modded_item.size_flags_vertical = Control.SIZE_EXPAND_FILL
		modded_section.add_child(modded_item)
	else:
		var empty_label = Label.new()
		empty_label.text = translate("no_saves_label")
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.5))
		modded_section.add_child(empty_label)

	# 在存档列表下方添加备份时间显示
	vbox.add_child(import_backup_time_label)

	return account_panel


# 创建分组存档项
func _create_save_group_item(info: Dictionary, is_modded: bool) -> Control:
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(200, 60)
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox = VBoxContainer.new()
	container.add_child(vbox)

	# 账号名
	var name_label = Label.new()
	var display_name = info.get("name", "未知账号")
	if is_modded:
		display_name += " (模组版)"
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_label)

	# 存档槽位
	var profiles = info.get("profiles", [])
	var profiles_text = "存档: " + ("1,2,3" if profiles.size() == 3 else str(profiles).replace("[", "").replace("]", ""))
	var profile_label = Label.new()
	profile_label.text = profiles_text
	profile_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(profile_label)

	# 最新时间
	var latest_date = info.get("latest_date", "未知")
	var date_label = Label.new()
	date_label.text = translate_fmt("latest_date", [latest_date])
	date_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(date_label)

	# 点击事件 - 显示详情
	container.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_group_save_selected(info, is_modded)
	)

	return container


# 简化存档名称（截取前16个字符）
func _truncate_save_name(name: String) -> String:
	if name.length() <= 16:
		return name
	return name.substr(0, 13) + "..."


# 删除导入存档
func _delete_imported_save(info: Dictionary) -> void:
	var save_name = info.get("name", "")
	var save_path = info.get("path", "")

	if save_name.is_empty() or save_path.is_empty():
		print("[_delete_imported_save] Invalid save info")
		return

	print("[_delete_imported_save] Deleting: ", save_name, " at ", save_path)

	# 确认删除
	var confirm_msg = "确定要删除导入的存档 \"%s\" 吗？\n此操作不可恢复！" % save_name
	# 直接删除（可以添加确认对话框，这里简化处理）
	if DirAccess.dir_exists_absolute(save_path):
		var delete_result = _delete_directory_recursive(save_path)
		if delete_result:
			print("[_delete_imported_save] Successfully deleted: ", save_path)
			# 重新加载存档列表
			load_saves()
			show_notification(translate_fmt("imported_save_deleted", [save_name]), true)
		else:
			print("[_delete_imported_save] Failed to delete: ", save_path)
			show_notification(translate_fmt("delete_failed", [save_name]), false)
	else:
		print("[_delete_imported_save] Path does not exist: ", save_path)
		# 即使路径不存在，也重新加载存档列表
		load_saves()


# 设置Steam存档删除功能（点击即弹出确认对话框）
func _setup_long_press_delete(btn: Button, steam_id: String, steam_info: Dictionary, modded_info: Dictionary) -> void:
	# 点击按钮立即弹出确认对话框
	btn.pressed.connect(func():
		_show_delete_steam_confirm_dialog(steam_id, steam_info, modded_info)
	)


# 显示删除Steam存档确认对话框（红色醒目警告+长按确认按钮）
func _show_delete_steam_confirm_dialog(steam_id: String, steam_info: Dictionary, modded_info: Dictionary) -> void:
	# 创建自定义对话框
	var dialog = Window.new()
	dialog.title = "⚠️ 警告：删除Steam存档"
	dialog.size = Vector2i(450, 450)
	dialog.exclusive = true
	dialog.visible = true
	add_child(dialog)
	dialog.close_requested.connect(func(): dialog.queue_free())

	# 创建主容器
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 15)
	vbox.add_theme_constant_override("margin_left", 20)
	vbox.add_theme_constant_override("margin_right", 20)
	vbox.add_theme_constant_override("margin_top", 20)
	vbox.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(vbox)

	# 警告文本
	var warn_label = Label.new()
	warn_label.text = translate("delete_steam_save_warning")
	warn_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1))
	warn_label.add_theme_font_size_override("font_size", 16)
	warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(warn_label)

	# Steam ID信息
	var id_label = Label.new()
	id_label.text = translate_fmt("steam_id", [steam_id])
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(id_label)

	# 存档信息
	var info_text = ""
	if not steam_info.is_empty():
		info_text += "原版存档: 存在\n"
	if not modded_info.is_empty():
		info_text += "模组存档: 存在\n"

	# 根据设置显示备份提示
	var do_backup = config.get_value("settings", "auto_backup", true)
	if do_backup:
		info_text += "\n此操作将永久删除所有相关数据！\n删除前系统会自动创建ZIP备份。"
	else:
		info_text += "\n此操作将永久删除所有相关数据！\n【警告：当前设置已禁用自动备份，删除后无法恢复！】"

	var info_label = Label.new()
	info_label.text = info_text
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(info_label)

	# 提示文本
	var hint_label = Label.new()
	hint_label.text = "请长按下方按钮2秒确认删除"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2, 1))
	vbox.add_child(hint_label)

	# 按钮容器
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(btn_container)

	# 确认按钮
	var confirm_btn = Button.new()
	confirm_btn.text = translate("longpress_confirm")
	confirm_btn.custom_minimum_size = Vector2(150, 40)
	btn_container.add_child(confirm_btn)

	# 添加到全局更新列表
	_long_press_buttons.append(confirm_btn)

	# 添加长按功能
	_setup_confirm_long_press(confirm_btn, dialog, steam_id, steam_info, modded_info)

	# 取消按钮
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(func():
		_long_press_buttons.erase(confirm_btn)
		dialog.queue_free()
		show_notification(translate("delete_cancelled"), false)
	)
	btn_container.add_child(cancel_btn)

	# 当对话框关闭时清理
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			_long_press_buttons.erase(confirm_btn)
	)

	# 显示对话框（居中）
	dialog.popup_centered()


# 确认按钮长按2秒检测
func _setup_confirm_long_press(btn: Button, dialog: Window, steam_id: String, steam_info: Dictionary, modded_info: Dictionary) -> void:
	var long_press_time = 2000  # 2秒

	# 创建进度条
	var progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(140, 36)
	progress_bar.visible = false
	progress_bar.value = 0
	progress_bar.max_value = 100
	progress_bar.show_percentage = false

	# 进度条样式
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.15, 0.98)
	bg_style.corner_radius_top_left = 6
	bg_style.corner_radius_top_right = 6
	bg_style.corner_radius_bottom_left = 6
	bg_style.corner_radius_bottom_right = 6
	progress_bar.add_theme_stylebox_override("background", bg_style)

	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.85, 0.15, 0.15, 1)
	fill_style.corner_radius_top_left = 6
	fill_style.corner_radius_top_right = 6
	fill_style.corner_radius_bottom_left = 6
	fill_style.corner_radius_bottom_right = 6
	progress_bar.add_theme_stylebox_override("fill", fill_style)

	btn.add_child(progress_bar)

	# 使用控件的meta存储状态
	btn.set_meta("is_pressing", false)
	btn.set_meta("start_time", 0)
	btn.set_meta("progress_bar", progress_bar)
	btn.set_meta("dialog", dialog)
	btn.set_meta("steam_id", steam_id)
	btn.set_meta("steam_info", steam_info)
	btn.set_meta("modded_info", modded_info)

	# 按钮按下
	btn.button_down.connect(func():
		btn.set_meta("is_pressing", true)
		btn.set_meta("start_time", Time.get_ticks_msec())
		progress_bar.visible = true
		progress_bar.value = 0
		btn.text = "请长按..."
	)

	# 按钮释放
	btn.button_up.connect(func():
		btn.set_meta("is_pressing", false)
		progress_bar.visible = false
		progress_bar.value = 0
		btn.text = translate("longpress_confirm")
	)


var _long_press_buttons: Array = []


# 每帧检查长按状态
func _process(delta: float) -> void:
	# 处理 API 桥接队列（每帧检查 HTTP 服务器线程提交的请求）
	if _api_bridge:
		_api_bridge.process_pending()

	var to_remove = []
	for btn in _long_press_buttons:
		if not is_instance_valid(btn):
			to_remove.append(btn)
			continue
		var progress_bar = btn.get_meta("progress_bar", null)
		if progress_bar == null:
			continue
		if not btn.get_meta("is_pressing", false):
			continue
		var start_time = btn.get_meta("start_time", 0)
		var elapsed = Time.get_ticks_msec() - start_time
		var long_press_time = 2000
		var progress = min(100.0, (float(elapsed) / float(long_press_time)) * 100.0)
		progress_bar.value = progress
		# 颜色变化
		if progress < 50:
			progress_bar.modulate = Color(1, 0.85, 0.2, 0.95)
		else:
			progress_bar.modulate = Color(1, 0.2, 0.2, 1)
		# 长按完成
		if elapsed >= long_press_time:
			btn.set_meta("is_pressing", false)
			progress_bar.visible = false
			btn.text = translate("longpress_confirm")
			var dialog = btn.get_meta("dialog", null)
			if dialog and is_instance_valid(dialog):
				dialog.queue_free()
			# 执行删除
			_delete_steam_save(btn.get_meta("steam_id"), btn.get_meta("steam_info"), btn.get_meta("modded_info"))
			to_remove.append(btn)

	for btn in to_remove:
		_long_press_buttons.erase(btn)


# 删除Steam存档
func _delete_steam_save(steam_id: String, steam_info: Dictionary, modded_info: Dictionary) -> void:
	if steam_id.is_empty():
		print("[_delete_steam_save] Invalid steam_id")
		return

	print("[_delete_steam_save] Deleting Steam saves for: ", steam_id)

	# 获取Steam存档路径
	if save_path.is_empty():
		show_notification(translate("cannot_get_save_path"), false)
		return

	var steam_path = save_path.path_join(steam_id)
	var modded_path = steam_path.path_join("modded")

	# 检查是否需要备份
	var do_backup = config.get_value("settings", "auto_backup", true)
	if do_backup:
		# 备份存档
		var backup_path = save_path.path_join("backups")
		if not DirAccess.dir_exists_absolute(backup_path):
			DirAccess.make_dir_recursive_absolute(backup_path)

		# 备份原版存档
		if not steam_info.is_empty():
			var timestamp = Time.get_unix_time_from_system()
			var backup_name = "steam_%s_%d.zip" % [steam_id, timestamp]
			var backup_zip_path = backup_path.path_join(backup_name)
			var zip_result = SaveUtils.create_save_zip(steam_path, backup_zip_path)
			if not zip_result:
				print("[_delete_steam_save] Warning: Failed to backup original saves")

		# 备份模组存档
		if not modded_info.is_empty():
			if DirAccess.dir_exists_absolute(modded_path):
				var timestamp = Time.get_unix_time_from_system()
				var backup_name = "steam_%s_modded_%d.zip" % [steam_id, timestamp]
				var backup_zip_path = backup_path.path_join(backup_name)
				var zip_result = SaveUtils.create_save_zip(modded_path, backup_zip_path)
				if not zip_result:
					print("[_delete_steam_save] Warning: Failed to backup modded saves")

	# 执行删除
	var deleted_any = false

	# 删除原版存档
	if DirAccess.dir_exists_absolute(steam_path):
		if _delete_directory_recursive(steam_path):
			deleted_any = true
			print("[_delete_steam_save] Deleted: ", steam_path)
		else:
			print("[_delete_steam_save] Failed to delete: ", steam_path)

	# 删除模组存档
	if DirAccess.dir_exists_absolute(modded_path):
		if _delete_directory_recursive(modded_path):
			deleted_any = true
			print("[_delete_steam_save] Deleted: ", modded_path)
		else:
			print("[_delete_steam_save] Failed to delete: ", modded_path)

	# 重新加载存档列表
	load_saves()

	if deleted_any:
		if do_backup:
			show_notification(translate_fmt("steam_save_deleted_backup", [steam_id]), true)
		else:
			show_notification(translate_fmt("steam_save_deleted_no_backup", [steam_id]), true)
	else:
		show_notification(translate("save_not_found"), false)


# 递归删除目录
func _delete_directory_recursive(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true  # 目录不存在视为成功

	var dir = DirAccess.open(path)
	if dir == null:
		return false

	# 先删除所有子文件和子目录
	dir.list_dir_begin()
	var item = dir.get_next()
	while item != "":
		var item_path = path.path_join(item)
		if dir.current_is_dir():
			if not _delete_directory_recursive(item_path):
				return false
		else:
			if DirAccess.remove_absolute(item_path) != OK:
				return false
		item = dir.get_next()
	dir.list_dir_end()

	# 最后删除目录本身
	if DirAccess.remove_absolute(path) != OK:
		return false

	return true


# 强制删除目录（使用命令行）
func _delete_directory_force(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true

	print("[_delete_directory_force] Force deleting: ", path)

	var output = []

	# 方法1：使用 PowerShell 的 Invoke-Expression（更可靠地处理空格）
	var ps_path = path.replace("/", "\\")
	# 使用 -Command 直接执行字符串
	var cmd_str = "Remove-Item -LiteralPath \\\"" + ps_path + "\\\" -Recurse -Force -ErrorAction SilentlyContinue"
	var exit_code = OS.execute("powershell", ["-NoProfile", "-Command", cmd_str], output, true)

	print("[_delete_directory_force] PowerShell exit code: ", exit_code)
	print("[_delete_directory_force] PowerShell output: ", output)

	if exit_code == 0 or exit_code == -1:
		if not DirAccess.dir_exists_absolute(path):
			print("[_delete_directory_force] Success!")
			return true

	# 方法2：如果PowerShell失败，使用 robocopy（更可靠）
	print("[_delete_directory_force] Trying robocopy method...")
	output = []
	# 创建一个空目录作为源，然后用robocopy /mir删除目标
	var empty_dir = OS.get_cache_dir().path_join("empty_for_delete")
	if DirAccess.dir_exists_absolute(empty_dir):
		_delete_directory_recursive(empty_dir)
	DirAccess.make_dir_recursive_absolute(empty_dir)

	exit_code = OS.execute("robocopy", [empty_dir, ps_path, "/MIR", "/NFL", "/NDL", "/NJH", "/NJS"], output, true)
	print("[_delete_directory_force] robocopy exit code: ", exit_code)

	# robocopy返回值：0=没有复制，1-7=成功或部分成功，8+=错误
	if exit_code <= 7:
		# 删除空的源目录
		_delete_directory_recursive(empty_dir)
		if not DirAccess.dir_exists_absolute(path):
			print("[_delete_directory_force] robocopy success!")
			return true

	print("[_delete_directory_force] All methods failed")
	return false


# 创建导入存档项
func _create_imported_save_item(info: Dictionary, is_modded: bool = false) -> Control:
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(200, 50)

	var vbox = VBoxContainer.new()
	container.add_child(vbox)

	# 简化存档名（截取前16个字符）
	var raw_name = info.get("name", "导入的存档")
	var display_name = _truncate_save_name(raw_name)

	if is_modded:
		display_name += " (模组版)"

	# 存档名
	var name_label = Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = raw_name  # 鼠标悬停显示完整名称
	vbox.add_child(name_label)

	# 存档槽位
	var profiles = info.get("modded_profiles", []) if is_modded else info.get("profiles", [])
	var profiles_text = "存档: " + ("1,2,3" if profiles.size() == 3 else str(profiles).replace("[", "").replace("]", ""))
	var profile_label = Label.new()
	profile_label.text = profiles_text
	profile_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(profile_label)

	# 最新时间
	var latest_date = info.get("latest_modded_date", "未知") if is_modded else info.get("latest_date", "未知")
	var date_label = Label.new()
	date_label.text = translate_fmt("latest_date", [latest_date])
	date_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(date_label)

	# 点击事件 - 显示详情
	container.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_imported_save_selected(info, is_modded)
	)

	return container


# 分组存档选中回调
func _on_group_save_selected(info: Dictionary, is_modded: bool) -> void:
	print("[_on_group_save_selected] Selected: ", info, " is_modded: ", is_modded)

	# 保存当前选中的存档信息
	current_save_steam_id = info.get("steam_id", "")
	current_save_is_modded = is_modded
	current_save_profiles = info.get("profiles", [])

	# 先清除详情面板的旧数据
	if save_details_name:
		save_details_name.text = ""
	if save_details_date:
		save_details_date.text = ""
	if save_details_size:
		save_details_size.text = ""
	if save_details_type:
		save_details_type.text = ""

	# 显示存档详情
	if save_details_panel:
		save_details_panel.visible = true

	var steam_id = info.get("steam_id", "")
	var name = info.get("name", "未知")

	if save_details_name:
		save_details_name.text = name + (" (模组版)" if is_modded else "")

	# 更新 Profile 选择器
	if save_profile_selector:
		save_profile_selector.clear()
		var has_p1 = 1 in current_save_profiles
		var has_p2 = 2 in current_save_profiles
		var has_p3 = 3 in current_save_profiles

		if has_p1:
			save_profile_selector.add_item("Profile 1", 1)
		if has_p2:
			save_profile_selector.add_item("Profile 2", 2)
		if has_p3:
			save_profile_selector.add_item("Profile 3", 3)

		# 默认选中 Profile 1
		current_selected_profile = 1
		save_profile_selector.selected = 0

	# 显示日期信息
	if save_details_date:
		var latest_date = info.get("latest_date", "未知")
		save_details_date.text = "日期: " + latest_date

	# 显示大小信息
	if save_details_size:
		var size_kb = info.get("size_kb", 0)
		if typeof(size_kb) != TYPE_INT:
			size_kb = 0
		var size_str = str(size_kb) + " KB"
		if size_kb > 1024:
			size_str = "%.2f MB" % [float(size_kb) / 1024.0]
		save_details_size.text = "大小: " + size_str

	if save_details_type:
		save_details_type.text = "类型: " + ("模组版" if is_modded else "原版") + " | SteamID: " + steam_id

	# 显示 Profile 1 的详细统计
	_print_save_details_for_profile(1)


# 导入存档选中回调
func _on_imported_save_selected(info: Dictionary, is_modded: bool = false) -> void:
	print("[_on_imported_save_selected] Selected: ", info, " is_modded: ", is_modded)

	# 保存当前选中的存档信息 - 只保存基础路径，is_modded单独标记
	current_save_steam_id = info.get("path", "")
	current_save_is_modded = is_modded

	# 根据是原版还是模组版获取对应的profiles
	current_save_profiles = info.get("modded_profiles", []) if is_modded else info.get("profiles", [])

	# 先清除详情面板的旧数据
	if save_details_name:
		save_details_name.text = ""
	if save_details_date:
		save_details_date.text = ""
	if save_details_size:
		save_details_size.text = ""
	if save_details_type:
		save_details_type.text = ""

	# 显示存档详情
	if save_details_panel:
		save_details_panel.visible = true

	var name = info.get("name", "导入的存档")

	if save_details_name:
		save_details_name.text = name + (" (模组版)" if is_modded else " (导入)")

	# 更新 Profile 选择器
	if save_profile_selector:
		save_profile_selector.clear()
		var has_p1 = 1 in current_save_profiles
		var has_p2 = 2 in current_save_profiles
		var has_p3 = 3 in current_save_profiles

		if has_p1:
			save_profile_selector.add_item("Profile 1", 1)
		if has_p2:
			save_profile_selector.add_item("Profile 2", 2)
		if has_p3:
			save_profile_selector.add_item("Profile 3", 3)

		# 默认选择第一个
		if save_profile_selector.item_count > 0:
			save_profile_selector.selected = 0
			current_selected_profile = save_profile_selector.get_item_id(0)

	# 显示存档信息
	if save_details_date:
		var latest_date = info.get("latest_modded_date", "未知") if is_modded else info.get("latest_date", "未知")
		save_details_date.text = "日期: " + latest_date

	if save_details_size:
		var size_kb = info.get("size_kb", 0)
		# 确保size_kb是数字类型
		if typeof(size_kb) != TYPE_INT:
			size_kb = 0
		var size_str = str(size_kb) + " KB"
		if size_kb > 1024:
			size_str = "%.2f MB" % [float(size_kb) / 1024.0]
		save_details_size.text = "大小: " + size_str

	if save_details_type:
		save_details_type.text = "类型: " + ("模组版" if is_modded else "原版") + " | " + name

	# 显示 Profile 1 的详细统计
	_print_save_details_for_profile(1)


# Profile选择器变化回调
func _on_profile_selector_changed(index: int) -> void:
	if save_profile_selector:
		current_selected_profile = save_profile_selector.get_item_id(index)
		print("[_on_profile_selector_changed] Selected profile: ", current_selected_profile)
		_print_save_details_for_profile(current_selected_profile)


# 存档左侧面板折叠/展开
func _on_save_collapse_pressed() -> void:
	if save_left_panel == null:
		return

	var left_panel_list = find_child_node(self, "LeftPanelList")
	var save_scroll = find_child_node(self, "SaveScroll")

	save_left_panel_collapsed = !save_left_panel_collapsed

	# 使用Tween实现平滑动画
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	if save_left_panel_collapsed:
		# 收起左侧面板 - 淡出 + 收缩
		if left_panel_list:
			var list_tween = create_tween()
			list_tween.set_ease(Tween.EASE_OUT)
			list_tween.set_trans(Tween.TRANS_CUBIC)
			list_tween.tween_property(left_panel_list, "modulate:a", 0.0, 0.2)
		if save_scroll:
			save_scroll.visible = false

		# 宽度收缩
		tween.tween_property(save_left_panel, "custom_minimum_size", Vector2(25, 0), 0.25)

		if save_collapse_btn:
			save_collapse_btn.text = ">"
	else:
		# 展开左侧面板 - 宽度展开 + 淡入
		# 设置初始状态 (不启用裁剪，让容器自然布局)
		save_left_panel.custom_minimum_size = Vector2(25, 0)

		if left_panel_list:
			left_panel_list.visible = true
			left_panel_list.modulate.a = 0.0

		if save_scroll:
			save_scroll.visible = true

		# 等待一帧让布局生效
		await get_tree().process_frame

		# 动画展开
		var expand_tween = create_tween()
		expand_tween.set_ease(Tween.EASE_OUT)
		expand_tween.set_trans(Tween.TRANS_CUBIC)

		# 宽度展开
		expand_tween.tween_property(save_left_panel, "custom_minimum_size", Vector2(250, 0), 0.25)

		# 淡入
		if left_panel_list:
			var list_tween = create_tween()
			list_tween.set_ease(Tween.EASE_OUT)
			list_tween.set_trans(Tween.TRANS_CUBIC)
			list_tween.tween_property(left_panel_list, "modulate:a", 1.0, 0.2)

		if save_collapse_btn:
			save_collapse_btn.text = "<"


func _refresh_save_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var container = find_child_node(self, "SaveContainer")
	if container:
		container.notify_property_list_changed()
		for child in container.get_children():
			child.notify_property_list_changed()
			child.queue_redraw()
	# 强制重新布局
	if save_left_panel:
		save_left_panel.get_parent().notify_property_list_changed()


# 滚动存档列表到底部
func _scroll_save_list_to_bottom() -> void:
	await get_tree().process_frame
	var save_scroll = find_child_node(self, "SaveScroll")
	if save_scroll:
		save_scroll.scroll_vertical = save_scroll.get_v_scroll_bar().max_value


# 存档选中回调
func _on_save_selected(save_data: Dictionary) -> void:
	var steam_id = save_data.get("steam_id", "")
	var is_imported = save_data.get("is_imported", false)

	# 先清除详情面板的旧数据
	if save_details_name:
		save_details_name.text = ""
	if save_details_date:
		save_details_date.text = ""
	if save_details_size:
		save_details_size.text = ""
	if save_details_type:
		save_details_type.text = ""

	# 先清除所有选中状态
	for id in save_panels:
		var panel_info = save_panels[id]
		if panel_info.has("bg"):
			panel_info["bg"].color = Color(0.13, 0.13, 0.13, 1)  # 取消选中（与模组一致）

	# 设置当前存档为选中状态
	var panel_key = steam_id
	if is_imported:
		panel_key = "imported_" + steam_id

	if save_panels.has(panel_key):
		var panel_info = save_panels[panel_key]
		if panel_info.has("bg"):
			panel_info["bg"].color = Color(0.25, 0.25, 0.25, 1.0)  # 选中后的背景色（与模组一致）

	# 更新备份时间显示
	_update_backup_time_display(panel_key)

	# 更新选中的存档ID
	if is_imported:
		selected_save_id = "imported_" + steam_id
	else:
		selected_save_id = steam_id

	print("[_on_save_selected] Selected: ", selected_save_id)

	# 显示存档详情
	if save_details_panel:
		save_details_panel.visible = true

	# 显示完整名称（包括SteamID和Profile）
	if save_details_name:
		save_details_name.text = save_data.get("full_name", save_data.get("name", "Unknown"))

	if save_details_date:
		save_details_date.text = "日期: " + save_data.get("date", "Unknown")

	if save_details_size:
		save_details_size.text = "大小: " + save_data.get("size", "Unknown")

	if save_details_type:
		var save_type = save_data.get("type", "unknown")
		var is_modded = save_data.get("is_modded", false)
		var has_current = save_data.get("has_current_save", false)
		var type_parts = []

		if save_type == "steam":
			type_parts.append("Steam存档")
		elif save_type == "modded":
			type_parts.append("模组版存档")
		else:
			type_parts.append("导入存档")

		if is_modded:
			type_parts.append("模组版")
		else:
			type_parts.append("原版")

		if has_current:
			type_parts.append("有当前游戏")

		# 显示Steam账号
		if not steam_id.is_empty():
			type_parts.append("账号: " + steam_id)

		save_details_type.text = "类型: " + " | ".join(type_parts)

	# 显示已备份状态
	if backed_up_saves.has(selected_save_id):
		print("[存档详情] 已备份位置: ", backed_up_saves[selected_save_id])

	# 显示详细游戏信息（角色胜率等）
	print("[存档详情] SteamID: ", save_data.get("steam_id", ""))
	print("[存档详情] Profile: ", save_data.get("profile", ""))
	print("[存档详情] 模组版: ", save_data.get("is_modded", false))
	print("[存档详情] 角色: ", save_data.get("characters", []))
	print("[存档详情] 总胜: ", save_data.get("total_wins", 0))
	print("[存档详情] 总败: ", save_data.get("total_losses", 0))
	print("[存档详情] 游戏时间: ", save_data.get("play_time", 0), "秒")
	print("[存档详情] 爬楼层数: ", save_data.get("floors_climbed", 0))
	print("[存档详情] 已备份: ", backed_up_saves.has(selected_save_id))


# 应用搜索和排序
func apply_filters_and_sort() -> void:
	print("=== apply_filters_and_sort ===")
	print("mods数量: ", mods.size())
	displayed_mods.clear()

	# 过滤
	for mod in mods:
		var mod_name = mod.get("name", "").to_lower()
		var search_text = current_search.to_lower()

		# 搜索过滤
		var search_match = search_text.is_empty() or mod_name.contains(search_text)

		# 分类过滤
		var category_match = true
		if current_category != "all":
			var affects_gameplay = mod.get("affects_gameplay", false)
			if current_category == "gameplay":
				category_match = affects_gameplay
			elif current_category == "cosmetic":
				category_match = not affects_gameplay

		if search_match and category_match:
			displayed_mods.append(mod)

	# 排序
	match current_sort:
		"name":
			displayed_mods.sort_custom(func(a, b): return a.get("name", "") < b.get("name", ""))
		"install_time":
			displayed_mods.sort_custom(func(a, b): return a.get("install_time", 0) > b.get("install_time", 0))
		"version":
			displayed_mods.sort_custom(func(a, b): return a.get("version", "") < b.get("version", ""))
		"author":
			displayed_mods.sort_custom(func(a, b): return a.get("author", "") < b.get("author", ""))

	print("displayed_mods数量: ", displayed_mods.size())


# 更新模组列表显示
func update_mod_list_display() -> void:
	"""刷新模组列表显示（统一走新建代码构建流程）"""
	_build_mod_list_with_boxes()

func _on_mod_batch_toggled(mod_data: Dictionary, toggled_on: bool) -> void:
	print("=== batch toggle ===", mod_data.get("name", ""), toggled_on)

	# 获取所有选中的模组
	var selected_mods = []
	for mod_id in mod_items:
		if mod_items[mod_id].get_selected():
			selected_mods.append(mod_id)

	if selected_mods.is_empty():
		_update_selected_count()
		return

	print("批量切换选中的模组数量: ", selected_mods.size())

	if toggled_on:
		# 批量启用 - 检查依赖
		var mods_to_enable = []
		for mod_id in selected_mods:
			for mod in mods:
				if mod.get("id") == mod_id:
					mods_to_enable.append(mod)
					break

		# 先检查所有依赖
		var all_disabled_deps: Array = []
		for mod in mods_to_enable:
			var dep_check = _check_deps_enabled(mod)
			var disabled = dep_check.get("disabled_deps", [])
			for dep in disabled:
				if dep not in all_disabled_deps:
					all_disabled_deps.append(dep)

		if not all_disabled_deps.is_empty():
			# 有未启用的依赖，显示确认对话框
			_show_dependency_enable_dialog(mods_to_enable[0] if not mods_to_enable.is_empty() else mod_data, all_disabled_deps, func():
				# 用户确认，一并启用依赖
				for dep_id in all_disabled_deps:
					for mod in mods:
						if mod.get("id") == dep_id:
							var success = ModUtils.enable_mod(mod, game_path)
							if success:
								enabled_mods[dep_id] = true
								if mod_items.has(dep_id):
									mod_items[dep_id].update_enabled_status(true)
							break
				# 然后启用选中的模组
				for mod in mods_to_enable:
					var mod_id = mod.get("id", "")
					var success = ModUtils.enable_mod(mod, game_path)
					if success:
						enabled_mods[mod_id] = true
						if mod_items.has(mod_id):
							mod_items[mod_id].update_enabled_status(true)
				_save_current_tag_mods()
				_save_tag_data()
				_save_enabled_mods()
			, func():
				# 用户取消，恢复复选框状态
				for mod in mods_to_enable:
					var mod_id = mod.get("id", "")
					for key in mod_items:
							if key.begins_with(mod_id + "_") or key == mod_id:
								mod_items[key].update_enabled_status(false)
								break
			)
			_update_selected_count()
			return

		# 没有依赖问题，直接启用
		for mod in mods_to_enable:
			var mod_id = mod.get("id", "")
			var success = ModUtils.enable_mod(mod, game_path)
			if success:
				enabled_mods[mod_id] = true
				for key in mod_items:
						if key.begins_with(mod_id + "_") or key == mod_id:
							mod_items[key].update_enabled_status(true)
							break
	else:
		# 批量停用
		for mod_id in selected_mods:
			for mod in mods:
				if mod.get("id") == mod_id:
					var success = ModUtils.disable_mod(mod, game_path)
					if success:
						enabled_mods[mod_id] = false
						if mod_items.has(mod_id):
							mod_items[mod_id].update_enabled_status(false)
					break

	# 更新选中数量显示
	_update_selected_count()

	# 保存当前标签的启用模组
	_save_current_tag_mods()
	_save_tag_data()
	# 保存模组启用状态到配置文件
	_save_enabled_mods()


# 模组复选框状态变化
func _on_mod_toggled(mod_data: Dictionary, toggled_on: bool) -> void:
	print("=== _on_mod_toggled called ===", mod_data.get("name", ""), "toggled:", toggled_on, "_all_selected:", _all_selected)
	var mod_id = mod_data.get("id", "")
	if mod_id.is_empty():
		return

	# 如果已启用整合包，禁止切换模组
	if not active_bundle.is_empty():
		show_notification(translate("bundle_active_tag_locked"), false)
		# 恢复复选框状态
		for key in mod_items:
			if key.begins_with(mod_id + "_") or key == mod_id:
				mod_items[key].update_enabled_status(not toggled_on)
				break
		return

	# 如果在全选模式下，点击复选框时启用/禁用所有模组
	if _all_selected:
		print("=== in all_selected mode ===")
		if toggled_on:
			# 全选模式下点击勾选 -> 启用所有模组
			_enable_all_mods()
		else:
			# 全选模式下点击取消勾选 -> 停用所有模组
			_disable_all_mods()
		# 退出全选模式
		_all_selected = false
		if batch_select_button:
			batch_select_button.text = translate("select_all")
		# 取消所有列表项的选中状态
		for id in mod_items:
			mod_items[id].set_selected(false)
		return

	if toggled_on:
		# 启用模组 - 先检查依赖
		var dep_check = _check_deps_enabled(mod_data)
		var missing_deps = mod_data.get("missing_dependencies", [])

		if not missing_deps.is_empty():
			# 有缺少的依赖，显示警告对话框
			_on_mod_toggled_continue_with_warning(mod_data, missing_deps, dep_check)
		elif not dep_check.get("can_enable", true) and not dep_check.get("disabled_deps", []).is_empty():
			# 依赖已安装但未启用，弹出确认对话框
			_on_mod_toggled_check_deps(mod_data, dep_check.get("disabled_deps", []))
		else:
			# 可以直接启用
			_do_enable_mod(mod_data)
	else:
		# 禁用模组
			var success = ModUtils.disable_mod(mod_data, game_path)
			if success:
				enabled_mods[mod_id] = false
				_save_enabled_mods()
				# 查找并更新UI
				for key in mod_items:
					if key.begins_with(mod_id + "_") or key == mod_id:
						mod_items[key].update_enabled_status(false)
						break
			else:
				# 恢复复选框状态
				show_notification(translate("mod_disable_failed"), false)
				for key in mod_items:
					if key.begins_with(mod_id + "_") or key == mod_id:
						mod_items[key].update_enabled_status(true)
						break

	# 保存当前标签的启用模组
	_save_current_tag_mods()
	_save_tag_data()
	# 保存模组启用状态到配置文件
	_save_enabled_mods()


# 处理启用模组 - 检查未启用的依赖
func _on_mod_toggled_check_deps(mod_data: Dictionary, disabled_deps: Array) -> void:
	var mod_id = mod_data.get("id", "")

	# 显示确认对话框，询问是否一并启用依赖
	_show_dependency_enable_dialog(mod_data, disabled_deps, func():
		# 用户确认启用（包括依赖）
		_do_enable_mod(mod_data)
	, func():
		# 用户取消，不启用
		for key in mod_items:
				if key.begins_with(mod_id + "_") or key == mod_id:
					mod_items[key].update_enabled_status(false)
					break
	)


# 处理启用模组 - 有缺少的依赖时的警告
func _on_mod_toggled_continue_with_warning(mod_data: Dictionary, missing_deps: Array, dep_check: Dictionary) -> void:
	var mod_id = mod_data.get("id", "")

	# 弹出警告对话框，询问是否仍要启用
	_show_missing_dep_warning_dialog(mod_data, func():
		# 用户确认仍要启用
		# 检查是否有未启用的依赖
		if not dep_check.get("can_enable", true) and not dep_check.get("disabled_deps", []).is_empty():
			# 有未启用的依赖，弹出确认对话框
			_show_dependency_enable_dialog(mod_data, dep_check.get("disabled_deps", []), func():
				_do_enable_mod(mod_data)
			, func():
				for key in mod_items:
						if key.begins_with(mod_id + "_") or key == mod_id:
							mod_items[key].update_enabled_status(false)
							break
			)
		else:
			_do_enable_mod(mod_data)
	, func():
		# 用户取消，不启用
		for key in mod_items:
				if key.begins_with(mod_id + "_") or key == mod_id:
					mod_items[key].update_enabled_status(false)
					break
	)


# 执行启用模组的实际逻辑
func _do_enable_mod(mod_data: Dictionary) -> void:
	var mod_id = mod_data.get("id", "")
	if mod_id.is_empty():
		return

	var success = ModUtils.enable_mod(mod_data, game_path)
	if success:
		enabled_mods[mod_id] = true
		_save_enabled_mods()
		# 查找并更新UI
		for key in mod_items:
			if key.begins_with(mod_id + "_") or key == mod_id:
				mod_items[key].update_enabled_status(true)
				break
	else:
		# 恢复复选框状态
		for key in mod_items:
			if key.begins_with(mod_id + "_") or key == mod_id:
				mod_items[key].update_enabled_status(false)
				break


# 设置模组启用/禁用状态
func _set_mod_enabled(mod_id: String, enabled: bool) -> void:
	# 查找模组数据
	var mod_data = {}
	for mod in mods:
		if mod.get("id", "") == mod_id:
			mod_data = mod
			break

	if mod_data.is_empty():
		return

	if enabled:
		_do_enable_mod(mod_data)
	else:
		var success = ModUtils.disable_mod(mod_data, game_path)
		if success:
			enabled_mods.erase(mod_id)
			_save_enabled_mods()
			# 查找并更新UI
			for key in mod_items:
				if key.begins_with(mod_id + "_") or key == mod_id:
					mod_items[key].update_enabled_status(false)
					break


# 模组选中（显示详情）
func _on_mod_selected(mod_data: Dictionary, toggled: bool = false) -> void:
	# 如果在全选模式下，点击任意模组则退出全选模式
	if _all_selected:
		_all_selected = false
		if batch_select_button:
			batch_select_button.text = translate("select_all")
		# 不执行后续的单选逻辑，直接返回
		# 因为全选模式下点击只是退出全选模式

	# 多选模式下不执行单选逻辑
	if multi_select_mode:
		# 在多选模式下，toggled为true表示选中，false表示取消选中
		# 模组项已经在mod_item中处理了选中状态变化
		_update_selected_count()
		return

	# 单选模式：先清除所有选中状态
	for mod_id in mod_items:
		mod_items[mod_id].set_selected(false)

	# 设置当前模组为选中状态
	var mod_id = mod_data.get("id", "")
	for key in mod_items:
		if key.begins_with(mod_id + "_") or key == mod_id:
			mod_items[mod_id].set_selected(true)
			selected_mod_id = mod_id

	# 显示模组详情
	current_mod_data = mod_data
	_show_mod_details(mod_data)


# 显示模组详情
func _show_mod_details(mod_data: Dictionary) -> void:
	if mod_details_panel:
		mod_details_panel.visible = true

	if mod_details_name:
		mod_details_name.text = mod_data.get("name", "Unknown")

	if mod_details_author:
		mod_details_author.text = translate_fmt("author", [mod_data.get("author", "Unknown")])

	if mod_details_version:
		mod_details_version.text = translate_fmt("version", [mod_data.get("version", "v1.0.0")])

	if mod_details_source:
		var download_source = mod_data.get("download_source", "")
		if not download_source.is_empty():
			if download_source == "nexus" or download_source == "nexusmods":
				mod_details_source.text = translate_fmt("mod_source", ["N网"])
				mod_details_source.add_theme_color_override("font_color", Color("#ffcc00"))
			else:
				mod_details_source.text = translate_fmt("mod_source", [download_source])
				mod_details_source.add_theme_color_override("font_color", Color("#ffcc00"))
		else:
			mod_details_source.text = translate_fmt("mod_source", ["-"])

	if mod_details_type:
		var affects_gameplay = mod_data.get("affects_gameplay", false)
		var type_str = translate("gameplay_mods") if affects_gameplay else translate("cosmetic_mods")
		mod_details_type.text = translate_fmt("mod_type", [type_str])

	if mod_details_desc:
		mod_details_desc.text = translate_fmt("mod_desc", [mod_data.get("description", "N/A")])

	# 显示缺少依赖
	var missing_deps = mod_data.get("missing_dependencies", [])
	if mod_details_dep:
		if not missing_deps.is_empty():
			var dep_text = "缺少依赖: " + ", ".join(missing_deps)
			mod_details_dep.text = dep_text
			mod_details_dep.visible = true
			# 设置红色文字
			mod_details_dep.add_theme_color_override("font_color", Color("#ff5555"))
		else:
			mod_details_dep.visible = false

	# 懒加载备注编辑按钮
	if not mod_note_edit_btn:
		var btn = Button.new()
		btn.name = "ModNoteEditBtn"
		btn.text = "📝"
		btn.tooltip_text = translate("mod_note_edit")
		btn.custom_minimum_size = Vector2(32, 32)
		# 添加到DetailsVBox
		if mod_details_vbox:
			mod_details_vbox.add_child(btn)
		mod_note_edit_btn = btn

	# 连接备注编辑按钮信号
	if mod_note_edit_btn and not mod_note_edit_btn.pressed.is_connected(_on_mod_note_edit_btn_pressed):
		mod_note_edit_btn.pressed.connect(_on_mod_note_edit_btn_pressed)

	# 懒加载分割线
	if not mod_note_separator:
		var sep = HSeparator.new()
		sep.name = "ModNoteSeparator"
		# 添加到DetailsVBox
		if mod_details_vbox:
			mod_details_vbox.add_child(sep)
		mod_note_separator = sep

	# 懒加载备注显示Label
	if not mod_note_label:
		var lbl = Label.new()
		lbl.name = "ModNoteLabel"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# 添加到DetailsVBox
		if mod_details_vbox:
			mod_details_vbox.add_child(lbl)
		mod_note_label = lbl

	# 显示备注（如果存在）
	var displayed_mod_id = mod_data.get("id", "")
	_refresh_mod_note_display(displayed_mod_id)


# 搜索文本变化
func _on_search_text_changed(text: String) -> void:
	current_search = text
	apply_filters_and_sort()
	update_mod_list_display()


# 搜索按钮点击
func _on_search_button_pressed() -> void:
	apply_filters_and_sort()
	update_mod_list_display()


# 安装模组按钮点击
func _on_install_mod_pressed() -> void:
	# 打开文件选择对话框
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.zip"]
	file_dialog.title = translate("select_mod_file")

	# 设置回调
	file_dialog.file_selected.connect(_on_mod_file_selected)

	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))


# 文件选择回调
func _on_mod_file_selected(path: String) -> void:
	# 直接调用统一的安装函数
	install_mod_from_path(path)


# 调试日志写入文件
func _debug_log(msg: String) -> void:
	print(msg)
	var log_path = get_base_path() + "debug.log"
	var log_file = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if log_file:
		log_file.seek_end()
		log_file.store_string(msg + "\n")
		log_file.close()
	else:
		log_file = FileAccess.open(log_path, FileAccess.WRITE)
		if log_file:
			log_file.store_string(msg + "\n")
			log_file.close()


# 打印场景树结构
func _print_scene_tree(node: Node, indent: int) -> void:
	var spaces = "  ".repeat(indent)
	var visible_str = "" if node.visible else " [HIDDEN]"
	var size_str = ""
	if node is Control:
		var c = node as Control
		size_str = " pos=" + str(c.position) + " size=" + str(c.size)
	print(spaces + node.name + ":" + node.get_class() + visible_str + size_str)
	for child in node.get_children():
		_print_scene_tree(child, indent + 1)


# 打印存档UI树结构（调试用）
func _print_save_ui_tree() -> void:
	print("=== [DEBUG] 打印存档UI树结构 ===")
	var tab_container = find_child_node(self, "TabContainer")
	if tab_container:
		var save_tab = find_child_node(tab_container, "SaveTab")
		if save_tab:
			_print_save_ui_recursive(save_tab, 0)
		else:
			print("ERROR: SaveTab not found!")
	else:
		print("ERROR: TabContainer not found!")


func _print_save_ui_recursive(node: Node, indent: int) -> void:
	var spaces = "  ".repeat(indent)
	var size_str = ""
	if node is Control:
		var c = node as Control
		size_str = " size=" + str(c.size) + " min=" + str(c.custom_minimum_size)
		if node is ScrollContainer:
			var sc = node as ScrollContainer
			size_str += " h_scroll=" + str(sc.h_scroll_mode) + " v_scroll=" + str(sc.v_scroll_mode)
		elif node is VBoxContainer:
			var vbc = node as VBoxContainer
			size_str += " separation=" + str(vbc.get_theme_constant("separation"))
	print(spaces + node.name + ":" + node.get_class() + size_str)
	for child in node.get_children():
		_print_save_ui_recursive(child, indent + 1)


# 打印TabContainer树结构
func _print_tab_container_tree() -> void:
	print("=== [DEBUG] 打印TabContainer树 ===")
	var tc = find_child_node(self, "TabContainer")
	if tc:
		_print_save_ui_recursive(tc, 0)
	else:
		print("ERROR: TabContainer not found!")


# 打印存档详细统计信息
func _print_save_details(steam_id: String, profiles: Array, is_modded: bool) -> void:
	print("=== [存档详情] SteamID: ", steam_id, " 模组版: ", is_modded, " 槽位: ", profiles)

	var base_path = save_path.path_join(steam_id)
	if is_modded:
		base_path = base_path.path_join("modded")

	print("[存档详情] base_path: ", base_path)

	# 汇总各profile的统计数据
	var total_wins = 0
	var total_losses = 0
	var total_cards = 0
	var total_relics = 0
	var total_playtime = 0
	var characters = {}

	for profile_num in profiles:
		var profile_path = base_path.path_join("profile" + str(profile_num))
		var saves_path = profile_path.path_join("saves")
		var progress_path = saves_path.path_join("progress.save")

		print("[存档详情] 检查 profile", profile_num, ": ", progress_path)
		print("[存档详情] 文件存在: ", FileAccess.file_exists(progress_path))

		if FileAccess.file_exists(progress_path):
			print("[存档详情] 读取 profile", profile_num, " 的 progress.save")
			var progress_info = SaveUtils.parse_progress_save(progress_path)
			print("[存档详情] profile", profile_num, " 数据: ", progress_info)
			total_wins += progress_info.get("total_wins", 0)
			total_losses += progress_info.get("total_losses", 0)
			total_cards += progress_info.get("discovered_cards", 0)
			total_relics += progress_info.get("discovered_relics", 0)
			total_playtime += progress_info.get("play_time", 0)

			# 合并角色统计
			for char in progress_info.get("characters", []):
				var char_name = char.get("name", "UNKNOWN")
				if not characters.has(char_name):
					characters[char_name] = {"wins": 0, "losses": 0}
				characters[char_name]["wins"] += char.get("wins", 0)
				characters[char_name]["losses"] += char.get("losses", 0)

	print("[存档详情] 总胜: ", total_wins)
	print("[存档详情] 总败: ", total_losses)
	print("[存档详情] 角色: ", characters)
	print("[存档详情] 游戏时间: ", total_playtime, "秒")
	print("[存档详情] 发现卡牌: ", total_cards)
	print("[存档详情] 发现遗物: ", total_relics)


# 打印指定Profile的存档详细统计信息
func _print_save_details_for_profile(profile_num: int) -> void:
	var steam_id = current_save_steam_id
	var is_modded = current_save_is_modded
	var profiles = current_save_profiles

	print("=== [Profile ", profile_num, " 详情] SteamID: ", steam_id, " 模组版: ", is_modded)

	# 判断是否是导入的存档
	var base_path: String

	# 检查是否是导入的存档（steam_id不是纯数字ID）
	if not steam_id.is_valid_int():
		# 导入的存档 - 使用完整路径
		base_path = steam_id
		if is_modded:
			base_path = base_path.path_join("modded")
	else:
		# Steam存档
		base_path = save_path.path_join(steam_id)
		if is_modded:
			base_path = base_path.path_join("modded")

	var profile_path = base_path.path_join("profile" + str(profile_num))
	var saves_path = profile_path.path_join("saves")
	var progress_path = saves_path.path_join("progress.save")

	print("[Profile详情] 路径: ", progress_path)
	print("[Profile详情] 文件存在: ", FileAccess.file_exists(progress_path))

	# 读取单个profile的数据
	var total_wins = 0
	var total_losses = 0
	var total_cards = 0
	var total_relics = 0
	var total_playtime = 0
	var characters = {}

	if FileAccess.file_exists(progress_path):
		var progress_info = SaveUtils.parse_progress_save(progress_path)
		print("[Profile详情] 数据: ", progress_info)

		total_wins = progress_info.get("total_wins", 0)
		total_losses = progress_info.get("total_losses", 0)
		total_cards = progress_info.get("discovered_cards", 0)
		total_relics = progress_info.get("discovered_relics", 0)
		total_playtime = progress_info.get("play_time", 0)
		characters = {}

		# 获取角色统计
		for char in progress_info.get("characters", []):
			var char_name = char.get("name", "UNKNOWN")
			characters[char_name] = {
				"wins": char.get("wins", 0),
				"losses": char.get("losses", 0)
			}

	# 更新详情面板显示
	if save_details_date:
		# 格式化时间
		var hours = int(total_playtime) / 3600
		var minutes = (int(total_playtime) % 3600) / 60
		var seconds = int(total_playtime) % 60
		var time_str = "%02d:%02d:%02d" % [hours, minutes, seconds]
		save_details_date.text = "游戏时间: " + time_str

	if save_details_size:
		save_details_size.text = "Profile " + str(profile_num) + " | 卡牌: " + str(total_cards) + " | 遗物: " + str(total_relics)

	# 显示角色统计数据到UI
	if char_stats_vbox:
		# 清除现有内容
		for child in char_stats_vbox.get_children():
			child.queue_free()

		# 添加总战绩
		var total_label = Label.new()
		total_label.text = "总战绩: " + str(total_wins) + " 胜 / " + str(total_losses) + " 败"
		total_label.add_theme_font_size_override("font_size", 14)
		char_stats_vbox.add_child(total_label)

		# 添加各角色统计
		var char_title = Label.new()
		char_title.text = "────────── 角色统计 ──────────"
		char_stats_vbox.add_child(char_title)

		# 角色名称映射
		var char_names = {
			"CHARACTER.IRONCLAD": "铁甲战士",
			"CHARACTER.SILENT": "静默猎手",
			"CHARACTER.REGENT": "储君",
			"CHARACTER.NECROBINDER": "亡灵契约师",
			"CHARACTER.DEFECT": "故障机器人"
		}

		# 按游玩时间排序的角色
		var char_list = []
		for char_name in characters:
			char_list.append({
				"id": char_name,
				"name": char_names.get(char_name, char_name),
				"wins": characters[char_name].wins,
				"losses": characters[char_name].losses
			})

		# 显示角色
		for char_data in char_list:
			var char_label = Label.new()
			var record = str(int(char_data.wins)) + "胜 / " + str(int(char_data.losses)) + "败"
			char_label.text = char_data.name + ": " + record
			char_label.add_theme_font_size_override("font_size", 13)
			char_stats_vbox.add_child(char_label)

		# 如果没有角色数据
		if characters.is_empty():
			var no_data_label = Label.new()
			no_data_label.text = "暂无角色数据"
			char_stats_vbox.add_child(no_data_label)

	# 显示详细统计到日志
	print("[Profile详情] 游戏时间: ", total_playtime, "秒 = ", _format_playtime(total_playtime))
	print("[Profile详情] 总胜: ", total_wins)
	print("[Profile详情] 总败: ", total_losses)
	print("[Profile详情] 角色统计:")
	for char_name in characters:
		var c = characters[char_name]
		print("  ", char_name, ": 胜=", c.wins, " 败=", c.losses)


# 格式化游玩时间
func _format_playtime(seconds: int) -> String:
	var hours = seconds / 3600
	var minutes = (seconds % 3600) / 60
	var secs = seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, secs]


# 显示通知消息
func show_notification(message: String, is_success: bool) -> void:
	# 如果已有通知，先移除
	var existing = get_node_or_null("TempNotification")
	if existing:
		existing.queue_free()

	# 创建通知面板
	var notif_panel = Panel.new()
	notif_panel.name = "TempNotification"
	notif_panel.z_index = 100

	# 设置样式
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.95) if is_success else Color(0.4, 0.15, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.7, 0.2, 1) if is_success else Color(0.7, 0.2, 0.2, 1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	notif_panel.add_theme_stylebox_override("panel", style)

	# 添加到根节点以便居中显示
	get_tree().root.add_child(notif_panel)

	# 计算居中位置
	var screen_size = get_tree().root.get_visible_rect().size
	var lines = message.split("\n")
	var panel_height = min(100 + lines.size() * 25, 300)
	var panel_width = min(350 + message.length() * 3, 500)
	notif_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	var x = (screen_size.x - panel_width) / 2
	var y = (screen_size.y - panel_height) / 2
	notif_panel.position = Vector2i(x, y)

	# 添加标题标签
	var title_label = Label.new()
	title_label.text = translate("success") if is_success else translate("error")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", Color(0.2, 0.7, 0.2, 1) if is_success else Color(0.9, 0.3, 0.3, 1))
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.position = Vector2(0, 10)
	title_label.size = Vector2(panel_width, 30)
	notif_panel.add_child(title_label)

	# 添加消息标签
	var msg_label = Label.new()
	msg_label.text = message
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	msg_label.position = Vector2(10, 45)
	msg_label.size = Vector2(panel_width - 20, panel_height - 55)
	notif_panel.add_child(msg_label)

	# 如果有 click_action，设置可点击
	var click_action = get("notification_click_action")
	if click_action != null and click_action != "":
		notif_panel.gui_input.connect(_on_notification_clicked)

	# 3秒后自动移除
	var timer = get_tree().create_timer(3.0)
	timer.timeout.connect(func():
		if is_instance_valid(notif_panel):
			notif_panel.queue_free()
			notification_click_action = ""
	)


# 通知面板点击处理
func _on_notification_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var action = notification_click_action
		print("[_on_notification_clicked] action: ", action)
		notification_click_action = ""

		if action == "show_update_dialog":
			_show_update_dialog()


# 批量启用选中的模组
func _on_batch_enable_pressed() -> void:
	print("=== batch enable pressed ===")

	# 获取所有选中的模组
	var selected_mods = []
	for mod_id in mod_items:
		if mod_items[mod_id].get_selected():
			selected_mods.append(mod_id)

	if selected_mods.is_empty():
		print("没有选中的模组")
		return

	print("选中的模组数量: ", selected_mods.size())

	# 启用所有选中的模组
	var success_count = 0
	for mod_id in selected_mods:
		# 找到对应的mod数据
		for mod in mods:
			if mod.get("id") == mod_id:
				var success = ModUtils.enable_mod(mod, game_path)
				if success:
					enabled_mods[mod_id] = true
					mod_items[mod_id].update_enabled_status(true)
					success_count += 1
				break

	print("成功启用: ", success_count, " / ", selected_mods.size())

	# 如果在全选模式下操作完成，退出全选模式
	if _all_selected:
		_all_selected = false
		if batch_select_button:
			batch_select_button.text = translate("select_all")
		# 取消所有列表项的选中状态
		for mod_id in mod_items:
			mod_items[mod_id].set_selected(false)

	# 刷新列表显示（不调用load_mods避免触发_apply_tag_mods覆盖结果）
	apply_filters_and_sort()
	update_mod_list_display()


# 批量卸载选中的模组
func _on_batch_uninstall_pressed() -> void:
	# 复用批量停用逻辑
	_on_batch_disable_pressed()


# 批量停用选中的模组
func _on_batch_disable_pressed() -> void:
	print("=== batch disable pressed ===")

	# 获取所有选中的模组
	var selected_mods = []
	for mod_id in mod_items:
		if mod_items[mod_id].get_selected():
			selected_mods.append(mod_id)

	if selected_mods.is_empty():
		print("没有选中的模组")
		return

	print("选中的模组数量: ", selected_mods.size())

	# 停用所有选中的模组
	var success_count = 0
	var fail_count = 0
	for mod_id in selected_mods:
		# 找到对应的mod数据
		for mod in mods:
			if mod.get("id") == mod_id:
				var success = ModUtils.disable_mod(mod, game_path)
				if success:
					enabled_mods[mod_id] = false
					if mod_items.has(mod_id):
						mod_items[mod_id].update_enabled_status(false)
					success_count += 1
				else:
					fail_count += 1
				break
	# 持久化禁用状态到配置文件
	_save_enabled_mods()

	if fail_count > 0:
		show_notification(translate_fmt("mod_disable_partially_failed", [success_count, fail_count]), false)
	else:
		show_notification(translate_fmt("mods_disabled_count", [success_count]), true)
	print("成功停用: ", success_count, " / ", selected_mods.size())

	# 如果在全选模式下操作完成，退出全选模式
	if _all_selected:
		_all_selected = false
		if batch_select_button:
			batch_select_button.text = translate("select_all")
		# 取消所有列表项的选中状态
		for mod_id in mod_items:
			mod_items[mod_id].set_selected(false)

	# 刷新列表显示（不调用load_mods避免触发_apply_tag_mods覆盖结果）
	apply_filters_and_sort()
	update_mod_list_display()


# 卸载模组按钮点击
func _on_uninstall_mod_pressed() -> void:
	# 如果在全选模式下，点击卸载按钮清空临时mod文件夹
	if _all_selected:
		_clear_temp_mods()
		# 退出全选模式
		_all_selected = false
		if batch_select_button:
			batch_select_button.text = translate("select_all")
		# 重新加载模组列表
		load_mods()
		return

	# 如果在多选模式下，点击卸载按钮批量停用选中的模组
	if multi_select_mode:
		_on_batch_disable_pressed()
		return

	# 显示确认对话框，让用户选择要卸载的模组
	# 这里简化处理：先检查是否有选中的模组
	var selected_mod = _get_selected_mod()
	if selected_mod.is_empty():
		# 如果没有选中，提示用户选择
		print(translate("select_mod_to_uninstall"))
		return

	# 调用ModUtils卸载模组
	# 检查模组是否已启用
	var mod_id = selected_mod.get("id", "")
	if mod_id.is_empty():
		return

	var is_enabled = enabled_mods.get(mod_id, false)
	print("=== uninstall mod ===", mod_id, "enabled:", is_enabled)
	print("temp_mods path:", temp_mods_path.path_join(mod_id))
	print("temp exists:", DirAccess.dir_exists_absolute(temp_mods_path.path_join(mod_id)))

	var success = ModUtils.uninstall_mod(mod_id, is_enabled, game_path)
	print("uninstall success:", success)

	if success:
		# 重新加载模组列表
		load_mods()
		show_notification(translate("mod_uninstalled"), true)
	else:
		show_notification(translate("mod_uninstall_failed"), false)


# 获取当前选中的模组
func _get_selected_mod() -> Dictionary:
	if selected_mod_id.is_empty():
		return {}

	for mod in displayed_mods:
		var mod_id = mod.get("id", "")
		if mod_id == selected_mod_id:
			return mod

	return {}


# 排序选项变化
func _on_sort_option_selected(index: int) -> void:
	match index:
		0:
			current_sort = "name"
		1:
			current_sort = "install_time"
		2:
			current_sort = "version"
		3:
			current_sort = "author"
	apply_filters_and_sort()
	update_mod_list_display()


# 分类过滤选项变化
func _on_category_tag_clicked(tag_name: String) -> void:
	"""处理分类标签点击"""
	var category_tags = find_child_node(self, "TopBarBg/TopBar/CategoryTags")
	if not category_tags:
		return

	var new_category = "all"
	if "Gameplay" in tag_name:
		new_category = "gameplay"
	elif "Cosmetic" in tag_name:
		new_category = "cosmetic"

	current_category = new_category

	for ch in category_tags.get_children():
		if ch is Button:
			var is_active = false
			if "All" in ch.name and new_category == "all":
				is_active = true
			elif "Gameplay" in ch.name and new_category == "gameplay":
				is_active = true
			elif "Cosmetic" in ch.name and new_category == "cosmetic":
				is_active = true

			if is_active:
				ch.add_theme_stylebox_override("normal", ch.get_meta("active_style"))
				ch.add_theme_color_override("font_color", Color(0.4, 0.753, 0.976))
			else:
				if ch.get_meta("normal_style"):
					ch.add_theme_stylebox_override("normal", ch.get_meta("normal_style"))
				ch.add_theme_color_override("font_color", Color(0.545, 0.596, 0.627))

	apply_filters_and_sort()


func _on_category_filter_selected(index: int) -> void:
	match index:
		0:
			current_category = "all"
		1:
			current_category = "gameplay"
		2:
			current_category = "cosmetic"
	apply_filters_and_sort()
	update_mod_list_display()


# 全选/取消全选
var _all_selected: bool = false
var multi_select_mode: bool = false  # 多选模式
var selected_count_label: Label  # 选中数量标签

# 清空临时mod文件夹
func _clear_temp_mods() -> void:
	print("=== clear temp mods ===")
	var temp_path = temp_mods_path
	if DirAccess.dir_exists_absolute(temp_path):
		var dir = DirAccess.open(temp_path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name != "." and file_name != "..":
					var full_path = temp_path.path_join(file_name)
					if dir.current_is_dir():
						FileUtils.delete_directory(full_path)
					else:
						DirAccess.remove_absolute(full_path)
				file_name = dir.get_next()
			dir.list_dir_end()
			print("=== temp mods cleared ===")

	# 同时清空 test_mods 文件夹
	var test_path = get_base_path() + "test_mods"
	if DirAccess.dir_exists_absolute(test_path):
		var dir = DirAccess.open(test_path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name != "." and file_name != "..":
					var full_path = test_path.path_join(file_name)
					if dir.current_is_dir():
						FileUtils.delete_directory(full_path)
					else:
						DirAccess.remove_absolute(full_path)
				file_name = dir.get_next()
			dir.list_dir_end()
			print("=== test mods cleared ===")

	# 同时清空游戏 mods 文件夹（如果已设置游戏路径）
	if not game_path.is_empty():
		var game_mods_path = game_path.path_join("mods")
		if DirAccess.dir_exists_absolute(game_mods_path):
			var dir = DirAccess.open(game_mods_path)
			if dir:
				dir.list_dir_begin()
				var file_name = dir.get_next()
				while file_name != "":
					if file_name != "." and file_name != "..":
						var full_path = game_mods_path.path_join(file_name)
						if dir.current_is_dir():
							FileUtils.delete_directory(full_path)
						else:
							DirAccess.remove_absolute(full_path)
					file_name = dir.get_next()
				dir.list_dir_end()
				print("=== game mods cleared ===")

# 启用所有模组
func _enable_all_mods() -> void:
	print("=== enable all mods ===")
	for mod_id in mod_items:
		var mod_item = mod_items[mod_id]
		# 找到对应的mod数据，无条件启用
		for mod in mods:
			if mod.get("id") == mod_id:
				var success = ModUtils.enable_mod(mod, game_path)
				if success:
					enabled_mods[mod_id] = true
					mod_item.update_enabled_status(true)
				break
	# 保存当前标签的启用模组
	_save_current_tag_mods()
	_save_tag_data()
	# 保存模组启用状态到配置文件
	_save_enabled_mods()

	# 刷新列表显示（不调用load_mods避免触发_apply_tag_mods覆盖结果）
	apply_filters_and_sort()
	update_mod_list_display()

# 停用所有模组
func _disable_all_mods() -> void:
	print("=== disable all mods ===")
	for mod_id in mod_items:
		var mod_item = mod_items[mod_id]
		# 找到对应的mod数据，无条件停用
		for mod in mods:
			if mod.get("id") == mod_id:
				var success = ModUtils.disable_mod(mod, game_path)
				if success:
					enabled_mods[mod_id] = false
					mod_item.update_enabled_status(false)
				break
	# 保存当前标签的启用模组
	_save_current_tag_mods()
	_save_tag_data()
	# 保存模组启用状态到配置文件
	_save_enabled_mods()

	# 刷新列表显示（不调用load_mods避免触发_apply_tag_mods覆盖结果）
	apply_filters_and_sort()
	update_mod_list_display()

# 多选模式复选框切换
func _on_multi_select_toggled(toggled_on: bool) -> void:
	print("=== multi_select_toggled:", toggled_on)
	multi_select_mode = toggled_on
	if multi_select_mode:
		# 进入多选模式，设置所有项的多选模式，但不选中任何项
		for mod_id in mod_items:
			mod_items[mod_id].set_multi_select_mode(true)
			mod_items[mod_id].set_batch_toggle_callback(_on_mod_batch_toggled)
		# 显示选中数量
		if selected_count_label:
			selected_count_label.visible = true
		_update_selected_count()
	else:
		# 退出多选模式，取消所有选中状态，并关闭多选模式
		for mod_id in mod_items:
			mod_items[mod_id].set_selected(false)
			mod_items[mod_id].set_multi_select_mode(false)
		# 隐藏选中数量
		if selected_count_label:
			selected_count_label.visible = false


# 更新选中数量显示
func _update_selected_count() -> void:
	if selected_count_label == null:
		return
	var count = 0
	for mod_id in mod_items:
		if mod_items[mod_id].get_selected():
			count += 1
	selected_count_label.text = translate_fmt("selected_count", [count])


# 刷新模组列表
func _on_refresh_mods_pressed() -> void:
	print("=== 刷新模组列表 ===")
	load_mods()

	# 检测并修复 .bak 文件
	var fixed_count = _check_and_fix_bak_files()
	if fixed_count > 0:
		show_notification(translate("bak_files_repaired").format({"count": fixed_count}), true)


func _on_batch_select_pressed() -> void:
	print("=== batch select pressed ===")
	_all_selected = not _all_selected
	print("=== _all_selected:", _all_selected)
	if _all_selected:
		# 全选 - 选中所有列表项（视觉选中效果）
		for mod_id in mod_items:
			mod_items[mod_id].set_selected(true)
		if batch_select_button:
			batch_select_button.text = translate("cancel")
	else:
		# 取消全选 - 取消选中所有列表项
		for mod_id in mod_items:
			mod_items[mod_id].set_selected(false)
		if batch_select_button:
			batch_select_button.text = translate("select_all")


# 导入存档
func _on_import_save_pressed() -> void:
	if save_path.is_empty():
		print(translate("select_save_path"))
		return

	# 打开文件选择对话框
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.zip"]
	file_dialog.title = translate("select_save_file")

	# 设置回调
	file_dialog.file_selected.connect(_on_save_file_selected)

	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))


# 存档文件选择回调
func _on_save_file_selected(path: String) -> void:
	# 获取ZIP文件名作为存档名（去掉.zip后缀）
	var zip_file_name = path.get_file()
	var save_name = zip_file_name.get_basename()

	print("[_on_save_file_selected] Importing: ", path)
	print("[_on_save_file_selected] Target dir: ", temp_save_path)

	# 导入到temp_save目录
	var result = SaveUtils.import_save(path, temp_save_path, save_name)

	print("[_on_save_file_selected] Import result: ", result)

	if result.success:
		# 重新加载存档列表
		load_saves()
		# 提示成功
		print(translate("save_imported"))
		# 可选：选中新导入的存档
		selected_save_id = "imported_" + save_name
	else:
		print(translate("error") + ": " + result.message)


# 导出存档
func _on_export_save_pressed() -> void:
	if selected_save_id.is_empty():
		print(translate("select_save_to_export"))
		return

	# 找到选中的存档
	var save_data = _get_selected_save()
	if save_data.is_empty():
		return

	# 获取存档路径 - 可能是profile路径，需要获取账号目录
	var profile_path = save_data.get("path", "")
	if profile_path.is_empty():
		return

	# 获取账号目录（去掉 /profile1 等后缀）
	var account_path = profile_path
	# 如果路径包含profileX，获取父目录
	if "/profile" in account_path:
		account_path = account_path.get_base_dir()
	if "/saves" in account_path:
		account_path = account_path.get_base_dir()

	# 获取账号ID用于显示和文件名
	var steam_id = save_data.get("steam_id", "")
	var is_imported = save_data.get("is_imported", false)
	# 导入存档使用name作为标识符
	if steam_id.is_empty():
		steam_id = save_data.get("name", "")

	# 打开保存文件对话框
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.zip"]
	file_dialog.title = translate("export_save")

	# 使用账号目录路径进行导出
	file_dialog.file_selected.connect(func(path: String):
		# 显示加载动画
		_show_loading(translate("exporting_save"))

		# 使用call_deferred确保UI先更新
		call_deferred("_do_export_save", account_path, path)
	)

	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))


# 执行导出存档
func _do_export_save(account_path: String, export_path: String) -> void:
	var result = SaveUtils.export_save(account_path, export_path)

	# 隐藏加载动画
	_hide_loading(false)

	if result.success:
		print(translate("save_exported"))
		show_notification(translate("save_exported"), true)
	else:
		print(translate("error") + ": " + result.message)
		show_notification(translate("error") + ": " + result.message, false)


# 备份存档
func _on_backup_save_pressed() -> void:
	if selected_save_id.is_empty():
		show_notification(translate("select_save_to_backup"), false)
		return

	# 使用 selected_save_id 来确定键名，与 _on_save_selected 保持一致
	var backup_key = selected_save_id
	var steam_id = ""
	var is_imported = selected_save_id.begins_with("imported_")

	if is_imported:
		steam_id = selected_save_id.substr(9)  # 去掉 "imported_" 前缀
	else:
		steam_id = selected_save_id

	# 获取存档数据
	var save_data = _get_selected_save()
	if save_data.is_empty():
		show_notification(translate("cannot_get_save_data"), false)
		return

	# 获取存档路径 - 可能是profile路径，需要获取账号目录
	var profile_path = save_data.get("path", "")
	if profile_path.is_empty():
		show_notification(translate("cannot_get_save_path"), false)
		return

	# 获取账号目录（去掉 /profile1 等后缀）
	var account_path = profile_path
	# 如果路径包含profileX，获取父目录
	if "/profile" in account_path:
		account_path = account_path.get_base_dir()
	if "/saves" in account_path:
		account_path = account_path.get_base_dir()

	print("[backup] 账号目录: ", account_path)
	print("[backup] backup_key: ", backup_key)
	print("[backup] steam_id: ", steam_id)
	print("[backup] is_imported: ", is_imported)

	# 使用用户配置的备份路径
	var backup_dir = backup_path
	if backup_dir.is_empty():
		# 默认使用应用的backups目录
		backup_dir = get_base_path() + "backups"

	# 确保备份目录存在
	if not DirAccess.dir_exists_absolute(backup_dir):
		DirAccess.make_dir_recursive_absolute(backup_dir)

	# 创建备份 - 传入steam_id以便命名备份文件夹，is_auto=false表示手动备份
	var backup_result = SaveUtils.create_backup(account_path, backup_dir, steam_id, false)
	print("backup_result: ", backup_result)

	if not backup_result.is_empty():
		# 标记该存档已被备份（使用正确的键）
		_mark_save_as_backed_up(backup_key, backup_result)

		# 如果是导入存档，同时持久化保存到config
		if is_imported:
			var saved_backups = config.get_value("imported_backups", "saves", {})
			saved_backups[backup_key] = backup_result
			config.set_value("imported_backups", "saves", saved_backups)
			config.save(config_path)
			print("[_on_backup_save_pressed] Saved imported backup to config: ", backup_key, " -> ", backup_result)
			# 清理旧的手动备份，保留最新 N 个
			_prune_old_backups(backup_dir, steam_id, false)

		show_notification(translate_fmt("backup_success", [steam_id, backup_result]), true)
		print("========== [backup success] ==========")

		# 重新加载存档列表以刷新显示
		# 保留当前导入存档的备份状态，避免 load_saves() 扫描后丢失
		var saved_imported_backups = {}
		for is_key in backed_up_saves:
			if is_key.begins_with("imported_") and not backed_up_saves[is_key].is_empty():
				saved_imported_backups[is_key] = backed_up_saves[is_key]
		# 设置跳过自动备份标志，避免立即再次备份
		_skip_auto_backup = true
		load_saves()
		# 恢复导入存档的备份状态
		for is_key in saved_imported_backups:
			backed_up_saves[is_key] = saved_imported_backups[is_key]
		# 刷新新创建面板的备份显示
		_refresh_imported_panels_backup_status()
	else:
		show_notification(translate_fmt("backup_failed", [translate("backup")]), false)
		print("========== [backup FAILED] ==========")


# 恢复存档
func _on_restore_save_pressed() -> void:
	if selected_save_id.is_empty():
		show_notification(translate("select_save_to_export"), false)
		return

	# 获取当前选中的存档数据
	var save_data = _get_selected_save()
	if save_data.is_empty():
		show_notification(translate("cannot_get_save_data"), false)
		return

	var is_imported = save_data.get("is_imported", false)
	var steam_id = save_data.get("steam_id", "")

	# 获取所有备份
	var all_backups = _get_all_backups_for_save(steam_id, is_imported)
	if all_backups.is_empty():
		show_notification(translate("no_backup_found"), false)
		return

	# 构建显示名称
	var save_name = steam_id
	if is_imported:
		save_name = save_data.get("import_info", {}).get("name", steam_id)

	# 显示恢复对话框
	_show_restore_dialog(save_data, all_backups, save_name)


# 获取存档的所有备份
func _get_all_backups_for_save(save_id: String, is_imported: bool) -> Array:
	var backups = []
	print("[_get_all_backups_for_save] START save_id=", save_id, " is_imported=", is_imported)

	# 扫描用户配置的备份目录
	if not backup_path.is_empty() and DirAccess.dir_exists_absolute(backup_path):
		print("[_get_all_backups_for_save] Scanning backup_path: ", backup_path)
		var found = _scan_backups_in_dir(backup_path, save_id, is_imported)
		for b in found:
			backups.append(b)

	# 也扫描 Steam 账号目录下的 backups 文件夹
	if not is_imported and not save_path.is_empty() and DirAccess.dir_exists_absolute(save_path):
		print("[_get_all_backups_for_save] Scanning save_path: ", save_path)
		var accounts = SaveUtils.get_all_steam_accounts(save_path)
		print("[_get_all_backups_for_save] Found ", accounts.size(), " accounts")
		for account in accounts:
			if account["steam_id"] == save_id:
				var account_backup_dir = account["path"].path_join("backups")
				if DirAccess.dir_exists_absolute(account_backup_dir):
					var found = _scan_backups_in_dir(account_backup_dir, save_id, false)
					for b in found:
						backups.append(b)

	# 按时间倒序排序（最新在前）
	backups.sort_custom(func(a, b): return a["name"] > b["name"])
	print("[_get_all_backups_for_save] END, total: ", backups.size())
	return backups
	return backups


# 扫描指定目录下的相关备份
func _scan_backups_in_dir(dir_path: String, save_id: String, is_imported: bool) -> Array:
	var results = []
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return results

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		if dir.current_is_dir():
			var is_match = false
			if is_imported:
				# 导入存档备份: manual_xxx 或 auto_xxx
				if folder_name.begins_with("manual_") or folder_name.begins_with("auto_"):
					is_match = true
			else:
				# Steam 存档备份: steam_<id>_xxx
				if folder_name.begins_with("steam_" + save_id + "_"):
					is_match = true

			if is_match:
				var full_path = dir_path.path_join(folder_name)
				var backup_time = _extract_backup_time(full_path)
				var backup_type = _extract_backup_type(full_path)
				results.append({
					"name": folder_name,
					"path": full_path,
					"time": backup_time,
					"type": backup_type  # "auto" or "manual"
				})
		folder_name = dir.get_next()
	dir.list_dir_end()
	return results


# 显示恢复对话框
func _show_restore_dialog(save_data: Dictionary, backups: Array, save_name: String) -> void:
	# 创建自定义对话框
	var dialog = Window.new()
	dialog.name = "RestoreDialog"
	dialog.title = translate("restore") + " - " + save_name
	dialog.transient = true
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	dialog.size = Vector2i(520, 400)
	add_child(dialog)
	dialog.close_requested.connect(func(): dialog.queue_free())

	# 用 Panel 包裹内容，提供填充大小
	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(panel)

	var content_vbox = VBoxContainer.new()
	content_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(content_vbox)

	# 警告信息
	var warning_label = Label.new()
	warning_label.text = "⚠ 覆盖操作不可逆，恢复后当前存档将被覆盖！"
	warning_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2, 1))
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_vbox.add_child(warning_label)

	# 备份列表说明
	var list_label = Label.new()
	list_label.text = "选择要恢复的备份（默认选择最新备份）："
	list_label.custom_minimum_size.y = 20
	content_vbox.add_child(list_label)

	# 滚动区域
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 250
	content_vbox.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	# 备份项引用（单选：selected_index）
	var backup_items = []
	var selected_index = 0  # 默认选中新备份

	for i in range(backups.size()):
		var backup = backups[i]
		var item_bg = ColorRect.new()
		item_bg.color = Color(0.18, 0.18, 0.18, 1)
		item_bg.custom_minimum_size.y = 44

		# 点击行选中
		var captured_i = i
		item_bg.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_set_backup_selection(list_vbox, backup_items, captured_i)
				selected_index = captured_i
		)

		var item_hbox = HBoxContainer.new()
		item_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_bg.add_child(item_hbox)

		# 选中指示器（圆点）
		var indicator = ColorRect.new()
		indicator.color = Color(0.3, 0.6, 0.3, 1)
		indicator.custom_minimum_size = Vector2(12, 12)
		indicator.name = "Indicator"
		item_hbox.add_child(indicator)

		# 左右分栏：左侧信息 | 右侧删除按钮
		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_hbox.add_child(info_vbox)

		# 备份名称（单行，简化显示）
		var type_text = translate("auto_backup_label") if backup["type"] == "auto" else translate("manual_backup")
		var simple_name = type_text + " - " + backup["time"]
		var name_label = Label.new()
		name_label.text = simple_name
		name_label.tooltip_text = backup["path"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		info_vbox.add_child(name_label)

		# 删除按钮（靠右）
		var delete_btn = Button.new()
		delete_btn.text = "X"
		delete_btn.tooltip_text = "删除此备份"
		delete_btn.custom_minimum_size = Vector2(30, 30)
		item_hbox.add_child(delete_btn)

		var captured_backup = backup
		delete_btn.pressed.connect(func():
			# 确认删除
			var confirm_dialog = Window.new()
			confirm_dialog.name = "ConfirmDelete"
			confirm_dialog.title = "确认删除备份"
			confirm_dialog.transient = true
			confirm_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
			confirm_dialog.size = Vector2i(360, 180)
			add_child(confirm_dialog)

			var confirm_vbox = VBoxContainer.new()
			confirm_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
			confirm_vbox.add_theme_constant_override("separation", 16)
			confirm_vbox.add_theme_constant_override("margin_left", 20)
			confirm_vbox.add_theme_constant_override("margin_right", 20)
			confirm_vbox.add_theme_constant_override("margin_top", 20)
			confirm_vbox.add_theme_constant_override("margin_bottom", 20)
			confirm_dialog.add_child(confirm_vbox)

			var confirm_label = Label.new()
			confirm_label.text = "确定要删除此备份吗？\n" + captured_backup["path"].get_file()
			confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			confirm_vbox.add_child(confirm_label)

			var confirm_btn_bar = HBoxContainer.new()
			confirm_btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
			confirm_btn_bar.custom_minimum_size.y = 40
			confirm_vbox.add_child(confirm_btn_bar)

			var no_btn = Button.new()
			no_btn.text = translate("cancel")
			no_btn.custom_minimum_size.x = 80
			no_btn.pressed.connect(func(): confirm_dialog.queue_free())
			confirm_btn_bar.add_child(no_btn)

			var btn_spacer = Control.new()
			btn_spacer.custom_minimum_size.x = 20
			confirm_btn_bar.add_child(btn_spacer)

			var yes_btn = Button.new()
			yes_btn.text = translate("confirm")
			yes_btn.custom_minimum_size.x = 80
			yes_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1))
			yes_btn.pressed.connect(func():
				# 删除备份文件夹
				if DirAccess.dir_exists_absolute(captured_backup["path"]):
					SaveUtils.delete_directory(captured_backup["path"])
				confirm_dialog.queue_free()
				dialog.queue_free()
				# 重新加载存档列表
				load_saves()
				show_notification(translate("backup_deleted"), true)
			)
			confirm_btn_bar.add_child(yes_btn)

			confirm_dialog.popup_centered()
		)
		item_hbox.add_child(delete_btn)

		list_vbox.add_child(item_bg)
		backup_items.append({"path": backup["path"], "bg": item_bg})

	# 应用默认选中
	_set_backup_selection(list_vbox, backup_items, 0)

	# 按钮栏
	var btn_bar = HBoxContainer.new()
	btn_bar.alignment = BoxContainer.ALIGNMENT_END
	btn_bar.custom_minimum_size.y = 40
	content_vbox.add_child(btn_bar)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bar.add_child(spacer)

	var cancel_btn = Button.new()
	cancel_btn.text = translate("cancel")
	cancel_btn.custom_minimum_size.x = 80
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	btn_bar.add_child(cancel_btn)

	var ok_btn = Button.new()
	ok_btn.text = translate("restore")
	ok_btn.custom_minimum_size.x = 80
	ok_btn.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))
	ok_btn.pressed.connect(func():
		if selected_index < 0 or selected_index >= backup_items.size():
			show_notification(translate("please_select_backup"), false)
			return
		var selected_path = backup_items[selected_index]["path"]
		dialog.queue_free()
		_do_restore(selected_path, save_data)
	)
	btn_bar.add_child(ok_btn)

	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.popup_centered()


# 更新备份列表选中状态（单选）
func _set_backup_selection(list_vbox: VBoxContainer, backup_items: Array, selected: int) -> void:
	for i in range(backup_items.size()):
		var item = backup_items[i]
		var bg = item["bg"]
		var indicator = bg.get_node_or_null("Indicator")
		if i == selected:
			bg.color = Color(0.25, 0.38, 0.25, 1)
			if indicator:
				indicator.color = Color(0.3, 0.8, 0.3, 1)
		else:
			bg.color = Color(0.18, 0.18, 0.18, 1)
			if indicator:
				indicator.color = Color(0.4, 0.4, 0.4, 0.5)


# 执行恢复操作
func _do_restore(backup_path: String, save_data: Dictionary) -> void:
	print("[_do_restore] Restoring from: ", backup_path)
	print("[_do_restore] Save data: ", save_data)

	var is_imported = save_data.get("is_imported", false)
	var steam_id = save_data.get("steam_id", "")
	var target_path = ""
	var restore_ok = false

	if is_imported:
		# 导入存档：恢复到 temp_save 目录
		var import_info = save_data.get("import_info", {})
		target_path = import_info.get("path", "")
		if target_path.is_empty():
			show_notification(translate("cannot_determine_imported_save_path"), false)
			return

		_show_loading("正在恢复导入存档...")
		print("[_do_restore] Imported target: ", target_path)
		print("[_do_restore] Backup exists: ", DirAccess.dir_exists_absolute(backup_path))
		restore_ok = SaveUtils.restore_backup(backup_path, target_path)
		_hide_loading(false)
		if restore_ok:
			# 恢复成功后，弹出选择同步位置的对话框
			_show_cloud_sync_dialog(target_path, "", "restore_imported")

			show_notification(translate("imported_save_restore_success"), true)
			# 设置跳过自动备份标志，避免立即再次备份
			_skip_auto_backup = true
			load_saves()
		else:
			show_notification(translate("restore_failed_check_file"), false)

	else:
		# Steam 账号存档：恢复到 Steam 账号目录
		if not save_path.is_empty() and DirAccess.dir_exists_absolute(save_path):
			var accounts = SaveUtils.get_all_steam_accounts(save_path)
			for account in accounts:
				if account["steam_id"] == steam_id:
					target_path = account["path"]
					break

		if target_path.is_empty():
			show_notification(translate("cannot_determine_save_path"), false)
			return

		_show_loading("正在恢复存档...")
		print("[_do_restore] Steam target: ", target_path)
		print("[_do_restore] Backup exists: ", DirAccess.dir_exists_absolute(backup_path))
		restore_ok = SaveUtils.restore_backup(backup_path, target_path)
		_hide_loading(false)
		if restore_ok:
			# 恢复成功后，弹出选择同步位置的对话框
			_show_cloud_sync_dialog(target_path, steam_id, "restore_steam")

			show_notification(translate_fmt("save_restore_success", [steam_id]), true)
			# 设置跳过自动备份标志，避免立即再次备份
			_skip_auto_backup = true
			load_saves()
		else:
			show_notification(translate("restore_failed_check_file"), false)


# 覆盖存档
func _on_overwrite_save_pressed() -> void:
	if selected_save_id.is_empty():
		print(translate("select_save_to_export"))
		return

	var save_data = _get_selected_save()
	if save_data.is_empty():
		return

	var is_imported = save_data.get("is_imported", false)
	if is_imported:
		_show_imported_overwrite_step1(save_data)
	else:
		_show_steam_overwrite_dialog(save_data)


# ========== Steam存档覆盖对话框 ==========
func _show_steam_overwrite_dialog(save_data: Dictionary) -> void:
	var steam_id = save_data.get("steam_id", "")
	# 获取Steam账号路径 - 需要从profile目录提取到账号根目录
	var steam_path = save_data.get("path", "")
	print("[Steam覆盖] steam_id: ", steam_id)
	print("[Steam覆盖] save_data path: ", steam_path)

	# 如果路径包含profile1/profile2/profile3，需要提取账号根目录
	if not steam_path.is_empty():
		var path_parts = steam_path.split("/")
		if path_parts.size() > 0:
			var last_part = path_parts[-1]
			if last_part.begins_with("profile"):
				# 去掉最后一部分，得到账号根目录
				path_parts = path_parts.slice(0, path_parts.size() - 1)
				steam_path = "/".join(path_parts)
				print("[Steam覆盖] 提取后的账号根目录: ", steam_path)

	# 如果路径为空，尝试从save_path构建
	if steam_path.is_empty() and not steam_id.is_empty():
		steam_path = save_path.path_join(steam_id)
		print("[Steam覆盖] 从save_path构建: ", steam_path)

	# 仍然为空则无法继续
	if steam_path.is_empty():
		show_notification(translate("error") + ": Save path not found", false)
		return

	print("[Steam覆盖] 最终steam_path: ", steam_path)
	print("[Steam覆盖] 路径存在: ", DirAccess.dir_exists_absolute(steam_path))

	# 检查原版和模组版存档是否存在
	var has_vanilla = false
	var has_modded = false
	for i in range(1, 4):
		var vanilla_profile = steam_path.path_join("profile" + str(i))
		var modded_profile = steam_path.path_join("modded/profile" + str(i))
		print("[Steam覆盖] profile", i, " vanilla exists: ", DirAccess.dir_exists_absolute(vanilla_profile))
		print("[Steam覆盖] profile", i, " modded exists: ", DirAccess.dir_exists_absolute(modded_profile))
		if DirAccess.dir_exists_absolute(vanilla_profile):
			has_vanilla = true
		if DirAccess.dir_exists_absolute(modded_profile):
			has_modded = true

	print("[Steam覆盖] has_vanilla: ", has_vanilla, " has_modded: ", has_modded)

	# 如果既没有原版也没有模组版，无法进行覆盖
	if not has_vanilla and not has_modded:
		show_notification(translate("error") + ": No saves found", false)
		return

	# 如果只有一种存档，无法双向覆盖
	if not has_vanilla or not has_modded:
		show_notification(translate("error") + ": Need both vanilla and modded saves for overwrite", false)
		return

	var dialog = Window.new()
	dialog.name = "SteamOverwriteDialog"
	dialog.title = translate("overwrite_save") + " - " + steam_id
	dialog.transient = true
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	dialog.size = Vector2i(480, 420)
	add_child(dialog)
	dialog.close_requested.connect(func(): dialog.queue_free())

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	vbox.add_theme_constant_override("margin_left", 16)
	vbox.add_theme_constant_override("margin_right", 16)
	vbox.add_theme_constant_override("margin_top", 16)
	vbox.add_theme_constant_override("margin_bottom", 16)
	dialog.add_child(vbox)

	# 警告
	var warn_lbl = Label.new()
	warn_lbl.text = "⚠ " + translate("overwrite_warning")
	warn_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4, 1))
	warn_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(warn_lbl)

	# 标题
	var dir_title = Label.new()
	dir_title.text = translate("overwrite") + " " + translate("save_list")
	dir_title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(dir_title)

	# 方向选项 - 使用更清晰的标题格式: 源 → 目标
	# 使用字典来存储选中的方向，确保闭包能正确捕获
	var direction_state = {"selected": "modded_to_vanilla"}
	var direction_options = [
		{"key": "modded_to_vanilla", "title": "模组 → 原版", "desc": translate("overwrite_vanilla_from_modded_desc"), "color": Color(0.35, 0.6, 0.85, 1)},
		{"key": "vanilla_to_modded", "title": "原版 → 模组", "desc": translate("overwrite_modded_from_vanilla_desc"), "color": Color(0.4, 0.75, 0.45, 1)}
	]

	var dir_bgs = []
	var dir_colors = []

	for idx in range(2):
		var opt = direction_options[idx]
		var card = ColorRect.new()
		card.color = Color(0.22, 0.22, 0.28, 1)
		card.custom_minimum_size.y = 60
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var captured_idx = idx
		var captured_key = direction_options[idx]["key"]
		card.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				direction_state["selected"] = captured_key
				for i in range(dir_bgs.size()):
					dir_bgs[i].color = Color(0.22, 0.22, 0.28, 1) if i != captured_idx else Color(0.3, 0.35, 0.45, 1)
		)
		vbox.add_child(card)
		dir_bgs.append(card)
		dir_colors.append(opt["color"])

		var hbox = HBoxContainer.new()
		hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		hbox.add_theme_constant_override("margin_left", 10)
		hbox.add_theme_constant_override("margin_right", 10)
		hbox.add_theme_constant_override("margin_top", 6)
		hbox.add_theme_constant_override("margin_bottom", 6)
		card.add_child(hbox)

		var strip = ColorRect.new()
		strip.color = opt["color"]
		strip.custom_minimum_size = Vector2(4, 40)
		hbox.add_child(strip)

		var text_vbox = VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(text_vbox)

		var title_lbl = Label.new()
		title_lbl.text = opt["title"]
		title_lbl.add_theme_font_size_override("font_size", 16)
		title_lbl.add_theme_color_override("font_color", opt["color"])
		text_vbox.add_child(title_lbl)

		var desc_lbl = Label.new()
		desc_lbl.text = opt["desc"]
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7, 1))
		text_vbox.add_child(desc_lbl)

	# 默认选中第一个
	dir_bgs[0].color = Color(0.3, 0.35, 0.45, 1)

	# 备份选项
	var backup_check = CheckBox.new()
	backup_check.button_pressed = true
	backup_check.text = translate("overwrite_create_backup_first")
	vbox.add_child(backup_check)

	# 按钮栏
	var btn_bar = HBoxContainer.new()
	btn_bar.custom_minimum_size.y = 36
	vbox.add_child(btn_bar)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bar.add_child(spacer)

	var cancel_btn = Button.new()
	cancel_btn.text = translate("cancel")
	cancel_btn.custom_minimum_size.x = 80
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	btn_bar.add_child(cancel_btn)

	var ok_btn = Button.new()
	ok_btn.text = translate("confirm_overwrite")
	ok_btn.custom_minimum_size.x = 100
	ok_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	ok_btn.add_theme_stylebox_override("normal", _make_flat_style(Color(0.25, 0.65, 0.3, 1)))
	ok_btn.pressed.connect(func():
		dialog.queue_free()
		_do_steam_overwrite(save_data, direction_state["selected"], backup_check.button_pressed)
	)
	btn_bar.add_child(ok_btn)

	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.popup_centered()


func _update_overwrite_card_selection(cards: Array, bgs: Array, selected: int) -> void:
	for i in range(bgs.size()):
		var bg = bgs[i]
		var strip = bg.get_node_or_null("Strip")
		if i == selected:
			bg.color = Color(0.3, 0.35, 0.45, 1)
			if strip:
				strip.color = cards[i]
		else:
			bg.color = Color(0.22, 0.22, 0.28, 1)
			if strip:
				strip.color = Color(0.3, 0.3, 0.35, 1)


func _get_backup_dir_for_steam(steam_id: String) -> String:
	if not backup_path.is_empty() and DirAccess.dir_exists_absolute(backup_path):
		return backup_path
	if save_path.is_empty():
		return ""
	var steam_dir = save_path.path_join(steam_id)
	if not DirAccess.dir_exists_absolute(steam_dir):
		return ""
	return steam_dir.path_join("backups")


func _do_steam_overwrite(save_data: Dictionary, direction: String, do_backup: bool) -> void:
	var steam_id = save_data.get("steam_id", "")
	# 从save_data获取path，如果不存在则从save_path和steam_id构建
	var steam_path = save_data.get("path", "")

	# 如果路径包含profile1/profile2/profile3，需要提取账号根目录
	if not steam_path.is_empty():
		var path_parts = steam_path.split("/")
		if path_parts.size() > 0:
			var last_part = path_parts[-1]
			if last_part.begins_with("profile"):
				# 去掉最后一部分，得到账号根目录
				path_parts = path_parts.slice(0, path_parts.size() - 1)
				steam_path = "/".join(path_parts)

	# 如果路径为空，尝试从save_path构建
	if steam_path.is_empty():
		steam_path = save_path.path_join(steam_id)

	if steam_path.is_empty() or not DirAccess.dir_exists_absolute(steam_path):
		show_notification(translate("overwrite_failed") + ": " + translate("error"), false)
		return

	_show_loading(translate("overwrite") + "...")

	var backup_dir = _get_backup_dir_for_steam(steam_id)

	# 备份整个账号（覆盖方向的两方都会被保护）
	if do_backup and not backup_dir.is_empty():
		var backup_result = SaveUtils.create_backup(steam_path, backup_dir, steam_id, false)
		if not backup_result.is_empty():
			print("覆盖前备份已创建: ", backup_result)

	# 执行定向profile覆盖
	var result = SaveUtils.overwrite_profiles(steam_path, steam_path, direction)

	if result["success"]:
		# 覆盖成功后，弹出选择同步位置的对话框
		_show_cloud_sync_dialog(steam_path, steam_id, "steam_overwrite")

	_hide_loading(false)

	if result["success"]:
		show_notification(translate("overwrite_success"), true)
		# 设置跳过自动备份标志，避免立即再次备份
		_skip_auto_backup = true
		load_saves()
	else:
		show_notification(translate("overwrite_failed") + ": " + str(result["message"]), false)


# ========== 导入存档覆盖 - 步骤1：选择目标Steam账号 ==========
func _show_imported_overwrite_step1(save_data: Dictionary) -> void:
	var dialog = Window.new()
	dialog.name = "ImportedOverwriteStep1"
	dialog.title = translate("select_target_account")
	dialog.transient = true
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	dialog.size = Vector2i(440, 380)
	add_child(dialog)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	vbox.add_theme_constant_override("margin_left", 16)
	vbox.add_theme_constant_override("margin_right", 16)
	vbox.add_theme_constant_override("margin_top", 16)
	vbox.add_theme_constant_override("margin_bottom", 16)
	dialog.add_child(vbox)

	# 标题
	var title_lbl = Label.new()
	title_lbl.text = translate("select_target_account")
	title_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(title_lbl)

	# 账号列表
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	var accounts = SaveUtils.get_all_steam_accounts(save_path)
	var account_bgs = []
	var selected_account_idx = -1

	# 提前声明 next_btn
	var next_btn = Button.new()
	next_btn.text = translate("next_step")
	next_btn.custom_minimum_size.x = 80
	next_btn.disabled = true
	next_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))

	# 样式定义（放在循环外部）
	var normal_bg = Color(0.22, 0.22, 0.28, 1)
	var hover_bg = Color(0.28, 0.32, 0.38, 1)
	var selected_bg = Color(0.28, 0.35, 0.5, 1)

	# 使用字典保存选中状态（闭包需要共享引用）
	var selection = {"idx": -1, "btn": null}
	var local_account_bgs = []

	for i in range(accounts.size()):
		var acc = accounts[i]
		var item_btn = Button.new()
		item_btn.custom_minimum_size.y = 44
		item_btn.flat = true

		var normal_style = StyleBoxFlat.new()
		normal_style.bg_color = normal_bg
		normal_style.corner_radius_top_left = 4
		normal_style.corner_radius_top_right = 4
		normal_style.corner_radius_bottom_left = 4
		normal_style.corner_radius_bottom_right = 4
		item_btn.add_theme_stylebox_override("normal", normal_style)
		item_btn.add_theme_stylebox_override("hover", normal_style)
		item_btn.add_theme_stylebox_override("pressed", normal_style)

		local_account_bgs.append(item_btn)
		list_vbox.add_child(item_btn)

		# 使用字典闭包捕获
		var idx = i
		var n_btn = next_btn
		var sel = selection
		var acc_bgs = local_account_bgs
		var n_bg = normal_bg
		var s_bg = selected_bg

		item_btn.pressed.connect(func():
			sel["idx"] = idx
			sel["btn"] = acc_bgs[idx]
			# 更新所有按钮样式
			for j in range(acc_bgs.size()):
				var b = acc_bgs[j]
				var st = StyleBoxFlat.new()
				st.corner_radius_top_left = 4
				st.corner_radius_top_right = 4
				st.corner_radius_bottom_left = 4
				st.corner_radius_bottom_right = 4
				if j == sel["idx"]:
					st.bg_color = s_bg
				else:
					st.bg_color = n_bg
				b.add_theme_stylebox_override("normal", st)
				b.add_theme_stylebox_override("hover", st)
				b.add_theme_stylebox_override("pressed", st)
			# 启用下一步按钮
			n_btn.disabled = false
			n_btn.add_theme_stylebox_override("normal", _make_flat_style(Color(0.25, 0.55, 0.85, 1)))
		)

		var hbox = HBoxContainer.new()
		hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		hbox.add_theme_constant_override("margin_left", 10)
		hbox.add_theme_constant_override("margin_right", 10)
		hbox.add_theme_constant_override("margin_top", 6)
		hbox.add_theme_constant_override("margin_bottom", 6)
		item_btn.add_child(hbox)

		var dot = ColorRect.new()
		dot.color = Color(0.4, 0.4, 0.4, 0.5)
		dot.custom_minimum_size = Vector2(8, 8)
		hbox.add_child(dot)

		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info_vbox)

		var name_lbl = Label.new()
		name_lbl.text = acc["steam_id"]
		name_lbl.add_theme_font_size_override("font_size", 12)
		info_vbox.add_child(name_lbl)

	# 保存到外部变量供下一步使用
	account_bgs = local_account_bgs

	# 按钮栏
	var btn_bar = HBoxContainer.new()
	btn_bar.custom_minimum_size.y = 36
	vbox.add_child(btn_bar)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bar.add_child(spacer)

	var cancel_btn = Button.new()
	cancel_btn.text = translate("cancel")
	cancel_btn.custom_minimum_size.x = 70
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	btn_bar.add_child(cancel_btn)

	btn_bar.add_child(next_btn)

	# 闭包使用的 selection 字典需要在按钮回调之前声明
	next_btn.pressed.connect(func():
		if selection["idx"] < 0:
			show_notification(translate("overwrite_select_account"), false)
			return
		var target_account = accounts[selection["idx"]]
		dialog.queue_free()
		_show_imported_overwrite_step2(save_data, target_account)
	)

	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.popup_centered()


func _update_account_selection(bgs: Array, selected: int) -> void:
	for i in range(bgs.size()):
		var bg = bgs[i]
		var dot = bg.get_node_or_null("Dot")
		if i == selected:
			bg.color = Color(0.28, 0.35, 0.5, 1)
			if dot:
				dot.color = Color(0.35, 0.6, 0.85, 1)
		else:
			bg.color = Color(0.22, 0.22, 0.28, 1)
			if dot:
				dot.color = Color(0.4, 0.4, 0.4, 0.5)




func _show_imported_overwrite_step2(save_data: Dictionary, target_account: Dictionary) -> void:
	var target_steam_id = target_account["steam_id"]
	var target_path = target_account["path"]

	# 检查导入存档是否有模组版
	var source_path = save_data.get("path", "")
	var has_modded = DirAccess.dir_exists_absolute(source_path.path_join("modded"))

	var dialog = Window.new()
	dialog.name = "ImportedOverwriteStep2"
	dialog.title = translate("overwrite_save") + " - " + target_steam_id
	dialog.transient = true
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	dialog.size = Vector2i(480, 480)
	add_child(dialog)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	vbox.add_theme_constant_override("margin_left", 16)
	vbox.add_theme_constant_override("margin_right", 16)
	vbox.add_theme_constant_override("margin_top", 16)
	vbox.add_theme_constant_override("margin_bottom", 16)
	dialog.add_child(vbox)

	# 警告
	var warn_lbl = Label.new()
	warn_lbl.text = "⚠ " + translate("overwrite_warning")
	warn_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4, 1))
	warn_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(warn_lbl)

	# 源存档信息
	var src_label = Label.new()
	src_label.text = translate("source_save_info") + ": " + save_data.get("name", "-")
	src_label.add_theme_font_size_override("font_size", 11)
	src_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65, 1))
	vbox.add_child(src_label)

	# 方向选择标题
	var dir_title = Label.new()
	dir_title.text = translate("overwrite") + " " + translate("save_list")
	dir_title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(dir_title)

	# 方向选项
	# 使用字典来存储选中的方向，确保闭包能正确捕获
	var direction_state = {"selected": "imported_to_vanilla"}
	var direction_options = [
		{"key": "imported_to_vanilla", "arrow": "→", "title": "Steam原版 ← 导入原版", "desc": translate("overwrite_vanilla_from_vanilla_desc"), "color": Color(0.35, 0.6, 0.85, 1)},
		{"key": "imported_to_modded", "arrow": "→", "title": "Steam模组 ← 导入原版", "desc": translate("overwrite_modded_from_vanilla_imported_desc"), "color": Color(0.75, 0.55, 0.3, 1)}
	]
	if has_modded:
		direction_options.append({"key": "imported_modded_to_vanilla", "arrow": "→", "title": "Steam原版 ← 导入模组", "desc": translate("overwrite_vanilla_from_modded_imported_desc"), "color": Color(0.7, 0.35, 0.65, 1)})
		direction_options.append({"key": "imported_modded_to_modded", "arrow": "→", "title": "Steam模组 ← 导入模组", "desc": translate("overwrite_modded_from_modded_imported_desc"), "color": Color(0.5, 0.35, 0.8, 1)})

	var dir_bgs = []
	var dir_colors = []

	for idx in range(direction_options.size()):
		var opt = direction_options[idx]
		var card = ColorRect.new()
		card.color = Color(0.22, 0.22, 0.28, 1)
		card.custom_minimum_size.y = 55
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var captured_idx = idx
		var captured_key = direction_options[idx]["key"]
		card.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				direction_state["selected"] = captured_key
				for i in range(dir_bgs.size()):
					dir_bgs[i].color = Color(0.22, 0.22, 0.28, 1) if i != captured_idx else Color(0.3, 0.35, 0.45, 1)
		)
		vbox.add_child(card)
		dir_bgs.append(card)
		dir_colors.append(opt["color"])

		var hbox = HBoxContainer.new()
		hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		hbox.add_theme_constant_override("margin_left", 10)
		hbox.add_theme_constant_override("margin_right", 10)
		hbox.add_theme_constant_override("margin_top", 6)
		hbox.add_theme_constant_override("margin_bottom", 6)
		card.add_child(hbox)

		var strip = ColorRect.new()
		strip.color = opt["color"]
		strip.custom_minimum_size = Vector2(4, 35)
		hbox.add_child(strip)

		var text_vbox = VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(text_vbox)

		var title_lbl = Label.new()
		title_lbl.text = opt["title"]
		title_lbl.add_theme_font_size_override("font_size", 14)
		title_lbl.add_theme_color_override("font_color", opt["color"])
		text_vbox.add_child(title_lbl)

		var desc_lbl = Label.new()
		desc_lbl.text = opt["desc"]
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7, 1))
		text_vbox.add_child(desc_lbl)

	# 默认选中
	dir_bgs[0].color = Color(0.3, 0.35, 0.45, 1)

	# 备份选项
	var backup_check = CheckBox.new()
	backup_check.button_pressed = true
	backup_check.text = translate("overwrite_create_backup_first")
	vbox.add_child(backup_check)

	# 按钮栏
	var btn_bar = HBoxContainer.new()
	btn_bar.custom_minimum_size.y = 36
	vbox.add_child(btn_bar)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bar.add_child(spacer)

	var cancel_btn = Button.new()
	cancel_btn.text = translate("cancel")
	cancel_btn.custom_minimum_size.x = 80
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	btn_bar.add_child(cancel_btn)

	var ok_btn = Button.new()
	ok_btn.text = translate("confirm_overwrite")
	ok_btn.custom_minimum_size.x = 100
	ok_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	ok_btn.add_theme_stylebox_override("normal", _make_flat_style(Color(0.25, 0.65, 0.3, 1)))
	ok_btn.pressed.connect(func():
		dialog.queue_free()
		_do_imported_overwrite(save_data, target_path, direction_state["selected"], backup_check.button_pressed)
	)
	btn_bar.add_child(ok_btn)

	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.popup_centered()


func _do_imported_overwrite(save_data: Dictionary, target_path: String, direction: String, do_backup: bool) -> void:
	var source_path = save_data.get("path", "")
	if source_path.is_empty() or not DirAccess.dir_exists_absolute(source_path):
		show_notification(translate("overwrite_failed") + ": " + translate("error"), false)
		return

	if target_path.is_empty() or not DirAccess.dir_exists_absolute(target_path):
		show_notification(translate("overwrite_failed") + ": " + translate("error"), false)
		return

	_show_loading(translate("overwrite") + "...")

	# 从target_path提取steam_id用于备份
	var target_steam_id = ""
	if not save_path.is_empty() and target_path.begins_with(save_path):
		target_steam_id = target_path.substr(save_path.length())
		if target_steam_id.begins_with("/") or target_steam_id.begins_with("\\"):
			target_steam_id = target_steam_id.substr(1)
	var backup_dir = _get_backup_dir_for_steam(target_steam_id)

	# 备份目标
	if do_backup and not backup_dir.is_empty():
		var backup_result = SaveUtils.create_backup(target_path, backup_dir, target_steam_id, false)
		if not backup_result.is_empty():
			print("导入存档覆盖前备份已创建: ", backup_result)

	# 执行覆盖
	var result = SaveUtils.overwrite_profiles(source_path, target_path, direction)

	if result["success"]:
		# 覆盖成功后，弹出选择同步位置的对话框
		_show_cloud_sync_dialog(target_path, target_steam_id, "imported_overwrite")

	_hide_loading(false)

	if result["success"]:
		show_notification(translate("overwrite_success"), true)
		# 设置跳过自动备份标志，避免立即再次备份
		_skip_auto_backup = true
		load_saves()
	else:
		show_notification(translate("overwrite_failed") + ": " + str(result["message"]), false)


# ========== 云存档同步选择对话框 ==========
var _sync_dialog_context: Dictionary = {}  # 存储同步对话框的上下文信息

func _show_cloud_sync_dialog(source_path: String, steam_id: String, sync_type: String) -> void:
	# 保存上下文信息，供回调使用
	_sync_dialog_context = {
		"source_path": source_path,
		"steam_id": steam_id,
		"sync_type": sync_type
	}

	var dialog = Window.new()
	dialog.name = "CloudSyncDialog"
	dialog.title = translate("cloud_sync_title")
	dialog.transient = true
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	dialog.size = Vector2i(420, 280)
	add_child(dialog)
	dialog.close_requested.connect(func(): dialog.queue_free())

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	vbox.add_theme_constant_override("margin_left", 20)
	vbox.add_theme_constant_override("margin_right", 20)
	vbox.add_theme_constant_override("margin_top", 16)
	vbox.add_theme_constant_override("margin_bottom", 16)
	dialog.add_child(vbox)

	# 说明文本
	var info_label = Label.new()
	info_label.text = translate("cloud_sync_info")
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(info_label)

	# 选项按钮
	var gse_check = CheckBox.new()
	gse_check.text = translate("cloud_sync_gse")
	gse_check.button_pressed = true
	vbox.add_child(gse_check)

	var steam_check = CheckBox.new()
	steam_check.text = translate("cloud_sync_steam")
	steam_check.button_pressed = true
	vbox.add_child(steam_check)

	# 提示
	var hint_label = Label.new()
	hint_label.text = "提示：同时同步可能导致存档冲突，请根据游戏版本选择"
	hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint_label)

	# 按钮栏
	var btn_bar = HBoxContainer.new()
	btn_bar.custom_minimum_size.y = 36
	vbox.add_child(btn_bar)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bar.add_child(spacer)

	var skip_btn = Button.new()
	skip_btn.text = translate("skip")
	skip_btn.custom_minimum_size.x = 80
	skip_btn.pressed.connect(func():
		dialog.queue_free()
	)
	btn_bar.add_child(skip_btn)

	var sync_btn = Button.new()
	sync_btn.text = translate("sync") if has_translation_key("sync") else "同步"
	sync_btn.custom_minimum_size.x = 100
	sync_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	sync_btn.add_theme_stylebox_override("normal", _make_flat_style(Color(0.25, 0.65, 0.3, 1)))
	sync_btn.pressed.connect(func():
		var sync_gse = gse_check.button_pressed
		var sync_steam = steam_check.button_pressed
		dialog.queue_free()
		# 执行同步
		_do_sync_to_cloud(source_path, steam_id, sync_type, sync_gse, sync_steam)
	)
	btn_bar.add_child(sync_btn)

	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.popup_centered()


func _do_sync_to_cloud(source_path: String, steam_id: String, sync_type: String, sync_gse: bool, sync_steam: bool) -> void:
	print("[_do_sync_to_cloud] source: ", source_path, " steam_id: ", steam_id)
	print("[_do_sync_to_cloud] sync_gse: ", sync_gse, " sync_steam: ", sync_steam)

	_show_loading(translate("syncing") + "...")

	# 使用设置中保存的云端路径
	var sync_result = SaveUtils.sync_save_to_all_locations(source_path, steam_id, sync_steam, sync_gse, gse_cloud_path, steam_cloud_path)
	print("[_do_sync_to_cloud] 结果: ", sync_result)

	_hide_loading(false)

	# 显示结果
	var success_count = 0
	var fail_count = 0
	for synced in sync_result.get("synced_paths", []):
		if synced.get("status") == "success":
			success_count += 1
		elif synced.get("status") == "failed":
			fail_count += 1

	if success_count > 0:
		show_notification("成功同步到 %d 个云端位置" % success_count, true)
	else:
		show_notification("同步失败或未选择任何云端", false)


# ========== 辅助函数 ==========
func _make_flat_style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


# 获取当前选中的存档
func _get_selected_save() -> Dictionary:
	if selected_save_id.is_empty():
		return {}

	# 首先尝试直接匹配（用于Steam账号存档）
	for save in steam_saves:
		if save.get("name") == selected_save_id:
			return save

	# 尝试匹配导入存档（selected_save_id 可能带 "imported_" 前缀）
	var search_name = selected_save_id
	if selected_save_id.begins_with("imported_"):
		search_name = selected_save_id.substr(9)  # 去掉 "imported_" 前缀

	for save in imported_saves:
		if save.get("name") == search_name:
			return save

	# 如果没有直接匹配，尝试通过steam_id匹配（用于Steam账号存档）
	var search_id = selected_save_id
	if selected_save_id.begins_with("imported_"):
		search_id = selected_save_id.substr(9)  # 去掉 "imported_" 前缀

	# 查找第一个匹配的存档
	for save in steam_saves:
		if save.get("steam_id") == search_id:
			return save

	return {}


# 标记存档已备份
func _mark_save_as_backed_up(save_id: String, backup_path: String = "") -> void:
	print("========== [_mark_save_as_backed_up] ==========")
	print("save_id: ", save_id)
	print("backup_path: ", backup_path)

	backed_up_saves[save_id] = backup_path

	# 如果是Steam存档，也标记导入存档（如果有相同Steam ID）
	if not save_id.begins_with("imported_"):
		backed_up_saves["imported_" + save_id] = backup_path
	# 如果是导入存档，也标记Steam存档
	elif save_id.begins_with("imported_"):
		var original_id = save_id.substr(9)  # 去掉 "imported_" 前缀
		backed_up_saves[original_id] = backup_path

	# 更新对应的存档面板
	if save_panels.has(save_id):
		_update_backup_time_display(save_id)
		# 确保也更新标题栏的备份状态
		var panel_info = save_panels[save_id]
		if panel_info.has("panel"):
			_update_backup_status_label_in_title(panel_info["panel"], save_id)

	# 如果是Steam存档，也要更新对应的导入存档（如果有相同Steam ID）
	if not save_id.begins_with("imported_"):
		var imported_key = "imported_" + save_id
		if save_panels.has(imported_key):
			print("[_mark_save_as_backed_up] Also updating imported panel: ", imported_key)
			_update_backup_time_display(imported_key)
			var panel_info = save_panels[imported_key]
			if panel_info.has("panel"):
				_update_backup_status_label_in_title(panel_info["panel"], imported_key)

	# 如果是导入存档，也要更新对应的Steam存档（如果有相同ID）
	elif save_id.begins_with("imported_"):
		var original_id = save_id.substr(9)
		if save_panels.has(original_id):
			print("[_mark_save_as_backed_up] Also updating steam panel: ", original_id)
			_update_backup_time_display(original_id)
			var panel_info = save_panels[original_id]
			if panel_info.has("panel"):
				_update_backup_status_label_in_title(panel_info["panel"], original_id)

	print("========== [end _mark_save_as_backed_up] ==========")


# 重新选中当前存档以刷新显示
func _on_reselect_current_save() -> void:
	if selected_save_id.is_empty():
		return

	# 创建一个临时的save_data来调用选中回调
	var save_data = _get_selected_save()
	if not save_data.is_empty():
		_on_save_selected(save_data)


# 刷新详情面板的备份状态显示
func _refresh_save_details_backup_status() -> void:
	# 查找详情面板中的备份状态标签
	if not save_details_panel:
		return

	# 查找"已备份"标签
	for child in save_details_panel.get_children():
		if child is VBoxContainer:
			for vbox_child in child.get_children():
				if vbox_child is Label and "备份" in vbox_child.text:
					# 更新备份状态
					var key = selected_save_id
					if backed_up_saves.has(key):
						var backup_info = backed_up_saves[key]
						if not backup_info.is_empty():
							var backup_time = _extract_backup_time(backup_info)
							var backup_type = _extract_backup_type(backup_info)
							var type_label = translate("auto_backup_label") if backup_type == "auto" else translate("manual_backup")
							vbox_child.text = "%s: %s (%s)" % [translate("backup"), backup_time, type_label]
							vbox_child.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))
							vbox_child.visible = true
					break


# 辅助函数：递归查找所有Label
func _find_all_labels(node: Control, indent: String) -> void:
	for child in node.get_children():
		if child is Label:
			print(indent + "Label: name=", child.name, " text=", child.text)
		if child is Control:
			_find_all_labels(child, indent + "  ")


# 更新存档面板的备份状态显示
func _update_save_panel_backup_status(save_id: String) -> void:
	# 使用新的更新备份时间显示函数
	_update_backup_time_display(save_id)


# 刷新所有导入存档面板的备份状态显示
func _refresh_imported_panels_backup_status() -> void:
	# 遍历所有导入存档相关的备份状态
	for key in backed_up_saves:
		if key.begins_with("imported_") and not backed_up_saves[key].is_empty():
			if save_panels.has(key):
				_update_backup_time_display(key)
				_update_backup_status_label_in_title(save_panels[key]["panel"], key)


# 更新备份时间显示
func _update_backup_time_display(panel_key: String) -> void:
	print("[_update_backup_time_display] panel_key: ", panel_key)

	if not save_panels.has(panel_key):
		print("ERROR: Panel not found for key: ", panel_key)
		return

	var panel_info = save_panels[panel_key]
	if not panel_info.has("panel"):
		return

	var panel = panel_info["panel"]

	# 查找备份时间标签（直接查找VBoxContainer的子节点）
	var backup_time_label = null
	for child in panel.get_children():
		if child is VBoxContainer:
			for vbox_child in child.get_children():
				if vbox_child is Label and vbox_child.name == "BackupTimeLabel":
					backup_time_label = vbox_child
					break
			if backup_time_label:
				break

	# 也检查直接子节点
	if backup_time_label == null:
		for child in panel.get_children():
			if child is Label and child.name == "BackupTimeLabel":
				backup_time_label = child
				break

	if backup_time_label == null:
		print("ERROR: BackupTimeLabel NOT FOUND!")
		_find_all_labels(panel, "")
		return

	# 更新备份时间显示 - 只检查当前键（不跨键检查）
	var backup_info = ""
	var has_backup = false

	# 只检查当前键
	if backed_up_saves.has(panel_key):
		backup_info = backed_up_saves[panel_key]
		has_backup = not backup_info.is_empty()

	if has_backup:
		var backup_time = _extract_backup_time(backup_info)
		var backup_type = _extract_backup_type(backup_info)
		var type_label = translate("auto_backup_label") if backup_type == "auto" else translate("manual_backup")
		backup_time_label.text = "%s: %s (%s)" % [translate("backup"), backup_time, type_label]
		backup_time_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))
		backup_time_label.visible = true
		backup_time_label.custom_minimum_size = Vector2(0, 20)
		print("SUCCESS: Set backup time - '", backup_time, "' (", backup_type, ")")
		_update_backup_status_label_in_title(panel, panel_key)
	else:
		backup_time_label.text = ""
		backup_time_label.visible = false
		backup_time_label.custom_minimum_size = Vector2(0, 0)


# 更新标题栏的备份状态标签
func _update_backup_status_label_in_title(panel: Control, save_id: String) -> void:
	# 查找标题栏
	var title_bar = null
	for child in panel.get_children():
		if child is VBoxContainer:
			var vbox = child as VBoxContainer
			if vbox.get_child_count() > 0 and vbox.get_child(0) is HBoxContainer:
				title_bar = vbox.get_child(0)
				break

	if title_bar == null:
		return

	# 查找是否已有备份状态标签
	var backup_label = null
	for child in title_bar.get_children():
		if child is Label and child.name == "BackupStatusLabel":
			backup_label = child
			break

	# 检查是否有备份
	var has_backup = backed_up_saves.has(save_id)

	# 确保标签存在且可见
	if backup_label != null:
		if has_backup:
			backup_label.text = "✓ 已备份"
			backup_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))  # 绿色
			backup_label.visible = true
		else:
			backup_label.text = ""
			backup_label.visible = false


# 隐藏标题栏的备份状态标签
func _hide_backup_status_label_in_title(panel: Control) -> void:
	# 查找标题栏
	var title_bar = null
	for child in panel.get_children():
		if child is VBoxContainer:
			var vbox = child as VBoxContainer
			if vbox.get_child_count() > 0 and vbox.get_child(0) is HBoxContainer:
				title_bar = vbox.get_child(0)
				break

	if title_bar == null:
		return

	# 查找备份状态标签并隐藏
	for child in title_bar.get_children():
		if child is Label and child.name == "BackupStatusLabel":
			child.visible = false
			break


# 从备份路径中提取备份时间
func _extract_backup_time(backup_path: String) -> String:
	# 备份路径格式可能是:
	# 1. steam_76561199032814693_2024-01-01_12-00-00 (下划线分隔)
	# 2. steam_76561199032814693_2024-01-01T12-00-00 (T分隔)
	# 3. backup_2024-01-01_12-00-00 (旧格式)
	# 4. steam_76561199032814693_auto_2024-01-01_12-00-00 (自动备份)
	# 5. steam_76561199032814693_manual_2024-01-01_12-00-00 (手动备份)
	var folder_name = backup_path.get_file()

	# 首先尝试同时匹配日期和时间 (支持 _ 或 T 分隔)
	# 格式: YYYY-MM-DD_HH-MM-SS 或 YYYY-MM-DDTHH-MM-SS
	var full_pattern = "(\\d{4}-\\d{2}-\\d{2})[_T](\\d{2}-\\d{2}-\\d{2})"
	var regex = RegEx.new()
	regex.compile(full_pattern)
	var match_result = regex.search(folder_name)

	if match_result:
		var date_str = match_result.get_string(1)
		var time_str = match_result.get_string(2)
		# 将 - 替换为 :
		time_str = time_str.replace("-", ":")
		return date_str + " " + time_str

	# 如果没找到，尝试只匹配日期
	var date_pattern = "\\d{4}-\\d{2}-\\d{2}"
	regex.compile(date_pattern)
	var date_match = regex.search(folder_name)

	if date_match:
		var date_str = date_match.get_string()
		return date_str

	# 如果都没找到，返回原始文件夹名
	return folder_name


# 从备份路径中提取备份类型（自动或手动）
func _extract_backup_type(backup_path: String) -> String:
	var folder_name = backup_path.get_file()
	# 检查是否包含 auto_ 或 manual_ 标记
	if "_auto_" in folder_name:
		return "auto"
	elif "_manual_" in folder_name:
		return "manual"
	# 旧格式的备份没有标记，默认视为手动备份
	return "manual"


# 添加备份状态标签到存档面板
func _add_backup_status_label(panel: Control, save_id: String) -> void:
	# 查找标题栏
	var title_bar = null
	for child in panel.get_children():
		if child is VBoxContainer:
			var vbox = child as VBoxContainer
			if vbox.get_child_count() > 0 and vbox.get_child(0) is HBoxContainer:
				title_bar = vbox.get_child(0)
				break

	if title_bar == null:
		return

	# 在标题栏添加备份状态标签
	var backup_label = Label.new()
	backup_label.name = "BackupStatus"
	backup_label.text = "✓ 已备份"
	backup_label.add_theme_font_size_override("font_size", 12)
	backup_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1))  # 绿色
	backup_label.custom_minimum_size = Vector2(70, 0)

	# 在删除按钮之前插入
	var insert_index = title_bar.get_child_count() - 1
	if insert_index > 0:
		title_bar.add_child(backup_label)
		title_bar.move_child(backup_label, insert_index)


# 浏览游戏路径
func _on_game_path_browse() -> void:
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.exe"]
	file_dialog.title = translate("select_game_exe")

	# 使用file_selected而非dir_selected
	file_dialog.file_selected.connect(func(path: String):
		if game_path_edit:
			# 保存exe文件路径，实际使用需要获取其所在目录
			var exe_path = path
			# 提取目录路径（游戏根目录）
			var game_dir = exe_path.get_base_dir()
			game_path = game_dir  # 更新全局变量
			game_path_edit.text = game_dir
	)

	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))


# 自动检测游戏路径
func _on_game_path_detect() -> void:
	var detected_path = _detect_game_path()
	if not detected_path.is_empty():
		game_path = detected_path
		if game_path_edit:
			game_path_edit.text = game_path
		show_notification(translate("path_detected") + ": " + game_path, true)
	else:
		show_notification(translate("path_detection_failed") + " - " + translate("select_game_path"), false)


# 联机补丁路径浏览
func _on_fix_steam_path_browse() -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	dialog.title = translate("fix_steam_path_placeholder")
	dialog.dir_selected.connect(_on_fix_steam_dir_selected)
	add_child(dialog)
	dialog.popup()

func _on_fix_steam_dir_selected(dir_path: String) -> void:
	fix_steam_path = dir_path
	if fix_steam_path_edit:
		fix_steam_path_edit.text = dir_path
	_update_fix_steam_checkbox_state()

# 联机补丁路径自动检测
func _on_fix_steam_path_detect() -> void:
	var base_path = get_base_path()
	var detected_path = base_path + "fix_steam"
	if DirAccess.dir_exists_absolute(detected_path):
		fix_steam_path = detected_path
		if fix_steam_path_edit:
			fix_steam_path_edit.text = detected_path
		show_notification(translate("path_detected") + ": " + detected_path, true)
		_update_fix_steam_checkbox_state()
	else:
		show_notification(translate("fix_steam_path_not_found"), false)

# 更新联机补丁复选框状态
func _update_fix_steam_checkbox_state() -> void:
	if enable_fix_steam_check:
		if fix_steam_path.is_empty():
			enable_fix_steam_check.disabled = true
			enable_fix_steam_check.button_pressed = false # 禁用时取消勾选
			enable_fix_steam_check.tooltip_text = translate("fix_steam_path_not_set")
		else:
			enable_fix_steam_check.disabled = false
			enable_fix_steam_check.tooltip_text = translate("enable_fix_steam_desc")

# 联机补丁路径变更回调
func _on_fix_steam_path_changed(new_text: String) -> void:
	fix_steam_path = new_text
	_update_fix_steam_checkbox_state()

# 检测游戏路径
func _detect_game_path() -> String:
	# 常见的Steam游戏安装路径
	var common_paths = [
		"C:/Program Files/Steam/steamapps/common/Slay The Spire 2",
		"C:/Program Files (x86)/Steam/steamapps/common/Slay The Spire 2",
		"D:/Steam/steamapps/common/Slay The Spire 2",
		"D:/Program Files/Steam/steamapps/common/Slay The Spire 2",
	]

	for path in common_paths:
		if DirAccess.dir_exists_absolute(path):
			return path

	# 尝试从Steam库中查找
	var steam_path = _find_steam_game_path("SlayTheSpire2")
	if not steam_path.is_empty():
		return steam_path

	return ""


# 从Steam库中查找游戏
func _find_steam_game_path(app_name: String) -> String:
	# 读取Steam配置文件获取库路径
	var steam_base = "C:/Program Files/Steam"
	var library_vdf = steam_base.path_join("steamapps/libraryfolders.vdf")

	if not FileAccess.file_exists(library_vdf):
		return ""

	# 解析libraryfolders.vdf获取所有库路径
	var library_paths = [steam_base]

	var file = FileAccess.open(library_vdf, FileAccess.READ)
	if file != null:
		var content = file.get_as_text()
		file.close()

		# 简单的正则匹配获取路径
		var regex = RegEx.new()
		regex.compile('"path"\\s*"([^"]+)"')
		var results = regex.search_all(content)
		for result in results:
			var path = result.get_string(1).replace("\\\\", "/")
			library_paths.append(path)

	# 在每个库路径中查找游戏
	for library_path in library_paths:
		var game_path = library_path.path_join("steamapps/common").path_join(app_name)
		if DirAccess.dir_exists_absolute(game_path):
			return game_path

	return ""


# 浏览存档路径
func _on_save_path_browse() -> void:
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.title = translate("select_save_path")

	file_dialog.dir_selected.connect(func(path: String):
		if save_path_edit:
			save_path_edit.text = path
	)

	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))


# 自动检测存档路径
func _on_save_path_detect() -> void:
	var detected_path = _detect_save_path()
	if not detected_path.is_empty():
		save_path = detected_path
		if save_path_edit:
			save_path_edit.text = save_path
		show_notification(translate("path_detected") + ": " + save_path, true)
	else:
		show_notification(translate("path_detection_failed") + " - " + translate("select_save_path"), false)


# 自动检测GSE云存档路径
func _on_gse_cloud_detect() -> void:
	# 检测所有可用的GSE存档ID
	var gse_ids = SaveUtils.detect_gse_app_ids()

	if gse_ids.is_empty():
		show_notification("未检测到GSE云存档路径", false)
		return

	# 如果只有一个，直接使用
	if gse_ids.size() == 1:
		gse_cloud_path = gse_ids[0].get("path", "")
		if gse_cloud_path_edit:
			gse_cloud_path_edit.text = gse_cloud_path
		show_notification(translate("path_detected") + ": " + gse_cloud_path, true)
		return

	# 多个ID，弹出选择对话框
	_show_gse_id_select_dialog(gse_ids)


# GSE ID选择对话框
func _show_gse_id_select_dialog(gse_ids: Array) -> void:
	var dialog = Window.new()
	dialog.name = "GSESelectDialog"
	dialog.title = translate("select_gse_id")
	dialog.transient = true
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	dialog.size = Vector2i(350, 250)
	add_child(dialog)
	dialog.close_requested.connect(func(): dialog.queue_free())

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	vbox.add_theme_constant_override("margin_left", 16)
	vbox.add_theme_constant_override("margin_right", 16)
	vbox.add_theme_constant_override("margin_top", 16)
	vbox.add_theme_constant_override("margin_bottom", 16)
	dialog.add_child(vbox)

	var info_label = Label.new()
	info_label.text = translate("select_gse_id_desc")
	vbox.add_child(info_label)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 150
	vbox.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)

	# 创建选项按钮
	for gse_info in gse_ids:
		var btn = Button.new()
		btn.text = gse_info.get("display_name", "ID: " + gse_info.get("app_id", ""))
		btn.custom_minimum_size.y = 40
		btn.pressed.connect(func():
			gse_cloud_path = gse_info.get("path", "")
			if gse_cloud_path_edit:
				gse_cloud_path_edit.text = gse_cloud_path
			dialog.queue_free()
			show_notification("已选择GSE存档: " + gse_info.get("app_id", ""), true)
		)
		list_vbox.add_child(btn)

	# 按钮栏
	var btn_bar = HBoxContainer.new()
	btn_bar.custom_minimum_size.y = 36
	vbox.add_child(btn_bar)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bar.add_child(spacer)

	var cancel_btn = Button.new()
	cancel_btn.text = translate("cancel")
	cancel_btn.custom_minimum_size.x = 80
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	btn_bar.add_child(cancel_btn)

	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.popup_centered()


# 自动检测Steam云存档路径
func _on_steam_cloud_detect() -> void:
	var detected_path = SaveUtils.detect_steam_cloud_save_path()
	if not detected_path.is_empty():
		steam_cloud_path = detected_path
		if steam_cloud_path_edit:
			steam_cloud_path_edit.text = steam_cloud_path
		show_notification(translate("path_detected") + ": " + detected_path, true)
	else:
		show_notification("未检测到Steam云存档路径", false)


# 浏览GSE云存档路径
func _on_gse_cloud_browse() -> void:
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.title = "选择GSE云存档目录"

	file_dialog.dir_selected.connect(func(path: String):
		gse_cloud_path = path
		if gse_cloud_path_edit:
			gse_cloud_path_edit.text = path
	)

	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))


# 浏览Steam云存档路径
func _on_steam_cloud_browse() -> void:
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.title = "选择Steam云存档目录"

	file_dialog.dir_selected.connect(func(path: String):
		steam_cloud_path = path
		if steam_cloud_path_edit:
			steam_cloud_path_edit.text = path
	)

	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))


# 检测存档路径
func _detect_save_path() -> String:
	# 存档目录结构:
	# save/steam/[SteamID]/profile1/ - Steam云存档
	# save/modded/profile1/ - 模组版存档
	# save/profile1/ - 本地存档

	var appdata = OS.get_environment("APPDATA")
	var username = OS.get_environment("USERNAME")

	# 收集所有可能的基础路径
	var possible_base_paths = []

	# 1. 用户提供的格式: C:\Users\guo\AppData\Roaming\SlayTheSpire2
	#    其下有 steam/ 和 modded/ 子目录
	if appdata:
		possible_base_paths.append(appdata.path_join("SlayTheSpire2"))
	if username:
		possible_base_paths.append("C:/Users/" + username + "/AppData/Roaming/SlayTheSpire2")

	# 2. 基于游戏路径
	if not game_path.is_empty():
		possible_base_paths.append(game_path.get_base_dir().path_join("save"))

	# 检查每个可能的基础路径
	for base_path in possible_base_paths:
		if not DirAccess.dir_exists_absolute(base_path):
			continue

		print("检测到存档基础路径: ", base_path)

		# 检查是否有 steam/ 或 modded/ 子目录
		var has_steam = DirAccess.dir_exists_absolute(base_path.path_join("steam"))
		var has_modded = DirAccess.dir_exists_absolute(base_path.path_join("modded"))
		var has_profile = DirAccess.dir_exists_absolute(base_path.path_join("profile1"))

		print("  steam/: ", has_steam, " modded/: ", has_modded, " profile1/: ", has_profile)

		# 优先返回 steam/ 目录（用户主要使用的）
		if has_steam:
			# 返回steam目录，让程序可以扫描所有账号
			var steam_dir = base_path.path_join("steam")
			var dir = DirAccess.open(steam_dir)
			if dir:
				# 检查是否有有效的SteamID目录
				dir.list_dir_begin()
				var item = dir.get_next()
				while item != "":
					if dir.current_is_dir() and item.is_valid_int():
						var steam_id_path = steam_dir.path_join(item)
						if DirAccess.dir_exists_absolute(steam_id_path.path_join("profile1")):
							print("  找到Steam ID目录: ", item)
							# 返回父目录steam/而不是特定账号，以便扫描所有账号
							return steam_dir
					item = dir.get_next()
				dir.list_dir_end()
				# 如果没有找到SteamID但有steam目录，也返回
				return steam_dir

		# 返回 modded/ 目录
		if has_modded:
			print("  使用 modded/ 目录: ", base_path.path_join("modded"))
			return base_path.path_join("modded")

		# 返回本地存档
		if has_profile:
			print("  使用本地存档: ", base_path)
			return base_path

	return ""


# 展开环境变量
func _expand_env_vars(path: String) -> String:
	var result = path
	result = result.replace("%APPDATA%", OS.get_environment("APPDATA"))
	result = result.replace("%LOCALAPPDATA%", OS.get_environment("LOCALAPPDATA"))
	result = result.replace("%USERPROFILE%", OS.get_environment("USERPROFILE"))
	return result


# 语言切换
func _on_language_changed(index: int) -> void:
	var new_lang = "zh_CN" if index == 0 else "en_US"
	if new_lang != current_language:
		current_language = new_lang
		# 重新加载语言文件
		load_locale()
		# 更新窗口标题（应用名 + 版本）
		get_tree().root.title = translate("app_name") + " v2.1.0 (beta)"

		# 刷新所有UI文本
		_refresh_all_ui_text()


# DPI 缩放变化回调
func _on_dpi_scale_changed(value: float) -> void:
	print("[_on_dpi_scale_changed] value: ", value)
	dpi_scale = clamp(value, DPI_SCALE_MIN, DPI_SCALE_MAX)
	_apply_font_scale()
	if dpi_scale_value_label:
		dpi_scale_value_label.text = str(int(dpi_scale * 100)) + "%"
		print("[_on_dpi_scale_changed] Updated label to: ", dpi_scale_value_label.text)
	else:
		print("[_on_dpi_scale_changed] dpi_scale_value_label is null!")


# 刷新所有UI文本
func _refresh_all_ui_text() -> void:
	# 确保获取tab_container引用
	if not tab_container:
		tab_container = find_child_node(self, "TabContainer")

	# 刷新Tab标题
	if tab_container:
		tab_container.set_tab_title(0, translate("mods"))
		tab_container.set_tab_title(1, translate("bundle_tab"))
		tab_container.set_tab_title(2, translate("saves"))
		tab_container.set_tab_title(3, translate("nexus_mods"))
		tab_container.set_tab_title(4, translate("downloads"))
		tab_container.set_tab_title(5, translate("settings"))
		if tab_container.get_tab_count() > 5:
			tab_container.set_tab_title(5, translate("tutorial"))

	# 刷新模组页按钮文本
	if search_button:
		search_button.text = translate("search")
	if install_mod_button:
		install_mod_button.text = translate("install_mod")
	if uninstall_mod_button:
		uninstall_mod_button.text = translate("uninstall_mod")
	if batch_enable_button:
		batch_enable_button.text = translate("batch_enable")
	if batch_uninstall_button:
		batch_uninstall_button.text = translate("batch_uninstall")
	if batch_select_button:
		batch_select_button.text = translate("select_all")

	# 刷新搜索框placeholder
	if mod_search:
		mod_search.placeholder_text = translate("search_hint")

	# 刷新排序选项
	if sort_option:
		var current_sort = sort_option.selected
		sort_option.clear()
		sort_option.add_item(translate("sort_by_name"))
		sort_option.add_item(translate("sort_by_time"))
		sort_option.add_item(translate("sort_by_version"))
		sort_option.add_item(translate("sort_by_author"))
		sort_option.selected = current_sort

	# 刷新分类过滤
	if category_filter:
		var current_cat = category_filter.selected
		category_filter.clear()
		category_filter.add_item(translate("all"))
		category_filter.add_item(translate("gameplay_mods"))
		category_filter.add_item(translate("cosmetic_mods"))
		category_filter.selected = current_cat

	# 刷新标签按钮
	_build_tag_buttons()

	# 刷新存档页按钮
	_refresh_save_tab_buttons()

	# 刷新设置页面的文本
	_refresh_settings_ui_text()

	# 刷新下载页面的文本
	_refresh_download_ui()

	# 刷新N网页面的文本
	if nexus_mods_instance and "refresh_ui_text" in nexus_mods_instance:
		nexus_mods_instance.refresh_ui_text()

	# 刷新模组列表显示（这会刷新模组计数标签的文本）
	update_mod_list_display()

	print("[_refresh_all_ui_text] UI text refreshed for language: ", current_language)


# 刷新下载页面文本
func _refresh_download_ui() -> void:
	# 获取下载页面节点
	var current_downloads_label = find_child_node(self, "ActiveDownloadsLabel")
	var open_folder_btn = find_child_node(self, "OpenFolderBtn")
	var no_download_label = find_child_node(self, "NoDownloadsLabel")
	var history_label = find_child_node(self, "HistoryLabel")
	var clear_history_btn = find_child_node(self, "ClearHistoryBtn")

	if current_downloads_label:
		current_downloads_label.text = translate("current_downloads")
	if open_folder_btn:
		open_folder_btn.text = translate("open_folder")
	if no_download_label:
		no_download_label.text = translate("no_download_task")
	if history_label:
		history_label.text = translate("download_history")
	if clear_history_btn:
		clear_history_btn.text = translate("clear_history")


# 刷新存档页按钮文本
func _refresh_save_tab_buttons() -> void:
	if import_save_button:
		import_save_button.text = translate("import")
	if export_save_button:
		export_save_button.text = translate("export")
	if backup_save_button:
		backup_save_button.text = translate("backup")
	if restore_save_button:
		restore_save_button.text = translate("restore")
	if overwrite_save_button:
		overwrite_save_button.text = translate("overwrite")


# 刷新设置页面的文本
func _refresh_settings_ui_text() -> void:
	# 刷新路径标签
	var game_path_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/GamePathLabel")
	var save_path_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/SavePathLabel")
	var language_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/LanguageSection/LanguageLabel")

	if game_path_label:
		game_path_label.text = translate("game_path")
	if save_path_label:
		save_path_label.text = translate("save_path")
	if language_label:
		language_label.text = translate("language")

	# 刷新浏览和自动检测按钮文本
	var game_path_browse_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/GamePathRow/GamePathBrowseBtn")
	var game_path_detect_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/GamePathRow/GamePathDetectBtn")
	var save_path_browse_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/SavePathRow/SavePathBrowseBtn")
	var save_path_detect_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/PathsSection/SavePathRow/SavePathDetectBtn")

	if game_path_browse_btn:
		game_path_browse_btn.text = translate("browse")
	if game_path_detect_btn:
		game_path_detect_btn.text = translate("auto_detect")
	if save_path_browse_btn:
		save_path_browse_btn.text = translate("browse")
	if save_path_detect_btn:
		save_path_detect_btn.text = translate("auto_detect")

	# 刷新语言选项本身
	if language_option:
		language_option.clear()
		language_option.add_item("中文")
		language_option.add_item("English")
		language_option.selected = 0 if current_language == "zh_CN" else 1

	# 刷新启动设置Section
	var launch_section = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/LaunchSection")
	if launch_section:
		for child in launch_section.get_children():
			if child is Label:
				child.text = translate("launch_settings")
			elif child is HBoxContainer:
				# 联机补丁路径配置行
				if child.name == "FixSteamPathRow":
					for hchild in child.get_children():
						if hchild is Label and hchild.name == "FixSteamPathLabel":
							hchild.text = translate("fix_steam_path")
						elif hchild is LineEdit:
							hchild.placeholder_text = translate("fix_steam_path_placeholder")
						elif hchild is Button:
							if hchild.name == "FixSteamPathBrowseBtn":
								hchild.text = translate("browse")
							elif hchild.name == "FixSteamPathDetectBtn":
								hchild.text = translate("auto_detect")
			elif child is CheckBox:
				if child.name == "LaunchViaSteamCheck":
					child.text = translate("launch_via_steam")
				elif child.name == "EnableFixSteamCheck":
					child.text = translate("enable_fix_steam")
					child.tooltip_text = translate("enable_fix_steam_desc")

	# 刷新云端存档路径Section
	var cloud_section = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/CloudSaveSection")
	if cloud_section:
		for child in cloud_section.get_children():
			if child is Label and child.name == "CloudSaveLabel":
				child.text = translate("cloud_save_paths")
			elif child is HBoxContainer:
				for hchild in child.get_children():
					if hchild is Label:
						# GSE和Steam标签
						if hchild.text.begins_with("GSE"):
							hchild.text = "GSE: "
						elif hchild.text.begins_with("Steam"):
							hchild.text = "Steam: "
					elif hchild is Button:
						# 刷新按钮文本
						if hchild.name.begins_with("GSE") and hchild.name.contains("Browse"):
							hchild.text = translate("browse")
						elif hchild.name.begins_with("GSE") and hchild.name.contains("Detect"):
							hchild.text = translate("auto_detect")
						elif hchild.name.begins_with("Steam") and hchild.name.contains("Browse"):
							hchild.text = translate("browse")
						elif hchild.name.begins_with("Steam") and hchild.name.contains("Detect"):
							hchild.text = translate("auto_detect")

	# 刷新存储设置Section（模组存储文件夹、存档备份文件夹）
	var temp_mods_path_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/TempModsPathHeader/TempModsPathLabel")
	var temp_mods_path_tooltip = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/TempModsPathHeader/TempModsPathTooltipBtn")
	var backup_path_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/BackupPathHeader/BackupPathLabel")
	var backup_path_tooltip = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/BackupPathHeader/BackupPathTooltipBtn")

	if temp_mods_path_label:
		temp_mods_path_label.text = translate("temp_mods_path")
	if temp_mods_path_tooltip:
		temp_mods_path_tooltip.tooltip_text = translate("temp_mods_path_desc")
	if backup_path_label:
		backup_path_label.text = translate("backup_path_label")
	if backup_path_tooltip:
		backup_path_tooltip.tooltip_text = translate("backup_path_label_desc")

	# 刷新存储路径浏览按钮
	var temp_mods_browse_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/TempModsPathRow/TempModsPathBrowseBtn")
	var backup_browse_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/StorageSection/BackupPathRow/BackupPathBrowseBtn")
	if temp_mods_browse_btn:
		temp_mods_browse_btn.text = translate("browse")
	if backup_browse_btn:
		backup_browse_btn.text = translate("browse")

	# 刷新备份设置Section
	var auto_backup_check = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/BackupSection/AutoBackupCheck")
	var auto_backup_on_startup_check = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/BackupSection/AutoBackupOnStartupCheck")
	var auto_backup_max_count_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/BackupSection/AutoBackupMaxCountHBox/AutoBackupMaxCountLabel")
	if auto_backup_check:
		auto_backup_check.text = translate("auto_backup")
	if auto_backup_on_startup_check:
		auto_backup_on_startup_check.text = translate("auto_backup_on_startup")
	if auto_backup_max_count_label:
		auto_backup_max_count_label.text = translate("auto_backup_max_count")

	# 刷新模组JSON字段验证Section
	var mod_fields_section = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ModFieldsSection")
	if mod_fields_section:
		for child in mod_fields_section.get_children():
			if child is Label:
				# 第一个是标题，第二个是hint
				if child.get_index() == 0:
					child.text = translate("mod_json_fields")
				elif child.get_index() == 1:
					child.text = translate("mod_json_fields_hint")
			elif child is GridContainer:
				# 刷新字段复选框文本
				var field_labels = {
					"id": translate("field_id"),
					"name": translate("field_name"),
					"author": translate("field_author"),
					"description": translate("field_description"),
					"version": translate("field_version"),
					"has_pck": translate("field_has_pck"),
					"has_dll": translate("field_has_dll"),
					"affects_gameplay": translate("field_affects_gameplay"),
					"dependencies": translate("field_dependencies")
				}
				for checkbox in child.get_children():
					if checkbox is CheckBox:
						var field_name = checkbox.name.replace("Field_", "")
						checkbox.text = field_labels.get(field_name, field_name)

	# 刷新Nexus API Section
	var nexus_api_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusAPILabel")
	var nexus_api_key_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusAPIKeyRow/NexusAPIKeyEdit")
	var nexus_validate_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusAPIKeyRow/NexusValidateBtn")
	var nexus_status_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/NexusAPISection/NexusStatusLabel")

	if nexus_api_label:
		nexus_api_label.text = translate("nexus_api_section")
	if nexus_api_key_edit:
		nexus_api_key_edit.placeholder_text = translate("nexus_api_key_placeholder")
	if nexus_validate_btn:
		nexus_validate_btn.text = translate("nexus_validate")
	# 状态标签保持当前状态文本，不强制刷新（会覆盖验证结果）

	# 刷新保存按钮文本（如有）
	var save_settings_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/SaveSettingsBtn")
	if save_settings_btn:
		save_settings_btn.text = translate("confirm")

	# 刷新教程按钮文本
	var tutorial_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/TutorialBtn")
	if tutorial_btn:
		tutorial_btn.text = translate("tutorial_button")

	# 刷新清除备份按钮文本
	var clear_backups_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/BackupSection/ClearBackupsBtn")
	if not clear_backups_btn:
		clear_backups_btn = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ClearBackupsBtn")
	if clear_backups_btn:
		clear_backups_btn.text = translate("clear_all_backups")

	# 刷新服务器端口设置Section
	var server_port_section = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ServerPortSection")
	if server_port_section:
		for child in server_port_section.get_children():
			if child is Label:
				# 第一个是标题，第二个是描述，第三个是提示
				if child.get_index() == 0:
					child.text = translate("server_port")
			elif child is HBoxContainer:
				for hchild in child.get_children():
					if hchild is Label:
						hchild.text = translate("server_port")

	# 获取端口输入框并刷新
	var port_spin = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ServerPortSection/ServerPortRow/ServerPortSpin")
	if port_spin:
		port_spin.value = config.get_value("server", "port", 8765)



func _on_save_settings_pressed() -> void:
	# 获取输入的路径
	if game_path_edit:
		game_path = game_path_edit.text
	if save_path_edit:
		save_path = save_path_edit.text
	if fix_steam_path_edit:
		fix_steam_path = fix_steam_path_edit.text

	# 获取存储路径
	var old_temp_mods_path = temp_mods_path
	if temp_mods_path_edit:
		temp_mods_path = temp_mods_path_edit.text
	if backup_path_edit:
		backup_path = backup_path_edit.text

	# 获取模组JSON必要字段配置（从复选框读取）
	var fields_grid = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/ModFieldsSection/FieldsGrid")
	if fields_grid:
		mod_required_fields.clear()
		for child in fields_grid.get_children():
			if child is CheckBox and child.button_pressed:
				var field_name = child.name.replace("Field_", "")
				mod_required_fields.append(field_name)
		print("[_on_save_settings_pressed] mod_required_fields: ", mod_required_fields)

	# 获取自动备份设置
	var auto_backup = true
	if auto_backup_check:
		auto_backup = auto_backup_check.button_pressed

	# 获取启动时自动备份设置
	var auto_backup_on_startup = true
	if auto_backup_on_startup_check:
		auto_backup_on_startup = auto_backup_on_startup_check.button_pressed

	# 获取自动备份最大保留数量
	var auto_backup_max_count = 5
	if auto_backup_max_count_spin:
		auto_backup_max_count = int(auto_backup_max_count_spin.value)

	# 获取正版启动设置
	var launch_via_steam = true
	if launch_via_steam_check:
		launch_via_steam = launch_via_steam_check.button_pressed

	# 获取联机补丁设置
	var enable_fix_steam = false
	if enable_fix_steam_check:
		enable_fix_steam = enable_fix_steam_check.button_pressed
		print("[_on_save_settings_pressed] enable_fix_steam from checkbox: ", enable_fix_steam)
	else:
		print("[_on_save_settings_pressed] enable_fix_steam_check is null!")

	# 获取云端存档路径
	if gse_cloud_path_edit:
		gse_cloud_path = gse_cloud_path_edit.text
	if steam_cloud_path_edit:
		steam_cloud_path = steam_cloud_path_edit.text

	# 检查是否需要转移temp_mods文件
	var need_transfer = false
	if old_temp_mods_path != temp_mods_path and not old_temp_mods_path.is_empty():
		# 询问用户是否转移文件
		var dialog = ConfirmationDialog.new()
		dialog.title = translate("confirm")
		dialog.dialog_text = "存储路径已更改，是否将原模组文件转移到新位置？"
		dialog.ok_button_text = translate("confirm")
		dialog.cancel_button_text = translate("cancel")
		add_child(dialog)

		dialog.canceled.connect(func(): dialog.queue_free())
		dialog.confirmed.connect(func():
			dialog.queue_free()
			# 转移文件
			_transfer_directory(old_temp_mods_path, temp_mods_path)
			_finish_save_settings(auto_backup, auto_backup_on_startup, auto_backup_max_count, launch_via_steam, enable_fix_steam)
		)
		dialog.popup_centered(Vector2(400, 200))
		return

	_finish_save_settings(auto_backup, auto_backup_on_startup, auto_backup_max_count, launch_via_steam, enable_fix_steam)


func _finish_save_settings(auto_backup: bool, auto_backup_on_startup: bool, auto_backup_max_count: int, launch_via_steam: bool = true, enable_fix_steam: bool = false) -> void:
	print("[_finish_save_settings] enable_fix_steam received: ", enable_fix_steam)
	# 保存到配置文件
	config.set_value("paths", "game_path", game_path)
	config.set_value("paths", "save_path", save_path)
	config.set_value("paths", "gse_cloud_path", gse_cloud_path)
	config.set_value("paths", "steam_cloud_path", steam_cloud_path)
	config.set_value("paths", "temp_mods_path", temp_mods_path)
	config.set_value("paths", "backup_path", backup_path)
	config.set_value("paths", "fix_steam_path", fix_steam_path)
	config.set_value("settings", "language", current_language)
	config.set_value("settings", "dpi_scale", dpi_scale)
	config.set_value("settings", "auto_backup", auto_backup)
	config.set_value("settings", "auto_backup_on_startup", auto_backup_on_startup)
	config.set_value("settings", "auto_backup_max_count", auto_backup_max_count)
	config.set_value("settings", "launch_via_steam", launch_via_steam)
	config.set_value("settings", "enable_fix_steam", enable_fix_steam)

	# 保存模组JSON必要字段配置
	config.set_value("mods", "required_fields", mod_required_fields)
	config.set_value("mods", "optional_fields", mod_optional_fields)

	# 保存收纳盒子与覆盖顺序数据
	_save_mod_organization_data()

	var err = config.save(config_path)
	if err == OK:
		show_notification(translate("settings_saved"), true)
		settings_dirty = false  # 重置未保存状态
		# 更新联机补丁复选框状态
		_update_fix_steam_checkbox_state()
		# 重新加载存档
		load_saves()
		# 重新加载模组
		load_mods()
	else:
		show_notification(translate("settings_save_failed"), false)


# 转移目录文件
func _transfer_directory(from_path: String, to_path: String) -> bool:
	if not DirAccess.dir_exists_absolute(from_path):
		return false

	# 确保目标目录存在
	if not DirAccess.dir_exists_absolute(to_path):
		DirAccess.make_dir_recursive_absolute(to_path)

	# 复制文件
	var dir = DirAccess.open(from_path)
	if dir == null:
		return false

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var source_path = from_path.path_join(file_name)
			var dest_path = to_path.path_join(file_name)
			if dir.current_is_dir():
				_transfer_directory(source_path, dest_path)
			else:
				DirAccess.copy_absolute(source_path, dest_path)
		file_name = dir.get_next()
	dir.list_dir_end()

	# 删除原目录
	FileUtils.delete_directory(from_path)
	return true


# 浏览temp_mods路径
func _on_temp_mods_path_browse() -> void:
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.title = translate("select_temp_mods_path")

	file_dialog.dir_selected.connect(func(path: String):
		if temp_mods_path_edit:
			temp_mods_path_edit.text = path
	)

	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))


# 清除所有备份
func _on_clear_all_backups_pressed() -> void:
	# 确认对话框
	var confirm_dialog = Window.new()
	confirm_dialog.name = "ConfirmClearAllBackups"
	confirm_dialog.title = "确认删除"
	confirm_dialog.transient = true
	confirm_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	confirm_dialog.size = Vector2i(400, 200)
	add_child(confirm_dialog)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)
	vbox.add_theme_constant_override("margin_left", 24)
	vbox.add_theme_constant_override("margin_right", 24)
	vbox.add_theme_constant_override("margin_top", 24)
	vbox.add_theme_constant_override("margin_bottom", 24)
	confirm_dialog.add_child(vbox)

	var label = Label.new()
	label.text = "确定要删除所有备份吗？\n此操作不可恢复！"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1))
	vbox.add_child(label)

	var btn_bar = HBoxContainer.new()
	btn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_bar)

	var cancel_btn = Button.new()
	cancel_btn.text = translate("cancel")
	cancel_btn.custom_minimum_size.x = 80
	cancel_btn.pressed.connect(func(): confirm_dialog.queue_free())
	btn_bar.add_child(cancel_btn)

	var ok_btn = Button.new()
	ok_btn.text = translate("confirm")
	ok_btn.custom_minimum_size.x = 80
	ok_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1))
	ok_btn.pressed.connect(func():
		# 执行删除
		var backup_dir = backup_path
		if backup_dir.is_empty() or not DirAccess.dir_exists_absolute(backup_dir):
			show_notification(translate("invalid_backup_path"), false)
			confirm_dialog.queue_free()
			return

		# 删除备份目录下所有内容
		var deleted_count = 0
		var dir = DirAccess.open(backup_dir)
		if dir:
			dir.list_dir_begin()
			var item = dir.get_next()
			while item != "":
				if dir.current_is_dir():
					var full_path = backup_dir.path_join(item)
					if SaveUtils.delete_directory(full_path):
						deleted_count += 1
				item = dir.get_next()
			dir.list_dir_end()

		confirm_dialog.queue_free()
		load_saves()
		show_notification(translate_fmt("all_backups_deleted", [str(deleted_count)]), true)
	)
	btn_bar.add_child(ok_btn)

	confirm_dialog.popup_centered()


# 浏览备份路径
func _on_backup_path_browse() -> void:
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.title = translate("select_backup_path")

	file_dialog.dir_selected.connect(func(path: String):
		if backup_path_edit:
			backup_path_edit.text = path
	)

	add_child(file_dialog)
	file_dialog.popup_centered(Vector2(600, 400))


# 教程弹窗相关方法
func _show_tutorial_if_needed() -> void:
	# 延迟显示，让界面先渲染完成
	await get_tree().create_timer(0.5).timeout
	# 如果 game_path 仍然为空，显示教程
	if game_path.is_empty():
		_create_tutorial_panel()
		_show_tutorial_step(0)

func _create_tutorial_panel() -> void:
	# 如果已存在，先移除
	if tutorial_panel and is_instance_valid(tutorial_panel):
		tutorial_panel.queue_free()

	# 创建主面板
	tutorial_panel = Panel.new()
	tutorial_panel.custom_minimum_size = Vector2(480, 360)
	tutorial_panel.name = "TutorialPanel"

	# 设置居中位置
	var screen_size = get_tree().root.get_size()
	var x = (screen_size.x - 480) / 2
	var y = (screen_size.y - 360) / 2
	tutorial_panel.position = Vector2i(x, y)

	get_tree().root.add_child(tutorial_panel)

	# 设置样式（与现代扁平设计保持一致）
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.3, 1)
	style.set_corner_radius_all(8)
	tutorial_panel.add_theme_stylebox_override("panel", style)

	# 创建内部容器
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)
	tutorial_panel.add_child(vbox)

	# === 步骤指示器 ===
	var step_indicator = HBoxContainer.new()
	step_indicator.name = "StepIndicator"
	step_indicator.alignment = BoxContainer.ALIGNMENT_CENTER
	step_indicator.add_theme_constant_override("separation", 12)
	vbox.add_child(step_indicator)

	for i in range(tutorial_steps.size()):
		var dot = Label.new()
		dot.text = "●" if i == 0 else "○"
		dot.add_theme_font_size_override("font_size", 16)
		if i == 0:
			dot.add_theme_color_override("font_color", Color(0.2, 0.7, 0.9, 1))
		else:
			dot.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		step_indicator.add_child(dot)

	# === 标题 ===
	var title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	vbox.add_child(title_label)

	# === 内容 ===
	var content_label = RichTextLabel.new()
	content_label.name = "ContentLabel"
	content_label.bbcode_enabled = true
	content_label.fit_content = true
	content_label.custom_minimum_size = Vector2(400, 180)
	content_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(content_label)

	# === 配置游戏路径步骤的浏览按钮 ===
	var game_path_container = HBoxContainer.new()
	game_path_container.name = "GamePathContainer"
	game_path_container.alignment = BoxContainer.ALIGNMENT_CENTER
	game_path_container.add_theme_constant_override("separation", 10)
	game_path_container.visible = false
	vbox.add_child(game_path_container)

	var browse_btn = Button.new()
	browse_btn.text = translate("browse")
	browse_btn.name = "BrowseBtn"
	browse_btn.pressed.connect(_on_tutorial_browse_game_path)
	game_path_container.add_child(browse_btn)

	var detect_btn = Button.new()
	detect_btn.text = translate("auto_detect")
	detect_btn.name = "DetectBtn"
	detect_btn.pressed.connect(_on_tutorial_detect_game_path)
	game_path_container.add_child(detect_btn)

	# === 按钮行 ===
	var btn_row = HBoxContainer.new()
	btn_row.name = "BtnRow"
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var skip_btn = Button.new()
	skip_btn.text = translate("tutorial_skip")
	skip_btn.name = "SkipBtn"
	skip_btn.pressed.connect(_close_tutorial)
	btn_row.add_child(skip_btn)

	var prev_btn = Button.new()
	prev_btn.text = translate("tutorial_prev")
	prev_btn.name = "PrevBtn"
	prev_btn.pressed.connect(_tutorial_prev_step)
	btn_row.add_child(prev_btn)

	var next_btn = Button.new()
	next_btn.text = translate("tutorial_next")
	next_btn.name = "NextBtn"
	next_btn.pressed.connect(_tutorial_next_step)
	btn_row.add_child(next_btn)

func _show_tutorial_step(step: int) -> void:
	if not tutorial_panel or not is_instance_valid(tutorial_panel):
		return

	tutorial_current_step = step
	var vbox = tutorial_panel.get_node("VBoxContainer")

	# 更新步骤指示器
	var step_indicator = vbox.get_node("StepIndicator")
	for i in range(step_indicator.get_child_count()):
		var dot = step_indicator.get_child(i)
		if i == step:
			dot.text = "●"
			dot.add_theme_color_override("font_color", Color(0.2, 0.7, 0.9, 1))
		else:
			dot.text = "○"
			dot.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))

	# 更新标题和内容
	var title_label = vbox.get_node("TitleLabel")
	var content_label = vbox.get_node("ContentLabel")
	var game_path_container = vbox.get_node("GamePathContainer")
	var btn_row = vbox.get_node("BtnRow")
	var next_btn = btn_row.get_node("NextBtn")
	var prev_btn = btn_row.get_node("PrevBtn")

	# 根据步骤显示不同内容
	var step_key = tutorial_steps[step]
	match step_key:
		"welcome":
			title_label.text = translate("tutorial_welcome_title")
			content_label.text = translate("tutorial_welcome_content")
			game_path_container.visible = false
			prev_btn.visible = false
			next_btn.text = translate("tutorial_next")
		"game_path":
			title_label.text = translate("tutorial_game_path_title")
			content_label.text = translate("tutorial_game_path_content")
			game_path_container.visible = true
			prev_btn.visible = true
			next_btn.text = translate("tutorial_next")
		"mods":
			title_label.text = translate("tutorial_mods_title")
			content_label.text = translate("tutorial_mods_content")
			game_path_container.visible = false
			prev_btn.visible = true
			next_btn.text = translate("tutorial_next")
		"saves":
			title_label.text = translate("tutorial_saves_title")
			content_label.text = translate("tutorial_saves_content")
			game_path_container.visible = false
			prev_btn.visible = true
			next_btn.text = translate("tutorial_next")
		"nexus":
			title_label.text = translate("tutorial_nexus_title")
			content_label.text = translate("tutorial_nexus_content")
			game_path_container.visible = false
			prev_btn.visible = true
			next_btn.text = translate("tutorial_next")
		"nexus_api_tutorial":
			title_label.text = translate("tutorial_nexus_api_title")
			content_label.bbcode_text = (
				"[center]" + translate("nexus_api_step1") + "[/center]\n" +
				"[center]" + translate("nexus_api_step2") + "[/center]\n" +
				"[center]" + translate("nexus_api_step3") + "[/center]\n" +
				"[center]" + translate("nexus_api_step4") + "[/center]\n" +
				"[center]" + translate("nexus_api_step5") + "[/center]"
			)
			content_label.custom_minimum_size = Vector2(420, 130)
			game_path_container.visible = true
			for child in game_path_container.get_children():
				child.queue_free()
			var get_key_btn = Button.new()
			get_key_btn.text = translate("tutorial_get_nexus_api_key")
			get_key_btn.pressed.connect(_on_tutorial_get_nexus_api_key)
			game_path_container.add_child(get_key_btn)
			var config_btn = Button.new()
			config_btn.text = translate("tutorial_config_nexus_api")
			config_btn.pressed.connect(_on_tutorial_open_nexus_config)
			game_path_container.add_child(config_btn)
			prev_btn.visible = true
			next_btn.text = translate("tutorial_finish")

	# 调整内容区域高度
	if step_key == "game_path":
		content_label.custom_minimum_size = Vector2(400, 120)
	elif step_key == "nexus_api_tutorial":
		content_label.custom_minimum_size = Vector2(420, 130)
	else:
		content_label.custom_minimum_size = Vector2(400, 180)

func _tutorial_next_step() -> void:
	var step_key = tutorial_steps[tutorial_current_step]

	# 如果是游戏路径步骤，验证是否已配置
	if step_key == "game_path":
		if game_path.is_empty():
			show_notification(translate("tutorial_set_game_path_hint"), false)
			return

	if tutorial_current_step < tutorial_steps.size() - 1:
		_show_tutorial_step(tutorial_current_step + 1)
	else:
		# 教程完成
		_close_tutorial()

func _tutorial_prev_step() -> void:
	if tutorial_current_step > 0:
		_show_tutorial_step(tutorial_current_step - 1)

func _close_tutorial() -> void:
	if tutorial_panel and is_instance_valid(tutorial_panel):
		tutorial_panel.queue_free()
		tutorial_panel = null

	# 如果 game_path 已配置，保存到 config
	if not game_path.is_empty():
		config.set_value("paths", "game_path", game_path)
		config.save(config_path)
		print("[Tutorial] game_path saved to config")

	# 保存Nexus API Key到配置并同步到各实例
	var saved_api_key = config.get_value("nexus", "api_key", "")
	if not saved_api_key.is_empty():
		# 同步到本地服务器
		if local_server and nexus_api:
			nexus_api.set_api_key(saved_api_key)
		# 同步到N网UI实例
		if nexus_mods_instance:
			nexus_mods_instance.set_api_key(saved_api_key)

func _on_tutorial_browse_game_path() -> void:
	_on_game_path_browse()

func _on_tutorial_detect_game_path() -> void:
	_on_game_path_detect()
	# 刷新教程显示（如果 game_path 已配置）
	if not game_path.is_empty():
		_show_tutorial_step(tutorial_current_step)

func _show_tutorial_from_settings() -> void:
	"""从设置页面重新打开教程"""
	print("[_show_tutorial_from_settings] Called, tutorial_panel: ", tutorial_panel)
	if tutorial_panel and is_instance_valid(tutorial_panel):
		return

	print("[_show_tutorial_from_settings] Creating tutorial popup...")
	_create_tutorial_panel()

	if tutorial_panel and is_instance_valid(tutorial_panel):
		_show_tutorial_step(0)
	else:
		print("[_show_tutorial_from_settings] ERROR: tutorial_panel creation failed!")
func _api_scan_bundles(_params: Dictionary) -> Dictionary:
	if bundle_data.is_empty():
		_load_bundles()

	var bundles_array: Array = []
	for bundle_id in bundle_data:
		var bd = bundle_data[bundle_id].duplicate(true)
		bd["id"] = bundle_id
		bundles_array.append(bd)

	# 读取 active_bundle 和 selected_bundle_preset
	if active_bundle.is_empty():
		active_bundle = config.get_value("bundles", "active_bundle", "")

	return {"code": 200, "data": {"bundles": bundles_array, "active_bundle": active_bundle}}


func _api_enable_bundle(params: Dictionary) -> Dictionary:
	var bundle_id: String = params.get("bundle_id", "")
	var preset_name: String = params.get("preset_name", "")
	print("[_api_enable_bundle] Called with bundle_id: ", bundle_id, ", preset_name: ", preset_name)

	if not bundle_data.has(bundle_id):
		print("[_api_enable_bundle] Bundle not found: ", bundle_id)
		return {"code": 404, "data": {"success": false, "message": "Bundle not found"}}

	var bd = bundle_data[bundle_id]
	var presets = bd.get("presets", {})

	# 保存当前状态以便禁用时恢复（与原版 _enable_bundle 保持一致）
	var previous_enabled_mods_backup = enabled_mods.duplicate()
	var previous_tag_data_backup = tag_data.duplicate(true)

	# 确保游戏路径已设置
	if game_path.is_empty():
		game_path = config.get_value("paths", "game_path", "")
	if game_path.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Game path not set"}}

	var package_dir = _get_newpackage_dir()
	if package_dir.is_empty():
		return {"code": 500, "data": {"success": false, "message": "Package directory not available"}}

	var bundle_mods_dir = package_dir.path_join(bundle_id).path_join("mods")
	var game_mods_dir = game_path.path_join("mods")

	# 清空游戏 mods 文件夹 - 完全删除后重新创建
	if DirAccess.dir_exists_absolute(game_mods_dir):
		print("[_api_enable_bundle] Removing existing game mods dir: ", game_mods_dir)
		_delete_directory_recursive(game_mods_dir)

	DirAccess.make_dir_recursive_absolute(game_mods_dir)
	print("[_api_enable_bundle] Created fresh game mods dir: ", game_mods_dir)

	# 获取当前预设的模组列表
	var preset_mods = []
	if not presets.is_empty():
		var preset_names = presets.keys()

		# 优先使用 API 传入的 preset_name（Web UI 传递）
		if not preset_name.is_empty() and preset_name in presets:
			preset_mods = Array(presets[preset_name])
			print("[_api_enable_bundle] Using preset from API param: ", preset_name)
		# 其次使用保存的选中预设
		elif not selected_bundle_preset.is_empty() and selected_bundle_preset in presets:
			preset_mods = Array(presets[selected_bundle_preset])
			print("[_api_enable_bundle] Using saved selected_preset: ", selected_bundle_preset)
		# 其次使用 current_tag
		elif current_tag in presets:
			preset_mods = Array(presets[current_tag])
			print("[_api_enable_bundle] Using current_tag: ", current_tag)
		# 默认使用第一个预设
		elif preset_names.size() > 0:
			preset_mods = Array(presets[preset_names[0]])
			print("[_api_enable_bundle] Using first preset: ", preset_names[0])

	print("[_api_enable_bundle] Using preset mods count: ", preset_mods.size())

	# 从整合包复制模组到游戏目录
	var copied_mods = []
	var failed_mods = []

	for mod_id in preset_mods:
		var source_mod_dir = bundle_mods_dir.path_join(mod_id)
		var target_mod_dir = game_mods_dir.path_join(mod_id)

		if DirAccess.dir_exists_absolute(source_mod_dir):
			DirAccess.make_dir_recursive_absolute(target_mod_dir)
			FileUtils.copy_directory(source_mod_dir, target_mod_dir)
			copied_mods.append(mod_id)
			print("[_api_enable_bundle] Copied mod: ", mod_id)
		else:
			failed_mods.append(mod_id)
			print("[_api_enable_bundle] Mod not found in bundle: ", mod_id)

	# 更新 enabled_mods
	enabled_mods.clear()
	for mod_id in copied_mods:
		enabled_mods[mod_id] = true

	_save_enabled_mods()

	# 应用整合包中保存的预设（与原版 _enable_bundle 保持一致）
	if not presets.is_empty():
		tag_data = presets.duplicate(true)
		# 确保默认标签存在
		if not tag_data.has("单人模组"):
			tag_data["单人模组"] = []
		if not tag_data.has("联机模组"):
			tag_data["联机模组"] = []
		# 设置当前标签：优先使用 API 传入的 preset_name
		var preset_names = presets.keys()
		if not preset_name.is_empty() and preset_name in presets:
			current_tag = preset_name
			selected_bundle_preset = preset_name
		elif not selected_bundle_preset.is_empty() and selected_bundle_preset in presets:
			current_tag = selected_bundle_preset
		elif preset_names.size() > 0:
			current_tag = preset_names[0]
		_save_tag_data()

		# 保存选中的预设（与 _api_apply_bundle_preset 保持一致）
		var preset_to_save = current_tag if current_tag in presets else preset_names[0]
		selected_bundle_preset = preset_to_save
		var bundle_selected_presets = config.get_value("bundles", "bundle_selected_presets", {})
		bundle_selected_presets[bundle_id] = preset_to_save
		config.set_value("bundles", "bundle_selected_presets", bundle_selected_presets)

	active_bundle = bundle_id
	config.set_value("bundles", "active_bundle", active_bundle)

	# 保存之前的状态到 config（禁用时恢复）
	var previous_state = {
		"enabled_mods": previous_enabled_mods_backup,
		"tag_data": previous_tag_data_backup
	}
	config.set_value("bundles", "bundle_previous_state", previous_state)
	config.save(config_path)

	print("[_api_enable_bundle] Success! Copied count: ", copied_mods.size())
	return {"code": 200, "data": {"success": true, "message": "Bundle enabled", "enabled_count": copied_mods.size(), "copied_mods": copied_mods, "failed_mods": failed_mods}}


func _api_disable_bundle(params: Dictionary) -> Dictionary:
	var bundle_id: String = params.get("bundle_id", "")
	if not bundle_data.has(bundle_id):
		return {"code": 404, "data": {"success": false, "message": "Bundle not found"}}

	# 确保游戏路径已设置
	if game_path.is_empty():
		game_path = config.get_value("paths", "game_path", "")
	if game_path.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Game path not set"}}

	var game_mods_dir = game_path.path_join("mods")

	# 清空游戏 mods 文件夹 - 禁用整合包时清空所有模组文件
	if DirAccess.dir_exists_absolute(game_mods_dir):
		print("[_api_disable_bundle] Removing game mods dir: ", game_mods_dir)
		_delete_directory_recursive(game_mods_dir)

	# 恢复之前保存的状态（与原版 _disable_bundle_and_save_state 保持一致）
	var previous_state = config.get_value("bundles", "bundle_previous_state", {})
	if not previous_state.is_empty():
		var prev_enabled_mods = previous_state.get("enabled_mods", {})
		var prev_tag_data = previous_state.get("tag_data", {})

		# 恢复 enabled_mods 并复制模组文件到游戏目录
		if not prev_enabled_mods.is_empty():
			enabled_mods = prev_enabled_mods.duplicate()
			# 从 temp_mods 目录复制启用的模组到游戏目录（Web UI 安装的模组存储在 temp_mods）
			var temp_mods_dir = get_base_path().path_join("temp_mods")

			for mod_id in prev_enabled_mods:
				if prev_enabled_mods[mod_id]:
					var source_mod_dir = temp_mods_dir.path_join(mod_id)
					var target_mod_dir = game_mods_dir.path_join(mod_id)

					if DirAccess.dir_exists_absolute(source_mod_dir):
						DirAccess.make_dir_recursive_absolute(target_mod_dir)
						FileUtils.copy_directory(source_mod_dir, target_mod_dir)
						print("[_api_disable_bundle] Restored mod: ", mod_id)

			print("[_api_disable_bundle] Restored enabled_mods: ", enabled_mods.size())

		# 恢复 tag_data
		if not prev_tag_data.is_empty():
			tag_data = prev_tag_data.duplicate(true)
			# 恢复 current_tag
			if tag_data.size() > 0:
				var tag_keys = tag_data.keys()
				if tag_keys.size() > 0:
					current_tag = tag_keys[0]
			print("[_api_disable_bundle] Restored tag_data: ", tag_data.keys())

		# 清除保存的状态
		config.set_value("bundles", "bundle_previous_state", {})
	else:
		# 没有保存的状态，清空 enabled_mods
		enabled_mods.clear()
		print("[_api_disable_bundle] No previous state to restore")

	_save_enabled_mods()
	_save_tag_data()

	# 清除 active_bundle
	if active_bundle == bundle_id:
		active_bundle = ""
		config.set_value("bundles", "active_bundle", "")
		config.save(config_path)

	print("[_api_disable_bundle] Success! Bundle disabled: ", bundle_id)
	return {"code": 200, "data": {"success": true, "message": "Bundle disabled", "bundle_id": bundle_id}}


func _api_delete_bundle(params: Dictionary) -> Dictionary:
	var bundle_id: String = params.get("bundle_id", "")
	var package_dir = _get_newpackage_dir().path_join(bundle_id)
	print("[_api_delete_bundle] bundle_id: ", bundle_id)
	print("[_api_delete_bundle] package_dir: ", package_dir)
	print("[_api_delete_bundle] package_dir exists: ", DirAccess.dir_exists_absolute(package_dir))
	print("[_api_delete_bundle] bundle_data has bundle_id: ", bundle_data.has(bundle_id))

	# 检查 bundle_data 中是否有此 bundle
	if bundle_data.has(bundle_id):
		# 先禁用
		_api_disable_bundle(params)
		# 删除目录（如果存在）- 使用递归删除
		if DirAccess.dir_exists_absolute(package_dir):
			print("[_api_delete_bundle] Deleting directory recursively: ", package_dir)
			_delete_directory_recursive(package_dir)
			# 验证是否删除成功
			if DirAccess.dir_exists_absolute(package_dir):
				print("[_api_delete_bundle] Warning: Directory still exists after deletion attempt")
			else:
				print("[_api_delete_bundle] Directory deleted successfully")
		else:
			print("[_api_delete_bundle] Package directory does not exist, skipping file deletion")

		# 从内存中移除
		bundle_data.erase(bundle_id)
		print("[_api_delete_bundle] Bundle removed from bundle_data")
		return {"code": 200, "data": {"success": true, "message": "Bundle deleted"}}

	print("[_api_delete_bundle] Bundle not found in bundle_data")
	return {"code": 404, "data": {"success": false, "message": "Bundle not found"}}


func _api_import_bundle(params: Dictionary) -> Dictionary:
	var filename: String = params.get("filename", "")
	var data_base64: String = params.get("data_base64", "")

	if data_base64.is_empty():
		return {"code": 400, "data": {"success": false, "message": "No file data"}}

	var bytes = Marshalls.base64_to_raw(data_base64)
	var temp_path = get_base_path().path_join("temp_upload_bundle_" + filename)
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"code": 500, "data": {"success": false, "message": "Failed to write temp file"}}
	file.store_buffer(bytes)
	file.close()

	# 先解压到临时目录，检测 bundle.json 是否存在
	var temp_extract_dir = get_base_path().path_join("temp_bundle_check_" + str(Time.get_unix_time_from_system()))
	DirAccess.make_dir_recursive_absolute(temp_extract_dir)

	var reader = ZIPReader.new()
	if reader.open(temp_path) == OK:
		var files = reader.get_files()
		for f in files:
			var file_data = reader.read_file(f)
			var out_path = temp_extract_dir.path_join(f)
			var out_dir = out_path.get_base_dir()
			DirAccess.make_dir_recursive_absolute(out_dir)
			var out_file = FileAccess.open(out_path, FileAccess.WRITE)
			if out_file:
				out_file.store_buffer(file_data)
				out_file.close()
		reader.close()

	# 检测 bundle.json 是否存在（判断是否是有效的整合包）
	# 先检查根目录，再检查子目录
	var bundle_json_found = false
	var bundle_id = ""
	var bundle_name = ""

	# 先检查根目录是否有 bundle.json
	if FileAccess.file_exists(temp_extract_dir.path_join("bundle.json")):
		bundle_json_found = true
		bundle_id = "bundle_" + str(Time.get_unix_time_from_system())
		var json_data = _load_json(temp_extract_dir.path_join("bundle.json"))
		if not json_data.is_empty():
			bundle_name = json_data.get("name", bundle_id)
	else:
		# 根目录没有，检查子目录
		var dir = DirAccess.open(temp_extract_dir)
		if dir:
			dir.list_dir_begin()
			var entry = dir.get_next()
			while entry != "":
				if dir.current_is_dir() and entry != "." and entry != "..":
					var test_json = temp_extract_dir.path_join(entry).path_join("bundle.json")
					if FileAccess.file_exists(test_json):
						bundle_json_found = true
						bundle_id = entry
						# 读取 bundle.json 获取名称
						var json_data = _load_json(test_json)
						if not json_data.is_empty():
							bundle_name = json_data.get("name", entry)
						break
				entry = dir.get_next()
			dir.list_dir_end()

	if not bundle_json_found:
		# 清理临时文件
		_delete_directory_recursive(temp_extract_dir)
		DirAccess.remove_absolute(temp_path)
		return {"code": 400, "data": {
			"success": false,
			"message": "不是有效的整合包：缺少 bundle.json 文件",
			"error_type": "missing_bundle_json"
		}}

	# 是有效的整合包，正式解压到 pack_mods/
	var dest_dir = _get_newpackage_dir().path_join(bundle_id)
	DirAccess.make_dir_recursive_absolute(dest_dir)

	# 复制文件（从临时目录到目标目录）
	var temp_dir = DirAccess.open(temp_extract_dir)
	if temp_dir:
		temp_dir.list_dir_begin()
		var entry = temp_dir.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var src_path = temp_extract_dir.path_join(entry)
				var dest_path = dest_dir.path_join(entry)
				if temp_dir.current_is_dir():
					DirAccess.make_dir_recursive_absolute(dest_path)
					_copy_directory_recursive(src_path, dest_path)
				else:
					var file_data = FileAccess.get_file_as_bytes(src_path)
					if file_data:
						var out_file = FileAccess.open(dest_path, FileAccess.WRITE)
						if out_file:
							out_file.store_buffer(file_data)
							out_file.close()
			entry = temp_dir.get_next()
		temp_dir.list_dir_end()

	# 清理临时文件
	_delete_directory_recursive(temp_extract_dir)
	DirAccess.remove_absolute(temp_path)

	_load_bundles()

	print("[_api_import_bundle] Bundle imported: ", bundle_name, " (", bundle_id, ")")
	return {"code": 200, "data": {
		"success": true,
		"message": "Bundle imported",
		"bundle_id": bundle_id,
		"bundle_name": bundle_name
	}}


func _api_import_bundle_local(params: Dictionary) -> Dictionary:
	var file_path: String = params.get("file_path", "")

	if file_path.is_empty():
		return {"code": 400, "data": {"success": false, "message": "No file path"}}

	print("[_api_import_bundle_local] Reading local file: ", file_path)

	# 直接读取本地 ZIP 文件
	var temp_path = file_path  # 直接使用用户选择的文件路径

	if not FileAccess.file_exists(temp_path):
		return {"code": 400, "data": {"success": false, "message": "File not found: " + temp_path}}

	# 获取文件名
	var filename = temp_path.get_file()
	if not filename.ends_with(".zip"):
		filename += ".zip"

	# 先解压到临时目录，检测 bundle.json 是否存在
	var temp_extract_dir = get_base_path().path_join("temp_bundle_check_" + str(Time.get_unix_time_from_system()))
	DirAccess.make_dir_recursive_absolute(temp_extract_dir)

	var reader = ZIPReader.new()
	if reader.open(temp_path) == OK:
		var files = reader.get_files()
		for f in files:
			var file_data = reader.read_file(f)
			var out_path = temp_extract_dir.path_join(f)
			var out_dir = out_path.get_base_dir()
			DirAccess.make_dir_recursive_absolute(out_dir)
			var out_file = FileAccess.open(out_path, FileAccess.WRITE)
			if out_file:
				out_file.store_buffer(file_data)
				out_file.close()
		reader.close()

	# 检测 bundle.json 是否存在（判断是否是有效的整合包）
	var bundle_json_found = false
	var bundle_id = ""
	var bundle_name = ""

	# 先检查根目录是否有 bundle.json
	if FileAccess.file_exists(temp_extract_dir.path_join("bundle.json")):
		bundle_json_found = true
		bundle_id = "bundle_" + str(Time.get_unix_time_from_system())
		var json_data = _load_json(temp_extract_dir.path_join("bundle.json"))
		if not json_data.is_empty():
			bundle_name = json_data.get("name", bundle_id)
	else:
		# 根目录没有，检查子目录
		var dir = DirAccess.open(temp_extract_dir)
		if dir:
			dir.list_dir_begin()
			var entry = dir.get_next()
			while entry != "":
				if dir.current_is_dir() and entry != "." and entry != "..":
					var test_json = temp_extract_dir.path_join(entry).path_join("bundle.json")
					if FileAccess.file_exists(test_json):
						bundle_json_found = true
						bundle_id = entry
						var json_data = _load_json(test_json)
						if not json_data.is_empty():
							bundle_name = json_data.get("name", entry)
						break
				entry = dir.get_next()
			dir.list_dir_end()

	if not bundle_json_found:
		_delete_directory_recursive(temp_extract_dir)
		return {"code": 400, "data": {
			"success": false,
			"message": "不是有效的整合包：缺少 bundle.json 文件",
			"error_type": "missing_bundle_json"
		}}

	# 是有效的整合包，正式解压到 pack_mods/
	var dest_dir = _get_newpackage_dir().path_join(bundle_id)
	DirAccess.make_dir_recursive_absolute(dest_dir)

	# 复制文件
	var temp_dir = DirAccess.open(temp_extract_dir)
	if temp_dir:
		temp_dir.list_dir_begin()
		var entry = temp_dir.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var src_path = temp_extract_dir.path_join(entry)
				var dest_path = dest_dir.path_join(entry)
				if temp_dir.current_is_dir():
					DirAccess.make_dir_recursive_absolute(dest_path)
					_copy_directory_recursive(src_path, dest_path)
				else:
					var file_data = FileAccess.get_file_as_bytes(src_path)
					if file_data:
						var out_file = FileAccess.open(dest_path, FileAccess.WRITE)
						if out_file:
							out_file.store_buffer(file_data)
							out_file.close()
			entry = temp_dir.get_next()
		temp_dir.list_dir_end()

	# 清理临时文件
	_delete_directory_recursive(temp_extract_dir)

	_load_bundles()

	print("[_api_import_bundle_local] Bundle imported: ", bundle_name, " (", bundle_id, ")")
	return {"code": 200, "data": {
		"success": true,
		"message": "Bundle imported",
		"bundle_id": bundle_id,
		"bundle_name": bundle_name
	}}


func _api_save_bundle(params: Dictionary) -> Dictionary:
	var bundle_id: String = params.get("bundle_id", "")
	var data: Dictionary = params.get("data", {})

	if bundle_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Bundle ID is required"}}

	if data.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Bundle data is required"}}

	# Ensure bundle_id in data matches path
	data["id"] = bundle_id

	# Save to JSON file
	if not _save_bundle_json(bundle_id, data):
		return {"code": 500, "data": {"success": false, "message": "Failed to save bundle JSON"}}

	# Update in-memory cache
	bundle_data[bundle_id] = data

	print("[API] Bundle saved: ", bundle_id)
	return {"code": 200, "data": {"success": true, "message": "Bundle saved", "bundle_id": bundle_id}}


func _api_update_bundle_presets(params: Dictionary) -> Dictionary:
	var bundle_id: String = params.get("bundle_id", "")
	var presets: Dictionary = params.get("presets", {})

	if bundle_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Bundle ID is required"}}

	# Check if bundle exists
	if not bundle_data.has(bundle_id):
		return {"code": 404, "data": {"success": false, "message": "Bundle not found"}}

	# Get existing data
	var data = bundle_data[bundle_id]

	# Update presets
	data["presets"] = presets

	# Save to JSON file
	if not _save_bundle_json(bundle_id, data):
		return {"code": 500, "data": {"success": false, "message": "Failed to save bundle presets"}}

	# Update in-memory cache
	bundle_data[bundle_id] = data

	print("[API] Bundle presets updated: ", bundle_id)
	return {"code": 200, "data": {"success": true, "message": "Presets updated", "bundle_id": bundle_id}}


func _api_export_bundle(params: Dictionary) -> Dictionary:
	var bundle_id: String = params.get("bundle_id", "")

	if bundle_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Bundle ID is required"}}

	# Check if bundle exists
	if not bundle_data.has(bundle_id):
		return {"code": 404, "data": {"success": false, "message": "Bundle not found"}}

	var data = bundle_data[bundle_id]
	var bundle_name: String = data.get("name", bundle_id)
	var bundle_author: String = data.get("author", "")
	var bundle_version: String = data.get("version", "v1.0.0")
	var bundle_desc: String = data.get("description", "")

	# Create exports directory
	var exports_dir = get_base_path().path_join("exports")
	DirAccess.make_dir_recursive_absolute(exports_dir)

	var zip_name = bundle_name.replace(" ", "_").replace("/", "_").replace("\\", "_") + ".zip"
	var zip_path = exports_dir.path_join(zip_name)

	# Check if file already exists and generate unique name
	var counter = 1
	var base_zip_path = zip_path
	while FileAccess.file_exists(zip_path):
		var name_without_ext = base_zip_path.get_basename()
		zip_path = name_without_ext + "_" + str(counter) + ".zip"
		counter += 1

	# Create temp bundle directory
	var package_dir = _get_newpackage_dir()
	if package_dir.is_empty():
		return {"code": 500, "data": {"success": false, "message": "Package directory not available"}}

	var temp_bundle_dir = package_dir.path_join("export_" + bundle_id)
	DirAccess.make_dir_recursive_absolute(temp_bundle_dir)

	# Copy bundle.json
	_save_bundle_json(bundle_id, data)

	# Copy mod files for this bundle
	var mod_names = data.get("mod_names", [])
	var copied_mods = []
	var mods_dir = temp_mods_path

	if DirAccess.dir_exists_absolute(mods_dir):
		for mod_id in mod_names:
			var mod_source_dir = mods_dir.path_join(mod_id)
			if DirAccess.dir_exists_absolute(mod_source_dir):
				var mod_target_dir = temp_bundle_dir.path_join(mod_id)
				DirAccess.make_dir_recursive_absolute(mod_target_dir)
				FileUtils.copy_directory(mod_source_dir, mod_target_dir)
				copied_mods.append(mod_id)

	# Copy preview if exists
	var preview_source = package_dir.path_join(bundle_id).path_join("preview.png")
	if FileAccess.file_exists(preview_source):
		FileUtils.copy_file(preview_source, temp_bundle_dir.path_join("preview.png"))

	# Copy mod configs
	_copy_config_to_bundle(temp_bundle_dir)

	# Create ZIP
	if not _create_zip_from_dir(temp_bundle_dir, zip_path):
		_delete_directory_recursive(temp_bundle_dir)
		return {"code": 500, "data": {"success": false, "message": "Failed to create ZIP file"}}

	# Cleanup temp directory
	_delete_directory_recursive(temp_bundle_dir)

	print("[API] Bundle exported: ", bundle_id, " to ", zip_path)
	return {
		"code": 200,
		"data": {
			"success": true,
			"message": "Bundle exported",
			"bundle_id": bundle_id,
			"export_path": zip_path,
			"file_name": zip_path.get_file(),
			"copied_mods": copied_mods.size()
		}
	}


func _api_export_current_bundle(params: Dictionary) -> Dictionary:
	var name: String = params.get("name", "").strip_edges()
	var author: String = params.get("author", "").strip_edges()
	var version: String = params.get("version", "v1.0.0").strip_edges()
	var description: String = params.get("description", "")
	var export_path: String = params.get("export_path", "").strip_edges()  # 自定义导出路径

	if name.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Bundle name is required"}}

	# 检查是否有预设（使用 tag_data 而不是 enabled_mods）
	if tag_data.is_empty():
		return {"code": 400, "data": {"success": false, "message": "No presets to export"}}

	var bundle_id = "bundle_" + str(Time.get_unix_time_from_system())
	var package_dir = _get_newpackage_dir()
	if package_dir.is_empty():
		return {"code": 500, "data": {"success": false, "message": "Package directory not available"}}

	# 确定ZIP文件路径（使用自定义路径或默认 exports 目录）
	var zip_name = name.replace(" ", "_").replace("/", "_").replace("\\", "_") + ".zip"
	var zip_path: String
	if not export_path.is_empty():
		# 使用用户指定的路径
		zip_path = export_path
		# 确保路径以.zip结尾
		if not zip_path.to_lower().ends_with(".zip"):
			zip_path = zip_path.path_join(zip_name)
	else:
		# 默认导出到 exports 目录
		var exports_dir = get_base_path().path_join("exports")
		DirAccess.make_dir_recursive_absolute(exports_dir)
		zip_path = exports_dir.path_join(zip_name)

	# Create temp bundle directory
	var bundle_dir = package_dir.path_join(bundle_id)
	DirAccess.make_dir_recursive_absolute(bundle_dir)

	# 构建有效模组 ID 集合（从 mods 数组中）
	var valid_mod_ids: Dictionary = {}
	for mod in mods:
		if mod.has("id"):
			valid_mod_ids[mod["id"]] = true

	# 收集预设中所有涉及的模组ID（与原版 _export_bundle_to_zip 逻辑一致）
	# 只保留实际存在于 mods 数组中的模组，过滤幽灵模组
	var preset_mod_ids: Array = []
	for preset_name in tag_data.keys():
		for mod_id in tag_data[preset_name]:
			# 只添加实际存在的模组，过滤幽灵模组
			if valid_mod_ids.has(mod_id) and not mod_id in preset_mod_ids:
				preset_mod_ids.append(mod_id)
	print("[_api_export_current_bundle] preset_mod_ids (filtered): ", preset_mod_ids, ", valid mods count: ", valid_mod_ids.size())

	# 创建bundle.json数据结构（与原版一致）
	var data = {
		"id": bundle_id,
		"name": name,
		"author": author,
		"version": version,
		"description": description,
		"mods": [],
		"presets": tag_data.duplicate(true),
		"created_at": Time.get_datetime_string_from_system(),
		"updated_at": Time.get_datetime_string_from_system()
	}

	# 遍历temp_mods目录，复制预设中涉及的模组（与原版逻辑一致）
	var copied_mods = []
	var mods_dir = temp_mods_path

	if DirAccess.dir_exists_absolute(mods_dir):
		var dir = DirAccess.open(mods_dir)
		if dir:
			dir.list_dir_begin()
			var item_dir = dir.get_next()
			while item_dir != "":
				if item_dir != "." and item_dir != ".." and not item_dir.begins_with("_"):
					var mod_path = mods_dir.path_join(item_dir)
					if DirAccess.dir_exists_absolute(mod_path):
						var mod_id = item_dir

						# 跳过 .zip 结尾的无效模组ID
						if ".zip" in mod_id:
							item_dir = dir.get_next()
							continue

						# 只添加在预设中出现的模组
						if mod_id in preset_mod_ids:
							var mod_info = {
								"id": mod_id,
								"tags": []
							}
							data["mods"].append(mod_info)

							# 复制预设中涉及的模组文件
							var target_mod_dir = bundle_dir.path_join("mods").path_join(mod_id)
							DirAccess.make_dir_recursive_absolute(target_mod_dir)
							FileUtils.copy_directory(mod_path, target_mod_dir)
							copied_mods.append(mod_id)
							print("[_api_export_current_bundle] Copied mod: ", mod_id)
				item_dir = dir.get_next()
			dir.list_dir_end()

	# Copy preview if exists
	var preview_source = get_base_path().path_join("bundle_preview.png")
	if FileAccess.file_exists(preview_source):
		FileUtils.copy_file(preview_source, bundle_dir.path_join("preview.png"))

	# Copy mod configs
	_copy_config_to_bundle(bundle_dir)

	# Save bundle.json
	_save_bundle_json(bundle_id, data)

	# 添加 mod_names 字段到 bundle.json（用于兼容性）
	var mod_names: Array = []
	for mod_info in data["mods"]:
		mod_names.append(mod_info["id"])
	data["mod_names"] = mod_names

	# 重新保存更新后的 bundle.json
	_save_bundle_json(bundle_id, data)

	# Create ZIP
	if not _create_zip_from_dir(bundle_dir, zip_path):
		_delete_directory_recursive(bundle_dir)
		return {"code": 500, "data": {"success": false, "message": "Failed to create ZIP file"}}

	# Cleanup temp directory
	_delete_directory_recursive(bundle_dir)

	print("[API] Current bundle exported: ", bundle_id, " to ", zip_path)
	return {
		"code": 200,
		"data": {
			"success": true,
			"message": "Bundle exported",
			"bundle_id": bundle_id,
			"export_path": zip_path,
			"file_name": zip_path.get_file(),
			"copied_mods": copied_mods.size()
		}
	}


# 应用整合包预设 - 实际执行模组文件夹操作
func _api_apply_bundle_preset(params: Dictionary) -> Dictionary:
	var bundle_id: String = params.get("bundle_id", "")
	var preset_name: String = params.get("preset_name", "")

	print("[_api_apply_bundle_preset] START - bundle_id=", bundle_id, ", preset_name=", preset_name)

	if bundle_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Bundle ID is required"}}
	if preset_name.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Preset name is required"}}

	var data = bundle_data.get(bundle_id, {})
	if data.is_empty():
		print("[_api_apply_bundle_preset] Bundle not found: ", bundle_id)
		return {"code": 404, "data": {"success": false, "message": "Bundle not found"}}

	var presets = data.get("presets", {})
	if not presets.has(preset_name):
		print("[_api_apply_bundle_preset] Preset not found: ", preset_name)
		return {"code": 404, "data": {"success": false, "message": "Preset not found: " + preset_name}}

	var preset_mods = presets[preset_name]
	print("[_api_apply_bundle_preset] Preset mods count: ", preset_mods.size())

	# 确保游戏路径已设置
	if game_path.is_empty():
		game_path = config.get_value("paths", "game_path", "")
	if game_path.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Game path not set"}}

	var package_dir = _get_newpackage_dir()
	if package_dir.is_empty():
		return {"code": 500, "data": {"success": false, "message": "Package directory not available"}}

	var bundle_mods_dir = package_dir.path_join(bundle_id).path_join("mods")
	var game_mods_dir = game_path.path_join("mods")

	# 清空游戏 mods 文件夹 - 完全删除后重新创建
	if DirAccess.dir_exists_absolute(game_mods_dir):
		print("[_api_apply_bundle_preset] Removing existing game mods dir: ", game_mods_dir)
		_delete_directory_recursive(game_mods_dir)

	DirAccess.make_dir_recursive_absolute(game_mods_dir)
	print("[_api_apply_bundle_preset] Created fresh game mods dir: ", game_mods_dir)

	# 从整合包复制模组到游戏目录
	var copied_mods = []
	var failed_mods = []

	for mod_id in preset_mods:
		var source_mod_dir = bundle_mods_dir.path_join(mod_id)
		var target_mod_dir = game_mods_dir.path_join(mod_id)

		if DirAccess.dir_exists_absolute(source_mod_dir):
			DirAccess.make_dir_recursive_absolute(target_mod_dir)
			FileUtils.copy_directory(source_mod_dir, target_mod_dir)
			copied_mods.append(mod_id)
			print("[_api_apply_bundle_preset] Copied mod: ", mod_id)
		else:
			failed_mods.append(mod_id)
			print("[_api_apply_bundle_preset] Mod not found in bundle: ", mod_id)

	# 更新 enabled_mods
	enabled_mods.clear()
	for mod_id in copied_mods:
		enabled_mods[mod_id] = true

	# 保存启用的模组配置
	_save_enabled_mods()

	# 更新当前标签
	current_tag = preset_name
	tag_data = presets.duplicate(true)
	_save_tag_data()

	# 更新整合包激活状态
	active_bundle = bundle_id
	config.set_value("bundles", "active_bundle", bundle_id)

	# 保存选中的预设
	selected_bundle_preset = preset_name
	var bundle_selected_presets = config.get_value("bundles", "bundle_selected_presets", {})
	bundle_selected_presets[bundle_id] = preset_name
	config.set_value("bundles", "bundle_selected_presets", bundle_selected_presets)
	config.save(config_path)

	print("[API] Bundle preset applied: ", bundle_id, "/", preset_name, " copied:", copied_mods.size())
	return {
		"code": 200,
		"data": {
			"success": true,
			"message": "Preset applied: " + preset_name,
			"bundle_id": bundle_id,
			"preset_name": preset_name,
			"copied_mods": copied_mods,
			"failed_mods": failed_mods,
			"enabled_count": copied_mods.size()
		}
	}


# ── 设置 API ───────────────────────────────────────────────────

func _api_get_settings(_params: Dictionary) -> Dictionary:
	var settings = {
		"game_path": config.get_value("paths", "game_path", ""),
		"save_path": config.get_value("paths", "save_path", ""),
		"gse_cloud_path": config.get_value("paths", "gse_cloud_path", ""),
		"steam_cloud_path": config.get_value("paths", "steam_cloud_path", ""),
		"language": config.get_value("settings", "language", "zh_CN"),
		"dpi_scale": config.get_value("settings", "dpi_scale", 1.0),
		"auto_backup": config.get_value("settings", "auto_backup", true),
		"auto_backup_on_startup": config.get_value("settings", "auto_backup_on_startup", true),
		"auto_backup_max_count": config.get_value("settings", "auto_backup_max_count", 5),
		"launch_via_steam": config.get_value("settings", "launch_via_steam", true),
		"minimize_to_tray": config.get_value("settings", "minimize_to_tray", true),
		"server_port": config.get_value("server", "port", 8765),
		"nexus_api_key": config.get_value("nexus", "api_key", ""),
	}
	return {"code": 200, "data": {"settings": settings}}


func _api_set_settings(params: Dictionary) -> Dictionary:
	# 更新路径
	if params.has("game_path"):
		game_path = params["game_path"]
		config.set_value("paths", "game_path", game_path)
	if params.has("save_path"):
		save_path = params["save_path"]
		config.set_value("paths", "save_path", save_path)
	if params.has("gse_cloud_path"):
		gse_cloud_path = params["gse_cloud_path"]
		config.set_value("paths", "gse_cloud_path", gse_cloud_path)
	if params.has("steam_cloud_path"):
		steam_cloud_path = params["steam_cloud_path"]
		config.set_value("paths", "steam_cloud_path", steam_cloud_path)
	# 更新设置
	if params.has("language"):
		config.set_value("settings", "language", params["language"])
	if params.has("dpi_scale"):
		config.set_value("settings", "dpi_scale", params["dpi_scale"])
	if params.has("auto_backup"):
		config.set_value("settings", "auto_backup", params["auto_backup"])
	if params.has("launch_via_steam"):
		config.set_value("settings", "launch_via_steam", params["launch_via_steam"])
	if params.has("minimize_to_tray"):
		config.set_value("settings", "minimize_to_tray", params["minimize_to_tray"])
	if params.has("nexus_api_key"):
		config.set_value("nexus", "api_key", params["nexus_api_key"])
		if nexus_api:
			nexus_api.set_api_key(params["nexus_api_key"])

	config.save(config_path)
	return {"code": 200, "data": {"success": true, "message": "Settings saved"}}


func _api_detect_game_path(_params: Dictionary) -> Dictionary:
	var detected = _detect_game_path()
	return {"code": 200, "data": {"path": detected}}


func _api_detect_save_path(_params: Dictionary) -> Dictionary:
	var detected = _detect_save_path()
	return {"code": 200, "data": {"path": detected}}


# ── 下载 API ───────────────────────────────────────────────────

func _api_get_downloads(_params: Dictionary) -> Dictionary:
	var active: Array = []
	for dl_id in download_tasks:
		var task = download_tasks[dl_id]
		active.append({
			"id": dl_id,
			"mod_name": task.get("mod_name", ""),
			"progress": task.get("progress", 0),
			"speed": task.get("speed", ""),
			"status": task.get("status", ""),
			"total_size": task.get("total_size", 0),
			"downloaded": task.get("downloaded", 0),
		})

	return {"code": 200, "data": {
		"active": active,
		"history": _format_download_history_for_api(download_history)
	}}


func _format_download_history_for_api(history: Array) -> Array:
	var result: Array = []
	for item in history:
		var end_time_val = item.get("end_time", 0)
		var start_time_val = item.get("start_time", 0)
		var is_end_time_valid = end_time_val != null and end_time_val != 0
		var is_start_time_valid = start_time_val != null and start_time_val != 0

		var date_val = int(Time.get_unix_time_from_system())
		if is_end_time_valid:
			date_val = int(end_time_val)

		var duration_val = 0
		if is_end_time_valid and is_start_time_valid:
			duration_val = int((int(end_time_val) - int(start_time_val)) * 1000)

		var status_str = "success"
		var item_status = item.get("status", "")
		if item_status == "completed":
			status_str = "completed"
		elif item_status == "failed":
			status_str = "failed"

		result.append({
			"id": item.get("download_id", item.get("id", "")),
			"mod_name": item.get("mod_name", ""),
			"status": status_str,
			"date": date_val,
			"size": item.get("downloaded_size", item.get("total_size", 0)),
			"duration": duration_val,
			"source": item.get("download_source", "nexus"),
		})
	return result


func _api_pause_download(params: Dictionary) -> Dictionary:
	var download_id: String = params.get("download_id", "")
	if download_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing download_id"}}

	if not download_tasks.has(download_id):
		return {"code": 404, "data": {"success": false, "message": "Download not found"}}

	_pause_download(download_id)
	return {"code": 200, "data": {"success": true, "message": "Download paused"}}


func _api_resume_download(params: Dictionary) -> Dictionary:
	var download_id: String = params.get("download_id", "")
	if download_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing download_id"}}

	if not download_tasks.has(download_id):
		return {"code": 404, "data": {"success": false, "message": "Download not found"}}

	_resume_download(download_id)
	return {"code": 200, "data": {"success": true, "message": "Download resumed"}}


func _api_cancel_download(params: Dictionary) -> Dictionary:
	var download_id: String = params.get("download_id", "")
	if download_id.is_empty():
		return {"code": 400, "data": {"success": false, "message": "Missing download_id"}}

	if not download_tasks.has(download_id):
		return {"code": 404, "data": {"success": false, "message": "Download not found"}}

	_on_download_cancel_pressed(download_id)
	return {"code": 200, "data": {"success": true, "message": "Download cancelled"}}


# ── 启动游戏 API ───────────────────────────────────────────────

func _api_launch_game(params: Dictionary) -> Dictionary:
	var mode: String = params.get("mode", "modded")

	# 通过 Steam 协议启动
	var steam_url = "steam://launch/%s/dialog" % STEAM_APP_ID
	var err = OS.shell_open(steam_url)
	if err == OK:
		return {"code": 200, "data": {"success": true, "message": "Game launch initiated (%s)" % mode}}
	return {"code": 500, "data": {"success": false, "message": "Failed to launch game"}}


# ── 更新检查 API ───────────────────────────────────────────────

func _api_check_update(_params: Dictionary) -> Dictionary:
	print("[_api_check_update] called")
	if update_checker:
		var latest_version = _read_version_from_file()
		update_checker.set_current_version(latest_version)

		# 用于接收异步结果的临时变量
		var async_result: Dictionary = {}
		var async_received = false

		# 设置一次性回调接收结果
		var orig_callback = update_checker._update_checked_callback
		var temp_callback = func(result: Dictionary) -> void:
			async_result = result
			async_received = true

		update_checker._update_checked_callback = Callable(temp_callback)

		# 触发检查（异步）
		update_checker.check_for_updates(false)

		# 等待结果，最多 15 秒（用 OS.delay_usec 实现精确等待）
		var wait_ms = 0
		while not async_received and wait_ms < 15000:
			OS.delay_usec(100000)  # 100ms
			wait_ms += 100

		# 恢复原始回调
		update_checker._update_checked_callback = orig_callback

		# 构建响应
		if async_received and async_result.get("success", false):
			var has_update = async_result.get("has_update", false)
			var data = async_result.get("data", {})
			return {
				"code": 200,
				"data": {
					"has_update": has_update,
					"current_version": latest_version,
					"new_version": data.get("version", "") if data else "",
					"changelog": data.get("changelog", "") if data else "",
					"download_url": data.get("download_url", "") if data else ""
				}
			}
		else:
			var err_msg = async_result.get("error", "") if async_received else "检查超时"
			return {
				"code": 200,
				"data": {
					"has_update": false,
					"error": err_msg
				}
			}
	return {"code": 503, "data": {"error": "Update checker not available"}}


# ── 标签数据 API ───────────────────────────────────────────────

func _api_save_tag_data(params: Dictionary) -> Dictionary:
	var new_tag_data: Dictionary = params.get("tag_data", {})
	var new_current_tag: String = params.get("current_tag", "")

	if new_tag_data.is_empty():
		return {"code": 400, "data": {"success": false, "message": "tag_data is required"}}

	# 更新内存中的数据
	tag_data = new_tag_data
	if not new_current_tag.is_empty():
		current_tag = new_current_tag

	# 【关键】只保存 tag_data 到 config，不要修改 enabled_mods
	# enabled_mods 代表当前实际启用的模组（从游戏 mods 目录扫描）
	# 不应该被 tag_data 覆盖，否则会导致重启后丢失实际启用状态
	# tag_data 是标签预设，enabled_mods 是实际状态，这是两个不同的概念

	# 保存到 config 文件（持久化）
	_save_tag_data()

	print("[_api_save_tag_data] Saved tag_data: ", tag_data.keys(), ", current_tag: ", current_tag)
	return {"code": 200, "data": {"success": true, "message": "Tag data saved"}}


# ── 收纳盒子与顺序 API ─────────────────────────────────────────

func _api_save_mod_organization(params: Dictionary) -> Dictionary:
	var boxes: Array = params.get("boxes", [])
	var item_order: Array = params.get("item_order", [])
	var enable_mod_drag: bool = params.get("enable_mod_drag", false)
	var enable_override_order: bool = params.get("enable_override_order", false)

	mod_boxes = boxes
	mod_order_override = item_order
	enable_mod_drag = enable_mod_drag
	enable_override_order = enable_override_order

	_save_mod_organization_data()

	print("[_api_save_mod_organization] Saved boxes: ", mod_boxes.size(), ", item_order: ", mod_order_override.size())
	return {"code": 200, "data": {"success": true, "message": "Mod organization saved"}}


func _api_get_mod_organization(_params: Dictionary) -> Dictionary:
	return {"code": 200, "data": {
		"boxes": mod_boxes,
		"item_order": mod_order_override,
		"enable_mod_drag": enable_mod_drag,
		"enable_override_order": enable_override_order
	}}


# 递归复制目录
func _copy_directory_recursive(src_path: String, dest_path: String) -> bool:
	var src_dir = DirAccess.open(src_path)
	if src_dir == null:
		return false

	# 确保目标目录存在
	DirAccess.make_dir_recursive_absolute(dest_path)

	# 复制所有文件和子目录
	src_dir.list_dir_begin()
	var item = src_dir.get_next()
	while item != "":
		var item_src_path = src_path.path_join(item)
		var item_dest_path = dest_path.path_join(item)

		if src_dir.current_is_dir():
			# 递归复制子目录
			if not _copy_directory_recursive(item_src_path, item_dest_path):
				return false
		else:
			# 复制文件
			var file_data = FileAccess.get_file_as_bytes(item_src_path)
			if file_data:
				var out_file = FileAccess.open(item_dest_path, FileAccess.WRITE)
				if out_file:
					out_file.store_buffer(file_data)
					out_file.close()
				else:
					return false
			else:
				return false
		item = src_dir.get_next()
	src_dir.list_dir_end()

	return true
