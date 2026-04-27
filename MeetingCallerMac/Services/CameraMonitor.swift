import SwiftUI
import Combine
import CoreMediaIO
import AVFoundation

class CameraMonitor: ObservableObject {
    @Published var isCameraActive: Bool = false

    private var pollTimer: Timer?
    private var onCameraOn: (() -> Void)?
    private var onCameraOff: (() -> Void)?
    private var wasActive = false
    private var debounceWorkItem: DispatchWorkItem?

    func start(onCameraOn: @escaping () -> Void, onCameraOff: @escaping () -> Void) {
        self.onCameraOn = onCameraOn
        self.onCameraOff = onCameraOff

        // Enable access to system camera properties
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, UInt32(MemoryLayout.size(ofValue: allow)), &allow)

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkCameraState()
        }
        checkCameraState()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        debounceWorkItem?.cancel()
    }

    private func checkCameraState() {
        let active = isCameraInUse()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isCameraActive = active

            if active && !self.wasActive {
                // Camera just turned ON — cancel any pending off-debounce, trigger immediately
                self.debounceWorkItem?.cancel()
                self.debounceWorkItem = nil
                self.wasActive = true
                print("CameraMonitor: ON detected")
                self.onCameraOn?()
            } else if !active && self.wasActive && self.debounceWorkItem == nil {
                // Camera just turned OFF — start debounce (only once, don't reset)
                print("CameraMonitor: OFF detected, debouncing 3s...")
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.debounceWorkItem = nil
                    if !self.isCameraActive {
                        self.wasActive = false
                        print("CameraMonitor: OFF confirmed after debounce")
                        self.onCameraOff?()
                    } else {
                        print("CameraMonitor: camera came back during debounce")
                    }
                }
                self.debounceWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
            }
        }
    }

    private func isCameraInUse() -> Bool {
        // Get all video devices
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        let status = CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }

        let deviceCount = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: deviceCount)
        CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &propertyAddress, 0, nil, dataSize, &dataSize, &devices)

        for device in devices {
            if isDeviceRunning(device) { return true }
        }
        return false
    }

    private func isDeviceRunning(_ deviceID: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = CMIOObjectGetPropertyData(deviceID, &address, 0, nil, dataSize, &dataSize, &isRunning)
        return status == noErr && isRunning != 0
    }
}
