// Mock mod bundle data for web-based Slay the Spire 2 Mod Manager
// 3 bundles: beginner, competitive, cosmetic

window.MOCK_BUNDLES = [
  {
    id: "beginner-starter-pack",
    name: "新手入门整合包",
    version: "v1.2.0",
    author: "BundleMaster",
    description: "精心挑选适合新手玩家的模组组合，包含中文汉化、战斗辅助和存档保护功能。帮助新玩家更快上手游戏，减少不必要的挫败感，同时保持游戏核心体验不变。",
    mod_names: [
      "STS2中文汉化补丁",
      "敌人血量显示",
      "自动存档备份",
      "遗物效果提示",
      "高级战斗日志"
    ],
    presets: {
      "推荐配置": [
        "STS2中文汉化补丁",
        "敌人血量显示",
        "自动存档备份"
      ],
      "完整配置": [
        "STS2中文汉化补丁",
        "敌人血量显示",
        "自动存档备份",
        "遗物效果提示",
        "高级战斗日志"
      ],
      "极简配置": [
        "STS2中文汉化补丁",
        "自动存档备份"
      ]
    },
    update_url: "https://api.example.com/bundles/beginner-starter-pack",
    created_date: "2026-03-15T08:00:00.000Z"
  },
  {
    id: "competitive-enhanced-pack",
    name: "竞技增强包",
    version: "v2.0.0",
    author: "ProPlayer",
    description: "面向竞技玩家的全面增强模组组合，覆盖战斗数据分析、路径优化和操作效率提升。所有模组均经过兼容性测试，确保稳定运行。让你的每一局都更高效。",
    mod_names: [
      "高级战斗日志",
      "敌人血量显示",
      "遗物效果提示",
      "地图路径优化",
      "卡组统计分析",
      "快捷键增强",
      "商店价格调整",
      "精英敌人增强"
    ],
    presets: {
      "标准竞技": [
        "高级战斗日志",
        "敌人血量显示",
        "遗物效果提示",
        "卡组统计分析"
      ],
      "极限挑战": [
        "高级战斗日志",
        "精英敌人增强",
        "地图路径优化",
        "商店价格调整"
      ],
      "全功能": [
        "高级战斗日志",
        "敌人血量显示",
        "遗物效果提示",
        "地图路径优化",
        "卡组统计分析",
        "快捷键增强",
        "商店价格调整",
        "精英敌人增强"
      ],
      "纯辅助（不影响平衡）": [
        "高级战斗日志",
        "卡组统计分析",
        "快捷键增强"
      ]
    },
    update_url: "https://api.example.com/bundles/competitive-enhanced-pack",
    created_date: "2026-03-22T12:00:00.000Z"
  },
  {
    id: "beauty-full-pack",
    name: "美化全家桶",
    version: "v1.5.0",
    author: "ArtTeam",
    description: "全面美化游戏界面和视听体验的模组组合，包含卡牌动画、粒子特效、自定义音乐和角色皮肤。让你的杀戮尖塔2焕然一新，享受极致的视觉盛宴。",
    mod_names: [
      "卡牌动画增强",
      "粒子特效美化",
      "自定义BGM",
      "UI主题切换器"
    ],
    presets: {
      "默认美化": [
        "卡牌动画增强",
        "粒子特效美化",
        "UI主题切换器"
      ],
      "视听全开": [
        "卡牌动画增强",
        "粒子特效美化",
        "自定义BGM",
        "UI主题切换器"
      ],
      "轻量美化": [
        "UI主题切换器",
        "自定义BGM"
      ]
    },
    update_url: "https://api.example.com/bundles/beauty-full-pack",
    created_date: "2026-04-01T16:30:00.000Z"
  }
];
