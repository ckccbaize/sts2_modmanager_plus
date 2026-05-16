# DPI 自适应缩放方案

**日期**: 2026-04-13
**状态**: 设计中

## 目标

在高分辨率屏幕上，模组管理器的 UI 元素和文字偏小，不方便查看。通过实现 DPI 自适应缩放功能，让界面在各种分辨率下保持舒适的可见性。

## 方案概述

- 窗口默认 800×700，用户可自由拖拽改变大小
- 启动时自动检测屏幕 DPI，设置合适的初始缩放因子
- 设置面板增加"DPI缩放"滑块，允许用户手动覆盖自动值（范围 80%~200%）
- 全局缩放因子统一应用到所有字体、间距和控件尺寸

## 实现细节

### 1. 缩放因子管理

**新增常量（modmanager.gd）**:
```gdscript
var dpi_scale: float = 1.0  # 当前缩放因子
const DPI_SCALE_MIN: float = 0.8
const DPI_SCALE_MAX: float = 2.0
const DPI_SCALE_DEFAULT: float = 1.0
```

**自动检测逻辑**:
```gdscript
func _detect_dpi_scale() -> float:
    var screen_dpi = DisplayServer.screen_get_dpi()
    # 96 DPI 为标准，1280×720 及以上屏幕通常需要缩放
    if screen_dpi >= 192:
        return 1.5
    elif screen_dpi >= 144:
        return 1.25
    return 1.0
```

### 2. 应用缩放

缩放因子通过以下方式应用到 UI：

- **字体大小**: 通过 `apply_font_scale()` 方法动态修改所有 Label 的自定义字体大小
- **间距**: 使用 `SPACING` 常量乘以 `dpi_scale` 计算实际间距
- **控件最小尺寸**: 设置 `custom_minimum_size` 应用缩放

```gdscript
func apply_ui_scale(scale: float) -> void:
    dpi_scale = clamp(scale, DPI_SCALE_MIN, DPI_SCALE_MAX)
    _apply_font_scale()
    _apply_spacing_scale()
    _apply_control_scale()
```

### 3. 设置面板

在设置页增加缩放滑块控件：
- 范围: 80% ~ 200%，步进 5%
- 实时预览：拖动滑块时立即更新 UI
- 保存到 config.cfg：`[settings] dpi_scale=1.25`

### 4. 配置持久化

**config.cfg 新增字段**:
```ini
[settings]
dpi_scale=1.25
```

**加载顺序**:
1. 启动时先读取 `config.cfg` 中的 `dpi_scale`
2. 若无记录或值为 0，执行自动检测
3. 应用缩放因子到 UI

### 5. 修改的文件

| 文件 | 改动内容 |
|------|----------|
| `modmanager.gd` | 新增 `dpi_scale` 变量、自动检测逻辑、缩放应用方法 |
| `config.cfg` | 新增 `dpi_scale` 配置项 |
| `locales/zh_CN.json` | 新增缩放相关翻译字符串 |
| `locales/en_US.json` | 新增缩放相关翻译字符串 |
| `modmanager.tscn` | 设置面板增加缩放滑块 UI |
| `ui/mod_item.gd` | 支持动态字体大小 |
| `ui/mod_details.gd` | 支持动态字体大小 |

## 注意事项

- 缩放变化时需刷新所有已实例化的 UI 控件
- 图标和图片资源需支持缩放（使用 `TextureRect` 的 `stretch_mode`）
- 滚动容器需正确处理缩放后的内容尺寸
