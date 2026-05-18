# STS2 模组管理器

杀戮尖塔2（Slay the Spire 2）模组管理器，基于 Godot 4.6.2 + C# 开发。

## 功能概览

### 模组管理
- **安装/卸载模组**：拖拽 ZIP 文件安装，支持多文件批量安装
- **启用/禁用模组**：一键切换模组状态，无需手动移动文件
- **批量操作**：多选模式，批量启用/禁用/卸载模组
- **搜索与排序**：按名称、时间、版本、作者排序筛选
- **标签分类**：自定义标签（游戏性、美化等），支持预设保存/加载
- **自动扫描**：启动时自动扫描 mods 文件夹，支持嵌套目录结构
- **依赖检查**：自动检测模组依赖关系

### 整合包管理
- **导入整合包**：支持本地 ZIP 文件导入和 URL 在线下载
- **导出整合包**：将当前模组配置导出为整合包（Bundle）
- **预设管理**：每个整合包支持多个预设，方便快速切换配置
- **一键应用**：选中预设后自动切换模组组合

### 存档管理
- **存档查看**：显示所有 Steam/GSE 账号的存档
- **备份/恢复**：本地存档备份与恢复
- **跨账号覆盖**：支持在不同账号间覆盖存档（Steam ↔ GSE）
- **云同步**：支持与 GSE Cloud / Steam Cloud 双向同步存档
- **导入/导出**：支持导入外部存档包（ZIP 格式）

### N网模组下载
- **浏览器注入**：通过 BrowserHost 内嵌浏览器和 nexus_inject.js 插件注入下载按钮
- **快捷下载**：在游戏内浏览器直接下载安装 N网模组

### 下载管理
- **下载队列**：实时显示下载进度和状态
- **断点续传**：支持暂停、继续、取消下载操作
- **下载历史**：记录已完成下载历史，支持清空

### 设置
- **游戏路径**：自动检测杀戮尖塔2安装路径
- **存档路径**：自动检测或手动配置存档目录
- **云端配置**：设置 GSE/Steam 云同步服务
- **DPI 缩放**：支持界面缩放比例 0.8x - 2.0x
- **调试导出**：可导出调试信息帮助问题排查

### 自动更新
- **启动检测**：启动时自动检查更新（优先 Gitee，失败则尝试 GitHub）
- **手动检查**：支持手动点击检查更新按钮
- **自动安装**：发现新版本时可直接下载安装

### 启动功能
- **Tesla Launch Bar**：底部快捷启动栏
- **原版启动**：启动不带任何模组的游戏
- **模组版启动**：启动带当前已启用模组的游戏

## 技术架构

```
├── modmanager.gd          # 主程序入口（Godot C# 项目）
├── utils/
│   ├── mod_utils.gd       # 模组安装/管理工具
│   ├── save_utils.gd      # 存档操作工具（GSE/Steam 云同步）
│   ├── file_utils.gd      # 文件操作工具
│   ├── nexus_api.gd       # N网 API 封装
│   ├── update_checker.gd  # 更新检测
│   └── local_server.gd    # HTTP API 服务器
├── browser_host/          # WebView2 内嵌浏览器
│   └── Program.cs         # BrowserHost 主程序
├── web/                   # WebUI 界面
│   ├── index.html         # 主页面（v2.9.5）
│   ├── css/               # 样式文件
│   └── js/                # JavaScript 模块
│       ├── api.js          # API 客户端
│       ├── mods.js         # 模组管理
│       ├── bundles.js      # 整合包管理
│       ├── saves.js        # 存档管理
│       ├── nexus.js        # N网集成
│       └── downloads.js   # 下载管理
└── sts2_browser_extension/ # N网浏览器插件（Chrome/Edge）
```

### 核心技术栈
- **引擎**：Godot 4.6.2 Mono（支持 C#）
- **前端**：原生 HTML/CSS/JavaScript WebUI
- **浏览器**：WebView2（Microsoft Edge 内核）
- **通信**：HTTP API（local_server.gd）+ WebView2 Host Objects
- **存档同步**：PowerShell 命令调用 GSE/Steam 云服务

## 系统要求

- Windows 10/11
- [WebView2 运行时](https://developer.microsoft.com/microsoft-edge/webview2/)
- 杀戮尖塔2 游戏本体
- .NET Framework 4.6+ 或 .NET 6+（用于 BrowserHost）

## 使用方法

1. 运行 `BrowserHost.exe` 启动管理器
2. 首次使用需在设置中配置游戏路径
3. 将模组 ZIP 文件拖入模组页面即可安装
4. 点击底部 Tesla Launch Bar 启动游戏

## 版本历史

### v2.9.5（当前版本）
- WebUI 界面优化
- 标签预设持久化修复
- 存档导出路径处理优化

### v2.8.3
- 批量模组操作
- 整合包功能增强
- N网模组集成

### v2.6.9
- 自动更新检测
- 调试信息导出
- PowerShell 兼容性修复

## 构建

### 环境要求
- Godot 4.6.2 Mono（[官网下载](https://godotengine.org/download)）
- .NET SDK 6.0+

### 编译步骤
```bash
# 克隆仓库
git clone https://github.com/ckccbaize/sts2_modmanager_plus.git
cd sts-2-modmanager

# 在 Godot 编辑器中打开项目导出
godot --headless --export-release "Windows Desktop"
```

### BrowserHost 编译
```bash
cd browser_host
dotnet build -c Release
```

## 许可证

MIT License

## 相关链接

- [GitHub 仓库](https://github.com/ckccbaize/sts2_modmanager_plus)
- [Slay the Spire 2](https://www.fireproofgames.com/slay-the-spire-2)
- [Godot Engine](https://godotengine.org/)
- [WebView2](https://developer.microsoft.com/microsoft-edge/webview2/)