//
//  AppDelegate.swift
//  TelegramLite
//
//  Created for iOS 11+ — ultra-light Telegram client.
//

import UIKit
import UserNotifications

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Register remote notifications for push (needs APNs cert — see README)
        application.registerForRemoteNotifications()

        // Request local notification permissions (used for incoming calls / messages when app in bg)
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        } else {
            let settings = UIUserNotificationSettings(types: [.alert, .sound, .badge], categories: nil)
            application.registerUserNotificationSettings(settings)
        }

        // Boot TDLib in background — it spins its own queue.
        TDLibManager.shared.start()

        // Build root UI.
        Theme.apply(.dark) // Telegram X default — pure dark. Change to .light if you prefer iOS native light.
        window = UIWindow(frame: UIScreen.main.bounds)
        showRootController()
        window?.makeKeyAndVisible()

        return true
    }

    func showRootController() {
        guard let window = window else { return }

        // Decide which screen to show based on auth state.
        if AuthManager.shared.isLoggedIn {
            window.rootViewController = MainTabBarController()
        } else {
            let nav = UINavigationController(rootViewController: AuthViewController())
            nav.navigationBar.tintColor = Theme.accent
            nav.navigationBar.barTintColor = Theme.navbar
            nav.navigationBar.titleTextAttributes = [
                .foregroundColor: Theme.text,
                .font: Theme.semiboldFont(17)
            ]
            // Remove iOS hairline for clean look
            nav.navigationBar.setValue(true, forKey: "hidesShadow")
            window.rootViewController = nav
        }
    }

    // MARK: - Push

    func application(_ application: UIApplication,
                    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        TDLibManager.shared.registerDeviceToken(token)
    }

    func application(_ application: UIApplication,
                    didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Push] register failed: \(error.localizedDescription)")
    }

    // MARK: - Lifecycle

    func applicationDidEnterBackground(_ application: UIApplication) {
        TDLibManager.shared.pause()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        TDLibManager.shared.resume()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        TDLibManager.shared.stop()
    }
}
