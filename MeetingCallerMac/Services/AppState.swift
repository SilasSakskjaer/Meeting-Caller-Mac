import Foundation

class AppState {
    static let shared = AppState()

    let meetingService = MeetingService()
    let cameraMonitor = CameraMonitor()
    let settings = AppSettings()
    let cameraOffHandler = CameraOffHandler()
    let wizService = WizService()
    private var initialized = false

    func initialize() {
        guard !initialized else { return }
        initialized = true

        print("Configuring services...")
        meetingService.configure(settings: settings)
        cameraOffHandler.configure(meeting: meetingService, camera: cameraMonitor, settings: settings)
        wizService.configure(settings: settings)
        wizService.startPolling()

        cameraMonitor.start(
            onCameraOn: { [self] in
                cameraOffHandler.cancel()

                // Resume if paused
                if meetingService.meetingState == "paused" {
                    meetingService.fireAndForget { await self.meetingService.pauseMeeting() }
                    print("Camera ON — resuming paused meeting")
                    return
                }

                guard settings.autoStartEnabled, !meetingService.isInMeeting else { return }
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

        // Handle light-off when meeting stops
        cameraOffHandler.onMeetingStopped = { [self] in
            if settings.wizOffWithMeeting && wizService.state {
                wizService.turnOff()
                print("Meeting stopped — turning off light")
            }
        }

        if settings.masterIP.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                SettingsWindowController.shared.show(meeting: meetingService, settings: settings, wiz: wizService)
            }
        }
    }

    private func handleLightOnMeetingStart() {
        guard wizService.reachable else { return }

        switch settings.wizOnAction {
        case 1: // Auto tænd
            if !wizService.state {
                wizService.turnOn()
                print("Auto-turning on light")
            }
        case 0: // Spørg popup
            LightPopupController.shared.show(
                isOn: wizService.state,
                onToggle: { [self] in
                    wizService.toggle()
                },
                onDismiss: {}
            )
        default: // Manual — do nothing
            break
        }
    }
}
