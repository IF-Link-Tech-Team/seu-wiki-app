# 开发进度

## 已完成（2026-10-04）

- [x] Xcode 工程脚手架（iOS 26 / Swift 6.2，文件系统同步组，`SEUWiki/SEUWiki/`）
- [x] 五 Tab 骨架：`Tab` API + `Tab(role: .search)` + `tabBarMinimizeBehavior(.onScrollDown)`
- [x] 数据模型对齐真实 API：FeedItem/CampusAudience（seu-wiki-v2）、ForumPost/Topic（iflab-forum）、手册/提醒/课程/工具
- [x] 设计系统：cardStyle、groupedBackground、ConsoleBar、profileEntry、appNavigationDestinations
- [x] 主页：bento（提醒倒计时 + 下一节课）+ 与我有关的通知 + 论坛新帖
- [x] 资讯：为你精选 / 全部（筛选 sheet）/ 8 分类 console；详情页底部「在网页中打开 + 设定提醒」；提醒编辑对齐提醒事项（原生 Form/DatePicker）
- [x] 经验：热门/关注/话题/生存手册 四 console + 侧滑切换；话题广场（播客分类式彩卡）；手册分类（节点导航式两列）→ 分组 List → 文档页；帖子详情（点赞/收藏/评论楼中楼）
- [x] 工具：快捷指令资料库式彩色网格；课表页（与主页联动，同读 UserProfile.courses）
- [x] 搜索：三信源聚合（通知/经验/手册分区卡片 + 查看更多 + 命中加粗高亮 + scope console）
- [x] 个人页：原生登录 UI（AuthStore stub）+ 画像编辑 + 我的提醒/收藏/关注
- [x] seu-forum 后端项目初始化（独立 git 仓库，基于 iflab-forum 复刻裁剪）——进行中

## 下一步（按优先级）

1. **seu-forum 后端收尾**：裁剪 products 线、话题目录替换、README；后续补充关注/通知/搜索 API
2. **真实数据接入**：资讯接 seu-wiki-v2 `/api/site/timeline` `/for-you` `/pool`（Models 已对齐契约，建 Services/FeedService.swift）
3. **Logto 登录接线**：AuthStore → OIDC PKCE（auth.iflink.tech，LOGTO_NATIVE_APP_ID），参考 Reference/iflab-forum/docs/auth.md 的 Bearer 契约
4. **持久化**：UserProfile 的提醒/关注/收藏目前内存态，接 SwiftData 或 App Group UserDefaults
5. **推送**：APNs（seu-wiki-v2 无 push 通道，需基于 /api/v1/selected/changes 自建）
6. **工具页实功能**：课表数据源（教务系统）、绩点计算器、考试安排
7. **图标与启动屏**：AppIcon 设计（当前为空占位）

## 构建验证

```bash
xcodebuild -project SEUWiki/SEUWiki.xcodeproj -scheme SEUWiki \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

模拟器截图验证：`xcrun simctl install/launch/io screenshot`，bundle id `tech.iflink.seuwiki`。
