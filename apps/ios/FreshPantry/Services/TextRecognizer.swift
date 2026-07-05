import Foundation
import Vision

/// Offline OCR over a receipt / label photo using the on-device Vision engine
/// (`VNRecognizeTextRequest`). No network — recognition runs entirely locally,
/// so a photographed shopping receipt can be turned into the same free-form text
/// the AI ingredient parser already consumes (the receipt path is just a
/// "image → OCR → text" prefix in front of the EXISTING text parse chain).
///
/// Concurrency: the heavy decode + Vision perform runs inside a `Task.detached`,
/// so the calling actor is never blocked. Only the `Data` input and the recognized
/// lines (`[String]`, a `Sendable` value) cross the actor boundary — the
/// non-`Sendable` `CGImage` / `VNRecognizeTextRequest` stay local to the task.
/// Callers are `@MainActor` and simply `await` the result.
enum TextRecognizer {
    /// OCR failures surfaced to the UI — each carries Chinese text so the import
    /// sheet can render it inline (parity with the AI import error handling).
    enum RecognizeError: Error, Equatable {
        /// The image bytes could not be decoded into a `CGImage`.
        case undecodable
        /// Vision threw while performing the request (wrapped message).
        case vision(String)
        /// The request succeeded but found no usable text in the photo.
        case noText

        var message: String {
            switch self {
            case .undecodable: return String(localized: "error.ocr.undecodable")
            case let .vision(text): return String(localized: "error.ocr.visionFailed \(text)")
            case .noText: return String(localized: "error.ocr.noText")
            }
        }
    }

    /// Recognizes text in the given JPEG/PNG image bytes and returns the cleaned,
    /// joined receipt text ready to feed the existing AI text parser. Throws a
    /// `RecognizeError` (decodable → vision → noText) so the caller can surface a
    /// specific inline message. Runs the Vision request off the calling actor.
    static func recognizeReceiptText(from imageData: Data) async throws -> String {
        let lines = try await recognizeLines(from: imageData)
        let cleaned = ReceiptTextCleaner.clean(lines)
        guard !cleaned.isEmpty else { throw RecognizeError.noText }
        return ReceiptTextCleaner.join(cleaned)
    }

    /// Lower-level entry: returns the raw recognized text lines (top candidate per
    /// observation, in reading order) WITHOUT cleaning. Throws `.undecodable` when
    /// the bytes are not an image, `.vision` when the request fails, and `.noText`
    /// when Vision returns no observations.
    ///
    /// Runs the whole CPU/Neural-Engine-heavy step (decode + `VNImageRequestHandler`)
    /// inside a `Task.detached`, so it never blocks the caller's actor. Only the
    /// `Data` input and the `[String]` result (both `Sendable`) cross the boundary —
    /// the non-`Sendable` `CGImage` / `VNRecognizeTextRequest` stay local to the task.
    static func recognizeLines(from imageData: Data) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            try Self.recognizeLinesSync(from: imageData)
        }.value
    }

    /// Synchronous OCR core: decode → perform → collect top candidates. The
    /// `VNRecognizeTextRequest` completion handler runs synchronously during
    /// `perform`, so there is no continuation / double-resume to manage. Accurate
    /// recognition level, Simplified-Chinese + English languages, correction on.
    private static func recognizeLinesSync(from imageData: Data) throws -> [String] {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw RecognizeError.undecodable
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw RecognizeError.vision(error.localizedDescription)
        }

        guard let observations = request.results else { throw RecognizeError.noText }
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}

/// Pure (no-Vision) text post-processing for OCR'd receipt lines. Extracted so the
/// noise-filtering / joining rules are unit-testable WITHOUT the Vision engine.
///
/// A receipt is mostly chrome — store header/footer, dates, register/cashier ids,
/// payment/total/tax rows, and bare prices — surrounding the few lines that name
/// actual items. The AI parser is robust to extra text, but stripping the obvious
/// noise keeps the prompt focused and the cost down. The rules are intentionally
/// conservative: when in doubt a line is KEPT (a wrongly-dropped item is worse
/// than a surviving noise line the parser can ignore).
enum ReceiptTextCleaner {
    /// Trims each line, drops blanks, and drops lines that are pure receipt noise
    /// (totals / payment / price-only / dividers). Preserves input order.
    static func clean(_ lines: [String]) -> [String] {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isNoiseLine($0) }
    }

    /// Joins cleaned lines with newlines into the free-form text block the existing
    /// `AiIngredientParser.fromText` consumes.
    static func join(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    /// Whether a (trimmed, non-empty) line is receipt chrome rather than an item:
    /// - a divider rule (only punctuation/box-drawing chars),
    /// - a price-/quantity-only line (no letters or CJK, e.g. "12.50", "¥9.9", "x2"),
    /// - a total / payment / change / tax / discount keyword row.
    static func isNoiseLine(_ line: String) -> Bool {
        if isDividerLine(line) { return true }
        if isPriceOnlyLine(line) { return true }
        if containsNoiseKeyword(line) { return true }
        return false
    }

    /// A line made up only of punctuation / separators (e.g. "------", "======",
    /// "***", "—————") with no alphanumeric or CJK content.
    private static func isDividerLine(_ line: String) -> Bool {
        line.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.alphanumerics.contains(scalar) && !isCJK(scalar)
        }
    }

    /// A line with NO letters/CJK — only digits, currency symbols, separators, and
    /// quantity markers (e.g. "12.50", "¥ 9.90", "$3.00", "2 x 1.50", "001234").
    /// These are price/quantity fragments with no item name to parse.
    private static func isPriceOnlyLine(_ line: String) -> Bool {
        // Drop a bare quantity multiplier ("x" / "X" / "×") before the letter
        // check so a "2 x 1.50" qty×price fragment reads as price-only. A real
        // item name carries OTHER letters or CJK ("Cola x2", "可乐 x2"), so it
        // still keeps a letter after this strip and is preserved.
        let withoutMultiplier = line.unicodeScalars.filter { $0 != "x" && $0 != "X" && $0 != "×" }
        let hasLetterOrCJK = withoutMultiplier.contains { scalar in
            CharacterSet.letters.contains(scalar) || isCJK(scalar)
        }
        if hasLetterOrCJK { return false }
        // Must contain at least one digit to count as a price/quantity fragment
        // (an all-symbol line is already caught by isDividerLine).
        return withoutMultiplier.contains { CharacterSet.decimalDigits.contains($0) }
    }

    /// Whether the line is a receipt-summary row (total / payment / store header…).
    ///
    /// Two tiers, both honoring "误删商品比留噪音更糟":
    ///  - STRONG terms (Chinese rows + unambiguous English words/phrases) are
    ///    definitive — they essentially never occur inside a grocery item name, so
    ///    a substring hit drops the line.
    ///  - AMBIGUOUS short English words (total/cash/card/store/tax…) collide with
    ///    real item words ("Store Brand Milk", "Total Greek Yogurt"), so they only
    ///    mark noise when the line is made up SOLELY of such keyword-words plus
    ///    digits/symbols. A line carrying any other letter-word is kept.
    private static func containsNoiseKeyword(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if strongNoiseKeywords.contains(where: { lowered.contains($0) }) { return true }
        let letterTokens = lowered.split { !$0.isLetter }.map(String.init)
        guard !letterTokens.isEmpty else { return false }
        // Every letter-word is an ambiguous keyword ⇒ a pure summary row
        // (e.g. "Total 45.30", "Card Payment"); any non-keyword word ⇒ a real
        // item that merely includes a keyword as a modifier ⇒ keep.
        return letterTokens.allSatisfy(ambiguousNoiseWords.contains)
    }

    /// Receipt-summary terms that never appear inside an item name — safe to match
    /// as a substring. All Chinese rows are here (2+ chars, unambiguous), plus a
    /// few English words/phrases with no food-name collision.
    private static let strongNoiseKeywords: [String] = ["合计", "小计", "总计", "应收", "实收", "找零", "找赎", "抹零", "现金", "支付", "微信", "支付宝", "银联", "刷卡", "会员", "积分", "优惠", "折扣", "税额", "税率", "发票", "收银", "门店", "电话", "地址", "欢迎", "谢谢", "营业", "单号", "流水", "数量", "金额", "单价", "subtotal", "thank you", "receipt", "invoice", "cashier"] // i18n:ignore OCR noise-matching data table, not UI text

    /// Short English words that ARE common summary rows but also collide with real
    /// item words. Only flag noise when EVERY letter-word on the line is one of
    /// these (see `containsNoiseKeyword`).
    private static let ambiguousNoiseWords: Set<String> = [
        "total", "change", "cash", "card", "visa", "debit", "credit",
        "tax", "vat", "balance", "tender", "payment", "discount", "store", "tel",
    ]

    /// CJK Unified Ideographs (incl. Extension A) — used to keep Chinese item names
    /// out of the price-only / divider filters. Deliberately NARROW: it covers only
    /// ideographs. Fullwidth letters/digits are already recognized by
    /// `CharacterSet.letters` / `.decimalDigits`, and CJK punctuation is excluded so
    /// a punctuation-only line still reads as a divider and a fullwidth-currency
    /// price line ("￥9.90") is still filtered as price-only.
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, // CJK Unified Ideographs
             0x3400...0x4DBF: // Extension A
            return true
        default:
            return false
        }
    }
}
