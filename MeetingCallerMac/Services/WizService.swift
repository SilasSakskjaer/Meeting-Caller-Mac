import Foundation

struct WizDevice: Identifiable, Hashable {
    let ip: String
    let mac: String
    let isOn: Bool
    let moduleName: String
    var id: String { mac.isEmpty ? ip : mac }

    var displayName: String {
        let shortMac = mac.count >= 6 ? String(mac.suffix(6)) : mac
        let stateIcon = isOn ? "●" : "○"
        if !moduleName.isEmpty {
            return "\(stateIcon) \(moduleName) (\(ip))"
        }
        if !shortMac.isEmpty {
            return "\(stateIcon) \(ip) [\(shortMac)]"
        }
        return "\(stateIcon) \(ip)"
    }
}

class WizService: ObservableObject {
    @Published var devices: [WizDevice] = []
    @Published var state: Bool = false
    @Published var reachable: Bool = false

    private var socket: Int32 = -1
    private var pollTimer: Timer?
    private var settings: AppSettings?
    private let wizPort: UInt16 = 38899

    func configure(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Discovery

    func scanForDevices() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let sock = self.createSocket()
            guard sock >= 0 else { return }
            defer { close(sock) }

            // Phase 1: broadcast getPilot to find all Wiz devices
            let msg = "{\"method\":\"getPilot\",\"params\":{}}"
            self.sendUDPBroadcast(sock: sock, message: msg, port: self.wizPort)

            // Collect responses for 2 seconds
            var found: [(ip: String, mac: String, isOn: Bool)] = []
            let start = Date()
            while Date().timeIntervalSince(start) < 2.0 {
                if let (resp, ip) = self.receiveUDP(sock: sock) {
                    let mac = self.extractString(from: resp, key: "mac") ?? ""
                    let isOn = resp.contains("\"state\":true")
                    if !found.contains(where: { $0.ip == ip }) {
                        found.append((ip: ip, mac: mac, isOn: isOn))
                    }
                }
            }

            // Phase 2: query each device for model info
            var devices: [WizDevice] = []
            for item in found {
                let detailSock = self.createSocket()
                guard detailSock >= 0 else { continue }
                defer { close(detailSock) }

                self.sendUDP(sock: detailSock, message: "{\"method\":\"getDevInfo\",\"params\":{}}", ip: item.ip, port: self.wizPort)
                var moduleName = ""
                if let (resp, _) = self.receiveUDP(sock: detailSock) {
                    moduleName = self.extractString(from: resp, key: "moduleName") ?? ""
                }

                devices.append(WizDevice(ip: item.ip, mac: item.mac, isOn: item.isOn, moduleName: moduleName))
            }

            DispatchQueue.main.async {
                self.devices = devices
                print("WizService: found \(devices.count) device(s)")
                for d in devices {
                    print("  \(d.displayName)")
                }
            }
        }
    }

    // MARK: - Control

    func turnOn() {
        sendCommand("{\"method\":\"setPilot\",\"params\":{\"state\":true}}")
    }

    func turnOff() {
        sendCommand("{\"method\":\"setPilot\",\"params\":{\"state\":false}}")
    }

    func toggle() {
        if state { turnOff() } else { turnOn() }
    }

    // MARK: - Polling

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.pollStatus()
        }
        pollStatus()
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func pollStatus() {
        guard let ip = settings?.wizIP, !ip.isEmpty else {
            DispatchQueue.main.async { self.reachable = false }
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let sock = self.createSocket()
            guard sock >= 0 else {
                DispatchQueue.main.async { self.reachable = false }
                return
            }
            defer { close(sock) }

            let msg = "{\"method\":\"getPilot\",\"params\":{}}"
            self.sendUDP(sock: sock, message: msg, ip: ip, port: self.wizPort)

            if let (resp, _) = self.receiveUDP(sock: sock) {
                let isOn = resp.contains("\"state\":true")
                DispatchQueue.main.async {
                    self.reachable = true
                    self.state = isOn
                }
            } else {
                DispatchQueue.main.async {
                    self.reachable = false
                }
            }
        }
    }

    // MARK: - Private

    private func sendCommand(_ json: String) {
        guard let ip = settings?.wizIP, !ip.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let sock = self.createSocket()
            guard sock >= 0 else { return }
            defer { close(sock) }

            self.sendUDP(sock: sock, message: json, ip: ip, port: self.wizPort)

            if let (resp, _) = self.receiveUDP(sock: sock) {
                let isOn = resp.contains("\"state\":true")
                let success = resp.contains("\"success\":true") || !resp.contains("\"error\"")
                if success {
                    DispatchQueue.main.async {
                        self.state = isOn
                        self.reachable = true
                    }
                }
            }
        }
    }

    private func createSocket() -> Int32 {
        let sock = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return -1 }

        var broadcast: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: 0, tv_usec: 500_000)  // 500ms timeout
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        return sock
    }

    private func sendUDP(sock: Int32, message: String, ip: String, port: UInt16) {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, ip, &addr.sin_addr)

        let data = [UInt8](message.utf8)
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                sendto(sock, data, data.count, 0, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    private func sendUDPBroadcast(sock: Int32, message: String, port: UInt16) {
        sendUDP(sock: sock, message: message, ip: "255.255.255.255", port: port)
    }

    private func receiveUDP(sock: Int32) -> (String, String)? {
        var buf = [UInt8](repeating: 0, count: 1024)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let n = withUnsafeMutablePointer(to: &srcAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                recvfrom(sock, &buf, buf.count, 0, ptr, &srcLen)
            }
        }

        guard n > 0 else { return nil }
        let resp = String(bytes: buf[0..<n], encoding: .utf8) ?? ""

        // Extract sender IP
        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &srcAddr.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
        let ip = String(cString: ipBuf)

        return (resp, ip)
    }

    private func extractString(from json: String, key: String) -> String? {
        guard let range = json.range(of: "\"\(key)\":\"") else { return nil }
        let start = range.upperBound
        guard let end = json[start...].firstIndex(of: "\"") else { return nil }
        return String(json[start..<end])
    }
}
