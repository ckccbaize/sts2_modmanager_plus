# 联机补丁功能改进实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现联机补丁功能改进：路径可自定义、注入时原文件保留为.bak、关闭游戏后自动恢复、启动和刷新时检测修复.bak文件

**Architecture:** 修改现有的联机补丁逻辑，从备份目录方式改为原地.bak备份方式；添加路径配置和.bak检测修复功能

**Tech Stack:** Godot 4.5.1 / GDScript

---

## 文件修改概览

| 文件 | 修改内容 |
|------|----------|
| `modmanager.gd` | 核心逻辑修改：添加配置、UI、注入/恢复逻辑、检测修复 |
| `locales/zh_CN.json` | 添加新字符串 |
| `locales/en_US.json` | 添加新字符串 |

---

## Task 1: 添加配置变量和本地化字符串

**Files:**
- Modify: `modmanager.gd` - 添加 fix_steam_path 变量
- Modify: `locales/zh_CN.json` - 添加新字符串
- Modify: `locales/en_US.json` - 添加新字符串

- [ ] **Step 1: 在 modmanager.gd 中添加 fix_steam_path 变量**

在 `var game_path: String = ""` 附近（约543行）添加：
```gdscript
var fix_steam_path: String = ""  # 联机补丁路径
```

- [ ] **Step 2: 添加本地化字符串**

在 `locales/zh_CN.json` 中添加：
```json
"fix_steam_path": "联机补丁路径",
"fix_steam_path_placeholder": "选择联机补丁目录",
"fix_steam_path_not_set": "请先设置联机补丁路径",
"fix_steam_path_not_found": "联机补丁目录不存在",
"fix_steam_injected": "联机补丁已注入",
"fix_steam_restored": "联机补丁已恢复",
"bak_files_repaired": "已修复 {count} 个联机补丁文件",
"bak_files_checking": "正在检测联机补丁状态...",
"no_bak_files_found": "未发现需要修复的联机补丁文件"
```

在 `locales/en_US.json` 中添加对应英文：
```json
"fix_steam_path": "Online Patch Path",
"fix_steam_path_placeholder": "Select online patch directory",
"fix_steam_path_not_set": "Please set online patch path first",
"fix_steam_path_not_found": "Online patch directory not found",
"fix_steam_injected": "Online patch injected",
"fix_steam_restored": "Online patch restored",
"bak_files_repaired": "Repaired {count} online patch files",
"bak_files_checking": "Checking online patch status...",
"no_bak_files_found": "No online patch files to repair"
```

- [ ] **Step 3: 提交**

---

## Task 2: 添加路径配置 UI

**Files:**
- Modify: `modmanager.gd` - 在设置界面添加联机补丁路径配置

- [ ] **Step 1: 找到联机补丁复选框创建位置**

在 `modmanager.gd` 中约5214行，找到 `enable_fix_steam_check` 创建位置

- [ ] **Step 2: 在联机补丁复选框之前添加路径配置行**

在 `enable_fix_steam_check` 创建之前（约5214行），添加：
```gdscript
# 创建联机补丁路径配置行
var fix_steam_path_row = HBoxContainer.new()
fix_steam_path_row.name = "FixSteamPathRow"
launch_section.add_child(fix_steam_path_row)

var fix_steam_path_label = Label.new()
fix_steam_path_label.name = "FixSteamPathLabel"
fix_steam_path_label.text = translate("fix_steam_path")
fix_steam_path_label.custom_minimum_size.x = 120
fix_steam_path_row.add_child(fix_steam_path_label)

var fix_steam_path_edit = LineEdit.new()
fix_steam_path_edit.name = "FixSteamPathEdit"
fix_steam_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
fix_steam_path_edit.placeholder_text = translate("fix_steam_path_placeholder")
fix_steam_path_edit.text = config.get_value("paths", "fix_steam_path", "")
fix_steam_path_edit.tooltip_text = translate("fix_steam_path_desc")
fix_steam_path_row.add_child(fix_steam_path_edit)

var fix_steam_path_browse_btn = Button.new()
fix_steam_path_browse_btn.name = "FixSteamPathBrowseBtn"
fix_steam_path_browse_btn.text = translate("browse")
fix_steam_path_browse_btn.pressed.connect(_on_fix_steam_path_browse)
fix_steam_path_row.add_child(fix_steam_path_browse_btn)

var fix_steam_path_detect_btn = Button.new()
fix_steam_path_detect_btn.name = "FixSteamPathDetectBtn"
fix_steam_path_detect_btn.text = translate("auto_detect")
fix_steam_path_detect_btn.pressed.connect(_on_fix_steam_path_detect)
fix_steam_path_row.add_child(fix_steam_path_detect_btn)
```

- [ ] **Step 3: 获取 fix_steam_path_edit 引用**

在变量声明区域（约273行），添加：
```gdscript
var fix_steam_path_edit: LineEdit
```

- [ ] **Step 4: 创建浏览和检测回调函数**

在 `_on_game_path_browse` 函数附近，添加：
```gdscript
# 联机补丁路径浏览
func _on_fix_steam_path_browse() -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.dir_access_mode = DirAccess.DIR_ACCESS_RECURSE
	dialog.initial_position = Window.POSITION_CENTER
	dialog.title = translate("select_fix_steam_path")
	dialog.connect("dir_selected", _on_fix_steam_dir_selected)
	get_tree().root.add_child(dialog)
	dialog.popup()

func _on_fix_steam_dir_selected(dir_path: String) -> void:
	fix_steam_path = dir_path
	if fix_steam_path_edit:
		fix_steam_path_edit.text = dir_path
	# 更新复选框状态
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
			enable_fix_steam_check.tooltip_text = translate("fix_steam_path_not_set")
		else:
			enable_fix_steam_check.disabled = false
			enable_fix_steam_check.tooltip_text = translate("enable_fix_steam_desc")
```

- [ ] **Step 5: 在 _init_settings_ui_if_needed 中获取引用并更新状态**

在获取 `enable_fix_steam_check` 引用后（约5223行），添加：
```gdscript
# 获取联机补丁路径编辑框
fix_steam_path_edit = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/LaunchSection/FixSteamPathRow/FixSteamPathEdit")
if fix_steam_path_edit:
	fix_steam_path_edit.text_changed.connect(_on_fix_steam_path_changed)

# 加载配置
fix_steam_path = config.get_value("paths", "fix_steam_path", "")

# 更新复选框状态
_update_fix_steam_checkbox_state()
```

- [ ] **Step 6: 添加路径变更回调**

```gdscript
func _on_fix_steam_path_changed(new_text: String) -> void:
	fix_steam_path = new_text
	_update_fix_steam_checkbox_state()
```

- [ ] **Step 7: 提交**

---

## Task 3: 修改注入逻辑使用 .bak 方式

**Files:**
- Modify: `modmanager.gd` - 修改 _apply_fix_steam_patch 函数

- [ ] **Step 1: 修改 _apply_fix_steam_patch 函数**

找到现有函数（约4675行），替换为：
```gdscript
# 应用联机补丁文件
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

	# 遍历 fix_steam 目录下的所有文件
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
			print("[_apply_fix_steam_patch]   source: ", source_path)
			print("[_apply_fix_steam_patch]   dest: ", dest_path)

			# 检查目标文件是否存在
			var has_dest = FileAccess.file_exists(dest_path) or DirAccess.dir_exists_absolute(dest_path)
			print("[_apply_fix_steam_patch]   has_dest: ", has_dest)

			if has_dest:
				var bak_path = dest_path + ".bak"
				# 如果 .bak 文件已存在，先删除
				if FileAccess.file_exists(bak_path):
					DirAccess.remove_absolute(bak_path)
				# 将原文件重命名为 .bak
				if DirAccess.dir_exists_absolute(dest_path):
					# 目录需要特殊处理 - 先复制再删除
					DirAccess.rename_absolute(dest_path, bak_path)
					print("[_apply_fix_steam_patch]   Renamed directory to .bak: ", file_name)
				else:
					DirAccess.rename_absolute(dest_path, bak_path)
					print("[_apply_fix_steam_patch]   Renamed file to .bak: ", file_name)

			# 特殊处理 data_sts2_windows_x86_64 目录：只复制其中的 steam_api64.dll
			if file_name == "data_sts2_windows_x86_64":
				var source_steam_api = source_path.path_join("steam_api64.dll")
				var dest_steam_api = dest_path.path_join("steam_api64.dll")
				print("[_apply_fix_steam_patch]   Special handling: copying only steam_api64.dll")
				_file_copy_safe(source_steam_api, dest_steam_api)
				copied_files.append(file_name)
				file_name = dir.get_next()
				continue

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
	
	show_notification(translate("fix_steam_injected"), true)
	return true
```

- [ ] **Step 2: 提交**

---

## Task 4: 修改恢复逻辑使用 .bak 方式

**Files:**
- Modify: `modmanager.gd` - 修改 _restore_fix_steam_backup 函数

- [ ] **Step 1: 修改 _restore_fix_steam_backup 函数**

找到现有函数（约4765行），替换为：
```gdscript
# 恢复联机补丁备份
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
	for file_name in files_to_restore:
		var dest_path = game_path.path_join(file_name)
		var bak_path = dest_path + ".bak"

		# 特殊处理 data_sts2_windows_x86_64 目录
		if file_name == "data_sts2_windows_x86_64":
			var dest_steam_api = dest_path.path_join("steam_api64.dll")
			var bak_steam_api = bak_path.path_join("steam_api64.dll")
			# 删除注入的补丁
			if FileAccess.file_exists(dest_steam_api):
				DirAccess.remove_absolute(dest_steam_api)
				print("[_restore_fix_steam_backup] Deleted injected steam_api64.dll")
			# 恢复 .bak 文件
			if FileAccess.file_exists(bak_steam_api):
				DirAccess.rename_absolute(bak_steam_api, dest_steam_api)
				print("[_restore_fix_steam_backup] Restored steam_api64.dll from .bak")
			continue

		# 删除注入的补丁文件/目录
		if DirAccess.dir_exists_absolute(dest_path):
			_delete_directory_recursive(dest_path)
			print("[_restore_fix_steam_backup] Deleted injected directory: ", file_name)
		elif FileAccess.file_exists(dest_path):
			DirAccess.remove_absolute(dest_path)
			print("[_restore_fix_steam_backup] Deleted injected file: ", file_name)

		# 恢复 .bak 文件
		if FileAccess.file_exists(bak_path):
			DirAccess.rename_absolute(bak_path, dest_path)
			print("[_restore_fix_steam_backup] Restored from .bak: ", file_name)
		elif DirAccess.dir_exists_absolute(bak_path + ".bak"):
			# 处理目录情况
			var dir_bak_path = bak_path
			DirAccess.rename_absolute(dir_bak_path, dest_path)
			print("[_restore_fix_steam_backup] Restored directory from .bak: ", file_name)

	print("[_restore_fix_steam_backup] Backup restored successfully")
	
	show_notification(translate("fix_steam_restored"), true)
	return true
```

- [ ] **Step 2: 提交**

---

## Task 5: 添加 .bak 文件检测和修复功能

**Files:**
- Modify: `modmanager.gd` - 添加 _check_and_fix_bak_files 函数

- [ ] **Step 1: 添加 _check_and_fix_bak_files 函数**

在 `_restore_fix_steam_backup` 函数后（约4810行），添加：
```gdscript
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
		var original_path = bak_path.substr(0, bak_path.length() - 4)  # 去掉 .bak 后缀
		var file_name = bak_path.get_file()
		var original_file_name = file_name.substr(0, file_name.length() - 4)
		
		print("[_check_and_fix_bak_files] Processing: ", file_name)
		print("[_check_and_fix_bak_files]   original: ", original_path)

		# 检查原始文件是否存在（被补丁覆盖）
		var original_exists = FileAccess.file_exists(original_path) or DirAccess.dir_exists_absolute(original_path)
		
		if original_exists:
			# 删除被补丁覆盖的版本
			if DirAccess.dir_exists_absolute(original_path):
				_delete_directory_recursive(original_path)
				print("[_check_and_fix_bak_files]   Deleted overwritten directory")
			else:
				DirAccess.remove_absolute(original_path)
				print("[_check_and_fix_bak_files]   Deleted overwritten file")

		# 将 .bak 重命名为原始文件名
		var dir = bak_path.get_base_dir()
		var original_full_path = dir.path_join(original_file_name)
		DirAccess.rename_absolute(bak_path, original_full_path)
		print("[_check_and_fix_bak_files]   Restored .bak to original: ", original_file_name)
		
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
```

- [ ] **Step 2: 在 _ready 中添加检测调用**

在 `_ready()` 函数中，加载配置后（约800行），添加：
```gdscript
# 检测并修复 .bak 文件
var fixed_count = _check_and_fix_bak_files()
if fixed_count > 0:
	show_notification(translate("bak_files_repaired").format({"count": fixed_count}), true)
else:
	# 仅在非首次运行时显示"未发现问题"
	if not config.get_value("settings", "first_run", true):
		print("[_ready] No .bak files to repair")
```

- [ ] **Step 3: 在刷新按钮回调中添加检测调用**

找到刷新按钮相关代码，添加检测调用

- [ ] **Step 4: 提交**

---

## Task 6: 保存和加载 fix_steam_path 配置

**Files:**
- Modify: `modmanager.gd` - 修改配置保存和加载逻辑

- [ ] **Step 1: 在 _on_save_settings_pressed 中添加 fix_steam_path 保存**

在设置保存函数中，添加：
```gdscript
# 获取联机补丁路径
fix_steam_path = config.get_value("paths", "fix_steam_path", "")
if fix_steam_path_edit:
	fix_steam_path = fix_steam_path_edit.text
	config.set_value("paths", "fix_steam_path", fix_steam_path)
```

- [ ] **Step 2: 在 _finish_save_settings 中确保配置保存**

确认 `config.set_value("paths", "fix_steam_path", fix_steam_path)` 被调用

- [ ] **Step 3: 在 _on_settings_changed 中触发复选框状态更新**

当路径变更时调用 `_update_fix_steam_checkbox_state()`

- [ ] **Step 4: 提交**

---

## Task 7: 测试和验证

**Files:**
- 测试所有功能点

- [ ] **Step 1: 测试路径配置**
- 启动管理器，进入设置界面
- 确认联机补丁路径配置行存在
- 使用浏览按钮选择目录
- 使用自动检测按钮

- [ ] **Step 2: 测试启用逻辑**
- 未设置路径时，复选框应该禁用
- 设置路径后，复选框应该启用

- [ ] **Step 3: 测试注入流程**
- 设置联机补丁路径
- 启用联机补丁选项
- 点击联机启动
- 检查游戏目录中的文件是否被重命名为 .bak

- [ ] **Step 4: 测试恢复流程**
- 关闭游戏后
- 检查 .bak 文件是否被恢复

- [ ] **Step 5: 测试 .bak 检测修复**
- 手动创建一些 .bak 文件
- 重启管理器
- 检查是否自动修复

- [ ] **Step 6: 提交**
