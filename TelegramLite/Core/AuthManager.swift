//
//  AuthManager.swift
//  TelegramLite
//
//  Wraps TDLib auth flow:
//    1. setAuthenticationPhoneNumber
//    2. checkAuthenticationCode         (when state == .waitCode)
//    3. checkAuthenticationPassword     (when state == .waitPassword, for 2FA)
//    4. registerUser                    (if is_registered == false)
//

import Foundation

final class AuthManager {

    static let shared = AuthManager()

    private(set) var isLoggedIn: Bool {
        get {
            UserDefaults.standard.bool(forKey: "tg.isLoggedIn")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "tg.isLoggedIn")
        }
    }

    private init() {}

    // MARK: - Send phone number

    func sendPhoneNumber(_ phone: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let formatted = formatPhone(phone)
        TDLibManager.shared.request(function: "setAuthenticationPhoneNumber",
                                    parameters: [
                                        "phone_number": formatted,
                                        "settings": [
                                            "@type": "phoneNumberAuthenticationSettings",
                                            "allow_flash_call": false,
                                            "is_current_phone_number": true,
                                            "allow_sms_retriever_api": false
                                        ]
                                    ]) { resp in
            if let err = resp.raw["error"] as? [String: Any] {
                let msg = err["message"] as? String ?? "Unknown error"
                completion(.failure(NSError(domain: "tg", code: err["code"] as? Int ?? -1, userInfo: [NSLocalizedDescriptionKey: msg])))
            } else {
                completion(.success(()))
            }
        }
    }

    // MARK: - Send code

    func sendCode(_ code: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        // Result.success(Bool) → bool = isRegistered
        TDLibManager.shared.request(function: "checkAuthenticationCode",
                                    parameters: ["code": code]) { resp in
            if let err = resp.raw["error"] as? [String: Any] {
                let msg = err["message"] as? String ?? "Unknown error"
                completion(.failure(NSError(domain: "tg", code: err["code"] as? Int ?? -1, userInfo: [NSLocalizedDescriptionKey: msg])))
                return
            }
            // Look at last seen auth state — TDLib emits the next state via update.
            switch TDLibManager.shared.authState {
            case .waitRegistration:
                completion(.success(false))
            case .authorizationReady:
                self.isLoggedIn = true
                completion(.success(true))
            default:
                completion(.success(true))
            }
        }
    }

    // MARK: - Send password (2FA)

    func sendPassword(_ password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        TDLibManager.shared.request(function: "checkAuthenticationPassword",
                                    parameters: ["password": password]) { resp in
            if let err = resp.raw["error"] as? [String: Any] {
                let msg = err["message"] as? String ?? "Wrong password"
                completion(.failure(NSError(domain: "tg", code: err["code"] as? Int ?? -1, userInfo: [NSLocalizedDescriptionKey: msg])))
            } else {
                self.isLoggedIn = true
                completion(.success(()))
            }
        }
    }

    // MARK: - Register new user (after waitRegistration)

    func register(firstName: String, lastName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        TDLibManager.shared.request(function: "registerUser",
                                    parameters: [
                                        "first_name": firstName,
                                        "last_name":  lastName
                                    ]) { resp in
            if let err = resp.raw["error"] as? [String: Any] {
                let msg = err["message"] as? String ?? "Registration failed"
                completion(.failure(NSError(domain: "tg", code: err["code"] as? Int ?? -1, userInfo: [NSLocalizedDescriptionKey: msg])))
            } else {
                self.isLoggedIn = true
                completion(.success(()))
            }
        }
    }

    // MARK: - Logout

    func logout(completion: @escaping () -> Void) {
        TDLibManager.shared.send(function: "logOut", parameters: [:])
        isLoggedIn = false
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .tgAuthClosed, object: nil)
            completion()
        }
    }

    // MARK: - Phone formatter

    /// TDLib expects E.164 format: +1234567890
    private func formatPhone(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "[^\\d+]", with: "", options: .regularExpression)
        if !s.hasPrefix("+") { s = "+" + s }
        return s
    }
}
