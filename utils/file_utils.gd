extends RefCounted
class_name FileUtils

# 文件操作工具类

# 复制目录及其所有内容
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
		var remove_result = DirAccess.remove_absolute(destination)
		push_error("[copy_directory] remove result: " + str(remove_result))
		if remove_result != OK:
			push_error("[copy_directory] FAILED: Cannot remove destination")
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


# 删除目录及其所有内容
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


# 移动目录
static func move_directory(source: String, destination: String) -> bool:
	if copy_directory(source, destination):
		return delete_directory(source)
	return false


# 创建带时间戳的备份
static func create_backup(source_path: String, backup_dir: String) -> String:
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var backup_name = "backup_" + timestamp
	var backup_path = backup_dir.path_join(backup_name)
	
	if copy_directory(source_path, backup_path):
		return backup_path
	
	return ""


# 检查文件是否存在
static func file_exists(path: String) -> bool:
	if FileAccess.file_exists(path):
		return true
	else:
		return DirAccess.dir_exists_absolute(path)


# 复制单个文件
static func copy_file(source: String, destination: String) -> bool:
	# 确保目标目录存在
	var dest_dir = DirAccess.open(destination.get_base_dir())
	if dest_dir == null:
		var result = DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		if result != OK:
			return false

	# 复制文件
	if DirAccess.copy_absolute(source, destination) != OK:
		return false

	return true


# 辅助函数：转换Godot路径为Windows路径
static func to_windows_path(godot_path: String) -> String:
	return godot_path.replace("/", "\\")


# 规范化路径（统一使用反斜杠，处理混用斜杠的问题）
static func normalize_path(path: String) -> String:
	# 先把正斜杠替换为反斜杠
	var normalized = path.replace("/", "\\")
	# 处理连续的多个反斜杠（但保留 UNC 路径的 //）
	normalized = normalized.replace("\\\\", "\\")
	# 移除路径末尾的反斜杠（除非是驱动器根目录）
	if normalized.length() > 3 and normalized.ends_with("\\"):
		normalized = normalized.substr(0, normalized.length() - 1)
	return normalized


# 读取JSON文件
static func read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		return {}
	
	return json.get_data()
