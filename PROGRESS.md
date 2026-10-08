# 开发进度

## 当前状态（2026-10-08）

iOS 端小步中文提交（`git log --oneline`），双端已接真实后端，生产路径**无任何 Mock / 编造内容**。
自检 177/177 通过，模拟器逐屏截图验收（浅色 + 深色）。

**2026-10-08：经验 tab 论坛化。** 经验 tab 从 seu-wiki-v2 文档接口迁移到论坛后端
`forum.seu.wiki`：热门（论坛热榜，置顶优先）/ 关注（阶段 2，未部署显式标注）/
东大生存手册（`/api/handbook/*`）三个 console；帖子详情有真实评论/点赞/收藏/浏览 +1；
原生发帖编辑器（标题选填 ≤160、正文 ≤20000、标签 ≤3 来自内嵌目录）；
搜索的经验/手册信源改论坛 `/api/search`（pool 只留资讯）；个人页「帖子收藏」接
`GET /api/bookmarks`（本机长文 slug 收藏保留）；删除 docs/experience 索引与全部
编造帖子数据。

**2026-10-08（第二轮）：内容管理 + 通知 + 发帖页重做。** 发帖页改为豆瓣式布局
（板块胶囊选择 + PhotosPicker 多图，`/api/media/upload` multipart 上传）；
帖子/评论支持作者编辑删除（`PATCH /api/posts/:id`、`DELETE /api/content/...`），
管理员管理删除（`DELETE /api/admin/content/...`，viewer.capabilities 只控按钮可见性）；
通知系统上线：经验页顶栏铃铛（未读角标）→ 通知列表（进页快照未读高亮一次、
全部标记已读、点击跳帖），后端为 `GET /api/notifications` +
`POST /api/notifications/mark-read`。

## 已完成

### 数据层：全部接真实后端

- [x] `/api/site/timeline`、`/api/site/for-you`、`/api/site/items/{id}`（cursor 分页 + 去重）
- [x] `/api/site/pool?q=&type=feed` 通知搜索
- [x] 论坛 `/api/posts`（hot offset 分页 / latest·tag keyset）、`/api/posts/{id}` 详情、`/view` 浏览 +1
- [x] 论坛评论（单层楼中楼）、点赞/收藏 toggle、`GET /api/bookmarks`
- [x] 论坛编辑/删除：`PATCH /api/posts/:id`、`DELETE /api/content/...`（作者）、`DELETE /api/admin/content/...`（管理删除）
- [x] 发帖配图：`POST /api/media/upload`（multipart，PhotosPicker 多图统一转 JPEG）
- [x] 论坛通知：`GET /api/notifications`（unread_count 角标）、`POST /api/notifications/mark-read`（空对象 body）
- [x] 论坛 `/api/handbook/*` 东大生存手册（板块 + 消毒后的 `content_html` 文章）
- [x] 论坛 `/api/search` 经验/手册信源（两组 keyset 分页，与通知信源各自成败）
- [x] `/api/site/docs/{slug}` 长文详情：HTML 按标题切分正文、目录跳转、锚点定位（保留给本机长文收藏与调试深链）
- [x] 失败与空结果**分开**处理（S-10），不再回退 Mock
- [x] 不给 `/api/site/*` 发 token（S-12）；论坛 Bearer token 只发 `forum.seu.wiki`（host 白名单）
- [x] 论坛时间戳是 PostgREST timestamptz（可带 6 位微秒），`.SSS` 只认 3 位 → `DateParser.parseForum` 先截断再解析
- [x] 论坛热榜线上曾先于仓库部署（`sort=hot` 回 `INVALID_SORT`）→ 客户端自动降级 latest 并记住
- [x] 移除本地 `followedTopicIDs`（默认值 `["baoyan","srtp"]` 是假关注数据），关注关系全部走服务端 `/api/follows`（阶段 2，未部署显式「即将上线」）
- [x] `campus`/`audience`/`deadline` 后端不返回 → 不编造默认值，筛选项显式置灰（S-4 / S-11）

### 会话安全

- [x] 仅 400 `invalid_grant` / 401 才清会话，网络抖动不再误登出（S-1）
- [x] `refreshTask` 合并 + `sessionGeneration` 防登出后被并发续期复活（S-2）
- [x] token 存 Keychain（`AfterFirstUnlockThisDeviceOnly`）+ 一次性明文迁移（S-3）
- [x] 始终带 `prompt=consent`，登出走 RFC 7009 吊销 + `prompt=login`（S-6 / S-7）

### 提醒闭环

- [x] `ReminderScheduler`：`UNCalendarNotificationTrigger` 排程、授权、删除即取消、冷启动 `reconcile` 对账、总开关（S-5）
- [x] 提醒可编辑/删除；过期提醒自动清理（S-13）
- [x] **`UNUserNotificationCenterDelegate`**：前台弹横幅、点通知深链到对应资讯（审查未覆盖，见下）
- [x] `AppDelegate` 在 `didFinishLaunchingWithOptions` 装 delegate —— 冷启动点通知的回调早于 SwiftUI `App.init()`

> **审查报告漏掉的一条。** S-5 只问「设定提醒会不会真的提醒」。提醒**排进去了**，
> 但工程里根本没有 delegate：iOS 默认「App 在前台静默丢弃通知」，不实现
> `willPresent` 就没有横幅；而 `userInfo` 写了却无人读，点通知只切前台、不导航。
> `relatedItemID` 当时压根没进 userInfo。Android 的 `ReminderReceiver` 注释写着
> 「对应 iOS 的 `UNUserNotificationCenterDelegate`」—— iOS 侧当时并不存在这个东西，
> 两端因此没对齐。

### 界面

- [x] 五个 Tab 均为真实数据，删除全部编造帖子/正文/评论/点赞（I-1）
- [x] 课表可增删改并落盘（I-8）
- [x] 本地化：`developmentRegion = zh-Hans`，相对时间全中文化（I-2）
- [x] 深色对比度：新增 `AccentInk.colorset`（深色下 `#00382B`，7.08:1 替代白字 1.83:1）
- [x] 工具卡 WCAG 自动选色；adaptive 网格
- [x] 未上线工具显式标注「即将推出」并置灰（I-15）
- [x] `ConsoleBar` 用 `.safeAreaBar(edge: .top)` 固定（I-6）
- [x] 主页卡片可点并跨 tab 跳转

### 健壮性

- [x] 持久化 schema 版本 + `.corruptBackup` 备份 + 逐字段容错解码（S-14）
- [x] 分页竞态用 generation 计数器解决（S-9）
- [x] 改画像重置 for-you cursor（S-8）
- [x] 绝对时间统一格式（I-12）

### 自检套件

`Services/SelfCheck.swift`，161 条断言，DEBUG 启动自动跑，结果同时写到 App 容器 `Documents/selfcheck.txt`（本机 `NSLog` 取不出来，详见 README）。**它抓到了三个代码审查看不出的真 bug**：

| 断言组 | 抓到的 bug |
|---|---|
| `checkGPA` | `Double("inf")` 返回 `inf` 而非 nil → 绩点/学分 NaN |
| `checkURLAssembly` | `URLComponents.path` 把已编码的 `%` 二次转义成 `%25` → **全站中文文档详情 404** |
| `checkDocDetailContract` | 后端字段是 `headings`/`depth`，代码写成 `outline`/`level` → **目录永远空白**（字段名写错不抛错，只是解成 nil） |
| `checkReminderNotification` | `userInfo` 的 key 写错（如 `feedId` vs `feedItemID`）→ 点了通知静默什么都不做；占位条目一旦编造标题 → 通知深链进来显示一条对不上的假资讯。两者编译期与运行期都无提示 |
| `checkReminderFireDate` | 提醒时间必须是 09:00（不是截止时刻本身）；往前推天数必须走 `Calendar.date(byAdding:)`，用「减 86400 秒」在夏令时那天会差一小时 |
| `checkSFSymbols` | 75 个 SF 名逐个验 `UIImage(systemName:)`：名字不存在时**不报错、只画空白**，构建照样全绿。补这条是因为安卓端在模拟器截图里发现收藏按钮渲染成了九宫格 |
| `checkForumTagCatalog` / `checkForumPostContract` | 论坛标签目录（8+29=37 slug，与后端 catalog.mjs 同一份）与论坛 DTO 的 snake_case 字段契约 —— 字段名写错不抛错只解成 nil，同 `headings` 那次事故 |

## 已知待办

- [ ] **S-15 绩点口径**：现按 4.8 制换算，代码注释已标注这是手册假设，**需向教务处核实**
- [ ] **论坛阶段 2 接口未部署时的端到端验证**：`/api/follows`、`/api/feed/following` 在仓库与线上均不存在路由，客户端按契约写好并以 404→「即将上线」降级；待后端上线后需复测关注流。另外「赞」无 hasUserLiked 读取接口，详情页初始一律显示未赞（后端契约限制）
- [ ] **发帖图片上传未实现**：`/api/media/upload`（multipart + COS）本期范围外，编辑器不提供图片按钮
- [ ] **登录无法端到端验证**：Logto 授权码 + PKCE 需要交互式浏览器 + 真实凭据。S-1/S-2/S-6/S-7 是靠代码审查 + 对真实 token/revocation 端点 `curl` 验证的，**不是**真的登进去过
- [ ] **通知授权弹窗与横幅未在本机实跑**：本机 `Simulator.app` 不在 Xcode 包内，无合成点击能力；`simctl privacy` 不含 notifications 服务、授权状态也不在可写的 TCC 里。因此「授权弹窗 → 真实排程 → 到点弹横幅 → 点开」这段**没有**在真机/模拟器上看过。
      已验证的部分：排程算法与 `userInfo` 契约有自检覆盖；深链后半段（`RootTabView` → `FeedHomeView` → 详情页）用 DEBUG 启动参数 `-uipush <真实id>` 冷启动实测直达并截图。`-uipush` 走的是与系统回调**同一个** `handle(userInfo:)` 入口，Release 二进制里不存在
- [ ] ~~**论坛 UGC 未接入 App**~~（2026-10-08 已接入：帖子/评论/点赞/收藏/手册/搜索全部走 forum.seu.wiki；关注流待后端阶段 2 部署）
- [ ] 后端补齐 `campus` 字段后，移除 `FeedFilter.supportsAudienceFilter = false` 即可开放学院/学段筛选
- [ ] APNs 推送（seu-wiki-v2 无 push 通道）
- [ ] 启动屏品牌化（当前系统默认）

## 构建验证

```bash
xcodebuild -project SEUWiki/SEUWiki.xcodeproj -scheme SEUWiki \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath /tmp/dd build
```

无头模拟器验收（仅 DEBUG）：

```bash
xcrun simctl install booted /tmp/dd/Build/Products/Debug-iphonesimulator/SEUWiki.app
xcrun simctl launch booted tech.iflink.seuwiki -uitab experience
xcrun simctl launch booted tech.iflink.seuwiki -uidoc "survival/观点篇/1-认识"
xcrun simctl io booted screenshot /tmp/shot.png
```

模拟器截图验证是**唯一**能发现这类静默 bug 的手段——上面三个 bug 有两个是截图直接看出来的。
