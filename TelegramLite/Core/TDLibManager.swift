//
//  TDLibManager.swift
//  TelegramLite
//
//  Bridges to TDLib (Telegram Database Library — official Telegram SDK).
//  Uses Swiftgram/TDLibFramework SPM package which exposes the C API
//  via `import TDLibFramework`.
//
//  We call td_json_client_* C functions directly — no dlopen+dlsym
//  hackery. The linker pulls symbols from the linked binaryTarget.
//

import Foundation
import UIKit
import TDLibFramework

// MARK: - TDLib JSON bridge response

struct TDResponse {
    let raw: [String: Any]

    var type: String? { raw["@type"] as? String }
    var extra: String? { raw["@extra"] as? String }

    subscript(key: String) -> Any? { raw[key] }
}

final class TDLibManager {

    static let shared = TDLibManager()

    // Set this to true to bypass TDLib and feed UI with mock data —
    // useful when running on simulator without a linked TDLib binary.
    static var useMockData: Bool {
        return ProcessInfo.processInfo.environment["USE_MOCK_TD"] == "1"
    }

    // MARK: - Telegram API credentials
    //
    // Get these from https://my.telegram.org → API development tools
    // (free, takes 1 minute). At build time, the GitHub Actions
    // workflow reads TG_API_ID / TG_API_HASH from GitHub Secrets and
    // rewrites the lines below to hardcode the real values.
    // (ProcessInfo.environment doesn't exist on iOS devices.)
    static let api_id: Int = {
        if let env = ProcessInfo.processInfo.environment["TG_API_ID"],
           let id = Int(env) { return id }
        return 0   // <-- put your api_id here (as Int)
    }()
    static let api_hash: String = {
        ProcessInfo.processInfo.environment["TG_API_HASH"] ?? "" // <-- put your api_hash here
    }()

    /// True if credentials are present. Used to show a clear error to
    /// the user instead of letting the spinner spin forever.
    static var hasCredentials: Bool {
        return api_id > 0 && !api_hash.isEmpty
    }

    /// In-memory log buffer — surfaced in Settings → Debug log so the
    /// user can see what TDLib is doing without needing a Mac console.
    private(set) static var logLines: [String] = []
    private static let logLock = NSLock()
    static func log(_ msg: String) {
        let stamp = DateFormatter.localizedString(from: Date(),
                                                   dateStyle: .none,
                                                   timeStyle: .medium)
        let line = "[\(stamp)] \(msg)"
        logLock.lock()
        logLines.append(line)
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
        logLock.unlock()
        print(line)
    }

    // MARK: - State

    /// Raw TDLib client pointer. `void *` in C → `UnsafeMutableRawPointer` in Swift.
    private var client: UnsafeMutableRawPointer?
    private var receiveThread: Thread?

    private let sendQueue = DispatchQueue(label: "tg.tdlib.send")
    private let lock = NSLock()

    // Listeners: extra-id → handler
    private var extraHandlers: [String: (TDResponse) -> Void] = [:]
    // Update-type → list of handlers
    private var updateHandlers: [String: [(TDResponse) -> Void]] = [:]

    private(set) var authState: TGAuthState = .waitPhoneNumber

    enum TGAuthState {
        case waitPhoneNumber
        case waitCode(isRegistered: Bool, codeType: String?, terms: String?)
        case waitPassword(hint: String?, hasRecovery: Bool)
        case waitRegistration
        case waitOtherDeviceConfirmation(link: String?)
        case authorizationReady
        case loggingOut
        case closing
        case closed
    }

    // MARK: - Lifecycle

    func start() {
        guard !TDLibManager.useMockData else {
            TDLibManager.log("Mock mode — skipping real init")
            return
        }
        guard TDLibManager.hasCredentials else {
            TDLibManager.log("ERROR: api_id/api_hash not set. Get them at https://my.telegram.org → API development tools. Add as GitHub Secrets TG_API_ID and TG_API_HASH, then re-trigger the workflow.")
            return
        }
        // Direct C call — no dlopen. Symbol is in the binary because we
        // link the TDLibFramework binaryTarget.
        let rawPtr = td_json_client_create()
        guard let ptr = rawPtr else {
            TDLibManager.log("ERROR: td_json_client_create() returned NULL.")
            return
        }
        client = ptr
        TDLibManager.log("TDLib client created (raw pointer: \(ptr)).")
        receiveThread = Thread(target: self, selector: #selector(receiveLoop), object: nil)
        receiveThread?.name = "tg.tdlib.receive"
        receiveThread?.start()

        // Kick off auth param init.
        sendParameters()
        TDLibManager.log("Sent setTdlibParameters (api_id=\(TDLibManager.api_id)).")
    }

    func stop() {
        send(function: "getOption", parameters: ["name": "version"])
        send(function: "close", parameters: [:])
    }

    func pause() {
        send(function: "setNetworkType", parameters: [
            "network_type": ["@type": "network_type_none"]
        ])
    }

    func resume() {
        send(function: "setNetworkType", parameters: [
            "network_type": ["@type": "network_type_wifi"]
        ])
    }

    // MARK: - Send

    /// Generic send: builds a JSON request with an `@extra` id, registers
    /// a one-shot handler, and submits to TDLib.
    func request(extraPrefix: String = "req",
                function: String,
                parameters: [String: Any],
                completion: @escaping (TDResponse) -> Void) {

        let extra = "\(extraPrefix)-\(UUID().uuidString.prefix(8))"
        lock.lock()
        extraHandlers[extra] = completion
        lock.unlock()

        var payload: [String: Any] = ["@type": function, "@extra": extra]
        for (k, v) in parameters { payload[k] = v }

        send(payload: payload)
    }

    /// Fire-and-forget send — no completion handler.
    func send(function: String, parameters: [String: Any]) {
        var payload: [String: Any] = ["@type": function]
        for (k, v) in parameters { payload[k] = v }
        send(payload: payload)
    }

    private func send(payload: [String: Any]) {
        guard let client = client else {
            TDLibManager.log("send() skipped — client is nil (TDLib not started). Payload @type=\(payload["@type"] ?? "?")")
            return
        }
        sendQueue.async { [weak self] in
            guard let self = self,
                  let data = try? JSONSerialization.data(withJSONObject: payload),
                  let str = String(data: data, encoding: .utf8) else { return }
            str.withCString { cstr in
                // void td_json_client_send(void *client, const char *request)
                td_json_client_send(client, cstr)
            }
        }
    }

    // MARK: - Receive loop (background thread)

    @objc private func receiveLoop() {
        guard let client = client else { return }
        while true {
            // const char *td_json_client_receive(void *client, double timeout)
            // Returns NULL on timeout — keep looping.
            if let rawPtr = td_json_client_receive(client, 1.0) {
                let str = String(cString: rawPtr)
                handle(raw: str)
            }
        }
    }

    // MARK: - Dispatch

    private func handle(raw: String) {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            TDLibManager.log("Could not parse TDLib response as JSON: \(raw.prefix(200))")
            return
        }
        let resp = TDResponse(raw: obj)

        // Log errors from TDLib
        if let err = resp.raw["error"] as? [String: Any] {
            let code = err["code"] ?? "?"
            let msg = err["message"] ?? "?"
            TDLibManager.log("TDLib error \(code): \(msg)")
        }

        // Auth state updates are critical — handle them here centrally.
        if resp.type == "updateAuthorizationState",
           let state = resp["authorization_state"] as? [String: Any],
           let stateType = state["@type"] as? String {
            TDLibManager.log("Auth state → \(stateType)")
            handleAuthState(stateType, state)
            emit("updateAuthorizationState", resp)
            return
        }
        if let extra = resp.extra {
            lock.lock()
            let handler = extraHandlers.removeValue(forKey: extra)
            lock.unlock()
            handler?(resp)
            return
        }
        if let type = resp.type, type.hasPrefix("update") {
            emit(type, resp)
        }
    }

    private func handleAuthState(_ stateType: String, _ state: [String: Any]) {
        switch stateType {
        case "authorizationStateWaitPhoneNumber":
            authState = .waitPhoneNumber
        case "authorizationStateWaitCode":
            authState = .waitCode(
                isRegistered: state["is_registered"] as? Bool ?? false,
                codeType: (state["code_type"] as? [String: Any])?["@type"] as? String,
                terms: (state["terms_of_service"] as? [String: Any])?["text"] as? String
            )
        case "authorizationStateWaitOtherDeviceConfirmation":
            authState = .waitOtherDeviceConfirmation(link: state["link"] as? String)
        case "authorizationStateWaitRegistration":
            authState = .waitRegistration
        case "authorizationStateWaitPassword":
            authState = .waitPassword(
                hint: state["password_hint"] as? String,
                hasRecovery: state["has_recovery_email_address"] as? Bool ?? false
            )
        case "authorizationStateReady":
            authState = .authorizationReady
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .tgAuthReady, object: nil)
            }
        case "authorizationStateLoggingOut":
            authState = .loggingOut
        case "authorizationStateClosing":
            authState = .closing
        case "authorizationStateClosed":
            authState = .closed
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .tgAuthClosed, object: nil)
            }
        default:
            break
        }
    }

    // MARK: - Pub/Sub for updates

    func subscribe(_ updateType: String, _ handler: @escaping (TDResponse) -> Void) {
        lock.lock()
        var list = updateHandlers[updateType] ?? []
        list.append(handler)
        updateHandlers[updateType] = list
        lock.unlock()
    }

    private func emit(_ type: String, _ resp: TDResponse) {
        lock.lock()
        let list = updateHandlers[type] ?? []
        lock.unlock()
        for h in list { h(resp) }
    }

    // MARK: - Init parameters

    private func sendParameters() {
        let params: [String: Any] = [
            "database_directory": documentsPath("tdlib"),
            "use_message_database": true,
            "use_chat_info_database": true,
            "use_file_database": true,
            "use_secret_chats": true,
            "api_id": TDLibManager.api_id,
            "api_hash": TDLibManager.api_hash,
            "system_language_code": Locale.current.languageCode ?? "en",
            "device_model": UIDevice.current.model,
            "application_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "system_version": UIDevice.current.systemVersion,
            "use_test_dc": false,
            "files_directory": documentsPath("tdlib-files")
        ]
        send(function: "setTdlibParameters", parameters: params)
    }

    // MARK: - Device token

    func registerDeviceToken(_ token: String) {
        send(function: "registerDevice", parameters: [
            "device_token": [
                "@type": "deviceTokenApplePushVOIP",
                "token": token,
                "is_app_sandbox": false
            ],
            "other_user_ids": []
        ])
    }

    private func documentsPath(_ sub: String) -> String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(sub)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let tgAuthReady  = Notification.Name("tg.authReady")
    static let tgAuthClosed = Notification.Name("tg.authClosed")
    static let tgChatsUpdated = Notification.Name("tg.chatsUpdated")
    static let tgMessagesUpdated = Notification.Name("tg.messagesUpdated")
    static let tgIncomingCall = Notification.Name("tg.incomingCall")
}
