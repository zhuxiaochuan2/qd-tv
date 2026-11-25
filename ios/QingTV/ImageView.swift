import SwiftUI
import UIKit

/// 图片缓存（内存）
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.countLimit = 300 }

    func get(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func put(_ key: String, _ img: UIImage) { cache.setObject(img, forKey: key as NSString) }

    /// 带 Referer 下载，失败重试一次
    func download(_ url: URL) async -> UIImage? {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(Net.ua, forHTTPHeaderField: "User-Agent")
        req.setValue("image/*", forHTTPHeaderField: "Accept")
        // 关键：豆瓣图床没这个头就是 418
        req.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")

        for attempt in 0..<2 {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                    if attempt == 0 {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        continue
                    }
                    return nil
                }
                return UIImage(data: data)
            } catch {
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    continue
                }
                return nil
            }
        }
        return nil
    }
}

/// 带 Referer 的图片加载器（AsyncImage 加不了请求头）
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
                    ProgressView().scaleEffect(0.55).tint(Color.white.opacity(0.35))
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
        if let img = await ImageCache.shared.download(u) {
            ImageCache.shared.put(s, img)
            await MainActor.run { image = img }
        } else {
            await MainActor.run { failed = true }
        }
    }
}
