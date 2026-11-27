import Foundation

/// HLS 分段下载：拉 m3u8 → 逐段下载 → 拼成一个 .mp4（实际是 TS 流，播放器能直接吃）
final class Downloader {
    enum DErr: Error { case badPlaylist, encrypted, writeFail, empty }

    static let shared = Downloader()

    /// 下载目录
    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("影匣下载", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    /// 返回保存后的文件名
    func download(m3u8: String,
                  headers: [String: String],
                  name: String,
                  progress: @escaping (Double) -> Void) async throws -> String {
        guard let u = URL(string: m3u8) else { throw DErr.badPlaylist }

        var req = URLRequest(url: u, timeoutInterval: 30)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let text = String(data: data, encoding: .utf8) else { throw DErr.badPlaylist }

        if text.contains("#EXT-X-KEY") && !text.contains("METHOD=NONE") {
            throw DErr.encrypted          // 加密流不搞，直接告诉用户
        }

        // 主播放列表（多码率）→ 取第一个子列表
        if text.contains("#EXT-X-STREAM-INF") {
            let lines = text.components(separatedBy: .newlines)
            if let idx = lines.firstIndex(where: { $0.contains("#EXT-X-STREAM-INF") }) {
                for l in lines[(idx + 1)...] {
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty || t.hasPrefix("#") { continue }
                    if let sub = URL(string: t, relativeTo: u)?.absoluteString {
                        return try await download(m3u8: sub, headers: headers, name: name, progress: progress)
                    }
                }
            }
            throw DErr.badPlaylist
        }

        // 媒体列表：收集所有分片
        var segs: [URL] = []
        for l in text.components(separatedBy: .newlines) {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            if let su = URL(string: t, relativeTo: u) { segs.append(su) }
        }
        guard !segs.isEmpty else { throw DErr.empty }

        // 先把首尾分片下载顺序拼起来，中间并发太难保证顺序，这里就走顺序（稳定优先）
        let fileName = sanitize(name) + ".mp4"
        let outURL = Downloader.dir.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        guard let fh = try? FileHandle(forWritingTo: outURL) else { throw DErr.writeFail }

        for (i, su) in segs.enumerated() {
            var sreq = URLRequest(url: su, timeoutInterval: 30)
            for (k, v) in headers { sreq.setValue(v, forHTTPHeaderField: k) }
            do {
                let (segData, _) = try await URLSession.shared.data(for: sreq)
                fh.write(segData)
            } catch {
                // 单段失败跳过，别整个下载作废
            }
            let done = Double(i + 1) / Double(segs.count)
            await MainActor.run { progress(done) }
        }
        try? fh.close()
        return fileName
    }

    func localURL(_ fileName: String) -> URL {
        Downloader.dir.appendingPathComponent(fileName)
    }

    func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: localURL(fileName))
    }

    func size(_ fileName: String) -> Int64 {
        let p = localURL(fileName).path
        let attrs = try? FileManager.default.attributesOfItem(atPath: p)
        return (attrs?[.size] as? Int64) ?? 0
    }

    private func sanitize(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return s.components(separatedBy: bad).joined(separator: "_")
    }
}
