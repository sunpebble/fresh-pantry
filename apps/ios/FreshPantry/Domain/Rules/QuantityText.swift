import Foundation

/// Single source of truth for two quantity-string rules ported verbatim from
/// `lib/utils/quantity_text.dart`.
///
///  * `parseLeadingQuantity` splits a free-text amount ("3 个", "1.5kg") into its
///    leading numeric magnitude and the remaining unit text.
///  * `formatQuantity` renders a double as an int string when whole, else as a
///    decimal string rounded to <=2 places — so binary float artifacts like
///    "1.2000000000000002" can never leak into a stored / displayed quantity.
enum QuantityText {
    /// Matches a leading decimal magnitude followed by optional unit text.
    /// `^(\d+(?:\.\d+)?)\s*(.*)$` — decimal-only on purpose (fraction/range
    /// dialect lives elsewhere).
    private static let leadingQuantityRe = try! NSRegularExpression(
        pattern: #"^(\d+(?:\.\d+)?)\s*(.*)$"#,
        options: [.dotMatchesLineSeparators]
    )

    /// The SINGLE arithmetic gate for free-text quantities: a quantity may join
    /// a sum/deduction iff this returns non-nil. "适量"/"半盒" → nil — callers
    /// must branch (hide merge / fall back to a new row / skip the deduction),
    /// NEVER coerce nil to 0: that is how stock silently vanishes. Non-finite
    /// parses ("inf"/"nan"/"1e999") are nil too — `formatQuantity` would trap
    /// on `Int(inf)`.
    static func numeric(_ text: String) -> Double? {
        guard let n = Double(text.trimmed), n.isFinite else { return nil }
        return n
    }

    /// Splits a (pre-trimmed) amount string into its leading numeric magnitude
    /// and the remaining (trimmed) text. Returns nil when there is no leading
    /// number. `magnitude` is the raw numeric token.
    static func parseLeadingQuantity(_ input: String) -> (magnitude: String, remainder: String)? {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = leadingQuantityRe.firstMatch(in: input, options: [], range: range) else {
            return nil
        }
        let magnitude = group(match, 1, in: input) ?? ""
        let remainder = (group(match, 2, in: input) ?? "").trimmed
        return (magnitude, remainder)
    }

    /// Renders `n` without trailing-zero / float-artifact noise: a whole number
    /// becomes an int string, otherwise a 2-decimal-rounded decimal string.
    static func formatQuantity(_ n: Double) -> String {
        if n == n.rounded() {
            return String(Int(n))
        }
        // Mirror Dart `double.parse(n.toStringAsFixed(2)).toString()`: round to
        // 2 decimals, then drop trailing zeros (e.g. 1.20 -> "1.2", 1.00 -> "1").
        let rounded = (n * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Common cooking fractions (vulgar-fraction glyphs) used for DISPLAY ONLY.
    /// Deliberately limited to halves/thirds/quarters/eighths — the amounts cooks
    /// actually read — so odd values like 0.2 fall back to a plain decimal rather
    /// than rendering an unfamiliar "⅕".
    private static let fractionGlyphs: [(value: Double, glyph: String)] = [
        (1.0 / 8, "⅛"), (1.0 / 4, "¼"), (1.0 / 3, "⅓"), (3.0 / 8, "⅜"),
        (1.0 / 2, "½"), (5.0 / 8, "⅝"), (2.0 / 3, "⅔"), (3.0 / 4, "¾"), (7.0 / 8, "⅞"),
    ]
    private static let fractionTolerance = 0.02

    /// Renders `n` as a clean cooking fraction for DISPLAY ONLY (½ 杯, 1¼ 茶匙):
    /// a whole number stays an int string; a fractional part close to a common
    /// cooking fraction becomes its glyph (mixed numbers like "1½"); anything else
    /// falls back to `formatQuantity` (plain decimal). NEVER use this for stored /
    /// mergeable quantities — the glyphs don't parse back through
    /// `parseLeadingQuantity`.
    static func formatFraction(_ n: Double) -> String {
        guard n.isFinite, n >= 0 else { return formatQuantity(n) }
        if n == n.rounded() { return String(Int(n.rounded())) }
        let whole = n.rounded(.down)
        let frac = n - whole
        var best: (glyph: String, dist: Double)?
        for entry in fractionGlyphs {
            let dist = abs(frac - entry.value)
            if dist <= fractionTolerance, best == nil || dist < best!.dist {
                best = (entry.glyph, dist)
            }
        }
        guard let best else { return formatQuantity(n) }
        if whole == 0 { return best.glyph }
        return "\(Int(whole))\(best.glyph)"
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in string: String) -> String? {
        let nsRange = match.range(at: index)
        guard nsRange.location != NSNotFound, let range = Range(nsRange, in: string) else {
            return nil
        }
        return String(string[range])
    }
}
