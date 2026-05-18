extends RefCounted
class_name Aria2Manager

# Aria2 RPC 管理器 - 占位符
# 注意：实际 Aria2 控制由 BrowserHost (C#) 处理
# 此文件仅用于保持 Godot 项目结构完整

const RPC_URL = "http://localhost:6800/jsonrpc"
const RPC_TOKEN = "sts2-mod-manager"

# 注意：Godot 不直接控制 Aria2 进程
# Aria2 由 BrowserHost 通过 Host Objects 控制
# WebUI 通过 chrome.webview.hostObjects.browserHost.aria2Manager 调用

# ── 进程管理（占位符）────────────────────────────────────────

func start(aria2_path: String = "aria2c.exe") -> bool:
	"""启动 Aria2 RPC 服务器（由 BrowserHost 控制）"""
	# BrowserHost 会在 WebUI 初始化时启动 Aria2
	# 此方法仅作为 API 兼容占位符
	print("[Aria2Manager] Godot 占位符：实际由 BrowserHost 控制 Aria2")
	return true


func stop() -> void:
	"""停止 Aria2（由 BrowserHost 控制）"""
	print("[Aria2Manager] Godot 占位符：停止请求已转发到 BrowserHost")


# ── RPC 调用（占位符）────────────────────────────────────────

func add_uri(url: String, save_dir: String = "", options: Dictionary = {}) -> String:
	"""添加下载任务（由 BrowserHost 处理）"""
	# WebUI 直接调用 Aria2，不需要通过 Godot
	print("[Aria2Manager] Godot 占位符：请使用 WebUI 的 Aria2 接口")
	return ""


func pause(gid: String) -> bool:
	"""暂停下载"""
	return false


func unpause(gid: String) -> bool:
	"""恢复下载"""
	return false


func remove(gid: String) -> bool:
	"""取消下载"""
	return false


func get_status(gid: String) -> Dictionary:
	"""获取下载状态"""
	return {}


func get_active_downloads() -> Array:
	"""获取所有活跃下载"""
	return []


func set_global_options(options: Dictionary) -> bool:
	"""设置全局选项"""
	return false


func get_global_options() -> Dictionary:
	"""获取全局选项"""
	return {}


# ── 配置方法 ─────────────────────────────────────────────────

func set_max_connections(count: int) -> void:
	"""设置单文件最大连接数"""
	pass


func set_max_concurrent(count: int) -> void:
	"""设置全局最大并发数"""
	pass


func set_download_speed_limit(kbps: int) -> void:
	"""设置下载速度限制"""
	pass