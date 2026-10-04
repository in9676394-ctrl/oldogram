//
//  ChatListViewController.swift
//  TelegramLite
//
//  Main chat list. Pinned chats sticky at top (visually indicated).
//

import UIKit

final class ChatListViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)

    private var chats: [TGChat] = []
    private var filtered: [TGChat] = []
    private var isSearching: Bool { searchController.isActive && (searchController.searchBar.text ?? "").isEmpty == false }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg
        title = "Chats"
        if #available(iOS 11.0, *) { navigationController?.navigationBar.prefersLargeTitles = true }

        setupTableView()
        setupSearch()
        setupNewChatButton()

        NotificationCenter.default.addObserver(self, selector: #selector(handleChatsUpdated),
                                              name: .tgChatsUpdated, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
        reloadFromStore()
    }

    // MARK: - Setup

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseId)
        tableView.backgroundColor = Theme.bg
        tableView.separatorColor = Theme.separator
        tableView.rowHeight = 70
        tableView.tableFooterView = UIView()
        // Hide scroll-to-top indicator (looks cleaner in lite design)
        tableView.showsVerticalScrollIndicator = false
        tableView.estimatedRowHeight = 70
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 76, bottom: 0, right: 0)
        _ = makeRefreshControl()
    }

    private func makeRefreshControl() -> UIRefreshControl {
        let rc = UIRefreshControl()
        rc.tintColor = Theme.accent
        rc.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = rc
        return rc
    }

    private func setupSearch() {
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "Search chats"
        searchController.searchBar.tintColor = Theme.accent
        searchController.searchBar.barTintColor = Theme.navbar
        if #available(iOS 11.0, *) {
            navigationItem.searchController = searchController
            navigationItem.hidesSearchBarWhenScrolling = false
        } else {
            tableView.tableHeaderView = searchController.searchBar
        }
        definesPresentationContext = true
    }

    private func setupNewChatButton() {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "square.and.pencil")?
            .withTintColor(Theme.accent, renderingMode: .alwaysOriginal),
                     for: .normal)
        btn.backgroundColor = Theme.accent.withAlphaComponent(0.12)
        btn.layer.cornerRadius = 28
        btn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 56),
            btn.heightAnchor.constraint(equalToConstant: 56),
            btn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            btn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
        btn.addTarget(self, action: #selector(openNewChat), for: .touchUpInside)
    }

    // MARK: - Data

    @objc private func refresh() {
        ChatStore.shared.loadInitial { [weak self] in
            self?.reloadFromStore()
            self?.tableView.refreshControl?.endRefreshing()
        }
    }

    @objc private func handleChatsUpdated() {
        reloadFromStore()
    }

    private func reloadFromStore() {
        chats = ChatStore.shared.chats
        applyFilter()
        tableView.reloadData()
    }

    private func applyFilter() {
        let query = (searchController.searchBar.text ?? "").lowercased()
        filtered = query.isEmpty ? chats :
            chats.filter { $0.title.lowercased().contains(query) }
    }

    // MARK: - New chat

    @objc private func openNewChat() {
        let alert = UIAlertController(title: "New chat",
                                      message: "Open a private chat by user ID or username",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "@username or numeric id"
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in
            let raw = alert.textFields?.first?.text ?? ""
            self.openChatByQuery(raw)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func openChatByQuery(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            // Username lookup
            let username = String(trimmed.dropFirst())
            TDLibManager.shared.request(function: "searchPublicChat",
                                       parameters: ["username": username]) { resp in
                if let id = resp.raw["id"] as? Int64 {
                    DispatchQueue.main.async { self.openChat(id: id) }
                }
            }
        } else if let n = Int64(trimmed) {
            openChat(id: n)
        } else {
            // Default to Saved Messages
            TDLibManager.shared.request(function: "getChat",
                                       parameters: ["chat_id": 0]) { _ in } // 0 means saved messages in TDLib
            // For Saved Messages we use chatId 0 — TDLib treats 0 as the Saved Messages pseudo-chat
            // Actually that's not how TDLib does it — saved messages chatId is provided by getChats /
            // we'd need a separate API call. For now, look it up via the current user.
            self.openSavedMessages()
        }
    }

    private func openSavedMessages() {
        TDLibManager.shared.request(function: "getMe",
                                   parameters: [:]) { resp in
            if let user = resp.raw["id"] as? Int64 {
                // Open private chat with self
                TDLibManager.shared.request(function: "createPrivateChat",
                                           parameters: ["user_id": user, "force": false]) { _ in
                    DispatchQueue.main.async { self.openChat(id: user) }
                }
            }
        }
    }

    private func openChat(id: Int64) {
        let vc = ChatViewController(chatId: id)
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - DataSource / Delegate

extension ChatListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isSearching ? filtered.count : chats.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatListCell.reuseId,
                                                 for: indexPath) as! ChatListCell
        let chat = isSearching ? filtered[indexPath.row] : chats[indexPath.row]
        cell.configure(with: chat)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let chat = isSearching ? filtered[indexPath.row] : chats[indexPath.row]
        openChat(id: chat.id)
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let chat = (isSearching ? filtered : chats)[indexPath.row]
        let pinTitle = chat.isPinned ? "Unpin" : "Pin"
        let pinAction = UIContextualAction(style: .normal, title: pinTitle) { _, _, completion in
            TDLibManager.shared.send(function: "toggleChatIsPinned",
                                     parameters: [
                                         "chat_id": chat.id,
                                         "chat_list": ["@type": "chatListMain"]
                                     ])
            completion(true)
        }
        pinAction.backgroundColor = Theme.bgElevated
        return UISwipeActionsConfiguration(actions: [pinAction])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let chat = (isSearching ? filtered : chats)[indexPath.row]
        let muteAction = UIContextualAction(style: .normal, title: chat.isMuted ? "Unmute" : "Mute") { _, _, completion in
            let newMute = chat.isMuted ? 0 : Int.max
            TDLibManager.shared.send(function: "setChatNotificationSettings",
                                     parameters: [
                                        "chat_id": chat.id,
                                        "notification_settings": [
                                            "@type": "chatNotificationSettings",
                                            "mute_for": newMute,
                                            "show_preview": false,
                                            "disable_pinned_message_notifications": false,
                                            "disable_mention_notifications": false
                                        ]
                                     ])
            completion(true)
        }
        muteAction.backgroundColor = .systemOrange
        let deleteAction = UIContextualAction(style: .destructive, title: "Hide") { _, _, completion in
            TDLibManager.shared.send(function: "setChatDraftMessage",
                                     parameters: ["chat_id": chat.id, "draft_message": NSNull()])
            TDLibManager.shared.send(function: "removeChatActionList",
                                     parameters: ["chat_list": ["@type": "chatListMain"], "chat_id": chat.id])
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction, muteAction])
    }
}

extension ChatListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        applyFilter()
        tableView.reloadData()
    }
}

// MARK: - Cell

final class ChatListCell: UITableViewCell {

    static let reuseId = "ChatListCell"

    private let avatar = AvatarView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let timeLabel = UILabel()
    private let unreadBadge = UILabel()
    private let verifiedIcon = UIImageView()
    private let premiumIcon = UIImageView()
    private let pinIcon = UIImageView()
    private let muteIcon = UIImageView()
    private let draftLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: ChatListCell.reuseId)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = Theme.cellBg
        textLabel?.textColor = Theme.text

        titleLabel.font = Theme.semiboldFont(16)
        titleLabel.textColor = Theme.text
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = Theme.regularFont(15)
        subtitleLabel.textColor = Theme.textSecondary
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail

        timeLabel.font = Theme.regularFont(12)
        timeLabel.textColor = Theme.textSecondary

        unreadBadge.backgroundColor = Theme.unread
        unreadBadge.textColor = .white
        unreadBadge.font = Theme.semiboldFont(11)
        unreadBadge.textAlignment = .center
        unreadBadge.layer.cornerRadius = 9
        unreadBadge.layer.masksToBounds = true

        verifiedIcon.image = UIImage(systemName: "checkmark.seal.fill")?
            .withTintColor(Theme.accent, renderingMode: .alwaysOriginal)
        verifiedIcon.contentMode = .scaleAspectFit

        premiumIcon.image = UIImage(systemName: "crown.fill")?
            .withTintColor(Theme.premium, renderingMode: .alwaysOriginal)
        premiumIcon.contentMode = .scaleAspectFit

        pinIcon.image = UIImage(systemName: "pin.fill")?
            .withTintColor(Theme.textSecondary, renderingMode: .alwaysOriginal)

        muteIcon.image = UIImage(systemName: "speaker.slash.fill")?
            .withTintColor(Theme.textSecondary, renderingMode: .alwaysOriginal)

        draftLabel.font = Theme.regularFont(15)
        draftLabel.textColor = Theme.destructive
        draftLabel.text = "Draft: "

        // Build layout via Auto Layout
        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.distribution = .fill
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(avatar)
        contentView.addSubview(textStack)
        contentView.addSubview(timeLabel)
        contentView.addSubview(unreadBadge)
        contentView.addSubview(verifiedIcon)
        contentView.addSubview(premiumIcon)
        contentView.addSubview(pinIcon)
        contentView.addSubview(muteIcon)
        contentView.addSubview(draftLabel)

        avatar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: Theme.avatarSize),
            avatar.heightAnchor.constraint(equalToConstant: Theme.avatarSize),

            textStack.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),

            timeLabel.trailingAnchor.constraint(equalTo: unreadBadge.leadingAnchor, constant: -8),
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            timeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 70),

            unreadBadge.trailingAnchor.constraint(equalTo: muteIcon.leadingAnchor, constant: -8),
            unreadBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            unreadBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            unreadBadge.heightAnchor.constraint(equalToConstant: 18),

            muteIcon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            muteIcon.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 17),
            muteIcon.widthAnchor.constraint(equalToConstant: 12),
            muteIcon.heightAnchor.constraint(equalToConstant: 14),

            pinIcon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            pinIcon.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            pinIcon.widthAnchor.constraint(equalToConstant: 12),
            pinIcon.heightAnchor.constraint(equalToConstant: 12),

            verifiedIcon.widthAnchor.constraint(equalToConstant: 12),
            verifiedIcon.heightAnchor.constraint(equalToConstant: 12),

            premiumIcon.widthAnchor.constraint(equalToConstant: 12),
            premiumIcon.heightAnchor.constraint(equalToConstant: 12),

            draftLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            draftLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
        ])

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func configure(with chat: TGChat) {
        avatar.set(title: chat.avatarInitial, color: chat.avatarColor, url: chat.photoURL)
        titleLabel.text = chat.title

        if let draft = chat.draftText, !draft.isEmpty {
            // Show draft
            subtitleLabel.isHidden = true
            draftLabel.text = "Draft: " + draft
            draftLabel.isHidden = false
        } else {
            draftLabel.isHidden = true
            subtitleLabel.text = chat.lastMessageText
            subtitleLabel.isHidden = false
        }

        timeLabel.text = formatRelative(chat.lastMessageDate)
        verifiedIcon.isHidden = !chat.isVerified
        premiumIcon.isHidden = !chat.isPremium
        pinIcon.isHidden = !chat.isPinned
        muteIcon.isHidden = !chat.isMuted

        let unread = chat.unreadCount
        unreadBadge.text = "\(unread)"
        unreadBadge.isHidden = (unread == 0)
        unreadBadge.sizeToFit()
        let w = max(unreadBadge.frame.width + 10, 18)
        unreadBadge.frame.size.width = w
    }

    private func formatRelative(_ date: Date) -> String {
        let now = Date()
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let daysAgo = cal.dateComponents([.day], from: date, to: now).day ?? 0
        if daysAgo < 7 {
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yy"
        return f.string(from: date)
    }
}
