# fresh_pantry 竞品功能调研报告

> 生成日期:2026-06-14 · 多智能体调研(18 agents:代码盘点 + 8 品类竞品调研 + 逐品类差距分析 + 综合排序)
> 方法:1 个 Explore agent 基于真实代码盘点现有功能(36 项)→ 8 个 agent 联网调研 2024–2026 竞品 → 逐品类对照判定 have/partial/missing → 综合去重排序

---

## 一、执行摘要

fresh_pantry 在「库存录入(条码/小票/拍照 AI 多模态)、库存↔食谱↔购物↔减废的闭环、离线优先家庭同步」三大核心维度已对齐甚至领先竞品,基础架构(数字化食材 schema、AI 解析管线、OFF 集成、food_log)非常扎实。最值得抓的机会不是补大功能,而是「把已有数据/管线再榨一道价值」——一批低成本高感知的增量:加购路径补上缩放后用量、OFF 已返回但未取的健康/环保评分字段、菜谱「能消耗 N 个临期」量化排序、放宽食谱导入白名单、对话式约束生成与 AI 改写、做过次数履历。中长线则围绕「价格列」这条价值链(浪费金额/预算/环保 Impact)与双类保质期食安做战略拍板。

---

## 二、机会清单(去重排序)

| # | 功能 | 价值 | 成本 | 竞品参照 |
|---|------|:----:|:----:|----------|
| 1 | 份量缩放贯穿到「加购缺料」路径(携带缩放后 quantity/unit) | 高 | 低 | Mealime, Eat This Much, Plan to Eat, Paprika, Samsung Food |
| 2 | 扫码即出健康/环保评分(Nutri-Score A-E + NOVA 加工度 + Green-Score) | 高 | 低 | Yuka, Open Food Facts Nutri-Score/NOVA/Green-Score, Lifesum food rating |
| 3 | 菜谱按「能消耗多少临期/过期品」量化排序 + 「可消耗 N 个临期」徽章 | 高 | 低 | Cozzo, Grocy, Remy |
| 4 | 放宽食谱 URL 导入白名单到通用网页/主流站(B站/小红书描述+字幕文本) | 高 | 中 | Mela, Whisk, Samsung Food, SideChef, CookTok |
| 5 | 对话式「用我现有食材能做什么」配方生成(自由文本约束) | 高 | 中 | ChefGPT, Magic Chef, Samsung Food, SideChef |
| 6 | AI 按库存/忌口/饮食目标就地改写已有菜谱(转素食/低卡/替换过敏原/换在库食材) | 高 | 中 | Samsung Food Personalize Recipe, ChefGPT, SideChef |
| 7 | 菜谱「做过次数/上次做的日期」履历 + 多维排序 | 中 | 中 | AnyList, 下厨房, 豆果美食, 美食杰 |
| 8 | 消耗速率/复购周期预测式补货(融合 food_log + 临期 + 历史频次) | 高 | 中 | Listonic, Grocery AI, Remy, Amazon Alexa+ |
| 9 | 步骤内时间词自动识别为可启动计时器 + 常驻 HUD | 高 | 中 | Crouton, Mela |
| 10 | Cook Mode 步骤内食材词级内联标注(随缩放更新该步用量) | 高 | 中 | Crouton, Deglaze |
| 11 | 二十四节气/时令食材驱动的内容推荐卡 | 中 | 中 | 下厨房, 美食杰, 豆果美食 |
| 12 | 膳食计划支持「便签条目」+ 餐别分槽 + 剩菜排期(leftover) | 中 | 中 | AnyList, Plan to Eat, Paprika, Mealime |
| 13 | App 内语音口述录入(SFSpeech 听写 → 复用 AI 文本解析) | 中 | 中 | OurGroceries, KitchenPal, Grocery AI, SmartThings |
| 14 | 可复用的整周膳食计划模板(存为模板/一键铺到日历) | 中 | 中 | Paprika, Prepear, Plan to Eat |
| 15 | 减废成效游戏化:成就/徽章/连续打卡 streak + 多去向口径(捐了/堆肥) | 中 | 中 | Kitche 铜银金勺, Too Good To Go, Olio |
| 16 | AI 步骤原子化拆分(导入侧 prompt 强化 + 对已存菜谱「AI 整理步骤」) | 中 | 低 | Crouton AI 食谱简化拆步 |
| 17 | 缩放结果显示为干净分数(½ 杯/¼ 茶匙) | 中 | 低 | Deglaze, Paprika, Crouton |
| 18 | 购物清单货架动线可由用户拖拽自定义排序 | 中 | 中 | Listonic, Bring!, OurGroceries, Out of Milk |

### 详情

#### #1 份量缩放贯穿到「加购缺料」路径(携带缩放后 quantity/unit)  ·  价值高 / 成本低

RecipeDetailView/MealPlanView 的 addMissingToShopping 当前只调 addItem(name:category:),丢掉了食材的 quantity/unit 与 scaleFactor。把缩放后的 ingredient.quantity/unit 拼成 detail 传给 addItem,既修复「改了份量不进购物清单数量」这一竞品公认坑,又让已有的 ShoppingStore.mergeQuantity 跨菜谱同名同单位自动聚合真正生效。

**竞品参照**:Mealime, Eat This Much, Plan to Eat, Paprika, Samsung Food

**理由**:已验证:addItem 已接受 detail 形参,missingIngredients 已是数字化 quantity/unit,但两处加购都没传。纯客户端、无迁移、无签名,一处小改同时解决「缩放传导」与「跨菜谱用量合并」两个 partial 缺口,性价比最高。

#### #2 扫码即出健康/环保评分(Nutri-Score A-E + NOVA 加工度 + Green-Score)  ·  价值高 / 成本低

OFF product 对象免费返回 nutriscore_grade/nova_group/ecoscore_grade/additives_tags,但 OpenFoodFactsService 的 fields 列表只取到 nutriments,营养卡仅展示 4 个宏量。在 fields 加这几个字段、NutritionFacts 加属性、详情页营养卡加色块徽章即可。

**竞品参照**:Yuka, Open Food Facts Nutri-Score/NOVA/Green-Score, Lifesum food rating

**理由**:已验证:扫码+OFF 查询+营养卡三个环节全有,只是没取这几个字段。零额外网络请求、无迁移、无签名,把「记录」升级为「货架前买什么更健康/更环保」的决策依据,且减废=减碳叙事与本 App 主题天然契合。

#### #3 菜谱按「能消耗多少临期/过期品」量化排序 + 「可消耗 N 个临期」徽章  ·  价值高 / 成本低

已有「用临期」tab 与 RecipeMatching,但排序是「库存匹配+临期优先」的综合权重,非明确的「一道菜能用掉的临期品数量(Due Score)降序」。在 RecipeMatching 新增临期命中计数维度并在卡片展示「可消耗 N 个临期」徽章。

**竞品参照**:Cozzo, Grocy, Remy

**理由**:骨架(菜谱库+临期看板+匹配规则)全在,只需新增/调整一个排序维度+一个徽章,纯本地。把减废目标量化进排序,比泛泛「临期优先」更像当日减废菜单,是库存×菜谱的护城河。

#### #4 放宽食谱 URL 导入白名单到通用网页/主流站(B站/小红书描述+字幕文本)  ·  价值高 / 成本中

RecipePageFetcher 的 supportedRecipeHosts 硬编码仅 [lanfanapp.com, xiachufang.com],其它站直接报「暂不支持」。放宽到通用网页抓取(或加主流站 provider),先抓「正文/视频描述+字幕」文本喂现有 AiRecipeParser 管线。

**竞品参照**:Mela, Whisk, Samsung Food, SideChef, CookTok

**理由**:已验证白名单仅两站。完整 URL→AI→结构化管线已存在,瓶颈只是 host 白名单与抓取稳定性。用户高频诉求是导入「自己刷到的网红配方」。注意懒饭/下厨房外的视频源历史标过死路,故先做文本层(描述+字幕)、完整音视频还原才是 high。

#### #5 对话式「用我现有食材能做什么」配方生成(自由文本约束)  ·  价值高 / 成本中

已有 AiRecipeGenerator.fromIngredients(从临期食材名生成一道菜),但只接受食材名列表。补一个约束输入框(口味/时间/餐次/食材/无麸质等)+ 把忌口/份量/库存喂入 prompt,从「按食材生成」升级为「对话式约束生成」。

**竞品参照**:ChefGPT, Magic Chef, Samsung Food, SideChef

**理由**:库存+忌口+营养上下文与生成管线都已存在,补输入框与 prompt 拼装即可,无签名/迁移。是工具→助手的关键一跳,竞品(ChefGPT/Magic Chef)的核心差异点。

#### #6 AI 按库存/忌口/饮食目标就地改写已有菜谱(转素食/低卡/替换过敏原/换在库食材)  ·  价值高 / 成本中

现有忌口仅做「过滤隐藏」,AI 仅「另生成新菜」或「解析导入」。菜谱详情新增「AI 改写」动作,把现有菜谱 JSON+库存名单+忌口喂给 chatFn,复用 mapToDraft 出新版存为自定义菜谱。

**竞品参照**:Samsung Food Personalize Recipe, ChefGPT, SideChef

**理由**:AI 管线(mapToDraft 共享 schema)+忌口+库存+份量数据全在,新增一个改写 prompt + 复用 RecipeDraft→表单链即可,无签名/迁移。把忌口从被动隐藏升级为主动替换,差异化明显且能与库存联动(优先用在库食材替代)。

#### #7 菜谱「做过次数/上次做的日期」履历 + 多维排序  ·  价值中 / 成本中

全库无 cookCount/lastCooked(已验证)。给 Recipe 或独立计数模型加 cookCount/lastCookedAt,在 Cook 完成/膳食标记完成处累计+同步,新增「好久没做/最常做」排序选项与详情展示。

**竞品参照**:AnyList, 下厨房, 豆果美食, 美食杰

**理由**:Cook Mode 完成与 MealPlanEntry.done 已是天然采集点,记录几乎零额外采集成本,却能把静态 364 条菜谱库盘活成个性化资产。轻量子集(仅个人做过次数)纯本地可先做,拿到「个人烹饪履历」的一半价值,避开完整 UGC/社区的高成本。

#### #8 消耗速率/复购周期预测式补货(融合 food_log + 临期 + 历史频次)  ·  价值高 / 成本中

LowStock 目前只用「买过≥3 次且当前不在库」的纯频次模型。融合 food_log 消耗数据+临期信号+入库间隔,估算「预计 X 天后用完,建议补货」。

**竞品参照**:Listonic, Grocery AI, Remy, Amazon Alexa+

**理由**:本 App 独有 food_log 消耗日志+库存+临期三套数据,具备做真正预测式补货的天然基础——多数竞品做不到。纯本地派生算法,无新签名/迁移。把 LowStock 从「最近买过」升级为前瞻性 agentic 雏形。

#### #9 步骤内时间词自动识别为可启动计时器 + 常驻 HUD  ·  价值高 / 成本中

Cook Mode 注释明确 Timers out of scope,全库无烹饪计时。用确定性正则从中文步骤(「煮10分钟」「静置1小时」)解析出时间,一键启动倒计时,常驻 SwiftUI overlay HUD。

**竞品参照**:Crouton, Mela

**理由**:把 Cook Mode 从电子菜谱升级为烹饪助手的关键。中文时间表述正则起步即可,纯本地、无后端、契合本地优先偏好;基础计时不需要 Live Activity(那才是 high)。

#### #10 Cook Mode 步骤内食材词级内联标注(随缩放更新该步用量)  ·  价值高 / 成本中

已有「食材速查」整张配料表浮层,但不是步骤文本里食材词可点/用量内联到每一步。做步骤文本↔食材名的词级匹配并内联渲染缩放后用量。

**竞品参照**:Crouton, Deglaze

**理由**:数据已具备(RecipeIngredient 含结构化 quantity/unit、步骤是纯文本),消除「这一步到底放多少」的翻找。属中等成本体验升级而非全新能力,可借已有 PinyinMatcher/归一基础设施做词级匹配。

#### #11 二十四节气/时令食材驱动的内容推荐卡  ·  价值中 / 成本中

全库无节气/应季/seasonal 实现。做一张节气→应季食材→关联菜谱的本地映射表,在 Dashboard 加「时令推荐」卡。

**竞品参照**:下厨房, 美食杰, 豆果美食

**理由**:节气是中国用户独有、自带文化认同的内容节奏器,提供「无需主动搜索就有理由推送今天吃什么」的天然触发点,提升打开频次。纯本地映射表无后端,高性价比本土化差异点。

#### #12 膳食计划支持「便签条目」+ 餐别分槽 + 剩菜排期(leftover)  ·  价值中 / 成本中

MealPlanEntry 强制要 recipeId+recipeName,无法加「周三吃泡面/外卖」便签,无早午晚槽位,也不能把同一道菜以剩菜形式排到后续几天。给 entry 加可空 recipeId+自由文本标题+可空 mealType+isLeftover 标记。

**竞品参照**:AnyList, Plan to Eat, Paprika, Mealime

**理由**:膳食+剩菜入库两块拼图已在,缺的是把它们缝成减废闭环。需 schema+sync 列扩展(故 medium),但剩菜排期不进购物清单、只提醒吃掉,直接服务减废主线;便签让用户不必为「吃泡面」也建菜谱。

#### #13 App 内语音口述录入(SFSpeech 听写 → 复用 AI 文本解析)  ·  价值中 / 成本中

全库无 SFSpeechRecognizer。Siri Intent 已覆盖「不开 App 加购」,但 App 内无按住说话录入。补语音转写→喂入现有 AiIngredientParser.fromText/缺料解析→进 review。

**竞品参照**:OurGroceries, KitchenPal, Grocery AI, SmartThings

**理由**:厨房「手脏两手忙」是真实场景,语音摩擦最低。下游文本解析链路已现成,只需前接转写;需 NSMicrophoneUsageDescription/NSSpeechRecognitionUsageDescription(Info.plist 改动,无签名/entitlement 风险)。

#### #14 可复用的整周膳食计划模板(存为模板/一键铺到日历)  ·  价值中 / 成本中

代码无 template/saved menu 概念,MealPlan 仅按天逐条 entry。新建「模板」本地实体(一组 recipeId+相对天偏移),「存为模板」序列化当前周,「应用模板」按选定周起点批量 addDish。

**竞品参照**:Paprika, Prepear, Plan to Eat

**理由**:降低每周从零排餐负担、提升周复访。纯本地即可起步(无需 sync),复用已有 addDish。订阅他人计划是后续内容化方向,本轮不做。

#### #15 减废成效游戏化:成就/徽章/连续打卡 streak + 多去向口径(捐了/堆肥)  ·  价值中 / 成本中

减废统计扎实但无激励层(无积分/连胜/徽章),FoodLogOutcome 只有 consumed/wasted。加成就规则引擎+成就页+各动作埋点(streak),并给 outcome 加 donated/composted 两个正向去向。

**竞品参照**:Kitche 铜银金勺, Too Good To Go, Olio

**理由**:减废是长期低频行为,过程奖励+streak 是被验证的留存杠杆。纯本地(状态用 SwiftData/UserDefaults,无后端);去向枚举仍是 string、统计层加性扩展、不动同步 schema。

#### #16 AI 步骤原子化拆分(导入侧 prompt 强化 + 对已存菜谱「AI 整理步骤」)  ·  价值中 / 成本低

导入侧 OCR 路径已有弱版「合理拆分步骤」,但 URL 路径与 364 条目录无专门的「一大段塞一步→拆成单一动作短句」处理,也无运行时按钮重排步骤。在导入 prompt 强化原子化拆步,或加对已存菜谱的「AI 整理步骤」动作。

**竞品参照**:Crouton AI 食谱简化拆步

**理由**:社媒/网页导入步骤质量参差,一大段塞一步直接拖累 Cook Mode 一步一屏。与 recipe-pipeline 清洗理念一脉相承,改 prompt+复用现有 AI 链即可。

#### #17 缩放结果显示为干净分数(½ 杯/¼ 茶匙)  ·  价值中 / 成本低

缩放结果经 QuantityText.formatQuantity 渲染为小数(0.5、1.2),不是漂亮分数。给 QuantityText 增加分数格式化分支。

**竞品参照**:Deglaze, Paprika, Crouton

**理由**:数字化 quantity schema 天然适配,纯展示层加分支即可,低成本提升专业感。中文厨房多用克/毫升,公制/英制换算价值有限故不优先;按单个食材缩放可作后续 medium 项。

#### #18 购物清单货架动线可由用户拖拽自定义排序  ·  价值中 / 成本中

已按 FoodCategories.values 固定 5 类品类排序,但顺序写死、用户无法拖拽匹配自家超市走道。新增本地持久化(可随家庭同步)的品类顺序数组,categoryRank 改读它,加可拖拽设置页。

**竞品参照**:Listonic, Bring!, OurGroceries, Out of Milk

**理由**:品类分桶骨架已在,差的是「用户可编辑排序」这一层。低成本、高感知、被竞品反复夸的体验点;多门店多套动线可作后续增量。

---

## 三、速赢项(低成本可快落地)

- 份量缩放贯穿到加购缺料路径(携带缩放后 quantity/unit,顺带激活跨菜谱合并)
- 扫码即出 Nutri-Score/NOVA/Green-Score 徽章(OFF fields 加字段,零额外请求)
- 菜谱「能消耗 N 个临期」量化排序维度 + 徽章
- AI 步骤原子化拆分(导入 prompt 强化 + 对已存菜谱整理步骤)
- 缩放结果显示为干净分数(½/¼)
- 临期看板每条食材旁加「→做这道菜」逐项直达入口

## 四、战略项(需你拍板:签名 / entitlement / 数据库迁移 / 食品安全)

- 价格列价值链(Ingredient+ShoppingItem+FoodLogEntry 加 price/cost:SwiftData 迁移+Supabase 列+同步 codec):一处投入解锁 购物预算累计/减废金额化「扔了多少钱」/个人 Impact 仪表盘 — 需用户拍板,MEMORY 已列为 A 类
- 小票 OCR 反转过滤抓结构化价格并入库(依赖 price 列;OCR 价格行↔商品行配对易错,小票版式多变)
- 个人 Impact 仪表盘(省下金额+CO2e+水耗;CO2e/水耗用静态系数可先做不依赖 price 的子集,金额维度依赖 price 列)
- Best-By vs Use-By 双类保质期建模 + 看-闻-尝分级提醒(全栈大改:Domain 多模型加字段+Codable 兼容+SwiftData 列+Supabase 迁移+ExpiryCalculator/通知四态全改+AI/OCR 双日期解析 — 食品安全相关,需独立 milestone 拍板)
- WidgetKit 临期 Top3/购物速览小组件 + Live Activity 烹饪计时(需新 Widget/ActivityKit Extension target、App Group 共享数据、独立签名/profile — 签名敏感,需拍板)
- 家庭成员变更远程推送 APNS(需 push entitlement+推送证书/签名+Supabase Edge Function 触发 APNS — 全链路重,签名敏感)
- Apple Watch App(quick-add/勾选,厨房超市刚需;需新 watchOS target+独立签名/entitlement+对接现有同步管线)
- 目标驱动自动配菜引擎(设卡路里/宏量目标→自动凑整周菜单;硬约束=364 条菜谱目录缺逐菜营养数据,需先走 recipe-pipeline/OFF/AI 补营养 — 是否进营养向赛道需拍板)

## 五、已领先 / 已对齐竞品的能力(差异化护城河)

- 整柜/冰箱/购物袋拍照 AI 多物识别 + 勾选确认入库(AiIngredientParser.fromImage→IntakeReview,复用文本入库同一 draft→proposal→review 机器):竞品 FridgeSmart/NoWaste.ai/Samsung Food/ChefGPT 的核心卖点本 App 已端到端
- 小票 OCR 批量入库 + 按类型智能估到期日 + 生产日期反推到期日 + 条码学习/防重复合并:对齐甚至强于 NoWaste.ai/Kitche
- 做完菜半自动回扣库存(配方↔库存闭环,确认式避免误扣/双扣)+ 部分消耗 + 剩菜入库:对齐 Remy 且更稳健
- 生成购物清单时自动按库存扣除「已在库」只买缺口(菜谱缺料加购+整周膳食缺料聚合,pantry-aware):竞品 Paprika/FoodiePrep/Mealime 主打,本 App 两处都已默认
- 库存反向驱动菜谱排序(现有/用临期两 tab 按命中度+临期权重 + AI 清冰箱生成):对齐 Samsung Food「Search with Your Food List」/Remy use-first
- 临期清仓闭环(临期看板→用临期食谱排序→AI 清冰箱→减废统计行动卡直达):对齐 Kitche/Too Good To Go 临期闭环
- 离线优先可靠同步 + 防丢数据/防重复购买(outbox+3-way merge+乐观并发+Realtime+防跨家庭泄漏,单行原语无闪空回滚):质量高于多数竞品,正是 Listonic「更新后清单消失」等翻车重灾区
- 家庭共享同一份库存/购物清单(创建/邀请链接+二维码+深链/成员管理/全量双向同步/food_log 家庭同步):深度超过收起来/电子菜单/Bring
- 强菜谱抓取器多入口(URL 粘贴+剪贴板检测+Share Extension+照片 OCR 导入,与 mapToDraft 共享 schema):对齐 Plan to Eat Recipe Clipper/Paprika
- 商业克制(完全免费/无广告/无订阅/无内购 + 持续做减法 + 可靠同步):正好命中竞品最大负面情绪(广告/强制订阅/臃肿),应显性化为产品承诺
- 拼音搜索 + 全局搜索(库存+食谱)+ 收藏 + 忌口饮食偏好过滤 + 份量缩放 ½/1/2/3× + Cook Mode 防熄屏 + Siri/App Intents/Spotlight 系统集成:中文本土化与基础体验已齐
- 食材用量无损数字化 schema(quantity/quantityMax/unit/note,364 条已数字化)+ OFF 营养解析消费侧已做透:领先于多数仅文本用量的竞品,且是上层减废扣减准确性/营养/价格链的基础设施

---

## 六、分品类差距分析

### 库存/食材管理（Pantry / Food Inventory Management）

| 功能 | 状态 | 价值 | 成本 | 现状/说明 |
|------|:----:|:----:|:----:|-----------|
| Best By / Use By 双类保质期建模 + 分级到期提醒 | 缺失 | 高 | 高 | Domain 全链路只有单一 shelfLifeDays(Ingredient/IngredientDraft/FrequentItem/FoodDetai… |
| 浪费换算成金钱/水/CO2/食物量的环保影响页 | 缺失 | 高 | 高 | 已有减废统计屏(用掉率/分类下钻/时间窗)+ Dashboard 减废卡 + 删除追问吃完/扔了(FoodLog)。但全部是『件数/比率』口径(grep W… |
| 一次扫码多语义:入库/消耗/移库/加购物清单 | 缺失 | 中 | 中 | 当前 BarcodeScannerView/BarcodeScanResolution 只服务『扫码→查 OpenFoodFacts→入库』单一动作(代码中… |
| 收据拍照 AI 一次性解析全部商品(名称+数量+价格) | 部分 | 高 | 中 | 小票 OCR 批量入库已实现:ReceiptImportView 用离线 Vision(TextRecognizer.recognizeReceiptTex… |
| 菜谱按『能消耗多少临期/过期品』排序推荐 | 部分 | 高 | 低 | 已有『临期食谱排序看板』(Recipes 的 use-expiring tab)+ RecipeMatching 规则,菜谱按库存匹配度/临期优先排序。但目… |
| 部分消耗 / 部分单位库存 + 入冷冻自动延展保质期 | 部分 | 中 | 中 | 部分消耗已完整实现:IngredientDetailView 的『用了一部分』sheet(planPartialConsume/consumePartial… |
| 语音输入作为一等录入方式(可接 Siri Shortcuts) | 部分 | 中 | 中 | 已有 Siri/App Intents(AddToShoppingListIntent『加到购物清单』name 参数 + CheckExpiring),可通… |
| 未知商品先拍照占位、细节稍后补全的渐进式录入 | 部分 | 中 | 中 | IntakeReviewView 已支持入库前编辑/延后补全字段(名称/数量/类别等可改、可不选),AddIngredientView 也支持渐进填写。但没… |
| 购物清单按超市货架分区自动排序 | 部分 | 中 | 低 | 购物清单已按品类分区排序(ShoppingStore.displaySections + categoryRank,unchecked 在前)。但排序键是 … |
| 最低库存阈值 → 自动补货建议 / 自动加购物清单 | 部分 | 中 | 中 | 已有低库存补货能力:LowStockStore 从加购历史(FrequentItem)挑出『买过 ≥3 次且当前不在库存』的常买品,Dashboard 卡片… |
| 自定义存放位置 + 按位置的库存清单视图 | 部分 | 低 | 中 | 按存储位置筛选库存已实现,但位置是固定三值枚举 IconType(fridge/freezer/pantry,fromName 任何未知值都回落 fridg… |
| 整柜/整冰箱拍照 AI 多物识别 + 用户勾选确认 | 已有 | 高 | 低 | 已实现端到端:ImageImportView 走 AiIngredientParser.fromImage 把一张照片解析成多条 IngredientDra… |

### 智能购物清单 (Smart Grocery / Shopping List)

| 功能 | 状态 | 价值 | 成本 | 现状/说明 |
|------|:----:|:----:|:----:|-----------|
| 带价格的清单 + 自动累计总价 + 预算对照 | 缺失 | 高 | 高 | 全代码库零 price/cost 字段(ShoppingItem/Ingredient 模型均无价格列)。这正是 MEMORY 里反复出现的 A 类待办『浪… |
| 实时协作的『人性化』层:活动流 + emoji 反应 + 谁加了什么 | 缺失 | 中 | 高 | ShoppingItem(及其它同步模型)无 addedBy/checkedBy/memberName 等署名字段,也没有任何 activity feed … |
| 菜谱『做过次数 / 上次做的日期』与多维排序 | 缺失 | 中 | 中 | 全代码库无 cookCount/lastCooked/timesCooked 等字段(已 grep 确认)。菜谱当前支持收藏 + 分类/tag/时长/忌口筛… |
| 促销传单/优惠券聚合 + 清单项内嵌价格与到期日 | 缺失 | 低 | 高 | 无任何促销/优惠券/传单聚合能力,清单项也不内嵌价格或有效期。调研已明确判断:促销数据在中国市场无现成传单 API,不建议照搬 Flipp 的传单聚合(故价… |
| AI 预测式补货 / 周期性复购建议 | 部分 | 高 | 中 | 已有『库存不足/常买补货』(LowStockStore):从 add-history 频次记忆里挑『买过 ≥3 次且当前不在库』的名字,按购买次数降序,一键… |
| 按本人所在超市自定义的货架动线排序 | 部分 | 中 | 中 | 购物清单已有品类分组 + 固定『品类货架动线』排序:ShoppingStore.displaySections 按 FoodCategories.value… |
| 图标化/可视化的加项体验 | 部分 | 中 | 中 | 已有可视化基础:每个品类有专属配色 + SF Symbol 图标(FkCategoryPalette/FkCategoryIcon),RecipeCard/… |
| 语音助手集成 + 拍照识物加项 | 部分 | 中 | 中 | ① 拍照识物加库存已完整实现:AiIngredientParser.fromImage 用 vision LLM 识别『货架/冰箱/购物车照片』→ Ingr… |
| 膳食计划里的『便签条目』与剩菜复用 | 部分 | 中 | 中 | 剩菜复用已部分实现:Cook Mode 完成自动扣减,剩菜可入库(LeftoverIntakeSheet)。但膳食计划侧 MealPlanEntry 模型强… |
| 全平台同步 + 一次性买断的商业克制 | 部分 | 中 | 高 | 商业克制天然达成:本 App 完全免费、无广告、无订阅、无内购,功能克制(MEMORY 多次主动删死代码/做减法),离线优先同步可靠——正好命中竞品最大负面… |
| 网页/视频菜谱一键导入 + AI 拍照解析食谱 | 已有 | 高 | 低 | 已全链路实现:① 网页 URL 导入走 AiRecipeParser.fromURL(apps/ios/.../Services/AiRecipeParse… |
| 可靠的离线优先同步与『防重复购买』保证 | 已有 | 高 | 低 | 本 App 的强项:离线优先 outbox + 3-way merge(remote-wins 保留 local-only 行)+ 乐观并发推送(版本冲突自… |

### 膳食计划 (Meal Planning)

| 功能 | 状态 | 价值 | 成本 | 现状/说明 |
|------|:----:|:----:|:----:|-----------|
| 目标驱动的自动配菜引擎(卡路里/宏量约束求解) | 缺失 | 中 | 高 | 已有营养展示(NutritionCard + Open Food Facts nutriments 解析,FoodDetails)但纯属库存物品的营养卡,菜… |
| AI 改写既有菜谱以适配在库食材/饮食限制 (Personalize Recipe) | 缺失 | 中 | 中 | 已有 AI 菜谱解析(URL/照片/文本→结构化 RecipeDraft)与 AI 清冰箱『生成新菜』(AiRecipeGenerator),以及忌口/饮食… |
| 可复用的膳食计划模板 / 整周菜单 (Saved Menus) | 缺失 | 中 | 中 | 代码中无任何 template/模板/saved menu 概念,MealPlan 仅按天逐条 entry,无法把排好的一整周存成可复用模板一键铺到日历。 |
| 购物清单一键导出到生鲜配送购物车 (Instacart/Walmart/Kroger) | 缺失 | 低 | 中 | 无生鲜配送集成,也无『导出/分享购物清单为可下单格式』。购物清单仅本地+家庭同步。 |
| 拍照识别食材入库 + 拍小票/拍冰箱生成计划 | 部分 | 高 | 中 | 已有:小票 OCR 批量入库(TextRecognizer+ReceiptTextCleaner+AI 解析)、包装到期日 OCR(ExpiryDatePa… |
| 份量缩放贯穿『菜谱→计划→购物清单』全链路 | 部分 | 高 | 低 | 菜谱详情份量缩放已实现且传导到部分链路:scaleFactor 缩放食材用量(scaledIngredients/RecipeIngredient.scal… |
| 拖拽式周/月膳食日历(早午晚加餐分槽) | 部分 | 中 | 中 | 已有 Mon→Sun 周历(WeekStrip+DayCell,带每日有菜小圆点)、上/下周导航、回到今天、按日选中查看当天菜品(MealPlanView.… |
| 购物清单跨菜谱同名食材合并 + 单位换算 | 部分 | 中 | 中 | ShoppingStore 已有同名聚合(performAdd→mergeQuantity:同名且单位余项一致时数字相加,QuantityText.form… |
| 『按剩菜规划 / 煮一次吃两顿』排餐 (Plan as Leftover) | 部分 | 中 | 中 | 已有『剩菜入库』:做菜扣减后弹「存为剩菜?」把成品按份数+保质期存进库存(LeftoverDraft/LeftoverIntakeSheet,RecipeD… |
| 加入购物清单时自动扣除库存已有项 (pantry-aware shopping) | 已有 | 高 | 低 | RecipeDetailView 的「加购缺少的 N 件」只对 missingIngredients(= RecipeMatching.missingIng… |
| 库存反向作为菜谱搜索/推荐的排序信号 | 已有 | 高 | 低 | 已实现:RecipesStore 有『现有(available)』tab 按库存命中度排序(RecipeMatching.rankedByAvailabil… |
| 强菜谱抓取器:粘贴 URL 结构化导入食材+步骤 | 已有 | 中 | 低 | 已实现:CustomRecipeFormView 创建模式有『AI 导入』banner,可粘贴懒饭/下厨房链接→AiRecipeParser.fromUrl… |

### 食谱管理 (Recipe Management)

| 功能 | 状态 | 价值 | 成本 | 现状/说明 |
|------|:----:|:----:|:----:|-----------|
| 社媒视频 URL 导入食谱(YouTube/Instagram/TikTok/抖音/小红书) | 缺失 | 高 | 高 | 已有「URL 导入食谱」管线(AiRecipeParser.fromUrl + RecipePageFetcher),但 RecipePageFetcher… |
| 步骤内时间自动识别为可启动计时器 + 常驻 HUD | 缺失 | 高 | 中 | 完全没有计时器。CookModeView 第 42 行注释明确写「Timers / Live Activities / voice are explicit… |
| 多食谱并行 Cook Mode(一桌多菜统筹) | 缺失 | 低 | 高 | CookModeView 是单食谱全屏步骤分页器(let steps: [String] 单一来源),无法同时加载多个食谱并切换,也无跨食谱计时统筹(本就无… |
| Cook Mode 步骤内点击食材即显用量 / 行内食材标注(随缩放更新) | 部分 | 高 | 中 | CookModeView 已有「食材速查」sheet:在烹饪模式里点顶部「食材」按钮弹出全部食材+缩放后用量(scaledIngredients 单一缩放源… |
| AI 按饮食限制/忌口改写已有食谱(转素食/低盐/替换过敏原) | 部分 | 高 | 中 | 已有「忌口/饮食偏好」但仅用于过滤:DietaryPreferencesStore 提供 keywords,RecipesStore 第 256 行 fil… |
| 冰箱/储藏室拍照 → AI 识别食材 → 反推可做菜谱 | 部分 | 高 | 中 | 构成要素都有但未串成单步闭环:① AiIngredientParser.fromImage(第 42 行注释明确「groceries / a fridge」… |
| 缩放显示为干净分数(½ 杯/¼ 茶匙)+ 双维度缩放(按份数/按单个食材)+ 公制/英制单位换算 | 部分 | 中 | 中 | 已有份量缩放(RecipeDetailView 备料 ½×/1×/2×/3× chips,scaledBy 缩放 quantity/quantityMax,… |
| 购物清单智能合并去重(非精确:切碎洋葱+整颗洋葱=3 颗)+ 按门店货架动线排序 | 部分 | 中 | 中 | 已有「同名自动聚合」:ShoppingStore.mergeQuantity 对「大小写不敏感的同名」行做数量合并(同单位时数值相加),ShoppingIt… |
| AI 食谱步骤简化(长步骤拆成原子小步) | 部分 | 中 | 低 | 导入侧已有「合理拆分步骤」的弱版:AiRecipeParser.fromTextSystemPrompt(OCR 路径)指示模型「合理拆分食材与步骤」。但 … |
| 单张照片 / OCR 实体菜谱书 AI 导入 | 已有 | 高 | 低 | 已完整实现。RecipePhotoImportView + AiRecipeParser.fromText(OCR 文本路径,系统提示词专门处理「错别字、断… |
| Pantry 感知:购物时标记「你已经有了」/ 生成清单时自动剔除在库 | 已有 | 高 | 低 | 已实现。食谱详情「加购缺少的 N 件」(RecipeDetailView.missingIngredients 用 RecipeMatching.missi… |
| 膳食计划自动汇总食材 → 整理为分类购物清单(并扣减库存) | 已有 | 高 | 低 | 已端到端打通。MealPlanView「缺料」卡:MealPlanMissing 聚合可见周内所有未做计划菜的食材、跳过库存已有项、按 addMissing… |

### 减废 / 临期 / 捐赠 (Food-waste reduction, near-expiry rescue & community donation)

| 功能 | 状态 | 价值 | 成本 | 现状/说明 |
|------|:----:|:----:|:----:|-----------|
| 浪费/省下金额化（按购买价或类目均价计入本周/本月浪费金额） | 缺失 | 高 | 高 | FoodLogEntry 只记 count(consumed/wasted/rescued),明确注释「Quantity is intentionally … |
| 保质期素养：区分赏味期(best-before)vs 食用期(use-by)+ 看-闻-尝提示 | 缺失 | 高 | 高 | Ingredient 模型只有单一的 expiryDate/shelfLifeDays/expiryLabel(Domain/Models/Ingredie… |
| 与全国/同类家庭平均对比的浪费基准线 + 自定义 missions/challenges | 缺失 | 中 | 中 | 减废统计屏只有用户自己的件数/用掉率,没有任何外部基准线对比,也没有用户可自建的减废目标/挑战。 |
| 记录动作即奖励的成就体系（铜/银/金勺、徽章、连续打卡 streak） | 缺失 | 中 | 中 | 全 App 没有任何 gamification:无 streak、无成就/徽章、无勺子等级。代码里 badge 字样全是同步角标/通知角标(待同步、pend… |
| 邻里 C2C 免费共享/赠送临期食物（含信任分门槛与就近匹配） | 缺失 | 中 | 高 | 完全没有。本 App 的『共享』仅指家庭内 Supabase 双向同步(household 成员共享同一份库存),没有面向陌生邻里的 C2C 食物赠送、LB… |
| 捐赠流：挂出食物时指定慈善机构做 pay-as-you-feel 捐赠 | 缺失 | 低 | 中 | 没有捐赠概念。FoodLogOutcome 枚举无 donated 去向,也无任何慈善机构对接。 |
| 临期�I漏地图：一屏对比多店折扣/盲盒（卡片式横竖滚动）+ 盲盒化清仓 | 缺失 | 低 | 高 | 完全没有商家侧能力。本 App 是纯家庭库存工具,无商家临期专区、无地图、无盲盒下单。 |
| 删除/丢弃时追问去向（吃完/做菜消耗/扔了/捐了/堆肥） | 部分 | 中 | 低 | 已实现「删除时追问吃完/扔了」二元去向(InventoryStore 删除流弹层 + 做菜自动扣减记 consumed),写入 FoodLogEntry 供… |
| 个人 Impact 仪表盘：省下金额 + CO2e + 水耗（固定换算系数累计） | 部分 | 中 | 高 | 已有减废统计屏(用掉率 headline + 用掉/浪费/抢救临期三个件数 metric tile + 分类去向 Swift Charts + 最常浪费排行… |
| 正向口径：按时吃掉『省下/救下』而非只统计损失 + 临期不催扔的情绪重构 | 部分 | 中 | 低 | 已有正向元素:减废统计有『用掉率%』headline、『抢救临期』件数 metric tile + 详细记录里的『抢救临期』标签 + Dashboard『r… |
| AI 小票拍照批量入库 + 按食材类型自动估算到期日 | 已有 | 高 | 低 | 已完整实现:小票拍照走离线 Vision OCR + 噪声过滤 + AI 解析成食材清单批量入库(ReceiptOCR/AI Ingredient Pars… |
| 临期清仓闭环：临期提醒 → 一键用临期食材搜菜谱 | 已有 | 中 | 低 | 已实现完整闭环:临期看板(ExpiringView)+ 临期食谱排序看板(按库存匹配/临期优先排序的『用掉临期』菜谱 tab)+ AI 清冰箱食谱生成;减废… |

### 营养与健康（Nutrition & Health）

| 功能 | 状态 | 价值 | 成本 | 现状/说明 |
|------|:----:|:----:|:----:|-----------|
| 差评商品的'更健康替代品'推荐 | 缺失 | 中 | 高 | 无。扫码/OFF 查询已有，但没有'扫到差评商品时推荐同类更优替代'的机制；购物清单加购时也无健康提示。 |
| 正向营养追踪（蔬果鱼多样性而非只盯热量限制） | 缺失 | 中 | 中 | 无。减废统计是'用掉/扔掉'维度，忌口/饮食偏好是负向过滤（排除关键字），没有'本周吃了几种蔬菜/膳食多样性'这类正向鼓励指标。 |
| 环境影响评分（Green-Score / Eco-Score）+ 减废=减碳 | 缺失 | 中 | 中 | 无。减废看板（WasteInsightsStore）统计 consumed/wasted/rescued/用掉率/分类，但没有任何环境/碳足迹维度；扔掉的食… |
| 权威背书：营养师审核内容徽章（Blue Check） | 缺失 | 低 | 低 | 无。364 条菜谱来自采集管线（howtocook/全网补图/AI 清洗），没有'专业审核'或'营养估算来源'标记，营养数据全部来自 OFF/AI。 |
| 扫条码即出健康评分（Nutri-Score / NOVA / Yuka 式 0-100） | 部分 | 高 | 中 | 已有完整的条码扫描（VisionKit DataScannerViewController）+ Open Food Facts 查询链路（OpenFoodF… |
| 多模态录入（拍照 / 语音 / 文本 / 扫码 四合一） | 部分 | 中 | 中 | 四种里已有三种且做得很扎实：文本（PasteImportView+AiIngredientParser）、拍照（ImageImportView 走 visi… |
| AI 拍照识别整盘并拆分多菜品 | 部分 | 中 | 中 | 已有拍照 AI 识别能力（AiIngredientParser.fromImage 识别冰箱/购物袋里的多个食材并拆成多条 IngredientDraft … |
| 添加剂/加工度透明化标注 + '为什么'说明 | 部分 | 中 | 中 | 营养仅 4 宏量，无添加剂列表、无加工度（NOVA）、无成分透明度维度。但 OFF 查询链路已在，additives_tags / nova_group /… |
| 日度/周度健康总分（Life Score 式聚合反馈） | 部分 | 中 | 中 | 已有减废看板（WasteInsightsStore）做'用掉率/分类消耗/rescued'的聚合统计，Dashboard 有减废卡。但没有把'库存结构/本周… |
| '先拍后录'：录入与整理动作解耦（snap-now-process-later） | 部分 | 中 | 中 | 已有拍照识别批量入库（ImageImportView/ReceiptImportView），但流程是同步的：选图 → 立即 AI 解析 → 立即进 Inta… |
| 膳食计划自动生成购物清单（扣除库存已有项） | 已有 | 高 | 低 | 已完整实现且做法正是竞品推崇的范式：MealPlanMissing.missingIngredientNames 对整周膳食计划聚合所需食材，并通过 Rec… |
| 免费开放数据库 + 众包补全（Open Food Facts 模式） | 已有 | 中 | 低 | 已深度接入 Open Food Facts：OpenFoodFactsService 做 barcode/name 双路查询、SearchALicious … |

### 中国本土厨房 App(食谱发现 / 库存 / 购物 / 膳食 / 减废)— 竞品 featureHighlight 逐项差距分析

| 功能 | 状态 | 价值 | 成本 | 现状/说明 |
|------|:----:|:----:|:----:|-----------|
| 二十四节气 / 时令食材驱动的内容更新与推荐 | 缺失 | 中 | 中 | 代码全量 grep 无任何节气/时令/应季/seasonal/solarTerm 相关实现。食谱推荐目前仅按库存匹配/临期优先排序,无任何季节维度。 |
| 做过标记(做过N次)+ 作品 UGC + 榜单社会证明 | 缺失 | 中 | 高 | FoodLogEntry 记录的是 consumed/wasted 食材出库,不挂 recipe,无 cookCount/做过次数;grep 无 cookC… |
| [平台能力补充] 家庭成员共享变更的远程推送(APNS) | 缺失 | 中 | 高 | 仅本地通知(临期/低库存),grep 无 APNS/remoteNotification/registerForRemote。家庭成员对共享库存/购物清单的… |
| [平台能力补充] WidgetKit 首页/锁屏小组件(临期/购物清单速览) | 缺失 | 中 | 高 | grep 无 WidgetKit。已知清单亦确认尚缺。临期食材、购物清单本是极适合 Widget 的『一眼速览』数据,目前只能进 App 查看。 |
| 菜谱 → 净菜 / 食材一键下单配送到家(或库存缺料深链跳转买菜平台补货) | 缺失 | 低 | 中 | grep 无任何净菜/买菜/叮咚/盒马/配送/电商/导购/深链跳转买菜相关代码。缺料目前只能加入 App 内购物清单,无法一键跳转外部买菜平台补货。 |
| 拍冰箱 / 选库存食材反向推荐「能做什么菜」(多模态识别冰箱内景列出可做菜并标缺料) | 部分 | 高 | 中 | 反向闭环的核心已具备:RecipesStore 的「现有」tab 按库存匹配排序列出可(部分)做的菜,RecipeDetailView 算「有 m/总」并高… |
| 食材用量精确量化 + 每步标注耗时与防错提示 | 部分 | 中 | 中 | 食材用量已完全量化:Recipe.Ingredient 是无损数字模型(quantity/quantityMax/unit/note),displayAmo… |
| 1分钟短视频菜谱(核心步骤)+ 图文并存 | 部分 | 中 | 中 | 已有 videoUrl 字段 + RecipeDetailView「观看视频」按钮,通过 SafariView(SFSafariViewController… |
| 保质期临期提醒 + 日历/时间轴双视图 + 低库存提醒 | 部分 | 中 | 中 | 临期提醒(每日 9:00、7/3/1 天分级、确定性 ID、勿扰时段、自定义时间、点击深链)与低库存补货(LowStockStore + 首页卡 + 一键批… |
| AI 营养师 / 健康目标驱动的每日三餐定制(设定减脂/增肌目标→定制三餐解锁健康菜谱) | 部分 | 中 | 高 | 基础原料已具备:NutritionFacts 已能从 Open Food Facts 解析并在详情页展示营养卡;膳食计划(每周日历)+ 忌口/饮食偏好过滤已… |
| 按食材 / 功效 / 体质等多维反向检索菜谱(极细分类、药膳食疗、按当季食材找菜) | 部分 | 中 | 中 | 『按已有食材反向找菜』维度已实现且是核心:RecipesStore「现有」tab 按库存匹配排序 + 「用临期」tab 按消耗临期排序,RecipeMatc… |
| 扫码 / 拍照 AI 识别快速录入食材(条码带名称分类、拍照批量识别、生产日期/批号反推到期日) | 已有 | 高 | 低 | 全链路已实现且超出多数竞品:BarcodeScannerView 用 VisionKit DataScannerViewController 实时扫码 + … |
| 菜谱食材一键汇入购物清单并跨菜谱去重合并(含整周计划聚合、勾掉已在库存项) | 已有 | 高 | 低 | RecipeDetailView 支持「缺料一键加购」且份量缩放会影响加购数量;ShoppingStore 实现同名自动聚合(quantity-merge)… |
| 家庭共享同一份库存 / 购物清单(多人实时协作、分储位) | 已有 | 高 | 低 | Household 全套已实现:创建家庭(自动收编本地 '' scope 数据)、邀请(链接+二维码+深链 freshpantry://invite/<to… |

### AI / 智能家居 / 创新 — 厨房库存·配方·膳食·减废类竞品差距分析

| 功能 | 状态 | 价值 | 成本 | 现状/说明 |
|------|:----:|:----:|:----:|-----------|
| WidgetKit/Live Activity 主动告警(把临期 Top3/今日该做的菜放锁屏/小组件) | 缺失 | 高 | 高 | 代码中无 WidgetKit / ActivityKit 任何实现(grep 零命中)。当前主动提醒仅本地通知(ExpiryScheduler 9:00 分… |
| 语音自由口述 → 结构化条目(购物/库存) | 缺失 | 中 | 中 | 代码中无 SFSpeechRecognizer / Speech / AVAudioEngine / dictation 任何语音输入实现。Siri 集成是… |
| 配方个性化改写(一份配方→N 种饮食版本，低卡/素食/无麸质) | 缺失 | 中 | 中 | 代码无 personalize/改写/低卡/无麸质/低钠 任何配方改写实现。已有忌口关键字过滤(DietaryPreferencesStore + Reci… |
| 对话式『用我现有食材能做什么』配方生成(带自由文本约束) | 部分 | 高 | 中 | 已有「AI 清冰箱食谱」(AiRecipeGenerator.fromIngredients):从(临期)库存食材名生成一道家常菜，复用 RecipePar… |
| 整周膳食计划自动排盘(给目标→出整周，而非手动拖拽) | 部分 | 高 | 高 | 已有每周膳食日历(MealPlanView/MealPlanStore):手动加菜到未来 7 天、移到其他日期、整周缺料聚合加购、家庭同步。但全是『手动逐餐… |
| AI 小票 OCR 批量解析中的『价格提取 + 自动归类』 | 部分 | 高 | 高 | 小票 OCR 已实现(TextRecognizer 设备端 Vision + ReceiptTextCleaner 噪声过滤 + AI 解析品名),但 Re… |
| 全网/社媒配方导入并解析为结构化分步(含视频) | 部分 | 高 | 中 | 已有 URL 导入(RecipePageFetcher + AiRecipeParser)+ 拍照导入 + Share Extension + B站视频外链… |
| 对着冰箱实时拍照(相机直拍)整柜识别 | 部分 | 中 | 低 | 图片识别入口当前用 PhotosPicker(从相册选图)。实时相机已有 DataScannerViewController(条码扫描)与小票拍照,但 AI… |
| 主动式补货建议 / 预测性补给(消耗周期模型，agentic 雏形) | 部分 | 中 | 中 | 已有 LowStock(库存不足/常买补货):基于 add-history 频率，保留『购买≥3 次且当前不在库』的名单+一键批量加购物清单(LowStoc… |
| 减废成效游戏化 + 金额量化(积分/连胜/徽章/省了多少钱) | 部分 | 中 | 中 | 已有减废统计(WasteInsights:用掉率/分类柱状/最常浪费排名/Dashboard 减废卡『已挽救 N』徽章/删除追问吃完/扔了写 FoodLog… |
| 拍照/视觉批量识别食材，一键灌入库存 | 已有 | 高 | 低 | 已实现且已接入 UI。AiIngredientParser.fromImage(_:chatFn:) 用 vision 系统提示「识别图中所有可入库的食材」… |
| 临期优先作为推荐/排序的一等输入(use-first) | 已有 | 高 | 低 | 已实现。ExpiringView 临期看板按 7/3/1 天分层；RecipeMatching 排序把临期食材作为权重输入(RecipeCard 有「临期·… |
| 做完菜自动回扣库存(配方↔库存闭环) | 已有 | 高 | 低 | 已实现且闭环。RecipeDetailView「做菜」CTA 或 Cook Mode『完成』后打开 DeductionReview:系统按配方食材匹配库存生… |

---

## 附录 A · 竞品调研明细(各品类值得借鉴的功能点)

### 库存/食材管理（Pantry / Food Inventory Management）

- **整柜/整冰箱拍照 AI 多物识别 + 用户勾选确认** `2024-2026新兴` — FridgeSmart, Fridge Scanner, Portions Master, Wonder Fridge, NoWaste.ai, SmartPantry
  - 拍一张冰箱或货架的照片,AI 一次性框出多件食材并分组,用户只需勾掉/确认要入库的项,而不是逐件手输。FridgeSmart、Fridge Scanner、Portions Master、Wonder Fridge 等 2024-2026 新入局者都以此为核心卖点。
  - *价值*:『手动录入太繁琐』是几乎所有 pantry app 用户流失的头号原因(评测与差评反复出现)。批量视觉识别把录入从『逐件几十秒』压成『拍照+确认几秒』,是当前品类最大的体验杠杆,也是本 app 已有食材库/多模态能力可复用的方向。
- **收据拍照 AI 一次性解析全部商品(名称+数量+价格)** `2024-2026新兴` — NoWaste.ai, Kitche, Wonder Fridge, PantryPlus, Portions Master
  - 拍超市小票,AI 识别整单商品、数量、单价并批量入库,无需逐项手填。NoWaste.ai、Kitche、Wonder Fridge、PantryPlus 都已落地。
  - *价值*:一次购物=一次性把十几件东西灌进库存,是录入效率的最大单点。还顺带拿到价格数据,可支撑后续『浪费金额』『预算』等高价值统计。本 app 已有小票 OCR 基础,升级为结构化全单解析价值高。
- **一次扫码多语义:入库/消耗/移库/加购物清单** `小众` — Grocy
  - Grocy 的 Quick Scan 模式:同一个扫码动作,先选当前模式(收货入库 / 记录消耗出库 / 在存放位置间移动 / 加入购物清单),再连续扫码批量执行。
  - *价值*:把『扫码』从单一录入动作升级成贯穿食材全生命周期的统一交互,极大降低消耗/移库/补货的操作成本。对追求高频精确记账的重度用户是留存利器,且实现成本不高(复用已有扫码器+模式切换)。
- **Best By / Use By 双类保质期建模 + 分级到期提醒** `成熟标配` — Cozzo, Grocy
  - Cozzo 区分『最佳食用期』与『食用截止期』两类日期,并按 今天到期 / 即将到期 / 已过期 / 需补货 四种状态分桶每日推送,帮用户判断是『还能吃』还是『必须扔』。
  - *价值*:真实食安里『最佳赏味』和『安全截止』是两回事,一刀切一个日期会误导用户提前扔(增加浪费)或过期还吃(食安风险)。双类建模既减废又更安全,是差异化且贴近真实厨房场景的功能(本 app MEMORY 中也被列为待拍板的 A 类高价值项)。
- **菜谱按『能消耗多少临期/过期品』排序推荐** `成熟标配` — Cozzo, Grocy
  - Cozzo 的『用掉临期食材』看板和 Grocy 的 Due Score:从用户自己的菜谱库里挑出能用掉临期库存的菜,并按一道菜能消耗的临期品数量降序排列,优先推最能减废的菜。
  - *价值*:把减废目标直接量化进菜谱推荐排序,而不是泛泛地『看你有什么推菜』。这让『先吃临期』从一句口号变成可执行的当日菜单,是库存数据 × 菜谱数据结合后才能产生的护城河功能。本 app 已有菜谱库+临期看板,做这个排序是天然延伸。
- **部分消耗 / 部分单位库存 + 入冷冻自动延展保质期** `小众` — Grocy
  - Grocy 支持消耗半颗生菜、记录剩余量;把食材移入冷冻时自动按设定赋予新的最佳食用期(default best before days after freezing)。
  - *价值*:真实做饭很少整件用完,『用了一部分』和『冻起来就能多放很久』是高频场景。精确的部分量记账让库存数字可信(否则用户因数字不准而弃用),冷冻延期则避免冷冻食材被误判过期。本 app 已实现部分消耗,冷冻自动延期是顺手的高性价比补充。
- **语音输入作为一等录入方式(可接 Siri Shortcuts)** `成熟标配` — KitchenPal, Kitche, Pantrify
  - KitchenPal、Kitche、Pantrify 都把语音录入与扫码/拍照/手输并列,做饭手脏或两手占用时直接说出要加/要扣的食材。
  - *价值*:厨房是典型的『手脏、两手忙』场景,语音是除视觉识别外摩擦最低的录入通道。配合 iOS 的 Siri Shortcuts/App Intents 还能做到不打开 app 就记账,契合本 app 已有的 Siri/Spotlight 集成基础。
- **自定义存放位置 + 按位置的库存清单视图** `成熟标配` — Pantry Check, Grocy, NoWaste
  - Pantry Check 支持任意命名位置(冰箱/冷冻/车库冷柜…),Grocy 提供 Location Content Sheet 按位置列出每个地方存了什么,NoWaste 三大区域分仓并可按位置筛选排序。
  - *价值*:多冰箱/多冷柜/储藏间的家庭很常见,『东西在哪』和『有没有』同样重要。自定义位置 + 按位置浏览既方便实物核对(去地下室拿之前先看清单),也是『移库』动作的前提。是成熟但必备的组织维度。
- **未知商品先拍照占位、细节稍后补全的渐进式录入** `小众` — Pantry Check
  - Pantry Check:扫码识别不到的商品,允许先拍张照片占位入库,名称/数量/到期日等细节稍后再补。
  - *价值*:扫码库总有盖不到的本地/散装/自制商品,若此时强制填全字段,用户当场就放弃了。先占位后补全把『录入完整性』和『录入即时性』解耦,显著降低中断率——把扫码失败从死路变成可继续的小机制。
- **浪费换算成金钱/水/CO2/食物量的环保影响页** `成熟标配` — Kitche, NoWaste
  - Kitche 的 Impact 页把记录的浪费换算成省下的水、碳排、金钱、食物量;NoWaste 直接把『家庭浪费率%』做成核心炫耀指标。
  - *价值*:减废 app 的长期留存靠『看到自己在变好』。把抽象的『少扔了几样』换算成金钱和环保影响,既给情感正反馈又契合可持续叙事,转化率与口碑传播都更强。需要价格数据支撑(因此与收据价格解析联动)。本 app MEMORY 已把『浪费金额 price 列』列为待拍板项。
- **购物清单按超市货架分区自动排序** `成熟标配` — KitchenPal, Out of Milk
  - KitchenPal 等把购物清单按超市的货架分区(生鲜/乳制品/冷冻…)归类排序,逛店时按动线一路扫过去不回头。
  - *价值*:购物清单不只是 todo,按实体动线排序能实打实缩短购物时间、减少漏买。是把『库存缺口→购物清单』链路体验做到位的关键一环,实现成本低(给品类加 aisle 排序权重即可)。本 app 已有购物品类排序,可进一步贴合超市动线。
- **最低库存阈值 → 自动补货建议 / 自动加购物清单** `成熟标配` — Grocy, Cozzo, NoWaste
  - Grocy 跟踪每件商品的最低期望库存,跌破即提示补货并可自动进购物清单;Cozzo 把『需补货(re-stock)』作为独立提醒状态每日推送。
  - *价值*:把库存从『被动查询』升级为『主动提醒该买了』,让 app 在不打开时也持续产生价值(推送回流)。对米面油盐这类常备品尤其有用,是从『记录工具』迈向『家庭后勤助手』的关键能力。

### 智能购物清单 (Smart Grocery / Shopping List)

- **网页/视频菜谱一键导入 + AI 拍照解析食谱** `2024-2026新兴` — AnyList, Bring!
  - 通过 schema.org 微数据从菜谱网站/博客自动抽取食材、步骤、配图(AnyList/Bring 均有);进一步用多模态 AI(如 Gemini)把纸质食谱书或截图照片解析成结构化菜谱。导入后食材可一键加入购物清单。
  - *价值*:对厨房 App 是'菜谱→购物→库存→减废'闭环的关键入口。本项目已有 364 条菜谱库和视频外链,补一个'用户自带菜谱(网页/拍照/视频)AI 导入'能让用户把私房菜也纳入同一闭环,而非局限于内置库。
- **按本人所在超市自定义的货架动线排序** `成熟标配` — Listonic, Bring!, OurGroceries
  - 不只是固定分类,而是让用户拖拽调整分类顺序以匹配自己常去超市的实际走道动线,清单项据此自动重排,购物时一条路走到底不折返。Listonic/Bring/OurGroceries 均把它当核心卖点。
  - *价值*:本项目购物页已有'品类排序',但货架动线是更精细、更高频被夸的体验点。允许用户自定义动线顺序(甚至按门店保存多套)能显著提升到店购物效率,是低成本高感知的改进。
- **AI 预测式补货 / 周期性复购建议** `2024-2026新兴` — Listonic, Grocery AI / Replenish (新兴竞品)
  - 学习历史购买的商品、数量、重量与复购周期,主动建议'该补了'。Listonic 已识别周期性复购并按你常买的量建议;行业层面 2025 年 32.6% 美国食品消费者愿意让 AI 自动补货常备品(eMarketer/Amazon Ads)。
  - *价值*:本项目有库存 + food_log 消耗数据,具备做'预测式补货'的天然数据基础(知道什么被吃完、消耗多快)。把'临期+消耗速度'推成'建议补货'清单,是竞品大多还做不到、但本项目数据已就绪的差异化点。
- **带价格的清单 + 自动累计总价 + 预算对照** `成熟标配` — Listonic, AnyList
  - 每个清单项可填价格,App 实时累计本次购物预估总花费,并可对照固定预算。Listonic 用'写价格能省钱'作为核心省钱叙事;Bring 因为'无价格/无预算/无统计'被用户明确吐槽为短板。
  - *价值*:这正好补本项目 MEMORY 里反复出现的'浪费金额 price 列'A 类待办。一个 price 字段同时解锁:购物预算预估、减废看板的'扔掉值多少钱'、消费统计——一处投入三处复用,且是用户对纯免费 App(Bring)最大的抱怨点。
- **实时协作的'人性化'层:活动流 + emoji 反应 + 谁加了什么** `2024-2026新兴` — Bring!
  - Bring! 的 Activities(2025-02):列表变更历史、对变更用 emoji 反应、给成员发快捷消息;配合实时同步与变更通知,把共享清单变成轻量'家庭群聊'。其他 App 仅做到静默实时同步。
  - *价值*:本项目已有家庭共享 + 离线优先乐观更新的硬同步能力,但缺'社交可见性'软层。加'谁添加/勾掉了项'的署名 + 轻量反应,能解决共享清单的经典死结:只有一个人在维护。属于在现有同步管线上加薄薄一层的高性价比功能。
- **图标化/可视化的加项体验** `成熟标配` — Bring!
  - Bring! 给每个商品配可视化图标,加项是'点图标'而非纯打字,辅以智能补全与个性化推荐。这是 Bring 用户评论里反复夸的'有趣/直观',也是它在功能不如对手时仍能留人的原因。
  - *价值*:让录入低摩擦、有愉悦感,直接影响共享清单的'全家参与度'——参与度低的清单等于没用。对厨房 App,愉悦的录入也利于库存录入这一公认枯燥环节的留存。
- **促销传单/优惠券聚合 + 清单项内嵌价格与到期日** `成熟标配` — Flipp
  - Flipp 聚合 2000+ 零售商每周电子传单与数字券,从传单一键 clip 到清单,清单项自带'哪家最便宜 + 优惠有效期 + 价格匹配信息',官方称周省约 20%。共享清单是其 2024 最高呼声补齐项。
  - *价值*:促销数据本地难拿(中国市场无现成传单 API),不建议照搬;但'清单项内嵌到期/有效期'的信息架构思路可借鉴到本项目的减废与库存:把'保质期/最佳食用日'像 Flipp 把'促销到期日'那样压进单条目,降低用户的认知负担。
- **语音助手集成 + 拍照识物加项** `成熟标配` — OurGroceries, AnyList
  - OurGroceries 开箱集成 Alexa/Siri/Google Assistant 语音加项,并支持拍商品照片用 AI 识别后自动加入清单;AnyList 提供 iOS18 控制中心'Add to List/Scan Barcode'快捷控件。
  - *价值*:厨房的真实场景是'手上沾着面粉/油'——语音和拍照是比打字更贴合的录入方式。本项目已有 Siri & Spotlight、条码与小票 OCR,补'拍商品照片 AI 识别加库存'与 App Intents 语音加项,能把现有 AI/OCR 能力扩展到更自然的入口。
- **膳食计划里的'便签条目'与剩菜复用** `2024-2026新兴` — AnyList
  - AnyList 允许在膳食计划日历里加不构成完整菜谱的'便签'(零食/简餐/外卖),可选图标、可挂少量食材一键加购,并支持把剩菜(leftovers)直接排入计划、复用历史便签。
  - *价值*:本项目有膳食计划 + 剩菜入库,但'排计划必须挂正式菜谱'会逼用户为'周三吃泡面'也建菜谱。便签条目降低排计划门槛,剩菜作为一等公民排进计划天然衔接减废目标——两者都贴合本项目已有数据模型。
- **菜谱'做过次数 / 上次做的日期'与多维排序** `2024-2026新兴` — AnyList
  - AnyList 2025 给菜谱集合加网格大图视图,并支持按'做过日期、做过次数'排序,把菜谱库变成可量化的家庭常做菜热度榜。
  - *价值*:本项目有 364 条菜谱与膳食计划,记录'做过次数/最近一次'几乎零成本(膳食计划完成即可累计),却能驱动'好久没做的菜''家里最常做的菜'等推荐与排序,把静态菜谱库盘活成个性化资产。
- **全平台同步 + 一次性买断的商业克制** `成熟标配` — OurGroceries, Bring!
  - OurGroceries 覆盖 iOS/Android/Web/Apple Watch/Wear OS,且提供一次性买断去广告而非订阅;Bring 在 2025 更新里主动'移除不必要功能'。反观 Listonic 因更新后广告泛滥、退订路径差被大量差评。
  - *价值*:用户对该品类最大的负面情绪集中在'广告侵入、被迫订阅、功能臃肿'。本项目作为自有 iOS App 可把'无广告、克制功能、可靠同步'当作隐性卖点。功能上少即是多——Bring 的减法和差评教训值得作为产品取舍的反面镜鉴。
- **可靠的离线优先同步与'防重复购买'保证** `成熟标配` — OurGroceries, Bring!, AnyList
  - 该品类共识刚需:多人在店里同时改清单,变更需秒级同步、勾掉即全员可见,以避免重复购买;OurGroceries 把'可靠同步'当头号卖点。差评里多次出现'更新后清单整个消失需重打'(Listonic)。
  - *价值*:本项目已在离线优先乐观更新上做了大量投入(单行原语 updateRow/upsert、无闪空、失败回滚),这正是竞品翻车最多的地方。值得把'离线可靠不丢数据'显性化为产品承诺,并确保购物清单的勾选/数量编辑全部走已验证的乐观更新路径。

### 膳食计划 (Meal Planning)

- **拖拽式周/月膳食日历(早午晚加餐分槽)** `成熟标配` — Plan to Eat, Paprika, Mealime
  - 在周/月视图里把已保存的菜谱直接拖到任意一天的早餐/午餐/晚餐/加餐槽位,支持跨天移动、复制。Plan to Eat、Paprika 均为核心交互。
  - *价值*:这是膳食计划品类的基础体验底座。本 App 已有 MealPlan「移到其他日期」,补齐『拖拽+按餐别分槽』能把膳食模块从列表升级为真正的日历,与库存/购物联动天然契合。
- **加入购物清单时自动扣除库存已有项 (pantry-aware shopping)** `成熟标配` — Paprika, FoodiePrep, Mealime
  - 把菜谱排进计划/加进购物清单时,App 自动比对储藏室库存,已拥有的食材自动取消勾选或标注『已有』,只买缺口。Paprika 与新兴 AI App(FoodiePrep)都主打此点。
  - *价值*:本 App 同时拥有库存与购物两个模块,这正是品类里被反复夸的『闭环』功能,且本 App 已有库存徽标雏形——把它升级为自动扣减是最高性价比的差异化,直接减少重复购买与浪费。
- **购物清单跨菜谱同名食材合并 + 单位换算** `成熟标配` — Paprika, Mealime, Plan to Eat
  - 多道菜都要牛奶时,清单合并成『1 又 1/2 杯牛奶』而非两条;按超市货架分区(produce/dairy/…)排序。
  - *价值*:本 App 已有同名聚合与品类排序,补『带单位换算的数量合并』(本 App 食材已是数字化 quantity/unit schema,实现成本低)能显著提升购物清单的专业度,是高频好评点。
- **『按剩菜规划 / 煮一次吃两顿』排餐 (Plan as Leftover)** `小众` — Plan to Eat
  - 把一道菜以『剩菜』形式排到后续几天,不重复进购物清单,只提醒吃掉已做好的;可单独换配菜。
  - *价值*:直接服务本 App 的减废主线:让『多做一顿、第二天吃剩菜』成为日历上的一等对象,而非靠用户记忆。与本 App 已有的『剩菜入库』『用掉临期』形成完整减废叙事。
- **目标驱动的自动配菜引擎(卡路里/宏量约束求解)** `成熟标配` — Eat This Much
  - 用户设定每日热量与蛋白/碳水/脂肪目标(克或百分比),App 几秒内自动凑出满足目标的一天/一周菜单,可逐日差异化(训练日加碳)。
  - *价值*:本 App 已有营养信息(OFF nutriments)与膳食计划,补一个轻量『按营养目标自动填日历』能把被动记录升级为主动规划,是营养向用户的强吸引力功能。
- **拍照识别食材入库 + 拍小票/拍冰箱生成计划** `2024-2026新兴` — Samsung Food, WiseList, Ollie for Meals, Fridge Leftovers AI
  - Samsung Food 用 Vision AI 识别 4 万+ 食材一拍入库;WiseList 拍超市小票推一周菜单;Ollie/Fridge Leftovers AI 拍冰箱即出可现做的菜。
  - *价值*:本 App 已有小票 OCR 与到期日 OCR 基础设施,把它扩展为『拍照批量入库』『拍冰箱出菜谱』是 2025-2026 最热的增长点,且能复用既有 OCR/视觉链路,降低录入摩擦。
- **AI 改写既有菜谱以适配在库食材/饮食限制 (Personalize Recipe)** `2024-2026新兴` — Samsung Food
  - 对一道已存菜谱,AI 直接给出『纯素版/素食版』『更营养均衡版』或『换成你库里现有食材的版本』,而不是另推一道新菜。
  - *价值*:本 App 已有菜谱采集管线 + Cloudflare Kimi enrich 能力,把同一套 AI 用于『按库存/忌口改写菜谱』能直接利用既有库存、忌口、份量数据,贴合厨房真实约束,差异化明显。
- **库存反向作为菜谱搜索/推荐的排序信号** `2024-2026新兴` — Samsung Food, Ollie for Meals, FoodiePrep
  - Samsung Food『Search with Your Food List』把库里有食材的菜谱在搜索结果置顶;『用库存做计划』优先消耗在库与临期食材。
  - *价值*:本 App 已有库存 + 临期看板 + 菜谱目录三者,只需把库存命中度/临期度作为菜谱排序权重,即可低成本实现『今天用什么菜消耗临期食材』,强化减废主线。
- **可复用的膳食计划模板 / 整周菜单 (Saved Menus)** `成熟标配` — Paprika, Prepear, Plan to Eat
  - 把排好的一整周(或一套搭配)存成可复用模板,下次一键铺到日历;Prepear 还能订阅创作者发布的成套计划。
  - *价值*:降低每周从零排餐的负担,提升周复访。对本 App 的膳食模块是低实现成本、高留存价值的增量;『订阅他人计划』可作为后续内容化方向。
- **购物清单一键导出到生鲜配送购物车 (Instacart/Walmart/Kroger)** `成熟标配` — eMeals, Mealime, Eat This Much
  - eMeals/Mealime 把清单按份量匹配商品规格,一键灌进 Instacart、Walmart、Amazon Fresh、Kroger 等购物车直接下单。
  - *价值*:把『规划→购买』闭环延伸到实际下单。对 iOS App 而言,即便不接美国生鲜,也可借鉴『清单导出/分享为可下单格式』的思路;是品类天花板级的便利功能。
- **份量缩放贯穿『菜谱→计划→购物清单』全链路** `成熟标配` — Mealime, Eat This Much, Plan to Eat
  - 改用餐人数后,食材用量、计划份数、购物清单数量同步重算;Samsung Food 曾因份量改了不带进购物清单而被用户狂吐槽。
  - *价值*:本 App 已有份量缩放,但要确保缩放结果一致传导到购物清单——竞品最大投诉点正是『serving size 改了不进 shopping list』,把这条做对就是直接规避同行公认的坑。
- **强菜谱抓取器:粘贴 URL 结构化导入食材+步骤** `成熟标配` — Plan to Eat, Paprika
  - Plan to Eat 的 Recipe Clipper 被公认全品类最干净:任意菜谱网址→食材、步骤、图片自动结构化入库。
  - *价值*:本 App 已有菜谱采集管线(Flue),面向 C 端可提供『用户粘贴链接导入私房菜谱』能力,补齐 UGC 菜谱来源;竞品(Samsung Food)的浏览器扩展长期损坏正是用户痛点,做稳即口碑。

### 食谱管理 (Recipe Management)

- **社媒视频 URL 导入食谱(YouTube/Instagram/TikTok)** `2024-2026新兴` — Mela, CookTok, CookingGuru, Flavorish
  - 用户粘贴一条短视频链接,app 解析视频(描述,进阶版还转写口播音频+识别屏幕叠字)自动结构化出食材用量与步骤。Mela 2.5 已落地基础版(读描述),CookTok/CookingGuru/Flavorish 做到了音视频转写级别。
  - *价值*:2024-2026 食谱的主要消费载体已是短视频,而非博客网页。一个库存/膳食 app 若能让用户把刷到的菜直接「存进来」并自动拆出配料,就接住了真实采集习惯,且抽出的食材可直接喂给购物清单/库存扣减。这是当下导入面的最高优先级缺口。
- **单张照片 / OCR 实体菜谱书 AI 导入** `成熟标配` — Crouton, Paprika AI, Flavorish, Honeydew
  - 拍一张照片(菜谱书页、手写卡片、网页截图),AI+OCR 自动转成可编辑的结构化食谱,零手动录入。
  - *价值*:降低录入摩擦是食谱类留存的命门。本项目已有小票/到期日 OCR 基础设施,复用到「拍菜谱页」成本低、用户感知强,能把家传/书本菜谱也纳入库存与采购联动。
- **Cook Mode 步骤内点击食材即显用量** `2024-2026新兴` — Crouton, Deglaze
  - 在分步烹饪模式里,步骤文本中的食材是可点击的;点一下就弹出/标注该食材在本步的精确用量,无需滚回顶部配料表。Deglaze 的「行内食材」更进一步,直接把用量内联进每一步且随缩放更新。
  - *价值*:做菜时手忙脚乱来回翻配料表是核心痛点。本项目已有 Cook Mode,加这一层把「读步骤」与「查用量」合并,体验提升立竿见影,且实现只需把食材与步骤做词级关联。
- **步骤内时间自动识别为可启动计时器 + 常驻 HUD** `成熟标配` — Crouton, Mela
  - 解析步骤文本里的时间表述(「煮10分钟」「静置1小时」),自动生成可一键启动的计时器;运行中以常驻浮层 HUD 始终可见,可从多个步骤并行起多个计时器。
  - *价值*:把烹饪步骤变成可执行的计时动作,是 Cook Mode 从「电子菜谱」升级为「烹饪助手」的关键。纯本地实现、无需后端,价值高,契合本项目偏好本地优先的功能。
- **缩放显示为干净分数 + 双维度缩放(按份数/按单个食材) + 单位换算** `成熟标配` — Deglaze, Paprika, Crouton
  - 缩放后用量显示为 1/2 杯、1/4 茶匙 这类规范分数而非 0.5/0.333 难看小数;支持按总份数或单独某个食材缩放;弹层内一键在公制/英制/原始单位间换算,行内标注同步刷新。
  - *价值*:本项目已有份量缩放,但中文厨房里分数/克↔毫升/把↔克 的呈现质量直接决定可用性。把缩放做到「分数漂亮、单位可换、内联同步」是低风险高感知的打磨,且与已数字化的食材 quantity/unit schema 天然契合。
- **AI 按饮食限制/忌口改写已有食谱** `2024-2026新兴` — Samsung Food
  - 对一份已保存食谱,AI 一键改写成符合用户饮食画像的版本(转素食/纯素、低盐、替换过敏原食材),并相应更新食材与步骤。
  - *价值*:本项目已有「忌口」设置但仅用于过滤;把忌口升级为「主动改写食谱替换冲突食材」是 AI 在食谱管理里最具差异化的落地点,且能与库存联动(改写后用现有食材替代)。
- **冰箱/储藏室拍照 → AI 识别食材 → 反推可做菜谱** `2024-2026新兴` — Fridge Scanner, SuperCook, Cooklist, Crumb
  - 拍一张冰箱或橱柜照片,AI 识别其中食材,直接推荐无需额外采购即可做的菜;或基于已录库存做 cook-from-pantry 反查。
  - *价值*:这是库存类 app 与食谱的天然交汇点,直击本项目的减废核心目标——把临期/在库食材主动转化为「今晚能做的菜」。比让用户手动搜菜谱更贴合「先有食材后找菜」的真实决策顺序。
- **购物清单智能合并去重 + 按门店货架动线排序** `成熟标配` — Copy Me That, Mealime, Grocery AI, Plan to Eat
  - 把多个食谱的相同食材智能合并(含非精确匹配,如「1个切碎洋葱 + 2个洋葱 = 3个洋葱」);并按真实超市动线(产区→乳品→储藏→冷冻)对清单重排,有些会学习用户常去门店的货架顺序。
  - *价值*:本项目已有购物品类排序与同名聚合,但「非精确单位/形态的合并」(切碎洋葱 vs 整颗)和「按货架动线而非字母/品类排序」是进一步减少漏买、加快采购的具体增量。
- **Pantry 感知:购物时标记「你已经有了」** `成熟标配` — Paprika, FoodiePrep, Grocery AI
  - 生成购物清单时,把食材与储藏室/库存比对,对已拥有的食材打标或剔除,避免重复购买。
  - *价值*:本项目已有库存数据,这是几乎零额外成本就能做的高价值联动——膳食计划/食谱生成清单时自动扣减已在库项,既防重复买又是减废抓手。属于本项目独有的数据优势能直接变现的功能。
- **AI 食谱步骤简化(长步骤拆成小块)** `2024-2026新兴` — Crouton
  - 对又长又密的导入步骤,AI 自动拆解成简短、单一动作的小步骤,便于在 Cook Mode 一步一屏地跟做。
  - *价值*:用户从社媒/网页导入的食谱步骤质量参差,常常一大段塞进一步。自动重排成原子步骤,直接提升 Cook Mode 可用性,且与本项目已有的菜谱清洗管线理念一脉相承(可在导入侧或管线侧做)。
- **多食谱并行 Cook Mode(一桌多菜统筹)** `小众` — Mela
  - Cook Mode 内可同时加入多个食谱并快速切换,配合各自的计时器统筹,适合一顿饭做多道菜的真实场景。
  - *价值*:单食谱 Cook Mode 已是标配,但真实做饭是几道菜并行。允许同时跟做多个食谱并集中管理计时,是把 Cook Mode 从演示功能做成日常工具的关键差异点。
- **膳食计划自动生成食材并整理为分类购物清单** `成熟标配` — Crouton, Samsung Food, Paprika
  - 把食谱排进周/未来膳食计划后,app 自动汇总所有食材、合并同类、按品类整理成购物清单;部分支持从已有晚餐食谱库自动生成整周计划。
  - *价值*:本项目已有膳食计划与购物清单两个模块,把「计划 → 自动汇总食材 → 扣减库存 → 生成需采购清单」打通成一条闭环链路,是把分散功能串成完整工作流的最高杠杆整合,也是各成熟竞品的标配能力。

### 减废 / 临期 / 捐赠 (Food-waste reduction, near-expiry rescue & community donation)

- **删除/丢弃时追问去向,并把每次浪费金额化** `成熟标配` — Kitche, NoWaste, MITRE Food Waste Tracker
  - 用户从库存移除食物时弹出去向(吃完/做菜消耗/扔了/捐了/堆肥),‘扔了’时按该食材的购买价或类目均价计入‘本周/本月浪费金额’。Kitche 把它做成左右滑动一刷记录(swipe-to-record),NoWaste/MITRE 则给出‘少扔=省钱’的金额估算。
  - *价值*:厨房库存 App 已经知道每件食物的数量与品类,天然能算出金额浪费——这是把‘减废’从抽象口号变成钱包数字的最低成本切入点,也是后续所有成效统计的数据源。
- **个人 Impact 仪表盘:省下金额 + CO2e + 水耗,用固定换算系数累计** `成熟标配` — Too Good To Go, Kitche, Flashfood
  - 把累计‘按时吃掉/拯救’的食物换算成省下的钱、避免的 CO2e 和水耗,用每份/每千克的固定系数累加成一个可炫耀的总数。Too Good To Go 用‘每袋≈2.7kg CO2e’,让每次行为立刻有可见回报。
  - *价值*:厨房 App 的 food_log 已经在记吃完/扔了,加一层换算系数即可生成环境+金钱双维度成就页,极大提升打开动机和分享意愿,几乎零额外数据成本。
- **与‘全国/同类家庭平均’对比的浪费基准线** `小众` — Kitche
  - 把用户自己的浪费成本画成折线,叠加一条‘全国家庭平均浪费’基准线做社会比较,并允许自建 missions/challenges 去压低自己的曲线。
  - *价值*:纯个人统计容易自我感觉良好;引入社会比较(你比平均多浪费 X 元)能显著提升减废动机,且基准线是静态常量、无需联网即可落地。
- **保质期素养:区分‘赏味期 vs 食用期’+ 看-闻-尝提示** `2024-2026新兴` — Too Good To Go
  - 对‘最佳食用前(品质)’与‘食用截止前(安全)’两类日期分别标注与提示,临期时弹出‘看-闻-尝再决定’而非直接催扔,并配科普文案/图标。
  - *价值*:App 内已有 [[fresh-pantry-market-optimize-loop]] 提到的‘双类保质期食安’待拍板项;这正是 Too Good To Go 在做的事,能直接减少‘到日就扔’造成的非必要浪费,是减废 App 的差异化专业感来源。
- **记录动作即奖励的成就体系(铜/银/金勺、徽章、连续打卡 streak)** `成熟标配` — Kitche, Olio
  - 为‘启动 App/加品/扫小票/选菜谱/记一次浪费’这些过程动作分别发铜银金勺,并用 streak(连续 N 天零浪费/连续记录)制造‘别断链’的日常习惯。研究显示成就/收集型用户占 45%、连续打卡可把留存提到 81%。
  - *价值*:减废是长期低频行为,靠结果(年省 X 元)难以驱动每日打开;奖励‘过程动作’和 streak 能把记录变成习惯,直接喂养上面的统计数据,形成正循环。
- **AI 小票拍照批量入库 + 按食材类型自动估算到期日** `2024-2026新兴` — NoWaste.ai, Kitche
  - 拍一张纸质/电子小票,AI 识别出食材逐条加入对应空间(冰箱/冷冻/储藏),并按食材类型自动估算保质期、设智能提醒;兼容主流电商小票格式。
  - *价值*:手动逐条录入+填到期日是库存类 App 最大的流失点;AI 小票解析把入库降到一拍,自动估到期日则让‘临期看板/减废统计’有数据可算,是 2025 年该品类最强的获客/留存杠杆。
- **临期清仓闭环:临期提醒 → 一键用临期食材搜菜谱** `成熟标配` — Kitche, NoWaste, Too Good To Go
  - 对接近到期的食材主动提醒,并直接推荐能优先消耗这些食材的菜谱(用掉临期),形成‘别扔→做掉’的闭环而非只报警。
  - *价值*:本项目已实现‘用掉临期’,但可强化为‘临期看板里每件都带一个 →做这道菜 的直达入口’,把提醒变成可执行动作,是把临期管理与既有菜谱库打通的高价值连接点。
- **邻里 C2C 免费共享/赠送临期食物(含信任分门槛与就近匹配)** `成熟标配` — Olio
  - 用户把吃不完的临期食物发图+标签+地理位置挂出,邻居私信约门口/安全点自取;出借/赠送方可设‘评分≥4★、共享过 5+ 次、2km 内’等门槛,用轻量信任分替代支付与押金。
  - *价值*:对家庭厨房 App 是最强的社区化扩展方向:把‘扔不掉的半盒东西’变成邻里社交货币,既减废又自带社交裂变。落地成本较高(需 LBS+IM+信任体系),适合作为长期 A 类拍板项。
- **捐赠流:挂出食物时指定慈善机构做 pay-as-you-feel 捐赠** `2024-2026新兴` — Olio
  - 在共享/清仓动作上叠加一个‘捐给指定慈善机构’的选项,支持随意金额(pay-as-you-feel)捐赠,把个人减废行为接入正式的食物再分配网络(如 FareShare)。
  - *价值*:为减废 App 提供‘善意出口’和品牌价值感;即使 MVP 不接真实慈善 API,也可先做‘标记为已捐赠’作为 food_log 的一种去向,丰富减废成效统计的正向口径。
- **临期捡漏地图:一屏对比多店折扣(卡片式横竖滚动)** `2024-2026新兴` — Flashfood, Too Good To Go
  - 用地图+卡片同屏展示附近多家有临期专区/盲盒的店及其折扣,横竖滚动快速比价,像逛折扣地图一样找捡漏点。
  - *价值*:若 App 后续接入商家临期清仓侧,这是把‘省钱捡漏’做成可逛体验的范式;即便纯家庭版,也可借鉴‘卡片同屏对比’的信息密度做临期看板。
- **‘按时吃掉省了多少钱’的正向口径(而非只统计损失)** `小众` — NoWaste, Too Good To Go
  - 除了统计扔掉的损失,额外统计‘因为按时吃掉/做掉而避免的浪费金额’,把减废成效表达为积极的‘已省下’而非消极的‘已损失’。
  - *价值*:心理学上正向反馈比负向更能维持长期行为;同一份 food_log 数据换个口径(consumed 计为‘救下的钱’)即可生成,几乎零成本,且能配合成就/分享。
- **盲盒化临期清仓(把临期重新包装为‘惊喜袋’)** `成熟标配` — Too Good To Go
  - 把临期/余量打包成低价‘惊喜袋’,弱化‘快坏了’的负面感、强化‘划算+开盲盒’的情绪;品类可细分(果蔬/海鲜/肉/烘焙/冷冻)。
  - *价值*:情绪重构是 Too Good To Go 成功核心。家庭版可借鉴‘把临期区做成正向的清仓挑战/惊喜’而非红色警告墙,降低用户对临期的焦虑与回避。

### 营养与健康（Nutrition & Health）

- **扫条码即出健康评分（Nutri-Score / NOVA / Yuka 式 0-100）** `成熟标配` — Yuka, Open Food Facts, Lifesum
  - 扫商品条码后，立即返回一个可即时决策的健康分级——可以是字母分级（Nutri-Score A-E）、加工度（NOVA 1-4）或综合分数+颜色（Yuka 0-100 红橙绿）。把营养标签的复杂信息压缩成货架前一眼可懂的信号。
  - *价值*:厨房 App 的购物/库存模块本就在扫码或录商品，复用同一条码即可叠加健康维度，几乎零额外用户操作。可直接接入 Open Food Facts 免费数据库实现，无授权成本。给'买什么/囤什么'提供决策依据，而不只是记录。
- **多模态录入（拍照 / 语音 / 文本 / 扫码 四合一）** `2024-2026新兴` — MyFitnessPal, Foodvisor, Lifesum
  - 把所有录入方式合并进一个入口，用户可任选拍照 AI 识别、语音口述、文字模糊搜索或扫码。2025 年起成为头部营养 App 的统一交互范式（MFP Summer Release、Lifesum 多模态记录器）。
  - *价值*:库存录入和购物清单录入是高频且摩擦大的动作，多模态能显著降低录入成本。尤其语音（'加两斤西红柿、一盒鸡蛋'）和拍照（拍冰箱/小票批量入库）对厨房场景非常贴合，本 App 已有小票/到期日 OCR 基础，可延伸。
- **AI 拍照识别整盘并拆分多菜品** `2024-2026新兴` — Foodvisor, MyFitnessPal, Lifesum
  - 对一张餐盘照片识别出多个独立菜品并分别估算营养，而非把整盘当成一个条目。Foodvisor 测得约 87% 准确率，本地化食材库是准确率关键杠杆。
  - *价值*:对'剩菜入库''今天做了什么菜'场景，拍一张照就能拆分录入多个库存/膳食条目，比逐个手填高效得多。中餐混合菜需要本地化食材库——这正是本 App 已有 364 条中文菜谱库可作为识别词表的独特优势。
- **差评商品的'更健康替代品'推荐** `成熟标配` — Yuka
  - 当扫到的商品评分差时，自动按品类+评分+门店在售推荐更健康的同类替代品，让用户当场就能换购。Yuka、Fooducate、CodeCheck 都有此机制。
  - *价值*:这是把'评分'从评判升级为'行动'的关键闭环，也是与购物清单结合最自然的点：在加入购物车/清单时提示'有更优替代'。对厨房 App 是从被动记录走向主动建议的差异化功能。
- **添加剂/加工度透明化标注 + '为什么'说明** `成熟标配` — Yuka, Open Food Facts
  - 逐项列出商品含的添加剂并标风险等级，每条附依据或预防性说明；NOVA 则用 1-4 级标注加工程度，4 级=超加工食品。让用户看懂'这个商品哪里不好'。
  - *价值*:为库存/购物商品增加'成分透明度'维度，帮用户识别超加工食品。NOVA 加工度比单纯热量更能区分真食物与工业食品，且数据可从 Open Food Facts 免费获取。注意要做'解释'而非'恐吓'。
- **日度健康总分（Life Score 式聚合反馈）** `成熟标配` — Lifesum
  - 把当天的多个分散指标（营养均衡、蔬果摄入、加工食品比例等）聚合成一个'今天健康吗'的日度分数+个性化建议，给即时正反馈。
  - *价值*:厨房 App 可基于库存结构/本周膳食计划生成'本周饮食健康度'或'临期消耗率'式聚合分，把分散的库存/膳食/减废数据变成一个有黏性的总览指标，提升留存。比单条记录更能驱动日常打开。
- **膳食计划自动生成购物清单** `成熟标配` — Lifesum, MyFitnessPal
  - 选定饮食法/膳食计划后，App 自动汇总所需食材生成带分量的购物清单，部分还联动 Instacart 等直接下单。
  - *价值*:本 App 同时拥有膳食计划和购物清单两个模块，这是天然衔接点：从周膳食计划一键生成购物清单、并自动扣除库存已有项（只买缺的）。这是营养 App 在做、而厨房 App 更该做好的核心整合能力。
- **正向营养追踪（蔬果鱼摄入而非只盯热量限制）** `小众` — Lifesum
  - 除了限制性指标，专门追踪蔬菜、水果、鱼、水等'多吃有益'的项目，鼓励达成而非禁止。Lifesum 有蔬果鱼专项追踪器。
  - *价值*:规避了 Yuka 被营养师反复批评的'食物恐惧/非黑即白'问题。厨房 App 可统计'本周吃了几种蔬菜''膳食多样性'等正向指标，把减废和健康饮食框定为积极目标，更可持续、更少诱发饮食焦虑。
- **'先拍后录'：录入与整理动作解耦** `2024-2026新兴` — MyFitnessPal
  - 允许用户先快速拍照存档，稍后由 AI 解析并补全条目（MFP Premium+ 的 Photo Upload）。解决'当下没空精细录入'的摩擦。
  - *价值*:厨房场景同理：买菜回来/打开冰箱时先拍一张，之后 App 后台识别并批量生成库存条目待用户确认。把高摩擦的批量入库拆成'零成本拍照 + 闲时确认'，大幅提升录入完成率。
- **免费开放数据库 + 众包补全（Open Food Facts 模式）** `成熟标配` — Open Food Facts
  - Open Food Facts 提供 400 万+ 商品的免费开放数据与 API；用户可拍照上传缺失商品的标签/营养表补全数据库，并保留历史图片，2025 起还众包价格（Open Prices）。
  - *价值*:对独立开发者是最具落地价值的一条：零授权成本接入条码→营养/Nutri-Score/NOVA，立即给商品库增加营养维度。众包补全 + 历史图片机制也可借鉴用于缺图/缺数据商品的社区补全（本 App 已有菜谱补图经验）。
- **权威背书：营养师审核内容徽章（Blue Check）** `2024-2026新兴` — MyFitnessPal
  - 对食谱/建议内容标注'注册营养师审核'徽章，区分 AI 生成与专业审核内容（MFP 2026 Blue Check Collection）。
  - *价值*:在 AI 生成内容泛滥的当下，给食谱/健康建议加可信度信号是差异化方向。本 App 已有 364 条菜谱库，可对部分内容做'营养审核'标记或标注营养估算来源，提升内容可信度而非全靠 AI。
- **环境影响评分（Green-Score / Eco-Score）** `2024-2026新兴` — Open Food Facts
  - 在营养之外给商品打环境影响分（A-E，综合 16 项环境指标），帮意识到饮食的碳足迹/可持续性。2024 末由 Eco-Score 更名 Green-Score。
  - *价值*:与减废主题高度契合：本 App 已有减废看板，可叠加'减废=减碳'的环境维度，把扔掉食物量换算成环境影响，强化减废行为的意义感。数据同样可从 Open Food Facts 免费获取。

### 中国本土厨房 App(食谱发现 / 库存 / 购物 / 膳食 / 减废)

- **扫码 / 拍照 AI 识别快速录入食材** `2024-2026新兴` — 收起来, 保质期提醒助手, 过期啦, 海尔智家
  - 扫商品条形码自动带出名称/分类/常见保质期;拍照用视觉模型批量识别多件食材;输生产日期/批号反推到期日。代表:收起来、各类保质期 App、海尔 AI 食材管家。
  - *价值*:库存类 App 最大的流失原因是手动录入太累。把每件食材的录入成本从十几秒压到一两秒(甚至拍一张照入库多件),直接决定库存功能是否会被持续使用——这是该品类的生死线。
- **拍冰箱 / 选库存食材反向推荐'能做什么菜'** `2024-2026新兴` — 海尔智家, Fridge Leftovers AI, 食谱菜谱AI助手, 美食杰
  - 用户拍冰箱内景或勾选已有库存食材,多模态/大模型识别后列出当前食材可做的菜谱,并标出还缺哪几样。代表:海尔 AI 食材管家、Fridge Leftovers AI、各类 AI 做菜助手、美食杰按食材找菜。
  - *价值*:这是把'库存'和'食谱发现'打通的杀手级闭环:既消化临期食材(减废),又解决'有菜不知道做啥'的日常决策疲劳。对一款同时有库存+食谱的 App 是天然的差异化王牌,且当前正处于新兴红利期。
- **菜谱食材一键汇入购物清单并跨菜谱去重合并** `成熟标配` — 下厨房, 电子菜单, 豆果美食
  - 从任意菜谱/周计划把所需食材加入统一'菜篮子',同名食材自动合并数量,可勾选已在库存的项不重复买。代表:下厨房菜篮子。
  - *价值*:把'看菜谱→规划采购'无缝连接,是膳食计划与购物清单之间的关键桥梁。去重合并+扣减库存能显著减少重复购买和浪费,是成熟但仍高频被用户夸的核心价值点。
- **二十四节气 / 时令食材驱动的内容更新与推荐** `成熟标配` — 下厨房, 美食杰, 豆果美食
  - 按节气当天切换首页推荐应季菜肴;每月按水果/蔬菜/五谷/生鲜推当季食材;结合节气给养生饮食建议。代表:下厨房时令流行、美食杰应季食材、豆果养生、二十四节气类 App。
  - *价值*:节气是中国用户独有的、自带情感与文化认同的内容节奏器。它给 App 提供了'无需用户主动搜索就有理由推送今天吃什么'的天然触发点,提升打开频次,也契合应季食材更新鲜便宜的实际利益,是本土化的高性价比差异点。
- **食材用量精确量化 + 每步标注耗时与防错提示** `成熟标配` — 懒饭
  - 所有食材/调料精确到克/毫升,杜绝'适量/少许';炒/炖等步骤标注所需时长;关键步骤内联防出错小贴士。代表:懒饭。
  - *价值*:'适量/少许'和'判断不了熟没熟'是新手做饭的两大劝退点。量化用量直接服务于库存扣减的准确性(做完一道菜能精确扣减食材),也提升新手留存,对'库存+食谱'联动的 App 价值双重叠加。
- **1分钟短视频菜谱(只留核心步骤)+ 图文并存** `成熟标配` — 懒饭, 美食杰, 豆果美食
  - 把菜谱拍成1分钟高清短视频高效呈现用料/用具/步骤,删繁就简;同时保留图文,做菜时看图文不用反复拖视频进度条。代表:懒饭、美食杰、豆果在线课堂。
  - *价值*:短视频是当下中国用户消费菜谱的主流形态,且新手跟做成功率远高于纯图文。'视频学+图文做'的组合解决了厨房油手反复操作的实际场景痛点,是提升食谱发现转化与完成率的成熟手段。
- **家庭共享同一份库存 / 购物清单(多人实时协作)** `成熟标配` — 收起来, 电子菜单, Bring
  - 家庭成员加入同一空间,共享冰箱/储藏库存与购物清单,任一人增删实时同步;可按冰箱/冷冻/储藏/不同储位分场景管理。代表:收起来、Bring、电子菜单。
  - *价值*:买菜做饭本质是家庭协作场景(一人买、一人做、库存共看)。多人实时同步避免重复购买、信息不对称,是把工具升级为'家庭厨房中枢'的关键,也大幅提升留存与口碑传播。
- **保质期临期提醒 + 日历/时间轴双视图 + 低库存提醒** `成熟标配` — 收起来, 保质期提醒助手, 过期啦, 叮咚买菜
  - 录入即开始到期倒计时,临期自动推送提醒优先消耗;库存与到期以日历或时间轴两种视图呈现;常备食材低于阈值时提醒补货。代表:收起来、保质期提醒助手、过期啦。
  - *价值*:减废功能的落地形态。'临期提醒优先吃'直接减少扔掉的食物=帮用户省钱,是减废类 App 的核心承诺;低库存提醒则反哺购物清单,形成'库存→减废→补货'的运营飞轮。
- **AI 营养师 / 健康目标驱动的每日三餐定制** `2024-2026新兴` — 豆果美食, 叮咚买菜
  - 用户设定健康/减脂/增肌目标,记录每日饮食,AI 据此定制每日三餐并解锁当日健康菜谱,结合体质/节气养生。代表:豆果美食 AI 营养师、叮咚 AI 膳食管家。
  - *价值*:把抽象的'膳食计划'包装成人格化助手,降低规划三餐的心理门槛。结合营养/卡路里目标能把'食谱发现'升级为'按目标推荐',提升膳食计划模块的使用动机与用户黏性。
- **做过标记 + 作品 UGC + 榜单社会证明** `成熟标配` — 下厨房, 豆果美食, 美食杰
  - 每道菜可标记'做过N次'、收藏'想做';用户上传成品'作品'照片与心得;首页展示'被N万人做过'的榜单。代表:下厨房、豆果美食、美食杰。
  - *价值*:'N人做过+真实作品照'是降低新手选菜决策成本的强社会证明,远胜官方精修图;'做过'还自然形成个人烹饪履历,为复推/收藏/复购提供数据。社区是该品类形成网络效应、对抗工具同质化的护城河。
- **菜谱 → 净菜 / 食材一键下单配送到家** `成熟标配` — 叮咚买菜, 盒马, 下厨房
  - 从菜谱直接把所需食材(含预洗预切净菜)一键加入买菜车并配送;库存缺料时深链跳转买菜平台补货。代表:叮咚买菜、盒马、下厨房市集。
  - *价值*:把'决定吃什么'到'食材到家'压缩为一步,是当下最强的做饭转化闭环。对独立 App 即使不自营电商,也可做导购/深链合作:库存检测到缺料→一键跳转补货,既提升体验又有商业化空间。
- **按食材 / 功效 / 体质等多维反向检索菜谱** `小众` — 美食杰, 豆果美食
  - 除菜系/口味外,支持按'当季食材''药膳食疗/功效''体质''快手/新手'等维度反向找菜;极细分类(如164个小栏目)。代表:美食杰、豆果养生。
  - *价值*:用户真实诉求常是'我有这些食材''我想调理身体',而非按菜名搜。多维反向检索(尤其按已有库存食材)直接服务'减少浪费+按需做饭',是本土养生文化下的差异化筛选维度。

### AI/智能家居/创新 (AI / Smart Home / Innovation) — 厨房库存·配方·膳食·减废类竞品

- **拍照/视觉批量识别食材,一键灌入库存** `2024-2026新兴` — Samsung Food, ChefGPT, Fridge Leftovers AI, Whisk, Remy
  - 对着冰箱或储藏柜拍一张照片,多模态视觉模型识别出全部食材并批量加入库存列表(Samsung Vision AI 云端识别 >4 万种;ChefGPT/Fridge 系拍剩菜识别)。可与现有的小票/到期日 OCR 能力同源复用同一相机入口。
  - *价值*:手动录入是所有库存类 App 的头号弃用原因。一张照片替代逐条录入能把'入库'从分钟级降到秒级,直接拉高库存数据的完整度,而库存完整度是后续临期提醒、配方匹配、减废统计一切功能的地基。
- **对话式'用我现有的食材能做什么'配方生成(带自由文本约束)** `2024-2026新兴` — ChefGPT, Magic Chef, Samsung Food, SideChef
  - 用户用自然语言提约束('用鸡肉和西葫芦、无麸质、30 分钟内'),AI 在库存范围内生成可做配方;支持'剩菜专用'入口。区别于固定筛选器的关键是接受任意组合约束。
  - *价值*:你已有本地配方库 + 库存 + 忌口数据,正是喂给生成式约束的完美上下文。把'按库存检索配方'升级成'按库存+口味+时间+饮食限制对话生成',能解决'今晚到底做啥'这个每日高频决策疲劳,是把工具型 App 变成助手型 App 的关键一跳。
- **临期优先作为推荐/排序的一等输入(use-first)** `2024-2026新兴` — Remy, KitchenPal, FedWell, Eat This Much
  - 把'快过期'直接作为配方推荐与膳食计划排序的最高权重输入,而不是让用户事后去筛'临期'标签。Remy 的整套推荐模型以临期 + 过敏 + 历史习惯联合驱动,主打减废 70%。
  - *价值*:你已有临期看板和减废统计,但若临期食材没有主动汇入'今天推荐做这道菜'的链路,减废仍依赖用户自觉。把临期反向驱动配方/膳食推荐,能把减废从被动记账变成主动闭环,且与你现有的减废成效统计天然咬合。
- **做完菜自动回扣库存(配方↔库存闭环)** `2024-2026新兴` — Remy
  - 用户标记某配方'做了',系统按配方用量自动从库存扣减对应食材;反过来库存又驱动下次推荐。Remy 明确把'recipes update inventory after cooking'作为核心。
  - *价值*:这是库存保持准确的关键环节,否则库存会随时间失真、临期提醒变噪声。你已有 Cook Mode、剩菜入库、部分消耗(planPartialConsume)等原语,补上'做菜自动扣减'即可闭环,且数据更准会反哺所有下游功能。
- **整周膳食计划自动排盘(给目标→出整周,而非手动拖拽)** `成熟标配` — Eat This Much, Prospre, FedWell
  - 用户设定卡路里/宏量目标 + 偏好 + 忌口 + 库存优先,App 自动生成整周计划并产出合并后的购物清单;不喜欢某餐可一键 swap 而保持目标不变。Eat This Much/Prospre 是范式。
  - *价值*:Samsung Food 被用户反复吐槽'有膳食计划但要自己一道道拖到每天'。你已有膳食计划日历 + 营养模型 + 库存,补一个'自动排盘 + 单餐替换'就能从'手动排程工具'升级为'帮你排好',这是当前竞品最大的体验落差点之一。
- **语音自由口述 → 结构化条目(购物/库存)** `2024-2026新兴` — Grocery AI, SmartThings, Alexa+
  - 用户口述'两盒牛奶、半斤排骨、一袋全麦面包',AI 解析成带数量/单位/品牌/备注的结构化购物或库存项。Grocery AI 的 Voice Add 是代表。
  - *价值*:做饭/边逛超市时双手占用,语音是比打字快得多的录入方式。你已有拼音搜索、Siri/Spotlight 集成基础,把一段语音直接转成结构化条目能进一步压低录入摩擦,尤其利好购物清单这种边走边加的场景。
- **AI 小票 OCR 批量解析(图像预增强 + 自动归类 + 价格)** `成熟标配` — Grocery Tracker Pro, Grocery AI, SpendScan
  - 对褪色/褶皱小票先做图像增强再 OCR,提取品名 + 价格 + 70+ 类自动归类,支持批量多张与 PDF;标准超市小票号称 95%+ 免修正。
  - *价值*:你已有小票 OCR,但'提取价格 + 自动归类'是延伸点:价格列能直接喂给'浪费金额统计'(你 MEMORY 里待拍板的 A 类功能),把减废从'扔了几样'升级为'扔了多少钱',对用户的冲击力和留存价值显著更高。
- **全网/社媒配方导入并解析为结构化分步(含视频)** `成熟标配` — Whisk, Samsung Food, SideChef
  - 粘贴 TikTok/Instagram/YouTube/Pinterest/任意博客链接,AI 理解视频与网页后转成统一的结构化食材表 + 分步骤;Whisk/Samsung Food 跨平台覆盖最广。
  - *价值*:你已有 B 站视频外链与本地配方库,但'用户自己看到的网红配方导入进来'是用户高频诉求(Samsung Food 正因导入不稳被骂)。一个稳定的'贴链接即入库'能极大丰富配方来源,并让你的库存匹配/购物清单生成应用到用户真正想做的菜上。
- **配方个性化改写(一份配方→N 种饮食版本)** `2024-2026新兴` — Samsung Food, ChefGPT, SideChef
  - 对任意配方一键改造成低卡/素食/无麸质/低钠等版本,自动替换食材并调整用量与步骤。Samsung Food 的 Personalize Recipe。
  - *价值*:你已有忌口/份量缩放,补'按饮食目标整体改写配方'能服务全家不同饮食需求(一人减脂一人正常),且复用你已有的忌口关键字与营养数据,把静态配方变成可适配资产。
- **主动式补货建议 / 预测性补给(agentic 雏形)** `2024-2026新兴` — Remy, Amazon Alexa+, Samsung Food, FMI agentic grocery
  - 基于历史购买频率 + 当前库存 + 临期,主动提示'牛奶快没了要不要加进清单',下一步演进到半自动/自动补单。2025 调研 32.6% 美国食品购买者愿意让 AI 自动补常购品。
  - *价值*:这是 2026 最热的方向(Alexa+/Rufus agentic 购物)。你不必接入零售商,先做'本地预测性补货建议'(常购品消耗周期模型 → 主动加入购物清单)就能体现前瞻性,且完全离线优先、与你现有架构契合。
- **减废成效游戏化 + 金额量化(代币/积分/省了多少钱)** `2024-2026新兴` — Remy, FoodSave, Too Good To Go
  - 把减废行为转成积分/代币/省钱金额并可视化(Remy 的 RemyCoin、FoodSave 的 gamified points + savings analytics、Too Good To Go 的社会化减废规模)。
  - *价值*:你已有减废统计与用掉率,但缺'激励层'。把'本月省下 ¥X / 减少 Y kg 浪费'做成里程碑/连胜/徽章,能显著提升日活与情感粘性,把一个工具型功能变成有反馈回路的习惯养成,且与小票价格列协同。
- **硬件/外部信号驱动的主动告警与远程查看** `成熟标配` — LG ThinQ, Samsung Family Hub
  - 智能冰箱内置摄像头远程查看内容、温度异常主动推送、自动维护食材清单(LG ThinQ / Samsung Family Hub)。
  - *价值*:纯 iOS App 无需买冰箱,但可借鉴'主动告警'理念并做 WidgetKit/Live Activity(你 MEMORY 中待拍板的 A 类):把临期 Top3、今日该做的菜放到锁屏/小组件,实现'不打开 App 也被提醒',逼近智能硬件的主动性,而成本只是一个 Widget。

---

## 附录 B · 本 App 现有功能盘点(基于真实代码,36 项)

### Inventory
- **Complete Inventory Management** — Full-featured inventory system with add/edit/delete food items, filter by storage location (fridge/freezer/pantry), detailed views with freshness/batch/shelf-life info, expiry alerts (7/3/1 day tiers), future 7-day change prediction, batch delete/undo and merge capabilities
- **AI-Powered Ingredient Intake** — Manual text input, paste-from-clipboard, or photo OCR recognition for ingredient entry. AI extracts structured data (name/quantity/unit/category/storage/shelf-life), supports recommendation refinement, intake review with auto-merging duplicate items, frequent items quick-fill chips
- **Barcode Scanning (VisionKit)** — Real-time barcode scanning (1D/2D) via VisionKit DataScannerViewController, auto-lookup OpenFoodFacts API to fill name/nutrition, one-tap auto-intake (non-blocking), scan history tracking
- **Receipt OCR Import** — Photograph shopping receipt, offline Vision OCR text recognition, intelligent noise filtering (removes totals/payments/prices), AI parsing for ingredient list, batch recognition support
- **Expiry Dashboard & Local Notifications** — Homepage expiry preview (4 items) + dedicated Expiring tab. Backend scheduling daily at 9:00 (7/3/1 day tiers), permission management, custom reminder times, quiet hours, notification cap 64 with deterministic ID hashing
- **Low Stock Tracking** — Tracks frequently-bought-but-out-of-stock items, homepage card with missing items, one-tap bulk-add to shopping list, powered by frequentItem history model

### Shopping
- **Shopping List** — Add/edit/delete items, category-based grouping with fold/unfold, filter by checkout state (all/pending/checked), checked items auto-bottom with strikethrough, swipe-delete with undo toast
- **Shopping to Inventory Workflow** — Checked items show 'Bulk Intake' CTA, opens IntakeReviewScreen for merge/quantity adjustment, applies only successfully-processed items, supports per-item toggle and undo

### Recipes
- **Recipe Browsing (4-Tab)** — Built-in 851KB howtocook.json (363 recipes, bilingual), 4-tab browsing: Explore/Available-to-cook/Use-expiring/My-custom, cooking-time filters (≤15/≤30 min), dietary exclusion filter, global search (inventory+recipes), ranked by inventory match/expiry priority
- **Recipe Details with Ingredient Matching** — Show recipe details (name/category/difficulty/time/description/steps), highlight inventory match (have/missing items), compute 'have m/total' progress, scale ingredients (½×/1×/2×/3×) affecting display & shopping add, step checklist with completion % & progress bar, one-tap add-missing-to-shopping & add-to-meal-plan(7-day picker)
- **Custom Recipe Creation** — Create/edit/delete custom recipes with name/category/difficulty/time/description, ingredient & step arrays with up/down reordering (chevron buttons), attach recipe photo, custom recipes override bundled by ID
- **Recipe Import from URL** — Import from Lanfan/XiachufangURL, AI auto-extracts structure (name/category/difficulty/steps/ingredients), Share Extension support, recipe URL pre-fill for new-recipe sheet
- **Recipe Import from Photo** — Photo recipe paper/screenshot, offline Vision OCR, AI tidies garbled text into structured recipe, generated recipe has no imageUrl (photo-only), shared structure with URL import
- **Cooking Mode & Step Completion** — Recipe-detail 'Cook' CTA enters CookModeView, steps tap-able to toggle complete/incomplete (Set<Int> state), display done/total + progress bar, auto-trigger deduction flow on completion
- **Deduction on Cooking** — Cooking completion auto-generates 'deduction proposals' (matched by recipe ingredients to inventory), user selects deduct qty/skip out-of-stock, apply deducts inventory count + FoodLog entries (consumed with expiring state)

### MealPlan
- **Meal Planning Calendar** — Week-anchored calendar view, add dishes to 7-day future dates (recipe picker), planned dishes shown with dot indicator, mark done/delete/undo, quick-add from recipe detail (7-day picker), display weekly count/today count/missing ingredients

### Waste
- **Waste Insights & Statistics** — Monthly usage rate (consumed/total), category bar chart showing waste ratio, most-wasted ranking (wasted-count descending), homepage card with dynamic subtitle (consumed count · wasted M or zero-waste emoji) + 'rescued N' badge, delete-time outcome sheet (ate/threw-away) feeding FoodLog

### Settings
- **Settings & Preferences** — Reminder toggle/time/quiet-hours, dietary exclusion editor, AI settings (API key/model choice), appearance/theme, personal profile (name/avatar), JSON backup export/import
- **Profile Card & Personal Info** — Set user name & avatar, display as name card in settings header (post-login), local UserDefaults storage, editable on login/signup

### Sync
- **Household Sharing & Invites** — Create household (auto-adopt local '' scope data), invite members (shareable link + QR code), receive/accept invites, owner can view pending invites & revoke, support deep links (freshpantry://invite/<token>), invite preview shows household name/member count, member management (remove/leave/dissolve with confirmation)
- **Household Data Sync** — Offline-first outbox (queued unsync changes), background periodic sync (BGTaskScheduler 15min), 3-way merge (remote-wins, preserve local-only rows), optimistic concurrent push (auto-retry on version conflict), Realtime subscription auto-pulls changes, anti-data-loss guards (cross-household scope leak prevention), auto-refresh on household switch
- **Offline Mode & Local-Only Data** — Complete offline operation (no backend), all changes local (SwiftData), connectivity recovery auto-syncs, prevents cross-household leakage (LocalUploadScope predicate), local-only no-op when empty household (skip outbox), UI shows offline state & pending-sync count (SyncStatusBanner)

### Auth
- **Supabase Authentication** — Email + 6-digit OTP login (magic-link deprecated to OTP), signup/login support, session management (LocalStorage auto-renew), local-only mode (no credentials), UI state machine (signedOut/codeSent/signedIn), backend optional (enabled when URL present)

### System Integration
- **Siri Shortcuts & App Intents** — Two Siri shortcuts: 'Add to Shopping List' (name param), 'Check Expiring Food' (lists 4-tier summary), Chinese trigger phrases ('用Fresh Pantry加到购物清单'), runs in main app process (no extension)
- **Spotlight Search & Deep Links** — Inventory items & recipes auto-indexed to Core Spotlight, tap results jump to detail view (or new-recipe import pre-fill URL), index auto-rebuilds on household switch, offline-capable
- **Share Extension for Recipe Import** — System share menu supports Lanfan/Xiachufang recipe links, auto-parses URL, opens main app new-recipe sheet pre-filled with URL for AI import, URL validation & normalization, independent signing (com.kunish.freshPantry.ShareExtension)
- **Local Notifications** — Expiry food daily scheduling (9:00 + 7/3/1-day tiers), permission management (request/check/apply), 64-notification cap with syncAll guard, notification tap deep-links (return to inventory/detail), deterministic ID hash (food-based, no duplicates)
- **Background Sync** — iOS Background App Refresh (BGTaskScheduler identifier fresh_pantry.periodic_sync), triggers outbox flush & notification reschedule, 15-min periodic, Info.plist configured with BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes:fetch/processing

### Persistence
- **SwiftData Persistence** — 27 @Models matching Drift schema (Ingredient/Recipe/MealPlanEntry/FoodLogEntry/ShoppingItem), @ModelActor repositories + @Query-driven views, domain Codable value types as JSON truth source, SwiftData stores JSON payload + query columns, offline outbox records (SyncOutboxRecord), ModelContainer per household, full-text search support

### AI Services
- **AI Ingredient Parser** — Accept free text (paste/OCR result) or photo (shopping cart), LLM auto-extracts structured ingredient list (name/qty/unit/category/storage/shelf-life), parse failures return error JSON, photo support via data:image/jpeg;base64
- **AI Recipe Parser** — Extract recipe from page URL or OCR text, returns structured JSON (name/category/difficulty/steps/ingredients/imageUrl), supports messy OCR text cleanup, unified RecipeDraft output format
- **OpenFoodFacts Integration** — Auto-lookup barcode via OpenFoodFacts API for name/nutrition enrichment, result caching prevents duplicate queries, lookup failure gracefully returns barcode only, offline-tolerant

### Features
- **Dietary Preferences & Recipe Filtering** — User edit exclusion keywords in settings ('exclude peanut'), recipe list auto-hides recipes containing exclusions, recipes tab topbar quick-access to editor, 7 local chip presets ('vegetarian'), filter & recommender weighting (exclusion)

### System
- **Design System** — Complete SwiftUI token system (FkColor/FkLayout/FkTypography/FkMotion/FkShadow/FkCategoryPalette), 40+ reusable component library (FkCard/FkChip/FkButton/FkSearchField/FkEmptyState/UrgencyBadge/IngredientRow/RecipeCard), Dynamic Type adaptation, reduce-motion respect, embedded Plus Jakarta + Manrope fonts
- **Diagnostics & Telemetry** — Local debug logs (OSLog) + remote Sentry telemetry, merge conflict detection & reporting, unresolved-row markers
- **Feature Flags** — Conditional compile + runtime feature gates (FeatureFlagStore), debug menu toggles (e.g. disable backend sync), no A/B test framework

### 突出优势
- Pure SwiftUI with native iOS 26 primitives (no cross-platform compromise, Swift 6 strict concurrency)
- Comprehensive AI-powered ingredient & recipe parsing pipeline (Vision OCR + LLM extraction + OpenFoodFacts enrichment) working 100% offline
- Sophisticated offline-first sync architecture with 3-way merge, optimistic locking, and anti-data-loss guards (parity with Flutter backend)
- Complete household sharing with deep-link invite system, QR code generation, and member management (family accounts)
- Unified inventory-to-shopping-to-meals workflow with AI assistance at every step (scope reduction, deduction on cook)
- Rich content capture: barcode scan, receipt OCR, recipe URL import, photo recipe recognition, paste-from-clipboard text parse
- Expiry management as core tenant with smart daily notifications (7/3/1 day tiers, deterministic hashing, quiet hours)
- Design system enforcing visual consistency (40+ reusable components, Dynamic Type, accessibility-first motions)
- True offline operation with automatic sync on reconnect (no feature degradation when offline)
- Siri + Spotlight integration for system-level discoverability without extension complexity

### 代码确认确实没有的能力
- No WidgetKit (home screen widgets, lock screen mini widgets, interactive widgets)
- No Live Activity (recipe cooking timer, sync progress indicator)
- No HealthKit (step count, calories burned, health data integration)
- No WatchOS app or Watch complications
- No push notifications (APNS) - only local notifications; household members cannot be notified of shared changes
- No voice input (Siri voice command beyond shortcut phrases)
- No in-app purchases or premium features (app is completely free)
- No iCloud sync (only Supabase backend, local-only mode without iCloud fallback)
- No custom calendar sharing with iOS Calendar app or export to ICS
- No import/export recipes from standard formats (PDF, Evernote, RSS feeds)
- No computer vision-based meal photo recognition (only ingredient photo recognition)
- No price tracking or cost estimation for shopping/recipes
- No recipe video playback support in-app
- No gamification (achievements, streaks, leaderboards)
- No household member role-based permissions (all members have equal access)
- No recipe comments/social features
- No periodic recipe recommendations from external services (only available-to-cook matching)
