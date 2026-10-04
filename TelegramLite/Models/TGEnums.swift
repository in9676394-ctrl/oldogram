//
//  TGEnums.swift
//  TelegramLite
//
//  Lightweight value-type mirrors of TDLib objects.
//  We keep these separate from the TDLib-generated source so the rest of
//  the app does NOT import the heavy TDLib module everywhere.
//

import Foundation
import UIKit

enum TGChatType: String {
    case private_   = "private"
    case group      = "group"
    case supergroup = "supergroup"
    case channel    = "channel"
    case secret     = "secret"
}

enum TGMessageContent {
    case text(String)
    case photo(caption: String, fileId: Int64)
    case gif(caption: String, fileId: Int64)
    case sticker(emoji: String, setId: Int64)
    case video(caption: String, fileId: Int64)
    case voice(duration: Int, fileId: Int64)
    case system(text: String)
    case unsupported
}

struct TGChat {
    let id: Int64
    var title: String
    var type: TGChatType
    var lastMessageText: String
    var lastMessageDate: Date
    var unreadCount: Int
    var lastReadInboxMessageId: Int64
    var avatarColorIndex: Int
    var isVerified: Bool
    var isPremium: Bool          // for private chats — peer is premium
    var isPinned: Bool
    var isMuted: Bool
    var photoURL: String?
    var draftText: String?

    /// Letter to draw on placeholder avatar.
    var avatarInitial: String {
        guard let first = title.first else { return "#" }
        return String(first).uppercased()
    }

    /// Deterministic color for placeholder avatar when no remote photo.
    var avatarColor: UIColor {
        let palette: [UInt32] = [
            0xFF885E, 0xFFCD6A, 0x82B1FF, 0xB388FF,
            0x7ED957, 0x4DD864, 0x00BCD4, 0xF36F8D
        ]
        let idx = Int(id % Int64(palette.count))
        return UIColor(hex: palette[idx])
    }
}

struct TGUser {
    let id: Int64
    var firstName: String
    var lastName: String
    var username: String?
    var phone: String?
    var bio: String?
    var isPremium: Bool
    var isVerified: Bool
    var photoURL: String?

    var fullName: String {
        if !lastName.isEmpty { return "\(firstName) \(lastName)" }
        return firstName
    }
}

struct TGMessage {
    let id: Int64
    let chatId: Int64
    let senderUserId: Int64
    let date: Date
    let isOutgoing: Bool
    var content: TGMessageContent
    var read: Bool
    var senderName: String    // for groups — name of sender
}
