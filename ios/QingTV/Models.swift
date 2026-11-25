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

/// 一次 cms 搜索的命中：带封面、备注，用来做「封面匹配」和「片名核对」
struct SearchHit: Identifiable, Hashable {
    let id = UUID()
    let site: String
    let name: String
    let pic: String
    let remark: String
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

final class Store: ObservableObject {
    @Published var sites: [Site] = Defaults.sites
    @Published var lives: [String] = Defaults.lives
    @Published var subscription: String = Defaults.subscription

    private let sitesKey = "qd_sites"
    private let livesKey = "qd_lives"
    private let subKey = "qd_sub"

    init() { load() }

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
}
