# @fresh-pantry/recipe-pipeline

Flue 菜谱采集清洗管线:多源采集 → LLM 清洗增强 → 去重 → 按 id 合并 → 写回
`apps/ios/FreshPantry/Resources/howtocook.json`(管线工作文件,不进 iOS target)。

## 用法
1. `cp .env.example .env` 填 `ANTHROPIC_API_KEY`(或 `OPENCODE_API_KEY` +
   `RECIPE_MODEL=opencode-go/deepseek-v4-pro` 走 opencode zen 订阅网关)
2. 预览(限量、不写盘):`npm run build:recipes:dry`
3. 全量:`npm run build:recipes`
4. 测试:`npm test`

CLI 直接调用:`flue run build-recipes --target node --payload '{"limit":3,"dryRun":true}'`
(payload 支持 `limit` / `dryRun` / `refreshDescriptions`)

## 架构
- 采集层(`src/sources/`,可插拔 `RecipeSource`)只产出统一 `RawRecipe`。
- 纯 TS 核心(`src/parse` `src/clean` `src/pipeline.ts`)不依赖 flue,可全单测。
- LLM 调用藏在 `RecipeEnricher` 接口后;flue 仅出现在 `src/agents/` `src/clean/flue-enricher.ts` `src/workflows/`。

## 合并保护(对已上线数据)
按 id 合并:既有 `imageUrl`/`remoteVersion`/软删保留,`description` 黏住(除非 `--refreshDescriptions`;
含 markdown 残留的脏描述不黏住,自动用新值自愈),食材用量「只抽不猜」回填。
既有 json 损坏时拒绝覆盖。详见
`docs/superpowers/specs/2026-06-12-recipe-collection-cleaning-pipeline-design.md`。

## 数据质量约定(写盘前闸门强制,违规条目 reject 进 `data/rejects.json`)
- 食材用量是**无损数字结构**,字段按需出现、绝不写空值/空字符串、能省则省:
  - `quantity`:JSON **number**(范围时存下界),无明确数值则省略;
  - `quantityMax`:JSON number,仅范围用量出现(上界,如源「6-15 克」→ `quantity:6, quantityMax:15`);
  - `unit`:计量单位字符串(`"克"`/`"只"`),为空省略(单位本质是文字,不数字化);
  - `note`:模糊量(`"适量"`/`"一小把"`)且无数字时出现的清洗后文本;
  - **无 `amount` 字段**(展示文本由消费端从上述字段派生)。
  iOS `RecipeIngredient` 解码向后兼容旧字符串形态(`"6-15"`→范围、遗留 `amount` 模糊量→`note`),不丢数据。
- 用量「只抽不猜」且**严禁运算**:每个数字必须能在源「计算」段找到(中文数字算依据)。
  公式里的系数不是用量——除式「变量/数」(`张数 / 0.13`)、配比「a:b:c」(`3:2:2`)一律留空 `quantity`;
  乘式每份率(`X * 份数`、`1.5 只/三人`)取带单位的每份量;闸门 `isFormulaCoefficient` 机器拦截系数误当用量。
- `description` 无 markdown 残留;食材不含厨具;`cookingMinutes` 源声明优先于 LLM 估算。
- 封面:管线内先把图收进 `apps/ios/.../RecipeImages/`(`assets/recipes/images/` 路径),
  上游有图的(177 `howtocook_*`)直接 vendor、无图的(187)由「联网补图」补成 `web_*`,
  现 364 条**零缺图**。发布介质是 **Supabase Storage**(见下「封面托管」):`RecipeImages/`
  作为上传源不再随 app 打包,`imageUrl` 改写为 Supabase 公共 URL,iOS 端流式拉取 + 磁盘缓存。

## 联网补图(为缺图菜谱找封面)
上游约半数家常菜本就没图。补图能力把 `imageUrl === null` 的菜谱联网搜一张成品图、
逐张做内容校验、下载到管线资源目录、记录出处。核心在 `src/clean/fetch-images.ts`
(`acquireMissingImages` 下载+magic-byte 验真图+`ImageVerifier` 内容校验+落盘+出处;
`applyAcquiredImages` 纯函数回写),搜索/校验都藏在注入接口后,有单测。

两条产出路径,同一 `ImageCandidate`/`Attribution` 结构:
- **管线内置默认(增量新菜)**:设 `RECIPE_ACQUIRE_IMAGES=1` 跑 `npm run build:recipes`,
  对仍缺图的菜走免 key 的 Openverse(`src/sources/image-search-openverse.ts`,CC 自由版权,
  覆盖有限),vendor 之前补图。默认关闭,不改既有全量跑行为。既有图「既有优先」不覆盖。
- **全量补图(ultracode workflow,本轮 187 条全覆盖)**:`data/acquired/acquire-images.workflow.mjs`
  每道菜一个 agent,全网图片搜索(WebSearch/WebFetch og:image + Wikimedia/Openverse 直链 API)
  → 下载 → `sips` 转 jpg → 多模态视觉校验「确为该菜的洁净成品照」→ 存 `RecipeImages/web_<id>.jpg`
  → 写 `data/acquired/<i>.json`。跑完 `npm run images:apply` 聚合回写 `howtocook.json`
  并合并出处到 `data/image-attributions.json`,再 `npm run gen:seed` 同步 DB。
  补单条/子集:workflow args 传 `{"indices":[…]}` 或 `{"start":N,"end":M}`。
- **出处与许可**:每张图的来源直链/来源页/许可记在 `data/image-attributions.json`(可溯源、可替换)。
  全网图来源混合(Wikimedia CC、下厨房/豆果 og:image、Flickr、菜谱博客、CC0 图库),
  托管他人版权图请按项目自身许可策略评估。

## 封面托管:Supabase Storage(发版后封面全部走 Supabase)
封面不再随 app 打包(省 ~111MB),改托管在 Supabase Storage 的 **`recipe-images` 公共桶**
(匿名只读、仅服务端/迁移可写,见 `supabase/migrations/<v>_recipe_images_bucket.sql`),
iOS 端流式拉取 + **磁盘缓存**(`RemoteImageCache`,见 app 侧),离线可用、冷启动不闪空。

发布/重跑流程(改图后):
1. `SUPABASE_URL=… SUPABASE_KEY=<service 或临时 anon 写的 publishable> npm run images:upload`
   把 `RecipeImages/` 全量幂等上传到 `recipe-images` 桶。对象 key 用 `src/db/storage-key.ts`
   的 `storageKeyFor`(本地中文名 → ASCII 安全 key:可读前缀 + sha1 短哈希;**Storage 不收 CJK key**)。
2. `SUPABASE_URL=… npm run images:rewrite-urls` 把 `howtocook.json` 的 `assets/…` 改写为
   `…/storage/v1/object/public/recipe-images/<key>`(与上传同一 `storageKeyFor`,保证一致)。
3. `npm run gen:seed` 重生成种子(image_url 即 Supabase URL),应用到 DB。
- **桶无写策略**:上传需 service_role key(绕 RLS),或临时给 anon 开 INSERT/UPDATE 策略、
  用 publishable key 上传后**立即删策略锁回**(本轮采用;桶 SELECT 已 public,upsert 冲突检查可用)。
- **一致性自检**(SQL):`recipes.image_url` ↔ `storage.objects` ↔ `howtocook.json` 三方
  key 必须零失配/零孤儿(本轮全 364 条核验通过)。

## 数据库:Supabase `recipes` 目录表
菜谱目录已可迁入 Supabase。howtocook 是**全局共享目录**(人人一样),不走按家庭 RLS——
`public.recipes` 表**匿名只读**、仅服务端/迁移可写;ingredients/steps/tags 存 jsonb(沿用无损数字结构)。

- **生成种子迁移**:`npm run gen:seed` 读 `howtocook.json`,经 `src/db/recipe-sql.ts`(纯函数,
  有单测)生成幂等迁移 `supabase/migrations/<version>_recipes_catalog.sql`(`create table if not exists`
  + `insert … on conflict (id) do update`)。管线重跑→`gen:seed`→重新应用即更新 DB。
- **生成当前目录同步迁移**:`npm run gen:catalog-sync -- supabase/migrations/<version>_recipe_catalog_i18n_sync.sql`
  会写入当前 364 条基础菜谱 + `howtocook.i18n.{en,ja,fr}.json` 的 1092 条 `recipe_i18n` 翻译行。
- **应用**:`supabase db push`(或 `psql -f` 该迁移文件)。迁移自包含 DDL+数据、幂等,重复应用安全。
- **iOS 读取**:DB 为权威源 + 本地缓存,不再 bundle `howtocook*.json`。客户端从 `recipes` 表拉取
  (列别名成 Recipe 的 JSON 键,直接解码)写本地缓存;翻译从 `recipe_i18n` 表按当前语言读取。
  详见 `apps/ios/.../RemoteRecipeCatalog.swift` / `RecipeCatalogCache.swift` / `RecipesStore`。
- **图片**:`recipes.image_url` 存 Supabase Storage 公共 URL(见上「封面托管」),iOS 流式拉取 + 磁盘缓存;
  封面不随 app 打包。

管线核心(采集→清洗→闸门→合并)与输出介质无关:写 json 与生成 DB 种子并联,采集/清洗层零改动。
