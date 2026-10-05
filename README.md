# SEU.wiki（iOS）

面向东南大学学生的原生 iOS 应用：聚合校园资讯、沉淀学习经验、直达校园服务。

## 功能结构（5 个 Tab）

| Tab | 内容 |
|---|---|
| 主页 | bento 卡片：提醒倒计时、下一节课、与我有关的通知、精选经验长文 |
| 资讯 | 全校通知信息流（源自 seu-wiki-v2），为你精选 / 全部（可筛选）/ 分类 console，详情页可设定截止提醒 |
| 经验 | 热门 / 关注 / 话题 / 东大生存手册；「热门」与手册均为**真实后端长文**，含正文、目录跳转、锚点定位 |
| 工具 | 课表、绩点计算等校园工具；**未上线的工具显式标注「即将推出」并置灰不可点** |
| 搜索 | 一次搜索聚合三个信源：通知 / 经验 / 手册（全部走 `/api/site/pool` 真实检索） |

个人页面与设置统一在各 Tab 右上角，登录走 IF.Link 生态自部署 Logto（原生界面，非网页跳转）。

## 数据来源

只读 API，全部实测确认（`curl` 验证过契约）：

| 端点 | 用途 | 备注 |
|---|---|---|
| `/api/site/timeline` | 全部通知 | cursor 分页 |
| `/api/site/for-you` | 为你精选 | cursor **绑定画像**，改画像须重置 cursor |
| `/api/site/items/{id}` | 通知详情 | |
| `/api/site/pool?q=&type=` | 统一搜索 | 同时返回 `items`（通知）与 `docs[]`（经验/手册，含 `anchor`） |
| `/api/site/docs/survival` | 生存手册目录树 | 篇 → 组 → 条 |
| `/api/site/docs/experience` | 经验长文 | 带 `filters` 分面（场景/年级/学院） |
| `/api/site/docs/{slug}` | 长文详情 | 返回 `html` + **`headings`**（`{id,text,depth}`） |

两条硬约束（都踩过坑，已写进代码注释）：

1. **`/api/site/*` 不校验鉴权，因此不发送 Logto token。** 发了只扩大暴露面，还会把 token 续期链路拽进来。
2. **slug 形如 `survival/观点篇/1-认识`，斜杠必须保留字面量，只编码非 ASCII 部分**，且拼 URL 要用 `URLComponents.percentEncodedPath`（用 `path` 会把 `%` 二次转义成 `%25`，全站中文文档详情 404）。

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
head -1 "$DC/Documents/selfcheck.txt"   # 例如 128/128 通过
grep '^FAIL' "$DC/Documents/selfcheck.txt"
```

无头模拟器验收用的启动参数（仅 DEBUG，Release 不含）：

```bash
xcrun simctl launch booted tech.iflink.seuwiki -uitab experience   # 直达某个 tab
xcrun simctl launch booted tech.iflink.seuwiki -uidoc "survival/观点篇/1-认识"  # 直达长文详情
xcrun simctl launch booted tech.iflink.seuwiki -uipush <feedItemID>  # 模拟点开提醒通知，直达该条资讯
```

## 目录

```
SEUWiki/SEUWiki/
├── App/          # 入口与根 TabView（含 DEBUG 深链参数）
├── Models/       # 数据模型（对齐真实 API）、ToolCatalog
├── Design/       # 共享设计组件（卡片、ConsoleBar、导航目的地、品牌色）
├── Services/     # FeedService、ReminderScheduler、NotificationCenterDelegate、SelfCheck、Paging、TimeFormat
├── Stores/       # UserProfile、FeedStore 等 @Observable 状态
└── Features/     # Home / Feed / Experience / Tools / Search / Profile
```

## 自检套件

`Services/SelfCheck.swift` 在 DEBUG 启动时自动执行 128 条断言，覆盖：日期解析、相对时间、绩点计算、分页去重、slug 编码、URL 组装、后端字段契约、画像指纹、颜色对比度、提醒徽标、提醒通知契约（`userInfo` 的 key、触发时刻算法）、SF Symbol 有效性、持久化容错。

其中 66 条是 SF Symbol 校验：`Image(systemName:)` 拿到不存在的名字**不报错、只画空白**，构建照样全绿。`checkSFSymbols()` 把工程用到的每个 SF 名用 `UIImage(systemName:)` 验一遍 —— 这条是安卓端在模拟器截图里发现「收藏按钮渲染成九宫格」之后补的，安卓那边兜底成了一个语义完全不相干的图形，iOS 这边兜底是空白。清单是照源码全量扫出来的，**新增图标要往 `usedSFSymbols` 里加一行**。

它抓到过五个真实 bug（`Double("inf")` 返回 `inf` 而非 nil、`%25` 双重编码、目录字段名写成 `outline` 而后端是 `headings`、`userInfo` key 写错导致点通知静默失效、夏令时用减 86400 秒会让提醒差一小时）——**这些都是代码审查看不出来、只有断言能抓住的**。新增这类修复时请一并补断言。
