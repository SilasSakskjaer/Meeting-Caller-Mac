import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var meeting: MeetingService
    @EnvironmentObject var camera: CameraMonitor
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openWindow) var openWindow

    @State private var showStopConfirmation = false
    @State private var stopTimer: Timer?
    @State private var stopCountdown = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            HStack {
                Circle()
                    .fill(meeting.isReachable ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(meeting.deviceName)
                    .font(.headline)
                Spacer()
                if meeting.isInMeeting {
                    Text(formatDuration(meeting.meetingDuration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Meeting state
            HStack {
                Image(systemName: meeting.isInMeeting ? "record.circle.fill" : "circle")
                    .foregroundColor(meeting.isInMeeting ? .red : .secondary)
                Text(stateText)
                    .font(.body)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Camera status
            HStack {
                Image(systemName: camera.isCameraActive ? "camera.fill" : "camera")
                    .foregroundColor(camera.isCameraActive ? .green : .secondary)
                Text(camera.isCameraActive ? "Kamera aktivt" : "Kamera inaktivt")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if settings.autoStartEnabled {
                    Text("Auto")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            // Meeting controls
            if meeting.isInMeeting {
                Button {
                    Task { await meeting.pauseMeeting() }
                } label: {
                    Label(meeting.meetingState == "paused" ? "Genoptag" : "Pause",
                          systemImage: meeting.meetingState == "paused" ? "play.fill" : "pause.fill")
                }
                .padding(.horizontal, 12).padding(.vertical, 4)

                Button(role: .destructive) {
                    Task { await meeting.stopMeeting() }
                } label: {
                    Label("Stop m\u{00f8}de", systemImage: "stop.fill")
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
            } else {
                Button {
                    Task { await meeting.startMeeting() }
                } label: {
                    Label("Start m\u{00f8}de", systemImage: "play.fill")
                }
                .disabled(!meeting.isReachable)
                .padding(.horizontal, 12).padding(.vertical, 4)
            }

            Divider()

            // Wiz light control
            if meeting.wizReachable {
                Button {
                    Task { await meeting.toggleWiz() }
                } label: {
                    Label(meeting.wizState ? "Sluk lys" : "T\u{00e6}nd lys",
                          systemImage: meeting.wizState ? "lightbulb.fill" : "lightbulb")
                }
                .padding(.horizontal, 12).padding(.vertical, 4)

                Divider()
            }

            // Callers
            if !meeting.callers.isEmpty {
                Text("Callere")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                ForEach(meeting.callers) { caller in
                    HStack {
                        Circle()
                            .fill(caller.active ? .green : .red)
                            .frame(width: 6, height: 6)
                        Text(caller.name)
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 1)
                }

                Divider()
            }

            // Bottom actions
            Toggle("Automatisk", isOn: $settings.autoStartEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            Button {
                openWindow(id: "dashboard")
            } label: {
                Label("Dashboard", systemImage: "square.grid.2x2")
            }
            .padding(.horizontal, 12).padding(.vertical, 4)

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Indstillinger...", systemImage: "gear")
            }
            .padding(.horizontal, 12).padding(.vertical, 4)

            Divider()

            Button("Afslut") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
        }
        .frame(width: 260)
        .onAppear {
            meeting.configure(settings: settings)
            setupCameraCallbacks()
        }
    }

    private var stateText: String {
        switch meeting.meetingState {
        case "active": return "M\u{00f8}de igang"
        case "paused": return "Pause"
        case "incoming_call": return "Incoming call..."
        case "idle": return "Intet m\u{00f8}de"
        default: return meeting.isReachable ? "Klar" : "Ikke forbundet"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func setupCameraCallbacks() {
        camera.start(
            onCameraOn: { [self] in
                guard settings.autoStartEnabled, !meeting.isInMeeting else { return }
                Task {
                    let started = await meeting.startMeeting()
                    if started && settings.wizSyncEnabled {
                        // Show light popup
                        showLightPopup()
                    }
                }
            },
            onCameraOff: { [self] in
                guard settings.autoStopEnabled, meeting.isInMeeting else { return }
                // Wait 2 minutes then show stop confirmation
                scheduleStopConfirmation()
            }
        )
    }

    private func showLightPopup() {
        // Post notification for light control popup
        NotificationCenter.default.post(name: .showLightControl, object: nil)
    }

    private func scheduleStopConfirmation() {
        stopCountdown = settings.stopDelaySeconds
        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] timer in
            stopCountdown -= 1
            if stopCountdown <= 0 {
                timer.invalidate()
                // Show stop confirmation popup
                NotificationCenter.default.post(name: .showStopConfirmation, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let showLightControl = Notification.Name("showLightControl")
    static let showStopConfirmation = Notification.Name("showStopConfirmation")
}
