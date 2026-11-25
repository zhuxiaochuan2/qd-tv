import SwiftUI
import UIKit

/// 图片缓存（内存）
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func get(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func put(_ key: String, _ img: UIImage) { cache.setObject(img, forKey: key as NSString) }
}

/// 带 Referer 的图片加载器。
/// 豆瓣图床不带 Referer 会直接返回 418，AsyncImage 又没法加请求头，
/// 所以必须自己用 URLSession 拉。
struct NetImage: View {
    let url: String
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.white.opacity(0.06)
                if failed {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundColor(Color.white.opacity(0.25))
                } else {
                    ProgressView().scaleEffect(0.6).tint(.gray)
                }
            }
        }
        .clipped()
        .task(id: url) { await load() }
    }

    private func load() async {
        guard !url.isEmpty else { failed = true; return }
        var s = url
        if s.hasPrefix("//") { s = "https:" + s }
        guard let u = URL(string: s) else { failed = true; return }

        if let cached = ImageCache.shared.get(s) {
            image = cached
            return
        }

        var req = URLRequest(url: u, timeoutInterval: 20)
        req.setValue(Net.ua, forHTTPHeaderField: "User-Agent")
        req.setValue("image/*", forHTTPHeaderField: "Accept")
        // 关键：豆瓣图床没这个头就是 418
        req.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                failed = true
                return
            }
            if let img = UIImage(data: data) {
                ImageCache.shared.put(s, img)
                image = img
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }
}
