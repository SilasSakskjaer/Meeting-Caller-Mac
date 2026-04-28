import SwiftUI
import AppKit

struct MenuBarMenu: View {
    @EnvironmentObject var meeting: MeetingService
    @EnvironmentObject var camera: CameraMonitor
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var wiz: WizService

    var body: some View {
        // Status
        if meeting.isReachable && meeting.isAuthenticated {
            Text("🟢 \(meeting.deviceName)")
        } else if meeting.isReachable && !meeting.isAuthenticated {
            Text("🟡 Forbundet, forkert kode")
        } else {
            Text("🔴 Ikke forbundet")
        }
        if meeting.isReachable, let ip = meeting.settings?.masterIP, !ip.isEmpty {
            Text("    IP: \(ip)").font(.caption)
        }

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
        if wiz.reachable {
            Text(wiz.state ? "💡 Lys: Tændt" : "💡 Lys: Slukket")
            Button(wiz.state ? "Sluk lys" : "Tænd lys") {
                wiz.toggle()
            }
            Divider()
        } else if !settings.wizIP.isEmpty {
            Text("💡 Lys: Ikke fundet")
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
                meeting: meeting, camera: camera, settings: settings, wiz: wiz
            )
        }

        Button("Indstillinger...") {
            SettingsWindowController.shared.show(
                meeting: meeting, settings: settings, wiz: wiz
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

    func show(meeting: MeetingService, camera: CameraMonitor, settings: AppSettings, wiz: WizService? = nil) {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = DashboardView()
            .environmentObject(meeting)
            .environmentObject(camera)
            .environmentObject(settings)
            .environmentObject(wiz ?? AppState.shared.wizService)
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

    func show(meeting: MeetingService, settings: AppSettings, wiz: WizService? = nil) {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = SettingsView()
            .environmentObject(meeting)
            .environmentObject(settings)
            .environmentObject(wiz ?? AppState.shared.wizService)
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
