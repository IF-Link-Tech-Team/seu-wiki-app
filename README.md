# SEU.wiki（iOS）

面向东南大学学生的原生 iOS 应用：聚合校园资讯、沉淀学习经验、直达校园服务。

## 功能结构（5 个 Tab）

| Tab | 内容 |
|---|---|
| 主页 | bento 卡片：提醒倒计时、下一节课、与我有关的通知、社区热议（论坛热榜前 3 条） |
| 资讯 | 全校通知信息流（源自 seu-wiki-v2），为你精选 / 全部（可筛选）/ 分类 console，详情页可设定截止提醒 |
| 经验 | 热门 / 关注 / 东大生存手册，全部来自论坛后端 `forum.seu.wiki`：热榜（置顶优先）、关注流（阶段 2，未部署显式标注）、手册板块与沉淀文章；帖子详情有真实评论/点赞/收藏/浏览计数，右上角原生发帖编辑器 |
| 工具 | 课表、绩点计算等校园工具；**未上线的工具显式标注「即将推出」并置灰不可点** |
| 搜索 | 一次搜索聚合三个信源：通知（`/api/site/pool`）/ 经验帖与手册文章（论坛 `/api/search`）；各信源独立成败，论坛未部署时显式标注、不拖垮通知 |

个人页面与设置统一在各 Tab 右上角，登录走 IF.Link 生态自部署 Logto（原生界面，非网页跳转）。

## 数据来源

两个后端，全部实测确认（`curl` 验证过契约）：

**seu.wiki（资讯，只读、不鉴权）**

| 端点 | 用途 | 备注 |
|---|---|---|
| `/api/site/timeline` | 全部通知 | cursor 分页 |
| `/api/site/for-you` | 为你精选 | cursor **绑定画像**，改画像须重置 cursor |
| `/api/site/items/{id}` | 通知详情 | |
| `/api/site/pool?q=&type=feed` | 通知搜索 | 经验/手册搜索已迁论坛，pool 只留资讯 |
| `/api/site/docs/{slug}` | 长文详情 | 保留给本机长文收藏与调试深链；返回 `html` + **`headings`**（`{id,text,depth}`） |

**forum.seu.wiki（社区，公开读 + Bearer 写）**

| 端点 | 用途 | 备注 |
|---|---|---|
| `GET /api/posts?sort=hot\|latest\|top&tag=` | 帖子信息流 | hot 用 offset 分页（置顶优先），其余 keyset；`tag` 是精确 slug 命中 |
| `GET /api/posts/{id}` | 帖子详情 | 含作者/标签/图片/`bookmarked`/收录的手册文章 |
| `POST /api/posts/{id}/view` | 浏览 +1 | 匿名可调 |
| `GET/POST /api/comments` | 评论 | 单层楼中楼（`parent_id`），正文 ≤5000 |
| `POST /api/post-likes` `POST /api/bookmarks` | 点赞/收藏 toggle | **「赞」无读取接口**，详情页初始一律未赞 |
| `POST /api/posts` | 发帖 | body 键白名单严格（title?/content/tags ≤3），多一个键 400 |
| `GET /api/bookmarks` | 我的帖子收藏 | 需登录 |
| `GET /api/handbook/*` | 东大生存手册 | 板块/文章；文章 `content_html` 已由服务端消毒 |
| `GET /api/search?q=&type=post\|article\|all` | 论坛搜索 | posts/articles 两组 keyset 分页 |
| `/api/follows` `/api/feed/following` | 关注（阶段 2） | 未部署时客户端显式标注「即将上线」 |

三条硬约束（都踩过坑，已写进代码注释）：

1. **`/api/site/*` 不校验鉴权，因此不发送 Logto token。** 发了只扩大暴露面，还会把 token 续期链路拽进来。
2. **论坛 Bearer token 只发给 `forum.seu.wiki`**（`ForumAPIClient` 里有 host 白名单校验），绝不带 Cookie。
3. **slug 形如 `survival/观点篇/1-认识`，斜杠必须保留字面量，只编码非 ASCII 部分**，且拼 URL 要用 `URLComponents.percentEncodedPath`（用 `path` 会把 `%` 二次转义成 `%25`，全站中文文档详情 404）。

`campus` / `audience` / `deadline` 三个字段**后端从不返回**，代码里不编造默认值；「按学院/学段筛选」在 `FeedFilter.supportsAudienceFilter` 上显式置灰并说明原因。

## 技术

- iOS 26+ / Swift 6 / 纯 SwiftUI，无第三方依赖
- Xcode 文件系统同步组：往 `SEUWiki/SEUWiki/` 目录加 `.swift` 即自动加入工程
- 设计遵循 Apple HIG 与最新版系统规范，图标全部 SF Symbols
- 会话：OIDC 授权码 + PKCE，token 存 Keychain（`AfterFirstUnlockThisDeviceOnly`），登出走 RFC 7009 吊销

## 构建与验收

```bash
xcodebuild -project SEUWiki/SEUWiki.xcodeproj -scheme SEUWiki \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath /tmp/dd build
```

启动即跑自检（DEBUG）。这台机器上 `NSLog` 取不出来（`log show` 匹配不到，`simctl launch --console-pty` 也接不到），所以自检会把报告写到 App 容器里，直接读文件确认：

```bash
DC=$(xcrun simctl get_app_container booted tech.iflink.seuwiki data)
head -1 "$DC/Documents/selfcheck.txt"   # 例如 161/161 通过
grep '^FAIL' "$DC/Documents/selfcheck.txt"
```

无头模拟器验收用的启动参数（仅 DEBUG，Release 不含）：

```bash
xcrun simctl launch booted tech.iflink.seuwiki -uitab experience   # 直达某个 tab
xcrun simctl launch booted tech.iflink.seuwiki -uiconsole following  # 经验 tab 直达某个 console（hot/following/handbook）
xcrun simctl launch booted tech.iflink.seuwiki -uicomposer   # 直接弹发帖编辑器（未登录时是登录引导）
xcrun simctl launch booted tech.iflink.seuwiki -uiprofile    # 直接弹个人页
xcrun simctl launch booted tech.iflink.seuwiki -uisearch 保研  # 搜索 tab 直接带关键词
xcrun simctl launch booted tech.iflink.seuwiki -uidoc "survival/观点篇/1-认识"  # 直达长文详情
xcrun simctl launch booted tech.iflink.seuwiki -uipush <feedItemID>  # 模拟点开提醒通知，直达该条资讯
```

## 目录

```
SEUWiki/SEUWiki/
├── App/          # 入口与根 TabView（含 DEBUG 深链参数）
├── Models/       # 数据模型（对齐真实 API）、ToolCatalog
├── Design/       # 共享设计组件（卡片、ConsoleBar、导航目的地、品牌色）
├── Services/     # FeedService（seu.wiki）、ForumService（forum.seu.wiki）、ReminderScheduler、NotificationCenterDelegate、SelfCheck、Paging、TimeFormat
├── Stores/       # UserProfile、FeedStore 等 @Observable 状态
└── Features/     # Home / Feed / Experience / Tools / Search / Profile
```

## 自检套件

`Services/SelfCheck.swift` 在 DEBUG 启动时自动执行 161 条断言，覆盖：日期解析（含论坛 PostgREST 6 位微秒时间戳）、相对时间、绩点计算、分页去重、slug 编码、URL 组装、后端字段契约（长文 `headings/depth`、论坛帖子/手册文章的 snake_case 字段）、论坛标签目录完整性（8 主题 + 29 子标签 = 37 slug 唯一）、画像指纹、颜色对比度、提醒徽标、提醒通知契约（`userInfo` 的 key、触发时刻算法）、SF Symbol 有效性、持久化容错。

其中 75 条是 SF Symbol 校验：`Image(systemName:)` 拿到不存在的名字**不报错、只画空白**，构建照样全绿。`checkSFSymbols()` 把工程用到的每个 SF 名用 `UIImage(systemName:)` 验一遍 —— 这条是安卓端在模拟器截图里发现「收藏按钮渲染成九宫格」之后补的，安卓那边兜底成了一个语义完全不相干的图形，iOS 这边兜底是空白。清单是照源码全量扫出来的，**新增图标要往 `usedSFSymbols` 里加一行**。

它抓到过五个真实 bug（`Double("inf")` 返回 `inf` 而非 nil、`%25` 双重编码、目录字段名写成 `outline` 而后端是 `headings`、`userInfo` key 写错导致点通知静默失效、夏令时用减 86400 秒会让提醒差一小时）——**这些都是代码审查看不出来、只有断言能抓住的**。新增这类修复时请一并补断言。

## 参与共建

这是东大学生共建的开源项目（MIT），欢迎提 Issue 和 PR。改动前先读
`AGENTS.md` —— 账号体系铁律、构建与自检规则都在里面。涉及双端行为的改动，
记得同步 Android 端 `../seu-wiki-android` 的 `SelfCheckTest.kt` 断言。

## License

MIT，见 `LICENSE`。
