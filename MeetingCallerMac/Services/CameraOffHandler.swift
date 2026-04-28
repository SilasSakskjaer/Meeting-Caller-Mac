import Foundation
import UserNotifications

class CameraOffHandler: ObservableObject {
    private var timer: Timer?
    private var meetingService: MeetingService?
    private var cameraMonitor: CameraMonitor?
    private var settings: AppSettings?
    private var countdown = 0
    private var notificationsAvailable = false
    var onMeetingStopped: (() -> Void)?

    private lazy var notificationDelegate = NotificationActionDelegate(handler: self)

    func configure(meeting: MeetingService, camera: CameraMonitor, settings: AppSettings) {
        self.meetingService = meeting
        self.cameraMonitor = camera
        self.settings = settings
        setupNotifications()
    }

    private func setupNotifications() {
        // UNUserNotificationCenter requires a valid bundle identifier
        guard Bundle.main.bundleIdentifier != nil else {
            print("Notifications: no bundle identifier — using popup fallback")
            return
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error { print("Notification auth error: \(error)") }
            self?.notificationsAvailable = granted
            print("Notification auth: \(granted)")
        }

        // Register actions
        let stopAction = UNNotificationAction(identifier: "STOP_MEETING", title: "Stop m\u{00f8}de", options: [.destructive])
        let resumeAction = UNNotificationAction(identifier: "RESUME_MEETING", title: "Genoptag", options: [])
        let category = UNNotificationCategory(
            identifier: "MEETING_PAUSE",
            actions: [stopAction, resumeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func scheduleAction() {
        print("scheduleAction: settings=\(settings != nil) meeting=\(meetingService != nil) inMeeting=\(meetingService?.isInMeeting ?? false) state=\(meetingService?.meetingState ?? "nil")")
        guard let settings, let meetingService, meetingService.isInMeeting else {
            print("scheduleAction: guard failed — skipping")
            return
        }

        timer?.invalidate()
        countdown = settings.stopDelaySeconds
        let action = settings.cameraOffAction
        print("Camera off — action \(action) in \(countdown)s")

        // Pause + spørg: pause instantly, then wait for notification
        if action == 3 {
            if meetingService.meetingState == "active" {
                meetingService.fireAndForget { await meetingService.pauseMeeting() }
                print("Instant pause (pause + spørg)")
            }
        }

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
                    self.onMeetingStopped?()
                    print("Auto-stopped meeting")
                case 2:
                    if self.meetingService?.meetingState == "active" {
                        self.meetingService?.fireAndForget { await self.meetingService!.pauseMeeting() }
                        print("Auto-paused meeting")
                    }
                case 3:
                    // Pause already happened instantly — show notification or popup
                    if self.notificationsAvailable {
                        self.sendNotification()
                    } else {
                        self.showPausePopup()
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
        if notificationsAvailable {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["meeting-pause"])
        }
    }

    // MARK: - Notification Center

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "M\u{00f8}de p\u{00e5} pause"
        let timeText = formatDelay()
        content.body = "Kamera har v\u{00e6}ret slukket i \(timeText). Vil du stoppe eller genoptage?"
        content.sound = .default
        content.categoryIdentifier = "MEETING_PAUSE"

        let request = UNNotificationRequest(identifier: "meeting-pause", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Notification error: \(error)") }
            else { print("Sent meeting pause notification") }
        }
    }

    func handleNotificationAction(_ actionIdentifier: String) {
        switch actionIdentifier {
        case "STOP_MEETING":
            meetingService?.fireAndForget { await self.meetingService!.stopMeeting() }
            onMeetingStopped?()
            print("Notification: stopped meeting")
        case "RESUME_MEETING":
            if meetingService?.meetingState == "paused" {
                meetingService?.fireAndForget { await self.meetingService!.pauseMeeting() }
                print("Notification: resumed meeting")
            }
        default:
            break
        }
    }

    // MARK: - Popups

    private func showPausePopup() {
        guard let meetingService, meetingService.isInMeeting else { return }
        let timeText = formatDelay()

        DispatchQueue.main.async {
            StopPopupController.shared.show(
                timeText: timeText,
                onStop: { [self] in
                    meetingService.fireAndForget { await meetingService.stopMeeting() }
                    self.onMeetingStopped?()
                },
                onPause: {
                    if meetingService.meetingState == "paused" {
                        meetingService.fireAndForget { await meetingService.pauseMeeting() }
                    }
                }
            )
        }
    }

    private func showPopup() {
        guard let meetingService, meetingService.isInMeeting else { return }
        let timeText = formatDelay()

        DispatchQueue.main.async {
            StopPopupController.shared.show(
                timeText: timeText,
                onStop: { [self] in
                    meetingService.fireAndForget { await meetingService.stopMeeting() }
                    self.onMeetingStopped?()
                },
                onPause: { meetingService.fireAndForget { await meetingService.pauseMeeting() } }
            )
        }
    }

    private func formatDelay() -> String {
        let delay = settings?.stopDelaySeconds ?? 0
        return delay >= 120 ? "\(delay / 60) minutter" : delay >= 60 ? "1 minut" : "\(delay) sekunder"
    }
}

// MARK: - Notification Delegate

private class NotificationActionDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var handler: CameraOffHandler?

    init(handler: CameraOffHandler) {
        self.handler = handler
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        handler?.handleNotificationAction(response.actionIdentifier)
        completionHandler()
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
