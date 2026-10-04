//
//  AvatarView.swift
//  TelegramLite
//
//  Reusable avatar component: shows remote image, or first-letter + color.
//

import UIKit

final class AvatarView: UIView {

    private let imageView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .clear
        layer.masksToBounds = true
        layer.cornerRadius = Theme.avatarSize / 2

        label.textColor = .white
        label.font = Theme.semiboldFont(20)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    func set(title: String, color: UIColor, url: String?) {
        if let urlStr = url, !urlStr.isEmpty, let url = URL(string: urlStr) {
            label.isHidden = true
            imageView.isHidden = false
            // Light remote-image loader — uses URLSession + memory cache only
            ImageLoader.shared.load(into: imageView, url: url)
        } else {
            imageView.image = nil
            imageView.isHidden = true
            label.isHidden = false
            label.text = title
            backgroundColor = color
        }
    }
}

/// Tiny image cache: 8MB memory cache, LRU eviction. No disk cache to keep
/// the app tiny and fast — re-fetching happens only when reloaded.
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private var inflight = [NSURL: [(UIImage?) -> Void]]()
    private let lock = NSLock()

    init() {
        cache.countLimit = 200
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    func load(into imageView: UIImageView, url: URL, placeholder: UIImage? = nil) {
        imageView.image = placeholder
        if let cached = cache.object(forKey: url as NSURL) {
            imageView.image = cached
            return
        }
        lock.lock()
        var list = inflight[url as NSURL] ?? []
        list.append { [weak imageView] img in
            DispatchQueue.main.async {
                imageView?.image = img
            }
        }
        inflight[url as NSURL] = list
        let alreadyLoading = list.count > 1
        lock.unlock()
        guard !alreadyLoading else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            var img: UIImage?
            if let d = data, let i = UIImage(data: d) {
                self.cache.setObject(i, forKey: url as NSURL,
                                     cost: Int(d.count))
                img = i
            }
            self.lock.lock()
            let callbacks = self.inflight.removeValue(forKey: url as NSURL)
            self.lock.unlock()
            callbacks?.forEach { $0(img) }
        }.resume()
    }
}
