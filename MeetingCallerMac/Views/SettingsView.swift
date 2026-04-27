import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var meeting: MeetingService
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Forbindelse") {
                Toggle("Brug mDNS autodiscovery", isOn: $settings.useMDNS)
                TextField("Master IP", text: $settings.masterIP)
                    .textFieldStyle(.roundedBorder)
                    .disabled(settings.useMDNS)
                SecureField("Password", text: $settings.password)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Circle()
                        .fill(meeting.isReachable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(meeting.isReachable ? "Forbundet til \(meeting.deviceName)" : "Ikke forbundet")
                        .font(.caption)
                }
            }

            Section("Automatik") {
                Toggle("Start m\u{00f8}de n\u{00e5}r kamera t\u{00e6}ndes", isOn: $settings.autoStartEnabled)

                Picker("N\u{00e5}r kamera slukkes", selection: $settings.cameraOffAction) {
                    Text("Sp\u{00f8}rg (popup)").tag(0)
                    Text("Stop m\u{00f8}de").tag(1)
                    Text("Pause m\u{00f8}de").tag(2)
                }

                Picker("Forsinkelse", selection: $settings.stopDelaySeconds) {
                    Text("5 sekunder").tag(5)
                    Text("30 sekunder").tag(30)
                    Text("1 minut").tag(60)
                    Text("2 minutter").tag(120)
                    Text("5 minutter").tag(300)
                }
            }

            Section("Lys (Wiz Plug)") {
                Toggle("Vis lys-popup ved m\u{00f8}destart", isOn: $settings.wizSyncEnabled)
                HStack {
                    Text("Status:")
                    Text(meeting.wizReachable ? (meeting.wizState ? "T\u{00e6}ndt" : "Slukket") : "Ikke fundet")
                        .foregroundColor(meeting.wizReachable ? .primary : .red)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 400)
    }
}
