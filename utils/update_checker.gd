extends RefCounted
class_name UpdateChecker

## 更新源 URL 配置
var gitee_url: String = "https://gitee.com/ckccbaize/STS2_modmanager/raw/class/version.json"
var github_url: String = "https://raw.githubusercontent.com/ckccbaize/STS2_modmanager/class/version.json"

## 当前版本（从 config 读取）
var current_version: String = "v0.0.0"

## 可用的新版本信息
var new_version_available: Dictionary = {}

## 上一次检查结果（用于 API 同步返回）
var last_check_result: Dictionary = {}

## 回调函数（通过 Callable 设置）
var _update_checked_callback: Callable
var _download_progress_callback: Callable
var _download_complete_callback: Callable
var _download_error_callback: Callable

## 超时时间（秒）
var timeout: float = 10.0

## 设置更新源 URL
func set_urls(gitee: String, github: String) -> void:
	gitee_url = gitee
	github_url = github

## 设置当前版本
func set_current_version(version: String) -> void:
	print("[UpdateChecker] set_current_version called: '", version, "'")
	current_version = version
	print("[UpdateChecker] current_version now: '", current_version, "'")

## 设置回调
func set_callbacks(update_checked: Callable, download_progress: Callable = Callable(), download_complete: Callable = Callable(), download_error: Callable = Callable()) -> void:
	_update_checked_callback = update_checked
	_download_progress_callback = download_progress
	_download_complete_callback = download_complete
	_download_error_callback = download_error

## 比较版本号: current vs remote
## 返回: 1=远程更新, -1=当前更新, 0=相同
func compare_versions(current: String, remote: String) -> int:
	var current_ver = current.lstrip("v")
	var remote_ver = remote.lstrip("v")

	print("[CompareVersions] current: '", current, "' -> '", current_ver, "', remote: '", remote, "' -> '", remote_ver, "'")

	var current_parts = current_ver.split(".")
	var remote_parts = remote_ver.split(".")

	var max_parts = max(current_parts.size(), remote_parts.size())
	for i in range(max_parts):
		var c = 0
		var r = 0
		if i < current_parts.size():
			c = current_parts[i].to_int()
		if i < remote_parts.size():
			r = remote_parts[i].to_int()

		print("[CompareVersions] Part ", i, ": current=", c, ", remote=", r)

		if r > c:
			return 1
		elif r < c:
			return -1

	return 0

## 从 URL 获取 version.json
func _fetch_version_from_url(url: String) -> Dictionary:
	print("[UpdateChecker] 请求 URL: ", url)

	# 创建临时的 HTTPRequest 节点
	var http_request = HTTPRequest.new()
	http_request.name = "UpdateHTTPRequest"
	Engine.get_main_loop().root.add_child(http_request)

	var headers = ["User-Agent: STS2-ModManager/2.6.9"]
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)

	if error != OK:
		http_request.queue_free()
		print("[UpdateChecker] 请求失败 error: ", error)
		return {"success": false, "error": "请求失败: " + str(error)}

	var response = await http_request.request_completed
	http_request.queue_free()

	var result = response[0]
	var code = response[1]
	var body = response[3]

	print("[UpdateChecker] 响应 result: ", result, " code: ", code)

	if result != HTTPRequest.RESULT_SUCCESS:
		print("[UpdateChecker] 网络错误: ", result)
		return {"success": false, "error": "网络错误: " + str(result)}

	if code != 200:
		print("[UpdateChecker] HTTP 错误: ", code)
		return {"success": false, "error": "HTTP 错误: " + str(code)}

	# 处理 body 可能是 PackedByteArray 或 PackedStringArray 的情况
	var body_str: String
	if body is PackedStringArray:
		body_str = "\n".join(body)
	else:
		body_str = body.get_string_from_utf8()
	print("[UpdateChecker] 响应内容: ", body_str)

	var json = JSON.new()
	var parse_error = json.parse(body_str)
	if parse_error != OK:
		print("[UpdateChecker] JSON 解析失败")
		return {"success": false, "error": "JSON 解析失败"}

	print("[UpdateChecker] 解析后的数据: ", json.data)
	return {"success": true, "data": json.data}

## 检查更新
## auto_check: 是否是自动检查（自动检查失败不提示，手动检查失败提示用户）
## 返回: Dictionary，包含 success, has_update, data 等字段（同步返回，结果通过回调异步通知）
func check_for_updates(auto_check: bool = true) -> Dictionary:
	# 立即返回"检查中"状态，实际结果通过回调通知
	# 异步操作开始
	_check_updates_async(auto_check)
	return {"success": true, "status": "checking"}


func _check_updates_async(auto_check: bool) -> void:
	# 优先尝试 Gitee
	var result = await _fetch_version_from_url(gitee_url)
	if result.success:
		_handle_version_response(result.data, auto_check)
		return

	# Gitee 失败，尝试 GitHub
	result = await _fetch_version_from_url(github_url)
	if result.success:
		_handle_version_response(result.data, auto_check)
		return

	# 全部失败
	if not auto_check:
		_emit_update_checked({"success": false, "error": "检查更新失败，请稍后重试"})
	else:
		_emit_update_checked({"success": false, "error": ""})

## 处理版本响应
func _handle_version_response(data: Dictionary, auto_check: bool) -> void:
	if not data.has("version"):
		if not auto_check:
			_emit_update_checked({"success": false, "error": "版本信息格式错误"})
		return

	var remote_version = data["version"]
	var cmp = compare_versions(current_version, remote_version)

	if cmp > 0:
		# 发现新版本
		new_version_available = data
		_emit_update_checked({"success": true, "has_update": true, "data": data})
	elif cmp == 0:
		_emit_update_checked({"success": true, "has_update": false, "data": data})
	else:
		# 当前版本更新（理论上不会出现）
		_emit_update_checked({"success": true, "has_update": false, "data": data})

## 发出更新检查结果
func _emit_update_checked(result: Dictionary) -> void:
	# 保存检查结果供 API 查询
	last_check_result = result
	if _update_checked_callback and _update_checked_callback.is_valid():
		_update_checked_callback.call(result)
	else:
		print("[UpdateChecker] update_checked callback not set")

## 获取上一次检查结果（用于 API 同步返回）
func get_last_check_result() -> Dictionary:
	return last_check_result

## 下载更新文件
func download_update(download_url: String) -> void:
	print("[UpdateChecker] download_update called with URL: ", download_url)
	# 使用 call_deferred 确保在主线程执行
	call_deferred("_download_update_deferred", download_url)


func _download_update_deferred(download_url: String) -> void:
	# 下载到用户下载目录
	var downloads_dir = OS.get_environment("USERPROFILE") + "/Downloads"
	var zip_path = downloads_dir + "/STS2-ModManager-update.zip"

	# 转换路径为 Windows 格式
	var win_path = zip_path.replace("/", "\\")

	# 使用 curl 通过 cmd 后台运行
	var curl_cmd = 'curl -L --max-time 600 -o "%s" -A "STS2-ModManager/2.6.9" -- "%s"' % [win_path, download_url]
	var full_command = "start \"\" cmd /C " + curl_cmd

	print("[UpdateChecker] Executing: ", full_command)
	var output = []
	# 使用 false 实现真正的异步执行
	var ret = OS.execute("cmd", ["/C", full_command], output, false)
	print("[UpdateChecker] OS.execute returned: ", ret)

	# 发出开始下载信号
	_emit_download_progress(0.1)

	# 使用定时器监控下载进度
	_start_download_monitor(zip_path)


var _download_monitor_timer: Timer = null
var _download_zip_path: String = ""
var _download_start_time: int = 0

func _start_download_monitor(zip_path: String) -> void:
	_download_zip_path = zip_path
	_download_start_time = Time.get_unix_time_from_system()

	# 使用 call_deferred 确保在主线程中添加定时器
	_start_timer_deferred()


func _start_timer_deferred() -> void:
	# 创建定时器监控下载状态
	_download_monitor_timer = Timer.new()
	_download_monitor_timer.wait_time = 1.0
	_download_monitor_timer.timeout.connect(_check_download_status)
	Engine.get_main_loop().root.add_child(_download_monitor_timer)
	_download_monitor_timer.start()


func _check_download_status() -> void:
	# 检查文件是否存在且大小不再增加
	if FileAccess.file_exists(_download_zip_path):
		# 读取文件大小
		var file = FileAccess.open(_download_zip_path, FileAccess.READ)
		if file:
			var file_size = file.get_length()
			file.close()

			# 如果文件大小超过最小值，认为下载完成
			if file_size > 1024:
				_download_monitor_timer.stop()
				_download_monitor_timer.queue_free()
				_download_monitor_timer = null

				print("[UpdateChecker] Download completed, file size: ", file_size)
				_emit_download_progress.call_deferred(1.0)
				_emit_download_complete.call_deferred(_download_zip_path)
				return

	# 检查是否超时（10分钟）
	var elapsed = Time.get_unix_time_from_system() - _download_start_time
	if elapsed > 600:
		_download_monitor_timer.stop()
		_download_monitor_timer.queue_free()
		_download_monitor_timer = null

		print("[UpdateChecker] Download timeout")
		_emit_download_error("下载超时")


## 发出下载进度
func _emit_download_progress(percent: float) -> void:
	if _download_progress_callback and _download_progress_callback.is_valid():
		_download_progress_callback.call(percent)

## 发出下载完成
func _emit_download_complete(save_path: String) -> void:
	print("[UpdateChecker] _emit_download_complete called with: ", save_path)
	if _download_complete_callback and _download_complete_callback.is_valid():
		_download_complete_callback.call(save_path)
	else:
		print("[UpdateChecker] download_complete callback not set or invalid")

## 发出下载错误
func _emit_download_error(message: String) -> void:
	print("[UpdateChecker] _emit_download_error: ", message)
	if _download_error_callback and _download_error_callback.is_valid():
		_download_error_callback.call(message)
	else:
		print("[UpdateChecker] download_error callback not set or invalid")
