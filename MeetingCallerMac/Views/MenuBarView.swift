import SwiftUI
import AppKit

struct MenuBarMenu: View {
    @EnvironmentObject var meeting: MeetingService
    @EnvironmentObject var camera: CameraMonitor
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        // Status
        Text(meeting.isReachable ? "\(meeting.deviceName)" : "Ikke forbundet")

        if meeting.isInMeeting {
            Text("Møde: \(formatDuration(meeting.meetingDuration))")
        }

        Text(camera.isCameraActive ? "📷 Kamera aktivt" : "📷 Kamera inaktivt")

        Divider()

        // Meeting controls
        if meeting.isInMeeting {
            Button(meeting.meetingState == "paused" ? "▶ Genoptag" : "⏸ Pause") {
                meeting.fireAndForget { await meeting.pauseMeeting() }
            }
            Button("⏹ Stop møde") {
                meeting.fireAndForget { await meeting.stopMeeting() }
            }
        } else {
            Button("▶ Start møde") {
                meeting.fireAndForget { await meeting.startMeeting() }
            }
            .disabled(!meeting.isReachable)
        }

        Divider()

        // Wiz light
        if meeting.wizReachable {
            Button(meeting.wizState ? "💡 Sluk lys" : "💡 Tænd lys") {
                meeting.fireAndForget { await meeting.toggleWiz() }
            }
            Divider()
        }

        // Callers
        if !meeting.callers.isEmpty {
            Text("Callere:")
            ForEach(meeting.callers) { caller in
                Text("  \(caller.active ? "🟢" : "🔴") \(caller.name)")
            }
            Divider()
        }

        // Auto toggle
        Toggle("Automatisk", isOn: $settings.autoStartEnabled)

        // Dashboard
        Button("Dashboard") {
            DashboardWindowController.shared.show(
                meeting: meeting, camera: camera, settings: settings
            )
        }

        Button("Indstillinger...") {
            SettingsWindowController.shared.show(
                meeting: meeting, settings: settings
            )
        }

        Divider()

        Button("Afslut") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Window Controllers

class DashboardWindowController {
    static let shared = DashboardWindowController()
    private var window: NSWindow?

    func show(meeting: MeetingService, camera: CameraMonitor, settings: AppSettings) {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = DashboardView()
            .environmentObject(meeting)
            .environmentObject(camera)
            .environmentObject(settings)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        w.title = "Meeting Caller — Dashboard"
        w.contentView = NSHostingView(rootView: view)
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.center()
        NSApp.setActivationPolicy(.accessory)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window = w
    }
}

class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(meeting: MeetingService, settings: AppSettings) {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = SettingsView()
            .environmentObject(meeting)
            .environmentObject(settings)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        w.title = "Meeting Caller — Indstillinger"
        w.contentView = NSHostingView(rootView: view)
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.center()
        NSApp.setActivationPolicy(.accessory)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window = w
    }
}
