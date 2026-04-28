import SwiftUI
import Combine

class AppSettings: ObservableObject {
    @AppStorage("masterIP") var masterIP: String = ""
    @AppStorage("password") var password: String = "admin"
    @AppStorage("autoStartEnabled") var autoStartEnabled: Bool = true
    @AppStorage("cameraOffAction") var cameraOffAction: Int = 0  // 0=popup, 1=stop, 2=pause
    @AppStorage("stopDelaySeconds") var stopDelaySeconds: Int = 120  // 2 minutes
    @AppStorage("wizIP") var wizIP: String = ""
    @AppStorage("wizOnAction") var wizOnAction: Int = 0  // 0=spørg, 1=auto tænd, 2=manual
    @AppStorage("wizOffWithMeeting") var wizOffWithMeeting: Bool = true  // Sluk lys når møde stopper
    @AppStorage("useMDNS") var useMDNS: Bool = true

    var baseURL: String {
        guard !masterIP.isEmpty else { return "" }
        return "http://\(masterIP)"
    }

    var basicAuthHeader: String {
        let credentials = ":\(password)"
        let data = credentials.data(using: .utf8)!
        return "Basic \(data.base64EncodedString())"
    }
}
