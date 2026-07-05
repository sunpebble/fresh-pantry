# IAP Pro 买断 + 内置 AI (DeepSeek) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一次性买断的 Pro 内购（StoreKit 2）+ 内置 AI（DeepSeek V4 Flash，经现有 Cloudflare Worker 代理），买 Pro 即 AI 开箱可用。

**Architecture:** 客户端 `ProStore`（StoreKit 2 entitlement）驱动 4 处门控；AI 传输由 `AiChatAccess` 三态解析（BYOK 优先 → Pro 走内置 worker → 否则弹 Paywall）；worker 在 `apps/api` 现有路由上加 `POST /ai/v1/chat/completions`（Supabase token 校验 + KV 日限额 + 转发 DeepSeek）。

**Tech Stack:** Swift/SwiftUI + StoreKit 2（零第三方依赖）；Cloudflare Worker（TypeScript，零 npm 运行时依赖）+ Workers KV；DeepSeek `deepseek-v4-flash`。

**Spec:** `docs/superpowers/specs/2026-07-04-iap-builtin-ai-design.md`

## Global Constraints

- 不引入任何第三方 IAP SDK（RevenueCat 等）；worker 不引入 npm 运行时依赖。
- 商品 ID：`freshpantry.pro`（non-consumable，Family Sharing 开启）。
- 内置模型 ID：`deepseek-v4-flash`（旧名 `deepseek-chat` 2026-07-24 弃用，禁用）。
- 免费版库存上限：50 条（`FreeTier.inventoryLimit`）；每用户每日 AI 调用上限：100 次。
- 现有中文错误文案（`AiError.message` 等）逐字保留（services invariant #1）；新增用户文案遵循 site 仓库 BRAND.md 的 plain and kind 语气（"还""再"类平实措辞，不惊叹号、不施压）。
- ~~新建 Swift 文件必须注册进 project.pbxproj~~ **勘误（Task 3 实测）**：`FreshPantry.xcodeproj/` 被 gitignore，工程由 xcodegen 从 `apps/ios/project.yml` 生成——新建 Swift 文件**无需注册**（sources 目录型自动收录），改动文件集后跑 `cd apps/ios && xcodegen generate`；禁止手改 pbxproj/xcscheme。
- iOS 测试命令模板（本机无 iPhone 16 Pro，用 17 Pro）：
  `cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:FreshPantryTests/<套件名> 2>&1 | tail -30`
- worker 测试命令：`cd apps/api && npm test`
- 每个任务结束即 commit；仓库根为 `apps/` 上一级（FreshPantry/）。

---

### Task 1: Worker AI 代理路由（apps/api）

**Files:**
- Create: `apps/api/src/ai.ts`
- Create: `apps/api/test/ai.test.ts`
- Create: `apps/api/test/env.d.ts`
- Modify: `apps/api/src/index.ts`（路由接线 + Env 类型）
- Modify: `apps/api/wrangler.jsonc`（KV 绑定 + vars）
- Modify: `apps/api/vitest.config.ts`（测试用 secret 绑定）
- Modify: `apps/api/test/index.test.ts`（现有 5 个 `worker.fetch(request)` 调用补 `env` 实参）

**Interfaces:**
- Consumes: 现有 `worker.fetch` 手写路由。
- Produces: `POST /ai/v1/chat/completions` — 请求头 `Authorization: Bearer <supabase access token>`，请求体为 OpenAI chat-completions JSON；200 时原样返回 DeepSeek 响应；401/429/400 返回 `{"error":{"message":"<中文>"}}`。`src/ai.ts` 导出 `handleAiChat(request: Request, env: Env): Promise<Response>` 与 `interface Env`。

- [ ] **Step 1: wrangler.jsonc 加 KV 绑定与 vars**

`SUPABASE_URL` 的值取自 `apps/ios/FreshPantry/Support/Secrets.plist` 的 supabase URL 字段（若文件缺失或为空，暂停并向用户要值）；`SUPABASE_ANON_KEY` 同理（publishable/anon key）。KV `id` 本任务先填占位（Task 2 部署时创建真实 namespace 后回填），本地测试 miniflare 不校验 id。

```jsonc
{
  "name": "fresh-pantry-api",
  "main": "src/index.ts",
  "compatibility_date": "2026-05-27",
  "routes": [
    {
      "pattern": "api.freshpantry.sunpebblelabs.com",
      "custom_domain": true
    }
  ],
  "kv_namespaces": [
    { "binding": "AI_RATE", "id": "PLACEHOLDER_FILLED_IN_DEPLOY_TASK" }
  ],
  "vars": {
    "SUPABASE_URL": "<Secrets.plist 中的 supabase url，https 原点，无尾斜杠>",
    "SUPABASE_ANON_KEY": "<Secrets.plist 中的 publishable key>"
  }
}
```

- [ ] **Step 2: vitest.config.ts 注入测试用 secret；建 test/env.d.ts**

```ts
// vitest.config.ts
import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: { bindings: { DEEPSEEK_API_KEY: "test-deepseek-key" } },
    }),
  ],
});
```

```ts
// test/env.d.ts
import type { Env } from "../src/ai";

declare module "cloudflare:test" {
  interface ProvidedEnv extends Env {}
}
```

- [ ] **Step 3: 写失败测试 `test/ai.test.ts`**

```ts
import { env, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, describe, expect, it } from "vitest";
import worker from "../src/index";

const AI_PATH = "https://api.freshpantry.sunpebblelabs.com/ai/v1/chat/completions";
const today = new Date().toISOString().slice(0, 10).replaceAll("-", "");

function post(body: unknown, token?: string): Request {
  return new Request(AI_PATH, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
}

function mockUserOk() {
  fetchMock
    .get(env.SUPABASE_URL)
    .intercept({ path: "/auth/v1/user" })
    .reply(200, { id: "user-1" });
}

beforeAll(() => {
  fetchMock.activate();
  fetchMock.disableNetConnect();
});
afterEach(() => fetchMock.assertNoPendingInterceptors());

describe("POST /ai/v1/chat/completions", () => {
  it("缺 token 返回 401", async () => {
    const res = await worker.fetch(post({ messages: [] }), env);
    expect(res.status).toBe(401);
  });

  it("token 校验失败返回 401", async () => {
    fetchMock.get(env.SUPABASE_URL).intercept({ path: "/auth/v1/user" }).reply(401, {});
    const res = await worker.fetch(post({ messages: [] }, "bad-token"), env);
    expect(res.status).toBe(401);
  });

  it("转发 DeepSeek 并强制服务端模型", async () => {
    mockUserOk();
    let sentBody = "";
    fetchMock
      .get("https://api.deepseek.com")
      .intercept({ path: "/chat/completions", method: "POST" })
      .reply(200, (req) => {
        sentBody = String(req.body);
        return JSON.stringify({ choices: [{ message: { content: "ok" } }] });
      });
    const res = await worker.fetch(
      post({ model: "gpt-4", messages: [{ role: "user", content: "hi" }] }, "good-token"),
      env,
    );
    expect(res.status).toBe(200);
    const json = (await res.json()) as { choices: { message: { content: string } }[] };
    expect(json.choices[0].message.content).toBe("ok");
    expect(JSON.parse(sentBody).model).toBe("deepseek-v4-flash");
  });

  it("超过日限额返回 429 + 中文提示", async () => {
    await env.AI_RATE.put(`ai:user-1:${today}`, "100");
    mockUserOk();
    const res = await worker.fetch(post({ messages: [] }, "good-token"), env);
    expect(res.status).toBe(429);
    const json = (await res.json()) as { error: { message: string } };
    expect(json.error.message).toContain("今天的 AI 次数用完了");
  });

  it("非 POST 返回 405", async () => {
    const res = await worker.fetch(new Request(AI_PATH, { method: "GET" }), env);
    expect(res.status).toBe(405);
  });
});
```

注：`fetchMock`（undici MockAgent）的 `.reply` 回调实参形状以 `@cloudflare/vitest-pool-workers` 实际版本为准，若 `req.body` 取不到就改用 `.intercept({ ..., body: (b) => { sentBody = b; return true; } })` 捕获——目标不变：断言转发体的 `model` 被覆写。

- [ ] **Step 4: 跑测试确认失败**

Run: `cd apps/api && npm test 2>&1 | tail -20`
Expected: FAIL —— `Cannot find module '../src/ai'` 或 404 断言失败。

- [ ] **Step 5: 实现 `src/ai.ts`**

```ts
const DAY_LIMIT = 100;
const MODEL = "deepseek-v4-flash";
const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";

export interface Env {
  AI_RATE: KVNamespace;
  DEEPSEEK_API_KEY: string;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
}

function aiError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function handleAiChat(request: Request, env: Env): Promise<Response> {
  if (request.method.toUpperCase() !== "POST") {
    return new Response("Method Not Allowed", { status: 405, headers: { Allow: "POST" } });
  }

  const auth = request.headers.get("authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) return aiError(401, "缺少登录凭证");

  // 用 Supabase 侧校验 token：免去 JWKS/HS256 双路径的密钥管理，AI 调用本身秒级，
  // 多一次子请求可接受。ponytail: 若这次往返成为瓶颈，再换本地 JWT 校验。
  const userRes = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${token}` },
  });
  if (!userRes.ok) return aiError(401, "登录已过期，请重新登录");
  const user = (await userRes.json()) as { id?: string };
  if (!user.id) return aiError(401, "登录已过期，请重新登录");

  // ponytail: KV 日计数最终一致，突发并发可能略超限——可接受；真滥用再换 Durable Object。
  const day = new Date().toISOString().slice(0, 10).replaceAll("-", "");
  const key = `ai:${user.id}:${day}`;
  const used = Number((await env.AI_RATE.get(key)) ?? "0");
  if (used >= DAY_LIMIT) return aiError(429, "今天的 AI 次数用完了，明天再来");
  await env.AI_RATE.put(key, String(used + 1), { expirationTtl: 172800 });

  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return aiError(400, "请求不是合法 JSON");
  }
  body.model = MODEL; // 服务端固定模型，不信任客户端

  const upstream = await fetch(DEEPSEEK_URL, {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.DEEPSEEK_API_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
```

- [ ] **Step 6: `src/index.ts` 接线**

删掉 `type Env = Record<string, never>;`，改为从 ai.ts 导入；`fetch` 签名的 `_env?: Env` 改为 `env: Env`；在 `/health` 分支之前加：

```ts
import { handleAiChat, type Env } from "./ai";

// fetch 内、url 解析之后：
if (url.pathname === "/ai/v1/chat/completions") {
  return handleAiChat(request, env);
}
```

同时把 `test/index.test.ts` 里 5 处 `worker.fetch(new Request(...))` 改为 `worker.fetch(new Request(...), env)`（文件头加 `import { env } from "cloudflare:test";`）。

- [ ] **Step 7: 跑全部 worker 测试确认通过**

Run: `cd apps/api && npm test 2>&1 | tail -15`
Expected: 全部 PASS（含原有 health/invite 用例）。

- [ ] **Step 8: Commit**

```bash
git add apps/api
git commit -m "feat(api): /ai/v1/chat/completions DeepSeek 代理(鉴权+日限额)"
```

---

### Task 2: Worker 部署与线上验证

**Files:**
- Modify: `apps/api/wrangler.jsonc`（回填真实 KV id）

**Interfaces:**
- Consumes: Task 1 的路由。
- Produces: 线上 `https://api.freshpantry.sunpebblelabs.com/ai/v1/chat/completions` 可用。

- [ ] **Step 1: 创建 KV namespace 并回填 id**

Run: `cd apps/api && npx wrangler kv namespace create AI_RATE`
Expected: 输出 `id = "<32位hex>"`；把它写进 wrangler.jsonc 的 `kv_namespaces[0].id`。
（若 wrangler 未登录：`npx wrangler login`，需要用户浏览器授权——此时暂停并请用户操作。）

- [ ] **Step 2: 设置 DeepSeek secret**

Run: `cd apps/api && npx wrangler secret put DEEPSEEK_API_KEY`
key 值需要用户提供（DeepSeek 开放平台 https://platform.deepseek.com 创建）——暂停向用户索取，不要造假值。

- [ ] **Step 3: 部署并验证**

```bash
cd apps/api && npm run deploy
curl -s -o /dev/null -w '%{http_code}' https://api.freshpantry.sunpebblelabs.com/health   # 期望 200
curl -s -X POST https://api.freshpantry.sunpebblelabs.com/ai/v1/chat/completions -d '{}'  # 期望 {"error":{"message":"缺少登录凭证"}} 且状态 401
```

- [ ] **Step 4: Commit**

```bash
git add apps/api/wrangler.jsonc
git commit -m "chore(api): AI_RATE KV namespace 绑定"
```

---

### Task 3: FreeTier + ProStore + StoreKit 配置

**Files:**
- Create: `apps/ios/FreshPantry/Domain/Models/FreeTier.swift`
- Create: `apps/ios/FreshPantry/Services/ProStore.swift`
- Create: `apps/ios/Products.storekit`
- Create: `apps/ios/FreshPantryTests/FreeTierTests.swift`
- Modify: `apps/ios/FreshPantry/App/AppDependencies.swift`（注入 proStore）
- Modify: `apps/ios/FreshPantry.xcodeproj/xcshareddata/xcschemes/FreshPantry.xcscheme`（StoreKit 配置引用）
- Modify: `apps/ios/FreshPantry.xcodeproj/project.pbxproj`（注册全部新文件）

**Interfaces:**
- Produces:
  - `FreeTier.inventoryLimit: Int`（= 50）
  - `FreeTier.inventoryLimitReached(isPro: Bool, currentCount: Int) -> Bool`
  - `ProStore`（`@Observable @MainActor`）：`isPro: Bool`、`product: Product?`、`purchaseError: String?`、`func start() async`、`func purchase() async`、`func restore() async`；`init(isProForPreview: Bool? = nil)`（预览/UI 测试注入用，传值即锁死 isPro 不再刷新）
  - `AppDependencies.proStore: ProStore`

- [ ] **Step 1: 写失败测试 `FreshPantryTests/FreeTierTests.swift`**

```swift
import Testing
@testable import FreshPantry

struct FreeTierTests {
    @Test func proNeverBlocked() {
        #expect(FreeTier.inventoryLimitReached(isPro: true, currentCount: 999) == false)
    }

    @Test func freeUnderLimitAllowed() {
        #expect(FreeTier.inventoryLimitReached(isPro: false, currentCount: 49) == false)
    }

    @Test func freeAtLimitBlocked() {
        #expect(FreeTier.inventoryLimitReached(isPro: false, currentCount: 50) == true)
        #expect(FreeTier.inventoryLimitReached(isPro: false, currentCount: 51) == true)
    }
}
```

（若现有测试用 XCTest 而非 Swift Testing，先看任一现有测试文件，保持同一框架写法。）

- [ ] **Step 2: 跑测试确认编译失败**

Run: `cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:FreshPantryTests/FreeTierTests 2>&1 | tail -20`
Expected: FAIL —— `cannot find 'FreeTier' in scope`。

- [ ] **Step 3: 实现 `Domain/Models/FreeTier.swift`**

```swift
import Foundation

/// 免费版配额（Pro 门控里唯一的纯逻辑，集中在这便于测试）。
enum FreeTier {
    /// 免费版库存条目上限。已有数据永不删、不锁读——只拦"新增"。
    static let inventoryLimit = 50

    static func inventoryLimitReached(isPro: Bool, currentCount: Int) -> Bool {
        !isPro && currentCount >= inventoryLimit
    }
}
```

- [ ] **Step 4: 实现 `Services/ProStore.swift`**

```swift
import Foundation
import StoreKit

/// Pro 买断状态（StoreKit 2）。启动时读一次 entitlement，常驻监听交易更新；
/// 购买/恢复的错误以中文短句暴露给 PaywallSheet 就地展示。
@Observable
@MainActor
final class ProStore {
    static let productID = "freshpantry.pro"

    private(set) var isPro = false
    private(set) var product: Product?
    private(set) var purchaseError: String?
    /// 预览/UI 测试注入：非 nil 时锁死 isPro，start() 不再改写。
    private let isProOverride: Bool?
    private var updatesTask: Task<Void, Never>?

    init(isProForPreview: Bool? = nil) {
        self.isProOverride = isProForPreview
        if let isProForPreview { self.isPro = isProForPreview }
    }

    /// App 根 .task 调一次：刷 entitlement、拉商品、挂交易监听。
    func start() async {
        guard isProOverride == nil else { return }
        await refreshEntitlement()
        product = try? await Product.products(for: [Self.productID]).first
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let tx) = update {
                    await tx.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }

    func refreshEntitlement() async {
        guard isProOverride == nil else { return }
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let tx) = entitlement,
               tx.productID == Self.productID, tx.revocationDate == nil {
                isPro = true
                return
            }
        }
        isPro = false
    }

    func purchase() async {
        purchaseError = nil
        guard let product else {
            purchaseError = "商品信息还没加载好，稍后再试"
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    await refreshEntitlement()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "购买没有完成：\(error.localizedDescription)"
        }
    }

    func restore() async {
        purchaseError = nil
        try? await AppStore.sync()
        await refreshEntitlement()
        if !isPro { purchaseError = "没有找到可恢复的购买" }
    }
}
```

- [ ] **Step 5: AppDependencies 注入**

在 `AppDependencies` 属性区加 `let proStore: ProStore`，init 中（`appearanceStore` 那一段旁）加 `self.proStore = ProStore()`。在 `FreshPantryApp`（或 RootView 的现有启动 `.task`，跟随现有启动挂载点）追加 `await dependencies.proStore.start()`。

- [ ] **Step 6: 建 `apps/ios/Products.storekit`**

```json
{
  "identifier" : "F3A1C2D4",
  "nonRenewingSubscriptions" : [],
  "products" : [
    {
      "displayPrice" : "30.00",
      "familyShareable" : true,
      "internalID" : "F3A1C2D5",
      "localizations" : [
        {
          "description" : "解锁 AI 助手、家庭共享、周派餐与不限量库存",
          "displayName" : "Fresh Pantry Pro",
          "locale" : "zh_CN"
        }
      ],
      "productID" : "freshpantry.pro",
      "referenceName" : "Pro",
      "type" : "NonConsumable"
    }
  ],
  "settings" : {},
  "subscriptionGroups" : [],
  "version" : { "major" : 4, "minor" : 0 }
}
```

在 `FreshPantry.xcscheme` 的 `<LaunchAction ...>` 内（`<BuildableProductRunnable>` 之前）加：

```xml
<StoreKitConfigurationFileReference
   identifier = "../../../Products.storekit">
</StoreKitConfigurationFileReference>
```

（identifier 是相对 .xcscheme 文件的路径；xcshareddata/xcschemes/ 上三级即 apps/ios/。同时把 Products.storekit 注册进 pbxproj 的 PBXFileReference + group，不加入任何 target 的 build phase。）

- [ ] **Step 7: 注册新 Swift 文件并跑测试**

FreeTier.swift、ProStore.swift 注册进 FreshPantry target；FreeTierTests.swift 注册进 FreshPantryTests target。

Run: `cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:FreshPantryTests/FreeTierTests 2>&1 | tail -15`
Expected: PASS（3 个用例）。

- [ ] **Step 8: Commit**

```bash
git add apps/ios
git commit -m "feat(ios): ProStore(StoreKit 2 买断) + FreeTier 配额 + StoreKit 本地配置"
```

---

### Task 4: AiChatAccess 传输解析 + 429 文案透传

**Files:**
- Create: `apps/ios/FreshPantry/Services/AiChatAccess.swift`
- Create: `apps/ios/FreshPantryTests/AiChatAccessTests.swift`
- Modify: `apps/ios/FreshPantry/Services/AiClient.swift`（mapStatus 429 分支）
- Modify: `apps/ios/FreshPantry/App/AppDependencies.swift`（暴露 builtInAiChatFn）
- Modify: `apps/ios/FreshPantry.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `AiSettings`（`isConfigured`）、`SupabaseClientProvider.client`、`AiClient.chat`、`AiChatFn`、`BackendConfig.defaultAPIBaseURL`。
- Produces:
  - `enum AiAvailability: Equatable { case byok(AiSettings); case builtIn; case needsPro }`
  - `AiChatAccess.builtInModel: String`（= "deepseek-v4-flash"）
  - `AiChatAccess.resolve(byok: AiSettings, isPro: Bool) -> AiAvailability`
  - `AiChatAccess.builtInSettings(apiBaseURL: URL, accessToken: String) -> AiSettings`
  - `AiChatAccess.builtInChatFn(clientProvider: SupabaseClientProvider, apiBaseURL: URL, responseFormat: [String: JSONValue]?) -> AiChatFn`
  - `AppDependencies.builtInAiChatFn(responseFormat: [String: JSONValue]?) -> AiChatFn?`（本地模式 nil）

- [ ] **Step 1: 写失败测试 `AiChatAccessTests.swift`**

```swift
import Foundation
import Testing
@testable import FreshPantry

struct AiChatAccessTests {
    @Test func byokWinsRegardlessOfPro() {
        let byok = AiSettings(baseUrl: "https://my.llm/v1", apiKey: "k", model: "m")
        #expect(AiChatAccess.resolve(byok: byok, isPro: false) == .byok(byok))
        #expect(AiChatAccess.resolve(byok: byok, isPro: true) == .byok(byok))
    }

    @Test func proWithoutByokUsesBuiltIn() {
        #expect(AiChatAccess.resolve(byok: .empty, isPro: true) == .builtIn)
    }

    @Test func freeWithoutByokNeedsPro() {
        #expect(AiChatAccess.resolve(byok: .empty, isPro: false) == .needsPro)
    }

    @Test func builtInSettingsPointAtWorker() {
        let settings = AiChatAccess.builtInSettings(
            apiBaseURL: URL(string: "https://api.freshpantry.sunpebblelabs.com")!,
            accessToken: "tok"
        )
        // normalizeAiBaseUrl 会补 /v1 → 最终打到 /ai/v1/chat/completions
        #expect(settings.baseUrl == "https://api.freshpantry.sunpebblelabs.com/ai")
        #expect(settings.apiKey == "tok")
        #expect(settings.model == "deepseek-v4-flash")
        #expect(settings.isConfigured)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:FreshPantryTests/AiChatAccessTests 2>&1 | tail -20`
Expected: FAIL —— `cannot find 'AiChatAccess' in scope`。

- [ ] **Step 3: 实现 `Services/AiChatAccess.swift`**

```swift
import Foundation

/// 一次 AI 调用可用的传输通道。BYOK（用户自填 endpoint）优先且不受 Pro/限额约束；
/// 其次 Pro 用户走内置 worker 代理；否则引导购买。
enum AiAvailability: Equatable {
    case byok(AiSettings)
    case builtIn
    case needsPro
}

/// 内置 AI 传输的解析与构造。纯函数 + 一个闭包工厂，保持可测。
enum AiChatAccess {
    static let builtInModel = "deepseek-v4-flash"

    static func resolve(byok: AiSettings, isPro: Bool) -> AiAvailability {
        if byok.isConfigured { return .byok(byok) }
        return isPro ? .builtIn : .needsPro
    }

    /// worker 基址 + Supabase access token → 可直接喂给 AiClient 的 AiSettings。
    /// normalizeAiBaseUrl 会给不含 /v1 的 base 补 /v1，所以 worker 路由是
    /// /ai/v1/chat/completions —— 这里只到 /ai。
    static func builtInSettings(apiBaseURL: URL, accessToken: String) -> AiSettings {
        AiSettings(
            baseUrl: apiBaseURL.appendingPathComponent("ai").absoluteString,
            apiKey: accessToken,
            model: builtInModel,
            timeout: 120
        )
    }

    /// 内置通道的 chat 闭包。每次调用现取 session（token 会自动刷新，不能缓存）。
    static func builtInChatFn(
        clientProvider: SupabaseClientProvider,
        apiBaseURL: URL,
        responseFormat: [String: JSONValue]? = nil
    ) -> AiChatFn {
        { messages in
            guard let client = clientProvider.client else {
                throw AiError.notConfigured
            }
            guard let session = try? await client.auth.session else {
                throw AiError.auth("请先登录后再使用 AI 功能")
            }
            let settings = builtInSettings(apiBaseURL: apiBaseURL, accessToken: session.accessToken)
            return try await AiClient.chat(
                settings: settings,
                messages: messages,
                responseFormat: responseFormat
            )
        }
    }
}
```

（若编译器对闭包内捕获 `clientProvider` 报 Sendable 警告/错误，把 `client` 在工厂函数体内先解出再捕获：`let client = clientProvider.client`。）

- [ ] **Step 4: AiClient.mapStatus 429 透传服务端文案**

`mapStatus` 的 `case 429` 改为（其余分支逐字不动）：

```swift
case 429:
    // 内置 worker 的日限额会带中文 error.message（如"今天的 AI 次数用完了，明天再来"），
    // 优先透传；无 body 时保留原文案。
    if let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
       let err = root["error"] as? [String: Any],
       let message = err["message"] as? String, !message.isEmpty {
        throw AiError.network(message)
    }
    throw AiError.network("服务繁忙 (429)")
```

`mapStatus` 现签名 `(_ status: Int, body: Data)` 已带 body，无需改签名。

- [ ] **Step 5: AppDependencies 暴露内置 chatFn 工厂**

`AppDependencies` 加存储属性与方法（init 里 `clientProvider` 就绪后即可赋值）：

```swift
/// 内置 AI 的 worker 基址（= 现有 api 域名）。
private let apiBaseURL: URL
// init 中、clientProvider 赋值之后：
self.apiBaseURL = config?.backend.apiBaseURL ?? BackendConfig.defaultAPIBaseURL

/// 内置 AI chat 闭包工厂；本地模式（无 Supabase 后端）返回 nil。
func builtInAiChatFn(responseFormat: [String: JSONValue]? = nil) -> AiChatFn? {
    guard clientProvider.client != nil else { return nil }
    return AiChatAccess.builtInChatFn(
        clientProvider: clientProvider,
        apiBaseURL: apiBaseURL,
        responseFormat: responseFormat
    )
}
```

- [ ] **Step 6: 注册文件、跑测试**

Run: `cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:FreshPantryTests/AiChatAccessTests 2>&1 | tail -15`
Expected: PASS（4 个用例）。

- [ ] **Step 7: Commit**

```bash
git add apps/ios
git commit -m "feat(ios): AiChatAccess 三态传输解析 + 内置 worker chatFn + 429 文案透传"
```

---

### Task 5: PaywallSheet + ProLockedView + Settings 入口

**Files:**
- Create: `apps/ios/FreshPantry/Features/Settings/PaywallSheet.swift`
- Modify: `apps/ios/FreshPantry/Features/Settings/SettingsView.swift`（Pro 行）
- Modify: `apps/ios/FreshPantry.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `ProStore`（isPro/product/purchaseError/purchase/restore）、设计系统色 `Color.fkPrimary` 等（用法参照 AiSettingsView）。
- Produces:
  - `struct PaywallSheet: View`（`init(proStore: ProStore)`）
  - `struct ProLockedView: View`（`init(featureName: String, proStore: ProStore)`——整页锁定占位，内嵌打开 PaywallSheet 的按钮；MealPlan 门控用）

- [ ] **Step 1: 实现 `PaywallSheet.swift`**

先读 `AiSettingsView.swift` 对齐排版习惯（分组、字体、fk 色板用法），再写。文案遵循 BRAND.md（平实、不施压；「解锁」而非「立即抢购」）：

```swift
import SwiftUI
import StoreKit

/// Pro 购买页。所有 Pro 门控统一弹这一张 sheet。
struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    let proStore: ProStore
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    featureRow("sparkles", "AI 助手", "粘贴文本一键入库、清冰箱生成菜谱")
                    featureRow("person.2", "家庭共享", "全家共用一份库存与购物清单")
                    featureRow("calendar", "周派餐", "按周安排每天做什么菜")
                    featureRow("archivebox", "不限量库存", "免费版可记录 \(FreeTier.inventoryLimit) 条")
                } header: {
                    Text("Fresh Pantry Pro")
                }

                Section {
                    Button {
                        Task {
                            isPurchasing = true
                            await proStore.purchase()
                            isPurchasing = false
                            if proStore.isPro { dismiss() }
                        }
                    } label: {
                        if proStore.isPro {
                            Text("已解锁")
                        } else if let product = proStore.product {
                            Text("一次买断 · \(product.displayPrice)")
                        } else {
                            Text("加载中…")
                        }
                    }
                    .disabled(proStore.isPro || proStore.product == nil || isPurchasing)

                    Button("恢复购买") {
                        Task { await proStore.restore() }
                    }
                    .disabled(isPurchasing)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("一次购买，长期使用，支持家庭共享。")
                        if let error = proStore.purchaseError {
                            Text(error).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("升级 Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.fkPrimary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// 整页锁定占位（MealPlan 等整页门控用）。
struct ProLockedView: View {
    let featureName: String
    let proStore: ProStore
    @State private var showPaywall = false

    var body: some View {
        ContentUnavailableView {
            Label(featureName, systemImage: "lock")
        } description: {
            Text("\(featureName)是 Pro 功能。")
        } actions: {
            Button("了解 Pro") { showPaywall = true }
                .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(proStore: proStore)
        }
    }
}
```

（写完后与 AiSettingsView 的实际排版比对，用色/间距不一致处向现有风格看齐——现有风格优先于本代码块。）

- [ ] **Step 2: SettingsView 加 Pro 行**

在 AI 助手行（`aiStore.isConfigured ? "已配置 ..." : "配置模型与连接"` 附近）上方加一行，复用该文件现有的行构造 helper：标题「Fresh Pantry Pro」，副标题 `proStore.isPro ? "已解锁" : "解锁 AI、家庭共享与周派餐"`，点击弹 `PaywallSheet`（`@State showPaywall` + `.sheet`）。`proStore` 取自该 View 现有的依赖注入方式（`@Environment(AppDependencies.self)` 或构造参数，与文件现状一致）。

- [ ] **Step 3: 编译验证 + Commit**

Run: `cd apps/ios && xcodebuild build -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

```bash
git add apps/ios
git commit -m "feat(ios): PaywallSheet/ProLockedView + Settings Pro 入口"
```

---

### Task 6: 5 个 AI 调用点接入三态解析

**Files:**
- Modify: `apps/ios/FreshPantry/Features/Dashboard/ExpiringView.swift`
- Modify: `apps/ios/FreshPantry/Features/Inventory/PasteImportStore.swift` 及其构造方（`PasteImportView.swift`）
- Modify: `apps/ios/FreshPantry/Features/Recipes/CustomRecipeFormView.swift`
- Modify: `apps/ios/FreshPantry/Features/Recipes/RecipeDetailView.swift`
- Modify: `apps/ios/FreshPantry/Features/Recipes/RecipePhotoImportView.swift`

**Interfaces:**
- Consumes: `AiChatAccess.resolve`、`AppDependencies.builtInAiChatFn(responseFormat:)`、`AppDependencies.proStore`、`PaywallSheet`。
- Produces: 无新公共接口——行为变更：BYOK 未配置时，Pro 用户 AI 直接可用；非 Pro 用户触发 AI 动作弹 PaywallSheet。

- [ ] **Step 1: 逐文件改造（以 ExpiringView 为准样板）**

`ExpiringView.generate()` 现状：

```swift
let settings = aiSettingsStore.settings
guard settings.isConfigured else {
    generateError = AiError.notConfigured.message + "，请在 设置 › AI 助手 配置后再试。"
    return
}
// … 后面构造 chatFn: { try await AiClient.chat(settings: settings, messages: $0, responseFormat: ["type": .string("json_object")]) }
```

改为：

```swift
let chatFn: AiChatFn
switch AiChatAccess.resolve(byok: aiSettingsStore.settings, isPro: dependencies.proStore.isPro) {
case .byok(let settings):
    chatFn = { messages in
        try await AiClient.chat(
            settings: settings,
            messages: messages,
            responseFormat: ["type": .string("json_object")]
        )
    }
case .builtIn:
    guard let builtIn = dependencies.builtInAiChatFn(responseFormat: ["type": .string("json_object")]) else {
        generateError = AiError.notConfigured.message
        return
    }
    chatFn = builtIn
case .needsPro:
    showPaywall = true
    return
}
```

并在该 View 加 `@State private var showPaywall = false` + `.sheet(isPresented: $showPaywall) { PaywallSheet(proStore: dependencies.proStore) }`。`dependencies` 用该文件现有的注入方式；原 `guard settings.isConfigured` 分支删除。后续 `AiRecipeGenerator.fromIngredients(...)` 尾随闭包改为直接传 `chatFn:`。

- [ ] **Step 2: 其余 4 个文件套用同一模式**

每个文件先读再改，规则一致：
1. 找到 `settings.isConfigured` guard（或等价的"未配置"分支）与 `AiClient.chat(settings:)` 闭包；
2. 换成上面的三态 switch（`responseFormat` 保持该调用点原值，未传则传 `nil`）；
3. `.needsPro` → 置本 View 的 `showPaywall`，加 `.sheet`；
4. `PasteImportStore` 是 store 而非 view：其 `init(aiSettings:...)` 的默认 chatFn 保持不动，改它的构造方（PasteImportView 等）在构造前做三态解析、把解析出的 `chatFn` 传入现有的 `chatFn:` 注入参数；`.needsPro` 时不进入导入流程、弹 paywall。

- [ ] **Step 3: 全量单测 + 编译**

Run: `cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:FreshPantryTests 2>&1 | tail -15`
Expected: 全部 PASS（既有 AI 相关测试注入 fake chatFn，不受影响）。

- [ ] **Step 4: Commit**

```bash
git add apps/ios
git commit -m "feat(ios): AI 调用点接入 Pro/内置/BYOK 三态门控"
```

---

### Task 7: Household 与 MealPlan 门控

**Files:**
- Modify: `apps/ios/FreshPantry/Features/Household/HouseholdView.swift`
- Modify: `apps/ios/FreshPantry/Features/MealPlan/MealPlanView.swift`

**Interfaces:**
- Consumes: `AppDependencies.proStore`、`PaywallSheet`、`ProLockedView`。
- Produces: 行为变更——非 Pro 用户：创建/加入家庭前弹 paywall；MealPlan 页面整页显示 `ProLockedView`。

- [ ] **Step 1: HouseholdView 创建/加入动作前置检查**

「创建」（`primaryButton(title: "创建", ...)`）与「接受邀请」（`primaryButton(title: "接受邀请", ...)`）两个 action 开头加：

```swift
guard dependencies.proStore.isPro else {
    showPaywall = true
    return
}
```

加 `@State private var showPaywall = false` 与 `.sheet(isPresented: $showPaywall) { PaywallSheet(proStore: dependencies.proStore) }`。已在家庭中的成员操作（离开/移除/解散）不拦——只拦"进入"家庭共享的两个入口。

- [ ] **Step 2: MealPlanView 整页门控**

`MealPlanView.body` 顶层包一层（门控在页面自身，深链/所有入口一并覆盖）：

```swift
if !dependencies.proStore.isPro {
    ProLockedView(featureName: "周派餐", proStore: dependencies.proStore)
} else {
    // 原 body 内容
}
```

- [ ] **Step 3: 编译 + Commit**

Run: `cd apps/ios && xcodebuild build -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

```bash
git add apps/ios
git commit -m "feat(ios): 家庭共享与周派餐 Pro 门控"
```

---

### Task 8: 库存 50 条上限（IntakeController 咽喉门控）

**Files:**
- Modify: `apps/ios/FreshPantry/Features/Inventory/IntakeController.swift`
- Modify: `apps/ios/FreshPantry/Features/Inventory/AddIngredientView.swift`
- Modify: `apps/ios/FreshPantry/Features/Inventory/IntakeReviewStore.swift` + `IntakeReviewView.swift`
- Modify: `apps/ios/FreshPantry/Features/Recipes/LeftoverIntakeSheet.swift`
- Create: `apps/ios/FreshPantryTests/IntakeControllerLimitTests.swift`
- Modify: 各 `IntakeController(` 构造点（grep 定位）传 `isPro:` 闭包
- Modify: `apps/ios/FreshPantry.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `FreeTier.inventoryLimitReached`、`ProStore.isPro`。
- Produces:
  - `IntakeController.init(repository:householdID:syncWriter:isPro:)` —— 新增 `isPro: (() -> Bool)? = nil`（nil = 不门控，既有测试/预览零改动）
  - `ApplyOutcome.limitReached: Bool`（默认 `false`）+ `static let limitBlocked: ApplyOutcome`

- [ ] **Step 1: 写失败测试 `IntakeControllerLimitTests.swift`**

先读现有的 IntakeController 相关测试（grep `IntakeController` in FreshPantryTests）借用其 repository/fixture 搭建方式，然后：

```swift
import Testing
@testable import FreshPantry

// 沿用现有 IntakeController 测试的内存 ModelContainer/repository 构造方式。
@MainActor
struct IntakeControllerLimitTests {
    @Test func freeUserAtLimitBlocked() async throws {
        // 1. 造 50 条既有库存（fixture 方式抄现有测试）
        // 2. IntakeController(repository:..., householdID: "", isPro: { false })
        // 3. apply 一条"新增"proposal
        // 4. 断言:
        //    outcome.limitReached == true
        //    outcome.persisted == false
        //    repository 里仍是 50 条
    }

    @Test func proUserAtLimitAllowed() async throws {
        // 同上但 isPro: { true } → limitReached == false, persisted == true, 51 条
    }

    @Test func deductionNeverBlocked() async throws {
        // 50 条 + isPro: { false }，apply 一条纯扣减 proposal（不新增行）
        // → limitReached == false（门控只看新增行）
    }
}
```

（注释里的搭建步骤必须落成真代码——fixture 细节以现有测试为准，这里不虚构 repository API。）

- [ ] **Step 2: 跑测试确认失败**

Run: `cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:FreshPantryTests/IntakeControllerLimitTests 2>&1 | tail -20`
Expected: FAIL —— `extra argument 'isPro'` / `no member 'limitReached'`。

- [ ] **Step 3: 实现门控**

`ApplyOutcome` 加字段与静态值：

```swift
var limitReached: Bool = false

/// 免费版库存上限拦截：什么都没写入。
static let limitBlocked = ApplyOutcome(
    appliedIds: [], addedItems: [], persisted: false, limitReached: true
)
```

`IntakeController` 加 `private let isPro: (() -> Bool)?`，init 加 `isPro: (() -> Bool)? = nil`。`apply` 中计算出 `addedItems` 之后、`repository.saveItems` 之前加：

```swift
// 免费版库存上限：只拦"会新增行"的 apply（纯扣减/合并不受影响）。
// 所有入库路径(手动/粘贴导入/购物/剩菜)都汇到这里,门控一处生效。
if let isPro, !addedItems.isEmpty,
   FreeTier.inventoryLimitReached(isPro: isPro(), currentCount: inventory.count) {
    return .limitBlocked
}
```

- [ ] **Step 4: 构造点传 isPro + 界面提示**

1. grep `IntakeController(` 的全部构造点，给每处补 `isPro: { dependencies.proStore.isPro }`（`dependencies` 用各文件现有注入方式；确实拿不到 deps 的测试/预览构造点保持 nil）。
2. `AddIngredientView`（`controller.apply([proposal])` 处）与 `IntakeReviewView`/`IntakeReviewStore`（`store.apply()` 链路）：outcome `limitReached == true` 时弹 `PaywallSheet`（各自 `@State showPaywall` + `.sheet`），提示文案「免费版最多记录 \(FreeTier.inventoryLimit) 条库存」。
3. `LeftoverIntakeSheet`：`limitReached` 时就地显示同句文案（该 sheet 空间小，不再叠 paywall sheet——ponytail: 罕见路径给文字提示即可，用户可去设置页升级）。

- [ ] **Step 5: 跑本套件 + 全量单测**

Run: `cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:FreshPantryTests 2>&1 | tail -15`
Expected: 全部 PASS（isPro 默认 nil，既有 IntakeController 测试不受影响）。

- [ ] **Step 6: Commit**

```bash
git add apps/ios
git commit -m "feat(ios): 免费版库存 50 条上限(IntakeController 单点门控)"
```

---

### Task 9: 全量验证

**Files:** 无新改动（只跑验证；发现问题就地修）。

- [ ] **Step 1: worker 全量测试**

Run: `cd apps/api && npm test 2>&1 | tail -10`
Expected: 全部 PASS。

- [ ] **Step 2: iOS 全量单测 + 构建**

```bash
cd apps/ios && xcodebuild test -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:FreshPantryTests 2>&1 | tail -15
```
Expected: 全部 PASS。

- [ ] **Step 3: 模拟器手动冒烟（StoreKit 本地配置生效）**

模拟器跑 app：Settings 出现 Pro 行 → 打开 PaywallSheet 显示 ¥30 本地价 → 购买（StoreKit 测试环境）→ isPro 生效 → MealPlan 解锁、AI 入口不再弹 paywall；Xcode Transactions 管理器里 Refund 该交易 → 门控恢复。

- [ ] **Step 4: Commit（如冒烟中有修复）并汇报**

## 手动跟进清单（用户操作，代码之外）

1. App Store Connect 创建内购商品：ID `freshpantry.pro`，类型 Non-Consumable，勾选 **Family Sharing**，定价（本地配置写的 ¥30 档，最终以 ASC 为准），中文名「Fresh Pantry Pro」。
2. DeepSeek 开放平台创建 API key 并充值，交给 Task 2 的 `wrangler secret put`。
3. 上线前用真实 prompt 对 `deepseek-v4-flash` 做质量抽查：4 个任务（食材解析/菜谱解析/菜谱生成/菜谱改写）各 3 条中文用例，走 TestFlight 或 BYOK 指向 DeepSeek 直连验证。
