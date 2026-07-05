import Foundation
import Testing
@testable import FreshPantry

/// State-machine tests for `AuthService`, driven through a fake `AuthBackend`
/// (NEVER the real Supabase SDK, simulator, or live creds). Exercises the OTP
/// flow transitions, error handling, session restore, and local-only mode.
@MainActor
struct AuthServiceTests {
    /// Injectable fake backend. Records calls and returns scripted results so the
    /// state machine can be exercised deterministically.
    final class FakeBackend: AuthBackend, @unchecked Sendable {
        var restoreEmail: String?
        var sendShouldThrow: AuthFailure?
        var verifyShouldThrow: AuthFailure?
        var verifyReturnsEmail: String?

        private(set) var sentEmails: [String] = []
        private(set) var verifiedCodes: [(email: String, code: String)] = []
        private(set) var signOutCount = 0

        func restoreSessionEmail() async -> String? { restoreEmail }

        func sendCode(email: String) async throws {
            sentEmails.append(email)
            if let sendShouldThrow { throw sendShouldThrow }
        }

        func verify(email: String, code: String) async throws -> String {
            verifiedCodes.append((email, code))
            if let verifyShouldThrow { throw verifyShouldThrow }
            return verifyReturnsEmail ?? email
        }

        func signOut() async { signOutCount += 1 }
    }

    // MARK: Local-only (no config)

    @Test func nilBackendIsLocalOnlyAndInert() async {
        let service = AuthService(backend: nil)
        #expect(service.state == .localOnly)
        #expect(!service.isConfigured)

        // All operations are no-ops in local-only mode.
        await service.sendCode(email: "a@b.com")
        await service.verify(code: "123456")
        await service.signOut()
        await service.restore()
        #expect(service.state == .localOnly)
        #expect(service.errorMessage == nil)
    }

    @Test func configuredBackendStartsSignedOut() {
        let service = AuthService(backend: FakeBackend())
        #expect(service.state == .signedOut)
        #expect(service.isConfigured)
    }

    // MARK: sendCode → codeSent

    @Test func sendCodeSuccessMovesToCodeSent() async {
        let backend = FakeBackend()
        let service = AuthService(backend: backend)

        await service.sendCode(email: "  user@example.com ")
        #expect(service.state == .codeSent(email: "user@example.com")) // trimmed
        #expect(backend.sentEmails == ["user@example.com"])
        #expect(service.errorMessage == nil)
        #expect(!service.isBusy)
    }

    @Test func sendCodeSuccessStartsResendCooldown() async {
        let now = Date(timeIntervalSince1970: 100)
        let service = AuthService(backend: FakeBackend(), now: { now })

        await service.sendCode(email: "user@example.com")

        #expect(service.resendCooldownRemaining(at: now) == 60)
        #expect(service.resendCooldownRemaining(at: now.addingTimeInterval(6.2)) == 54)
        #expect(service.resendCooldownRemaining(at: now.addingTimeInterval(60)) == 0)
    }

    @Test func sendCodeRejectsInvalidEmailWithoutCallingBackend() async {
        let backend = FakeBackend()
        let service = AuthService(backend: backend)

        await service.sendCode(email: "not-an-email")
        #expect(service.state == .signedOut)
        #expect(backend.sentEmails.isEmpty)
        #expect(service.errorMessage == String(localized: "auth.error.invalidEmail"))
    }

    @Test func sendCodeFailureSurfacesErrorAndStaysSignedOut() async {
        let backend = FakeBackend()
        backend.sendShouldThrow = AuthFailure(message: "请求过于频繁,请稍后再试")
        let service = AuthService(backend: backend)

        await service.sendCode(email: "user@example.com")
        #expect(service.state == .signedOut)
        #expect(service.errorMessage == "请求过于频繁,请稍后再试")
        #expect(!service.isBusy)
    }

    // MARK: verify

    @Test func verifySuccessMovesToSignedIn() async {
        let backend = FakeBackend()
        backend.verifyReturnsEmail = "user@example.com"
        let service = AuthService(backend: backend)
        await service.sendCode(email: "user@example.com")

        await service.verify(code: " 123456 ")
        #expect(service.state == .signedIn(userEmail: "user@example.com"))
        #expect(backend.verifiedCodes.count == 1)
        #expect(backend.verifiedCodes.first?.code == "123456") // trimmed
        #expect(service.errorMessage == nil)
    }

    @Test func verifyFailureStaysInCodeSentWithError() async {
        let backend = FakeBackend()
        backend.verifyShouldThrow = AuthFailure(message: "验证码不正确,请重新输入")
        let service = AuthService(backend: backend)
        await service.sendCode(email: "user@example.com")

        await service.verify(code: "000000")
        #expect(service.state == .codeSent(email: "user@example.com")) // unchanged
        #expect(service.errorMessage == "验证码不正确,请重新输入")
        #expect(!service.isBusy)
    }

    @Test func verifyEmptyCodeShowsErrorWithoutCallingBackend() async {
        let backend = FakeBackend()
        let service = AuthService(backend: backend)
        await service.sendCode(email: "user@example.com")

        await service.verify(code: "   ")
        #expect(service.state == .codeSent(email: "user@example.com"))
        #expect(backend.verifiedCodes.isEmpty)
        #expect(service.errorMessage == String(localized: "auth.error.emptyCode"))
    }

    @Test func verifyIsNoOpBeforeCodeSent() async {
        let backend = FakeBackend()
        let service = AuthService(backend: backend)

        await service.verify(code: "123456")
        #expect(service.state == .signedOut)
        #expect(backend.verifiedCodes.isEmpty)
    }

    // MARK: signOut

    @Test func signOutReturnsToSignedOut() async {
        let backend = FakeBackend()
        backend.verifyReturnsEmail = "user@example.com"
        let service = AuthService(backend: backend)
        await service.sendCode(email: "user@example.com")
        await service.verify(code: "123456")
        #expect(service.state == .signedIn(userEmail: "user@example.com"))

        await service.signOut()
        #expect(service.state == .signedOut)
        #expect(backend.signOutCount == 1)
        #expect(service.signedInEmail == nil)
    }

    // MARK: restore

    @Test func restoreRehydratesPersistedSession() async {
        let backend = FakeBackend()
        backend.restoreEmail = "back@example.com"
        let service = AuthService(backend: backend)

        await service.restore()
        #expect(service.state == .signedIn(userEmail: "back@example.com"))
        #expect(service.signedInEmail == "back@example.com")
    }

    @Test func restoreNoSessionStaysSignedOut() async {
        let backend = FakeBackend()
        backend.restoreEmail = nil
        let service = AuthService(backend: backend)

        await service.restore()
        #expect(service.state == .signedOut)
    }
}
