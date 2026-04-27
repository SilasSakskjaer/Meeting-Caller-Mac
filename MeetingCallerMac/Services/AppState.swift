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

                // Light handling
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                    handleLightOnMeetingStart()
                }
            },
            onCameraOff: { [self] in
                guard meetingService.isInMeeting else {
                    print("Camera OFF — not in meeting, ignoring")
                    return
                }
                print("Camera OFF — scheduling action")
                cameraOffHandler.scheduleAction()
            }
        )

        // Also handle light-off when meeting stops
        cameraOffHandler.onMeetingStopped = { [self] in
            if settings.wizOffWithMeeting && meetingService.wizState {
                meetingService.fireAndForget { await self.meetingService.toggleWiz() }
                print("Meeting stopped — turning off light")
            }
        }

        if settings.masterIP.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                SettingsWindowController.shared.show(meeting: meetingService, settings: settings)
            }
        }
    }

    private func handleLightOnMeetingStart() {
        guard meetingService.wizReachable else { return }

        switch settings.wizOnAction {
        case 1: // Auto tænd
            if !meetingService.wizState {
                meetingService.fireAndForget { await self.meetingService.toggleWiz() }
                print("Auto-turning on light")
            }
        case 0: // Spørg popup
            LightPopupController.shared.show(
                isOn: meetingService.wizState,
                onToggle: { [self] in
                    meetingService.fireAndForget { await self.meetingService.toggleWiz() }
                },
                onDismiss: {}
            )
        default: // Manual — do nothing
            break
        }
    }
}
