# HearthStone Draft Assistant

炉石传说竞技场选牌助手，支持 Mac（Mac Catalyst）和 iPhone/iPad（iOS）。

截图或拍照后自动识别选牌界面的三张卡，聚合 HearthArena、HSReplay、Firestone 三大数据源，给出当前职业下的选牌建议。

---

## 功能

**截图识别**
- Mac：监听截图文件夹，出现新截图时自动触发识别
- iOS/iPadOS：相机拍照或从相册选图

**卡牌识别**
- Apple Vision OCR 读取卡名文字
- 全图一次 OCR + X 坐标三槽分配，不依赖固定裁剪坐标，适应各种截图来源（游戏内截图、手机拍照、直播截图等）
- Mac 额外支持 OpenCV 图像特征匹配作为兜底

**数据聚合**
- HearthArena：竞技场静态评分（tier 分）
- HSReplay：选取率、入牌胜率、抽到胜率、打出胜率
- Firestone：入牌胜率（大样本）
- 支持 CORE_ 前缀自动映射，兼容游戏内卡牌 ID 与数据源 ID 不一致的情况

**选牌建议**
- 支持多职业同时对比（竞技场双职业 / 游侠模式）
- 按数据源优先级给出推荐，并列出每张牌的完整数据

**手动输入**
- 可直接输入中文名、英文名或卡牌 ID 触发查询
- 识别完成后支持手动修正

---

## 截图

> _（后续补充）_

---

## 技术架构

```
HearthStoneDraftAssistant/
├── App/
│   ├── DraftDashboardViewController.swift   # 主界面，UICollectionView + DiffableDataSource
│   ├── DraftScreenshotInput.swift           # 截图识别：Vision OCR + OpenCV 图像匹配
│   ├── ScreenshotFolderWatcher.swift        # Mac 截图文件夹监听（FSEvents）
│   ├── OpenCVDraftImageMatcher.h/.mm        # OpenCV 卡图特征匹配（仅 Mac Catalyst）
│   └── AppDelegate / SceneDelegate
└── Sources/HearthDraftData/
    ├── Repository.swift                     # 卡牌数据聚合与查询
    ├── DraftDataService.swift               # 数据拉取、缓存与刷新
    ├── DataSourceEndpoints.swift            # HearthArena / HSReplay / Firestone 接口定义
    ├── Models.swift                         # 数据模型
    ├── Providers.swift                      # 各数据源解析
    └── HearthstoneLogWatcher.swift          # 游戏日志解析（职业识别）
```

**识别流程（OCR 主路径）**

1. 全图做一次 `VNRecognizeTextRequest`，获取所有文字及其 X 坐标
2. 按 X 坐标分三个槽（左 / 中 / 右），每槽独立匹配候选卡名
3. 匹配算法：编辑距离 + 字符覆盖率加权，容忍中文 OCR 噪点
4. 三槽全部命中 → 直接返回；否则降级到固定布局扫描兜底
5. Mac 额外用 OpenCV SIFT 特征匹配卡图作为最终兜底

**平台差异**

| 能力 | Mac Catalyst | iOS / iPadOS |
|------|-------------|--------------|
| 截图输入 | 文件夹自动监听 | 相机 / 相册 |
| OpenCV 图像匹配 | ✅ | ❌（仅 Vision OCR）|
| 职业 chip 布局 | 换行铺满 | 横向滚动 |

---

## 依赖

| 依赖 | 用途 |
|------|------|
| [SnapKit](https://github.com/SnapKit/SnapKit) | 布局 |
| [SDWebImage](https://github.com/SDWebImage/SDWebImage) | 卡图异步加载与缓存 |
| OpenCV2 xcframework | 图像特征匹配（仅 Mac Catalyst，本地 Vendor） |
| Apple Vision | OCR 文字识别 |

---

## 数据来源

- **卡牌元数据**：[HearthstoneJSON](https://hearthstonejson.com)
- **HearthArena 评分**：[Arena-Tracker mirror](https://github.com/supertriodo/Arena-Tracker)
- **HSReplay 统计**：[HSReplay.net](https://hsreplay.net)
- **Firestone 统计**：[Firestone](https://www.firestoneapp.com)

数据在应用启动时自动拉取并本地缓存，可手动刷新。

---

## 构建

**环境要求**

- Xcode 15+
- macOS 14+ / iOS 17+
- CocoaPods

**步骤**

```bash
git clone https://github.com/DeftMKJ/hs-arena.git
cd hs-arena
pod install
open HearthStoneDraftAssistant.xcworkspace
```

选择 `HearthStoneDraftAssistant` scheme，Build & Run。

> Mac 运行需要对截图文件夹授予文件访问权限；iOS 运行需要相机 / 相册权限。

---

## License

MIT
