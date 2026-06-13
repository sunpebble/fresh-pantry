import Foundation
import Testing
@testable import FreshPantry

/// Unit tests for the pure `PinyinMatcher` search rule — pinyin 全拼 / 首字母 / 多音字
/// 校正, plus the preserved 中文子串 and latin behaviour.
struct PinyinMatcherTests {
    // MARK: 全拼 (full pinyin)

    @Test func fullPinyinMatchesAcrossSyllables() {
        #expect(PinyinMatcher.matches("番茄炒蛋", query: "fanqie"))
        #expect(PinyinMatcher.matches("西红柿炒鸡蛋", query: "xihongshi"))
        #expect(PinyinMatcher.matches("鱼香肉丝", query: "yuxiang"))
    }

    @Test func fullPinyinMatchesPrefixAndMidSyllable() {
        #expect(PinyinMatcher.matches("番茄炒蛋", query: "fan")) // 前缀
        #expect(PinyinMatcher.matches("番茄炒蛋", query: "chao")) // 中段音节
    }

    @Test func spacedPinyinStillMatches() {
        #expect(PinyinMatcher.matches("番茄炒蛋", query: "fan qie"))
    }

    // MARK: 首字母 (initials)

    @Test func initialsMatch() {
        #expect(PinyinMatcher.matches("番茄炒蛋", query: "fqcd"))
        #expect(PinyinMatcher.matches("西红柿炒鸡蛋", query: "xhscjd"))
        #expect(PinyinMatcher.matches("宫保鸡丁", query: "gbjd"))
    }

    // MARK: 多音字校正 (polyphone overrides, additive)

    @Test func polyphoneOverridesRescueCulinaryReadings() {
        #expect(PinyinMatcher.matches("茄子", query: "qiezi")) // ICU 默认读 jia
        #expect(PinyinMatcher.matches("蛤蜊", query: "geli")) // ICU 默认读 ha
        #expect(PinyinMatcher.matches("薄荷", query: "bohe")) // ICU 默认读 bao
    }

    @Test func overridesAreAdditiveNotReplacing() {
        // 薄 also reads "báo" (薄片) — ICU's "bao" is kept alongside the 薄荷 override.
        #expect(PinyinMatcher.matches("薄荷", query: "baohe"))
    }

    // MARK: 中文子串 / latin (preserved old behaviour)

    @Test func chineseSubstringStillMatches() {
        #expect(PinyinMatcher.matches("番茄炒蛋", query: "番茄"))
        #expect(PinyinMatcher.matches("番茄炒蛋", query: "炒蛋"))
    }

    @Test func latinMatchIsCaseInsensitive() {
        #expect(PinyinMatcher.matches("Pizza玛格丽特", query: "piz"))
        #expect(PinyinMatcher.matches("Pizza玛格丽特", query: "PIZ"))
    }

    // MARK: 负例 + 空 query

    @Test func unrelatedQueriesDoNotMatch() {
        #expect(!PinyinMatcher.matches("番茄炒蛋", query: "doufu"))
        #expect(!PinyinMatcher.matches("番茄炒蛋", query: "zzz"))
        #expect(!PinyinMatcher.matches("宫保鸡丁", query: "xhscjd")) // 别的菜的首字母
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(PinyinMatcher.matches("任意", query: ""))
        #expect(PinyinMatcher.matches("任意", query: "   "))
    }

    // MARK: 缓存一致性

    @Test func cachedAndFreshResultsAgree() {
        // Second call hits the cache; the result must be identical.
        let first = PinyinMatcher.matches("红烧排骨", query: "hspg")
        let second = PinyinMatcher.matches("红烧排骨", query: "hspg")
        #expect(first == second)
        #expect(first)
    }
}
