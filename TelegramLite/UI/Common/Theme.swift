//
//  Theme.swift
//  TelegramLite
//
//  iOS native minimal aesthetic, dark Telegram X vibe.
//  All colors/fonts centralized — app "flies" because there's zero runtime theming cost.
//

import UIKit

enum ThemeStyle {
    case light
    case dark
}

enum Theme {

    // MARK: - Style switch

    private(set) static var current: ThemeStyle = .dark

    static func apply(_ style: ThemeStyle) {
        current = style
        // No fancy dynamic colors — we want one absolute palette for max perf.
        switch style {
        case .dark:
            bg          = UIColor(hex: 0x000000)
            bgElevated  = UIColor(hex: 0x1C1C1E)
            navbar      = UIColor(hex: 0x0A0A0A)
            cellBg      = UIColor(hex: 0x000000)
            cellBgAlt   = UIColor(hex: 0x121212)
            separator   = UIColor(hex: 0x1C1C1E)
            text        = UIColor(hex: 0xFFFFFF)
            textSecondary = UIColor(hex: 0x8E8E93)
            accent      = UIColor(hex: 0x0098FC)
            bubbleOut   = UIColor(hex: 0x2C5, alpha: 0.96)  // Telegram green for outgoing
            bubbleIn    = UIColor(hex: 0x1C1C1E)
            bubbleOutText = .white
            bubbleInText = .white
            unread      = UIColor(hex: 0x0098FC)
            premium     = UIColor(hex: 0xE0C055)
            online      = UIColor(hex: 0x4DD864)
            destructive = UIColor(hex: 0xFF453A)
        case .light:
            bg          = UIColor(hex: 0xFFFFFF)
            bgElevated  = UIColor(hex: 0xF2F2F7)
            navbar      = UIColor(hex: 0xF9F9F9)
            cellBg      = UIColor(hex: 0xFFFFFF)
            cellBgAlt   = UIColor(hex: 0xF2F2F7)
            separator   = UIColor(hex: 0xE5E5EA)
            text        = UIColor(hex: 0x000000)
            textSecondary = UIColor(hex: 0x8E8E93)
            accent      = UIColor(hex: 0x007AFF)
            bubbleOut   = UIColor(hex: 0x37D2A1)
            bubbleIn    = UIColor(hex: 0xE9E9EB)
            bubbleOutText = .white
            bubbleInText = .black
            unread      = UIColor(hex: 0x007AFF)
            premium     = UIColor(hex: 0xC7951C)
            online      = UIColor(hex: 0x34C759)
            destructive = UIColor(hex: 0xFF3B30)
        }

        // Status bar
        UIApplication.shared.statusBarStyle = (current == .dark) ? .lightContent : .default
    }

    // MARK: - Palette (mutated by apply(_:))

    static var bg: UIColor           = .black
    static var bgElevated: UIColor   = .black
    static var navbar: UIColor       = .black
    static var cellBg: UIColor       = .black
    static var cellBgAlt: UIColor    = .black
    static var separator: UIColor    = .darkGray
    static var text: UIColor         = .white
    static var textSecondary: UIColor = .lightGray
    static var accent: UIColor       = .blue
    static var bubbleOut: UIColor    = .green
    static var bubbleIn: UIColor     = .darkGray
    static var bubbleOutText: UIColor = .white
    static var bubbleInText: UIColor = .white
    static var unread: UIColor       = .blue
    static var premium: UIColor      = .yellow
    static var online: UIColor       = .green
    static var destructive: UIColor  = .red

    // MARK: - Typography

    /// SF Pro is the iOS system font. Using `.system` (not `.rounded` or `.mono`)
    /// keeps glyph rasterization fast on A7/A8 chips (iPhone 5s/6).
    static func regularFont(_ size: CGFloat) -> UIFont {
        return .systemFont(ofSize: size, weight: .regular)
    }
    static func mediumFont(_ size: CGFloat) -> UIFont {
        return .systemFont(ofSize: size, weight: .medium)
    }
    static func semiboldFont(_ size: CGFloat) -> UIFont {
        return .systemFont(ofSize: size, weight: .semibold)
    }
    static func boldFont(_ size: CGFloat) -> UIFont {
        return .systemFont(ofSize: size, weight: .bold)
    }

    // MARK: - Layout metrics

    static let cornerRadius: CGFloat   = 14
    static let bubbleRadius: CGFloat   = 16
    static let avatarSize: CGFloat     = 46
    static let bubbleMaxWidth: CGFloat = 260
    static let tapTarget: CGFloat      = 44   // Apple HIG minimum tap target
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8)  & 0xFF) / 255.0,
            blue:  CGFloat( hex        & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
