# third_party

Vendored, lightly-patched copies of upstream packages. Wired in via
`dependency_overrides` in `apps/mobile/pubspec.yaml`.

## workmanager_apple

Vendored from `workmanager_apple` **0.9.1+2** (the latest published version as of
2026-05-31). The only change is the **iOS Swift Package layout**.

### Why

Flutter's Swift Package Manager integration discovers a plugin's package at
`ios/<plugin_name>/Package.swift`. Upstream `workmanager_apple` ships its manifest
at `ios/Package.swift` (no `workmanager_apple/` subdirectory), so Flutter does not
detect SPM support and falls back to CocoaPods — emitting:

> The following plugins do not support Swift Package Manager for ios:
>   - workmanager_apple

Upstream `main` has the same layout, and there is no fixed release. Vendoring lets
the whole app stay on SPM (no Podfile) while keeping `workmanager`.

### What changed vs upstream

- Moved `ios/Package.swift` → `ios/workmanager_apple/Package.swift`.
- Moved `ios/Sources/workmanager_apple/**` → `ios/workmanager_apple/Sources/workmanager_apple/**`.
- Moved `ios/Resources/PrivacyInfo.xcprivacy` → alongside the sources at
  `ios/workmanager_apple/Sources/workmanager_apple/PrivacyInfo.xcprivacy`, and pointed
  the `Package.swift` resource and the `.podspec` `resource_bundles` at the new path.
- No Dart (`lib/`) or Swift source changes.

### Upgrading

When a release fixes the SPM layout
(track https://github.com/fluttercommunity/flutter_workmanager/issues), drop this
override and the vendored copy, then bump `workmanager` in `pubspec.yaml`. Until
then, re-vendor from the new version and re-apply the layout moves above.
