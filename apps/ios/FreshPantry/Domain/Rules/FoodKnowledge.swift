import Foundation

/// Smart defaults for a food name keyword.
struct FoodDefaults: Equatable, Sendable {
    let category: String
    let storage: IconType
    let shelfLifeDays: Int

    init(_ category: String, _ storage: IconType, _ shelfLifeDays: Int) {
        self.category = category
        self.storage = storage
        self.shelfLifeDays = shelfLifeDays
    }
}

/// Name-keyword knowledge base ported VERBATIM from `lib/data/food_knowledge.dart`.
///
/// Entries are stored as an ORDERED array (not a dictionary) because the Dart
/// `lookup`/`englishName` use a strict `>` length comparison while iterating in
/// insertion order — on a length tie the FIRST-declared key wins. A Swift
/// dictionary's unordered iteration would break that determinism.
enum FoodKnowledge {
    static let entries: [(key: String, value: FoodDefaults)] = [
        // ── 乳品蛋类 → 冰箱 ──
        ("牛奶", FoodDefaults(FoodCategories.dairyAndEggs, .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("酸奶", FoodDefaults(FoodCategories.dairyAndEggs, .fridge, 14)), // i18n:ignore domain matching data, not UI text
        ("奶酪", FoodDefaults(FoodCategories.dairyAndEggs, .fridge, 30)), // i18n:ignore domain matching data, not UI text
        ("芝士", FoodDefaults(FoodCategories.dairyAndEggs, .fridge, 30)), // i18n:ignore domain matching data, not UI text
        ("黄油", FoodDefaults(FoodCategories.dairyAndEggs, .fridge, 60)), // i18n:ignore domain matching data, not UI text
        ("奶油", FoodDefaults(FoodCategories.dairyAndEggs, .fridge, 14)), // i18n:ignore domain matching data, not UI text
        ("鸡蛋", FoodDefaults(FoodCategories.dairyAndEggs, .fridge, 30)), // i18n:ignore domain matching data, not UI text
        ("鸭蛋", FoodDefaults(FoodCategories.dairyAndEggs, .fridge, 30)), // i18n:ignore domain matching data, not UI text
        ("蛋", FoodDefaults(FoodCategories.dairyAndEggs, .fridge, 30)), // i18n:ignore domain matching data, not UI text

        // ── 果蔬生鲜 → 冰箱 ──
        ("番茄", FoodDefaults("果蔬生鲜", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("西红柿", FoodDefaults("果蔬生鲜", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("菠菜", FoodDefaults("果蔬生鲜", .fridge, 3)), // i18n:ignore domain matching data, not UI text
        ("生菜", FoodDefaults("果蔬生鲜", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("白菜", FoodDefaults("果蔬生鲜", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("青菜", FoodDefaults("果蔬生鲜", .fridge, 3)), // i18n:ignore domain matching data, not UI text
        ("胡萝卜", FoodDefaults("果蔬生鲜", .fridge, 14)), // i18n:ignore domain matching data, not UI text
        ("萝卜", FoodDefaults("果蔬生鲜", .fridge, 14)), // i18n:ignore domain matching data, not UI text
        ("土豆", FoodDefaults("果蔬生鲜", .pantry, 21)), // i18n:ignore domain matching data, not UI text
        ("洋葱", FoodDefaults("果蔬生鲜", .pantry, 30)), // i18n:ignore domain matching data, not UI text
        ("大蒜", FoodDefaults("果蔬生鲜", .pantry, 30)), // i18n:ignore domain matching data, not UI text
        ("姜", FoodDefaults("果蔬生鲜", .pantry, 21)), // i18n:ignore domain matching data, not UI text
        ("黄瓜", FoodDefaults("果蔬生鲜", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("茄子", FoodDefaults("果蔬生鲜", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("辣椒", FoodDefaults("果蔬生鲜", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("青椒", FoodDefaults("果蔬生鲜", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("西兰花", FoodDefaults("果蔬生鲜", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("花菜", FoodDefaults("果蔬生鲜", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("芹菜", FoodDefaults("果蔬生鲜", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("蘑菇", FoodDefaults("果蔬生鲜", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("豆腐", FoodDefaults("果蔬生鲜", .fridge, 3)), // i18n:ignore domain matching data, not UI text
        ("苹果", FoodDefaults("果蔬生鲜", .fridge, 14)), // i18n:ignore domain matching data, not UI text
        ("香蕉", FoodDefaults("果蔬生鲜", .pantry, 5)), // i18n:ignore domain matching data, not UI text
        ("橙子", FoodDefaults("果蔬生鲜", .fridge, 14)), // i18n:ignore domain matching data, not UI text
        ("柠檬", FoodDefaults("果蔬生鲜", .fridge, 21)), // i18n:ignore domain matching data, not UI text
        ("葡萄", FoodDefaults("果蔬生鲜", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("草莓", FoodDefaults("果蔬生鲜", .fridge, 3)), // i18n:ignore domain matching data, not UI text
        ("蓝莓", FoodDefaults("果蔬生鲜", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("西瓜", FoodDefaults("果蔬生鲜", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("牛油果", FoodDefaults("果蔬生鲜", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("芒果", FoodDefaults("果蔬生鲜", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("豆芽", FoodDefaults("果蔬生鲜", .fridge, 2)), // i18n:ignore domain matching data, not UI text
        ("韭菜", FoodDefaults("果蔬生鲜", .fridge, 3)), // i18n:ignore domain matching data, not UI text
        ("葱", FoodDefaults("果蔬生鲜", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("香菜", FoodDefaults("果蔬生鲜", .fridge, 5)), // i18n:ignore domain matching data, not UI text

        // ── 肉类海鲜 → 冰箱 ──
        ("鸡肉", FoodDefaults("肉类海鲜", .fridge, 2)), // i18n:ignore domain matching data, not UI text
        ("鸡胸", FoodDefaults("肉类海鲜", .fridge, 2)), // i18n:ignore domain matching data, not UI text
        ("鸡腿", FoodDefaults("肉类海鲜", .fridge, 2)), // i18n:ignore domain matching data, not UI text
        ("鸡翅", FoodDefaults("肉类海鲜", .fridge, 2)), // i18n:ignore domain matching data, not UI text
        ("猪肉", FoodDefaults("肉类海鲜", .fridge, 3)), // i18n:ignore domain matching data, not UI text
        ("排骨", FoodDefaults("肉类海鲜", .fridge, 2)), // i18n:ignore domain matching data, not UI text
        ("五花肉", FoodDefaults("肉类海鲜", .fridge, 3)), // i18n:ignore domain matching data, not UI text
        ("牛肉", FoodDefaults("肉类海鲜", .fridge, 3)), // i18n:ignore domain matching data, not UI text
        ("牛排", FoodDefaults("肉类海鲜", .fridge, 90)), // i18n:ignore domain matching data, not UI text
        ("羊肉", FoodDefaults("肉类海鲜", .fridge, 3)), // i18n:ignore domain matching data, not UI text
        ("培根", FoodDefaults("肉类海鲜", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("香肠", FoodDefaults("肉类海鲜", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("火腿", FoodDefaults("肉类海鲜", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("鱼", FoodDefaults("肉类海鲜", .fridge, 2)), // i18n:ignore domain matching data, not UI text
        ("三文鱼", FoodDefaults("肉类海鲜", .fridge, 2)), // i18n:ignore domain matching data, not UI text
        ("虾", FoodDefaults("肉类海鲜", .fridge, 90)), // i18n:ignore domain matching data, not UI text
        ("虾仁", FoodDefaults("肉类海鲜", .fridge, 90)), // i18n:ignore domain matching data, not UI text
        ("蟹", FoodDefaults("肉类海鲜", .fridge, 2)), // i18n:ignore domain matching data, not UI text
        ("贝", FoodDefaults("肉类海鲜", .fridge, 2)), // i18n:ignore domain matching data, not UI text
        ("肉丸", FoodDefaults("肉类海鲜", .fridge, 60)), // i18n:ignore domain matching data, not UI text
        ("饺子", FoodDefaults("肉类海鲜", .fridge, 90)), // i18n:ignore domain matching data, not UI text
        ("馄饨", FoodDefaults("肉类海鲜", .fridge, 90)), // i18n:ignore domain matching data, not UI text

        // ── 其他 → 食品柜 ──
        ("米", FoodDefaults(FoodCategories.other, .pantry, 180)), // i18n:ignore domain matching data, not UI text
        ("大米", FoodDefaults(FoodCategories.other, .pantry, 180)), // i18n:ignore domain matching data, not UI text
        ("面条", FoodDefaults(FoodCategories.other, .pantry, 180)), // i18n:ignore domain matching data, not UI text
        ("挂面", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("意面", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("意大利面", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("面粉", FoodDefaults(FoodCategories.other, .pantry, 180)), // i18n:ignore domain matching data, not UI text
        ("面包", FoodDefaults(FoodCategories.other, .pantry, 3)), // i18n:ignore domain matching data, not UI text
        ("法棍", FoodDefaults(FoodCategories.other, .pantry, 2)), // i18n:ignore domain matching data, not UI text
        ("吐司", FoodDefaults(FoodCategories.other, .pantry, 5)), // i18n:ignore domain matching data, not UI text
        ("饼干", FoodDefaults(FoodCategories.other, .pantry, 90)), // i18n:ignore domain matching data, not UI text
        ("麦片", FoodDefaults(FoodCategories.other, .pantry, 180)), // i18n:ignore domain matching data, not UI text
        ("燕麦", FoodDefaults(FoodCategories.other, .pantry, 180)), // i18n:ignore domain matching data, not UI text
        ("糖", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("白糖", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("红糖", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("蜂蜜", FoodDefaults(FoodCategories.other, .pantry, 730)), // i18n:ignore domain matching data, not UI text
        ("食用油", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("橄榄油", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("花生油", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("菜籽油", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("醋", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("酱油", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("料酒", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("罐头", FoodDefaults(FoodCategories.other, .pantry, 730)), // i18n:ignore domain matching data, not UI text
        ("咖啡", FoodDefaults(FoodCategories.other, .pantry, 180)), // i18n:ignore domain matching data, not UI text
        ("茶", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("茶叶", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("巧克力", FoodDefaults(FoodCategories.other, .pantry, 180)), // i18n:ignore domain matching data, not UI text
        ("坚果", FoodDefaults(FoodCategories.other, .pantry, 90)), // i18n:ignore domain matching data, not UI text
        ("花生", FoodDefaults(FoodCategories.other, .pantry, 90)), // i18n:ignore domain matching data, not UI text
        ("核桃", FoodDefaults(FoodCategories.other, .pantry, 90)), // i18n:ignore domain matching data, not UI text
        ("芝麻", FoodDefaults(FoodCategories.other, .pantry, 180)), // i18n:ignore domain matching data, not UI text
        ("淀粉", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("番茄酱", FoodDefaults(FoodCategories.other, .pantry, 180)), // i18n:ignore domain matching data, not UI text
        ("豆瓣酱", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("老干妈", FoodDefaults(FoodCategories.other, .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("方便面", FoodDefaults(FoodCategories.other, .pantry, 180)), // i18n:ignore domain matching data, not UI text
        ("速冻", FoodDefaults(FoodCategories.other, .fridge, 180)), // i18n:ignore domain matching data, not UI text
        ("冰淇淋", FoodDefaults(FoodCategories.other, .fridge, 180)), // i18n:ignore domain matching data, not UI text

        // ── 香料草本 → 食品柜 ──
        ("盐", FoodDefaults("香料草本", .pantry, 1825)), // i18n:ignore domain matching data, not UI text
        ("海盐", FoodDefaults("香料草本", .pantry, 1825)), // i18n:ignore domain matching data, not UI text
        ("胡椒", FoodDefaults("香料草本", .pantry, 730)), // i18n:ignore domain matching data, not UI text
        ("黑胡椒", FoodDefaults("香料草本", .pantry, 730)), // i18n:ignore domain matching data, not UI text
        ("白胡椒", FoodDefaults("香料草本", .pantry, 730)), // i18n:ignore domain matching data, not UI text
        ("花椒", FoodDefaults("香料草本", .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("八角", FoodDefaults("香料草本", .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("桂皮", FoodDefaults("香料草本", .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("香叶", FoodDefaults("香料草本", .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("孜然", FoodDefaults("香料草本", .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("辣椒粉", FoodDefaults("香料草本", .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("咖喱", FoodDefaults("香料草本", .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("五香粉", FoodDefaults("香料草本", .pantry, 365)), // i18n:ignore domain matching data, not UI text
        ("香草", FoodDefaults("香料草本", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("薄荷", FoodDefaults("香料草本", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("迷迭香", FoodDefaults("香料草本", .fridge, 7)), // i18n:ignore domain matching data, not UI text
        ("罗勒", FoodDefaults("香料草本", .fridge, 5)), // i18n:ignore domain matching data, not UI text
        ("香草精", FoodDefaults("香料草本", .pantry, 365)), // i18n:ignore domain matching data, not UI text
    ]

    // ── Chinese → English food name mapping for API search ──
    static let englishNames: [(key: String, value: String)] = [
        ("牛奶", "milk"), // i18n:ignore domain matching data, not UI text
        ("酸奶", "yogurt"), // i18n:ignore domain matching data, not UI text
        ("奶酪", "cheese"), // i18n:ignore domain matching data, not UI text
        ("芝士", "cheese"), // i18n:ignore domain matching data, not UI text
        ("黄油", "butter"), // i18n:ignore domain matching data, not UI text
        ("奶油", "cream"), // i18n:ignore domain matching data, not UI text
        ("鸡蛋", "egg"), // i18n:ignore domain matching data, not UI text
        ("鸭蛋", "egg"), // i18n:ignore domain matching data, not UI text
        ("蛋", "egg"), // i18n:ignore domain matching data, not UI text
        ("番茄", "tomato"), // i18n:ignore domain matching data, not UI text
        ("西红柿", "tomato"), // i18n:ignore domain matching data, not UI text
        ("菠菜", "spinach"), // i18n:ignore domain matching data, not UI text
        ("生菜", "lettuce"), // i18n:ignore domain matching data, not UI text
        ("白菜", "cabbage"), // i18n:ignore domain matching data, not UI text
        ("青菜", "greens"), // i18n:ignore domain matching data, not UI text
        ("胡萝卜", "carrot"), // i18n:ignore domain matching data, not UI text
        ("萝卜", "radish"), // i18n:ignore domain matching data, not UI text
        ("土豆", "potato"), // i18n:ignore domain matching data, not UI text
        ("洋葱", "onion"), // i18n:ignore domain matching data, not UI text
        ("大蒜", "garlic"), // i18n:ignore domain matching data, not UI text
        ("姜", "ginger"), // i18n:ignore domain matching data, not UI text
        ("黄瓜", "cucumber"), // i18n:ignore domain matching data, not UI text
        ("茄子", "eggplant"), // i18n:ignore domain matching data, not UI text
        ("辣椒", "chili"), // i18n:ignore domain matching data, not UI text
        ("青椒", "pepper"), // i18n:ignore domain matching data, not UI text
        ("西兰花", "broccoli"), // i18n:ignore domain matching data, not UI text
        ("花菜", "cauliflower"), // i18n:ignore domain matching data, not UI text
        ("芹菜", "celery"), // i18n:ignore domain matching data, not UI text
        ("蘑菇", "mushroom"), // i18n:ignore domain matching data, not UI text
        ("豆腐", "tofu"), // i18n:ignore domain matching data, not UI text
        ("苹果", "apple"), // i18n:ignore domain matching data, not UI text
        ("香蕉", "banana"), // i18n:ignore domain matching data, not UI text
        ("橙子", "orange"), // i18n:ignore domain matching data, not UI text
        ("柠檬", "lemon"), // i18n:ignore domain matching data, not UI text
        ("葡萄", "grape"), // i18n:ignore domain matching data, not UI text
        ("草莓", "strawberry"), // i18n:ignore domain matching data, not UI text
        ("蓝莓", "blueberry"), // i18n:ignore domain matching data, not UI text
        ("西瓜", "watermelon"), // i18n:ignore domain matching data, not UI text
        ("牛油果", "avocado"), // i18n:ignore domain matching data, not UI text
        ("芒果", "mango"), // i18n:ignore domain matching data, not UI text
        ("鸡肉", "chicken"), // i18n:ignore domain matching data, not UI text
        ("鸡胸", "chicken breast"), // i18n:ignore domain matching data, not UI text
        ("鸡腿", "chicken leg"), // i18n:ignore domain matching data, not UI text
        ("鸡翅", "chicken wing"), // i18n:ignore domain matching data, not UI text
        ("猪肉", "pork"), // i18n:ignore domain matching data, not UI text
        ("排骨", "ribs"), // i18n:ignore domain matching data, not UI text
        ("五花肉", "pork belly"), // i18n:ignore domain matching data, not UI text
        ("牛肉", "beef"), // i18n:ignore domain matching data, not UI text
        ("牛排", "steak"), // i18n:ignore domain matching data, not UI text
        ("羊肉", "lamb"), // i18n:ignore domain matching data, not UI text
        ("培根", "bacon"), // i18n:ignore domain matching data, not UI text
        ("香肠", "sausage"), // i18n:ignore domain matching data, not UI text
        ("火腿", "ham"), // i18n:ignore domain matching data, not UI text
        ("鱼", "fish"), // i18n:ignore domain matching data, not UI text
        ("三文鱼", "salmon"), // i18n:ignore domain matching data, not UI text
        ("虾", "shrimp"), // i18n:ignore domain matching data, not UI text
        ("蟹", "crab"), // i18n:ignore domain matching data, not UI text
        ("米", "rice"), // i18n:ignore domain matching data, not UI text
        ("大米", "rice"), // i18n:ignore domain matching data, not UI text
        ("面条", "noodle"), // i18n:ignore domain matching data, not UI text
        ("意面", "pasta"), // i18n:ignore domain matching data, not UI text
        ("意大利面", "pasta"), // i18n:ignore domain matching data, not UI text
        ("面粉", "flour"), // i18n:ignore domain matching data, not UI text
        ("面包", "bread"), // i18n:ignore domain matching data, not UI text
        ("法棍", "baguette"), // i18n:ignore domain matching data, not UI text
        ("糖", "sugar"), // i18n:ignore domain matching data, not UI text
        ("蜂蜜", "honey"), // i18n:ignore domain matching data, not UI text
        ("橄榄油", "olive oil"), // i18n:ignore domain matching data, not UI text
        ("巧克力", "chocolate"), // i18n:ignore domain matching data, not UI text
        ("咖啡", "coffee"), // i18n:ignore domain matching data, not UI text
        ("茶", "tea"), // i18n:ignore domain matching data, not UI text
    ]

    private static let displayNameKeys: [(key: String, value: String)] = [
        ("香菇", "food.name.shiitakeMushroom"), // i18n:ignore data identity lookup, not UI text
        ("菜籽油", "food.name.rapeseedOil"), // i18n:ignore data identity lookup, not UI text
        ("排骨", "food.name.porkRibs"), // i18n:ignore data identity lookup, not UI text
        ("白糖", "food.name.whiteSugar"), // i18n:ignore data identity lookup, not UI text
        ("老抽", "food.name.darkSoySauce"), // i18n:ignore data identity lookup, not UI text
        ("菜椒", "food.name.bellPepper"), // i18n:ignore data identity lookup, not UI text
        ("味精", "food.name.msg"), // i18n:ignore data identity lookup, not UI text
        ("鸡精", "food.name.chickenBouillon"), // i18n:ignore data identity lookup, not UI text
        ("盐", "food.name.salt"), // i18n:ignore data identity lookup, not UI text
        ("醋", "food.name.vinegar"), // i18n:ignore data identity lookup, not UI text
    ]

    /// Keyword match rule. Multi-character keywords match as substrings (so
    /// "猪肉末" resolves via "猪肉"), but single-character keywords must match the
    /// whole name exactly (avoids "蛋糕"→"蛋", "鱼丸"→"鱼").
    static func keyMatches(_ lower: String, _ key: String) -> Bool {
        if key.count == 1 { return lower == key }
        return lower.contains(key)
    }

    /// Look up the English name for a Chinese food name (longest match wins).
    static func englishName(_ name: String) -> String? {
        let lower = name.trimmed.lowercased()
        if lower.isEmpty { return nil }
        var best: String?
        var bestLen = 0
        for entry in englishNames where keyMatches(lower, entry.key) && entry.key.count > bestLen {
            best = entry.value
            bestLen = entry.key.count
        }
        return best
    }

    /// Localized display-only name for known food data. Matching and persistence keep
    /// the original user-entered name.
    static func displayName(_ name: String) -> String {
        let trimmed = name.trimmed
        guard let key = displayNameKey(for: trimmed) else { return name }
        return Bundle.main.localizedString(forKey: key, value: trimmed, table: nil)
    }

    private static func displayNameKey(for name: String) -> String? {
        let lower = name.lowercased()
        if lower.isEmpty { return nil }
        var best: String?
        var bestLen = 0
        for entry in displayNameKeys where keyMatches(lower, entry.key) && entry.key.count > bestLen {
            best = entry.value
            bestLen = entry.key.count
        }
        return best
    }

    /// Look up smart defaults for an ingredient name (longest match wins).
    static func lookup(_ name: String) -> FoodDefaults? {
        let lower = name.trimmed.lowercased()
        if lower.isEmpty { return nil }
        var best: FoodDefaults?
        var bestLen = 0
        for entry in entries where keyMatches(lower, entry.key) && entry.key.count > bestLen {
            best = entry.value
            bestLen = entry.key.count
        }
        return best
    }

    /// Resolve the stable app category for a food name.
    static func categoryFor(_ name: String, fallback: String = FoodCategories.other) -> String {
        let normalized = FoodCategories.normalize(lookup(name)?.category)
        return normalized ?? FoodCategories.dropdownValue(fallback)
    }

    /// Whether a food name is a known perishable per the knowledge base.
    static func isPerishableName(_ name: String) -> Bool {
        FoodCategories.isPerishable(lookup(name)?.category)
    }

    /// Common shelf life presets for quick-select UI.
    static let shelfLifePresets = [3, 7, 14, 30]

    /// Common units.
    static let units = ["个", "瓶", "袋", "盒", "包", "g", "kg", "ml", "L"] // i18n:ignore domain matching data, not UI text
}
