# @fresh-pantry/recipe-pipeline

Flue 菜谱采集清洗管线:多源采集 → LLM 清洗增强 → 去重 → 按 id 合并 → 写回
`apps/ios/FreshPantry/Resources/howtocook.json`。

## 用法
1. `cp .env.example .env` 填 `ANTHROPIC_API_KEY`(或 `OPENCODE_API_KEY` +
   `RECIPE_MODEL=opencode-go/deepseek-v4-pro` 走 opencode zen 订阅网关)
2. 预览(限量、不写盘):`npm run build:recipes:dry`
3. 全量:`npm run build:recipes`
4. 测试:`npm test`

CLI 直接调用:`flue run build-recipes --target node --payload '{"limit":3,"dryRun":true}'`
(payload 支持 `limit` / `dryRun` / `refreshDescriptions`)

## 扩充来源
编辑 `data/sources.json`,加 `markdown-repo`(通用中文菜谱 git 仓库)或 `url-batch`
(任意菜谱网页)条目,字段见 `src/sources/registry.ts` 的 `SourceConfig`。首期默认只启用 `howtocook`。

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
- 封面:远程图自动 vendor 进 `apps/ios/.../RecipeImages/`(离线可用、零外链),
  json 写 `assets/recipes/images/` 路径;HowToCook 上游约半数菜谱无图,空值是客观缺口。

## 后续:迁移到数据库
howtocook.json 计划迁入数据库(Supabase)。管线核心(采集→清洗→闸门→合并)与输出介质无关:
写盘集中在 `runPipeline` 末尾的 `atomicWriteJson`,迁移时以同位置替换/并联一个 DB writer
(按 id upsert,沿用 merge 的 `remoteVersion`/软删语义)即可,采集与清洗层零改动。
