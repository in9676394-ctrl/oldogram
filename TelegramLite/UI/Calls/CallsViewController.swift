//
//  CallsViewController.swift
//  TelegramLite
//
//  Recent calls list. Tapping → call back.
//

import UIKit

final class CallsViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var calls: [(userId: Int64, name: String, date: Date, isIncoming: Bool, missed: Bool)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg
        title = "Calls"
        if #available(iOS 11.0, *) { navigationController?.navigationBar.prefersLargeTitles = true }
        setupTable()
        loadInitial()
        TDLibManager.shared.subscribe("updateNewCallLogRow") { [weak self] _ in
            DispatchQueue.main.async { self?.loadInitial() }
        }
    }

    private func setupTable() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.bg
        tableView.separatorColor = Theme.separator
        tableView.rowHeight = 64
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CallCell")
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func loadInitial() {
        // TDLib list call logs
        TDLibManager.shared.request(function: "searchCallMessages",
                                   parameters: ["from_message_id": 0, "limit": 100, "only_missed": false]) { resp in
            // Parse `messages` array
            if let arr = resp.raw["messages"] as? [[String: Any]] {
                self.calls = arr.compactMap { msg in
                    let isOutgoing = msg["is_outgoing"] as? Bool ?? false
                    let isMissed = (msg["is_outgoing"] == nil) && (msg["interaction_info"] as? [String: Any]) != nil
                    let dateInt = msg["date"] as? Int ?? 0
                    let date = Date(timeIntervalSince1970: TimeInterval(dateInt))
                    let content = msg["content"] as? [String: Any] ?? [:]
                    let duration = ((content["duration"] as? Int) ?? 0)
                    let userId = ((content["user_id"] as? Int64) ?? 0)
                    let name = msg["sender_name"] as? String ?? "Unknown"
                    _ = duration
                    return (userId, name, date, !isOutgoing, isMissed)
                }
                DispatchQueue.main.async { self.tableView.reloadData() }
            }
        }
    }
}

extension CallsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return calls.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CallCell", for: indexPath)
        let c = calls[indexPath.row]
        let icon = c.missed ? "phone.down.fill"
                  : (c.isIncoming ? "phone.arrow.down.left" : "phone.arrow.up.right")
        let iconColor = c.missed ? Theme.destructive : Theme.accent
        let att = NSMutableAttributedString()
        let bold = [NSAttributedString.Key.font: Theme.semiboldFont(16),
                    NSAttributedString.Key.foregroundColor: c.missed ? Theme.destructive : Theme.text]
        att.append(NSAttributedString(string: c.name, attributes: bold))
        let secondary = [NSAttributedString.Key.font: Theme.regularFont(13),
                         NSAttributedString.Key.foregroundColor: Theme.textSecondary]
        att.append(NSAttributedString(string: "\n\(formatDate(c.date))", attributes: secondary))

        cell.textLabel?.attributedText = att
        cell.textLabel?.numberOfLines = 2
        cell.imageView?.image = UIImage(systemName: icon)?
            .withTintColor(iconColor, renderingMode: .alwaysOriginal)
        cell.backgroundColor = Theme.cellBg
        cell.accessoryType = .detailButton
        cell.tintColor = Theme.accent
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let c = calls[indexPath.row]
        CallManager.shared.startCall(userId: c.userId, displayName: c.name)
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(d) {
            f.dateFormat = "HH:mm"
            return "Today " + f.string(from: d)
        }
        f.dateFormat = "dd.MM.yy HH:mm"
        return f.string(from: d)
    }
}
