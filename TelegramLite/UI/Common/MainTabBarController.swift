//
//  MainTabBarController.swift
//  TelegramLite
//
//  Bottom tab bar: Chats / Calls / Settings.
//  No Stories, no Stars — by request.
//

import UIKit

final class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg

        // Chat list
        let chats = UINavigationController(rootViewController: ChatListViewController())
        chats.tabBarItem = UITabBarItem(
            title: "Chats",
            image: UIImage(systemName: "bubble.left.and.bubble.right")?.withTintColor(Theme.textSecondary, renderingMode: .alwaysOriginal),
            selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill")?.withTintColor(Theme.accent, renderingMode: .alwaysOriginal)
        )
        styleNav(chats.navigationBar)

        // Calls
        let calls = UINavigationController(rootViewController: CallsViewController())
        calls.tabBarItem = UITabBarItem(
            title: "Calls",
            image: UIImage(systemName: "phone")?.withTintColor(Theme.textSecondary, renderingMode: .alwaysOriginal),
            selectedImage: UIImage(systemName: "phone.fill")?.withTintColor(Theme.accent, renderingMode: .alwaysOriginal)
        )
        styleNav(calls.navigationBar)

        // Settings
        let settings = UINavigationController(rootViewController: SettingsViewController())
        settings.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gear")?.withTintColor(Theme.textSecondary, renderingMode: .alwaysOriginal),
            selectedImage: UIImage(systemName: "gear")?.withTintColor(Theme.accent, renderingMode: .alwaysOriginal)
        )
        styleNav(settings.navigationBar)

        viewControllers = [chats, calls, settings]

        // Style tab bar itself
        tabBar.barTintColor = Theme.navbar
        tabBar.backgroundColor = Theme.navbar
        tabBar.tintColor = Theme.accent
        tabBar.unselectedItemTintColor = Theme.textSecondary
        tabBar.isTranslucent = false
        tabBar.layer.shadowColor = UIColor.clear.cgColor
        // Hide top hairline
        tabBar.setValue(true, forKey: "hidesShadow")

        // Load chats as soon as we appear
        DispatchQueue.global().async {
            ChatStore.shared.loadInitial { /* done */ }
        }
    }

    private func styleNav(_ bar: UINavigationBar) {
        bar.barTintColor = Theme.navbar
        bar.tintColor = Theme.accent
        bar.backgroundColor = Theme.navbar
        bar.titleTextAttributes = [
            .foregroundColor: Theme.text,
            .font: Theme.semiboldFont(17)
        ]
        bar.isTranslucent = false
        bar.setValue(true, forKey: "hidesShadow")
        if #available(iOS 11.0, *) {
            bar.largeTitleTextAttributes = [
                .foregroundColor: Theme.text,
                .font: Theme.boldFont(34)
            ]
        }
    }
}
