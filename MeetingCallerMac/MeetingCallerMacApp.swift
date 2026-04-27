import SwiftUI

@main
struct MeetingCallerMacApp: App {
    @NSApplicationDelegateAdaptor(AppStartup.self) var appDelegate
    private let state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(state.meetingService)
                .environmentObject(state.cameraMonitor)
                .environmentObject(state.settings)
        } label: {
            Image(systemName: state.meetingService.iconName)
        }
        .menuBarExtraStyle(.menu)
    }
}
