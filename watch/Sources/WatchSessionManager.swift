import Foundation
import WatchConnectivity

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    override init() { super.init(); if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() } }
    func send(status: String) { guard WCSession.default.activationState == .activated else { return }; WCSession.default.transferUserInfo(["status": status, "recordedAt": ISO8601DateFormatter().string(from: Date())]) }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
