import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation
import NotchCore

/// Volume and mute of the default output device. Each call is a single HAL property access.
enum SystemAudio {
    private static var device: AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private static func settable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = address(selector)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    static func level() -> SystemLevel? {
        guard let device else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var volumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr else { return nil }
        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = address(kAudioDevicePropertyMute)
        if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &muted) != noErr { muted = 0 }
        return SystemLevel(kind: .volume, value: Double(volume), muted: muted != 0)
    }

    /// Applies a key the way macOS does: raising unmutes, reaching zero mutes. Nil when the
    /// device has no adjustable volume (HDMI, some interfaces): the key then goes to the system.
    static func apply(_ key: MediaKey, fine: Bool) -> SystemLevel? {
        guard let device, let current = level(),
              settable(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume) else { return nil }
        let canMute = settable(device, kAudioDevicePropertyMute)
        if key == .mute && !canMute { return nil }
        var value = current.value
        var muted = current.muted
        switch key {
        case .mute:
            muted.toggle()
        case .volumeUp, .volumeDown:
            value = LevelStep.next(muted && key == .volumeUp ? 0 : value, up: key == .volumeUp, fine: fine)
            muted = value == 0
            var volume = Float32(value)
            var volumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        default:
            return nil
        }
        if canMute {
            var flag = UInt32(muted ? 1 : 0)
            var muteAddress = address(kAudioDevicePropertyMute)
            AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &flag)
        }
        return SystemLevel(kind: .volume, value: value, muted: canMute && muted)
    }
}

/// Brightness of the built-in display through DisplayServices, the private framework behind the
/// brightness keys and Control Center. Loaded once on first use; without it the keys stay with macOS.
enum DisplayBrightness {
    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let functions: (get: Getter, set: Setter)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return (unsafeBitCast(get, to: Getter.self), unsafeBitCast(set, to: Setter.self))
    }()

    private static var builtIn: CGDirectDisplayID? {
        var count = UInt32(0)
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsAsleep($0) == 0 }
    }

    static func apply(_ key: MediaKey, fine: Bool) -> SystemLevel? {
        guard key.kind == .brightness, let functions, let display = builtIn else { return nil }
        var current = Float(0)
        guard functions.get(display, &current) == 0 else { return nil }
        let next = LevelStep.next(Double(current), up: key == .brightnessUp, fine: fine)
        guard functions.set(display, Float(next)) == 0 else { return nil }
        return SystemLevel(kind: .brightness, value: next)
    }
}
