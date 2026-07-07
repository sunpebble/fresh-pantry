# Changelog

## [2.4.1](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.4.0...fresh_pantry-v2.4.1) (2026-07-07)


### Bug Fixes

* **i18n:** 用显式 substitution 消除 xcstrings 复数 variation 警告 ([653fd48](https://github.com/sunpebble/fresh-pantry/commit/653fd48a89534c253bef320748dd349490ed49ec))

## [2.4.0](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.3.4...fresh_pantry-v2.4.0) (2026-07-07)


### Features

* focus home on recommendations, ingredients and recipes ([9e2c9dd](https://github.com/sunpebble/fresh-pantry/commit/9e2c9dd6bcf4208a0b5f768f66fd5ede95986425))

## [2.3.4](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.3.3...fresh_pantry-v2.3.4) (2026-07-06)


### Bug Fixes

* **recipes:** 移除观看视频入口 ([d5ae95e](https://github.com/sunpebble/fresh-pantry/commit/d5ae95eb976dafd04da634387bcc9ece968c7302))

## [2.3.3](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.3.2...fresh_pantry-v2.3.3) (2026-07-06)


### Bug Fixes

* **i18n:** 保留本土化食材匹配别名 ([b903faf](https://github.com/sunpebble/fresh-pantry/commit/b903faf7761d7fab46ba092efd9d2e270d4ecfa5))

## [2.3.2](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.3.1...fresh_pantry-v2.3.2) (2026-07-06)


### Bug Fixes

* **i18n:** 补齐真实库存名称本地化 ([c5ae90c](https://github.com/sunpebble/fresh-pantry/commit/c5ae90c9c567bc5476077a92d5f74b9d641a3421))
* **ui:** avoid clipped category counts ([497108c](https://github.com/sunpebble/fresh-pantry/commit/497108cc77410e373962afb05902ba779005dfde))

## [2.3.1](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.3.0...fresh_pantry-v2.3.1) (2026-07-06)


### Bug Fixes

* **i18n:** 补齐菜谱和库存文案本地化 ([3eb41a1](https://github.com/sunpebble/fresh-pantry/commit/3eb41a1b1e4f8fd67de52ce81bc0da846402da5c))

## [2.3.0](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.2.1...fresh_pantry-v2.3.0) (2026-07-06)


### Features

* **ios:** 不再打包菜谱 JSON ([4672d04](https://github.com/sunpebble/fresh-pantry/commit/4672d04691ab1a5d0d84620f7d77b020ffab162f))

## [2.2.1](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.2.0...fresh_pantry-v2.2.1) (2026-07-06)


### Bug Fixes

* **ios:** 固定 UI 测试语言 ([6751404](https://github.com/sunpebble/fresh-pantry/commit/67514047e49984820956e3931635686696cf3345))

## [2.2.0](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.1.2...fresh_pantry-v2.2.0) (2026-07-05)


### Features

* **i18n:** 生成 DeepSeek 食谱翻译 overlay ([7b06996](https://github.com/sunpebble/fresh-pantry/commit/7b069962bfa0a8629cfa02e262f91a9f1728e9b7))
* **i18n:** 补齐 iOS 多语言与食谱 overlay 接入 ([e12695a](https://github.com/sunpebble/fresh-pantry/commit/e12695a1f4cf57430710ba3d41744f3fe1f99bce))
* **ios:** AI 错误文案本地化，429/401 按服务端 code 映射 ([63842b9](https://github.com/sunpebble/fresh-pantry/commit/63842b99e83737c07af92bdb6a105fdd1293c7b7))
* **ios:** Services 残留文案本地化（OCR/解析器/AI 服务错误提示） ([e25a7b7](https://github.com/sunpebble/fresh-pantry/commit/e25a7b7c6f2b08c224dc5c24219c7a4f0ebbe93f))
* **ios:** String Catalog 基建落地——Tab 标签四语言试点 ([fbc9ce1](https://github.com/sunpebble/fresh-pantry/commit/fbc9ce1e913b86a7782a29ed230b8aa6c70badda))
* **ios:** 设置/付费/备份文案本地化 ([686335e](https://github.com/sunpebble/fresh-pantry/commit/686335e0db85a1cfdee5f207853be2ae8ec4b4b5))
* **ios:** 通知文案本地化，en/fr 带复数变体 ([d93972a](https://github.com/sunpebble/fresh-pantry/commit/d93972aafac8374ad5618e9108a591cd50a537db))
* **ios:** 食谱/购物/规划/搜索/浪费洞察文案本地化 ([caffe90](https://github.com/sunpebble/fresh-pantry/commit/caffe90ffe729684656f2a4f967af1afec59e0e8))
* **ios:** 首页/库存/App 壳/组件文案本地化 ([f514b08](https://github.com/sunpebble/fresh-pantry/commit/f514b08f901d004d0e9d6556826c9b6169e89393))


### Bug Fixes

* **ios:** auth_missing 同样映射为重新登录文案 ([2c67c85](https://github.com/sunpebble/fresh-pantry/commit/2c67c85078aef108683b7556b3c37a09011d9e0c))
* **ios:** xcstrings key 调整为严格字母序 ([d58f493](https://github.com/sunpebble/fresh-pantry/commit/d58f493348f1c2051bd94f552d2b05aa5c9c1a9f))
* **ios:** 插值本地化 key 补格式后缀;check_i18n 增加 key 交叉引用闸门 ([b0800f6](https://github.com/sunpebble/fresh-pantry/commit/b0800f676ed87d948ef96a4cb0b265efa4bed488))
* **ios:** 计数文案改真复数变体;MealPlan 日期改 FormatStyle 跟随 locale ([810277e](https://github.com/sunpebble/fresh-pantry/commit/810277ed92935528ecc26c8b08b6bf3bb0d97de4))
* **ios:** 食谱日期改 FormatStyle;语音识别跟随界面语言 ([3823403](https://github.com/sunpebble/fresh-pantry/commit/3823403903e113b0cc5b288e75f522aac16fb997))
* **ios:** 首页分类网格接 displayLabel;单位 picker 选项本地化 ([93e0f78](https://github.com/sunpebble/fresh-pantry/commit/93e0f7854cd2424a3852803803b18980d8c1edba))

## [2.1.2](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.1.1...fresh_pantry-v2.1.2) (2026-07-05)


### Bug Fixes

* **ios:** Pro 用户设置页不再引导配置 AI——标明内置通道已可用 ([c85c1d1](https://github.com/sunpebble/fresh-pantry/commit/c85c1d13478e16edb891d59676bb0a0b840234cc))

## [2.1.1](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.1.0...fresh_pantry-v2.1.1) (2026-07-05)


### Bug Fixes

* **ios:** handle unavailable pro product ([d9674f8](https://github.com/sunpebble/fresh-pantry/commit/d9674f8ec075769bbafce9f74491fa9ad2262f29))

## [2.1.0](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v2.0.0...fresh_pantry-v2.1.0) (2026-07-05)


### Features

* **ios:** AI 调用点接入 Pro/内置/BYOK 三态门控 ([31b10bf](https://github.com/sunpebble/fresh-pantry/commit/31b10bf23889afbdbbbd2e686e594dc87f9dbaa9))
* **ios:** AiChatAccess 三态传输解析 + 内置 worker chatFn + 429 文案透传 ([cd52677](https://github.com/sunpebble/fresh-pantry/commit/cd52677deea67d1f912e9adf3c0d62bed67c47ac))
* **ios:** PaywallSheet/ProLockedView + Settings Pro 入口 ([b544347](https://github.com/sunpebble/fresh-pantry/commit/b544347d430ee0ffaee030b43f8779ea4b5245cb))
* **ios:** ProStore(StoreKit 2 买断) + FreeTier 配额 + StoreKit 本地配置 ([17b6cfb](https://github.com/sunpebble/fresh-pantry/commit/17b6cfb400adff72a9f1594a4177f709a88c3d42))
* **ios:** 免费版库存 50 条上限门控 ([32f607a](https://github.com/sunpebble/fresh-pantry/commit/32f607ac4f066427ef4b96ba980f9f3b50e5ac3f))
* **ios:** 家庭共享与周派餐 Pro 门控 ([aae1c99](https://github.com/sunpebble/fresh-pantry/commit/aae1c996522570b629e34be7f0559fc36f3349b0))


### Bug Fixes

* prepare auth for production ([c7a8bbb](https://github.com/sunpebble/fresh-pantry/commit/c7a8bbbe96c2514b61b57f2a5343fb07c61fce2b))

## [2.0.0](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v1.25.0...fresh_pantry-v2.0.0) (2026-07-03)


### ⚠ BREAKING CHANGES

* API 域名迁移至 api.freshpantry.sunpebblelabs.com

### Features

* API 域名迁移至 api.freshpantry.sunpebblelabs.com ([2ace26d](https://github.com/sunpebble/fresh-pantry/commit/2ace26d37b71b7aeb91989da95a8014fa8bb195b))

## [1.25.0](https://github.com/sunpebble/fresh-pantry/compare/fresh_pantry-v1.24.0...fresh_pantry-v1.25.0) (2026-07-03)


### Features

* App 图标重绘为 sunpebble 品牌配色 ([110f547](https://github.com/sunpebble/fresh-pantry/commit/110f547e05fbbd9f6af43f261584a9b1d042a87f))
* bundle id 迁移至 com.sunpebble.freshpantry,发布流程与其他 sunpebble app 统一 ([fd2bbc2](https://github.com/sunpebble/fresh-pantry/commit/fd2bbc203d3fbb647d58b2d70e22e73e88175650))
* 换肤到 sunpebble 品牌色——sun 金主色 + cream/ink 中性色 + 夜色深色模式 ([7ecb978](https://github.com/sunpebble/fresh-pantry/commit/7ecb978b035769c8e44af2a6e5d6e9c95b96f7ca))

## [1.24.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.23.4...fresh_pantry-v1.24.0) (2026-06-22)


### Features

* **ios:** 入库写入失败不再静默——重试 + Sentry + 应用内提示 ([9035e66](https://github.com/kunish/fresh_pantry/commit/9035e66ac9092f7909f8e482c203be9e7bf19dc6))

## [1.23.4](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.23.3...fresh_pantry-v1.23.4) (2026-06-20)


### Bug Fixes

* **ios:** Cook Mode 显式导入 Combine,修复倒计时发布者编译依赖 ([f895487](https://github.com/kunish/fresh_pantry/commit/f895487516526fe24d8f92210904103db5486383))

## [1.23.3](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.23.2...fresh_pantry-v1.23.3) (2026-06-17)


### Bug Fixes

* **ios:** 小组件勾选购物项后及时推送同步,消除「同步中,1 条待同步」滞留 ([dabcbd4](https://github.com/kunish/fresh_pantry/commit/dabcbd4dbbcd479d06ca2ff0e383101dab34998a))

## [1.23.2](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.23.1...fresh_pantry-v1.23.2) (2026-06-17)


### Bug Fixes

* **ios:** 小组件勾选购物项后 App 跟随刷新 ([c0defc8](https://github.com/kunish/fresh_pantry/commit/c0defc83f1cf3083c8900d192a425d52ba66ac79))

## [1.23.1](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.23.0...fresh_pantry-v1.23.1) (2026-06-17)


### Performance Improvements

* **ios:** 消除列表滚动时入场动画/分类头像弹入的「加载感」 ([f4e880c](https://github.com/kunish/fresh_pantry/commit/f4e880c354be52981faa59f0c603b96fbb8febbd))

## [1.23.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.22.2...fresh_pantry-v1.23.0) (2026-06-17)


### Features

* **ios:** 首页重构为仪表盘密集网格,提高信息密度 ([90d8152](https://github.com/kunish/fresh_pantry/commit/90d8152859b6889cb6eb6596475c5a2597065d87))

## [1.22.2](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.22.1...fresh_pantry-v1.22.2) (2026-06-17)


### Bug Fixes

* **ios:** FreshPantryWidgetKit 改静态库,把 widget intent 元数据合并进 app bundle ([01fd357](https://github.com/kunish/fresh_pantry/commit/01fd357e079b32ffd07a780499a6332f9bbbbd45))
* **ios:** widget framework 设 SKIP_INSTALL YES 修 Export IPA 失败 ([caefc0d](https://github.com/kunish/fresh_pantry/commit/caefc0d7b5cd78f33cdaa672fa68813f28fcc8eb))
* **ios:** widget intent 抽入共享 framework,根治真机交互/可配置失效 ([606c37e](https://github.com/kunish/fresh_pantry/commit/606c37e56fc117eac90d83b3a6847e468ee3eaed))
* **ios:** widget intent 改 dual-target membership 根治真机 no metadata ([eabc0a0](https://github.com/kunish/fresh_pantry/commit/eabc0a0adfca026649a12499ae9f47f048ecd629))

## [1.22.1](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.22.0...fresh_pantry-v1.22.1) (2026-06-16)


### Bug Fixes

* **ios:** widget 购物清单勾选点不动(容器 widgetURL 抢点 + 命中区过小) ([80605d2](https://github.com/kunish/fresh_pantry/commit/80605d207bde763a849fefaaf2aa26dd5879205d))

## [1.22.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.21.0...fresh_pantry-v1.22.0) (2026-06-16)


### Features

* **ios:** widget 锁屏配件按 4 类细化 + 补充一个可配置 widget ([ebd6276](https://github.com/kunish/fresh_pantry/commit/ebd62760338de2602dd577e7b44276f00bc14859))


### Bug Fixes

* **ios:** CI 改用 Xcode 27 构建 + 加回可配置 widget(真机 iOS 27 需 SDK 对齐) ([dd21225](https://github.com/kunish/fresh_pantry/commit/dd21225a71c74c81b19dc65f465f592f2fd4331e))
* **ios:** widget 改 4 个独立固定 widget(真机不认可配置 intent 的真根因) ([950051a](https://github.com/kunish/fresh_pantry/commit/950051a998c1f3cba76adbd0f2de64ca75707e98))
* **ios:** 修可配置 widget 真机不出「编辑小组件」(配置 intent 改 widget 专属 + 换新 kind) ([60e2d28](https://github.com/kunish/fresh_pantry/commit/60e2d289dd556f9e3f2e0cbbe2a6134e2193c655))
* **ios:** 移除真机不工作的可配置 widget,保留 4 个固定 widget + 细化配件 ([26d709e](https://github.com/kunish/fresh_pantry/commit/26d709e81599b26204da2c2de98390bc6c77826a))

## [1.21.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.20.0...fresh_pantry-v1.21.0) (2026-06-16)


### Features

* **ios:** app 集成 widget(写 App Group 身份/刷新触发/深链路由) ([0f929ee](https://github.com/kunish/fresh_pantry/commit/0f929ee4b7d17f4d6add48cddd2371ed2c3717cb))
* **ios:** ShoppingToggleService widget 勾选写路径 ([1276e12](https://github.com/kunish/fresh_pantry/commit/1276e12a282456101510a24d8ceb9312a05e9e27))
* **ios:** SwiftData store 迁移到 App Group 容器 + widget 只读变体 ([5b4d67e](https://github.com/kunish/fresh_pantry/commit/5b4d67e1a89f8556346a17586e45748f2d034069))
* **ios:** widget 扩展 target + App Group + 共享源码骨架 ([bcc47da](https://github.com/kunish/fresh_pantry/commit/bcc47daf09feabce8ba5dafe6fa69b85e143145d))
* **ios:** widget 视图(system + 锁屏配件)+ 装配 widget kind ([5e22d3f](https://github.com/kunish/fresh_pantry/commit/5e22d3fde593b4f67058b351edf4f2b32337c450))
* **ios:** widget 购物清单交互勾选(ToggleShoppingItemIntent) ([d985837](https://github.com/kunish/fresh_pantry/commit/d9858379dff28731ba2bc19501a1f49a3b0b5982))
* **ios:** widget 配置 intent + 时间线 Provider ([a3011a3](https://github.com/kunish/fresh_pantry/commit/a3011a3be40a76ffd05faf888d29698cfc0d8866))
* **ios:** WidgetDataReader 四类内容投影 ([7a7c3b0](https://github.com/kunish/fresh_pantry/commit/7a7c3b0c61e499b816782784819c3856f086ee7f))
* **ios:** WidgetDeepLinkRouter 深链路由解析 ([225e8ab](https://github.com/kunish/fresh_pantry/commit/225e8abba99deb7ecc36d5d80bf8c8ad61081944))
* **ios:** WidgetRefreshCoordinator 刷新 seam ([48af647](https://github.com/kunish/fresh_pantry/commit/48af647d28cff37eae6910c75b35893677c3af21))
* **ios:** WidgetSharedDefaults 跨进程身份通道 ([bd943c1](https://github.com/kunish/fresh_pantry/commit/bd943c1088d14422418a94c5d173c8ec9cf3f284))


### Bug Fixes

* **ios:** makeShared 打开失败回退默认位置 + 修正迁移调用者注释 ([bb60ded](https://github.com/kunish/fresh_pantry/commit/bb60ded092dcbff3a5675f9c8bd6adab6eacbe1a))
* **ios:** widget Info.plist 补 CFBundleExecutable(否则 appex 缺执行体名导致宿主 app 装不上) ([0e688d8](https://github.com/kunish/fresh_pantry/commit/0e688d89d8dadbc47d3c84bc8278405574a9f7d5))
* **ios:** widget Info.plist 补版本键以对齐父 app(消除 embed 校验 warning) ([cc2ac5a](https://github.com/kunish/fresh_pantry/commit/cc2ac5addfacaf1093797bc2c2815e1b803949ae))
* **ios:** widget reader 对齐 app 口径(日历 cutoff/displayTitle)+ 补 limit/空态测试 ([261d9b7](https://github.com/kunish/fresh_pantry/commit/261d9b7e601f6d761e5051133151ce0fcaf6102d))
* **ios:** widget 取数搬出扩展进程(app 预算快照写 App Group,时间线只读) ([f21dcd4](https://github.com/kunish/fresh_pantry/commit/f21dcd41c725e056f48905f4a33c03aeab243b04))
* **ios:** widget 扩展彻底移除 SwiftData/数据层(真机内存根因) ([c72c71e](https://github.com/kunish/fresh_pantry/commit/c72c71e5f7f13b1fec98fd1e19024f4612a718c5))
* **ios:** widget 按需只算当前内容快照(修真机加组件后停在占位空白) ([fcb0c3b](https://github.com/kunish/fresh_pantry/commit/fcb0c3baada628a5f3fc4e7c54027bf70b28c58b))

## [1.20.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.19.0...fresh_pantry-v1.20.0) (2026-06-14)


### Features

* **ios:** 食谱卡片长按快捷菜单(收藏/加入计划/加购缺料/编辑·删除) ([a5adf8b](https://github.com/kunish/fresh_pantry/commit/a5adf8ba903f9a05424ac65681c9e0da922dd88c))

## [1.19.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.18.0...fresh_pantry-v1.19.0) (2026-06-14)


### Features

* **ios:** [#15](https://github.com/kunish/fresh_pantry/issues/15) 减废去向口径 — 捐了/堆肥(donated/composted) ([d904bd5](https://github.com/kunish/fresh_pantry/commit/d904bd5c2a297730a4a39f39b7bd53c400acea00))
* **ios:** P4 收藏/忌口家庭同步 — 集合成员确定性 id + 端到端同步 ([e275b9d](https://github.com/kunish/fresh_pantry/commit/e275b9da45ae812d65a3839debf007b3d611e78d))
* **ios:** 懒饭对齐——贴士/内嵌视频/今天做什么 Intent/营养卡/步骤倒计时 ([8716cea](https://github.com/kunish/fresh_pantry/commit/8716cead7a1125a3e7d5ce824f52c8014ef0b496))
* **ios:** 竞品 follow-up — [#7](https://github.com/kunish/fresh_pantry/issues/7) RecipeCard 做过N次徽章 + [#16](https://github.com/kunish/fresh_pantry/issues/16) AI整理步骤预设 ([7fba958](https://github.com/kunish/fresh_pantry/commit/7fba95878d394547b9261b0a8b4c49d742daa288))
* **ios:** 竞品落地批次1 — 加购缩放传导/营养评分徽章/步骤食材内联/缩放分数显示 ([d3143d6](https://github.com/kunish/fresh_pantry/commit/d3143d6e108c2950bbe2b06fa7f1a700f5a29a7b))
* **ios:** 竞品落地批次10(Recipe区) — [#16](https://github.com/kunish/fresh_pantry/issues/16) AI步骤原子化(导入 prompt) ([6976909](https://github.com/kunish/fresh_pantry/commit/69769097cc0cd5b5fa9b2195c234b2dbfe606c11))
* **ios:** 竞品落地批次11(Recipe区) — [#6](https://github.com/kunish/fresh_pantry/issues/6) AI改写菜谱 ([9256ae2](https://github.com/kunish/fresh_pantry/commit/9256ae22a628849fb72d946a55c628a83302283d))
* **ios:** 竞品落地批次12(Recipe区) — [#7](https://github.com/kunish/fresh_pantry/issues/7) 做过次数/上次做履历(设备本地) ([0a42d64](https://github.com/kunish/fresh_pantry/commit/0a42d6429d29387113e30408fa6112eb38dec515))
* **ios:** 竞品落地批次13(Recipe区) — [#18](https://github.com/kunish/fresh_pantry/issues/18) 临期看板「→做这道菜」直达 ([e2f2df0](https://github.com/kunish/fresh_pantry/commit/e2f2df070914f83cede8c9273974509fd7c7fdcf))
* **ios:** 竞品落地批次2 — [#19](https://github.com/kunish/fresh_pantry/issues/19) 购物货架动线可拖拽自定义排序 ([9b2bf63](https://github.com/kunish/fresh_pantry/commit/9b2bf636284ab07b788ceed9fe2933aa4f9eecaa))
* **ios:** 竞品落地批次3 — [#15](https://github.com/kunish/fresh_pantry/issues/15) 减废游戏化(零浪费连胜+成就徽章) ([038a47c](https://github.com/kunish/fresh_pantry/commit/038a47c162f28286507199480357f37eb401a229))
* **ios:** 竞品落地批次4 — [#8](https://github.com/kunish/fresh_pantry/issues/8) 消耗速率预测式补货 ([0a93c43](https://github.com/kunish/fresh_pantry/commit/0a93c43f50091e89ac1e06bef1d0eaf7ad027c57))
* **ios:** 竞品落地批次5 — [#11](https://github.com/kunish/fresh_pantry/issues/11) 节气时令推荐 ([b332576](https://github.com/kunish/fresh_pantry/commit/b332576bedf3a69cfebf005ad4b4ab649eae8582))
* **ios:** 竞品落地批次6 — [#14](https://github.com/kunish/fresh_pantry/issues/14) 整周膳食模板 ([ccdf490](https://github.com/kunish/fresh_pantry/commit/ccdf4906ddf26270055b4c0154ff81126f110689))
* **ios:** 竞品落地批次7 — [#12](https://github.com/kunish/fresh_pantry/issues/12) MealPlan 便签+餐别+剩菜(payload-only,零SQL迁移) ([eb639d7](https://github.com/kunish/fresh_pantry/commit/eb639d773fc5844c09efdf995ab2ca3466e419b5))
* **ios:** 竞品落地批次8 — [#13](https://github.com/kunish/fresh_pantry/issues/13) App内语音口述录入 ([bec722b](https://github.com/kunish/fresh_pantry/commit/bec722b6f7b9302e33bb76c29ad8b5d8f17d7e43))
* **ios:** 竞品落地批次9(Recipe区) — [#4](https://github.com/kunish/fresh_pantry/issues/4) URL导入白名单放宽 + [#5](https://github.com/kunish/fresh_pantry/issues/5) 对话式约束生成 ([469b9ed](https://github.com/kunish/fresh_pantry/commit/469b9ed2f5a5bef416a9627649de5c9b0a647024))
* **pipeline:** 全量补菜谱营养/时长 + 灌 prod ([fe62126](https://github.com/kunish/fresh_pantry/commit/fe621265f4d29d58e8b93d5ffd4072ea006227a9))
* **pipeline:** 菜谱营养估算 + 每步时长 enrich + 灌库列 + iOS 读取 ([fa7510a](https://github.com/kunish/fresh_pantry/commit/fa7510a7261b8c72bcb49ed648d6df63df73535b))

## [1.18.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.17.0...fresh_pantry-v1.18.0) (2026-06-14)


### Features

* **ios:** 库存/食谱/膳食/减废多项功能补齐 + 收尾清理 ([9f572b8](https://github.com/kunish/fresh_pantry/commit/9f572b8e2d2db005495567c7912abb2384ced30c))

## [1.17.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.16.2...fresh_pantry-v1.17.0) (2026-06-13)


### Features

* **ios:** Recipe 加 videoUrl(encodeAlways + 向后兼容解码) ([40d58c8](https://github.com/kunish/fresh_pantry/commit/40d58c879c2b64c3b70eefb36b5f69dabc2e7cbc))
* **ios:** RemoteRecipeCatalog select 加 videoUrl:video_url 列别名 ([a1f16c5](https://github.com/kunish/fresh_pantry/commit/a1f16c577f9df508600f1c2915d1f01fd9f9144a))
* **ios:** 菜谱详情页加「观看视频」入口(SFSafariViewController 打开外链) ([9621667](https://github.com/kunish/fresh_pantry/commit/9621667f25611e4719f7190c86d11a425d90de8b))


### Performance Improvements

* **ios:** 入库 history 批量化 O(N²)→O(N) + 邀请卡片即时消失 ([8644e61](https://github.com/kunish/fresh_pantry/commit/8644e616b0a177345450e86f46f57921ef5dabfd))
* **ios:** 全部列表 mutation 改离线优先乐观更新——消除点击卡顿 ([0edf925](https://github.com/kunish/fresh_pantry/commit/0edf925f503eff96011531a65966a1858aa5c05f))

## [1.16.2](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.16.1...fresh_pantry-v1.16.2) (2026-06-13)


### Bug Fixes

* **ios:** 消除全部 Swift 6 并发隔离 warning(52→0) ([96d4e2d](https://github.com/kunish/fresh_pantry/commit/96d4e2dd1b00f7831bb695fa7331ff54d844f970))

## [1.16.1](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.16.0...fresh_pantry-v1.16.1) (2026-06-13)


### Bug Fixes

* **recipes:** 剔除混入食材列表的 26 个厨具 ([2c1d67a](https://github.com/kunish/fresh_pantry/commit/2c1d67a46d468a712078f901e60af804251ea016))

## [1.16.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.15.1...fresh_pantry-v1.16.0) (2026-06-13)


### Features

* **inventory:** 库存食材长按改为预览卡+快捷菜单(替代多选) ([06e3ca5](https://github.com/kunish/fresh_pantry/commit/06e3ca5339b705e26c745efa3fcee83b52c81563))
* **search:** 搜索支持拼音筛选——全拼/首字母/多音字校正 ([f334126](https://github.com/kunish/fresh_pantry/commit/f334126256263ef8a295256b8e46ab15408363d2))


### Bug Fixes

* **ios:** 家庭共享离线优先——切换数据不闪 + 管理页本地缓存 ([c9225af](https://github.com/kunish/fresh_pantry/commit/c9225afa39cfa3c462139c567ee0dddc1556f533))
* **recipes:** 回填缺量食材用量——步骤里的量不再漏 + 源无数字落「适量」 ([76aff06](https://github.com/kunish/fresh_pantry/commit/76aff06d43e4f750ff8645f06a0dc05cbf7a0dbd))


### Performance Improvements

* **ios:** 封面按尺寸解码 + 解码/目录 JSON 全移出主线程 + Replay 改 on-error ([74a1f64](https://github.com/kunish/fresh_pantry/commit/74a1f649ddc520f8872cdd5dd5810d3ac383c5e1))

## [1.15.1](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.15.0...fresh_pantry-v1.15.1) (2026-06-13)


### Bug Fixes

* **ios:** 抑制外部 503 噪声 + 移除封面解码主线程阻塞 ([95d9beb](https://github.com/kunish/fresh_pantry/commit/95d9beb2112d03a68971b5129bcbb2b0a23bee77))

## [1.15.0](https://github.com/kunish/fresh_pantry/compare/fresh_pantry-v1.14.0...fresh_pantry-v1.15.0) (2026-06-13)


### Features

* **recipes:** 封面联网补齐 + 迁 Supabase Storage + 全图离线磁盘缓存 ([4e31ed0](https://github.com/kunish/fresh_pantry/commit/4e31ed0799b64f10a2025481170d75219215f4ec))

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
