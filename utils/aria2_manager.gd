extends RefCounted
class_name Aria2Manager

# Aria2 RPC 管理器 - 通过 HTTP 调用 Aria2 RPC 接口

const RPC_URL = "http://localhost:6800/jsonrpc"
const RPC_TOKEN = "sts2-mod-manager"

var _aria2_process: Process = null
var _is_running: bool = false

signal download_complete(gid: String, file_path: String)
signal download_error(gid: String, error: String)
signal download_progress(gid: String, progress: int, speed: int)

# ── 进程管理 ─────────────────────────────────────────────────

func start(aria2_path: String = "aria2c.exe") -> bool:
	"""启动 Aria2 RPC 服务器"""
	if _is_running:
		return true

	# 构建启动参数
	var args = [
		"--enable-rpc",
		"--rpc-listen-all",
		"--rpc-listen-port=6800",
		"--continue=true",
		"--split=16",
		"--max-connection-per-server=16",
		"--min-split-size=10M",
		"--disk-cache=32M"
	]

	_aria2_process = OS.execute(aria2_path, args, [], false)
	_is_running = true

	print("[Aria2Manager] Aria2 started on port 6800")

	# 启动进度监控
	_start_progress_monitor()

	return true


func stop() -> void:
	"""停止 Aria2"""
	_is_running = false
	if _aria2_process != null:
		# 发送关闭命令
		await _rpc_call("aria2.pauseAll")
		OS.delay_msec(500)
		_ria2_process = null
	print("[Aria2Manager] Aria2 stopped")


# ── RPC 调用 ─────────────────────────────────────────────────

func add_uri(url: String, save_dir: String = "", options: Dictionary = {}) -> String:
	"""添加下载任务"""
	var params = [
		"token:" + RPC_TOKEN,
		[url],
		options
	]

	if not save_dir.is_empty():
		params[2]["dir"] = save_dir

	var result = await _rpc_call("aria2.addUri", params)
	if result and result.has("result"):
		return result["result"]
	return ""


func pause(gid: String) -> bool:
	"""暂停下载"""
	var result = await _rpc_call("aria2.pause", ["token:" + RPC_TOKEN, gid])
	return result != null


func unpause(gid: String) -> bool:
	"""恢复下载"""
	var result = await _rpc_call("aria2.unpause", ["token:" + RPC_TOKEN, gid])
	return result != null


func remove(gid: String) -> bool:
	"""取消下载"""
	var result = await _rpc_call("aria2.remove", ["token:" + RPC_TOKEN, gid])
	return result != null


func get_status(gid: String) -> Dictionary:
	"""获取下载状态"""
	var params = [
		"token:" + RPC_TOKEN,
		gid,
		["status", "totalLength", "completedLength", "downloadSpeed", "files"]
	]

	var result = await _rpc_call("aria2.tellStatus", params)
	if result and result.has("result"):
		return result["result"]
	return {}


func get_active_downloads() -> Array:
	"""获取所有活跃下载"""
	var params = [
		"token:" + RPC_TOKEN,
		["status", "totalLength", "completedLength", "downloadSpeed", "files"]
	]

	var result = await _rpc_call("aria2.tellActive", params)
	if result and result.has("result"):
		return result["result"]
	return []


func set_global_options(options: Dictionary) -> bool:
	"""设置全局选项"""
	var params = ["token:" + RPC_TOKEN, options]
	var result = await _rpc_call("aria2.setGlobalOptions", params)
	return result != null


func get_global_options() -> Dictionary:
	"""获取全局选项"""
	var result = await _rpc_call("aria2.getGlobalOptions", ["token:" + RPC_TOKEN])
	if result and result.has("result"):
		return result["result"]
	return {}


# ── 内部方法 ─────────────────────────────────────────────────

func _rpc_call(method: String, params: Array = []) -> Dictionary:
	"""发送 RPC 请求"""
	var payload = {
		"jsonrpc": "2.0",
		"id": str(Time.get_unix_time_from_system()) + "_" + str(randi()),
		"method": method,
		"params": params
	}

	var json_str = JSON.stringify(payload)

	# 使用 HTTP 请求（需要实现 HTTPClient）
	# 这里暂时用占位符，实际需要使用 Godot 的 HTTPClient
	print("[Aria2Manager] RPC call: ", method)

	return {}


func _start_progress_monitor() -> void:
	"""启动进度监控定时器"""
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = false
	timer.timeout.connect(_on_progress_timer)
	add_child(timer)
	timer.start()


func _on_progress_timer() -> void:
	"""定时检查下载进度"""
	if not _is_running:
		return

	var active = await get_active_downloads()
	for dl in active:
		var gid = dl.get("gid", "")
		var total = dl.get("totalLength", "").to_int()
		var completed = dl.get("completedLength", "").to_int()
		var speed = dl.get("downloadSpeed", "").to_int()

		var progress = 0
		if total > 0:
			progress = (completed * 100) / total

		download_progress.emit(gid, progress, speed)

		# 检查完成状态
		var status = dl.get("status", "")
		if status == "complete":
			var files = dl.get("files", [])
			var path = ""
			if files.size() > 0:
				path = files[0].get("path", "")
			download_complete.emit(gid, path)
		elif status == "error":
			download_error.emit(gid, "Download failed")


# ── 配置方法 ─────────────────────────────────────────────────

func set_max_connections(count: int) -> void:
	"""设置单文件最大连接数"""
	await set_global_options({"max-connection-per-server": str(count)})


func set_max_concurrent(count: int) -> void:
	"""设置全局最大并发数"""
	await set_global_options({"max-concurrent-downloads": str(count)})


func set_download_speed_limit(kbps: int) -> void:
	"""设置下载速度限制（KB/s，0 = 无限制）"""
	await set_global_options({"max-download-limit": str(kbps) + "K"})