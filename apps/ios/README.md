# Fresh Pantry — 原生 iOS app(SwiftUI)

家庭食材管理 app 的原生 SwiftUI 重写,取代 `apps/mobile` 的 Flutter 版(同 bundle id
`com.kunish.freshPantry`,只有原生这一份发 TestFlight)。架构与迁移记录见
[`docs/swiftui-migration/PLAN.md`](../../docs/swiftui-migration/PLAN.md)。

## 本地开发

工程文件用 [XcodeGen](https://github.com/yonyz/XcodeGen) 从 `project.yml` 生成,
`FreshPantry.xcodeproj` 已 gitignore——改了文件/依赖后须重跑 `xcodegen generate`。

```bash
cd apps/ios

# 1. 配置后端凭据(本地:复制模板填值;Secrets.plist 已 gitignore)
cp FreshPantry/Support/Secrets.example.plist FreshPantry/Support/Secrets.plist
#    至少填 SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY;其余留空用内置默认。
#    留空整个文件 = 本地模式(无登录/无同步),app 不崩。

# 2. 生成工程并打开
xcodegen generate
open FreshPantry.xcodeproj

# 命令行构建(模拟器,免签名)
xcodebuild build -project FreshPantry.xcodeproj -scheme FreshPantry \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO

# 跑测试
xcodebuild test -project FreshPantry.xcodeproj -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

> 监控(Sentry)只在 **Release** 构建启用(`#if !DEBUG`,对齐 Flutter 的
> `if (kDebugMode) return`),故本地 Debug/测试不会上报,也不会编译 Sentry 路径——
> 要验证 Sentry 须做 Release 构建。

## 发布流程(CI 自动发 TestFlight)

完全由 [release-please](https://github.com/googleapis/release-please) + GitHub Actions
驱动(`.github/workflows/release.yml`),平时零操作:

1. 用 **Conventional Commits** 提交(`feat:` → minor、`fix:` → patch、`feat!`/`BREAKING CHANGE` → major;中文描述不影响解析)。
2. push 到 `main` → release-please 累积提交到一个 **Release PR**(自动 bump 版本 + 生成中文 CHANGELOG),平时只跑这一段(便宜的 ubuntu job)。
3. **合并 Release PR** → 触发 `testflight` job(macOS):生成工程 + Secrets.plist → 跑测试门禁 → archive/签名/导出 → 上传 TestFlight → 传 dSYM 到 Sentry。
4. 在 App Store Connect → TestFlight 看到新 build(版本号来自 `version.txt`,build 号为 UTC 时间戳)。

也可在 Actions 页 **手动 `workflow_dispatch`** 重跑(用当前 `version.txt` 版本 + 新时间戳 build 号),用于失败重试或临时发一版。

### 版本号

- **单一真源 = `apps/ios/version.txt`**,由 release-please 维护(随 `.release-please-manifest.json` 同步)。
- `project.yml` 的 `MARKETING_VERSION` 只是本地默认;CI 构建时以 `MARKETING_VERSION=$(cat version.txt)` 注入覆盖。
- build number 不入库:CI 用 `date -u +%Y%m%d%H%M`,单调递增,天然规避 TestFlight「build 号必须更大」。
- git tag 沿用 `fresh_pantry-v<version>`(release-please component=`fresh_pantry`),与历史标签连续。

## 签名:ASC API Key 自动签名(无需手动管描述文件)

CI 用 **App Store Connect API Key** + `xcodebuild -allowProvisioningUpdates`:Xcode 按需
自动创建/续期 **Apple Distribution 证书**与 **App Store provisioning profile**。

- **不用** fastlane match、**不**托管证书 repo、**不**需要手动下载 `.mobileprovision`
  描述文件——所以仓库里没有、也不需要任何描述文件/证书。
- 本地开发用 `CODE_SIGN_STYLE: Automatic`(个人开发签名,模拟器免签)。
- 首次发版若报签名错,多半是 API Key 角色权限不足(需 Admin / App Manager 才能建分发证书),在 App Store Connect 调整 Key 角色即可。

## CI 需要的 GitHub Secrets

仓库 Settings → Secrets and variables → Actions(**均已配置**):

| Secret | 用途 |
|---|---|
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | API Key Issuer ID |
| `ASC_API_KEY_P8` | `.p8` 私钥全文(签名 + altool 上传) |
| `SUPABASE_URL` | 写入 CI 生成的 Secrets.plist |
| `SUPABASE_PUBLISHABLE_KEY` | 写入 CI 生成的 Secrets.plist |
| `SENTRY_AUTH_TOKEN` | sentry-cli 上传 dSYM(需 `project:releases` 权限) |

非敏感、直接写在配置里:team `62HCT6Q83X`、bundle id `com.kunish.freshPantry`、
Sentry org `kunish` / project `fresh_pantry`。`SENTRY_DSN` 不设 secret——CI 留空,
运行时退回 `AppConfig` 内置默认 DSN;CI 固定 `SENTRY_ENVIRONMENT=production`。

## Runner 与版本

iOS 26 / Swift 6 需要 Xcode 26,workflow 用 `runs-on: macos-26` + `xcode-version: latest-stable`。
若 GitHub 尚未提供 `macos-26` 镜像或其 stable Xcode 低于 26,改成带 Xcode 26 的可用
runner / 固定 `xcode-version` 即可(job 支持 re-run)。
