import AppKit

class AppStartup: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("App launched — initializing services")
        AppState.shared.initialize()
    }
}
