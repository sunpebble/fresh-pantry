# 个人信息（头像 / 名称 / 昵称）设计稿

- 日期：2026-06-11
- 状态：已评审，待实现计划
- 范围：iOS 端 + Supabase schema（Flutter 对等留作后续 parity backfill）

## 1. 背景与目标

家庭共享已落地（`households` / `household_members` / `list_household_members` RPC），但成员在 UI 里**只显示 email 首字母**。`profiles` 表早在初始 schema 就存在（`id` / `email` / `display_name`），却**从未被 iOS 端使用**。

本设计补齐「个人信息」：

1. 用户可设置**头像、名称（display_name）、昵称（nickname）**。
2. 家庭成员列表显示彼此的头像与名称。
3. 新用户 onboarding 时**强制填写显示名**（头像可选）。

### 名称语义（已确认）

- **名称 = `display_name`**：主显示名，家庭成员列表与各处显示的主名。
- **昵称 = `nickname`**：可选简称/别名；留空则显示回退到 `display_name`。
- 显示优先级：`nickname ?? display_name ?? email`。

## 2. 核心架构判断

Profile 与现有 content 实体（库存 / 采购 / 食谱 / 膳食 / FoodLog）**本质不同**，不能套用现有 household-scoped 的同步范式：

| 维度 | content 表 | profiles |
|---|---|---|
| 归属 | household-scoped（带 `household_id`） | **user-scoped**（主键即 `auth.users.id`，无 household） |
| 写者 | 家庭多人并发写 | **只有本人写自己** |
| 同步 | outbox + 版本合并 + realtime（按 household 订阅） | 单写者，无并发冲突 |
| RLS | `is_household_member(household_id)` | `auth.uid() = id`（写）；成员互看走 RPC |

**结论**：profile **不接** `HouseholdContentSyncCoordinator`，不复用 outbox/版本列。强行塞一个假的 `household_id` 会污染 content 同步的不变式。改用一套轻量直写同步（见 §6）。

## 3. 已确认的关键选择

| 决策点 | 选择 | 理由 |
|---|---|---|
| 头像存储 | **Supabase Storage（public `avatars` 桶）** | 规范、可扩展；用户已选 Storage 而非 base64 |
| 同步机制 | **轻量直写**（本地乐观更新 + pending 重试），不接 outbox | 单写者无并发冲突，outbox 的版本/合并是多余复杂度 |
| 成员显示数据源 | **扩展 `list_household_members` RPC** | RPC 已 `left join profiles`、是 `security definer`，一次拿全，且**无需放宽 `profiles_select_self`** RLS（最小暴露面） |
| 头像引用 | **存 storage path，客户端拼 public URL** | 换桶/迁移更稳，避免把完整 URL 固化进 DB |
| Onboarding 强制度 | **强制填 `display_name`，头像可选、可跳过** | 保证家庭成员列表不出现空名/纯 email |
| 平台范围 | **iOS-only + Supabase**，Flutter 留后续 | 与近期 commit 节奏一致，先单端落地 |

## 4. Supabase 变更（单个新 migration）

新文件：`supabase/migrations/<ts>_profile_personal_info.sql`

### 4.1 `profiles` 加列

```sql
alter table public.profiles
  add column if not exists nickname text,
  add column if not exists avatar_path text;
```

- `display_name` / `email` / `updated_at` 已存在，不动。
- **不加** `version` / `client_id` / `client_updated_at` / `deleted_at`：单写者，用 `updated_at` 做「最后写赢」即可。

### 4.2 扩展 `list_household_members` RPC

在 `returns table(...)` 与 `select` 中追加 `display_name`、`nickname`、`avatar_path`（复用已有的 `left join public.profiles p on p.id = hm.user_id`）。RPC 是 `security definer`，因此成员可见彼此这三个字段，**无需新增成员互看 profiles 的 RLS policy**。

`returns table` 追加：

```sql
  display_name text,
  nickname text,
  avatar_path text
```

`select` 追加对应 `p.display_name`、`p.nickname`、`p.avatar_path`。排序键沿用现状。

### 4.3 Storage `avatars` 桶

```sql
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;
```

`storage.objects` RLS（用户只能写自己 `{auth.uid()}/` 前缀；公开读由 public 桶提供）：

- `insert` / `update` / `delete`：`with check`/`using` 限定 `bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text`。
- 读：public 桶，无需额外 select policy。

`profiles.avatar_path` 存形如 `{user_id}/avatar.jpg` 的 storage path；客户端用 `getPublicURL` 拼显示地址。

### 4.4 RLS 现状（无需改动）

- `profiles_select_self` / `profiles_insert_self` / `profiles_update_self` 已覆盖本人读写自己。
- 成员互看走 §4.2 的 `security definer` RPC，**不**放宽 select 策略。

## 5. iOS 改动

### 5.1 新建

| 文件 | 职责 |
|---|---|
| `Sync/Household/ProfileModels.swift` | `UserProfile` DTO（Codable/Sendable）：`id` / `email` / `displayName` / `nickname` / `avatarPath` |
| `Persistence/ProfileRecord.swift` | SwiftData `@Model`：缓存当前用户 profile + `pendingUpload: Bool`（离线写标记） |
| `Persistence/Repositories/ProfileRepository.swift` | `ModelActor`：本地读写 `ProfileRecord` |
| `Features/Settings/ProfileStore.swift` | `@Observable @MainActor`：load / edit / save，暴露 pending / error 状态 |
| `Features/Settings/ProfileEditView.swift` | 编辑头像（`PhotosPicker`）+ 名称（必填）+ 昵称（可选）；onboarding 复用其精简态 |

### 5.2 扩展

| 文件 | 改动 |
|---|---|
| `Sync/RemotePantryRepository.swift` | 加 `loadMyProfile()`（`select profiles where id = auth.uid`）、`upsertMyProfile(...)`、`uploadAvatar(data:)`（Storage 上传 + 返回 path） |
| `Sync/Household/HouseholdModels.swift` | `HouseholdMember` 加 `displayName` / `nickname` / `avatarPath`；RPC 解码同步扩展 |
| `Persistence/ModelContainerFactory.swift` | models 数组加 `ProfileRecord.self` |
| `App/AppDependencies.swift` | 注入 `ProfileRepository` / `ProfileStore` |
| `Features/Household/HouseholdView.swift` | `memberRow` 显示头像（avatar→public URL，回退首字母色块）+ 显示名（`nickname ?? displayName ?? email`）+ role |
| `Features/Settings/SettingsView.swift` | 顶部「个人资料」入口行（头像 + 名称），进入 `ProfileEditView` |
| `App/RootView.swift` | onboarding 接入点：登录后、进家庭流程前插入 `ProfileSetupView`（详见 §7） |

## 6. 同步细节（轻量直写）

- **写**：编辑 → 本地 `ProfileRecord` 乐观更新 + `pendingUpload = true` → 触发 `upsertMyProfile` + 头像上传 → 成功清除 pending；失败**保留 pending 且 UI 可见**，在前台 / 网络恢复 / 下次启动时重试。单写者无并发冲突，无需版本合并。
- **读自己**：登录后 `loadMyProfile` 合并进本地 `ProfileRecord`。
- **读成员**：成员 profile 随 `list_household_members` 一并返回（成员列表刷新即更新），不额外订阅 realtime。
- **失败可见**：与上条 commit「迁移失败可见」一致，pending / 上传失败不静默吞，在编辑页与（必要时）成员页给出提示。

## 7. Onboarding（强制填显示名）

- 接入点：登录成功后、进入主界面 / 家庭流程**之前**（`RootView` 的 auth → household 之间）。
- 判定：登录后 `loadMyProfile`，若 `display_name` 为空 → 展示 `ProfileSetupView`，`displayName` 必填、头像可选、允许「稍后」跳过头像但不跳过名称；`display_name` 非空 → 跳过此步。
- 首次保存为 `insert`（`profiles_insert_self` 已允许；`email` 取自 auth 会话）。Supabase 无 `auth.users → profiles` 的自动建行 trigger，故客户端必须 `upsert`（insert-or-update）。

## 8. 头像处理

- `PhotosPicker` 选图 → 上传前压缩（**≤512px、JPEG 质量 0.8**），避免大图进 Storage。
- 上传路径 `{user_id}/avatar.jpg`；成功后写回 `profiles.avatar_path`。
- 显示：`avatar_path` → `getPublicURL` → `AsyncImage`；缺失或加载失败回退首字母色块（复用 `FkCategoryAvatar` 风格）。

## 9. 测试

- **RLS / RPC**：在 `supabase/tests/family_sync_rls.sql` 补充 `list_household_members` 返回新字段、且非成员无法读取的断言。
- **ProfileStore 单测**：保存成功清 pending；保存失败保留 pending；显示名回退优先级。
- **Storage RLS**：用户只能写自己 `{uid}/` 前缀（如本地可跑 storage 测试则补，否则在 migration 注释标注手测项）。

## 10. 文件清单

**新建（5 iOS + 1 migration）**
- `supabase/migrations/<ts>_profile_personal_info.sql`
- `apps/ios/FreshPantry/Sync/Household/ProfileModels.swift`
- `apps/ios/FreshPantry/Persistence/ProfileRecord.swift`
- `apps/ios/FreshPantry/Persistence/Repositories/ProfileRepository.swift`
- `apps/ios/FreshPantry/Features/Settings/ProfileStore.swift`
- `apps/ios/FreshPantry/Features/Settings/ProfileEditView.swift`

**修改（7 iOS + 1 测试）**
- `apps/ios/FreshPantry/Sync/RemotePantryRepository.swift`
- `apps/ios/FreshPantry/Sync/Household/HouseholdModels.swift`
- `apps/ios/FreshPantry/Persistence/ModelContainerFactory.swift`
- `apps/ios/FreshPantry/App/AppDependencies.swift`
- `apps/ios/FreshPantry/Features/Household/HouseholdView.swift`
- `apps/ios/FreshPantry/Features/Settings/SettingsView.swift`
- `apps/ios/FreshPantry/App/RootView.swift`（onboarding 接入点）
- `supabase/tests/family_sync_rls.sql`（测试）

## 11. 风险与开放点

- **Flutter parity**：本次 iOS-only；schema 改动两端共享，Flutter 客户端补齐另开任务。
- **onboarding 接入位置**：`RootView` 当前 auth → household 流转需在实现时精确定位插入点，避免与既有家庭自动选择 task 抢顺序。
- **Storage 测试**：本地 Storage RLS 自动化测试若不便，则降级为 migration 内注释化的手测清单。
