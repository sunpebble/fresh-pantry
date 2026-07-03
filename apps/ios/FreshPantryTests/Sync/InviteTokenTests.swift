import Foundation
import Testing
@testable import FreshPantry

/// Parity tests for `InviteToken` against the Flutter `lib/household/invite_token.dart`
/// contract: shared alphabet/length, regex shape, URL forms, and SHA-256 hex
/// hashing must stay byte-faithful so both clients sync the same backend.
struct InviteTokenTests {
    /// The 64-symbol URL-safe alphabet, mirrored from the source for charset
    /// assertions (kept private + nested so it can't collide with sibling tests).
    private static let alphabet = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
    )

    // MARK: - generate

    @Test func generateProducesShapeValid32CharTokensFromAlphabet() {
        // Several draws: assert length, charset membership, and shape-validity.
        for _ in 0..<200 {
            let token = InviteToken.generate()
            #expect(token.count == 32)
            #expect(token.allSatisfy { Self.alphabet.contains($0) })
            #expect(InviteToken.isShapeValid(token))
        }
    }

    @Test func generateIsEffectivelyUnique() {
        // Not a strength proof, just a smoke check that the CSPRNG isn't constant.
        var seen: Set<String> = []
        for _ in 0..<100 { seen.insert(InviteToken.generate()) }
        #expect(seen.count == 100)
    }

    // MARK: - isShapeValid

    @Test func shapeValidityHonorsLengthBoundaries() {
        #expect(!InviteToken.isShapeValid(String(repeating: "a", count: 9)))   // 9 < 10
        #expect(InviteToken.isShapeValid(String(repeating: "a", count: 10)))   // lower bound
        #expect(InviteToken.isShapeValid(String(repeating: "a", count: 160)))  // upper bound
        #expect(!InviteToken.isShapeValid(String(repeating: "a", count: 161))) // 161 > 160
    }

    @Test func shapeValidityRejectsCharsOutsideAlphabet() {
        #expect(!InviteToken.isShapeValid("abc!defghij"))      // '!'
        #expect(!InviteToken.isShapeValid("abc defghij"))      // space
        #expect(!InviteToken.isShapeValid("abc/defghij"))      // '/'
        #expect(!InviteToken.isShapeValid("abc+defghij"))      // '+' is NOT in alphabet
        #expect(!InviteToken.isShapeValid("abc.defghij"))      // '.'
        #expect(InviteToken.isShapeValid("abcDEF_-9012"))      // all allowed symbols
    }

    @Test func shapeValidityRejectsInternalNewline() {
        // Anchored \A…\z with no multiline flag — a newline must not slip through.
        #expect(!InviteToken.isShapeValid("abcdefghij\nabcdefghij"))
    }

    @Test func shapeValidityRejectsTrailingNewline() {
        // ICU `$` matches just before a trailing newline; Dart's default `$` does
        // not. `\z` reproduces Dart so a trailing-newline token is rejected — else
        // `hash` would digest newline-suffixed bytes the server/Flutter reject.
        #expect(!InviteToken.isShapeValid("abcdefghij\n"))
        #expect(!InviteToken.isShapeValid("abcDEF123_-ghijklmnop\n"))
    }

    // MARK: - fromInput

    @Test func fromInputAcceptsRawTokenAfterTrimming() {
        #expect(InviteToken.fromInput("abcDEF123_-ghijklmnop") == "abcDEF123_-ghijklmnop")
        #expect(InviteToken.fromInput("  abcDEF123_-ghijklmnop  ") == "abcDEF123_-ghijklmnop")
    }

    @Test func fromInputAcceptsSchemelessInvitePath() {
        #expect(InviteToken.fromInput("/invite/abcDEF123_-ghijklmnop") == "abcDEF123_-ghijklmnop")
        // No leading slash also yields 2 segments in Dart's Uri.
        #expect(InviteToken.fromInput("invite/abcDEF123_-ghijklmnop") == "abcDEF123_-ghijklmnop")
    }

    @Test func fromInputAcceptsHttpsInvitePath() {
        #expect(
            InviteToken.fromInput("https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-ghijklmnop")
                == "abcDEF123_-ghijklmnop"
        )
        // Scheme casing is normalized like Dart's Uri.
        #expect(
            InviteToken.fromInput("HTTPS://host/invite/abcDEF123_-ghijklmnop")
                == "abcDEF123_-ghijklmnop"
        )
    }

    @Test func fromInputAcceptsCustomSchemeURLs() {
        #expect(
            InviteToken.fromInput("com.sunpebble.freshpantry://invite/abcDEF123_-ghijklmnop")
                == "abcDEF123_-ghijklmnop"
        )
        #expect(
            InviteToken.fromInput("freshpantry://invite/abcDEF123_-ghijklmnop")
                == "abcDEF123_-ghijklmnop"
        )
        // Custom-scheme host is lowercased; the recognized host is `invite`.
        #expect(
            InviteToken.fromInput("FreshPantry://invite/abcDEF123_-ghijklmnop")
                == "abcDEF123_-ghijklmnop"
        )
    }

    @Test func fromInputPercentDecodesPathSegments() {
        // Dart's `Uri.pathSegments` percent-decodes; a share sheet / messenger may
        // encode the path. `%41`→`A` in the token segment.
        #expect(
            InviteToken.fromInput("/invite/abc%41DEF123_-ghijklmn") == "abcADEF123_-ghijklmn"
        )
        // `%5F`→`_`, `%2D`→`-` — both in the URL-safe alphabet once decoded.
        #expect(
            InviteToken.fromInput("/invite/abcDEF123%5F%2Dghijklmnop") == "abcDEF123_-ghijklmnop"
        )
        // The `invite` segment itself may be encoded (`%69`→`i`) and must match.
        #expect(
            InviteToken.fromInput("/%69nvite/abcDEF123_-ghijklmnop") == "abcDEF123_-ghijklmnop"
        )
    }

    @Test func fromInputRejectsJunkAndUnrecognizedForms() {
        #expect(InviteToken.fromInput("not a token") == nil)
        #expect(InviteToken.fromInput("https://host/other/abcDEF123_-ghijklmnop") == nil)
        // Trailing slash → 3 path segments in Dart's Uri → not matched (parity).
        #expect(InviteToken.fromInput("https://host/invite/abcDEF123_-ghijklmnop/") == nil)
        #expect(InviteToken.fromInput("/invite/abcDEF123_-ghijklmnop/") == nil)
        // Extra path depth.
        #expect(InviteToken.fromInput("/invite/abcDEF123_-ghijklmnop/extra") == nil)
        // Wrong custom-scheme host.
        #expect(InviteToken.fromInput("freshpantry://other/abcDEF123_-ghijklmnop") == nil)
        // Extracted token that fails the shape (too short).
        #expect(InviteToken.fromInput("/invite/short") == nil)
        #expect(InviteToken.fromInput("") == nil)
    }

    // MARK: - hash

    @Test func hashMatchesKnownSHA256Vector() {
        // SHA256("abc") — canonical NIST vector.
        #expect(
            InviteToken.hash("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test func hashOfShapeValidTokenRoundTrips() {
        let token = "abcDEF123_-ghijklmnop"
        let digest = InviteToken.hash(token)
        // Independently-computed vector for the round-trip token.
        #expect(digest == "fbdd6cd0e99924a809049b4fd8f7ce2259eddf50dbf1e41eb3cc08bc895b43f5")
        #expect(InviteToken.isShapeValid(token))
    }

    @Test func hashIsDeterministicLowercaseHex64() {
        let token = InviteToken.generate()
        let a = InviteToken.hash(token)
        let b = InviteToken.hash(token)
        #expect(a == b)                                   // deterministic
        #expect(a.count == 64)                            // 32 bytes → 64 hex chars
        #expect(a == a.lowercased())                      // lowercase hex
        #expect(a.allSatisfy { $0.isHexDigit })           // hex only
    }

    // MARK: - inviteURL

    @Test func inviteURLStripsSingleTrailingSlash() {
        #expect(
            InviteToken.inviteURL(
                apiBaseURL: "https://api.fresh-pantry.kunish.eu.org",
                token: "abc123"
            ) == "https://api.fresh-pantry.kunish.eu.org/invite/abc123"
        )
        // One trailing slash stripped, mirroring the Dart `substring` (not greedy).
        #expect(
            InviteToken.inviteURL(
                apiBaseURL: "https://api.fresh-pantry.kunish.eu.org/",
                token: "abc123"
            ) == "https://api.fresh-pantry.kunish.eu.org/invite/abc123"
        )
        // Only ONE slash removed → a double trailing slash keeps the inner one.
        #expect(
            InviteToken.inviteURL(apiBaseURL: "https://host//", token: "abc123")
                == "https://host//invite/abc123"
        )
    }
}
