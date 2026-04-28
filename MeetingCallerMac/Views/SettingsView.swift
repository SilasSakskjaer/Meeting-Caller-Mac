import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var meeting: MeetingService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var wiz: WizService

    var body: some View {
        Form {
            Section("Forbindelse") {
                Toggle("Autodiscovery", isOn: $settings.useMDNS)
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
                    Text("Pause + sp\u{00f8}rg").tag(3)
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
                HStack {
                    TextField("Wiz IP", text: $settings.wizIP)
                        .textFieldStyle(.roundedBorder)
                    Button("Scan") {
                        wiz.scanForDevices()
                    }
                }
                if !wiz.devices.isEmpty {
                    Picker("Fundne enheder", selection: $settings.wizIP) {
                        ForEach(wiz.devices) { device in
                            Text(device.displayName).tag(device.ip)
                        }
                    }
                }
                Picker("Ved m\u{00f8}destart", selection: $settings.wizOnAction) {
                    Text("Sp\u{00f8}rg (popup)").tag(0)
                    Text("T\u{00e6}nd automatisk").tag(1)
                    Text("Ingen handling").tag(2)
                }
                Toggle("Sluk lys n\u{00e5}r m\u{00f8}de stopper", isOn: $settings.wizOffWithMeeting)
                HStack {
                    Circle()
                        .fill(wiz.reachable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(wiz.reachable ? (wiz.state ? "T\u{00e6}ndt" : "Slukket") : "Ikke fundet")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 480)
    }
}
