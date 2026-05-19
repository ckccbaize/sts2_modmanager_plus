extends RefCounted
class_name LocalServer

# 本地HTTP服务器 - 监听浏览器扩展的下载请求

const DEFAULT_PORT: int = 28900  # 使用 28900 开始，避开被僵尸进程占用的端口
const BACKUP_PORTS: Array[int] = [28901, 28902, 28903, 28904]
const PORT_POOL_START: int = 29000  # 动态扩展端口池起始
const PORT_POOL_MAX: int = 29100     # 最大扩展到 29100

var _server_port: int = DEFAULT_PORT
var _actual_port: int = DEFAULT_PORT  # 实际使用的端口
var _server: TCPServer = null
var _is_running: bool = false
var _thread: Thread = null
var _mutex: Mutex = null
var _active_downloads: int = 0
var _installed_mods_count: int = 0

# Nexus API 引用
var _nexus_api: NexusAPI = null

# API 桥接（线程→主线程通信）
var _api_bridge: ApiBridge = null

signal download_request_received(data: Dictionary)
signal server_status_changed(running: bool)
signal server_error(error: String)


func _init() -> void:
	_mutex = Mutex.new()


func set_port(port: int) -> void:
	_server_port = port


func get_port() -> int:
	if _is_running:
		return _actual_port  # 返回实际绑定的端口
	return _server_port  # 返回配置的端口


func set_nexus_api(api: NexusAPI) -> void:
	_nexus_api = api


func set_api_bridge(bridge: ApiBridge) -> void:
	_api_bridge = bridge


func start() -> bool:
	if _is_running:
		return true

	_actual_port = _server_port  # 重置为配置的端口

	# 尝试绑定主端口
	_server = TCPServer.new()
	var err = _server.listen(_server_port, "127.0.0.1")
	if err != OK:
		# 端口被占用，尝试备用端口
		print("[LocalServer] Port ", _server_port, " bind failed, trying backup ports...")
		err = _try_bind_backup_ports()

	if err != OK:
		# 所有固定端口都不可用，自动扩展端口池
		print("[LocalServer] All fixed ports occupied, searching for available port...")
		var new_port = _find_available_port()
		if new_port > 0:
			_actual_port = new_port
			print("[LocalServer] Using dynamic port: ", new_port)
			# 成功绑定动态端口，直接返回
			_is_running = true
			server_status_changed.emit(true)
			_write_port_to_file()
			_thread = Thread.new()
			_thread.start(_thread_loop.bind(self), Thread.PRIORITY_NORMAL)
			print("[LocalServer] Server started on port ", _actual_port)
			return true
		else:
			print("[LocalServer] Failed to start server: no available port")
			server_error.emit("Failed to start server: no available port")
			_server = null
			return false

	_is_running = true
	server_status_changed.emit(true)

	# 将实际端口写入文件供 BrowserHost 读取
	_write_port_to_file()

	# 启动处理线程
	_thread = Thread.new()
	_thread.start(_thread_loop.bind(self), Thread.PRIORITY_NORMAL)

	print("[LocalServer] Server started on port ", _actual_port)
	return true


func _try_bind_backup_ports() -> int:
	# 尝试所有备用端口 - 直接尝试，不做任何清理
	for backup_port in BACKUP_PORTS:
		_server = TCPServer.new()
		var err = _server.listen(backup_port, "127.0.0.1")
		if err == OK:
			_actual_port = backup_port
			print("[LocalServer] Successfully bound to backup port: ", backup_port)
			return OK
		else:
			print("[LocalServer] Port ", backup_port, " bind failed")

	print("[LocalServer] All backup ports failed")
	return FAILED


func _find_available_port() -> int:
	# 从 28905 开始搜索可用端口
	var port = 29005  # 从 29005 开始避免与固定端口冲突
	var max_port = 29100
	var output = []

	while port <= max_port:
		var test_server = TCPServer.new()
		var err = test_server.listen(port, "127.0.0.1")
		if err == OK:
			# 成功绑定，释放测试 server 并使用这个端口
			test_server.stop()
			test_server = null
			_server = TCPServer.new()
			err = _server.listen(port, "127.0.0.1")
			if err == OK:
				print("[LocalServer] Found available port: ", port)
				return port
		test_server = null

		# 检查端口是否被占用（用于日志）
		OS.execute("netstat", ["-ano"], output, false)
		var is_occupied = false
		for line in output:
			if ":" + str(port) in line and "LISTENING" in line:
				is_occupied = true
				break

		if not is_occupied:
			# 端口未被占用但绑定失败，可能是其他问题
			print("[LocalServer] Port ", port, " not occupied but bind failed")
		else:
			# 端口被占用，尝试下一个
			pass

		port += 1

	print("[LocalServer] No available port found in range ", PORT_POOL_START, "-", max_port)
	return -1


func _write_port_to_file() -> void:
	# 将实际端口写入文件供 BrowserHost 读取
	var godot_appdata = OS.get_environment("APPDATA")
	var godot_dir = godot_appdata.replace("/", "\\") + "\\Godot\\app_userdata\\sts-2-modmanager"
	var port_file = godot_dir + "\\.local_server_port"
	# 确保目录存在
	var mkdir_output = []
	OS.execute("cmd", ["/C", "mkdir \"" + godot_dir + "\""], mkdir_output, false)
	# 写入文件
	var file = FileAccess.open(port_file, FileAccess.WRITE)
	if file != null:
		file.store_string(str(_actual_port))
		file.close()
		print("[LocalServer] Port written to file: ", port_file)
	else:
		print("[LocalServer] Failed to write port file: ", port_file)


func stop() -> void:
	if not _is_running:
		return

	# print("[LocalServer] Stopping server...")
	_is_running = false

	# 等待线程结束
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

	# 关闭服务器
	if _server != null:
		_server.stop()
		_server = null

	server_status_changed.emit(false)
	# print("[LocalServer] Server stopped")


func is_running() -> bool:
	return _is_running


func get_status() -> Dictionary:
	_mutex.lock()
	var count = _active_downloads
	var installed = _installed_mods_count
	_mutex.unlock()

	return {
		"running": _is_running,
		"active_downloads": count,
		"installed_mods": installed,
		"version": "1.0.0"
	}


func _thread_loop(server_ref: LocalServer) -> void:
	while server_ref._is_running:
		if server_ref._server == null:
			break

		# 等待客户端连接
		var client = server_ref._server.take_connection()
		if client == null:
			# 没有连接，睡眠一小段时间（减少延迟）
			OS.delay_msec(10)
			continue

		# 处理请求
		server_ref._handle_client(client)

	# 清理
	if server_ref._server != null:
		server_ref._server.stop()
		server_ref._server = null


func _handle_client(client: StreamPeerTCP) -> void:
	# print("[LocalServer] Client connected")

	var request_data = ""

	# 设置超时
	client.set_no_delay(true)

	# 读取请求
	var buffer = PackedByteArray()
	var max_read = 20971520  # 20MB max (支持大文件base64上传, 10MB ZIP ≈ 14MB base64)

	# 第一阶段：读取headers（知道Content-Length）
	var content_length = -1
	var headers_complete = false

	while buffer.size() < max_read:
		# 等待数据到达
		var start_time = Time.get_ticks_msec()
		while client.get_available_bytes() == 0:
			if Time.get_ticks_msec() - start_time > 200:  # 200ms超时
				break
			OS.delay_usec(500)

		var available = client.get_available_bytes()
		if available == 0:
			if buffer.size() > 0 and headers_complete:
				break  # 如果已经有headers了，且body也读得差不多了
			break

		var result = client.get_data(available)
		if result[0] != OK:
			break
		var chunk: PackedByteArray = result[1]
		if chunk.size() == 0:
			break

		buffer.append_array(chunk)

		# 检查headers是否完整（支持 \r\n\r\n 或 \n\n）
		if not headers_complete:
			var check_str = buffer.get_string_from_utf8()
			var header_end = check_str.find("\r\n\r\n")
			var header_delim_len = 4
			if header_end < 0:
				header_end = check_str.find("\n\n")
				header_delim_len = 2
			if header_end >= 0:
				var headers_section = check_str.substr(0, header_end)
				content_length = _get_content_length(headers_section)
				headers_complete = true

		# 检查是否读完
		if headers_complete:
			var header_end_pos = buffer.get_string_from_utf8().find("\r\n\r\n")
			var header_delim_len = 4
			if header_end_pos < 0:
				header_end_pos = buffer.get_string_from_utf8().find("\n\n")
				header_delim_len = 2
			if header_end_pos >= 0:
				var body_start = header_end_pos + header_delim_len
				var body_received = buffer.size() - body_start
				if content_length < 0:
					break
				if body_received >= content_length:
					break

	if buffer.size() > 0:
		# 尝试 UTF-8 解码
		request_data = buffer.get_string_from_utf8()
		if request_data.is_empty():
			# UTF-8 解码失败，尝试 ASCII/Latin-1 作为后备
			request_data = buffer.get_string_from_ascii()
		# print("[LocalServer] Request received, size: ", buffer.size(), ", string length: ", request_data.length())

	# 空数据直接关闭连接
	if request_data.is_empty():
		# print("[LocalServer] Empty request, closing connection")
		client.disconnect_from_host()
		return

	# 解析请求
	var parsed = _parse_http_request(request_data)
	if parsed.size() == 0:
		# print("[LocalServer] Failed to parse request: '", request_data.substr(0, min(200, request_data.length())), "'")
		_send_response(client, 400, {"error": "Bad request"})
		client.disconnect_from_host()
		return

	var method = parsed.get("method", "GET")
	var path = parsed.get("path", "/")
	var headers_dict = parsed.get("headers", {})
	var body_content = parsed.get("body", "")

	# print("[LocalServer] ", method, " ", path)

	# 处理请求
	var response = _handle_request(method, path, headers_dict, body_content)

	# 发送响应
	if response.get("is_file", false):
		_send_file_response(client, response.get("code", 200), response.get("content_type", ""), response.get("file_content", PackedByteArray()))
	else:
		_send_response(client, response.get("code", 200), response.get("data", {}), response.get("is_options", false))

	client.disconnect_from_host()



func _get_content_length(headers: String) -> int:
	# 标准化换行符
	var normalized = headers.replace("\r\n", "\n").replace("\r", "\n")
	var lines = normalized.split("\n")
	for line in lines:
		var stripped = line.to_lower().strip_edges()
		if stripped.begins_with("content-length:"):
			var colon_pos = stripped.find(":")
			if colon_pos >= 0:
				var value = stripped.substr(colon_pos + 1).strip_edges()
				# print("[LocalServer] Found Content-Length: ", value)
				return value.to_int()
	# print("[LocalServer] Content-Length not found")
	return -1


func _parse_http_request(data: String) -> Dictionary:
	var result = {
		"method": "GET",
		"path": "/",
		"headers": {},
		"body": ""
	}

	if data.is_empty():
		return {}

	# 标准化换行符（\r\n 或 \n → \r\n）
	var normalized = data.replace("\r\n", "\n").replace("\r", "\n")
	var lines = normalized.split("\n")
	if lines.is_empty():
		return {}

	# 解析请求行
	var request_line = lines[0].split(" ")
	if request_line.size() >= 2:
		result["method"] = request_line[0].strip_edges()
		result["path"] = request_line[1].strip_edges()

	# 解析headers
	var body_start = -1
	for i in range(1, lines.size()):
		var line = lines[i]
		if line.is_empty():
			body_start = i + 1
			break

		var colon_idx = line.find(":")
		if colon_idx > 0:
			var key = line.substr(0, colon_idx).strip_edges()
			var value = line.substr(colon_idx + 1).strip_edges()
			result["headers"][key.to_lower()] = value

	# 解析body - 收集从 body_start 到末尾的所有行
	if body_start >= 0 and body_start < lines.size():
		var body_lines = lines.slice(body_start)
		# 过滤空行并清理
		var cleaned_body = ""
		for i in range(body_lines.size()):
			var line = body_lines[i]
			# 跳过纯空行（但保留实际内容）
			if line.is_empty() and cleaned_body.is_empty():
				continue
			if not cleaned_body.is_empty():
				cleaned_body += "\r\n"
			cleaned_body += line

		# 去除首尾空白
		result["body"] = cleaned_body.strip_edges()
		# print("[LocalServer] Parsed body length: ", result["body"].length())

	return result


func _handle_request(method: String, path: String, headers: Dictionary, body: String) -> Dictionary:
	# 处理 CORS 预检请求
	if method == "OPTIONS":
		return {"code": 200, "data": {}, "is_options": true}

	# API 路由
	if path == "/api/health":
		# 返回版本信息
		var version = "v0.0.0"
		var exe_dir = OS.get_executable_path().get_base_dir()
		if FileAccess.file_exists(exe_dir + "/version.json"):
			var file = FileAccess.open(exe_dir + "/version.json", FileAccess.READ)
			if file:
				var json = JSON.new()
				if json.parse(file.get_as_text()) == OK:
					version = json.data.get("version", version)
				file.close()
		elif FileAccess.file_exists("res://project.godot"):
			# 开发环境：从 project.godot 读取
			var config = ConfigFile.new()
			if config.load("res://project.godot") == OK:
				version = config.get_value("application", "config/version", "v0.0.0")
		return {"code": 200, "data": {"status": "ok", "version": version}}
	elif path == "/api/status":
		return _handle_status(method, headers, body)
	elif path == "/api/download":
		return _handle_download(method, headers, body)
	elif path == "/api/shutdown":
		return _handle_shutdown(method, headers, body)
	# 新增：模组管理 API
	elif path.begins_with("/api/mods"):
		return _handle_mods_routes(method, path, headers, body)
	# 新增：存档管理 API
	elif path.begins_with("/api/saves"):
		return _handle_saves_routes(method, path, headers, body)
	# 新增：整合包 API
	elif path.begins_with("/api/bundles"):
		return _handle_bundles_routes(method, path, headers, body)
	# 新增：设置 API
	elif path.begins_with("/api/settings"):
		return _handle_settings_routes(method, path, headers, body)
	# 新增：下载管理 API
	elif path.begins_with("/api/downloads"):
		return _handle_downloads_routes(method, path, headers, body)
	# 新增：启动游戏 API
	elif path == "/api/launch":
		return _handle_launch(method, headers, body)
	# 新增：更新检查 API
	elif path == "/api/update/check":
		return _handle_update_check(method, headers, body)
	# 新增：更新下载 API
	elif path == "/api/update/download":
		return _handle_update_download(method, headers, body)
	# 静态文件服务
	elif path == "/" or path == "/index.html":
		return _serve_static_file("/index.html")
	elif path.begins_with("/js/") or path.begins_with("/css/") or path.begins_with("/assets/"):
		return _serve_static_file(path)
	else:
		return {"code": 404, "data": {"error": "Not found"}}


func _handle_status(method: String, headers: Dictionary, body: String) -> Dictionary:
	if method != "GET":
		return {"code": 405, "data": {"error": "Method not allowed"}}

	var status = get_status()
	return {"code": 200, "data": status}


func _handle_download(method: String, headers: Dictionary, body: String) -> Dictionary:
	if method != "POST":
		return {"code": 405, "data": {"error": "Method not allowed"}}

	# print("[LocalServer] Download request body: '", body, "'")

	# 解析请求体
	var json = JSON.new()
	var parse_result = json.parse(body)
	if parse_result != OK:
		# print("[LocalServer] JSON parse error: ", parse_result, ", body: '", body, "'")
		return {"code": 400, "data": {"error": "Invalid JSON"}}

	var request_data = json.get_data()
	if typeof(request_data) != TYPE_DICTIONARY:
		# print("[LocalServer] Request data is not a dictionary: ", typeof(request_data))
		return {"code": 400, "data": {"error": "Invalid request body"}}

	# 支持两种命名风格: snake_case (后端标准) 和 camelCase (前端/browser extension)
	var mod_id = request_data.get("mod_id", request_data.get("modId", 0))
	if typeof(mod_id) == TYPE_STRING:
		mod_id = int(mod_id) if mod_id.is_valid_int() else 0

	var mod_name = request_data.get("mod_name", request_data.get("modName", "Unknown"))
	var mod_page_url = request_data.get("mod_page_url", request_data.get("modPageUrl", ""))
	var version = request_data.get("version", request_data.get("version", ""))
	var download_url = request_data.get("download_url", request_data.get("downloadUrl", request_data.get("nxm_url", "")))
	var key = request_data.get("key", request_data.get("key", ""))
	var expires = request_data.get("expires", request_data.get("expires", 0))
	var user_id = request_data.get("user_id", request_data.get("userId", 0))
	var file_id = request_data.get("file_id", request_data.get("fileId", 0))

	# 解析 BrowserHost 发送的 Aria2 信息
	var aria2_gid = request_data.get("aria2_gid", "")
	var download_type = request_data.get("download_type", "")  # "aria2", "error", "fallback", "no-aria2"

	print("[LocalServer] Download request: mod_id=", mod_id, ", name=", mod_name, ", download_type=", download_type, ", aria2_gid=", aria2_gid)

	if mod_id == 0:
		return {"code": 400, "data": {"error": "mod_id is required"}}

	# 增加活跃下载计数
	_mutex.lock()
	_active_downloads += 1
	_mutex.unlock()

	# 异步处理下载（使用信号通知主线程）
	download_request_received.emit({
		"mod_id": mod_id,
		"mod_name": mod_name,
		"mod_page_url": mod_page_url,
		"version": version,
		"download_url": download_url,
		"nxm_url": request_data.get("nxm_url", ""),
		"key": key,
		"expires": expires,
		"user_id": user_id,
		"file_id": file_id,
		"aria2_gid": aria2_gid,
		"download_type": download_type
	})

	# 立即返回accepted状态
	return {
		"code": 202,
		"data": {
			"status": "accepted",
			"message": "Download request received",
			"mod_id": mod_id,
			"mod_name": mod_name
		}
	}


func _handle_shutdown(method: String, headers: Dictionary, body: String) -> Dictionary:
	if method != "POST":
		return {"code": 405, "data": {"error": "Method not allowed"}}

	# print("[LocalServer] Shutdown request received")

	# 延迟关闭服务器（通过call_deferred避免阻塞）
	call_deferred("_deferred_stop")

	return {"code": 200, "data": {"status": "shutdown", "message": "Server stopped"}}


func _deferred_stop() -> void:
	OS.delay_msec(50)
	stop()


func notify_download_complete(success: bool, mod_name: String, error: String = "") -> void:
	_mutex.lock()
	_active_downloads = max(0, _active_downloads - 1)
	if success:
		_installed_mods_count += 1
	_mutex.unlock()

	# if success:
	# 	print("[LocalServer] Download complete: ", mod_name)
	# else:
	# 	print("[LocalServer] Download failed: ", mod_name, " - ", error)


func _send_download_started(mod_id: int, mod_name: String) -> void:
	# print("[LocalServer] Download started: ", mod_name)
	pass


func _send_response(client: StreamPeerTCP, code: int, data: Dictionary, is_options: bool = false) -> void:
	var status_text = ""
	match code:
		200: status_text = "OK"
		202: status_text = "Accepted"
		400: status_text = "Bad Request"
		404: status_text = "Not Found"
		405: status_text = "Method Not Allowed"
		500: status_text = "Internal Server Error"
		_: status_text = "Unknown"

	# 构建响应
	var response = "HTTP/1.1 %d %s\r\n" % [code, status_text]
	response += "Content-Type: application/json\r\n"
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\n"
	response += "Access-Control-Allow-Headers: Content-Type\r\n"

	# CORS 预检请求不需要 body
	if not is_options:
		# 序列化响应数据
		var body_data = JSON.stringify(data)
		var body_bytes = body_data.to_utf8_buffer()
		response += "Content-Length: %d\r\n" % body_bytes.size()
		response += "Connection: close\r\n"
		response += "\r\n"

		# 发送完整响应
		var header_bytes = response.to_utf8_buffer()
		var all_bytes = PackedByteArray(header_bytes) + body_bytes
		var result = client.put_data(all_bytes)
		if result != OK:
			print("[LocalServer] Failed to send response")
	else:
		response += "Content-Length: 0\r\n"
		response += "Connection: close\r\n"
		response += "\r\n"

		var header_bytes = response.to_utf8_buffer()
		var result = client.put_data(header_bytes)
		if result != OK:
			print("[LocalServer] Failed to send OPTIONS response")


func get_active_downloads() -> int:
	_mutex.lock()
	var count = _active_downloads
	_mutex.unlock()
	return count


func get_installed_mods_count() -> int:
	_mutex.lock()
	var count = _installed_mods_count
	_mutex.unlock()
	return count


func set_installed_mods_count(count: int) -> void:
	_mutex.lock()
	_installed_mods_count = count
	_mutex.unlock()


# ════════════════════════════════════════════════════════════════
#  API 桥接辅助
# ════════════════════════════════════════════════════════════════

## 通过桥接向主线程发送请求并等待结果
func _bridge_request(type: String, params: Dictionary = {}) -> Dictionary:
	if _api_bridge == null:
		return {"code": 503, "data": {"error": "Bridge not initialized"}}
	var request_id = type + "_" + str(randi())
	_api_bridge.submit(request_id, type, params)
	return _api_bridge.wait_for_result(request_id)


## 从 JSON body 解析字典
func _parse_body_json(body: String) -> Dictionary:
	if body.is_empty():
		return {}
	var json = JSON.new()
	var err = json.parse(body)
	if err != OK:
		return {}
	var data = json.get_data()
	if typeof(data) == TYPE_DICTIONARY:
		return data
	return {}


## 从路径中提取 ID（/api/mods/{id}/enable → {id}）
func _extract_path_id(path: String, prefix: String) -> String:
	var remainder = path.substr(prefix.length())
	# 去掉开头的 /
	if remainder.begins_with("/"):
		remainder = remainder.substr(1)
	# 取第一个 / 之前的部分
	var slash_idx = remainder.find("/")
	if slash_idx >= 0:
		return remainder.substr(0, slash_idx)
	return remainder


# ════════════════════════════════════════════════════════════════
#  模组管理路由
# ════════════════════════════════════════════════════════════════

func _handle_mods_routes(method: String, path: String, headers: Dictionary, body: String) -> Dictionary:
	# GET /api/mods — 列出所有模组
	if path == "/api/mods" and method == "GET":
		return _bridge_request("scan_mods")

	# POST /api/mods/install — 安装模组 ZIP
	if path == "/api/mods/install" and method == "POST":
		var data = _parse_body_json(body)
		if data.is_empty():
			return {"code": 400, "data": {"error": "Invalid JSON"}}
		return _bridge_request("install_mod", data)

	# POST /api/mods/batch-enable
	if path == "/api/mods/batch-enable" and method == "POST":
		var data = _parse_body_json(body)
		return _bridge_request("batch_enable_mods", data)

	# POST /api/mods/batch-disable
	if path == "/api/mods/batch-disable" and method == "POST":
		var data = _parse_body_json(body)
		return _bridge_request("batch_disable_mods", data)

	# POST /api/mods/resolve-conflicts - 解决版本冲突
	if path == "/api/mods/resolve-conflicts" and method == "POST":
		var data = _parse_body_json(body)
		if data.is_empty():
			return {"code": 400, "data": {"error": "Invalid JSON"}}
		return _bridge_request("resolve_conflicts", data)

	# GET /api/mods/notes — 获取所有模组备注
	if path == "/api/mods/notes" and method == "GET":
		return _bridge_request("get_mod_notes")

	# POST /api/mods/notes — 保存模组备注
	if path == "/api/mods/notes" and method == "POST":
		var data = _parse_body_json(body)
		if data.is_empty():
			return {"code": 400, "data": {"error": "Invalid JSON"}}
		return _bridge_request("save_mod_notes", data)

	# POST /api/mods/save-tag-data — 保存标签数据（含当前标签和所有标签的模组列表）
	if path == "/api/mods/save-tag-data" and method == "POST":
		var data = _parse_body_json(body)
		if data.is_empty():
			return {"code": 400, "data": {"error": "Invalid JSON"}}
		return _bridge_request("save_tag_data", data)

	# POST /api/mods/save-mod-organization — 保存收纳盒子与顺序
	if path == "/api/mods/save-mod-organization" and method == "POST":
		var data = _parse_body_json(body)
		if data.is_empty():
			return {"code": 400, "data": {"error": "Invalid JSON"}}
		return _bridge_request("save_mod_organization", data)

	# GET /api/mods/organization — 获取收纳盒子与顺序
	if path == "/api/mods/organization" and method == "GET":
		return _bridge_request("get_mod_organization")

	# /api/mods/{id} 路径解析
	var mod_id = _extract_path_id(path, "/api/mods")
	if mod_id.is_empty():
		return {"code": 400, "data": {"error": "Missing mod ID"}}

	# 检查子路径
	var remainder = path.substr(("/api/mods/" + mod_id).length())

	if remainder == "/enable" and method == "POST":
		return _bridge_request("toggle_mod", {"mod_id": mod_id, "enable": true})
	elif remainder == "/disable" and method == "POST":
		return _bridge_request("toggle_mod", {"mod_id": mod_id, "enable": false})
	elif remainder == "" and method == "DELETE":
		return _bridge_request("uninstall_mod", {"mod_id": mod_id})
	elif remainder == "" and method == "GET":
		return _bridge_request("get_mod", {"mod_id": mod_id})

	return {"code": 404, "data": {"error": "Unknown mods route"}}


# ════════════════════════════════════════════════════════════════
#  存档管理路由
# ════════════════════════════════════════════════════════════════

func _handle_saves_routes(method: String, path: String, headers: Dictionary, body: String) -> Dictionary:
	# GET /api/saves — 列出所有存档
	if path == "/api/saves" and method == "GET":
		return _bridge_request("scan_saves")

	# POST /api/saves/import
	if path == "/api/saves/import" and method == "POST":
		var data = _parse_body_json(body)
		if data.is_empty():
			return {"code": 400, "data": {"error": "Invalid JSON"}}
		return _bridge_request("import_save", data)

	# POST /api/saves/overwrite
	if path == "/api/saves/overwrite" and method == "POST":
		var data = _parse_body_json(body)
		return _bridge_request("overwrite_save", data)

	# POST /api/saves/sync - 云端同步
	if path == "/api/saves/sync" and method == "POST":
		var data = _parse_body_json(body)
		if data.is_empty():
			return {"code": 400, "data": {"error": "Invalid JSON"}}
		return _bridge_request("sync_cloud", data)

	# /api/saves/{id}/... 路径解析
	var save_id = _extract_path_id(path, "/api/saves")
	if save_id.is_empty():
		return {"code": 400, "data": {"error": "Missing save ID"}}

	var remainder = path.substr(("/api/saves/" + save_id).length())

	if remainder == "/export" and method == "POST":
		var data = _parse_body_json(body)
		var params = {"save_id": save_id}
		if not data.is_empty() and data.has("export_path"):
			params["export_path"] = data.get("export_path", "")
		return _bridge_request("export_save", params)
	elif remainder == "/backup" and method == "POST":
		return _bridge_request("backup_save", {"save_id": save_id})
	elif remainder == "/restore" and method == "POST":
		var data = _parse_body_json(body)
		var params = {"save_id": save_id}
		if not data.is_empty() and data.has("backup_path"):
			params["backup_path"] = data.get("backup_path", "")
		return _bridge_request("restore_save", params)
	elif remainder == "/backups" and method == "GET":
		return _bridge_request("get_save_backups", {"save_id": save_id})
	elif remainder == "/details" and method == "GET":
		return _bridge_request("get_save_details", {"save_id": save_id})
	elif remainder == "" and method == "DELETE":
		return _bridge_request("delete_save", {"save_id": save_id})

	return {"code": 404, "data": {"error": "Unknown saves route"}}


# ════════════════════════════════════════════════════════════════
#  整合包路由
# ════════════════════════════════════════════════════════════════

func _handle_bundles_routes(method: String, path: String, headers: Dictionary, body: String) -> Dictionary:
	print("[_handle_bundles_routes] method=", method, " path=", path)

	# GET /api/bundles — 列出所有整合包
	if path == "/api/bundles" and method == "GET":
		return _bridge_request("scan_bundles")

	# POST /api/bundles/import
	if path == "/api/bundles/import" and method == "POST":
		var data = _parse_body_json(body)
		if data.is_empty():
			return {"code": 400, "data": {"error": "Invalid JSON"}}
		return _bridge_request("import_bundle", data)

	# POST /api/bundles/import-local - 本地文件导入（直接读取本地文件，无 base64）
	if path == "/api/bundles/import-local" and method == "POST":
		print("[_handle_bundles_routes] import-local route matched! body=", body)
		var data = _parse_body_json(body)
		if data.is_empty():
			return {"code": 400, "data": {"error": "Invalid JSON"}}
		var file_path = data.get("file_path", "")
		if file_path.is_empty():
			return {"code": 400, "data": {"error": "Missing file_path"}}
		print("[LocalServer] import_bundle_local: file_path=", file_path)
		return _bridge_request("import_bundle_local", {"file_path": file_path})

	# /api/bundles/{id}/... 路径解析
	var bundle_id = _extract_path_id(path, "/api/bundles")
	# print("[LocalServer] Extracted bundle_id: ", bundle_id)

	if bundle_id.is_empty():
		return {"code": 400, "data": {"error": "Missing bundle ID"}}

	var full_prefix = "/api/bundles/" + bundle_id
	var remainder = path.substr(full_prefix.length())
	# print("[LocalServer] Full path: ", path)
	# print("[LocalServer] Full prefix: ", full_prefix)
	# print("[LocalServer] Path remainder: '", remainder, "' (length: ", remainder.length(), ")")
	# print("[LocalServer] Method: ", method)

	if (remainder == "" or remainder == "/") and method == "DELETE":
		# print("[LocalServer] Calling delete_bundle API for: ", bundle_id)
		var delete_result = _bridge_request("delete_bundle", {"bundle_id": bundle_id})
		# print("[LocalServer] delete_bundle result: ", delete_result)
		return delete_result
	elif remainder == "/enable" and method == "POST":
		# print("[LocalServer] Calling enable_bundle API for: ", bundle_id)
		var data = _parse_body_json(body)
		var params = {"bundle_id": bundle_id}
		if not data.is_empty() and data.has("preset_name"):
			params["preset_name"] = data.get("preset_name", "")
			# print("[LocalServer] Passing preset_name to API: ", data.get("preset_name", ""))
		return _bridge_request("enable_bundle", params)
	elif remainder == "/disable" and method == "POST":
		# print("[LocalServer] Calling disable_bundle API for: ", bundle_id)
		return _bridge_request("disable_bundle", {"bundle_id": bundle_id})
	elif remainder == "" and method == "DELETE":
		# print("[LocalServer] Calling delete_bundle API for: ", bundle_id)
		var delete_result = _bridge_request("delete_bundle", {"bundle_id": bundle_id})
		# print("[LocalServer] delete_bundle result: ", delete_result)
		return delete_result
	# NEW: Save entire bundle data
	elif remainder == "" and method == "PUT":
		var data = _parse_body_json(body)
		if data.is_empty():
			return {"code": 400, "data": {"error": "Invalid JSON"}}
		return _bridge_request("save_bundle", {"bundle_id": bundle_id, "data": data})
	# NEW: Update presets only
	elif remainder == "/presets" and method == "PUT":
		var data = _parse_body_json(body)
		if data.is_empty():
			return {"code": 400, "data": {"error": "Invalid JSON"}}
		return _bridge_request("update_bundle_presets", {"bundle_id": bundle_id, "presets": data.get("presets", {})})
	# NEW: Export bundle to ZIP
	elif remainder == "/export" and method == "POST":
		return _bridge_request("export_bundle", {"bundle_id": bundle_id})
	# NEW: Apply preset to bundle
	elif remainder == "/apply-preset" and method == "POST":
		# print("[LocalServer] Apply preset request: bundle_id=", bundle_id, ", body=", body)
		var data = _parse_body_json(body)
		# print("[LocalServer] Parsed data: ", data)
		return _bridge_request("apply_bundle_preset", {"bundle_id": bundle_id, "preset_name": data.get("preset_name", "")})
	# NEW: Create and export bundle from current mods
	elif path == "/api/bundles/export-current" and method == "POST":
		var data = _parse_body_json(body)
		return _bridge_request("export_current_bundle", data)

	return {"code": 404, "data": {"error": "Unknown bundles route"}}


# ════════════════════════════════════════════════════════════════
#  设置路由
# ════════════════════════════════════════════════════════════════

func _handle_settings_routes(method: String, path: String, headers: Dictionary, body: String) -> Dictionary:
	# GET /api/settings
	if path == "/api/settings" and method == "GET":
		return _bridge_request("get_settings")

	# PUT /api/settings
	if path == "/api/settings" and method == "PUT":
		var data = _parse_body_json(body)
		return _bridge_request("set_settings", data)

	# POST /api/settings/detect-game-path
	if path == "/api/settings/detect-game-path" and method == "POST":
		return _bridge_request("detect_game_path")

	# POST /api/settings/detect-save-path
	if path == "/api/settings/detect-save-path" and method == "POST":
		return _bridge_request("detect_save_path")

	return {"code": 404, "data": {"error": "Unknown settings route"}}


# ════════════════════════════════════════════════════════════════
#  下载管理路由
# ════════════════════════════════════════════════════════════════

func _handle_downloads_routes(method: String, path: String, headers: Dictionary, body: String) -> Dictionary:
	# GET /api/downloads - 获取下载列表
	if path == "/api/downloads" and method == "GET":
		return _bridge_request("get_downloads")

	# POST /api/downloads/{id}/pause - 暂停下载
	if method == "POST" and path.find("/pause") > 0:
		var dl_id = _extract_path_id(path, "/api/downloads")
		if dl_id.is_empty():
			return {"code": 400, "data": {"error": "Missing download ID"}}
		return _bridge_request("pause_download", {"download_id": dl_id})

	# POST /api/downloads/{id}/resume - 恢复下载
	if method == "POST" and path.find("/resume") > 0:
		var dl_id = _extract_path_id(path, "/api/downloads")
		if dl_id.is_empty():
			return {"code": 400, "data": {"error": "Missing download ID"}}
		return _bridge_request("resume_download", {"download_id": dl_id})

	# DELETE /api/downloads/{id} - 取消下载
	if method == "DELETE":
		var dl_id = _extract_path_id(path, "/api/downloads")
		if dl_id.is_empty():
			return {"code": 400, "data": {"error": "Missing download ID"}}
		return _bridge_request("cancel_download", {"download_id": dl_id})

	return {"code": 404, "data": {"error": "Unknown downloads route"}}


# ════════════════════════════════════════════════════════════════
#  启动游戏路由
# ════════════════════════════════════════════════════════════════

func _handle_launch(method: String, headers: Dictionary, body: String) -> Dictionary:
	if method != "POST":
		return {"code": 405, "data": {"error": "Method not allowed"}}

	var data = _parse_body_json(body)
	var mode = data.get("mode", "modded")
	return _bridge_request("launch_game", {"mode": mode})


# ════════════════════════════════════════════════════════════════
#  更新检查路由
# ════════════════════════════════════════════════════════════════

func _handle_update_check(method: String, _headers: Dictionary, _body: String) -> Dictionary:
	if method != "GET":
		return {"code": 405, "data": {"error": "Method not allowed"}}

	# 实际使用：通过 bridge 调用 Godot 的更新检查
	return _bridge_request("check_update")
	# 	"code": 200,
	# 	"data": {
	# 		"has_update": false,
	# 		"current_version": "v2.9.5",
	# 		"message": "已是最新版本"
	# 	}
	# }


# ════════════════════════════════════════════════════════════════
#  更新下载路由
# ════════════════════════════════════════════════════════════════

func _handle_update_download(method: String, _headers: Dictionary, body: String) -> Dictionary:
	if method != "POST":
		return {"code": 405, "data": {"error": "Method not allowed"}}

	var data = _parse_body_json(body)
	var download_url = data.get("download_url", "")
	if download_url.is_empty():
		return {"code": 400, "data": {"error": "download_url is required"}}

	# 通过 bridge 调用 Godot 的更新下载
	return _bridge_request("download_update", {"download_url": download_url})


# ════════════════════════════════════════════════════════════════
#  静态文件服务
# ════════════════════════════════════════════════════════════════

func _get_web_dir() -> String:
	# 编辑器模式：检查项目根目录
	var project_dir = ProjectSettings.globalize_path("res://")
	if DirAccess.dir_exists_absolute(project_dir + "web"):
		return project_dir + "web"
	# 导出模式：检查可执行文件目录
	var exe_dir = OS.get_executable_path().get_base_dir()
	if DirAccess.dir_exists_absolute(exe_dir + "/web"):
		return exe_dir + "/web"
	return ""


func _serve_static_file(path: String) -> Dictionary:
	var base_dir = _get_web_dir()
	if base_dir.is_empty():
		return {"code": 404, "data": {"error": "Web directory not found"}}

	# 安全：防止路径遍历
	path = path.replace("..", "").replace("//", "/")
	if path.begins_with("/"):
		path = path.substr(1)

	var file_path = base_dir.path_join(path)
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {"code": 404, "data": {"error": "File not found: " + path}}

	var content = file.get_buffer(file.get_length())
	file.close()

	var content_type = _get_mime_type(path.get_extension())
	return {
		"code": 200,
		"file_content": content,
		"content_type": content_type,
		"is_file": true
	}


func _get_mime_type(ext: String) -> String:
	match ext:
		"html": return "text/html; charset=utf-8"
		"css": return "text/css; charset=utf-8"
		"js": return "application/javascript; charset=utf-8"
		"json": return "application/json"
		"svg": return "image/svg+xml"
		"png": return "image/png"
		"jpg", "jpeg": return "image/jpeg"
		"ico": return "image/x-icon"
		"gif": return "image/gif"
		"woff", "woff2": return "font/woff2"
		"ttf": return "font/ttf"
		_: return "application/octet-stream"


func _send_file_response(client: StreamPeerTCP, code: int, content_type: String, body_bytes: PackedByteArray) -> void:
	var status_text = "OK" if code == 200 else "Not Found"
	var response = "HTTP/1.1 %d %s\r\n" % [code, status_text]
	response += "Content-Type: %s\r\n" % content_type
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "Content-Length: %d\r\n" % body_bytes.size()
	response += "Connection: close\r\n"
	response += "Cache-Control: no-cache\r\n"
	response += "\r\n"

	var header_bytes = response.to_utf8_buffer()
	var all_bytes = PackedByteArray(header_bytes) + body_bytes
	client.put_data(all_bytes)
