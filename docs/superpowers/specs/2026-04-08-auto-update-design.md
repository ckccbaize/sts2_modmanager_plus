# 自动更新检测功能设计

**Date:** 2026-04-08
**Topic:** 自动更新检测功能

## 1. 需求概述

实现客户端自动检测更新功能：
- 通过 GitHub 和 Gitee 获取版本信息
- 检测到新版本后下载并自动安装
- 支持启动时自动检查和手动检查两种方式

## 2. 版本与配置

### 当前版本
- **当前版本**: v2.6.9
- **目标版本**: v2.7.0

### version.json 格式（Gitee 优先）
```json
{
  "version": "v2.7.0",
  "download_url": "https://gitee.com/xxx/sts2-modmanager/releases/download/v2.7.0/STS2-ModManager-v2.7.0-windows.zip",
  "changelog": "新增自动更新功能\n修复了xxx问题",
  "released_at": "2026-04-08"
}
```

### config.cfg 配置项
```ini
[current_version]
version=v2.6.9
```

### 备选源（GitHub）
```json
{
  "version": "v2.7.0",
  "download_url": "https://github.com/xxx/sts2-modmanager/releases/download/v2.7.0/STS2-ModManager-v2.7.0-windows.zip",
  "changelog": "...",
  "released_at": "2026-04-08"
}
```

## 3. 更新源 URL

| 源 | URL |
|----|-----|
| Gitee | `https://gitee.com/用户名/仓库/raw/master/version.json` |
| GitHub | `https://raw.githubusercontent.com/用户名/仓库/main/version.json` |

## 4. 版本号比较算法

```gdscript
func compare_versions(current: String, remote: String) -> int:
    # 去除 "v" 前缀
    var current_ver = current.lstrip("v")
    var remote_ver = remote.lstrip("v")

    # 分割版本号
    var current_parts = current_ver.split(".")
    var remote_parts = remote_ver.split(".")

    # 逐级比较
    for i in range(max(current_parts.size(), remote_parts.size())):
        var c = current_parts[i].to_int() if i < current_parts.size() else 0
        var r = remote_parts[i].to_int() if i < remote_parts.size() else 0
        if r > c: return 1   # 有新版本
        if r < c: return -1 # 版本更老

    return 0  # 版本相同
```

## 5. 核心流程

### 5.1 启动时检查流程
```
_modmanager._ready()
  → 加载 config.cfg
  → 读取 current_version.version
  → 延迟 2 秒后调用 _check_for_updates(auto_check=true)
```

### 5.2 手动检查流程
```
用户点击「检查更新」按钮
  → 调用 _check_for_updates(auto_check=false)
```

### 5.3 检查更新函数
```gdscript
func _check_for_updates(auto_check: bool) -> void:
    # 1. 先尝试 Gitee
    var result = await _fetch_version_from_url(gitee_url)
    if result.success:
        _handle_version_response(result.data, auto_check)
        return

    # 2. Gitee 失败，fallback 到 GitHub
    result = await _fetch_version_from_url(github_url)
    if result.success:
        _handle_version_response(result.data, auto_check)
        return

    # 3. 全部失败
    if not auto_check:
        _show_notification("检查更新失败，请稍后重试")
```

### 5.4 版本响应处理
```gdscript
func _handle_version_response(data: Dictionary, auto_check: bool) -> void:
    var remote_version = data.get("version", "")
    var current_version = config.get_value("current_version", "version", "v0.0.0")

    if compare_versions(current_version, remote_version) > 0:
        # 发现新版本
        new_version_available = data
        if auto_check:
            # 启动时检查：静默显示通知气泡
            _show_update_notification(data)
        else:
            # 手动检查：显示确认对话框
            _show_update_confirm_dialog(data)
```

## 6. 下载与安装流程

### 6.1 用户确认更新
```
用户点击通知/对话框「立即更新」
  → 显示下载进度
  → 调用 _download_and_install_update()
```

### 6.2 下载并安装
```gdscript
func _download_and_install_update() -> void:
    var download_url = new_version_available.get("download_url", "")
    var temp_dir = OS.get_temp_dir()

    # 1. 下载 ZIP 到临时目录
    var zip_path = temp_dir + "/STS2-ModManager-update.zip"
    await _download_file(download_url, zip_path, _on_download_progress)

    # 2. 解压到临时目录
    var extract_dir = temp_dir + "/STS2-ModManager-update/"
    _extract_zip(zip_path, extract_dir)

    # 3. 创建安装脚本
    var install_script = _create_install_script(extract_dir, temp_dir)

    # 4. 打开安装脚本（用户确认执行）
    OS.shell_open(install_script)

    # 5. 退出当前程序
    get_tree().quit()
```

### 6.3 安装脚本 (PowerShell)
```powershell
# update-install.ps1
param([string]$SourceDir, [string]$DestDir)

# 等待原程序退出
Start-Sleep -Seconds 2

# 复制新文件
Copy-Item -Path "$SourceDir\*" -Destination "$DestDir\" -Recurse -Force

# 清理临时文件
Remove-Item -Path "$SourceDir" -Recurse -Force
Remove-Item -Path "$DestDir\STS2-ModManager-update.zip" -Force

# 启动新版本
Start-Process "$DestDir\STS2-ModManager.exe"

# 删除自身
Remove-Item -Path $MyInvocation.InvocationName -Force
```

## 7. UI 设计

### 7.1 通知气泡
- 右下角显示非阻塞通知
- 内容: 「发现新版本 v2.7.0，点击更新」
- 点击后显示确认对话框

### 7.2 确认对话框
```
┌─────────────────────────────────┐
│  发现新版本                      │
│  ─────────────────────────────  │
│  当前版本: v2.6.9                │
│  新版本:   v2.7.0               │
│                                 │
│  更新内容:                       │
│  - 新增自动更新功能              │
│  - 修复了xxx问题                 │
│                                 │
│  [稍后提醒]    [立即更新]        │
└─────────────────────────────────┘
```

### 7.3 下载进度
- 模态窗口显示进度条
- 显示: 「正在下载更新... 50%」

### 7.4 设置界面按钮
- 在设置页面添加「检查更新」按钮
- 按钮下方显示: 「当前版本: v2.6.9」

## 8. 数据结构

### UpdateInfo (Dictionary)
```gdscript
{
    "version": "v2.7.0",
    "download_url": "https://...",
    "changelog": "...",
    "released_at": "2026-04-08"
}
```

### HTTP 请求结果
```gdscript
{
    "success": true,
    "data": {},  # JSON 解析后的字典
    "error": ""  # 错误信息（失败时）
}
```

## 9. 错误处理

| 场景 | 处理 |
|------|------|
| 网络请求超时 (10秒) | 显示错误通知，手动检查时提示 |
| Gitee 请求失败 | 自动尝试 GitHub |
| GitHub 也失败 | 手动检查时提示失败，启动时静默 |
| 下载失败 | 显示错误通知，保留重试机会 |
| 解压失败 | 清理临时文件，显示错误 |
| 安装脚本执行失败 | 提示用户手动更新 |

## 10. 文件变更

### 新增文件
- `utils/update_checker.gd` - 更新检查核心逻辑
- `scripts/update-install.ps1` - 安装脚本

### 修改文件
- `modmanager.gd` - 添加更新检查调用
- `config.cfg` - 添加 current_version 配置
- 设置界面 - 添加「检查更新」按钮和版本显示

## 11. 验收标准

1. **启动检查**: 启动后 2 秒自动检查更新，失败时不阻塞用户
2. **手动检查**: 设置页面按钮可触发检查，显示结果通知
3. **版本比较**: 正确识别 v2.6.9 < v2.7.0
4. **源切换**: Gitee 失败时自动尝试 GitHub
5. **下载安装**: 下载完成并安装后版本更新为 v2.7.0
6. **版本记录**: 更新后 config.cfg 中 version 正确更新
7. **无网络**: 无网络时不影响正常启动