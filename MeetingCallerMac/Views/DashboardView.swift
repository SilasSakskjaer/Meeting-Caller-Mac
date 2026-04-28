import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var meeting: MeetingService
    @EnvironmentObject var camera: CameraMonitor
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var wiz: WizService

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Connection status card
                GroupBox("Forbindelse") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(meeting.isReachable ? .green : .red)
                                .frame(width: 10, height: 10)
                            Text(meeting.isReachable ? "Forbundet til \(meeting.deviceName)" : "Ikke forbundet")
                                .font(.body)
                            Spacer()
                            Text("FW \(meeting.firmware)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if meeting.isReachable {
                            HStack {
                                Text("IP: \(settings.masterIP)")
                                Spacer()
                                Text("Uptime: \(formatUptime(meeting.uptime))")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(4)
                }

                // Meeting status card
                GroupBox("M\u{00f8}de") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: meeting.isInMeeting ? "record.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundColor(meeting.isInMeeting ? .red : .secondary)
                            VStack(alignment: .leading) {
                                Text(stateText)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                if meeting.isInMeeting {
                                    Text(formatDuration(meeting.meetingDuration))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            if meeting.isInMeeting {
                                Button {
                                    meeting.fireAndForget { await meeting.pauseMeeting() }
                                } label: {
                                    Label(meeting.meetingState == "paused" ? "Genoptag" : "Pause",
                                          systemImage: meeting.meetingState == "paused" ? "play.fill" : "pause.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .controlSize(.large)

                                Button(role: .destructive) {
                                    meeting.fireAndForget { await meeting.stopMeeting() }
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .controlSize(.large)
                            } else {
                                Button {
                                    meeting.fireAndForget { await meeting.startMeeting() }
                                } label: {
                                    Label("Start m\u{00f8}de", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .controlSize(.large)
                                .disabled(!meeting.isReachable)
                            }
                        }
                    }
                    .padding(4)
                }

                // Callers card
                GroupBox("Callere (\(meeting.callerCount))") {
                    VStack(alignment: .leading, spacing: 6) {
                        if meeting.callers.isEmpty {
                            Text("Ingen callere forbundet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(4)
                        } else {
                            ForEach(meeting.callers) { caller in
                                HStack {
                                    Circle()
                                        .fill(caller.active ? .green : .red)
                                        .frame(width: 8, height: 8)
                                    Text(caller.name)
                                    Spacer()
                                    Text(caller.active ? "Online" : "Offline")
                                        .font(.caption)
                                        .foregroundColor(caller.active ? .green : .red)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(4)
                }

                // Light control card
                GroupBox("Lys (Wiz Plug)") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: wiz.state ? "lightbulb.fill" : "lightbulb")
                                .font(.title2)
                                .foregroundColor(wiz.state ? .yellow : .secondary)
                            VStack(alignment: .leading) {
                                Text(wiz.state ? "T\u{00e6}ndt" : "Slukket")
                                    .font(.body)
                                Text(wiz.reachable ? "Tilsluttet" : "Ikke fundet")
                                    .font(.caption)
                                    .foregroundColor(wiz.reachable ? .green : .red)
                            }
                            Spacer()
                            Button {
                                wiz.toggle()
                            } label: {
                                Text(wiz.state ? "Sluk" : "T\u{00e6}nd")
                            }
                            .disabled(!wiz.reachable)
                        }
                    }
                    .padding(4)
                }

                // Camera card
                GroupBox("Kamera") {
                    HStack {
                        Image(systemName: camera.isCameraActive ? "camera.fill" : "camera")
                            .font(.title2)
                            .foregroundColor(camera.isCameraActive ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(camera.isCameraActive ? "I brug" : "Inaktivt")
                            Text(settings.autoStartEnabled ? "Automatik aktiv" : "Manuel styring")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("Auto", isOn: Binding(
                            get: { settings.autoStartEnabled },
                            set: { settings.autoStartEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .padding(4)
                }
            }
            .padding()
        }
        .frame(minWidth: 400)
    }

    private var stateText: String {
        switch meeting.meetingState {
        case "active": return "M\u{00f8}de igang"
        case "paused": return "Pause"
        case "incoming_call": return "Incoming call"
        case "idle": return "Intet m\u{00f8}de"
        default: return "Ukendt"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatUptime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)t \(m)m" }
        return "\(m)m"
    }
}
