import CoreAudio
import CoreMediaIO
import Foundation

/// Reports whether another app uses a camera or the default microphone. Only HAL property
/// listeners are registered, so nothing polls; every call runs on the monitor's own queue.
final class CallMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.vinicius.Notch.calls")
    private var onChange: (@Sendable (Bool) -> Void)?
    private var microphone = true
    private var running = false
    private var last = false
    private var cameras: [CMIOObjectID] = []
    private var input = AudioObjectID(kAudioObjectUnknown)

    private lazy var deviceListener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.evaluate() }
    private lazy var cameraListListener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.bindCameras(); self?.evaluate() }
    private lazy var inputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.evaluate() }
    private lazy var defaultInputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.bindInput(); self?.evaluate() }

    private var cameraListAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    private var cameraRunningAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private var inputRunningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// `onChange` receives the first state and every change after it.
    func start(microphone: Bool, onChange: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            if running { unbind() }
            self.microphone = microphone
            self.onChange = onChange
            running = true
            last = false
            CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameraListAddress, queue, cameraListListener)
            bindCameras()
            if microphone {
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, queue, defaultInputListener)
                bindInput()
            }
            let now = inUse()
            last = now
            onChange(now)
        }
    }

    func stop() {
        queue.async { [self] in
            guard running else { return }
            unbind()
            running = false
            onChange = nil
        }
    }

    private func unbind() {
        CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameraListAddress, queue, cameraListListener)
        for camera in cameras { CMIOObjectRemovePropertyListenerBlock(camera, &cameraRunningAddress, queue, deviceListener) }
        cameras = []
        if microphone {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, queue, defaultInputListener)
        }
        if input != kAudioObjectUnknown { AudioObjectRemovePropertyListenerBlock(input, &inputRunningAddress, queue, inputListener) }
        input = AudioObjectID(kAudioObjectUnknown)
    }

    private func bindCameras() {
        for camera in cameras { CMIOObjectRemovePropertyListenerBlock(camera, &cameraRunningAddress, queue, deviceListener) }
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &cameraListAddress, 0, nil, &size) == 0, size > 0 else { cameras = []; return }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &cameraListAddress, 0, nil, size, &used, &devices) == 0 else { cameras = []; return }
        cameras = devices
        for camera in cameras { CMIOObjectAddPropertyListenerBlock(camera, &cameraRunningAddress, queue, deviceListener) }
    }

    private func bindInput() {
        if input != kAudioObjectUnknown { AudioObjectRemovePropertyListenerBlock(input, &inputRunningAddress, queue, inputListener) }
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, 0, nil, &size, &device)
        input = status == noErr ? device : AudioObjectID(kAudioObjectUnknown)
        if input != kAudioObjectUnknown { AudioObjectAddPropertyListenerBlock(input, &inputRunningAddress, queue, inputListener) }
    }

    private func inUse() -> Bool {
        for camera in cameras {
            var running: UInt32 = 0
            var used: UInt32 = 0
            if CMIOObjectGetPropertyData(camera, &cameraRunningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == 0,
               running != 0 { return true }
        }
        guard microphone, input != kAudioObjectUnknown else { return false }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(input, &inputRunningAddress, 0, nil, &size, &running) == noErr && running != 0
    }

    private func evaluate() {
        guard running else { return }
        let now = inUse()
        guard now != last else { return }
        last = now
        onChange?(now)
    }
}
