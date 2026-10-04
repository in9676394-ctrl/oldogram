//
//  MessageInputView.swift
//  TelegramLite
//
//  Bottom input bar: text field + send button + attach (photo) + gif + emoji + voice.
//  iOS native look — uses system SF Symbols.
//

import UIKit
import AVFoundation

protocol MessageInputViewDelegate: AnyObject {
    func didSendText(_ text: String)
    func didTapPhotoPicker()
    func didTapGIFPicker()
    func didTapEmojiPicker()
    func didRecordVoice(url: URL, duration: Int)
}

final class MessageInputView: UIView, UITextViewDelegate {

    weak var delegate: MessageInputViewDelegate?

    private let textView = UITextView()
    private let sendButton = UIButton(type: .system)
    private let attachButton = UIButton(type: .system)
    private let gifButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    private let voiceButton = UIButton(type: .system)
    private let placeholderLabel = UILabel()
    private let topLine = UIView()
    private let bottomBar = UIStackView()

    // Voice recording
    private var audioRecorder: AVAudioRecorder?
    private var recordStart: Date?
    private var recordTimer: Timer?
    private var isRecording = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = Theme.navbar
        topLine.backgroundColor = Theme.separator
        addSubview(topLine)
        topLine.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topLine.topAnchor.constraint(equalTo: topAnchor),
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        textView.font = Theme.regularFont(16)
        textView.textColor = Theme.text
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        addSubview(textView)

        placeholderLabel.text = "Message"
        placeholderLabel.textColor = Theme.textSecondary
        placeholderLabel.font = Theme.regularFont(16)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        sendButton.setImage(UIImage(systemName: "paperplane.fill")?
            .withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        sendButton.backgroundColor = Theme.accent
        sendButton.layer.cornerRadius = 18
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        addSubview(sendButton)

        attachButton.setImage(UIImage(systemName: "paperclip")?
            .withTintColor(Theme.textSecondary, renderingMode: .alwaysOriginal), for: .normal)
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        attachButton.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        addSubview(attachButton)

        gifButton.setImage(UIImage(systemName: "square.stack")?
            .withTintColor(Theme.textSecondary, renderingMode: .alwaysOriginal), for: .normal)
        gifButton.translatesAutoresizingMaskIntoConstraints = false
        gifButton.addTarget(self, action: #selector(gifTapped), for: .touchUpInside)
        addSubview(gifButton)

        emojiButton.setImage(UIImage(systemName: "face.smiling")?
            .withTintColor(Theme.textSecondary, renderingMode: .alwaysOriginal), for: .normal)
        emojiButton.translatesAutoresizingMaskIntoConstraints = false
        emojiButton.addTarget(self, action: #selector(emojiTapped), for: .touchUpInside)
        addSubview(emojiButton)

        voiceButton.setImage(UIImage(systemName: "mic.fill")?
            .withTintColor(Theme.textSecondary, renderingMode: .alwaysOriginal), for: .normal)
        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        voiceButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleVoiceLongPress(_:))))
        addSubview(voiceButton)

        NSLayoutConstraint.activate([
            attachButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            attachButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            attachButton.widthAnchor.constraint(equalToConstant: 28),
            attachButton.heightAnchor.constraint(equalToConstant: 28),

            emojiButton.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 10),
            emojiButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            emojiButton.widthAnchor.constraint(equalToConstant: 28),
            emojiButton.heightAnchor.constraint(equalToConstant: 28),

            gifButton.leadingAnchor.constraint(equalTo: emojiButton.trailingAnchor, constant: 10),
            gifButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            gifButton.widthAnchor.constraint(equalToConstant: 28),
            gifButton.heightAnchor.constraint(equalToConstant: 28),

            textView.leadingAnchor.constraint(equalTo: gifButton.trailingAnchor, constant: 10),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),

            voiceButton.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 10),
            voiceButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            voiceButton.widthAnchor.constraint(equalToConstant: 28),
            voiceButton.heightAnchor.constraint(equalToConstant: 28),

            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 4),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 6),
        ])

        updateSendButtonState()
    }

    // MARK: - Send

    @objc private func sendTapped() {
        let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }
        delegate?.didSendText(text)
    }

    func clear() {
        textView.text = ""
        placeholderLabel.isHidden = false
        updateSendButtonState()
    }

    @objc private func attachTapped() { delegate?.didTapPhotoPicker() }
    @objc private func gifTapped()    { delegate?.didTapGIFPicker() }
    @objc private func emojiTapped()  { delegate?.didTapEmojiPicker() }

    // MARK: - Voice

    @objc private func handleVoiceLongPress(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            startRecording()
        case .ended, .cancelled:
            stopRecording()
        default: break
        }
    }

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch { return }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(Date().timeIntervalSince1970).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            recordStart = Date()
            isRecording = true
            voiceButton.backgroundColor = Theme.destructive.withAlphaComponent(0.2)
            voiceButton.layer.cornerRadius = 14
            recordTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                // (Could update a label here showing elapsed time.)
            }
        } catch {
            isRecording = false
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        audioRecorder?.stop()
        let url = audioRecorder?.url
        let duration = Int(Date().timeIntervalSince(recordStart ?? Date()))
        audioRecorder = nil
        isRecording = false
        voiceButton.backgroundColor = .clear
        recordTimer?.invalidate()
        recordTimer = nil
        if let u = url {
            delegate?.didRecordVoice(url: u, duration: duration)
        }
    }

    // MARK: - Text view delegate

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateSendButtonState()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            sendTapped()
            return false
        }
        return true
    }

    private func updateSendButtonState() {
        let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let active = !text.isEmpty
        sendButton.alpha = active ? 1.0 : 0.4
        sendButton.isEnabled = active
    }
}
