import Foundation

/// Pinyin-aware substring matching for the search bars (食谱/库存/全局/膳食计划).
///
/// The old predicate was `target.lowercased().contains(needle)` — Chinese-only,
/// so typing pinyin (`fanqie`, `fq`) never matched 番茄. This builds a per-string
/// "haystack" that unions three views of the text and matches the needle against
/// any of them:
///   1. the raw lowercased text         → keeps the original 中文子串 behaviour
///   2. whole-string ICU pinyin         → 全拼 `fanqie` + 首字母 `fq`
///   3. per-character pinyin + 多音字校正 → rescues readings ICU gets wrong (茄→qie)
///
/// Forms 2 & 3 are ADDITIVE (joined into one haystack): the override map can only
/// add a culinary reading, never remove ICU's, so it widens recall without
/// breaking any existing match. Pure (no SwiftUI/SwiftData) so it's unit-testable;
/// results are cached because the transliteration is recomputed on every keystroke
/// over a bounded vocabulary (recipe/ingredient names).
enum PinyinMatcher {
    /// Culinary polyphone corrections where ICU's default reading differs from the
    /// reading a cook would type. ADDITIVE — ICU's reading is still kept, so e.g.
    /// 薄片 ("baopian") and 薄荷 ("bohe") both match. Extend as the corpus needs.
    static let polyphoneOverrides: [Character: String] = [
        "茄": "qie", // 番茄 / 茄子 — ICU reads 雪茄's "jia"
        "蛤": "ge", // 蛤蜊 — ICU reads "ha"
        "薄": "bo", // 薄荷 — ICU reads "bao"
        "长": "chang", // 长豆角 / 长豇豆 — ICU reads "zhang"
    ]

    /// True when `text` matches `query` by raw substring, full pinyin, or pinyin
    /// initials. Empty query matches everything (mirrors the old early-return).
    /// `query` may already be trimmed/lowercased by the caller — re-normalizing a
    /// short query is cheap and keeps the call sites simple.
    static func matches(_ text: String, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        let hay = haystack(for: text)
        if hay.contains(needle) { return true }
        // Pinyin haystacks carry no spaces, so a spaced query ("fan qie") only
        // matches once de-spaced. Skip when the needle has no spaces to remove.
        let despaced = needle.replacingOccurrences(of: " ", with: "")
        return despaced != needle && hay.contains(despaced)
    }

    // MARK: Haystack

    /// Newline-joined union of raw text + whole-string pinyin forms + per-character
    /// (override-corrected) pinyin forms. The "\n" separator prevents a needle from
    /// matching across two forms (a search query is single-line / trimmed). Cached.
    static func haystack(for text: String) -> String {
        if let cached = cache.value(for: text) { return cached }
        let built = build(text)
        cache.set(built, for: text)
        return built
    }

    private static func build(_ text: String) -> String {
        var parts = [text.lowercased()]
        parts += pinyinForms(transliterate(text))

        var perCharacter: [String] = []
        for character in text {
            if let override = polyphoneOverrides[character] {
                perCharacter.append(override)
            } else {
                perCharacter += transliterate(String(character))
            }
        }
        parts += pinyinForms(perCharacter)

        return parts.joined(separator: "\n")
    }

    /// `[full pinyin, initials]` for the syllables, or `[]` when there are none
    /// (so a pure-ASCII / empty input contributes nothing extra here).
    private static func pinyinForms(_ syllables: [String]) -> [String] {
        guard !syllables.isEmpty else { return [] }
        let full = syllables.joined()
        let initials = syllables.compactMap(\.first).map(String.init).joined()
        return [full, initials]
    }

    /// Mandarin → ASCII pinyin syllables: lowercased, tone marks stripped, split on
    /// the spaces ICU inserts between syllables. Latin runs pass through as one
    /// token (so they contribute their own initial). Empty when transforms fail.
    private static func transliterate(_ text: String) -> [String] {
        guard let latin = text.applyingTransform(.mandarinToLatin, reverse: false),
              let ascii = latin.applyingTransform(.stripDiacritics, reverse: false)
        else { return [] }
        return ascii.lowercased().split(separator: " ").map(String.init)
    }

    // MARK: Cache

    private static let cache = HaystackCache()

    /// Lock-guarded string→haystack cache. `@unchecked Sendable` (the lock makes
    /// access safe) so the pure matcher stays usable from any actor, matching the
    /// project's existing locked-box pattern.
    private final class HaystackCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: String] = [:]

        func value(for key: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            return storage[key]
        }

        func set(_ value: String, for key: String) {
            lock.lock(); defer { lock.unlock() }
            storage[key] = value
        }
    }
}
