import SwiftUI

@main
struct MeetingCallerMacApp: App {
    @StateObject private var meetingService = MeetingService()
    @StateObject private var cameraMonitor = CameraMonitor()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(meetingService)
                .environmentObject(cameraMonitor)
                .environmentObject(settings)
        } label: {
            Image(systemName: meetingService.iconName)
        }

        Settings {
            SettingsView()
                .environmentObject(meetingService)
                .environmentObject(settings)
        }

        Window("Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(meetingService)
                .environmentObject(cameraMonitor)
                .environmentObject(settings)
                .frame(minWidth: 400, minHeight: 500)
        }
    }
}
