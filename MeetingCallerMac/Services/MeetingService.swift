import SwiftUI
import Combine

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

struct APIResponse: Codable {
    let ok: Bool
    let action: String?
    let reason: String?
}

class MeetingService: ObservableObject {
    @Published var meetingState: String = "unknown"
    @Published var meetingDuration: Int = 0
    @Published var isReachable: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var deviceName: String = "?"
    @Published var callers: [CallerStatus] = []
    @Published var callerCount: Int = 0
    @Published var firmware: String = ""
    @Published var uptime: Int = 0

    private var pollTimer: Timer?
    private(set) var settings: AppSettings?
    private(set) var discoveryService: DiscoveryService?

    var iconName: String {
        switch meetingState {
        case "active", "incoming_call": return "record.circle.fill"
        case "paused": return "pause.circle.fill"
        default: return isReachable ? "video.circle" : "video.slash.circle"
        }
    }

    var isInMeeting: Bool {
        ["active", "paused", "incoming_call"].contains(meetingState)
    }

    func configure(settings: AppSettings) {
        self.settings = settings
        startPolling()
        if settings.useMDNS {
            startDiscovery()
        }
    }

    // Fire-and-forget: runs detached so menu dismissal doesn't cancel it
    func fireAndForget(_ action: @escaping () async -> Any?) {
        Task.detached { _ = await action() }
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

    // MARK: - Status Polling

    func pollStatus() async {
        guard let status: DeviceStatus = await get("/api/status") else {
            await MainActor.run {
                isReachable = false
                isAuthenticated = false
            }
            return
        }
        let authOk = await checkAuth()
        await MainActor.run {
            isReachable = true
            isAuthenticated = authOk
            meetingState = status.meetingState
            meetingDuration = status.meetingDuration
            deviceName = status.deviceName
            callerCount = status.callerCount
            callers = status.callers ?? []
            firmware = status.firmware
            uptime = status.uptime
        }
    }

    private func checkAuth() async -> Bool {
        guard !baseURL.isEmpty,
              let url = URL(string: baseURL + "/api/auth/check"),
              let settings else { return false }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue(settings.basicAuthHeader, forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            struct AuthCheck: Decodable { let authenticated: Bool }
            let result = try JSONDecoder().decode(AuthCheck.self, from: data)
            return result.authenticated
        } catch {
            return false
        }
    }

    // MARK: - Discovery

    func startDiscovery() {
        discoveryService?.stop()
        discoveryService = DiscoveryService { [weak self] ip in
            DispatchQueue.main.async {
                print("Discovery: found master at \(ip)")
                if self?.settings?.masterIP.isEmpty == true || self?.settings?.useMDNS == true {
                    self?.settings?.masterIP = ip
                }
            }
        }
        discoveryService?.start()
    }

    func stopDiscovery() {
        discoveryService?.stop()
        discoveryService = nil
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
              let settings else {
            print("POST \(path): missing baseURL or settings")
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue(settings.basicAuthHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        print("POST \(path) → \(url) auth=\(settings.basicAuthHeader.prefix(20))...")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            print("POST \(path) → \(code): \(body)")
            guard code == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("POST \(path) error: \(error.localizedDescription)")
            return nil
        }
    }
}
