// Mock save data for web-based Slay the Spire 2 Mod Manager
// 6 save entries: 3 Steam + 3 imported

window.MOCK_SAVES = [
  // --- Steam save 1: main account, vanilla, 3 profiles ---
  {
    steam_id: "76561198000000001",
    name: "Steam云存档",
    type: "steam",
    modded: false,
    date: "2026-05-02T22:10:00.000Z",
    size: 2457600,
    path: "%APPDATA%\\SlayTheSpire2\\steam\\76561198000000001",
    profiles: [
      {
        profile_num: 1,
        game_time: 186400,
        discovered_cards: 312,
        discovered_relics: 98,
        character_stats: {
          "铁甲战士": { wins: 45, losses: 23 },
          "静默猎手": { wins: 38, losses: 31 },
          "储君": { wins: 22, losses: 18 },
          "亡灵契约师": { wins: 15, losses: 25 },
          "故障机器人": { wins: 30, losses: 20 }
        }
      },
      {
        profile_num: 2,
        game_time: 72000,
        discovered_cards: 180,
        discovered_relics: 55,
        character_stats: {
          "铁甲战士": { wins: 12, losses: 8 },
          "静默猎手": { wins: 8, losses: 14 },
          "储君": { wins: 5, losses: 10 },
          "亡灵契约师": { wins: 3, losses: 7 },
          "故障机器人": { wins: 10, losses: 6 }
        }
      },
      {
        profile_num: 3,
        game_time: 14400,
        discovered_cards: 45,
        discovered_relics: 12,
        character_stats: {
          "铁甲战士": { wins: 2, losses: 5 },
          "静默猎手": { wins: 1, losses: 3 },
          "储君": { wins: 0, losses: 2 },
          "亡灵契约师": { wins: 0, losses: 1 },
          "故障机器人": { wins: 0, losses: 0 }
        }
      }
    ]
  },

  // --- Steam save 2: same account, modded, 2 profiles ---
  {
    steam_id: "76561198000000001",
    name: "Steam云存档 (模组)",
    type: "steam",
    modded: true,
    date: "2026-05-03T18:30:00.000Z",
    size: 3145728,
    path: "%APPDATA%\\SlayTheSpire2\\steam\\76561198000000001\\modded",
    profiles: [
      {
        profile_num: 1,
        game_time: 54000,
        discovered_cards: 210,
        discovered_relics: 72,
        character_stats: {
          "铁甲战士": { wins: 20, losses: 12 },
          "静默猎手": { wins: 15, losses: 18 },
          "储君": { wins: 8, losses: 9 },
          "亡灵契约师": { wins: 6, losses: 11 },
          "故障机器人": { wins: 14, losses: 7 }
        }
      },
      {
        profile_num: 2,
        game_time: 10800,
        discovered_cards: 85,
        discovered_relics: 28,
        character_stats: {
          "铁甲战士": { wins: 4, losses: 6 },
          "静默猎手": { wins: 2, losses: 5 },
          "储君": { wins: 1, losses: 3 },
          "亡灵契约师": { wins: 0, losses: 4 },
          "故障机器人": { wins: 3, losses: 2 }
        }
      }
    ]
  },

  // --- Steam save 3: second account, vanilla, 1 profile ---
  {
    steam_id: "76561198000000002",
    name: "Steam云存档",
    type: "steam",
    modded: false,
    date: "2026-04-28T10:05:00.000Z",
    size: 1572864,
    path: "%APPDATA%\\SlayTheSpire2\\steam\\76561198000000002",
    profiles: [
      {
        profile_num: 1,
        game_time: 108000,
        discovered_cards: 198,
        discovered_relics: 63,
        character_stats: {
          "铁甲战士": { wins: 28, losses: 15 },
          "静默猎手": { wins: 20, losses: 22 },
          "储君": { wins: 10, losses: 12 },
          "亡灵契约师": { wins: 7, losses: 9 },
          "故障机器人": { wins: 18, losses: 11 }
        }
      }
    ]
  },

  // --- Imported save 1: perfect clear ---
  {
    steam_id: null,
    name: "完美通关存档",
    type: "imported",
    modded: false,
    date: "2026-04-20T08:00:00.000Z",
    size: 2097152,
    path: "saves\\完美通关存档",
    profiles: [
      {
        profile_num: 1,
        game_time: 259200,
        discovered_cards: 350,
        discovered_relics: 120,
        character_stats: {
          "铁甲战士": { wins: 100, losses: 5 },
          "静默猎手": { wins: 100, losses: 8 },
          "储君": { wins: 100, losses: 12 },
          "亡灵契约师": { wins: 100, losses: 10 },
          "故障机器人": { wins: 100, losses: 6 }
        }
      }
    ]
  },

  // --- Imported save 2: mod testing ---
  {
    steam_id: null,
    name: "模组测试存档",
    type: "imported",
    modded: true,
    date: "2026-04-30T15:20:00.000Z",
    size: 4194304,
    path: "saves\\模组测试存档",
    profiles: [
      {
        profile_num: 1,
        game_time: 36000,
        discovered_cards: 420,
        discovered_relics: 150,
        character_stats: {
          "铁甲战士": { wins: 50, losses: 50 },
          "静默猎手": { wins: 45, losses: 55 },
          "储君": { wins: 40, losses: 60 },
          "亡灵契约师": { wins: 35, losses: 65 },
          "故障机器人": { wins: 48, losses: 52 }
        }
      }
    ]
  },

  // --- Imported save 3: dated backup ---
  {
    steam_id: null,
    name: "备份存档_20260501",
    type: "imported",
    modded: false,
    date: "2026-05-01T03:00:00.000Z",
    size: 1835008,
    path: "saves\\备份存档_20260501",
    profiles: [
      {
        profile_num: 1,
        game_time: 144000,
        discovered_cards: 256,
        discovered_relics: 82,
        character_stats: {
          "铁甲战士": { wins: 32, losses: 18 },
          "静默猎手": { wins: 25, losses: 25 },
          "储君": { wins: 14, losses: 16 },
          "亡灵契约师": { wins: 10, losses: 20 },
          "故障机器人": { wins: 22, losses: 15 }
        }
      }
    ]
  }
];
