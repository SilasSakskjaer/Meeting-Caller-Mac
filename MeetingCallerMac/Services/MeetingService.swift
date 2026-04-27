import SwiftUI
import Combine
import Network

struct MeetingStatus: Codable {
    let state: String
    let meetingDuration: Int?
    let requestId: Int?
    let requestResult: String?

    enum CodingKeys: String, CodingKey {
        case state
        case meetingDuration = "meeting_duration"
        case requestId = "request_id"
        case requestResult = "request_result"
    }
}

struct DeviceStatus: Codable {
    let deviceName: String
    let firmware: String
    let wifiConnected: Bool
    let ip: String
    let ssid: String
    let role: String
    let meetingState: String
    let meetingDuration: Int
    let callerCount: Int
    let callers: [CallerStatus]?
    let uptime: Int
    let freeHeap: Int

    enum CodingKeys: String, CodingKey {
        case deviceName = "device_name"
        case firmware
        case wifiConnected = "wifi_connected"
        case ip, ssid, role
        case meetingState = "meeting_state"
        case meetingDuration = "meeting_duration"
        case callerCount = "caller_count"
        case callers, uptime
        case freeHeap = "free_heap"
    }
}

struct CallerStatus: Codable, Identifiable {
    let name: String
    let active: Bool
    var id: String { name }
}

struct WizStatus: Codable {
    let ok: Bool
    let state: Bool
    let reachable: Bool
    let ip: String
}

struct APIResponse: Codable {
    let ok: Bool
    let action: String?
    let reason: String?
    let state: Bool?  // For wiz toggle
}

class MeetingService: ObservableObject {
    @Published var meetingState: String = "unknown"
    @Published var meetingDuration: Int = 0
    @Published var isReachable: Bool = false
    @Published var deviceName: String = "?"
    @Published var callers: [CallerStatus] = []
    @Published var callerCount: Int = 0
    @Published var wizState: Bool = false
    @Published var wizReachable: Bool = false
    @Published var firmware: String = ""
    @Published var uptime: Int = 0

    private var pollTimer: Timer?
    private var settings: AppSettings?
    private var mdnsBrowser: NWBrowser?
    private var discoveredIP: String?

    var iconName: String {
        switch meetingState {
        case "active", "incoming_call": return "record.circle.fill"
        case "paused": return "pause.circle.fill"
        default: return isReachable ? "video.circle" : "video.circle.badge.xmark"
        }
    }

    var isInMeeting: Bool {
        ["active", "paused", "incoming_call"].contains(meetingState)
    }

    func configure(settings: AppSettings) {
        self.settings = settings
        startPolling()
        if settings.useMDNS {
            startMDNSDiscovery()
        }
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { await self?.pollStatus() }
        }
        Task { await pollStatus() }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Meeting Control

    func startMeeting() async -> Bool {
        guard let resp: APIResponse = await post("/api/meeting/start") else { return false }
        return resp.ok
    }

    func stopMeeting() async -> Bool {
        guard let resp: APIResponse = await post("/api/meeting/stop") else { return false }
        return resp.ok
    }

    func pauseMeeting() async -> Bool {
        guard let resp: APIResponse = await post("/api/meeting/pause") else { return false }
        return resp.ok
    }

    // MARK: - Wiz Control

    func toggleWiz() async -> Bool? {
        guard let resp: APIResponse = await post("/api/wiz/toggle") else { return nil }
        if resp.ok {
            await MainActor.run { wizState = resp.state ?? !wizState }
        }
        return resp.state
    }

    func pollWizStatus() async {
        guard let status: WizStatus = await get("/api/wiz/status") else { return }
        await MainActor.run {
            wizState = status.state
            wizReachable = status.reachable
        }
    }

    // MARK: - Status Polling

    func pollStatus() async {
        guard let status: DeviceStatus = await get("/api/status") else {
            await MainActor.run { isReachable = false }
            return
        }
        await MainActor.run {
            isReachable = true
            meetingState = status.meetingState
            meetingDuration = status.meetingDuration
            deviceName = status.deviceName
            callerCount = status.callerCount
            callers = status.callers ?? []
            firmware = status.firmware
            uptime = status.uptime
        }
        await pollWizStatus()
    }

    // MARK: - mDNS Discovery

    func startMDNSDiscovery() {
        let params = NWBrowser.Descriptor.bonjour(type: "_meeting-master._tcp", domain: nil)
        mdnsBrowser = NWBrowser(for: params, using: .tcp)
        mdnsBrowser?.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                if case .service(_, _, _, _) = result.endpoint {
                    // Resolve the service to get IP
                    let connection = NWConnection(to: result.endpoint, using: .tcp)
                    connection.stateUpdateHandler = { state in
                        if case .ready = state {
                            if let path = connection.currentPath,
                               let endpoint = path.remoteEndpoint,
                               case .hostPort(let host, _) = endpoint {
                                let ip = "\(host)"
                                DispatchQueue.main.async {
                                    self?.discoveredIP = ip
                                    if self?.settings?.masterIP.isEmpty == true {
                                        self?.settings?.masterIP = ip
                                    }
                                }
                            }
                            connection.cancel()
                        }
                    }
                    connection.start(queue: .global())
                }
            }
        }
        mdnsBrowser?.start(queue: .global())
    }

    // MARK: - Network

    private var baseURL: String {
        settings?.baseURL ?? ""
    }

    private func get<T: Decodable>(_ path: String) async -> T? {
        guard !baseURL.isEmpty, let url = URL(string: baseURL + path) else { return nil }
        let request = URLRequest(url: url, timeoutInterval: 3)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    private func post<T: Decodable>(_ path: String) async -> T? {
        guard !baseURL.isEmpty,
              let url = URL(string: baseURL + path),
              let settings else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue(settings.basicAuthHeader, forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }
}
