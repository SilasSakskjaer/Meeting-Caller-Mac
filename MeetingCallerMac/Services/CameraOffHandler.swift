import Foundation

class CameraOffHandler: ObservableObject {
    private var timer: Timer?
    private var meetingService: MeetingService?
    private var cameraMonitor: CameraMonitor?
    private var settings: AppSettings?
    private var countdown = 0

    func configure(meeting: MeetingService, camera: CameraMonitor, settings: AppSettings) {
        self.meetingService = meeting
        self.cameraMonitor = camera
        self.settings = settings
    }

    func scheduleAction() {
        guard let settings, let meetingService, meetingService.isInMeeting else { return }

        timer?.invalidate()
        countdown = settings.stopDelaySeconds
        let action = settings.cameraOffAction
        print("Camera off — action \(action) in \(countdown)s")

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }

            // Camera came back on
            if self.cameraMonitor?.isCameraActive == true {
                print("Camera back on — cancelling")
                t.invalidate()
                self.timer = nil
                return
            }
            // Meeting ended
            if self.meetingService?.isInMeeting != true {
                t.invalidate()
                self.timer = nil
                return
            }

            self.countdown -= 1
            print("Countdown: \(self.countdown)s")

            if self.countdown <= 0 {
                t.invalidate()
                self.timer = nil

                switch action {
                case 1:
                    self.meetingService?.fireAndForget { await self.meetingService!.stopMeeting() }
                    print("Auto-stopped meeting")
                case 2:
                    if self.meetingService?.meetingState == "active" {
                        self.meetingService?.fireAndForget { await self.meetingService!.pauseMeeting() }
                        print("Auto-paused meeting")
                    }
                default:
                    self.showPopup()
                }
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    private func showPopup() {
        guard let meetingService, let settings, meetingService.isInMeeting else { return }

        let delay = settings.stopDelaySeconds
        let timeText = delay >= 120 ? "\(delay / 60) minutter" : delay >= 60 ? "1 minut" : "\(delay) sekunder"

        DispatchQueue.main.async {
            StopPopupController.shared.show(
                timeText: timeText,
                onStop: { meetingService.fireAndForget { await meetingService.stopMeeting() } },
                onPause: { meetingService.fireAndForget { await meetingService.pauseMeeting() } }
            )
        }
    }
}
