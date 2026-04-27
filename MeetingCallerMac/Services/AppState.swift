import Foundation

class AppState {
    static let shared = AppState()

    let meetingService = MeetingService()
    let cameraMonitor = CameraMonitor()
    let settings = AppSettings()
    let cameraOffHandler = CameraOffHandler()
    private var initialized = false

    func initialize() {
        guard !initialized else { return }
        initialized = true

        print("Configuring services...")
        meetingService.configure(settings: settings)
        cameraOffHandler.configure(meeting: meetingService, camera: cameraMonitor, settings: settings)

        cameraMonitor.start(
            onCameraOn: { [self] in
                guard settings.autoStartEnabled, !meetingService.isInMeeting else { return }
                cameraOffHandler.cancel()
                meetingService.fireAndForget { await self.meetingService.startMeeting() }
                print("Camera ON — starting meeting")
            },
            onCameraOff: { [self] in
                guard meetingService.isInMeeting else { return }
                print("Camera OFF — scheduling action")
                cameraOffHandler.scheduleAction()
            }
        )

        if settings.masterIP.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                SettingsWindowController.shared.show(meeting: meetingService, settings: settings)
            }
        }
    }
}
