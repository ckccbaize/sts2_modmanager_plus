extends RefCounted
class_name ModUtils

# 模组管理工具类

# 获取应用基础路径（兼容编辑器模式）
static func get_base_path() -> String:
	if OS.has_feature("editor"):
		var path = ProjectSettings.globalize_path("res://").replace("res://", "")
		if not path.ends_with("/"):
			path += "/"
		return path
	else:
		return OS.get_executable_path().get_base_dir() + "/"

# 验证模组文件
static func validate_mod(mod_path: String) -> bool:
	var dir = DirAccess.open(mod_path)
	if dir == null:
		return false
	
	# 检查是否有JSON文件
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var has_json = false
	while file_name != "":
		if file_name.ends_with(".json"):
			has_json = true
			break
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return has_json


# 获取模组信息
static func get_mod_info(mod_path: String) -> Dictionary:
	var info = {}
	var dir = DirAccess.open(mod_path)
	if dir == null:
		print("无法打开目录: ", mod_path)
		return info

	# 查找JSON文件（首先检查当前目录，然后检查子目录）
	var json_path = find_json_file(mod_path)

	if json_path.is_empty():
		print("未找到JSON文件 in: ", mod_path)
		return info

	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		print("无法打开JSON文件: ", json_path)
		return info

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		print("JSON解析失败: ", json_path)
		return info

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return info

	info = data.duplicate(true)

	# 处理id字段：可能是id或pck_name
	if not info.has("id") or str(info["id"]).is_empty():
		if info.has("pck_name") and typeof(info["pck_name"]) == TYPE_STRING and not str(info["pck_name"]).is_empty():
			info["id"] = info["pck_name"]
		else:
			info["id"] = mod_path.get_file()

	# 硛保name字段有值
	if not info.has("name") or str(info["name"]).is_empty():
		info["name"] = info["id"]

	# 记录version是否来自JSON的真实字段（而非默认值）
	if not info.has("version") or str(info["version"]).is_empty():
		info["_has_version"] = false
		info["version"] = ""
	else:
		info["_has_version"] = true

	# 确保affects_gameplay字段有值
	if not info.has("affects_gameplay"):
		info["affects_gameplay"] = false

	info["path"] = mod_path
	info["has_pck"] = false
	info["has_dll"] = false

	# 检查是否有PCK和DLL文件
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".pck"):
			info["has_pck"] = true
		elif file_name.ends_with(".dll"):
			info["has_dll"] = true
		file_name = dir.get_next()

	dir.list_dir_end()

	return info


# 递归查找JSON文件
static func find_json_file(directory: String) -> String:
	var dir = DirAccess.open(directory)
	if dir == null:
		return ""

	# 首先检查当前目录
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			return directory.path_join(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# 然后检查子目录
	dir.list_dir_begin()
	file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			var subdir_path = directory.path_join(file_name)
			var json_path = find_json_file(subdir_path)
			if not json_path.is_empty():
				return json_path
		file_name = dir.get_next()
	dir.list_dir_end()

	return ""


# 查找模组的 manifest JSON（含 id 字段的那个，不是 settings.json 等配置文件）
static func find_manifest_json(mod_dir: String) -> String:
	var dir = DirAccess.open(mod_dir)
	if dir == null:
		return ""

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var full_path = mod_dir.path_join(file_name)
			var file = FileAccess.open(full_path, FileAccess.READ)
			if file != null:
				var content = file.get_as_text()
				file.close()
				var json = JSON.new()
				if json.parse(content) == OK:
					var data = json.get_data()
					if typeof(data) == TYPE_DICTIONARY and data.has("id"):
						return full_path
		file_name = dir.get_next()
	dir.list_dir_end()

	return ""


# 查找目录下所有的JSON文件
static func find_all_json_files(directory: String) -> Array:
	var json_files = []
	var dir = DirAccess.open(directory)
	if dir == null:
		return json_files

	# 检查当前目录
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			json_files.append(directory.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	# 递归检查子目录
	dir.list_dir_begin()
	file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			var subdir_path = directory.path_join(file_name)
			var sub_json_files = find_all_json_files(subdir_path)
			json_files.append_array(sub_json_files)
		file_name = dir.get_next()
	dir.list_dir_end()

	return json_files


# 启用模组到游戏的mods文件夹
# game_path 为空时使用 exe 所在目录
static func enable_mod(mod_data: Dictionary, game_path: String) -> bool:
	var mod_path = mod_data.get("path", "")
	var mod_name = mod_data.get("id", "")
	if mod_path.is_empty() or mod_name.is_empty():
		return false

	# 确定目标目录：game_path/mods（game_path为空时使用exe目录）
	var target_mods_path: String
	if game_path.is_empty():
		target_mods_path = get_base_path() + "mods"
		print("[enable_mod] WARN: game_path not configured, using default mods folder")
	else:
		target_mods_path = game_path.path_join("mods")

	var target_path = target_mods_path.path_join(mod_name)

	# 如果目标已存在，先删旧版本再复制（确保最新内容生效）
	if DirAccess.dir_exists_absolute(target_path):
		delete_directory(target_path)

	# 创建mods目录
	var dir = DirAccess.open(target_mods_path)
	if dir == null:
		var result = DirAccess.make_dir_recursive_absolute(target_mods_path)
		if result != OK:
			return false
		dir = DirAccess.open(target_mods_path)

	# 复制模组
	print("=== enable_mod ===", mod_name, " from:", mod_path, " to:", target_path)
	var success = copy_directory(mod_path, target_path)
	if success:
		print("=== enable_mod success ===", mod_name)
		return true
	else:
		print("=== enable_mod failed ===", mod_name)
		return false


# 禁用模组从游戏的mods文件夹
# game_path 为空时使用 exe 所在目录
static func disable_mod(mod_data: Dictionary, game_path: String) -> bool:
	var mod_name = mod_data.get("id", "")
	if mod_name.is_empty():
		print("=== disable_mod: mod_name is empty ===")
		return false

	# 确定源目录：game_path/mods（game_path为空时使用exe目录）
	var source_mods_path: String
	if game_path.is_empty():
		source_mods_path = get_base_path() + "mods"
		print("[disable_mod] WARN: game_path not configured, using default mods folder")
	else:
		source_mods_path = game_path.path_join("mods")

	var mod_path = source_mods_path.path_join(mod_name)

	print("=== disable_mod ===", mod_name)
	print("mod_path:", mod_path)
	print("mod exists:", DirAccess.dir_exists_absolute(mod_path))

	# 检查模组是否存在
	if not DirAccess.dir_exists_absolute(mod_path):
		print("=== disable_mod: mod not in mods folder, treating as already disabled ===")
		return true  # 模组不在文件夹中，已处于禁用状态

	# 使用delete_directory递归删除整个模组文件夹（包括所有嵌套内容）
	var result = delete_directory(mod_path)
	if result:
		print("=== disable_mod success ===", mod_name)
	else:
		print("=== disable_mod failed ===", mod_name)

	return result


# 安装模组（解压到暂存目录）
# 支持单模组和多模组整合包
static func install_mod(zip_path: String, mod_name: String = "", download_source: String = "", required_fields: Array = []) -> Dictionary:
	print("=== install_mod 开始 ===")
	print("zip_path: ", zip_path)
	print("download_source: ", download_source)
	var result = {"success": false, "message": "", "mod_info": {}, "installed_count": 0, "installed_mods": [], "failed_mods": [], "download_source": download_source}

	# 检查ZIP文件是否存在
	if not FileAccess.file_exists(zip_path):
		result["message"] = "ZIP文件不存在: " + zip_path
		return result

	var temp_base = get_base_path() + "temp_mods"

	# 确保temp_mods目录存在
	if not DirAccess.dir_exists_absolute(temp_base):
		var mkdir_result = DirAccess.make_dir_recursive_absolute(temp_base)
		if mkdir_result != OK:
			result["message"] = "无法创建临时目录"
			return result

	# 首先解压到一个临时目录
	var temp_extract_path = temp_base.path_join("_temp_extract")
	if DirAccess.dir_exists_absolute(temp_extract_path):
		delete_directory(temp_extract_path)
	DirAccess.make_dir_recursive_absolute(temp_extract_path)

	# 检查ZIP文件是否存在
	print("=== 检查ZIP文件 ===")
	print("zip_path: ", zip_path)
	print("exists: ", FileAccess.file_exists(zip_path))

	# 使用绝对路径
	var abs_zip_path = zip_path
	var project_dir = ""

	if abs_zip_path.begins_with("res://"):
		# res:// 路径需要转换为项目目录的实际路径
		project_dir = ProjectSettings.globalize_path("res://")
		abs_zip_path = abs_zip_path.replace("res://", project_dir)

	# 统一用正斜杠，避免PowerShell转义问题
	abs_zip_path = abs_zip_path.replace("\\", "/")
	print("绝对路径: ", abs_zip_path)
	print("文件存在: ", FileAccess.file_exists(abs_zip_path))

	var abs_extract_path = temp_extract_path
	if abs_extract_path.begins_with("res://"):
		if project_dir.is_empty():
			project_dir = ProjectSettings.globalize_path("res://")
		abs_extract_path = abs_extract_path.replace("res://", project_dir)
	abs_extract_path = abs_extract_path.replace("\\", "/")
	print("解压路径: ", abs_extract_path)

	# 如果ZIP文件不存在，尝试多个可能的位置
	if not FileAccess.file_exists(abs_zip_path):
		# 可能的downloads目录列表
		var possible_dirs = []
		if not project_dir.is_empty():
			possible_dirs.append(project_dir + "downloads")
		possible_dirs.append(OS.get_executable_path().get_base_dir() + "/downloads")
		possible_dirs.append(OS.get_executable_path().get_base_dir() + "/Downloads")

		var zip_name = abs_zip_path.get_file()
		var found = false

		for downloads_dir in possible_dirs:
			if found:
				break
			print("检查目录: ", downloads_dir)
			if not DirAccess.dir_exists_absolute(downloads_dir):
				continue

			# 首先尝试精确匹配
			var alt_path = downloads_dir + "/" + zip_name
			if FileAccess.file_exists(alt_path):
				abs_zip_path = alt_path
				print("使用备选路径: ", abs_zip_path)
				found = true
				break

			# 尝试查找名字相似的zip文件
			var dd = DirAccess.open(downloads_dir)
			if dd:
				dd.list_dir_begin()
				var fname = dd.get_next()
				while fname != "":
					if fname.ends_with(".zip") and zip_name.get_basename() in fname:
						abs_zip_path = downloads_dir + "/" + fname
						print("使用近似匹配: ", abs_zip_path)
						found = true
						break
					fname = dd.get_next()
				dd.list_dir_end()

	# 检查文件类型（ZIP 或 RAR）
	var lower_path = abs_zip_path.to_lower()
	var extract_success = false  # 先声明变量

	if lower_path.ends_with(".rar"):
		print("[ModUtils] RAR file detected, trying to extract...")

		# 尝试用 7z 命令解压（如果安装了7zip）
		var seven_zip_paths = [
			"C:\\Program Files\\7-Zip\\7z.exe",
			"C:\\Program Files (x86)\\7-Zip\\7z.exe",
			OS.get_executable_path().get_base_dir().path_join("7z.exe")
		]

		var seven_zip_exe = ""
		for path in seven_zip_paths:
			if FileAccess.file_exists(path):
				seven_zip_exe = path
				break

		if seven_zip_exe.is_empty():
			# 没有7z，显示友好的错误消息
			result["message"] = "RAR格式: 请手动解压后拖入模组文件夹"
			print("[ModUtils] 7-Zip not found, RAR extraction not possible")
			delete_directory(temp_extract_path)
			return result

		# 使用7z解压
		print("[ModUtils] Using 7-Zip: ", seven_zip_exe)
		var ps_script = "& '%s' x -y -o'%s' '%s'" % [seven_zip_exe, abs_extract_path, abs_zip_path]
		var output = []
		var exit_code = OS.execute("powershell", ["-NoProfile", "-Command", ps_script], output, true)
		print("[ModUtils] 7z extraction exit code: ", exit_code)
		print("[ModUtils] 7z extraction output: ", output)

		if exit_code != 0:
			result["message"] = "RAR解压失败"
			delete_directory(temp_extract_path)
			return result
		# RAR解压成功，继续扫描
	elif lower_path.ends_with(".7z"):
		result["message"] = "7z格式暂不支持，请手动解压后安装"
		delete_directory(temp_extract_path)
		return result
	else:
		# 使用Godot原生ZIPReader解压ZIP文件
		extract_success = extract_zip(abs_zip_path, abs_extract_path)
		print("=== ZIPReader解压结果:", extract_success)

		if not extract_success:
			result["message"] = "ZIP解压失败"
			delete_directory(temp_extract_path)
			return result

		# 检测是否为整合包（检查 bundle.json 是否存在）
		var is_bundle = false
		var bundle_name = ""
		var dir = DirAccess.open(abs_extract_path)
		if dir:
			# 先检查根目录是否有 bundle.json
			if FileAccess.file_exists(abs_extract_path.path_join("bundle.json")):
				is_bundle = true
				var bundle_file = FileAccess.open(abs_extract_path.path_join("bundle.json"), FileAccess.READ)
				if bundle_file:
					var bundle_json = JSON.new()
					if bundle_json.parse(bundle_file.get_as_text()) == OK:
						bundle_name = bundle_json.data.get("name", "bundle")
					bundle_file.close()
			else:
				# 根目录没有，再检查子目录
				dir.list_dir_begin()
				var entry = dir.get_next()
				while entry != "":
					if dir.current_is_dir() and entry != "." and entry != "..":
						var bundle_json_path = abs_extract_path.path_join(entry).path_join("bundle.json")
						if FileAccess.file_exists(bundle_json_path):
							is_bundle = true
							# 读取整合包名称
							var bundle_file = FileAccess.open(bundle_json_path, FileAccess.READ)
							if bundle_file:
								var bundle_json = JSON.new()
								if bundle_json.parse(bundle_file.get_as_text()) == OK:
									bundle_name = bundle_json.data.get("name", entry)
								bundle_file.close()
							break
					entry = dir.get_next()
				dir.list_dir_end()

		if is_bundle:
			result["message"] = "这是整合包文件，请到「整合包」页面导入"
			result["error_type"] = "is_bundle_not_mod"
			result["bundle_name"] = bundle_name
			delete_directory(temp_extract_path)
			return result

		# 检查解压是否成功
	if not extract_success:
		result["message"] = "解压失败"
		delete_directory(temp_extract_path)
		return result

	print("=== 解压完成 ===")
	print("解压路径: ", abs_extract_path)

	# 扫描解压后的内容（统一用正斜杠路径）
	var scan_path = abs_extract_path
	print("扫描路径: ", scan_path)

	# 扫描解压后的内容，找出所有模组（包括成功和失败的）
	var scan_result = scan_for_mods(scan_path, download_source, required_fields)
	var valid_mods = scan_result["valid_mods"]
	var invalid_mods = scan_result["invalid_mods"]

	print("=== 扫描结果 ===")
	print("有效模组数: ", valid_mods.size())
	print("无效模组数: ", invalid_mods.size())
	for i in range(invalid_mods.size()):
		print("  无效模组[", i, "]: ", invalid_mods[i])

	# 如果没有找到任何模组（valid和invalid都为空，可能是解压问题）
	if valid_mods.is_empty() and invalid_mods.is_empty():
		result["message"] = "未找到有效的模组（缺少必要的JSON文件）"
		delete_directory(temp_extract_path)
		return result

	# 如果有效模组为空但有无效模组，说明所有模组都验证失败
	if valid_mods.is_empty() and not invalid_mods.is_empty():
		result["success"] = false
		result["message"] = "所有模组缺少必要字段"
		result["failed_mods"] = invalid_mods
		result["installed_count"] = 0
		result["installed_mods"] = []
		delete_directory(temp_extract_path)
		return result

	# 移动每个有效模组到正确的位置
	var installed_count = 0
	var installed_mods = []
	var conflicts = []  # 检测版本冲突

	for mod_info in valid_mods:
		# mod_info["path"] 可能是解压目录（根目录有JSON的情况）或者是子目录
		var mod_dir = mod_info["path"]
		# 如果mod_dir等于temp_extract_path，说明是根目录情况，路径已经是正确的
		var target_dir = temp_base.path_join(mod_info["id"])

		# 如果目标目录已存在，检查是否真的需要替换
		if DirAccess.dir_exists_absolute(target_dir):
			print("[install_mod] Target dir exists: ", target_dir)
			var existing_info = get_mod_info(target_dir)
			print("[install_mod] existing_info.empty=", existing_info.is_empty(), " existing_info=", existing_info)
			if existing_info.is_empty():
				print("[install_mod] Existing mod has no JSON - treating as new install")
				# 已有模组无JSON，当成新版安装
				var copy_ok = copy_directory(mod_dir, target_dir)
				if copy_ok:
					mod_info["path"] = target_dir
					installed_count += 1
					installed_mods.append(mod_info)
				continue
			var new_version = mod_info.get("version", "")
			var existing_version = existing_info.get("version", "")
			var has_existing_version = existing_info.get("_has_version", false)
			var has_new_version = mod_info.get("_has_version", true)  # 新模组默认有version字段

			# 如果已有模组没有version字段：新模组不管有没有version，都记录冲突（因为无法确认是否相同）
			if not has_existing_version and has_new_version:
				print("[install_mod] Existing mod has no version field, recording conflict")
				conflicts.append({
					"id": mod_info["id"],
					"name": mod_info.get("name", mod_info["id"]),
					"new_version": new_version,
					"existing_version": "未知",
					"new_path": mod_dir,
					"existing_path": target_dir
				})
				continue

			# 如果已有模组有version，但新模组没有 → 冲突（降级风险）
			if has_existing_version and not has_new_version:
				print("[install_mod] New mod has no version, existing has version, recording conflict")
				conflicts.append({
					"id": mod_info["id"],
					"name": mod_info.get("name", mod_info["id"]),
					"new_version": "未知",
					"existing_version": existing_version,
					"new_path": mod_dir,
					"existing_path": target_dir
				})
				continue

			# 双方都有version，进行规范化比较
			var norm_new = new_version.strip_edges()
			var norm_existing = existing_version.strip_edges()
			if norm_new.begins_with("v"):
				norm_new = norm_new.substr(1)
			if norm_existing.begins_with("v"):
				norm_existing = norm_existing.substr(1)

			print("[install_mod] Target dir exists, comparing versions:")
			print("  existing: '", existing_version, "' vs new: '", new_version, "'")
			print("  normalized: '", norm_existing, "' vs '", norm_new, "'")

			# 只有版本不同时才记录冲突，相同版本直接覆盖安装
			if norm_new != norm_existing:
				print("[install_mod] Version different, recording conflict")
				conflicts.append({
					"id": mod_info["id"],
					"name": mod_info.get("name", mod_info["id"]),
					"new_version": new_version,
					"existing_version": existing_version,
					"new_path": mod_dir,
					"existing_path": target_dir
				})
				continue  # 跳过，等待用户决定如何处理
			else:
				print("[install_mod] Same version, will overwrite")

		# 检查源目录
		print("[install_mod] Checking mod_dir: '", mod_dir, "'")
		if DirAccess.dir_exists_absolute(mod_dir):
			var check_dir = DirAccess.open(mod_dir)
			if check_dir:
				print("[install_mod] mod_dir contents:")
				check_dir.list_dir_begin()
				var entry = check_dir.get_next()
				while entry != "":
					print("  - ", entry)
					entry = check_dir.get_next()
				check_dir.list_dir_end()

		# 移动到目标位置
		print("[install_mod] Copying from '", mod_dir, "' to '", target_dir, "'")
		var copy_ok = copy_directory(mod_dir, target_dir)
		print("[install_mod] copy_directory result: ", copy_ok)
		if copy_ok:
			# 更新path为正确的目标路径
			mod_info["path"] = target_dir
			installed_count += 1
			installed_mods.append(mod_info)
			print("[install_mod] Installed successfully, count: ", installed_count)
		else:
			print("[install_mod] Copy failed, skipping...")

	# 如果有冲突（不同版本），将冲突模组内容持久化保存后再清理 _temp_extract
	if not conflicts.is_empty():
		print("=== 发现版本冲突: ", conflicts.size(), " ===")
		for c in conflicts:
			print("  - ", c.get("name", ""), ": ", c.get("existing_version", ""), " -> ", c.get("new_version", ""))

		# 将冲突模组复制到持久化目录，避免 _temp_extract 被清理后路径失效
		var conflict_pending_dir = temp_base.path_join("_conflict_pending")
		if not DirAccess.dir_exists_absolute(conflict_pending_dir):
			DirAccess.make_dir_recursive_absolute(conflict_pending_dir)

		for conflict in conflicts:
			var new_path = conflict.get("new_path", "")
			var mod_id = conflict.get("id", "")
			if not new_path.is_empty() and not mod_id.is_empty():
				var target = conflict_pending_dir.path_join(mod_id)
				# 先删除旧的（如果存在）
				delete_directory(target)
				copy_directory(new_path, target)
				conflict["new_path"] = target  # 更新为持久化路径
				print("[install_mod] Persisted conflict mod: ", mod_id, " -> ", target)

		# 清理 _temp_extract
		delete_directory(temp_extract_path)

		result["success"] = true
		result["has_conflicts"] = true
		result["conflicts"] = conflicts
		result["installed_count"] = installed_count
		result["installed_mods"] = installed_mods
		result["message"] = "发现 %d 个版本冲突" % conflicts.size()
		result["conflict_pending_dir"] = conflict_pending_dir
		return result

	# 没有冲突，统一删除临时解压目录
	var del_ok = delete_directory(temp_extract_path)
	print("[install_mod] temp_extract cleanup: ", del_ok)

	# 如果既没有安装任何模组也没有冲突，说明无法移动
	if installed_count == 0 and conflicts.is_empty():
		result["message"] = "安装失败：无法移动模组文件"
		result["failed_mods"] = invalid_mods
		return result

	result["success"] = true
	result["installed_count"] = installed_count
	result["installed_mods"] = installed_mods
	result["failed_mods"] = invalid_mods

	if installed_count == 1:
		result["message"] = "模组安装成功: " + installed_mods[0].get("name", "Unknown")
		result["mod_info"] = installed_mods[0]
	else:
		result["message"] = "成功安装 %d 个模组" % installed_count

	return result


# 应用 _conflict_pending 中的冲突模组（覆盖现有版本）
static func apply_conflict_mods(conflict_pending_dir: String) -> Dictionary:
	print("[apply_conflict_mods] conflict_pending_dir: ", conflict_pending_dir)
	var result = {"success": false, "message": "", "installed_count": 0}

	if not DirAccess.dir_exists_absolute(conflict_pending_dir):
		result["message"] = "Conflict pending dir not found: " + conflict_pending_dir
		return result

	var base_path = get_base_path()
	var temp_base = base_path + "temp_mods"
	var installed_count = 0

	var dir = DirAccess.open(conflict_pending_dir)
	if dir:
		dir.list_dir_begin()
		var entry = dir.get_next()
		while entry != "":
			if dir.current_is_dir() and entry != "." and entry != "..":
				var mod_id = entry
				var source_dir = conflict_pending_dir.path_join(mod_id)
				var target_dir = temp_base.path_join(mod_id)

				# 删除旧的（如果存在）
				if DirAccess.dir_exists_absolute(target_dir):
					delete_directory(target_dir)

				# 复制新的
				var copy_ok = copy_directory(source_dir, target_dir)
				if copy_ok:
					print("[apply_conflict_mods] Applied conflict mod: ", mod_id)
					installed_count += 1
				else:
					print("[apply_conflict_mods] Failed to apply: ", mod_id)
			entry = dir.get_next()
		dir.list_dir_end()

	# 清理 conflict_pending 目录
	delete_directory(conflict_pending_dir)

	result["success"] = true
	result["installed_count"] = installed_count
	result["message"] = "成功解决 %d 个冲突" % installed_count
	return result


# 扫描解压后的目录，查找所有模组并验证
# 返回: {"valid_mods": [], "invalid_mods": []}
static func scan_for_mods(extract_path: String, download_source: String = "", required_fields: Array = []) -> Dictionary:
	print("=== scan_for_mods 开始 === extract_path: ", extract_path)
	var valid_mods = []
	var invalid_mods = []

	var dir = DirAccess.open(extract_path)
	if dir == null:
		print("无法打开目录")
		return {"valid_mods": valid_mods, "invalid_mods": invalid_mods}

	# 获取解压后根目录下的所有子文件夹和文件
	var subdirs = []
	var json_files = []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			if dir.current_is_dir():
				subdirs.append(file_name)
				print("  子目录: ", file_name)
			elif file_name.ends_with(".json"):
				json_files.append(extract_path.path_join(file_name))
				print("  JSON文件: ", file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	print("解压后根目录下的子文件夹: ", subdirs)
	print("解压后根目录下的JSON文件: ", json_files)

	# 情况1: 根目录下有JSON文件（没有子文件夹的情况）
	if not json_files.is_empty():
		print("检测到根目录下的JSON文件")
		for json_path in json_files:
			print("  处理JSON: ", json_path)
			var mod_dir = extract_path
			var mod_info = validate_and_get_mod_info(mod_dir, json_path, json_path.get_file().get_basename(), download_source, required_fields)
			print("  验证结果: ", mod_info)

			if mod_info.has("reason"):
				print("  JSON文件无效: ", json_path, " 原因: ", mod_info.get("reason"))
				invalid_mods.append({"name": json_path.get_file(), "reason": mod_info.get("reason")})
			else:
				print("  -> 有效: ", mod_info.get("name", ""))
				valid_mods.append(mod_info)

		# 如果找到了有效模组，直接返回
		if not valid_mods.is_empty():
			print("=== scan_for_mods 结束（根目录JSON）===")
			print("有效模组: ", valid_mods.size())
			return {"valid_mods": valid_mods, "invalid_mods": invalid_mods}

	# 情况2: 有子文件夹，按照原有逻辑处理
	if subdirs.size() == 1:
		print("处理单个子目录: ", subdirs[0])
		var nested_result = scan_nested_mod_folder(extract_path.path_join(subdirs[0]), subdirs[0])
		if not nested_result["valid_mods"].is_empty():
			valid_mods.append_array(nested_result["valid_mods"])
		if not nested_result["invalid_mods"].is_empty():
			invalid_mods.append_array(nested_result["invalid_mods"])
	else:
		# 多个子目录：每个子文件夹都是一个可能的模组
		for subdir_name in subdirs:
			var subdir_path = extract_path.path_join(subdir_name)
			print("检查模组文件夹: ", subdir_name)

			# 查找该文件夹下所有的JSON文件
			var subdir_json_files = find_all_json_files(subdir_path)
			print("  找到JSON文件: ", subdir_json_files)

			if subdir_json_files.is_empty():
				# 没有找到JSON文件，记录为无效
				print("  -> 无效: 未找到JSON文件")
				invalid_mods.append({"name": subdir_name, "reason": "缺少必要的JSON文件"})
				continue

			# 尝试每个JSON文件，找到第一个有效的
			var found_valid = false
			for json_path in subdir_json_files:
				var mod_dir = json_path.get_base_dir()
				var mod_info = validate_and_get_mod_info(mod_dir, json_path, subdir_name)

				if mod_info.has("reason"):
					# 这个JSON无效，继续尝试下一个
					print("  JSON文件无效: ", json_path, " 原因: ", mod_info.get("reason"))
					continue
				else:
					# 找到有效的JSON
					print("  -> 有效: ", mod_info.get("name", ""))
					valid_mods.append(mod_info)
					found_valid = true
					break

			# 所有JSON文件都无效
			if not found_valid:
				print("  -> 无效: 所有JSON文件都缺少必要字段")
				invalid_mods.append({"name": subdir_name, "reason": "所有JSON文件都缺少必要字段"})

	print("=== scan_for_mods 结束 ===")
	print("有效模组: ", valid_mods.size())
	print("无效模组: ", invalid_mods.size())

	return {"valid_mods": valid_mods, "invalid_mods": invalid_mods}


# 扫描嵌套的模组文件夹（处理单子目录的嵌套情况）
static func scan_nested_mod_folder(folder_path: String, original_name: String) -> Dictionary:
	var valid_mods = []
	var invalid_mods = []

	while true:
		# 查找所有JSON文件
		var json_files = find_all_json_files(folder_path)

		if not json_files.is_empty():
			# 尝试每个JSON文件，找到第一个有效的
			var found_valid = false
			for json_path in json_files:
				var mod_dir = json_path.get_base_dir()
				var mod_info = validate_and_get_mod_info(mod_dir, json_path, original_name)

				if mod_info.has("reason"):
					# 这个JSON无效，继续尝试下一个
					continue
				else:
					# 有效模组
					valid_mods.append(mod_info)
					found_valid = true
					break

			# 如果没有找到有效的，记录失败
			if not found_valid:
				invalid_mods.append({"name": original_name, "reason": "所有JSON文件都缺少必要字段"})

			return {"valid_mods": valid_mods, "invalid_mods": invalid_mods}

		# 检查是否只有一个子目录，可以继续深入
		var inner_dir = DirAccess.open(folder_path)
		if inner_dir == null:
			break

		var inner_subdirs = []
		inner_dir.list_dir_begin()
		var inner_name = inner_dir.get_next()
		while inner_name != "":
			if inner_dir.current_is_dir() and inner_name != "." and inner_name != "..":
				inner_subdirs.append(inner_name)
			inner_name = inner_dir.get_next()
		inner_dir.list_dir_end()

		# 只有一个子目录，继续深入
		if inner_subdirs.size() == 1:
			folder_path = folder_path.path_join(inner_subdirs[0])
		else:
			break

	# 没找到有效模组
	invalid_mods.append({"name": original_name, "reason": "缺少必要的JSON文件"})
	return {"valid_mods": valid_mods, "invalid_mods": invalid_mods}


# 验证并获取模组信息（检查9个必要字段）
# 必要字段: id, name, author, description, version, has_pck, has_dll, dependencies, affects_gameplay
# 返回: 有效返回完整信息，无效返回包含缺失字段详情的reason
static func validate_and_get_mod_info(mod_path: String, json_path: String, fallback_name: String, download_source: String = "", required_fields: Array = []) -> Dictionary:
	var info = {}

	# 使用本地变量存储要检查的字段（如果为空则不验证任何字段）
	var fields_to_check = required_fields.duplicate()

	var file = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return {"name": fallback_name, "reason": "无法读取JSON文件"}

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		return {"name": fallback_name, "reason": "JSON格式错误"}

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return {"name": fallback_name, "reason": "JSON不是有效对象"}

	# 动态验证必要字段
	var missing_fields = []
	var mod_id = ""  # 用于存储id

	# 始终尝试从JSON中获取id（不管是否在验证列表中）
	if data.has("id"):
		var id_value = data.get("id", "")
		if typeof(id_value) == TYPE_STRING and not id_value.is_empty():
			mod_id = id_value
	elif data.has("pck_name"):
		var pck_name = data.get("pck_name", "")
		if typeof(pck_name) == TYPE_STRING and not pck_name.is_empty():
			mod_id = pck_name

	# 遍历所有必要字段进行验证
	for field in fields_to_check:
		var field_valid = false
		var field_value = data.get(field, null)

		match field:
			"id", "name", "author", "description", "version":
				# 字符串字段
				if field_value != null and typeof(field_value) == TYPE_STRING and not str(field_value).is_empty():
					field_valid = true
					if field == "id":
						mod_id = str(field_value)
				elif field == "id" and data.has("pck_name"):
					# id 也接受 pck_name
					var pck_name = data.get("pck_name", "")
					if typeof(pck_name) == TYPE_STRING and not pck_name.is_empty():
						mod_id = pck_name
						field_valid = true
			"has_pck", "has_dll", "affects_gameplay":
				# 布尔字段
				if field_value != null and typeof(field_value) == TYPE_BOOL:
					field_valid = true
			_:
				# 其他字段：只要存在即可
				if field_value != null:
					field_valid = true

		if not field_valid:
			missing_fields.append(field)

	# 如果有缺失字段，返回缺失信息
	if not missing_fields.is_empty():
		print("  验证失败，缺失字段: ", missing_fields)
		return {"name": fallback_name, "reason": "缺少字段: " + ", ".join(missing_fields)}

	print("  验证成功!")

	# 填充信息
	info = data.duplicate(true)

	# 确保id字段存在（如果没有找到，使用fallback_name作为id）
	if mod_id.is_empty():
		mod_id = fallback_name
	info["id"] = mod_id

	info["path"] = mod_path

	# 记录version是否来自JSON（validate_and_get_mod_info直接操作JSON数据）
	if info.has("version") and typeof(info["version"]) == TYPE_STRING and not str(info["version"]).is_empty():
		info["_has_version"] = true
	else:
		info["_has_version"] = false
		info["version"] = ""  # 清空默认值

	# 检查是否有PCK和DLL文件
	var dir = DirAccess.open(mod_path)
	if dir != null:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".pck"):
				info["has_pck"] = true
			elif file_name.ends_with(".dll"):
				info["has_dll"] = true
			file_name = dir.get_next()
		dir.list_dir_end()

	# 设置下载来源
	print("[scan_for_mods] download_source: '", download_source, "'")
	if not download_source.is_empty():
		info["download_source"] = download_source

	print("[scan_for_mods] Final mod_info: ", info)
	return info


# 使用Godot原生ZIPReader解压ZIP文件
static func extract_zip(zip_path: String, destination: String) -> bool:
	print("=== ZIPReader解压开始 ===")
	print("zip_path: ", zip_path)
	print("destination: ", destination)

	# 检查ZIP文件是否存在
	if not FileAccess.file_exists(zip_path):
		print("ZIP文件不存在: ", zip_path)
		return false

	# 确保目标目录存在
	if not DirAccess.dir_exists_absolute(destination):
		var result = DirAccess.make_dir_recursive_absolute(destination)
		if result != OK:
			print("无法创建目标目录: ", destination)
			return false

	var zip_reader = ZIPReader.new()
	var open_result = zip_reader.open(zip_path)
	if open_result != OK:
		print("无法打开ZIP文件: ", zip_path)
		zip_reader.close()
		return false

	var files = zip_reader.get_files()
	print("ZIP内文件数: ", files.size())

	for file_path in files:
		# 跳过目录（以/结尾）
		if file_path.ends_with("/"):
			continue

		var full_destination = destination.path_join(file_path)

		# 创建目标文件的目录
		var dest_dir = DirAccess.open(full_destination.get_base_dir())
		if dest_dir == null:
			var mkdir_result = DirAccess.make_dir_recursive_absolute(full_destination.get_base_dir())
			if mkdir_result != OK:
				print("无法创建目录: ", full_destination.get_base_dir())
				continue

		# 读取并写入文件
		var data = zip_reader.read_file(file_path)
		var file = FileAccess.open(full_destination, FileAccess.WRITE)
		if file == null:
			print("无法创建文件: ", full_destination)
			continue

		file.store_buffer(data)
		file.close()

	zip_reader.close()
	print("=== ZIPReader解压完成 ===")
	return true


# 卸载模组
# remove_enabled: false 表示只删除临时文件夹中的模组
static func uninstall_mod(mod_name: String, remove_enabled: bool = false, game_path: String = "") -> bool:
	print("=== ModUtils.uninstall_mod ===", mod_name, "remove_enabled:", remove_enabled)
	var base = get_base_path()
	var temp_path = (base + "temp_mods").path_join(mod_name)
	print("temp_path:", temp_path)
	print("temp exists:", DirAccess.dir_exists_absolute(temp_path))

	var any_deleted = false

	# 如果需要删除启用文件夹中的模组
	if remove_enabled:
		# 删除 test_mods 中的模组
		var test_path = (base + "test_mods").path_join(mod_name)
		print("test_path:", test_path)
		print("test exists:", DirAccess.dir_exists_absolute(test_path))
		if DirAccess.dir_exists_absolute(test_path):
			if delete_directory(test_path):
				any_deleted = true
				print("test folder deleted")

		# 删除游戏 mods 中的模组
		if not game_path.is_empty():
			var game_mods_path = game_path.path_join("mods").path_join(mod_name)
			print("game_mods_path:", game_mods_path)
			print("game mods exists:", DirAccess.dir_exists_absolute(game_mods_path))
			if DirAccess.dir_exists_absolute(game_mods_path):
				if delete_directory(game_mods_path):
					any_deleted = true
					print("game mods folder deleted")

	# 删除临时文件夹中的模组
	if DirAccess.dir_exists_absolute(temp_path):
		var result = delete_directory(temp_path)
		print("delete temp result:", result)
		if result:
			any_deleted = true

	# 如果没有任何目录被删除（都不存在），返回 false
	if not any_deleted:
		print("=== uninstall complete: nothing to delete ===")
		return false

	print("=== uninstall complete: success ===")
	return true



# 检查模组是否已启用
static func is_mod_enabled(mod_data: Dictionary, game_path: String) -> bool:
	if game_path.is_empty():
		return false
	
	var mod_name = mod_data.get("id", "")
	if mod_name.is_empty():
		return false
	
	var game_mods_path = game_path.path_join("mods")
	var mod_path = game_mods_path.path_join(mod_name)
	
	return DirAccess.dir_exists_absolute(mod_path)


# 复制目录（从file_utils复制）
static func copy_directory(source: String, destination: String) -> bool:
	print("[copy_directory] START - Source: '", source, "', Dest: '", destination, "'")
	var dir = DirAccess.open(source)
	if dir == null:
		push_error("[copy_directory] FAILED: Cannot open source")
		return false

	var dest_parent = destination.get_base_dir()
	print("[copy_directory] Dest parent: '", dest_parent, "'")

	if DirAccess.dir_exists_absolute(destination):
		print("[copy_directory] Dest exists, removing first...")
		# 必须先递归删除目录内容，否则remove_absolute会失败
		var delete_result = delete_directory(destination)
		push_error("[copy_directory] delete_directory result: " + str(delete_result))
		if not delete_result:
			push_error("[copy_directory] FAILED: Cannot delete destination contents")
			return false

	print("[copy_directory] Creating dest dir...")
	var make_result = DirAccess.make_dir_recursive_absolute(destination)
	push_error("[copy_directory] make_result: " + str(make_result))
	if make_result != OK:
		push_error("[copy_directory] FAILED: Cannot create destination dir")
		return false

	# 复制文件
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue

		var source_path = source.path_join(file_name)
		var dest_path = destination.path_join(file_name)

		if dir.current_is_dir():
			print("[copy_directory] Recursive copy subdir: ", file_name)
			if not copy_directory(source_path, dest_path):
				push_error("[copy_directory] FAILED: Recursive copy failed")
				return false
		else:
			print("[copy_directory] Copying file: ", file_name)
			var copy_result = DirAccess.copy_absolute(source_path, dest_path)
			if copy_result != OK:
				push_error("[copy_directory] FAILED: copy_absolute returned " + str(copy_result) + " for " + file_name)
				return false

		file_name = dir.get_next()

	dir.list_dir_end()
	print("[copy_directory] SUCCESS!")
	return true


# 删除目录（从file_utils复制）
static func delete_directory(path: String) -> bool:
	var dir = DirAccess.open(path)
	if dir == null:
		return false
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		
		var file_path = path.path_join(file_name)
		
		if dir.current_is_dir():
			if not delete_directory(file_path):
				return false
		else:
			if DirAccess.remove_absolute(file_path) != OK:
				return false
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	if DirAccess.remove_absolute(path) != OK:
		return false
	
	return true
