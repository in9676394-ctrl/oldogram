//
//  MessageSender.swift
//  TelegramLite
//
//  High-level helpers for sending messages, media, and viewing chat history.
//

import Foundation
import UIKit

final class MessageSender {

    static let shared = MessageSender()
    private init() {}

    /// Load older messages (for pagination / infinite scroll)
    func loadHistory(chatId: Int64, fromMessageId: Int64 = 0, limit: Int = 50,
                     completion: @escaping () -> Void) {
        TDLibManager.shared.request(function: "getChatHistory",
                                   parameters: [
                                       "chat_id": chatId,
                                       "from_message_id": fromMessageId,
                                       "offset": 0,
                                       "limit": limit,
                                       "only_local": false
                                   ]) { resp in
            // TDLib emits updates for new messages via updateNewMessage —
            // the ChatStore will already pick those up. We just signal done.
            DispatchQueue.main.async { completion() }
        }
    }

    func sendText(chatId: Int64, text: String, replyTo: Int64? = nil,
                  completion: ((Int64) -> Void)? = nil) {
        var params: [String: Any] = [
            "chat_id": chatId,
            "input_message_content": [
                "@type": "inputMessageText",
                "text": ["@type": "formattedText", "text": text]
            ]
        ]
        if let r = replyTo { params["reply_to_message_id"] = r }
        TDLibManager.shared.request(function: "sendMessage",
                                    parameters: params) { resp in
            if let msg = resp.raw["message"] as? [String: Any],
               let id = msg["id"] as? Int64 {
                completion?(id)
            } else {
                completion?(0)
            }
        }
    }

    func sendPhoto(chatId: Int64, image: UIImage, caption: String = "",
                   completion: (() -> Void)? = nil) {
        guard let pngData = image.pngData() else { return }
        // Step 1: upload as file
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try? pngData.write(to: tmp)

        // Step 2: create input file
        TDLibManager.shared.request(function: "addFileToProcess",
                                   parameters: [
                                       "file": ["@type": "inputFile", "path": tmp.path, "name": "photo.png"]
                                   ]) { _ in
            // Then send with that file
            TDLibManager.shared.request(function: "sendMessage",
                                       parameters: [
                                           "chat_id": chatId,
                                           "input_message_content": [
                                               "@type": "inputMessagePhoto",
                                               "photo": ["@type": "inputFile", "path": tmp.path, "name": "photo.png"],
                                               "caption": ["@type": "formattedText", "text": caption]
                                           ]
                                       ]) { _ in
                completion?()
            }
        }
    }

    func sendGIF(chatId: Int64, gifURL: URL, caption: String = "",
                 completion: (() -> Void)? = nil) {
        let path = gifURL.path
        TDLibManager.shared.request(function: "sendMessage",
                                   parameters: [
                                       "chat_id": chatId,
                                       "input_message_content": [
                                           "@type": "inputMessageAnimation",
                                           "animation": ["@type": "inputFile", "path": path, "name": gifURL.lastPathComponent],
                                           "caption": ["@type": "formattedText", "text": caption]
                                       ]
                                   ]) { _ in
            completion?()
        }
    }

    func sendSticker(chatId: Int64, stickerId: Int64, completion: (() -> Void)? = nil) {
        TDLibManager.shared.request(function: "sendMessage",
                                   parameters: [
                                       "chat_id": chatId,
                                       "input_message_content": [
                                           "@type": "inputMessageSticker",
                                           "sticker": ["@type": "inputFile", "id": stickerId]
                                       ]
                                   ]) { _ in
            completion?()
        }
    }

    func deleteMessages(chatId: Int64, messageIds: [Int64], revoke: Bool = true) {
        TDLibManager.shared.request(function: "deleteMessages",
                                   parameters: [
                                       "chat_id": chatId,
                                       "message_ids": messageIds,
                                       "revoke": revoke
                                   ]) { _ in }
    }

    func markRead(chatId: Int64, lastMessageId: Int64) {
        TDLibManager.shared.send(function: "viewMessages",
                                 parameters: [
                                     "chat_id": chatId,
                                     "message_ids": [lastMessageId],
                                     "force_read": true
                                 ])
    }

    func sendVoice(chatId: Int64, audioPath: String, duration: Int) {
        TDLibManager.shared.request(function: "sendMessage",
                                   parameters: [
                                       "chat_id": chatId,
                                       "input_message_content": [
                                           "@type": "inputMessageVoiceNote",
                                           "voice_note": ["@type": "inputFile", "path": audioPath, "name": "voice.m4a"],
                                           "duration": duration
                                       ]
                                   ]) { _ in }
    }
}
