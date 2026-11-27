import Foundation

struct DoubanItem: Identifiable, Hashable {
    let id: String
    let name: String
    let pic: String
    let rate: String
}

struct Ep: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: String
}

struct PlayLine: Identifiable, Hashable {
    let id = UUID()
    let site: String
    let name: String
    let eps: [Ep]
}

/// 一次 cms 搜索的命中：带封面、简介、备注
struct SearchHit: Identifiable, Hashable {
    let id = UUID()
    let site: String
    let name: String
    let pic: String
    let remark: String
    let content: String
    let plays: [PlayLine]
}

struct Site: Identifiable, Hashable, Codable {
    var id: String { api }
    let name: String
    let api: String
}

struct Channel: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: String
}

struct Repo: Identifiable, Hashable {
    var id: String { url }
    let name: String
    let url: String
}

// MARK: - 观看历史 / 收藏

struct HistoryItem: Codable, Identifiable, Hashable {
    var id: String { title }          // 一部片一条
    let title: String
    let pic: String
    var site: String
    var line: String
    var epName: String
    var epURL: String
    var position: Double
    var duration: Double
    var updatedAt: Double

    var progress: Double {
        guard duration > 1 else { return 0 }
        return min(1, max(0, position / duration))
    }
}

struct FavItem: Codable, Identifiable, Hashable {
    var id: String { title }
    let title: String
    let pic: String
    let rate: String
    let addedAt: Double
}

/// 默认 cms 源（2026-11 实测能搜到片的）
enum Defaults {
    static let sites: [Site] = [
        Site(name: "量子", api: "https://lzizy1.com/api.php/provide/vod/"),
        Site(name: "非凡", api: "https://api.ffzyapi.com/api.php/provide/vod/"),
        Site(name: "红牛", api: "https://www.hongniuzy2.com/api.php/provide/vod/"),
        Site(name: "光速", api: "https://api.guangsuapi.com/api.php/provide/vod/"),
        Site(name: "建安", api: "http://154.219.117.232:9981/jacloudapi.php/provide/vod"),
        Site(name: "百度", api: "https://api.apibdzy.com/api.php/provide/vod/"),
        Site(name: "豪华", api: "https://hhzyapi.com/api.php/provide/vod/"),
        Site(name: "闪电", api: "https://sdzyapi.com/api.php/provide/vod/"),
    ]

    static let lives: [String] = [
        "https://live.zbds.top/tv/iptv4.m3u",
        "https://live.zbds.top/tv/iptv6.m3u",
        "https://www.iyouhun.com/tv/zb",
    ]

    static let subscription = "https://raw.githubusercontent.com/Lightconer/tvbox-ysc-config/main/output/多仓订阅.json"
}

struct DownloadItem: Codable, Identifiable, Hashable {
    var id: String { fileName }
    let fileName: String
    let title: String
    let pic: String
    let size: Int64
    let date: Date
}

final class Store: ObservableObject {
    @Published var sites: [Site] = Defaults.sites
    @Published var lives: [String] = Defaults.lives
    @Published var subscription: String = Defaults.subscription

    // 历史 / 收藏 / 搜索历史
    @Published var history: [HistoryItem] = []
    @Published var favorites: [FavItem] = []
    @Published var searches: [String] = []
    @Published var downloads: [DownloadItem] = []

    private let sitesKey = "qd_sites"
    private let livesKey = "qd_lives"
    private let subKey = "qd_sub"
    private let historyKey = "qd_history"
    private let favKey = "qd_fav"
    private let searchKey = "qd_search"
    private let downloadKey = "qd_downloads"

    // 儿童模式
    @Published var kidsMode: Bool = false
    @Published var kidsPwd: String = "1234"
    private let kidsKey = "qd_kids_mode"
    private let pwdKey = "qd_kids_pwd"

    init() {
        load()
        loadKids()
        loadHistory()
        loadDownloads()
    }

    // MARK: - 基础配置

    func load() {
        if let d = UserDefaults.standard.data(forKey: sitesKey),
           let v = try? JSONDecoder().decode([Site].self, from: d), !v.isEmpty { sites = v }
        if let v = UserDefaults.standard.stringArray(forKey: livesKey), !v.isEmpty { lives = v }
        if let s = UserDefaults.standard.string(forKey: subKey), !s.isEmpty { subscription = s }
    }

    func save() {
        if let d = try? JSONEncoder().encode(sites) { UserDefaults.standard.set(d, forKey: sitesKey) }
        UserDefaults.standard.set(lives, forKey: livesKey)
        UserDefaults.standard.set(subscription, forKey: subKey)
    }

    func apply(_ newSites: [Site]) {
        guard !newSites.isEmpty else { return }
        sites = newSites
        save()
    }

    // MARK: - 儿童模式

    func loadKids() {
        kidsMode = UserDefaults.standard.bool(forKey: kidsKey)
        if let p = UserDefaults.standard.string(forKey: pwdKey), !p.isEmpty { kidsPwd = p }
    }

    func saveKids() {
        UserDefaults.standard.set(kidsMode, forKey: kidsKey)
        UserDefaults.standard.set(kidsPwd, forKey: pwdKey)
    }

    func setKidsPwd(_ p: String) {
        guard !p.isEmpty else { return }
        kidsPwd = p
        saveKids()
    }

    func enterKidsMode() {
        kidsMode = true
        saveKids()
    }

    @discardableResult
    func exitKidsMode(pwd: String) -> Bool {
        if pwd == kidsPwd {
            kidsMode = false
            saveKids()
            return true
        }
        return false
    }

    // MARK: - 历史 / 收藏

    private func loadHistory() {
        if let d = UserDefaults.standard.data(forKey: historyKey),
           let v = try? JSONDecoder().decode([HistoryItem].self, from: d) {
            history = v.sorted { $0.updatedAt > $1.updatedAt }
        }
        if let d = UserDefaults.standard.data(forKey: favKey),
           let v = try? JSONDecoder().decode([FavItem].self, from: d) {
            favorites = v.sorted { $0.addedAt > $1.addedAt }
        }
        if let v = UserDefaults.standard.stringArray(forKey: searchKey) { searches = v }
    }

    private func saveHistory() {
        if let d = try? JSONEncoder().encode(history) { UserDefaults.standard.set(d, forKey: historyKey) }
        if let d = try? JSONEncoder().encode(favorites) { UserDefaults.standard.set(d, forKey: favKey) }
        UserDefaults.standard.set(searches, forKey: searchKey)
    }

    /// 记录/更新播放进度（同一部片只保留一条）
    func recordProgress(title: String, pic: String, site: String, line: String,
                        epName: String, epURL: String, position: Double, duration: Double) {
        guard !title.isEmpty, !epURL.isEmpty else { return }
        var item = HistoryItem(title: title, pic: pic, site: site, line: line,
                               epName: epName, epURL: epURL,
                               position: position, duration: duration,
                               updatedAt: Date().timeIntervalSince1970)
        if let idx = history.firstIndex(where: { $0.title == title }) {
            // 位置以新的为准，但别把更长剧集的进度冲掉
            if duration <= 0, history[idx].duration > 0 {
                item.position = history[idx].position
                item.duration = history[idx].duration
            }
            history.remove(at: idx)
        }
        history.insert(item, at: 0)
        if history.count > 40 { history = Array(history.prefix(40)) }
        saveHistory()
    }

    func historyItem(for title: String) -> HistoryItem? {
        history.first { $0.title == title }
    }

    func removeHistory(title: String) {
        history.removeAll { $0.title == title }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func isFav(_ title: String) -> Bool {
        favorites.contains { $0.title == title }
    }

    func toggleFav(title: String, pic: String, rate: String) {
        if let idx = favorites.firstIndex(where: { $0.title == title }) {
            favorites.remove(at: idx)
        } else {
            favorites.insert(FavItem(title: title, pic: pic, rate: rate,
                                     addedAt: Date().timeIntervalSince1970), at: 0)
        }
        saveHistory()
    }

    func pushSearch(_ kw: String) {
        let k = kw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        searches.removeAll { $0 == k }
        searches.insert(k, at: 0)
        if searches.count > 12 { searches = Array(searches.prefix(12)) }
        saveHistory()
    }

    func clearSearches() {
        searches.removeAll()
        saveHistory()
    }
}


/// 点海报要全屏播的目标
struct PlayTarget: Identifiable {
    let id = UUID()
    let title: String
    let pic: String
    let rate: String
    var doubanID: String = ""
    var kind: String = "movie"
}


/// 单集全屏播放目标
struct PlayVideo: Identifiable {
    let id = UUID()
    let urlString: String
    let title: String
    let pic: String
    let site: String
    let line: String
    let epName: String
    let resumeAt: Double
}


extension Store {
    func loadDownloads() {
        if let d = UserDefaults.standard.data(forKey: downloadKey),
           let v = try? JSONDecoder().decode([DownloadItem].self, from: d) {
            downloads = v
        }
    }

    func addDownload(fileName: String, title: String, pic: String, size: Int64) {
        downloads.removeAll { $0.fileName == fileName }
        downloads.insert(DownloadItem(fileName: fileName, title: title, pic: pic, size: size, date: Date()),
                         at: 0)
        if let d = try? JSONEncoder().encode(downloads) {
            UserDefaults.standard.set(d, forKey: downloadKey)
        }
    }

    func removeDownload(_ id: String) {
        downloads.removeAll { $0.id == id }
        if let d = try? JSONEncoder().encode(downloads) {
            UserDefaults.standard.set(d, forKey: downloadKey)
        }
    }
}
