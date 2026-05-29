# 家庭管理 UX 重组 — 设计

日期: 2026-05-29
状态: 已确认设计，待实现计划

## 目标

把家庭管理从「设置」深处的一段内联卡片，重组为一个易达、自洽的「家庭」页，解决四个摩擦点：

1. **埋得深** — 家庭管理是设置深处的卡片，不是一级入口。
2. **切换隐蔽** — 多家庭时切换只是名字旁的小下拉，单家庭时完全不出现。
3. **无法自行退出** — 成员只能被拥有者移除，自己想离开一个家庭没有入口。
4. **进入 app 后无法接受邀请** — 收到的邀请只在登录页处理。

本应用是自用（A-mode）：优化维护者的使用摩擦，不追求留存。设计相应保持轻量，优先复用既有部件与状态机。

## 范围

**做：**
- 首页（dashboard）顶栏新增「家庭 chip」作为一级入口，带未处理邀请红点。
- 新增独立「家庭」页（`HouseholdScreen`），集中：切换、成员、收到的邀请、邀请、改名、退出/解散。
- 家庭页内「收到的邀请」区，进入 app 后即可接受（复用已就绪的 `acceptInviteById`）。
- 成员「退出家庭」：新增 controller 方法 `leaveHousehold`。
- 设置里的内联 `HouseholdSection` 收成一行 `家庭共享 ›`，跳转到家庭页。

**不做（非目标）：**
- 共享透明度仪表盘（库存/清单/食谱数量、同步状态、变更历史）—— 原摩擦点 5，本次不做。
- 所有权转移。退出/解散后回退到另一家庭或本地态即可。
- 邀请「拒绝」API（后端目前只有拥有者撤销，无被邀人拒绝）。被邀人不处理即等同忽略。

## 现状（基线）

- 导航外壳：5 个底部 tab（home / 库存 / add / 食谱 / 购物），各页用 `FkTopBar`；设置从首页顶栏进。
- 家庭管理 UI：`lib/widgets/settings/household_section.dart`，作为内联卡片嵌在 `settings_screen.dart`。已含：家庭名（>1 时下拉切换）、改名、成员列表（拥有者可滑动移除）、拥有者待处理邀请（可撤销）、邀请（链接/扫码 + 邮箱）、解散家庭。
- 状态机：`household_session_controller.dart` 已提供 `createHousehold / switchHousehold / updateHouseholdName / createInvite / acceptInvite / acceptInviteById / removeMember / revokeInvite / dissolveHousehold / refreshPendingInvites` 等；状态含 `households / householdMembers / pendingInvitePreviews（收到的邀请）/ ownerPendingInvites / selectedHouseholdId / currentUserId`。
- 关键发现：
  - `acceptInviteById` 已经会「接受 → 重载家庭 → 选中新加入的家庭 → 从 `pendingInvitePreviews` 移除」。摩擦点 4 几乎是纯前端：把 `pendingInvitePreviews` 展示出来并加一个接受按钮。
  - `dissolveHousehold` 用私有 `_selectedHouseholdIdAfterRemoval` 在移除后回退选中家庭。`leaveHousehold` 可复用同一回退逻辑。
  - `removeMember(householdId, userId)` 移除后只重载「该家庭」的成员，不处理「移除的是当前用户」后的重选。因此自行退出需要独立的 `leaveHousehold` 流程，而非直接复用 `removeMember`。

## 设计

### 组件

| 组件 | 文件 | 说明 |
|------|------|------|
| 家庭 chip | `lib/widgets/dashboard/household_chip.dart`（新增） | 显示当前家庭名（`🏠 我家 ▾`），`pendingInvitePreviews` 非空时显示红点。点按 `Navigator.push` 到 `HouseholdScreen`。放在 dashboard 的 `FkTopBar` 上。 |
| 家庭页 | `lib/screens/household_screen.dart`（新增） | 承载家庭管理 UI。组合下面的 `HouseholdSection`（已扩展）。 |
| 家庭管理区 | `lib/widgets/household/household_section.dart`（从 `settings/` 移动 + 扩展） | 复用现有成员/邀请/待处理/解散/改名部件；新增「收到的邀请」区与成员「退出家庭」动作。 |
| 设置入口行 | `lib/screens/settings_screen.dart`（改） | 内联 `HouseholdSection` 替换为一行 `家庭共享 ›`，点按跳家庭页。 |
| 退出家庭 | `lib/household/household_session_controller.dart`（改） | 新增 `Future<bool> leaveHousehold(String householdId)`。 |

### 家庭页结构（自上而下）

1. **家庭头**：当前家庭名 + `▾`（点开展开切换列表，含 `＋创建家庭`，即使只有一个家庭也显示名字）+ 改名（仅拥有者）。
2. **收到的邀请**（新增，仅当 `pendingInvitePreviews` 非空）：每条显示家庭名 + 邀请人 + 库存/成员数预览 + `[接受]`（调 `acceptInviteById`，接受后自动切到该家庭并从列表移除）。
3. **成员**（复用）：成员行 + 角色标签；拥有者可对其他成员滑动移除。
4. **邀请**（复用，仅拥有者）：扫码/链接邀请 + 邮箱定向邀请；拥有者待处理邀请（可撤销）。
5. **危险区**：成员 → `退出家庭`（新增）；拥有者 → `解散家庭`（现有）。拥有者不显示「退出」。

### 角色可见性

- **拥有者**：头（改名）、成员（可移除他人）、邀请、待处理邀请、解散家庭。无「退出」。
- **成员**：头（不可改名）、成员（只读）、收到的邀请、退出家庭。无邀请/解散。

### 数据流

- chip 与家庭页都从 `householdSessionControllerProvider` 读状态：家庭名取 `households` 中 `selectedHouseholdId` 对应项；红点取 `pendingInvitePreviews.isNotEmpty`；`isOwner = selected.ownerId == currentUserId`。
- 切换：`▾` 列表项 → `switchHousehold(id)`（已加载成员、刷新拥有者待处理邀请）。
- 接受邀请：`[接受]` → `acceptInviteById(inviteId)`。
- 退出：`退出家庭` → 确认弹窗 → `leaveHousehold(selectedHouseholdId)`。
- 移除成员 / 撤销 / 邀请 / 改名 / 解散：维持现有调用。

### `leaveHousehold` 行为（新增方法）

仿 `dissolveHousehold`：

1. `removeMember(householdId, currentUserId)`（删自己的成员行）。
2. `loadHouseholds()` 重载。
3. `selectedId = _selectedHouseholdIdAfterRemoval(households, removedHouseholdId: householdId)`（回退到另一家庭；都没有则空 = 本地态）。
4. 为新的 `selectedId` 加载成员；刷新 `pendingInvitePreviews`。
5. 失败：保持原选中并写 `error`。

UI：成员在家庭页点「退出家庭」→ 确认弹窗（破坏性）→ 调用 → 成功后页面随状态刷新（若回退到本地态则关闭家庭页或显示空态）。

### 边界与状态

- **无家庭 / 本地态**：chip 显示「本地数据」之类占位，点按进入家庭页显示「创建家庭 / 登录共享」CTA（复用现有创建/登录路径，不新造登录流程）。
- **拥有者退出**：不提供。拥有者只能解散或先邀请他人（所有权转移本期不做）。
- **退出当前家庭**：靠 `_selectedHouseholdIdAfterRemoval` 回退；UI 跟随状态刷新。
- **chip 放置**：仅首页顶栏，不在每个 tab，保持轻量。

## 测试

- `leaveHousehold`：成员退出后 `_selectedHouseholdIdAfterRemoval` 回退到另一家庭 / 本地态；失败时保持原选中。沿用现有 `household_session_controller` 的 fake gateway 测试范式。
- 收到的邀请：家庭页在 `pendingInvitePreviews` 非空时渲染该区；`[接受]` 触发 `acceptInviteById` 并使该条消失、切到新家庭（widget + controller 测试）。
- 家庭 chip：渲染当前家庭名；`pendingInvitePreviews` 非空时显示红点；点按打开家庭页（widget 测试）。
- 角色可见性：成员看不到邀请/解散、看得到退出；拥有者反之（widget 测试）。
- 设置入口行：点按跳转家庭页（widget 测试）。
- 回归：现有 `household_section` / 设置相关测试随文件移动与结构调整更新。

## 需在实现时核实的假设 / 风险

- **Supabase RLS**：成员是否被允许删除「自己」的成员行（`leaveHousehold` 依赖此）。若现有策略只允许拥有者删除成员，需要一条迁移，新增「成员可删除自身成员行」的 RLS 策略。实现计划第一步先核实，必要时补迁移 + Supabase 测试。
- **chip 在顶栏的位置**：`FkTopBar` 是否有可用的 leading/trailing 槽位容纳 chip，需读 `fk_top_bar.dart` 确认接口，必要时扩展其参数。

## 不引入的东西

- 不新建底部 tab、不改底部导航结构。
- 不做共享透明度仪表盘、所有权转移、邀请拒绝 API。
- 不重写登录/创建家庭流程，复用现有路径。
