//
//  ChatStore.swift
//  TelegramLite
//
//  In-memory cache of chats + messages, fed by TDLib updates.
//  Subscribers (ViewControllers) get notified via NotificationCenter.
//

import Foundation
import UIKit

final class ChatStore {

    static let shared = ChatStore()

    /// chats: [chatId → TGChat]   sorted by lastMessageDate
    private(set) var chats: [TGChat] = []
    /// messages: [chatId → [TGMessage]]   sorted by id (chronological)
    private var messagesByChat: [Int64: [TGMessage]] = [:]

    private let lock = NSLock()
    private var loadedAll = false

    private init() {
        // Subscribe to TDLib updates
        TDLibManager.shared.subscribe("updateNewChat") { [weak self] resp in self?.handleNewChat(resp) }
        TDLibManager.shared.subscribe("updateNewMessage") { [weak self] resp in self?.handleNewMessage(resp) }
        TDLibManager.shared.subscribe("updateChatLastMessage") { [weak self] resp in self?.handleChatLastMessage(resp) }
        TDLibManager.shared.subscribe("updateChatReadUnreadCount") { [weak self] resp in self?.handleReadCount(resp) }
        TDLibManager.shared.subscribe("updateChatPosition") { [weak self] resp in self?.handleChatPosition(resp) }
        TDLibManager.shared.subscribe("updateChatDraftMessage") { [weak self] resp in self?.handleDraft(resp) }
        TDLibManager.shared.subscribe("updateDeleteMessages") { [weak self] resp in self?.handleDelete(resp) }
        TDLibManager.shared.subscribe("updateMessageSendSucceeded") { [weak self] resp in self?.handleSendSucceeded(resp) }
    }

    // MARK: - Loading

    func loadInitial(completion: @escaping () -> Void) {
        // Get chats list — TDLib will load them on demand and emit updateNewChat
        // per chat. Triggering getChats makes TDLib send them.
        TDLibManager.shared.request(function: "getChats",
                                   parameters: [
                                       "chat_list": ["@type": "chatListMain"],
                                       "limit": 100
                                   ]) { _ in
            DispatchQueue.main.async { completion() }
        }

        // Also subscribe to future updates
        TDLibManager.shared.send(function: "updateChatPosition", parameters: [:])
    }

    func chat(byId id: Int64) -> TGChat? {
        lock.lock(); defer { lock.unlock() }
        return chats.first(where: { $0.id == id })
    }

    func messages(for chatId: Int64) -> [TGMessage] {
        lock.lock(); defer { lock.unlock() }
        return messagesByChat[chatId] ?? []
    }

    // MARK: - Handlers

    private func handleNewChat(_ resp: TDResponse) {
        guard let chat = resp.raw["chat"] as? [String: Any] else { return }
        let tg = parseChat(chat)
        lock.lock()
        if let idx = chats.firstIndex(where: { $0.id == tg.id }) {
            chats[idx] = tg
        } else {
            chats.append(tg)
        }
        chats.sort { $0.lastMessageDate > $1.lastMessageDate }
        lock.unlock()
        notifyChatsUpdated()
    }

    private func handleNewMessage(_ resp: TDResponse) {
        guard let msg = resp.raw["message"] as? [String: Any] else { return }
        let tg = parseMessage(msg)
        lock.lock()
        var arr = messagesByChat[tg.chatId] ?? []
        if let idx = arr.firstIndex(where: { $0.id == tg.id }) {
            arr[idx] = tg
        } else {
            arr.append(tg)
        }
        arr.sort(by: { $0.id < $1.id })
        messagesByChat[tg.chatId] = arr
        // Bump chat last message if newer
        if let ci = chats.firstIndex(where: { $0.id == tg.chatId }) {
            if tg.date > chats[ci].lastMessageDate {
                chats[ci].lastMessageText = preview(msg: tg)
                chats[ci].lastMessageDate = tg.date
                chats.sort { $0.lastMessageDate > $1.lastMessageDate }
            }
        }
        lock.unlock()
        notifyMessagesUpdated(chatId: tg.chatId)
        notifyChatsUpdated()
    }

    private func handleChatLastMessage(_ resp: TDResponse) {
        guard let chatId = resp.raw["chat_id"] as? Int64,
              let last = resp.raw["last_message"] as? [String: Any] else { return }
        lock.lock()
        if let idx = chats.firstIndex(where: { $0.id == chatId }) {
            let previewText: String
            if let content = last["content"] as? [String: Any] {
                previewText = contentPreview(content, isOutgoing: last["is_outgoing"] as? Bool ?? false)
            } else {
                previewText = "..."
            }
            chats[idx].lastMessageText = previewText
            let dateInt = last["date"] as? Int ?? 0
            if dateInt > 0 {
                chats[idx].lastMessageDate = Date(timeIntervalSince1970: TimeInterval(dateInt))
            }
            chats.sort { $0.lastMessageDate > $1.lastMessageDate }
        }
        lock.unlock()
        notifyChatsUpdated()
    }

    private func handleReadCount(_ resp: TDResponse) {
        guard let chatId = resp.raw["chat_id"] as? Int64,
              let count = resp.raw["unread_count"] as? Int else { return }
        lock.lock()
        if let idx = chats.firstIndex(where: { $0.id == chatId }) {
            chats[idx].unreadCount = count
        }
        lock.unlock()
        notifyChatsUpdated()
    }

    private func handleChatPosition(_ resp: TDResponse) {
        // Pinning / ordering change
        guard let chatId = (resp.raw["chat_id"] as? Int64),
              let positions = resp.raw["positions"] as? [[String: Any]] else {
            if let cid = resp.raw["chat_id"] as? Int64, let pos = resp.raw["position"] as? [String: Any] {
                let isPinned = (pos["order"] as? Int64 ?? 0) > 0
                lock.lock()
                if let idx = chats.firstIndex(where: { $0.id == cid }) {
                    chats[idx].isPinned = isPinned
                }
                lock.unlock()
                notifyChatsUpdated()
            }
            return
        }
        _ = positions
    }

    private func handleDraft(_ resp: TDResponse) {
        guard let chatId = resp.raw["chat_id"] as? Int64 else { return }
        let draftText: String?
        if let draft = resp.raw["draft_message"] as? [String: Any],
           let input = draft["input_message_text"] as? [String: Any] {
            draftText = input["text"] as? [String: Any]
        } else {
            draftText = nil
        }
        lock.lock()
        if let idx = chats.firstIndex(where: { $0.id == chatId }) {
            chats[idx].draftText = draftText
        }
        lock.unlock()
        notifyChatsUpdated()
    }

    private func handleDelete(_ resp: TDResponse) {
        guard let chatId = resp.raw["chat_id"] as? Int64,
              let ids = resp.raw["message_ids"] as? [Int64] else { return }
        lock.lock()
        if var arr = messagesByChat[chatId] {
            arr.removeAll(where: { ids.contains($0.id) })
            messagesByChat[chatId] = arr
        }
        lock.unlock()
        notifyMessagesUpdated(chatId: chatId)
    }

    private func handleSendSucceeded(_ resp: TDResponse) {
        // Replace local msg id with server id
        guard let oldId = resp.raw["old_message_id"] as? Int64,
              let newMsg = resp.raw["message"] as? [String: Any],
              let chatId = newMsg["chat_id"] as? Int64,
              let newId = newMsg["id"] as? Int64 else { return }
        lock.lock()
        if var arr = messagesByChat[chatId] {
            if let idx = arr.firstIndex(where: { $0.id == oldId }) {
                var m = arr[idx]
                arr[idx] = TGMessage(id: newId,
                                     chatId: m.chatId,
                                     senderUserId: m.senderUserId,
                                     date: m.date,
                                     isOutgoing: m.isOutgoing,
                                     content: m.content,
                                     read: m.read,
                                     senderName: m.senderName)
                _ = m
            }
            messagesByChat[chatId] = arr
        }
        lock.unlock()
        notifyMessagesUpdated(chatId: chatId)
    }

    // MARK: - Notify

    private func notifyChatsUpdated() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .tgChatsUpdated, object: nil)
        }
    }
    private func notifyMessagesUpdated(chatId: Int64) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .tgMessagesUpdated, object: chatId)
        }
    }

    // MARK: - Parsing

    private func parseChat(_ c: [String: Any]) -> TGChat {
        let id = c["id"] as? Int64 ?? 0
        let title = c["title"] as? String ?? ""
        let typeRaw = (c["type"] as? [String: Any])?["@type"] as? String ?? "chatTypePrivate"
        let type: TGChatType
        switch typeRaw {
        case "chatTypePrivate":   type = .private_
        case "chatTypeBasicGroup": type = .group
        case "chatTypeSupergroup": type = .supergroup
        case "chatTypeSecret":     type = .secret
        default:                   type = .private_
        }
        // Channel detection — TDLib puts it as supergroup with `is_channel`.
        // We don't have that here without an extra query; we'll patch later.

        let last = c["last_message"] as? [String: Any]
        let lastText: String
        if let content = last?["content"] as? [String: Any] {
            lastText = contentPreview(content, isOutgoing: (last?["is_outgoing"] as? Bool) ?? false)
        } else {
            lastText = ""
        }
        let dateInt = last?["date"] as? Int ?? 0
        let date = dateInt > 0 ? Date(timeIntervalSince1970: TimeInterval(dateInt)) : Date(timeIntervalSince1970: 0)

        let unread = c["unread_count"] as? Int ?? 0
        let lastReadInbox = c["last_read_inbox_message_id"] as? Int64 ?? 0

        let photoURL: String? = {
            if let p = c["photo"] as? [String: Any],
               let small = p["small"] as? [String: Any],
               let local = small["local"] as? [String: Any] {
                return local["path"] as? String
            }
            return nil
        }()

        let isVerified = c["is_verified"] as? Bool ?? false
        let isMuted = ((c["notification_settings"] as? [String: Any])?["mute_for"] as? Int ?? 0) > 0

        let positionIsPinned = {
            if let pos = c["positions"] as? [[String: Any]],
               let list = pos.first(where: { ($0["list"] as? [String: Any])?["@type"] as? String == "chatListMain" }),
               let order = list["order"] as? Int64 { return order != 0 }
            return false
        }()

        return TGChat(
            id: id,
            title: title,
            type: type,
            lastMessageText: lastText,
            lastMessageDate: date,
            unreadCount: unread,
            lastReadInboxMessageId: lastReadInbox,
            avatarColorIndex: Int(id % 8),
            isVerified: isVerified,
            isPremium: false, // patched in user-detail query
            isPinned: positionIsPinned,
            isMuted: isMuted,
            photoURL: photoURL,
            draftText: nil
        )
    }

    private func parseMessage(_ m: [String: Any]) -> TGMessage {
        let id = m["id"] as? Int64 ?? 0
        let chatId = m["chat_id"] as? Int64 ?? 0
        let sender = (m["sender_id"] as? [String: Any])
        let senderId: Int64
        if let uid = sender?["user_id"] as? Int64 { senderId = uid }
        else if let cid = sender?["chat_id"] as? Int64 { senderId = cid }
        else { senderId = 0 }
        let dateInt = m["date"] as? Int ?? 0
        let isOutgoing = m["is_outgoing"] as? Bool ?? false
        let content = m["content"] as? [String: Any] ?? [:]
        let tgContent = parseContent(content)
        let senderName = (m["sender_name"] as? String) ?? ""

        return TGMessage(
            id: id,
            chatId: chatId,
            senderUserId: senderId,
            date: Date(timeIntervalSince1970: TimeInterval(dateInt)),
            isOutgoing: isOutgoing,
            content: tgContent,
            read: false,
            senderName: senderName
        )
    }

    private func parseContent(_ c: [String: Any]) -> TGMessageContent {
        let type = c["@type"] as? String ?? ""
        switch type {
        case "messageText":
            let text = (c["text"] as? [String: Any])?["text"] as? String ?? ""
            return .text(text)
        case "messagePhoto":
            let cap = (((c["caption"] as? [String: Any])?["text"] as? String) ?? "")
            let fileId = ((c["photo"] as? [String: Any])?["id"] as? Int64) ?? 0
            return .photo(caption: cap, fileId: fileId)
        case "messageAnimation":
            let cap = (((c["caption"] as? [String: Any])?["text"] as? String) ?? "")
            let fileId = ((c["animation"] as? [String: Any])?["id"] as? Int64) ?? 0
            return .gif(caption: cap, fileId: fileId)
        case "messageSticker":
            let emoji = ((c["sticker"] as? [String: Any])?["emoji"] as? String) ?? ""
            let setId = ((c["sticker"] as? [String: Any])?["set_id"] as? Int64) ?? 0
            return .sticker(emoji: emoji, setId: setId)
        case "messageVideo":
            let cap = (((c["caption"] as? [String: Any])?["text"] as? String) ?? "")
            let fileId = ((c["video"] as? [String: Any])?["id"] as? Int64) ?? 0
            return .video(caption: cap, fileId: fileId)
        case "messageVoiceNote":
            let dur = ((c["voice_note"] as? [String: Any])?["duration"] as? Int) ?? 0
            let fileId = ((c["voice_note"] as? [String: Any])?["id"] as? Int64) ?? 0
            return .voice(duration: dur, fileId: fileId)
        case "messageBasicGroupChatCreate", "messageChatAddMembers", "messageChatDeleteMember",
             "messageChatJoinByLink", "messageChatChangeTitle":
            return .system(text: "Group update")
        default:
            return .unsupported
        }
    }

    private func contentPreview(_ content: [String: Any], isOutgoing: Bool) -> String {
        let prefix = isOutgoing ? "You: " : ""
        let tg = parseContent(content)
        switch tg {
        case .text(let s):              return prefix + s
        case .photo(let c, _):          return prefix + "Photo" + (c.isEmpty ? "" : ": \(c)")
        case .gif(let c, _):            return prefix + "GIF" + (c.isEmpty ? "" : ": \(c)")
        case .sticker(let e, _):        return prefix + "\(e) Sticker"
        case .video(let c, _):          return prefix + "Video" + (c.isEmpty ? "" : ": \(c)")
        case .voice(let d, _):          return prefix + "Voice (\(d)s)"
        case .system(let s):            return s
        case .unsupported:              return prefix + "Unsupported message"
        }
    }

    private func preview(msg: TGMessage) -> String {
        let prefix = msg.isOutgoing ? "You: " : ""
        switch msg.content {
        case .text(let s):   return prefix + s
        case .photo(let c, _): return prefix + "Photo" + (c.isEmpty ? "" : ": \(c)")
        case .gif(let c, _):   return prefix + "GIF" + (c.isEmpty ? "" : ": \(c)")
        case .sticker(let e, _): return prefix + "\(e) Sticker"
        case .video(let c, _): return prefix + "Video" + (c.isEmpty ? "" : ": \(c)")
        case .voice(let d, _): return prefix + "Voice (\(d)s)"
        case .system(let s):   return s
        case .unsupported:     return prefix + "Unsupported message"
        }
    }
}
