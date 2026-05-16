# UI/UX 重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将模组管理器的UI从当前基础风格改为Steam×Windows 11混合风格，包含Tesla风格拖拽启动按钮

**Architecture:** 直接修改 `modmanager.tscn` 中的UI组件属性，使用Godot 4.x的Theme自定义和StyleBox来实现深蓝渐变、亚克力模糊、圆角等效果

**Tech Stack:** Godot 4.5.1, GDScript, Theme Editor

---

## 文件结构

### 主要修改
- `modmanager.tscn` - 主场景，包含所有UI组件定义
- `modmanager.gd` - 主控制器，样式相关代码
- `ui/mod_item.tscn` - 模组列表项组件（修改样式）
- `ui/save_item.tscn` - 存档列表项组件（修改样式）

### 参考设计
- `docs/reference/01-all-tabs-v8-final.html` - 完整UI设计规范
- `docs/reference/02-mod-page-with-launch-button.html` - Tesla启动按钮交互设计

---

## 零、风格规范 (Style Guide)

### 0.1 核心色彩系统

| 用途 | 颜色名 | Hex | GDScript Color |
|------|--------|-----|-----------------|
| 背景深 | Deep Ocean | #1b2838 | Color(0.106, 0.157, 0.22) |
| 背景浅 | Midnight | #12171e | Color(0.071, 0.09, 0.118) |
| 强调色 | Steam Blue | #66c0f9 | Color(0.4, 0.753, 0.976) |
| 强调深 | Dark Blue | #2a475e | Color(0.165, 0.278, 0.369) |
| 文字主 | Light Gray | #c7d5e0 | Color(0.78, 0.835, 0.878) |
| 文字次 | Medium Gray | #8b98a0 | Color(0.545, 0.596, 0.627) |
| 边框 | Blue Gray | rgba(86,131,172,0.3) | Color(0.337, 0.514, 0.675, 0.3) |
| 悬停 | Glow Blue | rgba(102,192,249,0.15) | Color(0.4, 0.753, 0.976, 0.15) |

### 0.2 功能色彩

| 用途 | 颜色名 | Hex | GDScript |
|------|--------|-----|----------|
| 游戏性Mod | Magenta | #f472b6 | Color(0.957, 0.447, 0.714) |
| 美化Mod | Cyan | #66c0f9 | Color(0.4, 0.753, 0.976) |
| 成功 | Green | #4ade80 | Color(0.29, 0.87, 0.5) |
| 警告 | Orange | #ffa940 | Color(1, 0.663, 0.251) |

### 0.3 字体系统

| 元素 | 字号 | 字重 | 颜色 |
|------|------|------|------|
| 窗口标题 | 13px | 500 | #c7d5e0 |
| 标签标题 | 12px | 400 | #8b98a0 (未激活) / #fff (激活) |
| 列表标题 | 13px | 400 | #e5e5e5 |
| 列表副标题 | 11px | 400 | #8b98a0 |
| 详情标题 | 22px | 500 | #66c0f9 |
| 详情正文 | 13px | 400 | #c7d5e0 |
| 徽章文字 | 10px | 400 | 根据类型 |
| 页脚文字 | 11px | 400 | #8b98a0 |

### 0.4 间距系统

| 级别 | 像素值 | 使用场景 |
|------|--------|----------|
| 大间距 | 20px | 区块之间 |
| 中间距 | 16px | 组件之间 |
| 小间距 | 12px | 元素之间 |
| 微间距 | 8px | 紧密元素 |

### 0.5 圆角系统

| 元素 | 圆角值 | 备注 |
|------|--------|------|
| 卡片/面板 | 8px | Panel, DetailPanel |
| 按钮 | 6px | Button, ActionBtn |
| 输入框 | 20px | LineEdit (药丸形) |
| Toggle | 10px | CheckBox (36×20尺寸) |
| 徽章 | 4px | Badge, Tag |

### 0.6 组件样式规范

#### 按钮 (Button)

**次按钮 (Secondary)**
```
背景: transparent
边框: 1px solid rgba(86,131,172,0.4)
圆角: 6px
内边距: 10px 20px
文字颜色: #a3c9e7
字号: 12px
悬停: 边框变亮
```

**主按钮 (Primary)**
```
背景: linear-gradient(90deg, #47bfff, #2a475e)
边框: none
圆角: 6px
内边距: 10px 20px
文字颜色: #fff
字号: 12px
悬停: opacity 0.9
```

#### 输入框 (LineEdit)
```
背景: rgba(42,71,94,0.6)
边框: 1px solid rgba(86,131,172,0.3)
圆角: 20px (药丸形)
内边距: 8px 14px
文字颜色: #c7d5e0
占位符颜色: #555
聚焦: 边框变 #66c0f9
```

#### 卡片/面板 (PanelContainer)
```
背景: rgba(0,0,0,0.2) 或 rgba(42,71,94,0.3)
边框: 1px solid rgba(86,131,172,0.15)
圆角: 8px
内边距: 12px-20px
```

#### Toggle开关
```
尺寸: 36px × 20px
关闭背景: rgba(42,71,94,0.8)
开启背景: #66c0f9
圆点: 16px白色, 偏移2px
动画: 0.2s ease
```

### 0.7 布局规范

#### 页面布局比例
- 模组页面: 55%列表 / 45%详情
- 整合包页面: 300px左侧列表 / 弹性右侧详情
- 存档页面: 300px左侧账号列表 / 弹性右侧详情
- 设置页面: 140px左侧导航 / 弹性右侧内容

#### 标题栏
```
高度: 40px (内容区) / 48px (整个标题栏)
背景: rgba(21,31,46,0.95)
边框底: 1px solid rgba(86,131,172,0.2)
布局: [图标 标题] -- [搜索框] -- [按钮组]
```

#### 底部栏
```
高度: 40px
背景: rgba(21,31,46,0.6)
边框顶: 1px solid rgba(86,131,172,0.15)
```

### 0.8 交互状态

| 状态 | 效果 |
|------|------|
| 默认 | 基础样式 |
| 悬停 (Hover) | 背景变亮/边框变亮 |
| 按下 (Pressed) | 背景变深 |
| 选中 (Selected) | 渐变背景 + 边框高亮 |
| 禁用 (Disabled) | opacity 0.5 |

### 0.9 动画规范

| 场景 | 时长 | 缓动函数 |
|------|------|----------|
| 悬停过渡 | 200ms | ease |
| 展开/收起 | 300ms | ease-out |
| 弹框出现 | 200ms | ease-back |
| Toggle开关 | 200ms | ease |
| 回弹动画 | 300-400ms | cubic-bezier(0.175, 0.885, 0.32, 1.275) |

### 0.10 Tesla启动按钮规范

**布局结构**
```
[P] — 轨道 — [D] — 间距30px — [N+球] — 间距30px — [R]
```

**档位球 (Knob)**
```
尺寸: 覆盖在N上方 (约28×26px)
背景: linear-gradient(145deg, #2a475e, #1b2838)
边框: 2px solid #66c0f9
圆角: 12px (覆盖N)
图标: 右侧三角形 (CSS border实现)
阴影: 0 2px 10px rgba(102,192,249,0.25)
```

**档位状态**
- P (联机): 粉色强调 #f472b6
- D (模组): 蓝色强调 #66c0f9
- N (空档): 绿色 #10b981
- R (原版): 粉色 #f472b6

**拖拽交互**
- 行程范围: -150px ~ +100px (从N开始)
- 吸附判定: 接近档位位置±15px内
- 释放行为: 在档位上则启动，否则弹回N

---

## 一、色彩系统定义

### 1.1 全局颜色常量（在modmanager.gd中定义）

```gdscript
# 在modmanager.gd顶部添加颜色常量
const COLORS = {
	"bg_deep": Color(0.106, 0.157, 0.22),      # #1b2838
	"bg_light": Color(0.071, 0.09, 0.118),     # #12171e
	"accent": Color(0.4, 0.753, 0.976),         # #66c0f9
	"accent_dark": Color(0.165, 0.278, 0.369), # #2a475e
	"text_primary": Color(0.78, 0.835, 0.878), # #c7d5e0
	"text_secondary": Color(0.545, 0.596, 0.627), # #8b98a0
	"border": Color(0.337, 0.514, 0.675, 0.3),  # rgba(86,131,172,0.3)
	"hover": Color(0.4, 0.753, 0.976, 0.15),   # rgba(102,192,249,0.15)
	"gameplay": Color(0.957, 0.447, 0.714),    # #f472b6
	"cosmetic": Color(0.4, 0.753, 0.976),      # #66c0f9
	"success": Color(0.29, 0.87, 0.5),         # #4ade80
	"warning": Color(1, 0.663, 0.251)           # #ffa940
}
```

### 1.2 Theme设置（在_setup_custom_theme()函数中）

```gdscript
func _setup_custom_theme() -> void:
	var theme = Theme.new()
	
	# Panel样式
	var panel = StyleBoxFlat.new()
	panel.bg_color = COLORS.bg_light
	panel.corner_radius_top_left = 8
	panel.corner_radius_top_right = 8
	panel.corner_radius_bottom_left = 8
	panel.corner_radius_bottom_right = 8
	panel.border_width_left = 1
	panel.border_width_right = 1
	panel.border_width_top = 1
	panel.border_width_bottom = 1
	panel.border_color = COLORS.border
	theme.set_stylebox("panel", "Panel", panel)
	
	# Button样式
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.165, 0.278, 0.369, 0.6)
	btn_normal.corner_radius_top_left = 6
	btn_normal.corner_radius_top_right = 6
	btn_normal.corner_radius_bottom_left = 6
	btn_normal.corner_radius_bottom_right = 6
	btn_normal.border_width_left = 1
	btn_normal.border_width_right = 1
	btn_normal.border_width_top = 1
	btn_normal.border_width_bottom = 1
	btn_normal.border_color = COLORS.border
	
	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.165, 0.278, 0.369, 0.8)
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = COLORS.accent_dark
	
	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	
	# 主按钮样式（渐变）
	var btn_primary_normal = StyleBoxFlat.new()
	btn_primary_normal.bg_color = COLORS.accent_dark
	btn_primary_normal.corner_radius_top_left = 6
	btn_primary_normal.corner_radius_top_right = 6
	btn_primary_normal.corner_radius_bottom_left = 6
	btn_primary_normal.corner_radius_bottom_right = 6
	
	theme.set_stylebox("normal", "PrimaryButton", btn_primary_normal)
	
	# LineEdit样式
	var lineedit = StyleBoxFlat.new()
	lineedit.bg_color = Color(0.165, 0.278, 0.369, 0.6)
	lineedit.corner_radius_top_left = 20
	lineedit.corner_radius_top_right = 20
	lineedit.corner_radius_bottom_left = 20
	lineedit.corner_radius_bottom_right = 20
	lineedit.border_width_left = 1
	lineedit.border_width_right = 1
	lineedit.border_width_top = 1
	lineedit.border_width_bottom = 1
	lineedit.border_color = COLORS.border
	theme.set_stylebox("normal", "LineEdit", lineedit)
	
	# CheckBox样式
	var checkbox = StyleBoxBoxMesh.new()  # 需要设置checkmark纹理
	
	set_theme(theme)
```

---

## 二、模组页面 (Mod Tab) 重构

### 2.1 顶部工具栏 (TopBar) 重构

**目标布局:** `[搜索框] [筛选下拉] [排序下拉] -- [安装按钮] [刷新按钮]`

**节点路径:** `TabContainer/ModTab/TopBar`

- [ ] **Step 1: 修改搜索框 (SearchEdit)**

```gdscript
# 在modmanager.gd的_setup_custom_theme()中添加
var search_bg = StyleBoxFlat.new()
search_bg.bg_color = Color(0.165, 0.278, 0.369, 0.6)
search_bg.corner_radius_top_left = 20
search_bg.corner_radius_top_right = 20
search_bg.corner_radius_bottom_left = 20
search_bg.corner_radius_bottom_right = 20
search_bg.border_width_left = 1
search_bg.border_width_right = 1
search_bg.border_width_top = 1
search_bg.border_width_bottom = 1
search_bg.border_color = Color(0.337, 0.514, 0.675, 0.3)
theme.set_stylebox("normal", "SearchEdit", search_bg)
```

修改属性:
- `placeholder_string`: "搜索模组..."
- `custom_minimum_size`: Vector2(200, 36)

- [ ] **Step 2: 修改筛选下拉 (CategoryFilter)**

修改属性:
- `custom_minimum_size`: Vector2(100, 36)
- `items`: ["全部", "游戏性", "美化", "已启用"]

- [ ] **Step 3: 修改排序下拉 (SortOption)**

修改属性:
- `custom_minimum_size`: Vector2(100, 36)
- `items`: ["名称", "作者", "日期", "类型"]

- [ ] **Step 4: 修改安装按钮 (InstallModBtn)**

修改属性:
- `text`: "安装模组"
- `custom_minimum_size`: Vector2(90, 36)
- 样式: 主按钮渐变背景

- [ ] **Step 5: 修改刷新按钮 (RefreshModsBtn)**

修改属性:
- `text`: "🔄 刷新"
- `custom_minimum_size`: Vector2(80, 36)

- [ ] **Step 6: 添加工具栏背景**

在TopBar节点添加`StyleBoxFlat`背景:
- `bg_color`: Color(0.082, 0.118, 0.176, 0.95)
- `corner_radius_top_left`: 0
- `corner_radius_top_right`: 0
- `corner_radius_bottom_left`: 0
- `corner_radius_bottom_right`: 0

### 2.2 模组列表 (ModList) 重构

**节点路径:** `TabContainer/ModTab/HSplitContainer/LeftPanel/ModScroll/ModList`

- [ ] **Step 1: 修改列表容器背景**

```gdscript
var mod_list_bg = StyleBoxFlat.new()
mod_list_bg.bg_color = COLORS.bg_light
theme.set_stylebox("panel", "ModList", mod_list_bg)
```

- [ ] **Step 2: 修改mod_item.tscn样式**

修改`ui/mod_item.tscn`:
```xml
<!-- 修改PanelContainer样式 -->
<panel_material>...</panel_material>
<theme_type_prefix>v</theme_type_prefix>
```

修改背景色: `Color(0.13, 0.13, 0.13, 1)` → `Color(0.071, 0.09, 0.118)`

修改项:
- `mod_item.tscn`的PanelContainer背景色
- 悬停效果: 添加`Color(0.4, 0.753, 0.976, 0.06)`背景
- 选中效果: 添加渐变背景 + 边框

- [ ] **Step 3: 重新设计Toggle开关**

创建自定义Toggle样式:
- 尺寸: 36px × 20px
- 关闭: `rgba(42,71,94,0.8)` 背景
- 开启: `#66c0f9` 背景
- 圆点: 16px白色，偏移2px
- 动画: 0.2s ease

### 2.3 模组详情面板 (ModDetailsPanel) 重构

**节点路径:** `TabContainer/ModTab/HSplitContainer/RightPanel/ModDetailsPanel`

- [ ] **Step 1: 修改详情面板背景**

```gdscript
var detail_bg = StyleBoxFlat.new()
detail_bg.bg_color = Color(0, 0, 0, 0.2)
detail_bg.corner_radius_top_left = 8
detail_bg.corner_radius_top_right = 8
detail_bg.corner_radius_bottom_left = 8
detail_bg.corner_radius_bottom_right = 8
detail_bg.border_width_left = 1
detail_bg.border_width_right = 1
detail_bg.border_width_top = 1
detail_bg.border_width_bottom = 1
detail_bg.border_color = Color(0.337, 0.514, 0.675, 0.15)
theme.set_stylebox("panel", "ModDetailsPanel", detail_bg)
```

- [ ] **Step 2: 修改标题样式**

- `NameLabel`:
  - `custom_minimum_size`: Vector2(0, 30)
  - `theme_type_override`: ""
  - `theme_font_type_override`: ""
  - `label_settings`: 新建LabelSettings
	- `font_size`: 22
	- `font_color`: #66c0f9
	- `outline_size`: 0

- [ ] **Step 3: 修改Badge样式**

- `TypeLabel`:
  - `horizontal_alignment`: HORIZONTAL_ALIGNMENT_CENTER
  - `vertical_alignment`: VERTICAL_ALIGNMENT_CENTER
  - `custom_minimum_size`: Vector2(60, 24)
  - `label_settings.font_size`: 10
  - `label_settings.font_color`: 根据类型变色

- [ ] **Step 4: 添加备注编辑区域**

在DetailsVBox中添加:
```xml
<PanelContainer name="NotesPanel">
	<VBoxContainer>
		<Label text="📝 备注" theme_type_override="header"/>
		<TextEdit name="NoteEdit" custom_minimum_size="Vector2(0, 80)"/>
	</VBoxContainer>
</PanelContainer>
```

### 2.4 启动模式切换 (Mod Tab Footer)

- [ ] **Step 1: 添加启动模式Tab**

在模组页面详情区域添加:
```xml
<HBoxContainer name="ModStartModes">
	<Button name="SinglePlayerBtn" text="单机模组"/>
	<Button name="MultiplayerBtn" text="联机模组"/>
	<Button name="CustomPresetBtn" text="自定义启动预设"/>
</HBoxContainer>
```

样式:
- 选中按钮: `border_bottom` = 2px solid #66c0f9, 文字白色
- 未选中按钮: 文字灰色

### 2.5 Tesla风格启动按钮 (Footer)

- [ ] **Step 1: 创建LaunchButton组件**

创建`ui/launch_bar.tscn`:

```xml
Control name="LaunchBar" custom_minimum_size="Vector2(300, 40)">
	<HBoxContainer name="BarContainer" anchors_preset="CENTER">
		<!-- P档位 -->
		<Button name="GearP" custom_size="Vector2(32, 32)" text="P"/>
		<!-- 轨道 -->
		<ColorRect name="Track" custom_size="Vector2(20, 2)"/>
		<!-- D档位 -->
		<Button name="GearD" custom_size="Vector2(32, 32)" text="D"/>
		<!-- 间距 -->
		<Control custom_size="Vector2(30, 0)"/>
		<!-- N档位(中间) -->
		<Button name="GearN" custom_size="Vector2(32, 32)" text="N"/>
		<!-- 间距 -->
		<Control custom_size="Vector2(30, 0)"/>
		<!-- R档位 -->
		<Button name="GearR" custom_size="Vector2(32, 32)" text="R"/>
		
		<!-- 档位球(覆盖在N上方) -->
		<TextureRect name="Knob" texture="play_icon.png"/>
	</HBoxContainer>
</Control>
```

- [ ] **Step 2: 实现拖拽逻辑**

```gdscript
# ui/launch_bar.gd
extends Control

var is_dragging := false
var start_mouse_x := 0.0
var knob_start_x := 0.0
var current_gear := "N"

const GEAR_POSITIONS = {
	"P": -80.0,
	"D": -40.0,
	"N": 0.0,
	"R": 40.0
}
const SNAP_RANGE := 15.0

@onready var knob = $BarContainer/Knob

func _ready():
	knob.gui_input.connect(_on_knob_input)

func _on_knob_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			if is_dragging:
				start_mouse_x = get_viewport().get_mouse_position().x
				knob_start_x = knob.position.x
			else:
				_on_drag_end()

func _process(delta):
	if is_dragging:
		var mouse_x = get_viewport().get_mouse_position().x
		var delta_x = mouse_x - start_mouse_x
		var new_x = clamp(knob_start_x + delta_x, -120.0, 80.0)
		knob.position.x = new_x
		_detect_gear(new_x)

func _detect_gear(knob_x: float):
	for gear in GEAR_POSITIONS:
		if abs(knob_x - GEAR_POSITIONS[gear]) < SNAP_RANGE:
			if current_gear != gear:
				current_gear = gear
				_highlight_gear(gear)
			return

func _on_drag_end():
	if current_gear != "N":
		_launch_game(current_gear)
	else:
		_return_to_neutral()

func _launch_game(gear: String):
	# 启动游戏逻辑
	emit_signal("launch_mode_pressed", gear)

func _return_to_neutral():
	var tween = create_tween()
	tween.tween_property(knob, "position:x", 0.0, 0.3)
```

---

## 三、整合包页面 (Bundle Tab) 重构

### 3.1 工具栏重构

**节点路径:** `TabContainer/BundleTab/BundleHSplit/BundleListPanel/BundleListVBox/TopBar`

- [ ] **Step 1: 修改按钮样式**

按钮列表:
- `ImportBundleBtn`: "📥 导入"
- `AddByUrlBtn`: "🔗 通过URL"
- `ExportBundleBtn`: "📤 导出"
- `CheckUpdateBtn`: "🔄 检查更新"

统一样式:
- `custom_minimum_size`: Vector2(100, 32)
- 背景: rgba(42,71,94,0.6)
- 边框: 1px solid rgba(86,131,172,0.3)
- 圆角: 6px

### 3.2 列表项重构

- [ ] **Step 1: 修改BundleItem样式**

```gdscript
var bundle_item = StyleBoxFlat.new()
bundle_item.bg_color = Color(0.071, 0.09, 0.118)
bundle_item.corner_radius_top_left = 8
bundle_item.corner_radius_top_right = 8
bundle_item.corner_radius_bottom_left = 8
bundle_item.corner_radius_bottom_right = 8
bundle_item.border_width_left = 1
bundle_item.border_width_right = 1
bundle_item.border_width_top = 1
bundle_item.border_width_bottom = 1
bundle_item.border_color = Color(0.337, 0.514, 0.675, 0.15)
```

---

## 四、存档页面 (Save Tab) 重构

### 4.1 工具栏重构

**节点路径:** `TabContainer/SaveTab/TopBar`

- [ ] **Step 1: 修改按钮组**

按钮列表及样式:
- `ImportSaveBtn`: "📥 导入存档"
- `ExportSaveBtn`: "📤 导出存档"
- `BackupSaveBtn`: "💾 备份"
- `RestoreSaveBtn`: "♻️ 恢复"
- `OverwriteSaveBtn`: "⚠️ 覆盖"

### 4.2 左侧面板重构 (Steam账号列表)

**节点路径:** `TabContainer/SaveTab/SaveContainer/LeftPanelWrapper/LeftPanelList/SaveScroll/SaveList`

- [ ] **Step 1: 创建账号卡片样式**

每个账号卡片结构:
```xml
<PanelContainer name="Account_76561197960287930">
	<VBoxContainer>
		<HBoxContainer name="Header">
			<Label text="🎮 76561197960287930"/>
			<Button name="DeleteBtn" text="✕" custom_size="Vector2(20, 20)"/>
		</HBoxContainer>
		<HBoxContainer name="TypeTabs">
			<Button name="VanillaTab" text="原版"/>
			<Button name="ModdedTab" text="模组"/>
		</HBoxContainer>
		<VBoxContainer name="Profiles">
			<Button name="Profile1" text="profile1"/>
			<Button name="Profile2" text="profile2"/>
			<Button name="Profile3" text="profile3"/>
		</VBoxContainer>
	</VBoxContainer>
</PanelContainer>
```

- [ ] **Step 2: 添加导入存档分组**

```xml
<PanelContainer name="ImportedSave_玩家备份_001">
	<VBoxContainer>
		<HBoxContainer name="Header">
			<Label text="📥 玩家备份_001"/>
			<Button name="DeleteBtn" text="✕"/>
		</HBoxContainer>
		<HBoxContainer name="TypeTabs">
			<Button name="VanillaTab" text="原版"/>
			<Button name="ModdedTab" text="模组"/>
		</HBoxContainer>
		<VBoxContainer name="Profiles">
			<Button name="Profile1" text="profile1"/>
		</VBoxContainer>
	</VBoxContainer>
</PanelContainer>
```

- [ ] **Step 3: 添加分隔线**

在Steam账号和导入存档之间添加:
```xml
<Label name="Divider" text="──────── 导入的存档 ────────" align="center"/>
```

### 4.3 删除按钮样式

- [ ] **Step 1: 实现悬停显示删除按钮**

```gdscript
# 在账号卡片的脚本中
func _ready():
	delete_btn.visible = false
	gui_input.connect(_on_input)

func _on_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			delete_btn.visible = event.pressed or is_mouse_hovered

func _on_mouse_entered():
	delete_btn.visible = true

func _on_mouse_exited():
	delete_btn.visible = false
```

样式:
- 默认: 不可见
- 悬停: opacity 0.6
- 悬停+点击: opacity 1.0, 背景 rgba(239,68,68,0.2), 文字 #ef4444

### 4.4 右侧详情面板重构

**节点路径:** `TabContainer/SaveTab/SaveContainer/RightPanel/SaveDetailsPanel`

- [ ] **Step 1: 角色选择网格**

```xml
<GridContainer name="CharacterGrid" columns="4">
	<TextureButton name="Char_Ironclad" tooltip="铁甲战士"/>
	<TextureButton name="Char_Silent" tooltip="静默猎手"/>
	<TextureButton name="Char_Regent" tooltip="储君"/>
	<TextureButton name="Char_Necrobinder" tooltip="亡灵契约师"/>
</GridContainer>
```

- [ ] **Step 2: 存档信息卡片**

```xml
<GridContainer name="SaveInfoGrid" columns="3">
	<VBoxContainer>
		<Label text="完成关卡"/>
		<Label id="floor_count" text="35"/>
	</VBoxContainer>
	<VBoxContainer>
		<Label text="总游戏时间"/>
		<Label id="play_time" text="12h 30m"/>
	</VBoxContainer>
	<VBoxContainer>
		<Label text="最后存档"/>
		<Label id="last_save" text="2小时前"/>
	</VBoxContainer>
</GridContainer>
```

- [ ] **Step 3: 移除操作按钮**

根据要求，删除详情面板中的读取/备份/复制/删除按钮

---

## 五、下载页面 (Download Tab) 重构

### 5.1 工具栏重构

**节点路径:** `TabContainer/DownloadTab/DownloadPanel/DownloadVBox/ActiveDownloadsSection/ActiveDownloadsHeader`

- [ ] **Step 1: 搜索框**

```xml
<LineEdit name="DownloadSearch" placeholder="搜索下载..."/>
```

- [ ] **Step 2: 筛选标签**

```xml
<HBoxContainer name="FilterTags">
	<Button name="AllTag" text="全部" toggle_mode="true" button_pressed="true"/>
	<Button name="ActiveTag" text="进行中" toggle_mode="true"/>
	<Button name="DoneTag" text="已完成" toggle_mode="true"/>
</HBoxContainer>
```

样式:
- 选中: background rgba(102,192,249,0.2), 文字 #66c0f9
- 未选中: 文字灰色

### 5.2 下载列表项重构

- [ ] **Step 1: 创建下载项样式**

```xml
<PanelContainer name="DownloadItem">
	<HBoxContainer>
		<TextureRect name="Icon"/>
		<VBoxContainer name="Info">
			<Label name="Name"/>
			<ProgressBar name="Progress" custom_minimum_size="Vector2(0, 4)"/>
			<Label name="Status"/>
		</VBoxContainer>
		<Button name="ActionBtn"/>
	</HBoxContainer>
</PanelContainer>
```

- [ ] **Step 2: 进度条样式**

```gdscript
var progress_bg = StyleBoxFlat.new()
progress_bg.bg_color = Color(0.165, 0.278, 0.369, 0.5)
progress_bg.corner_radius_top_left = 2
progress_bg.corner_radius_top_right = 2
progress_bg.corner_radius_bottom_left = 2
progress_bg.corner_radius_bottom_right = 2

var progress_fill = StyleBoxFlat.new()
progress_fill.bg_color = COLORS.accent
```

---

## 六、Nexus页面重构

### 6.1 工具栏重构

- [ ] **Step 1: 搜索框 + 分类标签**

```xml
<LineEdit name="NexusSearch" placeholder="搜索Nexus..."/>
<HBoxContainer name="Categories">
	<Button name="HotBtn" text="热门" toggle_mode="true" button_pressed="true"/>
	<Button name="NewBtn" text="新增" toggle_mode="true"/>
	<Button name="UpdatedBtn" text="更新" toggle_mode="true"/>
</HBoxContainer>
```

### 6.2 模组卡片网格

- [ ] **Step 1: 创建卡片布局**

```xml
<GridContainer name="NexusGrid" columns="3">
	<PanelContainer name="ModCard">
		<VBoxContainer>
			<TextureRect name="Preview"/>
			<Label name="Name"/>
			<Label name="Author"/>
			<Label name="Downloads"/>
		</VBoxContainer>
	</PanelContainer>
</GridContainer>
```

---

## 七、设置页面 (Settings Tab) 重构

### 7.1 左侧导航栏

**节点路径:** `TabContainer/SettingsTab/SettingsScroll/SettingsVBox`

- [ ] **Step 1: 创建侧边栏样式**

```xml
<VBoxContainer name="SettingsSidebar" custom_minimum_size="Vector2(140, 0)">
	<Button name="GeneralNav" text="通用"/>
	<Button name="PathsNav" text="游戏路径"/>
	<Button name="LanguageNav" text="语言"/>
	<Button name="LaunchNav" text="启动选项"/>
	<Button name="AboutNav" text="关于"/>
</VBoxContainer>
```

### 7.2 各设置分组

- [ ] **Step 1: 路径设置**

```xml
<VBoxContainer name="PathsSection">
	<Label text="游戏路径"/>
	<HBoxContainer>
		<LineEdit name="GamePathEdit"/>
		<Button name="BrowseBtn" text="浏览"/>
		<Button name="DetectBtn" text="自动检测"/>
	</HBoxContainer>
</VBoxContainer>
```

- [ ] **Step 2: 语言设置**

```xml
<VBoxContainer name="LanguageSection">
	<Label text="语言"/>
	<OptionButton name="LanguageOption">
		<item text="简体中文" id="zh_CN"/>
		<item text="English" id="en_US"/>
	</OptionButton>
</VBoxContainer>
```

- [ ] **Step 3: Toggle开关样式**

```gdscript
var toggle_on = StyleBoxFlat.new()
toggle_on.bg_color = COLORS.accent
toggle_on.corner_radius_top_left = 11
toggle_on.corner_radius_top_right = 11
toggle_on.corner_radius_bottom_left = 11
toggle_on.corner_radius_bottom_right = 11

var toggle_off = StyleBoxFlat.new()
toggle_off.bg_color = Color(0.165, 0.278, 0.369, 0.8)
# 同样圆角
```

---

## 八、验证清单

### 8.1 颜色验证
- [ ] 背景深色: #1b2838
- [ ] 背景浅色: #12171e
- [ ] 强调色: #66c0f9
- [ ] 文字主色: #c7d5e0
- [ ] 文字次色: #8b98a0
- [ ] 边框色: rgba(86,131,172,0.3)

### 8.2 交互验证
- [ ] 所有按钮悬停效果
- [ ] 所有Toggle开关动画
- [ ] Tesla启动按钮拖拽交互
- [ ] 存档卡片删除按钮悬停显示

### 8.3 功能验证
- [ ] 模组列表搜索过滤
- [ ] 模组启用/禁用
- [ ] 存档选择切换
- [ ] 游戏启动模式选择
- [ ] 设置保存

### 8.4 视觉验证
- [ ] 圆角一致性 (所有卡片8px, 按钮6px)
- [ ] 间距一致性 (20px/16px/12px/8px)
- [ ] 字体大小规范
- [ ] 选中状态高亮

---

## 执行顺序

**Task 1: 全局主题设置** (P0)
- 设置颜色常量
- 创建Theme资源
- 应用全局样式

**Task 2: 模组页面** (P0)
- TopBar重构
- ModList重构
- ModDetailsPanel重构
- Tesla启动按钮

**Task 3: 整合包页面** (P1)
- 工具栏按钮样式
- 列表项样式

**Task 4: 存档页面** (P1)
- 账号列表重构
- 角色选择网格
- 删除按钮逻辑

**Task 5: 下载页面** (P2)
- 搜索和筛选
- 下载项样式

**Task 6: Nexus页面** (P2)
- 搜索和分类
- 卡片网格

**Task 7: 设置页面** (P2)
- 侧边栏导航
- 各设置分组样式
