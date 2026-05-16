# UI重设计实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将模组管理器的UI从当前基础风格改为Steam×Windows 11混合风格

**Architecture:** 直接修改 `modmanager.tscn` 中的UI组件属性，使用Godot 4.x的Theme自定义和StyleBox来实现深蓝渐变、亚克力模糊、圆角等效果

**Tech Stack:** Godot 4.5.1, GDScript, Theme Editor

---

## 文件结构

### 主要修改
- `modmanager.tscn` - 主场景，包含所有UI组件定义
- `modmanager.gd` - 主控制器，部分样式代码在此

### 参考
- `docs/superpowers/specs/2026-04-11-ui-redesign-steam-win11.md` - 设计规范

---

## 实施任务

### Task 1: 修改主场景标题栏样式

**Files:**
- Modify: `modmanager.tscn:1-50` (LoadingPanel区域)
- Modify: `modmanager.tscn:73-82` (TabContainer区域)

- [ ] **Step 1: 添加全局样式自定义**

在 `modmanager.tscn` 的根节点 `Control` 上添加 `theme_override` 资源配置：

```gdscript
# 在modmanager.gd的_ready()开头添加主题初始化
func _ready() -> void:
    # 创建自定义主题
    _setup_custom_theme()
    # ... 原有代码
```

- [ ] **Step 2: 修改LoadingPanel样式**

找到 `LoadingPanel` 节点，修改：
- `color` 背景为深蓝渐变效果

```gdscript
# 在_setup_custom_theme()中添加
var loading_bg = StyleBoxFlat.new()
loading_bg.bg_color = Color(0.106, 0.157, 0.22, 0.9)  # #1b2838
loading_bg.corner_radius_top_left = 8
loading_bg.corner_radius_top_right = 8
loading_bg.corner_radius_bottom_left = 8
loading_bg.corner_radius_bottom_right = 8
theme.set_stylebox("panel", "LoadingPanel", loading_bg)
```

- [ ] **Step 3: 验证修改效果**

运行项目检查：
- 点击运行(F5)或 `godot --path . --headless`
- 确认LoadingPanel显示为深蓝色

- [ ] **Step 4: 提交**

```bash
git add modmanager.gd modmanager.tscn
git commit -m "refactor: 开始UI重设计 - 添加自定义主题基础"
```

---

### Task 2: 修改TabContainer标题栏

**Files:**
- Modify: `modmanager.tscn:73-141`

- [ ] **Step 1: 找到TabContainer节点**

定位 `TabContainer` 节点结构和 `TopBar`

- [ ] **Step 2: 修改TopBar背景**

在 `TabContainer/ModTab/TopBar`:
```gdscript
# 添加到_setup_custom_theme()
var topbar = StyleBoxFlat.new()
topbar.bg_color = Color(0.082, 0.118, 0.176, 0.95)  # rgba(21,31,46,0.95)
topbar.corner_radius_top_left = 0
topbar.corner_radius_top_right = 0
theme.set_stylebox("panel", "TopBar", topbar)
```

- [ ] **Step 3: 修改搜索框样式**

`SearchEdit` (LineEdit):
- 背景: `rgba(42,71,94,0.6)` = Color(0.165, 0.278, 0.369, 0.6)
- 边框: 1px solid `rgba(86,131,172,0.3)`
- 圆角: 20px (使用corner_radius)

- [ ] **Step 4: 修改按钮样式**

`SearchBtn`, `InstallModBtn` 等:
- 主按钮渐变或深色背景
- 圆角 6px

- [ ] **Step 5: 验证运行**

```bash
godot --path . --headless --script
# 检查无报错
```

- [ ] **Step 6: 提交**

```bash
git add modmanager.gd modmanager.tscn
git commit -m "refactor: 修改TabContainer标题栏样式"
```

---

### Task 3: 修改模组列表样式

**Files:**
- Modify: `modmanager.tscn:139-168`

- [ ] **Step 1: 找到ModList相关节点**

定位 `HSplit`, `LeftPanel`, `ModScroll`, `ModList`

- [ ] **Step 2: 修改LeftPanel背景**

```gdscript
var left_panel = StyleBoxFlat.new()
left_panel.bg_color = Color(0.071, 0.09, 0.118)  # #12171e
theme.set_stylebox("panel", "LeftPanel", left_panel)
```

- [ ] **Step 3: 修改ModItem显示**

模组列表项通过代码生成，需要在 `mod_item.gd` 中修改或使用Theme统一

- [ ] **Step 4: 验证列表显示**

运行检查列表项样式

- [ ] **Step 5: 提交**

```bash
git commit -m "refactor: 修改模组列表背景样式"
```

---

### Task 4: 修改详情面板样式

**Files:**
- Modify: `modmanager.tscn:169-221`

- [ ] **Step 1: 找到RightPanel/ModDetailsPanel节点**

- [ ] **Step 2: 设置详情面板StyleBox**

```gdscript
var detail_panel = StyleBoxFlat.new()
detail_panel.bg_color = Color(0, 0, 0, 0.2)  # rgba(0,0,0,0.2)
detail_panel.corner_radius_top_left = 8
detail_panel.corner_radius_top_right = 8
detail_panel.corner_radius_bottom_left = 8
detail_panel.corner_radius_bottom_right = 8
detail_panel.border_width_left = 1
detail_panel.border_width_right = 1
detail_panel.border_width_top = 1
detail_panel.border_width_bottom = 1
detail_panel.border_color = Color(0.337, 0.514, 0.675, 0.15)  # rgba(86,131,172,0.15)
theme.set_stylebox("panel", "ModDetailsPanel", detail_panel)
```

- [ ] **Step 3: 修改Label文字颜色**

详情面板中的文字需要调整为浅灰色：
- 标题: 22px, #66c0f9
- 正文: 13px, #c7d5e0

- [ ] **Step 4: 验证详情面板**

- [ ] **Step 5: 提交**

```bash
git commit -m "refactor: 修改详情面板样式"
```

---

### Task 5: 整合包/存档/设置Tab统一风格

**Files:**
- Modify: `modmanager.tscn:222-740` (整段)

- [ ] **Step 1: 检查各Tab结构**

- [ ] **Step 2: 批量应用主题**

为以下节点应用统一StyleBox：
- `BundleTab/BundleHSplit`
- `SaveTab/SaveContainer`
- `SettingsTab/SettingsScroll`

- [ ] **Step 3: 提交**

```bash
git commit -m "refactor: 统一其他Tab风格"
```

---

### Task 6: 添加动画和交互效果（可选）

**Files:**
- Modify: `modmanager.gd`

- [ ] **Step 1: 添加悬停效果**

使用Tween实现悬停过渡动画

- [ ] **Step 2: 提交**

```bash
git commit -m "refactor: 添加UI交互动画"
```

---

## 自检清单

- [ ] 每个Task都有对应的代码改动
- [ ] 颜色值与设计规范一致
- [ ] 运行验证后提交
- [ ] 所有功能保持正常工作

---

## 执行选择

**Plan complete and saved to `docs/superpowers/plans/2026-04-11-ui-redesign.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**