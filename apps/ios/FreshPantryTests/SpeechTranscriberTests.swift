import Foundation
import Testing
@testable import FreshPantry

/// The pure glue of #13 voice input — merging dictated text into the editor.
/// (The SFSpeech/AVAudioEngine capture itself is device-only, verified manually.)
struct SpeechTranscriberTests {
    @Test func appendsToEmptyText() {
        #expect(SpeechTranscriber.appendTranscript("牛奶两盒", to: "") == "牛奶两盒")
    }

    @Test func appendsWithNewlineToExisting() {
        #expect(SpeechTranscriber.appendTranscript("鸡蛋一打", to: "牛奶两盒") == "牛奶两盒\n鸡蛋一打")
    }

    @Test func trimsBothSides() {
        #expect(SpeechTranscriber.appendTranscript("  西红柿三个 ", to: "  牛奶  ") == "牛奶\n西红柿三个")
    }

    @Test func blankTranscriptLeavesTextUnchanged() {
        #expect(SpeechTranscriber.appendTranscript("   ", to: "牛奶") == "牛奶")
    }
}
