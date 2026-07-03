import CryptoKit
import Foundation

/// Household invite-token primitives: generation, shape validation, URL parsing
/// and hashing — ported byte-faithfully from the Flutter
/// `lib/household/invite_token.dart`.
///
/// The wire contract is shared with the existing Flutter app and the Supabase
/// backend, so every constant here (alphabet, length, regex, hash, URL shape)
/// must match Dart exactly: a token minted or hashed by one client has to be
/// accepted by the other and by the server.
///
/// SECURITY: the raw token is a bearer credential. It is only ever transmitted
/// after `hash` (SHA-256) on its way off-device, and the raw value must never be
/// logged.
enum InviteToken {
    // MARK: - Generation

    /// The 64-symbol URL-safe alphabet Dart draws from: A–Z, a–z, 0–9, `_`, `-`.
    /// Mirrors the literal in `generateInviteToken`; the 64-symbol size means a
    /// uniform `nextInt(alphabet.length)` has no modulo bias, matching Dart's
    /// `Random.secure().nextInt`.
    private static let alphabet = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
    )

    /// Number of characters in a freshly generated token (Dart `List.generate(32, …)`).
    private static let generatedLength = 32

    /// Mints a fresh 32-char invite token over the URL-safe alphabet using
    /// cryptographically secure randomness, mirroring Dart's `Random.secure()`.
    ///
    /// `SystemRandomNumberGenerator` is the CSPRNG Swift exposes; drawing a fresh
    /// `Int` per position over a power-of-two alphabet (64) keeps the draw
    /// unbiased, just like Dart over the same alphabet.
    static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        var chars: [Character] = []
        chars.reserveCapacity(generatedLength)
        for _ in 0..<generatedLength {
            // `randomElement(using:)` cannot fail for a non-empty array; the
            // force-unwrap encodes that invariant rather than masking an error.
            chars.append(alphabet.randomElement(using: &rng)!)
        }
        return String(chars)
    }

    // MARK: - Shape validation

    /// The canonical shape: 10–160 chars from the URL-safe alphabet. Dart's
    /// `_tokenPattern` is `^…$`, but ICU (`NSRegularExpression`) lets `$` match
    /// just before a trailing newline whereas Dart's default `$` does not — so a
    /// trailing-newline token would validate in Swift but not in Flutter, and
    /// `isShapeValid` + `hash` are public primitives (a mismatched validation
    /// would hash newline-suffixed bytes → a `token_hash` the server/Flutter
    /// reject). `\A…\z` are the absolute anchors that reproduce Dart's behavior.
    static let shapePattern = #"\A[A-Za-z0-9_-]{10,160}\z"#

    private static let shapeRegex = try! NSRegularExpression(pattern: shapePattern)

    /// Whether `token` matches `shapePattern` (mirrors `isInviteTokenShapeValid`).
    static func isShapeValid(_ token: String) -> Bool {
        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        return shapeRegex.firstMatch(in: token, options: [], range: range) != nil
    }

    // MARK: - Input parsing

    /// Resolves a user-supplied string (a raw token or a share URL) to a valid
    /// token, or nil. Mirrors Dart `inviteTokenFromInput`:
    ///   1. trim;
    ///   2. if already shape-valid, return it as-is;
    ///   3. else parse as a URI and extract a candidate token, then re-validate
    ///      its shape — returning nil if extraction fails or the candidate is not
    ///      shape-valid.
    static func fromInput(_ input: String) -> String? {
        let trimmed = input.trimmed
        if isShapeValid(trimmed) { return trimmed }

        guard let uri = ParsedURI(trimmed) else { return nil }
        guard let token = tokenFromURI(uri) else { return nil }
        return isShapeValid(token) ? token : nil
    }

    /// Extracts a token from the recognized URL forms, mirroring Dart's
    /// `_inviteTokenFromUri` branch-for-branch:
    ///   (a) schemeless `/invite/<token>` — exactly 2 path segments, first ==
    ///       `invite`;
    ///   (b) http/https URL with path `/invite/<token>` — same 2-segment rule;
    ///   (c) custom scheme `com.sunpebble.freshpantry` or `freshpantry`, host ==
    ///       `invite`, exactly 1 path segment = the token.
    ///
    /// Like Dart's `Uri`, a trailing slash yields a trailing empty path segment,
    /// so `/invite/<token>/` has 3 segments and is intentionally NOT matched —
    /// parity with the authoritative source, which does not special-case it.
    private static func tokenFromURI(_ uri: ParsedURI) -> String? {
        if !uri.hasScheme,
           uri.pathSegments.count == 2,
           uri.pathSegments.first == inviteSegment {
            return uri.pathSegments.last
        }

        if uri.scheme == "http" || uri.scheme == "https",
           uri.pathSegments.count == 2,
           uri.pathSegments.first == inviteSegment {
            return uri.pathSegments.last
        }

        if uri.scheme == customScheme || uri.scheme == shortScheme,
           uri.host == inviteSegment,
           uri.pathSegments.count == 1 {
            return uri.pathSegments.first
        }

        return nil
    }

    private static let inviteSegment = "invite"
    private static let customScheme = "com.sunpebble.freshpantry"
    private static let shortScheme = "freshpantry"

    // MARK: - Hashing

    /// Lowercase hex SHA-256 of the token's UTF-8 bytes (mirrors
    /// `hashInviteToken` = `sha256.convert(utf8.encode(token)).toString()`).
    ///
    /// SECURITY: this is the ONLY form of the token that leaves the device; the
    /// raw token must never be logged.
    static func hash(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Share-link construction

    /// Builds the share link for a token: `<apiBaseURL>/invite/<token>` with a
    /// single trailing slash stripped from the base, mirroring Dart
    /// `RemotePantryRepository.createInvite` (`baseUrl.endsWith('/') ? …`).
    ///
    /// Only ONE trailing slash is removed, matching the Dart `substring` (not a
    /// greedy trim), so the wire form stays identical across clients.
    static func inviteURL(apiBaseURL: String, token: String) -> String {
        let base = apiBaseURL.hasSuffix("/") ? String(apiBaseURL.dropLast()) : apiBaseURL
        return "\(base)/invite/\(token)"
    }
}

// MARK: - Dart-Uri-faithful parsing

/// A minimal URI decomposition that reproduces the specific
/// `scheme` / `host` / `pathSegments` / `hasScheme` semantics of Dart's `Uri`
/// for the branches `_inviteTokenFromUri` inspects.
///
/// Foundation's `URL`/`URLComponents` diverge from Dart here (different
/// trailing-slash handling, `pathComponents` includes `"/"`, schemes containing
/// dots are mishandled), so the decision logic is driven by this faithful parser
/// instead. It only needs to be correct for the recognized forms; anything that
/// can't be split into a valid scheme/authority/path is rejected, matching the
/// cases where `Uri.tryParse` returns nil.
private struct ParsedURI {
    let scheme: String
    let host: String
    let pathSegments: [String]
    let hasScheme: Bool

    /// Parses `input` into the Dart-`Uri` view, or returns nil for inputs Dart's
    /// `Uri.tryParse` rejects (e.g. an empty or malformed scheme).
    init?(_ input: String) {
        var rest = Substring(input)
        var parsedScheme = ""
        var parsedHasScheme = false

        // A scheme is `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )` followed by
        // ':'. Mirror Dart, which lowercases the scheme and rejects a leading
        // ':' or an empty/invalid scheme (those make `Uri.tryParse` return nil).
        if let colon = rest.firstIndex(of: ":") {
            let candidate = rest[rest.startIndex..<colon]
            if ParsedURI.looksLikeScheme(candidate) {
                parsedScheme = candidate.lowercased()
                parsedHasScheme = true
                rest = rest[rest.index(after: colon)...]
            } else if candidate.isEmpty {
                // Leading ':' — Dart `Uri.tryParse("://…")` / ":x" yields nil.
                return nil
            }
            // Otherwise the ':' belongs to the path (no valid scheme prefix),
            // which is fine — `rest` is left untouched and treated as a path.
        }

        // Authority (host) is present only after "//". Dart lowercases the host.
        var parsedHost = ""
        if rest.hasPrefix("//") {
            let afterSlashes = rest.index(rest.startIndex, offsetBy: 2)
            let authorityEnd =
                rest[afterSlashes...].firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" })
                ?? rest.endIndex
            let authority = rest[afterSlashes..<authorityEnd]
            // Strip userinfo/port to isolate the host, mirroring Dart's `Uri.host`.
            var hostPart = authority
            if let at = hostPart.lastIndex(of: "@") {
                hostPart = hostPart[hostPart.index(after: at)...]
            }
            if let portColon = hostPart.lastIndex(of: ":") {
                hostPart = hostPart[hostPart.startIndex..<portColon]
            }
            parsedHost = hostPart.lowercased()
            rest = rest[authorityEnd...]
        }

        // Strip a trailing query/fragment; only the path drives token extraction.
        if let cut = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            rest = rest[rest.startIndex..<cut]
        }

        self.scheme = parsedScheme
        self.host = parsedHost
        self.hasScheme = parsedHasScheme
        self.pathSegments = ParsedURI.splitPath(rest)
    }

    /// Splits a path into segments the way Dart's `Uri.pathSegments` does: drop a
    /// single leading empty segment (absolute path), keep a trailing empty
    /// segment (trailing slash), and yield `[]` for an empty path.
    private static func splitPath(_ path: Substring) -> [String] {
        if path.isEmpty { return [] }
        // Dart's `Uri.pathSegments` percent-decodes each segment, so a share link
        // whose path was percent-encoded (share sheet / messenger / QR reader)
        // extracts the same token the Flutter client would (e.g. `%41`→`A`,
        // `%69nvite`→`invite`). Fall back to the raw segment on malformed
        // encoding — it stays shape-invalid, so `fromInput` rejects it either way,
        // matching Dart (whose `Uri.tryParse` also yields nil for that input).
        var raw = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { segment -> String in
                let value = String(segment)
                return value.removingPercentEncoding ?? value
            }
        if let first = raw.first, first.isEmpty {
            raw.removeFirst() // leading '/' → drop the empty leading segment
        }
        return raw
    }

    /// Whether `candidate` is a syntactically valid URI scheme per RFC 3986 /
    /// Dart: an ASCII letter, then ASCII letters/digits/`+`/`-`/`.` (ASCII-only,
    /// to match Dart's scheme grammar rather than Unicode `isLetter`).
    private static func looksLikeScheme(_ candidate: Substring) -> Bool {
        guard let first = candidate.first, first.isASCII, first.isLetter else { return false }
        for ch in candidate {
            guard ch.isASCII else { return false }
            let ok = ch.isLetter || ch.isNumber || ch == "+" || ch == "-" || ch == "."
            if !ok { return false }
        }
        return true
    }
}
