import Foundation
import Testing
@testable import FreshPantry

/// Cook Mode 步骤时长的人类可读标签 + 倒计时 mm:ss 格式化(纯函数)。
struct CookStepTimerTests {
    @Test func labelUsesSecondsUnderAMinute() {
        #expect(CookStepTimer.label(seconds: 30) == String(localized: "cookStep.label.seconds \(30)"))
        #expect(CookStepTimer.label(seconds: 1) == String(localized: "cookStep.label.seconds \(1)"))
    }

    @Test func labelUsesWholeMinutes() {
        #expect(CookStepTimer.label(seconds: 180) == String(localized: "cookStep.label.minutes \(3)"))
        #expect(CookStepTimer.label(seconds: 60) == String(localized: "cookStep.label.minutes \(1)"))
    }

    @Test func labelMixesMinutesAndSeconds() {
        #expect(CookStepTimer.label(seconds: 90) == String(localized: "cookStep.label.minutesSeconds \(1) \(30)"))
        #expect(CookStepTimer.label(seconds: 125) == String(localized: "cookStep.label.minutesSeconds \(2) \(5)"))
    }

    @Test func countdownFormatsMinutesAndSeconds() {
        #expect(CookStepTimer.countdown(remaining: 125) == "02:05")
        #expect(CookStepTimer.countdown(remaining: 0) == "00:00")
        #expect(CookStepTimer.countdown(remaining: 600) == "10:00")
    }

    @Test func countdownClampsNegativeToZero() {
        #expect(CookStepTimer.countdown(remaining: -5) == "00:00")
    }
}
