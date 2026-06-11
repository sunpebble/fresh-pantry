import SwiftUI

/// 个人资料查看页：从设置「我」卡片 push 进入。把散落在各处的身份信息——头像 /
/// 名称 / 昵称 / 账号 / 家庭角色 / 同步状态——收拢到一处，右上「编辑」进现有
/// `ProfileEditView` 表单。标准 iOS「查看 → 编辑」模式（如通讯录）。
///
/// 纯展示：家庭行 / 同步行 / 账号行的文案由调用方（`SettingsView`）算好注入，本
/// 视图不直接依赖 household / auth，只读 `ProfileStore` 的实时字段驱动头像与名称。
struct ProfileDetailView: View {
    let store: ProfileStore
    /// 家庭行（"小白家 · 管理员"）；nil 时不显示（未配后端 / 未加入家庭）。
    let familyLine: String?
    /// 同步状态（"已同步" / "待同步…"）；nil 时不显示（本地模式 / 未登录）。
    let syncLine: String?
    /// 账号行：签到邮箱，或"未配置后端·本地模式"等。
    let accountLine: String

    @State private var showEditor = false

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.xl) {
                hero
                infoCard
            }
            .padding(FkSpacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color.fkSurface)
        .navigationTitle("个人资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") { showEditor = true }
            }
        }
        .tint(.fkPrimary)
        .sheet(isPresented: $showEditor) {
            ProfileEditView(store: store, mode: .settings)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: FkSpacing.sm) {
            MemberAvatar(displayName: store.displayName, avatarURL: store.avatarURL, size: 96)
            Text(store.displayName.trimmed.isEmpty ? "未命名" : store.displayName.trimmed)
                .font(.fkHeadlineSmall)
                .foregroundStyle(Color.fkOnSurface)
            if !store.nickname.trimmed.isEmpty {
                Text("@\(store.nickname.trimmed)")
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
        .padding(.top, FkSpacing.lg)
    }

    // MARK: 信息卡片

    private var infoCard: some View {
        FkCard {
            VStack(spacing: 0) {
                infoRow(label: "账号", value: accountLine, systemImage: "envelope")
                if let familyLine {
                    rowDivider
                    infoRow(label: "家庭", value: familyLine, systemImage: "house")
                }
                if let syncLine {
                    rowDivider
                    infoRow(label: "状态", value: syncLine, systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.fkOutlineVariant)
            .frame(height: 1)
            .padding(.vertical, FkSpacing.xs)
    }

    private func infoRow(label: String, value: String, systemImage: String) -> some View {
        HStack(spacing: FkSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: FkSize.iconSm, weight: .semibold))
                .foregroundStyle(Color.fkPrimary)
                .frame(width: FkSize.settingsIconBox)
            Text(label)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            Spacer(minLength: FkSpacing.md)
            Text(value)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurface)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, FkSpacing.sm)
    }
}
