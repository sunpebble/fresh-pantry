# Changelog

## [1.14.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.13.1...fresh_pantry-v1.14.0) (2026-06-13)


### Features

* **diagnostics:** Diagnostics 门面协议 + measure 默认 + Noop ([ab7c919](https://github.com/kunish/fresh_pantry/commit/ab7c919d2b7c8386208d0a19605949b32d76132e))
* **diagnostics:** DiagnosticsFactory(按构建配置分流 sink) ([0d857bd](https://github.com/kunish/fresh_pantry/commit/0d857bdeb0d6134889a55ed6580ca15d42fc070f))
* **diagnostics:** OSLogDiagnostics(DEBUG 本地可见 sink) ([ba12c70](https://github.com/kunish/fresh_pantry/commit/ba12c708d8fa617d2ff0f550af677d69d6f5f756))
* **diagnostics:** SentryDiagnostics(#if !DEBUG 的 Sentry sink) ([b2588e8](https://github.com/kunish/fresh_pantry/commit/b2588e83d22c89cb01bdb11c0ae7cc3797fec45b))
* **diagnostics:** 同步流程埋点 + AppDependencies DI 接线 ([c7700fa](https://github.com/kunish/fresh_pantry/commit/c7700faf1a7479aac6b871bb28678fca891b93b0))
* **ios:** add DebugMenuGate (hidden debug-menu unlock state) ([ff54419](https://github.com/kunish/fresh_pantry/commit/ff54419b97971fc2bb91a24fb4a55abc181301ab))
* **ios:** add DebugMenuView (feature-flag toggles) ([b648e04](https://github.com/kunish/fresh_pantry/commit/b648e04053fdb8580a92ad2fc989837ca8126326))
* **ios:** add FeatureFlag registry ([120ea00](https://github.com/kunish/fresh_pantry/commit/120ea008fb2d67f075bee98a078290357d10a96d))
* **ios:** add FeatureFlagStore (UserDefaults override store) ([e40774c](https://github.com/kunish/fresh_pantry/commit/e40774cf145df81a1abeec69d574ac04a8f6b596))
* **ios:** hidden debug menu unlock + demo flag row in Settings ([31624ee](https://github.com/kunish/fresh_pantry/commit/31624eeb070beb45239c0d298a9740ce6e911ba6))
* **ios:** wire FeatureFlagStore + DebugMenuGate into AppDependencies ([52f77ca](https://github.com/kunish/fresh_pantry/commit/52f77ca62cd95339c43f4b05a336ce6d7566c6c1))
* 食材用量数字化为无损 schema(管线+iOS+364 条数据) ([8cb35b3](https://github.com/kunish/fresh_pantry/commit/8cb35b3d2d773792309f5ad1affc2b20fe6934bc))


### Bug Fixes

* **ios:** 跨 tab 意图可靠投递 + 食谱目录远程化 ([e2f9403](https://github.com/kunish/fresh_pantry/commit/e2f9403e9403d7c11fa231bbff5fe2e6162e025a))

## [1.13.1](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.13.0...fresh_pantry-v1.13.1) (2026-06-12)


### Bug Fixes

* 闭合 13 处无闭环功能(静默吞错/流程断裂/并发丢写) ([773dbaf](https://github.com/kunish/fresh_pantry/commit/773dbaf8b49fca399f9f0130d1c912ca408adb31))

## [1.13.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.12.3...fresh_pantry-v1.13.0) (2026-06-12)


### Features

* **ios:** exclude expired stock from matching, incremental sync, and food log history ([82d38a4](https://github.com/kunish/fresh_pantry/commit/82d38a4fee2f7973eaf8f1294acfd3bf04fc545c))
* **ios:** household warning, sync failures, search, and cross-tab navigation ([0c952c5](https://github.com/kunish/fresh_pantry/commit/0c952c585cd615782aa843101ab22f041fbcd187))


### Bug Fixes

* **ios:** quick wins for meal plan, imports, backup, and expiring fallback ([b43b1ed](https://github.com/kunish/fresh_pantry/commit/b43b1ed01902785e95449f85d8ef47e9043afb65))

## [1.12.3](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.12.2...fresh_pantry-v1.12.3) (2026-06-12)


### Bug Fixes

* **ios:** move 食材分类 tile entrance animation into button label ([bab559f](https://github.com/kunish/fresh_pantry/commit/bab559fdf35b0e5b95fa24b046aa2beacddedd5b))

## [1.12.2](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.12.1...fresh_pantry-v1.12.2) (2026-06-12)


### Bug Fixes

* **ios:** restore persisted household scope at launch (offline-first) ([47b42db](https://github.com/kunish/fresh_pantry/commit/47b42db52042b65d7b14c03b0b3ab7a4bb8a7e53))

## [1.12.1](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.12.0...fresh_pantry-v1.12.1) (2026-06-11)


### Bug Fixes

* **ios:** 头像保存重试重传头像 + 暴露底层错误 ([fdb3228](https://github.com/kunish/fresh_pantry/commit/fdb3228050b80556488c931aa9ea382c2a46e915))

## [1.12.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.11.0...fresh_pantry-v1.12.0) (2026-06-11)


### Features

* **ios:** 会话与同步状态机闭环——登出停转 + 死信解阻 + 深链有反馈 ([8c09454](https://github.com/kunish/fresh_pantry/commit/8c09454465857fc14bf2ada3673a4c7f96a87cb9))
* **ios:** 分享扩展失败反馈——不支持的分享先提示再关闭,不再静默吞掉 ([9ec0425](https://github.com/kunish/fresh_pantry/commit/9ec0425678a3106af7e621ad966bb8863eb2070a))
* **ios:** 库存记账与录入闭环——批量删除去向追问 + 失败上浮 + 重试可用 ([eb90114](https://github.com/kunish/fresh_pantry/commit/eb90114ac0c4beb670212826df705042e7210d34))
* **ios:** 数据备份闭环——补全五类数据 + 导入走同步管线不再被回滚 ([9f23062](https://github.com/kunish/fresh_pantry/commit/9f23062229c1719c72ffcb5b96e6beb4170755c2))
* **ios:** 膳食计划闭环——完成餐衔接扣减 + 缺料口径对齐 + 可达的删除 ([0638510](https://github.com/kunish/fresh_pantry/commit/063851004e0ac0759217d624ef1ef88fa25ed5bf))
* **ios:** 菜谱闭环——编辑后刷新 + 扣减失败可见 + 烹饪模式收尾衔接 ([6a9a5e8](https://github.com/kunish/fresh_pantry/commit/6a9a5e86d9bc19a8d08e786c5fde324c35f8c918))
* **ios:** 设置反馈闭环——Profile 显式重试 + AI 设置 Keychain 失败不再假成功 ([334a2be](https://github.com/kunish/fresh_pantry/commit/334a2be7813f1f7b0a667404f28f241839e430bf))
* **ios:** 购物闭环——写前重读防丢行 + 三态反馈 + 入库审核失败可见 ([e243bbc](https://github.com/kunish/fresh_pantry/commit/e243bbc976e5ea6fd72250121ba2a6baea497fcb))
* **ios:** 通知提醒闭环——权限短路根因 + 库存变更后真重排 + 前台横幅 ([82767ca](https://github.com/kunish/fresh_pantry/commit/82767caee46a1277483077bd566db29caaf61842))
* **ios:** 首页与统计刷新闭环——主数据随变更刷新 + 临期撤销 + 死反馈复活 ([993ba3e](https://github.com/kunish/fresh_pantry/commit/993ba3e1ff25f11982637c804823e0becea37435))


### Bug Fixes

* **ios:** 重建设置「我」卡片丢失的定义,修复主干编译断裂 ([a209558](https://github.com/kunish/fresh_pantry/commit/a2095588247a377380cdf4c70d1c821511acc03d))

## [1.11.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.10.0...fresh_pantry-v1.11.0) (2026-06-11)


### Features

* **ios:** 个人资料详情页 + 设置页顶部「我」卡片入口 ([2cf061d](https://github.com/kunish/fresh_pantry/commit/2cf061de1c7999460b3bc0bd7156db5e96a7e96b))

## [1.10.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.9.0...fresh_pantry-v1.10.0) (2026-06-11)


### Features

* **ios:** AppDependencies 注入 profileRepository + profileStore ([9b67684](https://github.com/kunish/fresh_pantry/commit/9b6768451afbf791d2d31bd116c44f63fbc18d0c))
* **ios:** HouseholdMember 加 display_name/nickname/avatar_path + resolvedName ([5d29a5d](https://github.com/kunish/fresh_pantry/commit/5d29a5d365b32771efe05234f20bb1930ca4a2d0))
* **ios:** ProfileEditView（头像 PhotosPicker + 名称/昵称,编辑/onboarding 共用） ([5f78308](https://github.com/kunish/fresh_pantry/commit/5f78308a2b29038740f1bff57cd48b0bc8cf55fa))
* **ios:** ProfileRecord + ProfileRepository（单行本地缓存 + pending） ([a5611a1](https://github.com/kunish/fresh_pantry/commit/a5611a1436ef6ffcd7e736e8722f5424171cd621))
* **ios:** ProfileStore（乐观保存 + 失败保留 pending + needsProfileSetup） ([ae1c88a](https://github.com/kunish/fresh_pantry/commit/ae1c88aa1421f4412abe196a99682b898d173d59))
* **ios:** RemotePantryRepository 加 profile load/upsert + avatar 上传/URL（ProfileRemote） ([611c7e8](https://github.com/kunish/fresh_pantry/commit/611c7e83d77e2d5c396053e411f96ee9dc222eb6))
* **ios:** Settings 个人资料入口 + 家庭成员行显示头像/名称 ([7afd48e](https://github.com/kunish/fresh_pantry/commit/7afd48e1fe8091a06a0336e5ee27262f40331d10))
* **ios:** UserProfile DTO（snake_case lenient 解码） ([5d46b84](https://github.com/kunish/fresh_pantry/commit/5d46b84ceec9373d43704c9e93f4f35b857267c2))
* **ios:** 登录后 onboarding 强制填写个人信息(显示名) ([ef6f94f](https://github.com/kunish/fresh_pantry/commit/ef6f94f36cb32542cd433d3a0517302bcb3bd2ab))


### Bug Fixes

* **ios:** refreshOwnerPendingInvites 加 owner 门控，非 owner 成员加载不再撞 Not authorized ([16a4764](https://github.com/kunish/fresh_pantry/commit/16a4764c2b909f2bfe31009b1813b1c8b1afe334))
* **profile:** code review 跟进 —— migration DROP FUNCTION + storage policy 幂等 + 注释订正 ([8be57ff](https://github.com/kunish/fresh_pantry/commit/8be57ff3610039d62a41551e93a9770d30104d12))

## [1.9.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.8.0...fresh_pantry-v1.9.0) (2026-06-11)


### Features

* **ios:** FoodLog 去向/撤销写入家庭同步 outbox(create/软删) ([07eda4e](https://github.com/kunish/fresh_pantry/commit/07eda4eb138c56fa71a21e9066cd69d906c70ec2))
* **ios:** FoodLog 同步 codec + gateway 分支 + SyncEntityType.foodLogEntry ([7cd17b8](https://github.com/kunish/fresh_pantry/commit/7cd17b827384e137cb301f7fc18f35649d0ee57b))
* **ios:** FoodLogEntry id 切换为 UUID(家庭同步前置) ([6744e96](https://github.com/kunish/fresh_pantry/commit/6744e969bd82aa9f08c521e3eeeb357fded8cc5b))
* **ios:** FoodLogRepository 加一次性幂等 id 迁移(fl_→UUID) ([2df67d9](https://github.com/kunish/fresh_pantry/commit/2df67d98fecea718802238a56a484f68c09a45c7))
* **ios:** HouseholdContentSyncCoordinator 接入 FoodLog 同步 + 启动 id 迁移 ([5be8a3b](https://github.com/kunish/fresh_pantry/commit/5be8a3bb8353da97b9f1407df5c81825d9f0f1c0))
* **ios:** HouseholdMergePolicy.mergeFoodLog(append-only 并集) ([c5515d7](https://github.com/kunish/fresh_pantry/commit/c5515d737ef28cd78003d9ab2dc7a97c56d28c39))
* **ios:** RemotePantryRepository 加 food_log_entries load/upsert/watch ([b1e5a1e](https://github.com/kunish/fresh_pantry/commit/b1e5a1e90988455268fda9b653c438ee4d0fd3c4))


### Bug Fixes

* **ios:** code review 跟进 —— 迁移失败可见 + 远端 FoodLog 行 name 守卫 ([958604a](https://github.com/kunish/fresh_pantry/commit/958604a1c00bbf0d1f7b0b1b64c0b4abdabe7250))

## [1.8.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.7.0...fresh_pantry-v1.8.0) (2026-06-10)


### Features

* **ios:** 竞品调研驱动的 15 项功能补齐 ([eb12444](https://github.com/kunish/fresh_pantry/commit/eb1244441f43b6e9a2e0968779b4803e178563d9))

## [1.7.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.6.0...fresh_pantry-v1.7.0) (2026-06-09)


### Features

* **ios:** 明亮/暗黑模式切换 + 全调色板自适应暗色化 ([c0692ce](https://github.com/kunish/fresh_pantry/commit/c0692ce201c1293f97fe774b07f54862bdc6dae5))

## [1.6.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.5.0...fresh_pantry-v1.6.0) (2026-06-09)


### Features

* **ios:** 入库审核行食材名称内联编辑 + 临期屏提醒状态卡 ([42f687e](https://github.com/kunish/fresh_pantry/commit/42f687e25e2b2f31c22a504b1d8165798f3ec6c7))
* **ios:** 减废「最常浪费」榜单 + 设置减废成效入口 ([3ed4d98](https://github.com/kunish/fresh_pantry/commit/3ed4d98e65a4fe70030c102d689f5478a9a28235))
* **ios:** 数据备份剪贴板复制/粘贴 ([a965ee9](https://github.com/kunish/fresh_pantry/commit/a965ee9a6c654f5307bd94d1d8b1cd9e5872a801))
* **ios:** 购物清单分类分组折叠/展开 ([f411360](https://github.com/kunish/fresh_pantry/commit/f4113603f5ee5756028d277188f92c3f48e0aa6c))
* **ios:** 首页 Hero 显示「· N 类」食材分类数 ([d12dd83](https://github.com/kunish/fresh_pantry/commit/d12dd83ee47010b188dcc756ac20e30aaabad8f2))

## [1.5.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.4.0...fresh_pantry-v1.5.0) (2026-06-09)


### Features

* **ios:** 外部入口与接线 —— 邀请深链 + 系统分享导入 + 首页导航接线 ([81cdfb5](https://github.com/kunish/fresh_pantry/commit/81cdfb5c29cc76d592955dda2bfdd3ff62a29a13))
* **ios:** 家庭共享 —— 收到/发出邀请、邀请二维码、设置红点 ([f89d0a4](https://github.com/kunish/fresh_pantry/commit/f89d0a4a314e1e06666c6577027ee128f1d4d4c0))
* **ios:** 自定义食谱食材/步骤上下移动重排 ([1daf1ea](https://github.com/kunish/fresh_pantry/commit/1daf1ea08e5774325435a0b64084621bdf31e001))
* **ios:** 饮食偏好预设并接入「现有/今日推荐」加权排序 ([cf56d8e](https://github.com/kunish/fresh_pantry/commit/cf56d8edac5b6facdfaf5cbc9c861b34a9226613))
* **ios:** 首页发现 —— 全局搜索浮层 + 食材分类网格下钻(含首页/库存清理) ([543cb2a](https://github.com/kunish/fresh_pantry/commit/543cb2a861a7b5eaec12451e2e0708f6b6171ff3))

## [1.4.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.3.0...fresh_pantry-v1.4.0) (2026-06-09)


### Features

* **ios:** 回填 Flutter→iOS 平价缺口(编辑食材/缺料菜谱/采购入库/离线同步横幅) ([cde3f07](https://github.com/kunish/fresh_pantry/commit/cde3f07563d44718c214f802fb872b45546827b4))

## [1.3.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.2.1...fresh_pantry-v1.3.0) (2026-06-09)


### Features

* **ios:** 原生 SwiftUI 重写(apps/ios) ([417aada](https://github.com/kunish/fresh_pantry/commit/417aada087920960d08a65756a97a061f5f88da4))
* **ios:** 接入 Sentry 崩溃监控/会话回放(sentry-cocoa 9.16.1) ([79ddc88](https://github.com/kunish/fresh_pantry/commit/79ddc8883a1befe092f6cb1438078745e1bbc225))


### Bug Fixes

* **ios:** 收尾迁移待办三项(urgency 文案/Ingredient Hashable/查询确定性) ([b72f75b](https://github.com/kunish/fresh_pantry/commit/b72f75b444f52ad65e3682cf6e644aace2f236d0))
