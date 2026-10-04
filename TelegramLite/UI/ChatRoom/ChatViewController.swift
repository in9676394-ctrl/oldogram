//
//  ChatViewController.swift
//  TelegramLite
//
//  Open chat: messages list, send text / photo / gif / sticker / voice.
//  Premium badge shown if peer is premium. Verified checkmark shown.
//  Avatar + title in nav bar. Calls button in nav bar.
//

import UIKit
import Photos

final class ChatViewController: UIViewController {

    let chatId: Int64
    private var chat: TGChat?

    // MARK: - Views

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputBar = MessageInputView()
    private var inputBarBottom: NSLayoutConstraint!

    // MARK: - Messages

    private var messages: [TGMessage] = []

    // MARK: - Init

    init(chatId: Int64) {
        self.chatId = chatId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg
        setupNav()
        setupTable()
        setupInputBar()
        setupKeyboardHandling()
        loadChatInfo()
        loadInitialMessages()
        NotificationCenter.default.addObserver(self, selector: #selector(handleMessagesUpdated),
                                              name: .tgMessagesUpdated, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Nav

    private func setupNav() {
        if #available(iOS 11.0, *) { navigationController?.navigationBar.prefersLargeTitles = false }
        let callBtn = UIBarButtonItem(image: UIImage(systemName: "phone")?
                                        .withTintColor(Theme.accent, renderingMode: .alwaysOriginal),
                                      style: .plain, target: self, action: #selector(callTapped))
        navigationItem.rightBarButtonItem = callBtn
    }

    // MARK: - Table

    private func setupTable() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.bg
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 60
        tableView.rowHeight = UITableView.automaticDimension
        tableView.allowsSelection = false
        tableView.keyboardDismissMode = .interactive
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseId)
        tableView.transform = CGAffineTransform(scaleX: 1, y: -1) // reverse — newest at bottom

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupInputBar() {
        view.addSubview(inputBar)
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.delegate = self
        inputBarBottom = inputBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        NSLayoutConstraint.activate([
            inputBar.topAnchor.constraint(equalTo: tableView.bottomAnchor),
            inputBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }

    // MARK: - Keyboard handling

    private func setupKeyboardHandling() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                              name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                                              name: UIResponder.keyboardWillHideNotification, object: nil)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)
    }

    @objc private func keyboardWillChange(_ n: Notification) {
        guard let frame = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        let height = view.convert(frame, from: nil).intersection(view.bounds).height
        inputBarBottom.constant = -height
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }
    @objc private func keyboardWillHide(_ n: Notification) {
        inputBarBottom.constant = 0
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - Load

    private func loadChatInfo() {
        // Try to find chat in store; otherwise query TDLib
        if let c = ChatStore.shared.chat(byId: chatId) {
            chat = c
            updateNavTitle()
            return
        }
        TDLibManager.shared.request(function: "getChat",
                                   parameters: ["chat_id": chatId]) { resp in
            if let c = resp.raw as? [String: Any] {
                let title = c["title"] as? String ?? "Chat"
                DispatchQueue.main.async {
                    self.chat = TGChat(id: self.chatId, title: title, type: .private_,
                                       lastMessageText: "", lastMessageDate: Date(),
                                       unreadCount: 0, lastReadInboxMessageId: 0,
                                       avatarColorIndex: Int(self.chatId % 8),
                                       isVerified: false, isPremium: false,
                                       isPinned: false, isMuted: false,
                                       photoURL: nil, draftText: nil)
                    self.updateNavTitle()
                }
            }
        }
    }

    private func updateNavTitle() {
        guard let c = chat else { return }
        let titleLbl = UILabel()
        titleLbl.text = c.title
        titleLbl.font = Theme.semiboldFont(16)
        titleLbl.textColor = Theme.text

        let subtitleLbl = UILabel()
        subtitleLbl.text = c.isPremium ? "Premium user" : "online"
        subtitleLbl.font = Theme.regularFont(11)
        subtitleLbl.textColor = c.isPremium ? Theme.premium : Theme.online
        subtitleLbl.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [titleLbl, subtitleLbl])
        stack.axis = .vertical
        stack.alignment = .center
        stack.frame = CGRect(x: 0, y: 0, width: 220, height: 36)
        navigationItem.titleView = stack

        if c.isVerified {
            let v = UIImageView(image: UIImage(systemName: "checkmark.seal.fill")?
                .withTintColor(Theme.accent, renderingMode: .alwaysOriginal))
            stack.addArrangedSubview(v)
        }
        if c.isPremium {
            let p = UIImageView(image: UIImage(systemName: "crown.fill")?
                .withTintColor(Theme.premium, renderingMode: .alwaysOriginal))
            stack.addArrangedSubview(p)
        }
    }

    private func loadInitialMessages() {
        MessageSender.shared.loadHistory(chatId: chatId, fromMessageId: 0, limit: 50) { [weak self] in
            self?.reloadFromStore()
        }
    }

    @objc private func handleMessagesUpdated(_ n: Notification) {
        guard let id = n.object as? Int64, id == chatId else { return }
        reloadFromStore()
    }

    private func reloadFromStore() {
        messages = ChatStore.shared.messages(for: chatId)
        tableView.reloadData()
        if let last = messages.last {
            MessageSender.shared.markRead(chatId: chatId, lastMessageId: last.id)
        }
    }

    // MARK: - Actions

    @objc private func callTapped() {
        guard let peerId = chat?.id else { return }
        // For private chats peerId == chatId; for groups/supergroups we need
        // to extract the user_id (not implemented for group voice here).
        CallManager.shared.startCall(userId: peerId, displayName: chat?.title ?? "")
    }
}

// MARK: - Data source

extension ChatViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseId,
                                                 for: indexPath) as! MessageCell
        let msg = messages[indexPath.row]
        cell.configure(with: msg)
        return cell
    }

    // For table rotated 180, "top" of view = bottom of data — so when user
    // scrolls to the visible top, they want to load older messages.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y < 100 && !messages.isEmpty {
            // Load older
            let oldestId = messages.first?.id ?? 0
            MessageSender.shared.loadHistory(chatId: chatId, fromMessageId: oldestId, limit: 50) { [weak self] in
                self?.reloadFromStore()
            }
        }
    }
}

// MARK: - Input delegate

extension ChatViewController: MessageInputViewDelegate {

    func didSendText(_ text: String) {
        MessageSender.shared.sendText(chatId: chatId, text: text)
        inputBar.clear()
    }

    func didTapPhotoPicker() {
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .denied || status == .restricted {
            presentPermissionDeniedAlert(kind: "Photos")
            return
        }
        PHPhotoLibrary.requestAuthorization { _ in
            DispatchQueue.main.async { self.showPhotoPicker() }
        }
    }

    func didTapGIFPicker() {
        // Simple GIF picker — open URL prompt for now
        // (Real GIF library needs Giphy API key; that's outside scope here.)
        let alert = UIAlertController(title: "Send GIF",
                                      message: "Paste a GIF URL (https://.../something.gif)",
                                      preferredStyle: .alert)
        alert.addTextField { tf in tf.placeholder = "https://" }
        alert.addAction(UIAlertAction(title: "Send", style: .default) { _ in
            if let urlStr = alert.textFields?.first?.text, let url = URL(string: urlStr) {
                MessageSender.shared.sendGIF(chatId: self.chatId, gifURL: url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    func didTapEmojiPicker() {
        // Quick emoji — open a system emoji picker-ish alert
        let alert = UIAlertController(title: "Send Emoji",
                                      message: nil, preferredStyle: .actionSheet)
        let emojis = ["😀","😂","🥰","😎","😭","😡","👍","👎","🙏","🔥","🎉","💯","❤️","💜","💙","🖤","🤍"]
        for e in emojis {
            alert.addAction(UIAlertAction(title: e, style: .default) { _ in
                MessageSender.shared.sendText(chatId: self.chatId, text: e)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    func didRecordVoice(url: URL, duration: Int) {
        MessageSender.shared.sendVoice(chatId: chatId, audioPath: url.path, duration: duration)
    }

    private func showPhotoPicker() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentPermissionDeniedAlert(kind: String) {
        let alert = UIAlertController(title: "\(kind) Access Denied",
                                      message: "Open Settings to grant access.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                              didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        if let image = info[.originalImage] as? UIImage {
            MessageSender.shared.sendPhoto(chatId: chatId, image: image)
        }
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
