import Foundation
import Testing
@testable import NotchCore

struct SystemInputsTests {
    @Test func testMediaKeysDecodeFromSystemDefinedEvents() {
        // Volume up pressed: key 0 in the high half, state 0xA in the low half.
        let down = MediaKey.decode(subtype: 8, data1: (0 << 16) | 0x0A00)
        #expect(down?.key == .volumeUp)
        #expect(down?.down == true)
        #expect(down?.isRepeat == false)
        let repeatDown = MediaKey.decode(subtype: 8, data1: (1 << 16) | 0x0A01)
        #expect(repeatDown?.key == .volumeDown)
        #expect(repeatDown?.isRepeat == true)
        #expect(MediaKey.decode(subtype: 8, data1: (7 << 16) | 0x0B00)?.down == false)
        #expect(MediaKey.decode(subtype: 8, data1: (2 << 16) | 0x0A00)?.key == .brightnessUp)
        #expect(MediaKey.decode(subtype: 8, data1: (16 << 16) | 0x0A00) == nil)  // play/pause stays with Now Playing
        #expect(MediaKey.decode(subtype: 7, data1: 0x0A00) == nil)
    }

    @Test func testLevelStepsSnapToSixteenthsAndClamp() {
        #expect(LevelStep.next(0.5, up: true) == 0.5625)
        #expect(LevelStep.next(0.5, up: false) == 0.4375)
        #expect(LevelStep.next(0.52, up: true) == 0.5625)
        #expect(LevelStep.next(0.52, up: false) == 0.5)
        #expect(LevelStep.next(1, up: true) == 1)
        #expect(LevelStep.next(0, up: false) == 0)
        #expect(LevelStep.next(0.5, up: true, fine: true) == 0.515625)
        #expect(LevelStep.segments(0.5) == 8)
        #expect(SystemLevel(kind: .volume, value: 0.7, muted: true).shown == 0)
        #expect(SystemLevel(kind: .volume, value: 3).value == 1)
    }

    @Test func testHeadphoneBatteryIgnoresUnreportedPartsAndSummarizesLowestBud() {
        let airpods = HeadphoneBattery(left: 80, right: 72, caseLevel: 0)
        #expect(airpods.summary == 72)
        #expect(airpods.caseLevel == nil)
        #expect(airpods.hasSides)
        #expect(HeadphoneBattery(single: 55).summary == 55)
        #expect(HeadphoneBattery(single: 0, left: 0).isEmpty)
        #expect(HeadphoneStyle(name: "AirPods Pro de Ana") == .airpodsPro)
        #expect(HeadphoneStyle(name: "AirPods Max") == .airpodsMax)
        #expect(HeadphoneStyle(name: "WH-1000XM5") == .headphones)
    }

    @Test func testClipKindsRecognizeLinksAndColors() {
        #expect(ClipKind.classify("https://github.com/ViniciusInTech/notch") == .link)
        #expect(ClipKind.classify("  #7B5CD6\n") == .color)
        #expect(ClipKind.classify("#fff") == .color)
        #expect(ClipKind.classify("#12345") == .text)
        #expect(ClipKind.classify("veja https://example.com") == .text)
        #expect(ClipKind.classify("ftp://example.com") == .text)
        #expect(ClipKind.classify("git push -u origin main") == .text)
    }

    @Test func testClipboardMovesRepeatsUpKeepsPinsAndTrimsUnpinned() {
        var clipboard = Clipboard()
        let start = Date(timeIntervalSince1970: 1_000)
        clipboard.add(.text("a", at: start), limit: 2)
        clipboard.add(.text("b", at: start.addingTimeInterval(1)), limit: 2)
        clipboard.togglePin(clipboard.entries[1].id)  // pin "a"
        clipboard.add(.text("c", at: start.addingTimeInterval(2)), limit: 2)
        clipboard.add(.text("d", at: start.addingTimeInterval(3)), limit: 2)
        #expect(clipboard.entries.map(\.text) == ["d", "c", "a"])
        clipboard.add(.text("a", at: start.addingTimeInterval(4)), limit: 2)
        #expect(clipboard.entries.map(\.text) == ["a", "d", "c"])
        #expect(clipboard.entries[0].pinned)
        let cleared = clipboard.clearUnpinned()
        #expect(cleared.count == 2)
        #expect(clipboard.entries.map(\.text) == ["a"])
    }

    @Test func testClipboardExpiryKeepsPinnedEntries() {
        let now = Date(timeIntervalSince1970: 100_000)
        var clipboard = Clipboard()
        clipboard.add(.text("old", at: now.addingTimeInterval(-7200)), limit: 20)
        clipboard.add(.text("kept", at: now.addingTimeInterval(-7200)), limit: 20)
        clipboard.togglePin(clipboard.entries[0].id)
        clipboard.add(.text("new", at: now), limit: 20)
        let expired = clipboard.removeExpired(at: now, hours: 1)
        #expect(expired.map(\.text) == ["old"])
        #expect(Set(clipboard.entries.compactMap(\.text)) == ["kept", "new"])
        #expect(clipboard.removeExpired(at: now, hours: 0).isEmpty)
    }

    @Test func testClipboardPolicySkipsPrivateContentIgnoredAppsAndOtherShortcuts() {
        #expect(ClipboardPolicy.shouldSkip(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], sourceBundle: nil, ignored: []))
        #expect(ClipboardPolicy.shouldSkip(types: ["public.utf8-plain-text"], sourceBundle: "com.apple.Passwords", ignored: ClipboardPolicy.defaultIgnoredApps))
        #expect(!ClipboardPolicy.shouldSkip(types: ["public.utf8-plain-text"], sourceBundle: "com.apple.Safari", ignored: ClipboardPolicy.defaultIgnoredApps))
        #expect(ClipboardPolicy.isCopyShortcut(characters: "c", keyCode: 8, command: true, control: false, option: false))
        #expect(ClipboardPolicy.isCopyShortcut(characters: "x", keyCode: 99, command: true, control: false, option: false))
        // Dvorak: the C key code sends "j", which is not a copy.
        #expect(!ClipboardPolicy.isCopyShortcut(characters: "j", keyCode: 8, command: true, control: false, option: false))
        #expect(!ClipboardPolicy.isCopyShortcut(characters: "c", keyCode: 8, command: true, control: false, option: true))
        #expect(!ClipboardPolicy.isCopyShortcut(characters: "c", keyCode: 8, command: false, control: false, option: false))
        #expect(ClipboardPolicy.isCopyShortcut(characters: nil, keyCode: 7, command: true, control: false, option: false))
    }
}
