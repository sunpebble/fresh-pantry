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
                    featureRow("sparkles", String(localized: "paywall.feature.ai.title"), String(localized: "paywall.feature.ai.detail"))
                    featureRow("person.2", String(localized: "paywall.feature.household.title"), String(localized: "paywall.feature.household.detail"))
                    featureRow("calendar", String(localized: "paywall.feature.mealPlan.title"), String(localized: "paywall.feature.mealPlan.detail"))
                    featureRow("archivebox", String(localized: "paywall.feature.inventory.title"), String(localized: "paywall.feature.inventory.detail \(FreeTier.inventoryLimit)"))
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
                                    Text("paywall.purchase.unlocked")
                                } else if let product = proStore.product {
                                    Text("paywall.purchase.buy \(product.displayPrice)")
                                } else if proStore.isLoadingProduct || !proStore.didLoadProduct {
                                    Text("paywall.purchase.loading")
                                } else {
                                    Text("paywall.purchase.unavailable")
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
                        Text("paywall.restore")
                            .font(.fkBodyMedium)
                            .foregroundStyle(isPurchasing ? Color.fkOutline : Color.fkPrimary)
                    }
                    .disabled(isPurchasing)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("paywall.footer.note")
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
            .navigationTitle("paywall.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("paywall.close") { dismiss() }
                }
            }
            .tint(.fkPrimary)
            .task { await proStore.loadProduct() }
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
            Text("paywall.locked.description \(featureName)")
        } actions: {
            Button("paywall.locked.learnMore") { showPaywall = true }
                .buttonStyle(.borderedProminent)
                .tint(.fkPrimary)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(proStore: proStore)
        }
    }
}
