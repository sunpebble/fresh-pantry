import Foundation
import StoreKit

/// Pro 买断状态（StoreKit 2）。启动时读一次 entitlement，常驻监听交易更新；
/// 购买/恢复的错误以中文短句暴露给 PaywallSheet 就地展示。
@Observable
@MainActor
final class ProStore {
    static let productID = "freshpantry.pro"

    private(set) var isPro = false
    private(set) var product: Product?
    private(set) var purchaseError: String?
    /// 非错误的中性提示（如 Ask to Buy 待批准），PaywallSheet 就地展示。
    private(set) var purchaseNotice: String?
    /// 预览/UI 测试注入：非 nil 时锁死 isPro，start() 不再改写。
    private let isProOverride: Bool?
    private var updatesTask: Task<Void, Never>?

    init(isProForPreview: Bool? = nil) {
        self.isProOverride = isProForPreview
        if let isProForPreview { self.isPro = isProForPreview }
    }

    /// App 根 .task 调一次：刷 entitlement、拉商品、挂交易监听。
    func start() async {
        guard isProOverride == nil else { return }
        await refreshEntitlement()
        product = try? await Product.products(for: [Self.productID]).first
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let tx) = update {
                    await tx.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }

    func refreshEntitlement() async {
        guard isProOverride == nil else { return }
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let tx) = entitlement,
               tx.productID == Self.productID, tx.revocationDate == nil {
                isPro = true
                return
            }
        }
        isPro = false
    }

    func purchase() async {
        purchaseError = nil
        purchaseNotice = nil
        guard let product else {
            purchaseError = "商品信息还没加载好，稍后再试"
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    await refreshEntitlement()
                }
            case .pending:
                purchaseNotice = "购买请求已提交，批准后自动解锁"
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "购买没有完成：\(error.localizedDescription)"
        }
    }

    func restore() async {
        purchaseError = nil
        purchaseNotice = nil
        try? await AppStore.sync()
        await refreshEntitlement()
        if !isPro { purchaseError = "没有找到可恢复的购买" }
    }
}
