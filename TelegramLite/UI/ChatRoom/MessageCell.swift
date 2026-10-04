//
//  MessageCell.swift
//  TelegramLite
//
//  Renders a single message bubble. Supports:
//    - text
//    - photo (lazy loaded)
//    - gif (FLAnimatedImage-backed for animated)
//    - sticker (rendered big)
//    - voice note (UI only — playback wired via AVAudioPlayer)
//    - system message (centered gray)
//    - unsupported (placeholder)
//

import UIKit
import AVFoundation

final class MessageCell: UITableViewCell {

    static let reuseId = "MessageCell"

    private let bubble = UIView()
    private let titleLabel = UILabel()
    private let timeLabel = UILabel()
    private let mediaView = UIImageView()
    private let captionLabel = UILabel()
    private let voiceButton = UIButton(type: .system)
    private let systemLabel = UILabel()

    // Outgoing/incoming layout
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    private var currentPlayer: AVAudioPlayer?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: MessageCell.reuseId)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear

        contentView.addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.layer.cornerRadius = Theme.bubbleRadius

        titleLabel.font = Theme.regularFont(15)
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping

        timeLabel.font = Theme.regularFont(11)
        timeLabel.textColor = Theme.textSecondary.withAlphaComponent(0.85)

        mediaView.contentMode = .scaleAspectFill
        mediaView.layer.cornerRadius = 8
        mediaView.clipsToBounds = true
        mediaView.backgroundColor = Theme.bgElevated

        captionLabel.font = Theme.regularFont(14)
        captionLabel.numberOfLines = 0

        voiceButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        voiceButton.tintColor = Theme.accent
        voiceButton.setTitle(" Voice message", for: .normal)
        voiceButton.titleLabel?.font = Theme.regularFont(14)

        systemLabel.font = Theme.regularFont(13)
        systemLabel.textColor = Theme.textSecondary
        systemLabel.textAlignment = .center
        systemLabel.numberOfLines = 0
        contentView.addSubview(systemLabel)
        systemLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            systemLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            systemLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            systemLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            systemLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
        ])

        bubble.addSubview(titleLabel)
        bubble.addSubview(timeLabel)
        bubble.addSubview(mediaView)
        bubble.addSubview(captionLabel)
        bubble.addSubview(voiceButton)

        [titleLabel, timeLabel, mediaView, captionLabel, voiceButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        // Default constraints (outgoing, trailing)
        leadingConstraint = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        trailingConstraint = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            leadingConstraint,
            trailingConstraint,

            mediaView.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 6),
            mediaView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 6),
            mediaView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -6),
            mediaView.heightAnchor.constraint(lessThanOrEqualToConstant: 200),

            captionLabel.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 4),
            captionLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
            captionLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -50),
            captionLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -20),

            titleLabel.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -50),
            titleLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -14),

            timeLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -4),
            timeLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),

            voiceButton.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            voiceButton.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
            voiceButton.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
            voiceButton.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
        ])
        // Hide everything by default
        titleLabel.isHidden = true
        mediaView.isHidden = true
        captionLabel.isHidden = true
        voiceButton.isHidden = true
        systemLabel.isHidden = true
        bubble.isHidden = true
    }

    func configure(with msg: TGMessage) {
        // Reset visibility
        titleLabel.isHidden = true
        mediaView.isHidden = true
        captionLabel.isHidden = true
        voiceButton.isHidden = true
        systemLabel.isHidden = true
        bubble.isHidden = false

        // Outgoing vs incoming layout
        if msg.isOutgoing {
            leadingConstraint.isActive = false
            trailingConstraint.isActive = true
            bubble.backgroundColor = Theme.bubbleOut
            titleLabel.textColor = Theme.bubbleOutText
            captionLabel.textColor = Theme.bubbleOutText
            timeLabel.textColor = .white.withAlphaComponent(0.85)
        } else {
            trailingConstraint.isActive = false
            leadingConstraint.isActive = true
            bubble.backgroundColor = Theme.bubbleIn
            titleLabel.textColor = Theme.bubbleInText
            captionLabel.textColor = Theme.bubbleInText
            timeLabel.textColor = Theme.textSecondary
        }

        let timeStr: String = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: msg.date)
        }()
        timeLabel.text = timeStr

        switch msg.content {
        case .text(let s):
            titleLabel.text = s
            titleLabel.font = Theme.regularFont(15)  // Reset — cell may have shown sticker previously
            titleLabel.textAlignment = .left
            titleLabel.isHidden = false
            mediaView.isHidden = true
            voiceButton.isHidden = true
            captionLabel.isHidden = true
        case .photo(let caption, let fileId):
            mediaView.isHidden = false
            captionLabel.text = caption
            captionLabel.isHidden = caption.isEmpty
            // Request download
            requestFile(fileId: fileId) { path in
                DispatchQueue.main.async {
                    if let p = path, let img = UIImage(contentsOfFile: p) {
                        self.mediaView.image = img
                    } else {
                        self.mediaView.image = UIImage(systemName: "photo")
                    }
                }
            }
        case .gif(let caption, let fileId):
            mediaView.isHidden = false
            captionLabel.text = caption
            captionLabel.isHidden = caption.isEmpty
            requestFile(fileId: fileId) { path in
                DispatchQueue.main.async {
                    if let p = path, let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
                       let img = UIImage(data: data) { // TODO: gif playback via FLAnimatedImage
                        self.mediaView.image = img
                    }
                }
            }
        case .sticker(let emoji, let fileId):
            // Big sticker — render emoji centered, also try to fetch sticker image
            titleLabel.text = emoji
            titleLabel.font = .systemFont(ofSize: 80)
            titleLabel.textAlignment = .center
            titleLabel.isHidden = false
            mediaView.isHidden = true  // Will be revealed when image loads, if any
            mediaView.image = nil
            captionLabel.isHidden = true
            voiceButton.isHidden = true
            requestFile(fileId: fileId) { path in
                DispatchQueue.main.async {
                    if let p = path, let img = UIImage(contentsOfFile: p) {
                        self.mediaView.image = img
                        self.mediaView.isHidden = false
                        self.titleLabel.isHidden = true
                    }
                }
            }
        case .video(let caption, let fileId):
            captionLabel.text = "Video" + (caption.isEmpty ? "" : ": \(caption)")
            captionLabel.isHidden = false
            requestFile(fileId: fileId) { path in
                DispatchQueue.main.async {
                    if let p = path, let img = UIImage(contentsOfFile: p) {
                        self.mediaView.image = img
                        self.mediaView.isHidden = false
                    }
                }
            }
        case .voice(let duration, let fileId):
            voiceButton.isHidden = false
            voiceButton.setTitle(" ▸ \(duration)s", for: .normal)
            requestFile(fileId: fileId) { path in
                if let p = path {
                    DispatchQueue.main.async {
                        self.voiceButton.removeTarget(self, action: nil, for: .allEvents)
                        self.voiceButton.addTarget(self, action: #selector(self.playVoiceTapped),
                                                   for: .touchUpInside)
                        self.voiceButton.accessibilityHint = p
                    }
                }
            }
        case .system(let s):
            systemLabel.text = s
            systemLabel.isHidden = false
            bubble.isHidden = true
        case .unsupported:
            titleLabel.text = "Unsupported message"
            titleLabel.textColor = Theme.textSecondary
            titleLabel.isHidden = false
        }
    }

    @objc private func playVoiceTapped() {
        guard let path = voiceButton.accessibilityHint, !path.isEmpty else { return }
        do {
            currentPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            currentPlayer?.play()
        } catch {
            // ignore
        }
    }

    private func requestFile(fileId: Int64, completion: @escaping (String?) -> Void) {
        guard fileId > 0 else { completion(nil); return }
        TDLibManager.shared.request(function: "getFile",
                                   parameters: ["file_id": fileId]) { resp in
            if let local = resp.raw["local"] as? [String: Any],
               let path = local["path"] as? String, !path.isEmpty {
                completion(path)
            } else if let remote = resp.raw["remote"] as? [String: Any],
                      let rId = remote["id"] as? String, !rId.isEmpty {
                // Trigger download
                TDLibManager.shared.send(function: "downloadFile",
                                          parameters: ["file_id": fileId, "priority": 1, "offset": 0, "limit": 0, "synchronous": true])
                completion(nil)
            } else {
                completion(nil)
            }
        }
    }
}
