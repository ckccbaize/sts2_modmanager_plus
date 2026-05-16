# NXM 协议注册实现规划

## 目标
注册 Windows 系统级 `nxm://` 协议处理器，使得点击 Nexus Mods 的 "Mod Manager Download" 按钮时，自动唤醒 STS2 Mod Manager 并传递下载参数。

## 核心流程

### 1. 注册表结构
```
HKEY_CLASSES_ROOT\nxm
  (默认) = "URL:NXM Protocol"
  URL Protocol = ""
  DefaultIcon
    (默认) = "C:\Path\To\sts2-modmanager.exe,0"
  shell\open\command
    (默认) = "C:\Path\To\sts2-modmanager.exe" --nxm "%1"
```

### 2. 实现步骤

#### Step 1: 注册表操作（C# 或 Godot GDScript）
- **权限要求**：需要管理员权限才能写入 `HKEY_CLASSES_ROOT`
- **实现方式**：
  - 方案A：在 BrowserHost.exe 中添加注册逻辑
  - 方案B：在 Godot 启动时检查注册，如未注册则提示用户以管理员身份运行一次
  - 方案C：提供独立注册工具（推荐）

```csharp
// C# 示例
using Microsoft.Win32;

public static void RegisterNxmProtocol(string exePath)
{
    RegistryKey key = Registry.ClassesRoot.CreateSubKey("nxm");
    key.SetValue("", "URL:NXM Protocol");
    key.SetValue("URL Protocol", "");
    
    RegistryKey iconKey = key.CreateSubKey("DefaultIcon");
    iconKey.SetValue("", $"\"{exePath}\",0");
    
    RegistryKey cmdKey = key.CreateSubKey("shell\\open\\command");
    cmdKey.SetValue("", $"\"{exePath}\" --nxm \"%1\"");
}
```

#### Step 2: Godot 命令行解析
在 `modmanager.gd` 的 `_ready()` 或启动流程中添加：

```gdscript
func _ready():
    # 检查命令行参数
    var args = OS.get_cmdline_args()
    var nxm_url = null
    
    for i in range(args.size()):
        if args[i] == "--nxm" and i + 1 < args.size():
            nxm_url = args[i + 1]
            break
    
    if nxm_url:
        print("[NXM] Received URL: " + nxm_url)
        handle_nxm_url(nxm_url)
        # 可选：自动切换到下载页面
```

#### Step 3: NXM URL 解析
```gdscript
func handle_nxm_url(url: String):
    # URL 格式: nxm://slaythespire2/mods/{mod_id}/files/{file_id}?key=xxx&expires=xxx&user_id=xxx
    
    var regex = RegEx.new()
    regex.compile("nxm://slaythespire2/mods/(\\d+)/files/(\\d+).*key=([^&]+).*expires=([^&]+).*user_id=([^&]+)")
    
    var result = regex.search(url)
    if result:
        var mod_id = result.get_string(1)
        var file_id = result.get_string(2)
        var key = result.get_string(3)
        var expires = result.get_string(4)
        var user_id = result.get_string(5)
        
        # 调用后端 API 获取下载直链
        fetch_download_url(mod_id, file_id, key, expires, user_id)
```

#### Step 4: 调用 Nexus API 获取下载直链
```gdscript
func fetch_download_url(mod_id: String, file_id: String, key: String, expires: String, user_id: String):
    # 使用 Nexus API 获取下载链接
    # POST /api/download 或 GET /api/mods/{mod_id}/files/{file_id}/download_link
    
    var api_key = Settings.get_nexus_api_key()  # 需要存储用户的 Nexus API Key
    
    # 构建请求
    var url = "https://api.nexusmods.com/v1/games/slaythespire2/mods/{mod_id}/files/{file_id}/download_link.json"
    url = url.format({"mod_id": mod_id, "file_id": file_id})
    
    # 添加 Headers
    var headers = [
        "apikey: " + api_key,
        "Accept: application/json"
    ]
    
    # 发送 HTTP 请求获取下载链接
    # 返回格式包含 CDN 直链
```

#### Step 5: 添加下载任务
获取到直链后，调用现有的下载管理器：
```gdscript
func start_nxm_download(cdn_url: String, mod_name: String, file_name: String):
    # 复用现有的下载管理逻辑
    # 添加到 download_queue
    # 显示通知："已开始下载 mod_name"
```

### 3. 与现有架构集成

**复用的组件：**
1. `downloads.gd` - 现有的下载管理模块
2. `api.gd` - HTTP 请求封装
3. `notifications.gd` - 显示下载开始通知

**新增内容：**
1. 注册表注册功能
2. 命令行参数解析
3. NXM URL 解析器
4. Nexus API 下载链接获取

### 4. 注册流程 UX

```
首次启动检测：
  ↓
检查 nxm 协议是否已注册
  ↓
否 → 显示弹窗：
       "是否注册 nxm:// 协议？
        这将允许您在浏览器中直接点击下载按钮"
       [立即注册] [稍后]
  ↓
点击 [立即注册] → 请求管理员权限 → 写入注册表
  ↓
注册成功提示
```

### 5. 测试清单

- [ ] 运行注册功能后，注册表正确写入
- [ ] 在浏览器点击 "Mod Manager Download" 按钮
- [ ] STS2 Mod Manager 被唤醒（或已运行则切换到前台）
- [ ] URL 正确传递给 Godot
- [ ] Nexus API 调用成功（需要有效的 API Key）
- [ ] 下载任务正确添加到下载列表
- [ ] 通知显示下载已开始

### 6. 注意事项

1. **与 Vortex/MO2 的冲突**：
   - 如果用户已安装其他模组管理器，nxm 协议会被覆盖
   - 方案：提供"设为默认管理器"按钮，让用户手动选择

2. **路径问题**：
   - 确保 exe 路径是稳定路径（建议从 Godot 通过 `OS.get_executable_path()` 获取）

3. **卸载清理**：
   - 提供卸载时清理注册表的功能

4. **API Key 配置**：
   - 需要用户在设置中配置 Nexus API Key
   - 没有 API Key 无法获取下载直链

---

## 实现优先级

1. **P0** - 命令行参数解析 + NXM URL 解析
2. **P1** - Nexus API 调用获取下载链接
3. **P2** - 注册表注册功能
4. **P3** - UX 优化（弹窗提示等）
