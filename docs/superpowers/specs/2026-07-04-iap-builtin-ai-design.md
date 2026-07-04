# IAP（Pro 买断）+ 内置 AI 设计

日期：2026-07-04
状态：待评审

## 目标

给 FreshPantry 加一次性买断的 Pro 内购，并把 AI 从 BYOK（用户自填 endpoint/key）改为开箱即用的内置服务（DeepSeek），使"买 Pro → AI 直接能用"。

## 商业形态

- **1 个 non-consumable 商品**：`freshpantry.pro`（App Store Connect 上勾选 Family Sharing——家庭成员经 Apple 家庭组自动获得 Pro，不自建跨账号 entitlement 同步）。
- 不做订阅、不做促销/试用期、不做价格实验。

## Pro 门控（4 处，客户端判断）

| 功能 | 拦截点 |
|---|---|
| AI 功能（解析/生成/改写） | 各 AI 入口动作触发前 |
| 家庭共享 Household | 创建/加入家庭入口 |
| 周派餐 MealPlan | 进入周派餐页面 |
| 库存条目上限 | 新增条目且现有条目 ≥ 50 时拦截（已有数据永不删、不锁读） |

未购买时统一弹 `PaywallSheet`（价格取自 StoreKit `Product`，购买 + 恢复购买按钮，文案沿用品牌 plain and kind 语气，遵循 BRAND.md）。

## 客户端架构（StoreKit 2 原生，零第三方依赖）

- 新增 `Services/ProStore.swift`：`@Observable`。启动时读 `Transaction.currentEntitlements` 判定 `isPro`，常驻监听 `Transaction.updates`；暴露 `purchase()`、`restore()`。经 `AppDependencies` 注入。
- 新增 `Features/Settings/PaywallSheet.swift` + Settings 里一行 Pro 状态/购买入口。
- 新增 StoreKit Configuration 文件用于本地测试购买流。

不引入 RevenueCat；不做服务端收据校验（Pro 状态先信客户端 StoreKit 判定，出现被薅证据再加 App Store Server API 校验——升级路径已留：edge function 侧预留按 user 拒绝的能力）。

## 内置 AI

### 模型

**DeepSeek V4 Flash**（模型名 `deepseek-v4-flash`）。

- 注意：旧名 `deepseek-chat` 于 2026-07-24 弃用，直接用新名。
- 定价 $0.14/M 输入、$0.28/M 输出（缓存命中 $0.0028/M）；FreshPantry 单次 AI 调用（约 1K token 量级）成本 ≈ ¥0.002，重度用户月成本 < ¥1，一次性买断可安全覆盖。
- 中文原生强，4 个任务（食材解析、菜谱解析、菜谱生成、菜谱改写）全是中文结构化 JSON 抽取/轻生成，够用。
- 已知局限：DeepSeek API 无视觉模型——将来"拍照识食材"上线时需另接视觉模型（AiClient 的 image 消息路径保留不动）。

### 服务端：Supabase Edge Function `ai-chat`

项目首个 edge function（`supabase/functions/ai-chat/`）。

- 持有 `DEEPSEEK_API_KEY`（Supabase secret），客户端永远拿不到 key。
- 鉴权：验证 Supabase Auth JWT（登录用户才能调）。
- 转发：DeepSeek API 本身是 OpenAI 兼容格式，与 app 现有 `AiClient` 的消息格式一致——函数只做鉴权 + 注入 `model: deepseek-v4-flash` + 原样转发到 `https://api.deepseek.com/chat/completions`，不做格式翻译。
- 限额：每用户每日调用上限（初值 100 次/日，存 Postgres 计数表，超限返回 429 + 中文提示）。ponytail: 简单日计数表，出现真实滥用再上更细的配额/封禁。
- Pro 校验：v1 信任客户端（未购买用户客户端就不会发请求）；计数表按 user_id 记录，留有服务端拒绝的钩子。

### 客户端改动

- `AiClient` 默认指向 edge function URL，Authorization 用 Supabase session token；`AiBaseURL`/`AiSettingsStore` 的 BYOK 自定义 endpoint 保留为高级选项（用户填了自己的 endpoint 就绕过内置服务，此时不受每日限额约束）。
- AI 门控逻辑：`isPro == true` 或已配置 BYOK → 放行。

## 错误处理

- 购买失败/取消：StoreKit 错误就地吐回 PaywallSheet，文案平实（"购买没有完成"），不重试不弹循环。
- edge function 429（限额）：AiError.network 通道透出中文提示"今天的 AI 次数用完了，明天再来"。
- DeepSeek 上游错误：原样映射到现有 `AiError` 体系（notConfigured/network/auth/parse 已齐备）。

## 测试

- `ProStore` 门控逻辑（含 50 条上限判定、BYOK 绕行）单元测试。
- StoreKit Configuration 本地跑通：购买、恢复、Family Sharing 标记。
- edge function：本地 `supabase functions serve` + 一个限额计数的 pgTAP/deno 测试。
- 上线前用 app 真实 prompt 对 `deepseek-v4-flash` 做一轮人工质量抽查（4 个任务各 3 条中文用例）。

## 明确跳过（YAGNI）

- 服务端收据校验、订阅、促销、试用期
- 流式输出、模型可配置、多模型路由
- 视觉模型（拍照识食材未上线）
- RevenueCat / 任何第三方 IAP SDK
