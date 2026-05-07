# Agent Team 优化项目 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 派遣 4 个专科 Explorer agent 并行分析 fresh_pantry,合并报告后由 Lead 串行实施低风险改动并就高风险项与用户决策,最终产出统一报告 + 已实施的改动 + 已记录的决策。

**Architecture:** 三阶段流水线 — (1) 4 个 Explorer 并行只读分析、(2) Lead 合并报告并打风险标、(3) 串行实施(LOW 直改 / HIGH 待批准)。每个 commit 后跑 `flutter analyze` + `flutter test` 验证,失败立即 `git revert`。

**Tech Stack:** Claude Code Agent 工具(`Explore` subagent_type)、AskUserQuestion、git、flutter CLI、markdown 报告格式。

**Spec:** `docs/superpowers/specs/2026-05-07-agent-team-optimization-design.md`

---

## Task 1: 基线检查与报告骨架

**Files:**
- Create: `docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md`

- [ ] **Step 1.1: 跑基线 flutter analyze**

Run: `flutter analyze`
Record output (error/warning/info 数量)。如果**已有** error 或 warning,记到 report.md "Pre-existing baseline" 段(不是失败,只是基线)。

- [ ] **Step 1.2: 跑基线 flutter test**

Run: `flutter test`
Expected: All pass。如果有失败,**stop** 并先报告给用户(基线挂了不能开始)。

- [ ] **Step 1.3: 创建 report.md 骨架**

Write `docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md`:

````markdown
# Agent Team 优化报告

**日期:** 2026-05-07
**Spec:** `2026-05-07-agent-team-optimization-design.md`
**状态:** 进行中

## Baseline

- `flutter analyze`: <填入 error/warning/info 数>
- `flutter test`: <填入通过数 / 总数>

## Findings (合并表)

| File:Line | Severity | Category | Issue | Proposal | Risk | Source | Decision | Status |
|-----------|----------|----------|-------|----------|------|--------|----------|--------|

(Source = quality / perf / test / ux,可逗号分隔表示多 agent 命中)
(Decision = LOW: auto-approved / HIGH: pending|approved|deferred|rejected)
(Status = pending / done / failed / reverted)

## Failed Agents

(none)

## Failed Items

(none)

## Decisions Log

(空)

## Final Verification

- [ ] flutter analyze 0 error / 0 warning
- [ ] flutter test all pass
- [ ] 至少 1 个新增测试覆盖 Test Explorer 盲点
- [ ] HIGH 项决策全部记录
- [ ] commit 数 < 受影响文件数
````

- [ ] **Step 1.4: Commit 骨架**

```bash
git add docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md
git commit -m "docs: scaffold agent team optimization report"
```

---

## Task 2: 阶段 1 — 并行派发 4 个 Explorer agents

**Files:**
- Modify: `docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md`(填 Findings 表的 Source 列原始数据)

- [ ] **Step 2.1: 在单条消息中并行调用 4 个 Agent 工具**

**关键:必须在同一条 assistant 消息里发起 4 个 Agent 调用**(并行执行)。

每个 Agent 调用使用 `subagent_type=Explore`,prompt 模板如下(把 `<AGENT_NAME>` 与 scope/checks 替换):

**Quality Explorer:**

```
你是 fresh_pantry 项目的 Quality Explorer。这是一个 Flutter + Riverpod 应用,~11k LOC。

任务:只读分析 lib/**/*.dart 中的代码质量问题。

关注范围:
- lib/models/, lib/providers/, lib/screens/, lib/services/, lib/utils/, lib/widgets/, lib/theme/, lib/app.dart, lib/main.dart
- 排除 lib/data/(纯数据常量)、生成代码 (*.g.dart, *.freezed.dart 如有)

寻找:
1. 重复代码(相同/几乎相同的逻辑出现 ≥2 处)
2. 过长函数 (>60 行 body) 或过深嵌套
3. 命名不一致(同概念在不同文件里用不同名字)
4. 过度抽象(只用一处的抽象层、单实现接口、wrapper 套 wrapper)
5. Dead code(grep 确认 0 引用的私有/公共符号)

只读分析。不要修改任何文件。

输出格式严格为以下 markdown(不要加其他文字):

## Quality Explorer Findings

Summary: <一句话总结主要问题类型>

| File:Line | Severity | Category | Issue | Proposal | Risk |
|-----------|----------|----------|-------|----------|------|
| lib/foo/bar.dart:42 | medium | duplication | 描述问题 | 具体动作描述 | LOW |

Notes (optional): <无法在表格中表达的全局观察,可省略>

字段定义:
- File:Line — 项目内相对路径,行号指问题起始
- Severity — low / medium / high
- Category — 短词(duplication, long-function, naming, over-abstraction, dead-code)
- Issue — 1-2 句客观描述
- Proposal — 具体动作("提取到 utils/X.dart 新函数 Y","删除 method Z")
- Risk — LOW(单文件局部改动、删 dead code、补常量) / HIGH(跨文件 / 改 public API / 改 Provider 拆合)

上限:≤ 50 行 issues。超出时按 severity 降序、同 severity 按 risk(HIGH 优先)、再按 file 字典序取前 50。
```

**Perf Explorer:**

```
你是 fresh_pantry 项目的 Perf Explorer。这是一个 Flutter + Riverpod 应用。

任务:只读分析性能与 Riverpod 使用问题。

关注范围:
- lib/screens/
- lib/widgets/
- lib/providers/

寻找:
1. 不必要 rebuild(整屏 watch 整个大 provider,而不是 .select 子片段)
2. selector 缺失或粒度太粗
3. ListView/GridView 没用 .builder 形式(直接构造 List<Widget>)
4. Provider 依赖图问题(循环依赖、过深链、autoDispose 缺失导致内存堆积)
5. 同步 IO 在 build 方法里(应用 FutureProvider/AsyncValue)
6. 频繁创建一次性对象(controller/style 在 build 里 new)

只读分析。不要修改任何文件。

输出格式严格为以下 markdown(不要加其他文字):

## Perf Explorer Findings

Summary: <一句话总结主要问题类型>

| File:Line | Severity | Category | Issue | Proposal | Risk |
|-----------|----------|----------|-------|----------|------|

Notes (optional): <可省略>

字段定义:
- Category 短词:rebuild, selector-granularity, list-builder, provider-graph, sync-io-in-build, allocation-in-build
- Risk LOW(局部添加 .select / 改 ListView.builder / 把 const widget 标 const) / HIGH(改 Provider 结构、拆分 Provider、改 widget public API)

上限:≤ 50 行。超出时按 severity 降序、同 severity 按 risk(HIGH 优先)、再按 file 字典序取前 50。
```

**Test Explorer:**

```
你是 fresh_pantry 项目的 Test Explorer。这是一个 Flutter + Riverpod 应用,目前 22 个测试文件。

任务:只读分析测试覆盖盲点与质量问题。

关注范围:
- test/(查看现有测试)
- lib/providers/, lib/utils/(评估应该被测但未被测的部分)
- lib/screens/(找出关键屏幕但缺少 widget 测试的)

寻找:
1. Provider 行为没有覆盖关键状态转换
2. 边界值未测(空列表 / null / 极大值 / 重复输入)
3. 错误路径未测(异常、I/O 失败、空响应)
4. 关键屏幕缺 widget 测试(如 dashboard / inventory / shopping_list)
5. 现有测试有 anti-pattern(过度 mock、断言太弱、测试名描述不准确)

只读分析。不要修改任何文件。

输出格式严格为以下 markdown(不要加其他文字):

## Test Explorer Findings

Summary: <一句话总结主要问题类型>

| File:Line | Severity | Category | Issue | Proposal | Risk |
|-----------|----------|----------|-------|----------|------|

Notes (optional): <可省略>

字段定义:
- Category 短词:missing-test, weak-assertion, over-mock, missing-edge-case, missing-error-path, anti-pattern
- File:Line — 对于"应该测但没测"的 lib/ 文件,指向待覆盖的函数/类的起始行;对于现有测试问题,指向 test/ 文件
- Risk LOW(纯新增测试、加边界用例) / HIGH(重写已有测试、删除测试)

上限:≤ 50 行。超出时按 severity 降序、同 severity 按 risk(HIGH 优先)、再按 file 字典序取前 50。
```

**UX Explorer:**

```
你是 fresh_pantry 项目的 UX Explorer。这是一个 Flutter 应用。

任务:只读分析 UI 一致性与边缘体验问题。

关注范围:
- lib/screens/
- lib/widgets/
- lib/theme/

寻找:
1. 主题/字体/间距不一致(直接用魔术数字而非 theme token)
2. 空态缺失(列表为空时没有 empty state)
3. 加载态缺失(异步操作没有 loading indicator)
4. 错误态缺失(异步失败没有错误显示)
5. a11y 问题(图片缺 semanticLabel、可点击元素缺 tooltip、对比度疑似不足)
6. 响应式/溢出问题(固定宽高、Row/Column 没考虑窄屏)
7. 重复 UI 模式(一样的卡片/按钮在多处独立实现)

只读分析。不要修改任何文件。

输出格式严格为以下 markdown(不要加其他文字):

## UX Explorer Findings

Summary: <一句话总结主要问题类型>

| File:Line | Severity | Category | Issue | Proposal | Risk |
|-----------|----------|----------|-------|----------|------|

Notes (optional): <可省略>

字段定义:
- Category 短词:theme-inconsistency, missing-empty-state, missing-loading, missing-error, a11y, responsive, ui-duplication
- Risk LOW(替换魔术数字为 theme token、加 semanticLabel、加 const) / HIGH(抽象出新共享 widget、改 widget API、改主屏幕布局)

上限:≤ 50 行。超出时按 severity 降序、同 severity 按 risk(HIGH 优先)、再按 file 字典序取前 50。
```

- [ ] **Step 2.2: 收集 4 份原始报告**

Wait for all 4 agents to return. Save raw output to scratch (in-context only, no file). 

如果某个 agent 失败/超时,记录到 report.md "Failed Agents" 段:
````markdown
- <agent name>: <失败原因>
````
不阻塞其他 agent。

如果某个 agent 输出**不符合格式契约**(没有表格、字段缺失),允许 1 次重发(同样 prompt)。仍失败则手工解析其文本输出尽力提取条目,并在 "Failed Agents" 段记录"格式不合规已手工解析"。

- [ ] **Step 2.3: 不 commit**(原始报告只在内存,合并后才入 report.md)

下一个 task 直接进入合并。

---

## Task 3: 阶段 2 — 合并报告 + 风险打标

**Files:**
- Modify: `docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md`(填 Findings 表)

- [ ] **Step 3.1: 解析 4 份报告为内部行集合**

把 4 份 markdown 表格的每行转为内部数据(file_line, severity, category, issue, proposal, risk, source)。Source 字段填 agent 名(quality / perf / test / ux)。

- [ ] **Step 3.2: 按 file 排序合并**

合并到一张总表,先按 file 字典序排,同文件内按 severity 降序。

- [ ] **Step 3.3: 去重 / 合并强信号**

若多 agent 命中同一 (file, line) 且 issue 描述高度相似(>70% 词汇重叠或人工判断同事项):
- 合并为一行
- Source 字段累加(逗号分隔,如 `quality,perf`)
- Severity 取最高
- Risk 取最高(任一 HIGH 即 HIGH)

- [ ] **Step 3.4: 风险复核(Lead 复核 Explorer 自报的 Risk)**

按 spec §3.1 规则**复核**每行的 Risk 标签:

LOW(可直改):
- 重命名局部变量、私有方法、单文件内符号
- 删除 dead code(经 grep 确认 0 引用)
- 提取局部常量(scope 在单文件内)
- 补单元测试(纯新增,不动现有测试)
- 修 lint / dart format
- 一致化 import 顺序

HIGH(待批准):
- Provider 拆分/合并、Storage/Service 接口签名变更、Widget public API 变更
- 跨屏数据流重组、添加/删除依赖、提取全局常量
- 跨文件合并/拆分 widget、修改依赖注入

模糊地带优先归 HIGH(宁可多问一次)。

- [ ] **Step 3.5: 冲突检测**

若同文件同时存在 HIGH 与 LOW 项,在 Decision 列给所有 LOW 项标 `blocked-by-high`(等 HIGH 决策后再实施,避免重复修改 / 衍生冲突)。

- [ ] **Step 3.6: 写入 report.md 的 Findings 表**

每行填入:File:Line / Severity / Category / Issue / Proposal / Risk / Source / Decision / Status

- LOW 行:Decision = `auto-approved`,Status = `pending`
- HIGH 行:Decision = `pending`,Status = `pending`
- LOW 但 blocked-by-high:Decision = `blocked-by-high`,Status = `pending`

- [ ] **Step 3.7: Commit 合并报告**

```bash
git add docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md
git commit -m "docs: merge 4 explorer reports into unified findings"
```

---

## Task 4: LOW 项总览呈现 + 用户批准

**Files:**
- Modify: `docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md`(更新 Decisions Log)

- [ ] **Step 4.1: 准备 LOW 总览**

从 Findings 表统计 LOW 项(排除 blocked-by-high 的):
- 总条数
- 受影响文件数
- 按 Category 分组的数量(例如 `duplication: 5, dead-code: 3, missing-test: 8, theme-inconsistency: 4`)
- 列出最严重的 5 条作为代表(severity = high 优先)

- [ ] **Step 4.2: 用 AskUserQuestion 呈现总览并请求批准**

调用 AskUserQuestion,question 文本如下(把括号内换成实际数据):

```
LOW 项总览:共 <N> 条,涉及 <M> 个文件,类别分布 <category breakdown>。代表性问题前 5 条:
1. <file:line> [<severity>/<category>] <issue 简述>
2. ...
是否一次性批准全部 LOW 项的实施?
```

Options:
- "全部批准,继续实施" (description: "实施所有 LOW 项,失败的会自动 revert 并记入 Failed Items")
- "我先看完整 report.md 再说" (description: "暂停。我打开报告看一遍再回来告诉你")
- "只批准 high severity 的 LOW 项" (description: "保守模式:只实施 severity=high 的 LOW 项,medium/low severity 推迟")

- [ ] **Step 4.3: 根据用户回复更新 Decision 列**

- 全部批准 → 所有 LOW 行 Decision 保持 `auto-approved`
- 只批准 high severity → 把 severity≠high 的 LOW 行 Decision 改为 `deferred`
- 用户要先看 → 暂停 plan,等用户回来再继续(不前进到 Task 5)

- [ ] **Step 4.4: 在 Decisions Log 段记录批准时间与范围**

````markdown
## Decisions Log

- 2026-05-07 LOW batch: <用户的选择>(<最终批准条数>/<总 LOW 条数>)
````

- [ ] **Step 4.5: Commit 决策**

```bash
git add docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md
git commit -m "docs: record LOW batch approval decision"
```

---

## Task 5: HIGH 项逐项决策

**Files:**
- Modify: `docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md`(更新每条 HIGH 的 Decision + Decisions Log)

如果 Findings 表里没有 HIGH 项,**跳过整个 Task 5**,直接进 Task 6。

- [ ] **Step 5.1: 提取所有 Decision = pending 的 HIGH 行**

按 Severity 降序、同 Severity 按 file 字典序排列待决策列表。

- [ ] **Step 5.2: 按批次呈现给用户(每批 ≤4 项)**

为什么按批:AskUserQuestion 一次最多 4 个问题。

对每批的每项,准备一个 AskUserQuestion question:

```
HIGH 项决策 [<i>/<N>]:
File: <file:line>
Severity: <severity>  Category: <category>  Source: <source>
Issue: <issue>
Proposal: <proposal>

如何处理这一项?
```

Options:
- "实施" (description: "现在做这个改动")
- "推迟" (description: "记录但本轮不做")
- "拒绝" (description: "不同意,不会再做")

- [ ] **Step 5.3: 把每项决策写回 Decision 列**

- 实施 → Decision = `approved`,Status = `pending`
- 推迟 → Decision = `deferred`,Status = `pending`
- 拒绝 → Decision = `rejected`,Status = `done`(不会再做,等同完结)

- [ ] **Step 5.4: 解锁被 blocked-by-high 的 LOW 项**

对每个被解锁的文件:把该文件下 Decision = `blocked-by-high` 的 LOW 行改为 `auto-approved`(若 HIGH 被批准实施)或保持 `blocked-by-high`(若 HIGH 被推迟/拒绝,改为 `deferred`)。

- [ ] **Step 5.5: 更新 Decisions Log**

````markdown
## Decisions Log

- 2026-05-07 HIGH decisions:
  - <file:line>: approved
  - <file:line>: deferred
  - <file:line>: rejected
````

- [ ] **Step 5.6: Commit 决策**

```bash
git add docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md
git commit -m "docs: record HIGH item decisions"
```

---

## Task 6: 动态生成实施子任务

**Files:**
- (不写文件,只动态创建 TaskCreate 任务)

- [ ] **Step 6.1: 提取所有 Status = pending 且 Decision ∈ {auto-approved, approved} 的行**

这些是即将实施的项。按 file 分组(同文件的所有改动合并到一个 commit batch)。

- [ ] **Step 6.2: 为每个 file batch 创建一个 TaskCreate**

对每个文件 `<file>`,调用:

```
TaskCreate(
  subject: "实施 <file> 的 <N> 项改动",
  description: 
    "文件:<file>\n"
    "改动条目(取自 report.md Findings 表):\n"
    "1. line <L1>: <issue> → <proposal> [risk=<risk>]\n"
    "2. line <L2>: ...\n\n"
    "实施步骤(在子任务执行时):\n"
    "  a. 按 proposal 修改文件\n"
    "  b. 运行 flutter analyze(必须 0 error / 0 warning 增量)\n"
    "  c. 运行 flutter test(全量)\n"
    "  d. 通过则 git add + commit `opt(<source>): <一句总结>`\n"
    "  e. 失败则 git checkout <file>(revert 工作区改动),把这些条目挪到 report.md 'Failed Items' 段,Status 改 'failed'"
)
```

- [ ] **Step 6.3: 记录子任务 ID 列表**

把所有创建的 task id 列出,方便后续按 ID 顺序执行。

---

## Task 7: 循环执行实施子任务

**Files:**
- 各种 lib/ 与 test/ 文件(由子任务的内容决定)
- Modify: `docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md`(每个子任务完成后更新 Status)

对 Task 6 创建的每个子任务,按 ID 顺序循环执行下面 Step 7.1-7.6:

- [ ] **Step 7.1: 取下一个 pending 子任务**

调用 TaskList,选 ID 最小的 pending 子任务,TaskUpdate 标 in_progress。

- [ ] **Step 7.2: 实施改动**

按子任务 description 中的条目修改对应文件。优先用 Edit 工具(精确替换)。如果改动是"补测试"且较多文本,可用 Write 创建新测试文件。

注意:
- 同文件多条改动,在一次实施里全做完(不要每条单独走一遍 7.1-7.6)
- 不要顺手做"别的优化"——只做 description 列出的条目
- 如果发现 proposal 描述有歧义无法实施,**stop** 当前子任务,把这条挪到 Failed Items 段并备注"proposal 无法解释",继续下一个子任务

- [ ] **Step 7.3: 验证 — flutter analyze**

Run: `flutter analyze`
Expected: 0 error / 0 warning 增量(对比 Task 1.1 基线;基线已有的 warning 不算回归)

如果失败 → goto Step 7.5(revert)。

- [ ] **Step 7.4: 验证 — flutter test**

Run: `flutter test`
Expected: All pass

如果失败 → goto Step 7.5(revert)。

- [ ] **Step 7.5: revert(仅当 7.3 或 7.4 失败时)**

```bash
git checkout -- <file>
# 若已新建文件则 git clean -f <new_file>
```

把本子任务所有条目的 Status 改为 `failed`,挪到 report.md "Failed Items" 段:

````markdown
## Failed Items

- <file:line> [<category>] <issue> → <proposal>
  - 失败原因: <analyze/test 报错的关键 1-2 行>
  - Source: <agent name>
````

Commit 报告更新:

```bash
git add docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md
git commit -m "docs: record failed items for <file>"
```

跳到 Step 7.7 标本子任务 completed,继续下一个。

- [ ] **Step 7.6: Commit 成功改动**

```bash
git add <changed files>
git commit -m "opt(<source>): <一句总结>"
```

`<source>` 取自 Findings 表的 Source 列(多 agent 用第一个,如 `quality`)。
`<一句总结>` 描述该 commit 的实质改动,例如:`extract expiry helper` / `replace magic spacing with theme tokens` / `add edge-case tests for shopping provider`。

更新 report.md 中本子任务对应行的 Status 为 `done`,commit:

```bash
git add docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md
git commit -m "docs: mark <file> findings as done"
```

(可与 Step 7.6 主 commit 合并,如果改动小)

- [ ] **Step 7.7: 标子任务 completed**

```
TaskUpdate(taskId=<id>, status=completed)
```

回到 Step 7.1 处理下一个子任务,直到全部完成。

---

## Task 8: 终验

**Files:**
- Modify: `docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md`(填 Final Verification 段)

- [ ] **Step 8.1: 跑最终 flutter analyze**

Run: `flutter analyze`
Expected: 0 error / 0 warning(允许基线已有的;新增=失败)

如果有新增问题 → 找出引入它的 commit,`git revert <hash>`,把对应 Findings 行改 Status = `reverted`,在 Failed Items 段记录。

- [ ] **Step 8.2: 跑最终 flutter test**

Run: `flutter test`
Expected: All pass

同样,如果有失败 → 定位 + revert + 记录。

- [ ] **Step 8.3: 验证至少 1 个新增测试覆盖 Test Explorer 盲点**

```bash
git log --since="2026-05-07" --diff-filter=A --name-only | grep '^test/' | head
```

确认至少 1 个新测试文件 commit 进来,或现有测试文件被增量加了 test case(`git log --since="2026-05-07" -p -- test/ | grep '^+test\|^+void test\|^+ \+'`)。

如果没有 → 标记成功标准 #3 未达成,在 report.md 记录原因。

- [ ] **Step 8.4: 验证 commit 数 < 受影响文件数**

```bash
# 这次任务期间的 opt 与 docs commit 总数
git log --since="2026-05-07" --oneline | grep -E '^[a-f0-9]+ (opt|docs):' | wc -l
# 受影响文件数(去重)
git log --since="2026-05-07" --pretty=format: --name-only | grep -E '^(lib|test)/' | sort -u | wc -l
```

记录两个数字到 Final Verification 段。如果 commit 数 ≥ 文件数,记 "noise commits, future cleanup needed" 但不阻塞完成。

- [ ] **Step 8.5: 填 Final Verification checklist 并 commit**

把 report.md 末尾的 Final Verification checklist 全部勾上(根据 Step 8.1-8.4 的实际结果)。状态字段更新为 `状态: 已完成`。

```bash
git add docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md
git commit -m "docs: finalize agent team optimization report"
```

- [ ] **Step 8.6: 向用户汇报**

输出一段简短总结(不超过 8 行):
- 4 agents 跑完了几个(失败的列出)
- LOW 实施 / 失败 / 推迟 数量
- HIGH 实施 / 推迟 / 拒绝 数量
- 总 commit 数 vs 受影响文件数
- Failed Items 数量
- 报告路径

---

## 验证完成标准(对应 spec §9)

任务完成时下列全部成立:

- [ ] 4 份 Explorer 报告全部产出(或失败有记录)并合并到 report.md
- [ ] 所有 Decision = approved/auto-approved 的项 Status = done(或 failed/reverted 已记录)
- [ ] `flutter analyze` 0 error / 0 warning 新增
- [ ] `flutter test` all pass
- [ ] 至少 1 个新增测试 commit
- [ ] 所有 HIGH 项 Decision 不为 pending
- [ ] commit 数与文件数对比已记录
- [ ] report.md 中 Failed Agents、Failed Items 段存在(可为空)
