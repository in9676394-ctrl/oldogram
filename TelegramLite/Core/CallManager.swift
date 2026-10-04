//
//  CallManager.swift
//  TelegramLite
//
//  Wraps TDLib call lifecycle:
//    - updateCallIncoming / updateCallReady / updateCallEnded
//    - discardCall / acceptCall / etc.
//
//  Notes on VoIP: real audio streams use the OPUS codec over UDP. TDLib
//  exposes those via call_state protocol data — but the actual RTP socket
//  is managed by you (this app). For a *truly* functional call, we'd need
//  to wire a CallKit + AVAudioEngine pipeline. The scaffold below hooks
//  the state machine; audio plumbing is left as a TODO with a clear
//  hook point.
//

import Foundation
import CallKit
import AVFoundation

final class CallManager: NSObject {

    static let shared = CallManager()

    private let controller = CXCallController()
    private let provider = CXProvider(configuration: CallManager.providerConfig)

    private var activeCallId: Int = 0
    private var callObserverGuid: String?

    private override init() {
        super.init()
        provider.setDelegate(self, queue: nil)
        TDLibManager.shared.subscribe("updateCall") { [weak self] resp in
            self?.handleCallUpdate(resp)
        }
    }

    static var providerConfig: CXProviderConfiguration {
        let cfg = CXProviderConfiguration(localizedName: "Lite")
        cfg.maximumCallsPerCallGroup = 1
        cfg.maximumCallGroups = 1
        cfg.supportsVideo = false
        cfg.supportedHandleTypes = [.generic]
        if #available(iOS 11.0, *) { cfg.includesCallsInRecents = false }
        return cfg
    }

    // MARK: - Outgoing call

    func startCall(userId: Int64, displayName: String) {
        let uuid = UUID()
        let start = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: displayName))
        start.isVideo = false
        start.contactIdentifier = displayName
        let tx = CXTransaction(action: start)
        controller.request(tx) { _ in }
        // Tell TDLib to start the call
        TDLibManager.shared.request(function: "createCall",
                                   parameters: [
                                       "user_id": userId,
                                       "protocol": CallManager.tgCallProtocol()
                                   ]) { resp in
            if let id = resp.raw["id"] as? Int { self.activeCallId = id }
        }
    }

    func endCall() {
        let end = CXEndCallAction(call: UUID())
        let tx = CXTransaction(action: end)
        controller.request(tx) { _ in }
        if activeCallId > 0 {
            TDLibManager.shared.send(function: "discardCall",
                                     parameters: [
                                         "call_id": activeCallId,
                                         "is_disconnected": true,
                                         "duration": 0,
                                         "is_video": false,
                                         "connection_id": 0
                                     ])
            activeCallId = 0
        }
    }

    // MARK: - Incoming

    func handleCallUpdate(_ resp: TDResponse) {
        guard let call = resp.raw["call"] as? [String: Any] else { return }
        let id = call["id"] as? Int ?? 0
        let state = (call["state"] as? [String: Any])?["@type"] as? String
        switch state {
        case "callStatePending":
            // Incoming
            let isOutgoing = call["is_outgoing"] as? Bool ?? false
            if !isOutgoing {
                showIncomingCall(id: id, userId: call["user_id"] as? Int64 ?? 0)
            }
        case "callStateExchangingKeys", "callStateReady":
            // Connection established — wire audio pipeline here.
            // TODO: open AVAudioEngine with the OPUS parameters from call["protocol"].
            break
        case "callStateHangingUp":
            provider.reportCall(with: UUID(), endedAt: Date(), reason: .remoteEnded)
        case "callStateDiscarded", "callStateError":
            endCall()
        default:
            break
        }
    }

    private func showIncomingCall(id: Int, userId: Int64) {
        activeCallId = id
        let uuid = UUID()
        let upd = CXCallUpdate()
        upd.remoteHandle = CXHandle(type: .generic, value: "Telegram")
        upd.hasVideo = false
        upd.localizedCallerName = "Telegram user \(userId)"
        provider.reportNewIncomingCall(with: uuid, update: upd) { _ in }
    }

    // MARK: - Protocol params

    static func tgCallProtocol() -> [String: Any] {
        return [
            "@type": "callProtocol",
            "udp_p2p": true,
            "udp_reflector": true,
            "min_layer": 65,
            "max_layer": 92,
            "library_versions": ["4.0.0"]
        ]
    }
}

extension CallManager: CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        endCall()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // Accept call
        TDLibManager.shared.send(function: "acceptCall",
                                 parameters: ["call_id": activeCallId])
        action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        endCall()
        action.fulfill()
    }
}
