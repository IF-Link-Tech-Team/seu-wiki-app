# SEU.wiki

面向东南大学学生的原生 iOS 应用：聚合校园资讯、沉淀学习经验、直达校园服务。

## 功能结构（5 个 Tab）

| Tab | 内容 |
|---|---|
| 主页 | bento 卡片：提醒倒计时、下一节课、与我有关的通知、论坛新帖 |
| 资讯 | 全校通知信息流（源自 seu-wiki-v2 的 643 个信源），为你精选 / 全部（可筛选）/ 8 大分类，详情页可设定截止提醒 |
| 经验 | 学习经验论坛（保研/考研/留学/SRTP…）：热门 / 关注 / 话题广场 / 东大生存手册 |
| 工具 | 课表、绩点计算、考试安排等校园工具入口（快捷指令资料库式网格） |
| 搜索 | 一次搜索聚合三个信源：通知 / 经验 / 手册 |

个人页面与设置统一在各 Tab 右上角，登录走 IF.Link 生态自部署 Logto（原生界面）。

## 技术

- iOS 26 / Swift 6.2 / 纯 SwiftUI，无第三方依赖
- Xcode 16+ 文件系统同步组：往 `SEUWiki/SEUWiki/` 目录加文件即自动加入工程
- 设计遵循 Apple HIG 与 iOS 26（Liquid Glass）规范，图标全部使用 SF Symbols

## 构建

```bash
xcodebuild -project SEUWiki/SEUWiki.xcodeproj -scheme SEUWiki \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## 目录

```
SEUWiki/SEUWiki/
├── App/          # 入口与根 TabView
├── Models/       # 数据模型（结构对齐真实 API）与 MockData
├── Design/       # 共享设计组件（卡片、ConsoleBar、导航目的地、个人入口）
├── Stores/       # UserProfile 等 @Observable 状态
└── Features/     # Home / Feed / Experience / Tools / Search / Profile
```

## 关联仓库（Reference/，仅开发参考）

- `seu-wiki-v2`：资讯信源与 API（`/api/site/timeline`、`/for-you`、`/pool`）
- `iflab-forum`：论坛后端蓝本（`../seu-forum` 为其复刻裁剪版）
- `iflink-logto` / `iflink-community-auth` / `iflink-accounts`：IF.Link 账号体系
