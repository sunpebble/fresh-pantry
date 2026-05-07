# AI 录入：食谱 URL 解析 + 食材 拍照 / 文本清单 — 设计 spec

**日期**：2026-05-08
**作者**：kunish + Claude (brainstorming session)
**状态**：待审核
**范围**：sub-project SP0（AI 配置 + 客户端基础设施）+ SP1（三个 AI 录入入口）

> 本 spec 是一个更大优化计划的第一阶段。后续阶段（SP2 字段 / 控件重做、SP3 库存↔食谱闭环）将各自独立 spec。

---

## 1. 背景与目标

### 1.1 现状不对称

`AddIngredientScreen` 已有 `FoodKnowledge.lookup`、Open Food Facts 自动取图、常购 chips；`CustomRecipeFormScreen` 几乎全部裸 `TextField`。两屏的"录入辅助"成熟度差距明显。

### 1.2 用户痛点（已确认全选）

1. 录入方式单一 / 重复打字
2. 联想 / 复用不足
3. 字段 / 控件设计不顺手
4. 两屏不互通 / 没有闭环

### 1.3 本 spec 目标

通过引入 **OpenAI 兼容 AI 服务**，主攻"录入方式单一"和"联想 / 复用不足"两个痛点中"高速进入数据"那一面：

- **食谱**：从第三方 app 分享的 URL（如 `https://lanfanapp.com/recipe/15978`）一键 AI 解析为食谱草稿
- **食材**：拍照 → AI Vision 识别多条食材；粘贴/输入文本清单 → AI 拆解为多条
- **配置**：用户可自定义 OpenAI 兼容 base URL / api key / model（持久化在本机）

### 1.4 不在本 spec 范围

- 字段 / 控件重做（分类 dropdown、难度星级等）→ SP2
- 库存↔食谱 4 类闭环（缺料加购、匹配率、扣减、反向入库）→ SP3
- 流式输出（`streaming` review）—— 作为本 spec 之后的优化项
- AI 生成（自然语言 → 食谱）—— 用户未选

---

## 2. 系统架构

### 2.1 模块拆分

```
lib/
├── models/
│   ├── ai_settings.dart              ◄ 新
│   ├── recipe_draft.dart             ◄ 新（含 DraftField<T>）
│   └── ingredient_draft.dart         ◄ 新
│
├── services/
│   ├── ai_client.dart                ◄ 新 · OpenAI 兼容 chat client（含 vision、cancel）
│   ├── ai_recipe_parser.dart         ◄ 新 · URL → RecipeDraft
│   ├── ai_ingredient_parser.dart     ◄ 新 · 文本 / 图片 → List<IngredientDraft>
│   └── share_intent_service.dart     ◄ 新 · 接收系统分享 + 剪贴板捕获
│
├── providers/
│   ├── ai_settings_provider.dart     ◄ 新 · 持久化 + isConfigured
│   └── ai_draft_provider.dart        ◄ 新 · 当前 in-flight 草稿 (loading / error / data)
│
├── screens/
│   ├── ai_settings_screen.dart                ◄ 新
│   ├── recipe_draft_review_screen.dart        ◄ 新
│   ├── ingredient_draft_review_screen.dart    ◄ 新
│   ├── add_ingredient_screen.dart             ◄ 改 · 顶部「快速录入」三按钮
│   └── custom_recipe_form_screen.dart         ◄ 改 · 顶部 banner + 剪贴板检测
│
└── widgets/
    ├── common/top_app_bar.dart                ◄ 改 · 加齿轮入口
    └── shared/ai_draft_field.dart             ◄ 新 · 「AI 填」字段视觉标记
```

### 2.2 新增依赖

| 包 | 用途 | 必需性 |
|---|---|---|
| `receive_sharing_intent` | 系统分享接收（Android intent + iOS Share Extension） | 必需（系统分享入口） |
| 不新增 secure_storage | API key 走 SharedPreferences 明文 | 用户决策 |

### 2.3 关键架构原则

1. **统一 AI Client**：所有 AI 调用走单一 `AiClient`，通过 `ref.read(aiSettingsProvider)` 拿配置
2. **未配置时显式异常**：service 抛 `AiNotConfiguredException`，UI 层捕获后跳转设置页
3. **草稿与正式 model 分离**：`RecipeDraft` / `IngredientDraft` 带 `DraftField<T>` 来源标记，落库前 `toRecipe()` / `toIngredient()` 转换
4. **一次只能一个 in-flight AI 调用**：`aiDraftProvider` 内部 cancel token 接管旧调用
5. **`aiDraftProvider` 保留 source**：原始 URL / 图片字节 / 文本与 draft 一同保存，让 review 页的「重新生成 / 重新识别」可重放，无需用户重新输入

---

## 3. 数据模型

### 3.1 `AiSettings`

```dart
class AiSettings {
  final String baseUrl;       // e.g. https://api.openai.com/v1
  final String apiKey;
  final String model;         // 单字段，文本+vision 共用
  final Duration timeout;     // 默认 60s
  bool get isConfigured => baseUrl.isNotEmpty && apiKey.isNotEmpty && model.isNotEmpty;
  AiSettings copyWith({...});
  Map<String, dynamic> toJson();
  factory AiSettings.fromJson(Map<String, dynamic>);
}
```

持久化键：`ai_settings_v1`（单一 JSON 字符串塞 SharedPreferences）。

### 3.2 `DraftField<T>` 与 `RecipeDraft`

```dart
enum DraftSource { ai, user, hybrid }

class DraftField<T> {
  final T value;
  final DraftSource source;
  DraftField<T> editedTo(T newValue) => DraftField(newValue, DraftSource.user);
}

class RecipeDraft {
  final String? sourceUrl;
  final DraftField<String> name;
  final DraftField<String> category;
  final DraftField<int> cookingMinutes;
  final DraftField<int> difficulty;       // 1-5
  final DraftField<String> description;
  final DraftField<String?> imageUrl;
  final List<RecipeIngredientDraft> ingredients;
  final List<DraftField<String>> steps;
  Recipe toRecipe();
}
```

### 3.3 `IngredientDraft`

```dart
class IngredientDraft {
  final String id;                   // 临时 id，多项 review 用
  final DraftField<String> name;
  final DraftField<String> quantity;
  final DraftField<String> unit;
  final DraftField<String?> category;
  final DraftField<IconType?> storage;
  final DraftField<int?> shelfLifeDays;
  bool selected;                     // review 页勾选
  Ingredient toIngredient();
}
```

---

## 4. AI 协议

### 4.1 `AiClient` 接口

```dart
class AiClient {
  static Future<String> chat({
    required AiSettings settings,
    required List<AiMessage> messages,
    Map<String, dynamic>? responseFormat, // {"type":"json_object"} 兼容则启用
    CancelToken? cancelToken,
  });
}

class AiMessage {
  final String role;                    // system / user / assistant
  final List<AiContent> content;
  factory AiMessage.text(String role, String text);
  factory AiMessage.userWithImage(String text, String dataUrl);  // dataUrl: "data:image/jpeg;base64,..."
}
```

请求体（OpenAI 兼容 `/chat/completions`）：

```jsonc
{
  "model": "<settings.model>",
  "messages": [...],
  "temperature": 0.2,
  "response_format": {"type": "json_object"}  // 可选
}
```

### 4.2 三个 prompt 模板

| Service 方法 | 输入 | Prompt 关键 | 期望 JSON shape |
|---|---|---|---|
| `AiRecipeParser.fromUrl` | `String url` | "访问以下 URL（你具备访问网页的能力，请抓取页面内容并解析），抽取食谱…" | `RecipeDraft` JSON |
| `AiIngredientParser.fromImage` | `Uint8List imageBytes` | vision message + "识别图中所有可入库食材，输出条目数组…" | `[IngredientDraft]` JSON |
| `AiIngredientParser.fromText` | `String text` | "把以下食材清单拆为结构化条目，估算合理的数量、单位、分类、存储位置、保质期…" | `[IngredientDraft]` JSON |

每个 service 内部统一流程：
1. 检查 `aiSettingsProvider.isConfigured`，否则抛 `AiNotConfiguredException`
2. 构 prompt → 调 `AiClient.chat()`
3. 解析 JSON：先尝试 `jsonDecode`；失败则用正则提 ```` ```json ... ``` ```` 块再解
4. 转 draft 对象，所有字段标 `DraftSource.ai`

### 4.3 错误类型

```dart
sealed class AiException implements Exception {
  const AiException(this.message);
  final String message;
}
class AiNotConfiguredException extends AiException {}
class AiNetworkException extends AiException {}      // 含超时 / 429 / 5xx
class AiAuthException extends AiException {}        // 401 / 403
class AiParseException extends AiException {}       // JSON 不合法 / 字段缺
class AiCancelledException extends AiException {}
```

---

## 5. UI 流程

### 5.1 主流程

```
入口 → AiClient + Service → Review 页（修改）→ 写 Provider → 列表
                ↓ 失败                      ↓ 单条预填
            分类异常 UI                  AddIngredientScreen
```

### 5.2 五个屏幕

#### `AiSettingsScreen`（新）
- 入口：`TopAppBar` 右侧齿轮 + AI 功能按钮在未配置时跳转
- 字段：base URL / api key / model / timeout（默认 60s）
- **「测试连接」按钮**：发 `system: "respond with 'ok'"`、2s 超时，仅判断 200，不 parse 内容；展示 ✓ / ✗
- 「保存」：写 SharedPreferences；切换 baseUrl 时清当前 `aiDraftProvider`

#### `CustomRecipeFormScreen`（改）
- 顶部加 "✨ 用 AI 一键导入" banner（粘贴 URL + 「解析为草稿」按钮）
- **进入屏幕时**触发剪贴板检测：若剪贴板包含 `http(s)://` URL 且未在最近忽略列表中，弹一次性 toast「检测到食谱链接 → 导入 / 忽略」
- 系统分享路径：`receive_sharing_intent` 监听 → 启动时若有 pending intent 自动 push `RecipeDraftReviewScreen` 并触发解析

#### `RecipeDraftReviewScreen`（新）
- 顶部："审核 AI 草稿" + 来源 URL
- 字段就地编辑（点击 `AiDraftField` 弹简易编辑器；编辑后边色从蓝→灰，标 `DraftSource.user`）
- 步骤折叠展开
- 三按钮：「重新生成」「丢弃」「确认入库」
- 入库 = 写 `customRecipesProvider.add(recipeDraft.toRecipe())`，然后 `popUntil` 回 dashboard

#### `AddIngredientScreen`（改）
- 顶部加「快速录入」三按钮条：📷 拍照识别 / 📝 粘贴清单 / ✏️ 手填
- 「手填」= 当前默认行为
- 「拍照」→ `image_picker.pickImage(camera, imageQuality: 82)` → `AiIngredientParser.fromImage` → 路由
- 「粘贴清单」→ 弹 dialog 多行输入 → `AiIngredientParser.fromText` → 路由
- **路由分支**：识别 0 条 → SnackBar 留在原地；1 条 → push 自身（`AddIngredientScreen` initialIngredient 模式）；≥2 条 → push `IngredientDraftReviewScreen`

#### `IngredientDraftReviewScreen`（新）
- 多项卡片，默认全选；可点击编辑、可去勾
- 点击展开行 → 内联编辑 name / quantity / unit / category / storage / shelfLifeDays
- 「重新识别」（食材入口走原来源；图片 → 重新调用；文本 → 用原文重调）
- 「入库 (N 项)」→ 逐条 `inventoryProvider.add(draft.toIngredient())` → SnackBar "已添加 N 项"

### 5.3 路由 / 状态规则

- `AiSettingsScreen` push route，关闭返回
- 草稿 review 页都是 push route
- 切 tab 不丢草稿（`aiDraftProvider` 是 keepAlive）
- 杀 app 草稿丢失（不持久化，YAGNI）
- 安卓返回键在 review 页：弹 dialog "草稿未保存，丢弃？"

---

## 6. 错误处理矩阵

| 场景 | 异常 | UI 表现 | 用户出口 |
|------|------|---------|----------|
| 没填 / 填一半 settings | `AiNotConfigured` | dialog "需要先配置 AI" | 跳设置页 |
| 401 / 403 | `AiAuth` | SnackBar "认证失败，检查 API key" | 跳设置页 |
| 网络超时 / DNS | `AiNetwork` | 可重试 banner | 「重试」/ 「手填」 |
| 429 限流 | `AiNetwork`（带特征） | "服务繁忙，稍后" | 「重试」/ 「手填」 |
| 模型返回非 JSON | `AiParse` | review 页空状态 + 原文摘要 | 「重新生成」/ 「手填」 |
| 模型返回字段缺失 | `AiParse` | review 页填进部分字段，缺的标黄 | 用户补 / 重新生成 |
| URL 抓取失败（AI 端） | `AiParse`（透传） | "无法读取该链接" | 「换个 URL」/ 「手填」 |
| 用户取消 | `AiCancelled` | 静默关 loading | 留在原位 |

---

## 7. 边界情况

### SP0
- 切换 baseUrl 后清缓存：保存 settings 时丢弃 `aiDraftProvider`
- 同时多个 AI 调用：不允许；新调用进来取消旧的

### SP1 食谱 URL
- URL 校验：必须 `http(s)://`，前端拦截
- 同 URL 重复粘贴：检测 `RecipeDraft.sourceUrl` 已存在 → "已有进行中的草稿，是否覆盖"
- 系统分享带文字非纯 URL（小红书）：正则提取首个 URL
- 剪贴板捕获去重：内存记最近 1 个被忽略的 URL，30 分钟内同 URL 不再提示

### SP1 食材拍照
- 复用 `_pickCoverImage` 风格（imageQuality: 82, maxWidth: 1600）
- 0 条：SnackBar "未识别到食材"，留在 AddIngredientScreen
- 1 条：push `AddIngredientScreen(initialIngredient: ...)` 预填，跳过 review
- ≥2 条：push `IngredientDraftReviewScreen`

### SP1 食材文本
- 输入空 / 全空白：禁用「解析」按钮
- 文本超长（> 5000 字符）：截断 + 提示
- 0 / 1 / ≥2 条规则同上

---

## 8. 测试策略

### 8.1 自动化

```
test/
├── services/
│   ├── ai_client_test.dart            ← mock http；request body / headers / cancel
│   ├── ai_recipe_parser_test.dart     ← stub AiClient；fixture JSON → RecipeDraft
│   └── ai_ingredient_parser_test.dart ← 文本 / 图片 prompt 形态
├── providers/
│   └── ai_settings_provider_test.dart ← 持久化往返、isConfigured 转换
├── widgets/
│   └── ai_draft_field_test.dart       ← AI 填 / 用户改 视觉标记切换
└── screens/
    ├── ai_settings_screen_test.dart   ← 表单 + 测试连接的 loading / error
    ├── recipe_draft_review_screen_test.dart   ← 编辑 / 重新生成 / 丢弃 / 入库
    └── ingredient_draft_review_screen_test.dart ← 多项勾选 / 入库 N 项
```

### 8.2 Fixture

`test/fixtures/ai_responses/`
- `recipe_lanfan_15978.json`
- `recipe_xiaohongshu.json`
- `ingredient_text_simple.json`
- `ingredient_text_complex.json`
- `ingredient_image_fridge.json`
- `error_invalid_json.txt`
- `error_partial_fields.json`

### 8.3 手动验证清单（spec 内列出，不进 CI）

- 真实调用 OpenAI / 自定义服务，1 个 lanfan URL 走通
- 一张冰箱内部照片识别出 ≥3 条食材
- 1 条文本清单走"跳过 review"路径
- 网络断开时的错误分类是否正确
- 设置页「测试连接」在 4 种状态下表现：✓ / 401 / 网络断 / 模型不存在

---

## 9. 风险与开放问题

1. **AI 委托抓 URL 可靠性**：不一定所有 OpenAI 兼容服务支持 web tool；如失败需在错误信息明确提示。后续 spec 可以加客户端 `http.get` 兜底
2. **小红书 / 下厨房等 SPA 站点**：即使 AI 能抓，可能拿到空 SPA shell；同样在错误里明记
3. **vision 模型缺乏 confidence**：默认全选；UI 已留 confidence 钩子，未来 AI 输出后可启用差异化默认勾选

---

## 10. 后续 spec 衔接

本 spec 实现完毕后，下一阶段建议的 spec 顺序：

1. **SP3-D（反向入库）**：与本 spec 协同最佳——食谱草稿入库后，自动检测库存里没有的食材，可勾选一键入库
2. **SP2 字段 / 控件重做**：分类 dropdown / 难度星级 / 时长预设 / 步骤重排 / 食材从库存联想
3. **SP3 A/B/C**：缺料加购 / 库存匹配率 / 做完扣减（共同基石：食材名称归一化模块）

---

## 11. 决策记录

| 决策 | 选择 | 理由 |
|---|---|---|
| Review UI 模式 | B 独立 review 页 | 字段标记 / 重新生成 / 撤销整次解析 与表单耦合差，新页更清晰 |
| API key 存储 | SharedPreferences 明文 | 与现有持久化模式一致，不引入 `flutter_secure_storage` |
| URL 抓取策略 | 委托给 AI 后端 | 避免客户端 fetch 反爬复杂度 |
| 模型字段粒度 | 单一 model 字段 | 用户希望简单，需选择支持 text + vision 的模型 |
| 设置入口 | TopAppBar 齿轮 + 未配置时跳转 | 双入口最贴体验，无 BottomNav 改动 |
| 食材 AI 入口形态 | AddIngredientScreen 顶部 3 按钮 | 入口明显、闭合快、保留手填 |
| URL 入口 | 粘贴框 + 系统分享 + 剪贴板 | 三入口都做；剪贴板进 form 时检测 |
| 单条食材路径 | 直接进 AddIngredientScreen 跳过 review | 单条进 review 页过重 |
| 测试连接 | 加按钮 | 验证认证 / 模型 / 网络可用性 |
