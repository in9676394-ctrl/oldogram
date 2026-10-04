//
//  AuthViewController.swift
//  TelegramLite
//
//  Phone → Code → (Password) → Main.
//  Single screen that morphs between states based on TDLib.authState.
//

import UIKit

final class AuthViewController: UIViewController, UITextFieldDelegate {

    // Stage machine
    private enum Stage {
        case phone
        case code(isRegistered: Bool, hint: String?)
        case password(hint: String?)
        case registration
    }

    private var stage: Stage = .phone

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textField = UITextField()
    private let primaryButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .white)
    private var currentPhoneNumber: String = ""

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg
        setupSubviews()
        applyStage()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    // MARK: - Subviews

    private func setupSubviews() {
        let logo = UILabel()
        logo.text = "Lite"
        logo.font = Theme.boldFont(40)
        logo.textColor = Theme.accent
        logo.textAlignment = .center
        view.addSubview(logo)

        titleLabel.font = Theme.semiboldFont(22)
        titleLabel.textColor = Theme.text
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)

        subtitleLabel.font = Theme.regularFont(14)
        subtitleLabel.textColor = Theme.textSecondary
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        view.addSubview(subtitleLabel)

        textField.font = Theme.regularFont(17)
        textField.textColor = Theme.text
        textField.backgroundColor = Theme.bgElevated
        textField.layer.cornerRadius = 12
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        textField.leftViewMode = .always
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .go
        textField.delegate = self
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        view.addSubview(textField)

        primaryButton.setTitle("Continue", for: .normal)
        primaryButton.titleLabel?.font = Theme.semiboldFont(17)
        primaryButton.setTitleColor(.white, for: .normal)
        primaryButton.backgroundColor = Theme.accent
        primaryButton.layer.cornerRadius = 12
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        primaryButton.isEnabled = false
        primaryButton.alpha = 0.5
        view.addSubview(primaryButton)

        errorLabel.font = Theme.regularFont(13)
        errorLabel.textColor = Theme.destructive
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        view.addSubview(errorLabel)

        activityIndicator.color = .white
        view.addSubview(activityIndicator)

        // Layout via native Auto Layout — no third-party dep.
        [logo, titleLabel, subtitleLabel, textField, primaryButton, errorLabel, activityIndicator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            logo.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            logo.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            textField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            textField.heightAnchor.constraint(equalToConstant: 48),

            primaryButton.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 16),
            primaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            primaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            primaryButton.heightAnchor.constraint(equalToConstant: 48),

            errorLabel.topAnchor.constraint(equalTo: primaryButton.bottomAnchor, constant: 12),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            activityIndicator.centerXAnchor.constraint(equalTo: primaryButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
        ])
    }

    // MARK: - Stages

    private func applyStage() {
        switch stage {
        case .phone:
            titleLabel.text = "Phone Number"
            subtitleLabel.text = "Enter your number with country code, e.g. +1 555 1234567."
            textField.placeholder = "+1 555 1234567"
            textField.keyboardType = .phonePad
            textField.text = ""
            textField.isSecureTextEntry = false
            textField.becomeFirstResponder()
            primaryButton.setTitle("Continue", for: .normal)
        case .code(let isRegistered, let hint):
            titleLabel.text = "Confirmation Code"
            subtitleLabel.text = hint ?? "We sent a code to your device. Enter it below."
            textField.placeholder = "Code"
            textField.keyboardType = .numberPad
            textField.text = ""
            textField.isSecureTextEntry = false
            primaryButton.setTitle("Continue", for: .normal)
            if !isRegistered {
                subtitleLabel.text = (subtitleLabel.text ?? "") + "\nFirst time logging in here — you'll set a name next."
            }
        case .password(let hint):
            titleLabel.text = "Two-Step Verification"
            subtitleLabel.text = hint ?? "Enter your password."
            textField.placeholder = "Password"
            textField.keyboardType = .asciiCapable
            textField.isSecureTextEntry = true
            textField.text = ""
            primaryButton.setTitle("Continue", for: .normal)
        case .registration:
            titleLabel.text = "Your Name"
            subtitleLabel.text = "Enter your first and last name."
            textField.placeholder = "First Last"
            textField.keyboardType = .default
            textField.isSecureTextEntry = false
            textField.text = ""
            primaryButton.setTitle("Sign Up", for: .normal)
        }
        textChanged()
    }

    // MARK: - Actions

    @objc private func textChanged() {
        let text = textField.text ?? ""
        let ok: Bool
        switch stage {
        case .phone:        ok = text.count >= 7
        case .code:         ok = text.count >= 5
        case .password:     ok = text.count >= 1
        case .registration: ok = text.contains(" ") && text.count >= 3
        }
        primaryButton.isEnabled = ok
        primaryButton.alpha = ok ? 1.0 : 0.5
        errorLabel.text = nil
    }

    @objc private func primaryTapped() {
        setLoading(true)
        switch stage {
        case .phone:
            currentPhoneNumber = textField.text ?? ""
            AuthManager.shared.sendPhoneNumber(currentPhoneNumber) { result in
                self.setLoading(false)
                switch result {
                case .success:
                    self.waitForAuthStateChange { state in
                        switch state {
                        case .waitCode(let isReg, let codeType, let terms):
                            _ = codeType
                            self.stage = .code(isRegistered: isReg, hint: terms)
                        case .waitPassword(let hint, _):
                            self.stage = .password(hint: hint)
                        default:
                            self.errorLabel.text = "Unexpected state. Try again."
                        }
                        self.applyStage()
                    }
                case .failure(let err):
                    self.errorLabel.text = err.localizedDescription
                }
            }
        case .code:
            AuthManager.shared.sendCode(textField.text ?? "") { result in
                self.setLoading(false)
                switch result {
                case .success(let isReg):
                    if !isReg {
                        self.stage = .registration
                        self.applyStage()
                    } else {
                        self.waitForAuthStateChange { _ in
                            self.proceedIfReady()
                        }
                    }
                case .failure(let err):
                    self.errorLabel.text = err.localizedDescription
                }
            }
        case .password:
            AuthManager.shared.sendPassword(textField.text ?? "") { result in
                self.setLoading(false)
                switch result {
                case .success:
                    self.proceedIfReady()
                case .failure(let err):
                    self.errorLabel.text = err.localizedDescription
                }
            }
        case .registration:
            let parts = (textField.text ?? "").split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let first = String(parts.first ?? "")
            let last  = String(parts.count > 1 ? parts[1] : "")
            AuthManager.shared.register(firstName: first, lastName: last) { result in
                self.setLoading(false)
                switch result {
                case .success: self.proceedIfReady()
                case .failure(let err): self.errorLabel.text = err.localizedDescription
                }
            }
        }
    }

    private func waitForAuthStateChange(_ completion: @escaping (TDLibManager.TGAuthState) -> Void) {
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.5)
            let s = TDLibManager.shared.authState
            DispatchQueue.main.async { completion(s) }
        }
    }

    private func proceedIfReady() {
        guard case .authorizationReady = TDLibManager.shared.authState else {
            self.errorLabel.text = "Authentication is taking longer than expected. Try again in a moment."
            return
        }
        if let app = UIApplication.shared.delegate as? AppDelegate {
            UIView.transition(with: app.window!, duration: 0.25,
                              options: .transitionCrossDissolve) {
                app.showRootController()
            }
        }
    }

    private func setLoading(_ loading: Bool) {
        if loading {
            activityIndicator.startAnimating()
            primaryButton.setTitle("", for: .normal)
            primaryButton.isEnabled = false
        } else {
            activityIndicator.stopAnimating()
            primaryButton.setTitle("Continue", for: .normal)
            primaryButton.isEnabled = true
        }
    }

    // MARK: - TextField

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        primaryTapped()
        return true
    }
}
