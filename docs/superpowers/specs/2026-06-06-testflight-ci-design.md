# 设计:release-please → TestFlight 自动发布

- 日期：2026-06-06
- 状态：已实施；**2026-06-09 改指向原生 app**(见下「更新」)
- 仓库：`kunish/fresh_pantry`（private）

> **更新(2026-06-09):本文档描述的是 Flutter(`apps/mobile`)版流水线。** SwiftUI 原生
> 重写完成后,`release.yml` 的发布链路已**改指向原生 `apps/ios`**(同 bundle id,只能一个发
> TestFlight;Flutter 停止发版、代码保留)。签名策略(ASC API Key 自动签名)、build number
> 时间戳、Secrets 清单等核心决策**沿用不变**;差异仅在 job③ 用 `xcodegen + xcodebuild`
> 构建原生工程、release-please 改用 `simple` release-type 维护 `apps/ios/version.txt`。
> **原生流水线的运维说明见 [`apps/ios/README.md`](../../../apps/ios/README.md)。**

## 背景与目标

当前 iOS 发布是手动链路（本地 `flutter build ipa` → `xcodebuild -exportArchive` → `xcrun altool --upload-app`）。目标：把版本管理与 TestFlight 上传自动化——基于 Conventional Commits 自动 bump 版本、生成 CHANGELOG，并在发版时自动构建、签名、上传到 TestFlight。

## 已对齐的决策

| 决策 | 选择 |
|---|---|
| 仓库可见性 | private（macOS Actions 按 10× 计费，故门禁前置在 ubuntu） |
| 签名策略 | ASC API Key 自动签名（`-allowProvisioningUpdates` + authenticationKey），不用 fastlane match、不手动管证书 |
| 触发时机 | Release PR 合并即自动上传（全自动，无人工二次确认） |
| 质量门禁 | 上传前在 ubuntu 跑 `flutter analyze` + `flutter test`，通过才进 macOS 构建 |
| build number | UTC 时间戳 `YYYYMMDDHHMM`，单调递增且 > 现有 build 4 |

## 范围

**纳入**：release-please 配置、单个 GitHub Actions workflow（三段 job）、ASC API Key 签名上传、质量门禁、build number 策略、Secrets 清单。

**不纳入**：fastlane match / 证书托管 repo、Android/Play 发布、上传后自动提交外部测试审核、Slack/邮件通知（YAGNI，后续可加）。

## 架构总览

平时 push main 只跑 release-please（廉价）。release-please 累积 Conventional Commits 到一个「Release PR」。**合并 Release PR** 那次 push 触发 release-please 创建 GitHub Release，其 output 驱动后续「门禁 → 构建上传」两 job。门禁失败则不上传。

```
push main
  └─ job① release-please (ubuntu, 总是跑)
        outputs: release_created / paths_released
        └─ job② gate (ubuntu, if release_created) : flutter analyze + flutter test
              └─ job③ testflight (macOS, needs②) : xcodebuild archive + export → altool upload
```

## 新增文件

```
release-please-config.json          # packages: { "apps/mobile": { release-type: "dart" } }
.release-please-manifest.json       # { "apps/mobile": "1.0.1" }
.github/workflows/release.yml       # 三段式 job
```

不改动现有 app 代码（Info.plist 的加密合规声明已于 2026-06-06 提交 fee9b1b 加入）。

## release-please 配置

- 使用 `googleapis/release-please-action@v4`（manifest 模式）。
- `release-please-config.json`：
  - `packages["apps/mobile"].release-type = "dart"`（更新 `apps/mobile/pubspec.yaml` 的 `version`）。
  - 可选 `bump-minor-pre-major`、`include-component-in-tag`（单包可关）。
- `.release-please-manifest.json` 初始 `{ "apps/mobile": "1.0.1" }`，与当前版本对齐；release-please 从下一个 Conventional Commit 起接管 bump。
- Conventional Commits：`feat→minor`、`fix→patch`、`feat!`/`BREAKING CHANGE→major`；中文描述不影响解析，CHANGELOG 用中文。

> 注：release-please dart 策略管 `x.y.z`（build-name）。pubspec 中 `+N` build 部分在 CI 由 `--build-number` 覆盖，无关紧要。manifest 模式的实际 output 名（`release_created` vs `paths_released`/`apps/mobile--release_created`）在实施时以 action 文档核实。

## Workflow（release.yml）

### job① release-please（ubuntu）
- 触发：`on: push: branches: [main]`。
- 步骤：checkout → `release-please-action@v4`（传 config/manifest 路径）。
- 输出供下游判断是否本次产生了 release。

### job② gate（ubuntu，`needs: [release-please]`，`if: release_created`）
- `subosito/flutter-action`（Flutter 3.44.x，channel stable，与本地一致）。
- `working-directory: apps/mobile`：`flutter pub get` → `flutter analyze` → `flutter test`。
- 失败即终止，不进 job③。

### job③ testflight（macos-latest，`needs: [gate]`）
- `subosito/flutter-action` + 选定 Xcode 版本（与本地 26.x 兼容）。
- 注入凭证：把 `ASC_API_KEY_P8` 写到 `~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8`。
- 计算 build number：`BUILD_NUMBER=$(date -u +%Y%m%d%H%M)`。
- 构建 + 导出 + 上传（复用本地已验证链路）：
  1. 预生成 Flutter iOS 产物（`flutter build ios --release --config-only` 或等价，确保 Generated.xcconfig/SPM 就绪）。
  2. `xcodebuild ... archive -allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID …`。
  3. `xcodebuild -exportArchive -exportOptionsPlist ExportOptions.plist`（method `app-store-connect`，team `62HCT6Q83X`，signingStyle automatic，同上 authenticationKey）。
  4. `xcrun altool --validate-app` →（可选）→ `xcrun altool --upload-app`，用 API Key，**带一次失败重试**。

## 签名与上传机制

- 全程 ASC API Key 认证，`-allowProvisioningUpdates` 让 Xcode 按需自动创建 Apple Distribution 证书与 App Store profile，无需 keychain 预置证书或 fastlane match。
- macOS runner PATH 纯净（无 Homebrew GNU rsync 3.4.x），不会触发本地遇到的 `exportArchive Copy failed`。
- ExportOptions.plist 由 workflow 内生成（或入库一份 CI 专用），含 `method=app-store-connect / teamID=62HCT6Q83X / signingStyle=automatic / manageAppVersionAndBuildNumber=false`。

## build number 策略

`--build-number=$(date -u +%Y%m%d%H%M)`：

- 单调递增（时间），天然大于现有最大 build（4），杜绝「build number 必须更大」被拒。
- 与 release-please 的 build-name 解耦：build-name 来自 pubspec（release-please 维护），build-number 由 CI 注入并覆盖。

## Secrets 清单（仓库 Settings → Secrets and variables → Actions）

| Secret | 值 | 敏感 |
|---|---|---|
| `ASC_API_KEY_P8` | `.p8` 文件全文 | 是（私钥） |
| `ASC_KEY_ID` | `K9ZD53WDUR` | 中 |
| `ASC_ISSUER_ID` | `86b89170-b4e7-476a-be04-695be19bb5bf` | 中 |

team id `62HCT6Q83X`、bundle id `com.kunish.freshPantry` 非敏感，可直接写入配置。

## 错误处理与边界

- **门禁失败**：Release 已由 release-please 创建，但不构建上传；修复后可手动重跑 job③（`workflow_dispatch` 或 re-run）。
- **altool 上传瞬时失败**：内置一次重试。
- **build number 冲突**：时间戳策略规避。
- **首次 distribution 证书自动创建**：依赖 API Key 权限（Admin/App Manager）；权限不足会在 archive 阶段报签名错误，需在 ASC 调整 Key 角色。
- **Xcode/Flutter 版本漂移**：workflow 固定 Flutter 与 Xcode 版本，避免 runner 默认版本变动导致构建差异。

## 实现选项（实施时定）

job③ 的 iOS 构建有两条等价路径，均满足「API Key 自动签名、无 match」：

1. **纯 `xcodebuild` + `altool`**（首选）：零额外依赖，最贴合本地已验证命令；需正确编排 Flutter 产物预生成与 xcodebuild archive。
2. **fastlane**（回退）：`app_store_connect_api_key` + `build_app`(gym, automatic + `-allowProvisioningUpdates`) + `upload_to_testflight`(pilot)；编排更省心，代价是引入 fastlane 依赖。

若路径 1 在 Flutter + xcodebuild archive 编排上遇到摩擦，切换路径 2。

## 验收标准

1. 合入若干 `feat:`/`fix:` 提交后，release-please 自动开出 Release PR，含正确的版本 bump 与中文 CHANGELOG。
2. 合并 Release PR 后，workflow 自动跑 analyze+test，通过后在 macOS 构建并成功上传一个新 build 到 TestFlight。
3. 新 build 的 build-name 来自 pubspec，build-number 为时间戳且大于历史值；TestFlight 不报 build number 冲突，不再要求加密合规声明。
4. 门禁失败时不产生 TestFlight 上传。
5. 全程不需要本地操作、不需要手动管理证书。
