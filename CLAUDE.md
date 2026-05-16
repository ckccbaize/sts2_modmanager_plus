# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A graphical mod manager for Slay the Spire 2 (杀戮尖塔2), built entirely with Godot 4.5.1 and GDScript. Windows-only desktop application.

## Running the Project

- **Open in editor**: Launch Godot 4.5.1+ and open `project.godot`
- **Run**: Press F5 in the Godot editor, or from CLI: `godot --path . --headless`
- **Export**: Use Godot's built-in export system (Project > Export)

There is no test framework or linter currently configured. GDScript static analysis is available inline in the Godot editor.

## Architecture

**Single-scene, MVC-adjacent layout:**

- `modmanager.gd` / `modmanager.tscn` — Root `Control` node. Owns all app state (`mods[]`, `enabled_mods{}`, `mod_items{}`, paths, language). On `_ready()`: loads config → loads locale → initializes UI → loads mods. Has a custom `translate(key)` method that reads from `locales/*.json`.
- `ui/` — Stateless UI widgets that fire callbacks back to the main controller:
  - `mod_item.gd/.tscn` — List row for one mod; fires `on_toggled_callback`, `on_selected_callback`
  - `mod_details.gd/.tscn` — Detail panel for selected mod
  - `save_item.gd/.tscn` — List row for save files (stub)
- `utils/` — Static-function utility modules (no state):
  - `file_utils.gd` — Low-level filesystem ops (copy/delete/move dirs, timestamped backups, JSON reading)
  - `mod_utils.gd` — Mod logic: validate, enable (copy to game's `mods/`), disable (copy to `temp_mods/`). `install_mod()` and `uninstall_mod()` are stubs (TODO).
  - `save_utils.gd` — Save scanning, backup, copy. ZIP import/export are stubs (TODO).

**Mod data format** (`mods/<id>.json`):
```json
{
  "id": "...", "name": "...", "author": "...", "description": "...",
  "version": "v0.0.0", "has_pck": true, "has_dll": false,
  "dependencies": [], "affects_gameplay": false
}
```
Mods with `affects_gameplay: true` are categorized as "gameplay" (red); `false` = "cosmetic" (green).

**Config file** (`config.cfg`):
```
[paths]    game_path=, save_path=
[settings] language=zh_CN, minimize_to_tray=true, auto_backup=true
[window]   width=800, height=700, maximized=false
```

**Localization**: `locales/zh_CN.json` and `locales/en_US.json` — accessed via `translate(key)` in `modmanager.gd`.

**AI integration addons** (editor-only, don't modify):
- `addons/godot_mcp/` — WebSocket MCP server (autoloaded as `MCPGameBridge`) for AI tool control of the Godot editor
- `addons/agent/` — AlphaAgent AI assistant plugin

## Development Phases (from `need/need.txt`)

- **Stage 1** (Completed): Mod management core — list loading, search, enable/disable, categories, batch ops, sorting
- **Stage 2** (Completed): Mod install from ZIP, drag-drop, uninstall
- **Stage 3** (Completed): Save management — list, import/export ZIP, overwrite, auto-backup
- **Stage 4** (In Progress): Settings — path auto-detect, language switch, system tray (pending)
- **Stage 5** (Not started): Testing and optimization

## Save System Details

**Save directory structure**: `%APPDATA%\SlayTheSpire2\steam\` → SteamID folders → profile1-3/, modded/
- Each profile has: saves/progress.save, saves/prefs.save, saves/current_run.save, history/
- progress.save contains: total_playtime, discovered_cards, discovered_relics, ancient_stats (character_stats)

**Character IDs**: CHARACTER.IRONCLAD (铁甲战士), CHARACTER.SILENT (静默猎手), CHARACTER.REGENT (储君), CHARACTER.NECROBINDER (亡灵契约师), CHARACTER.DEFECT (故障机器人)

**Save overwrite UI**: Modal window with direction selection cards (vanilla←modded / modded←vanilla), backup option, warning zone

## Launch Button Requirements

- Circular main button (48px) with triangle icon at bottom-right of each tab
- Orbital expansion animation for 3 sub-buttons (vanilla/modded/multiplayer)
- Tween animations with tween_method and .bind()
- Signal: `launch_mode_pressed(mode: String)` where mode is "vanilla", "modded", "multiplayer"

## Steam Launch Implementation

**Steam App ID**: `2868840` (Slay the Spire 2)

**Launch Protocol**: Use `steam://launch/` protocol for proper Steam integration:
- `steam://launch/2868840` - Launch game directly
- `steam://launch/2868840/dialog` - Launch with Steam options dialog

**GDScript Implementation**:
```gdscript
# Launch game via Steam protocol
OS.shell_open("steam://launch/2868840/dialog")
```

**Key Points**:
- Always use Steam protocol to avoid "未使用Steam打开" error
- Steam must be running (will auto-launch if not)
- `steam://launch/` respects Steam's launch options; `steam://rungameid/` ignores them
- Detailed documentation: `docs/steam_launch_technical.md`

## Future Features

1. Mod JSON validation config (customizable required fields)
2. Nexus Mods API integration (search, download, progress display,断点续传)

## Key Conventions

- Use Godot built-in APIs first (e.g., `ZipReader` for ZIP, `ConfigFile` for config, `FileAccess`/`DirAccess` for filesystem)
- UI style: modern flat design
- All user-facing strings must support both `zh_CN` and `en_US` via the `translate()` system
- Eliminate duplicate code in utility classes
- **IMPORTANT**: Never skip or disable functionality to "solve" problems without user approval. If a feature needs to be modified or has issues, explain the situation and ask the user for direction instead of making unilateral decisions to disable features.

## Communication Note
- When user expressions are unclear or need more information, ask for clarification using the option format (AskUserQuestion tool)

## Download Feature Constraints

- **Browser Extension Download**: Browser extension sends NXM URL or direct download URL to Mod Manager. Both are supported:
  - NXM URL: `nxm://slaythespire2/mods/23/files/1028?key=XXX&expires=XXX&user_id=XXX`
  - Direct URL: `https://supporter-files.nexus-cdn.com/...`
  - If NXM URL is received, use Nexus API to get download link (requires Premium for some operations)

## Claude Code Hooks (任务完成通知)

需要在项目 `.claude/settings.local.json` 中配置 Stop hook 以启用任务完成时弹窗通知:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "async": true,
            "command": "node \"C:\\Users\\guo\\.claude\\cc-notifier\\dist\\hook.js\"",
            "timeout": 10,
            "type": "command"
          }
        ],
        "matcher": ""
      }
    ]
  }
}
```

**重要**: 将 Stop hook 配置添加到 `.claude/settings.local.json` 的 `hooks` 字段中。所有任务完成（Stop 事件）都会触发 cc-notifier 弹窗通知。

## Web UI 开发约束 (重要！)

**核心原则：直接复用原版 Godot 代码，不重新发明轮子**

1. **禁止随意创建新功能函数**：Web UI 的 API 绑定应尽可能直接调用原版 Godot 已验证过的函数逻辑
2. **API 绑定策略**：
   - 优先调用原版 `_on_*_pressed()` 函数或底层工具函数（如 `SaveUtils.*`）
   - 参数验证和路径处理逻辑应复用原版代码
3. **遇到不匹配时询问用户**：当原版函数与 Web UI 需求不匹配时（例如原版需要打开文件对话框，而 Web UI 需要直接返回结果），**必须先询问用户**，由用户决定如何处理
   - 示例：`_on_export_save_pressed()` 会打开文件对话框，Web UI 无法使用 → 询问用户是否需要在 Web UI 中添加路径选择功能
4. **前端调用方式**：Web UI 的 `_batchBackup()`、`_batchExport()`、`_batchRestore()` 只调用**一次** API，传入账号 `steam_id`，不得遍历 profile 循环调用
5. **存档操作单位**：原版 Godot 的备份/导出/恢复操作单位是**整个账号目录**（包含所有 profile 和 modded），而非单个 profile
6. **新功能许可**：任何新功能必须添加函数时，必须先获得用户许可

**违反后果**：重复备份、功能异常、浪费时间

## BrowserHost 内嵌浏览器 / WebView2 技术文档

### 架构概述

BrowserHost 是用 C# WinForms + WebView2 编写的内嵌浏览器组件（`browser_host/` 目录），负责在 Godot 窗口内显示 Web UI 页面。

### 组件层级
```
Godot 窗口 (SubViewport)
  └── BrowserHost.exe (独立进程，通过命令行参数注入父窗口句柄)
        └── WebView2 控件 (显示 http://localhost:PORT/index.html)
```

### 本地目录选择（重要！）

**问题**：WebView2 中，`webkitdirectory` input 会弹出"上传文件夹"对话框（两个连续的弹窗），且 JavaScript `change` 事件在某些版本中可能不触发。

**正确方案：通过 BrowserHost C# Host Object 调用原生 FolderBrowserDialog**

#### 1. 在 BrowserHost 中注册 Host Object

在 `Program.cs` 的 `BrowserHost` 类里，定义原生方法类：

```csharp
// Host object exposed to JavaScript via AddHostObjectToScript
public class BrowserHostObject
{
    public string SelectFolder()
    {
        using (var dialog = new FolderBrowserDialog())
        {
            dialog.Description = "选择导出目录";
            dialog.UseDescriptionForTitle = true;
            dialog.ShowNewFolderButton = true;
            if (dialog.ShowDialog() == DialogResult.OK)
            {
                return dialog.SelectedPath;
            }
        }
        return null;
    }
}
```

在页面加载成功（NavigationCompleted）后注册：
```csharp
// 在 NavigationCompleted 的 else 分支中
_webView.CoreWebView2.AddHostObjectToScript("browserHost", new BrowserHostObject());
```

**注意**：`AddHostObjectToScript` 必须在 `Navigate()` 之后页面加载成功时调用，不能在 `Navigate()` 之前调用。

#### 2. 前端调用方式（api.js）

```javascript
async selectDirectory() {
    // 优先使用 BrowserHost Host Object（显示原生文件夹选择对话框）
    if (window.chrome?.webview?.hostObjects) {
        const result = await window.chrome.webview.hostObjects.browserHost.SelectFolder();
        if (result && typeof result === 'string' && result.length > 0) {
            return { success: true, path: result };
        }
    }
    // Fallback: webkitdirectory input（不推荐，会显示上传对话框）
    // ...
}
```

#### 3. 调试方法

在浏览器控制台执行：
```javascript
JSON.stringify(Object.keys(window.chrome?.webview?.hostObjects || {}))
// 输出 '["browserHost"]' 表示注册成功
```

### 常见问题排查

| 症状 | 原因 | 解决方案 |
|------|------|----------|
| `chrome.webview.hostObjects` 为 `undefined` | BrowserHost 没有重新编译，或注册代码在 `Navigate()` 之前执行 | 重新编译 BrowserHost，确保 `AddHostObjectToScript` 在 `NavigationCompleted` 成功后调用 |
| `selectDirectory` 返回"桌面"而非完整路径 | WebView2 `showDirectoryPicker()` 只返回 handle.name，无完整路径 | 使用 `webkitdirectory` input 的 `files[0].path` 属性获取真实路径，或通过 BrowserHost C# Host Object 获取 |
| 页面在普通 Chrome 浏览器中打开 | Web UI 通过普通浏览器访问而非 BrowserHost | 必须通过 BrowserHost 的 WebView2 打开 Web UI |
