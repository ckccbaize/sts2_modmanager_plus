# STS2 Mod Manager

> 杀戮尖塔2（Slay the Spire 2）模组管理器

基于 **Godot 4.6.2 Mono** 开发，采用 **Godot 后端 + WebUI 前端** 架构。支持模组管理、存档管理、整合包管理、N 网下载等核心功能。

**当前版本：** v2.9.5 | **默认端口：** 28900

## 功能总览

### 模组管理
- **安装/卸载**：拖拽 ZIP 文件安装，支持多文件批量安装、安装进度对话框
- **启用/禁用**：一键切换模组状态，依赖自动检测（缺失依赖弹出警告对话框）
- **批量操作**：多选模式，批量启用/禁用/卸载模组，实时显示已选数量
- **搜索与排序**：按名称实时搜索，支持按时间、版本、作者排序
- **标签预设**：自定义标签（游戏性、美化等），保存/加载预设，一键切换模组组合
- **收纳盒子**：创建彩色收纳盒子，拖拽模组归类，折叠/展开/重命名
- **拖拽排序**：盒子内外自由拖拽，可视化放置指示线，排序持久化保存
- **模组备注**：为任意模组添加备注，方便记忆配置细节
- **依赖检查**：自动检测模组依赖关系，启用时提示缺失或未启用的依赖
- **自动扫描**：启动时扫描 mods 文件夹，支持嵌套目录结构

### 整合包管理
- **导入**：本地 ZIP 文件导入、URL 在线下载导入、原生文件对话框导入
- **导出**：将当前已启用模组打包导出为整合包 ZIP
- **预设管理**：每个整合包支持多个预设，快速切换不同模组组合
- **冲突处理**：启用整合包时检测冲突，提供替换/跳过选项
- **更新检查**：检查整合包是否有可用更新

### 存档管理
- **多账号支持**：自动扫描 Steam / GSE 所有账号存档，按账号分组显示
- **存档详情**：显示角色统计（胜场/败场/胜率）、游戏时长、运行次数等
- **备份/恢复**：本地存档备份，支持选择特定备份恢复，两步恢复向导
- **跨账号覆盖**：在不同账号间覆盖存档（modded ↔ vanilla），支持备份前置
- **导入/导出**：支持导入外部存档包（ZIP），批量导出存档
- **云同步**：支持 GSE 云存档和 Steam 云存档本地同步（覆盖后弹窗选择同步目标）
- **长按删除**：1.5 秒充能条动画防误触

### N 网模组下载
- **内嵌浏览器**：WebView2 内嵌浏览器，支持 N 网浏览和下载
- **插件注入**：nexus_inject.js 插件自动注入下载按钮到 N 网页面
- **断点续传**：支持暂停、恢复、取消下载
- **下载管理**：实时进度显示、下载历史记录

### 设置
- **路径检测**：自动检测游戏路径和存档路径
- **云端配置**：设置 GSE/Steam 云同步路径
- **DPI 缩放**：界面缩放比例 0.8x ~ 2.0x
- **语言切换**：中文 / English
- **自动备份**：启动时自动备份存档，可配置最大备份数量
- **Steam 启动**：通过 FixSteam 启动游戏的开关
- **JSON 字段验证**：可配置模组 JSON 校验规则
- **调试导出**：导出调试信息为 JSON 文件
- **版本更新**：启动时自动检查更新（Gitee → GitHub），支持手动检查和下载

### 启动功能
- **Tesla Launch Bar**：底部快捷启动栏
- **原版启动**：启动不带任何模组的游戏
- **模组版启动**：启动带当前已启用模组的游戏
- **启动预设**：单人模组预设 / 联机模组预设快速切换

## 技术架构

```
sts-2-modmanager/
├── modmanager.gd              # 主程序入口（GDScript）
├── project.godot              # Godot 项目配置
├── version.json               # 版本号 (v2.9.5)
├── utils/
│   ├── local_server.gd        # HTTP API 服务器（本地 28900 端口）
│   ├── api_bridge.gd          # 前后端通信桥梁
│   ├── mod_utils.gd           # 模组安装/管理工具
│   ├── save_utils.gd          # 存档操作工具（备份/覆盖/云同步）
│   ├── file_utils.gd          # 文件操作工具
│   ├── nexus_api.gd           # N 网 API 封装
│   └── update_checker.gd      # 版本更新检测
├── browser_host/              # WebView2 内嵌浏览器（C#）
│   ├── Program.cs             # BrowserHost 主程序
│   └── extension/
│       └── nexus_inject.js    # N 网下载按钮注入插件
├── web/                       # WebUI 界面
│   ├── index.html             # 主页面
│   ├── css/                   # 样式文件
│   └── js/
│       ├── app.js             # 主应用逻辑（路由、事件总线、DPI）
│       ├── api.js             # API 客户端（50+ 端点）
│       ├── mods.js            # 模组管理 UI（拖拽、盒子、批量操作）
│       ├── bundles.js         # 整合包管理 UI
│       ├── saves.js           # 存档管理 UI（多账号、备份、覆盖）
│       ├── nexus.js           # N 网集成
│       ├── downloads.js       # 下载管理
│       └── settings.js        # 设置页面（12 个配置区域）
└── locales/
    ├── zh_CN.json             # 中文翻译
    └── en_US.json             # 英文翻译
```

### 核心技术栈
- **引擎**：Godot 4.6.2 Mono（GDScript + C#）
- **前端**：原生 HTML/CSS/JavaScript（无框架 SPA）
- **浏览器**：Microsoft Edge WebView2
- **通信**：HTTP API（本地服务器）+ WebView2 Host Objects（原生对话框）
- **数据持久化**：后端 JSON 文件 + 前端 localStorage 离线缓存
- **国际化**：zh_CN / en_US，`data-i18n` 动态翻译

### API 端点概览
后端提供 **50+ 个 API 端点**，覆盖以下模块：
- `/api/health` · `/api/status` — 健康检查与状态
- `/api/mods/*` — 模组管理（14 个端点）
- `/api/saves/*` — 存档管理（10 个端点）
- `/api/bundles/*` — 整合包管理（11 个端点）
- `/api/settings` — 设置管理（4 个端点）
- `/api/downloads/*` — 下载管理（4 个端点）
- `/api/launch` · `/api/update/*` — 游戏启动与更新

## 系统要求

- **操作系统**：Windows 10/11
- **运行时**：[WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)、.NET 6+（BrowserHost）
- **游戏本体**：Slay the Spire 2

## 使用方法

1. 运行 `BrowserHost.exe` 启动管理器
2. 首次使用需在 **设置** 中配置游戏路径（可点击"自动检测"）
3. 将模组 ZIP 文件**拖入**模组页面，或点击"安装模组"按钮选择文件
4. 启用所需模组后，点击底部 **Tesla Launch Bar** 启动游戏

## 构建

### 环境要求
- [Godot 4.6.2 Mono](https://godotengine.org/download)
- .NET SDK 6.0+

### 编译步骤
```bash
git clone https://github.com/ckccbaize/sts2_modmanager_plus.git
cd sts-2-modmanager
# 在 Godot 编辑器中打开项目，选择导出 → Windows Desktop
```

### BrowserHost 编译
```bash
cd browser_host
dotnet build -c Release
```

## 版本历史

### v2.9.5（当前版本）
- WebUI 界面全面优化
- 标签预设持久化修复
- 存档 API 响应格式统一
- 云同步功能恢复（GSE/Steam 本地文件夹同步）
- 存档导出路径空格问题修复
- 导出整合包 ZIP 压缩路径问题修复
- 覆盖操作 source_steam_id 传递修复
- 覆盖操作路径修复（`modded/profile1/saves`）
- BrowserHost 导航稳定性优化（线程池饥饿修复）

### v2.8.3
- 批量模组操作
- 整合包功能增强
- N 网模组集成

### v2.6.9
- 自动更新检测
- 调试信息导出
- PowerShell 兼容性修复

## 许可证

MIT License

## 相关链接

- [GitHub 仓库](https://github.com/ckccbaize/sts2_modmanager_plus)
- [Slay the Spire 2](https://www.fireproofgames.com/slay-the-spire-2)
- [Godot Engine](https://godotengine.org/)
- [WebView2](https://developer.microsoft.com/microsoft-edge/webview2/)
