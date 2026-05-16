# DPI 自适应缩放实现计划

**Goal:** 在高分辨率屏幕上自动放大 UI，允许用户手动调整缩放比例。

**Architecture:** 在 `modmanager.gd` 中新增 `dpi_scale` 变量和缩放方法，设置面板增加滑块控件，config.cfg 持久化缩放值。

**Tech Stack:** Godot 4.5 GDScript, ConfigFile, DisplayServer

---

## 文件清单

| 文件 | 改动 |
|------|------|
| `modmanager.gd` | 新增缩放变量、检测逻辑、apply 方法 |
| `locales/zh_CN.json` | 新增翻译字符串 |
| `locales/en_US.json` | 新增翻译字符串 |
| `modmanager.tscn` | 设置面板增加缩放滑块 UI |

---

## Task 1: 添加 dpi_scale 变量和常量

**文件**: `modmanager.gd`

- [ ] 在 `FONT_SIZES` 常量定义下方（约第32行后）添加：

```gdscript
# DPI 缩放
const DPI_SCALE_MIN: float = 0.8
const DPI_SCALE_MAX: float = 2.0
const DPI_SCALE_STEP: float = 0.05
var dpi_scale: float = 1.0  # 当前缩放因子
```

---

## Task 2: 添加自动检测和缩放应用方法

**文件**: `modmanager.gd`

- [ ] 在文件末尾（`func load_config()` 之前）添加以下方法：

```gdscript
# 检测 DPI 并返回合适的缩放因子
func _detect_dpi_scale() -> float:
    var screen_dpi = DisplayServer.screen_get_dpi()
    print("[_detect_dpi_scale] Screen DPI: ", screen_dpi)
    if screen_dpi >= 192:
        return 1.5
    elif screen_dpi >= 144:
        return 1.25
    return 1.0

# 应用全局缩放到字体大小
func _apply_font_scale() -> void:
    # 通过动态设置主题覆盖字体大小
    var theme = Theme.new()
    var base_font = ThemeDB.fallback_font
    for size_key in FONT_SIZES:
        var size = int(FONT_SIZES[size_key] * dpi_scale)
        theme.set_font_size(size_key + "_font_size", "", size)
    # 应用主题到根节点
    if has_node("/root/Control"):
        get_node("/root/Control").theme = theme

# 计算缩放后的间距
func get_scaled_spacing(key: String) -> int:
    var base = SPACING.get(key, 8)
    return int(base * dpi_scale)
```

- [ ] 在 `load_config()` 函数中加载 dpi_scale（约第1781行后，settings 默认值设置区域）添加：

```gdscript
config.set_value("settings", "dpi_scale", 1.0)
```

- [ ] 在 `load_config()` 读取 settings 区域（约第1798行附近）添加：

```gdscript
dpi_scale = config.get_value("settings", "dpi_scale", 0.0)
```

- [ ] 在 `load_config()` 末尾，`load_locale()` 之前添加自动检测逻辑：

```gdscript
# 如果 dpi_scale 为 0 或未设置，执行自动检测
if dpi_scale <= 0.0:
    dpi_scale = _detect_dpi_scale()
    print("[load_config] Auto-detected dpi_scale: ", dpi_scale)

# 应用初始缩放
_apply_font_scale()
```

---

## Task 3: 添加设置 UI 缩放滑块

**文件**: `modmanager.gd`

- [ ] 在变量声明区域（约第486行附近，`var language_option: OptionButton` 之后）添加：

```gdscript
var dpi_scale_slider: HSlider
var dpi_scale_value_label: Label
```

- [ ] 在 `_init_settings_ui_if_needed()` 中设置节点引用（约第8891行后）添加：

```gdscript
dpi_scale_slider = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/DpiScaleSection/DpiScaleSlider")
dpi_scale_value_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/DpiScaleSection/DpiScaleValueLabel")
```

- [ ] 在 `_init_settings_ui_if_needed()` 初始化语言选项之后（约第8968行后）添加：

```gdscript
if dpi_scale_slider:
    dpi_scale_slider.min_value = DPI_SCALE_MIN
    dpi_scale_slider.max_value = DPI_SCALE_MAX
    dpi_scale_slider.step = DPI_SCALE_STEP
    dpi_scale_slider.value = dpi_scale
if dpi_scale_value_label:
    dpi_scale_value_label.text = str(int(dpi_scale * 100)) + "%"
```

- [ ] 在 `_connect_settings_signals()` 中连接滑块信号（约第9644行后）添加：

```gdscript
if dpi_scale_slider:
    dpi_scale_slider.value_changed.connect(_on_dpi_scale_changed)
```

- [ ] 在文件末尾添加滑块回调方法：

```gdscript
func _on_dpi_scale_changed(value: float) -> void:
    dpi_scale = clamp(value, DPI_SCALE_MIN, DPI_SCALE_MAX)
    _apply_font_scale()
    if dpi_scale_value_label:
        dpi_scale_value_label.text = str(int(dpi_scale * 100)) + "%"
```

- [ ] 在 `_refresh_all_ui_text()` 中刷新缩放标签文本（语言刷新之后）添加：

```gdscript
var dpi_scale_label = get_node_or_null("/root/Control/TabContainer/SettingsTab/SettingsScroll/SettingsVBox/DpiScaleSection/DpiScaleLabel")
if dpi_scale_label:
    dpi_scale_label.text = translate("dpi_scale")
```

- [ ] 在 `_save_settings()` 中保存 dpi_scale 值：

```gdscript
var dpi_scale_value = dpi_scale
if dpi_scale_slider:
    dpi_scale_value = dpi_scale_slider.value
config.set_value("settings", "dpi_scale", dpi_scale_value)
```

---

## Task 4: 添加场景节点（modmanager.tscn）

**文件**: `modmanager.tscn`

- [ ] 在 LanguageSection 下方添加新的 DpiScaleSection VBoxContainer：

```
[Path: SettingsTab/SettingsScroll/SettingsVBox/DpiScaleSection]
- 类型: VBoxContainer
- MarginContainer > Label(DpiScaleLabel) + HBox > HSlider(DpiScaleSlider) + Label(DpiScaleValueLabel)
```

具体结构：
```
DpiScaleSection (VBoxContainer)
├── DpiScaleLabel (Label) - 文本: "界面缩放"
└── DpiScaleHBox (HBoxContainer)
    ├── DpiScaleSlider (HSlider) - min=0.8, max=2.0, step=0.05
    └── DpiScaleValueLabel (Label) - 格式: "100%"
```

---

## Task 5: 添加翻译字符串

**文件**: `locales/zh_CN.json`

- [ ] 在 JSON 中添加：

```json
"dpi_scale": "界面缩放",
```

**文件**: `locales/en_US.json`

- [ ] 在 JSON 中添加：

```json
"dpi_scale": "Interface Scale",
```

---

## Task 6: 验证和提交

- [ ] 在 Godot 编辑器中打开项目，运行测试
- [ ] 检查设置面板是否显示缩放滑块
- [ ] 调整滑块验证 UI 是否正确缩放
- [ ] 重启程序验证配置是否正确保存/加载
- [ ] 提交更改

---

## 注意事项

- `_apply_font_scale()` 使用 Theme 方式全局覆盖字体大小
- 缩放变化时需要刷新所有已实例化的 mod_item 和其他控件
- 滚动容器需正确处理缩放后的内容尺寸
- 若使用 Godot 内置主题方式不可行，可改用 `add_theme_font_size_override` 直接设置
