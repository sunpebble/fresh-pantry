# Fresh Pantry — 原生 iOS app(SwiftUI)

家庭食材管理 app 的原生 SwiftUI 重写,取代 `apps/mobile` 的 Flutter 版(bundle id
`com.sunpebble.freshpantry`,只有原生这一份发 TestFlight)。架构与迁移记录见
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

### 编辑器/SourceKit 索引(sourcekit-lsp)

这是 **Xcode 工程**(非 SwiftPM),sourcekit-lsp 没有 `buildServer.json` 就只能做
**单文件分析**——看不到编译参数和整模块源文件,于是在编辑器 / Claude Code 里狂报
**假阳性**:`No such module 'UIKit'/'Testing'/'XCTest'/'Supabase'/'Sentry'`、
`Cannot find type 'Recipe'/'MealPlanRecord' ... in scope`、`#Predicate` 宏展开失败等。
这些不是真错误(`xcodebuild` 一直通过),但会淹没真实诊断。

修复 = 用 [`xcode-build-server`](https://github.com/SolaWing/xcode-build-server) 给
sourcekit-lsp 喂构建上下文。**一次性**本地设置(随 `xcodegen generate` 重生不失效,
因路径稳定;`buildServer.json` 已 gitignore——含机器特定绝对路径):

```bash
brew install xcode-build-server

# 关键:buildServer.json 必须在「仓库根」生成——sourcekit-lsp 的工作区根是仓库根
# (Claude Code / 多数编辑器都从这里打开),只在根目录找此文件,放进 apps/ios 不生效。
cd <repo-root>   # 即本仓库根目录,不是 apps/ios
xcode-build-server config -scheme FreshPantry -project apps/ios/FreshPantry.xcodeproj

# 构建一次填充「索引库 + 编译参数日志」(用默认 DerivedData,勿加 -derivedDataPath)。
# build-for-testing 会连测试 bundle 一起索引,顺带消掉测试文件里的 Testing/XCTest 假阳性。
xcodebuild build-for-testing -project apps/ios/FreshPantry.xcodeproj -scheme FreshPantry \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

大改动后重新 `xcodebuild build` 即可刷新索引;只有移动/重命名工程时才需重跑
`xcode-build-server config`。改完后重启编辑器的 LSP(或新开会话)让其重新发现配置。

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

## 签名：自动签名（固定 Distribution 证书 + 云 provisioning）

与 dayroll / simmer / sleeptab 完全一致：`apple-actions/import-codesign-certs` 导入
org 级共享的 Apple Distribution 证书作为固定签名身份，archive/export 以
`CODE_SIGN_STYLE=Automatic` + `-allowProvisioningUpdates` + ASC API key 云签名
按需生成 profile，**无需预生成或维护 provisioning profile**。

- 固定证书解决了 ephemeral runner 自动签名反复新建证书、撞账户证书配额的问题
  （"Your account has reached the maximum number of certificates"）。
- 注意：App ID 的 **App Group 关联须在 developer.apple.com 手动 Configure**，
  云签名不会自动补（只勾能力不关联 group 会签名失败）。

## CI 需要的 GitHub Secrets

签名/上传相关的 6 个为 **org 级 secrets**（sunpebble 全部仓库共享，均已配置）：

| Secret（org 级） | 用途 |
|---|---|
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | API Key Issuer ID |
| `ASC_API_KEY_P8` | `.p8` 私钥全文（云签名 + TestFlight 上传） |
| `APPLE_TEAM_ID` | 开发者 Team ID |
| `DIST_CERT_P12` | Apple Distribution 证书（含私钥）的 base64 |
| `DIST_CERT_PASSWORD` | `.p12` 导出密码 |

仓库级 secrets（FreshPantry 特有）：

| Secret（repo 级） | 用途 |
|---|---|
| `SUPABASE_URL` | 写入 CI 生成的 Secrets.plist |
| `SUPABASE_PUBLISHABLE_KEY` | 写入 CI 生成的 Secrets.plist |
| `SENTRY_AUTH_TOKEN` | sentry-cli 上传 dSYM（需 `project:releases` 权限） |

TestFlight 上传用 `apple-actions/upload-testflight-build`（`wait-for-processing`
关闭：action 预签的短时 JWT 会在处理轮询期间过期，上传成功也报 401）。

非敏感、直接写在配置里：team `62HCT6Q83X`、bundle id `com.sunpebble.freshpantry`、
Sentry org `kunish` / project `fresh_pantry`。`SENTRY_DSN` 不设 secret——CI 留空，
运行时退回 `AppConfig` 内置默认 DSN；CI 固定 `SENTRY_ENVIRONMENT=production`。

## Runner 与版本

iOS 26 / Swift 6 需要 Xcode 26,workflow 用 `runs-on: macos-26` + `xcode-version: latest-stable`。
若 GitHub 尚未提供 `macos-26` 镜像或其 stable Xcode 低于 26,改成带 Xcode 26 的可用
runner / 固定 `xcode-version` 即可(job 支持 re-run)。

## 常见构建问题（Troubleshooting）

### (a) XCBBuildService 脏状态（构建卡死 / SIGKILL 后）

Xcode 被强杀后 XCBBuildService 可能处于不一致状态，导致下次构建卡死不动。

```bash
pkill -9 XCBBuildService
rm -rf ~/Library/Developer/Xcode/DerivedData
```

重新打开 Xcode 并构建即可恢复。

### (b) Sentry xcframework 下载卡死（"network connection was lost"）

`xcodebuild -resolvePackageDependencies` 或构建时若 Sentry 二进制 xcframework 下载中途报
`"The network connection was lost"` 而卡住，重跑包解析即可（会重试下载）：

```bash
# 在 apps/ios 目录执行
xcodebuild -resolvePackageDependencies -project FreshPantry.xcodeproj -scheme FreshPantry
```

若仍失败，清除 SPM 缓存再试：

```bash
rm -rf ~/Library/Caches/org.swift.swiftpm
```

### (c) "destination ambiguous"（模拟器名重复）

```
error: destination "iPhone 17 Pro" is ambiguous; please specify the UDID
```

多个 iOS runtime 安装时同名模拟器会触发 ambiguous 错误，改用 UDID：

```bash
# 列出可用 iPhone 模拟器及 UDID
xcrun simctl list devices available | grep iPhone

# 用 UDID 指定目标
xcodebuild test -project FreshPantry.xcodeproj -scheme FreshPantry \
  -destination 'platform=iOS Simulator,id=<UDID>'
```

CI 的 `Run tests (gate)` step 已自动取第一个可用 iPhone 模拟器的 UDID，本地同理：

```bash
UDID=$(xcrun simctl list devices available -j | python3 -c \
  "import json,sys; d=json.load(sys.stdin)['devices']; \
   c=[v for rt in d for v in d[rt] if v.get('isAvailable') and v['name'].startswith('iPhone')]; \
   print(c[0]['udid'] if c else '')")
```

### (d) xcode-build-server：buildServer.json 须在仓库根生成

`xcode-build-server` 必须在**仓库根目录**（非 `apps/ios/`）运行才有效——sourcekit-lsp 从
工作区根（仓库根）查找 `buildServer.json`，放在子目录不生效：

```bash
# 错误示例（不生效）
cd apps/ios && xcode-build-server config -scheme FreshPantry -project FreshPantry.xcodeproj

# 正确：在仓库根执行
cd <repo-root>
xcode-build-server config -scheme FreshPantry -project apps/ios/FreshPantry.xcodeproj
```

完整 LSP 索引设置见上方 [编辑器/SourceKit 索引](#编辑器sourckit-索引sourcekit-lsp) 一节。
