# 自动更新检测功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现客户端自动检测更新功能，支持从 Gitee/GitHub 获取版本信息并下载安装新版本

**Architecture:** 在 utils/ 目录下创建 update_checker.gd 作为核心模块，modmanager.gd 负责调用和 UI 交互，使用 PowerShell 脚本执行文件替换

**Tech Stack:** Godot 4.5.1 + GDScript + PowerShell

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `utils/update_checker.gd` | 新增：版本检查、下载、安装逻辑 |
| `scripts/update-install.ps1` | 新增：安装脚本，执行文件替换 |
| `modmanager.gd` | 修改：添加更新检查调用和 UI |
| `config.cfg` | 修改：添加 current_version 配置节 |

---

### Task 1: 创建 update_checker.gd 工具模块

**Files:**
- Create: `utils/update_checker.gd`

- [ ] **Step 1: 创建 update_checker.gd 文件**

```gdscript
extends Node
class_name UpdateChecker

## 更新源 URL 配置
var gitee_url: String = "https://gitee.com/用户名/仓库/raw/master/version.json"
var github_url: String = "https://raw.githubusercontent.com/用户名/仓库/main/version.json"

## 当前版本（从 config 读取）
var current_version: String = "v0.0.0"

## 可用的新版本信息
var new_version_available: Dictionary = {}

## 下载进度回调
signal download_progress(percent: float)
signal download_complete(save_path: String)
signal download_error(message: String)
signal update_checked(result: Dictionary)

## 超时时间（秒）
var timeout: float = 10.0

func _ready() -> void:
	pass

## 设置更新源 URL
func set_urls(gitee: String, github: String) -> void:
	gitee_url = gitee
	github_url = github

## 设置当前版本
func set_current_version(version: String) -> void:
	current_version = version

## 比较版本号: current vs remote
## 返回: 1=远程更新, -1=当前更新, 0=相同
func compare_versions(current: String, remote: String) -> int:
	var current_ver = current.lstrip("v")
	var remote_ver = remote.lstrip("v")
	
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
		
		if r > c:
			return 1
		elif r < c:
			return -1
	
	return 0

## 从 URL 获取 version.json
func _fetch_version_from_url(url: String) -> Dictionary:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var result = await _make_request(http_request, url)
	remove_child(http_request)
	http_request.free()
	
	return result

## 发起 HTTP 请求
func _make_request(http_request: HTTPRequest, url: String) -> Dictionary:
	var headers = ["User-Agent: STS2-ModManager/2.6.9"]
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	
	if error != OK:
		return {"success": false, "error": "请求失败: " + str(error)}
	
	var response = await http_request.request_completed
	
	var result = response[0]
	var code = response[1]
	var body = response[3]
	
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"success": false, "error": "网络错误: " + str(result)}
	
	if code != 200:
		return {"success": false, "error": "HTTP 错误: " + str(code)}
	
	var json = JSON.new()
	var parse_error = json.parse(body.get_string_from_utf8())
	if parse_error != OK:
		return {"success": false, "error": "JSON 解析失败"}
	
	return {"success": true, "data": json.data}

## 检查更新
## auto_check: 是否是自动检查（自动检查失败不提示，手动检查失败提示用户）
func check_for_updates(auto_check: bool = true) -> void:
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
		update_checked.emit({"success": false, "error": "检查更新失败，请稍后重试"})

## 处理版本响应
func _handle_version_response(data: Dictionary, auto_check: bool) -> void:
	if not data.has("version"):
		if not auto_check:
			update_checked.emit({"success": false, "error": "版本信息格式错误"})
		return
	
	var remote_version = data["version"]
	var cmp = compare_versions(current_version, remote_version)
	
	if cmp > 0:
		# 发现新版本
		new_version_available = data
		update_checked.emit({"success": true, "has_update": true, "data": data})
	elif cmp == 0:
		update_checked.emit({"success": true, "has_update": false, "data": data})
	else:
		# 当前版本更新（理论上不会出现）
		update_checked.emit({"success": true, "has_update": false, "data": data})

## 下载更新文件
func download_update(download_url: String) -> void:
	var temp_dir = OS.get_environment("TEMP")
	var zip_path = temp_dir + "/STS2-ModManager-update.zip"
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var error = http_request.request(download_url, [], HTTPClient.METHOD_GET)
	if error != OK:
		download_error.emit("下载请求失败")
		_remove_http_request(http_request)
		return
	
	var response = await http_request.request_completed
	var result = response[0]
	var code = response[1]
	var body = response[2]
	
	_remove_http_request(http_request)
	
	if result != HTTPRequest.RESULT_SUCCESS:
		download_error.emit("下载失败: " + str(result))
		return
	
	if code != 200:
		download_error.emit("HTTP 错误: " + str(code))
		return
	
	# 保存到文件
	var file = FileAccess.open(zip_path, FileAccess.WRITE)
	if file:
		file.store_buffer(body)
		file.close()
		download_complete.emit(zip_path)
	else:
		download_error.emit("无法保存文件")

## 移除 HTTP 请求
func _remove_http_request(http_request: HTTPRequest) -> void:
	if is_instance_valid(http_request):
		remove_child(http_request)
		http_request.free()

## 创建安装脚本
func create_install_script(extract_dir: String, dest_dir: String) -> String:
	var temp_dir = OS.get_environment("TEMP")
	var script_path = temp_dir + "/update-install.ps1"
	
	var script_content = """
param([string]$SourceDir, [string]$DestDir)

# 等待原程序退出
Start-Sleep -Seconds 3

# 复制新文件
$files = Get-ChildItem -Path $SourceDir -File
foreach ($file in $files) {
    Copy-Item -Path $file.FullName -Destination "$DestDir\\" -Force
}

# 删除 zip 包
$zipPath = "$DestDir\\STS2-ModManager-update.zip"
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}

# 启动新版本
$exePath = Get-ChildItem -Path $DestDir -Filter "*.exe" | Select-Object -First 1
if ($exePath) {
    Start-Process $exePath.FullName
}

# 删除临时目录
Remove-Item -Path $SourceDir -Recurse -Force -ErrorAction SilentlyContinue

# 删除自身
Start-Sleep -Seconds 2
Remove-Item -Path $MyInvocation.InvocationName -Force -ErrorAction SilentlyContinue
"""
	
	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file:
		file.store_string(script_content)
		file.close()
		return script_path
	
	return ""

## 执行更新安装
func execute_update(zip_path: String, dest_dir: String) -> void:
	# 解压 ZIP（使用 Godot 内置 ZipReader）
	var zip_reader = ZipReader.new()
	var error = zip_reader.open(zip_path)
	
	if error != OK:
		download_error.emit("无法解压更新包")
		return
	
	var temp_dir = OS.get_environment("TEMP")
	var extract_dir = temp_dir + "/STS2-ModManager-update"
	
	# 创建解压目录
	var dir = DirAccess.open(temp_dir)
	if dir:
		dir.make_dir(extract_dir)
	
	# 解压所有文件
	var files = zip_reader.get_files()
	for file_path in files:
		var content = zip_reader.read_file(file_path)
		var dest_path = extract_dir + "/" + file_path
		
		# 创建目标目录
		var sub_dir = dest_path.get_base_dir()
		if sub_dir != "":
			var sub_dir_access = DirAccess.open(temp_dir)
			if sub_dir_access:
				sub_dir_access.make_dir_recursive(sub_dir)
		
		# 写入文件
		var out_file = FileAccess.open(dest_path, FileAccess.WRITE)
		if out_file:
			out_file.store_buffer(content)
			out_file.close()
	
	zip_reader.close()
	zip_reader.free()
	
	# 创建安装脚本
	var exe_dir = OS.get_executable_path().get_base_dir()
	var script_path = create_install_script(extract_dir, exe_dir)
	
	if script_path != "":
		# 执行 PowerShell 脚本
		OS.shell_open(script_path)
		
		# 退出当前程序
		get_tree().quit()
	else:
		download_error.emit("无法创建安装脚本")
```

- [ ] **Step 2: 提交更新检查模块**

```bash
git add utils/update_checker.gd
git commit -m "feat: 添加自动更新检查模块 update_checker.gd"
```

---

### Task 2: 创建安装脚本

**Files:**
- Create: `scripts/update-install.ps1`

- [ ] **Step 1: 创建 scripts 目录和安装脚本**

```bash
mkdir -p scripts
```

```powershell
# update-install.ps1
param(
    [string]$SourceDir,
    [string]$DestDir,
    [string]$ZipPath
)

# 等待原程序退出
Start-Sleep -Seconds 3

# 复制新文件
if (Test-Path $SourceDir) {
    $files = Get-ChildItem -Path $SourceDir -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $destFile = Join-Path $DestDir $file.Name
        Copy-Item -Path $file.FullName -Destination $destFile -Force
    }
    
    # 清理临时解压目录
    Remove-Item -Path $SourceDir -Recurse -Force -ErrorAction SilentlyContinue
}

# 删除 zip 包
if (Test-Path $ZipPath) {
    Remove-Item -Path $ZipPath -Force
}

# 启动新版本
$exeFiles = Get-ChildItem -Path $DestDir -Filter "*.exe" -ErrorAction SilentlyContinue
if ($exeFiles) {
    Start-Process $exeFiles[0].FullName
}

# 删除自身
Start-Sleep -Seconds 2
try {
    Remove-Item -Path $MyInvocation.InvocationName -Force -ErrorAction Stop
} catch {
    # 忽略删除失败
}
```

- [ ] **Step 2: 提交安装脚本**

```bash
git add scripts/update-install.ps1
git commit -m "feat: 添加更新安装 PowerShell 脚本"
```

---

### Task 3: 修改 modmanager.gd 添加更新检查功能

**Files:**
- Modify: `modmanager.gd`

- [ ] **Step 1: 添加 UpdateChecker 变量和初始化代码**

在 `modmanager.gd` 顶部变量声明区域添加：
```gdscript
# 更新检查器
var update_checker: UpdateChecker = null
var update_check_url_gitee: String = "https://gitee.com/chenyong724/sts2-modmanager/raw/master/version.json"
var update_check_url_github: String = "https://raw.githubusercontent.com/chenyong724/sts2-modmanager/main/version.json"
var pending_update_info: Dictionary = {}
```

- [ ] **Step 2: 在 _ready() 中初始化更新检查器并启动检查**

在 `_ready()` 函数末尾添加（延迟 2 秒后检查）：
```gdscript
# 初始化更新检查器
_update_checker_init()

# 延迟检查更新（启动后 2 秒）
await get_tree().create_timer(2.0).timeout
_check_for_updates(true)
```

添加 `_update_checker_init()` 函数：
```gdscript
func _update_checker_init() -> void:
	update_checker = UpdateChecker.new()
	add_child(update_checker)
	update_checker.set_urls(update_check_url_gitee, update_check_url_github)
	
	# 读取当前版本
	var current_ver = config.get_value("current_version", "version", "v2.6.9")
	update_checker.set_current_version(current_ver)
	
	# 连接信号
	update_checker.update_checked.connect(_on_update_checked)
	update_checker.download_progress.connect(_on_download_progress)
	update_checker.download_complete.connect(_on_download_complete)
	update_checker.download_error.connect(_on_download_error)
```

- [ ] **Step 3: 添加 _check_for_updates 函数**

```gdscript
func _check_for_updates(auto_check: bool) -> void:
	if update_checker:
		update_checker.check_for_updates(auto_check)
```

- [ ] **Step 4: 添加更新检查回调函数**

```gdscript
func _on_update_checked(result: Dictionary) -> void:
	if not result.get("success", false):
		# 检查失败
		return
	
	if result.get("has_update", false):
		# 发现新版本
		pending_update_info = result.get("data", {})
		var new_version = pending_update_info.get("version", "")
		var changelog = pending_update_info.get("changelog", "")
		
		# 显示通知气泡
		notification_message = "发现新版本 " + new_version + "，点击更新"
		notification_click_action = "show_update_dialog"
		_show_notification_panel()
```

- [ ] **Step 5: 添加设置界面的检查更新按钮**

在设置界面构建函数中找到合适位置，添加按钮：
```gdscript
# 检查更新按钮
var update_btn = Button.new()
update_btn.text = "检查更新"
update_btn.pressed.connect(_on_check_update_pressed)
settings_vbox.add_child(update_btn)

# 当前版本显示
var version_label = Label.new()
version_label.text = "当前版本: " + config.get_value("current_version", "version", "v2.6.9")
settings_vbox.add_child(version_label)
```

添加按钮回调：
```gdscript
func _on_check_update_pressed() -> void:
	_check_for_updates(false)
	notification_message = "正在检查更新..."
	_show_notification_panel()
```

- [ ] **Step 6: 添加更新确认对话框**

```gdscript
func _show_update_dialog() -> void:
	if pending_update_info.is_empty():
		return
	
	var new_version = pending_update_info.get("version", "")
	var current_version = config.get_value("current_version", "version", "v2.6.9")
	var changelog = pending_update_info.get("changelog", "")
	
	# 创建确认对话框
	var dialog = AcceptDialog.new()
	dialog.title = "发现新版本"
	dialog.ok_button_text = "立即更新"
	dialog.cancel_button_text = "稍后提醒"
	
	# 构建内容
	var content = "当前版本: " + current_version + "\n"
	content += "新版本: " + new_version + "\n\n"
	if changelog != "":
		content += "更新内容:\n" + changelog
	
	var label = Label.new()
	label.text = content
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	dialog.add_child(label)
	add_child(dialog)
	
	dialog.popup_centered(Vector2(400, 300))
	
	# 连接信号
	dialog.confirmed.connect(_on_update_confirmed)
	dialog.canceled.connect(_on_update_canceled)

func _on_update_confirmed() -> void:
	# 开始下载
	var download_url = pending_update_info.get("download_url", "")
	if download_url != "" and update_checker:
		notification_message = "正在下载更新..."
		_show_notification_panel()
		update_checker.download_update(download_url)

func _on_update_canceled() -> void:
	pending_update_info = {}

func _on_download_progress(percent: float) -> void:
	notification_message = "正在下载更新... " + str(round(percent * 100)) + "%"
	_show_notification_panel()

func _on_download_complete(zip_path: String) -> void:
	# 执行更新
	var exe_dir = OS.get_executable_path().get_base_dir()
	update_checker.execute_update(zip_path, exe_dir)

func _on_download_error(message: String) -> void:
	notification_message = "下载失败: " + message
	_show_notification_panel()
```

- [ ] **Step 7: 提交 modmanager.gd 修改**

```bash
git add modmanager.gd
git commit -m "feat: 添加自动更新检查功能"
```

---

### Task 4: 更新配置文件

**Files:**
- Modify: `config.cfg`

- [ ] **Step 1: 添加 current_version 配置节**

在 config.cfg 末尾添加：
```ini
[current_version]
version=v2.6.9
```

- [ ] **Step 2: 提交配置更改**

```bash
git add config.cfg
git commit -m "chore: 添加当前版本配置 current_version"
```

---

### Task 5: 测试与验证

- [ ] **Step 1: 在 Godot 编辑器中运行项目**

检查是否有编译错误

- [ ] **Step 2: 模拟测试版本检查**

修改 version.json 模拟新版本，验证通知气泡显示

- [ ] **Step 3: 测试手动检查更新按钮**

在设置页面点击按钮，验证响应

- [ ] **Step 4: 测试完整更新流程（可选）**

如果有测试版本，可以测试下载和安装

- [ ] **Step 5: 提交最终版本更新**

更新 config.cfg 中的版本号为 v2.7.0
```bash
git add config.cfg
git commit -m "release: v2.7.0 - 自动更新功能"
```

---

## 验收标准检查

1. **启动检查**: 启动后 2 秒自动检查更新
2. **手动检查**: 设置页面按钮可触发检查
3. **版本比较**: 正确识别 v2.6.9 < v2.7.0
4. **源切换**: Gitee 失败时自动尝试 GitHub
5. **通知气泡**: 发现新版本时显示通知
6. **下载安装**: 可下载并执行安装脚本
7. **无网络**: 无网络时不影响正常启动