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
- [x] seu-forum 后端（独立 git 仓库 `seu-forum/`）：复刻 iflab-forum，裁剪 products 线（−5213 行）、话题目录替换为 8 主题 + 29 子标签、品牌重写；tsc/eslint/next build/21 项测试/PostgreSQL 权限门禁全部通过
- [x] seu-forum 已部署到 iflink-prod：`seu_forum` 库 + `seu-forum-postgrest`:3503 + `seu-forum-app`:3502（healthy）+ Caddy `http://forum.seu.wiki` 已按 Host 路由配好；公网待 EdgeOne DNS（用户操作）；Logto/COS 为占位凭据
- [x] Logto 登录基础：URL scheme `tech.iflink.seuwiki` + AuthConfig 单点配置（clientID 待注册）
- [x] 资讯模块接线上真实 API（https://seu.wiki，timeline/for-you cursor 分页 + 详情 + Mock 离线回退）；主页通知区同步接 for-you
- [x] UserProfile 本地持久化（UserDefaults + Codable，8 项属性自动落盘/启动恢复，DEBUG 自检）
- [x] 工具页绩点计算器（五分制换算、加权汇总、本地持久化；换算规则为手册假设，待教务处口径确认）
- [x] 搜索「通知」信源接线上 /api/site/pool（防抖/分页/Mock 回退）；经验信源已抽象 provider 待接 seu-forum
- [x] App 图标（东大绿 + 白色书本/W，CoreGraphics 生成，模拟器主屏验证）

## 下一步（按优先级）

1. **等待用户操作**：EdgeOne 配 forum.seu.wiki（配好后公网验证 + 论坛/搜索经验信源接 seu-forum 真实数据）；Logto 控制台注册 Web 应用（论坛）+ Native 应用（iOS）——两组 App ID/Secret 到手后接登录
2. **论坛接 seu-forum**：经验模块帖子/评论/点赞从 seu-forum API 读取（等 DNS 生效）
5. **推送**：APNs（seu-wiki-v2 无 push 通道，需基于 /api/v1/selected/changes 自建）
6. **工具页实功能**：课表数据源（教务系统）、考试安排
7. **启动屏**：Launch Screen 品牌化（当前系统默认）

## 构建验证

```bash
xcodebuild -project SEUWiki/SEUWiki.xcodeproj -scheme SEUWiki \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

模拟器截图验证：`xcrun simctl install/launch/io screenshot`，bundle id `tech.iflink.seuwiki`。
