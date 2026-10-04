//
//  DebugLogViewController.swift
//  TelegramLite
//
//  Shows the TDLib log buffer so the user can debug auth issues
//  without a Mac console. Reachable from Settings → Debug → Debug Log.
//

import UIKit

final class DebugLogViewController: UIViewController {

    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg
        title = "Debug Log"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Copy",
            style: .plain,
            target: self,
            action: #selector(copyLog)
        )

        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = Theme.text
        textView.backgroundColor = Theme.bg
        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.automaticallyAdjustsScrollIndicatorInsets = true
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
        ])
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    private func refresh() {
        let lines = TDLibManager.logLines
        let text = lines.joined(separator: "\n")
        textView.text = text.isEmpty ? "(no log lines yet)" : text
        // Scroll to bottom — newest entries at the bottom.
        let bottom = NSMakeRange(textView.text.utf16.count - 1, 1)
        if bottom.location > 0 {
            textView.scrollRangeToVisible(bottom)
        }
    }

    @objc private func copyLog() {
        UIPasteboard.general.string = textView.text
        let alert = UIAlertController(title: "Copied",
                                      message: "Debug log copied to clipboard. You can paste it into Telegram Saved Messages or a chat with yourself to share with the developer.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
