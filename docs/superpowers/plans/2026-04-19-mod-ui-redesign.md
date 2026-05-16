# 模组界面 UI 重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将模组管理器的模组界面从当前基础风格升级为 Steam × Windows 11 混合风格，包含 Tesla 风格拖拽启动按钮。

**Architecture:** 修改 `modmanager.gd` 中的样式函数（`_apply_topbar_theme`, `_apply_modlist_theme`, `_apply_moddetails_theme`），在 `modmanager.tscn` 中添加启动模式 tab 和工具栏背景，新建 `ui/launch_bar.gd/tscn` 实现 Tesla 启动按钮。

**Tech Stack:** Godot 4.5.1, GDScript, StyleBoxFlat

---

## 文件结构

### 需要修改的文件
- `modmanager.gd` - 修改样式函数，添加分类标签逻辑，添加启动模式切换
- `modmanager.tscn` - 添加工具栏背景容器、启动模式 tab、分类标签按钮
- `ui/mod_item.gd` - 改进图标渐变、选中状态样式
- `ui/mod_details.gd` - 改进 Badge 渐变、备注区样式

### 需要新建的文件
- `ui/launch_bar.gd` - Tesla 启动按钮组件脚本
- `ui/launch_bar.tscn` - Tesla 启动按钮场景

---

## 颜色常量定义

在 `modmanager.gd` 中已定义以下常量（可直接使用）：

```gdscript
# 全局颜色常量 (Steam×Windows 11混合风格)
const COLORS = {
    "bg_deep": Color(0.106, 0.157, 0.22),       # #1b2838
    "bg_light": Color(0.071, 0.09, 0.118),      # #12171e
    "accent": Color(0.4, 0.753, 0.976),        # #66c0f9
    "accent_dark": Color(0.165, 0.278, 0.369), # #2a475e
    "text_primary": Color(0.78, 0.835, 0.878), # #c7d5e0
    "text_secondary": Color(0.545, 0.596, 0.627), # #8b98a0
    "border": Color(0.337, 0.514, 0.675, 0.3),
    "hover": Color(0.4, 0.753, 0.976, 0.15),
}

const FUNC_COLORS = {
    "gameplay": Color(0.957, 0.447, 0.714),   # #f472b6
    "cosmetic": Color(0.063, 0.725, 0.506),    # #10b981
    "success": Color(0.29, 0.87, 0.5),
    "warning": Color(1, 0.663, 0.251)
}
```

---

## Task 1: 重构工具栏背景和结构

**Files:**
- Modify: `modmanager.tscn` (添加工具栏背景 PanelContainer)
- Modify: `modmanager.gd:3937-3974` (修改 `_apply_topbar_theme` 函数)

- [ ] **Step 1: 在 modmanager.tscn 中为 TopBar 添加背景容器**

找到 TopBar 节点，在其外层添加一个 PanelContainer 作为工具栏背景：

```xml
[node name="TopBarBg" type="PanelContainer" parent="TabContainer/ModTab/TopVBox"]
layout_mode = 2
theme_override_constants/margin_left = 12
theme_override_constants/margin_right = 12
theme_override_constants/margin_top = 10
theme_override_constants/margin_bottom = 10

[node name="TopBar" type="HBoxContainer" parent="TabContainer/ModTab/TopVBox/TopBarBg"]
layout_mode = 2
theme_override_constants/separation = 10
```

- [ ] **Step 2: 修改 _apply_topbar_theme 函数 - 添加工具栏背景样式**

替换 `modmanager.gd` 中 `_apply_topbar_theme` 函数中的工具栏样式部分（约第 3937-3953 行）：

```gdscript
    # ===== 工具栏背景容器 =====
    var topbar_bg = find_child_node(self, "TopBarBg")
    if topbar_bg:
        var toolbar_bg_style = StyleBoxFlat.new()
        toolbar_bg_style.bg_color = Color(0.082, 0.122, 0.18, 0.5)  # rgba(21,31,46,0.5)
        toolbar_bg_style.corner_radius_top_left = 8
        toolbar_bg_style.corner_radius_top_right = 8
        toolbar_bg_style.corner_radius_bottom_left = 8
        toolbar_bg_style.corner_radius_bottom_right = 8
        toolbar_bg_style.border_width_left = 1
        toolbar_bg_style.border_width_right = 1
        toolbar_bg_style.border_width_top = 1
        toolbar_bg_style.border_width_bottom = 1
        toolbar_bg_style.border_color = Color(0.337, 0.514, 0.675, 0.15)
        topbar_bg.add_theme_stylebox_override("panel", toolbar_bg_style)
```

- [ ] **Step 3: 更新 TopBar 引用 - 从 TopBarBg 获取子节点**

修改 `_apply_modlist_theme` 函数中对 `TopBar` 的查找路径：

```gdscript
    # 修改前
    var topbar = find_child_node(self, "TopBar")

    # 修改后
    var topbar_bg = find_child_node(self, "TopBarBg")
    if topbar_bg:
        var topbar = topbar_bg  # TopBar 现在是 TopBarBg 的子节点
```

实际上，由于 TopBar 现在嵌套在 TopBarBg 内部，需要更新所有引用 `TopBar` 的地方为 `TopBarBg/TopBar`。

- [ ] **Step 4: 调整 TopVBox 的 offset**

更新 TopVBox 的布局，确保工具栏背景正确显示：

```xml
# 在 TopVBox 中添加底部 offset
offset_bottom = -118.0  # 保持原有值
```

- [ ] **Step 5: 提交更改**

```bash
git add modmanager.gd modmanager.tscn
git commit -m "refactor: 重构工具栏背景容器，添加圆角边框样式"
```

---

## Task 2: 添加分类标签筛选按钮

**Files:**
- Modify: `modmanager.tscn` (在 TopBar 中添加分类标签容器)
- Modify: `modmanager.gd` (添加分类标签样式和逻辑)

- [ ] **Step 1: 在 modmanager.tscn 的 TopBar 中添加分类标签容器**

在 TopBar 中 SearchBox 和 FilterDropdown 之间添加：

```xml
[node name="CategoryTags" type="HBoxContainer" parent="TabContainer/ModTab/TopVBox/TopBarBg/TopBar"]
layout_mode = 2
theme_override_constants/separation = 6

[node name="TagAll" type="Button" parent="TabContainer/ModTab/TopVBox/TopBarBg/TopBar/CategoryTags"]
layout_mode = 2
text = "全部"
toggle_mode = true
button_pressed = true

[node name="TagGameplay" type="Button" parent="TabContainer/ModTab/TopVBox/TopBarBg/TopBar/CategoryTags"]
layout_mode = 2
text = "游戏性"
toggle_mode = true

[node name="TagCosmetic" type="Button" parent="TabContainer/ModTab/TopVBox/TopBarBg/TopBar/CategoryTags"]
layout_mode = 2
text = "美化"
toggle_mode = true
```

- [ ] **Step 2: 在 modmanager.gd 中添加分类标签状态变量**

在文件开头的变量声明区域添加：

```gdscript
var current_category_filter: String = "all"  # "all", "gameplay", "cosmetic"
```

- [ ] **Step 3: 添加 _apply_category_tags_theme 函数**

在 `_apply_modlist_theme` 函数之后添加：

```gdscript
func _apply_category_tags_theme() -> void:
    """应用分类标签按钮样式 - 激活态带有边框高亮"""
    var category_tags = find_child_node(self, "CategoryTags")
    if not category_tags:
        return

    for ch in category_tags.get_children():
        if ch is Button:
            # 默认样式
            var normal_style = StyleBoxFlat.new()
            normal_style.bg_color = Color(0.165, 0.278, 0.369, 0.4)
            normal_style.corner_radius_top_left = 6
            normal_style.corner_radius_top_right = 6
            normal_style.corner_radius_bottom_left = 6
            normal_style.corner_radius_bottom_right = 6
            normal_style.border_width_left = 1
            normal_style.border_width_right = 1
            normal_style.border_width_top = 1
            normal_style.border_width_bottom = 1
            normal_style.border_color = Color(0.337, 0.514, 0.675, 0.3)

            # 激活样式
            var active_style = StyleBoxFlat.new()
            active_style.bg_color = Color(0.4, 0.753, 0.976, 0.2)
            active_style.corner_radius_top_left = 6
            active_style.corner_radius_top_right = 6
            active_style.corner_radius_bottom_left = 6
            active_style.corner_radius_bottom_right = 6
            active_style.border_width_left = 1
            active_style.border_width_right = 1
            active_style.border_width_top = 1
            active_style.border_width_bottom = 1
            active_style.border_color = COLORS.accent

            ch.add_theme_stylebox_override("normal", normal_style)
            ch.add_theme_stylebox_override("hover", normal_style)
            ch.add_theme_stylebox_override("pressed", active_style)
            ch.add_theme_color_override("font_color", Color(0.545, 0.596, 0.627))  # 灰色

            # 存储样式引用供切换使用
            ch.set_meta("normal_style", normal_style)
            ch.set_meta("active_style", active_style)
```

- [ ] **Step 4: 添加分类标签点击处理函数**

```gdscript
func _on_category_tag_clicked(tag_name: String) -> void:
    """处理分类标签点击"""
    var category_tags = find_child_node(self, "CategoryTags")
    if not category_tags:
        return

    # 确定新的筛选类别
    var new_category = "all"
    if "Gameplay" in tag_name:
        new_category = "gameplay"
    elif "Cosmetic" in tag_name:
        new_category = "cosmetic"

    current_category_filter = new_category

    # 更新按钮状态
    for ch in category_tags.get_children():
        if ch is Button:
            var is_active = false
            if "All" in ch.name and new_category == "all":
                is_active = true
            elif "Gameplay" in ch.name and new_category == "gameplay":
                is_active = true
            elif "Cosmetic" in ch.name and new_category == "cosmetic":
                is_active = true

            if is_active:
                ch.add_theme_stylebox_override("normal",
                    ch.get_meta("active_style"))
                ch.add_theme_color_override("font_color", COLORS.accent)
            else:
                ch.add_theme_stylebox_override("normal",
                    ch.get_meta("normal_style"))
                ch.add_theme_color_override("font_color",
                    Color(0.545, 0.596, 0.627))

    # 过滤模组列表
    _filter_mods_by_category()
```

- [ ] **Step 5: 添加 _filter_mods_by_category 函数**

```gdscript
func _filter_mods_by_category() -> void:
    """根据当前分类筛选器过滤模组列表"""
    var mod_list = find_child_node(self, "ModList")
    if not mod_list:
        return

    for child in mod_list.get_children():
        if child is ModItem:
            var mod_data = child.mod_data
            var affects_gameplay = mod_data.get("affects_gameplay", false)

            var should_show = true
            match current_category_filter:
                "gameplay":
                    should_show = affects_gameplay
                "cosmetic":
                    should_show = not affects_gameplay
                _:
                    should_show = true

            child.visible = should_show
```

- [ ] **Step 6: 在 _apply_steam_theme 中调用新函数**

找到 `_apply_steam_theme` 函数，添加调用：

```gdscript
    # 应用分类标签样式
    _apply_category_tags_theme()
```

- [ ] **Step 7: 连接分类标签信号**

在 `_ready` 或初始化函数中添加：

```gdscript
    # 连接分类标签信号
    var category_tags = find_child_node(self, "CategoryTags")
    if category_tags:
        for ch in category_tags.get_children():
            if ch is Button:
                ch.button_up.connect(_on_category_tag_clicked.bind(ch.name))
```

- [ ] **Step 8: 提交更改**

```bash
git add modmanager.gd modmanager.tscn
git commit -m "feat: 添加模组分类标签筛选按钮（全部/游戏性/美化）"
```

---

## Task 3: 添加启动模式切换 Tab

**Files:**
- Modify: `modmanager.tscn` (在 LeftPanel 和 RightPanel 之间添加启动模式容器)
- Modify: `modmanager.gd` (添加启动模式切换逻辑)

- [ ] **Step 1: 在 modmanager.tscn 中添加启动模式切换区域**

在 HSplitContainer 的 LeftPanel 之前添加：

```xml
[node name="ModStartModes" type="HBoxContainer" parent="TabContainer/ModTab"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_top = 118.0
offset_bottom = 158.0
grow_horizontal = 2
grow_vertical = 0
theme_override_constants/separation = 0

[node name="StartModeSpacer" type="Control" parent="TabContainer/ModTab/ModStartModes"]
layout_mode = 2
size_flags_horizontal = 3

[node name="ModeSingleplayer" type="Button" parent="TabContainer/ModTab/ModStartModes"]
layout_mode = 2
text = "单机模组"
toggle_mode = true
button_pressed = true

[node name="ModeMultiplayer" type="Button" parent="TabContainer/ModTab/ModStartModes"]
layout_mode = 2
text = "联机模组"
toggle_mode = true

[node name="ModeCustom" type="Button" parent="TabContainer/ModTab/ModStartModes"]
layout_mode = 2
text = "自定义预设"
toggle_mode = true

[node name="ModeSpacerRight" type="Control" parent="TabContainer/ModTab/ModStartModes"]
layout_mode = 2
size_flags_horizontal = 3
custom_minimum_size = Vector2(0, 0)
```

- [ ] **Step 2: 调整 HSplit 的 offset**

修改 HSplit 的 `offset_top` 从 118.0 改为 158.0（预留启动模式栏高度 40px）：

```xml
[node name="HSplit" type="HSplitContainer" parent="TabContainer/ModTab"]
offset_top = 158.0  # 从 118.0 改为 158.0
```

- [ ] **Step 3: 添加启动模式样式函数**

在 `modmanager.gd` 中添加：

```gdscript
var current_launch_mode: String = "singleplayer"  # "singleplayer", "multiplayer", "custom"

func _apply_start_modes_theme() -> void:
    """应用启动模式切换按钮样式"""
    var start_modes = find_child_node(self, "ModStartModes")
    if not start_modes:
        return

    # 底部边框
    var border_style = StyleBoxFlat.new()
    border_style.bg_color = Color(0, 0, 0, 0)
    border_style.border_width_top = 1
    border_style.border_color = Color(0.337, 0.514, 0.675, 0.15)
    start_modes.add_theme_stylebox_override("panel", border_style)

    for ch in start_modes.get_children():
        if ch is Button:
            # 基础样式（未激活）
            var normal_style = StyleBoxFlat.new()
            normal_style.bg_color = Color(0, 0, 0, 0)
            normal_style.border_width_bottom = 2
            normal_style.border_color = Color(0, 0, 0, 0)  # 透明

            # 激活样式
            var active_style = StyleBoxFlat.new()
            active_style.bg_color = Color(0, 0, 0, 0)
            active_style.border_width_bottom = 2
            active_style.border_color = COLORS.accent

            ch.add_theme_stylebox_override("normal", normal_style)
            ch.add_theme_stylebox_override("hover", normal_style)
            ch.add_theme_stylebox_override("pressed", active_style)
            ch.add_theme_color_override("font_color", Color(0.545, 0.596, 0.627))  # 灰色
            ch.add_theme_color_override("font_hover_color", Color(0.78, 0.835, 0.878))  # 悬停白色

            ch.set_meta("normal_style", normal_style)
            ch.set_meta("active_style", active_style)

    # 设置默认激活按钮
    _update_start_mode_buttons("ModeSingleplayer")
```

- [ ] **Step 4: 添加 _update_start_mode_buttons 函数**

```gdscript
func _update_start_mode_buttons(active_btn_name: String) -> void:
    """更新启动模式按钮激活状态"""
    var start_modes = find_child_node(self, "ModStartModes")
    if not start_modes:
        return

    for ch in start_modes.get_children():
        if ch is Button:
            if ch.name == active_btn_name:
                ch.add_theme_stylebox_override("normal", ch.get_meta("active_style"))
                ch.add_theme_color_override("font_color", Color.WHITE)
            else:
                ch.add_theme_stylebox_override("normal", ch.get_meta("normal_style"))
                ch.add_theme_color_override("font_color", Color(0.545, 0.596, 0.627))
```

- [ ] **Step 5: 添加启动模式点击处理函数**

```gdscript
func _on_start_mode_clicked(btn_name: String) -> void:
    """处理启动模式切换"""
    current_launch_mode = "singleplayer"
    if "Multiplayer" in btn_name:
        current_launch_mode = "multiplayer"
    elif "Custom" in btn_name:
        current_launch_mode = "custom"

    _update_start_mode_buttons(btn_name)

    # 通知用户切换
    print("[Launch Mode] Switched to: ", current_launch_mode)
```

- [ ] **Step 6: 在 _apply_steam_theme 中调用新函数**

```gdscript
    # 应用启动模式样式
    _apply_start_modes_theme()
```

- [ ] **Step 7: 连接启动模式信号**

```gdscript
    # 连接启动模式信号
    var start_modes = find_child_node(self, "ModStartModes")
    if start_modes:
        for ch in start_modes.get_children():
            if ch is Button:
                ch.button_up.connect(_on_start_mode_clicked.bind(ch.name))
```

- [ ] **Step 8: 提交更改**

```bash
git add modmanager.gd modmanager.tscn
git commit -m "feat: 添加模组启动模式切换tab（单机/联机/自定义）"
```

---

## Task 4: 改进模组列表项样式

**Files:**
- Modify: `ui/mod_item.gd` (改进图标渐变和选中状态)

- [ ] **Step 1: 修改图标渐变效果**

在 `mod_item.gd` 的 `setup` 函数中，将纯色图标改为渐变效果。由于 Godot 的 ColorRect 不直接支持渐变，需要用 Shader 或调整视觉效果。暂时通过添加边框来实现：

```gdscript
func setup(data: Dictionary, enabled: bool = false) -> void:
    mod_data = data
    is_toggled_on = enabled
    _update_toggle_visual(enabled)

    name_lbl.text = data.get("name", "Unknown")
    var author = data.get("author", "Unknown")
    var version = data.get("version", "v1.0")
    author_lbl.text = "%s • %s" % [author, version]

    # 设置图标颜色和边框
    if data.get("affects_gameplay", false):
        icon_bg.color = Color(0.957, 0.447, 0.714)  # 游戏性 - 玫红
        _add_icon_gradient_overlay(icon_bg, FUNC_COLORS.gameplay)
    elif data.get("icon", "") == "cosmetic":
        icon_bg.color = Color(0.063, 0.725, 0.506)  # 美化 - 青色
        _add_icon_gradient_overlay(icon_bg, FUNC_COLORS.cosmetic)
    else:
        icon_bg.color = COLORS.accent
        _add_icon_gradient_overlay(icon_bg, COLORS.accent)
```

- [ ] **Step 2: 添加图标渐变叠加效果**

```gdscript
func _add_icon_gradient_overlay(icon: ColorRect, base_color: Color) -> void:
    """为图标添加渐变边框效果"""
    # 使用 StyleBoxFlat 模拟渐变边框
    var overlay = ColorRect.new()
    overlay.name = "IconOverlay"
    overlay.color = Color(base_color.r, base_color.g, base_color.b, 0.3)
    overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    # 覆盖在原图标上方
    icon.add_child(overlay)
    # 向下移动一层，让原有颜色透出
    overlay.lower = true
```

- [ ] **Step 3: 改进选中状态样式**

修改 `_update_selection_style` 函数：

```gdscript
func _update_selection_style() -> void:
    if is_selected:
        var selected_style = StyleBoxFlat.new()
        selected_style.bg_color = Color(0.4, 0.753, 0.976, 0.15)
        selected_style.corner_radius_top_left = 6
        selected_style.corner_radius_top_right = 6
        selected_style.corner_radius_bottom_left = 6
        selected_style.corner_radius_bottom_right = 6
        selected_style.border_width_left = 1
        selected_style.border_width_right = 1
        selected_style.border_width_top = 1
        selected_style.border_width_bottom = 1
        selected_style.border_color = Color(0.4, 0.753, 0.976, 0.3)
        bg.add_theme_stylebox_override("normal", selected_style)
    else:
        bg.add_theme_stylebox_override("normal", _make_bg_style(COL_BG_NORMAL))
```

- [ ] **Step 4: 提交更改**

```bash
git add ui/mod_item.gd
git commit -m "refactor: 改进模组列表项样式 - 添加选中边框效果"
```

---

## Task 5: 改进详情面板 Badge 和备注区样式

**Files:**
- Modify: `ui/mod_details.gd` (改进 Badge 渐变和备注区样式)

- [ ] **Step 1: 修改 Badge 创建函数，添加渐变效果**

在 `mod_details.gd` 中修改 `_add_badge` 函数：

```gdscript
func _add_badge(parent: HBoxContainer, text: String, col: Color) -> void:
    var badge_container = Control.new()
    badge_container.custom_minimum_size = Vector2(0, 24)

    # Badge 背景（渐变效果通过双层 ColorRect 实现）
    var bg = ColorRect.new()
    bg.color = Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.8)  # 深色版本

    var lbl = Label.new()
    lbl.text = " " + text + " "
    lbl.add_theme_color_override("font_color", Color.WHITE)
    lbl.add_theme_font_size_override("font_size", 10)

    # 使用 StyleBoxFlat 替代 ColorRect 以支持圆角和边框
    var badge_style = StyleBoxFlat.new()
    badge_style.bg_color = Color(col.r, col.g, col.b, 0.8)  # 半透明强调色
    badge_style.corner_radius_top_left = 4
    badge_style.corner_radius_top_right = 4
    badge_style.corner_radius_bottom_left = 4
    badge_style.corner_radius_bottom_right = 4

    # 创建 PanelContainer 承载样式
    var badge_panel = PanelContainer.new()
    badge_panel.add_theme_stylebox_override("normal", badge_style)
    badge_panel.add_theme_color_override("font_color_shadow", Color(0, 0, 0, 0.5))

    var margin = MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 8)
    margin.add_theme_constant_override("margin_right", 8)
    margin.add_theme_constant_override("margin_top", 4)
    margin.add_theme_constant_override("margin_bottom", 4)

    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

    margin.add_child(lbl)
    badge_panel.add_child(margin)
    parent.add_child(badge_panel)
```

- [ ] **Step 2: 改进备注区样式**

在 `setup` 函数中修改备注区样式：

```gdscript
    # 备注区样式
    var notes = mod_data.get("notes", "")
    if notes_bg:
        notes_bg.visible = not notes.is_empty()
        # 设置备注区背景样式
        if not notes_bg.get_theme_stylebox("panel"):
            var notes_style = StyleBoxFlat.new()
            notes_style.bg_color = Color(0.165, 0.278, 0.369, 0.15)
            notes_style.corner_radius_top_left = 6
            notes_style.corner_radius_top_right = 6
            notes_style.corner_radius_bottom_left = 6
            notes_style.corner_radius_bottom_right = 6
            notes_style.border_width_left = 1
            notes_style.border_width_right = 1
            notes_style.border_width_top = 1
            notes_style.border_width_bottom = 1
            notes_style.border_color = Color(0.337, 0.514, 0.675, 0.15)
            notes_bg.add_theme_stylebox_override("normal", notes_style)
```

- [ ] **Step 3: 添加备注 Header 样式**

```gdscript
    if notes_lbl:
        notes_lbl.add_theme_color_override("font_color", COL_ACCENT)
        notes_lbl.add_theme_font_size_override("font_size", 11)
        notes_lbl.text = "📝 " + notes_lbl.text
```

- [ ] **Step 4: 提交更改**

```bash
git add ui/mod_details.gd
git commit -m "refactor: 改进详情面板Badge和备注区样式"
```

---

## Task 6: 创建 Tesla 启动按钮组件

**Files:**
- Create: `ui/launch_bar.gd`
- Create: `ui/launch_bar.tscn`
- Modify: `modmanager.gd` (集成 Tesla 按钮)

- [ ] **Step 1: 创建 launch_bar.tscn 场景**

```xml
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" uid="uid://launch_bar" path="res://ui/launch_bar.gd" id="1"]

[node name="LaunchBar" type="Control"]
custom_minimum_size = Vector2(280, 40)
layout_mode = 3
anchors_preset = 10
anchor_right = 1.0
grow_horizontal = 2
script = ExtResource("1")

[node name="GearContainer" type="HBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -140.0
offset_top = -20.0
offset_right = 140.0
offset_bottom = 20.0
grow_horizontal = 2
grow_vertical = 2
alignment = 1

[node name="GearP" type="Label" parent="GearContainer"]
layout_mode = 2
text = "P"
horizontal_alignment = 1
vertical_alignment = 1

[node name="TrackLeft" type="ColorRect" parent="GearContainer"]
custom_minimum_size = Vector2(30, 2)
layout_mode = 2
size_flags_vertical = 4
color = Color(0.337, 0.514, 0.675, 0.3)

[node name="GearD" type="Label" parent="GearContainer"]
layout_mode = 2
text = "D"
horizontal_alignment = 1
vertical_alignment = 1

[node name="TrackMid1" type="ColorRect" parent="GearContainer"]
custom_minimum_size = Vector2(30, 2)
layout_mode = 2
size_flags_vertical = 4
color = Color(0.337, 0.514, 0.675, 0.3)

[node name="GearN" type="Label" parent="GearContainer"]
layout_mode = 2
text = "N"
horizontal_alignment = 1
vertical_alignment = 1

[node name="TrackMid2" type="ColorRect" parent="GearContainer"]
custom_minimum_size = Vector2(30, 2)
layout_mode = 2
size_flags_vertical = 4
color = Color(0.337, 0.514, 0.675, 0.3)

[node name="GearR" type="Label" parent="GearContainer"]
layout_mode = 2
text = "R"
horizontal_alignment = 1
vertical_alignment = 1

[node name="Knob" type="PanelContainer" parent="."]
custom_minimum_size = Vector2(28, 26)
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -14.0
offset_top = -13.0
offset_right = 14.0
offset_bottom = 13.0
grow_horizontal = 2
grow_vertical = 2
```

- [ ] **Step 2: 创建 launch_bar.gd 脚本**

```gdscript
extends Control

# Tesla 启动按钮组件

# 信号
signal launch_mode_selected(mode: String)

# 档位位置（相对于中心的偏移）
const GEAR_POSITIONS = {
    "P": -70.0,
    "D": -35.0,
    "N": 0.0,
    "R": 35.0
}

# 档位颜色
const GEAR_COLORS = {
    "P": Color(0.957, 0.447, 0.714),  # 玫红 - 联机
    "D": Color(0.4, 0.753, 0.976),   # 蓝色 - 模组
    "N": Color(0.063, 0.725, 0.506),  # 绿色 - 空档
    "R": Color(0.957, 0.447, 0.714)   # 玫红 - 原版
}

# 吸附范围
const SNAP_RANGE = 15.0

# 状态
var current_gear: String = "N"
var is_dragging: bool = false
var drag_start_x: float = 0.0
var knob_start_x: float = 0.0

# 节点引用
var knob: PanelContainer
var gear_labels: Dictionary = {}

func _ready() -> void:
    _setup_knob()
    _setup_gear_labels()
    _update_knob_position(0.0)
    _highlight_current_gear()

func _setup_knob() -> void:
    knob = find_child("Knob", true, false) as PanelContainer
    if knob:
        # 设置档位球样式
        var knob_style = StyleBoxFlat.new()
        knob_style.bg_color = Color(0.106, 0.157, 0.22)
        knob_style.corner_radius_top_left = 12
        knob_style.corner_radius_top_right = 12
        knob_style.corner_radius_bottom_left = 12
        knob_style.corner_radius_bottom_right = 12
        knob_style.border_width_left = 2
        knob_style.border_width_right = 2
        knob_style.border_width_top = 2
        knob_style.border_width_bottom = 2
        knob_style.border_color = GEAR_COLORS[current_gear]
        knob.add_theme_stylebox_override("normal", knob_style)

        # 连接鼠标信号
        knob.gui_input.connect(_on_knob_input)

func _setup_gear_labels() -> void:
    for gear_name in ["P", "D", "N", "R"]:
        var label = find_child("Gear" + gear_name, true, false) as Label
        if label:
            gear_labels[gear_name] = label
            label.add_theme_color_override("font_color",
                Color(0.545, 0.596, 0.627))  # 默认灰色

func _on_knob_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                is_dragging = true
                drag_start_x = get_global_mouse_position().x
                knob_start_x = knob.offset_left
            else:
                is_dragging = false
                _on_drag_end()

    elif event is InputEventMouseMotion and is_dragging:
        var mouse_x = get_global_mouse_position().x
        var delta_x = mouse_x - drag_start_x
        var new_offset = clamp(knob_start_x + delta_x, -80.0, 50.0)
        _update_knob_position(new_offset - knob.offset_left)
        _detect_gear(new_offset)

func _update_knob_position(delta_x: float) -> void:
    knob.offset_left += delta_x
    knob.offset_right -= delta_x

func _detect_gear(offset_x: float) -> void:
    for gear in GEAR_POSITIONS:
        if abs(offset_x - GEAR_POSITIONS[gear]) < SNAP_RANGE:
            if current_gear != gear:
                current_gear = gear
                _highlight_current_gear()
            return

func _highlight_current_gear() -> void:
    # 更新档位球颜色
    if knob:
        var knob_style = knob.get_theme_stylebox("normal") as StyleBoxFlat
        if knob_style:
            knob_style.border_color = GEAR_COLORS[current_gear]

    # 更新档位标签颜色
    for gear_name in gear_labels:
        var label = gear_labels[gear_name]
        if gear_name == current_gear:
            label.add_theme_color_override("font_color", GEAR_COLORS[gear_name])
        else:
            label.add_theme_color_override("font_color",
                Color(0.545, 0.596, 0.627))

func _on_drag_end() -> void:
    if current_gear != "N":
        # 吸附到档位并启动
        _snap_to_gear(current_gear)
        emit_signal("launch_mode_selected", current_gear)
        print("[LaunchBar] Launch mode: ", current_gear)
    else:
        # 弹回 N
        _return_to_neutral()

func _snap_to_gear(gear: String) -> void:
    var target_offset = GEAR_POSITIONS[gear]
    var current_offset = knob.offset_left + 14  # 居中偏移

    var tween = create_tween()
    tween.set_ease(Tween.EASE_OUT)
    tween.tween_method(
        func(x): knob.offset_left = x - 14; knob.offset_right = -x + 14,
        current_offset,
        target_offset + 14,
        0.15
    )

func _return_to_neutral() -> void:
    var current_offset = knob.offset_left + 14
    var tween = create_tween()
    tween.set_ease(Tween.EASE_BACK)
    tween.set_overshoot(1.3)
    tween.tween_method(
        func(x): knob.offset_left = x - 14; knob.offset_right = -x + 14,
        current_offset,
        GEAR_POSITIONS["N"] + 14,
        0.3
    )
    current_gear = "N"
    _highlight_current_gear()
```

- [ ] **Step 3: 在 modmanager.gd 中集成 Tesla 按钮**

添加引用和初始化：

```gdscript
var launch_bar: Control  # Tesla 启动按钮
var current_launch_mode: String = "singleplayer"  # 添加到已有变量附近
```

添加初始化函数：

```gdscript
func _init_launch_bar() -> void:
    """初始化 Tesla 启动按钮"""
    var launch_bar_placeholder = find_child_node(self, "LaunchBarPlaceholder")
    if launch_bar_placeholder:
        var launch_bar_scene = preload("res://ui/launch_bar.tscn")
        launch_bar = launch_bar_scene.instantiate()
        launch_bar.name = "LaunchBar"
        launch_bar_placeholder.add_child(launch_bar)

        # 连接信号
        if launch_bar.has_signal("launch_mode_selected"):
            launch_bar.launch_mode_selected.connect(_on_launch_mode_selected)

func _on_launch_mode_selected(mode: String) -> void:
    """处理 Tesla 按钮选择的启动模式"""
    print("[ModManager] Launch mode selected: ", mode, " (UI: ", current_launch_mode, ")")

    # 构建启动参数
    var launch_args = {
        "mode": mode,
        "ui_mode": current_launch_mode,
        "enabled_mods": _get_enabled_mods_list()
    }

    # 调用游戏启动逻辑
    _launch_game_with_mods(launch_args)
```

- [ ] **Step 4: 在 _ready 或初始化中调用 _init_launch_bar**

找到 `_ready` 或初始化函数，添加调用：

```gdscript
    # 初始化 Tesla 启动按钮
    _init_launch_bar()
```

- [ ] **Step 5: 提交更改**

```bash
git add ui/launch_bar.gd ui/launch_bar.tscn modmanager.gd
git commit -m "feat: 添加Tesla风格启动按钮组件"
```

---

## Task 7: 整合测试和最终调整

- [ ] **Step 1: 运行 Godot 编辑器测试**

```bash
cd E:\modmanager_project\sts-2-modmanager
godot --path . --editor
```

或在 Godot 编辑器中打开项目，按 F5 运行。

- [ ] **Step 2: 验证各项功能**

检查清单：
- [ ] 工具栏背景显示正确（圆角边框）
- [ ] 分类标签按钮可点击且样式正确
- [ ] 启动模式切换 tab 显示正确
- [ ] 模组列表项图标颜色正确
- [ ] 模组选中状态有边框高亮
- [ ] 详情面板 Badge 显示渐变效果
- [ ] 备注区样式正确
- [ ] Tesla 启动按钮可拖拽

- [ ] **Step 3: 修复发现的问题**

根据测试结果修复任何样式或功能问题。

- [ ] **Step 4: 最终提交**

```bash
git add -A
git commit -m "feat: 完成模组界面UI重构 - Steam×Win11混合风格"
```

---

## 验证清单

### 样式验证
- [ ] 背景深色: #1b2838 / Color(0.106, 0.157, 0.22)
- [ ] 背景浅色: #12171e / Color(0.071, 0.09, 0.118)
- [ ] 强调色: #66c0f9 / Color(0.4, 0.753, 0.976)
- [ ] 工具栏圆角: 8px
- [ ] 按钮圆角: 6px
- [ ] 列表项间距: 6px

### 功能验证
- [ ] 分类标签筛选工作正常
- [ ] 启动模式切换工作正常
- [ ] Tesla 按钮拖拽和吸附工作正常
- [ ] 游戏启动逻辑正确传递参数

### 交互验证
- [ ] 按钮悬停效果
- [ ] Toggle 开关动画
- [ ] Tesla 档位拖拽回弹动画
