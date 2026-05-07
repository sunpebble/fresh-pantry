# Agent Team 优化项目 — 设计 Spec

**日期**:2026-05-07
**目标项目**:fresh_pantry(Flutter + Riverpod,~11k LOC)
**状态**:已通过用户批准,等待复审后进入实施计划

---

## 1. 目标

派遣一组 Claude Code sub-agents 协同分析与优化 fresh_pantry 现有代码,覆盖四个维度:代码质量与重构、性能与 Riverpod 使用、测试覆盖与错误处理、UI 一致性与边缘体验。

这是**一次性任务**(不是建立长期 team 配置),产出包括:统一优化报告 + 一批已实施的低风险改动 + 一份待人工裁决的高风险清单。

## 2. 非目标

- 不重新设计 fresh_pantry 的整体架构(分层、状态管理选型保持不变)
- 不引入新依赖(除非高风险清单中被批准)
- 不修改 build/ .dart_tool/ 平台目录(android/ios/macos/...)、配置文件(pubspec.yaml、analysis_options.yaml)
- 不建立长期 agent team 配置文件(如 .claude/agents/*),所有 agent 派发都走主对话即时调用

## 3. 执行模式

**实施优先**:发现低风险问题直接改,高风险才请用户拍板。

### 3.1 风险边界(LOW = 直改,HIGH = 待批准)

**LOW(直改)**
- 重命名局部变量、私有方法、单文件内符号
- 删除 dead code(经 grep 确认 0 引用)
- 提取局部常量(scope 在单文件内)
- 补单元测试(纯新增,不动现有测试)
- 修 lint 与 dart format 问题
- 一致化 import 顺序

**HIGH(待批准)**
- Provider 拆分/合并
- Storage / Service 接口签名变更
- Widget public API(props、callback 签名)变更
- 跨屏数据流重组
- 添加或删除依赖
- 提取全局常量
- 跨文件合并/拆分 widget
- 修改依赖注入结构

## 4. Team 组成

| Agent | subagent_type | 关注范围 | 职责 |
|-------|--------------|---------|------|
| Quality Explorer | `Explore` | `lib/**/*.dart`(排除 `lib/data/` 中的纯数据常量、生成代码) | 重复代码、过长函数(>60 行)、命名不一致、过度抽象、dead code |
| Perf Explorer | `Explore` | `lib/screens/`、`lib/widgets/`、`lib/providers/` | 不必要 rebuild、selector 缺失、ListView 未用 builder、Provider 依赖图问题 |
| Test Explorer | `Explore` | `test/`、`lib/providers/`、`lib/utils/` | 测试盲点(provider 行为/边界值/错误路径)、缺少 widget 测试的关键屏幕 |
| UX Explorer | `Explore` | `lib/screens/`、`lib/widgets/`、`lib/theme/` | 主题/字体/间距不一致、空态/加载/错误 UI 缺失、a11y 问题 |
| Lead(主对话) | — | 协调全局 | 合并报告、风险分类、串行实施、commit、与用户交互 |

**执行权限**:Explorer 全部只读(`Explore` subagent_type 默认无 Edit/Write);实施阶段 Lead 自己改 HIGH 待批准代码,LOW 改动可派 `code-simplifier` agent 协助。

## 5. 工作流(三阶段)

### 阶段 1:并行研究

Lead 在**单条消息内**并行派发 4 个 Explorer agent。每个 agent 收到的 prompt 包含:
- 关注范围(table 中列出的目录/文件 glob)
- 报告格式契约(见 §6)
- 严格要求"只读分析,不要修改任何文件"
- 限定输出长度:每个 agent ≤ 50 个 issue(超出时按 severity 降序、同 severity 按 risk(HIGH 优先)、再按 file 字典序取前 50)

### 阶段 2:Lead 合并 + 风险分类

Lead 收齐 4 份报告后:

1. **合并**:解析 4 份 markdown 表格,合并到一个总表,按文件路径排序
2. **去重**:同一 (file, line) 多 agent 命中视为强信号,合并为一行(category 字段累加)
3. **风险打标**:对每行按 §3.1 规则标注 LOW / HIGH
4. **冲突检测**:同一文件多个 LOW 改动合并到一个 commit batch;若 LOW 与 HIGH 同文件,LOW 必须等 HIGH 决策后再实施(避免重复修改)
5. **写入报告**:统一报告写入 `docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md`(独立于本 design 文件)
6. **向用户呈现**:
   - LOW 总览(数量 / 影响文件 / 类别分布) — 一次性批准
   - HIGH 一项一项过 — 用户对每项做 实施 / 推迟 / 拒绝 三选一

### 阶段 3:串行实施

按文件分组实施(同文件的 LOW 改动合到一个 commit):

1. 每个 commit 前:`flutter analyze`(基线)
2. 实施改动
3. 每个 commit 后:`flutter analyze` + `flutter test`(全量;~22 个测试文件,跑全量比"判断受影响范围"更可靠)
4. 失败立即 `git revert`,问题记入报告 "Failed Items" 段
5. Commit message 格式:`opt(<agent>): <one-line summary>`,例如 `opt(quality): extract expiry check helper`

## 6. 报告格式契约

每个 Explorer agent 必须返回这个结构(无变体):

````markdown
## <Agent Name> Findings

Summary: <1 句话总结发现的主要问题类型>

| File:Line | Severity | Category | Issue | Proposal | Risk |
|-----------|----------|----------|-------|----------|------|
| lib/foo/bar.dart:42 | medium | duplication | 同样的过期判断逻辑出现 3 次 | 提取到 utils/expiry_calculator.dart | LOW |

Notes (optional): <无法在表格中表达的全局观察>
````

**字段定义**:
- **File:Line** — 必须是项目内相对路径,行号指向问题的起始行
- **Severity** — `low` / `medium` / `high`,描述问题影响
- **Category** — 自由短词(`duplication`、`rebuild`、`missing-test`、`a11y`...),便于聚合
- **Issue** — 问题的 1-2 句客观描述
- **Proposal** — 具体修复方案(必须是动作,不是模糊描述)
- **Risk** — `LOW` / `HIGH`,Explorer 自己按 §3.1 初判,Lead 复核

**Severity 与 Risk 独立**:可能"严重但低风险"(明显死代码)或"轻微但高风险"(改 API 影响多处)。

## 7. 错误与冲突处理

- **Agent 失败/超时**:Lead 不阻塞其他 3 个 agent,记录失败原因到报告 "Failed Agents" 段,后续手动补做
- **同文件冲突**:Lead 检测后合并到一个 spec 条目人工裁决,不让 simplifier agent 同时改
- **commit 后测试失败**:立即 `git revert`,问题挪到 "Failed Items" 段,不重试
- **flutter analyze 引入新 warning**:与失败同等处理(revert)
- **Explorer 报告格式不合规**:Lead 拒收并要求 agent 重发,只重试 1 次,仍失败则手工解析

## 8. 范围

**包含**
- `lib/**/*.dart`
- `test/**/*.dart`

**排除**
- `build/`
- `.dart_tool/`
- 生成代码(`*.g.dart`、`*.freezed.dart` 如有)
- 平台目录(`android/`、`ios/`、`macos/`、`linux/`、`windows/`、`web/`)
- `docs/`
- 配置文件(`pubspec.yaml`、`analysis_options.yaml`、`.metadata`)

## 9. 成功标准

- [ ] 4 份 Explorer 报告全部产出并合并成统一报告(独立 markdown 文件)
- [ ] 所有 LOW 项实施完毕(或被 revert 后挪入 Failed Items),`flutter analyze` 0 error / 0 warning
- [ ] `flutter test` 全部通过
- [ ] 至少 1 个新增测试覆盖了 Test Explorer 找到的盲点
- [ ] 所有 HIGH 项有明确决策(实施 / 推迟 / 拒绝)记录在 spec
- [ ] 总 commit 数 < 受影响文件数(避免每文件多 commit 制造噪声)
- [ ] 报告中明确列出 "Failed Agents"、"Failed Items" 段(即使为空)

## 10. 产出物清单

执行完毕后,以下文件存在并已 commit:

1. `docs/superpowers/specs/2026-05-07-agent-team-optimization-design.md` — 本文件
2. `docs/superpowers/specs/2026-05-07-agent-team-optimization-report.md` — 合并报告与决策记录
3. `docs/superpowers/plans/2026-05-07-agent-team-optimization-plan.md` — 实施计划(由 writing-plans skill 产出)
4. 一系列 `opt(<agent>): ...` commit,实现 LOW 与已批准的 HIGH 项

## 11. 已知限制

- Explorer agent 的 ≤50 issue 上限可能漏掉次要问题(可接受,聚焦高价值)
- 跨 agent 的语义重叠(例如 Quality 看到的"重复代码"恰好也是 Perf 看到的"过度 rebuild")只能靠 Lead 在合并阶段识别,可能有少量重复条目
- 不在范围内:平台代码(android/ios)、构建脚本、CI 配置 — 这些后续如有优化需求需要单独立项
