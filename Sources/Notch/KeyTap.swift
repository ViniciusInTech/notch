import AppKit
import ApplicationServices
import NotchCore
import os

private let tapLog = Logger(subsystem: "dev.vinicius.Notch", category: "keys")

/// Event taps on their own thread for the two features that need keys: the volume and brightness
/// keys (taken over so the macOS HUD stays hidden) and Command-C/X (a hint to look at the pasteboard
/// once). The always-on tap only sees those special keys and modifier changes, never typing; the
/// key tap is switched on while Command is held and off when it is released, so ordinary text never
/// reaches the app. They exist only while one feature is on; nothing polls. Requires Accessibility;
/// the volume and brightness are changed on the tap thread, never on the main actor.
final class KeyTap: @unchecked Sendable {
    struct Options: Equatable { var levels = false; var copy = false; var any: Bool { levels || copy } }

    /// Called on the main actor.
    var onLevel: (@MainActor (SystemLevel) -> Void)?
    var onCopy: (@MainActor () -> Void)?

    private let lock = NSLock()
    private var options = Options()
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var port: CFMachPort?
    /// Key presses, enabled only while Command is down.
    private var keyPort: CFMachPort?
    /// Touched only on the tap thread.
    private var commandDown = false

    static var trusted: Bool { AXIsProcessTrusted() }

    /// Shows the macOS prompt that leads to Privacy & Security → Accessibility.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts, reconfigures or stops the tap. Returns false when Accessibility is missing.
    @discardableResult func configure(_ next: Options) -> Bool {
        lock.lock()
        options = next
        let running = thread != nil
        lock.unlock()
        if !next.any { stop(); return true }
        guard Self.trusted else { stop(); return false }
        if !running { start() }
        return true
    }

    private func start() {
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "dev.vinicius.Notch.keys"
        thread.qualityOfService = .userInteractive
        lock.lock(); self.thread = thread; lock.unlock()
        thread.start()
    }

    func stop() {
        lock.lock()
        let loop = runLoop
        thread = nil
        lock.unlock()
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(loop) }
        CFRunLoopWakeUp(loop)
    }

    private func run() {
        // NX_SYSDEFINED (14) carries the volume and brightness keys.
        let baseMask = (1 << 14) | (1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let current = Thread.current
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(baseMask), callback: keyTapCallback, userInfo: context),
              // An active tap needs only Accessibility; a listen-only key tap would also ask for Input Monitoring.
              let keyPort = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                              callback: keyTapCallback, userInfo: context) else {
            tapLog.error("tap not created")
            lock.lock(); if thread === current { thread = nil }; lock.unlock()
            return
        }
        CGEvent.tapEnable(tap: keyPort, enable: false)
        commandDown = false
        let loop = CFRunLoopGetCurrent()!
        // A stop (or a stop and a new start) may have come while this thread was starting.
        lock.lock()
        let cancelled = thread !== current
        if !cancelled { self.port = port; self.keyPort = keyPort; runLoop = loop }
        lock.unlock()
        if !cancelled {
            CFRunLoopAddSource(loop, CFMachPortCreateRunLoopSource(nil, port, 0), .defaultMode)
            CFRunLoopAddSource(loop, CFMachPortCreateRunLoopSource(nil, keyPort, 0), .defaultMode)
            tapLog.info("tap started")
            CFRunLoopRun()
        }
        for tap in [port, keyPort] {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        lock.lock()
        if self.port === port { self.port = nil; self.keyPort = nil; runLoop = nil }
        lock.unlock()
        if !cancelled { tapLog.info("tap stopped") }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        lock.lock(); let options = self.options, port = self.port, keyPort = self.keyPort; lock.unlock()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            if let keyPort, commandDown { CGEvent.tapEnable(tap: keyPort, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        if type == .flagsChanged {
            let down = options.copy && flags.contains(.maskCommand)
            if down != commandDown, let keyPort {
                commandDown = down
                CGEvent.tapEnable(tap: keyPort, enable: down)
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if options.copy, flags.contains(.maskCommand), event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                // NSEvent's characters ask the input source on the main thread and crash here;
                // the CGEvent carries the typed character itself.
                let characters = Self.characters(of: event)
                if ClipboardPolicy.isCopyShortcut(characters: characters, keyCode: code, command: flags.contains(.maskCommand),
                                                  control: flags.contains(.maskControl), option: flags.contains(.maskAlternate)) {
                    let onCopy = self.onCopy
                    DispatchQueue.main.async { MainActor.assumeIsolated { onCopy?() } }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard options.levels, let ns = NSEvent(cgEvent: event), ns.type == .systemDefined,
              let decoded = MediaKey.decode(subtype: Int(ns.subtype.rawValue), data1: ns.data1) else {
            return Unmanaged.passUnretained(event)
        }
        // Key-up of a key we handle is swallowed too, so the system never sees half a press.
        guard decoded.down else { return handled(decoded.key) ? nil : Unmanaged.passUnretained(event) }
        if decoded.key == .mute && decoded.isRepeat { return nil }
        return take(decoded.key, fine: flags.contains(.maskShift) && flags.contains(.maskAlternate)) ? nil : Unmanaged.passUnretained(event)
    }

    private static func characters(of event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return length > 0 ? String(utf16CodeUnits: buffer, count: length) : nil
    }

    private var lastHandled: Set<String> = []

    private func handled(_ key: MediaKey) -> Bool { lastHandled.contains("\(key)") }

    /// Changes the level and reports it; false hands the key back to macOS.
    private func take(_ key: MediaKey, fine: Bool) -> Bool {
        let level = key.kind == .volume ? SystemAudio.apply(key, fine: fine) : DisplayBrightness.apply(key, fine: fine)
        guard let level else { lastHandled.remove("\(key)"); return false }
        lastHandled.insert("\(key)")
        let onLevel = self.onLevel
        DispatchQueue.main.async { MainActor.assumeIsolated { onLevel?(level) } }
        return true
    }
}

private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyTap>.fromOpaque(info).takeUnretainedValue().handle(type, event)
}
