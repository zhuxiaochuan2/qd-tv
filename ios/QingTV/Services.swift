import Foundation

// MARK: - 豆瓣（发现片名/海报/评分）

enum Douban {
    static func list(type: String, tag: String, start: Int) async -> [DoubanItem] {
        let t = tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tag
        let u = "https://movie.douban.com/j/search_subjects?type=\(type)&tag=\(t)&sort=recommend&page_limit=20&page_start=\(start)"
        guard let j = try? await Net.json(u, referer: "https://movie.douban.com/") else { return [] }
        let arr = (j["subjects"] as? [[String: Any]]) ?? []
        return arr.map {
            DoubanItem(id: "\($0["id"] ?? "")",
                       name: $0["title"] as? String ?? "",
                       pic: $0["cover"] as? String ?? "",
                       rate: $0["rate"] as? String ?? "")
        }
    }

    static func search(_ q: String) async -> [DoubanItem] {
        let e = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        guard let t = try? await Net.text("https://movie.douban.com/j/subject_suggest?q=\(e)",
                                          referer: "https://movie.douban.com/"),
              let d = t.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return [] }
        return arr.map {
            DoubanItem(id: "\($0["id"] ?? "")",
                       name: $0["title"] as? String ?? "",
                       pic: $0["img"] as? String ?? "",
                       rate: $0["year"] as? String ?? "")
        }
    }

    /// 去掉标点，拿去 cms 搜索
    static func keyword(_ title: String) -> String {
        var s = title
        if let r = s.range(of: "/") { s = String(s[..<r.lowerBound]) }
        let bad = CharacterSet(charactersIn: "[]（）()【】·:：!！?？,，.。~～-—/ ")
        return s.components(separatedBy: bad).joined()
    }
}

// MARK: - cms 站源


/// 豆瓣条目详情（简介 / 类型 / 地区 / 年份）
struct DoubanInfo {
    var intro: String = ""
    var genres: String = ""
    var year: String = ""
    var rate: String = ""
}

extension Douban {
    /// 用 rexxar 接口取详情，必须带 Referer，否则 418
    static func subject(_ id: String, kind: String = "movie") async -> DoubanInfo? {
        guard !id.isEmpty else { return nil }
        let url = "https://m.douban.com/rexxar/api/v2/\(kind)/\(id)"
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            var info = DoubanInfo()
            info.intro = (obj["intro"] as? String) ?? ""
            let genres = (obj["genres"] as? [String]) ?? []
            info.genres = genres.joined(separator: " / ")
            info.year = (obj["year"] as? String) ?? ""
            if let rating = obj["rating"] as? [String: Any], let v = rating["value"] as? Double, v > 0 {
                info.rate = String(format: "%.1f", v)
            }
            return info
        } catch { return nil }
    }
}

enum Cms {
    static let blockWords = ["youku", "qiyi", "qq", "mgtv", "bilibili", "letv", "sohu", "pptv",
                             "优酷", "爱奇艺", "腾讯", "芒果", "哔哩", "搜狐", "乐视"]

    static func base(_ api: String) -> String { api.hasSuffix("/") ? api : api + "/" }

    /// 搜索站点，返回「命中」而不是扁平的线路，方便做封面/片名匹配
    static func search(_ site: Site, kw: String) async -> [SearchHit] {
        let e = kw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? kw
        let u = base(site.api) + "?ac=videolist&wd=\(e)&pg=1"
        guard let j = try? await Net.json(u, timeout: 9) else { return [] }
        let list = (j["list"] as? [[String: Any]]) ?? []
        var hits: [SearchHit] = []
        for o in list.prefix(3) {
            let from = o["vod_play_from"] as? String ?? ""
            let urls = o["vod_play_url"] as? String ?? ""
            let plays = parsePlays(site: site.name, from: from, urls: urls)
            guard !plays.isEmpty else { continue }
            var pic = o["vod_pic"] as? String ?? ""
            if pic.hasPrefix("//") { pic = "https:" + pic }
            let rawDesc = (o["vod_content"] as? String) ?? (o["vod_blurb"] as? String) ?? ""
            let desc = rawDesc
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            hits.append(SearchHit(site: site.name,
                                  name: o["vod_name"] as? String ?? "",
                                  pic: pic,
                                  remark: o["vod_remarks"] as? String ?? "",
                                  content: String(desc.prefix(400)),
                                  plays: plays))
            if hits.count >= 3 { break }
        }
        return hits
    }

    static func parsePlays(site: String, from: String, urls: String) -> [PlayLine] {
        guard !urls.isEmpty else { return [] }
        let flags = from.isEmpty ? ["线路"] : from.components(separatedBy: "$$$")
        let groups = urls.components(separatedBy: "$$$")
        var out: [PlayLine] = []
        for (i, g) in groups.enumerated() {
            let name = i < flags.count && !flags[i].isEmpty ? flags[i] : "线路\(i + 1)"
            if blockWords.contains(where: { name.lowercased().contains($0) }) { continue }
            var eps: [Ep] = []
            for (k, seg) in g.components(separatedBy: "#").enumerated() {
                guard !seg.isEmpty else { continue }
                let parts = seg.components(separatedBy: "$")
                let nm = parts.count > 1 ? parts[0] : "第\(k + 1)集"
                let link = parts.count > 1 ? parts[1] : parts[0]
                if link.hasPrefix("http") { eps.append(Ep(name: nm, url: link)) }
            }
            if !eps.isEmpty { out.append(PlayLine(site: site, name: name, eps: eps)) }
        }
        return out
    }
}

// MARK: - TVBox 订阅（多仓 / 单仓）

enum TVBox {
    struct Result {
        var repos: [Repo] = []
        var sites: [Site] = []
        var error: String?
    }

    static func load(_ urlString: String) async -> Result {
        var r = Result()
        guard let t = await Net.anyText(urlString) else {
            r.error = "订阅拉不到（网络或地址问题）"
            return r
        }
        guard let i = t.firstIndex(of: "{"), let d = String(t[i...]).data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
            r.error = "订阅不是合法 JSON"
            return r
        }
        if let urls = j["urls"] as? [[String: Any]] {
            r.repos = urls.compactMap {
                guard let u = $0["url"] as? String, u.hasPrefix("http") else { return nil }
                return Repo(name: $0["name"] as? String ?? "仓", url: u)
            }
            if r.repos.isEmpty { r.error = "多仓里没有有效地址" }
            return r
        }
        if let sites = j["sites"] as? [[String: Any]] {
            var seen = Set<String>()
            let mapped: [Site] = sites.compactMap { s in
                guard let api = s["api"] as? String, api.hasPrefix("http") else { return nil }
                let type = s["type"] as? Int ?? 0
                let looksCms = api.contains("api.php") || api.contains("provide/vod") || api.contains(".php")
                guard type == 1 || looksCms else { return nil }
                let clean = api.components(separatedBy: "?").first ?? api
                if seen.contains(clean) { return nil }
                seen.insert(clean)
                var nm = (s["name"] as? String ?? "源")
                nm = String(nm.filter { $0.isLetter || $0.isNumber })
                return Site(name: String(nm.prefix(10)).isEmpty ? "源" : String(nm.prefix(10)), api: clean)
            }
            r.sites = mapped
            if mapped.isEmpty { r.error = "这个仓里没有可直连的 cms 源（全是 spider 源）" }
            return r
        }
        r.error = "既没有 urls 也没有 sites 字段"
        return r
    }
}

// MARK: - 播放页 → m3u8

enum Resolver {
    static func m3u8(from pageUrl: String) async -> String? {
        if pageUrl.contains(".m3u8") { return pageUrl }
        guard let html = try? await Net.text(pageUrl, timeout: 15) else { return nil }
        let patterns = [
            "https?://[^\"'\\s\\\\<>]+?\\.m3u8[^\"'\\s\\\\<>]*",
            "[\"']([^\"']{1,300}?\\.m3u8[^\"']*)[\"']",
        ]
        for (idx, p) in patterns.enumerated() {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            let ns = html as NSString
            if let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
                let hit = m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : ns.substring(with: m.range)
                if idx == 0 { return hit }
                return absolutize(pageUrl, hit)
            }
        }
        return nil
    }

    static func absolutize(_ base: String, _ p: String) -> String? {
        if p.hasPrefix("http") { return p }
        guard let u = URLComponents(string: base) else { return nil }
        let origin = "\(u.scheme ?? "https")://\(u.host ?? "")" + (u.port.map { ":\($0)" } ?? "")
        if p.hasPrefix("//") { return "\(u.scheme ?? "https"):\(p)" }
        if p.hasPrefix("/") { return origin + p }
        var path = u.path
        if let idx = path.lastIndex(of: "/") { path = String(path[...idx]) } else { path = "/" }
        return origin + path + p
    }

    /// 给 AVPlayer 带上 Referer，防盗链源也能播
    static func headers(for pageUrl: String) -> [String: String] {
        guard let u = URLComponents(string: pageUrl) else { return [:] }
        let origin = "\(u.scheme ?? "https")://\(u.host ?? "")" + (u.port.map { ":\($0)" } ?? "") + "/"
        return [
            "Referer": origin,
            "User-Agent": Net.ua,
        ]
    }
}

// MARK: - 直播 m3u

enum Live {
    static func channels(from urls: [String]) async -> [Channel] {
        var out: [Channel] = []
        for u in urls {
            guard let t = try? await Net.text(u, timeout: 12) else { continue }
            var last: String?
            for raw in t.components(separatedBy: "\n") {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }
                if line.hasPrefix("#EXTINF") {
                    if let c = line.lastIndex(of: ",") {
                        last = String(line[line.index(after: c)...]).trimmingCharacters(in: .whitespaces)
                    } else { last = "频道" }
                } else if line.hasPrefix("#") {
                    continue
                } else if line.hasPrefix("http") || line.hasPrefix("rtmp") || line.hasPrefix("rtp") {
                    out.append(Channel(name: last ?? "频道\(out.count + 1)", url: line))
                    last = nil
                }
            }
            if out.count > 600 { break }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.url).inserted }
    }
}
