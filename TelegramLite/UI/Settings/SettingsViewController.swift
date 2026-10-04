//
//  SettingsViewController.swift
//  TelegramLite
//
//  Settings — profile, theme switch, notifications, premium display, logout.
//

import UIKit

final class SettingsViewController: UITableViewController {

    private struct Row {
        let title: String
        let detail: String?
        let icon: String
        let iconColor: UIColor
        let action: () -> Void
    }
    private struct Section {
        let header: String?
        let rows: [Row]
    }

    private var sections: [Section] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg
        title = "Settings"
        if #available(iOS 11.0, *) { navigationController?.navigationBar.prefersLargeTitles = true }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.backgroundColor = Theme.bg
        tableView.separatorColor = Theme.separator
        tableView.tableFooterView = makeProfileHeader()
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: .tgAuthReady, object: nil)
        loadMe()
    }

    @objc private func reload() {
        loadMe()
    }

    private func loadMe() {
        TDLibManager.shared.request(function: "getMe", parameters: [:]) { resp in
            if let u = resp.raw as? [String: Any] {
                let first = u["first_name"] as? String ?? ""
                let last  = u["last_name"]  as? String ?? ""
                let uname = u["username"] as? String
                let isPremium = u["is_premium"] as? Bool ?? false
                DispatchQueue.main.async { self.buildSections(name: "\(first) \(last)", username: uname, isPremium: isPremium) }
            }
        }
    }

    private func buildSections(name: String, username: String?, isPremium: Bool) {
        sections.removeAll()

        let themeTitle = (Theme.current == .dark) ? "Light" : "Dark"
        sections.append(Section(header: "Appearance", rows: [
            Row(title: "Theme", detail: Theme.current == .dark ? "Dark" : "Light",
                icon: "moon.fill", iconColor: Theme.accent,
                action: {
                    Theme.apply(Theme.current == .dark ? .light : .dark)
                    // Reload the whole app to apply — simpler than cascading UIAppearance.
                    if let app = UIApplication.shared.delegate as? AppDelegate {
                        app.window?.rootViewController = MainTabBarController()
                    }
                }),
            Row(title: "Premium Status", detail: isPremium ? "Active" : "Inactive",
                icon: "crown.fill", iconColor: Theme.premium,
                action: { /* no-op — visual only */ }),
        ]))

        sections.append(Section(header: "Account", rows: [
            Row(title: "Name", detail: name, icon: "person.fill", iconColor: Theme.accent, action: { }),
            Row(title: "Username", detail: "@\(username ?? "none")", icon: "at", iconColor: Theme.accent, action: { }),
            Row(title: "Saved Messages", detail: nil, icon: "bookmark.fill", iconColor: Theme.accent,
                action: {
                    TDLibManager.shared.request(function: "getMe", parameters: [:]) { resp in
                        if let id = resp.raw["id"] as? Int64 {
                            DispatchQueue.main.async {
                                let vc = ChatViewController(chatId: id)
                                self.navigationController?.pushViewController(vc, animated: true)
                            }
                        }
                    }
                }),
        ]))

        sections.append(Section(header: "Privacy", rows: [
            Row(title: "Phone Number", detail: nil, icon: "phone.fill", iconColor: Theme.accent, action: { }),
            Row(title: "Last Seen", detail: nil, icon: "clock.fill", iconColor: Theme.accent, action: { }),
            Row(title: "Profile Photo", detail: nil, icon: "photo.fill", iconColor: Theme.accent, action: { }),
        ]))

        sections.append(Section(header: "Debug", rows: [
            Row(title: "API Credentials",
                detail: TDLibManager.hasCredentials ? "Set ✓" : "MISSING",
                icon: "key.fill",
                iconColor: TDLibManager.hasCredentials ? Theme.online : Theme.destructive,
                action: {
                    let alert = UIAlertController(title: "API credentials",
                                                  message: TDLibManager.hasCredentials
                                                    ? "api_id = \(TDLibManager.api_id)\napi_hash = \(TDLibManager.api_hash.prefix(8))...\n\nThese are baked into the binary at build time. To change them, update GitHub Secrets TG_API_ID and TG_API_HASH, then re-trigger the workflow."
                                                    : "MISSING. Get them at https://my.telegram.org → API development tools, add as GitHub Secrets TG_API_ID and TG_API_HASH, re-trigger the workflow.",
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }),
            Row(title: "Debug Log",
                detail: "\(TDLibManager.logLines.count) lines",
                icon: "doc.text.fill",
                iconColor: Theme.accent,
                action: { self.showDebugLog() }),
        ]))

        sections.append(Section(header: "Data", rows: [
            Row(title: "Storage Usage", detail: nil, icon: "internaldrive", iconColor: Theme.accent, action: { }),
            Row(title: "Auto-Download Media", detail: "On", icon: "arrow.down.circle.fill", iconColor: Theme.accent, action: { }),
            Row(title: "Clear Cache", detail: nil, icon: "trash.fill", iconColor: Theme.destructive,
                action: {
                    TDLibManager.shared.send(function: "optimizeStorage",
                                             parameters: [
                                                "size": 1024 * 1024 * 1024,
                                                "duration": 0,
                                                "chat_ids": [],
                                                "exclude_chat_ids": [],
                                                "return_deleted_file_count": false,
                                                "chat_ids_": [],
                                                "apply_to_new_groups": true,
                                                "apply_to_new_channels": true,
                                                "apply_to_new_users": true,
                                                "types": ["@type": "storageFastPathFile"]
                                             ])
                }),
        ]))

        sections.append(Section(header: nil, rows: [
            Row(title: "Log Out", detail: nil, icon: "arrow.right.square.fill",
                iconColor: Theme.destructive,
                action: {
                    let alert = UIAlertController(title: "Log Out",
                                                  message: "Are you sure?",
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { _ in
                        AuthManager.shared.logout {
                            if let app = UIApplication.shared.delegate as? AppDelegate {
                                app.showRootController()
                            }
                        }
                    })
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                    self.present(alert, animated: true)
                })
        ]))

        tableView.reloadData()
    }

    // MARK: - Profile header

    private func makeProfileHeader() -> UIView {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 110))
        let avatar = AvatarView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(avatar)
        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            avatar.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            avatar.widthAnchor.constraint(equalToConstant: 70),
            avatar.heightAnchor.constraint(equalToConstant: 70),
        ])
        avatar.set(title: "Me", color: Theme.accent, url: nil)
        return header
    }

    // MARK: - Debug log

    private func showDebugLog() {
        let nav = UINavigationController(rootViewController: DebugLogViewController())
        nav.navigationBar.barTintColor = Theme.navbar
        nav.navigationBar.tintColor = Theme.accent
        nav.navigationBar.titleTextAttributes = [
            .foregroundColor: Theme.text,
            .font: Theme.semiboldFont(17)
        ]
        present(nav, animated: true)
    }

    // MARK: - Table data

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].header
    }
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let h = view as? UITableViewHeaderFooterView {
            h.textLabel?.font = Theme.semiboldFont(12)
            h.textLabel?.textColor = Theme.textSecondary
            h.contentView.backgroundColor = Theme.bg
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let row = sections[indexPath.section].rows[indexPath.row]
        cell.textLabel?.text = row.title
        cell.textLabel?.textColor = Theme.text
        cell.detailTextLabel?.text = row.detail
        cell.detailTextLabel?.textColor = Theme.textSecondary
        cell.imageView?.image = UIImage(systemName: row.icon)?
            .withTintColor(row.iconColor, renderingMode: .alwaysOriginal)
        cell.backgroundColor = Theme.cellBg
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        row.action()
    }
}
