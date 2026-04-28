import Foundation

struct DiscoveredDevice: Codable, Identifiable, Hashable {
    let type: String
    let role: String
    let ip: String
    let name: String
    let port: Int
    let firmware: String?
    var id: String { ip }
}

class DiscoveryService: ObservableObject {
    @Published var masters: [DiscoveredDevice] = []

    private var timer: Timer?
    private var receiveThread: Thread?
    private var socket: Int32 = -1
    private let discoveryPort: UInt16 = 19542
    private let onFound: ((String) -> Void)?
    private var running = false

    init(onFound: ((String) -> Void)? = nil) {
        self.onFound = onFound
    }

    func start() {
        guard socket < 0 else { return }

        socket = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socket >= 0 else {
            print("DiscoveryService: failed to create socket")
            return
        }

        // Enable broadcast
        var broadcast: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        // Enable address reuse
        var reuse: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind to any address to receive responses
        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = 0  // Ephemeral port
        bindAddr.sin_addr.s_addr = INADDR_ANY
        withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        // Set receive timeout
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        running = true
        startReceiveThread()

        // Send discovery broadcast every 5 seconds
        sendBroadcast()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.sendBroadcast()
        }
        print("DiscoveryService: started")
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        if socket >= 0 {
            close(socket)
            socket = -1
        }
    }

    private func startReceiveThread() {
        let thread = Thread { [weak self] in
            while let self, self.running, self.socket >= 0 {
                var buf = [UInt8](repeating: 0, count: 512)
                var srcAddr = sockaddr_in()
                var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                let n = withUnsafeMutablePointer(to: &srcAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                        recvfrom(self.socket, &buf, buf.count, 0, ptr, &srcLen)
                    }
                }

                if n > 0 {
                    let data = Data(buf[0..<n])
                    if let device = try? JSONDecoder().decode(DiscoveredDevice.self, from: data) {
                        DispatchQueue.main.async { [weak self] in
                            self?.handleDiscoveredDevice(device)
                        }
                    }
                }
            }
        }
        thread.name = "DiscoveryService.receive"
        thread.start()
        receiveThread = thread
    }

    private func handleDiscoveredDevice(_ device: DiscoveredDevice) {
        if let idx = masters.firstIndex(where: { $0.ip == device.ip }) {
            masters[idx] = device
        } else {
            masters.append(device)
            print("DiscoveryService: found \(device.role) '\(device.name)' at \(device.ip)")
        }

        if device.role == "master" {
            onFound?(device.ip)
        }
    }

    private func sendBroadcast() {
        guard socket >= 0 else { return }

        let message = "{\"cmd\":\"discover\"}"
        let data = [UInt8](message.utf8)

        var destAddr = sockaddr_in()
        destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = discoveryPort.bigEndian
        destAddr.sin_addr.s_addr = INADDR_BROADCAST

        withUnsafePointer(to: &destAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                sendto(socket, data, data.count, 0, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
}
