# 设置页「我」卡片 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把个人资料编辑入口从「账号·家庭」分组里的一行文字，改成设置页顶部一张带头像、整卡可点进编辑的「我」卡片。

**Architecture:** 纯 iOS 视图层重排，集中在 `SettingsView.swift`。把卡片唯一有分支的文案逻辑（标题/副标题选择）抽成可测的纯结构体 `ProfileCardModel`（TDD），卡片视图与 `Form` 重排靠编译 + 手测验证。复用既有 `MemberAvatar`、`ProfileStore`、`ProfileEditView`、`$showProfileEditor` sheet，不碰数据层/同步/schema/Flutter。

**Tech Stack:** SwiftUI、XCTest、`@Observable` ProfileStore、Supabase（仅间接，经 ProfileStore）。

**关联 spec:** `docs/superpowers/specs/2026-06-11-settings-profile-card-design.md`

---

## File Structure

| 文件 | 角色 | 改动 |
|---|---|---|
| `apps/ios/FreshPantry/Features/Settings/SettingsView.swift` | 设置页 | 新增 `ProfileCardModel`（纯逻辑）、`ProfileCardRow`（卡片视图）、`profileCardSection`；`Form` 顶部插入卡片；从 `accountSection` 删除「个人资料」`Button`；`.sheet` 迁移到卡片 section | 
| `apps/ios/FreshPantryTests/ProfileCardModelTests.swift` | 测试 | 新建，覆盖标题/副标题选择逻辑 |

`ProfileCardModel` 为 `internal`（默认）以便 `@testable import` 可访问；其余卡片视图保持 `private`。

---

## Task 1: ProfileCardModel —— 卡片文案选择（TDD）

把卡片的标题/副标题选择抽成纯结构体。规则（来自 spec §3.1）：
- `title`：`displayName` trimmed 非空 → 用它；否则 → `"设置头像与名称"`。
- `subtitle`：`nickname` trimmed 非空 → 用它；否则 → 传入的 `accountFallback`（账号态文案，由视图层用现有 `accountSubtitle` 计算后注入）。

**Files:**
- Create: `apps/ios/FreshPantryTests/ProfileCardModelTests.swift`
- Modify: `apps/ios/FreshPantry/Features/Settings/SettingsView.swift`（文件末尾新增 `ProfileCardModel`）

- [ ] **Step 1: 写失败测试**

Create `apps/ios/FreshPantryTests/ProfileCardModelTests.swift`:

```swift
import XCTest
@testable import FreshPantry

final class ProfileCardModelTests: XCTestCase {
    func test_title_usesDisplayName_whenPresent() {
        let model = ProfileCardModel(displayName: "小白", nickname: "", accountFallback: "a@b.com")
        XCTAssertEqual(model.title, "小白")
    }

    func test_title_fallsBackToPrompt_whenDisplayNameBlank() {
        let model = ProfileCardModel(displayName: "   ", nickname: "x", accountFallback: "a@b.com")
        XCTAssertEqual(model.title, "设置头像与名称")
    }

    func test_subtitle_prefersNickname_whenPresent() {
        let model = ProfileCardModel(displayName: "小白", nickname: "阿白", accountFallback: "a@b.com")
        XCTAssertEqual(model.subtitle, "阿白")
    }

    func test_subtitle_fallsBackToAccount_whenNicknameBlank() {
        let model = ProfileCardModel(displayName: "小白", nickname: "  ", accountFallback: "a@b.com")
        XCTAssertEqual(model.subtitle, "a@b.com")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run（Xcode 或 CLI）：
```bash
cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FreshPantryTests/ProfileCardModelTests 2>&1 | tail -20
```
Expected: 编译失败，`cannot find 'ProfileCardModel' in scope`。

- [ ] **Step 3: 写最小实现**

在 `SettingsView.swift` 文件末尾（最后一个 `private struct` 之后）新增：

```swift
/// Pure title/subtitle selection for the settings 「我」 card — extracted so the
/// branchy fallback logic is unit-testable without a SwiftUI host.
/// title: displayName when non-blank, else a "set me up" prompt.
/// subtitle: nickname when non-blank, else the account-state line.
struct ProfileCardModel {
    let displayName: String
    let nickname: String
    /// Account-state line (signed-in email / local-only / signed-out hint),
    /// computed by the view from the existing `accountSubtitle`.
    let accountFallback: String

    var title: String {
        displayName.trimmed.isEmpty ? "设置头像与名称" : displayName.trimmed
    }

    var subtitle: String {
        nickname.trimmed.isEmpty ? accountFallback : nickname.trimmed
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run:
```bash
cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FreshPantryTests/ProfileCardModelTests 2>&1 | tail -20
```
Expected: 4 测试全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/FreshPantry/Features/Settings/SettingsView.swift apps/ios/FreshPantryTests/ProfileCardModelTests.swift
git commit -m "test(ios): ProfileCardModel —— 设置「我」卡片标题/副标题选择逻辑"
```

---

## Task 2: ProfileCardRow —— 卡片视图

带头像的整卡可点行。复用 `MemberAvatar`（`MemberRow.swift`）。这是视图，无单元测试；靠编译 + Task 4 手测。

**Files:**
- Modify: `apps/ios/FreshPantry/Features/Settings/SettingsView.swift`（新增 `private struct ProfileCardRow`）

- [ ] **Step 1: 新增卡片视图**

在 `SettingsView.swift` 的 `// MARK: - Rows` 区，紧挨 `SettingsLinkLabel` 之前或之后新增：

```swift
/// The top 「我」 card: a 52pt avatar + name + account/nickname subtitle + chevron,
/// the whole row tappable to open the profile editor. Mirrors Apple Settings'
/// Apple-ID card so the editor is discoverable at a glance.
private struct ProfileCardRow: View {
    let avatarURL: URL?
    let model: ProfileCardModel

    var body: some View {
        HStack(spacing: FkSpacing.md) {
            MemberAvatar(displayName: model.title, avatarURL: avatarURL, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text(model.subtitle)
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: FkSize.iconSm, weight: .semibold))
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
        .padding(.vertical, FkSpacing.xs)
        .contentShape(Rectangle())
    }
}
```

注：`MemberAvatar` 用 `displayName` 取首字母回退，传 `model.title` 即可（名称为空时回退到提示文案首字 "设"，可接受；头像有真实图时不受影响）。

- [ ] **Step 2: 编译确认无误**

Run:
```bash
cd apps/ios && xcodebuild build -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -15
```
Expected: BUILD SUCCEEDED（`ProfileCardRow` 暂未被引用，编译器可能告警 unused —— 下个 Task 接线后消除；若报 unused error 而非 warning，可先跳过 build，与 Task 3 一起编译）。

- [ ] **Step 3: 提交**

```bash
git add apps/ios/FreshPantry/Features/Settings/SettingsView.swift
git commit -m "feat(ios): ProfileCardRow —— 设置页带头像的「我」卡片行"
```

---

## Task 3: 接线 —— 顶部 section + 移除重复行

把卡片插到 `Form` 顶部、删除 `accountSection` 里的旧「个人资料」行、迁移 sheet。

**Files:**
- Modify: `apps/ios/FreshPantry/Features/Settings/SettingsView.swift`（`body`、`accountSection`、新增 `profileCardSection`）

- [ ] **Step 1: 新增 `profileCardSection`**

在 `SettingsContent` 内（紧邻 `statsSection` 之前）新增：

```swift
// MARK: 个人资料卡片

private var profileCardSection: some View {
    Section {
        Button {
            showProfileEditor = true
        } label: {
            ProfileCardRow(
                avatarURL: dependencies.profileStore.avatarURL,
                model: ProfileCardModel(
                    displayName: dependencies.profileStore.displayName,
                    nickname: dependencies.profileStore.nickname,
                    accountFallback: accountSubtitle
                )
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: FkSpacing.sm, leading: FkSpacing.md, bottom: FkSpacing.sm, trailing: FkSpacing.md))
    }
    .listRowBackground(Color.fkSurfaceContainerLowest)
    .sheet(isPresented: $showProfileEditor) {
        ProfileEditView(store: dependencies.profileStore, mode: .settings)
    }
}
```

- [ ] **Step 2: `body` 的 `Form` 顶部插入卡片**

把 `Form { ... }` 第一行从 `statsSection` 改为先放卡片：

```swift
        Form {
            profileCardSection
            statsSection
            accountSection
            reminderSection
            dietarySection
            dietPreferenceSection
            assistantSection
            appearanceSection
            comingSoonSection
            aboutSection
        }
```

- [ ] **Step 3: 从 `accountSection` 删除旧「个人资料」行 + sheet**

在 `accountSection` 中删除开头那段 `Button { showProfileEditor = true } label: { SettingsLinkLabel(systemImage: "person.text.rectangle", title: "个人资料", subtitle: profileSubtitle) }.buttonStyle(.plain)` 整块（原 `SettingsView.swift:124-134`），并删除该 section 末尾的 `.sheet(isPresented: $showProfileEditor) { ProfileEditView(...) }`（已迁到 `profileCardSection`）。`accountSection` 改为只剩「账号」「家庭共享」两个 `NavigationLink`：

```swift
    private var accountSection: some View {
        Section {
            NavigationLink {
                LoginView(auth: auth)
            } label: {
                SettingsLinkLabel(
                    systemImage: accountIcon,
                    title: "账号",
                    subtitle: accountSubtitle
                )
            }
            NavigationLink {
                HouseholdView()
            } label: {
                SettingsLinkLabel(
                    systemImage: "house.and.flag",
                    title: "家庭共享",
                    subtitle: householdSubtitle,
                    showBadge: pendingInviteCount > 0
                )
            }
        } header: {
            Text("账号 · 家庭")
        } footer: {
            Text("登录后可创建或加入家庭,在成员间同步库存、采购与食谱。")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
    }
```

- [ ] **Step 4: 删除悬挂的 `profileSubtitle`**

旧「个人资料」行是 `profileSubtitle`（`SettingsView.swift:166-169`）的唯一引用，删除该计算属性避免死代码/编译告警：

```swift
// 删除整段：
//    /// 个人资料 row subtitle: the live display name, or a prompt when unset.
//    private var profileSubtitle: String {
//        let name = dependencies.profileStore.displayName.trimmed
//        return name.isEmpty ? "设置头像与名称" : name
//    }
```
（其语义已由 `ProfileCardModel.title` 承接。）

- [ ] **Step 5: 编译确认无误**

Run:
```bash
cd apps/ios && xcodebuild build -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -15
```
Expected: BUILD SUCCEEDED，无 unused / 未定义引用告警。

- [ ] **Step 6: 提交**

```bash
git add apps/ios/FreshPantry/Features/Settings/SettingsView.swift
git commit -m "feat(ios): 设置页顶部「我」卡片入口,移除账号分组里重复的个人资料行"
```

---

## Task 4: 验证（手测 + 回归）

**Files:** 无改动，仅验证。

- [ ] **Step 1: 跑全量测试确认无回归**

Run:
```bash
cd apps/ios && xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -25
```
Expected: 全部 PASS（含新增 `ProfileCardModelTests` 与既有 `ProfileStoreTests`）。

- [ ] **Step 2: 手测 4 个场景（spec §5）**

模拟器运行 app，进设置 tab，逐项确认：
1. 有头像/名称/昵称 → 顶部卡片显示头像 + 名称(主) + 昵称(副)；点整卡 → 弹编辑表单；改名保存 → 卡片实时刷新。
2. 仅名称无昵称 → 副标题回退为登录邮箱。
3. 名称为空（可临时清空 onboarding 后的名字模拟）→ 主标题「设置头像与名称」，头像为首字母色块。
4. 本地模式（未配后端 / 未登录）→ 副标题「未配置后端·本地模式」或「登录以同步家庭数据」，头像为首字母。
5. 滚到「账号·家庭」分组 → 确认不再有重复的「个人资料」行，只剩「账号」「家庭共享」。

- [ ] **Step 3: 无新增提交**（纯验证；若手测发现问题，回到对应 Task 修复）

---

## Self-Review

**Spec coverage:**
- spec §3 顶部卡片 → Task 2 + Task 3 ✓
- spec §3.1 头像/标题/副标题/回退 → `ProfileCardModel`(Task 1) + `ProfileCardRow`(Task 2) ✓
- spec §3.2 视觉一致（`fkSurfaceContainerLowest`、52pt、`.buttonStyle(.plain)`）→ Task 2/3 ✓
- spec §4 移除重复行 + 清理 `profileSubtitle` → Task 3 Step 3/4 ✓
- spec §5 测试与 4 手测项 → Task 1（单测）+ Task 4（手测）✓
- spec 非目标（不改数据层/Flutter/编辑逻辑/成员行）→ 计划未触碰 ✓

**Placeholder scan:** 无 TBD/TODO；所有代码步骤含完整代码。

**Type consistency:** `ProfileCardModel(displayName:nickname:accountFallback:)` 在 Task 1 定义、Task 3 调用一致；`title`/`subtitle` 属性名一致；`MemberAvatar(displayName:avatarURL:size:)`、`ProfileEditView(store:mode:)`、`accountSubtitle`、`avatarURL`、`showProfileEditor` 均为既有符号。

**注:** 模拟器名（iPhone 16）按本机可用 destination 调整；若 Task 2 因 `ProfileCardRow` 暂未引用产生 unused 报错，合并 Task 2/3 一次编译即可。
