import Foundation

/// Pure (no-Vision, no-UI) extraction of the most likely EXPIRY date from a block
/// of OCR'd packaging text. Sits behind the on-device `TextRecognizer` the same way
/// `ReceiptTextCleaner` does: photo → OCR lines → THIS parser → a `Date?` the add
/// form can prefill. All logic is deterministic and `now`-injectable so every rule
/// is unit-testable without the camera/Vision engine.
///
/// Strategy (in order of trust):
///  1. EXPLICIT expiry labels ("保质期至 / 有效期至 / 到期 / best before …") — when a
///     date sits next to such a marker it is authoritative, so it wins outright.
///  2. PRODUCTION date + duration ("生产日期 X … 保质期 N 天/月/年") — compute
///     production + N and treat it as an expiry candidate.
///  3. Otherwise any standalone calendar date on the label; among the leftovers the
///     LATEST plausible date is the best expiry guess (a packaging label's two bare
///     dates are production-then-expiry, expiry being later).
///
/// Noise guard: a date is only accepted when its components form a real calendar
/// day in a sane year window, so a price ("12.50"), a phone number, or a batch code
/// never masquerades as a date. Returns nil when nothing parses.
enum ExpiryDateParser {
    /// Years outside this window are rejected as non-dates (batch codes, prices,
    /// phone fragments). Generous on both ends so a long-dated can or a just-made
    /// product still parses, narrow enough that a 5+ digit run isn't a "year".
    private static let minYear = 2000
    private static let maxYear = 2099

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Extracts the single most likely expiry `Date` from free-form OCR text, or nil
    /// when no plausible date is present. `now` is injectable for deterministic tests
    /// (it only influences the production-date + duration math, never the literal
    /// date parsing). Returned dates are date-only (local midnight).
    static func parse(_ text: String, now: Date = Date()) -> Date? {
        let normalized = normalize(text)

        // 1. Explicit "expiry/at" labels win — a date glued to 至/到期/best before is
        // unambiguously the expiry, so return the FIRST such hit immediately.
        if let labeled = firstLabeledExpiry(in: normalized) {
            return labeled
        }

        // 2. Production date + a "保质期 N 天/月/年" duration → production + N.
        if let derived = derivedFromProductionAndDuration(in: normalized, now: now) {
            return derived
        }

        // 3. Fallback: any bare date on the label; the latest plausible one is the
        // best expiry guess (production-then-expiry ordering on a label).
        let bare = allDates(in: normalized)
        return bare.max()
    }

    // MARK: Normalization

    /// Folds the assorted CJK/full-width separators OCR emits into ASCII so the
    /// regexes stay simple: full-width digits → ASCII, CJK punctuation/space and
    /// full-width slashes/dots → their ASCII equivalents.
    private static func normalize(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19: // full-width digits ０-９
                result.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
            case 0x3000, 0x00A0: // ideographic / non-breaking space
                result.append(" ")
            case 0xFF0F: // full-width slash ／
                result.append("/")
            case 0xFF0E, 0x3002: // full-width dot ．/ ideographic period 。
                result.append(".")
            case 0xFF1A: // full-width colon ：
                result.append(":")
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    // MARK: 1. Explicit expiry labels

    /// CJK expiry markers (no word boundaries — OCR concatenation makes substring
    /// matching correct, and these never appear inside another word).
    private static let cjkExpiryMarkers = ["保质期至", "有效期至", "保质期到", "有效期到", "到期日", "到期"] // i18n:ignore OCR pattern-matching data table, not UI text

    /// English expiry markers. Matched on WORD boundaries (not bare substring):
    /// the short "exp" would otherwise hijack tier 1 from inside EXPORT /
    /// EXPERIENCE / EXPRESS / EXPIRED and silently set an arbitrary printed date.
    private static let englishExpiryMarkers = [
        "best before", "best by", "use by", "exp", "expiry", "expires",
    ]

    /// Returns the date immediately following the FIRST expiry marker, if any. The
    /// marker may be followed by punctuation/spaces ("保质期至：2026.05.01"); we scan
    /// the remainder of the string after the marker for the first parseable date.
    private static func firstLabeledExpiry(in text: String) -> Date? {
        let lowered = text.lowercased()
        var best: (index: String.Index, date: Date)?

        func consider(range: Range<String.Index>) {
            // Index into `lowered` (the string the range belongs to) — digits/dates
            // are unaffected by lowercasing, and this avoids any cross-string index
            // mismatch with `text`.
            let tail = String(lowered[range.upperBound...])
            guard let date = firstDate(in: tail) else { return }
            // Prefer the EARLIEST-positioned marker so "保质期至 X" beats a later
            // stray "生产" mention; ties resolve to whichever scanned first.
            if best == nil || range.lowerBound < best!.index {
                best = (range.lowerBound, date)
            }
        }

        for marker in cjkExpiryMarkers {
            if let range = lowered.range(of: marker) { consider(range: range) }
        }
        for marker in englishExpiryMarkers {
            // \b…\b so "exp" matches the standalone token, never EXPORT/EXPRESS.
            guard let regex = try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: marker))\\b",
                options: [.caseInsensitive]
            ) else { continue }
            let ns = lowered as NSString
            guard let match = regex.firstMatch(in: lowered, range: NSRange(location: 0, length: ns.length)),
                  let range = Range(match.range, in: lowered)
            else { continue }
            consider(range: range)
        }
        return best?.date
    }

    // MARK: 2. Production date + duration

    private static let productionMarkers = ["生产日期", "生产", "制造日期", "制造", "production", "mfg", "mfd"] // i18n:ignore OCR pattern-matching data table, not UI text

    /// Markers that introduce a shelf-life DURATION ("保质期 6个月"). The duration is
    /// only read from the text FOLLOWING such a marker — this is what keeps a bare
    /// date's own "2026年" from being misread as a "2026 年" (2026-year) duration.
    private static let durationMarkers = ["保质期", "有效期", "保存期", "shelf life", "best before within"] // i18n:ignore OCR pattern-matching data table, not UI text

    /// If the label carries BOTH a production date and a "保质期 N 天/月/年" duration,
    /// returns production + duration. The production date is the first date after a
    /// production marker (or, lacking a marker, the earliest bare date — the made-on
    /// date precedes the expiry). nil when either piece is missing.
    private static func derivedFromProductionAndDuration(in text: String, now: Date) -> Date? {
        guard let duration = shelfLifeDuration(in: text) else { return nil }
        let production = productionDate(in: text) ?? allDates(in: text).min()
        guard let production else { return nil }
        return calendar.date(byAdding: duration, to: production)
    }

    /// The production date: the first date following a production marker, else nil
    /// (the caller falls back to the earliest bare date).
    private static func productionDate(in text: String) -> Date? {
        let lowered = text.lowercased()
        for marker in productionMarkers {
            guard let range = lowered.range(of: marker.lowercased()) else { continue }
            if let date = firstDate(in: String(text[range.upperBound...])) {
                return date
            }
        }
        return nil
    }

    /// Parses a "保质期 N 天/个月/月/年" (or English "N days/months/years") shelf-life
    /// duration into `DateComponents`. The duration is read ONLY from the text after a
    /// `durationMarker` (保质期/有效期/shelf life…) — this gate is what stops a date's
    /// own "2026年" from reading as a "2026-year" duration, and stops a bare quantity
    /// ("净含量 500克") from looking like a shelf life.
    private static func shelfLifeDuration(in text: String) -> DateComponents? {
        let lowered = text.lowercased()
        var tail: String?
        for marker in durationMarkers {
            if let range = lowered.range(of: marker.lowercased()) {
                tail = String(text[range.upperBound...])
                break
            }
        }
        guard let tail else { return nil }

        // number + unit, where unit is 天/日 (day), (个)月 (month), or 年 (year), or the
        // English equivalents. Requires the unit so a bare number can't match.
        let pattern = #"(\d{1,4})\s*(天|日|个月|月|年|days?|months?|years?)"# // i18n:ignore regex pattern, not UI text
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(tail.startIndex..., in: tail)
        guard let match = regex.firstMatch(in: tail, range: range),
              let numberRange = Range(match.range(at: 1), in: tail),
              let unitRange = Range(match.range(at: 2), in: tail),
              let amount = Int(tail[numberRange])
        else { return nil }

        let unit = tail[unitRange].lowercased()
        var components = DateComponents()
        switch unit {
        case "天", "日", "day", "days": // i18n:ignore OCR unit-matching case literals, not UI text
            components.day = amount
        case "个月", "月", "month", "months": // i18n:ignore OCR unit-matching case literals, not UI text
            components.month = amount
        case "年", "year", "years": // i18n:ignore OCR unit-matching case literals, not UI text
            components.year = amount
        default:
            return nil
        }
        return components
    }

    // MARK: Bare date scanning

    /// All plausible calendar dates anywhere in the text, in appearance order.
    private static func allDates(in text: String) -> [Date] {
        dateMatches(in: text).map(\.date)
    }

    /// The first plausible date in the text, or nil.
    private static func firstDate(in text: String) -> Date? {
        dateMatches(in: text).first?.date
    }

    /// A matched date plus where it started (used to pick the marker-nearest one).
    private struct DateMatch {
        let date: Date
        let start: Int
    }

    /// Scans for `YYYY[-/.]MM[-/.]DD`, `YYYY年MM月DD日` (day optional → 1st), and the
    /// bare-digit `YYYYMMDD` run, keeping only those whose components form a real
    /// calendar day inside the sane year window. Patterns are tried widest-first and
    /// overlapping matches are de-duplicated by start index so one date isn't counted
    /// twice. A 2-digit "year" is intentionally NOT supported (too ambiguous with
    /// prices/batch codes), keeping false positives out.
    private static func dateMatches(in text: String) -> [DateMatch] {
        // year-first only (the unambiguous packaging convention); separators are
        // -, /, ., or the CJK 年月日 already normalized to keep . here.
        let separated = #"(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})?\s*日?"# // i18n:ignore regex pattern, not UI text
        let compact = #"(?<!\d)(\d{4})(\d{2})(\d{2})(?!\d)"#

        var matches: [DateMatch] = []
        var consumed = Set<Int>()

        for pattern in [separated, compact] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { result, _, _ in
                guard let result else { return }
                let start = result.range.location
                guard !consumed.contains(start) else { return }
                guard let year = intGroup(result, 1, in: text),
                      let month = intGroup(result, 2, in: text)
                else { return }
                // Day group is optional for "YYYY年MM月" → default to the 1st.
                let day = intGroup(result, 3, in: text) ?? 1
                guard let date = validDate(year: year, month: month, day: day) else { return }
                consumed.insert(start)
                matches.append(DateMatch(date: date, start: start))
            }
        }
        return matches.sorted { $0.start < $1.start }
    }

    private static func intGroup(_ result: NSTextCheckingResult, _ index: Int, in text: String) -> Int? {
        guard index < result.numberOfRanges,
              let range = Range(result.range(at: index), in: text)
        else { return nil }
        return Int(text[range])
    }

    /// Builds a date ONLY if year/month/day form a real calendar day in the year
    /// window — this is the gate that keeps prices / phone numbers / batch codes from
    /// being read as dates (e.g. month 13 or day 50 are rejected; a "year" like 1234
    /// or 5012 falls outside the window).
    private static func validDate(year: Int, month: Int, day: Int) -> Date? {
        guard (minYear...maxYear).contains(year),
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        // `date(from:)` is lenient; re-read the components back and require an exact
        // round-trip so an invalid day (Feb 30, Apr 31) is rejected, not rolled over.
        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }
}
