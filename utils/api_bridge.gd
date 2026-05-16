extends RefCounted
class_name ApiBridge

## 线程桥接器 - 用于将HTTP服务器线程的请求安全地转发到主线程处理
##
## 服务器线程调用 submit() 提交请求，然后 wait_for_result() 阻塞等待。
## 主线程每帧调用 process_pending() 取出请求，执行后存储结果。
## 服务器线程收到结果后继续发送HTTP响应。

var _mutex: Mutex = Mutex.new()
var _queue: Array = []  # Array of Dictionary: {id, type, params}
var _results: Dictionary = {}  # request_id -> Dictionary result
var _pending: Dictionary = {}  # request_id -> bool (async operations waiting for signal)
var _handler: Callable = Callable()  # 主线程处理函数

## 设置请求处理函数（由 modmanager.gd 注入）
func set_handler(handler: Callable) -> void:
	_handler = handler

## 信号回调调用：写入异步操作的结果
func set_result(request_id: String, result: Dictionary) -> void:
	_mutex.lock()
	_results[request_id] = result
	_pending.erase(request_id)
	_mutex.unlock()

## 服务器线程调用：提交请求到队列
func submit(request_id: String, type: String, params: Dictionary = {}) -> void:
	_mutex.lock()
	_queue.append({
		"id": request_id,
		"type": type,
		"params": params
	})
	_mutex.unlock()

## 服务器线程调用：阻塞等待结果（带超时）
## 返回: {code: int, data: Dictionary}
func wait_for_result(request_id: String, timeout_ms: int = 10000) -> Dictionary:
	var start_time = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_time < timeout_ms:
		_mutex.lock()
		if _results.has(request_id):
			var result = _results[request_id]
			_results.erase(request_id)
			_mutex.unlock()
			return result
		_mutex.unlock()
		OS.delay_usec(500)  # 0.5ms 间隔检查

	# 超时
	return {"code": 504, "data": {"error": "Request timed out"}}

## 非阻塞查询结果（用于轮询）
func poll_result(request_id: String) -> Dictionary:
	_mutex.lock()
	if _results.has(request_id):
		var result = _results[request_id]
		_results.erase(request_id)
		_mutex.unlock()
		return result
	_mutex.unlock()
	return {}

## 主线程调用：处理队列中的所有待处理请求
func process_pending() -> void:
	if _handler.is_null():
		return

	var pending: Array = []
	_mutex.lock()
	pending = _queue.duplicate()
	_queue.clear()
	_mutex.unlock()

	for request in pending:
		var request_id: String = request.get("id", "")
		var type: String = request.get("type", "")
		var params: Dictionary = request.get("params", {})

		var result: Dictionary = {}
		# 在主线程上调用处理函数，传入 request_id
		if _handler.is_valid():
			result = _handler.call(type, params, request_id)
		else:
			result = {"code": 503, "data": {"error": "Handler not available"}}

		# 如果返回空字典，说明是异步操作（如 select_directory），等待信号回调写入结果
		if result.is_empty():
			_mutex.lock()
			_pending[request_id] = true  # 标记为等待中
			_mutex.unlock()
			continue

		# 写入结果
		_mutex.lock()
		_results[request_id] = result
		_mutex.unlock()
