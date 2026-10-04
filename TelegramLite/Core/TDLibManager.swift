//
//  TDLibManager.swift
//  TelegramLite
//
//  Bridges to TDLib (Telegram Database Library — official Telegram SDK).
//  TDLib runs in JSON-in/JSON-out mode: we send a JSON request, get JSON
//  responses asynchronously. This file wires that pipe into Swift.
//
//  INTEGRATION:
//  The app expects `TDLib` as a linked binary. Two integration paths are
//  supported — see README.md:
//    1. CocoaPods:  pod 'TDLibKit' (community pod, see Podfile)
//    2. Prebuilt:    drop `libtdjson.xcframework` into Vendor/ and link it.
//
//  The wrapper degrades gracefully if TDLib is not linked at runtime:
//  you'll get logged warnings and a mock data provider for UI smoke testing.
//  Set `useMockData = true` below to test UI without TDLib.
//

import Foundation
import UIKit

// MARK: - TDLib JSON bridge

/// Opaque pointer to a TDLib client instance.
private typealias TDLibClientRef = OpaquePointer

/// Function-pointer signatures matching `td_json_client_create` etc.
private typealias td_create_client      = @convention(c) () -> TDLibClientRef?
private typealias td_receive            = @convention(c) (TDLibClientRef?, Double) -> UnsafeMutablePointer<CChar>?
private typealias td_send              = @convention(c) (TDLibClientRef?, UnsafePointer<CChar>) -> Void
private typealias td_execute           = @convention(c) (TDLibClientRef?, UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
private typealias td_destroy           = @convention(c) (TDLibClientRef?) -> Void

/// Lightweight TDLib call representation. We do NOT model every field —
/// only the ones we read in this app.
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

    // MARK: - Telegram API credentials (replace with your own)
    //
    // Get these from https://my.telegram.org → API development tools
    // (free, takes 1 minute). Put real values here or override via env
    // vars so the GitHub workflow can inject them at build time.
    static let api_id: Int = {
        if let env = ProcessInfo.processInfo.environment["TG_API_ID"],
           let id = Int(env) { return id }
        return 0   // <-- put your api_id here (as Int)
    }()
    static let api_hash: String = {
        ProcessInfo.processInfo.environment["TG_API_HASH"] ?? "" // <-- put your api_hash here
    }()

    /// True if credentials are missing. Used to show a clear error to the
    /// user instead of letting the spinner spin forever.
    static var hasCredentials: Bool {
        return api_id > 0 && !api_hash.isEmpty
    }

    /// In-memory log buffer — surfaced in Settings → Debug log so the user
    /// can see what TDLib is doing without needing a Mac console.
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

    private var client: TDLibClientRef?
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
        guard let lib = loadTDLib() else {
            TDLibManager.log("ERROR: Could not load libtdjson. TDLibFramework is not linked.")
            return
        }
        self.client = lib.create()
        TDLibManager.log("TDLib client created.")
        self.receiveThread = Thread(target: self, selector: #selector(receiveLoop), object: nil)
        self.receiveThread?.name = "tg.tdlib.receive"
        self.receiveThread?.start()

        // Kick off auth param init.
        sendParameters()
        TDLibManager.log("Sent setTdlibParameters (api_id=\(TDLibManager.api_id)).")
    }

    func stop() {
        send(function: "getOption", parameters: ["name": "version"])
        send(function: "close", parameters: [:])
    }

    func pause() {
        // Tell TDLib to flush network — we are going to background.
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

    /// Fire-and-forget send — no completion handler. Use for updates /
    /// background things.
    func send(function: String, parameters: [String: Any]) {
        var payload: [String: Any] = ["@type": function]
        for (k, v) in parameters { payload[k] = v }
        send(payload: payload)
    }

    private func send(payload: [String: Any]) {
        guard !TDLibManager.useMockData, let client = client else {
            TDLibManager.log("send() skipped — client is nil (TDLib not started). Payload @type=\(payload["@type"] ?? "?")")
            return
        }
        sendQueue.async { [weak self] in
            guard let self = self,
                  let lib = self.loadTDLib(),
                  let data = try? JSONSerialization.data(withJSONObject: payload),
                  let str = String(data: data, encoding: .utf8) else { return }
            str.withCString { cstr in
                lib.send(client, cstr)
            }
        }
    }

    // MARK: - Receive loop (background thread)

    @objc private func receiveLoop() {
        guard let lib = loadTDLib(), let client = client else { return }
        while true {
            guard let cstr = lib.receive(client, 1.0) else { continue }
            let str = String(cString: cstr)
            // td_json_client_receive — caller must free? In JSON mode, the
            // returned C string is allocated by TDLib and freed by it on
            // the next receive call. We just consume the string here.
            // (Note: some bindings require `free(ptr)` — TDLib's JSON client
            // does NOT; it pools buffers internally.)
            handle(raw: str)
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
        // Do NOT call setAuthenticationPhoneNumber here — wait for user.
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

    // MARK: - Dynamic load of libtdjson

    private var cachedLib: (create: td_create_client,
                           receive: td_receive,
                           send:    td_send,
                           execute: td_execute,
                           destroy: td_destroy)?

    private func loadTDLib() -> (create: td_create_client,
                                 receive: td_receive,
                                 send:    td_send,
                                 execute: td_execute,
                                 destroy: td_destroy)? {
        if let l = cachedLib { return l }

        // Try the bundled path first (when linked into the binary).
        if let handle = dlopen(nil, RTLD_LAZY),
           let createSym = dlsym(handle, "td_json_client_create") {
            guard let sendSym    = dlsym(handle, "td_json_client_send"),
                  let recvSym   = dlsym(handle, "td_json_client_receive"),
                  let execSym   = dlsym(handle, "td_json_client_execute"),
                  let destroySym = dlsym(handle, "td_json_client_destroy") else {
                return nil
            }
            let l = (
                create:   unsafeBitCast(createSym,    to: td_create_client.self),
                receive:  unsafeBitCast(recvSym,      to: td_receive.self),
                send:     unsafeBitCast(sendSym,     to: td_send.self),
                execute:  unsafeBitCast(execSym,     to: td_execute.self),
                destroy:  unsafeBitCast(destroySym,  to: td_destroy.self)
            )
            cachedLib = l
            return l
        }

        // Try dynamic load from app bundle (e.g. via pod 'TDLibKit')
        let candidates = [
            "@executable_path/Frameworks/libtdjson.dylib",
            "@loader_path/Frameworks/libtdjson.dylib",
            "/usr/lib/libtdjson.dylib"
        ]
        for path in candidates {
            if let handle = dlopen(path, RTLD_LAZY),
               let createSym = dlsym(handle, "td_json_client_create") {
                guard let sendSym   = dlsym(handle, "td_json_client_send"),
                      let recvSym   = dlsym(handle, "td_json_client_receive"),
                      let execSym   = dlsym(handle, "td_json_client_execute"),
                      let destroySym = dlsym(handle, "td_json_client_destroy") else {
                    continue
                }
                let l = (
                    create:   unsafeBitCast(createSym,    to: td_create_client.self),
                    receive:  unsafeBitCast(recvSym,      to: td_receive.self),
                    send:     unsafeBitCast(sendSym,     to: td_send.self),
                    execute:  unsafeBitCast(execSym,     to: td_execute.self),
                    destroy:  unsafeBitCast(destroySym,  to: td_destroy.self)
                )
                cachedLib = l
                return l
            }
        }
        return nil
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
