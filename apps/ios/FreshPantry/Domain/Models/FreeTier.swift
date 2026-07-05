import Foundation

/// 免费版配额（Pro 门控里唯一的纯逻辑，集中在这便于测试）。
enum FreeTier {
    /// 免费版库存条目上限。已有数据永不删、不锁读——只拦"新增"。
    static let inventoryLimit = 50

    static func inventoryLimitReached(isPro: Bool, currentCount: Int) -> Bool {
        !isPro && currentCount >= inventoryLimit
    }
}
