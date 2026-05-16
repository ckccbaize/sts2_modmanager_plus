# UI 参考文件

此文件夹用于永久保存各个阶段的UI设计参考。

## 最终定案文件

### 01-all-tabs-v8-final.html
**v8 最终版** - 包含所有标签页的完整预览
- 模组页面 (Mod)
- 整合包页面 (Bundle)
- 存档页面 (Save)
- 下载页面 (Download)
- Nexus页面
- 设置页面 (Settings)

**特点**: 用户确认的其他页面（下载/Nexus/设置）都固定下来，不再修改。

### 02-mod-page-with-launch-button.html
**模组页面含启动按钮** - 带Tesla风格拖拽换挡启动条
- 集成到底部栏
- 档位球覆盖在N上方
- 支持P/D/N/R四个档位
- 需拖动到档位正上方才能触发

### 03-ui-redesign-plan.md
**UI/UX重构实施计划** - 详细的重构方案
- 色彩系统定义 (颜色常量)
- 各页面重构详细步骤
- Tesla启动按钮实现逻辑
- 验证清单

---

## 启动按钮交互说明

**布局**: P — 轨道 — D — **[N+档位球]** — R

**操作**:
- 从N位置拖动向左 → D (模组版)
- 继续向左 → P (联机模式)
- 从N位置拖动向右 → R (原版)
- 松开不到档位 → 自动回N
- 挂到档位上 → 启动游戏

**技术细节**:
- 动态获取档位实际位置
- 行程范围: -150 ~ +100
- 吸附范围: ±15px

---

## 开发历史

| 文件 | 说明 |
|------|------|
| ui-styles-preview.html | 早期UI样式探索 |
| ui-styles-hybrid-steam-win11.html | Steam×Win11混合风格预览 |
| ui-styles-full-preview.html | 全页面预览(被01替代) |
| launch-button-test.html | 圆形启动按钮测试 |
| launch-button-drag.html | 特斯拉式垂直拖拽版本 |
| launch-bar-horizontal.html | 横向启动条独立测试 |
| mod-page-with-launch.html | 最终集成版本(被02替代) |
