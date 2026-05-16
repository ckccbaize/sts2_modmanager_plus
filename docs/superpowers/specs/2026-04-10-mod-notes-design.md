# 模组备注功能设计

## 概述

为Slay the Spire 2 Mod Manager添加自定义备注功能，用户可以为已安装的模组添加个性化备注，备注在模组详情面板中展示。

## 设计方案

### 1. 数据存储

**文件位置**: `%APPDATA%/SlayTheSpire2ModManager/mod_notes.json`

**JSON结构**:
```json
{
  "mod_notes": {
    "模组A": "这是我的备注内容",
    "模组B": "另一个模组备注"
  }
}
```

以模组 `id` 为key，备注内容为value。不同版本的相同模组会共享显示同一条备注。

### 2. 数据读写

- `load_notes()`: 启动时加载JSON，缓存在内存
- `save_notes()`: 修改备注后保存到文件
- `get_note(id)`: 获取指定模组备注
- `set_note(id, content)`: 设置/更新备注

### 3. UI布局

在模组详情面板右上角添加：
- 📝图标按钮（点击弹出备注编辑弹窗）

模组详情区域下方展示：
- 分割线
- 备注内容Label（如有）

### 4. 弹窗设计

- 半透明遮罩层
- 居中Panel包含：
  - 标题："模组备注"
  - TextEdit（最多500字符）
  - HBox: 确认 / 取消按钮

### 5. 交互流程

1. 用户点击📝 → 弹出编辑弹窗，TextEdit预填当前备注
2. 用户编辑 → 可修改备注内容
3. 点击确认 → 保存到文件，更新显示
4. 点击取消 → 忽略修改

## 实现计划

见: `docs/superpowers/plans/2026-04-10-mod-notes-plan.md`