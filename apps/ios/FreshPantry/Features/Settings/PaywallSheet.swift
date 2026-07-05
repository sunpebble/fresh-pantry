import SwiftUI
import StoreKit

/// Pro 购买页。所有 Pro 门控统一弹这一张 sheet。
struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    let proStore: ProStore
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    featureRow("sparkles", "AI 助手", "粘贴文本一键入库、清冰箱生成菜谱")
                    featureRow("person.2", "家庭共享", "全家共用一份库存与购物清单")
                    featureRow("calendar", "周派餐", "按周安排每天做什么菜")
                    featureRow("archivebox", "不限量库存", "免费版可记录 \(FreeTier.inventoryLimit) 条")
                } header: {
                    Text("Fresh Pantry Pro")
                }
                .listRowBackground(Color.fkSurfaceContainerLowest)

                Section {
                    Button {
                        Task {
                            isPurchasing = true
                            await proStore.purchase()
                            isPurchasing = false
                            if proStore.isPro { dismiss() }
                        }
                    } label: {
                        HStack(spacing: FkSpacing.sm) {
                            if isPurchasing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "lock.open")
                            }
                            Group {
                                if proStore.isPro {
                                    Text("已解锁")
                                } else if let product = proStore.product {
                                    Text("一次买断 · \(product.displayPrice)")
                                } else {
                                    Text("加载中…")
                                }
                            }
                            .font(.fkBodyMedium)
                        }
                        .foregroundStyle(purchaseEnabled ? Color.fkPrimary : Color.fkOutline)
                    }
                    .disabled(!purchaseEnabled)

                    Button {
                        Task { await proStore.restore() }
                    } label: {
                        Text("恢复购买")
                            .font(.fkBodyMedium)
                            .foregroundStyle(isPurchasing ? Color.fkOutline : Color.fkPrimary)
                    }
                    .disabled(isPurchasing)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("一次购买，长期使用，支持家庭共享。")
                        if let notice = proStore.purchaseNotice {
                            Text(notice)
                        }
                        if let error = proStore.purchaseError {
                            Text(error).foregroundStyle(Color.fkDanger)
                        }
                    }
                }
                .listRowBackground(Color.fkSurfaceContainerLowest)
            }
            .scrollContentBackground(.hidden)
            .background(Color.fkSurface)
            .navigationTitle("升级 Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .tint(.fkPrimary)
        }
    }

    private var purchaseEnabled: Bool {
        !proStore.isPro && proStore.product != nil && !isPurchasing
    }

    private func featureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: FkSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: FkSize.iconSm, weight: .semibold))
                .foregroundStyle(Color.fkPrimary)
                .frame(width: FkSize.settingsIconBox)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.fkTitleSmall)
                    .foregroundStyle(Color.fkOnSurface)
                Text(detail)
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
        }
    }
}

/// 整页锁定占位（MealPlan 等整页门控用）。
struct ProLockedView: View {
    let featureName: String
    let proStore: ProStore
    @State private var showPaywall = false

    var body: some View {
        ContentUnavailableView {
            Label(featureName, systemImage: "lock")
        } description: {
            Text("\(featureName)是 Pro 功能。")
        } actions: {
            Button("了解 Pro") { showPaywall = true }
                .buttonStyle(.borderedProminent)
                .tint(.fkPrimary)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(proStore: proStore)
        }
    }
}
